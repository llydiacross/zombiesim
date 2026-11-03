AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local collisionMins = Vector(-16, -16, 0)
local collisionMaxs = Vector(16, 16, 72)
local corpseFadeDelay = 60
local corpseFadeDuration = 5
local corpseFadeInterval = 0.1
local modelCandidates
local modelValidity = {}

local function pickModel(entity)
    if not modelCandidates then
        modelCandidates = {}
        for _, model in ipairs(entity.Models or {}) do
            table.insert(modelCandidates, model)
        end
    end
    // Validate only the drawn candidate, not the entire mounted catalogue on the first spawn.
    while #modelCandidates > 0 do
        local index = math.random(#modelCandidates)
        local model = modelCandidates[index]
        if modelValidity[model] == nil then modelValidity[model] = util.IsValidModel(model) end
        if modelValidity[model] then return model end
        table.remove(modelCandidates, index)
    end
    ErrorNoHalt("[ZombieSim] No valid Walker model candidates; using the default model.\n")
    return entity.Model
end

function ENT:Initialize()
    self:SetModel(pickModel(self))
    self:SetSkin(math.random(0, math.max(0, self:SkinCount() - 1)))
    ZM_Gore:ApplyBloodyAppearance(self)
    self.WalkActivity = self.WalkActivities[math.random(#self.WalkActivities)]
    self:SetHealth(self.DevelopmentHealth)
    self:SetCollisionBounds(collisionMins, collisionMaxs)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self.loco:SetDesiredSpeed(self.WalkSpeed or self.DevelopmentWalkSpeed)
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
    self.HeardNoiseCount = 0
    self.AlertsSent = 0
    self.ScuffleCount = 0
    self.NextAlertAt = 0
    self.NextWanderAt = CurTime() + math.Rand(0, self.WanderPauseMax)
    self.NextMoanAt = CurTime() + math.Rand(5, 30)
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
    ZM_Clothing:AssignWalkerOutfit(self, sourceCellId)
    self.WalkerMaterializedAt = CurTime()
    return true
end

function ENT:MarkWalkerTicketAcknowledged()
    self.WalkerTicketAcknowledged = true
    self.WalkerState = "search"
    self:RecordWalkerLifecycle("acknowledged")
end

// Applies an enemy_definitions.json entry. Health and speed interpolate across the enemy's own danger range;
// speed is a multiplier on the development walk speed.
function ENT:ApplyEnemyDefinition(enemy, danger)
    local progress = ZM_Enemies.GetDangerProgress(enemy, danger)
    local health = math.max(1, math.Round(Lerp(progress, enemy.minHealth, enemy.maxHealth)))
    self.EnemyId = enemy.id
    self.EnemyDanger = math.Clamp(tonumber(danger) or 0, 0, 1)
    self.WalkSpeed = self.DevelopmentWalkSpeed * Lerp(progress, enemy.minSpeed, enemy.maxSpeed)
    self:SetMaxHealth(health)
    self:SetHealth(health)
    self.loco:SetDesiredSpeed(self.WalkSpeed)
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
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or target:IsFlagSet(FL_NOTARGET) or
        target.ZM_WalkerPreloadWaiting then
        return false
    end
    if ZM_AFK and ZM_AFK:IsProtected(target) then
        return false
    end
    if ZM_Construction and ZM_Construction.IsProtected and ZM_Construction:IsProtected(target) then
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

local function isStructure(entity)
    return IsValid(entity) and entity:GetClass() == "zn_construction_piece" and entity:GetComplete()
end

// First complete player structure on the segment; the world is ignored because CanSeeTarget already covers it.
function ENT:TraceStructure(startPos, endPos)
    local trace = util.TraceLine({
        start = startPos, endpos = endPos, ignoreworld = true,
        filter = function(entity) return isStructure(entity) end
    })
    if trace.Hit and isStructure(trace.Entity) then
        return trace.Entity, trace.HitPos, trace.HitNormal
    end
    return nil
end

// Sensing still sees through gaps, but a hit needs a clear line that no built piece interrupts.
function ENT:CanReachTarget(target)
    if not self:CanSeeTarget(target) then
        return false
    end
    local origin = self:WorldSpaceCenter()
    return not self:TraceStructure(origin, target:EyePos()) and not self:TraceStructure(origin, target:WorldSpaceCenter())
end

// A complete piece within reach between the walker and its target, or directly ahead at knee or chest height.
function ENT:FindStructureBlocker(target)
    local now = CurTime()
    if self.BlockerCheckedAt and now < self.BlockerCheckedAt + 0.25 then
        if self.BlockerPiece and not isStructure(self.BlockerPiece) then
            self.BlockerPiece = nil
        end
        return self.BlockerPiece, self.BlockerHitPos, self.BlockerHitNormal
    end
    self.BlockerCheckedAt = now
    self.BlockerPiece, self.BlockerHitPos, self.BlockerHitNormal = nil, nil, nil
    if not self:IsValidTarget(target) then
        return nil
    end
    local origin = self:WorldSpaceCenter()
    local range = self.StructureBlockRange
    local piece, hitPos, hitNormal = self:TraceStructure(origin, target:WorldSpaceCenter())
    if not piece or hitPos:Distance2D(origin) > range then
        local position = self:GetPos()
        local forward = self:FlatForward()
        piece = nil
        for _, height in ipairs({ 28, 56 }) do
            local start = position + Vector(0, 0, height)
            piece, hitPos, hitNormal = self:TraceStructure(start, start + forward * range)
            if piece then
                break
            end
        end
    end
    self.BlockerPiece, self.BlockerHitPos, self.BlockerHitNormal = piece, hitPos, hitNormal
    return piece, hitPos, hitNormal
end

// One telegraphed swing at a piece, using the player attack's wind-up and recovery. Health lives on the piece, so
// a crowd breaks it faster than one walker.
function ENT:StrikeStructure(piece, hitPos, hitNormal)
    if CurTime() < self.NextAttackAt then
        self.WalkerState = "siege"
        coroutine.wait(0.1)
        return
    end
    self.NextAttackAt = CurTime() + math.max(self.DevelopmentAttackInterval, self.AttackWindup + self.AttackRecovery)
    self.WalkerState = "siegeWindup"
    if self:GetActivity() ~= self:RestActivity() then
        self:StartActivity(self:RestActivity())
    end
    self.loco:FaceTowards(hitPos)
    self:AddGesture(self.AttackGesture)
    self:PlayVoice(self.SoundAttack, self.SoundAttackCount, 75)
    coroutine.wait(self.AttackWindup)
    if self.WalkerDead then
        return
    end
    self.StructureStrikeCount = (self.StructureStrikeCount or 0) + 1
    if isStructure(piece) and hitPos:Distance2D(self:WorldSpaceCenter()) <= self.StructureBlockRange + self.AttackReachTolerance and
        ZM_Construction and ZM_Construction.DamagePiece and
        ZM_Construction:DamagePiece(piece, self.StructureDamage, self, hitPos, hitNormal) then
        self.StructureBreakCount = (self.StructureBreakCount or 0) + 1
        self.BlockerCheckedAt = nil
    end
    self.WalkerState = "siegeRecovery"
    coroutine.wait(self.AttackRecovery)
end

function ENT:ResetSiege()
    self.SiegePiece, self.SiegeStartedAt = nil, nil
end

// Nearest untried complete doorway around the target, weighted by the walk there and onward to the target.
function ENT:FindDoorway(target)
    local now = CurTime()
    local memory = self.DoorwayMemory or {}
    self.DoorwayMemory = memory
    local position, goal = self:GetPos(), target:GetPos()
    local best, bestCost
    for _, entity in ipairs(ents.FindInSphere(goal, self.DoorSearchRadius)) do
        if isStructure(entity) and entity:GetPieceKind() == "wall_doorway" and now >= (memory[entity] or 0) then
            local origin = entity:GetPos()
            local cost = origin:Distance(position) + origin:Distance(goal)
            if not bestCost or cost < bestCost then
                best, bestCost = entity, cost
            end
        end
    end
    return best
end

// Walk to the near side of the doorway, then straight through its 48-unit opening. Fails on timeout or a stall.
function ENT:SeekDoorway(doorway, target)
    local now = CurTime()
    self.DoorwayMemory[doorway] = now + self.DoorMemorySeconds
    self.DoorSeekCount = (self.DoorSeekCount or 0) + 1
    local position = self:GetPos()
    local front, back = doorway:LocalToWorld(Vector(0, 56, 0)), doorway:LocalToWorld(Vector(0, -56, 0))
    if back:DistToSqr(position) < front:DistToSqr(position) then
        front, back = back, front
    end
    local deadline = now + self.DoorSeekSeconds
    local mins, maxs = self:DetourHull()
    local checkAt, checkPosition = now, position
    local goal = front
    while CurTime() < deadline do
        if self.WalkerDead or not self:IsValidTarget(target) or not isStructure(doorway) then
            return false
        end
        self.WalkerState = "doorSeek"
        position = self:GetPos()
        if (position - goal):Length2DSqr() <= 24 * 24 then
            if goal == back then
                self.ProgressCheckAt = nil
                return true
            end
            goal = back
        end
        local direct = goal == back or not util.TraceHull({
            start = position, endpos = goal + Vector(0, 0, position.z - goal.z),
            mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = self
        }).Hit
        if direct then
            if self:GetActivity() ~= self:MoveActivity() then
                self:StartActivity(self:MoveActivity())
            end
            self.loco:FaceTowards(goal)
            self.loco:Approach(goal, 1)
        else
            self:MoveToward(goal, 1, true)
        end
        if CurTime() >= checkAt + 2 then
            if position:DistToSqr(checkPosition) < 16 * 16 then
                return false
            end
            checkAt, checkPosition = CurTime(), position
        end
        coroutine.yield()
    end
    return false
end

// Hit the blocking piece; after the give-up time try a reachable doorway, otherwise return to hitting.
function ENT:BesiegeStructure(target, piece, hitPos, hitNormal)
    local now = CurTime()
    if self.SiegePiece ~= piece or not self.SiegeStartedAt then
        if not self.SiegeStartedAt then
            self.SiegeCount = (self.SiegeCount or 0) + 1
        end
        self.SiegePiece = piece
        self.SiegeStartedAt = self.SiegeStartedAt or now
    end
    self.SiegeSeenAt = now
    if now - self.SiegeStartedAt >= self.SiegeGiveUpSeconds then
        self.SiegeGiveUpCount = (self.SiegeGiveUpCount or 0) + 1
        local doorway = self:FindDoorway(target)
        if doorway and self:SeekDoorway(doorway, target) then
            self:ResetSiege()
            self.BlockerCheckedAt = nil
            return
        end
        self.SiegeStartedAt = CurTime()
        self.BlockerCheckedAt = nil
        return
    end
    self:StrikeStructure(piece, hitPos, hitNormal)
end

// 120 degree forward cone plus a short all-round sense; an already-engaged target is tracked regardless of facing.
function ENT:IsWithinVision(target)
    local offset = target:GetPos() - self:GetPos()
    offset.z = 0
    local distanceSquared = offset:LengthSqr()
    if distanceSquared <= self.CloseSenseRange * self.CloseSenseRange then
        return true
    end
    if distanceSquared > self.DevelopmentTargetSearchRange * self.DevelopmentTargetSearchRange then
        return false
    end
    if target == self.CurrentTarget then
        return true
    end
    local forward = self:GetForward()
    forward.z = 0
    if forward:LengthSqr() < 0.0001 then
        return false
    end
    forward:Normalize()
    return forward:Dot(offset:GetNormalized()) >= self.VisionConeDot
end

function ENT:FindTarget()
    local selected
    local selectedDistance = math.huge
    local maximumDistanceSquared = self.DevelopmentTargetSearchRange * self.DevelopmentTargetSearchRange
    for _, playerEntity in ipairs(player.GetAll()) do
        if self:IsValidTarget(playerEntity) then
            local distance = self:GetPos():DistToSqr(playerEntity:GetPos())
            if distance <= maximumDistanceSquared and distance < selectedDistance and
                self:IsWithinVision(playerEntity) and self:CanSeeTarget(playerEntity) then
                selected = playerEntity
                selectedDistance = distance
            end
        end
    end
    return selected
end

function ENT:PlayVoice(pattern, count, level)
    self:EmitSound(string.format(pattern, math.random(count)), level or 75, math.random(90, 110))
end

function ENT:SetInvestigation(position)
    self.InvestigatePosition = Vector(position.x, position.y, position.z)
    self.InvestigateExpiresAt = CurTime() + self.InvestigateSeconds
    self.WanderGoal = nil
end

function ENT:ClearInvestigation()
    self.InvestigatePosition = nil
    self.InvestigateExpiresAt = 0
end

function ENT:HasInvestigation()
    return self.InvestigatePosition ~= nil and CurTime() < (self.InvestigateExpiresAt or 0)
end

// Heard sounds send an unengaged walker to investigate; they never grant a target directly.
function ENT:HearNoise(position, kind)
    if self.WalkerDead or IsValid(self.CurrentTarget) then
        return false
    end
    self:SetInvestigation(position)
    self.HeardNoiseCount = self.HeardNoiseCount + 1
    self.LastHeardNoise = kind
    return true
end

function ENT:ReceiveAlert(position)
    if self.WalkerDead or IsValid(self.CurrentTarget) then
        return false
    end
    self.AlertedAt = CurTime()
    self:SetInvestigation(position)
    return true
end

function ENT:OnTargetAcquired(target)
    self:ClearInvestigation()
    self.WanderGoal = nil
    if CurTime() < self.NextAlertAt then
        return
    end
    self.NextAlertAt = CurTime() + 8
    self:PlayVoice(self.SoundAlert, self.SoundAlertCount, 80)
    // Walkers woken by another walker's alert do not pass it on, so alerts never chain.
    local wokenByAlert = self.AlertedAt and CurTime() - self.AlertedAt < self.InvestigateSeconds
    if not wokenByAlert and ZM_WalkerAwareness then
        self.AlertsSent = self.AlertsSent + ZM_WalkerAwareness:Alert(self, target:GetPos())
    end
end

function ENT:RefreshTarget()
    if CurTime() < self.NextTargetSearchAt then
        return self.CurrentTarget
    end

    self.NextTargetSearchAt = CurTime() + self.DevelopmentTargetSearchInterval
    self.TargetSearchCount = self.TargetSearchCount + 1
    local previous = self.CurrentTarget
    self.CurrentTarget = self:FindTarget()
    if IsValid(self.CurrentTarget) then
        self.LastKnownTargetPosition = self.CurrentTarget:GetPos()
        self.LastKnownTargetExpiresAt = CurTime() + self.DevelopmentTargetMemorySeconds
        if self.CurrentTarget ~= previous then
            self:OnTargetAcquired(self.CurrentTarget)
        end
    end
    return self.CurrentTarget
end

function ENT:ShouldRefreshPath(goal, staticGoal)
    if not self.CurrentPath or not self.CurrentPath:IsValid() or not self.LastPathGoal then
        return true
    end
    // Fixed goals (wander, investigation, last-known position) only recompute when the goal itself changes.
    if not staticGoal and self.CurrentPath:GetAge() >= self.DevelopmentPathRefreshInterval then
        return true
    end
    return self.LastPathGoal:DistToSqr(goal) >= self.DevelopmentTargetMoveThreshold * self.DevelopmentTargetMoveThreshold
end

function ENT:UpdatePath(goal, quiet, staticGoal)
    if self:FollowDetour() then
        return true
    end
    if CurTime() < self.NextPathRetryAt then
        return false
    end
    if not self.CurrentPath then
        self.CurrentPath = Path("Follow")
        self.CurrentPath:SetMinLookAheadDistance(300)
        self.CurrentPath:SetGoalTolerance(self.DevelopmentAttackRange * 0.75)
    end
    if self:ShouldRefreshPath(goal, staticGoal) then
        self.CurrentPath:Compute(self, goal)
        self.LastPathGoal = Vector(goal.x, goal.y, goal.z)
        self.PathComputeCount = self.PathComputeCount + 1
    end
    if not self.CurrentPath:IsValid() then
        self.WalkerState = "pathFailed"
        self.NextPathRetryAt = CurTime() + self.DevelopmentPathFailureCooldown
        self.PathFailureCount = self.PathFailureCount + 1
        if not quiet then
            self:RecordWalkerLifecycle("pathFailed")
        end
        return false
    end
    self.CurrentPath:Update(self)
    if self.loco:IsStuck() or self:IsMakingNoProgress(goal) then
        self:HandleStuck()
        if self.DetourGoal then
            return true
        end
        self.NextPathRetryAt = CurTime() + self.DevelopmentPathFailureCooldown
        return false
    end
    return true
end

// Physics props are not in the navmesh, so paths can run through them; detect a stall sooner than the engine does.
function ENT:IsMakingNoProgress(goal)
    local now = CurTime()
    if self.ProgressCheckAt and now < self.ProgressCheckAt + 1 then
        return false
    end
    local position = self:GetPos()
    local stalled = self.ProgressCheckAt ~= nil and now - self.ProgressCheckAt < 2 and
        goal:DistToSqr(position) > 96 * 96 and position:DistToSqr(self.ProgressCheckPosition) < 12 * 12
    self.ProgressCheckAt, self.ProgressCheckPosition = now, position
    return stalled
end

// Walk a short sidestep directly (no path) to clear the blocking prop, then resume normal pathing.
function ENT:FollowDetour()
    if self.HoldUntil then
        if CurTime() < self.HoldUntil then
            if self:GetActivity() ~= self:RestActivity() then
                self:StartActivity(self:RestActivity())
            end
            return true
        end
        self.HoldUntil = nil
        self.ProgressCheckAt = nil
    end
    local goal = self.DetourGoal
    if not goal then
        return false
    end
    local position = self:GetPos()
    if CurTime() < (self.DetourStartsAt or 0) then
        // Yielding to another walker: stand still before stepping around it.
        if self:GetActivity() ~= self:RestActivity() then
            self:StartActivity(self:RestActivity())
        end
        return true
    end
    if self:GetActivity() ~= self:MoveActivity() then
        self:StartActivity(self:MoveActivity())
    end
    if CurTime() >= self.DetourExpiresAt or (position - goal):Length2DSqr() <= 20 * 20 then
        self.DetourGoal = nil
        self.ProgressCheckAt = nil
        return false
    end
    self.loco:FaceTowards(goal)
    self.loco:Approach(goal, 1)
    return true
end

// Telegraphed swing: the wind-up gesture plays first and the single hit lands only if the target is still in reach,
// so stepping away during the wind-up dodges it. Runs inside the behaviour coroutine.
function ENT:AttackTarget(target)
    if CurTime() < self.NextAttackAt or not self:IsValidTarget(target) or not self:CanReachTarget(target) or
        self:GetRangeTo(target) > self.DevelopmentAttackRange then
        return
    end

    self.NextAttackAt = CurTime() + math.max(self.DevelopmentAttackInterval, self.AttackWindup + self.AttackRecovery)
    self.AttackCount = self.AttackCount + 1
    self.WalkerState = "attackWindup"
    self.loco:FaceTowards(target:GetPos())
    self:AddGesture(self.AttackGesture)
    self:PlayVoice(self.SoundAttack, self.SoundAttackCount, 75)
    coroutine.wait(self.AttackWindup)
    if self.WalkerDead then
        return
    end

    if self:IsValidTarget(target) and self:GetRangeTo(target) <= self.DevelopmentAttackRange + self.AttackReachTolerance and
        self:CanReachTarget(target) then
        local damage = DamageInfo()
        damage:SetDamage(self.DevelopmentAttackDamage)
        damage:SetDamageType(DMG_SLASH)
        damage:SetAttacker(self)
        damage:SetInflictor(self)
        target:TakeDamageInfo(damage)
        self.AttackHitCount = (self.AttackHitCount or 0) + 1
        self:PlayVoice(self.SoundHit, self.SoundHitCount, 75)
    else
        self.AttackMissCount = (self.AttackMissCount or 0) + 1
        self:PlayVoice(self.SoundMiss, self.SoundMissCount, 70)
    end
    self.WalkerState = "attackRecovery"
    coroutine.wait(self.AttackRecovery)
end

function ENT:MoveActivity()
    return self.GoreCrawler and self.CrawlActivity or self.WalkActivity
end

function ENT:RestActivity()
    return self.GoreCrawler and self.CrawlActivity or self.IdleActivity
end

// base_nextbot only drives move_x/move_y for ACT_WALK/ACT_RUN. A crawler keeps the forward swim blend (an
// inclined drag along the ground) and scales playback with speed so it slows to a twitch when still.
function ENT:BodyUpdate()
    if self.GoreCrawler then
        self:SetPoseParameter("move_x", 1)
        self:SetPoseParameter("move_y", 0)
        self:SetPlaybackRate(math.Clamp(self.loco:GetVelocity():Length2D() / 30, 0.2, 1.5))
        self:FrameAdvance()
        return
    end
    if self:GetActivity() == self.WalkActivity then
        self:BodyMoveXY()
        return
    end
    self:FrameAdvance()
end

function ENT:ChaseTarget(target)
    self:StartActivity(self:MoveActivity())
    self.loco:SetDesiredSpeed(self.WalkSpeed or self.DevelopmentWalkSpeed)

    while self:IsValidTarget(target) do
        if self:RefreshTarget() ~= target then
            return
        end
        self:RecoverIfAirborne()
        if self:CanSeeTarget(target) then
            self.LastKnownTargetPosition = target:GetPos()
            self.LastKnownTargetExpiresAt = CurTime() + self.DevelopmentTargetMemorySeconds
        end
        local piece, hitPos, hitNormal = self:FindStructureBlocker(target)
        if piece then
            self:BesiegeStructure(target, piece, hitPos, hitNormal)
            if self.WalkerDead then
                return
            end
        elseif self:GetRangeTo(target) <= self.DevelopmentAttackRange then
            self:AttackTarget(target)
            coroutine.wait(0.1)
        else
            if self.SiegeStartedAt and CurTime() > (self.SiegeSeenAt or 0) + 2 then
                self:ResetSiege()
            end
            self.WalkerState = "pursue"
            if not self:UpdatePath(target:GetPos()) then
                return
            end
            coroutine.yield()
        end
    end
end

function ENT:MoveToward(goal, speedScale, quiet)
    if self:GetActivity() ~= self:MoveActivity() then
        self:StartActivity(self:MoveActivity())
    end
    self.loco:SetDesiredSpeed((self.WalkSpeed or self.DevelopmentWalkSpeed) * (speedScale or 1))
    return self:UpdatePath(goal, quiet, true)
end

// Safety net for a hull the engine has ejected upward: return it to the nearest walkable nav point.
function ENT:RecoverIfAirborne()
    if CurTime() < (self.NextAirborneCheckAt or 0) then
        return
    end
    self.NextAirborneCheckAt = CurTime() + 0.25
    if not navmesh or self.loco:IsOnGround() then
        return
    end
    local position = self:GetPos()
    local area = navmesh.GetNearestNavArea(position, false, 1024, false, true)
    if not IsValid(area) then
        return
    end
    local point = area:GetClosestPointOnArea(position)
    if point and position.z - point.z > 160 then
        self.loco:SetVelocity(vector_origin)
        self:SetPos(point + Vector(0, 0, 4))
        self.CurrentPath = nil
        self.LastPathGoal = nil
        self.AirborneRecoveries = (self.AirborneRecoveries or 0) + 1
        self:RecordWalkerLifecycle("airborneRecovered", { height = math.floor(position.z - point.z) })
    end
end

// Diagnostic: capture what launched a walker so sky ejections can be attributed.
function ENT:OnLeaveGround(ground)
    local velocity = self.loco:GetVelocity()
    if velocity.z > 250 then
        self.UpwardLaunches = (self.UpwardLaunches or 0) + 1
        self:RecordWalkerLifecycle("upwardLaunch", {
            velocityZ = math.floor(velocity.z),
            state = tostring(self.WalkerState),
            ground = IsValid(ground) and ground:GetClass() or tostring(ground)
        })
    end
end

function ENT:ScheduleWanderPause()
    self.WanderGoal = nil
    self.NextWanderAt = CurTime() + math.Rand(self.WanderPauseMin, self.WanderPauseMax)
end

local function closestNavPoint(position, radius)
    if not navmesh then return nil end
    local area = navmesh.GetNearestNavArea(position, false, radius)
    return IsValid(area) and area:GetClosestPointOnArea(position) or nil
end

// Wander goals stay near home; with grouping enabled, idle walkers sometimes drift beside an idle neighbour.
function ENT:PickWanderGoal()
    local home = self.HomePosition or self:GetPos()
    local awareness = ZM_WalkerAwareness
    if awareness and awareness:IsGroupingEnabled() and math.random() < 0.5 then
        local candidates = {}
        for _, other in ipairs(awareness:FindWalkersNear(self:GetPos(), self.GroupingRadius, self.WalkerSourceCellId)) do
            if other ~= self and not other:IsWalkerEngaged() and
                other:GetPos():DistToSqr(home) <= (self.WanderRadius * 2) ^ 2 then
                candidates[#candidates + 1] = other
            end
        end
        if #candidates > 0 then
            local neighbour = candidates[math.random(#candidates)]
            local angle = math.Rand(0, math.pi * 2)
            local distance = math.Rand(64, 128)
            local point = closestNavPoint(neighbour:GetPos() + Vector(math.cos(angle) * distance, math.sin(angle) * distance, 0), 128)
            if point then
                self.GroupingMoves = (self.GroupingMoves or 0) + 1
                return point
            end
        end
    end
    if not navmesh then return nil end
    local areas = navmesh.Find(home, self.WanderRadius, 64, 64)
    if type(areas) ~= "table" or #areas == 0 then
        return nil
    end
    local area = areas[math.random(#areas)]
    return IsValid(area) and area:GetRandomPoint() or nil
end

// Cosmetic shove between idle neighbours: a swing and a push, never damage, rewards or ticket changes.
function ENT:TryScuffle()
    local awareness = ZM_WalkerAwareness
    if not awareness or not awareness:IsInfightingEnabled() or CurTime() < (self.NextScuffleAt or 0) or
        math.random() > self.ScuffleChance then
        return false
    end
    for _, other in ipairs(awareness:FindWalkersNear(self:GetPos(), self.ScuffleRange, self.WalkerSourceCellId)) do
        if other ~= self and not other:IsWalkerEngaged() and CurTime() >= (other.NextScuffleAt or 0) and other.loco and
            other.loco:IsOnGround() then
            self.NextScuffleAt = CurTime() + self.ScuffleCooldown
            other.NextScuffleAt = self.NextScuffleAt
            self.loco:FaceTowards(other:GetPos())
            self:AddGesture(self.AttackGesture)
            self:PlayVoice(self.SoundMiss, self.SoundMissCount, 65)
            local push = other:GetPos() - self:GetPos()
            push.z = 0
            if push:LengthSqr() > 0.0001 then
                push:Normalize()
                other.loco:SetVelocity(push * 140)
            end
            self.ScuffleCount = self.ScuffleCount + 1
            return true
        end
    end
    return false
end

function ENT:MaybeMoan()
    if CurTime() >= self.NextMoanAt then
        self.NextMoanAt = CurTime() + math.Rand(15, 40)
        self:PlayVoice(self.SoundIdle, self.SoundIdleCount, 65)
    end
end

function ENT:InvestigateStep()
    local goal = self.InvestigatePosition
    if self:GetPos():DistToSqr(goal) <= 80 * 80 then
        self:ClearInvestigation()
        self:ScheduleWanderPause()
        return
    end
    self.WalkerState = "investigate"
    if not self:MoveToward(goal, 1, true) then
        self:ClearInvestigation()
        self:ScheduleWanderPause()
    end
end

function ENT:IdleStep()
    self:MaybeMoan()
    if self.WanderGoal then
        if CurTime() <= self.WanderExpiresAt and self:GetPos():DistToSqr(self.WanderGoal) > 48 * 48 and
            self:MoveToward(self.WanderGoal, self.WanderSpeedScale, true) then
            self.WalkerState = "wander"
            return
        end
        self:ScheduleWanderPause()
    end

    self.WalkerState = "idle"
    if self:GetActivity() ~= self:RestActivity() then
        self:StartActivity(self:RestActivity())
    end
    if not self:TryScuffle() and CurTime() >= self.NextWanderAt then
        self.WanderGoal = self:PickWanderGoal()
        self.WanderExpiresAt = CurTime() + self.WanderTimeout
        if not self.WanderGoal then
            self:ScheduleWanderPause()
        end
    end
    coroutine.wait(0.25)
end

function ENT:RunBehaviour()
    self.HomePosition = self.HomePosition or self:GetPos()
    while true do
        if self.WalkerDead then
            return
        end
        self:RecoverIfAirborne()
        local target = self:RefreshTarget()
        if target then
            self.WalkerState = "pursue"
            self:ChaseTarget(target)
        elseif self.LastKnownTargetPosition and CurTime() < self.LastKnownTargetExpiresAt then
            self.WalkerState = "targetLost"
            if not self:MoveToward(self.LastKnownTargetPosition, 1) then
                self.LastKnownTargetPosition = nil
                self.WanderGoal = nil
                self.NextWanderAt = CurTime() + 1
            end
        elseif self:HasInvestigation() then
            self:InvestigateStep()
        else
            if self.LastKnownTargetPosition then
                // Memory lapsed: head back toward the spawn area on the next wander.
                self.LastKnownTargetPosition = nil
                self.WanderGoal = nil
                self.NextWanderAt = CurTime() + 1
            end
            self:ClearInvestigation()
            self:IdleStep()
        end
        coroutine.yield()
    end
end

function ENT:IsWalkerEngaged()
    if IsValid(self.CurrentTarget) and self:IsValidTarget(self.CurrentTarget) then
        return true
    end
    if self:HasInvestigation() then
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
    self.ProgressCheckAt = nil
    self.DetourGoal = nil
    local blockingWalker = self:FindBlockingWalker()
    local detour = self:FindDetourPoint()
    if detour then
        // Keep the target and memory: only the route was blocked.
        local yieldSeconds = blockingWalker and math.Rand(0.4, 1.2) or 0
        if yieldSeconds > 0 then
            self.YieldCount = (self.YieldCount or 0) + 1
        end
        self.DetourGoal = detour
        self.DetourStartsAt = CurTime() + yieldSeconds
        self.DetourExpiresAt = self.DetourStartsAt + 1.5
        self.DetourCount = (self.DetourCount or 0) + 1
        return
    end
    if blockingWalker then
        // Packed in by other walkers: wait for the crowd to shift instead of forgetting the target.
        self.HoldUntil = CurTime() + math.Rand(0.5, 1.0)
        self.HoldCount = (self.HoldCount or 0) + 1
        return
    end
    if self:IsValidTarget(self.CurrentTarget) and self:FindStructureBlocker(self.CurrentTarget) then
        // Walled in by a player structure: keep the target so the chase loop strikes the piece.
        self.HoldUntil = CurTime() + 0.25
        return
    end
    self.CurrentTarget = nil
    self.LastKnownTargetPosition = nil
    self.LastKnownTargetExpiresAt = 0
    self.WanderGoal = nil
    self:ClearInvestigation()
end

function ENT:DetourHull()
    local mins, maxs = self:OBBMins(), self:OBBMaxs()
    return Vector(mins.x + 2, mins.y + 2, mins.z + 18), Vector(maxs.x - 2, maxs.y - 2, maxs.z)
end

function ENT:FlatForward()
    local forward = self:GetForward()
    forward.z = 0
    forward:Normalize()
    return forward
end

function ENT:FindBlockingWalker()
    local position = self:GetPos()
    local mins, maxs = self:DetourHull()
    local trace = util.TraceHull({
        start = position, endpos = position + self:FlatForward() * 32,
        mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = self
    })
    local hit = trace.Entity
    return IsValid(hit) and hit:GetClass() == "zn_walker_zombie" and hit or nil
end

function ENT:FindDetourPoint()
    if not navmesh then
        return nil
    end
    local position = self:GetPos()
    local forward = self:FlatForward()
    local right = Vector(forward.y, -forward.x, 0)
    local first = math.random() < 0.5 and 1 or -1
    local mins, maxs = self:DetourHull()
    // Lateral first, then forward-diagonal for progress, then backing off diagonally out of a pocket.
    for _, offset in ipairs({ { 72, -16 }, { 56, 40 }, { 56, -56 } }) do
        for _, sign in ipairs({ first, -first }) do
            local candidate = position + right * (offset[1] * sign) + forward * offset[2]
            local area = navmesh.GetNearestNavArea(candidate, false, 96)
            local point = IsValid(area) and area:GetClosestPointOnArea(candidate) or nil
            if point and (point - position):Length2DSqr() >= 32 * 32 then
                local trace = util.TraceHull({
                    start = position, endpos = point + Vector(0, 0, position.z - point.z),
                    mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = self
                })
                if not trace.Hit then
                    return point
                end
            end
        end
    end
    return nil
end

function ENT:GetWalkerPerformanceStats()
    return {
        state = self.WalkerState,
        targetSearches = self.TargetSearchCount,
        pathComputes = self.PathComputeCount,
        pathFailures = self.PathFailureCount,
        stuckRecoveries = self.StuckRecoveryCount,
        attacks = self.AttackCount,
        attackHits = self.AttackHitCount or 0,
        attackMisses = self.AttackMissCount or 0,
        noisesHeard = self.HeardNoiseCount,
        alertsSent = self.AlertsSent,
        groupingMoves = self.GroupingMoves or 0,
        scuffles = self.ScuffleCount,
        airborneRecoveries = self.AirborneRecoveries or 0,
        upwardLaunches = self.UpwardLaunches or 0,
        detours = self.DetourCount or 0,
        yields = self.YieldCount or 0,
        holds = self.HoldCount or 0,
        structureStrikes = self.StructureStrikeCount or 0,
        structureBreaks = self.StructureBreakCount or 0,
        sieges = self.SiegeCount or 0,
        siegeGiveUps = self.SiegeGiveUpCount or 0,
        doorSeeks = self.DoorSeekCount or 0,
        nextPathRetryAt = self.NextPathRetryAt
    }
end

// Runs before EntityTakeDamage, so ZM_Enemies can apply the headshot rule to the same bullet.
function ENT:OnTraceAttack(damage, _, trace)
    if self.WalkerDead or not trace then
        return
    end
    if trace.HitGroup == HITGROUP_HEAD then
        self.HeadHitTick = engine.TickCount()
    end
    if ZM_Gore then
        ZM_Gore:RecordTraceAttack(self, damage, trace)
    end
end

// The engine subtracts health after OnInjured and then calls OnKilled itself; only observe the hit here.
function ENT:OnInjured(damage)
    if self.WalkerDead then
        return
    end
    if ZM_Gore then
        ZM_Gore:HandleDamage(self, damage, self:Health() - math.max(0, damage:GetDamage()) <= 0)
    end
end

// The corpse keeps the zombie's model, skin and pose; severed regions are hidden on it by the client gore mask.
function ENT:CreateCorpse()
    local corpse = ents.Create("prop_ragdoll")
    if IsValid(corpse) then
        corpse:SetModel(self:GetModel())
        corpse:SetSkin(self:GetSkin())
        corpse:SetNWString("ZM_ClothingCorpse", util.TableToJSON(ZM_Clothing:GetEntitySelection(self)))
        for index in ipairs(self:GetMaterials()) do
            corpse:SetSubMaterial(index - 1, self:GetSubMaterial(index - 1))
        end
        corpse:SetPos(self:GetPos())
        corpse:SetAngles(self:GetAngles())
        corpse:Spawn()
        if not IsValid(corpse) then
            corpse = nil
        else
            corpse:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            local velocity = self.loco and self.loco:GetVelocity() or vector_origin
            for index = 0, corpse:GetPhysicsObjectCount() - 1 do
                local physics = corpse:GetPhysicsObjectNum(index)
                local position, angles = self:GetBonePosition(corpse:TranslatePhysBoneToBone(index))
                if IsValid(physics) and position then
                    physics:SetPos(position)
                    physics:SetAngles(angles)
                    physics:SetVelocity(velocity)
                    physics:Wake()
                end
            end
        end
    end
    return corpse
end

function ENT:ConfigureCorpse(corpse, lootable)
    if not IsValid(corpse) then
        return false
    end
    corpse:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    if lootable then
        return true
    end
    if corpse.CorpseFadeScheduled then
        return true
    end

    corpse.CorpseFadeScheduled = true
    timer.Simple(corpseFadeDelay, function()
        if not IsValid(corpse) or corpse:GetNWBool("ZM_LootSpot", false) then
            return
        end
        local originalColor = corpse:GetColor()
        local fadeStartedAt = CurTime()
        corpse:SetRenderMode(RENDERMODE_TRANSALPHA)

        local function fade()
            if not IsValid(corpse) then
                return
            end
            if corpse:GetNWBool("ZM_LootSpot", false) then
                corpse:SetRenderMode(RENDERMODE_NORMAL)
                corpse:SetColor(originalColor)
                return
            end

            local progress = math.Clamp((CurTime() - fadeStartedAt) / corpseFadeDuration, 0, 1)
            if progress >= 1 then
                corpse:Remove()
                return
            end
            corpse:SetColor(Color(originalColor.r, originalColor.g, originalColor.b, math.floor(originalColor.a * (1 - progress))))
            timer.Simple(corpseFadeInterval, fade)
        end

        fade()
    end)
    return true
end

function ENT:OnKilled(damage)
    if self.WalkerDead then
        return
    end
    self.WalkerDead = true
    self:ResolveWalkerTicket(true)
    local reward
    if self.EnemyId and ZM_Enemies then
        local _, killReward = ZM_Enemies:OnEnemyKilled(self, damage:GetAttacker())
        reward = killReward
    end
    local corpse = self:CreateCorpse()
    local lootable = false
    if reward and reward.item then
        local registered, registrationError = ZM_Enemies:RegisterCorpseLoot(corpse, reward.item)
        if registered then
            lootable = true
        else
            ErrorNoHalt("[ZombieSim] Could not register enemy corpse loot: " .. tostring(registrationError) .. "\n")
        end
    end
    self:ConfigureCorpse(corpse, lootable)
    if ZM_Gore then
        ZM_Gore:ApplyCorpse(self, corpse)
    end
    self:Remove()
end

function ENT:OnRemove()
    if not self.WalkerTicketAcknowledged then
        self:RecordWalkerLifecycle("removedBeforeAcknowledgement")
        return
    end
    self:ResolveWalkerTicket(self.WalkerDead == true)
end