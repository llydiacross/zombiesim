ZM_SkyInspection = ZM_SkyInspection or {}
local Inspection = ZM_SkyInspection
if Inspection.State and Inspection.Finish then Inspection:Finish("reload") end
Inspection.Duration = 10
Inspection.Height = 512

function Inspection:GetView(state, elapsed)
    if state.authoredCamera then
        local flightTime = elapsed / (state.duration or ZM_LauncherScene.SkyFlightDuration) * ZM_LauncherScene.SkyFlightDuration
        local origin, angles = ZM_LauncherScene:GetSkyFlightPose(state.authoredCamera, flightTime)
        return { origin = origin, angles = angles, x = 0, y = 0, w = ScrW(), h = ScrH(),
            fov = state.authoredCamera.fov, drawhud = false, drawviewmodel = false }
    end
    local rise = math.Clamp(elapsed / 0.8, 0, 1)
    rise = rise * rise * (3 - 2 * rise)
    local turn = math.Clamp((elapsed - 0.8) / (self.Duration - 1.6), 0, 1)
    local zenith = math.Clamp((elapsed - self.Duration + 0.8) / 0.8, 0, 1)
    return { origin = LerpVector(rise, state.startOrigin, state.origin),
        angles = Angle(Lerp(zenith, state.startPitch, -85), state.yaw + turn * 360, state.roll),
        x = 0, y = 0, w = ScrW(), h = ScrH(),
        fov = state.authoredCamera and state.authoredCamera.fov or 75, drawhud = false, drawviewmodel = false }
end

function Inspection:ValidateLauncherFlight(state, traceHull)
    traceHull = traceHull or util.TraceHull
    local previous = state.startOrigin
    for index = 0, 120 do
        local origin = self:GetView(state, index / 120 * state.duration).origin
        local trace = traceHull({ start = previous, endpos = origin,
            mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), filter = LocalPlayer(), mask = MASK_SOLID })
        if trace.StartSolid or trace.AllSolid or trace.Hit then
            return false, "The launcher flight path is obstructed; give preview_skybox more open space in Hammer."
        end

        previous = origin
    end
    return true
end

function Inspection:GetLauncherFogSettings()
    if not self.Rendering or not self.State or not self.State.authoredCamera or
        (ZM_WorldMap and ZM_WorldMap.Capturing) then return nil end
    return self.State.launcherFog
end

function Inspection:GetEndFade(state, elapsed)
    if not state.authoredCamera then return 0 end
    local fade = math.Clamp((elapsed - state.duration + 1.2) / 1.2, 0, 1)
    return fade * fade * (3 - 2 * fade)
end

