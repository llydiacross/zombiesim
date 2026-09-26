// Shared loader and validated registries for the item, loot, enemy, and boss JSON in data_static/.
// Registries are read-only after load; a failed load never replaces the previous valid registry.
ZM_StaticData = ZM_StaticData or {}
local StaticData = ZM_StaticData

StaticData.SchemaVersion = 1
StaticData.Files = {
    items = "data_static/item_definitions.json",
    loot = "data_static/loot.json",
    entityLoot = "data_static/entity_loot.json",
    enemies = "data_static/enemy_definitions.json",
    enemySpawns = "data_static/enemy_spawns.json",
    bosses = "data_static/boss_spawns.json"
}
StaticData.MaximumItemLevel = 300
StaticData.DefaultMastercraftChance = 0.05
StaticData.PlayerAttributes = {
    Strength = true, Agility = true, Intelligence = true, Endurance = true,
    MachineGuns = true, Shotguns = true, Snipers = true,
    WeaponCrafting = true, ArmorCrafting = true, Medicine = true, Farming = true,
    WeaponRepairing = true, ArmorRepairing = true, Mechanics = true
}
StaticData.ItemEntityClasses = { generic = true, entity = true, weapon = true }
StaticData.ReservedItemEntityClasses = { armour = true, clothing = true }
StaticData.AttributeTypes = {
    bullet_weapon = { "Damage", "Range", "FiringSpeed", "ReloadSpeed", "ClipSize" },
    melee_weapon = { "Damage", "Range", "Swiftness", "Crushing" }
}
StaticData.ReservedAttributeTypes = { heavy_armour = true, light_armour = true }
// Hammer *_override classes spawn as their base class, so rules match on the canonical name.
StaticData.LootPropClasses = {
    prop_physics = "prop_physics",
    prop_physics_override = "prop_physics",
    prop_physics_multiplayer = "prop_physics_multiplayer",
    prop_dynamic = "prop_dynamic",
    prop_dynamic_override = "prop_dynamic"
}
StaticData.DefaultLootPropClasses = { "prop_physics", "prop_physics_multiplayer", "prop_dynamic" }

local idPattern = "^%l%w*$"
local activeFiles = StaticData.Files

local function isObject(value)
    if type(value) ~= "table" then
        return false
    end
    for key in pairs(value) do
        if type(key) ~= "string" then
            return false
        end
    end
    return true
end

