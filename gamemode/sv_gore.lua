// Server-authoritative dismemberment. Decides which region a hit severs, converts legless zombies into crawlers,
// carries severed regions onto corpses, and tells clients to spawn the cosmetic limbs and blood (cl_gore.lua).
ZM_Gore = ZM_Gore or {}
local Gore = ZM_Gore

util.AddNetworkString("ZM.Gore")

Gore.EventWound = 1
Gore.EventSever = 2
Gore.MaskNetworkKey = "ZM_GoreSevered"
Gore.CrawlerBodyOffset = Vector(0, 0, -30)
Gore.CrawlerSpeedScale = 0.5
Gore.CrawlerMins = Vector(-16, -16, 0)
Gore.CrawlerMaxs = Vector(16, 16, 32)
Gore.ChanceScale = 1.6
Gore.KillingBlowScale = 1.5
Gore.TorsoChanceScale = 0.8
Gore.MaximumChance = 0.85
Gore.DefaultFactor = 0.6

// id is the network region id; bit is the ZM_GoreSevered mask bit. Torso splits share the legs bit because a
// split leaves the same legless corpse as a crawler. The head pops (blood plus the severed head) only on a kill.
Gore.Regions = {
    leftArm = { id = 1, bit = 1, threshold = 0.25 },
    rightArm = { id = 2, bit = 2, threshold = 0.25 },
    legs = { id = 3, bit = 4, threshold = 0.4 },
    head = { id = 4, bit = 8, threshold = 0.5, deathOnly = true },
    torso = { id = 5, bit = 4, deathOnly = true, torso = true }
}

local hitGroupRegions = {
    [HITGROUP_HEAD] = "head",
    [HITGROUP_CHEST] = "torso",
    [HITGROUP_STOMACH] = "torso",
    [HITGROUP_LEFTARM] = "leftArm",
    [HITGROUP_RIGHTARM] = "rightArm",
    [HITGROUP_LEFTLEG] = "legs",
    [HITGROUP_RIGHTLEG] = "legs"
}

// Bones used to resolve hits without a hitgroup (melee).
local boneRegions = {
    ["ValveBiped.Bip01_L_UpperArm"] = "leftArm", ["ValveBiped.Bip01_L_Forearm"] = "leftArm", ["ValveBiped.Bip01_L_Hand"] = "leftArm",
    ["ValveBiped.Bip01_R_UpperArm"] = "rightArm", ["ValveBiped.Bip01_R_Forearm"] = "rightArm", ["ValveBiped.Bip01_R_Hand"] = "rightArm",
    ["ValveBiped.Bip01_L_Thigh"] = "legs", ["ValveBiped.Bip01_L_Calf"] = "legs", ["ValveBiped.Bip01_L_Foot"] = "legs",
    ["ValveBiped.Bip01_R_Thigh"] = "legs", ["ValveBiped.Bip01_R_Calf"] = "legs", ["ValveBiped.Bip01_R_Foot"] = "legs",
    ["ValveBiped.Bip01_Spine1"] = "torso", ["ValveBiped.Bip01_Spine2"] = "torso",
    ["ValveBiped.Bip01_Head1"] = "head"
}

local damageTypeFactors = {
    { type = DMG_BUCKSHOT, factor = 2.5 },
    { type = DMG_SLASH, factor = 1.8 },
    { type = DMG_CLUB, factor = 1.2 }
}

function Gore.RegionForHitGroup(hitGroup)
    return hitGroupRegions[hitGroup]
end

function Gore.IsBoss(entity)
    return IsValid(entity) and (entity:GetClass() == "zn_boss_zombie" or entity.BossInstanceId ~= nil)
end

function Gore.GetMask(entity)
    return IsValid(entity) and entity:GetNWInt(Gore.MaskNetworkKey, 0) or 0
end

function Gore.HasRegion(mask, region)
    local definition = Gore.Regions[region]
    return definition ~= nil and bit.band(mask, definition.bit) ~= 0
end

