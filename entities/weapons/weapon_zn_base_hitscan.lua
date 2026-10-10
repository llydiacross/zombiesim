AddCSLuaFile()
DEFINE_BASECLASS("weapon_zn_base")

// Hitscan base with a per-instance clip. Bullets use the shared player aim helper.
// Damage and Range scale bullets, FiringSpeed scales the fire delay,
// ReloadSpeed scales the reload time, and ClipSize scales the magazine.
// Reloads are completed server-side by ZM_AmmoService and consume the weapon's mapped inventory ammo.
SWEP.Base = "weapon_zn_base"
SWEP.PrintName = "ZombieSim Firearm"
SWEP.HoldType = "pistol"
SWEP.BulletDamage = 12
SWEP.BulletRange = 4096
SWEP.BulletSpread = 0.02
SWEP.BulletForce = 2.5
SWEP.BulletCount = 1
// Multiplies ZM_Gore's per-hit sever chance; heavier weapons override it.
SWEP.GoreSeverFactor = 0.5
SWEP.FireDelay = 0.2
SWEP.BaseClipSize = 12
SWEP.ReloadTime = 1.5
SWEP.FireSound = "Weapon_Pistol.Single"
SWEP.ReloadSound = "Weapon_Pistol.Reload"
SWEP.EmptySound = "Weapon_Pistol.Empty"
SWEP.FirePresentation = "pistol"
SWEP.RecoilPitch = 0.65
SWEP.RecoilYaw = 0.2
SWEP.MuzzleBlastSpeed = 75

// Upper bound so the engine tracks Clip1; GetMaxClip is the real per-instance limit.
SWEP.Primary.ClipSize = 64
SWEP.Primary.DefaultClip = 0
SWEP.Primary.Ammo = "none"

function SWEP:SetupDataTables()
    BaseClass.SetupDataTables(self)
    // Slots 0-6 belong to weapon_zn_base.
    self:NetworkVar("Float", 7, "RecoilPitchOffset")
    self:NetworkVar("Float", 8, "RecoilYawOffset")
    self:NetworkVar("Float", 9, "RecoilUpdatedAt")
end

function SWEP:GetAimRecoil()
    // Lua auto-refresh does not rerun SetupDataTables on existing weapon entities.
    if not self.GetRecoilUpdatedAt then
        if not self.RecoilReloadWarning then
            self.RecoilReloadWarning = true
            ErrorNoHalt("[ZombieSim] Recoil awaits weapon recreation; reload the current map after this update.\n")
        end
        return Angle(0, 0, 0)
    end
    local decay = math.exp(-math.max(0, CurTime() - self:GetRecoilUpdatedAt()) * 7)
    return Angle(self:GetRecoilPitchOffset() * decay, self:GetRecoilYawOffset() * decay, 0)
end

function SWEP:AddAimRecoil()
    local offset = self:GetAimRecoil()
    if not self.SetRecoilUpdatedAt then return end
    self:SetRecoilPitchOffset(math.Clamp(offset.p - self.RecoilPitch, -4, 0))
    self:SetRecoilYawOffset(math.Clamp(offset.y + util.SharedRandom("ZM.WeaponRecoil", -self.RecoilYaw, self.RecoilYaw), -1.5, 1.5))
    self:SetRecoilUpdatedAt(CurTime())
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then
        self:SetClip1(0)
    end
end

function SWEP:GetMaxClip()
    return math.Clamp(math.Round(self.BaseClipSize * self:GetScale("ClipScale")), 1, self.Primary.ClipSize)
end

function SWEP:OnItemInstanceApplied(instance)
    if SERVER and ZM_AmmoService then
        ZM_AmmoService:ApplyStoredClip(self, instance)
    end
end

function SWEP:IsReloading()
    return self:GetReloadFinishTime() > 0
end

function SWEP:Think()
    if self:UpdateSafeZoneHolster() then return end
    if SERVER and self.NextCycleSoundAt and CurTime() >= self.NextCycleSoundAt then
        self.NextCycleSoundAt = nil
        local owner = self:GetOwner()
        if IsValid(owner) and owner:Alive() and owner:GetActiveWeapon() == self then
            self:PlaySound(self.CycleSound)
        end
    end
    local finish = self:GetReloadFinishTime()
    if SERVER and finish > 0 and CurTime() >= finish then
        self:SetReloadFinishTime(0)
        local owner = self:GetOwner()
        if not IsValid(owner) or not owner:Alive() or owner:GetActiveWeapon() ~= self then
            return
        end
        if ZM_AmmoService then
            local reloaded = ZM_AmmoService:CompleteReload(owner, self)
            if not reloaded then
                self:PlaySound(self.EmptySound)
            elseif self.ReloadFinishSound then
                self:PlaySound(self.ReloadFinishSound)
            end
        end
    end
