return function(createEngine, loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local contract = loadChunk("prefabs/sh_contract.lua")()
        local createStorage = loadChunk("prefabs/sv_storage.lua")()
        local createStorageEngine = loadChunk("tests/fixtures/sv_prefab_storage_engine.lua")()
        local createLoot = loadChunk("prefabs/sv_loot.lua")()
        local env, state = createEngine(contract, createStorage, createStorageEngine, createLoot)
        local function load()
            local chunk = loadChunk("sv_prefab_editor.lua")
            setfenv(chunk, env)
            return chunk()
        end
        return env, state, load, load()
    end

    suite:Add("explorer reads are limited to preview admins and the editor owner", function(check)
        local env, state, load, editor = fixture()
        local document = { schemaVersion = 1, id = "shared", name = "Shared", description = "",
            tags = { "road" }, props = {} }
        local storage = loadChunk("prefabs/sv_storage.lua")()(env.file, env.util,
            loadChunk("prefabs/sh_contract.lua")(), env.util.IsValidModel)
        check(storage.Save(document), "fixture prefab is saved")
        local response = state:Request("explorer_list")
        check(response.values[2] == true and #env.util.JSONToTable(response.values[4]) == 1,
            "preview admin can list the shared library")
        response = state:Request("explorer_preview", "shared")
        check(response.values[2] == true and env.util.JSONToTable(response.values[4]).id == "shared",
            "preview admin can load a validated document without opening the editor")
        response = state:Request("explorer_rename", "shared", "New name")
        check(response.values[2] and storage.Load("shared").name == "New name",
            "renaming preserves the stable ID")
        document.id = "other"
        document.name = "New name"
        check(storage.Save(document), "different IDs may have the same display name")
        check(not state:Request("explorer_rename", "shared", " ").values[2],
            "an invalid display name cannot be saved")
        state.target.admin = false
        check(not state:Request("explorer_list").values[2], "non-admin cannot browse the library")
        check(not state:Request("explorer_delete", "shared").values[2] and storage.Load("shared"),
            "non-admin cannot delete a shared prefab")
        state.target.admin = true
        state.target.ZM_LauncherState = "deploying"
        check(not state:Request("explorer_preview", "shared").values[2], "deploying players cannot browse")
        state.target.ZM_LauncherState = "menu"
        state.map = "zn_city_start"
        check(not state:Request("explorer_list").values[2], "city launcher cannot browse preview prefabs")
        state.map = "zn_preview_start"
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor owner enters workspace")
        check(state:Request("explorer_preview", "shared").values[2], "editor owner can browse")
        check(state:Request("load", "shared").values[2], "the editor opens a prefab")
        check(not state:Request("explorer_rename", "shared", "Different").values[2]
            and not state:Request("explorer_delete", "shared").values[2] and storage.Load("shared"),
            "explorer management cannot invalidate the document currently open in the editor")
        check(state:Request("new").values[2] and state:Request("explorer_rename", "shared", "Different").values[2],
            "starting a new document releases the previous server-side open target")
        state.humans[2] = {}
        check(not state:Request("explorer_list").values[2], "a late joiner blocks editor browsing")
        state.humans[2] = nil
        check(not state:Request("explorer_preview", "../shared").values[2], "invalid IDs are rejected")
        check(state:Request("explorer_delete", "other").values[2] and not storage.Load("other"),
            "the editor owner can delete a different prefab from the shared library")
    end)

    suite:Add("launcher explorer carries a validated prefab into the editor", function(check)
        local env, state, load, editor = fixture()
        local storage = loadChunk("prefabs/sv_storage.lua")()(env.file, env.util,
            loadChunk("prefabs/sh_contract.lua")(), env.util.IsValidModel)
        local document = { schemaVersion = 1, id = "shared", name = "Shared", description = "",
            tags = {}, props = {} }
        check(storage.Save(document), "fixture prefab is saved")
        check(not state:Request("begin", "missing").values[2] and #state.commands == 0,
            "a missing prefab does not start a session")
        check(not state:Request("begin", "../shared").values[2] and #state.commands == 0,
            "an invalid prefab ID does not start a session")
        check(state:Request("begin", "shared").values[2], "a validated prefab starts the editor session")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "the owner enters the editor workspace")
        local response = state:Request("status")
        local status = env.util.JSONToTable(response.values[4])
        check(response.values[2] and status.openId == "shared", "workspace status carries the selected ID")
        check(state:Request("load", status.openId).values[2] and editor.OpenedId == "shared",
            "the selected prefab loads through the usual validated editor path")
    end)

    suite:Add("isolated fixture reuses the owner-only editor session without a survivor", function(check)
        local _, state, load, editor = fixture()
        state.humans[2] = {}
        check(not editor:Begin(state.target, nil, true) and #state.commands == 0,
            "fixture entry refuses a second connected human")
        state.humans[2] = nil
        check(editor:Begin(state.target, nil, true) and state.commands[1] == "changelevel zn_dev_prefab_anchor\n",
            "the launcher owner can start the isolated fixture")
        state.map = "gm_flatgrass"
        editor = load()
        check(not editor:IsOwner(state.target), "a fixture marker does not authorize an ordinary editor map")
        state.map = "zn_dev_prefab_anchor"
        editor = load()
        state.humans[2] = {}
        check(editor:HandleSpawn(state.target) and state.target.frozen,
            "a late joiner prevents fixture access")
        state.humans[2] = nil
        check(editor:HandleSpawn(state.target) and not state.target.frozen and not state.target.hidden
            and state.target["ZM.PrefabEditorActive"] and editor:IsFixtureMap(),
            "the owner can move in the fixture without loading a survivor")
        check(state.target.survivor.health == 87 and state.target.survivor.cell == 12,
            "fixture entry does not mutate survivor data")
        local response = state:Request("end")
        check(response.values[2] and state.commands[2] == "changelevel zn_preview_start\n"
            and state.files["zombiesim/prefab_editor_session.json"] == nil,
            "fixture return clears its own marker and opens the preview launcher")
    end)

    suite:Add("server rejects invalid loot settings before saving", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "owner enters editor")
        local document = {
            schemaVersion = 1, id = "loot_fixture", name = "Fixture", description = "", tags = {},
            props = { { model = "models/props_c17/oildrum001.mdl", propId = "p_a",
                position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                skin = 0, lootMode = "normal", lootGroup = "notReal", lootChance = 0.4 } }
        }
        local response = state:Request("save", env.util.TableToJSON(document))
        check(not response.values[2] and state.files["zombiesim/prefabs/loot_fixture.json"] == nil,
            "unknown group cannot be saved")
        document.props[1].lootGroup = "lootFixture"
        document.props[1].lootChance = nil
        response = state:Request("save", env.util.TableToJSON(document))
        check(not response.values[2] and state.files["zombiesim/prefabs/loot_fixture.json"] == nil,
            "a model without an existing rule requires an explicit normal chance")
        document.props[1].lootChance = 0.4
        response = state:Request("save", env.util.TableToJSON(document))
        check(response.values[2] and state.files["zombiesim/prefabs/loot_fixture.json"] ~= nil,
            "known group and explicit chance save successfully")
    end)

    suite:Add("editor entry requires the preview launcher admin alone", function(check)
        local env, state, _, editor = fixture()
        state.target.admin = false
        local ok = editor:Begin(state.target)
        check(not ok and #state.commands == 0, "non-admin cannot change the map")
        state.target.admin = true
        state.humans[2] = {}
        ok = editor:Begin(state.target)
        check(not ok and #state.commands == 0, "a second human prevents the map change")
        state.humans[2] = nil
        state.map = "zn_city_start"
        ok = editor:Begin(state.target)
        check(not ok and #state.commands == 0, "city launcher cannot enter the editor")
        state.map = "zn_preview_start"
        state.target.ZM_LauncherState = "deploying"
        ok = editor:Begin(state.target)
        check(not ok and #state.commands == 0, "deployment cannot race the editor transition")
        state.target.ZM_LauncherState = "menu"
        env.ZM_MapBatch = { IsActive = function() return true end }
        ok = editor:Begin(state.target)
        check(not ok and #state.commands == 0, "active map maintenance prevents the editor transition")
        env.ZM_MapBatch = nil
        state.mounted = false
        ok = editor:Begin(state.target)
        check(not ok and #state.commands == 0, "missing flatgrass is reported")
        state.mounted = true
        ok = editor:Begin(state.target)
        check(ok and state.commands[1] == "changelevel gm_flatgrass\n", "authorized entry queues flatgrass")
        check(state.files["zombiesim/prefab_editor_session.json"] ~= nil, "owner session is persisted")
        check(state.target.survivor.health == 87 and state.target.survivor.cell == 12,
            "entry leaves survivor data untouched")
        check(state.target.ZM_LauncherState == "prefab_editor_transition",
            "launcher requests cannot race the map change")
    end)

    suite:Add("flatgrass editor spawn bypasses survivor loading", function(check)
        local _, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor spawn is handled")
        check(state.target.frozen and state.target.hidden and state.target.god,
            "editor player is isolated from gameplay")
        check(state.target.ZM_PrefabEditorOrigin and state.target.ZM_PrefabEditorOrigin.x == 3072,
            "workspace uses the traced floor")
        check(state.trace.start.z == -11263 and state.trace.endpos.z == -13311,
            "workspace trace brackets the actual spawn elevation instead of assuming world origin")
        state.hooks["ZM.PrefabEditor.PVS"](state.target)
        check(state.pvs == state.target.ZM_PrefabEditorOrigin, "workspace is included in the editor owner's PVS")
        local status = editor:GetStatus(state.target)
        check(status.editorMap and status.participant and status.origin.z == -12288
            and not status.persistentStateLoaded, "read-only status distinguishes editor workspace from survivor loading")
        check(state.target.survivor.health == 87 and state.target.survivor.cell == 12,
            "editor spawn does not load or mutate survivor state")
        local response = state:Request("status")
        check(response.values[2] == true, "editor status is available to its owner")
    end)

    suite:Add("a stale launcher session can be cleared by its owner", function(check)
        local _, state, _, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        local response = state:Request("recover")
        check(response.values[2] == true and state.target.ZM_LauncherState == "menu",
            "owner can explicitly clear the stale session")
        check(state.files["zombiesim/prefab_editor_session.json"] == nil, "session marker is removed")
        check(editor:Begin(state.target), "a new session can start after recovery")
    end)

    suite:Add("other players and corrupt sessions cannot enter gameplay", function(check)
        local _, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        local other = { admin = true, identity = "76561198000000001", valid = true }
        function other:IsAdmin() return self.admin end
        function other:SteamID64() return self.identity end
        function other:StripWeapons() self.stripped = true end
        function other:Freeze(value) self.frozen = value end
        function other:GodEnable() self.god = true end
        function other:SetNoDraw(value) self.hidden = value end
        function other:ChatPrint(message) self.message = message end
        state.humans[2] = other
        check(editor:HandleSpawn(other) and other.frozen and other.message ~= nil,
            "an unexpected player remains in the isolated editor session")
        check(not editor:IsParticipant(state.target), "the owner cannot issue editor requests while another player is present")
        state.humans[2] = nil
        state.files["zombiesim/prefab_editor_session.json"] = "invalid"
        check(editor:HandleSpawn(state.target) and state.target.frozen and state.target.message ~= nil,
            "a corrupt session cannot fall through to ordinary survivor spawning")
    end)

    suite:Add("exit retains the editor guard during the return transition", function(check)
        local _, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor spawn is handled")
        local response = state:Request("end")
        check(response.values[2] == true and state.commands[2] == "changelevel zn_preview_start\n",
            "exit returns to the preview launcher")
        check(state.files["zombiesim/prefab_editor_session.json"] == nil, "completed session marker is removed")
        check(editor:IsEditorMap(), "disconnect guard remains active during map teardown")
        check(state.target.survivor.health == 87 and state.target.survivor.cell == 12,
            "exit leaves survivor data unchanged")
    end)

    suite:Add("the owner can exit if another player joins", function(check)
        local _, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor spawn is handled")
        state.humans[2] = {}
        local response = state:Request("end")
        check(response.values[2] == true and state.commands[2] == "changelevel zn_preview_start\n",
            "a late joiner cannot trap the owner on the editor map")
    end)

    suite:Add("network edits require the server to have opened the prefab", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor spawn is handled")
        local document = {
            schemaVersion = 1, id = "test_prefab", name = "Test prefab", description = "",
            tags = {}, props = {
                { model = "models/props_c17/oildrum001.mdl", position = { x = 0, y = 0, z = 0 },
                    angles = { p = 0, y = 0, r = 0 }, skin = 0 }
            }
        }
        local encoded = env.util.TableToJSON(document)
        check(state:Request("save", encoded).values[2] == true, "new prefab can be saved")
        editor.OpenedId = nil
        document.name = "Changed"
        encoded = env.util.TableToJSON(document)
        check(state:Request("save", encoded, "test_prefab").values[2] == false,
            "a forged opened ID cannot overwrite a saved prefab")
        check(state:Request("delete", "test_prefab").values[2] == false,
            "a prefab cannot be deleted without opening it")
        check(state:Request("load", "test_prefab").values[2] == true, "saved prefab can be opened")
        check(state:Request("save", encoded, "test_prefab").values[2] == true,
            "the opened prefab can be saved")
        check(state:Request("delete", "test_prefab").values[2] == true,
            "the opened prefab can be deleted")
        check(state:Request("model", "models/../bad.mdl").values[2] == false,
            "invalid model paths are rejected")
    end)

    suite:Add("reference tile choices are validated independently of prefab props", function(check)
        local _, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor spawn is handled")
        local model = "models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl"
        state.referenceModels = { "road_ac5d4d36ced7_v1.mdl" }
        check(state:Request("references").values[2] == true, "the staged road is listed")
        check(state:Request("reference", model).values[2] == true, "the staged road can be selected")
        check(state:Request("reference", "models/props_c17/oildrum001.mdl").values[2] == false,
            "arbitrary props cannot be substituted as reference tiles")
        state.referenceModels = { "unexpected.mdl" }
        check(state:Request("references").values[2] == false, "unexpected reference files are reported")
    end)
    return suite
end