// The region nearest a world position (used for melee, which carries no hitgroup).
function Gore.NearestBoneRegion(entity, position)
    if not IsValid(entity) or not position then
        return nil
    end
    local bestRegion, bestDistance
    for boneName, region in pairs(boneRegions) do
        local bone = entity:LookupBone(boneName)
        local bonePosition = bone and entity:GetBonePosition(bone)
        if bonePosition then
            local distance = bonePosition:DistToSqr(position)
            if not bestDistance or distance < bestDistance then
                bestRegion, bestDistance = region, distance
            end
        end
    end
    return bestRegion
end

// Bullets record their hitgroup in the trace attack of the same tick; the group carrying the most damage wins.
function Gore:RecordTraceAttack(entity, damage, trace)
    if not IsValid(entity) or not trace then
        return
    end
    local tick = engine.TickCount()
    if entity.GoreTraceTick ~= tick then
        entity.GoreTraceTick = tick
        entity.GoreTraceDamage = {}
    end
    local region = Gore.RegionForHitGroup(trace.HitGroup)
    if region then
        entity.GoreTraceDamage[region] = (entity.GoreTraceDamage[region] or 0) + math.max(0, damage:GetDamage())
        entity.GoreTraceHitPos = trace.HitPos
    end
end

function Gore:ResolveRegion(entity, damage)
    if entity.GoreTraceTick == engine.TickCount() and entity.GoreTraceDamage then
        local bestRegion, bestDamage
        for region, amount in pairs(entity.GoreTraceDamage) do
            if not bestDamage or amount > bestDamage then
                bestRegion, bestDamage = region, amount
            end
        end
        if bestRegion then
            return bestRegion, entity.GoreTraceHitPos
        end
    end
    local position = damage:GetDamagePosition()
    if position and position ~= vector_origin then
        return Gore.NearestBoneRegion(entity, position) or "torso", position
    end
    return "torso", entity:WorldSpaceCenter()
end

// The inflictor or active weapon's GoreSeverFactor, otherwise a damage-type fallback.
function Gore.WeaponFactor(damage)
    for _, source in ipairs({ damage:GetInflictor(), damage:GetAttacker() }) do
        if IsValid(source) then
            if tonumber(source.GoreSeverFactor) then
                return tonumber(source.GoreSeverFactor)
            end
            if source.GetActiveWeapon then
                local weapon = source:GetActiveWeapon()
                if IsValid(weapon) and tonumber(weapon.GoreSeverFactor) then
                    return tonumber(weapon.GoreSeverFactor)
                end
            end
        end
    end
    for _, entry in ipairs(damageTypeFactors) do
        if damage:IsDamageType(entry.type) then
            return entry.factor
        end
    end
    return Gore.DefaultFactor
end

// Chance that a hit severs a region. fraction is this hit's damage over max health; accumulated is the region's
// total damage fraction including this hit. Living severs need accumulated damage past the region's threshold.
function Gore.SeverChance(region, fraction, accumulated, factor, killing)
    local definition = Gore.Regions[region]
    if not definition or (definition.deathOnly and not killing) then
        return 0
    end
    fraction = math.Clamp(tonumber(fraction) or 0, 0, 1)
    factor = math.max(0, tonumber(factor) or 0)
    if definition.torso then
        return math.min(Gore.MaximumChance, fraction * factor * Gore.TorsoChanceScale)
    end
    if not killing and (tonumber(accumulated) or 0) < definition.threshold then
        return 0
    end
    local chance = fraction * factor * Gore.ChanceScale
    if killing then
        chance = chance * Gore.KillingBlowScale
    end
    return math.min(Gore.MaximumChance, chance)
end

// Whether a region may still be severed. Living bosses keep their legs; nothing severs twice.
function Gore.CanSever(entity, region, killing)
    local definition = Gore.Regions[region]
    if not definition or Gore.HasRegion(Gore.GetMask(entity), region) then
        return false
    end
    if definition.deathOnly and not killing then
        return false
    end
    if Gore.IsBoss(entity) and not killing and region == "legs" then
        return false
    end
    return true
