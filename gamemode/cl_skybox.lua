// Runtime 3D skybox. Every city recipe carries the same sky_camera room; this module draws the current cell's
// neighbouring recipe models inside it, then a fog-coloured horizon wall and a drifting cloud deck. Models and the
// manifest come from bin/build_skybox_models.ps1, so cells that share a recipe still show their own surroundings.
ZM_Skybox = ZM_Skybox or {}
local Skybox = ZM_Skybox

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
local skylineDomeRings = {
    { elevation = -40, alpha = 1 },
    { elevation = -2, alpha = 1 },
    { elevation = 0, alpha = 0.45 },
    { elevation = 3, alpha = 0.12 },
    { elevation = 7, alpha = 0.05 },
    { elevation = 18, alpha = 0 }
}
// The fog becomes opaque slightly inside the outermost modelled ring so its far edge is never seen.
local fogEdgeFraction = 0.9
// Distant-tower fog: fog colours at or below the dark luminance keep the plain long-range tower ramp; at or above
// the pale luminance the towers share the nearby sky fog curve so they match the fogged neighbour cells.
local towerFogDarkLuminance = 0.45
local towerFogPaleLuminance = 0.7
local cloudClusterCount = 56
local cloudSeed = 7331
// Sky-space units (1 sky unit = manifest.scale world units).
local cloudBaseHeight = 300
local cloudHeightRange = 70
local cloudDriftSpeed = 1.6
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
coast.sandMaterial = CreateMaterial("zombiesim_skybox_sand_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/sandfloor010a",
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
Skybox.TowerDirection = Skybox.TowerDirection or Vector()
Skybox.FogResult = Skybox.FogResult or { color = {} }
Skybox.TuningSettings = {
    { label = "Skybox fog amount", name = "zombiesim_sky_fog_amount", default = 0.8, minimum = 0, maximum = 2,
        tooltip = "Extra skybox fog beyond the playable-city fog. 0 matches the city fog exactly; 1 thickens halfway to opaque; 2 closes the horizon." },
    { label = "Skybox fog distance", name = "zombiesim_sky_fog_distance", default = 0.9, minimum = 0.5, maximum = 3,
        tooltip = "Scales how far skybox fog extends. Higher values give clearer nearby scenery; playable-city fog is unchanged." },
    { label = "Skybox horizon haze", name = "zombiesim_sky_horizon_haze", default = 0.5, minimum = 0, maximum = 1.5,
        tooltip = "Scales the horizon overlay above eye level. Lower values reveal silhouettes; 0 may expose scenery edges." },
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
        return nil
    end
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

local coastMeshKinds = { "underlay", "water", "sand", "rock", "embankment", "foam" }
local quadOffsets = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }

function Skybox:DestroyCoast()
    for _, list in pairs(self.CoastMeshes or {}) do
        for _, imesh in ipairs(list) do imesh:Destroy() end
    end
    self.CoastMeshes = nil
end

local function pushCoastVertex(buffer, x, y, z, red, green, blue, alpha, u, v)
    local count = buffer.count
    buffer[count + 1], buffer[count + 2], buffer[count + 3] = x, y, z
    buffer[count + 4] = math.Clamp(math.floor(red + 0.5), 0, 255)
    buffer[count + 5] = math.Clamp(math.floor(green + 0.5), 0, 255)
    buffer[count + 6] = math.Clamp(math.floor(blue + 0.5), 0, 255)
    buffer[count + 7] = math.Clamp(math.floor(alpha + 0.5), 0, 255)
    buffer[count + 8], buffer[count + 9] = u, v
    buffer.count = count + 9
end

// Splits a quad buffer into static meshes well below the per-mesh vertex limit. Everything inside Begin/End is
// plain number access so nothing can error mid-build.
local function buildCoastMeshes(buffer)
    local meshes = {}
    local quadCount = math.floor(buffer.count / 36)
    local vertex = coast.vertex
    local first = 0
    while first < quadCount do
        local quads = math.min(coast.chunkQuads, quadCount - first)
        local imesh = Mesh()
        mesh.Begin(imesh, MATERIAL_QUADS, quads)
        for index = first * 36 + 1, (first + quads) * 36, 9 do
            vertex:SetUnpacked(buffer[index], buffer[index + 1], buffer[index + 2])
            mesh.Position(vertex)
            mesh.Color(buffer[index + 3], buffer[index + 4], buffer[index + 5], buffer[index + 6])
            mesh.TexCoord(0, buffer[index + 7], buffer[index + 8])
            mesh.AdvanceVertex()
        end
        mesh.End()
        table.insert(meshes, imesh)
        first = first + quads
    end
    return meshes, quadCount
end

local function waterShade(depth)
    local t = smoothstep(0, 5.5, depth)
    return Lerp(t, 96, 30), Lerp(t, 156, 68), Lerp(t, 150, 88)
end

// Slots beyond the world grid become sea. A low rock embankment caps every city edge that faces it; below it a
// noise-jittered sand beach with rocky outcrops descends into shallow water, and breaking foam follows the depth
// contours toward the waterline. Built in absolute sky coordinates whenever the placement changes.
function Skybox:BuildCoast(manifest, gridX, gridY, radius)
    self:DestroyCoast()
    local stats = self.Stats
    stats.coastSeaQuads, stats.coastWallQuads, stats.coastFoamQuads = 0, 0, 0
    stats.coastSandQuads, stats.coastRockQuads, stats.coastMeshes = 0, 0, 0
    if radius < 1 then return end
    local started = SysTime()

    local span = manifest.cellSpan / manifest.scale
    local half = span * 0.5
    local camera = manifest.cameraVector
    local reach = radius + 1
    // Only the west edge is ocean; the other edges are landforms drawn by the edge terrain, so they count as land here
    // (beaches form against them) but only city cells get the rock embankment.
    local data = ZM_World:GetData()
    local grid = data and data.world and data.world.grid
    local width, height = tonumber(grid and grid[1]) or 0, tonumber(grid and grid[2]) or 0
    local land, city = {}, {}
    local function classify(dx, dy)
        local key = dx .. ":" .. dy
        if land[key] == nil then
            local kind = Skybox.ClassifyEdge(gridX + dx, gridY + dy, width, height)
            city[key] = (dx == 0 and dy == 0) or (kind == "city" and ZM_World:GetCell(gridX + dx, gridY + dy) ~= nil)
            land[key] = city[key] or (kind ~= "ocean" and kind ~= "city")
        end
        return key
    end
    local function isLand(dx, dy) return land[classify(dx, dy)] end
    local function isCity(dx, dy) return city[classify(dx, dy)] end
    local seaSlots, edges = {}, {}
    local function landRectangle(dx, dy)
        local cell = ZM_World:GetCell(gridX + dx, gridY + dy)
        local x, y = camera.x + dx * span, camera.y - dy * span
        return ZM_SkyboxGeometry.GetLandRectangle(manifest, cell and mapBasename(cell.map), x, y)
    end
    local function nearbyLand(dx, dy)
        local lands = {}
        for ny = -1, 1 do
            for nx = -1, 1 do
                if isLand(dx + nx, dy + ny) then
                    table.insert(lands, landRectangle(dx + nx, dy + ny))
                end
            end
        end
        return lands
    end
    // Grid east (dx + 1) is +X; grid north (dy - 1) is +Y in Hammer space.
    local sides = { { 1, 0, 1, 0 }, { -1, 0, -1, 0 }, { 0, -1, 0, 1 }, { 0, 1, 0, -1 } }
    for dy = -reach, reach do
        for dx = -reach, reach do
            local cx, cy = camera.x + dx * span, camera.y - dy * span
            if isLand(dx, dy) then
                if not isCity(dx, dy) then continue end
                local rectangle = landRectangle(dx, dy)
                for _, band in ipairs(ZM_SkyboxGeometry.GetWaterBands(rectangle, cx, cy, half)) do
                    band.lands = nearbyLand(dx, dy)
                    table.insert(seaSlots, band)
                end
                for _, side in ipairs(sides) do
                    local omitted = (side[3] == 1 and rectangle.x1 < cx + half) or
                        (side[3] == -1 and rectangle.x0 > cx - half) or
                        (side[4] == 1 and rectangle.y1 < cy + half) or
                        (side[4] == -1 and rectangle.y0 > cy - half)
                    if omitted or not isLand(dx + side[1], dy + side[2]) then
                        local x = side[3] == 1 and rectangle.x1 or (side[3] == -1 and rectangle.x0 or (rectangle.x0 + rectangle.x1) * 0.5)
                        local y = side[4] == 1 and rectangle.y1 or (side[4] == -1 and rectangle.y0 or (rectangle.y0 + rectangle.y1) * 0.5)
                        table.insert(edges, { x = x, y = y, nx = side[3], ny = side[4],
                            length = side[3] ~= 0 and rectangle.y1 - rectangle.y0 or rectangle.x1 - rectangle.x0 })
                    end
                end
            else
                table.insert(seaSlots, { x = cx, y = cy, lands = nearbyLand(dx, dy) })
            end
        end
    end
    if #seaSlots == 0 then return end

    local seaZ = camera.z + coast.seaLevel
    local offsetX, offsetY = gridX * span - camera.x, -gridY * span - camera.y
    local far = coast.bandWidth + 40
    // Returns terrain height, rockiness, and the unjittered distance to the nearest land slot.
    local function sample(px, py, lands)
        local nearest = far
        for index = 1, #lands do
            local slot = lands[index]
            nearest = math.min(nearest, ZM_SkyboxGeometry.DistanceToLand(px, py, slot))
        end
        if nearest >= far then return seaZ - 8, 0, nearest end
        local wx, wy = px + offsetX, py + offsetY
        local jitter = ((valueNoise(wx / 90, wy / 90) - 0.5) * 26 + (valueNoise(wx / 23 + 7.1, wy / 23 + 3.7) - 0.5) * 7) * smoothstep(0, 14, nearest)
        local distance = math.max(nearest + jitter, 0)
        local height
        if distance < coast.beachWidth then
            height = seaZ + coast.duneHeight * (1 - distance / coast.beachWidth) ^ 1.4
        else
            height = seaZ - (distance - coast.beachWidth) * coast.shelfSlope
        end
        local rock = smoothstep(0.56, 0.72, valueNoise(wx / 150 + 31.7, wy / 150 + 17.3))
        if rock > 0 then
            local ridge = 1 - math.abs(valueNoise(wx / 16 + 5.3, wy / 16 + 9.1) * 2 - 1)
            height = height + rock * (1 - smoothstep(25, 95, nearest)) * (ridge * ridge * 6.5 - 1.2)
        end
        return height, rock, nearest
    end
    // Samples a slot grid with a one-sample border so terrain normals are continuous across slot edges.
    local function sampleGrid(slot, divisions)
        local width, height = (slot.halfX or half) * 2, (slot.halfY or half) * 2
        local cx = camera.x + math.floor((slot.x - camera.x) / span + 0.5) * span
        local cy = camera.y + math.floor((slot.y - camera.y) / span + 0.5) * span
        local coastHalf = manifest.schemaVersion == 2 and manifest.cellBounds.coastContactHalfExtent / manifest.scale or nil
        local xs, columns = ZM_SkyboxGeometry.GetCoastAxis(slot.x - width * 0.5, slot.x + width * 0.5, cx, span, divisions, coastHalf)
        local ys, rows = ZM_SkyboxGeometry.GetCoastAxis(slot.y - height * 0.5, slot.y + height * 0.5, cy, span, divisions, coastHalf)
        local stride = columns + 3
        local grid = { xs = xs, ys = ys, stepX = width / columns, stepY = height / rows, columns = columns, rows = rows, stride = stride,
            x0 = slot.x - width * 0.5, y0 = slot.y - height * 0.5, heights = {}, rocks = {}, nearest = {} }
        for row = -1, rows + 1 do
            for column = -1, columns + 1 do
                local index = (row + 1) * stride + column + 2
                grid.heights[index], grid.rocks[index], grid.nearest[index] = sample(xs[column], ys[row], slot.lands)
            end
        end
        return grid
    end

    local buffers = {}
    for _, kind in ipairs(coastMeshKinds) do buffers[kind] = { count = 0 } end
    local tile = coast.rippleTile
    local lightX, lightY, lightZ = 0.45, 0.35, 0.82
    for _, slot in ipairs(seaSlots) do
        local halfX, halfY = slot.halfX or half, slot.halfY or half
        local x0, y0, x1, y1 = slot.x - halfX, slot.y - halfY, slot.x + halfX, slot.y + halfY
        local deepRed, deepGreen, deepBlue = waterShade(99)
        local underlayZ = seaZ - 0.4
        local underlay = buffers.underlay
        pushCoastVertex(underlay, x0, y0, underlayZ, deepRed, deepGreen, deepBlue, 255, (x0 + offsetX) / tile, (y0 + offsetY) / tile)
        pushCoastVertex(underlay, x1, y0, underlayZ, deepRed, deepGreen, deepBlue, 255, (x1 + offsetX) / tile, (y0 + offsetY) / tile)
        pushCoastVertex(underlay, x1, y1, underlayZ, deepRed, deepGreen, deepBlue, 255, (x1 + offsetX) / tile, (y1 + offsetY) / tile)
        pushCoastVertex(underlay, x0, y1, underlayZ, deepRed, deepGreen, deepBlue, 255, (x0 + offsetX) / tile, (y1 + offsetY) / tile)
        if slot.lands and #slot.lands > 0 then
            // Beach and rock terrain: only quads that reach the surface are kept; the rest is hidden by water.
            local grid = sampleGrid(slot, coast.terrainDivisions)
            local stepX, stepY, stride, heights, rocks, nearest = grid.stepX, grid.stepY, grid.stride, grid.heights, grid.rocks, grid.nearest
            local function terrainVertex(buffer, row, column, rocky)
                local index = (row + 1) * stride + column + 2
                local height = heights[index]
                local slopeX = (heights[index + 1] - heights[index - 1]) / (grid.xs[column + 1] - grid.xs[column - 1])
                local slopeY = (heights[index + stride] - heights[index - stride]) / (grid.ys[row + 1] - grid.ys[row - 1])
                local light = (-slopeX * lightX - slopeY * lightY + lightZ) / math.sqrt(slopeX * slopeX + slopeY * slopeY + 1)
                local shade = 0.5 + 0.5 * math.max(light, 0)
                local wet = 1 - smoothstep(seaZ + 0.1, seaZ + 0.9, height)
                local red, green, blue
                if rocky then
                    shade = shade * (1 - 0.3 * wet)
                    red, green, blue = 192 * shade, 188 * shade, 182 * shade
                else
                    shade = shade * (1 - 0.38 * wet)
                    red, green, blue = 255 * shade, 226 * shade, 172 * shade
                end
                local x, y = grid.xs[column], grid.ys[row]
                pushCoastVertex(buffer, x, y, height, red, green, blue, 255, (x + offsetX) / 24, (y + offsetY) / 24)
            end
            for row = 0, grid.rows - 1 do
                for column = 0, grid.columns - 1 do
                    local a = (row + 1) * stride + column + 2
                    local b, c, d = a + 1, a + stride + 1, a + stride
                    local highest = math.max(heights[a], heights[b], heights[c], heights[d])
                    if highest > seaZ - 0.4 and math.min(nearest[a], nearest[b], nearest[c], nearest[d]) < coast.bandWidth then
                        local lowest = math.min(heights[a], heights[b], heights[c], heights[d])
                        local rocky = (rocks[a] + rocks[b] + rocks[c] + rocks[d]) * 0.25 > 0.42 or highest - lowest > math.min(stepX, stepY) * 0.75
                        local buffer = rocky and buffers.rock or buffers.sand
                        terrainVertex(buffer, row, column, rocky)
                        terrainVertex(buffer, row, column + 1, rocky)
                        terrainVertex(buffer, row + 1, column + 1, rocky)
                        terrainVertex(buffer, row + 1, column, rocky)
                    end
                end
            end

            // Shallow water shades with depth and carries the breaking-foam layer.
            grid = sampleGrid(slot, coast.waterDivisions)
            stepX, stepY, stride, heights, nearest = grid.stepX, grid.stepY, grid.stride, grid.heights, grid.nearest
            local foamZ = seaZ + 0.2
            local corners = {}
            for row = 0, grid.rows - 1 do
                for column = 0, grid.columns - 1 do
                    local a = (row + 1) * stride + column + 2
                    corners[1], corners[2], corners[3], corners[4] = a, a + 1, a + stride + 1, a + stride
                    if math.min(nearest[a], nearest[a + 1], nearest[a + stride + 1], nearest[a + stride]) < coast.bandWidth then
                        local shallowest, deepest = math.huge, -math.huge
                        for corner = 1, 4 do
                            local index = corners[corner]
                            local depth = seaZ - heights[index]
                            shallowest, deepest = math.min(shallowest, depth), math.max(deepest, depth)
                            local x, y = grid.xs[column + quadOffsets[corner][1]], grid.ys[row + quadOffsets[corner][2]]
                            local red, green, blue = waterShade(depth)
                            pushCoastVertex(buffers.water, x, y, seaZ, red, green, blue, 255, (x + offsetX) / tile, (y + offsetY) / tile)
                        end
                        if shallowest < coast.foamDepth and deepest > -0.4 then
                            for corner = 1, 4 do
                                local depth = seaZ - heights[corners[corner]]
                                local x, y = grid.xs[column + quadOffsets[corner][1]], grid.ys[row + quadOffsets[corner][2]]
                                local foam = 255 * (1 - smoothstep(2.6, coast.foamDepth, depth)) * smoothstep(-0.4, 0.2, depth)
                                pushCoastVertex(buffers.foam, x, y, foamZ, foam, foam, foam, 255, (x + y + offsetX + offsetY) / 70, depth / coast.waveDepthLength)
                            end
                        end
                    end
                end
            end
        end
    end

    // A low, slightly sloped rock lip covers the step between each city edge and the beach below it.
    local topZ, footZ = camera.z + coast.streetHeight, seaZ - 1
    for _, edge in ipairs(edges) do
        // The edge runs perpendicular to its outward normal.
        local edgeHalf = edge.length * 0.5
        local tx, ty = -edge.ny * edgeHalf, edge.nx * edgeHalf
        local ox, oy = edge.nx * 1.5, edge.ny * 1.5
        local buffer = buffers.embankment
        local height = (topZ - footZ) / 8
        pushCoastVertex(buffer, edge.x - tx, edge.y - ty, topZ, 205, 200, 194, 255, 0, 0)
        pushCoastVertex(buffer, edge.x + tx, edge.y + ty, topZ, 205, 200, 194, 255, edge.length / 8, 0)
        pushCoastVertex(buffer, edge.x + tx + ox, edge.y + ty + oy, footZ, 150, 146, 140, 255, edge.length / 8, height)
        pushCoastVertex(buffer, edge.x - tx + ox, edge.y - ty + oy, footZ, 150, 146, 140, 255, 0, height)
    end

    local meshes, counts, meshCount = {}, {}, 0
    for _, kind in ipairs(coastMeshKinds) do
        meshes[kind], counts[kind] = buildCoastMeshes(buffers[kind])
        meshCount = meshCount + #meshes[kind]
    end
    self.CoastMeshes = meshes
    stats.coastSeaQuads = counts.underlay + counts.water
    stats.coastWallQuads = counts.embankment
    stats.coastFoamQuads = counts.foam
    stats.coastSandQuads = counts.sand
    stats.coastRockQuads = counts.rock
    stats.coastMeshes = meshCount
    stats.coastBuildMs = math.Round((SysTime() - started) * 1000, 1)
end

local function drawCoastMeshes(list)
    for _, imesh in ipairs(list) do imesh:Draw() end
end

local function setCoastTextureTransform(material, scale, yaw, offsetU, offsetV)
    local matrix = coast.textureMatrix
    matrix:Identity()
    coast.textureAngle:SetUnpacked(0, yaw, 0)
    matrix:Rotate(coast.textureAngle)
    coast.textureScale:SetUnpacked(scale, scale, 1)
    matrix:Scale(coast.textureScale)
    coast.textureOffset:SetUnpacked(offsetU % 1, offsetV % 1, 0)
    matrix:SetTranslation(coast.textureOffset)
    material:SetMatrix("$basetexturetransform", matrix)
end

// The playable cell's baked lighting, measured through the light cube, tints the shared fog colour (see
// Atmosphere:GetFogSettings) so dark districts get dark fog in both the city and the sky, and the coast, edge terrain,
// dome and clouds that derive from the fog colour darken with it. Bright daylight cells (cube top luminance about
// 0.85) keep the profile colour; the square root keeps dim cells readable rather than black.
Skybox.SceneryLight = { level = 1, 1, 1, 1, fullBright = 0.8, minimum = 0.3, chroma = 0.4 }
function Skybox:UpdateSceneryLight(cube)
    local light = self.SceneryLight
    local top = cube and cube[5]
    if not top then
        light.level, light[1], light[2], light[3] = 1, 1, 1, 1
    else
        local luminance = math.max(top.x * 0.3 + top.y * 0.59 + top.z * 0.11, 0.0001)
        local level = math.Clamp(math.sqrt(luminance / light.fullBright), light.minimum, 1)
        // Hue follows the light only as it darkens, so daylight cells keep the profile colour exactly.
        local chroma = light.chroma * (1 - level) / (1 - light.minimum)
        light.level = level
        light[1] = math.min(level * Lerp(chroma, 1, math.Clamp(top.x / luminance, 0.5, 1.5)), 1)
        light[2] = math.min(level * Lerp(chroma, 1, math.Clamp(top.y / luminance, 0.5, 1.5)), 1)
        light[3] = math.min(level * Lerp(chroma, 1, math.Clamp(top.z / luminance, 0.5, 1.5)), 1)
    end
    self.Stats.sceneryLight = math.Round(light.level, 3)
    return light
end

// Coast colours follow the atmosphere's brightness; the sky-pass fog supplies distance haze, so the water keeps its
// own hue instead of being pre-mixed toward the fog colour.
function Skybox:DrawCoast(fogColor)
    local meshes = self.CoastMeshes
    if not meshes then return end
    local red, green, blue = (fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255
    local brightness = math.Clamp((red * 0.3 + green * 0.59 + blue * 0.11) * 1.6, 0.25, 1)
    local snow = self.Stats.snowAlpha or 0
    local now = CurTime()
    cam.PushModelMatrix(identityMatrix)
    coastColor:SetUnpacked(Lerp(0.12, brightness, red), Lerp(0.12, brightness, green), Lerp(0.12, brightness, blue))
    seaMaterial:SetVector("$color", coastColor)
    render.SetMaterial(seaMaterial)
    drawCoastMeshes(meshes.underlay)
    drawCoastMeshes(meshes.water)
    local ground = brightness * Lerp(snow, 1, 1.15)
    coastColor:SetUnpacked(math.min(Lerp(snow * 0.7, ground, 1), 1), math.min(Lerp(snow * 0.7, ground, 1), 1), math.min(Lerp(snow * 0.7, ground, 1), 1))
    for _, entry in ipairs({ { coast.sandMaterial, meshes.sand }, { coast.rockMaterial, meshes.rock }, { coast.embankmentMaterial, meshes.embankment } }) do
        if #entry[2] > 0 then
            entry[1]:SetVector("$color", coastColor)
            render.SetMaterial(entry[1])
            drawCoastMeshes(entry[2])
        end
    end
    if coast.texturesReady then
        // Two ripple layers at different scales and headings interfere into a moving glitter.
        local ripple = coast.rippleMaterial
        coastColor:SetUnpacked(0.7 * brightness, 0.75 * brightness, 0.8 * brightness)
        ripple:SetVector("$color", coastColor)
        setCoastTextureTransform(ripple, 1, 0, now * 0.011, now * 0.019)
        render.SetMaterial(ripple)
        drawCoastMeshes(meshes.underlay)
        drawCoastMeshes(meshes.water)
        setCoastTextureTransform(ripple, 1.7, 37, -now * 0.014, now * 0.008)
        render.SetMaterial(ripple)
        drawCoastMeshes(meshes.underlay)
        drawCoastMeshes(meshes.water)
        if #meshes.foam > 0 then
            coastColor:SetUnpacked(0.95 * brightness, 0.97 * brightness, brightness)
            foamMaterial:SetVector("$color", coastColor)
            setCoastTextureTransform(foamMaterial, 1, 0, now * 0.006, now / coast.wavePeriod)
            render.SetMaterial(foamMaterial)
            drawCoastMeshes(meshes.foam)
        end
    end
    cam.PopModelMatrix()
    self.Stats.coastDraws = (self.Stats.coastDraws or 0) + 1
end

// Cardinal world edges: north hills, east mountains, south flatlands, west open ocean (the coast above). The ring is
// one static height field in grid-local sky units, u east from the grid's west boundary and v south from its north
// boundary, built once per profile and translated to the current cell when drawn. City boundaries sit at street
// height; corners blend the two adjacent landforms and the north/south land falls to beach height at the west shore.
local edgeTerrain = {
    cellsPerQuad = 7,
    northDepth = 40,
    southDepth = 40,
    eastDepth = 60,
    snowLine = 380,
    light = Vector(-0.45, -0.3, 0.84):GetNormalized(),
    matrix = Matrix(),
    translation = Vector(),
    color = Vector(),
    layerDepthBias = 0.00003
}
edgeTerrain.grassMaterial = CreateMaterial("zombiesim_skybox_edge_grass_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/grassfloor002a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
// Rock and snow are translucent overlays on the same surface; per-vertex alpha blends them smoothly over the grass.
edgeTerrain.rockMaterial = CreateMaterial("zombiesim_skybox_edge_rock_v2", "UnlitGeneric", {
    ["$basetexture"] = "nature/rockfloor005a",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1
})
edgeTerrain.snowMaterial = CreateMaterial("zombiesim_skybox_edge_snow_v2", "UnlitGeneric", {
    ["$basetexture"] = "nature/snowfloor002a",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1
})
// Weather snow is drawn over grass and rock as a translucent pass whose alpha follows the settled snow cover.
edgeTerrain.coverMaterial = CreateMaterial("zombiesim_skybox_edge_cover_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/snowfloor002a",
    ["$vertexcolor"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1
})
edgeTerrain.kinds = { "grass", "rock", "snow" }
edgeTerrain.materials = { grass = edgeTerrain.grassMaterial, rock = edgeTerrain.rockMaterial, snow = edgeTerrain.snowMaterial }
edgeTerrain.tiles = { grass = 48, rock = 96, snow = 72 }

// Classifies a grid slot (cells, may lie outside the grid). Ocean owns every slot west of the grid, including the
// north-west and south-west corner columns, so the shoreline runs straight along the west boundary.
function Skybox.ClassifyEdge(gx, gy, width, height)
    if gx >= 0 and gx < width and gy >= 0 and gy < height then return "city" end
    if gx < 0 then return "ocean" end
    if gx >= width then
        if gy < 0 then return "hills-mountains" end
        if gy >= height then return "mountains-flatlands" end
        return "mountains"
    end
    if gy < 0 then return "hills" end
    return "flatlands"
end

local function terrainFbm(x, y)
    return valueNoise(x, y) * 0.5 + valueNoise(x * 2.03 + 17.1, y * 2.03 + 4.9) * 0.3 + valueNoise(x * 4.1 + 9.7, y * 4.1 + 23.3) * 0.2
end

local function terrainRidge(x, y)
    local total, amplitude, weight = 0, 0.6, 0
    for octave = 1, 3 do
        local ridge = 1 - math.abs(valueNoise(x, y) * 2 - 1)
        total, weight = total + ridge * ridge * amplitude, weight + amplitude
        x, y, amplitude = x * 2.1 + 13.7, y * 2.1 + 5.3, amplitude * 0.5
    end
    return total / weight
end

local function hillsHeight(u, v, d)
    return 2 + smoothstep(0, 350, d) * (14 + 62 * terrainFbm(u / 260 + 3.1, v / 260 + 8.7))
end

local function flatlandsHeight(u, v, d)
    return 2 + smoothstep(0, 250, d) * (1 + 5 * terrainFbm(u / 420 + 11.3, v / 420 + 2.9))
end

local function mountainHeight(u, v, d)
    local foothills = smoothstep(0, 300, d) * (12 + 40 * terrainFbm(u / 220 + 5.5, v / 220 + 1.7))
    // Large-scale massifs vary the range height; a domain warp breaks up the noise lattice so peaks do not repeat.
    local massif = terrainFbm(u / 1500 + 7.7, v / 1500 + 3.3)
    local warpU = u + (valueNoise(u / 700 + 1.9, v / 700 + 4.2) - 0.5) * 420
    local warpV = v + (valueNoise(u / 700 + 8.3, v / 700 + 6.6) - 0.5) * 420
    local ridge = terrainRidge(warpU / 430 + 2.2, warpV / 430 + 9.4)
    return 2 + foothills + smoothstep(250, 1300, d) * (140 + 1000 * massif * massif * (0.35 + 0.65 * ridge))
end

// Height above the sky camera (sky units) at grid-local (u, v) outside the city rectangle `width` x `height`.
function Skybox.EdgeHeight(u, v, width, height, span)
    local e, n, s = math.max(u - width, 0), math.max(-v, 0), math.max(v - height, 0)
    local quad = span / edgeTerrain.cellsPerQuad
    local h
    if e > 0 and n > 0 then
        local d = math.sqrt(e * e + n * n)
        h = Lerp(smoothstep(0.25, 0.75, e / (e + n)), hillsHeight(u, v, d), mountainHeight(u, v, d))
    elseif e > 0 and s > 0 then
        local d = math.sqrt(e * e + s * s)
        h = Lerp(smoothstep(0.25, 0.75, e / (e + s)), flatlandsHeight(u, v, d), mountainHeight(u, v, d))
    elseif e > 0 then
        h = mountainHeight(u, v, e)
    elseif n > 0 then
        h = hillsHeight(u, v, n)
    elseif s > 0 then
        h = flatlandsHeight(u, v, s)
    else
        return 2
    end
    // North/south land falls to the coast's dune height at the west shore.
    if e <= 0 then
        local depth = math.max(n, s)
        h = Lerp(smoothstep(0, 360, u), Lerp(smoothstep(0, 40, depth), 2, coast.seaLevel + coast.duneHeight), h)
    end
    // The ring's outer limits taper so no cut face shows on the horizon.
    local taper = (1 - smoothstep(edgeTerrain.northDepth * quad * 0.55, edgeTerrain.northDepth * quad, n)) *
        (1 - smoothstep(edgeTerrain.southDepth * quad * 0.55, edgeTerrain.southDepth * quad, s)) *
        (1 - smoothstep(edgeTerrain.eastDepth * quad * 0.8, edgeTerrain.eastDepth * quad, e))
    return 2 + (h - 2) * taper
end

function Skybox:DestroyEdgeTerrain()
    for _, list in pairs(self.EdgeMeshes or {}) do
        for _, imesh in ipairs(list) do imesh:Destroy() end
    end
    self.EdgeMeshes = nil
    self.EdgeKey = nil
end

// Regions share their boundary sample lines exactly (all extents are whole quads), so no T-junction cracks appear.
function Skybox:BuildEdgeTerrain(manifest)
    local data = ZM_World and ZM_World:GetData()
    local grid = data and data.world and data.world.grid
    local width, height = tonumber(grid and grid[1]), tonumber(grid and grid[2])
    if not width or not height then return end
    local span = manifest.cellSpan / manifest.scale
    local key = table.concat({ tostring(self.ManifestProfile), width, height, span, manifest.cameraVector.z, manifest.schemaVersion, "edges-v3" }, ":")
    if key == self.EdgeKey and self.EdgeMeshes then return end
    self:DestroyEdgeTerrain()
    local started = SysTime()
    local quad = span / edgeTerrain.cellsPerQuad
    local W, H = width * span, height * span
    local northDepth, southDepth, eastDepth = edgeTerrain.northDepth * quad, edgeTerrain.southDepth * quad, edgeTerrain.eastDepth * quad
    local regions = {
        { u0 = 0, v0 = -northDepth, columns = width * edgeTerrain.cellsPerQuad, rows = edgeTerrain.northDepth },
        { u0 = 0, v0 = H, columns = width * edgeTerrain.cellsPerQuad, rows = edgeTerrain.southDepth },
        { u0 = W, v0 = -northDepth, columns = edgeTerrain.eastDepth, rows = edgeTerrain.northDepth + height * edgeTerrain.cellsPerQuad + edgeTerrain.southDepth }
    }
    local baseZ = manifest.cameraVector.z
    local light = edgeTerrain.light
    local buffers = { grass = { count = 0 }, rock = { count = 0 }, snow = { count = 0 } }
    local tiles = edgeTerrain.tiles
    for _, region in ipairs(regions) do
        local stride = region.columns + 3
        local heights = {}
        for row = -1, region.rows + 1 do
            for column = -1, region.columns + 1 do
                heights[(row + 1) * stride + column + 2] = Skybox.EdgeHeight(region.u0 + column * quad, region.v0 + row * quad, W, H, span)
            end
        end
        local shades, rocks, snows = {}, {}, {}
        for row = 0, region.rows do
            for column = 0, region.columns do
                local index = (row + 1) * stride + column + 2
                // Grid-local v grows south while sky Y grows north, hence the sign on the Y gradient.
                local gx = (heights[index + 1] - heights[index - 1]) / (2 * quad)
                local gy = -(heights[index + stride] - heights[index - stride]) / (2 * quad)
                local length = math.sqrt(gx * gx + gy * gy + 1)
                local lambert = math.max((-gx * light.x - gy * light.y + light.z) / length, 0)
                shades[index] = 0.42 + 0.58 * lambert
                local slope = math.sqrt(gx * gx + gy * gy)
                local u, v = region.u0 + column * quad, region.v0 + row * quad
                local h = heights[index]
                rocks[index] = math.max(smoothstep(0.55, 1, slope), smoothstep(120, 230, h + (valueNoise(u / 90 + 1.3, v / 90 + 6.1) - 0.5) * 90))
                snows[index] = smoothstep(edgeTerrain.snowLine - 50, edgeTerrain.snowLine + 50,
                    h + (valueNoise(u / 140 + 4.4, v / 140 + 7.7) - 0.5) * 160) * (1 - 0.7 * smoothstep(1.1, 1.8, slope))
            end
        end
        local corners = {}
        for row = 0, region.rows - 1 do
            for column = 0, region.columns - 1 do
                local a = (row + 1) * stride + column + 2
                corners[1], corners[2], corners[3], corners[4] = a, a + 1, a + stride + 1, a + stride
                local rock, snow = 0, 0
                for corner = 1, 4 do
                    rock, snow = math.max(rock, rocks[corners[corner]]), math.max(snow, snows[corners[corner]])
                end
                for corner = 1, 4 do
                    local index = corners[corner]
                    local x = region.u0 + (column + quadOffsets[corner][1]) * quad
                    local y = -(region.v0 + (row + quadOffsets[corner][2]) * quad)
                    local z = baseZ + heights[index]
                    local shade = shades[index] * 255
                    // Lower, drier grass warms; lush patches cool slightly.
                    local dry = valueNoise(x / 300 + 2.5, y / 300 + 8.5)
                    pushCoastVertex(buffers.grass, x, y, z, shade * Lerp(dry, 0.82, 1), shade * Lerp(dry, 0.9, 0.86), shade * Lerp(dry, 0.7, 0.62), 255, x / tiles.grass, y / tiles.grass)
                    if rock > 0.01 then
                        pushCoastVertex(buffers.rock, x, y, z, shade, shade * 0.98, shade * 0.95, rocks[index] * 255, x / tiles.rock, y / tiles.rock)
                    end
                    if snow > 0.01 then
                        pushCoastVertex(buffers.snow, x, y, z, shade * 0.96, shade * 0.98, shade, snows[index] * 255, x / tiles.snow, y / tiles.snow)
                    end
                end
            end
        end
    end
    local meshes, total, meshCount = {}, 0, 0
    for _, kind in ipairs(edgeTerrain.kinds) do
        local quads
        meshes[kind], quads = buildCoastMeshes(buffers[kind])
        total, meshCount = total + quads, meshCount + #meshes[kind]
        self.Stats["edge" .. kind .. "Quads"] = quads
    end
    self.EdgeMeshes = meshes
    self.EdgeKey = key
    self.EdgeGrid = { width = width, height = height, span = span }
    local stats = self.Stats
    stats.edgeTerrainQuads = total
    stats.edgeTerrainMeshes = meshCount
    stats.edgeBuildMs = math.Round((SysTime() - started) * 1000, 1)
end

// Sky-space translation that places the grid-local terrain around the current cell.
function Skybox:GetEdgeTranslation(manifest, gridX, gridY)
    local span = manifest.cellSpan / manifest.scale
    local camera = manifest.cameraVector
    return camera.x - (gridX + 0.5) * span, camera.y + (gridY + 0.5) * span
end

function Skybox:DrawEdgeTerrain(manifest, fogColor)
    local meshes = self.EdgeMeshes
    if not meshes or not self.CurrentGridX then return end
    local red, green, blue = (fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255
    local brightness = math.Clamp((red * 0.3 + green * 0.59 + blue * 0.11) * 1.6, 0.25, 1)
    local x, y = self:GetEdgeTranslation(manifest, self.CurrentGridX, self.CurrentGridY)
    edgeTerrain.translation:SetUnpacked(x, y, 0)
    edgeTerrain.matrix:SetTranslation(edgeTerrain.translation)
    cam.PushModelMatrix(edgeTerrain.matrix)
    local color = edgeTerrain.color
    color:SetUnpacked(Lerp(0.1, brightness, red), Lerp(0.1, brightness, green), Lerp(0.1, brightness, blue))
    // Overlays sit on identical geometry; a growing window-space depth bias keeps each layer in front of the last.
    for layer, kind in ipairs(edgeTerrain.kinds) do
        local list = meshes[kind]
        if #list > 0 then
            local material = edgeTerrain.materials[kind]
            material:SetVector("$color", color)
            render.SetMaterial(material)
            render.DepthRange(0, 1 - (layer - 1) * edgeTerrain.layerDepthBias)
            drawCoastMeshes(list)
        end
    end
    local snow = self.Stats.snowAlpha or 0
    if snow > 0.002 then
        local cover = edgeTerrain.coverMaterial
        cover:SetVector("$color", color)
        cover:SetFloat("$alpha", snow * 0.9)
        render.SetMaterial(cover)
        render.DepthRange(0, 1 - (#edgeTerrain.kinds) * edgeTerrain.layerDepthBias)
        drawCoastMeshes(meshes.grass)
    end
    render.DepthRange(0, 1)
    cam.PopModelMatrix()
    self.Stats.edgeDraws = (self.Stats.edgeDraws or 0) + 1
end

// Pure-function regression for the cardinal contract: classification of all four edges and corners, landform
// character, seam continuity, the west shore height, east-range visibility from the far west, and sky-space direction.
function Skybox:RunEdgeRegression()
    local manifest = self.Manifest
    local data = ZM_World and ZM_World:GetData()
    local grid = data and data.world and data.world.grid
    local width, height = tonumber(grid and grid[1]), tonumber(grid and grid[2])
    local results, failures = {}, 0
    local function check(name, passed, detail)
        table.insert(results, { name = name, passed = passed and true or false, detail = detail })
        if not passed then failures = failures + 1 end
    end
    if not manifest or not width or not height then
        check("prerequisites", false, "skybox manifest or world grid missing")
        return results, failures
    end
    local span = manifest.cellSpan / manifest.scale
    local W, H = width * span, height * span
    local midX, midY = math.floor(width / 2), math.floor(height / 2)
    local expected = {
        { "north", midX, -1, "hills" }, { "east", width, midY, "mountains" }, { "south", midX, height, "flatlands" },
        { "west", -1, midY, "ocean" }, { "northeast", width, -1, "hills-mountains" },
        { "southeast", width, height, "mountains-flatlands" }, { "northwest", -1, -1, "ocean" },
        { "southwest", -1, height, "ocean" }, { "center", midX, midY, "city" }
    }
    for _, case in ipairs(expected) do
        local actual = Skybox.ClassifyEdge(case[2], case[3], width, height)
        check("classify " .. case[1], actual == case[4], string.format("(%d,%d) -> %s, expected %s", case[2], case[3], actual, case[4]))
    end
    local function heightAt(u, v) return Skybox.EdgeHeight(u, v, W, H, span) end
    local function meanHeight(side)
        local total, samples = 0, 0
        for step = 1, 24 do
            local along = (step - 0.5) / 24
            local u, v
            if side == "north" then u, v = W * along, -600 elseif side == "south" then u, v = W * along, H + 600 else u, v = W + 1500, H * along end
            total, samples = total + heightAt(u, v), samples + 1
        end
        return total / samples
    end
    local north, east, south = meanHeight("north"), meanHeight("east"), meanHeight("south")
    check("landform east mountains", east > 250, string.format("mean %.1f", east))
    check("landform north hills", north > 12 and north < 110, string.format("mean %.1f", north))
    check("landform south flatlands", south > 1.5 and south < 9, string.format("mean %.1f", south))
    check("landform ordering", east > north and north > south, string.format("east %.1f north %.1f south %.1f", east, north, south))
    local worst = 0
    for step = 0, 40 do
        local t = step / 40
        worst = math.max(worst, math.abs(heightAt(W * t, 0) - 2), math.abs(heightAt(W * t, H) - 2),
            math.abs(heightAt(W, H * t) - 2))
    end
    check("city boundaries at street height", worst < 0.01, string.format("max deviation %.4f", worst))
    local seam = 0
    for step = 1, 40 do
        local depth = step * 40
        seam = math.max(seam, math.abs(heightAt(W - 0.001, -depth) - heightAt(W + 0.001, -depth)),
            math.abs(heightAt(W - 0.001, H + depth) - heightAt(W + 0.001, H + depth)),
            math.abs(heightAt(W + depth, -0.001) - heightAt(W + depth, 0.001)),
            math.abs(heightAt(W + depth, H - 0.001) - heightAt(W + depth, H + 0.001)))
    end
    check("corner seams continuous", seam < 0.5, string.format("max step %.3f", seam))
    local shoreTarget = coast.seaLevel + coast.duneHeight
    local shore = math.max(math.abs(heightAt(0, -400) - shoreTarget), math.abs(heightAt(0, H + 400) - shoreTarget))
    check("west shore meets beach height", shore < 0.01, string.format("max deviation %.4f", shore))
    // The far-west cell (eye about 4 sky units up) must see the east range above the opaque horizon (-2 degrees).
    local best = -90
    for step = 0, 60 do
        for depth = 200, 2400, 100 do
            local u, v = W + depth, H * step / 60
            local distance = math.sqrt((u - span * 0.5) ^ 2 + (v - H * 0.5) ^ 2)
            best = math.max(best, math.deg(math.atan2(heightAt(u, v) - 4, distance)))
        end
    end
    check("east range visible from far west", best > 2, string.format("peak elevation %.2f deg", best))
    local camera = manifest.cameraVector
    local x, y = self:GetEdgeTranslation(manifest, midX, midY)
    local eastX = x + W + 100
    local northY = y + 100
    check("sky direction east is +X", eastX > camera.x + span, string.format("east sky x %.1f vs camera %.1f", eastX, camera.x))
    check("sky direction north is +Y", northY > camera.y + span, string.format("north sky y %.1f vs camera %.1f", northY, camera.y))
    // Sky fog must continue the city fog: never clearer at the cell boundary, and at least the city maximum beyond.
    if self.Manifest and self.Stats.state == "ready" then
        local boundary = ZM_SkyboxGeometry.GetFogBoundary(self.Manifest)
        local function density(fog, distance)
            return fog.maxDensity * math.Clamp((distance - fog.start) / math.max(fog.finish - fog.start, 1), 0, 1)
        end
        local worst = math.huge
        for _, world in ipairs({ { start = 800, finish = 3000, maxDensity = 0.65 }, { start = 600, finish = 2200, maxDensity = 0.72 },
            { start = 350, finish = 1450, maxDensity = 0.82 }, { start = 200, finish = 950, maxDensity = 0.9 },
            { start = 900, finish = 3000, maxDensity = 0.5 }, { start = 0, finish = 900, maxDensity = 1 } }) do
            local sky = self:GetSkyboxFog(world)
            for _, distance in ipairs({ boundary, boundary * 2, boundary * 3 }) do
                worst = math.min(worst, density(sky, distance) - density(world, distance))
            end
        end
        check("sky fog never clearer than city fog", worst > -0.01, string.format("worst sky-minus-city density %.4f", worst))
    end
    local saved = { level = self.SceneryLight.level, self.SceneryLight[1], self.SceneryLight[2], self.SceneryLight[3] }
    local bright = self:UpdateSceneryLight({ [5] = Vector(0.79, 0.87, 0.97) })
    local brightTint = math.min(bright[1], bright[2], bright[3])
    local dark = self:UpdateSceneryLight({ [5] = Vector(0.226, 0.277, 0.132) })
    local darkLevel = dark.level
    self.SceneryLight.level, self.SceneryLight[1], self.SceneryLight[2], self.SceneryLight[3] = saved.level, saved[1], saved[2], saved[3]
    self.Stats.sceneryLight = math.Round(saved.level, 3)
    check("daylight cells keep profile fog colour", brightTint > 0.999, string.format("min tint %.3f", brightTint))
    check("dark cells darken fog", darkLevel < 0.7, string.format("level %.3f", darkLevel))
    return results, failures
end

// Builds the horizon wall around the origin, in sky units; it is translated to the sky eye when drawn.
function Skybox:BuildDome(radius, skyline)
    local haze = math.Clamp(getConVarNumber("zombiesim_sky_horizon_haze", 0.5), 0, 1.5)
    if self.DomeMesh and self.DomeRadius == radius and self.DomeSkyline == skyline and self.DomeHaze == haze then return end
    if self.DomeMesh then self.DomeMesh:Destroy() end
    self.DomeMesh = nil
    self.DomeRadius = radius
    self.DomeSkyline = skyline
    self.DomeHaze = haze
    local rings = skyline and skylineDomeRings or domeRings

    local quads = domeSegments * (#rings - 1)
    if quads <= 0 then return end
    local ringZ = {}
    for index, ring in ipairs(rings) do
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
    for ringIndex = 1, #rings - 1 do
        local lowZ, highZ = ringZ[ringIndex], ringZ[ringIndex + 1]
        local lowAlpha = math.min(1, rings[ringIndex].alpha * (rings[ringIndex].elevation >= 0 and haze or 1)) * 255
        local highAlpha = math.min(1, rings[ringIndex + 1].alpha * (rings[ringIndex + 1].elevation >= 0 and haze or 1)) * 255
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
    local result = self.FogResult
    result.color = settings.color
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

function Skybox:BuildActivitySites(manifest, gridX, gridY, radius)
    local candidates = {}
    local facadeCandidates = {}
    local reach = math.min(8, manifest.skylineRadius or radius)
    for dy = -reach, reach do
        for dx = -reach, reach do
            if math.max(math.abs(dx), math.abs(dy)) >= 1 then
                local cell = ZM_World:GetCell(gridX + dx, gridY + dy)
                local detail = cell and manifest.detail and manifest.detail.recipes and manifest.detail.recipes[mapBasename(cell.map)]
                local rows = detail and detail.fires
                if math.max(math.abs(dx), math.abs(dy)) >= 2 and type(rows) == "table" and #rows > 0 then
                    local seed = fireHash(gridX + dx, gridY + dy, 1, 41)
                    local row = rows[math.min(#rows, math.floor(seed * #rows) + 1)]
                    local position = manifest.cameraVector + Vector(dx * manifest.cellSpan + row[1],
                        -dy * manifest.cellSpan + row[2], row[3]) / manifest.scale
                    candidates[#candidates + 1] = { position = position, seed = seed, distance = dx * dx + dy * dy, x = dx, y = dy }
                end
                local paths = cell and manifest.towers and manifest.towers[mapBasename(cell.map)]
                for _, path in ipairs(type(paths) == "table" and paths or {}) do
                    facadeCandidates[#facadeCandidates + 1] = { path = path, x = dx, y = dy, distance = dx * dx + dy * dy }
                end
            end
        end
    end
    local function compareSites(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return (a.path or "") < (b.path or "")
    end
    table.sort(candidates, compareSites)
    table.sort(facadeCandidates, compareSites)
    for _, candidate in ipairs(facadeCandidates) do
        if #self.FacadeFires >= 8 then break end
        local anchors = self:GetFacadeAnchors(candidate.path)
        if #anchors > 0 then
            local seed = fireHash(gridX + candidate.x, gridY + candidate.y, 1, 53)
            local anchor = anchors[math.min(#anchors, math.floor(seed * #anchors) + 1)]
            local origin = manifest.cameraVector + Vector(candidate.x * manifest.cellSpan, -candidate.y * manifest.cellSpan, 0) / manifest.scale
            self.FacadeFires[#self.FacadeFires + 1] = {
                position = origin + anchor, style = fireStyles[2], phase = seed
            }
        end
    end
    for index = 1, math.min(24, #candidates) do
        self.ActivitySites[index] = candidates[index]
    end
    self.Stats.activitySites = #self.ActivitySites
    self.Stats.facadeFires = #self.FacadeFires
end

// Exported tower models have an identity root and already contain recipe transforms and sky scaling.
// Use real wall triangles, not bounding boxes, which float outside stepped upper storeys.
function Skybox:GetFacadeAnchors(path)
    if self.FacadeAnchors[path] then return self.FacadeAnchors[path] end
    local anchors = {}
    self.FacadeAnchors[path] = anchors
    local meshes = util.GetModelMeshes(path, 0)
    if type(meshes) ~= "table" then
        ErrorNoHalt("[ZombieSim] Cannot read tower facade mesh: " .. path .. "\n")
        return anchors
    end
    for _, part in ipairs(meshes) do
        local triangles = part.triangles or {}
        for index = 1, #triangles - 2, 3 do
            local a, b, c = triangles[index], triangles[index + 1], triangles[index + 2]
            local low = math.min(a.pos.z, b.pos.z, c.pos.z)
            local high = math.max(a.pos.z, b.pos.z, c.pos.z)
            if math.abs(a.normal.z) < 0.2 and high - low >= 24 then
                local centre = (a.pos + b.pos + c.pos) / 3
                if centre.z > 32 then
                    anchors[#anchors + 1] = centre + a.normal * 1.5
                end
            end
        end
    end
    if #anchors == 0 then
        ErrorNoHalt("[ZombieSim] No tall vertical facade triangles in tower: " .. path .. "\n")
    end
    return anchors
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
local tracerStart, tracerEnd = Vector(), Vector()
local tracerColor = Color(255, 187, 94)

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

function Skybox:DrawActivity(manifest, skyEye, skyFog, fogColor)
    local stats = self.Stats
    stats.activityExplosions, stats.activityBursts, stats.activityBeams = 0, 0, 0
    stats.activityPreview = false
    if getConVarNumber("zombiesim_sky_fires", 1) <= 0 or not self.ViewForward or not self.ViewRight or not self.ViewUp or
        (ZM_WorldMap and ZM_WorldMap.Capturing) or (skyFog and skyFog.finish <= ZM_SkyboxGeometry.GetFogBoundary(manifest)) then return end
    local now = CurTime()
    local preview = (self.ActivityPreviewUntil or 0) > now
    local visible = self.ActivityVisible
    local count, explosions, bursts = 0, 0, 0
    for _, site in ipairs(self.ActivitySites) do
        local position = site.position
        local dx, dy, dz = position.x - skyEye.x, position.y - skyEye.y, position.z - skyEye.z
        if dx * self.ViewForward.x + dy * self.ViewForward.y + dz * self.ViewForward.z > 0 then
            local cycleTime = now + site.seed * 24
            local cycle = math.floor(cycleTime / 24)
            local age = cycleTime % 24
            local burst = fireHash(site.x, site.y, cycle, 47) > 0.55
            local scheduled = fireHash(site.x, site.y, cycle, 43) < 0.4
            if preview then
                age = (now - self.ActivityPreviewStart) % 4
                burst = count % 2 == 1
                scheduled = true
            end
            if scheduled and age < (burst and 1.65 or 4) and (burst and bursts < 2 or not burst and explosions < 2) then
                count = count + 1
                local entry = visible[count] or {}
                visible[count] = entry
                entry.position, entry.age, entry.burst, entry.seed = position, age, burst, site.seed
                if burst then bursts = bursts + 1 else explosions = explosions + 1 end
                if count >= (preview and 2 or 4) then break end
            end
        end
    end
    for index = count + 1, #visible do visible[index] = nil end
    stats.activityPreview = preview
    stats.activityExplosions, stats.activityBursts = explosions, bursts
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(self:GetFogEdge(manifest) / manifest.scale)
    render.FogEnd(9 * manifest.cellSpan * math.sqrt(2) / manifest.scale)
    render.FogMaxDensity(math.Clamp(getConVarNumber("zombiesim_sky_tower_fog", 0.8), 0, 1))
    render.FogColor(fogColor[1], fogColor[2], fogColor[3])
    self:DrawFires(skyEye, true)
    local right, up = self.ViewRight, self.ViewUp
    if count > 0 then
        render.SetMaterial(glowMaterial)
        mesh.Begin(MATERIAL_QUADS, count)
        for _, entry in ipairs(visible) do
            local p, age = entry.position, entry.age
            local pulse = entry.burst and math.max(0, 1 - (age % 0.24) / 0.1) or math.max(0, 1 - age / 0.8)
            emitBillboard(p.x, p.y, p.z + 2, entry.burst and 4 or 12 + age * 10, 1, 0, right, up, 255, 165, 65, pulse * 220)
        end
        mesh.End()
    end
    if explosions > 0 then
        render.SetMaterial(smokeMaterial)
        mesh.Begin(MATERIAL_QUADS, explosions * 3)
        for _, entry in ipairs(visible) do
            if not entry.burst then
                local p, age = entry.position, entry.age
                local alpha = smoothstep(0, 0.35, age) * (1 - age / 4) * 160
                for puff = 1, 3 do
                    emitBillboard(p.x + smokeDriftX * age * 6, p.y + smokeDriftY * age * 6,
                        p.z + age * 15 + puff * 4, 5 + age * 5 + puff, 1, 0, right, up, 45, 40, 35, alpha)
                end
            end
        end
        mesh.End()
    end
    if bursts > 0 then
        render.SetMaterial(tracerMaterial)
        for _, entry in ipairs(visible) do
            if entry.burst then
                for shot = 0, 3 do
                    local age = entry.age - shot * 0.24
                    if age >= 0 and age < 0.9 then
                        local p = entry.position
                        local drift = (entry.seed - 0.5) * age * 90
                        // Art ceiling below the existing 512-sky-unit room roof, including rooftop launch sites.
                        local velocity = math.max(0, math.min(420, (manifest.cameraVector.z + 460 - p.z - 2) / 0.9))
                        local height = age * velocity
                        tracerStart:SetUnpacked(p.x + drift, p.y + drift * 0.4, p.z + math.max(2, height - 32))
                        tracerEnd:SetUnpacked(p.x + drift + 2, p.y + drift * 0.4, p.z + height + 2)
                        tracerColor.a = (1 - age / 0.9) * 220
                        render.DrawBeam(tracerStart, tracerEnd, 0.8, 0, 1, tracerColor)
                        stats.activityBeams = stats.activityBeams + 1
                    end
                end
            end
        end
    end
    if skyFog then
        render.FogStart(skyFog.start / manifest.scale)
        render.FogEnd(skyFog.finish / manifest.scale)
        render.FogMaxDensity(skyFog.maxDensity)
    else
        render.FogMode(MATERIAL_FOG_NONE)
    end
end

// Burning wrecks and rooftops: rising, spreading smoke plumes drifting with the clouds, flickering flames at the base.
function Skybox:DrawFires(skyEye, facade)
    local stats = self.Stats
    if not facade then
        stats.frameFires = 0
        stats.smokeQuads = 0
        stats.fireQuads = 0
    end
    local fires = facade and self.FacadeFires or self.Fires
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
    stats.frameFires = stats.frameFires + #fires
    stats.smokeQuads = stats.smokeQuads + count

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
    stats.fireQuads = stats.fireQuads + flames + #fires
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
    local fogColor = settings and settings.color or defaultFogColor
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
    self:DrawFires(skyEye)
    self:DrawActivity(manifest, skyEye, skyFog, fogColor)
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

function Skybox:GetDiagnosticSnapshot()
    local stats = self.Stats
    local manifest = self.Manifest
    return {
        state = stats.state,
        profile = self.ManifestProfile,
        manifestError = self.ManifestError,
        recipes = manifest and manifest.recipeCount,
        scale = manifest and manifest.scale,
        manifestSchema = manifest and manifest.schemaVersion,
        neighbourPitch = manifest and manifest.cellSpan,
        coastContactHalfExtent = manifest and ZM_SkyboxGeometry.GetFogBoundary(manifest),
        templatePlanSha256 = manifest and manifest.templatePlanSha256,
        grid = stats.grid,
        radius = stats.radius,
        neighbourCells = stats.neighbourCells,
        placements = stats.placements,
        missingRecipes = stats.missingRecipes,
        missingModels = stats.missingModels,
        firstModelCheck = stats.firstModelCheck,
        frameModels = stats.frameModels,
        towerPlacements = stats.towerPlacements,
        missingTowerModels = stats.missingTowerModels,
        frameTowers = stats.frameTowers,
        skylineHorizon = self.DomeSkyline,
        towerFogMaxDensity = math.Clamp(getConVarNumber("zombiesim_sky_tower_fog", 0.8), 0, 1),
        towerFogPaleness = self.Stats.towerFogPaleness,
        towerFogStart = self.Stats.towerFogStart,
        towerFogEnd = self.Stats.towerFogEnd,
        towerFogAppliedMaxDensity = self.Stats.towerFogMaxDensity,
        tuning = self:GetTuningSnapshot(),
        activitySites = stats.activitySites,
        activityExplosions = stats.activityExplosions,
        activityBursts = stats.activityBursts,
        activityBeams = stats.activityBeams,
        activityPreview = stats.activityPreview,
        facadeFires = stats.facadeFires,
        tracerMaterialError = tracerMaterial:IsError(),
        towerCandidates = stats.towerCandidates,
        towerBudget = stats.towerBudget,
        omittedTowerModels = stats.omittedTowerModels,
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
        fogMaxDensity = stats.fogMaxDensity,
        fogBoundaryDensity = stats.fogBoundaryDensity,
        sceneryLight = stats.sceneryLight,
        lastDrawAge = stats.lastDraw and (RealTime() - stats.lastDraw) or nil,
        domeMaterialError = domeMaterial:IsError(),
        cloudMaterialError = cloudMaterial:IsError(),
        cloudTextureWidth = cloudMaterial:GetTexture("$basetexture") and cloudMaterial:GetTexture("$basetexture"):Width() or 0,
        coastSeaQuads = stats.coastSeaQuads,
        coastWallQuads = stats.coastWallQuads,
        coastFoamQuads = stats.coastFoamQuads,
        coastSandQuads = stats.coastSandQuads,
        coastRockQuads = stats.coastRockQuads,
        coastMeshes = stats.coastMeshes,
        coastBuildMs = stats.coastBuildMs,
        edgeTerrainQuads = stats.edgeTerrainQuads,
        edgeTerrainMeshes = stats.edgeTerrainMeshes,
        edgeBuildMs = stats.edgeBuildMs,
        edgeDraws = stats.edgeDraws,
        edgeMaterialErrors = (edgeTerrain.grassMaterial:IsError() and 1 or 0) + (edgeTerrain.rockMaterial:IsError() and 1 or 0) +
            (edgeTerrain.snowMaterial:IsError() and 1 or 0),
        coastTexturesReady = coast.texturesReady,
        coastDraws = stats.coastDraws,
        seaMaterialError = seaMaterial:IsError(),
        sandMaterialError = coast.sandMaterial:IsError(),
        sandTextureWidth = coast.sandMaterial:GetTexture("$basetexture") and coast.sandMaterial:GetTexture("$basetexture"):Width() or 0,
        rockMaterialError = coast.rockMaterial:IsError(),
        rockTextureWidth = coast.rockMaterial:GetTexture("$basetexture") and coast.rockMaterial:GetTexture("$basetexture"):Width() or 0,
        embankmentMaterialError = coast.embankmentMaterial:IsError(),
        embankmentTextureWidth = coast.embankmentMaterial:GetTexture("$basetexture") and coast.embankmentMaterial:GetTexture("$basetexture"):Width() or 0,
        rippleMaterialError = coast.rippleMaterial:IsError(),
        foamTextureWidth = coast.foamTexture and coast.foamTexture:Width() or 0,
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

hook.Add("PostDrawOpaqueRenderables", "ZM.Skybox.Draw", function(drawingDepth, _, drawing3DSkybox)
    if drawingDepth or not drawing3DSkybox then return end
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    Skybox:Draw()
end)

hook.Add("ShutDown", "ZM.Skybox.Cleanup", function()
    Skybox:RemoveModels()
    Skybox:DestroyCoast()
    Skybox:DestroyEdgeTerrain()
end)

concommand.Add("zombiesim_skybox_status", function()
    local snapshot = Skybox:GetDiagnosticSnapshot()
    local keys = table.GetKeys(snapshot)
    table.sort(keys)
    for _, key in ipairs(keys) do
        print(string.format("[ZombieSim] Skybox %s = %s", key, tostring(snapshot[key])))
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
