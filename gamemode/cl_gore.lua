// Client-only gore presentation: blood impacts and decals, arm stumps, severed limbs and blood trails. The server
// (sv_gore.lua) decides every sever; this file only draws it. Quality 0 disables these cosmetic effects, but
// crawler's hidden legs are gameplay state and stay hidden.
ZM_GoreClient = ZM_GoreClient or {}
local GoreClient = ZM_GoreClient
local Effects = ZM_GoreEffects

if GoreClient.Cleanup then
    GoreClient:Cleanup()
end

local qualityConVar = CreateClientConVar("zombiesim_gore_quality", "2", true, false,
    "Gore quality: 0 off, 1 reduced, 2 full.", 0, 2)

local maskKey = "ZM_GoreSevered"
local eventWound = 1
local eventSever = 2
local regionNames = { "leftArm", "rightArm", "legs", "head", "torso" }
// Mask bits match sv_gore.lua. A torso split shares the legs bit.
local regionBits = { leftArm = 1, rightArm = 2, legs = 4, head = 8 }
local regionRoots = {
    leftArm = { "ValveBiped.Bip01_L_Forearm" },
    rightArm = { "ValveBiped.Bip01_R_Forearm" },
    legs = { "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh" },
    head = { "ValveBiped.Bip01_Head1" }
}
local severedRegion = { torso = "legs" }
// A living legs sever happens as the zombie drops into its lowered crawl (sv_gore CrawlerBodyOffset); its legs
// are captured from that pose, so they are lifted back to standing height.
local crawlerLift = Vector(0, 0, 30)
local trackedClasses = { "zn_walker_zombie", "zn_boss_zombie", "prop_ragdoll" }
local limbLifetime = 60
local limbFadeDuration = 2
local pendingLifetime = 1.5
local trailIntervals = { 1.4, 0.6 }
local trailDistance = 28
// Hidden bones shrink to a near-zero (not zero) scale. A zero matrix is singular, and the hitbox of a zero-scaled
// bone breaks traces that cross it (NaN hit positions); a tiny box keeps traces valid and lets them pass through.
local zeroScale = Vector(0.001, 0.001, 0.001)
local limbHullMins = Vector(-3, -3, -3)
local limbHullMaxs = Vector(3, 3, 3)

GoreClient.Limbs = {}
GoreClient.Pending = {}
GoreClient.Spurts = {}
GoreClient.Tracked = setmetatable({}, { __mode = "k" })
GoreClient.ChainCache = {}
GoreClient.LimbSpawns = {}
GoreClient.Pools = {}
GoreClient.Tokens = {}
GoreClient.Statistics = { effects = 0, decals = 0, suppressed = 0, poolsCreated = 0, poolDraws = 0 }
GoreClient.PoolBuildFrame, GoreClient.PoolBuildCount = -1, 0

local poolMaterial = CreateMaterial("zombiesim_gore_pool_v1", "UnlitGeneric", {
    ["$basetexture"] = "models/debug/debugwhite",
    ["$translucent"] = "1", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1", ["$nocull"] = "1"
})
local poolTexture = poolMaterial:GetTexture("$basetexture")
local poolsAvailable = not poolMaterial:IsError() and poolTexture ~= nil and poolTexture:Width() > 0
if not poolsAvailable then ErrorNoHalt("[ZombieSim] Blood pool material is unavailable.\n") end

function GoreClient.Quality()
    return math.Clamp(math.floor(qualityConVar:GetInt()), 0, 2)
end

local function takeToken(kind)
    local allowed = Effects.TakeToken(GoreClient.Tokens, kind, CurTime(), FrameNumber(), GoreClient.Quality())
    if not allowed or kind == "decals" and GoreClient.Statistics.decals >= Effects.MaximumMapDecals then
        GoreClient.Statistics.suppressed = GoreClient.Statistics.suppressed + 1
        return false
    end
    return true
end

local function nearby(position)
    local player = LocalPlayer()
    return IsValid(player) and player:GetPos():DistToSqr(position) <= Effects.MaximumDistance * Effects.MaximumDistance
