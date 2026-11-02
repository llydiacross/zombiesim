"""Offline land-claim fixtures (Alpha 3.4 Phase E): real sql.lua writers on SQLite, explicit engine fakes."""

from pathlib import Path
import sqlite3
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"
LIFETIME = 30 * 24 * 60 * 60


class ClaimServiceTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.last_error = None
        runner = FixtureRunner(ROOT, ["utils/sql.lua", "sv_claims.lua"])
        lua = self.lua = runner.lua

        def query(statement):
            # Mirrors GMod sql.Query: false on error, nil for no rows, otherwise rows of string values.
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
                lua.table_from({name: (None if value is None else str(value)) for name, value in zip(names, row)})
                for row in rows
            ])

        lua.globals().py_query = query
        lua.globals().py_last_error = lambda: self.last_error
        lua.execute("""
            SERVER = false
            sql = {}
            function sql.Query(statement) return py_query(statement) end
            function sql.LastError() return py_last_error() end
            function sql.SQLStr(value) return "'" .. tostring(value):gsub("'", "''") .. "'" end
            function sql.QueryValue(statement)
                local rows = sql.Query(statement)
                if not rows then return rows end
                for _, value in pairs(rows[1]) do return value end
            end
            function IsValid(value) return value ~= nil and value.valid == true end
            ZM_Util = {
                ProfileFor = function(target) return target.profile end,
                CharacterKeyFor = function(target) return target.character end,
                IsWholeNumber = function(value, minimum, maximum)
                    return type(value) == "number" and value == math.floor(value)
                        and (minimum == nil or value >= minimum) and (maximum == nil or value <= maximum)
                end
            }
            loadedMap = "zz_cell_a"
            game = { GetMap = function() return loadedMap end }
            ZM_SafeZones = { IsSafeZoneCell = function(_, cell) return cell.safe == true end }
            claimable = { ["0,0"] = true, ["1,0"] = true, ["-2,2"] = true }
            ZM_World = {
                ActiveProfile = "fixture",
                GetMapPath = function(_, cell) return "maps/" .. cell.map end,
                GetCellBounds = function() return { tileSize = 640, coreHalfExtent = 1600 } end,
                IsClaimableTile = function(_, cellId, x, y) return cellId == 7 and claimable[x .. "," .. y] == true end,
                GetClaimTiles = function() return { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = -2, y = 2 } } end,
                GetCoreTileAt = function(_, position)
                    if math.abs(position.x) >= 1600 or math.abs(position.y) >= 1600 then return nil end
                    return math.floor(position.x / 640 + 0.5), math.floor(position.y / 640 + 0.5)
                end
            }
            failNextSave = false
            ZM_InventoryService = {
                Ops = {
                    Remove = function(draft, container, itemId, count)
                        local held = draft[container][itemId] or 0
                        if held < count then return false, "not enough items" end
                        draft[container][itemId] = held - count
                        return true
                    end
                },
                Mutate = function(_, target, mutator, options)
                    local draft = { backpack = {} }
                    for key, value in pairs(target.inventory.backpack) do draft.backpack[key] = value end
                    local ok, result = mutator(draft)
                    if not ok then return false, result end
                    local steps = options.extraSteps(draft, result)
                    if failNextSave then
                        failNextSave = false
                        steps[#steps + 1] = { kind = "noSuchWriter", steamid = "x" }
                    end
                    local saved, saveError = ZM_CommitWrites(target.profile, steps)
                    if not saved then return false, "could not save inventory: " .. tostring(saveError) end
                    target.inventory = draft
                    return true, result
                end
            }
            clock = 1000000000
            function person(account, character, x, y)
                local target = { valid = true, ZM_PersistentStateLoaded = true, profile = "fixture",
                    character = character, account = account, inventory = { backpack = { itemClaimToken = 2 } },
                    cell = { id = 7, map = "zz_cell_a" }, position = { x = x or 0, y = y or 0, z = 0 } }
                function target:SteamID() return self.account end
                function target:IsBot() return false end
                function target:GetWorldCell() return self.cell end
                function target:GetPos() return self.position end
                return target
            end
            function tokens(target) return target.inventory.backpack.itemClaimToken end
        """)
        runner.load("utils/sql.lua")
        runner.load("sv_claims.lua")
        lua.execute("""
            assert(ZM_CreateClaimTables())
            ZM_ClaimService.StorageReady = true
            ZM_ClaimService.Now = function() return clock end
        """)

    def run_lua(self, source):
        self.lua.execute(source)

    def test_claim_consumes_one_token_and_blocks_others(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a")
            local ok, result = ZM_ClaimService:ClaimTile(owner)
            assert(ok, result)
            assert(result.cellId == 7 and result.tileX == 0 and result.tileY == 0)
            assert(tokens(owner) == 1)
            local rival = person("STEAM_0:1:200", "rival")
            local blocked, reason = ZM_ClaimService:ClaimTile(rival, 0, 0)
            assert(not blocked and reason:find("already claimed"), reason)
            assert(tokens(rival) == 2, "a rejected claim keeps the token")
            local rows = ZM_GetCellClaims("fixture", 7)
            assert(#rows == 1 and rows[1].owner == "owner_a" and rows[1].account == "STEAM_0:1:100")
        """)

    def test_failed_save_keeps_token_and_writes_no_claim(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a")
            failNextSave = true
            local ok = ZM_ClaimService:ClaimTile(owner)
            assert(not ok and tokens(owner) == 2)
            assert(#ZM_GetCellClaims("fixture", 7) == 0, "rolled back with the inventory")
        """)

    def test_eligibility_rejections(self):
        self.run_lua("""
            local function rejects(target, x, y, text)
                local ok, reason = ZM_ClaimService:ClaimTile(target, x, y)
                assert(not ok and tostring(reason):find(text, 1, true), tostring(reason))
                assert(tokens(target) == 2)
            end
            rejects(person("STEAM_0:1:1", "a", 0, 640), 0, 1, "cannot be claimed")
            rejects(person("STEAM_0:1:1", "a"), 3, 0, "Invalid tile")
            rejects(person("STEAM_0:1:1", "a"), 0.5, 0, "Invalid tile")
            rejects(person("STEAM_0:1:1", "a", 0, 0), -2, 2, "Move closer")
            local den = person("STEAM_0:1:1", "a"); den.CurrentSafeZoneId = "den"
            rejects(den, 0, 0, "inside a den")
            local safe = person("STEAM_0:1:1", "a"); safe.cell.safe = true
            rejects(safe, 0, 0, "safe-zone cell")
            local elsewhere = person("STEAM_0:1:1", "a"); elsewhere.cell.map = "zz_other"
            rejects(elsewhere, 0, 0, "not loaded")
            local outside = person("STEAM_0:1:1", "a", 2000, 0)
            rejects(outside, nil, nil, "core tiles")
            local bot = person("STEAM_0:1:1", "a"); bot.IsBot = function() return true end
            rejects(bot, 0, 0, "active survivor")
            local unloaded = person("STEAM_0:1:1", "a"); unloaded.ZM_PersistentStateLoaded = false
            rejects(unloaded, 0, 0, "active survivor")
            local empty = person("STEAM_0:1:1", "a"); empty.inventory.backpack.itemClaimToken = 0
            local ok = ZM_ClaimService:ClaimTile(empty, 0, 0)
            assert(not ok and #ZM_GetCellClaims("fixture", 7) == 0, "no token, no claim")
            ZM_ClaimService.StorageReady = false
            rejects(person("STEAM_0:1:1", "a"), 0, 0, "storage is unavailable")
        """)

    def test_adjacent_tile_can_be_claimed(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a", 0, 0)
            assert(ZM_ClaimService:ClaimTile(owner, 1, 0))
            assert(ZM_GetCellClaims("fixture", 7)[1].tileX == 1)
        """)

    def test_lapsed_claim_is_replaced_and_visits_never_revive_it(self):
        self.run_lua(f"""
            local owner = person("STEAM_0:1:100", "owner_a")
            assert(ZM_ClaimService:ClaimTile(owner))
            clock = clock + {LIFETIME} + 1
            local ok, refreshed = ZM_ClaimService:RecordVisit(owner, true)
            assert(ok and refreshed == 0, "a lapsed claim is not refreshed")
            assert(ZM_GetCellClaims("fixture", 7)[1].lastVisitAt == clock - {LIFETIME} - 1)
            local snapshot = ZM_ClaimService:CellSnapshot(owner)
            assert(#snapshot.claims == 1 and not snapshot.claims[1].active)
            local rival = person("STEAM_0:1:200", "rival")
            assert(ZM_ClaimService:ClaimTile(rival))
            local rows = ZM_GetCellClaims("fixture", 7)
            assert(#rows == 1 and rows[1].owner == "rival" and rows[1].createdAt == clock)
        """)

    def test_visits_by_owner_account_and_friends_refresh_active_claims(self):
        self.run_lua(f"""
            local owner = person("STEAM_0:1:100", "owner_a")
            assert(ZM_ClaimService:ClaimTile(owner))
            local created = clock
            local stranger = person("STEAM_0:1:300", "stranger")
            clock = clock + 100
            local ok, count = ZM_ClaimService:RecordVisit(stranger, true)
            assert(ok and count == 0 and ZM_GetCellClaims("fixture", 7)[1].lastVisitAt == created)
            local alt = person("STEAM_0:1:100", "owner_b")
            ok, count = ZM_ClaimService:RecordVisit(alt, true)
            assert(ok and count == 1, "another survivor on the owner's account")
            assert(ZM_GetCellClaims("fixture", 7)[1].lastVisitAt == clock)
            assert(not ZM_ClaimService:AddFriend(owner, "STEAM_0:1:100"), "own account is rejected")
            assert(not ZM_ClaimService:AddFriend(owner, "not-an-account"))
            assert(ZM_ClaimService:AddFriend(owner, "STEAM_0:1:300"))
            assert(ZM_ClaimService:AddFriend(owner, "STEAM_0:1:300"), "adding twice is idempotent")
            assert(#ZM_GetClaimFriends("fixture", "owner_a") == 1)
            clock = clock + 100
            ok, count = ZM_ClaimService:RecordVisit(stranger, true)
            assert(ok and count == 1, "friends refresh the claim")
            local far = person("STEAM_0:1:100", "owner_a", 1600, 1600)
            clock = clock + 100
            ok, count = ZM_ClaimService:RecordVisit(far, true)
            assert(ok and count == 0, "visits must be near the tile")
            assert(ZM_ClaimService:RemoveFriend(owner, "STEAM_0:1:300"))
            ok, count = ZM_ClaimService:RecordVisit(stranger, true)
            assert(ok and count == 0, "removed friends lose access")
        """)

    def test_visit_throttle(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a")
            assert(ZM_ClaimService:ClaimTile(owner))
            clock = clock + 30
            local ok, count = ZM_ClaimService:RecordVisit(owner)
            assert(ok and count == 0, "throttled within the visit interval after claiming")
            clock = clock + 31
            ok, count = ZM_ClaimService:RecordVisit(owner)
            assert(ok and count == 1)
        """)

    def test_delete_claim_data_cleans_only_owner(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a")
            local other = person("STEAM_0:1:200", "owner_b", 640, 0)
            assert(ZM_ClaimService:ClaimTile(owner))
            assert(ZM_ClaimService:ClaimTile(other, 1, 0))
            assert(ZM_ClaimService:AddFriend(owner, "STEAM_0:1:300"))
            assert(ZM_DeleteClaimData("fixture", "owner_a"))
            local rows = ZM_GetCellClaims("fixture", 7)
            assert(#rows == 1 and rows[1].owner == "owner_b")
            assert(#ZM_GetClaimFriends("fixture", "owner_a") == 0)
        """)


if __name__ == "__main__":
    unittest.main()
