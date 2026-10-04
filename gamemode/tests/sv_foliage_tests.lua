// Server-side tests for deterministic foliage placement and shared harvest state.
local Foliage = ZM_Foliage
local Generation = ZM_ItemGeneration
local testProfile = "zn_test_foliage"
local otherProfile = "zn_test_foliage_other"
local testCell = 424243

local function clearTestRows()
    for _, profile in ipairs({ testProfile, otherProfile }) do
        local rows = ZM_GetFoliageHarvests(profile, testCell) or {}
        for _, row in ipairs(rows) do
            ZM_DeleteFoliageHarvest(profile, testCell, row.nodeKey)
        end
    end
end

local function fakePlayer(position, withMelee)
    local inventory = { equipped = {} }
    if withMelee then
        inventory.equipped[1] = { itemId = "weaponMeleeCrowbar" }
    end
    return {
        ZM_Inventory = inventory,
        position = position or Vector(0, 0, 0),
        items = {},
        alive = true,
        giveFails = false,
        Alive = function(self) return self.alive end,
        WorldSpaceCenter = function(self) return self.position end,
        GiveItem = function(self, itemId, count)
            if self.giveFails then
                return false, "there is no free slot in the backpack"
            end
            table.insert(self.items, { itemId = itemId, count = count })
            return true
        end
    }
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("ground_filter_accepts_only_flat_green_surfaces", function(check)
    local original = util.GetSurfacePropName
    util.GetSurfacePropName = function() return "grass" end
    local ground = { Hit = true, HitNormal = Vector(0, 0, 1), SurfaceProps = 1, HitTexture = "nature/grassfloor001a" }
    local slope = { Hit = true, HitNormal = Vector(0.7, 0, 0.7), SurfaceProps = 1, HitTexture = ground.HitTexture }
    local road = { Hit = true, HitNormal = Vector(0, 0, 1), SurfaceProps = 1, HitTexture = "nature/asphalt_road" }
    local carpark = { Hit = true, HitNormal = Vector(0, 0, 1), SurfaceProps = 1,
        HitTexture = "concrete/concretefloor038a" }
    local nonGrass = { Hit = true, HitNormal = Vector(0, 0, 1), SurfaceProps = 1, HitTexture = ground.HitTexture }
    check(Foliage.IsSuitableGround(ground), "flat grass is suitable")
    check(not Foliage.IsSuitableGround(slope), "steep ground is rejected")
    check(not Foliage.IsSuitableGround(road), "road material is rejected")
    check(not Foliage.IsSuitableGround(carpark), "carpark paving is rejected even with a grass surface property")
    util.GetSurfacePropName = function() return "concrete" end
    check(not Foliage.IsSuitableGround(nonGrass), "concrete surface props are rejected")
    util.GetSurfacePropName = original
end)

test("trees_at_paved_edges_become_shrubs", function(check)
    local bounds = { minimum = Vector(-1000, -1000, -64), maximum = Vector(1000, 1000, 512) }
    local original = util.GetSurfacePropName
    util.GetSurfacePropName = function() return "grass" end
    local treeCandidates = 0
    for seed = 1, 32 do
        local traces = 0
        local traceGround = function(x, y)
            traces = traces + 1
            return {
                Hit = true,
                HitNormal = Vector(0, 0, 1),
                HitPos = Vector(x, y, 0),
                SurfaceProps = 1,
                HitTexture = traces == 1 and "nature/grassfloor001a" or "concrete/concretefloor038a"
            }
        end
        local candidate = Foliage.MakeCandidate(bounds, Generation.NewRng(seed), seed, traceGround,
            function() return false end, {})
        if traces > 1 then
            treeCandidates = treeCandidates + 1
            check(candidate and candidate.type == "berry",
                "trees whose footprint crosses carpark paving are downgraded to shrubs")
        end
    end
    util.GetSurfacePropName = original
    check(treeCandidates > 0, "deterministic seeds exercise tree footprint filtering")
end)

