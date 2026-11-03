// A player-built construction piece. Its origin is the bottom centre and its local geometry encodes PieceYaw.
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
	// 0 pristine .. 1 broken; the server owns health and derives this for the client damage stages.
	self:NetworkVar("Float", 2, "Wear")
	self:NetworkVar("Bool", 0, "Complete")
	self:NetworkVar("Bool", 1, "Paid")
end

function ENT:LocalBounds()
	local minX, minY, minZ, maxX, maxY, maxZ = ZM_Construction.PieceBounds(self:GetPieceKind(), self:GetPieceYaw())
	if not minX then return nil end
	return Vector(minX, minY, minZ), Vector(maxX, maxY, maxZ)
end
