return function(contract)
    local state = {files = {}, hooks = {}, messages = {}, targetDepth = 0, renderCalls = 0}
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        return result
    end
    local env = {
        assert = assert, error = error, pairs = pairs, ipairs = ipairs, type = type,
        tostring = tostring, tonumber = tonumber, string = string, table = table,
        math = math, xpcall = xpcall, debug = debug, unpack = unpack,
        EF_NOSHADOW = 1, IMAGE_FORMAT_RGB888 = 2, RT_SIZE_LITERAL = 8, MATERIAL_RT_DEPTH_SEPARATE = 1
    }
    env.Vector = function(x, y, z) return {x = x, y = y, z = z} end
    env.Matrix = function()
        return {
            SetScale = function(self, value) self.scale = value end,
            SetTranslation = function(self, value) self.translation = value end
        }
    end
    env.Angle = function(p, y, r) return {p = p, y = y, r = r} end
    env.bit = {bor = function(a, b) return a + b end}
    env.RealTime = function() return state.now or 10 end
    env.os = {time = function() return 1000 end}
    env.include = function(path) assert(path == "world_capture/sh_contract.lua"); return contract end
    env.IsValid = function(entity) return type(entity) == "table" and not entity.invalid end
    local playerEntity = {noDraw = false, shadow = false}
    function playerEntity:GetNoDraw() return self.noDraw end
    function playerEntity:SetNoDraw(value) self.noDraw = value end
    function playerEntity:IsEffectActive() return self.shadow end
    function playerEntity:AddEffects() self.shadow = true end
    function playerEntity:RemoveEffects() self.shadow = false end
    function playerEntity:IsPlayer() return true end
    function playerEntity:IsNPC() return false end
    function playerEntity:IsWeapon() return false end
    function playerEntity:GetClass() return "player" end
    function playerEntity:GetNWInt(key) return key == "CellX" and 0 or 0 end
    function playerEntity:GetNWString() return "" end
    env.LocalPlayer = function() return playerEntity end
    env.ents = {GetAll = function() return {playerEntity} end}
    local casing, limb = copy(playerEntity), copy(playerEntity)
    casing.IsPlayer, limb.IsPlayer = function() return false end, function() return false end
    state.transients = {casing, limb}
    env.ZM_GoreClient = {Limbs = {{entity = limb}}}
    env.ZM_WeaponEffects = {GetWorldCaptureEntities = function() return {casing} end}
    env.game = {GetMap = function() return "recipe" end}
    local world = {profileId = "preview", mapManifestSha256 = string.rep("a", 64),
        templatePlanSha256 = string.rep("b", 64),
        cellBounds = {revision = 2, neighbourPitch = 5760, playableCeiling = 4608}}
    state.skyline = {profile = "preview", templatePlanSha256 = world.templatePlanSha256,
        cellSpan = 5760, cellBounds = {revision = 2}, cameraOrigin = {0, 0, 5120}}
    state.skyline.scale, state.skyline.cameraVector = 16, env.Vector(0, 0, 5120)
    env.ZM_Skybox = {
        CoastMeshes = {}, GetPlayableCeiling = function() return 4992 end,
        GetManifest = function() return state.skyline end,
        DrawCoast = function(_, color, matrix)
            state.coastDraws = (state.coastDraws or 0) + 1
            state.coastMatrix = copy(matrix)
            assert(color[1] == 128 and env.ZM_WorldCapture.Rendering)
        end
    }
    env.ZM_World = {ActiveProfile = "preview"}
    function env.ZM_World:GetData() return {world = world} end
    function env.ZM_World:IsLoaded() return true end
    function env.ZM_World:GetCellById(id)
        if id == 1 then return {id = 1, x = 0, y = 12, map = "recipe", atmosphereProfile = 0} end
    end
    function env.ZM_World:GetWorldCoordinates() return 0, 0 end
    env.ZM_WorldMap = {Capturing = false}
    env.ZM_Atmosphere = {MapCaptureParticlesHidden = false, WeatherSynced = true, ActiveProfileIndex = 0}
    function env.ZM_Atmosphere:BeginWorldCaptureFog(variant)
        local previous = self.variant
        self.variant = variant
        return {previous = previous}
    end
    function env.ZM_Atmosphere:EndWorldCaptureFog(token) self.variant = token.previous end
    function env.ZM_Atmosphere:SetMapCaptureHidden(value) self.MapCaptureParticlesHidden = value end
    function env.ZM_Atmosphere:GetMapCaptureState() return "clear/0/settled" end
    function env.ZM_Atmosphere:GetFogSettings() return {color = {128, 128, 128}} end
    env.GetRenderTargetEx = function() return {name = "capture"} end
    env.render = {
        PushRenderTarget = function() state.targetDepth = state.targetDepth + 1 end,
        PopRenderTarget = function() state.targetDepth = state.targetDepth - 1 end,
        Clear = function() if state.clearFailure then error("clear failed") end end,
        RenderView = function(view)
            state.renderCalls = state.renderCalls + 1
            state.view = copy(view)
            assert(env.ZM_WorldMap.Capturing and playerEntity.noDraw and env.ZM_Atmosphere.MapCaptureParticlesHidden)
            assert(casing.noDraw and limb.noDraw, "owner-tracked transients must be hidden")
            state.hooks.PostDrawOpaqueRenderables(false, false, false)
            if state.renderFailure then error("render failed") end
        end,
        Capture = function() return state.png end,
        CapturePixels = function() assert(state.camera2D == 1) end,
        ReadPixel = function(x, y)
            if state.pixelFailure then error("pixel read failed") end
            if state.blankPixels then return 0, 0, 0 end
            return x % 256, y % 256, (x + y) % 256
        end
    }
    env.cam = {
        Start2D = function() state.camera2D = (state.camera2D or 0) + 1 end,
        End2D = function() state.camera2D = state.camera2D - 1 end
    }
    env.util = {
        SHA256 = function(raw) return type(raw) == "table" and string.rep("c", 64) or "hash:" .. raw end,
        TableToJSON = copy, JSONToTable = copy
    }
    env.file = {
        CreateDir = function(path) assert(path:match("^zombiesim/world_captures/")) end,
        Write = function(path, raw) if not state.writeFailure then state.files[path] = raw end end,
        Read = function(path, realm)
            if realm == "GAME" then assert(path == "data_static/zombiesim_skybox_preview.json"); return state.skyline end
            assert(realm == "DATA"); return state.files[path]
        end
    }
    env.net = {
        Receive = function(name, callback) state.messages[name] = callback end,
        Start = function(name) state.lastMessage = name end,
        WriteString = function(result) state.reply = result end,
        SendToServer = function() state.sent = true end,
        ReadString = function() return state.request end
    }
    env.gui = {IsGameUIVisible = function() return state.menu == true end}
    env.ZM_LoadingScreen = {IsHidingHud = function() return state.loading == true end}
    env.hook = {
        Add = function(name, _, callback) state.hooks[name] = callback end,
        Remove = function(name, id)
            assert(name == "PreDrawSkyBox" and id == "ZM.WorldCapture.HideSkyRoom")
            state.hooks[name] = nil
        end
    }
    local function bytes(value)
        return string.char(math.floor(value / 16777216) % 256, math.floor(value / 65536) % 256,
            math.floor(value / 256) % 256, value % 256)
    end
    state.png = "\137PNG\r\n\26\n" .. bytes(13) .. "IHDR" .. bytes(1024) .. bytes(1024)
        .. string.rep("\0", 9) .. bytes(0) .. "IEND" .. bytes(0)
    state.player, state.world = playerEntity, world
    state.request = {runId = "test_1", token = "one", variant = "clear",
        revision = contract.Revision(world, "preview", state.skyline, string.rep("c", 64)),
        cell = {id = 1, x = 0, y = 12, map = "recipe"}}
    return env, state
end
