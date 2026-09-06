// Shared Player extensions. Server-owned values are mirrored through NW vars for client UI.
local ply = FindMetaTable("Player")

// Default persistent attributes for a newly created player.
ply.Attributes = {
    Strength = 0,
    Agility = 0,
    Intelligence = 0,
    Endurance = 0,
    MachineGuns = 0,
    Shotguns = 0,
    Snipers = 0,
    WeaponCrafting = 0,
    ArmorCrafting = 0,
    Medicine = 0,
    Farming = 0,
    WeaponRepairing = 0,
    ArmorRepairing = 0,
    Mechanics = 0
}

// Default persistent player state. CellX/CellY are zero-based logical city coordinates.
ply.XP = 0
ply.Level = 1
ply.MaxLevel = 300
ply.Difficulty = 1 -- 1 = Easy, 2 = Normal, 3 = Hard, 4 = Insane
ply.CellX = 0
ply.CellY = 0
ply.SkillPoints = 0
ply.SavedHealth = 100
ply.Stamina = 100

// Game-specific runtime values that are not individual database columns.
ply.ExperiencePerLevel = 1000 // equals a level
ply.PreviouslyConnected = false
ply.SkillPointsPerLevel = 1 // how many skill points the player gets per level up

// Returns the player's saved logical x/y coordinates, or nil if the stored values are invalid.
function ply:GetWorldCellCoordinates()
    local x = tonumber(self.CellX)
    local y = tonumber(self.CellY)
    if not x or not y then
        return nil
    end

    return math.floor(x), math.floor(y)
end

// Returns the runtime-world cell for the player, or nil plus a reason when data is unavailable.
function ply:GetWorldCell()
    local x, y = self:GetWorldCellCoordinates()
    if not x then
        return nil, "Player has no valid world-cell coordinates"
    end

    local cell = ZM_World:GetCell(x, y)
    if not cell then
        return nil, ZM_World:GetLoadError() or "Player world cell is outside the loaded world"
    end

    return cell
end

// Returns the compact world-data id for the player's current logical cell.
function ply:GetWorldCellId()
    local cell = self:GetWorldCell()
    return cell and cell.id or nil
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

