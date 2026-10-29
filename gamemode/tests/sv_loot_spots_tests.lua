// Server-only tests for world loot spots. Uses fake entities/players and throwaway profiles; never touches live spots.
local Spots = ZM_LootSpots
local Generation = ZM_ItemGeneration

local testProfile = "zn_test_loot"
local otherProfile = "zn_test_loot_other"
local testCell = 424242
local testOwners = {}
local nextTestOwner = 0

local function fakeEntity(position)
    return {
        position = position or Vector(0, 0, 0),
        IsValid = function() return true end,
        WorldSpaceCenter = function(self) return self.position end,
        GetPos = function(self) return self.position end,
        NearestPoint = function(self) return self.position end
    }
end

local function fakePlayer(position)
    nextTestOwner = nextTestOwner + 1
    local owner = "zn_test_loot_owner_" .. nextTestOwner
    testOwners[#testOwners + 1] = owner
    return {
        position = position or Vector(0, 0, 0),
        alive = true,
        items = {},
        ZM_InventoryProfile = testProfile,
        ZM_Inventory = ZM_InventoryService.NewInventory(),
        GetCharacterKey = function() return owner end,
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        Alive = function(self) return self.alive end,
        WorldSpaceCenter = function(self) return self.position end,
        GetLevel = function() return 5 end,
        GiveItemInstance = function(self, instance)
            table.insert(self.items, instance)
            return true
        end
    }
end

local function certainRule()
    return {
        // Test-only value 2 becomes a guaranteed searchable activation after the production 0.5 scale.
        activationChance = 2,
        entries = { { item = "itemBandage", minWeight = 1, maxWeight = 1, minCount = 1, maxCount = 1, mastercraft = false, mastercraftChance = 0 } }
    }
end

local function candidates(count, rule)
    local list = {}
    for index = 1, count do
        table.insert(list, { key = "m" .. index, rule = rule or certainRule(), entity = fakeEntity(Vector(index * 1000, 0, 0)) })
    end
    return list
end

local function cleanup()
    ZM_DeleteLootCells(testProfile)
    ZM_DeleteLootCells(otherProfile)
    for _, owner in ipairs(testOwners) do
        ZM_DeletePlayerItems(owner, testProfile)
        ZM_DeletePlayerItems(owner, otherProfile)
    end
    testOwners = {}
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("fingerprinted_cold_start_has_revision_helpers_before_any_generation", function(check)
    check(type(ZM_PrepareLootCellMapRevision) == "function"
        and type(ZM_GetLootCellBackups) == "function"
        and type(ZM_RestoreLootCellBackup) == "function",
        "map revision helpers exist before the first loot cell replacement")
    local loaded, loadError = Spots:LoadCell(testProfile, testCell, candidates(1), {
        now = 900, mapFingerprint = "zz_preview_cold_start", rng = Generation.NewRng(6)
    })
    check(loaded and loaded.regenerated, "first fingerprinted generation loads: " .. tostring(loadError))
end)

test("entity_rules_match_by_runtime_class_and_model", function(check)
    local rule = ZM_StaticData:GetEntityLootRule("prop_physics", "models/props_vehicles/car001b_phy.mdl")
    check(rule ~= nil, "a shipped car model should match as prop_physics")
    check(ZM_StaticData:GetEntityLootRule("prop_physics_override", "MODELS\\props_vehicles\\CAR001B_PHY.mdl") == rule, "override classes and model case/slashes normalize")
    check(ZM_StaticData:GetEntityLootRule("prop_static", "models/props_vehicles/car001b_phy.mdl") == nil, "static props never match")
    check(ZM_StaticData:GetEntityLootRule("prop_dynamic", "models/props_vehicles/car001b_phy.mdl") ~= nil, "default rules cover prop_dynamic")
    check(ZM_StaticData:GetEntityLootRule("prop_physics", "models/props_junk/trashdumpster01a.mdl") == nil, "a rule limited to prop_dynamic does not match prop_physics")
    check(ZM_StaticData:GetEntityLootRule("prop_physics", "models/not_lootable.mdl") == nil, "unlisted models are not lootable")
end)

test("semantic_container_rules_limit_loot_to_intended_families", function(check)
    local vending = ZM_StaticData:GetEntityLootRule("prop_dynamic", "models/props/cs_office/vending_machine.mdl")
    check(vending ~= nil and #vending.entries > 0, "the explicit vending model has drink loot")
    for _, entry in ipairs(vending and vending.entries or {}) do
        local item = ZM_StaticData:GetItem(entry.item)
        check(item and item.food and item.food.hydration > 0, "vending loot contains hydrating food only")
    end

    local ammo = ZM_StaticData:GetEntityLootRule("prop_physics", "models/items/ammocrate_pistol.mdl")
    check(ammo ~= nil and #ammo.entries > 0, "the explicit ammo crate has military loot")
    for _, entry in ipairs(ammo and ammo.entries or {}) do
        local item = ZM_StaticData:GetItem(entry.item)
        check(item and (item.lootCategory == "weapons" or item.lootCategory == "ammo"), "military containers yield only weapons or ammunition")
    end

    local crate = ZM_StaticData:GetEntityLootRule("prop_physics", "models/props_junk/wood_crate001a.mdl")
    check(crate ~= nil and #crate.entries > 0, "the ordinary crate has general supplies")
    local hasSuit = false
    for _, entry in ipairs(crate and crate.entries or {}) do
        local item = ZM_StaticData:GetItem(entry.item)
        hasSuit = hasSuit or entry.item == "itemRadiationSuit"
        check(item and (item.food or item.medical or item.lootCategory == "medical" or item.lootCategory == "materials"
            or entry.item == "itemRadiationSuit"), "ordinary crates contain supplies and the approved suit, not weapons, cash, or implants")
    end
    check(hasSuit, "ordinary crates retain the approved radiation-suit drop")

    check(ZM_StaticData:GetEntityLootRule("prop_physics", "models/props_junk/trafficcone001a.mdl") == nil, "an unsupported generic prop does not fall through to loot")
end)

test("ragdoll_rules_match_bodies_only", function(check)
    local civilian = ZM_StaticData:GetEntityLootRule("prop_ragdoll", "models/humans/group01/male_01.mdl")
    check(civilian ~= nil and #civilian.entries > 0, "a civilian body has loot")
    check(civilian and civilian.lootGroups[1] == "lootBodyCivilian", "civilian bodies use the civilian body group")
    local rebel = ZM_StaticData:GetEntityLootRule("prop_ragdoll", "models/humans/group03/male_01.mdl")
    local hasWeaponOrAmmo = false
    for _, entry in ipairs(rebel and rebel.entries or {}) do
        local item = ZM_StaticData:GetItem(entry.item)
        if item and (item.lootCategory == "weapons" or item.lootCategory == "ammo") then
            hasWeaponOrAmmo = true
        end
    end
    check(hasWeaponOrAmmo, "rebel bodies favour weapons and ammunition")
    check(ZM_StaticData:GetEntityLootRule("prop_physics", "models/humans/group01/male_01.mdl") == nil, "a body rule does not match physics props")
    check(ZM_StaticData:GetEntityLootRule("prop_ragdoll", "models/not_a_body.mdl") == nil, "unlisted ragdolls are not lootable")
end)

test("spot_keys_cover_bodies_but_never_enemy_corpses", function(check)
    local body = { ZM_LootSpotKey = "b1_07", MapCreationID = function() return -1 end }
    check(Spots.GetSpotKey(body) == "b1_07", "a fallen body uses its deterministic key")
    local corpse = { ZM_EnemyCorpse = true, MapCreationID = function() return 42 end }
    check(Spots.GetSpotKey(corpse) == nil, "an enemy corpse is never a generic candidate")
    local runtime = { MapCreationID = function() return -1 end }
    check(Spots.GetSpotKey(runtime) == nil, "other runtime props are never spots")
    check(Spots.GetSpotKey({ MapCreationID = function() return 12 end }) == "m12", "map props keep their map key")
end)

local function targetingPlayer(aimed)
    local ply = fakePlayer(Vector(0, 0, 0))
    ply.GetLevelAimTrace = function() return { Entity = aimed } end
    return ply
end

local function withTargeting(nearby, obstructed, body)
    local Targeting = ZM_LootTargeting
    local findNearby, isObstructed = Targeting.FindNearby, Targeting.IsObstructed
    Targeting.FindNearby = function() return nearby end
    Targeting.IsObstructed = function(_, entity) return obstructed[entity] == true end
    local ok, problem = pcall(body)
    Targeting.FindNearby, Targeting.IsObstructed = findNearby, isObstructed
    if not ok then
        error(problem, 0)
    end
end

test("targeting_prefers_the_aimed_spot_and_reports_why_it_cannot_be_searched", function(check)
    local Targeting = ZM_LootTargeting
    local near = fakeEntity(Vector(40, 0, 0))
    local aimed = fakeEntity(Vector(90, 0, 0))
    local far = fakeEntity(Vector(400, 0, 0))
    local states = { [near] = "available", [aimed] = "declined", [far] = "available" }
    local stateOf = function(entity) return states[entity] end
    withTargeting({ near, aimed, far }, {}, function()
        local chosen = Targeting.Select(targetingPlayer(aimed), stateOf)
        check(chosen and chosen.entity == aimed and chosen.aimed and not chosen.reason, "an aimed spot in range beats the nearest one")
        chosen = Targeting.Select(targetingPlayer(nil), stateOf)
        check(chosen and chosen.entity == near and not chosen.aimed, "without an aimed spot the nearest searchable spot is used")
        states[near] = "looted"
        chosen = Targeting.Select(targetingPlayer(far), stateOf)
        check(chosen and chosen.entity == aimed and not chosen.reason, "an unusable aimed spot falls back to a searchable one in range")
        states[aimed] = "looted"
        chosen = Targeting.Select(targetingPlayer(far), stateOf)
        check(chosen and chosen.entity == far and chosen.reason == "far", "an aimed spot out of range reports far")
        chosen = Targeting.Select(targetingPlayer(aimed), stateOf)
        check(chosen and chosen.reason == "empty", "an aimed looted spot reports empty")
        check(Targeting.Select(targetingPlayer(nil), stateOf) == nil, "nothing is selected when no spot is searchable")
    end)
    states[near] = "available"
    withTargeting({ near }, { [near] = true }, function()
        local chosen = Targeting.Select(targetingPlayer(near), stateOf)
        check(chosen and chosen.reason == "blocked", "an obstructed aimed spot reports blocked")
        check(Targeting.Select(targetingPlayer(nil), stateOf) == nil, "an obstructed spot is never the nearest fallback")
    end)
end)

test("aimed_spot_lookup_excludes_nearby_fallbacks", function(check)
    local originalCell = Spots.Cell
    local corpse = fakeEntity(Vector(40, 0, 0))
    Spots.Cell = {
        spotsByEntity = {
            [corpse] = { key = "enemycorpse_test", state = "available", entity = corpse }
        }
    }
    local ok, errorMessage = pcall(function()
        withTargeting({ corpse }, {}, function()
            check(Spots:FindAimedSpot(targetingPlayer(corpse)) == Spots.Cell.spotsByEntity[corpse],
                "an explicitly aimed enemy corpse is identified for gate input priority")
            check(Spots:FindAimedSpot(targetingPlayer(nil)) == nil,
                "a nearby fallback spot does not suppress intentional gate travel")
        end)
    end)
    Spots.Cell = originalCell
    if not ok then error(errorMessage) end
end)

test("fallen_body_plans_are_deterministic", function(check)
    local Bodies = ZM_LootBodies
    local pool = {
        { group = "lootBodyCivilian", weight = 3, models = { "models/humans/group01/male_01.mdl" } },
        { group = "lootBodyBird", weight = 1, models = { "models/crow.mdl" } }
    }
    local bounds = { minimum = Vector(-4096, -4096, -512), maximum = Vector(4096, 4096, 1024) }
    local ground = function(x, y)
        return { Hit = true, HitSky = false, HitNormal = Vector(0, 0, 1), HitTexture = "concrete/floor", HitPos = Vector(x, y, 0) }
    end
    local open = function() return false end
    local first = Bodies.Plan(Generation.NewRng(99), bounds, pool, ground, open)
    local second = Bodies.Plan(Generation.NewRng(99), bounds, pool, ground, open)
    check(#first >= Bodies.MinCount and #first <= Bodies.MaxCount, "a cell gets the configured number of bodies")
    local same = #first == #second
    for index, plan in ipairs(first) do
        local other = second[index]
        same = same and other and other.key == plan.key and other.model == plan.model and other.position == plan.position
        check(string.match(plan.key, "^b%d+_%d+$") ~= nil, "body keys are deterministic spot keys")
        check(plan.position.x >= bounds.minimum.x + Bodies.MapEdgeMargin
            and plan.position.x <= bounds.maximum.x - Bodies.MapEdgeMargin
            and plan.position.y >= bounds.minimum.y + Bodies.MapEdgeMargin
            and plan.position.y <= bounds.maximum.y - Bodies.MapEdgeMargin,
            "body placement stays outside the inaccessible map-edge margin")
        for otherIndex = index + 1, #first do
            check(plan.position:Distance(first[otherIndex].position) >= Bodies.MinSpacing, "bodies keep their spacing")
        end
    end
    check(same, "the same seed recreates the same bodies under the same keys")
    local legacy = Bodies.Plan(Generation.NewRng(99), bounds, pool, ground, open, Bodies.LegacyPolicy)
    check(#legacy >= 2 and #legacy <= 4 and string.StartWith(legacy[1].key, "b1_"),
        "an unexpired legacy loot generation recreates its original body policy")
    check(#first >= 1 and #first <= 2 and string.StartWith(first[1].key, "b2_"),
        "new and refreshed generations use the 1-2 body policy")
    local sky = function(x, y)
        local trace = ground(x, y)
        trace.HitSky = true
        return trace
    end
    check(#Bodies.Plan(Generation.NewRng(99), bounds, pool, sky, open) == 0, "sky and unsuitable ground never receive bodies")
end)

test("searchable_generation_is_order_independent_and_spaces_actual_centres", function(check)
    local rule = certainRule()
    rule.activationChance = 1
    local source = {
        { key = "m3", rule = rule, entity = fakeEntity(Vector(320, 0, 0)), center = Vector(320, 0, 0) },
        { key = "b2_01", rule = rule, entity = fakeEntity(Vector(0, 0, 320)), center = Vector(0, 0, 320) },
        { key = "m2", rule = rule, entity = fakeEntity(Vector(319.999, 0, 0)), center = Vector(319.999, 0, 0) },
        { key = "m1", rule = rule, entity = fakeEntity(Vector(0, 0, 0)), center = Vector(0, 0, 0) }
    }
    local function acceptingRng()
        local priority = 0
        return {
            Chance = function(_, chance)
                check(chance == 0.5, "original activation probability is halved once")
                return true
            end,
            Next = function()
                priority = priority + 0.1
                return priority
            end
        }
    end
    local first = Spots.SelectActiveCandidates(source, acceptingRng())
    local reversed = {}
    for index = #source, 1, -1 do table.insert(reversed, source[index]) end
    local second = Spots.SelectActiveCandidates(reversed, acceptingRng())
    local firstKeys, secondKeys = {}, {}
    for _, candidate in ipairs(first) do table.insert(firstKeys, candidate.key) end
    for _, candidate in ipairs(second) do table.insert(secondKeys, candidate.key) end
    check(table.concat(firstKeys, ",") == table.concat(secondKeys, ","),
        "entity enumeration order cannot change the selected set")
    check(table.HasValue(firstKeys, "m1") and not table.HasValue(firstKeys, "m2"),
        "319.999 units is rejected")
    check(table.HasValue(firstKeys, "m3"), "exactly 320 units is accepted")
    check(table.HasValue(firstKeys, "b2_01"), "3D spacing accepts a body on a separate floor at 320 units")
end)

test("activation_generates_and_persists_spots", function(check)
    local rule = certainRule()
    local never = { activationChance = 0, entries = rule.entries }
    local list = {
        { key = "m1", rule = rule, entity = fakeEntity(), center = Vector(0, 0, 0) },
        { key = "m2", rule = never, entity = fakeEntity(Vector(1000, 0, 0)), center = Vector(1000, 0, 0) }
    }
    local rng = { Chance = function(_, chance) return chance > 0 end, Next = function() return 0 end }
    local cell = Spots:LoadCell(testProfile, testCell, list, { now = 1000, rng = rng })
    check(cell and cell.regenerated, "a new cell is generated")
    check(cell.spots.m1 and not cell.spots.m2, "activation chance 1 activates and 0 never does")
    local rows = ZM_GetLootSpots(testProfile, testCell)
    check(#rows == 1 and rows[1].spotKey == "m1" and rows[1].state == "available", "the active spot is stored")
end)

test("guaranteed_prefab_spots_bypass_roll_and_spacing_without_suppressing_ordinary_loot", function(check)
    local rule = certainRule()
    local list = {
        { key = "m1", rule = rule, entity = fakeEntity(), center = Vector(0, 0, 0) },
        { key = "p1_a_a", rule = rule, entity = fakeEntity(), center = Vector(0, 0, 0), guaranteed = true },
        { key = "p1_a_b", rule = rule, entity = fakeEntity(), center = Vector(0, 0, 0), guaranteed = true }
    }
    local rolls = 0
    local rng = { Chance = function() rolls = rolls + 1; return true end, Next = function() return 0 end }
    local selected = Spots.SelectActiveCandidates(list, rng)
    check(#selected == 3 and rolls == 1, "guaranteed spots consume no roll or spacing slots")
    rng.Chance = function() return false end
    selected = Spots.SelectActiveCandidates(list, rng)
    check(#selected == 2 and selected[1].key == "p1_a_a" and selected[2].key == "p1_a_b",
        "guaranteed spots remain active when the ordinary roll fails")
end)

test("prefab_candidates_use_their_own_rules_and_guaranteed_overhangs", function(check)
    local rule = certainRule()
    local function prefab(key, position, guaranteed)
        local entity = fakeEntity(position)
        entity.ZM_LootSpotKey = key
        entity.ZM_PrefabLoot = { rule = rule, guaranteed = guaranteed }
        entity.GetClass = function() return "prop_physics" end
        entity.GetModel = function() return "models/props_c17/oildrum001.mdl" end
        entity.MapCreationID = function() return -1 end
        return entity
    end
    local guaranteed = prefab("p1_a_a", Vector(500, 0, 0), true)
    local normal = prefab("p1_a_b", Vector(0, 0, 0), false)
    local outside = prefab("p1_a_c", Vector(500, 0, 0), false)
    local off = fakeEntity(Vector(0, 0, 0))
    off.GetClass = function() return "prop_physics" end
    off.GetModel = function() return "models/props_c17/oildrum001.mdl" end
    off.MapCreationID = function() return -1 end
    local oldEntities = ents.GetAll
    local oldBounds, oldMaps, oldCore = ZM_World.GetCellBounds, ZM_World.GetCellsForMap, ZM_World.IsCoreSpawnPosition
    ents.GetAll = function() return { guaranteed, normal, outside, off } end
    ZM_World.GetCellBounds = function() return { revision = 2 } end
    ZM_World.GetCellsForMap = function() return {} end
    ZM_World.IsCoreSpawnPosition = function(_, position) return position.x == 0 end
    local called, found = pcall(Spots.FindCandidates, Spots)
    ents.GetAll = oldEntities
    ZM_World.GetCellBounds, ZM_World.GetCellsForMap, ZM_World.IsCoreSpawnPosition = oldBounds, oldMaps, oldCore
    check(called and #found == 2, "only the normal core prop and guaranteed overhanging prop are candidates")
    if not called or #found ~= 2 then return end
    check(found[1].key == "p1_a_a" and found[1].guaranteed and found[1].rule == rule
        and found[2].key == "p1_a_b" and not found[2].guaranteed,
        "explicit prefab rules and guaranteed state reach the loot owner")
end)

test("guaranteed_prefab_spots_merge_without_resetting_saved_state", function(check)
    local ordinary = candidates(1)
    local first = Spots:LoadCell(testProfile, testCell, ordinary, { now = 1000, rng = Generation.NewRng(12) })
    check(first and first.spots.m1, "existing ordinary loot generation is created")
    ZM_SetLootSpot(testProfile, testCell, "m1", "looted", nil)
    local guaranteed = { key = "p1234_fixture_p_one", rule = certainRule(), entity = fakeEntity(),
        center = Vector(0, 0, 0), guaranteed = true }
    table.insert(ordinary, guaranteed)
    local merged, problem = Spots:LoadCell(testProfile, testCell, ordinary, { now = 1010 })
    check(merged and merged.spots.m1 and merged.spots.m1.state == "looted"
        and merged.spots[guaranteed.key] and merged.spots[guaranteed.key].state == "available",
        "a new guaranteed spot is added without resetting ordinary loot: " .. tostring(problem))
    ZM_SetLootSpot(testProfile, testCell, guaranteed.key, "looted", nil)
    local repeated = Spots:LoadCell(testProfile, testCell, ordinary, { now = 1020 })
    check(repeated and repeated.spots[guaranteed.key] and repeated.spots[guaranteed.key].state == "looted"
        and #ZM_GetLootSpots(testProfile, testCell) == 2, "repeat loads cannot grant the same spot twice")
    local other = Spots:LoadCell(otherProfile, testCell, ordinary, { now = 1000, rng = Generation.NewRng(13) })
    check(other and other.spots[guaranteed.key] and other.spots[guaranteed.key].state == "available",
        "guaranteed spot state remains profile-scoped")
end)

test("guaranteed_prefab_merge_failure_preserves_existing_rows", function(check)
    local list = candidates(1)
    Spots:LoadCell(testProfile, testCell, list, { now = 1000, rng = Generation.NewRng(14) })
    ZM_SetLootSpot(testProfile, testCell, "m1", "looted", nil)
    table.insert(list, { key = "p1234_fixture_p_one", rule = certainRule(), entity = fakeEntity(),
        center = Vector(0, 0, 0), guaranteed = true })
    local originalQuery, originalLastError = sql.Query, sql.LastError
    sql.Query = function(query)
        if string.find(query, "INSERT OR IGNORE INTO loot_spots", 1, true) then return false end
        return originalQuery(query)
    end
    sql.LastError = function() return "injected guaranteed-spot failure" end
    local called, loaded, problem = pcall(Spots.LoadCell, Spots, testProfile, testCell, list, { now = 1010 })
    sql.Query, sql.LastError = originalQuery, originalLastError
    local rows = ZM_GetLootSpots(testProfile, testCell)
    check(called and not loaded and string.find(tostring(problem), "injected", 1, true),
        "failed guaranteed insertion reports its error")
    check(#rows == 1 and rows[1].spotKey == "m1" and rows[1].state == "looted",
        "failed insertion rolls back without resetting existing loot")
end)

test("refresh_waits_for_five_minutes_of_absence", function(check)
    local list = candidates(2)
    Spots:LoadCell(testProfile, testCell, list, { now = 1000 })
    ZM_SetLootSpot(testProfile, testCell, "m1", "looted", nil)
    local early = Spots:LoadCell(testProfile, testCell, list, { now = 1000 + Spots.RefreshSeconds - 1 })
    check(not early.regenerated and early.spots.m1.state == "looted", "a looted spot stays empty before the refresh time")
    local touched = tonumber(ZM_GetLootCell(testProfile, testCell).lastPresentAt)
    check(touched == 1000 + Spots.RefreshSeconds - 1, "loading the cell records presence")
    local late = Spots:LoadCell(testProfile, testCell, list, { now = touched + Spots.RefreshSeconds })
    check(late.regenerated and late.spots.m1.state == "available", "after five minutes away every spot re-rolls")
    local forced = Spots:LoadCell(testProfile, testCell, list, { now = touched + Spots.RefreshSeconds + 1, forceRegenerate = true })
    check(forced.regenerated, "forceRegenerate re-rolls immediately")
end)

test("map_revision_reset_is_backed_up_scoped_and_repeat_safe", function(check)
    local list = candidates(2)
    local first = Spots:LoadCell(testProfile, testCell, list, {
        now = 1000, mapFingerprint = "zz_preview_old", rng = Generation.NewRng(7)
    })
    check(first and first.regenerated, "old map generation is created")
    ZM_SetLootSpot(testProfile, testCell, "m1", "declined", { itemId = "itemBandage", count = 1 })
    local same = Spots:LoadCell(testProfile, testCell, list, { now = 1100, mapFingerprint = "zz_preview_old" })
    check(not same.regenerated and same.spots.m1.state == "declined", "same map revision preserves saved state")
    local rebuilt = Spots:LoadCell(testProfile, testCell, list, {
        now = 1200, mapFingerprint = "zz_preview_new", rng = Generation.NewRng(8)
    })
    check(rebuilt and rebuilt.regenerated and rebuilt.spots.m1.state == "available",
        "changed map revision generates fresh logical-cell spots")
    local backups = ZM_GetLootCellBackups(testProfile, testCell)
    check(#backups == 1 and backups[1].mapFingerprint == "zz_preview_old",
        "old map and loot rows are backed up together")
    ZM_SetLootSpot(testProfile, testCell, "m1", "looted", nil)
    local repeated = Spots:LoadCell(testProfile, testCell, list, { now = 1250, mapFingerprint = "zz_preview_new" })
    check(not repeated.regenerated and repeated.spots.m1.state == "looted",
        "repeated load of rebuilt revision never resets twice")
    local other = Spots:LoadCell(otherProfile, testCell, list, {
        now = 1000, mapFingerprint = "zz_preview_other", rng = Generation.NewRng(9)
    })
    check(other and other.regenerated and #ZM_GetLootCellBackups(otherProfile, testCell) == 0,
        "map reset and backups remain profile scoped")
    local restored, restoreError = ZM_RestoreLootCellBackup(testProfile, testCell, "zz_preview_old")
    check(restored, "matching old map and loot backup restores: " .. tostring(restoreError))
    local restoredRows = ZM_GetLootSpots(testProfile, testCell)
    check(#restoredRows > 0 and restoredRows[1].state == "declined",
        "restoration recovers the old saved spot state")
end)

test("legacy_revision_baseline_and_reset_failure_preserve_saved_rows", function(check)
    local list = candidates(2)
    local legacy = Spots:LoadCell(testProfile, testCell, list, {
        now = 1000, rng = Generation.NewRng(10)
    })
    check(legacy and legacy.regenerated, "legacy row starts without map metadata")
    ZM_SetLootSpot(testProfile, testCell, "m1", "declined", { itemId = "itemBandage", count = 1 })
    local baselined = Spots:LoadCell(testProfile, testCell, list, {
        now = 1100, mapFingerprint = "zz_preview_baseline"
    })
    local baselineRow = ZM_GetLootCell(testProfile, testCell)
    check(not baselined.regenerated and baselined.spots.m1.state == "declined",
        "first fingerprint assignment preserves an existing saved generation")
    check(baselineRow and baselineRow.mapFingerprint == "zz_preview_baseline",
        "legacy row records the current revision after safe baselining")

    local originalQuery = sql.Query
    local originalLastError = sql.LastError
    sql.Query = function(query)
        if string.find(query, "DELETE FROM loot_spots", 1, true) then return false end
        return originalQuery(query)
    end
    sql.LastError = function() return "injected loot reset failure" end
    local called, reset, resetError = pcall(ZM_PrepareLootCellMapRevision,
        testProfile, testCell, "zz_preview_failed_rebuild", 1200)
    sql.Query = originalQuery
    sql.LastError = originalLastError

    check(called and reset == nil and string.find(tostring(resetError), "injected loot reset failure", 1, true),
        "SQL failure is returned explicitly")
    local preservedCell = ZM_GetLootCell(testProfile, testCell)
    local preservedSpots = ZM_GetLootSpots(testProfile, testCell)
    check(preservedCell and preservedCell.mapFingerprint == "zz_preview_baseline"
        and #preservedSpots == 2 and preservedSpots[1].state == "declined",
        "failed reset rolls back the backup and preserves old cell/spot rows")
    check(#ZM_GetLootCellBackups(testProfile, testCell) == 0,
        "failed reset does not commit a success-shaped backup")
end)

test("search_offer_accept_loots_the_spot", function(check)
    local list = candidates(1)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1000 }))
    local spot = Spots.Cell.spots.m1
    local survivor = fakePlayer(Vector(1000, 50, 0))
    check(Spots:BeginSearch(survivor, spot, 10), "a nearby player can start searching")
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(2))
    check(offer and offer.itemId == "itemBandage" and type(offer.token) == "string", "completing the search issues an offer")
    check(ZM_GetLootSpots(testProfile, testCell)[1].item ~= "NULL", "the rolled item is saved on the spot")
    local accepted, message = Spots:RespondOffer(survivor, offer.token, true, 13)
    check(accepted and message == "accepted", "accepting the offer succeeds")
    check(ZM_InventoryService:Count(survivor, "itemBandage", "backpack") == offer.count, "the item is given once")
    check(spot.state == "looted" and ZM_GetLootSpots(testProfile, testCell)[1].state == "looted", "the spot is looted and saved")
    local replay = Spots:RespondOffer(survivor, offer.token, true, 14)
    check(not replay and ZM_InventoryService:Count(survivor, "itemBandage", "backpack") == offer.count,
        "replaying the token gives nothing")
    check(not Spots:BeginSearch(survivor, spot, 15), "a looted spot cannot be searched again")
end)

test("decline_keeps_the_same_item_across_reloads", function(check)
    local list = candidates(1)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local first = Spots:CompleteSearch(survivor, 12, Generation.NewRng(3))
    local declined = Spots:RespondOffer(survivor, first.token, false, 13)
    check(declined and ZM_InventoryService:Count(survivor, "itemBandage", "backpack") == 0, "declining gives nothing")
    check(Spots.Cell.spots.m1.state == "declined", "a declined spot keeps its gray declined state")

    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1100 }))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 20)
    local second = Spots:CompleteSearch(survivor, 22, Generation.NewRng(999))
    check(second.itemId == first.itemId and second.count == first.count and second.level == first.level, "the same item is offered again after a reload")
    check(second.token ~= first.token, "each offer gets a new token")
    check(not Spots:RespondOffer(survivor, first.token, true, 23), "an old token is rejected")
    local accepted = Spots:RespondOffer(survivor, second.token, true, 24)
    check(accepted and ZM_InventoryService:Count(survivor, first.itemId, "backpack") == first.count,
        "a re-opened declined item can be accepted")
    check(Spots.Cell.spots.m1.state == "looted", "accepting a declined item marks the spot looted")
end)

test("claims_range_and_expiry_are_enforced", function(check)
    local list = candidates(1)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1000 }))
    local spot = Spots.Cell.spots.m1
    local first, second = fakePlayer(Vector(1000, 0, 0)), fakePlayer(Vector(1000, 20, 0))
    local distant = fakePlayer(Vector(5000, 0, 0))
    check(not Spots:BeginSearch(distant, spot, 10), "a distant player cannot search")
    check(Spots:BeginSearch(first, spot, 10), "the first player claims the spot")
    local blocked, reason = Spots:BeginSearch(second, spot, 10)
    check(not blocked and reason == "Someone else is searching this.", "a second player is blocked while claimed")

    first.position = Vector(5000, 0, 0)
    local offer, moved = Spots:CompleteSearch(first, 12)
    check(offer == nil and moved == "You moved too far away.", "moving away interrupts the search")
    check(Spots:BeginSearch(second, spot, 13), "the spot is free again after the interruption")
    local secondOffer = Spots:CompleteSearch(second, 15, Generation.NewRng(4))
    second.position = Vector(5000, 0, 0)
    check(not Spots:RespondOffer(second, secondOffer.token, true, 16), "accepting from far away is rejected")
    check(ZM_InventoryService:Count(second, "itemBandage", "backpack") == 0 and spot.state == "available",
        "a rejected accept changes nothing")

    first.position = Vector(1000, 0, 0)
    Spots:BeginSearch(first, spot, 20)
    local lateOffer = Spots:CompleteSearch(first, 22, Generation.NewRng(5))
    check(not Spots:RespondOffer(first, lateOffer.token, true, 22 + Spots.OfferSeconds + 1), "an expired offer is rejected")
    check(Spots:ClaimExpired(spot, 22 + Spots.OfferSeconds + 1), "the claim is released")
end)

