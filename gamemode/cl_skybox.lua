// Runtime 3D skybox. Every city recipe carries the same sky_camera room; this module draws the current cell's
// neighbouring recipe models inside it, then a fog-coloured horizon wall and a drifting cloud deck. Models and the
// manifest come from bin/build_skybox_models.ps1, so cells that share a recipe still show their own surroundings.
ZM_Skybox = ZM_Skybox or {}
local Skybox = ZM_Skybox

// The fog becomes opaque slightly inside the outermost modelled ring so its far edge is never seen.
local fogEdgeFraction = 0.9
// Distant-tower fog: fog colours at or below the dark luminance keep the plain long-range tower ramp; at or above
// the pale luminance the towers share the nearby sky fog curve so they match the fogged neighbour cells.
local towerFogDarkLuminance = 0.45
local towerFogPaleLuminance = 0.7
// Coastline (sky units relative to the sky camera): tile street surfaces sit at +32 world units (+2 sky units).
// The shore is a height field over sea slots driven by distance to land, so beaches, rocks, and foam stay seam-free
// around corners; noise uses world-grid coordinates so the shore keeps its shape as the player changes cells.
local coast = {
    streetHeight = 2,
    seaLevel = -3,
    beachWidth = 40,
    duneHeight = 4,
    shelfSlope = 0.05,
    bandWidth = 170,
    terrainDivisions = 42,
    waterDivisions = 32,
    chunkQuads = 10000,
    foamDepth = 5,
    waveDepthLength = 2.4,
    wavePeriod = 7,
    rippleTile = 56,
    textureSize = 256,
    texturesReady = false,
    vertex = Vector(),
    textureMatrix = Matrix(),
    textureAngle = Angle(),
    textureScale = Vector(1, 1, 1),
    textureOffset = Vector()
}
local function coastTarget(name)
    return GetRenderTargetEx(name, coast.textureSize, coast.textureSize, RT_SIZE_LITERAL or 8,
        MATERIAL_RT_DEPTH_NONE or 2, 0, 0, IMAGE_FORMAT_RGBA8888 or 0)
