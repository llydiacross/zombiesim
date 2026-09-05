local dist = 100
local targetDist = 100
local minDist = 50
local maxDist = 500
local up = 20   
local zoomStep = 25
local flipCamera = true

-- Mouse movement rotates the model, while the camera stays behind it.
local modelYaw = 0
local modelPitch = 45

function ZM_IsSelfieCamera()
    return flipCamera and targetDist <= minDist
end

local function GetCameraAngles()
    if flipCamera and targetDist <= minDist then
        return Angle(-modelPitch, modelYaw + 180, 0)
    end

    return Angle(modelPitch, modelYaw, 0)
end

hook.Add("CreateMove", "ZM.RotateThirdPersonModel", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    targetDist = math.Clamp(targetDist - cmd:GetMouseWheel() * zoomStep, minDist, maxDist)
    modelYaw = modelYaw - cmd:GetMouseX() * 0.022
    modelPitch = math.Clamp(modelPitch - cmd:GetMouseY() * 0.022, 0, 89)

    local modelAngles = Angle(modelPitch, modelYaw, 0)
    local cameraAngles = GetCameraAngles()

    cmd:SetViewAngles(cameraAngles)
    ply:SetRenderAngles(modelAngles)
end)

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

hook.Add("ShouldDrawLocalPlayer", "ZM.DrawPlayer", function(ply)
    return true
end)