test("full_backpack_keeps_the_spot_and_item", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(6))
    local sample = Spots.Cell.spots.m1.item
    for slot = 1, ZM_Items.ContainerCapacity.backpack do
        local full = table.Copy(sample)
        full.instanceId = "zn_test_full_" .. slot
        full.count = ZM_Items:GetDefinition(full.itemId).maxStack
        survivor.ZM_Inventory.backpack[slot] = full
    end
    local accepted, reason = Spots:RespondOffer(survivor, offer.token, true, 13)
    check(not accepted and string.find(reason, "Could not take the item", 1, true), "a failed grant reports why")
    check(Spots.Cell.spots.m1.state == "available" and Spots.Cell.spots.m1.item.itemId == offer.itemId, "the spot keeps its item")
end)

test("loot_claim_is_atomic_when_spot_save_fails", function(check)
    local list = candidates(1)
    list[1].guaranteed = true
    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(22))
    local originalQuery, originalLastError = sql.Query, sql.LastError
    sql.Query = function(query)
        if string.find(query, "UPDATE loot_spots SET state = 'looted'", 1, true) then return false end
        return originalQuery(query)
    end
    sql.LastError = function() return "injected loot claim failure" end
    local called, accepted, reason = pcall(Spots.RespondOffer, Spots, survivor, offer.token, true, 13)
    sql.Query, sql.LastError = originalQuery, originalLastError
    check(called and not accepted and string.find(tostring(reason), "injected", 1, true),
        "a spot write failure is reported")
    local rows = ZM_GetLootSpots(testProfile, testCell)
    local inventory = ZM_GetPlayerItems(survivor:GetCharacterKey(), testProfile)
    check(ZM_InventoryService:Count(survivor, offer.itemId, "backpack") == 0
        and inventory and #inventory == 0 and rows and rows[1].state == "available"
        and Spots.Cell.spots.m1.item ~= nil, "failed claim rolls back inventory and preserves the offered spot")
    check(Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 20), "the preserved spot can be searched again")
    local retry = Spots:CompleteSearch(survivor, 22, Generation.NewRng(23))
    local retried = retry and Spots:RespondOffer(survivor, retry.token, true, 23)
    check(retried and ZM_InventoryService:Count(survivor, offer.itemId, "backpack") == offer.count,
        "a later successful claim grants the item exactly once")
