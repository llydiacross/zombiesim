"""Regression for optional catalogue durations and deferred resume bounds."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner


class OptionalDurationTests(unittest.TestCase):
    def test_validation_decoder_and_resume_contract(self):
        runner = FixtureRunner(Path(__file__).resolve().parents[2] / "gamemode", ["sh_music.lua"])
        runner.load("sh_music.lua")
        runner.lua.execute("""
            local music = ZM_Music
            local track = {id="cityE", name="City E", file="sounds/music/city 5.mp3"}
            local data = {schemaVersion=1, tracks={track}, sets={city={"cityE"}},
                defaultSet="city", idleSeconds={480,720}, safeZones={},
                environmentTags={}, tagPriority={}}
            local function validate()
                return music.Validate(data, function() return true end, {}, {})
            end
            local registry = assert(validate())
            assert(music.DurationMatches(187.62097916667, nil))
            assert(not music.DurationMatches(0, nil))
            assert(not music.DurationMatches(math.huge, nil))
            assert(not music.DurationMatches(0/0, nil))
            assert(music.ValidResume({version=1,trackId="cityE",position=185,nextAt=0}, registry))
            assert(not music.ValidResume({version=1,trackId="cityE",position=-1,nextAt=0}, registry))
            assert(not music.ValidResume({version=1,trackId="cityE",position=math.huge,nextAt=0}, registry))
            track.duration=184.2
            assert(not music.DurationMatches(187.62097916667, track.duration))
            assert(music.DurationMatches(184.8, track.duration))
            assert(not music.ValidResume({version=1,trackId="cityE",position=185,nextAt=0}, registry))
            for _, invalid in ipairs({0, -1, math.huge, "187"}) do
                track.duration=invalid
                assert(validate()==nil)
            end
        """)


if __name__ == "__main__":
    unittest.main()
