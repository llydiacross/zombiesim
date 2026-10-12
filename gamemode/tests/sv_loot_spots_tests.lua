// Server-only tests for world loot spots. Uses fake entities/players and throwaway profiles; never touches live spots.
local Spots = ZM_LootSpots
local Generation = ZM_ItemGeneration

local testProfile = "zn_test_loot"
local otherProfile = "zn_test_loot_other"
local testCell = 424242

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
    return {
        position = position or Vector(0, 0, 0),
        alive = true,
        items = {},
        giveFails = false,
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        Alive = function(self) return self.alive end,
        WorldSpaceCenter = function(self) return self.position end,
        GetLevel = function() return 5 end,
        GiveItemInstance = function(self, instance)
            if self.giveFails then
                return false, "there is no free slot in the backpack"
            end
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
    check(#survivor.items == 1 and survivor.items[1].itemId == "itemBandage", "the item is given once")
    check(spot.state == "looted" and ZM_GetLootSpots(testProfile, testCell)[1].state == "looted", "the spot is looted and saved")
    local replay = Spots:RespondOffer(survivor, offer.token, true, 14)
    check(not replay and #survivor.items == 1, "replaying the token gives nothing")
    check(not Spots:BeginSearch(survivor, spot, 15), "a looted spot cannot be searched again")
end)

test("decline_keeps_the_same_item_across_reloads", function(check)
    local list = candidates(1)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local first = Spots:CompleteSearch(survivor, 12, Generation.NewRng(3))
    local declined = Spots:RespondOffer(survivor, first.token, false, 13)
    check(declined and #survivor.items == 0, "declining gives nothing")
    check(Spots.Cell.spots.m1.state == "declined", "a declined spot keeps its gray declined state")

    Spots:Activate(Spots:LoadCell(testProfile, testCell, list, { now = 1100 }))
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 20)
    local second = Spots:CompleteSearch(survivor, 22, Generation.NewRng(999))
    check(second.itemId == first.itemId and second.count == first.count and second.level == first.level, "the same item is offered again after a reload")
    check(second.token ~= first.token, "each offer gets a new token")
    check(not Spots:RespondOffer(survivor, first.token, true, 23), "an old token is rejected")
    local accepted = Spots:RespondOffer(survivor, second.token, true, 24)
    check(accepted and #survivor.items == 1 and survivor.items[1].itemId == first.itemId, "a re-opened declined item can be accepted")
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
    check(#second.items == 0 and spot.state == "available", "a rejected accept changes nothing")

    first.position = Vector(1000, 0, 0)
    Spots:BeginSearch(first, spot, 20)
    local lateOffer = Spots:CompleteSearch(first, 22, Generation.NewRng(5))
    check(not Spots:RespondOffer(first, lateOffer.token, true, 22 + Spots.OfferSeconds + 1), "an expired offer is rejected")
    check(Spots:ClaimExpired(spot, 22 + Spots.OfferSeconds + 1), "the claim is released")
end)

test("full_backpack_keeps_the_spot_and_item", function(check)
    Spots:Activate(Spots:LoadCell(testProfile, testCell, candidates(1), { now = 1000 }))
    local survivor = fakePlayer(Vector(1000, 0, 0))
    survivor.giveFails = true
    Spots:BeginSearch(survivor, Spots.Cell.spots.m1, 10)
    local offer = Spots:CompleteSearch(survivor, 12, Generation.NewRng(6))
    local accepted, reason = Spots:RespondOffer(survivor, offer.token, true, 13)
    check(not accepted and string.find(reason, "Could not take the item", 1, true), "a failed grant reports why")
    check(Spots.Cell.spots.m1.state == "available" and Spots.Cell.spots.m1.item.itemId == offer.itemId, "the spot keeps its item")
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