end)

test("loot_claim_rejects_stale_database_state", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(24))
    ZM_SetLootSpot(testProfile, testCell, "m1", "looted", nil)
    local accepted, reason = Spots:RespondOffer(survivor, offer.token, true, 13)
    check(not accepted and string.find(tostring(reason), "changed", 1, true)
        and ZM_InventoryService:Count(survivor, offer.itemId, "backpack") == 0,
        "a stale offer cannot grant an item after the persisted spot changes")
end)

test("loot_claim_rolls_back_if_inventory_write_fails", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(26))
    local originalQuery, originalLastError = sql.Query, sql.LastError
    sql.Query = function(query)
        if string.find(query, "INSERT INTO player_items", 1, true) then return false end
        return originalQuery(query)
    end
    sql.LastError = function() return "injected inventory failure" end
    local called, accepted, reason = pcall(Spots.RespondOffer, Spots, survivor, offer.token, true, 13)
    sql.Query, sql.LastError = originalQuery, originalLastError
    local rows = ZM_GetLootSpots(testProfile, testCell)
    check(called and not accepted and string.find(tostring(reason), "injected", 1, true),
        "inventory write failure is reported")
    check(ZM_InventoryService:Count(survivor, offer.itemId, "backpack") == 0
        and rows and rows[1].state == "available" and Spots.Cell.spots.m1.item ~= nil,
        "failed inventory write preserves the saved offer and live inventory")
