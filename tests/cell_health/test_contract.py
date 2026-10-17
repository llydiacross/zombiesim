"""Offline regression tests for the Cell Health artifact contract."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]


class CellHealthContractTests(unittest.TestCase):
    def test_preview_artifact_status_contract(self):
        runner = FixtureRunner(
            ROOT / "gamemode",
            [
                "utils/test_harness.lua",
                "sh_cell_health_contract.lua",
                "tests/cl_cell_health_tests.lua",
                "tests/fixtures/cl_cell_health_engine.lua",
            ],
        )
        runner.lua.execute("""
            concommand = {
                Add = function() end,
                Remove = function() end
            }
        """)
        runner.load("utils/test_harness.lua")
        suite_factory = runner.load("tests/cl_cell_health_tests.lua")
        suite = suite_factory(
            runner.load("tests/fixtures/cl_cell_health_engine.lua"),
            runner.load,
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Cell Health artifact contract")


if __name__ == "__main__":
    unittest.main()