local function isArray(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function sortedKeys(source)
    local keys = {}
    for key in pairs(source) do
        table.insert(keys, key)
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    return keys
end

local function joinPath(path, key)
    if path == "" then
        return tostring(key)
    end
    return path .. "." .. tostring(key)
end

local function newReport()
    return { errors = {}, warnings = {} }
end

local function newContext(report, fileKey)
    local fileName = string.GetFileFromFilename(StaticData.Files[fileKey])
    local context = { fileName = fileName }
    function context:Error(path, message)
        table.insert(report.errors, { file = fileName, path = path, message = message })
    end
    function context:Warn(path, message)
        table.insert(report.warnings, { file = fileName, path = path, message = message })
    end
    return context
end

// Warns about unknown (likely misspelled) fields and rejects renamed prototype fields.
local function checkFields(context, source, allowed, renamed, path)
    for _, key in ipairs(sortedKeys(source)) do
        if renamed and renamed[key] then
            context:Error(joinPath(path, key), renamed[key])
        elseif not allowed[key] then
            context:Warn(joinPath(path, key), "is not a recognised field and is ignored")
        end
    end
end

local function readNumber(context, source, key, path, options)
    local value = source[key]
    local fieldPath = joinPath(path, key)
    if value == nil then
        if options.required then
            context:Error(fieldPath, "is required")
        end
        return options.default
    end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        context:Error(fieldPath, "must be a number")
        return options.default
    end
    if options.integer and value ~= math.floor(value) then
        context:Error(fieldPath, "must be a whole number")
        return options.default
    end
    if options.min and value < options.min then
        context:Error(fieldPath, "must be at least " .. options.min)
        return options.default
    end
    if options.max and value > options.max then
        context:Error(fieldPath, "must be at most " .. options.max)
        return options.default
    end
    return value
end

local function readString(context, source, key, path, options)
    local value = source[key]
    local fieldPath = joinPath(path, key)
    if value == nil then
        if options.required then
            context:Error(fieldPath, "is required")
        end
        return options.default
    end
    if type(value) ~= "string" or value == "" then
        context:Error(fieldPath, "must be a non-empty string")
        return options.default
    end
    if options.pattern and not string.match(value, options.pattern) then
        context:Error(fieldPath, options.patternMessage or "has an invalid format")
        return options.default
    end
    return value
end

local function readBoolean(context, source, key, path, default)
    local value = source[key]
    if value == nil then
        return default
    end
    if type(value) ~= "boolean" then
        context:Error(joinPath(path, key), "must be true or false")
        return default
    end
    return value
end

// Reads an array of ids that must exist in `known`. Returns the ids in authored order without duplicates.
local function readIdList(context, source, key, path, known, kind, required)
    local value = source[key]
    local fieldPath = joinPath(path, key)
    local ids = {}
    if value == nil then
        if required then
            context:Error(fieldPath, "is required")
        end
        return ids
    end
    if not isArray(value) then
        context:Error(fieldPath, "must be an array of " .. kind .. " ids")
        return ids
    end
    local seen = {}
    for index, id in ipairs(value) do
        local entryPath = fieldPath .. "[" .. index .. "]"
        if type(id) ~= "string" then
            context:Error(entryPath, "must be a " .. kind .. " id string")
        elseif not known[id] then
            context:Error(entryPath, "references unknown " .. kind .. " '" .. id .. "'")
        elseif seen[id] then
            context:Warn(entryPath, "repeats " .. kind .. " '" .. id .. "'")
        else
            seen[id] = true
            table.insert(ids, id)
        end
    end
    if required and #value == 0 then
        context:Error(fieldPath, "must list at least one " .. kind)
    end
    return ids
end

local function readJsonFile(report, fileKey)
    local context = newContext(report, fileKey)
    local path = activeFiles[fileKey]
    local json = file.Read(path, "GAME")
    if not json then
        context:Error("", "is missing or unreadable (" .. path .. ")")
        return nil, context
    end
    local data = util.JSONToTable(json)
    if not isObject(data) then
        context:Error("", "is not a valid JSON object (comments and trailing commas are not allowed)")
        return nil, context
    end
    if data.schemaVersion ~= StaticData.SchemaVersion then
        context:Error("schemaVersion", "must be " .. StaticData.SchemaVersion)
    end
    return data, context
end

// Converts an item id such as weaponHandgun9mm into its SWEP class, weapon_zn_handgun_9mm.
function StaticData.GetWeaponClassForItemId(itemId)
    local suffix = string.sub(itemId, 7)
    suffix = string.gsub(suffix, "(%l)(%u)", "%1_%2")
    suffix = string.gsub(suffix, "(%a)(%d)", "%1_%2")
    return "weapon_zn_" .. string.lower(suffix)
end

function StaticData.NormalizeModelPath(model)
    return string.lower(string.gsub(model, "\\", "/"))
end

local itemFields = {
    name = true, entityClass = true, type = true, thumbnail = true, value = true, maxStack = true,
    unit = true, minLevel = true, maxLevel = true, statRequirements = true, minAttributes = true, maxAttributes = true
}
local itemRenamedFields = {
    mastercrafted = "was removed; mastercraft is decided by loot entries (mastercraft or mastercraftChance)",
    mastercraft = "is not an item field; mastercraft is decided by loot entries",
    iconThumbnail = "was renamed to thumbnail",
    requiredLevel = "was renamed to minLevel"
}

local function validateItem(context, itemId, raw)
    local path = "items." .. tostring(itemId)
    if type(itemId) ~= "string" or not string.match(itemId, idPattern) then
        context:Error(path, "item ids must start with a lowercase letter and contain only letters and digits")
        return nil
    end
    if not isObject(raw) then
        context:Error(path, "must be an object")
        return nil
    end
    checkFields(context, raw, itemFields, itemRenamedFields, path)

    local item = { id = itemId }
    item.name = readString(context, raw, "name", path, { required = true })
    item.entityClass = readString(context, raw, "entityClass", path, { required = true })
    if StaticData.ReservedItemEntityClasses[item.entityClass] then
        context:Error(joinPath(path, "entityClass"), "'" .. item.entityClass .. "' items are not implemented yet (Alpha 2.7 Phase J)")
    elseif item.entityClass and not StaticData.ItemEntityClasses[item.entityClass] then
        context:Error(joinPath(path, "entityClass"), "must be generic, entity, or weapon")
    end

    item.type = readString(context, raw, "type", path, {})
    if item.entityClass == "weapon" then
        if not string.match(itemId, "^weapon%u") then
            context:Error(path, "weapon item ids must start with 'weapon' followed by an uppercase letter")
        else
            item.weaponClass = StaticData.GetWeaponClassForItemId(itemId)
        end
        if item.type == nil then
            context:Error(joinPath(path, "type"), "is required for weapon items (bullet_weapon or melee_weapon)")
        end
    end
    if item.type ~= nil then
        if StaticData.ReservedAttributeTypes[item.type] then
            context:Error(joinPath(path, "type"), "'" .. item.type .. "' is not implemented yet (Alpha 2.7 Phase J)")
        elseif not StaticData.AttributeTypes[item.type] then
            context:Error(joinPath(path, "type"), "must be bullet_weapon or melee_weapon")
        elseif item.entityClass ~= "weapon" then
            context:Error(joinPath(path, "type"), "only weapon items can have a weapon type")
        end
    end

    item.thumbnail = readString(context, raw, "thumbnail", path, {
        default = itemId,
        pattern = "^[%w_]+$",
        patternMessage = "must be a file name under materials/items/ without an extension (letters, digits, underscores)"
    })
    item.value = readNumber(context, raw, "value", path, { min = 0, default = 0 })
    item.maxStack = readNumber(context, raw, "maxStack", path, { integer = true, min = 1, default = 1 })
    if item.entityClass == "weapon" and item.maxStack ~= 1 then
        context:Error(joinPath(path, "maxStack"), "must be 1 for weapon items")
    end
    item.unit = readString(context, raw, "unit", path, {})
    item.minLevel = readNumber(context, raw, "minLevel", path, { integer = true, min = 1, max = StaticData.MaximumItemLevel, default = 1 })
    item.maxLevel = readNumber(context, raw, "maxLevel", path, { integer = true, min = 1, max = StaticData.MaximumItemLevel, default = item.minLevel })
    if item.maxLevel < item.minLevel then
        context:Error(joinPath(path, "maxLevel"), "must not be below minLevel")
    end

    item.statRequirements = {}
    if raw.statRequirements ~= nil then
        local requirementsPath = joinPath(path, "statRequirements")
        if not isObject(raw.statRequirements) then
            context:Error(requirementsPath, "must be an object of attribute name to required points")
        else
            for _, attribute in ipairs(sortedKeys(raw.statRequirements)) do
                if not StaticData.PlayerAttributes[attribute] then
                    local hint = attribute == "Medical" and " (did you mean Medicine?)" or ""
                    context:Error(joinPath(requirementsPath, attribute), "is not a player attribute" .. hint)
                else
                    item.statRequirements[attribute] = readNumber(context, raw.statRequirements, attribute, requirementsPath, { integer = true, min = 0, required = true })
                end
            end
        end
    end

    local attributes = StaticData.AttributeTypes[item.type or ""]
    if attributes and item.entityClass == "weapon" then
        item.attributes = table.Copy(attributes)
        item.minAttributes = readNumber(context, raw, "minAttributes", path, { integer = true, min = 0, max = 100, default = 2 })
        item.maxAttributes = readNumber(context, raw, "maxAttributes", path, { integer = true, min = 0, max = 100, default = 32 })
        if item.maxAttributes < item.minAttributes then
            context:Error(joinPath(path, "maxAttributes"), "must not be below minAttributes")
        end
    elseif raw.minAttributes ~= nil or raw.maxAttributes ~= nil then
        context:Error(path, "minAttributes/maxAttributes only apply to items with a weapon type")
    end
    return item
end

local function validateItems(report, registry)
    local data, context = readJsonFile(report, "items")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, items = true }, nil, "")
    if not isObject(data.items) then
        context:Error("items", "must be an object keyed by item id")
        return
    end
    for _, itemId in ipairs(sortedKeys(data.items)) do
        local item = validateItem(context, itemId, data.items[itemId])
        if item then
            registry.items[itemId] = item
        end
    end
