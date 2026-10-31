return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { allowed = false, owner = false, hooks = {}, timers = {}, commands = {}, entities = {} }
        local vectorMeta = { __add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, getmetatable(a)) end }
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local target = { valid = true, ZM_PrefabEditorOrigin = vector(100, 200, 300) }
        function target:ConCommand(command) state.commands[#state.commands + 1] = command end
        local env = {
            IsValid = function(value) return type(value) == "table" and value.valid == true end,
            os = { time = function() return 100 end }, tostring = tostring,
            Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            util = { IsValidModel = function() return true end, IsValidProp = function() return true end },
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
            },
            ents = { Create = function(class)
                assert(class == "prop_physics")
                local physics = { valid = state.physicsValid ~= false }
                function physics:EnableMotion(value) self.motion = value end
                function physics:Sleep() self.sleeping = true end
                local entity = { valid = true, physics = physics }
                function entity:SetModel(value) self.model = value end
                function entity:SetPos(value) self.position = value end
                function entity:SetAngles(value) self.angles = value end
                function entity:Spawn() end
                function entity:Activate() end
                function entity:GetPhysicsObject() return self.physics end
                function entity:Remove() self.valid = false end
                state.entities[#state.entities + 1] = entity
                return entity
            end }
        }
        local chunk = loadChunk("sv_prefab_spotlight_probe.lua")
        setfenv(chunk, env)
        chunk()
        return state
    end
    suite:Add("spotlight probe requires the editor owner and releases its prop", function(check)
        local state = fixture()
        local ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start" })
        check(not ok and #state.entities == 0, "unauthorized start creates no prop")
        state.allowed, state.owner, state.fixture = true, true, true
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start" })
        check(not ok and #state.entities == 0, "the anchor fixture is not the editor workspace")
        state.fixture = false
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start", "invalid" })
        check(not ok and #state.entities == 0, "unknown modes create no prop")
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start" })
        check(ok and state.entities[1].position.x == 180 and not state.entities[1].physics.motion
            and state.commands[1] == "zombiesim_dev_prefab_spotlight_client on normal", "editor probe creates a stationary prop and requests the client light")
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start" })
        check(not ok and #state.entities == 1, "duplicate starts do not allocate more props")
        state.command(nil, "zombiesim_prefab_spotlight_probe", { "status" })
        check(state.report and state.report.value.active and state.report.value.owner, "server status reports the owned prop")
        local commandCount = #state.commands
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "prop_off" })
        check(ok and not state.entities[1].valid and #state.commands == commandCount,
            "the owned test prop can be removed without stopping the projector")
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start" })
        check(not ok and #state.entities == 1, "removing the prop does not allow a second active probe")
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "pause_editor" })
        check(ok and state.commands[#state.commands] == "zombiesim_prefab_light_preview_control_client pause",
            "the probe owner can temporarily suspend the editor projector")
        ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "matrix_on" })
        check(ok and state.commands[#state.commands] == "zombiesim_dev_prefab_spotlight_client matrix_on",
            "the probe owner can toggle the manual comparison model's matrix")
        state.hooks.PreCleanupMap()
        check(not state.entities[1].valid and state.commands[#state.commands - 1] == "zombiesim_dev_prefab_spotlight_client off"
            and state.commands[#state.commands] == "zombiesim_prefab_light_preview_control_client resume",
            "map cleanup stops the probe and restores the editor preview")
    end)
    suite:Add("invalid spotlight physics fails without leaving a prop", function(check)
        local state = fixture()
        state.allowed, state.physicsValid = true, false
        local ok = state.command(nil, "zombiesim_prefab_spotlight_probe", { "start" })
        check(not ok and #state.entities == 1 and not state.entities[1].valid and #state.commands == 0,
            "invalid physics removes the test entity and never starts a client light")
    end)
    return suite
end
