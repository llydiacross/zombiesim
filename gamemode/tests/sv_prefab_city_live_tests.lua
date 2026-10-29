return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { files = {}, decoded = {}, cleaned = {}, position = { DistToSqr = function() return 0 end } }
        local target = { ZM_PersistentStateLoaded = true, ZM_Inventory = {} }
        function target:IsAdmin() return true end
        function target:Alive() return true end
        function target:GetWorldCell() return { id = 42, map = "fixture" } end
        function target:GetPos() return state.position end
        local active = { profile = "preview", cellId = 42 }
        local env = {
            type = type, tostring = tostring, string = string, ipairs = ipairs, pcall = pcall, error = error,
            ZM_TestHarness = { Register = function(spec) state.spec = spec end },
            ZM_Util = {
                FirstHuman = function() return target end,
                RegisterCommands = function(_, callback) state.recover = callback end
            },
            IsValid = function(value) return value == target end,
            player = { GetHumans = function() return { target } end },
            game = { GetMap = function() return "fixture" end },
            ZM_World = { ActiveProfile = "preview", GetMapPath = function() return "fixture" end },
            ZM_SafeZones = { IsSafeZoneCell = function() return false end },
            ZM_Prefabs = { Ready = true },
            ZM_LootSpots = { Cell = active },
            ZM_InventoryService = { ToRows = function() return {} end },
            ZM_ItemGeneration = { NewInstanceId = function() return "abc123" end },
            ZM_DeleteLootCells = function(profile) state.cleaned[#state.cleaned + 1] = profile; return true end,
            sql = { Query = function() return nil end, SQLStr = function(value) return "'" .. value .. "'" end },
            util = {
                TableToJSON = function(value)
                    if value.schemaVersion then state.decoded.marker = value; return "marker" end
                    return "rows"
                end,
                JSONToTable = function(value) return state.decoded[value] end
            },
            file = {
                CreateDir = function() end,
                Exists = function(path) return state.files[path] ~= nil end,
                Read = function(path) return state.files[path] end,
                Write = function(path, value) state.files[path] = value; return true end,
                Delete = function(path) state.files[path] = nil; return true end
            },
            Vector = function() end, Angle = function() end, LocalToWorld = function() end,
            ents = { Create = function() error("Unexpected real entity creation") end },
            os = { time = function() return 1000 end }
        }
        env.ZM_TestHarness.NewSuite = ZM_TestHarness.NewSuite
        state.loot = env.ZM_LootSpots
        local chunk = loadChunk("tests/sv_prefab_city_live.lua")
        setfenv(chunk, env)
        local register = chunk()
        register({}, function() return { Create = function() return nil, "injected spawn failure" end } end,
            function() return { Resolve = function() end } end)
        return state, target, active
    end
    suite:Add("city probe refuses a non-deployed player without writes", function(check)
        local state, target = fixture()
        target.ZM_PersistentStateLoaded = false
        local result = state.spec.run()
        check(result.failed == 1 and #state.cleaned == 0 and next(state.files) == nil,
            "launcher/non-deployed contexts fail before creating a marker or profile")
    end)
    suite:Add("city probe restores active state and cleans up on spawn failure", function(check)
        local state, target, active = fixture()
        local result = state.spec.run()
        check(result.failed == 1 and #state.cleaned == 1 and state.cleaned[1] == "zn_test_prefab_city_abc123",
            "spawn failure is reported and the unique test profile is removed")
        check(next(state.files) == nil and target.ZM_LootSearch == nil and target.ZM_LootOffer == nil,
            "recovery marker and player interaction state are restored")
        check(state.position == target:GetPos() and state.loot.Cell == active,
            "the original location and active cell remain unchanged")
    end)
    return suite
end
