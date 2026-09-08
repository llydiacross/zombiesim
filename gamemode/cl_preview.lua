// Client preview capability state and exclusive-window lifecycle management.
local Preview = ZM_Preview

ZM_UI = ZM_UI or {}
local UI = ZM_UI
UI.TransientPanels = UI.TransientPanels or {}

function UI:RegisterTransient(panel)
    if not IsValid(panel) then
        return panel
    end

    self.TransientPanels[panel] = true
    return panel
end

function UI:CloseTransient(exceptPanel)
    for panel in pairs(self.TransientPanels) do
        if panel ~= exceptPanel and IsValid(panel) then
            panel:Remove()
        end
    end
    if not IsValid(exceptPanel) then
        gui.EnableScreenClicker(false)
    end
end

function UI:OpenExclusive(panel)
    self:CloseTransient(panel)
    self:RegisterTransient(panel)
    gui.EnableScreenClicker(true)
    return panel
end

net.Receive("ZM.PreviewCapabilities", function()
    Preview:SetClientCapabilities(net.ReadUInt(3))
    Preview.ServerProfile = net.ReadString()
end)

Preview.TeleportStatus = Preview.TeleportStatus or ""

net.Receive("ZM.PreviewTeleportStatus", function()
    local requestId = net.ReadUInt(16)
    local accepted = net.ReadBool()
    local message = net.ReadString()
    local cellId = net.ReadUInt(16)
    local mapPath = net.ReadString()
    Preview.TeleportStatus = string.format("%s: %s", accepted and "READY" or "REJECTED", message)
    Preview.LastTeleportResult = {
        requestId = requestId,
        accepted = accepted,
        cellId = cellId,
        mapPath = mapPath
    }
end)

function Preview:RequestTeleport(cell)
    if not cell or type(cell.id) ~= "number" then
        self.TeleportStatus = "REJECTED: Select a valid cell"
        return
    end
    net.Start("ZM.RequestPreviewTeleport")
        net.WriteUInt(math.max(0, math.floor(cell.id)), 16)
    net.SendToServer()
end

