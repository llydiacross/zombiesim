// Preview-only outfit inspection. Selections belong to this window, never the survivor or inventory.
ZM_Wardrobe = ZM_Wardrobe or {}
local Wardrobe = ZM_Wardrobe
local models = { male = "models/player/group01/male_03.mdl", female = "models/player/group01/female_01.mdl" }
local rearLabels = { pants_back_left = "left rear thigh", pants_back_right = "right rear thigh",
    arm_back_left = "left rear arm", arm_back_right = "right rear arm",
    sleeve_cuff = "left sleeve hem", sleeve_cuff_right = "right sleeve hem", sleeve_cuff_both = "both sleeve hems" }

function Wardrobe:IsAvailable()
    return IsValid(LocalPlayer()) and LocalPlayer():IsAdmin() and ZM_World and ZM_World.ActiveProfile == "preview"
end

function Wardrobe:GetEntries()
    local result = {}
    local registry = ZM_StaticData:GetRegistry()
    for id, item in pairs(registry and registry.items or {}) do
        if item.clothing and ZM_Clothing.Finishes[item.clothing.finish] then
            result[#result + 1] = { id = id, name = item.name, garment = item.clothing.garment, finish = item.clothing.finish }
        end
    end
    table.sort(result, function(a, b)
        if a.garment ~= b.garment then return a.garment < b.garment end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return result
end

local function iconData(entry, sex)
    return ZM_ItemIcons:GetClothingIcon(entry.finish, entry.garment, sex, entry.id)
end

function Wardrobe:Select(entry)
    if not self:IsAvailable() or not IsValid(self.Frame) then return false end
    self.Selection[entry.garment] = entry.finish
    self.SelectedItems[entry.garment] = entry.id
    self.Dirty = true
    self.NextApply = 0
    return true
end

function Wardrobe:SetModel(sex)
    if not self:IsAvailable() or not IsValid(self.ModelPanel) or not models[sex] then return false end
    self.Sex = sex
    self.CitizenModel = nil
    if IsValid(self.ModelPanel.Entity) then ZM_Clothing:Apply(self.ModelPanel.Entity, "", "") end
    self.ModelPanel:SetModel(models[sex])
    if IsValid(self.CitizenSelector) then self.CitizenSelector:SetValue(sex == "male" and "male_03" or "female_01") end
    self.Dirty, self.NextApply = true, 0
    self:RefreshGrid()
    return true
end

function Wardrobe:SetCitizenModel(name)
    local path = "models/player/group01/" .. name .. ".mdl"
    local layout = ZM_Clothing:GetPreviewCitizenLayout(path)
    if not layout or not self:SetModel(layout.sex) then return false end
    self.ModelPanel:SetModel(path)
    self.CitizenModel = path
    if IsValid(self.CitizenSelector) then self.CitizenSelector:SetValue(name) end
    self.Dirty, self.NextApply = true, 0
    return true
end

function Wardrobe:Open(parent)
    if not self:IsAvailable() then
        ErrorNoHalt("[ZombieSim] Wardrobe requires a preview admin.\n")
        return
    end
    if IsValid(self.Frame) then self.Frame:MakePopup() return end
    local frame = vgui.Create("DFrame")
    self.Frame = frame
    self.Selection, self.SelectedItems = {}, {}
    self.Applied, self.Bloody = false, false
    self.Sex = ZM_Clothing.Models[string.lower(LocalPlayer():GetModel() or "")] or "male"
    self.CitizenModel = nil
    self.Dirty, self.NextApply, self.IconErrors = true, 0, {}
    self.Yaw, self.Filter, self.Search = 0, "all", ""
    frame:SetSkin("ZombieSim")
    frame:SetTitle("WARDROBE / PREVIEW ONLY")
    frame:SetSize(math.min(1120, ScrW() - 32), math.min(760, ScrH() - 32))
    frame:Center()
    frame:SetDeleteOnClose(true)
    frame:MakePopup()
    frame.OnRemove = function()
        if IsValid(self.ModelPanel) and IsValid(self.ModelPanel.Entity) then ZM_Clothing:Apply(self.ModelPanel.Entity, "", "") end
        self.Frame, self.ModelPanel, self.CitizenSelector = nil, nil, nil
        self.Selection, self.SelectedItems = {}, {}
        self.Applied = false
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    frame.Think = function()
        if not self:IsAvailable() or (parent ~= nil and not IsValid(parent)) then frame:Close() end
    end
    frame.OnClose = function() if IsValid(parent) then parent:MakePopup() end end
    frame.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE then frame:Close() end end
    if ZM_UI then
        if IsValid(parent) then ZM_UI:RegisterTransient(frame) else ZM_UI:OpenExclusive(frame) end
    end

    local palette = ZM_DermaSkin.Palette
    local function background(_, width, height)
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, width, height)
    end
    local footer = vgui.Create("DLabel", frame)
    footer:Dock(BOTTOM)
    footer:SetTall(32)
    footer:SetText("Window model only. No items granted, no saved appearance changed. Swatches show the actual garment print/fabric.")
    footer:SetWrap(true)
    footer:SetTextColor(palette.muted)
    local right = vgui.Create("DPanel", frame)
    right:Dock(RIGHT)
    right:SetWide(math.floor(frame:GetWide() * 0.38))
    right:DockMargin(12, 4, 4, 4)
    right.Paint = background
    right:DockPadding(8, 8, 8, 8)
    local previewHeading = vgui.Create("DLabel", right)
    previewHeading:Dock(TOP)
    previewHeading:SetTall(24)
    previewHeading:SetText("OUTFIT PREVIEW")
    previewHeading:SetFont("DermaDefaultBold")
    previewHeading:SetTextColor(palette.text)
    local controls = vgui.Create("DPanel", right)
    controls:Dock(TOP)
    controls:SetTall(32)
    controls.Paint = function() end
    local function button(parent, text, callback)
        local control = vgui.Create("DButton", parent)
        control:SetText(text)
        control.DoClick = callback
        return control
    end
    for _, sex in ipairs({ "male", "female" }) do
        local control = button(controls, string.upper(sex), function() self:SetModel(sex) end)
        control:Dock(LEFT)
        control:SetWide(90)
    end
    local reset = button(controls, "NATIVE", function()
        self.Selection, self.SelectedItems = {}, {}
        self.Dirty, self.NextApply = true, 0
    end)
    reset:Dock(FILL)
    if ZM_Clothing.CitizenLayouts then
        local selector = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", right))
        self.CitizenSelector = selector
        selector:Dock(TOP)
        selector:SetTall(28)
        selector:SetValue(self.Sex == "male" and "male_03" or "female_01")
        for _, sex in ipairs({ "male", "female" }) do
            for number = 1, sex == "male" and 9 or 6 do
                local name = string.format("%s_%02d", sex, number)
                selector:AddChoice(name, name)
            end
        end
        selector.OnSelect = function(_, _, _, name)
            if not self:SetCitizenModel(name) then
                ErrorNoHalt("[ZombieSim] Selected citizen calibration is unavailable.\n")
            end
        end
    end
    local blood = button(right, "BLOOD PREVIEW: OFF", function(control)
        self.Bloody = not self.Bloody
        control:SetText(self.Bloody and "BLOOD PREVIEW: ON" or "BLOOD PREVIEW: OFF")
        self.Dirty, self.NextApply = true, 0
    end)
    blood:Dock(TOP)
    blood:SetTall(28)
    self.Status = vgui.Create("DLabel", right)
    self.Status:Dock(BOTTOM)
    self.Status:SetTall(76)
    self.Status:SetWrap(true)
    self.Status:SetTextColor(palette.muted)
    self.Status:SetText("WINDOW OUTFIT\nShirt: native\nPants: native")
    local removeRow = vgui.Create("DPanel", right)
    removeRow:Dock(BOTTOM)
    removeRow:SetTall(30)
    removeRow.Paint = function() end
    for _, garment in ipairs({ "shirt", "pants" }) do
        local control = button(removeRow, "NATIVE " .. string.upper(garment), function()
            self.Selection[garment], self.SelectedItems[garment] = nil, nil
            self.Dirty, self.NextApply = true, 0
        end)
        control:Dock(LEFT)
        control:SetWide(math.floor((right:GetWide() - 16) / 2))
    end
    local rotate = vgui.Create("DNumSlider", right)
    rotate:Dock(BOTTOM)
    rotate:SetTall(36)
    rotate:SetText("Rotate")
    rotate:SetMin(0)
    rotate:SetMax(360)
    rotate:SetDecimals(0)
    rotate:SetValue(0)
    rotate.Label:SetTextColor(palette.text)
    rotate.Scratch.Paint = function() end
    rotate.TextArea:SetTextColor(palette.text)
    rotate:DockMargin(0, 8, 0, 8)
    rotate.OnValueChanged = function(_, value) self.Yaw = value end
    local model = vgui.Create("DModelPanel", right)
    self.ModelPanel = model
    model:Dock(FILL)
    model:SetModel(models[self.Sex])
    model:SetFOV(32)
    model:SetCamPos(Vector(125, 0, 40))
    model:SetLookAt(Vector(0, 0, 36))
    model.LayoutEntity = function(_, entity) entity:SetAngles(Angle(0, self.Yaw, 0)) end

    local left = vgui.Create("DPanel", frame)
    left:Dock(FILL)
    left:DockMargin(4, 4, 0, 4)
    left.Paint = background
    left:DockPadding(8, 8, 8, 8)
    local heading = vgui.Create("DLabel", left)
    heading:Dock(TOP)
    heading:SetTall(24)
    heading:SetText("CLOTHING CATALOGUE")
    heading:SetFont("DermaDefaultBold")
    heading:SetTextColor(palette.text)
    local search = vgui.Create("DTextEntry", left)
    search:Dock(TOP)
    search:SetTall(28)
    search:SetPlaceholderText("Search artwork, colour or placement...")
    search:DockMargin(0, 0, 0, 6)
    search.Paint = function(control, width, height)
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(control:HasFocus() and palette.redBright or palette.border)
        surface.DrawOutlinedRect(0, 0, width, height)
        control:DrawTextEntryText(palette.text, palette.redBright, palette.text)
        if control:GetValue() == "" and not control:HasFocus() then
            draw.SimpleText("Search artwork, colour or placement...", "DermaDefault", 8, height / 2,
                palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    search.OnChange = function(control)
        self.Search = string.lower(control:GetValue())
        self:RefreshGrid()
    end
    local filters = vgui.Create("DPanel", left)
    filters:Dock(TOP)
    filters:SetTall(30)
    filters.Paint = function() end
    filters:DockMargin(0, 0, 0, 8)
    for _, filter in ipairs({ "all", "shirt", "pants" }) do
        local control = button(filters, string.upper(filter), function()
            self.Filter = filter
            self:RefreshGrid()
        end)
        control:Dock(LEFT)
        control:SetWide(100)
    end
    local scroll = vgui.Create("DScrollPanel", left)
    scroll:Dock(FILL)
    self.Grid = vgui.Create("DIconLayout", scroll)
    self.Grid:Dock(TOP)
    self.Grid:SetSpaceX(6)
    self.Grid:SetSpaceY(6)
    self.Grid.Paint = function() end
    self.Grid.OnSizeChanged = function(_, width)
        if self.GridWidth ~= width then
            self.GridWidth = width
            self:SizeTiles()
        end
    end
    self:RefreshGrid()
end

function Wardrobe:SizeTiles()
    if not IsValid(self.Grid) or self.Grid:GetWide() < 1 then return end
    local columns = math.max(1, math.floor(self.Grid:GetWide() / 138))
    local width = math.floor((self.Grid:GetWide() - (columns - 1) * 6) / columns)
    for _, tile in ipairs(self.Grid:GetChildren()) do tile:SetWide(width) end
end

function Wardrobe:RefreshGrid()
    if not IsValid(self.Grid) then return end
    self.Grid:Clear()
    self.EntryCount, self.VisibleCount = 0, 0
    for _, entry in ipairs(self:GetEntries()) do
        self.EntryCount = self.EntryCount + 1
        if (self.Filter == "all" or self.Filter == entry.garment) and
            string.find(string.lower(entry.name .. " " .. entry.id), self.Search, 1, true) then
            self.VisibleCount = self.VisibleCount + 1
            local icon, iconResolved
            local tile = self.Grid:Add("DButton")
            tile:SetSize(132, 176)
            tile:SetText("")
            tile:SetTooltip(entry.name .. "\n" .. entry.id .. "\nClick to dress the window model.")
            tile.DoClick = function() self:Select(entry) end
            tile.Paint = function(control, width, height)
                if not iconResolved then
                    local failure
                    icon, failure = iconData(entry, self.Sex)
                    iconResolved = true
                    if failure and not self.IconErrors[entry.id] then
                        self.IconErrors[entry.id] = failure
                        ErrorNoHalt("[ZombieSim] " .. failure .. "\n")
                    end
                end
                local palette = ZM_DermaSkin.Palette
                local selected = self.SelectedItems[entry.garment] == entry.id
                surface.SetDrawColor(palette.black)
                surface.DrawRect(0, 0, width, height)
                if icon then
                    local canvas = icon.icon.size
                    local scale = math.min((width - 16) / canvas[1], (height - 64) / canvas[2])
                    local x, y = (width - canvas[1] * scale) / 2, 6
                    surface.SetMaterial(icon.material)
                    surface.SetDrawColor(255, 255, 255, 255)
                    for _, piece in ipairs(icon.icon[self.Sex]) do
                        local uv, source = piece.uv, piece.source
                        surface.DrawTexturedRectUV(x + source[1] * scale, y + source[2] * scale,
                            source[3] * scale, source[4] * scale,
                            uv[1] / 1024, uv[2] / 1024, (uv[1] + uv[3]) / 1024, (uv[2] + uv[4]) / 1024)
                    end
                else
                    draw.SimpleText("MISSING TEXTURE", "DermaDefault", 8, 48, palette.red)
                end
                local finish = ZM_Clothing.Finishes[entry.finish]
                local family = string.match(entry.name, "^(.-) " .. entry.garment .. " /") or "Prototype"
                draw.SimpleText(string.sub(family, 1, 22),
                    "DermaDefault", 6, height - 52, palette.text)
                draw.SimpleText(string.upper(entry.garment) .. " / " .. (finish.colour or "prototype"),
                    "DermaDefaultBold", 6, height - 34, palette.text)
                local styleLabel = rearLabels[finish.style] or (finish.style == "pants_leg" and "left thigh" or
                    (finish.style == "pants_leg_right" and "right thigh" or
                    (finish.style == "pants_cuff" and "left cuff-up" or
                    (finish.style == "pants_cuff_right" and "right cuff-up" or (finish.style == "pants_cuff_both" and "both cuff-up" or string.Replace(finish.treatment or finish.style or "base", "_", " "))))))
                draw.SimpleText(styleLabel, "DermaDefault", 6, height - 18, palette.muted)
                surface.SetDrawColor(selected and palette.redBright or (control.Hovered and palette.text or palette.muted))
                surface.DrawOutlinedRect(0, 0, width, height, selected and 2 or 1)
            end
            self:SizeTiles()
        end
    end
end

function Wardrobe:GetDiagnosticSnapshot()
    return { open = IsValid(self.Frame), model = self.CitizenModel or models[self.Sex or "male"], selection = self.Selection,
        selectedItems = self.SelectedItems, entries = self.EntryCount, visible = self.VisibleCount,
        iconErrors = self.IconErrors, applied = self.Applied, bloody = self.Bloody == true,
        windowOnly = true, cursorVisible = vgui.CursorVisible(),
        liveShirt = IsValid(LocalPlayer()) and LocalPlayer():GetNWString("ZM_Clothing_shirt", ""),
        livePants = IsValid(LocalPlayer()) and LocalPlayer():GetNWString("ZM_Clothing_pants", "") }
end

hook.Add("PreRender", "ZM.Wardrobe.Outfit", function()
    if not IsValid(Wardrobe.Frame) or not Wardrobe:IsAvailable() or not Wardrobe.Dirty or RealTime() < Wardrobe.NextApply then return end
    local entity = IsValid(Wardrobe.ModelPanel) and Wardrobe.ModelPanel.Entity
    if not IsValid(entity) then return end
    Wardrobe.NextApply = RealTime() + 0.5
    Wardrobe.Applied = ZM_Clothing:Apply(entity, Wardrobe.Selection.shirt, Wardrobe.Selection.pants, Wardrobe.Bloody)
    Wardrobe.Dirty = not Wardrobe.Applied
    Wardrobe.Status:SetText((Wardrobe.Applied and (Wardrobe.Bloody and "WINDOW OUTFIT / BLOODY" or "WINDOW OUTFIT") or
        "Texture unavailable or pool pinned; retrying...") ..
        "\nShirt: " .. (Wardrobe.SelectedItems.shirt and ZM_Items:GetDefinition(Wardrobe.SelectedItems.shirt).name or "native") ..
        "\nPants: " .. (Wardrobe.SelectedItems.pants and ZM_Items:GetDefinition(Wardrobe.SelectedItems.pants).name or "native"))
end)

concommand.Add("zombiesim_dev_wardrobe", function(_, _, arguments)
    if #arguments == 0 then Wardrobe:Open()
    elseif #arguments == 1 and arguments[1] == "close" then
        if IsValid(Wardrobe.Frame) then Wardrobe.Frame:Close() end
    elseif #arguments == 2 and arguments[1] == "model" and models[arguments[2]] then
        Wardrobe:Open()
        Wardrobe:SetModel(arguments[2])
    elseif #arguments == 2 and arguments[1] == "model" and
        ZM_Clothing:GetPreviewCitizenLayout("models/player/group01/" .. arguments[2] .. ".mdl") then
        Wardrobe:Open()
        Wardrobe:SetCitizenModel(arguments[2])
    elseif #arguments == 2 and arguments[1] == "select" then
        Wardrobe:Open()
        for _, entry in ipairs(Wardrobe:GetEntries()) do
            if entry.id == arguments[2] and Wardrobe:Select(entry) then return end
        end
        ErrorNoHalt("[ZombieSim] Wardrobe selection requires an available clothing item.\n")
    else ErrorNoHalt("[ZombieSim] Usage: zombiesim_dev_wardrobe [close|model male|female|male_01..09|female_01..06|select itemId]\n") end
end)
