// Server-only den trading and den NPC tests: deterministic shared daily stock, 1.5x/0.4x pricing, danger-gated offers
// and the essential-ammo floor, cash and credit buys saved in one transaction with the stock and ledger, stale
// price/day/stock refusals, full-backpack and failed-save rollback, replayed request ids, the daily sale limit,
// unsellable items, profile isolation, and NPC professionals (fixed fees, instant service, rollback, level caps).
// Uses stub players and NPCs with throwaway SteamIDs/profiles/den; every row they write is removed afterwards.
local Trade = ZM_TradeService
local Pro = ZM_ProfessionService
local Npcs = ZM_DenNpcs
local Credits = ZM_CreditService
local Professions = ZM_Professions
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items
local Generation = ZM_ItemGeneration
local StaticData = ZM_StaticData

local playerId = "STEAM_TEST:0:2840"
local otherId = "STEAM_TEST:0:2841"
local testProfile = "zn_test_trade"
local otherProfile = "zn_test_trade2"
local testDen = "zn_test_trade_den"
local testTraderId = "znTest"

local testTrader = {
    id = testTraderId, name = "Test Trader", essentialAmmo = true,
    buys = { food = true, medical = true, weapons = true }, buysList = { "food", "medical", "weapons" },
    offers = {
        { key = "1", item = "itemBandage", bundle = 1, minStock = 3, maxStock = 3, minDanger = 0, maxDanger = 1, mastercraft = false },
        { key = "2", item = "weaponMeleeCrowbar", bundle = 1, minStock = 2, maxStock = 2, minDanger = 0, maxDanger = 1, mastercraft = false },
        { key = "3", item = "weaponHandgun9mm", bundle = 1, minStock = 1, maxStock = 1, minDanger = 0, maxDanger = 1, mastercraft = true, credits = 30 },
        { key = "4", item = "itemMorphine", bundle = 1, minStock = 2, maxStock = 2, minDanger = 0.5, maxDanger = 1, mastercraft = false },
        { key = "5", item = "itemBottledWater", bundle = 1, minStock = 1, maxStock = 5, minDanger = 0, maxDanger = 0.4, mastercraft = false },
        { key = "6", item = "weaponShotgunM3", bundle = 1, minStock = 1, maxStock = 1, minDanger = 0, maxDanger = 1, mastercraft = false }
    }
}

