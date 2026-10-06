ZM_SkyBrowser = ZM_SkyBrowser or {}
local Browser = ZM_SkyBrowser
local Palettes = ZM_SkyPalettes
local colours = ZM_DermaSkin.Palette
local selectedConVar = GetConVar("zombiesim_sky_palette")

local function gradient(id, x, y, width, height, horizon)
    for row = 0, 47 do
        local r, g, b = Palettes:GradientColor(id, (1 - row / 47) * math.pi / 2, horizon)
        surface.SetDrawColor(r, g, b, 255)
        surface.DrawRect(x, y + row * height / 48, width, math.ceil(height / 48))
    end
end

function Browser:ResolveThumbnail(entry)
    if entry.automatic and entry.id ~= "default" then
        local parts = {}
        for _, context in ipairs(Palettes.ContextOrder) do
            local id = entry.contexts[context]
            parts[#parts + 1] = { context = context,
                entry = { id = id }, thumbnail = self:ResolveThumbnail({ id = id }) }
        end
        return { parts = parts }
    end
    local definition = Palettes.Entries[entry.id]
    local path = definition and definition.mounted
    if entry.id == "default" then
        local sky = GetConVar("sv_skyname")
        local name = sky and sky:GetString()
        if name and name:match("^[%w_%-]+$") then path = "skybox/" .. name end
        if not path or not file.Exists("materials/" .. path .. "ft.vmt", "GAME") then
            return { mapManaged = true }
        end
    end
    if not path then return {} end
    local material = Material(path .. "ft")
    local texture = not material:IsError() and material:GetTexture("$basetexture")
    if not texture or texture:Width() <= 0 or texture:Height() <= 0 then
        local failure = "Sky thumbnail unavailable: " .. path .. "ft"
        self.ThumbnailErrors[entry.id] = failure
        ErrorNoHalt("[ZombieSim] " .. failure .. "\n")
        return { failure = failure }
    end
    local info = definition and definition.faces and definition.faces.ft
    local scaleY = info and info.scaleY or 1
    return { material = material, insetU = 0.5 / texture:Width(), insetV = 0.5 / (texture:Height() * scaleY),
        scaleY = scaleY }
end

