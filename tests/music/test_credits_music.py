"""Exercise credits audio and launcher lifecycle against explicit engine fixtures."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2]


class CreditsMusicTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, ["tests/music/credits_engine.lua", "gamemode/cl_music.lua"])
        self.runner.load("tests/music/credits_engine.lua")
        self.runner.load("gamemode/cl_music.lua")
        source = lua_source(ROOT / "gamemode" / "cl_launcher_menu.lua")
        start = source.index("function Menu:StartCredits()")
        end = source.index("function Menu:ApplyRequestResult(", start)
        self.runner.lua.execute(source[start:end])

    def test_escape_fades_credits_and_resumes_exact_menu_position(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            menu.position = 37
            Menu:StartCredits()
            assert(menu.state == GMOD_CHANNEL_PAUSED and not Menu.Frame.visible)
            assert(fixture.pending[2].path == "sounds/music/credits.mp3")
            local credits = fixture:Complete(2)
            assert(credits.state == GMOD_CHANNEL_PLAYING and credits.volume == 0)
            fixture:Advance(0.4)
            assert(math.abs(credits.volume - 0.8) < 0.000001)
            fixture.musicVolume = 0.4
            fixture:Advance(0.1)
            assert(math.abs(credits.volume - 0.4) < 0.000001)
            local overlay = Menu.CreditsOverlay
            overlay:OnKeyCodePressed(KEY_ESCAPE)
            fixture:Advance(0.2)
            assert(credits.valid and math.abs(credits.volume - 0.2) < 0.000001)
            fixture:Advance(0.21)
            assert(not credits.valid and not Menu.Credits and ZM_Music.CreditsMusic == nil)
            assert(menu.state == GMOD_CHANNEL_PLAYING and menu.position == 37 and Menu.Frame.visible)
            assert(fixture.requests[1].action == "credits_stop" and fixture.cues[1] == "back")
        """)

    def test_pending_menu_and_late_credits_load_never_overlap(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            Menu:StartCredits()
            local menu = fixture:Complete(1)
            assert(menu.plays == 0 and menu.state == GMOD_CHANNEL_STOPPED)
            Menu.CreditsOverlay:OnMousePressed()
            fixture:Advance(0.41)
            assert(menu.state == GMOD_CHANNEL_PLAYING and not Menu.Credits)
            local late = fixture:Complete(2)
            assert(not late.valid and late.plays == 0)
        """)

    def test_pending_menu_load_resumes_after_credits_exit(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            Menu:StartCredits()
            local credits = fixture:Complete(2)
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(not credits.valid and ZM_Music.LauncherTrackPhase == "intro_loading")
            local menu = fixture:Complete(1)
            assert(menu.state == GMOD_CHANNEL_PLAYING and menu.plays == 1)
        """)

    def test_natural_track_end_and_scrolling_exit_allow_reentry(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            Menu:StartCredits()
            local first = fixture:Complete(2)
            first.state = GMOD_CHANNEL_STOPPED
            fixture:Advance(0.1)
            assert(not first.valid and ZM_Music.CreditsMusic.phase == "finished")
            assert(menu.state == GMOD_CHANNEL_PAUSED and #fixture.pending == 2)
            fixture:Advance(500)
            Menu.CreditsOverlay:Paint(1280, 720)
            fixture:Advance(0.41)
            assert(not Menu.Credits and menu.state == GMOD_CHANNEL_PLAYING)
            Menu:StartCredits()
            local second = fixture:Complete(3)
            assert(menu.state == GMOD_CHANNEL_PAUSED and second.state == GMOD_CHANNEL_PLAYING)
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(not second.valid and menu.state == GMOD_CHANNEL_PLAYING)
        """)

    def test_enable_disable_pauses_credits_and_restores_menu(self):
        self.runner.lua.execute("""
            fixture.musicEnabled = false
            Menu:StartCredits()
            assert(#fixture.pending == 0 and ZM_Music.CreditsMusic.phase == "waiting")
            fixture.musicEnabled = true
            fixture:Advance(0.1)
            local credits = fixture:Complete(1)
            credits.position = 11
            fixture.musicEnabled = false
            fixture:Advance(0.1)
            assert(credits.state == GMOD_CHANNEL_PAUSED)
            fixture.musicEnabled = true
            fixture:Advance(0.1)
            assert(credits.state == GMOD_CHANNEL_PLAYING and credits.position == 11)
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(not credits.valid and fixture.pending[2].path == "sounds/music/menu.mp3")
            local menu = fixture:Complete(2)
            assert(menu.state == GMOD_CHANNEL_PLAYING)
        """)

    def test_missing_and_failed_audio_report_errors_and_restore_menu(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            fixture.paths["sounds/music/credits.mp3"] = nil
            Menu:StartCredits()
            assert(ZM_Music.CreditsMusic.phase == "failed" and #fixture.pending == 1)
            assert(string.find(fixture.errors[1], "Credits music is missing", 1, true))
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(menu.state == GMOD_CHANNEL_PLAYING)
            fixture.paths["sound/music/credits.mp3"] = true
            Menu:StartCredits()
            assert(fixture.pending[2].path == "sound/music/credits.mp3")
            fixture:Complete(2, true)
            assert(ZM_Music.CreditsMusic.phase == "failed")
            assert(string.find(fixture.errors[2], "fixture decoding error", 1, true))
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(menu.state == GMOD_CHANNEL_PLAYING)
        """)

    def test_invalidated_credits_channel_reports_failure_and_restores_menu(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            Menu:StartCredits()
            local credits = fixture:Complete(2)
            credits.valid, credits.state = false, GMOD_CHANNEL_STOPPED
            fixture:Advance(0.1)
            assert(ZM_Music.CreditsMusic.phase == "failed")
            assert(string.find(fixture.errors[1], "channel became invalid", 1, true))
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(menu.state == GMOD_CHANNEL_PLAYING)
        """)

    def test_unexpected_overlay_removal_cleans_up_and_shutdown_cancels_loads(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            Menu:StartCredits()
            Menu.CreditsOverlay:Remove()
            assert(Menu.CreditsEnding ~= nil)
            fixture:Advance(0.41)
            assert(not Menu.Credits and menu.state == GMOD_CHANNEL_PLAYING)
            local late = fixture:Complete(2)
            assert(not late.valid and late.plays == 0)
            Menu:StartCredits()
            fixture.hooks["ShutDown:ZM.Music"]()
            assert(not menu.valid and ZM_Music.CreditsMusic == nil)
            local shutdownLate = fixture:Complete(3)
            assert(not shutdownLate.valid and shutdownLate.plays == 0)
        """)

    def test_reentry_during_fade_cannot_be_closed_by_the_old_timer(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            Menu:StartCredits()
            local first = fixture:Complete(2)
            Menu:EndCredits()
            Menu:StartCredits()
            assert(not first.valid and menu.state == GMOD_CHANNEL_PAUSED)
            local second = fixture:Complete(3)
            fixture:Advance(0.41)
            assert(Menu.Credits and second.state == GMOD_CHANNEL_PLAYING)
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(not second.valid and menu.state == GMOD_CHANNEL_PLAYING)
        """)

    def test_sky_preview_stops_before_credits_and_cannot_restart_during_them(self):
        self.runner.lua.execute("""
            ZM_Music:PlayLauncherTrackOnce()
            local menu = fixture:Complete(1)
            menu:Pause()
            local owner = { startedAt = fixture.now, duration = 10 }
            ZM_SkyInspection = { State = owner }
            ZM_Music:StartSkyPreview(owner)
            local sky = fixture:Complete(2)
            Menu:StartCredits()
            assert(not sky.valid and ZM_Music.SkyPreview == nil)
            local credits = fixture:Complete(3)
            ZM_Music:StartSkyPreview(owner)
            assert(#fixture.pending == 3 and credits.state == GMOD_CHANNEL_PLAYING)
            assert(string.find(fixture.errors[1], "cannot start during credits", 1, true))
            Menu:EndCredits()
            fixture:Advance(0.41)
            assert(menu.state == GMOD_CHANNEL_PLAYING)
        """)

    def test_pending_sky_preview_cannot_start_after_credits_open(self):
        self.runner.lua.execute("""
            local owner = { startedAt = fixture.now, duration = 10 }
            ZM_SkyInspection = { State = owner }
            ZM_Music:StartSkyPreview(owner)
            Menu:StartCredits()
            local lateSky = fixture:Complete(1)
            assert(not lateSky.valid and lateSky.plays == 0)
            local credits = fixture:Complete(2)
            assert(credits.state == GMOD_CHANNEL_PLAYING and ZM_Music.SkyPreview == nil)
        """)


if __name__ == "__main__":
    unittest.main()
