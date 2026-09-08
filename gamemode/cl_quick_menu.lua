// Player-facing Tab radial menu. It is intentionally independent of preview tools.
ZM_QuickMenu = ZM_QuickMenu or {}
local QuickMenu = ZM_QuickMenu
local tabHoldSeconds = 0.12
local tabReleaseGraceSeconds = 0.08

local baseEntries = {
    { id = "inventory", label = "INVENTORY" },
    { id = "scoreboard", label = "SCOREBOARD" },
    { id = "options", label = "OPTIONS" }
}

local function activeEntries()
    local active = {}
    for _, entry in ipairs(baseEntries) do
        table.insert(active, { id = entry.id, label = entry.label })
    end
    if ZM_Preview and ZM_Preview:HasClientCapability(ZM_Preview.Capabilities.operator) then
        table.insert(active, { id = "cheats", label = "CHEATS" })
    end

    local sliceAngle = 360 / #active
    for index, entry in ipairs(active) do
        entry.centerAngle = -90 + (index - 1) * sliceAngle
        entry.startAngle = entry.centerAngle - sliceAngle * 0.5
        entry.endAngle = entry.centerAngle + sliceAngle * 0.5
    end
    return active
end

local function normalizeAngle(angle)
    while angle <= -180 do angle = angle + 360 end
    while angle > 180 do angle = angle - 360 end
    return angle
end

local function selectedEntry(cursorX, cursorY, width, height, menuEntries)
    local deltaX = cursorX - width * 0.5
    local deltaY = cursorY - height * 0.5
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    if distance < math.min(width, height) * 0.11 then
        return nil
    end
    local angle = math.deg(math.atan2(deltaY, deltaX))
    local closestEntry
    local closestDistance = 181
    for _, entry in ipairs(menuEntries) do
        local angleDistance = math.abs(normalizeAngle(angle - entry.centerAngle))
        if angleDistance < closestDistance then
            closestEntry = entry
            closestDistance = angleDistance
        end
    end
    return closestEntry
end

