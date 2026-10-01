// Client den trading window. Offers, stock, prices, and sellability come from the server (ZM.TradeState); the client
// sends only the offer key or item, the quantity, the price it showed, and a fresh request id for each click.
ZM_TradingUI = ZM_TradingUI or {}
local UI = ZM_TradingUI

local good = Color(96, 190, 110)
local bad = Color(239, 57, 72)
local gold = Color(222, 184, 84)
local creditBlue = Color(110, 170, 240)
local tierColors = { Color(96, 190, 110), Color(222, 184, 84), Color(230, 130, 60), Color(239, 57, 72) }

function UI:SendRequest(request)
    request.npc = self.NpcIndex
    net.Start("ZM.TradeRequest")
        net.WriteString(util.TableToJSON(request, false) or "{}")
    net.SendToServer()
end

local function newRequestId()
    return string.format("c%08x%06x", os.time(), math.random(0, 0xFFFFFF))
end

local function currencyText(amount, currency)
    return currency == "credits" and (amount .. " CR") or ("$" .. amount)
end

local function line(parent, text, color, font)
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:DockMargin(0, 0, 0, 2)
    label:SetFont(font or "ZM_CraftingBody")
    label:SetTextColor(color or ZM_DermaSkin.Palette.text)
    label:SetText(text)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
    return label
end

local function qualityText(entry)
    local parts = {}
    for name, value in SortedPairs(entry.attributes or {}) do
        table.insert(parts, string.sub(name, 1, 5) .. " " .. value .. "/" .. tostring(entry.maxAttributes))
    end
    return table.concat(parts, " ")
end

local function nameColor(entry)
    return entry.ultra and gold or (entry.mastercraft and good or ZM_DermaSkin.Palette.text)
end

// The sale price the server will compute for `count` units: floor(value x sellMultiplier).
local function salePrice(entry, count)
    local trade = ZM_StaticData:GetTrade()
    if not trade then return entry.unitPrice * count end
    local value = ZM_Items:GetInstanceValue({ itemId = entry.item, count = count, level = entry.level, mastercraft = entry.mastercraft, attributes = entry.attributes })
    return math.floor(value * trade.sellMultiplier)
end

local function quantityWang(parent, maximum, onChange)
    local wang = vgui.Create("DNumberWang", parent)
    wang:Dock(RIGHT)
    wang:SetWide(56)
    wang:DockMargin(4, 12, 4, 12)
    wang:SetDecimals(0)
    wang:SetMin(1)
    wang:SetMax(math.max(1, maximum))
    wang:SetValue(1)
    wang.OnValueChanged = function(_, value) onChange(math.Clamp(math.floor(tonumber(value) or 1), 1, math.max(1, maximum))) end
    return wang
end

