return function(createEngine, loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local gizmo = loadChunk("prefabs/sh_gizmo.lua")()
        local contract = loadChunk("prefabs/sh_contract.lua")()
        local env, state = createEngine(gizmo, contract)
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
    suite:Add("loot settings and prop identity follow the selected prop", function(check)
        local _, state, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        local first = editor.Document.props[1]
        check(first.lootMode == "off" and first.propId == "p_fixture1", "new props default to Off with a stable server ID")
        editor.LootMode:OnSelect(2, "Normal", "normal")
        editor.LootGroup:TypeText("lootGenericMedical")
        editor.LootChanceToggle:SetValue(1)
        editor.LootChance:SetValue(70)
        check(first.lootMode == "normal" and first.lootGroup == "lootGenericMedical"
            and math.abs(first.lootChance - 0.7) < 0.00001, "normal loot stores the selected group and configured chance")
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        check(editor.Document.props[2].lootMode == "off" and editor.Document.props[2].propId ~= first.propId,
            "another prop has an independent stable ID and loot mode")
        editor.LootMode:OnSelect(3, "Guaranteed", "guaranteed")
        editor.PropList:OnRowSelected(1, { PrefabIndex = 1 })
        check(editor.LootMode:GetValue() == "Normal" and editor.LootGroup:GetValue() == "lootGenericMedical"
            and editor.LootChance:GetValue() == 70, "reselecting restores the first prop's settings")
        editor.IdInput:SetValue("loot_test")
        editor.NameInput:SetValue("Loot test")
        editor:Save(false)
        local saved = state.json[state.requests[#state.requests].values[2]]
        check(saved and saved.props[1].propId == first.propId and saved.props[2].lootMode == "guaranteed",
            "the saved document retains per-prop identities and modes")
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
