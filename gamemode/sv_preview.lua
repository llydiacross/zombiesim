// Server authority for preview-tool capabilities. Action handlers live here as they are added.
local Preview = ZM_Preview

CreateConVar(
    "zombiesim_preview_tools_enabled",
    game.IsDedicated() and "0" or "1",
    FCVAR_ARCHIVE + FCVAR_NOTIFY,
    "Enables ZombieSim preview tools on the preview world profile."
)

util.AddNetworkString("ZM.PreviewCapabilities")
util.AddNetworkString("ZM.RequestPreviewCapabilities")
util.AddNetworkString("ZM.RequestPreviewTeleport")
util.AddNetworkString("ZM.RequestPreviewDenTeleport")
util.AddNetworkString("ZM.PreviewTeleportStatus")
util.AddNetworkString("ZM.RequestPreviewCheat")
util.AddNetworkString("ZM.PreviewCheatStatus")
util.AddNetworkString("ZM.RequestPreviewData")
util.AddNetworkString("ZM.PreviewDataResponse")

Preview.TeleportCooldowns = Preview.TeleportCooldowns or {}
Preview.TeleportRequestId = Preview.TeleportRequestId or 0
Preview.TransitionLocked = false
Preview.CheatStates = Preview.CheatStates or {}

local function toolsAreEnabled()
    local convar = GetConVar("zombiesim_preview_tools_enabled")
    return convar and convar:GetBool() or false
end

function Preview:GetCapabilitiesFor(playerEntity)
    if not toolsAreEnabled() or not self:IsActive() or not IsValid(playerEntity) or not playerEntity:IsAdmin() then
        return 0
    end

    local capabilities = bit.bor(self.Capabilities.diagnostics, self.Capabilities.operator)
    if playerEntity:IsSuperAdmin() then
        capabilities = bit.bor(capabilities, self.Capabilities.dataAdmin)
    end
    return capabilities
end

function Preview:HasServerCapability(playerEntity, capability)
    capability = tonumber(capability) or 0
    return bit.band(self:GetCapabilitiesFor(playerEntity), capability) == capability
end

function Preview:SendCapabilities(playerEntity)
    if not IsValid(playerEntity) then
        return
    end

    net.Start("ZM.PreviewCapabilities")
        net.WriteUInt(self:GetCapabilitiesFor(playerEntity), 3)
        net.WriteString(self:IsActive() and "preview" or "")
    net.Send(playerEntity)
end

// Cheat toggles persist to DATA so they survive changelevel and cell transitions.
Preview.CheatToggles = { "god", "noclip", "notarget", "infiniteAmmo", "survivalLock" }
local cheatStatePath = "zombiesim/preview_cheats.json"

local function loadCheatStates()
    local stored = file.Exists(cheatStatePath, "DATA") and util.JSONToTable(file.Read(cheatStatePath, "DATA") or "") or nil
    return type(stored) == "table" and stored or {}
end

function Preview:SaveCheatStates()
    file.CreateDir("zombiesim")
    file.Write(cheatStatePath, util.TableToJSON(self.CheatStates, true) or "{}")
end

if not Preview.CheatStatesLoaded then
    Preview.CheatStates = loadCheatStates()
    Preview.CheatStatesLoaded = true
end

function Preview:GetCheatState(playerEntity)
    local steamId = IsValid(playerEntity) and playerEntity:SteamID() or nil
    if not steamId then
        return {}
    end

    local state = self.CheatStates[steamId]
    if type(state) ~= "table" then
        state = {}
        self.CheatStates[steamId] = state
    end
    for _, key in ipairs(self.CheatToggles) do
        state[key] = state[key] == true
    end
    return state
end

function Preview:SendCheatStatus(playerEntity, accepted, message)
    local state = self:GetCheatState(playerEntity)
    net.Start("ZM.PreviewCheatStatus")
        net.WriteBool(accepted == true)
        net.WriteString(message or "")
        for _, key in ipairs(self.CheatToggles) do
            net.WriteBool(state[key] == true)
        end
    net.Send(playerEntity)
end

