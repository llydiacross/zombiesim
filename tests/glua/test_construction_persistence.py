"""Offline construction persistence fixtures (Alpha 3.5): real sql.lua writers on SQLite with construction fakes."""

import sqlite3
import unittest

import tests.glua.test_construction as construction_fixtures


LIFETIME = 30 * 24 * 60 * 60


class ConstructionPersistenceTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.last_error = None

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

        def prepare(runner):
            runner.lua.globals().py_query = query
            runner.lua.globals().py_last_error = lambda: self.last_error

        runner = construction_fixtures.make_construction_runner(["utils/sql.lua"], prepare)
        lua = self.lua = runner.lua
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
            ZM_Util = {
                ProfileFor = function(target) return target.profile end,
                CharacterKeyFor = function(target) return target.character end
            }
        """)
        runner.load("utils/sql.lua")
        construction_fixtures.ConstructionTests.install_placement_mocks(self)
        lua.execute("""
            assert(ZM_CreateClaimTables())
            assert(ZM_CreateConstructionTables())
            ZM_Construction.StorageReady = true
            failNextSave = false
            -- Commits extraSteps with the inventory change, like the real service; failNextSave fails the transaction.
            ZM_InventoryService.Mutate = function(_, target, callback, options)
                mutations = mutations + 1
                local draft = {}
                for key, value in pairs(backpack) do draft[key] = value end
                local ok, reason = callback(draft)
                if not ok then return false, reason end
                local steps = options and options.extraSteps and options.extraSteps(draft) or {}
                if failNextSave then
                    failNextSave = false
                    steps[#steps + 1] = { kind = "noSuchWriter", steamid = "x" }
                end
                if #steps > 0 then
                    local saved, saveError = ZM_CommitWrites(target.profile, steps)
                    if not saved then return false, saveError end
                end
                backpack = draft
                return true
            end
            ZM_ClaimService.Identity = function(_, target)
                return { character = target.character, account = target.account, profile = target.profile }
            end
            ZM_ClaimService.CurrentCell = function() return { id = 7 } end
            local meta = getmetatable(Vector(0, 0, 0))
            meta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
            net.WriteVector = function() end
            net.WriteNormal = function() end
            net.SendPVS = function() end
            sound = { Play = function() end }
            COLLISION_GROUP_DEBRIS = 1
            function AngleRand() return {} end
            function VectorRand() return Vector(0, 0, 0) end
            math.Rand = function(low) return low end
            function SafeRemoveEntityDelayed() end
            local createPiece = ents.Create
            ents.Create = function(class)
                if class ~= "prop_physics" then return createPiece(class) end
                local gib = { valid = true }
                function gib:SetModel() end
                function gib:SetPos() end
                function gib:SetAngles() end
                function gib:Spawn() end
                function gib:SetCollisionGroup() end
                function gib:GetPhysicsObject() return nil end
                return gib
            end

            function persistedBuilder(character, profile)
                local builder = makeBuilder()
                builder.character = character or "char_a"
                builder.account = "STEAM_0:1:100"
                builder.profile = profile or "preview"
                return builder
            end
            function rows(profile, cellId)
                return assert(ZM_GetCellConstructionPieces(profile or "preview", cellId or 7))
            end
            function payAndComplete(builder, piece)
                builder.weapon.level = 30
                local tick = 100
                while not piece.complete and tick < 120 do
                    ZM_Construction:Contribute(builder, piece, tick)
                    tick = tick + 0.25
                end
                assert(piece.complete, "piece did not complete")
            end
        """)

    def test_blueprint_build_and_damage_round_trip_through_a_cell_reload(self):
        lua = self.lua
        lua.execute("""
            builder = persistedBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            blueprintRows = rows()
            blueprint = blueprintRows[1]
            payAndComplete(builder, piece)
            builtRow = rows()[1]
            maxHealth = ZM_Construction.MaxHealth(piece:GetPieceKind())
            ZM_Construction:DamagePiece(piece, 40, makeZombie(), Vector(0, 0, 8), Vector(0, 1, 0))
            dirtyBeforeFlush = rows()[1].health
            flushed = ZM_Construction:FlushDirty()
            damagedRow = rows()[1]
            wearBefore = piece:GetWear()
            slotKey, kind, yaw, pos = piece.ZM_SlotKey, piece:GetPieceKind(), piece:GetPieceYaw(), piece:GetPos()

            ZM_Construction:UnloadCell()
            unloadedValid = piece.valid
            unloadedSlot = ZM_Construction:PieceAtSlot(slotKey)
            rowsAfterUnload = #rows()
            createdBefore = #created
            restored, restoredCount = ZM_Construction:RestoreCell("preview", 7)
            again, againCount = ZM_Construction:RestoreCell("preview", 7)
            copy = created[createdBefore + 1]
            copySlot = ZM_Construction:PieceAtSlot(slotKey) == copy
            copyCost = ZM_Construction.EncodeCost(copy.ZM_PaidCost)
            copyHealth = ZM_Construction:PieceHealth(copy)
            ownsCopy = ZM_Construction:OwnsPiece(builder, copy)
            strangerOwns = ZM_Construction:OwnsPiece(persistedBuilder("char_b"), copy)
        """)
        g = lua.globals()
        self.assertEqual(len(g.blueprintRows), 1)
        self.assertEqual(g.blueprint["owner"], "char_a")
        self.assertFalse(g.blueprint["paid"])
        self.assertFalse(g.blueprint["complete"])
        self.assertEqual(g.blueprint["tiles"], ",0:0,")
        self.assertTrue(g.builtRow["paid"])
        self.assertTrue(g.builtRow["complete"])
        self.assertEqual(g.builtRow["paidCost"], "itemScrapMetal:2,itemWood:4")
        self.assertEqual(g.builtRow["health"], g.maxHealth)
        # Damage is written by the timed flush, not per hit.
        self.assertEqual(g.dirtyBeforeFlush, g.maxHealth)
        self.assertTrue(g.flushed)
        self.assertEqual(g.damagedRow["health"], g.maxHealth - 40)
        # Unloading despawns without deleting; restoring recreates the same piece once.
        self.assertFalse(g.unloadedValid)
        self.assertIsNone(g.unloadedSlot)
        self.assertEqual(g.rowsAfterUnload, 1)
        self.assertTrue(g.restored)
        self.assertEqual(g.restoredCount, 1)
        self.assertTrue(g.again)
        self.assertEqual(g.againCount, 0)
        copy = g.copy
        self.assertTrue(g.copySlot)
        self.assertEqual(copy.kind, g.kind)
        self.assertEqual(copy.yaw, g.yaw)
        self.assertEqual((copy.pos.x, copy.pos.y, copy.pos.z), (g.pos.x, g.pos.y, g.pos.z))
        self.assertTrue(copy.paid)
        self.assertTrue(copy.complete)
        self.assertEqual(copy.progress, 1)
        self.assertEqual(g.copyCost, "itemScrapMetal:2,itemWood:4")
        self.assertEqual(g.copyHealth, g.maxHealth - 40)
        self.assertAlmostEqual(copy.wear, g.wearBefore)
        self.assertTrue(g.ownsCopy)
        self.assertFalse(g.strangerOwns)

    def test_removal_refunds_and_deletes_in_one_transaction(self):
        lua = self.lua
        lua.execute("""
            builder = persistedBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            payAndComplete(builder, piece)
            woodPaid = backpack.itemWood
            failNextSave = true
            _, removedOnFailure, failureReason = ZM_Construction:RemoveOwnedPiece(builder, piece)
            rowsAfterFailure = #rows()
            validAfterFailure = piece.valid
            woodAfterFailure = backpack.itemWood
            _, removed = ZM_Construction:RemoveOwnedPiece(builder, piece)
            rowsAfterRemoval = #rows()
            validAfterRemoval = piece.valid
            woodAfterRemoval = backpack.itemWood

            -- An unpaid blueprint has nothing to refund; its row is deleted directly.
            aimTrace.HitPos = Vector(200, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            blueprint = created[#created]
            blueprintRows = #rows()
            _, blueprintRemoved = ZM_Construction:RemoveOwnedPiece(builder, blueprint)
            rowsAfterUndo = #rows()
        """)
        g = lua.globals()
        self.assertFalse(g.removedOnFailure)
        self.assertEqual(g.rowsAfterFailure, 1)
        self.assertTrue(g.validAfterFailure)
        self.assertEqual(g.woodAfterFailure, g.woodPaid)
        self.assertTrue(g.removed)
        self.assertEqual(g.rowsAfterRemoval, 0)
        self.assertFalse(g.validAfterRemoval)
        self.assertEqual(g.woodAfterRemoval, g.woodPaid + 4)
        self.assertEqual(g.blueprintRows, 1)
        self.assertTrue(g.blueprintRemoved)
        self.assertEqual(g.rowsAfterUndo, 0)

    def test_payment_write_failure_keeps_items_and_the_unpaid_row(self):
        lua = self.lua
        lua.execute("""
            builder = persistedBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            failNextSave = true
            started = ZM_Construction:Contribute(builder, piece, 100)
            row = rows()[1]
        """)
        g = lua.globals()
        self.assertFalse(g.started)
        self.assertFalse(g.piece.paid)
        self.assertEqual(g.backpack["itemWood"], 10)
        self.assertFalse(g.row["paid"])
        self.assertEqual(g.row["paidCost"], "")

    def test_placement_save_failure_removes_the_blueprint(self):
        lua = self.lua
        lua.execute("""
            builder = persistedBuilder()
            builder.account = ""
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            message = builder.messages[#builder.messages]
            slotFree = ZM_Construction:PieceAtSlot(piece.ZM_SlotKey) == nil
            rowCount = #rows()
        """)
        g = lua.globals()
        self.assertFalse(g.piece.valid)
        self.assertTrue(g.slotFree)
        self.assertEqual(g.rowCount, 0)
        self.assertIn("Could not save the blueprint", g.message)

    def test_pieces_are_isolated_by_profile_and_cell(self):
        lua = self.lua
        lua.execute("""
            builder = persistedBuilder("char_a", "preview")
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            ZM_Construction:UnloadCell()
            cityOk, cityCount = ZM_Construction:RestoreCell("city", 7)
            otherCellOk, otherCellCount = ZM_Construction:RestoreCell("preview", 8)
            previewOk, previewCount = ZM_Construction:RestoreCell("preview", 7)
            cityRows, otherCellRows = #rows("city", 7), #rows("preview", 8)
        """)
        g = lua.globals()
        self.assertEqual((g.cityOk, g.cityCount), (True, 0))
        self.assertEqual((g.otherCellOk, g.otherCellCount), (True, 0))
        self.assertEqual((g.previewOk, g.previewCount), (True, 1))
        self.assertEqual((g.cityRows, g.otherCellRows), (0, 0))

    def test_broken_pieces_delete_their_row(self):
        lua = self.lua
        lua.execute("""
            builder = persistedBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            payAndComplete(builder, piece)
            broke = ZM_Construction:DamagePiece(piece, 1000000, makeZombie(), Vector(0, 0, 8), Vector(0, 1, 0))
            rowCount = #rows()
            flushed = ZM_Construction:FlushDirty()
            rowCountAfterFlush = #rows()
        """)
        g = lua.globals()
        self.assertTrue(g.broke)
        self.assertFalse(g.piece.valid)
        self.assertEqual(g.rowCount, 0)
        # A pending damage flush must not resurrect the broken piece's row.
        self.assertTrue(g.flushed)
        self.assertEqual(g.rowCountAfterFlush, 0)

    def test_lapsed_claim_keeps_pieces_for_owner_and_clears_them_for_a_new_owner(self):
        lua = self.lua
        lua.execute(f"""
            builder = persistedBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            aimTrace.HitPos = Vector(1280, 10, 0)
            claims = {{ {{ tileX = 0, tileY = 0, active = true, access = true }},
                        {{ tileX = 2, tileY = 0, active = true, access = true }} }}
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            beforeCount = #rows()
            local old, now = 1000000000, 1000000000 + {LIFETIME} + 100
            local function claim(owner, account, tileX, at)
                return ZM_CommitWrites("preview", {{ {{ kind = "claimCreate", steamid = owner, account = account,
                    cellId = 7, tileX = tileX, tileY = 0, now = at }} }})
            end
            assert(claim("char_a", "STEAM_0:1:100", 0, old))
            assert(claim("char_a", "STEAM_0:1:100", 2, old))
            ownerReclaim = claim("char_a", "STEAM_0:1:100", 2, now)
            afterOwner = #rows()
            strangerReclaim = claim("char_b", "STEAM_0:1:200", 0, now)
            remaining = rows()
            otherProfileUntouched = #rows("city", 7)
        """)
        g = lua.globals()
        self.assertEqual(g.beforeCount, 2)
        self.assertTrue(g.ownerReclaim)
        self.assertEqual(g.afterOwner, 2)
        self.assertTrue(g.strangerReclaim)
        self.assertEqual(len(g.remaining), 1)
        self.assertEqual(g.remaining[1]["tiles"], ",2:0,")
        self.assertEqual(g.otherProfileUntouched, 0)


if __name__ == "__main__":
    unittest.main()