local function openFrame(owner, title, width, height)
    if IsValid(owner.Frame) then
        owner.Frame:MakePopup()
        return owner.Frame
    end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle(title)
    frame:SetSize(math.min(width, ScrW() - 40), math.min(height, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if owner.Frame == frame then owner.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    owner.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end
    return frame
end

ZM_Inventory = ZM_Inventory or {}
ZM_Options = ZM_Options or {}
ZM_PreviewCheats = ZM_PreviewCheats or { State = { god = false, noclip = false }, Message = "" }

function ZM_PreviewCheats:Request(action)
    if not ZM_Preview or not ZM_Preview:HasClientCapability(ZM_Preview.Capabilities.operator) then
        return
    end

    net.Start("ZM.RequestPreviewCheat")
        net.WriteString(action)
    net.SendToServer()
end

function ZM_Inventory:Open()
    local frame = openFrame(self, "INVENTORY", 560, 440)
    if frame.InventoryBuilt then return end
    frame.InventoryBuilt = true
    local label = vgui.Create("DLabel", frame)
    label:Dock(FILL)
    label:DockMargin(16, 34, 16, 16)
    label:SetFont("DermaDefaultBold")
    label:SetTextColor(ZM_DermaSkin.Palette.muted)
    label:SetContentAlignment(5)
    label:SetText("No inventory data is available in this build.")
end

function ZM_Options:Open()
    local frame = openFrame(self, "OPTIONS", 480, 310)
    if frame.OptionsBuilt then return end
    frame.OptionsBuilt = true
    local panel = vgui.Create("DPanel", frame)
    panel:Dock(FILL)
    panel:DockMargin(12, 36, 12, 12)
    panel.Paint = function() end
    local labels = vgui.Create("DCheckBoxLabel", panel)
    labels:Dock(TOP)
    labels:DockMargin(4, 4, 4, 8)
    labels:SetText("Show labels in radial menu")
    labels:SetTextColor(ZM_DermaSkin.Palette.text)
    labels:SetValue(cookie.GetString("zombiesim_quick_menu_labels", "1") == "1" and 1 or 0)
    labels.OnChange = function(_, enabled)
        cookie.Set("zombiesim_quick_menu_labels", enabled and "1" or "0")
    end
    local scale = vgui.Create("DNumSlider", panel)
    scale:Dock(TOP)
    scale:DockMargin(4, 0, 4, 4)
    scale:SetText("Radial menu size")
    scale:SetMin(0.7)
    scale:SetMax(1.4)
    scale:SetDecimals(1)
    scale:SetValue(tonumber(cookie.GetString("zombiesim_quick_menu_scale", "1")) or 1)
    scale.OnValueChanged = function(_, value)
        cookie.Set("zombiesim_quick_menu_scale", tostring(math.Round(value, 1)))
    end
end

function ZM_PreviewCheats:Open()
    local frame = openFrame(self, "CHEATS", 470, 430)
    if frame.CheatsBuilt then return end
    frame.CheatsBuilt = true

    local panel = vgui.Create("DPanel", frame)
    panel:Dock(FILL)
    panel:DockMargin(12, 36, 12, 12)
    panel.Paint = function() end

    local status = vgui.Create("DLabel", panel)
    status:Dock(TOP)
    status:SetTall(28)
    status:SetFont("DermaDefaultBold")
    status:SetTextColor(ZM_DermaSkin.Palette.muted)
    status:SetContentAlignment(5)

    local god = vgui.Create("DButton", panel)
    god:Dock(TOP)
    god:DockMargin(0, 4, 0, 6)
    god:SetTall(42)
    god.DoClick = function() self:Request("toggle_god") end

    local noclip = vgui.Create("DButton", panel)
    noclip:Dock(TOP)
    noclip:DockMargin(0, 0, 0, 6)
    noclip:SetTall(42)
    noclip.DoClick = function() self:Request("toggle_noclip") end

    local refill = vgui.Create("DButton", panel)
    refill:Dock(TOP)
    refill:DockMargin(0, 0, 0, 12)
    refill:SetTall(36)
    refill:SetText("RESTORE VITALS")
    refill.DoClick = function() self:Request("refill") end

    local directions = vgui.Create("DPanel", panel)
    directions:Dock(FILL)
    directions.Paint = function() end
    local directionButtons = {}
    for _, direction in ipairs({
        { id = "north", label = "NORTH" },
        { id = "west", label = "WEST" },
        { id = "east", label = "EAST" },
        { id = "south", label = "SOUTH" }
    }) do
        local button = vgui.Create("DButton", directions)
        button:SetText(direction.label)
        button.DoClick = function() self:Request("move_" .. direction.id) end
        directionButtons[direction.id] = button
    end
    directions.PerformLayout = function(currentPanel, width)
        local buttonWidth = math.min(130, math.max(96, math.floor(width * 0.32)))
        local buttonHeight = 34
        local centerX = math.floor((width - buttonWidth) * 0.5)
        directionButtons.north:SetPos(centerX, 0)
        directionButtons.north:SetSize(buttonWidth, buttonHeight)
        directionButtons.west:SetPos(math.max(0, centerX - buttonWidth - 12), buttonHeight + 12)
        directionButtons.west:SetSize(buttonWidth, buttonHeight)
        directionButtons.east:SetPos(math.min(width - buttonWidth, centerX + buttonWidth + 12), buttonHeight + 12)
        directionButtons.east:SetSize(buttonWidth, buttonHeight)
        directionButtons.south:SetPos(centerX, (buttonHeight + 12) * 2)
        directionButtons.south:SetSize(buttonWidth, buttonHeight)
    end

    frame.Think = function()
        local state = self.State or {}
        god:SetText(state.god and "GOD MODE: ON" or "GOD MODE: OFF")
        noclip:SetText(state.noclip and "NOCLIP: ON" or "NOCLIP: OFF")
        local playerEntity = LocalPlayer()
        local cellX = IsValid(playerEntity) and playerEntity:GetNWInt("CellX", 0) or 0
        local cellY = IsValid(playerEntity) and playerEntity:GetNWInt("CellY", 0) or 0
        status:SetText(string.format("CELL %d, %d%s", cellX, cellY, self.Message ~= "" and "  |  " .. self.Message or ""))
    end
end

net.Receive("ZM.PreviewCheatStatus", function()
    local accepted = net.ReadBool()
    local message = net.ReadString()
    ZM_PreviewCheats.State = { god = net.ReadBool(), noclip = net.ReadBool() }
    ZM_PreviewCheats.Message = message
    if not accepted and message ~= "" then
        surface.PlaySound("buttons/button10.wav")
    end
end)

function QuickMenu:OpenDestination(entryId)
    if entryId == "inventory" then
        ZM_Inventory:Open()
    elseif entryId == "scoreboard" then
        ZM_Scoreboard:Open()
    elseif entryId == "options" then
        ZM_Options:Open()
    elseif entryId == "cheats" then
        ZM_PreviewCheats:Open()
    end
end

function QuickMenu:Close(activate)
    local panel = self.Panel
    self.Panel = nil
    self.IsHoldingScoreboard = false
    self.TabHeldAt = nil
    self.TabHoldTriggered = false
    self.TabReleasedAt = nil
    gui.EnableScreenClicker(false)
    if not IsValid(panel) then
        return
    end
    local entryId = panel.SelectedEntryId
    panel:Remove()
    if activate and entryId then
        self:OpenDestination(entryId)
    end
end

function QuickMenu:Open(heldByScoreboard)
    if self.IsHoldingScoreboard or IsValid(self.Panel) then
        return
    end
    if vgui.GetKeyboardFocus() then
        return
    end

    self.IsHoldingScoreboard = heldByScoreboard == true
    self.TabReleasedAt = nil
    local panel = vgui.Create("DPanel")
    panel:SetSize(ScrW(), ScrH())
    panel:SetPos(0, 0)
    panel:SetMouseInputEnabled(true)
    panel:SetKeyboardInputEnabled(false)
    panel.Think = function(currentPanel)
        local cursorX, cursorY = gui.MousePos()
        local entry = selectedEntry(cursorX, cursorY, currentPanel:GetWide(), currentPanel:GetTall(), activeEntries())
        currentPanel.SelectedEntryId = entry and entry.id or nil
    end
    panel.Paint = function(currentPanel, width, height)
        local palette = ZM_DermaSkin.Palette
        local centerX, centerY = width * 0.5, height * 0.5
        local scale = math.Clamp(tonumber(cookie.GetString("zombiesim_quick_menu_scale", "1")) or 1, 0.7, 1.4)
        local outerRadius = math.min(width, height) * 0.22 * scale
        local innerRadius = outerRadius * 0.36
        surface.SetDrawColor(0, 0, 0, 105)
        surface.DrawRect(0, 0, width, height)
        for _, entry in ipairs(activeEntries()) do
            local active = currentPanel.SelectedEntryId == entry.id
            surface.SetDrawColor(active and palette.red.r or palette.panel.r, active and palette.red.g or palette.panel.g, active and palette.red.b or palette.panel.b, 240)
            local points = {}
            for step = 0, 16 do
                local angle = math.rad(entry.startAngle + (entry.endAngle - entry.startAngle) * step / 16)
                table.insert(points, { x = centerX + math.cos(angle) * outerRadius, y = centerY + math.sin(angle) * outerRadius })
            end
            table.insert(points, { x = centerX, y = centerY })
            draw.NoTexture()
            surface.DrawPoly(points)
            local labelAngle = math.rad((entry.startAngle + entry.endAngle) * 0.5)
            if cookie.GetString("zombiesim_quick_menu_labels", "1") == "1" then
                draw.SimpleText(entry.label, "ZM_DermaButton", centerX + math.cos(labelAngle) * (innerRadius + outerRadius) * 0.5, centerY + math.sin(labelAngle) * (innerRadius + outerRadius) * 0.5, palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        surface.SetDrawColor(palette.black.r, palette.black.g, palette.black.b, 255)
        surface.DrawCircle(centerX, centerY, innerRadius, palette.black)
        draw.SimpleText("?", "ZM_DermaFrameTitle", centerX, centerY, palette.redBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    panel.OnMousePressed = function(_, mouseCode)
        if mouseCode == MOUSE_RIGHT then
            self:Close(false)
        end
    end
    self.Panel = panel
    gui.EnableScreenClicker(true)
    input.SetCursorPos(math.floor(ScrW() * 0.5), math.floor(ScrH() * 0.5))
end

function QuickMenu:BeginTabHold()
    if self.TabWasDown then
        return
    end
    self.TabWasDown = true
    self.TabHeldAt = RealTime()
    self.TabHoldTriggered = false
    self.TabReleasedAt = nil
end

function QuickMenu:EndTabHold()
    if not self.TabWasDown then
        return
    end
    self.TabWasDown = false
    self.TabHoldTriggered = false
    if self.IsHoldingScoreboard then
        self.TabReleasedAt = RealTime()
    else
        self.TabHeldAt = nil
    end
end

hook.Add("PlayerBindPress", "ZM.QuickMenu.ControlScoreboardBind", function(_, bind, pressed)
    local command = string.lower(bind or "")
    if command == "+showscores" then
        if pressed then
            QuickMenu:BeginTabHold()
        else
            QuickMenu:EndTabHold()
        end
        return true
    end
    if command == "-showscores" then
        QuickMenu:EndTabHold()
        return true
    end
end)

hook.Add("Think", "ZM.QuickMenu.TabController", function()
    local now = RealTime()
    if QuickMenu.TabWasDown and not QuickMenu.TabHoldTriggered and now - QuickMenu.TabHeldAt >= tabHoldSeconds then
        QuickMenu.TabHoldTriggered = true
        QuickMenu:Open(true)
    end
    if QuickMenu.IsHoldingScoreboard and QuickMenu.TabReleasedAt and now - QuickMenu.TabReleasedAt >= tabReleaseGraceSeconds then
        QuickMenu:Close(true)
    end
end)

hook.Add("PlayerDeath", "ZM.QuickMenu.CloseOnDeath", function(playerEntity)
    if playerEntity == LocalPlayer() then
        QuickMenu:Close(false)
    end
end)

concommand.Add("zombiesim_quick_menu", function()
    if IsValid(QuickMenu.Panel) then
        QuickMenu:Close(false)
    else
        QuickMenu:Open(false)
    end
end)
