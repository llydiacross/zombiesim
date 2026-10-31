return function(contract, createCatalog)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = {
            available = true,
            decoded = { schemaVersion = 1, effects = { {
                id = "steam", label = "Steam", particleFile = "particles/train_steam.pcf",
                particleSystem = "steam_train", sound = "ambient/gas/steam_loop1.wav"
            } } }
        }
        local files = { Read = function(path, realm)
            assert(path == "data_static/prefab_particles.json" and realm == "GAME")
            return state.available and "fixture" or nil
        end }
        local json = { JSONToTable = function(text) assert(text == "fixture"); return state.decoded end }
        return state, function() return createCatalog(files, json, contract) end
    end
    suite:Add("particle catalog validates definitions and resolves exact IDs", function(check)
        local state, create = fixture()
        local catalog = create()
        local definitions, problem = catalog.Load()
        check(definitions and #definitions == 1 and definitions[1].id == "steam"
            and definitions[1].particleSystem == "steam_train", "validated catalog loads: " .. tostring(problem))
        check(catalog.Resolve("steam") and not catalog.Resolve("Steam"), "effect IDs are exact and case-sensitive")
        local ok, contentError = catalog.Validate({ particles = { { effect = "missing" } } })
        check(not ok and type(contentError) == "string", "unknown effects fail explicitly")
        state.decoded.effects[1].id = "changed"
        check(catalog.Resolve("steam") ~= nil, "validated definitions do not alias source")
    end)
    suite:Add("missing, unsafe, duplicate and sparse catalogs fail explicitly", function(check)
        local state, create = fixture()
        state.available = false
        local definitions, problem = create().Load()
        check(not definitions and type(problem) == "string", "missing catalog is reported")
        state.available = true
        state.decoded.effects[1].particleFile = "particles/../unsafe.pcf"
        check(not create().Load(), "unsafe mounted path is rejected")
        state.decoded.effects[1].particleFile = "particles/train_steam.pcf"
        state.decoded.effects[2] = state.decoded.effects[1]
        check(not create().Load(), "duplicate IDs are rejected")
        state.decoded.effects[2] = nil
        state.decoded.effects[3] = { id = "other", label = "Other", particleFile = "particles/other.pcf",
            particleSystem = "other", sound = "ambient/gas/steam2.wav" }
        check(not create().Load(), "sparse definitions are rejected")
    end)
    return suite
end
