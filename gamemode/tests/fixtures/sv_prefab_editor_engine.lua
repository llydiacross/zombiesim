return function(contract, createStorage, createStorageEngine, createLoot, createEditorMap)
    local storageEngine = createStorageEngine()
    local state = {
        map = "zn_preview_start", profile = "preview", humans = {}, callbacks = {}, hooks = {},
        commands = {}, errors = {}, mounted = true, responses = {}, referenceModels = {},
        mountedMaps = { gm_flatgrass = true, gm_construct = true, custom_map = true, zn_dev_prefab_anchor = true },
        mapFiles = { "gm_flatgrass.bsp", "gm_construct.bsp", "custom_map.bsp", "zz_preview_test.bsp" }
    }
    local env = {
        type = type, tostring = tostring, tonumber = tonumber, string = string, table = table, ipairs = ipairs,
        pairs = pairs, math = math, assert = assert, MASK_SOLID_BRUSHONLY = 1, MASK_SOLID = 2
    }
    env.Vector = function(x, y, z) return { x = x, y = y, z = z } end
    env.IsValid = function(entity) return type(entity) == "table" and entity.valid ~= false end
    env.ZM_World = {
        ActiveProfile = "preview",
        IsLoaded = function() return state.worldLoaded ~= false end,
        GetUniqueProfileForMap = function(_, name) return state.profileMaps and state.profileMaps[name] end,
        GetCellsForMap = function(_, name) return state.worldCells and state.worldCells[name] or nil end,
        GetData = function() return { safeZones = state.safeZones or {}, cells = state.cells or {} } end,
        GetCellById = function(_, id)
            for _, cell in ipairs(state.cells or {}) do if cell.id == id then return cell end end
        end,
        GetGridCoordinates = function(_, x, y) return x, y end,
        GetCell = function(_, x, y)
            for _, cell in ipairs(state.cells or {}) do
                if cell.worldX == x and cell.worldY == y then return cell end
            end
        end,
        GetMapPath = function(_, cell) return cell and cell.map end,
        GetWorldCoordinates = function(_, cell) return cell.worldX, cell.worldY end,
        GetCellBounds = function() return { tileSize = 640, coreTileGridSize = 5, playableCeiling = 4608 } end,
        LoadProfile = function(self, profile) self.ActiveProfile = profile; state.worldLoaded = true; return true end
    }
    env.ZM_SafeZones = { GetMap = function(_, id) return state.safeZoneMaps and state.safeZoneMaps[id] end }
    env.ZM_PrefabGuardConfig = { ValidateDocument = function(document)
        if state.guardError and #document.guards > 0 then return false, state.guardError end
        return true
    end }
    env.ZM_PrefabGuardWeapons = { List = function()
        if state.guardWeaponError then return nil, state.guardWeaponError end
        return { { id = "pistol", label = "9mm Handgun", model = "models/weapons/w_pistol.mdl",
            damage = 12, spread = 0.02, delay = 0.2, range = 3000 } }
    end }
    env.ZM_StaticData = {
        GetLootGroup = function(_, id) if id == "lootFixture" then return { entries = { { item = "fixture" } } } end end,
        GetEntityLootRule = function() return nil end
    }
    env.ZM_ItemGeneration = { NewInstanceId = function()
        state.nextPropId = (state.nextPropId or 0) + 1
        return "test" .. state.nextPropId
    end }
    env.GAMEMODE = {}
    env.file = storageEngine.files
    local exists = env.file.Exists
    env.file.Exists = function(path, realm)
        if realm == "GAME" then
            local name = string.match(path, "^maps/(.+)%.bsp$")
            assert(name)
            return state.mounted and state.mountedMaps[name] == true
        end
        return exists(path, realm)
    end
    local find = env.file.Find
    env.file.Find = function(pattern, realm)
        if pattern == "models/zombiesim/prefab_tile_preview/*.mdl" then
            assert(realm == "GAME")
            return state.referenceModels, {}
        end
        if pattern == "maps/*.bsp" then
            assert(realm == "GAME")
            return state.mapFiles, {}
        end
        return find(pattern, realm)
    end
    env.util = storageEngine.json
    env.util.IsValidModel = function(model)
        return model == "models/props_c17/oildrum001.mdl"
            or model == "models/player/group01/male_03.mdl"
            or model == "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
    end
    env.util.AddNetworkString = function(name) assert(type(name) == "string") end
    env.util.TraceLine = function(request)
        state.trace = request
        if request.mask == env.MASK_SOLID then
            return { Hit = state.flat ~= false, HitSky = state.sky == true, StartSolid = state.startSolid == true,
                HitNormal = env.Vector(0, 0, state.normalZ or 1),
                HitPos = env.Vector(request.start.x, request.start.y, state.cellHeight or 32) }
        end
        return { Hit = state.flat ~= false, HitSky = false, StartSolid = false,
            HitNormal = env.Vector(0, 0, 1), HitPos = env.Vector(3072, 3072, -12288) }
    end
    env.include = function(path)
        if path == "prefabs/sh_contract.lua" then return contract end
        if path == "prefabs/sh_editor_map.lua" then return createEditorMap end
        if path == "prefabs/sv_loot.lua" then return createLoot end
        if path == "prefabs/sh_particle_catalog.lua" then
            return function()
                return { Load = function()
                    return { { id = "steam", label = "Steam", particleFile = "particles/train_steam.pcf",
                        particleSystem = "steam_train", sound = "ambient/gas/steam_loop1.wav" } }
                end, Validate = function(document)
                    for _, particle in ipairs(document.particles) do
                        if particle.effect ~= "steam" then return false, "Unknown prefab particle effect." end
                    end
                    return true
                end }
            end
        end
        assert(path == "prefabs/sv_storage.lua")
        return createStorage
    end
    env.player = { GetHumans = function() return state.humans end }
    env.ZM_Util = {
        RegisterCommands = function(_, callback) state.statusCommand = callback end,
        ResolveCommandTarget = function() return state.target end,
        Reply = function(_, message) state.reply = message end
    }
    env.ZM_DevConsole = { Report = function(_, name, value) state.report = { name = name, value = value } end }
    env.ents = {
        FindByClass = function(class)
            assert(class == "info_player_start")
            return { { GetPos = function() return env.Vector(0, 0, -12287) end } }
        end
    }
    env.hook = { Add = function(event, name, callback) state.hooks[name] = callback end }
    env.AddOriginToPVS = function(position) state.pvs = position end
    env.game = {
        GetMap = function() return state.map end,
        ConsoleCommand = function(command) state.commands[#state.commands + 1] = command end
    }
    env.ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end
    env.net = {
        Receive = function(name, callback) state.callbacks[name] = callback end,
        ReadString = function()
            local value = state.input[state.inputIndex]
            state.inputIndex = state.inputIndex + 1
            return value
        end,
        Start = function(name) state.response = { name = name, values = {} } end,
        WriteString = function(value) state.response.values[#state.response.values + 1] = value end,
        WriteBool = function(value) state.response.values[#state.response.values + 1] = value end,
        Send = function(target)
            state.response.target = target
            state.responses[#state.responses + 1] = state.response
        end
    }
    local target = { admin = true, identity = "76561198000000000", ZM_LauncherState = "menu",
        survivor = { health = 87, cell = 12 } }
    function target:IsAdmin() return self.admin end
    function target:SteamID64() return self.identity end
    function target:StripWeapons() self.stripped = true end
    function target:Freeze(value) self.frozen = value end
    function target:GodEnable() self.god = true end
    function target:SetNoDraw(value) self.hidden = value end
    function target:SetNWBool(key, value) self[key] = value end
    function target:ChatPrint(message) self.message = message end
    state.target = target
    state.humans = { target }
    state.files = storageEngine.state.files
    state.storage = storageEngine.state
    function state:Request(action, text, openedId, caller, requestId)
        self.input, self.inputIndex = { action, text or "", openedId or "", requestId or "" }, 1
        self.callbacks["ZM.PrefabEditorRequest"](0, caller or self.target)
        return self.responses[#self.responses]
    end
    return env, state
end
