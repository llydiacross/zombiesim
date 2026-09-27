// Server-owned offline den trading. Traders are den NPCs (zn_den_npc) whose trader keyvalue names a table in
// trade_definitions.json. Each den's daily stock is shared by every player there and is regenerated deterministically
// from (profile, den, trader, UTC day, offer); only the units sold are stored (trade_stock). A buy or a sell saves the
// inventory, the cash or credits, the stock, and a trade_ledger row in one transaction, and the ledger's unique request
// id makes a replayed request fail. Clients name only an offer or an item and the price they saw; the server rebuilds
// the offer and refuses a stale day, price, or stock.
ZM_TradeService = ZM_TradeService or {}
local Trade = ZM_TradeService
local Service = ZM_InventoryService
local Credits = ZM_CreditService
local Items = ZM_Items
local Generation = ZM_ItemGeneration
local StaticData = ZM_StaticData

util.AddNetworkString("ZM.TradeRequest")
util.AddNetworkString("ZM.TradeState")
util.AddNetworkString("ZM.DenNpc.Open")

Trade.Range = 160
Trade.RequestCooldown = 0.25
Trade.StockRetentionDays = 7
Trade.DangerTiers = { { below = 0.25, name = "Safe" }, { below = 0.5, name = "Guarded" }, { below = 0.75, name = "Dangerous" }, { below = math.huge, name = "Deadly" } }

local profileFor = ZM_Util.ProfileFor

local cashOf = ZM_Util.CashOf

local isWholeNumber = ZM_Util.IsWholeNumber

local isPlayerEntity = ZM_Util.IsPlayerEntity

function Trade:Day()
    return ZM_ProfessionService:Day()
end

function Trade:Init()
    local created, createError = ZM_CreateTradeTables()
    if not created then return false, createError end
    return ZM_PruneTradeStock(os.date("!%Y-%m-%d", os.time() - self.StockRetentionDays * 86400))
end

function Trade.GetDangerTier(danger)
    for index, tier in ipairs(Trade.DangerTiers) do
        if danger < tier.below then return index, tier.name end
    end
end

// The player's den and its danger (the entrance cell's). DangerOverride (development only) replaces the danger.
function Trade:GetDen(target)
    if not Service:CanAccessStash(target) then
        return nil, "Trading is only available inside a den."
    end
    local denId = Service:CurrentDenId(target)
    local danger = self.DangerOverride
    if danger == nil then
        local cell = ZM_SafeZones:GetEntranceCell(denId)
        danger = cell and ZM_World:GetDangerIntensity(cell) or 0
    end
    return { id = denId, danger = math.Clamp(tonumber(danger) or 0, 0, 1) }
end

// Offered level: weapons scale from minLevel at danger 0 to halfway through their range at danger 1; everything else
// is offered at its definition's minimum level.
function Trade.OfferLevel(definition, danger)
    if not definition.attributes then return definition.minLevel end
    return math.min(definition.maxLevel, definition.minLevel + math.Round(math.Clamp(danger, 0, 1) * (definition.maxLevel - definition.minLevel) * 0.5))
end

// Ammunition compatibility text for an offer or sellable: a weapon's ammo, or the weapons an ammo item fits.
function Trade.AmmoInfo(itemId)
    local definition = Items:GetDefinition(itemId)
    if not definition then return nil end
    if definition.ammoId then
        return "Uses " .. Items:GetDisplayName({ itemId = definition.ammoId })
    end
    local registry = StaticData:GetRegistry()
    local weapons = {}
    for weaponId, weapon in SortedPairs(registry and registry.items or {}) do
        if weapon.ammoId == itemId then table.insert(weapons, weapon.name or weaponId) end
    end
    return #weapons > 0 and ("Fits " .. table.concat(weapons, ", ")) or nil
end

