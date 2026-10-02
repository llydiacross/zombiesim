// Server-only fallen bodies: each city cell gets a few deterministic prop_ragdoll bodies that become loot spots through
// their entity_loot rules. Positions, models, and spot keys come from the profile/cell/map seed, so a reloaded cell
// recreates the same bodies under the same keys and the loot-spot store keeps their searched state.
ZM_LootBodies = ZM_LootBodies or {}
local Bodies = ZM_LootBodies
local Foliage = ZM_Foliage

Bodies.Version = 1
Bodies.MinCount = 2
Bodies.MaxCount = 4
Bodies.MaxAttempts = 80
Bodies.MapEdgeMargin = 256
Bodies.MinSpacing = 320
Bodies.BodyLength = 72
Bodies.SettleSeconds = 3
// Loot-group weights decide which kind of body is chosen; models are then picked evenly within the family.
Bodies.FamilyWeights = {
    lootBodyCivilian = 40,
    lootBodyRebel = 22,
    lootBodyBird = 12,
    lootBodyCharred = 10,
    lootBodyMilitary = 8,
    lootBodyMedic = 8
}
Bodies.DefaultFamilyWeight = 5

local function mapBasename(path)
    return string.lower(string.match(path or "", "([^/]+)$") or path or "")
end

// Families { group, weight, models } built from every prop_ragdoll entity_loot rule, sorted for determinism.
function Bodies.BuildPool(byModel)
    local families = {}
    for model, rule in pairs(byModel or {}) do
        local group = rule.lootGroups and rule.lootGroups[1]
        if group and (not util.IsValidRagdoll or util.IsValidRagdoll(model)) then
            families[group] = families[group] or { group = group, weight = Bodies.FamilyWeights[group] or Bodies.DefaultFamilyWeight, models = {} }
            table.insert(families[group].models, model)
        end
    end
    local pool = {}
    for _, family in SortedPairs(families) do
        table.sort(family.models)
        if family.weight > 0 then
            table.insert(pool, family)
        end
    end
    return pool
end

