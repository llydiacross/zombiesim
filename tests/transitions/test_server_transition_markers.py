"""Exercise the real server gate publication with isolated engine fixtures."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner, lua_source


def main():
    source_root = Path(__file__).resolve().parents[2] / "gamemode"
    runner = FixtureRunner(source_root, [
        "utils/test_harness.lua", "tests/fixtures/cl_transition_markers_engine.lua",
    ])
    runner.load("utils/test_harness.lua")
    engine = runner.load("tests/fixtures/cl_transition_markers_engine.lua")
    build = runner.lua.eval("""
        function(createEngine, source)
            local tests = {}
            local function fixture()
                local env = createEngine()
                local state = env.State
                env.ZM_Transitions = {}
                env.game = { GetMap = function() return "fixture" end }
                env.ZM_World = {
                    IsLoaded = function() return state.worldLoaded ~= false end,
                    GetCellsForMap = function() return state.mapCells or {} end,
                    GetExit = function(_, cell, code) return cell[code] end,
                    GetTravelMode = function(_, exit) return exit and exit.highway end
                }
                env.math, env.string, env.table = math, string, table
                env.type = type
                env.bit = require("bit")
                env.IN_FORWARD, env.IN_BACK, env.IN_MOVELEFT, env.IN_MOVERIGHT, env.IN_JUMP = 8, 16, 512, 1024, 2
                env.util = {
                    AddNetworkString = function() end,
                    TraceLine = function(spec)
                        state.traces[#state.traces + 1] = spec
                        local hit = state.surface
                        return { Hit = hit ~= false, HitSky = state.hitSky, StartSolid = state.startSolid,
                            HitPos = env.Vector(spec.start.x, spec.start.y, hit or 0),
                            HitNormal = state.normal or env.Vector(0, 0, 1) }
                    end
                }
                env.net = { Receive = function() end }
                state.timers = {}
                env.timer = {
                    Create = function(name, _, _, callback) state.timers[name] = callback end,
                    Simple = function(_, callback) state.deferred = callback end
                }
                state.gates, state.traces = {}, {}
                env.ents = { FindByClass = function() return state.gates end }
                env.player = { GetHumans = function() return { state.player } end }
                env.MASK_SOLID_BRUSHONLY = 1
                env.SetGlobal2Vector = function(key, value) state.globals[key] = value end
                env.SetGlobal2Int = env.SetGlobal2Vector
                env.SetGlobal2Bool = env.SetGlobal2Vector
                state.player.SetNWString = function(self, key, value) self[key] = value end
                state.player.SetNWBool = state.player.SetNWString
                state.player.CanTravelToNeighbour = function(self, code, mode)
                    state.travelCalls[#state.travelCalls + 1] = { code, mode }
                    return state.available[code .. "_" .. mode]
                end
                state.travelCalls, state.available = {}, {}
                function state:Gate(code, position, mode, laneIndex)
                    local names = { N = "north", E = "east", S = "south", W = "west" }
                    local entity = { valid = true }
                    function entity:GetClass() return "trigger_multiple" end
                    function entity:GetName()
                        return "zm_transition_gate_" .. code .. (laneIndex and "_lane" .. laneIndex or "")
                    end
                    function entity:GetKeyValues()
                        return { zm_transition_gate = "1", zm_transition_direction = names[code],
                            zm_transition_mode = mode or "road", zm_transition_lane = laneIndex }
                    end
                    function entity:WorldSpaceCenter() return position end
                    function entity:SetNWBool() end
                    function entity:SetNWString() end
                    self.gates[#self.gates + 1] = entity
                end
                local chunk = assert(loadstring(source, "@sv_transitions.lua"))
                setfenv(chunk, env)
                chunk()
                return env.ZM_Transitions, state, env
            end
            function tests.Run()
                local suite = ZM_TestHarness.NewSuite()
                suite:Add("server_surface_anchors_follow_all_cardinal_decks_and_preserve_centres", function(check)
                    for _, height in ipairs({ 36, 196 }) do
                        local service, state, env = fixture()
                        state.surface = height
                        local forwards = { N = env.Vector(0, 1, 0), E = env.Vector(1, 0, 0),
                            S = env.Vector(0, -1, 0), W = env.Vector(-1, 0, 0) }
                        for code, forward in pairs(forwards) do
                            state:Gate(code, forward * 2208 + env.Vector(0, 0, height + 20))
                        end
                        service:InitializeGates()
                        check(#service.GateMarkers == 4 and #state.traces == 4, "one bounded trace per gate")
                        for code, forward in pairs(forwards) do
                            local key = "ZMTransitionGate_" .. code .. "_1"
                            check(state.globals[key] == forward * 2208 + env.Vector(0, 0, height + 20),
                                code .. " minimap centre unchanged")
                            check(state.globals[key .. "_Surface"] == forward * 2112 + env.Vector(0, 0, height + 2),
                                code .. " actual deck anchor with two-unit lift")
                            check(state.globals[key .. "_SurfaceReady"] == true, code .. " supported")
                        end
                        for _, trace in ipairs(state.traces) do
                            check(trace.start.z - trace.endpos.z == 512 and trace.mask == env.MASK_SOLID_BRUSHONLY,
                                "bounded brush-only surface probe")
                        end
                    end
                end)
                suite:Add("missing_sky_solid_and_steep_surfaces_are_reported_without_fallback", function(check)
                    for _, reason in ipairs({ "missing", "sky", "solid", "steep" }) do
                        local service, state, env = fixture()
                        state.surface = reason ~= "missing" and 36 or false
                        state.hitSky = reason == "sky"
                        state.startSolid = reason == "solid"
                        if reason == "steep" then state.normal = env.Vector(0.8, 0, 0.6) end
                        state:Gate("N", env.Vector(0, 2208, 56))
                        service:InitializeGates()
                        check(state.globals.ZMTransitionGate_N_1_SurfaceReady == false, reason .. " unsupported")
                        check(#state.errors == 1 and service.GateMarkers[1].surface == nil, reason .. " explicit diagnostic")
                    end
                end)
                suite:Add("motorway_pairs_trace_each_carriageway_inward_for_all_cardinals", function(check)
                    local forwards = { N = { 0, 1 }, E = { 1, 0 }, S = { 0, -1 }, W = { -1, 0 } }
                    for code, xy in pairs(forwards) do
                        for _, authored in ipairs({ true, false }) do
                            local service, state, env = fixture()
                            state.surface = 196
                            local forward = env.Vector(xy[1], xy[2], 0)
                            local right = forward:Cross(env.Vector(0, 0, 1))
                            state:Gate(code, forward * 2208 + env.Vector(0, 0, 56), authored and "highway" or "any")
                            if not authored then state.mapCells = { { [code] = { highway = {} } } } end
                            service:InitializeGates()
                            local key = "ZMTransitionGate_" .. code .. "_1"
                            check(#state.traces == 2 and state.globals[key .. "_ArrowCount"] == 2, "two independent probes")
                            for lane = 1, 2 do
                                local arrowKey = key .. (lane == 1 and "" or "_Lane2")
                                local expected = forward * 1952 + right * (lane == 1 and -160 or 160)
                                    + env.Vector(0, 0, 198)
                                check(state.globals[arrowKey .. "_Surface"] == expected, code .. " carriageway anchor")
                            end
                            if not authored then state.mapCells = {} else state.gates = {}; state:Gate(code, forward * 2208, "road") end
                            service:InitializeGates()
                            check(state.globals[key .. "_ArrowCount"] == 1
                                and state.globals[key .. "_Lane2_SurfaceReady"] == false, "road restores one arrow")
                        end
                    end
                end)
                suite:Add("separate_motorway_triggers_publish_one_arrow_each_and_keep_384_arrival", function(check)
                    local service, state, env = fixture()
                    state.surface = 68
                    state.mapCells = { { motorwayGates = { {
                        direction = "N", route = "motorway", x = 0, y = 2208, deckZ = 68,
                        arrivalLane = 1, status = "trusted_prior_grid_gate_not_compiled_or_live",
                        lanes = {
                            { lateral = -512, width = 416, deckZ = 68, arrowX = -512, arrowY = 1952,
                                arrivalX = -512, arrivalY = 1824 },
                            { lateral = 528, width = 416, deckZ = 68, arrowX = 528, arrowY = 1952,
                                arrivalX = 528, arrivalY = 1824 }
                        }
                    } } } }
                    state:Gate("N", env.Vector(-512, 2208, 88), "any", 1)
                    state:Gate("N", env.Vector(528, 2208, 88), "any", 2)
                    service:InitializeGates()
                    check(#service.GateMarkers == 2 and #state.traces == 2
                        and service.GateMarkers[1].surfaceReady and service.GateMarkers[2].surfaceReady,
                        "each carriageway gets one trigger and one surface trace")
                    check(state.globals.ZMTransitionGateCount_N == 2
                        and state.globals.ZMTransitionGate_N_1_ArrowCount == 1
                        and state.globals.ZMTransitionGate_N_2_ArrowCount == 1, "one arrow is published per physical trigger")
                    check(state.globals.ZMTransitionGate_N_1_Surface == env.Vector(-512, 1952, 70)
                        and state.globals.ZMTransitionGate_N_2_Surface == env.Vector(528, 1952, 70),
                        "each trigger publishes its own carriageway surface")

                    env.MASK_PLAYERSOLID = 2
                    state.hulls = {}
                    env.util.TraceHull = function(spec)
                        state.hulls[#state.hulls + 1] = spec
                        return { StartSolid = false }
                    end
                    function state.player:GetHull() return env.Vector(-16, -16, 0), env.Vector(16, 16, 72) end
                    local arrival = service:ResolveGateArrivalPosition(state.player, "N")
                    check(arrival == env.Vector(-512, 1824, 69), "arrival remains 384 units inward on the approved lane")
                    check(#state.hulls == 1 and state.hulls[1].mask == env.MASK_PLAYERSOLID, "arrival still validates player hull clearance")
                end)
                suite:Add("initialization_waits_for_world_profile_and_map_cleanup_republishes", function(check)
                    local service, state, env = fixture()
                    state.surface = 196
                    state:Gate("N", env.Vector(0, 2208, 56), "any")
                    state.worldLoaded = false
                    state.hooks.InitPostEntity["ZM.InitializeTransitionGates"]()
                    check(#state.traces == 0, "does not classify roads before GM loads the profile")
                    state.mapCells = { { N = { highway = {} } } }
                    state.worldLoaded = true
                    state.deferred()
                    check(state.globals.ZMTransitionGate_N_1_ArrowCount == 2, "fresh profile produces motorway pair")
                    state.mapCells = {}
                    state.hooks.PostCleanupMap["ZM.InitializeTransitionGates"]()
                    check(state.globals.ZMTransitionGate_N_1_ArrowCount == 1, "cleanup restores current metadata")
                    state.worldLoaded = false
                    state.deferred()
                    check(#state.errors == 1, "missing profile is explicitly reported")
                end)
                suite:Add("republishing_clears_counts_and_invalidates_unsupported_old_surface", function(check)
                    local service, state, env = fixture()
                    state.surface = 196
                    state:Gate("E", env.Vector(2208, 0, 216))
                    service:InitializeGates()
                    state.surface = false
                    service:InitializeGates()
                    check(state.globals.ZMTransitionGate_E_1_SurfaceReady == false, "old bridge anchor invalidated")
                    state.gates = {}
                    service:InitializeGates()
                    check(state.globals.ZMTransitionGateCount_E == 0 and #service.GateMarkers == 0,
                        "stale published gate removed")
                end)
                suite:Add("blocked_publication_uses_existing_authoritative_direction_and_mode", function(check)
                    local service, state, env = fixture()
                    state.surface = 36
                    state:Gate("N", env.Vector(0, 2208, 56), "road")
                    state:Gate("E", env.Vector(2208, 0, 56), "highway")
                    service:InitializeGates()
                    state.player.alive = false
                    state.available.N_road = {}
                    state.timers["ZM.PublishNearbyTransitionGate"]()
                    check(state.player.ZMTransitionGate_N_1_Blocked == false, "valid road is green eligible")
                    check(state.player.ZMTransitionGate_E_1_Blocked == true, "missing highway is blocked")
                    state.available.N_road = nil
                    state.available.E_highway = {}
                    state.timers["ZM.PublishNearbyTransitionGate"]()
                    check(state.player.ZMTransitionGate_N_1_Blocked and not state.player.ZMTransitionGate_E_1_Blocked,
                        "availability changes follow real modes")
                end)
                suite:Add("motorway_arrivals_clear_the_median_and_stand_past_the_arrows", function(check)
                    local forwards = { N = { 0, 1 }, E = { 1, 0 }, S = { 0, -1 }, W = { -1, 0 } }
                    for code, xy in pairs(forwards) do
                        local service, state, env = fixture()
                        state.surface = 36
                        env.MASK_PLAYERSOLID = 2
                        state.hulls = {}
                        env.util.TraceHull = function(spec)
                            state.hulls[#state.hulls + 1] = spec
                            return { StartSolid = state.hullSolid == true }
                        end
                        function state.player:GetHull() return env.Vector(-16, -16, 0), env.Vector(16, 16, 72) end
                        local forward = env.Vector(xy[1], xy[2], 0)
                        local right = forward:Cross(env.Vector(0, 0, 1))
                        state:Gate(code, forward * 2208 + env.Vector(0, 0, 56), "highway")
                        service:InitializeGates()
                        local lane = state.globals["ZMTransitionGate_" .. code .. "_1_Surface"]
                        local arrival = service:ResolveGateArrivalPosition(state.player, code)
                        check(arrival == forward * 1824 + right * -160 + env.Vector(0, 0, 37),
                            code .. " arrives on the lane-one carriageway")
                        check(math.abs(arrival.x) > 8 and math.abs(arrival.y) > 8,
                            code .. " clears the central reservation")
                        check(forward:Dot(lane - arrival) > 0,
                            code .. " stands further inside the cell than its arrow")
                        check(#state.hulls == 1 and state.hulls[1].mask == env.MASK_PLAYERSOLID,
                            code .. " validates the player hull before placing")
                        state.hullSolid = true
                        check(service:ResolveGateArrivalPosition(state.player, code) == nil,
                            code .. " obstructed carriageway keeps the authored landmark")
                        state.hullSolid, state.surface = false, false
                        check(service:ResolveGateArrivalPosition(state.player, code) == nil,
                            code .. " unsupported carriageway keeps the authored landmark")
                    end
                end)
                suite:Add("ordinary_road_and_absent_gate_arrivals_keep_the_authored_landmark", function(check)
                    local service, state, env = fixture()
                    state.surface = 36
                    env.util.TraceHull = function() return { StartSolid = false } end
                    env.MASK_PLAYERSOLID = 2
                    function state.player:GetHull() return env.Vector(-16, -16, 0), env.Vector(16, 16, 72) end
                    state:Gate("S", env.Vector(0, -2208, 56), "road")
                    service:InitializeGates()
                    check(service:ResolveGateArrivalPosition(state.player, "S") == nil,
                        "single-arrow road arrival unchanged")
                    check(service:ResolveGateArrivalPosition(state.player, "N") == nil,
                        "absent gate arrival unchanged")
                end)
                suite:Add("measured_wide_gates_use_explicit_axis_lanes_and_arrivals", function(check)
                    local forwards = { N = { 0, 1 }, E = { 1, 0 }, S = { 0, -1 }, W = { -1, 0 } }
                    for code, xy in pairs(forwards) do
                        local service, state, env = fixture()
                        state.surface = 68
                        local forward = env.Vector(xy[1], xy[2], 0)
                        local right = forward:Cross(env.Vector(0, 0, 1))
                        local flipped = code == "S" or code == "E"
                        local gate = { direction = code, x = forward.x * 2208, y = forward.y * 2208,
                            deckZ = 68, arrivalLane = 1, lanes = {},
                            status = "measured_source_gate_not_compiled_or_live" }
                        for _, lateral in ipairs(flipped and { -528, 512 } or { -512, 528 }) do
                            local arrow = forward * 1952 + right * lateral
                            local arrival = forward * 1824 + right * lateral
                            gate.lanes[#gate.lanes + 1] = { lateral = lateral, width = 416, deckZ = 68,
                                arrowX = arrow.x, arrowY = arrow.y, arrivalX = arrival.x, arrivalY = arrival.y }
                        end
                        state.mapCells = { { motorwayGates = { gate } }, { motorwayGates = { gate } } }
                        state:Gate(code, forward * 2208 + right * (flipped and -8 or 8) + env.Vector(0, 0, 88), "any")
                        service:InitializeGates()
                        local key = "ZMTransitionGate_" .. code .. "_1"
                        check(state.globals[key] == forward * 2208 + env.Vector(0, 0, 88),
                            code .. " corrects asymmetric brush centre to logical axis")
                        for index, lane in ipairs(gate.lanes) do
                            local suffix = index == 1 and "" or "_Lane2"
                            check(state.globals[key .. suffix .. "_Surface"] == env.Vector(lane.arrowX, lane.arrowY, 70),
                                code .. " publishes measured lane " .. index)
                        end
                        env.util.TraceHull = function() return { StartSolid = false } end
                        env.MASK_PLAYERSOLID = 2
                        function state.player:GetHull() return env.Vector(-16, -16, 0), env.Vector(16, 16, 72) end
                        local lane = gate.lanes[1]
                        check(service:ResolveGateArrivalPosition(state.player, code) == env.Vector(lane.arrivalX, lane.arrivalY, 69),
                            code .. " arrival follows measured selected lane")
                        state.surface = 36
                        service:InitializeGates()
                        check(state.globals[key .. "_SurfaceReady"] == false
                            and state.globals[key .. "_Lane2_SurfaceReady"] == false,
                            code .. " legacy or terrain deck cannot masquerade as a measured carriageway")
                        check(service:ResolveGateArrivalPosition(state.player, code) == nil and #state.errors == 3,
                            code .. " wrong arrow and arrival decks are explicitly reported")
                        state.surface, state.errors = 68, {}
                        state.mapCells[2] = {}
                        service:InitializeGates()
                        check(#service.GateMarkers == 0 and #state.errors == 1,
                            code .. " mixed metadata invalidates gate rather than guessing")
                    end
                end)
                suite:Add("measured_ordinary_roads_publish_one_arrow_and_use_their_arrival", function(check)
                    for code, xy in pairs({ N = { 0, 1 }, E = { 1, 0 }, S = { 0, -1 }, W = { -1, 0 } }) do
                        local service, state, env = fixture()
                        local forward = env.Vector(xy[1], xy[2], 0)
                        state.surface = 36
                        local gate = { direction = code, route = "road", x = forward.x * 2720,
                            y = forward.y * 2720, deckZ = 36, arrivalLane = 1,
                            status = "measured_source_gate_not_compiled_or_live",
                            lanes = { { lateral = 0, width = 256, deckZ = 36,
                                arrowX = forward.x * 2624, arrowY = forward.y * 2624,
                                arrivalX = forward.x * 2592, arrivalY = forward.y * 2592 } } }
                        state.mapCells = { { motorwayGates = { gate } }, { motorwayGates = { gate } } }
                        state:Gate(code, forward * 2720 + env.Vector(0, 0, 88), "highway")
                        service:InitializeGates()
                        local key = "ZMTransitionGate_" .. code .. "_1"
                        check(#state.errors == 0 and #state.traces == 1 and #service.GateMarkers == 1,
                            code .. " ordinary measured route ignores legacy motorway classification")
                        check(state.globals[key .. "_ArrowCount"] == 1
                            and state.globals[key .. "_Surface"] == forward * 2624 + env.Vector(0, 0, 38)
                            and state.globals[key .. "_Lane2_SurfaceReady"] == false,
                            code .. " publishes exactly one supported centred arrow")
                        check(service:ResolveGateArrivalPosition(state.player, code) == forward * 2592 + env.Vector(0, 0, 37),
                            code .. " road arrival stays behind its arrow on the centred approach")
                        state.surface = 68
                        check(service:ResolveGateArrivalPosition(state.player, code) == nil and #state.errors == 1,
                            code .. " road arrival rejects an incorrect deck")
                    end
                end)
                suite:Add("mixed_measured_route_types_and_bad_road_lanes_are_rejected", function(check)
                    for _, reason in ipairs({ "route", "count", "lateral", "unknown" }) do
                        local service, state, env = fixture()
                        local gate = { direction = "N", route = "road", x = 0, y = 2720, deckZ = 36,
                            arrivalLane = 1, status = "measured_source_gate_not_compiled_or_live",
                            lanes = { { lateral = 0, width = 256, deckZ = 36,
                                arrowX = 0, arrowY = 2624, arrivalX = 0, arrivalY = 2592 } } }
                        state.mapCells = { { motorwayGates = { gate } } }
                        if reason == "route" then
                            state.mapCells[2] = { motorwayGates = { { direction = "N", x = 0, y = 2720, deckZ = 36,
                                arrivalLane = 1, status = gate.status, lanes = {
                                    { lateral = -512, width = 416, deckZ = 36, arrowX = -512, arrowY = 2464, arrivalX = -512, arrivalY = 2336 },
                                    { lateral = 528, width = 416, deckZ = 36, arrowX = 528, arrowY = 2464, arrivalX = 528, arrivalY = 2336 }
                                } } } }
                        elseif reason == "count" then gate.lanes[2] = gate.lanes[1]
                        elseif reason == "lateral" then gate.lanes[1].lateral = 1
                        elseif reason == "unknown" then gate.route = "footpath" end
                        state:Gate("N", env.Vector(0, 2720, 88), "any")
                        service:InitializeGates()
                        check(#service.GateMarkers == 0 and #state.traces == 0 and #state.errors == 1,
                            reason .. " fails closed before any surface sampling")
                    end
                end)
                suite:Add("invalid_measured_gate_contracts_are_reported_without_legacy_fallback", function(check)
                    for _, reason in ipairs({ "missing", "nan", "duplicate", "moved", "conflict" }) do
                        local service, state, env = fixture()
                        local gate = { direction = "N", x = 0, y = 2208, deckZ = 68, arrivalLane = 1,
                            status = "measured_source_gate_not_compiled_or_live",
                            lanes = {
                                { lateral = -512, width = 416, deckZ = 68, arrowX = -512, arrowY = 1952, arrivalX = -512, arrivalY = 1824 },
                                { lateral = 528, width = 416, deckZ = 68, arrowX = 528, arrowY = 1952, arrivalX = 528, arrivalY = 1824 }
                            } }
                        state.mapCells = { { motorwayGates = { gate } } }
                        if reason == "missing" then state.mapCells[1].motorwayGates = {} end
                        if reason == "nan" then gate.lanes[1].arrowX = 0 / 0 end
                        if reason == "duplicate" then state.mapCells[1].motorwayGates[2] = gate end
                        if reason == "conflict" then
                            local other = { direction = "N", x = 0, y = 2208, deckZ = 68, arrivalLane = 1,
                                status = gate.status, lanes = {
                                    { lateral = -160, width = 416, deckZ = 68, arrowX = -512, arrowY = 1952, arrivalX = -512, arrivalY = 1824 },
                                    gate.lanes[2]
                                } }
                            state.mapCells[2] = { motorwayGates = { other } }
                        end
                        state:Gate("N", env.Vector(reason == "moved" and 100 or 0, 2208, 88), "any")
                        service:InitializeGates()
                        check(#service.GateMarkers == 0 and #state.traces == 0 and #state.errors == 1,
                            reason .. " rejects malformed source/map contract before traces")
                        env.HUD_PRINTCENTER = 4
                        function state.player:PrintMessage(_, text) state.lastMessage = text end
                        check(service:TryUseGate(state.player, state.gates[1]) == false
                            and state.lastMessage == "This route's map data is invalid.",
                            reason .. " travel rejects invalid metadata with a player-visible error")
                    end
                end)
                return suite:Run()
            end
            return tests
        end
    """)
    tests = build(engine, lua_source(source_root / "sv_transitions.lua"))
    runner.run(tests, "Server transition markers")


if __name__ == "__main__":
    main()
