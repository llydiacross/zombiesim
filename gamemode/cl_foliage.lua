// Client-local, bounded ambient debris. These models are cosmetic and never enter server physics or inventory.
ZM_AmbientDebris = ZM_AmbientDebris or {}
local Debris = ZM_AmbientDebris

if Debris.Cleanup then
    Debris:Cleanup()
end

local amountConVar = CreateClientConVar("zombiesim_ambient_debris_amount", "1", true, false,
    "Ambient debris amount multiplier (0 disables, up to 3).", 0, 3)

// Behaviour per kind: paper flutters in gusts, rolling items roll on their long axis, litter slides,
// and tumbleweeds roll with the prevailing wind.
Debris.Kinds = {
    paper = {
        models = { "models/props_c17/paper01.mdl", "models/props_junk/garbage_newspaper001a.mdl" },
        gravity = 160, groundFriction = 4, airFriction = 1.5, kickRadius = 40,
        shotStrength = 260, shotLift = 140, leash = 180
    },
    rolling = {
        models = {
            "models/props/cs_militia/bottle01.mdl",
            "models/props_junk/garbage_glassbottle001a.mdl",
            "models/props_junk/garbage_plasticbottle001a.mdl",
            "models/props_junk/popcan01a.mdl",
            "models/props_junk/garbage_metalcan001a.mdl"
        },
        gravity = 600, groundFriction = 1.6, airFriction = 0.2, kickRadius = 48,
        shotStrength = 240, shotLift = 90, leash = 180
    },
    litter = {
        models = {
            "models/props_junk/garbage_milkcarton001a.mdl",
            "models/props_junk/garbage_takeoutcarton001a.mdl",
            "models/props_junk/garbage_carboard001a.mdl"
        },
        gravity = 400, groundFriction = 5, airFriction = 0.2, kickRadius = 40,
        shotStrength = 200, shotLift = 120, leash = 140
    },
    tumbleweed = {
        models = { "models/props_foliage/bramble001a.mdl" },
        scale = 0.5,
        gravity = 380, groundFriction = 0.8, airFriction = 0.2, kickRadius = 56,
        shotStrength = 200, shotLift = 160, leash = 1400
    }
}
Debris.GridSize = 384
Debris.GridRadius = 2
Debris.SlotsPerCell = 3
Debris.BaseModels = 20
Debris.ModelCap = 60
Debris.SiteCheckInterval = 0.5
Debris.SimulationDistance = 2000
Debris.ShotRadius = 80
Debris.Active = {}
Debris.NextGustAt = 0
Debris.GustDirection = Vector(1, 0, 0)
Debris.GustEndsAt = 0
Debris.WindDirection = Vector(1, 0, 0)
Debris.LastMap = nil
Debris.LastGridX = nil
Debris.LastGridY = nil

local upVector = Vector(0, 0, 1)

function Debris.GetAmount()
    return math.Clamp(amountConVar:GetFloat(), 0, 3)
end

local function getWorldBounds()
    local world = game.GetWorld()
    if not world or world == NULL or not world:IsWorld() then
        return nil
    end
    local minimum, maximum = world:WorldSpaceAABB()
    if not minimum or not maximum or maximum.x <= minimum.x or maximum.y <= minimum.y then
        minimum, maximum = world:GetRenderBounds()
    end
    if not minimum or not maximum or maximum.z <= minimum.z then
        return nil
    end
    return minimum, maximum
end

local function deterministicSeed(text)
    local seed = 0
    for index = 1, #text do
        seed = (seed * 33 + string.byte(text, index)) % 2147483647
    end
    return math.max(seed, 1)
end

local function newRng(seed)
    local state = seed
    return {
        Next = function()
            state = (state * 48271) % 2147483647
            return (state - 1) / 2147483646
        end,
        Int = function(self, minimum, maximum)
            return minimum + math.floor(self:Next() * (maximum - minimum + 1))
        end
    }
end

local function isOutdoorCityCell(player)
    if not IsValid(player) or not ZM_World or not ZM_World:IsLoaded() then
        return false
    end
    local cell = player.GetWorldCell and player:GetWorldCell() or nil
    if not cell or (ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell)) then
        return false
    end
    local mapPath = ZM_World:GetMapPath(cell)
    local mapName = string.lower(string.match(mapPath or "", "([^/\\]+)$") or "")
    return mapName == string.lower(game.GetMap())
