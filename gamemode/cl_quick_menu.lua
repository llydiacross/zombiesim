// Player-facing Tab radial menu. It is intentionally independent of preview tools.
ZM_QuickMenu = ZM_QuickMenu or {}
local QuickMenu = ZM_QuickMenu

local entries = {
    { id = "inventory", label = "INVENTORY", startAngle = -150, endAngle = -30, centerAngle = -90 },
    { id = "scoreboard", label = "SCOREBOARD", startAngle = -30, endAngle = 90, centerAngle = 30 },
    { id = "options", label = "OPTIONS", startAngle = 90, endAngle = 210, centerAngle = 150 }
}

local function normalizeAngle(angle)
    while angle <= -180 do angle = angle + 360 end
    while angle > 180 do angle = angle - 360 end
    return angle
end

local function selectedEntry(cursorX, cursorY, width, height)
    local deltaX = cursorX - width * 0.5
    local deltaY = cursorY - height * 0.5
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    if distance < math.min(width, height) * 0.11 then
        return nil
    end
    local angle = math.deg(math.atan2(deltaY, deltaX))
    local closestEntry
    local closestDistance = 181
    for _, entry in ipairs(entries) do
        local angleDistance = math.abs(normalizeAngle(angle - entry.centerAngle))
        if angleDistance < closestDistance then
            closestEntry = entry
            closestDistance = angleDistance
        end
    end
    return closestDistance <= 60 and closestEntry or nil
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
    end
    owner.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end
    return frame
end

ZM_Inventory = ZM_Inventory or {}
ZM_Scoreboard = ZM_Scoreboard or {}
ZM_Options = ZM_Options or {}

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

function ZM_Scoreboard:Open()
    local frame = openFrame(self, "SCOREBOARD", 720, 500)
    if frame.ScoreboardList then return end
    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:DockMargin(10, 34, 10, 10)
    list:AddColumn("Player")
    list:AddColumn("Ping")
    list:AddColumn("Cell")
    frame.ScoreboardList = list
    frame.NextRefresh = 0
    frame.Think = function(currentFrame)
        if CurTime() < currentFrame.NextRefresh then return end
        currentFrame.NextRefresh = CurTime() + 1
        list:Clear()
        for _, playerEntity in ipairs(player.GetAll()) do
            if IsValid(playerEntity) then
                list:AddLine(playerEntity:Nick(), playerEntity:Ping(), string.format("%d, %d", playerEntity:GetNWInt("CellX", 0), playerEntity:GetNWInt("CellY", 0)))
            end
        end
    end
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

function QuickMenu:OpenDestination(entryId)
    if entryId == "inventory" then
        ZM_Inventory:Open()
    elseif entryId == "scoreboard" then
        ZM_Scoreboard:Open()
    elseif entryId == "options" then
        ZM_Options:Open()
    end
end

function QuickMenu:Close(activate)
    local panel = self.Panel
    self.Panel = nil
    self.IsHoldingScoreboard = false
    self.TabReleasedAt = nil
    gui.EnableScreenClicker(false)
    if not IsValid(panel) then
        return
    end
    local entry = panel.SelectedEntry
    panel:Remove()
    if activate and entry then
        self:OpenDestination(entry.id)
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
        currentPanel.SelectedEntry = selectedEntry(cursorX, cursorY, currentPanel:GetWide(), currentPanel:GetTall())
    end
    panel.Paint = function(currentPanel, width, height)
        local palette = ZM_DermaSkin.Palette
        local centerX, centerY = width * 0.5, height * 0.5
        local scale = math.Clamp(tonumber(cookie.GetString("zombiesim_quick_menu_scale", "1")) or 1, 0.7, 1.4)
        local outerRadius = math.min(width, height) * 0.22 * scale
        local innerRadius = outerRadius * 0.36
        surface.SetDrawColor(0, 0, 0, 105)
        surface.DrawRect(0, 0, width, height)
        for _, entry in ipairs(entries) do
            local active = currentPanel.SelectedEntry == entry
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
        draw.SimpleText("Z", "ZM_DermaFrameTitle", centerX, centerY, palette.redBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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

hook.Add("PlayerBindPress", "ZM.QuickMenu.SuppressNativeScoreboard", function(_, bind)
    local command = string.lower(bind or "")
    if command == "+showscores" or command == "-showscores" then
        return true
    end
end)

hook.Add("Think", "ZM.QuickMenu.TabController", function()
    local tabDown = input.IsKeyDown(KEY_TAB)
    if tabDown == QuickMenu.TabWasDown then
        return
    end
    QuickMenu.TabWasDown = tabDown
    if tabDown then
        QuickMenu:Open(true)
    elseif QuickMenu.IsHoldingScoreboard then
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