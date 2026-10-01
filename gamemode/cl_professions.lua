// Client Services window and provider offer prompt. Profession, delivery, and service eligibility come from the
// server (ZM.ProfessionState); the client only names a provider, service kind, item or recipe, count, and fee.
ZM_ProfessionsUI = ZM_ProfessionsUI or {}
local UI = ZM_ProfessionsUI

local good = Color(96, 190, 110)
local bad = Color(239, 57, 72)
local gold = Color(222, 184, 84)
local serviceLabels = { cook = "Cook", treat = "Treat", research = "Research", implant = "Install implant", extract = "Remove implant" }

local function itemName(itemId)
    local definition = ZM_Items:GetDefinition(itemId)
    return definition and definition.name or itemId
end

function UI:SendRequest(request)
    net.Start("ZM.ProfessionRequest")
        net.WriteString(util.TableToJSON(request, false) or "{}")
    net.SendToServer()
end

net.Receive("ZM.ProfessionState", function()
    local state = util.JSONToTable(net.ReadString())
    if type(state) ~= "table" then return end
    UI.State = state
    if state.message then
        UI.Message = { text = state.message, ok = state.ok ~= false }
    end
    UI:Rebuild()
end)

// Installed implants and capped modifiers; sent whenever they change (also embedded in ZM.ProfessionState).
net.Receive("ZM.ImplantState", function()
    local implants = util.JSONToTable(net.ReadString())
    if type(implants) ~= "table" then return end
    UI.Implants = implants
    if UI.State then UI.State.implants = implants end
    UI:Rebuild()
end)

// A customer asked this player for a service: accept or decline. The server re-checks everything on acceptance.
net.Receive("ZM.ProfessionOffer", function()
    local offer = util.JSONToTable(net.ReadString())
    if type(offer) ~= "table" or type(offer.id) ~= "string" then return end
    local what = offer.kind == "cook" and string.format("cook %d %s", offer.count or 1, tostring(offer.name))
        or offer.kind == "treat" and ("treat them with " .. tostring(offer.name))
        or offer.kind == "implant" and ("install " .. tostring(offer.name) .. " (their old implant in that slot is returned to them)")
        or offer.kind == "extract" and ("remove their " .. tostring(offer.name))
        or ("research " .. tostring(offer.name))
    Derma_Query(
        string.format("%s asks you to %s for a fee of %d.\nThey supply the items. This request expires in %ds.", tostring(offer.customer), what, tonumber(offer.fee) or 0, tonumber(offer.expiresIn) or 0),
        "Service Request",
        "Accept",
        function() UI:SendRequest({ action = "respond", offerId = offer.id, accept = true }) end,
        "Decline",
        function() UI:SendRequest({ action = "respond", offerId = offer.id, accept = false }) end
    )
end)

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

local function describeStacks(stacks)
    local parts = {}
    for _, stack in ipairs(stacks or {}) do
        table.insert(parts, stack.count .. " " .. itemName(stack.item))
    end
    return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

