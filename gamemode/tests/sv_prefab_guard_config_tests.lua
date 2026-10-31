return function(createConfig, contract)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("guard settings preserve supported citizen clothing and weapon range", function(check)
        local clothing = {
            Models = { ["models/player/group01/male_03.mdl"] = "male" },
            Finishes = { shirt_a = { garment = "shirt" }, pants_a = { garment = "pants" } }
        }
        local weapons = { Resolve = function(id)
            if id ~= "pistol" then return nil, "Unknown guard weapon." end
            return { id = "pistol", range = 3000, damage = 12, delay = 0.2, spread = 0.02 }
        end }
        local config = createConfig(clothing, weapons, function(model) return model == "models/player/group01/male_03.mdl" end,
            contract)
        local input = { name = "Guard", model = "models/player/group01/male_03.mdl", idle = "idle_all_01",
            weapon = "pistol", range = 1200, shirt = "shirt_a", pants = "pants_a" }
        local valid = config.Validate(input)
        check(valid and valid.weapon.id == "pistol" and valid.range == 1200 and valid.shirt == "shirt_a",
            "valid settings retain the chosen range, weapon and clothing")
        check(valid and valid.weapon.damage == 12 and valid.weapon.delay == 0.2 and valid.weapon.spread == 0.02,
            "omitted combat overrides preserve weapon values")
        input.damage, input.fireInterval, input.spread = 27.5, 0.075, 0
        valid = config.Validate(input)
        check(valid and valid.weapon.damage == 27.5 and valid.weapon.delay == 0.075 and valid.weapon.spread == 0,
            "combat overrides reach the actual resolved firearm")
        input.guardId, input.position, input.angles = "guard_1", { x = 0, y = 0, z = 0 }, { p = 0, y = 0, r = 0 }
        check(config.ValidateDocument({ guards = { input } }), "document validation reads the guard settings")
        local settings = config.PrepareDocumentGuard(input)
        check(settings and settings.guardId == nil and settings.position == nil and settings.damage == 27.5
            and settings.fireInterval == 0.075 and settings.spread == 0,
            "spawn settings retain overrides without document identity or transforms")
        input.damage = -1
        check(not config.ValidateDocument({ guards = { input } }), "document validation checks combat overrides")
        input.damage = 27.5
        input.guardId, input.position, input.angles = nil, nil, nil
        input.model = "models/player/group03/male_03.mdl"
        check(not config.Validate(input), "unsupported rebel models are rejected")
        input.model = "models/player/group01/male_03.mdl"
        input.shirt = "pants_a"
        check(not config.Validate(input), "mismatched clothing is rejected")
        input.shirt, input.range = "", 3001
        check(not config.Validate(input), "engagement range cannot exceed the weapon's actual range")
        input.range, input.weapon = 1200, "unknown"
        check(not config.Validate(input), "unknown weapons fail explicitly")
        input.weapon, input.range = "pistol", 0 / 0
        check(not config.Validate(input), "non-finite range is rejected")
        input.range, input.extra = 1200, true
        check(not config.Validate(input), "unexpected settings are rejected")
    end)
    suite:Add("Hammer guard keyvalues use the same validated settings", function(check)
        local clothing = {
            Models = { ["models/player/group01/male_03.mdl"] = "male" },
            Finishes = { shirt_a = { garment = "shirt" }, pants_a = { garment = "pants" } }
        }
        local weapons = { Resolve = function(id)
            if id ~= "pistol" then return nil, "Unknown guard weapon." end
            return { id = "pistol", range = 3000, damage = 12, delay = 0.2, spread = 0.02 }
        end }
        local config = createConfig(clothing, weapons, function(model) return model == "models/player/group01/male_03.mdl" end,
            contract)
        local defaults, problem = config.FromHammer({})
        check(defaults and defaults.name == "Guard" and defaults.range == 1000
            and defaults.damage == nil and defaults.fireInterval == nil and defaults.spread == nil,
            "missing Hammer fields use the documented defaults: " .. tostring(problem))
        local values = { guard_name = "Alex", model = "models/player/group01/male_03.mdl", idle = "idle_all_01",
            weapon = "pistol", range = "1200", shirt = "shirt_a", pants = "pants_a",
            damage = "25.5", fire_interval = "0.075", spread = "0" }
        local input = config.FromHammer(values)
        local resolved = input and config.Validate(input)
        check(resolved and resolved.name == "Alex" and resolved.shirt == "shirt_a"
            and resolved.pants == "pants_a" and resolved.weapon.damage == 25.5
            and resolved.weapon.delay == 0.075 and resolved.weapon.spread == 0,
            "Hammer clothing and numeric combat settings reach the guard config")
        values.fire_interval = "bad"
        local invalid, message = config.FromHammer(values)
        check(not invalid and type(message) == "string", "malformed numeric overrides are reported")
        values.fire_interval = "0.01"
        check(not config.FromHammer(values), "unsafe firing intervals are rejected")
        values.fire_interval, values.shirt = "", "pants_a"
        check(not config.FromHammer(values), "invalid clothing is not silently discarded")
        values.shirt, values.range = "", ""
        check(not config.FromHammer(values), "an explicitly empty range is rejected")
    end)
    return suite
end
