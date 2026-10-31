return function(createRuntime)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("networked lights reconcile, retry and clear with their owner", function(check)
        local state = { now = 0, hooks = {}, entities = {}, calls = {}, errors = {}, scans = 0, clears = 0 }
        local editor = { active = false, IsActive = function(self) return self.active end }
        local function entity(id, x)
            return {
                valid = true, id = id,
                GetPrefabLightId = function(self) return self.id end,
                GetPos = function() return { x = x, y = 0, z = 10 } end,
                GetAngles = function() return { p = 40, y = 90, r = 0 } end,
                GetLightColor = function() return { x = 255, y = 235, z = 200 } end,
                GetLightBrightness = function() return 6 end,
                GetLightFov = function() return 60 end,
                GetLightRange = function() return 512 end
            }
        end
        state.entities = { entity("1234:light_1", 10), entity("", 20) }
        local pool = {
            Reconcile = function(_, camera, candidates, refresh)
                state.calls[#state.calls + 1] = { camera = camera, candidates = candidates, refresh = refresh }
                if state.problem then return false, state.problem end
                return true
            end,
            Clear = function() state.clears = state.clears + 1 end,
            Status = function() return { active = 1, shadowed = 1 } end
        }
        local runtime = createRuntime({
            GetEditor = function() return editor end,
            FindEntities = function() state.scans = state.scans + 1 return state.entities end,
            CurTime = function() return state.now end,
            EyePos = function() return { x = 1, y = 2, z = 3 } end,
            IsValid = function(value) return value and value.valid end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        }, pool)
        state.hooks.PreDrawOpaqueRenderables(true, false)
        state.hooks.PreDrawOpaqueRenderables(false, true)
        check(#state.calls == 0, "depth and skybox passes are skipped")
        state.hooks.PreDrawOpaqueRenderables(false, false)
        local call = state.calls[1]
        check(call and call.refresh and call.camera.x == 1 and #call.candidates == 1
            and call.candidates[1].id == "1234:light_1" and call.candidates[1].color.g == 235
            and call.candidates[1].angles.y == 90 and call.candidates[1].range == 512
            and runtime:Status().pending == 1, "replicated values reach the pool and pending entities are counted")
        state.entities[2].id = "1234:light_2"
        state.now = 0.1
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(#state.calls[2].candidates == 2 and state.scans == 1,
            "replicated settings become available without another entity scan")
        state.entities[1].valid = false
        state.problem = "allocation failed"
        state.now = 0.2
        state.hooks.PreDrawOpaqueRenderables(false, false)
        state.now = 0.3
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(#state.errors == 1 and runtime:Status().error == state.problem
            and #state.calls[3].candidates == 1, "removed entities are skipped and repeated errors are logged once")
        state.problem, state.now = nil, 0.4
        state.hooks.PreDrawOpaqueRenderables(false, false)
        check(runtime:Status().error == nil and state.scans >= 2, "subsequent updates retry and rescan")
        editor.active = true
        state.hooks.PreDrawOpaqueRenderables(false, false)
        state.hooks.PreCleanupMap()
        state.hooks.ShutDown()
        check(state.clears >= 3, "editor ownership, map cleanup and shutdown release projectors")
    end)
    return suite
end
