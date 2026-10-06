// Development-only bridge from a mounted command file to the server console.
ZM_DevConsole = ZM_DevConsole or {}
local DevConsole = ZM_DevConsole
// Commands run synchronously by the bridge so their DevConsole:Report output reaches the result file.
DevConsole.DirectCommands = DevConsole.DirectCommands or {}
local atmosphereStatusPath = "zombiesim/atmosphere_status.json"
local nextAtmosphereStatusRequestId = 0
local writeJson

// Bridge-only: game.ConsoleCommand blocks lua_run, so death-path tests need a direct kill.
DevConsole.DirectCommands.zombiesim_dev_kill_player = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:Alive() then
        return false, "no living player to kill"
    end
    target:Kill()
    return true
end

DevConsole.DirectCommands.zombiesim_dev_character_slots = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then
        return false, "character slot inspection requires a connected admin"
    end

    local characters = {}
    for slot = 1, 3 do
        local character, characterError = ZM_CharacterService:GetOwnedCharacter(target, slot)
        if characterError then
            return false, characterError
        end
        if character then
            table.insert(characters, {
                slot = slot,
                name = character.name,
                level = tonumber(character.level) or 1,
                appearanceRequired = tonumber(character.appearanceRequired) == 1,
                originCellX = tonumber(character.originCellX),
                originCellY = tonumber(character.originCellY)
            })
        end
    end

    DevConsole:Report("characterSlots", characters)
    print(string.format("[ZombieSim] Found %d existing preview character slot(s).", #characters))
    return true
end

DevConsole.DirectCommands.zombiesim_dev_deploy_character = function(argumentString)
    local target = ZM_Util.FirstHuman()
    local slot = tonumber(string.Trim(argumentString or ""))
    if not IsValid(target) or not target:IsAdmin() then
        return false, "character deployment requires a connected admin"
    end
    if ZM_World.ActiveProfile ~= "preview" or not ZM_World.LauncherMapProfiles[game.GetMap()] then
        return false, "character deployment is restricted to the preview launcher"
    end
    if not slot or slot ~= math.floor(slot) or slot < 1 or slot > 3 then
        return false, "usage: zombiesim_dev_deploy_character <slot 1-3>"
    end

    local deployed, deployError = ZM_Launcher:Select(target, slot)
    if not deployed then
        return false, deployError or "character deployment failed"
    end
    print(string.format("[ZombieSim] Deploying preview character from slot %d.", slot))
    return true
end

DevConsole.DirectCommands.zombiesim_dev_atmosphere_status = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then
        return false, "atmosphere diagnostics require a connected admin"
    end
    if ZM_World.ActiveProfile ~= "preview" then
        return false, "atmosphere diagnostics are restricted to the preview profile"
    end

    nextAtmosphereStatusRequestId = (nextAtmosphereStatusRequestId % 65535) + 1
    target.ZM_DevAtmosphereStatusRequestId = nextAtmosphereStatusRequestId
    target.ZM_DevAtmosphereStatusMap = game.GetMap()
    net.Start("ZM.AtmosphereStatus.Request")
        net.WriteUInt(nextAtmosphereStatusRequestId, 16)
    net.Send(target)
    print("[ZombieSim] Requested client atmosphere status.")
    return true
end

net.Receive("ZM.AtmosphereStatus.Result", function(_, target)
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return
    end

    local requestId = net.ReadUInt(16)
    local encoded = net.ReadString()
    if requestId ~= target.ZM_DevAtmosphereStatusRequestId or
        target.ZM_DevAtmosphereStatusMap ~= game.GetMap() then
        return
    end
    if #encoded > 16384 then
        ErrorNoHalt("[ZombieSim] Atmosphere status report exceeded 16 KiB.\n")
        return
    end

    local clientStatus = util.JSONToTable(encoded)
    if type(clientStatus) ~= "table" or clientStatus.map ~= game.GetMap() then
        ErrorNoHalt("[ZombieSim] Atmosphere status report was invalid or from another map.\n")
        return
    end

    writeJson(atmosphereStatusPath, {
        requestId = requestId,
        receivedAt = os.time(),
        map = game.GetMap(),
        activeProfile = ZM_World.ActiveProfile,
        client = clientStatus
    })
    target.ZM_DevAtmosphereStatusRequestId = nil
    target.ZM_DevAtmosphereStatusMap = nil
    print("[ZombieSim] Client atmosphere status saved to data/" .. atmosphereStatusPath)
end)

// Bridge-only: starts the client hook profiler; the client writes data/zombiesim/hook_profile.json when it ends.
DevConsole.DirectCommands.zombiesim_dev_profile_client = function(argumentString)
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then
        return false, "client profiling requires a connected admin"
    end
    if ZM_World.ActiveProfile ~= "preview" then
        return false, "client profiling is restricted to the preview profile"
    end
    local seconds = math.Clamp(math.floor(tonumber(argumentString) or 15), 1, 120)
    target:ConCommand("zombiesim_dev_profile_hooks " .. seconds)
    print(string.format("[ZombieSim] Requested a %d s client hook profile.", seconds))
    return true
end

DevConsole.DirectCommands.zombiesim_dev_test_clothing_pool = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "Clothing pool tests require a connected preview admin"
    end

    target:ConCommand("zombiesim_dev_test_clothing_pool")
    return true
end

DevConsole.DirectCommands.zombiesim_dev_sky_palette = function(argumentString)
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "individual sky previews require a connected preview admin"
    end
    local id = string.Trim(argumentString or "")
    if not id:match("^[a-z_]+$") then return false, "expected an individual sky id or restore" end
    local valid = { restore = true, mounted_day = true }
    for _, palette in ipairs({ "natural", "cinematic" }) do
        for _, context in ipairs({ "day", "dusk", "night", "overcast" }) do valid[palette .. "_" .. context] = true end
    end
    if not valid[id] then return false, "unknown individual sky id" end
    target:ConCommand("zombiesim_dev_sky_palette " .. id)
    return true
end

DevConsole.DirectCommands.zombiesim_dev_test_sky_palettes = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "sky palette tests require a connected preview admin"
    end
    target:ConCommand("zombiesim_dev_test_sky_palettes")
    return true
end

DevConsole.DirectCommands.zombiesim_dev_test_sky_browser = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "sky browser tests require a connected preview admin"
    end

    target:ConCommand("zombiesim_dev_test_sky_browser")
    return true
end

DevConsole.DirectCommands.zombiesim_dev_test_sky_catalogue = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "sky catalogue tests require a connected preview admin"
    end
    target:ConCommand("zombiesim_dev_test_sky_catalogue")
    return true
end

DevConsole.DirectCommands.zombiesim_dev_clothing_meshes = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "Clothing mesh inspection requires a connected preview admin"
    end
    target:ConCommand("zombiesim_dev_clothing_meshes")
    return true
end

DevConsole.DirectCommands.zombiesim_dev_wardrobe = function(argumentString)
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "Wardrobe requires a connected preview admin"
    end
    local argument = string.Trim(argumentString or "")
    local itemId = string.match(argument, "^select (item[%w]+)$")
    local citizenSex, citizenNumber = string.match(argument, "^model (%a+)_(%d%d)$")
    citizenNumber = tonumber(citizenNumber)
    local citizenModel = (citizenSex == "male" or citizenSex == "female") and citizenNumber and
        citizenNumber >= 1 and citizenNumber <= (citizenSex == "male" and 9 or 6)
    local definition = itemId and ZM_Items:GetDefinition(itemId)
    if argument ~= "" and argument ~= "close" and argument ~= "model male" and argument ~= "model female" and
        not citizenModel and not (definition and definition.clothing) then
        return false, "usage: zombiesim_dev_wardrobe [close|model male|female|male_01..09|female_01..06|select itemId]"
    end
    target:ConCommand("zombiesim_dev_wardrobe " .. argument)
    return true
end

DevConsole.DirectCommands.zombiesim_dev_ui = function(argumentString)
    local target = ZM_Util.FirstHuman()
    local mode = string.Trim(argumentString or "")
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "UI inspection requires a connected preview admin"
    end
    if mode ~= "inventory" and mode ~= "scoreboard" and mode ~= "wardrobe" and mode ~= "options" and
        mode ~= "sky" and mode ~= "sky_edit" and mode ~= "tools" and mode ~= "close" then
        return false, "usage: zombiesim_dev_ui inventory|scoreboard|wardrobe|options|sky|sky_edit|close"
    end

    DevConsole.DirectCommands.zombiesim_dev_test_launcher_tools = function()
        local target = ZM_Util.FirstHuman()
        if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" or
            game.GetMap() ~= "zn_preview_start" then
            return false, "Tools tests require a preview launcher admin"
        end
        target:ConCommand("zombiesim_dev_test_launcher_tools")
        return true
    end
    target:ConCommand("zombiesim_dev_ui " .. mode)
    return true
end

DevConsole.DirectCommands.zombiesim_dev_capture = function(argumentString)
    local target = ZM_Util.FirstHuman()
    local arguments = string.Explode(" ", string.Trim(argumentString or ""), false)
    local label = arguments[1]
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "screenshot capture requires a connected preview admin"
    end

    local usage = "usage: zombiesim_dev_capture <label: letters, numbers, underscore or hyphen; max 48> [pitch yaw [x y z]]"
    if (#arguments ~= 1 and #arguments ~= 3 and #arguments ~= 6) or
        not label or #label > 48 or not string.match(label, "^[%w_-]+$") then
        return false, usage
    end
    local view = ""
    if #arguments > 1 then
        local numbers = {}
        for index = 2, #arguments do
            local value = tonumber(arguments[index])
            if not value or value ~= value or math.abs(value) > 32768 then return false, usage end
            numbers[index] = value
        end
        local pitch, yaw = numbers[2], numbers[3]
        view = string.format(" %.2f %.2f", math.Clamp(pitch, -89, 89), yaw)
        if #arguments == 6 then view = view .. string.format(" %.3f %.3f %.3f", numbers[4], numbers[5], numbers[6]) end
    end
    target:ConCommand("zombiesim_dev_capture " .. label .. view)
    print("[ZombieSim] Requested client screenshot " .. label .. ".")
    return true
end

DevConsole.DirectCommands.zombiesim_dev_skybox_activity = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "skyline activity preview requires a connected preview admin"
    end
    target:ConCommand("zombiesim_dev_skybox_activity")
    return true
end

// Bridge-only: the client runs the cardinal edge regression and writes data/zombiesim/skybox_edges.json.
DevConsole.DirectCommands.zombiesim_dev_skybox_edges = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        return false, "skybox edge regression requires a connected preview admin"
    end
    target:ConCommand("zombiesim_dev_skybox_edges")
    return true
end

// Bridge-only: moves the first player to a raw grid cell through the normal world-map transition.
DevConsole.DirectCommands.zombiesim_dev_teleport_cell = function(argumentString)
    local gridX, gridY = string.match(argumentString or "", "^(%-?%d+)%s+(%-?%d+)$")
    local target = ZM_Util.FirstHuman()
    local cell = gridX and ZM_World:GetCell(tonumber(gridX), tonumber(gridY)) or nil
    if not IsValid(target) or not cell then
        return false, "usage: zombiesim_dev_teleport_cell <gridX> <gridY> with a connected player"
    end
    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
    local positioned, positionError = target:SetWorldCell(worldX, worldY)
    if not positioned then
        return false, positionError
    end
    if not GAMEMODE:EnsurePlayerWorldMap(target) then
        return false, "the player is already on that cell's map or a transition is queued"
    end
    return true
end

local function previewAdmin()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then
        return nil, "requires a connected admin"
    end
    if ZM_World.ActiveProfile ~= "preview" then
        return nil, "restricted to the preview profile"
    end
    return target
end

DevConsole.DirectCommands.zombiesim_dev_sign = function(argumentString)
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    local arguments = string.Explode(" ", string.Trim(argumentString or ""), false)
    local action, variant = arguments[1], arguments[2] or "freestanding"
    if (action ~= "on" and action ~= "off") or #arguments > 2 then
        return false, "usage: zombiesim_dev_sign on [freestanding|panel|illuminated|wall|print|poster] or off"
    end
    if action == "off" then
        if IsValid(target.ZM_DevSign) then target.ZM_DevSign:Remove() end
        target.ZM_DevSign = nil
        return true, "billboard preview removed"
    end
    if not target:Alive() or target.ZM_PersistentStateLoaded ~= true or ZM_World.LauncherMapProfiles[game.GetMap()] then
        return false, "deploy a living survivor before previewing the billboard"
    end
    local catalog = util.JSONToTable(file.Read("data_static/zombiesim_signs_preview.json", "GAME") or "")
    local entry = catalog and catalog.schemaVersion == 1 and catalog.variants and catalog.variants[variant]
    if not entry or type(entry.model) ~= "string" then
        return false, "unknown variant or missing sign catalog; build sign assets first"
    end
    local model = entry.model
    local wallMounted = entry.wallMounted == true
    if not util.IsValidModel(model) then
        return false, "billboard model is unavailable; run bin/build_sign_assets.ps1 first"
    end
    local origin, direction = target:GetLevelAim()
    local ahead = util.TraceLine({
        start = origin, endpos = origin + direction * 320,
        filter = { target, target.ZM_DevSign }, mask = MASK_NPCSOLID_BRUSHONLY
    })
    local ground = util.TraceLine({
        start = ahead.HitPos - direction * 32,
        endpos = ahead.HitPos - direction * 32 - Vector(0, 0, 512),
        filter = target, mask = MASK_NPCSOLID_BRUSHONLY
    })
    if not wallMounted and (not ground.Hit or ground.HitNormal.z < 0.7) then
        return false, "no level ground for the billboard; face an open floor and retry"
    end
    if wallMounted and (not ahead.Hit or math.abs(ahead.HitNormal.z) > 0.2) then
        return false, "face a vertical wall within 320 units to preview the wall-mounted sign"
    end
    local entity = ents.Create("prop_dynamic")
    if not IsValid(entity) then return false, "could not create billboard preview" end
    entity:SetModel(model)
    if wallMounted then
        entity:SetPos(ahead.HitPos + ahead.HitNormal * 0.5)
        entity:SetAngles(Angle(0, ahead.HitNormal:Angle().y + 90, 0))
    else
        entity:SetPos(ground.HitPos + Vector(0, 0, variant == "panel" and 96 or 2))
        entity:SetAngles(Angle(0, (target:GetPos() - entity:GetPos()):Angle().y + 90, 0))
    end
    entity:Spawn()
    entity:Activate()
    entity:SetSolid(SOLID_NONE)
    entity:SetNotSolid(true)
    local lamp
    if entry.light then
        local light = entry.light
        if type(light.origin) ~= "table" or type(light.angles) ~= "table" or
            #light.origin ~= 3 or #light.angles ~= 3 or type(light.color) ~= "string" or
            type(light.fov) ~= "number" or light.fov <= 0 or light.fov > 170 or
            type(light.farZ) ~= "number" or light.farZ <= 1 or light.farZ > 512 then
            entity:Remove()
            return false, "invalid generated lamp placement"
        end
        for index = 1, 3 do
            if type(light.origin[index]) ~= "number" or type(light.angles[index]) ~= "number" or
                light.origin[index] ~= light.origin[index] or light.angles[index] ~= light.angles[index] or
                math.abs(light.origin[index]) > 512 or math.abs(light.angles[index]) > 360 then
                entity:Remove()
                return false, "invalid generated lamp transform"
            end
        end
        lamp = ents.Create("env_projectedtexture")
        if not IsValid(lamp) then
            entity:Remove()
            return false, "could not create the billboard preview light"
        end
        local position, angles = LocalToWorld(Vector(unpack(light.origin)), Angle(unpack(light.angles)),
            entity:GetPos(), entity:GetAngles())
        lamp:SetPos(position)
        lamp:SetAngles(angles)
        lamp:SetKeyValue("lightcolor", light.color)
        lamp:SetKeyValue("lightfov", tostring(light.fov))
        lamp:SetKeyValue("nearz", "1")
        lamp:SetKeyValue("farz", tostring(light.farZ))
        lamp:SetKeyValue("enableshadows", "0")
        lamp:SetKeyValue("lightworld", "1")
        lamp:SetKeyValue("spawnflags", "1")
        lamp:Spawn()
        lamp:Activate()
        entity:DeleteOnRemove(lamp)
    end
    if IsValid(target.ZM_DevSign) then target.ZM_DevSign:Remove() end
    target.ZM_DevSign = entity
    timer.Simple(180, function() if IsValid(entity) then entity:Remove() end end)
    DevConsole:Report("signPreview", {
        model = entity:GetModel(), materials = entity:GetMaterials(), variant = variant,
        projectedLight = IsValid(lamp),
        lightModel = IsValid(lamp) and lamp:GetModel() or nil,
        lightAngles = IsValid(lamp) and { lamp:GetAngles().p, lamp:GetAngles().y, lamp:GetAngles().r } or nil,
        origin = { x = entity:GetPos().x, y = entity:GetPos().y, z = entity:GetPos().z },
        yaw = entity:GetAngles().y, expiresIn = 180
    })
    return true, "original billboard preview created; non-solid and removed after 180 seconds"
end

local function removeClothingProbe(entities)
    for _, entity in ipairs(entities or {}) do
        if IsValid(entity) then entity:Remove() end
    end
end

DevConsole.DirectCommands.zombiesim_dev_clothing_model = function(argumentString)
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    if not target:Alive() or not target.ZM_PersistentStateLoaded then return false, "deploy a living survivor first" end
    local mode = string.Trim(argumentString or "")
    local models = { male = "models/player/group01/male_03.mdl", female = "models/player/group01/female_01.mdl",
        unsupported = "models/player/group03/male_01.mdl" }
    if mode ~= "restore" and not models[mode] then
        return false, "usage: zombiesim_dev_clothing_model male|female|unsupported|restore"
    end
    local characterKey = ZM_Util.CharacterKeyFor(target)
    if target.ZM_DevClothingModel and target.ZM_DevClothingModel.characterKey ~= characterKey then
        target.ZM_DevClothingModel = nil
        return false, "character changed; discarded the previous temporary model record"
    end
    if mode == "restore" then
        local saved = target.ZM_DevClothingModel
        if not saved then return false, "no temporary clothing-model change to restore" end
        target:SetModel(saved.model)
        target:SetSkin(saved.skin)
        for group, value in pairs(saved.bodygroups) do target:SetBodygroup(group, value) end
        target.ZM_DevClothingModel = nil
    else
        if not target.ZM_DevClothingModel then
            local saved = { model = target:GetModel(), skin = target:GetSkin(), bodygroups = {}, characterKey = characterKey }
            for group = 0, target:GetNumBodyGroups() - 1 do saved.bodygroups[group] = target:GetBodygroup(group) end
            target.ZM_DevClothingModel = saved
        end
        target:SetModel(models[mode])
        target:SetSkin(0)
        for group = 0, target:GetNumBodyGroups() - 1 do target:SetBodygroup(group, 0) end
    end
    local hands = target:GetHands()
    if IsValid(hands) then GAMEMODE:PlayerSetHandsModel(target, hands) end
    DevConsole:Report("clothingModel", { model = target:GetModel(), temporary = target.ZM_DevClothingModel ~= nil,
        persistedAppearanceChanged = false })
    return true
end

DevConsole.DirectCommands.zombiesim_dev_clothing_uv = function(argumentString)
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    local arguments = string.Explode(" ", string.Trim(argumentString or ""), false)
    local action, variant = arguments[1], arguments[2] or "current"
    local finish = arguments[3] or "uv"
    local style = arguments[4] or "base"
    local styles = { base = true, chest = true, chest_left = true, chest_right = true, arm_left = true, arm_right = true,
        back_small = true, front_full = true, back_full = true, ["repeat"] = true, pants_leg = true, pants_leg_right = true,
        pants_cuff = true, pants_cuff_right = true, pants_cuff_both = true, pants_back_left = true, pants_back_right = true,
        arm_back_left = true, arm_back_right = true, sleeve_cuff = true, sleeve_cuff_right = true, sleeve_cuff_both = true }
    local legStyle = string.match(style, "^pants_") ~= nil
    if (action ~= "on" and action ~= "off") or #arguments > 4 or not styles[style] or
        (style ~= "base" and style ~= "repeat" and not legStyle and finish ~= "shirt" and finish ~= "both") or
        (legStyle and finish ~= "pants" and finish ~= "both") or
        (style == "repeat" and finish == "uv") or
        (finish ~= "uv" and finish ~= "shirt" and finish ~= "pants" and finish ~= "both") or
        (variant ~= "current" and variant ~= "male" and variant ~= "female") then
        return false, "usage: zombiesim_dev_clothing_uv on [current|male|female] [uv|shirt|pants|both] [base|chest|chest_left|chest_right|arm_left|arm_right|back_small|front_full|back_full|repeat|pants_leg|pants_leg_right|pants_cuff|pants_cuff_right|pants_cuff_both|pants_back_left|pants_back_right|arm_back_left|arm_back_right|sleeve_cuff|sleeve_cuff_right|sleeve_cuff_both] or off"
    end
    if action == "off" then
        removeClothingProbe(target.ZM_DevClothingProbe)
        target.ZM_DevClothingProbe = nil
        return true, "clothing UV fixtures removed"
    end
    if not target:Alive() or target.ZM_PersistentStateLoaded ~= true or ZM_World.LauncherMapProfiles[game.GetMap()] then
        return false, "deploy a living survivor before previewing clothing UVs"
    end
    local model = variant == "current" and target:GetModel() or "models/player/group01/" .. variant .. "_01.mdl"
    if finish ~= "uv" then
        model = variant == "male" and "models/player/group01/male_03.mdl" or model
        if model ~= "models/player/group01/male_03.mdl" and model ~= "models/player/group01/female_01.mdl" then
            return false, "finish prototype supports male_03 and female_01 only; use male or female explicitly"
        end
        local sex = model == "models/player/group01/male_03.mdl" and "male" or "female"
        local shirt = "shirt_" .. sex .. (style ~= "base" and not legStyle and "_" .. style or "")
        local pants = legStyle and "pants_" .. sex .. "_" .. style or "pants" .. (style == "repeat" and "_repeat" or "")
        local required = finish == "shirt" and { shirt } or finish == "pants" and { pants } or { shirt, pants }
        for _, garment in ipairs(required) do
            if not file.Exists("materials/models/zombiesim/clothing/prototype_" .. garment .. ".vtf", "GAME") then
                return false, "prototype artwork is missing; run bin/build_clothing_prototype.ps1"
            end
        end
    end
    if not table.HasValue(ZM_CharacterRules.Models, model) or not util.IsValidModel(model) then
        return false, "clothing UV preview requires an available allowlisted citizen model"
    end
    local material = "models/zombiesim/clothing/uv_probe"
    if not file.Exists("materials/" .. material .. ".vmt", "GAME") or not file.Exists("materials/" .. material .. ".vtf", "GAME") then
        return false, "UV probe material is missing; run bin/build_clothing_uv_probe.ps1"
    end
    local _, aim = target:GetLevelAim()
    local forward = Vector(aim.x, aim.y, 0)
    if forward:LengthSqr() < 0.01 then return false, "aim toward open level ground, not straight up or down" end
    forward:Normalize()
    local right = forward:Angle():Right()
    local filter = { target }
    table.Add(filter, target.ZM_DevClothingProbe or {})
    local function findPosition(position)
        local floor = util.TraceLine({
            start = position + Vector(0, 0, 48), endpos = position - Vector(0, 0, 128),
            filter = filter, mask = MASK_NPCSOLID
        })
        if not floor.Hit or floor.StartSolid or floor.HitNormal.z < 0.7 then
            return nil
        end
        position = floor.HitPos + Vector(0, 0, 2)
        local clearance = util.TraceHull({
            start = position, endpos = position, mins = Vector(-20, -20, 1), maxs = Vector(20, 20, 76),
            filter = filter, mask = MASK_NPCSOLID
        })
        if clearance.Hit or clearance.StartSolid then return nil end
        return position
    end
    local positions
    for _, distance in ipairs({ 144, 256, 368 }) do
        for _, offset in ipairs({ 0, -160, 160 }) do
            local center = target:GetPos() + forward * distance + right * offset
            local pair = { findPosition(center - right * 64), findPosition(center + right * 64) }
            local clear = pair[1] ~= nil and pair[2] ~= nil
            if clear then
                local yaw = (target:GetPos() - pair[2]):Angle().y
                for _, camera in ipairs({ Vector(112, 0, 46), Vector(-112, 0, 46), Vector(0, 112, 46), Vector(0, -112, 46) }) do
                    local origin = LocalToWorld(camera, Angle(), pair[2], Angle(0, yaw, 0))
                    local trace = util.TraceLine({
                        start = pair[2] + Vector(0, 0, 38), endpos = origin, filter = filter, mask = MASK_NPCSOLID
                    })
                    if trace.Hit or trace.StartSolid then clear = false break end
                end
            end
            if clear then positions = pair break end
        end
        if positions then break end
    end
    if not positions then return false, "no clear fixture/camera area nearby; face open level ground and retry" end
    local fixtures, records = {}, {}
    for index = 1, 2 do
        local entity = ents.Create("prop_dynamic")
        if not IsValid(entity) then
            removeClothingProbe(fixtures)
            return false, "could not create clothing UV fixture"
        end
        fixtures[index] = entity
        entity:SetModel(model)
        entity:SetPos(positions[index])
        entity:SetAngles(Angle(0, (target:GetPos() - positions[index]):Angle().y, 0))
        entity:Spawn()
        entity:Activate()
        entity:SetSolid(SOLID_NONE)
        entity:SetNotSolid(true)
        local bodySlot
        for slot, path in ipairs(entity:GetMaterials()) do
            if string.lower(path):match("^models/humans/[a-z]+/group01/players_sheet$") then
                if bodySlot ~= nil then
                    removeClothingProbe(fixtures)
                    return false, "ambiguous clothing body material on preview model"
                end
                bodySlot = slot - 1
            end
        end
        if bodySlot == nil then
            removeClothingProbe(fixtures)
            return false, "preview model has no verified group01 clothing body material"
        end
        if index == 2 then
            if finish == "uv" then entity:SetSubMaterial(bodySlot, material)
            else
                entity:SetNWString("ZM_DevClothingFinish", finish)
                entity:SetNWString("ZM_DevClothingStyle", style)
            end
        end
        target:DeleteOnRemove(entity)
        records[index] = {
            entityIndex = entity:EntIndex(), model = model, bodySlot = bodySlot,
            checker = index == 2 and finish == "uv", finish = index == 2 and finish or "stock",
            style = index == 2 and style or "stock", override = entity:GetSubMaterial(bodySlot),
            position = { x = positions[index].x, y = positions[index].y, z = positions[index].z }
        }
    end
    removeClothingProbe(target.ZM_DevClothingProbe)
    target.ZM_DevClothingProbe = fixtures
    timer.Simple(300, function() removeClothingProbe(fixtures) end)
    DevConsole:Report("clothingUvPreview", { fixtures = records, expiresIn = 300 })
    return true, "two non-solid clothing fixtures created: stock and " .. finish .. " preview; expire after 300 seconds"
end

DevConsole.DirectCommands.zombiesim_dev_clothing_capture = function(argumentString)
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    local arguments = string.Explode(" ", string.Trim(argumentString or ""), false)
    local label, view = arguments[1], arguments[2]
    local offsets = {
        front = Vector(112, 0, 46), back = Vector(-112, 0, 46),
        left = Vector(0, 112, 46), right = Vector(0, -112, 46), neckline = Vector(48, 0, 57)
    }
    if #arguments ~= 2 or not offsets[view] or not label or #label > 48 or not label:match("^[%w_-]+$") then
        return false, "usage: zombiesim_dev_clothing_capture <label> <front|back|left|right|neckline>"
    end
    local fixtures = target.ZM_DevClothingProbe
    local entity = fixtures and fixtures[2]
    if not IsValid(entity) then return false, "create clothing UV fixtures before capturing them" end
    local origin = entity:LocalToWorld(offsets[view])
    local focus = entity:GetPos() + Vector(0, 0, view == "neckline" and 55 or 38)
    local trace = util.TraceLine({ start = focus, endpos = origin, filter = { target, entity }, mask = MASK_NPCSOLID })
    if trace.Hit or trace.StartSolid then return false, "an obstacle blocks this clothing camera angle; reposition the fixtures" end
    local angles = (focus - origin):Angle()
    return DevConsole.DirectCommands.zombiesim_dev_capture(string.format("%s %.3f %.3f %.3f %.3f %.3f",
        label, angles.p, angles.y, origin.x, origin.y, origin.z))
end

// Bridge-only: uses a cell transition gate through the normal gate service, as if the player pressed Use.
DevConsole.DirectCommands.zombiesim_dev_use_gate = function(argumentString)
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    local directionNames = { N = "north", E = "east", S = "south", W = "west" }
    local directionName = directionNames[string.upper(string.Trim(argumentString or ""))]
    if not directionName then
        return false, "usage: zombiesim_dev_use_gate <N|E|S|W>"
    end
    for _, entity in ipairs(ents.FindByClass("trigger_multiple")) do
        if entity:GetNWBool("ZMTransitionGate", false) and entity:GetNWString("ZMTransitionDirection", "") == directionName then
            ZM_Transitions:TryUseGate(target, entity)
            return true, string.format("used %s gate; exit sequence active: %s", directionName,
                tostring(ZM_Transitions:IsExitSequenceActive()))
        end
    end
    return false, "no " .. directionName .. " transition gate on this map"
end

// Bridge-only: reports every transition gate, the nearest gate, the transition guard and neighbour availability.
DevConsole.DirectCommands.zombiesim_dev_gate_report = function()
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    local function vectorTable(value) return { value.x, value.y, value.z } end
    local canTransition, guardError = ZM_Transitions:CheckDoorTransition(target)
    local nearest = ZM_Transitions:FindNearbyGate(target)
    local report = {
        map = game.GetMap(),
        player = vectorTable(target:GetPos()),
        cell = { target:GetWorldCellCoordinates() },
        guard = { ok = canTransition, reason = guardError },
        flags = {
            worldMapQueued = GAMEMODE.PlayerWorldMapTransitionQueued == true,
            originQueued = GAMEMODE.OriginSafeZoneTransitionQueued == true,
            mapBatch = ZM_MapBatch and ZM_MapBatch:IsActive() or false,
            exitSequence = ZM_Transitions:IsExitSequenceActive(),
            stateLoaded = target.ZM_PersistentStateLoaded == true
        },
        nearbyGate = IsValid(nearest) and nearest:GetNWString("ZMTransitionDirection", "") or nil,
        neighbours = {},
        neighbourMaps = {},
        gates = {}
    }
    for _, code in ipairs({ "N", "E", "S", "W" }) do
        for _, mode in ipairs({ "any", "road", "highway" }) do
            local cellOk = target:CanTravelToNeighbour(code, mode, false)
            report.neighbours[code .. "_" .. mode] = cellOk and true or false
            if cellOk and mode == "any" then
                report.neighbourMaps[code] = tostring(ZM_World:GetMapPath(cellOk))
            end
        end
    end
    for _, entity in ipairs(ents.FindByClass("trigger_multiple")) do
        local keys = entity:GetKeyValues()
        local name = entity:GetName() or ""
        if entity:GetNWBool("ZMTransitionGate", false) or string.find(name, "transition", 1, true) or keys.zm_transition_gate then
            local mins, maxs = entity:WorldSpaceAABB()
            table.insert(report.gates, {
                name = name,
                direction = entity:GetNWString("ZMTransitionDirection", ""),
                published = entity:GetNWBool("ZMTransitionGate", false),
                keyDirection = tostring(keys.zm_transition_direction or ""),
                mode = tostring(keys.zm_transition_mode or ""),
                boundsMin = vectorTable(mins),
                boundsMax = vectorTable(maxs),
                distance = target:GetPos():Distance(entity:NearestPoint(target:GetPos()))
            })
        end
    end
    DevConsole:Report("gateReport", report)
    return true
end

// Bridge-only: reports live safe-zone door/arrival entities and the first player's pose for placement diagnosis.
DevConsole.DirectCommands.zombiesim_dev_door_report = function()
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    local function vectorTable(value) return { value.x, value.y, value.z } end
    local report = {
        map = game.GetMap(),
        player = { position = vectorTable(target:GetPos()), eyeAngles = vectorTable(Vector(target:EyeAngles().p, target:EyeAngles().y, 0)) },
        entities = {},
        published = {}
    }
    for index = 1, GetGlobal2Int("ZMSafeZoneDoorCount", 0) do
        table.insert(report.published, {
            role = GetGlobal2String("ZMSafeZoneDoorRole_" .. index, ""),
            position = vectorTable(GetGlobal2Vector("ZMSafeZoneDoor_" .. index, vector_origin))
        })
    end
    for _, className in ipairs({ "zn_safezone_door", "zn_safezone_arrival" }) do
        for _, entity in ipairs(ents.FindByClass(className)) do
            local mins, maxs = entity:WorldSpaceAABB()
            table.insert(report.entities, {
                class = className,
                index = entity:EntIndex(),
                role = (ZM_SafeZoneDoors:GetDoorDetails(entity)),
                position = vectorTable(entity:GetPos()),
                yaw = entity:GetAngles().y,
                boundsMin = vectorTable(mins),
                boundsMax = vectorTable(maxs),
                distance = target:GetPos():Distance(entity:GetPos())
            })
        end
    end
    DevConsole:Report("doorReport", report)
    return true
end

// Bridge-only: arms a movement trace for the first seconds after the next map load. The arm file survives the
// level change; the trace is written to DATA zombiesim/arrival_trace.json.
local arrivalTraceArmPath = "zombiesim/arrival_trace.arm.txt"
local arrivalTracePath = "zombiesim/arrival_trace.json"
local arrivalTraceSeconds = 4
DevConsole.DirectCommands.zombiesim_dev_trace_arrival = function()
    local _, targetError = previewAdmin()
    if targetError then return false, targetError end
    file.CreateDir("zombiesim")
    file.Write(arrivalTraceArmPath, "1")
    file.Write("zombiesim/arrival_trace_client.arm.txt", "1")
    file.Delete(arrivalTracePath)
    file.Delete("zombiesim/arrival_trace_client.json")
    return true, "arrival trace armed for the next map load"
end

local arrivalTrace
if file.Exists(arrivalTraceArmPath, "DATA") then
    file.Delete(arrivalTraceArmPath)
    arrivalTrace = { map = game.GetMap(), samples = {} }
end

hook.Add("StartCommand", "ZM.DevArrivalTrace", function(playerEntity, cmd)
    local trace = arrivalTrace
    if not trace or playerEntity:IsBot() then return end
    trace.startedAt = trace.startedAt or CurTime()
    trace.realStartedAt = trace.realStartedAt or SysTime()
    local elapsed = CurTime() - trace.startedAt
    if elapsed > arrivalTraceSeconds then
        arrivalTrace = nil
        writeJson(arrivalTracePath, trace)
        return
    end
    local velocity = playerEntity:GetVelocity()
    table.insert(trace.samples, {
        t = math.Round(elapsed, 3),
        real = math.Round(SysTime() - trace.realStartedAt, 3),
        command = cmd:CommandNumber(),
        tick = cmd:TickCount(),
        forced = cmd:IsForced(),
        buttons = cmd:GetButtons(),
        forwardMove = cmd:GetForwardMove(),
        sideMove = cmd:GetSideMove(),
        speed = math.Round(Vector(velocity.x, velocity.y, 0):Length(), 1),
        frozen = playerEntity:IsFrozen(),
        flags = playerEntity:GetFlags(),
        moveType = playerEntity:GetMoveType(),
        walkSpeed = playerEntity:GetWalkSpeed(),
        maxSpeed = playerEntity:GetMaxSpeed(),
        loaded = playerEntity.ZM_PersistentStateLoaded == true,
        entryWalk = playerEntity.ZM_TransitionEntry ~= nil,
        stamina = tonumber(playerEntity.Stamina)
    })
end)

// Bridge-only: uses this map's safe-zone door (enter or exit) through the normal door service.
DevConsole.DirectCommands.zombiesim_dev_use_door = function()
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    for _, entity in ipairs(ents.FindByClass("zn_safezone_door")) do
        local role = ZM_SafeZoneDoors:GetDoorDetails(entity)
        if role then
            ZM_SafeZoneDoors:TryUseDoor(target, entity)
            return true, string.format("used %s door; exit sequence active: %s", role,
                tostring(ZM_Transitions:IsExitSequenceActive()))
        end
    end
    return false, "no safe-zone door on this map"
end

// Bridge-only: cancels an active gate/door exit sequence to exercise view, input, and state recovery.
DevConsole.DirectCommands.zombiesim_dev_cancel_transition = function()
    local target, targetError = previewAdmin()
    if not target then return false, targetError end
    if not ZM_Transitions:CancelExitSequence("Transition cancelled.") then
        return false, "no active exit sequence"
    end
    return true
end

DevConsole.DirectCommands.zombiesim_dev_spawn_boss = function(argumentString)
    local target = ZM_Util.FirstHuman()
    local bossId = string.Trim(argumentString or "")
    if not IsValid(target) or bossId == "" then
        return false, "usage: zombiesim_dev_spawn_boss <bossId>"
    end
    local instance, entityOrError = ZM_Bosses:SpawnForPlayer(target, bossId)
    if not instance then return false, entityOrError end
    return true, string.format("spawned boss %s instance %d", bossId, instance.id)
end

DevConsole.DirectCommands.zombiesim_dev_kill_boss = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) then return false, "no connected player" end
    local profileState = ZM_Bosses.Profiles[ZM_World.ActiveProfile]
    for _, instance in pairs(profileState and profileState.active or {}) do
        if IsValid(instance.entity) then
            local damage = DamageInfo()
            damage:SetDamage(999999)
            damage:SetAttacker(target)
            damage:SetInflictor(target)
            instance.entity:OnKilled(damage)
            return true, string.format("killed boss instance %d", instance.id)
        end
    end
    return false, "no active boss"
end

local inputPath = "data_static/consolecommands.txt"
local outputPath = "zombiesim/consolecommands.result.json"
local statePath = "zombiesim/consolecommands.state.json"
local heartbeatPath = "zombiesim/consolecommands.heartbeat.json"
local bridgeLoadedAt = os.time()
local pollInterval = 0.25

util.AddNetworkString("ZM.AtmosphereStatus.Request")
util.AddNetworkString("ZM.AtmosphereStatus.Result")

CreateConVar(
    "zombiesim_dev_console_enabled",
    game.IsDedicated() and "0" or "1",
    FCVAR_ARCHIVE,
    "Allows the development console command file to run server commands."
)

local function isEnabled()
    local convar = GetConVar("zombiesim_dev_console_enabled")
    return convar and convar:GetBool() or false
end

local function readState()
    local json = file.Read(statePath, "DATA")
    local state = json and util.JSONToTable(json) or nil
    return type(state) == "table" and state or {}
end

writeJson = function(path, value)
    file.CreateDir("zombiesim")
    file.Write(path, util.TableToJSON(value, true) or "{}")
end

local function writeResult(result)
    writeJson(outputPath, result)
end

function DevConsole:WritePlayerHydration(snapshot)
    writeJson("zombiesim/player_hydration.json", snapshot)
end

local function parseRequest(contents)
    if #contents > 32768 then
        return nil, "Command file exceeds 32 KiB"
    end

    local requestId
    local commands = {}
    for line in string.gmatch(contents:gsub("\r", ""), "[^\n]+") do
        line = string.Trim(line)
        local declaredId = string.match(line, "^#%s*[Rr]equest%s*:%s*(.-)%s*$")
        if declaredId then
            requestId = declaredId
        elseif line ~= "" and not string.StartWith(line, "#") and not string.StartWith(line, "//") then
            if #line > 1024 then
                return nil, "A command exceeds 1024 characters"
            end
            if string.find(line, ";", 1, true) then
                return nil, "Only one command is allowed per line"
            end
            table.insert(commands, line)
        end
    end

    if requestId == nil and #commands == 0 then
        return nil
    end
    if type(requestId) ~= "string" or not string.match(requestId, "^[%w_.%-]+$") then
        return nil, "Add a unique '# request: identifier' line"
    end
    if #commands == 0 then
        return nil, "No commands were supplied"
    end
    if #commands > 16 then
        return nil, "A request may contain at most 16 commands"
    end
    return { id = requestId, commands = commands }
end

function DevConsole:Report(name, value)
    if not self.CurrentResult then
        return false
    end

    self.CurrentResult.reports[name] = value
    return true
end

local function findPlayer(steamId)
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and not playerEntity:IsBot() and playerEntity:SteamID() == steamId then
            return playerEntity
        end
    end
end

local function firstHumanSteamId()
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and not playerEntity:IsBot() then
            return playerEntity:SteamID()
        end
    end
end

local function runtimeSnapshot(playerEntity)
    if not IsValid(playerEntity) then
        return nil
    end

    local cell, cellError = playerEntity:GetWorldCell()
    local radiationIntensity = cell and ZM_World:GetRadiationIntensity(cell) or nil
    local radiationElapsedSeconds = type(playerEntity.RadiationEnteredAt) == "number"
        and math.max(CurTime() - playerEntity.RadiationEnteredAt, 0)
        or nil

    return {
        persistentStateLoaded = playerEntity.ZM_PersistentStateLoaded == true,
        previouslyConnected = playerEntity.PreviouslyConnected == true,
        cellX = playerEntity.CellX,
        cellY = playerEntity.CellY,
        currentSafeZoneId = playerEntity.CurrentSafeZoneId,
        alive = playerEntity:Alive(),
        currentHealth = playerEntity:Health(),
        skillPoints = playerEntity.SkillPoints,
        health = playerEntity.SavedHealth,
        stamina = playerEntity.Stamina,
        movement = ZM_Movement.Snapshot(playerEntity),
        hunger = playerEntity.Hunger,
        thirst = playerEntity.Thirst,
        worldCellId = cell and cell.id or nil,
        worldCellError = cellError,
        radiationIntensity = radiationIntensity,
        radiationHealthFloor = playerEntity:GetRadiationHealthFloor(),
        radiationProtected = playerEntity:HasRadiationProtection(),
        radiationProximity = playerEntity:GetNWFloat("ZM_RadiatedProximity", 0),
        radiationDisplayedSv = ZM_RadiationFeedback.DisplaySv(radiationIntensity or 0,
            playerEntity:GetNWFloat("ZM_RadiatedProximity", 0)),
        radiationAcute = playerEntity.RadiationAcute == true,
        radiationEffectiveHealthFloor = playerEntity.RadiationAcute and 0 or playerEntity:GetRadiationHealthFloor(),
        networkRadiationIntensity = playerEntity:GetNWFloat("RadiationIntensity", 0),
        radiationCellId = playerEntity.RadiationCellId,
        radiationEnteredAt = playerEntity.RadiationEnteredAt,
        radiationElapsedSeconds = radiationElapsedSeconds,
        radiationNextDamageAt = playerEntity.RadiationNextDamageAt,
        radiationSecondsUntilDamage = type(playerEntity.RadiationNextDamageAt) == "number"
            and math.max(playerEntity.RadiationNextDamageAt - CurTime(), 0)
            or nil
    }
end

local function collectPersistenceReport(steamId)
    steamId = steamId or firstHumanSteamId()
    if type(steamId) ~= "string" or not string.match(steamId, "^STEAM_%d+:%d+:%d+$") then
        return nil, "Persistence report requires a SteamID or an active human player"
    end

    local cityKey, cityKeyError = ZM_CharacterService:GetCharacterKeyForSteamID(steamId, "city")
    local previewKey, previewKeyError = ZM_CharacterService:GetCharacterKeyForSteamID(steamId, "preview")
    local cityData, cityDataError
    local previewData, previewDataError
    local cityAttributes, cityAttributesError
    local previewAttributes, previewAttributesError
    if cityKey then
        cityData, cityDataError = ZM_GetPlayerData(cityKey, "city")
        cityAttributes, cityAttributesError = ZM_GetPlayerAttributes(cityKey, "city")
    else
        cityDataError, cityAttributesError = cityKeyError, cityKeyError
    end
    if previewKey then
        previewData, previewDataError = ZM_GetPlayerData(previewKey, "preview")
        previewAttributes, previewAttributesError = ZM_GetPlayerAttributes(previewKey, "preview")
    else
        previewDataError, previewAttributesError = previewKeyError, previewKeyError
    end
    local activePlayer = findPlayer(steamId)
    return {
        steamId = steamId,
        map = game.GetMap(),
        activeProfile = ZM_World and ZM_World.ActiveProfile or nil,
        selectedProfile = GetConVar("zombiesim_world_profile") and GetConVar("zombiesim_world_profile"):GetString() or nil,
        city = { characterId = cityKey, playerData = cityData, attributes = cityAttributes, error = cityDataError or cityAttributesError },
        preview = { characterId = previewKey, playerData = previewData, attributes = previewAttributes, error = previewDataError or previewAttributesError },
        runtime = runtimeSnapshot(activePlayer)
    }
end

local function runPersistenceReport(steamId)
    local report, reportError = collectPersistenceReport(steamId)
    if not report then
        print("[ZombieSim] " .. reportError .. ".")
        return false, reportError
    end

    DevConsole:Report("persistence", report)
    print(string.format(
        "[ZombieSim] Persistence report: %s; profile %s; preview row %s; runtime skill points %s",
        steamId,
        tostring(report.activeProfile),
        report.preview.playerData and "present" or "missing",
        tostring(report.runtime and report.runtime.skillPoints or "unavailable")
    ))
    return true
end

local scriptValidationDirectories = {
    "gamemodes/zombiesim/gamemode",
    "gamemodes/zombiesim/gamemode/utils",
    "gamemodes/zombiesim/entities/entities/zn_walker_zombie"
}

local function collectScriptPaths()
    local paths = {}
    for _, directory in ipairs(scriptValidationDirectories) do
        local files = file.Find(directory .. "/*.lua", "GAME")
        table.sort(files)
        for _, filename in ipairs(files) do
            table.insert(paths, directory .. "/" .. filename)
        end
    end
    return paths
end

local function runScriptValidation()
    local report = { checked = 0, passed = 0, failed = 0, files = {} }
    for _, path in ipairs(collectScriptPaths()) do
        report.checked = report.checked + 1
        local source = file.Read(path, "GAME")
        local compiled = source and CompileString(source, "@" .. path, false) or "Could not read source from the GAME mount"
        local valid = type(compiled) == "function"
        if valid then
            report.passed = report.passed + 1
        else
            report.failed = report.failed + 1
        end
        table.insert(report.files, {
            path = path,
            valid = valid,
            error = valid and nil or tostring(compiled)
        })
    end

    DevConsole:Report("scriptValidation", report)
    for _, fileResult in ipairs(report.files) do
        if not fileResult.valid then
            print("[ZombieSim] GLua syntax error in " .. fileResult.path .. ": " .. fileResult.error)
        end
    end
    print(string.format("[ZombieSim] GLua syntax validation: %d passed, %d failed.", report.passed, report.failed))
    return report.failed == 0, report.failed > 0 and "GLua syntax validation failed" or nil
end

concommand.Add("zombiesim_dev_persistence_report", function(_, _, arguments)
    runPersistenceReport(arguments[1])
end)

concommand.Add("zombiesim_validate_scripts", function(ply)
    if not ZM_Util.RequireAdmin(ply, "zombiesim_validate_scripts") then return end
    runScriptValidation()
end)

local function dispatchCommand(command)
    local persistenceSteamId = string.match(command, "^zombiesim_dev_persistence_report%s*(.-)%s*$")
    if persistenceSteamId then
        if persistenceSteamId == "" then
            persistenceSteamId = nil
        end
        return runPersistenceReport(persistenceSteamId)
    end

    if string.match(command, "^zombiesim_validate_scripts%s*$") then
        return runScriptValidation()
    end

    local commandName, commandArguments = string.match(command, "^(%S+)%s*(.-)%s*$")
    local directCommand = commandName and DevConsole.DirectCommands[commandName] or nil
    if directCommand then
        return directCommand(commandArguments)
    end

    game.ConsoleCommand(command .. "\n")
    return true
end

local lastFingerprint
local nextPollAt = 0
local nextHeartbeatAt = 0
hook.Add("Think", "ZombieSim.DevelopmentConsoleBridge", function()
    if CurTime() < nextPollAt then
        return
    end
    nextPollAt = CurTime() + pollInterval

    if not isEnabled() then
        return
    end

    // Server Think stops while singleplayer is paused or loading; a stale heartbeat tells external tooling why
    // a request is not being acknowledged.
    if RealTime() >= nextHeartbeatAt then
        nextHeartbeatAt = RealTime() + 1
        writeJson(heartbeatPath, { map = game.GetMap(), writtenAt = os.time(), loadedAt = bridgeLoadedAt })
    end

    local contents = file.Read(inputPath, "GAME")
    if not contents then
        return
    end

    local fingerprint = util.CRC(contents)
    if fingerprint == lastFingerprint then
        return
    end
    lastFingerprint = fingerprint

    local request, requestError = parseRequest(contents)
    if not request then
        if requestError then
            writeResult({
                ok = false,
                error = requestError,
                map = game.GetMap(),
                processedAt = os.time()
            })
        end
        return
    end

    local state = readState()
    if state.lastRequestId == request.id then
        return
    end

    local result = {
        ok = true,
        requestId = request.id,
        map = game.GetMap(),
        activeProfile = ZM_World and ZM_World.ActiveProfile or nil,
        processedAt = os.time(),
        commands = request.commands,
        commandResults = {},
        reports = {}
    }
    DevConsole.CurrentResult = result
    for _, command in ipairs(request.commands) do
        local dispatched, dispatchError = dispatchCommand(command)
        table.insert(result.commandResults, {
            command = command,
            dispatched = dispatched,
            error = dispatchError
        })
        if not dispatched then
            result.ok = false
        end
    end
    DevConsole.CurrentResult = nil

    state.lastRequestId = request.id
    state.lastFingerprint = fingerprint
    state.completedAt = result.processedAt
    writeJson(statePath, state)
    writeResult(result)
    print("[ZombieSim] Development console request completed: " .. request.id)
end)