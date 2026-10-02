// Server-only implant tests: effect interpolation and caps, Doctor install/replace/extract with one-transaction saves,
// level and profession gates, persistence and profile isolation, death retention, loot weight bonuses, and XP scaling.
// Uses stub players and throwaway SteamIDs/profiles/den; every row they write is removed afterwards.
local Svc = ZM_ImplantService
local Implants = ZM_Implants
local Pro = ZM_ProfessionService
local Professions = ZM_Professions
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items
local StaticData = ZM_StaticData

local customerId = "STEAM_TEST:0:2820"
local providerId = "STEAM_TEST:0:2821"
local testProfile = "zn_test_impl"
local otherProfile = "zn_test_impl2"
local testDen = "zn_test_impl_den"

local nextId = 0
local function instance(itemId, count, extra)
    nextId = nextId + 1
    local definition = Items:GetDefinition(itemId)
    local result = { instanceId = "impl" .. nextId, itemId = itemId, count = count or 1, level = definition.minLevel, mastercraft = false, clip = 0, createdAt = 0 }
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
        ZM_Implants = {},
        ZM_InventoryProfile = values.profile or testProfile
    }
end

local function give(target, itemId, extra)
    local placed = instance(itemId, 1, extra)
    assert(Ops.Add(target.ZM_Inventory, "backpack", placed))
    return placed
end

local function storedImplants(steamId, profile)
    local bySlot = {}
    for _, row in ipairs(ZM_GetPlayerImplants(steamId, profile) or {}) do bySlot[row.slot] = row end
    return bySlot
end

local function storedCount(steamId, profile, itemId)
    local total = 0
    for _, row in ipairs(ZM_GetPlayerItems(steamId, profile) or {}) do
        if row.itemId == itemId then total = total + tonumber(row.count) end
    end
    return total
end

local function storedCash(steamId)
    local data = ZM_GetPlayerData(steamId, testProfile)
    return data and tonumber(data.Cash) or nil
end

local function cleanup()
    for _, steamId in ipairs({ customerId, providerId }) do
        for _, profile in ipairs({ testProfile, otherProfile }) do
            ZM_DeletePlayerItems(steamId, profile)
            ZM_DeletePlayerImplants(steamId, profile)
            ZM_ReplaceDenStashItems(steamId, profile, testDen, {})
            sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(steamId) .. " AND profile = " .. sql.SQLStr(profile))
        end
    end
end

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("shipped_implants_and_loot_categories_resolve", function(check)
    local regen = Implants:GetDefinition("itemImplantRegenMesh")
    check(regen and regen.implant.slot == "Dermal", "the regen mesh is a Dermal implant")
    check(Implants:GetDefinition("itemBandage") == nil, "a bandage is not an implant")
    check(StaticData:GetItem("itemImplantRegenMesh").lootCategory == "implants", "implants derive the implants loot category")
    check(StaticData:GetItem("ammo9mm").lootCategory == "ammo", "ammo derives the ammo loot category")
    check(StaticData:GetItem("itemBandage").lootCategory == "medical", "the bandage is medical")
    check(StaticData:GetItem("itemCashBundle").lootCategory == "cash", "the cash bundle is cash")
    check(Professions:OffersService("Doctor", "implant") and Professions:OffersService("Doctor", "extract"), "Doctors install and remove implants")
    check(not Professions:OffersService("Chef", "implant"), "Chefs do not")
end)

