// Server-owned Walker awareness: player camera views, noise events and limited alert propagation.
// Walkers decide their own response; this module only routes validated stimuli to them.
ZM_WalkerAwareness = ZM_WalkerAwareness or {}
local Awareness = ZM_WalkerAwareness

Awareness.WalkerClass = "zn_walker_zombie"
Awareness.CameraMaxOffset = 720
Awareness.CameraFreshSeconds = 2
Awareness.CameraMinInterval = 0.1
Awareness.CameraVisibleRange = 6000
Awareness.CameraConeDot = 0.2
Awareness.EyeFallbackRange = 1600
Awareness.AlertRadius = 400
Awareness.Noise = {
    gunshot = { radius = 1400, cooldown = 0.25 },
    sprint = { radius = 350, cooldown = 0.4 },
    melee = { radius = 450, cooldown = 0.3 },
    breakage = { radius = 700, cooldown = 0.2 }
}
Awareness.VisibilityDeferrals = Awareness.VisibilityDeferrals or 0

util.AddNetworkString("ZM.WalkerCameraView")

// Exploratory Phase B behaviours; both default on and can be disabled without code changes.
local groupingConVar = CreateConVar("zombiesim_walker_grouping", "1", FCVAR_ARCHIVE,
    "Idle Walkers drift toward nearby idle Walkers.", 0, 1)
local infightingConVar = CreateConVar("zombiesim_walker_infighting", "1", FCVAR_ARCHIVE,
    "Idle Walkers occasionally shove a neighbour (cosmetic, no damage).", 0, 1)

function Awareness:IsGroupingEnabled()
    return groupingConVar:GetBool()
end

function Awareness:IsInfightingEnabled()
    return infightingConVar:GetBool()
end

local function isFiniteVector(value)
    return isvector(value) and value.x == value.x and value.y == value.y and value.z == value.z and
        math.abs(value.x) < 65536 and math.abs(value.y) < 65536 and math.abs(value.z) < 65536
end

// Accepts a camera origin only when it lies within the third-person camera's reach of the living player.
function Awareness:AcceptCameraView(playerEntity, origin, forward, now)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:Alive() then
        return false
    end
    if not isFiniteVector(origin) or not isFiniteVector(forward) then
        return false
    end
    local previous = playerEntity.ZM_CameraView
    if previous and now - previous.receivedAt < self.CameraMinInterval then
        return false
    end
    if origin:DistToSqr(playerEntity:EyePos()) > self.CameraMaxOffset * self.CameraMaxOffset then
        return false
    end
    local length = forward:Length()
    if length < 0.5 or length > 1.5 then
        return false
    end
    playerEntity.ZM_CameraView = { origin = origin, forward = forward / length, receivedAt = now }
    return true
end

function Awareness:GetCameraView(playerEntity, now)
    local view = playerEntity.ZM_CameraView
    if view and now - view.receivedAt <= self.CameraFreshSeconds then
        return view
    end
end

net.Receive("ZM.WalkerCameraView", function(_, playerEntity)
    local origin = net.ReadVector()
    local forward = net.ReadNormal()
    Awareness:AcceptCameraView(playerEntity, origin, forward, CurTime())
end)

// The server PVS follows the eye; the high third-person camera can see past walls the eye cannot.
hook.Add("SetupPlayerVisibility", "ZM.WalkerAwareness.CameraPVS", function(target)
    if not IsValid(target) or not target:Alive() then return end
    local view = Awareness:GetCameraView(target, CurTime())
    if view then
        AddOriginToPVS(view.origin)
    end
end)

local function isSameCell(entity, playerEntity)
    if entity.WalkerSourceCellId == nil then return true end
    local cell = playerEntity:GetWorldCell()
    return cell ~= nil and cell.id == entity.WalkerSourceCellId
end

// True when an eligible player's camera (or eye, without a camera report) has a clear view of any sample point.
function Awareness:CanPlayerSeePoints(playerEntity, points, now)
    local view = self:GetCameraView(playerEntity, now)
    local origin, range, forward
    if view then
        origin, range, forward = view.origin, self.CameraVisibleRange, view.forward
    else
        origin, range = playerEntity:EyePos(), self.EyeFallbackRange
    end
    for _, target in ipairs(points) do
        local offset = target - origin
        local distance = offset:Length()
        if distance <= range and (not forward or distance <= 1 or forward:Dot(offset / distance) >= self.CameraConeDot) then
            local trace = util.TraceLine({
                start = origin,
                endpos = target,
                mask = MASK_SOLID_BRUSHONLY
            })
            if not trace.Hit or trace.Fraction >= 0.999 then
                return true
            end
        end
    end
    return false
end

local function entitySamplePoints(entity)
    local base = entity:GetPos()
    return { entity:WorldSpaceCenter(), base + Vector(0, 0, 64), base + Vector(0, 0, 8) }