local function buildProfile(parent, state)
    local panel = vgui.Create("DScrollPanel", parent)
    panel:Dock(LEFT)
    panel:SetWide(280)
    panel:DockMargin(0, 0, 10, 0)
    line(panel, state.professionName, ZM_DermaSkin.Palette.text, "ZM_CraftingHeading")
    line(panel, string.format("Level %d  |  Cash %d", state.level or 1, state.cash or 0), ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    if state.storedJob and state.storedJob ~= state.job then
        line(panel, "Stored job '" .. state.storedJob .. "' is treated as " .. state.job .. ".", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    end
    if state.description ~= "" then line(panel, state.description) end
    local bonuses = {}
    for attribute, bonus in SortedPairs(state.statBonuses or {}) do
        table.insert(bonuses, "+" .. bonus .. " " .. attribute)
    end
    if #bonuses > 0 then line(panel, "Bonuses: " .. table.concat(bonuses, ", "), good, "ZM_CraftingSmall") end
    if #(state.services or {}) > 0 then
        local labels = {}
        for _, service in ipairs(state.services) do table.insert(labels, serviceLabels[service] or service) end
        line(panel, "Offers: " .. table.concat(labels, ", "), gold, "ZM_CraftingSmall")
    end

    line(panel, "TODAY'S DELIVERY (" .. tostring(state.day) .. " UTC)", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall"):DockMargin(0, 10, 0, 2)
    local delivery = state.delivery or {}
    if delivery.claimed then
        line(panel, "Arrived: " .. describeStacks(delivery.items), good)
    elseif delivery.items then
        line(panel, "Due: " .. describeStacks(delivery.items), ZM_DermaSkin.Palette.text)
        line(panel, state.inDen and "It arrives while you are in your den with room to spare." or "It arrives when you are in your den.", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    else
        line(panel, "Your profession has no daily delivery.", ZM_DermaSkin.Palette.muted)
    end

    local implants = state.implants or UI.Implants
    if implants then
        line(panel, "IMPLANTS", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall"):DockMargin(0, 10, 0, 2)
        for _, slot in ipairs(implants.slots or {}) do
            if slot.name then
                line(panel, string.format("%s: %s (lvl %d)", slot.slot, slot.name, slot.level or 1))
            else
                line(panel, slot.slot .. ": empty", ZM_DermaSkin.Palette.muted)
            end
        end
        for _, effect in ipairs(implants.effects or {}) do
            line(panel, effect.text .. (effect.capped and " (capped)" or ""), good, "ZM_CraftingSmall")
        end
        line(panel, "A Doctor in a den installs and removes implants.", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    end
end

// Choices for one service kind from the customer's own items (cook/treat) or research recipes.
local function serviceChoices(state, kind)
    local choices = {}
    if kind == "cook" then
        for _, entry in ipairs(state.cookables or {}) do
            table.insert(choices, { label = string.format("%s -> %s (%d)", itemName(entry.item), itemName(entry.cooksInto), entry.have or 0), ref = entry.item, max = entry.have or 1 })
        end
    elseif kind == "treat" then
        for _, entry in ipairs(state.treatables or {}) do
            table.insert(choices, { label = string.format("%s (+%d HP)", itemName(entry.item), entry.health or 0), ref = entry.item, max = 1 })
        end
    elseif kind == "implant" then
        for _, entry in ipairs(state.installables or {}) do
            table.insert(choices, { label = string.format("%s -> %s slot (lvl %d)", itemName(entry.item), entry.slot, entry.level or 1), ref = entry.item, max = 1 })
        end
    elseif kind == "extract" then
        for _, slot in ipairs(state.implants and state.implants.slots or {}) do
            if slot.name then
                table.insert(choices, { label = string.format("%s: %s (lvl %d)", slot.slot, slot.name, slot.level or 1), ref = slot.slot, max = 1 })
            end
        end
    elseif kind == "research" then
        for _, entry in ipairs(state.research or {}) do
            local parts = {}
            for _, stack in ipairs(entry.ingredients or {}) do
                table.insert(parts, string.format("%s %d/%d", itemName(stack.item), stack.have or 0, stack.count))
            end
            table.insert(choices, { label = entry.name .. " (lvl " .. (entry.levelRequirement or 1) .. ": " .. table.concat(parts, ", ") .. ")", ref = entry.id, max = 1 })
        end
    end
    return choices
end

local function buildServices(parent, state)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(FILL)
    panel.Paint = nil
    line(panel, "REQUEST A SERVICE", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    line(panel, "You supply the items; the professional's job and level decide what they can do.", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")

    if state.pending then
        line(panel, string.format("Waiting for %s to answer (%s, %ds left).", state.pending.provider, serviceLabels[state.pending.kind] or state.pending.kind, state.pending.expiresIn or 0), gold)
        local cancel = vgui.Create("DButton", panel)
        cancel:Dock(TOP)
        cancel:SetTall(26)
        cancel:SetText("Cancel request")
        cancel.DoClick = function() UI:SendRequest({ action = "cancel" }) end
        return
    end
    if #(state.professionals or {}) == 0 then
        line(panel, "No professionals are nearby.", bad)
        return
    end

    local selection = UI.Selection or {}
    UI.Selection = selection
    local provider
    for _, entry in ipairs(state.professionals) do
        if (entry.providerId or entry.userId) == selection.provider then provider = entry end
    end
    provider = provider or state.professionals[1]
    selection.provider = provider.providerId or provider.userId
    if not table.HasValue(provider.services, selection.kind) then selection.kind = provider.services[1] end

    local providerBox = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", panel))
    providerBox:Dock(TOP)
    providerBox:DockMargin(0, 6, 0, 4)
    providerBox:SetTall(24)
    for _, entry in ipairs(state.professionals) do
        local entryId = entry.providerId or entry.userId
        providerBox:AddChoice(string.format("%s%s - %s lvl %d", entry.name, entry.self and " (you)" or (entry.npc and " (den NPC)" or ""), entry.job, entry.level), entryId, entryId == selection.provider)
    end
    providerBox.OnSelect = function(_, _, _, providerId)
        selection.provider = providerId
        UI:Rebuild()
    end

    local kindBox = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", panel))
    kindBox:Dock(TOP)
    kindBox:DockMargin(0, 0, 0, 4)
    kindBox:SetTall(24)
    for _, kind in ipairs(provider.services) do
        kindBox:AddChoice(serviceLabels[kind] or kind, kind, kind == selection.kind)
    end
    kindBox.OnSelect = function(_, _, _, kind)
        selection.kind = kind
        selection.ref = nil
        UI:Rebuild()
    end

    local choices = serviceChoices(state, selection.kind)
    if #choices == 0 then
        line(panel, "You have nothing for this service.", bad)
        return
    end
    local choice
    for _, entry in ipairs(choices) do
        if entry.ref == selection.ref then choice = entry end
    end
    choice = choice or choices[1]
    selection.ref = choice.ref

    local refBox = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", panel))
    refBox:Dock(TOP)
    refBox:DockMargin(0, 0, 0, 4)
    refBox:SetTall(24)
    for _, entry in ipairs(choices) do
        refBox:AddChoice(entry.label, entry.ref, entry.ref == choice.ref)
    end
    refBox.OnSelect = function(_, _, _, ref)
        selection.ref = ref
        UI:Rebuild()
    end

    local controls = vgui.Create("DPanel", panel)
    controls:Dock(TOP)
    controls:SetTall(28)
    controls:DockMargin(0, 4, 0, 0)
    controls.Paint = nil

    local send = vgui.Create("DButton", controls)
    send:Dock(RIGHT)
    send:SetWide(120)
    // Den NPCs charge a fixed fee and do the work at once; players are offered the fee the customer chooses.
    local npcFee = provider.npc and (provider.fees or {})[selection.kind] or nil
    send:SetText(provider.self and "Do it" or (provider.npc and "Pay & do it" or "Request"))

    local fee = vgui.Create("DNumberWang", controls)
    fee:Dock(RIGHT)
    fee:SetWide(80)
    fee:DockMargin(0, 0, 8, 0)
    fee:SetDecimals(0)
    fee:SetMin(0)
    if npcFee then
        fee:SetMax(npcFee)
        fee:SetValue(npcFee)
        fee:SetEnabled(false)
    else
        fee:SetMax(provider.self and 0 or math.max(0, state.cash or 0))
        fee:SetValue(provider.self and 0 or math.Clamp(selection.fee or 0, 0, math.max(0, state.cash or 0)))
        fee:SetEnabled(not provider.self)
    end
    fee.OnValueChanged = function(_, value) selection.fee = math.floor(tonumber(value) or 0) end
    local feeLabel = vgui.Create("DLabel", controls)
    feeLabel:Dock(RIGHT)
    feeLabel:SetWide(36)
    feeLabel:SetText("Fee")
    feeLabel:SetTextColor(ZM_DermaSkin.Palette.muted)

    local count
    if selection.kind == "cook" then
        count = vgui.Create("DNumberWang", controls)
        count:Dock(RIGHT)
        count:SetWide(60)
        count:DockMargin(0, 0, 8, 0)
        count:SetDecimals(0)
        count:SetMin(1)
        count:SetMax(math.Clamp(choice.max, 1, 10))
        count:SetValue(math.Clamp(selection.count or 1, 1, math.Clamp(choice.max, 1, 10)))
        count.OnValueChanged = function(_, value) selection.count = math.floor(tonumber(value) or 1) end
    end

    send.DoClick = function()
        UI:SendRequest({
            action = "request", provider = provider.providerId or provider.userId, kind = selection.kind, ref = selection.ref,
            count = count and math.floor(tonumber(count:GetValue()) or 1) or 1,
            fee = npcFee or (provider.self and 0 or math.floor(tonumber(fee:GetValue()) or 0))
        })
    end
end

function UI:Rebuild()
    local frame = self.Frame
    if not IsValid(frame) or not IsValid(frame.Body) then return end
    frame.Body:Clear()
    local state = self.State
    if not state then
        line(frame.Body, "Loading...", ZM_DermaSkin.Palette.muted)
        return
    end
    local footer = vgui.Create("DPanel", frame.Body)
    footer:Dock(BOTTOM)
    footer:SetTall(22)
    footer.Paint = function(_, width, height)
        local message = UI.Message
        if message then
            draw.SimpleText(message.text, "ZM_CraftingSmall", 0, height * 0.5, message.ok and ZM_DermaSkin.Palette.muted or bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    buildProfile(frame.Body, state)
    buildServices(frame.Body, state)
end

function UI:Open()
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:SendRequest({ action = "open" })
        return
    end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("SERVICES")
    frame:SetSize(math.min(720, ScrW() - 40), math.min(420, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if UI.Frame == frame then UI.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
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

concommand.Add("zn_services", function()
    UI:Open()
end, nil, "Opens the Services window (profession, daily delivery, and professional services).")
