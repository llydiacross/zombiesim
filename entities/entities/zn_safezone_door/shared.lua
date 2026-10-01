ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Safe-Zone Door"
ENT.Spawnable = false
ENT.AdminOnly = false

// Hammer keyvalues are kept raw for ZM_SafeZoneDoors (role, use_radius, zm_instance_transformed).
function ENT:KeyValue(key, value)
    self.ZM_Config = self.ZM_Config or {}
    self.ZM_Config[string.lower(key)] = value
end

// An invisible, non-solid networked marker so the client can show the nearby-door prompt.
function ENT:Initialize()
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
end

function ENT:Draw()
end

if SERVER then
    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end
end
