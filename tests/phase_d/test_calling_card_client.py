"""Run the shared calling-card client response fixtures without a live game."""

import unittest
from pathlib import Path

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]


class CallingCardClientTests(unittest.TestCase):
    def test_client_bootstrap_injects_the_factory_before_deferred_fixtures(self):
        source = (ROOT / "gamemode" / "cl_init.lua").read_text(encoding="utf-8")
        start = source.index('local createCallingCardState = include( "cl_calling_card_state.lua" )')
        end = source.index('include( "cl_scoreboard.lua" )', start)
        runner = FixtureRunner(ROOT, [])
        runner.lua.execute("""
            fixture = { startup = true, initializations = 0 }
            fixture.state = function() end
            fixture.engine = function() end
            fixture.initializer = function(state)
                assert(state == fixture.state)
                fixture.initializations = fixture.initializations + 1
            end
            function include(name)
                assert(fixture.startup, "relative include attempted after bootstrap: " .. name)
                if name == "cl_calling_card_state.lua" then return fixture.state end
                if name == "cl_calling_cards.lua" then return fixture.initializer end
                if name == "tests/cl_calling_card_state_tests.lua" then
                    return function(state) assert(state == fixture.state) end
                end
                if name == "tests/fixtures/cl_calling_card_engine.lua" then return fixture.engine end
                if name == "tests/cl_calling_card_ui_tests.lua" then
                    return function(engine, loader, state)
                        assert(engine == fixture.engine and state == fixture.state)
                        fixture.loader = loader
                    end
                end
                error("Unexpected bootstrap include: " .. name)
            end
        """)
        runner.lua.execute(source[start:end])
        runner.lua.execute("""
            assert(fixture.initializations == 1 and type(fixture.loader) == "function")
            fixture.startup = false
            assert(fixture.loader("cl_calling_cards.lua") == fixture.initializer)
            local ok, message = pcall(fixture.loader, "unexpected.lua")
            assert(not ok and string.find(message, "Unknown calling-card UI test module", 1, true))
        """)

    def test_bridge_forwards_calling_card_fixtures_only_to_preview_admin(self):
        runner = FixtureRunner(ROOT, ["gamemode/sv_dev_console.lua"])
        runner.lua.execute("""
            fixture = { target = nil, sent = {} }
            function IsValid(value) return value ~= nil and value.valid == true end
            ZM_Util = { FirstHuman = function() return fixture.target end }
            ZM_World = { ActiveProfile = "preview" }
            net = { Receive = function(name, callback)
                assert(name == "ZM.AtmosphereStatus.Result" or name == "ZM.CSM.FeasibilityProbe.Status")
                assert(type(callback) == "function")
            end }
            hook = { Add = function(event, name, callback)
                assert((event == "StartCommand" and name == "ZM.DevArrivalTrace")
                    or (event == "Think" and name == "ZombieSim.DevelopmentConsoleBridge"))
                assert(type(callback) == "function")
            end }
            concommand = { Add = function(name, callback)
                assert(name == "zombiesim_dev_persistence_report" or name == "zombiesim_validate_scripts")
                assert(type(callback) == "function")
            end }
            util = { AddNetworkString = function(name)
                assert(name == "ZM.AtmosphereStatus.Request" or name == "ZM.AtmosphereStatus.Result"
                    or name == "ZM.CSM.FeasibilityProbe.Status")
            end }
            file = { Exists = function(path, realm)
                assert(path == "zombiesim/arrival_trace.arm.txt" and realm == "DATA")
                return false
            end }
            game = { IsDedicated = function() return false end }
            FCVAR_ARCHIVE = 128
            function CreateConVar(name)
                assert(name == "zombiesim_dev_console_enabled")
            end
        """)
        runner.load("gamemode/sv_dev_console.lua")
        runner.lua.execute("""
            local commands = {
                "zombiesim_dev_test_calling_card_client",
                "zombiesim_dev_test_calling_card_ui"
            }
            local target = { valid = true, admin = true }
            function target:IsAdmin() return self.admin end
            function target:ConCommand(command) table.insert(fixture.sent, command) end
            for _, name in ipairs(commands) do
                local dispatch = assert(ZM_DevConsole.DirectCommands[name])
                fixture.target = nil
                assert(dispatch() == false and #fixture.sent == 0)
                fixture.target = target
                target.admin = false
                assert(dispatch() == false and #fixture.sent == 0)
                target.admin = true
                ZM_World.ActiveProfile = "city"
                assert(dispatch() == false and #fixture.sent == 0)
                ZM_World.ActiveProfile = "preview"
                assert(dispatch() == true)
                assert(fixture.sent[#fixture.sent] == name)
                fixture.sent = {}
            end
        """)

    def test_chunked_state_fixture_suite(self):
        runner = FixtureRunner(ROOT, [
            "gamemode/utils/test_harness.lua",
            "gamemode/sh_calling_cards.lua",
            "gamemode/cl_calling_card_state.lua",
            "gamemode/tests/cl_calling_card_state_tests.lua",
            "gamemode/cl_calling_cards.lua",
            "gamemode/tests/cl_calling_card_ui_tests.lua",
            "gamemode/tests/fixtures/cl_calling_card_engine.lua",
        ])
        runner.load("gamemode/utils/test_harness.lua")
        runner.load("gamemode/sh_calling_cards.lua")
        create_state = runner.load("gamemode/cl_calling_card_state.lua")
        suite = runner.load("gamemode/tests/cl_calling_card_state_tests.lua")(create_state)
        wrapper = runner.lua.eval("function(suite) return { Run = function() return suite:Run() end } end")(suite)
        runner.run(wrapper, "Calling-card client state")
        engine = runner.load("gamemode/tests/fixtures/cl_calling_card_engine.lua")
        initialize = runner.load("gamemode/cl_calling_cards.lua")
        live_env, live_state = engine(runner.lua.globals().ZM_CallingCards)
        runner.lua.eval("function(f, env, create) setfenv(f, env); f(create) end")(
            initialize, live_env, create_state
        )

        def load_module(name):
            self.assertEqual(name, "cl_calling_cards.lua")
            return initialize

        suite = runner.load("gamemode/tests/cl_calling_card_ui_tests.lua")(engine, load_module, create_state)
        wrapper = runner.lua.eval("function(suite) return { Run = function() return suite:Run() end } end")(suite)
        runner.run(wrapper, "Calling-card selector and shop")
        self.assertTrue(runner.lua.eval("function(f, env) return getfenv(f) == env end")(initialize, live_env))
        parent = live_env.vgui.Create("DPanel")
        parent.SetSize(parent, 1024, 700)
        ui = live_env.ZM_CallingCardUI
        self.assertIsNotNone(ui.OpenSelector(ui, parent))
        self.assertEqual(live_state.requests[1].request.action, "list")
        parent.Remove(parent)

    def test_ui_fixture_restores_factory_environment_when_initialization_fails(self):
        runner = FixtureRunner(ROOT, [
            "gamemode/utils/test_harness.lua",
            "gamemode/sh_calling_cards.lua",
            "gamemode/cl_calling_card_state.lua",
            "gamemode/tests/cl_calling_card_ui_tests.lua",
            "gamemode/tests/fixtures/cl_calling_card_engine.lua",
        ])
        runner.load("gamemode/utils/test_harness.lua")
        runner.load("gamemode/sh_calling_cards.lua")
        create_state = runner.load("gamemode/cl_calling_card_state.lua")
        engine = runner.load("gamemode/tests/fixtures/cl_calling_card_engine.lua")
        initialize = runner.lua.eval(
            "(function() local fail = error; return function() fail('deliberate initialization failure') end end)()"
        )
        original_env = runner.lua.eval("getfenv")(initialize)
        suite = runner.load("gamemode/tests/cl_calling_card_ui_tests.lua")(
            engine, lambda name: initialize, create_state
        )
        result = suite.Run(suite)
        self.assertEqual((result.passed, result.failed), (0, 6))
        for case in result.cases.values():
            self.assertIn("deliberate initialization failure", case.failures[1])
        self.assertTrue(runner.lua.eval("function(f, env) return getfenv(f) == env end")(initialize, original_env))

    def test_trader_purchase_reports_encoding_failure_without_sending(self):
        runner = FixtureRunner(ROOT, ["gamemode/cl_trading.lua"])
        runner.lua.execute("""
            fixture = { fail = true, sent = {}, logs = {}, receivers = {}, hooks = {} }
            function Color(r, g, b) return { r = r, g = g, b = b } end
            function IsValid(value) return value ~= nil and value.valid == true end
            function ErrorNoHalt(message) table.insert(fixture.logs, message) end
            hook = { Add = function(event, id, callback)
                assert(type(event) == "string" and string.find(id, "^ZM%.DenNpc%."))
                assert(type(callback) == "function")
                fixture.hooks[id] = callback
            end }
            concommand = { Add = function(name, callback)
                assert(name == "zn_trade_window" and type(callback) == "function")
            end }
            util = { TableToJSON = function(request)
                fixture.request = request
                if fixture.fail then return nil end
                return "encoded request"
            end }
            net = {
                Receive = function(name, callback) fixture.receivers[name] = callback end,
                Start = function(name) assert(name == "ZM.TradeRequest") fixture.current = {} end,
                WriteString = function(value) fixture.current.encoded = value end,
                SendToServer = function() table.insert(fixture.sent, fixture.current) fixture.current = nil end
            }
        """)
        runner.load("gamemode/cl_trading.lua")
        ui, fixture = runner.lua.globals().ZM_TradingUI, runner.lua.globals().fixture
        ui.NpcIndex = 42
        ui.Frame = runner.lua.table_from({"valid": True})
        ui.Rebuild = runner.lua.eval("function(self) self.rebuilds = (self.rebuilds or 0) + 1 end")
        request_id, error = ui.SendCallingCardPurchase(ui, "background_shop", 100)
        self.assertIsNone(request_id)
        self.assertEqual(error, "Could not encode the trader request.")
        self.assertEqual(len(fixture.sent), 0)
        self.assertEqual(len(fixture.logs), 1)
        self.assertFalse(ui.Message.ok)
        self.assertEqual(ui.rebuilds, 1)

        fixture.fail = False
        request_id = ui.SendCallingCardPurchase(ui, "background_shop", 100)
        self.assertIsInstance(request_id, str)
        self.assertEqual(len(fixture.sent), 1)
        self.assertEqual(fixture.sent[1].encoded, "encoded request")
        self.assertEqual(fixture.request.action, "buy_calling_card")
        self.assertEqual(fixture.request.id, "background_shop")
        self.assertEqual(fixture.request.price, 100)
        self.assertEqual(fixture.request.npc, 42)
        self.assertEqual(fixture.request.requestId, request_id)


if __name__ == "__main__":
    unittest.main()
