ZM_PrefabExplorer = ZM_PrefabExplorer or {}
local Explorer = ZM_PrefabExplorer

local function label(parent, text, height)
    local control = vgui.Create("DLabel", parent)
    control:Dock(TOP)
    control:DockMargin(6, 4, 6, 2)
    control:SetTall(height or 20)
    control:SetText(text)
    control:SetWrap(true)
    return control
end

local function button(parent, text, action)
    local control = vgui.Create("DButton", parent)
    control:Dock(TOP)
    control:DockMargin(6, 3, 6, 2)
    control:SetTall(24)
    control:SetText(text)
    control.DoClick = action
    return control
end

function Explorer:Request(action, text, extra)
    return ZM_PrefabEditorClient:RequestExplorer(action, text, extra)
end

function Explorer:ClearPreview()
    for _, entity in ipairs(self.PreviewModels or {}) do
        if IsValid(entity) then entity:Remove() end
    end
    self.PreviewModels = {}
    if IsValid(self.Preview) then self.Preview:Remove() end
    self.Preview = nil
end

function Explorer:RefreshList()
    if not IsValid(self.List) then return end
    self.List:Clear()
    local search = string.lower(string.Trim(self.Search:GetValue()))
    local tag = string.lower(string.Trim(self.Tag:GetValue()))
    for _, document in ipairs(self.Documents or {}) do
        local haystack = string.lower(document.name .. " " .. document.id .. " " .. document.description)
        local tagMatches = tag == ""
        for _, entry in ipairs(document.tags) do
            if string.lower(entry) == tag then tagMatches = true break end
        end
        if tagMatches and (search == "" or string.find(haystack, search, 1, true)) then
            local row = self.List:AddLine(document.name, document.id, table.concat(document.tags, ", "))
            row.PrefabId = document.id
        end
    end
end

