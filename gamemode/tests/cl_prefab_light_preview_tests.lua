return function(createPreview)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("editor spotlight preview reconciles changes and releases its pool", function(check)
        local state = { active = false, hooks = {}, now = 0, calls = {}, errors = {}, fail = nil, cleared = 0 }
        local vectorMeta = { __add = function(a, b)
            return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, getmetatable(a))
        end }
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local editor = {
            Origin = vector(100, 200, 300), PrefabPreviewOffset = 0, SceneRefresh = true,
            Document = { lights = { { lightId = "light_1", position = { x = 10, y = 20, z = 30 },
                angles = { p = 40, y = 45, r = 0 }, color = { r = 255, g = 235, b = 200 },
                brightness = 6, fov = 60, range = 512 } } },
            IsActive = function() return state.active end,
            GetPreviewOrigin = function(self) return self.Origin + vector(0, 0, self.PrefabPreviewOffset) end,
            GetView = function() return { origin = vector(1, 2, 3) } end,
            Message = function(_, message, problem) state.errors[#state.errors + 1] = { message, problem } end
        }
        local pool = {
            Reconcile = function(_, camera, candidates, refresh)
                state.calls[#state.calls + 1] = { camera = camera, candidates = candidates, refresh = refresh }
                if state.fail then return false, state.fail end
                return true
            end,
            Clear = function() state.cleared = state.cleared + 1 end,
            Status = function() return { active = 1, shadowed = 1 } end
        }
        local preview = createPreview({
            GetEditor = function() return editor end, Vector = vector,
            CurTime = function() return state.now end,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        }, pool)
        state.hooks.PreDrawOpaqueRenderables(true, false)
        state.hooks.PreDrawOpaqueRenderables(false, true)
        check(#state.calls == 0, "depth and skybox passes do not reconcile")
        state.active = true
        state.hooks.PreDrawOpaqueRenderables(false, false)
        local call = state.calls[1]
        check(call and call.camera.x == 1 and call.candidates[1].id == "light_1"
            and call.candidates[1].position.x == 110 and call.candidates[1].position.z == 330
            and call.candidates[1].brightness == 6 and call.refresh and not editor.SceneRefresh,
            "authored local settings and a scene refresh reach the pool")
        editor.PrefabPreviewOffset, editor.SceneRefresh = 25, true
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(state.calls[2].candidates[1].position.z == 355 and state.calls[2].refresh
            and editor.Document.lights[1].position.z == 30, "preview height moves the spotlight without editing it")
        state.fail, editor.SceneRefresh = "texture unavailable", true
        state.hooks.PreDrawOpaqueRenderables(false, false)
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(#state.errors == 1 and state.errors[1][2] and preview:Status().error == state.fail
            and editor.SceneRefresh, "failures report once and preserve the pending scene refresh")
        state.now, state.fail = 1, nil
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(preview:Status().error == nil and not editor.SceneRefresh, "failed initialization retries")
        preview:SetSuspended(true)
        local count = #state.calls
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(preview:Status().suspended and #state.calls == count,
            "diagnostic suspension clears the pool without modifying the document")
        preview:SetSuspended(false)
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(not preview:Status().suspended and #state.calls == count + 1, "resuming recreates the preview")
        state.active = false
        state.hooks.Think()
        check(state.cleared > 0, "closing the editor clears the pool")
        state.hooks.PreCleanupMap()
        state.hooks.ShutDown()
        check(state.cleared >= 3, "map cleanup and shutdown clear the pool")
    end)
    return suite
end
