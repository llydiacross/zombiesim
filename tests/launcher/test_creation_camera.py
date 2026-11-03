"""Exercise the actual launcher camera transport, visibility, and client ownership."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from glua.harness import FixtureRunner


class CreationCameraTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(
            ROOT,
            [
                "gamemode/sv_launcher.lua",
                "gamemode/cl_launcher_menu.lua",
                "gamemode/cl_launcher_scene.lua",
                "gamemode/tests/cl_launcher_presentation_tests.lua",
                "tests/launcher/creation_camera_fixture.lua",
            ],
        )
        self.server, self.client, self.state = self.runner.load(
            "tests/launcher/creation_camera_fixture.lua"
        )()
        load = self.runner.lua.eval("function(chunk, env) setfenv(chunk, env); return chunk() end")
        load(self.runner.compile("gamemode/sv_launcher.lua"), self.server)
        load(self.runner.compile("gamemode/cl_launcher_menu.lua"), self.client)
        load(self.runner.compile("gamemode/cl_launcher_scene.lua"), self.client)
        load(self.runner.compile("gamemode/tests/cl_launcher_presentation_tests.lua"), self.client)
        self.menu = self.client.ZM_LauncherMenu
        self.scene = self.client.ZM_LauncherSceneClient
        self.menu.Render = self.runner.lua.eval("function() end")
        self.menu.PlayCue = self.runner.lua.eval("function() end")
        self.scene.TransitionPresentationState = self.runner.lua.eval(
            "function(self, state) self.PresentationState = state; return true end"
        )
        self.calc_view = self.state.clientHooks.CalcView["ZombieSim.Launcher.MenuCamera"]

    def send_status(self):
        launcher = self.server.ZM_Launcher
        launcher.SendStatus(launcher, self.state.target, "list", True, "")
        self.state.Deliver(self.state)

    def view(self):
        return self.calc_view(None, None, None, 90)

    def test_server_and_client_exchange_all_camera_poses(self):
        for profile in ("preview", "city"):
            self.state.map = "zn_" + profile + "_start"
            self.server.ZM_World.ActiveProfile = profile
            self.send_status()
            self.assertEqual(self.menu.Profile, profile)
            self.assertEqual((self.menu.Camera.origin.x, self.menu.Camera.fov), (1, 70))
            self.assertEqual(
                (self.menu.CreationCamera.origin.x, self.menu.CreationCamera.angles.y,
                 self.menu.CreationCamera.fov),
                (11, 15, 80),
            )
            self.assertEqual((self.menu.PreviewSkyCamera.origin.x, self.menu.PreviewSkyCamera.fov), (21, 90))
            self.assertEqual((self.menu.CreditsCamera.origin.x, self.menu.CreditsCamera.fov), (31, 90))
            self.assertEqual(self.menu.Globe.x, 41)

    def test_creation_and_appearance_own_the_view_until_exit(self):
        self.send_status()
        self.assertEqual(self.view().origin.x, 1)
        for step in range(2, 7):
            self.menu.Page = "create"
            self.menu.Step = step
            view = self.view()
            self.assertEqual((view.origin.x, view.angles.y, view.fov), (11, 15, 80))
            self.assertFalse(view.drawviewer)
            self.assertFalse(view.drawviewmodel)
            self.assertTrue(self.scene.IsPresentationHidden(self.scene))
        self.menu.Waiting = "create"
        self.assertEqual(self.view().origin.x, 11)
        self.assertTrue(self.scene.IsPresentationHidden(self.scene))
        self.menu.Waiting = None
        self.menu.Page = "appearance"
        self.assertEqual(self.view().origin.x, 11)

        self.menu.Page, self.menu.Step = "create", 3
        self.menu.Back(self.menu)
        self.assertEqual((self.menu.Page, self.menu.Step, self.view().origin.x), ("create", 2, 11))
        self.menu.Back(self.menu)
        self.assertEqual((self.menu.Page, self.view().origin.x), ("load", 1))
        self.assertFalse(self.scene.IsPresentationHidden(self.scene))

    def test_success_and_failure_restore_the_correct_camera(self):
        self.send_status()
        self.menu.Page = "create"
        self.menu.RequestReturnPage = "create"
        self.menu.ApplyRequestResult(self.menu, "create", False, "fixture failure", False)
        self.assertEqual((self.menu.Page, self.view().origin.x), ("create", 11))
        self.menu.ApplyRequestResult(self.menu, "create", True, "", False)
        self.assertEqual((self.menu.Page, self.view().origin.x), ("load", 1))

        self.menu.Page = "appearance"
        self.menu.Back(self.menu)
        self.assertEqual((self.menu.Page, self.view().origin.x), ("load", 1))

    def test_credits_and_inactive_launcher_take_precedence(self):
        self.send_status()
        self.menu.Page = "create"
        self.scene.CreditsView = self.runner.lua.eval("function() return { marker = 'credits' } end")
        self.menu.Credits = True
        self.assertEqual(self.view().marker, "credits")
        self.menu.Credits = False
        self.menu.Active = False
        self.assertIsNone(self.view())

    def test_absent_or_wrong_marker_warns_and_uses_the_previous_view(self):
        self.send_status()
        self.state.markers.create_character = None
        self.send_status()
        self.menu.Page = "create"
        self.assertIsNone(self.menu.CreationCamera)
        self.assertEqual(self.view().origin.x, 1)
        self.assertIn("using menu_camera", self.state.errors[1])
        self.send_status()
        self.assertEqual(len(self.state.errors), 1)

        self.state.markers.create_character = self.state.markers.menu_globe
        self.send_status()
        self.assertIsNone(self.menu.CreationCamera)
        self.assertEqual(len(self.state.errors), 1)
        self.state.map = "zn_city_start"
        self.server.ZM_World.ActiveProfile = "city"
        self.send_status()
        self.assertEqual(len(self.state.errors), 2)

    def test_creation_origin_is_included_in_each_launcher_pvs(self):
        visibility = self.state.serverHooks.SetupPlayerVisibility["ZombieSim.Launcher.MenuPVS"]
        for profile in ("preview", "city"):
            self.state.map = "zn_" + profile + "_start"
            self.server.ZM_World.ActiveProfile = profile
            self.state.pvs = self.runner.lua.table()
            visibility(self.state.target)
            xs = [point.x for _, point in self.state.pvs.items()]
            self.assertEqual(xs.count(1), 1)
            self.assertEqual(xs.count(11), 1)
            self.assertEqual(xs.count(21), 21)
        self.state.pvs = self.runner.lua.table()
        self.state.target.ZM_LauncherState = None
        visibility(self.state.target)
        self.assertEqual(len(self.state.pvs), 0)

    def test_in_game_camera_case_uses_and_restores_the_real_menu(self):
        self.send_status()
        original_page, original_camera = self.menu.Page, self.menu.Camera.origin.x
        case = self.state.presentationSuite.cases[
            "creation camera owns every creation and appearance step"
        ]
        check = self.runner.lua.eval("function(value, message) assert(value, message) end")
        case(check)
        self.assertEqual((self.menu.Page, self.menu.Camera.origin.x), (original_page, original_camera))
        self.assertEqual(self.menu.CreationCamera.origin.x, 11)

    def test_client_status_reports_readiness_and_the_received_pose(self):
        self.send_status()
        self.menu.Page = "menu"
        self.menu.Frame = self.runner.lua.eval("""{
            valid = true, IsVisible = function() return true end,
            GetChildren = function() return {} end
        }""")
        self.scene.GetMaterialStatus = self.runner.lua.eval("function() return {} end")
        self.scene.GetHorizonMaterialStatus = self.runner.lua.eval("function() return {} end")
        self.state.clientCommands["zombiesim_dev_launcher_presentation_status"]()
        report = self.state.clientWrites["zombiesim/launcher-presentation-status.json"]
        self.assertEqual(report.map, "zn_preview_start")
        self.assertTrue(report.launcher.active)
        self.assertTrue(report.launcher.frameVisible)
        self.assertTrue(report.launcher.earthControlsActive)
        self.assertEqual(report.launcher.page, "menu")
        self.assertEqual(report.launcher.creationCamera.origin.x, 11)
        self.assertEqual(report.launcher.creationCamera.angles.p, 14)
        self.assertEqual(report.launcher.creationCamera.fov, 80)

        self.state.markers.create_character = None
        self.send_status()
        self.state.clientCommands["zombiesim_dev_launcher_presentation_status"]()
        report = self.state.clientWrites["zombiesim/launcher-presentation-status.json"]
        self.assertFalse(report.launcher.creationCamera)

    def test_panel_status_counts_real_children_without_modifying_them(self):
        setup = self.runner.lua.eval("""function(menu)
            local frame = {valid = true}
            local function panel(name, visible, marked, alpha)
                return {
                    valid = true,
                    GetName = function() return name end,
                    GetParent = function() return frame end,
                    IsVisible = function() return visible end,
                    IsMarkedForDeletion = function() return marked end,
                    GetAlpha = function() return alpha end
                }
            end
            local stale = panel("DScrollPanel", true, false, 255)
            local pending = panel("DScrollPanel", false, true, 128)
            local current = panel("DScrollPanel", true, false, 255)
            frame.GetChildren = function() return {stale, pending, current} end
            menu.Frame, menu.Content = frame, current
        end""")
        setup(self.menu)
        report = self.menu.GetPanelStatus(self.menu)
        self.assertTrue(report.contentValid)
        self.assertTrue(report.contentParented)
        self.assertEqual(len(report.children), 3)
        self.assertFalse(report.children[1].currentContent)
        self.assertTrue(report.children[1].visible)
        self.assertFalse(report.children[1].markedForDeletion)
        self.assertTrue(report.children[2].markedForDeletion)
        self.assertEqual(report.children[2].alpha, 128)
        self.assertTrue(report.children[3].currentContent)
        self.menu.Frame = None
        report = self.menu.GetPanelStatus(self.menu)
        self.assertEqual(len(report.children), 0)
        self.assertFalse(report.contentParented)

    def test_discarded_pages_hide_before_deferred_removal(self):
        make = self.runner.lua.eval("""function()
            local calls = {}
            local panel = {valid = true}
            function panel:Stop() calls[#calls + 1] = "stop" end
            function panel:SetMouseInputEnabled(value) calls[#calls + 1] = "mouse:" .. tostring(value) end
            function panel:SetVisible(value) calls[#calls + 1] = "visible:" .. tostring(value) end
            function panel:Remove() calls[#calls + 1] = "remove" end
            return panel, calls
        end""")
        panel, calls = make()
        self.menu.DiscardPanel(self.menu, panel)
        self.assertEqual(list(calls.values()), ["stop", "mouse:false", "visible:false", "remove"])
        self.menu.DiscardPanel(self.menu, None)


if __name__ == "__main__":
    unittest.main()