function Preview:CreateMapPane(parent, mapContext)
    local palette = ZM_DermaSkin.Palette
    local pane = vgui.Create("DPanel", parent)
    pane:Dock(FILL)
    pane.Paint = function() end

    local status = vgui.Create("DLabel", pane)
    status:Dock(TOP)
    status:DockMargin(6, 5, 6, 4)
    status:SetFont("DermaDefaultBold")
    status:SetTextColor(palette.muted)
    status:SetWrap(true)
    status:SetTall(30)

    local selected = vgui.Create("DLabel", pane)
    selected:Dock(TOP)
    selected:DockMargin(6, 2, 6, 4)
    selected:SetFont("DermaDefault")
    selected:SetTextColor(palette.text)
    selected:SetWrap(true)
    selected:SetTall(34)

    local coordinateRow = vgui.Create("DPanel", pane)
    coordinateRow:Dock(TOP)
    coordinateRow:DockMargin(6, 0, 6, 5)
    coordinateRow:SetTall(22)
    coordinateRow.Paint = function() end
    local xInput = vgui.Create("DTextEntry", coordinateRow)
    xInput:Dock(LEFT)
    xInput:SetWide(70)
    xInput:SetPlaceholderText("World X")
    local yInput = vgui.Create("DTextEntry", coordinateRow)
    yInput:Dock(FILL)
    yInput:DockMargin(4, 0, 0, 0)
    yInput:SetPlaceholderText("World Y")

    local focusButton = vgui.Create("DButton", pane)
    focusButton:Dock(TOP)
    focusButton:DockMargin(6, 0, 6, 4)
    focusButton:SetTall(24)
    focusButton:SetText("Focus Selected")

    local teleportButton = vgui.Create("DButton", pane)
    teleportButton:Dock(TOP)
    teleportButton:DockMargin(6, 0, 6, 4)
    teleportButton:SetTall(26)
    teleportButton:SetText("Teleport")

    local consoleButton = vgui.Create("DButton", pane)
    consoleButton:Dock(TOP)
    consoleButton:DockMargin(6, 0, 6, 4)
    consoleButton:SetTall(24)
    consoleButton:SetText("Player Data")
    consoleButton.DoClick = function()
        if self.OpenDataConsole then
            self:OpenDataConsole()
        end
    end

    local function resolveCoordinateCell()
        local worldX = tonumber(xInput:GetValue())
        local worldY = tonumber(yInput:GetValue())
        if not worldX or not worldY or not ZM_World or not ZM_World:IsLoaded() then
            return nil
        end
        local gridX, gridY = ZM_World:GetGridCoordinates(math.floor(worldX), math.floor(worldY))
        return gridX and ZM_World:GetCell(gridX, gridY) or nil
    end

    focusButton.DoClick = function()
        local cell = resolveCoordinateCell() or mapContext.getSelectedCell()
        if cell then
            mapContext.selectCell(cell)
            mapContext.focusCell(cell)
        end
    end

    teleportButton.DoClick = function()
        local cell = resolveCoordinateCell() or mapContext.getSelectedCell()
        if not cell then
            self.TeleportStatus = "REJECTED: Select a valid cell"
            return
        end
        local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
        local mapPath = ZM_World:GetMapPath(cell) or "unresolved"
        Derma_Query(
            string.format("Load cell %d, %d on this one-player preview server?\n%s", worldX, worldY, mapPath),
            "Confirm Preview Teleport",
            "Teleport",
            function() self:RequestTeleport(cell) end,
            "Cancel"
        )
    end

    pane.Think = function()
        local hasDiagnostics = self:HasClientCapability(self.Capabilities.diagnostics)
        local hasOperator = self:HasClientCapability(self.Capabilities.operator)
        local hasDataAdmin = self:HasClientCapability(self.Capabilities.dataAdmin)
        local cell = resolveCoordinateCell() or mapContext.getSelectedCell()
        local worldX, worldY = cell and ZM_World:GetWorldCoordinates(cell) or nil, nil
        if cell then
            worldX, worldY = ZM_World:GetWorldCoordinates(cell)
            selected:SetText(string.format("CELL %d, %d\n%s", worldX, worldY, ZM_World:GetMapPath(cell) or "Map unavailable"))
        else
            selected:SetText("Select a cell or enter world coordinates")
        end
        status:SetText(self.TeleportStatus ~= "" and self.TeleportStatus or (hasDiagnostics and "READY" or "BLOCKED"))
        focusButton:SetEnabled(hasDiagnostics and cell ~= nil)
        teleportButton:SetEnabled(hasOperator and cell ~= nil)
        consoleButton:SetEnabled(hasDataAdmin and self.OpenDataConsole ~= nil)
    end

    return pane
end

Preview.DataHandlers = Preview.DataHandlers or {}

function Preview:RequestData(request)
    local json = util.TableToJSON(request, false) or "{}"
    net.Start("ZM.RequestPreviewData")
        net.WriteString(json)
    net.SendToServer()
end

net.Receive("ZM.PreviewDataResponse", function()
    local response = util.JSONToTable(net.ReadString()) or {}
    local handler = Preview.DataHandlers[response.action]
    if handler then
        handler(response)
    end
end)

local dataAttributeFields = {
    "Strength", "Agility", "Intelligence", "Endurance", "MachineGuns", "Shotguns", "Snipers",
    "WeaponCrafting", "ArmorCrafting", "Medicine", "Farming", "WeaponRepairing", "ArmorRepairing", "Mechanics"
}
local dataPlayerFields = {
    "XP", "Level", "MaxLevel", "Difficulty", "CellX", "CellY", "CurrentSafeZoneId", "SkillPoints",
    "Health", "Stamina", "Hunger", "Thirst"
}

