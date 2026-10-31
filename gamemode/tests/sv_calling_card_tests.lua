local Cards = ZM_CallingCardService
local Trade = ZM_TradeService
local Credits = ZM_CreditService
local suite = ZM_TestHarness.NewSuite()
local profile, otherProfile, prefix
local tables = { "calling_card_unlocks", "calling_card_selections", "player_credits", "credit_ledger", "trade_ledger" }
local catalogue = {
    byId = {
        background_default = { id = "background_default", category = "background" },
        detail_default = { id = "detail_default", category = "detail" },
        background_both = { id = "background_both", category = "background", name = "Both", shopCredits = 80, questReward = true },
        background_shop = { id = "background_shop", category = "background", name = "Shop", shopCredits = 100, questReward = false },
        detail_quest = { id = "detail_quest", category = "detail", name = "Quest", questReward = true }
    },
    aliases = { background_old = "background_both" }
}

local function person(account, character, worldProfile)
    local target = {
        valid = true, ZM_PersistentStateLoaded = true, ZM_InventoryProfile = worldProfile or profile,
        ZM_Inventory = { backpack = {} }, CurrentSafeZoneId = "zn_test_card_den", inDen = true,
        Credits = 0, nw = {}, position = Vector(0, 0, 0)
    }
    function target:IsValid() return true end
    function target:IsPlayer() return false end
    function target:IsBot() return false end
    function target:Alive() return true end
    function target:SteamID() return account end
    function target:GetCharacterKey() return prefix .. "_" .. character end
    function target:GetPos() return self.position end
    function target:SetNWString(key, value) self.nw[key] = value end
    return target
end

local function trader(position)
    local target = { valid = true, ZM_IsDenNpc = true, ZM_Config = { trader = "general" },
        trader = "general", position = position or Vector(0, 0, 0) }
    function target:IsValid() return true end
    function target:GetPos() return self.position end
    return target
end

local function rows(tableName, selectedProfile)
    local value = sql.QueryValue("SELECT COUNT(*) FROM " .. tableName .. " WHERE profile = " .. sql.SQLStr(selectedProfile))
    assert(value ~= nil and value ~= false, "Could not count " .. tableName .. ": " .. tostring(sql.LastError()))
    return tonumber(value)
end

suite:Add("defaults and locked selections", function(check)
    local target = person("STEAM_0:1:2147483640", "defaults")
    local snapshot, failure = Cards:Snapshot(target)
    assert(snapshot, failure)
    check(snapshot.owned.background_default and snapshot.owned.detail_default
        and snapshot.selection.background == "background_default" and snapshot.selection.detail == "detail_default",
        "new survivors receive both defaults without an unlock row")
    check(rows("calling_card_unlocks", profile) == 0 and rows("calling_card_selections", profile) == 0,
        "reading defaults writes no rows")
    local ok = Cards:Select(target, "background", "background_shop")
    check(not ok and rows("calling_card_selections", profile) == 0, "locked choices cannot be saved")
end)

suite:Add("quest rewards are shared per account and profile, selections per survivor", function(check)
    local account = "STEAM_0:1:2147483641"
    local first = person(account, "first")
    local second = person(account, "second")
    local elsewhere = person(account, "elsewhere", otherProfile)
    local stranger = person("STEAM_0:1:2147483644", "stranger")
    local granted, message = Cards:GrantReward(first, "background_old", "fixture")
    assert(granted, message)
    check(not Cards:GrantReward(first, "background_shop", "fixture"), "shop-only cards cannot be quest rewards")
    local firstState, secondState = Cards:Snapshot(first), Cards:Snapshot(second)
    local otherState, strangerState = Cards:Snapshot(elsewhere), Cards:Snapshot(stranger)
    assert(firstState and secondState and otherState and strangerState, "fixture snapshots must load")
    check(firstState.owned.background_both and secondState.owned.background_both
        and not otherState.owned.background_both and not strangerState.owned.background_both,
        "aliased reward ownership is shared only by the same account and profile")
    check(Cards:Select(first, "background", "background_both"), "owned background can be selected")
    local restored = person(account, "first")
    check(Cards:Load(restored) and restored.nw.ZM_CallingCardBackground == "background_both"
        and Cards:Snapshot(second).selection.background == "background_default",
        "reconnect restores the first survivor while the second retains its default")
end)

