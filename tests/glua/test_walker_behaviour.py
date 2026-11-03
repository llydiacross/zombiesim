"""Focused Phase B Walker perception, stimulus and culling regressions (offline LuaJIT fixtures)."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2]
ENTITY = "entities/entities/zn_walker_zombie/init.lua"
AWARENESS = "gamemode/sv_walker_awareness.lua"

VECTOR = """
local meta = {}
meta.__index = meta
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, meta) end
meta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
meta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
meta.__mul = function(a, s) return Vector(a.x * s, a.y * s, a.z * s) end
meta.__div = function(a, s) return Vector(a.x / s, a.y / s, a.z / s) end
function meta:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
function meta:Length() return math.sqrt(self:LengthSqr()) end
function meta:Length2DSqr() return self.x * self.x + self.y * self.y end
function meta:DistToSqr(o) return (self - o):LengthSqr() end
function meta:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function meta:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
function meta:Normalize() local l = self:Length() self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end
function isvector(value) return getmetatable(value) == meta end
IsValid = function(value) return type(value) == "table" end
now = 100
CurTime = function() return now end
"""


def section(path, start, end):
    source = lua_source(ROOT / path)
    return source[source.index(start):source.index(end)]


class WalkerBehaviourTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, [])
        self.lua = self.runner.lua
        self.lua.execute(VECTOR)

    def load_entity(self):
        self.lua.execute("ENT = {}")
        self.lua.execute(section(ENTITY, "function ENT:IsWithinVision", "function ENT:FindTarget"))
        self.lua.execute(section(ENTITY, "function ENT:SetInvestigation", "function ENT:RefreshTarget"))
        self.lua.execute("""
            function walker(position, forward)
                local entity = setmetatable({
                    position = position, forward = forward or Vector(1, 0, 0),
                    CloseSenseRange = 150, DevelopmentTargetSearchRange = 800, VisionConeDot = 0.5,
                    InvestigateSeconds = 15, NextAlertAt = 0, AlertsSent = 0, HeardNoiseCount = 0,
                    SoundAlert = "a%d", SoundAlertCount = 3, voices = 0
                }, {__index = ENT})
                function entity:GetPos() return self.position end
                function entity:GetForward() return Vector(self.forward.x, self.forward.y, self.forward.z) end
                function entity:PlayVoice() self.voices = self.voices + 1 end
                return entity
            end
            function target(position)
                return {GetPos = function() return position end}
            end
        """)

    def test_vision_cone_close_sense_and_tracked_target(self):
        self.load_entity()
        self.lua.execute("""
            local self = walker(Vector(0, 0, 0))
            assert(self:IsWithinVision(target(Vector(500, 100, 0))), "inside the forward cone")
            assert(not self:IsWithinVision(target(Vector(-500, 0, 0))), "behind is unseen")
            assert(not self:IsWithinVision(target(Vector(100, 500, 0))), "outside the 120 degree cone")
            assert(self:IsWithinVision(target(Vector(-140, 0, 0))), "close sense is all-round")
            assert(not self:IsWithinVision(target(Vector(900, 0, 0))), "beyond the vision range")
            local tracked = target(Vector(-500, 0, 0))
            self.CurrentTarget = tracked
            assert(self:IsWithinVision(tracked), "an engaged target is tracked regardless of facing")
            assert(not self:IsWithinVision(target(Vector(-900, 0, 0))), "range still applies")
        """)

    def test_structures_block_hits_and_sieges_give_up_for_a_doorway(self):
        self.lua.execute("ENT = {}")
        self.lua.execute(section(ENTITY, "local function isStructure", "function ENT:IsWithinVision"))
        self.lua.execute("""
            local meta = getmetatable(Vector(0, 0, 0))
            function meta:Distance(o) return (self - o):Length() end
            function meta:Distance2D(o) return math.sqrt((self - o):Length2DSqr()) end
            MASK_NPCSOLID = 1
            coroutine.wait = function(seconds) now = now + seconds end
            coroutine.yield = function() now = now + 0.1 end
            function piece(kind, position)
                return {kind = kind, position = position, complete = true,
                    GetClass = function() return "zn_construction_piece" end,
                    GetComplete = function(self) return self.complete end,
                    GetPieceKind = function(self) return self.kind end,
                    GetPos = function(self) return self.position end,
                    LocalToWorld = function(self, offset) return self.position + offset end}
            end
            wall = piece("wall", Vector(60, 0, 0))
            blocking = wall
            util = {
                TraceLine = function(trace)
                    assert(trace.ignoreworld and trace.filter(blocking or wall) ~= nil)
                    if blocking then return {Hit = true, Entity = blocking, HitPos = Vector(56, 0, 36), HitNormal = Vector(-1, 0, 0)} end
                    return {Hit = false}
                end,
                TraceHull = function() return {Hit = false} end
            }
            damage = {}
            ZM_Construction = {DamagePiece = function(_, entity, amount)
                damage[#damage + 1] = amount
                return false
            end}
            local survivor = {GetPos = function() return Vector(200, 0, 0) end,
                EyePos = function() return Vector(200, 0, 64) end,
                WorldSpaceCenter = function() return Vector(200, 0, 36) end}
            survivorTarget = survivor
            doorways = {}
            ents = {FindInSphere = function() return doorways end}
            local self = setmetatable({
                position = Vector(0, 0, 0), NextAttackAt = 0, DevelopmentAttackInterval = 0,
                AttackWindup = 0.9, AttackRecovery = 0.6, AttackReachTolerance = 16,
                StructureDamage = 1, StructureBlockRange = 72, SiegeGiveUpSeconds = 20,
                DoorSeekSeconds = 20, DoorMemorySeconds = 60, DoorSearchRadius = 768,
                loco = {FaceTowards = function() end}
            }, {__index = ENT})
            self.loco.Approach = function(_, goal) self.position = Vector(goal.x, goal.y, goal.z) end
            function self:GetPos() return self.position end
            function self:WorldSpaceCenter() return self.position + Vector(0, 0, 36) end
            function self:FlatForward() return Vector(1, 0, 0) end
            function self:DetourHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end
            function self:IsValidTarget(target) return target == survivor end
            function self:CanSeeTarget() return true end
            function self:GetActivity() return 1 end
            function self:RestActivity() return 1 end
            function self:MoveActivity() return 1 end
            function self:StartActivity() end
            function self:AddGesture() end
            function self:PlayVoice() end
            function self:MoveToward() error("direct approach expected") end
            walkerSelf = self

            canReachBlocked = self:CanReachTarget(survivor)
            blockerFound = self:FindStructureBlocker(survivor) == wall
            local started = now
            while now - started < 20 do
                self:BesiegeStructure(survivor, wall, Vector(56, 0, 36), Vector(-1, 0, 0))
            end
            strikesBeforeGiveUp = #damage
            sieges = self.SiegeCount

            door = piece("wall_doorway", Vector(60, 128, 0))
            used = piece("wall_doorway", Vector(60, 32, 0))
            doorways = {used, door, piece("wall", Vector(60, 64, 0))}
            self.DoorwayMemory = {[used] = now + 60}
            self:BesiegeStructure(survivor, wall, Vector(56, 0, 36), Vector(-1, 0, 0))
            throughDoor = self.position.x == 60 and self.position.y == 128 + 56
            seekCount, giveUps = self.DoorSeekCount, self.SiegeGiveUpCount
            siegeCleared = self.SiegePiece == nil and self.SiegeStartedAt == nil
            doorRemembered = self.DoorwayMemory[door] ~= nil

            -- Every doorway is remembered now: after the next give-up the walker returns to hitting.
            self.position = Vector(0, 0, 0)
            local restart = now
            while now - restart < 20 do
                self:BesiegeStructure(survivor, wall, Vector(56, 0, 36), Vector(-1, 0, 0))
            end
            local before = #damage
            self:BesiegeStructure(survivor, wall, Vector(56, 0, 36), Vector(-1, 0, 0))
            noDoorRestarted = self.SiegeStartedAt == now and #damage == before and self.DoorSeekCount == 1
            self:BesiegeStructure(survivor, wall, Vector(56, 0, 36), Vector(-1, 0, 0))
            resumedHitting = #damage == before + 1

            blocking = nil
            self.BlockerCheckedAt = nil
            canReachClear = self:CanReachTarget(survivor)
        """)
        g = self.lua.globals()
        self.assertFalse(g.canReachBlocked)
        self.assertTrue(g.blockerFound)
        # One strike per 1.5 s for 20 s before giving up.
        self.assertGreaterEqual(g.strikesBeforeGiveUp, 13)
        self.assertLessEqual(g.strikesBeforeGiveUp, 14)
        self.assertEqual(g.sieges, 1)
        self.assertTrue(g.throughDoor)
        self.assertEqual((g.seekCount, g.giveUps), (1, 1))
        self.assertTrue(g.siegeCleared)
        self.assertTrue(g.doorRemembered)
        self.assertTrue(g.noDoorRestarted)
        self.assertTrue(g.resumedHitting)
        self.assertTrue(g.canReachClear)

    def test_blocked_walker_sidesteps_and_keeps_its_target(self):
        self.lua.execute("ENT = {}")
        self.lua.execute(section(ENTITY, "function ENT:IsMakingNoProgress", "function ENT:AttackTarget"))
        self.lua.execute(section(ENTITY, "function ENT:HandleStuck", "function ENT:GetWalkerPerformanceStats"))
        self.lua.execute("""
            MASK_NPCSOLID = 1
            local blockedSide = -1
            navmesh = {GetNearestNavArea = function(position)
                return {GetClosestPointOnArea = function(_, p) return Vector(p.x, p.y, 0) end}
            end}
            util = {TraceHull = function(t) return {Hit = (t.endpos.y < 0) == (blockedSide < 0)} end}
            local approached
            local self = setmetatable({
                position = Vector(0, 0, 0), StuckRecoveryCount = 0, WalkerState = "pursue",
                CurrentTarget = "player", LastKnownTargetPosition = Vector(500, 0, 0), LastKnownTargetExpiresAt = 200,
                loco = {ClearStuck = function() end, FaceTowards = function() end,
                    Approach = function(_, goal) approached = goal end}
            }, {__index = ENT})
            function self:GetPos() return self.position end
            function self:GetForward() return Vector(1, 0, 0) end
            function self:OBBMins() return Vector(-13, -13, 0) end
            function self:OBBMaxs() return Vector(13, 13, 72) end
            function self:ClearInvestigation() self.investigationCleared = true end
            self.activity = "walk"
            function self:GetActivity() return self.activity end
            function self:StartActivity(activity) self.activity = activity end
            function self:RestActivity() return "rest" end
            function self:MoveActivity() return "walk" end
            math.Rand = function(low, high) return (low + high) / 2 end

            local goal = Vector(800, 0, 0)
            assert(not self:IsMakingNoProgress(goal), "first sample only records a baseline")
            now = now + 1.1
            assert(self:IsMakingNoProgress(goal), "no movement toward a distant goal is a stall")
            now = now + 1.1
            self.position = Vector(60, 0, 0)
            assert(not self:IsMakingNoProgress(goal), "progress is not a stall")
            now = now + 5
            assert(not self:IsMakingNoProgress(goal), "a stale sample after an idle gap is ignored")

            self.position = Vector(0, 0, 0)
            self:HandleStuck()
            assert(self.DetourGoal and self.DetourGoal.y > 0, "sidesteps to the unblocked side")
            assert(self.CurrentTarget == "player" and self.LastKnownTargetPosition, "keeps target and memory")
            assert(self:FollowDetour() and approached == self.DetourGoal, "walks the detour directly")
            self.position = Vector(self.DetourGoal.x, self.DetourGoal.y, 0)
            assert(not self:FollowDetour() and self.DetourGoal == nil, "detour ends on arrival")

            self.position = Vector(0, 0, 0)
            local walkerAhead = {GetClass = function() return "zn_walker_zombie" end}
            local sideTrace = util.TraceHull
            util.TraceHull = function(t)
                if t.endpos.y == 0 then return {Hit = true, Entity = walkerAhead} end
                return sideTrace(t)
            end
            approached = nil
            self:HandleStuck()
            assert(self.YieldCount == 1 and self.DetourStartsAt > now, "yields before passing a blocking walker")
            assert(self:FollowDetour() and approached == nil and self.activity == "rest", "stands still while yielding")
            now = self.DetourStartsAt
            assert(self:FollowDetour() and approached == self.DetourGoal and self.activity == "walk", "then sidesteps")
            util.TraceHull = sideTrace

            blockedSide = 0
            util.TraceHull = function() return {Hit = true, Entity = walkerAhead} end
            self.CurrentTarget = "player"
            self:HandleStuck()
            assert(self.HoldCount == 1 and self.HoldUntil > now and self.CurrentTarget == "player",
                "packed in by walkers: holds and keeps the target")
            assert(self:FollowDetour() and self.activity == "rest", "stands still while held")
            now = self.HoldUntil
            assert(not self:FollowDetour() and self.HoldUntil == nil, "hold ends and pathing resumes")

            util.TraceHull = function() return {Hit = true} end
            function self:IsValidTarget(target) return target == "player" end
            local structureAhead
            function self:FindStructureBlocker() return structureAhead end
            structureAhead = "wall"
            self:HandleStuck()
            assert(self.CurrentTarget == "player" and self.HoldUntil > now,
                "walled in by a player structure: keeps the target for the siege")
            now = self.HoldUntil
            assert(not self:FollowDetour(), "structure hold ends")
            structureAhead = nil
            self:HandleStuck()
            assert(self.DetourGoal == nil and self.CurrentTarget == nil and self.investigationCleared,
                "falls back to a full reset when both sides are blocked")
        """)

    def test_noise_and_alerts_only_affect_unengaged_walkers_without_chaining(self):
        self.load_entity()
        self.lua.execute("""
            alerts = 0
            ZM_WalkerAwareness = {Alert = function() alerts = alerts + 1 return 2 end}
            local idle = walker(Vector(0, 0, 0))
            assert(idle:HearNoise(Vector(300, 0, 0), "gunshot") and idle:HasInvestigation())
            assert(idle.HeardNoiseCount == 1 and idle.CurrentTarget == nil, "noise never grants a target")
            now = now + 16
            assert(not idle:HasInvestigation(), "investigation expires")

            local engaged = walker(Vector(0, 0, 0))
            engaged.CurrentTarget = target(Vector(10, 0, 0))
            assert(not engaged:HearNoise(Vector(300, 0, 0), "gunshot") and not engaged:HasInvestigation())
            assert(not engaged:ReceiveAlert(Vector(300, 0, 0)))

            local spotter = walker(Vector(0, 0, 0))
            spotter:OnTargetAcquired(target(Vector(100, 0, 0)))
            assert(alerts == 1 and spotter.AlertsSent == 2 and spotter.voices == 1, "spotter alerts once")
            spotter:OnTargetAcquired(target(Vector(100, 0, 0)))
            assert(alerts == 1, "alert cooldown")

            local woken = walker(Vector(0, 0, 0))
            assert(woken:ReceiveAlert(Vector(50, 0, 0)) and woken:HasInvestigation())
            woken:OnTargetAcquired(target(Vector(100, 0, 0)))
            assert(alerts == 1 and woken.voices == 1, "an alerted walker growls but does not chain")
            assert(not woken:HasInvestigation(), "acquiring a target clears the investigation")
        """)

    def test_excess_culling_keeps_visible_then_nearest(self):
        self.lua.execute("Materializer = {}")
        self.lua.execute(section(
            "gamemode/sv_walker_materialization.lua",
            "function Materializer.OrderExcessCandidates",
            "function Materializer:DespawnExcess",
        ))
        self.lua.execute("""
            local entries = Materializer.OrderExcessCandidates({
                {key = 1, visible = false, distance = 10},
                {key = 2, visible = true, distance = 900},
                {key = 3, visible = false, distance = 400},
                {key = 4, visible = false, distance = 10},
            })
            local order = {}
            for index, entry in ipairs(entries) do order[index] = entry.key end
            assert(table.concat(order, ",") == "2,4,1,3", table.concat(order, ","))
        """)

    def load_awareness(self):
        self.lua.execute("""
            FCVAR_ARCHIVE, FL_NOTARGET = 128, 1
            util = {AddNetworkString = function() end}
            CreateConVar = function() return {GetBool = function() return true end} end
            net = {Receive = function() end}
            hook = {Add = function() end}
            walkers = {}
            ents = {FindInSphere = function(position, radius)
                local found = {}
                for _, entity in ipairs(walkers) do
                    if entity:GetPos():DistToSqr(position) <= radius * radius then found[#found + 1] = entity end
                end
                return found
            end}
            function makeWalker(position, cell)
                local entity = {position = position, WalkerSourceCellId = cell, heard = 0}
                function entity:GetPos() return self.position end
                function entity:GetClass() return "zn_walker_zombie" end
                function entity:HearNoise() self.heard = self.heard + 1 return true end
                walkers[#walkers + 1] = entity
                return entity
            end
            function makePlayer(eye, cell)
                local entity = {eye = eye, flags = false, cell = cell}
                function entity:IsPlayer() return true end
                function entity:Alive() return true end
                function entity:EyePos() return self.eye end
                function entity:IsFlagSet() return self.flags end
                function entity:GetWorldCell() return {id = self.cell} end
                return entity
            end
        """)
        self.lua.execute(section(AWARENESS, "ZM_WalkerAwareness = ZM_WalkerAwareness", "net.Receive("))
        self.lua.execute("local Awareness = ZM_WalkerAwareness\n" + section(AWARENESS, "function Awareness:FindWalkersNear", "local function shooterOf"))

    def test_camera_view_validation(self):
        self.load_awareness()
        self.lua.execute("""
            local A = ZM_WalkerAwareness
            local survivor = makePlayer(Vector(0, 0, 64), 1)
            assert(not A:AcceptCameraView(survivor, Vector(2000, 0, 64), Vector(1, 0, 0), 10), "too far from the eye")
            assert(not A:AcceptCameraView(survivor, Vector(0 / 0, 0, 64), Vector(1, 0, 0), 10), "NaN origin")
            assert(not A:AcceptCameraView(survivor, Vector(0, 0, 400), Vector(0.1, 0, 0), 10), "short forward")
            assert(A:AcceptCameraView(survivor, Vector(-200, 0, 400), Vector(1, 0, 0), 10))
            assert(not A:AcceptCameraView(survivor, Vector(-100, 0, 400), Vector(1, 0, 0), 10.05), "rate limited")
            assert(A:GetCameraView(survivor, 11.9) ~= nil and A:GetCameraView(survivor, 12.1) == nil, "freshness")
            survivor.Alive = function() return false end
            assert(not A:AcceptCameraView(survivor, Vector(-200, 0, 400), Vector(1, 0, 0), 20), "dead players")
        """)

    def test_partially_occluded_walker_still_counts_as_visible(self):
        self.load_awareness()
        self.lua.execute("""
            MASK_SOLID_BRUSHONLY = 1
            blockedBelowZ = 0
            util = {TraceLine = function(t)
                if t.endpos.z < blockedBelowZ then return {Hit = true, Fraction = 0.5} end
                return {Hit = false, Fraction = 1}
            end}
            survivor = makePlayer(Vector(0, 0, 64), 1)
            survivor.IsBot = function() return false end
            player = {GetAll = function() return {survivor} end}
        """)
        self.lua.execute("local Awareness = ZM_WalkerAwareness\n" + section(
            AWARENESS, "local function isSameCell", "function Awareness:FindWalkersNear"))
        self.lua.execute("""
            local A = ZM_WalkerAwareness
            local zombie = {WalkerSourceCellId = 1}
            function zombie:GetPos() return Vector(500, 0, 0) end
            function zombie:WorldSpaceCenter() return Vector(500, 0, 36) end
            blockedBelowZ = 50
            assert(A:IsVisibleToAnyPlayer(zombie), "head above a low wall keeps the walker visible")
            blockedBelowZ = 1000
            assert(not A:IsVisibleToAnyPlayer(zombie), "fully occluded walkers are not visible")
            blockedBelowZ = 50
            assert(A:IsPositionVisibleToAnyPlayer(Vector(500, 0, 0)), "spawn hull head is in view")
            assert(A.CameraVisibleRange >= 5760, "camera range covers a whole cell")
        """)

    def test_noise_radius_cell_cooldown_and_notarget(self):
        self.load_awareness()
        self.lua.execute("""
            local A = ZM_WalkerAwareness
            local near, far, otherCell = makeWalker(Vector(300, 0, 0), 1), makeWalker(Vector(1000, 0, 0), 1),
                makeWalker(Vector(100, 0, 0), 2)
            local survivor = makePlayer(Vector(0, 0, 64), 1)
            assert(A:EmitNoise("sprint", Vector(0, 0, 0), survivor) == 1 and near.heard == 1)
            assert(far.heard == 0 and otherCell.heard == 0, "radius and cell limit hearing")
            assert(A:EmitNoise("sprint", Vector(0, 0, 0), survivor) == 0, "per-kind cooldown")
            now = now + 1
            assert(A:EmitNoise("gunshot", Vector(0, 0, 0), survivor) == 2 and far.heard == 1)
            assert(A:EmitNoise("whisper", Vector(0, 0, 0), survivor) == 0, "unknown kinds are rejected")
            now = now + 1
            survivor.flags = true
            assert(A:EmitNoise("gunshot", Vector(0, 0, 0), survivor) == 0, "notarget makes no noise")
        """)


if __name__ == "__main__":
    unittest.main()