// Today's offers from a trader in a den, or nil and a reason. Stock, level, and attributes depend only on the
// profile, den, trader, day, and offer, so every player in the den sees (and buys from) the same stock.
function Trade:BuildOffers(profile, den, traderId, day)
    local trade = StaticData:GetTrade()
    local trader = StaticData:GetTrader(traderId)
    if not trade or not trader then
        return nil, "Unknown trader table '" .. tostring(traderId) .. "'."
    end
    local sold, soldError = ZM_GetTradeStock(profile, den.id, traderId, day)
    if not sold then
        return nil, "Could not read the trader's stock: " .. tostring(soldError)
    end
    local offers = {}
    local function add(key, source, essential)
        local definition = Items:GetDefinition(source.item)
        if not definition then return end
        local rng = Generation.NewRng(tonumber(util.CRC(table.concat({ profile, den.id, traderId, day, key, source.item }, "|"))))
        local stock = essential and source.stock or rng:Int(source.minStock, source.maxStock)
        if stock <= 0 then return end
        local template = Generation:CreateInstance(source.item, {
            rng = rng, count = source.bundle, instanceId = "offer",
            level = essential and definition.minLevel or self.OfferLevel(definition, den.danger),
            mastercraft = source.mastercraft == true
        })
        if not template then return end
        template.createdAt = 0
        local soldCount = math.min(sold[key] or 0, stock)
        table.insert(offers, {
            key = key, item = source.item, name = Items:GetDisplayName(template), category = definition.lootCategory,
            bundle = source.bundle, level = template.level, mastercraft = template.mastercraft == true,
            ultra = Items:IsUltraMastercraft(template), attributes = template.attributes, maxAttributes = definition.maxAttributes,
            currency = source.credits and "credits" or "cash",
            price = source.credits or math.max(1, math.ceil(Items:GetInstanceValue(template) * trade.buyMultiplier)),
            stock = stock, sold = soldCount, remaining = stock - soldCount, essential = essential == true,
            ammo = self.AmmoInfo(source.item), template = template
        })
    end
    if trader.essentialAmmo then
        for _, itemId in ipairs(trade.essentialAmmo.items) do
            add("ammo:" .. itemId, { item = itemId, bundle = trade.essentialAmmo.bundle, stock = trade.essentialAmmo.stock }, true)
        end
    end
    for _, offer in ipairs(trader.offers) do
        if den.danger >= offer.minDanger and den.danger <= offer.maxDanger then
            add(offer.key, offer, false)
        end
    end
    return offers
end

// Checks the player, the den, and the trader NPC. Returns a context { den, traderId, trader, day, profile } or false.
function Trade:CheckAccess(target, npc)
    if not IsValid(target) or (target.Alive and not target:Alive()) then
        return false, "You must be alive."
    end
    if not target.ZM_Inventory then
        return false, "Your inventory is not loaded."
    end
    if not StaticData:GetTrade() then
        return false, "Trade data is not loaded."
    end
    local den, denError = self:GetDen(target)
    if not den then return false, denError end
    if not IsValid(npc) or not npc.ZM_IsDenNpc then
        return false, "That trader is no longer here."
    end
    if not target.GetPos or target:GetPos():DistToSqr(npc:GetPos()) > self.Range * self.Range then
        return false, "Stand closer to the trader."
    end
    local traderId = ZM_DenNpcs:Resolve(npc).trader
    if not traderId then
        return false, "They do not trade."
    end
    return { den = den, traderId = traderId, trader = StaticData:GetTrader(traderId), day = self:Day(), profile = profileFor(target), npc = npc }
end

// A client-chosen request id (letters, digits, - and _; at most 40), refused when it was already used.
function Trade:CheckRequestId(target, requestId)
    if type(requestId) ~= "string" or not string.match(requestId, "^[%w_-]+$") or #requestId > 40 then
        return nil, "Invalid request id."
    end
    local existing, readError = ZM_GetTradeRequest(target:SteamID(), profileFor(target), requestId)
    if existing == nil then return nil, "Could not check the request: " .. tostring(readError) end
    if existing then return nil, "That request was already completed." end
    return requestId
end