test("effects_interpolate_by_level_and_cap", function(check)
    local regen = Implants:GetDefinition("itemImplantRegenMesh")
    check(near(Implants:GetEffectValue(regen, 1, "healthRegen"), 1), "level 1 uses the minimum")
    check(near(Implants:GetEffectValue(regen, 50, "healthRegen"), 5), "level 50 uses the maximum")
    check(near(Implants:GetEffectValue(regen, 25.5, "healthRegen"), 3), "the midpoint interpolates")
    check(Implants:GetEffectValue(regen, 1, "xpGain") == 0, "an effect the implant lacks is 0")
    local installed = {
        Dermal = { instanceId = "a", itemId = "itemImplantRegenMesh", level = 50 },
        Neural = { instanceId = "b", itemId = "itemImplantCortexBooster", level = 1 },
        Ocular = { instanceId = "c", itemId = "itemImplantRegenMesh", level = 50 }
    }
    local aggregate = Implants:Aggregate(installed)
    check(near(aggregate.effects.healthRegen, 5), "an implant in the wrong slot contributes nothing")
    check(near(aggregate.effects.xpGain, 0.05), "the Neural implant contributes xpGain")
    local rule = StaticData.ImplantEffects.healthRegen
    local originalCap = rule.cap
    rule.cap = 2
    local capped = Implants:Aggregate(installed)
    rule.cap = originalCap
    check(near(capped.effects.healthRegen, 2) and capped.capped.healthRegen and near(capped.uncapped.healthRegen, 5), "the sum is clamped to the cap and flagged")
    check(Implants:Aggregate({ Dermal = { itemId = "itemRemovedImplant", level = 1 } }).effects.healthRegen == nil, "unknown implants are ignored")
end)

test("a_doctor_installs_replaces_and_extracts", function(check)
    local doctor = person({ job = "Doctor" })
    local first = give(doctor, "itemImplantRegenMesh")
    local request, reason = Pro:CheckService(doctor, doctor, "implant", "itemImplantRegenMesh", 1, 0)
    check(request, "a Doctor may self-install: " .. tostring(reason))
    local ok, message = request and Pro:PerformService(doctor, doctor, request)
    check(ok, "installation succeeds: " .. tostring(message))
    check(doctor.ZM_Implants.Dermal and doctor.ZM_Implants.Dermal.instanceId == first.instanceId, "the implant is in the Dermal slot")
    check(Ops.Count(doctor.ZM_Inventory, "itemImplantRegenMesh", "backpack") == 0 and storedCount(customerId, testProfile, "itemImplantRegenMesh") == 0, "it left the backpack and the saved items")
    check(storedImplants(customerId, testProfile).Dermal ~= nil, "the implant row was saved")
    check(Svc:GetEffect(doctor, "healthRegen") > 0, "the modifier is active")

    local second = give(doctor, "itemImplantMyofiberWeave")
    request = Pro:CheckService(doctor, doctor, "implant", second.instanceId, 1, 0)
    ok, message = request and Pro:PerformService(doctor, doctor, request)
    check(ok, "replacement succeeds: " .. tostring(message))
    check(doctor.ZM_Implants.Dermal.itemId == "itemImplantMyofiberWeave", "the new implant is installed")
    check(Ops.Count(doctor.ZM_Inventory, "itemImplantRegenMesh", "backpack") == 1 and storedCount(customerId, testProfile, "itemImplantRegenMesh") == 1, "the replaced implant returned to the backpack")
    check(Svc:GetEffect(doctor, "healthRegen") == 0 and Svc:GetEffect(doctor, "moveSpeed") > 0, "the modifiers follow the installed implant")

    check(not Pro:CheckService(doctor, doctor, "extract", "Neural", 1, 0), "an empty slot cannot be extracted")
    request = Pro:CheckService(doctor, doctor, "extract", "Dermal", 1, 0)
    ok, message = request and Pro:PerformService(doctor, doctor, request)
    check(ok, "extraction succeeds: " .. tostring(message))
    check(doctor.ZM_Implants.Dermal == nil and storedImplants(customerId, testProfile).Dermal == nil, "the slot is empty in memory and saved")
    check(Ops.Count(doctor.ZM_Inventory, "itemImplantMyofiberWeave", "backpack") == 1, "the extracted implant is in the backpack")
end)