function Inspection:UpdateLauncherSlot(state, elapsed)
    local slot = math.min(#state.sequence, math.floor(math.max(0, elapsed) / 5) + 1)
    if slot == state.slot then return true end
    local entry = state.sequence[slot]
    local fog, failure = ZM_SkyPalettes:GetLauncherPreviewFog(entry.id, entry.context)
    if not fog then return false, failure end
    state.slot, state.launcherFog = slot, fog
    ZM_SkyPalettes:Update()
    if ZM_SkyPalettes.Failure then return false, ZM_SkyPalettes.Failure end
    return true
end

function Inspection:RenderFlight(state, width, height)
    local elapsed = RealTime() - state.startedAt
    local ready, failure = self:UpdateLauncherSlot(state, elapsed)
    if not ready then
        ZM_SkyBrowser.Error = "Sky preview failed: " .. tostring(failure)
        self:Finish("sky slot failed")
        return false
    end
    local view = self:GetView(state, elapsed)
    local trace = util.TraceHull({ start = state.lastOrigin or state.startOrigin, endpos = view.origin,
        mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), filter = LocalPlayer(), mask = MASK_SOLID })
    if trace.StartSolid or trace.AllSolid or trace.Hit then
        ZM_SkyBrowser.Error = "Sky preview stopped: an obstacle entered the launcher flight path."
        self:Finish("flight obstructed")
        return false
    end
    state.lastOrigin = view.origin
    view.w, view.h = width, height
    self.Rendering = true
    local started = SysTime()
    local ok, renderFailure = ZM_Skybox:RenderClientView(view)
    local milliseconds = (SysTime() - started) * 1000
    self.Rendering = false
    if not ok then
        ZM_SkyBrowser.Error = "Sky preview failed: " .. tostring(renderFailure)
        self:Finish("render failed")
        return false
    end
    state.renders = state.renders + 1
    state.renderMs = (state.renderMs or 0) + milliseconds
    state.renderMaxMs = math.max(state.renderMaxMs or 0, milliseconds)
    return true
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
    if state.authoredCamera and ZM_Music then ZM_Music:StopSkyPreview(state) end
    self.State = nil
    self.Rendering = false
    if state.launcherFog then ZM_SkyPalettes:Update() end
    self.LastResult = { reason = reason, elapsed = RealTime() - state.startedAt,
        playerMoved = IsValid(LocalPlayer()) and LocalPlayer():GetPos():DistToSqr(state.playerPosition) > 1,
        renders = state.renders, cameraOnly = true, slots = state.sequence and #state.sequence,
        renderMeanMs = state.renders > 0 and (state.renderMs or 0) / state.renders or 0,
        renderMaxMs = state.renderMaxMs }
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
    local authoredCamera
    local menu = ZM_LauncherMenu
    local launcherProfiles = ZM_World and ZM_World.LauncherMapProfiles
    local launcherProfile = launcherProfiles and launcherProfiles[game.GetMap()]
    if menu and menu.Active and launcherProfile and menu.Profile == launcherProfile then
        local camera = menu.PreviewSkyCamera
        if not camera then return false, "The preview launcher sky camera is unavailable; reload the launcher map." end
        authoredCamera = {
            origin = Vector(camera.origin),
            angles = Angle(camera.angles.p, camera.angles.y, camera.angles.r),
            fov = math.Clamp(tonumber(camera.fov) or 90, 30, 120)
        }
    end
    local eye = player:EyePos()
    local startOrigin, origin = eye, nil
    if not authoredCamera then
        local trace = util.TraceHull({ start = eye, endpos = eye + Vector(0, 0, self.Height),
            mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), filter = player, mask = MASK_SOLID })
        if trace.StartSolid then return false, "The preview camera is obstructed; move into an open area." end
        origin = trace.Hit and trace.HitPos - Vector(0, 0, 8) or trace.HitPos
    else
        startOrigin = Vector(authoredCamera.origin)
        origin = startOrigin + Vector(0, 0, self.Height)
    end
    local x, y = gui.MousePos()
    local state = { browser = browser, startedAt = RealTime(), map = game.GetMap(),
        startOrigin = Vector(startOrigin), origin = Vector(origin), authoredCamera = authoredCamera,
        startPitch = authoredCamera and authoredCamera.angles.p or -20,
        yaw = authoredCamera and authoredCamera.angles.y or player:EyeAngles().y,
        roll = authoredCamera and authoredCamera.angles.r or 0,
        playerAngles = Angle(player:EyeAngles()), playerPosition = Vector(player:GetPos()),
        health = player:Health(), alive = player:Alive(), cursorX = x, cursorY = y, hidden = {}, renders = 0 }
    state.duration = authoredCamera and ZM_LauncherScene.SkyFlightDuration or self.Duration
    if authoredCamera then
        local sequence, sequenceFailure = ZM_SkyPalettes:GetLauncherPreviewSequence()
        if not sequence then return false, sequenceFailure end
        state.sequence = sequence
        if #sequence > 1 then state.duration = #sequence * 5 end
        local clear, failure = self:ValidateLauncherFlight(state)
        if not clear then return false, failure end
        state.launcherFog, failure = ZM_SkyPalettes:GetLauncherPreviewFog(sequence[1].id, sequence[1].context)
        if not state.launcherFog then return false, failure end
        state.slot = 1
    end
    for panel in pairs(ZM_UI.TransientPanels) do
        if IsValid(panel) then state.hidden[panel] = panel:IsVisible() panel:SetVisible(false) end
    end
    state.hidden[browser] = true
    browser:SetVisible(false)
    local frame = vgui.Create("DFrame")
    state.frame = frame
    self.State = state
    if state.launcherFog then ZM_SkyPalettes:Update() end
    if state.authoredCamera and ZM_Music then ZM_Music:StartSkyPreview(state) end
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
        elseif RealTime() - state.startedAt >= state.duration + (state.authoredCamera and 0.15 or 0) then
            self:Finish("completed")
        end
    end
    frame.Paint = function(_, width, height)
        if self.State ~= state then return end
        if state.authoredCamera then
            local elapsed = RealTime() - state.startedAt
            local endFade = self:GetEndFade(state, elapsed)
            if #state.sequence > 1 then
                local within = elapsed % 5
                local alpha = math.max(elapsed >= 5 and math.Clamp(1 - within / 0.3, 0, 1) or 0,
                    elapsed < state.duration - 0.3 and math.Clamp((within - 4.7) / 0.3, 0, 1) or 0,
                    endFade)
                surface.SetDrawColor(0, 0, 0, alpha * 255)
                surface.DrawRect(0, 0, width, height)
                draw.SimpleText(string.upper(state.launcherFog.context), "DermaDefault", width * 0.5, height - 28,
                    Color(255, 255, 255, (1 - endFade) * 255), TEXT_ALIGN_CENTER)
            else
                surface.SetDrawColor(0, 0, 0, endFade * 255)
                surface.DrawRect(0, 0, width, height)
            end
            return
        end
        local view = self:GetView(state, RealTime() - state.startedAt)
        view.w, view.h = width, height
        self.Rendering = true
        local ok, failure = ZM_Skybox:RenderClientView(view)
        self.Rendering = false
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
    return { active = state ~= nil, cameraOnly = true, duration = state and state.duration or self.Duration,
        motion = state and state.authoredCamera and "launcher flight" or "sky sweep",
        fog = state and state.launcherFog or nil, rendering = self.Rendering == true,
        slot = state and state.slot, slots = state and state.sequence and #state.sequence,
        renderMeanMs = state and state.renders > 0 and (state.renderMs or 0) / state.renders or nil,
        renderMaxMs = state and state.renderMaxMs,
        renders = state and state.renders or 0, elapsed = state and RealTime() - state.startedAt,
        lastResult = self.LastResult }
end

hook.Add("RenderScene", "ZM.SkyInspection.LauncherFlight", function()
    local state = Inspection.State
    if not state or not state.authoredCamera or Inspection.Rendering or
        (ZM_WorldMap and ZM_WorldMap.Capturing) then return end
    if Inspection:RenderFlight(state, ScrW(), ScrH()) then return true end
end)

hook.Add("ShutDown", "ZM.SkyInspection.Cleanup", function() Inspection:Finish("shutdown", false) end)
