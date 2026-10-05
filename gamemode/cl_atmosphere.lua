// Client-local world fog and colour correction driven by the logical cell's compact profile id.
ZM_Atmosphere = ZM_Atmosphere or {}
local Atmosphere = ZM_Atmosphere

Atmosphere.ActiveProfileIndex = Atmosphere.ActiveProfileIndex or nil
Atmosphere.StormIntensity = Atmosphere.StormIntensity or 0
Atmosphere.Weather = Atmosphere.Weather or "clear"
Atmosphere.PendingProfileIndex = Atmosphere.PendingProfileIndex or nil
Atmosphere.PendingPlayerProfileSource = Atmosphere.PendingPlayerProfileSource or nil
Atmosphere.LastApplySource = Atmosphere.LastApplySource or "none"
Atmosphere.ProfileApplications = Atmosphere.ProfileApplications or {}
Atmosphere.LastProfileReceive = Atmosphere.LastProfileReceive or nil
Atmosphere.HookResults = Atmosphere.HookResults or {}
Atmosphere.BoundaryMistActive = Atmosphere.BoundaryMistActive or false

CreateClientConVar("zombiesim_atmosphere_grain", "0", true, false, "Enables subtle animated film grain.")
local rainDensityConVar = CreateClientConVar("zombiesim_atmosphere_rain_density", "1.5", true, false,
    "Client rain particle density multiplier (0.5 to 2).")
local puddleOpacityConVar = CreateClientConVar("zombiesim_atmosphere_puddle_opacity", "0.15", true, false,
    "Client rain puddle opacity (0.05 to 0.45).")
local puddleAmountConVar = CreateClientConVar("zombiesim_atmosphere_puddle_amount", "1", true, false,
    "Client rain puddle amount multiplier (0.5 to 3).")

local weatherEmitter
local boundaryEmitter
local nextWeatherParticleAt = 0
local nextBoundaryParticleAt = 0
local nextShelterCheckAt = 0
local nextPuddleAt = 0
local puddleSiteDebt = 0
local puddleSites = Atmosphere.PuddleSites or {}
Atmosphere.PuddleSites = puddleSites
local puddleSiteMap = Atmosphere.PuddleSiteMap
local puddleSiteCursor = Atmosphere.PuddleSiteCursor or 1
local puddleWorldMinimum = Atmosphere.PuddleWorldMinimum
local puddleWorldMaximum = Atmosphere.PuddleWorldMaximum
local isSheltered
local nextGrainUpdateAt = 0
local grainRects = {}
local grainSeed = 0
local weatherDiagnostics = {}
local puddles = Atmosphere.WetPuddles or {}
Atmosphere.WetPuddles = puddles
local splashRings = {}
local rainSoundPath = "ambient/weather/rumble_rain.wav"
local puddleSloshSoundPaths = {
    "player/footsteps/slosh1.wav",
    "player/footsteps/slosh2.wav",
    "player/footsteps/slosh3.wav",
    "player/footsteps/slosh4.wav"
}
local snowStepSoundPaths = {
    "player/footsteps/snow1.wav",
    "player/footsteps/snow2.wav",
    "player/footsteps/snow3.wav",
    "player/footsteps/snow4.wav",
    "player/footsteps/snow5.wav",
    "player/footsteps/snow6.wav"
}
local windSoundPath = "ambient/wind/wasteland_wind.wav"
local windGustSoundPaths = {
    "ambient/wind/windgust.wav",
    "ambient/wind/windgust_strong.wav",
    "ambient/wind/wind_snippet1.wav",
    "ambient/wind/wind_snippet2.wav",
    "ambient/wind/wind_snippet3.wav"
}
local winterBlendSeconds = 3
// Snow cover settles patchily over about 3 minutes of snowfall, melts over 25 s when clear and 8 s in rain. The
// server owns the amount (sv_atmosphere.lua uses the same rates); the client only evolves it between syncs.
local snowCoverBuildSeconds = 180
local snowCoverMeltSeconds = 25
local snowCoverRainMeltSeconds = 8
// Coverage is baked into the vertices in discrete stages; each stage change rebuilds the chunks a few per frame.
local snowCoverStages = 48
local snowCoverTargetPoints = 40000
local snowCoverMinimumSpacing = 28
local snowCoverPointsPerFrame = 300
local snowCoverMaxStep = 6
local snowCoverChunkQuads = 16
local snowCoverChunksPerFrame = 6
local snowCoverRebuildsPerFrame = 4
// Snow sampling, chunk meshing, chunk re-bakes and the puddle site scan share one per-frame time budget.
// Each step always makes at least one unit of progress; the per-frame counts above remain upper caps.
local atmosphereWorkBudgetSeconds = 0.0015
// The loading screen hides a fresh map, so the preload may spend most of each frame building the cover.
local atmospherePreloadWorkBudgetSeconds = 0.05
// Chunks are drawn only inside a slightly widened view cone, and not beyond an opaque fog end.
local snowCoverCullConeMargin = math.rad(6)
local snowCoverFogCullDistance = nil
// While the loading screen hides a fresh map, the cover is built much faster and the fade-in waits for it.
local snowPreloadPointsPerFrame = 4000
local snowPreloadChunksPerFrame = 40
local snowPreloadWindowSeconds = 15
local snowPreloadMaxSeconds = 12
local snowCarveRadius = 34
local snowCarveInterval = 10
local snowFootprintFillSeconds = 150
// Refilling footprints only re-bake when a point's depth crosses one of these steps; the refill runs once per
// step so each pass re-bakes every trodden chunk once instead of a few points' chunks every 3 s.
local snowTrailRefillSteps = 12
local snowTrailRefillInterval = snowFootprintFillSeconds / snowTrailRefillSteps
local snowCover = Atmosphere.SnowCover or { status = "not built" }
Atmosphere.SnowCover = snowCover

local atmosphereWorkFrame = -1
local atmosphereWorkDeadline = 0

local function getAtmosphereWorkDeadline()
    local frame = FrameNumber()
    if frame ~= atmosphereWorkFrame then
        atmosphereWorkFrame = frame
        local budget = snowCover.preloadStep ~= nil and atmospherePreloadWorkBudgetSeconds or atmosphereWorkBudgetSeconds
        atmosphereWorkDeadline = SysTime() + budget
    end
    return atmosphereWorkDeadline
end
Atmosphere.SessionStart = Atmosphere.SessionStart or SysTime()
// Until the server's weather sync arrives, the last known state (saved by this client) lets a new map start
// building the settled cover behind the loading screen straight away.
if Atmosphere.SnowCoverAmount == nil then
    Atmosphere.SnowCoverAmount = math.Clamp(tonumber(cookie.GetString("zombiesim_snow_cover", "0")) or 0, 0, 1)
    Atmosphere.CachedWeather = cookie.GetString("zombiesim_weather", "clear")
end
local snowFloorMaterial = Material("nature/snowfloor001a")
local snowFloorTexture = not snowFloorMaterial:IsError() and snowFloorMaterial:GetTexture("$basetexture") or nil
if snowFloorTexture and snowFloorTexture:IsError() then
    snowFloorTexture = nil
