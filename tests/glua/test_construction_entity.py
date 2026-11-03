"""Exercise the real construction entity's collision initialization offline."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]
SHARED = "gamemode/sh_construction.lua"
ENTITY_SHARED = "entities/entities/zn_construction_piece/shared.lua"
ENTITY_INIT = "entities/entities/zn_construction_piece/init.lua"


class ConstructionEntityTests(unittest.TestCase):
    def setUp(self):
        runner = FixtureRunner(ROOT, [SHARED, ENTITY_SHARED, ENTITY_INIT])
        self.lua = runner.lua
        self.lua.execute("""
            ENT = {}
            function AddCSLuaFile() end
            function Vector(x, y, z) return { x = x, y = y, z = z } end
            function Angle(p, y, r) return { p = p, y = y, r = r } end
            function IsValid(value) return value ~= nil and value.valid == true end
            errors = {}
            function ErrorNoHalt(message) errors[#errors + 1] = message end
            RENDERGROUP_BOTH = 1
            MOVETYPE_NONE, MOVETYPE_VPHYSICS, SOLID_VPHYSICS = 2, 3, 4
            COLLISION_GROUP_NONE, COLLISION_GROUP_WORLD, CONTINUOUS_USE = 5, 6, 7
        """)
        runner.load(SHARED)
        self.lua.globals().include = lambda name: runner.load(
            "entities/entities/zn_construction_piece/" + name
        )
        runner.load(ENTITY_INIT)
        self.lua.execute("""
            function makePiece(kind, yaw, complete, initResult, physicsValid)
                local entity = {
                    valid = true, kind = kind, yaw = yaw, complete = complete,
                    initResult = initResult, calls = {}, physics = { valid = physicsValid }
                }
                setmetatable(entity, { __index = ENT })
                local function record(name) entity.calls[#entity.calls + 1] = name end
                function entity:GetPieceKind() return self.kind end
                function entity:GetPieceYaw() return self.yaw end
                function entity:GetComplete() return self.complete end
                function entity:SetModel(value) self.model = value; record("model") end
                function entity:SetAngles(value) self.angles = value; record("angles") end
                function entity:PhysicsInitBox(mins, maxs)
                    self.mins, self.maxs = mins, maxs
                    record("box")
                    return self.initResult
                end
                function entity:PhysicsInitMultiConvex(vertices)
                    self.convexes = vertices
                    record("multi")
                    return self.initResult
                end
                function entity:SetMoveType(value) self.moveType = value; record("move") end
                function entity:SetSolid(value) self.solid = value; record("solid") end
                function entity:SetCollisionBounds(mins, maxs)
                    self.mins, self.maxs = mins, maxs
                    record("bounds")
                end
                function entity:EnableCustomCollisions() self.custom = true; record("custom") end
                function entity:GetPhysicsObject() return self.physics end
                function entity.physics:EnableMotion(value) self.motion = value end
                function entity:SetCollisionGroup(value) self.group = value; record("group") end
                function entity:SetUseType(value) self.useType = value; record("use") end
                function entity:Remove() self.valid = false; record("remove") end
                return entity
            end
        """)

    def test_existing_boxes_keep_box_physics_and_frozen_blueprints(self):
        self.lua.execute("""
            foundation = makePiece("foundation", 0, false, true, true)
            foundation:Initialize()
            wall = makePiece("wall", 90, true, true, true)
            wall:Initialize()
        """)
        g = self.lua.globals()
        for piece in (g.foundation, g.wall):
            self.assertTrue(piece.ZM_CollisionReady)
            self.assertEqual(piece.moveType, 2)
            self.assertIsNone(piece.convexes)
            self.assertFalse(piece.physics.motion)
            self.assertEqual(piece.useType, 7)
        self.assertEqual(g.foundation.group, 6)
        self.assertEqual(g.wall.group, 5)
        self.assertEqual((g.foundation.mins.x, g.foundation.maxs.z), (-32, 16))
        self.assertEqual((g.wall.mins.x, g.wall.maxs.y, g.wall.maxs.z), (-4, 32, 128))
        self.assertEqual(len(g.errors), 0)

    def test_complex_shapes_use_frozen_custom_multiconvex_physics(self):
        for kind, count, vertices in (
            ("foundation_triangle", 1, 6),
            ("wall_doorway", 3, 8),
            ("wall_window", 4, 8),
            ("roof_slope", 1, 8),
            ("roof_corner_outer", 2, 6),
            ("roof_corner_inner", 2, 6),
            ("stairs", 8, 8),
            ("ramp", 1, 8),
        ):
            with self.subTest(kind=kind):
                make = self.lua.globals().makePiece
                piece = make(kind, 90, False, True, True)
                piece.Initialize(piece)
                self.assertTrue(piece.ZM_CollisionReady)
                self.assertEqual(piece.moveType, 3)
                self.assertEqual(piece.solid, 4)
                self.assertTrue(piece.custom)
                self.assertFalse(piece.physics.motion)
                self.assertEqual(len(piece.convexes), count)
                self.assertTrue(all(len(convex) == vertices for convex in piece.convexes.values()))
                calls = list(piece.calls.values())
                self.assertLess(calls.index("solid"), calls.index("multi"))
                self.assertLess(calls.index("multi"), calls.index("custom"))

    def test_failed_or_missing_physics_is_reported_and_never_ready(self):
        self.lua.execute("""
            badBox = makePiece("foundation", 0, false, false, true)
            badBox:Initialize()
            badConvex = makePiece("wall_doorway", 0, false, false, true)
            badConvex:Initialize()
            noObject = makePiece("stairs", 0, false, true, false)
            noObject:Initialize()
            unknown = makePiece("unknown", 0, false, true, true)
            unknown:Initialize()
        """)
        g = self.lua.globals()
        for piece in (g.badBox, g.badConvex, g.noObject, g.unknown):
            self.assertFalse(piece.valid)
            self.assertIsNone(piece.ZM_CollisionReady)
        self.assertEqual(len(g.errors), 4)
        self.assertIn("Could not initialize", g.errors[1])
        self.assertIn("Could not initialize", g.errors[2])
        self.assertIn("physics object is unavailable", g.errors[3])
        self.assertIn("unknown shape", g.errors[4])


if __name__ == "__main__":
    unittest.main()