end)

test("loot_claim_rejects_a_different_inventory_profile", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    survivor.ZM_InventoryProfile = otherProfile
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(27))
    local accepted, reason = Spots:RespondOffer(survivor, offer.token, true, 13)
    local rows = ZM_GetLootSpots(testProfile, testCell)
    check(not accepted and string.find(tostring(reason), "profiles differ", 1, true)
        and ZM_InventoryService:Count(survivor, offer.itemId, "backpack") == 0
        and rows and rows[1].state == "available", "profile mismatch cannot grant or consume loot")
end)

test("decline_reports_failed_save_without_changing_the_spot", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(25))
    local originalQuery, originalLastError = sql.Query, sql.LastError
    sql.Query = function(query)
        if string.find(query, "UPDATE loot_spots SET state = 'declined'", 1, true) then return false end
        return originalQuery(query)
    end
    sql.LastError = function() return "injected decline failure" end
    local called, declined, reason = pcall(Spots.RespondOffer, Spots, survivor, offer.token, false, 13)
    sql.Query, sql.LastError = originalQuery, originalLastError
    local rows = ZM_GetLootSpots(testProfile, testCell)
    check(called and not declined and string.find(tostring(reason), "injected", 1, true),
        "failed decline is reported")
    check(Spots.Cell.spots.m1.state == "available" and rows and rows[1].state == "available",
        "failed decline does not change the in-memory or stored state")
