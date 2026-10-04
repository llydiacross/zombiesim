// Third-person camera. The default is a locked top-down view with a fixed north-up yaw, where the player faces
// a virtual aim cursor and WASD moves relative to the screen. Middle click toggles the free orbit camera, and
// the view glides between the two. Shoulder view uses mouse-look; holding Z fixes the camera and frees the aim cursor.
// dist eases toward targetDist each frame.
local dist = 250
local targetDist = 250
local minDist = 50
local maxDist = 500
local up = 20
local zoomStep = 25

// Free camera: zooming into the last shoulderZone units glides the camera onto the player's right shoulder.
local shoulderZone = 50
local shoulderRight = 16
local shoulderBack = 12
local shoulderUp = 4
local shoulderMinPitch = -45
local shoulderMaxPitch = 30

// Free camera: mouse movement rotates the model, while the camera stays behind it.
local modelYaw = 0
local modelPitch = 45
local entryCameraUntil = 0

// Locked camera: yaw 90 puts world north (+Y) at the top of the screen; pitch steepens as it zooms out.
local lockedYaw = 90
local lockedMinPitch = 75
local lockedMaxPitch = 89
local lockBlendSpeed = 3
local cursorMargin = 24
local cursorPlaceDistance = 150
local cameraLocked = true
local lockBlend = 1
local aimYaw = 0
local aimPitch = 0
local shoulderCursorActive = false
local shoulderAimActive = false
local aimTransitionUntil = 0
local cursorX, cursorY
local lastViewOrigin
local middleWasDown = false
local denCameraBlend = 0
local lastDenCameraState
local lockedCameraObstructed = false
local arrivalCameraRise = 1
local arrivalCameraRiseStart = 0
local arrivalCameraRiseDuration = 0
local exitCameraStart = 0
local exitCameraDuration = 0
local exitCameraHeight = 96
local predictedWalk

local function isInDenCamera(ply)
    if not IsValid(ply) or not ZM_World or not ZM_World:IsLoaded() then
        return false
    end
    local safeZoneId = ply:GetNWString("CurrentSafeZoneId", "")
    local mapName = string.lower(game.GetMap())
    if safeZoneId ~= "" and safeZoneId ~= "NULL" then
        local mapPath = ZM_SafeZones:GetMap(safeZoneId)
        local expectedMap = mapPath and string.match(mapPath, "([^/]+)$")
        if expectedMap and string.lower(expectedMap) == mapName then return true end
    end
    local worldData = ZM_World:GetData()
    for _, safeZone in ipairs(worldData and worldData.safeZones or {}) do
        if type(safeZone.map) == "string" and string.lower(safeZone.map) == mapName then
            return true
        end
    end
    return false
end

// Mouse sensitivity scales cursor movement in the locked camera and look speed in the free camera.
local sensitivityCookie = "zombiesim_mouse_sensitivity"
local defaultSensitivity = 0.3
local minimumSensitivity = 0.1
local maximumSensitivity = 2
// Keep saved sensitivity values calibrated independently of the default.
local freeLookScale = 0.022 / 0.5
local sensitivity = math.Clamp(tonumber(cookie.GetString(sensitivityCookie, tostring(defaultSensitivity))) or defaultSensitivity, minimumSensitivity, maximumSensitivity)

function ZM_GetMouseSensitivity()
    return sensitivity
end

function ZM_SetMouseSensitivity(value)
    sensitivity = math.Clamp(tonumber(value) or defaultSensitivity, minimumSensitivity, maximumSensitivity)
    cookie.Set(sensitivityCookie, tostring(math.Round(sensitivity, 2)))
end

function ZM_GetMouseSensitivityRange()
    return minimumSensitivity, maximumSensitivity, defaultSensitivity
end

// Invert-Y per free-camera mode ("orbit" or "shoulder"): true means moving the mouse up looks down. Both default off.
local invertSettings = {
    orbit = { cookie = "zombiesim_mouse_inverted_orbit", default = "0" },
    shoulder = { cookie = "zombiesim_mouse_inverted_shoulder", default = "0" }
}
local invertY = {}
for mode, setting in pairs(invertSettings) do
    invertY[mode] = cookie.GetString(setting.cookie, setting.default) == "1"
end

function ZM_GetInvertMouseY(mode)
    return invertY[mode] == true
end

