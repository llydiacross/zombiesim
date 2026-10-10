AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    if not self.Velocity or not self.Damage or not self.Range then
        ErrorNoHalt("[ZombieSim] Crossbow bolt was spawned without its firing contract.\n")
        self:Remove()
        return
    end
    self:SetModel("models/crossbow_bolt.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self.Started = CurTime()
    self.LastTick = self.Started
    self.Travelled = 0
end

function ENT:Think()
    if self.Impacted then return end
    local now = CurTime()
    if now - self.Started >= 10 or self.Travelled >= self.Range then
        self:Remove()
        return
    end
    local delta = math.max(0, now - self.LastTick)
    self.LastTick = now
    local travel = self.Velocity * delta
    local remaining = self.Range - self.Travelled
    if travel:Length() > remaining then travel = travel:GetNormalized() * remaining end
    local start = self:GetPos()
    local trace = util.TraceLine({
        start = start, endpos = start + travel, mask = MASK_SHOT,
        filter = { self, self:GetOwner(), self.Weapon }
    })
    self.Travelled = self.Travelled + travel:Length()
    if trace.Hit or trace.StartSolid then
        self.Impacted = true
        if IsValid(trace.Entity) and not trace.HitSky then
            local damage = DamageInfo()
            damage:SetDamage(self.Damage)
            damage:SetDamageType(DMG_BULLET)
            damage:SetDamagePosition(trace.HitPos)
            damage:SetDamageForce(self.Velocity:GetNormalized() * self.Damage * 10)
            damage:SetAttacker(IsValid(self:GetOwner()) and self:GetOwner() or self)
            damage:SetInflictor(IsValid(self.Weapon) and self.Weapon or self)
            trace.Entity:DispatchTraceAttack(damage, trace, self.Velocity:GetNormalized())
        end
        if not trace.HitSky then
            self:EmitSound(IsValid(trace.Entity) and "weapons/crossbow/hitbod1.wav" or "weapons/crossbow/hit1.wav")
        end
        self:Remove()
        return
    end
    self:SetPos(trace.HitPos)
    self.Velocity = self.Velocity + Vector(0, 0, -30) * delta
    self:SetAngles(self.Velocity:Angle())
    self:NextThink(now)
    return true
end
