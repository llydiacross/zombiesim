AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local collisionMins = Vector(-16, -16, 0)
local collisionMaxs = Vector(16, 16, 72)

function ENT:Initialize()
    self:SetModel(self.Model)
    self:SetHealth(self.DevelopmentHealth)
    self:SetCollisionBounds(collisionMins, collisionMaxs)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self.loco:SetDesiredSpeed(self.DevelopmentWalkSpeed)
    self.loco:SetAcceleration(250)
    self.loco:SetDeceleration(300)
    self.NextAttackAt = 0
    self.NextTargetSearchAt = CurTime() + (self:EntIndex() % 5) * 0.1
    self.NextPathRetryAt = 0
    self.LastKnownTargetPosition = nil
    self.LastKnownTargetExpiresAt = 0
    self.CurrentTarget = nil
    self.CurrentPath = nil
    self.LastPathGoal = nil
    self.TargetSearchCount = 0
    self.PathComputeCount = 0
    self.PathFailureCount = 0
    self.StuckRecoveryCount = 0
    self.AttackCount = 0
    self.WalkerState = "idle"
end

function ENT:SetWalkerTicket(ticket, sourceCellId)
    if type(ticket) ~= "table" then
        return false
    end
    self.WalkerTicketIdLow = ticket.TicketIdLow
    self.WalkerTicketIdHigh = ticket.TicketIdHigh
    self.WalkerHordeIdLow = ticket.HordeIdLow
    self.WalkerHordeIdHigh = ticket.HordeIdHigh
    self.WalkerSourceCellId = sourceCellId
    self.WalkerMaterializedAt = CurTime()
    return true
end

function ENT:MarkWalkerTicketAcknowledged()
    self.WalkerTicketAcknowledged = true
    self.WalkerState = "search"
    self:RecordWalkerLifecycle("acknowledged")
end

function ENT:RecordWalkerLifecycle(event, details)
    if ZM_WalkerSim and type(ZM_WalkerSim.RecordZombieLifecycle) == "function" then
        ZM_WalkerSim:RecordZombieLifecycle(self, event, details)
    end
end

function ENT:ResolveWalkerTicket(killed)
    if self.WalkerTicketResolved or not self.WalkerTicketAcknowledged or not ZM_WalkerSim then
        return
    end
    if ZM_WalkerSim.IsShuttingDown then
        self.WalkerTicketResolved = true
        self.WalkerState = "shutdown"
        self:RecordWalkerLifecycle("resolutionSkippedDuringShutdown", { killed = killed == true })
        return
    end

    local resolved, resolveError = ZM_WalkerSim:ResolveTicket(
        self.WalkerTicketIdLow,
        self.WalkerTicketIdHigh,
        killed == true
    )
    if resolved then
        self.WalkerTicketResolved = true
        self.WalkerState = killed == true and "killed" or "despawned"
        self:RecordWalkerLifecycle(killed == true and "killedQueued" or "despawnQueued")
    else
        self:RecordWalkerLifecycle("resolutionFailed", { error = tostring(resolveError) })
        ErrorNoHalt("[ZombieSim] Could not resolve Walker ticket for zombie removal: " .. tostring(resolveError) .. "\n")
    end
end

function ENT:IsValidTarget(target)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
        return false
    end
    local cell = target:GetWorldCell()
    return cell and cell.id == self.WalkerSourceCellId
end

function ENT:CanSeeTarget(target)
    if not self:IsValidTarget(target) then
        return false
    end
    local trace = util.TraceLine({
        start = self:WorldSpaceCenter(),
        endpos = target:EyePos(),
        mask = MASK_SOLID_BRUSHONLY,
        filter = self
    })
    return not trace.Hit
end

function ENT:FindTarget()
    local selected
    local selectedDistance = math.huge
    local maximumDistanceSquared = self.DevelopmentTargetSearchRange * self.DevelopmentTargetSearchRange
    for _, playerEntity in ipairs(player.GetAll()) do
        if self:IsValidTarget(playerEntity) then
            local distance = self:GetPos():DistToSqr(playerEntity:GetPos())
            if distance <= maximumDistanceSquared and distance < selectedDistance and self:CanSeeTarget(playerEntity) then
                selected = playerEntity
                selectedDistance = distance
            end
        end
    end
    return selected
end

function ENT:RefreshTarget()
    if CurTime() < self.NextTargetSearchAt then
        return self.CurrentTarget
    end

    self.NextTargetSearchAt = CurTime() + self.DevelopmentTargetSearchInterval
    self.TargetSearchCount = self.TargetSearchCount + 1
    self.CurrentTarget = self:FindTarget()
    if IsValid(self.CurrentTarget) then
        self.LastKnownTargetPosition = self.CurrentTarget:GetPos()
        self.LastKnownTargetExpiresAt = CurTime() + self.DevelopmentTargetMemorySeconds
    end
    return self.CurrentTarget
end

function ENT:ShouldRefreshPath(goal)
    if not self.CurrentPath or not self.CurrentPath:IsValid() or not self.LastPathGoal then
        return true
    end
    if self.CurrentPath:GetAge() >= self.DevelopmentPathRefreshInterval then
        return true
    end
    return self.LastPathGoal:DistToSqr(goal) >= self.DevelopmentTargetMoveThreshold * self.DevelopmentTargetMoveThreshold
