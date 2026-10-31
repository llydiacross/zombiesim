return function(EditorMap)
concommand.Add("zombiesim_dev_test_prefab_map_client", function()
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("map-switch drafts round-trip through real JSON and client DATA", function(check)
        local path = "zombiesim/prefab_editor_map_transfer_fixture.json"
        if file.Exists(path, "DATA") then check(false, "The fixture file already exists; preserve it.") return end
        local view = { cameraYaw = 45.125, cameraPitch = 55, cameraDistance = 1000, panX = 0, panY = 0,
            positionSnap = 16, rotationSnap = 15, snapEnabled = true, gridSpacing = 64,
            showGrid = true, showCompass = true, previewDark = false, referenceOffset = 0, prefabOffset = 50 }
        local snapshot = {
            schemaVersion = 1, token = "switch_fixture", map = "gm_construct", active = 1,
            tabs = { {
                number = 1, dirty = true, revision = 2, mode = "move", view = view,
                document = { schemaVersion = 1, id = "unfinished id", name = "", description = "",
                    tags = { "duplicate", "duplicate" }, props = {}, lights = {}, particles = {}, guards = {} }
            } }
        }
        local valid, problem = EditorMap.ValidateSnapshot(snapshot)
        check(valid, "The incomplete draft is accepted: " .. tostring(problem))
        local encoded = util.TableToJSON(snapshot, false)
        local decoded = type(encoded) == "string" and util.JSONToTable(encoded) or nil
        check(type(decoded) == "table" and EditorMap.SnapshotsEqual(snapshot, decoded),
            "Real engine JSON preserves the complete draft exactly")
        if type(encoded) ~= "string" then return end
        file.CreateDir("zombiesim")
        if not file.Write(path, encoded) then check(false, "Could not write the isolated client fixture.") return end
        local actual = file.Read(path, "DATA")
        check(actual == encoded, "The client DATA file reads back exactly")
        if actual ~= encoded then
            check(false, "The changed fixture file was retained for inspection.")
            return
        end
        check(file.Delete(path) and not file.Exists(path, "DATA"), "The verified client fixture was removed")
    end)
    suite:Add("recommended map thumbnails resolve from mounted game assets", function(check)
        for _, name in ipairs({ "gm_construct", "gm_flatgrass" }) do
            local path = "maps/thumb/" .. name .. ".png"
            check(file.Exists(path, "GAME"), name .. " thumbnail exists in mounted game assets")
            local material = Material(path, "smooth")
            local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
            check(texture and texture:Width() > 0 and texture:Height() > 0,
                name .. " thumbnail resolves as a material")
        end
    end)
    local summary = suite:Run()
    file.CreateDir("zombiesim")
    local encoded = util.TableToJSON(summary, true)
    if type(encoded) ~= "string" or not file.Write("zombiesim/prefab-editor-map-client-tests.json", encoded) then
        ErrorNoHalt("[ZombieSim] Could not write prefab editor map client test results.\n")
    end
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do print("[ZombieSim]     " .. failure) end
    end
    print(string.format("[ZombieSim] Prefab editor map client tests: %d passed, %d failed.", summary.passed, summary.failed))
end)
end
