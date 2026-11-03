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
        runner = FixtureRunner(ROOT, ["utils/sql.lua", "sv_claims.lua", "sv_claim_review_test.lua"])
        lua = self.lua = runner.lua

        def query(statement):
            # GMod sql.Query returns strings for every column, including "NULL" for SQL NULL.
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
                lua.table_from({name: ("NULL" if value is None else str(value)) for name, value in zip(names, row)})
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
            reviewRadiation = 0
            reviewHumans = {}
            reviewEntities = {}
            player = { GetHumans = function() return reviewHumans end }
            ents = { FindByClass = function() return reviewEntities end }
            util = util or {}
            util.JSONToTable = function(value)
                if value == "{}" then return {} end
                if value == '{"a":1,"b":2}' or value == '{"b":2,"a":1}' then return { a = 1, b = 2 } end
                return nil
            end
            util.TableToJSON = function() return "{}" end
            claimable = { ["0,0"] = true, ["1,0"] = true, ["-2,2"] = true }
            ZM_World = {
                ActiveProfile = "fixture",
                DataPath = "data_static/zombiesim_world_fixture.json",
                GetMapPath = function(_, cell) return "maps/" .. cell.map end,
                GetCellById = function(_, cellId)
                    if cellId == 7 then return { id = 7, map = "zz_cell_a" } end
                    return nil
                end,
                GetRadiationIntensity = function() return reviewRadiation end,
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
                end,
                Load = function() return true end,
                ReconcileEquippedWeapons = function() end,
                Send = function(_, target, options)
                    lastInventorySendOptions = options
                    for _, loadout in pairs(target.ZM_WeaponSlots or {}) do
                        assert(loadout.instanceId, "inventory snapshots cannot index an empty weapon slot")
                    end
                end
            }
            ZM_Items = {
                ContainerCapacity = { backpack = 60 },
                CanUse = function(_, target, itemId, instance)
                    assert(itemId == "weaponMeleeHammer" and instance.itemId == itemId)
                    if target:GetLevel() < instance.level then
                        return false, "Requires player level " .. instance.level .. "."
                    end
                    if (target.strength or 5) < 5 then return false, "Requires Strength 5." end
                    return true, ""
                end
            }
            local nextReviewItemId = 0
            ZM_ItemGeneration = {
                CreateInstance = function(_, itemId, options)
                    nextReviewItemId = nextReviewItemId + 1
                    return {
                        instanceId = "review_item_" .. nextReviewItemId,
                        itemId = itemId,
                        count = options.count or 1,
                        level = options.level or 1,
                        mastercraft = options.mastercraft == true,
                        createdAt = os.time(),
                        clip = 0
                    }
                end
            }
            ZM_Construction = {
                PieceClass = "zn_construction_piece",
                SlotRegistry = {},
                Clear = function() end
            }
            lastDevReport = nil
            ZM_DevConsole = {
                DirectCommands = {},
                Report = function(_, name, data) lastDevReport = { name = name, data = data } end
            }
            ZM_Util.FirstHuman = function() return reviewHumans[1] end
            clock = 1000000000
            function person(account, character, x, y)
                local target = { valid = true, ZM_PersistentStateLoaded = true, profile = "fixture",
                    character = character, account = account, inventory = { backpack = { itemClaimToken = 2 } },
                    ZM_Inventory = { backpack = {}, equipped = {}, stash = {} }, ZM_WeaponSlots = {},
                    cell = { id = 7, map = "zz_cell_a" }, position = { x = x or 0, y = y or 0, z = 0 } }
                function target:SteamID() return self.account end
                function target:IsBot() return false end
                function target:GetWorldCell() return self.cell end
                function target:GetPos() return self.position end
                function target:IsPlayer() return false end
                return target
            end
            function tokens(target) return target.inventory.backpack.itemClaimToken end
        """)
        runner.load("utils/sql.lua")
        runner.load("sv_claims.lua")
        runner.load("sv_claim_review_test.lua")
        lua.execute("""
            assert(ZM_CreateClaimTables())
            assert(ZM_CreateConstructionTables())
            assert(ZM_CreatePlayerItemsTable())
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

    def test_client_snapshot_lists_cell_claims_and_owned_claims(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a")
            local before = ZM_ClaimService:ClientSnapshot(owner)
            assert(before.cellId == 7 and #before.claims == 0 and #before.owned == 0)
            local emptySignature = ZM_ClaimService.SnapshotSignature(before)
            assert(ZM_ClaimService:ClaimTile(owner, 1, 0))
            local after = ZM_ClaimService:ClientSnapshot(owner)
            assert(#after.claims == 1 and after.claims[1].mine and after.claims[1].active)
            assert(#after.owned == 1 and after.owned[1].cellId == 7 and after.owned[1].tileX == 1)
            assert(ZM_ClaimService.SnapshotSignature(after) ~= emptySignature)
            local rival = ZM_ClaimService:ClientSnapshot(person("STEAM_0:1:200", "rival"))
            assert(#rival.claims == 1 and not rival.claims[1].mine and not rival.claims[1].access)
            assert(#rival.owned == 0)
        """)

    def test_claim_request_validates_and_rate_limits(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a")
            local ok, message = ZM_ClaimService:HandleClaimRequest(owner, 3, 0, 10)
            assert(not ok and message == "Invalid tile.")
            ok, message = ZM_ClaimService:HandleClaimRequest(owner, 0, 0, 10.1)
            assert(not ok and message:find("wait"), message)
            ok, message = ZM_ClaimService:HandleClaimRequest(owner, "0", 0, 11)
            assert(not ok and message == "Invalid tile.")
            ok, message = ZM_ClaimService:HandleClaimRequest(owner, 0, 0, 12)
            assert(ok and message == "Claimed tile 0,0.", message)
            assert(tokens(owner) == 1)
        """)

    def test_adjacent_tile_can_be_claimed(self):
        self.run_lua("""
            local owner = person("STEAM_0:1:100", "owner_a", 0, 0)
            assert(ZM_ClaimService:ClaimTile(owner, 1, 0))
            assert(ZM_GetCellClaims("fixture", 7)[1].tileX == 1)
        """)

    def test_claim_reach_is_inclusive_and_rejects_invalid_positions(self):
        self.run_lua("""
            assert(ZM_ClaimService:IsWithinClaimReach({ x = 960, y = 0 }, 0, 0))
            assert(not ZM_ClaimService:IsWithinClaimReach({ x = 960.01, y = 0 }, 0, 0))
            assert(not ZM_ClaimService:IsWithinClaimReach(nil, 0, 0))
            assert(not ZM_ClaimService:IsWithinClaimReach({ x = 0 }, 0, 0))
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

    def test_exact_row_reads_distinguish_sql_null_from_literal_null(self):
        self.run_lua("""
            local character = "review_owner"
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = character, rows = {
                    { instanceId = "item_null", container = "backpack", slot = 1,
                        itemId = "itemBandage", count = 1, level = 1, mastercraft = 0,
                        clip = 0, createdAt = 10 },
                    { instanceId = "item_json", container = "backpack", slot = 2,
                        itemId = "itemBandage", count = 1, level = 1, mastercraft = 0,
                        attributes = "{}", clip = 0, createdAt = 11 }
                } },
                { kind = "equippedWeaponSlotsExact", steamid = character, rows = {
                    { slot = 1, selected = 0 },
                    { slot = 2, instanceId = "NULL", selected = 0 }
                } }
            }))
            local rawItems = ZM_GetPlayerItems(character, "preview")
            assert(rawItems[1].attributes == "NULL", "GMod exposes SQL NULL as a string")
            local exactItems = ZM_GetExactPlayerItems(character, "preview")
            assert(exactItems[1].attributes == nil and exactItems[2].attributes == "{}")
            local exactSlots = ZM_GetExactEquippedWeaponSlots(character, "preview")
            assert(exactSlots[1].instanceId == nil and exactSlots[2].instanceId == "NULL")
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = character, rows = exactItems },
                { kind = "equippedWeaponSlotsExact", steamid = character, rows = exactSlots }
            }))
            local slots = sql.Query("SELECT slot, instanceId IS NULL AS is_null FROM equipped_weapon_slots ORDER BY slot")
            assert(slots[1].is_null == "1" and slots[2].is_null == "0")

            assert(sql.Query("UPDATE player_items SET attributes = 'NULL' WHERE instanceId = 'item_null'") ~= false)
            exactItems = ZM_GetExactPlayerItems(character, "preview")
            assert(exactItems[1].attributes == "NULL", "literal text must not be changed into SQL NULL")
            local saved, reason = ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = character, rows = exactItems }
            })
            assert(not saved and reason:find("invalid exact player-item attributes", 1, true))
            local after = sql.Query("SELECT attributes, attributes IS NULL AS is_null FROM player_items WHERE instanceId = 'item_null'")
            assert(after[1].attributes == "NULL" and after[1].is_null == "0", "the invalid original stays unchanged")
        """)

    def test_review_cleanup_retains_current_rows_and_restores_displaced_selection(self):
        self.run_lua("""
            SERVER = true
            timer = {
                Create = function(name, seconds, repeats, callback)
                    reviewTimer = { name = name, seconds = seconds, repeats = repeats, callback = callback }
                end,
                Remove = function(name) removedTimer = name end
            }
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            local pistol = { valid = true }
            function pistol:GetItemInstanceId() return "baseline_pistol" end
            function pistol:GetClass() return "weapon_pistol" end
            local weapons = { pistol }
            function owner:GetWeapons() return weapons end
            function owner:StripWeapon(class)
                for _, weapon in ipairs(weapons) do
                    if weapon.valid and weapon:GetClass() == class then weapon.valid = false end
                end
            end
            function owner:SelectWeapon(class) self.selectedWeaponClass = class end
            owner.profile = "preview"
            reviewHumans = { owner }

            local baselineAttributes = '{"a":1,"b":2}'
            assert(ZM_CommitWrites("preview", { {
                kind = "playerItemsExact", steamid = owner.character, rows = {
                    {
                        instanceId = "baseline_bandage", container = "backpack", slot = 1,
                        itemId = "itemBandage", count = 2, level = 1, mastercraft = 0,
                        attributes = baselineAttributes, clip = 0, createdAt = 10
                    },
                    {
                        instanceId = "baseline_pistol", container = "equipped", slot = 1,
                        itemId = "weaponPistol", count = 1, level = 1, mastercraft = 0,
                        clip = 7, createdAt = 11
                    }
                }
            } }))
            assert(ZM_CommitWrites("preview", { {
                kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 1 },
                    { slot = 2, selected = 0 },
                    { slot = 3, selected = 0 }
                }
            } }))
            owner.ZM_Inventory.backpack[1] = {
                instanceId = "baseline_bandage", itemId = "itemBandage", count = 2, level = 1,
                mastercraft = false, attributes = { a = 1, b = 2 }, clip = 0, createdAt = 10
            }
            owner.ZM_Inventory.equipped[1] = {
                instanceId = "baseline_pistol", itemId = "weaponPistol", count = 1, level = 1,
                mastercraft = false, clip = 7, createdAt = 11
            }
            owner.ZM_WeaponSlots[1] = { instanceId = "baseline_pistol", selected = true }
            local now = os.time()
            assert(ZM_CommitWrites("preview", { {
                kind = "claimCreate", steamid = "other_owner", account = "STEAM_0:1:200",
                cellId = 7, tileX = 1, tileY = 0, now = now
            } }))

            local started, message = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(started, message)
            assert(reviewTimer.name == ZM_ClaimReviewTest.TimerName and reviewTimer.seconds == 1800
                and reviewTimer.repeats == 1, "review timeout is a single 30-minute timer")
            assert(message:find("30 minutes", 1, true) and message:find("pieces are removed", 1, true))
            assert(lastInventorySendOptions.skipWeaponSlotNormalization,
                "review refresh must not normalize persisted slots")
            local session = ZM_ClaimReviewTest.Active
            assert(session and session.testIds)
            local tokenId, hammerId
            for id in pairs(session.testIds) do
                local rows = ZM_GetPlayerItems(owner.character, "preview")
                for _, row in ipairs(rows) do
                    if row.instanceId == id then
                        if row.itemId == "itemClaimToken" then tokenId = id end
                        if row.itemId == "weaponMeleeHammer" then hammerId = id end
                    end
                end
            end
            assert(tokenId and hammerId, "both temporary instances were persisted")

            local currentItems = ZM_GetExactPlayerItems(owner.character, "preview")
            for _, row in ipairs(currentItems) do
                if row.instanceId == hammerId then
                    row.container = "equipped"
                    row.slot = 2
                elseif row.instanceId == "baseline_bandage" then
                    row.attributes = '{"b":2,"a":1}'
                end
            end
            owner.ZM_Inventory.backpack[session.tempSlots[2]] = nil
            owner.ZM_Inventory.equipped[2] = session.tempInstances[hammerId]
            owner.ZM_WeaponSlots[1] = { instanceId = "baseline_pistol", selected = false }
            owner.ZM_WeaponSlots[2] = { instanceId = hammerId, selected = true }
            local hammer = { valid = true }
            function hammer:GetItemInstanceId() return hammerId end
            function hammer:GetClass() return "weapon_zn_hammer" end
            weapons[#weapons + 1] = hammer
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = currentItems },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 0 },
                    { slot = 2, instanceId = hammerId, selected = 1 },
                    { slot = 3, selected = 0 }
                } }
            }))
            assert(ZM_CommitWrites("preview", { {
                kind = "claimCreate", steamid = owner.character, account = owner:SteamID(),
                cellId = 7, tileX = 0, tileY = 0, now = os.time()
            } }))

            local entity = { valid = true, ZM_ClaimReviewSessionId = session.id }
            function entity:Remove() self.valid = false end
            local unrelatedEntity = { valid = true, ZM_ClaimReviewSessionId = "other_session" }
            function unrelatedEntity:Remove() self.valid = false end
            reviewEntities = { entity, unrelatedEntity }
            pistol.valid = false
            local rolledBack, rollbackMessage = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(not rolledBack and rollbackMessage:find("selected weapon", 1, true))
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 4, "failed cleanup preserves temporary rows")
            assert(#ZM_GetCellClaims("preview", 7) == 2, "failed cleanup preserves the review claim")
            pistol.valid = true
            rolledBack, rollbackMessage = ZM_ClaimReviewTest:Rollback(owner, "fixture-retry")
            assert(rolledBack, rollbackMessage)

            local restoredItems = ZM_GetPlayerItems(owner.character, "preview")
            local restoredById = {}
            for _, row in ipairs(restoredItems) do restoredById[row.instanceId] = row end
            assert(#restoredItems == 2 and restoredById.baseline_bandage and restoredById.baseline_pistol)
            assert(restoredById.baseline_bandage.attributes == '{"b":2,"a":1}',
                "current raw attribute JSON is retained")
            local restoredSlots = ZM_GetEquippedWeaponSlots(owner.character, "preview")
            assert(#restoredSlots == 3 and restoredSlots[1].instanceId == "baseline_pistol"
                and tonumber(restoredSlots[1].selected) == 1)
            assert(owner.ZM_Inventory.backpack[1].instanceId == "baseline_bandage")
            assert(owner.ZM_Inventory.equipped[1].instanceId == "baseline_pistol")
            assert(owner.ZM_WeaponSlots[1].instanceId == "baseline_pistol"
                and owner.ZM_WeaponSlots[1].selected)
            assert(owner.selectedWeaponClass == "weapon_pistol", "the original live weapon is selected again")
            assert(pistol.valid and not hammer.valid, "only the temporary weapon is stripped")
            for _, container in pairs({ owner.ZM_Inventory.backpack, owner.ZM_Inventory.equipped }) do
                for _, instance in pairs(container) do assert(not session.testIds[instance.instanceId]) end
            end
            local claims = ZM_GetCellClaims("preview", 7)
            assert(#claims == 1 and claims[1].owner == "other_owner", "only the test claim is deleted")
            assert(not entity.valid and unrelatedEntity.valid and owner.ZM_ClaimReviewSessionId == nil)
            assert(ZM_ClaimReviewTest.Active == nil)
            assert(removedTimer == ZM_ClaimReviewTest.TimerName, "manual cleanup cancels the review timer")
        """)

    def test_review_cleanup_preserves_unrelated_items_claims_and_profiles(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            function owner:GetWeapons() return {} end
            function owner:StripWeapon() end
            owner.profile = "preview"
            reviewHumans = { owner }

            local started, message = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(started, message)
            local session = ZM_ClaimReviewTest.Active
            local currentItems = ZM_GetExactPlayerItems(owner.character, "preview")
            currentItems[#currentItems + 1] = {
                instanceId = "unexpected_item", container = "backpack", slot = 50,
                itemId = "itemBandage", count = 3, level = 1, mastercraft = 0,
                attributes = '{"a":1,"b":2}', clip = 0, createdAt = 20
            }
            owner.ZM_Inventory.backpack[50] = {
                instanceId = "unexpected_item", itemId = "itemBandage", count = 3, level = 1,
                mastercraft = false, attributes = { a = 1, b = 2 }, clip = 0, createdAt = 20
            }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = currentItems },
                { kind = "claimCreate", steamid = owner.character, account = owner:SteamID(),
                    cellId = 7, tileX = 0, tileY = 0, now = os.time() },
                { kind = "claimCreate", steamid = "other_owner", account = "STEAM_0:1:200",
                    cellId = 7, tileX = 1, tileY = 0, now = os.time() }
            }))
            assert(ZM_CommitWrites("city", {
                { kind = "playerItemsExact", steamid = owner.character, rows = {
                    { instanceId = "city_item", container = "backpack", slot = 1,
                        itemId = "itemBandage", count = 4, level = 1, mastercraft = 0,
                        clip = 0, createdAt = 21 }
                } }
            }))

            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(rolledBack, reason)
            local retained = ZM_GetExactPlayerItems(owner.character, "preview")
            assert(#retained == 1 and retained[1].instanceId == "unexpected_item"
                and tonumber(retained[1].count) == 3 and retained[1].attributes == '{"a":1,"b":2}')
            assert(owner.ZM_Inventory.backpack[50].instanceId == "unexpected_item")
            for _, instance in pairs(owner.ZM_Inventory.backpack) do assert(not session.testIds[instance.instanceId]) end
            local claims = ZM_GetCellClaims("preview", 7)
            assert(#claims == 1 and claims[1].owner == "other_owner" and claims[1].tileX == 1)
            local cityItems = ZM_GetExactPlayerItems(owner.character, "city")
            assert(#cityItems == 1 and cityItems[1].instanceId == "city_item" and tonumber(cityItems[1].count) == 4)
            assert(ZM_ClaimReviewTest.Active == nil)
        """)

    def test_review_cleanup_refuses_a_replaced_claim_on_the_review_tile(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            function owner:GetWeapons() return {} end
            function owner:StripWeapon() end
            owner.profile = "preview"
            reviewHumans = { owner }

            assert(ZM_ClaimReviewTest:Start(owner, 0, 0))
            local session = ZM_ClaimReviewTest.Active
            assert(ZM_CommitWrites("preview", { {
                kind = "claimCreate", steamid = "other_owner", account = "STEAM_0:1:200",
                cellId = 7, tileX = 0, tileY = 0, now = os.time()
            } }))
            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(not rolledBack and reason:find("does not match this session", 1, true))
            assert(ZM_ClaimReviewTest.Active == session)
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 2)
            local claims = ZM_GetCellClaims("preview", 7)
            assert(#claims == 1 and claims[1].owner == "other_owner")
        """)

    def test_review_cleanup_preserves_changed_weapon_selection(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            local pistol = { valid = true }
            function pistol:GetItemInstanceId() return "baseline_pistol" end
            function pistol:GetClass() return "weapon_pistol" end
            local rifle = { valid = true }
            function rifle:GetItemInstanceId() return "other_rifle" end
            function rifle:GetClass() return "weapon_rifle" end
            function owner:GetWeapons() return { pistol, rifle } end
            function owner:StripWeapon() end
            function owner:SelectWeapon(class) self.selectedWeaponClass = class end
            owner.profile = "preview"
            owner.ZM_Inventory.equipped[1] = {
                instanceId = "baseline_pistol", itemId = "weaponPistol", count = 1, level = 1,
                mastercraft = false, clip = 7, createdAt = 11
            }
            owner.ZM_Inventory.equipped[2] = {
                instanceId = "other_rifle", itemId = "weaponRifle", count = 1, level = 1,
                mastercraft = false, clip = 3, createdAt = 12
            }
            owner.ZM_WeaponSlots[1] = { instanceId = "baseline_pistol", selected = true }
            owner.ZM_WeaponSlots[2] = { instanceId = "other_rifle", selected = false }
            reviewHumans = { owner }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = {
                    { instanceId = "baseline_pistol", container = "equipped", slot = 1,
                        itemId = "weaponPistol", count = 1, level = 1, mastercraft = 0,
                        clip = 7, createdAt = 11 },
                    { instanceId = "other_rifle", container = "equipped", slot = 2,
                        itemId = "weaponRifle", count = 1, level = 1, mastercraft = 0,
                        clip = 3, createdAt = 12 }
                } },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 1 },
                    { slot = 2, instanceId = "other_rifle", selected = 0 }
                } }
            }))
            local started, message = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(started, message)
            owner.ZM_WeaponSlots[1].selected = false
            owner.ZM_WeaponSlots[2].selected = true
            assert(ZM_CommitWrites("preview", {
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 0 },
                    { slot = 2, instanceId = "other_rifle", selected = 1 }
                } }
            }))

            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(rolledBack, reason)
            local slots = ZM_GetExactEquippedWeaponSlots(owner.character, "preview")
            assert(#slots == 2 and tonumber(slots[1].selected) == 0
                and slots[2].instanceId == "other_rifle" and tonumber(slots[2].selected) == 1)
            assert(owner.ZM_WeaponSlots[2].selected and owner.selectedWeaponClass == "weapon_rifle")
        """)

    def test_review_cleanup_preserves_a_weapon_moved_out_of_the_hammer_slot(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            local pistol = { valid = true }
            function pistol:GetItemInstanceId() return "baseline_pistol" end
            function pistol:GetClass() return "weapon_pistol" end
            local weapons = { pistol }
            function owner:GetWeapons() return weapons end
            function owner:StripWeapon(class)
                for _, weapon in ipairs(weapons) do
                    if weapon.valid and weapon:GetClass() == class then weapon.valid = false end
                end
            end
            function owner:SelectWeapon(class) self.selectedWeaponClass = class end
            owner.profile = "preview"
            owner.ZM_Inventory.equipped[1] = {
                instanceId = "baseline_pistol", itemId = "weaponPistol", count = 1, level = 1,
                mastercraft = false, clip = 7, createdAt = 11
            }
            owner.ZM_WeaponSlots[1] = { instanceId = "baseline_pistol", selected = true }
            reviewHumans = { owner }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = {
                    { instanceId = "baseline_pistol", container = "equipped", slot = 1,
                        itemId = "weaponPistol", count = 1, level = 1, mastercraft = 0,
                        clip = 7, createdAt = 11 }
                } },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 1 }
                } }
            }))
            assert(ZM_ClaimReviewTest:Start(owner, 0, 0))
            local session = ZM_ClaimReviewTest.Active
            local items = ZM_GetExactPlayerItems(owner.character, "preview")
            for _, row in ipairs(items) do
                if row.instanceId == "baseline_pistol" then
                    row.container, row.slot = "backpack", 10
                elseif row.instanceId == session.hammerId then
                    row.container, row.slot = "equipped", 1
                end
            end
            owner.ZM_Inventory.backpack[10] = owner.ZM_Inventory.equipped[1]
            owner.ZM_Inventory.backpack[session.tempSlots[2]] = nil
            owner.ZM_Inventory.equipped[1] = session.tempInstances[session.hammerId]
            owner.ZM_WeaponSlots[1] = { instanceId = session.hammerId, selected = true }
            pistol.valid = false
            local hammer = { valid = true }
            function hammer:GetItemInstanceId() return session.hammerId end
            function hammer:GetClass() return "weapon_zn_hammer" end
            weapons = { hammer }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = items },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = session.hammerId, selected = 1 }
                } }
            }))
            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(rolledBack, reason)
            local retained = ZM_GetExactPlayerItems(owner.character, "preview")
            assert(#retained == 1 and retained[1].instanceId == "baseline_pistol"
                and retained[1].container == "backpack" and tonumber(retained[1].slot) == 10)
            local slots = ZM_GetExactEquippedWeaponSlots(owner.character, "preview")
            assert(#slots == 1 and slots[1].instanceId == nil and tonumber(slots[1].selected) == 0)
            assert(owner.ZM_Inventory.backpack[10].instanceId == "baseline_pistol")
            assert(not hammer.valid and owner.selectedWeaponClass == nil)
        """)

    def test_review_cleanup_rejects_multiple_selected_weapons(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            function owner:GetWeapons() return {} end
            function owner:StripWeapon() end
            owner.profile = "preview"
            reviewHumans = { owner }
            assert(ZM_ClaimReviewTest:Start(owner, 0, 0))
            local session = ZM_ClaimReviewTest.Active
            assert(ZM_CommitWrites("preview", {
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "other_pistol", selected = 1 },
                    { slot = 2, instanceId = session.hammerId, selected = 1 }
                } }
            }))
            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(not rolledBack and reason:find("multiple selections", 1, true))
            assert(ZM_ClaimReviewTest.Active == session)
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 2)
            assert(#ZM_GetExactEquippedWeaponSlots(owner.character, "preview") == 2)
        """)

    def test_review_disconnect_restores_selected_slot_without_a_live_weapon(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            local pistol = { valid = true }
            function pistol:GetItemInstanceId() return "baseline_pistol" end
            function pistol:GetClass() return "weapon_pistol" end
            function owner:GetWeapons() return { pistol } end
            owner.profile = "preview"
            reviewHumans = { owner }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = {
                    { instanceId = "baseline_pistol", container = "equipped", slot = 1,
                        itemId = "weaponPistol", count = 1, level = 1, mastercraft = 0,
                        clip = 7, createdAt = 11 }
                } },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 1 }
                } }
            }))
            assert(ZM_ClaimReviewTest:Start(owner, 0, 0))
            local session = ZM_ClaimReviewTest.Active
            local items = ZM_GetExactPlayerItems(owner.character, "preview")
            for _, row in ipairs(items) do
                if row.instanceId == session.hammerId then
                    row.container = "equipped"
                    row.slot = 2
                end
            end
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = items },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 0 },
                    { slot = 2, instanceId = session.hammerId, selected = 1 }
                } },
                { kind = "claimCreate", steamid = owner.character, account = owner:SteamID(),
                    cellId = 7, tileX = 0, tileY = 0, now = os.time() }
            }))
            pistol.valid = false

            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(nil, "disconnect")
            assert(rolledBack, reason)
            local restoredItems = ZM_GetPlayerItems(owner.character, "preview")
            local restoredSlots = ZM_GetExactEquippedWeaponSlots(owner.character, "preview")
            assert(#restoredItems == 1 and restoredItems[1].instanceId == "baseline_pistol")
            assert(#restoredSlots == 2 and restoredSlots[1].instanceId == "baseline_pistol"
                and tonumber(restoredSlots[1].selected) == 1 and restoredSlots[2].instanceId == nil)
            assert(#ZM_GetCellClaims("preview", 7) == 0)
            assert(ZM_ClaimReviewTest.Active == nil)
        """)

    def test_review_refuses_unusable_hammer_before_granting_items(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return self.level end
            owner.profile = "preview"
            owner.level = 1
            owner.strength = 5
            reviewHumans = { owner }

            local started, reason = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(not started and reason:find("Requires player level 8", 1, true), tostring(reason))
            owner.level = 20
            owner.strength = 4
            started, reason = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(not started and reason:find("Requires Strength 5", 1, true), tostring(reason))
            assert(ZM_ClaimReviewTest.Active == nil)
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 0)
            assert(#ZM_GetCellClaims("preview", 7) == 0)
        """)

    def test_review_refuses_missing_selected_weapon_before_granting_items(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            function owner:GetWeapons() return {} end
            owner.profile = "preview"
            reviewHumans = { owner }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = {
                    { instanceId = "baseline_pistol", container = "equipped", slot = 1,
                        itemId = "weaponPistol", count = 1, level = 1, mastercraft = 0,
                        clip = 7, createdAt = 11 }
                } },
                { kind = "equippedWeaponSlotsExact", steamid = owner.character, rows = {
                    { slot = 1, instanceId = "baseline_pistol", selected = 1 }
                } }
            }))

            local started, reason = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(not started and reason:find("selected weapon", 1, true), tostring(reason))
            assert(ZM_ClaimReviewTest.Active == nil)
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 1)
            assert(#ZM_GetCellClaims("preview", 7) == 0)
        """)

    def test_review_refuses_radiation_before_granting_items(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            reviewRadiation = 0.5
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 1 end
            owner.profile = "preview"
            reviewHumans = { owner }

            local started, reason = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(not started and reason:find("zero-radiation", 1, true))
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 0)
            assert(#ZM_GetCellClaims("preview", 7) == 0)
        """)

    def test_review_refuses_out_of_reach_tile_before_granting_items(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner", -640, 0)
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 1 end
            owner.profile = "preview"
            reviewHumans = { owner }

            local started, reason = ZM_ClaimReviewTest:Start(owner, 1, 0)
            assert(not started and reason:find("Move closer", 1, true))
            assert(ZM_ClaimReviewTest.Active == nil)
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 0)
            assert(#ZM_GetCellClaims("preview", 7) == 0)
        """)

    def test_claim_review_status_reports_loaded_world_index_without_writes(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsAdmin() return true end
            reviewHumans = { owner }

            local reported, reason = ZM_DevConsole.DirectCommands.zombiesim_dev_claim_review_status("7")
            assert(reported, tostring(reason))
            assert(lastDevReport.name == "claimConstructionReview")
            local details = lastDevReport.data
            assert(details.state == "status" and details.profile == "preview")
            assert(details.worldDataPath == "data_static/zombiesim_world_fixture.json")
            assert(details.cellId == 7 and details.map == "zz_cell_a")
            assert(#details.claimTiles == 3)
            assert(#ZM_GetCellClaims("preview", 7) == 0)
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 0)
        """)

    def test_review_rollback_transaction_failure_preserves_all_rows(self):
        self.run_lua("""
            ZM_World.ActiveProfile = "preview"
            local owner = person("STEAM_0:1:100", "review_owner")
            function owner:IsPlayer() return true end
            function owner:IsAdmin() return true end
            function owner:Alive() return true end
            function owner:Health() return 100 end
            function owner:GetMaxHealth() return 100 end
            function owner:GetLevel() return 20 end
            function owner:GetWeapons() return {} end
            function owner:StripWeapon() end
            owner.profile = "preview"
            reviewHumans = { owner }

            local started, message = ZM_ClaimReviewTest:Start(owner, 0, 0)
            assert(started, message)
            local session = ZM_ClaimReviewTest.Active
            local items = ZM_GetExactPlayerItems(owner.character, "preview")
            items[#items + 1] = {
                instanceId = "retained_item", container = "backpack", slot = 50,
                itemId = "itemBandage", count = 2, level = 1, mastercraft = 0,
                clip = 0, createdAt = 22
            }
            owner.ZM_Inventory.backpack[50] = {
                instanceId = "retained_item", itemId = "itemBandage", count = 2, level = 1,
                mastercraft = false, clip = 0, createdAt = 22
            }
            assert(ZM_CommitWrites("preview", {
                { kind = "playerItemsExact", steamid = owner.character, rows = items },
                { kind = "claimCreate", steamid = owner.character, account = owner:SteamID(),
                    cellId = 7, tileX = 0, tileY = 0, now = os.time() },
                { kind = "claimCreate", steamid = "other_owner", account = "STEAM_0:1:200",
                    cellId = 7, tileX = 1, tileY = 0, now = os.time() }
            }))
            assert(ZM_CommitWrites("city", { {
                kind = "playerItemsExact", steamid = owner.character, rows = {
                    { instanceId = "city_item", container = "backpack", slot = 1,
                        itemId = "itemBandage", count = 4, level = 1, mastercraft = 0,
                        clip = 0, createdAt = 21 }
                }
            } }))
            assert(sql.Query([[
                CREATE TRIGGER reject_review_claim_delete BEFORE DELETE ON player_claims
                BEGIN SELECT RAISE(ABORT, 'injected claim-delete failure'); END
            ]]) ~= false)

            local rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture")
            assert(not rolledBack and reason:find("injected claim-delete failure", 1, true), tostring(reason))
            assert(ZM_ClaimReviewTest.Active == session, "failed rollback remains available for retry")
            assert(#ZM_GetPlayerItems(owner.character, "preview") == 3, "all item rows survive transaction rollback")
            assert(#ZM_GetCellClaims("preview", 7) == 2, "both claims survive transaction rollback")
            assert(owner.ZM_Inventory.backpack[50].instanceId == "retained_item")
            assert(#ZM_GetPlayerItems(owner.character, "city") == 1, "other profile is unchanged")

            assert(sql.Query("DROP TRIGGER reject_review_claim_delete") ~= false)
            rolledBack, reason = ZM_ClaimReviewTest:Rollback(owner, "fixture-retry")
            assert(rolledBack, reason)
            assert(ZM_ClaimReviewTest.Active == nil)
            local retained = ZM_GetPlayerItems(owner.character, "preview")
            assert(#retained == 1 and retained[1].instanceId == "retained_item" and tonumber(retained[1].count) == 2)
            local claims = ZM_GetCellClaims("preview", 7)
            assert(#claims == 1 and claims[1].owner == "other_owner")
            assert(#ZM_GetPlayerItems(owner.character, "city") == 1)
        """)


if __name__ == "__main__":
    unittest.main()
