"""Run the native inventory-slot regressions offline against isolated SQLite."""

from pathlib import Path
import sqlite3
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class InventorySlotTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.last_error = None
        self.runner = FixtureRunner(ROOT, [
            "utils/sql.lua",
            "utils/test_harness.lua",
            "sv_inventory.lua",
            "sv_ammo.lua",
            "tests/sv_inventory_tests.lua",
        ])
        lua = self.runner.lua

        def query(statement):
            try:
                cursor = self.db.execute(statement)
                rows = cursor.fetchall()
            except sqlite3.Error as error:
                self.last_error = str(error)
                return False
            if not rows:
                return None
            names = [column[0] for column in cursor.description]
            return lua.table_from([
                lua.table_from({
                    name: ("NULL" if value is None else str(value))
                    for name, value in zip(names, row)
                })
                for row in rows
            ])

        lua.globals().py_query = query
        lua.globals().py_last_error = lambda: self.last_error
        lua.execute("""
            sql = {}
            function sql.Query(statement) return py_query(statement) end
            function sql.LastError() return py_last_error() end
            function sql.SQLStr(value) return "'" .. tostring(value):gsub("'", "''") .. "'" end
            function sql.QueryValue(statement)
                local rows = sql.Query(statement)
                if not rows then return rows end
                for _, value in pairs(rows[1]) do return value end
            end

            function table.Copy(value)
                if type(value) ~= "table" then return value end
                local copy = {}
                for key, entry in pairs(value) do copy[key] = table.Copy(entry) end
                return copy
            end
            function math.Clamp(value, minimum, maximum)
                return math.max(minimum, math.min(maximum, value))
            end
            function table.Add(target, source)
                for _, value in ipairs(source) do target[#target + 1] = value end
                return target
            end
            function SortedPairs(value)
                local keys = {}
                for key in pairs(value) do keys[#keys + 1] = key end
                table.sort(keys)
                local index = 0
                return function()
                    index = index + 1
                    local key = keys[index]
                    if key ~= nil then return key, value[key] end
                end
            end
            function IsValid(value)
                return type(value) == "table" and type(value.IsValid) == "function" and value:IsValid()
            end
            local playerMeta = {}
            function FindMetaTable(name)
                assert(name == "Player")
                return playerMeta
            end
            local definitions = {
                weaponFamas = { minLevel = 1, entityClass = "weapon", type = "bullet_weapon", ammoId = "ammo556", weaponClass = "fixture_famas" },
                weaponHandgun9mm = { minLevel = 1, entityClass = "weapon", type = "bullet_weapon", ammoId = "ammo9mm", weaponClass = "fixture_handgun" },
                weaponElite = { minLevel = 1, entityClass = "weapon", type = "bullet_weapon", ammoId = "ammo9mm", weaponClass = "fixture_elite" },
                weaponMeleeHammer = { minLevel = 8, entityClass = "weapon", weaponClass = "fixture_hammer" },
                weaponMeleeCrowbar = { minLevel = 1, entityClass = "weapon", weaponClass = "fixture_crowbar" }
            }
            ZM_Items = {
                ContainerCapacity = { backpack = 20, stash = 20 },
                Containers = { backpack = true, equipped = true, stash = true },
                ArmourSlot = 4,
                GetDefinition = function(_, id) return definitions[id] end,
                CanUse = function(_, target, id, item)
                    assert(definitions[id] and item.itemId == id)
                    return target:GetLevel() >= item.level, "fixture level requirement"
                end,
                ApplyInstanceToWeapon = function(_, weapon, item)
                    weapon:SetItemInstanceId(item.instanceId)
                    if weapon.OnItemInstanceApplied then weapon:OnItemInstanceApplied(item) end
                end
            }
            ZM_ItemGeneration = { NewInstanceId = function() error("unexpected item generation") end }
            ZM_Util = {
                ProfileFor = function(target) return target.ZM_InventoryProfile end,
                CharacterKeyFor = function(target) return target:SteamID() end,
                IsWholeNumber = function(value, minimum, maximum)
                    return type(value) == "number" and value == math.floor(value)
                        and (minimum == nil or value >= minimum) and (maximum == nil or value <= maximum)
                end,
                RegisterCommands = function() end
            }
            ZM_Clothing = { Slots = { shirt = 5, pants = 6 }, GetEquipped = function() return "" end }
            ZM_SafeZones = {}
            ZM_DroppedItems = {}
            weapons = { GetStored = function(class)
                for _, definition in pairs(definitions) do
                    if definition.weaponClass == class then return definition end
                end
            end }
            util = {
                AddNetworkString = function() end,
                TableToJSON = function(value) if type(value) == "table" then return "{}" end end,
                JSONToTable = function(value) if value == "{}" then return {} end end
            }
            net = {
                Receive = function() end,
                Start = function() error("unexpected network send") end,
                WriteString = function() error("unexpected network write") end,
                Send = function() error("unexpected network recipient") end
            }
            local hooks = {}
            hook = {
                Add = function(event, name, callback)
                    hooks[event] = hooks[event] or {}
                    hooks[event][name] = callback
                end,
                GetTable = function() return hooks end
            }
            concommand = { Add = function() end }
            game = { GetMap = function() return "fixture" end }
            function ErrorNoHalt(message) error(message) end
        """)
        self.runner.load("utils/sql.lua")
        lua.execute("assert(ZM_CreatePlayerItemsTable())")
        self.runner.load("utils/test_harness.lua")
        lua.execute("""
            local createSuite = ZM_TestHarness.NewSuite
            ZM_TestHarness.NewSuite = function()
                inventoryFixtureSuite = createSuite()
                return inventoryFixtureSuite
            end
            ZM_TestHarness.Register = function() end
        """)
        self.runner.load("sv_inventory.lua")
        self.runner.load("sv_ammo.lua")
        self.runner.load("tests/sv_inventory_tests.lua")

    def tearDown(self):
        self.db.close()

    def run_case(self, name):
        selected = self.runner.lua.eval("""
            function(suite, name)
                local result = { cases = {} }
                for _, case in ipairs(suite.cases) do
                    if case.name == name then result.cases[#result.cases + 1] = case end
                end
                assert(#result.cases == 1, "expected exactly one matching inventory case")
                setmetatable(result, getmetatable(suite))
                return { Run = function() return result:Run() end }
            end
        """)(self.runner.lua.globals().inventoryFixtureSuite, name)
        self.runner.run(selected, name)

    def test_conflicting_slot_recovery_and_snapshot(self):
        self.run_case("weapon_slot_conflict_recovers_occupied_weapon_and_backpack_snapshot")

    def test_stale_held_reference_does_not_hide_backpack(self):
        self.run_case("backpack_snapshot_never_hides_a_stale_held_reference")

    def test_occupied_slot_rejection(self):
        self.run_case("occupied_weapon_slot_rejection_preserves_inventory_and_selection")

    def test_equip_commits_items_and_slots(self):
        self.run_case("weapon_slot_equip_commits_items_and_loadout_together")

    def test_legacy_backpack_weapon_recovers_in_empty_slot(self):
        self.run_case("legacy_backpack_weapon_recovers_into_its_empty_slot")

    def test_failed_legacy_recovery_rolls_back(self):
        self.run_case("legacy_backpack_recovery_write_failure_keeps_the_item")

    def test_existing_drag_to_backpack_regression(self):
        self.run_case("unequip_drag_to_backpack_keeps_item")

    def test_existing_backpack_weapon_requires_equip(self):
        self.run_case("held_backpack_weapon_still_requires_an_atomic_equip")

    def test_spawn_failure_preserves_state(self):
        self.run_case("weapon_spawn_failure_leaves_inventory_and_slots_unchanged")

    def test_equipping_hammer_saves_firearm_ammunition(self):
        self.run_case("equipping_a_hammer_preserves_active_firearm_ammunition")

    def test_reselecting_keeps_the_live_firearm_clip(self):
        self.run_case("reselecting_a_firearm_keeps_its_live_clip")

    def test_failed_ammo_sync_prevents_equip(self):
        self.run_case("failed_firearm_sync_prevents_weapon_equip")

    def test_failed_equip_preserves_same_class_weapon(self):
        self.run_case("failed_equip_preserves_an_existing_same_class_weapon")

    def test_restore_preserves_selected_instance(self):
        self.run_case("weapon_restore_preserves_selected_instance_and_slots")

    def test_inventory_load_repairs_conflicts(self):
        self.run_case("inventory_load_repairs_conflicts_and_restores_selection")

    def test_selection_write_failure(self):
        self.run_case("weapon_selection_write_failure_keeps_previous_slots")

    def test_slot_swap_is_atomic(self):
        self.run_case("weapon_slot_swap_commits_or_rolls_back_both_tables")

    def test_drag_to_backpack_is_atomic(self):
        self.run_case("weapon_drag_to_backpack_commits_or_rolls_back_both_tables")

    def test_unequip_selects_the_next_weapon(self):
        self.run_case("unequip_persists_the_next_active_weapon")

    def test_equip_write_failure_rolls_back(self):
        self.run_case("weapon_slot_equip_write_failure_rolls_back_items_and_loadout")

    def test_reconciliation_write_failure_rolls_back(self):
        self.run_case("weapon_slot_reconciliation_write_failure_preserves_both_tables")

    def test_snapshot_reports_repair_failure(self):
        self.run_case("inventory_snapshot_reports_reconciliation_failure")


if __name__ == "__main__":
    unittest.main()
