"""Run isolated client atmosphere regressions with LuaJIT (optional dependency: lupa)."""

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner, compare, lua_source, plain


ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, help="Optional retained pre-refactor cl_atmosphere.lua")
    args = parser.parse_args()
    source_root = ROOT / "gamemode"
    runner = FixtureRunner(source_root, [
        *(path.relative_to(source_root).as_posix() for path in (source_root / "atmosphere").glob("*.lua")),
        "utils/test_harness.lua", "tests/cl_atmosphere_tests.lua",
        "tests/fixtures/cl_atmosphere_engine.lua",
    ])
    lua = runner.lua
    lua.execute("concommand = { Add = function() end }")
    runner.register("tests/cl_atmosphere_tests.lua", "tests/fixtures/cl_atmosphere_engine.lua")
    tests = lua.globals().ZM_AtmosphereTests
    runner.run(tests, "Client atmosphere")
    if args.baseline:
        create_engine = runner.load("tests/fixtures/cl_atmosphere_engine.lua")
        run_baseline = lua.eval("function(source, env) local chunk = assert(loadstring(source)); setfenv(chunk, env); chunk(); return env.ZM_Atmosphere end")
        scenario = lua.eval("""
            function(atmosphere, env, reverse)
                local state = env.State
                local snapshots = {}
                local order = {
                    "ZM.Atmosphere.WaitForWorldData", "ZM.Atmosphere.WeatherEffects",
                    "ZM.Atmosphere.WetPuddles", "ZM.Atmosphere.BoundaryMist",
                    "ZM.Atmosphere.WeatherFootsteps", "ZM.Atmosphere.Winter",
                    "ZM.Atmosphere.SnowCover", "ZM.Atmosphere.RetiredWeatherCleanup"
                }
                local function frame()
                    state:Advance()
                    for index = 1, #order do
                        state:Hook("Think", order[reverse and (#order - index + 1) or index])
                    end
                    state:Hook("SetupWorldFog", "ZM.Atmosphere.WorldFog")
                    state:Hook("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", 0.0625)
                    state:Hook("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection")
                    state:Hook("PreDrawTranslucentRenderables", "ZM.Atmosphere.SnowCover", false, false)
                    state:Hook("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", false, false)
                end
                state.net = { 1 }
                state.receivers["ZM.SetAtmosphereProfile"]()
                state.worldReady = true
                for _, sample in ipairs({ {0, 0}, {1, 0}, {2, 1}, {0, 0.5} }) do
                    state:Weather(sample[1], sample[2])
                    for _ = 1, 45 do frame() end
                    snapshots[#snapshots + 1] = env.table.Copy(atmosphere:GetDiagnosticSnapshot())
                end
                env.ZM_Quality.ConVars.screenEffects = { GetFloat = function() return 0 end }
                state.radiation = 0.5
                frame()
                snapshots[#snapshots + 1] = env.table.Copy(atmosphere:GetDiagnosticSnapshot())
                state:Hook("PreCleanupMap", "ZM.Atmosphere.WeatherCleanup")
                snapshots[#snapshots + 1] = env.table.Copy(atmosphere:GetDiagnosticSnapshot())
                assert(not state.meshOpen and #state.errors == 0)
                local draws = {}
                for _, call in ipairs(state.calls) do
                    if call[1] ~= "SetMaterial" and call[1] ~= "PushModelMatrix" then
                        draws[#draws + 1] = call
                    end
                end
                local registry = {}
                for event, callbacks in pairs(state.hooks) do
                    for name in pairs(callbacks) do registry[#registry + 1] = event .. "/" .. name end
                end
                table.sort(registry)
                return {
                    snapshots = snapshots, draws = draws, registry = registry,
                    vertexCount = state.vertexCount, vertexSignature = state.vertexSignature, vertexAlpha = state.vertexAlpha
                }
            end
        """)
        for reverse in (False, True):
            old_env = create_engine()
            old_env.State.worldReady = False
            old_env.ZM_Atmosphere = lua.table_from({"SnowCoverAmount": 0})
            old = run_baseline(lua_source(args.baseline), old_env)
            new, _, new_env, _ = tests.NewFixture(lua.table_from({"worldReady": False}))
            expected = plain(scenario(old, old_env, reverse))
            actual = plain(scenario(new, new_env, reverse))
            compare(expected, actual)
            print(f"PASS baseline equivalence: {'reverse' if reverse else 'forward'} Think order, six diagnostic snapshots, {actual['vertexCount']} vertices and {len(actual['draws'])} draw/audio calls")


if __name__ == "__main__":
    main()
