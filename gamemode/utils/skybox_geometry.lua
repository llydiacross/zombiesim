ZM_SkyboxGeometry = ZM_SkyboxGeometry or {}
local Geometry = ZM_SkyboxGeometry

function Geometry.ValidateManifest(data, world, cells)
	if type(data) ~= "table" or (data.schemaVersion ~= 1 and data.schemaVersion ~= 2) then
		return false, "unsupported skyline schema"
	end
	local bounds = world and world.cellBounds
	if data.schemaVersion == 1 then
		if bounds and bounds.revision == 2 then return false, "legacy skyline with expanded world" end
		if bounds and data.cellSpan ~= bounds.neighbourPitch then return false, "legacy skyline/world pitch mismatch" end
		return true
	end
	if type(bounds) ~= "table" or bounds.revision ~= 2 or type(data.cellBounds) ~= "table"
		or type(data.templatePlanSha256) ~= "string" or #data.templatePlanSha256 ~= 64
		or not string.match(data.templatePlanSha256, "^[a-fA-F0-9]+$") or type(data.recipes) ~= "table"
		or data.templatePlanSha256 ~= world.templatePlanSha256 then
		return false, "expanded skyline/world plan mismatch"
	end
	if data.profile ~= world.profileId then return false, "expanded skyline/world profile mismatch" end
	for _, key in ipairs({"revision", "tileSize", "coreTileGridSize", "coreHalfExtent", "traversableHalfExtent",
		"visualHalfExtent", "neighbourPitch", "coastContactHalfExtent", "playableCeiling"}) do
		if data.cellBounds[key] ~= bounds[key] then return false, "skyline/world bounds mismatch: " .. key end
	end
	if data.cellSpan ~= bounds.neighbourPitch or type(data.geometry) ~= "table" then
		return false, "invalid expanded skyline geometry"
	end
	for recipe in pairs(data.recipes or {}) do
		local record = data.geometry[recipe]
		if type(record) ~= "table" or type(record.waterSides) ~= "table" or type(record.vmfSha256) ~= "string"
			or #record.vmfSha256 ~= 64 or record.coastHalfExtent ~= bounds.coastContactHalfExtent
			or not string.match(record.vmfSha256, "^[a-fA-F0-9]+$")
			or record.visualHalfExtent ~= bounds.visualHalfExtent then
			return false, "invalid skyline footprint: " .. recipe
		end
		local seen = {}
		for _, side in ipairs(record.waterSides) do
			if (side ~= "N" and side ~= "E" and side ~= "S" and side ~= "W") or seen[side] then
				return false, "invalid skyline coast side: " .. recipe
			end
			seen[side] = true
		end
	end
	for _, cell in ipairs(cells or {}) do
		local record = data.geometry[cell.map]
		if not record then return false, "missing skyline footprint: " .. tostring(cell.map) end
		local expected, actual = {}, {}
		for _, side in ipairs(cell.waterSides or {}) do expected[side] = true end
		for _, side in ipairs(record.waterSides) do actual[side] = true end
		for _, side in ipairs({"N", "E", "S", "W"}) do
			if expected[side] ~= actual[side] then return false, "skyline/world coast mismatch: " .. cell.map end
		end
	end
	return true
end

function Geometry.GetFogBoundary(manifest)
	return manifest.schemaVersion == 2 and manifest.cellBounds.coastContactHalfExtent or manifest.cellSpan * 0.5
end

function Geometry.GetLandRectangle(manifest, recipe, x, y)
	local half = manifest.cellSpan / manifest.scale * 0.5
	local rectangle = { x0 = x - half, y0 = y - half, x1 = x + half, y1 = y + half }
	local footprint = manifest.schemaVersion == 2 and manifest.geometry[recipe]
	if footprint then
		local coastHalf = footprint.coastHalfExtent / manifest.scale
		for _, side in ipairs(footprint.waterSides) do
			if side == "N" then rectangle.y1 = y + coastHalf
			elseif side == "E" then rectangle.x1 = x + coastHalf
			elseif side == "S" then rectangle.y0 = y - coastHalf
			elseif side == "W" then rectangle.x0 = x - coastHalf end
		end
	end
	return rectangle
end

// Partition omitted bands without double-drawing mixed corners.
function Geometry.GetWaterBands(rectangle, x, y, half)
	local bands = {}
	local function add(x0, y0, x1, y1)
		if x1 > x0 and y1 > y0 then
			table.insert(bands, { x = (x0 + x1) * 0.5, y = (y0 + y1) * 0.5,
				halfX = (x1 - x0) * 0.5, halfY = (y1 - y0) * 0.5 })
		end
	end
	add(x - half, rectangle.y1, x + half, y + half)
	add(x - half, y - half, x + half, rectangle.y0)
	add(x - half, rectangle.y0, rectangle.x0, rectangle.y1)
	add(rectangle.x1, rectangle.y0, x + half, rectangle.y1)
	return bands
end

function Geometry.DistanceToLand(x, y, rectangle)
	local dx = math.max(rectangle.x0 - x, x - rectangle.x1, 0)
	local dy = math.max(rectangle.y0 - y, y - rectangle.y1, 0)
	return math.sqrt(dx * dx + dy * dy)
end

// Every full slot and omitted band shares the same cuts, including mixed-corner joins.
function Geometry.GetCoastAxis(minimum, maximum, centre, span, divisions, coastHalf)
	local values, unique = {}, {}
	local function add(value)
		if not unique[value] then
			unique[value] = true
			table.insert(values, value)
		end
	end
	for index = -1, divisions + 1 do add(centre - span * 0.5 + index * span / divisions) end
	if coastHalf and coastHalf < span * 0.5 then
		add(centre - coastHalf)
		add(centre + coastHalf)
	end
	table.sort(values)
	local first, last
	for index, value in ipairs(values) do
		if math.abs(value - minimum) < 0.000001 then first = index end
		if math.abs(value - maximum) < 0.000001 then last = index end
	end
	if not first or not last or first >= last then error("Unsupported coastline grid boundary") end
	local axis = {}
	for index = first - 1, last + 1 do axis[index - first] = values[index] end
	return axis, last - first
end
