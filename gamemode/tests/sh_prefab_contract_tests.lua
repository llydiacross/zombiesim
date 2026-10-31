return function(contract)
    local suite = ZM_TestHarness.NewSuite()
    local function validModel(model)
        return model == "models/props_c17/oildrum001.mdl" or model == "models/props_junk/wood_crate001a.mdl"
            or model == "models/player/group01/male_03.mdl"
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

    suite:Add("world placements preserve explicit profile, cell and tile transforms", function(check)
        local input = document()
        check(contract.Validate(input, validModel).worldPlacement == nil, "legacy prefabs remain tag-selected")
        input.worldPlacement = { enabled = true, profile = "preview", cellX = 14, cellY = -11,
            tileX = -2, tileY = 2, offset = { x = 1.25, y = -2.5, z = 3.75 },
            angles = { p = 10, y = 90, r = -5 } }
        local output = contract.Validate(input, validModel)
        check(output and output.worldPlacement.cellY == -11 and output.worldPlacement.offset.x == 1.25
            and output.worldPlacement.angles.y == 90, "placement survives validation precisely")
        output.worldPlacement.offset.x = 100
        check(input.worldPlacement.offset.x == 1.25, "placement offsets do not alias the draft")
        input.worldPlacement.enabled = false
        check(contract.Validate(input, validModel).worldPlacement.enabled == false, "disabled placements retain their settings")
        for key, invalid in pairs({ enabled = "yes", profile = "other", cellX = 0.5,
            cellY = math.huge, tileX = 3, tileY = -3 }) do
            local original = input.worldPlacement[key]
            input.worldPlacement[key] = invalid
            check(not contract.Validate(input, validModel), "invalid " .. key .. " is rejected")
            input.worldPlacement[key] = original
        end
        input.worldPlacement.offset.z = 32769
        check(not contract.Validate(input, validModel), "out-of-range offsets are rejected")
        input.worldPlacement.offset.z = 3
        input.worldPlacement.angles.y = 0 / 0
        check(not contract.Validate(input, validModel), "non-finite rotation is rejected")
        input.worldPlacement.angles.y = 0
        input.worldPlacement.unexpected = true
        check(not contract.Validate(input, validModel), "unknown placement fields are rejected")
    end)

    suite:Add("tag suggestions include custom library tags without duplicate casing", function(check)
        local tags = contract.GetTagSuggestions({ { tags = { "BURNINGCAR", "customTag" } } })
        local count, custom, barrel = 0, false, false
        for _, tag in ipairs(tags) do
            if string.lower(tag) == "burningcar" then count = count + 1 end
            if tag == "customTag" then custom = true end
            if tag == "burningBarrel" then barrel = true end
        end
        check(count == 1 and custom and barrel, "suggestions retain defaults and custom tags exactly once")
    end)

    suite:Add("empty prefabs and out-of-tile prop origins remain editable", function(check)
        local input = document()
        input.props = {}
        check(contract.Validate(input, validModel) ~= nil, "an empty draft can be saved")
        input = document()
        input.props[1].position.x = 400
        check(contract.Validate(input, validModel) ~= nil, "the 640-unit guide is not an overhang veto")
    end)

    suite:Add("guard records retain identity and local authoring data", function(check)
        local input = document()
        input.guards = { {
            guardId = "guard_1", name = "Guard", model = "models/player/group01/male_03.mdl",
            position = { x = 10, y = 20, z = 30 }, angles = { p = 0, y = 90, r = 0 },
            idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = ""
        } }
        local output = contract.Validate(input, validModel)
        check(output and #output.guards == 1 and output.guards[1].guardId == "guard_1"
            and output.guards[1].position.z == 30 and output.guards[1].angles.y == 90,
            "guard identity and local transform survive validation")
        check(output and output.guards[1].damage == nil and output.guards[1].fireInterval == nil
            and output.guards[1].spread == nil, "legacy guards retain weapon defaults")
        input.guards[1].damage, input.guards[1].fireInterval, input.guards[1].spread = 24.5, 0.075, 0
        output = contract.Validate(input, validModel)
        check(output and output.guards[1].damage == 24.5 and output.guards[1].fireInterval == 0.075
            and output.guards[1].spread == 0, "valid combat overrides survive validation")
        if output then
            output.guards[1].position.z = 50
            check(input.guards[1].position.z == 30, "validated guard transforms do not alias their source")
        end
        for _, invalid in ipairs({ 0, -1, math.huge, 0 / 0, "5" }) do
            input.guards[1].damage = invalid
            check(not contract.Validate(input, validModel), "invalid damage is rejected")
        end
        input.guards[1].damage = 24.5
        for _, invalid in ipairs({ 0, -1, 0.049, math.huge, 0 / 0, "0.1" }) do
            input.guards[1].fireInterval = invalid
            check(not contract.Validate(input, validModel), "invalid firing intervals are rejected")
        end
        input.guards[1].fireInterval = contract.MinGuardFireInterval
        check(contract.Validate(input, validModel) ~= nil, "minimum firing interval is accepted")
        for _, invalid in ipairs({ -1, math.huge, 0 / 0, "0" }) do
            input.guards[1].spread = invalid
            check(not contract.Validate(input, validModel), "invalid spread is rejected")
        end
        input.guards[1].spread = 0
        input.guards[2] = input.guards[1]
        check(not contract.Validate(input, validModel), "duplicate guard IDs are rejected")
        input.guards[2] = nil
        input.guards[1].range = 0 / 0
        check(not contract.Validate(input, validModel), "non-finite guard range is rejected")
        input.guards[1].range, input.guards[1].weapon = 1000, "Invalid"
        check(not contract.Validate(input, validModel), "invalid guard weapon IDs are rejected")
        input.guards = nil
        output = contract.Validate(input, validModel)
        check(output and #output.guards == 0 and input.guards == nil, "legacy documents load without being mutated")
    end)

    suite:Add("guard weapon choices retain valid server data", function(check)
        local choices = { { id = "pistol", label = "9mm Handgun", model = "models/weapons/w_pistol.mdl",
            damage = 12, delay = 0.18, spread = 0.02, range = 3000 } }
        local result = contract.ValidateGuardWeaponChoices(choices)
        check(result and result.pistol == choices[1], "the server choice is indexed by stable weapon ID")
        for _, invalid in ipairs({ math.huge, 0 / 0, -1, "1" }) do
            choices[1].spread = invalid
            check(not contract.ValidateGuardWeaponChoices(choices), "invalid spread is rejected")
        end
        choices[1].spread = 0
        choices[1].delay = 0.01
        check(not contract.ValidateGuardWeaponChoices(choices), "unsupported firing intervals are rejected")
        choices[1].delay = 0.18
        choices[2] = choices[1]
        check(not contract.ValidateGuardWeaponChoices(choices), "duplicate weapon IDs are rejected")
        choices[2] = nil
        choices[1].id = "smg"
        check(not contract.ValidateGuardWeaponChoices(choices), "missing default weapon is explicit")
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
    suite:Add("spotlights retain authored values and reject malformed data", function(check)
        local input = document()
        input.lights = {
            { lightId = "light_1", position = { x = 16, y = -20, z = 192 },
                angles = { p = 40, y = 45, r = 5 }, color = { r = 255, g = 235, b = 200 },
                brightness = 6, fov = 60, range = 512 }
        }
        local output, problem = contract.Validate(input, validModel)
        check(output and #output.lights == 1 and output.lights[1].position.z == 192
            and output.lights[1].angles.r == 5 and output.lights[1].color.g == 235
            and output.lights[1].brightness == 6 and output.lights[1].fov == 60
            and output.lights[1].range == 512, "spotlight settings are preserved: " .. tostring(problem))
        if output then
            output.lights[1].position.x = 999
            check(input.lights[1].position.x == 16, "validated light does not alias source")
        end
        local legacy = document()
        local legacyResult = contract.Validate(legacy, validModel)
        check(legacyResult and #legacyResult.lights == 0 and legacy.lights == nil,
            "legacy documents get no lights without rewriting their source")
        input.lights[2] = input.lights[1]
        check(not contract.Validate(input, validModel), "duplicate light IDs are rejected")
        input.lights[2] = nil
        for _, fov in ipairs({ 0, 0.0001, 180, math.huge, "60" }) do
            input.lights[1].fov = fov
            check(not contract.Validate(input, validModel), "invalid cone angle is rejected")
        end
        input.lights[1].fov = 60
        for _, range in ipairs({ 8, 8.0001, 0, 1000001, math.huge, "512" }) do
            input.lights[1].range = range
            check(not contract.Validate(input, validModel), "invalid range is rejected")
        end
        input.lights[1].range = 512
        for _, value in ipairs({ -1, 256, 1.5, math.huge }) do
            input.lights[1].color.r = value
            check(not contract.Validate(input, validModel), "invalid color is rejected")
        end
        input.lights[1].color.r = 255
        input.lights[1].brightness = -1
        check(not contract.Validate(input, validModel), "negative brightness is rejected")
        input.lights[1].brightness = 1000001
        check(not contract.Validate(input, validModel), "brightness beyond the editor's range is rejected")
        input.lights[1].brightness = 6
        input.lights[1].position.x = 0 / 0
        check(not contract.Validate(input, validModel), "non-finite light transform is rejected")
        input.lights[1].position.x = 0
        input.lights[3] = input.lights[1]
        check(not contract.Validate(input, validModel), "sparse light lists are rejected")
    end)
    suite:Add("particles preserve modes, transforms and per-effect overlap", function(check)
        local input = document()
        input.particles = {
            { particleId = "steam_1", effect = "steam", position = { x = 1, y = 2, z = 3 },
                angles = { p = 10, y = 90, r = -5 }, mode = "continuous" },
            { particleId = "steam_2", effect = "steam", position = { x = 4, y = 5, z = 6 },
                angles = { p = 0, y = 0, r = 0 }, mode = "triggered", overlap = false }
        }
        local output, problem = contract.Validate(input, validModel)
        check(output and #output.particles == 2 and output.particles[1].overlap == true
            and output.particles[2].overlap == false and output.particles[2].mode == "triggered"
            and output.particles[1].angles.y == 90, "particle settings survive validation: " .. tostring(problem))
        if output then
            output.particles[1].position.x = 999
            check(input.particles[1].position.x == 1, "validated particle does not alias source")
        end
        local legacy = document()
        local legacyResult = contract.Validate(legacy, validModel)
        check(legacyResult and #legacyResult.particles == 0 and legacy.particles == nil,
            "legacy documents contain no particles and are not rewritten on load")
        input.particles[2].particleId = "steam_1"
        check(not contract.Validate(input, validModel), "duplicate particle IDs are rejected")
        input.particles[2].particleId = "steam_2"
        input.particles[2].mode = "unknown"
        check(not contract.Validate(input, validModel), "unsupported playback modes are rejected")
        input.particles[2].mode, input.particles[2].overlap = "triggered", "true"
        check(not contract.Validate(input, validModel), "non-boolean overlap is rejected")
        input.particles[2].overlap, input.particles[2].position.z = true, 0 / 0
        check(not contract.Validate(input, validModel), "non-finite transforms are rejected")
        input.particles[2].position.z, input.particles[2].effect = 0, "../bad"
        check(not contract.Validate(input, validModel), "unsafe effect IDs are rejected")
        input.particles[2].effect = "steam"
        input.particles[4] = input.particles[2]
        check(not contract.Validate(input, validModel), "sparse particle lists are rejected")
    end)
    return suite
end
