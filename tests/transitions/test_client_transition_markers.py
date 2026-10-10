"""Run isolated transition-arrow geometry, rendering and lifecycle regressions."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner


def main():
    source_root = Path(__file__).resolve().parents[2] / "gamemode"
    runner = FixtureRunner(source_root, [
        "utils/test_harness.lua", "cl_transition_markers.lua",
        "tests/cl_transition_markers_tests.lua", "tests/fixtures/cl_transition_markers_engine.lua",
    ])
    runner.lua.execute("concommand = { Add = function() end }")
    runner.register("tests/cl_transition_markers_tests.lua", "tests/fixtures/cl_transition_markers_engine.lua")
    runner.run(runner.lua.globals().ZM_TransitionMarkersTests, "Client transition markers")


if __name__ == "__main__":
    main()
