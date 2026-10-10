AddCSLuaFile()
DEFINE_BASECLASS("weapon_zn_base_hitscan")

SWEP.Base = "weapon_zn_base_hitscan"
SWEP.PrintName = "Lewis Gun"
SWEP.Slot = 2
SWEP.ViewModel = "models/zombiesim/imported/lewis/weapons/v_lewis.mdl"
SWEP.WorldModel = "models/zombiesim/imported/lewis/weapons/w_mach_m249para.mdl"
SWEP.HoldType = "ar2"
SWEP.UseHands = false
SWEP.ViewModelFOV = 65
SWEP.Primary.Automatic = true
SWEP.Primary.ClipSize = 128
SWEP.BaseClipSize = 47
SWEP.BulletDamage = 24
SWEP.BulletRange = 4600
SWEP.BulletSpread = 0.035
SWEP.FireDelay = 0.11
SWEP.ReloadTime = 4
SWEP.FirePresentation = "rifle762"
SWEP.BulletForce = 4
SWEP.RecoilPitch = 1
SWEP.GoreSeverFactor = 1
SWEP.FireSound = "zombiesim/imported/lewis/weapons/lewis/fire.wav"
SWEP.ReloadSound = "zombiesim/imported/lewis/weapons/lewis/magout.wav"
SWEP.ReloadFinishSound = "zombiesim/imported/lewis/weapons/lewis/boltback.wav"
SWEP.EmptySound = "zombiesim/imported/lewis/weapons/lewis/empty.wav"

function SWEP:SendWeaponAnim(activity)
    local sequences = {
        [ACT_VM_DRAW] = "base_draw", [ACT_VM_IDLE] = "base_idle",
        [ACT_VM_RELOAD] = "base_reload", [ACT_VM_PRIMARYATTACK] = "base_fire_1"
    }
    local name = sequences[activity]
    if not name then
        ErrorNoHalt("[ZombieSim] Unsupported Lewis weapon activity: " .. tostring(activity) .. "\n")
        return
    end
    self:PlayNamedWeaponAnimation(name)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

function SWEP:Think()
    BaseClass.Think(self)
    if self:IsSafeZoneHolstered() or self:IsReloading() then return end
    if self.NextIdleAt and CurTime() >= self.NextIdleAt then self:SendWeaponAnim(ACT_VM_IDLE) end
end

function SWEP:FireAnimationEvent(pos, ang, event)
    if event == 5004 then return true end
    return BaseClass.FireAnimationEvent(self, pos, ang, event)
end
