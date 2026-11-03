"""Fixture the shared construction renderer and client entity without a GMod renderer."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]
SHARED = "gamemode/sh_construction.lua"
GEOMETRY = "gamemode/cl_construction_geometry.lua"
ENTITY_SHARED = "entities/entities/zn_construction_piece/shared.lua"
ENTITY_CLIENT = "entities/entities/zn_construction_piece/cl_init.lua"


class ConstructionRenderTests(unittest.TestCase):
    def setUp(self):
        runner = FixtureRunner(ROOT, [SHARED, GEOMETRY, ENTITY_SHARED, ENTITY_CLIENT])
        self.lua = runner.lua
        self.lua.execute("""
            local vectorMeta = {}
            vectorMeta.__index = vectorMeta
            vectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
            function vectorMeta:SetUnpacked(x, y, z) self.x, self.y, self.z = x, y, z end
            function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vectorMeta) end
            function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
            function FrameNumber() return frame or 1 end
            function CurTime() return now or 10 end
            math.Clamp = function(value, low, high) return math.min(math.max(value, low), high) end
            angle_zero = {}
            drawn = { boxes = {}, wires = {}, quads = {}, lines = {} }
            render = {
                DrawBox = function(origin, angle, mins, maxs, color)
                    drawn.boxes[#drawn.boxes + 1] = { origin = origin, mins = mins, maxs = maxs, color = color }
                end,
                DrawWireframeBox = function(origin, angle, mins, maxs, color, depth)
                    drawn.wires[#drawn.wires + 1] = { origin = origin, mins = mins, maxs = maxs, depth = depth, color = color }
                end,
                DrawQuad = function(a, b, c, d, color)
                    drawn.quads[#drawn.quads + 1] = {
                        Vector(a.x, a.y, a.z), Vector(b.x, b.y, b.z),
                        Vector(c.x, c.y, c.z), Vector(d.x, d.y, d.z), color = color
                    }
                end,
                DrawLine = function(a, b, color, depth)
                    drawn.lines[#drawn.lines + 1] = {
                        a = Vector(a.x, a.y, a.z), b = Vector(b.x, b.y, b.z), depth = depth
                    }
                end,
                SetMaterial = function(material) currentMaterial = material end,
                SetColorMaterial = function() currentMaterial = "color" end,
                ComputeLighting = function() return Vector(1, 1, 1) end
            }
            materialsCreated = {}
            function CreateMaterial(name, shader, keys)
                local material = { name = name, shader = shader, keys = keys }
                function material:IsError() return false end
                function material:GetShader() return self.shader end
                function material:GetTexture(key)
                    if not self.keys[key] then return nil end
                    return { Width = function() return 256 end }
                end
                materialsCreated[#materialsCreated + 1] = material
                return material
            end
            netReceivers = {}
            net = { Receive = function(name, callback) netReceivers[name] = callback end }
            ENT = {}
            RENDERGROUP_BOTH = 1
        """)
        runner.load(SHARED)
        self.lua.execute("""
            function ZM_Construction:PieceSelectedForDeletion(entity) return entity.deleteSelected == true end
        """)
        runner.load(GEOMETRY)
        self.lua.globals().include = lambda name: runner.load(
            "entities/entities/zn_construction_piece/" + name
        )
        runner.load(ENTITY_CLIENT)
        self.lua.execute("""
            function makePiece(kind, yaw)
                local entity = { kind = kind, yaw = yaw, pos = Vector(0, 0, 0), progress = 0, complete = false }
                setmetatable(entity, { __index = ENT })
                function entity:GetPieceKind() return self.kind end
                function entity:GetPieceYaw() return self.yaw end
                function entity:GetPos() return self.pos end
                function entity:GetComplete() return self.complete end
                function entity:GetProgress() return self.progress end
                function entity:GetCompletedAt() return self.completedAt or 0 end
                function entity:GetWear() return self.wear or 0 end
                function entity:SetRenderBounds(mins, maxs) self.mins, self.maxs = mins, maxs end
                return entity
            end
        """)
        self.geometry = self.lua.globals().ZM_Construction.Geometry

    def test_selected_blueprints_and_finished_pieces_turn_red_without_an_extra_overlay(self):
        self.lua.execute("""
            piece = makePiece("floor", 0)
            piece.deleteSelected = true
            piece:DrawTranslucent()
            assert(#drawn.wires == 1 and drawn.wires[1].color.r == 255 and drawn.wires[1].color.g == 55)
            piece.complete, piece.completedAt, now = true, 0, 100
            piece:Draw()
            assert(#drawn.boxes == 1 and drawn.boxes[1].color.r == 255 and drawn.boxes[1].color.g == 55)
            piece.deleteSelected = false
            piece:Draw()
            assert(drawn.boxes[2].color.g ~= 55)
        """)

    def test_damage_stages_darken_and_reveal_stable_marks(self):
        self.lua.execute("""
            local meta = getmetatable(Vector(0, 0, 0))
            meta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
            meta.__mul = function(a, s) return Vector(a.x * s, a.y * s, a.z * s) end
            meta.__div = function(a, s) return Vector(a.x / s, a.y / s, a.z / s) end
            function meta:Add(o) self.x, self.y, self.z = self.x + o.x, self.y + o.y, self.z + o.z end
            function meta:Div(s) self.x, self.y, self.z = self.x / s, self.y / s, self.z / s end
            function meta:Mul(s) self.x, self.y, self.z = self.x * s, self.y * s, self.z * s end
            function meta:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
            function meta:Cross(o)
                return Vector(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x)
            end
            function meta:Length() return math.sqrt(self:Dot(self)) end
            function meta:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
            function ENT:EntIndex() return 42 end
            easy = {}
            render.DrawQuadEasy = function(position, normal, w, h, color, rotation)
                easy[#easy + 1] = { position = position, normal = normal, size = w }
            end
            now = 100
            piece = makePiece("wall", 0)
            piece.complete, piece.completedAt = true, 0
            function counts(wear)
                piece.wear = wear
                easy, drawn.boxes = {}, {}
                piece:Draw()
                local shade = drawn.boxes[1].color.r
                piece:DrawTranslucent()
                return #easy, shade
            end
            freshMarks, freshShade = counts(0)
            firstMarks, firstShade = counts(0.3)
            firstPositions = {}
            for index, mark in ipairs(easy) do firstPositions[index] = mark.position.y end
            lastMarks, lastShade = counts(0.9)
            stable = true
            for index, y in ipairs(firstPositions) do stable = stable and easy[index].position.y == y end
            outward = true
            for _, mark in ipairs(easy) do
                outward = outward and math.abs(mark.position.y) <= 4.5 and mark.position.z >= -0.5
            end
        """)
        g = self.lua.globals()
        self.assertEqual(g.freshMarks, 0)
        self.assertGreater(g.firstMarks, 0)
        self.assertGreater(g.lastMarks, g.firstMarks)
        self.assertGreater(g.freshShade, g.firstShade)
        self.assertGreater(g.firstShade, g.lastShade)
        self.assertTrue(g.stable)
        self.assertTrue(g.outward)

    def test_existing_box_geometry_and_progress_are_preserved(self):
        self.lua.execute("""
            local geometry = ZM_Construction.Geometry
            geometry.DrawSolid("foundation", 0, Vector(10, 20, 30), Color(255, 255, 255, 255))
            geometry.DrawWire("wall", 90, Vector(0, 0, 0), Color(255, 255, 255, 255))
            geometry.DrawSolid("wall", 0, Vector(0, 0, 0), Color(255, 255, 255, 170), 0.5)
        """)
        drawn = self.lua.globals().drawn
        self.assertEqual(len(drawn.boxes), 2)
        foundation, half_wall = drawn.boxes[1], drawn.boxes[2]
        self.assertEqual((foundation.origin.x, foundation.origin.y, foundation.origin.z), (10, 20, 30))
        self.assertEqual((foundation.mins.x, foundation.mins.y, foundation.mins.z), (-32, -32, 0))
        self.assertEqual((foundation.maxs.x, foundation.maxs.y, foundation.maxs.z), (32, 32, 16))
        self.assertEqual((half_wall.mins.x, half_wall.maxs.x, half_wall.maxs.z), (-32, 32, 64))
        self.assertEqual(len(drawn.wires), 1)
        self.assertEqual((drawn.wires[1].mins.x, drawn.wires[1].maxs.y), (-4, 32))
        self.assertTrue(drawn.wires[1].depth)

    def test_composite_frames_and_steps_draw_their_parts_not_an_enclosing_box(self):
        self.lua.execute("""
            local geometry = ZM_Construction.Geometry
            geometry.DrawSolid("wall_doorway", 0, Vector(0, 0, 0), Color(255, 255, 255, 255))
            geometry.DrawWire("wall_window", 0, Vector(0, 0, 0), Color(255, 255, 255, 255))
            geometry.DrawSolid("stairs", 0, Vector(0, 0, 0), Color(255, 255, 255, 170), 0.5)
        """)
        drawn = self.lua.globals().drawn
        self.assertEqual(len(drawn.boxes), 11)
        self.assertEqual(len(drawn.wires), 4)
        self.assertEqual((drawn.boxes[1].mins.x, drawn.boxes[1].maxs.x), (-32, -24))
        self.assertEqual((drawn.boxes[2].mins.x, drawn.boxes[2].maxs.x), (24, 32))
        self.assertEqual((drawn.boxes[3].mins.z, drawn.boxes[3].maxs.z), (112, 128))
        self.assertTrue(all(box.maxs.z <= 64 for box in list(drawn.boxes.values())[3:]))
        self.assertEqual(drawn.boxes[11].maxs.z, 64)

    def test_triangles_and_roofs_draw_real_faces_and_edges(self):
        self.lua.execute("""
            local geometry = ZM_Construction.Geometry
            geometry.DrawSolid("foundation_triangle", 0, Vector(0, 0, 0), Color(255, 255, 255, 255))
            geometry.DrawWire("foundation_triangle", 0, Vector(0, 0, 0), Color(255, 255, 255, 255))
        """)
        drawn = self.lua.globals().drawn
        self.assertEqual(len(drawn.quads), 5)
        self.assertEqual(len(drawn.lines), 9)
        self.assertEqual(len(drawn.boxes), 0)
        self.assertEqual(len(drawn.wires), 0)
        top = next(quad for quad in drawn.quads.values() if all(quad[i].z == 16 for i in (1, 2, 3)))
        a, b, c = top[1], top[2], top[3]
        winding = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        self.assertLess(winding, 0)  # Clockwise, matching render.DrawQuad's upward-facing example.
        self.assertTrue(all(line.depth for line in drawn.lines.values()))

    def test_geometry_status_identifies_the_drawn_frame_without_resetting_it(self):
        self.lua.execute("""
            frame = 10
            ZM_Construction.Geometry.DrawWire("foundation_triangle", 0, Vector(10, 20, 30), Color(255, 255, 255))
            frame = 11
            previous = ZM_Construction.Geometry.Status()
            ZM_Construction.Geometry.DrawSolid("wall", 0, Vector(0, 0, 0), Color(255, 255, 255))
            current = ZM_Construction.Geometry.Status()
        """)
        g = self.lua.globals()
        self.assertEqual((g.previous.frame, g.previous.currentFrame, g.previous.lines), (10, 11, 9))
        self.assertEqual((g.current.frame, g.current.currentFrame, g.current.lines, g.current.boxes), (11, 11, 0, 1))
        line = g.drawn.lines[1]
        self.assertEqual((line.a.x, line.a.y, line.a.z), (-22, 52, 30))

    def test_progress_clips_slopes_and_adds_a_flat_cap(self):
        for kind, height in (("foundation_triangle", 8), ("roof_slope", 20), ("ramp", 64)):
            with self.subTest(kind=kind):
                part = self.lua.globals().ZM_Construction.GetParts(kind, 0)[1]
                faces = self.geometry.ClipPart(part, height)
                self.assertGreater(len(faces), 0)
                vertices = [vertex for face in faces.values() for vertex in face.values()]
                self.assertTrue(all(vertex[3] <= height for vertex in vertices))
                caps = [
                    face for face in faces.values()
                    if len(face) >= 3 and all(vertex[3] == height for vertex in face.values())
                ]
                self.assertGreaterEqual(len(caps), 1)
                cap = caps[-1]
                self.assertGreaterEqual(len(cap), 3)
                a, b, c = cap[1], cap[2], cap[3]
                winding = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
                self.assertGreater(winding, 0)
                self.assertEqual(len(self.geometry.ClipPart(part, part.minZ)), 0)

    def test_every_gallery_preview_has_bounded_sorted_visible_polygons(self):
        construction = self.lua.globals().ZM_Construction
        for kind in construction.PieceOrder.values():
            with self.subTest(kind=kind):
                polygons = list(self.geometry.PreviewPolygons(kind, 120, 70).values())
                self.assertGreater(len(polygons), 0)
                self.assertEqual([p.depth for p in polygons], sorted(p.depth for p in polygons))
                for polygon in polygons:
                    self.assertGreaterEqual(len(polygon.points), 3)
                    self.assertTrue(0 < polygon.shade <= 1)
                    for point in polygon.points.values():
                        self.assertGreaterEqual(point.x, -1e-8)
                        self.assertLessEqual(point.x, 120 + 1e-8)
                        self.assertGreaterEqual(point.y, -1e-8)
                        self.assertLessEqual(point.y, 70 + 1e-8)

    def test_client_bounds_update_after_piece_data_arrives_and_wall_materials_match(self):
        self.lua.execute("""
            piece = makePiece("", 0)
            piece:Initialize()
            missingInitially = piece.mins == nil
            piece.kind, piece.yaw = "wall_window", 90
            piece:Think()
            piece.progress = 0.5
            piece:DrawTranslucent()
            material = currentMaterial
            piece.complete, piece.completedAt, now = true, 0, 10
            piece:Draw()
            wallMaterial = currentMaterial
        """)
        g = self.lua.globals()
        self.assertTrue(g.missingInitially)
        self.assertEqual((g.piece.mins.x, g.piece.mins.y, g.piece.mins.z), (-4, -32, 0))
        self.assertEqual((g.piece.maxs.x, g.piece.maxs.y, g.piece.maxs.z), (4, 32, 128))
        self.assertEqual(g.material["keys"]["$basetexture"], "wood/woodwall009a")
        self.assertEqual(g.wallMaterial["keys"]["$basetexture"], "wood/woodwall009a")
        self.assertEqual(len(g.drawn.wires), 4)
        status = g.ZM_ConstructionPieceMaterialStatus()["wall_window"]
        self.assertEqual((status.shader, status.textureWidth), ("UnlitGeneric", 256))
        self.assertEqual((status.translucentShader, status.translucentTextureWidth), ("UnlitGeneric", 256))
        self.assertFalse(status.error)
        self.assertFalse(status.translucentError)


if __name__ == "__main__":
    unittest.main()
