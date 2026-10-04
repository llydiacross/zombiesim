ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Bank"
ENT.Category = "ZombieSim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.DefaultModel = "models/props_c17/cashregister01a.mdl"

function ENT:KeyValue(key, value)
    if string.lower(key) == "model" then
        self.ZM_Model = value
    end
end

function ENT:Initialize()
    if SERVER then
        local model = self.ZM_Model
        if type(model) == "string" and model ~= "" and not util.IsValidModel(model) then
            ErrorNoHalt("[ZombieSim] zn_bank has invalid model '" .. model .. "'; using its default.\n")
            model = nil
        end
        self:SetModel(type(model) == "string" and model ~= "" and model or self.DefaultModel)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local physics = self:GetPhysicsObject()
        if IsValid(physics) then
            physics:EnableMotion(false)
            physics:Sleep()
        end
    end
end

function ENT:Use(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:Alive() then return end
    if not ZM_BankService or not ZM_BankService:CheckAccess(playerEntity, self) then return end
    net.Start("ZM.Bank.Open")
        net.WriteUInt(self:EntIndex(), 16)
    net.Send(playerEntity)
end