end

local lootEntryFields = { minWeight = true, maxWeight = true, minCount = true, maxCount = true, mastercraft = true, mastercraftChance = true, bossOnly = true }
local lootEntryRenamedFields = { weight = "use minWeight and optionally maxWeight" }

// Copies only valid authored fields; defaults are applied after composition so implied values follow overrides.
local function readLootEntryFields(context, raw, path, requireWeight)
    local entry = {}
    if not isObject(raw) then
        context:Error(path, "must be an object")
        return entry
    end
    checkFields(context, raw, lootEntryFields, lootEntryRenamedFields, path)
    entry.minWeight = readNumber(context, raw, "minWeight", path, { min = 0, required = requireWeight })
    entry.maxWeight = readNumber(context, raw, "maxWeight", path, { min = 0 })
    entry.minCount = readNumber(context, raw, "minCount", path, { integer = true, min = 1 })
    entry.maxCount = readNumber(context, raw, "maxCount", path, { integer = true, min = 1 })
    entry.mastercraft = readBoolean(context, raw, "mastercraft", path, nil)
    entry.mastercraftChance = readNumber(context, raw, "mastercraftChance", path, { min = 0, max = 1 })
    entry.bossOnly = readBoolean(context, raw, "bossOnly", path, false)
    return entry
end

local function newPool()
    return { order = {}, entries = {} }
end

local function putPoolEntry(pool, id, entry)
    if not pool.entries[id] then
        table.insert(pool.order, id)
    end
    pool.entries[id] = table.Copy(entry)
end

local function appendPool(target, source)
    for _, id in ipairs(source.order) do
        putPoolEntry(target, id, source.entries[id])
    end
end

local function normalizeLootPool(context, path, pool, items)
    local entries = {}
    local canRoll = false
    for _, itemId in ipairs(pool.order) do
        local raw = pool.entries[itemId]
        local item = items[itemId]
        local entryPath = joinPath(path, itemId)
        local entry = { item = itemId }
        entry.minWeight = raw.minWeight or 0
        entry.maxWeight = raw.maxWeight or entry.minWeight
        entry.minCount = raw.minCount or 1
        entry.maxCount = raw.maxCount or entry.minCount
        if entry.maxCount < entry.minCount then
            context:Error(entryPath, "maxCount must not be below minCount")
        end
        if entry.maxCount > item.maxStack then
            context:Error(entryPath, "maxCount " .. entry.maxCount .. " exceeds the item's maxStack of " .. item.maxStack)
        end
        local canMastercraft = item.attributes ~= nil
        if not canMastercraft and (raw.mastercraft ~= nil or raw.mastercraftChance ~= nil) then
            context:Error(entryPath, "mastercraft only applies to items with a weapon type")
        end
        entry.mastercraft = raw.mastercraft == true
        entry.mastercraftChance = canMastercraft and (raw.mastercraftChance or StaticData.DefaultMastercraftChance) or 0
        entry.bossOnly = raw.bossOnly == true
        if math.max(entry.minWeight, entry.maxWeight) > 0 then
            canRoll = true
        end
        table.insert(entries, entry)
    end
    if not canRoll then
        context:Error(path, "can never roll an item (no entry has a weight above 0)")
    end
    return entries
end

