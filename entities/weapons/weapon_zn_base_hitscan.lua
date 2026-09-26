AddCSLuaFile()

// Hitscan base with a per-instance clip. Bullets leave the centre of mass level with the ground (see ply:GetLevelAim).
// Damage and Range scale bullets, FiringSpeed scales the fire delay,
// ReloadSpeed scales the reload time, and ClipSize scales the magazine.
// Reloads refill the clip without consuming reserve ammo; ammo items are not part of Alpha 2.7 yet.
SWEP.Base = "weapon_zn_base"
SWEP.PrintName = "ZombieSim Firearm"
SWEP.HoldType = "pistol"
SWEP.BulletDamage = 12
SWEP.BulletRange = 4096
SWEP.BulletSpread = 0.02
SWEP.BulletForce = 2
SWEP.FireDelay = 0.2
SWEP.BaseClipSize = 12
SWEP.ReloadTime = 1.5
SWEP.FireSound = "Weapon_Pistol.Single"
SWEP.ReloadSound = "Weapon_Pistol.Reload"
SWEP.EmptySound = "Weapon_Pistol.Empty"

// Upper bound so the engine tracks Clip1; GetMaxClip is the real per-instance limit.
SWEP.Primary.ClipSize = 64
SWEP.Primary.DefaultClip = 0
SWEP.Primary.Ammo = "Pistol"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then
        self:SetClip1(self.BaseClipSize)
    end
end

function SWEP:GetMaxClip()
    return math.Clamp(math.Round(self.BaseClipSize * self:GetScale("ClipScale")), 1, self.Primary.ClipSize)
end

function SWEP:OnItemInstanceApplied()
    self:SetClip1(self:GetMaxClip())
end

function SWEP:IsReloading()
    return self:GetReloadFinishTime() > 0
end

function SWEP:Think()
    local finish = self:GetReloadFinishTime()
    if finish > 0 and CurTime() >= finish then
        self:SetReloadFinishTime(0)
        self:SetClip1(self:GetMaxClip())
    end
end

function SWEP:Reload()
    if self:IsReloading() or self:Clip1() >= self:GetMaxClip() then
        return
    end
    local duration = self.ReloadTime * self:GetScale("ReloadScale")
    self:SetReloadFinishTime(CurTime() + duration)
    self:SetNextPrimaryFire(CurTime() + duration)
    self:SendWeaponAnim(ACT_VM_RELOAD)
    self:GetOwner():SetAnimation(PLAYER_RELOAD)
    self:PlaySound(self.ReloadSound)
end

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) or self:IsReloading() then
        return
    end
    if self:Clip1() <= 0 then
        self:SetNextPrimaryFire(CurTime() + 0.3)
        self:PlaySound(self.EmptySound)
        self:Reload()
        return
    end

    self:SetNextPrimaryFire(CurTime() + self:GetScaledDelay(self.FireDelay))
    self:SetClip1(self:Clip1() - 1)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    owner:MuzzleFlash()
    owner:SetAnimation(PLAYER_ATTACK1)
    self:PlaySound(self.FireSound)

    local source, direction = owner:GetLevelAim()
    owner:LagCompensation(true)
    owner:FireBullets({
        Num = 1,
        Src = source,
        Dir = direction,
        Spread = Vector(self.BulletSpread, self.BulletSpread, 0),
        Tracer = 1,
        Force = self.BulletForce,
        Damage = self:GetScaledDamage(self.BulletDamage),
        Distance = self.BulletRange * self:GetScale("RangeScale"),
        Attacker = owner
    })
    owner:LagCompensation(false)
end
