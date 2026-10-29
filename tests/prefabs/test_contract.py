"""Offline tests for the shared prefab document contract."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from glua.harness import FixtureRunner, lua_source


class PrefabContractTests(unittest.TestCase):
    def test_client_fixture_trace_only_activates_when_requested(self):
        runner = FixtureRunner(ROOT / "gamemode", ["tests/cl_prefab_fixture_trace.lua"])
        runner.lua.execute("""
            fixtureMap = "zn_dev_prefab_anchor"
            target = { IsAdmin = function() return true end, GetNWBool = function() return true end }
            game = { GetMap = function() return fixtureMap end }
            LocalPlayer = function() return target end
            IsValid = function(value) return value ~= nil end
            function Vector() end
            function Angle() end
            function LocalToWorld() end
            MASK_SOLID = 1
            util = { TableToJSON = function(value) report = value; return "json" end }
            file = { CreateDir = function() end, Write = function() return true end }
            function ErrorNoHalt(message) problem = message end
            concommand = { Add = function(_, callback) command = callback end }
            entities = {}
            for index = 1, 10 do
                entities[index] = {
                    GetModel = function() return "models/props_c17/oildrum001.mdl" end,
                    Activate = function(self) self.activated = (self.activated or 0) + 1 end
                }
            end
            ents = { FindByClass = function() return entities end }
            function fakeTrace()
                return { Sample = function(entity) return { entity = entity } end }
            end
        """)
        runner.load("tests/cl_prefab_fixture_trace.lua")(runner.lua.globals().fakeTrace)
        command = runner.lua.globals().command
        command(None, None, runner.lua.table_from(["101"]))
        self.assertEqual(len(runner.lua.globals().report.samples), 10)
        self.assertIsNone(runner.lua.globals().entities[1].activated)
        command(None, None, runner.lua.table_from(["102", "activate_client"]))
        self.assertEqual(runner.lua.globals().entities[1].activated, 1)
        runner.lua.globals().fixtureMap = "zn_preview_start"
        command(None, None, runner.lua.table_from(["103", "activate_client"]))
        self.assertEqual(runner.lua.globals().entities[1].activated, 1)

    def test_live_spawn_suite_receives_its_loot_factory(self):
        runner = FixtureRunner(ROOT / "gamemode", ["tests/sv_prefab_spawn_live.lua"])
        runner.lua.execute("""
            ZM_TestHarness = {
                Register = function(spec) capturedSpawnSuite = spec end,
                NewSuite = function()
                    return { count = 0, Add = function(self) self.count = self.count + 1 end,
                        Run = function(self) return { count = self.count } end }
                end
            }
            ZM_StaticData = {}
            util, ents = {}, {}
            function Vector() end
            function Angle() end
            function IsValid() end
            function LocalToWorld() end
            lootFactoryCalls = 0
            function fakeLootFactory(static)
                assert(static == ZM_StaticData)
                lootFactoryCalls = lootFactoryCalls + 1
                return { Resolve = function() end }
            end
            function fakeSpawnFactory(_, api)
                assert(type(api.ResolveLoot) == "function")
                return {}
            end
        """)
        runner.load("tests/sv_prefab_spawn_live.lua")(
            runner.lua.table(),
            runner.lua.globals().fakeSpawnFactory,
            runner.lua.globals().fakeLootFactory,
        )
        spec = runner.lua.globals().capturedSpawnSuite
        self.assertEqual(spec.command, "zn_test_prefab_spawn")
        self.assertEqual(spec.run().count, 4)
        self.assertEqual(runner.lua.globals().lootFactoryCalls, 1)

    def test_player_spawn_defers_loot_only_until_prefabs_are_ready(self):
        source = lua_source(ROOT / "gamemode" / "init.lua")
        start = source.index("    local prefabsOk, prefabsError = ZM_Prefabs:OnPlayerReady(ply)")
        end = source.index("    local droppedItemsLoaded", start)
        runner = FixtureRunner(ROOT / "gamemode", ["init.lua"])
        runner.lua.execute("""
            events = {}
            ply = {}
            ZM_Prefabs = { OnPlayerReady = function() table.insert(events, "prefabs"); return result, "failure" end }
            ZM_LootSpots = { OnPlayerReady = function() table.insert(events, "loot") end }
            ZM_Loading = { Step = function(_, _, message, status) table.insert(events, status or message) end }
            ErrorNoHalt = function() table.insert(events, "error") end
            logLoading = function(_, message) table.insert(events, message) end
        """)
        run = runner.lua.execute("return function()\n" + source[start:end] + "\nend")
        for value, expected in (
            (None, ["prefabs", "info"]),
            (True, ["prefabs", "ok", "loot", "Prepared loot spots"]),
            (False, ["prefabs", "error", "warn", "loot", "Prepared loot spots"]),
        ):
            runner.lua.globals().result = value
            runner.lua.execute("events = {}")
            run()
            events = runner.lua.globals().events
            self.assertEqual([events[i] for i in range(1, len(events) + 1)], expected)

    def test_editor_hud_guard_and_danger_star_geometry(self):
        runner = FixtureRunner(ROOT / "gamemode", ["cl_hud.lua"])
        source = lua_source(ROOT / "gamemode" / "cl_hud.lua")
        guard = source[
            source.index("local function gameplayHudHidden()"):
            source.index('hook.Add("HUDShouldDraw"')
        ]
        hidden = runner.lua.execute(guard + "\nreturn gameplayHudHidden")
        self.assertFalse(hidden())
        runner.lua.execute("ZM_PrefabEditorClient = { IsSession = function() return true end }")
        self.assertTrue(hidden())
        runner.lua.execute("ZM_PrefabEditorClient = nil; ZM_LauncherMenu = { Active = true }")
        self.assertTrue(hidden())

        star = source[
            source.index("local dangerStarShape = {"):
            source.index("local function drawDangerStar(centerX")
        ]
        runner.lua.execute("""
            drawnPolygons = 0
            surface = { DrawPoly = function(points)
                assert(type(points) == "table" and #points >= 3, "polygon has fewer than three vertices")
                for _, point in ipairs(points) do
                    assert(type(point.x) == "number" and type(point.y) == "number", "invalid vertex")
                end
                drawnPolygons = drawnPolygons + 1
            end }
        """)
        draw_star = runner.lua.execute(star + "\nreturn drawDangerStarShape")
        draw_star(100, 100, 8)
        self.assertEqual(runner.lua.globals().drawnPolygons, 6)

    def test_in_game_suite_registration(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_storage.lua",
                "prefabs/sh_gizmo.lua",
                "tests/sh_prefab_contract_tests.lua",
                "tests/sv_prefab_storage_tests.lua",
                "tests/fixtures/sv_prefab_storage_engine.lua",
                "tests/sh_prefab_gizmo_tests.lua",
                "tests/sv_prefab_registration.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        runner.lua.execute("ZM_TestHarness.Register = function(spec) capturedPrefabSuite = spec end")
        runner.lua.execute("""
            util = {
                TableToJSON = function(value) fixtureJson = value; return "fixture-json" end,
                JSONToTable = function(value) assert(value == "fixture-json"); return fixtureJson end
            }
        """)
        runner.load("tests/sv_prefab_registration.lua")(
            runner.load("prefabs/sh_contract.lua"),
            runner.load("prefabs/sv_storage.lua"),
            runner.load("tests/fixtures/sv_prefab_storage_engine.lua"),
            runner.load("tests/sh_prefab_contract_tests.lua"),
            runner.load("tests/sv_prefab_storage_tests.lua"),
            runner.load("prefabs/sh_gizmo.lua"),
            runner.load("tests/sh_prefab_gizmo_tests.lua"),
        )
        spec = runner.lua.globals().capturedPrefabSuite
        self.assertEqual(spec.command, "zn_test_prefabs")
        runnable = runner.lua.eval(
            "function(spec) return { Run = function() return spec.run() end } end"
        )(spec)
        runner.run(runnable, "Prefab in-game suite registration")

    def test_prefab_editor_client(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_gizmo.lua",
                "prefabs/sh_contract.lua",
                "cl_prefab_editor.lua",
                "tests/cl_prefab_editor_tests.lua",
                "tests/fixtures/cl_prefab_editor_engine.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_editor_tests.lua")(
            runner.load("tests/fixtures/cl_prefab_editor_engine.lua"),
            runner.compile,
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab editor client")

    def test_prefab_explorer_client(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_gizmo.lua",
                "prefabs/sh_contract.lua",
                "cl_prefab_editor.lua",
                "cl_prefab_explorer.lua",
                "tests/cl_prefab_explorer_tests.lua",
                "tests/fixtures/cl_prefab_editor_engine.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_explorer_tests.lua")(
            runner.load("tests/fixtures/cl_prefab_editor_engine.lua"),
            runner.compile,
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab explorer client")

    def test_prefab_gizmo(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_gizmo.lua",
                "tests/sh_prefab_gizmo_tests.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sh_prefab_gizmo_tests.lua")(
            runner.load("prefabs/sh_gizmo.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab gizmo")

    def test_prefab_document_contract(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_storage.lua",
                "tests/sh_prefab_contract_tests.lua",
                "tests/sv_prefab_storage_tests.lua",
                "tests/fixtures/sv_prefab_storage_engine.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        contract = runner.load("prefabs/sh_contract.lua")
        suite = runner.load("tests/sh_prefab_contract_tests.lua")(contract)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab document contract")

    def test_prefab_storage(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_storage.lua",
                "tests/sv_prefab_storage_tests.lua",
                "tests/fixtures/sv_prefab_storage_engine.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        contract = runner.load("prefabs/sh_contract.lua")
        suite = runner.load("tests/sv_prefab_storage_tests.lua")(
            runner.load("tests/fixtures/sv_prefab_storage_engine.lua"),
            contract,
            runner.load("prefabs/sv_storage.lua"),
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab storage")

    def test_prefab_exported_catalog(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_catalog.lua",
                "tests/sv_prefab_catalog_tests.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_catalog_tests.lua")(
            runner.load("prefabs/sh_contract.lua"),
            runner.load("prefabs/sv_catalog.lua"),
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Exported prefab catalog")

    def test_prefab_spawn(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_spawn.lua",
                "tests/sv_prefab_spawn_tests.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_spawn_tests.lua")(
            runner.load("prefabs/sh_contract.lua"),
            runner.load("prefabs/sv_spawn.lua"),
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab spawn")

    def test_prefab_loot_validation(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/sv_loot.lua", "tests/sv_prefab_loot_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_loot_tests.lua")(runner.load("prefabs/sv_loot.lua"))
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab loot validation")

    def test_prefab_fixture_trace(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/sh_fixture_trace.lua", "tests/sh_prefab_fixture_trace_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sh_prefab_fixture_trace_tests.lua")(
            runner.load("prefabs/sh_fixture_trace.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab fixture trace")

    def test_prefab_fixture_scale_sync(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_fixture_scale_sync.lua", "tests/cl_prefab_fixture_scale_sync_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_fixture_scale_sync_tests.lua")(
            runner.load("prefabs/cl_fixture_scale_sync.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab fixture scale sync")

    def test_prefab_spotlight_probe(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_spotlight_probe.lua", "tests/cl_prefab_spotlight_probe_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_spotlight_probe_tests.lua")(
            runner.load("prefabs/cl_spotlight_probe.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab spotlight probe")

    def test_prefab_spotlight_server_probe(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "sv_prefab_spotlight_probe.lua", "tests/sv_prefab_spotlight_probe_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_spotlight_probe_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab spotlight server probe")

    def test_prefab_runtime_owner(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "sv_prefabs.lua", "tests/sv_prefabs_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefabs_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab runtime owner")

    def test_prefab_city_probe_safety(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "tests/sv_prefab_city_live.lua", "tests/sv_prefab_city_live_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_city_live_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab city probe safety")

    def test_prefab_editor_session(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_storage.lua",
                "prefabs/sv_loot.lua",
                "sv_prefab_editor.lua",
                "tests/sv_prefab_editor_tests.lua",
                "tests/fixtures/sv_prefab_editor_engine.lua",
                "tests/fixtures/sv_prefab_storage_engine.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_editor_tests.lua")(
            runner.load("tests/fixtures/sv_prefab_editor_engine.lua"),
            runner.compile,
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab editor session")


if __name__ == "__main__":
    unittest.main()
