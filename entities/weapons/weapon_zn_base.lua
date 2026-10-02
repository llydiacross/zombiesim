AddCSLuaFile()

// Shared base for ZombieSim item weapons. The server copies an item instance's attribute multipliers into
// these networked scales (ZM_Items:ApplyInstanceToWeapon); scales stay 1 until an instance is applied.
SWEP.Base = "weapon_base"
SWEP.PrintName = "ZombieSim Weapon"
SWEP.Author = "ZombieSim"
SWEP.Category = "ZombieSim"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.DrawCrosshair = false
SWEP.HoldType = "normal"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = 0
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = 0
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local scaleNames = { "DamageScale", "RangeScale", "SpeedScale", "CrushScale", "ReloadScale", "ClipScale" }

function SWEP:SetupDataTables()
    for index, name in ipairs(scaleNames) do
        self:NetworkVar("Float", index - 1, name)
    end
    self:NetworkVar("Float", #scaleNames, "ReloadFinishTime")
    self:NetworkVar("String", 0, "ItemInstanceId")
    if SERVER then
        for _, name in ipairs(scaleNames) do
            self["Set" .. name](self, 1)
        end
    end
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:IsSafeZoneHolstered()
    return ZM_SafeZones:IsPlayerInside(self:GetOwner())
end

function SWEP:UpdateSafeZoneHolster()
    local holstered = self:IsSafeZoneHolstered()
    if self.SafeZoneHolstered ~= holstered then
        self.SafeZoneHolstered = holstered
        self:SetHoldType(holstered and "normal" or self.HoldType)
    end
    if holstered then
        local finish = self:GetReloadFinishTime()
        if finish > 0 then
            self:SetReloadFinishTime(0)
            if self:GetNextPrimaryFire() == finish then self:SetNextPrimaryFire(CurTime()) end
        end
        self.NextCycleSoundAt = nil
        if self.SetRecoilUpdatedAt then
            self:SetRecoilPitchOffset(0)
            self:SetRecoilYawOffset(0)
        end
    end
    return holstered
end

function SWEP:Think()
    self:UpdateSafeZoneHolster()
end

if CLIENT then
    function SWEP:PreDrawViewModel()
        if self:IsSafeZoneHolstered() then return true end
    end

    function SWEP:DrawWorldModel()
        if not self:IsSafeZoneHolstered() then self:DrawModel() end
    end

    function SWEP:DrawWorldModelTranslucent()
        if not self:IsSafeZoneHolstered() then self:DrawModel() end
    end
end

function SWEP:GetScale(name)
    local value = self["Get" .. name](self)
    return value > 0 and value or 1
end

function SWEP:GetScaledDamage(damage)
    return damage * self:GetScale("DamageScale")
end

// SpeedScale multiplies a delay, so values below 1 attack faster.
function SWEP:GetScaledDelay(delay)
    return delay * self:GetScale("SpeedScale")
end

function SWEP:PlaySound(sound)
    if sound and IsFirstTimePredicted() then
        self:EmitSound(sound)
    end
end

function SWEP:SecondaryAttack()
end
