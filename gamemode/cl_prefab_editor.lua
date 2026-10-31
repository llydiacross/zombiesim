local Gizmo = include("prefabs/sh_gizmo.lua")
local Contract = include("prefabs/sh_contract.lua")
local EditorMap = include("prefabs/sh_editor_map.lua")(Contract)
local MapTransfer = include("prefabs/cl_editor_transfer.lua")({
    file = file, util = util, SysTime = SysTime, RealTime = RealTime
}, EditorMap)
ZM_PrefabEditorClient = ZM_PrefabEditorClient or {}
local Editor = ZM_PrefabEditorClient
local axisColors = { x = Color(235, 75, 75), y = Color(80, 210, 110), z = Color(80, 150, 255) }
local axes = { x = Vector(1, 0, 0), y = Vector(0, 1, 0), z = Vector(0, 0, 1) }
local arrowWings = { x = Vector(0, 0, 1), y = Vector(0, 0, 1), z = Vector(1, 0, 0) }
local scaleHandleMin, scaleHandleMax = Vector(-5, -5, -5), Vector(5, 5, 5)
local lightHandleMin, lightHandleMax = Vector(-8, -8, -8), Vector(8, 8, 8)
local particleColor = Color(120, 200, 255)
local gridColor = Color(125, 210, 190)
local selectionColor = Color(255, 220, 100)
local axisLength = 100
local modelPageSize = 48
local lootModeLabels = { off = "Off", normal = "Normal", guaranteed = "Guaranteed" }
local function finiteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
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

local function send(action, text, openedId, requestId)
    if #action + #(text or "") + #(openedId or "") + #(requestId or "") > 60000 then
        Derma_Message("The prefab request is too large to send to the server.", "Prefab editor", "OK")
        return false
    end
    net.Start("ZM.PrefabEditorRequest")
        net.WriteString(action)
        net.WriteString(text or "")
        net.WriteString(openedId or "")
        net.WriteString(requestId or "")
    net.SendToServer()
    return true
end

local function blankDocument()
    return { schemaVersion = 1, id = "", name = "", description = "", tags = {},
        props = {}, lights = {}, particles = {}, guards = {} }
end

local function defaultTabView()
    return {
        cameraYaw = 45, cameraPitch = 55, cameraDistance = 1000, panX = 0, panY = 0,
        positionSnap = 16, rotationSnap = 15, snapEnabled = true, gridSpacing = 64,
        showGrid = true, showCompass = true, previewFog = nil, previewDark = false,
        reference = nil, referenceOffset = 0, prefabOffset = 0, prefabOffsetX = 0, prefabOffsetY = 0
    }
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

local function styleList(list)
    local palette = ZM_DermaSkin.Palette
    list:SetHeaderHeight(20)
    list:SetDataHeight(20)
    list.Paint = function(_, w, h)
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
end

local function styleListRow(row, selected)
    local palette = ZM_DermaSkin.Palette
    row.PrefabSelected = selected == true
    row.Paint = function(panel, w, h)
        local active = panel.PrefabSelected or panel:IsLineSelected()
        surface.SetDrawColor(active and palette.redDark or panel.Hovered and palette.raised or palette.black)
        surface.DrawRect(0, 0, w, h)
    end
end

Editor.StyleList = styleList
Editor.StyleListRow = styleListRow

local function textEntry(parent, title, action)
    label(parent, title)
    local control = vgui.Create("DTextEntry", parent)
    control:Dock(TOP)
    control:DockMargin(6, 0, 6, 2)
    control:SetTall(24)
    control:SetUpdateOnType(true)
    control.OnValueChange = function(_, value)
        if not Editor.Refreshing and not Editor.SwitchingMap then action(value) end
    end
    return control
end

local function numberEntry(parent, title, minimum, maximum, decimals, action)
    label(parent, title)
    local control = vgui.Create("DNumberWang", parent)
    control:Dock(TOP)
    control:DockMargin(6, 0, 6, 2)
    control:SetTall(24)
    control:SetMin(minimum)
    control:SetMax(maximum)
    control:SetDecimals(decimals)
    control.OnValueChanged = function(_, value)
        if not Editor.Refreshing and not Editor.SwitchingMap then action(tonumber(value)) end
    end

    return control
end

