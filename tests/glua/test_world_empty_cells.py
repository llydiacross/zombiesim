"""Explicit ZM_World fixtures for roadless "empty" cells (no map, no travel)."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class WorldEmptyCellTests(unittest.TestCase):
    def fixture(self, middle_cell):
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
            local function road(direction, cell)
                return {direction = direction, cell = cell, modes = {{type = "road", blocked = false}}}
            end
            function buildFixture(middle)
                fixtureData = {
                    schemaVersion = 1,
                    world = {grid = {3, 1}, population = 0, originSafeZoneId = "den", mapDirectory = ""},
                    atmosphereProfiles = {{id = "default", fog = {color = {0, 0, 0}, start = 0, ["end"] = 1, maxDensity = 0, stormMultiplier = 1}}},
                    safeZones = {{id = "den", map = "zz_den"}},
                    cells = {
                        {id = 0, map = "zz_west", atmosphereProfile = 0, exits = {road("E", 1)}},
                        middle,
                        {id = 2, map = "zz_east", atmosphereProfile = 0, exits = {road("W", 1)}}
                    }
                }
            end
        """)
        lua.globals().buildFixture(middle_cell)
        runner.load("utils/world.lua")
        return lua

    def empty_middle(self, lua, **overrides):
        cell = lua.table_from({
            "id": 1, "atmosphereProfile": 0, "empty": True, "topology": "empty",
            "emptyTerrain": "radioactive", "emptyColor": lua.table_from([103, 118, 60]),
            "exits": lua.table_from([]),
        })
        for key, value in overrides.items():
            cell[key] = value
        return cell

    def test_empty_cell_loads_without_map_and_cannot_be_entered(self):
        lua = self.fixture(None)
        lua.globals().buildFixture(self.empty_middle(lua))
        lua.execute("""
            local loaded, err = ZM_World:Load("fixture.json")
            assert(loaded, err)
            assert(ZM_World:IsEmptyCell(1, 0) == true)
            assert(ZM_World:IsEmptyCell(0, 0) == false)
            assert(ZM_World:GetEmptyCellTerrain(1, 0) == "radioactive")
            assert(ZM_World:GetEmptyCellTerrain(0, 0) == nil)
            assert(ZM_World:GetMapPath(1, 0) == nil)
            assert(#ZM_World:GetCellsForMap("zz_west") == 1)
            assert(ZM_World:CanTravel(0, 0, "E") == nil, "empty cells cannot be travelled to")
            assert(ZM_World:GetTransitionMap(0, 0, "E") == nil)
            local path = ZM_World:FindPath(ZM_World:GetCell(0, 0), ZM_World:GetCell(1, 0))
            assert(path == nil, "routes must not enter an empty cell")
        """)

    def test_load_rejects_empty_cell_with_map_or_exits(self):
        lua = self.fixture(None)
        cases = [
            {"map": "zz_middle"},
            {"exits": lua.table_from([lua.table_from({"direction": "W", "cell": 0, "modes": lua.table_from([])})])},
            {"emptyTerrain": ""},
        ]
        for overrides in cases:
            lua.globals().buildFixture(self.empty_middle(lua, **overrides))
            loaded, error = lua.eval('ZM_World:Load("fixture.json")')
            self.assertFalse(loaded, overrides)
            self.assertIn("invalid empty cell", error)


if __name__ == "__main__":
    unittest.main()
