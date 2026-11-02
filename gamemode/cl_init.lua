// Client entry point: shared state first, then player, camera, and HUD presentation systems.
include( "shared.lua" )
include( "sh_characters.lua" )
include( "sh_launcher_scene.lua" )
include( "sh_launcher_presentation.lua" )
include( "cl_skin.lua" )
include( "cl_quality.lua" )
include( "cl_csm.lua" )
include( "cl_chest_lamp.lua" )
include( "cl_player.lua" )
include( "cl_thirdpersoncamera.lua" )
include( "cl_prefab_guard_preview.lua" )
include( "cl_prefab_editor.lua" )
include( "cl_prefab_light_preview.lua" )
include( "cl_prefab_world_lights.lua" )
include( "cl_prefab_particle_probe.lua" )
include( "cl_prefab_particle_world.lua" )
include( "cl_prefab_explorer.lua" )
include( "cl_prefab_spotlight_probe.lua" )
if game.GetMap() == "zn_dev_prefab_anchor" then
    include( "prefabs/cl_fixture_scale_sync.lua" )({
        IsValid = IsValid, CurTime = CurTime, ErrorNoHalt = ErrorNoHalt, hook = hook, timer = timer
    })
end
include( "tests/cl_prefab_fixture_trace.lua" )( include( "prefabs/sh_fixture_trace.lua" ) )
include( "cl_transitions.lua" )
include( "sh_walker_preload.lua" )
local initializeTransitionMarkers = include( "cl_transition_markers.lua" )
ZM_TransitionMarkers = ZM_TransitionMarkers or {}
initializeTransitionMarkers(ZM_TransitionMarkers)
include( "cl_hud.lua" )
include( "cl_damage_feedback.lua" )
include( "cl_radiation_feedback.lua" )
include( "cl_radiated_zombies.lua" )
include( "cl_crosshair.lua" )
include( "cl_weapon_effects.lua" )
include( "cl_atmosphere.lua" )
include( "cl_skybox.lua" )
include( "cl_sky_catalogue.lua" )
include( "cl_sky_palettes.lua" )
include( "cl_sky_browser.lua" )
include( "cl_sky_inspection.lua" )
include( "cl_preview.lua" )
include( "cl_dependency_prompts.lua" )
ZM_LauncherProfessionPicker = include( "cl_launcher_profession_picker.lua" )
include( "cl_launcher_menu.lua" )
include( "cl_launcher_scene.lua" )
include( "cl_pause_log.lua" )
include( "cl_dev_profiler.lua" )
include( "cl_clothing_preview.lua" )
include( "cl_clothing.lua" )
include( "cl_character_cards.lua" )
include( "cl_wardrobe.lua" )
include( "utils/test_harness.lua" )
include( "tests/cl_prefab_editor_map_engine_tests.lua" )(
    include( "prefabs/sh_editor_map.lua" )( include( "prefabs/sh_contract.lua" ) )
)
include( "tests/cl_character_cards_tests.lua" )
ZM_LauncherProfessionPicker.Tests = include( "tests/cl_launcher_profession_picker_tests.lua" )(ZM_LauncherProfessionPicker)
include( "tests/cl_launcher_presentation_tests.lua" )
include( "tests/cl_chest_lamp_tests.lua" )
include( "tests/cl_csm_tests.lua" )
include( "tests/cl_transition_markers_tests.lua" )(
    include( "tests/fixtures/cl_transition_markers_engine.lua" ),
    function(path)
        assert(path == "cl_transition_markers.lua", "Unknown transition marker test module: " .. tostring(path))
        return initializeTransitionMarkers
    end
)
local atmosphereTestFactories = {
    ["atmosphere/cl_core.lua"] = include( "atmosphere/cl_core.lua" ),
    ["atmosphere/cl_environment.lua"] = include( "atmosphere/cl_environment.lua" ),
    ["atmosphere/cl_weather.lua"] = include( "atmosphere/cl_weather.lua" ),
    ["atmosphere/cl_puddles.lua"] = include( "atmosphere/cl_puddles.lua" ),
    ["atmosphere/cl_snow.lua"] = include( "atmosphere/cl_snow.lua" ),
    ["atmosphere/cl_footsteps.lua"] = include( "atmosphere/cl_footsteps.lua" ),
    ["atmosphere/cl_screen_effects.lua"] = include( "atmosphere/cl_screen_effects.lua" ),
    ["atmosphere/cl_fog.lua"] = include( "atmosphere/cl_fog.lua" ),
    ["atmosphere/cl_world_haze.lua"] = include( "atmosphere/cl_world_haze.lua" ),
    ["atmosphere/cl_diagnostics.lua"] = include( "atmosphere/cl_diagnostics.lua" )
}
include( "tests/cl_atmosphere_tests.lua" )(
    include( "tests/fixtures/cl_atmosphere_engine.lua" ),
    function(path)
        assert( atmosphereTestFactories[path], "Unknown atmosphere test module: " .. path )
        return atmosphereTestFactories[path]
    end
)
include( "tests/cl_clothing_tests.lua" )
include( "tests/cl_imported_assets_tests.lua" )
include( "tests/cl_sky_catalogue_tests.lua" )
local createCallingCardState = include( "cl_calling_card_state.lua" )
local initializeCallingCards = include( "cl_calling_cards.lua" )
initializeCallingCards(createCallingCardState)
include( "tests/cl_calling_card_state_tests.lua" )(createCallingCardState)
include( "tests/cl_calling_card_ui_tests.lua" )(
    include( "tests/fixtures/cl_calling_card_engine.lua" ),
    function(path)
        assert(path == "cl_calling_cards.lua", "Unknown calling-card UI test module: " .. tostring(path))
        return initializeCallingCards
    end,
    createCallingCardState
)
include( "cl_scoreboard.lua" )
include( "cl_foliage.lua" )
include( "cl_gore.lua" )
include( "cl_music.lua" )
include( "tests/cl_credits_probe.lua" )(ZM_LauncherMenu, ZM_LauncherSceneClient, ZM_Music)
include( "cl_world_map.lua" )
include( "cl_world_capture.lua" )
include( "cl_cell_health.lua" )
include( "tests/cl_cell_health_tests.lua" )
include( "cl_map_batch.lua" )
include( "cl_quick_menu.lua" )
include( "cl_afk.lua" )
include( "cl_item_icons.lua" )
include( "cl_changelog.lua" )
include( "cl_third_party_licenses.lua" )
include( "cl_launcher_tools.lua" )
include( "cl_inventory.lua" )
include( "cl_crafting.lua" )
include( "cl_mastercraft.lua" )
include( "cl_bank.lua" )
include( "cl_professions.lua" )
include( "cl_trading.lua" )
include( "cl_loot_popup.lua" )
include( "tests/cl_csm_feasibility_probe.lua" )

// The server has updated NWInts; mirror them into the local Player extension table.
net.Receive("ZM.RefreshPlayerAttributes", function(len, ply)
    LocalPlayer():SetPlayerAttributes()
    ZM_Loading:Step("Synced survivor attributes")
end)

// The server sends an authoritative core-data snapshot with each player-data refresh.
net.Receive("ZM.RefreshPlayerData", function()
    local snapshot = util.JSONToTable(net.ReadString()) or {}
    LocalPlayer():SetPlayerData(snapshot)
    ZM_Loading:Step("Synced survivor data")
    if ZM_Atmosphere and ZM_Atmosphere.ApplyPlayerProfile then
        ZM_Atmosphere:ApplyPlayerProfile("player data refresh")
    end
end)