local nextId = 0
local function instance(itemId, count, extra)
    nextId = nextId + 1
    local definition = Items:GetDefinition(itemId)
    local result = { instanceId = "trade" .. nextId, itemId = itemId, count = count or 1, level = definition.minLevel, mastercraft = false, clip = 0, createdAt = os.time() }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function person(values)
    values = values or {}
    return {
        steamId = values.steamId or playerId,
        inDen = values.inDen ~= false,
        alive = true,
        level = values.level or 1,
        job = values.job or "Civilian",
        Cash = values.cash or 0,
        Credits = 0,
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

// A stub den NPC: a table with ZM_Config and the shared provider methods, as the entity has.
local function npc(config, pos)
    local stub = {
        ZM_Config = config or {},
        pos = pos or Vector(40, 0, 0),
        IsValid = function() return true end,
        GetPos = function(self) return self.pos end,
        EntIndex = function() return 0 end
    }
    for key, value in pairs(Npcs.ProviderMethods) do stub[key] = value end
    return stub
end

local function trader(pos)
    return npc({ trader = testTraderId }, pos)
end

local function give(target, itemId, count, extra)
    local item = instance(itemId, count, extra)
    assert(Ops.Add(target.ZM_Inventory, "backpack", item))
    return item
end

local function withCash(target, cash)
    target.Cash = cash
    return ZM_SetPlayerData(target:SteamID(), target.ZM_InventoryProfile, { Cash = cash }, "trade test")
end

local function storedCash(target)
    local data = ZM_GetPlayerData(target:SteamID(), target.ZM_InventoryProfile)
    return data and tonumber(data.Cash) or nil
end

local function storedCount(target, itemId)
    local total = 0
    for _, row in ipairs(ZM_GetPlayerItems(target:SteamID(), target.ZM_InventoryProfile) or {}) do
        if row.itemId == itemId then total = total + tonumber(row.count) end
    end
    return total
end

local function backpackCount(target, itemId)
    return Ops.Count(target.ZM_Inventory, itemId, "backpack")
end

local function offersFor(profile, danger)
    return Trade:BuildOffers(profile or testProfile, { id = testDen, danger = danger or 0 }, testTraderId, Trade:Day())
end

local function findOffer(offers, key)
    return offers and Trade:FindOffer(offers, key)
end

local function soldOf(profile, key)
    return (ZM_GetTradeStock(profile or testProfile, testDen, testTraderId, Trade:Day()) or {})[key] or 0
end

local function ledgerCount(target)
    return #(ZM_GetTradeLedger(target:SteamID(), target.ZM_InventoryProfile, 100) or {})
end

local requestCounter = 0
local function rid()
    requestCounter = requestCounter + 1
    return "t" .. requestCounter
end

local function cleanup()
    for _, steamId in ipairs({ playerId, otherId }) do
        for _, profile in ipairs({ testProfile, otherProfile }) do
            ZM_DeletePlayerItems(steamId, profile)
            ZM_DeletePlayerCredits(steamId, profile)
            ZM_ReplaceDenStashItems(steamId, profile, testDen, {})
            ZM_DeleteTradeData(steamId, profile, true)
            sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(steamId) .. " AND profile = " .. sql.SQLStr(profile))
        end
    end
    for id, offer in pairs(Pro.Offers) do
        if type(offer.customer) == "table" and offer.customer.steamId then Pro.Offers[id] = nil end
    end
    Trade.DangerOverride = 0
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("shipped_trade_data_loads", function(check)
    local trade = StaticData:GetTrade()
    check(trade and trade.buyMultiplier == 1.5 and trade.sellMultiplier == 0.4, "the shipped multipliers load")
    check(StaticData:GetTrader("general") and StaticData:GetTrader("quartermaster") and StaticData:GetTrader("clinic"), "the shipped traders load")
    check(trade and trade.npcServiceFees.cook == 5 and trade.npcServiceFees.treat == 10, "the shipped NPC fees load")
end)

test("daily_stock_is_deterministic_and_shared", function(check)
    local first, second = offersFor(), offersFor()
    check(first and second and #first == #second, "the same offers are built twice")
    for index, offer in ipairs(first or {}) do
        local other = second[index]
        check(other.key == offer.key and other.stock == offer.stock and other.level == offer.level and other.price == offer.price
            and util.TableToJSON(other.attributes or {}) == util.TableToJSON(offer.attributes or {}), "offer " .. offer.key .. " is identical on a rebuild")
    end
    local bandage = findOffer(first, "1")
    check(bandage and bandage.stock == 3 and bandage.remaining == 3, "a fixed stock of 3 is offered")
    local buyer, other = person({ cash = 500 }), person({ steamId = otherId, cash = 500 })
    check(withCash(buyer, 500) and withCash(other, 500), "the player rows exist")
    local ok, message = Trade:Buy(buyer, trader(), { key = "1", units = 2, requestId = rid() })
    check(ok, "the first player buys two bandages: " .. tostring(message))
    local seen = findOffer(offersFor(), "1")
    check(seen and seen.sold == 2 and seen.remaining == 1, "another player in the den sees the shared stock drop")
    check(not Trade:Buy(other, trader(), { key = "1", units = 2, requestId = rid() }), "the other player cannot buy more than remains")
    check(Trade:Buy(other, trader(), { key = "1", units = 1, requestId = rid() }), "the other player buys the last one")
    local soldOut, why = Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = rid() })
    check(not soldOut and string.find(tostring(why), "sold out", 1, true), "a sold-out offer is refused: " .. tostring(why))
    check(findOffer(offersFor(otherProfile), "1").remaining == 3, "another profile's den stock is separate")
end)

