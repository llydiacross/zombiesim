ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Den Stash"
ENT.Category = "ZombieSim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.DefaultModel = "models/props_junk/wood_crate001a.mdl"

function ENT:KeyValue(key, value)
    if string.lower(key) == "model" then
        self.ZM_Model = value
    end
end

function ENT:Initialize()
    if SERVER then
        local model = self.ZM_Model
        if type(model) == "string" and model ~= "" and not util.IsValidModel(model) then
            ErrorNoHalt("[ZombieSim] zn_den_stash has invalid model '" .. model .. "'; using its default.\n")
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
        else
            // A missing model has no collision, so traces (and +use) pass straight through it.
            ErrorNoHalt("[ZombieSim] " .. self:GetClass() .. " has no physics; model '" .. self:GetModel() .. "' may be missing.\n")
        end
    end
end

function ENT:Use(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:Alive() then return end
    if not ZM_InventoryService or not ZM_InventoryService:CanAccessStash(playerEntity) then return end
    net.Start("ZM.DenEntity.Open")
        net.WriteString(self:GetClass())
    net.Send(playerEntity)
end