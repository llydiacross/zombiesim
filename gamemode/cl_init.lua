include( "shared.lua" )
include( "cl_player.lua" )

net.Receive("RefreshPlayerAttributes", function(len, ply)
    ply:SetAttributes()
end)

net.Receive("RefreshPlayerData", function(len, ply)
    ply:SetPlayerData()
end)