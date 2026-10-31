"""Offline launcher Cell Health entry and lifecycle fixtures."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from glua.harness import FixtureRunner, lua_source


class LauncherCellHealthTests(unittest.TestCase):
    def test_sidebar_and_manager(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            ["utils/test_harness.lua", "cl_launcher_tools.lua", "cl_cell_health.lua",
             "tests/cl_launcher_cell_health_tests.lua"],
        )
        runner.load("utils/test_harness.lua")
        source = lua_source(ROOT / "gamemode" / "cl_launcher_tools.lua")
        capability_start = source.index("function Tools:GetCapabilities(")
        capability_end = source.index("\nfunction Tools:IsAvailable()", capability_start)
        menu_start = source.index("function Tools:BuildMenu(")
        menu_end = source.index("\nfunction Tools:Open()", menu_start)
        extracted = (
            "ZM_LauncherTools = ZM_LauncherTools or {}\n"
            "local Tools = ZM_LauncherTools\n"
            "local colours = ZM_DermaSkin.Palette\n"
            + source[capability_start:capability_end]
            + "\n"
            + source[menu_start:menu_end]
        )
        load_tools = runner.lua.eval(
            "function(source) return function() return assert(loadstring(source)) end end"
        )(extracted)
        suite = runner.load("tests/cl_launcher_cell_health_tests.lua")(runner.compile, load_tools)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Launcher Cell Health")


if __name__ == "__main__":
    unittest.main()
