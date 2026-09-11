// Server entry point: distributes shared/client code, loads server systems, and owns persistence.
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "sh_player.lua" )
AddCSLuaFile( "sh_compass.lua" )
AddCSLuaFile( "sh_preview.lua" )
AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "cl_skin.lua" )
AddCSLuaFile( "cl_player.lua" )
AddCSLuaFile( "cl_thirdpersoncamera.lua" )
AddCSLuaFile( "cl_transitions.lua" )
AddCSLuaFile( "cl_hud.lua" )
AddCSLuaFile( "cl_crosshair.lua" )
AddCSLuaFile( "cl_atmosphere.lua" )
AddCSLuaFile( "cl_world_map.lua" )
AddCSLuaFile( "cl_scoreboard.lua" )
AddCSLuaFile( "cl_map_batch.lua" )
AddCSLuaFile( "cl_preview.lua" )
AddCSLuaFile( "cl_dependency_prompts.lua" )
AddCSLuaFile( "cl_quick_menu.lua" )
AddCSLuaFile( "utils/world.lua" )
AddCSLuaFile( "utils/safezone.lua" )

// These are server-only utilities; shared.lua loads code needed by both realms.
include( "utils/sql.lua" )
include( "shared.lua" )
include( "sv_player.lua" )
include( "sv_map_batch.lua" )
include( "sv_preview.lua" )
include( "sv_dev_console.lua" )
include( "sv_dependency_prompts.lua" )
include( "sv_walker_sim.lua" )
include( "sv_walker_materialization.lua" )
include( "sv_transitions.lua" )

// Ensure the SQLite schema exists before any PlayerSpawn handler performs a lookup.
local attributesReady, attributesError = ZM_CreatePlayerAttributesTable()
local playerDataReady, playerDataError = ZM_CreatePlayerDataTable()
if not attributesReady then
    ErrorNoHalt("[ZombieSim] Could not prepare player attributes: " .. tostring(attributesError) .. "\n")
end
if not playerDataReady then
    ErrorNoHalt("[ZombieSim] Could not prepare player data: " .. tostring(playerDataError) .. "\n")
end

// Clients use these lightweight signals to refresh their local Player extension fields.
util.AddNetworkString("ZM.RefreshPlayerAttributes")
util.AddNetworkString("ZM.RefreshPlayerData")
util.AddNetworkString("ZM.SetAtmosphereProfile")
util.AddNetworkString("ZM.UpdatePlayerBio")

net.Receive("ZM.UpdatePlayerBio", function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then
        return
    end

    ply:SaveBio(net.ReadString())
end)

// Persists the selected city or preview data profile while the session moves into safe-room maps.
CreateConVar("zombiesim_world_profile", "city", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Active ZombieSim world-data profile.")

concommand.Add("zombiesim_reset_player", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        print("[ZombieSim] zombiesim_reset_player must be run by an in-game admin.")
        return
    end

    local reset, destination = ply:ResetForWorldOrigin()
    if not reset then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] Could not reset player: " .. destination .. "\n")
        return
    end

    ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] Player reset. Returning to the world origin.\n")
    game.ConsoleCommand("changelevel " .. destination .. "\n")
end)

concommand.Add("zombiesim_player_status", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        print("[ZombieSim] zombiesim_player_status must be run by an in-game admin.")
        return
    end

    local reconciled = GAMEMODE:ReconcilePlayerOriginCell(ply)
    if reconciled then
        ply:UpdatePlayerData("status reconciliation")
        ply:SetNetworkPlayerData()
        ply:SendPlayerData()
        GAMEMODE:SendPlayerAtmosphereProfile(ply)
    end

    local cell, cellError = ply:GetWorldCell()
    local worldX, worldY = ply:GetWorldCellCoordinates()
    local gridX, gridY = worldX and ZM_World:GetGridCoordinates(worldX, worldY) or nil, nil
    if worldX then
        gridX, gridY = ZM_World:GetGridCoordinates(worldX, worldY)
    end
    local originGridX, originGridY = ZM_World:GetGridOrigin()
    local worldData = ZM_World:GetData() or {}
    local originWorld = worldData.world and worldData.world.origin or {}
    local safeZoneId = ply.CurrentSafeZoneId or "none"
    local currentMap = game.GetMap()
    local cellMap = cell and ZM_World:GetMapPath(cell) or "unresolved"
    local message = string.format(
        "[ZombieSim] Player status%s\nLogical world: %s, %s\nMap grid: %s, %s\nWorld origin: %s, %s (raw grid %s, %s)\nCurrent safe zone: %s\nLoaded map: %s\nCell map: %s\n",
        reconciled and " (safe-zone position repaired)" or "",
        tostring(worldX), tostring(worldY), tostring(gridX), tostring(gridY),
        tostring(originWorld[1]), tostring(originWorld[2]), tostring(originGridX), tostring(originGridY),
        safeZoneId, currentMap, cellMap
    )
    if not cell then
        message = message .. "Cell resolution error: " .. tostring(cellError) .. "\n"
    end
    ply:PrintMessage(HUD_PRINTCONSOLE, message)
end)

