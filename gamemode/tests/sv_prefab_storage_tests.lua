return function(createEngine, contract, createStorage)
    local suite = ZM_TestHarness.NewSuite()
    local function document(name)
        return {
            schemaVersion = 1, id = "test_prefab", name = name or "Test prefab",
            description = "", tags = { "roadDetail" },
            props = {
                { model = "models/props_c17/oildrum001.mdl", position = { x = 0, y = 0, z = 0 },
                    angles = { p = 0, y = 0, r = 0 }, skin = 0 }
            }
        }
    end
    local function setup()
        local engine = createEngine()
        local storage = createStorage(engine.files, engine.json, contract, function(model)
            return model == "models/props_c17/oildrum001.mdl"
        end)
        return engine, storage
    end

    suite:Add("new prefab saves, lists and reloads", function(check)
        local engine, storage = setup()
        local ok, problem = storage.Save(document())
        check(ok and problem == nil, "new document saves")
        local loaded = storage.Load("test_prefab")
        check(loaded and loaded.name == "Test prefab" and #loaded.props == 1, "saved document reloads")
        local listed = storage.List()
        check(listed and #listed == 1 and listed[1].id == "test_prefab", "explorer lists the saved prefab")
        check(engine.state.files["zombiesim/prefabs/test_prefab.json"] ~= nil, "document is stored in DATA")
    end)

    suite:Add("existing unscaled prefabs load without rewriting the original", function(check)
        local engine, storage = setup()
        local path = "zombiesim/prefabs/test_prefab.json"
        local original = engine.json.TableToJSON(document())
        engine.files.CreateDir("zombiesim/prefabs")
        engine.state.files[path] = original
        local loaded = storage.Load("test_prefab")
        check(loaded and loaded.props[1].scale == 1, "an older prop keeps its original size")
        check(engine.state.files[path] == original, "opening a legacy document does not rewrite it")
        loaded.props[1].scale = 1.5
        check(storage.Save(loaded, "test_prefab"), "the opened document can be explicitly resaved with scale")
        check(storage.Load("test_prefab").props[1].scale == 1.5, "the new scale survives reload")
    end)

    suite:Add("prop mobility survives save and reload", function(check)
        local _, storage = setup()
        local input = document()
        input.props[1].movable = true
        check(storage.Save(input), "movable prefab saves")
        local loaded = storage.Load("test_prefab")
        check(loaded and loaded.props[1].movable == true, "movable setting survives reload")
        loaded.props[1].movable = false
        check(storage.Save(loaded, "test_prefab"), "stationary setting can be saved")
        check(storage.Load("test_prefab").props[1].movable == false, "stationary setting survives reload")
    end)

    suite:Add("stable prop identities survive editing and removal", function(check)
        local _, storage = setup()
        local input = document()
        input.props[2] = { model = "models/props_c17/oildrum001.mdl", position = { x = 20, y = 0, z = 0 },
            angles = { p = 0, y = 0, r = 0 }, skin = 0 }
        check(storage.Save(input), "legacy two-prop document saves")
        local loaded = storage.Load("test_prefab")
        check(loaded and loaded.props[1].propId == "legacy_1" and loaded.props[2].propId == "legacy_2",
            "legacy prop IDs are retained by validation and storage")
        table.remove(loaded.props, 1)
        loaded.props[1].lootMode = "guaranteed"
        check(storage.Save(loaded, "test_prefab"), "edited document saves")
        local again = storage.Load("test_prefab")
        check(again and again.props[1].propId == "legacy_2" and again.props[1].lootMode == "guaranteed",
            "removing an earlier prop does not remap the surviving ID")
    end)

    suite:Add("saving requires the existing prefab to be opened", function(check)
        local _, storage = setup()
        check(storage.Save(document()), "initial save succeeds")
        local ok, problem = storage.Save(document("Changed"))
        check(not ok and type(problem) == "string", "new draft cannot overwrite an existing ID")
        check(storage.Load("test_prefab").name == "Test prefab", "failed overwrite preserves the original")
        check(storage.Save(document("Changed"), "test_prefab"), "opened document can be updated")
        check(storage.Load("test_prefab").name == "Changed", "updated document reloads")
        ok, problem = storage.Save(document(), "different_prefab")
        check(not ok and type(problem) == "string", "an opened ID cannot silently change")
    end)

    suite:Add("failed publication restores the old file and retains the draft", function(check)
        local engine, storage = setup()
        check(storage.Save(document()), "initial save succeeds")
        local pending = "zombiesim/prefab_editor_recovery/test_prefab.pending.json"
        engine.state.fail.renameFrom = pending
        local ok, problem = storage.Save(document("Changed"), "test_prefab")
        check(not ok and type(problem) == "string", "failed publication reports an error")
        check(storage.Load("test_prefab").name == "Test prefab", "previous file is restored")
        check(engine.state.files[pending] ~= nil, "pending draft is retained for recovery")
        engine.state.fail.renameFrom = nil
        ok, problem = storage.Save(document("Again"), "test_prefab")
        check(not ok and string.find(problem, "recovery", 1, true) ~= nil, "later saves do not overwrite recovery files")
    end)

    suite:Add("invalid input and corrupt files do not produce success-shaped results", function(check)
        local engine, storage = setup()
        local input = document()
        input.id = "../escape"
        local ok, problem = storage.Save(input)
        check(not ok and type(problem) == "string", "unsafe ID fails")
        check(next(engine.state.files) == nil, "invalid document writes no files")
        engine.files.CreateDir("zombiesim/prefabs")
        engine.state.files["zombiesim/prefabs/test_prefab.json"] = "broken-json"
        local loaded, loadError = storage.Load("test_prefab")
        check(loaded == nil and type(loadError) == "string", "corrupt JSON is reported")
        local listed, listError = storage.List()
        check(listed == nil and type(listError) == "string", "explorer does not silently hide corrupt data")
    end)

    suite:Add("deletion and failed writes are reported", function(check)
        local engine, storage = setup()
        engine.state.fail.write = true
        local ok, problem = storage.Save(document())
        check(not ok and type(problem) == "string", "write failure is reported")
        engine.state.fail.write = false
        check(storage.Save(document()), "subsequent save succeeds")
        engine.state.fail.delete = true
        ok, problem = storage.Delete("test_prefab")
        check(not ok and type(problem) == "string", "delete failure is reported")
        check(storage.Load("test_prefab") ~= nil, "failed deletion retains the prefab")
        engine.state.fail.delete = false
        check(storage.Delete("test_prefab"), "explicit deletion succeeds")
        ok, problem = storage.Delete("test_prefab")
        check(not ok and type(problem) == "string", "deleting an absent prefab reports an error")
    end)
    return suite
end
