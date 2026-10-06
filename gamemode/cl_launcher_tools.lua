// Read-only asset inspection; no gameplay requests or survivor mutations.
ZM_LauncherTools = ZM_LauncherTools or {}
local Tools = ZM_LauncherTools
local colours = ZM_DermaSkin.Palette

function Tools:IsAvailable()
    return ZM_World and ZM_World.ActiveProfile == "preview" and game.GetMap() == "zn_preview_start"
end

function Tools:GetItems()
    local result = {}
    local registry = ZM_StaticData:GetRegistry()
    for id, definition in pairs(registry and registry.items or {}) do
        result[#result + 1] = { id = id, label = definition.name, category = definition.entityClass, definition = definition }
    end
    table.sort(result, function(a, b) return a.label == b.label and a.id < b.id or a.label < b.label end)
    return result
end

function Tools:GetMaps()
    local entries = {}
    local data = ZM_World:GetData()
    local function add(cell, category)
        local id = cell.map
        if not isstring(id) or id == "" then return end
        local row = entries[id]
        if not row then
            row = { id = id, label = id, category = category, cell = cell, uses = {} }
            entries[id] = row
        end
        if category == "City recipe" then
            local x, y = ZM_World:GetWorldCoordinates(cell)
            row.uses[#row.uses + 1] = "Cell " .. tostring(x) .. ", " .. tostring(y)
        else
            row.uses[#row.uses + 1] = cell.name or cell.id or id
        end
    end
    for _, cell in ipairs(data and data.cells or {}) do add(cell, "City recipe") end
    for _, den in ipairs(data and data.safeZones or {}) do add(den, "Den") end
    local result = {}
    for _, row in pairs(entries) do result[#result + 1] = row end
    table.sort(result, function(a, b) return a.category == b.category and a.id < b.id or a.category < b.category end)
    return result
end

function Tools:GetItemUsage(id)
    local paths, visited = {}, {}
    local function visit(value, path)
        if not istable(value) or visited[value] then return end
        visited[value] = true
        for key, child in pairs(value) do
            local nextPath = path .. "." .. tostring(key)
            if key == id or child == id then paths[#paths + 1] = nextPath end
            if istable(child) then visit(child, nextPath) end
        end
    end
    local registry = ZM_StaticData:GetRegistry()
    for key, value in pairs(registry or {}) do
        if key ~= "items" then visit(value, tostring(key)) end
    end
    table.sort(paths)
    return paths
end

local function label(parent, text, height)
    local panel = vgui.Create("DLabel", parent)
    panel:Dock(TOP)
    panel:DockMargin(8, 6, 8, 6)
    panel:SetTall(height or 40)
    panel:SetTextColor(colours.text)
    panel:SetWrap(true)
    panel:SetText(text)
    return panel
end

local function button(parent, text, action)
    local panel = vgui.Create("DButton", parent)
    panel:Dock(TOP)
    panel:DockMargin(8, 4, 8, 4)
    panel:SetTall(36)
    panel:SetText(text)
    panel.DoClick = action
    return panel
end

local function drawImage(material, x, y, width, height)
    local texture = material and not material:IsError() and material:GetTexture("$basetexture")
    if not texture or texture:Width() <= 0 or texture:Height() <= 0 then return false end
    local scale = math.min(width / texture:Width(), height / texture:Height())
    local w, h = texture:Width() * scale, texture:Height() * scale
    surface.SetMaterial(material)
    surface.SetDrawColor(255, 255, 255)
    surface.DrawTexturedRect(x + (width - w) / 2, y + (height - h) / 2, w, h)
    return true
end

function Tools:Inspect(row, maps)
    self.Selected = row.id
    self.Inspector:Clear()
    label(self.Inspector, row.label .. "\n" .. row.id, 48)
    if maps then
        local preview = vgui.Create("DPanel", self.Inspector)
        preview:Dock(TOP)
        preview:SetTall(330)
        local zoom = 1
        preview:SetMouseInputEnabled(true)
        preview.OnMouseWheeled = function(_, delta) zoom = math.Clamp(zoom + delta * 0.25, 1, 4) return true end
        preview.Paint = function(_, width, height)
            surface.SetDrawColor(colours.black)
            surface.DrawRect(0, 0, width, height)
            local material = ZM_WorldMap:GetCellAtlasMaterial(row.cell, self.Wireframe)
            if not drawImage(material, -(zoom - 1) * width / 2, -(zoom - 1) * height / 2, width * zoom, height * zoom) then
                draw.SimpleText("Staged map image unavailable", "DermaDefaultBold", 8, 16, colours.redBright)
            end
        end
        local path = "worlds/preview/" .. (self.Wireframe and "cells_wireframe/" or "cells/") .. row.id .. ".png"
        label(self.Inspector, "Image: materials/" .. path .. "\nBSP: maps/" .. row.id .. ".bsp\n" ..
            (file.Exists("maps/" .. row.id .. ".bsp", "GAME") and "BSP mounted" or "BSP MISSING") ..
            "\nScroll over the image to zoom. Images are staged artwork, not a live 3D render.", 100)
        label(self.Inspector, "USED BY " .. #row.uses .. " LOCATION(S)\n" .. table.concat(row.uses, "\n"), math.max(48, #row.uses * 16 + 24))
        return
    end
    local definition = row.definition
    local material = ZM_ItemIcons:GetOverride(definition)
    local model = ZM_ItemIcons:GetModel(definition)
    if material and not material:IsError() then
        local image = vgui.Create("DPanel", self.Inspector)
        image:Dock(TOP)
        image:SetTall(260)
        image.Paint = function(_, width, height) drawImage(material, 0, 0, width, height) end
    end
    if definition.clothing then
        local swatch = vgui.Create("DPanel", self.Inspector)
        swatch:Dock(TOP)
        swatch:SetTall(260)
        swatch.Paint = function(_, width, height)
            local size = math.min(width, height)
            ZM_ItemIcons:DrawClothing(definition, math.floor((width - size) / 2), 0, size)
        end
    end
    if not definition.clothing and util.IsValidModel(model) then
        local preview = vgui.Create("DModelPanel", self.Inspector)
        preview:Dock(TOP)
        preview:SetTall(260)
        preview:SetModel(model)
        preview:SetFOV(35)
        local entity = preview:GetEntity()
        if IsValid(entity) then
            local mins, maxs = entity:GetRenderBounds()
            local center = (mins + maxs) / 2
            local distance = math.max(16, (maxs - mins):Length() * 1.3)
            preview:SetLookAt(center)
            preview:SetCamPos(center + Vector(distance, distance, distance * 0.5))
            preview.LayoutEntity = function(_, object) object:SetAngles(Angle(0, RealTime() * 15, 0)) end
        end
    end
    local lines = { "Category: " .. tostring(row.category),
        "Thumbnail: " .. tostring(definition.thumbnail or "(model icon)") ..
            (definition.clothing and " / fabric swatch from garment layer" or
            (definition.thumbnail and not material and " / MISSING" or "")),
        "Icon model: " .. tostring(model) .. (util.IsValidModel(model) and " / mounted" or " / MISSING") }
    if definition.clothing then
        local finish = ZM_Clothing.Finishes[definition.clothing.finish]
        lines[#lines + 1] = "Clothing finish: " .. definition.clothing.finish .. (finish and " / loaded" or " / MISSING")
        lines[#lines + 1] = "Use Wardrobe for the actual UV-projected garment, fabric and bloody variants."
        if finish then
            lines[#lines + 1] = "Finish metadata:\n" .. util.TableToJSON(finish, true)
        end
        local open = button(self.Inspector, "Inspect garment in Wardrobe", function()
            ZM_Wardrobe:Open(self.Host)
            for _, entry in ipairs(ZM_Wardrobe:GetEntries()) do
                if entry.id == row.id then ZM_Wardrobe:Select(entry) break end
            end
        end)
        open:SetEnabled(ZM_Wardrobe:IsAvailable())
    end
    local usage = self:GetItemUsage(row.id)
    lines[#lines + 1] = "Registry references (" .. #usage .. "):\n" ..
        (#usage > 0 and table.concat(usage, "\n") or "No direct registry references. This does not imply the item is unused by gameplay code.")
    lines[#lines + 1] = "Loaded definition:\n" .. util.TableToJSON(definition, true)
    local text = vgui.Create("DTextEntry", self.Inspector)
    text:Dock(TOP)
    text:DockMargin(8, 8, 8, 8)
    text:SetTall(420)
    text:SetMultiline(true)
    text:SetEditable(false)
    text:SetText(table.concat(lines, "\n\n"))
end

function Tools:Atlas(maps)
    if not self:EnsureWorkspace() then return end
    self.Body:Clear()
    self.Page = maps and "maps" or "items"
    local top = vgui.Create("DPanel", self.Body)
    top:Dock(TOP)
    top:SetTall(36)
    top.Paint = function() end
    local search = vgui.Create("DTextEntry", top)
    search:Dock(FILL)
    search:SetPlaceholderText(maps and "Search recipe, den or logical cell..." or "Search item name, ID or category...")
    local filter = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", top))
    filter:Dock(RIGHT)
    filter:SetWide(170)
    filter:SetValue("All categories")
    filter:AddChoice("All categories", "")
    local inspector = vgui.Create("DScrollPanel", self.Body)
    self.Inspector = inspector
    inspector:Dock(RIGHT)
    inspector:SetWide(math.floor(self.Body:GetWide() * 0.42))
    label(inspector, "Select a card for full-size artwork, paths and usage.", 48)
    local scroll = vgui.Create("DScrollPanel", self.Body)
    scroll:Dock(FILL)
    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(TOP)
    grid:SetSpaceX(8)
    grid:SetSpaceY(8)
    // Stretch cards so each row fills the grid instead of leaving fixed-width right padding.
    local function fitCards(width)
        width = width or grid:GetWide()
        if width <= 0 then return end
        local columns = math.max(1, math.floor((width + 8) / 158))
        local cardWidth = math.floor((width - (columns - 1) * 8) / columns)
        for _, card in ipairs(self.Cards or {}) do
            if IsValid(card) then card:SetSize(cardWidth, cardWidth + 26) end
        end
    end
    grid.OnSizeChanged = function(_, width)
        fitCards(width)
        grid:InvalidateLayout()
    end
    local rows = maps and self:GetMaps() or self:GetItems()
    local categories, category = {}, ""
    for _, row in ipairs(rows) do categories[row.category] = true end
    local categoryNames = table.GetKeys(categories)
    table.sort(categoryNames)
    for _, name in ipairs(categoryNames) do filter:AddChoice(name, name) end
    local function refresh()
        grid:Clear()
        self.Cards = {}
        local query = string.lower(search:GetValue())
        for _, row in ipairs(rows) do
            local haystack = string.lower(row.label .. " " .. row.id .. " " .. row.category ..
                (maps and " " .. table.concat(row.uses, " ") or ""))
            if (category ~= "" and row.category ~= category) or not haystack:find(query, 1, true) then continue end
            local card = grid:Add("DButton")
            card:SetSize(170, 196)
            card:SetText("")
            card:SetTooltip(row.label .. "\n" .. row.id .. "\n" .. row.category)
            card.AtlasId = row.id
            local material, attempted = nil, false
            card.Paint = function(_, width, height)
                surface.SetDrawColor(colours.black)
                surface.DrawRect(0, 0, width, height)
                if not attempted then
                    attempted = true
                    material = maps and ZM_WorldMap:GetCellAtlasMaterial(row.cell, self.Wireframe) or
                        ZM_ItemIcons:GetOverride(row.definition)
                    if not maps and not material then
                        local image = ZM_ItemIcons:Attach(card, row.definition, 12)
                        if image then
                            image:SetSize(width - 24, height - 56)
                            image:SetPos(12, 6)
                            card.PerformLayout = function(_, w, h) image:SetSize(w - 24, h - 56) image:SetPos(12, 6) end
                        end
                    end
                end
                if material then drawImage(material, 6, 6, width - 12, height - 56) end
                if not maps and row.definition.clothing then
                    local size = math.min(width - 12, height - 56)
                    ZM_ItemIcons:DrawClothing(row.definition, math.floor((width - size) / 2), 6, size)
                end
                if maps and (not material or material:IsError()) then
                    draw.SimpleText("Image missing", "DermaDefaultBold", 8, 50, colours.redBright)
                end
                surface.SetDrawColor(self.Selected == row.id and colours.redBright or colours.border)
                surface.DrawOutlinedRect(0, 0, width, height, 1)
            end
            card.PaintOver = function(_, _, height)
                draw.SimpleText(row.label, "DermaDefaultBold", 6, height - 40, colours.text)
                draw.SimpleText(row.category, "DermaDefault", 6, height - 20, colours.muted)
            end
            card.DoClick = function() self:Inspect(row, maps) end
            self.Cards[#self.Cards + 1] = card
        end
        fitCards()
        grid:InvalidateLayout(true)
    end
    search.OnChange = refresh
    filter.OnSelect = function(_, _, _, id) category = id refresh() end
    if maps then
        local mode = vgui.Create("DButton", top)
        mode:Dock(RIGHT)
        mode:SetWide(120)
        mode:SetText(self.Wireframe and "Wireframe" or "Satellite")
        mode.DoClick = function() self.Wireframe = not self.Wireframe self:Atlas(true) end
    end
    refresh()
end

// Tools is a launcher tab: buttons live in the left menu and read-only views use the right side of the same frame.
function Tools:Attach(host, menuWidth)
    if self.Host ~= host then self:CloseWorkspace() end
    self.Host = host
    self.MenuWidth = menuWidth or (IsValid(host) and host:GetWide()) or self.MenuWidth
end

function Tools:EnsureWorkspace()
    local host = self.Host
    if not self:IsAvailable() or not IsValid(host) then return false end
    if IsValid(self.Body) then return true end
    host:SetWide(ScrW())
    local body = vgui.Create("DPanel", host)
    self.Body = body
    body:Dock(RIGHT)
    body:DockMargin(0, 48, 24, 20)
    body:SetWide(math.max(320, ScrW() - self.MenuWidth - 24))
    body.Paint = function(_, width, height)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(colours.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end
    body.OnRemove = function()
        if self.Body ~= body then return end
        self.Body, self.Inspector, self.Cards, self.Page = nil, nil, {}, "home"
    end
    return true
end

function Tools:CloseWorkspace()
    if IsValid(self.Body) then self.Body:Remove() end
    self.Body, self.Inspector, self.Cards, self.Page = nil, nil, {}, "home"
    if IsValid(self.Host) and self.MenuWidth then self.Host:SetWide(self.MenuWidth) end
end

function Tools:IsOpen()
    return IsValid(self.Body)
end

function Tools:Home()
    self:CloseWorkspace()
end

// One structured snapshot of the running build; Content Status renders it and the tests assert on it.
function Tools:GetBuildReport()
    local report = { problems = {}, registries = {}, packs = {} }
    local function problem(text) report.problems[#report.problems + 1] = text end
    local Version = ZM_Version
    report.version = Version and Version.Info
    report.label = Version and Version:GetLabel() or "Unknown version"
    report.commit = Version and Version:GetSourceCommit()
    report.changelog = Version and Version.Entries or {}
    if not Version or Version.Error then problem("Version: " .. tostring(Version and Version.Error or "version loader missing")) end
    if Version and Version.ChangelogError then problem("Changelog: " .. Version.ChangelogError) end

    local distribution = ZM_Distribution
    local manifest = distribution.Manifest
    report.mode = manifest and (manifest.development and "Packaged development build" or "Packaged release build")
        or "Loose development install"
    report.releaseId = manifest and manifest.releaseId
    report.contentReady = distribution.Ready
    if not distribution.Ready then problem("Content packages: " .. tostring(distribution.Error)) end
    for _, row in ipairs(distribution.WorkshopRows or {}) do report.packs[#report.packs + 1] = row end

    local data = ZM_World:GetData()
    local maps = self:GetMaps()
    local profile = tostring(ZM_World.ActiveProfile)
    local mounted, imaged, cityRecipes = 0, 0, 0
    for _, row in ipairs(maps) do
        if file.Exists("maps/" .. row.id .. ".bsp", "GAME") then mounted = mounted + 1 end
        if row.category == "City recipe" then
            cityRecipes = cityRecipes + 1
            if file.Exists("materials/worlds/" .. profile .. "/cells/" .. row.id .. ".png", "GAME") then imaged = imaged + 1 end
        end
    end
    report.world = { profile = profile, map = game.GetMap(), cells = #(data and data.cells or {}),
        dens = #(data and data.safeZones or {}), recipes = #maps, mounted = mounted, imaged = imaged, cityRecipes = cityRecipes }
    if ZM_World:GetLoadError() then problem("World: " .. tostring(ZM_World:GetLoadError())) end
    if mounted < #maps then problem((#maps - mounted) .. " of " .. #maps .. " map BSPs are not mounted") end

    local registry = ZM_StaticData:GetRegistry() or {}
    for _, id in ipairs(table.GetKeys(registry)) do
        if istable(registry[id]) then report.registries[#report.registries + 1] = { id = id, count = table.Count(registry[id]) } end
    end
    table.SortByMember(report.registries, "id", true)
    report.registries[#report.registries + 1] = { id = "clothing finishes", count = table.Count(ZM_Clothing.Finishes) }
    report.registries[#report.registries + 1] = { id = "sky entries", count = table.Count(ZM_SkyPalettes.Entries) }
    if ZM_SkyPalettes.CatalogueFailure then problem("Sky catalogue: " .. tostring(ZM_SkyPalettes.CatalogueFailure)) end
    if ZM_SkyPalettes.CustomFailure then problem("Custom sky store: " .. tostring(ZM_SkyPalettes.CustomFailure)) end
    return report
end

function Tools:Status()
    if not self:EnsureWorkspace() then return end
    self.Body:Clear()
    self.Page, self.Cards = "status", {}
    local report = self:GetBuildReport()
    self.LastReport = report
    local scroll = vgui.Create("DScrollPanel", self.Body)
    scroll:Dock(FILL)
    scroll:DockMargin(4, 4, 4, 4)

    local function heading(text)
        local panel = scroll:Add("DPanel")
        panel:Dock(TOP)
        panel:DockMargin(12, 18, 12, 6)
        panel:SetTall(28)
        panel.Paint = function(_, width, height)
            surface.SetDrawColor(colours.redBright)
            surface.DrawRect(0, 4, 4, height - 8)
            draw.SimpleText(text, "ZM_ToolsHeading", 12, height / 2, colours.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(colours.border)
            surface.DrawRect(0, height - 1, width, 1)
        end
    end
    local function row(key, value, colour)
        local panel = scroll:Add("DPanel")
        panel:Dock(TOP)
        panel:DockMargin(24, 1, 12, 1)
        panel:SetTall(22)
        panel.Paint = function(_, width, height)
            draw.SimpleText(key, "ZM_ToolsBody", 0, height / 2, colours.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(value), "ZM_ToolsBody", math.max(180, width * 0.34), height / 2,
                colour or colours.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local function paragraph(text, colour, indent) ZM_Changelog:Paragraph(scroll, text, colour, indent) end
    local good, warn = Color(110, 200, 120), Color(230, 180, 70)

    local info = report.version or {}
    ZM_Changelog:AddBanner(scroll, info)

    heading("BUILD HEALTH")
    if #report.problems == 0 then
        paragraph("No load problems detected.", good)
    else
        for _, text in ipairs(report.problems) do paragraph("! " .. text, colours.redBright) end
    end

    heading("VERSION & SOURCE")
    row("Version", report.label)
    row("Started", info.started or "-")
    row("Released", info.released or "not yet released", info.released and good or warn)
    row("Previous release", info.previousRelease or "-")
    if report.commit then
        row("Source commit", report.commit.hash .. "  (" .. report.commit.branch .. ")")
        paragraph("Commit read from the local Git checkout; uncommitted changes are not reflected.", colours.muted)
    else
        row("Source commit", "unavailable (no local Git checkout)", colours.muted)
    end

    heading("DISTRIBUTION")
    row("Build type", report.mode)
    row("Content check", report.contentReady and "verified" or "FAILED", report.contentReady and good or colours.redBright)
    row("Release ID", report.releaseId and string.sub(report.releaseId, 1, 16) .. "..." or "none (loose files)")
    for _, pack in ipairs(report.packs) do row("Package " .. pack.id, pack.message) end

    local world = report.world
    heading("WORLD")
    row("Active profile", world.profile)
    row("Current map", world.map)
    row("Logical cells", world.cells)
    row("Dens", world.dens)
    row("Unique map recipes", world.recipes)
    row("Mounted BSPs", world.mounted .. " / " .. world.recipes, world.mounted == world.recipes and good or colours.redBright)
    row("City map images", world.imaged .. " / " .. world.cityRecipes, world.imaged == world.cityRecipes and good or warn)

    heading("LOADED CONTENT")
    for _, entry in ipairs(report.registries) do row(entry.id, entry.count) end
    paragraph("Counts describe loaded registries, not source-folder inventory or rights clearance.", colours.muted)

    heading("CHANGELOG")
    ZM_Changelog:Populate(scroll, info, report.changelog)
end

// Called by the launcher while rendering its "tools" page.
function Tools:BuildMenu(content, addButton, addLabelLine, refresh)
    addLabelLine(content, "TOOLS", 36)
    addLabelLine(content, "Preview launcher only. Browsing never grants items, changes equipment or teleports the survivor.", 54)
    local function entry(text, page, action)
        local item = addButton((self.Page == page and IsValid(self.Body) and "? " or "") .. text, function()
            action()
            refresh()
        end)
        return item
    end
    entry("ITEM ATLAS", "items", function() self:Atlas(false) end):SetTooltip("Item artwork, definitions and registry usage.")
    entry("MAP ATLAS", "maps", function() self:Atlas(true) end):SetTooltip("Staged satellite and wireframe cell artwork.")
    entry("CONTENT STATUS", "status", function() self:Status() end):SetTooltip("Loaded registries and content failures.")
    // Tools below the rule open their own windows instead of the right-hand view.
    local rule = vgui.Create("DPanel", content)
    rule:Dock(TOP)
    rule:DockMargin(0, 10, 0, 10)
    rule:SetTall(1)
    rule.Paint = function(_, width, height)
        surface.SetDrawColor(colours.border)
        surface.DrawRect(0, 0, width, height)
    end
    self.Rule = rule
    local wardrobe = entry("WARDROBE", nil, function() ZM_Wardrobe:Open(self.Host) end)
    wardrobe:SetEnabled(ZM_Wardrobe:IsAvailable())
    wardrobe:SetTooltip("Opens a window: full citizen outfit, fabric and blood preview. Requires a preview admin.")
    entry("SKY BROWSER", nil, function() ZM_SkyBrowser:Open(self.Host) end):SetTooltip("Opens a window: skies and automatic palette artwork.")
end

// Switches the launcher to the Tools tab (kept for the development UI bridge).
function Tools:Open()
    if not self:IsAvailable() then ErrorNoHalt("[ZombieSim] Tools are available only in the preview launcher.\n") return end
    local menu = ZM_LauncherMenu
    if not menu or not IsValid(menu.Frame) then return end
    menu.Page = "tools"
    menu:Render()
end

function Tools:GetDiagnosticSnapshot()
    local menu = ZM_LauncherMenu
    return { available = self:IsAvailable(), open = menu ~= nil and IsValid(menu.Frame) and menu.Page == "tools",
        workspace = IsValid(self.Body), page = self.Page, selected = self.Selected, cards = #(self.Cards or {}),
        items = #self:GetItems(), maps = #self:GetMaps(), readOnly = true }
end

concommand.Add("zombiesim_dev_test_launcher_tools", function()
    if not Tools:IsAvailable() or not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then
        ErrorNoHalt("[ZombieSim] Tools tests require a preview launcher admin.\n")
        return
    end
    if IsValid(Tools.Body) or IsValid(ZM_Wardrobe.Frame) or IsValid(ZM_SkyBrowser.Frame) then
        ErrorNoHalt("[ZombieSim] Close Tools views, Wardrobe and the sky browser before testing.\n")
        return
    end
    local previousHost, previousWidth = Tools.Host, Tools.MenuWidth
    local root = vgui.Create("DPanel")
    root:SetSize(640, 720)
    root:SetVisible(false)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("atlas_entries_cover_loaded_items_and_unique_maps", function(check)
        check(#Tools:GetItems() == table.Count(ZM_StaticData:GetRegistry().items), "every loaded item is represented")
        local ids = {}
        for _, row in ipairs(Tools:GetMaps()) do
            check(not ids[row.id], "map recipe is not duplicated: " .. row.id)
            check(#row.uses > 0, "map has logical-cell or den provenance: " .. row.id)
            ids[row.id] = true
        end
        for _, cell in ipairs(ZM_World:GetData().cells) do check(ids[cell.map], "every cell map is included") end
    end)
    suite:Add("clothing_items_draw_fabric_swatches_not_box_models", function(check)
        local sampled, styles = 0, {}
        for _, row in ipairs(Tools:GetItems()) do
            local clothing = row.definition.clothing
            local finish = clothing and ZM_Clothing.Finishes[clothing.finish]
            local style = finish and (clothing.garment .. ":" .. tostring(finish.style))
            if style and not styles[style] then
                styles[style] = true
                sampled = sampled + 1
                for _, sex in ipairs({ "male", "female" }) do
                    local data, failure = ZM_ItemIcons:GetClothingIcon(clothing.finish, clothing.garment, sex, row.id)
                    check(data ~= nil, "swatch resolves for " .. style .. " " .. sex .. (failure and ": " .. failure or ""))
                end
                check(ZM_ItemIcons:Attach(root, row.definition) == nil, "clothing never attaches a box model: " .. row.id)
            end
        end
        check(sampled >= 10, "sampled every loaded garment style (" .. sampled .. ")")
    end)
    suite:Add("tools_views_render_inside_host_without_changing_saved_sky", function(check)
        local sky = GetConVar("zombiesim_sky_palette"):GetString()
        Tools:Attach(root, 640)
        Tools:Atlas(false)
        check(IsValid(Tools.Body) and Tools.Body:GetParent() == root, "atlas renders inside the launcher host, not a new window")
        check(root:GetWide() == ScrW(), "host widens to show the tool view")
        check(#Tools.Cards == #Tools:GetItems(), "item cards match loaded catalogue")
        for _, row in ipairs(Tools:GetItems()) do
            if row.id == "itemBandage" then Tools:Inspect(row, false) break end
        end
        check(Tools.Selected == "itemBandage", "item inspector selects a loaded definition")
        Tools:Atlas(true)
        check(#Tools.Cards == #Tools:GetMaps(), "map atlas deduplicates recipes")
        local maps = Tools:GetMaps()
        if maps[1] then Tools:Inspect(maps[1], true) end
        Tools:Status()
        check(Tools.Page == "status" and IsValid(Tools.Body), "content status reuses the same view")
        local report = Tools.LastReport
        check(report and report.version and report.version.version == ZM_Version.Info.version, "status shows the version.json version")
        check(report and #report.changelog > 0 and report.changelog[1].version == ZM_Version.Info.version, "changelog leads with the current version")
        local marked = true
        for _, entry in ipairs(report and report.changelog or {}) do
            for _, line in ipairs(entry.highlights or {}) do
                if not string.match(tostring(line), "^[%+%-%?] ") then marked = false end
            end
            local last = 0
            for _, line in ipairs(entry.highlights or {}) do
                local rank = ({ ["+"] = 1, ["?"] = 2, ["-"] = 3 })[string.sub(tostring(line), 1, 1)] or 0
                if rank < last then marked = false end
                last = rank
            end
        end
        check(marked and report.changelog[#report.changelog].version == "1.0", "highlights are marked, ordered + ? - and history reaches 1.0")
        check(report and report.world.recipes == #Tools:GetMaps() and istable(report.problems), "status reports world and problem summary")
        Tools:CloseWorkspace()
        check(not IsValid(Tools.Body) and root:GetWide() == 640, "closing the view returns host to menu width")
        check(GetConVar("zombiesim_sky_palette"):GetString() == sky, "read-only atlases preserve saved sky")
    end)
    suite:Add("wardrobe_and_parent_lifecycle_preserve_launcher", function(check)
        Tools:Atlas(false)
        ZM_Wardrobe:Open(root)
        check(IsValid(Tools.Body) and IsValid(ZM_Wardrobe.Frame) and IsValid(root), "Wardrobe does not close the tool view or launcher")
        if IsValid(ZM_Wardrobe.Frame) then
            ZM_Wardrobe.Frame:OnKeyCodePressed(KEY_ESCAPE)
            check(not IsValid(ZM_Wardrobe.Frame) and IsValid(Tools.Body), "Wardrobe Escape returns to Tools")
        end
        local body = Tools.Body
        check(IsValid(body) and body:GetParent() == root, "tool view is owned by the launcher host")
        root:Remove()
        check(root:IsMarkedForDeletion(), "host removal also removes its owned tool view")
    end)
    suite:Add("launcher_back_always_returns_to_main_menu", function(check)
        local menu = ZM_LauncherMenu
        if not IsValid(menu.Frame) then check(false, "launcher frame is open") return end
        local page = menu.Page
        menu.Page = "tools"
        menu:Render()
        check(IsValid(Tools.Rule), "window-opening tools are separated by a rule")
        Tools:Atlas(true)
        check(IsValid(Tools.Body) and Tools.Body:GetParent() == menu.Frame, "map atlas opens beside the launcher menu")
        menu:Back()
        check(menu.Page == "menu" and not IsValid(Tools.Body), "Back with an open view returns to the main menu")
        check(menu.Frame:GetWide() == menu.FrameWidth, "launcher returns to its menu width")
        menu.Page = page
        menu:Render()
    end)
    suite:Add("options_changelog_button_opens_window_in_game_and_side_panel_in_launcher", function(check)
        local options = vgui.Create("DPanel")
        options:SetVisible(false)
        ZM_Options:BuildPanel(options)
        local button = options.ZM_ChangelogButton
        check(IsValid(button) and button:GetParent() == options, "Options has a changelog button")
        local below = true
        for _, group in ipairs(options.ZM_OptionSections or {}) do
            below = below and group.category:GetZPos() <= button:GetZPos() and
                table.KeyFromValue(options:GetChildren(), group.category) < table.KeyFromValue(options:GetChildren(), button)
        end
        check(below, "changelog button docks below every Options section")
        if IsValid(button) then button:DoClick() end
        local window = ZM_Changelog.Frame
        check(IsValid(window) and window:GetTitle() == "CHANGELOG", "in-game button opens the Changelog window")
        check(IsValid(window) and IsValid(options), "Changelog window leaves Options open")
        if IsValid(window) then
            window:OnKeyCodePressed(KEY_ESCAPE)
            check(not IsValid(ZM_Changelog.Frame) and IsValid(options), "Escape closes only the Changelog window")
        end
        options:Remove()

        local menu = ZM_LauncherMenu
        if not IsValid(menu.Frame) then check(false, "launcher frame is open") return end
        local page = menu.Page
        menu.Page = "options"
        menu:Render()
        local launcherButton
        local function find(panel)
            if launcherButton or not IsValid(panel) then return end
            if IsValid(panel.ZM_ChangelogButton) then launcherButton = panel.ZM_ChangelogButton return end
            for _, child in ipairs(panel:GetChildren()) do find(child) end
        end
        find(menu.Content)
        check(IsValid(launcherButton), "launcher Options has the changelog button")
        if IsValid(launcherButton) then launcherButton:DoClick() end
        check(ZM_Changelog:IsPanelOpen() and ZM_Changelog.Panel:GetParent() == menu.Frame and not IsValid(ZM_Changelog.Frame),
            "launcher shows the changelog beside the menu, not in a window")
        menu:Back()
        check(menu.Page == "menu" and not ZM_Changelog:IsPanelOpen(), "Back returns to the main menu and closes the changelog")
        check(menu.Frame:GetWide() == menu.FrameWidth, "launcher returns to its menu width after the changelog")
        menu.Page = page
        menu:Render()
    end)
    local summary = suite:Run()
    if IsValid(ZM_Changelog.Frame) then ZM_Changelog.Frame:Remove() end
    ZM_Changelog:ClosePanel()
    if IsValid(ZM_Wardrobe.Frame) then ZM_Wardrobe.Frame:Close() end
    if IsValid(root) then root:Remove() end
    Tools.Body, Tools.Inspector, Tools.Cards, Tools.Page = nil, nil, {}, "home"
    Tools.Host, Tools.MenuWidth = previousHost, previousWidth
    if IsValid(ZM_LauncherMenu.Frame) then ZM_LauncherMenu.Frame:MakePopup() end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/launcher_tools_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Launcher tools " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
    end
end)
