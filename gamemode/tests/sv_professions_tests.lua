// Server-only profession tests: registry resolution, deterministic delivery bands, exactly-once daily claims,
// profile isolation, capacity and save failures, and cook/treat/research services with fee transfer and offer replay.
// Uses stub players and throwaway SteamIDs/profiles/den; every row they write is removed afterwards.
local Pro = ZM_ProfessionService
local Professions = ZM_Professions
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items
local StaticData = ZM_StaticData

local customerId = "STEAM_TEST:0:2810"
local providerId = "STEAM_TEST:0:2811"
local testProfile = "zn_test_prof"
local otherProfile = "zn_test_prof2"
local testDen = "zn_test_prof_den"
local day = 86400

local nextId = 0
local function instance(itemId, count, extra)
    nextId = nextId + 1
    local definition = Items:GetDefinition(itemId)
    local result = { instanceId = "prof" .. nextId, itemId = itemId, count = count or 1, level = definition.minLevel, mastercraft = false, clip = 0, createdAt = 0 }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function person(values)
    values = values or {}
    return {
        steamId = values.steamId or customerId,
        inDen = values.inDen ~= false,
        alive = true,
        level = values.level or 1,
        job = values.job or "Civilian",
        Cash = values.cash or 0,
        health = values.health or 100,
        pos = values.pos or Vector(0, 0, 0),
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        Alive = function(self) return self.alive end,
        SteamID = function(self) return self.steamId end,
        Nick = function(self) return self.steamId end,
        GetLevel = function(self) return self.level end,
        GetJobRole = function(self) return Professions:Resolve(self.job) end,
        GetStoredJob = function(self) return self.job end,
        GetStat = function(self, name) return Professions:GetStatBonus(self.job, name) end,
        Health = function(self) return self.health end,
        GetMaxHealth = function() return 100 end,
        SetHealth = function(self, value) self.health = value end,
        GetPos = function(self) return self.pos end,
        CurrentSafeZoneId = testDen,
        ZM_Inventory = Service.NewInventory(),
        ZM_InventoryProfile = values.profile or testProfile
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

local function storedCount(steamId, profile, itemId)
    local total = 0
    for _, row in ipairs(ZM_GetPlayerItems(steamId, profile) or {}) do
        if row.itemId == itemId then total = total + tonumber(row.count) end
    end
    for _, row in ipairs(ZM_GetDenStashItems(steamId, profile, testDen) or {}) do
        if row.itemId == itemId then total = total + tonumber(row.count) end
    end
    return total
end

local function storedCash(steamId)
    local data = ZM_GetPlayerData(steamId, testProfile)
    return data and tonumber(data.Cash) or nil
end

local function totalCount(target, itemId)
    return Ops.Count(target.ZM_Inventory, itemId, "backpack") + Ops.Count(target.ZM_Inventory, itemId, "stash")
end

local function cleanup()
    for _, steamId in ipairs({ customerId, providerId }) do
        for _, profile in ipairs({ testProfile, otherProfile }) do
            ZM_DeletePlayerItems(steamId, profile)
            ZM_ReplaceDenStashItems(steamId, profile, testDen, {})
            ZM_DeleteProfessionClaims(steamId, profile)
            sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(steamId) .. " AND profile = " .. sql.SQLStr(profile))
        end
    end
    for id, offer in pairs(Pro.Offers) do
        if type(offer.customer) == "table" and offer.customer.steamId then Pro.Offers[id] = nil end
    end
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("profession_registry_resolves_ids_aliases_and_fallback", function(check)
    local registry = StaticData:GetRegistry()
    check(registry.professionVersion == 1, "the shipped profession registry declares version 1")
    check(registry.professions.Civilian ~= nil, "Civilian exists")
    check(Professions:Resolve("Medic") == "Doctor" and Professions:Resolve("Soldier") == "ArmySoldier" and Professions:Resolve("Police") == "PoliceOfficer", "aliases resolve to canonical ids")
    check(Professions:Resolve("Wizard") == "Civilian", "unknown jobs fall back to Civilian")
    check(Pro:ResolveJob("Army Soldier") == "ArmySoldier" and Pro:ResolveJob("police officer") == "PoliceOfficer", "authored display names resolve to canonical ids")
    check(Pro:ResolveJob("Wizard") == nil, "unknown authored jobs are still rejected")
    check(Professions:GetStatBonus("Farmer", "Farming") == 3 and Professions:GetStatBonus("Civilian", "Farming") == 0, "stat bonuses come from the profession")
    check(Professions:OffersService("Doctor", "treat") and not Professions:OffersService("Doctor", "cook"), "services come from the profession")
    check(Professions:GetDeliveryTier("Doctor", 1).minLevel == 1, "level 1 gets the first Doctor tier")
    check(Professions:GetDeliveryTier("Doctor", 15).minLevel == 10, "level 15 gets the level-10 Doctor tier")
    check(Professions:GetDeliveryTier("Doctor", 300).minLevel == 40, "level 300 gets the top Doctor tier")
    check(Professions:GetDeliveryTier("Civilian", 50) == nil, "Civilians have no delivery")
end)

