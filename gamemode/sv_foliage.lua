// Server-owned, deterministic per-cell harvestable foliage. Visual debris remains client-only.
ZM_Foliage = ZM_Foliage or {}
local Foliage = ZM_Foliage

if Foliage.Cleanup then
    Foliage:Cleanup()
end

Foliage.Models = {
    tree = "models/props/de_inferno/tree_small.mdl",
    berry = "models/props/de_inferno/bushgreensmall.mdl"
}
Foliage.HarvestRange = 96
Foliage.TreeCooldownSeconds = 7 * 24 * 60 * 60
Foliage.BerryCooldownSeconds = 24 * 60 * 60
Foliage.MaxNodesPerCell = 18
Foliage.MaxPlacementAttempts = 240
Foliage.PlacementBatchSize = 6
Foliage.PlacementInterval = 0.05
Foliage.MinPlantSpacing = 240
Foliage.MapEdgeMargin = 256
Foliage.MeshVersion = 1
Foliage.StorageReady = Foliage.StorageReady == true
Foliage.BuildTimer = "ZM.Foliage.Build"
Foliage.RegrowthTimer = "ZM.Foliage.Regrowth"
Foliage.SuitableSurfaceProps = {
    grass = true,
    dirt = true,
    mud = true,
    gravel = true,
    sand = true
}

local rewardCounts = {
    tree = { minimum = 2, maximum = 4 },
    berry = { minimum = 3, maximum = 5 }
}
local blockedMaterialWords = { "asphalt", "road", "street", "concrete", "sidewalk", "brick", "metal", "wood", "nodraw" }
local excludedClassWords = { "door", "gate", "transition", "spawn", "entrance", "exit" }
local yellowColor = Color(255, 225, 110)
local depletedColor = Color(135, 135, 135)

local function mapBasename(path)
    return string.lower(string.match(path or "", "([^/\\]+)$") or path or "")
end

local function isHarvestableSeason(nodeType, month)
    if nodeType == "tree" then
        return true
    end
    return nodeType == "berry" and month >= 3 and month <= 11
end

function Foliage.GetBerrySeason(month)
    if month >= 3 and month <= 8 then
        return "plentiful"
    end
    if month >= 9 and month <= 11 then
        return "scarce"
    end
    return "winter"
end

function Foliage.GetCooldown(nodeType)
    if nodeType == "tree" then
        return Foliage.TreeCooldownSeconds
    end
    if nodeType == "berry" then
        return Foliage.BerryCooldownSeconds
    end
    return nil
end

function Foliage.GetReward(nodeType, month, rng)
    if nodeType == "tree" then
        local count = rewardCounts.tree
        return "itemWood", rng:Int(count.minimum, count.maximum)
    end
    if nodeType == "berry" then
        local season = Foliage.GetBerrySeason(month)
        if season == "winter" then
            return nil, "There are no ripe berries in winter."
        end
        local minimum = season == "plentiful" and 3 or 1
        local maximum = season == "plentiful" and 5 or 2
        return "itemBerries", rng:Int(minimum, maximum)
    end
    return nil, "That plant cannot be harvested."
end

function Foliage.HasEquippedMelee(target)
    local inventory = target and target.ZM_Inventory
    for _, instance in pairs(inventory and inventory.equipped or {}) do
        local definition = ZM_Items:GetDefinition(instance.itemId)
        if definition and definition.type == "melee_weapon" then
            return true
        end
    end
    return false
end

function Foliage.GetSeed(profile, cellId, mapName)
    local value = tostring(profile) .. ":" .. tostring(cellId) .. ":" .. tostring(mapName)
    local seed = 0
    for index = 1, #value do
        seed = (seed * 33 + string.byte(value, index)) % 2147483647
    end
    return math.max(seed, 1)
end

function Foliage.IsSuitableGround(trace)
    if type(trace) ~= "table" or trace.Hit ~= true or trace.HitSky == true then
        return false, "no_ground"
    end
    if not trace.HitNormal or trace.HitNormal.z < 0.82 then
        return false, "slope"
    end
    if type(util.GetSurfacePropName) ~= "function" then
        return false, "no_surface_lookup"
    end
    local surfaceName = string.lower(util.GetSurfacePropName(trace.SurfaceProps) or "")
    if not Foliage.SuitableSurfaceProps[surfaceName] then
        return false, "surface_prop"
    end
    local texture = string.lower(tostring(trace.HitTexture or ""))
    for _, word in ipairs(blockedMaterialWords) do
        if string.find(texture, word, 1, true) then
            return false, "texture"
        end
    end
    return true