test("placement_is_deterministic_bounded_and_spaced", function(check)
    local bounds = { minimum = Vector(-1000, -1000, -64), maximum = Vector(1000, 1000, 512) }
    local traceGround = function(x, y)
        return {
            Hit = true,
            HitNormal = Vector(0, 0, 1),
            HitPos = Vector(x, y, 0),
            SurfaceProps = 1,
            HitTexture = "nature/grassfloor001a"
        }
    end
    local original = util.GetSurfacePropName
    util.GetSurfacePropName = function() return "grass" end
    local first = Foliage.MakeCandidate(bounds, Generation.NewRng(123), 7, traceGround,
        function() return false end, {})
    local second = Foliage.MakeCandidate(bounds, Generation.NewRng(123), 7, traceGround,
        function() return false end, {})
    check(first and second and first.key == second.key and first.type == second.type
        and first.position:DistToSqr(second.position) == 0 and first.yaw == second.yaw,
        "fixed seed and attempt produce the same placement")
    check(first and math.abs(first.position.x) <= 1000 - Foliage.MapEdgeMargin
        and math.abs(first.position.y) <= 1000 - Foliage.MapEdgeMargin,
        "placements stay inside the map-edge margin")
    local occupied = Foliage.MakeCandidate(bounds, Generation.NewRng(123), 7, traceGround,
        function() return true end, {})
    check(occupied == nil, "blocked spaces are rejected")
    local spaced = Foliage.MakeCandidate(bounds, Generation.NewRng(123), 7, traceGround,
        function() return false end, { { position = first and first.position or Vector(0, 0, 0) } })
    check(spaced == nil, "placements too close to another plant are rejected")
    util.GetSurfacePropName = original
end)