local function validateLoot(report, registry, internal)
    local data, context = readJsonFile(report, "loot")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, groups = true }, nil, "")
    if not isObject(data.groups) then
        context:Error("groups", "must be an object keyed by loot group id")
        return
    end

    local source = data.groups
    local state = {}
    local pools = {}
    local function resolve(groupId, stack)
        if state[groupId] == "done" then
            return pools[groupId]
        elseif state[groupId] == "failed" then
            return nil
        elseif state[groupId] == "visiting" then
            context:Error("groups." .. groupId, "includes itself through " .. table.concat(stack, " -> ") .. " -> " .. groupId)
            return nil
        end

        local path = "groups." .. groupId
        local raw = source[groupId]
        if not string.match(groupId, idPattern) then
            context:Error(path, "group ids must start with a lowercase letter and contain only letters and digits")
            state[groupId] = "failed"
            return nil
        end
        if not isObject(raw) then
            context:Error(path, "must be an object with include, items, and/or overrides")
            state[groupId] = "failed"
            return nil
        end
        checkFields(context, raw, { include = true, items = true, overrides = true }, nil, path)
        if raw.include == nil and raw.items == nil then
            context:Error(path, "must define include and/or items")
        end

        state[groupId] = "visiting"
        table.insert(stack, groupId)
        local pool = newPool()
        if raw.include ~= nil then
            if not isArray(raw.include) then
                context:Error(joinPath(path, "include"), "must be an array of loot group ids")
            else
                for index, includeId in ipairs(raw.include) do
                    local includePath = joinPath(path, "include") .. "[" .. index .. "]"
                    if type(includeId) ~= "string" or source[includeId] == nil then
                        context:Error(includePath, "references unknown loot group '" .. tostring(includeId) .. "'")
                    else
                        local included = resolve(includeId, stack)
                        if included then
                            appendPool(pool, included)
                        end
                    end
                end
            end
        end
        if raw.items ~= nil then
            if not isObject(raw.items) then
                context:Error(joinPath(path, "items"), "must be an object keyed by item id")
            else
                for _, itemId in ipairs(sortedKeys(raw.items)) do
                    local itemPath = joinPath(joinPath(path, "items"), itemId)
                    if not registry.items[itemId] then
                        context:Error(itemPath, "references unknown item '" .. itemId .. "'")
                    else
                        putPoolEntry(pool, itemId, readLootEntryFields(context, raw.items[itemId], itemPath, true))
                    end
                end
            end
        end
        if raw.overrides ~= nil then
            if not isObject(raw.overrides) then
                context:Error(joinPath(path, "overrides"), "must be an object keyed by item id")
            else
                for _, itemId in ipairs(sortedKeys(raw.overrides)) do
                    local overridePath = joinPath(joinPath(path, "overrides"), itemId)
                    local entry = pool.entries[itemId]
                    if not entry then
                        context:Error(overridePath, "overrides item '" .. itemId .. "', which is not in this group")
                    else
                        for field, value in pairs(readLootEntryFields(context, raw.overrides[itemId], overridePath, false)) do
                            entry[field] = value
                        end
                    end
                end
            end
        end
        table.remove(stack)
        state[groupId] = "done"
        pools[groupId] = pool
        return pool
    end

    for _, groupId in ipairs(sortedKeys(source)) do
        resolve(groupId, {})
    end
    for _, groupId in ipairs(sortedKeys(pools)) do
        registry.lootGroups[groupId] = {
            id = groupId,
            entries = normalizeLootPool(context, "groups." .. groupId, pools[groupId], registry.items)
        }
    end
    internal.lootPools = pools
end

// Combines several loot groups into one pool with the same later-wins rule as include.
local function buildCombinedLootEntries(context, path, groupIds, registry, internal)
    if #groupIds == 0 then
        return {}
    end
    local pool = newPool()
    for _, groupId in ipairs(groupIds) do
        appendPool(pool, internal.lootPools[groupId])
    end
    return normalizeLootPool(context, path, pool, registry.items)
end

local entityLootRuleFields = { classes = true, model = true, lootGroups = true, activationChance = true }

