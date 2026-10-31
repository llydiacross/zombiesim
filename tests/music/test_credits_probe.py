"""Verify the bounded credits diagnostic with explicit client/server fixtures."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2]


class CreditsProbeTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, [
            "tests/music/credits_probe_engine.lua", "gamemode/tests/cl_credits_probe.lua"
        ])
        self.runner.load("tests/music/credits_probe_engine.lua")
        self.runner.load("gamemode/tests/cl_credits_probe.lua")(
            self.runner.lua.globals().Menu, self.runner.lua.globals().Scene, self.runner.lua.globals().Music
        )

    def test_reads_all_four_dancers_camera_and_audio_without_changing_them(self):
        self.runner.lua.execute("""
            fixture:Capture("123")
            local report = fixture.report
            assert(report.ok and report.requestId == "123" and #report.errors == 0)
            assert(report.phase == "orbit" and report.camera.origin.x == 20 and report.cameraAge < 1)
            assert(report.music.phase == "playing" and report.music.channelValid and report.music.time == 5)
            assert(#report.dancers == 4)
            for index, entry in ipairs(report.dancers) do
                assert(entry.ok and entry.id == 100 + index and entry.name == Menu.DancerNames[index])
                assert(entry.class == "prop_ragdoll" and entry.model == fixture.dancers[index].model)
                assert(entry.head.index == 6 and entry.head.parent == 5 and entry.head.parentName == "neck")
                assert(entry.head.physicsBone == 2 and entry.eyes.bone == 6)
                assert(entry.eyes.forwardInHead.forward == 0 and entry.eyes.forwardInHead.right == 1)
                assert(entry.eyes.forwardInHead.up == 0 and fixture.dancers[index].setups == 1)
            end
            assert(Menu.Credits and Music.CreditsMusic.channel == fixture.channel)
        """)

    def test_inactive_credits_and_stale_camera_are_explicit_failures(self):
        self.runner.lua.execute("""
            Menu.Credits = false
            fixture:Capture("1")
            assert(not fixture.report.ok and #fixture.report.dancers == 0)
            assert(fixture.report.errors[1] == "credits are not active")
            Menu.Credits = true
            Scene.LastCreditsViewAt = 8
            fixture:Capture("2")
            assert(not fixture.report.ok and #fixture.report.dancers == 4)
            assert(fixture.report.errors[1] == "last credits camera view is stale")
            Scene.LastCreditsView = nil
            fixture:Capture("3")
            assert(not fixture.report.ok and fixture.report.camera == false)
            assert(fixture.report.errors[1] == "credits camera view is unavailable or non-finite")
        """)

    def test_missing_entities_bones_matrices_and_attachments_are_reported(self):
        self.runner.lua.execute("""
            fixture.dancers[1].valid = false
            fixture.dancers[2].noHead = true
            fixture.dancers[3].noMatrix = true
            fixture.dancers[4].noEyes = true
            fixture:Capture("4")
            local report = fixture.report
            assert(not report.ok and #report.errors == 4)
            for _, entry in ipairs(report.dancers) do assert(entry.ok == false and #entry.errors == 1) end
            assert(report.dancers[1].errors[1] == "dancer entity is not available on the client")
            assert(report.dancers[2].errors[1] == "head bone is missing")
            assert(report.dancers[3].errors[1] == "head matrix is unavailable or non-finite")
            assert(report.dancers[4].errors[1] == "eyes attachment is unavailable")
        """)

    def test_nonfinite_values_and_output_failure_are_reported(self):
        self.runner.lua.execute("""
            fixture.dancers[1].matrix.position.x = 0 / 0
            fixture:Capture("5")
            assert(not fixture.report.ok and not fixture.report.dancers[1].ok)
            assert(fixture.report.dancers[1].errors[1] == "head matrix is unavailable or non-finite")
            fixture.failWrite = true
            fixture:Capture("6")
            assert(fixture.writes == 1 and string.find(fixture.errors[1], "Could not write", 1, true))
        """)

    def test_only_preview_launcher_admin_with_numeric_request_can_capture(self):
        self.runner.lua.execute("""
            fixture:Capture("1;quit")
            fixture:Capture(string.rep("1", 33))
            fixture.map = "zn_city_start"
            fixture:Capture("1")
            fixture.map = "zn_preview_start"
            Menu.Profile = "city"
            fixture:Capture("2")
            Menu.Profile = "preview"
            fixture.player.admin = false
            fixture:Capture("3")
            assert(fixture.writes == 0 and #fixture.errors == 5)
        """)

    def test_bootstrap_and_server_bridge_guards(self):
        client = lua_source(ROOT / "gamemode" / "cl_init.lua")
        self.assertLess(client.index('include( "cl_music.lua" )'), client.index('include( "tests/cl_credits_probe.lua" )'))
        self.assertIn('AddCSLuaFile( "tests/cl_credits_probe.lua" )', lua_source(ROOT / "gamemode" / "init.lua"))

        source = lua_source(ROOT / "gamemode" / "sv_dev_console.lua")
        helper_start = source.index("local function previewAdmin()")
        helper_end = source.index("DevConsole.DirectCommands.zombiesim_dev_test_imported_assets_client", helper_start)
        start = source.index("DevConsole.DirectCommands.zombiesim_dev_credits_status =")
        end = source.index("\nDevConsole.DirectCommands.", start + 1)
        self.runner.lua.execute("""
            DevConsole = { DirectCommands = {} }
            ZM_Util = { FirstHuman = function() return fixture.player end }
            ZM_World = { ActiveProfile = "preview" }
            function string.Trim(value) return string.match(value, "^%s*(.-)%s*$") end
        """)
        self.runner.lua.execute(source[helper_start:helper_end] + source[start:end])
        self.runner.lua.execute("""
            local run = DevConsole.DirectCommands.zombiesim_dev_credits_status
            assert(run(" 123 ") == true and fixture.sent[1] == "zombiesim_dev_credits_status 123")
            assert(run("123;quit") == false and run(string.rep("1", 33)) == false)
            fixture.map = "zn_city_start"
            assert(run("123") == false)
            fixture.map = "zn_preview_start"
            ZM_World.ActiveProfile = "city"
            assert(run("123") == false)
            ZM_World.ActiveProfile = "preview"
            fixture.player.admin = false
            assert(run("123") == false and #fixture.sent == 1)
        """)


if __name__ == "__main__":
    unittest.main()
