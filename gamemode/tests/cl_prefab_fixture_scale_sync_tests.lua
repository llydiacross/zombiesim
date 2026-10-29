return function(createSync)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("fixture scale waits for replication and reactivates after transmission", function(check)
        local state = { now = 0, hooks = {}, timers = {}, errors = {} }
        local entity = { valid = true, scale = 1, networkScale = 0, dormant = false, calls = 0 }
        function entity:GetClass() return "prop_physics" end
        function entity:GetModelScale() return self.scale end
        function entity:GetNW2Float() return self.networkScale end
        function entity:IsDormant() return self.dormant end
        function entity:Activate() self.calls = self.calls + 1 end
        function entity:EntIndex() return 7 end
        local sync = createSync({
            IsValid = function(value) return value and value.valid end,
            CurTime = function() return state.now end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end },
            timer = { Simple = function(_, callback) state.timers[#state.timers + 1] = callback end }
        })
        state.hooks.EntityNetworkedVarChanged(entity, "other", nil, 0.5)
        sync:Think()
        check(entity.calls == 0, "unrelated network state does not activate props")
        state.hooks.EntityNetworkedVarChanged(entity, "ZM.PrefabFixtureScale", nil, 0.5)
        sync:Think()
        check(entity.calls == 0, "activation waits until the model scale actually arrives")
        entity.scale, entity.networkScale = 0.5, 0.5
        sync:Think()
        sync:Think()
        check(entity.calls == 1, "matching scale activates exactly once")
        state.hooks.NotifyShouldTransmit(entity, false)
        state.hooks.NotifyShouldTransmit(entity, true)
        state.timers[#state.timers]()
        sync:Think()
        check(entity.calls == 2, "re-entering transmission reactivates the owned prop")
        state.hooks.EntityNetworkedVarChanged(entity, "ZM.PrefabFixtureScale", 0.5, 2)
        state.now = 6
        sync:Think()
        check(entity.calls == 2 and #state.errors == 1, "a missing scale update is reported")
        state.hooks.EntityRemoved(entity)
        check(sync.Pending[entity] == nil and sync.Applied[entity] == nil, "removal releases tracked state")
    end)
    return suite
end
