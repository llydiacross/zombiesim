AddCSLuaFile()
DEFINE_BASECLASS("weapon_zn_base_hitscan")

SWEP.Base = "weapon_zn_base_hitscan"
SWEP.PrintName = "ZombieSim CS 1.6 Firearm"
SWEP.ViewModelFOV = 75
SWEP.ViewModelFlip = true
SWEP.UseHands = true
SWEP.IdleSequence = "idle1"
SWEP.DrawSequence = "draw"
SWEP.FireSequence = "shoot1"
SWEP.ReloadSequence = "reload"
SWEP.Primary.ClipSize = 256

local bonuses = { DamageScale = 1.25, RangeScale = 1.2, SpeedScale = 1 / 1.15, ReloadScale = 1 / 1.15, ClipScale = 1.2 }

function SWEP:GetScale(name)
    return BaseClass.GetScale(self, name) * (bonuses[name] or 1)
end

// These ports have named sequences, but no ACT_VM activity mappings.
function SWEP:SendWeaponAnim(activity)
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    local model = owner:GetViewModel()
    if not IsValid(model) then return end
    local name
    if activity == ACT_VM_PRIMARYATTACK then
        name = self.FireSequence
        if self.DualPistols then
            name = self:Clip1() % 2 == 0 and "shoot_left1" or "shoot_right1"
        end
    elseif activity == ACT_VM_RELOAD then
        name = self.ReloadSequence
    elseif activity == ACT_VM_DRAW then
        name = self.DrawSequence
    elseif activity == ACT_VM_IDLE then
        name = self.IdleSequence
    else
        ErrorNoHalt("[ZombieSim] Unsupported CS 1.6 weapon activity: " .. tostring(activity) .. "\n")
        return
    end
    self:PlayNamedWeaponAnimation(name)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

function SWEP:FireAnimationEvent(pos, ang, event, options)
    // Reload/cycle audio and brass belong to ZombieSim, not the addon aliases.
    if event == 5004 or (event == 0 and string.StartWith(options or "", "EjectBrass_")) then return true end
    return BaseClass.FireAnimationEvent(self, pos, ang, event, options)
end

function SWEP:Think()
    BaseClass.Think(self)
    if self:IsSafeZoneHolstered() or self:IsReloading() then return end
    if self.NextIdleAt and CurTime() >= self.NextIdleAt then
        self:SendWeaponAnim(ACT_VM_IDLE)
    end
end
