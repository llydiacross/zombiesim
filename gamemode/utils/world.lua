// Shared, read-only view of data_static/zombiesim_world.json.
//
// Logical cells use zero-based x/y coordinates. Directions are uppercase
// cardinal strings: "N", "E", "S", and "W". A recipe map may represent
// several logical cells, so use a cell's coordinates or id for identity.
ZM_World = ZM_World or {}

local World = ZM_World

// Exported world-data profiles are read from the addon GAME mount on both realms.
World.DataProfiles = {
	city = "data_static/zombiesim_world.json",
	preview = "data_static/zombiesim_world_preview.json"
}
World.LauncherMapProfiles = {
	zn_start = "city",
	zn_preview = "preview"
}
World.CustomProfileDataPrefix = "data_static/zombiesim_world_"
// Re-including this module during a Lua refresh must not discard a live world index.
World.DataPath = World.DataPath or World.DataProfiles.city
World.ActiveProfile = World.ActiveProfile or "city"

// Direction metadata also defines the only accepted values for graph traversal.
local directions = {
	N = { x = 0, y = -1, opposite = "S" },
	E = { x = 1, y = 0, opposite = "W" },
	S = { x = 0, y = 1, opposite = "N" },
	W = { x = -1, y = 0, opposite = "E" }
}

// Internal keys keep coordinate lookups O(1) after the index is loaded.
local function coordinateKey(x, y)
	return tostring(x) .. "," .. tostring(y)
end

// JSON references are zero-based ids, while Lua arrays begin at one.
local function indexedValue(values, id)
	if id == nil or type(id) ~= "number" then
		return nil
	end

	return values[id + 1]
end

// Normalizes caller input but rejects diagonals and any unknown direction.
local function normalizeDirection(direction)
	if type(direction) ~= "string" then
		return nil
	end

	direction = string.upper(direction)
	if directions[direction] then
		return direction
	end

	return nil
end

