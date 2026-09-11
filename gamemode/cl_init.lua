// Client entry point: shared state first, then player, camera, and HUD presentation systems.
include( "shared.lua" )
include( "cl_skin.lua" )
include( "cl_player.lua" )
include( "cl_thirdpersoncamera.lua" )
include( "cl_transitions.lua" )
include( "cl_hud.lua" )
include( "cl_crosshair.lua" )
include( "cl_atmosphere.lua" )
include( "cl_preview.lua" )
include( "cl_dependency_prompts.lua" )
include( "cl_scoreboard.lua" )
include( "cl_world_map.lua" )
include( "cl_map_batch.lua" )
include( "cl_quick_menu.lua" )

// The server has updated NWInts; mirror them into the local Player extension table.
net.Receive("ZM.RefreshPlayerAttributes", function(len, ply)
    LocalPlayer():SetPlayerAttributes()
end)

// The server sends an authoritative core-data snapshot with each player-data refresh.
net.Receive("ZM.RefreshPlayerData", function()
    LocalPlayer():SetPlayerData(util.JSONToTable(net.ReadString()) or {})
    if ZM_Atmosphere and ZM_Atmosphere.ApplyPlayerProfile then
        ZM_Atmosphere:ApplyPlayerProfile()
    end
end)