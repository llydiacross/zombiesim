ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Dropped Item Crate"
ENT.Category = "ZombieSim"
ENT.Spawnable = false
ENT.AdminOnly = false

function ENT:SetDropData(data)
    self.ZM_DroppedItemData = table.Copy(data)
    local instance = data and data.instance
    if not instance then return end
    local definition = ZM_Items and ZM_Items:GetDefinition(instance.itemId)
    self:SetNWString("ZM_DropItemName", definition and definition.name or instance.itemId)
    self:SetNWInt("ZM_DropItemCount", instance.count or 0)
end

function ENT:Initialize()
    if not SERVER then return end
    self:SetModel("models/props_junk/wood_crate001a.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    local minimum, maximum = self:GetModelBounds()
    self:SetCollisionBounds(minimum, maximum)
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(true)
    if self.ZM_DroppedItemData then
        self:SetDropData(self.ZM_DroppedItemData)
    end
end
