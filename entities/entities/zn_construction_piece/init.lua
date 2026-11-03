AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(ZM_Construction.PieceModel)
    local mins, maxs = self:LocalBounds()
    if not mins then
        ErrorNoHalt("[ZombieSim] Construction piece has an unknown shape.\n")
        self:Remove()
        return
    end
    self:SetAngles(Angle(0, 0, 0))
    local parts = ZM_Construction.GetParts(self:GetPieceKind(), self:GetPieceYaw())
    local initialized
    if #parts == 1 and parts[1].box then
        initialized = self:PhysicsInitBox(mins, maxs)
        self:SetMoveType(MOVETYPE_NONE)
    else
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        initialized = self:PhysicsInitMultiConvex(ZM_Construction.CollisionVertices(self:GetPieceKind(), self:GetPieceYaw()))
        if initialized then
            self:SetCollisionBounds(mins, maxs)
            self:EnableCustomCollisions()
        end
    end
    if not initialized then
        ErrorNoHalt("[ZombieSim] Could not initialize construction collision for " .. self:GetPieceKind() .. ".\n")
        self:Remove()
        return
    end
    local physics = self:GetPhysicsObject()
    if not IsValid(physics) then
        ErrorNoHalt("[ZombieSim] Construction physics object is unavailable for " .. self:GetPieceKind() .. ".\n")
        self:Remove()
        return
    end
    physics:EnableMotion(false)
    self:SetCollisionGroup(self:GetComplete() and COLLISION_GROUP_NONE or COLLISION_GROUP_WORLD)
    self:SetUseType(CONTINUOUS_USE)
    self.ZM_CollisionReady = true
end

function ENT:Use(activator)
    if IsValid(activator) and activator:IsPlayer() then
        ZM_Construction:Contribute(activator, self, CurTime())
    end
end

function ENT:OnRemove()
    local registry = ZM_Construction.SlotRegistry
    if registry and self.ZM_SlotKey and registry[self.ZM_SlotKey] == self then
        registry[self.ZM_SlotKey] = nil
    end
end