end
coast.foamTexture = coastTarget("zombiesim_skybox_foam_rt_v1")
coast.rippleTexture = coastTarget("zombiesim_skybox_ripple_rt_v1")
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
// The coast is fogged with the rest of the sky pass so it fades into the horizon wall. Water hue comes from vertex
// colours (shallow turquoise to deep blue); ripples and breaking foam are additive procedural render targets.
local seaMaterial = CreateMaterial("zombiesim_skybox_sea_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
// Matches the sand layer of the authored ocean edge blend (nature/blendrocksand004a: rockfloor005a + sandfloor009a).
coast.sandMaterial = CreateMaterial("zombiesim_skybox_sand_v2", "UnlitGeneric", {
    ["$basetexture"] = "nature/sandfloor009a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
coast.rockMaterial = CreateMaterial("zombiesim_skybox_rock_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/rockfloor005a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
coast.embankmentMaterial = CreateMaterial("zombiesim_skybox_embankment_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/cliffface002a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
local foamMaterial = CreateMaterial("zombiesim_skybox_foam_v2", "UnlitGeneric", {
    ["$basetexture"] = coast.foamTexture:GetName(),
    ["$vertexcolor"] = 1,
    ["$additive"] = 1,
    ["$nocull"] = 1
})
coast.rippleMaterial = CreateMaterial("zombiesim_skybox_ripple_v1", "UnlitGeneric", {
    ["$basetexture"] = coast.rippleTexture:GetName(),
    ["$vertexcolor"] = 1,
    ["$additive"] = 1,
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
local tracerMaterial = CreateMaterial("zombiesim_skybox_tracer_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$additive"] = 1
})

Skybox.Stats = Skybox.Stats or {}
Skybox.ViewOrigin = Skybox.ViewOrigin or Vector()
Skybox.SkyEye = Skybox.SkyEye or Vector()
Skybox.TowerDirection = Skybox.TowerDirection or Vector()
Skybox.FogResult = Skybox.FogResult or { color = {} }
Skybox.TuningSettings = {
    { label = "Skybox fog amount", name = "zombiesim_sky_fog_amount", default = 0.8, minimum = 0, maximum = 2,
        tooltip = "Extra skybox fog beyond the playable-city fog. 0 matches the city fog exactly; 1 thickens halfway to opaque; 2 closes the horizon." },
    { label = "Skybox fog distance", name = "zombiesim_sky_fog_distance", default = 0.9, minimum = 0.5, maximum = 3,
        tooltip = "Scales how far skybox fog extends. Higher values give clearer nearby scenery; playable-city fog is unchanged." },
    { label = "Skybox horizon haze", name = "zombiesim_sky_horizon_haze", default = 0.5, minimum = 0, maximum = 1.5,
        tooltip = "Scales the horizon overlay above eye level. Lower values reveal silhouettes; 0 may expose scenery edges." },
    { label = "Skybox ground haze", name = "zombiesim_sky_haze_density", default = 1, minimum = 0, maximum = 2,
        tooltip = "Density of the low ground haze that distant buildings rise out of. Weather and radiation thicken it." },
    { label = "Distant tower fog", name = "zombiesim_sky_tower_fog", default = 0.8, minimum = 0, maximum = 1,
        tooltip = "Fog density for distant tower silhouettes. Pale atmosphere fog thickens this automatically; dark fog keeps it." },
    { label = "Skybox model brightness", name = "zombiesim_sky_light_scale", default = 0.25, minimum = 0, maximum = 2,
        tooltip = "Brightness of matched skybox model lighting. Requires matched lighting enabled." }
}
for _, setting in ipairs(Skybox.TuningSettings) do
    CreateClientConVar(setting.name, tostring(setting.default), true, false, setting.tooltip, setting.minimum, setting.maximum)
end

function Skybox:GetTuningSnapshot()
    local values = {}
    for _, setting in ipairs(self.TuningSettings) do
        values[setting.name] = math.Clamp(GetConVar(setting.name):GetFloat(), setting.minimum, setting.maximum)
    end
    values.zombiesim_sky_matched_lighting = GetConVar("zombiesim_sky_matched_lighting"):GetBool()
    return values
end

function Skybox:ResetTuning()
    for _, setting in ipairs(self.TuningSettings) do
        GetConVar(setting.name):SetString(tostring(setting.default))
    end
    GetConVar("zombiesim_sky_matched_lighting"):SetString("1")
end

local defaultFogColor = { 128, 128, 128 }
local snowDepthBias = 0.00005
CreateClientConVar("zombiesim_sky_matched_lighting", "1", true, false,
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

local function hashNoise(ix, iy)
    local value = math.sin(ix * 127.1 + iy * 311.7) * 43758.5453
    return value - math.floor(value)
end

// Smooth 0..1 value noise; `period` (cells) wraps the lattice so render-target textures tile.
local function valueNoise(x, y, period)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    local ax, bx, ay, by = ix, ix + 1, iy, iy + 1
    if period then ax, bx, ay, by = ax % period, bx % period, ay % period, by % period end
    local top = Lerp(fx, hashNoise(ax, ay), hashNoise(bx, ay))
    local bottom = Lerp(fx, hashNoise(ax, by), hashNoise(bx, by))
    return Lerp(fy, top, bottom)
end

// Greyscale, tiling foam and ripple textures drawn once into render targets. Foam rows hold a broken breaking-wave
// crest with a sharp shoreward front and a seaward wash; scrolling v moves the crests toward the waterline.
local function foamTexel(u, v)
    local tau = math.pi * 2
    local presence = smoothstep(0.3, 0.58, 0.5 + 0.25 * math.sin(tau * 3 * u + 1.3) + 0.15 * math.sin(tau * 7 * u + 0.4) + 0.1 * math.sin(tau * 13 * u + 2.2))
    local laterPresence = smoothstep(0.38, 0.62, 0.5 + 0.25 * math.sin(tau * 4 * u + 2.9) + 0.18 * math.sin(tau * 9 * u + 1.1))
    local crest = 0.08 + 0.03 * math.sin(tau * 2 * u + 0.7) + 0.012 * math.sin(tau * 9 * u)
    local function band(center, tail)
        local behind = (v - center) % 1
        if behind > 0.975 then return smoothstep(0.975, 1, behind) end
        return behind < tail and math.exp(-behind / (tail * 0.35)) or 0
    end
    local breakup = 0.4 + 0.6 * valueNoise(u * 16, v * 16, 16) * (0.6 + 0.4 * valueNoise(u * 64 + 3, v * 64 + 7, 64))
    return math.Clamp((presence * band(crest, 0.4) + 0.45 * laterPresence * band(crest + 0.5, 0.25)) * breakup * 1.3, 0, 1)
end

local function rippleTexel(u, v)
    local tau = math.pi * 2
    local wave = v * 5 + 0.12 * math.sin(tau * 3 * u + 0.5) + 0.06 * math.sin(tau * 7 * u + 1.7)
    local line = (0.5 + 0.5 * math.cos(tau * wave)) ^ 10
    local sparkle = valueNoise(u * 32 + 11, v * 32 + 5, 32) ^ 6
    return math.Clamp(line * smoothstep(0.35, 0.75, valueNoise(u * 8, v * 8, 8)) + 0.6 * sparkle, 0, 1)
end

hook.Add("PreRender", "ZM.Skybox.BuildWaterTextures", function()
    hook.Remove("PreRender", "ZM.Skybox.BuildWaterTextures")
    if not coast.foamTexture or not coast.rippleTexture then return end
    local size = coast.textureSize
    for _, target in ipairs({ { coast.foamTexture, foamTexel }, { coast.rippleTexture, rippleTexel } }) do
        render.PushRenderTarget(target[1])
        render.OverrideAlphaWriteEnable(true, true)
        render.Clear(0, 0, 0, 255)
        cam.Start2D()
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local value = math.floor(target[2]((x + 0.5) / size, (y + 0.5) / size) * 255 + 0.5)
                if value > 0 then
                    surface.SetDrawColor(value, value, value, 255)
                    surface.DrawRect(x, y, 1, 1)
                end
            end
        end
        cam.End2D()
        render.OverrideAlphaWriteEnable(false)
        render.PopRenderTarget()
    end
    coast.texturesReady = true
end)

function Skybox:RemoveModels()
    for _, list in ipairs({ self.Placements or {}, self.SnowPlacements or {}, self.TowerPlacements or {} }) do
        for _, placement in ipairs(list) do
            if IsValid(placement.entity) then placement.entity:Remove() end
        end
    end
    for _, model in pairs(self.DetailModels or {}) do
        if model and IsValid(model.entity) then model.entity:Remove() end
    end
    self.Placements = {}
    self.SnowPlacements = {}
    self.TowerPlacements = {}
    self.DetailModels = {}
    self.DetailProps = {}
    self.Fires = {}
    self.FacadeFires = {}
    self.FacadeAnchors = {}
    self.ActivitySites = {}
    self.ActivityVisible = {}
    self.EdgeFires = {}
    self.EdgeFireKey = nil
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
    if type(data) ~= "table" or
        (tonumber(data.scale) or 0) <= 0 or (tonumber(data.cellSpan) or 0) <= 0 or
        (tonumber(data.neighbourRadius) or 0) < 1 or type(origin) ~= "table" or type(data.recipes) ~= "table" then
        self.ManifestError = "invalid " .. path
        return nil
    end
    local worldData = ZM_World:GetData()
    local compatible, compatibilityError = ZM_SkyboxGeometry.ValidateManifest(data, worldData and worldData.world, worldData and worldData.cells)
    if not compatible then
        self.ManifestError = compatibilityError .. " (" .. path .. ")"
        ErrorNoHalt("[ZombieSim] " .. self.ManifestError .. "\n")
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
    local half = self.Manifest.cellSpan * 0.5
    return Vector(math.min(maximum.x, half), math.min(maximum.y, half), ceiling)
end

function Skybox:ClampWorldBounds(minimum, maximum)
    local ceiling = self:GetPlayableCeiling()
    if not ceiling or not minimum or not maximum then return minimum, maximum end
    local half = self.Manifest.cellSpan * 0.5
    return Vector(math.max(minimum.x, -half), math.max(minimum.y, -half), minimum.z),
        Vector(math.min(maximum.x, half), math.min(maximum.y, half), math.min(maximum.z, ceiling))
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
        self.GridX, self.GridY = nil, nil
        return nil
    end
    self.GridX, self.GridY = gridX, gridY
    local radius = self:GetRadius(manifest)
    local key = table.concat({ tostring(self.ManifestProfile), gridX, gridY, radius, manifest.cellSpan, manifest.schemaVersion, "activity-v4" }, ":")
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
            if neighbour and neighbour.empty ~= true then
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
                            table.insert(self.Placements, { entity = entity, origin = origin, dx = dx, dy = dy })
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
    stats.missingTowerModels = 0
    local skylineRadius = math.max(radius, tonumber(manifest.skylineRadius) or radius)
    local towerCandidates = {}
    if type(manifest.towers) == "table" then
        for y = gridY - skylineRadius, gridY + skylineRadius do
            for x = gridX - skylineRadius, gridX + skylineRadius do
                local dx, dy = x - gridX, y - gridY
                if math.max(math.abs(dx), math.abs(dy)) > radius then
                    local distant = ZM_World:GetCell(x, y)
                    local paths = distant and manifest.towers[mapBasename(distant.map)]
                    if type(paths) == "table" then
                        local origin = manifest.cameraVector + Vector(dx * manifest.cellSpan, -dy * manifest.cellSpan, 0) / scale
                        for _, path in ipairs(paths) do
                            towerCandidates[#towerCandidates + 1] = { path = path, origin = origin, distance = dx * dx + dy * dy, x = x, y = y }
                        end
                    end
                end
            end
        end
    end
    table.sort(towerCandidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.path < b.path
    end)
    local towerBudget = math.max(1, math.floor(tonumber(manifest.maxTowerModels) or 128))
    for index = 1, math.min(#towerCandidates, towerBudget) do
        local candidate = towerCandidates[index]
        local entity = createSkyModel(candidate.path, candidate.origin)
        if entity then
            table.insert(self.TowerPlacements, { entity = entity, origin = candidate.origin })
        else
            stats.missingTowerModels = stats.missingTowerModels + 1
        end
    end
    stats.towerCandidates = #towerCandidates
    stats.towerBudget = towerBudget
    stats.omittedTowerModels = math.max(0, #towerCandidates - towerBudget)
    stats.towerPlacements = #self.TowerPlacements
    stats.snowPlacements = #self.SnowPlacements
    // The sky eye stays near the sky camera, so priority from the camera is a stable per-cell draw order.
    table.sort(self.DetailProps, function(a, b) return a.priority > b.priority end)
    stats.detailProps = #self.DetailProps
    stats.fires = #self.Fires
    self:BuildActivitySites(manifest, gridX, gridY, radius)
    self:BuildCoast(manifest, gridX, gridY, radius)
    self.CurrentGridX, self.CurrentGridY = gridX, gridY
    self:BuildEdgeTerrain(manifest)
    return manifest
end

// Called from cl_atmosphere's SetupSkyboxFog with the world fog; returns linear sky fog (world units) that continues the
// world fog past the cell edge. The sky is never clearer than the playable cell: it starts at the world density at the
// boundary and rises to at least the world's maximum. Fog amount 0 holds the world maximum, 1 rises halfway to opaque,
// and 2 closes to opaque at the horizon.
function Skybox:GetSkyboxFog(settings)
    local manifest = self.Manifest
    if not settings or not manifest or self.Stats.state ~= "ready" then return settings end
    local boundary = ZM_SkyboxGeometry.GetFogBoundary(manifest)
    local edge = math.max(boundary + 1, self:GetFogEdge(manifest) *
        math.Clamp(getConVarNumber("zombiesim_sky_fog_distance", 0.9), 0.5, 3))
    local range = math.max(settings.finish - settings.start, 1)
    local worldMaximum = math.Clamp(settings.maxDensity, 0, 1)
    local boundaryDensity = worldMaximum * math.Clamp((boundary - settings.start) / range, 0, 1)
    local amount = math.Clamp(getConVarNumber("zombiesim_sky_fog_amount", 0.8), 0, 2)
    // Layered fog keeps the sky's Source fog gentle too; the haze shells carry the distance falloff instead.
    if settings.style == "layered" then amount = amount * 0.5 end
    local result = self.FogResult
    result.color = settings.skyColor or settings.color
    result.maxDensity = Lerp(amount * 0.5, worldMaximum, 1)
    result.finish = edge
    if boundaryDensity >= 0.98 then
        result.start = 0
        result.finish = boundary
        result.maxDensity = 1
    elseif result.maxDensity - boundaryDensity < 0.002 then
        // Flat continuation of an already saturated world fog.
        result.start = -40 * edge
    else
        // Never ramp slower than the city fog, so the sky is not clearer just past the boundary.
        local slope = math.max(worldMaximum / range, (result.maxDensity - boundaryDensity) / (edge - boundary))
        result.finish = boundary + (result.maxDensity - boundaryDensity) / slope
        result.start = math.max(boundary - boundaryDensity / slope, -40 * edge)
    end
    self.Stats.fogStart = result.start
    self.Stats.fogEnd = result.finish
    self.Stats.fogMaxDensity = result.maxDensity
    self.Stats.fogBoundaryDensity = boundaryDensity
    return result
end

// Traces the ring of sample points once per map; only their lighting is re-read afterwards.
function Skybox:CollectLightSamples()
    local mapName = game.GetMap()
    if self.LightSampleMap == mapName then return self.LightSamples end
    local world = game.GetWorld()
    if not world or world == NULL or not world:IsWorld() then return nil end
    local minimum, maximum = world:GetRenderBounds()
    minimum, maximum = self:ClampWorldBounds(minimum, maximum)
    if not minimum or not maximum then return nil end
    if self.Manifest and self.Manifest.schemaVersion == 2 then
        local half = self.Manifest.cellBounds.traversableHalfExtent
        minimum = Vector(math.max(minimum.x, -half), math.max(minimum.y, -half), minimum.z)
        maximum = Vector(math.min(maximum.x, half), math.min(maximum.y, half), maximum.z)
    end
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

local function applyLightCube(cube)
    local scale = getConVarNumber("zombiesim_sky_light_scale", 0.25)
    render.SuppressEngineLighting(true)
    for index, direction in ipairs(lightDirections) do
        local colour = cube[index]
        render.SetModelLighting(direction[1], colour.x * scale, colour.y * scale, colour.z * scale)
    end
end

function Skybox:Draw()
    local stats = self.Stats
    stats.frameModels = 0
    stats.frameTowers = 0
    stats.activityExplosions, stats.activityBursts, stats.activityBeams = 0, 0, 0
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
    // The cell's baked light always drives scenery and fog brightness; the convar only gates model relighting.
    local sampledCube = self:UpdateLighting()
    self:UpdateSceneryLight(sampledCube)
    local lightCube = getConVarNumber("zombiesim_sky_matched_lighting", 1) > 0 and sampledCube or nil
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
    // Layered fog supplies a separate sky colour (darker burnt orange in radiated cells) for all 3D-skybox scenery.
    local fogColor = settings and (settings.skyColor or settings.color) or defaultFogColor
    // A lightning flash briefly lifts every sky layer that shares the fog colour (towers, dome, haze and clouds).
    fogColor = self.Lightning:ApplySkyFlash(fogColor)
    local skyFog = self:GetSkyboxFog(settings)
    // Opaque distant towers must precede the translucent horizon's graduated haze.
    self:DrawTowers(manifest, skyEye, skyFog, fogColor, lightCube)
    self:DrawCoast(fogColor)
    local edgeTerrainPresent = self.EdgeMeshes ~= nil
    self:BuildDome(edge, #self.TowerPlacements > 0 or edgeTerrainPresent)
    if self.DomeMesh then
        domeColor:SetUnpacked((fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255)
        domeMaterial:SetVector("$color", domeColor)
        domeMatrix:SetTranslation(skyEye)
        cam.PushModelMatrix(domeMatrix)
        render.SetMaterial(domeMaterial)
        // Edge terrain extends far past the dome radius; the dome then acts as a backdrop rather than an occluder.
        if edgeTerrainPresent then render.OverrideDepthEnable(true, false) end
        self.DomeMesh:Draw()
        if edgeTerrainPresent then render.OverrideDepthEnable(false, false) end
        cam.PopModelMatrix()
        stats.domeDraws = (stats.domeDraws or 0) + 1
    end
    self:DrawEdgeTerrain(manifest, fogColor)
    // Radiated cells: distant fire glow low on the horizon, occluded by towers and edge terrain.
    self.Haze:DrawGlow(edge, skyEye)
    self:DrawFires(skyEye)
    self:DrawActivity(manifest, skyEye, skyFog, fogColor)
    // Ground haze follows all opaque scenery and precedes the high cloud deck.
    self.Haze:Draw(manifest, skyEye, fogColor)
    local fogStart = (skyFog and skyFog.start or 0) / scale
    local fogEnd = (skyFog and skyFog.finish or edge * scale) / scale
    if getConVarNumber("zombiesim_sky_clouds", 1) > 0 then
        self:DrawClouds(manifest, skyEye, fogColor, fogStart, fogEnd)
    else
        stats.cloudQuads = 0
    end
    self.Lightning:Draw(manifest, skyEye, fogStart, fogEnd)

    stats.lastDraw = RealTime()
    stats.draws = (stats.draws or 0) + 1
end

// A separate long-range fog pass keeps the nearby dome/fog contract intact.
function Skybox:DrawTowers(manifest, skyEye, skyFog, fogColor, lightCube)
    self.Stats.frameTowers = 0
    if not self.TowerPlacements or #self.TowerPlacements == 0 then return end
    local scale = manifest.scale
    local finish = ((manifest.skylineRadius or manifest.neighbourRadius) + 1) * manifest.cellSpan * math.sqrt(2) / scale
    // If weather already hides the playable edge, distant towers must remain hidden too.
    if skyFog and skyFog.finish <= ZM_SkyboxGeometry.GetFogBoundary(manifest) then return end
    local towerFog = math.Clamp(getConVarNumber("zombiesim_sky_tower_fog", 0.8), 0, 1)
    // Pale fog makes dark tower silhouettes stand out against the fogged neighbour cells, so lighter fog colours
    // (already darkened on dark-lit cells) blend the towers onto the same fog curve as that scenery; dark fog keeps
    // the separate long-range ramp and its plain silhouettes.
    local luminance = (0.2126 * (fogColor[1] or 128) + 0.7152 * (fogColor[2] or 128) + 0.0722 * (fogColor[3] or 128)) / 255
    local paleness = math.Clamp((luminance - towerFogDarkLuminance) / (towerFogPaleLuminance - towerFogDarkLuminance), 0, 1)
    paleness = paleness * paleness * (3 - 2 * paleness)
    local fogStart, fogEnd, fogMaximum = self:GetFogEdge(manifest) / scale, finish, towerFog
    if skyFog and paleness > 0 then
        fogStart = Lerp(paleness, fogStart, skyFog.start / scale)
        fogEnd = Lerp(paleness, fogEnd, skyFog.finish / scale)
        fogMaximum = Lerp(paleness, towerFog, math.max(towerFog, skyFog.maxDensity))
    end
    self.Stats.towerFogPaleness = math.Round(paleness, 3)
    self.Stats.towerFogStart = fogStart * scale
    self.Stats.towerFogEnd = fogEnd * scale
    self.Stats.towerFogMaxDensity = fogMaximum
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(fogStart)
    render.FogEnd(fogEnd)
    render.FogMaxDensity(fogMaximum)
    render.FogColor(fogColor[1], fogColor[2], fogColor[3])
    if lightCube then applyLightCube(lightCube) end
    local direction = self.TowerDirection
    for _, placement in ipairs(self.TowerPlacements) do
        direction:Set(placement.origin)
        direction:Sub(skyEye)
        local distance = direction:Length()
        if IsValid(placement.entity) and self.ViewForward and direction:Dot(self.ViewForward) > -placement.entity:BoundingRadius() and distance < finish then
            placement.entity:DrawModel()
            self.Stats.frameTowers = self.Stats.frameTowers + 1
        end
    end
    if lightCube then render.SuppressEngineLighting(false) end
    if skyFog then
        render.FogStart(skyFog.start / scale)
        render.FogEnd(skyFog.finish / scale)
        render.FogMaxDensity(skyFog.maxDensity)
    else
        render.FogMode(MATERIAL_FOG_NONE)
    end
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

// RenderView bypasses RenderScene, so secondary client views must temporarily supply the skyline basis.
function Skybox:RenderClientView(view)
    local savedOrigin = Vector(self.ViewOrigin)
    local forward, right, up = self.ViewForward, self.ViewRight, self.ViewUp
    self.ViewOrigin:Set(view.origin)
    self.ViewForward, self.ViewRight, self.ViewUp = view.angles:Forward(), view.angles:Right(), view.angles:Up()
    local ok, failure = xpcall(function() render.RenderView(view) end, debug.traceback)
    self.ViewOrigin:Set(savedOrigin)
    self.ViewForward, self.ViewRight, self.ViewUp = forward, right, up
    if not ok then ErrorNoHalt("[ZombieSim] Client view render failed: " .. tostring(failure) .. "\n") end
    return ok, failure
end

// Section modules share these file locals explicitly; each returns any helpers a later module needs.
local moduleHelpers = {
    getConVarNumber = getConVarNumber, smoothstep = smoothstep, valueNoise = valueNoise, mapBasename = mapBasename,
    resolveCurrentCell = resolveCurrentCell, coast = coast, defaultFogColor = defaultFogColor,
    materials = {
        dome = domeMaterial, cloud = cloudMaterial, sea = seaMaterial, foam = foamMaterial,
        smoke = smokeMaterial, fire = fireMaterial, glow = glowMaterial, tracer = tracerMaterial
    }
}
table.Merge(moduleHelpers, include("skybox/cl_coast.lua")(Skybox, moduleHelpers))
table.Merge(moduleHelpers, include("skybox/cl_edge_terrain.lua")(Skybox, moduleHelpers))
include("skybox/cl_clouds.lua")(Skybox, moduleHelpers)
include("skybox/cl_activity.lua")(Skybox, moduleHelpers)
include("skybox/cl_diagnostics.lua")(Skybox, moduleHelpers)

include("skybox/cl_haze.lua")(Skybox, { getConVarNumber = getConVarNumber })
include("skybox/cl_lightning.lua")(Skybox, { getConVarNumber = getConVarNumber })

hook.Add("PostDrawOpaqueRenderables", "ZM.Skybox.Draw", function(drawingDepth, _, drawing3DSkybox)
    if drawingDepth or not drawing3DSkybox then return end
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    Skybox:Draw()
end)

hook.Add("ShutDown", "ZM.Skybox.Cleanup", function()
    Skybox:RemoveModels()
    Skybox:DestroyCoast()
    Skybox:DestroyEdgeTerrain()
    Skybox.Haze:Destroy()
    Skybox.Haze:DestroyGlow()
    Skybox.Lightning:Reset()
end)

hook.Add("PostDrawTranslucentRenderables", "ZM.Skybox.CurrentEdgeFires", function(drawingDepth, drawingSkybox)
    if drawingDepth or drawingSkybox then return end
    Skybox:DrawCurrentEdgeFires()
end)

concommand.Add("zombiesim_skybox_status", function()
    local snapshot = Skybox:GetDiagnosticSnapshot()
    local keys = table.GetKeys(snapshot)
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = key == "currentEdgeFires" and util.TableToJSON(snapshot[key]) or tostring(snapshot[key])
        print(string.format("[ZombieSim] Skybox %s = %s", key, value))
    end
end)

concommand.Add("zombiesim_dev_skybox_activity", function()
    local player = LocalPlayer()
    if not IsValid(player) or not player:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Activity preview requires a preview admin.\n")
        return
    end
    Skybox.ActivityPreviewStart = CurTime()
    Skybox.ActivityPreviewUntil = CurTime() + 12
    print("[ZombieSim] Cosmetic skyline activity preview enabled for 12 seconds.")
end)

// Writes data/zombiesim/skybox_edges.json with the cardinal edge regression results.
concommand.Add("zombiesim_dev_skybox_edges", function()
    local player = LocalPlayer()
    if not IsValid(player) or not player:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Edge regression requires a preview admin.\n")
        return
    end
    local results, failures = Skybox:RunEdgeRegression()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/skybox_edges.json", util.TableToJSON({
        passed = failures == 0, failures = failures, cases = results, generated = os.time(),
        edgeTerrainQuads = Skybox.Stats.edgeTerrainQuads, edgeBuildMs = Skybox.Stats.edgeBuildMs
    }, true))
    for _, result in ipairs(results) do
        print(string.format("[ZombieSim] %s %s: %s", result.passed and "PASS" or "FAIL", result.name, result.detail or ""))
    end
    print(string.format("[ZombieSim] Skybox edge regression: %d/%d passed.", #results - failures, #results))
end)

// A hot reload must not leave the previous load's hidden models behind.
Skybox:RemoveModels()
Skybox:DestroyCoast()
Skybox:DestroyEdgeTerrain()
Skybox.PlacementKey = nil
Skybox.ManifestProfile = nil
if Skybox.DomeMesh then Skybox.DomeMesh:Destroy() end
Skybox.DomeMesh = nil
Skybox.Clouds = nil
Skybox.LightSampleMap = nil
Skybox.LightCube = nil
