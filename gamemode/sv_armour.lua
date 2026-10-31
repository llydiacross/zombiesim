ZM_Armour = ZM_Armour or {}
local Armour = ZM_Armour

function Armour:GetDamageMultiplier(inventory, endurance, isRadiation)
    if isRadiation then return 1 end
    local effects = ZM_Items:GetArmourEffects(inventory, endurance)
    return 1 - effects.damageReduction
end

function Armour:ApplyDamage(target, damage)
    if not target:IsPlayer() then return end
    local multiplier = self:GetDamageMultiplier(
        target.ZM_Inventory, target:GetStat("Endurance"), damage:IsDamageType(DMG_RADIATION))
    if multiplier < 1 then damage:SetDamage(damage:GetDamage() * multiplier) end
end

hook.Add("EntityTakeDamage", "ZM.Armour.DamageReduction", function(target, damage)
    Armour:ApplyDamage(target, damage)
end)