end

local function removeRecord(record)
    if IsValid(record.entity) then
        record.entity:Remove()
    end
end

function Debris:Cleanup()
    for _, record in pairs(self.Active or {}) do
        removeRecord(record)
    end
    self.Active = {}
    self.LastMap = nil
    self.LastGridX = nil
    self.LastGridY = nil
end

local function hasNearbyProp(position)
    for _, entity in ipairs(ents.FindInSphere(position, 36)) do
        if IsValid(entity) and not entity:IsPlayer() and not entity:IsWorld()
            and string.StartWith(entity:GetClass(), "prop_") then
            return true
        end
    end
    return false
end

local modelAvailability = {}

// util.IsValidModel is false on the client until a model is precached, so check the mounted file instead.
local function isDebrisModelAvailable(modelPath)
    local cached = modelAvailability[modelPath]
    if cached ~= nil then
        return cached
    end
    local available = file.Exists(modelPath, "GAME")
    if available then
        util.PrecacheModel(modelPath)
    else
        ErrorNoHalt("[ZombieSim] Ambient debris model is unavailable: " .. modelPath .. "\n")
    end
    modelAvailability[modelPath] = available
    return available
end

// Positions the model so its scaled bounds centre sits at record.position.
local function placeEntity(record)
    local entity = record.entity
    entity:SetAngles(record.angles)
    local offset = entity:LocalToWorld(record.centre) - entity:GetPos()
    entity:SetPos(record.position - offset)
end

local function createDebris(site)
    local kind = Debris.Kinds[site.kind]
    local modelPath = kind.models[site.variant]
    if not isDebrisModelAvailable(modelPath) then
        return nil
    end
    local entity = ClientsideModel(modelPath, RENDERGROUP_OPAQUE)
    if not IsValid(entity) then
        ErrorNoHalt("[ZombieSim] Could not create client-side ambient debris model: " .. modelPath .. "\n")
        return nil
    end
    local scale = kind.scale or 1
    if scale ~= 1 then
        entity:SetModelScale(scale, 0)
    end
    entity:SetSolid(SOLID_NONE)
    entity:SetNotSolid(true)
    entity:SetMoveType(MOVETYPE_NONE)
    entity:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    entity:DrawShadow(false)

    local minimum, maximum = entity:GetModelBounds()
    minimum, maximum = minimum * scale, maximum * scale
    local size = maximum - minimum
    local angles = Angle(0, site.yaw, 0)
    local restHeight
    if site.kind == "rolling" then
        // Bottles and cans lie on their side so they can roll about their long (model Z) axis.
        angles = Angle(0, site.yaw, 90)
        restHeight = math.max(math.min(size.x, size.y) * 0.5, 1)
    elseif site.kind == "tumbleweed" then
        restHeight = math.max((size.x + size.y + size.z) / 6, 4)
        angles = Angle(site.yaw % 90, site.yaw, 0)
    else
        restHeight = math.max(size.z * 0.5, 0.5)
    end

    local record = {
        key = site.key,
        kind = site.kind,
        definition = kind,
        entity = entity,
        centre = (minimum + maximum) * 0.5,
        restHeight = restHeight,
        home = site.ground + site.normal * restHeight,
        normal = site.normal,
        angles = angles,
        velocity = Vector(0, 0, 0),
        moving = site.kind == "tumbleweed",
        grounded = true,
        nextKickAt = 0,
        spin = 0
    }
    record.position = Vector(record.home)
    placeEntity(record)
    return record
end

local function traceSiteGround(x, y, minimum, maximum)
    // Step through the sealed skybox ceiling and tool brushes before testing the real ground.
    local bottom = Vector(x, y, minimum.z - 64)
    local start = Vector(x, y, maximum.z - 1)
    local trace
    for _ = 1, 8 do
        trace = util.TraceLine({ start = start, endpos = bottom, mask = MASK_SOLID_BRUSHONLY })
        if trace.StartSolid and trace.FractionLeftSolid and trace.FractionLeftSolid < 1 then
            start = start + (bottom - start) * trace.FractionLeftSolid - Vector(0, 0, 2)
        elseif trace.Hit and (trace.HitSky or string.StartWith(string.lower(tostring(trace.HitTexture or "")), "tools/")) then
            start = trace.HitPos - Vector(0, 0, 2)
        else
            break
        end
        if start.z <= bottom.z then
            break
        end
    end
    return trace
