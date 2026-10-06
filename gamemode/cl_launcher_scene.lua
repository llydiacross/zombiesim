// Launcher presentation is drawn only while the menu is open.
ZM_LauncherSceneClient = ZM_LauncherSceneClient or {}
local Scene = ZM_LauncherSceneClient
local Menu = ZM_LauncherMenu
local quality = CreateClientConVar("zombiesim_globe_quality", "0", true, false,
    "Globe detail: 0 low, 1 normal.")
local shotLock = CreateClientConVar("zombiesim_credits_shot", "", false, false,
    "Credits dancer name for camera tuning.")
local debugShots = CreateClientConVar("zombiesim_credits_debug", "0", false, false,
    "Show the credits camera trace and shot state.")
local tilt = math.rad(12)
local lightDirection = Vector(-0.4, -0.8, 0.45)

function Scene:GetDancer(index)
    local id = Menu.DancerIds and Menu.DancerIds[index]
    return id and id > 0 and Entity(id) or nil
end

local function surfacePoint(latitude, longitude)
    local lat, lon = math.rad(latitude), math.rad(longitude)
    return Vector(math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))
end

local function rotate(normal, yawSine, yawCosine, pitchSine, pitchCosine)
    local x = normal.x * yawCosine - normal.y * yawSine
    local y = normal.x * yawSine + normal.y * yawCosine
    return Vector(x, y * pitchCosine - normal.z * pitchSine,
        y * pitchSine + normal.z * pitchCosine)
end

local continents = {
    { 48, -104, 0.62 }, { -8, -65, 0.53 }, { 52, 18, 0.69 },
    { 4, 25, 0.57 }, { 24, 91, 0.72 }, { -24, 136, 0.43 }, { -80, 0, 0.36 }
}
for _, region in ipairs(continents) do region.normal = surfacePoint(region[1], region[2]) end

// Positive scores are land; the continuous value lets coastlines blend smoothly across triangles.
local function landScore(normal, lat, lon)
    local score = -1
    for _, region in ipairs(continents) do
        score = math.max(score, normal:Dot(region.normal) - (0.98 - region[3] * 0.1))
    end
    return score + math.sin(math.rad(lat * 13 + lon * 7)) * 0.045
        + math.cos(math.rad(lat * 21 - lon * 11)) * 0.026
end

local globeMaterial = CreateMaterial("zombiesim_launcher_globe_v3", "UnlitGeneric", {
    ["$basetexture"] = "color/white",
    ["$vertexcolor"] = "1",
    ["$nocull"] = "1"
})

local function surfaceGrid(detail)
    if Scene.SurfaceVersion ~= 2 then
        Scene.SurfaceGrids, Scene.SurfaceVersion = {}, 2
    end
    if Scene.SurfaceGrids[detail] then return Scene.SurfaceGrids[detail] end
    local grid = {}
    for row = 0, detail do
        grid[row] = {}
        for col = 0, detail * 2 do
            local lat = -90 + row * 180 / detail
            local lon = -180 + col * 180 / detail
            local normal = surfacePoint(lat, lon)
            local score = landScore(normal, lat, lon)
            grid[row][col] = {
                normal = normal,
                land = math.Clamp((score + 0.015) / 0.03, 0, 1),
                cityLights = math.sin(math.rad(lat * 119 + lon * 67))
                    * math.cos(math.rad(lat * 83 - lon * 141)) > 0.62
            }
        end
    end
    Scene.SurfaceGrids[detail] = grid
    return grid
end

local function surfaceColour(entry, rotated)
    local daylight = math.max(0, rotated:Dot(lightDirection))
    local rim = math.pow(1 - math.abs(rotated.y), 3)
    local land = entry.land * entry.land * (3 - 2 * entry.land)
    local amount = 0.24 + daylight * 0.76
    local light = (entry.cityLights and daylight < 0.28) and land or 0
    local red = Lerp(land, 8, 48) * amount + rim * 20 + light * 65
    local green = Lerp(land, 32, 110) * amount + rim * 39 + light * 43
    local blue = Lerp(land, 78, 68) * amount + rim * 72 + light * 9
    return math.min(255, red), math.min(255, green), math.min(255, blue)
end

local function emitVertex(entry, rotated, centre, radius)
    local red, green, blue = surfaceColour(entry, rotated)
    mesh.Position(centre + rotated * radius)
    mesh.Normal(rotated)
    mesh.Color(red, green, blue, 255)
    mesh.AdvanceVertex()
end

function Scene:IsGlobeHidden()
    return not Menu.Active or Menu.Credits or not Menu.Globe
        or (ZM_SkyInspection and ZM_SkyInspection:IsActive())
        or (Menu.IsCharacterPreviewVisible and Menu:IsCharacterPreviewVisible())
