local Gizmo = include("prefabs/sh_gizmo.lua")
local Contract = include("prefabs/sh_contract.lua")
ZM_PrefabEditorClient = ZM_PrefabEditorClient or {}
local Editor = ZM_PrefabEditorClient
local axisColors = { x = Color(235, 75, 75), y = Color(80, 210, 110), z = Color(80, 150, 255) }
local axes = { x = Vector(1, 0, 0), y = Vector(0, 1, 0), z = Vector(0, 0, 1) }
local arrowWings = { x = Vector(0, 0, 1), y = Vector(0, 0, 1), z = Vector(1, 0, 0) }
local scaleHandleMin, scaleHandleMax = Vector(-5, -5, -5), Vector(5, 5, 5)
local gridColor = Color(125, 210, 190)
local selectionColor = Color(255, 220, 100)
local axisLength = 100
local modelPageSize = 48
local lootModeLabels = { off = "Off", normal = "Normal", guaranteed = "Guaranteed" }
local compassAngle = Angle(0, 0, 0)
local compassLabels = {
    { text = "N", x = 0, y = 300 },
    { text = "E", x = 300, y = 0 },
    { text = "S", x = 0, y = -300 },
    { text = "W", x = -300, y = 0 }
}
local rotationCircle = {}
for index = 0, 24 do
    local angle = index * math.pi * 2 / 24
    rotationCircle[#rotationCircle + 1] = { math.cos(angle) * 72, math.sin(angle) * 72 }
end
surface.CreateFont("ZM_PrefabCompass", { font = "Trebuchet MS", size = 36, weight = 900, antialias = true })

local function send(action, text, openedId)
    if #action + #(text or "") + #(openedId or "") > 60000 then
        Derma_Message("The prefab request is too large to send to the server.", "Prefab editor", "OK")
        return false
    end
    net.Start("ZM.PrefabEditorRequest")
        net.WriteString(action)
        net.WriteString(text or "")
        net.WriteString(openedId or "")
    net.SendToServer()
    return true
end

local function blankDocument()
    return { schemaVersion = 1, id = "", name = "", description = "", tags = {}, props = {} }
end

local function label(parent, text)
    local control = vgui.Create("DLabel", parent)
    control:Dock(TOP)
    control:DockMargin(6, 5, 6, 1)
    control:SetTall(18)
    control:SetText(text)
    return control
end

local function button(parent, text, action)
    local control = vgui.Create("DButton", parent)
    control:Dock(TOP)
    control:DockMargin(6, 3, 6, 2)
    control:SetTall(25)
    control:SetText(text)
    control.DoClick = action
    return control
end

local function textEntry(parent, title, action)
    label(parent, title)
    local control = vgui.Create("DTextEntry", parent)
    control:Dock(TOP)
    control:DockMargin(6, 0, 6, 2)
    control:SetTall(24)
    control:SetUpdateOnType(true)
    control.OnValueChange = function(_, value)
        if not Editor.Refreshing then action(value) end
    end
    return control
end

function Editor:IsActive()
    return self.Active == true and IsValid(self.Frame)
end

function Editor:IsSession()
    local ply = LocalPlayer()
    local map = game.GetMap()
    return (map == "gm_flatgrass" or map == "zn_dev_prefab_anchor")
        and IsValid(ply) and ply:GetNWBool("ZM.PrefabEditorActive", false)
end

function Editor:Message(text, problem)
    if IsValid(self.Status) then
        self.Status:SetText(tostring(text or ""))
        self.Status:SetTextColor(problem and Color(255, 120, 110) or color_white)
    end
    if problem then
        ErrorNoHalt("[ZombieSim] Prefab editor: " .. tostring(text) .. "\n")
        Derma_Message(tostring(text), "Prefab editor", "OK")
    end
end

function Editor:MarkChanged()
    self.Revision = (self.Revision or 0) + 1
    self.Dirty = true
end

function Editor:ClearModels()
    for _, model in ipairs(self.Models or {}) do
        if IsValid(model) then model:Remove() end
    end
    self.Models = {}
end

function Editor:UpdateModel(index)
    local prop = self.Document.props[index]
    local model = self.Models[index]
    if not prop or not IsValid(model) then return end
    model:SetPos(self.Origin + Vector(prop.position.x, prop.position.y, prop.position.z))
    model:SetAngles(Angle(prop.angles.p, prop.angles.y, prop.angles.r))
    model:SetSkin(prop.skin)
    if model.ZM_PrefabScale ~= prop.scale then
        local matrix = Matrix()
        matrix:Scale(Vector(prop.scale, prop.scale, prop.scale))
        model:EnableMatrix("RenderMultiply", matrix)
        local minimum, maximum = model:GetModelBounds()
        model:SetRenderBounds(minimum * prop.scale, maximum * prop.scale)
        model.ZM_PrefabScale = prop.scale
    end
end

function Editor:MakeModel(index)
    local prop = self.Document.props[index]
    local model = ClientsideModel(prop.model, RENDERGROUP_OTHER)
    if not IsValid(model) then
        self.Models[index] = false
        self:Message("Could not display model: " .. prop.model, true)
        return false
    end
    model:SetNoDraw(true)
    self.Models[index] = model
    self:UpdateModel(index)
    return true
end

function Editor:RefreshInspector()
    if not IsValid(self.PropList) then return end
    self.Refreshing = true
    self.PropList:Clear()
    for index, prop in ipairs(self.Document.props) do
        local row = self.PropList:AddLine((self.Selected == index and "> " or "") .. prop.model)
        row.PrefabIndex = index
    end
    local prop = self.Document.props[self.Selected or 0]
    for _, entry in ipairs(self.Inspector or {}) do
        entry.control:SetEnabled(prop ~= nil)
        local value = prop and (entry.group and prop[entry.group][entry.key] or prop[entry.key]) or 0
        entry.control:SetValue(value)
    end
    if IsValid(self.MovableToggle) then
        self.MovableToggle:SetEnabled(prop ~= nil)
        self.MovableToggle:SetValue(prop and prop.movable and 1 or 0)
    end
    if IsValid(self.LootMode) then
        self.LootMode:SetEnabled(prop ~= nil)
        self.LootMode:SetValue(prop and lootModeLabels[prop.lootMode or "off"] or "Off")
        self.LootGroup:SetEnabled(prop ~= nil and prop.lootMode ~= "off")
        self.LootGroup:SetValue(prop and prop.lootGroup or "")
        self.LootChanceToggle:SetEnabled(prop ~= nil and prop.lootMode == "normal")
        self.LootChanceToggle:SetValue(prop and prop.lootChance ~= nil and 1 or 0)
        self.LootChance:SetEnabled(prop ~= nil and prop.lootMode == "normal" and prop.lootChance ~= nil)
        self.LootChance:SetValue(prop and prop.lootChance ~= nil and prop.lootChance * 100 or 0)
    end
    self.Refreshing = false
end

function Editor:RefreshDocument()
    if not IsValid(self.Frame) then return end
    self.Refreshing = true
    self.IdInput:SetValue(self.Document.id)
    self.IdInput:SetEnabled(self.OpenedId == nil)
    self.NameInput:SetValue(self.Document.name)
    self.DescriptionInput:SetValue(self.Document.description)
    self.TagsInput:SetValue(table.concat(self.Document.tags, ", "))
    self.Refreshing = false
    self:RefreshInspector()
end

function Editor:SetDocument(document, openedId)
    if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
    self.Drag = nil
    self:ClearRotationSelection()
    self:ClearModels()
    self.Document = document
    self.OpenedId = openedId
    self.Selected = nil
    self.LastPropClick = nil
    self.Dirty = false
    self.Revision = (self.Revision or 0) + 1
    for index in ipairs(document.props) do self:MakeModel(index) end
    self:RefreshDocument()
end

function Editor:SetDocuments(documents)
    if not IsValid(self.PrefabList) then return end
    self.PrefabList:Clear()
    for _, document in ipairs(documents or {}) do
        local row = self.PrefabList:AddLine(document.name, document.id)
        row.PrefabId = document.id
    end
end

function Editor:ConfirmDiscard(action)
    if not self.Dirty then action() return end
    Derma_Query("Discard the unsaved prefab changes?", "Prefab editor",
        "Discard", action, "Cancel", function() end)
end

function Editor:RequestExplorer(action, text, extra)
    return send(action, text, extra)
end

function Editor:OpenSaved(id, after)
    self:ConfirmDiscard(function()
        if send("load", id) and after then after() end
    end)
end

local function parseTags(value)
    local tags = {}
    for tag in string.gmatch(value, "[^,]+") do
        tag = string.Trim(tag)
        if tag ~= "" then tags[#tags + 1] = tag end
    end
    return tags
end

function Editor:SyncMetadata()
    local id = self.IdInput:GetValue()
    local name = self.NameInput:GetValue()
    local description = self.DescriptionInput:GetValue()
    local tags = parseTags(self.TagsInput:GetValue())
    local changed = self.Document.id ~= id or self.Document.name ~= name
        or self.Document.description ~= description or #self.Document.tags ~= #tags
    if not changed then
        for index, tag in ipairs(tags) do
            if self.Document.tags[index] ~= tag then changed = true break end
        end
    end
    self.Document.id = id
    self.Document.name = name
    self.Document.description = description
    self.Document.tags = tags
    if changed then self:MarkChanged() end
end

function Editor:Save(exitAfter)
    if self.Saving then return end
    self:SyncMetadata()
    local encoded = util.TableToJSON(self.Document, false)
    if type(encoded) ~= "string" then self:Message("Could not encode the prefab.", true) return end
    if not send("save", encoded, self.OpenedId) then return end
    self.Saving = true
    self.SaveRevision = self.Revision
    self.PendingSaveId = self.Document.id
    self.ExitAfterSave = exitAfter == true
end

function Editor:Exit()
    if self.Saving then self:Message("Wait for the current save to finish.", true) return end
    if not self.Dirty then send("end") return end
    Derma_Query("Save the current prefab before returning to the preview launcher?", "Prefab editor",
        "Save and exit", function() self:Save(true) end,
        "Discard and exit", function() send("end") end,
        "Cancel", function() end)
end

local function validModelFolder(folder)
    return type(folder) == "string" and string.match(folder, "^models/") ~= nil
        and not string.find(folder, "..", 1, true) and not string.find(folder, "\\", 1, true)
        and not string.find(folder, ":", 1, true) and not string.find(folder, "*", 1, true)
        and not string.find(folder, "?", 1, true) and not string.find(folder, "%c")
end

function Editor:OpenModelBrowser()
    if IsValid(self.ModelBrowser) then self.ModelBrowser:MakePopup() return end
    local browser = vgui.Create("DFrame", self.Frame)
    self.ModelBrowser = browser
    browser:SetSize(math.min(900, ScrW() - 80), math.min(700, ScrH() - 80))
    browser:Center()
    browser:SetTitle("MODEL BROWSER")
    browser:MakePopup()
    browser.OnRemove = function()
        self.ModelBrowser = nil
        if self:IsActive() then self.Frame:MakePopup() end
    end
    browser.OnKeyCodePressed = function(panel, key)
        if key == KEY_ESCAPE then panel:Close() end
    end

    local folderBar = vgui.Create("DPanel", browser)
    folderBar:Dock(TOP)
    folderBar:SetTall(32)
    folderBar.Paint = function() end
    local up = vgui.Create("DButton", folderBar)
    up:Dock(LEFT)
    up:SetWide(50)
    up:SetText("UP")
    local go = vgui.Create("DButton", folderBar)
    go:Dock(RIGHT)
    go:SetWide(50)
    go:SetText("GO")
    local folderInput = vgui.Create("DTextEntry", folderBar)
    folderInput:Dock(FILL)
    folderInput:SetValue(self.ModelFolder:GetValue())
    browser.FolderInput = folderInput

    local search = vgui.Create("DTextEntry", browser)
    search:Dock(TOP)
    search:DockMargin(0, 4, 0, 4)
    search:SetTall(26)
    search:SetPlaceholderText("Search models in this folder")
    search:SetUpdateOnType(true)
    browser.Search = search

    local globalSearch = vgui.Create("DCheckBoxLabel", browser)
    globalSearch:Dock(TOP)
    globalSearch:DockMargin(0, 0, 0, 4)
    globalSearch:SetText("Search all mounted model folders")
    globalSearch:SetValue(0)
    browser.GlobalSearch = globalSearch

    local footer = vgui.Create("DPanel", browser)
    footer:Dock(BOTTOM)
    footer:SetTall(30)
    footer.Paint = function() end
    local previous = vgui.Create("DButton", footer)
    previous:Dock(LEFT)
    previous:SetWide(90)
    previous:SetText("PREVIOUS")
    browser.Previous = previous
    local nextPage = vgui.Create("DButton", footer)
    nextPage:Dock(RIGHT)
    nextPage:SetWide(90)
    nextPage:SetText("NEXT")
    browser.NextPage = nextPage
    local pageLabel = vgui.Create("DLabel", footer)
    pageLabel:Dock(FILL)
    pageLabel:SetContentAlignment(5)
    browser.PageLabel = pageLabel

    local folders = vgui.Create("DListView", browser)
    folders:Dock(LEFT)
    folders:SetWide(200)
    folders:AddColumn("Folders")
    browser.Folders = folders
    local scroll = vgui.Create("DScrollPanel", browser)
    scroll:Dock(FILL)
    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(TOP)
    grid:SetSpaceX(6)
    grid:SetSpaceY(6)
    browser.Grid = grid

    local folder, filenames, page = "", {}, 1
    local globalEnabled, indexPaths, indexQueue, indexCursor, indexFailure = false, {}, nil, 1, nil
    local nextIndexRefresh
    local function refresh()
        grid:Clear()
        local query = string.lower(string.Trim(search:GetValue()))
        local matches = {}
        local paths = globalEnabled and indexPaths or filenames
        if not globalEnabled or query ~= "" then
            for _, path in ipairs(paths) do
                local searchable = string.lower(globalEnabled and path or string.match(path, "([^/]+)$"))
                local matched = true
                for term in string.gmatch(query, "%S+") do
                    if not string.find(searchable, term, 1, true) then matched = false break end
                end
                if matched then matches[#matches + 1] = path end
            end
        end
        table.sort(matches)
        local pages = math.max(1, math.ceil(#matches / modelPageSize))
        page = math.Clamp(page, 1, pages)
        local progress = ""
        if globalEnabled and query == "" then progress = " - enter a search term"
        elseif globalEnabled and indexFailure then progress = " - search incomplete"
        elseif globalEnabled and indexQueue and indexCursor <= #indexQueue then progress = " - scanning" end
        pageLabel:SetText(string.format("Page %d / %d  -  %d models%s", page, pages, #matches, progress))
        previous:SetEnabled(page > 1)
        nextPage:SetEnabled(page < pages)
        for index = (page - 1) * modelPageSize + 1, math.min(page * modelPageSize, #matches) do
            local path = matches[index]
            local name = string.match(path, "([^/]+)$")
            local card = grid:Add("DButton")
            card:SetSize(100, 112)
            card:SetText("")
            card:SetTooltip(path)
            card.ModelPath = path
            local image = vgui.Create("ModelImage", card)
            image:SetPos(10, 4)
            image:SetSize(80, 80)
            image:SetMouseInputEnabled(false)
            image:SetKeyboardInputEnabled(false)
            image:SetModel(path)
            local title = vgui.Create("DLabel", card)
            title:SetPos(4, 88)
            title:SetSize(92, 20)
            title:SetText(name)
            title:SetMouseInputEnabled(false)
            card.DoClick = function()
                self.ModelFolder:SetValue(string.match(path, "^(.*[/])"))
                self.ModelPath:SetValue(path)
                self:Message("Selected " .. path .. ". Use ADD PROP to place it.")
                browser:Close()
            end
        end
        grid:InvalidateLayout(true)
    end
    local function navigate(requested)
        local requestedFolder = string.Trim(requested)
        if string.sub(requestedFolder, -1) ~= "/" then requestedFolder = requestedFolder .. "/" end
        if not validModelFolder(requestedFolder) then
            self:Message("Enter a mounted folder under models/, without parent-directory segments.", true)
            return
        end
        local found, directories = file.Find(requestedFolder .. "*", "GAME")
        if type(found) ~= "table" or type(directories) ~= "table" then
            self:Message("Could not browse model folder: " .. requestedFolder, true)
            return
        end
        folder, filenames, page = requestedFolder, {}, 1
        for _, name in ipairs(found) do
            if string.match(string.lower(name), "%.mdl$") then filenames[#filenames + 1] = folder .. name end
        end
        table.sort(filenames)
        table.sort(directories)
        folderInput:SetValue(folder)
        folders:Clear()
        for _, name in ipairs(directories) do
            local row = folders:AddLine(name)
            row.Folder = folder .. name .. "/"
        end
        refresh()
    end
    folders.OnRowSelected = function(_, _, row) navigate(row.Folder) end
    up.DoClick = function()
        local parent = string.match(folder, "^(models/.+)/[^/]+/$") or "models/"
        navigate(parent)
    end
    go.DoClick = function() navigate(folderInput:GetValue()) end
    folderInput.OnEnter = function() navigate(folderInput:GetValue()) end
    previous.DoClick = function() page = page - 1; refresh() end
    nextPage.DoClick = function() page = page + 1; refresh() end
    globalSearch.OnChange = function(_, checked)
        globalEnabled, page = checked, 1
        search:SetPlaceholderText(checked and "Search all mounted model paths" or "Search models in this folder")
        if checked and not indexQueue and not indexFailure then indexQueue = { "models/" } end
        refresh()
    end
    search.OnValueChange = function() page = 1; browser.SearchAt = RealTime() + 0.2 end
    browser.Think = function()
        if globalEnabled and string.Trim(search:GetValue()) ~= ""
            and indexQueue and not indexFailure and indexCursor <= #indexQueue then
            local deadline = SysTime() + 0.002
            for _ = 1, 4 do
                local current = indexQueue[indexCursor]
                if not current then break end
                local found, directories = file.Find(current .. "*", "GAME")
                if type(found) ~= "table" or type(directories) ~= "table" then
                    indexFailure = "Could not scan mounted model folder: " .. current
                    self:Message(indexFailure, true)
                    break
                end
                for _, name in ipairs(found) do
                    if string.match(string.lower(name), "%.mdl$") then indexPaths[#indexPaths + 1] = current .. name end
                end
                table.sort(directories)
                for _, name in ipairs(directories) do
                    if name ~= "." and name ~= ".." then
                        local child = current .. name .. "/"
                        if string.find(name, "/", 1, true) or not validModelFolder(child) then
                            indexFailure = "Cannot safely scan mounted model folder: " .. child
                            self:Message(indexFailure, true)
                            break
                        end
                        indexQueue[#indexQueue + 1] = child
                    end
                end
                indexCursor = indexCursor + 1
                if indexFailure or SysTime() >= deadline then break end
            end
            nextIndexRefresh = nextIndexRefresh or RealTime() + 0.25
            if indexFailure or indexCursor > #indexQueue or RealTime() >= nextIndexRefresh then
                nextIndexRefresh = nil
                refresh()
            end
        end
        if browser.SearchAt and RealTime() >= browser.SearchAt then
            browser.SearchAt = nil
            refresh()
        end
    end
    navigate(folderInput:GetValue())
end

function Editor:GetPropBounds(index)
    local prop = self.Document.props[index]
    local model = self.Models[index]
    if not prop or not IsValid(model) then return nil end
    if prop.scale == 1 then return model:OBBMins(), model:OBBMaxs() end
    local minimum, maximum = model:GetModelBounds()
    return minimum * prop.scale, maximum * prop.scale
end

function Editor:FindPropAt(x, y)
    local view = self:GetView(90)
    local direction = gui.ScreenToVector(x, y) * 10000
    local chosen, closest
    for index, model in ipairs(self.Models) do
        if IsValid(model) then
            local minimum, maximum = self:GetPropBounds(index)
            local _, _, fraction = util.IntersectRayWithOBB(view.origin, direction,
                model:GetPos(), model:GetAngles(), minimum, maximum)
            if fraction and (not closest or fraction < closest) then chosen, closest = index, fraction end
        end
    end
    return chosen
end

function Editor:SelectAt(x, y)
    local chosen = self:FindPropAt(x, y)
    if chosen ~= self.Selected then self:StopRotation() end
    self.Selected = chosen
    self:RefreshInspector()
    return chosen
end

function Editor:CycleMode()
    if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
    self.Drag, self.RotationSelection = nil, nil
    self.Mode = ({ move = "rotate", rotate = "scale", scale = "move" })[self.Mode]
    if IsValid(self.ModeButton) then self.ModeButton:SetText("MODE: " .. string.upper(self.Mode)) end
    if self.Mode == "move" then
        self:Message("Move: drag an axis.")
    elseif self.Mode == "rotate" then
        self:Message("Rotate: click a ring, then drag anywhere in the viewport.")
    else
        self:Message("Uniform scale: drag any axis. Snapping uses 0.1 increments.")
    end
end

function Editor:ClearRotationSelection()
    self.RotationSelection = nil
    if self.Mode == "rotate" and IsValid(self.ModeButton) then self.ModeButton:SetText("MODE: ROTATE") end
end

function Editor:StopRotation()
    if self.Drag and self.Drag.kind == "rotate" then
        if IsValid(self.Drag.panel) then self.Drag.panel:MouseCapture(false) end
        self.Drag = nil
    end
    self:ClearRotationSelection()
end

function Editor:ReleaseDrag(panel, mouseCode)
    local drag = self.Drag
    if drag and mouseCode and drag.mouseCode ~= mouseCode then return end
    if drag and drag.kind == "rotate" then self:UpdateDrag() end
    self.Drag = nil
    panel:MouseCapture(false)
    if drag and drag.kind == "rotate" and not drag.moved and not drag.onSelectedRing then
        self:ClearRotationSelection()
        local hit = self:FindPropAt(drag.x, drag.y)
        self.LastPropClick = hit and { index = hit, time = drag.time, x = drag.x, y = drag.y } or nil
        self:Message("Rotation ring deselected.")
    end
end

function Editor:CancelRotation()
    local drag = self.Drag
    if not drag or drag.kind ~= "rotate" then return end
    local prop = self.Document and self.Document.props[drag.index]
    if prop and prop.angles[drag.key] ~= drag.initial then
        prop.angles[drag.key] = drag.initial
        self:UpdateModel(drag.index)
        self:MarkChanged()
        self:RefreshInspector()
    end
    if IsValid(drag.panel) then drag.panel:MouseCapture(false) end
    self.Drag = nil
    self:Message("Rotation drag cancelled; ring remains selected.")
end

function Editor:GetRotationBasis(prop, axis)
    if axis == "x" then
        local angle = Angle(prop.angles.p, prop.angles.y, 0)
        return angle:Forward(), angle:Right() * -1, angle:Up()
    elseif axis == "y" then
        local angle = Angle(0, prop.angles.y, 0)
        return angle:Right() * -1, angle:Up(), angle:Forward()
    end
    return axes.z, axes.x, axes.y
end

function Editor:RotationAngleAt(x, y, pivot, normal, first, second)
    local view = self:GetView(90)
    local hit = util.IntersectRayWithPlane(view.origin, gui.ScreenToVector(x, y), pivot, normal)
    if not hit then return nil end
    local offset = hit - pivot
    return Gizmo.RingAngle(offset:Dot(first), offset:Dot(second))
end

function Editor:ResetRotation(index)
    local prop = self.Document.props[index]
    if not prop then return end
    self.Selected, self.LastPropClick = index, nil
    self:ClearRotationSelection()
    if prop.angles.p ~= 0 or prop.angles.y ~= 0 or prop.angles.r ~= 0 then
        prop.angles.p, prop.angles.y, prop.angles.r = 0, 0, 0
        self:UpdateModel(index)
        self:MarkChanged()
    end
    self:RefreshInspector()
    self:Message("Rotation reset to the model's default orientation.")
end

local function nearestGizmoSegment(points, x, y)
    local nearest, selectedStart, selectedFinish
    for _, segment in ipairs(points.segments or { points }) do
        if segment.start.visible and segment.finish.visible then
            local distance = Gizmo.DistanceToSegment(x, y, segment.start.x, segment.start.y,
                segment.finish.x, segment.finish.y)
            if distance <= 12 and (not nearest or distance < nearest) then
                nearest, selectedStart, selectedFinish = distance, segment.start, segment.finish
            end
        end
    end
    return nearest, selectedStart, selectedFinish
end

function Editor:BeginDrag(panel, mouseCode)
    local x, y = gui.MousePos()
    if self.Drag and self.Drag.kind == "rotate" then
        if mouseCode == MOUSE_RIGHT then
            self:CancelRotation()
        elseif mouseCode == MOUSE_MIDDLE then
            local hit = self:FindPropAt(x, y)
            if hit == self.Drag.index then
                self:CancelRotation()
                self:ResetRotation(hit)
            end
        end
        return
    end
    if mouseCode == MOUSE_RIGHT then
        self.LastPropClick = nil
        self.Drag = { kind = "camera", panel = panel, mouseCode = mouseCode,
            x = x, y = y, yaw = self.CameraYaw, pitch = self.CameraPitch }
    elseif mouseCode == MOUSE_MIDDLE then
        local hit = self:FindPropAt(x, y)
        if hit then
            if self.Drag then self:ReleaseDrag(panel) end
            self:ResetRotation(hit)
        end
    elseif mouseCode == MOUSE_LEFT then
        local now = RealTime()
        local selection = self.RotationSelection
        if self.Mode == "rotate" and selection and selection.index == self.Selected then
            local prop, model = self.Document.props[selection.index], self.Models[selection.index]
            local normal, first, second = self:GetRotationBasis(prop, selection.axis)
            local pivot = model:GetPos()
            local points = self.GizmoPoints and self.GizmoPoints[selection.axis]
            local onSelectedRing = points and nearestGizmoSegment(points, x, y) ~= nil or false
            local angle = self:RotationAngleAt(x, y, pivot, normal, first, second)
            if angle == nil then self:Message("Cannot rotate from this view. Orbit the camera and try again.") end
            self.Drag = { kind = "rotate", panel = panel, mouseCode = mouseCode,
                index = selection.index, axis = selection.axis, time = now,
                x = x, y = y, key = selection.key, initial = prop.angles[selection.key],
                pivot = pivot, normal = normal, first = first, second = second,
                previousAngle = angle,
                totalAngle = 0, moved = false, onSelectedRing = onSelectedRing }
            panel:MouseCapture(true)
            return
        end
        local chosen, nearest, chosenStart, chosenFinish
        for _, axis in ipairs({ "x", "y", "z" }) do
            local points = self.GizmoPoints and self.GizmoPoints[axis]
            if points then
                local distance, first, second = nearestGizmoSegment(points, x, y)
                if distance and (not nearest or distance < nearest) then
                    chosen, nearest, chosenStart, chosenFinish = axis, distance, first, second
                end
            end
        end
        local prop = self.Document.props[self.Selected or 0]
        if self.Mode == "rotate" and chosen and prop then
            self.LastPropClick = nil
            self.RotationSelection = { axis = chosen, index = self.Selected, key = ({ x = "r", y = "p", z = "y" })[chosen] }
            if IsValid(self.ModeButton) then self.ModeButton:SetText("ROTATE " .. string.upper(chosen) .. " SELECTED") end
            self:Message("Drag anywhere in the viewport to rotate; click elsewhere to deselect.")
            return
        end
        local hit = self:FindPropAt(x, y)
        local previous = self.LastPropClick
        if hit and previous and previous.index == hit and now >= previous.time and now - previous.time <= 0.35
            and (x - previous.x) ^ 2 + (y - previous.y) ^ 2 <= 64 then
            self.LastPropClick = nil
            self.Selected = hit
            self:CycleMode()
            self:RefreshInspector()
            return
        end
        self.LastPropClick = hit and { index = hit, time = now, x = x, y = y } or nil
        if chosen and prop then
            local group = self.Mode == "move" and "position" or nil
            local key = self.Mode == "move" and chosen or "scale"
            self.Drag = { kind = self.Mode, panel = panel, mouseCode = mouseCode, axis = chosen, x = x, y = y,
                axisX = chosenFinish.x - chosenStart.x, axisY = chosenFinish.y - chosenStart.y,
                group = group, key = key, initial = group and prop[group][key] or prop[key] }
        else
            self.Selected = hit
            self:RefreshInspector()
        end
    end
    if self.Drag then panel:MouseCapture(true) end
end

function Editor:UpdateDrag()
    local drag = self.Drag
    if not drag then return end
    local x, y = gui.MousePos()
    if (x - drag.x) ^ 2 + (y - drag.y) ^ 2 > 16 then self.LastPropClick = nil end
    if drag.kind == "camera" then
        self.CameraYaw = drag.yaw - (x - drag.x) * 0.3
        self.CameraPitch = math.Clamp(drag.pitch + (y - drag.y) * 0.3, 15, 85)
        return
    end
    local prop = self.Document.props[self.Selected or 0]
    if not prop then return end
    if drag.kind == "rotate" then
        if not drag.moved then
            if (x - drag.x) ^ 2 + (y - drag.y) ^ 2 <= 16 then return end
            drag.moved = true
        end
        local angle = self:RotationAngleAt(x, y, drag.pivot, drag.normal, drag.first, drag.second)
        if angle == nil then
            if not drag.warned then
                self:Message("Cannot rotate from this view. Orbit the camera and try again.")
                ErrorNoHalt("[ZombieSim] Prefab editor: rotation ray does not intersect the selected plane.\n")
                drag.warned = true
            end
            return
        end
        if drag.previousAngle == nil then drag.previousAngle = angle return end
        drag.totalAngle = drag.totalAngle + Gizmo.AngleDelta(drag.previousAngle, angle)
        drag.previousAngle = angle
        local value = drag.initial + drag.totalAngle
        if self.SnapEnabled then value = Gizmo.Snap(value, self.RotationSnap) end
        if value ~= prop.angles[drag.key] then
            prop.angles[drag.key] = value
            self:UpdateModel(self.Selected)
            self:MarkChanged()
            self:RefreshInspector()
        end
        return
    end
    local delta
    delta = Gizmo.AxisDelta(x - drag.x, y - drag.y, drag.axisX, drag.axisY, axisLength)
    if delta == nil then return end
    if drag.kind == "scale" then
        local value = drag.initial + delta / axisLength
        if self.SnapEnabled then value = Gizmo.Snap(value, 0.1) end
        value = math.Clamp(value, Contract.MinScale, Contract.MaxScale)
        if value ~= prop.scale then
            prop.scale = value
            self:UpdateModel(self.Selected)
            self:MarkChanged()
            self:RefreshInspector()
        end
        return
    end
    local step = drag.kind == "move" and self.PositionSnap or self.RotationSnap
    local value = self.SnapEnabled and Gizmo.Snap(drag.initial + delta, step) or drag.initial + delta
    if value ~= prop[drag.group][drag.key] then
        prop[drag.group][drag.key] = value
        self:UpdateModel(self.Selected)
        self:MarkChanged()
        self:RefreshInspector()
    end
end

function Editor:GetView(fov)
    local angles = Angle(self.CameraPitch or 55, self.CameraYaw or 45, 0)
    local center = self.Origin + Vector(0, 0, 40)
    return { origin = center - angles:Forward() * (self.CameraDistance or 1000),
        angles = angles, fov = fov, drawviewer = false, drawviewmodel = false }
end

function Editor:GetInnerCityFog()
    local worldData = ZM_World and ZM_World:GetData()
    local profiles = worldData and worldData.atmosphereProfiles
    if type(profiles) ~= "table" then return nil, "Preview world atmosphere profiles are unavailable." end
    for index = 0, #profiles - 1 do
        local profile = ZM_World:GetAtmosphereProfileByIndex(index)
        if profile and profile.id == "inner_city" then
            local fog = profile.fog
            if type(fog) ~= "table" or type(fog.start) ~= "number" or type(fog["end"]) ~= "number"
                or type(fog.maxDensity) ~= "number" or type(fog.color) ~= "table"
                or type(fog.color[1]) ~= "number" or type(fog.color[2]) ~= "number"
                or type(fog.color[3]) ~= "number" then
                return nil, "The inner-city fog profile is invalid."
            end
            return { start = fog.start, finish = fog["end"], maxDensity = fog.maxDensity,
                color = { fog.color[1], fog.color[2], fog.color[3] } }
        end
    end
    return nil, "The inner-city fog profile is unavailable."
end

function Editor:BuildGrid(height)
    self.GridHeight = height
    self.GridLines = {}
    local gridOrigin = self.Origin + Vector(0, 0, height)
    for offset = -320, 320, 64 do
        self.GridLines[#self.GridLines + 1] = {
            gridOrigin + Vector(offset, -320, 0), gridOrigin + Vector(offset, 320, 0)
        }
        self.GridLines[#self.GridLines + 1] = {
            gridOrigin + Vector(-320, offset, 0), gridOrigin + Vector(320, offset, 0)
        }
    end
end

function Editor:ClearReference()
    if IsValid(self.ReferenceModel) then self.ReferenceModel:Remove() end
    self.ReferenceModel = nil
    if self.Origin then self:BuildGrid(1) end
end

function Editor:SetReference(path)
    self:ClearReference()
    local model = ClientsideModel(path, RENDERGROUP_OTHER)
    if not IsValid(model) then
        self:Message("Could not display reference tile: " .. tostring(path), true)
        return false
    end
    local maximum = model:OBBMaxs()
    if not maximum or type(maximum.z) ~= "number" or maximum.z ~= maximum.z
        or maximum.z == math.huge or maximum.z == -math.huge then
        model:Remove()
        self:Message("Reference tile has invalid bounds: " .. tostring(path), true)
        return false
    end
    model:SetNoDraw(true)
    model:SetPos(self.Origin)
    model:SetAngles(Angle(0, 0, 0))
    self.ReferenceModel = model
    self:BuildGrid(math.max(1, maximum.z + 1))
    return true
end

function Editor:SetReferenceChoices(references)
    if not IsValid(self.ReferenceChoice) then return end
    self.ReferenceChoice:Clear()
    self.ReferenceChoice:AddChoice("No reference", "")
    for _, reference in ipairs(references) do
        self.ReferenceChoice:AddChoice(reference.label, reference.model)
    end
    self.ReferenceChoice:SetValue("No reference")
end

function Editor:Open(data)
    if self:IsActive() then return end
    if type(data) ~= "table" or type(data.origin) ~= "table" or type(data.documents) ~= "table"
        or type(data.origin.x) ~= "number" or type(data.origin.y) ~= "number" or type(data.origin.z) ~= "number" then
        self:Message("The editor workspace response is invalid.", true)
        return
    end
    self.Active = true
    self.Origin = Vector(data.origin.x, data.origin.y, data.origin.z)
    self.CameraYaw, self.CameraPitch, self.CameraDistance = 45, 55, 1000
    self.PositionSnap, self.RotationSnap, self.SnapEnabled = 16, 15, true
    self.Mode, self.Models, self.Revision, self.LastPropClick = "move", {}, 0, nil
    self.PreviewFog, self.PreviewDark = nil, false
    self:BuildGrid(1)

    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetTitle("")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame.Paint = function() end
    frame:MakePopup()
    frame.OnRemove = function()
        if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
        self:ClearModels()
        if IsValid(self.ReferenceModel) then self.ReferenceModel:Remove() end
        self.ReferenceModel, self.ReferenceWanted = nil, nil
        self.Active, self.Frame, self.Drag, self.GridLines, self.LastPropClick, self.RotationSelection =
            false, nil, nil, nil, nil, nil
        self.PreviewFog, self.PreviewDark = nil, false
    end
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then self:Exit() end
    end

    local left = vgui.Create("DScrollPanel", frame)
    left:Dock(LEFT)
    left:SetWide(290)
    left.Paint = function(_, w, h) surface.SetDrawColor(20, 23, 28, 240); surface.DrawRect(0, 0, w, h) end
    label(left, "PREFABS")
    button(left, "OPEN PREFAB EXPLORER", function() ZM_PrefabExplorer:Open() end)
    self.PrefabList = vgui.Create("DListView", left)
    self.PrefabList:Dock(TOP)
    self.PrefabList:DockMargin(6, 2, 6, 2)
    self.PrefabList:SetTall(110)
    self.PrefabList:AddColumn("Name")
    self.PrefabList:AddColumn("ID")
    self.PrefabList.OnRowSelected = function(_, _, row)
        self:ConfirmDiscard(function() send("load", row.PrefabId) end)
    end
    button(left, "NEW PREFAB", function()
        self:ConfirmDiscard(function()
            if send("new") then self:SetDocument(blankDocument(), nil) end
        end)
    end)
    self.IdInput = textEntry(left, "ID (lowercase, numbers, - or _)", function(value)
        self.Document.id = value; self:MarkChanged()
    end)
    self.NameInput = textEntry(left, "Name", function(value) self.Document.name = value; self:MarkChanged() end)
    self.DescriptionInput = textEntry(left, "Description", function(value)
        self.Document.description = value; self:MarkChanged()
    end)
    self.TagsInput = textEntry(left, "Tags (comma separated)", function(value)
        self.Document.tags = parseTags(value); self:MarkChanged()
    end)
    button(left, "SAVE", function() self:Save(false) end)
    button(left, "DELETE SAVED PREFAB", function()
        if not self.OpenedId then self:Message("Open a saved prefab before deleting it.", true) return end
        local id = self.OpenedId
        Derma_Query("Permanently delete prefab '" .. id .. "'?", "Prefab editor",
            "Delete", function() send("delete", id) end, "Cancel", function() end)
    end)
    label(left, "MODEL BROWSER")
    self.ModelFolder = textEntry(left, "Mounted folder", function() end)
    self.ModelFolder:SetValue("models/props_c17/")
    button(left, "OPEN MODEL BROWSER", function() self:OpenModelBrowser() end)
    self.ModelPath = textEntry(left, "Model path", function() end)
    button(left, "ADD PROP", function() send("model", string.Trim(self.ModelPath:GetValue())) end)
    label(left, "REFERENCE TILE (NOT SAVED)")
    self.ReferenceChoice = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", left))
    self.ReferenceChoice:Dock(TOP)
    self.ReferenceChoice:DockMargin(6, 0, 6, 2)
    self.ReferenceChoice:SetTall(24)
    self.ReferenceChoice:AddChoice("No reference", "")
    self.ReferenceChoice:SetValue("No reference")
    self.ReferenceChoice.OnSelect = function(_, _, _, path)
        self.ReferenceWanted = path
        self:ClearReference()
        if path ~= "" then send("reference", path) end
    end
    button(left, "RETURN TO LAUNCHER", function() self:Exit() end)

    local right = vgui.Create("DScrollPanel", frame)
    right:Dock(RIGHT)
    right:SetWide(260)
    right.Paint = function(_, w, h) surface.SetDrawColor(20, 23, 28, 240); surface.DrawRect(0, 0, w, h) end
    label(right, "PROPS")
    self.PropList = vgui.Create("DListView", right)
    self.PropList:Dock(TOP)
    self.PropList:DockMargin(6, 2, 6, 2)
    self.PropList:SetTall(100)
    self.PropList:AddColumn("Model")
    self.PropList.OnRowSelected = function(_, _, row)
        if row.PrefabIndex ~= self.Selected then self:StopRotation() end
        self.Selected = row.PrefabIndex
        self:RefreshInspector()
    end
    self.MovableToggle = vgui.Create("DCheckBoxLabel", right)
    self.MovableToggle:Dock(TOP)
    self.MovableToggle:DockMargin(6, 3, 6, 3)
    self.MovableToggle:SetText("Movable physics prop")
    self.MovableToggle.OnChange = function(_, checked)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if self.Refreshing or not prop or prop.movable == checked then return end
        prop.movable = checked
        self:MarkChanged()
    end
    label(right, "Prop loot")
    self.LootMode = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", right))
    self.LootMode:Dock(TOP)
    self.LootMode:DockMargin(6, 0, 6, 2)
    self.LootMode:SetTall(24)
    self.LootMode:AddChoice("Off", "off")
    self.LootMode:AddChoice("Normal", "normal")
    self.LootMode:AddChoice("Guaranteed", "guaranteed")
    self.LootMode.OnSelect = function(_, _, _, mode)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if self.Refreshing or not prop or prop.lootMode == mode then return end
        prop.lootMode = mode
        self:MarkChanged()
        self:RefreshInspector()
    end
    self.LootGroup = textEntry(right, "Loot group override (optional)", function(value)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if not prop then return end
        value = string.Trim(value)
        prop.lootGroup = value ~= "" and value or nil
        self:MarkChanged()
    end)
    self.LootChanceToggle = vgui.Create("DCheckBoxLabel", right)
    self.LootChanceToggle:Dock(TOP)
    self.LootChanceToggle:DockMargin(6, 3, 6, 3)
    self.LootChanceToggle:SetText("Override normal activation chance")
    self.LootChanceToggle.OnChange = function(_, checked)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if self.Refreshing or not prop or prop.lootMode ~= "normal" then return end
        if checked and prop.lootChance == nil then prop.lootChance = 0.4
        elseif not checked then prop.lootChance = nil end
        self:MarkChanged()
        self:RefreshInspector()
    end
    button(right, "REMOVE SELECTED", function()
        if not self.Selected then return end
        self:StopRotation()
        local model = self.Models[self.Selected]
        if IsValid(model) then model:Remove() end
        table.remove(self.Models, self.Selected)
        table.remove(self.Document.props, self.Selected)
        self.Selected, self.LastPropClick = nil, nil; self:MarkChanged(); self:RefreshInspector()
    end)
    self.ModeButton = button(right, "MODE: MOVE", function() self:CycleMode() end)
    label(right, "Double-click a prop to cycle modes")
    label(right, "Rotation: select ring, drag, click elsewhere to finish")
    label(right, "Rotation axes: X roll, Y pitch, Z yaw")
    local snap = vgui.Create("DCheckBoxLabel", right)
    snap:Dock(TOP); snap:DockMargin(6, 3, 6, 3); snap:SetText("Enable snapping"); snap:SetValue(1)
    snap.OnChange = function(_, checked) self.SnapEnabled = checked end
    local fog = vgui.Create("DCheckBoxLabel", right)
    fog:Dock(TOP); fog:DockMargin(6, 3, 6, 3); fog:SetText("Preview inner-city fog"); fog:SetValue(0)
    fog.OnChange = function(control, checked)
        if not checked then self.PreviewFog = nil return end
        local settings, problem = self:GetInnerCityFog()
        if not settings then
            control:SetValue(0)
            self:Message(problem, true)
            return
        end
        self.PreviewFog = settings
    end
    self.FogToggle = fog
    local dark = vgui.Create("DCheckBoxLabel", right)
    dark:Dock(TOP); dark:DockMargin(6, 3, 6, 3); dark:SetText("Dark preview (simulated)"); dark:SetValue(0)
    dark.OnChange = function(_, checked) self.PreviewDark = checked end
    self.DarkToggle = dark
    local function number(title, minimum, maximum, decimals, action)
        label(right, title)
        local control = vgui.Create("DNumberWang", right)
        control:Dock(TOP); control:DockMargin(6, 0, 6, 2); control:SetTall(24)
        control:SetMin(minimum); control:SetMax(maximum); control:SetDecimals(decimals)
        control.OnValueChanged = function(_, value)
            if not self.Refreshing then action(tonumber(value)) end
        end
        return control
    end
    local positionSnap = number("Position snap (units)", 0, 640, 2, function(value)
        if value ~= nil then self.PositionSnap = value end
    end)
    positionSnap:SetValue(16)
    local rotationSnap = number("Rotation snap (degrees)", 0, 360, 2, function(value)
        if value ~= nil then self.RotationSnap = value end
    end)
    rotationSnap:SetValue(15)
    self.Inspector = {}
    for _, field in ipairs({
        { "X", "position", "x" }, { "Y", "position", "y" }, { "Z", "position", "z" },
        { "Pitch", "angles", "p" }, { "Yaw", "angles", "y" }, { "Roll", "angles", "r" },
        { "Skin", nil, "skin" }, { "Scale", nil, "scale" }
    }) do
        local group, key = field[2], field[3]
        local minimum = key == "skin" and 0 or key == "scale" and Contract.MinScale or -32768
        local maximum = key == "scale" and Contract.MaxScale or 32768
        local control = number(field[1], minimum, maximum, key == "skin" and 0 or 3,
            function(value)
                local prop = self.Document and self.Document.props[self.Selected or 0]
                if not prop or value == nil then return end
                if key == "scale" then value = math.Clamp(value, Contract.MinScale, Contract.MaxScale) end
                if group then prop[group][key] = value else prop[key] = value end
                self:UpdateModel(self.Selected); self:MarkChanged()
            end)
        self.Inspector[#self.Inspector + 1] = { control = control, group = group, key = key }
    end
    self.LootChance = number("Configured chance % (normal activation is halved)", 0, 100, 2, function(value)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if not prop or prop.lootMode ~= "normal" or prop.lootChance == nil or value == nil then return end
        prop.lootChance = math.Clamp(value, 0, 100) / 100
        self:MarkChanged()
    end)
    self.Status = label(right, "Right-drag: orbit. Wheel: zoom. Left-click: select.")
    self.Status:SetWrap(true)
    self.Status:SetTall(45)

    local viewport = vgui.Create("DPanel", frame)
    viewport:Dock(FILL)
    viewport.Paint = function() end
    viewport.OnMousePressed = function(panel, code) self:BeginDrag(panel, code) end
    viewport.OnMouseReleased = function(panel, code) self:ReleaseDrag(panel, code) end
    viewport.OnMouseWheeled = function(_, delta)
        self.CameraDistance = math.Clamp(self.CameraDistance - delta * 80, 350, 2400)
        return true
    end
    viewport.Think = function() self:UpdateDrag() end

    self:SetDocument(blankDocument(), nil)
    self:SetDocuments(data.documents)
    send("references")
    if data.openId then send("load", data.openId) end
end

function Editor:Begin(openId, onConfirm)
    Derma_Query("Open the prefab editor on gm_flatgrass? The preview launcher will reload on return.",
        "Prefab editor", "Open editor", function()
            if send("begin", openId) and onConfirm then onConfirm() end
        end, "Cancel", function() end)
end

net.Receive("ZM.PrefabEditorResponse", function()
    local action, success, message, encoded = net.ReadString(), net.ReadBool(), net.ReadString(), net.ReadString()
    if string.sub(action, 1, 9) == "explorer_" then
        local value = encoded ~= "" and util.JSONToTable(encoded) or nil
        if encoded ~= "" and type(value) ~= "table" then
            ZM_PrefabExplorer:OnResponse(action, false, "Invalid explorer response.")
        else
            ZM_PrefabExplorer:OnResponse(action, success, message, value)
        end
        return
    end
    if not success then
        if action == "save" then Editor.Saving, Editor.ExitAfterSave = false, false end
        if action == "reference" then
            Editor.ReferenceWanted = nil
            Editor:ClearReference()
            if IsValid(Editor.ReferenceChoice) then Editor.ReferenceChoice:SetValue("No reference") end
        end
        if action == "begin" and string.find(message, "previous prefab editor session", 1, true) then
            Derma_Query(message .. "\nClear the old session marker?", "Prefab editor",
                "Clear marker", function() send("recover") end, "Cancel", function() end)
        elseif action == "status" then
            Derma_Query(message, "Prefab editor", "Retry", function() send("status") end,
                "Return to launcher", function() send("end") end)
        else
            Editor:Message(message, true)
        end
        return
    end
    local data = encoded ~= "" and util.JSONToTable(encoded) or nil
    if encoded ~= "" and type(data) ~= "table" then Editor:Message("Invalid editor response.", true) return end
    if action == "status" then
        Editor:Open(data)
    elseif action == "list" then
        Editor:SetDocuments(data)
    elseif action == "load" then
        Editor:SetDocument(data, data.id)
    elseif action == "model" then
        Editor:StopRotation()
        if not Contract.IsValidId(data.propId) then
            Editor:Message("The server returned an invalid prop ID.", true)
            return
        end
        local prop = { model = data.model, position = { x = 0, y = 0, z = 0 },
            angles = { p = 0, y = 0, r = 0 }, skin = 0, scale = 1, movable = false,
            propId = data.propId, lootMode = "off" }
        Editor.Document.props[#Editor.Document.props + 1] = prop
        Editor.Selected = #Editor.Document.props
        Editor:MakeModel(Editor.Selected)
        Editor:MarkChanged(); Editor:RefreshInspector()
    elseif action == "references" then
        Editor:SetReferenceChoices(data)
    elseif action == "reference" then
        if data.model == Editor.ReferenceWanted and not Editor:SetReference(data.model) then
            Editor.ReferenceWanted = nil
            Editor.ReferenceChoice:SetValue("No reference")
        end
    elseif action == "save" then
        Editor.Saving = false
        Editor.OpenedId = Editor.PendingSaveId
        Editor.Dirty = Editor.Revision ~= Editor.SaveRevision
        Editor:RefreshDocument()
        Editor:Message(message)
        send("list")
        if Editor.ExitAfterSave and not Editor.Dirty then send("end") end
        Editor.ExitAfterSave = false
    elseif action == "delete" then
        Editor:SetDocument(blankDocument(), nil)
        Editor:Message(message)
        send("list")
    elseif action == "recover" then
        Editor:Message(message)
    end
end)

hook.Add("Think", "ZM.PrefabEditor.WaitForSession", function()
    local ply = LocalPlayer()
    if game.GetMap() ~= "gm_flatgrass" or not IsValid(ply) or not ply:GetNWBool("ZM.PrefabEditorActive", false) then return end
    if Editor.RequestedStatus then return end
    Editor.RequestedStatus = true
    send("status")
end)

hook.Add("HUDShouldDraw", "ZM.PrefabEditor.HideHud", function()
    if Editor:IsSession() then return false end
end)

hook.Add("PostDrawTranslucentRenderables", "ZM.PrefabEditor.Render", function(depth, skybox)
    if depth or skybox or not Editor:IsActive() then return end
    if IsValid(Editor.ReferenceModel) then Editor.ReferenceModel:DrawModel() end
    for _, line in ipairs(Editor.GridLines) do render.DrawLine(line[1], line[2], gridColor, true) end
    cam.Start3D2D(Editor.Origin + Vector(0, 0, Editor.GridHeight + 1), compassAngle, 1)
    for _, direction in ipairs(compassLabels) do
        draw.SimpleText(direction.text, "ZM_PrefabCompass", direction.x, direction.y,
            gridColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    cam.End3D2D()
    for _, model in ipairs(Editor.Models) do if IsValid(model) then model:DrawModel() end end
    local selected = Editor.Models[Editor.Selected or 0]
    Editor.GizmoPoints = {}
    if not IsValid(selected) then return end
    local minimum, maximum = Editor:GetPropBounds(Editor.Selected)
    render.DrawWireframeBox(selected:GetPos(), selected:GetAngles(), minimum, maximum, selectionColor, true)
    local start = selected:GetPos()
    if Editor.Mode == "rotate" then
        local prop = Editor.Document.props[Editor.Selected]
        for name in pairs(axes) do
            local _, first, second = Editor:GetRotationBasis(prop, name)
            local ringColor = Editor.RotationSelection and Editor.RotationSelection.axis == name
                and selectionColor or axisColors[name]
            local segments = {}
            local previousPosition, previousScreen
            for _, components in ipairs(rotationCircle) do
                local position = start + first * components[1] + second * components[2]
                local screen = position:ToScreen()
                if previousPosition then
                    render.DrawLine(previousPosition, position, ringColor, true)
                    segments[#segments + 1] = { start = previousScreen, finish = screen }
                end
                previousPosition, previousScreen = position, screen
            end
            Editor.GizmoPoints[name] = { segments = segments }
        end
    else
        for name, direction in pairs(axes) do
            local finish = start + direction * axisLength
            render.DrawLine(start, finish, axisColors[name], true)
            if Editor.Mode == "move" then
                local base = finish - direction * 16
                local wing = arrowWings[name] * 7
                render.DrawLine(finish, base + wing, axisColors[name], true)
                render.DrawLine(finish, base - wing, axisColors[name], true)
            else
                render.DrawWireframeBox(finish, compassAngle, scaleHandleMin, scaleHandleMax, axisColors[name], true)
            end
            Editor.GizmoPoints[name] = { start = start:ToScreen(), finish = finish:ToScreen() }
        end
    end
end)

concommand.Add("zombiesim_prefab_editor_open", function()
    local ply = LocalPlayer()
    if IsValid(ply) and ply:GetNWBool("ZM.PrefabEditorActive", false) then send("status") end
end)