local function friendlySaveError(message)
    message = tostring(message)
    if string.find(message, "UNIQUE constraint failed", 1, true) then return "That request was already completed." end
    if string.find(message, "stock changed", 1, true) then return "The trader's stock changed; check the offers and try again." end
    if string.find(message, "sale limit", 1, true) then return "That would exceed today's sale limit." end
    if string.find(message, "credit balance changed", 1, true) then return "Your credits changed; try again." end
    return "The trade could not be saved: " .. message
end

local function syncCash(target)
    if target.SendPlayerData then target:SendPlayerData() end
end

function Trade:FindOffer(offers, key)
    for _, offer in ipairs(offers) do
        if offer.key == key then return offer end
    end
end

// Buys request.units of an offer. request: { key, units, requestId, price?, currency?, day? }; price, currency, and
// day are what the client saw and are refused when stale. Returns true, message, instanceIds or false, reason.
function Trade:Buy(target, npc, request)
    local context, reason = self:CheckAccess(target, npc)
    if not context then return false, reason end
    request = type(request) == "table" and request or {}
    local trade = StaticData:GetTrade()
    local units = tonumber(request.units) or 1
    if not isWholeNumber(units, 1, trade.maximumPurchaseUnits) then
        return false, "Buy from 1 to " .. trade.maximumPurchaseUnits .. " at a time."
    end
    local requestId, idError = self:CheckRequestId(target, request.requestId)
    if not requestId then return false, idError end
    if request.day ~= nil and request.day ~= context.day then
        return false, "The trader restocked for a new day; check the new offers."
    end
    local offers, offersError = self:BuildOffers(context.profile, context.den, context.traderId, context.day)
    if not offers then return false, offersError end
    local offer = self:FindOffer(offers, tostring(request.key or ""))
    if not offer then
        return false, "That offer is not available here today."
    end
    if (request.price ~= nil and tonumber(request.price) ~= offer.price) or (request.currency ~= nil and request.currency ~= offer.currency) then
        return false, "The price is now " .. offer.price .. " " .. offer.currency .. "; check the offer and try again."
    end
    if offer.remaining < units then
        return false, offer.remaining == 0 and "That offer is sold out." or ("Only " .. offer.remaining .. " left.")
    end
    local total = offer.price * units
    local currencyStep
    if offer.currency == "credits" then
        local step, stepError = Credits:Step(target, -total, "trade", offer.item)
        if not step then return false, stepError end
        currencyStep = step
    else
        if cashOf(target) < total then
            return false, "That costs " .. total .. " cash; you have " .. cashOf(target) .. "."
        end
        currencyStep = { kind = "cash", steamid = target:SteamID(), cash = cashOf(target) - total }
    end
    local now = os.time()
    local ok, result = Service:Mutate(target, function(draft)
        local added = {}
        for _ = 1, units do
            local instance = table.Copy(offer.template)
            instance.instanceId = Service.NewInstanceId()
            instance.createdAt = now
            local fits = Service.Ops.Add(draft, "backpack", instance)
            if not fits then return false, "Your backpack has no room for that." end
            table.insert(added, instance.instanceId)
        end
        return true, added
    end, { extraSteps = function()
        return {
            currencyStep,
            { kind = "tradeStock", safeZoneId = context.den.id, traderId = context.traderId, day = context.day, offerKey = offer.key, stock = offer.stock, expected = offer.sold, units = units },
            { kind = "tradeLedger", steamid = target:SteamID(), requestId = requestId, safeZoneId = context.den.id, traderId = context.traderId, day = context.day, tradeKind = "buy",
                itemId = offer.item, count = units * offer.bundle, cash = offer.currency == "cash" and total or 0, credits = offer.currency == "credits" and total or 0 }
        }
    end })
    if not ok then
        return false, string.find(tostring(result), "could not save", 1, true) and friendlySaveError(result) or result
    end
    if offer.currency == "credits" then
        Credits:Apply(target, currencyStep)
    else
        target.Cash = currencyStep.cash
        syncCash(target)
    end
    return true, string.format("Bought %d x %s%s for %d %s.", units, offer.bundle > 1 and (offer.bundle .. " ") or "", offer.name, total, offer.currency), result