end

function Scene:DrawGlobe()
    if self:IsGlobeHidden() or not Menu.Camera then return end
    local latitudeSteps = quality:GetBool() and 48 or 24
    local longitudeSteps = latitudeSteps * 2
    local now = RealTime()
    local anchor = ZM_LauncherScene:GetAnchor(Menu.Profile)
    local selected = Menu.SelectedSlot and Menu.Slots and Menu.Slots[Menu.SelectedSlot]
    local lat = tonumber(selected and selected.originLatitude) or (anchor and tonumber(anchor.latitude))
    local lon = tonumber(selected and selected.originLongitude) or (anchor and tonumber(anchor.longitude))
    local targetYaw = lon and (-90 - lon) or nil
    local elapsed = math.min(FrameTime(), 0.1)
    self.Yaw = self.Yaw or 0
    self.Pitch = self.Pitch or math.deg(tilt)
    if targetYaw then
        local blend = 1 - math.exp(-elapsed * 2)
        self.Yaw = self.Yaw + math.AngleDifference(targetYaw, self.Yaw) * blend
        self.Pitch = self.Pitch + ((lat or 0) - self.Pitch) * blend
    else
        self.Yaw = self.Yaw + elapsed * 4
        self.Pitch = math.deg(tilt)
    end
    local centre = Menu.Globe + Vector(0, 0, math.sin(now * 0.9) * 2)
    local yawSine, yawCosine = math.sin(math.rad(self.Yaw)), math.cos(math.rad(self.Yaw))
    local pitchSine, pitchCosine = math.sin(math.rad(self.Pitch)), math.cos(math.rad(self.Pitch))
    // Vertex-coloured mesh; only the camera-facing (south, -Y) hemisphere is emitted, so face winding is irrelevant.
    local fogMode = render.GetFogMode()
    render.FogMode(MATERIAL_FOG_NONE)
    local grid = surfaceGrid(latitudeSteps)
    local rotated = {}
    for row = 0, latitudeSteps do
        rotated[row] = {}
        for col = 0, longitudeSteps do
            rotated[row][col] = rotate(grid[row][col].normal, yawSine, yawCosine, pitchSine, pitchCosine)
        end
    end
    local quads = {}
    for row = 0, latitudeSteps - 1 do
        for col = 0, longitudeSteps - 1 do
            if math.min(rotated[row][col].y, rotated[row + 1][col].y, rotated[row][col + 1].y,
                rotated[row + 1][col + 1].y) < 0.05 then
                quads[#quads + 1] = { row, col }
            end
        end
    end
    render.SetMaterial(globeMaterial)
    mesh.Begin(MATERIAL_TRIANGLES, #quads * 2)
    for _, quad in ipairs(quads) do
        local row, col = quad[1], quad[2]
        emitVertex(grid[row][col], rotated[row][col], centre, 42)
        emitVertex(grid[row + 1][col], rotated[row + 1][col], centre, 42)
        emitVertex(grid[row + 1][col + 1], rotated[row + 1][col + 1], centre, 42)
        emitVertex(grid[row][col], rotated[row][col], centre, 42)
        emitVertex(grid[row + 1][col + 1], rotated[row + 1][col + 1], centre, 42)
        emitVertex(grid[row][col + 1], rotated[row][col + 1], centre, 42)
    end
    mesh.End()
    render.SetColorMaterial()
    if anchor then
        for slot, row in pairs(Menu.Slots or {}) do
            local dotLat = tonumber(row.originLatitude) or tonumber(anchor.latitude)
            local dotLon = tonumber(row.originLongitude) or tonumber(anchor.longitude)
            if dotLat and dotLon then
                local normal = surfacePoint(dotLat, dotLon)
                local rotated = rotate(normal, yawSine, yawCosine, pitchSine, pitchCosine)
                if rotated.y < -0.03 then
                    local pulse = slot == Menu.SelectedSlot and 1 + 0.3 * math.sin(now * 4) or 0.7
                    render.DrawSphere(centre + rotated * 43, pulse * 1.7, 8, 6,
                        Color(255, slot == Menu.SelectedSlot and 175 or 105, 70))
                end
            end
        end
    end
    render.FogMode(fogMode)
end

// The opaque pass was never visible in the launcher room; the translucent pass is drawn after the fake-fog walls.
hook.Remove("PostDrawOpaqueRenderables", "ZombieSim.Launcher.Globe")
hook.Remove("PostDrawTranslucentRenderables", "ZombieSim.Launcher.GlobeHalo")
hook.Add("PostDrawTranslucentRenderables", "ZombieSim.Launcher.Globe", function(depth, skybox)
    if not depth and not skybox then Scene:DrawGlobe() end
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
