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
                function state:Gate(code, position, mode)
                    local names = { N = "north", E = "east", S = "south", W = "west" }
                    local entity = { valid = true }
                    function entity:GetClass() return "trigger_multiple" end
                    function entity:GetName() return "zm_transition_gate_" .. code end
                    function entity:GetKeyValues()
                        return { zm_transition_gate = "1", zm_transition_direction = names[code],
                            zm_transition_mode = mode or "road" }
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
                return suite:Run()
            end
            return tests
        end
    """)
    tests = build(engine, lua_source(source_root / "sv_transitions.lua"))
    runner.run(tests, "Server transition markers")


if __name__ == "__main__":
    main()