end

local function isEquipped(target, instanceId)
    for _, slot in pairs(target.ZM_WeaponSlots or {}) do
        if slot.instanceId == instanceId then return true end
    end
    return false
end

// Backpack instance by instance id, or the lowest-slot stack of an item id.
function Trade:FindSellable(target, ref)
    local bestSlot, best
    for slot, instance in pairs(target.ZM_Inventory and target.ZM_Inventory.backpack or {}) do
        if instance.instanceId == ref then return instance end
        if instance.itemId == ref and (not bestSlot or slot < bestSlot) then
            bestSlot, best = slot, instance
        end
    end
    return best
end

// Cash paid for `count` units of an instance: floor(value x sellMultiplier).
function Trade:SellPrice(instance, count)
    local trade = StaticData:GetTrade()
    local portion = table.Copy(instance)
    portion.count = count or instance.count
    return math.floor(Items:GetInstanceValue(portion) * trade.sellMultiplier)
end

// Why a trader will not buy an instance, or nil.
function Trade:UnsellableReason(target, trader, instance)
    local definition = Items:GetDefinition(instance.itemId)
    if not definition then return "Unknown item." end
    if not trader.buys[definition.lootCategory] then
        return trader.name .. " does not buy " .. definition.lootCategory .. "."
    end
    if isEquipped(target, instance.instanceId) then
        return "Unequip it before selling."
    end
    if definition.food and ZM_Food:GetBand(instance) == "spoiled" then
        return "Nobody buys spoiled food."
    end
end

// Sells request.count of a backpack item. request: { ref, count, requestId, price? } (price is the total the client saw).
function Trade:Sell(target, npc, request)
    local context, reason = self:CheckAccess(target, npc)
    if not context then return false, reason end
    request = type(request) == "table" and request or {}
    local trade = StaticData:GetTrade()
    if type(request.ref) ~= "string" or #request.ref > 64 then return false, "Invalid item." end
    local instance = self:FindSellable(target, request.ref)
    if not instance then return false, "That item is not in your backpack." end
    local count = tonumber(request.count) or instance.count
    if not isWholeNumber(count, 1, instance.count) then
        return false, "Sell from 1 to " .. instance.count .. "."
    end
    local unsellable = self:UnsellableReason(target, context.trader, instance)
    if unsellable then return false, unsellable end
    local price = self:SellPrice(instance, count)
    if price <= 0 then return false, "That is worth nothing to a trader." end
    if request.price ~= nil and tonumber(request.price) ~= price then
        return false, "The trader now offers " .. price .. " cash; check and try again."
    end
    local requestId, idError = self:CheckRequestId(target, request.requestId)
    if not requestId then return false, idError end
    local soldToday, soldError = ZM_GetTradeSaleTotal(target:SteamID(), context.profile, context.day)
    if not soldToday then return false, "Could not read today's sales: " .. tostring(soldError) end
    if soldToday + price > trade.dailySaleCashLimit then
        return false, "Traders will pay you at most " .. math.max(0, trade.dailySaleCashLimit - soldToday) .. " more cash today."
    end
    local cash = cashOf(target) + price
    local instanceId, itemId, name = instance.instanceId, instance.itemId, Items:GetDisplayName(instance)
    local ok, result = Service:Mutate(target, function(draft)
        local container, _, found = Service.Ops.FindInstance(draft, instanceId)
        if container ~= "backpack" or not found then return false, "That item is no longer in your backpack." end
        return Service.Ops.RemoveInstance(draft, instanceId, count)
    end, { extraSteps = function()
        return {
            { kind = "cash", steamid = target:SteamID(), cash = cash },
            { kind = "tradeLedger", steamid = target:SteamID(), requestId = requestId, safeZoneId = context.den.id, traderId = context.traderId, day = context.day, tradeKind = "sell",
                itemId = itemId, count = count, cash = price, credits = 0, saleLimit = trade.dailySaleCashLimit }
        }
    end })
    if not ok then
        return false, string.find(tostring(result), "could not save", 1, true) and friendlySaveError(result) or result
    end
    target.Cash = cash
    syncCash(target)
    return true, string.format("Sold %d %s for %d cash.", count, name, price)
