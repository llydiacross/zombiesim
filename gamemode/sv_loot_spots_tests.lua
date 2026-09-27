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
        activationChance = 1,
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

test("entity_rules_match_by_runtime_class_and_model", function(check)
    local rule = ZM_StaticData:GetEntityLootRule("prop_physics", "models/props_vehicles/car001b_phy.mdl")
    check(rule ~= nil, "a shipped car model should match as prop_physics")
    check(ZM_StaticData:GetEntityLootRule("prop_physics_override", "MODELS\\props_vehicles\\CAR001B_PHY.mdl") == rule, "override classes and model case/slashes normalize")
    check(ZM_StaticData:GetEntityLootRule("prop_static", "models/props_vehicles/car001b_phy.mdl") == nil, "static props never match")
    check(ZM_StaticData:GetEntityLootRule("prop_dynamic", "models/props_vehicles/car001b_phy.mdl") ~= nil, "default rules cover prop_dynamic")
    check(ZM_StaticData:GetEntityLootRule("prop_physics", "models/props_junk/trashdumpster01a.mdl") == nil, "a rule limited to prop_dynamic does not match prop_physics")
    check(ZM_StaticData:GetEntityLootRule("prop_physics", "models/not_lootable.mdl") == nil, "unlisted models are not lootable")
end)

test("activation_generates_and_persists_spots", function(check)
    local rule = certainRule()
    local never = { activationChance = 0, entries = rule.entries }
    local list = { { key = "m1", rule = rule, entity = fakeEntity() }, { key = "m2", rule = never, entity = fakeEntity() } }
    local cell = Spots:LoadCell(testProfile, testCell, list, { now = 1000, rng = Generation.NewRng(1) })
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