test("prices_use_the_buy_and_sell_multipliers", function(check)
    local offers = offersFor()
    local bandage = findOffer(offers, "1")
    local value = Items:GetInstanceValue(bandage.template)
    check(bandage.currency == "cash" and bandage.price == math.max(1, math.ceil(value * 1.5)), "the buy price is ceil(value x 1.5), got " .. tostring(bandage.price))
    local credit = findOffer(offers, "3")
    check(credit and credit.currency == "credits" and credit.price == 30 and credit.mastercraft, "the mastercraft offer is priced in credits")
    local seller = person()
    local crowbar = give(seller, "weaponMeleeCrowbar", 1)
    check(Trade:SellPrice(crowbar) == math.floor(Items:GetInstanceValue(crowbar) * 0.4), "the sell price is floor(value x 0.4)")
    local mastercrafted = give(seller, "weaponMeleeCrowbar", 1, { mastercraft = true })
    check(Trade:SellPrice(mastercrafted) > Trade:SellPrice(crowbar), "a mastercraft sells for more")
    check(Trade:SellPrice(crowbar) < math.ceil(Items:GetInstanceValue(crowbar) * 1.5), "selling back pays less than buying")
end)

test("danger_gates_offers_and_essential_ammo_is_always_stocked", function(check)
    local calm, deadly = offersFor(nil, 0.2), offersFor(nil, 0.9)
    check(not findOffer(calm, "4") and findOffer(deadly, "4"), "morphine (minDanger 0.5) is only offered in a dangerous den")
    check(findOffer(calm, "5") and not findOffer(deadly, "5"), "water (maxDanger 0.4) is only offered in a calm den")
    local calmShotgun, deadlyShotgun = findOffer(calm, "6"), findOffer(deadly, "6")
    check(calmShotgun and deadlyShotgun and deadlyShotgun.level >= calmShotgun.level, "weapon levels scale with danger")
    check(Trade.GetDangerTier(0.2) ~= Trade.GetDangerTier(0.9), "the two dens are in different danger tiers")
    for _, danger in ipairs({ 0, 1 }) do
        local offers = offersFor(nil, danger)
        for _, itemId in ipairs(StaticData:GetTrade().essentialAmmo.items) do
            local ammo = findOffer(offers, "ammo:" .. itemId)
            check(ammo and ammo.stock == 10 and ammo.bundle == 30 and ammo.essential, itemId .. " is stocked at danger " .. danger)
        end
    end
    local shipped = Trade:BuildOffers(testProfile, { id = testDen, danger = 0 }, "general", Trade:Day())
    check(findOffer(shipped, "ammo:ammo9mm"), "the shipped general trader stocks 9mm at danger 0")
    check(not findOffer(Trade:BuildOffers(testProfile, { id = testDen, danger = 0 }, "clinic", Trade:Day()), "ammo:ammo9mm"), "the clinic has no ammo")
end)