function ZM_SetInvertMouseY(mode, inverted)
    local setting = invertSettings[mode]
    if not setting then
        return
    end
    invertY[mode] = inverted == true
    cookie.Set(setting.cookie, invertY[mode] and "1" or "0")
end

net.Receive("ZM.PlayerTransitionEntry", function()
    modelYaw = net.ReadFloat()
    aimYaw = modelYaw
    aimPitch = 0
    cursorX = nil
    arrivalCameraRiseDuration = math.max(0, net.ReadFloat())
    local speed = net.ReadFloat()
    // Delay while the screen stays black for the engine's post-load input lock.
    local delay = math.max(0, net.ReadFloat())
    arrivalCameraRiseStart = CurTime() + delay
    arrivalCameraRise = arrivalCameraRiseDuration > 0 and 0 or 1
    entryCameraUntil = arrivalCameraRiseStart + arrivalCameraRiseDuration
    predictedWalk = {
        startTime = arrivalCameraRiseStart,
        untilTime = entryCameraUntil,
        yaw = modelYaw,
        speed = speed
    }
end)

// Server-driven exit sequence; an inactive message cancels it and returns control to the player.
net.Receive("ZM.PlayerTransitionExit", function()
    local active = net.ReadBool()
    local yaw = net.ReadFloat()
    local duration = net.ReadFloat()
    if not active then
        exitCameraDuration = 0
        entryCameraUntil = 0
        cursorX = nil
        predictedWalk = nil
        if ZM_LoadingScreen then ZM_LoadingScreen:Clear() end
        return
    end
    if ZM_LoadingScreen then ZM_LoadingScreen:BeginFadeOut(duration, net.ReadString()) end
    modelYaw = yaw
    aimYaw = yaw
    aimPitch = 0
    cursorX = nil
    exitCameraStart = CurTime()
    exitCameraDuration = math.max(0.01, duration)
    entryCameraUntil = math.huge
    predictedWalk = { untilTime = exitCameraStart + exitCameraDuration, yaw = yaw, speed = 100, holdAfter = true }
end)

// Mirrors the server's scripted transition walk so client prediction keeps the player moving dead straight.
// Movement input interrupts an arrival walk (never the committed exit sequence) and releases the camera.
local movementButtons = bit.bor(IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT, IN_JUMP)

local function isWalkActive(walk)
    return walk ~= nil and (walk.holdAfter or CurTime() < walk.untilTime)
end

local function isWalkHeld(walk)
    return walk ~= nil and walk.startTime ~= nil and CurTime() < walk.startTime
end

local function cancelArrivalWalk()
    predictedWalk = nil
    entryCameraUntil = 0
    net.Start("ZM.CancelTransitionWalk")
    net.SendToServer()
end

local mouseCancelThreshold = 2

// Mouse look cancels any arrival walk, even before the den view has been detected after the level change. During
// the committed den exit walk the mouse is ignored and the view turns smoothly toward the exit instead of snapping.
hook.Add("InputMouseApply", "ZM.HoldTransitionWalkView", function(cmd, x, y, angles)
    local walk = predictedWalk
    if not isWalkActive(walk) then
        return
    end
    if not walk.holdAfter then
        if not isWalkHeld(walk) and math.abs(x) + math.abs(y) > mouseCancelThreshold then
            cancelArrivalWalk()
        end
        return
    end
    if not isInDenCamera(LocalPlayer()) then
        return
    end
    cmd:SetMouseX(0)
    cmd:SetMouseY(0)
    cmd:SetViewAngles(LerpAngle(math.min(FrameTime() * 10, 1), angles, Angle(0, walk.yaw, 0)))
    return true
end)

hook.Add("SetupMove", "ZM.PredictTransitionWalk", function(ply, moveData)
    local walk = predictedWalk
    if not walk or ply ~= LocalPlayer() then
        return
    end
    // The server discards input during the engine lock; predict standing still so nothing snaps back.
    if isWalkHeld(walk) then
        moveData:SetForwardSpeed(0)
        moveData:SetSideSpeed(0)
        return
    end
    local walking = CurTime() < walk.untilTime
    if not walk.holdAfter and (not walking or bit.band(moveData:GetButtons(), movementButtons) ~= 0) then
        predictedWalk = nil
        entryCameraUntil = 0
        return
    end
    moveData:SetMoveAngles(Angle(0, walk.yaw, 0))
    moveData:SetForwardSpeed(walking and walk.speed or 0)
    moveData:SetSideSpeed(0)
end)