end

function Gore:MarkSevered(entity, region)
    local definition = Gore.Regions[region]
    entity:SetNWInt(Gore.MaskNetworkKey, bit.bor(Gore.GetMask(entity), definition.bit))
end

// Drops a legless zombie into a crawl and halves its speed; damage is unchanged. The model is kept: its root bone
// is lowered so server hitboxes match the crawl, and clients hide the legs through the gore mask.
function Gore:MakeCrawler(entity)
    if not IsValid(entity) or entity.GoreCrawler then
        return false
    end
    entity.GoreCrawler = true
    entity:ManipulateBonePosition(0, Gore.CrawlerBodyOffset)
    entity:SetCollisionBounds(Gore.CrawlerMins, Gore.CrawlerMaxs)
    entity.WalkSpeed = (entity.WalkSpeed or entity.DevelopmentWalkSpeed or 55) * Gore.CrawlerSpeedScale
    if entity.loco then
        entity.loco:SetDesiredSpeed(entity.WalkSpeed)
    end
    if entity.StartActivity and entity.CrawlActivity then
        entity:StartActivity(entity.CrawlActivity)
    end
    return true
end

local function writeSever(entityIndex, event)
    net.Start("ZM.Gore")
    net.WriteUInt(Gore.EventSever, 3)
    net.WriteUInt(entityIndex, 16)
    net.WriteUInt(Gore.Regions[event.region].id, 3)
    net.WriteVector(event.position)
    net.WriteNormal(event.direction)
    net.WriteFloat(event.force)
    net.WriteVector(event.origin)
    net.WriteAngle(event.angles)
end

// Sends a sever to every client; reliable because it spawns a limb that must not be lost.
function Gore:SendSever(entity, event)
    if not IsValid(entity) then
        return
    end
    writeSever(entity:EntIndex(), event)
    net.Broadcast()
end

local pendingWounds = {}
local woundFlushQueued = false

local function flushWounds()
    woundFlushQueued = false
    for entity, wound in pairs(pendingWounds) do
        if IsValid(entity) then
            net.Start("ZM.Gore", true)
            net.WriteUInt(Gore.EventWound, 3)
            net.WriteUInt(entity:EntIndex(), 16)
            net.WriteVector(wound.position)
            net.WriteNormal(wound.direction)
            net.WriteUInt(math.Clamp(math.ceil(wound.fraction * 10), 1, 10), 4)
            net.SendPVS(wound.position)
        end
    end
    pendingWounds = {}
end

// Wounds are coalesced per entity per tick (shotgun pellets) and sent unreliably to nearby clients.
function Gore:QueueWound(entity, position, direction, fraction)
    local wound = pendingWounds[entity]
    if wound then
        wound.fraction = wound.fraction + fraction
        return
    end
    pendingWounds[entity] = { position = position, direction = direction, fraction = fraction }
    if not woundFlushQueued then
        woundFlushQueued = true
        timer.Simple(0, flushWounds)
    end
end

local function damageDirection(entity, damage, position)
    local force = damage:GetDamageForce()
    if force and force:LengthSqr() > 1 then
        return force:GetNormalized()
    end
    local attacker = damage:GetAttacker()
    if IsValid(attacker) then
        local direction = position - attacker:WorldSpaceCenter()
        if direction:LengthSqr() > 1 then
            return direction:GetNormalized()
        end
    end
    return -entity:GetForward()
end