end

// Rolls every slot regardless of the amount setting so sites stay stable when the slider changes.
local function sitesForGrid(gx, gy, minimum, maximum, amount, output)
    local cellKey = tostring(gx) .. ":" .. tostring(gy)
    local rng = newRng(deterministicSeed(game.GetMap() .. ":" .. cellKey))
    for slot = 1, Debris.SlotsPerCell do
        local roll = rng:Next()
        local x = gx * Debris.GridSize + rng:Next() * Debris.GridSize
        local y = gy * Debris.GridSize + rng:Next() * Debris.GridSize
        local kindRoll = rng:Next()
        local variantRoll = rng:Next()
        local yaw = rng:Int(0, 359)
        local chance = math.Clamp(amount * 0.35 - (slot - 1) * 0.35, 0, 0.9)
        if roll < chance and x >= minimum.x and x <= maximum.x and y >= minimum.y and y <= maximum.y then
            local trace = traceSiteGround(x, y, minimum, maximum)
            local texture = string.lower(tostring(trace and trace.HitTexture or ""))
            if trace and trace.Hit and not trace.HitSky and trace.HitWorld and trace.HitNormal
                and trace.HitNormal.z >= 0.75 and not string.find(texture, "tools/", 1, true)
                and not string.find(texture, "nodraw", 1, true) and not hasNearbyProp(trace.HitPos) then
                local kind
                if kindRoll < 0.08 then
                    kind = "tumbleweed"
                elseif kindRoll < 0.48 then
                    kind = "paper"
                elseif kindRoll < 0.80 then
                    kind = "rolling"
                else
                    kind = "litter"
                end
                local variants = #Debris.Kinds[kind].models
                table.insert(output, {
                    key = cellKey .. ":" .. slot,
                    kind = kind,
                    variant = math.min(variants, 1 + math.floor(variantRoll * variants)),
                    ground = trace.HitPos,
                    normal = trace.HitNormal,
                    yaw = yaw
                })
            end
        end
    end
end

function Debris:UpdateSites(player)
    local amount = self.GetAmount()
    if amount <= 0 or not isOutdoorCityCell(player) then
        self:Cleanup()
        return
    end
    local minimum, maximum = getWorldBounds()
    if not minimum or not maximum then
        self:Cleanup()
        return
    end
    local gridX = math.floor(player:GetPos().x / self.GridSize)
    local gridY = math.floor(player:GetPos().y / self.GridSize)
    local mapName = game.GetMap()
    if self.LastMap == mapName and self.LastGridX == gridX and self.LastGridY == gridY then
        return
    end

    local limit = math.min(self.ModelCap, math.ceil(self.BaseModels * amount))
    local sites = {}
    for offsetX = -self.GridRadius, self.GridRadius do
        for offsetY = -self.GridRadius, self.GridRadius do
            sitesForGrid(gridX + offsetX, gridY + offsetY, minimum, maximum, amount, sites)
        end
    end
    local origin = player:GetPos()
    table.sort(sites, function(left, right)
        return left.ground:DistToSqr(origin) < right.ground:DistToSqr(origin)
    end)

    local nextActive = {}
    local count = 0
    for _, site in ipairs(sites) do
        if count >= limit then
            break
        end
        local record = self.Active[site.key] or createDebris(site)
        if record then
            nextActive[site.key] = record
            count = count + 1
        end
    end
    for key, record in pairs(self.Active) do
        if not nextActive[key] then
            removeRecord(record)
        end
    end
    self.Active = nextActive
    self.LastMap = mapName
    self.LastGridX = gridX
    self.LastGridY = gridY
end

function Debris:Invalidate()
    self.LastMap = nil
end

cvars.AddChangeCallback("zombiesim_ambient_debris_amount", function()
    Debris:Invalidate()
end, "ZM.Foliage.AmbientDebrisAmount")

local function horizontal(vector)
    return Vector(vector.x, vector.y, 0)
end

local function applyImpulse(record, impulse)
    record.velocity = record.velocity + impulse
    record.moving = true
    if impulse.z > 0 then
        record.grounded = false
    end
    record.spin = math.Rand(-1, 1)
