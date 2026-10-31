return function(createEngine, loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local contract = loadChunk("prefabs/sh_contract.lua")()
        local createStorage = loadChunk("prefabs/sv_storage.lua")()
        local createStorageEngine = loadChunk("tests/fixtures/sv_prefab_storage_engine.lua")()
        local createLoot = loadChunk("prefabs/sv_loot.lua")()
        local env, state = createEngine(contract, createStorage, createStorageEngine, createLoot,
            loadChunk("prefabs/sh_editor_map.lua")())
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
        response = state:Request("explorer_guard_weapons")
        check(response.values[2] and #env.util.JSONToTable(response.values[4]) == 1,
            "preview admin can load guard-preview weapon choices")
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
        check(not state:Request("explorer_guard_weapons").values[2], "non-admin cannot request guard choices")
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
        check(state:Request("new").values[2] and not state:Request("explorer_rename", "shared", "Different").values[2],
            "starting another document keeps the earlier open target protected")
        check(state:Request("close", "shared").values[2] and state:Request("explorer_rename", "shared", "Different").values[2],
            "closing the tab releases its server-side protection")
        state.humans[2] = {}
        check(not state:Request("explorer_list").values[2], "a late joiner blocks editor browsing")
        state.humans[2] = nil
        check(not state:Request("explorer_preview", "../shared").values[2], "invalid IDs are rejected")
        check(state:Request("explorer_delete", "other").values[2] and not storage.Load("other"),
            "the editor owner can delete a different prefab from the shared library")
    end)

    suite:Add("guard weapon choices are available only to the editor owner", function(check)
        local env, state, load, editor = fixture()
        check(not state:Request("guard_weapons").values[2], "launcher requests cannot access editor choices")
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor owner enters workspace")
        local response = state:Request("guard_weapons")
        local choices = env.util.JSONToTable(response.values[4])
        check(response.values[2] and #choices == 1 and choices[1].id == "pistol"
            and choices[1].damage == 12 and choices[1].model == "models/weapons/w_pistol.mdl",
            "the server returns the resolved guard weapon data")
        state.guardWeaponError = "weapon registry unavailable"
        response = state:Request("guard_weapons")
        check(not response.values[2] and response.values[3] == state.guardWeaponError,
            "catalogue failures are reported")
        state.guardWeaponError = nil
        state.humans[2] = {}
        check(not state:Request("guard_weapons").values[2], "a late joiner blocks access")
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

    suite:Add("map switches retain owner authorization and protect the preview session", function(check)
        local env, state, load, editor = fixture()
        local storage = loadChunk("prefabs/sv_storage.lua")()(env.file, env.util,
            loadChunk("prefabs/sh_contract.lua")(), env.util.IsValidModel)
        check(storage.Save({ schemaVersion = 1, id = "saved", name = "Saved", description = "", tags = {}, props = {} }),
            "saved tab fixture is available")
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target) and state:Request("load", "saved").values[2], "the owner opens a saved tab")
        local maps = state:Request("maps")
        local listed = env.util.JSONToTable(maps.values[4])
        check(maps.values[2] and #listed.recommended == 2 and listed.recommended[1] == "gm_construct"
            and #listed.custom == 1 and listed.custom[1] == "custom_map",
            "recommended and custom mounted maps are separated and generated maps excluded")
        local function request(map, ids)
            return state:Request("switch_map", env.util.TableToJSON({ map = map, token = "switch_123", openIds = ids }))
        end
        check(not request("gm_construct;quit", { "saved" }).values[2], "command injection is rejected")
        local rejected = request("zn_city_start", { "saved" })
        check(not rejected.values[2] and env.util.JSONToTable(rejected.values[4]).markerUnchanged,
            "the city launcher is reserved without changing the session marker")
        check(not request("gm_construct", {}).values[2], "missing open-tab authorization is rejected")
        check(not request("missing_map", { "saved" }).values[2], "unmounted maps are rejected")
        state.profileMaps = { custom_map = "city" }
        check(not request("custom_map", { "saved" }).values[2], "a known production-world map is rejected")
        state.profileMaps = nil
        state.worldCells = { custom_map = { { id = 1 } } }
        check(not request("custom_map", { "saved" }).values[2], "a shared preview-world cell is rejected")
        state.worldCells.custom_map = "invalid"
        check(not request("custom_map", { "saved" }).values[2], "malformed world-index results fail explicitly")
        state.worldCells = nil
        state.safeZones = { { id = "den" } }
        state.safeZoneMaps = { den = "maps/custom_map" }
        check(not request("custom_map", { "saved" }).values[2], "a preview safe-zone map is rejected")
        state.safeZones, state.safeZoneMaps = nil, nil
        local response = request("gm_construct", { "saved" })
        local session = env.util.JSONToTable(state.files["zombiesim/prefab_editor_session.json"])
        check(response.values[2] and session.map == "gm_construct" and session.previousMap == "gm_flatgrass"
            and session.transferToken == "switch_123" and session.openIds[1] == "saved"
            and state.commands[#state.commands] == "changelevel gm_construct\n",
            "the destination and open IDs are committed before the map transition")
        check(editor:IsOwner(state.target) and not state:Request("end").values[2],
            "the owner stays protected on the source map but cannot discard a pending draft")
        state.map = "gm_construct"
        editor = load()
        check(editor:HandleSpawn(state.target) and editor:IsParticipant(state.target)
            and state.trace.start.x == 0 and state.trace.start.y == 0 and state.trace.start.z == -12223,
            "the new workspace is located from its player spawn")
        local status = state:Request("status")
        check(env.util.JSONToTable(status.values[4]).transferToken == "switch_123"
            and state:Request("activate", "saved").values[2], "the new map restores server-side tab authorization")
        check(not state:Request("switch_complete", "wrong").values[2], "a mismatched completion token is rejected")
        check(state:Request("switch_complete", "switch_123").values[2], "the matching completion is accepted")
        session = env.util.JSONToTable(state.files["zombiesim/prefab_editor_session.json"])
        check(session.map == "gm_construct" and session.transferToken == nil and session.previousMap == nil,
            "completion clears only the transfer state")
    end)

    suite:Add("failed session writes and mismatched maps preserve the survivor boundary", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "the owner enters the workspace")
        state.storage.fail.renameFrom = "zombiesim/prefab_editor_session.pending.json"
        local request = env.util.TableToJSON({ map = "gm_construct", token = "switch_123", openIds = {} })
        local result = state:Request("switch_map", request)
        local session = env.util.JSONToTable(state.files["zombiesim/prefab_editor_session.json"])
        check(not result.values[2] and not env.util.JSONToTable(result.values[4]).markerUnchanged
            and session.map == "gm_flatgrass" and #state.commands == 1
            and state.files["zombiesim/prefab_editor_session.pending.json"] ~= nil,
            "failed publication restores the original marker and leaves recovery evidence")
        local checked = state:Request("switch_check")
        check(checked.values[2] and env.util.JSONToTable(checked.values[4]).safeToResume,
            "a separate owner-authorized check confirms the old session is still active")
        state.map = "custom_map"
        editor = load()
        check(editor:IsEditorMap() and not editor:IsOwner(state.target) and editor:HandleSpawn(state.target)
            and state.target.frozen and state.target.survivor.health == 87 and state.target.survivor.cell == 12,
            "a stale marker on an unexpected map prevents survivor loading")
    end)

    suite:Add("pending map switches can retry or return without discarding drafts", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "the owner enters the workspace")
        local request = env.util.TableToJSON({ map = "gm_construct", token = "switch_123", openIds = {} })
        check(state:Request("switch_map", request).values[2], "a switch is committed")
        local status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transitionTarget == "gm_construct" and status.transferToken == nil,
            "the source map reports a pending destination rather than restoring prematurely")
        check(state:Request("switch_retry").values[2] and state.commands[#state.commands] == "changelevel gm_construct\n",
            "the owner can retry a pending transition")
        state.map = "gm_construct"
        editor = load()
        check(editor:HandleSpawn(state.target), "the owner enters the destination")
        check(state:Request("switch_return").values[2] and state.commands[#state.commands] == "changelevel gm_flatgrass\n",
            "the owner can return to the previous map without clearing the draft token")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "the previous workspace reopens")
        status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transferToken == "switch_123" and state:Request("switch_complete", "switch_123").values[2],
            "the same draft can be restored after returning")
    end)

    suite:Add("mounted custom map browsing is paginated and searchable", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "the owner enters the workspace")
        for index = 1, 80 do state.mapFiles[#state.mapFiles + 1] = string.format("custom_%03d.bsp", index) end
        local options = env.util.TableToJSON({ query = "custom_", page = 2 })
        local response = state:Request("maps", options)
        local result = env.util.JSONToTable(response.values[4])
        check(response.values[2] and result.total == 81 and result.pages == 2 and result.page == 2
            and #result.custom == 33, "search results use bounded pages")
        local invalid = env.util.TableToJSON({ query = "", page = 0 })
        check(not state:Request("maps", invalid).values[2], "invalid pages are reported")
    end)

    suite:Add("preview cells use authoritative identity and centered surface tiles", function(check)
        local env, state, load, editor = fixture()
        state.cells = {
            { id = 302, worldX = 14, worldY = 0, map = "zz_preview_cell" },
            { id = 303, worldX = 15, worldY = 0, map = "zz_preview_cell" }
        }
        state.mountedMaps.zz_preview_cell = true
        local statusOk = state.statusCommand(nil, "zombiesim_prefab_cell_status", { "14", "0" })
        check(statusOk and state.report and state.report.name == "prefabCell" and state.report.value.id == 302
            and state.report.value.map == "zz_preview_cell", "read-only cell status uses logical world coordinates")
        check(not state.statusCommand(nil, "zombiesim_prefab_cell_status", { "14.5", "0" }),
            "fractional logical cell diagnostics are rejected")
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "the owner enters the workspace")
        local options = env.util.TableToJSON({ query = "14,0", page = 1 })
        local listed = env.util.JSONToTable(state:Request("cells", options).values[4])
        check(listed.total == 1 and listed.cells[1].id == 302 and listed.cells[1].x == 14
            and listed.cells[1].y == 0, "the cell picker uses logical coordinates and authoritative ID")
        local function switch(map, cellId, token)
            return state:Request("switch_map", env.util.TableToJSON({
                map = map, cellId = cellId, token = token, openIds = {}
            }))
        end
        check(not switch("zn_city_start", 302, "switch_123").values[2],
            "a forged cell map cannot select a production launcher")
        check(not switch("zz_preview_cell", 999, "switch_123").values[2], "unknown cell IDs are rejected")
        check(switch("zz_preview_cell", 302, "switch_123").values[2], "a matching preview cell starts the switch")
        state.map = "zz_preview_cell"
        editor = load()
        check(editor:HandleSpawn(state.target) and state.trace.mask == env.MASK_SOLID
            and state.trace.start.x == 0 and state.trace.start.y == 0 and state.trace.start.z == 4607
            and state.target.ZM_PrefabEditorOrigin.z == 32, "the default cell workspace is on the centre surface")
        local status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transferToken == "switch_123" and status.cell.id == 302 and status.cell.x == 14
            and status.cell.y == 0 and status.cell.tileX == 0 and status.cell.tileY == 0,
            "the destination reports the correct logical cell and centred tile")
        check(state:Request("switch_complete", "switch_123").values[2], "the cell transfer completes")
        local tile = env.util.TableToJSON({ x = 2, y = -1 })
        local changed = state:Request("cell_tile", tile)
        local value = env.util.JSONToTable(changed.values[4])
        check(changed.values[2] and value.x == 2 and value.y == -1 and value.origin.x == 1280
            and value.origin.y == -640 and value.origin.z == 32
            and state.target.ZM_PrefabEditorOrigin.x == 1280 and state.target.ZM_PrefabEditorOrigin.y == -640,
            "tile offsets use 640-unit east/north axes and the detected surface")
        local session = env.util.JSONToTable(state.files["zombiesim/prefab_editor_session.json"])
        check(session.cellId == 302 and session.tileX == 2 and session.tileY == -1
            and state.target.survivor.health == 87 and state.target.survivor.cell == 12,
            "tile settings persist in the editor marker without modifying survivor state")
        check(not state:Request("cell_tile", env.util.TableToJSON({ x = 3, y = 0 })).values[2]
            and not state:Request("cell_tile", env.util.TableToJSON({ x = 0.5, y = 0 })).values[2],
            "out-of-core and fractional tile requests are rejected")
        state.flat = false
        check(not state:Request("cell_tile", env.util.TableToJSON({ x = 0, y = 0 })).values[2]
            and state.target.ZM_PrefabEditorOrigin.x == 1280, "a missing surface leaves the workspace unchanged")
        state.flat, state.cellHeight = true, 0 / 0
        check(not state:Request("cell_tile", env.util.TableToJSON({ x = 0, y = 0 })).values[2],
            "non-finite surface positions are rejected")
        state.cellHeight = 32
        check(switch("zz_preview_cell", 303, "switch_456").values[2],
            "a different logical cell sharing the same BSP still requests a reload")
        status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transitionTarget == "zz_preview_cell" and status.transferToken == nil
            and not state:Request("switch_complete", "switch_456").values[2],
            "the old map instance cannot acknowledge a same-BSP transfer")
        editor = load()
        check(editor:HandleSpawn(state.target), "the shared BSP reload enters the new logical cell")
        status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transferToken == "switch_456" and status.cell.id == 303 and status.cell.tileX == 0,
            "the new map instance restores the distinct cell at its centre")
        check(state:Request("switch_return").values[2], "the cell transfer can return to the previous cell")
        status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transitionTarget == "zz_preview_cell" and status.transferToken == nil,
            "same-BSP recovery also requires a fresh map instance")
        editor = load()
        check(editor:HandleSpawn(state.target), "the previous cell reloads")
        status = env.util.JSONToTable(state:Request("status").values[4])
        check(status.transferToken == "switch_456" and status.cell.id == 302
            and status.cell.tileX == 2 and status.cell.tileY == -1
            and state:Request("switch_complete", "switch_456").values[2],
            "returning restores the prior cell and tile without losing the draft token")
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

    suite:Add("server rejects particle effects outside the catalog", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "owner enters editor")
        local document = {
            schemaVersion = 1, id = "particle_fixture", name = "Fixture", description = "", tags = {}, props = {},
            particles = { { particleId = "p_1", effect = "unknown", position = { x = 0, y = 0, z = 0 },
                angles = { p = 0, y = 0, r = 0 }, mode = "triggered", overlap = false } }
        }
        local response = state:Request("save", env.util.TableToJSON(document))
        check(not response.values[2] and state.files["zombiesim/prefabs/particle_fixture.json"] == nil,
            "unknown effect cannot be saved")
        document.particles[1].effect = "steam"
        response = state:Request("save", env.util.TableToJSON(document))
        check(response.values[2] and state.files["zombiesim/prefabs/particle_fixture.json"] ~= nil,
            "catalog effect can be saved")
        response = state:Request("particles")
        local effects = env.util.JSONToTable(response.values[4])
        check(response.values[2] and effects and effects[1].id == "steam",
            "authorized editor receives the validated selectable effects")
    end)
    suite:Add("server validates guard content before saving", function(check)
        local env, state, _, editor = fixture()
        state.map, state.profile = "gm_flatgrass", "preview"
        editor.EditorMapSession = true
        state.files["zombiesim/prefab_editor_session.json"] =
            env.util.TableToJSON({ schemaVersion = 1, profile = "preview", owner = state.target.identity })
        local document = { schemaVersion = 1, id = "guard_fixture", name = "Guard", description = "", tags = {},
            props = {}, guards = { {
                guardId = "guard_1", name = "Guard", model = "models/player/group01/male_03.mdl",
                position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = ""
            } } }
        state.guardError = "Guard content unavailable."
        local response = state:Request("save", env.util.TableToJSON(document))
        check(not response.values[2] and state.files["zombiesim/prefabs/guard_fixture.json"] == nil,
            "failed guard content validation cannot write a prefab")
        state.guardError = nil
        response = state:Request("save", env.util.TableToJSON(document))
        check(response.values[2] and state.files["zombiesim/prefabs/guard_fixture.json"] ~= nil,
            "validated guard records can be saved")
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
        editor.OpenedId, editor.OpenedIds.test_prefab = nil, nil
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

    suite:Add("multiple open prefabs retain independent server authorization", function(check)
        local env, state, load, editor = fixture()
        check(editor:Begin(state.target), "editor session begins")
        state.map = "gm_flatgrass"
        editor = load()
        check(editor:HandleSpawn(state.target), "editor owner enters workspace")
        local first = { schemaVersion = 1, id = "first", name = "First", description = "", tags = {}, props = {} }
        local second = { schemaVersion = 1, id = "second", name = "Second", description = "", tags = {}, props = {} }
        local firstSave = state:Request("save", env.util.TableToJSON(first), "", nil, "request_1")
        check(firstSave.values[2] and firstSave.values[5] == "request_1", "save response echoes its request ID")
        check(state:Request("new").values[2] and state:Request("save", env.util.TableToJSON(second)).values[2],
            "a second document can be saved without releasing the first")
        check(editor.OpenedIds.first and editor.OpenedIds.second
            and not state:Request("explorer_delete", "first").values[2]
            and not state:Request("explorer_rename", "second", "Changed").values[2],
            "every open prefab remains protected in the explorer")
        first.name = "First updated"
        check(state:Request("save", env.util.TableToJSON(first), "first").values[2],
            "an open background document remains authorized to save")
        check(state:Request("close", "first").values[2] and not editor.OpenedIds.first and editor.OpenedIds.second,
            "closing one tab releases only that prefab")
        check(not state:Request("save", env.util.TableToJSON(first), "first").values[2]
            and state:Request("explorer_rename", "first", "Renamed").values[2],
            "closed documents cannot be saved as open and can be managed again")
        check(not state:Request("activate", "missing").values[2]
            and not state:Request("close", "missing").values[2], "unopened IDs cannot be activated or closed")
        local invalid = state:Request("list", "", "", nil, "../bad")
        check(not invalid.values[2] and invalid.values[5] == "", "invalid correlation tokens are rejected")
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