function Preview:ApplyCheatState(playerEntity)
    if not IsValid(playerEntity) then
        return
    end

    // Persisted toggles only take effect while the player still holds preview operator rights.
    local allowed = self:HasServerCapability(playerEntity, self.Capabilities.operator)
    local state = self:GetCheatState(playerEntity)
    if allowed and state.god then
        playerEntity:GodEnable()
    else
        playerEntity:GodDisable()
    end
    if allowed and state.noclip then
        playerEntity:SetMoveType(MOVETYPE_NOCLIP)
    elseif playerEntity:GetMoveType() == MOVETYPE_NOCLIP then
        playerEntity:SetMoveType(MOVETYPE_WALK)
    end
    local notarget = allowed and state.notarget == true
    playerEntity.ZM_CheatNoTarget = notarget
    playerEntity:SetNoTarget(notarget)
    playerEntity.ZM_CheatInfiniteAmmo = allowed and state.infiniteAmmo == true
    playerEntity.ZM_CheatSurvivalLock = allowed and state.survivalLock == true
    playerEntity:SetNWBool("ZM_CheatGod", allowed and state.god == true)
end

// Keeps clips topped up and survival reserves full for players with those cheats.
local nextCheatMaintenanceAt = 0
hook.Add("Think", "ZM.Preview.CheatMaintenance", function()
    if CurTime() < nextCheatMaintenanceAt then return end
    nextCheatMaintenanceAt = CurTime() + 0.2

    for _, playerEntity in ipairs(player.GetHumans()) do
        if not playerEntity:Alive() then continue end
        if playerEntity.ZM_CheatInfiniteAmmo then
            local weapon = playerEntity:GetActiveWeapon()
            if IsValid(weapon) and weapon:GetMaxClip1() > 0 and weapon:Clip1() < weapon:GetMaxClip1() then
                weapon:SetClip1(weapon:GetMaxClip1())
            end
        end
        if playerEntity.ZM_CheatSurvivalLock and playerEntity.ZM_PersistentStateLoaded == true then
            playerEntity.Hunger = 100
            playerEntity.Thirst = 100
            playerEntity.Stamina = playerEntity:GetMaxStamina()
            playerEntity:SetNWFloat("Hunger", 100)
            playerEntity:SetNWFloat("Thirst", 100)
            playerEntity:SetNWFloat("Stamina", playerEntity.Stamina)
        end
    end
end)

net.Receive("ZM.RequestPreviewCapabilities", function(_, playerEntity)
    Preview:SendCapabilities(playerEntity)
end)

local function getHumanPlayerCount()
    local count = 0
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and not playerEntity:IsBot() then
            count = count + 1
        end
    end
    return count
end

local function sendTeleportStatus(playerEntity, requestId, accepted, message, cellId, mapPath)
    net.Start("ZM.PreviewTeleportStatus")
        net.WriteUInt(requestId, 16)
        net.WriteBool(accepted)
        net.WriteString(message or "")
        net.WriteUInt(math.max(0, tonumber(cellId) or 0), 16)
        net.WriteString(mapPath or "")
    net.Send(playerEntity)
end

local function nextTeleportRequestId()
    Preview.TeleportRequestId = Preview.TeleportRequestId % 65535 + 1
    return Preview.TeleportRequestId
end

local function getPreviewTeleportTarget(cellId)
    if not ZM_World or not ZM_World:IsLoaded() then
        return nil, "Preview world data is not loaded"
    end
    local worldData = ZM_World:GetData()
    local grid = worldData and worldData.world and worldData.world.grid or {}
    local maximumCellId = (tonumber(grid[1]) or 0) * (tonumber(grid[2]) or 0) - 1
    if cellId < 0 or cellId > maximumCellId then
        return nil, "Selected cell is outside the preview world"
    end

    local cell = ZM_World:GetCellById(cellId)
    local mapPath = cell and ZM_World:GetMapPath(cell) or nil
    if not cell or type(mapPath) ~= "string" or not string.match(mapPath, "^[%w_/%-]+$") then
        return nil, "Selected cell has no valid city map"
    end
    if not file.Exists("maps/" .. mapPath .. ".bsp", "GAME") then
        return nil, "Selected cell map is not staged in Garry's Mod"
    end

    return { cell = cell, mapPath = mapPath }
end