end

// Bullet impacts throw nearby debris away from the hit point and along the shot direction.
function Debris:OnShot(source, direction, impacts)
    if not istable(impacts) or table.IsEmpty(self.Active) then
        return
    end
    local radius = self.ShotRadius
    for _, impact in ipairs(impacts) do
        if isvector(impact) then
            for _, record in pairs(self.Active) do
                local distance = record.position:Distance(impact)
                if distance <= radius then
                    local definition = record.definition
                    local falloff = 1 - distance / radius
                    local away = horizontal(record.position - impact)
                    if away:LengthSqr() < 1 then
                        away = horizontal(direction or Vector(1, 0, 0))
                    end
                    if away:LengthSqr() < 0.01 then
                        away = Vector(1, 0, 0)
                    end
                    local push = away:GetNormalized() * 0.65 + horizontal(direction or vector_origin) * 0.35
                    applyImpulse(record, push * definition.shotStrength * falloff
                        + upVector * definition.shotLift * (0.4 + falloff * 0.6))
                end
            end
        end
    end
end

// Moving players are gathered once per frame; most frames nobody is moving fast enough and nothing is allocated.
local kickers = {}
local kickerCount = 0

local function gatherKickers()
    kickerCount = 0
    for _, target in ipairs(player.GetAll()) do
        if IsValid(target) and target:Alive() then
            local velocity = target:GetVelocity()
            local speedSqr = velocity.x * velocity.x + velocity.y * velocity.y
            if speedSqr > 50 * 50 then
                kickerCount = kickerCount + 1
                local kicker = kickers[kickerCount]
                if not kicker then
                    kicker = {}
                    kickers[kickerCount] = kicker
                end
                local feet = target:GetPos()
                kicker.x, kicker.y = feet.x, feet.y
                kicker.vx, kicker.vy = velocity.x, velocity.y
                kicker.speed = math.sqrt(speedSqr)
            end
        end
    end
end

local function kickFromPlayers(record, now)
    if kickerCount == 0 or now < record.nextKickAt then
        return
    end
    local radius = record.definition.kickRadius
    local position = record.position
    for index = 1, kickerCount do
        local kicker = kickers[index]
        local awayX, awayY = position.x - kicker.x, position.y - kicker.y
        local distanceSqr = awayX * awayX + awayY * awayY
        if distanceSqr <= radius * radius then
            local speed = kicker.speed
            local moveX, moveY = kicker.vx / speed, kicker.vy / speed
            if distanceSqr < 1 then
                awayX, awayY = moveX, moveY
            else
                local distance = math.sqrt(distanceSqr)
                awayX, awayY = awayX / distance, awayY / distance
            end
            local strength = math.min(speed, 320) * 0.55
            applyImpulse(record, Vector((awayX * 0.5 + moveX * 0.5) * strength, (awayY * 0.5 + moveY * 0.5) * strength,
                record.kind == "paper" and 50 or 20))
            record.nextKickAt = now + 0.5
            return
        end
    end
end

local function applyWind(record, now, frameTime)
    local gusting = now < Debris.GustEndsAt
    local drift = record.position:Distance(record.home)
    local withinLeash = drift < record.definition.leash
    if record.kind == "tumbleweed" then
        local wind = gusting and Debris.GustDirection or Debris.WindDirection
        local speed = gusting and 140 or 40
        local targetX, targetY = wind.x * speed, wind.y * speed
        if not withinLeash then
            // Roll back toward home once a tumbleweed has blown too far away.
            local homeX, homeY = record.home.x - record.position.x, record.home.y - record.position.y
            local homeLength = math.sqrt(homeX * homeX + homeY * homeY)
            if homeLength > 0 then
                targetX, targetY = homeX / homeLength * 40, homeY / homeLength * 40
            else
                targetX, targetY = 0, 0
            end
        end
        local velocity = record.velocity
        local currentSpeed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        local blend = math.min(1, 1.2 * frameTime)
        velocity.x = velocity.x + (targetX - velocity.x) * blend
        velocity.y = velocity.y + (targetY - velocity.y) * blend
        record.moving = true
        if record.grounded and currentSpeed > 60 and math.random() < frameTime * 1.2 then
            velocity.z = math.Rand(60, 110)
            record.grounded = false
        end
    elseif gusting and withinLeash then
        local velocity = record.velocity
        local gust = Debris.GustDirection
        if record.kind == "paper" then
            velocity.x = velocity.x + gust.x * 60 * frameTime
            velocity.y = velocity.y + gust.y * 60 * frameTime
            if record.grounded and math.random() < frameTime * 1.5 then
                velocity.z = math.Rand(40, 70)
                record.grounded = false
            end
            record.moving = true
        elseif record.kind == "litter" and velocity.x * velocity.x + velocity.y * velocity.y < 25 * 25 then
            velocity.x = velocity.x + gust.x * 18 * frameTime
            velocity.y = velocity.y + gust.y * 18 * frameTime
            record.moving = true
        end
    end
