"""Offline fixtures for the claim-mode client's pure helpers (Alpha 3.5): tile geometry, clipping and tile state."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class ClaimsClientTests(unittest.TestCase):
    def setUp(self):
        runner = FixtureRunner(ROOT, ["cl_claims.lua"])
        self.lua = runner.lua
        self.lua.execute("""
            receivers, hooks, commands = {}, {}, {}
            net = { Receive = function(name, callback) receivers[name] = callback end }
            hook = { Add = function(event, name, callback) hooks[event .. "/" .. name] = callback end }
            concommand = { Add = function(name, callback) commands[name] = callback end }
            function Material(path) return { path = path } end
            function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
        """)
        runner.load("cl_claims.lua")

    def run_lua(self, source):
        self.lua.execute(source)

    def test_registers_snapshot_and_input_owners(self):
        self.run_lua("""
            assert(receivers["ZM.Claims.Snapshot"] and receivers["ZM.Claims.Result"])
            assert(commands["zombiesim_claim_mode"])
            assert(hooks["PlayerBindPress/ZM.Claims.Input"] and hooks["CreateMove/ZM.Claims.BlockAttack"])
            assert(hooks["PostDrawTranslucentRenderables/ZM.Claims.WorldHighlight"])
        """)

    def test_tile_corners_and_reach_match_the_server_rule(self):
        self.run_lua("""
            local corners = ZM_Claims.TileCorners(1, -1, 640)
            assert(corners[1].x == 320 and corners[1].y == -320)
            assert(corners[3].x == 960 and corners[3].y == -960)
            assert(ZM_Claims.WithinReach({ x = 960, y = 0 }, 0, 0, 640))
            assert(not ZM_Claims.WithinReach({ x = 960.01, y = 0 }, 0, 0, 640))
            assert(not ZM_Claims.WithinReach({ x = 0, y = -1000 }, 0, 0, 640))
        """)

    def test_grid_tile_rect_keeps_north_up(self):
        self.run_lua("""
            local x, y, w, h = ZM_Claims.GridTileRect(100, 200, 576, 576, 0, 0, 640, 5760)
            assert(math.abs(x - (100 + 288 - 32)) < 1e-6 and math.abs(y - (200 + 288 - 32)) < 1e-6)
            assert(math.abs(w - 64) < 1e-6 and math.abs(h - 64) < 1e-6)
            local _, northTop = ZM_Claims.GridTileRect(100, 200, 576, 576, 0, 2, 640, 5760)
            local _, southTop = ZM_Claims.GridTileRect(100, 200, 576, 576, 0, -2, 640, 5760)
            assert(northTop < y and southTop > y, "north tiles are drawn above the centre")
            local eastX = ZM_Claims.GridTileRect(100, 200, 576, 576, 2, 0, 640, 5760)
            assert(eastX > x)
        """)

    def test_clip_polygon_and_winding(self):
        self.run_lua("""
            local square = { { x = -10, y = -10 }, { x = 10, y = -10 }, { x = 10, y = 10 }, { x = -10, y = 10 } }
            local clipped = ZM_Claims.ClipPolygon(square, 0, 0, 100, 100)
            assert(#clipped == 4)
            for _, point in ipairs(clipped) do
                assert(point.x >= 0 and point.x <= 10 and point.y >= 0 and point.y <= 10)
            end
            assert(#ZM_Claims.ClipPolygon(square, 50, 50, 10, 10) == 0, "fully outside is dropped")
            local anticlockwise = { { x = 0, y = 0 }, { x = 0, y = 10 }, { x = 10, y = 10 }, { x = 10, y = 0 } }
            ZM_Claims.Clockwise(anticlockwise)
            assert(anticlockwise[1].x == 10 and anticlockwise[1].y == 0)
        """)

    def test_tile_state_classification(self):
        self.run_lua("""
            local snapshot = {
                claimable = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 2, y = 0 }, { x = 0, y = 1 }, { x = 0, y = 2 } },
                claims = {
                    { tileX = 0, tileY = 0, active = true, mine = true, access = true },
                    { tileX = 1, tileY = 0, active = true, mine = false, access = true },
                    { tileX = 2, tileY = 0, active = true, mine = false, access = false },
                    { tileX = 0, tileY = 1, active = false, mine = true, access = true },
                    { tileX = 0, tileY = 2, active = false, mine = false, access = false }
                }
            }
            assert(ZM_Claims.TileState(snapshot, 0, 0) == "mine")
            assert(ZM_Claims.TileState(snapshot, 1, 0) == "friend")
            assert(ZM_Claims.TileState(snapshot, 2, 0) == "other")
            assert(ZM_Claims.TileState(snapshot, 0, 1) == "lapsed")
            assert(ZM_Claims.TileState(snapshot, 0, 2) == "free", "someone else's lapsed claim is replaceable")
            assert(ZM_Claims.TileState(snapshot, -1, 0) == nil)
        """)

    def test_world_grid_uses_both_grid_coordinates(self):
        self.run_lua("""
            polys = 0
            draw = { NoTexture = function() end }
            surface = { SetDrawColor = function() end, DrawPoly = function() polys = polys + 1 end }
            math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
            local cell = { id = 7 }
            ZM_World = {
                GetCellById = function(_, id) return id == 7 and cell or nil end,
                GetCellBounds = function() return { tileSize = 640, neighbourPitch = 5760 } end
            }
            ZM_Claims.Snapshot = { tileSize = 640, cellId = 0, claims = {}, claimable = {},
                owned = { { cellId = 7, tileX = 1, tileY = -1, active = true } } }
            -- The world map's helper returns two values; both must reach the box.
            local function gridCoordinates(c) return 3, 4 end
            ZM_Claims:DrawWorldGrid(0, 0, 100, 100, gridCoordinates, 0, 0, 2000, 2000)
            assert(ZM_Claims.MapDraws == 1 and polys > 0)
        """)


if __name__ == "__main__":
    unittest.main()
