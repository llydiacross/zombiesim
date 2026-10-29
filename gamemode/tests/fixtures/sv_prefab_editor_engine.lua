return function(contract, createStorage, createStorageEngine, createLoot)
    local storageEngine = createStorageEngine()
    local state = {
        map = "zn_preview_start", profile = "preview", humans = {}, callbacks = {}, hooks = {},
        commands = {}, errors = {}, mounted = true, responses = {}, referenceModels = {}
    }
    local env = {
        type = type, tostring = tostring, string = string, table = table, ipairs = ipairs,
        pairs = pairs, math = math, assert = assert, MASK_SOLID_BRUSHONLY = 1
    }
    env.Vector = function(x, y, z) return { x = x, y = y, z = z } end
    env.IsValid = function(entity) return type(entity) == "table" and entity.valid ~= false end
    env.ZM_World = { ActiveProfile = "preview" }
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
            assert(path == "maps/gm_flatgrass.bsp" or path == "maps/zn_dev_prefab_anchor.bsp")
            return state.mounted
        end
        local find = env.file.Find
        env.file.Find = function(pattern, realm)
            if pattern == "models/zombiesim/prefab_tile_preview/*.mdl" then
                assert(realm == "GAME")
                return state.referenceModels, {}
            end
            return find(pattern, realm)
        end
        return exists(path, realm)
    end
    env.util = storageEngine.json
    env.util.IsValidModel = function(model)
        return model == "models/props_c17/oildrum001.mdl"
            or model == "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
    end
    env.util.AddNetworkString = function(name) assert(type(name) == "string") end
    env.util.TraceLine = function(request)
        state.trace = request
        return { Hit = state.flat ~= false, HitSky = false, StartSolid = false,
            HitNormal = env.Vector(0, 0, 1), HitPos = env.Vector(3072, 3072, -12288) }
    end
    env.include = function(path)
        if path == "prefabs/sh_contract.lua" then return contract end
        if path == "prefabs/sv_loot.lua" then return createLoot end
        assert(path == "prefabs/sv_storage.lua")
        return createStorage
    end
    env.player = { GetHumans = function() return state.humans end }
    env.ZM_Util = {
        RegisterCommands = function(_, callback) state.statusCommand = callback end,
        ResolveCommandTarget = function() return state.target end,
        Reply = function(_, message) state.reply = message end
    }
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
    function state:Request(action, text, openedId, caller)
        self.input, self.inputIndex = { action, text or "", openedId or "" }, 1
        self.callbacks["ZM.PrefabEditorRequest"](0, caller or self.target)
        return self.responses[#self.responses]
    end
    return env, state
end
