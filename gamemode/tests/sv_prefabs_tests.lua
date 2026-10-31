return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { hooks = {}, timers = {}, anchors = {}, created = {}, choices = {}, errors = {}, loads = 0,
            pendingAnchors = {}, pendingCallbacks = {} }
        local target = { ZM_PersistentStateLoaded = true }
        function target:IsAdmin() return self.admin ~= false end
        function target:ConCommand(command) state.clientCommand = command end
        local cell = { id = 42, map = "fixture" }
        function target:GetWorldCell() return cell end
        local catalog = {
            Load = function()
                state.loads = state.loads + 1
                if state.loadError then return nil, state.loadError end
                return state.documents or {}
            end,
            Select = function(_, tags, profile, seed, cellId, id)
                state.choices[#state.choices + 1] = { tags = tags, profile = profile, seed = seed, cell = cellId, id = id }
                if state.failAnchor == id then return nil, "unmatched tags" end
                return { id = "chosen", props = {} }
            end,
            ForWorldCell = function(documents, profile, x, y)
                local result = {}
                for _, document in ipairs(documents) do
                    local placement = document.worldPlacement
                    if placement and placement.enabled and placement.profile == profile
                        and placement.cellX == x and placement.cellY == y then result[#result + 1] = document end
                end
                return result
            end
        }
        local spawn = {
            Create = function(_, anchor, onReady)
                local id = anchor.ZM_PrefabInstanceId or anchor:MapCreationID()
                local entity = { anchor = anchor, ZM_PrefabGuard = state.pendingAnchors[id] == true }
                state.created[#state.created + 1] = entity
                if state.pendingAnchors[id] then
                    state.pendingCallbacks[id] = function(ok, problem)
                        if not ok then entity.removed = true end
                        onReady(ok, problem)
                    end
                    return { entity, particles = {
                        burst = { id = "test:burst", mode = "triggered", effect = "steam" }
                    } }, nil, true
                end
                return { entity }
            end,
            Remove = function(entities) for _, entity in ipairs(entities) do entity.removed = true end end
        }
        local env = {
            ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
            string = {}, math = math, table = table, CurTime = function() return 10 end,
            MASK_SOLID = 1,
            os = { time = function() return 12345 end },
            ZM_Util = {
                RegisterCommands = function(_, callback) state.statusCommand = callback end,
                RequireAdmin = function() return true end,
                ResolveCommandTarget = function() return target end
            },
            IsValid = function(value) return type(value) == "table" and value.valid ~= false end,
            file = {}, util = { AddNetworkString = function(name)
                state.networkNames = state.networkNames or {}; state.networkNames[name] = true
            end,
                TraceLine = function(request)
                    state.traces = state.traces or {}
                    state.traces[#state.traces + 1] = request
                    return { Hit = not state.noSurface, HitNormal = { z = 1 },
                        HitPos = { x = request.start.x, y = request.start.y, z = 36 } }
                end
            },
            Vector = function(x, y, z) return { x = x, y = y, z = z } end,
            Angle = function(p, y, r) return { p = p, y = y, r = r } end, LocalToWorld = function() end,
            net = {
                Start = function(name) state.packet = { name = name, values = {} } end,
                WriteString = function(value) table.insert(state.packet.values, value) end,
                WriteDouble = function(value) table.insert(state.packet.values, value) end,
                WriteBool = function(value) table.insert(state.packet.values, value) end,
                Broadcast = function() state.sent = (state.sent or 0) + 1 end
            },
            ents = {
                FindByClass = function(class)
                    assert(class == "zn_prefab_anchor")
                    local result = {}
                    for _, anchor in ipairs(state.anchors) do
                        if anchor.valid ~= false then result[#result + 1] = anchor end
                    end
                    return result
                end,
                Create = function(class)
                    assert(class == "zn_prefab_anchor")
                    if state.failWorldAnchor then return nil end
                    local anchor = { valid = true }
                    function anchor:SetPos(value) self.position = value end
                    function anchor:SetAngles(value) self.angles = value end
                    function anchor:Spawn() self.spawned = true end
                    function anchor:CallOnRemove(_, callback) self.onRemove = callback end
                    function anchor:Remove()
                        self.valid = false
                        if self.onRemove then self.onRemove(self) end
                    end
                    state.anchors[#state.anchors + 1] = anchor
                    return anchor
                end
            },
            player = { GetHumans = function() return { target } end },
            game = { GetMap = function() return state.map or "fixture" end },
            ZM_World = {
                ActiveProfile = "preview",
                GetCellById = function(_, id) return id == cell.id and cell or nil end,
                GetWorldCoordinates = function() return 14, 0 end,
                GetCellBounds = function() return { tileSize = 640, playableCeiling = 4096 } end,
                GetMapPath = function(_, value) return value.map end,
                GetData = function() return { world = { seed = 1337 } } end
            },
            ZM_SafeZones = { IsSafeZoneCell = function() return state.safe == true end },
            ZM_PrefabGuardConfig = { ValidateDocument = function() return true end,
                PrepareDocumentGuard = function(guard) return guard end },
            ZM_DevConsole = { Report = function(_, name, value) state.report = { name = name, value = value } end },
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
        local vectorMeta = { __add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end }
        env.Vector = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local traceLine = env.util.TraceLine
        env.util.TraceLine = function(request)
            local result = traceLine(request)
            setmetatable(result.HitPos, vectorMeta)
            return result
        end
        env.string.Trim = function(value) return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")) end
        env.include = function(path)
            if path == "prefabs/sh_contract.lua" then
                return { IsValidId = function(id) return type(id) == "string" and id:match("^[a-z0-9_]+$") ~= nil end }
            end
            if path == "prefabs/sv_loot.lua" then return function() return { Validate = function() return true end } end end
            if path == "prefabs/sh_particle_catalog.lua" then
                return function() return { Validate = function() return true end } end
            end
            if path == "prefabs/sh_fixture_trace.lua" then return function() return {
                Sample = function(entity)
                    if entity == state.traceFailure then return nil, "fixture trace failed" end
                    return { entity = entity }
                end
            } end end
            if path == "prefabs/sv_catalog.lua" then return function() return catalog end end
            assert(path == "prefabs/sv_spawn.lua")
            return function() return spawn end
        end
        env.hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        env.timer = { Simple = function(delay, callback) assert(delay == 0); state.timers[#state.timers + 1] = callback end }
        function state:AddAnchor(id, keys)
            local anchor = { ZM_Config = keys or { prefab_tags = "road, motorway" }, MapCreationID = function() return id end }
            function anchor:CallOnRemove(_, callback) self.onRemove = callback end
            function anchor:Fire(input, value, delay) self.fired = { input, value, delay } end
            self.anchors[#self.anchors + 1] = anchor
        end
        local chunk = loadChunk("sv_prefabs.lua")
        setfenv(chunk, env)
        chunk()
        return env.ZM_Prefabs, state, target, cell
    end

    suite:Add("world prefabs spawn without compiled anchors and restore on cleanup", function(check)
        local prefabs, state, target = fixture()
        state.documents = { { id = "unique", worldPlacement = {
            enabled = true, profile = "preview", cellX = 14, cellY = 0, tileX = -1, tileY = 2,
            offset = { x = 10, y = -20, z = 5 }, angles = { p = 0, y = 90, r = 0 } } } }
        local ok = prefabs:OnPlayerReady(target)
        check(ok == nil and #state.created == 0, "placements wait for map initialization")
        state.hooks.InitPostEntity(); state.timers[1]()
        local instance = prefabs.Instances and prefabs.Instances.world_unique
        check(instance and #state.created == 1 and #state.choices == 0
            and instance.anchor.position.x == -630 and instance.anchor.position.y == 1260
            and instance.anchor.position.z == 41 and instance.anchor.angles.y == 90,
            "exact cell uses the tile surface and XYZ offset, bypassing tag selection")
        check(state.traces[1].start.x == -640 and state.traces[1].start.y == 1280
            and state.propsAtLoot == 1, "surface detection precedes entities and loot")
        prefabs:OnPlayerReady(target)
        check(#state.created == 1, "another ready player cannot duplicate the placement")
        local oldAnchor = instance.anchor
        state.hooks.PreCleanupMap()
        check(not oldAnchor.valid and state.created[1].removed, "cleanup removes both the owned anchor and its content")
        state.hooks.PostCleanupMap(); state.timers[#state.timers]()
        check(#state.created == 2 and prefabs.Instances.world_unique.anchor ~= oldAnchor,
            "map cleanup restores one fresh authored placement")
        state.hooks.PreCleanupMap()
        state.documents[1].worldPlacement.enabled = false
        state.hooks.PostCleanupMap(); state.timers[#state.timers]()
        check(#state.created == 2 and prefabs:GetStatus().anchors == 0, "disabled exports no longer spawn")
    end)

    suite:Add("world placements fail explicitly on missing surfaces or anchor creation", function(check)
        local prefabs, state = fixture()
        state.documents = { { id = "unique", worldPlacement = {
            enabled = true, profile = "preview", cellX = 14, cellY = 0, tileX = 0, tileY = 0,
            offset = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 } } } }
        state.noSurface = true
        local ok, problem = prefabs:SpawnForCell(42)
        check(ok == false and string.find(problem, "solid surface", 1, true) and #state.created == 0,
            "missing surfaces do not create or silently relocate a prefab")
        state.noSurface, state.failWorldAnchor = false, true
        ok, problem = prefabs:SpawnForCell(42)
        check(ok == false and string.find(problem, "create world prefab", 1, true) and #state.created == 0,
            "anchor creation failures are explicit")
        state.failWorldAnchor = false
        state.documents[1].worldPlacement.cellX = 15
        check(prefabs:SpawnForCell(42) and #state.created == 0,
            "another logical cell using the same BSP cannot receive the placement")
    end)

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
    suite:Add("loot waits until every deferred guard is ready", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(101)
        state:AddAnchor(102)
        state.pendingAnchors[101], state.pendingAnchors[102] = true, true
        state.hooks.InitPostEntity()
        state.timers[1]()
        check(owner:GetStatus().pending == 2 and state.lootCalls == nil
            and owner:OnPlayerReady(target) == nil, "pending guards block loot for early and later players")
        local ok, problem = owner:TriggerParticle(state.anchors[1], "burst")
        check(not ok and type(problem) == "string" and state.sent == nil,
            "a pending anchor cannot emit triggered particles")
        state.pendingCallbacks[101](true)
        check(owner:GetStatus().pending == 1 and state.lootCalls == nil,
            "one ready guard does not unblock another pending guard")
        state.pendingCallbacks[102](true)
        local status = owner:GetStatus()
        check(status.pending == 0 and status.guards == 2 and status.props == 0
            and state.lootCalls == 1 and owner:OnPlayerReady(target),
            "loot resumes once after every guard is ready")
    end)
    suite:Add("failed or removed pending guards unblock loot without partial prefabs", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(201)
        state.pendingAnchors[201] = true
        state.hooks.InitPostEntity()
        state.timers[1]()
        state.pendingCallbacks[201](false, "missing guard animation")
        local ok, problem = owner:OnPlayerReady(target)
        check(ok == false and string.find(problem, "missing guard animation", 1, true)
            and state.created[1].removed and owner:GetStatus().anchors == 0 and state.lootCalls == 1,
            "failed initialization removes the instance, reports the cause and resumes ordinary loot")
        local owner2, state2 = fixture()
        state2:AddAnchor(202)
        state2.pendingAnchors[202] = true
        state2.hooks.InitPostEntity()
        state2.timers[1]()
        state2.anchors[1].onRemove(state2.anchors[1])
        check(owner2:GetStatus().pending == 0 and owner2:GetStatus().anchors == 0
            and state2.created[1].removed and state2.lootCalls == 1,
            "removing the pending anchor releases the wait and its entities")
        state2.pendingCallbacks[202](false, "late callback")
        check(state2.lootCalls == 1 and owner2:GetStatus().error == nil,
            "late callbacks cannot alter or reinitialize the removed anchor")
    end)
    suite:Add("map cleanup ignores late guard initialization callbacks", function(check)
        local owner, state = fixture()
        state:AddAnchor(301)
        state.pendingAnchors[301] = true
        state.hooks.InitPostEntity()
        state.timers[1]()
        state.hooks.PreCleanupMap()
        state.pendingCallbacks[301](false, "late callback")
        check(not owner.Ready and owner.Instances == nil and state.created[1].removed
            and state.lootCalls == nil and #state.errors == 0,
            "cleanup removes pending entities and late callbacks cannot revive or fail the old map")
    end)
    suite:Add("client light status requests require a connected admin", function(check)
        local _, state, target = fixture()
        local ok = state.statusCommand(nil, "zombiesim_prefab_lights_status", {})
        check(ok and state.report and state.report.name == "prefabLightStatus"
            and state.clientCommand == "zombiesim_prefab_lights_status_client " .. state.report.value.requestId,
            "status request reports an ID and forwards it to the client")
        target.admin = false
        state.clientCommand = nil
        ok = state.statusCommand(nil, "zombiesim_prefab_lights_status", {})
        check(not ok and state.clientCommand == nil, "non-admin targets cannot receive status requests")
    end)
    suite:Add("anchor triggers only the requested one-shot particle", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        owner.Ready = true
        owner:OnPlayerReady(target)
        owner.Instances[1234].entities.particles = {
            steam_1 = { id = "1234:steam_1", effect = "steam", mode = "triggered", overlap = true,
                position = { x = 1, y = 2, z = 3 }, angles = { p = 4, y = 5, r = 6 } },
            steam_2 = { id = "1234:steam_2", effect = "steam", mode = "continuous", overlap = false }
        }
        local anchor = state.anchors[1]
        local ok = owner:TriggerParticle(anchor, "steam_1")
        check(ok and state.networkNames["ZM.PrefabParticle.Trigger"] and state.sent == 1
            and state.packet.values[1] == "1234:steam_1" and state.packet.values[2] == "steam"
            and state.packet.values[3] == 1 and state.packet.values[8] == 6 and state.packet.values[9] == true,
            "requested ID broadcasts its own transform and overlap setting")
        check(not owner:TriggerParticle(anchor, "steam_2") and not owner:TriggerParticle(anchor, "missing")
            and not owner:TriggerParticle(anchor, "../bad") and state.sent == 1,
            "continuous, missing and invalid IDs cannot broadcast")
        anchor.onRemove(anchor)
        check(not owner:TriggerParticle(anchor, "steam_1") and state.sent == 2
            and state.packet.name == "ZM.PrefabParticle.Stop" and state.packet.values[1] == "1234:steam_1",
            "anchor removal stops active bursts and prevents stale triggers")
        state.hooks.PreCleanupMap()
        check(state.sent == 2, "subsequent map cleanup does not send duplicate stop messages")
    end)
    suite:Add("fixture input command is guarded and addresses one anchor", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        owner.Ready = true
        owner:OnPlayerReady(target)
        owner.Instances[1234].entities.particles = {
            burst = { id = "1234:burst", mode = "triggered" },
            continuous = { id = "1234:continuous", mode = "continuous" }
        }
        check(not state.statusCommand(nil, "zombiesim_prefab_fixture_particle_trigger", { "1234", "burst" }),
            "ordinary maps cannot use the fixture trigger")
        state.fixture, state.participant = true, true
        target.ZM_PersistentStateLoaded = false
        check(state.statusCommand(nil, "zombiesim_prefab_fixture_particle_trigger", { "1234", "burst" })
            and state.anchors[1].fired[1] == "TriggerParticle" and state.anchors[1].fired[2] == "burst",
            "fixture trigger queues the engine input for the selected particle")
        check(not state.statusCommand(nil, "zombiesim_prefab_fixture_particle_trigger", { "1234", "continuous" })
            and not state.statusCommand(nil, "zombiesim_prefab_fixture_particle_trigger", { "1234", "missing" }),
            "continuous and unknown particle IDs are rejected")
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
    suite:Add("fixture traces forward the actual prop count and report failures", function(check)
        local owner, state, target = fixture()
        state.fixture, state.participant, state.map = true, true, "zn_dev_prefab_anchor"
        target.ZM_PersistentStateLoaded = false
        local props = { {}, {}, {}, {}, {} }
        owner.Instances = { bench = { entities = props } }
        local ok = state.statusCommand(nil, "zombiesim_prefab_fixture_trace", {})
        check(ok and state.clientCommand == "zombiesim_dev_prefab_fixture_trace_client 10000 compare 5"
            and #state.report.value.samples == 5 and #state.report.value.errors == 0,
            "five server props request five client samples")
        state.traceFailure = props[1]
        ok = state.statusCommand(nil, "zombiesim_prefab_fixture_trace", { "activate_client" })
        check(not ok and state.clientCommand == "zombiesim_dev_prefab_fixture_trace_client 10000 activate_client 5"
            and #state.report.value.samples == 4 and #state.report.value.errors == 1,
            "a server trace error remains explicit and retains the expected count")
        owner.Instances = {}
        state.clientCommand = nil
        ok = state.statusCommand(nil, "zombiesim_prefab_fixture_trace", {})
        check(not ok and state.clientCommand == nil, "an empty fixture cannot report a successful comparison")
        state.fixture = false
        owner.Instances = { bench = { entities = props } }
        ok = state.statusCommand(nil, "zombiesim_prefab_fixture_trace", {})
        check(not ok and state.clientCommand == nil, "other maps cannot invoke fixture traces")
    end)
    suite:Add("synthetic guard fixture reports pending separately from failure", function(check)
        local owner, state, target = fixture()
        state:AddAnchor(1234)
        state.pendingAnchors[1234] = true
        owner.Ready = true
        target.ZM_PersistentStateLoaded = false
        state.fixture, state.participant, state.map = true, true, "zn_dev_prefab_anchor"
        local ok, message = state.statusCommand(nil, "zombiesim_prefab_fixture_spawn")
        check(ok and message == nil and state.report and state.report.name == "prefabFixtureSpawn"
            and state.report.value.state == "pending" and state.report.value.pending == 1
            and owner:GetStatus().pending == 1,
            "fixture start reports pending initialization without a misleading bridge error")
        state.pendingCallbacks[1234](true)
        check(owner:GetStatus().pending == 0, "the fixture publishes completion after its guard is ready")
    end)
    return suite
end
