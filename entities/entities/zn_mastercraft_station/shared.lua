ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "ZombieSim Mastercrafting Station"
ENT.Category = "ZombieSim"
ENT.Spawnable = true
ENT.AdminOnly = false

function ENT:Initialize()
    if SERVER then
        self:SetModel("models/props_combine/combine_interface001.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local physics = self:GetPhysicsObject()
        if IsValid(physics) then
            physics:Wake()
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