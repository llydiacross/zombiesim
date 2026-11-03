include("shared.lua")

local fadeSeconds = 1
local wireColor = Color(90, 200, 255, 220)
local deleteColor = Color(255, 55, 55, 240)
// Each damage stage darkens the wood a little more; damage marks use the mounted wood impact decals.
local stageDarkening = 0.12
local damageTextures = { "decals/wood/shot1", "decals/wood/shot2", "decals/wood/shot3", "decals/wood/shot4", "decals/wood/shot5" }
local materials = ZM_ConstructionPieceMaterials or {}
ZM_ConstructionPieceMaterials = materials

local function pieceMaterial(kind, translucent)
	local definition = ZM_Construction.Pieces[kind]
	local category = definition and definition.material or "floor"
	local key = category .. (translucent and "_translucent" or "_opaque")
	if materials[key] then return materials[key] end
	local texture = category == "wall" and "wood/woodwall009a" or "wood/woodfloor005a"
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

local function updateRenderBounds(self)
	local kind, yaw = self:GetPieceKind(), self:GetPieceYaw()
	if self.ZM_BoundsKind == kind and self.ZM_BoundsYaw == yaw then return end
	local mins, maxs = self:LocalBounds()
	if mins then
		self:SetRenderBounds(mins, maxs)
		self.ZM_BoundsKind, self.ZM_BoundsYaw = kind, yaw
	end
end

function ENT:Initialize()
	updateRenderBounds(self)
end

function ENT:Think()
	updateRenderBounds(self)
end

// Baked lighting at the piece, so the unlit texture still matches the area's brightness.
local function shadedColor(position, alpha)
	local light = render.ComputeLighting(position, Vector(0, 0, 1))
	local scale = math.Clamp(math.max(light.x, light.y, light.z) * 1.6, 0.15, 1)
	return Color(255 * scale, 255 * scale, 255 * scale, alpha)
end

local function selectionColor(entity, color)
	if ZM_Construction:PieceSelectedForDeletion(entity) then
		return Color(deleteColor.r, deleteColor.g, deleteColor.b, color.a)
	end
	return color
end

function ENT:Draw()
	if not self:GetComplete() then return end
	local fade = math.Clamp((CurTime() - self:GetCompletedAt()) / fadeSeconds, 0, 1)
	if fade < 1 then return end
	local mins, maxs = self:LocalBounds()
	if not mins then return end
	local origin = self:GetPos()
	local color = shadedColor(origin + Vector(0, 0, maxs.z * 0.5), 255)
	local darken = 1 - stageDarkening * ZM_Construction.DamageStage(self:GetWear())
	color.r, color.g, color.b = color.r * darken, color.g * darken, color.b * darken
	color = selectionColor(self, color)
	render.SetMaterial(pieceMaterial(self:GetPieceKind(), false))
	ZM_Construction.Geometry.DrawSolid(self:GetPieceKind(), self:GetPieceYaw(), origin, color)
end

// Small deterministic generator so mark placement is stable per piece without touching the global random state.
local function seededRandom(seed)
	local state = (math.floor(math.abs(seed)) * 7919 + 12345) % 2147483647
	if state == 0 then state = 1 end
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

