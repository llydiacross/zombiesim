// Client Mastercrafting Station window. Balances, eligibility, prices, and outcomes come from the server
// (ZM.MastercraftState); the client only asks for a quote on a weapon or job and confirms the server's quote token.
ZM_MastercraftUI = ZM_MastercraftUI or {}
local UI = ZM_MastercraftUI

local good = Color(96, 190, 110)
local bad = Color(239, 57, 72)
local gold = Color(222, 184, 84)

function UI:SendRequest(request)
    net.Start("ZM.MastercraftRequest")
        net.WriteString(util.TableToJSON(request, false) or "{}")
    net.SendToServer()
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

local function attributeText(weapon)
    local parts = {}
    for name, value in SortedPairs(weapon.attributes or {}) do
        table.insert(parts, name .. " " .. value .. "/" .. tostring(weapon.maxAttributes))
    end
    return table.concat(parts, "  ")
end

// Asks the player to accept the server's quote; credits are spent whatever the roll.
function UI:PromptQuote(quote)
    if not quote or self.PromptedQuote == quote.id then return end
    self.PromptedQuote = quote.id
    local text
    if quote.kind == "mastercraft" then
        text = string.format("Mastercraft %s for %d credits?\n\nThe attributes are re-rolled and the credits are spent whatever the result. Each weapon can only be mastercrafted once.", quote.name, quote.cost)
    else
        text = string.format("Change your job to %s for %d credits?", quote.name, quote.cost)
    end
    Derma_Query(text, "MASTERCRAFTING STATION",
        "Confirm", function() UI:SendRequest({ action = "confirm", token = quote.id }) end,
        "Cancel", function() UI:SendRequest({ action = "cancel" }) end)
end

net.Receive("ZM.MastercraftState", function()
    local state = util.JSONToTable(net.ReadString())
    if type(state) ~= "table" then return end
    UI.State = state
    if state.message then
        UI.Message = { text = state.message, ok = state.ok ~= false, ultra = state.ok ~= false and string.find(state.message, "ULTRA", 1, true) ~= nil }
    end
    UI:Rebuild()
    if IsValid(UI.Frame) and state.quote then
        UI:PromptQuote(state.quote)
    end
end)

local function weaponRow(parent, weapon)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(46)
    row:DockMargin(0, 0, 0, 2)
    local eligible = weapon.reason == nil
    row.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText(weapon.name .. "  (level " .. weapon.level .. ")", "ZM_CraftingBody", 8, 13, weapon.ultra and gold or (weapon.mastercraft and good or ZM_DermaSkin.Palette.text), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(attributeText(weapon), "ZM_CraftingSmall", 8, 32, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local button = vgui.Create("DButton", row)
    button:Dock(RIGHT)
    button:DockMargin(4, 8, 8, 8)
    button:SetWide(170)
    if eligible then
        button:SetText("Mastercraft (" .. weapon.cost .. " credits)")
    else
        button:SetText(weapon.mastercraft and "Already mastercrafted" or "Unavailable")
        button:SetTooltip(weapon.reason)
        button:SetEnabled(false)
    end
    button.DoClick = function()
        UI:SendRequest({ action = "quote", kind = "mastercraft", ref = weapon.instanceId })
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
    local body = frame.Body
    line(body, "CREDITS: " .. tostring(state.credits or 0), gold, "ZM_CraftingHeading")
    if not state.available then
        line(body, state.reason or "The station is unavailable.", bad)
    end
    if self.Message then
        line(body, self.Message.text, self.Message.ultra and gold or (self.Message.ok and good or bad), self.Message.ultra and "ZM_CraftingHeading" or "ZM_CraftingBody"):DockMargin(0, 4, 0, 6)
    end

    local jobRow = vgui.Create("DPanel", body)
    jobRow:Dock(BOTTOM)
    jobRow:SetTall(34)
    jobRow:DockMargin(0, 8, 0, 0)
    jobRow.Paint = nil
    local jobLabel = vgui.Create("DLabel", jobRow)
    jobLabel:Dock(LEFT)
    jobLabel:SetWide(190)
    jobLabel:SetFont("ZM_CraftingBody")
    jobLabel:SetTextColor(ZM_DermaSkin.Palette.text)
    jobLabel:SetText("Job: " .. tostring(state.job or "?"))
    local jobChoice = vgui.Create("DComboBox", jobRow)
    jobChoice:Dock(LEFT)
    jobChoice:SetWide(180)
    jobChoice:DockMargin(0, 4, 8, 4)
    jobChoice:SetValue("Choose a job")
    for _, job in ipairs(state.jobs or {}) do
        if job ~= state.job then jobChoice:AddChoice(job, job) end
    end
    local jobButton = vgui.Create("DButton", jobRow)
    jobButton:Dock(LEFT)
    jobButton:SetWide(200)
    jobButton:DockMargin(0, 4, 0, 4)
    jobButton:SetText("Change job (" .. tostring(state.jobChangeCost or "?") .. " credits)")
    jobButton:SetEnabled(state.available == true)
    jobButton.DoClick = function()
        local _, job = jobChoice:GetSelected()
        if job then UI:SendRequest({ action = "quote", kind = "job", ref = job }) end
    end

    line(body, string.format("MASTERCRAFT A WEAPON  |  backpack weapons only  |  %.0f%% Ultra chance", (state.ultraChance or 0) * 100), ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall"):DockMargin(0, 6, 0, 2)
    local list = vgui.Create("DScrollPanel", body)
    list:Dock(FILL)
    if #(state.weapons or {}) == 0 then
        line(list, "No weapons in your backpack.", ZM_DermaSkin.Palette.muted)
    end
    for _, weapon in ipairs(state.weapons or {}) do
        weaponRow(list, weapon)
    end
end

function UI:Open()
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:SendRequest({ action = "open" })
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("MASTERCRAFTING STATION")
    frame:SetSize(math.min(700, ScrW() - 40), math.min(480, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if UI.Frame == frame then UI.Frame = nil end
    end
    self.Frame = frame
    self.Message = nil
    self.PromptedQuote = nil
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(8, 8, 8, 8)
    body.Paint = nil
    frame.Body = body
    self:Rebuild()
    self:SendRequest({ action = "open" })
end
