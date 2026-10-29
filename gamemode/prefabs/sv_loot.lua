return function(staticData)
    local PrefabLoot = {}

    function PrefabLoot.Resolve(prop)
        local group
        if prop.lootGroup then
            group = staticData:GetLootGroup(prop.lootGroup)
            if not group or type(group.entries) ~= "table" or #group.entries == 0 then
                return nil, "Unknown or empty loot group: " .. prop.lootGroup
            end
        end
        if prop.lootMode == "off" then return nil end
        local rule = staticData:GetEntityLootRule("prop_physics", prop.model)
        if not group and not rule then
            return nil, "This model has no loot rule; choose a loot group."
        end
        if prop.lootMode == "normal" and prop.lootChance == nil and not rule then
            return nil, "This model has no loot rule; set an activation chance."
        end
        return {
            entries = group and group.entries or rule.entries,
            activationChance = prop.lootChance ~= nil and prop.lootChance or (rule and rule.activationChance or 0)
        }
    end

    function PrefabLoot.Validate(document)
        for index, prop in ipairs(document.props) do
            local _, problem = PrefabLoot.Resolve(prop)
            if problem then return false, "Prefab prop " .. index .. ": " .. problem end
        end
        return true
    end

    return PrefabLoot
end
