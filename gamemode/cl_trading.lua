// Client den trading window. Offers, stock, prices, and sellability come from the server (ZM.TradeState); the client
// sends only the offer key or item, the quantity, the price it showed, and a fresh request id for each click.
ZM_TradingUI = ZM_TradingUI or {}
local UI = ZM_TradingUI

local good = Color(96, 190, 110)
local bad = Color(239, 57, 72)
local gold = Color(222, 184, 84)
local tierColors = { Color(96, 190, 110), Color(222, 184, 84), Color(230, 130, 60), Color(239, 57, 72) }
local denNpcInteraction = ZM_DenNpcInteraction or {}
ZM_DenNpcInteraction = denNpcInteraction
denNpcInteraction.HoldSeconds = 0.25
denNpcInteraction.Range = 160
denNpcInteraction.UseIntercepted = denNpcInteraction.UseIntercepted or false

local serviceLabels = {
    cook = "COOK",
    treat = "TREAT",
    research = "RESEARCH",
    implant = "INSTALL IMPLANT",
    extract = "REMOVE IMPLANT"
}

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

local function findAimedDenNpc()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive()
        or not (ZM_IsInDenCamera and ZM_IsInDenCamera()) then
        return nil
    end
    local trace = playerEntity:GetEyeTrace()
    local npc = trace and trace.Entity
    if not IsValid(npc) or npc:GetClass() ~= "zn_den_npc"
        or playerEntity:GetPos():DistToSqr(npc:GetPos()) > denNpcInteraction.Range * denNpcInteraction.Range then
        return nil
    end
    return npc
end

local function findAimedDenUseEntity()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive()
        or not (ZM_IsInDenCamera and ZM_IsInDenCamera()) then
        return nil
    end
    local trace = playerEntity:GetEyeTrace()
    local entity = trace and trace.Entity
    if not IsValid(entity) then return nil end
    local class = entity:GetClass()
    if class ~= "zn_bank" and class ~= "zn_den_stash" then return nil end
    if playerEntity:GetPos():DistToSqr(entity:GetPos()) > denNpcInteraction.Range * denNpcInteraction.Range then
        return nil
    end
    return entity
end

local function buildNpcActions(npc)
    local actions = {}
    local job = npc:GetNWString("ZM_NpcJob", "")
    local profession = job ~= "" and ZM_Professions:Get(job) or nil
    local services = profession and table.GetKeys(profession.services) or {}
    table.sort(services)
    for _, kind in ipairs(services) do
        table.insert(actions, { id = "service:" .. kind, kind = kind, label = serviceLabels[kind] or string.upper(kind), enabled = true })
    end
    if npc:GetNWString("ZM_NpcTrader", "") ~= "" then
        table.insert(actions, { id = "trade", label = "TRADE", enabled = true })
    end
    table.insert(actions, { id = "talk", label = "TALK", enabled = true })
    table.insert(actions, { id = "future", label = "COMING SOON", enabled = false })
    for index, action in ipairs(actions) do
        local slice = 360 / #actions
        action.centerAngle = -90 + (index - 1) * slice
        action.startAngle = action.centerAngle - slice * 0.5
        action.endAngle = action.centerAngle + slice * 0.5
    end
    return actions
end

local function selectedNpcAction(cursorX, cursorY, width, height, actions)
    local deltaX = cursorX - width * 0.5
    local deltaY = cursorY - height * 0.5
    if deltaX * deltaX + deltaY * deltaY < (math.min(width, height) * 0.1) ^ 2 then return nil end
    local angle = math.deg(math.atan2(deltaY, deltaX))
    local best, bestDistance = nil, 181
    for _, action in ipairs(actions) do
        local distance = math.abs(math.NormalizeAngle(angle - action.centerAngle))
        if distance < bestDistance then
            best, bestDistance = action, distance
        end
    end
    return best
end