function Preview:OpenDataConsole()
    if not self:HasClientCapability(self.Capabilities.dataAdmin) then
        return
    end
    if IsValid(self.DataConsole) then
        self.DataConsole:MakePopup()
        return
    end

    local palette = ZM_DermaSkin.Palette
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("PREVIEW PLAYER DATA")
    frame:SetSize(math.min(1060, ScrW() - 40), math.min(700, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if self.DataConsole == frame then
            self.DataConsole = nil
        end
    end
    self.DataConsole = frame
    UI:OpenExclusive(frame)

    local listPanel = vgui.Create("DPanel", frame)
    listPanel:Dock(LEFT)
    listPanel:SetWide(270)
    listPanel:DockMargin(8, 30, 4, 8)
    listPanel.Paint = function(_, width, height)
        surface.SetDrawColor(palette.panel.r, palette.panel.g, palette.panel.b, 255)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border.r, palette.border.g, palette.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local search = vgui.Create("DTextEntry", listPanel)
    search:Dock(TOP)
    search:DockMargin(7, 7, 7, 4)
    search:SetTall(24)
    search:SetPlaceholderText("Exact SteamID")

    local refresh = vgui.Create("DButton", listPanel)
    refresh:Dock(TOP)
    refresh:DockMargin(7, 0, 7, 5)
    refresh:SetTall(24)
    refresh:SetText("Refresh Players")

    local playerList = vgui.Create("DListView", listPanel)
    playerList:Dock(FILL)
    playerList:DockMargin(7, 0, 7, 7)
    playerList:AddColumn("SteamID")
    playerList:AddColumn("Level")
    playerList:AddColumn("Cell")

    local content = vgui.Create("DScrollPanel", frame)
    content:Dock(FILL)
    content:DockMargin(4, 30, 8, 8)

    local status = vgui.Create("DLabel", content)
    status:Dock(TOP)
    status:DockMargin(4, 3, 4, 6)
    status:SetFont("DermaDefaultBold")
    status:SetTextColor(palette.muted)
    status:SetTall(20)
    status:SetText("Select a preview player record")

    local selectedLabel = vgui.Create("DLabel", content)
    selectedLabel:Dock(TOP)
    selectedLabel:DockMargin(4, 0, 4, 6)
    selectedLabel:SetTextColor(palette.text)
    selectedLabel:SetTall(20)

    local inputs = { attributes = {}, playerData = {} }
    local selectedRecord
    local function addField(parent, label, inputsTable, withStepper)
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:DockMargin(4, 1, 4, 1)
        row:SetTall(24)
        row.Paint = function() end
        local text = vgui.Create("DLabel", row)
        text:Dock(LEFT)
        text:SetWide(142)
        text:SetText(label)
        text:SetTextColor(palette.muted)
        if withStepper then
            local incrementButton = vgui.Create("DButton", row)
            incrementButton:Dock(RIGHT)
            incrementButton:SetWide(24)
            incrementButton:SetText("+")
            incrementButton:SetTooltip("Increase " .. label)
            local decrementButton = vgui.Create("DButton", row)
            decrementButton:Dock(RIGHT)
            decrementButton:DockMargin(3, 0, 3, 0)
            decrementButton:SetWide(24)
            decrementButton:SetText("-")
            decrementButton:SetTooltip("Decrease " .. label)
            local function adjustAttribute(delta)
                local current = math.floor(tonumber(inputsTable[label] and inputsTable[label]:GetValue()) or 0)
                inputsTable[label]:SetValue(tostring(math.Clamp(current + delta, 0, 300)))
            end
            incrementButton.DoClick = function() adjustAttribute(1) end
            decrementButton.DoClick = function() adjustAttribute(-1) end
        end
        local input = vgui.Create("DTextEntry", row)
        input:Dock(FILL)
        inputsTable[label] = input
    end

    local attributePanel = vgui.Create("DPanel", content)
    attributePanel:Dock(TOP)
    attributePanel:DockMargin(4, 0, 4, 8)
    attributePanel:SetTall(#dataAttributeFields * 26 + 58)
    attributePanel.Paint = function(_, width, height)
        surface.SetDrawColor(palette.panel.r, palette.panel.g, palette.panel.b, 255)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border.r, palette.border.g, palette.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end
    local attributeTitle = vgui.Create("DLabel", attributePanel)
    attributeTitle:Dock(TOP)
    attributeTitle:DockMargin(6, 5, 6, 2)
    attributeTitle:SetText("ATTRIBUTES (PREVIEW ONLY)")
    attributeTitle:SetFont("DermaDefaultBold")
    attributeTitle:SetTextColor(palette.redBright)
    for _, field in ipairs(dataAttributeFields) do addField(attributePanel, field, inputs.attributes, true) end
    local saveAttributes = vgui.Create("DButton", attributePanel)
    saveAttributes:Dock(BOTTOM)
    saveAttributes:DockMargin(6, 4, 6, 5)
    saveAttributes:SetTall(24)
    saveAttributes:SetText("Save Attributes")

    local playerDataPanel = vgui.Create("DPanel", content)
    playerDataPanel:Dock(TOP)
    playerDataPanel:DockMargin(4, 0, 4, 8)
    playerDataPanel:SetTall(#dataPlayerFields * 26 + 58)
    playerDataPanel.Paint = attributePanel.Paint
    local playerDataTitle = vgui.Create("DLabel", playerDataPanel)
    playerDataTitle:Dock(TOP)
    playerDataTitle:DockMargin(6, 5, 6, 2)
    playerDataTitle:SetText("PROGRESSION AND SURVIVAL (PREVIEW ONLY)")
    playerDataTitle:SetFont("DermaDefaultBold")
    playerDataTitle:SetTextColor(palette.redBright)
    for _, field in ipairs(dataPlayerFields) do addField(playerDataPanel, field, inputs.playerData) end
    local savePlayerData = vgui.Create("DButton", playerDataPanel)
    savePlayerData:Dock(BOTTOM)
    savePlayerData:DockMargin(6, 4, 6, 5)
    savePlayerData:SetTall(24)
    savePlayerData:SetText("Save Progression")

    local function fillRecord(record)
        selectedRecord = record
        local attributes = record.attributes or {}
        local playerData = record.playerData or {}
        selectedLabel:SetText(record.steamId)
        for _, field in ipairs(dataAttributeFields) do inputs.attributes[field]:SetValue(tostring(attributes[field] or 0)) end
        for _, field in ipairs(dataPlayerFields) do inputs.playerData[field]:SetValue(tostring(playerData[field] or "")) end
    end

    local function collectInputs(inputTable, fields)
        local values = {}
        for _, field in ipairs(fields) do values[field] = inputTable[field]:GetValue() end
        return values
    end

    refresh.DoClick = function()
        self:RequestData({ action = "list", search = search:GetValue() })
    end
    playerList.OnRowSelected = function(_, _, row)
        self:RequestData({ action = "read", steamId = row.SteamId })
    end
    saveAttributes.DoClick = function()
        if selectedRecord then
            self:RequestData({ action = "attributes", steamId = selectedRecord.steamId, values = collectInputs(inputs.attributes, dataAttributeFields) })
        end
    end
    savePlayerData.DoClick = function()
        if selectedRecord then
            self:RequestData({ action = "playerData", steamId = selectedRecord.steamId, values = collectInputs(inputs.playerData, dataPlayerFields) })
        end
    end

    self.DataHandlers.list = function(response)
        status:SetText(response.ok and "Preview player records" or (response.message or "Could not load records"))
        playerList:Clear()
        for _, row in ipairs(response.rows or {}) do
            local line = playerList:AddLine(row.steamid, row.Level or "-", string.format("%s, %s", row.CellX or "-", row.CellY or "-"))
            line.SteamId = row.steamid
        end
    end
    local function handleRecord(response)
        status:SetText(response.ok and (response.message or "Preview record loaded") or (response.message or "Preview record request failed"))
        if response.record then fillRecord(response.record) end
    end
    self.DataHandlers.read = handleRecord
    self.DataHandlers.attributes = handleRecord
    self.DataHandlers.playerData = handleRecord
    self:RequestData({ action = "list" })
end

concommand.Add("zombiesim_preview_data", function()
    Preview:OpenDataConsole()
end)

hook.Add("InitPostEntity", "ZM.Preview.RefreshClientCapabilities", function()
    UI:CloseTransient()
    Preview:SetClientCapabilities(0)
    timer.Simple(0, function()
        if not ZM_World or not ZM_World:IsLoaded() then
            return
        end
        net.Start("ZM.RequestPreviewCapabilities")
        net.SendToServer()
    end)
end)