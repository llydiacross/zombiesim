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
    elseif not ZM_Preview or not ZM_Preview:IsActive() then
        table.insert(active, { id = "map", label = "MAP" })
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
ZM_Options.WalkerSettings = ZM_Options.WalkerSettings or {
    activeCap = 64,
    populationPerZombie = 4,
    canEdit = false,
    loaded = false
}

function ZM_Options:RequestWalkerSettings()
    net.Start("ZM.RequestWalkerMaterializationSettings")
    net.SendToServer()
end

function ZM_Options:SetWalkerSettings(activeCap, populationPerZombie)
    local settings = self.WalkerSettings or {}
    if not settings.canEdit then
        return
    end
    net.Start("ZM.SetWalkerMaterializationSettings")
        net.WriteUInt(math.Clamp(math.floor(activeCap), 1, 256), 9)
        net.WriteUInt(math.Clamp(math.floor(populationPerZombie), 1, 65535), 16)
    net.SendToServer()
end

function ZM_PreviewCheats:Request(action)
    if not ZM_Preview or not ZM_Preview:HasClientCapability(ZM_Preview.Capabilities.operator) then
        return
    end

    net.Start("ZM.RequestPreviewCheat")
        net.WriteString(action)
    net.SendToServer()
end

function ZM_Options:BuildPanel(panel)
    local labels = vgui.Create("DCheckBoxLabel", panel)
    labels:Dock(TOP)
    labels:DockMargin(4, 4, 4, 8)
    labels:SetText("Show labels in radial menu")
    labels:SetTextColor(ZM_DermaSkin.Palette.text)
    labels:SetValue(cookie.GetString("zombiesim_quick_menu_labels", "1") == "1" and 1 or 0)
    labels.OnChange = function(_, enabled)
        cookie.Set("zombiesim_quick_menu_labels", enabled and "1" or "0")
    end
    local function setSliderLabel(slider, text)
        ZM_DermaSkin.LabelSlider(slider, text)
    end
    local scale = vgui.Create("DNumSlider", panel)
    scale:Dock(TOP)
    scale:DockMargin(4, 0, 4, 4)
    setSliderLabel(scale, "Radial menu size")
    scale:SetMin(0.7)
    scale:SetMax(1.4)
    scale:SetDecimals(1)
    scale:SetValue(tonumber(cookie.GetString("zombiesim_quick_menu_scale", "1")) or 1)
    scale.OnValueChanged = function(_, value)
        cookie.Set("zombiesim_quick_menu_scale", tostring(math.Round(value, 1)))
    end

    for _, setting in ipairs({
        { label = "Compass height", convar = "zombiesim_compass_height", minimum = 0.55, maximum = 1.5 },
        { label = "Minimap size", convar = "zombiesim_minimap_size", minimum = 0.7, maximum = 1.75 },
        {
            label = "Rain density",
            convar = "zombiesim_atmosphere_rain_density",
            minimum = 0.5,
            maximum = 2,
            decimals = 1,
            tooltip = "Adjusts the density of locally rendered rain."
        },
        {
            label = "Puddle opacity",
            convar = "zombiesim_atmosphere_puddle_opacity",
            minimum = 0.05,
            maximum = 0.45,
            decimals = 2,
            tooltip = "Lower values let more of the ground show through."
        },
        {
            label = "Puddle amount",
            convar = "zombiesim_atmosphere_puddle_amount",
            minimum = 0.5,
            maximum = 3,
            decimals = 1,
            tooltip = "Scales how many puddles form in the rain. Higher values cost more frame time."
        },
        {
            label = "Debris amount",
            convar = "zombiesim_ambient_debris_amount",
            minimum = 0,
            maximum = 3,
            decimals = 1,
            tooltip = "Scales ambient paper, bottles, litter and tumbleweeds. 0 disables them; higher values cost more frame time."
        },
        {
            label = "Gore (0 off, 1 reduced, 2 full)",
            convar = "zombiesim_gore_quality",
            minimum = 0,
            maximum = 2,
            decimals = 0,
            tooltip = "Controls blood, severed limbs and stump effects. Crawlers still lose their legs when gore is off."
        }
    }) do
        local slider = vgui.Create("DNumSlider", panel)
        slider:Dock(TOP)
        slider:DockMargin(4, 0, 4, 4)
        setSliderLabel(slider, setting.label)
        slider:SetMin(setting.minimum)
        slider:SetMax(setting.maximum)
        slider:SetDecimals(setting.decimals or 2)
        if setting.tooltip then slider:SetTooltip(setting.tooltip) end
        slider:SetConVar(setting.convar)
    end

    local filmGrain = vgui.Create("DCheckBoxLabel", panel)
    filmGrain:Dock(TOP)
    filmGrain:DockMargin(4, 4, 4, 8)
    filmGrain:SetText("Subtle film grain")
    filmGrain:SetTextColor(ZM_DermaSkin.Palette.text)
    filmGrain:SetConVar("zombiesim_atmosphere_grain")

    if ZM_GetMouseSensitivity then
        local minimumSensitivity, maximumSensitivity = ZM_GetMouseSensitivityRange()
        local sensitivity = vgui.Create("DNumSlider", panel)
        sensitivity:Dock(TOP)
        sensitivity:DockMargin(4, 0, 4, 4)
        setSliderLabel(sensitivity, "Mouse sensitivity")
        sensitivity:SetMin(minimumSensitivity)
        sensitivity:SetMax(maximumSensitivity)
        sensitivity:SetDecimals(2)
        sensitivity:SetValue(ZM_GetMouseSensitivity())
        sensitivity.OnValueChanged = function(_, value)
            ZM_SetMouseSensitivity(value)
        end
    end

    if ZM_GetInvertMouseY then
        for _, option in ipairs({
            { mode = "orbit", label = "Invert mouse Y when orbiting" },
            { mode = "shoulder", label = "Invert mouse Y in shoulder view" }
        }) do
            local invert = vgui.Create("DCheckBoxLabel", panel)
            invert:Dock(TOP)
            invert:DockMargin(4, 4, 4, 4)
            invert:SetText(option.label)
            invert:SetTextColor(ZM_DermaSkin.Palette.text)
            invert:SetValue(ZM_GetInvertMouseY(option.mode) and 1 or 0)
            invert.OnChange = function(_, enabled)
                ZM_SetInvertMouseY(option.mode, enabled)
            end
        end
    end

    if GetConVar("zombiesim_globe_quality") then
        local globeQuality = vgui.Create("DCheckBoxLabel", panel)
        globeQuality:Dock(TOP)
        globeQuality:DockMargin(4, 4, 4, 4)
        globeQuality:SetText("High-detail menu globe")
        globeQuality:SetTextColor(ZM_DermaSkin.Palette.text)
        globeQuality:SetConVar("zombiesim_globe_quality")
    end

    local walkerHeading = vgui.Create("DLabel", panel)
    walkerHeading:Dock(TOP)
    walkerHeading:DockMargin(4, 14, 4, 4)
    walkerHeading:SetTall(20)
    walkerHeading:SetFont("DermaDefaultBold")
    walkerHeading:SetText("ZOMBIE SETTINGS")
    walkerHeading:SetTextColor(ZM_DermaSkin.Palette.text)

    local activeCap = vgui.Create("DNumSlider", panel)
    activeCap:Dock(TOP)
    activeCap:DockMargin(4, 0, 4, 4)
    setSliderLabel(activeCap, "Active zombie cap")
    activeCap:SetMin(1)
    activeCap:SetMax(256)
    activeCap:SetDecimals(0)

    local populationPerZombie = vgui.Create("DNumSlider", panel)
    populationPerZombie:Dock(TOP)
    populationPerZombie:DockMargin(4, 0, 4, 4)
    setSliderLabel(populationPerZombie, "Virtual walkers per zombie")
    populationPerZombie:SetMin(1)
    populationPerZombie:SetMax(10)
    populationPerZombie:SetDecimals(0)

    local updatingWalkerSettings = false
    local function submitWalkerSettings()
        if updatingWalkerSettings then
            return
        end
        self:SetWalkerSettings(activeCap:GetValue(), populationPerZombie:GetValue())
    end
    activeCap.OnValueChanged = submitWalkerSettings
    populationPerZombie.OnValueChanged = submitWalkerSettings

    local displayedActiveCap
    local displayedPopulationPerZombie
    panel.Think = function()
        local settings = self.WalkerSettings or {}
        activeCap:SetEnabled(settings.canEdit == true)
        populationPerZombie:SetEnabled(settings.canEdit == true)
        if not settings.loaded then
            return
        end
        if displayedActiveCap ~= settings.activeCap or displayedPopulationPerZombie ~= settings.populationPerZombie then
            updatingWalkerSettings = true
            activeCap:SetValue(settings.activeCap)
            populationPerZombie:SetValue(settings.populationPerZombie)
            updatingWalkerSettings = false
            displayedActiveCap = settings.activeCap
            displayedPopulationPerZombie = settings.populationPerZombie
        end
    end
    // Size to the docked children so new options never fall off the bottom of the scroll area.
    local contentHeight = 8
    for _, child in ipairs(panel:GetChildren()) do
        local _, marginTop, _, marginBottom = child:GetDockMargin()
        contentHeight = contentHeight + child:GetTall() + marginTop + marginBottom
    end
    panel:SetTall(contentHeight)
    self:RequestWalkerSettings()
