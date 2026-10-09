return function(createEngine, loadFactory)
local Tests = {}
ZM_AtmosphereTests = Tests

function Tests.NewFixture(options)
    local env = createEngine()
    for key, value in pairs(options or {}) do env.State[key] = value end
    local function loadModule(name)
        local factory = loadFactory( name )
        setfenv(factory, env)
        return factory
    end
    env.include = loadModule
    local atmosphere = options and options.cachedStart and {} or { SnowCoverAmount = 0 }
    local initialize = loadModule("atmosphere/cl_core.lua")
    initialize(atmosphere)
    return atmosphere, env.State, env, initialize
end

function Tests.Run()
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("fixture_rejects_unmodeled_engine_calls_without_live_fallback", function(check)
        local env = createEngine()
        local ok, message = pcall(function() return env.RunConsoleCommand end)
        check(not ok and tostring(message):find("Unsupported atmosphere fixture global", 1, true), "unknown global fails explicitly")
        local particle = env.ParticleEmitter(env.Vector()):Add("fixture", env.Vector())
        ok, message = pcall(function() particle:UnknownFixtureMethod() end)
        check(not ok and tostring(message):find("Unsupported atmosphere fixture particle method", 1, true), "unknown particle method is not a no-op")
    end)
    suite:Add("all_modules_ready_before_callbacks_and_public_tables_keep_identity", function(check)
        local atmosphere, state = Tests.NewFixture()
        check(atmosphere.ModulesReady, "synchronous initialization completes")
        for _, name in ipairs({ "Core", "Environment", "Weather", "Puddles", "Snow", "Footsteps", "ScreenEffects", "Fog", "Diagnostics" }) do
            check(type(atmosphere.Modules[name].RegisterHooks) == "function", name .. " callback definitions available")
        end
        check(atmosphere.PuddleSites == atmosphere.Modules.Environment.SurfaceSites, "surface sites retain public identity")
        check(atmosphere.WetPuddles == atmosphere.Modules.Puddles.Items, "puddles retain public identity")
        check(atmosphere.SnowCover == atmosphere.Modules.Snow.Cover, "snow retains public identity")
        check(state.hooks.Think["ZM.Atmosphere.SnowCover"] ~= nil, "snow update registered")
        check(state.hooks.RenderScreenspaceEffects["ZM.Atmosphere.ColourCorrection"] ~= nil, "screen composition registered")
    end)
    suite:Add("profile_and_weather_messages_before_world_data_converge", function(check)
        local atmosphere, state = Tests.NewFixture({ worldReady = false })
        state.net = { 1 }
        state.receivers["ZM.SetAtmosphereProfile"]()
        state:Weather(2, 0.6)
        check(atmosphere.PendingProfileIndex == 1 and atmosphere.ActiveProfileIndex == nil, "profile queued before world readiness")
        check(atmosphere.WeatherSynced and atmosphere.Weather == "snow" and atmosphere.SnowCoverAmount == 0.6, "weather sync is independent")
        state.worldReady = true
        state:Hook("Think", "ZM.Atmosphere.WaitForWorldData")
        check(atmosphere.ActiveProfileIndex == 1 and atmosphere.PendingProfileIndex == nil, "queued profile applies once")
        local count = #atmosphere.ProfileApplications
        state:Hook("Think", "ZM.Atmosphere.WaitForWorldData")
        check(#atmosphere.ProfileApplications == count, "no duplicate pending application")
    end)
    suite:Add("invalid_messages_do_not_change_valid_weather_or_cover", function(check)
        local atmosphere, state = Tests.NewFixture()
        state:Weather(1, 0.25)
        state:Weather(3, 0.9)
        check(atmosphere.Weather == "rain" and atmosphere.SnowCoverAmount == 0.25, "invalid code preserves valid state")
        check(not atmosphere:SetWeather("unknown") and atmosphere.Weather == "rain", "invalid name reports failure")
        state:Weather(2, 0 / 0)
        check(atmosphere.SnowCoverAmount == 0.25, "NaN sync does not poison cover")
        check(#state.errors == 2, "both invalid weather inputs report errors")
    end)
    suite:Add("cached_snow_preloads_before_first_server_sync", function(check)
        local atmosphere, state = Tests.NewFixture({
            cachedStart = true, cookies = { zombiesim_snow_cover = "0.6", zombiesim_weather = "snow" }
        })
        check(atmosphere.SnowCoverAmount == 0.6 and atmosphere.CachedWeather == "snow", "cached winter state restored")
        state:Hook("Think", "ZM.Atmosphere.SnowCover")
        check(atmosphere.SnowCoverAmount > 0.6 and state.holds.snowCover, "cached snow settles instead of melting before sync")
        state:Weather(0, 0)
        state:Advance()
        state:Hook("Think", "ZM.Atmosphere.SnowCover")
        check(not state.holds.snowCover and atmosphere.SnowCoverAmount == 0, "authoritative clear sync releases preload")
    end)
    suite:Add("one_deadline_per_frame_including_loading_preload", function(check)
        local atmosphere, state = Tests.NewFixture()
        local environment = atmosphere.Modules.Environment
        local first = environment.GetAtmosphereWorkDeadline()
        state.time = state.time + 0.001
        check(environment.GetAtmosphereWorkDeadline() == first, "other subsystem cannot replenish same-frame budget")
        atmosphere.SnowCover.preloadStep = 1
        check(environment.GetAtmosphereWorkDeadline() == first, "preload cannot expand an already allocated frame")
        state:Advance()
        check(math.abs(environment.GetAtmosphereWorkDeadline() - state.time - 0.05) < 0.000001, "preload gets original 50ms budget next frame")
    end)
    suite:Add("surface_sampling_is_shared_and_map_cleanup_keeps_table_identity", function(check)
        local atmosphere, state = Tests.NewFixture()
        local environment = atmosphere.Modules.Environment
        check(environment.EnsureSurfaceSites(), "shared surface sampler initializes")
        check(#atmosphere.PuddleSites == 192, "original site capacity")
        local sites, puddles, cover = atmosphere.PuddleSites, atmosphere.WetPuddles, atmosphere.SnowCover
        atmosphere.Modules.Footsteps.Splashes[1] = {}
        atmosphere.Modules.Puddles.PuddleSiteDebt = 3
        state:Hook("PreCleanupMap", "ZM.Atmosphere.WeatherCleanup")
        check(atmosphere.PuddleSites == sites and atmosphere.WetPuddles == puddles and atmosphere.SnowCover == cover, "cleanup does not detach public tables")
        check(#sites == 0 and #puddles == 0 and #atmosphere.Modules.Footsteps.Splashes == 0, "owned records cleared")
        check(environment.WorldMinimum == nil and atmosphere.Modules.Puddles.PuddleSiteDebt == 0, "bounds and work debt cleared")
        check(environment.EnsureSurfaceSites(), "sampler rebuilds after cleanup")
    end)
    suite:Add("capture_hides_active_new_and_draining_emitters_and_shutdown_finishes_once", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        local weather = atmosphere.Modules.Weather
        local first = weather.GetEmitter(env.Vector())
        atmosphere:SetMapCaptureHidden(true)
        check(first.hidden, "active emitter hidden")
        atmosphere:StopWeatherEffects()
        local second = weather.GetEmitter(env.Vector())
        check(second.hidden, "new emitter inherits capture hiding")
        atmosphere:SetMapCaptureHidden(false)
        check(not first.hidden and not second.hidden, "active and draining emitters restored")
        state:Hook("ShutDown", "ZM.Atmosphere.WeatherCleanup")
        check(first.finished == 1 and second.finished == 1, "all emitters finished exactly once")
        check(#atmosphere.RetiredWeatherEmitters == 0, "draining emitter ownership cleared")
    end)
    suite:Add("rain_growth_drying_and_render_pass_guards", function(check)
        local atmosphere, state = Tests.NewFixture()
        state:Weather(1, 0)
        for _ = 1, 8 do
            state:Advance(0.55)
            state:Hook("Think", "ZM.Atmosphere.WetPuddles")
        end
        check(#atmosphere.WetPuddles > 0, "rain creates original map-bound puddles")
        local count = #state.calls
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", true, false)
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", false, true)
        check(#state.calls == count, "depth and skybox passes produce no wet rendering")
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", false, false)
        check((atmosphere.PuddleRenderLobes or 0) > 0 and not state.meshOpen, "wet mesh renders with balanced nonempty batches")
        state:Weather(0, 0)
        state:Advance(3.1)
        state:Hook("Think", "ZM.Atmosphere.WetPuddles")
        check(#atmosphere.WetPuddles == 0, "original three-second drying completes")
    end)
    suite:Add("snow_preload_meshes_trails_and_quality_rebuild", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        state:Weather(2, 1)
        for _ = 1, 12 do
            state:Advance()
            state:Hook("Think", "ZM.Atmosphere.SnowCover")
        end
        check(atmosphere.SnowCover.status == "ready" and atmosphere.SnowCover.meshCount > 0, "settled snow builds real mesh records")
        check(state.holds.snowCover == false and atmosphere.SnowCover.preloadDone, "preload hold releases")
        check(atmosphere.SnowCover.troddenCount > 0, "walking carves snow trail")
        state:Hook("PreDrawTranslucentRenderables", "ZM.Atmosphere.SnowCover", false, false)
        check((atmosphere.SnowCover.drawCount or 0) > 0, "snow render hook runs")
        env.ZM_Quality.ConVars.snowDetail = { GetFloat = function() return 0.5 end }
        state:Advance()
        state:Hook("Think", "ZM.Atmosphere.SnowCover")
        check(atmosphere.SnowCover.detail == 0.5, "quality change resamples cover")
        check(state.meshes[1].destroyed, "old snow mesh is destroyed before replacement")
    end)
    suite:Add("snow_preload_timeout_releases_loading_hold", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        env.util.TraceLine = function() state.time = state.time + 0.1 return { Hit = false } end
        state:Weather(2, 1)
        state:Hook("Think", "ZM.Atmosphere.SnowCover")
        state:Advance(13)
        state:Hook("Think", "ZM.Atmosphere.SnowCover")
        check(state.holds.snowCover == false and atmosphere.SnowCover.preloadResult == "timed out", "unfinished preload releases after original timeout")
    end)
    suite:Add("map_capture_skips_transient_wet_effects_but_keeps_snow", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        state:Weather(2, 1)
        for _ = 1, 12 do state:Advance() state:Hook("Think", "ZM.Atmosphere.SnowCover") end
        env.ZM_WorldMap.Capturing = true
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", false, false)
        check(#state.calls == 0, "capture has no transient wet-surface drawing")
        state:Hook("PreDrawTranslucentRenderables", "ZM.Atmosphere.SnowCover", false, false)
        check((atmosphere.SnowCover.drawCount or 0) > 0, "lying snow remains in level captures")
    end)
    suite:Add("screenspace_quality_preserves_frost_and_radiation_without_grain", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        atmosphere:ApplyProfile(1, "fixture")
        atmosphere.FrostAmount = 1
        env.ZM_Quality.ConVars.screenEffects = { GetFloat = function() return 0 end }
        state.radiation = 0.5
        state.convars.zombiesim_atmosphere_grain.value = 1
        state:Hook("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection")
        local rects, grade = 0, nil
        for _, call in ipairs(state.calls) do
            if call[1] == "DrawRect" then rects = rects + 1 end
            if call[1] == "DrawColorModify" then grade = call[2] end
        end
        check(rects == 72, "18 frost strips per edge, no grain at low quality")
        check(grade and grade["$pp_colour_colour"] == 0.5, "radiation composition still applies")
        state.calls = {}
        env.ZM_Quality.ConVars.screenEffects = nil
        state:Hook("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection")
        rects = 0
        for _, call in ipairs(state.calls) do if call[1] == "DrawRect" then rects = rects + 1 end end
        check(rects == 124, "original frost plus 52 grain rectangles")
    end)
    suite:Add("fog_cache_launcher_and_den_contexts", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        atmosphere:ApplyProfile(1, "fixture")
        local fog = atmosphere:GetFogSettings()
        check(atmosphere:GetFogSettings() == fog and fog.finish == 1600, "fog table cached per frame")
        check(state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog") == true, "world fog retains true return")
        check(atmosphere.Modules.Snow.FogCullDistance == 1600, "opaque fog feeds snow culling")
        env.ZM_LauncherMenu.Active = true
        state.launcherFog = { start = 10, finish = 100, maxDensity = 0.8, color = { 1, 2, 3 } }
        check(state:Hook("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", 0.0625) == true, "launcher preview supplies fog")
        state.calls = {}
        state:Hook("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection")
        check(#state.calls == 0, "launcher bypasses gameplay grade and frost")
        env.ZM_LauncherMenu.Active = false
        state.inDen = true
        state:Weather(1, 0)
        state:Hook("Think", "ZM.Atmosphere.WeatherEffects")
        check(#state.emitters == 0, "den does not emit precipitation")
    end)
    suite:Add("singleplayer_distance_steps_and_multiplayer_prediction", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        state:Weather(1, 0)
        for _ = 1, 4 do state:Advance(0.55) state:Hook("Think", "ZM.Atmosphere.WetPuddles") end
        for _ = 1, 12 do
            state:Advance()
            state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", false, false)
        end
        state:Hook("Think", "ZM.Atmosphere.WeatherFootsteps")
        for _ = 1, 3 do
            state.player.position = state.player.position + env.Vector(25, 0, 0)
            state:Hook("Think", "ZM.Atmosphere.WeatherFootsteps")
        end
        check(atmosphere.StepCount == 1, "singleplayer distance produces one step")
        state.singlePlayer = false
        local before = atmosphere.StepCount
        state.predicted = false
        state:Hook("PlayerFootstep", "ZM.Atmosphere.RainFootstepSplash", state.player, env.Vector())
        check(atmosphere.StepCount == before, "replayed predicted step produces no duplicate")
        state.predicted = true
        state:Hook("PlayerFootstep", "ZM.Atmosphere.RainFootstepSplash", state.player, env.Vector())
        check(atmosphere.StepCount == before + 1, "first predicted puddle step is recorded")
    end)
    suite:Add("reinitialization_replaces_hooks_without_orphaning_emitters", function(check)
        local atmosphere, state, env, initialize = Tests.NewFixture()
        atmosphere.Modules.Weather.GetEmitter(env.Vector())
        local previous, sites = atmosphere.Modules, atmosphere.PuddleSites
        initialize(atmosphere)
        check(atmosphere.Modules ~= previous and atmosphere.ModulesReady, "new module closures ready")
        check(state.emitters[1].finished == 1 and #atmosphere.RetiredWeatherEmitters == 0, "previous emitter shut down")
        check(atmosphere.PuddleSites == sites, "persistent sites retained")
        local count = 0
        for name in pairs(state.hooks.Think) do if name:find("ZM.Atmosphere.", 1, true) then count = count + 1 end end
        check(count == 8, "same eight Think hooks, no duplicate registrations")
    end)
    return suite:Run()
end

concommand.Add("zombiesim_dev_test_atmosphere_client", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Client atmosphere tests require a preview admin.\n")
        return
    end
    local summary = Tests.Run()
    local live = ZM_TestHarness.NewSuite()
    live:Add("live_module_ownership_and_registered_callbacks", function(check)
        local atmosphere = ZM_Atmosphere
        check(atmosphere.ModulesReady, "live client finished module initialization")
        check(atmosphere.PuddleSites == atmosphere.Modules.Environment.SurfaceSites, "live sampling table is attached")
        check(atmosphere.WetPuddles == atmosphere.Modules.Puddles.Items, "live puddle table is attached")
        check(atmosphere.SnowCover == atmosphere.Modules.Snow.Cover, "live snow table is attached")
        for _, spec in ipairs({
            { "Think", "ZM.Atmosphere.WeatherEffects" }, { "Think", "ZM.Atmosphere.WetPuddles" },
            { "Think", "ZM.Atmosphere.SnowCover" }, { "RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection" },
            { "SetupWorldFog", "ZM.Atmosphere.WorldFog" }, { "SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog" }
        }) do
            check(type((hook.GetTable()[spec[1]] or {})[spec[2]]) == "function", "live " .. spec[2] .. " registered")
        end
    end)
    live:Add("live_diagnostic_contract_and_materials", function(check)
        local snapshot = ZM_Atmosphere:GetDiagnosticSnapshot()
        summary.live = snapshot
        check(snapshot.worldDataLoaded and snapshot.playerValid, "actual world and player are ready")
        check(snapshot.snowCoverTextured and not snapshot.puddleMaterialError, "snow texture and wet materials available")
        check(snapshot.splashRingMaterialAvailable and snapshot.footstepSplashMaterialAvailable, "approved splash materials available")
        check(type(snapshot.hookResults) == "table" and type(snapshot.profileApplications) == "table", "existing diagnostic shape retained")
    end)
    local liveSummary = live:Run()
    summary.passed, summary.failed = summary.passed + liveSummary.passed, summary.failed + liveSummary.failed
    for _, result in ipairs(liveSummary.cases) do summary.cases[#summary.cases + 1] = result end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/atmosphere_client_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
    end
    print(string.format("[ZombieSim] Client atmosphere tests: %d passed, %d failed.", summary.passed, summary.failed))
end)
end