// Sends only the compact atmosphere-profile id; clients already have the static profile table.
function GM:SendPlayerAtmosphereProfile(ply)
    if not IsValid(ply) then
        return false
    end

    local cell = ply:GetWorldCell()
    local profileIndex = cell and tonumber(cell.atmosphereProfile)
    if not profileIndex or profileIndex < 0 or profileIndex > 255 then
        return false
    end

    net.Start("ZM.SetAtmosphereProfile")
        net.WriteUInt(profileIndex, 8)
    net.Send(ply)
    return true
end

// Aligns the saved logical position with the active safe-zone entrance when loaded in that den.
function GM:ReconcilePlayerOriginCell(ply)
    local safeZoneId = ply.CurrentSafeZoneId
    local safeZone = type(safeZoneId) == "string" and safeZoneId ~= "" and ZM_SafeZones:Get(safeZoneId) or nil
    if not safeZone then
        return false
    end

    local safeZoneMap = ZM_SafeZones:GetMap(safeZone.id)
    local safeZoneCell = ZM_World:GetCellById(safeZone.cell)
    if not safeZoneMap or not safeZoneCell then
        return false
    end
    local activeMap = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    local safeZoneMapName = string.lower(string.match(safeZoneMap, "([^/]+)$") or safeZoneMap)
    if activeMap ~= safeZoneMapName then
        return false
    end
    local safeZoneWorldX, safeZoneWorldY = ZM_World:GetWorldCoordinates(safeZoneCell)
    if ply.CellX == safeZoneWorldX and ply.CellY == safeZoneWorldY then
        return false
    end

    ply.CellX = safeZoneWorldX
    ply.CellY = safeZoneWorldY
    return true
end

// Starts a single-player session in the safe room attached to the generated world origin.
// Returns false when world data is unavailable or the session is already on that safe-room map.
function GM:EnterOriginSafeZone(ply)
    if self.OriginSafeZoneTransitionQueued then
        return false
    end

    local safeZone = ZM_SafeZones:GetOrigin()
    local destination = ZM_SafeZones:GetOriginMap()
    if not safeZone or not destination then
        return false
    end

    local destinationMap = string.match(destination, "([^/]+)$") or destination
    local currentMap = string.match(game.GetMap(), "([^/]+)$") or game.GetMap()
    if currentMap == destinationMap then
        return false
    end

    local startDelay, delayError = ZM_World:GetMapStartDelay()
    if delayError then
        ErrorNoHalt("[ZombieSim] Could not read start delay: " .. delayError .. "\n")
        return false
    end

    local function transitionToOriginSafeZone()
        self.OriginSafeZoneTransitionQueued = false
        if not IsValid(ply) then
            return
        end

        local activeMap = string.match(game.GetMap(), "([^/]+)$") or game.GetMap()
        if activeMap == destinationMap then
            return
        end

        local originCell = ZM_World:GetCellById(safeZone.cell)
        if not originCell then
            ErrorNoHalt("[ZombieSim] Could not resolve the world-origin city cell.\n")
            return
        end
        local originWorldX, originWorldY = ZM_World:GetWorldCoordinates(originCell)
        local positioned, positionError = ply:SetWorldCell(originWorldX, originWorldY)
        if not positioned then
            ErrorNoHalt("[ZombieSim] Could not set world-origin city cell: " .. positionError .. "\n")
            return
        end

        local set, setError = ply:SetCurrentSafeZone(safeZone.id)
        if not set then
            ErrorNoHalt("[ZombieSim] Could not enter origin safe room: " .. setError .. "\n")
            return
        end

        game.ConsoleCommand("changelevel " .. destination .. "\n")
    end

    self.OriginSafeZoneTransitionQueued = true
    if startDelay > 0 then
        timer.Simple(startDelay, transitionToOriginSafeZone)
    else
        transitionToOriginSafeZone()
    end
    return true
end

// Returns the map a saved player belongs on in the active world-data profile.
// A current safe-room id takes priority over the city cell used as that room's entrance.
function GM:GetExpectedPlayerMap(ply)
    local safeZoneId = ply.CurrentSafeZoneId
    if type(safeZoneId) == "string" and safeZoneId ~= "" then
        local safeZone = ZM_SafeZones:Get(safeZoneId)
        if not safeZone then
            return nil, "Saved safe-zone id is not available in the active profile: " .. safeZoneId
        end

        return ZM_SafeZones:GetMap(safeZoneId)
    end

    local cell, cellError = ply:GetWorldCell()
    if not cell then
        return nil, cellError or "Player has no valid saved city cell"
    end

    return ZM_World:GetMapPath(cell)
end

