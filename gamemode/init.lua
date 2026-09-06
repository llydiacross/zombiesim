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

// Starts a single-player session in the safe room attached to the generated world origin.
// Returns false when world data is unavailable or the session is already on that safe-room map.
function GM:EnterOriginSafeZone(ply)
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

    local set, setError = ply:SetCurrentSafeZone(safeZone.id)
    if not set then
        ErrorNoHalt("[ZombieSim] Could not enter origin safe room: " .. setError .. "\n")
        return false
    end

    game.ConsoleCommand("changelevel " .. destination .. "\n")
    return true
end

// Restores persistent state, applies new-player defaults, and synchronizes the spawned player.
function GM:PlayerSpawn( ply )

    // check if the player has previously connected to the server
    if( !ZM_PlayerPreviouslyExists( ply:SteamID() ) ) then
        ply.PreviouslyConnected = true
    end

    // fetch the player attributes and data from the database
    ply:FetchAttributes()
    ply:FetchPlayerData()
    ply:SetHealth(math.max(ply.SavedHealth, 1))
    ply.Stamina = math.Clamp(tonumber(ply.Stamina) or ply:GetMaxStamina(), 0, ply:GetMaxStamina())

    if( !ply.PreviouslyConnected ) then
        ply.SkillPoints = 10 // give the player 10 skill points to start with
        self:EnterOriginSafeZone(ply)
    end

    // save the player attributes and data to the database
    ply:Save()

    // network the player attributes and data to the client
    ply:UpdateAttributes()
    ply:UpdatePlayerData()

    // tell the client to set the player attributes and data
    ply:SendPlayerAttributes()
    ply:SendPlayerData()

    // enter the origin safe zone
    if( !ply.PreviouslyConnected ) then
        self:EnterOriginSafeZone(ply)
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