local function validateEntityLoot(report, registry, internal)
    local data, context = readJsonFile(report, "entityLoot")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, rules = true }, nil, "")
    if not isArray(data.rules) then
        context:Error("rules", "must be an array of rule objects")
        return
    end

    local ruleIndexByClassModel = {}
    for index, raw in ipairs(data.rules) do
        local path = "rules[" .. index .. "]"
        if not isObject(raw) then
            context:Error(path, "must be an object with model, lootGroups, and activationChance")
        else
            checkFields(context, raw, entityLootRuleFields, nil, path)
            local rule = { index = index }
            local model = readString(context, raw, "model", path, { required = true })
            if model then
                rule.model = StaticData.NormalizeModelPath(model)
                if not string.match(rule.model, "^models/.+%.mdl$") then
                    context:Error(joinPath(path, "model"), "must be a path like models/<folder>/<name>.mdl")
                end
            end

            rule.classes = {}
            local classes = raw.classes
            if classes == nil then
                classes = StaticData.DefaultLootPropClasses
            elseif not isArray(classes) or #classes == 0 then
                context:Error(joinPath(path, "classes"), "must be a non-empty array of prop classes")
                classes = {}
            end
            local seenClasses = {}
            for classIndex, className in ipairs(classes) do
                local classPath = joinPath(path, "classes") .. "[" .. classIndex .. "]"
                local canonical = type(className) == "string" and StaticData.LootPropClasses[className] or nil
                if className == "prop_static" then
                    context:Error(classPath, "static props are compiled into the map and cannot be looted; use prop_physics_override or prop_dynamic_override in the template")
                elseif not canonical then
                    context:Error(classPath, "must be prop_physics, prop_physics_multiplayer, or prop_dynamic")
                elseif not seenClasses[canonical] then
                    seenClasses[canonical] = true
                    table.insert(rule.classes, canonical)
                end
            end

            rule.lootGroups = readIdList(context, raw, "lootGroups", path, registry.lootGroups, "loot group", true)
            rule.activationChance = readNumber(context, raw, "activationChance", path, { min = 0, max = 1, required = true })
            rule.entries = buildCombinedLootEntries(context, path, rule.lootGroups, registry, internal)

            if rule.model then
                for _, className in ipairs(rule.classes) do
                    local key = className .. "|" .. rule.model
                    if ruleIndexByClassModel[key] then
                        context:Error(path, "duplicates rules[" .. ruleIndexByClassModel[key] .. "] for " .. className .. " " .. rule.model)
                    else
                        ruleIndexByClassModel[key] = index
                        registry.entityLoot.byClass[className] = registry.entityLoot.byClass[className] or {}
                        registry.entityLoot.byClass[className][rule.model] = rule
                    end
                end
            end
            table.insert(registry.entityLoot.rules, rule)
        end
    end
end

local enemyFields = {
    entity = true, minHealth = true, maxHealth = true, minSpeed = true, maxSpeed = true,
    minDanger = true, maxDanger = true, minSpawnWeight = true, maxSpawnWeight = true,
    boss = true, minLootDropChance = true, maxLootDropChance = true, lootGroups = true, xp = true
}
local enemyRenamedFields = {
    minRarity = "was renamed to minSpawnWeight (a danger-scaled relative weight)",
    maxRarity = "was renamed to maxSpawnWeight (a danger-scaled relative weight)",
    lootGroup = "was renamed to lootGroups (an array of loot group ids)"
}

local function validateEnemy(context, enemyId, raw, registry, internal)
    local path = "enemies." .. tostring(enemyId)
    if type(enemyId) ~= "string" or not string.match(enemyId, idPattern) then
        context:Error(path, "enemy ids must start with a lowercase letter and contain only letters and digits")
        return nil
    end
    if not isObject(raw) then
        context:Error(path, "must be an object")
        return nil
    end
    checkFields(context, raw, enemyFields, enemyRenamedFields, path)

    local enemy = { id = enemyId }
    enemy.entity = readString(context, raw, "entity", path, {
        required = true,
        pattern = "^[%l_][%l%d_]*$",
        patternMessage = "must be a lowercase entity class name"
    })
    enemy.minHealth = readNumber(context, raw, "minHealth", path, { integer = true, min = 1, required = true, default = 1 })
    enemy.maxHealth = readNumber(context, raw, "maxHealth", path, { integer = true, min = 1, default = enemy.minHealth })
    if enemy.maxHealth < enemy.minHealth then
        context:Error(joinPath(path, "maxHealth"), "must not be below minHealth")
    end
    enemy.minSpeed = readNumber(context, raw, "minSpeed", path, { min = 0.01, default = 1 })
    enemy.maxSpeed = readNumber(context, raw, "maxSpeed", path, { min = 0.01, default = enemy.minSpeed })
    if enemy.maxSpeed < enemy.minSpeed then
        context:Error(joinPath(path, "maxSpeed"), "must not be below minSpeed")
    end
    enemy.minDanger = readNumber(context, raw, "minDanger", path, { min = 0, max = 1, default = 0 })
    enemy.maxDanger = readNumber(context, raw, "maxDanger", path, { min = 0, max = 1, default = 1 })
    if enemy.maxDanger < enemy.minDanger then
        context:Error(joinPath(path, "maxDanger"), "must not be below minDanger")
    end
    enemy.boss = readBoolean(context, raw, "boss", path, false)
    enemy.xp = readNumber(context, raw, "xp", path, { integer = true, min = 0, default = 0 })
    local spawnWeightRequired = not enemy.boss
    local rawMinSpawnWeight = readNumber(context, raw, "minSpawnWeight", path, { min = 0, required = spawnWeightRequired })
    local rawMaxSpawnWeight = readNumber(context, raw, "maxSpawnWeight", path, { min = 0 })
    internal.enemySpawnWeights[enemyId] = { minSpawnWeight = rawMinSpawnWeight, maxSpawnWeight = rawMaxSpawnWeight }
    enemy.minSpawnWeight = rawMinSpawnWeight or 0
    enemy.maxSpawnWeight = rawMaxSpawnWeight or enemy.minSpawnWeight
    enemy.minLootDropChance = readNumber(context, raw, "minLootDropChance", path, { min = 0, max = 1, default = 0 })
    enemy.maxLootDropChance = readNumber(context, raw, "maxLootDropChance", path, { min = 0, max = 1, default = enemy.minLootDropChance })
    enemy.lootGroups = readIdList(context, raw, "lootGroups", path, registry.lootGroups, "loot group", false)
    if #enemy.lootGroups == 0 and math.max(enemy.minLootDropChance, enemy.maxLootDropChance) > 0 then
        context:Error(joinPath(path, "lootGroups"), "is required when a loot drop chance is above 0")
    end
    enemy.lootEntries = buildCombinedLootEntries(context, path, enemy.lootGroups, registry, internal)
    return enemy