end

function Foliage.MakeCandidate(bounds, rng, attempt, traceGround, isOccupied, existingPositions)
    local minimumX = bounds.minimum.x + Foliage.MapEdgeMargin
    local maximumX = bounds.maximum.x - Foliage.MapEdgeMargin
    local minimumY = bounds.minimum.y + Foliage.MapEdgeMargin
    local maximumY = bounds.maximum.y - Foliage.MapEdgeMargin
    if maximumX <= minimumX or maximumY <= minimumY then
        return nil, "bounds"
    end

    local x = minimumX + rng:Next() * (maximumX - minimumX)
    local y = minimumY + rng:Next() * (maximumY - minimumY)
    local nodeType = rng:Chance(0.38) and "tree" or "berry"
    local trace = traceGround(x, y, bounds)
    local suitable, groundReason = Foliage.IsSuitableGround(trace)
    if not suitable then
        return nil, groundReason
    end
    local position = trace.HitPos + trace.HitNormal * 2
    if isOccupied(position, nodeType) then
        return nil, "occupied"
    end

    for _, existing in ipairs(existingPositions) do
        if existing.position:DistToSqr(position) < Foliage.MinPlantSpacing * Foliage.MinPlantSpacing then
            return nil, "spacing"
        end
    end

    return {
        key = string.format("v%d_%03d", Foliage.MeshVersion, attempt),
        type = nodeType,
        position = position,
        yaw = rng:Int(0, 359)
    }
end

local function getWorldBounds()
    local world = game.GetWorld()
    if not world or world == NULL or not world:IsWorld() then
        return nil, "world entity is unavailable"
    end
    // GetRenderBounds is client-only; the server falls back to model bounds and worldspawn's stored extents.
    local function valid(minimum, maximum)
        return minimum and maximum and maximum.x > minimum.x and maximum.y > minimum.y and maximum.z > minimum.z
    end
    local minimum, maximum = world:WorldSpaceAABB()
    if not valid(minimum, maximum) and world.GetModelBounds then
        minimum, maximum = world:GetModelBounds()
    end
    if not valid(minimum, maximum) and world.GetInternalVariable then
        minimum, maximum = world:GetInternalVariable("m_WorldMins"), world:GetInternalVariable("m_WorldMaxs")
        if not isvector(minimum) or not isvector(maximum) then
            minimum, maximum = nil, nil
        end
    end
    if not minimum or not maximum or maximum.x <= minimum.x or maximum.y <= minimum.y or maximum.z <= minimum.z then
        return nil, "world bounds are invalid"
    end
    return { minimum = minimum, maximum = maximum }
end

local function traceGround(x, y, bounds)
    // Sealed cells are capped by a skybox brush, so step through sky/tool faces until real ground is hit.
    local bottom = Vector(x, y, bounds.minimum.z - 64)
    local start = Vector(x, y, bounds.maximum.z - 1)
    local trace
    for _ = 1, 8 do
        trace = util.TraceLine({ start = start, endpos = bottom, mask = MASK_SOLID_BRUSHONLY })
        if trace.StartSolid and trace.FractionLeftSolid and trace.FractionLeftSolid < 1 then
            start = start + (bottom - start) * trace.FractionLeftSolid - Vector(0, 0, 2)
        elseif trace.Hit and (trace.HitSky or string.StartWith(string.lower(tostring(trace.HitTexture or "")), "tools/")) then
            start = trace.HitPos - Vector(0, 0, 2)
        else
            return trace
        end
        if start.z <= bottom.z then
            break
        end
    end
    return trace
end

local function isNamedExclusion(entity)
    local className = string.lower(entity:GetClass() or "")
    local targetName = entity.GetName and string.lower(entity:GetName() or "") or ""
    for _, word in ipairs(excludedClassWords) do
        if string.find(className, word, 1, true) or string.find(targetName, word, 1, true) then
            return true
        end
    end
    return false
end

local function isOccupied(position, nodeType)
    local radius = nodeType == "tree" and 36 or 24
    local height = nodeType == "tree" and 176 or 88
    local nearby = ents.FindInSphere(position, 112)
    for _, entity in ipairs(nearby) do
        if IsValid(entity) then
            if entity:IsPlayer() or string.StartWith(entity:GetClass(), "prop_") or isNamedExclusion(entity) then
                return true
            end
        end
    end

    local trace = util.TraceHull({
        start = position + Vector(0, 0, 8),
        endpos = position + Vector(0, 0, height),
        mins = Vector(-radius, -radius, 0),
        maxs = Vector(radius, radius, 8),
        mask = MASK_SOLID
    })
    return trace.Hit or trace.StartSolid