function ZM_IsCameraLocked()
    return cameraLocked
end

// Returns 0..1: how far the free camera has moved onto the player's shoulder (0 while locked).
local function getShoulderWeight()
    local zoom = math.Clamp((dist - minDist) / shoulderZone, 0, 1)
    return (1 - zoom) * (1 - lockBlend)
end

function ZM_IsShoulderCamera()
    return not cameraLocked and not isInDenCamera(LocalPlayer()) and getShoulderWeight() > 0.5
end

function ZM_IsInDenCamera()
    return isInDenCamera(LocalPlayer())
end

// Returns the aim cursor's screen position while the camera is locked (never in the first-person den camera).
function ZM_GetAimCursor()
    if not (cameraLocked or shoulderCursorActive) or not cursorX or isInDenCamera(LocalPlayer())
        or vgui.CursorVisible() or gui.IsGameUIVisible() then
        return nil
    end
    return cursorX, cursorY
end

local function getLockedPitch()
    local zoom = math.Clamp((dist - minDist) / (maxDist - minDist), 0, 1)
    return Lerp(zoom, lockedMinPitch, lockedMaxPitch)
end

local function getFreeCameraAngles()
    return Angle(modelPitch, modelYaw, 0)
end

// Blends free and locked angles with smoothstep easing while the camera glides between modes.
local function GetCameraAngles()
    local locked = Angle(getLockedPitch(), lockedYaw, 0)
    if lockBlend >= 1 then
        return locked
    end
    local free = getFreeCameraAngles()
    if lockBlend <= 0 then
        return free
    end
    return LerpAngle(lockBlend * lockBlend * (3 - 2 * lockBlend), free, locked)
end

function ZM_GetScreenCameraAngles()
    return GetCameraAngles()
end

// Puts the cursor in front of the player on screen so re-locking does not snap their facing.
local function placeCursorInFront()
    local offset = math.rad(aimYaw - lockedYaw)
    cursorX = ScrW() * 0.5 - math.sin(offset) * cursorPlaceDistance
    cursorY = ScrH() * 0.5 - math.cos(offset) * cursorPlaceDistance
end

local function setCameraLocked(locked)
    if locked == cameraLocked then
        return
    end
    cameraLocked = locked
    if locked then
        cursorX = nil
    else
        modelYaw = aimYaw
    end
end

hook.Add("Think", "ZM.CameraLockToggle", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        entryCameraUntil = 0
        arrivalCameraRiseDuration = 0
        arrivalCameraRise = 1
        exitCameraDuration = 0
        predictedWalk = nil
        shoulderCursorActive = false
        shoulderAimActive = false
        aimPitch = 0
        cursorX = nil
    end
    local inDen = isInDenCamera(ply)
    if lastDenCameraState == nil then
        denCameraBlend = inDen and 1 or 0
    elseif lastDenCameraState and not inDen and IsValid(ply) then
        modelYaw = ply:EyeAngles().y
        aimYaw = modelYaw
        cursorX = nil
    elseif inDen and not lastDenCameraState then
        cursorX = nil
        shoulderCursorActive = false
        shoulderAimActive = false
        aimPitch = 0
    end
    lastDenCameraState = inDen
    denCameraBlend = math.Approach(denCameraBlend, inDen and 1 or 0, FrameTime() * 3)

    local down = input.IsMouseDown(MOUSE_MIDDLE)
    if not inDen and down and not middleWasDown and not vgui.CursorVisible() and not gui.IsGameUIVisible() then
        setCameraLocked(not cameraLocked)
    end
    middleWasDown = down
    lockBlend = math.Approach(lockBlend, cameraLocked and 1 or 0, FrameTime() * lockBlendSpeed)
    if shoulderCursorActive then
        modelPitch = Lerp(1 - math.exp(-10 * FrameTime()), modelPitch, math.Clamp(modelPitch, shoulderMinPitch, shoulderMaxPitch))
    end
end)

// Faces the player toward the point under the cursor on the horizontal plane through their centre of mass.
local function updateAimFromCursor(ply)
    if not lastViewOrigin then
        return
    end
    local direction = gui.ScreenToVector(cursorX, cursorY)
    if direction.z > -0.01 then
        return
    end
    local center = ply:WorldSpaceCenter()
    local point = lastViewOrigin + direction * ((center.z - lastViewOrigin.z) / direction.z)
    local offset = point - center
    offset.z = 0
    if offset:LengthSqr() < 64 then
        return
    end
    aimYaw = offset:Angle().y