end

local function validateEnemies(report, registry, internal)
    local data, context = readJsonFile(report, "enemies")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, enemies = true }, nil, "")
    if not isObject(data.enemies) then
        context:Error("enemies", "must be an object keyed by enemy id")
        return
    end
    for _, enemyId in ipairs(sortedKeys(data.enemies)) do
        local enemy = validateEnemy(context, enemyId, data.enemies[enemyId], registry, internal)
        if enemy then
            registry.enemies[enemyId] = enemy
        end
    end
end

local spawnOverrideFields = { minSpawnWeight = true, maxSpawnWeight = true }

local function validateEnemySpawns(report, registry, internal)
    local data, context = readJsonFile(report, "enemySpawns")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, defaultGroup = true, groups = true, environmentTags = true }, nil, "")
    if not isObject(data.groups) then
        context:Error("groups", "must be an object keyed by spawn group id")
        return
    end

    local source = data.groups
    local state = {}
    local pools = {}
    local function resolve(groupId, stack)
        if state[groupId] == "done" then
            return pools[groupId]
        elseif state[groupId] == "failed" then
            return nil
        elseif state[groupId] == "visiting" then
            context:Error("groups." .. groupId, "includes itself through " .. table.concat(stack, " -> ") .. " -> " .. groupId)
            return nil
        end

        local path = "groups." .. groupId
        local raw = source[groupId]
        if not string.match(groupId, idPattern) then
            context:Error(path, "group ids must start with a lowercase letter and contain only letters and digits")
            state[groupId] = "failed"
            return nil
        end
        if not isObject(raw) then
            context:Error(path, "must be an object with include, enemies, and/or overrides")
            state[groupId] = "failed"
            return nil
        end
        checkFields(context, raw, { include = true, enemies = true, overrides = true }, nil, path)
        if raw.include == nil and raw.enemies == nil then
            context:Error(path, "must define include and/or enemies")
        end

        state[groupId] = "visiting"
        table.insert(stack, groupId)
        local pool = newPool()
        if raw.include ~= nil then
            if not isArray(raw.include) then
                context:Error(joinPath(path, "include"), "must be an array of spawn group ids")
            else
                for index, includeId in ipairs(raw.include) do
                    local includePath = joinPath(path, "include") .. "[" .. index .. "]"
                    if type(includeId) ~= "string" or source[includeId] == nil then
                        context:Error(includePath, "references unknown spawn group '" .. tostring(includeId) .. "'")
                    else
                        local included = resolve(includeId, stack)
                        if included then
                            appendPool(pool, included)
                        end
                    end
                end
            end
        end
        for _, enemyId in ipairs(readIdList(context, raw, "enemies", path, registry.enemies, "enemy", false)) do
            if registry.enemies[enemyId].boss then
                context:Error(joinPath(path, "enemies"), "'" .. enemyId .. "' is a boss; bosses spawn through boss_spawns.json")
            else
                putPoolEntry(pool, enemyId, internal.enemySpawnWeights[enemyId])
            end
        end
        if raw.overrides ~= nil then
            if not isObject(raw.overrides) then
                context:Error(joinPath(path, "overrides"), "must be an object keyed by enemy id")
            else
                for _, enemyId in ipairs(sortedKeys(raw.overrides)) do
                    local overridePath = joinPath(joinPath(path, "overrides"), enemyId)
                    local entry = pool.entries[enemyId]
                    local override = raw.overrides[enemyId]
                    if not entry then
                        context:Error(overridePath, "overrides enemy '" .. enemyId .. "', which is not in this group")
                    elseif not isObject(override) then
                        context:Error(overridePath, "must be an object")
                    else
                        checkFields(context, override, spawnOverrideFields, nil, overridePath)
                        for field in pairs(spawnOverrideFields) do
                            local value = readNumber(context, override, field, overridePath, { min = 0 })
                            if value ~= nil then
                                entry[field] = value
                            end
                        end
                    end
                end
            end
        end
        table.remove(stack)
        state[groupId] = "done"
        pools[groupId] = pool
        return pool
    end

    for _, groupId in ipairs(sortedKeys(source)) do
        resolve(groupId, {})
    end
    for _, groupId in ipairs(sortedKeys(pools)) do
        local pool = pools[groupId]
        local entries = {}
        local canSpawn = false
        for _, enemyId in ipairs(pool.order) do
            local raw = pool.entries[enemyId]
            local entry = { enemy = enemyId }
            entry.minSpawnWeight = raw.minSpawnWeight or 0
            entry.maxSpawnWeight = raw.maxSpawnWeight or entry.minSpawnWeight
            if math.max(entry.minSpawnWeight, entry.maxSpawnWeight) > 0 then
                canSpawn = true
            end
            table.insert(entries, entry)
        end
        if not canSpawn then
            context:Error("groups." .. groupId, "can never spawn an enemy (no entry has a spawn weight above 0)")
        end
        registry.spawnGroups[groupId] = { id = groupId, enemies = entries }
    end

    registry.defaultSpawnGroup = readString(context, data, "defaultGroup", "", { required = true })
    if registry.defaultSpawnGroup and not registry.spawnGroups[registry.defaultSpawnGroup] then
        context:Error("defaultGroup", "references unknown spawn group '" .. registry.defaultSpawnGroup .. "'")
    end
    if data.environmentTags ~= nil then
        if not isObject(data.environmentTags) then
            context:Error("environmentTags", "must be an object of environment tag to spawn group id")
        else
            for _, tag in ipairs(sortedKeys(data.environmentTags)) do
                local tagPath = joinPath("environmentTags", tag)
                local groupId = data.environmentTags[tag]
                if not string.match(tag, "^[%l_]+$") then
                    context:Error(tagPath, "environment tags are lowercase words with underscores")
                elseif type(groupId) ~= "string" or not registry.spawnGroups[groupId] then
                    context:Error(tagPath, "references unknown spawn group '" .. tostring(groupId) .. "'")
                else
                    registry.environmentTags[tag] = groupId
                end
            end
        end
    end
