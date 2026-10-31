ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Prefab Particle"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PrefabParticleId")
    self:NetworkVar("String", 1, "ParticleEffectId")
end

if SERVER then
    function ENT:Initialize()
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
    end

    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end
end

if CLIENT then
    function ENT:Draw()
    end
end
