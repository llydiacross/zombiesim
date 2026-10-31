return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("steam preview requires its sole editor owner and is cleaned up", function(check)
        local state = { allowed = false, owner = false, hooks = {}, commands = {}, timers = {} }
        local target = { valid = true, ZM_PrefabEditorOrigin = {} }
        function target:ConCommand(command) state.commands[#state.commands + 1] = command end
        local env = {
            IsValid = function(value) return value and value.valid end, tostring = tostring,
            os = { time = function() return 100 end },
            ZM_PrefabEditor = {
                IsParticipant = function() return state.allowed end,
                IsOwner = function() return state.owner end,
                IsFixtureMap = function() return state.fixture == true end
            },
            ZM_Util = {
                RegisterCommands = function(_, callback) state.command = callback end,
                ResolveCommandTarget = function() return target end
            },
            ZM_DevConsole = { Report = function(_, name, value) state.report = { name = name, value = value } end },
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end },
            timer = {
                Create = function(name, _, _, callback) state.timers[name] = callback end,
                Remove = function(name) state.timers[name] = nil end
            }
        }
        local chunk = loadChunk("sv_prefab_particle_probe.lua")
        setfenv(chunk, env)
        chunk()
        check(not state.command(nil, "zombiesim_prefab_particle_probe", { "start" }) and #state.commands == 0,
            "unauthorized start does nothing")
        state.allowed, state.owner, state.fixture = true, true, true
        check(not state.command(nil, "zombiesim_prefab_particle_probe", { "start" }),
            "anchor fixture map is excluded")
        state.fixture = false
        check(not state.command(nil, "zombiesim_prefab_particle_probe", { "start", "unknown" }),
            "unknown preview modes are rejected")
        check(state.command(nil, "zombiesim_prefab_particle_probe", { "start" })
            and state.commands[1] == "zombiesim_dev_prefab_particle_client on burst", "owner starts one preview")
        check(not state.command(nil, "zombiesim_prefab_particle_probe", { "start" }), "duplicate start is rejected")
        state.command(nil, "zombiesim_prefab_particle_probe", { "status" })
        check(state.report and state.report.value.owner and state.commands[2]:find("status 1001", 1, true),
            "status forwards a request ID for separate client verification")
        state.hooks.PreCleanupMap()
        check(state.commands[#state.commands] == "zombiesim_dev_prefab_particle_client off"
            and next(state.timers) == nil, "map cleanup stops the client preview and expiry timer")
    end)
    return suite
end