end

function ENT:UpdatePath(goal)
    if CurTime() < self.NextPathRetryAt then
        return false
    end
    if not self.CurrentPath then
        self.CurrentPath = Path("Follow")
        self.CurrentPath:SetMinLookAheadDistance(300)
        self.CurrentPath:SetGoalTolerance(self.DevelopmentAttackRange * 0.75)
    end
    if self:ShouldRefreshPath(goal) then
        self.CurrentPath:Compute(self, goal)
        self.LastPathGoal = Vector(goal.x, goal.y, goal.z)
        self.PathComputeCount = self.PathComputeCount + 1
    end
    if not self.CurrentPath:IsValid() then
        self.WalkerState = "pathFailed"
        self.NextPathRetryAt = CurTime() + self.DevelopmentPathFailureCooldown
        self.PathFailureCount = self.PathFailureCount + 1
        self:RecordWalkerLifecycle("pathFailed")
        return false
    end
    self.CurrentPath:Update(self)
    if self.loco:IsStuck() then
        self:HandleStuck()
        self.NextPathRetryAt = CurTime() + self.DevelopmentPathFailureCooldown
        return false
    end
    return true
end

function ENT:AttackTarget(target)
    if CurTime() < self.NextAttackAt or not self:IsValidTarget(target) or not self:CanSeeTarget(target) or
        self:GetRangeTo(target) > self.DevelopmentAttackRange then
        return
    end

    self.NextAttackAt = CurTime() + self.DevelopmentAttackInterval
    self.AttackCount = self.AttackCount + 1
    self.WalkerState = "attack"
    self:StartActivity(ACT_MELEE_ATTACK1)
    local damage = DamageInfo()
    damage:SetDamage(self.DevelopmentAttackDamage)
    damage:SetDamageType(DMG_SLASH)
    damage:SetAttacker(self)
    damage:SetInflictor(self)
    target:TakeDamageInfo(damage)
end

function ENT:ChaseTarget(target)
    self:StartActivity(ACT_WALK)
    self.loco:SetDesiredSpeed(self.DevelopmentWalkSpeed)

    while self:IsValidTarget(target) do
        if self:RefreshTarget() ~= target then
            return
        end
        if self:CanSeeTarget(target) then
            self.LastKnownTargetPosition = target:GetPos()
            self.LastKnownTargetExpiresAt = CurTime() + self.DevelopmentTargetMemorySeconds
        end
        if self:GetRangeTo(target) <= self.DevelopmentAttackRange then
            self:AttackTarget(target)
            coroutine.wait(0.1)
        else
            self.WalkerState = "pursue"
            if not self:UpdatePath(target:GetPos()) then
                return
            end
            coroutine.yield()
        end
    end
end

function ENT:RunBehaviour()
    while true do
        local target = self:RefreshTarget()
        if target then
            self.WalkerState = "pursue"
            self:ChaseTarget(target)
        elseif self.LastKnownTargetPosition and CurTime() < self.LastKnownTargetExpiresAt then
            self.WalkerState = "targetLost"
            self:StartActivity(ACT_WALK)
            self.loco:SetDesiredSpeed(self.DevelopmentWalkSpeed)
            if self:UpdatePath(self.LastKnownTargetPosition) then
                coroutine.yield()
            else
                self.LastKnownTargetPosition = nil
            end
        else
            self.WalkerState = "idle"
            self:StartActivity(ACT_IDLE)
            coroutine.wait(0.1)
        end
        coroutine.yield()
    end
end

function ENT:IsWalkerEngaged()
    if IsValid(self.CurrentTarget) and self:IsValidTarget(self.CurrentTarget) then
        return true
    end
    return self.LastKnownTargetPosition ~= nil and CurTime() < self.LastKnownTargetExpiresAt
end

function ENT:HandleStuck()
    self.loco:ClearStuck()
    self.WalkerState = "stuckRecovery"
    self.StuckRecoveryCount = self.StuckRecoveryCount + 1
    self.CurrentPath = nil
    self.LastPathGoal = nil
    self.CurrentTarget = nil
    self.LastKnownTargetPosition = nil
    self.LastKnownTargetExpiresAt = 0
end

function ENT:GetWalkerPerformanceStats()
    return {
        state = self.WalkerState,
        targetSearches = self.TargetSearchCount,
        pathComputes = self.PathComputeCount,
        pathFailures = self.PathFailureCount,
        stuckRecoveries = self.StuckRecoveryCount,
        attacks = self.AttackCount,
        nextPathRetryAt = self.NextPathRetryAt
    }
end

function ENT:OnInjured(damage)
    if self.WalkerDead then
        return
    end
    self:SetHealth(self:Health() - math.max(0, damage:GetDamage()))
    if self:Health() <= 0 then
        self:OnKilled(damage)
    end
end

function ENT:OnKilled(damage)
    if self.WalkerDead then
        return
    end
    self.WalkerDead = true
    self:ResolveWalkerTicket(true)
    self:BecomeRagdoll(damage)
end

function ENT:OnRemove()
    if not self.WalkerTicketAcknowledged then
        self:RecordWalkerLifecycle("removedBeforeAcknowledgement")
        return
    end
    self:ResolveWalkerTicket(self.WalkerDead == true)
end