end

function Awareness:IsVisibleToPlayer(entity, playerEntity, now)
    if not IsValid(playerEntity) or playerEntity:IsBot() or not playerEntity:Alive() or not isSameCell(entity, playerEntity) then
        return false
    end
    return self:CanPlayerSeePoints(playerEntity, entitySamplePoints(entity), now)
end

// Spawn-time check: a standing hull at this ground position would be in view of any living player's camera or eye.
function Awareness:IsPositionVisibleToAnyPlayer(position)
    local points = { position + Vector(0, 0, 8), position + Vector(0, 0, 36), position + Vector(0, 0, 64) }
    local now = CurTime()
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and not playerEntity:IsBot() and playerEntity:Alive() and
            self:CanPlayerSeePoints(playerEntity, points, now) then
            return true
        end
    end
    return false
end

function Awareness:IsVisibleToAnyPlayer(entity)
    if not IsValid(entity) then return false end
    local now = CurTime()
    for _, playerEntity in ipairs(player.GetAll()) do
        if self:IsVisibleToPlayer(entity, playerEntity, now) then
            return true
        end
    end
    return false
end

function Awareness:FindWalkersNear(position, radius, cellId)
    local result = {}
    for _, entity in ipairs(ents.FindInSphere(position, radius)) do
        if IsValid(entity) and entity:GetClass() == self.WalkerClass and not entity.WalkerDead and
            (cellId == nil or entity.WalkerSourceCellId == cellId) then
            result[#result + 1] = entity
        end
    end
    return result
end

local function playerCellId(playerEntity)
    local cell = IsValid(playerEntity) and playerEntity.GetWorldCell and playerEntity:GetWorldCell()
    return cell and cell.id
end

// Routes a heard sound to walkers in range; sound travels through walls, so no line of sight is required.
function Awareness:EmitNoise(kind, position, source)
    local definition = self.Noise[kind]
    if not definition or not isvector(position) or not IsValid(source) or not source:IsPlayer() then
        return 0
    end
    if source:IsFlagSet(FL_NOTARGET) or (ZM_AFK and ZM_AFK:IsProtected(source)) then
        return 0
    end
    local now = CurTime()
    source.ZM_WalkerNoiseAt = source.ZM_WalkerNoiseAt or {}
    if now < (source.ZM_WalkerNoiseAt[kind] or 0) then
        return 0
    end
    source.ZM_WalkerNoiseAt[kind] = now + definition.cooldown
    local heard = 0
    for _, walker in ipairs(self:FindWalkersNear(position, definition.radius, playerCellId(source))) do
        if walker.HearNoise and walker:HearNoise(position, kind) then
            heard = heard + 1
        end
    end
    return heard
end

// One-shot alert: walkers woken here do not alert others, so alerts never chain.
function Awareness:Alert(fromWalker, position)
    if not IsValid(fromWalker) or not isvector(position) then return 0 end
    local woken = 0
    for _, walker in ipairs(self:FindWalkersNear(fromWalker:GetPos(), self.AlertRadius, fromWalker.WalkerSourceCellId)) do
        if walker ~= fromWalker and walker.ReceiveAlert and walker:ReceiveAlert(position) then
            woken = woken + 1
        end
    end
    return woken
end

local function shooterOf(entity)
    if not IsValid(entity) then return nil end
    if entity:IsPlayer() then return entity end
    local owner = entity:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then return owner end
end

hook.Add("EntityFireBullets", "ZM.WalkerAwareness.Gunshot", function(entity, data)
    local shooter = shooterOf(entity)
    if shooter then
        Awareness:EmitNoise("gunshot", shooter:GetPos(), shooter)
    end
end)

hook.Add("PlayerFootstep", "ZM.WalkerAwareness.Sprint", function(playerEntity, position)
    if IsValid(playerEntity) and playerEntity:IsSprinting() and playerEntity:GetVelocity():Length2DSqr() > 10000 then
        Awareness:EmitNoise("sprint", position, playerEntity)
    end
end)

hook.Add("EntityTakeDamage", "ZM.WalkerAwareness.Melee", function(target, damage)
    if not damage:IsDamageType(DMG_CLUB) and not damage:IsDamageType(DMG_SLASH) then return end
    local attacker = damage:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() then
        local position = damage:GetDamagePosition()
        if position:IsZero() and IsValid(target) then position = target:GetPos() end
        Awareness:EmitNoise("melee", position, attacker)
    end
end)

hook.Add("PropBreak", "ZM.WalkerAwareness.Breakage", function(attacker, prop)
    if IsValid(attacker) and attacker:IsPlayer() and IsValid(prop) then
        Awareness:EmitNoise("breakage", prop:GetPos(), attacker)
    end
end)