end

local bossFields = { enemy = true, spawnConditions = true, mapMarker = true, lootGroups = true }
local bossRenamedFields = {
    entityDefinition = "was renamed to enemy",
    lootGroup = "was renamed to lootGroups (an array of loot group ids)"
}
local spawnConditionFields = { minCellDanger = true, allowedEnvironmentTags = true, maxActiveWorldCount = true, cooldownHours = true }
local mapMarkerFields = { showOnMinimap = true, icon = true, label = true }

local function validateBoss(context, bossId, raw, registry, internal)
    local path = "bosses." .. tostring(bossId)
    if type(bossId) ~= "string" or not string.match(bossId, idPattern) then
        context:Error(path, "boss ids must start with a lowercase letter and contain only letters and digits")
        return nil
    end
    if not isObject(raw) then
        context:Error(path, "must be an object")
        return nil
    end
    checkFields(context, raw, bossFields, bossRenamedFields, path)

    local boss = { id = bossId }
    boss.enemy = readString(context, raw, "enemy", path, { required = true })
    local enemy = boss.enemy and registry.enemies[boss.enemy] or nil
    if boss.enemy and not enemy then
        context:Error(joinPath(path, "enemy"), "references unknown enemy '" .. boss.enemy .. "'")
    elseif enemy and not enemy.boss then
        context:Error(joinPath(path, "enemy"), "'" .. boss.enemy .. "' must set boss: true in enemy_definitions.json")
    end

    local conditions = raw.spawnConditions or {}
    local conditionsPath = joinPath(path, "spawnConditions")
    if not isObject(conditions) then
        context:Error(conditionsPath, "must be an object")
        conditions = {}
    end
    checkFields(context, conditions, spawnConditionFields, nil, conditionsPath)
    boss.spawnConditions = {
        minCellDanger = readNumber(context, conditions, "minCellDanger", conditionsPath, { min = 0, max = 1, default = 0 }),
        maxActiveWorldCount = readNumber(context, conditions, "maxActiveWorldCount", conditionsPath, { integer = true, min = 1, default = 1 }),
        cooldownHours = readNumber(context, conditions, "cooldownHours", conditionsPath, { min = 0, default = 0 }),
        allowedEnvironmentTags = {}
    }
    local tags = conditions.allowedEnvironmentTags
    if tags ~= nil then
        if not isArray(tags) then
            context:Error(joinPath(conditionsPath, "allowedEnvironmentTags"), "must be an array of environment tags")
        else
            for index, tag in ipairs(tags) do
                if type(tag) ~= "string" or not string.match(tag, "^[%l_]+$") then
                    context:Error(joinPath(conditionsPath, "allowedEnvironmentTags") .. "[" .. index .. "]", "environment tags are lowercase words with underscores")
                else
                    table.insert(boss.spawnConditions.allowedEnvironmentTags, tag)
                end
            end
        end
    end

    local marker = raw.mapMarker or {}
    local markerPath = joinPath(path, "mapMarker")
    if not isObject(marker) then
        context:Error(markerPath, "must be an object")
        marker = {}
    end
    checkFields(context, marker, mapMarkerFields, nil, markerPath)
    boss.mapMarker = {
        showOnMinimap = readBoolean(context, marker, "showOnMinimap", markerPath, true),
        icon = readString(context, marker, "icon", markerPath, {
            pattern = "^[%w_/]+$",
            patternMessage = "must be a material path without an extension"
        }),
        label = readString(context, marker, "label", markerPath, { default = bossId })
    }

    boss.lootGroups = readIdList(context, raw, "lootGroups", path, registry.lootGroups, "loot group", true)
    boss.lootEntries = buildCombinedLootEntries(context, path, boss.lootGroups, registry, internal)
    return boss
end

local function validateBosses(report, registry, internal)
    local data, context = readJsonFile(report, "bosses")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, bosses = true }, nil, "")
    if not isObject(data.bosses) then
        context:Error("bosses", "must be an object keyed by boss id")
        return
    end
    local referencedEnemies = {}
    for _, bossId in ipairs(sortedKeys(data.bosses)) do
        local boss = validateBoss(context, bossId, data.bosses[bossId], registry, internal)
        if boss then
            registry.bosses[bossId] = boss
            if boss.enemy then
                referencedEnemies[boss.enemy] = true
            end
        end
    end
    for _, enemyId in ipairs(sortedKeys(registry.enemies)) do
        if registry.enemies[enemyId].boss and not referencedEnemies[enemyId] then
            context:Warn("bosses", "boss enemy '" .. enemyId .. "' is not used by any boss spawn")
        end
    end