test("a_cash_buy_saves_items_cash_stock_and_ledger_together", function(check)
    local buyer = person()
    check(withCash(buyer, 200), "the player row exists")
    local ammo = findOffer(offersFor(), "ammo:ammo9mm")
    local ok, message, added = Trade:Buy(buyer, trader(), { key = "ammo:ammo9mm", units = 2, requestId = "buy-1", price = ammo.price, currency = "cash", day = Trade:Day() })
    check(ok, "the ammo is bought: " .. tostring(message))
    check(type(added) == "table" and #added == 2, "two units were added")
    check(backpackCount(buyer, "ammo9mm") == 60 and storedCount(buyer, "ammo9mm") == 60, "60 rounds are in the backpack and saved")
    check(buyer.Cash == 200 - ammo.price * 2 and storedCash(buyer) == buyer.Cash, "the cash was taken and saved")
    check(soldOf(nil, "ammo:ammo9mm") == 2, "the stock row records two units")
    local ledger = (ZM_GetTradeLedger(playerId, testProfile, 1) or {})[1]
    check(ledger and ledger.requestId == "buy-1" and ledger.kind == "buy" and tonumber(ledger.count) == 60 and tonumber(ledger.cash) == ammo.price * 2, "the ledger records the buy")
    local replay = { Trade:Buy(buyer, trader(), { key = "ammo:ammo9mm", units = 1, requestId = "buy-1" }) }
    check(not replay[1] and string.find(tostring(replay[2]), "already completed", 1, true), "a replayed request id is refused")
    check(backpackCount(buyer, "ammo9mm") == 60 and soldOf(nil, "ammo:ammo9mm") == 2, "the replay changed nothing")
    local poor = person({ steamId = otherId })
    check(withCash(poor, 1), "the poor player's row exists")
    check(not Trade:Buy(poor, trader(), { key = "ammo:ammo9mm", units = 1, requestId = rid() }), "a player who cannot afford it is refused")
end)

test("a_credit_buy_spends_credits_not_cash", function(check)
    local buyer = person()
    check(withCash(buyer, 100), "the player row exists")
    check(not Trade:Buy(buyer, trader(), { key = "3", units = 1, requestId = rid() }), "too few credits are refused")
    check(Credits:Grant(buyer, 40, "trade test"), "credits are granted")
    local ok, message = Trade:Buy(buyer, trader(), { key = "3", units = 1, requestId = rid(), currency = "credits", price = 30 })
    check(ok, "the mastercraft is bought: " .. tostring(message))
    check(Credits:Get(buyer) == 10 and ZM_GetPlayerCredits(playerId, testProfile) == 10, "30 credits were spent and saved")
    check(buyer.Cash == 100 and storedCash(buyer) == 100, "no cash was spent")
    local weapon
    for _, item in pairs(buyer.ZM_Inventory.backpack) do
        if item.itemId == "weaponHandgun9mm" then weapon = item end
    end
    check(weapon and weapon.mastercraft == true and weapon.instanceId ~= "offer", "a mastercrafted weapon with a new instance id arrived")
    local ledger = (ZM_GetTradeLedger(playerId, testProfile, 1) or {})[1]
    check(ledger and tonumber(ledger.credits) == 30 and tonumber(ledger.cash) == 0, "the ledger records the credit price")
end)

test("stale_views_are_refused", function(check)
    local buyer = person()
    check(withCash(buyer, 500), "the player row exists")
    local bandage = findOffer(offersFor(), "1")
    check(not Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = rid(), day = "1999-01-01" }), "a request for another day is refused")
    check(not Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = rid(), price = bandage.price + 1 }), "a stale price is refused")
    check(not Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = rid(), currency = "credits" }), "a stale currency is refused")
    check(not Trade:Buy(buyer, trader(), { key = "4", units = 1, requestId = rid() }), "an offer not available at this danger is refused")
    check(not Trade:Buy(buyer, trader(), { key = "1", units = 0, requestId = rid() }), "zero units are refused")
    check(not Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = "bad id!" }), "a malformed request id is refused")
    check(backpackCount(buyer, "itemBandage") == 0 and buyer.Cash == 500 and ledgerCount(buyer) == 0, "the refusals changed nothing")

    check(Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = rid() }), "a bandage is bought")
    // Another buyer's view read before that sale: the stock step's expected count is stale, so the save fails.
    local originalGetStock = ZM_GetTradeStock
    ZM_GetTradeStock = function() return {} end
    local other = person({ steamId = otherId })
    check(withCash(other, 500), "the other player's row exists")
    local ok, why = Trade:Buy(other, trader(), { key = "1", units = 1, requestId = rid() })
    ZM_GetTradeStock = originalGetStock
    check(not ok and string.find(tostring(why), "stock changed", 1, true), "a stale stock view fails the save: " .. tostring(why))
    check(backpackCount(other, "itemBandage") == 0 and other.Cash == 500 and storedCash(other) == 500 and ledgerCount(other) == 0, "the failed buy changed nothing")
    check(soldOf(nil, "1") == 1, "the stock still records one sale")
end)

test("a_full_backpack_or_failed_save_rolls_back", function(check)
    local buyer = person()
    check(withCash(buyer, 5000), "the player row exists")
    local originalCapacity = Items.ContainerCapacity
    Items.ContainerCapacity = { backpack = 1, stash = 0, equipped = 3 }
    local ok, why = Trade:Buy(buyer, trader(), { key = "2", units = 2, requestId = rid() })
    Items.ContainerCapacity = originalCapacity
    check(not ok and string.find(tostring(why), "no room", 1, true), "two crowbars do not fit one slot: " .. tostring(why))
    check(backpackCount(buyer, "weaponMeleeCrowbar") == 0 and buyer.Cash == 5000 and storedCash(buyer) == 5000, "nothing was bought")
    check(soldOf(nil, "2") == 0 and ledgerCount(buyer) == 0, "no stock or ledger row was written")

    // No player_data row in this profile: the cash step fails inside the transaction.
    local missing = person({ profile = otherProfile })
    missing.Cash = 500
    local failed = Trade:Buy(missing, trader(), { key = "1", units = 1, requestId = rid() })
    check(not failed, "the buy fails when the cash cannot be saved")
    check(backpackCount(missing, "itemBandage") == 0 and storedCount(missing, "itemBandage") == 0 and missing.Cash == 500, "no item or cash moved")
    check(soldOf(otherProfile, "1") == 0 and ledgerCount(missing) == 0, "no stock or ledger row was written")
end)

