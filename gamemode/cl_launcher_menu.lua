// Character selection stays open until the server confirms a selected slot.
ZM_LauncherMenu = ZM_LauncherMenu or {}
local Menu = ZM_LauncherMenu
local palette = ZM_DermaSkin.Palette
local steps = { "slot", "name", "appearance", "profession", "points", "review" }
local menuSounds = {
    hover = "buttons/button15.wav",
    select = "buttons/button14.wav",
    back = "buttons/button10.wav",
    confirm = "buttons/button16.wav"
}

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

function Menu:Request(action, slot, details)
    if self.Waiting then return end
    self.Waiting = action
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
        self.Step = math.max(1, self.Step - 1)
        if self.Step == 1 then self.Page = "menu" end
    elseif self.Page == "appearance" then
        self.Page = "load"
    else
        self.Page = "menu"
    end
    self:Render()
end

function Menu:Open()
    if self.Credits then self:EndCredits() end
    self.Active = true
    self.Page = "menu"
    self.Step = 1
    self.Waiting = nil
    if ZM_DependencyPrompts then ZM_DependencyPrompts:SetLauncherBlackout(not self.Camera) end
    if IsValid(self.Frame) then self.Frame:Remove() end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    local frameWidth = math.Clamp(ScrW() * 0.38, 340, 680)
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
            self.Page = "menu"
            self:Render()
        end
    end
    frame.OnRemove = function()
        if self.Frame ~= frame then return end
        if self.Credits then self:EndCredits() end
        self.Frame = nil
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end
    self:Render()
end

