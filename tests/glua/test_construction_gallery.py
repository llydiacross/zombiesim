"""Exercise the construction gallery's real client lifecycle with explicit UI fixtures."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2] / "gamemode"


class ConstructionGalleryTests(unittest.TestCase):
    def setUp(self):
        names = [
            "sh_construction.lua", "cl_construction_geometry.lua",
            "cl_construction.lua", "cl_construction_gallery.lua", "cl_dev_profiler.lua",
        ]
        runner = FixtureRunner(ROOT, names)
        self.lua = runner.lua
        self.lua.execute("""
            math.Clamp = function(value, low, high) return math.min(math.max(value, low), high) end
            function IsValid(value) return value ~= nil and value.valid == true end
            function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
            local vectorMeta = {}
            vectorMeta.__index = vectorMeta
            vectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
            vectorMeta.__mul = function(a, n) return Vector(a.x * n, a.y * n, a.z * n) end
            function vectorMeta:SetUnpacked(x, y, z) self.x, self.y, self.z = x, y, z end
            function Vector(x, y, z)
                return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vectorMeta)
            end
            function Material() return {
                IsError = function() return false end,
                GetShader = function() return "UnlitGeneric" end,
                GetTexture = function() return { Width = function() return 128 end } end
            } end
            function ScrW() return 1280 end
            function ScrH() return 720 end
            function RealTime() return 10 end
            function FrameNumber() return 10 end
            game = { GetMap = function() return "fixture_map" end }
            ZM_World = { ActiveProfile = "preview" }
            errors, writes, encodedReports = {}, {}, {}
            function ErrorNoHalt(message) errors[#errors + 1] = message end
            util = {
                TableToJSON = function(value)
                    encodedReports[#encodedReports + 1] = value
                    if encodeFailure then return nil end
                    return "{}"
                end
            }
            file = {
                CreateDir = function(path) assert(path == "zombiesim" or path == "zombiesim/screenshots") end,
                Write = function(path, value)
                    writes[#writes + 1] = { path = path, value = value }
                    return not writeFailure
                end
            }
            function GetConVar()
                return {
                    GetFloat = function() return 1 end,
                    GetInt = function() return 1 end,
                    GetBool = function() return true end
                }
            end
            captures = 0
            render = { Capture = function() captures = captures + 1; return "png" end }
            commands = {}
            concommand = { Add = function(name, callback) commands[name] = callback end }
            function table.GetKeys(source)
                local keys = {}
                for key in pairs(source) do keys[#keys + 1] = key end
                return keys
            end
            ZM_Items = { GetDefinition = function(_, id)
                if id == "itemWood" then return { name = "Wood" } end
                if id == "itemScrapMetal" then return { name = "Scrap Metal" } end
            end }
            local color = Color(80, 80, 80, 255)
            ZM_DermaSkin = { Palette = {
                raised = color, panel = color, redBright = color, border = color, muted = color, text = color
            } }
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2, 3
            TOP, FILL = 1, 2
            KEY_Q, KEY_DELETE, MOUSE_LEFT, MOUSE_RIGHT, MOUSE_4 = 17, 73, 107, 108, 110
            IN_ATTACK, IN_ATTACK2, IN_USE = 1, 2048, 32
            keyDown, leftDown, rightDown = false, false, false
            input = {
                IsKeyDown = function(code) assert(code == KEY_DELETE); return deleteDown == true end,
                LookupBinding = function(name) assert(name == "+menu"); return boundKey end,
                GetKeyCode = function(name)
                    assert(name == boundKey)
                    if name == "mouse4" then return MOUSE_4 end
                    return KEY_Q
                end,
                IsButtonDown = function(code)
                    assert(code == KEY_Q or code == MOUSE_4)
                    return keyDown
                end,
                IsMouseDown = function(code)
                    if code == MOUSE_LEFT then return leftDown end
                    if code == MOUSE_RIGHT then return rightDown end
                    error("Unexpected mouse button")
                end
            }
            boundKey = "q"
            gameUI, cursorVisible, focus = false, false, nil
            gui = {
                IsGameUIVisible = function() return gameUI end,
                EnableScreenClicker = function(value) cursorVisible = value end
            }
            createdPanels = {}
            vgui = {
                CursorVisible = function() return cursorVisible end,
                GetKeyboardFocus = function() return focus end
            }
            function vgui.Create(class, parent)
                local panel = { valid = true, class = class, parent = parent, children = {}, wide = 0, tall = 0 }
                createdPanels[#createdPanels + 1] = panel
                if parent then parent.children[#parent.children + 1] = panel end
                function panel:SetSkin(value) self.skin = value end
                function panel:SetTitle(value) self.title = value end
                function panel:SetSize(width, height) self.wide, self.tall = width, height end
                function panel:SetWide(width) self.wide = width end
                function panel:SetTall(height) self.tall = height end
                function panel:GetWide() return self.wide end
                function panel:Center() self.centered = true end
                function panel:MakePopup() focus = self end
                function panel:Dock(value) self.dock = value end
                function panel:DockMargin() end
                function panel:SetSpaceX(value) self.spaceX = value end
                function panel:SetSpaceY(value) self.spaceY = value end
                function panel:SetText(value) self.text = value end
                function panel:SetTooltip(value) self.tooltip = value end
                function panel:IsHovered() return self.hovered == true end
                function panel:Add(kind) return vgui.Create(kind, self) end
                function panel:Remove()
                    if not self.valid then return end
                    self.valid = false
                    if focus == self then focus = nil end
                    if self.OnRemove then self:OnRemove() end
                end
                return panel
            end
            ZM_UI = { transient = {} }
            function ZM_UI:OpenExclusive(panel)
                for other in pairs(self.transient) do if other ~= panel then other:Remove() end end
                self.transient[panel] = true
                gui.EnableScreenClicker(true)
            end
            function ZM_UI:UnregisterTransient(panel)
                self.transient[panel] = nil
                for other in pairs(self.transient) do if IsValid(other) then return end end
                gui.EnableScreenClicker(false)
            end
            local colorCalls, polygonCalls = 0, 0
            surface = {
                SetDrawColor = function() colorCalls = colorCalls + 1 end,
                DrawRect = function() end, DrawOutlinedRect = function() end, DrawLine = function() end,
                DrawPoly = function(points) assert(#points >= 3); polygonCalls = polygonCalls + 1 end
            }
            draw = { SimpleText = function() end, NoTexture = function() end, RoundedBox = function() end }
            hooks = {}
            hook = { Add = function(event, name, callback) hooks[event .. "/" .. name] = callback end }
            sent, receives = {}, {}
            local current
            net = {
                Receive = function(name, callback) receives[name] = callback end,
                Start = function(name) current = { name = name } end,
                WriteString = function(value) current.value = value end,
                SendToServer = function() sent[#sent + 1] = current; current = nil end
            }
            weapon = { valid = true, build = true, kind = "foundation" }
            function weapon:GetClass() return self.class or "weapon_zn_hammer" end
            function weapon:GetBuildMode() return self.build end
            function weapon:GetBuildPiece() return self.kind end
            function weapon:GetItemMastercraft() return false end
            player = { valid = true, alive = true, weapon = weapon }
            function player:Alive() return self.alive end
            function player:IsAdmin() return self.admin ~= false end
            function player:GetActiveWeapon() return self.weapon end
            function player:GetNWBool(key, default) if self[key] == nil then return default end return self[key] end
            function player:GetNWInt(key, default) return self[key] or default end
            function player:GetGroundEntity() return self.ground end
            function player:GetPos() return self.pos or Vector(0, 0, 0) end
            function player:GetLevelAim() return Vector(0, 0, 36), Vector(1, 0, 0) end
            function LocalPlayer() return player end
            function makeCommand()
                local command = { removed = {} }
                function command:RemoveKey(key) self.removed[key] = true end
                return command
            end
        """)
        for name in names:
            runner.load(name)
        self.g = self.lua.globals()
        self.gallery = self.g.ZM_Construction.Gallery

    def test_delete_key_is_debounced_and_respects_ui_focus(self):
        self.lua.execute("""
            local key = hooks["Think/ZM.Construction.DeleteKey"]
            deleteDown = true
            key(); key()
            assert(#sent == 1 and sent[1].name == "ZM.Construction.Delete" and sent[1].value == nil)
            for _, blocked in ipairs({ "menu", "cursor", "focus", "tool", "dead" }) do
                deleteDown = false; key()
                gameUI, cursorVisible, focus = blocked == "menu", blocked == "cursor",
                    blocked == "focus" and { valid = true } or nil
                weapon.build, player.alive = blocked ~= "tool", blocked ~= "dead"
                deleteDown = true; key()
                assert(#sent == 1, blocked)
            end
            gameUI, cursorVisible, focus, weapon.build, player.alive = false, false, nil, true, true
            deleteDown = false; key()
            ZM_Construction.Gallery:Open()
            deleteDown = true; key()
            assert(#sent == 1)
        """)

    def test_delete_mode_suppresses_gallery_and_ghost_and_only_tints_own_selection(self):
        self.lua.execute("""
            ZM_Construction.Gallery:Open()
            player.ZM_ConstructionDeleteMode, player.ZM_ConstructionDeleteCount = true, 2
            hooks["Think/ZM.Construction.GalleryLifecycle"]()
            assert(not ZM_Construction.Gallery:IsOpen())
            assert(not ZM_Construction.Gallery:Open())
            assert(not ZM_Construction:GhostPlacement())
            assert(hooks["PlayerBindPress/ZM.Construction.GalleryBind"](player, "+menu", true))
            entity = { owner = player, selected = true }
            function entity:GetNWEntity() return self.owner end
            function entity:GetNWBool() return self.selected end
            assert(ZM_Construction:PieceSelectedForDeletion(entity))
            entity.owner = {}
            assert(not ZM_Construction:PieceSelectedForDeletion(entity))
            entity.owner, entity.selected = player, false
            assert(not ZM_Construction:PieceSelectedForDeletion(entity))
            status = ZM_Construction:ClientStatus()
            assert(status.deleteMode and status.deleteSelection == 2)
        """)

    def test_ghost_previews_the_same_upper_floor_and_roof_attachments(self):
        self.lua.execute("""
            function player:EyeAngles() return { y = self.yaw or 0 } end
            ZM_Construction.Client.tiles = { { tileX = 0, tileY = 0 } }
            local support = { valid = true, kind = "stairs", yaw = 0, pos = Vector(0, 32, 16), complete = true }
            function support:GetClass() return "zn_construction_piece" end
            function support:GetPieceKind() return self.kind end
            function support:GetPieceYaw() return self.yaw end
            function support:GetPos() return self.pos end
            function support:GetComplete() return self.complete end
            local trace = {
                Hit = true, HitWorld = false, Entity = support,
                HitNormal = Vector(0, 0, 1), HitPos = Vector(0, 32, 48)
            }
            function ZM_Construction:AimTrace() return trace end
            weapon.kind, player.yaw = "floor", 0
            floorKind, floorPos, floorYaw, floorValid = ZM_Construction:GhostPlacement()
            support.kind, support.yaw, support.pos = "wall", 90, Vector(0, 32, 16)
            trace.HitNormal, trace.HitPos = Vector(1, 0, 0), Vector(4, 32, 80)
            weapon.kind, player.yaw = "roof_flat", 180
            roofKind, roofPos, roofYaw, roofValid = ZM_Construction:GhostPlacement()
            support.kind, support.yaw, support.pos = "floor", 0, Vector(288, 32, 144)
            trace.HitNormal, trace.HitPos = Vector(0, 0, 1), Vector(319, 32, 152)
            weapon.kind, player.yaw = "floor", 0
            _, outsidePos, _, outsideValid = ZM_Construction:GhostPlacement()
            support.kind, support.yaw, support.pos = "stairs", 0, Vector(0, 32, 16)
            player.ground, player.pos = support, Vector(40, 30, 144)
            function ZM_Construction:AimTrace() return { Hit = false } end
            _, airPos, _, airValid = ZM_Construction:GhostPlacement()
        """)
        g = self.g
        self.assertEqual((g.airPos.x, g.airPos.y, g.airPos.z), (96, 32, 144))
        self.assertTrue(g.airValid)
        self.assertEqual(g.floorKind, "floor")
        self.assertEqual((g.floorPos.x, g.floorPos.y, g.floorPos.z, g.floorYaw), (96, 32, 144, 0))
        self.assertTrue(g.floorValid)
        self.assertEqual(g.roofKind, "roof_flat")
        self.assertEqual((g.roofPos.x, g.roofPos.y, g.roofPos.z, g.roofYaw), (32, 32, 144, 0))
        self.assertTrue(g.roofValid)
        self.assertEqual((g.outsidePos.x, g.outsidePos.y, g.outsidePos.z), (352, 32, 144))
        self.assertFalse(g.outsideValid)

    def test_ghost_previews_stairs_and_ramp_from_world_ground_in_open_air(self):
        self.lua.execute("""
            function player:EyeAngles() return { y = self.yaw or 0 } end
            ZM_Construction.Client.tiles = { { tileX = 0, tileY = 0 } }
            player.pos, player.yaw = Vector(40, 32, 0), 0
            player.ground = { valid = true, IsWorld = function() return true end }
            function ZM_Construction:AimTrace() return { Hit = false } end
            accessGhosts = {}
            for _, kind in ipairs({ "stairs", "ramp" }) do
                weapon.kind = kind
                local ghostKind, pos, yaw, valid = ZM_Construction:GhostPlacement()
                accessGhosts[kind] = { kind = ghostKind, pos = pos, yaw = yaw, valid = valid }
            end
        """)
        for kind in ("stairs", "ramp"):
            with self.subTest(kind=kind):
                ghost = self.g.accessGhosts[kind]
                self.assertEqual(ghost.kind, kind)
                self.assertEqual((ghost.pos.x, ghost.pos.y, ghost.pos.z, ghost.yaw), (64, 32, 0, 0))
                self.assertTrue(ghost.valid)

    def test_triangle_ghost_matches_diagonal_and_wall_attachments(self):
        self.lua.execute("""
            function player:EyeAngles() return { y = self.yaw or 0 } end
            ZM_Construction.Client.tiles = { { tileX = 0, tileY = 0 } }
            local support = { valid = true, kind = "floor_triangle", yaw = 0, pos = Vector(32, 32, 144), complete = true }
            function support:GetClass() return "zn_construction_piece" end
            function support:GetPieceKind() return self.kind end
            function support:GetPieceYaw() return self.yaw end
            function support:GetPos() return self.pos end
            function support:GetComplete() return self.complete end
            local trace = {
                Hit = true, HitWorld = false, Entity = support,
                HitNormal = Vector(0.707, 0.707, 0), HitPos = Vector(32, 32, 148)
            }
            function ZM_Construction:AimTrace() return trace end
            weapon.kind, player.yaw = "floor_triangle", 0
            _, diagonalPos, diagonalYaw, diagonalValid = ZM_Construction:GhostPlacement()
            support.kind, support.yaw, support.pos = "wall", 90, Vector(0, 32, 16)
            trace.HitNormal, trace.HitPos = Vector(1, 0, 0), Vector(4, 32, 80)
            player.yaw = 180
            _, wallPos, wallYaw, wallValid = ZM_Construction:GhostPlacement()
            support.complete = false
            _, _, _, unfinishedValid = ZM_Construction:GhostPlacement()
        """)
        g = self.g
        self.assertEqual((g.diagonalPos.x, g.diagonalPos.y, g.diagonalPos.z, g.diagonalYaw),
                         (32, 32, 144, 180))
        self.assertTrue(g.diagonalValid)
        self.assertEqual((g.wallPos.x, g.wallPos.y, g.wallPos.z, g.wallYaw), (32, 32, 144, 270))
        self.assertTrue(g.wallValid)
        self.assertFalse(g.unfinishedValid)

    def test_selecting_any_card_sends_its_own_id_and_closes(self):
        self.lua.execute("""
            for _, kind in ipairs(ZM_Construction.PieceOrder) do
                assert(hooks["PlayerBindPress/ZM.Construction.GalleryBind"](player, "+menu", true))
                local chosen
                for _, card in ipairs(ZM_Construction.Gallery.cards) do
                    if card.kind == kind then chosen = card end
                end
                assert(chosen and #chosen.preview > 0)
                chosen.DoClick()
                assert(not ZM_Construction.Gallery:IsOpen())
            end
        """)
        sent = list(self.g.sent.values())
        expected = list(self.g.ZM_Construction.PieceOrder.values())
        self.assertEqual(len(sent), 16)
        self.assertEqual([entry.name for entry in sent], ["ZM.Construction.SelectPiece"] * 16)
        self.assertEqual([entry.value for entry in sent], expected)
        self.assertFalse(self.g.cursorVisible)
        self.assertIsNone(self.g.focus)

    def test_only_eligible_build_mode_intercepts_q_and_other_ui_keeps_focus(self):
        self.lua.execute("""
            bind = hooks["PlayerBindPress/ZM.Construction.GalleryBind"]
            weapon.build = false
            inactive = bind(player, "+menu", true)
            weapon.build = true
            otherBind = bind(player, "+attack", true)
            otherFocus = { valid = true }
            focus = otherFocus
            focused = bind(player, "+menu", true)
            focus = nil
            cursorVisible = true
            cursor = bind(player, "+menu", true)
            cursorVisible = false
            gameUI = true
            paused = bind(player, "+menu", true)
            gameUI = false
            player.alive = false
            dead = bind(player, "+menu", true)
            player.alive = true
            weapon.class = "weapon_zn_crowbar"
            switched = bind(player, "+menu", true)
            weapon.class = nil
            opened = bind(player, "+menu", true)
            openFrame = ZM_Construction.Gallery.Frame
        """)
        g = self.g
        for name in ("inactive", "otherBind", "focused", "cursor", "paused", "dead", "switched"):
            self.assertIsNone(g[name], name)
        self.assertTrue(g.opened)
        self.assertTrue(g.openFrame.valid)
        self.assertEqual(g.openFrame.skin, "ZombieSim")
        self.assertTrue(g.cursorVisible)
        self.assertEqual(len(self.gallery.cards), 16)
        self.assertEqual(len(g.sent), 0)

    def test_q_key_and_escape_close_without_selection(self):
        self.lua.execute("""
            bind = hooks["PlayerBindPress/ZM.Construction.GalleryBind"]
            tick = hooks["Think/ZM.Construction.GalleryLifecycle"]
            bind(player, "+menu", true)
            keyDown = true
            tick()
            firstPressStillOpen = ZM_Construction.Gallery:IsOpen()
            keyDown = false
            tick()
            keyDown = true
            tick()
            secondPressClosed = not ZM_Construction.Gallery:IsOpen()
            keyDown = false
            bind(player, "+menu", true)
            consumed = bind(player, "+menu", true)
            bindClosed = not ZM_Construction.Gallery:IsOpen()
            bind(player, "+menu", true)
            escape = hooks["OnPauseMenuShow/ZM.Construction.GalleryEscape"]()
            escapeClosed = not ZM_Construction.Gallery:IsOpen()
            outsideEscape = hooks["OnPauseMenuShow/ZM.Construction.GalleryEscape"]()
        """)
        g = self.g
        self.assertTrue(g.firstPressStillOpen)
        self.assertTrue(g.secondPressClosed)
        self.assertTrue(g.consumed)
        self.assertTrue(g.bindClosed)
        self.assertFalse(g.escape)
        self.assertTrue(g.escapeClosed)
        self.assertIsNone(g.outsideEscape)
        self.assertEqual(len(g.sent), 0)
        self.assertFalse(g.cursorVisible)

    def test_lifecycle_closes_when_player_mode_or_ui_context_changes(self):
        self.lua.execute("""
            bind = hooks["PlayerBindPress/ZM.Construction.GalleryBind"]
            tick = hooks["Think/ZM.Construction.GalleryLifecycle"]
            bind(player, "+menu", true)
            player.alive = false; tick(); closedDead = not ZM_Construction.Gallery:IsOpen()
            player.alive = true
            bind(player, "+menu", true)
            weapon.build = false; tick(); closedMode = not ZM_Construction.Gallery:IsOpen()
            weapon.build = true
            bind(player, "+menu", true)
            weapon.class = "weapon_zn_crowbar"; tick(); closedWeapon = not ZM_Construction.Gallery:IsOpen()
            weapon.class = nil
            bind(player, "+menu", true)
            gameUI = true; tick(); closedPause = not ZM_Construction.Gallery:IsOpen()
            gameUI = false
            bind(player, "+menu", true)
            ZM_LauncherMenu = { Active = true }; tick(); closedLauncher = not ZM_Construction.Gallery:IsOpen()
        """)
        for name in ("closedDead", "closedMode", "closedWeapon", "closedPause", "closedLauncher"):
            self.assertTrue(self.g[name], name)
        self.assertFalse(self.g.cursorVisible)
        self.assertEqual(len(self.g.sent), 0)

    def test_rebound_mouse_button_closes_gallery_and_unbound_label_is_explicit(self):
        self.lua.execute("""
            boundKey = "mouse4"
            ZM_Construction.Gallery:Open()
            label = ZM_Construction.Gallery:BindingLabel()
            tick = hooks["Think/ZM.Construction.GalleryLifecycle"]
            keyDown = false; tick()
            keyDown = true; tick()
            closed = not ZM_Construction.Gallery:IsOpen()
            boundKey = nil
            unbound = ZM_Construction.Gallery:BindingLabel()
        """)
        self.assertEqual(self.g.label, "MOUSE4")
        self.assertTrue(self.g.closed)
        self.assertEqual(self.g.unbound, "Bind +menu")

    def test_gallery_swallows_build_inputs_until_selection_click_is_released(self):
        self.lua.execute("""
            bind = hooks["PlayerBindPress/ZM.Construction.GalleryBind"]
            createMove = hooks["CreateMove/ZM.Construction.GalleryInput"]
            bind(player, "+menu", true)
            during = makeCommand(); createMove(during)
            leftDown = true
            ZM_Construction.Gallery.cards[1].DoClick()
            held = makeCommand(); createMove(held)
            stillSuppressing = ZM_Construction.Gallery.releaseMouse
            leftDown = false
            released = makeCommand(); createMove(released)
            stoppedSuppressing = not ZM_Construction.Gallery.releaseMouse
            after = makeCommand(); createMove(after)
        """)
        g = self.g
        for command in (g.during, g.held, g.released):
            self.assertTrue(command.removed[1])
            self.assertTrue(command.removed[2048])
            self.assertTrue(command.removed[32])
        self.assertTrue(g.stillSuppressing)
        self.assertTrue(g.stoppedSuppressing)
        self.assertEqual(len(g.after.removed), 0)
        self.assertEqual(len(g.sent), 1)

    def test_cards_relayout_and_paint_with_shape_previews(self):
        self.lua.execute("""
            ZM_Construction.Gallery:Open()
            local grid = ZM_Construction.Gallery.cards[1].parent
            grid.OnSizeChanged(grid, 320)
            firstWidth = ZM_Construction.Gallery.cards[1].wide
            for _, card in ipairs(ZM_Construction.Gallery.cards) do
                card.Paint(card, card.wide, card.tall)
            end
        """)
        self.assertEqual(self.g.firstWidth, 156)
        self.assertTrue(all(card.wide == 156 for card in self.gallery.cards.values()))

    def test_preview_admin_status_is_written_and_failures_are_reported(self):
        self.lua.execute("""
            local status = commands["zombiesim_dev_construction_status"]
            player.admin = false
            status()
            ZM_World.ActiveProfile = "city"
            player.admin = true
            status()
            ZM_World.ActiveProfile = "preview"
            encodeFailure = true
            status()
            encodeFailure = false
            writeFailure = true
            status()
            writeFailure = false
            ZM_Construction.Gallery:Open()
            status()
        """)
        g = self.g
        self.assertEqual(len(g.errors), 4)
        self.assertIn("preview admin", g.errors[1])
        self.assertIn("preview admin", g.errors[2])
        self.assertIn("encode", g.errors[3])
        self.assertIn("write", g.errors[4])
        self.assertEqual(g.writes[2].path, "zombiesim/construction_status.json")
        report = g.encodedReports[3]
        self.assertEqual((report.map, report.profile), ("fixture_map", "preview"))
        self.assertTrue(report.galleryOpen)
        self.assertTrue(report.buildMode)
        self.assertEqual(report.materialShader, "UnlitGeneric")
        self.assertEqual(report.materialTextureWidth, 128)

    def test_gallery_screenshot_waits_for_the_vgui_render_pass(self):
        self.lua.execute("""
            ZM_Construction.Gallery:Open()
            commands["zombiesim_dev_capture"](nil, nil, { "construction_gallery" })
            hooks["PostRender/ZM.DevProfiler.Capture"]()
            beforeVgui = captures
            hooks["PostRenderVGUI/ZM.DevProfiler.CaptureUI"]()
        """)
        g = self.g
        self.assertEqual(g.beforeVgui, 0)
        self.assertEqual(g.captures, 1)
        self.assertEqual(g.writes[1].path, "zombiesim/screenshots/construction_gallery.png")
        self.assertEqual(g.writes[2].path, "zombiesim/screenshots/construction_gallery.json")
        self.assertTrue(g.encodedReports[1].afterVGUI)
        self.assertTrue(g.encodedReports[1].construction.galleryOpen)


if __name__ == "__main__":
    unittest.main()