end

local collisionFilter = {}
// Trace inputs and results are reused through the trace `output` field.
local wallResult = {}
local wallTrace = { mask = MASK_SOLID, filter = collisionFilter, output = wallResult }
local groundResult = {}
local groundStart = Vector()
local groundEnd = Vector()
local groundTrace = { mask = MASK_SOLID_BRUSHONLY, output = groundResult, start = groundStart, endpos = groundEnd }
local tumbleAxis = Vector()

local function simulate(record, now, frameTime)
    local definition = record.definition
    local velocity = record.velocity
    if not record.grounded then
        velocity.z = velocity.z - definition.gravity * frameTime
    end
    local friction = math.exp(-(record.grounded and definition.groundFriction or definition.airFriction) * frameTime)
    velocity.x = velocity.x * friction
    velocity.y = velocity.y * friction

    // Each record alternates between two position vectors, so stepping does not allocate.
    local oldPosition = record.position
    local nextPosition = record.spare or Vector()
    nextPosition:SetUnpacked(oldPosition.x + velocity.x * frameTime, oldPosition.y + velocity.y * frameTime,
        oldPosition.z + velocity.z * frameTime)
    record.spare = nil
    wallTrace.start = oldPosition
    wallTrace.endpos = nextPosition
    local wall = util.TraceLine(wallTrace)
    if wall.Hit or wall.StartSolid then
        local normal = wall.HitNormal or -velocity:GetNormalized()
        record.velocity = (velocity - normal * 2 * velocity:Dot(normal)) * 0.35
        record.spare = nextPosition
        nextPosition = oldPosition
        velocity = record.velocity
    end

    groundStart:SetUnpacked(nextPosition.x, nextPosition.y, nextPosition.z + 20)
    groundEnd:SetUnpacked(nextPosition.x, nextPosition.y, nextPosition.z - (record.restHeight + 64))
    local ground = util.TraceLine(groundTrace)
    if ground.Hit and not ground.StartSolid then
        local groundZ = ground.HitPos.z + record.restHeight
        if groundZ - nextPosition.z > 18 then
            // A step this tall is a wall for debris; stay put and bounce off it.
            velocity.x, velocity.y = -velocity.x * 0.35, -velocity.y * 0.35
            if not rawequal(nextPosition, oldPosition) then
                record.spare = nextPosition
                nextPosition = oldPosition
            end
        elseif nextPosition.z <= groundZ + 0.5 and velocity.z <= 0 then
            nextPosition.z = groundZ
            record.normal = ground.HitNormal
            if velocity.z < -120 then
                velocity.z = -velocity.z * 0.3
                record.grounded = false
            else
                velocity.z = 0
                record.grounded = true
            end
        elseif nextPosition.z > groundZ + 1 then
            record.grounded = false
        end
    else
        record.grounded = false
        if nextPosition.z < record.home.z - 600 then
            if not rawequal(nextPosition, oldPosition) then
                record.spare = nextPosition
            end
            nextPosition = Vector(record.home)
            velocity:Zero()
            record.grounded = true
        end
    end

    local travelledX, travelledY = nextPosition.x - oldPosition.x, nextPosition.y - oldPosition.y
    local distance = math.sqrt(travelledX * travelledX + travelledY * travelledY)
    record.position = nextPosition
    if not rawequal(nextPosition, oldPosition) and not record.spare then
        record.spare = oldPosition
    end
    if distance > 0.01 then
        if record.kind == "rolling" then
            local axis = record.angles:Up()
            local rollDirection = axis:Cross(upVector)
            if rollDirection:LengthSqr() > 0.01 then
                rollDirection:Normalize()
                local rolled = travelledX * rollDirection.x + travelledY * rollDirection.y
                record.angles:RotateAroundAxis(axis, -math.deg(rolled / record.restHeight))
            end
            if not record.grounded then
                record.angles:RotateAroundAxis(upVector, record.spin * 360 * frameTime)
            end
        elseif record.kind == "tumbleweed" then
            // upVector x moveDirection, written out for a horizontal move.
            tumbleAxis:SetUnpacked(-travelledY / distance, travelledX / distance, 0)
            record.angles:RotateAroundAxis(tumbleAxis, math.deg(distance / record.restHeight))
        elseif record.kind == "paper" then
            record.angles.y = record.angles.y + (record.spin * 120 + 35) * frameTime
            local flutter = record.grounded and 0 or 15
            record.angles.p = math.sin(now * 7 + record.spin) * flutter
            record.angles.r = math.cos(now * 5 + record.spin) * flutter
        else
            record.angles.y = record.angles.y + record.spin * distance * 4
            if not record.grounded then
                record.angles.p = record.angles.p + record.spin * 360 * frameTime
            elseif math.abs(record.angles.p) > 0.1 then
                record.angles.p = 0
            end
        end
    end
    placeEntity(record)

    if record.grounded and record.kind ~= "tumbleweed" and record.velocity:LengthSqr() < 4 then
        record.velocity:Zero()
        record.moving = false
        if record.kind == "paper" then
            record.angles.p = 0
            record.angles.r = 0
            placeEntity(record)
        end
    end
