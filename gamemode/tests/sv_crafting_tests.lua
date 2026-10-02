// Server-only crafting tests: recipe registry, den/station/requirement gates, atomic exchange and rollback,
// interruption, replay resistance, and inherited freshness. Uses stub players and a throwaway SteamID/profile/den.
local Crafting = ZM_CraftingService
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items
local StaticData = ZM_StaticData

local testSteamId = "STEAM_TEST:0:2800"
local testProfile = "zn_test_craft"
local testDen = "zn_test_craft_den"

local function deepEqual(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local nextId = 0
local function instance(itemId, count, extra)
    nextId = nextId + 1
    local definition = Items:GetDefinition(itemId)
    local result = { instanceId = "craft" .. nextId, itemId = itemId, count = count or 1, level = definition.minLevel, mastercraft = false, clip = 0, createdAt = 0 }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function newStation()
    return { valid = true, IsValid = function(self) return self.valid end }
end

// A den-bound crafter standing at a station unless the test changes inDen / nearStation.
local function crafter(values)
    values = values or {}
    return {
        inDen = values.inDen ~= false,
        nearStation = values.nearStation ~= false,
        station = newStation(),
        alive = true,
        level = values.level or 1,
        stats = values.stats or {},
        job = values.job or "Civilian",
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        Alive = function(self) return self.alive end,
        SteamID = function() return testSteamId end,
        GetLevel = function(self) return self.level end,
        GetStat = function(self, name) return self.stats[name] or 0 end,
        GetJobRole = function(self) return self.job end,
        CurrentSafeZoneId = testDen,
        ZM_Inventory = Service.NewInventory(),
        ZM_InventoryProfile = testProfile
    }
end

local function give(target, itemId, count, container, extra)
    local definition = Items:GetDefinition(itemId)
    local remaining = count
    while remaining > 0 do
        local amount = math.min(remaining, definition.maxStack)
        assert(Ops.Add(target.ZM_Inventory, container or "backpack", instance(itemId, amount, extra)))
        remaining = remaining - amount
    end
end

local function storedCount(itemId)
    local total = 0
    for _, row in ipairs(ZM_GetPlayerItems(testSteamId, testProfile) or {}) do
        if row.itemId == itemId then total = total + tonumber(row.count) end
    end
    return total
end

local function storedStashCount(itemId)
    local total = 0
    for _, row in ipairs(ZM_GetDenStashItems(testSteamId, testProfile, testDen) or {}) do
        if row.itemId == itemId then total = total + tonumber(row.count) end
    end
    return total
end

local function cleanup()
    ZM_DeletePlayerItems(testSteamId, testProfile)
    ZM_ReplaceDenStashItems(testSteamId, testProfile, testDen, {})
    for target in pairs(Crafting.Jobs) do
        if type(target) == "table" and target.SteamID and target:SteamID() == testSteamId then
            Crafting.Jobs[target] = nil
        end
    end
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

// Finishes the active batch for a stub crafter.
local function finishBatch(target)
    local job = Crafting.Jobs[target]
    if job then Crafting:Advance(target, job.batchEndsAt) end
end

test("recipe_registry_is_loaded_and_versioned", function(check)
    local registry = StaticData:GetRegistry()
    check(registry.recipeVersion == 1, "the shipped recipe registry declares version 1")
    check(table.Count(registry.recipes) >= 5, "the shipped registry has the representative recipes")
    for recipeId, recipe in pairs(registry.recipes) do
        check(recipe.service or StaticData.CraftingStations[recipe.station] ~= nil, recipeId .. " uses a known station or is a service recipe")
        for _, stack in ipairs(recipe.ingredients) do
            check(Items:GetDefinition(stack.item) and Items:GetDefinition(stack.item).entityClass ~= "weapon", recipeId .. " consumes a known stackable item")
        end
        for _, stack in ipairs(recipe.results) do
            check(Items:GetDefinition(stack.item) ~= nil, recipeId .. " produces a known item")
        end
    end
    check(StaticData:GetRecipe("recipeAmmo9mm").results[1].item == "ammo9mm", "9mm ammunition is craftable")
    check(StaticData:GetRecipe("recipeBeanStew").freshness == "inherit", "stew inherits ingredient freshness")
    check(StaticData:GetRecipe("recipeMissing") == nil, "unknown recipes resolve to nil")
end)

test("crafting_is_den_and_station_only", function(check)
    local target = crafter({ inDen = false })
    give(target, "itemScrapMetal", 2)
    give(target, "itemGunpowder", 1)
    local before = table.Copy(target.ZM_Inventory)
    local function refused(expected, recipeId, count)
        local ok, reason = Crafting:Start(target, recipeId or "recipeAmmo9mm", count or 1)
        check(not ok and reason == expected, "expected '" .. expected .. "', got " .. tostring(reason))
    end
    refused("Crafting is only available inside your den.")
    target.inDen = true
    target.nearStation = false
    refused("Stand next to a crafting station to craft this.")
    target.nearStation = true
    refused("That recipe is not available.", "recipeMissing")
    refused("Invalid recipe.", string.rep("x", 80))
    refused("Choose from 1 to " .. Crafting.MaximumBatches .. " crafts.", nil, 0)
    refused("Choose from 1 to " .. Crafting.MaximumBatches .. " crafts.", nil, 1.5)
    refused("Choose from 1 to " .. Crafting.MaximumBatches .. " crafts.", nil, Crafting.MaximumBatches + 1)
    refused("Not enough Scrap Metal.", nil, 2)
    check(Crafting.Jobs[target] == nil, "refused requests never create a job")
    check(deepEqual(target.ZM_Inventory, before), "refused requests change nothing")
end)

test("requirements_gate_level_stats_and_jobs", function(check)
    local target = crafter({ level = 1 })
    give(target, "itemScrapMetal", 1)
    give(target, "itemGunpowder", 2)
    local ok, reason = Crafting:Start(target, "recipeAmmoShells", 1)
    check(not ok and reason == "Requires level 4.", "shells need level 4, got " .. tostring(reason))
    target.level = 5
    target.stats.WeaponCrafting = 1
    ok, reason = Crafting:Start(target, "recipeAmmoShells", 1)
    check(not ok and reason == "Requires WeaponCrafting 2.", "shells need WeaponCrafting 2, got " .. tostring(reason))
    target.stats.WeaponCrafting = 2
    check(Crafting:Start(target, "recipeAmmoShells", 1), "meeting every requirement starts the craft")
    local jobRecipe = { levelRequirement = 1, statRequirements = {}, jobs = { Chef = true } }
    check(#Crafting:UnmetRequirements(target, jobRecipe) == 1, "a job-gated recipe refuses other jobs")
    target.job = "Chef"
    check(#Crafting:UnmetRequirements(target, jobRecipe) == 0, "a job-gated recipe accepts its job")
end)

test("craft_exchanges_ingredients_for_results_atomically", function(check)
    local target = crafter()
    give(target, "itemScrapMetal", 4)
    give(target, "itemGunpowder", 2)
    check(Crafting:Start(target, "recipeAmmo9mm", 2), "two batches should start")
    local job = Crafting.Jobs[target]
    Crafting:Advance(target, job.batchEndsAt - 0.01)
    check(Service:Count(target, "ammo9mm") == 0, "nothing is produced before the craft time")
    finishBatch(target)
    check(Service:Count(target, "ammo9mm") == 20 and Service:Count(target, "itemScrapMetal") == 2 and Service:Count(target, "itemGunpowder") == 1, "the first batch exchanges exactly one recipe's worth")
    check(storedCount("ammo9mm") == 20 and storedCount("itemScrapMetal") == 2, "the first batch is persisted")
    check(Crafting.Jobs[target] and Crafting.Jobs[target].completed == 1, "the job continues with the second batch")
    finishBatch(target)
    check(Service:Count(target, "ammo9mm") == 40 and Service:Count(target, "itemScrapMetal") == 0 and Service:Count(target, "itemGunpowder") == 0, "the second batch uses the rest")
    check(Crafting.Jobs[target] == nil, "the job ends after its last batch")
    finishBatch(target)
    Crafting:Advance(target, CurTime() + 999)
    check(Service:Count(target, "ammo9mm") == 40 and storedCount("ammo9mm") == 40, "advancing a finished job grants nothing more")
end)

test("stash_ingredients_and_results_save_together", function(check)
    local target = crafter()
    give(target, "itemCloth", 3, "stash")
    target.stats.Medicine = 1
    check(Crafting:Start(target, "recipeClothBandage", 1), "stash ingredients count inside the den")
    finishBatch(target)
    check(Service:Count(target, "itemCloth", "stash") == 1 and Service:Count(target, "itemBandage", "backpack") == 1, "cloth comes from the stash and the bandage goes to the backpack")
    check(storedStashCount("itemCloth") == 1 and storedCount("itemBandage") == 1, "the stash and backpack are saved together")
end)

test("failed_save_missing_ingredients_or_full_inventory_consume_nothing", function(check)
    local target = crafter()
    give(target, "itemScrapMetal", 4)
    give(target, "itemGunpowder", 2)
    check(Service:Mutate(target, function() return true end), "the starting inventory persists")
    local before = table.Copy(target.ZM_Inventory)
    local beforeRows = ZM_GetPlayerItems(testSteamId, testProfile)

    check(Crafting:Start(target, "recipeAmmo9mm", 1), "the craft starts")
    target.ZM_InventoryProfile = "INVALID PROFILE"
    finishBatch(target)
    target.ZM_InventoryProfile = testProfile
    check(Crafting.Jobs[target] == nil, "a failed save stops the job")
    check(deepEqual(target.ZM_Inventory, before) and deepEqual(ZM_GetPlayerItems(testSteamId, testProfile), beforeRows), "a failed save consumes and grants nothing")

    check(Crafting:Start(target, "recipeAmmo9mm", 1), "the craft starts again")
    check(Service:RemoveItem(target, "itemGunpowder", 2), "the gunpowder is moved away mid-craft")
    local afterRemoval = table.Copy(target.ZM_Inventory)
    finishBatch(target)
    check(Crafting.Jobs[target] == nil and deepEqual(target.ZM_Inventory, afterRemoval), "missing ingredients at completion change nothing")

    cleanup()
    local full = crafter()
    give(full, "itemScrapMetal", 4)
    give(full, "itemGunpowder", 2)
    for _ = 1, Items.ContainerCapacity.backpack - 2 do give(full, "weaponMeleeCrowbar", 1) end
    for _ = 1, Items.ContainerCapacity.stash do give(full, "weaponMeleeCrowbar", 1, "stash") end
    local fullBefore = table.Copy(full.ZM_Inventory)
    check(Crafting:Start(full, "recipeAmmo9mm", 1), "the craft starts with a full inventory")
    finishBatch(full)
    check(Crafting.Jobs[full] == nil, "no room stops the job")
    check(deepEqual(full.ZM_Inventory, fullBefore), "a result that does not fit keeps every ingredient")
    check(#ZM_GetPlayerItems(testSteamId, testProfile) == 0 and #ZM_GetDenStashItems(testSteamId, testProfile, testDen) == 0, "nothing is written for a rolled-back craft")
end)

test("interruptions_cancel_without_consuming", function(check)
    local target = crafter()
    give(target, "itemScrapMetal", 2)
    give(target, "itemGunpowder", 1)
    local before = table.Copy(target.ZM_Inventory)
    local function interrupted(expected, breakIt, restore)
        check(Crafting:Start(target, "recipeAmmo9mm", 1), "the craft starts before: " .. expected)
        local job = Crafting.Jobs[target]
        breakIt(job)
        Crafting:Advance(target, job.batchEndsAt)
        check(Crafting.Jobs[target] == nil, "the job stops: " .. expected)
        check(deepEqual(target.ZM_Inventory, before), "nothing is consumed: " .. expected)
        restore(job)
    end
    interrupted("died", function() target.alive = false end, function() target.alive = true end)
    interrupted("left den", function() target.inDen = false end, function() target.inDen = true end)
    interrupted("station removed", function(job) job.station.valid = false end, function() end)
    interrupted("moved away", function() target.nearStation = false end, function() target.nearStation = true end)
    interrupted("recipe changed", function(job) job.recipe = table.Copy(job.recipe) end, function() end)
    interrupted("lost requirement", function() target.level = 0 end, function() target.level = 1 end)

    check(Crafting:Start(target, "recipeAmmo9mm", 1), "the craft starts before cancelling")
    local cancelled, message = Crafting:Cancel(target, "Crafting cancelled.", true)
    check(cancelled and message == "Crafting cancelled." and Crafting.Jobs[target] == nil, "a player can cancel")
    check(not Crafting:Cancel(target), "cancelling twice is refused")
    check(deepEqual(target.ZM_Inventory, before), "cancelling consumes nothing")
end)

test("duplicate_and_replayed_requests_are_refused", function(check)
    local target = crafter()
    give(target, "itemScrapMetal", 4)
    give(target, "itemGunpowder", 2)
    local function request(body)
        target.ZM_NextCraftingRequestAt = nil
        return Crafting:HandleRequest(target, body)
    end
    check(not request(nil) and not request({ action = 5 }) and not request({ action = "complete", recipeId = "recipeAmmo9mm" }), "malformed and client-completion requests are rejected")
    check(not request({ action = "start", recipeId = "recipeAmmo9mm", count = "lots" }), "non-numeric counts are rejected")
    check(request({ action = "start", recipeId = "recipeAmmo9mm", count = 1 }), "a valid start works")
    local again, reason = request({ action = "start", recipeId = "recipeAmmo9mm", count = 1 })
    check(not again and reason == "You are already crafting.", "a duplicate submission is refused")
    local limited, limitReason = Crafting:HandleRequest(target, { action = "cancel" })
    check(not limited and limitReason == "Slow down.", "requests faster than the cooldown are refused")
    finishBatch(target)
    finishBatch(target)
    check(Service:Count(target, "ammo9mm") == 20 and Service:Count(target, "itemScrapMetal") == 2, "one start crafts exactly one batch")
end)

test("inherited_freshness_follows_ingredients", function(check)
    local now = os.time()
    local target = crafter()
    local beansShelf = Items:GetDefinition("itemCannedBeans").food.shelfLifeHours * 3600
    give(target, "itemCannedBeans", 2, "backpack", { createdAt = now - beansShelf * 0.5 })
    give(target, "itemBarrelWater", 1, "backpack", { createdAt = now })
    give(target, "itemOil", 1)
    local crafted = Crafting:CraftBatch(target, StaticData:GetRecipe("recipeBeanStew"), now)
    check(crafted, "the stew crafts")
    local stew
    for _, candidate in pairs(target.ZM_Inventory.backpack) do
        if candidate.itemId == "itemBeanStew" then stew = candidate end
    end
    local freshness = stew and ZM_Food:GetFreshness(stew, now)
    check(freshness and math.abs(freshness - 2 / 3) < 0.001, "stew freshness is the count-weighted input freshness, got " .. tostring(freshness))

    cleanup()
    local boiler = crafter()
    local waterShelf = Items:GetDefinition("itemBarrelWater").food.shelfLifeHours * 3600
    give(boiler, "itemBarrelWater", 2, "backpack", { createdAt = now - waterShelf * 0.9 })
    give(boiler, "itemOil", 1)
    check(Crafting:CraftBatch(boiler, StaticData:GetRecipe("recipeBoiledWater"), now), "the water boils")
    local boiled
    for _, candidate in pairs(boiler.ZM_Inventory.backpack) do
        if candidate.itemId == "itemBottledWater" then boiled = candidate end
    end
    check(boiled and boiled.count == 2 and boiled.createdAt == now, "freshness 'new' results are brand new")
end)

test("player_and_stash_rows_save_in_one_transaction", function(check)
    local keepPlayer = { { instanceId = "keepPlayer", container = "backpack", slot = 1, itemId = "itemBandage", count = 1, level = 1 } }
    local keepStash = { { instanceId = "keepStash", container = "stash", slot = 1, itemId = "itemCloth", count = 2, level = 1 } }
    check(ZM_ReplacePlayerItems(testSteamId, testProfile, keepPlayer) and ZM_ReplaceDenStashItems(testSteamId, testProfile, testDen, keepStash), "the starting rows persist")
    local changedPlayer = { { instanceId = "newPlayer", container = "backpack", slot = 2, itemId = "itemBandage", count = 2, level = 1 } }
    local duplicateStash = {
        { instanceId = "dupA", container = "stash", slot = 3, itemId = "itemCloth", count = 1, level = 1 },
        { instanceId = "dupB", container = "stash", slot = 3, itemId = "itemCloth", count = 1, level = 1 }
    }
    check(not ZM_ReplacePlayerAndDenStashItems(testSteamId, testProfile, changedPlayer, testDen, duplicateStash), "an invalid stash write fails the combined save")
    local playerRows = ZM_GetPlayerItems(testSteamId, testProfile)
    local stashRows = ZM_GetDenStashItems(testSteamId, testProfile, testDen)
    check(#playerRows == 1 and playerRows[1].instanceId == "keepPlayer", "the player rows roll back with the stash")
    check(#stashRows == 1 and stashRows[1].instanceId == "keepStash", "the stash rows are unchanged")
end)

function Crafting:RunTests()
    local restoreStashAccess = ZM_TestHarness.StubStashAccess()
    local originalFindStation = Crafting.FindStation
    local originalInRange = Crafting.IsStationInRange
    Crafting.FindStation = function(self, target, stationTag)
        if type(target) == "table" and target.nearStation ~= nil then
            return target.nearStation and StaticData.CraftingStations[stationTag] and target.station or nil
        end
        return originalFindStation(self, target, stationTag)
    end
    Crafting.IsStationInRange = function(self, target, station)
        if type(target) == "table" and target.nearStation ~= nil then return target.nearStation and IsValid(station) end
        return originalInRange(self, target, station)
    end
    local summary = suite:Run({ before = cleanup, after = cleanup })
    restoreStashAccess()
    Crafting.FindStation = originalFindStation
    Crafting.IsStationInRange = originalInRange
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_crafting", label = "Crafting", file = "crafting_tests.json", report = "craftingTests",
    help = "Runs crafting registry, transaction, interruption, and replay tests against a throwaway SteamID and profile.",
    run = function() return Crafting:RunTests() end
})