end

// Reads and validates every file into a new registry without touching the live one.
// `files` optionally replaces StaticData.Files (used by fixture tests).
// Returns the registry (nil when any error was found) and the report.
function StaticData:Build(files)
    activeFiles = files or self.Files
    local report = newReport()
    local registry = {
        items = {},
        lootGroups = {},
        entityLoot = { rules = {}, byClass = {} },
        enemies = {},
        spawnGroups = {},
        environmentTags = {},
        defaultSpawnGroup = nil,
        bosses = {},
        loadedAt = os.time()
    }
    local internal = { lootPools = {}, enemySpawnWeights = {} }
    validateItems(report, registry)
    validateLoot(report, registry, internal)
    validateEntityLoot(report, registry, internal)
    validateEnemies(report, registry, internal)
    validateEnemySpawns(report, registry, internal)
    validateBosses(report, registry, internal)
    activeFiles = self.Files
    if #report.errors > 0 then
        return nil, report
    end
    return registry, report
end

// Replaces the live registry only when every file validates. Returns success and the report.
function StaticData:Reload(files)
    local registry, report = self:Build(files)
    self.LastReport = report
    if not registry then
        return false, report
    end
    if self.RuntimeReady and self.ValidateRuntimeReferences then
        self:ValidateRuntimeReferences(registry, report)
    end
    self.Registry = registry
    return true, report
end

// Formats a report as console lines. `fileFilter` optionally limits output to a set of file names.
function StaticData:FormatReport(report, fileFilter)
    local lines = {}
    local errorCount, warningCount = 0, 0
    local function addLines(issues, label)
        local count = 0
        for _, issue in ipairs(issues) do
            if not fileFilter or fileFilter[issue.file] then
                local location = issue.path ~= "" and (issue.file .. " " .. issue.path) or issue.file
                table.insert(lines, label .. " " .. location .. ": " .. issue.message)
                count = count + 1
            end
        end
        return count
    end
    errorCount = addLines(report.errors, "ERROR")
    warningCount = addLines(report.warnings, "WARN ")
    table.insert(lines, string.format("%d error(s), %d warning(s).", errorCount, warningCount))
    return lines, errorCount, warningCount
end

function StaticData:GetSummary()
    local registry = self.Registry
    if not registry then
        return "no static data loaded"
    end
    return string.format(
        "%d items, %d loot groups, %d entity loot rules, %d enemies, %d spawn groups, %d bosses",
        table.Count(registry.items), table.Count(registry.lootGroups), #registry.entityLoot.rules,
        table.Count(registry.enemies), table.Count(registry.spawnGroups), table.Count(registry.bosses)
    )
end

function StaticData:GetRegistry()
    return self.Registry
end

function StaticData:GetItem(itemId)
    return self.Registry and self.Registry.items[itemId] or nil
end

function StaticData:GetLootGroup(groupId)
    return self.Registry and self.Registry.lootGroups[groupId] or nil
end

// Returns the loot rule for a runtime prop class and model, or nil if the prop is not lootable.
function StaticData:GetEntityLootRule(className, model)
    local canonical = self.LootPropClasses[className]
    if not self.Registry or not canonical or type(model) ~= "string" then
        return nil
    end
    local byModel = self.Registry.entityLoot.byClass[canonical]
    return byModel and byModel[self.NormalizeModelPath(model)] or nil
end

function StaticData:GetEnemy(enemyId)
    return self.Registry and self.Registry.enemies[enemyId] or nil
end

function StaticData:GetSpawnGroup(groupId)
    return self.Registry and self.Registry.spawnGroups[groupId] or nil
end

// Returns spawn group ids mapped from a cell's environment tags, or the default group when none match.
function StaticData:GetSpawnGroupIdsForTags(tags)
    local registry = self.Registry
    if not registry then
        return {}
    end
    local groupIds, seen = {}, {}
    for _, tag in ipairs(tags or {}) do
        local groupId = registry.environmentTags[tag]
        if groupId and not seen[groupId] then
            seen[groupId] = true
            table.insert(groupIds, groupId)
        end
    end
    if #groupIds == 0 and registry.defaultSpawnGroup then
        table.insert(groupIds, registry.defaultSpawnGroup)
    end
    return groupIds
end

function StaticData:GetBoss(bossId)
    return self.Registry and self.Registry.bosses[bossId] or nil
end

local function reportLoad(loaded, report)
    if loaded then
        print("[ZombieSim] Static data loaded: " .. StaticData:GetSummary() .. ".")
        return
    end
    local lines = StaticData:FormatReport(report)
    ErrorNoHalt("[ZombieSim] Static data failed to load; keeping the previous registry (" .. StaticData:GetSummary() .. ").\n")
    for _, line in ipairs(lines) do
        ErrorNoHalt("[ZombieSim]   " .. line .. "\n")
    end
end

function StaticData:ReloadAndReport()
    local loaded, report = self:Reload()
    reportLoad(loaded, report)
    return loaded, report
end

StaticData:ReloadAndReport()

if CLIENT then
    net.Receive("ZM.StaticDataReloaded", function()
        StaticData:ReloadAndReport()
    end)
end
