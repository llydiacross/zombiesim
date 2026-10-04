ZM_RadiatedZombies = ZM_RadiatedZombies or {}
local Visuals = ZM_RadiatedZombies
local quality = CreateClientConVar("zombiesim_radiated_visuals", "2", true, false,
    "Radiated walker sheen and glowing eyes: 0 off, 1 reduced, 2 full.", 0, 2)
local sheen = CreateMaterial("zombiesim_radiated_sheen_v1", "VertexLitGeneric", {
    ["$basetexture"] = "models/debug/debugwhite",
    ["$model"] = "1",
    ["$additive"] = "1",
    ["$selfillum"] = "1",
    ["$color"] = "[0.025 0.11 0.015]",
    ["$envmap"] = "environment maps/water_wasteland05",
    ["$envmaptint"] = "[0.12 0.65 0.24]",
    ["$envmapfresnel"] = "1"
})
local eyeGlow = Material("sprites/light_glow02_add")
local eyeColor = Color(255, 12, 4)
local eyeCore = Color(255, 105, 70)
local sheenTint = Vector(0.12, 0.65, 0.24)
local attachmentCache = setmetatable({}, { __mode = "k" })
local candidates = {}
local maximumDistanceSquared = 1500 * 1500
local nextRefresh = 0
local sheenTexture = sheen:GetTexture("$basetexture")
local eyeTexture = eyeGlow:GetTexture("$basetexture")
local materialsAvailable = not sheen:IsError() and not eyeGlow:IsError()
    and sheenTexture ~= nil and sheenTexture:Width() > 0 and eyeTexture ~= nil and eyeTexture:Width() > 0
if not materialsAvailable then ErrorNoHalt("[ZombieSim] Radiated walker sheen or eye material is unavailable.\n") end

Visuals.DrawCount, Visuals.EyeCount = 0, 0

hook.Add("Think", "ZM.RadiatedZombies.Refresh", function()
    if CurTime() < nextRefresh then return end
    nextRefresh = CurTime() + 0.25
    table.Empty(candidates)
    local target = LocalPlayer()
    if quality:GetInt() <= 0 or not IsValid(target) then return end
    local origin = target:GetPos()
    for _, entity in ipairs(ents.FindByClass("zn_walker_zombie")) do
        if entity:GetNWBool("ZM_Radiated", false) and origin:DistToSqr(entity:GetPos()) <= maximumDistanceSquared then
            candidates[#candidates + 1] = entity
        end
    end
    table.sort(candidates, function(left, right)
        return origin:DistToSqr(left:GetPos()) < origin:DistToSqr(right:GetPos())
    end)
end)

local function drawEyes(entity)
    if bit.band(entity:GetNWInt("ZM_GoreSevered", 0), 8) ~= 0 then return end
    local model = entity:GetModel()
    local cached = attachmentCache[entity]
    if not cached or cached.model ~= model then
        cached = { model = model, index = entity:LookupAttachment("eyes") }
        attachmentCache[entity] = cached
        if cached.index <= 0 then
            ErrorNoHalt("[ZombieSim] Radiated walker has no eyes attachment: " .. tostring(model) .. "\n")
        end
    end
    if cached.index <= 0 then return end
    local eyes = entity:GetAttachment(cached.index)
    if not eyes then return end
    local scale = entity:GetModelScale()
    local center = eyes.Pos + eyes.Ang:Forward() * 0.8 * scale
    local side = eyes.Ang:Right() * 1.35 * scale
    render.SetMaterial(eyeGlow)
    render.DrawSprite(center + side, 2.4 * scale, 2.4 * scale, eyeColor)
    render.DrawSprite(center - side, 2.4 * scale, 2.4 * scale, eyeColor)
    render.DrawSprite(center + side, 0.65 * scale, 0.65 * scale, eyeCore)
    render.DrawSprite(center - side, 0.65 * scale, 0.65 * scale, eyeCore)
    Visuals.EyeCount = Visuals.EyeCount + 2
end

hook.Add("PostDrawTranslucentRenderables", "ZM.RadiatedZombies.Draw", function(depth, skybox)
    if depth or skybox or ZM_WorldMap and ZM_WorldMap.Capturing then return end
    Visuals.DrawCount, Visuals.EyeCount = 0, 0
    local detail = math.Clamp(quality:GetInt(), 0, 2)
    if detail == 0 or not materialsAvailable then return end
    local maximum = detail == 1 and 8 or 24
    sheenTint.z = 0.24 + 0.10 * math.sin(CurTime() * 0.7)
    sheen:SetVector("$envmaptint", sheenTint)
    for _, entity in ipairs(candidates) do
        if Visuals.DrawCount >= maximum then break end
        if IsValid(entity) and not entity:IsDormant() and not entity:GetNoDraw()
            and entity:GetNWBool("ZM_Radiated", false) then
            // Overlay the animated model without replacing its skin or severed-bone transforms.
            render.SetBlend(0.5)
            render.MaterialOverride(sheen)
            entity:DrawModel()
            render.MaterialOverride()
            render.SetBlend(1)
            Visuals.DrawCount = Visuals.DrawCount + 1
            drawEyes(entity)
        end
    end
end)

function Visuals:GetDiagnosticSnapshot()
    return {
        quality = quality:GetInt(), candidates = #candidates,
        drawn = self.DrawCount, eyes = self.EyeCount,
        maximumModels = quality:GetInt() == 1 and 8 or quality:GetInt() == 2 and 24 or 0,
        maximumDistance = 1500, materialsAvailable = materialsAvailable,
        sheenShader = sheen:GetShader(), eyeShader = eyeGlow:GetShader()
    }
end