// Shared by the world-map request and the development bridge; both pass the same operator/transition guards.
function Preview:RequestCellTeleport(playerEntity, cellId)
    local requestId = nextTeleportRequestId()
    local function reject(message)
        sendTeleportStatus(playerEntity, requestId, false, message, cellId)
        return false, message
    end

    if not Preview:HasServerCapability(playerEntity, Preview.Capabilities.operator) then
        return reject("Preview teleport is unavailable")
    end
    if getHumanPlayerCount() ~= 1 then
        return reject("Preview teleport requires exactly one human player")
    end
    if ZM_MapBatch and ZM_MapBatch:IsActive() then
        return reject("Map maintenance is active")
    end
    if Preview.TransitionLocked then
        return reject("A preview transition is already pending")
    end

    local lastRequestAt = Preview.TeleportCooldowns[playerEntity:SteamID()] or 0
    if CurTime() - lastRequestAt < 1 then
        return reject("Preview teleport is cooling down")
    end

    local target, targetError = getPreviewTeleportTarget(cellId)
    if not target then
        return reject(targetError)
    end

    local profileConVar = GetConVar("zombiesim_world_profile")
    if profileConVar then
        profileConVar:SetString("preview")
    end

    local worldX, worldY = ZM_World:GetWorldCoordinates(target.cell)
    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        return reject(positionError or "Could not update player world position")
    end

    local targetMapName = string.lower(string.match(target.mapPath, "([^/]+)$") or target.mapPath)
    local currentMapName = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    if targetMapName == currentMapName then
        Preview.TeleportCooldowns[playerEntity:SteamID()] = CurTime()
        sendTeleportStatus(playerEntity, requestId, true, "Selected current preview cell", target.cell.id, target.mapPath)
        return true, "Selected current preview cell"
    end

    Preview.TeleportCooldowns[playerEntity:SteamID()] = CurTime()
    Preview.TransitionLocked = true
    local transitionQueued = GAMEMODE and GAMEMODE.EnsurePlayerWorldMap and GAMEMODE:EnsurePlayerWorldMap(playerEntity)
    if not transitionQueued then
        Preview.TransitionLocked = false
        return reject("Core world transition could not be queued")
    end

    sendTeleportStatus(playerEntity, requestId, true, "Loading selected preview cell", target.cell.id, target.mapPath)
    print(string.format("[ZombieSim] Preview teleport: %s -> %d,%d (%s)", playerEntity:SteamID(), worldX, worldY, target.mapPath))
    return true, "Loading selected preview cell"
end

net.Receive("ZM.RequestPreviewTeleport", function(_, playerEntity)
    Preview:RequestCellTeleport(playerEntity, net.ReadUInt(16))
end)

hook.Add("InitPostEntity", "ZM.Preview.ReleaseTransitionLock", function()
    Preview.TransitionLocked = false
end)

// An empty id selects the world-origin den.
net.Receive("ZM.RequestPreviewDenTeleport", function(_, playerEntity)
    local safeZoneId = net.ReadString()
    local requestId = nextTeleportRequestId()
    local function reject(message)
        sendTeleportStatus(playerEntity, requestId, false, message, 0)
    end

    if not Preview:HasServerCapability(playerEntity, Preview.Capabilities.operator) then
        reject("Preview teleport is unavailable")
        return
    end
    if getHumanPlayerCount() ~= 1 then
        reject("Preview teleport requires exactly one human player")
        return
    end
    if ZM_MapBatch and ZM_MapBatch:IsActive() then
        reject("Map maintenance is active")
        return
    end
    if Preview.TransitionLocked then
        reject("A preview transition is already pending")
        return
    end
    local lastRequestAt = Preview.TeleportCooldowns[playerEntity:SteamID()] or 0
    if CurTime() - lastRequestAt < 1 then
        reject("Preview teleport is cooling down")
        return
    end
    if not ZM_World or not ZM_World:IsLoaded() then
        reject("Preview world data is not loaded")
        return
    end

    local safeZone = safeZoneId ~= "" and ZM_SafeZones:Get(safeZoneId) or ZM_SafeZones:GetOrigin()
    local entrance = safeZone and ZM_SafeZones:GetEntranceCell(safeZone.id) or nil
    local mapPath = safeZone and ZM_SafeZones:GetMap(safeZone.id) or nil
    if not safeZone or not entrance or type(mapPath) ~= "string" or not string.match(mapPath, "^[%w_/%-]+$") then
        reject("Selected den has no valid map")
        return
    end
    if not file.Exists("maps/" .. mapPath .. ".bsp", "GAME") then
        reject("Den map is not staged in Garry's Mod")
        return
    end

    local worldX, worldY = ZM_World:GetWorldCoordinates(entrance)
    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        reject(positionError or "Could not update player world position")
        return
    end
    local entered, enterError = playerEntity:SetCurrentSafeZone(safeZone.id)
    if not entered then
        reject(enterError or "Could not enter den")
        return
    end

    Preview.TeleportCooldowns[playerEntity:SteamID()] = CurTime()
    local targetMapName = string.lower(string.match(mapPath, "([^/]+)$") or mapPath)
    local currentMapName = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    if targetMapName == currentMapName then
        sendTeleportStatus(playerEntity, requestId, true, "Already in " .. (safeZone.name or safeZone.id), entrance.id, mapPath)
        return
    end

    Preview.TransitionLocked = true
    local transitionQueued = GAMEMODE and GAMEMODE.EnsurePlayerWorldMap and GAMEMODE:EnsurePlayerWorldMap(playerEntity)
    if not transitionQueued then
        Preview.TransitionLocked = false
        reject("Core world transition could not be queued")
        return
    end

    sendTeleportStatus(playerEntity, requestId, true, "Loading " .. (safeZone.name or safeZone.id), entrance.id, mapPath)
    print(string.format("[ZombieSim] Preview den teleport: %s -> %s (%s)", playerEntity:SteamID(), safeZone.id, mapPath))
end)

