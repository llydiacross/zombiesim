include("shared.lua")

local fadeSeconds = 1
local wireColor = Color(90, 200, 255, 220)
local materials = ZM_ConstructionPieceMaterials or {}
ZM_ConstructionPieceMaterials = materials

local function pieceMaterial(kind, translucent)
	local key = kind .. (translucent and "_translucent" or "_opaque")
	if materials[key] then return materials[key] end
	local texture = kind == "wall" and "wood/woodwall009a" or "wood/woodfloor005a"
	local keyValues = {
		["$basetexture"] = texture,
		["$vertexcolor"] = 1,
		["$model"] = 1
	}
	if translucent then
		keyValues["$vertexalpha"] = 1
		keyValues["$translucent"] = 1
	end
	materials[key] = CreateMaterial("zombiesim_construction_" .. key .. "_v1", "UnlitGeneric", keyValues)
	return materials[key]
end

function ENT:Initialize()
	local mins, maxs = self:LocalBounds()
	if mins then self:SetRenderBounds(mins, maxs) end
end

// Baked lighting at the piece, so the unlit texture still matches the area's brightness.
local function shadedColor(position, alpha)
	local light = render.ComputeLighting(position, Vector(0, 0, 1))
	local scale = math.Clamp(math.max(light.x, light.y, light.z) * 1.6, 0.15, 1)
	return Color(255 * scale, 255 * scale, 255 * scale, alpha)
end

function ENT:Draw()
	if not self:GetComplete() then return end
	local fade = math.Clamp((CurTime() - self:GetCompletedAt()) / fadeSeconds, 0, 1)
	if fade < 1 then return end
	local mins, maxs = self:LocalBounds()
	if not mins then return end
	local origin = self:GetPos()
	render.SetMaterial(pieceMaterial(self:GetPieceKind(), false))
	render.DrawBox(origin, angle_zero, mins, maxs, shadedColor(origin + Vector(0, 0, maxs.z * 0.5), 255))
end

function ENT:DrawTranslucent()
	local mins, maxs = self:LocalBounds()
	if not mins then return end
	local origin = self:GetPos()
	if self:GetComplete() then
		local fade = math.Clamp((CurTime() - self:GetCompletedAt()) / fadeSeconds, 0, 1)
		if fade >= 1 then return end
		render.SetMaterial(pieceMaterial(self:GetPieceKind(), true))
		render.DrawBox(origin, angle_zero, mins, maxs, shadedColor(origin + Vector(0, 0, maxs.z * 0.5), 120 + 135 * fade))
		return
	end
	render.SetColorMaterial()
	render.DrawWireframeBox(origin, angle_zero, mins, maxs, wireColor, true)
	local progress = math.Clamp(self:GetProgress(), 0, 1)
	if progress > 0 then
		local filled = Vector(maxs.x, maxs.y, mins.z + (maxs.z - mins.z) * progress)
		render.SetMaterial(pieceMaterial(self:GetPieceKind(), true))
		render.DrawBox(origin, angle_zero, mins, filled, shadedColor(origin, 170))
	end
end

// Diagnostics for the construction client status report.
function ZM_ConstructionPieceMaterialStatus()
	local report = {}
	for _, kind in ipairs(ZM_Construction.PieceOrder) do
		local material = pieceMaterial(kind, false)
		local texture = material:GetTexture("$basetexture")
		report[kind] = {
			error = material:IsError(),
			textureWidth = texture and texture:Width() or 0
		}
	end
	return report
end
