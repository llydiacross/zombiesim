ZM_CellHealth = ZM_CellHealth or {}
local CellHealth = ZM_CellHealth
local Contract = include("sh_cell_health_contract.lua")()
local palette = ZM_DermaSkin.Palette

CellHealth.Contract = Contract
CellHealth.BatchSelection = CellHealth.BatchSelection or { navmesh = false, photos = false, cubemaps = false }

local statusColors = {
    green = Color(60, 155, 79),
    orange = Color(218, 143, 47),
    red = Color(168, 45, 56)
}

local function fileAccess()
    return {
        Exists = function(path) return file.Exists(path, "GAME") end,
        Size = function(path) return file.Size(path, "GAME") end,
        Read = function(path) return file.Read(path, "GAME") end
    }
end

local function readCaptureManifest()
    local path = "data_static/world_captures_preview.json"
    local source = file.Read(path, "GAME")
    if not source then return nil, "Captured-world manifest is not mounted." end

    local manifest = util.JSONToTable(source)
    if type(manifest) ~= "table" then return nil, "Captured-world manifest is invalid JSON." end
    return manifest
end

local function hasPreviewAdmin()
    local player = LocalPlayer()
    if not IsValid(player) or not player:IsAdmin() then
        return false, "Cell Health requires an admin player."
    end
    if not ZM_World or ZM_World.ActiveProfile ~= "preview" then
        return false, "Cell Health is available only in the preview profile."
    end
    if not ZM_World:IsLoaded() then
        return false, "Preview world data is unavailable: " .. tostring(ZM_World:GetLoadError())
    end
    return true
end

function CellHealth:GetSnapshot()
    local allowed, reason = hasPreviewAdmin()
    if not allowed then return nil, reason end

    local manifest, manifestError = readCaptureManifest()
    return Contract.BuildSnapshot(ZM_World:GetData(), manifest, fileAccess(), manifestError, self.CubemapConfirmations)
end

local function photoText(photo)
    if photo.complete then
        return string.upper(photo.variant) .. ": PRESENT (" .. photo.width .. "x" .. photo.height .. ")"
    end
    return string.upper(photo.variant) .. ": INCOMPLETE - " .. tostring(photo.reason)
end

local function cubemapText(cubemaps)
    if cubemaps.complete then
        return "USER CONFIRMED - " .. tostring(cubemaps.reason)
    end
    return "INCOMPLETE - " .. tostring(cubemaps.reason)
end

