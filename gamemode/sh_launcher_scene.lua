// Presentation data is authored independently of the generated world.
ZM_LauncherScene = ZM_LauncherScene or {}
local Scene = ZM_LauncherScene
Scene.SkyFlightDuration = 10
Scene.SkyFlightHeight = 512
Scene.SkyFlightRadius = 480

local function easeFlight(value)
    value = math.Clamp(value, 0, 1)
    return value * value * value * (value * (value * 6 - 15) + 10)
end

function Scene:GetSkyFlightPose(camera, elapsed)
    elapsed = math.Clamp(elapsed, 0, self.SkyFlightDuration)
    local progress = easeFlight(elapsed / self.SkyFlightDuration)
    local turn = progress * math.pi * 2
    local heading = Angle(0, camera.angles.y, 0)
    local lift = easeFlight(elapsed / 3.2)
    local settling = easeFlight(elapsed / 1.6)
    local envelope = math.sin(progress * math.pi)
    local flap = 10 * easeFlight(elapsed / 0.6) * (1 - lift) * math.sin(elapsed * math.pi * 1.5) ^ 2
    local origin = camera.origin + heading:Forward() * (self.SkyFlightRadius * math.sin(turn))
        + heading:Right() * (self.SkyFlightRadius * (1 - math.cos(turn)))
        + Vector(0, 0, self.SkyFlightHeight * lift + flap + 8 * envelope * math.sin(turn * 2))
    local pitch = Lerp(settling, camera.angles.p, -6) + 2 * envelope * math.sin(turn)
    local roll = Lerp(settling, camera.angles.r, 0) - 7 * envelope + 1.5 * envelope * math.sin(turn * 2)
    return origin, Angle(pitch, camera.angles.y - progress * 360, roll)
end

function Scene:GetData()
    if self.Data then return self.Data end
    local raw = file.Read("data_static/launcher_scene.json", "GAME")
    local data = raw and util.JSONToTable(raw)
    if not data or data.schemaVersion ~= 1 or type(data.profiles) ~= "table"
        or type(data.credits) ~= "table" then return nil end
    self.Data = data
    return data
end

function Scene:GetAnchor(profile)
    local data = self:GetData()
    local anchor = data and data.profiles[profile]
    if not anchor or type(anchor.city) ~= "string" or not tonumber(anchor.latitude)
        or not tonumber(anchor.longitude) or not tonumber(anchor.extentKm) then return nil end
    return anchor
end

function Scene:GetOrigin(profile, cellX, cellY)
    local anchor = self:GetAnchor(profile)
    if not anchor then return nil end
    local x, y = tonumber(cellX), tonumber(cellY)
    if not x or not y then return tonumber(anchor.latitude), tonumber(anchor.longitude) end
    local world = ZM_World and ZM_World:GetData() or {}
    local origin = world.world and world.world.origin or {}
    local dx = math.Clamp(x - (tonumber(origin[1]) or x), -1, 1)
    local dy = math.Clamp(y - (tonumber(origin[2]) or y), -1, 1)
    local km = math.Clamp(tonumber(anchor.extentKm) or 0, 0, 100) / 4
    local latitude = math.Clamp(tonumber(anchor.latitude) + dy * km / 111, -89, 89)
    local longitude = tonumber(anchor.longitude) + dx * km / (111 * math.max(0.1, math.cos(math.rad(latitude))))
    return latitude, (longitude + 180) % 360 - 180
end
