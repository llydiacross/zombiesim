return function()
    local state = { globals = {}, meshes = {}, errors = {}, hooks = {}, route = nil, matrixDepth = 0 }
    local env = { State = state }
    for _, name in ipairs({ "assert", "ipairs", "pairs", "tostring" }) do env[name] = _G[name] end
    setmetatable(env, { __index = function(_, name)
        error("Unsupported transition marker fixture global: " .. tostring(name), 2)
    end })
    local vector = {}
    vector.__index = vector
    function env.Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector) end
    function vector:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
    function vector:Cross(other)
        return env.Vector(self.y * other.z - self.z * other.y, self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x)
    end
    function vector:LengthSqr() return self:Dot(self) end
    function vector:Normalize()
        local length = math.sqrt(self:LengthSqr())
        if length > 0 then self.x, self.y, self.z = self.x / length, self.y / length, self.z / length end
    end
    function vector:DistToSqr(other) return (self - other):LengthSqr() end
    function vector.__add(a, b) return env.Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    function vector.__sub(a, b) return env.Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    function vector.__mul(a, b) return env.Vector(a.x * b, a.y * b, a.z * b) end
    function vector.__eq(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
    env.Color = function(r, g, b) return { r = r, g = g, b = b } end
    env.Matrix = function() return {} end
    env.CreateMaterial = function(_, shader, values)
        assert(shader == "UnlitGeneric" and values["$nocull"] == 1 and not values["$ignorez"],
            "two-sided depth-tested arrow material")
        return { IsError = function() return state.materialError == true end,
            GetTexture = function() return { Width = function() return 32 end } end,
            GetShader = function() return "UnlitGeneric" end }
    end
    env.Mesh = function(material)
        assert(material and material.IsError, "mesh requires its intended vertex-colour material")
        local object = { builds = 0, draws = 0, destroyed = 0 }
        function object:BuildFromTriangles(vertices)
            assert(self.destroyed == 0 and #vertices == 9, "valid owned arrow mesh")
            self.vertices, self.builds = vertices, self.builds + 1
        end
        function object:Draw()
            assert(self.destroyed == 0 and state.matrixDepth == 1, "mesh draw scope")
            self.draws = self.draws + 1
        end
        function object:Destroy() self.destroyed = self.destroyed + 1 end
        state.meshes[#state.meshes + 1] = object
        return object
    end
    env.GetGlobal2Int = function(key, default) return state.globals[key] or default end
    env.GetGlobal2Bool = function(key, default)
        if state.globals[key] == nil then return default end
        return state.globals[key]
    end
    env.GetGlobal2Vector = function(key) return state.globals[key] or env.Vector() end
    state.player = { valid = true, alive = true, safeZone = "", blocked = false }
    function state.player:Alive() return self.alive end
    function state.player:GetNWString() return self.safeZone end
    function state.player:GetNWInt() return 0 end
    function state.player:GetNWBool() return self.blocked end
    env.LocalPlayer = function() return state.player end
    env.IsValid = function(value) return value and value.valid == true end
    state.eye = env.Vector()
    env.EyePos = function() return state.eye end
    env.ZM_World = {
        IsLoaded = function() return true end, GetGridCoordinates = function() return 0, 0 end,
        GetCell = function() return {} end
    }
    env.ZM_WorldMap = { GetWaypointDirection = function() return state.route end }
    env.ZM_SkyInspection = {}
    env.ZM_LauncherMenu = {}
    env.ZM_LoadingScreen = { IsHidingHud = function() return state.loading == true end }
    env.cam = {
        PushModelMatrix = function() state.matrixDepth = state.matrixDepth + 1 end,
        PopModelMatrix = function() state.matrixDepth = state.matrixDepth - 1 end
    }
    env.render = { SetMaterial = function() end }
    state.polygons = {}
    env.draw = { NoTexture = function() end }
    env.surface = {
        SetDrawColor = function(r, g, b) state.drawColour = { r = r, g = g, b = b } end,
        DrawPoly = function(points)
            state.polygons[#state.polygons + 1] = { points = points, colour = state.drawColour }
        end
    }
    env.hook = { Add = function(event, name, callback)
        state.hooks[event] = state.hooks[event] or {}
        state.hooks[event][name] = callback
    end }
    env.concommand = { Add = function() end }
    env.ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end
    function state:Gate(code, index, position, normal)
        local key = "ZMTransitionGate_" .. code .. "_" .. index
        self.globals["ZMTransitionGateCount_" .. code] = index
        self.globals[key .. "_ArrowCount"] = 1
        self.globals[key .. "_SurfaceReady"] = true
        self.globals[key .. "_Surface"] = position
        self.globals[key .. "_Normal"] = normal or env.Vector(0, 0, 1)
        return key
    end
    return env
end
