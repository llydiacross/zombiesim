// Server-only Mastercrafting Station tests: credit grants/bounds/ledger, quote tokens (single use, expiry, price
// changes), in-place mastercrafts saved in one transaction with the credits and the attempt record, rollback on a failed
// save, eligibility gates, Ultra odds, paid job changes, and profile isolation.
// Uses stub players and throwaway SteamIDs/profiles/den; every row they write is removed afterwards.
local Svc = ZM_MastercraftService
local Credits = ZM_CreditService
local Professions = ZM_Professions
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items
local Generation = ZM_ItemGeneration
local StaticData = ZM_StaticData

local playerId = "STEAM_TEST:0:2830"
local testProfile = "zn_test_mc"
local otherProfile = "zn_test_mc2"
local testDen = "zn_test_mc_den"
local weaponId = "weaponMeleeCrowbar"

local function person(values)
    values = values or {}
    return {
        steamId = values.steamId or playerId,
        inDen = values.inDen ~= false,
        nearStation = values.nearStation ~= false,
        alive = true,
        job = values.job or "Civilian",
        Credits = 0,
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        Alive = function(self) return self.alive end,
        SteamID = function(self) return self.steamId end,
        Nick = function(self) return self.steamId end,
        GetJobRole = function(self) return Professions:Resolve(self.job) end,
        GetStoredJob = function(self) return self.job end,
        CurrentSafeZoneId = testDen,
        ZM_Inventory = Service.NewInventory(),
        ZM_Implants = {},
        ZM_InventoryProfile = values.profile or testProfile
    }
end

// Stubs hold their job in .job; ApplyJob writes .Job, so keep the two together.
local function syncJob(target)
    if target.Job then target.job = target.Job end
end

local function giveWeapon(target, container, extra)
    local options = { level = 10, seed = 5 }
    for key, value in pairs(extra or {}) do options[key] = value end
    local weapon = assert(Generation:CreateInstance(weaponId, options))
    assert(Ops.Add(target.ZM_Inventory, container or "backpack", weapon))
    return weapon
end

local function storedWeapon(steamId, profile, instanceId)
    for _, row in ipairs(ZM_GetPlayerItems(steamId, profile) or {}) do
        if row.instanceId == instanceId then return row end
    end
end

local function stored(target)
    return ZM_GetPlayerCredits(target:SteamID(), target.ZM_InventoryProfile)
end

local function quoteAndConfirm(target, kind, ref, options)
    local quoted, quote = Svc:Quote(target, kind, ref)
    if not quoted then return false, quote end
    return Svc:Confirm(target, quote.id, options)
end

local function cleanup()
    for _, profile in ipairs({ testProfile, otherProfile }) do
        ZM_DeletePlayerItems(playerId, profile)
        ZM_DeletePlayerCredits(playerId, profile)
        ZM_ReplaceDenStashItems(playerId, profile, testDen, {})
        sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(playerId) .. " AND profile = " .. sql.SQLStr(profile))
    end
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("shipped_den_services_and_cost_formula", function(check)
    local services = StaticData:GetDenServices()
    check(services and services.mastercraft.baseCredits == 5 and services.jobChange.credits == 25, "the shipped prices load")
    check(StaticData:GetMastercraftCost(1) == 6, "level 1 costs 5 + ceil(0.5)")
    check(StaticData:GetMastercraftCost(10) == 10, "level 10 costs 5 + 5")
    check(StaticData:GetMastercraftCost(11) == 11, "fractions round up")
    local definition = Items:GetDefinition(weaponId)
    local best, nearly = {}, {}
    for index, name in ipairs(definition.attributes) do
        best[name] = definition.maxAttributes
        nearly[name] = index == 1 and definition.maxAttributes - 1 or definition.maxAttributes
    end
    check(Items:IsUltraMastercraft({ itemId = weaponId, mastercraft = true, attributes = best }), "all-max attributes are Ultra")
    check(not Items:IsUltraMastercraft({ itemId = weaponId, mastercraft = true, attributes = nearly }), "one attribute short of max is not Ultra")
    check(not Items:IsUltraMastercraft({ itemId = weaponId, mastercraft = false, attributes = {} }), "an ordinary weapon is not Ultra")
end)

