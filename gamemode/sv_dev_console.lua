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
        hunger = playerEntity.Hunger,
        thirst = playerEntity.Thirst,
        worldCellId = cell and cell.id or nil,
        worldCellError = cellError,
        radiationIntensity = radiationIntensity,
        radiationHealthFloor = playerEntity:GetRadiationHealthFloor(),
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