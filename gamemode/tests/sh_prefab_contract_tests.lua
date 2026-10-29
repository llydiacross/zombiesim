return function(contract)
    local suite = ZM_TestHarness.NewSuite()
    local function validModel(model)
        return model == "models/props_c17/oildrum001.mdl" or model == "models/props_junk/wood_crate001a.mdl"
    end
    local function document()
        return {
            schemaVersion = 1, id = "test_prefab", name = "Test prefab", description = "Two props",
            tags = { "roadDetail", "transitionGate Motorway" },
            props = {
                { model = "models/props_c17/oildrum001.mdl", position = { x = 0, y = 0, z = 0 },
                    angles = { p = 0, y = 0, r = 0 }, skin = 0 },
                { model = "models/props_junk/wood_crate001a.mdl", position = { x = 64, y = -32, z = 4 },
                    angles = { p = 10, y = 90, r = -5 }, skin = 1 }
            }
        }
    end

    suite:Add("two-prop prefab preserves local transforms and metadata", function(check)
        local input = document()
        local output, problem = contract.Validate(input, validModel)
        check(output ~= nil and problem == nil, "valid prefab is accepted")
        check(output and output.id == input.id and output.name == input.name and output.description == input.description,
            "identity and description are preserved")
        check(output and #output.tags == 2 and output.tags[2] == "transitionGate Motorway",
            "both generic and environment tags are preserved")
        check(output and #output.props == 2 and output.props[2].position.x == 64
            and output.props[2].position.y == -32 and output.props[2].angles.y == 90
            and output.props[2].angles.r == -5 and output.props[2].skin == 1,
            "prop positions, rotations and skin are preserved")
        check(output and output.props[1].scale == 1 and input.props[1].scale == nil,
            "existing unscaled prefabs load at their original size without mutating their source")
        if output then
            output.props[1].position.x = 100
            check(input.props[1].position.x == 0, "validated data does not alias the input")
        end
    end)

    suite:Add("empty prefabs and out-of-tile prop origins remain editable", function(check)
        local input = document()
        input.props = {}
        check(contract.Validate(input, validModel) ~= nil, "an empty draft can be saved")
        input = document()
        input.props[1].position.x = 400
        check(contract.Validate(input, validModel) ~= nil, "the 640-unit guide is not an overhang veto")
    end)

    suite:Add("unsafe IDs and unavailable models fail explicitly", function(check)
        for _, id in ipairs({ "", "../escape", "Uppercase", "two words", "a/b" }) do
            local input = document()
            input.id = id
            local result, problem = contract.Validate(input, validModel)
            check(result == nil and type(problem) == "string", "invalid ID is rejected: " .. id)
        end
        for _, model in ipairs({ "materials/no.mdl", "models/../bad.mdl", "models\\bad.mdl",
            "models/missing.mdl" }) do
            local input = document()
            input.props[1].model = model
            local result, problem = contract.Validate(input, validModel)
            check(result == nil and type(problem) == "string", "invalid or unavailable model is rejected: " .. model)
        end
        local result, problem = contract.Validate(document(), nil)
        check(result == nil and type(problem) == "string", "missing model validator is an error")
    end)

    suite:Add("invalid transforms, skins and collection shapes fail explicitly", function(check)
        local invalid = { 0 / 0, math.huge, -math.huge, "1" }
        for _, value in ipairs(invalid) do
            local input = document()
            input.props[1].position.x = value
            local result, problem = contract.Validate(input, validModel)
            check(result == nil and type(problem) == "string", "non-finite or non-numeric position is rejected")
        end
        local input = document()
        input.props[1].angles.y = 0 / 0
        check(contract.Validate(input, validModel) == nil, "non-finite rotation is rejected")
        input = document()
        input.props[1].skin = -1
        check(contract.Validate(input, validModel) == nil, "negative skin is rejected")
        input = document()
        input.props[2] = nil
        input.props[3] = document().props[2]
        check(contract.Validate(input, validModel) == nil, "sparse prop lists are rejected")
        input = document()
        input.tags[2] = "ROADDETAIL"
        check(contract.Validate(input, validModel) == nil, "duplicate tags are rejected without changing their case")
        input = document()
        input.props[1].unexpected = true
        check(contract.Validate(input, validModel) == nil, "unsupported data is rejected instead of discarded")
    end)

    suite:Add("uniform scale is finite and within the supported range", function(check)
        local input = document()
        input.props[1].scale = 2.5
        local output = contract.Validate(input, validModel)
        check(output and output.props[1].scale == 2.5, "a valid uniform scale is preserved")
        for _, scale in ipairs({ 0.1, 10 }) do
            input.props[1].scale = scale
            check(contract.Validate(input, validModel) ~= nil, "range endpoints are accepted")
        end
        for _, scale in ipairs({ 0, -1, 0.099, 10.001, math.huge, -math.huge, 0 / 0, "2" }) do
            input.props[1].scale = scale
            local result, problem = contract.Validate(input, validModel)
            check(result == nil and type(problem) == "string", "invalid uniform scale is rejected")
        end
    end)
    suite:Add("per-prop mobility is boolean and defaults to stationary", function(check)
        local input = document()
        input.props[2].movable = true
        local output = contract.Validate(input, validModel)
        check(output and output.props[1].movable == false and output.props[2].movable == true,
            "legacy props default to stationary and explicit movable props remain movable")
        check(input.props[1].movable == nil, "validation does not rewrite a legacy document")
        input.props[1].movable = false
        output = contract.Validate(input, validModel)
        check(output and output.props[1].movable == false, "explicit stationary is preserved")
        for _, invalid in ipairs({ 0, 1, "true", "false", {} }) do
            input.props[1].movable = invalid
            local result, problem = contract.Validate(input, validModel)
            check(result == nil and type(problem) == "string", "non-boolean mobility is rejected")
        end
    end)
    suite:Add("loot modes and stable per-prop identities are validated", function(check)
        local input = document()
        input.props[2].propId = "p_new"
        input.props[2].lootMode = "normal"
        input.props[2].lootGroup = "lootGenericMedical"
        input.props[2].lootChance = 0.4
        local output = contract.Validate(input, validModel)
        check(output and output.props[1].propId == "legacy_1" and output.props[1].lootMode == "off",
            "legacy props gain a stable index-based identity and default to no loot")
        check(output and output.props[2].propId == "p_new" and output.props[2].lootMode == "normal"
            and output.props[2].lootGroup == "lootGenericMedical" and output.props[2].lootChance == 0.4,
            "explicit loot settings and prop identity survive validation")
        check(input.props[1].propId == nil and input.props[1].lootMode == nil,
            "loading legacy data does not mutate its original")
        for _, invalid in ipairs({ false, "unknown", 1 }) do
            input.props[2].lootMode = invalid
            check(contract.Validate(input, validModel) == nil, "invalid loot modes are rejected")
        end
        input.props[2].lootMode = "guaranteed"
        input.props[2].propId = "legacy_1"
        check(contract.Validate(input, validModel) == nil, "duplicate prop IDs are rejected")
        input.props[2].propId = "p_new"
        for _, invalid in ipairs({ -0.01, 1.01, math.huge, "0.5" }) do
            input.props[2].lootChance = invalid
            check(contract.Validate(input, validModel) == nil, "invalid activation chances are rejected")
        end
        input.props[2].lootChance = 0
        input.props[2].lootGroup = "../unsafe"
        check(contract.Validate(input, validModel) == nil, "invalid loot group IDs are rejected")
    end)
    return suite
end