local function cellDetails(cell)
    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
    local lines = {
        "CELL " .. tostring(cell.id) .. " - " .. string.upper(cell.state),
        "Grid: " .. cell.x .. ", " .. cell.y,
        worldX and ("World: " .. worldX .. ", " .. worldY) or nil,
        "Map: " .. tostring(cell.map),
        "Navmesh: " .. (cell.navmesh.complete and ("PRESENT (" .. cell.navmesh.size .. " bytes)") or
            ("INCOMPLETE - " .. tostring(cell.navmesh.reason))),
        "Cubemaps: " .. cubemapText(cell.cubemaps),
        "World photos: " .. (cell.photos.complete and "COMPLETE" or "INCOMPLETE"),
        "  " .. photoText(cell.photos.clear),
        "  " .. photoText(cell.photos.atmospheric)
    }
    local filtered = {}
    for _, line in ipairs(lines) do
        if line then filtered[#filtered + 1] = line end
    end
    return table.concat(filtered, "\n")
end

function CellHealth:UpdateBatchControls()
    if not IsValid(self.BatchStartButton) or not IsValid(self.BatchSummary) or not IsValid(self.BatchResult) then return end
    local jobs, failure = Contract.BuildBatchSelection(self.Snapshot, self.BatchSelection)
    if not jobs then
        self.BatchStartButton:SetEnabled(false)
        self.BatchSummary:SetText(failure)
        self.BatchResult:SetText(self.BatchStatusMessage or "")
        return
    end

    local photoCells, navMaps, cubemapMaps = 0, {}, {}
    local mapById = {}
    for _, cell in ipairs(self.Snapshot.cells) do mapById[cell.id] = cell.map end
    for _, job in ipairs(jobs) do
        local map = mapById[job.id]
        if job.photos then photoCells = photoCells + 1 end
        if type(map) == "string" then
            if job.navmesh then navMaps[map] = true end
            if job.cubemaps then cubemapMaps[map] = true end
        end
    end

    local function countKeys(values)
        local count = 0
        for _ in pairs(values) do count = count + 1 end
        return count
    end
    self.BatchStartButton:SetEnabled(#jobs > 0)
    self.BatchSummary:SetText(string.format(
        "%d unhealthy cell(s) queued; navmeshes %d, photos %d, cubemap prompts %d",
        #jobs, countKeys(navMaps), photoCells, countKeys(cubemapMaps)
    ))
    self.BatchResult:SetText(self.BatchStatusMessage or "")
end

function CellHealth:StartBatch()
    local jobs, failure = Contract.BuildBatchSelection(self.Snapshot, self.BatchSelection)
    if not jobs then
        self.BatchStatusMessage = failure
        self:UpdateBatchControls()
        return
    end
    if #jobs == 0 then
        self.BatchStatusMessage = "No unhealthy cells for the selected artifacts."
        self:UpdateBatchControls()
        return
    end

    local request = util.TableToJSON({
        schemaVersion = 1,
        selection = self.BatchSelection
    }, false)
    if type(request) ~= "string" or #request > 2048 then
        self.BatchStatusMessage = "Cell Health batch request could not be encoded."
        self:UpdateBatchControls()
        return
    end
    net.Start("ZM.CellHealth.BatchStart")
        net.WriteString(request)
    net.SendToServer()
    self.BatchStatusMessage = "Requesting the preview maintenance batch..."
    self:UpdateBatchControls()
end

function CellHealth:Render(snapshot)
    if not IsValid(self.Frame) then return end
    if IsValid(self.Body) then self.Body:Remove() end

    local body = vgui.Create("DPanel", self.Frame)
    self.Body = body
    body:Dock(FILL)
    body:DockMargin(12, 6, 12, 12)
    body.Paint = function(_, width, height)
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, width, height)
    end

    local header = vgui.Create("DPanel", body)
    header:Dock(TOP)
    header:SetTall(60)
    header.Paint = function(_, width, height)
        surface.SetDrawColor(palette.raised)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local refresh = vgui.Create("DButton", header)
    refresh:Dock(RIGHT)
    refresh:DockMargin(6, 10, 8, 10)
    refresh:SetWide(96)
    refresh:SetSkin("ZombieSim")
    refresh:SetText("REFRESH")
    refresh.DoClick = function() self:Refresh() end

    local summary = vgui.Create("DLabel", header)
    summary:Dock(FILL)
    summary:DockMargin(10, 6, 4, 6)
    summary:SetTextColor(palette.text)
    summary:SetWrap(true)
    summary:SetText(string.format(
        "CELLS %d   GREEN %d   ORANGE %d   RED %d\nNAVMESH %d/%d   WORLD PHOTOS %d/%d   CUBEMAPS USER CONFIRMED %d/%d",
        snapshot.summary.total, snapshot.summary.green, snapshot.summary.orange, snapshot.summary.red,
        snapshot.summary.navmeshCells, snapshot.summary.total, snapshot.summary.photoCells, snapshot.summary.total,
        snapshot.summary.cubemapCells, snapshot.summary.total
    ))

    local note = vgui.Create("DLabel", body)
    note:Dock(TOP)
    note:DockMargin(6, 6, 6, 2)
    note:SetTall(snapshot.photoManifestError and 48 or 34)
    note:SetTextColor(palette.muted)
    note:SetWrap(true)
    local noteText = "Preview artifact check. Green = all three complete; orange = some; red = none. World photo requires current-map clear and atmospheric images. A cubemap counts only after you confirm buildcubemaps succeeded; it is not engine-verified."
    if snapshot.photoManifestError then
        noteText = noteText .. "\nPhoto manifest: " .. snapshot.photoManifestError
    end
    note:SetText(noteText)

    local main = vgui.Create("DPanel", body)
    main:Dock(FILL)
    main:DockMargin(4, 4, 4, 4)
    main.Paint = function() end

    local gridPanel = vgui.Create("DPanel", main)
    gridPanel:Dock(LEFT)
    gridPanel:DockMargin(0, 0, 10, 0)
    gridPanel:SetWide(506)
    gridPanel.Paint = function(_, width, height)
        surface.SetDrawColor(palette.raised)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local details = vgui.Create("DPanel", main)
    details:Dock(FILL)
    details.Paint = function(_, width, height)
        surface.SetDrawColor(palette.raised)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local detailLabel = vgui.Create("DLabel", details)
    detailLabel:Dock(TOP)
    detailLabel:DockMargin(12, 12, 12, 12)
    detailLabel:SetTall(300)
    detailLabel:SetTextColor(palette.text)
    detailLabel:SetWrap(true)
    detailLabel:SetText("Select a cell to inspect its artifacts.")

    local controls = vgui.Create("DPanel", details)
    controls:Dock(BOTTOM)
    controls:DockMargin(10, 0, 10, 10)
    controls:SetTall(178)
    controls.Paint = function(_, width, height)
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local startBatch = vgui.Create("DButton", controls)
    self.BatchStartButton = startBatch
    startBatch:Dock(TOP)
    startBatch:DockMargin(8, 8, 8, 4)
    startBatch:SetTall(30)
    startBatch:SetSkin("ZombieSim")
    startBatch:SetText("START BATCH OF UNHEALTHY CELLS")
    startBatch.DoClick = function() self:StartBatch() end

    local function addBatchCheckbox(key, label)
        local checkbox = vgui.Create("DCheckBoxLabel", controls)
        checkbox:Dock(TOP)
        checkbox:DockMargin(8, 0, 8, 0)
        checkbox:SetText(label)
        checkbox:SetTextColor(palette.text)
        checkbox:SetValue(self.BatchSelection[key] and 1 or 0)
        checkbox.OnChange = function(_, enabled)
            self.BatchSelection[key] = enabled == true
            self.BatchStatusMessage = nil
            self:UpdateBatchControls()
        end
    end

    addBatchCheckbox("navmesh", "Generate missing navmeshes")
    addBatchCheckbox("photos", "Capture missing world photos")
    addBatchCheckbox("cubemaps", "Prompt me for missing cubemaps")

    local batchSummary = vgui.Create("DLabel", controls)
    self.BatchSummary = batchSummary
    batchSummary:Dock(TOP)
    batchSummary:DockMargin(8, 2, 8, 0)
    batchSummary:SetTall(22)
    batchSummary:SetTextColor(palette.muted)
    batchSummary:SetWrap(true)

    local batchResult = vgui.Create("DLabel", controls)
    self.BatchResult = batchResult
    batchResult:Dock(TOP)
    batchResult:DockMargin(8, 0, 8, 4)
    batchResult:SetTall(38)
    batchResult:SetTextColor(palette.text)
    batchResult:SetWrap(true)

    local grid = vgui.Create("DIconLayout", gridPanel)
    grid:Dock(FILL)
    grid:DockMargin(12, 12, 12, 12)
    grid:SetSpaceX(2)
    grid:SetSpaceY(2)

    local function selectCell(cell)
        CellHealth.SelectedCellId = cell.id
        detailLabel:SetText(cellDetails(cell))
    end

    for _, cell in ipairs(snapshot.cells) do
        local tile = grid:Add("DButton")
        tile:SetSize(18, 18)
        tile:SetText("")
        tile:SetTooltip("Cell " .. cell.x .. ", " .. cell.y .. " | " .. cell.map .. " | " .. string.upper(cell.state))
        tile.Paint = function(panel, width, height)
            surface.SetDrawColor(statusColors[cell.state] or statusColors.red)
            surface.DrawRect(0, 0, width, height)
            local outline = panel:IsHovered() and palette.text or
                (CellHealth.SelectedCellId == cell.id and palette.redBright or palette.border)
            surface.SetDrawColor(outline)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
        end
        tile.DoClick = function() selectCell(cell) end
    end

    local selectedCell
    for _, cell in ipairs(snapshot.cells) do
        if cell.id == self.SelectedCellId then selectedCell = cell break end
    end
    selectCell(selectedCell or snapshot.cells[1])
    self:UpdateBatchControls()
end

function CellHealth:Refresh()
    if not IsValid(self.Frame) then return false end
    local snapshot, failure = self:GetSnapshot()
    if not snapshot then
        if IsValid(self.Body) then self.Body:Remove() end
        local body = vgui.Create("DPanel", self.Frame)
        self.Body = body
        body:Dock(FILL)
        local message = vgui.Create("DLabel", body)
        message:Dock(FILL)
        message:SetTextColor(palette.text)
        message:SetWrap(true)
        message:SetText("Cell Health could not load: " .. tostring(failure))
        return false
    end
    self.Snapshot = snapshot
    self:Render(snapshot)
    return true
end

function CellHealth:Open()
    local allowed, reason = hasPreviewAdmin()
    if not allowed then
        ErrorNoHalt("[ZombieSim] " .. reason .. "\n")
        return false
    end
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:Refresh()
        self:RequestCubemapStatus()
        return true
    end

    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSkin("ZombieSim")
    frame:SetSize(math.min(980, ScrW() - 40), math.min(700, ScrH() - 40))
    frame:Center()
    frame:SetTitle("PREVIEW CELL HEALTH")
    frame:MakePopup()
    frame.OnRemove = function()
        if self.Frame ~= frame then return end
        self.Frame, self.Body, self.Snapshot = nil, nil, nil
    end
    self:Refresh()
    self:RequestCubemapStatus()
    return true
end

function CellHealth:RequestCubemapStatus()
    net.Start("ZM.CellHealth.CubemapStatusRequest")
    net.SendToServer()
end

concommand.Remove("zombiesim_dev_cell_health")
concommand.Add("zombiesim_dev_cell_health", function()
    if CellHealth:Open() then
        print("[ZombieSim] Cell Health window opened.")
    end
end)

net.Receive("ZM.CellHealth.CubemapStatus", function()
    local success = net.ReadBool()
    local message = net.ReadString()
    if not success then
        ErrorNoHalt("[ZombieSim] Could not load cubemap confirmations: " .. message .. "\n")
        return
    end
    local confirmations = util.JSONToTable(message)
    if type(confirmations) ~= "table" then
        ErrorNoHalt("[ZombieSim] Cubemap confirmation response is invalid.\n")
        return
    end
    CellHealth.CubemapConfirmations = confirmations
    if IsValid(CellHealth.Frame) then CellHealth:Refresh() end
end)

net.Receive("ZM.CellHealth.BatchResult", function()
    local success = net.ReadBool()
    CellHealth.BatchStatusMessage = net.ReadString()
    print("[ZombieSim] " .. CellHealth.BatchStatusMessage)
    if IsValid(CellHealth.Frame) then CellHealth:UpdateBatchControls() end
    if not success then ErrorNoHalt("[ZombieSim] Cell Health batch was not started.\n") end
end)

net.Receive("ZM.WorldCapture.CubemapPrompt", function()
    local request = util.JSONToTable(net.ReadString())
    if type(request) ~= "table" or type(request.runId) ~= "string" or
        type(request.map) ~= "string" or (request.stage ~= "run" and request.stage ~= "success") then
        ErrorNoHalt("[ZombieSim] Cubemap prompt is invalid.\n")
        return
    end

    if request.stage == "run" then
        Derma_Query(
            "For " .. request.map .. ", open the developer console and run buildcubemaps. The map will reload; after it does, you will be asked whether it succeeded.",
            "BUILD CUBEMAPS",
            "OK",
            function() end,
            "CANCEL BATCH",
            function()
                net.Start("ZM.WorldCapture.Cancel")
                net.SendToServer()
            end
        )
        return
    end

    Derma_Query(
        "Did buildcubemaps succeed for " .. request.map .. "? This answer is recorded as your confirmation, not engine verification.",
        "CUBEMAP RESULT",
        "YES",
        function()
            net.Start("ZM.WorldCapture.CubemapDecision")
                net.WriteString(request.runId)
                net.WriteString(request.map)
                net.WriteBool(true)
            net.SendToServer()
        end,
        "NO",
        function()
            net.Start("ZM.WorldCapture.CubemapDecision")
                net.WriteString(request.runId)
                net.WriteString(request.map)
                net.WriteBool(false)
            net.SendToServer()
        end
    )
end)
