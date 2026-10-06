ZM_SkyInspection = ZM_SkyInspection or {}
local Inspection = ZM_SkyInspection
if Inspection.State and Inspection.Finish then Inspection:Finish("reload") end
Inspection.Duration = 10
Inspection.Height = 512

function Inspection:GetView(state, elapsed)
    local rise = math.Clamp(elapsed / 0.8, 0, 1)
    rise = rise * rise * (3 - 2 * rise)
    local turn = math.Clamp((elapsed - 0.8) / (self.Duration - 1.6), 0, 1)
    local zenith = math.Clamp((elapsed - self.Duration + 0.8) / 0.8, 0, 1)
    return { origin = LerpVector(rise, state.startOrigin, state.origin),
        angles = Angle(Lerp(zenith, -20, -85), state.yaw + turn * 360, 0),
        x = 0, y = 0, w = ScrW(), h = ScrH(), fov = 75, drawhud = false, drawviewmodel = false }
end

function Inspection:IsActive()
    return self.State ~= nil
end

function Inspection:BlockInput(cmd)
    local state = self.State
    if not state then return false end
    cmd:ClearButtons()
    cmd:ClearMovement()
    cmd:SetViewAngles(state.playerAngles)
    return true
end

function Inspection:Finish(reason, restore)
    local state = self.State
    if not state then return end
    self.State = nil
    self.LastResult = { reason = reason, elapsed = RealTime() - state.startedAt,
        playerMoved = IsValid(LocalPlayer()) and LocalPlayer():GetPos():DistToSqr(state.playerPosition) > 1,
        renders = state.renders, cameraOnly = true }
    if IsValid(state.frame) then state.frame:Remove() end
    for panel, visible in pairs(state.hidden) do
        if IsValid(panel) then panel:SetVisible(visible) end
    end
    if restore ~= false and IsValid(state.browser) then
        state.browser:MakePopup()
        gui.EnableScreenClicker(true)
        input.SetCursorPos(state.cursorX, state.cursorY)
    else
        local visible = false
        for panel in pairs(ZM_UI.TransientPanels) do
            if panel ~= state.browser and IsValid(panel) and panel:IsVisible() then visible = true break end
        end
        gui.EnableScreenClicker(visible)
    end
end

function Inspection:Start(browser)
    if self.State then return false, "A sky preview is already running." end
    local player = LocalPlayer()
    if not IsValid(player) or not IsValid(browser) or not browser:IsVisible() then
        return false, "Open the sky browser before previewing."
    end
    if ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud() then return false, "Wait for the map transition to finish." end
    local eye = player:EyePos()
    local trace = util.TraceHull({ start = eye, endpos = eye + Vector(0, 0, self.Height),
        mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), filter = player, mask = MASK_SOLID })
    if trace.StartSolid then return false, "The preview camera is obstructed; move into an open area." end
    local x, y = gui.MousePos()
    local state = { browser = browser, startedAt = RealTime(), map = game.GetMap(),
        startOrigin = Vector(eye), origin = trace.Hit and trace.HitPos - Vector(0, 0, 8) or trace.HitPos,
        yaw = player:EyeAngles().y, playerAngles = Angle(player:EyeAngles()), playerPosition = Vector(player:GetPos()),
        health = player:Health(), alive = player:Alive(), cursorX = x, cursorY = y, hidden = {}, renders = 0 }
    for panel in pairs(ZM_UI.TransientPanels) do
        if IsValid(panel) then state.hidden[panel] = panel:IsVisible() panel:SetVisible(false) end
    end
    state.hidden[browser] = true
    browser:SetVisible(false)
    local frame = vgui.Create("DFrame")
    state.frame = frame
    self.State = state
    frame:SetPos(0, 0)
    frame:SetSize(ScrW(), ScrH())
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:SetDeleteOnClose(true)
    frame:SetDrawOnTop(true)
    frame:MakePopup()
    frame:SetMouseInputEnabled(false)
    gui.EnableScreenClicker(false)
    ZM_UI:RegisterTransient(frame)
    frame.OnRemove = function()
        ZM_UI:UnregisterTransient(frame)
        if self.State == state then self:Finish("closed", false) end
    end
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE or key == KEY_SPACE then self:Finish("cancelled") end
    end
    frame.Think = function()
        local current = LocalPlayer()
        if not IsValid(browser) or not IsValid(current) or game.GetMap() ~= state.map then
            self:Finish("parent or map changed", false)
        elseif gui.IsGameUIVisible() or (ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud()) then
            self:Finish("interrupted")
        elseif state.alive and (not current:Alive() or current:Health() < state.health) then
            self:Finish("survivor needs attention")
        elseif RealTime() - state.startedAt >= self.Duration then self:Finish("completed") end
    end
    frame.Paint = function(_, width, height)
        if self.State ~= state then return end
        local view = self:GetView(state, RealTime() - state.startedAt)
        view.w, view.h = width, height
        local ok, failure = ZM_Skybox:RenderClientView(view)
        if not ok then
            ZM_SkyBrowser.Error = "Sky preview failed: " .. tostring(failure)
            self:Finish("render failed")
            return
        end
        state.renders = state.renders + 1
    end
    return true
end

function Inspection:GetDiagnosticSnapshot()
    local state = self.State
    return { active = state ~= nil, cameraOnly = true, duration = self.Duration,
        renders = state and state.renders or 0, elapsed = state and RealTime() - state.startedAt,
        lastResult = self.LastResult }
end

hook.Add("ShutDown", "ZM.SkyInspection.Cleanup", function() Inspection:Finish("shutdown", false) end)
