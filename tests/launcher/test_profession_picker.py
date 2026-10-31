"""Exercise the actual launcher profession picker with explicit offline Derma fixtures."""

from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from glua.harness import FixtureRunner


class ProfessionPickerTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(
            ROOT,
            [
                "gamemode/utils/test_harness.lua",
                "gamemode/cl_launcher_profession_picker.lua",
                "gamemode/tests/cl_launcher_profession_picker_tests.lua",
                "tests/launcher/profession_fixture.lua",
            ],
        )
        self.runner.load("gamemode/utils/test_harness.lua")
        self.env, self.state = self.runner.load("tests/launcher/profession_fixture.lua")(
            self.runner.lua.globals().ZM_TestHarness
        )
        self.load_in_env = self.runner.lua.eval(
            "function(chunk, env) setfenv(chunk, env); return chunk() end"
        )
        self.picker = self.load_in_env(
            self.runner.compile("gamemode/cl_launcher_profession_picker.lua"), self.env
        )

    def test_shared_picker_cases(self):
        factory = self.load_in_env(
            self.runner.compile("gamemode/tests/cl_launcher_profession_picker_tests.lua"),
            self.env,
        )
        runnable = self.runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(factory(self.picker))
        self.runner.run(runnable, "Launcher profession picker")

    def test_missing_icon_is_reported_once(self):
        self.state.missingIcon = "icon16/heart.png"
        status = self.picker.GetIconStatus(self.picker, "Doctor")
        self.assertFalse(status.valid)
        self.assertEqual(status.path, self.state.missingIcon)
        self.picker.GetIconStatus(self.picker, "Doctor")
        self.assertEqual(len(self.state.errors), 1)
        self.assertIn(self.state.missingIcon, self.state.errors[1])

    def test_wrapped_label_height_invalidates_the_outer_layout(self):
        create = self.runner.lua.eval(
            """function(picker, env)
                local host = env.vgui.Create("DPanel")
                local menu = { Step = 4 }
                function menu:Render() end
                local function button(text, callback, parent)
                    local control = env.vgui.Create("DButton", parent or host)
                    control:SetText(text)
                    control.DoClick = callback
                    return control
                end
                return picker:Build(menu, host, { job = "Doctor", attributes = {} },
                    button, function(attribute) return attribute end)
            end"""
        )
        view = create(self.picker, self.env)
        view.root.PerformLayout(view.root, 640, view.root.GetTall(view.root))
        before = view.root.layoutInvalidations or 0
        old_height = view.details.GetTall(view.details)
        view.description.SetTall(view.description, view.description.GetTall(view.description) + 100)
        self.assertGreater(view.root.layoutInvalidations, before)
        view.root.PerformLayout(view.root, 640, view.root.GetTall(view.root))
        self.assertEqual(view.details.GetTall(view.details), old_height + 100)

    def test_positive_bonus_highlight_follows_selected_profession(self):
        create = self.runner.lua.eval(
            """function(picker, env)
                local host = env.vgui.Create("DPanel")
                local menu = { Step = 4 }
                function menu:Render() end
                local function button(text, callback, parent)
                    local control = env.vgui.Create("DButton", parent or host)
                    control:SetText(text)
                    control.DoClick = callback
                    return control
                end
                return picker:Build(menu, host, { job = "Doctor", attributes = {} },
                    button, function(attribute) return attribute end)
            end"""
        )
        view = create(self.picker, self.env)
        same = self.runner.lua.eval("function(a, b) return a == b end")
        medicine = view.rows.Medicine
        medicine.Paint(medicine, 120, 24)
        self.assertTrue(same(self.state.lastColor[1], self.env.ZM_DermaSkin.Palette.bonus))
        self.assertTrue(same(view["values"].Medicine.textColor, self.env.ZM_DermaSkin.Palette.bonus))
        self.assertEqual(self.state.lastRect[3], 3)

        view.cards.Civilian.DoClick()
        medicine.Paint(medicine, 120, 24)
        self.assertFalse(same(self.state.lastColor[1], self.env.ZM_DermaSkin.Palette.bonus))
        self.assertTrue(same(view["values"].Medicine.textColor, self.env.ZM_DermaSkin.Palette.muted))
        self.assertEqual(self.state.lastRect[3], 120)

    def test_shipped_professions_have_distinct_icons(self):
        definitions = json.loads(
            (ROOT / "content" / "data_static" / "profession_definitions.json").read_text(
                encoding="utf-8"
            )
        )["professions"]
        paths = {
            self.picker.GetIconStatus(self.picker, job_id).path
            for job_id in definitions
        }
        self.assertEqual(len(paths), len(definitions))

    def test_client_wiring_loads_and_distributes_picker(self):
        server = (ROOT / "gamemode" / "init.lua").read_text(encoding="utf-8")
        client = (ROOT / "gamemode" / "cl_init.lua").read_text(encoding="utf-8")
        self.assertIn('AddCSLuaFile( "cl_launcher_profession_picker.lua" )', server)
        self.assertIn('AddCSLuaFile( "tests/cl_launcher_profession_picker_tests.lua" )', server)
        self.assertLess(
            client.index('include( "cl_launcher_profession_picker.lua" )'),
            client.index('include( "cl_launcher_menu.lua" )'),
        )


if __name__ == "__main__":
    unittest.main()