local function refillPlayer(playerEntity)
    playerEntity.SavedHealth = math.max(playerEntity:GetMaxHealth(), 100)
    playerEntity.Stamina = playerEntity:GetMaxStamina()
    playerEntity.Hunger = 100
    playerEntity.Thirst = 100
    playerEntity:SetHealth(playerEntity.SavedHealth)
    local saved, saveError = playerEntity:UpdatePlayerData("preview cheat refill")
    if not saved then
        return false, saveError or "Could not save player survival state"
    end
    playerEntity:SetNetworkPlayerData()
    playerEntity:SendPlayerData()
    return true
end

local function runPreviewRefill(playerEntity)
    if not IsValid(playerEntity) then
        return false, "no target player"
    end
    if not Preview:HasServerCapability(playerEntity, Preview.Capabilities.operator) then
        return false, "Preview refill requires an active admin preview session"
    end

    return refillPlayer(playerEntity)
end

local function restorePreviewPlayer(playerEntity)
    if not IsValid(playerEntity) then
        return false, "no target player"
    end
    if not Preview:HasServerCapability(playerEntity, Preview.Capabilities.operator) then
        return false, "Preview restoration requires an active admin preview session"
    end

    local safeZone = ZM_World:GetOriginSafeZone()
    local cell = safeZone and ZM_World:GetCellById(safeZone.cell) or nil
    if not safeZone or not cell then
        return false, "The preview origin safe room is unavailable"
    end
    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
    if not worldX or not worldY then
        return false, "The preview origin coordinates are unavailable"
    end

    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        return false, positionError or "Could not move the player to the preview origin"
    end
    local entered, enterError = playerEntity:SetCurrentSafeZone(safeZone.id)
    if not entered then
        return false, enterError or "Could not enter the preview origin safe room"
    end
    local refilled, refillError = refillPlayer(playerEntity)
    if not refilled then
        return false, refillError
    end

    local transitionQueued = GAMEMODE and GAMEMODE.EnsurePlayerWorldMap
        and GAMEMODE:EnsurePlayerWorldMap(playerEntity)
    if not transitionQueued then
        return false, "Could not queue the preview origin safe-room transition"
    end
    if not playerEntity:Alive() then
        playerEntity:Spawn()
    end
    return true
end