end

// Shared with runtime fallen-body placement (sv_loot_bodies.lua).
Foliage.GetWorldBounds = getWorldBounds
Foliage.TraceGround = traceGround
Foliage.IsNamedExclusion = isNamedExclusion

local function setNodeVisual(node, now)
    local month = os.date("*t", now or os.time()).month
    local seasonal = isHarvestableSeason(node.type, month)
    local available = seasonal and (not node.availableAt or node.availableAt <= (now or os.time()))
    node.available = available
    local entity = node.entity
    if IsValid(entity) then
        entity:SetNWBool("ZM_FoliageAvailable", available)
        entity:SetNWString("ZM_FoliageType", node.type)
        entity:SetNWFloat("ZM_FoliageAvailableAt", tonumber(node.availableAt) or 0)
        entity:SetColor(available and yellowColor or depletedColor)
    end
end

local function removeNodeEntities(cell)
    for _, node in pairs(cell and cell.nodes or {}) do
        if IsValid(node.entity) then
            node.entity:Remove()
        end
    end
end

function Foliage:Cleanup()
    timer.Remove(self.BuildTimer)
    timer.Remove(self.RegrowthTimer)
    removeNodeEntities(self.Cell)
    self.Cell = nil
end

local function createNode(candidate, oldStates)
    local model = Foliage.Models[candidate.type]
    if not util.IsValidModel(model) then
        return nil, "mounted model is unavailable: " .. model
    end
    local entity = ents.Create("prop_dynamic")
    if not IsValid(entity) then
        return nil, "could not create prop_dynamic"
    end
    entity:SetModel(model)
    entity:SetPos(candidate.position)
    entity:SetAngles(Angle(0, candidate.yaw, 0))
    entity:SetSolid(SOLID_NONE)
    entity:SetNotSolid(true)
    entity:SetMoveType(MOVETYPE_NONE)
    entity:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    entity:SetRenderMode(RENDERMODE_TRANSCOLOR)
    entity:DrawShadow(false)
    entity:Spawn()
    entity:Activate()
    local state = oldStates[candidate.key]
    local node = {
        key = candidate.key,
        type = candidate.type,
        position = candidate.position,
        entity = entity,
        availableAt = state and tonumber(state.availableAt) or nil
    }
    setNodeVisual(node)
    return node
end

local function baseSeed(profile, cellId, mapName)
    return Foliage.GetSeed(profile, cellId, mapName)
end

function Foliage:BeginCell(profile, cellId)
    if type(util.GetSurfacePropName) ~= "function" then
        return false, "surface-property lookup is unavailable"
    end
    for _, model in pairs(self.Models) do
        if not util.IsValidModel(model) then
            return false, "mounted foliage model is unavailable: " .. model
        end
    end
    local bounds, boundsError = getWorldBounds()
    if not bounds then
        return false, boundsError
    end
    local states, stateError = ZM_GetFoliageHarvests(profile, cellId)
    if not states then
        return false, stateError
    end
    local oldStates = {}
    for _, row in ipairs(states) do
        oldStates[row.nodeKey] = { availableAt = tonumber(row.availableAt) }
    end
    local mapName = game.GetMap()
    local state = {
        profile = profile,
        cellId = cellId,
        map = mapName,
        bounds = bounds,
        rng = ZM_ItemGeneration.NewRng(baseSeed(profile, cellId, mapName)),
        oldStates = oldStates,
        nodes = {},
        positions = {},
        attempts = 0,
        status = "building",
        rejected = 0,
        rejections = {},
        surfaces = {}
    }
    // Records what the placement traces actually hit so empty cells can be diagnosed from zn_foliage_status.
    local function sampledTraceGround(x, y, traceBounds)
        local trace = traceGround(x, y, traceBounds)
        if trace and trace.Hit then
            local surfaceName = util.GetSurfacePropName(trace.SurfaceProps) or "?"
            local key = string.lower(surfaceName) .. "|" .. string.lower(tostring(trace.HitTexture or "?"))
            state.surfaces[key] = (state.surfaces[key] or 0) + 1
        end
        return trace
    end
    self.Cell = state
    timer.Remove(self.BuildTimer)
    timer.Create(self.BuildTimer, self.PlacementInterval, 0, function()
        if self.Cell ~= state then
            timer.Remove(self.BuildTimer)
            return
        end
        for _ = 1, self.PlacementBatchSize do
            if state.attempts >= self.MaxPlacementAttempts or table.Count(state.nodes) >= self.MaxNodesPerCell then
                break
            end
            state.attempts = state.attempts + 1
            local candidate, rejectReason = self.MakeCandidate(
                state.bounds,
                state.rng,
                state.attempts,
                sampledTraceGround,
                isOccupied,
                state.positions
            )
            if candidate then
                local node, nodeError = createNode(candidate, state.oldStates)
                if node then
                    state.nodes[node.key] = node
                    table.insert(state.positions, node)
                else
                    state.rejected = state.rejected + 1
                    ErrorNoHalt("[ZombieSim] Runtime foliage node skipped: " .. tostring(nodeError) .. "\n")
                end
            else
                state.rejected = state.rejected + 1
                local reason = rejectReason or "unknown"
                state.rejections[reason] = (state.rejections[reason] or 0) + 1
            end
        end
        if state.attempts >= self.MaxPlacementAttempts or table.Count(state.nodes) >= self.MaxNodesPerCell then
            timer.Remove(self.BuildTimer)
            state.status = "ready"
            print(string.format("[ZombieSim] Runtime foliage for cell %d: %d nodes after %d placement attempts.",
                state.cellId, table.Count(state.nodes), state.attempts))
            if table.Count(state.nodes) == 0 then
                ErrorNoHalt("[ZombieSim] Runtime foliage found no suitable ground placements on "
                    .. tostring(state.map) .. "; no nodes were spawned.\n")
            end
        end
    end)
    timer.Create(self.RegrowthTimer, 5, 0, function()
        if self.Cell ~= state then
            timer.Remove(self.RegrowthTimer)
            return
        end
        self:RefreshRegrowth(os.time())
    end)
    return true
