AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(ZM_Construction.PieceModel)
    local mins, maxs = self:LocalBounds()
    if not mins then
        self:Remove()
        return
    end
    self:SetAngles(Angle(0, 0, 0))
    self:PhysicsInitBox(mins, maxs)
    self:SetMoveType(MOVETYPE_NONE)
    local physics = self:GetPhysicsObject()
    if IsValid(physics) then physics:EnableMotion(false) end
    self:SetCollisionGroup(self:GetComplete() and COLLISION_GROUP_NONE or COLLISION_GROUP_WORLD)
    self:SetUseType(CONTINUOUS_USE)
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
