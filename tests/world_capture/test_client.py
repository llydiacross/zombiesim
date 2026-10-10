"""Focused real-module fixtures using the shared offline GLua harness."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tests.glua.harness import FixtureRunner


def main():
    runner = FixtureRunner(ROOT / "gamemode", {
        "utils/test_harness.lua", "world_capture/sh_contract.lua", "cl_world_capture.lua",
        "tests/cl_world_capture_tests.lua", "tests/fixtures/cl_world_capture_engine.lua",
    })
    runner.load("utils/test_harness.lua")
    runner.load("tests/cl_world_capture_tests.lua")(
        runner.load("tests/fixtures/cl_world_capture_engine.lua"), runner.compile
    )
    runner.run(runner.lua.globals().ZM_WorldCaptureTests, "World capture client")
    runner = FixtureRunner(ROOT / "gamemode", {
        "utils/test_harness.lua", "world_capture/sh_contract.lua", "sv_world_capture.lua",
        "tests/sv_world_capture_tests.lua", "tests/fixtures/sv_world_capture_engine.lua",
    })
    runner.load("utils/test_harness.lua")
    runner.load("tests/sv_world_capture_tests.lua")(
        runner.load("tests/fixtures/sv_world_capture_engine.lua"), runner.compile
    )
    runner.run(runner.lua.globals().ZM_WorldCaptureServerTests, "World capture server")


if __name__ == "__main__":
    main()