// Changes level only when the loaded map differs from the player's persisted city or safe-room state.
function GM:EnsurePlayerWorldMap(ply, entryLandmark)
    if self.PlayerWorldMapTransitionQueued then
        return false
    end

    local expectedMap, mapError = self:GetExpectedPlayerMap(ply)
    if not expectedMap then
        ErrorNoHalt("[ZombieSim] Could not resolve player map: " .. mapError .. "\n")
        return false
    end

    local expectedMapName = string.lower(string.match(expectedMap, "([^/]+)$") or expectedMap)
    local currentMapName = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    if currentMapName == expectedMapName then
        return false
    end

    self.PlayerWorldMapTransitionQueued = true
    local landmark = type(entryLandmark) == "string" and string.match(entryLandmark, "^[A-Z]+_ENTRANCE$") or nil
    game.ConsoleCommand("changelevel " .. expectedMap .. (landmark and " " .. landmark or "") .. "\n")
    return true
end

local function isCurrentProfileLauncher(profile)
    local mapName = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    return ZM_World.LauncherMapProfiles[mapName] == profile
end

function GM:NewPlayer(ply)
    ply.SkillPoints = 10 // give the player 10 skill points to start with
end

function GM:ContinuePlayerSpawnMapTransition(ply, profile, previouslyConnected)
    if ZM_MapBatch and ZM_MapBatch:IsActive() then
        return
    end

    // Preview always enters its saved city cell; city retains its safe-room start.
    if profile == "preview" then
        self:EnsurePlayerWorldMap(ply)
    elseif not previouslyConnected and isCurrentProfileLauncher(profile) then
        self:EnterOriginSafeZone(ply)
    else
        self:EnsurePlayerWorldMap(ply)
    end
end

// Restores persistent state, applies new-player defaults, and synchronizes the spawned player.
function GM:PlayerSpawn( ply )

    ply.ZM_PersistentStateLoaded = false

    // PlayerSpawn can run before InitPostEntity after a level change.
    local loaded, loadError = ZM_World:LoadMapProfile()
    if not loaded then
        ErrorNoHalt("[ZombieSim] Could not load map profile before player spawn: " .. tostring(loadError) .. "\n")
        return
    end

    // A first-time player receives the starting skills and origin safe-room transition.
    local profile = ZM_World.ActiveProfile
    local profiled, profileError = ZM_EnsureProfiledPlayerData(profile)
    if not profiled then
        ErrorNoHalt("[ZombieSim] Could not prepare player data for profile '" .. tostring(profile) .. "': " .. tostring(profileError) .. "\n")
        return
    end
    // fetch the player attributes and data from the database
    local attributesLoaded, attributesError = ply:FetchAttributes()
    if not attributesLoaded then
        ErrorNoHalt("[ZombieSim] Could not load player attributes: " .. tostring(attributesError) .. "\n")
        return
    end
    local previouslyConnected, playerDataError = ply:FetchPlayerData()
    if previouslyConnected == nil then
        ErrorNoHalt("[ZombieSim] Could not load player data: " .. tostring(playerDataError) .. "\n")
        return
    end
    ply.PreviouslyConnected = previouslyConnected
    ply.ZM_PersistentStateLoaded = true
    self:ReconcilePlayerOriginCell(ply)
    ply:SetHealth(math.max(ply.SavedHealth, 1))
    ply.Stamina = math.Clamp(tonumber(ply.Stamina) or ply:GetMaxStamina(), 0, ply:GetMaxStamina())

    if not previouslyConnected then
        self:NewPlayer(ply)
        local saved, saveError = ply:Save("new-player spawn")
        if not saved then
            ErrorNoHalt("[ZombieSim] Could not save new player state: " .. tostring(saveError) .. "\n")
        end
    end

    // network the player attributes and data to the client
    ply:LoadBio()
    ply:SetNetworkAttributes()
    ply:SetNetworkPlayerData()

    // tell the client to set the player attributes and data
    ply:SendPlayerAttributes()
    ply:SendPlayerData()
    self:SendPlayerAtmosphereProfile(ply)
    ZM_Preview:SendCapabilities(ply)
    ZM_Preview:ApplyCheatState(ply)
    ZM_Preview:SendCheatStatus(ply, true, "")
    if ZM_Transitions then
        ZM_Transitions:ApplyPendingEntry(ply)
    end

    if ZM_DependencyPrompts and ZM_DependencyPrompts:HoldLauncherTransition(ply, profile, previouslyConnected) then
        return
    end

    self:ContinuePlayerSpawnMapTransition(ply, profile, previouslyConnected)
end

// Persist progress that may have changed since the last explicit update.
function GM:PlayerDisconnected( ply )
    // Preview editor and teleport writes are immediate; disconnect teardown can expose cleared fields.
    if ZM_World.ActiveProfile ~= "preview" then
        ply:Save("player disconnect")
    end
    ply.ZM_PersistentStateLoaded = false
end

// Map teardown can expose cleared Player fields, so persistence happens through explicit updates and disconnects.
function GM:ShutDown()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            ply.ZM_PersistentStateLoaded = false
        end
    end
end

