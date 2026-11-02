"""Offline construction fixtures (Alpha 3.4 Phase E): Hammer build rules, eligibility and non-interaction."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class ConstructionTests(unittest.TestCase):
    def setUp(self):
        runner = FixtureRunner(ROOT, ["sh_construction.lua", "sv_construction.lua"])
        lua = self.lua = runner.lua
        lua.execute("""
            now = 100
            function CurTime() return now end
            HUD_PRINTCENTER = 4
            math.Clamp = function(value, low, high) return math.min(math.max(value, low), high) end
            function IsValid(value) return value ~= nil and value.valid == true end
            hooks = {}
            hook = { Add = function(event, name, callback) hooks[event .. "/" .. name] = callback end }
            humans = {}
            player = { GetHumans = function() return humans end }
            networkStrings = {}
            util = { AddNetworkString = function(name) networkStrings[name] = true end }
            sent = {}
            local current
            net = {
                Start = function(name) current = { name = name, values = {} } end,
                WriteUInt = function(value) table.insert(current.values, value) end,
                WriteInt = function(value) table.insert(current.values, value) end,
                Send = function(target) current.target = target; table.insert(sent, current) end,
            }
            ZM_Items = { GetDefinition = function(_, id)
                if id == "weaponMeleeHammer" then return { minLevel = 8, maxLevel = 30 } end
            end }
            ZM_World = { GetCellBounds = function() return { tileSize = 640 } end }
            claims = {}
            ZM_ClaimService = { StorageReady = true, CellSnapshot = function(_, target)
                if target.noCell then return nil, "Claims are only available in city cells." end
                return { cellId = 7, claimable = {}, claims = claims }
            end }

            function makeWeapon(class)
                local weapon = { valid = true, class = class, build = false }
                function weapon:GetClass() return self.class end
                function weapon:GetBuildMode() return self.build end
                function weapon:SetBuildMode(value) self.build = value end
                return weapon
            end
            function makePlayer(x, y)
                local target = { valid = true, alive = true, pos = { x = x, y = y, z = 0 }, messages = {} }
                target.weapon = makeWeapon("weapon_zn_hammer")
                function target:IsPlayer() return true end
                function target:Alive() return self.alive end
                function target:GetPos() return self.pos end
                function target:GetActiveWeapon() return self.weapon end
                function target:PrintMessage(_, message) self.messages[#self.messages + 1] = message end
                return target
            end
            function makeZombie()
                local zombie = { valid = true }
                function zombie:GetClass() return "zn_walker_zombie" end
                function zombie:IsPlayer() return false end
                return zombie
            end
        """)
        runner.load("sh_construction.lua")
        runner.load("sv_construction.lua")
        self.construction = lua.globals().ZM_Construction

    def test_build_speed_scales_linearly_with_hammer_level(self):
        speed = self.construction.BuildSpeed
        self.assertEqual(speed(8, 8, 30), 1)
        self.assertEqual(speed(30, 8, 30), 2)
        self.assertAlmostEqual(speed(19, 8, 30), 1.5)
        self.assertEqual(speed(1, 8, 30), 1)
        self.assertEqual(speed(99, 8, 30), 2)
        self.assertAlmostEqual(self.lua.eval("ZM_Construction:BuildSeconds('foundation', 30)"), 3)
        self.assertIsNone(self.lua.eval("ZM_Construction:BuildSeconds('roof', 30)"))

    def test_mastercraft_halves_costs_rounded_up_to_one(self):
        cost = self.construction.MaterialCost
        self.assertEqual(dict(cost("foundation", False)), {"itemWood": 4, "itemScrapMetal": 2})
        self.assertEqual(dict(cost("foundation", True)), {"itemWood": 2, "itemScrapMetal": 1})
        self.assertEqual(dict(cost("wall", True)), {"itemWood": 2, "itemScrapMetal": 1})
        # Halving leaves the definition untouched.
        self.assertEqual(dict(cost("wall", False)), {"itemWood": 3, "itemScrapMetal": 1})
        self.assertIsNone(cost("roof", True))

    def test_toggle_requires_accessible_active_claim_within_margin(self):
        lua = self.lua
        lua.execute("""
            builder = makePlayer(0, 0)
            claims = { { tileX = 1, tileY = 0, active = true, access = false } }
            result1 = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            claims = { { tileX = 1, tileY = 0, active = false, access = true } }
            result2 = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            claims = { { tileX = -2, tileY = 2, active = true, access = true } }
            builder.pos = { x = 1500, y = 0, z = 0 }
            result3 = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            -- Tile (-2,2) square reaches x=-960; with the 640 margin, x=-320 is the far edge.
            builder.pos = { x = -320, y = 1280, z = 0 }
            result4 = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            protected4 = ZM_Construction:IsProtected(builder)
            result5 = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            protected5 = ZM_Construction:IsProtected(builder)
        """)
        g = lua.globals()
        self.assertFalse(g.result1)
        self.assertFalse(g.result2)
        self.assertFalse(g.result3)
        self.assertTrue(g.result4)
        self.assertTrue(g.protected4)
        self.assertFalse(g.result5)
        self.assertFalse(g.protected5)
        messages = list(g.builder.messages.values())
        self.assertEqual(messages[2], "Move closer to your claim to build.")
        self.assertEqual(messages[4], "Build mode off.")

    def test_tick_ends_mode_when_builder_leaves_or_switches_weapon(self):
        lua = self.lua
        lua.execute("""
            builder = makePlayer(0, 0)
            humans = { builder }
            claims = { { tileX = 0, tileY = 0, active = true, access = true } }
            ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            builder.pos = { x = 2000, y = 0, z = 0 }
            now = 100.5
            ZM_Construction:Tick(builder, now)
            stillOn = builder.weapon.build
            now = 101.5
            ZM_Construction:Tick(builder, now)
            leftOff = builder.weapon.build
            lastMessage = builder.messages[#builder.messages]

            builder.pos = { x = 0, y = 0, z = 0 }
            ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            hammer = builder.weapon
            builder.weapon = makeWeapon("weapon_zn_crowbar")
            switchedProtected = ZM_Construction:IsProtected(builder)
            ZM_Construction:Tick(builder, now)
            switchedFlag = builder.ZM_ConstructionProtected
        """)
        g = lua.globals()
        self.assertTrue(g.stillOn)
        self.assertFalse(g.leftOff)
        self.assertEqual(g.lastMessage, "Build mode ended: Move closer to your claim to build.")
        self.assertFalse(g.switchedProtected)
        self.assertIsNone(g.switchedFlag)

    def test_damage_blocked_both_ways_between_builder_and_zombies_or_players(self):
        lua = self.lua
        lua.execute("""
            builder = makePlayer(0, 0)
            other = makePlayer(100, 0)
            zombie = makeZombie()
            world = { valid = true, GetClass = function() return "worldspawn" end, IsPlayer = function() return false end }
            claims = { { tileX = 0, tileY = 0, active = true, access = true } }
            before = ZM_Construction:BlocksDamage(builder, zombie)
            ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            zombieToBuilder = ZM_Construction:BlocksDamage(builder, zombie)
            builderToZombie = ZM_Construction:BlocksDamage(zombie, builder)
            otherToBuilder = ZM_Construction:BlocksDamage(builder, other)
            builderToOther = ZM_Construction:BlocksDamage(other, builder)
            worldToBuilder = ZM_Construction:BlocksDamage(builder, world)
            zombieToOther = ZM_Construction:BlocksDamage(other, zombie)
            self = ZM_Construction:BlocksDamage(builder, builder)
            builder.alive = false
            hooks["PlayerDeath/ZM.Construction.ClearOnDeath"](builder)
            afterDeath = builder.weapon.build
        """)
        g = lua.globals()
        self.assertFalse(g.before)
        for name in ("zombieToBuilder", "builderToZombie", "otherToBuilder", "builderToOther"):
            self.assertTrue(g[name], name)
        self.assertFalse(g.worldToBuilder)
        self.assertFalse(g.zombieToOther)
        self.assertFalse(g["self"])
        self.assertFalse(g.afterDeath)

    def test_unavailable_storage_or_cell_refuses_build_mode(self):
        lua = self.lua
        lua.execute("""
            builder = makePlayer(0, 0)
            claims = { { tileX = 0, tileY = 0, active = true, access = true } }
            ZM_ClaimService.StorageReady = false
            noStorage = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            ZM_ClaimService.StorageReady = true
            builder.noCell = true
            noCell = ZM_Construction:ToggleBuildMode(builder, builder.weapon)
        """)
        g = lua.globals()
        self.assertFalse(g.noStorage)
        self.assertFalse(g.noCell)
        self.assertEqual(list(g.builder.messages.values()), [
            "Land-claim storage is unavailable.", "Claims are only available in city cells."
        ])

    def test_boundary_tiles_sent_on_entry_and_only_when_changed(self):
        lua = self.lua
        lua.execute("""
            builder = makePlayer(0, 0)
            claims = { { tileX = 0, tileY = 0, active = true, access = true },
                       { tileX = -1, tileY = 2, active = true, access = true } }
            ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            afterEntry = #sent
            now = 101.5
            ZM_Construction:Tick(builder, now)
            afterSameTick = #sent
            table.insert(claims, { tileX = 1, tileY = 0, active = true, access = true })
            now = 103
            ZM_Construction:Tick(builder, now)
            afterChange = #sent
            ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            ZM_Construction:ToggleBuildMode(builder, builder.weapon)
            afterReentry = #sent
        """)
        g = lua.globals()
        self.assertTrue(g.networkStrings["ZM.Construction.Tiles"])
        self.assertEqual((g.afterEntry, g.afterSameTick, g.afterChange, g.afterReentry), (1, 1, 2, 3))
        first = g.sent[1]
        self.assertEqual(first["name"], "ZM.Construction.Tiles")
        self.assertEqual(list(first["values"].values()), [640, 2, 0, 0, -1, 2])

    def test_boundary_edges_omit_shared_sides(self):
        lua = self.lua
        lua.execute("""
            single = #ZM_Construction.BoundaryEdges({ { tileX = 0, tileY = 0 } }, 640)
            pair = ZM_Construction.BoundaryEdges({ { tileX = 0, tileY = 0 }, { tileX = 1, tileY = 0 } }, 640)
            pairCount = #pair
            sharedEdge = false
            for _, edge in ipairs(pair) do
                if edge[1] == 320 and edge[3] == 320 then sharedEdge = true end
            end
            apart = #ZM_Construction.BoundaryEdges({ { tileX = -2, tileY = -2 }, { tileX = 2, tileY = 2 } }, 640)
        """)
        g = lua.globals()
        self.assertEqual((g.single, g.pairCount, g.apart), (4, 6, 8))
        self.assertFalse(g.sharedEdge)

    def install_placement_mocks(self):
        self.lua.execute("""
            local vectorMeta = {}
            vectorMeta.__index = vectorMeta
            vectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
            vectorMeta.__mul = function(a, scale) return Vector(a.x * scale, a.y * scale, a.z * scale) end
            function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vectorMeta) end
            COLLISION_GROUP_NONE = 0
            MASK_SOLID = 1
            function table.GetKeys(source)
                local keys = {}
                for key in pairs(source) do keys[#keys + 1] = key end
                return keys
            end
            aimTrace = { Hit = true, HitWorld = true, HitNormal = Vector(0, 0, 1), HitPos = Vector(10, 10, 0) }
            util.TraceLine = function() return aimTrace end
            occupants = {}
            created = {}
            ents = {
                FindInBox = function() return occupants end,
                Create = function(class)
                    local piece = { valid = true, class = class, kind = "", yaw = 0, progress = 0,
                                    complete = false, paid = false, completedAt = 0 }
                    function piece:GetClass() return self.class end
                    function piece:SetPieceKind(value) self.kind = value end
                    function piece:GetPieceKind() return self.kind end
                    function piece:SetPieceYaw(value) self.yaw = value end
                    function piece:GetPieceYaw() return self.yaw end
                    function piece:SetPos(value) self.pos = value end
                    function piece:GetPos() return self.pos end
                    function piece:SetProgress(value) self.progress = value end
                    function piece:GetProgress() return self.progress end
                    function piece:SetComplete(value) self.complete = value end
                    function piece:GetComplete() return self.complete end
                    function piece:SetCompletedAt(value) self.completedAt = value end
                    function piece:SetPaid(value) self.paid = value end
                    function piece:GetPaid() return self.paid end
                    function piece:SetCollisionGroup(value) self.group = value end
                    function piece:Spawn() self.spawned = true end
                    function piece:Remove() self.valid = false end
                    table.insert(created, piece)
                    return piece
                end
            }
            backpack = { itemWood = 10, itemScrapMetal = 3 }
            mutations = 0
            ZM_InventoryService = {
                Ops = { Remove = function(draft, container, itemId, count)
                    if container ~= "backpack" or (draft[itemId] or 0) < count then return false, "missing" end
                    draft[itemId] = draft[itemId] - count
                    return true
                end },
                Mutate = function(_, _, callback)
                    mutations = mutations + 1
                    local draft = {}
                    for key, value in pairs(backpack) do draft[key] = value end
                    local ok, reason = callback(draft)
                    if not ok then return false, reason end
                    backpack = draft
                    return true
                end
            }
            ZM_Items.GetDefinition = function(_, id)
                if id == "weaponMeleeHammer" then return { minLevel = 8, maxLevel = 30 } end
                if id == "itemWood" then return { name = "Wood" } end
                if id == "itemScrapMetal" then return { name = "Scrap Metal" } end
            end
            function makeBuilder()
                local builder = makePlayer(0, 0)
                builder.weapon.level = 8
                builder.weapon.mastercraft = false
                function builder.weapon:GetItemLevel() return self.level end
                function builder.weapon:GetItemMastercraft() return self.mastercraft end
                function builder.weapon:GetBuildPiece() return self.piece end
                function builder.weapon:SetBuildPiece(value) self.piece = value end
                function builder:EyePos() return Vector(0, 0, 64) end
                function builder:GetAimVector() return Vector(1, 0, 0) end
                function builder:EyeAngles() return { y = self.viewYaw or 0 } end
                claims = { { tileX = 0, tileY = 0, active = true, access = true } }
                ZM_Construction:ToggleBuildMode(builder, builder.weapon)
                return builder
            end
        """)

    def test_snapping_bounds_and_footprints(self):
        lua = self.lua
        lua.execute("""
            fx, fy, fz, fyaw = ZM_Construction.SnapPlacement('foundation', 10, -10, 3.6, 45)
            wx, wy, wz, wyaw = ZM_Construction.SnapPlacement('wall', 40, 10, 0, 170)
            sx, sy, sz, syaw = ZM_Construction.SnapPlacement('wall', 10, 40, 0, 95)
            bx1, by1, bz1, bx2, by2, bz2 = ZM_Construction.PieceBounds('wall', 90)
            corners = ZM_Construction.FootprintCorners('wall', 64, 32, 90)
            unknown = ZM_Construction.SnapPlacement('roof', 0, 0, 0, 0)
            keyLow = ZM_Construction.SlotKey('wall', 64, 32, 2, 90)
            keyHigh = ZM_Construction.SlotKey('wall', 64, 32, 128, 90)
        """)
        g = lua.globals()
        self.assertEqual((g.fx, g.fy, g.fz, g.fyaw), (32, -32, 4, 0))
        # Looking along X: the wall spans Y on the nearest X grid line.
        self.assertEqual((g.wx, g.wy, g.wz, g.wyaw), (64, 32, 0, 90))
        # Looking along Y: the wall spans X on the nearest Y grid line.
        self.assertEqual((g.sx, g.sy, g.sz, g.syaw), (32, 64, 0, 0))
        self.assertEqual((g.bx1, g.by1, g.bz1, g.bx2, g.by2, g.bz2), (-4, -32, 0, 4, 32, 128))
        self.assertEqual([(c["x"], c["y"]) for c in g.corners.values()], [(60, 0), (68, 0), (68, 64), (60, 64)])
        self.assertIsNone(g.unknown)
        self.assertNotEqual(g.keyLow, g.keyHigh)

    def test_placement_requires_claim_footprint_and_refuses_duplicates_and_cap(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            first = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            duplicate = #created
            duplicateMessage = builder.messages[#builder.messages]
            -- A foundation square beyond the tile edge at x=320 is refused.
            aimTrace.HitPos = Vector(330, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            outsideMessage = builder.messages[#builder.messages]
            aimTrace.HitPos = Vector(10, 10, 0)
            aimTrace.HitNormal = Vector(0, 0, 0.2)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            slopeMessage = builder.messages[#builder.messages]
            aimTrace.HitNormal = Vector(0, 0, 1)
            aimTrace.HitWorld = false
            aimTrace.Entity = created[1]
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            blueprintMessage = builder.messages[#builder.messages]
            aimTrace.HitWorld = true
            aimTrace.Entity = nil
            for index = 1, 12 do
                aimTrace.HitPos = Vector(-310 + ((index - 1) % 10) * 64, 200 + math.floor((index - 1) / 10) * 64, 0)
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
            end
            capped = #created
            capMessage = builder.messages[#builder.messages]
        """)
        g = lua.globals()
        self.assertEqual((g.first, g.duplicate), (1, 1))
        piece = g.created[1]
        self.assertEqual((piece.kind, piece.pos.x, piece.pos.y, piece.yaw), ("foundation", 32, 32, 0))
        self.assertTrue(piece.spawned)
        self.assertEqual(g.duplicateMessage, "Something is already built there.")
        self.assertEqual(g.outsideMessage, "Pieces must be built inside your claim.")
        self.assertEqual(g.slopeMessage, "Aim at level ground within reach.")
        self.assertEqual(g.blueprintMessage, "Pieces must stand on the ground or a finished piece.")
        self.assertEqual(g.capped, 12)
        self.assertEqual(g.capMessage, "Finish or remove some blueprints first.")

    def test_contribution_pays_once_atomically_and_scales_with_level(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            builder.weapon.level = 30
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            started = ZM_Construction:Contribute(builder, piece, 100)
            paidAfterStart = piece.paid
            woodAfterPay = backpack.itemWood
            -- A long gap is not credited: progress only accrues across consecutive ticks.
            ZM_Construction:Contribute(builder, piece, 105)
            afterGap = piece.progress
            for tick = 1, 11 do ZM_Construction:Contribute(builder, piece, 105 + tick * 0.25) end
            nearlyDone = piece.progress
            ZM_Construction:Contribute(builder, piece, 108)
            done = piece.complete
            group = piece.group
            again = ZM_Construction:Contribute(builder, piece, 108.25)
            mutationsAfter = mutations
        """)
        g = lua.globals()
        self.assertTrue(g.started)
        self.assertTrue(g.paidAfterStart)
        self.assertEqual(g.woodAfterPay, 6)
        self.assertEqual(g.backpack["itemScrapMetal"], 1)
        self.assertEqual(g.afterGap, 0)
        # Level 30 builds a 6 s foundation in 3 s: 11 ticks of 0.25 s is 2.75 s.
        self.assertAlmostEqual(g.nearlyDone, 2.75 / 3)
        self.assertTrue(g.done)
        self.assertEqual(g.group, 0)
        self.assertFalse(g.again)
        self.assertEqual(g.mutationsAfter, 1)

    def test_insufficient_materials_leave_inventory_and_progress_unchanged(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            backpack = { itemWood = 10, itemScrapMetal = 1 }
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            result = ZM_Construction:Contribute(builder, piece, 100)
            message = builder.messages[#builder.messages]
            unpaid = not piece.paid and backpack.itemWood == 10 and backpack.itemScrapMetal == 1
            -- A mastercrafted hammer halves the foundation to 2 Wood and 1 Scrap Metal.
            builder.weapon.mastercraft = true
            now = 102
            mastercraftResult = ZM_Construction:Contribute(builder, piece, 102)
        """)
        g = lua.globals()
        self.assertFalse(g.result)
        self.assertEqual(g.message, "Building this needs 2 Scrap Metal and 4 Wood in your backpack.")
        self.assertTrue(g.unpaid)
        self.assertTrue(g.mastercraftResult)
        self.assertEqual((g.backpack["itemWood"], g.backpack["itemScrapMetal"]), (8, 0))

    def test_completion_waits_while_someone_stands_inside(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            builder.weapon.level = 30
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            ZM_Construction:Contribute(builder, piece, 100)
            for tick = 1, 11 do ZM_Construction:Contribute(builder, piece, 100 + tick * 0.25) end
            standing = makePlayer(32, 32)
            function standing:IsNPC() return false end
            occupants = { standing }
            blocked = ZM_Construction:Contribute(builder, piece, 103)
            blockedComplete = piece.complete
            message = builder.messages[#builder.messages]
            occupants = {}
            now = 103.25
            finished = ZM_Construction:Contribute(builder, piece, 103.25)
        """)
        g = lua.globals()
        self.assertFalse(g.blocked)
        self.assertFalse(g.blockedComplete)
        self.assertEqual(g.message, "Something is in the way.")
        self.assertTrue(g.finished)
        self.assertTrue(g.created[1].complete)

    def test_secondary_removes_only_own_unpaid_blueprints_else_cycles(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            other = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            aimTrace.Entity = piece
            ZM_Construction:SecondaryBuild(other, other.weapon)
            otherSelected = other.weapon.piece
            stillThere = piece.valid
            piece.paid = true
            ZM_Construction:SecondaryBuild(builder, builder.weapon)
            paidStays = piece.valid
            firstCycle = builder.weapon.piece
            ZM_Construction:SecondaryBuild(builder, builder.weapon)
            secondCycle = builder.weapon.piece
            piece.paid = false
            ZM_Construction:SecondaryBuild(builder, builder.weapon)
            removed = not piece.valid
            removedMessage = builder.messages[#builder.messages]
            slotFree = next(ZM_Construction.SlotRegistry) == nil
        """)
        g = lua.globals()
        self.assertEqual(g.otherSelected, "wall")
        self.assertTrue(g.stillThere)
        self.assertTrue(g.paidStays)
        self.assertEqual((g.firstCycle, g.secondCycle), ("wall", "foundation"))
        self.assertTrue(g.removed)
        self.assertEqual(g.removedMessage, "Blueprint removed.")
        self.assertTrue(g.slotFree)


if __name__ == "__main__":
    unittest.main()
