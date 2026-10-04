// Runtime 3D skybox. Every city recipe carries the same sky_camera room; this module draws the current cell's
// neighbouring recipe models inside it, then a fog-coloured horizon wall and a drifting cloud deck. Models and the
// manifest come from bin/build_skybox_models.ps1, so cells that share a recipe still show their own surroundings.
ZM_Skybox = ZM_Skybox or {}
local Skybox = ZM_Skybox

local manifestSchemaVersion = 1
local domeSegments = 48
// Elevation (degrees above the eye) and alpha for each horizon-wall ring; below the eye the wall is opaque.
local domeRings = {
    { elevation = -40, alpha = 1 },
    { elevation = 0, alpha = 1 },
    { elevation = 3, alpha = 0.9 },
    { elevation = 7, alpha = 0.55 },
    { elevation = 12, alpha = 0.18 },
    { elevation = 18, alpha = 0 }
}
// The fog becomes opaque slightly inside the outermost modelled ring so its far edge is never seen.
local fogEdgeFraction = 0.9
local cloudClusterCount = 56
local cloudSeed = 7331
// Sky-space units (1 sky unit = manifest.scale world units).
local cloudBaseHeight = 300
local cloudHeightRange = 70
local cloudDriftSpeed = 1.6
// Coastline (sky units relative to the sky camera): tile street surfaces sit at +32 world units (+2 sky units).
local coastStreetHeight = 2
local coastSeaLevel = -3
local coastFoamWidth = 5
local coastSeaSubdivisions = 4
// The room's floor shell starts 80 units below the sky camera; world-space work stays below this clearance.
local skyRoomClearance = 128