end

// Converts screen-relative WASD input (W = up the screen) into moves relative to the player's facing.
local function applyScreenRelativeMovement(cmd, screenYaw)
    local forward, side = cmd:GetForwardMove(), cmd:GetSideMove()
    if forward == 0 and side == 0 then
        return
    end
    local screen = Angle(0, screenYaw or lockedYaw, 0)
    local wish = screen:Forward() * forward + screen:Right() * side
    local facing = Angle(0, aimYaw, 0)
    cmd:SetForwardMove(wish:Dot(facing:Forward()))
    cmd:SetSideMove(wish:Dot(facing:Right()))
end

local aimEnemyClasses = { "zn_walker_zombie", "zn_boss_zombie" }
local aimHeadRadius = 14
local aimHeadDrop = 7
local aimDepthSpeed = 14
local aimDepthRange = 32768
local smoothedAimDepth

// NaN fails every comparison, so one bad trace would otherwise poison the smoothed aim permanently.
local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
// Depth along the camera ray of the nearest enemy head the ray passes close to. The head is estimated from the
// collision hull (bone reads outside rendering are not allowed on NextBots), so crawlers use their low hull.
local function nearestHeadDepth(origin, direction, limit)
    local best
    for _, class in ipairs(aimEnemyClasses) do
        for _, enemy in ipairs(ents.FindByClass(class)) do
            if not enemy:IsDormant() then
                local head = enemy:GetPos()
                head.z = head.z + enemy:OBBMaxs().z - aimHeadDrop
                local depth = (head - origin):Dot(direction)
                if depth > 0 and depth < limit and (not best or depth < best) and
                    (origin + direction * depth):DistToSqr(head) <= aimHeadRadius * aimHeadRadius then
                    best = depth
                end
            end
        end
    end
    return best
end

// The gun fires from the body, not the camera, so its aim converges on a point along the camera ray. That depth
// is stabilised: a head the ray narrowly misses keeps its depth (aiming up stays on the head instead of dropping
// onto the body behind a far wall), and depth changes ease in rather than snapping between near and far hits.
local function updateShoulderAim(ply, screenX, screenY)
    if not lastViewOrigin then return end
    local direction = gui.ScreenToVector(screenX, screenY)
    local trace = util.TraceLine({
        start = lastViewOrigin,
        endpos = lastViewOrigin + direction * aimDepthRange,
        filter = ply,
        mask = MASK_SHOT
    })
    local depth = trace.Fraction * aimDepthRange
    if not isFiniteNumber(depth) then return end
    local headDepth = nearestHeadDepth(lastViewOrigin, direction, depth + 48)
    if headDepth and not (trace.HitGroup == HITGROUP_HEAD and IsValid(trace.Entity)) then
        depth = headDepth
    end
    if not isFiniteNumber(smoothedAimDepth) or CurTime() < aimTransitionUntil then
        smoothedAimDepth = depth
    else
        smoothedAimDepth = Lerp(1 - math.exp(-aimDepthSpeed * FrameTime()), smoothedAimDepth, depth)
    end
    local offset = lastViewOrigin + direction * smoothedAimDepth - ply:WorldSpaceCenter()
    if offset:LengthSqr() < 64 then return end
    local target = offset:Angle()
    if not isFiniteNumber(target.p) or not isFiniteNumber(target.y) then return end
    local blend = 1 - math.exp(-18 * FrameTime())
    if not isFiniteNumber(aimYaw) or not isFiniteNumber(aimPitch) then
        aimYaw, aimPitch = target.y, math.Clamp(math.NormalizeAngle(target.p), -89, 89)
    end
    aimYaw = math.NormalizeAngle(aimYaw + math.AngleDifference(target.y, aimYaw) * blend)
    aimPitch = Lerp(blend, aimPitch, math.Clamp(math.NormalizeAngle(target.p), -89, 89))
end

// The scroll wheel zooms the camera, so its default weapon-cycling binds are blocked; number keys still select weapons.
local blockedScrollBinds = { invprev = true, invnext = true }

