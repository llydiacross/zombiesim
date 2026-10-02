AddCSLuaFile()

// Melee base: a lag-compensated hull trace from the centre of mass along the player's level facing.
// Damage and Range scale damage and reach, Swiftness scales the swing delay, Crushing scales knockback force.
SWEP.Base = "weapon_zn_base"
SWEP.PrintName = "ZombieSim Melee"
SWEP.HoldType = "melee"
SWEP.MeleeDamage = 20
SWEP.MeleeRange = 72
SWEP.MeleeDelay = 0.5
SWEP.MeleeForce = 4000
SWEP.MeleeDamageType = DMG_CLUB
SWEP.GoreSeverFactor = 1.4
SWEP.SwingSound = "Weapon_Crowbar.Single"
SWEP.HitSound = "Weapon_Crowbar.Melee_Hit"
SWEP.HitWorldSound = "Weapon_Crowbar.Melee_HitWorld"

local hullMins = Vector(-10, -10, -8)
local hullMaxs = Vector(10, 10, 8)

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) or self:IsSafeZoneHolstered() then
        return
    end
    self:SetNextPrimaryFire(CurTime() + self:GetScaledDelay(self.MeleeDelay))
    owner:SetAnimation(PLAYER_ATTACK1)

    local start, direction = owner:GetLevelAim()
    owner:LagCompensation(true)
    local trace = util.TraceHull({
        start = start,
        endpos = start + direction * self.MeleeRange * self:GetScale("RangeScale"),
        filter = owner,
        mins = hullMins,
        maxs = hullMaxs,
        mask = MASK_SHOT_HULL
    })
    owner:LagCompensation(false)

    if trace.Hit then
        self:SendWeaponAnim(ACT_VM_HITCENTER)
        self:PlaySound(IsValid(trace.Entity) and self.HitSound or self.HitWorldSound)
    else
        self:SendWeaponAnim(ACT_VM_MISSCENTER)
        self:PlaySound(self.SwingSound)
    end

    if SERVER and IsValid(trace.Entity) then
        local damage = DamageInfo()
        damage:SetDamage(self:GetScaledDamage(self.MeleeDamage))
        damage:SetDamageType(self.MeleeDamageType)
        damage:SetAttacker(owner)
        damage:SetInflictor(self)
        damage:SetDamagePosition(trace.HitPos)
        damage:SetDamageForce(direction * self.MeleeForce * self:GetScale("CrushScale"))
        trace.Entity:TakeDamageInfo(damage)
    end
end