function Explorer:ShowPreview(document)
    self:ClearPreview()
    self.Selected = document
    self.Details:SetText(document.name .. "  [" .. document.id .. "]\n" ..
        document.description .. "\nTags: " .. table.concat(document.tags, ", ") ..
        "\nDrag to orbit; mouse wheel zooms.")
    if #document.props == 0 then
        self.Details:SetText(self.Details:GetText() .. "\nThis prefab has no props.")
        return
    end
    local panel = vgui.Create("DModelPanel", self.Right)
    panel:Dock(FILL)
    panel:SetFOV(40)
    panel:SetModel(document.props[1].model)
    local first = panel:GetEntity()
    if not IsValid(first) then
        panel:Remove()
        self:Message("Could not display prefab model: " .. document.props[1].model)
        return
    end
    self.Preview = panel
    local extent = 320
    for index, prop in ipairs(document.props) do
        local model = index == 1 and first or ClientsideModel(prop.model, RENDERGROUP_OTHER)
        if not IsValid(model) then
            self:ClearPreview()
            self:Message("Could not display prefab model: " .. prop.model)
            return
        end
        if index > 1 then
            model:SetNoDraw(true)
            self.PreviewModels[#self.PreviewModels + 1] = model
        end
        local matrix = Matrix()
        matrix:Scale(Vector(prop.scale, prop.scale, prop.scale))
        model:EnableMatrix("RenderMultiply", matrix)
        model:SetPos(Vector(prop.position.x, prop.position.y, prop.position.z))
        model:SetAngles(Angle(prop.angles.p, prop.angles.y, prop.angles.r))
        model:SetSkin(prop.skin)
        local minimum, maximum = model:GetModelBounds()
        model:SetRenderBounds(minimum * prop.scale, maximum * prop.scale)
        local radius = math.max(minimum:Length(), maximum:Length()) * prop.scale
        extent = math.max(extent, math.abs(prop.position.x) + radius,
            math.abs(prop.position.y) + radius, math.abs(prop.position.z) + radius)
    end
    local yaw, pitch, distance = 45, 35, extent * 3.8
    local function updateCamera()
        panel:SetLookAt(Vector(0, 0, 0))
        panel:SetCamPos(Angle(pitch, yaw, 0):Forward() * -distance)
        panel.FarZ = math.max(4096, distance + extent * 4 + 10)
    end
    panel.LayoutEntity = function() end
    panel.PostDrawModel = function()
        for _, model in ipairs(self.PreviewModels) do if IsValid(model) then model:DrawModel() end end
    end
    panel.OnMousePressed = function(control, code)
        if code ~= MOUSE_LEFT then return end
        local x, y = gui.MousePos()
        control.Drag = { x = x, y = y, yaw = yaw, pitch = pitch }
        control:MouseCapture(true)
    end
    panel.OnMouseReleased = function(control, code)
        if code ~= MOUSE_LEFT then return end
        control.Drag = nil
        control:MouseCapture(false)
    end
    panel.Think = function(control)
        if not control.Drag then return end
        local x, y = gui.MousePos()
        yaw = control.Drag.yaw - (x - control.Drag.x) * 0.3
        pitch = math.Clamp(control.Drag.pitch + (y - control.Drag.y) * 0.3, -85, 85)
        updateCamera()
    end
    panel.OnMouseWheeled = function(_, delta)
        distance = math.Clamp(distance - delta * extent * 0.25, extent, extent * 10)
        updateCamera()
        return true
    end
    updateCamera()
end

function Explorer:Message(message)
    ErrorNoHalt("[ZombieSim] Prefab explorer: " .. tostring(message) .. "\n")
    Derma_Message(tostring(message), "Prefab explorer", "OK")
end

function Explorer:Open()
    if IsValid(self.Frame) then self.Frame:MakePopup() return end
    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSize(math.min(1000, ScrW() - 40), math.min(700, ScrH() - 40))
    frame:Center()
    frame:SetTitle("Prefab Explorer")
    frame:MakePopup()
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then frame:Close() end
    end
    frame.OnRemove = function()
        self:ClearPreview()
        self.Frame, self.List, self.Selected, self.Documents = nil, nil, nil, nil
        if ZM_PrefabEditorClient:IsActive() then
            ZM_PrefabEditorClient.Frame:MakePopup()
        elseif ZM_LauncherMenu and IsValid(ZM_LauncherMenu.Frame) then
            ZM_LauncherMenu.Frame:MakePopup()
        end
    end
    local left = vgui.Create("DPanel", frame)
    left:Dock(LEFT)
    left:SetWide(400)
    label(left, "Search name, ID or description")
    self.Search = vgui.Create("DTextEntry", left)
    self.Search:Dock(TOP)
    self.Search:SetUpdateOnType(true)
    self.Search.OnValueChange = function() self:RefreshList() end
    label(left, "Filter by exact tag")
    self.Tag = vgui.Create("DTextEntry", left)
    self.Tag:Dock(TOP)
    self.Tag:SetUpdateOnType(true)
    self.Tag.OnValueChange = function() self:RefreshList() end
    button(left, "REFRESH", function() self:Request("explorer_list") end)
    button(left, "RENAME", function()
        local selected = self.Selected
        if not selected or not selected.name then self:Message("Select a prefab and wait for its preview.") return end
        Derma_StringRequest("Rename prefab", "New display name (ID remains unchanged):", selected.name, function(name)
            Derma_Query("Rename '" .. selected.name .. "' to '" .. name .. "'?", "Rename prefab",
                "Rename", function() self:Request("explorer_rename", selected.id, name) end,
                "Cancel", function() end)
        end)
    end)
    button(left, "DELETE", function()
        local selected = self.Selected
        if not selected or not selected.name then self:Message("Select a prefab and wait for its preview.") return end
        Derma_Query("Delete '" .. selected.name .. "' [" .. selected.id .. "]?", "Delete prefab",
            "Delete", function() self:Request("explorer_delete", selected.id) end, "Cancel", function() end)
    end)
    button(left, "OPEN IN EDITOR", function()
        if not self.Selected or not self.Selected.name then
            self:Message("Select a prefab and wait for its preview.")
            return
        end
        local id = self.Selected.id
        if ZM_PrefabEditorClient:IsActive() then
            ZM_PrefabEditorClient:OpenSaved(id, function() frame:Close() end)
        else
            ZM_PrefabEditorClient:Begin(id, function() frame:Close() end)
        end
    end)
    self.List = vgui.Create("DListView", left)
    self.List:Dock(FILL)
    self.List:AddColumn("Name")
    self.List:AddColumn("ID")
    self.List:AddColumn("Tags")
    self.List.OnRowSelected = function(_, _, row)
        self.Selected = { id = row.PrefabId }
        self:ClearPreview()
        self:Request("explorer_preview", row.PrefabId)
    end
    self.Right = vgui.Create("DPanel", frame)
    self.Right:Dock(FILL)
    self.Details = label(self.Right, "Select a prefab to preview.", 90)
    self.PreviewModels = {}
    self:Request("explorer_list")
end

function Explorer:OnResponse(action, success, message, value)
    if not IsValid(self.Frame) then return end
    if not success then self:Message(message) return end
    if type(value) ~= "table" then self:Message("Invalid explorer response.") return end
    if action == "explorer_list" then
        self.Documents = value
        self:RefreshList()
    elseif action == "explorer_preview" then
        if self.Selected and self.Selected.id == value.id then self:ShowPreview(value) end
    elseif action == "explorer_rename" or action == "explorer_delete" then
        self:ClearPreview()
        self.Selected = nil
        self.Details:SetText(message)
        self:Request("explorer_list")
    end
end
