// Launcher presentation is drawn only while the menu is open.
ZM_LauncherSceneClient = ZM_LauncherSceneClient or {}
local Scene = ZM_LauncherSceneClient
local Menu = ZM_LauncherMenu
local quality = CreateClientConVar("zombiesim_globe_quality", "1", true, false,
    "Launcher Earth detail: 0 low, 1 high.")
local prototypeLayers = CreateClientConVar("zombiesim_dev_earth_layers", "3", false, false,
    "Development Earth layers: 0 base, 1 clouds, 2 distress, 3 both.")
local shotLock = CreateClientConVar("zombiesim_credits_shot", "", false, false,
    "Credits dancer name for camera tuning.")
local debugShots = CreateClientConVar("zombiesim_credits_debug", "0", false, false,
    "Show the credits camera trace and shot state.")
local tilt = math.rad(12)
local presentationResourceVersion = 6
local transitionEarthZoom = 7
local earthSpinDamping = 2.4
local horizonCityScale = 0.19
local horizonCityHeightScale = 0.23
local dioramaHalfWidth, dioramaHalfDepth = 620, 520
local dioramaRoadExtent = 300
local presentationNightSky = { id = "imported_space_9", horizon = { 24, 6, 6 } }
local presentationDaySky = { id = "imported_tropo_day_2", horizon = { 150, 178, 204 } }
local presentationLightingDirection = Vector(-0.4, -0.8, 0.45):GetNormalized()
local presentationAssets = {}
local sunMaterial = Material("sprites/light_glow02_add")
local dioramaTerrainMaterial = CreateMaterial("zombiesim_launcher_diorama_terrain_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/grassfloor002a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
local dioramaRoadMaterial = CreateMaterial("zombiesim_launcher_diorama_roads_v1", "UnlitGeneric", {
    ["$basetexture"] = "nature/rockfloor005a",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
local horizonSunColor = Color(255, 243, 214, 215)
local horizonHazeColor = Color(178, 204, 228, 74)
local atmosphereColor = Color(196, 219, 238, 255)
local terrainColor = Color(134, 139, 103)
local roadColor = Color(97, 98, 100)
local earthMarkerColor = Color(255, 176, 82)
local cityMarkerColor = Color(255, 154, 62)
local cityLabelColor = Color(248, 242, 232)
local cityLabelOutline = Color(16, 20, 26, 235)
local earthLightMaterial = CreateMaterial("zombiesim_launcher_earth_lights_v2", "UnlitGeneric", {
    ["$basetexture"] = "zombiesim/launcher/earth_lights",
    ["$vertexcolor"] = 1,
    ["$vertexalpha"] = 1,
    ["$translucent"] = 1,
    ["$nocull"] = 1,
    ["$nofog"] = 1
})
local earthMaterials = {
    day = Material("zombiesim/launcher/earth_day"),
    lights = earthLightMaterial,
    clouds = Material("zombiesim/launcher/earth_clouds"),
    distress = Material("zombiesim/launcher/earth_distress"),
    rim = Material("zombiesim/launcher/earth_rim")
}
local earthHighDetailStart, earthHighDetailFull = 1.5, 2.1
local earthHighDetailMaterials

// The 4096x2048 close-zoom layers are created on the first high-quality draw,
// so low globe quality never loads their extra texture memory.
local function getEarthHighDetailMaterials()
    if earthHighDetailMaterials then return earthHighDetailMaterials end
    local function layer(name)
        return CreateMaterial("zombiesim_launcher_" .. name .. "_v1", "UnlitGeneric", {
            ["$basetexture"] = "zombiesim/launcher/" .. name,
            ["$vertexcolor"] = 1,
            ["$vertexalpha"] = 1,
            ["$translucent"] = 1,
            ["$nocull"] = 1,
            ["$nofog"] = 1
        })
    end
    earthHighDetailMaterials = { day = layer("earth_day_hd"), lights = layer("earth_lights_hd") }
    return earthHighDetailMaterials
end

function Scene:GetEarthHighDetailBlend(zoom)
    if not quality:GetBool() then return 0 end
    local amount = math.Clamp(((tonumber(zoom) or 1) - earthHighDetailStart)
        / (earthHighDetailFull - earthHighDetailStart), 0, 1)
    return amount * amount * (3 - 2 * amount)
end

function Scene:GetDancer(index)
    local id = Menu.DancerIds and Menu.DancerIds[index]
    return id and id > 0 and Entity(id) or nil
end

local function surfacePoint(latitude, longitude)
    local lat, lon = math.rad(latitude), math.rad(longitude)
    return Vector(math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))
end

function Scene:IsPresentationHidden()
    return not Menu.Active or Menu.Credits or not Menu.Globe
        or (ZM_SkyInspection and ZM_SkyInspection:IsActive())
        or (Menu.IsCharacterPreviewVisible and Menu:IsCharacterPreviewVisible())
end

function Scene:Uses3DSkybox()
    local skybox = Menu.PresentationSkybox
    return skybox and isvector(skybox.origin) and tonumber(skybox.scale)
        and tonumber(skybox.scale) > 0 or false
end

function Scene:ToPresentationSpace(position)
    if not self:Uses3DSkybox() then return position, 1 end
    local skybox = Menu.PresentationSkybox
    return skybox.origin + position / skybox.scale, 1 / skybox.scale
end

function Scene:GetPresentationCameraOrigin()
    if not Menu.Camera then return vector_origin end
    if not self:Uses3DSkybox() then return Menu.Camera.origin end
    local skybox = Menu.PresentationSkybox
    return skybox.origin + Menu.Camera.origin / skybox.scale
end

function Scene:GetEarthTarget()
    local anchor = ZM_LauncherScene:GetAnchor(Menu.Profile)
    local selected = Menu.SelectedSlot and Menu.Slots and Menu.Slots[Menu.SelectedSlot]
    return tonumber(selected and selected.originLatitude) or (anchor and tonumber(anchor.latitude)),
        tonumber(selected and selected.originLongitude) or (anchor and tonumber(anchor.longitude))
end

function Scene:GetEarthZoomBounds()
    local cameraDistance = Menu.Camera and Menu.Globe
        and (Menu.Camera.origin - Menu.Globe):Length() or 0
    local maximum = cameraDistance > 0 and (cameraDistance - 24) / 42 or 1.45
    return 0.72, math.Clamp(maximum, 1, 3), cameraDistance
end

function Scene:BeginEarthView()
    self.EarthViewReturn = nil
    self.ManualEarthView = true
    self.EarthViewZoom = self.EarthViewZoom or 1
end

function Scene:BeginEarthDrag()
    self:BeginEarthView()
    self.EarthDragging = true
    self.EarthSpinYawVelocity, self.EarthSpinPitchVelocity = 0, 0
end

function Scene:EndEarthDrag()
    self.EarthDragging = false
end

function Scene:AdjustEarthView(deltaX, deltaY, wheel, frameTime)
    self:BeginEarthView()
    deltaX, deltaY = tonumber(deltaX) or 0, tonumber(deltaY) or 0
    wheel = tonumber(wheel) or 0
    if wheel ~= 0 then
        self.EarthSpinYawVelocity, self.EarthSpinPitchVelocity = 0, 0
    end
    self.Yaw = (tonumber(self.Yaw) or 0) + deltaX * 0.28
    self.Pitch = math.Clamp((tonumber(self.Pitch) or math.deg(tilt)) + deltaY * 0.22, -72, 72)
    if frameTime and frameTime > 0 then
        local blend = 1 - math.exp(-math.min(frameTime, 0.1) * 18)
        local targetYawVelocity = math.Clamp(deltaX * 0.28 / frameTime, -360, 360)
        local targetPitchVelocity = math.Clamp(deltaY * 0.22 / frameTime, -240, 240)
        self.EarthSpinYawVelocity = Lerp(blend, self.EarthSpinYawVelocity or 0, targetYawVelocity)
        self.EarthSpinPitchVelocity = Lerp(blend, self.EarthSpinPitchVelocity or 0, targetPitchVelocity)
    end
    local minimum, maximum = self:GetEarthZoomBounds()
    self.EarthViewZoom = math.Clamp((self.EarthViewZoom or 1)
        * math.pow(1.1, wheel), minimum, maximum)
    return self.Yaw, self.Pitch, self.EarthViewZoom
end

function Scene:AdvanceEarthMomentum(frameTime)
    if not self.ManualEarthView or self.EarthDragging then return self.Yaw, self.Pitch end
    local elapsed = math.max(0, math.min(tonumber(frameTime) or 0, 0.1))
    if elapsed == 0 then return self.Yaw, self.Pitch end
    local decay = math.exp(-earthSpinDamping * elapsed)
    local travel = (1 - decay) / earthSpinDamping
    local yawVelocity = self.EarthSpinYawVelocity or 0
    local pitchVelocity = self.EarthSpinPitchVelocity or 0
    self.Yaw = (tonumber(self.Yaw) or 0) + yawVelocity * travel
    local nextPitch = (tonumber(self.Pitch) or math.deg(tilt)) + pitchVelocity * travel
    self.Pitch = math.Clamp(nextPitch, -72, 72)
    self.EarthSpinYawVelocity = math.abs(yawVelocity * decay) < 0.2 and 0 or yawVelocity * decay
    if nextPitch ~= self.Pitch or math.abs(pitchVelocity * decay) < 0.2 then
        self.EarthSpinPitchVelocity = 0
    else
        self.EarthSpinPitchVelocity = pitchVelocity * decay
    end
    return self.Yaw, self.Pitch
end

function Scene:ClearEarthMomentum()
    self.EarthDragging = false
    self.EarthSpinYawVelocity, self.EarthSpinPitchVelocity = 0, 0
end

function Scene:ReleaseEarthView()
    self.ManualEarthView = false
    self.EarthViewReturn = nil
    self:ClearEarthMomentum()
end

function Scene:ResetEarthView()
    local latitude, longitude = self:GetEarthTarget()
    local targetYaw = longitude and (-90 - longitude) or 0
    local targetPitch = latitude or math.deg(tilt)
    self:ClearEarthMomentum()
    self.EarthViewReturn = {
        startedAt = RealTime(),
        duration = 0.8,
        yaw = self.Yaw or targetYaw,
        pitch = self.Pitch or targetPitch,
        zoom = self.EarthViewZoom or 1,
        targetYaw = targetYaw,
        targetPitch = targetPitch
    }
    self.ManualEarthView = false
    return targetYaw, targetPitch, 1
end

function Scene:AdvanceEarthViewReturn(now)
    local transition = self.EarthViewReturn
    if not transition then return false end
    local progress = math.Clamp(((now or RealTime()) - transition.startedAt) / transition.duration, 0, 1)
    local eased = progress * progress * (3 - 2 * progress)
    self.Yaw = transition.yaw + math.AngleDifference(transition.targetYaw, transition.yaw) * eased
    self.Pitch = Lerp(eased, transition.pitch, transition.targetPitch)
    self.EarthViewZoom = Lerp(eased, transition.zoom, 1)
    if progress >= 1 then self.EarthViewReturn = nil end
    return true
end

function Scene:ShouldDrawPresentationPass(depth, skybox)
    if depth then return false end
    return self:Uses3DSkybox() == (skybox == true)
end

local function vertex(normal, u, v, colour)
    return { pos = normal, normal = normal, u = u, v = v, color = colour }
end

local function addTriangle(vertices, a, b, c, colourA, colourB, colourC)
    vertices[#vertices + 1] = vertex(a.normal, a.u, a.v, colourA)
    vertices[#vertices + 1] = vertex(b.normal, b.u, b.v, colourB)
    vertices[#vertices + 1] = vertex(c.normal, c.u, c.v, colourC)
end

local function lightingColours(normal)
    local daylight, nightBlend = Scene:GetEarthNightBlend(normal)
    local amount = 0.055 + math.pow(daylight, 1.45) * 0.945
    return Color(amount * 255, amount * 255, amount * 255, 255),
        Color(255, 191, 119, nightBlend * 255)
end

function Scene:GetEarthNightBlend(normal)
    local daylight = math.Clamp(normal:Dot(presentationLightingDirection) * 0.5 + 0.5, 0, 1)
    local edge = math.Clamp((daylight - 0.28) / 0.5, 0, 1)
    local night = 1 - edge * edge * (3 - 2 * edge)
    return daylight, night
end

local function buildSphere(detail)
    local longitudeSteps = detail * 2
    local rows = {}
    for row = 1, detail - 1 do
        rows[row] = {}
        for col = 0, longitudeSteps do
            local u, v = col / longitudeSteps, row / detail
            rows[row][col] = { normal = surfacePoint(-90 + v * 180, -180 + u * 360), u = u, v = 1 - v }
        end

    end
    local dayVertices, nightVertices = {}, {}
    local south, north = surfacePoint(-90, 0), surfacePoint(90, 0)
    for col = 0, longitudeSteps - 1 do
        local first, second = rows[1][col], rows[1][col + 1]
        local pole = { normal = south, u = (col + 0.5) / longitudeSteps, v = 1 }
        local dayA, nightA = lightingColours(pole.normal)
        local dayB, nightB = lightingColours(second.normal)
        local dayC, nightC = lightingColours(first.normal)
        addTriangle(dayVertices, pole, second, first, dayA, dayB, dayC)
        addTriangle(nightVertices, pole, second, first, nightA, nightB, nightC)
        for row = 1, detail - 2 do
            local a, b = rows[row][col], rows[row + 1][col]
            local c, d = rows[row + 1][col + 1], rows[row][col + 1]
            local day1, night1 = lightingColours(a.normal)
            local day2, night2 = lightingColours(b.normal)
            local day3, night3 = lightingColours(c.normal)
            local day4, night4 = lightingColours(d.normal)
            addTriangle(dayVertices, a, b, c, day1, day2, day3)
            addTriangle(dayVertices, a, c, d, day1, day3, day4)
            addTriangle(nightVertices, a, b, c, night1, night2, night3)
            addTriangle(nightVertices, a, c, d, night1, night3, night4)
        end
        first, second = rows[detail - 1][col], rows[detail - 1][col + 1]
        pole = { normal = north, u = (col + 0.5) / longitudeSteps, v = 0 }
        dayA, nightA = lightingColours(first.normal)
        dayB, nightB = lightingColours(second.normal)
        dayC, nightC = lightingColours(pole.normal)
        addTriangle(dayVertices, first, second, pole, dayA, dayB, dayC)
        addTriangle(nightVertices, first, second, pole, nightA, nightB, nightC)
    end
    local day, night = Mesh(), Mesh()
    day:BuildFromTriangles(dayVertices)
    night:BuildFromTriangles(nightVertices)
    return {
        day = day, night = night, triangles = #dayVertices / 3, vertices = #dayVertices,
        seamVertices = detail * 2, poleTriangles = detail * 4
    }
end

// A flat city basin, rolling ground beyond it, and a far ridge that keeps the plate boundary out of frame.
local function terrainHeight(x, y)
    local distance = math.sqrt(x * x + y * y)
    local relief = math.Clamp((distance - 150) / 190, 0, 1)
    relief = relief * relief * (3 - 2 * relief)
    local rolling = math.sin(x * 0.0134) * 12.5 + math.cos(y * 0.0171) * 9.5
        + math.sin((x + y) * 0.0086) * 7
    local ridge = math.Clamp((distance - 330) / 250, 0, 1)
    ridge = ridge * ridge * (3 - 2 * ridge)
    return rolling * relief + ridge * 30 - 3
end

local function dioramaVertex(x, y, z, colour, uvScale)
    uvScale = uvScale or 48
    return {
        pos = Vector(x, y, z),
        normal = Vector(0, 0, 1),
        u = x / uvScale,
        v = y / uvScale,
        color = colour
    }
end

local function addDioramaQuad(vertices, a, b, c, d)
    vertices[#vertices + 1] = a
    vertices[#vertices + 1] = b
    vertices[#vertices + 1] = c
    vertices[#vertices + 1] = a
    vertices[#vertices + 1] = c
    vertices[#vertices + 1] = d
end

local function buildDioramaMeshes()
    local terrainVertices = {}
    local xSteps, ySteps = 28, 24
    local halfWidth, halfDepth = dioramaHalfWidth, dioramaHalfDepth
    for yIndex = 0, ySteps - 1 do
        local y0 = Lerp(yIndex / ySteps, -halfDepth, halfDepth)
        local y1 = Lerp((yIndex + 1) / ySteps, -halfDepth, halfDepth)
        for xIndex = 0, xSteps - 1 do
            local x0 = Lerp(xIndex / xSteps, -halfWidth, halfWidth)
            local x1 = Lerp((xIndex + 1) / xSteps, -halfWidth, halfWidth)
            addDioramaQuad(terrainVertices,
                dioramaVertex(x0, y0, terrainHeight(x0, y0), terrainColor),
                dioramaVertex(x1, y0, terrainHeight(x1, y0), terrainColor),
                dioramaVertex(x1, y1, terrainHeight(x1, y1), terrainColor),
                dioramaVertex(x0, y1, terrainHeight(x0, y1), terrainColor))
        end
    end
    local roadVertices = {}
    local function addRoad(horizontal)
        local steps = 24
        local extent = dioramaRoadExtent
        local halfRoad = 8
        for index = 0, steps - 1 do
            local start = Lerp(index / steps, -extent, extent)
            local finish = Lerp((index + 1) / steps, -extent, extent)
            local x0, y0 = horizontal and start or -halfRoad, horizontal and -halfRoad or start
            local x1, y1 = horizontal and finish or halfRoad, horizontal and halfRoad or finish
            local aX, aY = x0, y0
            local bX, bY = horizontal and x1 or -halfRoad, horizontal and y0 or y1
            local cX, cY = x1, y1
            local dX, dY = horizontal and x0 or halfRoad, horizontal and y1 or y0
            addDioramaQuad(roadVertices,
                dioramaVertex(aX, aY, terrainHeight(aX, aY) + 0.35, roadColor, 30),
                dioramaVertex(bX, bY, terrainHeight(bX, bY) + 0.35, roadColor, 30),
                dioramaVertex(cX, cY, terrainHeight(cX, cY) + 0.35, roadColor, 30),
                dioramaVertex(dX, dY, terrainHeight(dX, dY) + 0.35, roadColor, 30))
        end
    end
    addRoad(true)
    addRoad(false)
    local terrain, roads = Mesh(), Mesh()
    terrain:BuildFromTriangles(terrainVertices)
    roads:BuildFromTriangles(roadVertices)
    return {
        terrain = terrain,
        roads = roads,
        terrainTriangles = #terrainVertices / 3,
        roadTriangles = #roadVertices / 3,
        halfWidth = halfWidth,
        halfDepth = halfDepth,
        meshes = 2
    }
end

function Scene:ReleaseCity()
    for _, record in ipairs(self.CityModels or {}) do
        if IsValid(record.entity) then record.entity:Remove() end
    end
    self.CityModels = {}
    self.CityKey, self.CityData = nil, nil
end

function Scene:ReleasePresentationResources()
    for _, sphere in pairs(self.Spheres or {}) do
        if sphere.day then sphere.day:Destroy() end
        if sphere.night then sphere.night:Destroy() end
    end
    self.Spheres = {}
    if self.DioramaMeshes then
        if self.DioramaMeshes.terrain then self.DioramaMeshes.terrain:Destroy() end
        if self.DioramaMeshes.roads then self.DioramaMeshes.roads:Destroy() end
    end
    self.DioramaMeshes = nil
    self:ReleaseCity()
end

if Scene.PresentationResourceVersion ~= presentationResourceVersion then
    Scene:ReleasePresentationResources()
    Scene.PresentationResourceVersion = presentationResourceVersion
end

function Scene:GetSphereForDetail(detail)
    self.Spheres = self.Spheres or {}
    if not self.Spheres[detail] then self.Spheres[detail] = buildSphere(detail) end
    return self.Spheres[detail]
end

function Scene:GetSphere()
    local detail = quality:GetBool() and 32 or 16
    return self:GetSphereForDetail(detail), detail
end

function Scene:GetDioramaMeshes()
    if not self.DioramaMeshes then self.DioramaMeshes = buildDioramaMeshes() end
    return self.DioramaMeshes
end

function Scene:SetPresentationState(state)
    if state ~= "earth" and state ~= "city" then return false end
    self.PresentationTransition = nil
    self.PresentationState = state
    self.PresentationDescent = state == "city" and 1 or 0
    if state ~= "city" then self:ReleaseCity() end
    return true
end

local function smoothStep(value)
    value = math.Clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end

local function smootherStep(value)
    value = math.Clamp(value, 0, 1)
    return value * value * value * (value * (value * 6 - 15) + 10)
end

function Scene:GetDescentVisuals(descent)
    descent = math.Clamp(tonumber(descent) or 0, 0, 1)
    local approach = smootherStep(math.Clamp((descent - 0.06) / 0.56, 0, 1))
    local atmosphereIn = smootherStep(math.Clamp((descent - 0.3) / 0.26, 0, 1))
    local atmosphereOut = 1 - smootherStep(math.Clamp((descent - 0.64) / 0.3, 0, 1))
    local stage = descent < 0.16 and "orbit" or descent < 0.44 and "approach"
        or descent < 0.78 and "atmosphere" or "destination"
    return {
        descent = descent,
        earth = 1 - smootherStep(math.Clamp((descent - 0.4) / 0.24, 0, 1)),
        city = smootherStep(math.Clamp((descent - 0.5) / 0.3, 0, 1)),
        zoom = Lerp(approach, 1, transitionEarthZoom),
        earthDrop = smootherStep(math.Clamp((descent - 0.12) / 0.5, 0, 1)) * 84,
        marker = 1 - smootherStep(math.Clamp((descent - 0.3) / 0.22, 0, 1)),
        // The veil holds at full cover across the handoff, so the Earth, city and sky swap are never seen crossing.
        atmosphere = math.min(atmosphereIn, atmosphereOut),
        skyDay = descent >= 0.58,
        stage = stage
    }
end

// The launcher sky belongs to the descent: orbital night above the Earth, daylight once the city is the destination.
function Scene:GetPresentationSky()
    local descent = self.PresentationDescent
    if not descent then descent = self:GetPresentationState() == "city" and 1 or 0 end
    local day = self:GetDescentVisuals(descent).skyDay
    local sky = day and presentationDaySky or presentationNightSky
    return sky.id, { sky.horizon[1], sky.horizon[2], sky.horizon[3] }, day
end

function Scene:GetPresentationWeights(now)
    local transition = self.PresentationTransition
    local state = self.PresentationState or "earth"
    if not transition then
        local visuals = self:GetDescentVisuals(state == "city" and 1 or 0)
        self.PresentationDescent = visuals.descent
        return visuals.earth, visuals.city, 1, visuals.zoom, visuals.atmosphere, visuals.descent
    end
    local progress = math.Clamp(((now or RealTime()) - transition.startedAt) / transition.duration, 0, 1)
    local blend = smootherStep(progress)
    local descent = Lerp(blend, transition.fromDescent, transition.targetDescent)
    local visuals = self:GetDescentVisuals(descent)
    self.PresentationDescent = descent
    if progress >= 1 then
        self.PresentationTransition = nil
        if state ~= "city" then self:ReleaseCity() end
    end
    return visuals.earth, visuals.city, progress, visuals.zoom, visuals.atmosphere, descent
end

function Scene:TransitionPresentationState(state, duration)
    if state ~= "earth" and state ~= "city" then return false end
    local now = RealTime()
    local earth, city, _, earthZoom, _, descent = self:GetPresentationWeights(now)
    local targetDescent = state == "city" and 1 or 0
    self.PresentationState = state
    duration = math.max(tonumber(duration) or 0, 0)
    if duration == 0 or math.abs(descent - targetDescent) < 0.001 then
        return self:SetPresentationState(state)
    end
    self.PresentationTransition = {
        startedAt = now,
        duration = duration,
        fromDescent = descent,
        targetDescent = targetDescent,
        fromEarth = earth,
        fromCity = city,
        fromEarthZoom = earthZoom
    }
    return true
end

function Scene:GetPresentationTransitionState()
    if not self.PresentationTransition then return nil end
    return self.PresentationState == "city" and "entering_play" or "returning_home"
end

function Scene:GetPresentationState()
    if self:IsPresentationHidden() then return "hidden" end
    return self.PresentationState or "earth"
end

function Scene:GetPresentationData(profile)
    local cached = presentationAssets[profile]
    if cached then return cached.world, cached.skyline end
    local worldRaw = file.Read("data_static/zombiesim_world_" .. tostring(profile) .. ".json", "GAME")
    local skylineRaw = file.Read("data_static/zombiesim_skybox_" .. tostring(profile) .. ".json", "GAME")
    cached = {
        world = worldRaw and util.JSONToTable(worldRaw),
        skyline = skylineRaw and util.JSONToTable(skylineRaw)
    }
    presentationAssets[profile] = cached
    self.PresentationAssetLoads = (self.PresentationAssetLoads or 0) + 1
    return cached.world, cached.skyline
end

function Scene:ResolveSelectedCity()
    local selected = Menu.SelectedSlot and Menu.Slots and Menu.Slots[Menu.SelectedSlot]
    if not selected then return nil, "select an occupied survivor slot" end
    local world, skyline = self:GetPresentationData(Menu.Profile)
    return ZM_LauncherPresentation.ResolveCity(world, skyline, Menu.Profile, selected.location)
end

function Scene:GetCitySelectionKey()
    local selected = Menu.SelectedSlot and Menu.Slots and Menu.Slots[Menu.SelectedSlot]
    if not selected then return tostring(Menu.Profile) .. "|none" end
    local location = selected.location or {}
    return table.concat({
        tostring(Menu.Profile), tostring(Menu.SelectedSlot), tostring(selected.presentationRevision),
        tostring(location.state), tostring(location.cellX), tostring(location.cellY),
        tostring(location.safeZoneId), tostring(location.map)
    }, "|")
end

function Scene:PrepareCity()
    local selectionKey = self:GetCitySelectionKey()
    if self.CitySelectionKey == selectionKey then
        local valid = #(self.CityModels or {}) > 0
        for _, record in ipairs(self.CityModels or {}) do
            if not IsValid(record.entity) then valid = false break end
        end
        if valid then return self.CityModels end
        if self.CitySelectionFailure then return nil end
    end
    self.CitySelectionKey = selectionKey
    self.CitySelectionFailure = nil
    local data, failure = self:ResolveSelectedCity()
    self.CityError = failure
    if not data then
        self.CitySelectionFailure = failure or true
        self:ReleaseCity()
        return nil
    end
    local paths = {}
    for _, record in ipairs(data.models or {}) do paths[#paths + 1] = record.model end
    local key = data.profile .. "|" .. data.map .. "|" .. util.CRC(table.concat(paths, "\31"))
    if self.CityKey == key and #(self.CityModels or {}) > 0 then
        self.CityData = data
        return self.CityModels
    end
    self:ReleaseCity()
    local models = {}
    for _, source in ipairs(data.models or {}) do
        local entity = ClientsideModel(source.model, RENDERGROUP_OPAQUE)
        if not IsValid(entity) then
            for _, record in ipairs(models) do
                if IsValid(record.entity) then record.entity:Remove() end
            end
            self.CityError = "city-cluster skyline model could not be created: " .. tostring(source.model)
            self.CitySelectionFailure = self.CityError
            return nil
        end
        entity:SetNoDraw(true)
        entity:SetLOD(0)
        models[#models + 1] = {
            entity = entity,
            offsetX = source.offsetX,
            offsetY = source.offsetY,
            selected = source.selected,
            model = source.model
        }
    end
    self.CityModels, self.CityKey, self.CityData = models, key, data
    return models
end

function Scene:GetEarthMarkerPosition(centre, zoom, presentationScale, latitude, longitude)
    if not latitude or not longitude then return nil end
    local normal = (self:GetEarthRotation() * surfacePoint(latitude, longitude)):GetNormalized()
    return centre + normal * 43.2 * zoom * presentationScale, normal
end

// Gimbal: the planet spins about its own pole (inner yaw), then tilts about the
// screen-horizontal axis facing the menu camera along +Y (outer pitch). Tilting
// about world X keeps north up for any longitude instead of rolling the globe.
function Scene:GetEarthRotation()
    local yaw, pitch = math.rad(self.Yaw or 0), math.rad(self.Pitch or 0)
    local cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    return Matrix({
        { cy, -sy, 0, 0 },
        { cp * sy, cp * cy, -sp, 0 },
        { sp * sy, sp * cy, cp, 0 },
        { 0, 0, 0, 1 }
    })
end

local spaceFogMaterial = Material("zombiesim/launcher/space_fog")
local missileTrailMaterial = Material("trails/smoke")
local shockwaveMaterial = Material("effects/select_ring")
// Gloomy nebula drift: far puffs sit behind the globe, a few faint near puffs frame its edges.
local spaceFogPuffs = {
    { right = -150, up = 60, depth = 120, size = 260, alpha = 95, speed = 0.011, phase = 0.4 },
    { right = 170, up = -40, depth = 150, size = 300, alpha = 90, speed = -0.008, phase = 1.9 },
    { right = 30, up = 130, depth = 180, size = 280, alpha = 70, speed = 0.006, phase = 3.1 },
    { right = -60, up = -120, depth = 140, size = 240, alpha = 80, speed = -0.012, phase = 4.4 },
    { right = 230, up = 110, depth = 90, size = 200, alpha = 60, speed = 0.014, phase = 5.2 },
    { right = -240, up = -70, depth = 80, size = 210, alpha = 65, speed = -0.01, phase = 2.6 },
    { right = -120, up = -78, depth = -70, size = 120, alpha = 28, speed = 0.018, phase = 0.9, front = true },
    { right = 128, up = 74, depth = -60, size = 110, alpha = 24, speed = -0.016, phase = 3.7, front = true },
    { right = 112, up = -92, depth = -80, size = 130, alpha = 22, speed = 0.013, phase = 5.9, front = true }
}
local spaceFogColor = { 92, 30, 22 }
local spaceFogFrontColor = { 70, 38, 32 }
local strikeBlocs = {
    west = {
        launch = { { 47.5, -111.2 }, { 48.4, -101.4 }, { 41.1, -104.8 }, { 55, -32 }, { 42, -160 } },
        targets = { { 40.7, -74.0 }, { 34.05, -118.24 }, { 41.9, -87.6 }, { 38.9, -77.0 }, { 51.5, -0.13 },
            { 48.86, 2.35 }, { 52.5, 13.4 }, { 47.6, -122.3 }, { 43.7, -79.4 }, { 29.8, -95.4 }, { 37.8, -122.4 } }
    },
    east = {
        launch = { { 55.3, 89.8 }, { 51.2, 58.6 }, { 54.0, 35.8 }, { 39.7, 98.5 }, { 72, 40 }, { 40.0, 125.8 } },
        targets = { { 55.75, 37.6 }, { 59.9, 30.3 }, { 39.9, 116.4 }, { 31.2, 121.5 }, { 39.0, 125.75 },
            { 56.8, 60.6 }, { 55.0, 82.9 }, { 30.6, 104.1 }, { 43.1, 131.9 }, { 22.5, 114.1 } }
    }
}
local maximumStrikes, maximumMissilesInFlight = 9, 3
local strikeAftermath = 22

local function slerpUnit(a, b, amount, omega)
    if omega < 0.0001 then return a end
    local sinOmega = math.sin(omega)
    return a * (math.sin((1 - amount) * omega) / sinOmega) + b * (math.sin(amount * omega) / sinOmega)
end

local function strikePoint(strike, amount)
    local direction = slerpUnit(strike.from, strike.to, amount, strike.omega)
    return direction * (1 + strike.apex * math.sin(math.pi * amount)), direction
end

local function sightBlocked(point, camera, centre, radius)
    local ray, offset = camera - point, point - centre
    local a, b = ray:Dot(ray), offset:Dot(ray)
    local c = offset:Dot(offset) - radius * radius
    local discriminant = b * b - a * c
    if c <= 0 or discriminant < 0 then return c <= 0 end
    local hit = (-b - math.sqrt(discriminant)) / a
    return hit > 0 and hit < 1
end

function Scene:SpawnNuclearStrike(now)
    local blocs = { "west", "east" }
    local attacker = blocs[math.random(2)]
    local defender = attacker == "west" and "east" or "west"
    local launch = strikeBlocs[attacker].launch[math.random(#strikeBlocs[attacker].launch)]
    local markerLat, markerLon = self:GetEarthTarget()
    local candidates = {}
    for _, target in ipairs(strikeBlocs[defender].targets) do
        if not markerLat or math.abs(target[1] - markerLat) + math.abs(math.AngleDifference(target[2], markerLon)) > 9 then
            candidates[#candidates + 1] = target
        end
    end
    if #candidates == 0 then return nil end
    local target = candidates[math.random(#candidates)]
    local from, to = surfacePoint(launch[1], launch[2]), surfacePoint(target[1], target[2])
    local omega = math.acos(math.Clamp(from:Dot(to), -1, 1))
    local strike = {
        from = from, to = to, omega = omega,
        apex = 0.06 + 0.16 * omega / math.pi,
        launchedAt = now,
        flight = 4.5 + 4 * omega / math.pi
    }
    self.NuclearStrikes[#self.NuclearStrikes + 1] = strike
    return strike
end

function Scene:UpdateNuclearStrikes(now)
    self.NuclearStrikes = self.NuclearStrikes or {}
    local strikes, inFlight = self.NuclearStrikes, 0
    for index = #strikes, 1, -1 do
        local strike = strikes[index]
        if now - strike.launchedAt > strike.flight + strikeAftermath then
            table.remove(strikes, index)
        elseif now - strike.launchedAt < strike.flight then
            inFlight = inFlight + 1
        end
    end
    self.NextStrikeAt = self.NextStrikeAt or now + 1.2
    if now >= self.NextStrikeAt then
        if #strikes < maximumStrikes and inFlight < maximumMissilesInFlight then self:SpawnNuclearStrike(now) end
        self.NextStrikeAt = now + math.Rand(2.4, 5.8)
    end
    return strikes
end

function Scene:DrawSpaceFog(centre, presentationScale, alpha, front, fade)
    if not Menu.Camera or spaceFogMaterial:IsError() then return 0 end
    local camera = self:GetPresentationCameraOrigin()
    local forward = (centre - camera):GetNormalized()
    local right = forward:Cross(Vector(0, 0, 1)):GetNormalized()
    local up = right:Cross(forward):GetNormalized()
    local now, draws = RealTime(), 0
    local tint = front and spaceFogFrontColor or spaceFogColor
    render.OverrideDepthEnable(true, false)
    render.SetMaterial(spaceFogMaterial)
    for _, puff in ipairs(spaceFogPuffs) do
        if (puff.front == true) == front then
            local drift = math.sin(now * 0.07 + puff.phase)
            local position = centre + (right * (puff.right + drift * 18) + up * (puff.up + math.cos(now * 0.05 + puff.phase) * 10)
                + forward * puff.depth) * presentationScale
            local size = puff.size * (1 + drift * 0.06) * presentationScale
            render.DrawQuadEasy(position, -forward, size, size,
                Color(tint[1], tint[2], tint[3], puff.alpha * alpha * (fade or 1)),
                (puff.phase * 57 + now * puff.speed * 57.3) % 360)
            draws = draws + 1
        end
    end
    render.OverrideDepthEnable(false, false)
    return draws
end

function Scene:DrawNuclearStrikes(centre, rotation, radius, alpha, now)
    local strikes = self:UpdateNuclearStrikes(now)
    if #strikes == 0 or alpha <= 0.001 then return 0 end
    local camera = self:GetPresentationCameraOrigin()
    local toCamera = (camera - centre):GetNormalized()
    local draws = 0
    local function world(local_)
        return centre + (rotation * local_) * radius
    end
    render.OverrideDepthEnable(true, false)
    for _, strike in ipairs(strikes) do
        local age = now - strike.launchedAt
        local progress = math.Clamp(age / strike.flight, 0, 1)
        local travel = progress * progress * (3 - 2 * progress) * 0.35 + progress * 0.65
        local trailFade = alpha * (1 - smoothStep((age - strike.flight) / 7))
        if trailFade > 0.01 then
            render.SetMaterial(missileTrailMaterial)
            local samples = math.max(2, math.ceil(28 * travel))
            local previous = world(strikePoint(strike, 0))
            local previousHidden = sightBlocked(previous, camera, centre, radius * 0.995)
            for step = 1, samples do
                local amount = travel * step / samples
                local point = world(strikePoint(strike, amount))
                local hidden = sightBlocked(point, camera, centre, radius * 0.995)
                if not hidden and not previousHidden then
                    local recency = step / samples
                    render.DrawBeam(previous, point, radius * (0.008 + 0.01 * recency), 0, 1,
                        Color(214, 196, 178, 255 * trailFade * (0.3 + 0.7 * recency)))
                    draws = draws + 1
                end
                previous, previousHidden = point, hidden
            end
        end
        if progress < 1 then
            local head = world(strikePoint(strike, travel))
            if not sightBlocked(head, camera, centre, radius * 0.995) then
                render.SetMaterial(sunMaterial)
                local flicker = 1 + math.sin(now * 37 + strike.launchedAt) * 0.15
                render.DrawSprite(head, radius * 0.09 * flicker, radius * 0.09 * flicker, Color(255, 196, 128, 255 * alpha))
                render.DrawSprite(head, radius * 0.035, radius * 0.035, Color(255, 250, 235, 255 * alpha))
                draws = draws + 2
            end
        else
            local since = age - strike.flight
            local normal = (rotation * strike.to):GetNormalized()
            local facing = smoothStep((normal:Dot(toCamera) + 0.12) / 0.3)
            if facing > 0.01 then
                local ground = centre + normal * radius * 1.004
                local fade = alpha * facing
                render.SetMaterial(sunMaterial)
                if since < 1.2 then
                    local flash = 1 - since / 1.2
                    local size = radius * (0.1 + 0.55 * smoothStep(since / 0.25))
                    render.DrawSprite(ground, size, size, Color(255, 252, 240, 255 * fade * flash))
                    draws = draws + 1
                end
                local fire = 1 - smoothStep((since - 1.5) / 9)
                if fire > 0.01 then
                    local size = radius * (0.08 + 0.1 * smoothStep(since / 2.5))
                    render.DrawSprite(ground + normal * radius * 0.01, size, size, Color(255, 120, 40, 255 * fade * fire))
                    draws = draws + 1
                end
                local embers = 1 - smoothStep((since - 6) / (strikeAftermath - 6))
                render.DrawSprite(ground, radius * 0.07, radius * 0.07, Color(255, 84, 24, 190 * fade * embers))
                draws = draws + 1
                if since < 3 then
                    local ring = smoothStep(since / 3)
                    render.SetMaterial(shockwaveMaterial)
                    render.DrawQuadEasy(ground + normal * radius * 0.003, normal, radius * 0.42 * ring,
                        radius * 0.42 * ring, Color(255, 214, 170, 230 * fade * (1 - ring)), 0)
                    draws = draws + 1
                end
                local cloud = smoothStep(since / 4)
                local cloudFade = (1 - smoothStep((since - 7) / 12)) * smoothStep(since / 0.6)
                if cloudFade > 0.01 then
                    render.SetMaterial(spaceFogMaterial)
                    local heat = 1 - smoothStep((since - 1) / 6)
                    local stem = ground + normal * radius * (0.012 + 0.03 * cloud)
                    local cap = ground + normal * radius * (0.02 + 0.075 * cloud)
                    render.DrawSprite(stem, radius * 0.035, radius * (0.03 + 0.05 * cloud),
                        Color(150 + 105 * heat, 110 + 40 * heat, 80, 200 * fade * cloudFade))
                    render.DrawSprite(cap, radius * (0.05 + 0.08 * cloud), radius * (0.04 + 0.06 * cloud),
                        Color(140 + 115 * heat, 96 + 50 * heat, 70 + 10 * heat, 230 * fade * cloudFade))
                    draws = draws + 2
                end
            end
        end
    end
    render.OverrideDepthEnable(false, false)
    return draws
end

function Scene:DrawEarth(alpha, transitionZoom, descent)
    if not Menu.Camera then return end
    alpha = math.Clamp(tonumber(alpha) or 1, 0, 1)
    local visuals = self:GetDescentVisuals(descent)
    local sphere, detail = self:GetSphere()
    local now = RealTime()
    local lat, lon = self:GetEarthTarget()
    local targetYaw = lon and (-90 - lon) or nil
    local elapsed = math.min(FrameTime(), 0.1)
    self.Yaw = self.Yaw or 0
    self.Pitch = self.Pitch or math.deg(tilt)
    local manual = self.ManualEarthView and Menu.IsEarthControlsActive
        and Menu:IsEarthControlsActive()
    local returning = self:AdvanceEarthViewReturn(now)
    if manual then self:AdvanceEarthMomentum(elapsed) end
    if not manual and not returning and targetYaw then
        local blend = 1 - math.exp(-elapsed * 2)
        self.Yaw = self.Yaw + math.AngleDifference(targetYaw, self.Yaw) * blend
        self.Pitch = self.Pitch + ((lat or 0) - self.Pitch) * blend
    elseif not manual and not returning then
        self.Yaw = self.Yaw + elapsed * 4
        self.Pitch = math.deg(tilt)
    end
    self.EarthViewZoom = self.EarthViewZoom or 1
    if not manual and not returning then
        local zoomBlend = 1 - math.exp(-elapsed * 4)
        self.EarthViewZoom = Lerp(zoomBlend, self.EarthViewZoom, 1)
    end
    local centre, presentationScale = self:ToPresentationSpace(
        Menu.Globe + Vector(0, 0, math.sin(now * 0.9) * 2 - visuals.earthDrop))
    local zoom = (self.PrototypeEarthZoom or 1) * self.EarthViewZoom * (transitionZoom or 1)
    local fogMode = render.GetFogMode()
    render.FogMode(MATERIAL_FOG_NONE)
    local fogDraws = self:DrawSpaceFog(centre, presentationScale, alpha, false)
    render.SetBlend(alpha)
    render.SetMaterial(earthMaterials.rim)
    render.DrawSprite(centre, 102 * zoom * presentationScale, 102 * zoom * presentationScale, color_white)
    local matrix = self:GetEarthRotation()
    matrix:Scale(Vector(42, 42, 42) * zoom * presentationScale)
    matrix:SetTranslation(centre)
    cam.PushModelMatrix(matrix)
    local highDetail = quality:GetBool() and getEarthHighDetailMaterials() or nil
    local highBlend = highDetail and self:GetEarthHighDetailBlend(zoom) or 0
    render.SetMaterial(earthMaterials.day)
    sphere.day:Draw()
    if highBlend > 0 then
        highDetail.day:SetFloat("$alpha", highBlend)
        render.SetMaterial(highDetail.day)
        sphere.day:Draw()
    end
    if highBlend < 1 then
        earthMaterials.lights:SetFloat("$alpha", 1 - highBlend)
        render.SetMaterial(earthMaterials.lights)
        sphere.night:Draw()
        earthMaterials.lights:SetFloat("$alpha", 1)
    end
    if highBlend > 0 then
        highDetail.lights:SetFloat("$alpha", highBlend)
        render.SetMaterial(highDetail.lights)
        sphere.night:Draw()
    end
    local layerMode = math.Clamp(prototypeLayers:GetInt(), 0, 3)
    if quality:GetBool() and layerMode % 2 == 1 then
        render.SetMaterial(earthMaterials.clouds)
        sphere.day:Draw()
    end
    if quality:GetBool() and layerMode >= 2 then
        render.SetMaterial(earthMaterials.distress)
        sphere.day:Draw()
    end
    cam.PopModelMatrix()
    local markerPosition, markerNormal = self:GetEarthMarkerPosition(
        centre, zoom, presentationScale, lat, lon)
    local markerAlpha = alpha * visuals.marker
    if markerPosition and markerAlpha > 0.001 then
        local cameraDirection = (self:GetPresentationCameraOrigin() - centre):GetNormalized()
        local facing = math.Clamp(markerNormal:Dot(cameraDirection), 0, 1)
        markerAlpha = markerAlpha * smoothStep(facing)
        if markerAlpha > 0.001 then
            local pulse = 1 + math.sin(now * 4.5) * 0.12
            render.SetBlend(markerAlpha)
            render.SetMaterial(sunMaterial)
            render.DrawSprite(markerPosition + markerNormal * 0.5 * presentationScale,
                7 * pulse * presentationScale, 7 * pulse * presentationScale, earthMarkerColor)
            render.SetColorMaterial()
            render.DrawSphere(markerPosition, 0.72 * presentationScale, 8, 6, earthMarkerColor)
        end
    end
    render.SetBlend(1)
    local strikeDraws = self:DrawNuclearStrikes(centre, self:GetEarthRotation(),
        42 * zoom * presentationScale, alpha * visuals.marker, now)
    fogDraws = fogDraws + self:DrawSpaceFog(centre, presentationScale, alpha, true, 1 / math.max(zoom, 1))
    render.FogMode(fogMode)
    local minimumZoom, maximumZoom, cameraDistance = self:GetEarthZoomBounds()
    self.Stats = {
        state = "earth", detail = detail, triangles = sphere.triangles, vertices = sphere.vertices,
        meshes = 2, draws = 3 + (highBlend > 0 and highBlend < 1 and 2 or highBlend >= 1 and 1 or 0)
            + (quality:GetBool() and (layerMode % 2 + math.floor(layerMode / 2)) or 0), models = 0,
        highDetailBlend = highBlend,
        seamVertices = sphere.seamVertices, poleTriangles = sphere.poleTriangles, zoom = zoom,
        layerMode = layerMode, alpha = alpha, marker = markerAlpha,
        markerLatitude = lat, markerLongitude = lon,
        manualView = manual == true, viewZoom = self.EarthViewZoom,
        minimumViewZoom = minimumZoom, maximumViewZoom = maximumZoom,
        cameraDistance = cameraDistance,
        fogDraws = fogDraws, strikeDraws = strikeDraws,
        nuclearStrikes = #(self.NuclearStrikes or {}),
        descent = visuals.descent, descentStage = visuals.stage, earthDrop = visuals.earthDrop,
        coordinateSpace = self:Uses3DSkybox() and "skybox" or "world"
    }
    return self.Stats
end

function Scene:DrawCity(alpha)
    alpha = math.Clamp(tonumber(alpha) or 1, 0, 1)
    local models = self:PrepareCity()
    if not models then
        self.Stats = { state = "city", meshes = 0, draws = 0, models = 0, error = self.CityError }
        return
    end
    local now = RealTime()
    local centreWorld = Menu.Globe + Vector(0, 0, -19)
    local centre, presentationScale = self:ToPresentationSpace(centreWorld)
    local finalAngle = Angle(0, 24, 0)
    local pitch = self.CityData.cellSpan / 16 * horizonCityScale * presentationScale
    local diorama = self:GetDioramaMeshes()
    local scale = Matrix()
    scale:Scale(Vector(horizonCityScale, horizonCityScale, horizonCityHeightScale) * presentationScale)
    render.SetBlend(alpha)
    render.SetMaterial(sunMaterial)
    local sunPosition = self:ToPresentationSpace(
        centreWorld + Menu.Camera.angles:Forward() * 54 + Vector(0, 0, 45))
    local hazePosition = self:ToPresentationSpace(
        centreWorld + Menu.Camera.angles:Forward() * 48 + Vector(0, 0, 20))
    render.DrawSprite(sunPosition, 104 * presentationScale, 104 * presentationScale, horizonSunColor)
    render.DrawSprite(hazePosition, 460 * presentationScale, 118 * presentationScale, horizonHazeColor)
    local terrainMatrix = Matrix()
    terrainMatrix:Rotate(finalAngle)
    terrainMatrix:Scale(Vector(presentationScale, presentationScale, presentationScale))
    terrainMatrix:SetTranslation(centre)
    cam.PushModelMatrix(terrainMatrix)
    render.SetMaterial(dioramaTerrainMaterial)
    diorama.terrain:Draw()
    render.SetMaterial(dioramaRoadMaterial)
    diorama.roads:Draw()
    cam.PopModelMatrix()
    render.SuppressEngineLighting(true)
    render.SetModelLighting(BOX_FRONT, 0.68, 0.7, 0.72)
    render.SetModelLighting(BOX_BACK, 0.3, 0.33, 0.38)
    render.SetModelLighting(BOX_RIGHT, 0.56, 0.58, 0.62)
    render.SetModelLighting(BOX_LEFT, 0.38, 0.41, 0.47)
    render.SetModelLighting(BOX_TOP, 0.95, 0.94, 0.88)
    render.SetModelLighting(BOX_BOTTOM, 0.18, 0.19, 0.22)
    render.SetColorModulation(0.96, 0.96, 0.95)
    for _, record in ipairs(models) do
        local localX, localY = record.offsetX * pitch / presentationScale,
            record.offsetY * pitch / presentationScale
        local offset = Vector(localX, localY, terrainHeight(localX, localY) + 0.7)
        offset:Rotate(finalAngle)
        record.entity:SetPos(centre + offset * presentationScale)
        record.entity:SetAngles(finalAngle)
        record.entity:EnableMatrix("RenderMultiply", scale)
        record.entity:DrawModel()
    end
    render.SetColorModulation(1, 1, 1)
    render.SuppressEngineLighting(false)
    local markerPosition = centre + Vector(0, 0, terrainHeight(0, 0) + 62) * presentationScale
    render.SetColorMaterial()
    render.DrawSphere(markerPosition, (2.7 + math.sin(now * 4) * 0.45) * presentationScale, 8, 6,
        cityMarkerColor)
    local labelPosition = centre + Vector(0, 0, 70) * presentationScale
    local labelAngle = (labelPosition - self:GetPresentationCameraOrigin()):Angle()
    labelAngle:RotateAroundAxis(labelAngle:Up(), -90)
    labelAngle:RotateAroundAxis(labelAngle:Forward(), 90)
    cam.Start3D2D(labelPosition, labelAngle, 0.36 * presentationScale)
        draw.SimpleTextOutlined(string.upper(self.CityData.label), "DermaDefaultBold", 0, 0,
            cityLabelColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, cityLabelOutline)
    cam.End3D2D()
    render.SetBlend(1)
    local selected = Menu.SelectedSlot and Menu.Slots and Menu.Slots[Menu.SelectedSlot] or {}
    local cameraDistance = (centre - self:GetPresentationCameraOrigin()):Length() / presentationScale
    local skyId, _, skyDay = self:GetPresentationSky()
    self.Stats = {
        state = "city", meshes = diorama.meshes, draws = #models + 6, models = #models,
        terrainTriangles = diorama.terrainTriangles, roadTriangles = diorama.roadTriangles,
        label = self.CityData.label, alpha = alpha, horizon = true, groundedDiorama = true,
        sun = true, coordinateSpace = self:Uses3DSkybox() and "skybox" or "world",
        cityScale = horizonCityScale, cityPitch = pitch / presentationScale,
        terrainHalfWidth = diorama.halfWidth, terrainHalfDepth = diorama.halfDepth,
        cameraDistance = cameraDistance,
        terrainCoverage = diorama.halfWidth / math.max(cameraDistance, 1),
        sky = skyId, skyDay = skyDay == true,
        selectedLatitude = tonumber(selected.originLatitude),
        selectedLongitude = tonumber(selected.originLongitude)
    }
    return self.Stats
end

function Scene:DrawAtmosphereVeil(alpha)
    alpha = math.Clamp(tonumber(alpha) or 0, 0, 1)
    if alpha <= 0.001 or not Menu.Camera then return 0 end
    local camera = self:GetPresentationCameraOrigin()
    local _, presentationScale = self:ToPresentationSpace(Menu.Globe)
    local forward = Menu.Camera.angles:Forward()
    render.OverrideDepthEnable(true, false)
    render.SetBlend(alpha)
    render.SetColorMaterial()
    render.DrawQuadEasy(camera + forward * 38 * presentationScale, -forward,
        340 * presentationScale, 260 * presentationScale, atmosphereColor, 0)
    render.SetBlend(1)
    render.OverrideDepthEnable(false, false)
    return 1
end

// Rebuilding the palette mid-descent is hidden by the veil, so the sky only changes while the handoff is covered.
function Scene:UpdatePresentationSky()
    local skyId = self:GetPresentationSky()
    if skyId == self.PresentationSkyId then return false end
    self.PresentationSkyId = skyId
    if ZM_SkyPalettes and isfunction(ZM_SkyPalettes.Update) then ZM_SkyPalettes:Update() end
    return true
end

function Scene:DrawPresentation()
    local state = self:GetPresentationState()
    if state == "hidden" then
        self:ReleaseCity()
        self.Stats = { state = "hidden", meshes = 0, draws = 0, models = 0 }
        return
    end
    local earthWeight, cityWeight, progress, earthZoom, atmosphere, descent = self:GetPresentationWeights()
    local visuals = self:GetDescentVisuals(descent)
    self:UpdatePresentationSky()
    local transition = self.PresentationTransition
    if not transition then
        if state == "city" then
            self:DrawCity(1)
        else
            self:DrawEarth()
        end
        return
    end
    local earthStats = earthWeight > 0.001 and self:DrawEarth(earthWeight, earthZoom, descent) or nil
    local cityStats = cityWeight > 0.001 and self:DrawCity(cityWeight) or nil
    local atmosphereDraws = self:DrawAtmosphereVeil(atmosphere)
    self.Stats = {
        state = "transition",
        transition = self:GetPresentationTransitionState(),
        progress = progress,
        earthAlpha = earthWeight,
        cityAlpha = cityWeight,
        earthZoom = earthZoom,
        descent = descent,
        descentStage = visuals.stage,
        atmosphere = atmosphere,
        sky = self.PresentationSkyId,
        skyDay = visuals.skyDay == true,
        cityHorizon = true,
        groundedDiorama = cityStats and cityStats.groundedDiorama or false,
        meshes = (earthStats and earthStats.meshes or 0) + (cityStats and cityStats.meshes or 0),
        models = cityStats and cityStats.models or 0,
        draws = (earthStats and earthStats.draws or 0) + (cityStats and cityStats.draws or 0)
            + atmosphereDraws
    }
end

function Scene:GetMaterialStatus()
    local result = {}
    for name, material in pairs(earthMaterials) do
        local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
        result[name] = {
            valid = not material:IsError() and texture ~= nil and texture:Width() > 0 and texture:Height() > 0,
            width = texture and texture:Width() or 0,
            height = texture and texture:Height() or 0,
            shader = material:GetShader()
        }
    end

    function Scene:GetHorizonMaterialStatus()
        return {
            sun = { valid = not sunMaterial:IsError(), shader = sunMaterial:GetShader() },
            terrain = { valid = not dioramaTerrainMaterial:IsError(), shader = dioramaTerrainMaterial:GetShader() },
            roads = { valid = not dioramaRoadMaterial:IsError(), shader = dioramaRoadMaterial:GetShader() }
        }
    end
    return result
end

function Scene:GetHighDetailMaterialStatus()
    local result = {}
    for name, material in pairs(getEarthHighDetailMaterials()) do
        local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
        result[name] = {
            valid = not material:IsError() and texture ~= nil and not texture:IsError()
                and texture:Width() > 0 and texture:Height() > 0,
            width = texture and texture:Width() or 0,
            height = texture and texture:Height() or 0,
            shader = material:GetShader()
        }
    end
    return result
end

hook.Remove("PostDrawOpaqueRenderables", "ZombieSim.Launcher.Globe")
hook.Remove("PostDrawTranslucentRenderables", "ZombieSim.Launcher.GlobeHalo")
hook.Add("PostDrawTranslucentRenderables", "ZombieSim.Launcher.Globe", function(depth, skybox)
    if Scene:ShouldDrawPresentationPass(depth, skybox) then Scene:DrawPresentation() end
end)

hook.Remove("HUDPaint", "ZombieSim.Launcher.CityLabel")

concommand.Remove("zombiesim_dev_launcher_presentation")
concommand.Add("zombiesim_dev_launcher_presentation", function(_, _, arguments)
    local state = string.lower(arguments[1] or "")
    if not Scene:SetPresentationState(state) then
        print("[ZombieSim] Usage: zombiesim_dev_launcher_presentation earth|city")
        return
    end
    print("[ZombieSim] Launcher presentation state: " .. state)
end)

concommand.Remove("zombiesim_dev_launcher_presentation_zoom")
concommand.Add("zombiesim_dev_launcher_presentation_zoom", function(_, _, arguments)
    local mode = string.lower(arguments[1] or "")
    if mode ~= "normal" and mode ~= "close" then
        print("[ZombieSim] Usage: zombiesim_dev_launcher_presentation_zoom normal|close")
        return
    end
    Scene.PrototypeEarthZoom = mode == "close" and 1.45 or 1
    print("[ZombieSim] Launcher Earth prototype zoom: " .. mode)
end)

concommand.Remove("zombiesim_dev_launcher_presentation_status")
concommand.Add("zombiesim_dev_launcher_presentation_status", function()
    print("[ZombieSim] Launcher presentation: " .. util.TableToJSON({
        stats = Scene.Stats or { state = Scene:GetPresentationState() },
        materials = Scene:GetMaterialStatus(),
        horizonMaterials = Scene:GetHorizonMaterialStatus(),
        cityError = Scene.CityError,
        presentationAssetLoads = Scene.PresentationAssetLoads or 0
    }))
end)

local function dancerPoint(entity)
    if not IsValid(entity) then return nil end
    local bone = entity:LookupBone("ValveBiped.Bip01_Spine2")
    local position = bone and entity:GetBonePosition(bone)
    if not position or position == vector_origin then return entity:WorldSpaceCenter() end
    return position
end

local function ease(value)
    value = math.Clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end

local function lerpPose(amount, from, to)
    return LerpVector(ease(amount), from, to)
end

function Scene:BeginCredits()
    if not Menu.CreditsCamera then return end
    Menu.CreditsGeneration = (Menu.CreditsGeneration or 0) + 1
    Menu.CreditsEnding = nil
    self.Started = RealTime()
    self.Phase = "room"
    self.PhaseAt = self.Started
    self.Order = {}
    self.Index = 0
    self.Target = nil
    self.Dancer = nil
    self.Hit = nil
    self.LastDancer = nil
    Menu.Credits = true
end

function Scene:NextDancer()
    local available = {}
    for i = 1, #(Menu.DancerNames or {}) do
        if dancerPoint(self:GetDancer(i)) then available[#available + 1] = i end
    end
    if #available == 0 then return nil end
    if self.Index >= #self.Order then
        self.Order = table.Copy(available)
        for i = #self.Order, 2, -1 do
            local j = math.random(i)
            self.Order[i], self.Order[j] = self.Order[j], self.Order[i]
        end
        if #self.Order > 1 and self.Order[1] == self.LastDancer then
            self.Order[1], self.Order[2] = self.Order[2], self.Order[1]
        end
        self.Index = 0
    end
    self.Index = self.Index + 1
    self.LastDancer = self.Order[self.Index]
    return self.LastDancer
end

function Scene:CreditsView()
    local room = Menu.CreditsCamera
    if not room then return end
    local now = RealTime()
    local age = now - self.PhaseAt
    local locked = string.lower(shotLock:GetString())
    local entity
    if locked ~= "" then
        for index, name in ipairs(Menu.DancerNames or {}) do
            if locked == name or locked == string.gsub(name, "^dancing_", "") then
                entity = self:GetDancer(index)
                break
            end
        end
    end
    if not dancerPoint(entity) then
        entity = nil
        locked = ""
    end
    if not entity then entity = self:GetDancer(self.Dancer) end
    local target = dancerPoint(entity)
    if self.Phase ~= "room" and not target then
        self.Phase, self.PhaseAt, self.Dancer = "room", now, nil
    end
    if self.Phase == "room" and age > 4 then
        self.Dancer = locked ~= "" and (self.Dancer or self:NextDancer()) or self:NextDancer()
        if dancerPoint(locked ~= "" and entity or self:GetDancer(self.Dancer)) then
            self.Phase, self.PhaseAt = "push", now
        else
            self.PhaseAt = now
        end
    end
    local origin = room.origin + Vector(0, 0, math.sin(now * 0.35) * 2)
    local angles = room.angles + Angle(0, math.sin(now * 0.25) * 1.5, 0)
    local fov = room.fov
    self.Hit = nil
    entity = locked ~= "" and entity or self:GetDancer(self.Dancer)
    target = dancerPoint(entity)
    if target and self.Phase ~= "room" then
        if not self.Target then self.Target = target end
        local vertical = math.Clamp(target.z - self.Target.z, -FrameTime() * 220, FrameTime() * 220)
        local limited = Vector(target.x, target.y, self.Target.z + vertical)
        self.Target = LerpVector(1 - math.exp(-FrameTime() * 6), self.Target, limited)
        local delta = room.origin - self.Target
        delta.z = 0
        if delta:LengthSqr() < 1 then delta = Vector(1, 0, 0) end
        local startAngle = math.atan2(delta.y, delta.x)
        local orbitAmount = self.Phase == "orbit" and ease(age / 7) * math.pi * 1.8 or 0
        local heading = startAngle + orbitAmount
        local desired = self.Target + Vector(math.cos(heading) * 52, math.sin(heading) * 52,
            18 + math.sin(now * 1.2) * 3)
        local trace = util.TraceHull({ start = self.Target, endpos = desired, mask = MASK_VISIBLE,
            mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5), filter = { entity, LocalPlayer() } })
        self.Hit = trace.Hit and trace.HitPos or nil
        if trace.StartSolid then
            desired = room.origin
        elseif trace.Hit then
            desired = trace.HitPos - (desired - self.Target):GetNormalized() * 7
            if desired:DistToSqr(self.Target) < 20 * 20 then desired = room.origin end
        end
        if self.Phase == "push" then
            local t = ease(age / 2.5)
            origin = lerpPose(t, room.origin, desired)
            fov = Lerp(t, room.fov, 45)
            if age >= 2.5 then self.Phase, self.PhaseAt = "orbit", now end
        elseif self.Phase == "orbit" then
            origin = desired
            fov = 45
            if age >= 7 then self.Phase, self.PhaseAt, self.Exit = "pull", now, desired end
        elseif self.Phase == "pull" then
            local t = ease(age / 2.5)
            origin = lerpPose(t, self.Exit or desired, room.origin)
            fov = Lerp(t, 45, room.fov)
            if age >= 2.5 then
                self.Phase, self.PhaseAt, self.Dancer, self.Target = "room", now, nil, nil
            end
        end
        local path = util.TraceHull({ start = room.origin, endpos = origin, mask = MASK_VISIBLE,
            mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5), filter = { entity, LocalPlayer() } })
        if path.StartSolid then
            origin = room.origin
        elseif path.Hit then
            origin = path.HitPos - (origin - room.origin):GetNormalized() * 7
            self.Hit = path.HitPos
        end
        angles = ((self.Target or target) - origin):Angle()
    end
    return { origin = origin, angles = angles, fov = fov, drawviewer = false, drawviewmodel = false }
end

hook.Add("SetupWorldFog", "ZombieSim.Launcher.CreditsFog", function()
    if not Menu.Active or not Menu.Credits then return end
    local fog = Menu.CreditsCamera and Menu.CreditsCamera.fog
    if not fog then return end
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(fog.start)
    render.FogEnd(fog.finish)
    render.FogMaxDensity(fog.density)
    render.FogColor(fog.red, fog.green, fog.blue)
    return true
end)

hook.Add("PostDrawTranslucentRenderables", "ZombieSim.Launcher.CreditsDebug", function(_, skybox)
    if skybox or not Menu.Credits or not debugShots:GetBool() or not Scene.Target or not Scene.Hit then return end
    render.DrawLine(Scene.Target, Scene.Hit, Color(255, 40, 40), true)
end)
