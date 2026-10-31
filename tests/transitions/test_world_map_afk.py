"""Exercise the server AFK owner and the real world-map entry paths offline."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class ServerWorldMapAfkTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, ["sv_afk.lua"])
        self.lua = self.runner.lua
        self.lua.execute("""
            clock = 100
            CurTime = function() return clock end
            IsValid = function(value) return type(value) == "table" and value.valid == true end
            util = { AddNetworkString = function() end }
            net = { Receive = function() end }
            hook = { Add = function() end }
            ents = { FindByClass = function() return {} end }
            player = { GetHumans = function() return {} end }
            IN_ATTACK = 1
            target = { valid = true, alive = true }
            function target:Alive() return self.alive end
        """)
        self.runner.load("sv_afk.lua")
        self.lua.execute("""
            sent = {}
            ZM_AFK.Send = function(_, _, menu, message)
                table.insert(sent, { menu = menu, message = message })
            end
        """)

    def test_map_countdown_protection_grace_and_interrupt(self):
        self.lua.execute("""
            local afk = ZM_AFK
            assert(afk:Begin(target, "map", 100))
            assert(afk:GetState(target).countdownMenu == "map")
            assert(not afk:IsProtected(target, 100))
            afk:Tick(target, 102.99)
            assert(not afk:IsAFK(target))
            afk:Tick(target, 103)
            assert(afk:IsAFK(target) and sent[#sent].menu == "map")
            local zombie = { valid = true }
            function zombie:IsNPC() return true end
            function zombie:IsNextBot() return false end
            local damage = {}
            function damage:GetAttacker() return zombie end
            function damage:GetDamage() return 5 end
            assert(afk:FilterDamage(target, damage))
            assert(afk:Leave(target, 104))
            assert(afk:IsInGrace(target, 106.99))
            assert(not afk:IsInGrace(target, 107))
            afk:Clear(target)
            assert(afk:Begin(target, "map", 110))
            assert(not afk:FilterDamage(target, damage))
            afk:Tick(target, 114)
            assert(not afk:IsProtected(target, 114))
            assert(not afk:EnterImmediately(target, "map", 115))
        """)

    def test_map_cancel_is_not_lost_to_request_rate_limit(self):
        self.lua.execute("""
            local afk = ZM_AFK
            clock = 100
            assert(afk:HandleRequest(target, afk.Actions.begin, "map"))
            clock = 100.05
            assert(afk:HandleRequest(target, afk.Actions.cancel, ""))
            afk:Tick(target, 104)
            assert(not afk:IsProtected(target, 104))
            assert(afk:GetState(target).countdownMenu == nil)
        """)

    def test_map_can_restart_after_leave_without_waiting_for_rate_limit(self):
        self.lua.execute("""
            local afk = ZM_AFK
            assert(afk:Begin(target, "map", 96))
            afk:Tick(target, 99)
            clock = 100
            assert(afk:HandleRequest(target, afk.Actions.leave, ""))
            clock = 100.05
            assert(afk:HandleRequest(target, afk.Actions.begin, "map"))
            assert(afk:GetState(target).countdownMenu == "map")
        """)


class ClientWorldMapAfkTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, ["cl_afk.lua", "cl_world_map.lua", "cl_quick_menu.lua"])
        self.lua = self.runner.lua
        self.lua.execute("""
            clock = 100
            CurTime = function() return clock end
            RealTime = function() return clock end
            IsValid = function(value) return type(value) == "table" and value.valid == true end
            surface = { CreateFont = function() end, PlaySound = function() end }
            hooks = {}
            hook = { Add = function(_, name, callback) hooks[name] = callback end }
            commands = {}
            concommand = { Add = function(name, callback) commands[name] = callback end }
            requests, receivers = {}, {}
            net = {
                Receive = function(name, callback) receivers[name] = callback end,
                Start = function(name) currentRequest = { name = name } end,
                WriteUInt = function(value) currentRequest.action = value end,
                WriteString = function(value) currentRequest.menu = value end,
                SendToServer = function() table.insert(requests, currentRequest) end,
                ReadBool = function() return nextValue() end,
                ReadFloat = function() return nextValue() end,
                ReadString = function() return nextValue() end
            }
            function receiveState(...)
                values, valueIndex = {...}, 0
                receivers["ZM.AFKState"]()
            end
            function nextValue()
                valueIndex = valueIndex + 1
                return values[valueIndex]
            end
            ZM_WorldMap = {}
            WorldMap = ZM_WorldMap
            QuickMenu = {}
            input = { IsKeyDown = function(key) return key == KEY_M and mDown end }
            KEY_M, KEY_LCONTROL, KEY_RCONTROL = 1, 2, 3
            vgui = { GetKeyboardFocus = function() return nil end }
            gui = { IsGameUIVisible = function() return false end }
            ErrorNoHalt = function(message) error(message) end
        """)
        self.runner.load("cl_afk.lua")
        source = lua_source(ROOT / "cl_world_map.lua")
        start = source.index("function WorldMap:Open()")
        end = source.index("    self:LoadPersistentState()", start)
        self.lua.execute(source[start:end] + """
            self.openCount = (self.openCount or 0) + 1
            self.Frame = { valid = true }
            function self.Frame:Remove() self.valid = false end
        end
        """)
        start = source.index("function WorldMap:Toggle()")
        end = source.index('\nconcommand.Add("zombiesim_map"', start)
        self.lua.execute(source[start:end])
        start = source.index('concommand.Add("zombiesim_map"')
        end = source.index('\nconcommand.Add("zombiesim_world_map_view_status"', start)
        self.lua.execute(source[start:end])
        start = source.index('hook.Add("Think", "ZM.WorldMap.M"')
        end = source.index('\nhook.Add("PostRender", "ZM.WorldMap.LocalMapRefresh"', start)
        self.lua.execute(source[start:end])
        source = lua_source(ROOT / "cl_quick_menu.lua")
        start = source.index("function QuickMenu:OpenDestination(entryId)")
        end = source.index("\nfunction QuickMenu:Close(", start)
        self.lua.execute(source[start:end])
        self.lua.execute("""
            function pressM()
                mDown = true
                hooks["ZM.WorldMap.M"]()
                mDown = false
                hooks["ZM.WorldMap.M"]()
            end
        """)

    def test_m_countdown_cancel_open_heartbeat_and_close(self):
        self.lua.execute("""
            pressM()
            assert(#requests == 1 and requests[1].action == ZM_AFK.Actions.begin)
            assert(requests[1].menu == "map" and ZM_AFK.State.countdownMenu == "map")
            assert(not IsValid(WorldMap.Frame))
            pressM()
            assert(#requests == 2 and requests[2].action == ZM_AFK.Actions.cancel)
            assert(ZM_AFK.State.countdownMenu == "")
            receiveState(false, 0, "", 0, "", "")
            pressM()
            receiveState(false, 103, "map", 0, "", "")
            receiveState(true, 0, "", 0, "map", "")
            assert(IsValid(WorldMap.Frame) and WorldMap.openCount == 1)
            hooks["ZM.AFK.MenuWatch"]()
            assert(requests[#requests].action == ZM_AFK.Actions.hold)
            pressM()
            assert(not IsValid(WorldMap.Frame))
            clock = 100.2
            hooks["ZM.AFK.MenuWatch"]()
            assert(requests[#requests].action == ZM_AFK.Actions.leave)
            local requestCount = #requests
            clock = 100.4
            hooks["ZM.AFK.MenuWatch"]()
            assert(#requests == requestCount)
        """)

    def test_tab_menu_and_direct_open_cannot_skip_countdown(self):
        self.lua.execute("""
            QuickMenu:OpenDestination("map")
            assert(requests[1].action == ZM_AFK.Actions.begin and requests[1].menu == "map")
            assert(not IsValid(WorldMap.Frame))
            receiveState(false, 0, "", 0, "", "")
            requests = {}
            WorldMap:Open()
            assert(requests[1].action == ZM_AFK.Actions.begin and requests[1].menu == "map")
            assert(not IsValid(WorldMap.Frame))
        """)

    def test_map_console_command_uses_the_same_countdown_and_close_path(self):
        self.lua.execute("""
            commands.zombiesim_map()
            assert(requests[1].action == ZM_AFK.Actions.begin and requests[1].menu == "map")
            assert(not IsValid(WorldMap.Frame))
            receiveState(true, 0, "", 0, "map", "")
            assert(IsValid(WorldMap.Frame))
            commands.zombiesim_map()
            assert(not IsValid(WorldMap.Frame))
            hooks["ZM.AFK.MenuWatch"]()
            assert(requests[#requests].action == ZM_AFK.Actions.leave)
        """)

    def test_map_overlap_and_launcher_guard(self):
        self.lua.execute("""
            ZM_LauncherMenu = { Active = true }
            WorldMap:Open()
            assert(#requests == 0 and not IsValid(WorldMap.Frame))
            ZM_LauncherMenu.Active = false
            ZM_Inventory = { Frame = { valid = true } }
            ZM_AFK.State.afk = true
            WorldMap:Open()
            assert(IsValid(WorldMap.Frame) and #requests == 0)
            WorldMap.Frame:Remove()
            hooks["ZM.AFK.MenuWatch"]()
            assert(requests[#requests].action == ZM_AFK.Actions.hold)
            ZM_Inventory.Frame.valid = false
            clock = 100.2
            hooks["ZM.AFK.MenuWatch"]()
            assert(requests[#requests].action == ZM_AFK.Actions.leave)
        """)

    def test_reopening_during_leave_waits_for_server_and_starts_a_countdown(self):
        self.lua.execute("""
            ZM_AFK.State.afk = true
            WorldMap:Open()
            WorldMap.Frame:Remove()
            hooks["ZM.AFK.MenuWatch"]()
            assert(requests[#requests].action == ZM_AFK.Actions.leave)
            pressM()
            assert(not IsValid(WorldMap.Frame), "map reopened before the server acknowledged leave")
            receiveState(false, 0, "", 103, "", "")
            assert(requests[#requests].action == ZM_AFK.Actions.begin)
            assert(requests[#requests].menu == "map" and not IsValid(WorldMap.Frame))
            receiveState(true, 0, "", 0, "map", "")
            assert(IsValid(WorldMap.Frame) and ZM_AFK.State.afk)
        """)

    def test_queued_reopen_can_be_cancelled_before_leave_acknowledgement(self):
        self.lua.execute("""
            ZM_AFK.State.afk = true
            WorldMap:Open()
            WorldMap.Frame:Remove()
            hooks["ZM.AFK.MenuWatch"]()
            pressM()
            pressM()
            receiveState(false, 0, "", 103, "", "")
            assert(#requests == 1 and requests[1].action == ZM_AFK.Actions.leave)
            assert(not IsValid(WorldMap.Frame))
        """)


if __name__ == "__main__":
    unittest.main()
