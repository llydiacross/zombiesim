ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "ZombieSim Bank"
ENT.Category = "ZombieSim"
ENT.Spawnable = true
ENT.AdminOnly = false

function ENT:Initialize()
    if SERVER then
        self:SetModel("models/props_c17/cashregister01a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local physics = self:GetPhysicsObject()
        if IsValid(physics) then physics:Wake() end
    end
end

function ENT:Use(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:Alive() then return end
    if not ZM_InventoryService or not ZM_InventoryService:CanAccessStash(playerEntity) then return end
    local deposited, depositError = ZM_InventoryService:DepositCashBundles(playerEntity)
    if not deposited then
        playerEntity:ChatPrint("[Bank] " .. tostring(depositError))
        return
    end
    playerEntity:ChatPrint("[Bank] Deposited $" .. tostring(deposited) .. ".")
end