return function(contract, createStorage, createEngine, contractTests, storageTests, gizmo, gizmoTests, createCatalog, catalogTests)
    ZM_TestHarness.Register({
        command = "zn_test_prefabs",
        label = "Prefab contracts",
        file = "prefab-contract-tests.json",
        report = "prefab_contract_tests",
        help = "Tests prefab document, storage, catalog and gizmo contracts.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            for _, group in ipairs({ contractTests(contract), storageTests(createEngine, contract, createStorage),
                gizmoTests(gizmo), catalogTests(contract, createCatalog, util.CRC) }) do
                for _, case in ipairs(group.cases) do suite:Add(case.name, case.body) end
            end
            suite:Add("storage JSON preserves editor precision and cardinal local rotations", function(check)
                local props = {}
                for _, yaw in ipairs({ 0, 90, 180, 270 }) do
                    props[#props + 1] = {
                        model = "models/props_c17/oildrum001.mdl",
                        position = { x = 123.456, y = -27.135, z = 0.125 },
                        angles = { p = -12.375, y = yaw, r = 3.625 }, skin = 0, scale = 1.375
                    }
                end
                local document = { schemaVersion = 1, id = "precision_fixture", name = "Precision",
                    description = "", tags = {}, props = props }
                local engine = createEngine()
                local storage = createStorage(engine.files, util, contract, function(model)
                    return model == "models/props_c17/oildrum001.mdl"
                end)
                local saved, problem = storage.Save(document)
                check(saved, "the precision fixture saves: " .. tostring(problem or ""))
                local decoded = saved and storage.Load(document.id) or nil
                check(type(decoded) == "table" and type(decoded.props) == "table" and #decoded.props == 4,
                    "the JSON round trip retains all four props")
                if type(decoded) ~= "table" or type(decoded.props) ~= "table" or #decoded.props ~= 4 then return end
                for index, expected in ipairs(props) do
                    local actual = decoded.props[index]
                    check(type(actual) == "table" and type(actual.position) == "table" and type(actual.angles) == "table",
                        "prop " .. index .. " retains its transform")
                    if type(actual) == "table" and type(actual.position) == "table" and type(actual.angles) == "table" then
                        for _, field in ipairs({ "x", "y", "z" }) do
                            check(type(actual.position[field]) == "number"
                                and math.abs(actual.position[field] - expected.position[field]) < 0.0000005,
                                "prop " .. index .. " position " .. field .. " retains three-decimal precision")
                        end
                        for _, field in ipairs({ "p", "y", "r" }) do
                            check(type(actual.angles[field]) == "number"
                                and math.abs(actual.angles[field] - expected.angles[field]) < 0.0000005,
                                "prop " .. index .. " angle " .. field .. " is preserved")
                        end
                        check(type(actual.scale) == "number" and math.abs(actual.scale - expected.scale) < 0.0000005,
                            "prop " .. index .. " scale is preserved")
                    end
                end
            end)
            return suite:Run()
        end
    })
end
