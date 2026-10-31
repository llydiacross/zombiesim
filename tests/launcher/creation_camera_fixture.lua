return function()
    local state = {
        map = "zn_preview_start", markers = {}, serverHooks = {}, clientHooks = {},
        errors = {}, pvs = {}, receivers = {}, tokens = {}, clientCommands = {}, clientWrites = {}
    }

    local vectorMethods = {}
    function vectorMethods:GetNormalized() return self end
    local function vector(x, y, z)
        return setmetatable({ x = x, y = y, z = z }, { __index = vectorMethods })
    end
    local function angle(p, y, r) return { p = p, y = y, r = r } end
    local function marker(class, origin, angles, fov)
        return {
            valid = true, class = class, origin = origin, angles = angles, fov = fov,
            GetClass = function(self) return self.class end,
            GetPos = function(self) return self.origin end,
            GetAngles = function(self) return self.angles end,
            GetInternalVariable = function(self, name)
                if name == "FOV" then return self.fov end
                if name == "fogStart" then return 2048 end
                if name == "fogEnd" then return 4096 end
                if name == "fogMaxDensity" then return 1 end
                if name == "fogColor" then return "0 0 0" end
                error("unsupported camera variable " .. tostring(name))
            end
        }
    end
    state.markers.menu_camera = marker("point_camera", vector(1, 2, 3), angle(4, 5, 6), 70)
    state.markers.create_character = marker("point_camera", vector(11, 12, 13), angle(14, 15, 16), 80)
    state.markers.preview_skybox = marker("point_camera", vector(21, 22, 23), angle(24, 25, 26), 90)
    state.markers.credits_camera = marker("point_camera", vector(31, 32, 33), angle(34, 35, 36), 90)
    state.markers.menu_globe = marker("info_target", vector(41, 42, 43), angle(0, 0, 0))
    state.target = { valid = true, ZM_LauncherState = "menu" }

    local function hooks(store)
        return {
            Add = function(event, name, callback)
                store[event] = store[event] or {}
                store[event][name] = callback
            end,
            Remove = function(event, name)
                if store[event] then store[event][name] = nil end
            end,
            GetTable = function() return store end
        }
    end
    local net = {}
    local function write(kind, value)
        state.tokens[#state.tokens + 1] = { kind = kind, value = value }
    end
    local function read(kind)
        local token = state.tokens[state.readIndex]
        assert(token and token.kind == kind, "unexpected network field " .. kind)
        state.readIndex = state.readIndex + 1
        return token.value
    end
    function net.Start(name)
        assert(name == "ZM.LauncherStatus", "unexpected network message")
        state.tokens = {}
    end
    function net.WriteBool(value) assert(type(value) == "boolean") write("bool", value) end
    function net.WriteString(value) assert(type(value) == "string") write("string", value) end
    function net.WriteUInt(value) assert(type(value) == "number") write("uint", value) end
    function net.WriteFloat(value) assert(type(value) == "number") write("float", value) end
    function net.WriteVector(value) assert(type(value) == "table") write("vector", value) end
    function net.WriteAngle(value) assert(type(value) == "table") write("angle", value) end
    function net.ReadBool() return read("bool") end
    function net.ReadString() return read("string") end
    function net.ReadUInt() return read("uint") end
    function net.ReadFloat() return read("float") end
    function net.ReadVector() return read("vector") end
    function net.ReadAngle() return read("angle") end
    function net.Send(target) assert(target == state.target, "unexpected network recipient") end
    function net.Receive(name, callback)
        assert(not state.receivers[name], "duplicate network receiver")
        state.receivers[name] = callback
    end
    function state:Deliver()
        self.readIndex = 1
        self.receivers["ZM.LauncherStatus"]()
        assert(self.readIndex == #self.tokens + 1, "launcher status left unread fields")
    end

    local util = {
        AddNetworkString = function(name)
            assert(name == "ZM.LauncherStatus" or name == "ZM.LauncherRequest")
        end,
        TableToJSON = function() return "[]" end,
        JSONToTable = function(value) assert(value == "[]") return {} end
    }
    local commands = { Add = function() end, Remove = function() end }
    local clientCommands = {
        Add = function(name, callback) state.clientCommands[name] = callback end,
        Remove = function(name) state.clientCommands[name] = nil end
    }
    local function valid(value) return type(value) == "table" and value.valid == true end
    local function material() return { IsError = function() return false end } end
    local function convar()
        return {
            GetBool = function() return true end,
            GetInt = function() return 1 end,
            GetString = function() return "1" end
        }
    end
    local server = {
        assert = assert, ipairs = ipairs, pairs = pairs, tonumber = tonumber, tostring = tostring,
        type = type, math = math, string = string, table = table,
        util = util, net = net, hook = hooks(state.serverHooks), concommand = commands,
        IsValid = valid, CreateConVar = convar, FCVAR_ARCHIVE = 1,
        game = { GetMap = function() return state.map end },
        ents = {
            FindByName = function(name)
                local found = state.markers[name]
                return found and { found } or {}
            end,
            FindByClass = function(name)
                assert(name == "sky_camera")
                return {}
            end
        },
        ZM_World = {
            ActiveProfile = "preview",
            LauncherMapProfiles = { zn_preview_start = "preview", zn_city_start = "city" }
        },
        ZM_CharacterService = { List = function() return {} end },
        ZM_LauncherScene = {
            SkyFlightDuration = 10,
            GetSkyFlightPose = function(_, pose) return pose.origin end
        },
        AddOriginToPVS = function(origin) state.pvs[#state.pvs + 1] = origin end,
        ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end
    }
    local client = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, pcall = pcall,
        tonumber = tonumber, tostring = tostring, type = type, math = math, string = string, table = table,
        util = {
            JSONToTable = util.JSONToTable,
            TableToJSON = function(value) state.lastClientJson = value return "{}" end
        },
        net = net, hook = hooks(state.clientHooks), concommand = clientCommands,
        IsValid = valid, Vector = vector, Angle = angle,
        Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
        Material = material, CreateMaterial = material, CreateClientConVar = convar,
        game = { GetMap = function() return state.map end },
        file = {
            CreateDir = function(name) assert(name == "zombiesim") end,
            Write = function(path, value)
                assert(value == "{}")
                state.clientWrites[path] = state.lastClientJson
            end
        },
        print = function() end,
        vector_origin = vector(0, 0, 0), angle_zero = angle(0, 0, 0),
        ZM_DermaSkin = { Palette = {} }, ZM_LauncherMenu = { Active = true, Page = "load" },
        ZM_SkyInspection = { IsActive = function(self) return self.State ~= nil end },
        ZM_LauncherProfessionPicker = { Tests = { cases = {} } },
        ZM_TestHarness = {
            NewSuite = function()
                local suite = { cases = {} }
                function suite:Add(name, body) self.cases[name] = body end
                state.presentationSuite = suite
                return suite
            end
        }
    }
    return server, client, state
end
