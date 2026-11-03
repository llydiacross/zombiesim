"""Offline dropped-crate restoration fixtures using the shared Lua harness."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class DroppedItemRestorationTests(unittest.TestCase):
    def setUp(self):
        runner = FixtureRunner(ROOT, ["sv_dropped_items.lua"])
        self.lua = runner.lua
        self.lua.execute("""
            SOLID_NONE = 0
            SOLID_BBOX = 2
            function Vector(x, y, z) return { x = x, y = y, z = z } end
            function Angle(p, y, r) return { p = p, y = y, r = r } end
            function IsValid(value) return type(value) == "table" and value.valid == true end
            function table.Copy(value)
                if type(value) ~= "table" then return value end
                local copy = {}
                for key, entry in pairs(value) do copy[key] = table.Copy(entry) end
                return copy
            end

            fixturePlayers = {}
            player = { GetAll = function() return fixturePlayers end }
            function fixturePlayer(minimum, maximum)
                return {
                    valid = true,
                    WorldSpaceAABB = function() return minimum, maximum end
                }
            end
            spawned = {}
            ents = {
                Create = function(class)
                    assert(class == "zn_dropped_item", "unexpected entity class")
                    local entity = { valid = true, solid = SOLID_BBOX }
                    function entity:SetPos(position) self.position = position end
                    function entity:SetAngles(angles) self.angles = angles end
                    function entity:Spawn() self.spawned = true end
                    function entity:GetModelBounds() return Vector(-16, -16, 0), Vector(16, 16, 24) end
                    function entity:Activate() self.activated = true end
                    function entity:WorldSpaceAABB()
                        assert(self.angles.y == 0, "fixture only models an unrotated collision box")
                        return Vector(self.position.x - 16, self.position.y - 16, self.position.z),
                            Vector(self.position.x + 16, self.position.y + 16, self.position.z + 24)
                    end
                    function entity:SetSolid(solid) self.solid = solid end
                    function entity:Remove() self.solidAtRemoval = self.solid; self.valid = false end
                    function entity:SetDropData(row) self.data = table.Copy(row) end
                    spawned[#spawned + 1] = entity
                    return entity
                end
            }
            util = {
                IsValidModel = function(model) return model == "models/props_junk/wood_crate001a.mdl" end,
                JSONToTable = function(value)
                    assert(value == "fixture-item", "unexpected saved item")
                    return { instanceId = "fixture-item", itemId = "itemBandage", count = 1 }
                end
            }
            ZM_InventoryService = {}
            ZM_Items = {
                ValidateInstance = function(_, instance)
                    return instance.itemId == "itemBandage" and instance.count == 1
                end
            }
            game = { GetMap = function() return "fixture_map" end }
            local now = os.time()
            stored = {
                { dropId = "fixture-drop", itemData = "fixture-item", itemCount = 1,
                    x = 0, y = 0, z = 100, yaw = 0, createdAt = now, expiresAt = now + 600 }
            }
            ZM_CreateWorldDroppedItemTables = function() return true end
            ZM_DeleteExpiredWorldDroppedItems = function(profile, location, timestamp)
                assert(profile == "preview" and location == "cell:7" and timestamp >= now)
                return true
            end
            ZM_GetWorldDroppedItems = function(profile, location)
                assert(profile == "preview" and location == "cell:7")
                return table.Copy(stored)
            end
            ZM_DeleteWorldDroppedItem = function() error("unexpired fixture drop must not be deleted") end
            ZM_DeleteExpiredWorldDropRequests = function(profile, location, timestamp)
                assert(profile == "preview" and location == "cell:7" and timestamp >= now)
                return true
            end
            errors = {}
            ErrorNoHalt = function(message) errors[#errors + 1] = message end
            timers = {}
            timer = { Create = function(name, interval, repetitions, callback)
                assert(name == "ZM.DroppedItems.Expiry" and interval == 30 and repetitions == 0)
                timers[name] = callback
            end }
            hook = { Add = function(event, name, callback)
                assert(event == "InitPostEntity" and name == "ZM.DroppedItems.ClearPreviousCell")
            end }
        """)
        runner.load("sv_dropped_items.lua")
        self.lua.execute("""
            ZM_DroppedItems.GetTargetLocation = function()
                return "preview", 7, "cell:7", { id = 7 }
            end
            target = { ZM_PersistentStateLoaded = true }
        """)

    def test_restoration_waits_for_player_then_retries_without_losing_row(self):
        self.lua.execute("""
            fixturePlayers = { fixturePlayer(Vector(-32, -32, 90), Vector(32, 32, 150)) }
            loaded, loadError = ZM_DroppedItems:OnPlayerReady(target)
            assert(loaded, tostring(loadError))
        """)
        self.assertTrue(self.lua.eval("ZM_DroppedItems.Cell.rows['fixture-drop'] ~= nil"))
        self.assertTrue(self.lua.eval("ZM_DroppedItems.Cell.entities['fixture-drop'] == nil"))
        self.assertEqual(self.lua.eval("#stored"), 1)
        self.assertEqual(self.lua.eval("spawned[1].solidAtRemoval"), self.lua.globals().SOLID_NONE)
        self.assertIn("overlap a player", self.lua.eval("errors[1]"))

        self.lua.execute("timers['ZM.DroppedItems.Expiry']()")
        self.assertTrue(self.lua.eval("ZM_DroppedItems.Cell.entities['fixture-drop'] == nil"))
        self.assertEqual(self.lua.eval("#stored"), 1)
        self.assertEqual(self.lua.eval("spawned[2].solidAtRemoval"), self.lua.globals().SOLID_NONE)

        self.lua.execute("""
            fixturePlayers = {}
            timers['ZM.DroppedItems.Expiry']()
        """)
        self.assertTrue(self.lua.eval("IsValid(ZM_DroppedItems.Cell.entities['fixture-drop'])"))
        self.assertEqual(self.lua.eval("ZM_DroppedItems.Cell.entities['fixture-drop'].data.dropId"), "fixture-drop")
        self.assertEqual(self.lua.eval("#stored"), 1)


if __name__ == "__main__":
    unittest.main()
