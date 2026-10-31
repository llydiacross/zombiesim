"""Exercise the world-map inspector's actual danger-star drawing function."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner, lua_source


class WorldMapDangerStarTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[2] / "gamemode"
        self.runner = FixtureRunner(root, ["cl_world_map.lua"])
        self.lua = self.runner.lua
        self.lua.execute("""
            WorldMap = {}
            polygons = {}
            colors = {}
            draw = { NoTexture = function() end }
            surface = {
                SetDrawColor = function(...) table.insert(colors, {...}) end,
                DrawPoly = function(points)
                    assert(type(points) == "table" and (#points == 3 or #points == 5),
                        "star polygon must have three or five vertices")
                    local snapshot = {}
                    for index, point in ipairs(points) do
                        assert(type(point.x) == "number" and type(point.y) == "number",
                            "star vertex must have numeric coordinates")
                        assert(point.x == point.x and point.y == point.y
                            and math.abs(point.x) < math.huge and math.abs(point.y) < math.huge,
                            "star vertex must be finite")
                        snapshot[index] = { x = point.x, y = point.y }
                    end
                    table.insert(polygons, snapshot)
                end
            }
        """)
        source = lua_source(root / "cl_world_map.lua")
        start = source.index("local function drawCellInspectorDangerStar(")
        end = source.index("\nlocal function createCellInspector(", start)
        self.draw_star = self.lua.execute(source[start:end] + "\nreturn drawCellInspectorDangerStar")
        self.color = self.lua.table_from({"r": 220, "g": 40, "b": 50, "a": 255})

    def test_both_passes_draw_complete_star_geometry(self):
        self.draw_star(100, 120, 7, self.color)
        polygons = self.lua.globals().polygons
        self.assertEqual(len(polygons), 12)
        self.assertEqual([len(polygons[index]) for index in range(1, 13)],
                         [5, 3, 3, 3, 3, 3] * 2)
        self.assertAlmostEqual(polygons[2][1].y, 112)
        self.assertAlmostEqual(polygons[8][1].y, 113)
        self.lua.execute("""
            local shape = WorldMap.InspectorDangerStarShape
            for index = 1, 5 do
                local triangle = shape.triangles[index]
                assert(triangle[1] == shape.tipPoints[index])
                assert(triangle[2] == shape.innerPoints[index])
                assert(triangle[3] == shape.innerPoints[index % 5 + 1])
            end
        """)

    def test_cache_is_reused_and_an_old_incomplete_cache_is_rebuilt(self):
        self.draw_star(20, 30, 7, self.color)
        self.lua.execute("originalShape = WorldMap.InspectorDangerStarShape")
        self.draw_star(-3, -4, 7, self.color)
        self.lua.execute("assert(originalShape == WorldMap.InspectorDangerStarShape)")
        self.lua.execute("WorldMap.InspectorDangerStarShape = { triangles = { { {}, {} } } }")
        self.draw_star(20, 30, 7, self.color)
        self.assertEqual(len(self.lua.globals().polygons), 36)


if __name__ == "__main__":
    unittest.main()
