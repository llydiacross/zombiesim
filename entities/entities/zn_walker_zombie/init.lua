AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local collisionMins = Vector(-16, -16, 0)
local collisionMaxs = Vector(16, 16, 72)
local corpseFadeDelay = 60
local corpseFadeDuration = 5
local corpseFadeInterval = 0.1
local validModels

local function pickModel(entity)
    if not validModels then
        validModels = {}
        for _, model in ipairs(entity.Models or {}) do
            if util.IsValidModel(model) then
                table.insert(validModels, model)
            end
        end
    end
    return validModels[math.random(#validModels)] or entity.Model
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
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or target:IsFlagSet(FL_NOTARGET) then
        return false
    end
    if ZM_AFK and ZM_AFK:IsProtected(target) then
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
    self:AddGesture(self.AttackGesture)
    local damage = DamageInfo()
    damage:SetDamage(self.DevelopmentAttackDamage)
    damage:SetDamageType(DMG_SLASH)
    damage:SetAttacker(self)
    damage:SetInflictor(self)
    target:TakeDamageInfo(damage)
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
            self:StartActivity(self:MoveActivity())
            self.loco:SetDesiredSpeed(self.WalkSpeed or self.DevelopmentWalkSpeed)
            if self:UpdatePath(self.LastKnownTargetPosition) then
                coroutine.yield()
            else
                self.LastKnownTargetPosition = nil
            end
        else
            self.WalkerState = "idle"
            if self:GetActivity() ~= self:RestActivity() then
                self:StartActivity(self:RestActivity())
            end
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