end

function Trade:BuildState(target, npc)
    local context, reason = self:CheckAccess(target, npc)
    local state = { available = context ~= false and context ~= nil, reason = not context and reason or nil, cash = cashOf(target), credits = Credits:Get(target), offers = {}, sellables = {} }
    if IsValid(npc) and npc.ZM_IsDenNpc then
        local resolved = ZM_DenNpcs:Resolve(npc)
        state.npc = npc.EntIndex and npc:EntIndex() or nil
        state.npcName = resolved.name
        state.services = resolved.job ~= nil and #resolved.services > 0
    end
    if not context then return state end
    local trade = StaticData:GetTrade()
    state.traderId, state.traderName, state.day = context.traderId, context.trader.name, context.day
    local tier, tierName = self.GetDangerTier(context.den.danger)
    state.den = { id = context.den.id, danger = context.den.danger, tier = tier, tierName = tierName, name = ZM_SafeZones:GetName(context.den.id) }
    state.buys = context.trader.buysList
    state.maximumPurchaseUnits = trade.maximumPurchaseUnits
    state.saleLimit = trade.dailySaleCashLimit
    state.soldToday = ZM_GetTradeSaleTotal(target:SteamID(), context.profile, context.day) or 0
    local offers, offersError = self:BuildOffers(context.profile, context.den, context.traderId, context.day)
    if not offers then
        state.available, state.reason = false, offersError
        return state
    end
    for _, offer in ipairs(offers) do
        local entry = table.Copy(offer)
        entry.template = nil
        table.insert(state.offers, entry)
    end
    for slot, instance in SortedPairs(target.ZM_Inventory.backpack or {}) do
        local unsellable = self:UnsellableReason(target, context.trader, instance)
        local definition = Items:GetDefinition(instance.itemId)
        table.insert(state.sellables, {
            instanceId = instance.instanceId, item = instance.itemId, name = Items:GetDisplayName(instance), slot = slot,
            count = instance.count, level = instance.level, mastercraft = instance.mastercraft == true, ultra = Items:IsUltraMastercraft(instance),
            attributes = instance.attributes, maxAttributes = definition and definition.maxAttributes, ammo = self.AmmoInfo(instance.itemId),
            unitPrice = self:SellPrice(instance, 1), price = self:SellPrice(instance, instance.count), reason = unsellable
        })
    end
    return state
end

function Trade:SendState(target, npc, ok, message)
    if not isPlayerEntity(target) then return end
    local state = self:BuildState(target, npc)
    state.ok = ok ~= false
    state.message = message
    net.Start("ZM.TradeState")
        net.WriteString(util.TableToJSON(state, false) or "{}")
    net.Send(target)
end

// Nearest trader NPC in range (or the NPC with entIndex `index`), or nil and a reason.
function Trade:FindTrader(target, index)
    if index then
        local npc = Entity(tonumber(index) or -1)
        if IsValid(npc) and npc.ZM_IsDenNpc then return npc end
        return nil, "That trader is no longer here."
    end
    for _, npc in ipairs(ZM_DenNpcs:FindNear(target, self.Range)) do
        if ZM_DenNpcs:Resolve(npc).trader then return npc end
    end
    return nil, "No trader is nearby."
end

// Validates one client request; the client names an action, the NPC, and an offer or item plus what it was shown.
function Trade:HandleRequest(target, request)
    if type(request) ~= "table" or type(request.action) ~= "string" then
        return nil, false, "Invalid request."
    end
    local npc = self:FindTrader(target, tonumber(request.npc))
    local now = CurTime()
    if target.ZM_NextTradeRequestAt and now < target.ZM_NextTradeRequestAt then
        return npc, false, "Slow down."
    end
    target.ZM_NextTradeRequestAt = now + self.RequestCooldown
    if request.action == "open" then
        return npc, true
    elseif request.action == "buy" then
        return npc, self:Buy(target, npc, { key = request.key, units = tonumber(request.units), requestId = request.requestId, price = tonumber(request.price), currency = request.currency, day = request.day })
    elseif request.action == "sell" then
        local ok, message = self:Sell(target, npc, { ref = request.ref, count = tonumber(request.count), requestId = request.requestId, price = tonumber(request.price) })
        return npc, ok, message
    end
    return npc, false, "Unknown action."