hook.Add("PlayerBindPress", "ZM.CameraBlockScrollWeaponSwitch", function(_, bind)
    local command = string.lower(bind or "")
    if not isInDenCamera(LocalPlayer()) and (blockedScrollBinds[command] or shoulderAimActive and command == "+zoom") then
        return true
    end
end)

// Consumes mouse and wheel input for the active camera mode.
hook.Add("CreateMove", "ZM.RotateThirdPersonModel", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    if isInDenCamera(ply) then
        return
    end
    if vgui.CursorVisible() or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus())
        or ZM_LauncherMenu and ZM_LauncherMenu.Active then return end

    targetDist = math.Clamp(targetDist - cmd:GetMouseWheel() * zoomStep, minDist, maxDist)
    local onShoulder = not cameraLocked and getShoulderWeight() > 0.5
    if onShoulder ~= shoulderAimActive then
        shoulderAimActive = onShoulder
        aimTransitionUntil = CurTime() + 0.4
    end
    local wantsShoulderCursor = onShoulder and input.IsKeyDown(KEY_Z)
    if wantsShoulderCursor ~= shoulderCursorActive then
        shoulderCursorActive = wantsShoulderCursor
        aimTransitionUntil = CurTime() + 0.4
        if shoulderCursorActive then
            local screen = (ply:WorldSpaceCenter() + Angle(aimPitch, aimYaw, 0):Forward() * 2048):ToScreen()
            cursorX = screen.visible and math.Clamp(screen.x, cursorMargin, ScrW() - cursorMargin) or ScrW() * 0.5
            cursorY = screen.visible and math.Clamp(screen.y, cursorMargin, ScrH() - cursorMargin) or ScrH() * 0.5
        else
            cursorX = nil
        end
    end

    if shoulderCursorActive then
        if not cursorX then
            cursorX, cursorY = ScrW() * 0.5, ScrH() * 0.5
        end
        if CurTime() >= entryCameraUntil and not isWalkActive(predictedWalk) then
            cursorX = math.Clamp(cursorX + cmd:GetMouseX() * sensitivity, cursorMargin, ScrW() - cursorMargin)
            cursorY = math.Clamp(cursorY + cmd:GetMouseY() * sensitivity, cursorMargin, ScrH() - cursorMargin)
            updateShoulderAim(ply, cursorX, cursorY)
        end
        cmd:SetViewAngles(Angle(aimPitch, aimYaw, 0))
        ply:SetRenderAngles(Angle(0, aimYaw, 0))
        applyScreenRelativeMovement(cmd, modelYaw)
        return
    end

    if cameraLocked then
        if not cursorX then
            placeCursorInFront()
        end
        if not isWalkActive(predictedWalk) then
            cursorX = math.Clamp(cursorX + cmd:GetMouseX() * sensitivity, cursorMargin, ScrW() - cursorMargin)
            cursorY = math.Clamp(cursorY + cmd:GetMouseY() * sensitivity, cursorMargin, ScrH() - cursorMargin)
        end
        if CurTime() >= entryCameraUntil then
            local previousYaw = aimYaw
            updateAimFromCursor(ply)
            if CurTime() < aimTransitionUntil then
                aimYaw = math.NormalizeAngle(previousYaw + math.AngleDifference(aimYaw, previousYaw) * (1 - math.exp(-18 * FrameTime())))
            end
        end
        aimPitch = CurTime() < aimTransitionUntil and Lerp(1 - math.exp(-18 * FrameTime()), aimPitch, 0) or 0
        local aimAngles = Angle(aimPitch, aimYaw, 0)
        cmd:SetViewAngles(aimAngles)
        ply:SetRenderAngles(Angle(0, aimYaw, 0))
        applyScreenRelativeMovement(cmd)
        return
    end

    if CurTime() >= entryCameraUntil then
        local lookScale = freeLookScale * sensitivity
        local shoulderWeight = getShoulderWeight()
        local minimumPitch = shoulderMinPitch * shoulderWeight
        local maximumPitch = Lerp(shoulderWeight, 89, shoulderMaxPitch)
        local pitchDirection = invertY[onShoulder and "shoulder" or "orbit"] and -1 or 1
        modelYaw = modelYaw - cmd:GetMouseX() * lookScale
        modelPitch = math.Clamp(modelPitch + pitchDirection * cmd:GetMouseY() * lookScale, minimumPitch, maximumPitch)
    end
    if onShoulder and CurTime() >= entryCameraUntil then
        updateShoulderAim(ply, ScrW() * 0.5, ScrH() * 0.5)
    else
        local blend = CurTime() < aimTransitionUntil and (1 - math.exp(-18 * FrameTime())) or 1
        aimYaw = math.NormalizeAngle(aimYaw + math.AngleDifference(modelYaw, aimYaw) * blend)
        aimPitch = Lerp(blend, aimPitch, 0)
    end

    cmd:SetViewAngles(Angle(aimPitch, aimYaw, 0))
    ply:SetRenderAngles(Angle(0, aimYaw, 0))
    applyScreenRelativeMovement(cmd, modelYaw)
