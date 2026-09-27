// Medical items: any definition with a medical block. Heals the user or a target player; a Doctor (by job or
// Medicine 5+) applies it for StaticData.DoctorMedicalBonus more. Loaded through shared.lua's items/ scan.
local MedicalItem = ZM_Items:NewItemClass()
MedicalItem.DoctorMedicine = 5

function MedicalItem:IsDoctor(ply)
    return ply:GetStat("Medicine") >= self.DoctorMedicine or ply:GetJobRole() == "Doctor"
end

function MedicalItem:GetHealAmount(ply, itemData)
    local definition = itemData.definition or ZM_Items:GetDefinition(itemData.id)
    local base = definition and definition.medical and definition.medical.health or 0
    local doctor = self:IsDoctor(ply)
    return doctor and math.floor(base * (1 + ZM_StaticData.DoctorMedicalBonus) + 0.5) or base, doctor
end

function MedicalItem:CanUse(ply, itemData, targetPly)
    local canUse, reason = ZM_EntityClasses.GenericItem.CanUse(self, ply, itemData, targetPly)
    if not canUse then
        return false, reason
    end
    local target = targetPly or ply
    if not IsValid(target) or not target:Alive() then
        return false, "Target is dead or invalid."
    end
    if target:Health() >= target:GetMaxHealth() then
        return false, "Health is already full."
    end
    return true, ""
end

function MedicalItem:OnUse(ply, itemData, targetPly)
    local target = targetPly or ply
    if not IsValid(target) or not target:Alive() then
        return false
    end
    local healAmount, doctor = self:GetHealAmount(ply, itemData)
    local currentHealth = target:Health()
    local newHealth = math.min(currentHealth + healAmount, target:GetMaxHealth())
    target:SetHealth(newHealth)
    if target.EmitSound then
        target:EmitSound("items/medshot4.wav", 75, 100)
    end
    itemData.healed = newHealth - currentHealth
    if ply.ChatPrint then
        if doctor then
            ply:ChatPrint("[Medical] Doctor application bonus applied (+" .. math.floor(ZM_StaticData.DoctorMedicalBonus * 100) .. "% healing).")
        end
        ply:ChatPrint("[Item] Restored " .. itemData.healed .. " HP.")
    end
    return true
end

ZM_EntityClasses = ZM_EntityClasses or {}
ZM_EntityClasses.MedicalItem = MedicalItem