local function canSeeNpc(playerEntity, npc)
    local trace = util.TraceLine({
        start = playerEntity:EyePos(),
        endpos = npc:WorldSpaceCenter(),
        filter = { playerEntity, npc },
        mask = MASK_SOLID
    })
    return not trace.Hit
end

local function openNpcTalk(npc)
    if not IsValid(npc) then return end
    local name = npc:GetNWString("ZM_NpcName", "Den Resident")
    local job = npc:GetNWString("ZM_NpcJob", "")
    local profession = job ~= "" and ZM_Professions:Get(job) or nil
    local services = profession and table.GetKeys(profession.services) or {}
    table.sort(services)
    local level = npc:GetNWInt("ZM_NpcLevel", 1)
    local hasTrader = npc:GetNWString("ZM_NpcTrader", "") ~= ""
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("TALK - " .. name)
    frame:SetSize(math.min(420, ScrW() - 40), math.min(260, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if denNpcInteraction.TalkFrame == frame then denNpcInteraction.TalkFrame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    denNpcInteraction.TalkFrame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 8, 12, 12)
    body.Paint = nil
    line(body, name, ZM_DermaSkin.Palette.text, "ZM_CraftingHeading")
    line(body, job ~= "" and ((profession and profession.name or job) .. "  |  Level " .. level) or "Den resident", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    if #services > 0 then
        local labels = {}
        for _, kind in ipairs(services) do table.insert(labels, serviceLabels[kind] or string.upper(kind)) end
        line(body, "Services: " .. table.concat(labels, ", "), gold)
    end
    if hasTrader then line(body, "Trading: available", ZM_DermaSkin.Palette.muted) end
    if #services == 0 and not hasTrader then
        line(body, "No services or goods are available here yet.", ZM_DermaSkin.Palette.muted)
    else
        line(body, "Choose a service or trade from the interaction menu.", ZM_DermaSkin.Palette.muted)
    end
end

function denNpcInteraction:Activate(npc, action)
    if not IsValid(npc) or not action or not action.enabled then return end
    if string.StartWith(action.id, "service:") and ZM_ProfessionsUI then
        ZM_ProfessionsUI:Open("n:" .. tostring(npc:EntIndex()), action.kind)
    elseif action.id == "trade" then
        UI:Open(npc:EntIndex())
    elseif action.id == "talk" then
        openNpcTalk(npc)
    end
end

function denNpcInteraction:CloseRadial(activate)
    local panel = self.Panel
    self.Panel = nil
    if not IsValid(panel) then return end
    local npc = panel.TargetNpc
    local action = panel.SelectedAction
    panel:Remove()
    if activate then self:Activate(npc, action) end
end

function denNpcInteraction:OpenRadial(npc)
    if not IsValid(npc) or IsValid(self.Panel) then return end
    local actions = buildNpcActions(npc)
    local panel = vgui.Create("DPanel")
    panel:SetSize(ScrW(), ScrH())
    panel:SetPos(0, 0)
    panel:SetMouseInputEnabled(true)
    panel:SetKeyboardInputEnabled(false)
    panel.TargetNpc = npc
    panel.Actions = actions
    panel.Think = function(currentPanel)
        local playerEntity = LocalPlayer()
        if not IsValid(currentPanel.TargetNpc) or not IsValid(playerEntity)
            or playerEntity:GetPos():DistToSqr(currentPanel.TargetNpc:GetPos()) > self.Range * self.Range
            or not canSeeNpc(playerEntity, currentPanel.TargetNpc) then
            self:CloseRadial(false)
            return
        end
        local cursorX, cursorY = gui.MousePos()
        currentPanel.SelectedAction = selectedNpcAction(cursorX, cursorY, currentPanel:GetWide(), currentPanel:GetTall(), currentPanel.Actions)
    end
    panel.Paint = function(currentPanel, width, height)
        local palette = ZM_DermaSkin.Palette
        local centerX, centerY = width * 0.5, height * 0.5
        local outerRadius = math.min(width, height) * 0.24
        local innerRadius = outerRadius * 0.34
        surface.SetDrawColor(0, 0, 0, 115)
        surface.DrawRect(0, 0, width, height)
        for _, action in ipairs(currentPanel.Actions) do
            local active = currentPanel.SelectedAction == action and action.enabled
            local color = action.enabled and (active and palette.red or palette.panel) or palette.black
            surface.SetDrawColor(color.r, color.g, color.b, action.enabled and 240 or 170)
            local points = {}
            for step = 0, 16 do
                local angle = math.rad(action.startAngle + (action.endAngle - action.startAngle) * step / 16)
                table.insert(points, { x = centerX + math.cos(angle) * outerRadius, y = centerY + math.sin(angle) * outerRadius })
            end
            table.insert(points, { x = centerX, y = centerY })
            draw.NoTexture()
            surface.DrawPoly(points)
            local labelAngle = math.rad(action.centerAngle)
            draw.SimpleText(action.label, "ZM_CraftingSmall", centerX + math.cos(labelAngle) * (innerRadius + outerRadius) * 0.5,
                centerY + math.sin(labelAngle) * (innerRadius + outerRadius) * 0.5,
                action.enabled and palette.text or palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        surface.SetDrawColor(palette.black.r, palette.black.g, palette.black.b, 255)
        surface.DrawCircle(centerX, centerY, innerRadius, palette.black)
        draw.SimpleText(currentPanel.TargetNpc:GetNWString("ZM_NpcName", "DEN NPC"), "ZM_CraftingSmall",
            centerX, centerY, palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    panel.OnMousePressed = function(_, mouseCode)
        if mouseCode == MOUSE_RIGHT then self:CloseRadial(false) end
    end
    panel.OnRemove = function()
        if self.Panel == panel then self.Panel = nil end
        if ZM_UI then
            ZM_UI:UnregisterTransient(panel)
        else
            gui.EnableScreenClicker(false)
        end
    end
    self.Panel = panel
    if ZM_UI then ZM_UI:RegisterTransient(panel) end
    gui.EnableScreenClicker(true)
    input.SetCursorPos(math.floor(ScrW() * 0.5), math.floor(ScrH() * 0.5))
end

local function hasInteractionFocus()
    if vgui.CursorVisible() or vgui.GetKeyboardFocus() or gui.IsGameUIVisible() then return true end
    if ZM_QuickMenu and IsValid(ZM_QuickMenu.Panel) then return true end
    if ZM_UI then
        for panel in pairs(ZM_UI.TransientPanels or {}) do
            if IsValid(panel) then return true end
        end
    end
    return false
end

hook.Add("HUDPaint", "ZM.DenNpc.HoverPrompt", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active or IsValid(denNpcInteraction.Panel) or vgui.CursorVisible() then return end
    if ZM_QuickMenu and IsValid(ZM_QuickMenu.Panel) then return end
    if ZM_UI then
        for panel in pairs(ZM_UI.TransientPanels or {}) do
            if IsValid(panel) then return end
        end
    end
    local x, y = ScrW() * 0.5, ScrH() * 0.5
    if not (ZM_IsInDenCamera and ZM_IsInDenCamera()) and ZM_GetAimCursor then
        x, y = ZM_GetAimCursor()
        x, y = x or ScrW() * 0.5, y or ScrH() * 0.5
    end
    local npc = findAimedDenNpc()
    if IsValid(npc) then
        local name = npc:GetNWString("ZM_NpcName", "Den Resident")
        local role = npc.GetRoleText and npc:GetRoleText() or ""
        draw.SimpleText(name, "ZM_CraftingHeading", x, y - 24, ZM_DermaSkin.Palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if role ~= "" then
            draw.SimpleText(role, "ZM_CraftingSmall", x, y - 6, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("Hold or Press E to interact", "ZM_CraftingSmall", x, y + 16, gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    local entity = findAimedDenUseEntity()
    if not IsValid(entity) then return end
    local class = entity:GetClass()
    local label = class == "zn_bank" and "BANK" or "DEN STASH"
    draw.SimpleText(label, "ZM_CraftingHeading", x, y - 10, ZM_DermaSkin.Palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Press E to interact", "ZM_CraftingSmall", x, y + 14, gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

hook.Add("PlayerBindPress", "ZM.DenNpc.HoldInteraction", function(_, bind, pressed)
    local command = string.lower(bind or "")
    if input.TranslateAlias then command = string.lower(input.TranslateAlias(command) or command) end
    if command == "+use" then
        if pressed then
            if IsValid(denNpcInteraction.Panel) or hasInteractionFocus() then return end
            local npc = findAimedDenNpc()
            if not IsValid(npc) then return end
            denNpcInteraction.TargetNpc = npc
            denNpcInteraction.UseStartedAt = RealTime()
            denNpcInteraction.RadialOpened = false
            denNpcInteraction.UseIntercepted = true
            return true
        end
        if denNpcInteraction.UseIntercepted then
            local npc = denNpcInteraction.TargetNpc
            if IsValid(denNpcInteraction.Panel) then
                denNpcInteraction:CloseRadial(true)
            elseif not denNpcInteraction.RadialOpened and IsValid(npc) and findAimedDenNpc() == npc then
                net.Start("ZM.DenNpc.Interact")
                    net.WriteUInt(npc:EntIndex(), 16)
                net.SendToServer()
            end
            denNpcInteraction.TargetNpc = nil
            denNpcInteraction.UseStartedAt = nil
            denNpcInteraction.RadialOpened = false
            denNpcInteraction.UseIntercepted = false
            return true
        end
    elseif command == "-use" and denNpcInteraction.UseIntercepted then
        if IsValid(denNpcInteraction.Panel) then
            denNpcInteraction:CloseRadial(true)
        elseif not denNpcInteraction.RadialOpened and IsValid(denNpcInteraction.TargetNpc) and findAimedDenNpc() == denNpcInteraction.TargetNpc then
            net.Start("ZM.DenNpc.Interact")
                net.WriteUInt(denNpcInteraction.TargetNpc:EntIndex(), 16)
            net.SendToServer()
        end
        denNpcInteraction.TargetNpc = nil
        denNpcInteraction.UseStartedAt = nil
        denNpcInteraction.RadialOpened = false
        denNpcInteraction.UseIntercepted = false
        return true
    elseif command == "cancelselect" and IsValid(denNpcInteraction.Panel) then
        denNpcInteraction:CloseRadial(false)
        return true
    end
end)

hook.Add("Think", "ZM.DenNpc.HoldRadial", function()
    if not denNpcInteraction.UseIntercepted or denNpcInteraction.RadialOpened
        or not denNpcInteraction.UseStartedAt or RealTime() - denNpcInteraction.UseStartedAt < denNpcInteraction.HoldSeconds then
        return
    end
    local npc = denNpcInteraction.TargetNpc
    if not IsValid(npc) or findAimedDenNpc() ~= npc then
        denNpcInteraction.RadialOpened = true
        return
    end
    denNpcInteraction.RadialOpened = true
    denNpcInteraction:OpenRadial(npc)
end)

hook.Add("PlayerDeath", "ZM.DenNpc.CloseInteraction", function(playerEntity)
    if playerEntity == LocalPlayer() then
        denNpcInteraction:CloseRadial(false)
        denNpcInteraction.TargetNpc = nil
        denNpcInteraction.UseStartedAt = nil
        denNpcInteraction.RadialOpened = false
        denNpcInteraction.UseIntercepted = false
    end
end)

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

local function ammoQuantityText(offer, units)
    local rounds = (tonumber(offer.bundle) or 1) * units
    return string.Comma(rounds) .. " rounds"
end

local function offerTooltip(offer)
    local details = { offer.name, "Level " .. tostring(offer.level) }
    if offer.bundle > 1 then table.insert(details, "Per purchase: " .. string.Comma(offer.bundle) .. (offer.ammo and " rounds" or " items")) end
    if offer.essential then table.insert(details, "Essential ammunition") end
    if offer.ammo then table.insert(details, offer.ammo) end
    local quality = qualityText(offer)
    if quality ~= "" then table.insert(details, quality) end
    return table.concat(details, "\n")
end

local function renderOfferDetail(panel, state, offer)
    panel:Clear()
    local definition = ZM_Items:GetDefinition(offer.item)
    line(panel, offer.name, nameColor(offer), "ZM_CraftingHeading")
    line(panel, string.format("Level %d  |  %d/%d in stock", offer.level, offer.remaining, offer.stock), ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    if offer.mastercraft then
        line(panel, offer.ultra and "ULTRA MASTERCRAFT" or "MASTERCRAFT", gold, "ZM_CraftingSmall")
    end
    if offer.attributes and next(offer.attributes) then
        for name, value in SortedPairs(offer.attributes) do
            line(panel, string.format("%s  %d / %d", name, value, offer.maxAttributes or value), ZM_DermaSkin.Palette.text, "ZM_CraftingSmall")
        end
    end
    if offer.ammo then line(panel, offer.ammo, ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall") end
    if offer.bundle > 1 and not offer.ammo then
        line(panel, "Bundle: " .. string.Comma(offer.bundle) .. " items per purchase", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    end

    local affordability = offer.currency == "credits" and (state.credits or 0) or (state.cash or 0)
    local affordableUnits = offer.price > 0 and math.floor(affordability / offer.price) or 0
    local maximum = math.max(0, math.min(offer.remaining or 0, state.maximumPurchaseUnits or 1, affordableUnits))
    if offer.ammo then
        local rounds = vgui.Create("DLabel", panel)
        rounds:Dock(TOP)
        rounds:DockMargin(0, 2, 0, 6)
        rounds:SetFont("ZM_CraftingSmall")
        rounds:SetTextColor(ZM_DermaSkin.Palette.text)
        rounds:SetWrap(true)
        rounds:SetAutoStretchVertical(true)
        rounds:SetText(ammoQuantityText(offer, 1))
        panel.AmmoSummary = rounds
    end

    line(panel, string.format("%s each", currencyText(offer.price, offer.currency)), gold)
    local quantityRow = vgui.Create("DPanel", panel)
    quantityRow:Dock(TOP)
    quantityRow:SetTall(36)
    quantityRow:DockMargin(0, 3, 0, 4)
    quantityRow.Paint = nil
    local quantity = vgui.Create("DNumberWang", quantityRow)
    quantity:Dock(LEFT)
    quantity:SetWide(66)
    quantity:SetDecimals(0)
    quantity:SetMin(1)
    quantity:SetMax(math.max(1, maximum))
    quantity:SetValue(1)
    panel.Quantity = quantity
    local totalLabel = line(panel, "", ZM_DermaSkin.Palette.text, "ZM_CraftingSmall")
    local function updateTotal(value)
        local units = math.Clamp(math.floor(tonumber(value) or 1), 1, math.max(1, maximum))
        local total = offer.price * units
        totalLabel:SetText(string.format("Total: %s  |  %d purchase unit%s", currencyText(total, offer.currency), units, units == 1 and "" or "s"))
        totalLabel:SizeToContents()
        if IsValid(panel.AmmoSummary) then panel.AmmoSummary:SetText(ammoQuantityText(offer, units)) end
    end
    quantity.OnValueChanged = function(_, value) updateTotal(value) end
    updateTotal(1)

    local function quantityShortcut(units)
        if units > maximum then return end
        local button = vgui.Create("DButton", quantityRow)
        button:Dock(LEFT)
        button:SetWide(52)
        button:DockMargin(5, 3, 0, 3)
        button:SetText(units .. "x")
        button.DoClick = function() quantity:SetValue(units) end
    end
    if maximum >= 1 then quantityShortcut(1) end
    if maximum >= 5 then quantityShortcut(5) end
    if maximum >= 10 then quantityShortcut(10) end

    local buy = vgui.Create("DButton", panel)
    buy:Dock(TOP)
    buy:SetTall(34)
    buy:SetText(maximum > 0 and "BUY" or (offer.remaining <= 0 and "SOLD OUT" or "UNAFFORDABLE"))
    buy:SetEnabled(maximum > 0 and state.available == true)
    buy.DoClick = function()
        local units = math.Clamp(math.floor(tonumber(quantity:GetValue()) or 1), 1, maximum)
        Derma_Query(
            string.format("Buy %d purchase unit%s of %s for %s?", units, units == 1 and "" or "s", offer.name, currencyText(offer.price * units, offer.currency)),
            "Confirm Purchase",
            "Confirm", function()
                UI:SendRequest({ action = "buy", key = offer.key, units = units, price = offer.price, currency = offer.currency, day = state.day, requestId = newRequestId() })
            end,
            "Cancel", function() end
        )
    end
end

local function offerTile(parent, state, offer, detailPanel)
    local definition = ZM_Items:GetDefinition(offer.item)
    local button = vgui.Create("DButton", parent)
    button:SetSize(68, 86)
    button:SetText("")
    button:SetTooltip(offerTooltip(offer))
    button.OfferKey = offer.key
    button.Paint = function(panel, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(0, 0, width, height)
        if definition and ZM_ItemIcons:DrawOverride(definition, 8, 5, width - 16) then
        elseif not definition or not definition.iconModel then
            draw.SimpleText("?", "ZM_CraftingHeading", width * 0.5, 32, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleTextOutlined(offer.name, "ZM_CraftingSmall", width * 0.5, height - 22, nameColor(offer), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 255))
        draw.SimpleText(currencyText(offer.price, offer.currency), "ZM_CraftingSmall", width * 0.5, height - 8, gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    button.PaintOver = function(panel, width, height)
        if offer.mastercraft then
            surface.SetDrawColor(gold)
            surface.DrawOutlinedRect(1, 1, width - 2, height - 2, 2)
        end
        if UI.SelectedOfferKey == offer.key then
            surface.SetDrawColor(ZM_DermaSkin.Palette.text)
            surface.DrawOutlinedRect(3, 3, width - 6, height - 6, 1)
        end
    end
    if definition and definition.iconModel then
        local iconViewport = vgui.Create("DPanel", button)
        iconViewport:SetPos(8, 3)
        iconViewport:SetSize(52, 52)
        iconViewport:SetMouseInputEnabled(false)
        iconViewport:SetKeyboardInputEnabled(false)
        iconViewport.Paint = nil
        ZM_ItemIcons:Attach(iconViewport, definition, 1)
    end
    button.DoClick = function()
        UI.SelectedOfferKey = offer.key
        renderOfferDetail(detailPanel, state, offer)
        if IsValid(parent) then parent:InvalidateLayout() end
    end
    return button
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
    local definition = ZM_Items:GetDefinition(entry.item)
    row.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText(entry.name, "ZM_CraftingBody", 48, 14, entry.reason and ZM_DermaSkin.Palette.muted or nameColor(entry), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, width - 170)
        draw.SimpleText(detailText, "ZM_CraftingSmall", 48, 34, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, width - 170)
    end
    local icon = vgui.Create("DPanel", row)
    icon:Dock(LEFT)
    icon:SetWide(38)
    icon:DockMargin(5, 5, 5, 5)
    icon.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.panel)
        surface.DrawRect(0, 0, width, height)
        if not definition then
            draw.SimpleText("?", "ZM_CraftingBody", width * 0.5, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif not ZM_ItemIcons:DrawOverride(definition, 3, 3, math.min(width, height) - 6) and not definition.iconModel then
            draw.SimpleText("?", "ZM_CraftingBody", width * 0.5, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    if definition and definition.iconModel then ZM_ItemIcons:Attach(icon, definition, 3) end
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
        ZM_ProfessionsUI:Open("n:" .. tostring(index))
    else
        openNpcTalk(Entity(index))
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
        ZM_DermaSkin.DrawTextSegments(0, 12, "ZM_CraftingHeading", {
            { text = "Cash: ", color = ZM_DermaSkin.Palette.text },
            { text = "$" .. string.Comma(state.cash or 0), color = gold }
        })
        ZM_DermaSkin.DrawTextSegments(180, 12, "ZM_CraftingHeading", {
            { text = "Credits: ", color = ZM_DermaSkin.Palette.text },
            { text = string.Comma(state.credits or 0) .. " CR", color = gold }
        })
        if state.den then
            local tier = state.den.tier or 1
            draw.SimpleText(string.format("%s  |  %s danger (%.2f)", state.den.name or state.den.id, state.den.tierName or "?", state.den.danger or 0), "ZM_CraftingSmall", width, 10, tierColors[tier] or ZM_DermaSkin.Palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            ZM_DermaSkin.DrawTextSegments(width, 28, "ZM_CraftingSmall", {
                { text = string.format("Stock for %s UTC  |  sold today ", tostring(state.day)), color = ZM_DermaSkin.Palette.muted },
                { text = "$" .. string.Comma(state.soldToday or 0), color = gold },
                { text = " of ", color = ZM_DermaSkin.Palette.muted },
                { text = "$" .. string.Comma(state.saleLimit or 0), color = gold }
            }, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT)
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
        services.DoClick = function() ZM_ProfessionsUI:Open("n:" .. tostring(UI.NpcIndex)) end
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
    line(buyColumn, "BUY  |  $ = cash, CR = credits  |  select an item for details", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    local purchaseArea = vgui.Create("DPanel", buyColumn)
    purchaseArea:Dock(FILL)
    purchaseArea.Paint = nil
    local detailCard = vgui.Create("DPanel", purchaseArea)
    detailCard:Dock(RIGHT)
    detailCard:SetWide(math.min(270, math.floor(frame:GetWide() * 0.38)))
    detailCard:DockMargin(10, 0, 0, 0)
    detailCard.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.panel)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        surface.SetDrawColor(ZM_DermaSkin.Palette.red)
        surface.DrawRect(1, 1, width - 2, 2)
    end
    line(detailCard, "SELECTED OFFER", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall"):DockMargin(10, 8, 8, 4)
    local detail = vgui.Create("DScrollPanel", detailCard)
    detail:Dock(FILL)
    detail:DockMargin(10, 0, 8, 10)
    detail:GetCanvas():DockPadding(2, 4, 2, 6)
    local gridPanel = vgui.Create("DPanel", purchaseArea)
    gridPanel:Dock(FILL)
    gridPanel.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.black)
        surface.DrawRect(0, 0, width, height)
    end
    local gridScroll = vgui.Create("DScrollPanel", gridPanel)
    gridScroll:Dock(FILL)
    gridScroll:DockMargin(8, 8, 4, 8)
    local grid = vgui.Create("DIconLayout", gridScroll)
    grid:Dock(TOP)
    grid:SetSpaceX(5)
    grid:SetSpaceY(5)
    local selectedOffer
    if #(state.offers or {}) == 0 then
        line(gridScroll, "Nothing for sale today.", ZM_DermaSkin.Palette.muted)
        line(detail, "No purchase selected.", ZM_DermaSkin.Palette.muted)
    else
        for _, offer in ipairs(state.offers) do
            offerTile(grid, state, offer, detail)
            if offer.key == self.SelectedOfferKey then selectedOffer = offer end
        end
        selectedOffer = selectedOffer or state.offers[1]
        self.SelectedOfferKey = selectedOffer.key
        renderOfferDetail(detail, state, selectedOffer)
    end
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