end)

// Positions the camera with a hull trace so walls cannot clip through the view.
local cameraHullMins = Vector(-4, -4, -4)
local cameraHullMaxs = Vector(4, 4, 4)
local cameraTraceResult = {}
local cameraTrace = { mins = cameraHullMins, maxs = cameraHullMaxs, output = cameraTraceResult }

hook.Add("CalcView", "ZM.CustomThirdPersonView", function(ply, pos, angles, fov)
    lockedCameraObstructed = false
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local inDen = isInDenCamera(ply)
    local view = {}
    local cameraAngles = GetCameraAngles()

    dist = Lerp(math.min(FrameTime() * 10, 1), dist, targetDist)

    local orbitPos = ply:EyePos() - (cameraAngles:Forward() * dist) + (cameraAngles:Up() * up)
    local cameraEndPos = orbitPos
    local shoulderWeight = getShoulderWeight()
    if shoulderWeight > 0 then
        local facing = Angle(0, cameraAngles.y, 0)
        local shoulderPos = ply:EyePos() + facing:Right() * shoulderRight - facing:Forward() * shoulderBack + Vector(0, 0, shoulderUp)
        cameraEndPos = LerpVector(shoulderWeight * shoulderWeight * (3 - 2 * shoulderWeight), orbitPos, shoulderPos)
    end

    local eyePos = ply:EyePos()
    cameraTrace.start = eyePos
    cameraTrace.endpos = cameraEndPos
    cameraTrace.filter = ply
    util.TraceHull(cameraTrace)
    local tr = cameraTraceResult

    lockedCameraObstructed = tr.Hit
    local collisionAwareOrigin = LerpVector(lockBlend, tr.HitPos, cameraEndPos)
    view.origin = LerpVector(denCameraBlend, collisionAwareOrigin, ply:EyePos())
    if arrivalCameraRiseDuration > 0 then
        local progress = math.Clamp((CurTime() - arrivalCameraRiseStart) / arrivalCameraRiseDuration, 0, 1)
        arrivalCameraRise = progress * progress * (3 - 2 * progress)
        view.origin = LerpVector(arrivalCameraRise, ply:EyePos(), view.origin)
        if progress >= 1 then
            arrivalCameraRiseDuration = 0
        end
    end
    if exitCameraDuration > 0 then
        local progress = math.Clamp((CurTime() - exitCameraStart) / exitCameraDuration, 0, 1)
        local rise = progress * progress * (3 - 2 * progress)
        view.origin = view.origin + Vector(0, 0, rise * exitCameraHeight * (1 - denCameraBlend))
    end
    view.angles = LerpAngle(denCameraBlend, cameraAngles, angles)
    view.fov = fov
    view.drawplayer = not inDen and denCameraBlend < 0.5 and arrivalCameraRise >= 0.25
    lastViewOrigin = view.origin

    return view
end)

hook.Add("PreDrawHalos", "ZM.CameraOcclusionHalo", function()
    if ZM_WorldMap and ZM_WorldMap.Capturing then return end
    local ply = LocalPlayer()
    if cameraLocked and lockBlend > 0.95 and lockedCameraObstructed
        and denCameraBlend < 0.5 and IsValid(ply) and ply:Alive() then
        halo.Add({ ply }, Color(246, 210, 48), 2, 2, 1, true, true)
    end
end)

// The camera is always external enough that the local player model should be rendered.
hook.Add("ShouldDrawLocalPlayer", "ZM.DrawPlayer", function(ply)
    if ZM_WorldMap and ZM_WorldMap.Capturing then return false end
    return not isInDenCamera(ply) and denCameraBlend < 0.5 and arrivalCameraRise >= 0.25
end)