function Browser:DrawThumbnail(entry, thumbnail, x, y, width, height)
    if thumbnail.parts then
        for index, part in ipairs(thumbnail.parts) do
            local strip = width / #thumbnail.parts
            self:DrawThumbnail(part.entry, part.thumbnail, x + (index - 1) * strip, y, strip, height)
            draw.SimpleText(string.upper(part.context), "DermaDefault", x + (index - 0.5) * strip,
                y + height - 12, colours.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    elseif thumbnail.material then
        surface.SetMaterial(thumbnail.material)
        surface.SetDrawColor(255, 255, 255, 255)
        local scaleY = thumbnail.scaleY or 1
        local maximumV = 1 / scaleY - thumbnail.insetV
        surface.DrawTexturedRectUV(x, y, width, height / scaleY, thumbnail.insetU, thumbnail.insetV,
            1 - thumbnail.insetU, maximumV)
        if scaleY > 1 then
            surface.DrawTexturedRectUV(x, y + height / scaleY, width, height - height / scaleY,
                thumbnail.insetU, maximumV, 1 - thumbnail.insetU, maximumV)
        end
    elseif thumbnail.mapManaged or thumbnail.failure then
        surface.SetDrawColor(colours.raised)
        surface.DrawRect(x, y, width, height)
        draw.SimpleText(thumbnail.failure and "Preview unavailable" or "Your map's own sky",
            "DermaDefaultBold", x + width / 2, y + height / 2, colours.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        local _, horizon = Palettes:GetContext()
        if Palettes.Entries[entry.id] and Palettes.Entries[entry.id].top then
            gradient(entry.id, x, y, width, height, horizon)
        else
            surface.SetDrawColor(colours.raised)
            surface.DrawRect(x, y, width, height)
        end
    end
end

function Browser:Close()
    if IsValid(self.Frame) then self.Frame:Close() end
end

function Browser:Select(entry)
    local state = self.EditorState
    if entry.unavailable then
        if state then state.failure = entry.unavailable else self.Error = entry.unavailable end
        return false
    end
    if state then
        if entry.automatic and entry.id ~= "default" then
            state.failure = "Choose an individual sky for this slot, not an automatic palette."
            return false
        end
        state.contexts[state.activeContext] = entry.id
        state.failure, self.Error = nil, nil
        state.thumbnails[state.activeContext] = self:ResolveThumbnail({ id = entry.id })
        return true
    end
    local ok, failure = Palettes:Select(entry.id)
    self.Error = failure
    if ok then self.Selected = entry.id end
    return ok
end

function Browser:RefreshCards()
    if not IsValid(self.Grid) then return end
    self.Grid:Clear()
    self.Cards, self.PendingThumbnails = {}, {}
    local query = string.lower(self.Search and self.Search:GetValue() or "")
    for _, entry in ipairs(Palettes:GetChoices()) do
        if (self.EditorState and entry.automatic and entry.id ~= "default") or
            (self.Filter == "automatic" and not entry.automatic) or
            (self.Filter == "individual" and entry.automatic) or
            (query ~= "" and not string.lower(entry.label .. " " .. entry.id):find(query, 1, true)) then continue end
        local thumbnail, queued
        local card = self.Grid:Add("DButton")
        card:SetSize(220, 184)
        card:SetText("")
        card:SetTooltip(entry.label .. (entry.unavailable and "\nUnavailable: " .. entry.unavailable or
            self.EditorState and "\nClick to assign this sky to the selected slot on the left." or
            entry.automatic and "\nFollows the map atmosphere." or "\nFixed cosmetic sky. Baked lighting will not change.") ..
            (entry.credit and "\n" .. entry.credit or ""))
        card.DoClick = function() self:Select(entry) end
        card.Paint = function(control, width, height)
            surface.SetDrawColor(colours.black)
            surface.DrawRect(0, 0, width, height)
            if entry.unavailable then
                self:DrawThumbnail(entry, { failure = entry.unavailable }, 6, 6, width - 12, height - 60)
            elseif thumbnail then
                self:DrawThumbnail(entry, thumbnail, 6, 6, width - 12, height - 60)
            elseif not queued then
                queued = true
                self.PendingThumbnails[#self.PendingThumbnails + 1] = function()
                    thumbnail = self:ResolveThumbnail(entry)
                end
            end
            local state = self.EditorState
            local selected = state and state.contexts[state.activeContext] == entry.id or
                not state and selectedConVar:GetString() == entry.id
            draw.SimpleText(entry.label, "DermaDefaultBold", 8, height - 40, colours.text)
            draw.SimpleText((selected and (state and "ASSIGNED / " or "SELECTED / ") or "") .. (entry.unavailable and "Unavailable" or
                state and entry.id == "default" and "Native map sky" or
                entry.custom and "Custom automatic" or entry.automatic and "Automatic" or
                string.upper(entry.context) .. " / Fixed sky"), "DermaDefault", 8, height - 20, colours.muted)
            surface.SetDrawColor(selected and colours.redBright or (control.Hovered and colours.text or colours.border))
            surface.DrawOutlinedRect(0, 0, width, height, selected and 2 or 1)
        end
        card.SkyChoice = entry.id
        self.Cards[#self.Cards + 1] = card
    end
    self.Grid.OnSizeChanged(self.Grid, self.Grid:GetWide())
    self.Grid:InvalidateLayout(true)
end

function Browser:CloseEditor(refresh)
    if IsValid(self.Editor) then self.Editor:Remove() end
    local previous = self.EditorRestore
    self.Editor, self.EditorState = nil, nil
    self.EditorRestore = nil
    if previous then
        self.Filter = previous.filter
        if IsValid(self.FilterControl) then
            self.FilterControl:SetEnabled(true)
            self.FilterControl:SetValue(previous.filter == "automatic" and "Automatic" or
                previous.filter == "individual" and "Individual" or "All skies")
        end
        if IsValid(self.Search) then self.Search:SetText(previous.search) end
    end
    if IsValid(self.Frame) then
        self.Frame:InvalidateLayout(true)
        if refresh ~= false then self:RefreshCards() end
    end
end

function Browser:OpenEditor(id)
    self:CloseEditor(false)
    local profile = Palettes:GetProfile(id or selectedConVar:GetString())
    profile = profile or Palettes.Profiles.natural
    local customId = id and Palettes.CustomStore.profiles[id] and id or nil
    local state = { id = customId, contexts = table.Copy(profile.contexts), activeContext = "day", thumbnails = {}, slots = {} }
    self.EditorRestore = { filter = self.Filter, search = self.Search:GetValue() }
    self.EditorState = state
    self.Filter = "all"
    self.Search:SetText("")
    self.FilterControl:SetValue("Individual skies")
    self.FilterControl:SetEnabled(false)
    local panel = vgui.Create("DPanel", self.Frame)
    self.Editor = panel
    panel:Dock(LEFT)
    panel:SetZPos(10)
    panel:SetWide(math.min(290, self.Frame:GetWide() * 0.45))
    panel:DockMargin(8, 0, 4, 4)
    panel.Paint = function(_, width, height)
        surface.SetDrawColor(colours.panel)
        surface.DrawRect(0, 0, width, height)
    end
    local function label(text, height)
        local control = vgui.Create("DLabel", panel)
        control:Dock(TOP)
        control:DockMargin(8, 6, 8, 4)
        control:SetTall(height)
        control:SetWrap(true)
        control:SetTextColor(colours.text)
        control:SetText(text)
        return control
    end
    label(customId and "EDIT YOUR PALETTE" or id and "MAKE YOUR OWN COPY" or "NEW PALETTE", 22)
    label("1. Click a slot below.\n2. Choose a sky from the images on the right.", 38)
    local name = vgui.Create("DTextEntry", panel)
    name:Dock(TOP)
    name:DockMargin(8, 0, 8, 6)
    name:SetTall(28)
    name:SetPlaceholderText("Name your palette")
    name:SetValue(customId and profile.label or id and profile.label .. " - My palette" or "")
    state.nameControl = name
    local actions = vgui.Create("DPanel", panel)
    actions:Dock(BOTTOM)
    actions:SetTall(customId and 156 or 120)
    actions.Paint = function() end
    local result = vgui.Create("DLabel", actions)
    result:Dock(TOP)
    result:DockMargin(8, 0, 8, 4)
    result:SetTall(40)
    result:SetWrap(true)
    result:SetTextColor(colours.muted)
    result.Think = function(control)
        local sky = Palettes.Entries[state.contexts[state.activeContext]]
        control:SetText(state.failure or (sky and sky.context ~= state.activeContext and
            "Lighting warning: this sky was authored for " .. sky.context .. ", not " .. state.activeContext .. "." or
            "Choosing for " .. string.upper(state.activeContext) .. ". Changes apply only when you Save & use."))
    end
    local function button(text, action)
        local control = vgui.Create("DButton", actions)
        control:Dock(TOP)
        control:DockMargin(8, 4, 8, 4)
        control:SetTall(28)
        control:SetText(text)
        control.DoClick = action
        return control
    end
    state.saveButton = button("Save & use palette", function()
        local ok, saved = Palettes:SaveCustomProfile(state.id, { label = name:GetValue(), contexts = state.contexts })
        if not ok then state.failure = saved return end
        ok, state.failure = Palettes:Select(saved)
        if not ok then return end
        self.Error = nil
        self:CloseEditor()
    end)
    button("Cancel", function() self:CloseEditor() end)
    if customId then
        local confirm
        local remove
        remove = button("Delete palette", function()
            if not confirm then confirm = true remove:SetText("Confirm delete palette") return end
            local ok, failure = Palettes:DeleteCustomProfile(customId)
            if not ok then state.failure = failure return end
            self:CloseEditor()
        end)
    end
    local scroll = vgui.Create("DScrollPanel", panel)
    scroll:Dock(FILL)
    state.slotScroll = scroll
    scroll.OnSizeChanged = function(_, _, height)
        local slotHeight = math.Clamp(math.floor(height / #Palettes.ContextOrder) - 6, 64, 84)
        for _, slot in pairs(state.slots) do slot:SetTall(slotHeight) end
    end
    for _, context in ipairs(Palettes.ContextOrder) do
        local slot = vgui.Create("DButton", scroll)
        state.slots[context] = slot
        slot:Dock(TOP)
        slot:DockMargin(8, 2, 8, 4)
        slot:SetTall(84)
        slot:SetText("")
        slot:SetTooltip("Click to choose the " .. context .. " sky, then pick a thumbnail on the right.")
        slot.DoClick = function() state.activeContext = context state.failure = nil end
        local sky = state.contexts[context]
        local ok, failure = Palettes:GetAvailability(sky)
        state.thumbnails[context] = ok and self:ResolveThumbnail({ id = sky }) or { failure = failure }
        slot.Paint = function(_, width, height)
            local active = state.activeContext == context
            local selected = state.contexts[context]
            local definition = Palettes.Entries[selected]
            surface.SetDrawColor(colours.black)
            surface.DrawRect(0, 0, width, height)
            draw.SimpleText(string.upper(context) .. (active and " / CHOOSING" or ""), "DermaDefaultBold", 6, 4, colours.text)
            self:DrawThumbnail({ id = selected }, state.thumbnails[context], 6, 23, width - 12, height - 46)
            draw.SimpleText(definition and definition.label or "Default map sky", "DermaDefault", 6, height - 18, colours.muted)
            surface.SetDrawColor(active and colours.redBright or colours.border)
            surface.DrawOutlinedRect(0, 0, width, height, active and 2 or 1)
        end
    end
    self:RefreshCards()
    self.Frame:InvalidateLayout(true)
end

function Browser:Open(parent)
    if IsValid(self.Frame) then self.Frame:MakePopup() return end
    self.ParentPanel = parent
    self.ThumbnailErrors, self.Cards, self.PendingThumbnails, self.Error = {}, {}, {}, nil
    self.Filter = "all"
    self.Selected = selectedConVar:GetString()
    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSkin("ZombieSim")
    frame:SetTitle("SKY BROWSER")
    frame:SetSize(math.min(980, ScrW() - 32), math.min(720, ScrH() - 32))
    frame:Center()
    frame:SetDeleteOnClose(true)
    frame:MakePopup()
    if ZM_UI then ZM_UI:RegisterTransient(frame) end
    frame.OnRemove = function()
        if ZM_SkyInspection and ZM_SkyInspection.State and ZM_SkyInspection.State.browser == frame then
            ZM_SkyInspection:Finish("browser closed", false)
        end
        self:CloseEditor(false)
        if self.Frame == frame then self.Frame, self.Grid, self.Search, self.Cards = nil, nil, nil, {} end
        self.PendingThumbnails = {}
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
        self.ParentPanel = nil
    end
    frame.OnClose = function()
        if IsValid(parent) then
            local window = parent
            while IsValid(window:GetParent()) and window:GetParent() ~= vgui.GetWorldPanel() do
                window = window:GetParent()
            end
            window:MakePopup()
        end
    end
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then
            if IsValid(self.Editor) then self:CloseEditor() else frame:Close() end
        end
    end
    frame.Think = function()
        if (parent ~= nil and not IsValid(parent)) or not IsValid(LocalPlayer()) then
            if ZM_SkyInspection and ZM_SkyInspection.State and ZM_SkyInspection.State.browser == frame then
                ZM_SkyInspection:Finish("parent removed", false)
            end
            frame:Remove()
            return
        end
        if #self.PendingThumbnails > 0 then table.remove(self.PendingThumbnails, 1)() end
    end
    local hint = vgui.Create("DLabel", frame)
    hint:Dock(TOP)
    hint:DockMargin(8, 8, 8, 8)
    hint:SetTall(44)
    hint:SetWrap(true)
    hint:SetTextColor(colours.muted)
    hint:SetText("Click a card to apply and save your sky. Automatic palettes follow the current atmosphere. " ..
        "Individual skies stay fixed: cosmetic backdrop only, not a change to the map's lighting.")
    hint.Think = function(control)
        control:SetText(self.EditorState and
            "Build your palette: select Day, Overcast, Dusk or Night on the left, then click a sky image on the right. " ..
            "Save & use applies your palette; Cancel leaves your saved selection unchanged." or
            "Click a card to apply and save your sky. Automatic palettes follow the current atmosphere. " ..
            "Individual skies stay fixed: cosmetic backdrop only, not a change to the map's lighting.")
    end
    local tools = vgui.Create("DPanel", frame)
    tools:Dock(TOP)
    tools:DockMargin(8, 0, 8, 8)
    tools:SetTall(30)
    tools.Paint = function() end
    local create = vgui.Create("DButton", tools)
    create:Dock(RIGHT)
    create:SetWide(145)
    create:SetText("New custom palette")
    create.Think = function(control) control:SetEnabled(not self.EditorState) end
    create.DoClick = function() self:OpenEditor() end
    local edit = vgui.Create("DButton", tools)
    self.EditButton = edit
    edit:Dock(RIGHT)
    edit:DockMargin(6, 0, 6, 0)
    edit:SetWide(100)
    edit:SetText("Edit selected")
    edit.Think = function(control)
        control:SetEnabled(not self.EditorState and Palettes:GetProfile(selectedConVar:GetString()) ~= nil)
    end
    edit.DoClick = function() self:OpenEditor(selectedConVar:GetString()) end
    local filter = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", tools))
    self.FilterControl = filter
    filter:Dock(LEFT)
    filter:SetWide(120)
    filter:SetValue("All skies")
    filter:AddChoice("All skies", "all")
    filter:AddChoice("Automatic", "automatic")
    filter:AddChoice("Individual", "individual")
    filter.OnSelect = function(_, _, _, id) self.Filter = id self:RefreshCards() end
    local search = vgui.Create("DTextEntry", tools)
    self.Search = search
    search:Dock(FILL)
    search:DockMargin(8, 0, 8, 0)
    search:SetPlaceholderText("Search skies...")
    search.OnChange = function() self:RefreshCards() end
    local footer = vgui.Create("DPanel", frame)
    footer:Dock(BOTTOM)
    footer:SetTall(62)
    footer.Paint = function() end
    local back = vgui.Create("DButton", footer)
    back:Dock(RIGHT)
    back:DockMargin(8, 12, 8, 12)
    back:SetWide(130)
    back:SetText("Back to Options")
    back.DoClick = function() self:Close() end
    local inspect = vgui.Create("DButton", footer)
    inspect:Dock(RIGHT)
    inspect:DockMargin(4, 12, 4, 12)
    inspect:SetWide(160)
    inspect:SetText("Preview current skybox")
    inspect:SetTooltip("Ten-second camera-only aerial turn, then return here. Escape or Space returns early. The world keeps running.")
    inspect.DoClick = function()
        local ok, failure = ZM_SkyInspection:Start(frame)
        self.Error = not ok and failure or nil
    end
    local status = vgui.Create("DLabel", footer)
    status:Dock(FILL)
    status:DockMargin(8, 4, 4, 4)
    status:SetWrap(true)
    status:SetTextColor(colours.text)
    status.Think = function(control)
        local context = Palettes:GetContext()
        local definition = Palettes.Entries[selectedConVar:GetString()]
        control:SetText(self.Error or Palettes.CustomFailure or Palettes.CatalogueFailure or ("Selected: " .. Palettes:GetChoiceLabel() ..
            ((definition and definition.context ~= context) and
                "\nLighting warning: this sky differs from the current " .. context .. " atmosphere." or
                "\nYour selection is saved locally. Map lighting and weather remain unchanged.")))
    end
    local scroll = vgui.Create("DScrollPanel", frame)
    self.Scroll = scroll
    scroll:Dock(FILL)
    scroll:SetZPos(20)
    scroll:DockMargin(8, 0, 8, 0)
    local grid = vgui.Create("DIconLayout", scroll)
    self.Grid = grid
    grid:Dock(TOP)
    grid:SetSpaceX(10)
    grid:SetSpaceY(10)
    grid.OnSizeChanged = function(_, width)
        local columns = math.max(1, math.floor((width + 10) / 230))
        local tileWidth = math.max(1, math.floor((width - (columns - 1) * 10) / columns))
        for _, card in ipairs(self.Cards) do card:SetWide(tileWidth) end
    end
    self:RefreshCards()
end

function Browser:GetDiagnosticSnapshot()
    return { open = IsValid(self.Frame), cards = #(self.Cards or {}), choice = selectedConVar:GetString(),
        thumbnailErrors = self.ThumbnailErrors, error = self.Error, cursorVisible = vgui.CursorVisible(),
        parentAlive = IsValid(self.ParentPanel), previewTargets = 0, editorOpen = IsValid(self.Editor),
        editorSlot = self.EditorState and self.EditorState.activeContext,
        editorContexts = self.EditorState and table.Copy(self.EditorState.contexts),
        editorProfile = self.EditorState and self.EditorState.id,
        customProfiles = table.Count(Palettes.CustomStore.profiles), pendingThumbnails = #(self.PendingThumbnails or {}) }
end

concommand.Add("zombiesim_dev_test_sky_browser", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Sky browser tests require a preview admin.\n")
        return
    end
    if IsValid(Browser.Frame) or IsValid(ZM_Options.Frame) then
        ErrorNoHalt("[ZombieSim] Close Options and the sky browser before running their tests.\n")
        return
    end
    local savedChoice = selectedConVar:GetString()
    local savedPreview = Palettes.Preview
    local root = vgui.Create("DPanel")
    root:SetSize(640, 2400)
    root:SetVisible(false)
    ZM_Options:BuildPanel(root)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("options_sections_default_closed_and_remember_header_toggles", function(check)
        local getString, setCookie = cookie.GetString, cookie.Set
        local stored, panels = {}, {}
        cookie.GetString = function(key, default)
            if key:StartWith("zombiesim_options_section_") then return stored[key] or default end
            return getString(key, default)
        end
        cookie.Set = function(key, value)
            if key:StartWith("zombiesim_options_section_") then stored[key] = value else setCookie(key, value) end
        end
        local fixture = ZM_TestHarness.NewSuite()
        fixture:Add("isolated_section_cookies", function(assert)
            local function build()
                local panel = vgui.Create("DPanel")
                panels[#panels + 1] = panel
                panel:SetSize(640, 2400)
                panel:SetVisible(false)
                ZM_Options:BuildPanel(panel)
                return panel
            end
            local first = build()
            for _, group in ipairs(first.ZM_OptionSections) do
                assert(not group.category:GetExpanded(), group.id .. " defaults closed without a saved state")
            end
            for index, group in ipairs(first.ZM_OptionSections) do
                group.category.Header:DoClick()
                assert(stored["zombiesim_options_section_" .. group.id] == "1", group.id .. " opening writes its cookie")
                if index % 2 == 0 then group.category.Header:DoClick() end
            end
            first:Remove()
            local reopened = build()
            for index, group in ipairs(reopened.ZM_OptionSections) do
                assert(group.category:GetExpanded() == (index % 2 == 1), group.id .. " restores independently on another Options surface")
                group.category.Header:DoClick()
            end
            reopened:Remove()
            local rebuilt = build()
            for index, group in ipairs(rebuilt.ZM_OptionSections) do
                assert(group.category:GetExpanded() == (index % 2 == 0), group.id .. " remembers both opening and closing")
            end
        end)
        local result = fixture:Run()
        cookie.GetString, cookie.Set = getString, setCookie
        for _, panel in ipairs(panels) do if IsValid(panel) then panel:Remove() end end
        for _, test in ipairs(result.cases) do
            for _, failure in ipairs(test.failures) do check(false, failure) end
        end
    end)
    suite:Add("options_have_nine_resizing_sections", function(check)
        check(#root.ZM_OptionSections == 9, "all settings sections exist")
        for _, group in ipairs(root.ZM_OptionSections) do
            group.category:SetExpanded(false)
            group.category:InvalidateLayout(true)
            check(group.category:GetTall() == 30, group.title .. " collapses to header")
            group.category:SetExpanded(true)
            group.category:InvalidateLayout(true)
            check(group.category:GetTall() > 30, group.title .. " contains its controls")
        end
    end)
    suite:Add("options_retain_convars_and_audio_notice", function(check)
        local names, notice, developerCopy = {}, false, false
        local function visit(parent)
            for _, control in ipairs(parent:GetChildren()) do
                // Derma stores bindings on the slider's Scratch/TextArea and checkbox Button, not the parent.
                if control.m_strConVar then names[control.m_strConVar] = true end
                if control.GetText then
                    local text = control:GetText() or ""
                    if text:find("Sound levels follow Garry", 1, true) then notice = true end
                    if text:find("Copy skybox tuning", 1, true) then developerCopy = true end
                end
                visit(control)
            end
        end
        visit(root)
        for _, name in ipairs({
            "zombiesim_compass_height", "zombiesim_minimap_size", "zombiesim_atmosphere_rain_density",
            "zombiesim_atmosphere_puddle_opacity", "zombiesim_atmosphere_puddle_amount",
            "zombiesim_atmosphere_ripple_amount", "zombiesim_snow_detail", "zombiesim_snow_draw_distance",
            "zombiesim_ambient_debris_amount", "zombiesim_geiger_volume", "zombiesim_music_enabled",
            "zombiesim_geiger_visual", "zombiesim_radiation_corners", "zombiesim_radiation_symbol",
            "zombiesim_radiation_extreme_grayscale", "zombiesim_radiation_extreme_shake",
            "zombiesim_radiated_visuals", "zombiesim_gore_quality", "zombiesim_atmosphere_grain",
            "zombiesim_screen_effects", "zombiesim_sky_detail", "zombiesim_sky_props",
            "zombiesim_sky_clouds", "zombiesim_sky_fires", "zombiesim_sky_matched_lighting",
            "zombiesim_globe_quality"
        }) do check(names[name] == true, "retained " .. name) end
        for _, setting in ipairs(ZM_Skybox.TuningSettings) do check(names[setting.name], "retained " .. setting.name) end
        check(not names.volume and not names.volume_sfx and not names.snd_musicvolume, "engine audio remains engine-owned")
        check(notice and not developerCopy, "friendly audio notice replaces technical explanation")
    end)
    suite:Add("browser_cards_and_responsive_widths", function(check)
        Browser:Open(root)
        check(#Browser.Cards == #Palettes:GetChoices(), "every choice has a thumbnail card")
        check(table.Count(Browser.ThumbnailErrors) == 0, "all requested image materials resolve")
        for _, width in ipairs({ 210, 470, 940 }) do
            Browser.Grid.OnSizeChanged(Browser.Grid, width)
            for _, card in ipairs(Browser.Cards) do
                check(card:GetWide() > 0 and card:GetWide() <= width, "card fits viewport " .. width)
            end
        end
        check(IsValid(root), "opening the browser does not close Options")
    end)
    suite:Add("card_selection_saves_and_default_restores_native", function(check)
        for _, entry in ipairs(Palettes:GetChoices()) do
            // The exhaustive cube suite advances one set per frame; keep this synchronous UI case small.
            if entry.id ~= "default" and entry.id ~= "natural" and entry.id ~= "cinematic" and
                entry.id ~= "mounted_day" and entry.id ~= "imported_moonlit" then continue end
            Palettes.Preview = { id = "natural_day", expiresAt = RealTime() + 120 }
            check(Browser:Select(entry), entry.id .. " applies through card selection")
            check(selectedConVar:GetString() == entry.id, entry.id .. " writes the saved selection")
            check(Palettes.Preview == nil, entry.id .. " clears temporary preview")
            local expected = Palettes:Resolve(entry.id, Palettes:GetContext())
            check(Palettes.ActiveEntry == expected, entry.id .. " renders the resolved sky")
            if entry.id == "default" then check(#Palettes.Meshes == 0, "default releases replacement meshes") end
        end
        check(Palettes:Select(savedChoice), "original selection restored")
    end)
    suite:Add("browser_filters_and_editor_cancel_are_non_mutating", function(check)
        Browser.Filter = "automatic"
        Browser:RefreshCards()
        check(#Browser.Cards == 1 + #Palettes.ProfileOrder + table.Count(Palettes.CustomStore.profiles),
            "automatic filter contains only native/palettes")
        Browser.Filter = "individual"
        Browser:RefreshCards()
        check(#Browser.Cards == table.Count(Palettes.Entries), "individual filter contains every sky")
        Browser.Search:SetText("Moonlit clouds")
        Browser:RefreshCards()
        check(#Browser.Cards == 1, "search finds the licensed sky")
        Browser:OpenEditor()
        check(IsValid(Browser.Editor) and table.Count(Browser.EditorState.contexts) == 4, "editor has four states")
        Browser.Frame:OnKeyCodePressed(KEY_ESCAPE)
        check(not IsValid(Browser.Editor) and IsValid(Browser.Frame), "Escape cancels editor, not browser")
        check(selectedConVar:GetString() == savedChoice, "editor cancellation preserves selected sky")
        Browser.Search:SetText("")
        Browser.Filter = "all"
        Browser:RefreshCards()
    end)
    suite:Add("visual_editor_assigns_only_the_selected_slot", function(check)
        Browser.Filter = "automatic"
        Browser.Search:SetText("Natural")
        Browser:OpenEditor("natural")
        local state = Browser.EditorState
        check(state.id == nil and state.activeContext == "day", "built-in opens as a personal copy with Day active")
        check(table.Count(state.slots) == 4, "four clickable preview slots replace dropdowns")
        local viewport = state.slotScroll:GetTall()
        if viewport >= #Palettes.ContextOrder * 70 then
            local total = 0
            for _, slot in pairs(state.slots) do total = total + slot:GetTall() + 6 end
            check(total <= viewport, "all four slots fit without scrolling at the current window height")
        end
        check(#Browser.Cards == table.Count(Palettes.Entries) + 1, "right grid contains individual skies and native sky")
        check(not Browser.FilterControl:IsEnabled(), "automatic filter cannot hide sky choices during editing")
        for _, card in ipairs(Browser.Cards) do
            check(card.SkyChoice == "default" or Palettes.Entries[card.SkyChoice] ~= nil, "no automatic palette assignment cards")
        end
        local original = table.Copy(state.contexts)
        state.slots.night:DoClick()
        for _, card in ipairs(Browser.Cards) do
            if card.SkyChoice == "cinematic_night" then card:DoClick() end
        end
        check(state.activeContext == "night" and state.contexts.night == "cinematic_night", "thumbnail assigns the active Night slot")
        check(state.thumbnails.night ~= nil, "assigned slot has a preview")
        for _, context in ipairs({ "day", "overcast", "dusk" }) do
            check(state.contexts[context] == original[context], "assignment leaves " .. context .. " unchanged")
        end
        check(selectedConVar:GetString() == savedChoice, "draft assignment does not change the saved sky")
        check(Palettes.Profiles.natural.contexts.night == "natural_night", "editing does not mutate built-in definition")
        check(not Browser:Select({ id = "missing", unavailable = "Fixture unavailable" }) and
            state.failure == "Fixture unavailable" and state.contexts.night == "cinematic_night",
            "unavailable choice reports its failure without changing the slot")
        for _, card in ipairs(Browser.Cards) do
            if card.SkyChoice == "default" then card:DoClick() end
        end
        check(state.contexts.night == "default", "native sky can be assigned with a thumbnail")
        Browser.Frame:OnKeyCodePressed(KEY_ESCAPE)
        check(Browser.Filter == "automatic" and Browser.Search:GetValue() == "Natural" and
            Browser.FilterControl:IsEnabled(), "Cancel restores browsing filter and search")
        Browser.Filter = "all"
        Browser.Search:SetText("")
        Browser:RefreshCards()
    end)
    suite:Add("visual_editor_saves_copies_and_edits_custom_in_place", function(check)
        local savedPath, savedStore, savedFailure = Palettes.CustomPath, Palettes.CustomStore, Palettes.CustomFailure
        local path = "zombiesim/sky_browser_test_" .. util.CRC(tostring(SysTime())) .. ".json"
        check(not file.Exists(path, "DATA") and not file.Exists(path .. ".backup.json", "DATA"), "isolated fixture path is unused")
        if file.Exists(path, "DATA") or file.Exists(path .. ".backup.json", "DATA") then return end
        Palettes.CustomPath, Palettes.CustomFailure = path, nil
        Palettes.CustomStore = { schemaVersion = 1, nextId = 1, profiles = {} }
        local isolated = ZM_TestHarness.NewSuite()
        isolated:Add("editor_persistence", function(assert)
            assert(Palettes:Select("natural"), "built-in selected")
            Browser.EditButton:Think()
            assert(Browser.EditButton:IsEnabled(), "Edit selected is enabled for built-in palettes")
            Browser.EditButton:DoClick()
            local state = Browser.EditorState
            state.nameControl:SetText("Visual fixture")
            state.slots.dusk:DoClick()
            Browser:Select({ id = "cinematic_dusk" })
            state.saveButton:DoClick()
            local id = selectedConVar:GetString()
            assert(id == "custom_1" and not IsValid(Browser.Editor), "saving a built-in copy creates and selects a custom palette")
            assert(Palettes.Profiles.natural.contexts.dusk == "natural_dusk", "original built-in remains unchanged")
            assert(Palettes:LoadCustomProfiles() and Palettes.CustomStore.profiles[id].contexts.dusk == "cinematic_dusk",
                "saved slot assignment survives loading from disk")
            Browser.EditButton:Think()
            assert(Browser.EditButton:IsEnabled(), "Edit selected is enabled for custom palettes")
            Browser.EditButton:DoClick()
            state = Browser.EditorState
            assert(state.id == id and state.contexts.dusk == "cinematic_dusk", "custom editor loads existing assignments")
            state.nameControl:SetText("Renamed visual fixture")
            state.slots.overcast:DoClick()
            Browser:Select({ id = "cinematic_overcast" })
            state.saveButton:DoClick()
            assert(selectedConVar:GetString() == id and table.Count(Palettes.CustomStore.profiles) == 1,
                "editing retains custom id without creating another palette")
            assert(Palettes:LoadCustomProfiles() and Palettes.CustomStore.profiles[id].label == "Renamed visual fixture" and
                Palettes.CustomStore.profiles[id].contexts.overcast == "cinematic_overcast", "name and assignments persist")
        end)
        local result = isolated:Run()
        Browser:CloseEditor()
        Palettes.CustomPath, Palettes.CustomStore, Palettes.CustomFailure = savedPath, savedStore, savedFailure
        Palettes:Select(savedChoice)
        Browser:RefreshCards()
        file.Delete(path)
        file.Delete(path .. ".backup.json")
        for _, test in ipairs(result.cases) do
            for _, failure in ipairs(test.failures) do check(false, failure) end
        end
    end)
    suite:Add("sky_inspection_is_camera_only_and_restores_ui", function(check)
        local Inspection = ZM_SkyInspection
        local position = Vector(LocalPlayer():GetPos())
        local ok, failure = Inspection:Start(Browser.Frame)
        check(ok, "preview starts from browser: " .. tostring(failure))
        local state = Inspection.State
        if not state then return end
        check(not Browser.Frame:IsVisible() and IsValid(state.frame), "browser hidden behind full-screen HUD-free view")
        for index = 0, 4 do
            local elapsed = 0.8 + index / 4 * (Inspection.Duration - 1.6)
            local view = Inspection:GetView(state, elapsed)
            check(math.abs(view.angles.y - state.yaw - index * 90) < 0.001, "turn visits sky corner " .. index)
            check(view.drawhud == false and view.drawviewmodel == false, "inspection view hides HUD and weapon")
        end
        local clearedButtons, clearedMovement, retainedAngles = false, false, false
        Inspection:BlockInput({
            ClearButtons = function() clearedButtons = true end,
            ClearMovement = function() clearedMovement = true end,
            SetViewAngles = function(_, angles) retainedAngles = angles == state.playerAngles end
        })
        check(clearedButtons and clearedMovement and retainedAngles, "camera preview blocks gameplay input without aim rotation")
        state.frame:OnKeyCodePressed(KEY_SPACE)
        check(not Inspection:IsActive() and Browser.Frame:IsVisible(), "early return restores the same browser")
        check(LocalPlayer():GetPos():DistToSqr(position) == 0, "survivor not teleported")
        check(Inspection:Start(Browser.Frame), "preview reopens")
        if Inspection.State then
            Inspection.State.startedAt = RealTime() - Inspection.Duration - 1
            Inspection.State.frame:Think()
            check(not Inspection:IsActive() and Browser.Frame:IsVisible(), "timeout restores UI")
        end
        check(selectedConVar:GetString() == savedChoice, "preview does not change saved sky")
    end)
    suite:Add("browser_close_reopen_and_parent_cleanup", function(check)
        Browser:Close()
        check(not IsValid(Browser.Frame) and IsValid(root), "Back closes only the browser")
        Browser:Open(root)
        local ok, failure = ZM_SkyInspection:Start(Browser.Frame)
        check(ok, "preview starts before parent cleanup: " .. tostring(failure))
        root:Remove()
        Browser.Frame:Think()
        check(not IsValid(Browser.Frame), "removing Options also removes its browser")
        check(not ZM_SkyInspection:IsActive(), "parent removal also cleans up camera preview")
        check(selectedConVar:GetString() == savedChoice, "opening, browsing and closing never changes selection")
    end)
    local summary = suite:Run()
    ZM_SkyInspection:Finish("test cleanup")
    Palettes:Select(savedChoice)
    Palettes.Preview = savedPreview
    Palettes:Update()
    Browser:Close()
    if IsValid(root) then root:Remove() end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/sky_browser_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Sky browser " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
    end
end)
