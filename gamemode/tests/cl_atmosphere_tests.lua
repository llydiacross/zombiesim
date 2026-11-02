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
        for _, name in ipairs({ "Core", "Environment", "Weather", "Puddles", "Snow", "Footsteps", "ScreenEffects", "Fog", "WorldHaze", "Diagnostics" }) do
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
    suite:Add("precipitation_spawns_in_open_sky_and_continues_under_cover", function(check)
        local atmosphere, state = Tests.NewFixture()
        local weather = atmosphere.Modules.Weather
        // Awning over the player and a large roof east of them; everything else is open sky.
        state.roofs = {
            { minX = -100, maxX = 100, minY = -100, maxY = 100, bottom = 200, top = 232 },
            { minX = 300, maxX = 2400, minY = -3000, maxY = 3000, bottom = 300, top = 340 }
        }
        local function covered(position)
            for _, roof in ipairs(state.roofs) do
                if position.x >= roof.minX and position.x <= roof.maxX and position.y >= roof.minY
                    and position.y <= roof.maxY and position.z < roof.bottom then
                    return true
                end
            end
            return false
        end
        for code, name in pairs({ [1] = "rain", [2] = "snow" }) do
            state:Weather(code, 0)
            for _ = 1, 40 do
                state:Advance(0.11)
                state:Hook("Think", "ZM.Atmosphere.WeatherEffects")
            end
            local emitter = weather.GetEmitter(state.player:EyePos())
            local precipitation, misplaced = 0, 0
            for _, spawn in ipairs(emitter.spawns or {}) do
                if spawn.material == (name == "rain" and "effects/laser_tracer" or "particle/snow") then
                    precipitation = precipitation + 1
                    if covered(spawn.position) then misplaced = misplaced + 1 end
                end
            end
            check(weather.Diagnostics.sheltered == true, name .. " player is sheltered by the awning")
            check(precipitation > 0, name .. " keeps falling outside while sheltered")
            check(misplaced == 0, name .. " never spawns beneath a roof")
            check((weather.Diagnostics.precipitationCoveredRejected or 0) > 0, name .. " rejects covered columns")
            atmosphere:StopWeatherEffects()
        end
        state.roofs = { state.roofs[1] }
        state:Weather(1, 0)
        for _ = 1, 20 do
            state:Advance(0.11)
            state:Hook("Think", "ZM.Atmosphere.WeatherEffects")
        end
        check((weather.Diagnostics.precipitationFarSpawned or 0) > 0, "rain fills the distant band")
        check(atmosphere.RainSoundSheltered == true, "sheltered rain ambience is softened, not stopped")

        // A skybox ceiling beyond trace range reports no hit at all; that is open sky, as in the shelter check.
        local distant, distantState = Tests.NewFixture()
        distantState.skyOutOfRange = true
        distantState:Weather(1, 0)
        for _ = 1, 20 do
            distantState:Advance(0.11)
            distantState:Hook("Think", "ZM.Atmosphere.WeatherEffects")
        end
        local distantDiagnostics = distant.Modules.Weather.Diagnostics
        check((distantDiagnostics.precipitationNearSpawned or 0) > 0, "rain spawns when the sky is beyond trace range")
        check((distantDiagnostics.precipitationCoveredRejected or 0) == 0, "an out-of-range sky is not treated as cover")
    end)
    suite:Add("rain_runoff_finds_open_roof_edges_and_rejects_walled_rooms", function(check)
        local atmosphere, state = Tests.NewFixture()
        local weather = atmosphere.Modules.Weather
        state.player.position.x = -200
        state.roofs = { { minX = -400, maxX = 0, minY = -400, maxY = 400, bottom = 200, top = 240 } }
        state:Weather(1, 0)
        for _ = 1, 120 do
            state:Advance(0.13)
            state:Hook("Think", "ZM.Atmosphere.WeatherEffects")
        end
        local edges = weather.RunoffEdges
        check(#edges > 0, "open roof edges are found")
        local outside = true
        for _, edge in ipairs(edges) do
            local p = edge.position
            local nearEdge = (p.x > 0 and p.x < 12) or (p.x < -400 and p.x > -412)
                or (p.y > 400 and p.y < 412) or (p.y < -400 and p.y > -412)
            if not nearEdge or math.abs(p.z - 198) > 0.01 then outside = false end
        end
        check(outside, "drip points sit just outside the roof edge below the roof")
        check((weather.Diagnostics.runoffDrips or 0) > 0, "edges emit drip streams")
        state:Weather(0, 0)
        state:Hook("Think", "ZM.Atmosphere.WeatherEffects")
        check(#edges == 0, "stopping rain clears cached edges")

        local walled, walledState = Tests.NewFixture()
        walledState.player.position.x = -200
        walledState.roofs = { { minX = -400, maxX = 0, minY = -400, maxY = 400, bottom = 200, top = 240 } }
        walledState.walls = {
            { minX = -16, maxX = 0, minY = -400, maxY = 400, bottom = 0, top = 240 },
            { minX = -400, maxX = -384, minY = -400, maxY = 400, bottom = 0, top = 240 },
            { minX = -400, maxX = 0, minY = -400, maxY = -384, bottom = 0, top = 240 },
            { minX = -400, maxX = 0, minY = 384, maxY = 400, bottom = 0, top = 240 }
        }
        walledState:Weather(1, 0)
        for _ = 1, 120 do
            walledState:Advance(0.13)
            walledState:Hook("Think", "ZM.Atmosphere.WeatherEffects")
        end
        local walledWeather = walled.Modules.Weather
        check(#walledWeather.RunoffEdges == 0, "enclosed rooms produce no runoff edges")
        check((walledWeather.Diagnostics.runoffWallRejected or 0) > 0, "walls between probe and opening are rejected")
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
    suite:Add("prefab_fog_and_dark_grade_are_scoped_to_the_editor", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        state.convars.zombiesim_fog_style.value = "legacy"
        atmosphere:ApplyProfile(1, "fixture")
        local editor = { active = true, PreviewFog = nil, PreviewDark = false }
        function editor:IsActive() return self.active end
        env.ZM_PrefabEditorClient = editor

        state.calls = {}
        check(state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog") == true, "editor disables world fog by default")
        check(state.calls[1][1] == "FogMode" and state.calls[1][2] == env.MATERIAL_FOG_NONE,
            "fog-off uses the engine's no-fog mode")
        editor.PreviewFog = { start = 350, finish = 1450, maxDensity = 0.82, color = { 122, 132, 141 } }
        state.calls = {}
        check(state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog") == true, "editor world fog is applied")
        check(state.calls[2][1] == "FogStart" and state.calls[2][2] == 350
            and state.calls[3][1] == "FogEnd" and state.calls[3][2] == 1450,
            "the representative profile distances are preserved")
        state.calls = {}
        check(state:Hook("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", 0.0625) == true, "editor skybox fog is applied")
        check(state.calls[2][2] == 350 * 0.0625 and state.calls[3][2] == 1450 * 0.0625,
            "the skybox uses engine scale")

        editor.PreviewDark = true
        state.calls = {}
        state:Hook("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection")
        check(state.calls[1] and state.calls[1][1] == "DrawColorModify"
            and state.calls[1][2]["$pp_colour_brightness"] == -0.15,
            "the explicitly simulated dark grade is used")
        editor.active = false
        state.calls = {}
        state:Hook("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection")
        check(state.calls[1] and state.calls[1][1] == "DrawColorModify"
            and state.calls[1][2]["$pp_colour_brightness"] == 0,
            "leaving the editor restores normal atmosphere grading")
        state.calls = {}
        check(state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog") == true and state.calls[2][2] == 100,
            "leaving the editor restores the original profile fog")
    end)
    suite:Add("capture_fog_is_scoped_nested_and_preserves_native_cache", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        state.convars.zombiesim_fog_style.value = "legacy"
        atmosphere:ApplyProfile(1, "fixture")
        local cached = atmosphere:GetFogSettings()
        atmosphere.Modules.Snow.FogCullDistance = 123
        local token = atmosphere:BeginWorldCaptureFog("clear")
        check(state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog") == true, "clear owns world fog")
        check(state:Hook("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", 0.0625) == true, "clear owns sky fog")
        check(atmosphere.Modules.Snow.FogCullDistance == nil, "clear disables fog culling")
        local nested = atmosphere:BeginWorldCaptureFog("atmospheric")
        atmosphere:EndWorldCaptureFog(nested)
        check(atmosphere.WorldCaptureFogVariant == "clear", "nested restoration")
        atmosphere:EndWorldCaptureFog(token)
        check(atmosphere.WorldCaptureFogVariant == nil and atmosphere.Modules.Snow.FogCullDistance == 123,
            "original renderer state restored")
        check(atmosphere:GetFogSettings() == cached and cached.finish == 1600, "native cache and profile untouched")
    end)
    suite:Add("layered_fog_is_gentle_and_tinted_by_radiation", function(check)
        local atmosphere, state = Tests.NewFixture()
        atmosphere:ApplyProfile(1, "fixture")
        check(atmosphere:GetFogStyle() == "layered", "layered is the default style")
        local fog = atmosphere:GetFogSettings()
        check(fog.style == "layered" and math.abs(fog.start - 140) < 0.001 and math.abs(fog.finish - 2560) < 0.001,
            "layered fog starts later and ends further away")
        check(math.abs(fog.maxDensity - 0.45) < 0.001, "layered fog is gentle")
        check(fog.color[1] == 100 and fog.color[2] == 120 and fog.color[3] == 140, "clean cells keep the profile colour")
        check(fog.radiation == 0 and fog.skyColor[1] == 100 and fog.skyColor[3] == 140, "clean sky fog matches the world fog")
        check(state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog") == true, "layered world fog is applied")
        check(atmosphere.Modules.Snow.FogCullDistance == nil, "translucent layered fog never culls snow")
        function state.player:GetRadiationIntensity() return 1 end
        state:Advance(0.1)
        local easing = atmosphere:GetFogSettings()
        check(easing.radiation > 0 and easing.radiation < 0.1 and easing.finish > 2400,
            "radiation eases in over seconds rather than popping")
        state:Advance(30)
        local radiated = atmosphere:GetFogSettings()
        local function near(value, expected) return math.abs(value - expected) < 0.2 end
        check(near(radiated.radiation, 1) and near(radiated.color[1], 149) and near(radiated.color[2], 100.4)
            and near(radiated.color[3], 70), "radiated cells converge on the burnt-orange sky tint")
        check(near(radiated.start, 105) and near(radiated.finish, 1664) and near(radiated.maxDensity, 0.7),
            "radiated fog closes in and thickens gently")
        check(near(radiated.skyColor[1], 101.4) and near(radiated.skyColor[2], 63.44) and near(radiated.skyColor[3], 39),
            "radiated sky fog is a darker orange")
        state.convars.zombiesim_fog_style.value = "legacy"
        state:Advance()
        local legacy = atmosphere:GetFogSettings()
        check(legacy.style == "legacy" and legacy.finish == 1600 and legacy.maxDensity == 1
            and legacy.color[1] == 100 and legacy.radiation == nil and legacy.skyColor == nil,
            "legacy restores the original fog exactly")
        function state.player:GetRadiationIntensity() return 0 end
        state.convars.zombiesim_fog_style.value = "layered"
        state:Advance()
        local restored = atmosphere:GetFogSettings()
        check(restored.radiation == 0 and math.abs(restored.finish - 2560) < 0.001,
            "returning to layered snaps to the current target")
    end)
    suite:Add("top_down_camera_fades_layered_fog_and_world_haze", function(check)
        local atmosphere, state = Tests.NewFixture()
        atmosphere:ApplyProfile(1, "fixture")
        local haze = atmosphere.Modules.WorldHaze
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        state:Advance(3)
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        local freeAlpha = haze.GetDiagnostics().alpha
        check(freeAlpha > 0.002, "free camera draws world haze")
        state.topDown = 1
        state:Advance()
        local fog = atmosphere:GetFogSettings()
        check(fog.topDown == 1 and fog.maxDensity == 0 and math.abs(fog.finish - 2560) < 0.001,
            "top-down camera fades the layered fog density out without moving its range")
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        local diagnostics = haze.GetDiagnostics()
        check(diagnostics.alpha == 0 and diagnostics.topDown == 1 and diagnostics.frameCurtains == 0
            and diagnostics.frameMist == 0, "top-down camera hides curtains and mist")
        state.topDown = 0.5
        state:Advance()
        fog = atmosphere:GetFogSettings()
        check(math.abs(fog.maxDensity - 0.225) < 0.001, "the fade follows the camera glide weight")
        state.convars.zombiesim_fog_style.value = "legacy"
        state.topDown = 1
        state:Advance()
        local legacy = atmosphere:GetFogSettings()
        check(legacy.maxDensity == 1 and legacy.topDown == nil, "legacy fog is never faded")
    end)
    local function newHazeFixture(options)
        local atmosphere, state, env = Tests.NewFixture(options)
        atmosphere:ApplyProfile(1, "fixture")
        return atmosphere, state, env, atmosphere.Modules.WorldHaze
    end
    local function countCalls(state, name)
        local count = 0
        for _, call in ipairs(state.calls) do if call[1] == name then count = count + 1 end end
        return count
    end
    suite:Add("world_haze_builds_static_side_curtains_per_tier", function(check)
        local atmosphere, state, env, haze = newHazeFixture()
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        local diagnostics = haze.GetDiagnostics()
        check(diagnostics.active and diagnostics.tier == "high" and diagnostics.builds == 1, "high tier builds once")
        check(diagnostics.curtainQuads == 4 * 3 * 32 * 3, "four sides of three 32-column curtains")
        local sides = 0
        for _, imesh in pairs(haze.Meshes) do
            sides = sides + 1
            check(imesh.quads == 3 * 32 * 3, "each side mesh has its own quad count")
        end
        check(sides == 4, "one static mesh per side")
        local slanted, quadCount = true, 0
        for _, imesh in pairs(haze.Meshes) do
            local positions = imesh.positions or {}
            for index = 1, #positions - 3, 4 do
                local a, b = positions[index], positions[index + 1]
                quadCount = quadCount + 1
                // A slanted segment can only cross an axis-aligned brush face along a line, never lie in it.
                if math.abs(a.x - b.x) < 8 or math.abs(a.y - b.y) < 8 then slanted = false end
            end
        end
        check(quadCount == 4 * 3 * 32 * 3 and slanted, "no curtain segment is axis-aligned with brush faces")
        check(haze.Stats.innerN > 2240 and haze.Stats.innerN < 2880, "curtains stand in the traversable-to-seam band")
        state:Advance()
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(haze.GetDiagnostics().builds == 1, "unchanged cell reuses the static meshes")
        local convar = env.CreateClientConVar("zombiesim_world_haze", "1")
        env.ZM_Quality.ConVars.worldHaze = convar
        convar.value = 0.5
        local previous = haze.Meshes.N
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        diagnostics = haze.GetDiagnostics()
        check(diagnostics.tier == "low" and diagnostics.builds == 2 and diagnostics.curtainQuads == 4 * 2 * 16 * 3,
            "low tier rebuilds with two 16-column curtains")
        check(previous.destroyed, "replaced meshes are destroyed")
        convar.value = 0
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(not haze.Active and haze.Meshes.N == nil and haze.GetDiagnostics().reason == "disabled",
            "off destroys meshes and stays inactive")
    end)
    suite:Add("world_haze_fades_near_sides_and_never_draws_empty", function(check)
        local atmosphere, state, env, haze = newHazeFixture()
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        check(countCalls(state, "IMesh.Draw") == 4, "all four sides draw from the cell centre")
        check(haze.SideFade.N == 1 and haze.SideFade.S == 1, "distant sides draw at full strength")
        state.player.position = env.Vector(0, 2100, 0)
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        check(haze.SideFade.N == 0 and haze.SideFade.S == 1, "the side being approached clears, the far side stays")
        check(countCalls(state, "IMesh.Draw") == 3, "a fully faded side is skipped")
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", true, false)
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, true)
        check(#state.calls == 0, "depth and skybox passes draw nothing")
        state.player.position = env.Vector()
        for index = #haze.Sprites, 1, -1 do haze.Sprites[index] = nil end
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        check(countCalls(state, "mesh.Begin") == 0, "no mist sprites means no dynamic mesh.Begin")
    end)
    suite:Add("world_haze_mist_seeds_outdoors_within_limits", function(check)
        local atmosphere, state, env, haze = newHazeFixture()
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(#haze.Sprites <= 2, "at most two seeds per frame")
        for _ = 1, 60 do state:Advance() state:Hook("Think", "ZM.Atmosphere.WorldHaze") end
        check(#haze.Sprites == 64, "high tier fills the 64-sprite pool")
        for _, sprite in ipairs(haze.Sprites) do
            check(math.abs(sprite.x) <= 2880 and math.abs(sprite.y) <= 2880, "sprites stay inside the visual bounds")
        end
        state:Advance(3)
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        check(countCalls(state, "mesh.Begin") == 1 and haze.GetDiagnostics().frameMist > 0, "visible mist draws in one batch")
        local sheltered = newHazeFixture({ sheltered = true })
        local shelteredHaze = sheltered.Modules.WorldHaze
        for _ = 1, 20 do shelteredHaze.Update() end
        check(#shelteredHaze.Sprites == 0 and (shelteredHaze.Stats.seedAttempts or 0) > 0,
            "points without open sky are rejected")
    end)
    suite:Add("world_haze_inactive_in_legacy_den_capture_and_editor", function(check)
        local atmosphere, state, env, haze = newHazeFixture()
        for _ = 1, 5 do state:Advance() state:Hook("Think", "ZM.Atmosphere.WorldHaze") end
        check(#haze.Sprites > 0, "outdoor mist exists before the context change")
        state.convars.zombiesim_fog_style.value = "legacy"
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(not haze.Active and #haze.Sprites == 0 and haze.GetDiagnostics().reason == "legacy fog style",
            "legacy fog style disables haze and clears mist")
        state.convars.zombiesim_fog_style.value = "layered"
        state.inDen = true
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(haze.GetDiagnostics().reason == "not an outdoor city cell", "dens have no edge haze")
        state.inDen = false
        local token = atmosphere:BeginWorldCaptureFog("clear")
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(haze.GetDiagnostics().reason == "map capture", "map captures exclude haze")
        atmosphere:EndWorldCaptureFog(token)
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(haze.Active, "haze resumes after capture")
        env.ZM_WorldMap.Capturing = true
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        check(#state.calls == 0, "a capture starting between Think and render still suppresses drawing")
    end)
    suite:Add("world_haze_thickens_with_weather_and_radiation", function(check)
        local atmosphere, state, env, haze = newHazeFixture()
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        local clear = haze.Density
        state:Weather(1, 0)
        for _ = 1, 600 do state:Advance(0.1) state:Hook("Think", "ZM.Atmosphere.WorldHaze") end
        local rain = haze.Density
        check(rain > clear * 1.3 and rain <= 1.6, "rain eases the haze up within the cap")
        check(#haze.Ash == 0, "clean cells have no fallout ash")
        check(#haze.Embers == 0, "clean cells have no fire embers")
        function state.player:GetRadiationIntensity() return 1 end
        for _ = 1, 600 do state:Advance(0.1) state:Hook("Think", "ZM.Atmosphere.WorldHaze") end
        check(haze.Density > rain, "radiation thickens it further")
        local diagnostics = haze.GetDiagnostics()
        check(#haze.Ash > 0 and #haze.Ash <= 160 and diagnostics.ashTarget == 160, "radiated cells fill the ash pool to the tier")
        check(#haze.Embers > 0 and #haze.Embers <= 36 and diagnostics.emberTarget == 36, "radiated cells fill the ember pool to the tier")
        for _, ember in ipairs(haze.Embers) do
            check(ember.z <= state.player:EyePos().z + 500, "embers above the ceiling are removed")
        end
        for _, flake in ipairs(haze.Ash) do
            check(flake.z >= state.player:EyePos().z - 150, "ash below the floor is removed")
        end
        state.calls = {}
        state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", false, false)
        check(countCalls(state, "mesh.Begin") == 3 and haze.GetDiagnostics().frameAsh > 0
            and haze.GetDiagnostics().frameEmbers > 0, "ash, embers and mist each draw in one batch")
        local material = haze.CurtainMaterials.N
        check(material["$color"] and material["$color"].x > material["$color"].z, "radiated curtains take the tinted fog colour")
        check(material["$alpha"] > 0 and material["$alpha"] <= 1, "curtain alpha stays in range")
        function state.player:GetRadiationIntensity() return 0 end
        state:Advance(0.1)
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(haze.GetDiagnostics().ashTarget > 100, "ash fades out with the eased radiation rather than vanishing")
        state:Advance(60)
        state:Hook("Think", "ZM.Atmosphere.WorldHaze")
        check(haze.GetDiagnostics().ashTarget == 0, "ash stops seeding once radiation clears")
        check(haze.GetDiagnostics().emberTarget == 0, "embers stop seeding once radiation clears")
    end)
    suite:Add("fog_cache_launcher_and_den_contexts", function(check)
        local atmosphere, state, env = Tests.NewFixture()
        state.convars.zombiesim_fog_style.value = "legacy"
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
        check(count == 9, "same nine Think hooks, no duplicate registrations")
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
