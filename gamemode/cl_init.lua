// Client entry point: shared state first, then player, camera, and HUD presentation systems.
include( "shared.lua" )
include( "cl_player.lua" )
include( "cl_thirdpersoncamera.lua" )
include( "cl_hud.lua" )
include( "cl_crosshair.lua" )
include( "cl_atmosphere.lua" )

// The server has updated NWInts; mirror them into the local Player extension table.
net.Receive("RefreshPlayerAttributes", function(len, ply)
    LocalPlayer():SetPlayerAttributes()
end)

// The server has updated core NW values; mirror them into the local Player extension table.
net.Receive("RefreshPlayerData", function(len, ply)
    LocalPlayer():SetPlayerData()
    if ZM_Atmosphere and ZM_Atmosphere.ApplyPlayerProfile then
        ZM_Atmosphere:ApplyPlayerProfile()
    end
end)