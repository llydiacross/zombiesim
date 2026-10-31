return function(contract, createMap)
    local suite = ZM_TestHarness.NewSuite()
    local map = createMap(contract)

    local function view()
        return { cameraYaw = 45, cameraPitch = 55, cameraDistance = 1000, panX = 0, panY = 0,
            positionSnap = 16, rotationSnap = 15, snapEnabled = true, gridSpacing = 64,
            showGrid = true, showCompass = true, previewDark = false, referenceOffset = 0, prefabOffset = 0 }
    end
    local function snapshot()
        return {
            schemaVersion = 1, token = "switch_123", map = "gm_construct", active = 1,
            tabs = { {
                number = 1, dirty = true, revision = 2, mode = "move", view = view(),
                document = { schemaVersion = 1, id = "unfinished id", name = "", description = "",
                    tags = { "duplicate", "duplicate" }, props = {}, lights = {}, particles = {}, guards = { {
                        guardId = "guard_1", name = "", model = "models/player/group01/male_03.mdl",
                        position = { x = 1, y = 2, z = 3 }, angles = { p = 0, y = 90, r = 0 },
                        idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = ""
                    } } },
                selected = "guard:guard_1"
            } }
        }
    end

    suite:Add("map switches reject unsafe and reserved map names", function(check)
        check(map.IsValidName("gm_construct") and map.IsValidName("custom-map_1"), "ordinary mounted map names are accepted")
        for _, name in ipairs({ "", "../escape", "bad map", "bad;quit", "maps/test", "line\nbreak" }) do
            check(not map.IsValidName(name), "unsafe map name is rejected")
        end
        for _, name in ipairs({ "zn_preview_start", "zn_city_start", "zn_dev_prefab_anchor",
            "zz_preview_abcdef", "zz_city_abcdef" }) do
            check(map.IsReservedName(name), "ZombieSim launcher, fixture and generated map names are reserved")
        end
        local request = { map = "gm_construct", token = "switch_123", openIds = { "one", "two" } }
        check(map.ValidateRequest(request), "valid switch requests retain all open IDs")
        request.openIds[2] = "one"
        check(not map.ValidateRequest(request), "duplicate open IDs are rejected")
        request.openIds = {}
        request.map = "gm_construct;quit"
        check(not map.ValidateRequest(request), "command injection is rejected")
        request.map, request.cellId = "zz_preview_fixture", 302
        check(map.ValidateRequest(request), "a preview cell can use its authoritative generated map")
        request.cellId = -1
        check(not map.ValidateRequest(request), "invalid preview cell IDs are rejected")
        for _, value in ipairs({ -2, -1, 0, 1, 2 }) do check(map.IsValidTile(value), "core tile is accepted") end
        for _, value in ipairs({ -3, 3, 0.5, 0 / 0, math.huge }) do
            check(not map.IsValidTile(value), "invalid core tile is rejected")
        end
    end)

    suite:Add("map snapshots preserve incomplete drafts and independent tabs", function(check)
        local input = snapshot()
        input.tabs[2] = {
            number = 2, openedId = "saved", dirty = false, revision = 4, mode = "rotate", view = view(),
            document = { schemaVersion = 1, id = "saved", name = "Saved", description = "", tags = {},
                props = {}, lights = {}, particles = {}, guards = {} }
        }
        input.tabs[2].view.prefabOffset = 50
        input.tabs[2].view.prefabOffsetX, input.tabs[2].view.prefabOffsetY = 12.5, -20
        input.tabs[2].document.worldPlacement = { enabled = true, profile = "preview", cellX = 14, cellY = 0,
            tileX = -2, tileY = 2, offset = { x = 12.5, y = -20, z = 50 }, angles = { p = 0, y = 90, r = 0 } }
        check(map.ValidateSnapshot(input), "dirty incomplete metadata and a second saved tab are accepted")
        check(input.tabs[1].document.id == "unfinished id" and input.tabs[1].document.name == ""
            and input.tabs[1].document.guards[1].name == "" and #input.tabs[1].document.tags == 2
            and input.tabs[2].view.prefabOffset == 50, "validation does not normalize or mutate a draft")
        local copy = snapshot()
        check(map.SnapshotsEqual(snapshot(), copy), "identical snapshots compare without changing their values")
        copy.tabs[1].view.cameraYaw = 45.000001
        check(not map.SnapshotsEqual(snapshot(), copy), "a changed numeric value cannot pass a round-trip check")
        input.tabs[2].openedId = "saved"
        input.tabs[1].openedId = "saved"
        check(not map.ValidateSnapshot(input), "duplicate saved IDs cannot bypass tab ownership")
        input.tabs[1].openedId = nil
        input.tabs[1].selected = "guard:missing"
        check(not map.ValidateSnapshot(input), "a selection must resolve to an object in its tab")
        input.tabs[1].selected = "guard:guard_1"
        input.tabs[2].view.prefabOffset = 0 / 0
        check(not map.ValidateSnapshot(input), "non-finite view values cannot be restored")
        input.tabs[2].view.prefabOffset = 0
        input.tabs[2].view.prefabOffsetX = math.huge
        check(not map.ValidateSnapshot(input), "non-finite horizontal preview offsets cannot be restored")
        input.tabs[2].view.prefabOffsetX = 12.5
        input.tabs[2].document.worldPlacement.tileX = 3
        check(not map.ValidateSnapshot(input), "invalid world-placement metadata cannot survive a map switch")
        input.tabs[2].document.worldPlacement.tileX = -2
        input.tabs[1].document.guards[3] = input.tabs[1].document.guards[1]
        check(not map.ValidateSnapshot(input), "sparse guard lists cannot hide draft objects")
        input.tabs[1].document.guards[3] = nil
        input.map, input.cellId = "zz_preview_fixture", 302
        check(map.ValidateSnapshot(input), "a saved draft can target an authorized cell map")
        input.cellId = nil
        check(not map.ValidateSnapshot(input), "generated maps require an explicit cell identity")
    end)
    return suite
end
