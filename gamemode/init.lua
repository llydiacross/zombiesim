
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "sh_player.lua" )
AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "cl_player.lua" )
AddCSLuaFile( "cl_thirdpersoncamera.lua" )
AddCSLuaFile( "cl_hud.lua" )
AddCSLuaFile( "cl_crosshair.lua" )

include( "utils/sql.lua" )
include( "shared.lua" )
include( "sv_player.lua" )

ZM_CreatePlayerAttributesTable()
ZM_CreatePlayerDataTable()

util.AddNetworkString("ZM.RefreshPlayerAttributes")
util.AddNetworkString("ZM.RefreshPlayerData")

function GM:PlayerSpawn( ply )

    // check if the player has previously connected to the server
    if( !ZM_PlayerPreviouslyExists( ply:SteamID() ) ) then
        ply.PreviouslyConnected = true
    end

    // fetch the player attributes and data from the database
    ply:FetchAttributes()
    ply:FetchPlayerData()
    ply:SetHealth(math.max(ply.Health, 1))
    ply.Stamina = math.Clamp(ply.Stamina, 0, ply:GetMaxStamina())

    if( !ply.PreviouslyConnected ) then
        ply.SkillPoints = 10 // give the player 10 skill points to start with
    end

    // save the player attributes and data to the database
    ply:Save()

    // network the player attributes and data to the client
    ply:UpdateAttributes()
    ply:UpdatePlayerData()

    // tell the client to set the player attributes and data
    ply:SendPlayerAttributes()
    ply:SendPlayerData()
end

function GM:PlayerDisconnected( ply )
    // save the player attributes and data to the database
    ply:Save()
end

function GM:ShutDown()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            ply:Save()
        end
    end
end