test("gates_refuse_without_changes", function(check)
    local civilian = person()
    give(civilian, "itemImplantRegenMesh")
    check(not Pro:CheckService(civilian, civilian, "implant", "itemImplantRegenMesh", 1, 0), "a Civilian cannot install implants")
    local doctor = person({ steamId = providerId, job = "Doctor", pos = Vector(20, 0, 0) })
    civilian.ZM_Inventory = Service.NewInventory()
    give(civilian, "itemImplantRegenMesh", { level = 30 })
    check(not Pro:CheckService(civilian, doctor, "implant", "itemImplantRegenMesh", 1, 0), "a level-1 Doctor cannot install a level-30 implant")
    doctor.level = 30
    local request = Pro:CheckService(civilian, doctor, "implant", "itemImplantRegenMesh", 1, 0)
    check(request, "a level-30 Doctor can")
    check(request and Pro:PerformService(civilian, doctor, request), "the installation succeeds")
    doctor.level = 1
    check(not Pro:CheckService(civilian, doctor, "extract", "Dermal", 1, 0), "a level-1 Doctor cannot remove a level-30 implant")
    doctor.level = 30
    for _ = 1, Items.ContainerCapacity.backpack do
        Ops.Add(civilian.ZM_Inventory, "backpack", instance("itemImplantCortexBooster", 1))
    end
    check(not Pro:CheckService(civilian, doctor, "extract", "Dermal", 1, 0), "extraction needs a free backpack slot")
    local before = civilian.ZM_Inventory
    local ok = Svc:Extract(civilian, "Dermal")
    check(not ok and civilian.ZM_Inventory == before and civilian.ZM_Implants.Dermal ~= nil and storedImplants(customerId, testProfile).Dermal ~= nil, "a direct extraction into a full backpack changes nothing")
end)

test("a_failed_fee_save_changes_nothing", function(check)
    local customer = person({ cash = 100 })
    local doctor = person({ steamId = providerId, job = "Doctor", pos = Vector(10, 0, 0) })
    check(ZM_SetPlayerData(customerId, testProfile, { Cash = 100 }, "implant test"), "the customer row exists")
    // The provider has no player_data row, so the provider cash step fails inside the transaction.
    give(customer, "itemImplantCortexBooster")
    check(Service:Mutate(customer, function() return true end), "the starting inventory persists")
    local before = customer.ZM_Inventory
    local request = Pro:CheckService(customer, doctor, "implant", "itemImplantCortexBooster", 1, 10)
    check(request, "the installation request is valid")
    local ok = request and Pro:PerformService(customer, doctor, request)
    check(not ok, "the service fails when the fee cannot be saved")
    check(customer.ZM_Inventory == before and storedCount(customerId, testProfile, "itemImplantCortexBooster") == 1, "the implant stayed in the backpack")
    check(customer.ZM_Implants.Neural == nil and storedImplants(customerId, testProfile).Neural == nil, "nothing was installed")
    check(customer.Cash == 100 and storedCash(customerId) == 100, "no cash moved")
end)

test("a_paid_installation_moves_the_fee", function(check)
    local customer = person({ cash = 100 })
    local doctor = person({ steamId = providerId, job = "Doctor", cash = 5, pos = Vector(10, 0, 0) })
    check(ZM_SetPlayerData(customerId, testProfile, { Cash = 100 }, "implant test"), "the customer row exists")
    check(ZM_SetPlayerData(providerId, testProfile, { Cash = 5 }, "implant test"), "the provider row exists")
    give(customer, "itemImplantTargetingLens")
    local request = Pro:CheckService(customer, doctor, "implant", "itemImplantTargetingLens", 1, 20)
    local ok, message = request and Pro:PerformService(customer, doctor, request)
    check(ok, "the paid installation succeeds: " .. tostring(message))
    check(customer.Cash == 80 and doctor.Cash == 25 and storedCash(customerId) == 80 and storedCash(providerId) == 25, "the fee moved in memory and the database")
    check(customer.ZM_Implants.Ocular ~= nil and storedImplants(customerId, testProfile).Ocular ~= nil, "the lens is installed")
end)

