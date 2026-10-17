return function(createEngine, loadChunk)
    local Tests = {}
    ZM_WorldCaptureServerTests = Tests
    local function fixture()
        local contract = loadChunk("world_capture/sh_contract.lua")()
        local cellHealthContractFactory = loadChunk("sh_cell_health_contract.lua")()
        local env, state = createEngine(contract, cellHealthContractFactory)
        local function load()
            local chunk = loadChunk("sv_world_capture.lua")
            setfenv(chunk, env); chunk()
        end
        load()
        local function reload()
            state:Reload(loadChunk("sv_world_capture.lua"))
            state:Advance(); state:Advance(6)
        end
        return env, state, contract, reload
    end
    function Tests.Run()
        local suite = ZM_TestHarness.NewSuite()
        suite:Add("full_rollout_requires_explicit_scope_count_and_never_deduplicates_recipes", function(check)
            local _, state = fixture()
            check(not state.commands.zombiesim_world_capture_full({"city", "4"}), "production scope rejected")
            check(not state.commands.zombiesim_world_capture_full({"preview", "3"}), "wrong authoritative count rejected")
            check(state.commands.zombiesim_world_capture_full({"preview", "4"}), "explicit full scope starts")
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(saved.fullWorld and not saved.withNav and #saved.queue == 4 and saved.completedResults == 0,
                "fresh full capture-only all logical cells")
            check(saved.queue[1].map == saved.queue[2].map and saved.queue[1].id ~= saved.queue[2].id,
                "shared recipes retained as distinct cells")
            local _, combined = fixture()
            check(combined.commands.zombiesim_world_maintenance_full({"preview", "4"}), "separate combined rollout")
            check(combined.files["zombiesim/world_capture_state.json"].withNav, "combined explicitly enables nav")
        end)
        suite:Add("two_logical_cells_sharing_recipe_reload_and_restore_exact_core", function(check)
            local env, state, contract, reload = fixture()
            check(state.commands.zombiesim_world_capture_start({"0,0", "1,0"}), "bounded queue starts")
            reload()
            check(state.request.cell.id == 0 and state.request.variant == "clear", "first ready request")
            state:Result(contract); state:Advance()
            check(state.request.variant == "atmospheric", "second variant without map travel")
            state:Result(contract); state:Advance()
            check(state.changelevel == "recipe_0" and state.player.CellX == 1, "same BSP distinct logical cell reloads")
            reload()
            check(state.request.cell.id == 1, "logical identity retained across reload")
            state:Result(contract); state:Advance(); state:Result(contract); state:Advance()
            check(state.changelevel == "recipe_0", "return map queued")
            reload()
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(not saved.active and saved.phase == "complete" and saved.restorationVerified, "restoration acknowledged")
            check(saved.completedResults == 4 and not state.player.frozen, "results retained/unfrozen")
            for key, value in pairs(state.originalRow) do check(tostring(state.row[key]) == value, key .. " restored") end
            check(state.player.position.x == 20 and state.player.position.y == 30, "original local position restored")
        end)
        suite:Add("failed_png_restores_then_retry_keeps_completed_clear_result", function(check)
            local _, state, contract, reload = fixture()
            state.commands.zombiesim_world_capture_start({"current"}); reload()
            state:Result(contract); state:Advance()
            state:Result(contract, {sha256 = "wrong"})
            check(state.changelevel == "recipe_0", "invalid output restores before retry")
            reload()
            check(state.commands.zombiesim_world_capture_retry({}), "same run retries after restoration")
            reload()
            check(state.request.variant == "atmospheric", "completed clear result is not repeated")
        end)
        suite:Add("explicit_extension_keeps_results_and_snapshots_intervening_gameplay", function(check)
            local _, state, contract, reload = fixture()
            state.commands.zombiesim_world_capture_start({"current"}); reload()
            state:Result(contract); state:Advance(); state:Result(contract); state:Advance(); reload()
            local runId = state.files["zombiesim/world_capture_state.json"].runId
            state.player.Hunger, state.row.Hunger = 20, "30"
            check(state.commands.zombiesim_world_capture_extend({"1,0"}), "bounded explicit extension accepted")
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(saved.runId == runId and saved.results.clear["0"] ~= nil, "same run retains completed logical result")
            check(saved.original.runtimeCore.Hunger == 20 and saved.original.core.Hunger == "30",
                "fresh gameplay/persistence restoration baseline")
            check(#saved.queue == 2 and saved.index == 2, "only new logical cell queued")
        end)
        suite:Add("revision_drift_and_competing_batch_are_fail_closed", function(check)
            local _, state, _, reload = fixture()
            state.navBatchActive = true
            check(not state.commands.zombiesim_world_capture_start({"current"}), "nav-only batch cannot overlap")
            state.navBatchActive = false
            state.commands.zombiesim_world_capture_start({"current"})
            state.world.templatePlanSha256 = string.rep("c", 64)
            reload()
            check(state.files["zombiesim/world_capture_state.json"].phase == "restoring", "revision drift routes to restoration")
        end)
        suite:Add("nav_generation_save_reload_validation_precedes_capture", function(check)
            local _, state, _, reload = fixture()
            state.commands.zombiesim_world_maintenance_start({"current"}); reload()
            check(state.navStarts == 1 and not state.request, "nav starts before any capture")
            state:Advance()
            state.navGenerating, state.navAreas = false, 42
            state:Advance(4)
            check(state.navSaves == 1 and not state.request, "native nav saved before capture")
            state:Advance(3)
            check(state.changelevel == "recipe_0", "fresh persistence reload required")
            reload()
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(saved.navmeshes.recipe_0.reloadValidated and state.request.variant == "clear", "capture follows loaded nav proof")
            check(state.navSaves == 1, "existing nav-only state never touched")
        end)
        suite:Add("nav_cancel_waits_for_safe_boundary_and_timeout_is_bounded", function(check)
            local _, state, _, reload = fixture()
            state.commands.zombiesim_world_maintenance_start({"current"}); reload()
            state:Advance()
            state.commands.zombiesim_world_capture_cancel({})
            check(not state.changelevel, "cannot changelevel during native generation")
            state.navGenerating, state.navAreas = false, 10
            state:Advance(4); state:Advance(3); reload()
            check(state.changelevel == "recipe_0" and not state.request, "cancellation restores after nav reload")
        end)
        suite:Add("cell_health_batch_schedules_only_missing_selected_work_and_deduplicates_map_tasks", function(check)
            local env, state = fixture()
            local started, message = env.ZM_WorldCapture:StartCellHealth(state.player, {
                navmesh = true, photos = true, cubemaps = true
            }, true)
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(started and saved and saved.cellHealthBatch,
                "server starts the health-filtered persistent queue (" .. tostring(message) .. ")")
            check(#saved.queue == 4 and saved.expectedCaptureResults == 8,
                "logical photo jobs remain distinct while both photo variants are counted")
            check(saved.queue[1].doNav and saved.queue[1].doCubemaps and saved.queue[1].doPhotos,
                "the first logical cell owns shared map work and its missing photos")
            check(not saved.queue[2].doNav and not saved.queue[2].doCubemaps and saved.queue[2].doPhotos,
                "a second logical cell sharing a BSP retains only its own photo work")
            check(saved.queue[3].doNav and saved.queue[3].doCubemaps,
                "a distinct BSP receives its own shared-map tasks")
        end)
        suite:Add("cell_health_network_start_validates_selection_and_returns_a_result", function(check)
            local env, state = fixture()
            state.readValues = {"batch-request"}
            state.jsonInput = {
                schemaVersion = 1,
                selection = {navmesh = true, photos = false, cubemaps = false}
            }
            state.callbacks["ZM.CellHealth.BatchStart"](0, state.player)
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(saved and saved.cellHealthBatch and #saved.queue == 3,
                "server recomputes the map-deduplicated unhealthy navmesh queue")
            check(state.lastMessage.name == "ZM.CellHealth.BatchResult"
                and state.lastMessage.writes[1].value == true,
                "client receives a start acknowledgement")

            local invalidEnv, invalidState = fixture()
            invalidState.readValues = {"invalid-request"}
            invalidState.jsonInput = {
                schemaVersion = 1,
                selection = {navmesh = false, photos = false, cubemaps = false}
            }
            invalidState.callbacks["ZM.CellHealth.BatchStart"](0, invalidState.player)
            check(invalidState.files["zombiesim/world_capture_state.json"] == nil
                and invalidState.lastMessage.writes[1].value == false,
                "an empty client selection starts no maintenance run")
        end)
        suite:Add("manual_cubemap_confirmation_waits_for_reload_and_persists_user_answer", function(check)
            local env, state, _, reload = fixture()
            local started, message = env.ZM_WorldCapture:StartCellHealth(state.player, {
                navmesh = false, photos = false, cubemaps = true
            })
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(started and saved and saved.phase == "loading",
                "cubemap-only batch begins without automating the native command (" .. tostring(message) .. ")")
            reload()
            local saved = state.files["zombiesim/world_capture_state.json"]
            check(saved.phase == "awaiting-cubemap-run" and state.lastMessage.name == "ZM.WorldCapture.CubemapPrompt",
                "the first prompt asks the user to run buildcubemaps on the loaded map")
            state.changelevel = state.map
            reload()
            saved = state.files["zombiesim/world_capture_state.json"]
            check(saved.phase == "awaiting-cubemap-success"
                and state.lastMessage.writes[1].value.stage == "success",
                "a map reload leads to a separate success question")
            state.readValues = {saved.runId, "recipe_0", true}
            state.callbacks["ZM.WorldCapture.CubemapDecision"](0, state.player)
            state:Advance(6)
            local confirmations = state.files["zombiesim/cubemap_confirmations_preview.json"]
            saved = state.files["zombiesim/world_capture_state.json"]
            check(confirmations ~= nil, "decision was accepted (phase=" .. tostring(saved.phase)
                .. ", active=" .. tostring(saved.active) .. ", error=" .. tostring(saved.error) .. ")")
            if not confirmations then return end
            check(confirmations.maps.recipe_0.confirmed and saved.cubemapResults.recipe_0 == true,
                "a Yes response is durably recorded per BSP as user-confirmed")
            check(saved.index == 2 and saved.phase == "next",
                "the confirmation resumes the queue (index=" .. tostring(saved.index)
                    .. ", phase=" .. tostring(saved.phase) .. ", error=" .. tostring(saved.error) .. ")")
        end)
        suite:Add("negative_cubemap_confirmation_stays_incomplete_and_continues", function(check)
            local env, state, _, reload = fixture()
            env.ZM_WorldCapture:StartCellHealth(state.player, {
                navmesh = false, photos = false, cubemaps = true
            })
            reload()
            state.changelevel = state.map
            reload()
            local saved = state.files["zombiesim/world_capture_state.json"]
            state.readValues = {saved.runId, "recipe_0", false}
            state.callbacks["ZM.WorldCapture.CubemapDecision"](0, state.player)
            state:Advance(6)
            local confirmations = state.files["zombiesim/cubemap_confirmations_preview.json"]
            saved = state.files["zombiesim/world_capture_state.json"]
            check(confirmations ~= nil, "negative response was accepted (phase=" .. tostring(saved.phase)
                .. ", active=" .. tostring(saved.active) .. ", error=" .. tostring(saved.error) .. ")")
            if not confirmations then return end
            check(confirmations.maps.recipe_0 == nil and saved.cubemapResults.recipe_0 == false,
                "No clears any prior confirmation but does not mark this BSP complete")
            check(saved.index == 2 and saved.phase == "next",
                "a No response leaves the map unhealthy and continues (index=" .. tostring(saved.index)
                    .. ", phase=" .. tostring(saved.phase) .. ", error=" .. tostring(saved.error) .. ")")
        end)
        return suite:Run()
    end
end