end
// The texture is named in the material's key values: a texture swapped in after creation did not survive fresh
// map loads (the cover rendered flat white), so the draw also re-applies it if the material lost it.
local snowCoverMaterial = CreateMaterial("zombiesim_atmosphere_snow_cover_v3", "UnlitGeneric", {
    ["$basetexture"] = snowFloorTexture and snowFloorTexture:GetName() or "color/white",
    ["$translucent"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
    ["$nocull"] = "1",
    ["$alpha"] = "1"
})
local snowCoverMeshVersion = 8
local snowCoverLift = 4
local frostEdgeStrips = 18
Atmosphere.WinterBlend = Atmosphere.WinterBlend or 0
Atmosphere.FrostAmount = Atmosphere.FrostAmount or 0
Atmosphere.StepCount = Atmosphere.StepCount or 0
Atmosphere.BreathPuffs = Atmosphere.BreathPuffs or 0
local nextWindGustAt = 0
local stepDistance = 0
local lastStepPosition
// Refract ignores vertex alpha, so puddles use an alpha-blended wet-darkening pass plus a faint additive sheen.
local puddleMaterial = CreateMaterial("zombiesim_atmosphere_puddle_wet_v3", "UnlitGeneric", {
    ["$basetexture"] = "color/white",
    ["$translucent"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
    ["$nocull"] = "1"
})
local puddleSheenMaterial = CreateMaterial("zombiesim_atmosphere_puddle_sheen_v3", "UnlitGeneric", {
    ["$basetexture"] = "color/white",
    ["$additive"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
    ["$nocull"] = "1"
})
// Additive envmap-only pass: a black base leaves just the mounted HL2 outdoor water cubemap,
// sampled along the view reflection vector so the water reflects the sky and shifts with the camera.
local puddleReflectionMaterial = CreateMaterial("zombiesim_atmosphere_puddle_reflect_v1", "UnlitGeneric", {
    ["$basetexture"] = "color/white",
    ["$color"] = "[0 0 0]",
    ["$envmap"] = "environment maps/water_wasteland05",
    ["$envmaptint"] = "[0.42 0.44 0.46]",
    ["$additive"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
    ["$nocull"] = "1"
})
if puddleReflectionMaterial:IsError() then
    puddleReflectionMaterial = nil
end
local boundaryMistMaterial = Material("particle/particle_smokegrenade")
local boundaryMistTexture = boundaryMistMaterial:GetTexture("$basetexture")
if puddleMaterial:IsError() or puddleSheenMaterial:IsError() then
    ErrorNoHalt("[ZombieSim] Could not initialize the puddle materials.\n")
    puddleMaterial = nil
end
local puddleBaseTexture = Material("color/white"):GetTexture("$basetexture")
if boundaryMistMaterial:IsError() then
    ErrorNoHalt("[ZombieSim] Mounted transition-mist material is unavailable.\n")
end
local splashRingMaterial = Material("effects/select_ring")
if splashRingMaterial:IsError() then
    ErrorNoHalt("[ZombieSim] Mounted splash ring material is unavailable.\n")
end
Atmosphere.FootstepSplashMaterial = Material("effects/splash2")
if Atmosphere.FootstepSplashMaterial:IsError() then
    ErrorNoHalt("[ZombieSim] Mounted footstep splash material is unavailable.\n")
end
local basePuddleSites = 64
local puddleSiteCapacity = 192
local maxPuddleLobes = 8
local maxPuddleMeshLobes = 64
local puddleSiteInterval = 0.55
local puddleSiteCycleTicks = 64
local puddleMatureSeconds = 240
local puddleFlatTolerance = 6

local function getPuddleAmount()
    return math.Clamp(puddleAmountConVar:GetFloat(), 0.5, 3)
end

local function getActivePuddleSiteCount()
    return math.Clamp(math.Round(basePuddleSites * getPuddleAmount()), 16, puddleSiteCapacity)
end

local function getPuddleClusterLimit()
    return getActivePuddleSiteCount()
end

local function getVisiblePuddleClusterLimit()
    return math.Clamp(math.Round(14 * getPuddleAmount()), 8, 32)
end

local function getVisiblePuddleLobeLimit()
    return math.Clamp(math.Round(32 * getPuddleAmount()), 16, maxPuddleMeshLobes)
end
local puddleLifetime = 60
local puddleMeshSegments = 32
// Lobes beyond this distance draw every second outline segment; the outline points themselves are unchanged.
local puddleMeshLodDistanceSqr = 900 * 900
local puddleProbeDirections = {
    Vector(1, 0, 0),
    Vector(0.707, 0.707, 0),
    Vector(0, 1, 0),
    Vector(-0.707, 0.707, 0),
    Vector(-1, 0, 0),
    Vector(-0.707, -0.707, 0),
    Vector(0, -1, 0),
    Vector(0.707, -0.707, 0)
}

local function getNumber(value, fallback)
    value = tonumber(value)
    return value and value or fallback
end

local function getExpectedCell(player)
    if not ZM_World:IsLoaded() or not IsValid(player) then
        return nil
    end

    local cellX = player.CellX
    local cellY = player.CellY
    if cellX == nil then cellX = player:GetNWInt("CellX", 0) end
    if cellY == nil then cellY = player:GetNWInt("CellY", 0) end
    local gridX, gridY = ZM_World:GetGridCoordinates(cellX, cellY)
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    if not cell then
        return nil
    end

    return {
        cellX = cellX,
        cellY = cellY,
        gridX = gridX,
        gridY = gridY,
        profileIndex = cell.atmosphereProfile
    }
end

local function getProfileId(profileIndex)
    local profile = ZM_World:GetAtmosphereProfileByIndex(profileIndex)
    return profile and (profile.id or profile.name) or nil
end

local function recordHookResult(name, returned, applied, settings, scale, reason, correction)
    local result = Atmosphere.HookResults[name] or {}
    result.time = RealTime()
    result.returned = returned
    result.applied = applied
    result.profileIndex = Atmosphere.ActiveProfileIndex
    result.profileId = getProfileId(Atmosphere.ActiveProfileIndex)
    result.worldDataLoaded = ZM_World:IsLoaded()
    result.scale = scale
    result.reason = reason
    result.colorCorrection = correction
    if settings then
        local fog = result.fog or {}
        fog.start = settings.start
        fog.finish = settings.finish
        fog.maxDensity = settings.maxDensity
        fog.color = settings.color
        result.fog = fog
    else
        result.fog = nil
    end
    Atmosphere.HookResults[name] = result
end

local function recordProfileApplication(profileIndex, source, applied)
    local expected = getExpectedCell(LocalPlayer())
    local history = Atmosphere.ProfileApplications
    history[#history + 1] = {
        time = RealTime(),
        source = tostring(source or "unknown"),
        profileIndex = profileIndex,
        profileId = getProfileId(profileIndex),
        applied = applied,
        worldDataLoaded = ZM_World:IsLoaded(),
        expectedProfileIndex = expected and expected.profileIndex or nil,
        cellX = expected and expected.cellX or nil,
        cellY = expected and expected.cellY or nil
    }
    if #history > 16 then
        table.remove(history, 1)
    end
end

local function getColorComponent(color, index)
    return math.Clamp(getNumber(color and color[index], 0), 0, 255)
end

function Atmosphere:GetActiveProfile()
    return ZM_World:GetAtmosphereProfileByIndex(self.ActiveProfileIndex)
end

Atmosphere.RetiredWeatherEmitters = Atmosphere.RetiredWeatherEmitters or {}

function Atmosphere:SetMapCaptureHidden(hidden)
    self.MapCaptureParticlesHidden = hidden
    if hidden then self.MapCaptureHideCount = (self.MapCaptureHideCount or 0) + 1 end
    if weatherEmitter then weatherEmitter:SetNoDraw(hidden) end
    for _, emitter in ipairs(self.RetiredWeatherEmitters) do
        emitter:SetNoDraw(hidden)
    end
end

function Atmosphere:GetMapCaptureState()
    local amount = self.SnowCoverAmount or 0
    local rebuilding = amount > 0.002 and
        (next(snowCover.dirtyChunks or {}) ~= nil or next(snowCover.urgentChunks or {}) ~= nil)
    return string.format("%s/%d/%s/%s", self.Weather or "clear",
        amount <= 0.002 and 0 or math.max(1, math.Round(amount * 12)),
        snowCover.status or "not built", rebuilding and "rebuilding" or "settled")
end

hook.Add("Think", "ZM.Atmosphere.RetiredWeatherCleanup", function()
    for index = #Atmosphere.RetiredWeatherEmitters, 1, -1 do
        local emitter = Atmosphere.RetiredWeatherEmitters[index]
        if emitter:GetNumActiveParticles() == 0 then
            emitter:Finish()
            table.remove(Atmosphere.RetiredWeatherEmitters, index)
        end
    end
end)

function Atmosphere:StopWeatherEffects()
    if weatherEmitter then
        // Retain draining emitters so map captures can still hide their remaining particles.
        self.RetiredWeatherEmitters[#self.RetiredWeatherEmitters + 1] = weatherEmitter
        weatherEmitter = nil
    end
    if self.RainSoundPatch then
        self.RainSoundPatch:FadeOut(0.6)
        self.RainSoundPatch = nil
    end
    if self.WindSoundPatch then
        self.WindSoundPatch:FadeOut(1.2)
        self.WindSoundPatch = nil
    end
    nextWeatherParticleAt = 0
end

function Atmosphere:StopBoundaryEffects()
    if boundaryEmitter then
        boundaryEmitter:Finish()
        boundaryEmitter = nil
    end
    nextBoundaryParticleAt = 0
    self.BoundaryMistActive = false
end

function Atmosphere:SetWeather(weather)
    if type(weather) ~= "string" then
        ErrorNoHalt("[ZombieSim] Atmosphere received an invalid weather state.\n")
        return false
    end
    weather = string.lower(string.Trim(weather))
    if weather ~= "clear" and weather ~= "rain" and weather ~= "snow" then
        ErrorNoHalt("[ZombieSim] Atmosphere received an unknown weather state: " .. weather .. "\n")
        return false
    end
    if self.Weather ~= weather then
        self:StopWeatherEffects()
    end
    if self.Weather == "rain" and weather ~= "rain" then
        self.PuddlesDryAt = CurTime() + 3
    elseif weather == "rain" then
        self.PuddlesDryAt = nil
    end
    self.Weather = weather
    self.StormIntensity = weather == "rain" and 0.55 or (weather == "snow" and 0.35 or 0)
    self.WeatherChangedAt = CurTime()
    return true
end

function Atmosphere:ApplyProfile(profileIndex, source)
    profileIndex = tonumber(profileIndex)
    if not profileIndex then
        ErrorNoHalt("[ZombieSim] Atmosphere received a non-numeric profile index.\n")
        recordProfileApplication(nil, source, false)
        return false
    end
    local profile = ZM_World:GetAtmosphereProfileByIndex(profileIndex)
    if not profile then
        if not ZM_World:IsLoaded() then
            self.PendingProfileIndex = profileIndex
            self.LastApplySource = tostring(source or "unknown") .. " (waiting for world data)"
        else
            self.PendingProfileIndex = nil
            ErrorNoHalt("[ZombieSim] Unknown atmosphere profile index: " .. tostring(profileIndex) .. "\n")
            if self.LoadingStepId then
                ZM_Loading:Finish(self.LoadingStepId, "fail", "Unknown atmosphere profile " .. profileIndex)
                self.LoadingStepId = nil
            end
        end
        recordProfileApplication(profileIndex, source, false)
        return false
    end

    self.ActiveProfileIndex = math.floor(profileIndex)
    self.PendingProfileIndex = nil
    self.PendingPlayerProfileSource = nil
    self.LastApplySource = source or "unknown"
    recordProfileApplication(self.ActiveProfileIndex, source, true)
    if self.LoadingStepId then
        ZM_Loading:Finish(self.LoadingStepId, "ok", "Applied atmosphere profile " .. self.ActiveProfileIndex)
        self.LoadingStepId = nil
    end
    return true
end

function Atmosphere:ApplyPlayerProfile(source)
    local player = LocalPlayer()
    if not IsValid(player) then
        recordProfileApplication(nil, source, false)
        return false
    end

    if not ZM_World:IsLoaded() then
        self.PendingPlayerProfileSource = source or "player data"
        recordProfileApplication(nil, source, false)
        return false
    end
    self.PendingPlayerProfileSource = nil
    local expected = getExpectedCell(player)
    if not expected then
        recordProfileApplication(nil, source, false)
        return false
    end
    return self:ApplyProfile(expected.profileIndex, source or "player data")
end

// Weather updates set a bounded intensity that blends into the active cell fog profile.
function Atmosphere:SetStormIntensity(intensity)
    self.StormIntensity = math.Clamp(getNumber(intensity, 0), 0, 1)
end

// Fog settings are read by several hooks per frame, so they are computed once per frame into reused tables.
local fogSettingsCache = { color = {} }
local fogWinterColor = {}
local fogSettingsFrame = -1
local fogSettingsResult

function Atmosphere:GetFogSettings()
    local frame = FrameNumber()
    if frame == fogSettingsFrame then
        return fogSettingsResult
    end
    fogSettingsFrame = frame
    local profile = self:GetActiveProfile()
    local fog = profile and profile.fog
    if type(fog) ~= "table" then
        fogSettingsResult = nil
        return nil
    end

    local stormMultiplier = math.Clamp(getNumber(fog.stormMultiplier, 1), 0.1, 1)
    local visibilityMultiplier = 1 + (stormMultiplier - 1) * self.StormIntensity
    local maxDensity = math.Clamp(getNumber(fog.maxDensity, 1), 0, 1)
    local density = math.Clamp(maxDensity + (1 - maxDensity) * self.StormIntensity, 0, 1)
    local color = fog.color
    // Snow pulls the fog toward a pale blue-white and closes it in slightly; eased by WinterBlend.
    local winter = self.WinterBlend or 0
    if winter > 0.001 then
        visibilityMultiplier = visibilityMultiplier * (1 - 0.22 * winter)
        density = math.Clamp(density + (1 - density) * 0.25 * winter, 0, 1)
        fogWinterColor[1] = Lerp(winter * 0.75, getColorComponent(color, 1), 212)
        fogWinterColor[2] = Lerp(winter * 0.75, getColorComponent(color, 2), 222)
        fogWinterColor[3] = Lerp(winter * 0.75, getColorComponent(color, 3), 234)
        color = fogWinterColor
    end
    // Dark-lit cells tint the profile fog by the light measured from the cell's baked lighting, so fogged city and
    // sky scenery darken together instead of washing toward a pale daytime colour.
    local sceneryLight = ZM_Skybox and ZM_Skybox.SceneryLight
    if sceneryLight and (sceneryLight[1] < 0.999 or sceneryLight[2] < 0.999 or sceneryLight[3] < 0.999) then
        local litColor = self.FogLitColor or {}
        self.FogLitColor = litColor
        litColor[1] = getColorComponent(color, 1) * sceneryLight[1]
        litColor[2] = getColorComponent(color, 2) * sceneryLight[2]
        litColor[3] = getColorComponent(color, 3) * sceneryLight[3]
        color = litColor
    end
    local settings = fogSettingsCache
    settings.color = color
    settings.start = math.max(0, getNumber(fog.start, 0) * visibilityMultiplier)
    settings.finish = math.max(1, getNumber(fog["end"], 1) * visibilityMultiplier)
    settings.maxDensity = density
    fogSettingsResult = settings
    return settings
end

function Atmosphere:GetDiagnosticSnapshot()
    local player = LocalPlayer()
    local nearbyPuddleCount = 0
    if IsValid(player) then
        local playerPosition = player:GetPos()
        local nearbyPuddleRadiusSquared = 560 * 560
        for _, puddle in ipairs(puddles) do
            if not puddle.removed and puddle.position:DistToSqr(playerPosition) <= nearbyPuddleRadiusSquared then
                nearbyPuddleCount = nearbyPuddleCount + 1
            end
        end
    end
    local expected = getExpectedCell(player)
    local profile = self:GetActiveProfile()
    local cells = ZM_World:IsLoaded() and ZM_World:GetCellsForMap(game.GetMap()) or nil
    local insideDen = IsValid(player) and ZM_SafeZones:IsPlayerInside(player) or false
    return {
        map = game.GetMap(),
        playerValid = IsValid(player),
        worldDataLoaded = ZM_World:IsLoaded(),
        outdoorCityCellCount = type(cells) == "table" and #cells or 0,
        insideDen = insideDen,
        precipitationEligible = type(cells) == "table" and #cells > 0 and not insideDen,
        weatherDiagnostics = table.Copy(weatherDiagnostics),
        weatherThinkHookRegistered = type((hook.GetTable().Think or {})["ZM.Atmosphere.WeatherEffects"]) == "function",
        wetPuddleThinkHookRegistered = type((hook.GetTable().Think or {})["ZM.Atmosphere.WetPuddles"]) == "function",
        wetSurfaceRenderHookRegistered = type((hook.GetTable().PostDrawTranslucentRenderables or {})["ZM.Atmosphere.WetSurfaceEffects"]) == "function",
        boundaryThinkHookRegistered = type((hook.GetTable().Think or {})["ZM.Atmosphere.BoundaryMist"]) == "function",
        wetPuddleCount = #puddles,
        nearbyPuddleCount = nearbyPuddleCount,
        puddleSitesMap = puddleSiteMap,
        puddleSiteCount = puddleSiteMap == game.GetMap() and #puddleSites or 0,
        puddleSiteCursor = puddleSiteCursor,
        puddleSiteStatus = self.PuddleSiteStatus or "not initialized",
        puddleSiteAttempts = self.PuddleSiteAttempts or 0,
        puddleBoundsSource = self.PuddleBoundsSource,
        puddleUnusableSiteCount = (function()
            local count = 0
            for _, site in ipairs(puddleSites) do
                if site.unusable then count = count + 1 end
            end
            return count
        end)(),
        puddleWorldBoundsAvailable = puddleWorldMinimum ~= nil and puddleWorldMaximum ~= nil,
        puddleWorldBounds = puddleWorldMinimum and puddleWorldMaximum and {
            minX = puddleWorldMinimum.x,
            minY = puddleWorldMinimum.y,
            minZ = puddleWorldMinimum.z,
            maxX = puddleWorldMaximum.x,
            maxY = puddleWorldMaximum.y,
            maxZ = puddleWorldMaximum.z
        } or nil,
        puddleMapBound = true,
        puddleAmount = getPuddleAmount(),
        activePuddleSites = getActivePuddleSiteCount(),
        maxPuddleClusters = getPuddleClusterLimit(),
        maxVisiblePuddleClusters = getVisiblePuddleClusterLimit(),
        largestPuddleSpread = (function()
            local largest = 0
            for _, puddle in ipairs(puddles) do
                largest = math.max(largest, puddle.spread or 1)
            end
            return largest
        end)(),
        renderedPuddleClusters = self.PuddleRenderClusters or 0,
        renderedPuddleLobes = self.PuddleRenderLobes or 0,
        splashRingCount = #splashRings,
        rainSoundActive = self.RainSoundPatch ~= nil,
        rainSoundMounted = file.Exists("sound/" .. rainSoundPath, "GAME"),
        rainDensity = math.Clamp(rainDensityConVar:GetFloat(), 0.5, 2),
        puddleDropRings = self.PuddleDropRings or 0,
        puddleDropCrowns = self.PuddleDropCrowns or 0,
        puddleImpactQuads = self.PuddleImpactQuads or 0,
        puddleImpactMaxIndices = self.PuddleImpactMaxIndices or 0,
        splashRingMaterialAvailable = not splashRingMaterial:IsError(),
        splashRingMaterialShader = splashRingMaterial:GetShader(),
        footstepSplashMaterialAvailable = not self.FootstepSplashMaterial:IsError(),
        footstepSplashMaterialShader = self.FootstepSplashMaterial:GetShader(),
        puddleOpacity = math.Clamp(puddleOpacityConVar:GetFloat(), 0.05, 0.45),
        puddleTranslucencyMaterialAvailable = puddleMaterial ~= nil,
        puddleMaterialShader = puddleMaterial and puddleMaterial:GetShader() or nil,
        puddleMaterialError = puddleMaterial == nil,
        puddleReflection = puddleReflectionMaterial ~= nil,
        winterBlend = self.WinterBlend or 0,
        frostAmount = self.FrostAmount or 0,
        snowCoverAmount = self.SnowCoverAmount or 0,
        snowCoverStatus = snowCover.status,
        snowCoverStage = snowCover.stage,
        snowCoverPreload = snowCover.preloadStep ~= nil and "holding" or (snowCover.preloadDone and "done" or "waiting"),
        snowCoverPreloadResult = snowCover.preloadResult,
        snowCoverPreloadSeconds = snowCover.preloadSeconds,
        weatherSynced = self.WeatherSynced == true,
        snowCoverMap = snowCover.map,
        snowCoverSpacing = snowCover.spacing,
        snowCoverPoints = snowCover.validPoints or 0,
        snowCoverTriangles = snowCover.triangleCount or 0,
        snowCoverMeshes = snowCover.meshCount or 0,
        snowCoverTextured = snowFloorTexture ~= nil,
        snowCoverTexture = (function()
            local texture = snowCoverMaterial:GetTexture("$basetexture")
            return texture and texture:GetName() or "none"
        end)(),
        snowCoverTextureReapplied = snowCover.textureReapplied or 0,
        snowTrailPoints = snowCover.troddenCount or 0,
        snowCoverDraws = snowCover.drawCount or 0,
        snowCoverChunks = snowCover.chunkList and #snowCover.chunkList or 0,
        snowCoverDrawnChunks = snowCover.lastDrawnChunks or 0,
        snowCoverCulledChunks = snowCover.lastCulledChunks or 0,
        snowCoverRebuilds = snowCover.rebuildCount or 0,
        snowCoverRebuildMsAverage = (snowCover.rebuildCount or 0) > 0
            and (snowCover.rebuildSeconds or 0) * 1000 / snowCover.rebuildCount or 0,
        snowCoverFogCullDistance = snowCoverFogCullDistance,
        windSoundActive = self.WindSoundPatch ~= nil,
        windSoundMounted = file.Exists("sound/" .. windSoundPath, "GAME"),
        snowStepSoundMounted = file.Exists("sound/" .. snowStepSoundPaths[1], "GAME"),
        puddleSloshSoundMounted = file.Exists("sound/" .. puddleSloshSoundPaths[1], "GAME"),
        stepCount = self.StepCount or 0,
        lastStep = self.LastStep and table.Copy(self.LastStep) or nil,
        breathPuffs = self.BreathPuffs or 0,
        puddleTextureWidth = puddleBaseTexture and puddleBaseTexture:Width() or nil,
        boundaryMistMaterialError = boundaryMistMaterial:IsError(),
        boundaryMistTextureWidth = boundaryMistTexture and boundaryMistTexture:Width() or nil,
        puddleMeshLobeLimit = getVisiblePuddleLobeLimit(),
        puddleMeshSegments = puddleMeshSegments,
        activeProfileIndex = self.ActiveProfileIndex,
        activeProfileId = profile and (profile.id or profile.name) or nil,
        expectedProfileIndex = expected and expected.profileIndex or nil,
        expectedProfileId = getProfileId(expected and expected.profileIndex),
        cellX = expected and expected.cellX or nil,
        cellY = expected and expected.cellY or nil,
        safeZoneId = IsValid(player) and player:GetNWString("CurrentSafeZoneId", "") or "",
        pendingProfileIndex = self.PendingProfileIndex,
        pendingPlayerProfileSource = self.PendingPlayerProfileSource,
        lastApplySource = self.LastApplySource,
        stormIntensity = self.StormIntensity,
        fog = self:GetFogSettings(),
        lastProfileReceive = self.LastProfileReceive,
        weather = self.Weather,
        sheltered = isSheltered,
        boundaryMistActive = self.BoundaryMistActive,
        profileApplications = table.Copy(self.ProfileApplications),
        skybox = ZM_Skybox and ZM_Skybox:GetDiagnosticSnapshot() or nil,
        mapCapture = ZM_WorldMap and ZM_WorldMap:GetCaptureDiagnosticSnapshot() or nil,
        mapCaptureParticlesHidden = self.MapCaptureParticlesHidden == true,
        mapCaptureHideCount = self.MapCaptureHideCount or 0,
        retiredWeatherEmitters = #self.RetiredWeatherEmitters,
        shoulderCamera = ZM_IsShoulderCamera(),
        radiationFeedback = ZM_RadiationFeedback:GetDiagnosticSnapshot(),
        gore = ZM_GoreClient:GetDiagnosticSnapshot(),
        music = ZM_Music:GetDiagnosticSnapshot(),
        hookResults = table.Copy(self.HookResults)
    }
end

local function applyFog(settings, scale)
    scale = scale or 1
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(settings.start * scale)
    render.FogEnd(math.max(settings.finish * scale, settings.start * scale + 1))
    render.FogMaxDensity(settings.maxDensity)
    render.FogColor(getColorComponent(settings.color, 1), getColorComponent(settings.color, 2), getColorComponent(settings.color, 3))
    return true
end

local function hasOutdoorCityCells()
    if not ZM_World:IsLoaded() then return false end
    local cells = ZM_World:GetCellsForMap(game.GetMap())
    return type(cells) == "table" and #cells > 0
end

local function isOutdoorCityCell(player)
    if not IsValid(player) or not hasOutdoorCityCells() then return false end
    return not ZM_SafeZones:IsPlayerInside(player)
end

local shelterTraceStart = Vector()
local shelterTraceEnd = Vector()
local shelterTraceResult = {}
local shelterTrace = {
    start = shelterTraceStart,
    endpos = shelterTraceEnd,
    mask = MASK_SOLID_BRUSHONLY,
    output = shelterTraceResult
}

local function checkShelter(player, now)
    if now < nextShelterCheckAt then return isSheltered end
    nextShelterCheckAt = now + 0.5
    local origin = player:GetPos()
    shelterTraceStart:SetUnpacked(origin.x, origin.y, origin.z + 32)
    shelterTraceEnd:SetUnpacked(origin.x, origin.y, origin.z + 32 + 4096)
    shelterTrace.filter = player
    local trace = util.TraceLine(shelterTrace)
    isSheltered = trace.Hit and not trace.HitSky
    weatherDiagnostics.shelterCheckedAt = RealTime()
    weatherDiagnostics.shelterTraceHit = trace.Hit == true
    weatherDiagnostics.shelterTraceHitSky = trace.HitSky == true
    return isSheltered
end

local function emitPrecipitationParticle(weather, eyePosition, eyeAngles)
    if not weatherEmitter then
        weatherEmitter = ParticleEmitter(eyePosition)
    end
    if not weatherEmitter then return end

    local side = eyeAngles:Right() * math.Rand(-620, 620)
    local forward = eyeAngles:Forward() * math.Rand(-180, 420)
    local position = eyePosition + side + forward + Vector(0, 0, math.Rand(260, 640))
    local material = weather == "rain" and "effects/laser_tracer" or "particle/snow"
    local particle = weatherEmitter:Add(material, position)
    if not particle then return end

    particle:SetDieTime(weather == "rain" and 0.65 or 4.2)
    particle:SetStartAlpha(weather == "rain" and 115 or 210)
    particle:SetEndAlpha(0)
    particle:SetStartSize(weather == "rain" and 1 or 2)
    particle:SetEndSize(weather == "rain" and 0.8 or 3)
    particle:SetColor(weather == "rain" and 177 or 218, weather == "rain" and 194 or 226, weather == "rain" and 204 or 232)
    particle:SetCollide(true)
    particle:SetBounce(0)
    particle:SetCollideCallback(function(collidedParticle)
        collidedParticle:SetDieTime(0)
    end)

    if weather == "rain" then
        particle:SetStartLength(34)
        particle:SetEndLength(34)
        particle:SetVelocity(Vector(math.Rand(-45, 45), math.Rand(-45, 45), -1250))
    else
        particle:SetStartSize(math.Rand(1.6, 2.8))
        particle:SetEndSize(math.Rand(1.4, 2.4))
        particle:SetRoll(math.Rand(0, 360))
        particle:SetRollDelta(math.Rand(-1.5, 1.5))
        particle:SetAirResistance(18)
        particle:SetGravity(Vector(math.Rand(-10, 10), math.Rand(-10, 10), -22))
        particle:SetVelocity(Vector(math.Rand(-38, 38), math.Rand(-38, 38), math.Rand(-80, -40)))
    end
end

local function playMountedSound(paths, position, level, pitch, volume, missingKey)
    local path = paths[math.random(#paths)]
    if file.Exists("sound/" .. path, "GAME") then
        sound.Play(path, position, level, pitch, volume)
        return true
    end
    if not Atmosphere[missingKey] then
        Atmosphere[missingKey] = true
        ErrorNoHalt("[ZombieSim] Mounted atmosphere sound is unavailable: " .. path .. "\n")
    end
    return false
end

// A step into a puddle throws a larger crown and sloshes; a step on merely rain-wet ground only patters.
local function addFootstepSplash(position, inPuddle)
    local now = CurTime()
    splashRings[#splashRings + 1] = {
        position = position + Vector(0, 0, 1),
        createdAt = now,
        expiresAt = now + 0.45,
        rotation = math.Rand(0, 360),
        size = inPuddle and 58 or 22
    }
    if #splashRings > 12 then
        table.remove(splashRings, 1)
    end

    if inPuddle then
        if not weatherEmitter then
            weatherEmitter = ParticleEmitter(position)
        end
        if weatherEmitter and not Atmosphere.FootstepSplashMaterial:IsError() then
            for _ = 1, 5 do
                local particle = weatherEmitter:Add("effects/splash2", position + Vector(math.Rand(-4, 4), math.Rand(-4, 4), 1))
                if particle then
                    particle:SetDieTime(math.Rand(0.3, 0.45))
                    particle:SetStartAlpha(110)
                    particle:SetEndAlpha(0)
                    particle:SetStartSize(math.Rand(2, 4))
                    particle:SetEndSize(math.Rand(7, 11))
                    particle:SetRoll(math.Rand(0, 360))
                    particle:SetColor(150, 162, 168)
                    particle:SetCollide(false)
                    particle:SetGravity(Vector(0, 0, -380))
                    particle:SetVelocity(Vector(math.Rand(-55, 55), math.Rand(-55, 55), math.Rand(60, 130)))
                end
            end
        end
        return playMountedSound(puddleSloshSoundPaths, position, 70, math.Rand(94, 106), 0.55, "PuddleSloshSoundMissing")
    end
    return playMountedSound(puddleSloshSoundPaths, position, 60, math.Rand(108, 118), 0.14, "PuddleSloshSoundMissing")
end

local function addSnowStep(position, onSnowPatch)
    if onSnowPatch then
        if not weatherEmitter then
            weatherEmitter = ParticleEmitter(position)
        end
        if weatherEmitter then
            for _ = 1, 5 do
                local particle = weatherEmitter:Add("particle/particle_smokegrenade", position + Vector(math.Rand(-6, 6), math.Rand(-6, 6), 2))
                if particle then
                    particle:SetDieTime(math.Rand(0.5, 0.8))
                    particle:SetStartAlpha(70)
                    particle:SetEndAlpha(0)
                    particle:SetStartSize(math.Rand(3, 5))
                    particle:SetEndSize(math.Rand(9, 14))
                    particle:SetColor(232, 238, 244)
                    particle:SetCollide(false)
                    particle:SetAirResistance(80)
                    particle:SetVelocity(Vector(math.Rand(-30, 30), math.Rand(-30, 30), math.Rand(10, 34)))
                end
            end
        end
    end
    playMountedSound(snowStepSoundPaths, position, 65, math.Rand(92, 106), onSnowPatch and 0.6 or 0.32, "SnowStepSoundMissing")
end

local function startWindAmbience(player, now)
    local patch = Atmosphere.WindSoundPatch
    if not patch then
        if not file.Exists("sound/" .. windSoundPath, "GAME") then
            if not Atmosphere.WindSoundMissing then
                Atmosphere.WindSoundMissing = true
                ErrorNoHalt("[ZombieSim] Mounted wind ambience is unavailable: " .. windSoundPath .. "\n")
            end
            return
        end
        patch = CreateSound(player, windSoundPath)
        if not patch then
            ErrorNoHalt("[ZombieSim] Could not create wind ambience sound patch.\n")
            return
        end
        Atmosphere.WindSoundPatch = patch
        patch:PlayEx(0, 100)
        patch:ChangeVolume(0.34, 2.5)
        nextWindGustAt = now + math.Rand(5, 10)
    elseif not patch:IsPlaying() then
        // Restart if the mounted wave has no loop cue.
        patch:PlayEx(0.34, 100)
    end

    if now >= nextWindGustAt then
        nextWindGustAt = now + math.Rand(9, 20)
        local offset = VectorRand() * 420
        offset.z = math.abs(offset.z) * 0.3 + 120
        playMountedSound(windGustSoundPaths, player:EyePos() + offset, 75, math.Rand(85, 110), math.Rand(0.25, 0.45), "WindGustSoundMissing")
    end
end

local function startRainAmbience(player)
    if Atmosphere.RainSoundPatch then return end
    if not file.Exists("sound/" .. rainSoundPath, "GAME") then
        if not Atmosphere.RainSoundMissing then
            Atmosphere.RainSoundMissing = true
            ErrorNoHalt("[ZombieSim] Mounted rain ambience is unavailable: " .. rainSoundPath .. "\n")
        end
        return
    end

    Atmosphere.RainSoundPatch = CreateSound(player, rainSoundPath)
    if not Atmosphere.RainSoundPatch then
        ErrorNoHalt("[ZombieSim] Could not create rain ambience sound patch.\n")
        return
    end
    Atmosphere.RainSoundPatch:PlayEx(0.24, 100)
end

local function ensurePuddleMapSites()
    local mapName = game.GetMap()
    if puddleSiteMap == mapName and #puddleSites == puddleSiteCapacity and puddleWorldMinimum and puddleWorldMaximum then
        Atmosphere.PuddleSiteStatus = "ready"
        return true
    end

    Atmosphere.PuddleSiteAttempts = (Atmosphere.PuddleSiteAttempts or 0) + 1
    // Worldspawn is never IsValid(); test the NULL entity and IsWorld instead.
    local world = game.GetWorld()
    if not world or world == NULL or not world:IsWorld() then
        Atmosphere.PuddleSiteStatus = "world entity unavailable"
        if Atmosphere.PuddleBoundsErrorMap ~= mapName then
            Atmosphere.PuddleBoundsErrorMap = mapName
            ErrorNoHalt("[ZombieSim] Cannot seed map puddles: world entity bounds are unavailable for " .. mapName .. ".\n")
        end
        return false
    end
    local minimum, maximum = world:WorldSpaceAABB()
    if not minimum or not maximum or maximum.x <= minimum.x or maximum.y <= minimum.y then
        minimum, maximum = world:GetRenderBounds()
        Atmosphere.PuddleBoundsSource = "render bounds"
    else
        Atmosphere.PuddleBoundsSource = "world AABB"
    end
    // City recipes carry the 3D skybox room above the playable cell; keep puddle and snow sampling below it.
    if ZM_Skybox and ZM_Skybox.ClampWorldBounds then
        minimum, maximum = ZM_Skybox:ClampWorldBounds(minimum, maximum)
    end
    if not minimum or not maximum or maximum.x <= minimum.x or maximum.y <= minimum.y or maximum.z <= minimum.z then
        Atmosphere.PuddleSiteStatus = "invalid world bounds"
        if Atmosphere.PuddleBoundsErrorMap ~= mapName then
            Atmosphere.PuddleBoundsErrorMap = mapName
            ErrorNoHalt("[ZombieSim] Cannot seed map puddles: invalid world bounds for " .. mapName .. ".\n")
        end
        return false
    end

    local width = maximum.x - minimum.x
    local height = maximum.y - minimum.y
    local margin = math.min(48, math.min(width, height) * 0.05)
    local minimumX = minimum.x + margin
    local maximumX = maximum.x - margin
    local minimumY = minimum.y + margin
    local maximumY = maximum.y - margin
    if maximumX <= minimumX or maximumY <= minimumY then
        Atmosphere.PuddleSiteStatus = "world bounds too small"
        return false
    end

    table.Empty(puddleSites)
    table.Empty(puddles)
    for index = 1, puddleSiteCapacity do
        local seed = mapName .. ":" .. index
        puddleSites[index] = {
            index = index,
            position = Vector(
                util.SharedRandom("ZM.PuddleSiteX:" .. seed, minimumX, maximumX),
                util.SharedRandom("ZM.PuddleSiteY:" .. seed, minimumY, maximumY),
                0
            )
        }
    end

    puddleSiteMap = mapName
    puddleSiteCursor = 1
    puddleWorldMinimum = minimum
    puddleWorldMaximum = maximum
    Atmosphere.PuddleSiteMap = mapName
    Atmosphere.PuddleSiteCursor = puddleSiteCursor
    Atmosphere.PuddleWorldMinimum = minimum
    Atmosphere.PuddleWorldMaximum = maximum
    Atmosphere.PuddleBoundsErrorMap = nil
    Atmosphere.PuddleSiteStatus = "ready"
    return true
end

local puddleGroundStart = Vector()
local puddleGroundEnd = Vector()
// Ground results are retained and compared by callers, so only the request is reused.
local puddleGroundTrace = {
    start = puddleGroundStart,
    endpos = puddleGroundEnd,
    mask = MASK_SOLID_BRUSHONLY
}

local function tracePuddleGround(position, player)
    local minimumZ = puddleWorldMinimum.z
    local startZ = puddleWorldMaximum.z - 1
    local trace
    puddleGroundTrace.filter = IsValid(player) and player or nil
    // Step through sky ceilings and thin overhead brushes until real ground is found.
    for _ = 1, 4 do
        puddleGroundStart:SetUnpacked(position.x, position.y, startZ)
        puddleGroundEnd:SetUnpacked(position.x, position.y, minimumZ - 64)
        trace = util.TraceLine(puddleGroundTrace)
        if not trace.Hit then return nil end
        if not trace.StartSolid and not trace.HitSky then break end
        local exitZ = trace.StartSolid and (startZ + (minimumZ - 64 - startZ) * trace.FractionLeftSolid) or trace.HitPos.z
        startZ = exitZ - 2
        if startZ <= minimumZ then return nil end
        trace = nil
    end
    if not trace or not trace.HitWorld or trace.HitSky or trace.HitNormal.z < 0.7 then return nil end
    return trace
end

local puddleOverheadStart = Vector()
local puddleOverheadEnd = Vector()
local puddleOverheadResult = {}
local puddleOverheadTrace = {
    start = puddleOverheadStart,
    endpos = puddleOverheadEnd,
    mask = MASK_SOLID_BRUSHONLY,
    output = puddleOverheadResult
}

local function isPuddleSurfaceExposed(trace, player)
    local hitPos, hitNormal = trace.HitPos, trace.HitNormal
    local surfaceX = hitPos.x + hitNormal.x * 12
    local surfaceY = hitPos.y + hitNormal.y * 12
    puddleOverheadStart:SetUnpacked(surfaceX, surfaceY, hitPos.z + hitNormal.z * 12)
    puddleOverheadEnd:SetUnpacked(surfaceX, surfaceY, puddleWorldMaximum.z + 64)
    puddleOverheadTrace.filter = IsValid(player) and player or nil
    local overhead = util.TraceLine(puddleOverheadTrace)
    return not overhead.Hit or overhead.HitSky
end

local function findPuddleLowPoint(trace, player)
    local lowest = trace
    for _ = 1, 4 do
        local nextLowest = lowest
        for _, direction in ipairs(puddleProbeDirections) do
            local candidate = tracePuddleGround(lowest.HitPos + direction * 24, player)
            if candidate and candidate.HitPos.z < nextLowest.HitPos.z - 2 then
                nextLowest = candidate
            end
        end
        if nextLowest == lowest then break end
        lowest = nextLowest
    end
    return lowest
end

// Low-frequency harmonics give a smooth, organic outline instead of per-vertex spikes.
local function createPuddleEdgeFactors()
    local harmonics = {
        { 2, math.Rand(0.06, 0.12), math.Rand(0, math.pi * 2) },
        { 3, math.Rand(0.04, 0.09), math.Rand(0, math.pi * 2) },
        { 5, math.Rand(0.01, 0.04), math.Rand(0, math.pi * 2) }
    }
    local edgeFactors = {}
    for index = 1, puddleMeshSegments do
        local angle = (index - 1) / puddleMeshSegments * math.pi * 2
        local factor = 1
        for _, harmonic in ipairs(harmonics) do
            factor = factor + harmonic[2] * math.sin(harmonic[1] * angle + harmonic[3])
        end
        edgeFactors[index] = factor
    end
    return edgeFactors
end

local function createPuddleLobe(trace, width, now)
    local edgeFactors = createPuddleEdgeFactors()
    return {
        position = trace.HitPos + trace.HitNormal * 0.6,
        normal = trace.HitNormal,
        width = 0,
        targetWidth = width,
        height = 0,
        targetHeight = width * math.Rand(0.68, 0.9),
        rotation = math.Rand(0, 360),
        opacityScale = math.Rand(0.8, 1),
        edgeFactors = edgeFactors,
        createdAt = now
    }
end

// Largest spread multiplier whose rim stays on level, open ground; prevents pools climbing kerbs or walls.
local function measurePuddleMaxSpread(trace, width, player)
    local desired = math.random() < 0.22 and math.Rand(3.2, 4.4) or math.Rand(1.3, 2.0)
    local accepted = 1
    for _, spread in ipairs({ 1.4, 2, 2.8, 3.6, 4.4 }) do
        if spread > desired then break end
        local radius = width * 0.55 * spread
        for _, direction in ipairs({ Vector(1, 0, 0), Vector(0, 1, 0), Vector(-1, 0, 0), Vector(0, -1, 0) }) do
            local edge = tracePuddleGround(trace.HitPos + direction * radius, player)
            if not edge or math.abs(edge.HitPos.z - trace.HitPos.z) > puddleFlatTolerance then
                return accepted
            end
        end
        accepted = spread
    end
    return math.max(accepted, math.min(desired, accepted * 1.15))
end

local function addSpreadLobe(puddle, player, now)
    if #puddle.lobes >= maxPuddleLobes then return end
    local spread = puddle.spread or 1
    local angle = math.Rand(0, math.pi * 2)
    local distance = puddle.size * 0.45 * spread * math.Rand(0.35, 0.8)
    local offset = Vector(math.cos(angle) * distance, math.sin(angle) * distance, 0)
    local trace = tracePuddleGround(puddle.position + offset, player)
    if not trace or math.abs(trace.HitPos.z - puddle.position.z) > puddleFlatTolerance then return end
    local lobe = createPuddleLobe(trace, math.Rand(88, 128), now)
    // Store lobes in unspread space so the render-time spread places them where the trace landed.
    local z = lobe.position.z
    lobe.position = puddle.position + (lobe.position - puddle.position) / spread
    lobe.position.z = z
    puddle.lobes[#puddle.lobes + 1] = lobe
end

local function addWetPuddle(site, player, now)
    if site.puddle and not site.puddle.removed then
        site.puddle.expiresAt = now + puddleLifetime
        site.puddle.lastWetAt = now
        if (site.puddle.spread or 1) > 1.25 and math.random() < 0.5 then
            addSpreadLobe(site.puddle, player, now)
        end
        return
    end

    local trace = tracePuddleGround(site.position, player)
    if not trace then
        site.unusable = true
        return
    end
    trace = findPuddleLowPoint(trace, player)
    if not isPuddleSurfaceExposed(trace, player) then
        site.unusable = true
        return
    end

    local position = trace.HitPos + trace.HitNormal * 0.6
    local width = math.Rand(88, 128)
    local nearestPuddle
    local nearestDistance = math.huge
    for _, puddle in ipairs(puddles) do
        local dx = position.x - puddle.position.x
        local dy = position.y - puddle.position.y
        local distance = dx * dx + dy * dy
        local mergeDistance = math.max(108, math.min(puddle.size * 0.62 + width * 0.35, 210)) * (puddle.spread or 1)
        if not puddle.removed and math.abs(position.z - puddle.position.z) <= 40 and distance <= mergeDistance * mergeDistance and distance < nearestDistance then
            nearestPuddle = puddle
            nearestDistance = distance
        end
    end

    if not nearestPuddle then
        if #puddles >= getPuddleClusterLimit() then
            local oldestIndex = 1
            local oldestWetAt = math.huge
            for index, puddle in ipairs(puddles) do
                local lastWetAt = puddle.lastWetAt or puddle.createdAt or 0
                if lastWetAt < oldestWetAt then
                    oldestIndex = index
                    oldestWetAt = lastWetAt
                end
            end
            if oldestIndex then
                puddles[oldestIndex].removed = true
                table.remove(puddles, oldestIndex)
            end
        end
        nearestPuddle = {
            position = position,
            normal = trace.HitNormal,
            size = width,
            createdAt = now,
            lastWetAt = now,
            expiresAt = now + puddleLifetime,
            rippleOffset = math.Rand(0, 2.4),
            wetSeconds = 0,
            spread = 1,
            maxSpread = measurePuddleMaxSpread(trace, width, player),
            lobes = {},
            removed = false
        }
        puddles[#puddles + 1] = nearestPuddle
    else
        nearestPuddle.expiresAt = now + puddleLifetime
        nearestPuddle.lastWetAt = now
        nearestPuddle.size = math.min(240, nearestPuddle.size + width * 0.1)
        if position.z < nearestPuddle.position.z - 2 then
            nearestPuddle.position = position
            nearestPuddle.normal = trace.HitNormal
        end
    end

    site.puddle = nearestPuddle
    local nearestLobe
    local nearestLobeDistance = math.huge
    for _, lobe in ipairs(nearestPuddle.lobes) do
        lobe.targetWidth = lobe.targetWidth or lobe.width or width
        lobe.targetHeight = lobe.targetHeight or lobe.height or width * 0.8
        local dx = position.x - lobe.position.x
        local dy = position.y - lobe.position.y
        local distance = dx * dx + dy * dy
        if distance < nearestLobeDistance then
            nearestLobe = lobe
            nearestLobeDistance = distance
        end
    end

    local mergeLobeDistance = nearestLobe and (nearestLobe.targetWidth + width) * 0.55 or 0
    if nearestLobe and nearestLobeDistance <= mergeLobeDistance * mergeLobeDistance then
        nearestLobe.targetWidth = math.min(184, nearestLobe.targetWidth + width * 0.12)
        nearestLobe.targetHeight = math.min(164, nearestLobe.targetHeight + width * 0.09)
    elseif #nearestPuddle.lobes < maxPuddleLobes then
        local lobe = createPuddleLobe(trace, width, now)
        local spread = nearestPuddle.spread or 1
        local z = lobe.position.z
        lobe.position = nearestPuddle.position + (lobe.position - nearestPuddle.position) / spread
        lobe.position.z = z
        nearestPuddle.lobes[#nearestPuddle.lobes + 1] = lobe
    end
end

local function updateWetPuddles()
    local now = CurTime()
    local dryAt = Atmosphere.PuddlesDryAt
    local elapsed = math.Clamp(now - (Atmosphere.PuddleGrowthAt or now), 0, 1)
    Atmosphere.PuddleGrowthAt = now
    local raining = Atmosphere.Weather == "rain" and not dryAt
    for index = #puddles, 1, -1 do
        local puddle = puddles[index]
        if now >= puddle.expiresAt or (dryAt and now >= dryAt) then
            puddle.removed = true
            table.remove(puddles, index)
        elseif raining then
            puddle.wetSeconds = (puddle.wetSeconds or 0) + elapsed
            local maturity = math.Clamp(puddle.wetSeconds / puddleMatureSeconds, 0, 1)
            maturity = maturity * maturity * (3 - 2 * maturity)
            puddle.spread = 1 + ((puddle.maxSpread or 1) - 1) * maturity
        end
    end

    local clusterLimit = getPuddleClusterLimit()
    while #puddles > clusterLimit do
        local oldestIndex = 1
        local oldestWetAt = math.huge
        for index, puddle in ipairs(puddles) do
            if (puddle.lastWetAt or 0) < oldestWetAt then
                oldestIndex = index
                oldestWetAt = puddle.lastWetAt or 0
            end
        end
        puddles[oldestIndex].removed = true
        table.remove(puddles, oldestIndex)
    end

    if not raining then
        puddleSiteDebt = 0
        return
    end
    if now >= nextPuddleAt then
        nextPuddleAt = now + puddleSiteInterval
        if not hasOutdoorCityCells() or not ensurePuddleMapSites() then
            puddleSiteDebt = 0
            return
        end
        // Visit every active site about once per 35 seconds, well inside the 60-second puddle lifetime.
        // Each tick's sites become debt that is paid off within the shared frame budget instead of in one burst.
        local activeSites = getActivePuddleSiteCount()
        puddleSiteDebt = math.min(puddleSiteDebt + math.ceil(activeSites / puddleSiteCycleTicks), activeSites)
    end
    if puddleSiteDebt <= 0 then return end

    local activeSites = getActivePuddleSiteCount()
    if activeSites <= 0 then
        puddleSiteDebt = 0
        return
    end
    local deadline = getAtmosphereWorkDeadline()
    local player = LocalPlayer()
    while puddleSiteDebt > 0 do
        if puddleSiteCursor > activeSites then puddleSiteCursor = 1 end
        local site = puddleSites[puddleSiteCursor]
        puddleSiteCursor = puddleSiteCursor % activeSites + 1
        puddleSiteDebt = puddleSiteDebt - 1
        if site and not site.unusable then
            addWetPuddle(site, player, now)
        end
        if SysTime() >= deadline then break end
    end
    Atmosphere.PuddleSiteCursor = puddleSiteCursor
end

local function findNearbyTransitionGate(position)
    local nearestGate
    local nearestDistance = 700 * 700
    for _, direction in ipairs({ "N", "E", "S", "W" }) do
        local count = math.min(GetGlobal2Int("ZMTransitionGateCount_" .. direction, 0), 4)
        for index = 1, count do
            local gate = GetGlobal2Vector("ZMTransitionGate_" .. direction .. "_" .. index, vector_origin)
            local distance = position:DistToSqr(gate)
            if distance < nearestDistance then
                nearestGate = gate
                nearestDistance = distance
            end
        end
    end
    return nearestGate
end

local function emitBoundaryMist(gate, fogColor)
    if not boundaryEmitter then
        boundaryEmitter = ParticleEmitter(gate)
    end
    if not boundaryEmitter then return end
    Atmosphere.BoundaryMistActive = true

    for _ = 1, 3 do
        local position = gate + Vector(math.Rand(-110, 110), math.Rand(-110, 110), math.Rand(-18, 104))
        local particle = boundaryEmitter:Add("particle/particle_smokegrenade", position)
        if particle then
            particle:SetDieTime(1.25)
            particle:SetStartAlpha(15)
            particle:SetEndAlpha(0)
            particle:SetStartSize(math.Rand(44, 62))
            particle:SetEndSize(math.Rand(88, 124))
            particle:SetColor(getColorComponent(fogColor, 1), getColorComponent(fogColor, 2), getColorComponent(fogColor, 3))
            particle:SetCollide(false)
            particle:SetVelocity(Vector(math.Rand(-16, 16), math.Rand(-16, 16), math.Rand(-2, 5)))
        end
    end
end

local function findPuddleAt(position)
    local now = CurTime()
    local dryAt = Atmosphere.PuddlesDryAt
    local fade = dryAt and math.Clamp((dryAt - now) / 3, 0, 1) or 1
    if fade <= 0.15 then return nil end
    for _, puddle in ipairs(puddles) do
        if not puddle.removed and math.abs(position.z - puddle.position.z) <= 24 then
            local spread = (puddle.spread or 1) * (0.7 + 0.3 * fade)
            for _, lobe in ipairs(puddle.lobes) do
                local center = puddle.position + (lobe.position - puddle.position) * spread
                local radius = 0.25 * ((lobe.width or 0) + (lobe.height or 0)) * spread
                local dx = position.x - center.x
                local dy = position.y - center.y
                if radius > 4 and dx * dx + dy * dy <= radius * radius then
                    return puddle
                end
            end
        end
    end
    return nil
end

// Snow cover: a client-side heightfield blanket sampled once per map over every sky-exposed walkable
// surface, built into static meshes and faded in/out as snow settles and melts. No map compile needed.
local function snowHash(first, second)
    local value = math.sin(first * 12.9898 + second * 78.233) * 43758.5453
    return value - math.floor(value)
end

local function destroySnowCoverMeshes()
    for _, chunk in pairs(snowCover.chunks or {}) do
        if chunk.imesh then
            chunk.imesh:Destroy()
            chunk.imesh = nil
        end
    end
    for _, imesh in ipairs(snowCover.meshes or {}) do
        imesh:Destroy()
    end
    snowCover.meshes = {}
    snowCover.chunks = {}
    snowCover.chunkList = {}
    snowCover.dirtyChunks = {}
    snowCover.urgentChunks = {}
    snowCover.meshCount = 0
end

// Quality settings come from cl_quality.lua; the fallbacks keep the original high-quality behaviour.
function Atmosphere.GetQualityNumber(key, fallback, minimum, maximum)
    local convar = ZM_Quality and ZM_Quality.ConVars and ZM_Quality.ConVars[key]
    if not convar then return fallback end
    return math.Clamp(convar:GetFloat(), minimum, maximum)
end

local function beginSnowCover(mapName)
    destroySnowCoverMeshes()
    local minimum, maximum = puddleWorldMinimum, puddleWorldMaximum
    local width = maximum.x - minimum.x
    local height = maximum.y - minimum.y
    local detail = Atmosphere.GetQualityNumber("snowDetail", 1, 0.25, 1)
    local spacing = math.max(snowCoverMinimumSpacing,
        math.ceil(math.sqrt(width * height / (snowCoverTargetPoints * detail))))
    snowCover.map = mapName
    snowCover.meshVersion = snowCoverMeshVersion
    snowCover.detail = detail
    snowCover.status = "sampling"
    snowCover.spacing = spacing
    snowCover.originX = minimum.x
    snowCover.originY = minimum.y
    snowCover.columns = math.floor(width / spacing) + 1
    snowCover.rows = math.floor(height / spacing) + 1
    snowCover.total = snowCover.columns * snowCover.rows
    snowCover.chunkColumns = math.ceil(snowCover.columns / snowCoverChunkQuads)
    snowCover.points = {}
    snowCover.trodden = {}
    snowCover.troddenCount = 0
    snowCover.cursor = 0
    snowCover.validPoints = 0
    snowCover.validQuads = nil
    snowCover.buildCursor = 1
    snowCover.triangleCount = 0
    snowCover.lastCarvePosition = nil
    snowCover.stage = math.Round((Atmosphere.SnowCoverAmount or 0) * snowCoverStages) / snowCoverStages
end

// Smooth value noise over a few grid cells, so snow settles in drifts rather than per-sample speckle.
local function snowPatchNoise(column, row)
    local x, y = column / 7, row / 7
    local x0, y0 = math.floor(x), math.floor(y)
    local fx, fy = x - x0, y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    local top = Lerp(fx, snowHash(x0, y0), snowHash(x0 + 1, y0))
    local bottom = Lerp(fx, snowHash(x0, y0 + 1), snowHash(x0 + 1, y0 + 1))
    return Lerp(fy, top, bottom)
end

local function sampleSnowCover(budget)
    local columns = snowCover.columns
    local spacing = snowCover.spacing
    local deadline = getAtmosphereWorkDeadline()
    for sampled = 1, budget do
        if sampled > 1 and SysTime() >= deadline then return end
        local cursor = snowCover.cursor
        if cursor >= snowCover.total then
            snowCover.status = "meshing"
            return
        end
        snowCover.cursor = cursor + 1
        local column = cursor % columns
        local row = math.floor(cursor / columns)
        local trace = tracePuddleGround(Vector(snowCover.originX + column * spacing, snowCover.originY + row * spacing, 0), nil)
        if trace and isPuddleSurfaceExposed(trace, nil) then
            local normal = trace.HitNormal
            local light = render.GetLightColor(trace.HitPos + normal * 4)
            local position = trace.HitPos + normal * snowCoverLift
            snowCover.points[cursor + 1] = {
                position = position,
                normal = normal,
                // Plain numbers let chunk re-bakes update pooled vertices without Vector temporaries.
                px = position.x, py = position.y, pz = position.z,
                nx = normal.x, ny = normal.y, nz = normal.z,
                // Unlit material: keep snow bright and only dim it modestly in darker spots.
                brightness = math.Clamp(0.72 + (light.x + light.y + light.z) / 3 * 0.8, 0.72, 1),
                drift = 0.7 + 0.3 * snowHash(column * 0.37, row * 0.71),
                // Lower values settle first and melt last.
                patch = 0.8 * snowPatchNoise(column, row) + 0.2 * snowHash(column * 1.31, row * 2.17)
            }
            snowCover.validPoints = snowCover.validPoints + 1
        end
    end
end

local function getSnowChunkKey(index)
    local columns = snowCover.columns
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    return math.floor(row / snowCoverChunkQuads) * snowCover.chunkColumns + math.floor(column / snowCoverChunkQuads)
end

// Quads are grouped into small spatial chunks so a carved trail only rebuilds the chunks it touches.
local function collectSnowCoverQuads()
    local points = snowCover.points
    local columns = snowCover.columns
    local valid = {}
    local chunks = {}
    local chunkList = {}
    for row = 0, snowCover.rows - 2 do
        for column = 0, columns - 2 do
            local index = row * columns + column + 1
            local a, b, c, d = points[index], points[index + 1], points[index + columns + 1], points[index + columns]
            if a and b and c and d then
                local low = math.min(a.position.z, b.position.z, c.position.z, d.position.z)
                local high = math.max(a.position.z, b.position.z, c.position.z, d.position.z)
                // Skip quads that would bridge kerbs or walls; their neighbours feather out instead.
                if high - low <= snowCoverMaxStep then
                    valid[index] = true
                    local key = getSnowChunkKey(index)
                    local chunk = chunks[key]
                    if not chunk then
                        chunk = { key = key, quads = {},
                            minX = math.huge, minY = math.huge, minZ = math.huge,
                            maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge,
                            patchMin = math.huge, patchMax = -math.huge }
                        chunks[key] = chunk
                        chunkList[#chunkList + 1] = chunk
                    end
                    chunk.quads[#chunk.quads + 1] = index
                    for _, point in ipairs({ a, b, c, d }) do
                        chunk.minX = math.min(chunk.minX, point.px)
                        chunk.minY = math.min(chunk.minY, point.py)
                        chunk.minZ = math.min(chunk.minZ, point.pz)
                        chunk.maxX = math.max(chunk.maxX, point.px)
                        chunk.maxY = math.max(chunk.maxY, point.py)
                        chunk.maxZ = math.max(chunk.maxZ, point.pz)
                        chunk.patchMin = math.min(chunk.patchMin, point.patch)
                        chunk.patchMax = math.max(chunk.patchMax, point.patch)
                    end
                end
            end
        end
    end
    // Bounding spheres for draw culling.
    for _, chunk in ipairs(chunkList) do
        chunk.centerX = (chunk.minX + chunk.maxX) * 0.5
        chunk.centerY = (chunk.minY + chunk.maxY) * 0.5
        chunk.centerZ = (chunk.minZ + chunk.maxZ) * 0.5
        local dx, dy, dz = chunk.maxX - chunk.centerX, chunk.maxY - chunk.centerY, chunk.maxZ - chunk.centerZ
        chunk.radius = math.sqrt(dx * dx + dy * dy + dz * dz) + snowCoverLift
    end
    snowCover.validQuads = valid
    snowCover.chunks = chunks
    snowCover.chunkList = chunkList
    snowCover.buildCursor = 1
end

local function getSnowVertexAlpha(index)
    local columns = snowCover.columns
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    if column == 0 or row == 0 then return 0 end
    local valid = snowCover.validQuads
    if valid[index] and valid[index - 1] and valid[index - columns] and valid[index - columns - 1] then
        return 255 * snowCover.points[index].drift
    end
    return 0
end

// Rewrites a pooled vertex in place: no tables, Vectors or Colors are allocated per re-bake.
local function updateSnowVertex(vertex, index)
    local point = snowCover.points[index]
    local trodden = snowCover.trodden[index] or 0
    // Each point fills in over its own slice of the build: patches settle first, then the cover joins up and thickens.
    local coverage = math.Clamp((snowCover.stage - point.patch * 0.6) / 0.4, 0, 1)
    local depth = 1 + (snowCoverLift - 1) * coverage
    // Trodden snow is pressed down towards the ground, greyer, and thin enough to show the road through.
    local offset = depth - (depth - 0.5) * trodden - snowCoverLift
    vertex.pos:SetUnpacked(point.px + point.nx * offset, point.py + point.ny * offset, point.pz + point.nz * offset)
    local brightness = point.brightness * (1 - 0.28 * trodden)
    local color = vertex.color
    color.r = 236 * brightness
    color.g = 241 * brightness
    color.b = 250 * brightness
    color.a = point.edgeAlpha * coverage * (1 - 0.72 * trodden)
end

local function getSnowChunkVertex(chunk, index)
    local vertex = chunk.vertices[index]
    if not vertex then
        local point = snowCover.points[index]
        if point.edgeAlpha == nil then
            point.edgeAlpha = getSnowVertexAlpha(index)
        end
        vertex = {
            pos = Vector(point.px, point.py, point.pz),
            normal = point.normal,
            u = point.px / 192,
            v = point.py / 192,
            color = Color(255, 255, 255, 0)
        }
        chunk.vertices[index] = vertex
        chunk.vertexList[#chunk.vertexList + 1] = index
    end
    return vertex
end

// The triangle list references shared pooled vertices, so it is built once per chunk and reused.
local function prepareSnowChunkVertices(chunk)
    chunk.vertices = {}
    chunk.vertexList = {}
    local triangles = {}
    local columns = snowCover.columns
    for _, index in ipairs(chunk.quads) do
        local a, b = getSnowChunkVertex(chunk, index), getSnowChunkVertex(chunk, index + 1)
        local c, d = getSnowChunkVertex(chunk, index + columns + 1), getSnowChunkVertex(chunk, index + columns)
        triangles[#triangles + 1] = a
        triangles[#triangles + 1] = c
        triangles[#triangles + 1] = b
        triangles[#triangles + 1] = a
        triangles[#triangles + 1] = d
        triangles[#triangles + 1] = c
    end
    chunk.triangleList = triangles
end

local function buildSnowChunkMesh(chunk)
    local startedAt = SysTime()
    if chunk.imesh then
        chunk.imesh:Destroy()
        chunk.imesh = nil
        snowCover.meshCount = snowCover.meshCount - 1
        snowCover.triangleCount = snowCover.triangleCount - (chunk.triangles or 0)
    end
    if not chunk.triangleList then
        prepareSnowChunkVertices(chunk)
    end
    if #chunk.triangleList == 0 then return end
    local vertices = chunk.vertices
    for _, index in ipairs(chunk.vertexList) do
        updateSnowVertex(vertices[index], index)
    end
    local imesh = Mesh(snowCoverMaterial)
    imesh:BuildFromTriangles(chunk.triangleList)
    chunk.imesh = imesh
    chunk.triangles = #chunk.quads * 2
    snowCover.meshCount = snowCover.meshCount + 1
    snowCover.rebuildCount = (snowCover.rebuildCount or 0) + 1
    snowCover.rebuildSeconds = (snowCover.rebuildSeconds or 0) + SysTime() - startedAt
    snowCover.triangleCount = snowCover.triangleCount + chunk.triangles
end

local function buildSnowCoverChunks(budget)
    if not snowCover.validQuads then
        collectSnowCoverQuads()
        return
    end
    local chunkList = snowCover.chunkList
    local deadline = getAtmosphereWorkDeadline()
    for built = 1, budget do
        if built > 1 and SysTime() >= deadline then return end
        local chunk = chunkList[snowCover.buildCursor]
        if not chunk then
            snowCover.status = "ready"
            return
        end
        buildSnowChunkMesh(chunk)
        snowCover.buildCursor = snowCover.buildCursor + 1
    end
end

local function markSnowQuadDirty(quadIndex, urgent)
    if snowCover.validQuads[quadIndex] then
        local key = getSnowChunkKey(quadIndex)
        if urgent then
            snowCover.urgentChunks[key] = true
        else
            snowCover.dirtyChunks[key] = true
        end
    end
end

// A point is shared by up to four quads; footprints are urgent so they jump the background re-bake queue.
local function markSnowPointDirty(index, urgent)
    if not snowCover.validQuads or not snowCover.dirtyChunks then return end
    snowCover.urgentChunks = snowCover.urgentChunks or {}
    local columns = snowCover.columns
    markSnowQuadDirty(index, urgent)
    markSnowQuadDirty(index - 1, urgent)
    markSnowQuadDirty(index - columns, urgent)
    markSnowQuadDirty(index - columns - 1, urgent)
end

local function rebuildDirtySnowChunks(budget)
    local limit = budget or snowCoverRebuildsPerFrame
    local deadline = getAtmosphereWorkDeadline()
    local rebuilt = 0
    local urgent = snowCover.urgentChunks or {}
    local dirty = snowCover.dirtyChunks
    while rebuilt < limit do
        local key = next(urgent)
        local queue = urgent
        if key == nil then
            key = next(dirty)
            queue = dirty
        end
        if key == nil then return end
        queue[key] = nil
        dirty[key] = nil
        local chunk = snowCover.chunks[key]
        if chunk then
            buildSnowChunkMesh(chunk)
        end
        rebuilt = rebuilt + 1
        if SysTime() >= deadline then return end
    end
end

// Coverage only changes for points whose settle window [0.6 * patch, 0.6 * patch + 0.4] overlaps the stage move.
local function isSnowChunkAffectedByStage(chunk, from, to)
    local low, high = math.min(from, to), math.max(from, to)
    return high > chunk.patchMin * 0.6 and low < chunk.patchMax * 0.6 + 0.4
end

local function getSnowCoverPointAt(position)
    if snowCover.status ~= "ready" or snowCover.map ~= game.GetMap() then return nil end
    local column = math.Round((position.x - snowCover.originX) / snowCover.spacing)
    local row = math.Round((position.y - snowCover.originY) / snowCover.spacing)
    if column < 0 or row < 0 or column >= snowCover.columns or row >= snowCover.rows then return nil end
    local point = snowCover.points[row * snowCover.columns + column + 1]
    if point and math.abs(point.position.z - snowCoverLift - position.z) <= 16 then return point end
    return nil
end

local function carveSnowAt(position)
    local spacing = snowCover.spacing
    local columns = snowCover.columns
    local radius = snowCarveRadius
    local centerColumn = (position.x - snowCover.originX) / spacing
    local centerRow = (position.y - snowCover.originY) / spacing
    local reach = math.ceil(radius / spacing)
    local points = snowCover.points
    local trodden = snowCover.trodden
    for row = math.max(0, math.floor(centerRow) - reach), math.min(snowCover.rows - 1, math.ceil(centerRow) + reach) do
        for column = math.max(0, math.floor(centerColumn) - reach), math.min(columns - 1, math.ceil(centerColumn) + reach) do
            local index = row * columns + column + 1
            local point = points[index]
            if point and math.abs(point.position.z - snowCoverLift - position.z) <= 24 then
                local dx = point.position.x - position.x
                local dy = point.position.y - position.y
                local falloff = 1 - math.sqrt(dx * dx + dy * dy) / radius
                if falloff > 0 then
                    local depth = math.min(1, falloff * 1.6)
                    local current = trodden[index]
                    if not current or current < depth - 0.05 then
                        if not current then snowCover.troddenCount = snowCover.troddenCount + 1 end
                        trodden[index] = depth
                        markSnowPointDirty(index, true)
                    end
                end
            end
        end
    end
end

local function clearSnowTrail()
    for index in pairs(snowCover.trodden or {}) do
        markSnowPointDirty(index)
    end
    snowCover.trodden = {}
    snowCover.troddenCount = 0
    snowCover.lastCarvePosition = nil
end

local function updateSnowTrail(weather)
    local player = LocalPlayer()
    if IsValid(player) and player:Alive() and player:IsOnGround() and player:GetMoveType() ~= MOVETYPE_NOCLIP then
        local position = player:GetPos()
        local last = snowCover.lastCarvePosition
        if not last or last:DistToSqr(position) >= snowCarveInterval * snowCarveInterval then
            snowCover.lastCarvePosition = position
            if getSnowCoverPointAt(position) then
                carveSnowAt(position)
            end
        end
    end

    // Fresh snowfall slowly fills the trail back in.
    local now = RealTime()
    if weather == "snow" and snowCover.troddenCount > 0 and now >= (snowCover.nextRefillAt or 0) then
        local elapsed = now - (snowCover.lastRefillAt or now)
        snowCover.lastRefillAt = now
        snowCover.nextRefillAt = now + snowTrailRefillInterval
        local fill = elapsed / snowFootprintFillSeconds
        if fill > 0 then
            for index, depth in pairs(snowCover.trodden) do
                local updated = depth - fill
                if updated <= 0.02 then
                    snowCover.trodden[index] = nil
                    snowCover.troddenCount = snowCover.troddenCount - 1
                    markSnowPointDirty(index)
                else
                    snowCover.trodden[index] = updated
                    if math.floor(updated * snowTrailRefillSteps) ~= math.floor(depth * snowTrailRefillSteps) then
                        markSnowPointDirty(index)
                    end
                end
            end
        end
    elseif weather ~= "snow" then
        snowCover.lastRefillAt = nil
    end
    rebuildDirtySnowChunks()
end

local function setSnowPreload(active)
    if active == (snowCover.preloadStep ~= nil) then return end
    if active then
        snowCover.preloadStartedAt = SysTime()
        snowCover.preloadStep = ZM_Loading and ZM_Loading:Begin("Settling snow cover") or false
    else
        if snowCover.preloadStep and ZM_Loading then
            local ready = snowCover.status == "ready"
            ZM_Loading:Finish(snowCover.preloadStep, ready and "ok" or "warn",
                ready and string.format("Settled snow cover (%d triangles)", snowCover.triangleCount or 0)
                    or "Snow cover still settling")
        end
        snowCover.preloadStep = nil
        snowCover.preloadDone = true
        snowCover.preloadSeconds = SysTime() - (snowCover.preloadStartedAt or SysTime())
        snowCover.preloadResult = snowCover.status == "ready" and "ready" or "timed out"
        print(string.format("[ZombieSim] Snow cover preload %s after %.2f s (%d triangles).",
            snowCover.preloadResult, snowCover.preloadSeconds, snowCover.triangleCount or 0))
    end
    if ZM_LoadingScreen and ZM_LoadingScreen.SetExtraHold then
        ZM_LoadingScreen:SetExtraHold("snowCover", active)
    end
end

// Only a freshly loaded map waits for its snow cover; weather changes during play build it in the background.
local function updateSnowPreload(amount, outdoorMap)
    if snowCover.preloadDone then return false end
    local mapName = game.GetMap()
    local needed = outdoorMap and amount > 0.002
        and (snowCover.map ~= mapName or snowCover.meshVersion ~= snowCoverMeshVersion
            or snowCover.detail ~= Atmosphere.GetQualityNumber("snowDetail", 1, 0.25, 1) or snowCover.status ~= "ready")
    if snowCover.preloadStep ~= nil then
        if not needed or SysTime() - snowCover.preloadStartedAt > snowPreloadMaxSeconds then
            setSnowPreload(false)
            return false
        end
        return true
    end
    if needed and SysTime() - Atmosphere.SessionStart < snowPreloadWindowSeconds then
        setSnowPreload(true)
        return true
    end
    if SysTime() - Atmosphere.SessionStart >= snowPreloadWindowSeconds then
        snowCover.preloadDone = true
    end
    return false
end

local function saveSnowCookie(amount)
    local now = RealTime()
    if now < (snowCover.nextCookieAt or 0) then return end
    snowCover.nextCookieAt = now + 2
    cookie.Set("zombiesim_snow_cover", string.format("%.4f", amount))
    cookie.Set("zombiesim_weather", Atmosphere.WeatherSynced and Atmosphere.Weather or (Atmosphere.CachedWeather or "clear"))
end

local function updateSnowCover()
    // Before the first sync, assume the last known weather so a cached cover neither grows nor melts wrongly.
    local weather = Atmosphere.WeatherSynced and Atmosphere.Weather or Atmosphere.CachedWeather
    local outdoorMap = hasOutdoorCityCells()
    local frameTime = FrameTime()
    local amount = Atmosphere.SnowCoverAmount or 0
    if weather == "snow" then
        amount = math.min(1, amount + frameTime / snowCoverBuildSeconds)
    else
        amount = math.max(0, amount - frameTime / (weather == "rain" and snowCoverRainMeltSeconds or snowCoverMeltSeconds))
    end
    Atmosphere.SnowCoverAmount = amount
    saveSnowCookie(amount)
    local preloading = updateSnowPreload(amount, outdoorMap)
    if amount <= 0 then
        if snowCover.status == "ready" and (snowCover.troddenCount or 0) > 0 then
            clearSnowTrail()
            rebuildDirtySnowChunks()
        end
        return
    end

    local mapName = game.GetMap()
    // A changed snow-detail setting resamples the cover in the background, like a new map would.
    if snowCover.map ~= mapName or snowCover.meshVersion ~= snowCoverMeshVersion
        or snowCover.detail ~= Atmosphere.GetQualityNumber("snowDetail", 1, 0.25, 1) then
        if not outdoorMap or not ensurePuddleMapSites() then return end
        beginSnowCover(mapName)
    end
    if snowCover.status == "sampling" then
        sampleSnowCover(preloading and snowPreloadPointsPerFrame or snowCoverPointsPerFrame)
    elseif snowCover.status == "meshing" then
        snowCover.stage = math.Round(amount * snowCoverStages) / snowCoverStages
        buildSnowCoverChunks(preloading and snowPreloadChunksPerFrame or snowCoverChunksPerFrame)
    elseif snowCover.status == "ready" then
        // A new coverage stage re-bakes only the chunks whose points it changes, a few per frame, so the cover
        // fills in (or thins) gradually.
        local stage = math.Round(amount * snowCoverStages) / snowCoverStages
        if stage ~= snowCover.stage then
            local previous = snowCover.stage or 0
            snowCover.stage = stage
            for key, chunk in pairs(snowCover.chunks) do
                if isSnowChunkAffectedByStage(chunk, previous, stage) then
                    snowCover.dirtyChunks[key] = true
                end
            end
        end
        updateSnowTrail(weather)
    end
end

// PlayerFootstep does not run clientside in singleplayer, so weather footsteps follow distance walked instead.
local function updateWeatherFootsteps()
    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() or not player:IsOnGround()
        or player:GetMoveType() == MOVETYPE_NOCLIP or player:WaterLevel() > 0 then
        lastStepPosition = nil
        stepDistance = 0
        return
    end
    local position = player:GetPos()
    local weather = Atmosphere.Weather
    if lastStepPosition then
        local dx = position.x - lastStepPosition.x
        local dy = position.y - lastStepPosition.y
        local moved = math.sqrt(dx * dx + dy * dy)
        // Teleports and cell transitions must not count as walking.
        if moved < 64 then
            stepDistance = stepDistance + moved
        end
    end
    lastStepPosition = position

    local speed = player:GetVelocity():Length2D()
    local stride = speed > 200 and 92 or 70
    if stepDistance < stride then return end
    stepDistance = 0

    local puddle = weather == "rain" and findPuddleAt(position) or nil
    local snowPoint = (Atmosphere.SnowCoverAmount or 0) > 0.15 and getSnowCoverPointAt(position) or nil
    if snowPoint and (snowCover.stage or 0) - snowPoint.patch * 0.6 < 0.15 then
        snowPoint = nil
    end
    local outdoors = isOutdoorCityCell(player) and not checkShelter(player, CurTime())
    local result
    if puddle then
        // Multiplayer puddle steps are handled by PlayerFootstep; keep other weather steps here.
        if not game.SinglePlayer() then return end
        addFootstepSplash(position, true)
        result = "puddle"
    elseif snowPoint then
        addSnowStep(position, true)
        result = "snow cover"
    elseif outdoors and weather == "snow" then
        addSnowStep(position, false)
        result = "snowfall"
    elseif outdoors and weather == "rain" then
        addFootstepSplash(position, false)
        result = "wet ground"
    end
    if result then
        Atmosphere.StepCount = (Atmosphere.StepCount or 0) + 1
        Atmosphere.LastStep = { surface = result, time = RealTime() }
    end
end

local function emitBreath(player, now)
    if (player.ZM_NextBreathAt or 0) > now then return end
    player.ZM_NextBreathAt = now + math.Rand(2.6, 4)
    if not weatherEmitter then
        weatherEmitter = ParticleEmitter(player:EyePos())
    end
    if not weatherEmitter then return end

    local aim = player:EyeAngles():Forward()
    local origin = player:EyePos() + aim * 10 - Vector(0, 0, 4)
    local velocity = player:GetVelocity()
    for _ = 1, 4 do
        local particle = weatherEmitter:Add("particle/particle_smokegrenade", origin + VectorRand() * 1.5)
        if particle then
            particle:SetDieTime(math.Rand(1, 1.5))
            particle:SetStartAlpha(28)
            particle:SetEndAlpha(0)
            particle:SetStartSize(math.Rand(1.5, 2.5))
            particle:SetEndSize(math.Rand(9, 13))
            particle:SetColor(236, 240, 245)
            particle:SetCollide(false)
            particle:SetAirResistance(60)
            particle:SetGravity(Vector(0, 0, 6))
            particle:SetVelocity(velocity * 0.8 + aim * math.Rand(22, 34) + VectorRand() * 4)
        end
    end
    Atmosphere.BreathPuffs = (Atmosphere.BreathPuffs or 0) + 1
end

// WinterBlend eases the cold grade and fog over winterBlendSeconds; FrostAmount additionally needs open sky.
local function updateWinter()
    local localPlayer = LocalPlayer()
    local outdoorCell = IsValid(localPlayer) and isOutdoorCityCell(localPlayer)
    local snowing = Atmosphere.Weather == "snow"
    local step = FrameTime() / winterBlendSeconds
    Atmosphere.WinterBlend = math.Approach(Atmosphere.WinterBlend or 0, (snowing and outdoorCell) and 1 or 0, step)
    local exposed = snowing and outdoorCell and not checkShelter(localPlayer, CurTime())
    Atmosphere.FrostAmount = math.Approach(Atmosphere.FrostAmount or 0, exposed and 1 or 0, step)
    if Atmosphere.WinterBlend < 0.5 or not outdoorCell then return end

    local now = CurTime()
    local eyePosition = EyePos()
    for _, other in ipairs(player.GetAll()) do
        if other:Alive() and other:EyePos():DistToSqr(eyePosition) < 1500 * 1500 then
            emitBreath(other, now)
        end
    end
end

local function drawFrostEdges()
    local amount = Atmosphere.FrostAmount or 0
    if amount <= 0.01 then return end
    local width, height = ScrW(), ScrH()
    local depth = math.floor(math.min(width, height) * 0.16)
    local stripSize = math.max(1, math.ceil(depth / frostEdgeStrips))
    cam.Start2D()
    for strip = 0, frostEdgeStrips - 1 do
        local falloff = 1 - strip / frostEdgeStrips
        surface.SetDrawColor(214, 228, 240, 34 * amount * falloff * falloff)
        local offset = strip * stripSize
        surface.DrawRect(0, offset, width, stripSize)
        surface.DrawRect(0, height - offset - stripSize, width, stripSize)
        surface.DrawRect(offset, 0, stripSize, height)
        surface.DrawRect(width - offset - stripSize, 0, stripSize, height)
    end
    cam.End2D()
end

local function updateWeatherEffects()
    weatherDiagnostics.weatherThinkAt = RealTime()
    local player = LocalPlayer()
    local weather = Atmosphere.Weather
    weatherDiagnostics.weather = weather
    weatherDiagnostics.playerValid = IsValid(player)
    weatherDiagnostics.outdoorCityCell = IsValid(player) and isOutdoorCityCell(player) or false
    if not IsValid(player) or not weatherDiagnostics.outdoorCityCell then
        Atmosphere:StopWeatherEffects()
        isSheltered = nil
        nextShelterCheckAt = 0
        return
    end
    if weather ~= "rain" and weather ~= "snow" then
        Atmosphere:StopWeatherEffects()
        return
    end

    local now = CurTime()
    if checkShelter(player, now) then
        Atmosphere:StopWeatherEffects()
        return
    end
    if weather == "rain" then
        startRainAmbience(player)
    else
        startWindAmbience(player, now)
    end

    local interval = weather == "rain" and 0.05 or 0.1
    local density = math.Clamp(rainDensityConVar:GetFloat(), 0.5, 2)
    local particlesPerBurst = weather == "rain" and math.Clamp(math.Round(4 * density), 2, 8) or math.Clamp(math.Round(3 * density), 2, 6)
    weatherDiagnostics.particleInterval = interval
    weatherDiagnostics.particlesPerBurst = particlesPerBurst
    weatherDiagnostics.rainDensity = density
    if now < nextWeatherParticleAt then return end
    nextWeatherParticleAt = now + interval
    local eyePosition = player:EyePos()
    local eyeAngles = EyeAngles()
    for _ = 1, particlesPerBurst do
        emitPrecipitationParticle(weather, eyePosition, eyeAngles)
    end
end

local function updateBoundaryMist()
    weatherDiagnostics.boundaryThinkAt = RealTime()
    local player = LocalPlayer()
    weatherDiagnostics.boundaryOutdoorCityCell = IsValid(player) and isOutdoorCityCell(player) or false
    if not weatherDiagnostics.boundaryOutdoorCityCell then
        Atmosphere:StopBoundaryEffects()
        return
    end

    local now = CurTime()
    if now < nextBoundaryParticleAt then return end
    nextBoundaryParticleAt = now + 0.12
    if checkShelter(player, now) then
        Atmosphere:StopBoundaryEffects()
        return
    end

    local gate = findNearbyTransitionGate(player:GetPos())
    if not gate then
        Atmosphere:StopBoundaryEffects()
        return
    end
    local fog = Atmosphere:GetFogSettings()
    if not fog then
        Atmosphere:StopBoundaryEffects()
        return
    end
    emitBoundaryMist(gate, fog.color)
end

local function updateGrain()
    local grain = GetConVar("zombiesim_atmosphere_grain")
    if not grain or not grain:GetBool() or (ZM_LauncherMenu and ZM_LauncherMenu.Active) then return end
    if ZM_LoadingScreen and CurTime() < ZM_LoadingScreen.HideUntil then return end

    local now = RealTime()
    if now >= nextGrainUpdateAt then
        nextGrainUpdateAt = now + 0.075
        grainSeed = grainSeed + 1
        grainRects = {}
        local width, height = ScrW(), ScrH()
        for index = 1, 52 do
            grainRects[#grainRects + 1] = {
                x = math.floor(util.SharedRandom("ZM.Atmosphere.GrainX" .. grainSeed .. ":" .. index, 0, width)),
                y = math.floor(util.SharedRandom("ZM.Atmosphere.GrainY" .. grainSeed .. ":" .. index, 0, height)),
                size = math.floor(util.SharedRandom("ZM.Atmosphere.GrainSize" .. grainSeed .. ":" .. index, 1, 4)),
                shade = math.floor(util.SharedRandom("ZM.Atmosphere.GrainShade" .. grainSeed .. ":" .. index, 130, 256))
            }
        end
    end

    cam.Start2D()
    for _, rect in ipairs(grainRects) do
        surface.SetDrawColor(rect.shade, rect.shade, rect.shade, 18)
        surface.DrawRect(rect.x, rect.y, rect.size, rect.size)
    end
    cam.End2D()
end

net.Receive("ZM.Atmosphere.Weather", function()
    local code = net.ReadUInt(2)
    local weather = ({ [0] = "clear", [1] = "rain", [2] = "snow" })[code]
    if not weather then
        ErrorNoHalt("[ZombieSim] Received an unknown weather code: " .. tostring(code) .. "\n")
        return
    end
    Atmosphere:SetWeather(weather)
    Atmosphere.WeatherSynced = true
    local snowAmount = net.ReadFloat()
    if snowAmount == snowAmount then
        Atmosphere.SnowCoverAmount = math.Clamp(snowAmount, 0, 1)
    end
end)

hook.Add("Think", "ZM.Atmosphere.WeatherEffects", updateWeatherEffects)
hook.Add("Think", "ZM.Atmosphere.WetPuddles", updateWetPuddles)
hook.Add("Think", "ZM.Atmosphere.BoundaryMist", updateBoundaryMist)
hook.Add("Think", "ZM.Atmosphere.WeatherFootsteps", updateWeatherFootsteps)
hook.Add("Think", "ZM.Atmosphere.Winter", updateWinter)
hook.Add("Think", "ZM.Atmosphere.SnowCover", updateSnowCover)
hook.Remove("PostDrawOpaqueRenderables", "ZM.Atmosphere.SnowCover")
local identityMatrix = Matrix()
hook.Add("PreDrawTranslucentRenderables", "ZM.Atmosphere.SnowCover", function(drawingDepth, drawingSkybox)
    snowCover.hookCount = (snowCover.hookCount or 0) + 1
    if drawingDepth or drawingSkybox then return end
    local amount = Atmosphere.SnowCoverAmount or 0
    if amount <= 0.002 or snowCover.map ~= game.GetMap() then return end
    // The settled pattern lives in the vertices; this only fades the first dusting in and the last of a melt out.
    local fade = math.min(1, amount * 3)
    local coverAlpha = fade * fade * (3 - 2 * fade)
    // Static meshes inherit whatever model matrix the last entity left behind; draw in world space.
    cam.PushModelMatrix(identityMatrix)
    if snowCover.chunkList and (snowCover.meshCount or 0) > 0 then
        if snowFloorTexture then
            local current = snowCoverMaterial:GetTexture("$basetexture")
            if not current or current:GetName() ~= snowFloorTexture:GetName() then
                snowCoverMaterial:SetTexture("$basetexture", snowFloorTexture)
                snowCover.textureReapplied = (snowCover.textureReapplied or 0) + 1
            end
        end
        snowCoverMaterial:SetFloat("$alpha", coverAlpha)
        render.SetMaterial(snowCoverMaterial)
        // IMesh:Draw is not engine-culled: skip chunks outside the view cone or hidden by opaque fog.
        local eyeX, eyeY, eyeZ = EyePos():Unpack()
        local forwardX, forwardY, forwardZ = EyeVector():Unpack()
        local view = render.GetViewSetup and render.GetViewSetup() or nil
        local coneSin, coneCos
        if view and view.fov and not view.ortho then
            local tanHorizontal = math.tan(math.rad(math.Clamp(view.fov, 1, 170)) * 0.5)
            local aspect = view.aspect
            if not aspect or aspect <= 0 then
                aspect = (view.w or view.width or ScrW()) / math.max(1, view.h or view.height or ScrH())
            end
            local tanVertical = tanHorizontal / aspect
            local halfAngle = math.atan(math.sqrt(tanHorizontal * tanHorizontal + tanVertical * tanVertical))
                + snowCoverCullConeMargin
            if halfAngle < math.pi * 0.5 then
                coneSin, coneCos = math.sin(halfAngle), math.cos(halfAngle)
            end
        end
        local maxDistance = (view and view.ortho) and nil or snowCoverFogCullDistance
        local qualityDistance = Atmosphere.GetQualityNumber("snowDrawDistance", 0, 0, 100000)
        if qualityDistance > 0 and not (view and view.ortho) then
            maxDistance = maxDistance and math.min(maxDistance, qualityDistance) or qualityDistance
        end
        local drawn, culled = 0, 0
        for _, chunk in ipairs(snowCover.chunkList) do
            if chunk.imesh then
                local radius = chunk.radius
                local visible = true
                if radius then
                    local dx, dy, dz = chunk.centerX - eyeX, chunk.centerY - eyeY, chunk.centerZ - eyeZ
                    local distanceSqr = dx * dx + dy * dy + dz * dz
                    local along = dx * forwardX + dy * forwardY + dz * forwardZ
                    visible = along >= -radius
                    if visible and maxDistance then
                        local reach = maxDistance + radius
                        visible = distanceSqr <= reach * reach
                    end
                    if visible and coneSin and distanceSqr > radius * radius then
                        local lateral = math.sqrt(math.max(0, distanceSqr - along * along))
                        visible = lateral * coneCos - along * coneSin <= radius
                    end
                end
                if visible then
                    chunk.imesh:Draw()
                    drawn = drawn + 1
                else
                    culled = culled + 1
                end
            end
        end
        snowCover.lastDrawnChunks = drawn
        snowCover.lastCulledChunks = culled
        snowCover.drawCount = (snowCover.drawCount or 0) + 1
    end
    cam.PopModelMatrix()
end)
hook.Add("PreCleanupMap", "ZM.Atmosphere.WeatherCleanup", function()
    Atmosphere:StopWeatherEffects()
    Atmosphere:StopBoundaryEffects()
    table.Empty(puddles)
    table.Empty(puddleSites)
    table.Empty(splashRings)
    puddleSiteMap = nil
    puddleSiteCursor = 1
    puddleWorldMinimum = nil
    puddleWorldMaximum = nil
    Atmosphere.PuddleSiteMap = nil
    Atmosphere.PuddleSiteCursor = puddleSiteCursor
    Atmosphere.PuddleWorldMinimum = nil
    Atmosphere.PuddleWorldMaximum = nil
    Atmosphere.PuddleBoundsErrorMap = nil
    Atmosphere.PuddleRenderLobes = 0
    Atmosphere.PuddleRenderClusters = 0
    Atmosphere.PuddlesDryAt = nil
    clearSnowTrail()
    lastStepPosition = nil
    stepDistance = 0
    nextWindGustAt = 0
    isSheltered = nil
    nextShelterCheckAt = 0
    nextPuddleAt = 0
    puddleSiteDebt = 0
end)
hook.Add("ShutDown", "ZM.Atmosphere.WeatherCleanup", function()
    Atmosphere:StopWeatherEffects()
    for _, emitter in ipairs(Atmosphere.RetiredWeatherEmitters) do emitter:Finish() end
    Atmosphere.RetiredWeatherEmitters = {}
    Atmosphere:StopBoundaryEffects()
end)

hook.Add("PlayerFootstep", "ZM.Atmosphere.RainFootstepSplash", function(player, position)
    local localPlayer = LocalPlayer()
    if game.SinglePlayer() or player ~= localPlayer or not IsValid(localPlayer)
        or Atmosphere.Weather ~= "rain" or not isOutdoorCityCell(localPlayer)
        or checkShelter(localPlayer, CurTime()) then
        return
    end

    local puddle = findPuddleAt(position)
    if not puddle then return end
    if not IsFirstTimePredicted() then return true end

    local soundPlayed = addFootstepSplash(position, true)
    Atmosphere.StepCount = (Atmosphere.StepCount or 0) + 1
    Atmosphere.LastStep = { surface = "puddle", time = RealTime() }
    if soundPlayed then return true end
end)

// Per-frame puddle render scratch lives in one table to stay under the chunk's local-variable limit.
local puddleRender = {}
// Candidate records, selection lists and per-lobe render centres are reused; results only live for one frame.
puddleRender.candidatePool = {}
puddleRender.candidates = {}
puddleRender.selected = {}
puddleRender.selectedClusters = {}

local function comparePuddleCandidates(left, right)
    return left.distance < right.distance
end

local function getVisiblePuddleLobes(now)
    local candidates, selected, selectedClusters = puddleRender.candidates, puddleRender.selected, puddleRender.selectedClusters
    for index = #candidates, 1, -1 do candidates[index] = nil end
    for index = #selected, 1, -1 do selected[index] = nil end
    for key in pairs(selectedClusters) do selectedClusters[key] = nil end
    if #puddles == 0 or not puddleMaterial then return selected, 0 end

    local cameraPosition = EyePos()
    local viewDirection = EyeVector()
    local cameraX, cameraY, cameraZ = cameraPosition.x, cameraPosition.y, cameraPosition.z
    local viewX, viewY, viewZ = viewDirection.x, viewDirection.y, viewDirection.z
    for _, puddle in ipairs(puddles) do
        if not puddle.removed then
            local fade = 1
            if Atmosphere.PuddlesDryAt then
                fade = math.Clamp((Atmosphere.PuddlesDryAt - now) / 3, 0, 1)
            elseif puddle.expiresAt - now < 4 then
                fade = math.Clamp((puddle.expiresAt - now) / 4, 0, 1)
            end
            if fade > 0 then
                // Drying pools contract toward their centre as they fade.
                local spread = (puddle.spread or 1) * (0.7 + 0.3 * fade)
                for _, lobe in ipairs(puddle.lobes) do
                    if not lobe.smoothEdges then
                        lobe.smoothEdges = true
                        lobe.edgeFactors = createPuddleEdgeFactors()
                        lobe.targetWidth = lobe.targetWidth or lobe.width
                        lobe.targetHeight = lobe.targetHeight or lobe.height
                        lobe.createdAt = lobe.createdAt or now - 1.25
                    end

                    local origin, lobePosition = puddle.position, lobe.position
                    local centerX = origin.x + (lobePosition.x - origin.x) * spread
                    local centerY = origin.y + (lobePosition.y - origin.y) * spread
                    local centerZ = lobePosition.z
                    local radius = math.max(lobe.targetWidth or 0, lobe.targetHeight or 0) * 0.6 * spread
                    local dx, dy, dz = centerX - cameraX, centerY - cameraY, centerZ - cameraZ
                    if dx * viewX + dy * viewY + dz * viewZ > -radius then
                        local center = lobe.renderCenter
                        if not center then
                            center = Vector()
                            lobe.renderCenter = center
                        end
                        center:SetUnpacked(centerX, centerY, centerZ)
                        local candidateIndex = #candidates + 1
                        local candidate = puddleRender.candidatePool[candidateIndex]
                        if not candidate then
                            candidate = {}
                            puddleRender.candidatePool[candidateIndex] = candidate
                        end
                        candidate.puddle = puddle
                        candidate.lobe = lobe
                        candidate.fade = fade
                        candidate.center = center
                        candidate.spread = spread
                        candidate.distance = dx * dx + dy * dy + dz * dz
                        candidates[candidateIndex] = candidate
                    end
                end
            end
        end
    end

    table.sort(candidates, comparePuddleCandidates)
    local clusterCount = 0
    local clusterLimit = getVisiblePuddleClusterLimit()
    local lobeLimit = getVisiblePuddleLobeLimit()
    for _, candidate in ipairs(candidates) do
        if not selectedClusters[candidate.puddle] then
            if clusterCount >= clusterLimit then break end
            selectedClusters[candidate.puddle] = true
            clusterCount = clusterCount + 1
        end
        selected[#selected + 1] = candidate
        if #selected >= lobeLimit then break end
    end
    return selected, clusterCount
end

local puddleUpNormal = Vector(0, 0, 1)
puddleRender.tangent = Vector()
puddleRender.bitangent = Vector()
// Shapes and their ring vertices are pooled; they only live for the frame that builds them.
puddleRender.shapePool = {}
puddleRender.shapes = {}

local function buildPuddleGeometry(candidates, now, opacity)
    local shapes = puddleRender.shapes
    for index = #shapes, 1, -1 do shapes[index] = nil end
    local tangent, bitangent = puddleRender.tangent, puddleRender.bitangent
    for _, candidate in ipairs(candidates) do
        local lobe = candidate.lobe
        local normal = lobe.normal or puddleUpNormal
        local nx, ny, nz = normal.x, normal.y, normal.z
        tangent:SetUnpacked(1 - nx * nx, -ny * nx, -nz * nx)
        if tangent:LengthSqr() < 0.01 then
            tangent:SetUnpacked(-nx * ny, 1 - ny * ny, -nz * ny)
        end
        tangent:Normalize()
        local tx, ty, tz = tangent.x, tangent.y, tangent.z
        bitangent:SetUnpacked(ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx)
        bitangent:Normalize()
        local bx, by, bz = bitangent.x, bitangent.y, bitangent.z

        local progress = math.Clamp((now - (lobe.createdAt or now - 1.25)) / 1.25, 0, 1)
        local growth = progress * progress * (3 - 2 * progress)
        local resize = math.Clamp(FrameTime() * 3, 0, 1)
        lobe.width = Lerp(resize, lobe.width or lobe.targetWidth, lobe.targetWidth or lobe.width)
        lobe.height = Lerp(resize, lobe.height or lobe.targetHeight, lobe.targetHeight or lobe.height)
        local spread = candidate.spread or 1
        local center = candidate.center or lobe.position
        local width = lobe.width * growth * spread
        local height = lobe.height * growth * spread
        local alpha = math.Clamp(255 * math.min(opacity * 3.5, 0.85) * lobe.opacityScale * candidate.fade * growth, 0, 220)
        local shapeIndex = #shapes + 1
        local shape = puddleRender.shapePool[shapeIndex]
        if not shape then
            shape = { inner = {}, outer = {} }
            puddleRender.shapePool[shapeIndex] = shape
        end
        local inner, outer = shape.inner, shape.outer
        local cx, cy, cz = center.x, center.y, center.z
        for segment = 1, puddleMeshSegments do
            local angle = math.rad((segment - 1) * 360 / puddleMeshSegments + lobe.rotation)
            local edgeFactor = lobe.edgeFactors[segment] or 1
            local along = math.cos(angle) * edgeFactor * width * 0.5
            local across = math.sin(angle) * edgeFactor * height * 0.5
            local ox = tx * along + bx * across
            local oy = ty * along + by * across
            local oz = tz * along + bz * across
            local innerPoint, outerPoint = inner[segment], outer[segment]
            if not innerPoint then
                innerPoint, outerPoint = Vector(), Vector()
                inner[segment], outer[segment] = innerPoint, outerPoint
            end
            innerPoint:SetUnpacked(cx + ox * 0.7, cy + oy * 0.7, cz + oz * 0.7)
            outerPoint:SetUnpacked(cx + ox, cy + oy, cz + oz)
        end
        shape.center = center
        shape.normal = normal
        shape.step = (candidate.distance or 0) > puddleMeshLodDistanceSqr and 2 or 1
        shape.alpha = alpha
        shape.reflectAlpha = nil
        shapes[shapeIndex] = shape
    end
    return shapes
end

local puddleWetColor = { 6, 8, 10 }
local puddleSheenColor = { 58, 66, 78 }
local puddleReflectionColor = { 255, 255, 255 }

local function drawPuddlePass(shapes, material, color, alphaScale, alphaKey)
    if #shapes == 0 then return end
    render.SetMaterial(material)
    local segments = puddleMeshSegments
    local segmentCount = 0
    for _, shape in ipairs(shapes) do
        segmentCount = segmentCount + math.ceil(segments / shape.step)
    end
    local position, normalFn, texCoord, vertexColor, advance = mesh.Position, mesh.Normal, mesh.TexCoord, mesh.Color, mesh.AdvanceVertex
    // Solid centre fan as triangles, then the feathered rim as quads. Source splits a quad (0,1,2)/(0,2,3),
    // so innerA, outerA, outerB, innerB reproduces the former two rim triangles with 4 vertices instead of 6.
    mesh.Begin(MATERIAL_TRIANGLES, segmentCount)
    for _, shape in ipairs(shapes) do
        local step = shape.step
        local alpha = (shape[alphaKey or "alpha"] or shape.alpha) * alphaScale
        local shapeColor = color or shape.color
        local red, green, blue = shapeColor[1], shapeColor[2], shapeColor[3]
        local center, normal, inner = shape.center, shape.normal, shape.inner
        for segment = 1, segments, step do
            local nextSegment = (segment + step - 1) % segments + 1
            position(center) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
            position(inner[segment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
            position(inner[nextSegment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
        end
    end
    mesh.End()
    mesh.Begin(MATERIAL_QUADS, segmentCount)
    for _, shape in ipairs(shapes) do
        local step = shape.step
        local alpha = (shape[alphaKey or "alpha"] or shape.alpha) * alphaScale
        local shapeColor = color or shape.color
        local red, green, blue = shapeColor[1], shapeColor[2], shapeColor[3]
        local normal, inner, outer = shape.normal, shape.inner, shape.outer
        for segment = 1, segments, step do
            local nextSegment = (segment + step - 1) % segments + 1
            position(inner[segment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
            position(outer[segment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, 0) advance()
            position(outer[nextSegment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, 0) advance()
            position(inner[nextSegment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
        end
    end
    mesh.End()
end

local function drawPuddleMesh(candidates, now, opacity)
    if #candidates == 0 or not puddleMaterial then return end

    local shapes = buildPuddleGeometry(candidates, now, opacity)
    drawPuddlePass(shapes, puddleMaterial, puddleWetColor, 1)
    if not puddleReflectionMaterial then
        drawPuddlePass(shapes, puddleSheenMaterial, puddleSheenColor, 0.55)
        return
    end

    // Schlick-style Fresnel: shallow viewing angles reflect strongly, looking straight down mostly shows the wet ground.
    local eye = EyePos()
    local ex, ey, ez = eye.x, eye.y, eye.z
    for _, shape in ipairs(shapes) do
        local center, normal = shape.center, shape.normal
        local dx, dy, dz = ex - center.x, ey - center.y, ez - center.z
        local length = math.sqrt(dx * dx + dy * dy + dz * dz)
        local facing = 0
        if length > 0 then
            facing = math.Clamp(math.abs((dx * normal.x + dy * normal.y + dz * normal.z) / length), 0, 1)
        end
        local fresnel = 0.2 + 0.8 * (1 - facing) ^ 3
        shape.reflectAlpha = shape.alpha * fresnel
    end
    drawPuddlePass(shapes, puddleReflectionMaterial, puddleReflectionColor, 1, "reflectAlpha")
end

local puddleDropLifetime = 0.32
local maxPuddleDropRings = 240
local maxPuddleDropCrowns = 40
local puddleDropCrownDistance = 500
local puddleDropBeamMaterial = Material("particle/particledefault")
Atmosphere.PuddleImpactMaxIndices = maxPuddleDropRings * 6

local function hashUnit(first, second)
    local value = math.sin(first * 12.9898 + second * 78.233) * 43758.5453
    return value - math.floor(value)
end

puddleRender.ringPosition = Vector()
puddleRender.ringQuadCorners = { { -1, -1, 0, 0 }, { 1, -1, 1, 0 }, { 1, 1, 1, 1 }, { -1, 1, 0, 1 } }
puddleRender.EmitRingQuad = function(center, normal, tangent, bitangent, size, red, green, blue, alpha)
    local half = size * 0.5
    local position = puddleRender.ringPosition
    local cx, cy, cz = center.x, center.y, center.z
    local rx, ry, rz = tangent.x * half, tangent.y * half, tangent.z * half
    local ux, uy, uz = bitangent.x * half, bitangent.y * half, bitangent.z * half
    for index = 1, 4 do
        local corner = puddleRender.ringQuadCorners[index]
        local sx, sy = corner[1], corner[2]
        position:SetUnpacked(cx + rx * sx + ux * sy, cy + ry * sx + uy * sy, cz + rz * sx + uz * sy)
        mesh.Position(position)
        mesh.Normal(normal)
        mesh.TexCoord(0, corner[3], corner[4])
        mesh.Color(red, green, blue, alpha)
        mesh.AdvanceVertex()
    end
end

// Drop records are pooled across frames; each frame overwrites the first #drops entries.
puddleRender.dropPool = {}
puddleRender.drops = {}
puddleRender.dropTangent = Vector()
puddleRender.dropBitangent = Vector()
puddleRender.crownEnd = Vector()
puddleRender.crownColor = Color(200, 215, 225, 0)

// Each lobe owns deterministic drop slots; every slot re-rolls its impact point each cycle,
// so the count scales with rain density and puddle area without allocating per-drop state.
local function drawPuddleRainImpacts(candidates, now)
    if #candidates == 0 then
        Atmosphere.PuddleDropRings = 0
        Atmosphere.PuddleDropCrowns = 0
        Atmosphere.PuddleImpactQuads = 0
        return
    end

    local density = math.Clamp(rainDensityConVar:GetFloat(), 0.5, 2)
    local rippleAmount = Atmosphere.GetQualityNumber("rippleAmount", 1, 0.1, 1)
    local maxRings = math.max(1, math.floor(maxPuddleDropRings * rippleAmount))
    local cameraPosition = EyePos()
    local drops = puddleRender.drops
    for index = #drops, 1, -1 do drops[index] = nil end
    for candidateIndex, candidate in ipairs(candidates) do
        local lobe = candidate.lobe
        local spread = candidate.spread or 1
        local width = (lobe.width or 0) * spread
        local height = (lobe.height or 0) * spread
        if width > 4 and height > 4 then
            local area = width * height / (110 * 90)
            local slots = math.Clamp(math.Round(6 * density * rippleAmount * area * candidate.fade), 1, 30)
            local seed = (lobe.rotation or candidateIndex) * 1.37
            local normal = lobe.normal or puddleUpNormal
            local center = candidate.center
            for slot = 1, slots do
                local offset = hashUnit(seed, slot) * puddleDropLifetime
                local cycle = math.floor((now + offset) / puddleDropLifetime)
                local phase = ((now + offset) % puddleDropLifetime) / puddleDropLifetime
                local angle = hashUnit(cycle + seed, slot * 3.1) * math.pi * 2
                local radius = math.sqrt(hashUnit(slot * 1.7, cycle + seed * 0.5)) * 0.42
                local dropIndex = #drops + 1
                local drop = puddleRender.dropPool[dropIndex]
                if not drop then
                    drop = { position = Vector() }
                    puddleRender.dropPool[dropIndex] = drop
                end
                drop.position:SetUnpacked(
                    center.x + math.cos(angle) * width * radius + normal.x * 1.1,
                    center.y + math.sin(angle) * height * radius + normal.y * 1.1,
                    center.z + normal.z * 1.1
                )
                drop.normal = normal
                drop.phase = phase
                drop.weight = 0.6 + hashUnit(cycle, slot + seed) * 0.6
                drop.fade = candidate.fade
                drops[dropIndex] = drop
                if #drops >= maxRings then break end
            end
        end
        if #drops >= maxRings then break end
    end

    if #drops == 0 then
        Atmosphere.PuddleDropRings = 0
        Atmosphere.PuddleDropCrowns = 0
        Atmosphere.PuddleImpactQuads = 0
        return
    end

    // One quad per drop: at the 240-drop cap this uses only 1,440 indices.
    if not splashRingMaterial:IsError() then
        render.SetMaterial(splashRingMaterial)
        mesh.Begin(MATERIAL_QUADS, #drops)
        for _, drop in ipairs(drops) do
            local normal = drop.normal
            local nx, ny, nz = normal.x, normal.y, normal.z
            local tangent, bitangent = puddleRender.dropTangent, puddleRender.dropBitangent
            tangent:SetUnpacked(1 - nx * nx, -ny * nx, -nz * nx)
            if tangent:LengthSqr() < 0.01 then
                tangent:SetUnpacked(-nx * ny, 1 - ny * ny, -nz * ny)
            end
            tangent:Normalize()
            local tx, ty, tz = tangent.x, tangent.y, tangent.z
            bitangent:SetUnpacked(ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx)
            local inverse = 1 - drop.phase
            local growth = 1 - inverse * inverse
            local size = (2 + growth * 9) * drop.weight
            local alpha = 72 * inverse * math.sqrt(inverse) * drop.fade
            puddleRender.EmitRingQuad(drop.position, normal, tangent, bitangent, size, 168, 188, 198, alpha)
        end
        mesh.End()
        Atmosphere.PuddleImpactQuads = #drops
    else
        Atmosphere.PuddleImpactQuads = 0
    end

    // Nearby drops throw a tiny upward fleck at the moment of impact.
    local crowns = 0
    render.SetMaterial(puddleDropBeamMaterial)
    local crownDistance = puddleDropCrownDistance * puddleDropCrownDistance
    for _, drop in ipairs(drops) do
        if crowns >= maxPuddleDropCrowns then break end
        if drop.phase < 0.18 and drop.position:DistToSqr(cameraPosition) < crownDistance then
            crowns = crowns + 1
            local progress = drop.phase / 0.18
            local lift = math.sin(progress * math.pi) * 4 * drop.weight
            local position, normal = drop.position, drop.normal
            local length = 1 + lift
            puddleRender.crownEnd:SetUnpacked(position.x + normal.x * length, position.y + normal.y * length, position.z + normal.z * length)
            puddleRender.crownColor.a = 110 * (1 - progress) * drop.fade
            render.DrawBeam(position, puddleRender.crownEnd, 0.6, 0, 1, puddleRender.crownColor)
        end
    end
    Atmosphere.PuddleDropRings = #drops
    Atmosphere.PuddleDropCrowns = crowns
end

puddleRender.splashColor = Color(170, 205, 218, 0)
puddleRender.DrawFootstepSplashes = function(now)
    // Rain crowns bind their beam material; footsteps must rebind their own texture.
    render.SetMaterial(splashRingMaterial)
    for index = #splashRings, 1, -1 do
        local splash = splashRings[index]
        local life = math.Clamp((splash.expiresAt - now) / 0.45, 0, 1)
        if life <= 0 then
            table.remove(splashRings, index)
        elseif not splashRingMaterial:IsError() and splash.position:ToScreen().visible then
            local size = (splash.size or 44) * (1 - life) + 8
            puddleRender.splashColor.a = 90 * life
            render.DrawQuadEasy(splash.position, puddleUpNormal, size, size, puddleRender.splashColor, splash.rotation)
        end
    end
end

hook.Add("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", function(drawingDepth, drawingSkybox)
    if drawingDepth or drawingSkybox or ZM_WorldMap and ZM_WorldMap.Capturing then return end

    local now = CurTime()
    local puddleOpacity = math.Clamp(puddleOpacityConVar:GetFloat(), 0.05, 0.45)
    local visiblePuddles, visiblePuddleClusters = getVisiblePuddleLobes(now)
    Atmosphere.PuddleRenderLobes = #visiblePuddles
    Atmosphere.PuddleRenderClusters = visiblePuddleClusters
    drawPuddleMesh(visiblePuddles, now, puddleOpacity)

    if Atmosphere.Weather == "rain" and not Atmosphere.PuddlesDryAt then
        drawPuddleRainImpacts(visiblePuddles, now)
    else
        Atmosphere.PuddleDropRings = 0
        Atmosphere.PuddleDropCrowns = 0
        Atmosphere.PuddleImpactQuads = 0
    end
    puddleRender.DrawFootstepSplashes(now)
end)

hook.Add("SetupWorldFog", "ZM.Atmosphere.WorldFog", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then
        recordHookResult("SetupWorldFog", nil, false, nil, nil, "launcher menu active")
        return
    end
    local settings = Atmosphere:GetFogSettings()
    local applied = settings and applyFog(settings) or false
    // Only fully opaque fog hides geometry beyond its end, so only then may the snow draw cull by distance.
    snowCoverFogCullDistance = (applied and settings.maxDensity >= 0.999) and settings.finish or nil
    local reason
    if not settings then reason = "no active profile" end
    recordHookResult("SetupWorldFog", applied, applied, settings, 1, reason)
    return applied
end)

hook.Add("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", function(scale)
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then
        recordHookResult("SetupSkyboxFog", nil, false, nil, scale, "launcher menu active")
        return
    end
    local settings = Atmosphere:GetFogSettings()
    // The runtime 3D skybox grades this fog to opaque at its horizon wall.
    if settings and ZM_Skybox and ZM_Skybox.GetSkyboxFog then settings = ZM_Skybox:GetSkyboxFog(settings) end
    local applied = settings and applyFog(settings, scale) or false
    local reason
    if not settings then reason = "no active profile" end
    recordHookResult("SetupSkyboxFog", applied, applied, settings, scale, reason)
    return applied
end)

local colourCorrectionSettings = {}
local emptyTable = {}

hook.Add("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then
        recordHookResult("RenderScreenspaceEffects", nil, false, nil, nil, "launcher menu active")
        return
    end
    local profile = Atmosphere:GetActiveProfile()
    local correction = profile and profile.colorCorrection
    if type(correction) ~= "table" then
        recordHookResult("RenderScreenspaceEffects", nil, false, nil, nil, "no active colour-correction profile")
        return
    end

    local add = correction.add or emptyTable
    local multiply = correction.multiply or emptyTable
    local colorSettings = colourCorrectionSettings
    colorSettings["$pp_colour_addr"] = getNumber(add[1], 0)
    colorSettings["$pp_colour_addg"] = getNumber(add[2], 0)
    colorSettings["$pp_colour_addb"] = getNumber(add[3], 0)
    colorSettings["$pp_colour_brightness"] = getNumber(correction.brightness, 0)
    colorSettings["$pp_colour_contrast"] = getNumber(correction.contrast, 1)
    colorSettings["$pp_colour_colour"] = getNumber(correction.colour, 1)
    colorSettings["$pp_colour_mulr"] = getNumber(multiply[1], 1)
    colorSettings["$pp_colour_mulg"] = getNumber(multiply[2], 1)
    colorSettings["$pp_colour_mulb"] = getNumber(multiply[3], 1)
    // Cold grade: desaturate, cool the shadows and lift the mids slightly while snow is falling.
    local winter = Atmosphere.WinterBlend or 0
    if winter > 0.001 then
        colorSettings["$pp_colour_colour"] = colorSettings["$pp_colour_colour"] * (1 - 0.32 * winter)
        colorSettings["$pp_colour_brightness"] = colorSettings["$pp_colour_brightness"] + 0.025 * winter
        colorSettings["$pp_colour_contrast"] = colorSettings["$pp_colour_contrast"] * (1 - 0.05 * winter)
        colorSettings["$pp_colour_addr"] = colorSettings["$pp_colour_addr"] - 0.01 * winter
        colorSettings["$pp_colour_addb"] = colorSettings["$pp_colour_addb"] + 0.025 * winter
        colorSettings["$pp_colour_mulb"] = colorSettings["$pp_colour_mulb"] + 0.08 * winter
    end
    // The low preset turns off the full-screen grade and grain; frost edges remain because they convey the weather.
    local radiationGray = ZM_RadiationFeedback.GetGrayscale()
    local radiationSeverity = ZM_RadiationFeedback.GetExtremeVisualSeverity()
    colorSettings["$pp_colour_colour"] = colorSettings["$pp_colour_colour"] * (1 - radiationGray)
    if radiationGray > 0 then
        colorSettings["$pp_colour_addr"] = colorSettings["$pp_colour_addr"] * (1 - radiationGray)
        colorSettings["$pp_colour_addg"] = colorSettings["$pp_colour_addg"] * (1 - radiationGray)
        colorSettings["$pp_colour_addb"] = colorSettings["$pp_colour_addb"] * (1 - radiationGray)
        colorSettings["$pp_colour_mulr"] = colorSettings["$pp_colour_mulr"] * (1 - radiationGray)
        colorSettings["$pp_colour_mulg"] = colorSettings["$pp_colour_mulg"] * (1 - radiationGray)
        colorSettings["$pp_colour_mulb"] = colorSettings["$pp_colour_mulb"] * (1 - radiationGray)
        colorSettings["$pp_colour_contrast"] = colorSettings["$pp_colour_contrast"] + 0.4 * radiationSeverity
        colorSettings["$pp_colour_brightness"] = colorSettings["$pp_colour_brightness"] - 0.04 * radiationSeverity
    end
    if Atmosphere.GetQualityNumber("screenEffects", 1, 0, 1) < 0.5 then
        if ZM_RadiationFeedback.GetGrayscale() > 0 then
            colorSettings["$pp_colour_addr"], colorSettings["$pp_colour_addg"], colorSettings["$pp_colour_addb"] = 0, 0, 0
            colorSettings["$pp_colour_mulr"], colorSettings["$pp_colour_mulg"], colorSettings["$pp_colour_mulb"] = 0, 0, 0
            colorSettings["$pp_colour_brightness"], colorSettings["$pp_colour_contrast"] = -0.04 * radiationSeverity, 1 + 0.4 * radiationSeverity
            colorSettings["$pp_colour_colour"] = 1 - radiationGray
            DrawColorModify(colorSettings)
        end
        recordHookResult("RenderScreenspaceEffects", nil, false, nil, nil, "screen effects disabled by quality setting")
        drawFrostEdges()
        return
    end
    DrawColorModify(colorSettings)
    recordHookResult("RenderScreenspaceEffects", nil, true, Atmosphere:GetFogSettings(), nil,
        "DrawColorModify applied; hook chain continues", colorSettings)
    drawFrostEdges()
    updateGrain()
end)

net.Receive("ZM.SetAtmosphereProfile", function()
    local profileIndex = net.ReadUInt(8)
    local expected = getExpectedCell(LocalPlayer())
    Atmosphere.LastProfileReceive = {
        time = RealTime(),
        profileIndex = profileIndex,
        worldDataLoaded = ZM_World:IsLoaded(),
        expectedProfileIndex = expected and expected.profileIndex or nil,
        cellX = expected and expected.cellX or nil,
        cellY = expected and expected.cellY or nil
    }
    Atmosphere:ApplyProfile(profileIndex, "server net message")
    if Atmosphere.ActiveProfileIndex == profileIndex and not Atmosphere.PendingProfileIndex then
        ZM_Loading:Step("Applied atmosphere profile " .. profileIndex)
    elseif Atmosphere.PendingProfileIndex then
        Atmosphere.LoadingStepId = ZM_Loading:Begin("Applying atmosphere (waiting for world data)")
    else
        ZM_Loading:Step("Unknown atmosphere profile " .. profileIndex, "fail")
    end
end)

net.Receive("ZM.AtmosphereStatus.Request", function()
    local requestId = net.ReadUInt(16)
    local encoded = util.TableToJSON(Atmosphere:GetDiagnosticSnapshot(), false) or "{}"
    net.Start("ZM.AtmosphereStatus.Result")
        net.WriteUInt(requestId, 16)
        net.WriteString(encoded)
    net.SendToServer()
end)

hook.Add("InitPostEntity", "ZM.Atmosphere.ApplyLoadedCell", function()
    timer.Simple(0, function()
        Atmosphere:ApplyPlayerProfile("InitPostEntity")
    end)
end)

hook.Add("Think", "ZM.Atmosphere.WaitForWorldData", function()
    if not ZM_World:IsLoaded() then return end
    if Atmosphere.PendingProfileIndex then
        Atmosphere:ApplyProfile(Atmosphere.PendingProfileIndex, "world data ready")
    elseif Atmosphere.PendingPlayerProfileSource and IsValid(LocalPlayer()) then
        Atmosphere:ApplyPlayerProfile(Atmosphere.PendingPlayerProfileSource .. " (world data ready)")
    end
end)

concommand.Add("zombiesim_atmosphere_status", function()
    local player = LocalPlayer()
    local profile = Atmosphere:GetActiveProfile()
    local settings = Atmosphere:GetFogSettings()
    local worldReady = ZM_World:IsLoaded()
    local expected = getExpectedCell(player)
    print(string.format("[ZombieSim] Atmosphere: map=%s world=%s active=%s activeId=%s expected=%s expectedId=%s cell=%s,%s pending=%s pendingPlayer=%s source=%s storm=%.2f fog=%s",
        game.GetMap(),
        tostring(worldReady), tostring(Atmosphere.ActiveProfileIndex),
        tostring(profile and (profile.id or profile.name) or "none"),
        tostring(expected and expected.profileIndex),
        tostring(getProfileId(expected and expected.profileIndex)),
        tostring(expected and expected.cellX), tostring(expected and expected.cellY),
        tostring(Atmosphere.PendingProfileIndex), tostring(Atmosphere.PendingPlayerProfileSource),
        tostring(Atmosphere.LastApplySource), Atmosphere.StormIntensity,
        settings and string.format("start %.1f end %.1f density %.2f color %s",
            settings.start, settings.finish, settings.maxDensity, table.concat(settings.color or {}, ","))
            or "inactive"))
    local cells = ZM_World:IsLoaded() and ZM_World:GetCellsForMap(game.GetMap()) or nil
    local insideDen = IsValid(player) and ZM_SafeZones:IsPlayerInside(player) or false
    print("[ZombieSim] Atmosphere weather: " .. tostring(Atmosphere.Weather)
        .. " sheltered=" .. tostring(isSheltered)
        .. " boundaryMist=" .. tostring(Atmosphere.BoundaryMistActive)
        .. " precipitationEligible=" .. tostring(type(cells) == "table" and #cells > 0 and not insideDen)
        .. " grain=" .. tostring(GetConVar("zombiesim_atmosphere_grain"):GetBool()))
    local received = Atmosphere.LastProfileReceive
    if received then
        print(string.format("[ZombieSim] Atmosphere receive: profile=%s id=%s world=%s expected=%s cell=%s,%s time=%.2f",
            tostring(received.profileIndex), tostring(getProfileId(received.profileIndex)),
            tostring(received.worldDataLoaded), tostring(received.expectedProfileIndex),
            tostring(received.cellX), tostring(received.cellY), received.time))
    else
        print("[ZombieSim] Atmosphere receive: no server profile received in this client session")
    end

    for _, application in ipairs(Atmosphere.ProfileApplications) do
        print(string.format("[ZombieSim] Atmosphere apply: time=%.2f source=%s profile=%s id=%s applied=%s world=%s expected=%s cell=%s,%s",
            application.time, application.source, tostring(application.profileIndex),
            tostring(application.profileId), tostring(application.applied),
            tostring(application.worldDataLoaded), tostring(application.expectedProfileIndex),
            tostring(application.cellX), tostring(application.cellY)))
    end

    for _, hookName in ipairs({ "SetupWorldFog", "SetupSkyboxFog", "RenderScreenspaceEffects" }) do
        local result = Atmosphere.HookResults[hookName]
        if result then
            local fog = result.fog
            local correction = result.colorCorrection
            local correctionSummary = correction and string.format("brightness %.2f contrast %.2f colour %.2f add %.2f,%.2f,%.2f multiply %.2f,%.2f,%.2f",
                correction["$pp_colour_brightness"], correction["$pp_colour_contrast"], correction["$pp_colour_colour"],
                correction["$pp_colour_addr"], correction["$pp_colour_addg"], correction["$pp_colour_addb"],
                correction["$pp_colour_mulr"], correction["$pp_colour_mulg"], correction["$pp_colour_mulb"])
                or "inactive"
            print(string.format("[ZombieSim] Atmosphere hook: %s applied=%s returned=%s reason=%s profile=%s id=%s world=%s scale=%s fog=%s correction=%s",
                hookName, tostring(result.applied), tostring(result.returned), tostring(result.reason),
                tostring(result.profileIndex), tostring(result.profileId), tostring(result.worldDataLoaded),
                tostring(result.scale), fog and string.format("start %.1f end %.1f density %.2f color %s",
                    fog.start, fog.finish, fog.maxDensity, table.concat(fog.color or {}, ","))
                    or "inactive", correctionSummary))
        else
            print("[ZombieSim] Atmosphere hook: " .. hookName .. " has not run in this client session")
        end
    end
end)