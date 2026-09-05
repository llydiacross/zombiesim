include( "shared.lua" )
include( "cl_player.lua" )
include( "cl_thirdpersoncamera.lua" )
include( "cl_hud.lua" )
include( "cl_crosshair.lua" )

net.Receive("RefreshPlayerAttributes", function(len, ply)
    LocalPlayer():SetPlayerAttributes()
end)

net.Receive("RefreshPlayerData", function(len, ply)
    LocalPlayer():SetPlayerData()
end)