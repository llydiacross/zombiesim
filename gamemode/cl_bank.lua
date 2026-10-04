ZM_BankUI = ZM_BankUI or {}
local UI = ZM_BankUI

local gold = Color(222, 184, 84)
local green = Color(110, 210, 130)
local red = Color(235, 95, 95)

local function newRequestId()
    return string.format("b%08x%06x", os.time(), math.random(0, 0xFFFFFF))
end

local function makeLabel(parent, text, font, color)
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:SetFont(font or "ZM_CraftingBody")
    label:SetTextColor(color or ZM_DermaSkin.Palette.text)
    label:SetText(text)
    label:SetTall(22)
    label:DockMargin(0, 0, 0, 5)
    return label
end

function UI:Send(action, amount)
    if not self.TerminalIndex then return end
    net.Start("ZM.Bank.Request")
        net.WriteUInt(self.TerminalIndex, 16)
        net.WriteString(util.TableToJSON({
            action = action,
            amount = amount,
            requestId = action ~= "refresh" and newRequestId() or nil
        }, false) or "{}")
    net.SendToServer()
end

local function transactionText(entry)
    local direction = entry.kind == "deposit" and "DEPOSIT  " or "WITHDRAWAL  "
    local amount = "$" .. string.Comma(tonumber(entry.amount) or 0)
    local balanceLabel = "  |  balance "
    local balance = "$" .. string.Comma(tonumber(entry.balance) or 0)
    local time = "  |  " .. os.date("%b %d %H:%M", tonumber(entry.createdAt) or 0)
    return {
        { text = direction, color = entry.kind == "deposit" and green or gold },
        { text = amount, color = gold },
        { text = balanceLabel, color = ZM_DermaSkin.Palette.muted },
        { text = balance, color = gold },
        { text = time, color = ZM_DermaSkin.Palette.muted }
    }
end

function UI:Render(state)
    if not IsValid(self.Frame) then return end
    self.State = state
    if IsValid(self.Content) then self.Content:Remove() end

    local content = vgui.Create("DPanel", self.Frame)
    content:Dock(FILL)
    content:DockMargin(14, 10, 14, 14)
    content.Paint = nil
    self.Content = content

    if state.available ~= true then
        makeLabel(content, state.reason or "Banking is unavailable.", "ZM_CraftingBody", red)
        return
    end

    ZM_DermaSkin.CurrencyLine(content, "BANK BALANCE", "$" .. string.Comma(tonumber(state.balance) or 0), "ZM_CraftingHeading")
    ZM_DermaSkin.CurrencyLine(content, "Cash bundles available", "$" .. string.Comma(tonumber(state.depositable) or 0), "ZM_CraftingSmall", ZM_DermaSkin.Palette.muted)

    local amountRow = vgui.Create("DPanel", content)
    amountRow:Dock(TOP)
    amountRow:SetTall(42)
    amountRow:DockMargin(0, 8, 0, 8)
    amountRow.Paint = nil

    local amount = vgui.Create("DNumberWang", amountRow)
    amount:Dock(LEFT)
    amount:SetWide(110)
    amount:SetDecimals(0)
    amount:SetMin(1)
    amount:SetMax(math.max(1, math.min(tonumber(state.maximumTransfer) or 1000000, tonumber(state.depositable) or 1)))
    amount:SetValue(math.min(100, tonumber(state.depositable) or 1))
    self.Amount = amount

    local function setMode(nextMode)
        local maximum = nextMode == "deposit" and tonumber(state.depositable) or tonumber(state.balance)
        amount:SetMax(math.max(1, math.min(tonumber(state.maximumTransfer) or 1000000, maximum or 1)))
        amount:SetValue(math.min(tonumber(amount:GetValue()) or 1, math.max(1, maximum or 1)))
    end

    for _, preset in ipairs(state.presets or {}) do
        local button = vgui.Create("DButton", amountRow)
        button:Dock(LEFT)
        button:SetWide(68)
        button:DockMargin(5, 4, 0, 4)
        button:SetText("$" .. string.Comma(preset))
        button:SetTextColor(gold)
        button.DoClick = function()
            amount:SetValue(math.min(preset, amount:GetMax()))
        end
    end

    local actions = vgui.Create("DPanel", content)
    actions:Dock(TOP)
    actions:SetTall(38)
    actions:DockMargin(0, 0, 0, 8)
    actions.Paint = nil
    local depositButton = vgui.Create("DButton", actions)
    depositButton:Dock(LEFT)
    depositButton:SetWide(140)
    depositButton:SetText("DEPOSIT")
    depositButton.DoClick = function()
        setMode("deposit")
        UI:Send("deposit", math.floor(tonumber(amount:GetValue()) or 0))
    end
    local withdrawButton = vgui.Create("DButton", actions)
    withdrawButton:Dock(LEFT)
    withdrawButton:SetWide(140)
    withdrawButton:DockMargin(6, 0, 0, 0)
    withdrawButton:SetText("WITHDRAW")
    withdrawButton.DoClick = function()
        setMode("withdraw")
        UI:Send("withdraw", math.floor(tonumber(amount:GetValue()) or 0))
    end

    if state.message then
        makeLabel(content, state.message, "ZM_CraftingSmall", state.ok and green or red)
    end

    makeLabel(content, "RECENT TRANSACTIONS", "ZM_CraftingHeading", ZM_DermaSkin.Palette.text)
    local history = vgui.Create("DScrollPanel", content)
    history:Dock(FILL)
    if #(state.history or {}) == 0 then
        makeLabel(history, "No bank transactions yet.", "ZM_CraftingSmall", ZM_DermaSkin.Palette.muted)
    else
        for _, entry in ipairs(state.history) do
            local row = vgui.Create("DPanel", history)
            row:Dock(TOP)
            row:SetTall(22)
            row:DockMargin(0, 0, 0, 5)
            local segments = transactionText(entry)
            row.Paint = function(_, _, height)
                ZM_DermaSkin.DrawTextSegments(0, height * 0.5, "ZM_CraftingSmall", segments)
            end
        end
    end
end

function UI:Open(terminalIndex)
    self.TerminalIndex = terminalIndex or self.TerminalIndex
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:Send("refresh")
        return
    end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("BANK")
    frame:SetSize(math.min(570, ScrW() - 40), math.min(480, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if UI.Frame == frame then UI.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end
    self:Send("refresh")
end

net.Receive("ZM.Bank.Open", function()
    UI:Open(net.ReadUInt(16))
end)

net.Receive("ZM.Bank.State", function()
    local state = util.JSONToTable(net.ReadString())
    if type(state) == "table" then UI:Render(state) end
end)
