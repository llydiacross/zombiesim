"""Exercise construction aiming through the real third-person camera hooks."""

import math
from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class ConstructionCameraTests(unittest.TestCase):
    def setUp(self):
        runner = FixtureRunner(ROOT, ["sh_construction.lua", "cl_thirdpersoncamera.lua"])
        self.lua = runner.lua
        self.lua.execute("""
            now = 100
            function CurTime() return now end
            function RealTime() return now end
            function FrameTime() return 0.1 end
            function ScrW() return 1366 end
            function ScrH() return 768 end
            function IsValid(value) return value ~= nil and value.valid == true end
            math.Clamp = function(value, low, high) return math.min(math.max(value, low), high) end
            math.NormalizeAngle = function(value) return (value + 180) % 360 - 180 end
            math.AngleDifference = function(target, source) return math.NormalizeAngle(target - source) end
            math.Approach = function(value, target, step)
                if value < target then return math.min(value + step, target) end
                return math.max(value - step, target)
            end
            function Lerp(fraction, first, second) return first + (second - first) * fraction end

            local vectorMeta = {}
            vectorMeta.__index = vectorMeta
            vectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
            vectorMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
            vectorMeta.__mul = function(a, scale) return Vector(a.x * scale, a.y * scale, a.z * scale) end
            function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vectorMeta) end
            function vectorMeta:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
            function vectorMeta:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
            function vectorMeta:DistToSqr(other) return (self - other):LengthSqr() end
            function vectorMeta:Angle()
                return Angle(math.deg(math.atan2(-self.z, math.sqrt(self.x * self.x + self.y * self.y))),
                    math.deg(math.atan2(self.y, self.x)), 0)
            end
            function LerpVector(fraction, first, second) return first + (second - first) * fraction end

            local angleMeta = {}
            angleMeta.__index = angleMeta
            function Angle(pitch, yaw, roll) return setmetatable({ p = pitch, y = yaw, r = roll }, angleMeta) end
            function angleMeta:Forward()
                local pitch, yaw = math.rad(self.p), math.rad(self.y)
                return Vector(math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch))
            end
            function angleMeta:Up()
                local pitch, yaw = math.rad(self.p), math.rad(self.y)
                return Vector(math.sin(pitch) * math.cos(yaw), math.sin(pitch) * math.sin(yaw), math.cos(pitch))
            end
            function angleMeta:Right()
                local yaw = math.rad(self.y)
                return Vector(math.sin(yaw), -math.cos(yaw), 0)
            end
            function LerpAngle(fraction, first, second)
                return Angle(Lerp(fraction, first.p, second.p), Lerp(fraction, first.y, second.y),
                    Lerp(fraction, first.r, second.r))
            end

            MASK_SOLID, MASK_SHOT = 1, 2
            IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT, IN_JUMP = 1, 2, 4, 8, 16
            MOUSE_MIDDLE, KEY_Z = 3, 26
            bit = { bor = function(...) return 0 end }
            cookie = { GetString = function(_, default) return default end }
            hooks = {}
            hook = { Add = function(event, name, callback) hooks[event .. "/" .. name] = callback end }
            net = {
                Receive = function() end, Start = function() end, WriteVector = function() end,
                WriteNormal = function() end, SendToServer = function() end
            }
            vgui = { CursorVisible = function() return false end, GetKeyboardFocus = function() return nil end }
            input = {
                IsMouseDown = function() return middleDown == true end,
                IsKeyDown = function() return zDown == true end
            }
            gui = {
                IsGameUIVisible = function() return false end,
                ScreenToVector = function(x, y)
                    lastScreenX, lastScreenY = x, y
                    return Vector(0.2 + (x - ScrW() / 2) / 600, 0.1 + (y - ScrH() / 2) / 600, -1)
                end
            }
            traces = {}
            surfaceMode = "ground"
            util = {
                TraceHull = function(options)
                    options.output.Hit = false
                    options.output.HitPos = options.endpos
                end,
                TraceLine = function(options)
                    traces[#traces + 1] = options
                    if options.mask == MASK_SHOT then return { Hit = true, Fraction = 0.01 } end
                    if surfaceMode == "miss" then return { Hit = false } end
                    if surfaceMode == "sky" then return { Hit = true, HitSky = true } end
                    if surfaceMode == "near" then return { Hit = true, HitPos = Vector(0, 0, 36) } end
                    if surfaceMode == "nan" then return { Hit = true, HitPos = Vector(0 / 0, 0, 0) } end
                    local delta = options.endpos - options.start
                    if delta.z == 0 then return { Hit = false, HitPos = options.endpos } end
                    local fraction = -options.start.z / delta.z
                    if fraction < 0 or fraction > 1 then return { Hit = false, HitPos = options.endpos } end
                    local hit = options.start + delta * fraction
                    lastSurface = hit
                    return { Hit = true, HitWorld = true, HitNormal = Vector(0, 0, 1), HitPos = hit, Fraction = fraction }
                end
            }
            ents = { FindByClass = function() return {} end }
            player = { valid = true, angles = Angle(0, 0, 0) }
            function player:Alive() return true end
            function player:EyePos() return Vector(0, 0, 64) end
            function player:WorldSpaceCenter() return Vector(0, 0, 36) end
            function player:GetLevelAim() return self:WorldSpaceCenter(), self.angles:Forward() end
            function player:GetGroundEntity() return self.ground end
            function player:GetPos() return self.pos or Vector(0, 0, 0) end
            function player:GetActiveWeapon() return { GetBuildPiece = function() return "floor" end } end
            function player:EyeAngles() return self.angles end
            function player:SetRenderAngles(angles) self.renderAngles = angles end
            function LocalPlayer() return player end
            ZM_Construction = {
                LocalBuildMode = function() return buildMode == true end,
                LocalDeleteMode = function() return deleteMode == true end
            }

            function makeCommand(wheel)
                local command = { wheel = wheel or 0 }
                function command:GetMouseWheel() return self.wheel end
                function command:GetMouseX() return 0 end
                function command:GetMouseY() return 0 end
                function command:GetForwardMove() return 0 end
                function command:GetSideMove() return 0 end
                function command:SetViewAngles(angles) self.angles = angles; player.angles = angles end
                return command
            end
            function renderView()
                return hooks["CalcView/ZM.CustomThirdPersonView"](player, player:EyePos(), Angle(0, 0, 0), 90)
            end
            function moveCamera(wheel)
                local command = makeCommand(wheel)
                hooks["CreateMove/ZM.RotateThirdPersonModel"](command)
                return command
            end
            function unlockCamera()
                middleDown = true
                hooks["Think/ZM.CameraLockToggle"]()
                middleDown = false
                for _ = 1, 4 do hooks["Think/ZM.CameraLockToggle"]() end
            end
        """)
        runner.load("sh_construction.lua")
        runner.load("cl_thirdpersoncamera.lua")
        self.lua.execute("renderView()")

    def assert_points_at_surface(self, angles):
        surface = self.lua.globals().lastSurface
        expected = math.degrees(math.atan2(36, math.hypot(surface["x"], surface["y"])))
        yaw = math.degrees(math.atan2(surface["y"], surface["x"]))
        self.assertAlmostEqual(angles["p"], expected, places=5)
        self.assertAlmostEqual(angles["y"], yaw, places=5)

    def test_locked_cursor_aims_at_ground_only_in_build_mode(self):
        self.lua.execute("""
            ordinary = moveCamera()
            ordinaryTraces = #traces
            buildMode = true
            building = moveCamera()
            cursorX, cursorY = ZM_GetAimCursor()
            trace = traces[#traces]
            assert(trace.filter[1] == player and trace.mask == MASK_SOLID)
            cursorSurface = lastSurface
            placement = ZM_Construction:AimTrace(player)
        """)
        g = self.lua.globals()
        self.assertEqual(g.ordinary["angles"]["p"], 0)
        self.assertEqual(g.ordinaryTraces, 0)
        self.assert_points_at_surface(g.building["angles"])
        self.assertEqual((g.lastScreenX, g.lastScreenY), (g.cursorX, g.cursorY))
        self.assertTrue(g.placement["Hit"])
        self.assertAlmostEqual(g.placement["HitPos"]["x"], g.cursorSurface["x"], places=5)
        self.assertAlmostEqual(g.placement["HitPos"]["y"], g.cursorSurface["y"], places=5)
        self.lua.execute("buildMode = false; after = moveCamera()")
        self.assertEqual(g.after["angles"]["p"], 0)
        self.assertEqual(len(g.traces), 2)

    def test_orbit_view_aims_at_its_centre_while_building(self):
        self.lua.execute("""
            unlockCamera()
            renderView()
            buildMode = true
            building = moveCamera()
            cursorSurface = lastSurface
            placement = ZM_Construction:AimTrace(player)
        """)
        g = self.lua.globals()
        self.assertEqual((g.lastScreenX, g.lastScreenY), (683, 384))
        self.assert_points_at_surface(g.building["angles"])
        self.assertTrue(g.placement["Hit"])
        self.assertAlmostEqual(g.placement["HitPos"]["x"], g.cursorSurface["x"], places=5)
        self.assertAlmostEqual(g.placement["HitPos"]["y"], g.cursorSurface["y"], places=5)

    def test_shoulder_mode_retains_its_existing_aim_path(self):
        self.lua.execute("""
            unlockCamera()
            moveCamera(8)
            renderView()
            traces = {}
            buildMode = true
            building = moveCamera()
        """)
        g = self.lua.globals()
        self.assertEqual(len(g.traces), 1)
        self.assertEqual(g.traces[1]["mask"], 2)
        self.assertTrue(math.isfinite(g.building["angles"]["p"]))
        self.assertTrue(math.isfinite(g.building["angles"]["y"]))

    def test_elevated_cursor_projection_preserves_its_side_and_storey(self):
        self.lua.execute("""
            buildMode = true
            player.pos = Vector(20, -15, 152)
            function player:WorldSpaceCenter() return self.pos + Vector(0, 0, 36) end
            support = { valid = true }
            function support:GetClass() return "zn_construction_piece" end
            function support:GetPieceKind() return "floor" end
            function support:GetPieceYaw() return 0 end
            function support:GetPos() return Vector(32, 32, 144) end
            function support:GetComplete() return true end
            player.ground = support
            building = moveCamera()
            local camera = traces[#traces]
            local ray = gui.ScreenToVector(lastScreenX, lastScreenY)
            expected = camera.start + ray * ((152 - camera.start.z) / ray.z)
            projected = ZM_Construction:PlacementTrace(player, "floor")
            assert(projected.ZM_AimPlane)
            assert(math.abs(projected.HitPos.x - expected.x) < 0.00001)
            assert(math.abs(projected.HitPos.y - expected.y) < 0.00001)
            assert(projected.HitPos.z == 152)
            x, y, z = ZM_Construction.ResolvePlacement("floor", projected, 0)
            assert(z == 144 and (math.abs(x - 32) == 64 or math.abs(y - 32) == 64))
            deleteMode = true
            deleting = moveCamera()
            assert(deleting.angles.p ~= building.angles.p)
            local aimed = player:GetLevelAim()
            assert(aimed.z == 188)
        """)

    def test_invalid_cursor_hits_do_not_poison_aim(self):
        self.lua.execute("""
            buildMode = true
            surfaceMode = "sky"; sky = moveCamera()
            surfaceMode = "near"; near = moveCamera()
            surfaceMode = "nan"; invalid = moveCamera()
            surfaceMode = "miss"; missed = moveCamera()
        """)
        g = self.lua.globals()
        for name in ("sky", "near", "invalid", "missed"):
            self.assertEqual(g[name]["angles"]["p"], 0)
            self.assertTrue(math.isfinite(g[name]["angles"]["y"]))


if __name__ == "__main__":
    unittest.main()
