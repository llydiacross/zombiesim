AddCSLuaFile()

SWEP.Base = "weapon_zn_base_hitscan"
SWEP.PrintName = "Crossbow"
SWEP.ViewModel = "models/weapons/c_crossbow.mdl"
SWEP.WorldModel = "models/weapons/w_crossbow.mdl"
SWEP.HoldType = "crossbow"
SWEP.Slot = 4
SWEP.FirePresentation = "crossbow"
SWEP.PresentsShot = false
SWEP.BulletDamage = 75
SWEP.BulletRange = 8192
SWEP.FireDelay = 1.1
SWEP.BaseClipSize = 1
SWEP.ReloadTime = 1.8
SWEP.RecoilPitch = 0.5
SWEP.GoreSeverFactor = 1.5
SWEP.FireSound = "weapons/crossbow/fire1.wav"
SWEP.ReloadSound = "weapons/crossbow/reload1.wav"
SWEP.ReloadFinishSound = "weapons/crossbow/bolt_load1.wav"

function SWEP:FireRound(owner, source, direction)
    if CLIENT then return true end
    local bolt = ents.Create("zn_crossbow_bolt")
    if not IsValid(bolt) then
        ErrorNoHalt("[ZombieSim] Could not create crossbow bolt; ammunition retained.\n")
        return false
    end
    bolt:SetPos(source)
    bolt:SetAngles(direction:Angle())
    bolt:SetOwner(owner)
    bolt.Weapon = self
    bolt.Damage = self:GetScaledDamage(self.BulletDamage)
    bolt.Range = self.BulletRange * self:GetScale("RangeScale")
    bolt.Velocity = direction * 2500
    bolt:Spawn()
    if not IsValid(bolt) or bolt:IsMarkedForDeletion() then
        ErrorNoHalt("[ZombieSim] Crossbow bolt initialization failed; ammunition retained.\n")
        return false
    end
    return true
end
