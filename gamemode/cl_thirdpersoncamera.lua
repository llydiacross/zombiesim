// Third-person camera state. targetDist changes immediately; dist eases toward it each frame.
local dist = 100
local targetDist = 100
local minDist = 50
local maxDist = 500
local up = 20   
local zoomStep = 25
local flipCamera = true

// Mouse movement rotates the model, while the camera stays behind it.
local modelYaw = 0
local modelPitch = 45
local entryCameraUntil = 0

net.Receive("ZM.PlayerTransitionEntry", function()
    modelYaw = net.ReadFloat()
    entryCameraUntil = CurTime() + math.max(0, net.ReadFloat())
end)

// The closest zoom level flips the camera in front of the player and hides HUD reticles.
function ZM_IsSelfieCamera()
    return flipCamera and targetDist <= minDist
end

// Produces camera angles for ordinary behind-the-player and selfie-camera modes.
local function GetCameraAngles()
    if flipCamera and targetDist <= minDist then
        return Angle(-modelPitch, modelYaw + 180, 0)
    end

    return Angle(modelPitch, modelYaw, 0)
end

// Consumes mouse and wheel input to rotate the model and choose the current third-person view.
hook.Add("CreateMove", "ZM.RotateThirdPersonModel", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    targetDist = math.Clamp(targetDist - cmd:GetMouseWheel() * zoomStep, minDist, maxDist)
    if CurTime() >= entryCameraUntil then
        modelYaw = modelYaw - cmd:GetMouseX() * 0.022
        modelPitch = math.Clamp(modelPitch - cmd:GetMouseY() * 0.022, 0, 89)
    end

    local modelAngles = Angle(modelPitch, modelYaw, 0)
    local cameraAngles = GetCameraAngles()

    cmd:SetViewAngles(cameraAngles)
    ply:SetRenderAngles(modelAngles)
end)

// Positions the camera with a hull trace so walls cannot clip through the view.
hook.Add("CalcView", "ZM.CustomThirdPersonView", function(ply, pos, angles, fov)
    if not IsValid(ply) or not ply:Alive() then return end

    local view = {}
    local modelAngles = ply:GetRenderAngles()
    local cameraAngles = GetCameraAngles()
    dist = Lerp(math.min(FrameTime() * 10, 1), dist, targetDist)
    local cameraEndPos

    if flipCamera and targetDist <= minDist then
        cameraEndPos = ply:EyePos() + (modelAngles:Forward() * dist) + (modelAngles:Up() * up)
    else
        cameraEndPos = ply:EyePos() - (cameraAngles:Forward() * dist) + (cameraAngles:Up() * up)
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

    return view
end)

// The camera is always external enough that the local player model should be rendered.
hook.Add("ShouldDrawLocalPlayer", "ZM.DrawPlayer", function(ply)
    return true
end)