end

function ZM_Options:Open()
    local frame = openFrame(self, "OPTIONS", 480, 550)
    if frame.OptionsBuilt then return end
    frame.OptionsBuilt = true
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(12, 36, 12, 12)
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(640)
    panel.Paint = function() end
    self:BuildPanel(panel)
end

// Cheat toggles mirror Preview.CheatToggles on the server; the status message reads them in this order.
local previewCheatToggles = {
    { key = "god", action = "toggle_god", label = "GOD MODE" },
    { key = "noclip", action = "toggle_noclip", label = "NOCLIP" },
    { key = "notarget", action = "toggle_notarget", label = "ZOMBIES IGNORE ME" },
    { key = "infiniteAmmo", action = "toggle_infinite_ammo", label = "INFINITE AMMO" },
    { key = "survivalLock", action = "toggle_survival_lock", label = "SURVIVAL LOCK" }
}

local function addCheatSection(parent, title)
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:DockMargin(0, 8, 0, 4)
    label:SetTall(18)
    label:SetFont("DermaDefaultBold")
    label:SetTextColor(ZM_DermaSkin.Palette.muted)
    label:SetText(title)
end

// Lays out buttons in equal-width columns, wrapping into as many rows as needed.
local function addCheatButtonGrid(parent, columns, entries, onCreate)
    local rowHeight, gap = 38, 6
    local rows = math.ceil(#entries / columns)
    local grid = vgui.Create("DPanel", parent)
    grid:Dock(TOP)
    grid:SetTall(rows * rowHeight + (rows - 1) * gap)
    grid.Paint = function() end
    local buttons = {}
    for index, entry in ipairs(entries) do
        local button = vgui.Create("DButton", grid)
        button:SetText(entry.label)
        onCreate(button, entry)
        buttons[index] = button
    end
    grid.PerformLayout = function(_, width)
        local buttonWidth = math.floor((width - (columns - 1) * gap) / columns)
        for index, button in ipairs(buttons) do
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            button:SetPos(column * (buttonWidth + gap), row * (rowHeight + gap))
            button:SetSize(buttonWidth, rowHeight)
        end
    end
    return buttons
end

function ZM_PreviewCheats:Open()
    local frame = openFrame(self, "CHEATS", 500, 470)
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

    addCheatSection(panel, "TOGGLES  (kept across levels)")
    local toggleButtons = addCheatButtonGrid(panel, 2, previewCheatToggles, function(button, entry)
        button.DoClick = function() self:Request(entry.action) end
    end)

    addCheatSection(panel, "ACTIONS")
    addCheatButtonGrid(panel, 3, {
        { action = "refill", label = "RESTORE VITALS" },
        { action = "grant_level", label = "LEVEL UP" },
        { action = "kill_nearby", label = "KILL NEARBY ZOMBIES" }
    }, function(button, entry)
        button.DoClick = function() self:Request(entry.action) end
    end)

    addCheatSection(panel, "WEATHER")
    addCheatButtonGrid(panel, 3, {
        { action = "weather_clear", label = "CLEAR" },
        { action = "weather_rain", label = "RAIN" },
        { action = "weather_snow", label = "SNOW" }
    }, function(button, entry)
        button.DoClick = function() self:Request(entry.action) end
    end)

    frame.Think = function()
        local state = self.State or {}
        for index, entry in ipairs(previewCheatToggles) do
            toggleButtons[index]:SetText(entry.label .. (state[entry.key] and ": ON" or ": OFF"))
        end
        local playerEntity = LocalPlayer()
        local cellX = IsValid(playerEntity) and playerEntity:GetNWInt("CellX", 0) or 0
        local cellY = IsValid(playerEntity) and playerEntity:GetNWInt("CellY", 0) or 0
        status:SetText(string.format("CELL %d, %d%s", cellX, cellY, self.Message ~= "" and "  |  " .. self.Message or ""))
    end
end

net.Receive("ZM.PreviewCheatStatus", function()
    local accepted = net.ReadBool()
    local message = net.ReadString()
    local state = {}
    for _, entry in ipairs(previewCheatToggles) do
        state[entry.key] = net.ReadBool()
    end
    ZM_PreviewCheats.State = state
    ZM_PreviewCheats.Message = message
    if not accepted and message ~= "" then
        surface.PlaySound("buttons/button10.wav")
    end
end)

net.Receive("ZM.WalkerMaterializationSettings", function()
    ZM_Options.WalkerSettings = {
        activeCap = net.ReadUInt(9),
        populationPerZombie = net.ReadUInt(16),
        canEdit = net.ReadBool(),
        loaded = true
    }
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
    elseif entryId == "map" and ZM_WorldMap then
        ZM_WorldMap:Open()
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
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
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
