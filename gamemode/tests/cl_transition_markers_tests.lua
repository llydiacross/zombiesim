return function(createEngine, loadFactory)
    local Tests = {}
    ZM_TransitionMarkersTests = Tests
    function Tests.NewFixture()
        local env = createEngine()
        local initialize = loadFactory("cl_transition_markers.lua")
        setfenv(initialize, env)
        local markers = {}
        initialize(markers)
        return markers, env.State, env, initialize
    end
    function Tests.Run()
        local suite = ZM_TestHarness.NewSuite()
        suite:Add("cardinal_arrows_have_exact_dimensions_outward_tip_and_upward_winding", function(check)
            local markers, _, env = Tests.NewFixture()
            for code, forward in pairs({ N = env.Vector(0, 1, 0), E = env.Vector(1, 0, 0),
                S = env.Vector(0, -1, 0), W = env.Vector(-1, 0, 0) }) do
                local origin, normal = env.Vector(50, 60, 198), env.Vector(0, 0, 1)
                local vertices = markers.BuildVertices(origin, normal, code, markers.GetColour(false, false))
                local minLong, maxLong, minWide, maxWide = math.huge, -math.huge, math.huge, -math.huge
                local right = forward:Cross(normal)
                for _, vertex in ipairs(vertices) do
                    local offset = vertex.pos - origin
                    minLong, maxLong = math.min(minLong, offset:Dot(forward)), math.max(maxLong, offset:Dot(forward))
                    minWide, maxWide = math.min(minWide, offset:Dot(right)), math.max(maxWide, offset:Dot(right))
                    check(vertex.pos.z == 198, code .. " remains on lifted bridge deck")
                end
                check(maxLong - minLong == 192 and maxWide - minWide == 128, code .. " exact dimensions")
                check(vertices[9].pos == origin + forward * 96, code .. " outward tip")
                for i = 1, 9, 3 do
                    check((vertices[i + 1].pos - vertices[i].pos):Cross(vertices[i + 2].pos - vertices[i].pos):Dot(normal) > 0,
                        code .. " triangle winding faces up")
                end
            end
        end)
        suite:Add("slope_geometry_is_tangent_and_blocked_colour_overrides_route", function(check)
            local markers, _, env = Tests.NewFixture()
            local normal = env.Vector(0, 0.6, 0.8)
            local origin = env.Vector(10, 20, 30)
            for _, vertex in ipairs(markers.BuildVertices(origin, normal, "N", markers.GetColour(false, false))) do
                check(math.abs((vertex.pos - origin):Dot(normal)) < 0.00001, "all points lie in road plane")
            end
            check(markers.GetColour(false, false).g == 240, "normal green")
            check(markers.GetColour(false, true).r == 246, "route yellow")
            check(markers.GetColour(true, true).r == 232, "blocked red wins")
        end)
        suite:Add("metadata_reconciliation_reuses_and_destroys_owned_meshes", function(check)
            local markers, state, env = Tests.NewFixture()
            local key = state:Gate("N", 1, env.Vector(0, 2112, 198))
            markers:Reconcile()
            markers:Reconcile()
            check(#state.meshes == 1 and state.meshes[1].builds == 1, "unchanged geometry stays static")
            state.globals[key .. "_Surface"] = env.Vector(0, 2112, 38)
            markers:Reconcile()
            check(#state.meshes == 2 and state.meshes[1].destroyed == 1, "changed anchor replaces old mesh")
            state.globals["ZMTransitionGateCount_N"] = 0
            markers:Reconcile()
            check(state.meshes[2].destroyed == 1 and markers:GetDiagnosticSnapshot().markers == 0, "removed gate cleaned")
        end)
        suite:Add("unavailable_surface_and_delayed_normal_never_draw_ground_fallback", function(check)
            local markers, state, env = Tests.NewFixture()
            local key = state:Gate("E", 1, env.Vector(), env.Vector())
            markers:Reconcile()
            check(#state.meshes == 0, "incomplete network anchor does not create mesh")
            state.globals[key .. "_Normal"] = env.Vector(0, 0, 1)
            markers:Reconcile()
            state.globals[key .. "_SurfaceReady"] = false
            markers:Reconcile()
            check(state.meshes[1].destroyed == 1, "unsupported surface removes old marker")
        end)
        suite:Add("visibility_range_is_inclusive_and_render_capture_guards_restore", function(check)
            local markers, state, env = Tests.NewFixture()
            state:Gate("E", 1, env.Vector())
            markers:Reconcile()
            state.eye = env.Vector(1280, 0, 0)
            markers:Draw(false, false)
            check(markers.Draws == 1, "exactly 1280 visible")
            state.eye = env.Vector(1280.01, 0, 0)
            markers:Draw(false, false)
            check(markers.Draws == 0, "beyond range hidden")
            state.eye = env.Vector()
            markers:Draw(true, false)
            check(markers.Draws == 0, "depth pass hidden")
            markers:Draw(false, true)
            check(markers.Draws == 0, "skybox pass hidden")
            for _, owner in ipairs({ env.ZM_WorldMap, env.ZM_SkyInspection, env.ZM_LauncherMenu }) do
                local key = owner == env.ZM_WorldMap and "Capturing" or owner == env.ZM_SkyInspection and "Rendering" or "Active"
                owner[key] = true
                markers:Draw(false, false)
                check(markers.Draws == 0, key .. " hidden")
                owner[key] = false
            end
            state.loading = true
            markers:Draw(false, false)
            check(markers.Draws == 0, "loading hidden")
            state.loading = false
            state.player.safeZone = "den"
            markers:Draw(false, false)
            check(markers.Draws == 0, "den hidden")
            state.player.safeZone = ""
            state.player.alive = false
            markers:Draw(false, false)
            check(markers.Draws == 0, "dead player hidden")
            state.player.alive = true
            markers:Draw(false, false)
            check(markers.Draws == 1 and state.matrixDepth == 0, "main view returns without leaked matrix")
        end)
        suite:Add("colour_changes_do_not_allocate_meshes_or_rebuild_every_frame", function(check)
            local markers, state, env = Tests.NewFixture()
            state:Gate("E", 1, env.Vector())
            markers:Reconcile()
            markers:Draw(false, false)
            local first = state.meshes[1].builds
            markers:Draw(false, false)
            check(state.meshes[1].builds == first, "unchanged colour is cached")
            state.route = "E"
            markers:Draw(false, false)
            check(state.meshes[1].vertices[1].color.r == 246, "route updates yellow")
            state.player.blocked = true
            markers:Draw(false, false)
            check(state.meshes[1].vertices[1].color.r == 232 and #state.meshes == 1, "blocked updates red without allocation")
        end)
        suite:Add("motorway_pair_shares_gate_colours_and_removes_only_stale_lane", function(check)
            local markers, state, env = Tests.NewFixture()
            local key = state:Gate("E", 1, env.Vector(1952, 160, 198))
            state.globals[key .. "_ArrowCount"] = 2
            state.globals[key .. "_Lane2_SurfaceReady"] = true
            state.globals[key .. "_Lane2_Surface"] = env.Vector(1952, -160, 198)
            state.globals[key .. "_Lane2_Normal"] = env.Vector(0, 0, 1)
            state.eye = env.Vector(1952, 0, 300)
            markers:Reconcile()
            markers:Reconcile()
            check(#state.meshes == 2 and markers:GetDiagnosticSnapshot().markers == 2, "one static mesh per carriageway")
            state.route = "E"
            markers:Draw(false, false)
            for _, mesh in ipairs(state.meshes) do
                check(mesh.vertices[1].color.r == 246, "both lanes use route yellow")
            end
            local requested = {}
            state.player.GetNWBool = function(_, name)
                requested[#requested + 1] = name
                return true
            end
            markers:Draw(false, false)
            check(#requested == 2 and requested[1] == key .. "_Blocked"
                and requested[2] == key .. "_Blocked", "both lanes use their parent gate blocked state")
            for _, mesh in ipairs(state.meshes) do
                check(mesh.vertices[1].color.r == 232, "blocked wins on both arrows")
            end
            state.globals[key .. "_ArrowCount"] = 1
            markers:Reconcile()
            check(markers:GetDiagnosticSnapshot().markers == 1
                and markers.Items[key .. "_Lane2"] == nil, "single-road publication removes second mesh")
            markers:Cleanup()
            for _, mesh in ipairs(state.meshes) do check(mesh.destroyed == 1, "each owned mesh destroyed exactly once") end
        end)
        suite:Add("reinitialization_cleanup_and_material_failure_are_explicit", function(check)
            local markers, state, env, initialize = Tests.NewFixture()
            state:Gate("N", 1, env.Vector())
            markers:Reconcile()
            initialize(markers)
            check(state.meshes[1].destroyed == 1, "reinitialization removes previous mesh")
            markers:Reconcile()
            state.hooks.PreCleanupMap["ZM.TransitionArrows.Cleanup"]()
            markers:Cleanup()
            check(state.meshes[2].destroyed == 1, "cleanup remains idempotent")
            state.materialError = true
            initialize(markers)
            check(#state.errors == 1 and markers:GetDiagnosticSnapshot().materialError, "material error reported")
        end)
        suite:Add("map_overlays_project_all_cardinals_without_world_range_or_capture_baking", function(check)
            local markers, state, env = Tests.NewFixture()
            state.eye = env.Vector(10000, 10000, 10000)
            env.ZM_WorldMap.Capturing = true
            for code, position in pairs({ N = env.Vector(0, 200, 198), E = env.Vector(200, 0, 198),
                S = env.Vector(0, -200, 198), W = env.Vector(-200, 0, 198) }) do
                state:Gate(code, 1, position)
            end
            markers:Reconcile()
            local project = function(point) return 300 + point.x, 300 - point.y end
            markers:DrawMap(project, 0, 0, 600, 600)
            check(markers.MapDraws == 4 and #state.polygons == 12, "all arrows overlay independent of distant capture camera")
            for _, polygon in ipairs(state.polygons) do
                local a, b, c = polygon.points[1], polygon.points[2], polygon.points[3]
                check((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0,
                    "clockwise screen winding")
            end
            markers:Draw(false, false)
            check(markers.Draws == 0, "world meshes remain excluded from capture")
            state.polygons = {}
            state.route = "N"
            markers:DrawMap(project, 0, 0, 600, 600)
            local yellow = 0
            for _, polygon in ipairs(state.polygons) do if polygon.colour.r == 246 then yellow = yellow + 1 end end
            check(yellow == 3, "waypoint colour updates without refreshing capture")
        end)
        suite:Add("map_overlay_clipping_pairs_blocked_state_and_cleanup", function(check)
            local markers, state, env = Tests.NewFixture()
            local key = state:Gate("N", 1, env.Vector(-160, 0, 38))
            state.globals[key .. "_ArrowCount"] = 2
            state.globals[key .. "_Lane2_SurfaceReady"] = true
            state.globals[key .. "_Lane2_Surface"] = env.Vector(160, 0, 38)
            state.globals[key .. "_Lane2_Normal"] = env.Vector(0, 0, 1)
            markers:Reconcile()
            local project = function(point) return 300 + point.x, 300 - point.y end
            state.player.blocked = true
            markers:DrawMap(project, 0, 0, 600, 600)
            check(markers.MapDraws == 2 and #state.polygons == 6, "motorway pair stays separate")
            for _, polygon in ipairs(state.polygons) do check(polygon.colour.r == 232, "shared blocked red") end
            state.polygons = {}
            markers:DrawMap(project, 150, 250, 40, 60)
            check(#state.polygons > 0, "partially visible arrow clipped rather than omitted")
            for _, polygon in ipairs(state.polygons) do
                for _, point in ipairs(polygon.points) do
                    check(point.x >= 150 and point.x <= 190 and point.y >= 250 and point.y <= 310,
                        "no pixels spill outside minimap rectangle")
                end
            end
            state.polygons = {}
            markers:DrawMap(project, 800, 800, 100, 100)
            check(#state.polygons == 0, "offscreen arrows are not pinned or drawn")
            state.player.safeZone = "den"
            markers:DrawMap(project, 0, 0, 600, 600)
            check(#state.polygons == 0, "den overlay hidden")
            state.player.safeZone = ""
            markers:Cleanup()
            markers:DrawMap(project, 0, 0, 600, 600)
            check(#state.polygons == 0, "removed arrows do not persist in cached map")
        end)
        return suite:Run()
    end
    concommand.Add("zombiesim_dev_test_transition_markers_client", function()
        if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
            ErrorNoHalt("[ZombieSim] Transition marker tests require a preview admin.\n")
            return
        end
        local summary = Tests.Run()
        summary.live = ZM_TransitionMarkers:GetDiagnosticSnapshot()
        file.CreateDir("zombiesim")
        file.Write("zombiesim/transition_markers_client_tests.json", util.TableToJSON(summary, true))
        for _, result in ipairs(summary.cases) do
            print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
            for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
        end
    end)
end