end

function Foliage:OnPlayerReady(target)
    if not self.StorageReady or not IsValid(target) or not target:IsPlayer()
        or target.ZM_PersistentStateLoaded ~= true then
        return false
    end
    local cell = target:GetWorldCell()
    if not cell or (ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell))
        or (target.CurrentSafeZoneId and target.CurrentSafeZoneId ~= "") then
        self:Cleanup()
        return false
    end
    if mapBasename(ZM_World:GetMapPath(cell)) ~= mapBasename(game.GetMap()) then
        self:Cleanup()
        return false
    end
    if self.Cell and self.Cell.profile == ZM_World.ActiveProfile and self.Cell.cellId == cell.id then
        return true
    end
    self:Cleanup()
    local started, startError = self:BeginCell(ZM_World.ActiveProfile, cell.id)
    if not started then
        ErrorNoHalt("[ZombieSim] Runtime foliage could not start: " .. tostring(startError) .. "\n")
        return false
    end
    return true
end

function Foliage:RefreshRegrowth(now)
    local cell = self.Cell
    if not cell then
        return
    end
    for _, node in pairs(cell.nodes) do
        if node.availableAt and node.availableAt <= now then
            local removed, removeError = ZM_DeleteFoliageHarvest(cell.profile, cell.cellId, node.key)
            if not removed then
                ErrorNoHalt("[ZombieSim] Could not clear regrown foliage state: " .. tostring(removeError) .. "\n")
            end
            node.availableAt = nil
        end
        setNodeVisual(node, now)
    end
end

function Foliage.GetDistance(target, node)
    local center = target:WorldSpaceCenter()
    return center:Distance(node.position)
end

function Foliage:FindNearestNode(target)
    local cell = self.Cell
    if not cell then
        return nil
    end
    local nearest, nearestDistance = nil, self.HarvestRange
    for _, node in pairs(cell.nodes) do
        if IsValid(node.entity) then
            local distance = self.GetDistance(target, node)
            if distance <= nearestDistance then
                nearest, nearestDistance = node, distance
            end
        end
    end
    return nearest
end