local function offerRow(parent, state, offer)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(50)
    row:DockMargin(0, 0, 0, 2)
    local details = { "lvl " .. offer.level }
    if offer.bundle > 1 then table.insert(details, "x" .. offer.bundle .. " per unit") end
    table.insert(details, offer.remaining .. "/" .. offer.stock .. " in stock")
    if offer.essential then table.insert(details, "essential") end
    if offer.ammo then table.insert(details, offer.ammo) end
    local quality = qualityText(offer)
    if quality ~= "" then table.insert(details, quality) end
    local detailText = table.concat(details, "  |  ")
    row.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText(offer.name, "ZM_CraftingBody", 8, 14, nameColor(offer), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(currencyText(offer.price, offer.currency) .. " each", "ZM_CraftingSmall", width - 250, 14, offer.currency == "credits" and creditBlue or ZM_DermaSkin.Palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText(detailText, "ZM_CraftingSmall", 8, 34, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local button = vgui.Create("DButton", row)
    button:Dock(RIGHT)
    button:SetWide(130)
    button:DockMargin(4, 10, 8, 10)
    local units = 1
    local function refresh()
        button:SetText(offer.remaining > 0 and ("Buy " .. currencyText(offer.price * units, offer.currency)) or "Sold out")
    end
    local maximum = math.min(offer.remaining, state.maximumPurchaseUnits or 1)
    if offer.remaining > 0 then
        quantityWang(row, maximum, function(value) units = value refresh() end)
    end
    button:SetEnabled(offer.remaining > 0 and state.available == true)
    refresh()
    button.DoClick = function()
        UI:SendRequest({ action = "buy", key = offer.key, units = units, price = offer.price, currency = offer.currency, day = state.day, requestId = newRequestId() })
    end
end

local function sellRow(parent, state, entry)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(50)
    row:DockMargin(0, 0, 0, 2)
    local details = { "lvl " .. entry.level, "x" .. entry.count }
    if entry.ammo then table.insert(details, entry.ammo) end
    local quality = qualityText(entry)
    if quality ~= "" then table.insert(details, quality) end
    local detailText = entry.reason or table.concat(details, "  |  ")
    row.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText(entry.name, "ZM_CraftingBody", 8, 14, entry.reason and ZM_DermaSkin.Palette.muted or nameColor(entry), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(detailText, "ZM_CraftingSmall", 8, 34, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local button = vgui.Create("DButton", row)
    button:Dock(RIGHT)
    button:SetWide(110)
    button:DockMargin(4, 10, 8, 10)
    local count = 1
    local function refresh()
        button:SetText(entry.reason and "Won't buy" or ("Sell $" .. salePrice(entry, count)))
        button:SetEnabled(entry.reason == nil and state.available == true and salePrice(entry, count) > 0)
    end
    if not entry.reason and entry.count > 1 then
        quantityWang(row, entry.count, function(value) count = value refresh() end)
    end
    if entry.reason then button:SetTooltip(entry.reason) end
    refresh()
    button.DoClick = function()
        UI:SendRequest({ action = "sell", ref = entry.instanceId, count = count, price = salePrice(entry, count), requestId = newRequestId() })
    end
end

net.Receive("ZM.TradeState", function()
    local state = util.JSONToTable(net.ReadString())
    if type(state) ~= "table" then return end
    UI.State = state
    if state.message then
        UI.Message = { text = state.message, ok = state.ok ~= false }
    end
    UI:Rebuild()
end)

// Pressing E on a den NPC: traders open this window; professionals without a trade table open the Services window.
net.Receive("ZM.DenNpc.Open", function()
    local index = net.ReadUInt(16)
    local trader = net.ReadBool()
    local services = net.ReadBool()
    if trader then
        UI:Open(index)
    elseif services and ZM_ProfessionsUI then
        ZM_ProfessionsUI:Open()
    end
end)

function UI:Rebuild()
    local frame = self.Frame
    if not IsValid(frame) or not IsValid(frame.Body) then return end
    frame.Body:Clear()
    local state = self.State
    if not state then
        line(frame.Body, "Loading...", ZM_DermaSkin.Palette.muted)
        return
    end
    local body = frame.Body
    frame:SetTitle(string.upper(state.traderName or state.npcName or "TRADER"))
    local header = vgui.Create("DPanel", body)
    header:Dock(TOP)
    header:SetTall(40)
    header.Paint = function(_, width, height)
        draw.SimpleText(string.format("Cash $%d", state.cash or 0), "ZM_CraftingHeading", 0, 12, ZM_DermaSkin.Palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("Credits %d CR", state.credits or 0), "ZM_CraftingHeading", 180, 12, creditBlue, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if state.den then
            local tier = state.den.tier or 1
            draw.SimpleText(string.format("%s  |  %s danger (%.2f)", state.den.name or state.den.id, state.den.tierName or "?", state.den.danger or 0), "ZM_CraftingSmall", width, 10, tierColors[tier] or ZM_DermaSkin.Palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("Stock for %s UTC  |  sold today $%d of $%d", tostring(state.day), state.soldToday or 0, state.saleLimit or 0), "ZM_CraftingSmall", width, 28, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    if not state.available then
        line(body, state.reason or "This trader is unavailable.", bad)
    end
    local footer = vgui.Create("DPanel", body)
    footer:Dock(BOTTOM)
    footer:SetTall(28)
    footer:DockMargin(0, 6, 0, 0)
    footer.Paint = function(_, _, height)
        local message = UI.Message
        if message then
            draw.SimpleText(message.text, "ZM_CraftingSmall", 0, height * 0.5, message.ok and good or bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    if state.services and ZM_ProfessionsUI then
        local services = vgui.Create("DButton", footer)
        services:Dock(RIGHT)
        services:SetWide(120)
        services:SetText("Services")
        services.DoClick = function() ZM_ProfessionsUI:Open() end
    end

    local sellColumn = vgui.Create("DPanel", body)
    sellColumn:Dock(RIGHT)
    sellColumn:SetWide(math.floor(frame:GetWide() * 0.4))
    sellColumn:DockMargin(10, 4, 0, 0)
    sellColumn.Paint = nil
    local buys = {}
    for _, category in ipairs(state.buys or {}) do table.insert(buys, category) end
    line(sellColumn, "SELL FOR CASH" .. (#buys > 0 and ("  |  buys " .. table.concat(buys, ", ")) or ""), ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    local sellList = vgui.Create("DScrollPanel", sellColumn)
    sellList:Dock(FILL)
    if #(state.sellables or {}) == 0 then line(sellList, "Your backpack is empty.", ZM_DermaSkin.Palette.muted) end
    for _, entry in ipairs(state.sellables or {}) do sellRow(sellList, state, entry) end

    local buyColumn = vgui.Create("DPanel", body)
    buyColumn:Dock(FILL)
    buyColumn:DockMargin(0, 4, 0, 0)
    buyColumn.Paint = nil
    line(buyColumn, "BUY  |  $ = cash, CR = credits  |  bought items go to your backpack", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    local buyList = vgui.Create("DScrollPanel", buyColumn)
    buyList:Dock(FILL)
    if #(state.offers or {}) == 0 then line(buyList, "Nothing for sale today.", ZM_DermaSkin.Palette.muted) end
    for _, offer in ipairs(state.offers or {}) do offerRow(buyList, state, offer) end
end

function UI:Open(npcIndex)
    self.NpcIndex = npcIndex or self.NpcIndex
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:SendRequest({ action = "open" })
        return
    end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("TRADER")
    frame:SetSize(math.min(980, ScrW() - 40), math.min(560, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if UI.Frame == frame then UI.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
    self.State = nil
    self.Message = nil
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(8, 8, 8, 8)
    body.Paint = nil
    frame.Body = body
    self:Rebuild()
    self:SendRequest({ action = "open" })
end

concommand.Add("zn_trade_window", function()
    UI:Open()
end, nil, "Opens the trading window for the nearest den trader.")
