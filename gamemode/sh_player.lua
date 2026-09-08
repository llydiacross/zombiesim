// Shared Player extensions. Server-owned values are mirrored through NW vars for client UI.
local ply = FindMetaTable("Player")

// Game-wide progression constants. Mutable state belongs on each Player instance.
ply.ExperiencePerLevel = 1000 // equals a level
ply.SkillPointsPerLevel = 1 // how many skill points the player gets per level up

// Returns the player's saved logical world x/y coordinates, or nil if the stored values are invalid.
function ply:GetWorldCellCoordinates()
    local x = tonumber(self.CellX)
    local y = tonumber(self.CellY)
    if not x or not y then
        return nil
    end

    return math.floor(x), math.floor(y)
end

// Returns the runtime-world cell for the player, converting from logical to raw grid coordinates.
function ply:GetWorldCell()
    local worldX, worldY = self:GetWorldCellCoordinates()
    if not worldX then
        return nil, "Player has no valid world-cell coordinates"
    end

    local gridX, gridY = ZM_World:GetGridCoordinates(worldX, worldY)
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    if not cell then
        return nil, ZM_World:GetLoadError() or "Player world cell is outside the loaded world"
    end

    return cell
end

// Returns the district record for the player's current world cell.
function ply:GetCurrentDistrict()
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    return ZM_World:GetDistrict(cell)
end

// Returns the display name of the district containing the player's current world cell.
function ply:GetCurrentDistrictName()
    local district, loadError = self:GetCurrentDistrict()
    return district and district.name or nil, loadError
end

// Returns the ambient radiation intensity for the player's current city cell.
function ply:GetRadiationIntensity()
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    return ZM_World:GetRadiationIntensity(cell)
end

// Returns the generated enemy-scaling danger intensity for the player's current city cell.
function ply:GetDangerIntensity()
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    return ZM_World:GetDangerIntensity(cell)
end

// Returns radiation damage per second for the player's current city cell.
function ply:GetRadiationDamagePerSecond()
    local intensity, loadError = self:GetRadiationIntensity()
    if intensity == nil then
        return nil, loadError
    end

    return intensity * ZM_World:GetRadiationDamagePerSecondAtPeak()
end

// Returns the compact world-data id for the player's current logical cell.
function ply:GetWorldCellId()
    local cell = self:GetWorldCell()
    return cell and cell.id or nil
end

// Returns the city safe-room entrance at the player's saved CellX/CellY, if one exists.
function ply:GetAccessibleSafeZone()
    return ZM_World:GetPlayerSafeZone(self)
end

// Returns the standalone safe room the player is currently in, if any.
function ply:GetCurrentSafeZone()
    return ZM_World:GetPlayerCurrentSafeZone(self)
end

// Returns the standalone safe-room map the player is currently in, if any.
function ply:GetCurrentSafeZoneMap()
    return ZM_World:GetPlayerCurrentSafeZoneMap(self)
end

// Returns one graph-connected neighbour and its exit. Directions are "N", "E", "S", or "W".
// This reports a connected neighbour even if a road blockade prevents travel.
function ply:GetNeighbouringCell(direction)
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    local exit = ZM_World:GetExit(cell, direction)
    if not exit then
        return nil
    end

    return ZM_World:GetCellById(exit.cell), exit
end

// Returns connected neighbours keyed by direction, for example neighbours.N or neighbours["N"].
// Missing keys mean that no graph connection exists in that direction.
function ply:GetNeighbouringCells()
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    local neighbours = {}
    for _, exit in ipairs(cell.exits or {}) do
        local neighbour = ZM_World:GetCellById(exit.cell)
        if neighbour then
            neighbours[exit.direction] = neighbour
        end
    end

    return neighbours
end

// Returns travelable neighbours keyed by direction with { cell, exit, mode, blocked } details.
// Mode is "road", "highway", or "any"; blocked roads require allowBlocked to be true.
function ply:GetReachableNeighbouringCells(mode, allowBlocked)
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    local neighbours = {}
    for _, exit in ipairs(cell.exits or {}) do
        local travelMode = ZM_World:GetTravelMode(exit, mode, allowBlocked)
        local neighbour = ZM_World:GetCellById(exit.cell)
        if neighbour and travelMode then
            neighbours[exit.direction] = {
                cell = neighbour,
                exit = exit,
                mode = travelMode.type,
                blocked = travelMode.blocked
            }
        end
    end

    return neighbours
end

// Validates one move and returns targetCell, exit, mode. It accepts the same direction/mode values
// as ZM_World:CanTravel and is suitable for a transition trigger's final authority check.
function ply:CanTravelToNeighbour(direction, mode, allowBlocked)
    local cell, loadError = self:GetWorldCell()
    if not cell then
        return nil, loadError
    end

    return ZM_World:CanTravel(cell, direction, mode, allowBlocked)
end

// American spellings are aliases so game code can use either "neighbor" or "neighbour" consistently.
ply.GetNeighboringCell = ply.GetNeighbouringCell
ply.GetNeighboringCells = ply.GetNeighbouringCells
ply.GetReachableNeighboringCells = ply.GetReachableNeighbouringCells
ply.CanTravelToNeighbor = ply.CanTravelToNeighbour

// Strength and agility increase the player's maximum stamina pool.
function ply:GetMaxStamina()
    local agility = tonumber(self.Attributes and self.Attributes.Agility) or 0
    local strength = tonumber(self.Attributes and self.Attributes.Strength) or 0

    return 100 + agility * 5 + strength * 3
end

// Returns unclamped level progress as a percentage for HUD code.
function ply:GetPercentageToNextLevel()
    return (self.XP / self.ExperiencePerLevel) * 100
end

// A level-up is available once accumulated XP reaches the current threshold.
function ply:CanLevelUp()
    return self.XP >= self.ExperiencePerLevel
end