// Damage-mark candidates spread over the piece's faces by area: local offset, outward normal, size and rotation.
local function buildDamageMarks(kind, yaw, seed)
	local parts = ZM_Construction.GetParts(kind, yaw)
	if not parts then return {} end
	local triangles, totalArea = {}, 0
	for _, part in ipairs(parts) do
		local centroid = Vector(0, 0, 0)
		for _, vertex in ipairs(part.vertices) do
			centroid:Add(Vector(vertex[1], vertex[2], vertex[3]))
		end
		centroid:Div(math.max(1, #part.vertices))
		for _, face in ipairs(part.faces) do
			local first = part.vertices[face[1]]
			local a = Vector(first[1], first[2], first[3])
			for index = 2, #face - 1 do
				local second, third = part.vertices[face[index]], part.vertices[face[index + 1]]
				local b, c = Vector(second[1], second[2], second[3]), Vector(third[1], third[2], third[3])
				local cross = (b - a):Cross(c - a)
				local area = cross:Length() * 0.5
				if area > 1 then
					local normal = cross:GetNormalized()
					if normal:Dot((a + b + c) / 3 - centroid) < 0 then normal:Mul(-1) end
					totalArea = totalArea + area
					triangles[#triangles + 1] = { a = a, b = b, c = c, normal = normal, cumulative = totalArea }
				end
			end
		end
	end
	if #triangles == 0 then return {} end
	local random = seededRandom(seed)
	local perStage = math.Clamp(math.ceil(totalArea / 6000), 2, 5)
	local marks = {}
	for index = 1, perStage * ZM_Construction.DamageStages do
		local pick = random() * totalArea
		local chosen = triangles[#triangles]
		for _, triangle in ipairs(triangles) do
			if pick <= triangle.cumulative then chosen = triangle break end
		end
		local u, v = random(), random()
		if u + v > 1 then u, v = 1 - u, 1 - v end
		local stage = math.ceil(index / perStage)
		marks[index] = {
			offset = chosen.a + (chosen.b - chosen.a) * u + (chosen.c - chosen.a) * v + chosen.normal * 0.4,
			normal = chosen.normal,
			stage = stage,
			size = 10 + stage * 4 + random() * 8,
			rotation = random() * 360,
			material = math.floor(random() * #damageTextures) + 1
		}
	end
	return marks
end

local function damageMaterial(index)
	local key = "damage_" .. index
	if materials[key] then return materials[key] end
	materials[key] = CreateMaterial("zombiesim_construction_damage_" .. index .. "_v1", "UnlitGeneric", {
		["$basetexture"] = damageTextures[index],
		["$translucent"] = 1,
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1
	})
	return materials[key]
end

function ENT:DrawDamageMarks(origin, lightPosition)
	local stage = ZM_Construction.DamageStage(self:GetWear())
	if stage <= 0 then return end
	local kind, yaw = self:GetPieceKind(), self:GetPieceYaw()
	if self.ZM_MarksKind ~= kind or self.ZM_MarksYaw ~= yaw then
		self.ZM_Marks = buildDamageMarks(kind, yaw, self:EntIndex())
		self.ZM_MarksKind, self.ZM_MarksYaw = kind, yaw
	end
	local color = shadedColor(lightPosition, 235)
	for _, mark in ipairs(self.ZM_Marks) do
		if mark.stage <= stage then
			render.SetMaterial(damageMaterial(mark.material))
			render.DrawQuadEasy(origin + mark.offset, mark.normal, mark.size, mark.size, color, mark.rotation)
		end
	end
end

function ENT:DrawTranslucent()
	local mins, maxs = self:LocalBounds()
	if not mins then return end
	local origin = self:GetPos()
	if self:GetComplete() then
		local fade = math.Clamp((CurTime() - self:GetCompletedAt()) / fadeSeconds, 0, 1)
		if fade >= 1 then
			self:DrawDamageMarks(origin, origin + Vector(0, 0, maxs.z * 0.5))
			return
		end
		render.SetMaterial(pieceMaterial(self:GetPieceKind(), true))
		ZM_Construction.Geometry.DrawSolid(self:GetPieceKind(), self:GetPieceYaw(), origin,
			selectionColor(self, shadedColor(origin + Vector(0, 0, maxs.z * 0.5), 120 + 135 * fade)))
		return
	end
	render.SetColorMaterial()
	ZM_Construction.Geometry.DrawWire(self:GetPieceKind(), self:GetPieceYaw(), origin, selectionColor(self, wireColor))
	local progress = math.Clamp(self:GetProgress(), 0, 1)
	if progress > 0 then
		render.SetMaterial(pieceMaterial(self:GetPieceKind(), true))
		ZM_Construction.Geometry.DrawSolid(self:GetPieceKind(), self:GetPieceYaw(), origin,
			selectionColor(self, shadedColor(origin, 170)), progress)
	end
end

// Wood splinters at each zombie hit. Emitters are created per hit and finished at once; a rate cap bounds crowds.
local splinterMaterials = { "effects/fleck_wood1", "effects/fleck_wood2" }
local splinterWindowAt, splinterWindowCount = 0, 0
local maxSplintersPerSecond = 24

net.Receive("ZM.Construction.Hit", function()
	local position = net.ReadVector()
	local normal = net.ReadNormal()
	local now = CurTime()
	if now >= splinterWindowAt then
		splinterWindowAt, splinterWindowCount = now + 1, 0
	end
	if splinterWindowCount >= maxSplintersPerSecond then return end
	if EyePos():DistToSqr(position) > 2048 * 2048 then return end
	splinterWindowCount = splinterWindowCount + 1
	local emitter = ParticleEmitter(position)
	if not emitter then return end
	for _ = 1, 6 do
		local particle = emitter:Add(splinterMaterials[math.random(#splinterMaterials)], position + normal * 2)
		if particle then
			particle:SetVelocity((normal + VectorRand() * 0.6):GetNormalized() * math.Rand(60, 140))
			particle:SetGravity(Vector(0, 0, -500))
			particle:SetDieTime(math.Rand(0.8, 1.4))
			particle:SetStartAlpha(255)
			particle:SetEndAlpha(0)
			particle:SetStartSize(math.Rand(1.5, 3))
			particle:SetEndSize(1)
			particle:SetRoll(math.Rand(0, 360))
			particle:SetRollDelta(math.Rand(-6, 6))
			particle:SetColor(170, 130, 90)
			particle:SetCollide(true)
			particle:SetBounce(0.3)
		end
	end
	emitter:Finish()
end)

// Diagnostics for the construction client status report.
function ZM_ConstructionPieceMaterialStatus()
	local report = {}
	for index = 1, #damageTextures do
		local material = damageMaterial(index)
		local texture = material:GetTexture("$basetexture")
		report["damage_" .. index] = {
			error = material:IsError(),
			shader = material:GetShader(),
			textureWidth = texture and texture:Width() or 0
		}
	end
	for _, kind in ipairs(ZM_Construction.PieceOrder) do
		local material = pieceMaterial(kind, false)
		local texture = material:GetTexture("$basetexture")
		local translucent = pieceMaterial(kind, true)
		local translucentTexture = translucent:GetTexture("$basetexture")
		report[kind] = {
			error = material:IsError(),
			shader = material:GetShader(),
			textureWidth = texture and texture:Width() or 0,
			translucentError = translucent:IsError(),
			translucentShader = translucent:GetShader(),
			translucentTextureWidth = translucentTexture and translucentTexture:Width() or 0
		}
	end
	return report
end
