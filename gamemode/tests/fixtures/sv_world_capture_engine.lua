return function(contract)
    local state = {files = {}, now = 100, map = "recipe_0", callbacks = {}, hooks = {}, commands = {}}
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        return result
    end
    local env = {
        assert = assert, error = error, pairs = pairs, ipairs = ipairs, type = type,
        tostring = tostring, tonumber = tonumber, string = string, table = table,
        math = math, xpcall = xpcall, pcall = pcall, debug = debug, unpack = unpack, MOVETYPE_NONE = 0
    }
    env.SysTime = function() return state.now / 10 end
    env.RealTime = function() return state.now end
    env.os = {time = function() return state.now end}
    env.Vector = function(x, y, z)
        return {x = x, y = y, z = z, DistToSqr = function(a, b)
            return (a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2
        end}
    end
    env.Angle = function(p, y, r) return {p = p, y = y, r = r} end
    env.AddCSLuaFile = function(path) assert(path == "world_capture/sh_contract.lua") end
    env.AddOriginToPVS = function(position) state.pvs = position end
    env.include = function(path) assert(path == "world_capture/sh_contract.lua"); return contract end
    env.IsValid = function(entity) return type(entity) == "table" and not entity.invalid end
    env.GAMEMODE = {}
    env.util = {
        TableToJSON = copy, JSONToTable = copy, AddNetworkString = function(name) state.callbacks[name] = false end,
        SHA256 = function(raw) return type(raw) == "table" and string.rep("c", 64) or "hash:" .. raw end,
        CRC = function() return "123" end
    }
    env.file = {
        CreateDir = function(path) assert(path:match("^zombiesim")) end,
        Read = function(path, realm)
            if realm == "GAME" then assert(path == "data_static/zombiesim_skybox_preview.json"); return state.skyline end
            assert(realm == "DATA"); return state.files[path]
        end,
        Write = function(path, raw) state.files[path] = raw end,
        Exists = function(path, realm)
            assert(realm == "GAME")
            if path:match("%.bsp$") then return true end
            return state.navFile == true
        end
    }
    local playerEntity = {
        ZM_PersistentStateLoaded = true, XP = 50, Level = 2, MaxLevel = 300, Difficulty = 1,
        CellX = 0, CellY = 0, SkillPoints = 10, Cash = 25, SavedHealth = 90,
        Stamina = 99, Hunger = 98, Thirst = 97, Job = "Civilian", health = 90,
        position = env.Vector(20, 30, 40), angles = env.Angle(0, 90, 0), frozen = false, moveType = 2
    }
    function playerEntity:GetCharacterKey() return "character_1" end
    function playerEntity:SteamID64() return "steam_1" end
    function playerEntity:IsAdmin() return true end
    function playerEntity:Alive() return true end
    function playerEntity:Health() return self.health end
    function playerEntity:SetHealth(value) self.health = value end
    function playerEntity:Freeze(value) self.frozen = value end
    function playerEntity:IsFrozen() return self.frozen end
    function playerEntity:GetMoveType() return self.moveType end
    function playerEntity:SetMoveType(value) self.moveType = value end
    function playerEntity:GetPos() return self.position end
    function playerEntity:SetPos(value) self.position = value end
    function playerEntity:EyeAngles() return self.angles end
    function playerEntity:SetEyeAngles(value) self.angles = value end
    function playerEntity:SetNetworkPlayerData() state.networked = true end
    function playerEntity:SendPlayerData() state.playerSent = true end
    function playerEntity:SetWorldCell(x, y)
        self.CellX, self.CellY, self.CurrentSafeZoneId = x, y, nil
        state.row.CellX, state.row.CellY, state.row.CurrentSafeZoneId = x, y, nil
        return true
    end
    local cells = {
        {id = 0, x = 0, y = 0, map = "recipe_0", atmosphereProfile = 0},
        {id = 1, x = 1, y = 0, map = "recipe_0", atmosphereProfile = 0},
        {id = 2, x = 0, y = 1, map = "recipe_2", atmosphereProfile = 0},
        {id = 3, x = 1, y = 1, map = "recipe_3", atmosphereProfile = 0}
    }
    function playerEntity:GetWorldCell() return cells[self.CellY * 2 + self.CellX + 1] end
    state.player = playerEntity
    state.row = {XP = "50", Level = "2", MaxLevel = "300", Difficulty = "1",
        CellX = "0", CellY = "0", SkillPoints = "10", Cash = "25", Health = "90",
        Stamina = "99", Hunger = "98", Thirst = "97", Job = "Civilian"}
    state.originalRow = copy(state.row)
    env.ZM_GetPlayerData = function(key, profile)
        assert(key == "character_1" and profile == "preview")
        return copy(state.row)
    end
    env.ZM_SetPlayerData = function(key, profile, data)
        assert(key == "character_1" and profile == "preview")
        state.row = copy(data)
        return true
    end
    env.player = {GetHumans = function() return state.extraHuman and {playerEntity, {}} or {playerEntity} end}
    state.world = {profileId = "preview", mapManifestSha256 = string.rep("a", 64),
        templatePlanSha256 = string.rep("b", 64),
        cellBounds = {revision = 2, neighbourPitch = 5760, playableCeiling = 4608}}
    state.skyline = {profile = "preview", templatePlanSha256 = state.world.templatePlanSha256,
        cellSpan = 5760, scale = 16, cellBounds = {revision = 2}, cameraOrigin = {0, 0, 5120}}
    env.ZM_World = {ActiveProfile = "preview", LauncherMapProfiles = {}}
    function env.ZM_World:IsLoaded() return true end
    function env.ZM_World:GetData() return {world = state.world, cells = cells} end
    function env.ZM_World:GetMapPath(cell) return cell and cell.map end
    function env.ZM_World:GetPlayerCurrentSafeZoneMap() return nil end
    function env.ZM_World:GetWorldCoordinates(cell) return cell.x, cell.y end
    function env.ZM_World:GetGridCoordinates(x, y) return x, y end
    function env.ZM_World:GetCell(x, y)
        if x < 0 or y < 0 or x > 1 or y > 1 then return nil end
        return cells[y * 2 + x + 1]
    end
    function env.ZM_World:GetCellById(id) return cells[id + 1] end
    env.game = {
        GetMap = function() return state.map end,
        ConsoleCommand = function(command) state.changelevel = command:match("^changelevel ([%w_%-]+)\n$") end
    }
    env.ZM_Util = {
        RegisterCommands = function(commands, runner)
            for name in pairs(commands) do state.commands[name] = function(arguments) return runner(nil, name, arguments or {}) end end
        end,
        RequireAdmin = function() return true end,
        ResolveCommandTarget = function() return playerEntity end,
        Print = function(_, message) state.status = message end
    }
    env.net = {
        Receive = function(name, callback) state.callbacks[name] = callback end,
        Start = function(name) state.netName = name end,
        WriteString = function(request) state.request = copy(request) end,
        Send = function(target) assert(target == playerEntity) end,
        ReadString = function() return state.result end
    }
    env.hook = {Add = function(name, _, callback) state.hooks[name] = callback end}
    env.timer = {Create = function(_, _, _, callback) state.tick = callback end}
    env.ZM_MapBatch = {IsActive = function() return state.navBatchActive == true end}
    function env.ZM_MapBatch:GetNavmeshStatus()
        return {generating = state.navGenerating == true, loaded = state.navFile == true,
            navFileExists = state.navFile == true, areaCount = state.navAreas or 0}
    end
    function env.ZM_MapBatch:AddNavmeshSpawnSeed() return env.Vector(0, 0, 0) end
    env.navmesh = {
        IsGenerating = function() return state.navGenerating == true end,
        BeginGeneration = function() state.navGenerating = true; state.navStarts = (state.navStarts or 0) + 1 end,
        Save = function() state.navFile = true; state.navSaves = (state.navSaves or 0) + 1 end
    }
    function state:Advance(seconds) self.now = self.now + (seconds or 1); self.tick() end
    function state:Reload(chunk)
        assert(self.changelevel, "no requested reload")
        self.map, self.changelevel, self.now = self.changelevel, nil, self.now + 1
        setfenv(chunk, env); chunk()
    end
    function state:Result(contract, overrides)
        local request = self.request
        local png = "\137PNG\r\n\26\n" .. string.char(0,0,0,13) .. "IHDR" .. string.char(0,0,4,0,0,0,4,0)
            .. string.rep("\0",9) .. string.char(0,0,0,0) .. "IEND" .. string.char(0,0,0,0)
        local path = contract.OutputPath(request.runId, request.cell.id, request.variant)
        self.files[path] = png
        self.result = {ok = true, runId = request.runId, token = request.token, cellId = request.cell.id,
            variant = request.variant, revision = request.revision, path = path, bytes = #png,
            sha256 = env.util.SHA256(png), ready = true, map = self.map}
        for key, value in pairs(overrides or {}) do self.result[key] = value end
        self.callbacks["ZM.WorldCapture.Result"](0, playerEntity)
    end
    return env, state
end
