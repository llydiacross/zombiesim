"""Focused Walker spawning regressions using the shared LuaJIT fixture support."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2]


def section(path, start, end):
    source = lua_source(ROOT / path)
    return source[source.index(start):source.index(end)]


class WalkerSpawningTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, [])
        self.lua = self.runner.lua

    def test_mounted_model_catalogue_excludes_nonexistent_refugees(self):
        self.lua.execute("ENT = {}")
        self.lua.execute(section(
            "entities/entities/zn_walker_zombie/shared.lua", "ENT.Model =", "ENT.WalkActivities ="
        ))
        models = list(self.lua.globals().ENT.Models.values())
        self.assertEqual(len(models), 34)
        self.assertEqual(
            [model for model in models if "/group02/" in model],
            [f"models/player/group02/male_{index:02d}.mdl" for index in (2, 4, 6, 8)],
        )
        for group in ("group01", "group03"):
            self.assertEqual(len([model for model in models if f"/{group}/" in model]), 15)

    def test_survivors_waiting_for_preload_are_not_materialization_or_attack_targets(self):
        self.lua.execute("""
            IsValid = function(entity) return type(entity) == "table" end
            FL_NOTARGET = 1
            ENT, ZM_WalkerSim = {}, {}
            survivor = {
                IsPlayer=function() return true end, IsBot=function() return false end,
                Alive=function() return true end, IsFlagSet=function() return false end,
                GetWorldCell=function() return {id=1} end,
                ZM_WalkerPreloadWaiting={}
            }
            player = {GetAll=function() return {survivor} end}
        """)
        self.lua.execute(section(
            "entities/entities/zn_walker_zombie/init.lua",
            "function ENT:IsValidTarget",
            "function ENT:CanSeeTarget",
        ))
        eligible = self.lua.execute(section(
            "gamemode/sv_walker_materialization.lua",
            "local function getEligiblePlayer",
            "local function writeStatus",
        ) + "\nreturn getEligiblePlayer")
        self.assertIsNone(eligible())
        self.lua.execute("""
            assert(not ENT.IsValidTarget({WalkerSourceCellId=1},survivor))
            survivor.ZM_WalkerPreloadWaiting = nil
            assert(ENT.IsValidTarget({WalkerSourceCellId=1},survivor))
        """)
        self.assertIsNotNone(eligible())

    def test_lazy_model_validation_and_invalid_candidates(self):
        self.lua.execute("""
            calls, errors = 0, 0
            util = { IsValidModel = function(model)
                calls = calls + 1
                return model ~= "missing"
            end }
            ErrorNoHalt = function() errors = errors + 1 end
            math.random = function(maximum)
                assert(maximum > 0)
                return 1
            end
        """)
        source = section(
            "entities/entities/zn_walker_zombie/init.lua",
            "local modelCandidates",
            "function ENT:Initialize()",
        )
        pick = self.lua.execute(source + "\nreturn pickModel")
        entity = self.lua.eval('{ Models = {"missing", "valid", "other"}, Model = "default" }')
        self.assertEqual(pick(entity), "valid")
        self.assertEqual(self.lua.globals().calls, 2)
        self.lua.execute("math.random = function(maximum) return maximum end")
        self.assertEqual(pick(entity), "other")
        self.assertEqual(self.lua.globals().calls, 3)
        self.lua.execute("math.random = function() return 1 end")
        self.assertEqual(pick(entity), "valid")
        self.assertEqual(self.lua.globals().calls, 3)
        fallback = self.lua.execute(source + "\nreturn pickModel")
        self.assertEqual(fallback(self.lua.eval('{ Models = {"missing"}, Model = "default" }')), "default")
        self.assertEqual(self.lua.globals().errors, 1)

    def test_nav_centres_read_once_and_spawn_guards_preserved(self):
        self.lua.execute("""
            WalkerSim = { MaterializationConfig = {
                placementAttemptsPerTicket = 128, playerExclusionRadius = 1,
                minimumZombieSeparation = 1
            } }
            function Vector(x, y, z)
                return { x = x, y = y, z = z, DistToSqr = function(self, other)
                    return (self.x-other.x)^2 + (self.y-other.y)^2 + (self.z-other.z)^2
                end }
            end
            function area(x, blocked, valid)
                return {
                    reads = 0, IsValid = function() return valid end,
                    GetCenter = function(self) self.reads = self.reads + 1; return Vector(x,0,0) end,
                    IsBlocked = function() return blocked end,
                    IsUnderwater = function() return false end
                }
            end
            areas = {area(0,true,true),area(1,false,true),area(-1,false,true),
                area(99,false,true),area(2,false,false)}
            navmesh = { IsLoaded = function() return true end, GetAllNavAreas = function() return areas end }
            ZM_World = {
                GetCellBounds = function() return {coreHalfExtent=10,revision=2} end,
                IsCoreSpawnPosition = function(_,p) return math.abs(p.x) <= 10 end
            }
        """)
        prefix = """
            local function isPlayerTooClose() return playerTooClose == true end
            local function isWalkerZombieTooClose() return zombieTooClose == true end
            local function hasSpawnClearance() return blockedClearance ~= true end
            local function isHiddenFromPlayers() return visibleToPlayer ~= true end
        """
        self.lua.execute(prefix + section(
            "gamemode/sv_walker_sim.lua",
            "function WalkerSim:FindZombieSpawnPosition",
            "function WalkerSim:SpawnTicketZombie",
        ))
        self.lua.execute("""
            local p = WalkerSim:FindZombieSpawnPosition({LocalU=32767.5,LocalV=32767.5})
            assert(p.x == 1, "equal-distance candidates retain nav enumeration order")
            for i=1,4 do assert(areas[i].reads == 1) end
            assert(areas[5].reads == 0)
            for _, guard in ipairs({"playerTooClose","zombieTooClose","blockedClearance","visibleToPlayer"}) do
                _G[guard] = true
                assert(WalkerSim:FindZombieSpawnPosition({LocalU=32767.5,LocalV=32767.5}) == nil)
                _G[guard] = false
            end
            areas[2].IsBlocked = function() return true end
            areas[3].IsUnderwater = function() return true end
            local p, err = WalkerSim:FindZombieSpawnPosition({LocalU=32767.5,LocalV=32767.5})
            assert(p == nil and string.find(err, "no nav area passed", 1, true))
        """)

    def test_batch_budget_defers_without_consuming_tickets(self):
        self.lua.execute("""
            now, spawned, rejected = 0, 0, 0
            SysTime = function() return now end
            CurTime = function() return 10 end
            IsValid = function(entity) return type(entity) == "table" end
            Materializer = {Registry={},HandledReservations={},NextReconcileAt=99,NextRequestAt=0,
                RecordError=function() error("unexpected placement error") end}
            ZM_WalkerSim = {
                SpawnTicketZombie = function()
                    spawned = spawned + 1
                    now = now + 0.003
                    return {}
                end,
                RejectTicket = function() rejected = rejected + 1; return true end
            }
            tickets = {}
            for i=1,3 do tickets[i]={CellId=1,State="reserved",TicketIdLow=i,TicketIdHigh=0} end
            survivor = {GetPos=function() return {} end}
        """)
        prefix = """
            local function ticketKey(ticket) return ticket.TicketIdHigh .. ":" .. ticket.TicketIdLow end
            local function getConfig() return {materializationRadius=1200} end
            local function getRetrySeconds() return 1 end
        """
        self.lua.execute(prefix + section(
            "gamemode/sv_walker_materialization.lua",
            "function Materializer:MaterializeReservations",
            "function Materializer:RequestTickets",
        ))
        self.lua.execute("""
            local count, deferred = Materializer:MaterializeReservations(tickets,{id=1},survivor,0,3)
            assert(count == 1 and deferred == true)
            assert(Materializer.NextReconcileAt == 10)
            assert(Materializer.HandledReservations["0:2"] == nil)
            assert(rejected == 0)
            count, deferred = Materializer:MaterializeReservations(tickets,{id=1},survivor,count,3)
            assert(count == 2 and deferred == true)
            count, deferred = Materializer:MaterializeReservations(tickets,{id=1},survivor,count,3)
            assert(count == 3 and deferred == nil and spawned == 3)
            count = Materializer:MaterializeReservations(tickets,{id=1},survivor,count,3)
            assert(count == 3 and spawned == 3, "population target remains a hard cap")
            Materializer.Registry, Materializer.HandledReservations = {}, {}
            local errors = 0
            Materializer.RecordError = function() errors = errors + 1 end
            ZM_WalkerSim.SpawnTicketZombie = function()
                now = now + 0.003
                return nil, "no valid placement"
            end
            count, deferred = Materializer:MaterializeReservations(tickets,{id=1},survivor,0,3)
            assert(count == 0 and deferred == true and rejected == 1 and errors == 1)
            assert(Materializer.HandledReservations["0:1"] == true)
            assert(Materializer.HandledReservations["0:2"] == nil)
        """)


if __name__ == "__main__":
    unittest.main()