suite:Add("trader debit, ownership and replay protection", function(check)
    local account = "STEAM_0:1:2147483642"
    local buyer = person(account, "buyer")
    local other = person(account, "buyer_sibling")
    local npc = trader()
    assert(Credits:Grant(buyer, 300, "calling card fixture"))
    local function purchase(id, price, requestId)
        return Trade:BuyCallingCard(buyer, npc, { id = id, price = price, requestId = requestId })
    end
    buyer.inDen = false
    check(not purchase("background_shop", 100, "outside"), "outside-den access is refused")
    buyer.inDen = true
    npc.position = Vector(1000, 0, 0)
    check(not purchase("background_shop", 100, "far"), "distant traders are refused")
    npc.position = Vector(0, 0, 0)
    check(not purchase("background_shop", 99, "stale") and not purchase("detail_quest", 100, "quest"),
        "stale prices and quest-only purchases are refused")
    local ok, message = purchase("background_shop", 100, "buy")
    assert(ok, message)
    check(Credits:Get(buyer) == 200 and ZM_GetPlayerCredits(buyer:GetCharacterKey(), profile) == 200
        and Cards:Snapshot(other).owned.background_shop, "the debit and account unlock both persist")
    check(not purchase("background_shop", 100, "buy") and not purchase("background_shop", 100, "another")
        and Credits:Get(buyer) == 200 and rows("trade_ledger", profile) == 1,
        "replay and a second purchase do not charge again")
    check(next(buyer.ZM_Inventory.backpack) == nil, "calling cards do not occupy inventory")
end)

suite:Add("stale credit writes roll back without an unlock or ledger entry", function(check)
    local buyer = person("STEAM_0:1:2147483643", "stale_credit")
    assert(Credits:Grant(buyer, 100, "calling card fixture"))
    buyer.Credits = 200
    local ok, message = Trade:BuyCallingCard(buyer, trader(), { id = "background_shop", price = 100, requestId = "stale_credit" })
    check(not ok and string.find(tostring(message), "balance changed", 1, true) ~= nil,
        "the conditional credit write reports stale state")
    check(ZM_GetPlayerCredits(buyer:GetCharacterKey(), profile) == 100
        and not Cards:Snapshot(buyer).owned.background_shop and rows("trade_ledger", profile) == 1,
        "the failed transaction preserves the balance and creates neither purchase nor ledger")
end)

local function failureSummary(name, message)
    return { passed = 0, failed = 1, ranAt = os.time(), cases = {
        { name = name, passed = false, failures = { tostring(message) } }
    } }
end

local function cleanProfiles()
    local failures = {}
    for _, selectedProfile in ipairs({ profile, otherProfile }) do
        for _, name in ipairs(tables) do
            local result = sql.Query("DELETE FROM " .. name .. " WHERE profile = " .. sql.SQLStr(selectedProfile))
            if result == false then
                failures[#failures + 1] = name .. " / " .. selectedProfile .. ": " .. tostring(sql.LastError())
            elseif rows(name, selectedProfile) ~= 0 then
                failures[#failures + 1] = name .. " / " .. selectedProfile .. ": rows remain"
            end
        end
    end
    return failures
end

function Cards:RunTests()
    prefix = "zn_card_test_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    profile, otherProfile = prefix, prefix .. "_other"
    for _, selectedProfile in ipairs({ profile, otherProfile }) do
        for _, name in ipairs(tables) do
            local ok, count = pcall(rows, name, selectedProfile)
            if not ok or count ~= 0 then return failureSummary("fixture_preflight", ok and
                ("Refusing to overwrite existing test profile " .. selectedProfile) or count) end
        end
    end

    local originalCatalogue, originalDanger = self.Catalogue, Trade.DangerOverride
    local restoreStash = ZM_TestHarness.StubStashAccess()
    self.Catalogue = function() return catalogue end
    Trade.DangerOverride = 0
    local ok, summary = xpcall(function() return suite:Run() end, debug.traceback)
    self.Catalogue, Trade.DangerOverride = originalCatalogue, originalDanger
    restoreStash()
    local cleanOk, cleanup = pcall(cleanProfiles)
    if not ok then summary = failureSummary("fixture_runtime", summary) end
    if not cleanOk then cleanup = { tostring(cleanup) } end
    if #cleanup > 0 then
        summary.failed = summary.failed + 1
        summary.cases[#summary.cases + 1] = { name = "fixture_cleanup", passed = false, failures = cleanup }
    end
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_calling_cards", label = "Calling cards", file = "calling_card_tests.json", report = "callingCardTests",
    help = "Tests calling-card persistence and purchases in isolated throwaway profiles.",
    run = function() return Cards:RunTests() end
})