local function numberRow(parent, title, fields, action)
    label(parent, title)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP); row:DockMargin(6, 0, 6, 2); row:SetTall(42)
    row.Paint = function() end
    local columns, controls = {}, {}
    for _, field in ipairs(fields) do
        local key = field[2]
        local column = vgui.Create("DPanel", row)
        column:Dock(LEFT)
        column.Paint = function() end
        local caption = vgui.Create("DLabel", column)
        caption:Dock(TOP); caption:SetTall(16); caption:SetText(field[1])
        local control = vgui.Create("DNumberWang", column)
        control:Dock(FILL); control:DockMargin(0, 0, 4, 0)
        control:SetMin(field[3] or -32768); control:SetMax(field[4] or 32768)
        control:SetDecimals(field[5] or 0)
        control.OnValueChanged = function(_, value)
            value = tonumber(value)
            if not Editor.Refreshing and not Editor.SwitchingMap and finiteNumber(value) then action(key, value) end
        end
        columns[#columns + 1], controls[key] = column, control
    end
    row.PerformLayout = function(_, width)
        for _, column in ipairs(columns) do column:SetWide(math.floor(width / #columns)) end
    end
    return controls
end

function Editor:IsActive()
    return self.Active == true and IsValid(self.Frame)
end

function Editor:IsSession()
    local ply = LocalPlayer()
    return IsValid(ply) and ply:GetNWBool("ZM.PrefabEditorActive", false)
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
    if self.ActiveTab then
        self.ActiveTab.Revision, self.ActiveTab.Dirty = self.Revision, true
        self:RefreshTabTitles()
    end
end

function Editor:ClearModels()
    for _, model in ipairs(self.Models or {}) do
        if IsValid(model) then model:Remove() end
    end
    for _, instance in pairs(self.GuardModels or {}) do
        ZM_PrefabGuardPreview:Remove(instance)
    end
    self.Models = {}
    self.GuardModels = {}
    self.SceneRefresh = true
end

function Editor:GetPreviewOrigin()
    return self.Origin + Vector(self.PrefabPreviewOffsetX or 0, self.PrefabPreviewOffsetY or 0,
        self.PrefabPreviewOffset or 0)
end

function Editor:UpdateModel(index)
    self.SceneRefresh = true
    if type(index) == "string" and string.match(index, "^guard:") then
        local guard = self:GetSelectedObject(index)
        local instance = guard and self.GuardModels[guard.guardId]
        if instance then
            local ok, problem = ZM_PrefabGuardPreview:Update(instance, guard, self:GetPreviewOrigin())
            if not ok then self:Message(problem, true) end
        end
        return
    end
    local prop = self.Document.props[index]
    local model = self.Models[index]
    if not prop or not IsValid(model) then return end
    model:SetPos(self:GetPreviewOrigin() + Vector(prop.position.x, prop.position.y, prop.position.z))
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

function Editor:GetSelectedObject(index)
    if not self.Document then return nil end
    index = index or self.Selected
    if not index then return nil end
    if type(index) == "string" then
        local guardId = string.match(index, "^guard:(.+)$")
        if guardId then
            for _, guard in ipairs(self.Document.guards) do
                if guard.guardId == guardId then return guard end
            end
            return nil
        end
        local id = string.match(index, "^particle:(.+)$")
        for _, particle in ipairs(self.Document.particles) do
            if particle.particleId == id then return particle end
        end
        return nil
    end
    if index < 0 then return self.Document.lights[-index] end
    return self.Document.props[index]
end

function Editor:SelectionKind(index)
    index = index or self.Selected
    if type(index) == "string" then
        if string.match(index, "^guard:") then return "guard" end
        if string.match(index, "^particle:") then return "particle" end
        return nil
    end
    if type(index) ~= "number" then return nil end
    return index < 0 and "light" or "prop"
end

function Editor:GetSelectionPosition(index)
    index = index or self.Selected
    if not index then return nil end
    if self:SelectionKind(index) ~= "prop" then
        local object = self:GetSelectedObject(index)
        if not object then return nil end
        return self:GetPreviewOrigin() + Vector(object.position.x, object.position.y, object.position.z)
    end
    local model = self.Models[index]
    return IsValid(model) and model:GetPos() or nil
end

function Editor:Select(index)
    if index ~= self.Selected then self:StopRotation() end
    self.Selected = index
    if index and self:SelectionKind(index) ~= "prop" and self.Mode == "scale" then
        self.Mode = "move"
        if IsValid(self.ModeButton) then self.ModeButton:SetText("MODE: MOVE") end
    end
    self:RefreshInspector()
end

function Editor:AddParticle()
    if not self.SelectedParticleEffect then
        self:Message("Choose an available particle effect first.", true)
        return
    end
    local used = {}
    for _, particle in ipairs(self.Document.particles) do used[particle.particleId] = true end
    local index = 1
    while used["particle_" .. index] do index = index + 1 end
    local particle = {
        particleId = "particle_" .. index, effect = self.SelectedParticleEffect,
        position = { x = 0, y = 0, z = 16 }, angles = { p = 0, y = 0, r = 0 },
        mode = "continuous", overlap = true
    }
    self.Document.particles[#self.Document.particles + 1] = particle
    self:Select("particle:" .. particle.particleId)
    self:MarkChanged()
end

function Editor:AddLight()
    local used = {}
    for _, light in ipairs(self.Document.lights) do used[light.lightId] = true end
    local index = 1
    while used["light_" .. index] do index = index + 1 end
    self.Document.lights[#self.Document.lights + 1] = {
        lightId = "light_" .. index, position = { x = -80, y = -160, z = 192 },
        angles = { p = 40, y = 45, r = 0 }, color = { r = 255, g = 235, b = 200 },
        brightness = 6, fov = 60, range = 512
    }
    self:Select(-#self.Document.lights)
    self:MarkChanged()
end

function Editor:MakeGuardModel(guard)
    local weapon = self.GuardWeapons and self.GuardWeapons[guard.weapon]
    if not weapon then return false end
    local instance, problem = ZM_PrefabGuardPreview:Create(guard, weapon, self:GetPreviewOrigin())
    if not instance then self:Message(problem, true) return false end
    self.GuardModels[guard.guardId] = instance
    self.SceneRefresh = true
    timer.Simple(0, function()
        if self:IsActive() and self.GuardModels[guard.guardId] == instance
            and self.Selected == "guard:" .. guard.guardId then self:RefreshInspector() end
    end)
    return true
end

function Editor:AddGuard()
    local weapon = self.GuardWeapons and self.GuardWeapons.pistol
    if not weapon then self:Message("Guard weapon choices are not available yet.", true) return end
    if not ZM_Clothing or not ZM_Clothing.Models["models/player/group01/male_03.mdl"] then
        self:Message("The default clothing-compatible guard model is unavailable.", true)
        return
    end
    local used = {}
    for _, guard in ipairs(self.Document.guards) do used[guard.guardId] = true end
    local index = 1
    while used["guard_" .. index] do index = index + 1 end
    local guard = {
        guardId = "guard_" .. index, name = "Guard", model = "models/player/group01/male_03.mdl",
        position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
        idle = "idle_all_01", weapon = "pistol", range = math.min(1000, weapon.range), shirt = "", pants = ""
    }
    if not self:MakeGuardModel(guard) then return end
    self.Document.guards[#self.Document.guards + 1] = guard
    self:Select("guard:" .. guard.guardId)
    self:MarkChanged()
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
        styleListRow(row, self.Selected == index)
        row.PrefabIndex = index
    end
    if IsValid(self.LightList) then
        self.LightList:Clear()
        for index, light in ipairs(self.Document.lights) do
            local row = self.LightList:AddLine((self.Selected == -index and "> " or "") .. light.lightId)
            styleListRow(row, self.Selected == -index)
            row.PrefabLightIndex = index
        end
        if IsValid(self.ParticleList) then
            self.ParticleList:Clear()
            for _, particle in ipairs(self.Document.particles) do
                local selected = self.Selected == "particle:" .. particle.particleId
                local row = self.ParticleList:AddLine((selected and "> " or "") .. particle.particleId, particle.effect)
                styleListRow(row, selected)
                row.PrefabParticleId = particle.particleId
            end
        end
        if IsValid(self.GuardList) then
            self.GuardList:Clear()
            for _, guard in ipairs(self.Document.guards) do
                local selected = self.Selected == "guard:" .. guard.guardId
                local row = self.GuardList:AddLine((selected and "> " or "") .. guard.name, guard.guardId)
                styleListRow(row, selected)
                row.PrefabGuardId = guard.guardId
            end
        end
    end
    local object = self:GetSelectedObject()
    local prop = self.Document.props[self.Selected or 0]
    local kind = object and self:SelectionKind() or nil
    if IsValid(self.SelectionPanel) then
        self.SelectionPanel:SetVisible(object ~= nil)
        self.PropPanel:SetVisible(kind == "prop")
        self.LightPanel:SetVisible(kind == "light")
        self.ParticlePanel:SetVisible(kind == "particle")
        self.GuardPanel:SetVisible(kind == "guard")
        self.EmptySelection:SetVisible(object == nil)
        self.InspectorPanel:InvalidateLayout(true)
    end
    for _, entry in ipairs(self.Inspector or {}) do
        local enabled = object ~= nil and (entry.group ~= nil or prop ~= nil)
        entry.control:SetEnabled(enabled)
        local value = enabled and (entry.group and object[entry.group][entry.key] or object[entry.key]) or 0
        entry.control:SetValue(value)
    end
    local light = self:SelectionKind() == "light" and object or nil
    for _, entry in ipairs(self.LightInspector or {}) do
        entry.control:SetEnabled(light ~= nil)
        entry.control:SetValue(light and (entry.group and light[entry.group][entry.key] or light[entry.key]) or 0)
    end
    local particle = self:SelectionKind() == "particle" and object or nil
    if IsValid(self.ParticleMode) then
        self.ParticleMode:SetEnabled(particle ~= nil)
        self.ParticleMode:SetValue(particle and (particle.mode == "continuous" and "Continuous" or "Triggered") or "Continuous")
        self.ParticleOverlap:SetEnabled(particle ~= nil and particle.mode == "triggered")
        self.ParticleOverlap:SetValue(particle and particle.overlap and 1 or 0)
        self.ParticleTrigger:SetEnabled(particle ~= nil and particle.mode == "triggered")
    end
    if particle and IsValid(self.ParticleChoice) then
        for _, definition in ipairs(self.ParticleDefinitions or {}) do
            if definition.id == particle.effect then
                self.SelectedParticleEffect = particle.effect
                self.ParticleChoice:SetValue(definition.label)
                break
            end
        end
        local guard = kind == "guard" and object or nil
        if IsValid(self.GuardName) then
            self.GuardName:SetValue(guard and guard.name or "")
            self.GuardModel:SetValue(guard and guard.model or "")
            self.GuardWeapon:SetValue(guard and self.GuardWeapons and self.GuardWeapons[guard.weapon]
                and self.GuardWeapons[guard.weapon].label or "")
            self.GuardShirt:SetValue(guard and guard.shirt ~= "" and guard.shirt or "Model default")
            self.GuardPants:SetValue(guard and guard.pants ~= "" and guard.pants or "Model default")
            self.GuardRange:SetValue(guard and guard.range or 0)
            self.GuardIdle:Clear()
            if guard then
                local instance = self.GuardModels[guard.guardId]
                local sequences = instance and IsValid(instance.model) and instance.model:GetSequenceList() or nil
                local names, seen = {}, {}
                for _, name in pairs(sequences or {}) do
                    if type(name) == "string" and string.find(string.lower(name), "idle", 1, true) and not seen[name] then
                        names[#names + 1], seen[name] = name, true
                    end
                end
                table.sort(names)
                for _, name in ipairs(names) do self.GuardIdle:AddChoice(name, name) end
                self.GuardIdle:SetValue(guard.idle)
            end
            for _, entry in ipairs(self.GuardOverrides or {}) do
                local weapon = guard and self.GuardWeapons and self.GuardWeapons[guard.weapon]
                local enabled = guard and guard[entry.field] ~= nil
                entry.toggle:SetEnabled(guard ~= nil and weapon ~= nil)
                entry.toggle:SetValue(enabled and 1 or 0)
                entry.control:SetEnabled(enabled == true)
                entry.control:SetValue(enabled and guard[entry.field] or weapon and weapon[entry.weaponField] or 0)
            end
        end
    end
    if IsValid(self.MovableToggle) then
        self.MovableToggle:SetEnabled(prop ~= nil)
        self.MovableToggle:SetValue(prop and prop.movable and 1 or 0)
    end
    if IsValid(self.LootMode) then
        self.LootMode:SetEnabled(prop ~= nil)
        self.LootMode:SetValue(prop and lootModeLabels[prop.lootMode or "off"] or "Off")
        self.LootGroup:SetEnabled(prop ~= nil and prop.lootMode ~= "off" and self.LootGroupsReady == true)
        local groupId = prop and prop.lootGroup or nil
        local groupLabel = groupId and self.LootGroupLabels[groupId] or nil
        self.LootGroup:SetValue(not self.LootGroupsReady and "Loot groups unavailable"
            or groupId and (groupLabel or ("Unavailable: " .. groupId)) or "Model default")
        if groupId and not groupLabel and self.LootGroupsReady and self.LastLootGroupWarning ~= groupId then
            self.LastLootGroupWarning = groupId
            ErrorNoHalt("[ZombieSim] Prefab editor: loot group is unavailable on this client: " .. groupId .. "\n")
        end
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
    self.IdInput:SetText(self.OpenedId or self.Document.id)
    self.IdInput:SetEnabled(self.OpenedId == nil and not self.Saving)
    self.NameInput:SetText(self.Document.name)
    self.DescriptionInput:SetText(self.Document.description)
    self.TagsInput:SetText(table.concat(self.Document.tags, ", "))
    self:RefreshWorldPlacementControls()
    self.Refreshing = false
    self:RefreshInspector()
end

function Editor:SetDocument(document, openedId)
    if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
    self.Drag = nil
    self:ClearRotationSelection()
    self:ClearModels()
    if ZM_PrefabParticlePreview then ZM_PrefabParticlePreview:Clear() end
    self.Document = document
    if document.lights == nil then document.lights = {} end
    if document.particles == nil then document.particles = {} end
    if document.guards == nil then document.guards = {} end
    self.OpenedId = openedId
    self.Selected = nil
    self.LastPropClick = nil
    self.Dirty = false
    self.Revision = (self.Revision or 0) + 1
    for index in ipairs(document.props) do self:MakeModel(index) end
    for _, guard in ipairs(document.guards) do self:MakeGuardModel(guard) end
    self:RefreshDocument()
end

function Editor:SetDocuments(documents)
    if not IsValid(self.PrefabList) then return end
    self.PrefabList:Clear()
    self.TagSuggestions:Clear()
    for _, tag in ipairs(Contract.GetTagSuggestions(documents)) do self.TagSuggestions:AddChoice(tag, tag) end
    for _, document in ipairs(documents or {}) do
        local row = self.PrefabList:AddLine(document.name, document.id)
        styleListRow(row, document.id == self.OpenedId)
        row.PrefabId = document.id
    end
end

function Editor:RequestExplorer(action, text, extra)
    return send(action, text, extra)
end

function Editor:OpenSaved(id, after)
    if not Contract.IsValidId(id) then self:Message("Invalid prefab ID.", true) return false end
    local existing = self:FindTab(id)
    if existing then
        self:ActivateTab(existing)
        if after then after() end
        return true
    end
    if self.PendingLoads[id] then
        self:Message("That prefab is already loading.")
        return false
    end
    local requestId = self:NewRequest({ kind = "load", id = id, origin = self.ActiveTab, serial = self.SwitchSerial })
    if not send("load", id, "", requestId) then self.PendingRequests[requestId] = nil return false end
    self.PendingLoads[id] = requestId
    if after then after() end
    return true
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
    local id = self.OpenedId or self.IdInput:GetValue()
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

function Editor:NewRequest(request)
    self.RequestSerial = (self.RequestSerial or 0) + 1
    local id = "r" .. self.RequestSerial
    self.PendingRequests[id] = request
    return id
end

function Editor:FindTab(id)
    for _, tab in ipairs(self.Tabs or {}) do
        if tab.OpenedId == id then return tab end
    end
end

function Editor:CaptureActiveTab()
    local tab = self.ActiveTab
    if not tab then return end
    self:SyncMetadata()
    tab.Document, tab.OpenedId, tab.Dirty, tab.Revision = self.Document, self.OpenedId, self.Dirty, self.Revision
    tab.Selected, tab.Mode = self.Selected, self.Mode
    tab.View = {
        cameraYaw = self.CameraYaw, cameraPitch = self.CameraPitch, cameraDistance = self.CameraDistance,
        panX = self.CameraPanX or 0, panY = self.CameraPanY or 0,
        positionSnap = self.PositionSnap, rotationSnap = self.RotationSnap, snapEnabled = self.SnapEnabled,
        gridSpacing = self.GridSpacing or 64, showGrid = self.ShowGrid ~= false, showCompass = self.ShowCompass ~= false,
        previewFog = self.PreviewFog, previewDark = self.PreviewDark,
        reference = self.ReferenceWanted, referenceOffset = self.ReferenceOffset or 0,
        prefabOffset = self.PrefabPreviewOffset or 0,
        prefabOffsetX = self.PrefabPreviewOffsetX or 0, prefabOffsetY = self.PrefabPreviewOffsetY or 0
    }
end

function Editor:LockMapSwitch(text)
    if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
    self.Drag = nil
    self.SwitchingMap = true
    if IsValid(self.MapSwitchOverlay) then self.MapSwitchOverlay:Remove() end
    local overlay = vgui.Create("DPanel", self.Frame)
    self.MapSwitchOverlay = overlay
    overlay:SetPos(0, 0)
    overlay:SetSize(ScrW(), ScrH())
    overlay:SetZPos(10000)
    overlay:SetMouseInputEnabled(true)
    overlay:SetKeyboardInputEnabled(true)
    overlay.Paint = function(_, w, h)
        surface.SetDrawColor(0, 0, 0, 220)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText(text, "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    overlay:MakePopup()
end

function Editor:UnlockMapSwitch()
    if IsValid(self.MapSwitchOverlay) then self.MapSwitchOverlay:Remove() end
    self.MapSwitchOverlay, self.SwitchingMap = nil, false
    if self:IsActive() then self.Frame:MakePopup() end
end

function Editor:BeginMapSwitch(mapName, cellId)
    if not self:IsActive() or self.SwitchingMap then return false end
    if not EditorMap.IsValidName(mapName) or (cellId == nil and EditorMap.IsReservedName(mapName))
        or (cellId ~= nil and not EditorMap.IsValidCellId(cellId)) then
        self:Message("The selected editor map is invalid or reserved.", true)
        return false
    end
    if string.lower(mapName) == string.lower(game.GetMap())
        and cellId == (self.Cell and self.Cell.id or nil) then
        self:Message("The editor is already on that map or cell.")
        return false
    end
    if IsValid(self.ModelBrowser) or (ZM_PrefabExplorer and IsValid(ZM_PrefabExplorer.Frame)) then
        self:Message("Close the model browser or prefab explorer before switching maps.", true)
        return false
    end
    for _, request in pairs(self.PendingRequests or {}) do
        if request.kind ~= "maps" and request.kind ~= "cells" then
            self:Message("Wait for pending editor requests before switching maps.", true)
            return false
        end
    end
    for _, tab in ipairs(self.Tabs or {}) do
        if tab.Saving or (tab.PendingCount or 0) > 0 then
            self:Message("Wait for all prefab tabs to finish saving or loading.", true)
            return false
        end
    end
    self:CaptureActiveTab()
    local tabs, active = {}, nil
    for index, tab in ipairs(self.Tabs) do
        if tab == self.ActiveTab then active = index end
        tabs[index] = {
            number = tab.Number, document = tab.Document, openedId = tab.OpenedId,
            dirty = tab.Dirty, revision = tab.Revision, selected = tab.Selected, mode = tab.Mode, view = tab.View
        }
    end
    local saved, problem = MapTransfer:Save(mapName, tabs, active, cellId)
    if not saved then self:Message(problem, true) return false end
    local payload = util.TableToJSON({ map = mapName, cellId = cellId, token = saved.token,
        openIds = saved.openIds }, false)
    if type(payload) ~= "string" then
        local removed, removeError = MapTransfer:Remove(saved.encoded)
        self:Message(removed and "Could not encode the map-switch request." or removeError, true)
        return false
    end
    if IsValid(self.MapBrowser) then self.MapBrowser:Close() end
    self:LockMapSwitch("Switching maps - preserving all prefab tabs...")
    local requestId = self:NewRequest({ kind = "switch_map", encoded = saved.encoded, token = saved.token })
    if not send("switch_map", payload, "", requestId) then
        self.PendingRequests[requestId] = nil
        local removed, removeError = MapTransfer:Remove(saved.encoded)
        self:UnlockMapSwitch()
        if not removed then self:Message(removeError, true) end
        return false
    end
    self.MapSwitchToken = saved.token
    timer.Simple(10, function()
        if self:IsActive() and self.SwitchingMap and self.MapSwitchToken == saved.token then
            Derma_Query("The map change is still pending. Your tab snapshot is preserved.", "Prefab editor",
                "Retry switch", function() send("switch_retry") end, "Keep waiting", function() end)
        end
    end)
    return true
end

function Editor:ConfirmMapRestore(token, encoded)
    local requestId = self:NewRequest({ kind = "switch_complete", token = token, encoded = encoded })
    if not send("switch_complete", token, "", requestId) then
        self.PendingRequests[requestId] = nil
        self:Message("Could not confirm the restored tabs. The saved draft remains available.", true)
        return false
    end
    return true
end

function Editor:CheckFailedMapSwitch(encoded)
    local requestId = self:NewRequest({ kind = "switch_check", encoded = encoded })
    if not send("switch_check", "", "", requestId) then
        self.PendingRequests[requestId] = nil
        self:Message("Could not check the editor session. The saved draft remains available.", true)
        return false
    end
    return true
end

function Editor:RestoreMapSnapshot(snapshot, encoded)
    self.Tabs, self.ActiveTab, self.TabSerial = {}, nil, 0
    for _, saved in ipairs(snapshot.tabs) do
        local tab = {
            Number = saved.number, Document = saved.document, OpenedId = saved.openedId,
            Dirty = saved.dirty, Revision = saved.revision, Selected = saved.selected,
            Mode = saved.mode, View = saved.view, PendingCount = 0
        }
        self.Tabs[#self.Tabs + 1] = tab
        self.TabSerial = math.max(self.TabSerial, tab.Number)
    end
    self:RebuildTabs()
    self:ActivateTab(self.Tabs[snapshot.active])
    self.MapSwitchToken = snapshot.token
    self:LockMapSwitch("Restoring prefab tabs...")
    return self:ConfirmMapRestore(snapshot.token, encoded)
end

function Editor:RequestMapList(query, page)
    if not IsValid(self.MapBrowser) then return false end
    self.MapListSerial = (self.MapListSerial or 0) + 1
    local action = self.MapCategory == "cells" and "cells" or "maps"
    local requestId = self:NewRequest({ kind = action, browser = self.MapBrowser, serial = self.MapListSerial })
    local encoded = util.TableToJSON({ query = query, page = page }, false)
    if type(encoded) ~= "string" or not send(action, encoded, "", requestId) then
        self.PendingRequests[requestId] = nil
        self:Message("Could not request the mounted map list.", true)
        return false
    end
    return true
end

function Editor:MapThumbnail(name)
    local cached = self.MapThumbnailCache[name]
    if cached ~= nil then return cached or nil end
    local path = "maps/thumb/" .. name .. ".png"
    if not file.Exists(path, "GAME") then self.MapThumbnailCache[name] = false return nil end
    local material = Material(path, "smooth")
    local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
    if not texture or texture:Width() <= 0 or texture:Height() <= 0 then
        self.MapThumbnailCache[name] = false
        ErrorNoHalt("[ZombieSim] Prefab editor: map thumbnail could not be loaded: " .. name .. "\n")
        return nil
    end
    self.MapThumbnailCache[name] = material
    return material
end

function Editor:CellThumbnail(id)
    local key = "cell:" .. tostring(id)
    local cached = self.MapThumbnailCache[key]
    if cached ~= nil then return cached or nil end
    local cell = ZM_World and ZM_World:GetCellById(id)
    local material = cell and ZM_WorldMap and ZM_WorldMap:GetCellAtlasMaterial(cell, false) or nil
    local texture = material and not material:IsError() and material:GetTexture("$basetexture") or nil
    if not texture or texture:Width() <= 0 or texture:Height() <= 0 then
        self.MapThumbnailCache[key] = false
        return nil
    end
    self.MapThumbnailCache[key] = material
    return material
end

function Editor:RefreshMapCards()
    if not IsValid(self.MapGrid) or not self.MapLists then return end
    self.MapGrid:Clear()
    local entries = self.MapCategory == "recommended" and self.MapLists.recommended
        or self.MapCategory == "cells" and self.MapLists.cells or self.MapLists.custom
    for _, entry in ipairs(entries) do
        local card = self.MapGrid:Add("DButton")
        card:SetSize(200, 150)
        card:SetText("")
        local cell = type(entry) == "table" and entry or nil
        local selectedMap = cell and cell.map or entry
        local label = cell and ("Cell " .. cell.x .. ", " .. cell.y) or selectedMap
        card.MapName = selectedMap
        card.CellId = cell and cell.id or nil
        local thumbnail = cell and self:CellThumbnail(cell.id) or self:MapThumbnail(selectedMap)
        card:SetTooltip(cell and (label .. "\n" .. selectedMap) or selectedMap)
        card.DoClick = function() self:BeginMapSwitch(selectedMap, cell and cell.id or nil) end
        card.Paint = function(panel, w, h)
            local palette = ZM_DermaSkin.Palette
            surface.SetDrawColor(palette.black)
            surface.DrawRect(0, 0, w, h)
            if thumbnail then
                surface.SetMaterial(thumbnail)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(6, 6, w - 12, h - 36)
            else
                surface.SetDrawColor(palette.raised)
                surface.DrawRect(6, 6, w - 12, h - 36)
                draw.SimpleText("No thumbnail", "DermaDefault", w / 2, (h - 30) / 2,
                    palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            local current = cell and self.Cell and self.Cell.id == cell.id
                or not cell and not self.Cell and string.lower(selectedMap) == string.lower(game.GetMap())
            draw.SimpleText(label .. (current and " (current)" or ""), "DermaDefaultBold",
                8, h - 22, palette.text)
            surface.SetDrawColor(panel.Hovered and palette.text or palette.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
    end
    if IsValid(self.MapPageLabel) then
        self.MapPageLabel:SetText(self.MapCategory ~= "recommended"
            and ("Page " .. self.MapLists.page .. " / " .. self.MapLists.pages
                .. "  (" .. self.MapLists.total .. (self.MapCategory == "cells" and " cells)" or " maps)"))
            or "Recommended maps")
    end
    self.MapGrid:InvalidateLayout(true)
end

function Editor:OnMapList(data, request)
    if not IsValid(self.MapBrowser) or request.browser ~= self.MapBrowser or request.serial ~= self.MapListSerial then return end
    if type(data) ~= "table" or (request.kind == "maps" and
        (type(data.recommended) ~= "table" or type(data.custom) ~= "table"))
        or (request.kind == "cells" and type(data.cells) ~= "table")
        or type(data.page) ~= "number" or type(data.pages) ~= "number" or type(data.total) ~= "number" then
        self:Message("The mounted map list is invalid.", true)
        return
    end
    if request.kind == "cells" then
        for _, cell in ipairs(data.cells) do
            if type(cell) ~= "table" or not EditorMap.IsValidCellId(cell.id) or not EditorMap.IsValidName(cell.map)
                or not finiteNumber(cell.x) or not finiteNumber(cell.y)
                or cell.x ~= math.floor(cell.x) or cell.y ~= math.floor(cell.y) then
                self:Message("The preview cell list contains an invalid entry.", true)
                return
            end
        end
    else
        for _, names in ipairs({ data.recommended, data.custom }) do
            for _, name in ipairs(names) do
                if not EditorMap.IsValidName(name) or EditorMap.IsReservedName(name) then
                    self:Message("The mounted map list contains an invalid entry.", true)
                    return
                end
            end
        end
    end
    self.MapLists = data
    self:RefreshMapCards()
end

function Editor:OpenMapBrowser()
    if not self:IsActive() or self.SwitchingMap then return end
    if IsValid(self.MapBrowser) then self.MapBrowser:MakePopup() return end
    local frame = vgui.Create("DFrame", self.Frame)
    self.MapBrowser = frame
    frame:SetSkin("ZombieSim")
    frame:SetSize(math.min(1000, ScrW() - 40), math.min(700, ScrH() - 40))
    frame:Center()
    frame:SetTitle("Change Editor Map")
    frame:MakePopup()
    frame.OnRemove = function()
        if self.MapBrowser == frame then
            self.MapBrowser, self.MapGrid, self.MapLists, self.MapThumbnailCache = nil, nil, nil, nil
            self.MapSearch, self.MapSearchAt, self.MapPageLabel = nil, nil, nil
        end
        if self:IsActive() and not self.SwitchingMap then self.Frame:MakePopup() end
    end
    local choices = vgui.Create("DPanel", frame)
    choices:Dock(TOP)
    choices:SetTall(32)
    choices.Paint = function() end
    local recommended = vgui.Create("DButton", choices)
    recommended:Dock(LEFT); recommended:SetWide(150); recommended:SetText("RECOMMENDED")
    local custom = vgui.Create("DButton", choices)
    custom:Dock(LEFT); custom:SetWide(150); custom:SetText("CUSTOM MAPS")
    local cells = vgui.Create("DButton", choices)
    cells:Dock(LEFT); cells:SetWide(150); cells:SetText("CELLS")
    self.MapCategory, self.MapThumbnailCache = "recommended", {}
    local function selectCategory(category)
        local changedType = (self.MapCategory == "cells") ~= (category == "cells")
        self.MapCategory = category
        if changedType then
            self.MapLists = nil
            self.MapGrid:Clear()
            self.MapPageLabel:SetText("Loading...")
            self:RequestMapList(string.Trim(self.MapSearch:GetValue()), 1)
        else
            self:RefreshMapCards()
        end
    end
    recommended.DoClick = function() selectCategory("recommended") end
    custom.DoClick = function() selectCategory("custom") end
    cells.DoClick = function() selectCategory("cells") end
    self.MapSearch = textEntry(frame, "Search custom maps or cell coordinates", function()
        self.MapSearchAt = RealTime() + 0.25
    end)
    self.MapSearch:SetValue("")
    local manual = textEntry(frame, "Custom map name", function() end)
    button(frame, "OPEN CUSTOM MAP", function() self:BeginMapSwitch(string.Trim(manual:GetValue())) end)
    local paging = vgui.Create("DPanel", frame)
    paging:Dock(BOTTOM); paging:SetTall(32); paging.Paint = function() end
    local previous = vgui.Create("DButton", paging)
    previous:Dock(LEFT); previous:SetWide(90); previous:SetText("PREVIOUS")
    previous.DoClick = function()
        if self.MapLists and self.MapLists.page > 1 then
            self:RequestMapList(string.Trim(self.MapSearch:GetValue()), self.MapLists.page - 1)
        end
    end
    local nextPage = vgui.Create("DButton", paging)
    nextPage:Dock(RIGHT); nextPage:SetWide(90); nextPage:SetText("NEXT")
    nextPage.DoClick = function()
        if self.MapLists and self.MapLists.page < self.MapLists.pages then
            self:RequestMapList(string.Trim(self.MapSearch:GetValue()), self.MapLists.page + 1)
        end
    end
    self.MapPageLabel = vgui.Create("DLabel", paging)
    self.MapPageLabel:Dock(FILL); self.MapPageLabel:SetContentAlignment(5); self.MapPageLabel:SetText("Loading maps...")
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    self.MapGrid = vgui.Create("DIconLayout", scroll)
    self.MapGrid:Dock(TOP)
    self.MapGrid:SetSpaceX(6); self.MapGrid:SetSpaceY(6)
    frame.Think = function()
        if self.MapSearchAt and RealTime() >= self.MapSearchAt then
            self.MapSearchAt = nil
            self:RequestMapList(string.Trim(self.MapSearch:GetValue()), 1)
        end
    end
    self:RequestMapList("", 1)
end

function Editor:RefreshTabTitles()
    for _, tab in ipairs(self.Tabs or {}) do
        if IsValid(tab.Button) then
            local name = string.Trim(tab.Document.name or "")
            if name == "" then name = tab.Document.id ~= "" and tab.Document.id or ("Untitled " .. tab.Number) end
            tab.Button:SetText((tab.Dirty and "* " or "") .. name)
        end
    end
end

function Editor:RebuildTabs()
    if not IsValid(self.TabScroller) then return end
    self.TabScroller:Clear()
    for _, tab in ipairs(self.Tabs) do
        local panel = vgui.Create("DPanel", self.TabScroller)
        panel:SetWide(180)
        panel.Paint = function() end
        local close = vgui.Create("DButton", panel)
        close:Dock(RIGHT)
        close:SetWide(26)
        close:SetText("X")
        close:SetTooltip("Close prefab tab")
        close.DoClick = function() self:CloseTab(tab) end
        local selected = vgui.Create("DButton", panel)
        selected:Dock(FILL)
        selected:SetText("")
        selected.Paint = function(control, w, h)
            local palette = ZM_DermaSkin.Palette
            local active = self.ActiveTab == tab
            surface.SetDrawColor(active and palette.redDark or control.Hovered and palette.border or palette.raised)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(active and palette.redBright or palette.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        selected.DoClick = function() self:ActivateTab(tab) end
        tab.Panel, tab.Button = panel, selected
        self.TabScroller:AddPanel(panel)
    end
    self:RefreshTabTitles()
end

function Editor:CreateTab(document, openedId, activate)
    self.TabSerial = (self.TabSerial or 0) + 1
    local tab = { Number = self.TabSerial, Document = document, OpenedId = openedId,
        Dirty = false, Revision = 0, Mode = "move", View = defaultTabView(), PendingCount = 0 }
    self.Tabs[#self.Tabs + 1] = tab
    self:RebuildTabs()
    if activate then self:ActivateTab(tab) end
    return tab
end

function Editor:ActivateTab(tab)
    if not tab or self.ActiveTab == tab then return end
    self:CaptureActiveTab()
    self.ActiveTab = tab
    self.SwitchSerial = (self.SwitchSerial or 0) + 1
    local view = tab.View
    self.PrefabPreviewOffset = view.prefabOffset
    self.PrefabPreviewOffsetX, self.PrefabPreviewOffsetY = view.prefabOffsetX or 0, view.prefabOffsetY or 0
    self:SetDocument(tab.Document, tab.OpenedId)
    self.Dirty, self.Revision, self.Saving = tab.Dirty, tab.Revision, tab.Saving == true
    self.Selected = tab.Selected
    if self.Selected and not self:GetSelectedObject() then self.Selected = nil end
    self.Mode = tab.Mode
    if self.Selected and self:SelectionKind() ~= "prop" and self.Mode == "scale" then self.Mode = "move" end
    if IsValid(self.ModeButton) then self.ModeButton:SetText("MODE: " .. string.upper(self.Mode)) end
    self.CameraYaw, self.CameraPitch, self.CameraDistance = view.cameraYaw, view.cameraPitch, view.cameraDistance
    self.CameraPanX, self.CameraPanY = view.panX, view.panY
    self.PositionSnap, self.RotationSnap, self.SnapEnabled = view.positionSnap, view.rotationSnap, view.snapEnabled
    self.GridSpacing, self.ShowGrid, self.ShowCompass = view.gridSpacing, view.showGrid, view.showCompass
    self.PreviewFog, self.PreviewDark, self.ReferenceOffset = view.previewFog, view.previewDark, view.referenceOffset
    self.ReferenceWanted = view.reference
    self:ClearReference()
    if view.reference and not self:SetReference(view.reference) then self.ReferenceWanted = nil end
    self.Refreshing = true
    if IsValid(self.ReferenceChoice) then
        self.ReferenceChoice:SetValue(self.ReferenceWanted and self.ReferenceLabels
            and self.ReferenceLabels[self.ReferenceWanted] or "No reference")
    end
    if IsValid(self.FogToggle) then self.FogToggle:SetValue(self.PreviewFog and 1 or 0) end
    if IsValid(self.DarkToggle) then self.DarkToggle:SetValue(self.PreviewDark and 1 or 0) end
    self.Refreshing = false
    self:RefreshViewControls()
    self:RefreshDocument()
    self:RefreshTabTitles()
    send("activate", tab.OpenedId or "")
end

function Editor:RemoveTab(tab)
    local index
    for current, value in ipairs(self.Tabs) do if value == tab then index = current break end end
    if not index then return end
    if tab.OpenedId then send("close", tab.OpenedId) end
    local active = self.ActiveTab == tab
    table.remove(self.Tabs, index)
    if active then self.ActiveTab = nil end
    self:RebuildTabs()
    if #self.Tabs == 0 then
        self:CreateTab(blankDocument(), nil, true)
    elseif active then
        self:ActivateTab(self.Tabs[math.min(index, #self.Tabs)])
    end
end

function Editor:CloseTab(tab)
    if not tab or self.SwitchingMap then return end
    if tab.Saving or (tab.PendingCount or 0) > 0 then
        self:Message("Wait for this tab's request to finish.", true)
        return
    end
    if self.ActiveTab == tab then self:CaptureActiveTab() end
    if not tab.Dirty then self:RemoveTab(tab) return end
    self:ActivateTab(tab)
    Derma_Query("Save changes to this prefab before closing its tab?", "Prefab editor",
        "Save", function()
            self:ActivateTab(tab)
            self:Save(false, function(ok)
                if ok and not tab.Dirty then self:RemoveTab(tab) end
            end)
        end,
        "Discard", function() self:RemoveTab(tab) end,
        "Cancel", function() end)
end

function Editor:RequestModel(path)
    local tab = self.ActiveTab
    if not tab then return false end
    local requestId = self:NewRequest({ kind = "model", tab = tab })
    if not send("model", path, "", requestId) then self.PendingRequests[requestId] = nil return false end
    tab.PendingCount = (tab.PendingCount or 0) + 1
    return true
end

function Editor:RequestDelete(tab)
    if not tab or not tab.OpenedId or (tab.PendingCount or 0) > 0 or tab.Saving then
        self:Message("Wait for pending tab requests before deleting.", true)
        return false
    end
    local requestId = self:NewRequest({ kind = "delete", tab = tab, id = tab.OpenedId })
    if not send("delete", tab.OpenedId, "", requestId) then self.PendingRequests[requestId] = nil return false end
    tab.PendingCount = tab.PendingCount + 1
    return true
end

function Editor:RequestReference(path)
    local tab = self.ActiveTab
    if not tab then return false end
    tab.ReferenceRequest = nil
    self.ReferenceWanted = nil
    self:ClearReference()
    if path == "" then return true end
    local requestId = self:NewRequest({ kind = "reference", tab = tab, path = path })
    if not send("reference", path, "", requestId) then self.PendingRequests[requestId] = nil return false end
    tab.ReferenceRequest = requestId
    tab.PendingCount = tab.PendingCount + 1
    return true
end

function Editor:Save(exitAfter, afterSave)
    if self.SwitchingMap then return end
    local tab = self.ActiveTab
    if not tab or tab.Saving then return end
    self:SyncMetadata()
    local encoded = util.TableToJSON(self.Document, false)
    if type(encoded) ~= "string" then self:Message("Could not encode the prefab.", true) return end
    local request = { kind = "save", tab = tab, revision = self.Revision, id = self.Document.id,
        exitAfter = exitAfter == true, afterSave = afterSave }
    local requestId = self:NewRequest(request)
    if not send("save", encoded, self.OpenedId, requestId) then self.PendingRequests[requestId] = nil return end
    tab.Saving, self.Saving = true, true
    self:RefreshDocument()
end

function Editor:Exit()
    if self.SwitchingMap then return end
    local discarded = {}
    local function confirm()
        self:CaptureActiveTab()
        if next(self.PendingLoads) then
            self:Message("Wait for pending prefab loads before exiting.", true)
            return
        end
        for _, tab in ipairs(self.Tabs) do
            if tab.Saving or (tab.PendingCount or 0) > 0 then
                self:Message("Wait for pending tab requests before exiting.", true)
                return
            end
        end
        for _, tab in ipairs(self.Tabs) do
            if tab.Dirty and discarded[tab] ~= tab.Revision then
                self:ActivateTab(tab)
                local revision = tab.Revision
                Derma_Query("Save changes to this prefab before returning to the preview launcher?", "Prefab editor",
                    "Save", function()
                        self:ActivateTab(tab)
                        self:Save(false, function(ok)
                            if ok and not tab.Dirty then confirm()
                            elseif ok then self:Message("The tab changed while saving; review it before exiting.", true) end
                        end)
                    end,
                    "Discard", function() discarded[tab] = revision; confirm() end,
                    "Cancel", function() end)
                return
            end
        end
        send("end")
    end
    confirm()
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
    styleList(folders)
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
            styleListRow(row)
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
    for index, light in ipairs(self.Document.lights) do
        local position = self:GetPreviewOrigin() + Vector(light.position.x, light.position.y, light.position.z)
        local _, _, fraction = util.IntersectRayWithOBB(view.origin, direction, position,
            Angle(light.angles.p, light.angles.y, light.angles.r), lightHandleMin, lightHandleMax)
        if fraction and (not closest or fraction < closest) then chosen, closest = -index, fraction end
    end
    for _, particle in ipairs(self.Document.particles) do
        local position = self:GetPreviewOrigin() + Vector(particle.position.x, particle.position.y, particle.position.z)
        local _, _, fraction = util.IntersectRayWithOBB(view.origin, direction, position,
            Angle(particle.angles.p, particle.angles.y, particle.angles.r), lightHandleMin, lightHandleMax)
        if fraction and (not closest or fraction < closest) then
            chosen, closest = "particle:" .. particle.particleId, fraction
        end
    end
    for _, guard in ipairs(self.Document.guards) do
        local instance = self.GuardModels[guard.guardId]
        local model = instance and instance.model
        if IsValid(model) then
            local _, _, fraction = util.IntersectRayWithOBB(view.origin, direction,
                model:GetPos(), model:GetAngles(), model:OBBMins(), model:OBBMaxs())
            if fraction and (not closest or fraction < closest) then
                chosen, closest = "guard:" .. guard.guardId, fraction
            end
        end
    end
    return chosen
end

function Editor:SelectAt(x, y)
    local chosen = self:FindPropAt(x, y)
    self:Select(chosen)
    return chosen
end

function Editor:CycleMode()
    if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
    self.Drag, self.RotationSelection = nil, nil
    self.Mode = self.Selected and self:SelectionKind() ~= "prop"
        and ({ move = "rotate", rotate = "move", scale = "move" })[self.Mode]
        or ({ move = "rotate", rotate = "scale", scale = "move" })[self.Mode]
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
    local prop = self:GetSelectedObject(drag.index)
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
    local prop = self:GetSelectedObject(index)
    if not prop then return end
    self.Selected, self.LastPropClick = index, nil
    self:ClearRotationSelection()
    if prop.angles.p ~= 0 or prop.angles.y ~= 0 or prop.angles.r ~= 0 then
        prop.angles.p, prop.angles.y, prop.angles.r = 0, 0, 0
        self:UpdateModel(index)
        self:MarkChanged()
    end
    self:RefreshInspector()
    self:Message("Rotation reset to the default orientation.")
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
    if self.SwitchingMap then return end
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
        if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then
            self.Drag = { kind = "pan", panel = panel, mouseCode = mouseCode,
                x = x, y = y, yaw = self.CameraYaw, distance = self.CameraDistance,
                panX = self.CameraPanX, panY = self.CameraPanY }
        else
            self.Drag = { kind = "camera", panel = panel, mouseCode = mouseCode,
                x = x, y = y, yaw = self.CameraYaw, pitch = self.CameraPitch }
        end
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
            local prop = self:GetSelectedObject(selection.index)
            local normal, first, second = self:GetRotationBasis(prop, selection.axis)
            local pivot = self:GetSelectionPosition(selection.index)
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
        local prop = self:GetSelectedObject()
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
            self:Select(hit)
            self:CycleMode()
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
            self:Select(hit)
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
        self:RefreshCameraControls()
        return
    end
    if drag.kind == "pan" then
        local angles = Angle(0, drag.yaw, 0)
        local right, forward = angles:Right(), angles:Forward()
        local scale = drag.distance * 0.0015
        local dx, dy = (x - drag.x) * scale, (y - drag.y) * scale
        self.CameraPanX = math.Clamp(drag.panX - right.x * dx + forward.x * dy, -32768, 32768)
        self.CameraPanY = math.Clamp(drag.panY - right.y * dx + forward.y * dy, -32768, 32768)
        self:RefreshCameraControls()
        return
    end
    local prop = self:GetSelectedObject()
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
    local center = self.Origin + Vector(self.CameraPanX or 0, self.CameraPanY or 0, 40)
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

function Editor:GetGridOrigin()
    return self.Origin + Vector(self.PrefabPreviewOffsetX or 0, self.PrefabPreviewOffsetY or 0,
        self.GridHeight or 1)
end

function Editor:BuildGrid(height)
    self.GridHeight = height
    self.GridLines = {}
    local gridOrigin = self:GetGridOrigin()
    for offset = -320, 320, self.GridSpacing or 64 do
        self.GridLines[#self.GridLines + 1] = {
            gridOrigin + Vector(offset, -320, 0), gridOrigin + Vector(offset, 320, 0)
        }
        self.GridLines[#self.GridLines + 1] = {
            gridOrigin + Vector(-320, offset, 0), gridOrigin + Vector(320, offset, 0)
        }
    end
end

function Editor:SetReferenceOffset(value)
    self.ReferenceOffset = value
    if IsValid(self.ReferenceModel) then
        self.ReferenceModel:SetPos(self.Origin + Vector(0, 0, value))
        self:BuildGrid(self.ReferenceTop + value + 1)
        self.SceneRefresh = true
    end
end

function Editor:SetPrefabPreviewOffset(value)
    if self.PrefabPreviewOffset == value then return end
    self.PrefabPreviewOffset = value
    for index in ipairs(self.Document.props) do self:UpdateModel(index) end
    for _, guard in ipairs(self.Document.guards) do self:UpdateModel("guard:" .. guard.guardId) end
    self.SceneRefresh = true
end

function Editor:SetPrefabPreviewHorizontal(axis, value)
    if axis == "x" then self.PrefabPreviewOffsetX = value else self.PrefabPreviewOffsetY = value end
    for index in ipairs(self.Document.props) do self:UpdateModel(index) end
    for _, guard in ipairs(self.Document.guards) do self:UpdateModel("guard:" .. guard.guardId) end
    self:BuildGrid(self.GridHeight or 1)
    self.SceneRefresh = true
end

function Editor:UseCurrentWorldPlacement()
    if not self.Cell then
        self:Message("Choose a world cell in Change Map before capturing its placement.", true)
        return false
    end
    local placement = self.Document.worldPlacement
    if not placement then return false end
    placement.profile, placement.cellX, placement.cellY = "preview", self.Cell.x, self.Cell.y
    placement.tileX, placement.tileY = self.Cell.tileX, self.Cell.tileY
    placement.offset = { x = self.PrefabPreviewOffsetX or 0, y = self.PrefabPreviewOffsetY or 0,
        z = self.PrefabPreviewOffset or 0 }
    self:MarkChanged()
    self:RefreshDocument()
    return true
end

function Editor:RefreshWorldPlacementControls()
    if not IsValid(self.WorldPlacementToggle) then return end
    local placement = self.Document.worldPlacement
    self.WorldPlacementToggle:SetValue(placement and placement.enabled and 1 or 0)
    self.WorldPlacementPanel:SetVisible(placement ~= nil)
    if placement then
        self.WorldProfile:SetValue(placement.profile)
        for key, control in pairs(self.WorldPlacementControls) do
            control:SetValue(placement[key])
        end
        for key, control in pairs(self.WorldOffsetControls) do control:SetValue(placement.offset[key]) end
        for key, control in pairs(self.WorldAngleControls) do control:SetValue(placement.angles[key]) end
    end
    if self.AreaPanels and IsValid(self.AreaPanels.prefab) then self.AreaPanels.prefab:InvalidateLayout(true) end
end

function Editor:RefreshCellTileControls()
    if not IsValid(self.CellTilePanel) then return end
    self.CellTilePanel:SetVisible(self.Cell ~= nil)
    local refreshing = self.Refreshing
    self.Refreshing = true
    self.CellTileX:SetEnabled(self.Cell ~= nil and not self.CellTilePending)
    self.CellTileY:SetEnabled(self.Cell ~= nil and not self.CellTilePending)
    self.CellTileX:SetValue(self.Cell and self.Cell.tileX or 0)
    self.CellTileY:SetValue(self.Cell and self.Cell.tileY or 0)
    self.Refreshing = refreshing
    if self.AreaPanels and IsValid(self.AreaPanels.view) then self.AreaPanels.view:InvalidateLayout(true) end
end

function Editor:RequestCellTile(x, y)
    if not self.Cell or self.SwitchingMap or self.CellTilePending
        or not EditorMap.IsValidTile(x) or not EditorMap.IsValidTile(y) then return false end
    if x == self.Cell.tileX and y == self.Cell.tileY then return true end
    local encoded = util.TableToJSON({ x = x, y = y }, false)
    if type(encoded) ~= "string" then self:Message("Could not encode the cell tile selection.", true) return false end
    local request = { kind = "cell_tile", x = x, y = y }
    local requestId = self:NewRequest(request)
    request.id = requestId
    if not send("cell_tile", encoded, "", requestId) then
        self.PendingRequests[requestId] = nil
        return false
    end
    self.CellTilePending = requestId
    self:RefreshCellTileControls()
    timer.Simple(10, function()
        if self:IsActive() and self.CellTilePending == requestId then
            Derma_Query("The tile selection is still pending.", "Prefab editor",
                "Retry", function()
                    if self.CellTilePending ~= requestId then return end
                    self.PendingRequests[requestId], self.CellTilePending = nil, nil
                    self:RequestCellTile(x, y)
                end, "Keep waiting", function() end)
        end
    end)
    return true
end

function Editor:ApplyCellTile(data, request)
    if not self.Cell or self.CellTilePending ~= request.id or type(data) ~= "table"
        or data.x ~= request.x or data.y ~= request.y or type(data.origin) ~= "table"
        or not finiteNumber(data.origin.x) or not finiteNumber(data.origin.y) or not finiteNumber(data.origin.z) then
        return false, "The cell tile response is invalid."
    end
    self.Cell.tileX, self.Cell.tileY = data.x, data.y
    self.Origin = Vector(data.origin.x, data.origin.y, data.origin.z)
    for index in ipairs(self.Document.props) do self:UpdateModel(index) end
    for _, guard in ipairs(self.Document.guards) do self:UpdateModel("guard:" .. guard.guardId) end
    if IsValid(self.ReferenceModel) then
        self.ReferenceModel:SetPos(self.Origin + Vector(0, 0, self.ReferenceOffset or 0))
    end
    self:BuildGrid(self.GridHeight or 1)
    self.SceneRefresh = true
    self.CellTilePending = nil
    self:RefreshCellTileControls()
    return true
end

function Editor:RefreshCameraControls()
    self.Refreshing = true
    if IsValid(self.ViewZoom) then self.ViewZoom:SetValue(self.CameraDistance) end
    if IsValid(self.ViewYaw) then self.ViewYaw:SetValue(self.CameraYaw) end
    if IsValid(self.ViewPitch) then self.ViewPitch:SetValue(self.CameraPitch) end
    if IsValid(self.ViewPanX) then self.ViewPanX:SetValue(self.CameraPanX or 0) end
    if IsValid(self.ViewPanY) then self.ViewPanY:SetValue(self.CameraPanY or 0) end
    self.Refreshing = false
end

function Editor:RefreshViewControls()
    self:RefreshCameraControls()
    self.Refreshing = true
    if IsValid(self.ViewPositionSnap) then self.ViewPositionSnap:SetValue(self.PositionSnap) end
    if IsValid(self.ViewRotationSnap) then self.ViewRotationSnap:SetValue(self.RotationSnap) end
    if IsValid(self.GridToggle) then self.GridToggle:SetValue(self.ShowGrid and 1 or 0) end
    if IsValid(self.CompassToggle) then self.CompassToggle:SetValue(self.ShowCompass and 1 or 0) end
    if IsValid(self.SnapToggle) then self.SnapToggle:SetValue(self.SnapEnabled and 1 or 0) end
    if IsValid(self.GridChoice) then self.GridChoice:SetValue(tostring(self.GridSpacing) .. " units") end
    if IsValid(self.ReferenceOffsetInput) then self.ReferenceOffsetInput:SetValue(self.ReferenceOffset or 0) end
    if IsValid(self.PrefabOffsetInput) then self.PrefabOffsetInput:SetValue(self.PrefabPreviewOffset or 0) end
    if self.PrefabHorizontalInputs then
        self.PrefabHorizontalInputs.x:SetValue(self.PrefabPreviewOffsetX or 0)
        self.PrefabHorizontalInputs.y:SetValue(self.PrefabPreviewOffsetY or 0)
    end
    self.Refreshing = false
    self:RefreshCellTileControls()
end

function Editor:ResetView()
    self.CameraYaw, self.CameraPitch, self.CameraDistance = 45, 55, 1000
    self.CameraPanX, self.CameraPanY = 0, 0
    self:RefreshViewControls()
end

function Editor:ClearReference()
    if IsValid(self.ReferenceModel) then self.ReferenceModel:Remove() end
    self.ReferenceModel = nil
    self.ReferenceTop = nil
    self.SceneRefresh = true
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
    model:SetPos(self.Origin + Vector(0, 0, self.ReferenceOffset or 0))
    model:SetAngles(Angle(0, 0, 0))
    self.ReferenceModel = model
    self.ReferenceTop = maximum.z
    self:BuildGrid(maximum.z + (self.ReferenceOffset or 0) + 1)
    return true
end

function Editor:SetReferenceChoices(references)
    if not IsValid(self.ReferenceChoice) then return end
    self.ReferenceChoice:Clear()
    self.ReferenceChoice:AddChoice("No reference", "")
    self.ReferenceLabels = {}
    for _, reference in ipairs(references) do
        self.ReferenceChoice:AddChoice(reference.label, reference.model)
        self.ReferenceLabels[reference.model] = reference.label
    end
    self.ReferenceChoice:SetValue(self.ReferenceWanted and self.ReferenceLabels[self.ReferenceWanted] or "No reference")
end

function Editor:SetParticleChoices(definitions)
    if not IsValid(self.ParticleChoice) then return end
    self.ParticleChoice:Clear()
    self.ParticleDefinitions = definitions
    self.SelectedParticleEffect = nil
    for _, definition in ipairs(definitions) do
        self.ParticleChoice:AddChoice(definition.label, definition.id)
        if not self.SelectedParticleEffect then
            self.SelectedParticleEffect = definition.id
            self.ParticleChoice:SetValue(definition.label)
        end
    end
    if not self.SelectedParticleEffect then self:Message("The particle effect catalog is empty.", true) end
    self:RefreshInspector()
end

function Editor:SetGuardWeapons(choices)
    if not self:IsActive() then return end
    local byId, problem = Contract.ValidateGuardWeaponChoices(choices)
    if not byId then self:Message(problem, true) return end
    self.GuardWeapons, self.GuardWeaponChoices = byId, choices
    if IsValid(self.GuardWeapon) then
        self.GuardWeapon:Clear()
        for _, weapon in ipairs(choices) do self.GuardWeapon:AddChoice(weapon.label, weapon.id) end
    end
    for _, guard in ipairs(self.Document.guards) do
        if not byId[guard.weapon] then
            self:Message("Guard weapon is unavailable: " .. tostring(guard.weapon), true)
        elseif not self.GuardModels[guard.guardId] then
            self:MakeGuardModel(guard)
        end
    end
    self:RefreshInspector()
end

function Editor:PopulateLootGroups()
    self.LootGroup:Clear()
    self.LootGroup:AddChoice("Model default", "")
    self.LootGroupLabels, self.LootGroupsReady, self.LastLootGroupWarning = {}, false, nil
    local registry = ZM_StaticData and ZM_StaticData:GetRegistry()
    if not registry or type(registry.lootGroups) ~= "table" then
        self.LootGroup:SetValue("Loot groups unavailable")
        self:Message("The loot group registry is unavailable.", true)
        return false
    end
    local ids = {}
    for id, group in pairs(registry.lootGroups) do
        if type(id) ~= "string" or type(group) ~= "table" or type(group.entries) ~= "table" then
            self:Message("The loot group registry contains invalid data.", true)
            return false
        end
        if #group.entries > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local name = string.gsub(string.gsub(id, "^loot", ""), "(%l)(%u)", "%1 %2")
        name = string.gsub(name, "_", " ")
        if name == "" then name = id end
        local label = name .. " (" .. id .. ")"
        self.LootGroupLabels[id] = label
        self.LootGroup:AddChoice(label, id)
    end
    self.LootGroupsReady = true
    return true
end

function Editor:UpdateAreaLayout()
    if not IsValid(self.AreaContainer) or not IsValid(self.Workspace) then return end
    local open = self.ActiveArea ~= nil
    self.AreaContainer:SetWide(open and math.Clamp(ScrW() - 520, 190, 290) or 0)
    self.AreaContainer:SetVisible(open)
    for name, panel in pairs(self.AreaPanels or {}) do panel:SetVisible(name == self.ActiveArea) end
    self.Workspace:InvalidateLayout(true)
end

function Editor:ToggleArea(name)
    if not self.AreaPanels or not self.AreaPanels[name] then
        ErrorNoHalt("[ZombieSim] Prefab editor: unknown workflow area " .. tostring(name) .. ".\n")
        return false
    end
    if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
    self.Drag = nil
    if self.ActiveArea == name then self.ActiveArea = nil else self.ActiveArea = name end
    self:UpdateAreaLayout()
    return true
end

function Editor:Open(data)
    if self:IsActive() then return end
    if type(data) ~= "table" or type(data.origin) ~= "table" or type(data.documents) ~= "table"
        or not finiteNumber(data.origin.x) or not finiteNumber(data.origin.y) or not finiteNumber(data.origin.z) then
        self:Message("The editor workspace response is invalid.", true)
        return
    end
    if data.cell ~= nil and (type(data.cell) ~= "table" or not EditorMap.IsValidCellId(data.cell.id)
        or not finiteNumber(data.cell.x) or not finiteNumber(data.cell.y)
        or not EditorMap.IsValidTile(data.cell.tileX) or not EditorMap.IsValidTile(data.cell.tileY)
        or not finiteNumber(data.cell.tileSize) or data.cell.tileSize <= 0) then
        self:Message("The editor cell context is invalid; the saved draft was preserved.", true)
        return
    end
    if data.transitionTarget then
        Derma_Query("The change to " .. tostring(data.transitionTarget)
            .. " is still pending. Your saved tab snapshot is preserved.", "Prefab editor",
            "Retry switch", function() send("switch_retry") end, "Keep waiting", function() end)
        return
    end
    local snapshot, snapshotEncoded
    if data.transferToken then
        snapshot, snapshotEncoded = MapTransfer:Read(data.transferToken, data.openIds)
        if not snapshot then
            Derma_Query(tostring(snapshotEncoded), "Prefab editor recovery",
                "Retry", function() send("status") end,
                "Return to previous map", function() send("switch_return") end)
            return
        end
    end
    if not ZM_World then self:Message("Preview world data is unavailable.", true) return end
    if ZM_World.ActiveProfile ~= "preview" then
        local loaded, problem = ZM_World:LoadProfile("preview")
        if not loaded then self:Message(problem or "Could not load preview world data.", true) return end
    end
    self.Active = true
    self.Cell, self.CellTilePending = data.cell, nil
    self.Origin = Vector(data.origin.x, data.origin.y, data.origin.z)
    self.CameraYaw, self.CameraPitch, self.CameraDistance = 45, 55, 1000
    self.PositionSnap, self.RotationSnap, self.SnapEnabled = 16, 15, true
    self.Mode, self.Models, self.GuardModels, self.Revision, self.LastPropClick = "move", {}, {}, 0, nil
    self.ActiveArea = nil
    self.Tabs, self.ActiveTab, self.PendingRequests, self.PendingLoads = {}, nil, {}, {}
    self.TabSerial, self.RequestSerial, self.SwitchSerial = 0, 0, 0
    self.Saving = false
    self.ParticleDefinitions, self.SelectedParticleEffect = {}, nil
    self.GuardWeapons, self.GuardWeaponChoices = nil, nil
    self.PreviewFog, self.PreviewDark = nil, false
    self.GuardWeapons, self.GuardWeaponChoices = nil, nil
    self:BuildGrid(1)

    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSkin("ZombieSim")
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetTitle("")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:DockPadding(0, 0, 0, 0)
    frame.Paint = function() end
    frame:MakePopup()
    frame.OnRemove = function()
        if self.Drag and self.Drag.panel then self.Drag.panel:MouseCapture(false) end
        if ZM_PrefabLightPreview then ZM_PrefabLightPreview:Clear() end
        if ZM_PrefabParticleProbe then ZM_PrefabParticleProbe:Stop() end
        if ZM_PrefabParticlePreview then ZM_PrefabParticlePreview:Clear() end
        self:ClearModels()
        if IsValid(self.ReferenceModel) then self.ReferenceModel:Remove() end
        self.ReferenceModel, self.ReferenceWanted = nil, nil
        self.Active, self.Frame, self.Drag, self.GridLines, self.LastPropClick, self.RotationSelection =
            false, nil, nil, nil, nil, nil
        self.ActiveArea, self.AreaPanels, self.AreaContainer, self.AreaButtons, self.Workspace, self.Viewport =
            nil, nil, nil, nil, nil, nil
        self.Tabs, self.ActiveTab, self.TabScroller, self.PendingRequests, self.PendingLoads = nil, nil, nil, nil, nil
        self.MapBrowser, self.MapSwitchOverlay, self.MapSwitchToken, self.SwitchingMap = nil, nil, nil, nil
        self.Cell, self.CellTilePending, self.CellTilePanel, self.CellTileX, self.CellTileY = nil, nil, nil, nil, nil
        self.PreviewFog, self.PreviewDark = nil, false
    end
    frame.OnKeyCodePressed = function(_, key)
        if not self.SwitchingMap and key == KEY_ESCAPE then self:Exit() end
    end

    local palette = ZM_DermaSkin.Palette
    local toolbar = vgui.Create("DPanel", frame)
    toolbar:Dock(TOP)
    toolbar:SetZPos(0)
    toolbar:SetTall(42)
    toolbar:DockPadding(8, 4, 8, 4)
    toolbar.Paint = function(_, w, h)
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(palette.border)
        surface.DrawRect(0, h - 2, w, 2)
    end
    local function areaButton(text, name, z)
        local control = vgui.Create("DButton", toolbar)
        control:Dock(LEFT)
        control:SetZPos(z)
        control:DockMargin(0, 0, 5, 0)
        control:SetWide(100)
        control:SetFont("ZM_DermaButton")
        control:SetText(text)
        control:SetTextColor(palette.text)
        control.Paint = function(panel, w, h)
            local active = self.ActiveArea == name
            surface.SetDrawColor(active and palette.redDark or panel.Hovered and palette.border or palette.raised)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(active and palette.redBright or palette.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            if active then surface.DrawRect(2, h - 3, w - 4, 2) end
        end
        control.DoClick = function() self:ToggleArea(name) end
        return control
    end
    self.AreaButtons = {
        prefab = areaButton("PREFAB", "prefab", 1),
        place = areaButton("PLACE", "place", 2),
        scene = areaButton("SCENE", "scene", 3),
        view = areaButton("VIEW", "view", 4)
    }
    local exitButton = vgui.Create("DButton", toolbar)
    exitButton:Dock(RIGHT)
    exitButton:SetZPos(5)
    exitButton:SetWide(150)
    exitButton:SetText("RETURN TO LAUNCHER")
    exitButton.DoClick = function() self:Exit() end
    self.MapButton = vgui.Create("DButton", toolbar)
    self.MapButton:Dock(RIGHT)
    self.MapButton:SetZPos(6)
    self.MapButton:SetWide(110)
    self.MapButton:SetText("CHANGE MAP")
    self.MapButton.DoClick = function() self:OpenMapBrowser() end

    local tabBar = vgui.Create("DPanel", frame)
    tabBar:Dock(TOP)
    tabBar:SetZPos(1)
    tabBar:SetTall(34)
    tabBar:DockPadding(8, 2, 8, 2)
    tabBar.Paint = function(_, w, h)
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(palette.border)
        surface.DrawRect(0, h - 1, w, 1)
    end
    local newTab = vgui.Create("DButton", tabBar)
    newTab:Dock(RIGHT)
    newTab:SetZPos(0)
    newTab:SetWide(36)
    newTab:SetText("+")
    newTab:SetTooltip("New prefab tab")
    newTab.DoClick = function() self:CreateTab(blankDocument(), nil, true) end
    self.TabScroller = vgui.Create("DHorizontalScroller", tabBar)
    self.TabScroller:Dock(FILL)
    self.TabScroller:SetZPos(1)
    self.TabScroller:SetOverlap(-4)

    local workspace = vgui.Create("DPanel", frame)
    self.Workspace = workspace
    workspace:Dock(FILL)
    workspace:SetZPos(2)
    workspace.Paint = function() end
    local areaContainer = vgui.Create("DPanel", workspace)
    self.AreaContainer = areaContainer
    areaContainer:Dock(LEFT)
    areaContainer:SetZPos(0)
    areaContainer:SetWide(0)
    areaContainer:SetVisible(false)
    areaContainer.Paint = function(_, w, h)
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    self.AreaPanels = {}
    for _, name in ipairs({ "prefab", "place", "scene", "view" }) do
        local panel = vgui.Create("DScrollPanel", areaContainer)
        panel:Dock(FILL)
        panel:SetVisible(false)
        panel.Paint = function() end
        self.AreaPanels[name] = panel
    end
    local left, place, scene, view = self.AreaPanels.prefab, self.AreaPanels.place,
        self.AreaPanels.scene, self.AreaPanels.view
    label(left, "PREFABS")
    button(left, "OPEN PREFAB EXPLORER", function() ZM_PrefabExplorer:Open() end)
    self.PrefabList = vgui.Create("DListView", left)
    styleList(self.PrefabList)
    self.PrefabList:Dock(TOP)
    self.PrefabList:DockMargin(6, 2, 6, 2)
    self.PrefabList:SetTall(110)
    self.PrefabList:AddColumn("Name")
    self.PrefabList:AddColumn("ID")
    self.PrefabList.OnRowSelected = function(_, _, row)
        self:OpenSaved(row.PrefabId)
    end
    button(left, "NEW PREFAB", function()
        if not snapshot then self:CreateTab(blankDocument(), nil, true) end
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
    self.TagSuggestions = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", left))
    self.TagSuggestions:Dock(TOP); self.TagSuggestions:DockMargin(6, 0, 6, 2); self.TagSuggestions:SetTall(24)
    self.TagSuggestions:SetValue("Add a suggested tag...")
    for _, tag in ipairs(Contract.GetTagSuggestions()) do self.TagSuggestions:AddChoice(tag, tag) end
    self.TagSuggestions.OnSelect = function(_, _, _, tag)
        self:SyncMetadata()
        for _, existing in ipairs(self.Document.tags) do
            if string.lower(existing) == string.lower(tag) then return end
        end
        self.Document.tags[#self.Document.tags + 1] = tag
        self:MarkChanged()
        self:RefreshDocument()
    end
    self.WorldPlacementToggle = vgui.Create("DCheckBoxLabel", left)
    self.WorldPlacementToggle:Dock(TOP); self.WorldPlacementToggle:DockMargin(6, 6, 6, 3)
    self.WorldPlacementToggle:SetText("World prefab: automatic placement")
    self.WorldPlacementToggle.OnChange = function(_, checked)
        if self.Refreshing or self.SwitchingMap then return end
        local placement = self.Document.worldPlacement
        if not placement then
            if not checked then return end
            placement = { enabled = true, profile = "preview",
                cellX = self.Cell and self.Cell.x or 0, cellY = self.Cell and self.Cell.y or 0,
                tileX = self.Cell and self.Cell.tileX or 0, tileY = self.Cell and self.Cell.tileY or 0,
                offset = { x = self.PrefabPreviewOffsetX or 0, y = self.PrefabPreviewOffsetY or 0,
                    z = self.PrefabPreviewOffset or 0 }, angles = { p = 0, y = 0, r = 0 } }
            self.Document.worldPlacement = placement
        end
        placement.enabled = checked
        self:MarkChanged()
        self:RefreshDocument()
    end
    local worldPanel = vgui.Create("DPanel", left)
    self.WorldPlacementPanel = worldPanel
    worldPanel:Dock(TOP); worldPanel:SetTall(400)
    worldPanel.Paint = function() end
    label(worldPanel, "Requires explicit export; applies on cell load.")
    self.WorldProfile = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", worldPanel))
    self.WorldProfile:Dock(TOP); self.WorldProfile:DockMargin(6, 0, 6, 2); self.WorldProfile:SetTall(24)
    self.WorldProfile:AddChoice("Preview", "preview"); self.WorldProfile:AddChoice("City", "city")
    self.WorldProfile.OnSelect = function(_, _, _, profile)
        if self.Refreshing or self.SwitchingMap or not self.Document.worldPlacement then return end
        self.Document.worldPlacement.profile = profile; self:MarkChanged()
    end
    local function setPlacement(key, value)
        if not self.Document.worldPlacement then return end
        self.Document.worldPlacement[key] = value; self:MarkChanged()
    end
    self.WorldPlacementControls = numberRow(worldPanel, "LOGICAL CELL",
        { { "X", "cellX" }, { "Y", "cellY" } }, setPlacement)
    local tiles = numberRow(worldPanel, "CORE TILE (EAST +X / NORTH +Y)",
        { { "X", "tileX", -2, 2 }, { "Y", "tileY", -2, 2 } }, setPlacement)
    for key, control in pairs(tiles) do self.WorldPlacementControls[key] = control end
    self.WorldOffsetControls = numberRow(worldPanel, "OFFSET FROM TILE SURFACE",
        { { "X", "x", nil, nil, 3 }, { "Y", "y", nil, nil, 3 }, { "Z", "z", nil, nil, 3 } }, function(key, value)
            if not self.Document.worldPlacement then return end
            self.Document.worldPlacement.offset[key] = value; self:MarkChanged()
        end)
    self.WorldAngleControls = numberRow(worldPanel, "WORLD ROTATION (APPLIED ON CELL LOAD)",
        { { "Pitch", "p", nil, nil, 3 }, { "Yaw", "y", nil, nil, 3 }, { "Roll", "r", nil, nil, 3 } }, function(key, value)
            if not self.Document.worldPlacement then return end
            self.Document.worldPlacement.angles[key] = value; self:MarkChanged()
        end)
    button(worldPanel, "USE CURRENT PREVIEW PLACEMENT", function() self:UseCurrentWorldPlacement() end)
    button(worldPanel, "CONVERT BACK TO TAG PREFAB", function()
        self.Document.worldPlacement = nil; self:MarkChanged(); self:RefreshDocument()
    end)
    button(left, "SAVE", function() self:Save(false) end)
    button(left, "DELETE SAVED PREFAB", function()
        if not self.OpenedId then self:Message("Open a saved prefab before deleting it.", true) return end
        local tab, id = self.ActiveTab, self.OpenedId
        Derma_Query("Permanently delete prefab '" .. id .. "'?", "Prefab editor",
            "Delete", function() self:RequestDelete(tab) end, "Cancel", function() end)
    end)
    label(place, "PLACE OBJECTS")
    self.ModelFolder = textEntry(place, "Mounted folder", function() end)
    self.ModelFolder:SetValue("models/props_c17/")
    button(place, "OPEN MODEL BROWSER", function() self:OpenModelBrowser() end)
    self.ModelPath = textEntry(place, "Model path", function() end)
    button(place, "ADD PROP", function() self:RequestModel(string.Trim(self.ModelPath:GetValue())) end)
    button(place, "ADD GUARD", function() self:AddGuard() end)
    button(place, "ADD SPOTLIGHT", function() self:AddLight() end)
    label(place, "PARTICLE EFFECT")
    self.ParticleChoice = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", place))
    self.ParticleChoice:Dock(TOP)
    self.ParticleChoice:DockMargin(6, 0, 6, 2)
    self.ParticleChoice:SetTall(24)
    self.ParticleChoice:SetValue("Loading effects...")
    self.ParticleChoice.OnSelect = function(_, _, _, effect)
        self.SelectedParticleEffect = effect
        local particle = self:SelectionKind() == "particle" and self:GetSelectedObject() or nil
        if particle and particle.effect ~= effect then
            particle.effect = effect
            self:MarkChanged()
            self:RefreshInspector()
        end
    end
    button(place, "ADD PARTICLE", function() self:AddParticle() end)
    label(scene, "REFERENCE TILE (NOT SAVED)")
    self.ReferenceChoice = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", scene))
    self.ReferenceChoice:Dock(TOP)
    self.ReferenceChoice:DockMargin(6, 0, 6, 2)
    self.ReferenceChoice:SetTall(24)
    self.ReferenceChoice:AddChoice("No reference", "")
    self.ReferenceChoice:SetValue("No reference")
    self.ReferenceChoice.OnSelect = function(_, _, _, path)
        self:RequestReference(path)
    end
    self.ReferenceOffsetInput = numberEntry(scene, "Reference height offset (preview only)",
        -32768, 32768, 3, function(value)
            if value and value == value and value > -math.huge and value < math.huge then
                self:SetReferenceOffset(math.Clamp(value, -32768, 32768))
            end
        end)
    local previewOffsets = numberRow(scene, "PREFAB OFFSET (PREVIEW ONLY)",
        { { "X", "x", nil, nil, 3 }, { "Y", "y", nil, nil, 3 }, { "Z", "z", nil, nil, 3 } }, function(key, value)
            if key == "z" then self:SetPrefabPreviewOffset(value) else self:SetPrefabPreviewHorizontal(key, value) end
        end)
    self.PrefabOffsetInput = previewOffsets.z
    self.PrefabHorizontalInputs = { x = previewOffsets.x, y = previewOffsets.y }
    label(scene, "ATMOSPHERE PREVIEW")
    local fog = vgui.Create("DCheckBoxLabel", scene)
    fog:Dock(TOP); fog:DockMargin(6, 3, 6, 3); fog:SetText("Preview inner-city fog"); fog:SetValue(0)
    fog.OnChange = function(control, checked)
        if self.Refreshing then return end
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
    local dark = vgui.Create("DCheckBoxLabel", scene)
    dark:Dock(TOP); dark:DockMargin(6, 3, 6, 3); dark:SetText("Dark preview (simulated)"); dark:SetValue(0)
    dark.OnChange = function(_, checked) if not self.Refreshing then self.PreviewDark = checked end end
    self.DarkToggle = dark

    label(view, "CAMERA")
    self.CellTilePanel = vgui.Create("DPanel", view)
    self.CellTilePanel:Dock(TOP)
    self.CellTilePanel:SetTall(76)
    self.CellTilePanel.Paint = function() end
    label(self.CellTilePanel, "CELL TILE (CENTRE 0, 0)")
    local tileRow = vgui.Create("DPanel", self.CellTilePanel)
    tileRow:Dock(TOP); tileRow:DockMargin(6, 0, 6, 2); tileRow:SetTall(42); tileRow.Paint = function() end
    local tileColumns = {}
    for _, axis in ipairs({ "x", "y" }) do
        local column = vgui.Create("DPanel", tileRow)
        column:Dock(LEFT); column.Paint = function() end
        local caption = vgui.Create("DLabel", column)
        caption:Dock(TOP); caption:SetTall(16); caption:SetText(axis == "x" and "X (east +)" or "Y (north +)")
        local control = vgui.Create("DNumberWang", column)
        control:Dock(FILL); control:DockMargin(0, 0, 4, 0)
        control:SetMin(-2); control:SetMax(2); control:SetDecimals(0)
        local key = axis
        control.OnValueChanged = function(_, value)
            if self.Refreshing or not self.Cell or self.SwitchingMap or self.CellTilePending then return end
            local number = tonumber(value)
            if not EditorMap.IsValidTile(number) then self:RefreshCellTileControls() return end
            if key == "x" then self:RequestCellTile(number, self.Cell.tileY)
            else self:RequestCellTile(self.Cell.tileX, number) end
        end
        if axis == "x" then self.CellTileX = control else self.CellTileY = control end
        tileColumns[#tileColumns + 1] = column
    end
    tileRow.PerformLayout = function(_, width)
        for _, column in ipairs(tileColumns) do column:SetWide(math.floor(width / 2)) end
    end
    self:RefreshCellTileControls()
    self.ViewZoom = numberEntry(view, "Distance", 64, 2400, 1, function(value)
        if value and value == value then self.CameraDistance = math.Clamp(value, 64, 2400) end
    end)
    self.ViewYaw = numberEntry(view, "Yaw (degrees)", -1000000, 1000000, 2, function(value)
        if value and value == value then self.CameraYaw = math.Clamp(value, -1000000, 1000000) end
    end)
    self.ViewPitch = numberEntry(view, "Pitch (degrees)", 15, 85, 2, function(value)
        if value and value == value then self.CameraPitch = math.Clamp(value, 15, 85) end
    end)
    self.ViewPanX = numberEntry(view, "Pan X", -32768, 32768, 2, function(value)
        if value and value == value then self.CameraPanX = math.Clamp(value, -32768, 32768) end
    end)
    self.ViewPanY = numberEntry(view, "Pan Y", -32768, 32768, 2, function(value)
        if value and value == value then self.CameraPanY = math.Clamp(value, -32768, 32768) end
    end)
    button(view, "RESET CAMERA", function() self:ResetView() end)
    local viewHelp = label(view, "Right-drag: orbit. Shift + right-drag: pan. Wheel: zoom.")
    viewHelp:SetTall(36)
    viewHelp:SetWrap(true)
    label(view, "GRID AND SNAPPING")
    self.GridToggle = vgui.Create("DCheckBoxLabel", view)
    self.GridToggle:Dock(TOP); self.GridToggle:DockMargin(6, 3, 6, 3); self.GridToggle:SetText("Show grid")
    self.GridToggle.OnChange = function(_, checked) if not self.Refreshing then self.ShowGrid = checked end end
    self.CompassToggle = vgui.Create("DCheckBoxLabel", view)
    self.CompassToggle:Dock(TOP); self.CompassToggle:DockMargin(6, 3, 6, 3); self.CompassToggle:SetText("Show compass")
    self.CompassToggle.OnChange = function(_, checked) if not self.Refreshing then self.ShowCompass = checked end end
    label(view, "Grid spacing")
    self.GridChoice = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", view))
    self.GridChoice:Dock(TOP); self.GridChoice:DockMargin(6, 0, 6, 2); self.GridChoice:SetTall(24)
    for _, spacing in ipairs({ 16, 32, 64, 128, 160, 320 }) do
        self.GridChoice:AddChoice(tostring(spacing) .. " units", spacing)
    end
    self.GridChoice.OnSelect = function(_, _, _, spacing)
        self.GridSpacing = spacing
        self:BuildGrid(self.GridHeight)
    end
    self.SnapToggle = vgui.Create("DCheckBoxLabel", view)
    self.SnapToggle:Dock(TOP); self.SnapToggle:DockMargin(6, 3, 6, 3); self.SnapToggle:SetText("Enable snapping")
    self.SnapToggle.OnChange = function(_, checked) if not self.Refreshing then self.SnapEnabled = checked end end
    self.ViewPositionSnap = numberEntry(view, "Position snap (units)", 0, 640, 2, function(value)
        if value and value == value then self.PositionSnap = math.Clamp(value, 0, 640) end
    end)
    self.ViewRotationSnap = numberEntry(view, "Rotation snap (degrees)", 0, 360, 2, function(value)
        if value and value == value then self.RotationSnap = math.Clamp(value, 0, 360) end
    end)

    local right = vgui.Create("DScrollPanel", workspace)
    self.InspectorPanel = right
    right:Dock(RIGHT)
    right:SetZPos(1)
    right:SetWide(260)
    right.Paint = function(_, w, h)
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    label(right, "PROPS")
    self.PropList = vgui.Create("DListView", right)
    styleList(self.PropList)
    self.PropList:Dock(TOP)
    self.PropList:DockMargin(6, 2, 6, 2)
    self.PropList:SetTall(100)
    self.PropList:AddColumn("Model")
    self.PropList.OnRowSelected = function(_, _, row)
        self:Select(row.PrefabIndex)
    end
    label(right, "SPOTLIGHTS")
    self.LightList = vgui.Create("DListView", right)
    styleList(self.LightList)
    self.LightList:Dock(TOP)
    self.LightList:DockMargin(6, 2, 6, 2)
    self.LightList:SetTall(70)
    self.LightList:AddColumn("Light ID")
    self.LightList.OnRowSelected = function(_, _, row) self:Select(-row.PrefabLightIndex) end
    label(right, "PARTICLES")
    self.ParticleList = vgui.Create("DListView", right)
    styleList(self.ParticleList)
    self.ParticleList:Dock(TOP)
    self.ParticleList:DockMargin(6, 2, 6, 2)
    self.ParticleList:SetTall(70)
    self.ParticleList:AddColumn("Particle ID")
    self.ParticleList:AddColumn("Effect")
    self.ParticleList.OnRowSelected = function(_, _, row) self:Select("particle:" .. row.PrefabParticleId) end
    label(right, "GUARDS")
    self.GuardList = vgui.Create("DListView", right)
    styleList(self.GuardList)
    self.GuardList:Dock(TOP)
    self.GuardList:DockMargin(6, 2, 6, 2)
    self.GuardList:SetTall(70)
    self.GuardList:AddColumn("Name")
    self.GuardList:AddColumn("Guard ID")
    self.GuardList.OnRowSelected = function(_, _, row) self:Select("guard:" .. row.PrefabGuardId) end
    self.EmptySelection = label(right, "Select an object to edit its properties.")
    local function inspectorGroup(height)
        local panel = vgui.Create("DPanel", right)
        panel:Dock(TOP)
        panel:SetTall(height)
        panel.Paint = function() end
        return panel
    end
    self.SelectionPanel = inspectorGroup(222)
    self.PropPanel = inspectorGroup(340)
    self.LightPanel = inspectorGroup(330)
    self.ParticlePanel = inspectorGroup(110)
    self.GuardPanel = inspectorGroup(620)
    local selection, propPanel, lightPanel, particlePanel =
        self.SelectionPanel, self.PropPanel, self.LightPanel, self.ParticlePanel
    local guardPanel = self.GuardPanel
    local function selectedGuard()
        return self:SelectionKind() == "guard" and self:GetSelectedObject() or nil
    end
    local function replaceGuardPreview(guard, field, value)
        if not guard or guard[field] == value then return end
        local previous, old = guard[field], self.GuardModels[guard.guardId]
        guard[field] = value
        if not self:MakeGuardModel(guard) then
            guard[field] = previous
            self:RefreshInspector()
            return
        end
        if old then ZM_PrefabGuardPreview:Remove(old) end
        self:MarkChanged()
        self:RefreshInspector()
    end
    local function guardCombo(title)
        label(guardPanel, title)
        local combo = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", guardPanel))
        combo:Dock(TOP); combo:DockMargin(6, 0, 6, 2); combo:SetTall(24)
        return combo
    end
    label(guardPanel, "GUARD")
    self.GuardName = textEntry(guardPanel, "Name", function(value)
        local guard = selectedGuard()
        if guard and guard.name ~= value then guard.name = value; self:MarkChanged() end
    end)
    self.GuardModel = guardCombo("Citizen model")
    local models = {}
    for path in pairs(ZM_Clothing and ZM_Clothing.Models or {}) do models[#models + 1] = path end
    table.sort(models)
    for _, path in ipairs(models) do self.GuardModel:AddChoice(path, path) end
    self.GuardModel.OnSelect = function(_, _, _, path)
        if self.Refreshing or not ZM_Clothing or not ZM_Clothing.Models[path] then return end
        replaceGuardPreview(selectedGuard(), "model", path)
    end
    self.GuardIdle = guardCombo("Idle animation")
    self.GuardIdle.OnSelect = function(_, _, _, idle)
        local guard = selectedGuard()
        if self.Refreshing or not guard or type(idle) ~= "string" or guard.idle == idle then return end
        guard.idle = idle
        self:UpdateModel(self.Selected); self:MarkChanged()
    end
    self.GuardWeapon = guardCombo("Weapon")
    self.GuardWeapon.OnSelect = function(_, _, _, id)
        local guard = selectedGuard()
        local weapon = self.GuardWeapons and self.GuardWeapons[id]
        if self.Refreshing or not guard or not weapon or guard.weapon == id then return end
        if guard.range > weapon.range then
            self:Message("Reduce the engagement range before selecting this weapon.", true)
            self:RefreshInspector()
            return
        end
        replaceGuardPreview(guard, "weapon", id)
    end
    self.GuardRange = numberEntry(guardPanel, "Engagement range", 0.001, 1000000, 3, function(value)
        local guard = selectedGuard()
        if guard and value and value == value and guard.range ~= value then
            guard.range = value; self:MarkChanged()
        end
    end)
    local function clothingCombo(garment)
        local combo = guardCombo(garment == "shirt" and "Shirt" or "Pants")
        combo:AddChoice("Model default", "")
        local finishes = {}
        for id, finish in pairs(ZM_Clothing and ZM_Clothing.Finishes or {}) do
            if not finish.garment or finish.garment == garment then finishes[#finishes + 1] = id end
        end
        table.sort(finishes)
        for _, id in ipairs(finishes) do combo:AddChoice(id, id) end
        combo.OnSelect = function(_, _, _, value)
            local guard = selectedGuard()
            if self.Refreshing or not guard or guard[garment] == value then return end
            guard[garment] = value
            self:MarkChanged(); self:RefreshInspector()
        end
        return combo
    end
    self.GuardShirt, self.GuardPants = clothingCombo("shirt"), clothingCombo("pants")
    self.GuardOverrides = {}
    for _, definition in ipairs({
        { field = "damage", weaponField = "damage", title = "Override damage per shot", min = 0.001 },
        { field = "fireInterval", weaponField = "delay", title = "Override fire interval (seconds per shot)",
            min = Contract.MinGuardFireInterval },
        { field = "spread", weaponField = "spread", title = "Override shot spread (lower is more accurate)", min = 0 }
    }) do
        local field, weaponField = definition.field, definition.weaponField
        local toggle = vgui.Create("DCheckBoxLabel", guardPanel)
        toggle:Dock(TOP); toggle:DockMargin(6, 3, 6, 3); toggle:SetText(definition.title)
        local control = numberEntry(guardPanel, "Value", definition.min, 1000000, 3, function(value)
            local guard = selectedGuard()
            if not guard or guard[field] == nil or not value or value ~= value then return end
            local candidate = { damage = guard.damage, fireInterval = guard.fireInterval, spread = guard.spread }
            candidate[field] = value
            if not Contract.ValidateGuardCombat(candidate) then return end
            if guard[field] ~= value then guard[field] = value; self:MarkChanged() end
        end)
        toggle.OnChange = function(_, checked)
            local guard = selectedGuard()
            local weapon = guard and self.GuardWeapons and self.GuardWeapons[guard.weapon]
            if self.Refreshing or not guard or not weapon then return end
            local value = checked and weapon[weaponField] or nil
            if guard[field] ~= value then guard[field] = value; self:MarkChanged() end
            self:RefreshInspector()
        end
        self.GuardOverrides[#self.GuardOverrides + 1] = {
            toggle = toggle, control = control, field = field, weaponField = weaponField
        }
    end
    label(particlePanel, "PARTICLE")
    self.ParticleMode = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", particlePanel))
    self.ParticleMode:Dock(TOP)
    self.ParticleMode:DockMargin(6, 0, 6, 2)
    self.ParticleMode:SetTall(24)
    self.ParticleMode:AddChoice("Continuous", "continuous")
    self.ParticleMode:AddChoice("Triggered", "triggered")
    self.ParticleMode.OnSelect = function(_, _, _, mode)
        local particle = self:SelectionKind() == "particle" and self:GetSelectedObject() or nil
        if self.Refreshing or not particle or particle.mode == mode then return end
        particle.mode = mode
        self:MarkChanged()
        self:RefreshInspector()
    end
    self.ParticleOverlap = vgui.Create("DCheckBoxLabel", particlePanel)
    self.ParticleOverlap:Dock(TOP)
    self.ParticleOverlap:DockMargin(6, 3, 6, 3)
    self.ParticleOverlap:SetText("Allow triggered bursts to overlap")
    self.ParticleOverlap.OnChange = function(_, checked)
        local particle = self:SelectionKind() == "particle" and self:GetSelectedObject() or nil
        if self.Refreshing or not particle or particle.mode ~= "triggered" or particle.overlap == checked then return end
        particle.overlap = checked
        self:MarkChanged()
    end
    self.ParticleTrigger = button(particlePanel, "PREVIEW TRIGGER", function()
        local particle = self:SelectionKind() == "particle" and self:GetSelectedObject() or nil
        if not particle or not ZM_PrefabParticlePreview then
            self:Message("The triggered particle preview is unavailable.", true)
            return
        end
        local ok, problem = ZM_PrefabParticlePreview:Trigger(particle.particleId)
        if not ok then self:Message(problem, true) end
    end)
    label(propPanel, "PROP")
    self.MovableToggle = vgui.Create("DCheckBoxLabel", propPanel)
    self.MovableToggle:Dock(TOP)
    self.MovableToggle:DockMargin(6, 3, 6, 3)
    self.MovableToggle:SetText("Movable physics prop")
    self.MovableToggle.OnChange = function(_, checked)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if self.Refreshing or not prop or prop.movable == checked then return end
        prop.movable = checked
        self:MarkChanged()
    end
    label(propPanel, "Prop loot")
    self.LootMode = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", propPanel))
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
    label(propPanel, "Loot group override")
    self.LootGroup = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", propPanel))
    self.LootGroup:Dock(TOP)
    self.LootGroup:DockMargin(6, 0, 6, 2)
    self.LootGroup:SetTall(24)
    self.LootGroup.OnSelect = function(_, _, _, value)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if self.Refreshing or not prop or prop.lootMode == "off" then return end
        if type(value) ~= "string" or (value ~= "" and not self.LootGroupLabels[value]) then
            self:Message("The selected loot group is unavailable.", true)
            return
        end
        prop.lootGroup = value ~= "" and value or nil
        self:MarkChanged()
        self:RefreshInspector()
    end
    self:PopulateLootGroups()
    self.LootChanceToggle = vgui.Create("DCheckBoxLabel", propPanel)
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
    label(selection, "SELECTED OBJECT")
    button(selection, "REMOVE SELECTED", function()
        if not self.Selected then return end
        self:StopRotation()
        if self:SelectionKind() == "guard" then
            local selected = self:GetSelectedObject()
            local instance = selected and self.GuardModels[selected.guardId]
            if instance then ZM_PrefabGuardPreview:Remove(instance); self.GuardModels[selected.guardId] = nil end
            for index, guard in ipairs(self.Document.guards) do
                if guard == selected then table.remove(self.Document.guards, index) break end
            end
            self.SceneRefresh = true
        elseif self:SelectionKind() == "particle" then
            local selected = self:GetSelectedObject()
            for index, particle in ipairs(self.Document.particles) do
                if particle == selected then table.remove(self.Document.particles, index) break end
            end
        elseif self:SelectionKind() == "light" then
            table.remove(self.Document.lights, -self.Selected)
        else
            local model = self.Models[self.Selected]
            if IsValid(model) then model:Remove() end
            table.remove(self.Models, self.Selected)
            table.remove(self.Document.props, self.Selected)
            self.SceneRefresh = true
        end
        self.Selected, self.LastPropClick = nil, nil; self:MarkChanged(); self:RefreshInspector()
    end)
    self.ModeButton = button(selection, "MODE: MOVE", function() self:CycleMode() end)
    self.ModeButton:SetTooltip("Double-click an object to cycle modes. Select a rotation ring, then drag.")
    self.Inspector = {}
    local function addInspector(control, group, key)
        control.OnValueChanged = function(_, inputValue)
            if self.Refreshing then return end
            local value = tonumber(inputValue)
            local object = self:GetSelectedObject()
            if not object or value == nil then return end
            if self:SelectionKind() ~= "prop" and not group then return end
            if key == "scale" then value = math.Clamp(value, Contract.MinScale, Contract.MaxScale) end
            if group then object[group][key] = value else object[key] = value end
            self:UpdateModel(self.Selected); self:MarkChanged()
        end
        self.Inspector[#self.Inspector + 1] = { control = control, group = group, key = key }
    end
    local function axisRow(title, group, fields)
        label(selection, title)
        local row = vgui.Create("DPanel", selection)
        row:Dock(TOP); row:DockMargin(6, 0, 6, 2); row:SetTall(42)
        row.Paint = function() end
        local columns = {}
        for _, field in ipairs(fields) do
            local column = vgui.Create("DPanel", row)
            column:Dock(LEFT)
            column.Paint = function() end
            local caption = vgui.Create("DLabel", column)
            caption:Dock(TOP); caption:SetTall(16); caption:SetText(field[1])
            local control = vgui.Create("DNumberWang", column)
            control:Dock(FILL); control:DockMargin(0, 0, 4, 0)
            control:SetMin(-32768); control:SetMax(32768); control:SetDecimals(3)
            addInspector(control, group, field[2])
            columns[#columns + 1] = column
        end
        row.PerformLayout = function(_, width)
            for _, column in ipairs(columns) do column:SetWide(math.floor(width / 3)) end
        end
    end
    axisRow("POSITION", "position", { { "X", "x" }, { "Y", "y" }, { "Z", "z" } })
    axisRow("ROTATION", "angles", { { "X (roll)", "r" }, { "Y (pitch)", "p" }, { "Z (yaw)", "y" } })
    for _, field in ipairs({ { "Skin", "skin" }, { "Scale", "scale" } }) do
        local key = field[2]
        local minimum = key == "skin" and 0 or key == "scale" and Contract.MinScale or -32768
        local maximum = key == "scale" and Contract.MaxScale or 32768
        local control = numberEntry(propPanel, field[1], minimum, maximum, key == "skin" and 0 or 3, function() end)
        addInspector(control, nil, key)
    end
    label(lightPanel, "SPOTLIGHT")
    self.LightInspector = {}
    for _, field in ipairs({
        { "Light red", "color", "r", 0, 255, 0 },
        { "Light green", "color", "g", 0, 255, 0 },
        { "Light blue", "color", "b", 0, 255, 0 },
        { "Light brightness", nil, "brightness", 0, 1000000, 3 },
        { "Light cone angle", nil, "fov", 0.001, 179.999, 3 },
        { "Light range", nil, "range", 8.001, 1000000, 3 }
    }) do
        local group, key = field[2], field[3]
        local control = numberEntry(lightPanel, field[1], field[4], field[5], field[6], function(value)
            local light = self:SelectionKind() == "light" and self:GetSelectedObject() or nil
            if not light or value == nil then return end
            if group then light[group][key] = value else light[key] = value end
            self:MarkChanged()
        end)
        self.LightInspector[#self.LightInspector + 1] = { control = control, group = group, key = key }
    end
    self.LootChance = numberEntry(propPanel, "Configured chance % (normal activation is halved)", 0, 100, 2, function(value)
        local prop = self.Document and self.Document.props[self.Selected or 0]
        if not prop or prop.lootMode ~= "normal" or prop.lootChance == nil or value == nil then return end
        prop.lootChance = math.Clamp(value, 0, 100) / 100
        self:MarkChanged()
    end)
    self.Status = label(right, "Right-drag: orbit. Shift + right-drag: pan. Left-click: select.")
    self.Status:SetWrap(true)
    self.Status:SetTall(45)

    local viewport = vgui.Create("DPanel", workspace)
    self.Viewport = viewport
    viewport:Dock(FILL)
    viewport:SetZPos(2)
    viewport.Paint = function() end
    viewport.OnMousePressed = function(panel, code) self:BeginDrag(panel, code) end
    viewport.OnMouseReleased = function(panel, code) self:ReleaseDrag(panel, code) end
    viewport.OnMouseWheeled = function(_, delta)
        self.CameraDistance = math.Clamp(self.CameraDistance - delta * 80, 64, 2400)
        self:RefreshCameraControls()
        return true
    end
    viewport.Think = function() self:UpdateDrag() end

    for _, parent in ipairs({ left:GetCanvas(), worldPanel }) do
        for index, control in ipairs(parent:GetChildren()) do control:SetZPos(index) end
    end

    self:CreateTab(blankDocument(), nil, true)
    self:UpdateAreaLayout()
    self:SetDocuments(data.documents)
    send("particles")
    send("guard_weapons")
    send("references")
    if snapshot then self:RestoreMapSnapshot(snapshot, snapshotEncoded)
    elseif data.openId then self:OpenSaved(data.openId) end
end

function Editor:Begin(openId, onConfirm)
    Derma_Query("Open the prefab editor on gm_flatgrass? The preview launcher will reload on return.",
        "Prefab editor", "Open editor", function()
            if send("begin", openId) and onConfirm then onConfirm() end
        end, "Cancel", function() end)
end

net.Receive("ZM.PrefabEditorResponse", function()
    local action = net.ReadString()
    local success = net.ReadBool()
    local message = net.ReadString()
    local encoded = net.ReadString()
    local requestId = net.ReadString()
    if string.sub(action, 1, 9) == "explorer_" then
        local value = encoded ~= "" and util.JSONToTable(encoded) or nil
        if encoded ~= "" and type(value) ~= "table" then
            ZM_PrefabExplorer:OnResponse(action, false, "Invalid explorer response.")
        else
            ZM_PrefabExplorer:OnResponse(action, success, message, value)
        end
        return
    end
    local request = requestId ~= "" and Editor.PendingRequests and Editor.PendingRequests[requestId] or nil
    if requestId ~= "" and (not request or request.kind ~= action) then
        ErrorNoHalt("[ZombieSim] Prefab editor: unexpected response ID for " .. tostring(action) .. ".\n")
        return
    end
    if (action == "load" or action == "model" or action == "reference" or action == "save" or action == "delete"
        or action == "maps" or action == "cells" or action == "cell_tile"
        or action == "switch_map" or action == "switch_complete" or action == "switch_check")
        and not request then
        ErrorNoHalt("[ZombieSim] Prefab editor: missing response ID for " .. tostring(action) .. ".\n")
        return
    end
    if request then
        Editor.PendingRequests[requestId] = nil
        if request.tab and request.kind ~= "save" then
            request.tab.PendingCount = math.max(0, (request.tab.PendingCount or 0) - 1)
        end
        if request.kind == "load" then Editor.PendingLoads[request.id] = nil end
    end
    local function failRequest(problem, failureData)
        if request and request.kind == "save" then
            request.tab.Saving = false
            if Editor.ActiveTab == request.tab then Editor.Saving = false; Editor:RefreshDocument() end
            if request.afterSave then request.afterSave(false) end
        elseif request and request.kind == "reference" and request.tab.ReferenceRequest == requestId then
            request.tab.ReferenceRequest = nil
            if Editor.ActiveTab == request.tab then
                Editor.ReferenceWanted = nil
                Editor:ClearReference()
                if IsValid(Editor.ReferenceChoice) then Editor.ReferenceChoice:SetValue("No reference") end
            end
        elseif request and request.kind == "switch_map" then
            if type(failureData) ~= "table" or failureData.markerUnchanged ~= true then
                Derma_Query(tostring(problem) .. "\nThe map-switch snapshot has been preserved for recovery.",
                    "Prefab editor recovery", "Check session", function() Editor:CheckFailedMapSwitch(request.encoded) end,
                    "Keep waiting", function() end)
                return
            end
            local removed, removeError = MapTransfer:Remove(request.encoded)
            Editor.MapSwitchToken = nil
            Editor:UnlockMapSwitch()
            if not removed then problem = tostring(problem) .. "\n" .. tostring(removeError) end
        elseif request and request.kind == "switch_complete" then
            Derma_Query(tostring(problem) .. "\nYour tab snapshot remains available.", "Prefab editor recovery",
                "Retry", function() Editor:ConfirmMapRestore(request.token, request.encoded) end,
                "Return to previous map", function() send("switch_return") end)
            return
        elseif request and request.kind == "cell_tile" and Editor.CellTilePending == requestId then
            Editor.CellTilePending = nil
            Editor:RefreshCellTileControls()
        end
        Editor:Message(problem, true)
    end
    if not success then
        if action == "begin" and string.find(message, "pending editor map-switch draft", 1, true) then
            Derma_Query(message, "Prefab editor recovery", "Resume", function() send("resume") end,
                "Cancel", function() end)
        elseif action == "begin" and string.find(message, "previous prefab editor session", 1, true) then
            Derma_Query(message .. "\nClear the old session marker?", "Prefab editor",
                "Clear marker", function() send("recover") end, "Cancel", function() end)
        elseif action == "status" then
            if MapTransfer:Exists() then
                Derma_Query(message, "Prefab editor recovery", "Retry", function() send("status") end,
                    "Return to previous map", function() send("switch_return") end)
            else
                Derma_Query(message, "Prefab editor", "Retry", function() send("status") end,
                    "Return to launcher", function() send("end") end)
            end
        else
            local failureData = encoded ~= "" and util.JSONToTable(encoded) or nil
            failRequest(message, failureData)
        end
        return
    end
    local data = encoded ~= "" and util.JSONToTable(encoded) or nil
    if encoded ~= "" and type(data) ~= "table" then failRequest("Invalid editor response.") return end
    if action == "status" then
        Editor:Open(data)
    elseif action == "maps" or action == "cells" then
        Editor:OnMapList(data, request)
    elseif action == "cell_tile" then
        local ok, problem = Editor:ApplyCellTile(data, request)
        if not ok then failRequest(problem) end
    elseif action == "switch_check" then
        if not data or data.safeToResume ~= true then
            Editor:Message("The editor session is still changing; the saved draft remains available.", true)
            return
        end
        local removed, problem = MapTransfer:Remove(request.encoded)
        Editor.MapSwitchToken = nil
        Editor:UnlockMapSwitch()
        if not removed then Editor:Message(problem, true) end
    elseif action == "switch_complete" then
        local removed, problem = MapTransfer:Remove(request.encoded)
        Editor.MapSwitchToken = nil
        Editor:UnlockMapSwitch()
        if not removed then Editor:Message(problem, true) else Editor:Message("Prefab tabs restored.") end
    elseif action == "list" then
        Editor:SetDocuments(data)
    elseif action == "load" then
        if not data or data.id ~= request.id then failRequest("The loaded prefab ID does not match the request.") return end
        local tab = Editor:FindTab(data.id)
        local activate = Editor.ActiveTab == request.origin and Editor.SwitchSerial == request.serial
        if not tab and activate and request.origin and not request.origin.Dirty and not request.origin.Saving
            and not request.origin.OpenedId and request.origin.Document.id == "" and request.origin.Document.name == ""
            and #request.origin.Document.props == 0 and #request.origin.Document.lights == 0
            and #request.origin.Document.particles == 0 and #request.origin.Document.guards == 0 then
            tab = request.origin
            tab.Document, tab.OpenedId, tab.Dirty, tab.Revision, tab.Selected = data, data.id, false, 0, nil
            Editor:SetDocument(data, data.id)
            Editor.Dirty, Editor.Revision, Editor.Saving = false, 0, false
            Editor:RefreshDocument()
        elseif not tab then
            tab = Editor:CreateTab(data, data.id, false)
        end
        Editor:RefreshTabTitles()
        if activate and Editor.ActiveTab ~= tab then Editor:ActivateTab(tab) end
    elseif action == "model" then
        if not data or not Contract.IsValidId(data.propId) or not Contract.IsValidModelPath(data.model) then
            failRequest("The server returned an invalid prop.") return
        end
        local prop = { model = data.model, position = { x = 0, y = 0, z = 0 },
            angles = { p = 0, y = 0, r = 0 }, skin = 0, scale = 1, movable = false,
            propId = data.propId, lootMode = "off" }
        local tab = request.tab
        tab.Document.props[#tab.Document.props + 1] = prop
        tab.Selected = #tab.Document.props
        if Editor.ActiveTab == tab then
            Editor:StopRotation()
            Editor:Select(tab.Selected)
            Editor:MakeModel(tab.Selected)
            Editor:MarkChanged()
            Editor:RefreshInspector()
        else
            tab.Revision, tab.Dirty = tab.Revision + 1, true
            Editor:RefreshTabTitles()
        end
    elseif action == "references" then
        Editor:SetReferenceChoices(data)
    elseif action == "particles" then
        Editor:SetParticleChoices(data)
    elseif action == "guard_weapons" then
        Editor:SetGuardWeapons(data)
    elseif action == "reference" then
        if not data or data.model ~= request.path then failRequest("The reference response does not match the request.") return end
        local tab = request.tab
        if tab.ReferenceRequest == requestId then
            tab.ReferenceRequest = nil
            tab.View.reference = data.model
            if Editor.ActiveTab == tab then
                Editor.ReferenceWanted = data.model
                if not Editor:SetReference(data.model) then
                    Editor.ReferenceWanted, tab.View.reference = nil, nil
                    Editor.ReferenceChoice:SetValue("No reference")
                end
            end
        end
    elseif action == "save" then
        local tab = request.tab
        tab.Saving, tab.OpenedId = false, request.id
        tab.Dirty = tab.Revision ~= request.revision
        if Editor.ActiveTab == tab then
            Editor.Saving, Editor.OpenedId, Editor.Dirty = false, tab.OpenedId, tab.Dirty
            Editor:RefreshDocument()
        end
        Editor:RefreshTabTitles()
        Editor:Message(message)
        send("list")
        if request.afterSave then request.afterSave(true)
        elseif request.exitAfter and not tab.Dirty then Editor:Exit() end
    elseif action == "delete" then
        request.tab.OpenedId = nil
        if Editor.ActiveTab == request.tab then Editor.OpenedId = nil end
        Editor:RemoveTab(request.tab)
        Editor:Message(message)
        send("list")
    elseif action == "recover" then
        Editor:Message(message)
    end
end)

hook.Add("Think", "ZM.PrefabEditor.WaitForSession", function()
    local ply = LocalPlayer()
    if game.GetMap() == "zn_dev_prefab_anchor" or not IsValid(ply)
        or not ply:GetNWBool("ZM.PrefabEditorActive", false) then return end
    if Editor.RequestedStatus then return end
    Editor.RequestedStatus = true
    send("status")
end)

hook.Add("OnScreenSizeChanged", "ZM.PrefabEditor.Resize", function()
    if not Editor:IsActive() then return end
    if Editor.Drag and Editor.Drag.panel then Editor.Drag.panel:MouseCapture(false) end
    Editor.Drag = nil
    Editor.Frame:SetSize(ScrW(), ScrH())
    Editor.Frame:SetPos(0, 0)
    Editor:UpdateAreaLayout()
end)

hook.Add("HUDShouldDraw", "ZM.PrefabEditor.HideHud", function()
    if Editor:IsSession() then return false end
end)

hook.Add("PostDrawTranslucentRenderables", "ZM.PrefabEditor.Render", function(depth, skybox)
    if depth or skybox or not Editor:IsActive() then return end
    if IsValid(Editor.ReferenceModel) then Editor.ReferenceModel:DrawModel() end
    if Editor.ShowGrid then
        for _, line in ipairs(Editor.GridLines) do render.DrawLine(line[1], line[2], gridColor, true) end
    end
    if Editor.ShowCompass then
        cam.Start3D2D(Editor:GetGridOrigin() + Vector(0, 0, 1), compassAngle, 1)
        for _, direction in ipairs(compassLabels) do
            draw.SimpleText(direction.text, "ZM_PrefabCompass", direction.x, direction.y,
                gridColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        cam.End3D2D()
    end
    for _, model in ipairs(Editor.Models) do if IsValid(model) then model:DrawModel() end end
    for _, instance in pairs(Editor.GuardModels) do
        local ok, problem = ZM_PrefabGuardPreview:Draw(instance)
        if not ok and not instance.drawError then
            instance.drawError = problem
            timer.Simple(0, function()
                if Editor:IsActive() then Editor:Message(problem, true) end
            end)
        end
    end
    for _, light in ipairs(Editor.Document.lights) do
        local position = Editor:GetPreviewOrigin() + Vector(light.position.x, light.position.y, light.position.z)
        local angle = Angle(light.angles.p, light.angles.y, light.angles.r)
        render.DrawWireframeBox(position, angle, lightHandleMin, lightHandleMax, selectionColor, true)
        render.DrawLine(position, position + angle:Forward() * 32, selectionColor, true)
    end
    for _, particle in ipairs(Editor.Document.particles) do
        local position = Editor:GetPreviewOrigin() + Vector(particle.position.x, particle.position.y, particle.position.z)
        local angle = Angle(particle.angles.p, particle.angles.y, particle.angles.r)
        render.DrawWireframeBox(position, angle, lightHandleMin, lightHandleMax, particleColor, true)
        render.DrawLine(position, position + angle:Forward() * 32, particleColor, true)
    end
    Editor.GizmoPoints = {}
    local start = Editor:GetSelectionPosition()
    if not start then return end
    if Editor:SelectionKind() == "prop" then
        local selected = Editor.Models[Editor.Selected]
        local minimum, maximum = Editor:GetPropBounds(Editor.Selected)
        render.DrawWireframeBox(selected:GetPos(), selected:GetAngles(), minimum, maximum, selectionColor, true)
    elseif Editor:SelectionKind() == "guard" then
        local guard = Editor:GetSelectedObject()
        local instance = guard and Editor.GuardModels[guard.guardId]
        if instance and IsValid(instance.model) then
            local model = instance.model
            render.DrawWireframeBox(model:GetPos(), model:GetAngles(), model:OBBMins(), model:OBBMaxs(), selectionColor, true)
        end
    end
    if Editor.Mode == "rotate" then
        local prop = Editor:GetSelectedObject()
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
