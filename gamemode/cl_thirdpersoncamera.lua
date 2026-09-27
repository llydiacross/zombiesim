// Third-person camera. The default is a locked top-down view with a fixed north-up yaw, where the player faces
// a virtual aim cursor and WASD moves relative to the screen. Middle click toggles the free orbit camera, and
// the view glides between the two. In the free camera, zooming fully in moves onto the right shoulder.
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
local cursorX, cursorY
local lastViewOrigin
local middleWasDown = false

// Mouse sensitivity scales cursor movement in the locked camera and look speed in the free camera.
local sensitivityCookie = "zombiesim_mouse_sensitivity"
local defaultSensitivity = 0.5
local minimumSensitivity = 0.1
local maximumSensitivity = 2
local freeLookScale = 0.022 / defaultSensitivity
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
    cursorX = nil
    entryCameraUntil = CurTime() + math.max(0, net.ReadFloat())
end)

function ZM_IsCameraLocked()
    return cameraLocked
end

// Returns 0..1: how far the free camera has moved onto the player's shoulder (0 while locked).
local function getShoulderWeight()
    local zoom = math.Clamp((dist - minDist) / shoulderZone, 0, 1)
    return (1 - zoom) * (1 - lockBlend)
end

// Returns the aim cursor's screen position while the camera is locked.
function ZM_GetAimCursor()
    if not cameraLocked or not cursorX then
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
    local down = input.IsMouseDown(MOUSE_MIDDLE)
    if down and not middleWasDown and not vgui.CursorVisible() and not gui.IsGameUIVisible() then
        setCameraLocked(not cameraLocked)
    end
    middleWasDown = down
    lockBlend = math.Approach(lockBlend, cameraLocked and 1 or 0, FrameTime() * lockBlendSpeed)
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
local function applyScreenRelativeMovement(cmd)
    local forward, side = cmd:GetForwardMove(), cmd:GetSideMove()
    if forward == 0 and side == 0 then
        return
    end
    local screen = Angle(0, lockedYaw, 0)
    local wish = screen:Forward() * forward + screen:Right() * side
    local facing = Angle(0, aimYaw, 0)
    cmd:SetForwardMove(wish:Dot(facing:Forward()))
    cmd:SetSideMove(wish:Dot(facing:Right()))
end

// The scroll wheel zooms the camera, so its default weapon-cycling binds are blocked; number keys still select weapons.
local blockedScrollBinds = { invprev = true, invnext = true }

hook.Add("PlayerBindPress", "ZM.CameraBlockScrollWeaponSwitch", function(_, bind)
    if blockedScrollBinds[string.lower(bind or "")] then
        return true
    end
end)

// Consumes mouse and wheel input for the active camera mode.
hook.Add("CreateMove", "ZM.RotateThirdPersonModel", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    targetDist = math.Clamp(targetDist - cmd:GetMouseWheel() * zoomStep, minDist, maxDist)

    if cameraLocked then
        if not cursorX then
            placeCursorInFront()
        end
        cursorX = math.Clamp(cursorX + cmd:GetMouseX() * sensitivity, cursorMargin, ScrW() - cursorMargin)
        cursorY = math.Clamp(cursorY + cmd:GetMouseY() * sensitivity, cursorMargin, ScrH() - cursorMargin)
        if CurTime() >= entryCameraUntil then
            updateAimFromCursor(ply)
        end
        local aimAngles = Angle(0, aimYaw, 0)
        cmd:SetViewAngles(aimAngles)
        ply:SetRenderAngles(aimAngles)
        applyScreenRelativeMovement(cmd)
        return
    end

    if CurTime() >= entryCameraUntil then
        local lookScale = freeLookScale * sensitivity
        local shoulderWeight = getShoulderWeight()
        local minimumPitch = shoulderMinPitch * shoulderWeight
        local maximumPitch = Lerp(shoulderWeight, 89, shoulderMaxPitch)
        local onShoulder = shoulderWeight > 0.5
        local pitchDirection = invertY[onShoulder and "shoulder" or "orbit"] and -1 or 1
        modelYaw = modelYaw - cmd:GetMouseX() * lookScale
        modelPitch = math.Clamp(modelPitch + pitchDirection * cmd:GetMouseY() * lookScale, minimumPitch, maximumPitch)
    end
    aimYaw = modelYaw

    local modelAngles = Angle(0, modelYaw, 0)
    local cameraAngles = GetCameraAngles()

    cmd:SetViewAngles(cameraAngles)
    ply:SetRenderAngles(modelAngles)
end)

// Positions the camera with a hull trace so walls cannot clip through the view.
hook.Add("CalcView", "ZM.CustomThirdPersonView", function(ply, pos, angles, fov)
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    if not IsValid(ply) or not ply:Alive() then return end

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

    local tr = util.TraceHull({
        start = ply:EyePos(),
        endpos = cameraEndPos,
        filter = ply,
        mins = Vector(-4, -4, -4),
        maxs = Vector(4, 4, 4),
    })

    view.origin = tr.HitPos
    view.angles = cameraAngles
    view.fov = fov
    view.drawplayer = true -- Make sure the player model is visible
    lastViewOrigin = view.origin

    return view
end)

// The camera is always external enough that the local player model should be rendered.
hook.Add("ShouldDrawLocalPlayer", "ZM.DrawPlayer", function(ply)
    return true
end)
