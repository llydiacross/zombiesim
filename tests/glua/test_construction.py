"""Offline construction fixtures (Alpha 3.4 Phase E): Hammer build rules, eligibility and non-interaction."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


def make_construction_runner(extra_files=(), prepare=None):
    """Loads the construction modules over the shared engine fakes; prepare(runner) runs before the fakes."""
    runner = FixtureRunner(ROOT, ["sh_construction.lua", "sv_construction.lua", *extra_files])
    lua = runner.lua
    if prepare:
        prepare(runner)
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
            receivers = {}
            local current
            net = {
                Start = function(name) current = { name = name, values = {} } end,
                WriteUInt = function(value) table.insert(current.values, value) end,
                WriteInt = function(value) table.insert(current.values, value) end,
                Send = function(target) current.target = target; table.insert(sent, current) end,
                Receive = function(name, callback) receivers[name] = callback end,
                ReadString = function() return receivedKind end,
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
                function target:SetNWBool(key, value) self[key] = value end
                function target:GetNWBool(key, default) if self[key] == nil then return default end return self[key] end
                function target:SetNWInt(key, value) self[key] = value end
                function target:PrintMessage(_, message) self.messages[#self.messages + 1] = message end
                function target:SetAnimation(activity) self.lastAnimation = activity end
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
    return runner


class ConstructionTests(unittest.TestCase):
    def setUp(self):
        self.lua = make_construction_runner().lua
        self.construction = self.lua.globals().ZM_Construction

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
            ACT_VM_HITCENTER, PLAYER_ATTACK1, CHAN_WEAPON = 1, 2, 3
            function table.GetKeys(source)
                local keys = {}
                for key in pairs(source) do keys[#keys + 1] = key end
                return keys
            end
            aimTrace = { Hit = true, HitWorld = true, HitNormal = Vector(0, 0, 1), HitPos = Vector(10, 10, 0) }
            util.TraceLine = function(options) lastPlacementTrace = options; return aimTrace end
            occupants = {}
            created = {}
            ents = {
                FindByClass = function() return {} end,
                FindInBox = function() return occupants end,
                Create = function(class)
                    local piece = { valid = true, class = class, kind = "", yaw = 0, progress = 0,
                                    complete = false, paid = false, completedAt = 0 }
                    function piece:GetClass() return self.class end
                    function piece:IsWorld() return false end
                    function piece:SetNWEntity(key, value) self[key] = value end
                    function piece:SetNWBool(key, value) self[key] = value end
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
                    function piece:SetWear(value) self.wear = value end
                    function piece:GetWear() return self.wear or 0 end
                    function piece:SetPaid(value) self.paid = value end
                    function piece:GetPaid() return self.paid end
                    function piece:SetCollisionGroup(value) self.group = value end
                    function piece:Spawn()
                        self.spawned = true
                        self.ZM_CollisionReady = not failCollision
                    end
                    function piece:Remove() self.valid = false end
                    table.insert(created, piece)
                    return piece
                end
            }
            backpack = { itemWood = 10, itemScrapMetal = 3 }
            mutations = 0
            paymentErrors = {}
            function ErrorNoHalt(message) paymentErrors[#paymentErrors + 1] = message end
            ZM_InventoryService = {
                Ops = {
                    Count = function(draft, itemId, container)
                        assert(container == "backpack")
                        return draft[itemId] or 0
                    end,
                    Remove = function(draft, container, itemId, count)
                        if container ~= "backpack" or (draft[itemId] or 0) < count then return false, "missing" end
                        draft[itemId] = draft[itemId] - count
                        return true
                    end,
                    Add = function(draft, container, instance)
                        if container ~= "backpack" then return false, "wrong container" end
                        refundAdds = (refundAdds or 0) + 1
                        if failRefundAdd == refundAdds then return false, "injected capacity failure" end
                        draft[instance.itemId] = (draft[instance.itemId] or 0) + instance.count
                        return true
                    end
                },
                Mutate = function(_, _, callback)
                    mutations = mutations + 1
                    local draft = {}
                    for key, value in pairs(backpack) do draft[key] = value end
                    local ok, reason = callback(draft)
                    if not ok then return false, reason end
                    if failPaymentSave then return false, "injected payment write failure" end
                    backpack = draft
                    return true
                end
            }
            local refundInstance = 0
            ZM_ItemGeneration = {
                CreateInstance = function(_, itemId, options)
                    refundInstance = refundInstance + 1
                    return { instanceId = "refund-" .. refundInstance, itemId = itemId, count = options.count }
                end
            }
            ZM_Items.GetDefinition = function(_, id)
                if id == "weaponMeleeHammer" then return { minLevel = 8, maxLevel = 30 } end
                if id == "itemWood" then return { name = "Wood", maxStack = refundStack or 100 } end
                if id == "itemScrapMetal" then return { name = "Scrap Metal", maxStack = 100 } end
            end
            function makeBuilder()
                local builder = makePlayer(0, 0)
                builder.weapon.level = 8
                builder.weapon.mastercraft = false
                function builder.weapon:GetItemLevel() return self.level end
                function builder.weapon:GetItemMastercraft() return self.mastercraft end
                function builder.weapon:GetBuildPiece() return self.piece end
                function builder.weapon:SetBuildPiece(value) self.piece = value end
                function builder.weapon:SendWeaponAnim(value)
                    self.animationCount = (self.animationCount or 0) + 1
                    self.lastAnimation = value
                end
                function builder.weapon:EmitSound(value)
                    self.soundCount = (self.soundCount or 0) + 1
                    self.lastSound = value
                end
                function builder:EyePos() return Vector(0, 0, 64) end
                function builder:GetAimVector() return Vector(1, 0, 0) end
                function builder:GetLevelAim() return Vector(0, 0, 36), Vector(1, 0, 0) end
                function builder:EyeAngles() return { y = self.viewYaw or 0 } end
                function builder:GetGroundEntity() return self.ground end
                claims = { { tileX = 0, tileY = 0, active = true, access = true } }
                ZM_Construction:ToggleBuildMode(builder, builder.weapon)
                return builder
            end
        """)

    def test_placement_trace_uses_the_crosshair_origin_and_direction(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            function builder:GetLevelAim() return Vector(4, 5, 36), Vector(0.6, 0, -0.8) end
            ZM_Construction:AimTrace(builder)
        """)
        trace = self.lua.globals().lastPlacementTrace
        self.assertEqual((trace["start"]["x"], trace["start"]["y"], trace["start"]["z"]), (4, 5, 36))
        self.assertAlmostEqual(trace["endpos"]["x"], 4 + 0.6 * 256)
        self.assertAlmostEqual(trace["endpos"]["y"], 5)
        self.assertAlmostEqual(trace["endpos"]["z"], 36 - 0.8 * 256)
        self.assertEqual(trace["mask"], 1)

    def test_trace_skips_pieces_whose_client_accessors_are_not_ready(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            local pending = { valid = true }
            function pending:GetClass() return ZM_Construction.PieceClass end
            function pending:GetPos() return Vector(64, 0, 0) end
            ents.FindByClass = function() return { pending } end
            readyTrace = ZM_Construction:AimTrace(builder)
            readyFlag = ZM_Construction.IsReadyPiece(pending)
        """)
        globals_ = self.lua.globals()
        self.assertFalse(globals_.readyFlag)
        self.assertTrue(globals_.readyTrace["HitWorld"])

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

    def test_placement_requires_claim_footprint_refuses_duplicates_and_has_no_blueprint_cap(self):
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
            for index = 1, 20 do
                aimTrace.HitPos = Vector(-310 + ((index - 1) % 10) * 64, 200 + math.floor((index - 1) / 10) * 64, 0)
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
            end
            placed = #created
            placementMessage = builder.messages[#builder.messages]
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
        self.assertEqual(g.placed, 21)
        self.assertEqual(g.placementMessage, "Foundation blueprint placed. Hold E on it to build.")

    def test_completed_foundation_supports_four_distinct_wall_edges(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            foundation = created[1]
            foundation.complete, foundation.paid = true, true
            builder.weapon.piece = "wall"
            aimTrace.HitWorld, aimTrace.Entity = false, foundation
            local edges = {
                { 1, 32, 0 }, { 63, 32, 0 }, { 32, 1, 90 }, { 32, 63, 90 }
            }
            for _, edge in ipairs(edges) do
                aimTrace.HitPos = Vector(edge[1], edge[2], 16)
                builder.viewYaw = edge[3]
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
            end
        """)
        pieces = list(self.lua.globals().created.values())
        self.assertEqual(len(pieces), 5)
        actual = {
            (piece["pos"]["x"], piece["pos"]["y"], piece["pos"]["z"], piece["yaw"])
            for piece in pieces[1:]
        }
        self.assertEqual(actual, {(0, 32, 16, 90), (64, 32, 16, 90), (32, 0, 16, 0), (32, 64, 16, 0)})

    def test_stairs_and_ramps_support_upper_floors_in_all_directions(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            landings = {}
            for _, kind in ipairs({ "stairs", "ramp" }) do
                for _, yaw in ipairs({ 0, 90, 180, 270 }) do
                    ZM_Construction.SlotRegistry = {}
                    local support = ents.Create("zn_construction_piece")
                    support.kind, support.yaw, support.complete = kind, yaw, true
                    support.pos = yaw % 180 == 0 and Vector(0, 32, 16) or Vector(32, 0, 16)
                    aimTrace = {
                        Hit = true, HitWorld = false, Entity = support,
                        HitNormal = Vector(0, 0, 1),
                        HitPos = Vector(support.pos.x, support.pos.y, 48)
                    }
                    builder.weapon.piece, builder.viewYaw = "floor", yaw
                    local before = #created
                    ZM_Construction:PrimaryBuild(builder, builder.weapon)
                    landings[#landings + 1] = {
                        kind = kind, yaw = yaw, support = support, placed = #created > before,
                        piece = #created > before and created[#created] or nil,
                        message = builder.messages[#builder.messages]
                    }
                end
            end
        """)
        expected = {
            0: (96, 32, 144), 90: (32, 96, 144),
            180: (-96, 32, 144), 270: (32, -96, 144),
        }
        for landing in self.lua.globals().landings.values():
            with self.subTest(kind=landing.kind, yaw=landing.yaw):
                self.assertTrue(landing.placed, landing.message)
                self.assertEqual(
                    (landing.piece.pos.x, landing.piece.pos.y, landing.piece.pos.z),
                    expected[landing.yaw],
                )
                support_bounds = self.construction.PieceBounds(landing.kind, landing.yaw)
                floor_bounds = self.construction.PieceBounds("floor", landing.piece.yaw)
                self.assertEqual(landing.support.pos.z + support_bounds[5], landing.piece.pos.z)
                self.assertEqual(landing.piece.pos.z + floor_bounds[5] - (landing.support.pos.z + support_bounds[5]), 8)

    def test_stairs_and_ramps_can_start_from_ground_when_aiming_into_open_air(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            builder.pos = Vector(40, 32, 0)
            builder.viewYaw = 0
            builder.ground = { valid = true, IsWorld = function() return true end }
            aimTrace = { Hit = false }
            groundAccess = {}
            for _, kind in ipairs({ "stairs", "ramp" }) do
                builder.weapon.piece = kind
                local before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                local piece = #created > before and created[#created] or nil
                groundAccess[kind] = {
                    piece = piece,
                    message = builder.messages[#builder.messages]
                }
            end
        """)
        access = self.lua.globals().groundAccess
        for kind in ("stairs", "ramp"):
            with self.subTest(kind=kind):
                piece = access[kind].piece
                self.assertIsNotNone(piece, access[kind].message)
                self.assertEqual(piece.kind, kind)
                self.assertEqual((piece.pos.x, piece.pos.y, piece.pos.z, piece.yaw), (64, 32, 0, 0))

    def test_floor_extends_the_finished_piece_underfoot_when_aiming_into_open_air(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            standing = {}
            local function attempt(label, hit, complete, piece)
                ZM_Construction.SlotRegistry = {}
                local support = ents.Create("zn_construction_piece")
                support.kind, support.yaw, support.complete = "stairs", 0, complete
                support.pos = Vector(0, 32, 16)
                builder.ground = support
                builder.pos = Vector(40, 30, 144)
                builder.viewYaw = 0
                builder.weapon.piece = piece
                aimTrace = hit
                local before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                local placed = #created > before and created[#created] or nil
                standing[label] = {
                    placed = placed ~= nil,
                    x = placed and placed.pos.x, y = placed and placed.pos.y, z = placed and placed.pos.z,
                    message = builder.messages[#builder.messages]
                }
            end
            attempt("air", { Hit = false }, true, "floor")
            attempt("below", { Hit = true, HitWorld = true, HitNormal = Vector(0, 0, 1), HitPos = Vector(200, 32, 0) },
                true, "floor")
            attempt("blueprint", { Hit = false }, false, "floor")
            attempt("wall", { Hit = false }, true, "wall")
        """)
        result = self.lua.globals().standing
        for label in ("air", "below"):
            with self.subTest(case=label):
                self.assertTrue(result[label].placed, result[label].message)
                self.assertEqual((result[label].x, result[label].y, result[label].z), (96, 32, 144))
        self.assertFalse(result["blueprint"].placed)
        self.assertFalse(result["wall"].placed)

    def test_upper_floors_extend_from_finished_floor_edges_at_the_same_level(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            floorEdges = {}
            local cases = {
                { 63, 32, 0 }, { 1, 32, 180 }, { 32, 63, 90 }, { 32, 1, 270 }
            }
            for _, case in ipairs(cases) do
                ZM_Construction.SlotRegistry = {}
                local support = ents.Create("zn_construction_piece")
                support.kind, support.yaw, support.complete = "floor", 0, true
                support.pos = Vector(32, 32, 144)
                aimTrace = {
                    Hit = true, HitWorld = false, Entity = support,
                    HitNormal = Vector(0, 0, 1), HitPos = Vector(case[1], case[2], 152)
                }
                builder.weapon.piece, builder.viewYaw = "floor", case[3]
                local before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                floorEdges[#floorEdges + 1] = {
                    placed = #created > before,
                    piece = #created > before and created[#created] or nil,
                    message = builder.messages[#builder.messages]
                }
            end
        """)
        expected = [(96, 32, 144), (-32, 32, 144), (32, 96, 144), (32, -32, 144)]
        for edge, position in zip(self.lua.globals().floorEdges.values(), expected):
            self.assertTrue(edge.placed, edge.message)
            self.assertEqual((edge.piece.pos.x, edge.piece.pos.y, edge.piece.pos.z), position)

    def test_roofs_attach_to_both_sides_of_each_finished_wall(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            roofs = {}
            local cases = {
                { 0, 32, 90, 1, 0, 180 }, { 0, 32, 90, -1, 0, 0 },
                { 32, 0, 0, 0, 1, 270 }, { 32, 0, 0, 0, -1, 90 }
            }
            for _, case in ipairs(cases) do
                ZM_Construction.SlotRegistry = {}
                local support = ents.Create("zn_construction_piece")
                support.kind, support.yaw, support.complete = "wall", case[3], true
                support.pos = Vector(case[1], case[2], 16)
                aimTrace = {
                    Hit = true, HitWorld = false, Entity = support,
                    HitNormal = Vector(case[4], case[5], 0),
                    HitPos = Vector(case[1] + case[4] * 4, case[2] + case[5] * 4, 80)
                }
                builder.weapon.piece, builder.viewYaw = "roof_flat", case[6]
                local before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                roofs[#roofs + 1] = {
                    placed = #created > before,
                    piece = #created > before and created[#created] or nil,
                    message = builder.messages[#builder.messages]
                }
            end
        """)
        expected = [(32, 32, 144), (-32, 32, 144), (32, 32, 144), (32, -32, 144)]
        for roof, position in zip(self.lua.globals().roofs.values(), expected):
            self.assertTrue(roof.placed, roof.message)
            self.assertEqual((roof.piece.pos.x, roof.piece.pos.y, roof.piece.pos.z), position)

    def test_every_roof_shape_can_attach_to_a_wall_without_sinking_through_it(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            roofShapes = {}
            local walls = {
                { 0, 32, 90, 1, 0 }, { 0, 32, 90, -1, 0 },
                { 32, 0, 0, 0, 1 }, { 32, 0, 0, 0, -1 }
            }
            for _, kind in ipairs({ "roof_flat", "roof_slope", "roof_corner_outer", "roof_corner_inner" }) do
                for _, wall in ipairs(walls) do
                    for _, yaw in ipairs({ 0, 90, 180, 270 }) do
                        ZM_Construction.SlotRegistry = {}
                        local support = ents.Create("zn_construction_piece")
                        support.kind, support.yaw, support.complete = "wall", wall[3], true
                        support.pos = Vector(wall[1], wall[2], 16)
                        aimTrace = {
                            Hit = true, HitWorld = false, Entity = support,
                            HitNormal = Vector(wall[4], wall[5], 0),
                            HitPos = Vector(wall[1] + wall[4] * 4, wall[2] + wall[5] * 4, 80)
                        }
                        builder.weapon.piece, builder.viewYaw = kind, yaw
                        local before = #created
                        ZM_Construction:PrimaryBuild(builder, builder.weapon)
                        roofShapes[#roofShapes + 1] = {
                            kind = kind, wallX = wall[1], wallY = wall[2], nx = wall[4], ny = wall[5],
                            viewYaw = yaw, placed = #created > before,
                            piece = #created > before and created[#created] or nil,
                            message = builder.messages[#builder.messages]
                        }
                    end
                end
            end
        """)
        for result in self.lua.globals().roofShapes.values():
            with self.subTest(kind=result.kind, normal=(result.nx, result.ny), view_yaw=result.viewYaw):
                self.assertTrue(result.placed, result.message)
                roof = result.piece
                self.assertEqual((roof.pos.x, roof.pos.y),
                                 (result.wallX + result.nx * 32, result.wallY + result.ny * 32))
                # The roof's low edge vertex on the wall is flush with the wall's top.
                edge = [
                    vertex[3] + roof.pos.z
                    for part in self.construction.GetParts(result.kind, roof.yaw).values()
                    for vertex in part.vertices.values()
                    if (roof.pos.x + vertex[1] == result.wallX if result.nx
                        else roof.pos.y + vertex[2] == result.wallY)
                ]
                self.assertTrue(edge)
                self.assertEqual(min(edge), 144)

    def test_upper_wall_stacks_on_wall_and_supports_a_roof(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            lower = ents.Create("zn_construction_piece")
            lower.kind, lower.yaw, lower.complete, lower.pos = "wall", 90, true, Vector(0, 32, 16)
            aimTrace = {
                Hit = true, HitWorld = false, Entity = lower,
                HitNormal = Vector(1, 0, 0), HitPos = Vector(4, 32, 80)
            }
            builder.weapon.piece, builder.viewYaw = "wall_half", 180
            local before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            upper = #created > before and created[#created] or nil
            if upper then
                upper.complete = true
                aimTrace.Entity = upper
                aimTrace.HitPos = Vector(4, 32, 176)
                builder.weapon.piece = "roof_flat"
                before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                cap = #created > before and created[#created] or nil
            end
        """)
        g = self.lua.globals()
        self.assertIsNotNone(g.upper)
        self.assertEqual((g.upper.pos.x, g.upper.pos.y, g.upper.pos.z, g.upper.yaw), (0, 32, 144, 90))
        self.assertIsNotNone(g.cap)
        self.assertEqual((g.cap.pos.x, g.cap.pos.y, g.cap.pos.z), (32, 32, 208))

    def test_sloped_roofs_join_matching_edges_and_refuse_mismatched_profiles(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            support = ents.Create("zn_construction_piece")
            support.kind, support.yaw, support.complete, support.pos = "roof_slope", 0, true, Vector(32, 32, 144)
            aimTrace = {
                Hit = true, HitWorld = false, Entity = support,
                HitNormal = Vector(0, 0, 1), HitPos = Vector(63, 32, 183)
            }
            builder.weapon.piece, builder.viewYaw = "roof_slope", 0
            local before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            aligned = #created > before and created[#created] or nil
            builder.viewYaw = 90
            before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            mismatchPlaced = #created > before
            mismatchMessage = builder.messages[#builder.messages]
        """)
        g = self.lua.globals()
        self.assertIsNotNone(g.aligned)
        self.assertEqual((g.aligned.pos.x, g.aligned.pos.y, g.aligned.pos.z, g.aligned.yaw), (96, 32, 176, 0))
        self.assertFalse(g.mismatchPlaced)
        self.assertIn("edges", g.mismatchMessage.lower())

    def test_sloped_roofs_continue_at_matching_heights_in_all_rotations(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            roofEdges = {}
            local edges = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
            for _, yaw in ipairs({ 0, 90, 180, 270 }) do
                for _, edge in ipairs(edges) do
                    ZM_Construction.SlotRegistry = {}
                    local support = ents.Create("zn_construction_piece")
                    support.kind, support.yaw, support.complete, support.pos = "roof_slope", yaw, true, Vector(32, 32, 144)
                    aimTrace = {
                        Hit = true, HitWorld = false, Entity = support,
                        HitNormal = Vector(0, 0, 1),
                        HitPos = Vector(32 + edge[1] * 31, 32 + edge[2] * 31, 160)
                    }
                    builder.weapon.piece, builder.viewYaw = "roof_slope", yaw
                    local before = #created
                    ZM_Construction:PrimaryBuild(builder, builder.weapon)
                    roofEdges[#roofEdges + 1] = {
                        yaw = yaw, nx = edge[1], ny = edge[2], placed = #created > before,
                        piece = #created > before and created[#created] or nil,
                        message = builder.messages[#builder.messages]
                    }
                end
            end
        """)
        directions = {0: (1, 0), 90: (0, 1), 180: (-1, 0), 270: (0, -1)}
        for result in self.lua.globals().roofEdges.values():
            with self.subTest(yaw=result.yaw, normal=(result.nx, result.ny)):
                self.assertTrue(result.placed, result.message)
                dx, dy = directions[result.yaw]
                self.assertEqual(
                    (result.piece.pos.x, result.piece.pos.y, result.piece.pos.z, result.piece.yaw),
                    (32 + 64 * result.nx, 32 + 64 * result.ny,
                     144 + 32 * (dx * result.nx + dy * result.ny), result.yaw),
                )

    def test_half_floor_edges_extend_without_a_gap_or_overlap(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            support = ents.Create("zn_construction_piece")
            support.kind, support.yaw, support.complete, support.pos = "floor_half", 90, true, Vector(16, 32, 144)
            aimTrace = {
                Hit = true, HitWorld = false, Entity = support,
                HitNormal = Vector(0, 0, 1), HitPos = Vector(31, 32, 152)
            }
            builder.weapon.piece, builder.viewYaw = "floor", 0
            local before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            extended = #created > before and created[#created] or nil
        """)
        extended = self.lua.globals().extended
        self.assertIsNotNone(extended)
        # The half-floor ends at x=32, so the full floor begins there.
        self.assertEqual((extended.pos.x, extended.pos.y, extended.pos.z), (64, 32, 144))

    def test_triangle_floors_join_along_their_diagonal_for_all_rotations(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            triangles = {}
            local normals = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
            for index, yaw in ipairs({ 0, 90, 180, 270 }) do
                ZM_Construction.SlotRegistry = {}
                local support = ents.Create("zn_construction_piece")
                support.kind, support.yaw, support.complete, support.pos = "floor_triangle", yaw, true, Vector(32, 32, 144)
                aimTrace = {
                    Hit = true, HitWorld = false, Entity = support,
                    HitNormal = Vector(normals[index][1] * 0.707, normals[index][2] * 0.707, 0),
                    HitPos = Vector(32, 32, 148)
                }
                builder.weapon.piece, builder.viewYaw = "floor_triangle", yaw
                local before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                triangles[#triangles + 1] = {
                    yaw = yaw, placed = #created > before,
                    piece = #created > before and created[#created] or nil,
                    message = builder.messages[#builder.messages]
                }
            end
        """)
        for result in self.lua.globals().triangles.values():
            with self.subTest(yaw=result.yaw):
                self.assertTrue(result.placed, result.message)
                self.assertEqual(
                    (result.piece.pos.x, result.piece.pos.y, result.piece.pos.z, result.piece.yaw),
                    (32, 32, 144, (result.yaw + 180) % 360),
                )

    def test_triangular_floor_automatically_presents_a_straight_edge_to_a_wall(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            support = ents.Create("zn_construction_piece")
            support.kind, support.yaw, support.complete, support.pos = "wall", 90, true, Vector(0, 32, 16)
            aimTrace = {
                Hit = true, HitWorld = false, Entity = support,
                HitNormal = Vector(1, 0, 0), HitPos = Vector(4, 32, 80)
            }
            builder.weapon.piece, builder.viewYaw = "floor_triangle", 180
            local before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            triangle = #created > before and created[#created] or nil
        """)
        triangle = self.lua.globals().triangle
        self.assertIsNotNone(triangle)
        self.assertEqual((triangle.pos.x, triangle.pos.y, triangle.pos.z, triangle.yaw), (32, 32, 144, 270))

    def test_triangle_diagonal_is_selectable_from_its_top_surface(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            triangles = {}
            local hits = { { 8, -8 }, { 8, 8 }, { -8, 8 }, { -8, -8 } }
            for index, yaw in ipairs({ 0, 90, 180, 270 }) do
                ZM_Construction.SlotRegistry = {}
                local support = ents.Create("zn_construction_piece")
                support.kind, support.yaw, support.complete, support.pos = "floor_triangle", yaw, true, Vector(32, 32, 144)
                aimTrace = {
                    Hit = true, HitWorld = false, Entity = support, HitNormal = Vector(0, 0, 1),
                    HitPos = Vector(32 + hits[index][1], 32 + hits[index][2], 152)
                }
                builder.weapon.piece, builder.viewYaw = "floor_triangle", yaw
                local before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                triangles[#triangles + 1] = {
                    yaw = yaw, piece = #created > before and created[#created] or nil,
                    message = builder.messages[#builder.messages]
                }
            end
        """)
        for result in self.lua.globals().triangles.values():
            with self.subTest(yaw=result.yaw):
                triangle = result.piece
                self.assertIsNotNone(triangle, result.message)
                self.assertEqual((triangle.pos.x, triangle.pos.y, triangle.pos.z, triangle.yaw),
                                 (32, 32, 144, (result.yaw + 180) % 360))

    def test_an_upper_floor_can_support_stairs_to_a_further_storey(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            upper = ents.Create("zn_construction_piece")
            upper.kind, upper.yaw, upper.complete, upper.pos = "floor", 0, true, Vector(32, 32, 144)
            aimTrace = {
                Hit = true, HitWorld = false, Entity = upper,
                HitNormal = Vector(0, 0, 1), HitPos = Vector(10, 10, 152)
            }
            builder.weapon.piece, builder.viewYaw = "stairs", 0
            local before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            stairs = #created > before and created[#created] or nil
            if stairs then
                stairs.complete = true
                aimTrace.Entity, aimTrace.HitPos = stairs, Vector(64, 32, 184)
                builder.weapon.piece = "floor"
                before = #created
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
                nextFloor = #created > before and created[#created] or nil
            end
        """)
        g = self.lua.globals()
        self.assertIsNotNone(g.stairs)
        self.assertEqual((g.stairs.pos.x, g.stairs.pos.y, g.stairs.pos.z), (64, 32, 152))
        self.assertIsNotNone(g.nextFloor)
        self.assertEqual((g.nextFloor.pos.x, g.nextFloor.pos.y, g.nextFloor.pos.z), (160, 32, 280))

    def test_adjacent_upper_floor_must_remain_inside_the_claim(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            support = ents.Create("zn_construction_piece")
            support.kind, support.yaw, support.complete, support.pos = "floor", 0, true, Vector(288, 32, 144)
            aimTrace = {
                Hit = true, HitWorld = false, Entity = support,
                HitNormal = Vector(0, 0, 1), HitPos = Vector(319, 32, 152)
            }
            builder.weapon.piece, builder.viewYaw = "floor", 0
            local before = #created
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            outsidePlaced = #created > before
            outsideMessage = builder.messages[#builder.messages]
        """)
        g = self.lua.globals()
        self.assertFalse(g.outsidePlaced)
        self.assertEqual(g.outsideMessage, "Pieces must be built inside your claim.")

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
            initialProgress = piece.progress
            -- A later E press starts another visible contribution; holding it accrues elapsed time.
            ZM_Construction:Contribute(builder, piece, 105)
            afterGap = piece.progress
            for tick = 1, 3 do ZM_Construction:Contribute(builder, piece, 105 + tick * 0.25) end
            nearlyDone = piece.progress
            ZM_Construction:Contribute(builder, piece, 106)
            done = piece.complete
            group = piece.group
            again = ZM_Construction:Contribute(builder, piece, 106.25)
            mutationsAfter = mutations
        """)
        g = lua.globals()
        self.assertTrue(g.started)
        self.assertTrue(g.paidAfterStart)
        self.assertEqual(g.woodAfterPay, 6)
        self.assertEqual(g.backpack["itemScrapMetal"], 1)
        # A tap starts one second of work; a separate tap after a pause starts another second.
        self.assertAlmostEqual(g.initialProgress, 1 / 3)
        # Level 30 builds a 6 s foundation in 3 s: two one-second contributions plus 0.75 s.
        self.assertAlmostEqual(g.afterGap, 2 / 3)
        self.assertAlmostEqual(g.nearlyDone, 2.75 / 3)
        self.assertTrue(g.done)
        self.assertEqual(g.group, 0)
        self.assertFalse(g.again)
        self.assertEqual(g.mutationsAfter, 1)

    def test_zombie_damage_wears_breaks_and_free_repair_restores_pieces(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            local meta = getmetatable(Vector(0, 0, 0))
            meta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
            COLLISION_GROUP_DEBRIS = 1
            function AngleRand() return {} end
            function VectorRand() return Vector(0, 0, 0) end
            math.Rand = function(low) return low end
            removals = {}
            function SafeRemoveEntityDelayed(entity, delay) removals[#removals + 1] = delay end
            sounds = {}
            sound = { Play = function(path) sounds[#sounds + 1] = path end }
            net.WriteVector = function(value) table.insert(sentValues, value) end
            net.WriteNormal = function(value) table.insert(sentValues, value) end
            net.SendPVS = function() hits = hits + 1 end
            hits, sentValues = 0, {}
            local createPiece = ents.Create
            gibs = {}
            ents.Create = function(class)
                local entity = createPiece(class)
                if class == "prop_physics" then
                    table.remove(created)
                    function entity:SetModel(value) self.model = value end
                    function entity:SetAngles() end
                    function entity:GetPhysicsObject() return nil end
                    gibs[#gibs + 1] = entity
                end
                return entity
            end
            health = {}
            for _, kind in ipairs({ "wall", "wall_half", "foundation", "stairs" }) do
                health[kind] = ZM_Construction.MaxHealth(kind)
            end
            stages = {}
            for _, wear in ipairs({ 0, 0.1, 0.3, 0.6, 0.9, 1 }) do
                stages[#stages + 1] = ZM_Construction.DamageStage(wear)
            end

            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            wall = created[1]
            wall:SetPieceKind("wall")
            ZM_Construction:CompletePiece(wall)
            zombie = makeZombie()
            stageSoundsBefore = #sounds
            for strike = 1, 50 do
                assert(not ZM_Construction:DamagePiece(wall, 1, zombie, Vector(0, 0, 32), Vector(0, 1, 0)))
            end
            quarterWear = wall:GetWear()
            quarterStage = ZM_Construction.DamageStage(wall:GetWear())
            ignoredDamage = ZM_Construction:DamagePiece(wall, 0, zombie, Vector(0, 0, 32), Vector(0, 1, 0))

            builder.weapon.build = false
            refused = ZM_Construction:Contribute(builder, wall, 200)
            refusal = builder.messages[#builder.messages]
            builder.weapon.build = true
            woodBefore, mutationsBefore = backpack.itemWood, mutations
            repaired = ZM_Construction:Contribute(builder, wall, 201)
            local tick = 201
            while wall:GetWear() > 0 and tick < 260 do
                tick = tick + 0.25
                ZM_Construction:Contribute(builder, wall, tick)
            end
            repairedWear = wall:GetWear()
            repairMessage = builder.messages[#builder.messages]
            fullRepair = ZM_Construction:Contribute(builder, wall, tick + 0.25)
            repairFree = backpack.itemWood == woodBefore and mutations == mutationsBefore

            brokeEarly = false
            for strike = 1, health.wall - 1 do
                brokeEarly = brokeEarly or ZM_Construction:DamagePiece(wall, 1, zombie, Vector(0, 0, 32), Vector(0, 1, 0))
            end
            validBeforeLast = wall.valid
            broke = ZM_Construction:DamagePiece(wall, 1, zombie, Vector(0, 0, 32), Vector(0, 1, 0))
            afterBreak = ZM_Construction:DamagePiece(wall, 1, zombie, Vector(0, 0, 32), Vector(0, 1, 0))
        """)
        g = lua.globals()
        # One walker at one strike per 1.5 s breaks a 3-wood wall in 300 s; other pieces scale with wood.
        self.assertEqual(
            (g.health["wall"], g.health["wall_half"], g.health["foundation"], g.health["stairs"]),
            (200, 134, 267, 400),
        )
        self.assertEqual(list(g.stages.values()), [0, 1, 2, 3, 4, 4])
        self.assertAlmostEqual(g.quarterWear, 0.25)
        self.assertEqual(g.quarterStage, 1)
        self.assertFalse(g.ignoredDamage)
        self.assertFalse(g.refused)
        self.assertEqual(g.refusal, "Hold the Hammer in build mode to repair.")
        self.assertTrue(g.repaired)
        self.assertEqual(g.repairedWear, 0)
        self.assertEqual(g.repairMessage, "Repair complete.")
        self.assertFalse(g.fullRepair)
        self.assertTrue(g.repairFree)
        self.assertFalse(g.brokeEarly)
        self.assertTrue(g.validBeforeLast)
        self.assertTrue(g.broke)
        self.assertFalse(g.wall["valid"])
        self.assertFalse(g.afterBreak)
        self.assertGreaterEqual(len(g.gibs), 4)
        self.assertEqual(len(g.removals), len(g.gibs))
        self.assertEqual(g.ZM_Construction.BrokenCount, 1)
        # Every landed hit sends one splinter message: 50 + full health (the ignored and post-break hits send none).
        self.assertEqual(g.hits, 50 + 200)
        self.assertIn("physics/wood/wood_strain", "".join(str(v) for v in g.sounds.values()))

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

    def test_claim_review_cannot_contribute_paid_materials(self):
        self.lua.execute("""
            target = { ZM_ClaimReviewSessionId = "fixture-review" }
            allowed, reason = ZM_Construction:PayForPiece(target, nil, nil)
        """)
        self.assertFalse(self.lua.globals().allowed)
        self.assertEqual(
            self.lua.globals().reason,
            "Paid construction is disabled during the claim review."
        )

    def test_payment_write_failure_is_reported_without_consuming_items_or_progress(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            failPaymentSave = true
            result = ZM_Construction:Contribute(builder, piece, 100)
            message = builder.messages[#builder.messages]
        """)
        g = self.lua.globals()
        self.assertFalse(g.result)
        self.assertFalse(g.piece.paid)
        self.assertEqual(g.piece.progress, 0)
        self.assertEqual((g.backpack["itemWood"], g.backpack["itemScrapMetal"]), (10, 3))
        self.assertEqual(g.message, "Could not save construction materials; check the server log.")
        self.assertIn("injected payment write failure", g.paymentErrors[1])

    def test_claim_review_builds_only_matching_blueprints_for_free(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            builder.weapon.level = 30
            builder.ZM_ClaimReviewSessionId = "fixture-review"
            ZM_ClaimReviewTest = { Active = { id = "fixture-review", target = builder } }
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            freePiece = created[1]
            freeTag = freePiece.ZM_ClaimReviewSessionId
            freeStarted = ZM_Construction:Contribute(builder, freePiece, 100)
            freeProgress = freePiece.progress
            paidAfterFreeStart = freePiece.paid
            mutationsAfterFreeStart = mutations
            for tick = 1, 8 do ZM_Construction:Contribute(builder, freePiece, 100 + tick * 0.25) end
            freeComplete = freePiece.complete
            completionMessage = builder.messages[#builder.messages]
            -- A differently tagged piece must still hit the review payment guard.
            aimTrace.HitPos = Vector(100, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            mismatchedPiece = created[2]
            mismatchedPiece.ZM_ClaimReviewSessionId = "another-review"
            mismatched = ZM_Construction:Contribute(builder, mismatchedPiece, 103)
            mismatchedProgress = mismatchedPiece.progress
            mismatchMessage = builder.messages[#builder.messages]
            aimTrace.HitPos = Vector(164, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            inactivePiece = created[3]
            ZM_ClaimReviewTest.Active = nil
            inactive = ZM_Construction:Contribute(builder, inactivePiece, 104)
            inactiveProgress = inactivePiece.progress
        """)
        g = lua.globals()
        self.assertEqual(g.freeTag, "fixture-review")
        self.assertTrue(g.freeStarted)
        self.assertAlmostEqual(g.freeProgress, 1 / 3)
        self.assertFalse(g.paidAfterFreeStart)
        self.assertEqual(g.mutationsAfterFreeStart, 0)
        self.assertTrue(g.freeComplete)
        self.assertEqual(g.completionMessage, "Review blueprint complete; no materials were used.")
        self.assertFalse(g.mismatched)
        self.assertEqual(g.mismatchedProgress, 0)
        self.assertEqual(g.mismatchMessage, "Paid construction is disabled during the claim review.")
        self.assertFalse(g.inactive)
        self.assertEqual(g.inactiveProgress, 0)
        self.assertEqual(g.mutations, 0)

    def test_free_build_cheat_skips_payment_and_keeps_blueprint_unpaid(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            builder.weapon.level = 30
            builder.ZM_CheatFreeBuild = true
            backpack = {}
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            started = ZM_Construction:Contribute(builder, piece, 100)
            startMessage = builder.messages[#builder.messages]
            paidAfterStart = piece.paid
            for tick = 1, 8 do ZM_Construction:Contribute(builder, piece, 100 + tick * 0.25) end
            complete = piece.complete
            completionMessage = builder.messages[#builder.messages]
            mutationsWhileFree = mutations
            -- Without the cheat the same empty backpack is refused.
            builder.ZM_CheatFreeBuild = false
            aimTrace.HitPos = Vector(100, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            paidPiece = created[2]
            refused = ZM_Construction:Contribute(builder, paidPiece, 103)
            refusedProgress = paidPiece.progress
        """)
        g = lua.globals()
        self.assertTrue(g.started)
        self.assertEqual(g.startMessage, "Free building cheat: no materials are used.")
        self.assertFalse(g.paidAfterStart)
        self.assertTrue(g.complete)
        self.assertEqual(g.completionMessage, "Construction complete; no materials were used.")
        self.assertEqual(g.mutationsWhileFree, 0)
        self.assertFalse(g.refused)
        self.assertEqual(g.refusedProgress, 0)

    def test_completion_waits_while_someone_stands_inside(self):
        self.install_placement_mocks()
        lua = self.lua
        lua.execute("""
            builder = makeBuilder()
            builder.weapon.level = 30
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            ZM_Construction:Contribute(builder, piece, 100)
            for tick = 1, 7 do ZM_Construction:Contribute(builder, piece, 100 + tick * 0.25) end
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

    def test_catalogue_geometry_and_cardinal_rotations(self):
        pieces = self.construction.Pieces
        expected = {
            "foundation", "foundation_half", "foundation_triangle",
            "floor", "floor_half", "floor_triangle",
            "wall", "wall_half", "wall_doorway", "wall_window",
            "roof_flat", "roof_slope", "roof_corner_outer", "roof_corner_inner",
            "stairs", "ramp",
        }
        order = list(self.construction.PieceOrder.values())
        self.assertEqual(set(order), expected)
        self.assertEqual(len(order), len(expected))
        self.assertEqual(set(pieces.keys()), expected)
        self.assertEqual(self.construction.PieceBounds("foundation", 0), (-32, -32, 0, 32, 32, 16))
        self.assertEqual(self.construction.PieceBounds("wall", 0), (-32, -4, 0, 32, 4, 128))
        self.assertEqual(self.construction.PieceBounds("wall", 90), (-4, -32, 0, 4, 32, 128))
        self.assertEqual(self.construction.PieceBounds("stairs", 0), (-64, -32, 0, 64, 32, 128))
        self.assertEqual(self.construction.PieceBounds("stairs", 90), (-32, -64, 0, 32, 64, 128))
        self.assertEqual(self.construction.PieceBounds("roof_slope", 0), (-32, -32, 0, 32, 32, 40))

        for kind in order:
            piece = pieces[kind]
            self.assertGreater(piece["buildSeconds"], 0, kind)
            self.assertGreater(piece["cost"]["itemWood"], 0, kind)
            base = self.construction.GetParts(kind, 0)
            self.assertGreater(len(base), 0, kind)
            for yaw in (0, 90, 180, 270):
                rotated = self.construction.GetParts(kind, yaw)
                self.assertEqual(len(rotated), len(base), (kind, yaw))
                for source, part in zip(base.values(), rotated.values()):
                    vertices = list(part["vertices"].values())
                    self.assertGreaterEqual(len(vertices), 6, (kind, yaw))
                    self.assertGreater(part["maxX"] - part["minX"], 0, (kind, yaw))
                    self.assertGreater(part["maxY"] - part["minY"], 0, (kind, yaw))
                    self.assertGreater(part["maxZ"] - part["minZ"], 0, (kind, yaw))
                    for original, vertex in zip(source["vertices"].values(), vertices):
                        x, y = original[1], original[2]
                        expected_xy = {
                            0: (x, y), 90: (-y, x), 180: (-x, -y), 270: (y, -x),
                        }[yaw]
                        self.assertEqual((vertex[1], vertex[2], vertex[3]), (*expected_xy, original[3]))
                    for face in part["faces"].values():
                        self.assertGreaterEqual(len(face), 3)
                        self.assertTrue(all(1 <= index <= len(vertices) for index in face.values()))

    def test_openings_steps_and_roof_edges_have_expected_geometry(self):
        def part_contains(part, x, y, z):
            return (part["minX"] < x < part["maxX"] and part["minY"] < y < part["maxY"]
                    and part["minZ"] < z < part["maxZ"])

        def in_box_parts(kind, x, y, z):
            return any(part_contains(part, x, y, z) for part in self.construction.GetParts(kind, 0).values())

        self.assertFalse(in_box_parts("wall_doorway", 0, 0, 36))
        self.assertTrue(in_box_parts("wall_doorway", -28, 0, 36))
        self.assertTrue(in_box_parts("wall_doorway", 0, 0, 120))
        self.assertFalse(in_box_parts("wall_window", 0, 0, 64))
        self.assertTrue(in_box_parts("wall_window", 0, 0, 20))
        self.assertTrue(in_box_parts("wall_window", 28, 0, 64))

        stairs = list(self.construction.GetParts("stairs", 0).values())
        self.assertEqual(len(stairs), 8)
        for index, part in enumerate(stairs):
            self.assertEqual(
                (part["minX"], part["maxX"], part["minY"], part["maxY"], part["minZ"], part["maxZ"]),
                (-64 + 16 * index, -48 + 16 * index, -32, 32, 0, 16 * (index + 1)),
            )
        ramp_vertices = list(self.construction.GetParts("ramp", 0)[1]["vertices"].values())
        self.assertEqual(max(v[3] for v in ramp_vertices if v[1] == -64), 8)
        self.assertEqual(max(v[3] for v in ramp_vertices if v[1] == 64), 128)

        def top_heights(kind, x, y):
            return {
                v[3]
                for part in self.construction.GetParts(kind, 0).values()
                for v in part["vertices"].values()
                if v[1] == x and v[2] == y
            }

        self.assertEqual(top_heights("roof_slope", -32, 32), {0, 8})
        self.assertEqual(top_heights("roof_slope", 32, 32), {32, 40})
        self.assertEqual(top_heights("roof_corner_outer", -32, 32), {0, 8})
        self.assertEqual(top_heights("roof_corner_outer", 32, 32), {32, 40})
        self.assertEqual(top_heights("roof_corner_inner", -32, -32), {0, 8})
        self.assertEqual(top_heights("roof_corner_inner", 32, -32), {32, 40})

        for kind in ("foundation_triangle", "floor_triangle"):
            vertices = list(self.construction.GetParts(kind, 0)[1]["vertices"].values())
            area = abs(sum(
                vertices[i][1] * vertices[(i + 1) % 3][2]
                - vertices[(i + 1) % 3][1] * vertices[i][2]
                for i in range(3)
            )) / 2
            self.assertEqual(area, 64 * 64 / 2)

    def test_catalogue_provisional_prices_and_level_eight_times(self):
        expected = {
            "foundation": (4, 2, 6), "foundation_half": (2, 1, 3), "foundation_triangle": (2, 1, 3),
            "floor": (3, 1, 4), "floor_half": (2, 1, 3), "floor_triangle": (2, 1, 3),
            "wall": (3, 1, 4), "wall_half": (2, 1, 3), "wall_doorway": (3, 1, 4),
            "wall_window": (3, 1, 4), "roof_flat": (3, 1, 4), "roof_slope": (3, 1, 4),
            "roof_corner_outer": (3, 1, 4), "roof_corner_inner": (3, 1, 4),
            "stairs": (6, 2, 8), "ramp": (5, 2, 6),
        }
        self.assertEqual(set(expected), set(self.construction.PieceOrder.values()))
        for kind, (wood, scrap, seconds) in expected.items():
            with self.subTest(kind=kind):
                cost = self.construction.MaterialCost(kind, False)
                self.assertEqual((cost.itemWood, cost.itemScrapMetal), (wood, scrap))
                self.assertEqual(self.construction.BuildSeconds(self.construction, kind, 8), seconds)

    def test_new_snaps_and_wall_variants_share_their_wall_slot(self):
        snap = self.construction.SnapPlacement
        self.assertEqual(snap("foundation_half", 10, 10, 16, 0), (32, 16, 16, 0))
        self.assertEqual(snap("foundation_half", 10, 10, 16, 90), (16, 32, 16, 90))
        self.assertEqual(snap("stairs", 10, 10, 16, 0), (64, 32, 16, 0))
        self.assertEqual(snap("stairs", 10, 10, 16, 90), (32, 64, 16, 90))
        self.assertEqual(snap("stairs", 10, 10, 16, 180), (0, 32, 16, 180))
        self.assertEqual(snap("stairs", 10, 10, 16, 270), (32, 0, 16, 270))
        self.assertEqual(snap("roof_slope", 10, 10, 16, 270), (32, 32, 16, 270))
        keys = {
            self.construction.SlotKey(kind, 32, 0, 16, 0)
            for kind in ("wall", "wall_half", "wall_doorway", "wall_window")
        }
        self.assertEqual(len(keys), 1)

    def test_selection_rechecks_piece_tool_protection_and_claim_access(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            chosen = ZM_Construction:SelectPiece(builder, "wall_window")
            chosenKind = builder.weapon.piece
            unknown, unknownReason = ZM_Construction:SelectPiece(builder, "not-a-piece")
            kindAfterUnknown = builder.weapon.piece
            claims[1].access = false
            lostClaim, claimReason = ZM_Construction:SelectPiece(builder, "stairs")
            claims[1].access = true
            builder.weapon.build = false
            disabled, disabledReason = ZM_Construction:SelectPiece(builder, "stairs")
            builder.weapon.build = true
            builder.alive = false
            dead = ZM_Construction:SelectPiece(builder, "stairs")
            builder.alive = true
            receivedKind = "roof_corner_inner"
            receivers["ZM.Construction.SelectPiece"](0, builder)
            fromNetwork = builder.weapon.piece
            receivedKind = "bogus"
            receivers["ZM.Construction.SelectPiece"](0, builder)
            afterBadNetwork = builder.weapon.piece
            networkMessage = builder.messages[#builder.messages]
        """)
        g = self.lua.globals()
        self.assertTrue(g.networkStrings["ZM.Construction.SelectPiece"])
        self.assertTrue(g.chosen)
        self.assertEqual(g.chosenKind, "wall_window")
        self.assertFalse(g.unknown)
        self.assertEqual(g.unknownReason, "Unknown construction piece.")
        self.assertEqual(g.kindAfterUnknown, "wall_window")
        self.assertFalse(g.lostClaim)
        self.assertEqual(g.claimReason, "Build mode needs a claim you can access in this cell.")
        self.assertFalse(g.disabled)
        self.assertEqual(g.disabledReason, "Hold the Hammer in build mode to select a piece.")
        self.assertFalse(g.dead)
        self.assertEqual(g.fromNetwork, "roof_corner_inner")
        self.assertEqual(g.afterBadNetwork, "roof_corner_inner")
        self.assertEqual(g.networkMessage, "Unknown construction piece.")

    def test_failed_collision_does_not_register_a_blueprint(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            failCollision = true
            failed, reason = ZM_Construction:PlacePiece(builder, builder.weapon, "wall_doorway",
                0, 32, 0, 90)
            registered = next(ZM_Construction.SlotRegistry) ~= nil
            removed = not created[1].valid
            failCollision = false
            retry = ZM_Construction:PlacePiece(builder, builder.weapon, "wall_doorway",
                0, 32, 0, 90)
        """)
        g = self.lua.globals()
        self.assertFalse(g.failed)
        self.assertEqual(g.reason, "Could not initialize the construction piece's collision.")
        self.assertFalse(g.registered)
        self.assertTrue(g.removed)
        self.assertTrue(g.retry.valid)

    def test_occupancy_checks_frame_parts_and_individual_steps(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            builder.weapon.piece = "wall_doorway"
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            doorway = created[1]
            person = makePlayer(0, 0)
            function person:IsNPC() return false end
            function ents.FindInBox(mins, maxs)
                local p = person.pos
                if p.x - 16 < maxs.x and p.x + 16 > mins.x
                    and p.y - 16 < maxs.y and p.y + 16 > mins.y
                    and p.z < maxs.z and p.z + 72 > mins.z then
                    return { person }
                end
                return {}
            end
            -- The doorway is centred at x=0, y=32 for this aim.
            person.pos = Vector(0, 32, 0)
            insideOpening = ZM_Construction:Occupied(doorway)
            person.pos = Vector(0, 52, 0)
            insidePost = ZM_Construction:Occupied(doorway)
            person.pos = Vector(0, 32, 70)
            insideLintel = ZM_Construction:Occupied(doorway)
            builder.weapon.piece = "stairs"
            aimTrace.HitPos = Vector(10, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            stair = created[2]
            person.pos = Vector(8, 32, 70)
            aboveLowStep = ZM_Construction:Occupied(stair)
            person.pos = Vector(120, 32, 40)
            insideHighStep = ZM_Construction:Occupied(stair)
        """)
        g = self.lua.globals()
        self.assertFalse(g.insideOpening)
        self.assertTrue(g.insidePost)
        self.assertTrue(g.insideLintel)
        self.assertFalse(g.aboveLowStep)
        self.assertTrue(g.insideHighStep)

    def test_successful_contributions_throttle_feedback_and_failures_are_silent(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            first = ZM_Construction:Contribute(builder, piece, 100)
            firstSounds, firstAnimations = builder.weapon.soundCount, builder.weapon.animationCount
            ZM_Construction:Contribute(builder, piece, 100.25)
            ZM_Construction:Contribute(builder, piece, 100.50)
            throttledSounds = builder.weapon.soundCount
            ZM_Construction:Contribute(builder, piece, 100.75)
            laterSounds, laterAnimations = builder.weapon.soundCount, builder.weapon.animationCount
            sound = builder.weapon.lastSound
            playerAnimation = builder.lastAnimation
            aimTrace.HitPos = Vector(100, 10, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            backpack = { itemWood = 0, itemScrapMetal = 0 }
            denied = ZM_Construction:Contribute(builder, created[2], 102)
            soundsAfterDenied = builder.weapon.soundCount
        """)
        g = self.lua.globals()
        self.assertTrue(g.first)
        self.assertEqual((g.firstSounds, g.firstAnimations, g.throttledSounds), (1, 1, 1))
        self.assertEqual((g.laterSounds, g.laterAnimations), (2, 2))
        self.assertIn(g.sound, {
            f"physics/wood/wood_plank_impact_hard{number}.wav" for number in range(1, 4)
        })
        self.assertEqual(g.playerAnimation, 2)
        self.assertFalse(g.denied)
        self.assertEqual(g.soundsAfterDenied, 2)

    def test_secondary_only_undoes_owned_blueprints_and_refunds_paid_cost(self):
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
            builder.weapon.mastercraft = true
            ZM_Construction:Contribute(builder, piece, now)
            paid, paidCost = piece:GetPaid(), piece.ZM_PaidCost
            ZM_Construction:SecondaryBuild(builder, builder.weapon)
            removed = not piece.valid
            removedMessage = builder.messages[#builder.messages]
            slotFree = next(ZM_Construction.SlotRegistry) == nil
            refundedWood, refundedScrap = backpack.itemWood, backpack.itemScrapMetal
        """)
        g = lua.globals()
        self.assertIsNone(g.otherSelected)
        self.assertTrue(g.stillThere)
        self.assertTrue(g.paid)
        self.assertEqual((g.paidCost.itemWood, g.paidCost.itemScrapMetal), (2, 1))
        self.assertTrue(g.removed)
        self.assertEqual(g.removedMessage, "Structure removed; materials refunded.")
        self.assertEqual((g.refundedWood, g.refundedScrap), (10, 3))
        self.assertTrue(g.slotFree)

    def test_secondary_does_not_remove_paid_structure_when_refund_fails(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            piece.paid, piece.complete = true, false
            piece.ZM_PaidCost = { itemWood = 4, itemScrapMetal = 2 }
            aimTrace.Entity = piece
            failPaymentSave = true
            ZM_Construction:SecondaryBuild(builder, builder.weapon)
            stillThere = piece.valid
            message = builder.messages[#builder.messages]
            wood, scrap = backpack.itemWood, backpack.itemScrapMetal
        """)
        g = self.lua.globals()
        self.assertTrue(g.stillThere)
        self.assertEqual((g.wood, g.scrap), (10, 3))
        self.assertIn("Could not refund materials", g.message)

    def test_secondary_leaves_completed_pieces_and_does_not_cycle(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            builder.ZM_CheatFreeBuild = true
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            ZM_Construction:Contribute(builder, piece, now)
            piece.complete = true
            aimTrace.Entity = piece
            ZM_Construction:SecondaryBuild(builder, builder.weapon)
            removed = not piece.valid
            selected = builder.weapon.piece
            wood, scrap = backpack.itemWood, backpack.itemScrapMetal
        """)
        g = self.lua.globals()
        self.assertFalse(g.removed)
        self.assertIsNone(g.selected)
        self.assertEqual((g.wood, g.scrap), (10, 3))

    def test_delete_selects_without_removing_and_refunds_the_batch_atomically(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            aimTrace.HitPos = Vector(96, 32, 0)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            for index, piece in ipairs(created) do
                piece.paid, piece.complete = true, true
                piece.ZM_PaidCost = { itemWood = index + 1, itemScrapMetal = 1 }
            end
            entered = ZM_Construction:ToggleDeleteMode(builder)
            for _, piece in ipairs(created) do
                aimTrace.Entity = piece
                ZM_Construction:PrimaryBuild(builder, builder.weapon)
            end
            assert(created[1].valid and created[2].valid and mutations == 0)
            assert(builder.ZM_ConstructionDeleteCount == 2)
            assert(created[1].ZM_ConstructionDeleteSelected and created[2].ZM_ConstructionDeleteSelected)
            refundStack = 2
            failRefundAdd = 3
            capacityResult = ZM_Construction:ToggleDeleteMode(builder)
            assert(created[1].valid and created[2].valid)
            assert(backpack.itemWood == 10 and backpack.itemScrapMetal == 3)
            assert(builder.ZM_ConstructionDeleteMode)
            failRefundAdd, failPaymentSave = nil, true
            writeResult = ZM_Construction:ToggleDeleteMode(builder)
            assert(created[1].valid and created[2].valid)
            assert(backpack.itemWood == 10 and backpack.itemScrapMetal == 3)
            failPaymentSave, refundAdds = false, 0
            result = ZM_Construction:ToggleDeleteMode(builder)
            assert(not created[1].valid and not created[2].valid)
            assert(backpack.itemWood == 15 and backpack.itemScrapMetal == 5)
            assert(refundAdds == 4 and mutations == 3)
            assert(not builder.ZM_ConstructionDeleteMode and builder.ZM_ConstructionDeleteCount == 0)
            assert(next(ZM_Construction.SlotRegistry) == nil)
        """)
        self.assertTrue(self.lua.globals().entered)
        self.assertFalse(self.lua.globals().capacityResult)
        self.assertFalse(self.lua.globals().writeResult)
        self.assertTrue(self.lua.globals().result)

    def test_delete_revalidates_ownership_access_and_cancels_without_removal(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            piece.complete = true
            other = makeBuilder()
            aimTrace.Entity = piece
            ZM_Construction:ToggleDeleteMode(other)
            ZM_Construction:PrimaryBuild(other, other.weapon)
            assert(other.ZM_ConstructionDeleteCount == 0 and piece.valid)
            ZM_Construction:ToggleDeleteMode(builder)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            assert(builder.ZM_ConstructionDeleteCount == 0 and not piece.ZM_ConstructionDeleteSelected)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            claims[1].access = false
            allowed = ZM_Construction:ToggleDeleteMode(builder)
            assert(not allowed and piece.valid and mutations == 0)
            ZM_Construction:Clear(builder)
            assert(not builder.ZM_ConstructionDeleteMode and not piece.ZM_ConstructionDeleteSelected)
            assert(piece.valid and mutations == 0)
        """)

    def test_delete_free_pieces_and_empty_selections_need_no_inventory_mutation(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            piece = created[1]
            piece.complete = true
            aimTrace.Entity = piece
            ZM_Construction:ToggleDeleteMode(builder)
            ZM_Construction:PrimaryBuild(builder, builder.weapon)
            removed = ZM_Construction:ToggleDeleteMode(builder)
            assert(removed and not piece.valid and mutations == 0)
            ZM_Construction:ToggleDeleteMode(builder)
            empty = ZM_Construction:ToggleDeleteMode(builder)
            assert(empty and not builder.ZM_ConstructionDeleteMode and mutations == 0)
        """)

    def test_authored_shape_picking_respects_holes_rotations_and_inside_starts(self):
        self.install_placement_mocks()
        self.lua.execute("""
            local ray = ZM_Construction.RayPiece
            local origin = Vector(0, 0, 0)
            floorHit, floorNormal = ray("floor", 0, origin, Vector(25, 25, -20), Vector(0, 0, 50))
            topHit, topNormal = ray("floor", 0, origin, Vector(25, 25, 20), Vector(0, 0, -50))
            assert(not ray("floor_triangle", 0, origin, Vector(25, 25, -20), Vector(0, 0, 50)))
            assert(ray("floor_triangle", 0, origin, Vector(-20, -20, -20), Vector(0, 0, 50)))
            assert(not ray("wall_doorway", 0, origin, Vector(0, -100, 60), Vector(0, 200, 0)))
            assert(ray("wall_doorway", 0, origin, Vector(28, -100, 60), Vector(0, 200, 0)))
            inside = ray("floor", 0, origin, Vector(0, 0, 4), Vector(100, 0, 0))
            for kind in pairs(ZM_Construction.Pieces) do
                for yaw = 0, 270, 90 do
                    for _, part in ipairs(ZM_Construction.GetParts(kind, yaw)) do
                        local x, y = 0, 0
                        for _, vertex in ipairs(part.vertices) do x, y = x + vertex[1], y + vertex[2] end
                        local hit, normal = ray(kind, yaw, origin,
                            Vector(x / #part.vertices, y / #part.vertices, 1000), Vector(0, 0, -1100))
                        assert(hit and hit >= 0 and hit <= 1 and normal.z > 0, kind .. ":" .. yaw)
                    end
                end
            end
        """)
        g = self.lua.globals()
        self.assertAlmostEqual(g.floorHit, 0.4)
        self.assertAlmostEqual(g.topHit, 0.24)
        self.assertEqual((g.floorNormal.z, g.topNormal.z), (-1, 1))
        self.assertAlmostEqual(g.inside, 0.32)

    def test_floating_blueprints_use_authored_shapes_reach_and_world_occlusion(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            for index = 1, 2 do
                local piece = ents.Create(ZM_Construction.PieceClass)
                piece.kind, piece.pos = "floor", Vector(0, 0, 600 - index * 100)
            end
            ents.FindByClass = function() return created end
            function builder:GetLevelAim() return Vector(25, 25, 36), Vector(0, 0, 1) end
            aimTrace = { Hit = false, Fraction = 1 }
            short = ZM_Construction:AimTrace(builder)
            picked = ZM_Construction:AimTrace(builder, ZM_Construction.DeleteReach)
            assert(picked.Entity == created[2] and picked.HitPos.z == 400)
            assert(not created[2].complete)
            created[2].ZM_ConstructionRemoving = true
            assert(ZM_Construction:AimTrace(builder, 1024).Entity == created[1])
            aimTrace = { Hit = true, HitWorld = true, Fraction = 0.2 }
            blocked = ZM_Construction:AimTrace(builder, 1024)
            assert(blocked.HitWorld)
        """)
        self.assertFalse(self.lua.globals().short.Hit)

    def test_storey_projection_extends_the_cursor_side_from_off_centre(self):
        self.install_placement_mocks()
        self.lua.execute("""
            builder = makeBuilder()
            support = ents.Create(ZM_Construction.PieceClass)
            support.kind, support.pos, support.complete = "floor", Vector(32, 32, 144), true
            builder.ground, builder.pos = support, Vector(55, 10, 152)
            local miss = { Hit = true, HitWorld = true, HitPos = Vector(0, 0, 0) }
            for _, case in ipairs({
                { 160, 32, 96, 32 }, { -96, 32, -32, 32 },
                { 32, 160, 32, 96 }, { 32, -96, 32, -32 }
            }) do
                local trace = ZM_Construction:StandingTrace(builder, "floor", miss,
                    Vector(case[1], case[2], 200), Vector(0, 0, -1), 256)
                assert(trace.ZM_AimPlane)
                local x, y, z = ZM_Construction.ResolvePlacement("floor", trace, 0)
                assert(x == case[3] and y == case[4] and z == 144)
            end
            far = ZM_Construction:StandingTrace(builder, "floor", miss,
                Vector(200, 32, 1000), Vector(0, 0, -1), 256)
            assert(far == miss)
        """)


if __name__ == "__main__":
    unittest.main()