// Called by the zombie after health is applied. Returns the severed region (or nil). options.rng injects a
// random source for tests. A killing-blow sever is held on the entity and replayed onto its corpse.
function Gore:HandleDamage(entity, damage, killing, options)
    if not IsValid(entity) then
        return nil
    end
    local amount = math.max(0, damage:GetDamage())
    local maximumHealth = math.max(1, entity:GetMaxHealth())
    local fraction = math.min(1, amount / maximumHealth)
    local region, position = self:ResolveRegion(entity, damage)
    position = position or entity:WorldSpaceCenter()
    local direction = damageDirection(entity, damage, position)
    if fraction > 0 then
        self:QueueWound(entity, position, direction, fraction)
    end

    entity.GoreRegionDamage = entity.GoreRegionDamage or {}
    local accumulated = (entity.GoreRegionDamage[region] or 0) + fraction
    entity.GoreRegionDamage[region] = accumulated
    if not Gore.CanSever(entity, region, killing) then
        return nil
    end

    local chance = Gore.SeverChance(region, fraction, accumulated, Gore.WeaponFactor(damage), killing)
    if entity.GoreForcedRegion == region then
        chance = 1
    end
    local roll = options and options.rng and options.rng() or math.random()
    if chance <= 0 or roll >= chance then
        return nil
    end

    local event = {
        region = region,
        position = position,
        direction = direction,
        force = math.Clamp(amount * 4, 80, 600),
        origin = entity:GetPos(),
        angles = entity:GetAngles()
    }
    self:MarkSevered(entity, region)
    if killing then
        entity.GoreDeathSever = event
        return region
    end
    if region == "legs" then
        self:MakeCrawler(entity)
    end
    self:SendSever(entity, event)
    return region
end

// Copies severed regions onto the corpse and replays a killing-blow sever against it.
function Gore:ApplyCorpse(entity, corpse)
    if not IsValid(entity) or not IsValid(corpse) then
        return false
    end
    corpse:SetNWInt(Gore.MaskNetworkKey, Gore.GetMask(entity))
    local event = entity.GoreDeathSever
    entity.GoreDeathSever = nil
    if event then
        self:SendSever(corpse, event)
    end
    return true
end

// Development command: severs a region on the enemy under the player's crosshair (or the nearest one).
local regionNames = { leftArm = true, rightArm = true, legs = true, head = true, torso = true }

local function findEnemy(target)
    local trace = target:GetEyeTrace()
    if IsValid(trace.Entity) and trace.Entity.EnemyId and not trace.Entity.WalkerDead then
        return trace.Entity
    end
    local nearest, nearestDistance
    for _, entity in ipairs(ents.FindInSphere(target:GetPos(), 1500)) do
        if IsValid(entity) and entity.EnemyId and not entity.WalkerDead then
            local distance = entity:GetPos():DistToSqr(target:GetPos())
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = entity, distance
            end
        end
    end
    return nearest
end

ZM_Util.RegisterCommands({
    zn_gore_sever = "zn_gore_sever <leftArm|rightArm|legs|head|torso>: severs a region on the aimed or nearest enemy; head and torso kill it."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not target then
        return false, "no target player"
    end
    local region = arguments and arguments[1]
    if not regionNames[region] then
        ZM_Util.Reply(caller, command .. ": unknown region " .. tostring(region))
        return false, "unknown region"
    end
    local enemy = findEnemy(target)
    if not enemy then
        ZM_Util.Reply(caller, command .. ": no enemy nearby")
        return false, "no enemy"
    end
    local killing = Gore.Regions[region].deathOnly == true
    if not Gore.CanSever(enemy, region, killing) then
        ZM_Util.Reply(caller, command .. ": " .. region .. " cannot be severed on this enemy")
        return false, "cannot sever"
    end
    local damage = DamageInfo()
    damage:SetDamage(killing and enemy:Health() + 100 or 1)
    damage:SetDamageType(DMG_SLASH)
    damage:SetAttacker(target)
    damage:SetInflictor(target)
    enemy.GoreTraceTick = engine.TickCount()
    enemy.GoreTraceDamage = { [region] = 1 }
    enemy.GoreTraceHitPos = enemy:WorldSpaceCenter()
    enemy.GoreForcedRegion = region
    enemy:TakeDamageInfo(damage)
    enemy.GoreForcedRegion = nil
    ZM_Util.Reply(caller, command .. ": severed " .. region)
    return true
end)