function Bodies.PickModel(pool, rng)
    local total = 0
    for _, family in ipairs(pool) do
        total = total + family.weight
    end
    if total <= 0 then
        return nil
    end
    local roll = rng:Next() * total
    for _, family in ipairs(pool) do
        roll = roll - family.weight
        if roll <= 0 then
            return family.models[rng:Int(1, #family.models)], family.group
        end
    end
    local last = pool[#pool]
    return last.models[#last.models], last.group
end

function Bodies.IsSuitableGround(trace)
    if type(trace) ~= "table" or trace.Hit ~= true or trace.HitSky == true then
        return false
    end
    if not trace.HitNormal or trace.HitNormal.z < 0.82 then
        return false
    end
    local texture = string.lower(tostring(trace.HitTexture or ""))
    return not string.StartWith(texture, "tools/") and not string.find(texture, "water", 1, true)
end

// Plans bodies with injected world access: traceGround(x, y, bounds) and isBlocked(position, angles).
// Every random draw happens before any rejection check, so one rejected attempt never shifts later attempts.
function Bodies.Plan(rng, bounds, pool, traceGround, isBlocked)
    local plans = {}
    if #pool == 0 then
        return plans
    end
    local minimumX = bounds.minimum.x + Bodies.MapEdgeMargin
    local maximumX = bounds.maximum.x - Bodies.MapEdgeMargin
    local minimumY = bounds.minimum.y + Bodies.MapEdgeMargin
    local maximumY = bounds.maximum.y - Bodies.MapEdgeMargin
    if maximumX <= minimumX or maximumY <= minimumY then
        return plans
    end
    local wanted = rng:Int(Bodies.MinCount, Bodies.MaxCount)
    for attempt = 1, Bodies.MaxAttempts do
        if #plans >= wanted then
            break
        end
        local x = minimumX + rng:Next() * (maximumX - minimumX)
        local y = minimumY + rng:Next() * (maximumY - minimumY)
        local model, group = Bodies.PickModel(pool, rng)
        local faceDown = rng:Chance(0.4)
        local yaw = rng:Int(0, 359)
        local trace = traceGround(x, y, bounds)
        if model and Bodies.IsSuitableGround(trace) then
            local position = trace.HitPos + Vector(0, 0, 10)
            local angles = Angle(faceDown and 90 or -90, yaw, 0)
            local spaced = true
            for _, existing in ipairs(plans) do
                if existing.position:DistToSqr(position) < Bodies.MinSpacing * Bodies.MinSpacing then
                    spaced = false
                    break
                end
            end
            if spaced and not isBlocked(position, angles) then
                table.insert(plans, {
                    key = string.format("b%d_%02d", Bodies.Version, attempt),
                    model = model,
                    group = group,
                    position = position,
                    angles = angles,
                    ground = trace.HitPos
                })
            end
        end
    end
    return plans
end

// Map-static blockers only: players and enemies move between loads and must not change the deterministic plan.
local function isBlocked(position, angles)
    if navmesh and navmesh.IsLoaded and navmesh.IsLoaded() and not navmesh.GetNavArea(position, 64) then
        return true
    end
    for _, entity in ipairs(ents.FindInSphere(position, 96)) do
        if IsValid(entity) and (string.StartWith(entity:GetClass(), "prop_") or Foliage.IsNamedExclusion(entity)) then
            return true
        end
    end
    local length = angles:Up() * Bodies.BodyLength
    length.z = 0
    local start = position + Vector(0, 0, 4)
    local trace = util.TraceHull({
        start = start,
        endpos = start + length,
        mins = Vector(-14, -14, 0),
        maxs = Vector(14, 14, 12),
        mask = MASK_SOLID
    })
    if trace.Hit or trace.StartSolid then
        return true
    end
    local headroom = util.TraceLine({ start = start, endpos = start + Vector(0, 0, 48), mask = MASK_SOLID })
    return headroom.Hit
end

function Bodies:Cleanup()
    for _, entity in ipairs(self.Cell and self.Cell.entities or {}) do
        if IsValid(entity) then
            entity:Remove()
        end
    end
    self.Cell = nil
end

local function settle(entity)
    if not IsValid(entity) then
        return
    end
    for index = 0, entity:GetPhysicsObjectCount() - 1 do
        local physics = entity:GetPhysicsObjectNum(index)
        if IsValid(physics) then
            physics:EnableMotion(false)
            physics:Sleep()
        end
    end
end

function Bodies:SpawnPlan(plan)
    local entity = ents.Create("prop_ragdoll")
    if not IsValid(entity) then
        return nil
    end
    entity:SetModel(plan.model)
    entity:SetPos(plan.position)
    entity:SetAngles(plan.angles)
    entity.ZM_LootSpotKey = plan.key
    entity.ZM_FallenBody = true
    entity:Spawn()
    entity:Activate()
    entity:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    for index = 0, entity:GetPhysicsObjectCount() - 1 do
        local physics = entity:GetPhysicsObjectNum(index)
        if IsValid(physics) then
            physics:Wake()
        end
    end
    if plan.group ~= "lootBodyBird" then
        util.Decal("Blood", plan.ground + Vector(0, 0, 8), plan.ground - Vector(0, 0, 16))
    end
    timer.Simple(self.SettleSeconds, function()
        settle(entity)
    end)
    return entity
end

// Spawns the cell's bodies once per map, the first time a loaded player is on their own city-cell map.
function Bodies:OnPlayerReady(target)
    if self.Cell or not IsValid(target) or not target:IsPlayer() or target.ZM_PersistentStateLoaded ~= true then
        return false
    end
    if type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" then
        return false
    end
    local cell = target:GetWorldCell()
    if not cell or (ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell)) then
        return false
    end
    local mapName = mapBasename(game.GetMap())
    if mapBasename(ZM_World:GetMapPath(cell)) ~= mapName then
        return false
    end
    local registry = ZM_StaticData.Registry
    local pool = Bodies.BuildPool(registry and registry.entityLoot.byClass.prop_ragdoll)
    local bounds, boundsError = Foliage.GetWorldBounds()
    if not bounds then
        ErrorNoHalt("[ZombieSim] Fallen bodies could not be placed: " .. tostring(boundsError) .. "\n")
        return false
    end
    local seed = Foliage.GetSeed(ZM_World.ActiveProfile, cell.id, mapName .. ":bodies")
    local plans = Bodies.Plan(ZM_ItemGeneration.NewRng(seed), bounds, pool, Foliage.TraceGround, isBlocked)
    self.Cell = { profile = ZM_World.ActiveProfile, cellId = cell.id, map = mapName, entities = {} }
    for _, plan in ipairs(plans) do
        local entity = self:SpawnPlan(plan)
        if entity then
            table.insert(self.Cell.entities, entity)
        end
    end
    print(string.format("[ZombieSim] Fallen bodies for cell %d: %d placed.", cell.id, #self.Cell.entities))
    return true
end
