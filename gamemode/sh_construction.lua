// Shared construction rules. The Hammer is the building tool: while it is held, Reload toggles build mode.
// Build speed scales linearly with the hammer's item level, and a mastercrafted (including ultra) hammer halves
// each material cost, rounded up to at least one.
ZM_Construction = ZM_Construction or {}
local Construction = ZM_Construction

Construction.ToolClass = "weapon_zn_hammer"
Construction.ToolItemId = "weaponMeleeHammer"
// Protection reaches this far beyond the edges of an accessible active claim tile.
Construction.ProtectionMargin = 640
Construction.MinSpeed = 1
Construction.MaxSpeed = 2
// Prototype pieces. buildSeconds is the contribution time at speed 1; size is length x thickness x height at yaw 0.
// Times and sizes are provisional, pending live review.
Construction.Pieces = {
    foundation = { name = "Foundation", buildSeconds = 6, size = { 64, 64, 16 }, cost = { itemWood = 4, itemScrapMetal = 2 } },
    wall = { name = "Wall", buildSeconds = 4, size = { 64, 8, 128 }, cost = { itemWood = 3, itemScrapMetal = 1 } }
}
Construction.PieceOrder = { "foundation", "wall" }
Construction.GridSize = 64
Construction.PlaceReach = 256
// Pieces are axis-aligned boxes (SOLID_BBOX), so a wall's yaw is folded into its bounds rather than its angles.
Construction.PieceModel = "models/hunter/blocks/cube025x025x025.mdl"
Construction.MaxBlueprintsPerPlayer = 12

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

// Local bounds (minX, minY, minZ, maxX, maxY, maxZ) of a piece whose origin is its bottom centre; yaw 90 swaps
// length and thickness.
function Construction.PieceBounds(kind, yaw)
    local piece = Construction.Pieces[kind]
    if not piece then return nil end
    local sizeX, sizeY, sizeZ = piece.size[1], piece.size[2], piece.size[3]
    if yaw == 90 then sizeX, sizeY = sizeY, sizeX end
    return -sizeX / 2, -sizeY / 2, 0, sizeX / 2, sizeY / 2, sizeZ
end

// Snaps an aimed surface point to the build grid and returns x, y, z, yaw. Foundations fill grid squares. Walls
// stand on square edges facing the viewer: looking along X builds a wall spanning Y (yaw 90), and vice versa.
function Construction.SnapPlacement(kind, hitX, hitY, hitZ, viewYaw)
    if not Construction.Pieces[kind] then return nil end
    local grid = Construction.GridSize
    local centreX = math.floor(hitX / grid) * grid + grid / 2
    local centreY = math.floor(hitY / grid) * grid + grid / 2
    local z = math.floor(hitZ + 0.5)
    if kind ~= "wall" then return centreX, centreY, z, 0 end
    local quarter = math.floor((tonumber(viewYaw) or 0) / 90 + 0.5) % 2
    if quarter == 0 then
        return math.floor(hitX / grid + 0.5) * grid, centreY, z, 90
    end
    return centreX, math.floor(hitY / grid + 0.5) * grid, z, 0
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
    return string.format("%s:%d:%d:%d:%d", kind, x, y, math.floor(z / 8 + 0.5), yaw)
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

// The placement aim trace, shared so the client ghost matches what the server places.
function Construction:AimTrace(target)
    local start = target:EyePos()
    return util.TraceLine({
        start = start,
        endpos = start + target:GetAimVector() * self.PlaceReach,
        filter = target,
        mask = MASK_SOLID
    })
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
