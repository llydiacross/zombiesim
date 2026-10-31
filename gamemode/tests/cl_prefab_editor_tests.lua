return function(createEngine, loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local gizmo = loadChunk("prefabs/sh_gizmo.lua")()
        local contract = loadChunk("prefabs/sh_contract.lua")()
        local env, state = createEngine(gizmo, contract, loadChunk("prefabs/sh_editor_map.lua")(),
            loadChunk("prefabs/cl_editor_transfer.lua")())
        local chunk = loadChunk("cl_prefab_editor.lua")
        setfenv(chunk, env)
        chunk()
        return env, state, env.ZM_PrefabEditorClient
    end
    local function selectRingAndStartDrag(editor, state, env)
        local panel = { capture = false, MouseCapture = function(self, value) self.capture = value end }
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel)
        state.now = state.now + 0.2
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        return panel
    end
    local function blank()
        return { schemaVersion = 1, id = "", name = "", description = "", tags = {},
            props = {}, lights = {}, particles = {} }
    end

    suite:Add("world placement captures the current cell without changing local props", function(check)
        local _, state, editor = fixture()
        state.map = "zz_preview_fixture"
        state:Response("status", true, "", {
            origin = { x = 640, y = -640, z = 36 },
            cell = { id = 302, x = 14, y = 0, tileX = 1, tileY = -1, tileSize = 640 },
            documents = {}
        })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.IdInput:SetValue("unique")
        editor.NameInput:SetValue("Unique")
        editor.PrefabHorizontalInputs.x:SetValue(12.5)
        editor.PrefabHorizontalInputs.y:SetValue(-20)
        editor.PrefabOffsetInput:SetValue(5)
        editor.WorldPlacementToggle:SetValue(1)
        local placement = editor.Document.worldPlacement
        check(placement and placement.enabled and placement.profile == "preview"
            and placement.cellX == 14 and placement.cellY == 0 and placement.tileX == 1 and placement.tileY == -1
            and placement.offset.x == 12.5 and placement.offset.y == -20 and placement.offset.z == 5,
            "enabling world placement captures the active cell, tile and preview XYZ")
        editor.WorldPlacementControls.tileX:SetValue(-2)
        editor.WorldOffsetControls.z:SetValue(7.5)
        editor.WorldAngleControls.y:SetValue(90)
        check(placement.tileX == -2 and placement.offset.z == 7.5 and placement.angles.y == 90
            and editor.Document.props[1].position.x == 0 and editor.Document.props[1].position.z == 0,
            "placement edits do not bake offsets into prop-local coordinates")
        editor.WorldPlacementToggle:SetValue(0)
        check(not placement.enabled and placement.angles.y == 90 and editor.WorldPlacementPanel.visible,
            "disabling keeps the placement editable")
        editor:UseCurrentWorldPlacement()
        check(placement.tileX == 1 and placement.offset.z == 5 and not placement.enabled,
            "capture refreshes the location without silently enabling it")
        editor:Save(false)
        local saved = state.json[state.requests[#state.requests].values[2]]
        check(saved.worldPlacement.cellX == 14 and saved.worldPlacement.angles.y == 90
            and not saved.worldPlacement.enabled, "save includes the explicit placement settings")
        local first = editor.ActiveTab
        editor:CreateTab(blank(), nil, true)
        check(editor.Document.worldPlacement == nil and not editor.WorldPlacementPanel.visible,
            "new tabs do not inherit another prefab's world placement")
        editor:ActivateTab(first)
        check(editor.Document.worldPlacement == placement and editor.WorldOffsetControls.z.value == 5,
            "returning to a tab restores its placement controls")
    end)

    suite:Add("suggested tags supplement custom text without duplicates", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 },
            documents = { { id = "other", name = "Other", tags = { "customExisting" } } } })
        editor.TagsInput:SetValue("customTag")
        editor.TagSuggestions:OnSelect(1, "burningCar", "burningCar")
        editor.TagSuggestions:OnSelect(1, "BURNINGCAR", "BURNINGCAR")
        check(#editor.Document.tags == 2 and editor.Document.tags[1] == "customTag"
            and editor.Document.tags[2] == "burningCar", "suggestions retain custom tags and reject duplicate casing")
        local found = false
        for _, choice in ipairs(editor.TagSuggestions.choices) do
            if choice.data == "customExisting" then found = true end
        end
        check(found, "suggestions also include tags from the saved library")
    end)

    suite:Add("horizontal prefab offsets stay independent per tab and survive map snapshots", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 10 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local first, revision = editor.ActiveTab, editor.Revision
        editor.PrefabHorizontalInputs.x:SetValue(20)
        check(editor.GridLines[1][1].x == -300 and editor.GridLines[1][1].y == -320,
            "the reported 20,0,0 offset moves the grid twenty units east")
        editor.PrefabHorizontalInputs.y:SetValue(-40)
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(editor.GridLines[1][1].x == -300 and editor.GridLines[1][1].y == -360
            and state.compassOrigin.x == 20 and state.compassOrigin.y == -40
            and editor.Origin.x == 0 and editor.Origin.y == 0,
            "grid and compass follow horizontal preview offsets without moving the base/reference origin")
        check(editor.Models[1].position.x == 20 and editor.Models[1].position.y == -40
            and editor.Document.props[1].position.x == 0 and editor.Revision == revision,
            "preview X/Y moves objects without dirtying or changing the document")
        local second = editor:CreateTab(blank(), nil, true)
        check(editor:GetPreviewOrigin().x == 0 and editor:GetPreviewOrigin().y == 0,
            "new tabs start at the unshifted origin")
        editor:ActivateTab(first)
        check(editor.Models[1].position.x == 20 and editor.PrefabHorizontalInputs.y.value == -40
            and editor.GridLines[1][1].x == -300,
            "tab activation restores X/Y before rebuilding models")
        editor:CaptureActiveTab()
        check(first.View.prefabOffsetX == 20 and first.View.prefabOffsetY == -40,
            "map transfer view state includes both horizontal offsets")
        editor:ActivateTab(second)
        check(editor.PrefabPreviewOffsetX == 0 and editor.PrefabPreviewOffsetY == 0,
            "horizontal preview state does not leak across tabs")
    end)

    suite:Add("editor opens and adds a validated model without mutating saved state", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(editor:IsActive() and #editor.GridLines == 22, "the 640-unit workspace opens")
        editor.IdInput:SetValue("test_prefab")
        editor.NameInput:SetValue("Test prefab")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(#editor.Document.props == 1 and editor.Document.props[1].model == "models/props_c17/oildrum001.mdl",
            "the model response adds a local prop")
        check(state.models[1].noDraw and editor.Dirty, "the preview is editor-owned and marked dirty")
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(state.models[1].drawn, "the owned model is rendered in the editor pass")
        check(state.compassLabels.N.y == 300 and state.compassLabels.S.y == -300
            and state.compassLabels.E.x == 300 and state.compassLabels.W.x == -300,
            "ground compass uses north +Y and east +X")
        check(state.compassOrigin.z == 2 and state.compassAngle.p == 0
            and state.compassAngle.y == 0 and state.compassScale == 1,
            "compass is placed just above the editor floor")
    end)

    suite:Add("guard authoring shares transforms, clothing and per-guard combat settings", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:AddGuard()
        check(#editor.Document.guards == 0, "guards cannot be added before the server weapon catalogue arrives")
        state:Response("guard_weapons", true, "", {
            { id = "pistol", label = "9mm Handgun", model = "models/weapons/w_pistol.mdl",
                range = 3000, damage = 12, delay = 0.2, spread = 0.02 },
            { id = "smg", label = "HL2 SMG", model = "models/weapons/w_smg1.mdl",
                range = 4000, damage = 14, delay = 0.1, spread = 0.03 }
        })
        editor:AddGuard()
        local guard = editor.Document.guards[1]
        check(guard and guard.guardId == "guard_1" and editor.Selected == "guard:guard_1"
            and editor.GuardPanel.visible and editor.Dirty, "a guard is created, selected and shown in its inspector")
        local firstModel = editor.GuardModels.guard_1.model
        editor.GuardName:SetValue("Alex")
        editor.GuardShirt:OnSelect(1, "shirt_blue", "shirt_blue")
        editor.GuardPants:OnSelect(1, "pants_black", "pants_black")
        editor.GuardWeapon:OnSelect(1, "HL2 SMG", "smg")
        check(guard.name == "Alex" and guard.shirt == "shirt_blue" and guard.pants == "pants_black"
            and guard.weapon == "smg" and not firstModel.valid,
            "name, clothing and weapon update the guard and replace the old preview")
        editor.GuardIdle:OnSelect(1, "idle_subtle", "idle_subtle")
        editor.GuardRange:SetValue(1200)
        editor.GuardOverrides[1].toggle:SetValue(1)
        editor.GuardOverrides[1].control:SetValue(25)
        editor.GuardOverrides[2].toggle:SetValue(1)
        editor.GuardOverrides[2].control:SetValue(0.075)
        editor.GuardOverrides[3].toggle:SetValue(1)
        editor.GuardOverrides[3].control:SetValue(0)
        check(guard.idle == "idle_subtle" and guard.range == 1200 and guard.damage == 25
            and guard.fireInterval == 0.075 and guard.spread == 0,
            "idle, range, damage, firing interval and accuracy are independently editable")
        editor.Inspector[1].control:SetValue(64)
        editor:SetPrefabPreviewOffset(50)
        local model = editor.GuardModels.guard_1.model
        check(guard.position.x == 64 and guard.position.z == 0 and model:GetPos().x == 64
            and model:GetPos().z == 50, "shared transform controls and preview-only height move the guard")
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(model.drawn, "guard preview participates in the existing editor render pass")
        local tab = editor.ActiveTab
        editor:CreateTab(blank(), nil, true)
        check(not model.valid and #editor.Document.guards == 0, "switching tabs removes the previous guard preview")
        editor:ActivateTab(tab)
        check(editor.Document.guards[1] == guard and editor.Selected == "guard:guard_1"
            and editor.GuardModels.guard_1.model:GetPos().z == 50,
            "returning to the tab restores the guard and its preview offset")
        editor.GuardOverrides[1].toggle:SetValue(0)
        check(guard.damage == nil, "an override can return to the weapon default")
    end)

    suite:Add("workflow panels start closed and switch without losing editor state", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(editor.ActiveArea == nil and not editor.AreaContainer.visible and editor.AreaContainer.wide == 0,
            "workflow panels start closed without reserving viewport width")
        check(editor.Frame.skin == "ZombieSim" and editor.Frame.padding[2] == 0
            and editor.PropList.headerHeight == 20 and editor.PropList.dataHeight == 20
            and type(editor.PropList.Paint) == "function",
            "the editor uses the game skin, full-screen toolbar and styled lists")
        check(editor.IdInput.parent == editor.AreaPanels.prefab:GetCanvas()
            and editor.ModelFolder.parent == editor.AreaPanels.place:GetCanvas()
            and editor.ReferenceChoice.parent == editor.AreaPanels.scene:GetCanvas()
            and editor.FogToggle.parent == editor.AreaPanels.scene:GetCanvas()
            and editor.PropList.parent == editor.InspectorPanel:GetCanvas()
            and editor.InspectorPanel.dock == 3, "prefab, placement and scene controls use their intended areas")
        editor.IdInput:SetValue("test_prefab")
        editor.AreaButtons.prefab:DoClick()
        check(editor.ActiveArea == "prefab" and editor.AreaContainer.visible
            and editor.AreaPanels.prefab.visible and not editor.AreaPanels.place.visible,
            "Prefab opens exactly one panel")
        local drag = { captured = true }
        function drag:MouseCapture(value) self.captured = value end
        editor.Drag = { panel = drag }
        editor.AreaButtons.scene:DoClick()
        check(editor.ActiveArea == "scene" and editor.AreaPanels.scene.visible
            and not editor.AreaPanels.prefab.visible and not drag.captured and editor.Drag == nil,
            "switching panels releases any viewport mouse capture")
        editor.FogToggle:SetValue(1)
        editor.AreaButtons.place:DoClick()
        check(editor.PreviewFog ~= nil and editor.IdInput:GetValue() == "test_prefab",
            "switching panels preserves document and preview settings")
        editor.AreaButtons.place:DoClick()
        check(editor.ActiveArea == nil and not editor.AreaContainer.visible and editor.AreaContainer.wide == 0,
            "clicking the active area closes it")
        check(not editor:ToggleArea("unknown"), "unknown workflow areas fail explicitly")
    end)

    suite:Add("metadata docking order survives placement toggles and save responses", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {},
            cell = { id = 28, x = 4, y = -11, tileX = 0, tileY = 0, tileSize = 640 } })
        editor.IdInput:SetValue("test")
        editor.NameInput:SetValue("Test")
        local function checkOrder()
            for _, parent in ipairs({ editor.AreaPanels.prefab:GetCanvas(), editor.WorldPlacementPanel }) do
                for index, control in ipairs(parent:GetChildren()) do
                    check(control.z == index, "each form control has its own stable docking position")
                end
            end
            local children = editor.AreaPanels.prefab:GetCanvas():GetChildren()
            check(children[editor.IdInput.z - 1].text == "ID (lowercase, numbers, - or _)"
                and children[editor.NameInput.z - 1].text == "Name"
                and children[editor.DescriptionInput.z - 1].text == "Description",
                "metadata fields stay immediately below their labels")
            check(editor.TagsInput.z < editor.WorldPlacementPanel.z,
                "metadata fields precede the world-placement controls")
        end
        checkOrder()
        editor.WorldPlacementToggle:SetValue(1)
        editor.WorldPlacementToggle:SetValue(0)
        editor:Save(false)
        state:Response("save", false, "A prefab with this ID already exists; open it before saving.")
        checkOrder()
        check(editor.Document.id == "test" and editor.Document.name == "Test"
            and not editor.Saving, "failed saves retain the draft and release saving state")
        editor:Save(false)
        state:Response("save", true, "Saved.")
        editor:ToggleArea("prefab")
        editor:ToggleArea("scene")
        editor:ToggleArea("prefab")
        checkOrder()
    end)

    suite:Add("focused metadata refreshes when switching saved and draft tabs", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:SetValue("draft")
        editor.NameInput:SetValue("Draft")
        editor.DescriptionInput:SetValue("Unfinished")
        editor.TagsInput:SetValue("customTag")
        local draft = editor.ActiveTab
        local document = blank()
        document.id, document.name, document.description, document.tags = "test", "Saved", "Existing", { "burningBarrel" }
        local saved = editor:CreateTab(document, "test", false)
        local controls = { editor.IdInput, editor.NameInput, editor.DescriptionInput, editor.TagsInput }
        local expected = { "test", "Saved", "Existing", "burningBarrel" }
        for index, control in ipairs(controls) do
            state.keyboardFocus = control
            editor:ActivateTab(saved)
            check(control:GetValue() == expected[index], "the focused field shows the destination tab's metadata")
            editor:SyncMetadata()
            check(document.id == "test" and document.name == "Saved" and document.description == "Existing"
                and document.tags[1] == "burningBarrel", "old focused text cannot overwrite the saved tab")
            editor:ActivateTab(draft)
            check(editor.Document.id == "draft" and editor.Document.name == "Draft"
                and editor.Document.description == "Unfinished" and editor.Document.tags[1] == "customTag",
                "switching back preserves unfinished metadata")
        end
        editor:ActivateTab(saved)
        editor.IdInput:SetText("stale_id")
        editor:Save(false)
        local request = state.requests[#state.requests]
        check(request.values[1] == "save" and request.values[3] == "test"
            and state.json[request.values[2]].id == "test",
            "saving an opened prefab always uses its bound identity, not stale widget text")
        check(editor.IdInput:GetValue() == "test", "save refresh repairs a stale saved-ID display")
    end)

    suite:Add("map picker preserves unsaved tabs through a level change", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:SetValue("unfinished id")
        editor.NameInput:SetValue("")
        local first = editor.ActiveTab
        local second = editor:CreateTab(blank(), nil, true)
        editor.IdInput:SetValue("second_draft")
        editor.NameInput:SetValue("Second")
        editor:SetPrefabPreviewOffset(50)
        editor.MapButton:DoClick()
        state:Response("maps", true, "", {
            recommended = { "gm_construct", "gm_flatgrass" }, custom = { "custom_map" }, page = 1, pages = 1, total = 1
        })
        check(editor.MapBrowser and #editor.MapGrid.children == 2 and editor.MapGrid.children[1].MapName == "gm_construct",
            "recommended maps appear as a thumbnail grid")
        editor.MapGrid.children[1]:DoClick()
        local path = "zombiesim/prefab_editor_map_transfer.json"
        local encoded = state.dataFiles[path]
        local saved = encoded and state.json[encoded]
        check(editor.SwitchingMap and saved and #saved.tabs == 2 and saved.active == 2
            and saved.tabs[1].document.id == "unfinished id" and saved.tabs[1].dirty
            and saved.tabs[2].view.prefabOffset == 50 and saved.tabs[2].dirty,
            "all tabs and their independent unsaved view state are verified before switching")
        local request = state.requests[#state.requests]
        local requestData = state.json[request.values[2]]
        check(request.values[1] == "switch_map" and requestData.map == "gm_construct"
            and requestData.token == "switch_123", "the server receives the matching destination and transfer token")
        state:Response("switch_map", true, "")
        check(editor.SwitchingMap and state.dataFiles[path] == encoded, "an acknowledgement alone does not discard the snapshot")
        editor.Frame:Remove()
        state.map = "gm_construct"
        state:Response("status", true, "", { origin = { x = 100, y = 200, z = 0 }, documents = {},
            transferToken = "switch_123", openIds = {} })
        check(editor:IsActive() and editor.SwitchingMap and #editor.Tabs == 2 and editor.ActiveTab == editor.Tabs[2]
            and editor.Tabs[1].Document.id == "unfinished id" and editor.Tabs[1].Dirty
            and editor.Document.id == "second_draft" and editor.PrefabPreviewOffset == 50,
            "both drafts, selected tab and preview height are restored on the destination")
        state:Response("switch_complete", true, "Editor tabs restored.")
        check(not editor.SwitchingMap and state.dataFiles[path] == nil and editor.Document.id == "second_draft"
            and first ~= editor.Tabs[1] and second ~= editor.Tabs[2],
            "only a matching server confirmation removes the local transfer file")
    end)

    suite:Add("failed map switches preserve editor state and report recovery failures", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:SetValue("draft")
        local tab = editor.ActiveTab
        check(editor:BeginMapSwitch("gm_construct"), "a valid destination starts a switch")
        local path = "zombiesim/prefab_editor_map_transfer.json"
        state:Response("switch_map", false, "Map is unavailable.", { markerUnchanged = true })
        check(not editor.SwitchingMap and state.dataFiles[path] == nil and editor.ActiveTab == tab
            and editor.Document.id == "draft" and editor.Dirty,
            "server rejection unlocks the unchanged draft and removes only its verified snapshot")
        check(editor:BeginMapSwitch("gm_construct"), "a later attempt can start")
        state.dataFiles[path] = "changed"
        state:Response("switch_map", false, "Map is unavailable.", { markerUnchanged = true })
        check(not editor.SwitchingMap and state.dataFiles[path] == "changed" and #state.messages > 0,
            "changed recovery data is preserved and the failure is surfaced")
        check(not editor:BeginMapSwitch("gm_construct"), "an existing recovery file cannot be overwritten")
    end)

    suite:Add("uncertain map-session failures retain the recovery snapshot", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:SetValue("draft")
        check(editor:BeginMapSwitch("gm_construct"), "a valid destination starts a switch")
        local path = "zombiesim/prefab_editor_map_transfer.json"
        local encoded = state.dataFiles[path]
        state:Response("switch_map", false, "Session recovery is required.", { markerUnchanged = false })
        check(editor.SwitchingMap and state.dataFiles[path] == encoded and state.query ~= nil,
            "an uncertain server marker retains the snapshot and blocks further edits")
        state.query[4]()
        state:Response("switch_check", true, "", { safeToResume = true })
        check(not editor.SwitchingMap and state.dataFiles[path] == nil and editor.Document.id == "draft",
            "a separately verified unchanged session releases the editor without losing the draft")
    end)

    suite:Add("cell preview moves the workspace without editing prefab coordinates", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(not editor.CellTilePanel.visible, "cell tile controls are hidden on ordinary maps")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.IdInput:SetValue("cell_draft")
        editor.NameInput:SetValue("Cell draft")
        editor:SetPrefabPreviewOffset(10)
        editor.MapButton:DoClick()
        for _, panel in ipairs(state.panels) do
            if panel.kind == "DButton" and panel.text == "CELLS" then panel:DoClick() break end
        end
        state:Response("cells", true, "", {
            cells = { { id = 302, x = 14, y = 0, map = "zz_preview_cell" } }, page = 1, pages = 1, total = 1
        })
        check(editor.MapGrid.children[1].CellId == 302, "the cell picker uses the logical cell identity")
        editor.MapGrid.children[1]:DoClick()
        local path = "zombiesim/prefab_editor_map_transfer.json"
        local saved = state.json[state.dataFiles[path]]
        local request = state.requests[#state.requests]
        local requestData = state.json[request.values[2]]
        check(saved and saved.cellId == 302 and requestData.cellId == 302
            and requestData.map == "zz_preview_cell", "cell identity accompanies the protected draft")
        state:Response("switch_map", true, "")
        editor.Frame:Remove()
        state.map = "zz_preview_cell"
        state:Response("status", true, "", {
            origin = { x = 0, y = 0, z = 36 }, documents = {}, transferToken = "switch_123", openIds = {},
            cell = { id = 302, x = 14, y = 0, tileX = 0, tileY = 0, tileSize = 640 }
        })
        state:Response("switch_complete", true, "")
        local prop, revision = editor.Document.props[1], editor.Revision
        local model = editor.Models[1]
        check(editor.CellTilePanel.visible and editor.Cell.tileX == 0 and editor.Cell.tileY == 0
            and model:GetPos().z == 46, "the cell opens at its centre surface with the preview height retained")
        check(editor:SetReference("models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"),
            "a reference model can be displayed")
        editor.CellTileX:SetValue(2)
        request = state.requests[#state.requests]
        requestData = state.json[request.values[2]]
        check(request.values[1] == "cell_tile" and requestData.x == 2 and requestData.y == 0
            and editor.CellTilePending ~= nil, "tile changes request a server-validated surface")
        state:Response("cell_tile", true, "", { x = 2, y = 0, origin = { x = 1280, y = 0, z = 50 } })
        editor.CellTileY:SetValue(-1)
        state:Response("cell_tile", true, "", { x = 2, y = -1, origin = { x = 1280, y = -640, z = 55 } })
        check(editor.Origin.x == 1280 and editor.Origin.y == -640 and editor.Origin.z == 55
            and model:GetPos().x == 1280 and model:GetPos().y == -640 and model:GetPos().z == 65
            and editor.ReferenceModel:GetPos().x == 1280 and editor.ReferenceModel:GetPos().z == 55,
            "the prefab, camera origin and reference move together to the detected tile surface")
        check(prop.position.x == 0 and prop.position.y == 0 and prop.position.z == 0 and editor.Revision == revision,
            "tile movement does not change saved prefab coordinates or dirty revision")
        editor.CellTileX:SetValue(1)
        state:Response("cell_tile", false, "No surface.")
        check(editor.Cell.tileX == 2 and editor.Cell.tileY == -1 and editor.Origin.x == 1280
            and editor.CellTilePending == nil, "a failed trace restores the previous tile controls and origin")
    end)

    suite:Add("workflow panels resize and camera zooms closer", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:ToggleArea("place")
        state.screenWidth, state.screenHeight = 800, 600
        state.hooks["ZM.PrefabEditor.Resize"]()
        check(editor.Frame.width == 800 and editor.Frame.height == 600 and editor.AreaContainer.wide == 280,
            "resolution change resizes the editor and available panel width")
        editor.Viewport:OnMouseWheeled(100)
        check(editor.CameraDistance == 64, "zoom can approach substantially closer than the old 350-unit limit")
        editor.Viewport:OnMouseWheeled(-100)
        check(editor.CameraDistance == 2400, "the existing maximum zoom-out limit remains")
    end)

    suite:Add("view panel controls camera and grid per tab", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        local first = editor.ActiveTab
        editor.AreaButtons.view:DoClick()
        check(editor.ActiveArea == "view" and editor.ViewZoom.parent == editor.AreaPanels.view:GetCanvas()
            and editor.SnapToggle.parent == editor.AreaPanels.view:GetCanvas(), "camera and snapping are in the View panel")
        editor.ViewZoom:SetValue(500)
        editor.ViewYaw:SetValue(0)
        editor.ViewPitch:SetValue(45)
        editor.GridChoice:OnSelect(4, "128 units", 128)
        check(#editor.GridLines == 12 and editor.GridLines[1][1].x == -320
            and editor.GridLines[#editor.GridLines][2].y == 320, "spacing retains the 640-unit guide")
        editor.GridToggle:SetValue(0)
        editor.CompassToggle:SetValue(0)
        state.renderLines, state.compassLabels = {}, {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(#state.renderLines == 0 and state.compassLabels.N == nil, "grid and compass can be hidden independently")
        local panel = editor.Viewport
        state.keys = { [env.KEY_LSHIFT] = true }
        editor:BeginDrag(panel, env.MOUSE_RIGHT)
        state.mouseX, state.mouseY = 70, 60
        editor:UpdateDrag()
        editor:ReleaseDrag(panel, env.MOUSE_RIGHT)
        check(editor.CameraPanX ~= 0 and editor.CameraPanY ~= 0 and editor.CameraYaw == 0,
            "Shift plus right-drag pans without orbiting")
        local panX, panY = editor.CameraPanX, editor.CameraPanY
        local second = editor:CreateTab(blank(), nil, true)
        check(editor.ShowGrid and editor.ShowCompass and editor.GridSpacing == 64 and editor.CameraPanX == 0,
            "a new tab starts with independent defaults")
        editor:ActivateTab(first)
        check(editor.CameraPanX == panX and editor.CameraPanY == panY and editor.GridSpacing == 128
            and not editor.ShowGrid and not editor.ShowCompass and #editor.GridLines == 12,
            "switching back restores the first tab's camera and grid")
        editor:ResetView()
        check(editor.CameraYaw == 45 and editor.CameraPitch == 55 and editor.CameraDistance == 1000
            and editor.CameraPanX == 0 and editor.CameraPanY == 0 and editor.GridSpacing == 128,
            "camera reset leaves the grid settings unchanged")
        state.keys = {}
        editor:BeginDrag(panel, env.MOUSE_RIGHT)
        state.mouseX = 80
        editor:UpdateDrag()
        editor:ReleaseDrag(panel, env.MOUSE_RIGHT)
        check(editor.CameraYaw ~= 45 and editor.CameraPanX == 0, "ordinary right-drag still orbits")
        editor:ActivateTab(second)
        check(editor.CameraYaw == 45 and editor.ShowGrid, "camera changes do not leak to another tab")
    end)

    suite:Add("save acknowledgements do not discard edits made while saving", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:SetValue("test_prefab")
        editor.NameInput:SetValue("Original")
        editor:Save(false)
        check(editor.Saving and state.requests[#state.requests].values[1] == "save", "save is requested")
        editor.NameInput:SetValue("Later edit")
        state:Response("save", true, "Prefab saved.")
        check(not editor.Saving and editor.Dirty, "a later edit remains dirty")
        check(editor.OpenedId == "test_prefab", "the saved ID remains the open target")
    end)

    suite:Add("tabs retain independent documents, views and background saves", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        local first = editor.ActiveTab
        editor.IdInput:SetValue("first")
        editor.NameInput:SetValue("First")
        editor.CameraYaw, editor.CameraDistance, editor.PreviewDark = 123, 250, true
        local second = editor:CreateTab(blank(), nil, true)
        editor.IdInput:SetValue("second")
        editor.NameInput:SetValue("Second")
        editor.CameraYaw, editor.CameraDistance = 35, 800
        editor:ActivateTab(first)
        check(editor.Document.id == "first" and editor.Dirty and editor.CameraYaw == 123
            and editor.CameraDistance == 250 and editor.PreviewDark, "first document and its view are restored")
        editor:Save(false)
        local saveToken = state.requests[#state.requests].values[4]
        check(first.Saving and not editor.IdInput.enabled, "saving locks the unsaved ID while the request is pending")
        editor:ActivateTab(second)
        state:Response("save", true, "Saved", nil, saveToken)
        check(editor.ActiveTab == second and editor.Document.id == "second" and editor.Dirty
            and first.OpenedId == "first" and not first.Dirty and not first.Saving,
            "background save updates only its originating tab")
        editor:ActivateTab(first)
        check(editor.OpenedId == "first" and not editor.Dirty and not editor.IdInput.enabled,
            "returning to the saved tab restores its locked ID")
        editor:ActivateTab(second)
        check(editor.CameraYaw == 35 and editor.CameraDistance == 800, "second tab retains its own view")
    end)

    suite:Add("late tab requests cannot overwrite another document", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        local first = editor.ActiveTab
        editor.IdInput:SetValue("draft")
        editor.NameInput:SetValue("Draft")
        check(editor:RequestModel("models/props_c17/oildrum001.mdl"), "model validation is requested")
        local modelToken = state.requests[#state.requests].values[4]
        local second = editor:CreateTab(blank(), nil, true)
        editor:CloseTab(first)
        check(#editor.Tabs == 2, "a tab with pending model validation cannot be closed")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" }, modelToken)
        check(editor.ActiveTab == second and #second.Document.props == 0 and #first.Document.props == 1
            and first.Dirty, "late model response modifies only its originating tab")
        check(editor:OpenSaved("one"), "first saved prefab is requested")
        local oneToken = state.requests[#state.requests].values[4]
        check(not editor:OpenSaved("one"), "duplicate pending loads are not sent")
        check(editor:OpenSaved("two"), "second saved prefab is requested")
        local twoToken = state.requests[#state.requests].values[4]
        local third = editor:CreateTab(blank(), nil, true)
        local one = { schemaVersion = 1, id = "one", name = "One", description = "", tags = {},
            props = {}, lights = {}, particles = {} }
        local two = { schemaVersion = 1, id = "two", name = "Two", description = "", tags = {},
            props = {}, lights = {}, particles = {} }
        state:Response("load", true, "", two, twoToken)
        state:Response("load", true, "", one, oneToken)
        check(editor.ActiveTab == third and editor:FindTab("one") and editor:FindTab("two"),
            "out-of-order loads become background tabs after the user switches")
        local count = #editor.Tabs
        editor:OpenSaved("one")
        check(editor.ActiveTab == editor:FindTab("one") and #editor.Tabs == count,
            "reopening a prefab focuses its existing tab")
    end)

    suite:Add("pending loads block exit and failures allow retry", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:OpenSaved("missing")
        local token = state.requests[#state.requests].values[4]
        editor:Exit()
        check(state.requests[#state.requests].values[1] == "load" and #state.messages > 0,
            "exit does not discard an outstanding load")
        state:Response("load", false, "Prefab not found.", nil, token)
        check(editor.PendingLoads.missing == nil and editor:OpenSaved("missing"),
            "a failed response clears the pending load and permits retry")
        token = state.requests[#state.requests].values[4]
        state:Response("load", false, "Prefab not found.", nil, token)
        editor:Exit()
        check(state.requests[#state.requests].values[1] == "end",
            "a clean editor may exit once the load has completed")
    end)

    suite:Add("late reference validation stays with its originating tab", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        local first = editor.ActiveTab
        local path = "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
        editor:RequestReference(path)
        local token = state.requests[#state.requests].values[4]
        local second = editor:CreateTab(blank(), nil, true)
        state:Response("reference", true, "", { model = path }, token)
        check(editor.ActiveTab == second and editor.ReferenceModel == nil and first.View.reference == path,
            "a late reference response does not alter the active tab")
        editor:ActivateTab(first)
        check(editor.ReferenceWanted == path and editor.ReferenceModel and editor.ReferenceModel.path == path,
            "the validated reference is restored when its tab becomes active")
    end)

    suite:Add("closing and exiting protect every dirty tab", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        local first = editor.ActiveTab
        editor.IdInput:SetValue("first")
        editor.NameInput:SetValue("First")
        local second = editor:CreateTab(blank(), nil, true)
        editor.IdInput:SetValue("second")
        editor.NameInput:SetValue("Second")
        editor:CloseTab(first)
        check(state.query and editor.ActiveTab == first and #editor.Tabs == 2, "dirty tab asks before closing")
        state.query[8]()
        check(#editor.Tabs == 2 and first.Dirty, "cancel keeps the dirty tab")
        editor:Exit()
        state.query[6]()
        state.query[8]()
        check(first.Dirty and second.Dirty and #editor.Tabs == 2,
            "cancelling a later exit prompt preserves every earlier dirty tab")
        editor:Exit()
        state.query[6]()
        editor:ActivateTab(first)
        editor.NameInput:SetValue("Changed after discard")
        state.query[6]()
        check(state.query and first.Dirty and editor.ActiveTab == first,
            "editing a previously discarded tab causes another confirmation")
        editor:CloseTab(first)
        state.query[6]()
        check(#editor.Tabs == 1 and editor.ActiveTab == second, "discard closes only the chosen tab")
        editor:CloseTab(second)
        state.query[6]()
        check(#editor.Tabs == 1 and editor.ActiveTab.Document.id == "" and not editor.Dirty,
            "closing the last tab opens a clean blank document")
    end)

    suite:Add("mobility is edited independently for each prop", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(not editor.MovableToggle.enabled, "mobility is disabled without a selected prop")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(editor.MovableToggle.enabled and editor.Document.props[1].movable == false,
            "new props start stationary")
        editor.MovableToggle:SetValue(1)
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(editor.Document.props[1].movable == true and editor.Document.props[2].movable == false,
            "changing one prop does not change the other")
        editor.PropList:OnRowSelected(1, { PrefabIndex = 1 })
        check(editor.MovableToggle:GetValue() == 1 and editor.Document.props[1].movable == true,
            "reselecting restores the selected prop's setting")
        editor.IdInput:SetValue("mobility_test")
        editor.NameInput:SetValue("Mobility test")
        editor:Save(false)
        local request = state.requests[#state.requests]
        local saved = state.json[request.values[2]]
        check(saved and saved.props[1].movable == true and saved.props[2].movable == false,
            "save includes both per-prop settings")
    end)
    suite:Add("inspector follows selected object and keeps axis rows compact", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(editor.EmptySelection.visible and not editor.SelectionPanel.visible
            and not editor.PropPanel.visible and not editor.LightPanel.visible and not editor.ParticlePanel.visible,
            "no object shows no transform or type-specific settings")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(editor.SelectionPanel.visible and editor.PropPanel.visible and not editor.LightPanel.visible
            and not editor.ParticlePanel.visible and not editor.EmptySelection.visible,
            "selecting a prop shows only its settings")
        local positions, angles = {}, {}
        for _, entry in ipairs(editor.Inspector) do
            if entry.group == "position" then positions[entry.key] = entry.control end
            if entry.group == "angles" then angles[entry.key] = entry.control end
        end
        check(positions.x.parent.parent == positions.y.parent.parent
            and positions.y.parent.parent == positions.z.parent.parent
            and angles.r.parent.parent == angles.p.parent.parent and angles.p.parent.parent == angles.y.parent.parent,
            "position and rotation each share one three-axis row")
        positions.z:SetValue(12)
        angles.r:SetValue(10); angles.p:SetValue(20); angles.y:SetValue(30)
        local prop = editor.Document.props[1]
        check(prop.position.z == 12 and prop.angles.r == 10 and prop.angles.p == 20 and prop.angles.y == 30,
            "compact axis controls preserve the prop transform mapping")
        editor:AddLight()
        check(editor.SelectionPanel.visible and not editor.PropPanel.visible and editor.LightPanel.visible
            and not editor.ParticlePanel.visible, "selecting a light hides prop and particle settings")
        state:Response("particles", true, "", { { id = "steam", label = "Steam" } })
        editor:AddParticle()
        check(editor.SelectionPanel.visible and not editor.PropPanel.visible and not editor.LightPanel.visible
            and editor.ParticlePanel.visible, "selecting a particle shows its own settings")
        editor:Select(nil)
        check(editor.EmptySelection.visible and not editor.SelectionPanel.visible and not editor.ParticlePanel.visible,
            "deselecting returns to the empty inspector")
    end)
    suite:Add("loot settings and prop identity follow the selected prop", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local first = editor.Document.props[1]
        check(first.lootMode == "off" and first.propId == "p_fixture1", "new props default to Off with a stable server ID")
        editor.LootMode:OnSelect(2, "Normal", "normal")
        editor.LootGroup:OnSelect(2, "Generic Medical", "lootGenericMedical")
        editor.LootChanceToggle:SetValue(1)
        editor.LootChance:SetValue(70)
        check(first.lootMode == "normal" and first.lootGroup == "lootGenericMedical"
            and math.abs(first.lootChance - 0.7) < 0.00001, "normal loot stores the selected group and configured chance")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(editor.Document.props[2].lootMode == "off" and editor.Document.props[2].propId ~= first.propId,
            "another prop has an independent stable ID and loot mode")
        editor.LootMode:OnSelect(3, "Guaranteed", "guaranteed")
        editor.PropList:OnRowSelected(1, { PrefabIndex = 1 })
        check(editor.LootMode:GetValue() == "Normal" and editor.LootGroup:GetValue() == "Generic Medical (lootGenericMedical)"
            and editor.LootChance:GetValue() == 70, "reselecting restores the first prop's settings")
        editor.IdInput:SetValue("loot_test")
        editor.NameInput:SetValue("Loot test")
        editor:Save(false)
        local saved = state.json[state.requests[#state.requests].values[2]]
        check(saved and saved.props[1].propId == first.propId and saved.props[2].lootMode == "guaranteed",
            "the saved document retains per-prop identities and modes")
    end)
    suite:Add("loot groups are selectable and retain the model default", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local prop = editor.Document.props[1]
        editor.LootMode:OnSelect(2, "Normal", "normal")
        check(#editor.LootGroup.choices == 3 and editor.LootGroup.choices[1].data == ""
            and editor.LootGroup.choices[2].data == "lootGenericMedical"
            and editor.LootGroup.choices[3].data == "lootGenericWeapons",
            "model default and valid groups are listed in stable order")
        editor.LootGroup:OnSelect(2, "Generic Medical", "lootGenericMedical")
        check(prop.lootGroup == "lootGenericMedical", "selecting a group preserves its real ID")
        editor.LootGroup:OnSelect(1, "Model default", "")
        check(prop.lootGroup == nil and editor.LootGroup:GetValue() == "Model default",
            "model default clears only the override")
        editor.LootGroup:OnSelect(2, "Invalid", "lootNotAvailable")
        check(prop.lootGroup == nil and #state.messages > 0, "unavailable choices are reported")
    end)
    suite:Add("missing loot registry is reported and cannot be selected", function(check)
        local _, state, editor = fixture()
        state.lootRegistry = {}
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.LootMode:OnSelect(2, "Normal", "normal")
        check(not editor.LootGroupsReady and not editor.LootGroup.enabled
            and editor.LootGroup:GetValue() == "Loot groups unavailable" and #state.messages > 0,
            "missing registry is visible and disables the selector")
    end)

    suite:Add("spotlights support selection, numeric editing and saved identity", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:AddLight()
        local first = editor.Document.lights[1]
        check(editor.Selected == -1 and first.lightId == "light_1" and editor.Dirty,
            "adding a spotlight selects a stable ID and marks the document dirty")
        for _, entry in ipairs(editor.Inspector) do
            if entry.group == "position" and entry.key == "x" then entry.control:SetValue(25) end
        end
        for _, entry in ipairs(editor.LightInspector) do
            if entry.key == "g" then entry.control:SetValue(100) end
            if entry.key == "brightness" then entry.control:SetValue(4) end
            if entry.key == "fov" then entry.control:SetValue(75) end
            if entry.key == "range" then entry.control:SetValue(750) end
        end
        check(first.position.x == 25 and first.color.g == 100 and first.brightness == 4
            and first.fov == 75 and first.range == 750, "numeric settings edit the selected light")
        editor:AddLight()
        check(editor.Document.lights[2].lightId == "light_2" and editor.Document.lights[2].brightness == 6,
            "a second light has independent settings")
        editor.LightList:OnRowSelected(1, { PrefabLightIndex = 1 })
        check(editor.Selected == -1 and editor:GetSelectedObject() == first, "light list reselects the first light")
        editor.IdInput:SetValue("light_test")
        editor.NameInput:SetValue("Light test")
        editor:Save(false)
        local saved = state.json[state.requests[#state.requests].values[2]]
        check(saved and #saved.lights == 2 and saved.lights[1].lightId == "light_1"
            and saved.lights[1].position.x == 25 and saved.lights[1].brightness == 4,
            "save includes the authored lights")
        state:Response("load", true, "", saved)
        check(#editor.Document.lights == 2 and editor.Document.lights[1].color.g == 100,
            "reopening retains spotlight settings")
    end)

    suite:Add("spotlights use move and rotation gizmos without scale", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:AddLight()
        local light = editor.Document.lights[1]
        editor.SnapEnabled = false
        editor.GizmoPoints = {
            x = { start = { x = 50, y = 50, visible = true }, finish = { x = 150, y = 50, visible = true } }
        }
        local panel = { MouseCapture = function() end }
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        state.mouseX = 100
        editor:UpdateDrag()
        check(light.position.x == -30, "move gizmo changes the light position")
        editor:ReleaseDrag(panel)
        editor:CycleMode()
        check(editor.Mode == "rotate", "spotlight switches from move to rotate")
        editor:CycleMode()
        check(editor.Mode == "move", "spotlights skip the prop-only scale mode")
        editor.Mode = "rotate"
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.mouseX, state.mouseY = 50, 50
        state.planeHit = env.Vector(light.position.x + 72, light.position.y, light.position.z)
        selectRingAndStartDrag(editor, state, env)
        state.planeHit = env.Vector(light.position.x, light.position.y + 72, light.position.z)
        state.mouseY = 100
        editor:UpdateDrag()
        check(math.abs(light.angles.y - 135) < 0.0001, "rotation gizmo changes the light direction")
        editor:CancelRotation()
        check(math.abs(light.angles.y - 45) < 0.0001, "cancelling restores the light rotation")
        state.renderLines, state.renderBoxes = {}, {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(#state.renderBoxes >= 1 and editor.GizmoPoints.z ~= nil,
            "spotlight handle and rotation rings are rendered")
        editor:Select(nil)
        state.rayHit = true
        check(editor:SelectAt(50, 50) == -1 and editor.Selected == -1,
            "spotlight can also be selected in the viewport")
        local remove
        for _, control in ipairs(state.panels) do
            if control.text == "REMOVE SELECTED" then remove = control break end
        end
        check(remove ~= nil, "remove control exists")
        if remove then remove:DoClick() end
        check(#editor.Document.lights == 0 and editor.Selected == nil,
            "removing the selected light clears selection and its document entry")
    end)

    suite:Add("particle authoring preserves mode and overlap through save and reopen", function(check)
        local env, state, editor = fixture()
        local triggers, clears = {}, 0
        env.ZM_PrefabParticlePreview = {
            Trigger = function(_, id) triggers[#triggers + 1] = id; return true end,
            Clear = function() clears = clears + 1 end
        }
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:AddParticle()
        check(#editor.Document.particles == 0 and #state.messages > 0, "missing catalog does not silently select an effect")
        state:Response("particles", true, "", { { id = "steam", label = "Steam" } })
        editor:AddParticle()
        local particle = editor.Document.particles[1]
        check(particle and particle.particleId == "particle_1" and particle.effect == "steam"
            and particle.mode == "continuous" and particle.overlap == true
            and editor.Selected == "particle:particle_1", "new particle uses the selected catalog effect and approved defaults")
        editor.ParticleMode:OnSelect(2, "Triggered", "triggered")
        editor.ParticleOverlap:SetValue(0)
        editor.ParticleTrigger:DoClick()
        check(particle.mode == "triggered" and particle.overlap == false and triggers[1] == "particle_1",
            "mode, overlap and explicit preview trigger apply to the selected particle")
        for _, entry in ipairs(editor.Inspector) do
            if entry.group == "position" and entry.key == "x" then entry.control:SetValue(80) end
        end
        editor.IdInput:SetValue("particle_test")
        editor.NameInput:SetValue("Particle test")
        editor:Save(false)
        local saved = state.json[state.requests[#state.requests].values[2]]
        check(saved and saved.particles[1].position.x == 80 and saved.particles[1].mode == "triggered"
            and saved.particles[1].overlap == false, "save includes the authored particle settings")
        state:Response("load", true, "", saved)
        check(clears >= 1 and editor.Document.particles[1].particleId == "particle_1"
            and editor.Document.particles[1].overlap == false, "reopen retains data and clears previous previews")
    end)

    suite:Add("particle handles use the existing move and rotation gizmos", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("particles", true, "", { { id = "steam", label = "Steam" } })
        editor:AddParticle()
        local particle = editor.Document.particles[1]
        editor.SnapEnabled = false
        editor.GizmoPoints = {
            x = { start = { x = 50, y = 50, visible = true }, finish = { x = 150, y = 50, visible = true } }
        }
        local panel = { MouseCapture = function() end }
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        state.mouseX = 100
        editor:UpdateDrag()
        check(particle.position.x == 50, "move gizmo changes particle position")
        editor:ReleaseDrag(panel)
        editor:CycleMode()
        check(editor.Mode == "rotate", "particle switches to rotation")
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.mouseX, state.mouseY = 50, 50
        state.planeHit = env.Vector(particle.position.x + 72, particle.position.y, particle.position.z)
        selectRingAndStartDrag(editor, state, env)
        state.planeHit = env.Vector(particle.position.x, particle.position.y + 72, particle.position.z)
        state.mouseY = 100
        editor:UpdateDrag()
        check(math.abs(particle.angles.y - 90) < 0.0001, "rotation gizmo changes particle direction")
        editor:CancelRotation()
        check(particle.angles.y == 0, "cancelling restores particle direction")
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(editor.GizmoPoints.z ~= nil and #state.renderBoxes > 0, "particle handle and gizmos render")
        editor:Select(nil)
        state.rayHit = true
        check(editor:SelectAt(50, 50) == "particle:particle_1", "particle handle is selectable in the viewport")
    end)

    suite:Add("typed metadata is saved without pressing enter", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:TypeText("1")
        editor.NameInput:TypeText("Test")
        editor.DescriptionInput:TypeText("A test prefab")
        editor.TagsInput:TypeText("roadDetail, transitionGate")
        check(editor.Dirty, "typing metadata marks the document dirty before leaving the field")
        editor:Save(false)
        local request = state.requests[#state.requests]
        local document = request and state.json[request.values[2]]
        check(document and document.id == "1" and document.name == "Test",
            "save uses the exact visible ID and name")
        check(document and document.description == "A test prefab" and #document.tags == 2
            and document.tags[1] == "roadDetail" and document.tags[2] == "transitionGate",
            "save uses the visible description and tags")
    end)

    suite:Add("save synchronizes visible metadata even if a change callback was missed", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor.IdInput:SetUpdateOnType(false)
        editor.NameInput:SetUpdateOnType(false)
        editor.IdInput:TypeText("test_prefab")
        editor.NameInput:TypeText("Test")
        editor:Save(false)
        local request = state.requests[#state.requests]
        local document = request and state.json[request.values[2]]
        check(document and document.id == "test_prefab" and document.name == "Test",
            "the save request reads the current visible text")
        check(editor.Dirty, "synchronizing missed changes marks the document dirty")
    end)

    suite:Add("editor cleanup removes its preview entities", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local model = state.models[1]
        editor.Frame:Remove()
        check(not model.valid and not editor:IsActive(), "closing the panel removes its client model")
    end)

    suite:Add("editor preview controls use the inner-city profile and reset on close", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(editor.PreviewFog == nil and not editor.PreviewDark, "fog and simulated dark preview start off")
        editor.FogToggle:SetValue(1)
        check(editor.PreviewFog and editor.PreviewFog.start == 350 and editor.PreviewFog.finish == 1450
            and editor.PreviewFog.color[1] == 122, "fog uses the actual inner-city profile")
        editor.DarkToggle:SetValue(1)
        check(editor.PreviewDark == true, "simulated dark preview can be enabled")
        editor.FogToggle:SetValue(0)
        check(editor.PreviewFog == nil, "fog preview can be turned off")
        editor.Frame:Remove()
        check(editor.PreviewFog == nil and editor.PreviewDark == false, "closing clears editor-only previews")
    end)

    suite:Add("missing editor fog profile is reported and stays off", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state.atmosphereProfiles = {}
        editor.FogToggle:SetValue(1)
        check(editor.PreviewFog == nil and editor.FogToggle:GetValue() == 0,
            "an unavailable profile does not silently enable a fallback")
        check(#state.messages > 0, "the missing profile is reported")
    end)

    suite:Add("model browser navigates, searches and selects without spawning", function(check)
        local _, state, editor = fixture()
        state.modelFolders["models/props_c17/"] = {
            files = { "oildrum001.mdl", "chair.mdl", "notes.txt" }, directories = { "detail" }
        }
        state.modelFolders["models/props_c17/detail/"] = {
            files = { "small.mdl" }, directories = {}
        }
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        local requestsBeforeBrowse = #state.requests
        editor:OpenModelBrowser()
        local browser = editor.ModelBrowser
        check(browser and #browser.Grid.children == 2 and #browser.Folders.lines == 1,
            "the browser shows model thumbnails and subfolders")
        check(browser.Grid.children[1].ModelPath == "models/props_c17/chair.mdl"
            and browser.Grid.children[1].children[1].model == "models/props_c17/chair.mdl",
            "thumbnails are sorted and point at the mounted models")
        browser.Search:TypeText("oil")
        state.now = 1
        browser:Think()
        check(#browser.Grid.children == 1 and browser.Grid.children[1].ModelPath == "models/props_c17/oildrum001.mdl",
            "search filters the current folder")
        browser.Search:TypeText("")
        state.now = 2
        browser:Think()
        browser.Folders:OnRowSelected(1, browser.Folders.lines[1])
        check(#browser.Grid.children == 1 and browser.Grid.children[1].ModelPath == "models/props_c17/detail/small.mdl",
            "selecting a folder navigates into it")
        browser.Grid.children[1]:DoClick()
        check(editor.ModelPath:GetValue() == "models/props_c17/detail/small.mdl" and editor.ModelBrowser == nil,
            "selecting a thumbnail fills the existing model field and closes the browser")
        check(#editor.Document.props == 0 and #state.requests == requestsBeforeBrowse,
            "browsing never spawns a prop without the existing Add Prop action")
    end)

    suite:Add("model browser pages and rejects unsafe folders", function(check)
        local _, state, editor = fixture()
        local files = {}
        for index = 1, 100 do files[index] = string.format("model_%03d.mdl", index) end
        state.modelFolders["models/props_c17/"] = { files = files, directories = {} }
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:OpenModelBrowser()
        local browser = editor.ModelBrowser
        check(#browser.Grid.children == 48 and browser.NextPage.enabled,
            "the first page bounds thumbnail creation")
        browser.NextPage:DoClick()
        check(#browser.Grid.children == 48 and browser.Grid.children[1].ModelPath == "models/props_c17/model_049.mdl",
            "next page uses the next bounded set")
        browser.NextPage:DoClick()
        check(#browser.Grid.children == 4 and not browser.NextPage.enabled,
            "the final page has the remaining models")
        browser.FolderInput:SetValue("models/../outside/")
        browser.FolderInput:OnEnter()
        check(#browser.Grid.children == 4 and #state.messages > 0, "unsafe paths fail without replacing the current folder")
    end)

    suite:Add("model browser searches mounted folders incrementally", function(check)
        local _, state, editor = fixture()
        state.modelFolders["models/"] = { files = {}, directories = { "props_c17", "other", "extras", "nested" } }
        state.modelFolders["models/other/"] = { files = { "oildrum_other.mdl" }, directories = {} }
        state.modelFolders["models/nested/"] = { files = {}, directories = { "deeper" } }
        state.modelFolders["models/nested/deeper/"] = { files = { "oildrum_deep.mdl" }, directories = {} }
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:OpenModelBrowser()
        local browser = editor.ModelBrowser
        browser.Search:TypeText("oil drum")
        browser.GlobalSearch:SetValue(1)
        state.now = 1
        browser:Think()
        check(string.find(browser.PageLabel.text, "scanning", 1, true) ~= nil, "unfinished indexing is visible")
        browser.GlobalSearch:SetValue(0)
        browser:Think()
        check(#browser.Grid.children == 1 and browser.Grid.children[1].ModelPath == "models/props_c17/oildrum001.mdl",
            "returning to folder search restores its local results")
        browser.GlobalSearch:SetValue(1)
        state.now = 2
        browser:Think()
        check(#browser.Grid.children == 3 and not string.find(browser.PageLabel.text, "scanning", 1, true),
            "resuming finishes the scan and finds models in other and nested folders")
        browser.Grid.children[1]:DoClick()
        check(editor.ModelPath:GetValue() == "models/nested/deeper/oildrum_deep.mdl"
            and editor.ModelFolder:GetValue() == "models/nested/deeper/" and editor.ModelBrowser == nil,
            "a global result selects its full path and containing folder")
    end)

    suite:Add("model browser reports an incomplete mounted search", function(check)
        local _, state, editor = fixture()
        state.modelFolders["models/"] = { files = {}, directories = { "unavailable" } }
        state.failedModelFolder = "models/unavailable/"
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        editor:OpenModelBrowser()
        local browser = editor.ModelBrowser
        browser.Search:TypeText("oil")
        browser.GlobalSearch:SetValue(1)
        browser:Think()
        check(#state.messages > 0 and string.find(browser.PageLabel.text, "search incomplete", 1, true),
            "folder enumeration failure is visible and does not look complete")
    end)

    suite:Add("reference tile stays separate from prefab props and is cleaned up", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        check(state.requests[#state.requests].values[1] == "references", "available references are requested")
        local path = "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
        state:Response("references", true, "", { { label = "Straight road", model = path } })
        check(#editor.ReferenceChoice.choices == 2, "the selector includes no reference and the road")
        editor.ReferenceChoice:OnSelect(2, "Straight road", path)
        check(state.requests[#state.requests].values[1] == "reference", "selection is validated by the server")
        state:Response("reference", true, "", { label = "Straight road", model = path })
        local reference = editor.ReferenceModel
        check(reference and reference.noDraw and #editor.Document.props == 0 and not editor.Dirty,
            "the reference is an editor-only model, not a saved prop")
        check(editor.GridHeight == 2 and #editor.GridLines == 22, "the guide lifts above the reference bounds")
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(reference.drawn and state.compassOrigin.z == 3, "the reference and raised compass are rendered")
        editor.ReferenceChoice:OnSelect(1, "No reference", "")
        check(not reference.valid and editor.ReferenceModel == nil and editor.GridHeight == 1,
            "removing the reference restores the original grid")
        state:Response("reference", true, "", { model = path })
        check(editor.ReferenceModel == nil, "a late response cannot restore a deselected reference")
    end)

    suite:Add("reference height is preview-only and follows its tab", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 10 }, documents = {} })
        local first = editor.ActiveTab
        local path = "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
        editor:RequestReference(path)
        state:Response("reference", true, "", { model = path })
        editor.ReferenceOffsetInput:SetValue(-5)
        check(editor.ReferenceModel.position.z == 5 and editor.GridHeight == -3 and not editor.Dirty,
            "negative offset moves only the reference and its guide")
        check(#editor.Document.props == 0 and editor.Document.referenceOffset == nil,
            "reference offset is not part of the prefab")
        local second = editor:CreateTab(blank(), nil, true)
        check(editor.ReferenceModel == nil and editor.ReferenceOffset == 0, "new tab has no reference offset")
        editor:ActivateTab(first)
        check(editor.ReferenceModel.position.z == 5 and editor.ReferenceOffsetInput.value == -5
            and editor.GridHeight == -3, "switching back restores reference and offset")
        editor:ActivateTab(second)
        check(editor.ReferenceOffset == 0 and not editor.Dirty, "offset does not leak or mark another tab dirty")
    end)

    suite:Add("prefab preview height moves objects without changing the document", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 10 }, documents = {} })
        local first = editor.ActiveTab
        local path = "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
        editor:RequestReference(path)
        state:Response("reference", true, "", { model = path })
        editor.ReferenceOffsetInput:SetValue(5)
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor:AddLight()
        state:Response("particles", true, "", { { id = "steam", label = "Steam" } })
        editor:AddParticle()
        local prop, light, particle = editor.Document.props[1], editor.Document.lights[1], editor.Document.particles[1]
        local revision = editor.Revision
        editor.PrefabOffsetInput:SetValue(48)
        check(editor.Models[1].position.z == 58 and editor:GetSelectionPosition().z == 74
            and editor.SceneRefresh, "props and the selected particle move with the preview origin")
        check(editor.ReferenceModel.position.z == 15 and editor.GridHeight == 7,
            "prefab height does not move the reference tile or its guide")
        check(prop.position.z == 0 and light.position.z == 192 and particle.position.z == 16
            and editor.Revision == revision and editor.Document.prefabOffset == nil,
            "preview height does not modify or dirty the document")
        state.rayPositions = {}
        editor:FindPropAt(50, 50)
        check(state.rayPositions[1].z == 58 and state.rayPositions[2].z == 250
            and state.rayPositions[3].z == 74, "selection traces follow every offset object")
        state.renderBoxes = {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(state.renderBoxes[1][1].z == 250 and state.renderBoxes[2][1].z == 74,
            "light and particle handles render at their offset positions")
        editor.IdInput:SetValue("preview_offset")
        editor.NameInput:SetValue("Preview offset")
        editor:Save(false)
        local saved = state.json[state.requests[#state.requests].values[2]]
        check(saved.props[1].position.z == 0 and saved.lights[1].position.z == 192
            and saved.particles[1].position.z == 16 and saved.prefabOffset == nil,
            "save sends the original local positions without a preview-offset field")
        local second = editor:CreateTab(blank(), nil, true)
        check(editor.PrefabPreviewOffset == 0, "a new tab has its own default preview height")
        editor:ActivateTab(first)
        check(editor.PrefabPreviewOffset == 48 and editor.Models[1].position.z == 58
            and editor.PrefabOffsetInput.value == 48, "switching tabs restores preview height before rebuilding models")
        editor:ActivateTab(second)
        check(editor.PrefabPreviewOffset == 0, "the preview offset does not leak to another tab")
    end)

    suite:Add("double-click cycles move, rotate and uniform scale", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local panel = { MouseCapture = function() end }
        state.rayHit = true
        state.now = 1
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        state.now = 1.2
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Mode == "rotate", "the first double-click selects rotation")
        state.now = 2
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        state.now = 2.2
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Mode == "scale", "the second double-click selects uniform scale")
        state.now = 3
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        state.now = 3.2
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Mode == "move", "the third double-click returns to movement")
        check(editor.ModeButton.text == "MODE: MOVE", "the visible mode stays in sync")
    end)

    suite:Add("uniform scaling updates the model, saved document and selection bounds", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode = "scale"
        editor.GizmoPoints = {
            x = { start = { x = 50, y = 50, visible = true }, finish = { x = 150, y = 50, visible = true } }
        }
        state.rayHit = true
        state.now = 10
        editor:BeginDrag({ MouseCapture = function() end }, env.MOUSE_LEFT)
        state.mouseX = 100
        editor:UpdateDrag()
        local prop, model = editor.Document.props[1], state.models[1]
        check(prop.scale == 1.5 and model.matrixKind == "RenderMultiply"
            and model.matrix.scale.x == 1.5 and model.matrix.scale.y == 1.5 and model.matrix.scale.z == 1.5,
            "axis drag applies a uniform render matrix to the model")
        check(model.renderMinimum.x == -3 and model.renderMaximum.z == 6,
            "render bounds follow the scaled model")
        editor:FindPropAt(50, 50)
        check(state.rayMinimum.x == -3 and state.rayMaximum.z == 6, "selection uses scaled model bounds")
        editor.IdInput:TypeText("scale_test")
        editor.NameInput:TypeText("Scale test")
        editor:Save(false)
        local request = state.requests[#state.requests]
        local saved = state.json[request.values[2]]
        check(saved and saved.props[1].scale == 1.5, "uniform scale is included in the saved document")
        editor.Drag.initial = 9.9
        state.mouseX = 1000
        editor:UpdateDrag()
        check(prop.scale == 10, "large drags are clamped to the supported maximum")
    end)

    suite:Add("gizmo visuals and selectable handles distinguish each mode", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode = "move"
        state.renderLines, state.renderBoxes = {}, {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(#state.renderLines == 31 and #state.renderBoxes == 1, "move displays three arrow-tipped axes")
        editor.Mode = "rotate"
        state.renderLines, state.renderBoxes = {}, {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(#state.renderLines == 94 and #state.renderBoxes == 1, "rotate displays three circular handles")
        check(editor.GizmoPoints.x and #editor.GizmoPoints.x.segments == 24,
            "rotation ring segments are available for hit testing")
        editor.GizmoPoints = {
            x = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.rayHit = false
        state.planeHit = env.Vector(0, 72, 0)
        local panel = selectRingAndStartDrag(editor, state, env)
        check(editor.Drag and editor.Drag.kind == "rotate" and editor.Drag.axis == "x",
            "a selected rotation ring can be dragged")
        editor:ReleaseDrag(panel)
        editor.Mode = "scale"
        state.renderLines, state.renderBoxes = {}, {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        check(#state.renderLines == 25 and #state.renderBoxes == 4, "uniform scale displays three square-ended handles")
    end)

    suite:Add("rotation drag follows its selected ring and handles orbit and wrap", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode, editor.SnapEnabled = "rotate", false
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.planeHit = env.Vector(72, 0, 0)
        selectRingAndStartDrag(editor, state, env)
        check(editor.Drag and editor.Drag.kind == "rotate", "the selected ring starts a rotation")
        state.planeHit = env.Vector(0, 72, 0)
        state.mouseY = 100
        editor:UpdateDrag()
        local prop = editor.Document.props[1]
        check(math.abs(prop.angles.y - 90) < 0.0001, "a quarter-turn along the ring rotates by 90 degrees")
        state.planeHit = env.Vector(72, 0, 0)
        state.mouseY = 50
        editor:UpdateDrag()
        check(math.abs(prop.angles.y) < 0.0001, "dragging back reverses the rotation")
        state.planeHit = nil
        editor:UpdateDrag()
        check(math.abs(prop.angles.y) < 0.0001, "a missing plane intersection does not corrupt the rotation")
        local normal, first, second = editor:GetRotationBasis({ angles = { p = 0, y = 90, r = 0 } }, "x")
        check(math.abs(normal.x) < 0.0001 and math.abs(normal.y - 1) < 0.0001
            and math.abs(first.x + 1) < 0.0001 and math.abs(second.z - 1) < 0.0001,
            "roll ring follows the prop's yaw rather than staying on a fixed world axis")
    end)

    suite:Add("all rotation rings follow their displayed axes after yaw", function(check)
        for _, case in ipairs({
            { axis = "x", key = "r", start = { -72, 0, 0 }, finish = { 0, 0, 72 }, expected = 90 },
            { axis = "y", key = "p", start = { 0, 0, 72 }, finish = { 0, 72, 0 }, expected = 90 },
            { axis = "z", key = "y", start = { 72, 0, 0 }, finish = { 0, 72, 0 }, expected = 180 }
        }) do
            local env, state, editor = fixture()
            state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
            state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
            local prop = editor.Document.props[1]
            prop.angles.y = 90
            editor.Mode, editor.SnapEnabled = "rotate", false
            editor.GizmoPoints = {
                [case.axis] = { segments = { { start = { x = 0, y = 50, visible = true },
                    finish = { x = 100, y = 50, visible = true } } } }
            }
            state.planeHit = env.Vector(case.start[1], case.start[2], case.start[3])
            selectRingAndStartDrag(editor, state, env)
            state.planeHit = env.Vector(case.finish[1], case.finish[2], case.finish[3])
            state.mouseX = state.mouseX + 20
            editor:UpdateDrag()
            check(math.abs(prop.angles[case.key] - case.expected) < 0.0001,
                case.axis .. " ring turns in its displayed positive direction")
        end
    end)

    suite:Add("rotation snapping follows the configured step", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode, editor.SnapEnabled, editor.RotationSnap = "rotate", true, 15
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.planeHit = env.Vector(72, 0, 0)
        selectRingAndStartDrag(editor, state, env)
        local angle = math.rad(8)
        state.planeHit = env.Vector(72 * math.cos(angle), 72 * math.sin(angle), 0)
        state.mouseX = state.mouseX + 20
        editor:UpdateDrag()
        check(editor.Document.props[1].angles.y == 15, "eight degrees snaps to the nearest 15-degree step")
        editor.SnapEnabled = false
        editor:UpdateDrag()
        check(math.abs(editor.Document.props[1].angles.y - 8) < 0.0001,
            "disabling snap exposes the continuous angle without restarting the drag")
    end)

    suite:Add("a single click selects a ring and viewport drags keep it selected", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode, editor.SnapEnabled = "rotate", false
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        local panel = { capture = false, MouseCapture = function(self, value) self.capture = value end }
        state.planeHit = env.Vector(72, 0, 0)
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Drag == nil and editor.RotationSelection and editor.RotationSelection.axis == "z"
            and editor.Document.props[1].angles.y == 0, "a single click selects the ring without rotating")
        editor:ReleaseDrag(panel)
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel, env.MOUSE_LEFT)
        check(editor.RotationSelection and editor.RotationSelection.axis == "z",
            "clicking the selected ring without dragging keeps it selected")
        state.mouseX, state.mouseY = 250, 200
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Drag and editor.Drag.kind == "rotate" and editor.Drag.axis == "z" and panel.capture,
            "dragging can begin away from the selected ring")
        editor:ReleaseDrag(panel, env.MOUSE_RIGHT)
        check(editor.Drag and panel.capture, "releasing another button does not end the left-button drag")
        state.renderLines = {}
        state.hooks["ZM.PrefabEditor.Render"](false, false)
        local highlighted = 0
        for _, line in ipairs(state.renderLines) do
            local color = line[3]
            if color.r == 255 and color.g == 220 and color.b == 100 then highlighted = highlighted + 1 end
        end
        check(highlighted == 24, "the selected ring is highlighted separately")
        state.planeHit = env.Vector(0, 72, 0)
        state.mouseY = 240
        editor:UpdateDrag()
        check(math.abs(editor.Document.props[1].angles.y - 90) < 0.0001,
            "dragging rotates along the selected ring")
        editor:ReleaseDrag(panel)
        check(editor.Drag == nil and not panel.capture and editor.RotationSelection.axis == "z",
            "releasing a drag keeps the ring selected")
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel)
        check(editor.Drag == nil and not panel.capture and editor.RotationSelection == nil
            and math.abs(editor.Document.props[1].angles.y - 90) < 0.0001, "clicking elsewhere deselects and keeps the rotation")
    end)

    suite:Add("clicking a crossing selects a ring without rotating", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode = "rotate"
        local segment = { start = { x = 0, y = 50, visible = true }, finish = { x = 100, y = 50, visible = true } }
        local panel = { MouseCapture = function() end }
        editor.GizmoPoints = { x = { segments = { segment } }, z = { segments = { segment } } }
        state.planeHit = env.Vector(72, 0, 0)
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Drag == nil and editor.RotationSelection and editor.RotationSelection.axis == "x"
            and editor.Document.props[1].angles.y == 0,
            "clicking overlapping handles selects one deterministically without rotating")
    end)

    suite:Add("double-clicking a prop still cycles after ring selection", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode = "rotate"
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        local panel = { MouseCapture = function() end }
        state.planeHit = env.Vector(72, 0, 0)
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel, env.MOUSE_LEFT)
        state.mouseX, state.mouseY, state.rayHit, state.now = 250, 200, true, 1
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel, env.MOUSE_LEFT)
        state.now = 1.2
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        check(editor.Mode == "scale" and editor.RotationSelection == nil,
            "the first prop click deselects the ring and the second cycles the mode")
    end)

    suite:Add("changing the selected prop or document clears rotation state", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode = "rotate"
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.planeHit = env.Vector(72, 0, 0)
        local panel = selectRingAndStartDrag(editor, state, env)
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(editor.Selected == 2 and editor.RotationSelection == nil and editor.Drag == nil and not panel.capture,
            "adding a prop releases the previous selection and capture")
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel, env.MOUSE_LEFT)
        editor.PropList:OnRowSelected(1, { PrefabIndex = 1 })
        check(editor.Selected == 1 and editor.RotationSelection == nil and editor.ModeButton.text == "MODE: ROTATE",
            "changing the prop list selection clears the old ring highlight")
        editor:BeginDrag(panel, env.MOUSE_LEFT)
        editor:ReleaseDrag(panel, env.MOUSE_LEFT)
        editor:SetDocument(editor.Document, nil)
        check(editor.RotationSelection == nil and editor.ModeButton.text == "MODE: ROTATE",
            "opening another document resets the ring and mode label")
    end)

    suite:Add("right-click cancels a rotation drag and releases the mouse", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode, editor.SnapEnabled = "rotate", false
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.planeHit = env.Vector(72, 0, 0)
        local panel = selectRingAndStartDrag(editor, state, env)
        state.planeHit = env.Vector(0, 72, 0)
        state.mouseY = 100
        editor:UpdateDrag()
        editor:BeginDrag(panel, env.MOUSE_RIGHT)
        check(editor.Drag == nil and not panel.capture and editor.Document.props[1].angles.y == 0,
            "cancel restores the original angle and releases mouse capture")
    end)

    suite:Add("middle-click resets only the clicked prop rotation", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local prop = editor.Document.props[1]
        prop.position.x, prop.position.y, prop.scale = 40, -20, 1.5
        prop.angles.p, prop.angles.y, prop.angles.r = 15, 60, -30
        editor:UpdateModel(1)
        state.rayHit = true
        editor:BeginDrag({ MouseCapture = function() end }, env.MOUSE_MIDDLE)
        check(prop.angles.p == 0 and prop.angles.y == 0 and prop.angles.r == 0,
            "middle-click returns the clicked prop to zero local rotation")
        check(prop.position.x == 40 and prop.position.y == -20 and prop.scale == 1.5,
            "position and uniform scale remain unchanged")
        check(editor.Selected == 1 and editor.Dirty and state.models[1].angles.y == 0,
            "the selected preview and document update together")
        check(editor.Mode == "move" and editor.ModeButton.text == "MODE: MOVE",
            "resetting rotation does not change the active mode label")
    end)

    suite:Add("middle-clicking empty space does not reset a prop", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Document.props[1].angles.y = 45
        state.rayHit = false
        editor:BeginDrag({ MouseCapture = function() end }, env.MOUSE_MIDDLE)
        check(editor.Document.props[1].angles.y == 45, "empty-space middle-click leaves the prop unchanged")
    end)

    suite:Add("middle-click resets the selected prop during a rotation drag", function(check)
        local env, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        editor.Mode, editor.SnapEnabled = "rotate", false
        editor.GizmoPoints = {
            z = { segments = { { start = { x = 0, y = 50, visible = true },
                finish = { x = 100, y = 50, visible = true } } } }
        }
        state.planeHit = env.Vector(72, 0, 0)
        local panel = selectRingAndStartDrag(editor, state, env)
        state.planeHit = env.Vector(0, 72, 0)
        state.mouseY = 100
        editor:UpdateDrag()
        state.rayHit = true
        editor:BeginDrag(panel, env.MOUSE_MIDDLE)
        check(editor.Drag == nil and not panel.capture and editor.Document.props[1].angles.y == 0,
            "middle-click resets the rotation and releases the drag")
    end)
    return suite
end