end

local function bloodImpact(position, normal, scale)
    if not nearby(position) or not takeToken("effects") then return end
    local effect = EffectData()
    effect:SetOrigin(position)
    effect:SetNormal(normal or vector_up)
    effect:SetScale(scale or 1)
    effect:SetColor(BLOOD_COLOR_RED)
    util.Effect("BloodImpact", effect, true, true)
    GoreClient.Statistics.effects = GoreClient.Statistics.effects + 1
end

local function bloodDecal(start, direction, distance, filter)
    if not nearby(start) or not takeToken("decals") then return false end
    local trace = util.TraceLine({
        start = start,
        endpos = start + direction * distance,
        mask = MASK_SOLID_BRUSHONLY,
        filter = filter
    })
    if trace.Hit then
        util.Decal("Blood", trace.HitPos + trace.HitNormal, trace.HitPos - trace.HitNormal)
        GoreClient.Statistics.decals = GoreClient.Statistics.decals + 1
        return true
    end
    return false
end

local function removeLimb(limb)
    if IsValid(limb.entity) then limb.entity:Remove() end
end

local function removePool(pool)
    pool.mesh:Destroy()
end

// Ground overlays reuse the puddles' flat-ground/depth discipline, not their weather-driven lifetime.
local function addPool(entity, now, cutPosition)
    if GoreClient.PoolBuildFrame ~= FrameNumber() then
        GoreClient.PoolBuildFrame, GoreClient.PoolBuildCount = FrameNumber(), 0
    end
    if GoreClient.PoolBuildCount >= GoreClient.Quality() then return false end
    GoreClient.PoolBuildCount = GoreClient.PoolBuildCount + 1
    if not poolsAvailable or not nearby(entity:GetPos()) then return true end
    local start = cutPosition or entity:WorldSpaceCenter()
    local trace = util.TraceLine({
        start = start, endpos = start - Vector(0, 0, 120),
        mask = MASK_SOLID_BRUSHONLY, filter = entity
    })
    if not trace.HitWorld or trace.HitSky or trace.HitNormal.z < 0.9 then return true end
    local radius = math.Rand(16, 26)
    for index = 1, 8 do
        local angle = index * math.pi / 4
        local point = trace.HitPos + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0)
        local edge = util.TraceLine({
            start = point + Vector(0, 0, 12), endpos = point - Vector(0, 0, 12),
            mask = MASK_SOLID_BRUSHONLY, filter = entity
        })
        if not edge.HitWorld or edge.HitSky or edge.HitNormal.z < 0.9
            or math.abs(edge.HitPos.z - trace.HitPos.z) > 2 then return true end
    end
    local center = trace.HitPos + trace.HitNormal * 2
    local angles = trace.HitNormal:Angle()
    local right, forward = angles:Right(), angles:Up()
    local points = {}
    local seed = math.Rand(0, math.pi * 2)
    for index = 0, 24 do
        local angle = index * math.pi / 12
        local width = radius * (0.86 + 0.10 * math.sin(angle * 3 + seed) + 0.04 * math.cos(angle * 5))
        points[index + 1] = center + (right * math.cos(angle) + forward * math.sin(angle)) * width
    end
    local vertices = {}
    local coreColor, edgeColor = Color(65, 4, 3, 200), Color(65, 4, 3, 0)
    local function vertex(position, color)
        return { pos = position, normal = trace.HitNormal, u = 0.5, v = 0.5, color = color }
    end
    for index = 1, 24 do
        vertices[#vertices + 1] = vertex(center, coreColor)
        vertices[#vertices + 1] = vertex(points[index + 1], edgeColor)
        vertices[#vertices + 1] = vertex(points[index], edgeColor)
    end
    local poolMesh = Mesh()
    poolMesh:BuildFromTriangles(vertices)
    Effects.PushBounded(GoreClient.Pools, { mesh = poolMesh, position = center, createdAt = now },
        Effects.Budget(GoreClient.Quality()).pools, removePool)
    GoreClient.Statistics.poolsCreated = GoreClient.Statistics.poolsCreated + 1
    return true
end

// The bone named root and every descendant, cached per model.
local function boneChain(entity, rootName)
    local model = entity:GetModel() or ""
    local key = model .. "|" .. rootName
    local cached = GoreClient.ChainCache[key]
    if cached ~= nil then
        return cached or nil
    end
    local root = entity:LookupBone(rootName)
    if not root then
        GoreClient.ChainCache[key] = false
        return nil
    end
    local chain, inChain = { root }, { [root] = true }
    for bone = root + 1, entity:GetBoneCount() - 1 do
        if inChain[entity:GetBoneParent(bone)] then
            inChain[bone] = true
            table.insert(chain, bone)
        end
    end
    GoreClient.ChainCache[key] = chain
    return chain
end

// Only bones computed by the current BuildBonePositions pass are writable; the engine prints "Bone is unwriteable"
// for any other bone even under pcall. A bone is readable exactly when it is writable, so every write is guarded.
local function writeBone(entity, bone, matrix)
    if entity:GetBoneMatrix(bone) then
        entity:SetBoneMatrix(bone, matrix)
    end
end

// Pins every bone of a severed chain (including fingers and helpers) to the chain root at zero scale.
local function collapseChain(entity, chain)
    local rootMatrix = entity:GetBoneMatrix(chain[1])
    if not rootMatrix then
        return
    end
    local collapsed = Matrix()
    collapsed:SetTranslation(rootMatrix:GetTranslation())
    collapsed:SetAngles(rootMatrix:GetAngles())
    collapsed:Scale(zeroScale)
    for _, bone in ipairs(chain) do
        writeBone(entity, bone, collapsed)
    end
end

local regionChainCache = {}
local function regionChains(entity, region)
    local key = (entity:GetModel() or "") .. "|" .. region
    local cached = regionChainCache[key]
    if cached then
        return cached
    end
    local chains = {}
    for _, rootName in ipairs(regionRoots[region] or {}) do
        local chain = boneChain(entity, rootName)
        if chain then
            table.insert(chains, chain)
        end
    end
    regionChainCache[key] = chains
    return chains
end

// Records a region's pose relative to its first root bone. Called from the bone setup callback, where bone access
// is allowed, before that region is collapsed.
local function captureRegion(entity, chains)
    local rootMatrix = chains[1] and entity:GetBoneMatrix(chains[1][1])
    if not rootMatrix then
        return nil
    end
    local inverse = rootMatrix:GetInverseTR()
    local relative = {}
    local cut, roots = Vector(0, 0, 0), 0
    for _, chain in ipairs(chains) do
        local chainRoot = entity:GetBoneMatrix(chain[1])
        if chainRoot then
            cut = cut + chainRoot:GetTranslation()
            roots = roots + 1
        end
        for _, bone in ipairs(chain) do
            local matrix = entity:GetBoneMatrix(bone)
            if matrix then
                relative[bone] = inverse * matrix
            end
        end
    end
    // The cut point is the centre of the chain roots (between the hips for legs), in root-local space.
    local cutMatrix = Matrix()
    cutMatrix:SetTranslation(cut / math.max(roots, 1))
    cutMatrix:SetAngles(rootMatrix:GetAngles())
    local pin = inverse * cutMatrix
    pin:Scale(zeroScale)
    return { root = rootMatrix, relative = relative, pin = pin, cutPosition = cutMatrix:GetTranslation() }
end

// Legs stay hidden at every quality because a crawler's missing legs are gameplay state; arms and head are
// cosmetic and follow the quality setting.
local function buildStumps(entity)
    local state = GoreClient.Tracked[entity]
    if not state then
        return
    end
    local quality = GoreClient.Quality()
    state.boneBuilds = (state.boneBuilds or 0) + 1
    if state.pendingRegions then
        for region, event in pairs(state.pendingRegions) do
            local capture = quality > 0 and CurTime() <= event.capturedBy and captureRegion(entity, regionChains(entity, region))
            if capture then
                local materials = {}
                for index in ipairs(entity:GetMaterials()) do
                    materials[index - 1] = ZM_Clothing and ZM_Clothing:GetEntitySubMaterial(entity, index - 1) or
                        entity:GetSubMaterial(index - 1)
                end
                Effects.PushBounded(GoreClient.LimbSpawns, {
                    model = entity:GetModel(), skin = entity:GetSkin(), region = region, capture = capture, event = event,
                    materials = materials,
                    lift = region == "legs" and entity:GetClass() ~= "prop_ragdoll" and crawlerLift or nil
                }, Effects.Budget(quality).limbs)
                GoreClient.EmitSever(entity, region, event, capture.cutPosition)
            end
            state.localMask = bit.bor(state.localMask, regionBits[region])
        end
        state.pendingRegions = nil
    end
    local mask = bit.bor(entity:GetNWInt(maskKey, 0), state.localMask)
    for region, maskBit in pairs(regionBits) do
        if bit.band(mask, maskBit) ~= 0 and (quality > 0 or region == "legs") then
            local position, count = Vector(0, 0, 0), 0
            for _, chain in ipairs(regionChains(entity, region)) do
                local root = entity:GetBoneMatrix(chain[1])
                if root then
                    position = position + root:GetTranslation()
                    count = count + 1
                end
                collapseChain(entity, chain)
            end
            if count > 0 then
                state.stumps[region] = { position = position / count, sampledAt = CurTime() }
            end
        end
    end
end

local function trackEntity(entity)
    local state = GoreClient.Tracked[entity]
    if state then
        return state
    end
    state = { localMask = 0, stumps = {}, trails = {} }
    state.callback = entity:AddCallback("BuildBonePositions", buildStumps)
    if entity:GetClass() == "prop_ragdoll" then
        state.previousRenderOverride = entity.RenderOverride
        state.renderOverride = function(ragdoll)
            // Physics ragdolls can reuse bones without invoking the registered callback on an ordinary draw.
            state.renderDraws = (state.renderDraws or 0) + 1
            local builds = state.boneBuilds or 0
            ragdoll:SetupBones()
            if (state.boneBuilds or 0) == builds then buildStumps(ragdoll) end
            if state.previousRenderOverride then
                state.previousRenderOverride(ragdoll)
            else
                ragdoll:DrawModel()
            end
        end
        entity.RenderOverride = state.renderOverride
    end
    GoreClient.Tracked[entity] = state
    return state
end
local function addLimb(limb)
    local cap = Effects.Budget(GoreClient.Quality()).limbs
    while #GoreClient.Limbs >= cap and #GoreClient.Limbs > 0 do
        local oldest = table.remove(GoreClient.Limbs, 1)
        if IsValid(oldest.entity) then
            oldest.entity:Remove()
        end
    end
    if cap <= 0 then
        if IsValid(limb.entity) then
            limb.entity:Remove()
        end
        return
    end
    limb.expiresAt = CurTime() + limbLifetime
    table.insert(GoreClient.Limbs, limb)
end

// A rigid copy of a severed region, built from a pose captured during bone setup. Bone matrices are relative to
// the region's root so the limb moves as one body. Every other bone is pinned to the cut point at a near-zero
// scale; merely scaling them in place leaves them at the model's default pose, and skin weighted between the
// limb and the hidden body (hips, shoulder, neck) stretches out to wherever those bones sit.
local function spawnLimb(spawn)
    local capture, event = spawn.capture, spawn.event
    local limb = ClientsideModel(spawn.model, RENDERGROUP_OPAQUE)
    if not IsValid(limb) then
        return
    end
    limb:SetSkin(spawn.skin or 0)
    for index, material in pairs(spawn.materials or {}) do
        limb:SetSubMaterial(index, material)
    end
    local relative, pin = capture.relative, capture.pin
    local hidden = {}
    for bone = 0, limb:GetBoneCount() - 1 do
        if not relative[bone] then
            limb:ManipulateBoneScale(bone, zeroScale)
            table.insert(hidden, bone)
        end
    end
    limb:SetPos(capture.root:GetTranslation() + (spawn.lift or vector_origin))
    limb:SetAngles(capture.root:GetAngles())
    limb:SetRenderBounds(Vector(-48, -48, -48), Vector(48, 48, 48))
    limb:AddCallback("BuildBonePositions", function(entity)
        local base = Matrix()
        base:SetTranslation(entity:GetPos())
        base:SetAngles(entity:GetAngles())
        local pinned = base * pin
        for _, bone in ipairs(hidden) do
            writeBone(entity, bone, pinned)
        end
        for bone, offset in pairs(relative) do
            writeBone(entity, bone, base * offset)
        end
    end)
    local spin = spawn.region == "legs" and 120 or 400
    addLimb({
        entity = limb,
        materials = table.Copy(spawn.materials or {}),
        rigid = true,
        velocity = event.direction * event.force * (spawn.region == "legs" and 0.3 or 0.6) + Vector(0, 0, spawn.region == "head" and 200 or 140),
        angularVelocity = Angle(math.Rand(-spin, spin), math.Rand(-spin, spin), math.Rand(-spin, spin)),
        bleeding = true, cutLocal = capture.pin:GetTranslation(), nextTrailAt = 0
    })
    GoreClient.AddSpurt(limb, nil, limb:LocalToWorld(capture.pin:GetTranslation()))
end

local function updateLimbSpawns()
    local spawns = GoreClient.LimbSpawns
    if #spawns == 0 then
        return
    end
    for _ = 1, math.min(#spawns, GoreClient.Quality() * 2) do
        spawnLimb(table.remove(spawns, 1))
    end
end
local function burst(position, direction, count, filter)
    for _ = 1, count do
        bloodImpact(position + VectorRand() * 6, (VectorRand() + vector_up):GetNormalized(), 2)
    end
    bloodDecal(position, direction, 160, filter)
    bloodDecal(position, Vector(0, 0, -1), 160, filter)
    if count > 3 then
        for _ = 1, 3 do
            local spread = Vector(math.Rand(-0.6, 0.6), math.Rand(-0.6, 0.6), -1):GetNormalized()
            bloodDecal(position, spread, 180, filter)
        end
    end
end

// Spurts follow the entity through a local offset; reading bone positions from Think raises "Bone access not
// allowed" on NextBots.
function GoreClient.AddSpurt(source, region, position)
    Effects.PushBounded(GoreClient.Spurts, {
        entity = source, region = region, offset = source:WorldToLocal(position), position = position,
        endsAt = CurTime() + 2, nextAt = 0
    }, Effects.Budget(GoreClient.Quality()).spurts)
end

function GoreClient.EmitSever(source, region, event, position)
    GoreClient.AddSpurt(source, region, position)
    burst(position, event.direction, GoreClient.Quality() >= 2 and 6 or 2, source)
end

// The severed part is captured on the source's next bone setup, then spawned as a rigid copy and hidden on the
// source. A torso split drops the legs.
local function handleSever(source, region, event)
    region = severedRegion[region] or region
    if not regionBits[region] then
        return
    end
    local state = trackEntity(source)
    state.pendingRegions = state.pendingRegions or {}
    event.capturedBy = CurTime() + 1
    state.pendingRegions[region] = event
end
local function handleWound(source, event)
    local quality = GoreClient.Quality()
    local intensity = event.intensity / 10
    bloodImpact(event.position, -event.direction, 1 + intensity * 2)
    if quality >= 2 or math.random() < 0.5 then
        bloodDecal(event.position, event.direction, 128, source)
    end
    if quality >= 2 and intensity >= 0.2 then
        bloodDecal(event.position, Vector(0, 0, -1), 128, source)
    end
end

local function dispatch(event)
    local source = Entity(event.entityIndex)
    if not IsValid(source) then
        return false
    end
    if event.kind == eventSever then
        local state = trackEntity(source)
        handleSever(source, event.region, event)
    else
        handleWound(source, event)
    end
    return true
end

net.Receive("ZM.Gore", function()
    local event = { kind = net.ReadUInt(3), entityIndex = net.ReadUInt(16) }
    if event.kind == eventSever then
        event.region = regionNames[net.ReadUInt(3)]
        event.position = net.ReadVector()
        event.direction = net.ReadNormal()
        event.force = net.ReadFloat()
        event.origin = net.ReadVector()
        event.angles = net.ReadAngle()
    elseif event.kind == eventWound then
        event.position = net.ReadVector()
        event.direction = net.ReadNormal()
        event.intensity = net.ReadUInt(4)
    else
        return
    end
    if GoreClient.Quality() == 0 then
        return
    end
    if not nearby(event.position) then return end
    if not dispatch(event) and event.kind == eventSever then
        event.expiresAt = CurTime() + pendingLifetime
        Effects.PushBounded(GoreClient.Pending, event, Effects.Budget(GoreClient.Quality()).pending)
    end
end)

local function simulateRigid(limb, delta)
    local entity = limb.entity
    if limb.resting then
        return
    end
    limb.velocity.z = limb.velocity.z - 600 * delta
    local start = entity:GetPos()
    local finish = start + limb.velocity * delta
    local trace = util.TraceHull({
        start = start,
        endpos = finish,
        mins = limbHullMins,
        maxs = limbHullMaxs,
        mask = MASK_SOLID_BRUSHONLY
    })
    if trace.Hit then
        entity:SetPos(trace.HitPos + trace.HitNormal * 0.5)
        local normal = trace.HitNormal
        limb.velocity = (limb.velocity - normal * 2 * limb.velocity:Dot(normal)) * 0.3
        limb.angularVelocity = limb.angularVelocity * 0.5
        if limb.bleeding then
            limb.bleeding = false
            bloodDecal(trace.HitPos + normal * 2, -normal, 4, entity)
        end
        if normal.z > 0.7 and limb.velocity:LengthSqr() < 400 then
            limb.resting = true
            return
        end
    else
        entity:SetPos(finish)
    end
    entity:SetAngles(entity:GetAngles() + limb.angularVelocity * delta)
end

local function updateLimbs(now, delta)
    for index = #GoreClient.Limbs, 1, -1 do
        local limb = GoreClient.Limbs[index]
        local entity = limb.entity
        if not IsValid(entity) then
            table.remove(GoreClient.Limbs, index)
        elseif now >= limb.expiresAt + limbFadeDuration then
            entity:Remove()
            table.remove(GoreClient.Limbs, index)
        else
            if limb.rigid then
                simulateRigid(limb, delta)
            end
            if now >= (limb.nextTrailAt or 0) and limb.cutLocal and not limb.resting then
                limb.nextTrailAt = now + trailIntervals[GoreClient.Quality()]
                bloodDecal(entity:LocalToWorld(limb.cutLocal), Vector(0, 0, -1), 128, entity)
            end
            if now >= limb.expiresAt then
                local alpha = math.Clamp(1 - (now - limb.expiresAt) / limbFadeDuration, 0, 1)
                entity:SetRenderMode(RENDERMODE_TRANSALPHA)
                entity:SetColor(Color(255, 255, 255, math.floor(alpha * 255)))
            end
        end
    end
end

local function updateSpurts(now)
    for index = #GoreClient.Spurts, 1, -1 do
        local spurt = GoreClient.Spurts[index]
        if now >= spurt.endsAt or not IsValid(spurt.entity) then
            table.remove(GoreClient.Spurts, index)
        elseif now >= spurt.nextAt then
            spurt.nextAt = now + (GoreClient.Quality() == 1 and 0.3 or 0.15)
            local position = spurt.position
            if IsValid(spurt.entity) then
                local state = GoreClient.Tracked[spurt.entity]
                local stump = state and state.stumps[spurt.region]
                position = stump and stump.position or spurt.entity:LocalToWorld(spurt.offset)
            end
            if position then
                bloodImpact(position, (VectorRand() * 0.4 + vector_up):GetNormalized(), 1)
                if math.random() < 0.35 then
                    bloodDecal(position, Vector(0, 0, -1), 128, spurt.entity)
                end
            end
        end
    end
end

local function updatePending(now)
    for index = #GoreClient.Pending, 1, -1 do
        local event = GoreClient.Pending[index]
        if now >= event.expiresAt or dispatch(event) then
            table.remove(GoreClient.Pending, index)
        end
    end
end

// Wounded zombies leave a blood trail; gored corpses get a pool once they come to rest.
local function updateTracked(now, quality)
    local interval = trailIntervals[quality]
    for entity, state in pairs(GoreClient.Tracked) do
        if not IsValid(entity) then
            GoreClient.Tracked[entity] = nil
        elseif not entity:IsDormant() and nearby(entity:GetPos()) then
            if entity:GetClass() == "prop_ragdoll" then
                if entity:GetVelocity():LengthSqr() >= 100 then
                    state.restingAt = now
                end
                if not state.pooled and now - (state.restingAt or state.firstSeenAt or now) > 0.6 then
                    local stump = state.stumps.head or state.stumps.leftArm or state.stumps.rightArm or state.stumps.legs
                    local center = stump and stump.position or entity:WorldSpaceCenter()
                    state.pooled = addPool(entity, now, center)
                    if state.pooled then
                        for _ = 1, quality >= 2 and 3 or 1 do
                            bloodDecal(center, Vector(0, 0, -1), 96, entity)
                        end
                    end
                end
            else
                for region, stump in pairs(state.stumps) do
                    local trail = state.trails[region] or { nextAt = 0 }
                    state.trails[region] = trail
                    if now <= stump.sampledAt + 0.5 and now >= trail.nextAt
                        and (not trail.position or trail.position:DistToSqr(stump.position) >= trailDistance * trailDistance) then
                        trail.nextAt, trail.position = now + interval, stump.position
                        bloodDecal(stump.position, Vector(0, 0, -1), 128, entity)
                    end
                end
            end
        end
    end
end

local nextScanAt = 0
local function scanEntities(now)
    if now < nextScanAt then
        return
    end
    nextScanAt = now + 0.5
    for _, class in ipairs(trackedClasses) do
        for _, entity in ipairs(ents.FindByClass(class)) do
            if entity:GetNWInt(maskKey, 0) ~= 0 then
                local state = trackEntity(entity)
                state.firstSeenAt = state.firstSeenAt or now
            end
        end
    end
end

local lastThinkAt
hook.Add("Think", "ZM.Gore", function()
    local now = CurTime()
    local delta = math.Clamp(now - (lastThinkAt or now), 0, 0.1)
    lastThinkAt = now
    local quality = GoreClient.Quality()
    local budget = Effects.Budget(quality)
    Effects.Trim(GoreClient.Limbs, budget.limbs, removeLimb)
    Effects.Trim(GoreClient.Pending, budget.pending)
    Effects.Trim(GoreClient.Spurts, budget.spurts)
    Effects.Trim(GoreClient.LimbSpawns, budget.limbs)
    Effects.Trim(GoreClient.Pools, budget.pools, removePool)
    for index = #GoreClient.Pools, 1, -1 do
        if now - GoreClient.Pools[index].createdAt >= Effects.PoolLifetime then
            removePool(GoreClient.Pools[index])
            table.remove(GoreClient.Pools, index)
        end
    end
    updateLimbs(now, delta)
    scanEntities(now)
    if quality == 0 then
        GoreClient.Pending = {}
        GoreClient.Spurts = {}
        return
    end
    updatePending(now)
    updateLimbSpawns()
    updateSpurts(now)
    updateTracked(now, quality)
end)

function GoreClient:Cleanup()
    for entity, state in pairs(self.Tracked or {}) do
        if IsValid(entity) and state.callback then
            entity:RemoveCallback("BuildBonePositions", state.callback)
            if entity.RenderOverride == state.renderOverride then
                entity.RenderOverride = state.previousRenderOverride
            end
        end
    end
    self.Tracked = setmetatable({}, { __mode = "k" })
    for _, limb in ipairs(self.Limbs or {}) do
        if IsValid(limb.entity) then
            limb.entity:Remove()
        end
    end
    self.Limbs = {}
    self.Pending = {}
    self.Spurts = {}
    self.LimbSpawns = {}
    for _, pool in ipairs(self.Pools or {}) do removePool(pool) end
    self.Pools = {}
    self.Tokens = {}
    self.Statistics = { effects = 0, decals = 0, suppressed = 0, poolsCreated = 0, poolDraws = 0 }
end

hook.Add("PreDrawTranslucentRenderables", "ZM.Gore.Pools", function(depth, skybox)
    GoreClient.Statistics.poolDraws = 0
    if depth or skybox or ZM_WorldMap and ZM_WorldMap.Capturing or GoreClient.Quality() == 0 then return end
    local player = LocalPlayer()
    if not IsValid(player) or ZM_SafeZones:IsPlayerInside(player) then return end
    cam.PushModelMatrix(Matrix())
    for _, pool in ipairs(GoreClient.Pools) do
        if nearby(pool.position) then
            poolMaterial:SetFloat("$alpha", Effects.PoolAlpha(CurTime() - pool.createdAt))
            render.SetMaterial(poolMaterial)
            pool.mesh:Draw()
            GoreClient.Statistics.poolDraws = GoreClient.Statistics.poolDraws + 1
        end
    end
    poolMaterial:SetFloat("$alpha", 1)
    cam.PopModelMatrix()
end)

function GoreClient:GetDiagnosticSnapshot()
    local tracked = {}
    for entity, state in pairs(self.Tracked) do
        if IsValid(entity) and nearby(entity:GetPos()) and #tracked < 8 then
            tracked[#tracked + 1] = {
                entityIndex = entity:EntIndex(), class = entity:GetClass(), mask = entity:GetNWInt(maskKey, 0),
                localMask = state.localMask, boneBuilds = state.boneBuilds or 0,
                renderDraws = state.renderDraws or 0, stumps = table.Count(state.stumps)
            }
        end
    end
    return {
        quality = self.Quality(), budget = table.Copy(Effects.Budget(self.Quality())),
        limbs = #self.Limbs, pending = #self.Pending, spurts = #self.Spurts,
        limbSpawns = #self.LimbSpawns, pools = #self.Pools, statistics = table.Copy(self.Statistics),
        poolMaterialAvailable = poolsAvailable, poolShader = poolMaterial:GetShader(),
        poolTextureWidth = poolTexture and poolTexture:Width() or 0, poolTriangles = #self.Pools * 24,
        maximumDistance = Effects.MaximumDistance, maximumMapDecals = Effects.MaximumMapDecals,
        poolLifetime = Effects.PoolLifetime, tracked = tracked
    }
end

hook.Add("PostCleanupMap", "ZM.Gore", function()
    GoreClient:Cleanup()
end)

function GoreClient:RestoreProbeQuality()
    if self.ProbeQuality == nil then return end
    qualityConVar:SetInt(self.ProbeQuality)
    self.ProbeQuality = nil
    timer.Remove("ZM.Gore.ProbeQuality")
end

concommand.Add("zombiesim_gore_quality_probe", function(_, _, arguments)
    if ZM_World.ActiveProfile ~= "preview" or not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then
        ErrorNoHalt("[ZombieSim] Gore quality probes require an admin preview session.\n")
        return
    end
    local action = arguments[1]
    if action == "restore" then GoreClient:RestoreProbeQuality() return end
    if action ~= "0" and action ~= "1" and action ~= "2" then
        ErrorNoHalt("[ZombieSim] Invalid gore quality probe; expected 0, 1, 2 or restore.\n")
        return
    end
    if GoreClient.ProbeQuality == nil then GoreClient.ProbeQuality = qualityConVar:GetInt() end
    qualityConVar:SetInt(tonumber(action))
    timer.Create("ZM.Gore.ProbeQuality", 120, 1, function() GoreClient:RestoreProbeQuality() end)
end)

hook.Add("ShutDown", "ZM.Gore.ProbeQuality", function() GoreClient:RestoreProbeQuality() end)
