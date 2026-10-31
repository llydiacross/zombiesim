return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("anchor input forwards only the addressed particle ID", function(check)
        local state = { calls = {}, errors = {} }
        local env = {
            ENT = {}, SERVER = true, string = string, tostring = tostring,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            ZM_Prefabs = { TriggerParticle = function(_, anchor, id)
                state.calls[#state.calls + 1] = { anchor = anchor, id = id }
                if id == "missing" then return false, "Unknown particle." end
                return true
            end }
        }
        local chunk = loadChunk("entities/entities/zn_prefab_anchor/shared.lua")
        setfenv(chunk, env)
        chunk()
        local anchor = env.ENT
        check(anchor:AcceptInput("TriggerParticle", nil, nil, "particle_1") == true
            and state.calls[1].anchor == anchor and state.calls[1].id == "particle_1",
            "known input forwards the target ID")
        check(anchor:AcceptInput("OtherInput", nil, nil, "particle_1") == nil and #state.calls == 1,
            "unrelated inputs are left to the engine")
        anchor:AcceptInput("triggerparticle", nil, nil, "missing")
        check(#state.errors == 1, "failed triggers are logged")
        env.ZM_Prefabs = nil
        check(anchor:AcceptInput("TriggerParticle", nil, nil, "particle_1") == true and #state.errors == 2,
            "an unavailable owner is reported")
    end)
    return suite
end