function Menu:Render()
    if not IsValid(self.Frame) then return end
    if IsValid(self.Content) then self.Content:Remove() end
    local content = vgui.Create("DScrollPanel", self.Frame)
    content:Dock(FILL)
    content:DockMargin(24, 48, 24, 20)
    content:SetAlpha(0)
    content:AlphaTo(255, 0.16, 0)
    self.Content = content
    self.Buttons = {}
    self.FocusIndex = 1
    local function button(text, callback)
        local item = addButton(content, text, callback)
        item.OnKeyCodePressed = function(_, key) self.Frame:OnKeyCodePressed(key) end
        table.insert(self.Buttons, item)
        return item
    end
    addLabel(content, "Z-NATION ", 52):SetFont("ZM_DependencyBriefingTitle")
    if self.Error then
        addLabel(content, self.Error, 48):SetTextColor(palette.redBright)
        self.Error = nil
    end
    if self.Waiting then
        addLabel(content, self.Waiting == "select" and "DEPLOYING..." or "CONTACTING SERVER...", 52)
        return
    end
    if self.Page == "menu" then
        local anchor = ZM_LauncherScene:GetAnchor(self.Profile)
        if anchor then
            for slot, row in pairs(self.Slots or {}) do
                button((slot == self.SelectedSlot and "● " or "○ ") .. "Continue: " .. row.name .. " / " .. anchor.city,
                    function() self.SelectedSlot = slot self:Render() end)
            end
        end
        button("NEW CHARACTER", function()
            self.Draft = { attributes = {}, appearance = { model = ZM_CharacterRules.Models[1], skin = 0, bodygroups = {}, playerColour = { 1, 1, 1 } } }
            self.Step = 1
            self.Page = "create"
            self:Render()
        end)
        button("EDIT CHARACTERS", function() self.Page = "load" self:Render() end)
        button("OPTIONS", function() self.Page = "options" self:Render() end)
        button("CREDITS", function() self:Request("credits_start", 0) end)
        button("EXIT TO GMOD", function()
            Derma_Query("Disconnect from this session?", "EXIT TO GMOD", "DISCONNECT",
                function() RunConsoleCommand("disconnect") end, "CANCEL", function() end)
        end)
    elseif self.Page == "options" then
        button("BACK", function() self:Back() end)
        local panel = vgui.Create("DPanel", content)
        panel:Dock(TOP)
        panel:SetTall(math.min(ScrH() - 230, 540))
        panel.Paint = function() end
        ZM_Options:BuildPanel(panel)
    elseif self.Page == "load" then
        addLabel(content, "CHOOSE A SURVIVOR", 36)
        for slot = 1, 3 do
            local row = self.Slots and self.Slots[slot]
            if row then
                addLabel(content, string.format("%d  %s  /  %s  /  LEVEL %d", slot, row.name, row.job,
                    tonumber(row.level) or 1), 28)
                addLabel(content, string.format("ORIGIN %s, %s  /  LAST PLAYED %s", row.originCellX or "?",
                    row.originCellY or "?", tonumber(row.lastPlayedAt) and tonumber(row.lastPlayedAt) > 0
                        and os.date("%Y-%m-%d", tonumber(row.lastPlayedAt)) or "NEVER"), 24)
                if row.model and util.IsValidModel(row.model) then
                    local preview = vgui.Create("DModelPanel", content)
                    preview:Dock(TOP)
                    preview:SetTall(124)
                    preview:SetModel(row.model)
                    preview:SetFOV(45)
                    preview:SetCamPos(Vector(70, 0, 55))
                    preview:SetLookAt(Vector(0, 0, 50))
                    preview.LayoutEntity = function(_, entity) entity:SetAngles(Angle(0, RealTime() * 15 % 360, 0)) end
                end
                button(tonumber(row.appearanceRequired) ~= 0 and "SET APPEARANCE" or "DEPLOY " .. row.name,
                    function()
                        if tonumber(row.appearanceRequired) ~= 0 then
                            self.Draft = { slot = slot, appearance = { model = ZM_CharacterRules.Models[1], skin = 0,
                                bodygroups = {}, playerColour = { 1, 1, 1 } } }
                            self.Page = "appearance"
                            self:Render()
                        else
                            self:Request("select", slot)
                        end
                    end)
                button("DELETE " .. row.name, function()
                    Derma_StringRequest("DELETE SURVIVOR", "Type " .. row.name .. " to delete this character:",
                        "", function(name) self:Request("delete", slot, { name = name }) end)
                end)
            else
                button("SLOT " .. slot .. "  /  EMPTY - CREATE", function()
                    self.Draft = { slot = slot, attributes = {}, appearance = { model = ZM_CharacterRules.Models[1],
                        skin = 0, bodygroups = {}, playerColour = { 1, 1, 1 } } }
                    self.Page = "create"
                    self.Step = 2
                    self:Render()
                end)
            end
        end
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
            addLabel(content, "Choose a male or female face / model. Drag the preview to inspect it.", 42)
            local preview = vgui.Create("DModelPanel", content)
            preview:Dock(TOP)
            preview:SetTall(175)
            preview:SetModel(draft.appearance.model)
            preview:SetFOV(38)
            preview:SetCamPos(Vector(80, 0, 55))
            preview:SetLookAt(Vector(0, 0, 51))
            preview.LayoutEntity = function(_, entity) entity:SetAngles(Angle(0, RealTime() * 20 % 360, 0)) end
            local model = vgui.Create("DComboBox", content)
            model:Dock(TOP)
            model:SetTall(32)
            model:SetValue(draft.appearance.model)
            for _, path in ipairs(ZM_CharacterRules.Models) do model:AddChoice(path, path) end
            model.OnSelect = function(_, _, _, value)
                draft.appearance.model = value
                draft.appearance.skin = 0
                draft.appearance.bodygroups = {}
                preview:SetModel(value)
                self:Render()
            end
            local skin = vgui.Create("DNumSlider", content)
            skin:Dock(TOP)
            skin:SetTall(44)
            skin:SetText("Skin")
            skin:SetMin(0)
            local entity = preview:GetEntity()
            skin:SetMax(IsValid(entity) and math.max(0, entity:SkinCount() - 1) or 0)
            skin:SetDecimals(0)
            skin:SetValue(draft.appearance.skin)
            skin.OnValueChanged = function(_, value)
                draft.appearance.skin = math.Round(value)
                if IsValid(preview:GetEntity()) then preview:GetEntity():SetSkin(draft.appearance.skin) end
            end
            if IsValid(entity) then
                for _, group in ipairs(entity:GetBodyGroups() or {}) do
                    if group.num > 1 then
                        local id = group.id
                        local groupSlider = vgui.Create("DNumSlider", content)
                        groupSlider:Dock(TOP)
                        groupSlider:SetTall(44)
                        groupSlider:SetText(group.name)
                        groupSlider:SetMin(0)
                        groupSlider:SetMax(group.num - 1)
                        groupSlider:SetDecimals(0)
                        groupSlider:SetValue(draft.appearance.bodygroups[tostring(id)] or 0)
                        groupSlider.OnValueChanged = function(_, value)
                            draft.appearance.bodygroups[tostring(id)] = math.Round(value)
                            if IsValid(preview:GetEntity()) then preview:GetEntity():SetBodygroup(id, math.Round(value)) end
                        end
                    end
                end
            end
            for index, colourName in ipairs({ "RED", "GREEN", "BLUE" }) do
                local slider = vgui.Create("DNumSlider", content)
                slider:Dock(TOP)
                slider:SetTall(43)
                slider:SetText("Player colour " .. colourName)
                slider:SetMin(0)
                slider:SetMax(1)
                slider:SetDecimals(2)
                slider:SetValue(draft.appearance.playerColour[index])
                slider.OnValueChanged = function(_, value) draft.appearance.playerColour[index] = math.Round(value, 2) end
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
            local function update() counter:SetText("POINTS REMAINING: " .. remaining()) end
            update()
            for _, name in ipairs(ZM_CharacterRules.Attributes) do
                local attribute = name
                local bonus = ZM_Professions:GetStatBonus(draft.job, attribute)
                local line = vgui.Create("DPanel", content)
                line:Dock(TOP)
                line:SetTall(34)
                line.Paint = function() end
                local label = vgui.Create("DLabel", line)
                label:Dock(FILL)
                label:SetTextColor(palette.text)
                local function refresh() label:SetText(attribute .. "  " .. (draft.attributes[attribute] or 0) .. "  +" .. bonus .. " PROFESSION") update() end
                local plus = vgui.Create("DButton", line)
                plus:Dock(RIGHT)
                plus:SetWide(30)
                plus:SetText("+")
                plus.DoClick = function()
                    if remaining() <= 0 or (draft.attributes[attribute] or 0) >= ZM_CharacterRules.MaximumAttribute then return end
                    draft.attributes[attribute] = (draft.attributes[attribute] or 0) + 1
                    refresh()
                end
                local minus = vgui.Create("DButton", line)
                minus:Dock(RIGHT)
                minus:SetWide(30)
                minus:SetText("-")
                minus.DoClick = function()
                    draft.attributes[attribute] = math.max(0, (draft.attributes[attribute] or 0) - 1)
                    refresh()
                end
                refresh()
            end
            button("REVIEW", function()
                if remaining() ~= 0 then self.Error = "Spend all 10 starting points" self:Render() return end
                self.Step = 6 self:Render()
            end)
        elseif step == "review" then
            addLabel(content, "SLOT " .. draft.slot .. "  /  " .. draft.name .. "  /  " .. draft.job, 38)
            addLabel(content, "MODEL " .. draft.appearance.model, 38)
            for _, name in ipairs(ZM_CharacterRules.Attributes) do
                if (draft.attributes[name] or 0) > 0 then addLabel(content, name .. ": " .. draft.attributes[name], 22) end
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
    local hasCreditsCamera = net.ReadBool()
    Menu.CreditsCamera = hasCreditsCamera and
        { origin = net.ReadVector(), angles = net.ReadAngle(), fov = net.ReadFloat() } or nil
    local fog = { start = net.ReadFloat(), finish = net.ReadFloat(), density = net.ReadFloat(),
        red = net.ReadUInt(8), green = net.ReadUInt(8), blue = net.ReadUInt(8) }
    if Menu.CreditsCamera then Menu.CreditsCamera.fog = fog end
    Menu.Globe = net.ReadBool() and net.ReadVector() or nil
    Menu.Profile = net.ReadString()
    Menu.DancerIds = {}
    Menu.DancerNames = {}
    for i = 1, 4 do
        Menu.DancerNames[i] = net.ReadString()
        Menu.DancerIds[i] = net.ReadUInt(16)
    end
    if ZM_DependencyPrompts then ZM_DependencyPrompts:SetLauncherBlackout(not Menu.Camera) end
    if not Menu.Active then Menu:Open() end
    Menu.Waiting = nil
    Menu.Slots = {}
    for _, row in ipairs(rows) do Menu.Slots[tonumber(row.slot)] = row end
    if not success then
        Menu.Error = message ~= "" and message or "Server request failed"
        Menu.Page = "menu"
    elseif action == "create" then
        Menu.Page = "load"
    elseif action == "appearance" then
        Menu.Page = "load"
    elseif action == "select" and deploying then
        Menu.Waiting = "select"
        Menu.Deadline = RealTime() + 30
    elseif action == "credits_start" then
        Menu:StartCredits()
    end
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