test("stat_bonuses_are_derived_not_persisted", function(check)
    local meta = FindMetaTable("Player")
    local fake = setmetatable({ Attributes = { Medicine = 2 }, Job = "Doctor" }, { __index = function(_, key) return meta[key] end })
    fake.GetNWString = function(_, _, default) return default end
    check(fake:GetBaseStat("Medicine") == 2, "the base stat is the allocated points")
    check(fake:GetStat("Medicine") == 5, "the effective stat adds the Doctor bonus, got " .. tostring(fake:GetStat("Medicine")))
    check(fake.Attributes.Medicine == 2, "the bonus is never written into Attributes")
    fake.Job = "Medic"
    check(fake:GetJobRole() == "Doctor", "a stored alias reports the canonical job")
end)

test("delivery_plan_is_deterministic_and_bounded", function(check)
    local target = person({ job = "Farmer", level = 12 })
    local first = Pro:PlanDelivery(target, "2026-01-01")
    local second = Pro:PlanDelivery(target, "2026-01-01")
    check(first and #first == 3, "a level-12 Farmer gets the three-item level-10 tier")
    check(util.TableToJSON(first) == util.TableToJSON(second), "the same day always plans the same delivery")
    local tier = Professions:GetDeliveryTier("Farmer", 12)
    for index, stack in ipairs(first or {}) do
        local entry = tier.items[index]
        check(stack.item == entry.item and stack.count >= entry.min and stack.count <= entry.max, stack.item .. " count " .. stack.count .. " is within its band")
    end
end)

test("claim_is_exactly_once_per_day", function(check)
    local target = person({ job = "Farmer" })
    local now = os.time()
    local ok, stacks = Pro:Claim(target, now)
    check(ok, "the first claim succeeds: " .. tostring(stacks))
    local potatoes = storedCount(customerId, testProfile, "itemPotato")
    check(potatoes >= 2 and potatoes <= 4, "the potatoes were saved, got " .. potatoes)
    local again, message, reason = Pro:Claim(target, now)
    check(not again and reason == "claimed", "a second claim the same day is refused: " .. tostring(message))
    check(storedCount(customerId, testProfile, "itemPotato") == potatoes, "the refused claim grants nothing")
    check(Pro:Claim(target, now + day), "the next UTC day can be claimed")
    check(storedCount(customerId, testProfile, "itemPotato") > potatoes, "the next day's delivery was saved")
end)

test("a_claim_race_rolls_back_the_items", function(check)
    local target = person({ job = "Farmer" })
    local now = os.time()
    check(Pro:Claim(target, now), "the first claim succeeds")
    local before = target.ZM_Inventory
    local beforeCount = storedCount(customerId, testProfile, "itemPotato")
    local beforeHeld = totalCount(target, "itemPotato")
    // Simulate a second server path that missed the existing claim: the primary key must still refuse it.
    local originalGetClaim = Pro.GetClaim
    Pro.GetClaim = function() return nil end
    local ok = Pro:Claim(target, now)
    Pro.GetClaim = originalGetClaim
    check(not ok, "the duplicate claim row fails the transaction")
    check(storedCount(customerId, testProfile, "itemPotato") == beforeCount and target.ZM_Inventory == before and totalCount(target, "itemPotato") == beforeHeld, "the rolled-back claim grants nothing")
end)

test("claims_are_profile_isolated_and_keyed_by_day_not_job", function(check)
    local target = person({ job = "Farmer" })
    local now = os.time()
    check(Pro:Claim(target, now), "the claim succeeds on the first profile")
    target.job = "Doctor"
    local ok, _, reason = Pro:Claim(target, now)
    check(not ok and reason == "claimed", "changing job the same day gives no second delivery")
    target.ZM_InventoryProfile = otherProfile
    target.ZM_Inventory = Service.NewInventory()
    check(Pro:Claim(target, now), "a different profile has its own claim")
end)

test("civilians_out_of_den_and_full_inventories_get_nothing", function(check)
    local civilian = person()
    local ok, _, reason = Pro:Claim(civilian, os.time())
    check(not ok and reason == "none", "a Civilian has no delivery")

    local away = person({ job = "Farmer", inDen = false })
    check(not Pro:Claim(away, os.time()), "deliveries only arrive in the den")

    local full = person({ job = "Farmer" })
    give(full, "itemCloth", 1)
    local now = os.time()
    local deliveryDay = Pro:Day(now)
    local originalCapacity = Items.ContainerCapacity
    Items.ContainerCapacity = { backpack = 1, stash = 0, equipped = 3 }
    local claimed, message = Pro:Claim(full, now)
    Items.ContainerCapacity = originalCapacity
    check(not claimed and string.find(tostring(message), "no room", 1, true), "a full inventory refuses the delivery: " .. tostring(message))
    check(Pro:GetClaim(full, deliveryDay) == nil, "a refused delivery leaves the day unclaimed for a retry")
    check(totalCount(full, "itemPotato") == 0, "nothing was granted")

    check(Ops.Remove(full.ZM_Inventory, "backpack", "itemCloth", 1), "the blocker can be removed to make room")
    local plan = Pro:PlanDelivery(full, deliveryDay)
    local retried, stacks = Pro:Claim(full, now)
    check(retried, "the same day's delivery succeeds after capacity is available: " .. tostring(stacks))
    check(Pro:GetClaim(full, deliveryDay) ~= nil, "the successful retry records its exactly-once claim")
    for _, stack in ipairs(plan or {}) do
        check(totalCount(full, stack.item) == stack.count, "the retried delivery grants the planned amount of " .. stack.item)
    end
    local beforeDuplicate = totalCount(full, "itemPotato")
    local duplicate, _, duplicateReason = Pro:Claim(full, now)
    check(not duplicate and duplicateReason == "claimed", "a delivery retry still succeeds at most once per day")
    check(totalCount(full, "itemPotato") == beforeDuplicate, "a duplicate retry grants no extra items")
end)

test("cooking_service_keeps_freshness_and_refuses_spoiled_food", function(check)
    local chef = person({ job = "Chef" })
    local fresh = os.time() - 3600 * 42 // a quarter of the potato's 168-hour shelf life
    give(chef, "itemPotato", 3, "backpack", { createdAt = fresh })
    give(chef, "itemRawGameBird", 1, "backpack", { createdAt = os.time() - 3600 * 48 }) // spoiled (24h shelf life)
    local request, reason = Pro:CheckService(chef, chef, "cook", "itemPotato", 2, 0)
    check(request, "a Chef may cook for themselves: " .. tostring(reason))
    local ok, message = Pro:PerformService(chef, chef, request)
    check(ok, "cooking succeeds: " .. tostring(message))
    check(totalCount(chef, "itemPotato") == 1 and totalCount(chef, "itemBakedPotato") == 2, "two potatoes became two baked potatoes")
    local baked
    for _, item in pairs(chef.ZM_Inventory.backpack) do
        if item.itemId == "itemBakedPotato" then baked = item end
    end
    local freshness = baked and ZM_Food:GetFreshness(baked)
    check(freshness and math.abs(freshness - 0.75) < 0.02, "the cooked food keeps the raw food's freshness, got " .. tostring(freshness))
    check(storedCount(customerId, testProfile, "itemBakedPotato") == 2, "the cooked food was saved")
    check(not Pro:CheckService(chef, chef, "cook", "itemRawGameBird", 1, 0), "spoiled food cannot be cooked")
    check(not Pro:CheckService(chef, chef, "cook", "itemCannedBeans", 1, 0), "food without cooksInto cannot be cooked")
    local farmer = person({ job = "Farmer" })
    give(farmer, "itemPotato", 1)
    check(not Pro:CheckService(farmer, farmer, "cook", "itemPotato", 1, 0), "a Farmer does not offer cooking")
end)

test("services_transfer_the_fee_atomically", function(check)
    local customer = person({ cash = 100, health = 40 })
    local doctor = person({ steamId = providerId, job = "Doctor", cash = 10, pos = Vector(50, 0, 0) })
    check(ZM_SetPlayerData(customerId, testProfile, { Cash = 100 }, "profession test"), "the customer row exists")
    check(ZM_SetPlayerData(providerId, testProfile, { Cash = 10 }, "profession test"), "the provider row exists")
    give(customer, "itemPainkillers", 2)
    local request, reason = Pro:CheckService(customer, doctor, "treat", "itemPainkillers", 1, 25)
    check(request, "a nearby Doctor can treat: " .. tostring(reason))
    local ok, message = Pro:PerformService(customer, doctor, request)
    check(ok, "the treatment succeeds: " .. tostring(message))
    check(customer.health == 40 + math.floor(15 * 1.5 + 0.5), "the Doctor bonus applies to the customer, got " .. customer.health)
    check(totalCount(customer, "itemPainkillers") == 1 and storedCount(customerId, testProfile, "itemPainkillers") == 1, "one painkiller was consumed and saved")
    check(customer.Cash == 75 and doctor.Cash == 35, "the fee moved in memory")
    check(storedCash(customerId) == 75 and storedCash(providerId) == 35, "the fee moved in the database")

    check(not Pro:CheckService(customer, doctor, "treat", "itemPainkillers", 1, 500), "a fee above the customer's cash is refused")
    check(not Pro:CheckService(customer, customer, "treat", "itemPainkillers", 1, 5), "self-service cannot charge a fee")
    doctor.pos = Vector(Pro.ServiceRange + 100, 0, 0)
    check(not Pro:CheckService(customer, doctor, "treat", "itemPainkillers", 1, 0), "a distant professional cannot serve")
    doctor.pos = Vector(50, 0, 0)
    doctor.level, customer.ZM_Inventory = 1, Service.NewInventory()
    give(customer, "itemMorphine", 1)
    check(not Pro:CheckService(customer, doctor, "treat", "itemMorphine", 1, 0), "a level-1 Doctor cannot apply level-10 morphine")
end)

test("a_failed_fee_save_changes_nothing", function(check)
    local customer = person({ cash = 100 })
    local chef = person({ steamId = providerId, job = "Chef", pos = Vector(10, 0, 0) })
    check(ZM_SetPlayerData(customerId, testProfile, { Cash = 100 }, "profession test"), "the customer row exists")
    // The provider has no player_data row, so the provider cash step fails inside the transaction.
    give(customer, "itemPotato", 2)
    check(Service:Mutate(customer, function() return true end), "the starting inventory persists")
    local before = customer.ZM_Inventory
    local request = Pro:CheckService(customer, chef, "cook", "itemPotato", 2, 10)
    check(request, "the cooking request is valid")
    local ok = request and Pro:PerformService(customer, chef, request)
    check(not ok, "the service fails when the fee cannot be saved")
    check(customer.ZM_Inventory == before and totalCount(customer, "itemPotato") == 2 and storedCount(customerId, testProfile, "itemPotato") == 2, "no food was consumed")
    check(customer.Cash == 100 and chef.Cash == 0 and storedCash(customerId) == 100, "no cash moved")
end)

test("research_service_uses_the_scientist_recipe", function(check)
    local customer = person()
    local scientist = person({ steamId = providerId, job = "Scientist", pos = Vector(20, 0, 0) })
    give(customer, "itemHerbs", 2)
    give(customer, "itemBottledWater", 1)
    local request, reason = Pro:CheckService(customer, scientist, "research", "recipeResearchPainkillers", 1, 0)
    check(request, "a Scientist can research painkillers: " .. tostring(reason))
    local ok, message = request and Pro:PerformService(customer, scientist, request)
    check(ok, "research succeeds: " .. tostring(message))
    check(totalCount(customer, "itemPainkillers") == 2 and totalCount(customer, "itemHerbs") == 0, "the customer's ingredients became painkillers")
    check(not Pro:CheckService(customer, scientist, "research", "recipeResearchMorphine", 1, 0), "a level-1 Scientist cannot research morphine")
    check(not Pro:CheckService(customer, person({ steamId = providerId, job = "Doctor" }), "research", "recipeResearchPainkillers", 1, 0), "a Doctor cannot research")
    local crafting = ZM_CraftingService
    local refused, why = crafting:CheckStart(customer, "recipeResearchPainkillers", 1)
    check(not refused and string.find(tostring(why), "Scientist", 1, true), "the workbench refuses service recipes: " .. tostring(why))
end)

test("offers_are_single_use_and_expire", function(check)
    local customer = person({ health = 50 })
    local doctor = person({ steamId = providerId, job = "Doctor", pos = Vector(30, 0, 0) })
    give(customer, "itemPainkillers", 3)
    local sentOffer
    local originalSendOffer = Pro.SendOffer
    Pro.SendOffer = function(_, _, offer) sentOffer = offer end
    check(Pro:RequestService(customer, doctor, "treat", "itemPainkillers", 1, 0), "the request is sent")
    check(sentOffer ~= nil, "the provider receives the offer")
    check(not Pro:RequestService(customer, doctor, "treat", "itemPainkillers", 1, 0), "only one pending request per customer")
    check(not Pro:RespondToOffer(customer, sentOffer.id, true), "only the provider can respond")
    check(Pro:RespondToOffer(doctor, sentOffer.id, true), "the provider accepts")
    check(totalCount(customer, "itemPainkillers") == 2, "the accepted treatment consumed one painkiller")
    check(not Pro:RespondToOffer(doctor, sentOffer.id, true), "a replayed acceptance is refused")
    check(totalCount(customer, "itemPainkillers") == 2, "the replay consumed nothing")

    customer.health = 50
    check(Pro:RequestService(customer, doctor, "treat", "itemPainkillers", 1, 0), "a new request is sent")
    local stale = sentOffer.id
    Pro.Offers[stale].expiresAt = CurTime() - 1
    check(not Pro:RespondToOffer(doctor, stale, true), "an expired request cannot be accepted")
    check(totalCount(customer, "itemPainkillers") == 2, "the expired request consumed nothing")
    Pro.SendOffer = originalSendOffer
end)

function Pro:RunTests()
    local restoreStashAccess = ZM_TestHarness.StubStashAccess()
    local originalDayOffset = Pro.DayOffset
    Pro.DayOffset = 0
    local summary = suite:Run({ before = cleanup, after = cleanup })
    restoreStashAccess()
    Pro.DayOffset = originalDayOffset
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_professions", label = "Profession", file = "profession_tests.json", report = "professionTests",
    help = "Runs profession registry, daily delivery, and service tests against throwaway SteamIDs and profiles.",
    run = function() return Pro:RunTests() end
})
