// Server entry point: distributes shared/client code, loads server systems, and owns persistence.
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "sh_player.lua" )
AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "cl_player.lua" )
AddCSLuaFile( "cl_thirdpersoncamera.lua" )
AddCSLuaFile( "cl_hud.lua" )
AddCSLuaFile( "cl_crosshair.lua" )
AddCSLuaFile( "utils/world.lua" )
AddCSLuaFile( "utils/safezone.lua" )

// These are server-only utilities; shared.lua loads code needed by both realms.
include( "utils/sql.lua" )
include( "shared.lua" )
include( "sv_player.lua" )

// Ensure the SQLite schema exists before any PlayerSpawn handler performs a lookup.
ZM_CreatePlayerAttributesTable()
ZM_CreatePlayerDataTable()

// Clients use these lightweight signals to refresh their local Player extension fields.
util.AddNetworkString("ZM.RefreshPlayerAttributes")
util.AddNetworkString("ZM.RefreshPlayerData")

// Persists the selected city or preview data profile while the session moves into safe-room maps.
CreateConVar("zombiesim_world_profile", "city", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Active ZombieSim world-data profile.")

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
function GM:EnsurePlayerWorldMap(ply)
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
    game.ConsoleCommand("changelevel " .. expectedMap .. "\n")
    return true
end

function GM:NewPlayer(ply)
    ply.SkillPoints = 10 // give the player 10 skill points to start with
end

// Restores persistent state, applies new-player defaults, and synchronizes the spawned player.
function GM:PlayerSpawn( ply )

    // A first-time player receives the starting skills and origin safe-room transition.
    ply.PreviouslyConnected = ZM_PlayerPreviouslyExists( ply:SteamID() )

    // fetch the player attributes and data from the database
    ply:FetchAttributes()
    ply:FetchPlayerData()
    ply:SetHealth(math.max(ply.SavedHealth, 1))
    ply.Stamina = math.Clamp(tonumber(ply.Stamina) or ply:GetMaxStamina(), 0, ply:GetMaxStamina())

    if not ply.PreviouslyConnected then
        self:NewPlayer(ply)
    end
    
    // save the player attributes and data to the database
    ply:Save()

    // network the player attributes and data to the client
    ply:UpdateAttributes()
    ply:UpdatePlayerData()

    // tell the client to set the player attributes and data
    ply:SendPlayerAttributes()
    ply:SendPlayerData()

    // A first-time single-player session begins at the safe room attached to the world origin.
    if( !ply.PreviouslyConnected ) then
        self:EnterOriginSafeZone(ply)
    else
        self:EnsurePlayerWorldMap(ply)
    end
end

// Persist progress that may have changed since the last explicit update.
function GM:PlayerDisconnected( ply )
    // save the player attributes and data to the database
    ply:Save()
end

// Save all connected players when the server closes or the gamemode unloads.
function GM:ShutDown()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            ply:Save()
        end
    end
end

