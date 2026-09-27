// Development-only bridge from a mounted command file to the server console.
ZM_DevConsole = ZM_DevConsole or {}
local DevConsole = ZM_DevConsole
// Commands run synchronously by the bridge so their DevConsole:Report output reaches the result file.
DevConsole.DirectCommands = DevConsole.DirectCommands or {}

// Bridge-only: game.ConsoleCommand blocks lua_run, so death-path tests need a direct kill.
DevConsole.DirectCommands.zombiesim_dev_kill_player = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:Alive() then
        return false, "no living player to kill"
    end
    target:Kill()
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
local pollInterval = 0.25

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

local function writeJson(path, value)
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

    local cityData, cityDataError = ZM_GetPlayerData(steamId, "city")
    local previewData, previewDataError = ZM_GetPlayerData(steamId, "preview")
    local cityAttributes, cityAttributesError = ZM_GetPlayerAttributes(steamId, "city")
    local previewAttributes, previewAttributesError = ZM_GetPlayerAttributes(steamId, "preview")
    local activePlayer = findPlayer(steamId)
    return {
        steamId = steamId,
        map = game.GetMap(),
        activeProfile = ZM_World and ZM_World.ActiveProfile or nil,
        selectedProfile = GetConVar("zombiesim_world_profile") and GetConVar("zombiesim_world_profile"):GetString() or nil,
        city = { playerData = cityData, attributes = cityAttributes, error = cityDataError or cityAttributesError },
        preview = { playerData = previewData, attributes = previewAttributes, error = previewDataError or previewAttributesError },
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
hook.Add("Think", "ZombieSim.DevelopmentConsoleBridge", function()
    if CurTime() < nextPollAt then
        return
    end
    nextPollAt = CurTime() + pollInterval

    if not isEnabled() then
        return
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