end

net.Receive("ZM.TradeRequest", function(length, target)
    if not IsValid(target) or length > 2048 then return end
    local npc, ok, message = Trade:HandleRequest(target, util.JSONToTable(net.ReadString()))
    Trade:SendState(target, npc, ok, message)
end)

// ---------------------------------------------------------------------------------------------------------------
// Commands (act on the nearest trader NPC)
// ---------------------------------------------------------------------------------------------------------------

local firstHuman = ZM_Util.FirstHuman

local function newRequestId()
    return string.format("cmd%08x%06x", os.time(), math.random(0, 0xFFFFFF))
end

local function runTradeCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command, { zn_trade = true }) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    if not target then return false, "no target player" end
    local ok, message = true, nil
    local npc, npcError = Trade:FindTrader(target, command == "zn_trade" and tonumber(arguments[1]) or nil)
    if command == "zn_trade_buy" then
        // zn_trade_buy <offerKey> [units] [requestId]
        ok, message = Trade:Buy(target, npc, { key = arguments[1], units = tonumber(arguments[2]) or 1, requestId = arguments[3] or newRequestId() })
    elseif command == "zn_trade_sell" then
        // zn_trade_sell <instanceId|itemId> [count] [requestId]
        ok, message = Trade:Sell(target, npc, { ref = arguments[1], count = tonumber(arguments[2]), requestId = arguments[3] or newRequestId() })
    elseif command == "zn_dev_reset_trade" then
        ok, message = ZM_DeleteTradeData(target:SteamID(), profileFor(target), true)
        message = ok and "deleted this player's trade ledger and the profile's den stock" or message
    elseif command == "zn_dev_trade_danger" then
        local value = arguments[1]
        if value == nil or value == "off" then
            Trade.DangerOverride = nil
            message = "den danger override cleared"
        elseif tonumber(value) and tonumber(value) >= 0 and tonumber(value) <= 1 then
            Trade.DangerOverride = tonumber(value)
            message = "den danger override set to " .. value
        else
            ok, message = false, "the override must be from 0 to 1, or off"
        end
    elseif not npc then
        ok, message = false, npcError
    end
    local line = "[ZombieSim] " .. command .. ": " .. tostring(message or (ok and "ok" or "failed"))
    ZM_Util.Print(caller, line)
    if ZM_DevConsole and ZM_DevConsole.Report then
        local state = Trade:BuildState(target, npc)
        state.command, state.ok, state.message = command, ok, message
        state.dangerOverride = Trade.DangerOverride
        state.storedCash = (ZM_GetPlayerData(target:SteamID(), profileFor(target)) or {}).Cash
        state.storedCredits = ZM_GetPlayerCredits(target:SteamID(), profileFor(target))
        state.ledger = ZM_GetTradeLedger(target:SteamID(), profileFor(target), 5)
        state.sellables = nil
        ZM_DevConsole:Report("trade", state)
    end
    Trade:SendState(target, npc, ok, message)
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_trade = "zn_trade [npcEntIndex]: reports the nearest trader's offers, stock, and prices for the target player.",
    zn_trade_buy = "zn_trade_buy <offerKey> [units] [requestId]: admin; buys from the nearest trader (reusing a request id is refused).",
    zn_trade_sell = "zn_trade_sell <instanceId|itemId> [count] [requestId]: admin; sells a backpack item to the nearest trader.",
    zn_dev_reset_trade = "Development: deletes the target player's trade ledger and the active profile's den trader stock.",
    zn_dev_trade_danger = "Development: zn_dev_trade_danger <0..1|off>: overrides the den danger used for trader stock."
}, runTradeCommand)
