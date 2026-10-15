// Character selection stays open until the server confirms a selected slot.
ZM_LauncherMenu = ZM_LauncherMenu or {}
local Menu = ZM_LauncherMenu
local palette = ZM_DermaSkin.Palette
local launcherLogo = Material("zombiesim/ui/logo.png", "smooth")
local steps = { "slot", "name", "appearance", "profession", "points", "review" }
local menuSounds = {
    hover = "buttons/button15.wav",
    select = "buttons/button14.wav",
    back = "buttons/button10.wav",
    confirm = "buttons/button16.wav"
}
local pageStates = {
    menu = "home",
    load = "play",
    create = "create",
    appearance = "appearance",
    options = "settings",
    content = "settings",
    tools = "tools"
}

function Menu:RefreshState()
    if self.Credits then
        self.State = "credits"
    elseif self.Waiting == "select" then
        self.State = "deploying"
    elseif ZM_SkyInspection and ZM_SkyInspection:IsActive() then
        self.State = "sky_inspection"
    elseif ZM_LauncherSceneClient and ZM_LauncherSceneClient:GetPresentationTransitionState() then
        self.State = ZM_LauncherSceneClient:GetPresentationTransitionState()
    else
        self.State = pageStates[self.Page] or "home"
    end
    return self.State
end

function Menu:SetPage(page)
    if not pageStates[page] then return false end
    if self.ReleaseEarthControls then self:ReleaseEarthControls() end
    self.Page = page
    self:RefreshState()
    if ZM_LauncherSceneClient then
        if page == "load" then
            ZM_LauncherSceneClient:TransitionPresentationState("city", 4.5)
        elseif page ~= "create" and page ~= "appearance" then
            ZM_LauncherSceneClient:TransitionPresentationState("earth", 3)
        end
    end
    self:RefreshState()
    return true
end

function Menu:GetState()
    return self:RefreshState()
end

function Menu:GetLogoStatus()
    local texture = not launcherLogo:IsError() and launcherLogo:GetTexture("$basetexture") or nil
    return {
        valid = not launcherLogo:IsError() and texture ~= nil and texture:Width() > 0,
        width = texture and texture:Width() or 0,
        height = texture and texture:Height() or 0
    }
end

function Menu:IsEarthControlsActive()
    return self.Active and self.Page == "menu" and not self.Waiting and not self.Credits
        and IsValid(self.Frame) and self.Frame:IsVisible()
        and not (ZM_SkyInspection and ZM_SkyInspection:IsActive())
        and ZM_LauncherSceneClient
        and ZM_LauncherSceneClient:GetPresentationState() == "earth"
        and not ZM_LauncherSceneClient:GetPresentationTransitionState()
end

function Menu:ReleaseEarthControls()
    local panel = self.EarthControls
    if IsValid(panel) and panel.DragButton then
        panel.DragButton = nil
        panel:MouseCapture(false)
    end
    if ZM_LauncherSceneClient then ZM_LauncherSceneClient:ReleaseEarthView() end
end

