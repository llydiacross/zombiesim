// Shared client drawing for construction pieces, placement outlines and gallery previews.
local Construction = ZM_Construction
local Geometry = {}
Construction.Geometry = Geometry

local shapes = {}
local stats = { frame = -1, boxes = 0, faces = 0, lines = 0 }
local worldA, worldB, worldC, worldD = Vector(), Vector(), Vector(), Vector()

local function beginFrame()
	local frame = FrameNumber()
	if stats.frame == frame then return end
	stats.frame, stats.boxes, stats.faces, stats.lines = frame, 0, 0, 0
end

local function shapeFor(kind, yaw)
	local parts = Construction.GetParts(kind, yaw)
	if not parts then return nil end
	local key = kind .. ":" .. tostring(yaw)
	if shapes[key] then return shapes[key] end
	local _, _, minZ, _, _, maxZ = Construction.PieceBounds(kind, yaw)
	local shape = { parts = parts, minZ = minZ, maxZ = maxZ, wire = {}, fills = {} }
	for _, part in ipairs(parts) do
		local wire = {
			part = part, vertices = {}, edges = {},
			mins = Vector(part.minX, part.minY, part.minZ),
			maxs = Vector(part.maxX, part.maxY, part.maxZ)
		}
		for _, vertex in ipairs(part.vertices) do
			wire.vertices[#wire.vertices + 1] = Vector(vertex[1], vertex[2], vertex[3])
		end
		if not part.box then
			local seen = {}
			for _, face in ipairs(part.faces) do
				for index, first in ipairs(face) do
					local second = face[index % #face + 1]
					local edge = math.min(first, second) .. ":" .. math.max(first, second)
					if not seen[edge] then
						seen[edge] = true
						wire.edges[#wire.edges + 1] = { first, second }
					end
				end
			end
		end
		shape.wire[#shape.wire + 1] = wire
	end
	shapes[key] = shape
	return shape
end

local function samePoint(a, b)
	return math.abs(a[1] - b[1]) < 0.0001 and math.abs(a[2] - b[2]) < 0.0001
		and math.abs(a[3] - b[3]) < 0.0001
end

local function appendUnique(points, point)
	for _, existing in ipairs(points) do
		if samePoint(existing, point) then return end
	end
	points[#points + 1] = point
end

// Clip convex faces at a horizontal build-progress plane, including its visible cap.
function Geometry.ClipPart(part, height)
	if height <= part.minZ then return {} end
	local clipped, cap = {}, {}
	for _, face in ipairs(part.faces) do
		local points = {}
		for index, firstIndex in ipairs(face) do
			local first = part.vertices[firstIndex]
			local second = part.vertices[face[index % #face + 1]]
			if first[3] <= height then
				if not points[#points] or not samePoint(points[#points], first) then
					points[#points + 1] = first
				end
				if first[3] == height then appendUnique(cap, first) end
			end
			if (first[3] < height and second[3] > height)
				or (first[3] > height and second[3] < height) then
				local fraction = (height - first[3]) / (second[3] - first[3])
				local crossing = {
					first[1] + (second[1] - first[1]) * fraction,
					first[2] + (second[2] - first[2]) * fraction,
					height
				}
				points[#points + 1] = crossing
				appendUnique(cap, crossing)
			end
		end
		if #points > 1 and samePoint(points[1], points[#points]) then points[#points] = nil end
		if #points >= 3 then clipped[#clipped + 1] = points end
	end
	if height < part.maxZ and #cap >= 3 then
		local centerX, centerY = 0, 0
		for _, point in ipairs(cap) do
			centerX, centerY = centerX + point[1], centerY + point[2]
		end
		centerX, centerY = centerX / #cap, centerY / #cap
		table.sort(cap, function(a, b)
			return math.atan2(a[2] - centerY, a[1] - centerX) < math.atan2(b[2] - centerY, b[1] - centerX)
		end)
		clipped[#clipped + 1] = cap
	end
	return clipped
end

local function fillFor(shape, step)
	if shape.fills[step] then return shape.fills[step] end
	local height = shape.minZ + (shape.maxZ - shape.minZ) * step / 64
	local fill = {}
	for _, part in ipairs(shape.parts) do
		if height > part.minZ then
			if part.box then
				fill[#fill + 1] = {
					box = true,
					mins = Vector(part.minX, part.minY, part.minZ),
					maxs = Vector(part.maxX, part.maxY, math.min(part.maxZ, height))
				}
			else
				local faces = {}
				for _, face in ipairs(Geometry.ClipPart(part, height)) do
					local vertices = {}
					for _, vertex in ipairs(face) do
						vertices[#vertices + 1] = Vector(vertex[1], vertex[2], vertex[3])
					end
					faces[#faces + 1] = vertices
				end
				fill[#fill + 1] = { faces = faces }
			end
		end
	end
	shape.fills[step] = fill
	return fill
end

local function placeWorldVertex(target, origin, vertex)
	target:SetUnpacked(origin.x + vertex.x, origin.y + vertex.y, origin.z + vertex.z)
end

local function drawFace(origin, face, color)
	// Source renders clockwise-facing quads; shared convex faces wind outwards counter-clockwise.
	placeWorldVertex(worldA, origin, face[1])
	if #face == 4 then
		placeWorldVertex(worldB, origin, face[4])
		placeWorldVertex(worldC, origin, face[3])
		placeWorldVertex(worldD, origin, face[2])
		render.DrawQuad(worldA, worldB, worldC, worldD, color)
		stats.faces = stats.faces + 1
		return
	end
	for index = 2, #face - 1 do
		placeWorldVertex(worldB, origin, face[index + 1])
		placeWorldVertex(worldC, origin, face[index])
		render.DrawQuad(worldA, worldB, worldC, worldC, color)
		stats.faces = stats.faces + 1
	end
end

// The caller supplies the material. Box pieces retain their original DrawBox presentation.
function Geometry.DrawSolid(kind, yaw, origin, color, progress)
	local shape = shapeFor(kind, yaw)
	if not shape then return end
	local step = math.Clamp(math.floor((progress or 1) * 64 + 0.5), 0, 64)
	if step == 0 then return end
	beginFrame()
	for _, part in ipairs(fillFor(shape, step)) do
		if part.box then
			render.DrawBox(origin, angle_zero, part.mins, part.maxs, color)
			stats.boxes = stats.boxes + 1
		else
			for _, face in ipairs(part.faces) do drawFace(origin, face, color) end
		end
	end
end

function Geometry.DrawWire(kind, yaw, origin, color)
	local shape = shapeFor(kind, yaw)
	if not shape then return end
	beginFrame()
	for _, wire in ipairs(shape.wire) do
		local part = wire.part
		if part.box then
			render.DrawWireframeBox(origin, angle_zero, wire.mins, wire.maxs, color, true)
			stats.boxes = stats.boxes + 1
		else
			for _, edge in ipairs(wire.edges) do
				placeWorldVertex(worldA, origin, wire.vertices[edge[1]])
				placeWorldVertex(worldB, origin, wire.vertices[edge[2]])
				render.DrawLine(worldA, worldB, color, true)
				stats.lines = stats.lines + 1
			end
		end
	end
end

// Isometric polygons are built once per gallery tile, not during its Paint callback.
function Geometry.PreviewPolygons(kind, width, height)
	local parts = Construction.GetParts(kind, 0)
	if not parts then return {} end
	local polygons, minX, minY, maxX, maxY = {}
	for _, part in ipairs(parts) do
		for _, face in ipairs(part.faces) do
			local a, b, c = part.vertices[face[1]], part.vertices[face[2]], part.vertices[face[3]]
			local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
			local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
			local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
			if nx + ny + nz > 0 then
				local polygon = { points = {}, depth = 0, shade = nz > 0 and 1 or (nx > 0 and 0.78 or 0.62) }
				for _, vertexIndex in ipairs(face) do
					local vertex = part.vertices[vertexIndex]
					local x, y = vertex[1] - vertex[2], (vertex[1] + vertex[2]) * 0.5 - vertex[3]
					minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
					minY, maxY = math.min(minY or y, y), math.max(maxY or y, y)
					polygon.depth = polygon.depth + vertex[1] + vertex[2] + vertex[3]
					polygon.points[#polygon.points + 1] = { x = x, y = y }
				end
				polygon.depth = polygon.depth / #face
				polygons[#polygons + 1] = polygon
			end
		end
	end
	if #polygons == 0 then return polygons end
	table.sort(polygons, function(a, b) return a.depth < b.depth end)
	local scale = math.min(width / math.max(maxX - minX, 1), height / math.max(maxY - minY, 1))
	for _, polygon in ipairs(polygons) do
		for _, point in ipairs(polygon.points) do
			point.x = width * 0.5 + (point.x - (minX + maxX) * 0.5) * scale
			point.y = height * 0.5 + (point.y - (minY + maxY) * 0.5) * scale
		end
	end
	return polygons
end

function Geometry.Status()
	return { frame = stats.frame, currentFrame = FrameNumber(), boxes = stats.boxes, faces = stats.faces, lines = stats.lines }
end
