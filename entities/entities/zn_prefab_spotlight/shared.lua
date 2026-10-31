ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Prefab Spotlight"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PrefabLightId")
    self:NetworkVar("Vector", 0, "LightColor")
    self:NetworkVar("Float", 0, "LightBrightness")
    self:NetworkVar("Float", 1, "LightFov")
    self:NetworkVar("Float", 2, "LightRange")
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