test("selling_pays_cash_within_the_daily_limit", function(check)
    local seller = person()
    check(withCash(seller, 0), "the player row exists")
    local pills = give(seller, "itemPainkillers", 4)
    check(Service:Mutate(seller, function() return true end), "the starting inventory persists")
    local unit = Trade:SellPrice(pills, 1)
    check(unit > 0, "a painkiller is worth something")
    check(not Trade:Sell(seller, trader(), { ref = pills.instanceId, count = 2, requestId = rid(), price = Trade:SellPrice(pills, 2) + 1 }), "a stale sale price is refused")
    local ok, message = Trade:Sell(seller, trader(), { ref = pills.instanceId, count = 2, requestId = "sell-1", price = Trade:SellPrice(pills, 2) })
    check(ok, "two painkillers are sold: " .. tostring(message))
    local earned = Trade:SellPrice(instance("itemPainkillers", 2), 2)
    check(seller.Cash == earned and storedCash(seller) == earned, "the cash was paid and saved")
    check(backpackCount(seller, "itemPainkillers") == 2 and storedCount(seller, "itemPainkillers") == 2, "two painkillers remain and are saved")
    check(ZM_GetTradeSaleTotal(playerId, testProfile, Trade:Day()) == earned, "the sale counts toward today's total")
    check(not Trade:Sell(seller, trader(), { ref = pills.instanceId, count = 1, requestId = "sell-1" }), "a replayed sale is refused")

    local trade = StaticData:GetTrade()
    local originalLimit = trade.dailySaleCashLimit
    trade.dailySaleCashLimit = earned
    local limited, why = Trade:Sell(seller, trader(), { ref = "itemPainkillers", count = 1, requestId = rid() })
    check(not limited and string.find(tostring(why), "more cash today", 1, true), "a sale over the daily limit is refused: " .. tostring(why))
    // The limit is also enforced inside the transaction, against sales saved by another server path.
    local saved = ZM_CommitWrites(testProfile, { { kind = "tradeLedger", steamid = playerId, requestId = rid(), safeZoneId = testDen, traderId = testTraderId, day = Trade:Day(), tradeKind = "sell", itemId = "itemPainkillers", count = 1, cash = 1, credits = 0, saleLimit = trade.dailySaleCashLimit } })
    trade.dailySaleCashLimit = originalLimit
    check(not saved, "the ledger writer refuses a sale over the limit")
    check(backpackCount(seller, "itemPainkillers") == 2 and seller.Cash == earned, "the refused sales changed nothing")
end)

test("unsellable_items_are_refused", function(check)
    local seller = person()
    check(withCash(seller, 0), "the player row exists")
    local rotten = give(seller, "itemPotato", 1, { createdAt = os.time() - 3600 * 1000 })
    local crowbar = give(seller, "weaponMeleeCrowbar", 1)
    local ammo = give(seller, "ammo9mm", 10)
    check(Service:Mutate(seller, function() return true end), "the starting inventory persists")
    local spoiled, spoiledWhy = Trade:Sell(seller, trader(), { ref = rotten.instanceId, requestId = rid() })
    check(not spoiled and string.find(tostring(spoiledWhy), "spoiled", 1, true), "spoiled food is refused: " .. tostring(spoiledWhy))
    seller.ZM_WeaponSlots = { { instanceId = crowbar.instanceId } }
    local equipped, equippedWhy = Trade:Sell(seller, trader(), { ref = crowbar.instanceId, requestId = rid() })
    check(not equipped and string.find(tostring(equippedWhy), "Unequip", 1, true), "an equipped weapon is refused: " .. tostring(equippedWhy))
    seller.ZM_WeaponSlots = nil
    local category, categoryWhy = Trade:Sell(seller, trader(), { ref = ammo.instanceId, requestId = rid() })
    check(not category and string.find(tostring(categoryWhy), "does not buy", 1, true), "a category the trader does not buy is refused: " .. tostring(categoryWhy))
    check(not Trade:Sell(seller, trader(), { ref = "notAnItem", requestId = rid() }), "an item not in the backpack is refused")
    check(not Trade:Sell(seller, trader(), { ref = ammo.instanceId, count = 11, requestId = rid() }), "more than the stack is refused")
    check(seller.Cash == 0 and ledgerCount(seller) == 0 and storedCount(seller, "weaponMeleeCrowbar") == 1, "the refusals changed nothing")
    local state = Trade:BuildState(seller, trader())
    local reasons = 0
    for _, entry in ipairs(state.sellables or {}) do
        if entry.reason then reasons = reasons + 1 end
    end
    check(state.available and reasons == 2, "the trade state marks the potato and the ammo unsellable")
end)