function Menu:SyncEarthControls()
    local wanted = IsValid(self.Frame) and self.Page == "menu" and not self.Waiting and not self.Credits
    if not wanted then
        self:ReleaseEarthControls()
        if IsValid(self.EarthControls) then self.EarthControls:Remove() end
        self.EarthControls = nil
        return nil
    end
    if IsValid(self.EarthControls) then return self.EarthControls end

    local panel = vgui.Create("DPanel")
    panel:SetPaintBackgroundEnabled(false)
    panel:SetKeyboardInputEnabled(false)
    panel.DragButton = nil
    local reset = vgui.Create("DButton", panel)
    reset:SetText("RESET VIEW")
    reset:SetSkin("ZombieSim")
    reset.DoClick = function()
        if self:IsEarthControlsActive() and ZM_LauncherSceneClient then
            ZM_LauncherSceneClient:ResetEarthView()
        end
    end
    local lowerMusic = vgui.Create("DButton", panel)
    lowerMusic:SetSkin("ZombieSim")
    lowerMusic.DoClick = function()
        if self:IsEarthControlsActive() and ZM_Music then
            ZM_Music:ToggleLauncherTrackLevel()
        end
    end
    panel.OnMousePressed = function(viewport, code)
        if not self:IsEarthControlsActive() then return end
        if code == MOUSE_MIDDLE then
            ZM_LauncherSceneClient:ResetEarthView()
            return
        end
        if code ~= MOUSE_LEFT then return end
        viewport.DragButton = code
        viewport.DragX, viewport.DragY = gui.MousePos()
        viewport:MouseCapture(true)
        ZM_LauncherSceneClient:BeginEarthDrag()
    end
    panel.OnMouseReleased = function(viewport, code)
        if code ~= viewport.DragButton then return end
        viewport.DragButton = nil
        viewport:MouseCapture(false)
        ZM_LauncherSceneClient:EndEarthDrag()
    end
    panel.OnMouseWheeled = function(_, delta)
        if not self:IsEarthControlsActive() then return false end
        ZM_LauncherSceneClient:AdjustEarthView(0, 0, delta)
        return true
    end
    panel.Think = function(viewport)
        local active = self:IsEarthControlsActive()
        viewport:SetMouseInputEnabled(active)
        reset:SetVisible(active)
        local left = self.FrameWidth or 0
        viewport:SetPos(left, 0)
        viewport:SetSize(math.max(1, ScrW() - left), ScrH())
        reset:SetPos(18, viewport:GetTall() - 54)
        reset:SetSize(112, 32)
        lowerMusic:SetText(ZM_Music and ZM_Music.LauncherTrackLowered
            and "RESTORE MENU MUSIC" or "LOWER MENU MUSIC")
        lowerMusic:SetPos(138, viewport:GetTall() - 54)
        lowerMusic:SetSize(190, 32)
        if viewport.WasActive and not active then self:ReleaseEarthControls() end
        viewport.WasActive = active
        if not active or not viewport.DragButton then return end
        if not input.IsMouseDown(viewport.DragButton) then
            viewport:OnMouseReleased(viewport.DragButton)
            return
        end
        local x, y = gui.MousePos()
        local deltaX, deltaY = x - viewport.DragX, y - viewport.DragY
        viewport.DragX, viewport.DragY = x, y
        ZM_LauncherSceneClient:AdjustEarthView(deltaX, deltaY, 0, FrameTime())
    end
    panel.Paint = function(viewport, _, height)
        if not self:IsEarthControlsActive() then return end
        draw.SimpleText("DRAG TO SPIN  /  SCROLL TO ZOOM  /  MIDDLE-CLICK TO RECENTER",
            "DermaDefaultBold", 344, height - 38,
            palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    panel.OnRemove = function(viewport)
        if viewport.DragButton then viewport:MouseCapture(false) end
        if self.EarthControls == viewport then self.EarthControls = nil end
        if ZM_LauncherSceneClient then ZM_LauncherSceneClient:ReleaseEarthView() end
    end
    self.EarthControls = panel
    return panel
end

function Menu:PlayCue(cue)
    local soundPath = menuSounds[cue]
    if not soundPath then return end
    if cue == "hover" then
        local now = RealTime()
        if now - (self.LastHoverSound or 0) < 0.08 then return end
        self.LastHoverSound = now
    end
    surface.PlaySound(soundPath)
end

local function buttonCue(text)
    local normalized = string.lower(text)
    if string.find(normalized, "back", 1, true) or string.find(normalized, "cancel", 1, true) then
        return nil
    end
    if string.find(normalized, "confirm", 1, true) or string.find(normalized, "save", 1, true)
        or string.find(normalized, "delete", 1, true) or string.find(normalized, "deploy", 1, true)
        or string.find(normalized, "next", 1, true) then
        return "confirm"
    end
    return "select"
end

local function addLabel(parent, text, height)
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:DockMargin(4, 4, 4, 4)
    label:SetTall(height or 28)
    label:SetText(text)
    label:SetTextColor(palette.text)
    label:SetWrap(true)
    return label
end

local function addRule(parent, text)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:DockMargin(4, 7, 4, 7)
    panel:SetTall(text and 24 or 1)
    panel.Paint = function(_, width, height)
        local y = math.floor(height * 0.5)
        surface.SetDrawColor(palette.border)
        surface.DrawRect(0, y, width, 1)
        if not text then return end
        surface.SetFont("DermaDefaultBold")
        local textWidth = surface.GetTextSize(text)
        surface.SetDrawColor(5, 8, 12, 245)
        surface.DrawRect(12, y - 10, textWidth + 16, 20)
        draw.SimpleText(text, "DermaDefaultBold", 20, y, palette.muted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return panel
end

local function locationLabel(row)
    local location = row.location or {}
    if not location.available then
        return "LOCATION UNAVAILABLE"
    end
    if location.state == "den" then return "DEN / " .. tostring(location.safeZoneId) end
    return string.upper(location.state or "CITY") .. " / "
        .. tostring(location.cellX) .. ", " .. tostring(location.cellY)
end

local function addSurvivorDossier(parent, slot, row)
    local header = vgui.Create("DPanel", parent)
    header:Dock(TOP)
    header:DockMargin(4, 2, 4, 0)
    header:SetTall(62)
    header.Paint = function(_, width, height)
        surface.SetDrawColor(12, 16, 21, 238)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawRect(0, 0, width, 1)
        surface.DrawRect(0, height - 1, width, 1)
        surface.SetDrawColor(palette.redBright)
        surface.DrawRect(0, 0, 3, height)
        draw.SimpleText(string.upper(row.name or "SURVIVOR"), "ZM_DependencyBriefingTitle",
            16, 12, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("SLOT 0" .. slot, "DermaDefaultBold", width - 14, 15,
            palette.redBright, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        draw.SimpleText(string.upper(tostring(row.job or "SURVIVOR")) .. "  /  LEVEL "
            .. tostring(tonumber(row.level) or 1), "DermaDefault", 17, 43,
            palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local details = vgui.Create("DPanel", parent)
    details:Dock(TOP)
    details:DockMargin(4, 0, 4, 0)
    details:SetTall(58)
    details.Paint = function(_, width, height)
        surface.SetDrawColor(8, 11, 15, 220)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText("RESUME", "DermaDefaultBold", 12, 15, palette.muted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(locationLabel(row), "DermaDefaultBold", width - 12, 15,
            row.location and row.location.available and palette.text or palette.redBright,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local played = tonumber(row.lastPlayedAt) and tonumber(row.lastPlayedAt) > 0
            and os.date("%Y-%m-%d", tonumber(row.lastPlayedAt)) or "NEVER"
        draw.SimpleText("ORIGIN " .. tostring(row.originCellX or "?") .. ", "
            .. tostring(row.originCellY or "?"), "DermaDefault", 12, 41,
            palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("LAST PLAYED " .. played, "DermaDefault", width - 12, 41,
            palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(palette.border)
        surface.DrawRect(12, 29, width - 24, 1)
    end
    return header, details
end

local function addLogo(parent)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:DockMargin(4, 4, 4, 10)
    panel:SetTall(132)
    panel.Paint = function(_, width, height)
        local imageWidth = math.min(width - 24, 288)
        local imageHeight = imageWidth / 2.25
        local x, y = (width - imageWidth) * 0.5, (height - imageHeight) * 0.5
        local breath = 232 + math.sin(RealTime() * 0.8) * 18
        surface.SetDrawColor(8, 10, 13, 150)
        surface.DrawRect(x - 10, y - 7, imageWidth + 20, imageHeight + 14)
        surface.SetDrawColor(palette.redBright.r, palette.redBright.g, palette.redBright.b, 48)
        for index = 0, 5 do
            local offset = index * (imageWidth / 5)
            surface.DrawRect(x + offset - 3, y - 5, math.max(8, imageWidth * 0.13), 1)
            surface.DrawRect(x + imageWidth - offset - imageWidth * 0.1, y + imageHeight + 4,
                math.max(7, imageWidth * 0.1), 1)
        end
        surface.SetMaterial(launcherLogo)
        surface.SetDrawColor(255, 255, 255, breath)
        surface.DrawTexturedRect(x, y, imageWidth, imageHeight)
    end
    return panel
end

local function addButton(parent, text, callback)
    local button = vgui.Create("DButton", parent)
    button:Dock(TOP)
    button:DockMargin(4, 5, 4, 5)
    button:SetTall(37)
    button:SetText(text)
    button.OnCursorEntered = function() Menu:PlayCue("hover") end
    button.DoClick = function(item, ...)
        local cue = buttonCue(text)
        if cue then Menu:PlayCue(cue) end
        callback(item, ...)
    end
    return button
end

local function modelLabel(path)
    local gender, number = string.match(path or "", "/(%a+)_(%d+)%.mdl$")
    if not gender then return tostring(path or "") end
    return string.upper(string.sub(gender, 1, 1)) .. string.sub(gender, 2) .. " " .. number
end

local function attributeLabel(attribute)
    return (string.gsub(attribute, "(%l)(%u)", "%1 %2"))
end

local bonusColour = Color(92, 214, 112)
local previewPages = { create = true, appearance = true }

function Menu:IsCharacterPreviewVisible()
    return IsValid(self.PreviewPanel) and self.PreviewPanel:IsVisible()
end

local function createCharacterPreview()
    local panel = vgui.Create("DModelPanel")
    panel:SetFOV(30)
    panel:SetAmbientLight(Color(70, 70, 80))
    panel:SetDirectionalLight(BOX_TOP, Color(255, 244, 230))
    panel:SetDirectionalLight(BOX_FRONT, Color(170, 170, 185))
    panel:SetMouseInputEnabled(true)
    panel.Yaw, panel.Distance, panel.PanX, panel.PanZ = 0, 150, 0, 0
    panel.PlayerColour = Vector(1, 1, 1)

    panel.LayoutEntity = function(preview, entity)
        local appearance = Menu.Draft and Menu.Draft.appearance
        if appearance then
            entity:SetSkin(tonumber(appearance.skin) or 0)
            for id, value in pairs(appearance.bodygroups or {}) do
                entity:SetBodygroup(tonumber(id) or 0, tonumber(value) or 0)
            end
            local colour = appearance.playerColour or {}
            preview.PlayerColour = Vector(colour[1] or 1, colour[2] or 1, colour[3] or 1)
        end
        if not entity.GetPlayerColor then
            entity.GetPlayerColor = function() return preview.PlayerColour end
        end
        preview:RunAnimation()
        entity:SetAngles(Angle(0, preview.Yaw, 0))
        local lookZ = 36 + preview.PanZ
        preview:SetLookAt(Vector(0, preview.PanX, lookZ))
        preview:SetCamPos(Vector(preview.Distance, preview.PanX, lookZ + 4))
    end

    // Left-drag rotates, right-drag moves the camera, and the wheel zooms.
    panel.OnMousePressed = function(preview, code)
        if code ~= MOUSE_LEFT and code ~= MOUSE_RIGHT then return end
        preview.DragButton = code
        preview.DragX, preview.DragY = gui.MousePos()
        preview:MouseCapture(true)
    end
    panel.OnMouseReleased = function(preview, code)
        if code ~= preview.DragButton then return end
        preview.DragButton = nil
        preview:MouseCapture(false)
    end
    panel.OnMouseWheeled = function(preview, delta)
        preview.Distance = math.Clamp(preview.Distance - delta * 12, 40, 220)
        return true
    end
    local baseThink = panel.Think
    panel.Think = function(preview)
        if baseThink then baseThink(preview) end
        if not preview.DragButton then return end
        if not input.IsMouseDown(preview.DragButton) then
            preview:OnMouseReleased(preview.DragButton)
            return
        end
        local x, y = gui.MousePos()
        local deltaX, deltaY = x - preview.DragX, y - preview.DragY
        preview.DragX, preview.DragY = x, y
        if preview.DragButton == MOUSE_LEFT then
            preview.Yaw = (preview.Yaw + deltaX * 0.6) % 360
        else
            local scale = preview.Distance / 400
            preview.PanX = math.Clamp(preview.PanX - deltaX * scale, -40, 40)
            preview.PanZ = math.Clamp(preview.PanZ + deltaY * scale, -34, 36)
        end
    end

    local basePaint = panel.Paint
    panel.Paint = function(preview, width, height)
        surface.SetDrawColor(0, 0, 0, 70)
        surface.DrawRect(0, 0, width, height)
        basePaint(preview, width, height)
        local draft = Menu.Draft or {}
        local name = isstring(draft.name) and string.Trim(draft.name) ~= "" and draft.name or "UNNAMED SURVIVOR"
        local _, nameHeight = draw.SimpleText(string.upper(name), "ZM_DependencyBriefingTitle", width * 0.5, 36,
            palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(string.upper(draft.job or "NO PROFESSION CHOSEN"), "DermaDefaultBold", width * 0.5,
            42 + nameHeight, palette.redBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("LEFT-DRAG ROTATE  /  RIGHT-DRAG MOVE  /  SCROLL ZOOM", "DermaDefault", width * 0.5,
            height - 28, palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
    return panel
end

// The full-body preview replaces the globe on the right for the whole create/appearance flow.
function Menu:SyncCharacterPreview()
    local draft = self.Draft
    local wanted = IsValid(self.Frame) and self.Frame:IsVisible() and not self.Credits and not self.Waiting
        and previewPages[self.Page] and istable(draft) and istable(draft.appearance)
    if not wanted then
        if IsValid(self.PreviewPanel) then self.PreviewPanel:Remove() end
        self.PreviewPanel = nil
        return nil
    end
    local panel = self.PreviewPanel
    if not IsValid(panel) then
        panel = createCharacterPreview()
        self.PreviewPanel = panel
    end
    local left = self.Frame:GetWide()
    panel:SetPos(left, 0)
    panel:SetSize(math.max(1, ScrW() - left), ScrH())
    if panel.ModelPath ~= draft.appearance.model then
        panel:SetModel(draft.appearance.model)
        panel.ModelPath = draft.appearance.model
        local entity = panel:GetEntity()
        if IsValid(entity) then
            local sequence = entity:LookupSequence("idle_all_01")
            if sequence and sequence > 0 then entity:ResetSequence(sequence) end
        end
    end
    return panel
end

function Menu:Request(action, slot, details)
    if self.Waiting then return end
    if action == "select" and ZM_Distribution then
        local ready, message = ZM_Distribution:RefreshClient()
        if not ready then
            self.Error = "Content packages unavailable: " .. tostring(message)
            self.ContentReturnPage = "load"
            self:SetPage("content")
            self:Render()
            return
        end
    end
    self.RequestReturnPage = self.Page
    self.Waiting = action
    self:RefreshState()
    self.Deadline = RealTime() + 10
    self:Render()
    net.Start("ZM.LauncherRequest")
        net.WriteString(action)
        net.WriteUInt(slot or 0, 3)
        net.WriteString(util.TableToJSON(details or {}, false) or "{}")
    net.SendToServer()
end

function Menu:Back()
    if self.Waiting then return end
    if self.Credits then self:EndCredits(true) return end
    if self.Page == "menu" then return end
    self:PlayCue("back")
    if self.Page == "create" then
        if self.Step <= 2 then
            self:SetPage("load")
        else
            self.Step = self.Step - 1
        end
    elseif self.Page == "appearance" then
        self:SetPage("load")
    elseif self.Page == "content" then
        self:SetPage(self.ContentReturnPage or "options")
        self.ContentReturnPage = nil
    else
        self:SetPage("menu")
    end
    self:Render()
end

function Menu:Open()
    if ZM_Distribution then ZM_Distribution:RefreshWorkshop() end
    if self.Credits then self:EndCredits() end
    self.Active = true
    if ZM_Music then ZM_Music:PlayLauncherTrackOnce() end
    self:SetPage("menu")
    self.Step = 1
    self.Waiting = nil
    if ZM_DependencyPrompts then ZM_DependencyPrompts:SetLauncherBlackout(not self.Camera) end
    if IsValid(self.Frame) then self.Frame:Remove() end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    local frameWidth = math.floor(math.Clamp(ScrW() * 0.38, 340, 680))
    frame:SetSize(frameWidth, ScrH())
    frame:SetPos(0, 0)
    frame:MakePopup()
    frame.Paint = function(_, width, height)
        surface.SetDrawColor(5, 8, 12, 220)
        surface.DrawRect(0, 0, width, height)
        for edge = 1, 8 do
            local shade = edge * 2
            surface.SetDrawColor(0, 0, 0, shade)
            surface.DrawRect(0, 0, edge * 2, height)
            surface.DrawRect(width - edge * 2, 0, edge * 2, height)
        end
        for line = 0, 4 do
            surface.SetDrawColor(255, 255, 255, 4)
            surface.DrawRect(18, 34 + line * 3, width - 36, 1)
        end
        local accent = 112 + math.sin(RealTime() * 2) * 24
        surface.SetDrawColor(palette.redBright.r, palette.redBright.g, palette.redBright.b, accent)
        surface.DrawRect(width - 2, 0, 2, height)
    end
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then self:Back() end
        if key == KEY_ENTER and IsValid(self.FocusedButton) then self.FocusedButton:DoClick() end
        if key == KEY_UP or key == KEY_DOWN then
            local buttons = self.Buttons or {}
            if #buttons == 0 then return end
            self.FocusIndex = ((self.FocusIndex or 1) + (key == KEY_UP and -2 or 0)) % #buttons + 1
            self.FocusedButton = buttons[self.FocusIndex]
            self.FocusedButton:RequestFocus()
        end
    end
    frame.Think = function()
        if self.Waiting and RealTime() > self.Deadline then
            self.Waiting = nil
            self.Error = "Server did not respond. Try again."
            self:SetPage(self.RequestReturnPage or "menu")
            self.RequestReturnPage = nil
            self:Render()
        end
    end
    frame.OnRemove = function()
        if self.Frame ~= frame then return end
        if self.Credits then self:EndCredits() end
        if ZM_CharacterCards then ZM_CharacterCards:Reset() end
        self.Frame = nil
        if IsValid(self.PreviewPanel) then self.PreviewPanel:Remove() end
        self.PreviewPanel = nil
        self:ReleaseEarthControls()
        if IsValid(self.EarthControls) then self.EarthControls:Remove() end
        self.EarthControls = nil
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
    self.FrameWidth = frameWidth
    if ZM_UI then ZM_UI:OpenExclusive(frame) end
    self:Render()
end

function Menu:Render()
    if not IsValid(self.Frame) then return end
    self:RefreshState()
    if ZM_LauncherTools then
        ZM_LauncherTools:Attach(self.Frame, self.FrameWidth)
        if self.Page ~= "tools" or self.Waiting or self.Credits then ZM_LauncherTools:CloseWorkspace() end
    end
    if ZM_Changelog and (self.Page ~= "options" or self.Waiting or self.Credits) then ZM_Changelog:ClosePanel() end
    self:SyncCharacterPreview()
    self:SyncEarthControls()
    if ZM_CharacterCards then ZM_CharacterCards:Reset() end
    if IsValid(self.Content) then self.Content:Remove() end
    local content = vgui.Create("DScrollPanel", self.Frame)
    content:Dock(FILL)
    content:DockMargin(24, 48, 24, 20)
    content:SetAlpha(0)
    content:AlphaTo(255, 0.16, 0)
    self.Content = content
    self.Buttons = {}
    self.FocusIndex = 1
    local function button(text, callback, parent)
        local item = addButton(parent or content, text, callback)
        item.OnKeyCodePressed = function(_, key) self.Frame:OnKeyCodePressed(key) end
        table.insert(self.Buttons, item)
        return item
    end
    if self.Page == "menu" then
        addLogo(content)
    else
        addLabel(content, "Z-NATION ", 52):SetFont("ZM_DependencyBriefingTitle")
    end
    if self.Error then
        addLabel(content, self.Error, 48):SetTextColor(palette.redBright)
        self.Error = nil
    end
    if self.Waiting then
        addLabel(content, self.Waiting == "select" and "DEPLOYING..." or "CONTACTING SERVER...", 52)
        return
    end
    if self.Page == "menu" then
        if ZM_Distribution and not ZM_Distribution.Ready then
            addLabel(content, "CONTENT CHECK FAILED - open Content Addons before deploying.", 42):SetTextColor(palette.redBright)
        end
        button("PLAY", function() self:SetPage("load") self:Render() end)
        local tools = button("TOOLS", function() self:SetPage("tools") self:Render() end)
        if not ZM_LauncherTools or not ZM_LauncherTools:IsAvailable() then
            tools:SetEnabled(false)
            tools:SetTooltip("Launcher tools are unavailable in this profile.")
        end
        button("SETTINGS", function() self:SetPage("options") self:Render() end)
        button("EXIT TO GMOD", function()
            Derma_Query("Disconnect from this session?", "EXIT TO GMOD", "DISCONNECT",
                function() RunConsoleCommand("disconnect") end, "CANCEL", function() end)
        end)
    elseif self.Page == "content" then
        addLabel(content, "WORKSHOP CONTENT", 36)
        if not ZM_Distribution.Manifest and not ZM_Distribution.Packaged then
            addLabel(content, "Loose development installation. No Workshop subscriptions required.", 54)
        else
            addLabel(content, ZM_Distribution.Ready and "Mounted package files and revisions verified."
                or "Content check failed: " .. tostring(ZM_Distribution.Error), 72)
            addLabel(content, "Subscription is not installation. Finish downloads, enable addons and restart if content is not mounted.", 64)
            for _, row in ipairs(ZM_Distribution.WorkshopRows or {}) do
                addLabel(content, string.upper(row.id) .. "\n" .. row.message, 60)
                if row.workshopId ~= "" then
                    local workshopId = row.workshopId
                    button("OPEN WORKSHOP: " .. row.id, function() steamworks.ViewFile(workshopId) end)
                end
            end
        end
        button("RECHECK CONTENT", function()
            ZM_Distribution:RefreshClient()
            self:Render()
        end)
        button("BACK", function() self:Back() end)
    elseif self.Page == "tools" and ZM_LauncherTools and ZM_LauncherTools:IsAvailable() then
        ZM_LauncherTools:BuildMenu(content, button, addLabel, function() self:Render() end)
        button("BACK", function() self:Back() end)
    elseif self.Page == "options" then
        button("BACK", function() self:Back() end)
        button("CONTENT ADDONS", function()
            ZM_Distribution:RefreshWorkshop()
            self.ContentReturnPage = "options"
            self:SetPage("content")
            self:Render()
        end)
        button("CREDITS", function() self:Request("credits_start", 0) end)
        local panel = vgui.Create("DPanel", content)
        panel:Dock(TOP)
        panel:SetTall(640)
        panel.Paint = function() end
        ZM_Options:BuildPanel(panel, { openChangelog = function()
            ZM_Changelog:TogglePanel(self.Frame, self.FrameWidth)
        end })
    elseif self.Page == "load" then
        addRule(content, "SELECT SURVIVOR")
        local slotRow = vgui.Create("DPanel", content)
        slotRow:Dock(TOP)
        slotRow:DockMargin(0, 0, 0, 6)
        slotRow:SetTall(52)
        slotRow.Paint = function() end
        local slotButtons = {}
        for slot = 1, 3 do
            local slotId = slot
            local row = self.Slots and self.Slots[slotId]
            if row then
                slotButtons[slotId] = button("0" .. slotId .. "  "
                    .. string.upper(tostring(row.name or "SURVIVOR")), function()
                    self.SelectedSlot = slotId
                    self:Render()
                end, slotRow)
            else
                slotButtons[slotId] = button("0" .. slotId .. "  + CREATE", function()
                    self.Draft = { slot = slotId, attributes = {}, appearance = { model = ZM_CharacterRules.Models[1],
                        skin = 0, bodygroups = {}, playerColour = { 1, 1, 1 } } }
                    self:SetPage("create")
                    self.Step = 2
                    self:Render()
                end, slotRow)
            end
            local selector = slotButtons[slotId]
            selector:Dock(LEFT)
            selector:DockMargin(slotId == 1 and 4 or 3, 4, slotId == 3 and 4 or 3, 4)
            selector.PaintOver = function(control, width, height)
                if self.SelectedSlot ~= slotId or not (self.Slots and self.Slots[slotId]) then return end
                surface.SetDrawColor(palette.redBright)
                surface.DrawRect(0, height - 2, width, 2)
            end
        end
        slotRow.PerformLayout = function(_, width)
            local available = math.max(width - 20, 3)
            for _, selector in ipairs(slotButtons) do selector:SetWide(math.floor(available / 3)) end
        end
        local selectedSlot = tonumber(self.SelectedSlot)
        local row = selectedSlot and self.Slots and self.Slots[selectedSlot]
        if row then
            addSurvivorDossier(content, selectedSlot, row)
            if ZM_CharacterCards then
                local preview, previewError = ZM_CharacterCards:Create(content, self.Profile, row)
                if not preview then
                    addLabel(content, string.upper(tostring(previewError)), 32):SetTextColor(palette.redBright)
                end
            elseif row.model and util.IsValidModel(row.model) then
                addLabel(content, "CHARACTER PREVIEW UNAVAILABLE", 32):SetTextColor(palette.redBright)
            end
            if tonumber(row.appearanceRequired) ~= 0 then
                addLabel(content, "APPEARANCE REQUIRED BEFORE DEPLOYMENT", 32):SetTextColor(palette.redBright)
            end
            local actionRow = vgui.Create("DPanel", content)
            actionRow:Dock(TOP)
            actionRow:DockMargin(0, 0, 0, 5)
            actionRow:SetTall(48)
            actionRow.Paint = function() end
            local action = button(tonumber(row.appearanceRequired) ~= 0 and "SET APPEARANCE"
                or "DEPLOY " .. string.upper(row.name), function()
                if tonumber(row.appearanceRequired) ~= 0 then
                    self.Draft = { slot = selectedSlot, name = row.name, job = row.job,
                        appearance = { model = ZM_CharacterRules.Models[1], skin = 0,
                        bodygroups = {}, playerColour = { 1, 1, 1 } } }
                    self:SetPage("appearance")
                    self:Render()
                else
                    self:Request("select", selectedSlot)
                end
            end, actionRow)
            action:Dock(LEFT)
            action:DockMargin(4, 3, 3, 3)
            local remove = button("DELETE", function()
                Derma_StringRequest("DELETE SURVIVOR", "Type " .. row.name .. " to delete this character:",
                    "", function(name) self:Request("delete", selectedSlot, { name = name }) end)
            end, actionRow)
            remove:Dock(FILL)
            remove:DockMargin(3, 3, 4, 3)
            actionRow.PerformLayout = function(_, width) action:SetWide(math.floor(width * 0.68)) end
            local location = row.location or {}
            if tonumber(row.appearanceRequired) == 0 and not location.available then
                action:SetEnabled(false)
                action:SetTooltip(location.reason or "Saved location is unavailable")
            end
        else
            addLabel(content, "Choose an occupied slot, or create a new survivor.", 44)
                :SetTextColor(palette.muted)
        end
        addRule(content)
        button("BACK", function() self:Back() end)
    elseif self.Page == "create" or self.Page == "appearance" then
        local draft = self.Draft
        local step = self.Page == "appearance" and "appearance" or steps[self.Step]
        addLabel(content, "CREATE  /  " .. string.upper(step) .. "  /  " .. (self.Page == "appearance" and "LEGACY" or self.Step .. " OF 6"), 36)
        if step == "slot" then
            for slot = 1, 3 do
                if not (self.Slots and self.Slots[slot]) then
                    button("USE EMPTY SLOT " .. slot, function() draft.slot = slot self.Step = 2 self:Render() end)
                end
            end
        elseif step == "name" then
            local input = vgui.Create("DTextEntry", content)
            input:Dock(TOP)
            input:SetTall(36)
            input:SetPlaceholderText("Character name (2-24 characters)")
            input:SetText(draft.name or "")
            input.OnChange = function(field) draft.name = field:GetValue() end
        elseif step == "appearance" then
            addLabel(content, "Choose a face and outfit. The survivor on the right updates as you edit.", 42)
            addLabel(content, "FACE / MODEL", 20):SetFont("DermaDefaultBold")
            local model = ZM_DermaSkin.StyleComboBox(vgui.Create("DComboBox", content))
            model:Dock(TOP)
            model:DockMargin(4, 0, 4, 6)
            model:SetTall(32)
            for _, path in ipairs(ZM_CharacterRules.Models) do model:AddChoice(modelLabel(path), path) end
            model:SetValue(modelLabel(draft.appearance.model))
            model.OnSelect = function(_, _, _, value)
                draft.appearance.model = value
                draft.appearance.skin = 0
                draft.appearance.bodygroups = {}
                self:Render()
            end
            local preview = self.PreviewPanel
            local entity = IsValid(preview) and preview:GetEntity() or nil
            local function addSlider(text, minimum, maximum, decimals, value, onChange)
                local slider = vgui.Create("DNumSlider", content)
                slider:Dock(TOP)
                slider:DockMargin(4, 2, 4, 4)
                ZM_DermaSkin.LabelSlider(slider, text)
                slider:SetMin(minimum)
                slider:SetMax(maximum)
                slider:SetDecimals(decimals)
                slider:SetValue(value)
                slider.OnValueChanged = function(_, newValue) onChange(newValue) end
                return slider
            end
            local skinCount = IsValid(entity) and entity:SkinCount() or 1
            if skinCount > 1 then
                addSlider("Skin", 0, skinCount - 1, 0, draft.appearance.skin or 0, function(value)
                    draft.appearance.skin = math.Round(value)
                end)
            end
            if IsValid(entity) then
                for _, group in ipairs(entity:GetBodyGroups() or {}) do
                    if group.num > 1 then
                        local id = group.id
                        addSlider(attributeLabel(string.gsub(group.name or ("Bodygroup " .. id), "^%l", string.upper)),
                            0, group.num - 1, 0, draft.appearance.bodygroups[tostring(id)] or 0, function(value)
                                draft.appearance.bodygroups[tostring(id)] = math.Round(value)
                            end)
                    end
                end
            end
            for index, colourName in ipairs({ "Red", "Green", "Blue" }) do
                addSlider("Clothing colour - " .. colourName, 0, 1, 2, draft.appearance.playerColour[index] or 1,
                    function(value) draft.appearance.playerColour[index] = math.Round(value, 2) end)
            end
        elseif step == "profession" then
            for _, id in ipairs(ZM_Professions:GetIds()) do
                local profession = ZM_Professions:Get(id)
                button(id, function() draft.job = id self.Step = 5 self:Render() end)
                addLabel(content, profession.description or "", 46)
                local bonuses = {}
                for stat, bonus in pairs(profession.statBonuses or {}) do
                    table.insert(bonuses, stat .. " +" .. bonus)
                end
                table.sort(bonuses)
                addLabel(content, table.concat(bonuses, ", "), 42)
                local services = {}
                for service, enabled in pairs(profession.services or {}) do
                    if enabled then table.insert(services, service) end
                end
                addLabel(content, "Services: " .. table.concat(services, ", ") ..
                    " / Deliveries: " .. #(profession.deliveries or {}), 36)
            end
        elseif step == "points" then
            local function remaining()
                local spent = 0
                for _, points in pairs(draft.attributes) do spent = spent + points end
                return ZM_CharacterRules.StartingPoints - spent
            end
            local counter = addLabel(content, "", 30)
            counter:SetFont("DermaDefaultBold")
            local function update()
                counter:SetText("POINTS REMAINING: " .. remaining() .. " / " .. ZM_CharacterRules.StartingPoints)
            end
            update()
            local header = vgui.Create("DPanel", content)
            header:Dock(TOP)
            header:DockMargin(4, 4, 4, 0)
            header:SetTall(26)
            header.Paint = function(_, width, height)
                surface.SetDrawColor(palette.redDark)
                surface.DrawRect(0, 0, width, height)
                draw.SimpleText("ATTRIBUTE", "DermaDefaultBold", 10, height * 0.5, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("VALUE", "DermaDefaultBold", width - 150, height * 0.5, palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            for index, name in ipairs(ZM_CharacterRules.Attributes) do
                local attribute = name
                local bonus = ZM_Professions:GetStatBonus(draft.job, attribute)
                local line = vgui.Create("DPanel", content)
                line:Dock(TOP)
                line:DockMargin(4, 0, 4, 0)
                line:SetTall(30)
                // Values start at the profession default; spent points are added on top of it.
                line.Paint = function(_, width, height)
                    if index % 2 == 0 then
                        surface.SetDrawColor(30, 33, 38, 240)
                    else
                        surface.SetDrawColor(14, 16, 19, 240)
                    end
                    surface.DrawRect(0, 0, width, height)
                    draw.SimpleText(attributeLabel(attribute), "DermaDefaultBold", 10, height * 0.5, palette.text,
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    local spent = draft.attributes[attribute] or 0
                    local valueX = width - 150
                    draw.SimpleText(tostring(bonus + spent), "DermaDefaultBold", valueX, height * 0.5,
                        spent > 0 and palette.redBright or palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    if bonus > 0 then
                        draw.SimpleText("(+" .. bonus .. ")", "DermaDefaultBold", valueX + 14, height * 0.5, bonusColour,
                            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                end
                local plus = vgui.Create("DButton", line)
                plus:Dock(RIGHT)
                plus:DockMargin(2, 3, 4, 3)
                plus:SetWide(28)
                plus:SetText("+")
                plus.DoClick = function()
                    if remaining() <= 0 or (draft.attributes[attribute] or 0) >= ZM_CharacterRules.MaximumAttribute then return end
                    self:PlayCue("select")
                    draft.attributes[attribute] = (draft.attributes[attribute] or 0) + 1
                    update()
                end
                local minus = vgui.Create("DButton", line)
                minus:Dock(RIGHT)
                minus:DockMargin(2, 3, 2, 3)
                minus:SetWide(28)
                minus:SetText("-")
                minus.DoClick = function()
                    if (draft.attributes[attribute] or 0) <= 0 then return end
                    self:PlayCue("select")
                    draft.attributes[attribute] = draft.attributes[attribute] - 1
                    update()
                end
            end
            button("REVIEW", function()
                if remaining() ~= 0 then self.Error = "Spend all 10 starting points" self:Render() return end
                self.Step = 6 self:Render()
            end)
        elseif step == "review" then
            addLabel(content, "SLOT " .. draft.slot .. "  /  " .. draft.name .. "  /  " .. draft.job, 38)
            addLabel(content, "MODEL " .. modelLabel(draft.appearance.model), 38)
            for _, name in ipairs(ZM_CharacterRules.Attributes) do
                local bonus = ZM_Professions:GetStatBonus(draft.job, name)
                local spent = draft.attributes[name] or 0
                if spent + bonus > 0 then
                    addLabel(content, attributeLabel(name) .. ": " .. (spent + bonus)
                        .. (bonus > 0 and "  (+" .. bonus .. " profession)" or ""), 22)
                end
            end
            button("CONFIRM AND SAVE", function()
                self:Request("create", draft.slot, {
                    name = draft.name, job = draft.job, appearance = draft.appearance, attributes = draft.attributes
                })
            end)
        end
        if step == "name" or step == "appearance" then
            button("NEXT", function()
                if self.Page == "appearance" then
                    self:Request("appearance", draft.slot, draft.appearance)
                else
                    self.Step = self.Step + 1
                    self:Render()
                end
            end)
        end
        button("BACK / CANCEL", function() self:Back() end)
    end
    self.FocusedButton = self.Buttons[1]
end

function Menu:StartCredits()
    if not self.CreditsCamera or not ZM_LauncherSceneClient then return end
    if IsValid(self.CreditsOverlay) then self.CreditsOverlay:Remove() end
    ZM_LauncherSceneClient:BeginCredits()
    if IsValid(self.Frame) then self.Frame:SetVisible(false) end
    self:SyncCharacterPreview()
    local overlay = vgui.Create("DFrame")
    overlay:SetSize(ScrW(), ScrH())
    overlay:SetPos(0, 0)
    overlay:SetTitle("")
    overlay:ShowCloseButton(false)
    overlay:SetDraggable(false)
    overlay:MakePopup()
    overlay.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_SPACE then self:EndCredits(true) end
    end
    overlay.OnMousePressed = function() self:EndCredits(true) end
    overlay.Paint = function(_, width, height)
        local age = RealTime() - ZM_LauncherSceneClient.Started
        local entries = ZM_LauncherScene:GetData()
        local blocks = entries and entries.credits or {}
        local fadeIn = math.max(0, 1 - age) * 255
        local fadeOut = self.CreditsEnding and math.min(1, (RealTime() - self.CreditsEnding) / 0.4) * 255 or 0
        surface.SetDrawColor(0, 0, 0, math.min(255, math.max(fadeIn, fadeOut)))
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(0, 0, 0, 115)
        surface.DrawRect(width * 0.32, 0, width * 0.36, height)
        local y = height + 50 - math.max(0, age - 1) * 24
        for _, block in ipairs(blocks) do
            draw.SimpleText(tostring(block.heading or ""), "ZM_DependencyBriefingTitle", width * 0.5, y,
                palette.text, TEXT_ALIGN_CENTER)
            y = y + 38
            for _, line in ipairs(block.lines or {}) do
                draw.SimpleText(tostring(line), "DermaDefaultBold", width * 0.5, y,
                    palette.text, TEXT_ALIGN_CENTER)
                y = y + 27
            end
            y = y + 90
        end
        if y < -50 then self:EndCredits() return end
        draw.SimpleText("ESC / CLICK TO RETURN", "DermaDefault", width * 0.5, height - 28,
            palette.text, TEXT_ALIGN_CENTER)
        if GetConVar("zombiesim_credits_debug"):GetBool() then
            draw.SimpleText(ZM_LauncherSceneClient.Phase or "room", "DermaDefault",
                width - 120, 24, palette.text)
        end
    end
    self.CreditsOverlay = overlay
end

function Menu:EndCredits(withSound)
    if not self.Credits or self.CreditsEnding then return end
    if withSound then self:PlayCue("back") end
    self.CreditsEnding = RealTime()
    local generation = self.CreditsGeneration
    timer.Simple(0.4, function()
        if self.Credits and self.CreditsEnding and self.CreditsGeneration == generation then
            self:FinishCredits(generation)
        end
    end)
end

function Menu:FinishCredits(generation)
    if generation ~= self.CreditsGeneration then return end
    self.Credits = false
    self.CreditsEnding = nil
    if IsValid(self.CreditsOverlay) then self.CreditsOverlay:Remove() end
    self.CreditsOverlay = nil
    if IsValid(self.Frame) then
        self.Frame:SetVisible(true)
        self.Frame:MakePopup()
    end
    if self.Active and not self.Waiting then self:Request("credits_stop", 0) end
end

function Menu:ApplyRequestResult(action, success, message, deploying)
    self.Waiting = nil
    if not success then
        self.Error = message ~= "" and message or "Server request failed"
        self:SetPage(self.RequestReturnPage or "menu")
    elseif action == "create" or action == "appearance" then
        self:SetPage("load")
    elseif action == "select" and deploying then
        self.Waiting = "select"
        self.Deadline = RealTime() + 30
    elseif action == "credits_start" then
        self:StartCredits()
    end
    self.RequestReturnPage = nil
end

net.Receive("ZM.LauncherStatus", function()
    local action = net.ReadString()
    local success = net.ReadBool()
    local message = net.ReadString()
    local rows = util.JSONToTable(net.ReadString()) or {}
    local deploying = net.ReadBool()
    local hasCamera = net.ReadBool()
    if hasCamera then
        Menu.Camera = { origin = net.ReadVector(), angles = net.ReadAngle(), fov = net.ReadFloat() }
    else
        Menu.Camera = nil
    end
    local hasPreviewSkyCamera = net.ReadBool()
    Menu.PreviewSkyCamera = hasPreviewSkyCamera and
        { origin = net.ReadVector(), angles = net.ReadAngle(), fov = net.ReadFloat() } or nil
    local hasCreditsCamera = net.ReadBool()
    Menu.CreditsCamera = hasCreditsCamera and
        { origin = net.ReadVector(), angles = net.ReadAngle(), fov = net.ReadFloat() } or nil
    local fog = { start = net.ReadFloat(), finish = net.ReadFloat(), density = net.ReadFloat(),
        red = net.ReadUInt(8), green = net.ReadUInt(8), blue = net.ReadUInt(8) }
    if Menu.CreditsCamera then Menu.CreditsCamera.fog = fog end
    Menu.Globe = net.ReadBool() and net.ReadVector() or nil
    local hasPresentationSkybox = net.ReadBool()
    Menu.PresentationSkybox = hasPresentationSkybox and
        { origin = net.ReadVector(), scale = net.ReadFloat() } or nil
    Menu.Profile = net.ReadString()
    Menu.DancerIds = {}
    Menu.DancerNames = {}
    for i = 1, 4 do
        Menu.DancerNames[i] = net.ReadString()
        Menu.DancerIds[i] = net.ReadUInt(16)
    end
    if ZM_DependencyPrompts then ZM_DependencyPrompts:SetLauncherBlackout(not Menu.Camera) end
    if not Menu.Active then Menu:Open() end
    Menu.Slots = {}
    local activeSlot
    for _, row in ipairs(rows) do
        local slot = tonumber(row.slot)
        Menu.Slots[slot] = row
        if tonumber(row.active) == 1 then activeSlot = slot end
    end
    if not Menu.Slots[Menu.SelectedSlot] then Menu.SelectedSlot = activeSlot end
    Menu:ApplyRequestResult(action, success, message, deploying)
    Menu:Render()
end)

hook.Add("CalcView", "ZombieSim.Launcher.MenuCamera", function(_, _, _, fov)
    if not Menu.Active then return end
    if Menu.Credits and ZM_LauncherSceneClient then
        return ZM_LauncherSceneClient:CreditsView()
    end
    if not Menu.Camera then return { origin = vector_origin, angles = angle_zero, fov = fov, drawviewer = false } end
    return { origin = Menu.Camera.origin, angles = Menu.Camera.angles, fov = Menu.Camera.fov,
        drawviewer = false, drawviewmodel = false }
end)

hook.Add("HUDShouldDraw", "ZombieSim.Launcher.HideHud", function()
    if Menu.Active then return false end
end)

hook.Add("PreDrawViewModel", "ZombieSim.Launcher.HideViewModel", function()
    if Menu.Active then return true end
end)
