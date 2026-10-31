return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("world particle probe remains isolated and cleans up", function(check)
        local state = { allowed = false, owner = false, commands = {}, timers = {}, hooks = {}, triggers = {} }
        local target = { valid = true, ZM_PrefabEditorOrigin = { x = 1, y = 2, z = 3 } }
        function target:ConCommand(command) state.commands[#state.commands + 1] = command end
        local env = {
            IsValid = function(value) return value and value.valid end,
            setmetatable = setmetatable, Vector = function() end,
            Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            LocalToWorld = function() end, file = {}, util = {}, ents = {}, ZM_StaticData = {},
            ZM_World = { ActiveProfile = "preview" },
            ZM_PrefabEditor = {
                IsParticipant = function() return state.allowed end,
                IsOwner = function() return state.owner end,
                IsFixtureMap = function() return state.fixture == true end
            },
            ZM_Prefabs = {
                Cleanup = function(self) state.cleaned = true; self.Instances = nil end,
                TriggerParticle = function(_, anchor, id)
                    state.triggers[#state.triggers + 1] = { anchor = anchor, id = id }
                    return true
                end
            },
            ZM_Util = {
                RegisterCommands = function(_, callback) state.command = callback end,
                ResolveCommandTarget = function() return target end
            },
            ZM_DevConsole = { Report = function(_, _, report) state.report = report end },
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end },
            timer = {
                Create = function(name, _, _, callback) state.timers[name] = callback end,
                Remove = function(name) state.timers[name] = nil end
            }
        }
        local function createSpawn(_, api)
            check(type(api.ResolveParticle) == "function", "probe uses the validated particle catalog")
            return { Create = function(document, anchor)
                state.document, state.anchor = document, anchor
                if state.spawnError then return nil, "Spawn failed." end
                return { particles = {} }
            end }
        end
        local createLoot = function() return { Resolve = function() end } end
        local createCatalog = function() return { Resolve = function() end } end
        local chunk = loadChunk("sv_prefab_particle_world_probe.lua")
        setfenv(chunk, env)
        chunk()({}, createSpawn, createLoot, createCatalog)
        check(not state.command(nil, "zombiesim_prefab_particle_world_probe", { "start" }),
            "unauthorized start is rejected")
        state.allowed, state.owner, state.fixture = true, true, true
        check(not state.command(nil, "zombiesim_prefab_particle_world_probe", { "start" }),
            "anchor fixture map is excluded")
        state.fixture, target.ZM_PersistentStateLoaded = false, true
        check(not state.command(nil, "zombiesim_prefab_particle_world_probe", { "start" }),
            "loaded survivor is excluded")
        target.ZM_PersistentStateLoaded = false
        state.spawnError = true
        check(not state.command(nil, "zombiesim_prefab_particle_world_probe", { "start" }) and #state.commands == 0,
            "spawn failure does not enable the client fixture")
        state.spawnError = false
        check(state.command(nil, "zombiesim_prefab_particle_world_probe", { "start" })
            and state.commands[1] == "zombiesim_prefab_particle_world_fixture_client on"
            and #state.document.particles == 3 and state.document.particles[2].overlap
            and not state.document.particles[3].overlap, "owner starts continuous and distinct triggered cases")
        check(not state.command(nil, "zombiesim_prefab_particle_world_probe", { "start" }),
            "duplicate fixture start is rejected")
        check(state.command(nil, "zombiesim_prefab_particle_world_probe", { "trigger", "burst_overlap" })
            and state.triggers[1].id == "burst_overlap" and not state.command(nil,
                "zombiesim_prefab_particle_world_probe", { "trigger", "unknown" }),
            "only explicitly named fixture triggers are allowed")
        state.hooks.PreCleanupMap()
        check(state.cleaned and state.commands[#state.commands] == "zombiesim_prefab_particle_world_fixture_client off"
            and not state.anchor.valid and next(state.timers) == nil,
            "cleanup removes owned state, disables the client fixture and cancels expiry")
    end)
    return suite
end
