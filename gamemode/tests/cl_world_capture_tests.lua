return function(createEngine, loadChunk)
    local Tests = {}
    ZM_WorldCaptureTests = Tests
    local function fixture()
        local contract = loadChunk("world_capture/sh_contract.lua")()
        local env, state = createEngine(contract)
        local chunk = loadChunk("cl_world_capture.lua")
        setfenv(chunk, env)
        chunk()
        return env.ZM_WorldCapture, env, state, contract
    end
    function Tests.Run()
        local suite = ZM_TestHarness.NewSuite()
        suite:Add("authoritative_hashes_bounds_and_path_contract", function(check)
            local _, _, state, contract = fixture()
            local revision = contract.Revision(state.world, "preview", state.skyline, string.rep("c", 64))
            check(revision.pitch == 5760 and revision.cameraZ == 4992, "full pitch at owning skyline ceiling")
            check(not contract.Revision(state.world, "preview"), "missing skyline rejected")
            check(not contract.Revision(state.world, "city"), "production rejected")
            check(not contract.OutputPath("../escape", 1, "clear"), "run traversal rejected")
            check(not contract.OutputPath("run", -1, "clear"), "negative cell rejected")
            check(not contract.OutputPath("run", 1, "native"), "unknown variant rejected")
            state.world.templatePlanSha256 = ""
            check(not contract.Revision(state.world, "preview"), "missing second hash rejected")
        end)
        suite:Add("north_up_flat_orthographic_projection_and_png_readback", function(check)
            local capture, env, state = fixture()
            local result = capture:Render(state.request)
            check(result.ok and result.ready and result.bytes == #state.png, "validated actual render output")
            check(state.view.ortho and state.view.ortholeft == -2880 and state.view.orthoright == 2880, "full footprint")
            check(state.view.ortho == true and state.view.angles.p == 90 and state.view.angles.y == 90
                and state.view.origin.z == 4992, "native flat ortho north up at owner ceiling")
            check(not state.player.noDraw and not state.player.shadow and not env.ZM_WorldMap.Capturing
                and not env.ZM_Atmosphere.MapCaptureParticlesHidden and state.targetDepth == 0, "all scopes restored")
            for _, entity in ipairs(state.transients) do check(not entity.noDraw and not entity.shadow, "transient auto-draw restored") end
        end)
        suite:Add("render_clear_and_capture_failures_restore_every_scope", function(check)
            for _, failure in ipairs({"renderFailure", "clearFailure", "png", "writeFailure", "blankPixels", "pixelFailure"}) do
                local capture, env, state = fixture()
                if failure == "png" then state.png = nil else state[failure] = true end
                local result = capture:Render(state.request)
                check(not result.ok, failure .. " rejected")
                check(not state.player.noDraw and not state.player.shadow and not env.ZM_WorldMap.Capturing
                    and not env.ZM_Atmosphere.MapCaptureParticlesHidden and env.ZM_Atmosphere.variant == nil
                    and state.targetDepth == 0 and (state.camera2D or 0) == 0, failure .. " restores")
            end
        end)
        suite:Add("coast_reuses_owner_geometry_under_exact_sky_to_world_transform", function(check)
            local capture, _, state = fixture()
            state.hooks.PostDrawOpaqueRenderables(false, false, false)
            check(not state.coastDraws, "ordinary gameplay does not draw extra coast")
            capture.Rendering = true
            state.hooks.PostDrawOpaqueRenderables(true, false, false)
            state.hooks.PostDrawOpaqueRenderables(false, false, true)
            check(not state.coastDraws, "depth and sky passes excluded")
            capture.Rendering = false
            check(capture:Render(state.request).ok and state.coastDraws == 1, "one capture-only owner draw")
            check(state.coastMatrix.scale.x == 16 and state.coastMatrix.translation.x == 0
                and state.coastMatrix.translation.y == 0 and state.coastMatrix.translation.z == -81920,
                "exact inverse sky camera/scale transform")
        end)
        suite:Add("prior_owner_state_preserved_and_stale_revision_never_draws", function(check)
            local capture, env, state = fixture()
            state.player.noDraw, state.player.shadow = true, true
            env.ZM_Atmosphere.MapCaptureParticlesHidden = true
            local result = capture:Render(state.request)
            check(result.ok and state.player.noDraw and state.player.shadow
                and env.ZM_Atmosphere.MapCaptureParticlesHidden, "preexisting hide states preserved")
            state.request.revision.mapManifestSha256 = string.rep("c", 64)
            result = capture:Render(state.request)
            check(not result.ok and state.renderCalls == 1, "stale manifest refuses rendering")
            check(state.hooks.PreDrawSkyBox == nil, "capture must retain native sky and coast ocean")
            state.request.revision.mapManifestSha256 = string.rep("a", 64)
            env.ZM_Skybox.GetPlayableCeiling = function() return 4592 end
            check(not capture:Render(state.request).ok, "owner ceiling drift rejects output")
        end)
        suite:Add("ready_ack_waits_for_map_weather_loading_and_stable_frames", function(check)
            local _, env, state = fixture()
            state.now = 0
            state.messages["ZM.WorldCapture.Request"]()
            state.now, state.loading = 10, true
            state.hooks.PostRender()
            check(not state.sent, "loading blocks capture")
            state.loading, env.ZM_Atmosphere.WeatherSynced = false, false
            state.hooks.PostRender()
            check(not state.sent, "weather sync blocks capture")
            env.ZM_Atmosphere.WeatherSynced = true
            state.hooks.PostRender(); state.hooks.PostRender()
            check(not state.sent, "stable frame warmup")
            state.hooks.PostRender()
            check(state.sent and state.reply.ok and state.reply.token == "one", "authenticated output acknowledgement")
        end)
        return suite:Run()
    end
end