end

function SWEP:Reload()
    if self:IsSafeZoneHolstered() then return end
    if self:IsReloading() or self:Clip1() >= self:GetMaxClip() then
        return
    end
    if SERVER and (not ZM_AmmoService or ZM_AmmoService:GetReserve(self:GetOwner(), self:GetMappedAmmoId()) <= 0) then
        self:PlaySound(self.EmptySound)
        return
    end
    local duration = self.ReloadTime * self:GetScale("ReloadScale")
    self:SetReloadFinishTime(CurTime() + duration)
    self:SetNextPrimaryFire(CurTime() + duration)
    self:SendWeaponAnim(ACT_VM_RELOAD)
    self:GetOwner():SetAnimation(PLAYER_RELOAD)
    self:PlaySound(self.ReloadSound)
end

function SWEP:GetMappedAmmoId()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner.ZM_Inventory then
        return nil
    end
    local _, _, instance = ZM_InventoryService.Ops.FindInstance(owner.ZM_Inventory, self:GetItemInstanceId())
    local definition = instance and ZM_Items:GetDefinition(instance.itemId) or nil
    return definition and definition.ammoId or nil
end

function SWEP:FireAnimationEvent(_, _, event)
    if self:IsSafeZoneHolstered() then return true end
    if ZM_WeaponEffects.AnimationEvents[event] then return true end
end

function SWEP:PlaySound(sound)
    if sound == self.FireSound and string.EndsWith(sound, ".wav") then
        if IsFirstTimePredicted() then self:EmitSound(sound, 140, 100, 1, CHAN_WEAPON) end
    else
        BaseClass.PlaySound(self, sound)
    end
end

function SWEP:GetBulletData(owner, source, direction, impacts)
    return {
        Num = self.BulletCount,
        Src = source,
        Dir = direction,
        Spread = Vector(self.BulletSpread, self.BulletSpread, 0),
        Tracer = 0,
        Force = self.BulletForce,
        Damage = self:GetScaledDamage(self.BulletDamage),
        Distance = self.BulletRange * self:GetScale("RangeScale"),
        Attacker = owner,
        Callback = impacts and function(_, trace, damage)
            if self.BulletDamageType and damage then damage:SetDamageType(self.BulletDamageType) end
            impacts[#impacts + 1] = {
                position = trace.HitPos, normal = trace.HitNormal,
                material = trace.MatType, hit = trace.Hit and not trace.HitSky
            }
        end or nil
    }
end

function SWEP:FireRound(owner, source, direction, impacts)
    owner:LagCompensation(true)
    owner:FireBullets(self:GetBulletData(owner, source, direction, impacts))
    owner:LagCompensation(false)
    return true
end

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) or self:IsSafeZoneHolstered() or self:IsReloading() then
        return
    end
    if self:Clip1() <= 0 then
        self:SetNextPrimaryFire(CurTime() + 0.3)
        self:PlaySound(self.EmptySound)
        self:Reload()
        return
    end

    local source, direction = owner:GetLevelAim()
    local impacts = SERVER and {} or nil
    local previousClip = self:Clip1()
    self:SetNextPrimaryFire(CurTime() + self:GetScaledDelay(self.FireDelay))
    self:SetClip1(previousClip - 1)
    if not self:FireRound(owner, source, direction, impacts) then
        self:SetClip1(previousClip)
        self:SetNextPrimaryFire(CurTime() + 0.3)
        return
    end
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    owner:SetAnimation(PLAYER_ATTACK1)
    self:PlaySound(self.FireSound)

    self:AddAimRecoil()
    if SERVER and self.PresentsShot ~= false then
        if self.CycleSound then self.NextCycleSoundAt = CurTime() + self.CycleSoundDelay end
        ZM_WeaponEffects.ApplyMuzzleBlast(self, source)
        ZM_WeaponEffects.SendShot(self, source, direction, impacts)
    end
end
