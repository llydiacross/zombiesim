"""Explicit loading/realm fixtures for Walker model preparation."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class WalkerPreloadTests(unittest.TestCase):
    def fixture(self, server):
        runner = FixtureRunner(ROOT, ["sh_walker_preload.lua"])
        lua = runner.lua
        lua.globals().SERVER = server
        lua.globals().CLIENT = not server
        lua.execute("""
            now, validates, errors, finished, sent, arrivals = 0, 0, 0, 0, 0, 0
            SysTime = function() return now end
            ErrorNoHalt = function() errors = errors + 1 end
            hooks, receivers, globals = {}, {}, {}
            hook = {Add = function(event,name,callback) hooks[name] = callback end}
            concommand = {Add = function(name,callback) end}
            net = {
                Receive = function(name,callback) receivers[name] = callback end,
                Start = function(name) assert(name == "ZM.WalkerModelsReady") end,
                SendToServer = function() sent = sent + 1 end
            }
            SetGlobalBool = function(key,value) globals[key] = value end
            GetGlobalBool = function(key,default)
                if globals[key] == nil then return default end
                return globals[key]
            end
            util = {
                AddNetworkString = function(name) assert(name == "ZM.WalkerModelsReady") end,
                IsValidModel = function(model)
                    validates = validates + 1
                    return model ~= "missing"
                end
            }
            scripted_ents = {GetStored = function(name)
                assert(name == "zn_walker_zombie")
                return {t={Models={"first","missing","last"}}}
            end}
            ZM_Loading = {
                Begin = function(...) return "step" end,
                Finish = function(...) finished = finished + 1 end,
                Step = function(...) finished = finished + 1 end
            }
            ZM_LoadingScreen = {SetExtraHold=function(_,key,value)
                assert(key == "walkerModels")
                holding = value
            end}
            IsValid = function(entity) return type(entity) == "table" end
            survivor = {Alive = function() return true end, IsPlayer = function() return true end}
            player = {GetHumans=function() return {survivor} end}
            Vector = function(x,y,z) return {x=x,y=y,z=z} end
        """)
        runner.load("sh_walker_preload.lua")
        return lua

    def test_server_warms_one_per_frame_and_arrival_waits_for_client(self):
        lua = self.fixture(True)
        lua.execute("""
            ZM_WalkerPreload:HoldPlayer(survivor,function() arrivals=arrivals+1 end)
            assert(survivor.ZM_WalkerPreloadWaiting ~= nil)
            local tick = hooks["ZM.WalkerPreload.Prepare"]
            tick()
            assert(validates == 1 and not ZM_WalkerPreload.done and arrivals == 0)
            tick()
            tick()
            assert(validates == 3 and ZM_WalkerPreload.done and arrivals == 0)
            assert(ZM_WalkerPreload.status == "warn" and ZM_WalkerPreload.valid == 2)
            receivers["ZM.WalkerModelsReady"](0,survivor)
            tick()
            assert(arrivals == 1 and survivor.ZM_WalkerPreloadWaiting == nil)
            tick()
            assert(arrivals == 1 and validates == 3)
        """)

    def test_client_cover_waits_for_both_realms(self):
        lua = self.fixture(False)
        lua.execute("""
            hooks["ZM.WalkerPreload.Start"]()
            assert(holding == true)
            local tick = hooks["ZM.WalkerPreload.Prepare"]
            tick(); tick(); tick()
            assert(sent == 1 and holding == true)
            globals["ZM.WalkerModelsReady"] = true
            tick()
            assert(holding == false and ZM_WalkerPreload.released == true)
            tick()
            assert(sent == 1)
        """)

    def test_timeouts_are_reported_and_release_arrival(self):
        lua = self.fixture(True)
        lua.execute("""
            ZM_WalkerPreload:HoldPlayer(survivor,function() arrivals=arrivals+1 end)
            now = 31
            hooks["ZM.WalkerPreload.Prepare"]()
            assert(arrivals == 1 and validates == 0)
            assert(ZM_WalkerPreload.status == "warn" and errors >= 2)
        """)
        lua = self.fixture(False)
        lua.execute("""
            ZM_WalkerPreload:Start()
            now = 31
            hooks["ZM.WalkerPreload.Prepare"]()
            assert(holding == false and errors >= 2 and sent == 1)
        """)

    def test_missing_catalogue_fails_explicitly(self):
        lua = self.fixture(False)
        lua.execute("""
            scripted_ents.GetStored = function() return nil end
            ZM_WalkerPreload:Start()
            assert(ZM_WalkerPreload.done and ZM_WalkerPreload.status == "fail")
            assert(errors == 1 and sent == 1)
        """)

    def test_gate_and_den_placement_precede_loading_but_walk_and_fade_wait(self):
        source = lua_source(ROOT / "sv_transitions.lua")
        source = source[source.index("function Transitions:ApplyPendingEntry"):source.index("local movementButtons")]
        for den in (False, True):
            lua = self.fixture(True)
            lua.globals().inDen = den
            lua.execute("""
                now = 10
                CurTime = function() return now end
                fades, messages = 0, 0
                local mt = {
                    __add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end,
                    __mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
                }
                Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
                Angle=function() return {Forward=function() return Vector(1,0,0) end} end
                MASK_PLAYERSOLID = 1
                local anchor = {
                    GetPos=function() return Vector(10,20,30) end,
                    GetAngles=function() return {y=90} end
                }
                Transitions = {
                    DenArrivalDistance=120, DenArrivalFade=2.2,
                    FindPendingEntryAnchor=function() return anchor end,
                    IsPlayerHullClear=function() return true end,
                    GetEngineInputLockRemaining=function() return 0 end,
                    FadeInFromBlack=function(_,_,fade) fades=fades+1; lastFade=fade end
                }
                ZM_World = {ActiveProfile="preview"}
                survivor.CurrentSafeZoneId = inDen and "den" or nil
                survivor.GetPData = function() return "entry" end
                survivor.RemovePData = function() removed=true end
                survivor.SetPos = function(self,p) self.position=p end
                survivor.GetPos = function(self) return self.position end
                survivor.GetHull = function() return Vector(0,0,0),Vector(1,1,1) end
                survivor.SetEyeAngles = function(self,a) self.eye=a end
                util.JSONToTable = function() return {
                    anchorClass=inDen and "zn_safezone_arrival" or nil,
                    landmark="NORTH_ENTRANCE",yaw=90
                } end
                util.TraceHull = function(trace) return {StartSolid=false,HitPos=trace.endpos} end
                net.Start=function() end
                net.WriteFloat=function() end
                net.Send=function() messages=messages+1 end
            """)
            lua.execute('local function getEntryKey() return "entry" end\n' + source)
            lua.execute("""
                assert(Transitions:ApplyPendingEntry(survivor))
                assert(removed and survivor.position and survivor.eye)
                assert(fades == 0 and messages == 0 and survivor.ZM_TransitionEntry == nil)
                local tick = hooks["ZM.WalkerPreload.Prepare"]
                tick(); tick(); tick()
                assert(fades == 0)
                receivers["ZM.WalkerModelsReady"](0,survivor)
                now = 11
                tick()
                assert(fades == 1 and messages == 1)
                if inDen then
                    assert(lastFade == 2.2 and survivor.ZM_TransitionEntry == nil)
                    assert(survivor.position.x == 130)
                else
                    assert(lastFade == 1.1)
                    assert(survivor.ZM_TransitionEntry.startTime == 11)
                    assert(survivor.ZM_TransitionEntry.speed == 160)
                end
            """)


if __name__ == "__main__":
    unittest.main()
