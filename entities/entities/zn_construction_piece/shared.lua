// A player-built construction piece (Alpha 3.4 prototype). Its origin is the bottom centre and its collision is an
// axis-aligned box from ZM_Construction.PieceBounds, so walls encode their yaw in PieceYaw rather than angles.
// Unpaid blueprints are non-solid wireframes; Use (E) contributes build progress through ZM_Construction.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Construction Piece"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "PieceKind")
	self:NetworkVar("Int", 0, "PieceYaw")
	self:NetworkVar("Float", 0, "Progress")
	self:NetworkVar("Float", 1, "CompletedAt")
	self:NetworkVar("Bool", 0, "Complete")
	self:NetworkVar("Bool", 1, "Paid")
end

function ENT:LocalBounds()
	local minX, minY, minZ, maxX, maxY, maxZ = ZM_Construction.PieceBounds(self:GetPieceKind(), self:GetPieceYaw())
	if not minX then return nil end
	return Vector(minX, minY, minZ), Vector(maxX, maxY, maxZ)
end
