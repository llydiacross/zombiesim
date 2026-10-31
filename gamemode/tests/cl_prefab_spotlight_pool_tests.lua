return function(createPool)
    local suite = ZM_TestHarness.NewSuite()

    local function fixture()
        local state = { created = {}, events = {}, missing = false, fail = false }
        local api = {
            IsValid = function(value) return value and value.valid end,
            IsVector = function() return false end, IsAngle = function() return false end,
            Vector = function(x, y, z) return { x = x, y = y, z = z } end,
            Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            Color = function(r, g, b) return { r = r, g = g, b = b } end,
            Material = function()
                return { IsError = function() return state.missing end,
                    GetTexture = function() return { Width = function() return 64 end, Height = function() return 64 end } end }
            end,
            ProjectedTexture = function()
                if state.fail then return nil end
                local light = { valid = true, updates = 0, number = #state.created + 1 }
                for _, name in ipairs({ "SetTexture", "SetOrthographic", "SetNearZ", "SetPos", "SetAngles",
                    "SetColor", "SetBrightness", "SetFOV", "SetFarZ", "SetEnableShadows" }) do
                    light[name] = function(self, ...)
                        self[name .. "Value"] = { ... }
                        if name == "SetEnableShadows" then
                            state.events[#state.events + 1] = { self.number, (...) }
                        end
                    end
                end
                function light:Update() self.updates = self.updates + 1 end
                function light:Remove() self.valid = false end
                function light:GetPos() return self.SetPosValue[1] end
                function light:GetAngles() return self.SetAnglesValue[1] end
                function light:GetColor() return self.SetColorValue[1] end
                function light:GetEnableShadows() return self.SetEnableShadowsValue[1] end
                function light:GetBrightness() return self.SetBrightnessValue[1] end
                function light:GetHorizontalFOV() return self.SetFOVValue[1] end
                function light:GetFarZ() return self.SetFarZValue[1] end
                state.created[#state.created + 1] = light
                return light
            end
        }
        local function candidate(id, x)
            return { id = id, position = { x = x, y = 0, z = 0 }, angles = { p = 40, y = 45, r = 0 },
                color = { r = 255, g = 235, b = 200 }, brightness = 6, fov = 60, range = 512 }
        end
        return state, createPool(api), candidate
    end

    suite:Add("nearest eight are deterministic and only the nearest casts shadows", function(check)
        local state, pool, candidate = fixture()
        local lights = {}
        for index = 10, 1, -1 do lights[#lights + 1] = candidate(string.format("%02d", index), index) end
        check(pool:Reconcile({ x = 0, y = 0, z = 0 }, lights, false), "valid candidates reconcile")
        local status = pool:Status()
        check(status.active == 8 and status.shadowed == 1 and #state.created == 8
            and status.projectors[1].shadowEnabled and status.projectors[1].updates == 1,
            "eight projectors and one shadow, with engine state reported")
        check(pool.States["01"].shadow and pool.States["08"] and not pool.States["09"],
            "nearest candidates are selected regardless of input order")
        check(pool.States["01"].light.SetBrightnessValue[1] == 6 and pool.States["01"].light.SetNearZValue[1] == 8,
            "authored brightness and nonzero near plane reach the projector")
        pool:Clear()
        check(pool:Status().active == 0 and not state.created[1].valid, "cleanup removes owned projectors")
    end)

    suite:Add("ties and changing nearest light hand off shadows without overlap", function(check)
        local state, pool, candidate = fixture()
        local lights = { candidate("b", 1), candidate("a", -1) }
        check(pool:Reconcile({ x = 0, y = 0, z = 0 }, lights, false), "equal distances reconcile")
        check(pool.States.a.shadow and not pool.States.b.shadow, "stable ID breaks equal-distance ties")
        state.events = {}
        check(pool:Reconcile({ x = 2, y = 0, z = 0 }, lights, false), "moving camera changes nearest")
        check(#state.events == 2 and state.events[1][2] == false and state.events[2][2] == true,
            "previous shadow is disabled before the new one is enabled")
        check(pool.States.b.shadow and not pool.States.a.shadow and pool:Status().shadowed == 1,
            "only the new nearest is shadowed")
    end)

    suite:Add("mutated authored settings and scene refresh update existing projectors", function(check)
        local _, pool, candidate = fixture()
        local light = candidate("a", 1)
        check(pool:Reconcile({ x = 0, y = 0, z = 0 }, { light }, false), "initial light reconciles")
        local projector = pool.States.a.light
        check(projector.updates == 1, "initial settings are applied")
        pool:Reconcile({ x = 0, y = 0, z = 0 }, { light }, false)
        check(projector.updates == 1, "unchanged light does not update unnecessarily")
        light.position.x, light.angles.y, light.color.g = 7, 90, 100
        light.brightness, light.fov, light.range = 2, 45, 600
        pool:Reconcile({ x = 0, y = 0, z = 0 }, { light }, false)
        check(projector.updates == 2 and projector.SetPosValue[1].x == 7
            and projector.SetAnglesValue[1].y == 90 and projector.SetColorValue[1].g == 100
            and projector.SetBrightnessValue[1] == 2 and projector.SetFOVValue[1] == 45
            and projector.SetFarZValue[1] == 600, "in-place changes are detected and applied")
        pool:Reconcile({ x = 0, y = 0, z = 0 }, { light }, true)
        check(projector.updates == 3, "caller can refresh after scene changes")
    end)

    suite:Add("replacement and invalid input remove old projectors explicitly", function(check)
        local state, pool, candidate = fixture()
        local camera = { x = 0, y = 0, z = 0 }
        local lights = {}
        for index = 1, 9 do lights[index] = candidate(tostring(index), index) end
        pool:Reconcile(camera, lights, false)
        local old = pool.States["1"].light
        camera.x = 10
        check(pool:Reconcile(camera, lights, false), "changed candidate set reconciles")
        check(not old.valid and pool.States["9"] and pool:Status().active == 8,
            "outgoing projector is removed before its replacement")
        lights[2].id = lights[1].id
        local ok, problem = pool:Reconcile(camera, lights, false)
        check(not ok and type(problem) == "string" and pool:Status().active == 0,
            "duplicate IDs report an error and clear stale lights")
        check(not state.created[1].valid, "all owned projectors are removed after invalid input")
        lights[2].id = "2"
        lights[1].fov = 180
        check(not pool:Reconcile(camera, lights, false), "invalid FOV is rejected")
        lights[1].fov, lights[1].range = 60, 8
        check(not pool:Reconcile(camera, lights, false), "range at the near plane is rejected")
        lights[1].range, lights[1].color.r = 512, 256
        check(not pool:Reconcile(camera, lights, false), "out-of-range color is rejected")
        lights[1].color.r, lights[1].position.x = 255, 0 / 0
        check(not pool:Reconcile(camera, lights, false), "non-finite coordinates are rejected")
        local sparse = { [1] = candidate("a", 1), [2] = candidate("b", 2), [10] = candidate("c", 3) }
        check(not pool:Reconcile(camera, sparse, false), "sparse candidates are rejected")
    end)

    suite:Add("unavailable texture or projector allocation fails without partial lights", function(check)
        local state, pool, candidate = fixture()
        local camera, lights = { x = 0, y = 0, z = 0 }, { candidate("a", 1) }
        state.missing = true
        local ok, problem = pool:Reconcile(camera, lights, false)
        check(not ok and type(problem) == "string" and #state.created == 0, "missing texture is reported")
        state.missing = false
        check(pool:Reconcile(camera, lights, false), "existing candidate can allocate")
        state.fail = true
        lights[2] = candidate("b", 2)
        ok, problem = pool:Reconcile(camera, lights, false)
        check(not ok and type(problem) == "string" and pool:Status().active == 0
            and not state.created[1].valid, "allocation failure clears earlier projectors")
    end)
    return suite
end