test("model_pools_are_diverse_mounted_and_deterministic", function(check)
    for _, nodeType in ipairs({ "tree", "berry" }) do
        local pool = Foliage.Models[nodeType]
        check(type(pool) == "table" and #pool >= 3, nodeType .. " pool offers several models")
        local seen = {}
        for _, model in ipairs(pool or {}) do
            check(util.IsValidModel(model), nodeType .. " model is mounted: " .. model)
            check(not seen[model], nodeType .. " pool has no duplicates: " .. model)
            seen[model] = true
        end
        check(Foliage.PickModel(nodeType, 0) == pool[1] and Foliage.PickModel(nodeType, 0.9999) == pool[#pool],
            nodeType .. " model roll maps onto the full pool")
        check(Foliage.PickModel(nodeType, 0.5) == Foliage.PickModel(nodeType, 0.5), nodeType .. " model pick is stable")
    end
    check(Foliage.MaxNodesPerCell >= 30, "foliage density target is about 30 nodes per cell")
end)

test("foliage_nodes_are_one_third_harvestable", function(check)
    local harvestable = 0
    local decorative = 0
    for slot = 1, Foliage.MaxNodesPerCell do
        if Foliage.IsHarvestableSlot(slot) then
            harvestable = harvestable + 1
        else
            decorative = decorative + 1
        end
    end
    check(harvestable == 10 and decorative == 20,
        "30 deterministic foliage slots provide 10 harvestable and 20 decorative plants")
    check(Foliage.IsHarvestableSlot(1) and not Foliage.IsHarvestableSlot(2)
        and not Foliage.IsHarvestableSlot(3) and Foliage.IsHarvestableSlot(4),
        "harvestable nodes are interspersed with decorative plants")
    check(not Foliage.IsHarvestableSlot(0) and not Foliage.IsHarvestableSlot(1.5),
        "invalid placement slots are never harvestable")
end)

test("rocky_ground_only_grows_shrubs", function(check)
    local bounds = { minimum = Vector(-1000, -1000, -64), maximum = Vector(1000, 1000, 512) }
    local traceGround = function(x, y)
        return { Hit = true, HitNormal = Vector(0, 0, 1), HitPos = Vector(x, y, 0), SurfaceProps = 1,
            HitTexture = "nature/rockwall001a" }
    end
    local original = util.GetSurfacePropName
    util.GetSurfacePropName = function() return "rock" end
    local trees, shrubs = 0, 0
    for attempt = 1, 40 do
        local candidate = Foliage.MakeCandidate(bounds, Generation.NewRng(attempt), attempt, traceGround,
            function() return false end, {})
        if candidate then
            if candidate.type == "tree" then trees = trees + 1 else shrubs = shrubs + 1 end
            check(candidate.model ~= nil, "rock candidates carry a model")
        end
    end
    util.GetSurfacePropName = original
    check(trees == 0 and shrubs > 0, "rocky surfaces accept shrubs but never trees")
end)

test("placement_bounds_exclude_the_inaccessible_border_ring", function(check)
    local bounds = Foliage.GetWorldBounds()
    check(bounds ~= nil, "world bounds resolve on the current map")
    if bounds then
        local half = Foliage.PlayableHalfExtent
        check(bounds.minimum.x >= -half and bounds.maximum.x <= half
            and bounds.minimum.y >= -half and bounds.maximum.y <= half,
            "foliage and fallen-body bounds stay inside the 5x5 playable grid")
    end
end)

test("berry_rewards_follow_server_calendar_seasons", function(check)
    local itemId, springCount = Foliage.GetReward("berry", 4, Generation.NewRng(1))
    check(itemId == "itemBerries" and springCount >= 3 and springCount <= 5,
        "spring/summer yields plentiful berries")
    local autumnId, autumnCount = Foliage.GetReward("berry", 10, Generation.NewRng(1))
    check(autumnId == "itemBerries" and autumnCount >= 1 and autumnCount <= 2,
        "autumn yields a scarce berry crop")
    local winterId, winterMessage = Foliage.GetReward("berry", 12, Generation.NewRng(1))
    check(winterId == nil and string.find(winterMessage, "winter", 1, true) ~= nil,
        "winter bushes do not yield berries")
    local woodId, woodCount = Foliage.GetReward("tree", 12, Generation.NewRng(1))
    check(woodId == "itemWood" and woodCount >= 2 and woodCount <= 4,
        "trees yield wood in every season")
end)

test("harvest_cooldowns_match_shared_regrowth_contract", function(check)
    check(Foliage.GetCooldown("berry") == 24 * 60 * 60, "berry bushes regrow in 24 hours")
    check(Foliage.GetCooldown("tree") == 7 * 24 * 60 * 60, "trees regrow in seven days")
    check(Foliage.GetBerrySeason(1) == "winter" and Foliage.GetBerrySeason(6) == "plentiful"
        and Foliage.GetBerrySeason(10) == "scarce", "months map to the agreed seasons")
end)

test("harvest_requires_melee_for_wood_and_blocks_duplicate_requests", function(check)
    local previousCell = Foliage.Cell
    local node = { key = "v3_001", type = "tree", harvestable = true, position = Vector(0, 0, 0) }
    Foliage.Cell = { profile = testProfile, cellId = testCell, nodes = { [node.key] = node } }
    local survivor = fakePlayer(Vector(0, 0, 0), false)
    local rejected = Foliage:Harvest(survivor, node, 1000, { month = 4 }, Generation.NewRng(1))
    check(not rejected and #survivor.items == 0, "trees reject harvesting without equipped melee")
    survivor.ZM_Inventory.equipped[1] = { itemId = "weaponMeleeCrowbar" }
    local harvested = Foliage:Harvest(survivor, node, 1000, { month = 4 }, Generation.NewRng(1))
    check(harvested and #survivor.items == 1 and survivor.items[1].itemId == "itemWood",
        "equipped melee allows a wood reward")
    local duplicate = Foliage:Harvest(survivor, node, 1001, { month = 4 }, Generation.NewRng(1))
    check(not duplicate and #survivor.items == 1, "the depleted node cannot be harvested twice")
    check(node.availableAt == 1000 + Foliage.TreeCooldownSeconds, "harvest sets the persistent cooldown")
    Foliage.Cell = previousCell
end)

test("berry_harvest_is_hand_picked_and_inventory_items_exist", function(check)
    local previousCell = Foliage.Cell
    local node = { key = "v3_002", type = "berry", harvestable = true, position = Vector(0, 0, 0) }
    Foliage.Cell = { profile = testProfile, cellId = testCell, nodes = { [node.key] = node } }
    local survivor = fakePlayer(Vector(0, 0, 0), false)
    local harvested = Foliage:Harvest(survivor, node, 2000, { month = 5 }, Generation.NewRng(4))
    check(harvested and #survivor.items == 1 and survivor.items[1].itemId == "itemBerries",
        "berries can be picked by hand and are granted through inventory")
    check(ZM_Items:GetDefinition("itemWood") ~= nil and ZM_Items:GetDefinition("itemBerries") ~= nil,
        "both harvest rewards have inventory definitions")
    Foliage.Cell = previousCell
end)

test("decorative_foliage_cannot_be_harvested", function(check)
    local previousCell = Foliage.Cell
    local node = { key = "v3_003", type = "berry", harvestable = false, position = Vector(0, 0, 0) }
    Foliage.Cell = { profile = testProfile, cellId = testCell, nodes = { [node.key] = node } }
    local survivor = fakePlayer(Vector(0, 0, 0), false)
    local harvested, message = Foliage:Harvest(survivor, node, 2200, { month = 5 }, Generation.NewRng(5))
    check(not harvested and message == "That plant is decorative." and #survivor.items == 0,
        "decorative plants grant no harvest reward")
    Foliage.Cell = previousCell
end)

test("decorative_foliage_does_not_block_nearby_harvestable_plants", function(check)
    local previousCell = Foliage.Cell
    local decorativeEntity = ents.Create("prop_dynamic")
    local harvestableEntity = ents.Create("prop_dynamic")
    if not IsValid(decorativeEntity) or not IsValid(harvestableEntity) then
        if IsValid(decorativeEntity) then decorativeEntity:Remove() end
        if IsValid(harvestableEntity) then harvestableEntity:Remove() end
        Foliage.Cell = previousCell
        check(false, "temporary foliage entities can be created")
        return
    end

    local placements = {
        { decorativeEntity, Foliage.Models.berry[1], Vector(8, 0, 0) },
        { harvestableEntity, Foliage.Models.berry[1], Vector(24, 0, 0) }
    }
    for _, placement in ipairs(placements) do
        local entity, model, position = placement[1], placement[2], placement[3]
        entity:SetModel(model)
        entity:SetPos(position)
        entity:SetSolid(SOLID_NONE)
        entity:SetNotSolid(true)
        entity:SetMoveType(MOVETYPE_NONE)
        entity:Spawn()
    end

    local decorative = {
        key = "decorative",
        harvestable = false,
        entity = decorativeEntity,
        position = Vector(8, 0, 0)
    }
    local harvestable = {
        key = "harvestable",
        harvestable = true,
        entity = harvestableEntity,
        position = Vector(24, 0, 0)
    }
    Foliage.Cell = { nodes = { decorative = decorative, harvestable = harvestable } }
    local nearest = Foliage:FindNearestNode(fakePlayer(Vector(0, 0, 0), false))
    check(nearest == harvestable, "use targeting skips nearer decorative plants")

    decorativeEntity:Remove()
    harvestableEntity:Remove()
    Foliage.Cell = previousCell
end)

test("failed_inventory_grant_restores_the_harvest_node", function(check)
    local previousCell = Foliage.Cell
    local node = { key = "v3_004", type = "berry", harvestable = true, position = Vector(0, 0, 0) }
    Foliage.Cell = { profile = testProfile, cellId = testCell, nodes = { [node.key] = node } }
    local survivor = fakePlayer(Vector(0, 0, 0), false)
    survivor.giveFails = true
    local harvested = Foliage:Harvest(survivor, node, 2500, { month = 5 }, Generation.NewRng(7))
    check(not harvested and #survivor.items == 0, "a full backpack receives no item")
    check(node.availableAt == nil, "a failed reward does not leave the node depleted")
    local rows = ZM_GetFoliageHarvests(testProfile, testCell) or {}
    local persisted = false
    for _, row in ipairs(rows) do
        if row.nodeKey == node.key then persisted = true end
    end
    check(not persisted, "the failed reward cooldown is removed from SQLite")
    Foliage.Cell = previousCell
end)

test("harvest_range_is_enforced", function(check)
    local previousCell = Foliage.Cell
    local node = { key = "v3_005", type = "berry", harvestable = true, position = Vector(0, 0, 0) }
    Foliage.Cell = { profile = testProfile, cellId = testCell, nodes = { [node.key] = node } }
    local survivor = fakePlayer(Vector(Foliage.HarvestRange + 1, 0, 0), false)
    local harvested = Foliage:Harvest(survivor, node, 2600, { month = 5 }, Generation.NewRng(8))
    check(not harvested and #survivor.items == 0, "out-of-range harvests do not grant items")
    Foliage.Cell = previousCell
end)

test("harvest_state_isolated_by_profile_and_survives_reload", function(check)
    local saved, saveError = ZM_SetFoliageHarvest(testProfile, testCell, "v3_001", 3000)
    local rows, readError = ZM_GetFoliageHarvests(testProfile, testCell)
    local otherRows = ZM_GetFoliageHarvests(otherProfile, testCell)
    local found = false
    for _, row in ipairs(rows or {}) do
        if row.nodeKey == "v3_001" and tonumber(row.availableAt) == 3000 then
            found = true
        end
    end
    check(saved and found, "cooldown data is stored and read from SQLite")
    check(otherRows and #otherRows == 0, "harvest state is isolated by world profile")
    check(saveError == nil and readError == nil, "SQLite reads and writes report no errors")
end)

function Foliage:RunTests()
    local previousCell = self.Cell
    clearTestRows()
    self.Cell = nil
    local summary = suite:Run({
        before = function()
            clearTestRows()
            self.Cell = nil
        end,
        after = clearTestRows
    })
    self.Cell = previousCell
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_foliage",
    label = "Runtime foliage",
    file = "foliage_tests.json",
    report = "foliageTests",
    help = "Runs deterministic placement, seasonal reward, harvest, and persistence tests.",
    run = function() return Foliage:RunTests() end
})