end

local nextSiteCheckAt = 0
hook.Add("Think", "ZM.Foliage.AmbientDebris", function()
    local now = CurTime()
    local localPlayer = LocalPlayer()
    if now >= nextSiteCheckAt then
        nextSiteCheckAt = now + Debris.SiteCheckInterval
        Debris:UpdateSites(localPlayer)
    end
    if table.IsEmpty(Debris.Active) or not IsValid(localPlayer) then
        return
    end

    if now >= Debris.NextGustAt then
        local windAngle = math.atan2(Debris.WindDirection.y, Debris.WindDirection.x) + math.Rand(-0.6, 0.6)
        Debris.WindDirection = Vector(math.cos(windAngle), math.sin(windAngle), 0)
        local gustAngle = windAngle + math.Rand(-0.5, 0.5)
        Debris.GustDirection = Vector(math.cos(gustAngle), math.sin(gustAngle), 0)
        Debris.GustEndsAt = now + math.Rand(1, 2.5)
        Debris.NextGustAt = now + math.Rand(8, 18)
    end

    table.Empty(collisionFilter)
    for _, target in ipairs(player.GetAll()) do
        table.insert(collisionFilter, target)
    end
    gatherKickers()

    local frameTime = math.min(FrameTime(), 0.05)
    local viewer = localPlayer:GetPos()
    local simulationDistance = Debris.SimulationDistance * Debris.SimulationDistance
    for key, record in pairs(Debris.Active) do
        if not IsValid(record.entity) then
            Debris.Active[key] = nil
        elseif record.position:DistToSqr(viewer) <= simulationDistance then
            kickFromPlayers(record, now)
            applyWind(record, now, frameTime)
            if record.moving then
                simulate(record, now, frameTime)
            end
        end
    end
end)

hook.Add("PreCleanupMap", "ZM.Foliage.AmbientDebrisCleanup", function()
    Debris:Cleanup()
end)
hook.Add("ShutDown", "ZM.Foliage.AmbientDebrisShutdown", function()
    Debris:Cleanup()
end)

concommand.Add("zombiesim_ambient_debris_status", function()
    local counts = {}
    local moving = 0
    for _, record in pairs(Debris.Active) do
        counts[record.kind] = (counts[record.kind] or 0) + 1
        if record.moving then
            moving = moving + 1
        end
    end
    local parts = {}
    for kind, count in SortedPairs(counts) do
        table.insert(parts, kind .. "=" .. count)
    end
    print(string.format("[ZombieSim] Ambient debris: amount=%.1f models=%d moving=%d %s",
        Debris.GetAmount(), table.Count(Debris.Active), moving, table.concat(parts, " ")))
end)
