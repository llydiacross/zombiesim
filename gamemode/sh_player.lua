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

// Radiation cannot reduce health below the tier unlocked by Strength.
function ply:GetRadiationHealthFloor()
    local strength = self:GetStat("Strength")
    if strength >= 10 then
        return 80
    end
    if strength >= 5 then
        return 72
    end
    return 64
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
    local agility = self:GetStat("Agility")
    local strength = self:GetStat("Strength")

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

// Level shots from the centre of mass pass over crawlers, so a level command (top-down/orbit) dips onto the
// nearest crawler in its line of fire. The target comes from networked entity state on both realms, never from
// the client, and shoulder aim (a cursor pitch) is left unchanged.
ZM_LowTargetAim = ZM_LowTargetAim or {}
ZM_LowTargetAim.Classes = { "zn_walker_zombie" }
ZM_LowTargetAim.LegsMaskKey = "ZM_GoreSevered"
ZM_LowTargetAim.LegsBit = 4
ZM_LowTargetAim.AimHeight = 16
ZM_LowTargetAim.LateralRadius = 24
ZM_LowTargetAim.Range = 2048
ZM_LowTargetAim.LevelTolerance = 0.001

function ZM_LowTargetAim.IsLowTarget(entity)
    return IsValid(entity) and entity:Health() > 0
        and bit.band(entity:GetNWInt(ZM_LowTargetAim.LegsMaskKey, 0), ZM_LowTargetAim.LegsBit) ~= 0
end

// Returns the aim point of the nearest crawler the level ray passes over, unless a wall or another entity
// intercepts the level ray first.
function ZM_LowTargetAim.Find(origin, yaw, filter, candidates)
    local forward = Angle(0, yaw, 0):Forward()
    local bestDepth, bestPoint
    if not candidates then
        candidates = {}
        for _, class in ipairs(ZM_LowTargetAim.Classes) do
            for _, entity in ipairs(ents.FindByClass(class)) do
                candidates[#candidates + 1] = entity
            end
        end
    end
    for _, entity in ipairs(candidates) do
        if entity ~= filter and ZM_LowTargetAim.IsLowTarget(entity) then
            local point = entity:GetPos() + Vector(0, 0, ZM_LowTargetAim.AimHeight)
            local offset = point - origin
            offset.z = 0
            local depth = offset:Dot(forward)
            local lateral = offset - forward * depth
            if depth > 0 and depth <= ZM_LowTargetAim.Range and point.z < origin.z
                and lateral:LengthSqr() <= ZM_LowTargetAim.LateralRadius * ZM_LowTargetAim.LateralRadius
                and (not bestDepth or depth < bestDepth) then
                bestDepth, bestPoint = depth, point
            end
        end
    end
    if not bestPoint then
        return nil
    end
    local level = util.TraceLine({ start = origin, endpos = origin + forward * bestDepth, filter = filter, mask = MASK_SHOT })
    if level.Hit then
        return nil
    end
    return bestPoint
end

// Outdoor commands carry weapon aim, not camera pitch: top-down/orbit send level aim, shoulder sends cursor aim.
function ply:GetLevelAim()
    local angles = self:EyeAngles()
    local origin = self:WorldSpaceCenter()
    local safeZoneId = self:GetNWString("CurrentSafeZoneId", "")
    local inSafeZone = safeZoneId ~= "" and safeZoneId ~= "NULL"
    if not inSafeZone and math.abs(math.NormalizeAngle(angles.p)) < ZM_LowTargetAim.LevelTolerance then
        local point = ZM_LowTargetAim.Find(origin, angles.y, self)
        if point then
            angles = Angle((point - origin):Angle().p, angles.y, 0)
        end
    end
    local weapon = self.GetActiveWeapon and self:GetActiveWeapon()
    if IsValid(weapon) and weapon.GetAimRecoil then
        local recoil = weapon:GetAimRecoil()
        angles = Angle(math.Clamp(math.NormalizeAngle(angles.p) + recoil.p, -89, 89), angles.y + recoil.y, 0)
    end
    if inSafeZone then
        angles = Angle(0, angles.y, 0)
    end
    return origin, angles:Forward()
end

// Weapons and the crosshair share the same recoil-adjusted aim trace.
function ply:GetLevelAimTrace(range)
    local origin, direction = self:GetLevelAim()
    return util.TraceLine({
        start = origin,
        endpos = origin + direction * (range or 4096),
        filter = self,
        mask = MASK_SHOT
    })
end
