// Isolated client engine: no live hooks, convars, particles, sounds, meshes or persistence are modified.
return function()
    local state = {
        time = 0, frame = 0, delta = 1 / 60, worldReady = true, outdoor = true,
        sheltered = false, inDen = false, singlePlayer = true, predicted = true,
        map = "atmosphere_fixture", errors = {}, emitters = {}, meshes = {},
        calls = {}, holds = {}, loading = {}, cookies = {}, convars = {}, net = {},
        vertexCount = 0, vertexSignature = 0, vertexAlpha = 0
    }
    local function copy(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local result = {}
        seen[value] = result
        for key, item in pairs(value) do result[key] = copy(item, seen) end
        return setmetatable(result, getmetatable(value))
    end
    local env = { State = state }
    for _, name in ipairs({
        "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall",
        "select", "setmetatable", "tonumber", "tostring", "type", "unpack"
    }) do env[name] = _G[name] end
    setmetatable(env, { __index = function(_, name)
        error("Unsupported atmosphere fixture global: " .. tostring(name), 2)
    end })
    env._G = env
    env.math, env.table, env.string = copy(math), copy(table), copy(string)
    env.math.Clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
    env.math.Round = function(value) return math.floor(value + 0.5) end
    env.math.Approach = function(value, target, step)
        return value < target and math.min(value + step, target) or math.max(value - step, target)
    end
    local randomSeed = 1
    local function randomUnit()
        randomSeed = randomSeed * 16807 % 2147483647
        return randomSeed / 2147483647
    end
    env.math.random = function(first, last)
        local value = randomUnit()
        if first == nil then return value end
        if last == nil then first, last = 1, first end
        return math.floor(first + value * (last - first + 1))
    end
    env.math.Rand = function(first, last) return first + randomUnit() * (last - first) end
    env.table.Copy = copy
    env.table.Empty = function(value) for key in pairs(value) do value[key] = nil end end
    env.string.Trim = function(value) return value:match("^%s*(.-)%s*$") end
    local vector = {}
    vector.__index = vector
    function env.Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector) end
    function vector:Unpack() return self.x, self.y, self.z end
    function vector:SetUnpacked(x, y, z) self.x, self.y, self.z = x, y, z end
    function vector:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
    function vector:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
    function vector:DistToSqr(other) return (self - other):LengthSqr() end
    function vector:Normalize()
        local length = math.sqrt(self:LengthSqr())
        if length > 0 then self:SetUnpacked(self.x / length, self.y / length, self.z / length) end
    end
    function vector:ToScreen() return { visible = true } end
    function vector.__add(a, b) return env.Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    function vector.__sub(a, b) return env.Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    function vector.__mul(a, b)
        if type(a) == "number" then a, b = b, a end
        return env.Vector(a.x * b, a.y * b, a.z * b)
    end
    function vector.__div(a, b) return env.Vector(a.x / b, a.y / b, a.z / b) end
    env.VectorRand = function() return env.Vector(env.math.Rand(-1, 1), env.math.Rand(-1, 1), env.math.Rand(-1, 1)) end
    env.vector_origin = env.Vector()
    env.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env.Matrix = function() return {} end
    env.Lerp = function(amount, first, last) return first + (last - first) * amount end
    env.FrameNumber = function() return state.frame end
    env.CurTime, env.RealTime, env.SysTime = function() return state.time end, function() return state.time end, function() return state.time end
    env.FrameTime = function() return state.delta end
    env.ScrW, env.ScrH = function() return 1280 end, function() return 720 end
    env.ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end
    env.print = function() end
    env.NULL = {}
    env.IsValid = function(value) return type(value) == "table" and value.valid == true end
    env.MASK_SOLID_BRUSHONLY, env.MATERIAL_FOG_LINEAR = 1, 1
    env.MATERIAL_TRIANGLES, env.MATERIAL_QUADS, env.MOVETYPE_NOCLIP = 1, 2, 8
    local angles = {
        Forward = function() return env.Vector(1, 0, 0) end,
        Right = function() return env.Vector(0, 1, 0) end
    }
    local player = { valid = true, CellX = 0, CellY = 0, position = env.Vector(), velocity = env.Vector(100, 0, 0) }
    function player:GetPos() return self.position end
    function player:EyePos() return self.position + env.Vector(0, 0, 64) end
    function player:EyeAngles() return angles end
    function player:GetVelocity() return self.velocity end
    function player:GetNWInt() return 0 end
    function player:GetNWString() return "" end
    function player:Alive() return true end
    function player:IsOnGround() return true end
    function player:GetMoveType() return 0 end
    function player:WaterLevel() return 0 end
    function player:IsAdmin() return true end
    state.player = player
    env.LocalPlayer = function() return player end
    env.EyePos = function() return player:EyePos() end
    env.EyeAngles = function() return angles end
    env.EyeVector = function() return angles:Forward() end
    env.IsFirstTimePredicted = function() return state.predicted end
    env.player = { GetAll = function() return { player } end }
    local world = {}
    function world:IsWorld() return true end
    function world:WorldSpaceAABB() return env.Vector(-96, -96, -32), env.Vector(96, 96, 256) end
    world.GetRenderBounds = world.WorldSpaceAABB
    env.game = {
        GetMap = function() return state.map end, GetWorld = function() return world end,
        SinglePlayer = function() return state.singlePlayer end
    }
    env.ZM_World = {
        ActiveProfile = "preview", IsLoaded = function() return state.worldReady end,
        GetCellsForMap = function() return state.outdoor and { {} } or {} end,
        GetGridCoordinates = function(_, x, y) return x, y end,
        GetCell = function() return { atmosphereProfile = 1 } end
    }
    local profile = {
        id = "fixture", fog = { start = 100, ["end"] = 1600, maxDensity = 1, color = { 100, 120, 140 }, stormMultiplier = 0.5 },
        colorCorrection = { brightness = 0, contrast = 1, colour = 0.8, add = { 0, 0, 0 }, multiply = { 1, 1, 1 } }
    }
    env.ZM_World.GetAtmosphereProfileByIndex = function(_, index)
        if state.worldReady and index == 1 then return profile end
    end
    env.ZM_SafeZones = { IsPlayerInside = function() return state.inDen end }
    env.ZM_Quality = { ConVars = {} }
    env.ZM_LauncherMenu, env.ZM_WorldMap = { Active = false }, { Capturing = false }
    env.ZM_SkyInspection = { GetLauncherFogSettings = function() return state.launcherFog end }
    env.ZM_Skybox = {
        SceneryLight = { 1, 1, 1 }, ClampWorldBounds = function(_, minimum, maximum) return minimum, maximum end,
        GetSkyboxFog = function(_, settings) return settings end
    }
    local emptySnapshot = function() return {} end
    env.ZM_Skybox.GetDiagnosticSnapshot = emptySnapshot
    env.ZM_WorldMap.GetCaptureDiagnosticSnapshot = emptySnapshot
    env.ZM_RadiationFeedback = {
        GetGrayscale = function() return state.radiation or 0 end,
        GetExtremeVisualSeverity = function() return state.radiation or 0 end,
        GetDiagnosticSnapshot = emptySnapshot
    }
    env.ZM_GoreClient, env.ZM_Music = { GetDiagnosticSnapshot = emptySnapshot }, { GetDiagnosticSnapshot = emptySnapshot }
    env.ZM_IsShoulderCamera = function() return false end
    env.ZM_Loading = {
        Step = function() end,
        Begin = function(_, label) state.loading[#state.loading + 1] = label return #state.loading end,
        Finish = function(_, id, result) state.loading[id] = result end
    }
    env.ZM_LoadingScreen = {
        HideUntil = 0, SetExtraHold = function(_, key, active) state.holds[key] = active end
    }
    env.cookie = {
        GetString = function(key, default) return state.cookies[key] or default end,
        Set = function(key, value) state.cookies[key] = value end
    }
    function env.CreateClientConVar(name, default)
        if not state.convars[name] then
            state.convars[name] = {
                value = tonumber(default), GetFloat = function(self) return self.value end,
                GetBool = function(self) return self.value ~= 0 end
            }
        end
        return state.convars[name]
    end
    env.GetConVar = function(name) return state.convars[name] end
    env.file = { Exists = function() return true end, CreateDir = function() end, Write = function() end }
    env.util = {
        SharedRandom = function(_, minimum, maximum) return (minimum + maximum) * 0.5 end,
        TableToJSON = function() return "fixture" end,
        TraceLine = function(request)
            if request.endpos.z > request.start.z then
                return { Hit = true, HitSky = not state.sheltered, HitWorld = true }
            end
            return {
                Hit = true, HitSky = false, HitWorld = true, StartSolid = false,
                HitPos = env.Vector(request.start.x, request.start.y, 0), HitNormal = env.Vector(0, 0, 1)
            }
        end
    }
    local function log(name, ...)
        state.calls[#state.calls + 1] = { name, ... }
    end
    local texture = { IsError = function() return false end, GetName = function() return "fixture" end, Width = function() return 64 end }
    env.Material = function(name)
        return {
            IsError = function() return false end, GetTexture = function() return texture end,
            GetShader = function() return "UnlitGeneric" end, SetTexture = function() end,
            SetFloat = function() end
        }
    end
    env.CreateMaterial = env.Material
    env.render, env.surface, env.cam, env.mesh = {}, {}, {}, {}
    for _, name in ipairs({ "FogMode", "FogStart", "FogEnd", "FogMaxDensity", "FogColor", "SetMaterial", "DrawQuadEasy", "DrawBeam" }) do
        env.render[name] = function(...) log(name, ...) end
    end
    env.render.GetLightColor = function() return env.Vector(1, 1, 1) end
    env.render.GetViewSetup = function() return { fov = 90, aspect = 16 / 9 } end
    for _, name in ipairs({ "SetDrawColor", "DrawRect" }) do env.surface[name] = function(...) log(name, ...) end end
    for _, name in ipairs({ "Start2D", "End2D", "PushModelMatrix", "PopModelMatrix" }) do env.cam[name] = function(...) log(name, ...) end end
    env.DrawColorModify = function(settings) log("DrawColorModify", copy(settings)) end
    env.mesh.Begin = function(kind, count)
        assert(count > 0, "zero-count mesh.Begin")
        assert(not state.meshOpen, "nested mesh.Begin")
        state.meshOpen = true
        log("mesh.Begin", kind, count)
    end
    env.mesh.End = function() assert(state.meshOpen, "unmatched mesh.End") state.meshOpen = false end
    for _, name in ipairs({ "Position", "Normal", "TexCoord", "Color", "AdvanceVertex" }) do
        env.mesh[name] = function() assert(state.meshOpen, "vertex outside mesh.Begin") end
    end
    env.mesh.Position = function(position)
        assert(state.meshOpen, "position outside mesh.Begin")
        state.vertexCount = state.vertexCount + 1
        state.vertexSignature = state.vertexSignature + position.x * 0.37 + position.y * 0.61 + position.z * 0.83
    end
    env.mesh.Color = function(_, _, _, alpha)
        assert(state.meshOpen, "colour outside mesh.Begin")
        state.vertexAlpha = state.vertexAlpha + alpha
    end
    env.Mesh = function()
        local mesh = {
            BuildFromTriangles = function(self, triangles) assert(#triangles > 0) self.triangles = #triangles end,
            Destroy = function(self) self.destroyed = true end,
            Draw = function(self) assert(not self.destroyed) log("IMesh.Draw", self.triangles) end
        }
        state.meshes[#state.meshes + 1] = mesh
        return mesh
    end
    // These setters do not simulate particle physics; unknown methods must fail.
    local particle = setmetatable({}, { __index = function(_, name)
        error("Unsupported atmosphere fixture particle method: " .. tostring(name), 2)
    end })
    for _, name in ipairs({
        "SetDieTime", "SetStartAlpha", "SetEndAlpha", "SetStartSize", "SetEndSize",
        "SetRoll", "SetRollDelta", "SetColor", "SetCollide", "SetGravity", "SetVelocity",
        "SetAirResistance", "SetBounce", "SetCollideCallback", "SetStartLength", "SetEndLength"
    }) do particle[name] = function() end end
    env.ParticleEmitter = function()
        local emitter = {
            active = 1, Add = function(self) self.added = (self.added or 0) + 1 return particle end,
            SetNoDraw = function(self, hidden) self.hidden = hidden end,
            GetNumActiveParticles = function(self) return self.active end,
            Finish = function(self) self.finished = (self.finished or 0) + 1 end
        }
        state.emitters[#state.emitters + 1] = emitter
        return emitter
    end
    env.CreateSound = function()
        local patch = { playing = false }
        function patch:PlayEx() self.playing = true end
        function patch:ChangeVolume() end
        function patch:IsPlaying() return self.playing end
        function patch:FadeOut() self.playing = false end
        return patch
    end
    env.sound = { Play = function(...) log("sound.Play", ...) end }
    env.GetGlobal2Int = function() return 0 end
    env.GetGlobal2Vector = function(_, default) return default end
    local hooks, receivers, commands = {}, {}, {}
    env.hook = {
        Add = function(event, name, callback) hooks[event] = hooks[event] or {} hooks[event][name] = callback end,
        Remove = function(event, name) if hooks[event] then hooks[event][name] = nil end end,
        GetTable = function() return hooks end
    }
    env.net = {
        Receive = function(name, callback) receivers[name] = callback end,
        ReadUInt = function() return table.remove(state.net, 1) end,
        ReadFloat = function() return table.remove(state.net, 1) end,
        Start = function() end, WriteUInt = function() end, WriteString = function() end, SendToServer = function() end
    }
    env.concommand = { Add = function(name, callback) commands[name] = callback end }
    env.timer = { Simple = function(_, callback) state.deferred = callback end }
    state.hooks, state.receivers, state.commands = hooks, receivers, commands
    function state:Advance(seconds)
        self.time, self.frame = self.time + (seconds or self.delta), self.frame + 1
    end
    function state:Hook(event, name, ...)
        assert(hooks[event] and hooks[event][name], "missing hook " .. event .. "/" .. name)
        return hooks[event][name](...)
    end
    function state:Weather(code, amount)
        self.net = { code, amount }
        receivers["ZM.Atmosphere.Weather"]()
    end
    return env
end