end)

test("missing_spot_and_failed_item_encoding_are_reported", function(check)
    Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 })
    local updated, problem = ZM_SetLootSpot(testProfile, testCell, "missing", "available", nil)
    check(not updated and type(problem) == "string", "updating a nonexistent row is not reported as success")
    local originalEncode = util.TableToJSON
    util.TableToJSON = function() return nil end
    local called, saved, encodeError = pcall(ZM_SetLootSpot, testProfile, testCell, "m1", "available", { itemId = "itemBandage" })
    util.TableToJSON = originalEncode
    local rows = ZM_GetLootSpots(testProfile, testCell)
    check(called and not saved and type(encodeError) == "string" and rows and rows[1].item == "NULL",
        "encoding failure is reported without replacing stored loot")
end)

test("declined_runtime_spot_can_be_reopened_without_a_database_row", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    local entity = fakeEntity(Vector(1000, 0, 0))
    local item = Generation:CreateInstance("itemBandage", { count = 1, level = 1 })
    local spot, problem = Spots:RegisterRuntimeSpot(entity, item, "temporary-fixture")
    check(spot ~= nil, "runtime spot registers: " .. tostring(problem))
    if not spot then return end
    check(Spots:BeginSearch(survivor, spot, 10), "runtime spot can be searched")
    local first = Spots:CompleteSearch(survivor, 12)
    check(first and Spots:RespondOffer(survivor, first.token, false, 13), "runtime offer can be declined")
    check(Spots:BeginSearch(survivor, spot, 20), "declined runtime spot can be searched again")
    local second, reopenError = Spots:CompleteSearch(survivor, 22)
    check(second and second.itemId == first.itemId, "runtime offer reopens without a stored row: " .. tostring(reopenError))
end)