concommand.Add("zombiesim_preview_refill", function(caller)
    local target = IsValid(caller) and caller or ZM_Util.FirstHuman()
    local ok, errorMessage = runPreviewRefill(target)
    if IsValid(caller) then
        caller:PrintMessage(HUD_PRINTCONSOLE, ok and "[ZombieSim] Preview survival restored.\n" or ("[ZombieSim] " .. tostring(errorMessage) .. "\n"))
    elseif not ok then
        print("[ZombieSim] " .. tostring(errorMessage))
    end
end, nil, "Restore health and survival reserves for a preview admin.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zombiesim_preview_refill = function()
    return runPreviewRefill(ZM_Util.FirstHuman())
end
ZM_DevConsole.DirectCommands.zombiesim_preview_restore = function()
    return restorePreviewPlayer(ZM_Util.FirstHuman())
end

local function grantPreviewLevel(playerEntity)
    if playerEntity.ZM_PersistentStateLoaded ~= true then
        return false, "Player data is not loaded"
    end
    local previousLevel = tonumber(playerEntity.Level) or 1
    playerEntity.XP = math.max(tonumber(playerEntity.XP) or 0, tonumber(playerEntity.ExperiencePerLevel) or 0)
    playerEntity:AddXP(0)
    local saved, saveError = playerEntity:UpdatePlayerData("preview cheat level")
    if not saved then
        return false, saveError or "Could not save the level grant"
    end
    playerEntity:SetNetworkPlayerData()
    playerEntity:SendPlayerData()
    return true, string.format("Level %d -> %d", previousLevel, tonumber(playerEntity.Level) or previousLevel)
end

local killNearbyRadius = 2500

local function killNearbyZombies(playerEntity)
    local origin = playerEntity:GetPos()
    local killed = 0
    for _, zombie in ipairs(ents.FindByClass("zn_walker_zombie")) do
        if IsValid(zombie) and zombie:Health() > 0 and zombie:GetPos():DistToSqr(origin) <= killNearbyRadius * killNearbyRadius then
            // Credit the player so kill rewards, corpses, and walker tickets resolve normally.
            local damageInfo = DamageInfo()
            damageInfo:SetDamage(zombie:Health() + 1000)
            damageInfo:SetDamageType(DMG_GENERIC)
            damageInfo:SetAttacker(playerEntity)
            damageInfo:SetInflictor(playerEntity)
            zombie:TakeDamageInfo(damageInfo)
            killed = killed + 1
        end
    end
    return true, killed == 0 and "No zombies nearby" or string.format("Killed %d nearby zombie(s)", killed)
end

local cheatToggleActions = {
    toggle_god = { key = "god", label = "God mode" },
    toggle_noclip = { key = "noclip", label = "Noclip" },
    toggle_notarget = { key = "notarget", label = "Zombies ignore you" },
    toggle_infinite_ammo = { key = "infiniteAmmo", label = "Infinite ammo" },
    toggle_survival_lock = { key = "survivalLock", label = "Survival lock" }
}

local cheatWeatherActions = {
    weather_clear = "clear",
    weather_rain = "rain",
    weather_snow = "snow"
}

net.Receive("ZM.RequestPreviewCheat", function(_, playerEntity)
    local action = net.ReadString()
    if not Preview:HasServerCapability(playerEntity, Preview.Capabilities.operator) then
        Preview:SendCheatStatus(playerEntity, false, "Preview cheats are unavailable")
        return
    end

    local state = Preview:GetCheatState(playerEntity)
    local accepted, message
    local toggle = cheatToggleActions[action]
    if toggle then
        state[toggle.key] = not state[toggle.key]
        Preview:ApplyCheatState(playerEntity)
        Preview:SaveCheatStates()
        accepted = true
        message = toggle.label .. (state[toggle.key] and " enabled" or " disabled")
    elseif action == "refill" then
        accepted, message = refillPlayer(playerEntity)
        message = message or "Health and survival reserves restored"
    elseif action == "kill_nearby" then
        accepted, message = killNearbyZombies(playerEntity)
    elseif action == "grant_level" then
        accepted, message = grantPreviewLevel(playerEntity)
    elseif cheatWeatherActions[action] then
        if not ZM_AtmosphereService or not ZM_AtmosphereService.SetWeather then
            accepted, message = false, "The atmosphere service is unavailable"
        else
            accepted, message = ZM_AtmosphereService.SetWeather(cheatWeatherActions[action])
            message = message or ("Weather set to " .. cheatWeatherActions[action])
        end
    else
        accepted = false
        message = "Unknown preview cheat action"
    end

    Preview:SendCheatStatus(playerEntity, accepted, message)
end)

local attributeFields = {
    "Strength", "Agility", "Intelligence", "Endurance", "MachineGuns", "Shotguns", "Snipers",
    "WeaponCrafting", "ArmorCrafting", "Medicine", "Farming", "WeaponRepairing", "ArmorRepairing", "Mechanics"
}
local playerDataFields = {
    "XP", "Level", "MaxLevel", "Difficulty", "CellX", "CellY", "CurrentSafeZoneId", "SkillPoints",
    "Health", "Stamina", "Hunger", "Thirst"
}

local function sendPreviewData(playerEntity, action, response)
    response.action = action
    local json = util.TableToJSON(response, false) or "{}"
    net.Start("ZM.PreviewDataResponse")
        net.WriteString(json)
    net.Send(playerEntity)
end

local function validSteamId(steamId)
    return type(steamId) == "string" and string.match(steamId, "^STEAM_%d+:%d+:%d+$") ~= nil
end

local function hasDataAccess(playerEntity)
    return Preview:HasServerCapability(playerEntity, Preview.Capabilities.dataAdmin)
end

local function playerBySteamId(steamId)
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and playerEntity:SteamID() == steamId then
            return playerEntity
        end
    end
end

local function recordForSteamId(steamId)
    local characterKey, characterKeyError = ZM_CharacterService:GetCharacterKeyForSteamID(steamId, "preview")
    if not characterKey then return nil, characterKeyError end
    local attributes, attributesError = ZM_GetPlayerAttributes(characterKey, "preview")
    if attributesError then
        return nil, attributesError
    end
    local playerData, playerDataError = ZM_GetPlayerData(characterKey, "preview")
    if playerDataError then
        return nil, playerDataError
    end
    if not playerData then
        return nil
    end
    if not attributes then
        attributes = { Revision = 0, UpdatedAt = 0 }
        for _, field in ipairs(attributeFields) do
            attributes[field] = 0
        end
    end
    return { steamId = steamId, characterId = characterKey, attributes = attributes, playerData = playerData, online = IsValid(playerBySteamId(steamId)) }
end

local function boundedInteger(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= math.floor(value) or value < minimum or value > maximum then
        return nil
    end
    return value
end

local function validateAttributes(values)
    local output = {}
    for _, field in ipairs(attributeFields) do
        local value = boundedInteger(values[field], 0, 300)
        if value == nil then
            return nil, "Invalid " .. field
        end
        output[field] = value
    end
    return output
end

local function validatePlayerData(values)
    local output = {}
    output.XP = boundedInteger(values.XP, 0, 2000000000)
    output.Level = boundedInteger(values.Level, 1, 300)
    output.MaxLevel = boundedInteger(values.MaxLevel, 1, 300)
    output.Difficulty = boundedInteger(values.Difficulty, 1, 4)
    output.CellX = boundedInteger(values.CellX, -32768, 32767)
    output.CellY = boundedInteger(values.CellY, -32768, 32767)
    output.SkillPoints = boundedInteger(values.SkillPoints, 0, 10000)
    output.Health = boundedInteger(values.Health, 1, 100)
    output.Stamina = tonumber(values.Stamina)
    output.Hunger = tonumber(values.Hunger)
    output.Thirst = tonumber(values.Thirst)
    if not output.XP or not output.Level or not output.MaxLevel or output.Level > output.MaxLevel or not output.Difficulty or
        not output.CellX or not output.CellY or not output.SkillPoints or not output.Health or not output.Stamina or not output.Hunger or not output.Thirst then
        return nil, "Invalid progression or survival value"
    end
    local gridX, gridY = ZM_World:GetGridCoordinates(output.CellX, output.CellY)
    if not gridX or not gridY or not ZM_World:GetCell(gridX, gridY) then
        return nil, "Selected world cell is outside preview"
    end
    output.CurrentSafeZoneId = string.Trim(tostring(values.CurrentSafeZoneId or ""))
    if #output.CurrentSafeZoneId > 80 then
        return nil, "Safe-zone id is too long"
    end
    if output.CurrentSafeZoneId ~= "" then
        local safeZone = ZM_World:GetSafeZoneById(output.CurrentSafeZoneId)
        if not safeZone then
            return nil, "Unknown preview safe-zone id"
        end
        local safeZoneCell = ZM_World:GetCellById(safeZone.cell)
        if not safeZoneCell then
            return nil, "Preview safe-zone location is unavailable"
        end
        local safeZoneX, safeZoneY = ZM_World:GetWorldCoordinates(safeZoneCell)
        if safeZoneX == nil or safeZoneY == nil then
            return nil, "Preview safe-zone coordinates are unavailable"
        end
        if output.CellX ~= safeZoneX or output.CellY ~= safeZoneY then
            output.CurrentSafeZoneId = ""
        end
    end
    output.Stamina = math.Clamp(output.Stamina, 0, 100000)
    output.Hunger = math.Clamp(output.Hunger, 0, 100)
    output.Thirst = math.Clamp(output.Thirst, 0, 100)
    return output
end

local function applyLiveRecord(record)
    local target = playerBySteamId(record.steamId)
    if not target or ZM_World.ActiveProfile ~= "preview" then
        return
    end
    local characterKey = target:GetCharacterKey()
    if characterKey ~= record.characterId then return end
    for _, field in ipairs(attributeFields) do
        target.Attributes[field] = tonumber(record.attributes[field]) or 0
    end
    for _, field in ipairs(playerDataFields) do
        if field ~= "CurrentSafeZoneId" then
            target[field] = tonumber(record.playerData[field]) or 0
        end
    end
    target.CurrentSafeZoneId = record.playerData.CurrentSafeZoneId ~= "" and record.playerData.CurrentSafeZoneId or nil
    target.Stamina = math.Clamp(target.Stamina, 0, target:GetMaxStamina())
    target:SetHealth(math.max(1, target.SavedHealth))
    target:SetNetworkAttributes()
    target:SetNetworkPlayerData()
    target:SendPlayerAttributes()
    target:SendPlayerData()
    GAMEMODE:SendPlayerAtmosphereProfile(target)
end

net.Receive("ZM.RequestPreviewData", function(_, playerEntity)
    local json = net.ReadString()
    if #json > 8192 then
        sendPreviewData(playerEntity, "error", { ok = false, message = "Request is too large" })
        return
    end
    local request = util.JSONToTable(json)
    if type(request) ~= "table" or type(request.action) ~= "string" then
        sendPreviewData(playerEntity, "error", { ok = false, message = "Invalid preview data request" })
        return
    end
    if not hasDataAccess(playerEntity) then
        sendPreviewData(playerEntity, request.action, { ok = false, message = "Preview data access is unavailable" })
        return
    end

    if request.action == "list" then
        local search = tostring(request.search or "")
        if #search > 32 or (search ~= "" and not validSteamId(search)) then
            sendPreviewData(playerEntity, "list", { ok = false, message = "Search requires an exact SteamID" })
            return
        end
        local where = " WHERE a.profile = 'preview'"
        if search ~= "" then
            where = where .. " AND c.steamid = " .. sql.SQLStr(search)
        end
        local rows = sql.Query("SELECT c.steamid AS steamid, c.slot AS slot, c.name AS name, pd.Level, pd.CellX, pd.CellY, pd.UpdatedAt FROM active_characters a JOIN characters c ON c.steamid = a.steamid AND c.profile = a.profile AND c.slot = a.slot JOIN player_data pd ON pd.steamid = c.characterId AND pd.profile = c.profile"
            .. where .. " ORDER BY c.steamid LIMIT 50")
        if rows == false then
            sendPreviewData(playerEntity, "list", { ok = false, message = sql.LastError() or "Could not list preview characters" })
            return
        end
        sendPreviewData(playerEntity, "list", { ok = true, rows = rows or {} })
        return
    end

    local steamId = tostring(request.steamId or "")
    if not validSteamId(steamId) then
        sendPreviewData(playerEntity, request.action, { ok = false, message = "Invalid SteamID" })
        return
    end
    local record, recordError = recordForSteamId(steamId)
    if not record then
        sendPreviewData(playerEntity, request.action, { ok = false, message = recordError or "No preview record exists for this player" })
        return
    end
    if request.action == "read" then
        sendPreviewData(playerEntity, "read", { ok = true, record = record })
        return
    end

    local values, validationError
    if request.action == "attributes" then
        values, validationError = validateAttributes(request.values or {})
    elseif request.action == "playerData" then
        values, validationError = validatePlayerData(request.values or {})
    else
        sendPreviewData(playerEntity, request.action, { ok = false, message = "Unknown preview data action" })
        return
    end
    if not values then
        sendPreviewData(playerEntity, request.action, { ok = false, message = validationError })
        return
    end

    local saved, saveError
    if request.action == "attributes" then
        saved, saveError = ZM_SetPlayerAttributes(record.characterId, "preview", values)
    else
        saved, saveError = ZM_SetPlayerData(record.characterId, "preview", values, "preview data editor")
    end
    if not saved then
        sendPreviewData(playerEntity, request.action, { ok = false, message = saveError or "Could not save preview record" })
        return
    end
    local savedRecord, savedRecordError = recordForSteamId(steamId)
    if not savedRecord then
        sendPreviewData(playerEntity, request.action, { ok = false, message = savedRecordError or "Preview record could not be reloaded" })
        return
    end
    applyLiveRecord(savedRecord)
    sendPreviewData(playerEntity, request.action, { ok = true, message = "Preview record saved", record = savedRecord })
end)