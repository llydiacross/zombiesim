"""Explicit ZM_World fixtures for structure-claim tile metadata (Alpha 3.4 Phase E)."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class WorldClaimTileTests(unittest.TestCase):
    def fixture(self):
        runner = FixtureRunner(ROOT, ["utils/world.lua"])
        lua = runner.lua
        lua.execute("""
            SERVER, CLIENT = true, false
            string.Trim = function(value) return (value:gsub("^%s+", ""):gsub("%s+$", "")) end
            file = {Read = function(path, mount)
                assert(mount == "GAME")
                return path == "fixture.json" and "{}" or nil
            end}
            util = {JSONToTable = function(json) return fixtureData end}
            function buildFixture(firstClaims, secondCell)
                fixtureData = {
                    schemaVersion = 1,
                    world = {grid = {2, 1}, population = 0, originSafeZoneId = "den", mapDirectory = "",
                        cellBounds = {revision = 2, tileSize = 640, coreTileGridSize = 5, coreHalfExtent = 1600,
                            traversableHalfExtent = 2240, visualHalfExtent = 2880, neighbourPitch = 5760,
                            coastContactHalfExtent = 2240, playableCeiling = 4608}},
                    atmosphereProfiles = {{id = "default", fog = {color = {0, 0, 0}, start = 0, ["end"] = 1, maxDensity = 0, stormMultiplier = 1}}},
                    safeZones = {{id = "den", map = "zz_den"}},
                    cells = {
                        {id = 0, map = "zz_a", atmosphereProfile = 0, waterSides = {}, exits = {}, claimTiles = firstClaims},
                        secondCell or {id = 1, map = "zz_b", atmosphereProfile = 0, waterSides = {}, exits = {}}
                    }
                }
            end
        """)
        runner.load("utils/world.lua")
        return lua

    def test_claim_tiles_load_and_resolve(self):
        lua = self.fixture()
        lua.execute("""
            buildFixture({{-2, 2}, {0, -1}, {2, -2}})
            local loaded, err = ZM_World:Load("fixture.json")
            assert(loaded, err)
            local tiles = ZM_World:GetClaimTiles(0)
            assert(#tiles == 3 and tiles[1].x == -2 and tiles[1].y == 2)
            tiles[1].x = 99
            assert(ZM_World:GetClaimTiles(0)[1].x == -2, "accessor returns copies")
            assert(ZM_World:IsClaimableTile(0, -2, 2))
            assert(ZM_World:IsClaimableTile(ZM_World:GetCellById(0), 0, -1))
            assert(not ZM_World:IsClaimableTile(0, 0, 0))
            assert(not ZM_World:IsClaimableTile(0, "-2", 2))
            assert(not ZM_World:IsClaimableTile("zz_a", -2, 2), "map names are not cell identity")
            assert(#ZM_World:GetClaimTiles(1) == 0, "cells without claimTiles have none")
            assert(not ZM_World:IsClaimableTile(1, -2, 2))
            assert(#ZM_World:GetClaimTiles(5) == 0)
        """)

    def test_core_tile_at_position(self):
        lua = self.fixture()
        lua.execute("""
            buildFixture({})
            assert(ZM_World:Load("fixture.json"))
            local function at(x, y) return ZM_World:GetCoreTileAt({x = x, y = y, z = 0}) end
            local x, y = at(0, 0); assert(x == 0 and y == 0)
            x, y = at(-1500, 1500); assert(x == -2 and y == 2)
            x, y = at(1000, -400); assert(x == 2 and y == -1)
            x, y = at(319, -321); assert(x == 0 and y == -1)
            assert(at(1600, 0) == nil and at(0, -1700) == nil, "outside the core")
            assert(at(0/0, 0) == nil)
        """)

    def test_load_rejects_malformed_claim_tiles(self):
        lua = self.fixture()
        for claims in ["{{3, 0}}", "{{0.5, 0}}", "{{0, 0}, {0, 0}}", "{{'0', 0}}", "{0, 0}", "'bad'"]:
            lua.execute("buildFixture(" + claims + ")")
            loaded, error = lua.eval('ZM_World:Load("fixture.json")')
            self.assertFalse(loaded, claims)
            self.assertIn("invalid claim tiles", error)

    def test_empty_cell_cannot_carry_claim_tiles(self):
        lua = self.fixture()
        lua.execute("""
            buildFixture({}, {id = 1, atmosphereProfile = 0, waterSides = {}, empty = true, topology = "empty",
                emptyTerrain = "grassland", exits = {}, claimTiles = {}})
        """)
        loaded, error = lua.eval('ZM_World:Load("fixture.json")')
        self.assertFalse(loaded)
        self.assertIn("invalid claim tiles", error)


if __name__ == "__main__":
    unittest.main()