test("implants_persist_per_profile_and_survive_death", function(check)
    local doctor = person({ job = "Doctor" })
    give(doctor, "itemImplantFortuneChip", { level = 50 })
    check(Svc:Install(doctor, "itemImplantFortuneChip"), "the chip installs")
    check(Service:LoseBackpack(doctor), "the backpack is lost on death")
    check(doctor.ZM_Implants.Neural ~= nil and storedImplants(customerId, testProfile).Neural ~= nil, "death keeps the implant")

    local reloaded = person()
    reloaded.ZM_Implants = nil
    check(Svc:Load(reloaded), "implants load")
    local chip = reloaded.ZM_Implants.Neural
    check(chip and chip.itemId == "itemImplantFortuneChip" and chip.level == 50, "the reloaded implant keeps its item and level")
    check(near(Svc:GetEffect(reloaded, "lootCash"), 0.4), "the reloaded modifiers are active")

    local other = person({ profile = otherProfile })
    check(Svc:Load(other) and next(other.ZM_Implants) == nil, "another profile has no implants")
    check(Svc:Clear(reloaded) and next(reloaded.ZM_Implants) == nil and next(storedImplants(customerId, testProfile)) == nil, "clearing removes every implant row")
    check(Svc:GetEffect(reloaded, "lootCash") == 0, "clearing removes the modifiers")
end)

test("loot_bonuses_boost_only_the_matching_category", function(check)
    local group = StaticData:GetLootGroup("lootGenericZombie")
    check(group, "the generic zombie group exists")
    if not group then return end
    local function totals(bonuses)
        local weights = ZM_Loot.GetWeights(group.entries, 0.5, bonuses)
        local byCategory, total = {}, 0
        for _, candidate in ipairs(weights) do
            local category = StaticData:GetItem(candidate.entry.item).lootCategory
            byCategory[category] = (byCategory[category] or 0) + candidate.weight
            total = total + candidate.weight
        end
        return byCategory, total
    end
    local base = totals(nil)
    local boosted = totals({ ammo = 0.5, implants = 1 })
    check(base.ammo and near(boosted.ammo, base.ammo * 1.5), "ammo weight is multiplied by 1.5")
    for category, weight in pairs(base) do
        if category ~= "ammo" then
            check(near(boosted[category], weight), category .. " weight is unchanged")
        end
    end
    local lens = person()
    lens.ZM_Implants = { Ocular = { instanceId = "x", itemId = "itemImplantTargetingLens", level = 50 } }
    Svc:Refresh(lens)
    local bonuses = Svc:GetLootBonuses(lens)
    check(near(bonuses.weapons or 0, 0.3) and near(bonuses.ammo or 0, 0.2) and bonuses.cash == nil, "the targeting lens boosts weapons and ammo only")
    local rolledPlain = ZM_Loot:RollItem(group.entries, { danger = 0.5, seed = 99 })
    local rolledEmpty = ZM_Loot:RollItem(group.entries, { danger = 0.5, seed = 99, lootBonuses = {} })
    check(rolledPlain and rolledEmpty and rolledPlain.itemId == rolledEmpty.itemId, "empty bonuses do not change a seeded roll")
end)

test("xp_gain_scales_awards", function(check)
    local target = person()
    check(Svc:ScaleXP(target, 100) == 100, "no implant leaves XP unchanged")
    target.ZM_Implants = { Neural = { instanceId = "x", itemId = "itemImplantCortexBooster", level = 50 } }
    Svc:Refresh(target)
    check(Svc:ScaleXP(target, 100) == 125, "a level-50 booster adds 25%")
    check(Svc:ScaleXP(target, 3) == 4, "awards round to whole points")
    check(Svc:ScaleXP(target, -10) == -10 and Svc:ScaleXP(target, 0) == 0, "non-positive amounts are not scaled")
end)

function Svc:RunTests()
    local restoreStashAccess = ZM_TestHarness.StubStashAccess()
    local summary = suite:Run({ before = cleanup, after = cleanup })
    restoreStashAccess()
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_implants", label = "Implant", file = "implant_tests.json", report = "implantTests",
    help = "Runs implant effect, Doctor service, persistence, and loot/XP modifier tests against throwaway SteamIDs and profiles.",
    run = function() return Svc:RunTests() end
})
