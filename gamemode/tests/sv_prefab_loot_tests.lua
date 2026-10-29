return function(createLoot)
    local suite = ZM_TestHarness.NewSuite()
    local entries = { { item = "bandage" } }
    local groupEntries = { { item = "ammo" } }
    local static = {
        GetLootGroup = function(_, id)
            if id == "lootAmmo" then return { entries = groupEntries } end
            if id == "empty" then return { entries = {} } end
        end,
        GetEntityLootRule = function(_, class, model)
            if class == "prop_physics" and model == "recognized" then
                return { entries = entries, activationChance = 0.6 }
            end
        end
    }
    local loot = createLoot(static)

    suite:Add("prefab loot rules use validated model and group data", function(check)
        local rule, problem = loot.Resolve({ model = "missing", lootMode = "off" })
        check(rule == nil and problem == nil, "non-lootable props do not require a model loot rule")
        rule = loot.Resolve({ model = "recognized", lootMode = "normal" })
        check(rule and rule.entries == entries and rule.activationChance == 0.6,
            "normal model loot retains its existing chance and entries")
        rule = loot.Resolve({ model = "recognized", lootMode = "normal", lootGroup = "lootAmmo" })
        check(rule and rule.entries == groupEntries and rule.activationChance == 0.6,
            "a group override retains the model activation chance")
        rule = loot.Resolve({ model = "missing", lootMode = "normal", lootGroup = "lootAmmo", lootChance = 0.4 })
        check(rule and rule.entries == groupEntries and rule.activationChance == 0.4,
            "unrecognized models use an explicitly configured activation chance")
        rule = loot.Resolve({ model = "missing", lootMode = "guaranteed", lootGroup = "lootAmmo" })
        check(rule and rule.entries == groupEntries, "guaranteed group loot needs no activation chance")
        for _, prop in ipairs({
            { model = "missing", lootMode = "normal" },
            { model = "missing", lootMode = "normal", lootGroup = "lootAmmo" },
            { model = "recognized", lootMode = "normal", lootGroup = "unknown" },
            { model = "recognized", lootMode = "off", lootGroup = "empty" }
        }) do
            rule, problem = loot.Resolve(prop)
            check(not rule and type(problem) == "string", "invalid loot configuration reports a reason")
        end
        local ok, validationError = loot.Validate({ props = { { model = "missing", lootMode = "normal" } } })
        check(not ok and type(validationError) == "string", "document validation identifies the invalid prop")
    end)
    return suite
end
