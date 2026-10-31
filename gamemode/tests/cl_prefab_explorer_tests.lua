return function(createEngine, loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local gizmo = loadChunk("prefabs/sh_gizmo.lua")()
        local contract = loadChunk("prefabs/sh_contract.lua")()
        local env, state = createEngine(gizmo, contract, loadChunk("prefabs/sh_editor_map.lua")(),
            loadChunk("prefabs/cl_editor_transfer.lua")())
        local editorChunk = loadChunk("cl_prefab_editor.lua")
        setfenv(editorChunk, env)
        editorChunk()
        local explorerChunk = loadChunk("cl_prefab_explorer.lua")
        setfenv(explorerChunk, env)
        explorerChunk()
        return env, state, env.ZM_PrefabExplorer, env.ZM_PrefabEditorClient
    end
    local function document(id, name, tags, props)
        return { schemaVersion = 1, id = id, name = name, description = "A description",
            tags = tags or {}, props = props or {} }
    end
    local function prop(x)
        return { model = "models/props_c17/oildrum001.mdl", position = { x = x, y = 0, z = 0 },
            angles = { p = 0, y = 30, r = 0 }, skin = 0, scale = 1.5 }
    end
    local function findButton(state, text)
        for _, panel in ipairs(state.panels) do
            if panel.kind == "DButton" and panel.text == text then return panel end
        end
    end

    suite:Add("explorer lists and filters shared prefabs", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        check(state.requests[#state.requests].values[1] == "explorer_list", "opening requests the library")
        state:Response("explorer_list", true, "", {
            document("one", "Same", { "road" }), document("two", "Same", { "gate" })
        })
        check(#explorer.List.lines == 2, "duplicate names remain separately identified by ID")
        explorer.Search:TypeText("TWO")
        check(#explorer.List.lines == 1 and explorer.List.lines[1].PrefabId == "two",
            "search is case-insensitive and includes IDs")
        explorer.Search:TypeText("")
        explorer.Tag:TypeText("ROAD")
        check(#explorer.List.lines == 1 and explorer.List.lines[1].PrefabId == "one",
            "tag filter matches exact tags without case sensitivity")
        explorer.Tag:TypeText("ro")
        check(#explorer.List.lines == 0, "partial tags do not match an exact tag filter")
    end)

    suite:Add("explorer shows world placement and offers suggested tag filters", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        local value = document("unique", "Unique", { "customTag" })
        value.worldPlacement = { enabled = true, profile = "preview", cellX = 14, cellY = 0,
            tileX = -1, tileY = 2, offset = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 } }
        state:Response("explorer_list", true, "", { value, document("other", "Other") })
        explorer.TagSuggestions:OnSelect(1, "customTag", "customTag")
        check(#explorer.List.lines == 1 and explorer.List.lines[1].PrefabId == "unique",
            "suggestion selection filters the library while retaining custom text")
        explorer.Selected = { id = "unique" }
        state:Response("explorer_preview", true, "", value)
        check(string.find(explorer.Details.text, "preview cell (14,0), tile (-1,2), enabled", 1, true),
            "preview details distinguish an explicit world placement from ordinary tags")
    end)

    suite:Add("explorer uses game styling and fits a smaller screen", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        check(explorer.Frame.skin == "ZombieSim" and explorer.Left.wide == 400
            and explorer.List.headerHeight == 20 and type(explorer.List.Paint) == "function",
            "library and preview use the game skin and styled list")
        state:Response("explorer_list", true, "", { document("one", "One") })
        check(type(explorer.List.lines[1].Paint) == "function", "library rows use the themed selection style")
        state.screenWidth, state.screenHeight = 800, 600
        state.hooks["ZM.PrefabExplorer.Resize"]()
        check(explorer.Frame.width == 760 and explorer.Frame.height == 560 and explorer.Left.wide == 304,
            "screen changes resize and recenter the library layout")
    end)

    suite:Add("preview draws all props and releases its models", function(check)
        local env, state, explorer = fixture()
        explorer:Open()
        explorer.Selected = { id = "one" }
        state:Response("explorer_preview", true, "", document("other", "Other", {}, { prop(0) }))
        check(explorer.Preview == nil, "late responses do not replace the selected prefab")
        state:Response("explorer_preview", true, "", document("one", "One", { "road" }, { prop(0), prop(100) }))
        local panel, additional = explorer.Preview, explorer.PreviewModels[1]
        check(panel and panel:GetEntity().matrix.scale.x == 1.5 and additional.position.x == 100
            and additional.angles.y == 30, "preview preserves model positions, angles and scale")
        panel:PostDrawModel(panel:GetEntity())
        check(additional.drawn, "additional models draw in the model panel's 3D context")
        local before = panel.camPos
        panel:OnMousePressed(env.MOUSE_LEFT)
        state.mouseX = state.mouseX + 30
        panel:Think()
        panel:OnMouseReleased(env.MOUSE_LEFT)
        check(not panel.capture and panel.camPos.x ~= before.x, "left-drag orbits and releases capture")
        local frame = explorer.Frame
        frame:Close()
        check(not panel.valid and not additional.valid and not panel:GetEntity().valid,
            "closing releases the panel and all preview models")
        state:Response("explorer_preview", true, "", document("one", "One", {}, { prop(0) }))
        check(explorer.Frame == nil and explorer.Preview == nil, "late replies do not reopen the explorer")
    end)

    suite:Add("empty prefabs and request failures are visible", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        explorer.Selected = { id = "empty" }
        state:Response("explorer_preview", true, "", document("empty", "Empty"))
        check(explorer.Preview == nil and string.find(explorer.Details.text, "no props", 1, true),
            "empty prefabs are reported without a placeholder model")
        state:Response("explorer_preview", false, "Missing prefab")
        check(#state.messages > 0, "request errors are surfaced")
    end)

    suite:Add("guard-only and mixed prefabs preview their guards and release models", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        explorer.Selected = { id = "guard_only" }
        local value = document("guard_only", "Guard")
        value.guards = { {
            guardId = "guard_1", name = "Alex", model = "models/player/group01/male_03.mdl",
            position = { x = 20, y = 30, z = 0 }, angles = { p = 0, y = 90, r = 0 },
            idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "shirt_blue", pants = "pants_black"
        } }
        state:Response("explorer_preview", true, "", value)
        check(not explorer.Preview and state.requests[#state.requests].values[1] == "explorer_guard_weapons",
            "guard-only previews wait for the authorized weapon catalogue")
        state:Response("explorer_guard_weapons", true, "", {
            { id = "pistol", label = "9mm Handgun", model = "models/weapons/w_pistol.mdl",
                range = 3000, damage = 12, delay = 0.2, spread = 0.02 }
        })
        local panel = explorer.Preview
        local entry = explorer.GuardPreviews[1]
        check(panel and entry and entry.panelModel and entry.instance.model == panel:GetEntity()
            and entry.instance.guard.shirt == "shirt_blue" and entry.instance.model.position.x == 20,
            "the panel owns the guard body with its authored transform and clothing")
        panel:PostDrawModel()
        check(entry.instance.weaponDrawn and not entry.instance.model.drawn,
            "the guard weapon is drawn without drawing the panel body twice")
        value.props = { prop(0) }
        explorer:ShowPreview(value)
        check(not panel.valid and not entry.instance.model.valid and #explorer.GuardPreviews == 1
            and not explorer.GuardPreviews[1].panelModel, "mixed previews release and replace guard models")
        local mixed = explorer.GuardPreviews[1].instance
        explorer.Preview:PostDrawModel()
        check(mixed.model.drawn and mixed.weaponDrawn, "mixed previews draw the guard and weapon beside the prop")
        explorer.Frame:Close()
        check(not mixed.model.valid, "closing the explorer removes guard previews")
    end)

    suite:Add("explorer reports lights are previewed in the editor", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        explorer.Selected = { id = "light" }
        local value = document("light", "Light", {}, { prop(0) })
        value.lights = { { lightId = "light_1" } }
        value.particles = { { particleId = "particle_1" } }
        state:Response("explorer_preview", true, "", value)
        check(string.find(explorer.Details.text, "Spotlights: 1", 1, true)
            and string.find(explorer.Details.text, "previewed in editor only", 1, true)
            and string.find(explorer.Details.text, "Particles: 1 (not shown here)", 1, true),
            "model panel does not imply lights or particles have been rendered")
    end)

    suite:Add("management actions require confirmation", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        explorer.Selected = document("one", "Original")
        local count = #state.requests
        findButton(state, "RENAME"):DoClick()
        check(#state.requests == count and state.stringRequest, "rename prompts for a name")
        state.stringRequest[4]("Updated")
        check(#state.requests == count and state.query, "rename asks for explicit confirmation")
        state.query[4]()
        local request = state.requests[#state.requests]
        check(request.values[1] == "explorer_rename" and request.values[2] == "one"
            and request.values[3] == "Updated", "confirmation sends the stable ID and new display name")
        findButton(state, "DELETE"):DoClick()
        count = #state.requests
        state.query[6]()
        check(#state.requests == count, "cancelling deletion does not send a request")
        findButton(state, "DELETE"):DoClick()
        state.query[4]()
        check(state.requests[#state.requests].values[1] == "explorer_delete",
            "deletion is sent only after confirmation")
    end)

    suite:Add("opening from the editor retains the unsaved tab", function(check)
        local _, state, explorer, editor = fixture()
        state:Response("status", true, "", { origin = { x = 0, y = 0, z = 0 }, documents = {} })
        state:Response("model", true, "", { model = "models/props_c17/oildrum001.mdl" })
        explorer:Open()
        explorer.Selected = document("one", "One")
        findButton(state, "OPEN IN EDITOR"):DoClick()
        check(state.requests[#state.requests].values[1] == "load"
            and state.requests[#state.requests].values[2] == "one" and explorer.Frame == nil
            and editor.Dirty, "opening another prefab requests it without discarding the dirty tab")
        state:Response("load", true, "", document("one", "One"))
        check(editor:IsActive() and #editor.Tabs == 2 and editor.Tabs[1].Dirty,
            "the loaded prefab gets a separate tab and the original remains dirty")
    end)

    suite:Add("opening from the launcher carries the chosen ID", function(check)
        local _, state, explorer = fixture()
        explorer:Open()
        explorer.Selected = document("one", "One")
        local count = #state.requests
        findButton(state, "OPEN IN EDITOR"):DoClick()
        check(#state.requests == count and state.query, "map change requires confirmation")
        state.query[6]()
        check(#state.requests == count and explorer.Frame ~= nil, "cancel leaves the explorer open")
        findButton(state, "OPEN IN EDITOR"):DoClick()
        state.query[4]()
        check(state.requests[#state.requests].values[1] == "begin"
            and state.requests[#state.requests].values[2] == "one" and explorer.Frame == nil,
            "confirmation sends the selected ID and closes the explorer")
        state:Response("status", true, "", {
            origin = { x = 0, y = 0, z = 0 }, documents = {}, openId = "one"
        })
        check(state.requests[#state.requests].values[1] == "load"
            and state.requests[#state.requests].values[2] == "one",
            "workspace initialization loads the selected ID through the editor")
    end)
    return suite
end
