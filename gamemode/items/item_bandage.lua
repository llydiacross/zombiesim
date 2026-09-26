// Bandage: restores health. A doctor (Medicine 5+ or the Doctor job) doubles the healing.
local itemBandage = ZM_Items:NewItemClass()
itemBandage.BaseHealAmount = 25
itemBandage.DoctorMedicine = 5

function itemBandage:IsDoctor(ply)
    return ply:GetStat("Medicine") >= self.DoctorMedicine or ply:GetJobRole() == "Doctor"
end

function itemBandage:CanUse(ply, itemData, targetPly)
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

function itemBandage:GetHealAmount(ply)
    local doctor = self:IsDoctor(ply)
    return doctor and self.BaseHealAmount * 2 or self.BaseHealAmount, doctor
end

function itemBandage:OnUse(ply, itemData, targetPly)
    local target = targetPly or ply
    if not IsValid(target) or not target:Alive() then
        return false
    end
    local healAmount, doctor = self:GetHealAmount(ply)
    local currentHealth = target:Health()
    local newHealth = math.min(currentHealth + healAmount, target:GetMaxHealth())
    target:SetHealth(newHealth)
    target:EmitSound("items/medshot4.wav", 75, 100)
    if doctor then
        ply:ChatPrint("[Medical] Doctor application bonus applied! (+100% Healing)")
    end
    ply:ChatPrint("[Item] Restored " .. (newHealth - currentHealth) .. " HP.")
    return true
end

ZM_EntityClasses["itemBandage"] = itemBandage
