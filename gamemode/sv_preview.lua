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

function Preview:GetCheatState(playerEntity)
    local steamId = IsValid(playerEntity) and playerEntity:SteamID() or nil
    if not steamId then
        return { god = false, noclip = false }
    end

    self.CheatStates[steamId] = self.CheatStates[steamId] or { god = false, noclip = false }
    return self.CheatStates[steamId]
end

function Preview:SendCheatStatus(playerEntity, accepted, message)
    local state = self:GetCheatState(playerEntity)
    net.Start("ZM.PreviewCheatStatus")
        net.WriteBool(accepted == true)
        net.WriteString(message or "")
        net.WriteBool(state.god == true)
        net.WriteBool(state.noclip == true)
    net.Send(playerEntity)
end

function Preview:ApplyCheatState(playerEntity)
    if not IsValid(playerEntity) then
        return
    end

    local state = self:GetCheatState(playerEntity)
    if state.god then
        playerEntity:GodEnable()
    else
        playerEntity:GodDisable()
    end
    if state.noclip then
        playerEntity:SetMoveType(MOVETYPE_NOCLIP)
    elseif playerEntity:GetMoveType() == MOVETYPE_NOCLIP then
        playerEntity:SetMoveType(MOVETYPE_WALK)
    end
end

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

net.Receive("ZM.RequestPreviewTeleport", function(_, playerEntity)
    local cellId = net.ReadUInt(16)
    local requestId = nextTeleportRequestId()
    local function reject(message)
        sendTeleportStatus(playerEntity, requestId, false, message, cellId)
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

    local target, targetError = getPreviewTeleportTarget(cellId)
    if not target then
        reject(targetError)
        return
    end

    local profileConVar = GetConVar("zombiesim_world_profile")
    if profileConVar then
        profileConVar:SetString("preview")
    end

    local worldX, worldY = ZM_World:GetWorldCoordinates(target.cell)
    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        reject(positionError or "Could not update player world position")
        return
    end

    local targetMapName = string.lower(string.match(target.mapPath, "([^/]+)$") or target.mapPath)
    local currentMapName = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    if targetMapName == currentMapName then
        Preview.TeleportCooldowns[playerEntity:SteamID()] = CurTime()
        sendTeleportStatus(playerEntity, requestId, true, "Selected current preview cell", target.cell.id, target.mapPath)
        return
    end

    Preview.TeleportCooldowns[playerEntity:SteamID()] = CurTime()
    Preview.TransitionLocked = true
    local transitionQueued = GAMEMODE and GAMEMODE.EnsurePlayerWorldMap and GAMEMODE:EnsurePlayerWorldMap(playerEntity)
    if not transitionQueued then
        Preview.TransitionLocked = false
        reject("Core world transition could not be queued")
        return
    end

    sendTeleportStatus(playerEntity, requestId, true, "Loading selected preview cell", target.cell.id, target.mapPath)
    print(string.format("[ZombieSim] Preview teleport: %s -> %d,%d (%s)", playerEntity:SteamID(), worldX, worldY, target.mapPath))
end)

hook.Add("InitPostEntity", "ZM.Preview.ReleaseTransitionLock", function()
    Preview.TransitionLocked = false
end)

local cheatDirections = {
    move_north = "N",
    move_east = "E",
    move_south = "S",
    move_west = "W"
}

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

local function movePlayerToNeighbour(playerEntity, direction)
    if getHumanPlayerCount() ~= 1 then
        return false, "Cell movement requires exactly one human player"
    end
    if Preview.TransitionLocked or (ZM_MapBatch and ZM_MapBatch:IsActive()) then
        return false, "A map transition is already active"
    end

    local targetCell = playerEntity:GetNeighbouringCell(direction)
    if not targetCell then
        return false, "There is no connected cell in that direction"
    end
    local worldX, worldY = ZM_World:GetWorldCoordinates(targetCell)
    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        return false, positionError or "Could not set the neighboring cell"
    end

    Preview.TransitionLocked = true
    local transitionQueued = GAMEMODE and GAMEMODE.EnsurePlayerWorldMap and GAMEMODE:EnsurePlayerWorldMap(playerEntity)
    if not transitionQueued then
        Preview.TransitionLocked = false
        return false, "Core world transition could not be queued"
    end
    return true, "Loading the neighboring cell"
end

net.Receive("ZM.RequestPreviewCheat", function(_, playerEntity)
    local action = net.ReadString()
    if not Preview:HasServerCapability(playerEntity, Preview.Capabilities.operator) then
        Preview:SendCheatStatus(playerEntity, false, "Preview cheats are unavailable")
        return
    end

    local state = Preview:GetCheatState(playerEntity)
    local accepted, message
    if action == "toggle_god" then
        state.god = not state.god
        Preview:ApplyCheatState(playerEntity)
        accepted = true
        message = state.god and "God mode enabled" or "God mode disabled"
    elseif action == "toggle_noclip" then
        state.noclip = not state.noclip
        Preview:ApplyCheatState(playerEntity)
        accepted = true
        message = state.noclip and "Noclip enabled" or "Noclip disabled"
    elseif action == "refill" then
        accepted, message = refillPlayer(playerEntity)
        message = message or "Health and survival reserves restored"
    elseif cheatDirections[action] then
        accepted, message = movePlayerToNeighbour(playerEntity, cheatDirections[action])
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
    local attributes, attributesError = ZM_GetPlayerAttributes(steamId, "preview")
    if attributesError then
        return nil, attributesError
    end
    local playerData, playerDataError = ZM_GetPlayerData(steamId, "preview")
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
    return { steamId = steamId, attributes = attributes, playerData = playerData, online = IsValid(playerBySteamId(steamId)) }
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
        local where = " WHERE profile = 'preview'"
        if search ~= "" then
            where = where .. " AND steamid = " .. sql.SQLStr(search)
        end
        local rows = sql.Query("SELECT steamid, Level, CellX, CellY, UpdatedAt FROM player_data" .. where .. " ORDER BY steamid LIMIT 50") or {}
        local playerRows = {}
        for _, row in ipairs(rows) do
            if validSteamId(row.steamid) then
                table.insert(playerRows, row)
            end
        end
        sendPreviewData(playerEntity, "list", { ok = true, rows = playerRows })
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
        saved, saveError = ZM_SetPlayerAttributes(steamId, "preview", values)
    else
        saved, saveError = ZM_SetPlayerData(steamId, "preview", values, "preview data editor")
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