test("credits_grant_bound_ledger_and_isolate_profiles", function(check)
    local target = person()
    check(Credits:Grant(target, 40, "test grant"), "a grant succeeds")
    check(Credits:Get(target) == 40 and stored(target) == 40, "the grant is in memory and stored")
    check(not Credits:Grant(target, -41, "overspend"), "a balance cannot go below 0")
    check(not Credits:Grant(target, 1.5, "fraction"), "credits are whole numbers")
    check(not Credits:Grant(target, StaticData.MaximumCredits, "overflow"), "a balance cannot exceed the maximum")
    check(Credits:Grant(target, -15, "spend"), "a negative grant removes credits")
    check(stored(target) == 25, "the removal is stored")
    local ledger = ZM_GetCreditLedger(playerId, testProfile, 10) or {}
    check(#ledger == 2 and tonumber(ledger[1].delta) == -15 and tonumber(ledger[1].balance) == 25 and tonumber(ledger[2].delta) == 40, "each change writes a ledger row, newest first")
    local other = person({ profile = otherProfile })
    check(Credits:Load(other) and Credits:Get(other) == 0, "another profile has its own balance")
    local reloaded = person()
    check(Credits:Load(reloaded) and Credits:Get(reloaded) == 25, "the balance reloads")
end)

test("a_stale_balance_is_refused_by_the_save", function(check)
    local target = person()
    Credits:Grant(target, 20, "test grant")
    target.Credits = 50
    check(not Credits:Grant(target, -10, "stale spend"), "a step whose expected balance no longer matches the database fails")
    check(stored(target) == 20 and #(ZM_GetCreditLedger(playerId, testProfile, 10) or {}) == 1, "nothing was written")
end)

test("a_mastercraft_upgrades_in_place_and_spends_credits", function(check)
    local target = person()
    local weapon = giveWeapon(target)
    Credits:Grant(target, 100, "test grant")
    local cost = StaticData:GetMastercraftCost(weapon.level)
    local ok, message, result = quoteAndConfirm(target, "mastercraft", weapon.instanceId, { seed = 3 })
    check(ok, "the mastercraft succeeds: " .. tostring(message))
    local _, _, live = Ops.FindInstance(target.ZM_Inventory, weapon.instanceId)
    check(live and live.mastercraft and live.level == weapon.level and live.itemId == weaponId, "the same instance is now a mastercraft at the same level")
    local definition = Items:GetDefinition(weaponId)
    local inRange = live ~= nil
    for _, name in ipairs(definition.attributes) do
        local value = live and live.attributes[name]
        inRange = inRange and value ~= nil and value >= definition.maxAttributes - 1 and value <= definition.maxAttributes
    end
    check(inRange, "every attribute is within one point of the maximum")
    check(result and result.instanceId == weapon.instanceId, "the result names the upgraded instance")
    check(Credits:Get(target) == 100 - cost and stored(target) == 100 - cost, "the cost is deducted in memory and storage")
    local row = storedWeapon(playerId, testProfile, weapon.instanceId)
    check(row and tonumber(row.mastercraft) == 1, "the stored instance is a mastercraft")
    local attempt = ZM_GetMastercraftAttempt(playerId, testProfile, weapon.instanceId)
    check(attempt and tonumber(attempt.credits) == cost and attempt.itemId == weaponId, "the attempt is recorded")
    local ledger = ZM_GetCreditLedger(playerId, testProfile, 1) or {}
    check(ledger[1] and tonumber(ledger[1].delta) == -cost and ledger[1].reason == "mastercraft" and ledger[1].ref == weapon.instanceId, "the ledger records the spend against the instance")
    check(not Svc:Quote(target, "mastercraft", weapon.instanceId), "a mastercraft cannot be mastercrafted again")
end)

test("a_failed_save_rolls_everything_back", function(check)
    local target = person()
    local weapon = giveWeapon(target)
    Credits:Grant(target, 100, "test grant")
    Service:Mutate(target, function() return true end)
    local quoted, quote = Svc:Quote(target, "mastercraft", weapon.instanceId)
    check(quoted, "the quote is issued")
    sql.Query("UPDATE player_credits SET credits = 99 WHERE steamid = " .. sql.SQLStr(playerId) .. " AND profile = " .. sql.SQLStr(testProfile))
    local ok = Svc:Confirm(target, quoted and quote.id)
    check(not ok, "the confirmation fails when the stored balance changed underneath it")
    local _, _, live = Ops.FindInstance(target.ZM_Inventory, weapon.instanceId)
    check(live and not live.mastercraft and util.TableToJSON(live.attributes) == util.TableToJSON(weapon.attributes), "the live weapon is unchanged")
    local row = storedWeapon(playerId, testProfile, weapon.instanceId)
    check(row and tonumber(row.mastercraft) == 0, "the stored weapon is unchanged")
    check(ZM_GetMastercraftAttempt(playerId, testProfile, weapon.instanceId) == false, "no attempt was recorded")
    check(stored(target) == 99 and Credits:Get(target) == 100, "no credits were spent")
end)

test("quotes_are_single_use_expire_and_track_price", function(check)
    local target = person()
    local weapon = giveWeapon(target)
    Credits:Grant(target, 100, "test grant")
    local _, quote = Svc:Quote(target, "mastercraft", weapon.instanceId)
    check(not Svc:Confirm(target, "not-the-token"), "a wrong token is refused")
    check(not Svc:Confirm(target, quote.id), "the refused attempt consumed the quote")
    _, quote = Svc:Quote(target, "mastercraft", weapon.instanceId)
    target.ZM_StationQuote.expiresAt = CurTime() - 1
    check(not Svc:Confirm(target, quote.id), "an expired quote is refused")
    _, quote = Svc:Quote(target, "mastercraft", weapon.instanceId)
    local services = StaticData:GetDenServices()
    local originalBase = services.mastercraft.baseCredits
    services.mastercraft.baseCredits = originalBase + 7
    local changed, reason = Svc:Confirm(target, quote.id)
    services.mastercraft.baseCredits = originalBase
    check(not changed and string.find(tostring(reason), "price changed", 1, true), "a price change is refused")
    check(Credits:Get(target) == 100 and stored(target) == 100, "no refused confirmation spent credits")
    _, quote = Svc:Quote(target, "mastercraft", weapon.instanceId)
    check(Svc:Confirm(target, quote.id), "a fresh quote confirms")
    check(not Svc:Confirm(target, quote.id), "a spent quote cannot be replayed")
end)

test("eligibility_gates", function(check)
    local target = person()
    local equipped = giveWeapon(target, "equipped")
    local stashed = giveWeapon(target, "stash")
    local mastercraft = giveWeapon(target, "backpack", { mastercraft = true })
    assert(Ops.Add(target.ZM_Inventory, "backpack", assert(Generation:CreateInstance("itemBandage", {}))))
    Credits:Grant(target, 5, "test grant")
    check(not Svc:Quote(target, "mastercraft", equipped.instanceId), "an equipped weapon is refused")
    check(not Svc:Quote(target, "mastercraft", stashed.instanceId), "a stashed weapon is refused")
    check(not Svc:Quote(target, "mastercraft", mastercraft.instanceId), "an existing mastercraft is refused")
    check(not Svc:Quote(target, "mastercraft", "itemBandage"), "a non-weapon is refused")
    local ordinary = giveWeapon(target)
    local poor, poorReason = Svc:Quote(target, "mastercraft", ordinary.instanceId)
    check(not poor and string.find(tostring(poorReason), "costs", 1, true), "too few credits are refused")
    Credits:Grant(target, 100, "test grant")
    check(Svc:Quote(target, "mastercraft", weaponId), "an item id resolves to the ordinary backpack weapon")
    target.nearStation = false
    check(not Svc:Quote(target, "mastercraft", ordinary.instanceId), "away from a station is refused")
    target.nearStation, target.inDen = true, false
    check(not Svc:Quote(target, "mastercraft", ordinary.instanceId), "outside a den is refused")
    target.inDen, target.ZM_Inventory = true, nil
    check(not Svc:Quote(target, "mastercraft", ordinary.instanceId), "an unloaded inventory is refused")
end)

test("ultra_odds_follow_static_data", function(check)
    local definition = Items:GetDefinition(weaponId)
    local rng = Generation.NewRng(17)
    local chance = StaticData:GetDenServices().mastercraft.ultraChance
    local ultras = 0
    for _ = 1, 5000 do
        local attributes = Generation:RollAttributes(definition, 10, true, rng, chance)
        if Items:IsUltraMastercraft({ itemId = weaponId, mastercraft = true, attributes = attributes }) then ultras = ultras + 1 end
    end
    check(ultras / 5000 > 0.002 and ultras / 5000 < 0.03, "about 1% of station rolls are Ultra (" .. ultras .. "/5000)")
    local target = person()
    local weapon = giveWeapon(target)
    Credits:Grant(target, 100, "test grant")
    local services = StaticData:GetDenServices()
    local original = services.mastercraft.ultraChance
    services.mastercraft.ultraChance = 1
    local ok, message = quoteAndConfirm(target, "mastercraft", weapon.instanceId)
    services.mastercraft.ultraChance = original
    local _, _, live = Ops.FindInstance(target.ZM_Inventory, weapon.instanceId)
    check(ok and live and Items:IsUltraMastercraft(live), "a certain roll is Ultra")
    check(string.find(tostring(message), "ULTRA", 1, true) ~= nil, "the result announces the Ultra")
    local attempt = ZM_GetMastercraftAttempt(playerId, testProfile, weapon.instanceId)
    check(attempt and tonumber(attempt.ultra) == 1, "the attempt records the Ultra")
    check(Items:GetDisplayName(live) == definition.name .. " (Ultra MC)", "the display name marks the Ultra")
end)

test("a_paid_job_change", function(check)
    local target = person()
    ZM_SetPlayerData(playerId, testProfile, { Cash = 0 })
    Credits:Grant(target, 30, "test grant")
    check(not Svc:Quote(target, "job", "Civilian"), "the current job is refused")
    check(not Svc:Quote(target, "job", "NotAJob"), "an unknown job is refused")
    local ok, message = quoteAndConfirm(target, "job", "Doctor")
    syncJob(target)
    check(ok, "the job change succeeds: " .. tostring(message))
    check(target.Job == "Doctor" and (ZM_GetPlayerData(playerId, testProfile) or {}).Job == "Doctor", "the job is applied and stored")
    check(Credits:Get(target) == 5 and stored(target) == 5, "the job change cost 25 credits")
    check(not Svc:Quote(target, "job", "Chef"), "too few credits are refused")
    local missing = person({ profile = otherProfile })
    Credits:Grant(missing, 30, "test grant")
    check(not quoteAndConfirm(missing, "job", "Doctor") and stored(missing) == 30, "without a player record nothing is spent")
end)

function Svc:RunTests()
    local restoreStashAccess = ZM_TestHarness.StubStashAccess()
    local originalFindStation = Svc.FindStation
    Svc.FindStation = function(self, target)
        if type(target) == "table" and target.nearStation ~= nil then return target.nearStation and {} or nil end
        return originalFindStation(self, target)
    end
    local summary = suite:Run({ before = cleanup, after = cleanup })
    restoreStashAccess()
    Svc.FindStation = originalFindStation
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_mastercraft", label = "Mastercraft", file = "mastercraft_tests.json", report = "mastercraftTests",
    help = "Runs credit, quote, mastercraft, Ultra, and paid job change tests against throwaway SteamIDs and profiles.",
    run = function() return Svc:RunTests() end
})
