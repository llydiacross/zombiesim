AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )

AddCSLuaFile( "cl_player.lua" )
AddCSLuaFile( "sh_player.lua" )

include( "shared.lua" )

util.AddNetworkString("RefreshPlayerAttributes")
util.AddNetworkString("RefreshPlayerData")

function GM:PlayerSpawn( ply )

    // check if the player has previously connected to the server
    if( !PlayerPreviouslyExists( ply:SteamID() ) ) then
        ply.PreviouslyConnected = true
    end

    // fetch the player attributes and data from the database
    ply:FetchAttributes()
    ply:FetchPlayerData()

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

function: GM:PlayerDisconnected( ply )
    // save the player attributes and data to the database
    ply:Save()
end