test("trading_requires_the_den_and_a_nearby_trader", function(check)
    local buyer = person({ inDen = false })
    check(withCash(buyer, 100), "the player row exists")
    check(not Trade:Buy(buyer, trader(), { key = "1", units = 1, requestId = rid() }), "outside a den trading is refused")
    buyer.inDen = true
    check(not Trade:Buy(buyer, trader(Vector(Trade.Range + 50, 0, 0)), { key = "1", units = 1, requestId = rid() }), "a distant trader is refused")
    check(not Trade:Buy(buyer, npc({ profession = "Chef" }), { key = "1", units = 1, requestId = rid() }), "an NPC without a trade table is refused")
    check(not Trade:Buy(buyer, nil, { key = "1", units = 1, requestId = rid() }), "a missing NPC is refused")
    check(buyer.Cash == 100 and ledgerCount(buyer) == 0, "nothing changed")
end)

test("npc_settings_resolve_and_report_problems", function(check)
    local chef = Npcs:Resolve(npc({ profession = "Chef", service_level = "12", fees = "cook=7", npc_name = "Marge" }))
    check(chef.job == "Chef" and chef.level == 12 and chef.fees.cook == 7 and chef.name == "Marge" and #chef.problems == 0, "a configured Chef resolves")
    local defaults = Npcs:Resolve(npc({ profession = "Doctor" }))
    check(defaults.fees.treat == StaticData:GetTrade().npcServiceFees.treat and defaults.level == 1, "fees and level default from the data")
    local broken = Npcs:Resolve(npc({ profession = "Juggler", service_level = "0", fees = "cook=5", trader = "nobody" }))
    check(broken.job == nil and broken.trader == nil and #broken.problems >= 3, "invalid settings are reported, got " .. #broken.problems)
    local shop = Npcs:Resolve(npc({ trader = "general" }))
    check(shop.trader == "general" and shop.name == "General Trader" and #shop.services == 0, "a trader-only NPC resolves")
    local named = Npcs:Resolve(npc({ targetname = "Ketamine Keith", trader = "general" }))
    check(named.name == "Ketamine Keith", "Hammer targetname takes precedence over the trader label")
    local overridden = Npcs:Resolve(npc({ npc_name = "Custom Name", targetname = "Ketamine Keith" }))
    check(overridden.name == "Custom Name", "npc_name takes precedence over Hammer targetname")
end)

test("npc_professionals_serve_at_once_for_a_fixed_fee", function(check)
    local customer = person({ cash = 50, health = 40 })
    check(withCash(customer, 50), "the customer row exists")
    give(customer, "itemPotato", 2)
    local chef = npc({ profession = "Chef", service_level = 10 })
    check(not Pro:CheckService(customer, chef, "cook", "itemPotato", 2, 3), "a fee other than the NPC's is refused")
    local ok, message = Pro:RequestService(customer, chef, "cook", "itemPotato", 2, nil)
    check(ok, "the NPC Chef cooks at once: " .. tostring(message))
    check(backpackCount(customer, "itemBakedPotato") == 2 and backpackCount(customer, "itemPotato") == 0, "two potatoes were cooked")
    check(customer.Cash == 45 and storedCash(customer) == 45, "the 5 fee was taken from the customer only")
    check(Pro:FindOfferFor(customer) == nil, "no offer was created")

    local doctor = npc({ profession = "Doctor", fees = "treat=12" })
    give(customer, "itemPainkillers", 1)
    local treated, treatMessage = Pro:RequestService(customer, doctor, "treat", "itemPainkillers", 1, 12)
    check(treated, "the NPC Doctor treats: " .. tostring(treatMessage))
    check(customer.health > 40 and customer.Cash == 33 and storedCash(customer) == 33, "the patient healed and paid the keyvalue fee")

    local scientist = npc({ profession = "Scientist" })
    give(customer, "itemHerbs", 2)
    give(customer, "itemBottledWater", 1)
    local researched, researchMessage = Pro:RequestService(customer, scientist, "research", "recipeResearchPainkillers", 1, nil)
    check(researched, "the NPC Scientist researches: " .. tostring(researchMessage))
    check(backpackCount(customer, "itemPainkillers") == 2 and customer.Cash == 13, "the research made painkillers for a 20 fee")
    check(not Pro:RequestService(customer, scientist, "research", "recipeResearchPainkillers", 1, nil), "without ingredients nothing happens")
end)

test("npc_services_refuse_and_roll_back", function(check)
    local customer = person({ profile = otherProfile })
    customer.Cash = 50
    give(customer, "itemPotato", 2)
    check(Service:Mutate(customer, function() return true end), "the starting inventory persists")
    // No player_data row: the customer's fee cannot be saved, so nothing is cooked.
    check(not Pro:RequestService(customer, npc({ profession = "Chef" }), "cook", "itemPotato", 2, nil), "the service fails when the fee cannot be saved")
    check(backpackCount(customer, "itemPotato") == 2 and storedCount(customer, "itemPotato") == 2 and customer.Cash == 50, "no food or cash moved")

    local patient = person()
    check(withCash(patient, 100), "the patient row exists")
    give(patient, "itemMorphine", 1)
    check(not Pro:CheckService(patient, npc({ profession = "Doctor", service_level = 1 }), "treat", "itemMorphine", 1, nil), "a level-1 NPC Doctor cannot apply level-10 morphine")
    local unknown, unknownWhy = Pro:CheckService(patient, npc({ profession = "Juggler" }), "treat", "itemMorphine", 1, nil)
    check(not unknown and string.find(tostring(unknownWhy), "no valid profession", 1, true), "an NPC without a valid profession offers nothing: " .. tostring(unknownWhy))
    check(not Pro:CheckService(patient, npc({ profession = "Doctor", service_level = 50 }, Vector(Pro.ServiceRange + 100, 0, 0)), "treat", "itemMorphine", 1, nil), "a distant NPC cannot serve")
    check(not Pro:CheckService(patient, npc({ profession = "Chef" }), "treat", "itemMorphine", 1, nil), "an NPC Chef does not treat")
    patient.inDen = false
    check(not Pro:CheckService(patient, npc({ profession = "Doctor", service_level = 50 }), "treat", "itemMorphine", 1, nil), "outside a den an NPC cannot serve")
    patient.inDen = true
    local poor = person({ steamId = otherId })
    check(withCash(poor, 2), "the poor customer's row exists")
    give(poor, "itemPotato", 1)
    check(not Pro:CheckService(poor, npc({ profession = "Chef" }), "cook", "itemPotato", 1, nil), "a customer who cannot afford the NPC fee is refused")
    check(patient.Cash == 100 and storedCash(patient) == 100, "no cash moved")
end)

function Trade:RunTests()
    local restoreStashAccess = ZM_TestHarness.StubStashAccess()
    local originalOverride = Trade.DangerOverride
    local trade = StaticData:GetTrade()
    if trade then trade.traders[testTraderId] = testTrader end
    local summary = suite:Run({ before = cleanup, after = cleanup })
    if trade then trade.traders[testTraderId] = nil end
    restoreStashAccess()
    Trade.DangerOverride = originalOverride
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_trading", label = "Trading", file = "trading_tests.json", report = "tradingTests",
    help = "Runs den trading and den NPC professional tests against throwaway SteamIDs and profiles.",
    run = function() return Trade:RunTests() end
})