test("profiles_and_cells_are_isolated", function(check)
    local list = candidates(2)
    Spots:LoadCell(testProfile, testCell, list, { now = 1000 })
    ZM_SetLootSpot(testProfile, testCell, "m1", "looted", nil)
    local other = Spots:LoadCell(otherProfile, testCell, list, { now = 1000 })
    check(other.regenerated and other.spots.m1.state == "available", "another profile has its own spots")
    local neighbour = Spots:LoadCell(testProfile, testCell + 1, list, { now = 1000 })
    check(neighbour.regenerated and neighbour.spots.m1.state == "available", "another cell has its own spots")
    ZM_DeleteLootCells(testProfile)
    check(#ZM_GetLootSpots(testProfile, testCell + 1) == 0, "cleanup removes the test rows")
end)

test("missing_entities_are_dropped_on_restore", function(check)
    local list = candidates(2)
    Spots:LoadCell(testProfile, testCell, list, { now = 1000 })
    local restored = Spots:LoadCell(testProfile, testCell, { list[1] }, { now = 1010 })
    check(restored.spots.m1 and not restored.spots.m2, "a stored spot without a matching entity is ignored")
end)

function Spots:RunTests()
    local previousCell = self.Cell
    local summary = suite:Run({ before = function() cleanup() self.Cell = nil end, after = cleanup })
    self.Cell = previousCell
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_loot_spots", label = "Loot spot", file = "loot_spot_tests.json", report = "lootSpotTests",
    help = "Runs the world loot spot tests against throwaway profiles.",
    run = function() return Spots:RunTests() end
})
