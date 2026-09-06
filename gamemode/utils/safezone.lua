// Shared safe-zone queries backed by ZM_World's loaded runtime index.
// Safe-zone ids are stable strings such as "safezone-3-17".
ZM_SafeZones = ZM_SafeZones or {}

local SafeZones = ZM_SafeZones

// Retrieves the complete runtime record for a safe-zone id, or nil when it is unknown.
function SafeZones:Get(id)
	return ZM_World:GetSafeZoneById(id)
end

// Returns the safe-room entrance at the generated world origin.
function SafeZones:GetOrigin()
	return ZM_World:GetOriginSafeZone()
end

// Returns the safe-zone record attached to a city cell, or nil when the cell is not an entrance.
// Accepts the same cell id, cell table, { x, y }, or x/y inputs as ZM_World:GetSafeZone.
function SafeZones:GetForCell(reference, y)
	return ZM_World:GetSafeZone(reference, y)
end

// Returns whether a city cell is a safe-room entrance.
function SafeZones:IsSafeZoneCell(reference, y)
	return self:GetForCell(reference, y) ~= nil
end

// Returns a safe-zone's display name, or nil when the id is unknown.
function SafeZones:GetName(id)
	local safeZone = self:Get(id)
	return safeZone and safeZone.name or nil
end

// Returns the logical city entrance cell for a safe-zone id, or nil when it is unknown.
function SafeZones:GetEntranceCell(id)
	local safeZone = self:Get(id)
	return safeZone and ZM_World:GetCellById(safeZone.cell) or nil
end

// Returns the zero-based city entrance coordinates for a safe-zone id, or nil when it is unknown.
function SafeZones:GetEntranceCoordinates(id)
	local entrance = self:GetEntranceCell(id)
	if not entrance then
		return nil
	end

	return entrance.x, entrance.y
end

// Returns the district record containing the safe-zone entrance, or nil for the world-origin zone.
function SafeZones:GetDistrict(id)
	local safeZone = self:Get(id)
	if not safeZone or type(safeZone.district) ~= "number" then
		return nil
	end

	return ZM_World.Data.districts[safeZone.district + 1]
end

// Returns the reusable safe-room transition map for a safe-zone id, or nil when it is unknown.
function SafeZones:GetMap(id)
	local safeZone = self:Get(id)
	if not safeZone or type(safeZone.map) ~= "string" or safeZone.map == "" then
		return nil
	end

	return ZM_World.Data.world.mapDirectory .. "/" .. safeZone.map
end

// Returns the reusable safe-room transition map at the generated world origin.
function SafeZones:GetOriginMap()
	return ZM_World:GetOriginSafeZoneMap()
end

// Returns the semantic biome/profile used by a safe-zone's destination map.
function SafeZones:GetBiome(id)
	local safeZone = self:Get(id)
	return safeZone and safeZone.biome or nil
end

// Returns the landmark-specific destination variant, or nil for a generic safe room.
function SafeZones:GetLandmarkVariant(id)
	local safeZone = self:Get(id)
	if not safeZone or type(safeZone.landmarkVariant) ~= "string" or safeZone.landmarkVariant == "" then
		return nil
	end

	return safeZone.landmarkVariant
end
