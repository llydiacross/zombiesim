return function(createProbe)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("isolated spotlight checks assets, renders once and cleans up", function(check)
        local state = { active = false, hooks = {}, created = {}, models = {}, missing = false }
        local vectorMeta = { __add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, getmetatable(a)) end }
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local editor = { Origin = vector(100, 200, 300), IsActive = function() return state.active end }
        local probe = createProbe({
            Editor = editor, IsValid = function(value) return value and value.valid end,
            Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            Color = function(r, g, b) return { r = r, g = g, b = b } end,
            Matrix = function() return { Scale = function(self, value) self.scale = value end } end,
            Material = function()
                return { IsError = function() return state.missing end,
                    GetTexture = function() return { Width = function() return 64 end, Height = function() return 64 end } end }
            end,
            ProjectedTexture = function()
                local light = { valid = true, updates = 0 }
                for _, name in ipairs({ "SetTexture", "SetOrthographic", "SetFOV", "SetNearZ", "SetFarZ",
                    "SetColor", "SetBrightness", "SetEnableShadows", "SetPos", "SetAngles" }) do
                    light[name] = function(self, ...) self[name] = { ... } end
                end
                function light:Update() self.updates = self.updates + 1 end
                function light:Remove() self.valid = false end
                function light:GetPos() return self.SetPos[1] end
                function light:GetAngles() return self.SetAngles[1] end
                function light:GetColor() return self.SetColor[1] end
                function light:GetBrightness() return self.SetBrightness[1] end
                function light:GetHorizontalFOV() return self.SetFOV[1] end
                function light:GetFarZ() return self.SetFarZ[1] end
                function light:GetEnableShadows() return self.SetEnableShadows[1] end
                state.created[#state.created + 1] = light
                return light
            end,
            ClientsideModel = function(path, group)
                local model = { valid = true, path = path, group = group }
                function model:SetPos(value) self.position = value end
                function model:SetAngles(value) self.angles = value end
                function model:SetNoDraw(value) self.noDraw = value end
                function model:SetSkin(value) self.skin = value end
                function model:GetModelBounds() return vector(-2, -2, 0), vector(2, 2, 4) end
                function model:SetRenderBounds(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
                function model:EnableMatrix(name, value) self.matrixName, self.matrix = name, value end
                function model:DisableMatrix(name) self.disabledMatrix, self.matrix = name, nil end
                function model:DrawModel() self.drawn = true end
                function model:Remove() self.valid = false end
                state.models[#state.models + 1] = model
                if group == 7 then state.comparison = model else state.manual = model end
                return model
            end,
            RENDERGROUP_OPAQUE = 7, RENDERGROUP_OTHER = 13,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        })
        local ok = probe:Start("normal")
        check(not ok and #state.created == 0, "inactive editor cannot allocate a preview")
        state.active, state.missing = true, true
        ok = probe:Start("normal")
        check(not ok and #state.created == 0, "missing texture is reported before allocation")
        state.missing = false
        check(not probe:Start("invalid") and #state.created == 0, "unknown modes cannot allocate a preview")
        check(probe:Start("normal"), "active editor starts one preview")
        local light = state.created[1]
        check(light.SetEnableShadows[1] == true and light.SetFOV[1] == 60 and light.SetFarZ[1] == 512,
            "preview uses one shadowed, bounded spotlight")
        check(light.SetPos[1].x == 20 and light.SetPos[1].y == 40 and light.SetPos[1].z == 492
            and light.SetAngles[1].p == 40 and light.SetAngles[1].y == 45,
            "preview is aimed from a known position toward the test prop")
        state.hooks.PreDrawOpaqueRenderables(true, false)
        state.hooks.PreDrawOpaqueRenderables(false, true)
        check(light.updates == 0, "depth and skybox passes do not update the light")
        state.hooks.PreDrawOpaqueRenderables(false, false)
        state.hooks.PreDrawOpaqueRenderables(false, false)
        local lightStatus = probe:Status()
        check(light.updates == 1 and lightStatus.textureWidth == 64 and lightStatus.projector.shadows
            and lightStatus.projector.position.x == 20 and lightStatus.projector.fov == 60,
            "normal render updates once and reports engine projector settings")
        state.active = false
        state.hooks.Think()
        check(not light.valid and not probe:Status().active, "closing the editor removes the projector")
        state.active = true
        check(probe:Start("bright"), "bright shadowed comparison starts")
        local bright = state.created[2]
        check(bright.SetBrightness[1] == 6 and bright.SetEnableShadows[1] == true,
            "bright comparison retains shadows")
        probe:Stop()
        check(probe:Start("unshadowed"), "unshadowed comparison starts")
        local unshadowed = state.created[3]
        local status = probe:Status()
        check(unshadowed.SetBrightness[1] == 6 and unshadowed.SetEnableShadows[1] == false
            and status.mode == "unshadowed" and status.brightness == 6 and not status.shadows,
            "unshadowed comparison reports its actual configuration")
        probe:Stop()
        check(probe:Start("compare"), "client model comparison starts")
        check(state.comparison.valid and state.comparison.group == 7 and probe:Status().comparisonModel,
            "comparison model is an engine-drawn opaque client model")
        check(state.manual.valid and state.manual.noDraw and probe:Status().manualModel,
            "comparison includes the editor's original manually drawn model")
        state.hooks.PostDrawTranslucentRenderables(false, false)
        check(state.manual.drawn, "manual comparison is drawn in the editor render phase")
        check(probe:SetManualMatrix(true) and probe:Status().manualMatrix
            and state.manual.matrix.scale.x == 1, "an identity matrix can be applied to the same manual model")
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(probe:Status().updates == 1, "changing the model matrix refreshes the projector")
        check(probe:SetManualMatrix(false) and not probe:Status().manualMatrix
            and state.manual.disabledMatrix == "RenderMultiply", "the identity matrix can be removed again")
        check(probe:RemoveComparison() and not state.comparison.valid and not probe:Status().comparisonModel,
            "the other model can be removed without stopping the light or manual model")
        check(probe:MatchEditorModel() and probe:Status().manualEditorSetup
            and state.manual.skin == 0 and state.manual.matrix.scale.x == 1
            and state.manual.minimum.x == -2 and state.manual.maximum.z == 4,
            "the same manual model can receive the editor's exact skin, matrix and bounds setup")
        probe:Stop()
        check(not state.comparison.valid and not state.manual.valid
            and not probe:Status().comparisonModel and not probe:Status().manualModel,
            "both comparison models are removed with the projector")
        check(probe:Start("matrix"), "matrix comparison starts")
        local matrixModel, plainModel = state.models[#state.models - 1], state.models[#state.models]
        check(matrixModel.noDraw and plainModel.noDraw and matrixModel.group == 13 and plainModel.group == 13
            and matrixModel.matrixName == "RenderMultiply" and matrixModel.matrix.scale.x == 1
            and plainModel.matrix == nil, "two manually drawn drums differ only by an identity render matrix")
        state.hooks.PostDrawTranslucentRenderables(false, false)
        check(matrixModel.drawn and plainModel.drawn, "both matrix comparison models use the same render hook")
        probe:Stop()
        check(not matrixModel.valid and not plainModel.valid, "matrix comparison cleanup removes both models")
    end)
    return suite
end