// Binary min-heap operations used by FindPath's A* open set.
local function heapPush(heap, entry)
	heap[#heap + 1] = entry
	local index = #heap

	while index > 1 do
		local parentIndex = math.floor(index / 2)
		if heap[parentIndex].priority <= entry.priority then
			break
		end

		heap[index] = heap[parentIndex]
		index = parentIndex
	end

	heap[index] = entry
end

local function heapPop(heap)
	if #heap == 0 then
		return nil
	end

	local first = heap[1]
	local last = table.remove(heap)
	if #heap == 0 then
		return first
	end

	local index = 1
	while true do
		local leftIndex = index * 2
		local rightIndex = leftIndex + 1
		if leftIndex > #heap then
			break
		end

		local childIndex = leftIndex
		if rightIndex <= #heap and heap[rightIndex].priority < heap[leftIndex].priority then
			childIndex = rightIndex
		end
		if heap[childIndex].priority >= last.priority then
			break
		end

		heap[index] = heap[childIndex]
		index = childIndex
	end

	heap[index] = last
	return first
end

// Returns true only after a complete and validated runtime index has been loaded.
function World:IsLoaded()
	return self.Data ~= nil and self.Indexes ~= nil
end

// Returns the most recent load error; useful when a release has not been staged yet.
function World:GetLoadError()
	return self.LastError
end

// Returns the raw exported table. Prefer the helpers below for gameplay queries.
function World:GetData()
	return self.Data
end

// Returns the GAME-relative data file for a built-in or safely named custom world profile.
function World:GetProfileDataPath(profile)
	if type(profile) ~= "string" then
		return nil
	end

	profile = string.lower(profile)
	if self.DataProfiles[profile] then
		return self.DataProfiles[profile]
	end
	if not string.match(profile, "^[a-z0-9_-]+$") then
		return nil
	end

	return self.CustomProfileDataPrefix .. profile .. ".json"
end

// Returns the dedicated map entity that selects this map's world-data profile.
// More than one marker is allowed only when every marker selects the same profile.
function World:GetMapProfileMarker()
	if not ents or not ents.FindByClass then
		return nil
	end

	local selectedProfile = nil
	local selectedMarker = nil
	for _, marker in ipairs(ents.FindByClass("zn_world_profile")) do
		local profile = marker.GetWorldProfile and marker:GetWorldProfile() or ""
		profile = string.lower(string.Trim(profile))
		if profile ~= "" then
			if selectedProfile and selectedProfile ~= profile then
				return nil, "Map has conflicting zn_world_profile entities"
			end
			selectedProfile = profile
			selectedMarker = marker
		end
	end

	return selectedMarker
end

// Returns the profile selected by the dedicated zn_world_profile map entity.
function World:GetMapDataProfile()
	local marker, markerError = self:GetMapProfileMarker()
	if markerError then
		return nil, markerError
	end

	if marker then
		return marker:GetWorldProfile()
	end
	if not game or not game.GetMap then
		return nil
	end

	local mapName = string.lower(string.match(game.GetMap(), "([^/\\]+)$") or game.GetMap())
	return self.LauncherMapProfiles[mapName]
end

// Returns the current map marker's non-negative opening delay in seconds.
// It is used only before a first-time player transitions to the origin safe room.
function World:GetMapStartDelay()
	local marker, markerError = self:GetMapProfileMarker()
	if markerError then
		return nil, markerError
	end
	if not marker or not marker.GetStartDelay then
		return 0
	end

	return math.max(tonumber(marker:GetStartDelay()) or 0, 0)
end

// Loads a named city-data profile and remembers it for safe-room maps without a selector marker.
function World:LoadProfile(profile)
	profile = type(profile) == "string" and string.lower(profile) or nil
	local path = self:GetProfileDataPath(profile)
	if not path then
		return false, "Unknown ZombieSim world-data profile: " .. tostring(profile)
	end

	local loaded, loadError = self:Load(path)
	if loaded then
		self.DataPath = path
		self.ActiveProfile = profile
	end
	return loaded, loadError
end

// Applies a map profile marker when present; otherwise restores the saved session profile.
function World:LoadMapProfile()
	local profile, markerError = self:GetMapDataProfile()
	if markerError then
		return false, markerError
	end

	if SERVER then
		local profileConVar = GetConVar("zombiesim_world_profile")
		if profile then
			profileConVar:SetString(profile)
		elseif profileConVar then
			profile = profileConVar:GetString()
		end
	elseif not profile then
		local profileConVar = GetConVar("zombiesim_world_profile")
		profile = profileConVar and profileConVar:GetString() or nil
	end

	return self:LoadProfile(profile or "city")
end

// Loads and indexes a runtime file. Returns true, or false plus a readable error.
// Pass a path only for testing or alternate world-data presets.
function World:Load(path)
	path = path or self.DataPath

	local json = file.Read(path, "GAME")
	if not json then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data was not found at " .. path
		return false, self.LastError
	end

	local data = util.JSONToTable(json)
	if type(data) ~= "table" or type(data.world) ~= "table" or type(data.cells) ~= "table" then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data at " .. path .. " has an invalid schema"
		return false, self.LastError
	end

	if data.schemaVersion ~= 1 or type(data.world.grid) ~= "table" then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data at " .. path .. " has an unsupported schema version"
		return false, self.LastError
	end

	if type(data.atmosphereProfiles) ~= "table" or #data.atmosphereProfiles < 1 then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data at " .. path .. " has no atmosphere profiles"
		return false, self.LastError
	end

	local width = tonumber(data.world.grid[1])
	local height = tonumber(data.world.grid[2])
	if not width or not height or width < 1 or height < 1 then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data at " .. path .. " has an invalid grid"
		return false, self.LastError
	end

	local indexes = {
		cellsById = {},
		cellsByCoordinate = {},
		cellsByMap = {},
		cellsByDistrict = {},
		cellsByLandmark = {},
		cellsByMetroLine = {},
		safeZonesById = {},
		atmosphereProfilesById = {}
	}

	for profileIndex, profile in ipairs(data.atmosphereProfiles) do
		local fog = type(profile) == "table" and profile.fog or nil
		if type(profile) ~= "table" or type(profile.id) ~= "string" or profile.id == "" or
			indexes.atmosphereProfilesById[profile.id] or type(fog) ~= "table" or
			type(fog.color) ~= "table" or #fog.color ~= 3 or tonumber(fog.start) == nil or
			tonumber(fog["end"]) == nil or tonumber(fog.maxDensity) == nil or tonumber(fog.stormMultiplier) == nil then
			self.Data = nil
			self.Indexes = nil
			self.LastError = "Runtime world data at " .. path .. " has invalid atmosphere profile " .. profileIndex
			return false, self.LastError
		end

		indexes.atmosphereProfilesById[profile.id] = profile
	end

	for _, cell in ipairs(data.cells) do
		local id = tonumber(cell.id)
		local atmosphereProfile = tonumber(cell.atmosphereProfile)
		if not id or id < 0 or id >= width * height or indexes.cellsById[id] or
			not atmosphereProfile or atmosphereProfile < 0 or atmosphereProfile >= #data.atmosphereProfiles or
			atmosphereProfile ~= math.floor(atmosphereProfile) then
			self.Data = nil
			self.Indexes = nil
			self.LastError = "Runtime world data at " .. path .. " has duplicate or invalid cell ids or atmosphere profiles"
			return false, self.LastError
		end

		local x = id % width
		local y = math.floor(id / width)
		cell.x = x
		cell.y = y
		indexes.cellsById[id] = cell
		indexes.cellsByCoordinate[coordinateKey(x, y)] = cell

		if type(cell.map) == "string" and cell.map ~= "" then
			indexes.cellsByMap[cell.map] = indexes.cellsByMap[cell.map] or {}
			table.insert(indexes.cellsByMap[cell.map], cell)
		end
		if type(cell.district) == "number" then
			indexes.cellsByDistrict[cell.district] = indexes.cellsByDistrict[cell.district] or {}
			table.insert(indexes.cellsByDistrict[cell.district], cell)
		end
		for _, landmarkId in ipairs(cell.landmarks or {}) do
			indexes.cellsByLandmark[landmarkId] = indexes.cellsByLandmark[landmarkId] or {}
			table.insert(indexes.cellsByLandmark[landmarkId], cell)
		end
		for _, lineId in ipairs((cell.metro or {}).lines or {}) do
			indexes.cellsByMetroLine[lineId] = indexes.cellsByMetroLine[lineId] or {}
			table.insert(indexes.cellsByMetroLine[lineId], cell)
		end
	end

	if #data.cells ~= width * height then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data at " .. path .. " does not contain a complete grid"
		return false, self.LastError
	end

	for _, safeZone in ipairs(data.safeZones or {}) do
		if type(safeZone.id) ~= "string" or safeZone.id == "" or indexes.safeZonesById[safeZone.id] then
			self.Data = nil
			self.Indexes = nil
			self.LastError = "Runtime world data at " .. path .. " has duplicate or invalid safe-zone ids"
			return false, self.LastError
		end

		indexes.safeZonesById[safeZone.id] = safeZone
	end

	if type(data.world.originSafeZoneId) ~= "string" or not indexes.safeZonesById[data.world.originSafeZoneId] then
		self.Data = nil
		self.Indexes = nil
		self.LastError = "Runtime world data at " .. path .. " has no valid origin safe-zone id"
		return false, self.LastError
	end

	self.Data = data
	self.Indexes = indexes
	self.LastError = nil
	return true
end

// Rebuilds every lookup index after a world-data file has changed.
function World:Reload(path)
	return self:Load(path or self.DataPath)
end

// Converts zero-based logical coordinates to the exported numeric cell id.
function World:GetCellId(x, y)
	if not self:IsLoaded() or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end

	x = math.floor(x)
	y = math.floor(y)
	local width = self.Data.world.grid[1]
	local height = self.Data.world.grid[2]
	if x < 0 or y < 0 or x >= width or y >= height then
		return nil
	end

	return y * width + x
end

// Converts an exported numeric cell id back to zero-based x/y coordinates.
function World:GetCoordinates(id)
	if not self:IsLoaded() or type(id) ~= "number" then
		return nil
	end

	local cell = self.Indexes.cellsById[id]
	if not cell then
		return nil
	end

	return cell.x, cell.y
end

// Retrieves one logical cell by its exported id, or nil when it does not exist.
function World:GetCellById(id)
	if not self:IsLoaded() or type(id) ~= "number" then
		return nil
	end

	return self.Indexes.cellsById[id]
end

// Retrieves one logical cell by zero-based x/y coordinates.
function World:GetCell(x, y)
	local id = self:GetCellId(x, y)
	if id == nil then
		return nil
	end

	return self.Indexes.cellsById[id]
end

// Returns the zero-based grid cell occupied by the logical world origin.
// Older exported worlds derive it from their origin safe-zone record.
function World:GetGridOrigin()
	if not self:IsLoaded() then
		return nil
	end

	local gridOrigin = self.Data.world.gridOrigin
	local x = tonumber(type(gridOrigin) == "table" and gridOrigin[1] or nil)
	local y = tonumber(type(gridOrigin) == "table" and gridOrigin[2] or nil)
	if x and y then
		return math.floor(x), math.floor(y)
	end

	local safeZone = self:GetOriginSafeZone()
	local cell = safeZone and self:GetCellById(safeZone.cell) or nil
	return cell and cell.x or 0, cell and cell.y or 0
end

// Converts a raw grid cell into the displayed logical world coordinate system.
function World:GetWorldCoordinates(reference, y)
	local cell = self:ResolveCell(reference, y)
	if not cell then
		return nil
	end

	local gridOriginX, gridOriginY = self:GetGridOrigin()
	local worldOrigin = self.Data.world.origin or {}
	return cell.x - gridOriginX + (tonumber(worldOrigin[1]) or 0), cell.y - gridOriginY + (tonumber(worldOrigin[2]) or 0)
end

// Converts a displayed logical world coordinate back into a raw grid cell.
function World:GetGridCoordinates(worldX, worldY)
	if not self:IsLoaded() or type(worldX) ~= "number" or type(worldY) ~= "number" then
		return nil
	end

	local gridOriginX, gridOriginY = self:GetGridOrigin()
	local worldOrigin = self.Data.world.origin or {}
	return math.floor(worldX - (tonumber(worldOrigin[1]) or 0) + gridOriginX), math.floor(worldY - (tonumber(worldOrigin[2]) or 0) + gridOriginY)
end

// Accepts a cell id, a loaded cell table, { x = ..., y = ... }, or x/y arguments.
// It keeps higher-level APIs convenient without allowing arbitrary map-name guesses.
function World:ResolveCell(reference, y)
	if type(reference) == "table" then
		if type(reference.id) == "number" then
			return self:GetCellById(reference.id)
		end
		if type(reference.x) == "number" and type(reference.y) == "number" then
			return self:GetCell(reference.x, reference.y)
		end
		return nil
	end
	if type(reference) == "number" and y == nil then
		return self:GetCellById(reference)
	end

	return self:GetCell(reference, y)
end

// Returns every logical cell that uses a recipe map, never just the first match.
function World:GetCellsForMap(mapName)
	if not self:IsLoaded() or type(mapName) ~= "string" then
		return nil
	end

	mapName = string.match(mapName, "([^/]+)$") or mapName
	return self.Indexes.cellsByMap[mapName]
end

// Looks up all cells in a district by display name or zero-based district id.
function World:GetCellsForDistrict(district)
	if not self:IsLoaded() then
		return nil
	end

	if type(district) == "string" then
		for id, record in ipairs(self.Data.districts) do
			if record.name == district then
				return self.Indexes.cellsByDistrict[id - 1] or {}
			end
		end
		return {}
	end

	return self.Indexes.cellsByDistrict[district] or {}
end

// Looks up all cells containing a landmark by name or zero-based landmark id.
function World:GetCellsForLandmark(landmark)
	if not self:IsLoaded() then
		return nil
	end

	if type(landmark) == "string" then
		for id, name in ipairs(self.Data.landmarks) do
			if name == landmark then
				return self.Indexes.cellsByLandmark[id - 1] or {}
			end
		end
		return {}
	end

	return self.Indexes.cellsByLandmark[landmark] or {}
end

// Looks up all cells served by a metro line name or zero-based line id.
function World:GetCellsForMetroLine(line)
	if not self:IsLoaded() then
		return nil
	end

	if type(line) == "string" then
		for id, name in ipairs((self.Data.metro or {}).lines or {}) do
			if name == line then
				return self.Indexes.cellsByMetroLine[id - 1] or {}
			end
		end
		return {}
	end

	return self.Indexes.cellsByMetroLine[line] or {}
end

// Produces the Source map transition name, for example "city/zn_grassland_open_none".
function World:GetMapPath(reference, y)
	local cell = self:ResolveCell(reference, y)
	if not cell then
		return nil
	end

	return self.Data.world.mapDirectory .. "/" .. cell.map
end

// Resolves a cell's shared terrain/tag record from its compact environment id.
function World:GetEnvironment(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and indexedValue(self.Data.environments, cell.environment) or nil
end

// Resolves a cell's district record, including its display name and color.
function World:GetDistrict(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and indexedValue(self.Data.districts, cell.district) or nil
end

// Returns a cell's ambient radiation intensity from 0 (safe) to 1 (peak exposure).
function World:GetRadiationIntensity(reference, y)
	local cell = self:ResolveCell(reference, y)
	return math.Clamp(tonumber(cell and cell.radiation) or 0, 0, 1)
end

// Returns a generated enemy-scaling danger intensity from 0 (safe) to 1 (extreme).
function World:GetDangerIntensity(reference, y)
	local cell = self:ResolveCell(reference, y)
	return math.Clamp(tonumber(cell and cell.danger) or 0, 0, 1)
end

// Returns the damage per second associated with peak radiation intensity.
function World:GetRadiationDamagePerSecondAtPeak()
	local hazards = self.Data and self.Data.hazards
	return math.max(tonumber(hazards and hazards.radiation and hazards.radiation.damagePerSecondAtPeak) or 0, 0)
end

// Returns the safe-zone record for a cell, or nil outside a safe zone.
// Its biome and landmarkVariant values identify the selected standalone den template.
function World:GetSafeZone(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and indexedValue(self.Data.safeZones, cell.safeZone) or nil
end

// Retrieves one standalone safe-zone record by its stable id, such as "safezone-3-17".
function World:GetSafeZoneById(safeZoneId)
	if not self:IsLoaded() or type(safeZoneId) ~= "string" or safeZoneId == "" then
		return nil
	end

	return self.Indexes.safeZonesById[safeZoneId]
end

// Returns the safe-room entrance anchored at the generated world origin.
function World:GetOriginSafeZone()
	if not self:IsLoaded() then
		return nil
	end

	return self:GetSafeZoneById(self.Data.world.originSafeZoneId)
end

// Returns the standalone den transition name for a safe-zone cell, or nil elsewhere.
// Dens are separate maps, not city-grid cells, even though their entrance belongs to a city cell.
function World:GetSafeZoneMap(reference, y)
	local safeZone = self:GetSafeZone(reference, y)
	if not safeZone or type(safeZone.map) ~= "string" or safeZone.map == "" then
		return nil
	end

	return self.Data.world.mapDirectory .. "/" .. safeZone.map
end

// Returns the reusable safe-room transition map anchored at the generated world origin.
function World:GetOriginSafeZoneMap()
	local safeZone = self:GetOriginSafeZone()
	if not safeZone or type(safeZone.map) ~= "string" or safeZone.map == "" then
		return nil
	end

	return self.Data.world.mapDirectory .. "/" .. safeZone.map
end

// Returns the safe-zone record at a player's persisted logical CellX/CellY.
// It returns nil when the player has no valid city position or is outside a safe-zone entrance.
function World:GetPlayerSafeZone(player)
	if player == nil then
		return nil
	end

	local x = tonumber(player.CellX)
	local y = tonumber(player.CellY)
	if not x or not y then
		return nil
	end

	local gridX, gridY = self:GetGridCoordinates(math.floor(x), math.floor(y))
	return gridX and self:GetSafeZone(gridX, gridY) or nil
end

// Returns the reusable safe-room transition map for a player's current city cell.
function World:GetPlayerSafeZoneMap(player)
	local safeZone = self:GetPlayerSafeZone(player)
	if not safeZone or type(safeZone.map) ~= "string" or safeZone.map == "" then
		return nil
	end

	return self.Data.world.mapDirectory .. "/" .. safeZone.map
end

// Returns the standalone safe room the player is currently in, not the city entrance they can access.
// CurrentSafeZoneId is persisted independently because CellX/CellY remains the player's city position.
function World:GetPlayerCurrentSafeZone(player)
	if player == nil then
		return nil
	end

	return self:GetSafeZoneById(player.CurrentSafeZoneId)
end

// Returns the current standalone safe-room transition map for a player, or nil while they are in the city.
function World:GetPlayerCurrentSafeZoneMap(player)
	local safeZone = self:GetPlayerCurrentSafeZone(player)
	if not safeZone or type(safeZone.map) ~= "string" or safeZone.map == "" then
		return nil
	end

	return self.Data.world.mapDirectory .. "/" .. safeZone.map
end

// Returns landmark names on a cell. The returned table is empty when none exist.
function World:GetLandmarks(reference, y)
	local cell = self:ResolveCell(reference, y)
	if not cell then
		return nil
	end

	local landmarks = {}
	for _, landmarkId in ipairs(cell.landmarks or {}) do
		local landmark = indexedValue(self.Data.landmarks, landmarkId)
		if landmark then
			table.insert(landmarks, landmark)
		end
	end

	return landmarks
end

// Returns the cell's metro-stop record, or nil if the cell has no stop.
function World:GetMetroStop(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and indexedValue((self.Data.metro or {}).stops or {}, (cell.metro or {}).stop) or nil
end

// Returns metro line names that pass through the cell.
function World:GetMetroLines(reference, y)
	local cell = self:ResolveCell(reference, y)
	if not cell then
		return nil
	end

	local lines = {}
	for _, lineId in ipairs((cell.metro or {}).lines or {}) do
		local line = indexedValue((self.Data.metro or {}).lines or {}, lineId)
		if line then
			table.insert(lines, line)
		end
	end

	return lines
end

// Resolves a cell's full atmosphere profile from its compact zero-based profile index.
function World:GetAtmosphereProfile(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and indexedValue(self.Data.atmosphereProfiles, cell.atmosphereProfile) or nil
end

// Resolves an atmosphere profile directly from the zero-based id sent to clients during map travel.
function World:GetAtmosphereProfileByIndex(profileIndex)
	if not self:IsLoaded() or type(profileIndex) ~= "number" then
		return nil
	end

	return indexedValue(self.Data.atmosphereProfiles, math.floor(profileIndex))
end

// Returns the stable string id for a cell's atmosphere profile.
function World:GetAtmosphereProfileId(reference, y)
	local profile = self:GetAtmosphereProfile(reference, y)
	return profile and profile.id or nil
end

// Returns bridge, ramp-exit, and diagonal-highway metadata for a cell.
function World:GetTransport(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and cell.transport or nil
end

// Returns whether a cell belongs to a dead zone.
function World:IsDeadZone(reference, y)
	local cell = self:ResolveCell(reference, y)
	return cell and cell.deadZone or false
end

// Returns whether a cell has an associated safe-zone record.
function World:IsSafeZone(reference, y)
	return self:GetSafeZone(reference, y) ~= nil
end

// Finds a graph exit by direction. Call as GetExit(cellOrId, "N") or GetExit(x, y, "N").
// An exit means the cells are connected; it may still be blocked for road travel.
function World:GetExit(reference, yOrDirection, direction)
	local cell
	if direction then
		cell = self:GetCell(reference, yOrDirection)
	else
		cell = self:ResolveCell(reference)
		direction = yOrDirection
	end
	direction = normalizeDirection(direction)
	if not cell or not direction then
		return nil
	end

	for _, exit in ipairs(cell.exits or {}) do
		if exit.direction == direction then
			return exit
		end
	end

	return nil
end

// Chooses a permitted exit mode: "road", "highway", or "any" (the default).
// Blocked roads are rejected unless allowBlocked is true; highways are never blocked by this data.
function World:GetTravelMode(exit, requestedMode, allowBlocked)
	if type(exit) ~= "table" then
		return nil
	end

	requestedMode = requestedMode or "any"
	for _, mode in ipairs(exit.modes or {}) do
		if (requestedMode == "any" or mode.type == requestedMode) and (allowBlocked or not mode.blocked) then
			return mode
		end
	end

	return nil
end

// Validates a movement and returns targetCell, exit, mode on success.
// Call as CanTravel(cellOrId, "N", "road", allowBlocked) or CanTravel(x, y, "N", "road", allowBlocked).
function World:CanTravel(reference, yOrDirection, directionOrMode, requestedMode, allowBlocked)
	local exit
	if type(reference) == "number" and type(yOrDirection) == "number" then
		exit = self:GetExit(reference, yOrDirection, directionOrMode)
	else
		exit = self:GetExit(reference, yOrDirection)
		local requestedAllowBlocked = requestedMode
		requestedMode = directionOrMode
		allowBlocked = requestedAllowBlocked
	end
	local mode = self:GetTravelMode(exit, requestedMode, allowBlocked)
	if not mode then
		return nil
	end

	return self:GetCellById(exit.cell), exit, mode
end

// Validates travel and returns a Source transition name followed by targetCell, exit, and mode.
function World:GetTransitionMap(reference, yOrDirection, directionOrMode, requestedMode, allowBlocked)
	local target, exit, mode = self:CanTravel(reference, yOrDirection, directionOrMode, requestedMode, allowBlocked)
	if not target then
		return nil
	end

	return self:GetMapPath(target), target, exit, mode
end

// Searches cells using optional map, terrain, profile, atmosphere, district, landmark, metroLine,
// safeZone, deadZone, building, metroStop, limit, and predicate criteria.
function World:FindCells(criteria)
	if not self:IsLoaded() then
		return nil
	end

	criteria = criteria or {}
	local matches = {}
	for _, cell in ipairs(self.Data.cells) do
		local environment = indexedValue(self.Data.environments, cell.environment) or {}
		local district = indexedValue(self.Data.districts, cell.district) or {}
		local safeZone = indexedValue(self.Data.safeZones, cell.safeZone)
		local atmosphereProfile = indexedValue(self.Data.atmosphereProfiles, cell.atmosphereProfile)
		local atmosphere = atmosphereProfile and atmosphereProfile.id or nil
		local matchesCriteria =
			(criteria.map == nil or cell.map == criteria.map) and
			(criteria.terrain == nil or environment.terrain == criteria.terrain) and
			(criteria.profile == nil or cell.profile == criteria.profile) and
			(criteria.atmosphere == nil or atmosphere == criteria.atmosphere) and
			(criteria.district == nil or district.name == criteria.district) and
			(criteria.deadZone == nil or cell.deadZone == criteria.deadZone) and
			(criteria.building == nil or cell.building == criteria.building) and
			(criteria.safeZone == nil or (safeZone ~= nil) == criteria.safeZone) and
			(criteria.metroStop == nil or (self:GetMetroStop(cell) ~= nil) == criteria.metroStop)

		if matchesCriteria and criteria.landmark then
			matchesCriteria = false
			for _, landmark in ipairs(self:GetLandmarks(cell)) do
				if landmark == criteria.landmark then
					matchesCriteria = true
					break
				end
			end
		end
		if matchesCriteria and criteria.metroLine then
			matchesCriteria = false
			for _, line in ipairs(self:GetMetroLines(cell)) do
				if line == criteria.metroLine then
					matchesCriteria = true
					break
				end
			end
		end
		if matchesCriteria and criteria.predicate then
			matchesCriteria = criteria.predicate(cell, environment, district, safeZone)
		end

		if matchesCriteria then
			table.insert(matches, cell)
			if criteria.limit and #matches >= criteria.limit then
				break
			end
		end
	end

	return matches
end

// Finds the nearest matching cell by Manhattan grid distance; returns cell, distance.
function World:FindNearestCell(reference, criteria)
	local origin = self:ResolveCell(reference)
	if not origin then
		return nil
	end

	local candidates = self:FindCells(criteria)
	local nearest
	local nearestDistance
	for _, candidate in ipairs(candidates or {}) do
		local distance = math.abs(candidate.x - origin.x) + math.abs(candidate.y - origin.y)
		if not nearestDistance or distance < nearestDistance then
			nearest = candidate
			nearestDistance = distance
		end
	end

	return nearest, nearestDistance
end

// Runs A* over valid exits. Options: mode, allowBlocked, maximumVisited, canEnter, and stepCost.
// Road and motorway travel can change mode only at a cell with an explicit motorway ramp.
// Returns { cells, directions, modes, cost, visited } or nil plus a failure reason.
function World:FindPath(startReference, goalReference, options)
	local start = self:ResolveCell(startReference)
	local goal = self:ResolveCell(goalReference)
	if not start or not goal then
		return nil, "Start and goal cells must exist in the loaded world"
	end
	if start.id == goal.id then
		return { cells = { start }, directions = {}, modes = {}, cost = 0, visited = 1 }
	end

	options = options or {}
	local maximumVisited = options.maximumVisited or #self.Data.cells * 2
	local modeName = options.mode or "any"
	local open = {}
	local startState = tostring(start.id) .. ":start"
	local costs = { [startState] = 0 }
	local cameFrom = {}
	local visited = 0

	heapPush(open, { id = start.id, mode = nil, state = startState, cost = 0, priority = math.abs(start.x - goal.x) + math.abs(start.y - goal.y) })
	while #open > 0 and visited < maximumVisited do
		local current = heapPop(open)
		if current.cost == costs[current.state] then
			visited = visited + 1
			if current.id == goal.id then
				local reverseSteps = {}
				local state = current.state
				while state ~= startState do
					local step = cameFrom[state]
					table.insert(reverseSteps, step)
					state = step.from
				end

				local result = { cells = { start }, directions = {}, modes = {}, cost = current.cost, visited = visited }
				for index = #reverseSteps, 1, -1 do
					local step = reverseSteps[index]
					table.insert(result.cells, self:GetCellById(step.to))
					table.insert(result.directions, step.direction)
					table.insert(result.modes, step.mode)
				end
				return result
			end

			local cell = self:GetCellById(current.id)
			local transport = cell.transport or {}
			local canChangeMode = current.mode == nil or #(transport.rampExits or {}) > 0
			for _, exit in ipairs(cell.exits or {}) do
				local target = self:GetCellById(exit.cell)
				for _, mode in ipairs(exit.modes or {}) do
					local isRequestedMode = modeName == "any" or mode.type == modeName
					local isAvailable = options.allowBlocked or not mode.blocked
					local canUseMode = canChangeMode or current.mode == mode.type
					if target and isRequestedMode and isAvailable and canUseMode and (not options.canEnter or options.canEnter(target, cell, exit, mode)) then
						local stepCost = options.stepCost and options.stepCost(target, cell, exit, mode) or 1
						if type(stepCost) == "number" and stepCost > 0 then
							local nextCost = current.cost + stepCost
							local nextState = tostring(target.id) .. ":" .. mode.type
							if costs[nextState] == nil or nextCost < costs[nextState] then
								costs[nextState] = nextCost
								cameFrom[nextState] = { from = current.state, to = target.id, direction = exit.direction, mode = mode.type }
								local heuristic = math.abs(target.x - goal.x) + math.abs(target.y - goal.y)
								heapPush(open, { id = target.id, mode = mode.type, state = nextState, cost = nextCost, priority = nextCost + heuristic })
							end
						end
					end
				end
			end
		end
	end

	return nil, "No path was found within the visit limit"
end
