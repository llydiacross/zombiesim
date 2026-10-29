return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { hooks = {}, timers = {}, anchors = {}, created = {}, choices = {}, errors = {}, loads = 0 }
        local target = { ZM_PersistentStateLoaded = true }
        local cell = { id = 42, map = "fixture" }
        function target:GetWorldCell() return cell end
        local catalog = {
            Load = function()
                state.loads = state.loads + 1
                if state.loadError then return nil, state.loadError end
                return {}
            end,
            Select = function(_, tags, profile, seed, cellId, id)
                state.choices[#state.choices + 1] = { tags = tags, profile = profile, seed = seed, cell = cellId, id = id }
                if state.failAnchor == id then return nil, "unmatched tags" end
                return { id = "chosen", props = {} }
            end
        }
        local spawn = {
            Create = function(_, anchor)
                local entity = { anchor = anchor }
                state.created[#state.created + 1] = entity
                return { entity }
            end,
            Remove = function(entities) for _, entity in ipairs(entities) do entity.removed = true end end
        }
        local env = {
            ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, string = {},
            ZM_Util = {
                RegisterCommands = function(_, callback) state.statusCommand = callback end,
                RequireAdmin = function() return true end,
                ResolveCommandTarget = function() return target end
            },
            IsValid = function(value) return type(value) == "table" and value.valid ~= false end,
            file = {}, util = {}, Vector = function() end, Angle = function() end, LocalToWorld = function() end,
            ents = { FindByClass = function(class) assert(class == "zn_prefab_anchor"); return state.anchors end },
            player = { GetHumans = function() return { target } end },
            game = { GetMap = function() return state.map or "fixture" end },
            ZM_World = {
                ActiveProfile = "preview",
                GetMapPath = function(_, value) return value.map end,
                GetData = function() return { world = { seed = 1337 } } end
            },
            ZM_SafeZones = { IsSafeZoneCell = function() return state.safe == true end },
            ZM_PrefabEditor = {
                IsFixtureMap = function() return state.fixture == true end,
                IsParticipant = function() return state.participant == true end
            },
            ZM_Loading = { Step = function(_, _, message) state.loading = message end },
            ZM_LootSpots = { OnPlayerReady = function()
                state.lootCalls = (state.lootCalls or 0) + 1
                state.propsAtLoot = #state.created
            end },
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end
        }
        for key, value in pairs(string) do env.string[key] = value end
        env.string.Trim = function(value) return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")) end
        env.include = function(path)
            if path == "prefabs/sh_contract.lua" then return {} end
            if path == "prefabs/sv_loot.lua" then return function() return { Validate = function() return true end } end end
            if path == "prefabs/sh_fixture_trace.lua" then return function() return {} end end
            if path == "prefabs/sv_catalog.lua" then return function() return catalog end end
            assert(path == "prefabs/sv_spawn.lua")
            return function() return spawn end
        end
        env.hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        env.timer = { Simple = function(delay, callback) assert(delay == 0); state.timers[#state.timers + 1] = callback end }
        function state:AddAnchor(id, keys)
            local anchor = { ZM_Config = keys or { prefab_tags = "road, motorway" }, MapCreationID = function() return id end }
            self.anchors[#self.anchors + 1] = anchor
        end
        local chunk = loadChunk("sv_prefabs.lua")
        setfenv(chunk, env)
        chunk()
        return env.ZM_Prefabs, state, target, cell
    end

    suite:Add("map readiness precedes one server-owned spawn per anchor", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        local early, problem = owner:OnPlayerReady(target)
        check(early == nil and type(problem) == "string" and #state.created == 0,
            "early player spawn reports pending and cannot create entities before InitPostEntity")
        state.hooks.InitPostEntity()
        check(#state.created == 0, "initialization waits until after the map profile callback")
        state.timers[1]()
        check(#state.created == 1 and state.loads == 1, "ready callback spawns for an already-loaded survivor")
        check(state.lootCalls == 1 and state.propsAtLoot == 1,
            "loot initialization follows prefab creation for an early player spawn")
        owner:OnPlayerReady(target)
        check(#state.created == 1, "later players or respawns do not duplicate the map instance")
        local status = owner:GetStatus()
        check(status.ready and status.anchors == 1 and status.props == 1 and status.cellId == 42,
            "read-only status reports the actual owned instances")
        local choice = state.choices[1]
        check(choice.cell == 42 and choice.id == 1234 and choice.profile == "preview"
            and choice.seed == 1337 and choice.tags[2] == "motorway", "selection uses authoritative cell and anchor identity")
    end)
    suite:Add("instance-local copies are skipped without discarding direct anchors", function(check)
        local owner, state, target = fixture()
        owner.Ready = true
        state:AddAnchor(1234, { instance_local = "1", prefab_tags = "road" })
        state:AddAnchor(1235, { instance_local = "1", zm_instance_transformed = "1", prefab_tags = "road" })
        state:AddAnchor(1236, { prefab_tags = "road" })
        check(owner:OnPlayerReady(target), "mixed anchor placement is accepted")
        check(#state.created == 2 and state.choices[1].id == 1235 and state.choices[2].id == 1236,
            "only transformed and direct world-space anchors spawn")
    end)
    suite:Add("cleanup restores authored instances and cell conflicts fail explicitly", function(check)
        local owner, state, target, cell = fixture()
        state:AddAnchor(1234)
        owner.Ready = true
        owner:OnPlayerReady(target)
        cell.id = 43
        local ok, problem = owner:OnPlayerReady(target)
        check(not ok and type(problem) == "string" and #state.created == 1, "another cell cannot replace active props")
        state.hooks.PreCleanupMap()
        check(state.created[1].removed and not owner.Ready, "cleanup removes owned props")
        state.hooks.PostCleanupMap()
        state.timers[1]()
        check(#state.created == 2 and state.choices[2].cell == 43, "cleanup recreates authored layout for the current cell")
    end)
    suite:Add("launcher, den and mismatched-map contexts cannot spawn prefabs", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        owner.Ready = true
        target.ZM_PersistentStateLoaded = false
        owner:OnPlayerReady(target)
        target.ZM_PersistentStateLoaded = true
        target.CurrentSafeZoneId = "den"
        owner:OnPlayerReady(target)
        target.CurrentSafeZoneId = nil
        state.map = "other"
        owner:OnPlayerReady(target)
        check(#state.created == 0 and state.loads == 0, "ineligible contexts leave the catalog and world untouched")
    end)
    suite:Add("unmatched tags remain explicit failures without repeated spawning", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        state.failAnchor = 1234
        owner.Ready = true
        local ok, problem = owner:OnPlayerReady(target)
        check(not ok and type(problem) == "string" and #state.errors == 1, "failed anchor logs its error")
        owner:OnPlayerReady(target)
        check(#state.created == 0 and #state.choices == 1, "a failed anchor cannot silently choose a substitute")
    end)
    suite:Add("catalog failures spawn nothing and preserve the error", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        state.loadError = "invalid export"
        owner.Ready = true
        local ok, problem = owner:OnPlayerReady(target)
        check(not ok and problem == "invalid export" and owner:GetStatus().error == problem and #state.created == 0,
            "invalid exported catalog cannot produce partial world props")
    end)
    suite:Add("map readiness resumes ordinary loot even when prefab placement fails", function(check)
        local _, state = fixture()
        state:AddAnchor(1234)
        state.failAnchor = 1234
        state.hooks.InitPostEntity()
        state.timers[1]()
        check(#state.errors > 0 and state.lootCalls == 1 and state.propsAtLoot == 0,
            "prefab failure is logged and ordinary loot initialization is not suppressed")
    end)
    suite:Add("synthetic-cell fixture spawning is restricted to the isolated session", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        owner.Ready = true
        target.ZM_PersistentStateLoaded = false
        local ok = state.statusCommand(nil, "zombiesim_prefab_fixture_spawn")
        check(not ok and #state.created == 0, "ordinary maps cannot invoke fixture spawning")
        state.fixture, state.participant = true, true
        state.map = "zn_dev_prefab_anchor"
        target.ZM_PersistentStateLoaded = true
        ok = state.statusCommand(nil, "zombiesim_prefab_fixture_spawn")
        check(not ok and #state.created == 0, "a loaded survivor cannot invoke fixture spawning")
        target.ZM_PersistentStateLoaded = false
        ok = state.statusCommand(nil, "zombiesim_prefab_fixture_spawn")
        check(ok and #state.created == 1 and state.choices[1].cell == 0,
            "the isolated owner spawns through the shared catalog and spawn path")
        state.fixture = false
        local rejected, problem = owner:SpawnForCell(0, true)
        check(not rejected and type(problem) == "string",
            "fixture-only scale cannot be requested outside the isolated fixture")
    end)
    return suite
end
