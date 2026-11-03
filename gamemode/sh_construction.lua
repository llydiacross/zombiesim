// Shared construction rules. The Hammer is the building tool: while it is held, Reload toggles build mode.
// Build speed scales linearly with the hammer's item level, and a mastercrafted (including ultra) hammer halves
// each material cost, rounded up to at least one.
ZM_Construction = ZM_Construction or {}
local Construction = ZM_Construction

Construction.ToolClass = "weapon_zn_hammer"
Construction.ToolItemId = "weaponMeleeHammer"
Construction.PieceClass = "zn_construction_piece"
// Protection reaches this far beyond the edges of an accessible active claim tile.
Construction.ProtectionMargin = 640
Construction.MinSpeed = 1
Construction.MaxSpeed = 2
Construction.GridSize = 64
Construction.PlaceReach = 256
Construction.DeleteReach = 1024
Construction.PieceModel = "models/hunter/blocks/cube025x025x025.mdl"

local function prism(points, bottom, top)
    local vertices, faces, count = {}, {}, #points
    for index, point in ipairs(points) do
        vertices[index] = { point[1], point[2], bottom[index] }
        vertices[index + count] = { point[1], point[2], top[index] }
    end
    local lower, upper = {}, {}
    for index = 1, count do
        lower[index] = count - index + 1
        upper[index] = count + index
    end
    faces[1], faces[2] = lower, upper
    for index = 1, count do
        local nextIndex = index % count + 1
        faces[#faces + 1] = { index, nextIndex, nextIndex + count, index + count }
    end
    return { vertices = vertices, faces = faces }
end

local function box(x1, y1, z1, x2, y2, z2)
    local part = prism({ { x1, y1 }, { x2, y1 }, { x2, y2 }, { x1, y2 } },
        { z1, z1, z1, z1 }, { z2, z2, z2, z2 })
    part.box = true
    return part
end

local function triangle(height)
    return prism({ { -32, -32 }, { 32, -32 }, { -32, 32 } },
        { 0, 0, 0 }, { height, height, height })
end

local function roofCorner(inner)
    local a, b, c, d = { -32, -32 }, { 32, -32 }, { 32, 32 }, { -32, 32 }
    local edge = inner and 32 or 0
    return {
        prism({ a, b, c }, { 0, edge, 32 }, { 8, edge + 8, 40 }),
        prism({ a, c, d }, { 0, 32, edge }, { 8, 40, edge + 8 })
    }
end

local function stairs()
    local parts = {}
    for index = 0, 7 do
        parts[#parts + 1] = box(-64 + index * 16, -32, 0, -48 + index * 16, 32, (index + 1) * 16)
    end
    return parts
end

// The approved foundation and wall retain their dimensions and appearance. New prices and times are provisional.
Construction.Pieces = {
    foundation = { name = "Foundation", category = "Foundations", snap = "grid", material = "floor",
        buildSeconds = 6, cost = { itemWood = 4, itemScrapMetal = 2 }, parts = { box(-32, -32, 0, 32, 32, 16) } },
    foundation_half = { name = "Half Foundation", category = "Foundations", snap = "half", material = "floor",
        buildSeconds = 3, cost = { itemWood = 2, itemScrapMetal = 1 }, parts = { box(-32, -16, 0, 32, 16, 16) } },
    foundation_triangle = { name = "Triangle Foundation", category = "Foundations", snap = "rotated", material = "floor",
        buildSeconds = 3, cost = { itemWood = 2, itemScrapMetal = 1 }, parts = { triangle(16) } },
    floor = { name = "Floor", category = "Floors", snap = "grid", material = "floor",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = { box(-32, -32, 0, 32, 32, 8) } },
    floor_half = { name = "Half Floor", category = "Floors", snap = "half", material = "floor",
        buildSeconds = 3, cost = { itemWood = 2, itemScrapMetal = 1 }, parts = { box(-32, -16, 0, 32, 16, 8) } },
    floor_triangle = { name = "Triangle Floor", category = "Floors", snap = "rotated", material = "floor",
        buildSeconds = 3, cost = { itemWood = 2, itemScrapMetal = 1 }, parts = { triangle(8) } },
    wall = { name = "Wall", category = "Walls", snap = "wall", material = "wall", slotGroup = "wall",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = { box(-32, -4, 0, 32, 4, 128) } },
    wall_half = { name = "Half Wall", category = "Walls", snap = "wall", material = "wall", slotGroup = "wall",
        buildSeconds = 3, cost = { itemWood = 2, itemScrapMetal = 1 }, parts = { box(-32, -4, 0, 32, 4, 64) } },
    wall_doorway = { name = "Doorway", category = "Walls", snap = "wall", material = "wall", slotGroup = "wall",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = {
            box(-32, -4, 0, -24, 4, 112), box(24, -4, 0, 32, 4, 112), box(-32, -4, 112, 32, 4, 128)
        } },
    wall_window = { name = "Window Wall", category = "Walls", snap = "wall", material = "wall", slotGroup = "wall",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = {
            box(-32, -4, 0, 32, 4, 40), box(-32, -4, 96, 32, 4, 128),
            box(-32, -4, 40, -24, 4, 96), box(24, -4, 40, 32, 4, 96)
        } },
    roof_flat = { name = "Flat Roof", category = "Roofs", snap = "grid", material = "floor",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = { box(-32, -32, 0, 32, 32, 8) } },
    roof_slope = { name = "Sloped Roof", category = "Roofs", snap = "rotated", material = "floor",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = {
            prism({ { -32, -32 }, { 32, -32 }, { 32, 32 }, { -32, 32 } },
                { 0, 32, 32, 0 }, { 8, 40, 40, 8 })
        } },
    roof_corner_outer = { name = "Outer Roof Corner", category = "Roofs", snap = "rotated", material = "floor",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = roofCorner(false) },
    roof_corner_inner = { name = "Inner Roof Corner", category = "Roofs", snap = "rotated", material = "floor",
        buildSeconds = 4, cost = { itemWood = 3, itemScrapMetal = 1 }, parts = roofCorner(true) },
    stairs = { name = "Stairs", category = "Access", snap = "long", material = "floor",
        buildSeconds = 8, cost = { itemWood = 6, itemScrapMetal = 2 }, parts = stairs() },
    ramp = { name = "Ramp", category = "Access", snap = "long", material = "floor",
        buildSeconds = 6, cost = { itemWood = 5, itemScrapMetal = 2 }, parts = {
            prism({ { -64, -32 }, { 64, -32 }, { 64, 32 }, { -64, 32 } },
                { 0, 120, 120, 0 }, { 8, 128, 128, 8 })
        } }
}
Construction.PieceOrder = {
    "foundation", "wall", "foundation_half", "foundation_triangle", "floor", "floor_half", "floor_triangle",
    "wall_half", "wall_doorway", "wall_window", "roof_flat", "roof_slope", "roof_corner_outer",
    "roof_corner_inner", "stairs", "ramp"
}

local rotatedParts = {}

local function rotatePoint(x, y, yaw)
    if yaw == 90 then return -y, x end
    if yaw == 180 then return -x, -y end
    if yaw == 270 then return y, -x end
    return x, y
end

// Cached local convex parts are shared by rendering, collision and placement checks.
function Construction.GetParts(kind, yaw)
    local piece = Construction.Pieces[kind]
    if not piece then return nil end
    yaw = math.floor((tonumber(yaw) or 0) / 90 + 0.5) % 4 * 90
    local key = kind .. ":" .. yaw
    if rotatedParts[key] then return rotatedParts[key] end
    local parts = {}
    for _, source in ipairs(piece.parts) do
        local part = { box = source.box, faces = source.faces, vertices = {} }
        for _, vertex in ipairs(source.vertices) do
            local x, y = rotatePoint(vertex[1], vertex[2], yaw)
            local z = vertex[3]
            part.vertices[#part.vertices + 1] = { x, y, z }
            part.minX, part.maxX = math.min(part.minX or x, x), math.max(part.maxX or x, x)
            part.minY, part.maxY = math.min(part.minY or y, y), math.max(part.maxY or y, y)
            part.minZ, part.maxZ = math.min(part.minZ or z, z), math.max(part.maxZ or z, z)
        end
        parts[#parts + 1] = part
    end
    rotatedParts[key] = parts
    return parts
end

function Construction.CollisionVertices(kind, yaw)
    local parts = Construction.GetParts(kind, yaw)
    if not parts then return nil end
    local convexes = {}
    for _, part in ipairs(parts) do
        local vertices = {}
        for _, vertex in ipairs(part.vertices) do
            vertices[#vertices + 1] = Vector(vertex[1], vertex[2], vertex[3])
        end
        convexes[#convexes + 1] = vertices
    end
    return convexes
end

// Speed multiplier for a hammer level: MinSpeed at minLevel rising linearly to MaxSpeed at maxLevel.
function Construction.BuildSpeed(level, minLevel, maxLevel)
    level, minLevel, maxLevel = tonumber(level), tonumber(minLevel), tonumber(maxLevel)
    if not level or not minLevel or not maxLevel or maxLevel <= minLevel then
        return Construction.MinSpeed
    end
    local fraction = math.Clamp((level - minLevel) / (maxLevel - minLevel), 0, 1)
    return Construction.MinSpeed + (Construction.MaxSpeed - Construction.MinSpeed) * fraction
end

// Speed for a hammer level using the hammer's item definition range.
function Construction:ToolSpeed(level)
    local definition = ZM_Items and ZM_Items:GetDefinition(self.ToolItemId)
    if not definition then return self.MinSpeed end
    return self.BuildSpeed(level, definition.minLevel, definition.maxLevel)
end

function Construction:BuildSeconds(kind, level)
    local piece = self.Pieces[kind]
    if not piece then return nil end
    return piece.buildSeconds / self:ToolSpeed(level)
end

// Material cost of a piece as a new itemId -> count table, or nil for an unknown piece.
function Construction.MaterialCost(kind, mastercraft)
    local piece = Construction.Pieces[kind]
    if not piece then return nil end
    local cost = {}
    for itemId, count in pairs(piece.cost) do
        cost[itemId] = mastercraft and math.max(1, math.ceil(count / 2)) or count
    end
    return cost
end

// Structure health. One walker striking continuously (one strike per StrikeSeconds) breaks a full wall in
// WallBreakSeconds; other pieces scale with their wood cost, so larger pieces last longer. Damage accumulates, so a
// crowd breaks a piece proportionally faster. Wear is 1 - health / max and shows DamageStages visible stages.
Construction.WallBreakSeconds = 300
Construction.StrikeSeconds = 1.5
Construction.ReferenceWood = 3
Construction.DamageStages = 4

function Construction.MaxHealth(kind)
    local piece = Construction.Pieces[kind]
    if not piece then return nil end
    local strikes = Construction.WallBreakSeconds / Construction.StrikeSeconds
    local wood = piece.cost.itemWood or Construction.ReferenceWood
    return math.max(1, math.ceil(strikes * wood / Construction.ReferenceWood))
end

// Damage stage for a wear fraction: 0 is pristine, 1..DamageStages are the visible stages (any wear shows stage 1).
function Construction.DamageStage(wear)
    wear = math.Clamp(tonumber(wear) or 0, 0, 1)
    return math.Clamp(math.ceil(wear * Construction.DamageStages), 0, Construction.DamageStages)
end

// Whether a position lies within margin units of any listed tile's square (centred offsets, tileSize units).
function Construction.WithinTiles(position, tiles, tileSize, margin)
    local reach = tileSize / 2 + margin
    for _, tile in ipairs(tiles) do
        if math.abs(position.x - tile.tileX * tileSize) <= reach and math.abs(position.y - tile.tileY * tileSize) <= reach then
            return true
        end
    end
    return false
end

// Local bounds (minX, minY, minZ, maxX, maxY, maxZ) of the rotated convex parts.
function Construction.PieceBounds(kind, yaw)
    local parts = Construction.GetParts(kind, yaw)
    if not parts then return nil end
    local minX, minY, minZ, maxX, maxY, maxZ
    for _, part in ipairs(parts) do
        minX, minY, minZ = math.min(minX or part.minX, part.minX),
            math.min(minY or part.minY, part.minY), math.min(minZ or part.minZ, part.minZ)
        maxX, maxY, maxZ = math.max(maxX or part.maxX, part.maxX),
            math.max(maxY or part.maxY, part.maxY), math.max(maxZ or part.maxZ, part.maxZ)
    end
    return minX, minY, minZ, maxX, maxY, maxZ
end

// Walls retain their approved edge snap. Asymmetric pieces face the nearest cardinal view direction.
function Construction.SnapPlacement(kind, hitX, hitY, hitZ, viewYaw)
    local piece = Construction.Pieces[kind]
    if not piece then return nil end
    local grid = Construction.GridSize
    local centreX = math.floor(hitX / grid) * grid + grid / 2
    local centreY = math.floor(hitY / grid) * grid + grid / 2
    local z = math.floor(hitZ + 0.5)
    local quarter = math.floor((tonumber(viewYaw) or 0) / 90 + 0.5) % 4
    if piece.snap == "wall" then
        if quarter % 2 == 0 then
            return math.floor(hitX / grid + 0.5) * grid, centreY, z, 90
        end
        return centreX, math.floor(hitY / grid + 0.5) * grid, z, 0
    elseif piece.snap == "half" then
        local yaw = quarter % 2 * 90
        local stepX, stepY = yaw == 0 and grid or grid / 2, yaw == 0 and grid / 2 or grid
        return math.floor(hitX / stepX) * stepX + stepX / 2,
            math.floor(hitY / stepY) * stepY + stepY / 2, z, yaw
    elseif piece.snap == "long" then
        if quarter == 0 then centreX = centreX + grid / 2
        elseif quarter == 1 then centreY = centreY + grid / 2
        elseif quarter == 2 then centreX = centreX - grid / 2
        else centreY = centreY - grid / 2 end
        return centreX, centreY, z, quarter * 90
    elseif piece.snap == "rotated" then
        return centreX, centreY, z, quarter * 90
    end
    return centreX, centreY, z, 0
end

local function facing(viewYaw)
    local yaw = math.floor((tonumber(viewYaw) or 0) / 90 + 0.5) % 4 * 90
    return rotatePoint(1, 0, yaw)
end

local function edgeTowardTrace(trace, origin, minX, minY, maxX, maxY, viewYaw)
    if trace.ZM_StandingSupport then
        local dx, dy = facing(viewYaw)
        if trace.ZM_AimPlane then
            dx = (trace.HitPos.x - origin.x - (minX + maxX) / 2) / (maxX - minX)
            dy = (trace.HitPos.y - origin.y - (minY + maxY) / 2) / (maxY - minY)
        end
        if math.abs(dx) >= math.abs(dy) then return "x", dx >= 0 and 1 or -1 end
        return "y", dy >= 0 and 1 or -1
    end
    local normal = trace.HitNormal
    if normal.z < 0.7 and (math.abs(normal.x) > 0.5 or math.abs(normal.y) > 0.5) then
        if math.abs(normal.x) >= math.abs(normal.y) then
            return "x", normal.x > 0 and 1 or -1
        end
        return "y", normal.y > 0 and 1 or -1
    end
    local west, east = math.abs(trace.HitPos.x - origin.x - minX), math.abs(trace.HitPos.x - origin.x - maxX)
    local south, north = math.abs(trace.HitPos.y - origin.y - minY), math.abs(trace.HitPos.y - origin.y - maxY)
    local dx, dy = math.min(west, east), math.min(south, north)
    local forwardX, forwardY = facing(viewYaw)
    if dx < dy or (dx == dy and forwardX ~= 0) then
        return "x", west == east and (forwardX ~= 0 and forwardX or 1) or (west < east and -1 or 1)
    end
    return "y", south == north and (forwardY ~= 0 and forwardY or 1) or (south < north and -1 or 1)
end

local function edgeProfile(kind, yaw, axis, side)
    local minX, minY, _, maxX, maxY = Construction.PieceBounds(kind, yaw)
    local edge = axis == "x" and (side > 0 and maxX or minX) or (side > 0 and maxY or minY)
    local tangentMin, tangentMax = axis == "x" and minY or minX, axis == "x" and maxY or maxX
    local low, high
    for _, part in ipairs(Construction.GetParts(kind, yaw)) do
        for _, vertex in ipairs(part.vertices) do
            local normal = axis == "x" and vertex[1] or vertex[2]
            local tangent = axis == "x" and vertex[2] or vertex[1]
            if normal == edge then
                if tangent == tangentMin then low = math.min(low or vertex[3], vertex[3]) end
                if tangent == tangentMax then high = math.min(high or vertex[3], vertex[3]) end
            end
        end
    end
    return low, high, tangentMin, tangentMax
end

local function edgeHeight(low, high, tangentMin, tangentMax, origin, position)
    return low + (high - low) * (position - origin - tangentMin) / (tangentMax - tangentMin)
end

local function tangentOrigin(sourceMin, sourceMax, hit, targetMin, targetMax)
    local targetSize = targetMax - targetMin
    if targetSize < sourceMax - sourceMin then
        local last = math.ceil((sourceMax - sourceMin) / targetSize) - 1
        local index = math.Clamp(math.floor((hit - sourceMin) / targetSize), 0, last)
        return sourceMin + index * targetSize - targetMin
    end
    return (sourceMin + sourceMax - targetMin - targetMax) / 2
end

local function triangleDiagonal(trace, origin, yaw)
    local inverseYaw = (360 - yaw % 360) % 360
    if trace.HitNormal.z < 0.7 then
        local x, y = rotatePoint(trace.HitNormal.x, trace.HitNormal.y, inverseYaw)
        return x > 0.5 and y > 0.5
    end
    local x, y = rotatePoint(trace.HitPos.x - origin.x, trace.HitPos.y - origin.y, inverseYaw)
    local diagonal = math.abs(x + y) / math.sqrt(2)
    local half = Construction.GridSize / 2
    return diagonal < math.abs(x + half) and diagonal < math.abs(y + half)
end

// Pieces with a flat top that stairs and ramps can start beside.
function Construction.IsLevelSupport(kind)
    local piece = Construction.Pieces[kind]
    return piece ~= nil and (piece.category == "Foundations" or piece.category == "Floors" or kind == "roof_flat")
end

// Stairs and ramps start just outside a level piece's straight edge, at its top, and rise away from it.
local function accessFromEdge(kind, trace, viewYaw, supportKind, supportYaw, origin)
    local minX, minY, _, maxX, maxY, maxZ = Construction.PieceBounds(supportKind, supportYaw)
    local axis, side
    if trace.ZM_StandingSupport then
        local forwardX, forwardY = facing(viewYaw)
        axis, side = forwardX ~= 0 and "x" or "y", forwardX ~= 0 and forwardX or forwardY
    else
        axis, side = edgeTowardTrace(trace, origin, minX, minY, maxX, maxY, viewYaw)
    end
    local yaw = axis == "x" and (side > 0 and 0 or 180) or (side > 0 and 90 or 270)
    local low, high = edgeProfile(supportKind, supportYaw, axis, side)
    if not low or not high or low ~= high then
        return origin.x, origin.y, origin.z, yaw, false, "Stairs need a straight edge; aim at a side of the piece."
    end
    local targetMinX, targetMinY, _, targetMaxX, targetMaxY = Construction.PieceBounds(kind, yaw)
    local boundary = axis == "x" and origin.x + (side > 0 and maxX or minX) or origin.y + (side > 0 and maxY or minY)
    local sourceMin = axis == "x" and origin.y + minY or origin.x + minX
    local sourceMax = axis == "x" and origin.y + maxY or origin.x + maxX
    local hitTangent = axis == "x" and trace.HitPos.y or trace.HitPos.x
    local tangent = tangentOrigin(sourceMin, sourceMax, hitTangent,
        axis == "x" and targetMinY or targetMinX, axis == "x" and targetMaxY or targetMaxX)
    local x, y
    if axis == "x" then
        x, y = boundary - (side > 0 and targetMinX or targetMaxX), tangent
    else
        x, y = tangent, boundary - (side > 0 and targetMinY or targetMaxY)
    end
    return x, y, math.floor(origin.z + maxZ + 0.5), yaw, true
end

// Resolve finished-piece attachments in both realms; the server still traces and checks claim access itself.
function Construction.ResolvePlacement(kind, trace, viewYaw)
    if not trace.Hit then return nil, nil, nil, nil, false, "Aim at level ground within reach." end
    local x, y, z, yaw = Construction.SnapPlacement(kind, trace.HitPos.x, trace.HitPos.y, trace.HitPos.z, viewYaw)
    if not x then return nil, nil, nil, nil, false, "Unknown construction piece." end
    if trace.HitWorld then
        if trace.HitNormal.z < 0.7 then return x, y, z, yaw, false, "Aim at level ground within reach." end
        return x, y, z, yaw, true
    end

    local support = trace.Entity
    if not Construction.IsReadyPiece(support) or not support:GetComplete() then
        local reason = trace.HitNormal.z < 0.7 and "Aim at level ground within reach."
            or "Pieces must stand on the ground or a finished piece."
        return x, y, z, yaw, false, reason
    end
    local supportKind, supportYaw = support:GetPieceKind(), support:GetPieceYaw()
    local supportPiece, piece = Construction.Pieces[supportKind], Construction.Pieces[kind]
    if not supportPiece then return x, y, z, yaw, false, "The supporting piece has an unknown shape." end
    local origin = support:GetPos()
    local minX, minY, _, maxX, maxY, maxZ = Construction.PieceBounds(supportKind, supportYaw)

    if piece.slotGroup == "wall" and supportPiece.slotGroup == "wall" then
        return origin.x, origin.y, origin.z + maxZ, supportYaw % 180, true
    end
    if kind == "floor_triangle" and supportKind == kind and triangleDiagonal(trace, origin, supportYaw) then
        return origin.x, origin.y, origin.z, (supportYaw + 180) % 360, true
    end

    if piece.category == "Access" and Construction.IsLevelSupport(supportKind)
        and (trace.ZM_StandingSupport or trace.HitNormal.z < 0.7) then
        return accessFromEdge(kind, trace, viewYaw, supportKind, supportYaw, origin)
    end

    if piece.category ~= "Floors" and piece.category ~= "Roofs" then
        if trace.HitNormal.z < 0.7 then return x, y, z, yaw, false, "Aim at level ground within reach." end
        return x, y, z, yaw, true
    end

    local axis, side, boundary, top
    if supportPiece.slotGroup == "wall" then
        axis = supportYaw % 180 == 0 and "y" or "x"
        local component = axis == "x" and trace.HitNormal.x or trace.HitNormal.y
        local forwardX, forwardY = facing(viewYaw)
        local forward = axis == "x" and forwardX or forwardY
        if math.abs(component) > 0.5 then
            side = component > 0 and 1 or -1
        else
            side = forward > 0 and -1 or 1
        end
        boundary = axis == "x" and origin.x or origin.y
        top = origin.z + maxZ
    elseif supportPiece.category == "Access" then
        local directionX, directionY = facing(supportYaw)
        axis = directionX ~= 0 and "x" or "y"
        side = directionX ~= 0 and directionX or directionY
        boundary = axis == "x" and origin.x + (side > 0 and maxX or minX)
            or origin.y + (side > 0 and maxY or minY)
        top = origin.z + maxZ
    elseif supportPiece.category == "Floors" or supportPiece.category == "Roofs" then
        axis, side = edgeTowardTrace(trace, origin, minX, minY, maxX, maxY, viewYaw)
        boundary = axis == "x" and origin.x + (side > 0 and maxX or minX)
            or origin.y + (side > 0 and maxY or minY)
    else
        if trace.HitNormal.z < 0.7 then return x, y, z, yaw, false, "Aim at level ground within reach." end
        return x, y, z, yaw, true
    end

    local targetMinX, targetMinY, _, targetMaxX, targetMaxY = Construction.PieceBounds(kind, yaw)
    local sourceMin = axis == "x" and origin.y + minY or origin.x + minX
    local sourceMax = axis == "x" and origin.y + maxY or origin.x + maxX
    local targetMin = axis == "x" and targetMinY or targetMinX
    local targetMax = axis == "x" and targetMaxY or targetMaxX
    local hitTangent = axis == "x" and trace.HitPos.y or trace.HitPos.x
    local tangent = tangentOrigin(sourceMin, sourceMax, hitTangent, targetMin, targetMax)
    if axis == "x" then
        x, y = boundary - (side > 0 and targetMinX or targetMaxX), tangent
    else
        x, y = tangent, boundary - (side > 0 and targetMinY or targetMaxY)
    end

    local targetLow, targetHigh, targetTMin, targetTMax = edgeProfile(kind, yaw, axis, -side)
    if kind == "floor_triangle" and (not targetLow or not targetHigh) then
        for _, turn in ipairs({ 90, 270, 180 }) do
            local candidateYaw = (yaw + turn) % 360
            local low, high, tangentMin, tangentMax = edgeProfile(kind, candidateYaw, axis, -side)
            if low and high then
                yaw, targetLow, targetHigh, targetTMin, targetTMax = candidateYaw, low, high, tangentMin, tangentMax
                break
            end
        end
    end
    if not targetLow or not targetHigh then
        return x, y, z, yaw, false, "Aim at matching straight edges or turn to rotate the piece."
    end
    local start = math.max(sourceMin, tangent + targetTMin)
    local finish = math.min(sourceMax, tangent + targetTMax)
    local targetStart = edgeHeight(targetLow, targetHigh, targetTMin, targetTMax, tangent, start)
    local targetFinish = edgeHeight(targetLow, targetHigh, targetTMin, targetTMax, tangent, finish)
    if top then
        z = math.floor(top - math.min(targetStart, targetFinish) + 0.5)
        return x, y, z, yaw, true
    end

    local sourceLow, sourceHigh, sourceTMin, sourceTMax = edgeProfile(supportKind, supportYaw, axis, side)
    if not sourceLow or not sourceHigh then
        return x, y, z, yaw, false, "Aim at matching straight edges or turn to rotate the piece."
    end
    local sourceTangent = axis == "x" and origin.y or origin.x
    local startHeight = origin.z + edgeHeight(sourceLow, sourceHigh, sourceTMin, sourceTMax, sourceTangent, start) - targetStart
    local finishHeight = origin.z + edgeHeight(sourceLow, sourceHigh, sourceTMin, sourceTMax, sourceTangent, finish) - targetFinish
    z = math.floor(startHeight + 0.5)
    if math.abs(startHeight - finishHeight) > 0.01 then
        return x, y, z, yaw, false, "These edges do not align; turn to rotate the piece."
    end
    return x, y, z, yaw, true
end

// The four XY corners of a placed piece's footprint.
function Construction.FootprintCorners(kind, x, y, yaw)
    local minX, minY, _, maxX, maxY = Construction.PieceBounds(kind, yaw)
    if not minX then return nil end
    return {
        { x = x + minX, y = y + minY }, { x = x + maxX, y = y + minY },
        { x = x + maxX, y = y + maxY }, { x = x + minX, y = y + maxY }
    }
end

// Identity of a placement used to refuse duplicates; heights are bucketed so stacked pieces stay distinct.
function Construction.SlotKey(kind, x, y, z, yaw)
    local piece = Construction.Pieces[kind]
    return string.format("%s:%d:%d:%d:%d", piece and piece.slotGroup or kind, x, y, math.floor(z / 8 + 0.5), yaw)
end

// Next piece kind in PieceOrder after the given one, wrapping around.
function Construction.NextPieceKind(kind)
    local order = Construction.PieceOrder
    for index, name in ipairs(order) do
        if name == kind then return order[index % #order + 1] end
    end
    return order[1]
end

// The hammer's selected piece kind; an unset selection means the first piece.
function Construction.SelectedPiece(weapon)
    local kind = weapon.GetBuildPiece and weapon:GetBuildPiece() or nil
    if Construction.Pieces[kind] then return kind end
    return Construction.PieceOrder[1]
end

local function partPlanes(part)
    if part.tracePlanes then return part.tracePlanes end
    local cx, cy, cz = 0, 0, 0
    for _, vertex in ipairs(part.vertices) do
        cx, cy, cz = cx + vertex[1], cy + vertex[2], cz + vertex[3]
    end
    cx, cy, cz = cx / #part.vertices, cy / #part.vertices, cz / #part.vertices
    local planes = {}
    for _, face in ipairs(part.faces) do
        local a, b, c = part.vertices[face[1]], part.vertices[face[2]], part.vertices[face[3]]
        local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local length = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / length, ny / length, nz / length
        if nx * (a[1] - cx) + ny * (a[2] - cy) + nz * (a[3] - cz) < 0 then
            nx, ny, nz = -nx, -ny, -nz
        end
        planes[#planes + 1] = { nx, ny, nz, nx * a[1] + ny * a[2] + nz * a[3] }
    end
    part.tracePlanes = planes
    return planes
end

// Pick the authored convex shape, not the small model used to initialize its physics.
function Construction.RayPiece(kind, yaw, origin, start, delta)
    local parts = Construction.GetParts(kind, yaw)
    if not parts then return nil end
    local x, y, z = start.x - origin.x, start.y - origin.y, start.z - origin.z
    local nearest, normal
    for _, part in ipairs(parts) do
        local enter, leave, plane, exitPlane = 0, 1, nil, nil
        for _, face in ipairs(partPlanes(part)) do
            local distance = face[1] * x + face[2] * y + face[3] * z - face[4]
            local speed = face[1] * delta.x + face[2] * delta.y + face[3] * delta.z
            if speed == 0 then
                if distance > 0 then leave = -1 break end
            else
                local fraction = -distance / speed
                if speed < 0 and fraction > enter then enter, plane = fraction, face
                elseif speed > 0 and fraction <= leave then leave, exitPlane = fraction, face end
            end
            if enter > leave then break end
        end
        local hit, face = enter, plane
        if not face then hit, face = leave, exitPlane end
        if face and enter <= leave and (not nearest or hit < nearest) then
            nearest, normal = hit, Vector(face[1], face[2], face[3])
        end
    end
    return nearest, normal
end

// Clients can enumerate a piece before its scripted table and network vars are set up.
function Construction.IsReadyPiece(entity)
    return IsValid(entity) and entity:GetClass() == Construction.PieceClass
        and entity.GetPieceKind ~= nil and entity.GetPieceYaw ~= nil and entity.GetComplete ~= nil
        and Construction.Pieces[entity:GetPieceKind()] ~= nil
end

function Construction:TraceRay(start, direction, reach, target)
    local delta = direction * reach
    local trace = util.TraceLine({
        start = start,
        endpos = start + delta,
        filter = { target, self.PieceClass },
        mask = MASK_SOLID
    })
    for _, entity in ipairs(ents.FindByClass(self.PieceClass)) do
        if self.IsReadyPiece(entity) and not entity.ZM_ConstructionRemoving then
            local fraction, normal = self.RayPiece(entity:GetPieceKind(), entity:GetPieceYaw(), entity:GetPos(), start, delta)
            if fraction and (not trace.Hit or fraction < trace.Fraction) then
                trace = {
                    Hit = true, HitWorld = false, Entity = entity, Fraction = fraction,
                    HitPos = start + delta * fraction, HitNormal = normal
                }
            end
        end
    end
    return trace
end

// Placement and deletion share picking in both realms, including non-solid blueprints.
function Construction:AimTrace(target, reach)
    local start, direction = target:GetLevelAim()
    return self:TraceRay(start, direction, reach or self.PlaceReach, target)
end

// Project empty-space aiming onto the current storey instead of the world ground below it.
function Construction:StandingTrace(target, kind, trace, start, direction, reach)
    local piece = self.Pieces[kind]
    local isAccess = piece and piece.category == "Access"
    local isFloorOrRoof = piece and (piece.category == "Floors" or piece.category == "Roofs")
    if not isAccess and not isFloorOrRoof then return trace end
    local support = target:GetGroundEntity()
    local feet = target:GetPos()
    if trace.Hit and not trace.HitSky and trace.HitPos.z >= feet.z - 32 then return trace end
    if isAccess and IsValid(support) and support:IsWorld() then
        return {
            Hit = true,
            HitWorld = true,
            HitPos = Vector(feet.x, feet.y, feet.z),
            HitNormal = Vector(0, 0, 1),
            ZM_StandingSupport = true
        }
    end
    if self.IsReadyPiece(support) and support:GetComplete()
        and (isFloorOrRoof or self.IsLevelSupport(support:GetPieceKind())) then
        local forwardX, forwardY = facing(target:EyeAngles().y)
        local position = Vector(feet.x + forwardX * self.GridSize, feet.y + forwardY * self.GridSize, feet.z)
        local projected = false
        if isFloorOrRoof and direction.z ~= 0 then
            local _, _, _, _, _, top = self.PieceBounds(support:GetPieceKind(), support:GetPieceYaw())
            local distance = (support:GetPos().z + top - start.z) / direction.z
            if distance > reach then return trace end
            if distance > 0 then
                position, projected = start + direction * distance, true
            end
        end
        return {
            Hit = true,
            HitWorld = false,
            Entity = support,
            HitPos = position,
            HitNormal = Vector(0, 0, 1),
            ZM_StandingSupport = true,
            ZM_AimPlane = projected
        }
    end
    return trace
end

function Construction:PlacementTrace(target, kind)
    local start, direction = target:GetLevelAim()
    return self:StandingTrace(target, kind, self:AimTrace(target), start, direction, self.PlaceReach)
end

// Outer boundary of the union of tiles as segments { x1, y1, x2, y2 }; edges shared by two tiles are omitted.
function Construction.BoundaryEdges(tiles, tileSize)
    local owned = {}
    for _, tile in ipairs(tiles) do owned[tile.tileX .. "," .. tile.tileY] = true end
    local half = tileSize / 2
    local edges = {}
    for _, tile in ipairs(tiles) do
        local x, y = tile.tileX * tileSize, tile.tileY * tileSize
        local sides = {
            { 1, 0, x + half, y - half, x + half, y + half },
            { -1, 0, x - half, y - half, x - half, y + half },
            { 0, 1, x - half, y + half, x + half, y + half },
            { 0, -1, x - half, y - half, x + half, y - half }
        }
        for _, side in ipairs(sides) do
            if not owned[(tile.tileX + side[1]) .. "," .. (tile.tileY + side[2])] then
                edges[#edges + 1] = { side[3], side[4], side[5], side[6] }
            end
        end
    end
    return edges
end