local domeMaterial = CreateMaterial("zombiesim_skybox_horizon_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1,
    ["$nofog"] = 1
})
local cloudMaterial = CreateMaterial("zombiesim_skybox_cloud_v1", "UnlitGeneric", {
    ["$basetexture"] = "particle/smokesprites0001",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1,
    ["$nofog"] = 1
})
// The coast is fogged with the rest of the sky pass so it fades into the horizon wall.
local seaMaterial = CreateMaterial("zombiesim_skybox_sea_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
local seaWallMaterial = CreateMaterial("zombiesim_skybox_seawall_v1", "UnlitGeneric", {
    ["$basetexture"] = "concrete/concretewall001a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
local foamMaterial = CreateMaterial("zombiesim_skybox_foam_v1", "UnlitGeneric", {
    ["$basetexture"] = "particle/smokesprites0001",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1
})
// Burning wrecks and rooftops. Smoke is fogged with the sky pass so distant plumes melt into the horizon.
local smokeMaterial = CreateMaterial("zombiesim_skybox_smoke_v1", "UnlitGeneric", {
    ["$basetexture"] = "particle/smokesprites0001",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1
})
local fireMaterial = CreateMaterial("zombiesim_skybox_fire_v1", "UnlitGeneric", {
    ["$basetexture"] = "effects/fire_cloud1",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$additive"] = 1,
    ["$nocull"] = 1
})
local glowMaterial = CreateMaterial("zombiesim_skybox_glow_v1", "UnlitGeneric", {
    ["$basetexture"] = "sprites/light_glow02",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$additive"] = 1,
    ["$nocull"] = 1
})
// Set dressing: props are drawn while their projected radius/distance exceeds this, highest priority first, up to a
// per-frame budget scaled by zombiesim_sky_props. Each prop is a separate model draw, so the budget bounds the cost.
local detailAngularThreshold = 0.004
local detailDrawBudget = 200
// The scale matrix hides how small the models are on screen, so the engine would pick LOD0; force a low LOD.
local detailModelLod = 3
// Fire candidates come from the manifest (kind 1 wreck, kind 2 rooftop); a stable per-cell hash picks which burn.
local fireChance = { 0.06, 0.08 }
local firesPerCell = 2
local maxFires = 32
local smokePuffs = 9
// Per kind (sky units / seconds): base lift, plume rise, sideways drift, puff start and growth, cycle, flame size.
local fireStyles = {
    { lift = 1.5, rise = 40, drift = 24, size = 2.5, grow = 11, cycle = 14, flame = 2.2 },
    { lift = 0.5, rise = 85, drift = 48, size = 4.5, grow = 22, cycle = 20, flame = 4 }
}
local smokeDriftX, smokeDriftY = 0.944, 0.33

Skybox.Stats = Skybox.Stats or {}
Skybox.ViewOrigin = Skybox.ViewOrigin or Vector()
Skybox.SkyEye = Skybox.SkyEye or Vector()
Skybox.FogResult = Skybox.FogResult or { color = {} }

local defaultFogColor = { 128, 128, 128 }
local snowDepthBias = 0.00005
CreateClientConVar("zombiesim_sky_matched_lighting", "1", false, false,
    "Lights skybox models from the playable cell's lighting (0 uses the sky room's own model lighting).", 0, 1)
// The sky room has none of the playable cell's baked lighting, so the models are lit from samples of the playable
// map instead: ground points on a ring just inside the cell edge, where the skybox meets the real world.
local lightSampleInset = 256
local lightSampleStep = 256
local lightSampleLift = 8
local lightRefreshSeconds = 2
local lightDirections = {
    { BOX_FRONT, Vector(1, 0, 0) },
    { BOX_BACK, Vector(-1, 0, 0) },
    { BOX_RIGHT, Vector(0, 1, 0) },
    { BOX_LEFT, Vector(0, -1, 0) },
    { BOX_TOP, Vector(0, 0, 1) },
    { BOX_BOTTOM, Vector(0, 0, -1) }
}
local domeColor = Vector()
local domeMatrix = Matrix()
local identityMatrix = Matrix()
local coastColor = Vector()

local function mapBasename(mapPath)
    local mapName = string.lower(string.match(tostring(mapPath or ""), "([^/\\]+)$") or "")
    return (string.gsub(mapName, "%.bsp$", ""))
end

local function getConVarNumber(name, fallback)
    local convar = GetConVar(name)
    return convar and convar:GetFloat() or fallback
end

local function smoothstep(edge0, edge1, value)
    local t = math.Clamp((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
end

function Skybox:RemoveModels()
    for _, list in ipairs({ self.Placements or {}, self.SnowPlacements or {} }) do
        for _, placement in ipairs(list) do
            if IsValid(placement.entity) then placement.entity:Remove() end
        end
    end
    for _, model in pairs(self.DetailModels or {}) do
        if model and IsValid(model.entity) then model.entity:Remove() end
    end
    self.Placements = {}
    self.SnowPlacements = {}
    self.DetailModels = {}
    self.DetailProps = {}
    self.Fires = {}
end

local function createSkyModel(modelPath, origin)
    if not file.Exists(modelPath, "GAME") then return nil, false end
    local entity = ClientsideModel(modelPath, RENDERGROUP_OPAQUE)
    if not IsValid(entity) then return nil, true end
    entity:SetNoDraw(true)
    entity:SetPos(origin)
    entity:SetAngles(angle_zero)
    return entity, true
end

// Loads (once per world profile) the recipe-to-model manifest for the active world profile.
function Skybox:GetManifest()
    local profile = ZM_World and ZM_World.ActiveProfile
    if self.ManifestProfile == profile then return self.Manifest end
    self.ManifestProfile = profile
    self.Manifest = nil
    self.ManifestError = nil

    local path = "data_static/zombiesim_skybox_" .. tostring(profile) .. ".json"
    local text = file.Read(path, "GAME")
    if not text then
        self.ManifestError = "missing " .. path
        return nil
    end
    local data = util.JSONToTable(text)
    local origin = type(data) == "table" and data.cameraOrigin
    if type(data) ~= "table" or tonumber(data.schemaVersion) ~= manifestSchemaVersion or
        (tonumber(data.scale) or 0) <= 0 or (tonumber(data.cellSpan) or 0) <= 0 or
        (tonumber(data.neighbourRadius) or 0) < 1 or type(origin) ~= "table" or type(data.recipes) ~= "table" then
        self.ManifestError = "invalid " .. path
        return nil
    end
    data.cameraVector = Vector(tonumber(origin[1]) or 0, tonumber(origin[2]) or 0, tonumber(origin[3]) or 0)
    data.recipeCount = table.Count(data.recipes)
    self.Manifest = data
    return data
end

// Highest world Z of the playable volume when the loaded map carries the skybox room (every city recipe), else nil.
// Dens and other maps are absent from the manifest, so their bounds are left untouched.
function Skybox:GetPlayableCeiling()
    local manifest = self:GetManifest()
    if not manifest or type(manifest.recipes[mapBasename(game.GetMap())]) ~= "table" then return nil end
    return manifest.cameraVector.z - skyRoomClearance
end

// Returns world bounds with the maximum lowered below the skybox room, so world-space traces and captures
// (foliage debris, puddles, snow cover, the local map) never reach the room's floor or its models.
function Skybox:ClampWorldMaximum(maximum)
    local ceiling = maximum and self:GetPlayableCeiling()
    if not ceiling or maximum.z <= ceiling then return maximum end
    return Vector(maximum.x, maximum.y, ceiling)
end

// Neighbour radius chosen by the quality setting, capped at what the manifest was built for.
function Skybox:GetRadius(manifest)
    local detail = math.floor(getConVarNumber("zombiesim_sky_detail", 2))
    return math.Clamp(detail, 0, manifest and manifest.neighbourRadius or 0)
end

// Distance (world units) at which the skybox fog is opaque and the horizon wall stands.
function Skybox:GetFogEdge(manifest)
    return (math.max(self:GetRadius(manifest), 1) + 0.5) * manifest.cellSpan * fogEdgeFraction
end

local function resolveCurrentCell()
    local player = LocalPlayer()
    if not IsValid(player) or not ZM_World:IsLoaded() then return nil, "world not ready" end
    local cellX = player.CellX
    local cellY = player.CellY
    if cellX == nil then cellX = player:GetNWInt("CellX", 0) end
    if cellY == nil then cellY = player:GetNWInt("CellY", 0) end
    local gridX, gridY = ZM_World:GetGridCoordinates(cellX, cellY)
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    if not cell then return nil, "no cell at " .. tostring(cellX) .. "," .. tostring(cellY) end
    if mapBasename(cell.map) ~= mapBasename(game.GetMap()) then
        return nil, "loaded map is not the player's cell"
    end
    return cell, nil, gridX, gridY
end

// Rebuilds the neighbour model placements whenever the cell, profile, or detail radius changes.
function Skybox:Refresh()
    local manifest = self:GetManifest()
    local stats = self.Stats
    if not manifest then
        stats.state = self.ManifestError or "no manifest"
        self:RemoveModels()
        self.PlacementKey = nil
        return nil
    end
    local cell, reason, gridX, gridY = resolveCurrentCell()
    if not cell then
        stats.state = reason
        self:RemoveModels()
        self.PlacementKey = nil
        return nil
    end
    local radius = self:GetRadius(manifest)
    local key = table.concat({ tostring(self.ManifestProfile), gridX, gridY, radius }, ":")
    stats.state = "ready"
    if key == self.PlacementKey then return manifest end

    self:RemoveModels()
    self.PlacementKey = key
    stats.grid = gridX .. "," .. gridY
    stats.radius = radius
    stats.neighbourCells = 0
    stats.missingRecipes = 0
    stats.missingModels = 0
    stats.missingSnowModels = 0
    stats.missingDetailModels = 0
    stats.firstModelCheck = nil
    local scale = manifest.scale
    for dy = -radius, radius do
        for dx = -radius, radius do
            local neighbour = (dx ~= 0 or dy ~= 0) and ZM_World:GetCell(gridX + dx, gridY + dy) or nil
            if neighbour then
                stats.neighbourCells = stats.neighbourCells + 1
                local models = manifest.recipes[mapBasename(neighbour.map)]
                if type(models) ~= "table" then
                    stats.missingRecipes = stats.missingRecipes + 1
                else
                    // Grid north (y - 1) is +Y in Hammer space.
                    local origin = manifest.cameraVector + Vector(dx * manifest.cellSpan, -dy * manifest.cellSpan, 0) / scale
                    for _, modelPath in ipairs(models) do
                        // util.IsValidModel reports false on the client for these gamemode-content models
                        // even though ClientsideModel loads them, so only require the file to exist.
                        local entity, onDisk = createSkyModel(modelPath, origin)
                        if not stats.firstModelCheck then
                            stats.firstModelCheck = string.format("%s exists=%s entity=%s", modelPath, tostring(onDisk), tostring(IsValid(entity)))
                        end
                        if entity then
                            table.insert(self.Placements, { entity = entity, dx = dx, dy = dy })
                        else
                            stats.missingModels = stats.missingModels + 1
                        end
                    end
                    local snowModels = type(manifest.snow) == "table" and manifest.snow[mapBasename(neighbour.map)] or nil
                    for _, modelPath in ipairs(type(snowModels) == "table" and snowModels or {}) do
                        local entity = createSkyModel(modelPath, origin)
                        if entity then
                            table.insert(self.SnowPlacements, { entity = entity, dx = dx, dy = dy })
                        else
                            stats.missingSnowModels = stats.missingSnowModels + 1
                        end
                    end
                    local detail = type(manifest.detail) == "table" and type(manifest.detail.recipes) == "table" and
                        manifest.detail.recipes[mapBasename(neighbour.map)] or nil
                    if type(detail) == "table" then self:AddNeighbourDetail(manifest, detail, origin, gridX + dx, gridY + dy) end
                end
            end
        end
    end
    stats.placements = #self.Placements
    stats.snowPlacements = #self.SnowPlacements
    // The sky eye stays near the sky camera, so priority from the camera is a stable per-cell draw order.
    table.sort(self.DetailProps, function(a, b) return a.priority > b.priority end)
    stats.detailProps = #self.DetailProps
    stats.fires = #self.Fires
    self:BuildCoast(manifest, gridX, gridY, radius)
    return manifest
end

function Skybox:DestroyCoast()
    for _, key in ipairs({ "CoastSeaMesh", "CoastWallMesh", "CoastFoamMesh" }) do
        if self[key] then self[key]:Destroy() end
        self[key] = nil
    end
end

local function emitQuad(a, b, c, d, red, green, blue, alphaA, alphaB, uA, uB, vA, vB)
    mesh.Position(a) mesh.Color(red, green, blue, alphaA) mesh.TexCoord(0, uA, vA) mesh.AdvanceVertex()
    mesh.Position(b) mesh.Color(red, green, blue, alphaA) mesh.TexCoord(0, uB, vA) mesh.AdvanceVertex()
    mesh.Position(c) mesh.Color(red, green, blue, alphaB) mesh.TexCoord(0, uB, vB) mesh.AdvanceVertex()
    mesh.Position(d) mesh.Color(red, green, blue, alphaB) mesh.TexCoord(0, uA, vB) mesh.AdvanceVertex()
end

// Slots beyond the world grid become sea: a concrete sea wall on every city edge that faces it, a foam line at its
// foot, and open water out past the horizon wall. Built in absolute sky coordinates whenever the placement changes.
function Skybox:BuildCoast(manifest, gridX, gridY, radius)
    self:DestroyCoast()
    local stats = self.Stats
    stats.coastSeaQuads, stats.coastWallQuads, stats.coastFoamQuads = 0, 0, 0
    if radius < 1 then return end

    local span = manifest.cellSpan / manifest.scale
    local half = span * 0.5
    local camera = manifest.cameraVector
    local reach = radius + 1
    local land = {}
    local function isLand(dx, dy)
        local key = dx .. ":" .. dy
        if land[key] == nil then
            land[key] = (dx == 0 and dy == 0) or ZM_World:GetCell(gridX + dx, gridY + dy) ~= nil
        end
        return land[key]
    end
    local seaSlots, landSlots, edges = {}, {}, {}
    // Grid east (dx + 1) is +X; grid north (dy - 1) is +Y in Hammer space.
    local sides = { { 1, 0, 1, 0 }, { -1, 0, -1, 0 }, { 0, -1, 0, 1 }, { 0, 1, 0, -1 } }
    for dy = -reach - 1, reach + 1 do
        for dx = -reach - 1, reach + 1 do
            local cx, cy = camera.x + dx * span, camera.y - dy * span
            if isLand(dx, dy) then
                table.insert(landSlots, { cx, cy })
                if math.abs(dx) <= reach and math.abs(dy) <= reach then
                    for _, side in ipairs(sides) do
                        if not isLand(dx + side[1], dy + side[2]) then
                            table.insert(edges, { x = cx + side[3] * half, y = cy + side[4] * half, nx = side[3], ny = side[4] })
                        end
                    end
                end
            elseif math.abs(dx) <= reach and math.abs(dy) <= reach then
                table.insert(seaSlots, { cx, cy })
            end
        end
    end
    if #seaSlots == 0 then return end

    // Shallow water is lighter near the shore; vertex shade is tinted by the material colour each frame.
    local function shoreShade(px, py)
        local nearest = span
        for _, slot in ipairs(landSlots) do
            local ox = math.max(math.abs(px - slot[1]) - half, 0)
            local oy = math.max(math.abs(py - slot[2]) - half, 0)
            nearest = math.min(nearest, math.sqrt(ox * ox + oy * oy))
        end
        return Lerp(smoothstep(0, span * 0.6, nearest), 255, 150)
    end
    local seaZ = camera.z + coastSeaLevel
    local step = span / coastSeaSubdivisions
    local shades = {}
    for slotIndex, slot in ipairs(seaSlots) do
        local grid = {}
        for row = 0, coastSeaSubdivisions do
            grid[row] = {}
            for column = 0, coastSeaSubdivisions do
                grid[row][column] = shoreShade(slot[1] - half + column * step, slot[2] - half + row * step)
            end
        end
        shades[slotIndex] = grid
    end

    local a, b, c, d = Vector(), Vector(), Vector(), Vector()
    local seaQuads = #seaSlots * coastSeaSubdivisions * coastSeaSubdivisions
    local seaMesh = Mesh()
    mesh.Begin(seaMesh, MATERIAL_QUADS, seaQuads)
    for slotIndex, slot in ipairs(seaSlots) do
        local grid = shades[slotIndex]
        for row = 0, coastSeaSubdivisions - 1 do
            for column = 0, coastSeaSubdivisions - 1 do
                local x0, y0 = slot[1] - half + column * step, slot[2] - half + row * step
                a:SetUnpacked(x0, y0, seaZ)
                b:SetUnpacked(x0 + step, y0, seaZ)
                c:SetUnpacked(x0 + step, y0 + step, seaZ)
                d:SetUnpacked(x0, y0 + step, seaZ)
                local s1, s2, s3, s4 = grid[row][column], grid[row][column + 1], grid[row + 1][column + 1], grid[row + 1][column]
                mesh.Position(a) mesh.Color(s1, s1, s1, 255) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
                mesh.Position(b) mesh.Color(s2, s2, s2, 255) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
                mesh.Position(c) mesh.Color(s3, s3, s3, 255) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
                mesh.Position(d) mesh.Color(s4, s4, s4, 255) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
            end
        end
    end
    mesh.End()
    self.CoastSeaMesh = seaMesh
    stats.coastSeaQuads = seaQuads
    if #edges == 0 then return end

    local topZ, footZ = camera.z + coastStreetHeight, seaZ - 0.5
    local foamZ = seaZ + 0.15
    local wallMesh = Mesh()
    mesh.Begin(wallMesh, MATERIAL_QUADS, #edges)
    for _, edge in ipairs(edges) do
        // The edge runs perpendicular to its outward normal.
        local tx, ty = -edge.ny * half, edge.nx * half
        a:SetUnpacked(edge.x - tx, edge.y - ty, topZ)
        b:SetUnpacked(edge.x + tx, edge.y + ty, topZ)
        c:SetUnpacked(edge.x + tx, edge.y + ty, footZ)
        d:SetUnpacked(edge.x - tx, edge.y - ty, footZ)
        emitQuad(a, b, c, d, 255, 255, 255, 255, 255, 0, span / 8, 0, (topZ - footZ) / 8)
    end
    mesh.End()
    self.CoastWallMesh = wallMesh

    local foamMesh = Mesh()
    mesh.Begin(foamMesh, MATERIAL_QUADS, #edges)
    for _, edge in ipairs(edges) do
        local tx, ty = -edge.ny * half, edge.nx * half
        local ox, oy = edge.nx * coastFoamWidth, edge.ny * coastFoamWidth
        a:SetUnpacked(edge.x - tx, edge.y - ty, foamZ)
        b:SetUnpacked(edge.x + tx, edge.y + ty, foamZ)
        c:SetUnpacked(edge.x + tx + ox, edge.y + ty + oy, foamZ)
        d:SetUnpacked(edge.x - tx + ox, edge.y - ty + oy, foamZ)
        emitQuad(a, b, c, d, 255, 255, 255, 255, 0, 0, span / 12, 0, 1)
    end
    mesh.End()
    self.CoastFoamMesh = foamMesh
    stats.coastWallQuads = #edges
    stats.coastFoamQuads = #edges
end

// Sea, sea wall, and foam colours follow the atmosphere so the coast sits in the same light as the fog.
function Skybox:DrawCoast(fogColor)
    if not self.CoastSeaMesh then return end
    local red, green, blue = (fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255
    local brightness = math.Clamp((red * 0.3 + green * 0.59 + blue * 0.11) * 1.6, 0.25, 1)
    cam.PushModelMatrix(identityMatrix)
    coastColor:SetUnpacked(Lerp(0.45, red, 0.13 * brightness), Lerp(0.45, green, 0.23 * brightness), Lerp(0.45, blue, 0.27 * brightness))
    seaMaterial:SetVector("$color", coastColor)
    render.SetMaterial(seaMaterial)
    self.CoastSeaMesh:Draw()
    if self.CoastWallMesh then
        coastColor:SetUnpacked(Lerp(0.3, red, 0.62) * brightness, Lerp(0.3, green, 0.6) * brightness, Lerp(0.3, blue, 0.57) * brightness)
        seaWallMaterial:SetVector("$color", coastColor)
        render.SetMaterial(seaWallMaterial)
        self.CoastWallMesh:Draw()
    end
    if self.CoastFoamMesh then
        coastColor:SetUnpacked(0.92 * brightness, 0.94 * brightness, 0.96 * brightness)
        foamMaterial:SetVector("$color", coastColor)
        foamMaterial:SetFloat("$alpha", 0.4 + 0.15 * math.sin(CurTime() * 0.8))
        render.SetMaterial(foamMaterial)
        self.CoastFoamMesh:Draw()
    end
    cam.PopModelMatrix()
    self.Stats.coastDraws = (self.Stats.coastDraws or 0) + 1
end

// Builds the horizon wall around the origin, in sky units; it is translated to the sky eye when drawn.
function Skybox:BuildDome(radius)
    if self.DomeMesh and self.DomeRadius == radius then return end
    if self.DomeMesh then self.DomeMesh:Destroy() end
    self.DomeMesh = nil
    self.DomeRadius = radius

    local quads = domeSegments * (#domeRings - 1)
    if quads <= 0 then return end
    local ringZ = {}
    for index, ring in ipairs(domeRings) do
        ringZ[index] = radius * math.tan(math.rad(ring.elevation))
    end
    local corners = {}
    for segment = 0, domeSegments do
        local angle = segment / domeSegments * math.pi * 2
        corners[segment] = { math.cos(angle) * radius, math.sin(angle) * radius }
    end
    local position = Vector()
    local domeMesh = Mesh()
    mesh.Begin(domeMesh, MATERIAL_QUADS, quads)
    for ringIndex = 1, #domeRings - 1 do
        local lowZ, highZ = ringZ[ringIndex], ringZ[ringIndex + 1]
        local lowAlpha = domeRings[ringIndex].alpha * 255
        local highAlpha = domeRings[ringIndex + 1].alpha * 255
        for segment = 0, domeSegments - 1 do
            local a, b = corners[segment], corners[segment + 1]
            position:SetUnpacked(a[1], a[2], lowZ)
            mesh.Position(position) mesh.Color(255, 255, 255, lowAlpha) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
            position:SetUnpacked(b[1], b[2], lowZ)
            mesh.Position(position) mesh.Color(255, 255, 255, lowAlpha) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
            position:SetUnpacked(b[1], b[2], highZ)
            mesh.Position(position) mesh.Color(255, 255, 255, highAlpha) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
            position:SetUnpacked(a[1], a[2], highZ)
            mesh.Position(position) mesh.Color(255, 255, 255, highAlpha) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
        end
    end
    mesh.End()
    self.DomeMesh = domeMesh
    self.Stats.domeQuads = quads
end

// Deterministic cloud clusters spread over a square that wraps around the sky camera.
function Skybox:BuildClouds(fieldHalf)
    if self.Clouds and self.CloudFieldHalf == fieldHalf then return end
    self.CloudFieldHalf = fieldHalf
    local state = cloudSeed
    local function random()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
    local clouds = {}
    for index = 1, cloudClusterCount do
        local cluster = {
            x = (random() * 2 - 1) * fieldHalf,
            y = (random() * 2 - 1) * fieldHalf,
            z = cloudBaseHeight + random() * cloudHeightRange,
            threshold = random(),
            shade = 0.85 + random() * 0.15,
            puffs = {}
        }
        local spread = 40 + random() * 60
        for puff = 1, 4 + math.floor(random() * 5) do
            local size = 45 + random() * 75
            local rotation = random() * math.pi * 2
            table.insert(cluster.puffs, {
                x = (random() * 2 - 1) * spread,
                y = (random() * 2 - 1) * spread * 0.7,
                z = (random() * 2 - 1) * 10,
                cos = math.cos(rotation) * size,
                sin = math.sin(rotation) * size
            })
        end
        clouds[index] = cluster
    end
    self.Clouds = clouds
    self.CloudOrder = {}
end

// Weather-driven cloud cover (0..1), eased so weather changes roll in rather than pop.
function Skybox:UpdateCloudCover()
    local atmosphere = ZM_Atmosphere
    local weather = atmosphere and atmosphere.Weather or "clear"
    local storm = atmosphere and atmosphere.StormIntensity or 0
    local target = weather == "rain" and 0.85 or weather == "snow" and 0.75 or 0.38
    target = math.Clamp(target + storm * 0.3, 0, 1)
    local now = RealTime()
    local delta = math.Clamp(now - (self.CloudCoverTime or now), 0, 1)
    self.CloudCoverTime = now
    self.CloudCover = self.CloudCover and math.Approach(self.CloudCover, target, delta * 0.05) or target
    self.CloudStorm = storm
    return self.CloudCover
end

local cloudVertex = Vector()

local function compareCloudDistance(a, b)
    return a.distance > b.distance
end

function Skybox:DrawClouds(manifest, skyEye, fogColor, fogStart, fogEnd)
    local fieldHalf = self:GetFogEdge(manifest) / manifest.scale * 1.15
    self:BuildClouds(fieldHalf)
    local cover = self:UpdateCloudCover()
    local storm = self.CloudStorm or 0
    local camera = manifest.cameraVector
    local drift = CurTime() * cloudDriftSpeed
    local span = fieldHalf * 2
    local red, green, blue = fogColor[1] or 128, fogColor[2] or 128, fogColor[3] or 128
    // Clouds are lit from above: fog colour lifted toward white, dimmed in storms and in dark atmospheres.
    local luminance = (red * 0.3 + green * 0.59 + blue * 0.11) / 255
    local brightness = math.Clamp(luminance * 1.7, 0.3, 1) * (1 - 0.45 * storm)
    local baseRed = Lerp(0.5, red, 245 * brightness)
    local baseGreen = Lerp(0.5, green, 245 * brightness)
    local baseBlue = Lerp(0.5, blue, 248 * brightness)
    local order = self.CloudOrder
    local count = 0
    local quads = 0
    for _, cluster in ipairs(self.Clouds) do
        local visibility = math.Clamp((cover - cluster.threshold) / 0.12, 0, 1)
        if visibility > 0 then
            // Wrap the drifting cluster into the field square centred on the sky camera.
            local x = (cluster.x + drift + fieldHalf) % span - fieldHalf + camera.x
            local y = (cluster.y + drift * 0.35 + fieldHalf) % span - fieldHalf + camera.y
            local z = camera.z + cluster.z
            local dx, dy, dz = x - skyEye.x, y - skyEye.y, z - skyEye.z
            local horizontal = math.sqrt(dx * dx + dy * dy)
            local edge = 1 - smoothstep(fieldHalf * 0.55, fieldHalf * 0.95, horizontal)
            local distance = math.sqrt(horizontal * horizontal + dz * dz)
            local fogAmount = math.Clamp((distance - fogStart) / math.max(fogEnd - fogStart, 1), 0, 1)
            // Clouds sink into the horizon wall rather than drawing over it.
            local elevation = smoothstep(0.03, 0.17, dz / math.max(distance, 1))
            local alpha = visibility * edge * elevation * (1 - 0.65 * fogAmount) * (0.55 + 0.35 * cover) * 255
            if alpha > 1 then
                count = count + 1
                local entry = order[count] or {}
                order[count] = entry
                entry.cluster = cluster
                entry.x, entry.y, entry.z = x, y, z
                entry.distance = distance
                entry.alpha = alpha
                entry.red = Lerp(fogAmount, baseRed * cluster.shade, red)
                entry.green = Lerp(fogAmount, baseGreen * cluster.shade, green)
                entry.blue = Lerp(fogAmount, baseBlue * cluster.shade, blue)
                quads = quads + #cluster.puffs
            end
        end
    end
    for index = count + 1, #order do order[index] = nil end
    self.Stats.cloudClusters = count
    self.Stats.cloudQuads = quads
    self.Stats.cloudCover = cover
    if quads <= 0 then return end
    table.sort(order, compareCloudDistance)

    render.SetMaterial(cloudMaterial)
    mesh.Begin(MATERIAL_QUADS, quads)
    for index = 1, count do
        local entry = order[index]
        local r, g, b, a = entry.red, entry.green, entry.blue, entry.alpha
        for _, puff in ipairs(entry.cluster.puffs) do
            local px, py, pz = entry.x + puff.x, entry.y + puff.y, entry.z + puff.z
            local c, s = puff.cos, puff.sin
            cloudVertex:SetUnpacked(px - c + s, py - s - c, pz)
            mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
            cloudVertex:SetUnpacked(px + c + s, py + s - c, pz)
            mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
            cloudVertex:SetUnpacked(px + c - s, py + s + c, pz)
            mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
            cloudVertex:SetUnpacked(px - c - s, py - s + c, pz)
            mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
        end
    end
    mesh.End()
end

// Called from cl_atmosphere's SetupSkyboxFog with the world fog; returns linear sky fog (world units) that matches the
// world fog at the cell edge and reaches full density at the horizon wall.
function Skybox:GetSkyboxFog(settings)
    local manifest = self.Manifest
    if not settings or not manifest or self.Stats.state ~= "ready" then return settings end
    local boundary = manifest.cellSpan * 0.5
    local edge = self:GetFogEdge(manifest)
    local range = math.max(settings.finish - settings.start, 1)
    local boundaryDensity = settings.maxDensity * math.Clamp((boundary - settings.start) / range, 0, 1)
    local result = self.FogResult
    result.color = settings.color
    result.maxDensity = 1
    result.finish = edge
    if boundaryDensity >= 0.98 then
        result.start = 0
        result.finish = boundary
    else
        result.start = math.max(boundary - boundaryDensity * (edge - boundary) / (1 - boundaryDensity), -4 * edge)
    end
    self.Stats.fogStart = result.start
    self.Stats.fogEnd = result.finish
    return result
end

// Traces the ring of sample points once per map; only their lighting is re-read afterwards.
function Skybox:CollectLightSamples()
    local mapName = game.GetMap()
    if self.LightSampleMap == mapName then return self.LightSamples end
    local world = game.GetWorld()
    if not world or world == NULL or not world:IsWorld() then return nil end
    local minimum, maximum = world:GetRenderBounds()
    maximum = self:ClampWorldMaximum(maximum)
    if not minimum or not maximum then return nil end
    self.LightSampleMap = mapName
    self.LightSamples = {}
    local minX, maxX = minimum.x + lightSampleInset, maximum.x - lightSampleInset
    local minY, maxY = minimum.y + lightSampleInset, maximum.y - lightSampleInset
    if maxX <= minX or maxY <= minY then return self.LightSamples end
    local points, rejects = {}, {}
    for x = minX, maxX, lightSampleStep do
        points[#points + 1] = { x, minY }
        points[#points + 1] = { x, maxY }
    end
    for y = minY + lightSampleStep, maxY - lightSampleStep, lightSampleStep do
        points[#points + 1] = { minX, y }
        points[#points + 1] = { maxX, y }
    end
    for _, point in ipairs(points) do
        local startZ, bottomZ = maximum.z - 16, minimum.z + 16
        local trace
        // The cell's own sky lid sits below the clamped bounds; step through sky brushes to the ground.
        for _ = 1, 4 do
            trace = util.TraceLine({
                start = Vector(point[1], point[2], startZ),
                endpos = Vector(point[1], point[2], bottomZ),
                mask = MASK_SOLID_BRUSHONLY
            })
            if trace.StartSolid and not trace.AllSolid then
                startZ = startZ + (bottomZ - startZ) * trace.FractionLeftSolid - 1
            elseif trace.Hit and trace.HitSky then
                startZ = trace.HitPos.z - 1
            else
                break
            end
        end
        local reason
        if trace.StartSolid then reason = "startSolid"
        elseif not trace.Hit then reason = "miss"
        elseif trace.HitSky then reason = "sky"
        elseif trace.HitNormal.z <= 0.7 then reason = "steep"
        end
        if reason then
            rejects[reason] = (rejects[reason] or 0) + 1
        else
            table.insert(self.LightSamples, trace.HitPos + trace.HitNormal * lightSampleLift)
        end
    end
    self.Stats.lightRejects = string.format("points %d startSolid %d miss %d sky %d steep %d top %.0f bottom %.0f",
        #points, rejects.startSolid or 0, rejects.miss or 0, rejects.sky or 0, rejects.steep or 0, maximum.z, minimum.z)
    return self.LightSamples
end

// Averages the playable cell's lighting per direction into the six-sided model lighting cube.
function Skybox:UpdateLighting()
    local samples = self:CollectLightSamples()
    local stats = self.Stats
    stats.lightSamples = samples and #samples or 0
    if not samples or #samples == 0 then
        self.LightCube = nil
        return nil
    end
    local now = RealTime()
    if self.LightCube and (self.LightCubeTime or 0) > now then return self.LightCube end
    self.LightCubeTime = now + lightRefreshSeconds
    local cube = self.LightCube or {}
    for index, direction in ipairs(lightDirections) do
        local total = Vector()
        for _, position in ipairs(samples) do
            total:Add(render.ComputeLighting(position, direction[2]))
        end
        total:Div(#samples)
        cube[index] = total
    end
    self.LightCube = cube
    stats.lightTop = string.format("%.3f %.3f %.3f", cube[5].x, cube[5].y, cube[5].z)
    stats.lightSide = string.format("%.3f %.3f %.3f", cube[1].x, cube[1].y, cube[1].z)
    return cube
end

CreateClientConVar("zombiesim_sky_light_scale", "0.2", false, false,
    "Brightness multiplier for matched skybox model lighting.", 0, 2)
local function applyLightCube(cube)
    local scale = getConVarNumber("zombiesim_sky_light_scale", 0.2)
    render.SuppressEngineLighting(true)
    for index, direction in ipairs(lightDirections) do
        local colour = cube[index]
        render.SetModelLighting(direction[1], colour.x * scale, colour.y * scale, colour.z * scale)
    end
end

// One shared, hidden model per detail prop type, scaled down to sky units; every placement re-poses it per draw.
function Skybox:GetDetailModel(manifest, index)
    local models = self.DetailModels
    local cached = models[index]
    if cached ~= nil then return cached or nil end
    local modelPath = manifest.detail.models and manifest.detail.models[index + 1]
    local entity = type(modelPath) == "string" and file.Exists(modelPath, "GAME") and ClientsideModel(modelPath, RENDERGROUP_OPAQUE) or nil
    if not IsValid(entity) then
        models[index] = false
        return nil
    end
    entity:SetNoDraw(true)
    entity:SetLOD(detailModelLod)
    local scaleMatrix = Matrix()
    scaleMatrix:Scale(Vector(1, 1, 1) / manifest.scale)
    entity:EnableMatrix("RenderMultiply", scaleMatrix)
    local model = {
        entity = entity,
        radius = math.max(entity:GetModelRadius() or 0, 1) / manifest.scale,
        // Generated wrecks are placed on the road surface, so lift their origin by the model's floor offset.
        lift = -entity:OBBMins().z / manifest.scale
    }
    models[index] = model
    return model
end

// Stable 0..1 hash per cell and candidate, so a neighbour's fires stay put as the player moves between cells.
local function fireHash(x, y, index, salt)
    local value = math.sin(x * 12.9898 + y * 78.233 + index * 37.719 + salt * 4.581) * 43758.5453
    return value - math.floor(value)
end

function Skybox:AddNeighbourDetail(manifest, detail, origin, cellX, cellY)
    local scale = manifest.scale
    for _, row in ipairs(type(detail.props) == "table" and detail.props or {}) do
        local model = self:GetDetailModel(manifest, tonumber(row[1]) or -1)
        if model then
            local kind = tonumber(row[9]) or 0
            local position = origin + Vector(tonumber(row[2]) or 0, tonumber(row[3]) or 0, tonumber(row[4]) or 0) / scale
            if kind == 2 then position.z = position.z + model.lift end
            // Wrecks count double: they are what breaks the long road sightlines.
            local radius = model.radius * (kind > 0 and 2 or 1)
            table.insert(self.DetailProps, {
                model = model,
                position = position,
                angles = Angle(tonumber(row[5]) or 0, tonumber(row[6]) or 0, tonumber(row[7]) or 0),
                skin = tonumber(row[8]) or 0,
                radius = radius,
                priority = radius / math.max(position:Distance(manifest.cameraVector), 1)
            })
        else
            self.Stats.missingDetailModels = (self.Stats.missingDetailModels or 0) + 1
        end
    end
    local burning = 0
    for index, row in ipairs(type(detail.fires) == "table" and detail.fires or {}) do
        local kind = tonumber(row[4]) == 2 and 2 or 1
        if burning < firesPerCell and #self.Fires < maxFires and fireHash(cellX, cellY, index, kind) < fireChance[kind] then
            burning = burning + 1
            local style = fireStyles[kind]
            local position = origin + Vector(tonumber(row[1]) or 0, tonumber(row[2]) or 0, tonumber(row[3]) or 0) / scale
            position.z = position.z + style.lift
            table.insert(self.Fires, { position = position, style = style, phase = fireHash(cellY, cellX, index, 9) })
        end
    end
end

local propForward = Vector()

function Skybox:DrawDetailProps(skyEye, maxDistance)
    local stats = self.Stats
    stats.frameProps = 0
    local density = getConVarNumber("zombiesim_sky_props", 1)
    local props = self.DetailProps
    if density <= 0 or not props or #props == 0 then return end
    local threshold = detailAngularThreshold
    local thresholdSqr = threshold * threshold
    local budget = math.floor(detailDrawBudget * math.Clamp(density, 0.1, 1))
    local maxDistanceSqr = maxDistance * maxDistance
    local forward = self.ViewForward or propForward
    local fx, fy, fz = forward.x, forward.y, forward.z
    local ex, ey, ez = skyEye.x, skyEye.y, skyEye.z
    local drawn = 0
    for _, prop in ipairs(props) do
        local position = prop.position
        local dx, dy, dz = position.x - ex, position.y - ey, position.z - ez
        local distanceSqr = dx * dx + dy * dy + dz * dz
        local radius = prop.radius
        if distanceSqr < maxDistanceSqr and radius * radius > thresholdSqr * distanceSqr and
            dx * fx + dy * fy + dz * fz > -radius then
            local entity = prop.model.entity
            if IsValid(entity) then
                entity:SetRenderOrigin(position)
                entity:SetRenderAngles(prop.angles)
                entity:SetSkin(prop.skin)
                entity:InvalidateBoneCache()
                entity:SetupBones()
                entity:DrawModel()
                drawn = drawn + 1
                if drawn >= budget then break end
            end
        end
    end
    stats.frameProps = drawn
end

local smokeOrder = {}
local billboardVertex = Vector()

local function compareSmokeDistance(a, b)
    return a.distance > b.distance
end

// Camera-facing quad rotated in the view plane; right/up are the view's unit vectors.
local function emitBillboard(x, y, z, size, cosine, sine, right, up, red, green, blue, alpha)
    local ax, ay, az = (right.x * cosine + up.x * sine) * size, (right.y * cosine + up.y * sine) * size, (right.z * cosine + up.z * sine) * size
    local bx, by, bz = (up.x * cosine - right.x * sine) * size, (up.y * cosine - right.y * sine) * size, (up.z * cosine - right.z * sine) * size
    billboardVertex:SetUnpacked(x - ax + bx, y - ay + by, z - az + bz)
    mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
    billboardVertex:SetUnpacked(x + ax + bx, y + ay + by, z + az + bz)
    mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
    billboardVertex:SetUnpacked(x + ax - bx, y + ay - by, z + az - bz)
    mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
    billboardVertex:SetUnpacked(x - ax - bx, y - ay - by, z - az - bz)
    mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
end

// Burning wrecks and rooftops: rising, spreading smoke plumes drifting with the clouds, flickering flames at the base.
function Skybox:DrawFires(skyEye)
    local stats = self.Stats
    stats.frameFires = 0
    stats.smokeQuads = 0
    stats.fireQuads = 0
    local fires = self.Fires
    local right, up = self.ViewRight, self.ViewUp
    if getConVarNumber("zombiesim_sky_fires", 1) <= 0 or not fires or #fires == 0 or not right or not up then return end
    local now = CurTime()
    local count = 0
    for fireIndex, fire in ipairs(fires) do
        local style = fire.style
        local base = fire.position
        for puff = 1, smokePuffs do
            local progress = (now / style.cycle + fire.phase + puff / smokePuffs) % 1
            local alpha = smoothstep(0, 0.12, progress) * (1 - progress) ^ 1.3 * 175
            if alpha > 2 then
                local spread = progress ^ 1.4 * style.drift
                local x = base.x + smokeDriftX * spread
                local y = base.y + smokeDriftY * spread
                local z = base.z + progress * style.rise
                count = count + 1
                local entry = smokeOrder[count] or {}
                smokeOrder[count] = entry
                local dx, dy, dz = x - skyEye.x, y - skyEye.y, z - skyEye.z
                local rotation = fire.phase * 6.283 + puff * 1.7 + progress * 1.4 * (fireIndex % 2 == 0 and 1 or -1)
                entry.x, entry.y, entry.z = x, y, z
                entry.distance = dx * dx + dy * dy + dz * dz
                entry.size = style.size + style.grow * progress ^ 0.8
                entry.cosine, entry.sine = math.cos(rotation), math.sin(rotation)
                entry.alpha = alpha
                // Thick black smoke low down, lifting to a paler grey as it thins out.
                entry.shade = 34 + 46 * progress
            end
        end
    end
    for index = count + 1, #smokeOrder do smokeOrder[index] = nil end
    stats.frameFires = #fires
    stats.smokeQuads = count

    // Flames first, so the base of the plume drifts over them.
    local flames = #fires * 3
    render.SetMaterial(glowMaterial)
    mesh.Begin(MATERIAL_QUADS, #fires)
    for _, fire in ipairs(fires) do
        local base = fire.position
        local flicker = 0.85 + 0.15 * math.sin(now * 7.3 + fire.phase * 40)
        emitBillboard(base.x, base.y, base.z, fire.style.flame * 2.6 * flicker, 1, 0, right, up, 255, 120, 40, 120 * flicker)
    end
    mesh.End()
    render.SetMaterial(fireMaterial)
    mesh.Begin(MATERIAL_QUADS, flames)
    for _, fire in ipairs(fires) do
        local base = fire.position
        local size = fire.style.flame
        for flame = 1, 3 do
            local wave = now * (5 + flame * 1.9) + fire.phase * 30 + flame * 2.1
            local flicker = 0.75 + 0.25 * math.sin(wave) * math.sin(wave * 0.61)
            local offset = (flame - 2) * size * 0.45
            emitBillboard(base.x + right.x * offset, base.y + right.y * offset, base.z + size * (0.35 + 0.25 * flame) * flicker,
                size * flicker * (1.15 - flame * 0.15), 1, 0, right, up, 255, 200, 140, 235)
        end
    end
    mesh.End()
    stats.fireQuads = flames + #fires
    if count <= 0 then return end
    table.sort(smokeOrder, compareSmokeDistance)
    render.SetMaterial(smokeMaterial)
    mesh.Begin(MATERIAL_QUADS, count)
    for index = 1, count do
        local entry = smokeOrder[index]
        local shade = entry.shade
        emitBillboard(entry.x, entry.y, entry.z, entry.size, entry.cosine, entry.sine, right, up, shade, shade * 0.97, shade * 0.94, entry.alpha)
    end
    mesh.End()
end

function Skybox:Draw()
    local stats = self.Stats
    stats.frameModels = 0
    if getConVarNumber("zombiesim_sky_detail", 2) <= 0 then
        stats.state = "disabled by zombiesim_sky_detail"
        return
    end
    local manifest = self:Refresh()
    if not manifest then return end

    local scale = manifest.scale
    local skyEye = self.SkyEye
    skyEye:Set(self.ViewOrigin)
    skyEye:Div(scale)
    skyEye:Add(manifest.cameraVector)
    local edge = self:GetFogEdge(manifest) / scale
    local lightCube = getConVarNumber("zombiesim_sky_matched_lighting", 1) > 0 and self:UpdateLighting() or nil
    stats.matchedLighting = lightCube ~= nil
    if lightCube then applyLightCube(lightCube) end
    for _, placement in ipairs(self.Placements) do
        if IsValid(placement.entity) then
            placement.entity:DrawModel()
            stats.frameModels = stats.frameModels + 1
        end
    end
    self:DrawDetailProps(skyEye, edge)
    // Settled snow fades in with the same snow-cover amount (and easing) as the playable cell's ground cover.
    local snowAmount = ZM_Atmosphere and ZM_Atmosphere.SnowCoverAmount or 0
    local snowFade = math.min(1, snowAmount * 3)
    local snowAlpha = snowFade * snowFade * (3 - 2 * snowFade)
    stats.snowAlpha = snowAlpha
    stats.frameSnowModels = 0
    if snowAlpha > 0.002 and #self.SnowPlacements > 0 then
        // The overlay sits only a hair above the surfaces it covers (a visible lift reads as a raised slab at the
        // playable cell's edge), so a window-space depth bias stops it z-fighting; the bias grows with distance in
        // world terms exactly as depth precision falls off. https://wiki.facepunch.com/gmod/render.DepthRange
        render.DepthRange(0, 1 - snowDepthBias)
        render.SetBlend(snowAlpha)
        for _, placement in ipairs(self.SnowPlacements) do
            if IsValid(placement.entity) then
                placement.entity:DrawModel()
                stats.frameSnowModels = stats.frameSnowModels + 1
            end
        end
        render.SetBlend(1)
        render.DepthRange(0, 1)
    end
    if lightCube then render.SuppressEngineLighting(false) end

    local settings = ZM_Atmosphere and ZM_Atmosphere:GetFogSettings()
    local fogColor = settings and settings.color or defaultFogColor
    self:DrawCoast(fogColor)
    local skyFog = self:GetSkyboxFog(settings)
    self:BuildDome(edge)
    if self.DomeMesh then
        domeColor:SetUnpacked((fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255)
        domeMaterial:SetVector("$color", domeColor)
        domeMatrix:SetTranslation(skyEye)
        cam.PushModelMatrix(domeMatrix)
        render.SetMaterial(domeMaterial)
        self.DomeMesh:Draw()
        cam.PopModelMatrix()
        stats.domeDraws = (stats.domeDraws or 0) + 1
    end
    self:DrawFires(skyEye)
    if getConVarNumber("zombiesim_sky_clouds", 1) > 0 then
        local fogStart = (skyFog and skyFog.start or 0) / scale
        local fogEnd = (skyFog and skyFog.finish or edge * scale) / scale
        self:DrawClouds(manifest, skyEye, fogColor, fogStart, fogEnd)
    else
        stats.cloudQuads = 0
    end
    stats.lastDraw = RealTime()
    stats.draws = (stats.draws or 0) + 1
end

function Skybox:GetDiagnosticSnapshot()
    local stats = self.Stats
    local manifest = self.Manifest
    return {
        state = stats.state,
        profile = self.ManifestProfile,
        manifestError = self.ManifestError,
        recipes = manifest and manifest.recipeCount,
        scale = manifest and manifest.scale,
        grid = stats.grid,
        radius = stats.radius,
        neighbourCells = stats.neighbourCells,
        placements = stats.placements,
        missingRecipes = stats.missingRecipes,
        missingModels = stats.missingModels,
        firstModelCheck = stats.firstModelCheck,
        frameModels = stats.frameModels,
        snowPlacements = stats.snowPlacements,
        missingSnowModels = stats.missingSnowModels,
        frameSnowModels = stats.frameSnowModels,
        snowAlpha = stats.snowAlpha,
        matchedLighting = stats.matchedLighting,
        lightSamples = stats.lightSamples,
        lightRejects = stats.lightRejects,
        lightTop = stats.lightTop,
        lightSide = stats.lightSide,
        draws = stats.draws,
        domeDraws = stats.domeDraws,
        domeQuads = stats.domeQuads,
        cloudClusters = stats.cloudClusters,
        cloudQuads = stats.cloudQuads,
        cloudCover = stats.cloudCover,
        fogStart = stats.fogStart,
        fogEnd = stats.fogEnd,
        lastDrawAge = stats.lastDraw and (RealTime() - stats.lastDraw) or nil,
        domeMaterialError = domeMaterial:IsError(),
        cloudMaterialError = cloudMaterial:IsError(),
        cloudTextureWidth = cloudMaterial:GetTexture("$basetexture") and cloudMaterial:GetTexture("$basetexture"):Width() or 0,
        coastSeaQuads = stats.coastSeaQuads,
        coastWallQuads = stats.coastWallQuads,
        coastFoamQuads = stats.coastFoamQuads,
        coastDraws = stats.coastDraws,
        seaMaterialError = seaMaterial:IsError(),
        seaWallMaterialError = seaWallMaterial:IsError(),
        seaWallTextureWidth = seaWallMaterial:GetTexture("$basetexture") and seaWallMaterial:GetTexture("$basetexture"):Width() or 0,
        foamMaterialError = foamMaterial:IsError(),
        detailProps = stats.detailProps,
        missingDetailModels = stats.missingDetailModels,
        detailModelTypes = table.Count(self.DetailModels or {}),
        frameProps = stats.frameProps,
        fires = stats.fires,
        frameFires = stats.frameFires,
        smokeQuads = stats.smokeQuads,
        fireQuads = stats.fireQuads,
        smokeMaterialError = smokeMaterial:IsError(),
        fireMaterialError = fireMaterial:IsError(),
        glowMaterialError = glowMaterial:IsError(),
        fireTextureWidth = fireMaterial:GetTexture("$basetexture") and fireMaterial:GetTexture("$basetexture"):Width() or 0,
        glowTextureWidth = glowMaterial:GetTexture("$basetexture") and glowMaterial:GetTexture("$basetexture"):Width() or 0
    }
end

// The sky view origin is the sky camera plus the main view origin divided by the skybox scale; the view basis
// orients the skybox's smoke and flame billboards.
hook.Add("RenderScene", "ZM.Skybox.ViewOrigin", function(origin, angles)
    Skybox.ViewOrigin:Set(origin)
    if angles then
        Skybox.ViewForward = angles:Forward()
        Skybox.ViewRight = angles:Right()
        Skybox.ViewUp = angles:Up()
    end
end)

hook.Add("PostDrawOpaqueRenderables", "ZM.Skybox.Draw", function(drawingDepth, _, drawing3DSkybox)
    if drawingDepth or not drawing3DSkybox then return end
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    Skybox:Draw()
end)

hook.Add("ShutDown", "ZM.Skybox.Cleanup", function()
    Skybox:RemoveModels()
    Skybox:DestroyCoast()
end)

concommand.Add("zombiesim_skybox_status", function()
    local snapshot = Skybox:GetDiagnosticSnapshot()
    local keys = table.GetKeys(snapshot)
    table.sort(keys)
    for _, key in ipairs(keys) do
        print(string.format("[ZombieSim] Skybox %s = %s", key, tostring(snapshot[key])))
    end
end)

// A hot reload must not leave the previous load's hidden models behind.
Skybox:RemoveModels()
Skybox:DestroyCoast()
Skybox.PlacementKey = nil
Skybox.ManifestProfile = nil
if Skybox.DomeMesh then Skybox.DomeMesh:Destroy() end
Skybox.DomeMesh = nil
Skybox.Clouds = nil
Skybox.LightSampleMap = nil
Skybox.LightCube = nil
