return function(contract, createCatalog)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { files = {}, decoded = {}, names = {} }
        local files = {
            Find = function(pattern, realm)
                assert(pattern == "data_static/prefabs/*.json" and realm == "GAME")
                return state.names
            end,
            Read = function(path, realm)
                assert(realm == "GAME")
                return state.files[path]
            end
        }
        local json = {
            JSONToTable = function(text) return state.decoded[text] end,
            CRC = function(text)
                local hash = 0
                for index = 1, #text do hash = (hash * 33 + string.byte(text, index)) % 4294967296 end
                return tostring(hash)
            end
        }
        local catalog = createCatalog(files, json, contract, function(model)
            return model == "models/props_c17/oildrum001.mdl"
        end, function(document)
            if document.id == state.rejectId then return false, "invalid loot configuration" end
            return true
        end)
        function state:Add(id, name, tags)
            local path = "data_static/prefabs/" .. id .. ".json"
            self.names[#self.names + 1] = id .. ".json"
            self.files[path] = id
            self.decoded[id] = { schemaVersion = 1, id = id, name = name, description = "",
                tags = tags, props = {} }
        end
        return state, catalog
    end

    suite:Add("exported catalog validates GAME data and names", function(check)
        local state, catalog = fixture()
        state:Add("b", "B", { "road" })
        state:Add("a", "A", { "road", "motorway" })
        local documents = catalog.Load()
        check(documents and #documents == 2 and documents[1].id == "a",
            "exported prefabs load in stable ID order")
        state.decoded.a.id = "different"
        local loaded, problem = catalog.Load()
        check(not loaded and type(problem) == "string", "mismatched filenames fail explicitly")
        state.decoded.a.id = "a"
        state.rejectId = "a"
        loaded, problem = catalog.Load()
        check(not loaded and type(problem) == "string", "invalid prefab loot configuration rejects the catalog")
        state.rejectId = nil
        state.files["data_static/prefabs/a.json"] = "broken"
        loaded, problem = catalog.Load()
        check(not loaded and type(problem) == "string", "invalid JSON does not silently disappear")
    end)

    suite:Add("selection requires all tags and a stable cell and anchor", function(check)
        local state, catalog = fixture()
        state:Add("a", "A", { "Road", "Motorway" })
        state:Add("b", "B", { "road", "motorway" })
        state:Add("c", "C", { "road" })
        local documents = catalog.Load()
        local first = catalog.Select(documents, { "ROAD", "motorway" }, "preview", 1337, 42, 17)
        local again = catalog.Select(documents, { "road", "MOTORWAY" }, "preview", 1337, 42, 17)
        check(first and again and first.id == again.id and first.id ~= "c",
            "matching is case-insensitive, conjunctive and deterministic")
        local ids = {}
        for anchor = 1, 32 do
            local selected = catalog.Select(documents, { "road", "motorway" }, "preview", 1337, 42, anchor)
            ids[selected.id] = true
        end
        check(ids.a and ids.b, "different anchors can select different matching prefabs")
        local reversed = { documents[3], documents[2], documents[1] }
        local reordered = catalog.Select(reversed, { "road", "motorway" }, "preview", 1337, 42, 17)
        check(reordered and first and reordered.id == first.id,
            "catalog enumeration order cannot change a choice")
        local cellChoices = {}
        for cell = 40, 55 do
            local chosen = catalog.Select(documents, { "road", "motorway" }, "preview", 1337, cell, 17)
            local repeated = catalog.Select(documents, { "road", "motorway" }, "preview", 1337, cell, 17)
            check(chosen and repeated and chosen.id == repeated.id,
                "reloading logical cell " .. cell .. " repeats the same selection")
            if chosen then cellChoices[chosen.id] = true end
        end
        check(cellChoices.a and cellChoices.b,
            "logical cells sharing one map anchor can select different prefabs")
        local selected, problem = catalog.Select(documents, { "missing" }, "preview", 1337, 42, 17)
        check(not selected and type(problem) == "string", "no match returns an error rather than a fallback")
        selected, problem = catalog.Select(documents, { "road" }, "preview", 1337, 42, -1)
        check(not selected and type(problem) == "string", "anchors require a stable map creation ID")
        selected, problem = catalog.Select(documents, {}, "preview", 1337, 42, 17)
        check(not selected and type(problem) == "string", "an empty tag request is rejected")
    end)
    suite:Add("roadblock and transition set-piece tags remain distinct", function(check)
        local state, catalog = fixture()
        state:Add("zz_dev_roadblock", "Temporary roadblock", { "roadBlockade" })
        state:Add("zz_dev_transition_gate", "Temporary gate", { "transitionGate", "road" })
        local documents = catalog.Load()
        local blockade = catalog.Select(documents, { "roadBlockade" }, "preview", 1337, 42, 100)
        local gate = catalog.Select(documents, { "transitionGate", "road" }, "preview", 1337, 42, 101)
        check(blockade and blockade.id == "zz_dev_roadblock", "roadblock context selects only its tagged fixture")
        check(gate and gate.id == "zz_dev_transition_gate", "road gate context selects only its tagged fixture")
        local motorway, problem = catalog.Select(documents, { "transitionGate", "motorway" }, "preview", 1337, 42, 102)
        check(not motorway and type(problem) == "string", "road gate fixture cannot silently substitute for a motorway gate")
    end)
    return suite
end
