"""Offline tests for the shared prefab document contract."""

from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from glua.harness import FixtureRunner, lua_source


class PrefabContractTests(unittest.TestCase):
    def test_editor_map_client_engine_suite_registration(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/sh_contract.lua", "prefabs/sh_editor_map.lua",
            "tests/cl_prefab_editor_map_engine_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        runner.lua.execute("""
            state = { files = {}, values = {}, serial = 0 }
            local function clone(value)
                if type(value) ~= "table" then return value end
                local result = {}
                for key, entry in pairs(value) do result[key] = clone(entry) end
                return result
            end
            concommand = { Add = function(name, callback)
                assert(name == "zombiesim_dev_test_prefab_map_client"); state.command = callback
            end }
            util = {
                TableToJSON = function(value)
                    state.serial = state.serial + 1
                    local key = "json" .. state.serial
                    state.values[key] = clone(value)
                    return key
                end,
                JSONToTable = function(value) return clone(state.values[value]) end
            }
            file = {
                CreateDir = function() end,
                Exists = function(path, realm)
                    if realm == "GAME" then
                        return path == "maps/thumb/gm_construct.png" or path == "maps/thumb/gm_flatgrass.png"
                    end
                    assert(realm == "DATA")
                    return state.files[path] ~= nil
                end,
                Write = function(path, value) state.files[path] = value; return true end,
                Read = function(path, realm) assert(realm == "DATA"); return state.files[path] end,
                Delete = function(path) state.files[path] = nil; return true end
            }
            function Material(path)
                assert(path == "maps/thumb/gm_construct.png" or path == "maps/thumb/gm_flatgrass.png")
                return { IsError = function() return false end, GetTexture = function()
                    return { Width = function() return 128 end, Height = function() return 128 end }
                end }
            end
            ErrorNoHalt = function(message) error(message) end
        """)
        contract = runner.load("prefabs/sh_contract.lua")
        map_contract = runner.load("prefabs/sh_editor_map.lua")(contract)
        runner.load("tests/cl_prefab_editor_map_engine_tests.lua")(map_contract)
        runner.lua.globals().state.command()
        state = runner.lua.globals().state
        result = state["values"][state["files"]["zombiesim/prefab-editor-map-client-tests.json"]]
        self.assertEqual((result.passed, result.failed), (2, 0))
        self.assertIsNone(state["files"]["zombiesim/prefab_editor_map_transfer_fixture.json"])

    def test_editor_map_transfer_storage(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/sh_contract.lua", "prefabs/sh_editor_map.lua",
            "prefabs/cl_editor_transfer.lua", "tests/cl_prefab_editor_transfer_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_editor_transfer_tests.lua")(
            runner.load("prefabs/sh_contract.lua"), runner.load("prefabs/sh_editor_map.lua"),
            runner.load("prefabs/cl_editor_transfer.lua"),
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab editor map transfer")

    def test_editor_map_profile_initialization_is_preview_only(self):
        source = lua_source(ROOT / "gamemode" / "shared.lua")
        start = source.index("function GM:InitPostEntity()")
        runner = FixtureRunner(ROOT / "gamemode", ["shared.lua"])
        runner.lua.execute("""
            GM = {}
            state = { editor = false, calls = {} }
            SERVER, CLIENT = true, false
            ZM_PrefabEditor = { IsEditorMap = function() return state.editor end }
            ZM_World = {
                LoadProfile = function(_, profile) table.insert(state.calls, profile); return true end,
                LoadMapProfile = function() table.insert(state.calls, "map"); return true end
            }
            ErrorNoHalt = function(message) error(message) end
            ZM_Loading = { Step = function() end }
        """)
        runner.lua.execute(source[start:])
        runner.lua.globals().GM.InitPostEntity(runner.lua.globals().GM)
        self.assertEqual(runner.lua.globals().state.calls[1], "map")
        runner.lua.globals().state.editor = True
        runner.lua.globals().GM.InitPostEntity(runner.lua.globals().GM)
        self.assertEqual(runner.lua.globals().state.calls[2], "preview")
        runner.lua.globals().SERVER = False
        runner.lua.globals().CLIENT = True
        runner.lua.globals().GM.InitPostEntity(runner.lua.globals().GM)
        self.assertEqual(runner.lua.globals().state.calls[3], "map")

    def test_editor_map_switch_contract(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/sh_contract.lua", "prefabs/sh_editor_map.lua",
            "tests/sh_prefab_editor_map_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sh_prefab_editor_map_tests.lua")(
            runner.load("prefabs/sh_contract.lua"), runner.load("prefabs/sh_editor_map.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab editor map switch contract")

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
        runner.lua.execute("""
            entities = {}
            for index = 1, 5 do
                entities[index] = {
                    GetModel = function() return "models/props_c17/bench01a.mdl" end,
                    GetNW2Float = function(_, key, default)
                        assert(key == "ZM.PrefabFixtureScale" and default == 0)
                        return 1.4
                    end,
                    Activate = function(self) self.activated = (self.activated or 0) + 1 end
                }
            end
        """)
        command(None, None, runner.lua.table_from(["103", "compare", "5"]))
        self.assertEqual(len(runner.lua.globals().report.samples), 5)
        self.assertEqual(len(runner.lua.globals().report.errors), 0)
        self.assertIsNone(runner.lua.globals().entities[1].activated)
        command(None, None, runner.lua.table_from(["104", "compare", "6"]))
        self.assertEqual(len(runner.lua.globals().report.errors), 1)
        runner.lua.globals().fixtureMap = "zn_preview_start"
        command(None, None, runner.lua.table_from(["105", "activate_client", "5"]))
        self.assertIsNone(runner.lua.globals().entities[1].activated)

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
            util, ents, file = {}, {}, {}
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
                assert(type(api.ResolveParticle) == "function")
                return {}
            end
            function fakeParticleFactory(files, json, _)
                assert(files == file and json == util)
                return { Resolve = function() end }
            end
        """)
        runner.load("tests/sv_prefab_spawn_live.lua")(
            runner.lua.table(),
            runner.lua.globals().fakeSpawnFactory,
            runner.lua.globals().fakeLootFactory,
            runner.lua.globals().fakeParticleFactory,
        )
        spec = runner.lua.globals().capturedSpawnSuite
        self.assertEqual(spec.command, "zn_test_prefab_spawn")
        self.assertEqual(spec.run().count, 7)
        self.assertEqual(runner.lua.globals().lootFactoryCalls, 1)

    def test_live_scale_fixture_covers_authored_bench_and_cleanup(self):
        runner = FixtureRunner(ROOT / "gamemode", ["tests/sv_prefab_spawn_live.lua"])
        runner.lua.execute("""
            state = { records = {}, entities = {}, map = "zn_preview_start" }
            ZM_TestHarness = {
                Register = function(spec) capturedSpawnSuite = spec end,
                NewSuite = function()
                    local suite = {}
                    function suite:Add(name, callback)
                        if name == "native model scaling changes server collision relative to an unscaled control" then
                            self.selected = callback
                        end
                    end
                    function suite:Run(options)
                        assert(self.selected)
                        local failures = {}
                        self.selected(function(ok, message)
                            if not ok then table.insert(failures, message) end
                        end)
                        if options and options.teardown then options.teardown() end
                        return { failures = failures }
                    end
                    return suite
                end
            }
            local human = { valid = true, ZM_PersistentStateLoaded = false }
            function human:IsAdmin() return true end
            player = { GetHumans = function() return { human } end }
            game = { GetMap = function() return state.map end }
            ZM_World = { ActiveProfile = "preview" }
            ZM_StaticData, file = {}, {}
            MASK_SOLID = 1
            function Vector(x, y, z) return { x = x, y = y, z = z } end
            function Angle(p, y, r) return { p = p, y = y, r = r } end
            function IsValid(value) return type(value) == "table" and value.valid ~= false end
            function LocalToWorld() end
            ents = { Create = function(class)
                assert(class == "prop_physics")
                local entity = { valid = true }
                function entity:SetModel(model) self.model = model end
                function entity:SetPos(position) self.position = position end
                function entity:SetAngles(angles) self.angles = angles end
                function entity:Spawn() end
                function entity:SetModelScale(scale, duration) self.scale = scale; assert(duration == 0) end
                function entity:GetModelScale() return self.scale end
                function entity:Activate() self.activated = true end
                function entity:GetModelBounds() return Vector(-20, -20, 0), Vector(20, 20, 80) end
                function entity:GetPhysicsObject()
                    local physics = { valid = true }
                    function physics:EnableMotion(value) entity.movable = value end
                    function physics:Wake() end
                    function physics:Sleep() end
                    return physics
                end
                function entity:Remove() self.valid = false end
                table.insert(state.entities, entity)
                return entity
            end }
            util = { TraceLine = function(request)
                assert(request.whitelist and request.ignoreworld)
                local entity = request.filter[1]
                assert(entity.activated and entity.movable ~= nil)
                local axis = request.start.x ~= request.endpos.x and "x"
                    or request.start.y ~= request.endpos.y and "y" or "z"
                table.insert(state.records, {
                    model = entity.model, scale = entity.scale, movable = entity.movable, axis = axis
                })
                local factor = entity.model == "models/props_c17/bench01a.mdl" and entity.scale ~= 1
                    and (state.benchFactor or 1) or 1
                local extent = 20 * entity.scale * factor
                local hit = Vector(axis == "x" and extent or 0, axis == "y" and extent or 0,
                    4096 + (axis == "z" and extent or 0))
                return { Hit = true, Entity = entity, StartSolid = false, HitPos = hit }
            end }
            function fakeLootFactory() return { Resolve = function() end } end
            function fakeParticleFactory() return { Resolve = function() end } end
            function fakeSpawnFactory() return {} end
        """)
        runner.load("tests/sv_prefab_spawn_live.lua")(
            runner.lua.table(),
            runner.lua.globals().fakeSpawnFactory,
            runner.lua.globals().fakeLootFactory,
            runner.lua.globals().fakeParticleFactory,
        )
        state = runner.lua.globals().state
        spec = runner.lua.globals().capturedSpawnSuite
        result = spec.run()
        self.assertEqual(len(result.failures), 0)
        expected = {
            (model, scale, movable, axis)
            for model, scales in (
                ("models/props_c17/oildrum001.mdl", (1, 0.1, 0.5, 2, 10)),
                ("models/props_c17/bench01a.mdl", (1, 1.4)),
            )
            for scale in scales for movable in (False, True) for axis in ("x", "y", "z")
        }
        actual = {
            (state.records[i].model, state.records[i].scale, state.records[i].movable, state.records[i].axis)
            for i in range(1, len(state.records) + 1)
        }
        self.assertEqual(actual, expected)
        self.assertEqual(len(state.records), len(expected))
        state.benchFactor = 1.049
        self.assertEqual(len(spec.run().failures), 0)
        state.benchFactor = 1.051
        outside_tolerance = spec.run()
        self.assertEqual(len(outside_tolerance.failures), 6)
        self.assertTrue(all(
            "bench01a.mdl" in outside_tolerance.failures[i]
            for i in range(1, len(outside_tolerance.failures) + 1)
        ))
        self.assertTrue(all(not state.entities[i].valid for i in range(1, len(state.entities) + 1)))
        state.map = "zz_preview_city"
        rejected = spec.run()
        self.assertEqual(len(rejected.failures), 1)
        self.assertEqual(len(state.records), len(expected) * 3)

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

    def test_editor_screenshots_include_vgui(self):
        source = lua_source(ROOT / "gamemode" / "cl_dev_profiler.lua")
        start = source.index("    local visibleUI =")
        end = source.index("\n    local needsVGUI", start)
        runner = FixtureRunner(ROOT / "gamemode", ["cl_dev_profiler.lua"])
        runner.lua.execute("IsValid = function(value) return value ~= nil end")
        visible = runner.lua.execute("return function()\n" + source[start:end] + "\nreturn visibleUI == true\nend")
        self.assertFalse(visible())
        runner.lua.execute("ZM_PrefabEditorClient = { IsActive = function() return true end }")
        self.assertTrue(visible())
        runner.lua.execute("""ZM_PrefabEditorClient = nil
            ZM_LauncherMenu = {
                Page = "menu", Frame = { IsVisible = function() return true end }
            }""")
        self.assertTrue(visible())
        runner.lua.execute('ZM_LauncherMenu.Page = "tools"')
        self.assertTrue(visible())
        runner.lua.execute('ZM_LauncherMenu.Frame.IsVisible = function() return false end')
        self.assertFalse(visible())

    def test_in_game_suite_registration(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sv_storage.lua",
                "prefabs/sv_catalog.lua",
                "prefabs/sh_gizmo.lua",
                "tests/sh_prefab_contract_tests.lua",
                "tests/sv_prefab_storage_tests.lua",
                "tests/fixtures/sv_prefab_storage_engine.lua",
                "tests/sh_prefab_gizmo_tests.lua",
                "tests/sv_prefab_catalog_tests.lua",
                "tests/sv_prefab_registration.lua",
            ],
        )
        runner.load("utils/test_harness.lua")
        runner.lua.execute("ZM_TestHarness.Register = function(spec) capturedPrefabSuite = spec end")
        runner.lua.execute("""
            util = {
                TableToJSON = function(value) fixtureJson = value; return "fixture-json" end,
                JSONToTable = function(value) assert(value == "fixture-json"); return fixtureJson end,
                CRC = function(text)
                    crcCalls = (crcCalls or 0) + 1
                    local hash = 0
                    for index = 1, #text do hash = (hash * 33 + string.byte(text, index)) % 4294967296 end
                    return tostring(hash)
                end
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
            runner.load("prefabs/sv_catalog.lua"),
            runner.load("tests/sv_prefab_catalog_tests.lua"),
        )
        spec = runner.lua.globals().capturedPrefabSuite
        self.assertEqual(spec.command, "zn_test_prefabs")
        runnable = runner.lua.eval(
            "function(spec) return { Run = function() return spec.run() end } end"
        )(spec)
        runner.run(runnable, "Prefab in-game suite registration")
        self.assertGreater(runner.lua.globals().crcCalls, 0)

    def test_prefab_editor_client(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "prefabs/sh_gizmo.lua",
                "prefabs/sh_contract.lua",
                "prefabs/sh_editor_map.lua",
                "prefabs/cl_editor_transfer.lua",
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
                "prefabs/sh_editor_map.lua",
                "prefabs/cl_editor_transfer.lua",
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

    def test_prefab_spotlight_pool(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_spotlight_pool.lua", "tests/cl_prefab_spotlight_pool_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_spotlight_pool_tests.lua")(
            runner.load("prefabs/cl_spotlight_pool.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab spotlight pool")

    def test_prefab_light_preview(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_light_preview.lua", "tests/cl_prefab_light_preview_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_light_preview_tests.lua")(
            runner.load("prefabs/cl_light_preview.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab light preview")

    def test_prefab_light_runtime(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_light_runtime.lua", "tests/cl_prefab_light_runtime_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_light_runtime_tests.lua")(
            runner.load("prefabs/cl_light_runtime.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab light runtime")

    def test_prefab_particle_probe(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_particle_probe.lua", "prefabs/cl_particle_effect.lua",
             "tests/cl_prefab_particle_probe_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_particle_probe_tests.lua")(
            runner.load("prefabs/cl_particle_probe.lua"), runner.load("prefabs/cl_particle_effect.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab particle probe")

    def test_prefab_particle_server_probe(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "sv_prefab_particle_probe.lua", "tests/sv_prefab_particle_probe_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_particle_probe_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab particle server probe")

    def test_prefab_particle_catalog(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/sh_contract.lua", "prefabs/sh_particle_catalog.lua",
             "tests/sh_prefab_particle_catalog_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sh_prefab_particle_catalog_tests.lua")(
            runner.load("prefabs/sh_contract.lua"), runner.load("prefabs/sh_particle_catalog.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab particle catalog")
        catalog = json.loads((ROOT / "content" / "data_static" / "prefab_particles.json").read_text(encoding="utf-8"))
        self.assertEqual(catalog["schemaVersion"], 1)
        self.assertEqual(
            catalog["effects"],
            [{"id": "steam", "label": "Steam", "particleFile": "particles/train_steam.pcf",
              "particleSystem": "steam_train", "sound": "ambient/gas/steam_loop1.wav"}],
        )

    def test_prefab_particle_preview(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_particle_preview.lua",
             "tests/cl_prefab_particle_preview_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_particle_preview_tests.lua")(
            runner.load("prefabs/cl_particle_preview.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab particle preview")

    def test_prefab_particle_world(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "prefabs/cl_particle_world.lua", "tests/cl_prefab_particle_world_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_particle_world_tests.lua")(
            runner.load("prefabs/cl_particle_world.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab particle world")

    def test_prefab_particle_network_and_anchor_input(self):
        runner = FixtureRunner(
            ROOT,
            ["gamemode/utils/test_harness.lua", "gamemode/cl_prefab_particle_world.lua",
             "gamemode/tests/cl_prefab_particle_network_tests.lua",
             "entities/entities/zn_prefab_anchor/shared.lua", "gamemode/tests/sv_prefab_anchor_input_tests.lua"],
        )
        runner.load("gamemode/utils/test_harness.lua")
        for path, label in (
            ("gamemode/tests/cl_prefab_particle_network_tests.lua", "Prefab particle network"),
            ("gamemode/tests/sv_prefab_anchor_input_tests.lua", "Prefab anchor particle input"),
        ):
            suite = runner.load(path)(runner.compile)
            runnable = runner.lua.eval(
                "function(suite) return { Run = function() return suite:Run() end } end"
            )(suite)
            runner.run(runnable, label)

    def test_prefab_particle_world_probe(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "sv_prefab_particle_world_probe.lua",
             "tests/sv_prefab_particle_world_probe_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_particle_world_probe_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab particle world probe")

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
                "prefabs/sh_editor_map.lua",
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