function Foliage:Harvest(target, node, now, date, rng)
    now = now or os.time()
    local cell = self.Cell
    if not cell or cell.nodes[node.key] ~= node then
        return false, "That plant is no longer here."
    end
    if not target:Alive() then
        return false, "You are dead."
    end
    if self.GetDistance(target, node) > self.HarvestRange then
        return false, "You are too far away."
    end
    if node.availableAt and node.availableAt > now then
        return false, "This plant has already been harvested."
    end
    date = date or os.date("*t", now)
    if node.type == "tree" and not self.HasEquippedMelee(target) then
        return false, "You need an equipped melee weapon to harvest wood."
    end
    rng = rng or ZM_ItemGeneration.NewRng(math.random(1, 2147483646))
    local itemId, countOrReason = self.GetReward(node.type, date.month, rng)
    if not itemId then
        return false, countOrReason
    end

    local availableAt = now + self.GetCooldown(node.type)
    local saved, saveError = ZM_SetFoliageHarvest(cell.profile, cell.cellId, node.key, availableAt)
    if not saved then
        ErrorNoHalt("[ZombieSim] Could not save foliage harvest state: " .. tostring(saveError) .. "\n")
        return false, "The harvest could not be saved."
    end
    node.availableAt = availableAt
    setNodeVisual(node, now)

    local granted, grantError = target:GiveItem(itemId, countOrReason)
    if not granted then
        local restored, restoreError = ZM_DeleteFoliageHarvest(cell.profile, cell.cellId, node.key)
        if restored then
            node.availableAt = nil
            setNodeVisual(node, now)
        else
            ErrorNoHalt("[ZombieSim] Could not restore foliage availability after a failed reward: " .. tostring(restoreError) .. "\n")
        end
        return false, "Could not carry the harvest: " .. tostring(grantError)
    end
    return true, string.format("Harvested %d %s.", countOrReason, itemId == "itemWood" and "wood" or "berries")
end

function Foliage:UseNearestNode(target)
    if target.ZM_LootSearch or target.ZM_LootOffer then
        return false
    end
    local lootSpot = ZM_LootSpots and ZM_LootSpots:FindNearestSpot(target)
    if lootSpot and ZM_LootSpots.GetDistance(target, lootSpot) <= self.HarvestRange then
        return false
    end
    local node = self:FindNearestNode(target)
    if not node then
        return false
    end
    local ok, message = self:Harvest(target, node)
    target:ChatPrint(message)
    return ok
end

hook.Add("KeyPress", "ZM.Foliage.Harvest", function(target, key)
    if key == IN_USE and IsValid(target) and target:IsPlayer() and target:Alive() and Foliage.Cell then
        Foliage:UseNearestNode(target)
    end
end)

hook.Add("PreCleanupMap", "ZM.Foliage.Cleanup", function()
    Foliage:Cleanup()
end)

hook.Add("ShutDown", "ZM.Foliage.CleanupShutdown", function()
    Foliage:Cleanup()
end)

ZM_Util.RegisterCommands({
    zn_foliage_status = "Reports runtime foliage placement and harvest status for the current cell.",
    zn_foliage_rebuild = "Clears and re-places runtime foliage for the first player's current cell."
}, function(caller, command)
    if not ZM_Util.RequireAdmin(caller, command) then
        return
    end
    if command == "zn_foliage_rebuild" then
        local target = ZM_Util.FirstHuman()
        if not IsValid(target) then
            ZM_Util.Reply(caller, "No player is available for a foliage rebuild.")
            return
        end
        Foliage:Cleanup()
        Foliage:OnPlayerReady(target)
        ZM_Util.Reply(caller, "Runtime foliage rebuild started.")
        return
    end
    local cell = Foliage.Cell
    if not cell then
        ZM_Util.Reply(caller, "Runtime foliage is inactive.")
        return
    end
    local trees, berries, available = 0, 0, 0
    for _, node in pairs(cell.nodes) do
        if node.type == "tree" then trees = trees + 1 else berries = berries + 1 end
        if node.available then available = available + 1 end
    end
    ZM_Util.Reply(caller, string.format(
        "Runtime foliage: profile=%s cell=%d status=%s nodes=%d trees=%d berries=%d available=%d attempts=%d rejected=%d",
        cell.profile, cell.cellId, cell.status, table.Count(cell.nodes), trees, berries, available,
        cell.attempts, cell.rejected))
    local reasons = {}
    for reason, count in SortedPairs(cell.rejections or {}) do
        table.insert(reasons, reason .. "=" .. count)
    end
    if #reasons > 0 then
        ZM_Util.Reply(caller, "Rejections: " .. table.concat(reasons, " "))
    end
    local surfaces = {}
    for key, count in pairs(cell.surfaces or {}) do
        table.insert(surfaces, { key = key, count = count })
    end
    table.sort(surfaces, function(left, right) return left.count > right.count end)
    for index = 1, math.min(#surfaces, 10) do
        ZM_Util.Reply(caller, string.format("Surface %s x%d", surfaces[index].key, surfaces[index].count))
    end
end)
