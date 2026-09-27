ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Den NPC"
ENT.Category = "ZombieSim"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true
ENT.ZM_IsDenNpc = true

ENT.IdleSequences = { "idle_subtle", "lineidle01", "idle_all_01", "idle01" }

if SERVER then
    for name, method in pairs(ZM_DenNpcs and ZM_DenNpcs.ProviderMethods or {}) do
        ENT[name] = method
    end
end

// Hammer keyvalues arrive before Spawn; they are kept raw and resolved by ZM_DenNpcs against the live static data.
function ENT:KeyValue(key, value)
    self.ZM_Config = self.ZM_Config or {}
    self.ZM_Config[string.lower(key)] = value
end

function ENT:Initialize()
    if SERVER then
        self.ZM_Config = self.ZM_Config or {}
        local model = self.ZM_Config.model
        self:SetModel((type(model) == "string" and model ~= "") and model or ZM_DenNpcs.DefaultModel)
        self:SetSolid(SOLID_BBOX)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
        self:SetUseType(SIMPLE_USE)
        for _, name in ipairs(self.IdleSequences) do
            local sequence = self:LookupSequence(name)
            if sequence and sequence >= 0 then
                self:ResetSequence(sequence)
                break
            end
        end
        ZM_DenNpcs:Sync(self)
    end
end

function ENT:Think()
    self:NextThink(CurTime())
    return true
end

function ENT:Use(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:Alive() then return end
    if not ZM_InventoryService or not ZM_InventoryService:CanAccessStash(playerEntity) then return end
    local resolved = ZM_DenNpcs:Resolve(self)
    net.Start("ZM.DenNpc.Open")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteBool(resolved.trader ~= nil)
        net.WriteBool(resolved.job ~= nil and #resolved.services > 0)
    net.Send(playerEntity)
end
