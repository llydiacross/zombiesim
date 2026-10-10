AddCSLuaFile()
DEFINE_BASECLASS("weapon_zn_base_melee")

SWEP.Base = "weapon_zn_base_melee"
SWEP.PrintName = "ZombieSim Imported Melee"
SWEP.UseHands = false
SWEP.ViewModelFOV = 65
SWEP.IdleSequence = "idle"
SWEP.DrawSequence = "draw"
SWEP.HitSequence = "midslash1"
SWEP.MissSequence = "stab_miss"

function SWEP:SendWeaponAnim(activity)
    local sequences = {
        [ACT_VM_DRAW] = self.DrawSequence, [ACT_VM_IDLE] = self.IdleSequence,
        [ACT_VM_HITCENTER] = self.HitSequence, [ACT_VM_MISSCENTER] = self.MissSequence
    }
    local name = sequences[activity]
    if not name then
        ErrorNoHalt("[ZombieSim] Unsupported imported melee activity: " .. tostring(activity) .. "\n")
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
    if self:IsSafeZoneHolstered() then return end
    if self.NextIdleAt and CurTime() >= self.NextIdleAt then self:SendWeaponAnim(ACT_VM_IDLE) end
end

function SWEP:FireAnimationEvent(_, _, event)
    if event == 5004 then return true end
end
