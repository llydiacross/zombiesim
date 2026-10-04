// Shared loader and validated registries for the item, loot, enemy, boss, and recipe JSON in data_static/.
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
    bosses = "data_static/boss_spawns.json",
    recipes = "data_static/recipe_definitions.json",
    professions = "data_static/profession_definitions.json",
    denServices = "data_static/den_service_definitions.json",
    trade = "data_static/trade_definitions.json",
    music = "data_static/music_definitions.json"
}
StaticData.MaximumItemLevel = 300
StaticData.DefaultMastercraftChance = 0.05
StaticData.PlayerAttributes = {
    Strength = true, Agility = true, Intelligence = true, Endurance = true,
    MachineGuns = true, Shotguns = true, Snipers = true,
    WeaponCrafting = true, ArmorCrafting = true, Medicine = true, Farming = true,
    WeaponRepairing = true, ArmorRepairing = true, Mechanics = true
}
StaticData.ItemEntityClasses = { generic = true, entity = true, weapon = true, armour = true }
StaticData.ReservedItemEntityClasses = { clothing = true }
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
    prop_dynamic_override = "prop_dynamic",
    prop_ragdoll = "prop_ragdoll"
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
    unit = true, minLevel = true, maxLevel = true, statRequirements = true, minAttributes = true, maxAttributes = true,
    weaponClass = true, cssFamily = true, viewModel = true, worldModel = true, ammoId = true, firingMode = true, rarity = true,
    iconModel = true, food = true, medical = true, implant = true, lootCategory = true, radiationProtection = true
}

// Loot categories are derived from each definition (see deriveLootCategory) unless an item sets lootCategory.
// Implant loot effects boost the weights of one category; the implants category itself can never be boosted.
StaticData.LootCategories = { weapons = true, ammo = true, medical = true, food = true, cash = true, materials = true, implants = true, other = true }

// Implants are installed by a Doctor into one typed slot each. Effect values are authored as { atMinLevel, atMaxLevel }
// and interpolated by the instance level. perImplant bounds one implant's value; cap bounds the sum of all installed.
StaticData.ImplantSlots = { "Neural", "Ocular", "Dermal" }
StaticData.ImplantEffects = {
    lootWeapons = { perImplant = 0.5, cap = 0.75, category = "weapons", label = "weapon finds" },
    lootAmmo = { perImplant = 0.5, cap = 0.75, category = "ammo", label = "ammunition finds" },
    lootMedical = { perImplant = 0.5, cap = 0.75, category = "medical", label = "medical finds" },
    lootFood = { perImplant = 0.5, cap = 0.75, category = "food", label = "food finds" },
    lootCash = { perImplant = 0.5, cap = 0.75, category = "cash", label = "cash finds" },
    lootMaterials = { perImplant = 0.5, cap = 0.75, category = "materials", label = "material finds" },
    xpGain = { perImplant = 0.3, cap = 0.5, label = "XP gain" },
    moveSpeed = { perImplant = 0.15, cap = 0.2, label = "movement speed" },
    healthRegen = { perImplant = 6, cap = 10, label = "health regeneration", unit = "HP/min" }
}
local implantFields = { slot = true, effects = true }

local function validateImplant(context, raw, path)
    if not isObject(raw) then
        context:Error(path, "must be an object with a slot and effects")
        return nil
    end
    checkFields(context, raw, implantFields, nil, path)
    local implant = { effects = {} }
    implant.slot = readString(context, raw, "slot", path, { required = true })
    if implant.slot and not table.HasValue(StaticData.ImplantSlots, implant.slot) then
        context:Error(joinPath(path, "slot"), "must be one of " .. table.concat(StaticData.ImplantSlots, ", "))
    end
    local effectsPath = joinPath(path, "effects")
    if not isObject(raw.effects) or next(raw.effects) == nil then
        context:Error(effectsPath, "must be an object with at least one effect")
        return implant
    end
    for _, effectId in ipairs(sortedKeys(raw.effects)) do
        local effectPath = joinPath(effectsPath, effectId)
        local rule = StaticData.ImplantEffects[effectId]
        local value = raw.effects[effectId]
        if not rule then
            context:Error(effectPath, "is not an implant effect (" .. table.concat(sortedKeys(StaticData.ImplantEffects), ", ") .. ")")
        elseif not isArray(value) or #value ~= 2 or type(value[1]) ~= "number" or type(value[2]) ~= "number" then
            context:Error(effectPath, "must be [valueAtMinLevel, valueAtMaxLevel]")
        elseif value[1] <= 0 or value[2] < value[1] then
            context:Error(effectPath, "values must be above 0 and must not decrease with level")
        elseif value[2] > rule.perImplant then
            context:Error(effectPath, "must be at most " .. rule.perImplant .. " per implant")
        else
            implant.effects[effectId] = { value[1], value[2] }
        end
    end
    return implant
end

local function deriveLootCategory(item, ammoIds)
    if item.lootCategory then return item.lootCategory end
    if item.implant then return "implants" end
    if item.entityClass == "weapon" then return "weapons" end
    if ammoIds[item.id] or (item.entityClass == "generic" and string.match(item.id, "^ammo%w")) then return "ammo" end
    if item.food then return "food" end
    if item.medical then return "medical" end
    if item.entityClass == "generic" then return "materials" end
    return "other"
end

// Food tiers bound every food definition, so balance comes from these ranges rather than per-item exceptions.
// Shelf life is in real hours (spoilage keeps running while offline); nil shelfLife ranges mean the tier never spoils.
StaticData.FoodPreparations = { raw = true, preserved = true, cooked = true }
StaticData.FoodTiers = {
    [0] = { label = "Rotten", nutrition = { 0, 15 }, hydration = { 0, 10 }, health = { -20, 0 }, stamina = { 0, 10 } },
    [1] = { label = "Scavenged", nutrition = { 0, 25 }, hydration = { 0, 35 }, health = { -10, 5 }, stamina = { 0, 20 }, shelfLifeHours = { 6, 168 } },
    [2] = { label = "Ordinary", nutrition = { 15, 35 }, hydration = { 0, 20 }, health = { 0, 10 }, stamina = { 0, 30 }, shelfLifeHours = { 72, 720 } },
    [3] = { label = "Good", nutrition = { 30, 50 }, hydration = { 0, 25 }, health = { 0, 20 }, stamina = { 10, 50 }, shelfLifeHours = { 168, 1440 } },
    [4] = { label = "Factory", nutrition = { 40, 65 }, hydration = { 0, 30 }, health = { 5, 30 }, stamina = { 20, 70 }, shelfLifeHours = { 336, 2160 } },
    [5] = { label = "Lab-grown", nutrition = { 55, 80 }, hydration = { 0, 30 }, health = { 15, 50 }, stamina = { 40, 100 }, shelfLifeHours = { 720, 4320 } }
}
StaticData.FoodEffects = { "nutrition", "hydration", "health", "stamina" }
local foodFields = { preparation = true, tier = true, nutrition = true, hydration = true, health = true, stamina = true, shelfLifeHours = true, cooksInto = true }

local function validateFood(context, raw, path)
    if not isObject(raw) then
        context:Error(path, "must be an object with preparation, tier, and effect values")
        return nil
    end
    checkFields(context, raw, foodFields, nil, path)
    local food = {}
    food.preparation = readString(context, raw, "preparation", path, { required = true })
    if food.preparation and not StaticData.FoodPreparations[food.preparation] then
        context:Error(joinPath(path, "preparation"), "must be raw, preserved, or cooked")
    end
    food.tier = readNumber(context, raw, "tier", path, { integer = true, min = 0, max = 5, required = true })
    local tier = food.tier and StaticData.FoodTiers[food.tier]
    if not tier then
        return nil
    end
    for _, effect in ipairs(StaticData.FoodEffects) do
        local range = tier[effect]
        food[effect] = readNumber(context, raw, effect, path, { integer = true, min = range[1], max = range[2], default = math.max(range[1], 0) })
    end
    if tier.shelfLifeHours then
        local range = tier.shelfLifeHours
        food.shelfLifeHours = readNumber(context, raw, "shelfLifeHours", path, { min = range[1], max = range[2], required = true })
    elseif raw.shelfLifeHours ~= nil then
        context:Error(joinPath(path, "shelfLifeHours"), "tier " .. food.tier .. " food is already spoiled and cannot have a shelf life")
    end
    if food.nutrition + food.hydration + math.max(food.health, 0) + food.stamina <= 0 then
        context:Error(path, "food must restore at least one of nutrition, hydration, health, or stamina")
    end
    // Checked against the full item table in validateItems once every item is known.
    food.cooksInto = readString(context, raw, "cooksInto", path, {})
    if food.cooksInto and food.preparation ~= "raw" then
        context:Error(joinPath(path, "cooksInto"), "only raw food can be cooked")
    end
    return food
end

// Medical items heal a fixed amount; Doctors apply them for StaticData.DoctorMedicalBonus more.
StaticData.DoctorMedicalBonus = 0.5
local medicalFields = { health = true }

local function validateMedical(context, raw, path)
    if not isObject(raw) then
        context:Error(path, "must be an object with a health value")
        return nil
    end
    checkFields(context, raw, medicalFields, nil, path)
    local health = readNumber(context, raw, "health", path, { integer = true, min = 1, max = 100, required = true })
    return health and { health = health } or nil
end

// Mounted model used for an item's spawn icon when it names neither an iconModel nor a worldModel.
StaticData.DefaultItemIconModel = "models/props_junk/cardboard_box004a.mdl"
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
        context:Error(joinPath(path, "entityClass"), "must be generic, entity, weapon, or armour")
    end
    if raw.radiationProtection ~= nil then
        if item.entityClass ~= "armour" then
            context:Error(joinPath(path, "radiationProtection"), "only wearable armour can protect against radiation")
        else
            item.radiationProtection = readBoolean(context, raw, "radiationProtection", path, false)
        end
    end

    item.type = readString(context, raw, "type", path, {})
    if item.entityClass == "weapon" then
        if not string.match(itemId, "^weapon%u") then
            context:Error(path, "weapon item ids must start with 'weapon' followed by an uppercase letter")
        end
        local derivedClass = StaticData.GetWeaponClassForItemId(itemId)
        item.weaponClass = readString(context, raw, "weaponClass", path, { default = derivedClass })
        if not string.match(item.weaponClass or "", "^weapon_zn_[%w_]+$") then
            context:Error(joinPath(path, "weaponClass"), "must name a local weapon_zn_ SWEP, not a stock content class")
        end
        if item.type == nil then
            context:Error(joinPath(path, "type"), "is required for weapon items (bullet_weapon or melee_weapon)")
        end

        item.cssFamily = readString(context, raw, "cssFamily", path, {})
        item.viewModel = readString(context, raw, "viewModel", path, {})
        item.worldModel = readString(context, raw, "worldModel", path, {})
        item.ammoId = readString(context, raw, "ammoId", path, {})
        item.firingMode = readString(context, raw, "firingMode", path, {})
        item.rarity = readString(context, raw, "rarity", path, {})

        if raw.weaponClass ~= nil then
            if not item.cssFamily then context:Error(joinPath(path, "cssFamily"), "is required for an explicit weapon mapping") end
            if not item.viewModel then context:Error(joinPath(path, "viewModel"), "is required for an explicit weapon mapping") end
            if not item.worldModel then context:Error(joinPath(path, "worldModel"), "is required for an explicit weapon mapping") end
            if not item.ammoId then context:Error(joinPath(path, "ammoId"), "is required for an explicit weapon mapping") end
            if not item.firingMode then context:Error(joinPath(path, "firingMode"), "is required for an explicit weapon mapping") end
            if not item.rarity then context:Error(joinPath(path, "rarity"), "is required for an explicit weapon mapping") end
        end
        if item.viewModel and not string.match(item.viewModel, "^models/[%w_/%-]+%.mdl$") then
            context:Error(joinPath(path, "viewModel"), "must be a normalized models/ .mdl path")
        end
        if item.worldModel and not string.match(item.worldModel, "^models/[%w_/%-]+%.mdl$") then
            context:Error(joinPath(path, "worldModel"), "must be a normalized models/ .mdl path")
        end
        if item.ammoId and not string.match(item.ammoId, "^ammo[%w]+$") then
            context:Error(joinPath(path, "ammoId"), "must be a stable ammo item id beginning with ammo")
        end
        if item.firingMode and item.firingMode ~= "semi_auto" and item.firingMode ~= "automatic" then
            context:Error(joinPath(path, "firingMode"), "must be semi_auto or automatic")
        end
        local rarities = { common = true, uncommon = true, rare = true, very_rare = true }
        if item.rarity and not rarities[item.rarity] then
            context:Error(joinPath(path, "rarity"), "must be common, uncommon, rare, or very_rare")
        end
    elseif raw.weaponClass ~= nil or raw.cssFamily ~= nil or raw.viewModel ~= nil or raw.worldModel ~= nil
        or raw.ammoId ~= nil or raw.firingMode ~= nil or raw.rarity ~= nil then
        context:Error(path, "weapon mapping fields may only be used by weapon items")
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
    local iconModel = readString(context, raw, "iconModel", path, {})
    if iconModel and not string.match(iconModel, "^models/[%w_/%-]+%.mdl$") then
        context:Error(joinPath(path, "iconModel"), "must be a normalized models/ .mdl path")
    end
    item.iconModel = iconModel or item.worldModel or StaticData.DefaultItemIconModel
    item.value = readNumber(context, raw, "value", path, { min = 0, default = 0 })
    item.maxStack = readNumber(context, raw, "maxStack", path, { integer = true, min = 1, default = 1 })
    if (item.entityClass == "weapon" or item.entityClass == "armour") and item.maxStack ~= 1 then
        context:Error(joinPath(path, "maxStack"), "must be 1 for " .. item.entityClass .. " items")
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

    if raw.food ~= nil then
        if item.entityClass ~= "entity" then
            context:Error(joinPath(path, "food"), "only usable entity items can be food")
        else
            item.food = validateFood(context, raw.food, joinPath(path, "food"))
        end
    end
    if raw.medical ~= nil then
        if item.entityClass ~= "entity" then
            context:Error(joinPath(path, "medical"), "only usable entity items can be medical")
        elseif raw.food ~= nil then
            context:Error(joinPath(path, "medical"), "an item cannot be both food and medical")
        else
            item.medical = validateMedical(context, raw.medical, joinPath(path, "medical"))
        end
    end
    if raw.implant ~= nil then
        if item.entityClass ~= "generic" then
            context:Error(joinPath(path, "implant"), "implants must be generic items (they are installed, not used)")
        elseif raw.food ~= nil or raw.medical ~= nil then
            context:Error(joinPath(path, "implant"), "an implant cannot also be food or medical")
        elseif item.maxStack ~= 1 then
            context:Error(joinPath(path, "maxStack"), "must be 1 for implants")
        else
            item.implant = validateImplant(context, raw.implant, joinPath(path, "implant"))
        end
    end
    item.lootCategory = readString(context, raw, "lootCategory", path, {})
    if item.lootCategory and not StaticData.LootCategories[item.lootCategory] then
        context:Error(joinPath(path, "lootCategory"), "must be one of " .. table.concat(sortedKeys(StaticData.LootCategories), ", "))
        item.lootCategory = nil
    elseif item.lootCategory == "implants" and not raw.implant then
        context:Error(joinPath(path, "lootCategory"), "only implant items can use the implants category")
        item.lootCategory = nil
    elseif item.lootCategory and raw.implant then
        context:Error(joinPath(path, "lootCategory"), "implants always use the implants category")
        item.lootCategory = nil
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
    for _, itemId in ipairs(sortedKeys(registry.items)) do
        local item = registry.items[itemId]
        local cooksInto = item.food and item.food.cooksInto
        if cooksInto then
            local cookedPath = joinPath("items." .. itemId, "food.cooksInto")
            local cooked = registry.items[cooksInto]
            if not cooked then
                context:Error(cookedPath, "references unknown item '" .. cooksInto .. "'")
            elseif not cooked.food or cooked.food.preparation ~= "cooked" then
                context:Error(cookedPath, "must reference a cooked food item")
            elseif cooked.food.tier < item.food.tier then
                context:Error(cookedPath, "cooking must not lower the food tier (" .. item.food.tier .. " to " .. cooked.food.tier .. ")")
            end
        end
        if item.type == "bullet_weapon" then
            if not item.ammoId then
                context:Error(joinPath("items." .. itemId, "ammoId"), "is required for bullet weapons")
            else
                local ammo = registry.items[item.ammoId]
                if not ammo then
                    context:Error(joinPath("items." .. itemId, "ammoId"), "references unknown ammo item '" .. item.ammoId .. "'")
                elseif ammo.entityClass ~= "generic" or ammo.maxStack <= 1 then
                    context:Error(joinPath("items." .. itemId, "ammoId"), "must reference a stackable generic ammo item")
                end
            end
            if not item.firingMode then
                context:Error(joinPath("items." .. itemId, "firingMode"), "is required for bullet weapons")
            end
        end
    end
    local ammoIds = {}
    for _, item in pairs(registry.items) do
        if item.ammoId then ammoIds[item.ammoId] = true end
    end
    for _, item in pairs(registry.items) do
        item.lootCategory = deriveLootCategory(item, ammoIds)
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
                    context:Error(classPath, "must be prop_physics, prop_physics_multiplayer, prop_dynamic, or prop_ragdoll")
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

// Professions: a stored job name resolves through ids and aliases to one definition. Civilian must exist and is
// the fallback for unknown jobs. Stat bonuses are derived at runtime and never persisted.
StaticData.ProfessionServices = { cook = true, treat = true, research = true, implant = true, extract = true }
StaticData.DefaultProfession = "Civilian"
StaticData.MaximumProfessionBonus = 5
StaticData.MaximumProfessionBonusTotal = 6
StaticData.MaximumDeliveryItems = 8
local professionFields = { name = true, description = true, aliases = true, statBonuses = true, services = true, deliveries = true }
local deliveryTierFields = { minLevel = true, items = true }
local deliveryItemFields = { item = true, min = true, max = true }
local professionIdPattern = "^%u%a*$"

local function validateDeliveries(context, raw, path, registry)
    local tiers = {}
    if raw == nil then
        return tiers
    end
    if not isArray(raw) then
        context:Error(path, "must be an array of { minLevel, items } tiers")
        return tiers
    end
    local previousLevel = 0
    for index, rawTier in ipairs(raw) do
        local tierPath = path .. "[" .. index .. "]"
        if not isObject(rawTier) then
            context:Error(tierPath, "must be an object with minLevel and items")
        else
            checkFields(context, rawTier, deliveryTierFields, nil, tierPath)
            local tier = { items = {} }
            tier.minLevel = readNumber(context, rawTier, "minLevel", tierPath, { integer = true, min = 1, max = StaticData.MaximumItemLevel, required = true })
            if tier.minLevel then
                if index == 1 and tier.minLevel ~= 1 then
                    context:Error(joinPath(tierPath, "minLevel"), "the first delivery tier must start at level 1")
                elseif tier.minLevel <= previousLevel then
                    context:Error(joinPath(tierPath, "minLevel"), "delivery tiers must be in ascending minLevel order")
                end
                previousLevel = tier.minLevel
            end
            local itemsPath = joinPath(tierPath, "items")
            if not isArray(rawTier.items) or #rawTier.items == 0 then
                context:Error(itemsPath, "must be a non-empty array of { item, min, max } entries")
            elseif #rawTier.items > StaticData.MaximumDeliveryItems then
                context:Error(itemsPath, "may list at most " .. StaticData.MaximumDeliveryItems .. " entries")
            else
                local seen = {}
                for itemIndex, entry in ipairs(rawTier.items) do
                    local entryPath = itemsPath .. "[" .. itemIndex .. "]"
                    if not isObject(entry) then
                        context:Error(entryPath, "must be an object with item, min, and max")
                    else
                        checkFields(context, entry, deliveryItemFields, nil, entryPath)
                        local itemId = readString(context, entry, "item", entryPath, { required = true })
                        local item = itemId and registry.items[itemId]
                        local minimum = readNumber(context, entry, "min", entryPath, { integer = true, min = 1, max = 1000, required = true })
                        local maximum = readNumber(context, entry, "max", entryPath, { integer = true, min = 1, max = 1000, default = minimum })
                        if itemId and not item then
                            context:Error(joinPath(entryPath, "item"), "references unknown item '" .. itemId .. "'")
                        elseif item and item.entityClass == "weapon" then
                            context:Error(joinPath(entryPath, "item"), "weapons cannot be daily deliveries")
                        elseif item and seen[itemId] then
                            context:Error(joinPath(entryPath, "item"), "lists '" .. itemId .. "' more than once")
                        elseif minimum and maximum and maximum < minimum then
                            context:Error(joinPath(entryPath, "max"), "must not be below min")
                        elseif item and minimum and maximum then
                            seen[itemId] = true
                            table.insert(tier.items, { item = itemId, min = minimum, max = maximum })
                        end
                    end
                end
            end
            table.insert(tiers, tier)
        end
    end
    return tiers
end

local function validateProfession(context, professionId, raw, registry)
    local path = "professions." .. tostring(professionId)
    if not string.match(professionId, professionIdPattern) or #professionId > 32 then
        context:Error(path, "profession ids must be PascalCase letters only (at most 32)")
        return nil
    end
    if not isObject(raw) then
        context:Error(path, "must be an object")
        return nil
    end
    checkFields(context, raw, professionFields, nil, path)
    local profession = { id = professionId, aliases = {}, statBonuses = {}, services = {} }
    profession.name = readString(context, raw, "name", path, { required = true })
    profession.description = readString(context, raw, "description", path, { default = "" })

    if raw.aliases ~= nil then
        if not isArray(raw.aliases) then
            context:Error(joinPath(path, "aliases"), "must be an array of alternative job names")
        else
            for index, alias in ipairs(raw.aliases) do
                if type(alias) ~= "string" or not string.match(alias, professionIdPattern) or #alias > 32 then
                    context:Error(joinPath(path, "aliases") .. "[" .. index .. "]", "must be a PascalCase job name")
                else
                    table.insert(profession.aliases, alias)
                end
            end
        end
    end

    if raw.statBonuses ~= nil then
        local bonusesPath = joinPath(path, "statBonuses")
        if not isObject(raw.statBonuses) then
            context:Error(bonusesPath, "must be an object of attribute name to bonus points")
        else
            local total = 0
            for _, attribute in ipairs(sortedKeys(raw.statBonuses)) do
                if not StaticData.PlayerAttributes[attribute] then
                    context:Error(joinPath(bonusesPath, attribute), "is not a player attribute")
                else
                    local bonus = readNumber(context, raw.statBonuses, attribute, bonusesPath, { integer = true, min = 1, max = StaticData.MaximumProfessionBonus, required = true })
                    if bonus then
                        profession.statBonuses[attribute] = bonus
                        total = total + bonus
                    end
                end
            end
            if total > StaticData.MaximumProfessionBonusTotal then
                context:Error(bonusesPath, "bonuses total " .. total .. "; at most " .. StaticData.MaximumProfessionBonusTotal .. " points are allowed")
            end
        end
    end

    if raw.services ~= nil then
        if not isArray(raw.services) then
            context:Error(joinPath(path, "services"), "must be an array of service names")
        else
            for index, service in ipairs(raw.services) do
                if type(service) ~= "string" or not StaticData.ProfessionServices[service] then
                    context:Error(joinPath(path, "services") .. "[" .. index .. "]", "must be one of " .. table.concat(sortedKeys(StaticData.ProfessionServices), ", "))
                else
                    profession.services[service] = true
                end
            end
        end
    end

    profession.deliveries = validateDeliveries(context, raw.deliveries, joinPath(path, "deliveries"), registry)
    return profession
end

local function validateProfessions(report, registry)
    local data, context = readJsonFile(report, "professions")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, professionVersion = true, professions = true }, nil, "")
    registry.professionVersion = readNumber(context, data, "professionVersion", "", { integer = true, min = 1, required = true })
    if not isObject(data.professions) then
        context:Error("professions", "must be an object keyed by profession id")
        return
    end
    for _, professionId in ipairs(sortedKeys(data.professions)) do
        local profession = validateProfession(context, professionId, data.professions[professionId], registry)
        if profession then
            registry.professions[professionId] = profession
        end
    end
    for _, professionId in ipairs(sortedKeys(registry.professions)) do
        for index, alias in ipairs(registry.professions[professionId].aliases) do
            local aliasPath = "professions." .. professionId .. ".aliases[" .. index .. "]"
            if registry.professions[alias] then
                context:Error(aliasPath, "'" .. alias .. "' is already a profession id")
            elseif registry.professionAliases[alias] then
                context:Error(aliasPath, "'" .. alias .. "' is already an alias of " .. registry.professionAliases[alias])
            else
                registry.professionAliases[alias] = professionId
            end
        end
    end
    local default = registry.professions[StaticData.DefaultProfession]
    if not default then
        context:Error("professions", "must define the " .. StaticData.DefaultProfession .. " fallback profession")
    elseif next(default.statBonuses) or next(default.services) then
        context:Error("professions." .. StaticData.DefaultProfession, "the fallback profession must not grant bonuses or services")
    end
end

// Credit-priced den services at the Mastercrafting Station. Credits are whole numbers from 0 to MaximumCredits.
StaticData.MaximumCredits = 1000000
StaticData.MastercraftStation = "zn_mastercraft_station"

local function validateDenServices(report, registry)
    local data, context = readJsonFile(report, "denServices")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, denServiceVersion = true, mastercraft = true, jobChange = true }, nil, "")
    registry.denServiceVersion = readNumber(context, data, "denServiceVersion", "", { integer = true, min = 1, required = true })
    local services = {}
    if not isObject(data.mastercraft) then
        context:Error("mastercraft", "must be an object with baseCredits, creditsPerLevel, and ultraChance")
    else
        checkFields(context, data.mastercraft, { baseCredits = true, creditsPerLevel = true, ultraChance = true }, nil, "mastercraft")
        services.mastercraft = {
            baseCredits = readNumber(context, data.mastercraft, "baseCredits", "mastercraft", { integer = true, min = 0, max = 100000, required = true }),
            creditsPerLevel = readNumber(context, data.mastercraft, "creditsPerLevel", "mastercraft", { min = 0, max = 1000, required = true }),
            ultraChance = readNumber(context, data.mastercraft, "ultraChance", "mastercraft", { min = 0, max = 0.25, required = true })
        }
        if services.mastercraft.baseCredits == 0 and services.mastercraft.creditsPerLevel == 0 then
            context:Error("mastercraft", "must cost at least 1 credit (baseCredits or creditsPerLevel above 0)")
        end
    end
    if not isObject(data.jobChange) then
        context:Error("jobChange", "must be an object with credits")
    else
        checkFields(context, data.jobChange, { credits = true }, nil, "jobChange")
        services.jobChange = { credits = readNumber(context, data.jobChange, "credits", "jobChange", { integer = true, min = 1, max = 100000, required = true }) }
    end
    registry.denServices = services
end

// Credits for one mastercraft attempt on an item instance level: baseCredits + ceil(level * creditsPerLevel).
function StaticData:GetMastercraftCost(level)
    local mastercraft = self.Registry and self.Registry.denServices and self.Registry.denServices.mastercraft
    if not mastercraft then return nil end
    return mastercraft.baseCredits + math.ceil((tonumber(level) or 1) * mastercraft.creditsPerLevel)
end

function StaticData:GetDenServices()
    return self.Registry and self.Registry.denServices or nil
end

// Offline den trading: predefined trader stock tables, price multipliers, limits, and den NPC service fees.
// Traders are placed as zn_den_npc entities whose trader keyvalue names a table here.
StaticData.DenNpcClass = "zn_den_npc"
StaticData.MaximumTraderOffers = 32
StaticData.MaximumNpcServiceFee = 100000
StaticData.UnsellableCategories = { cash = true, implants = true }
local tradeFields = { schemaVersion = true, tradeVersion = true, buyMultiplier = true, sellMultiplier = true, maximumPurchaseUnits = true, dailySaleCashLimit = true, npcServiceFees = true, essentialAmmo = true, traders = true }
local traderFields = { name = true, buys = true, essentialAmmo = true, offers = true }
local offerFields = { item = true, bundle = true, minStock = true, maxStock = true, minDanger = true, maxDanger = true, credits = true, mastercraft = true }

local function validateTraderOffer(context, raw, path, registry)
    if not isObject(raw) then
        context:Error(path, "must be an object with item, minStock, and maxStock")
        return nil
    end
    checkFields(context, raw, offerFields, nil, path)
    local itemId = readString(context, raw, "item", path, { required = true })
    local item = itemId and registry.items[itemId]
    if itemId and not item then
        context:Error(joinPath(path, "item"), "references unknown item '" .. itemId .. "'")
        return nil
    end
    if not item then return nil end
    local offer = { item = itemId }
    offer.bundle = readNumber(context, raw, "bundle", path, { integer = true, min = 1, max = item.maxStack, default = 1 })
    offer.minStock = readNumber(context, raw, "minStock", path, { integer = true, min = 0, max = 100, required = true })
    offer.maxStock = readNumber(context, raw, "maxStock", path, { integer = true, min = 1, max = 100, required = true })
    offer.minDanger = readNumber(context, raw, "minDanger", path, { min = 0, max = 1, default = 0 })
    offer.maxDanger = readNumber(context, raw, "maxDanger", path, { min = 0, max = 1, default = 1 })
    offer.credits = readNumber(context, raw, "credits", path, { integer = true, min = 1, max = 100000 })
    offer.mastercraft = readBoolean(context, raw, "mastercraft", path, false)
    if offer.minStock and offer.maxStock and offer.maxStock < offer.minStock then
        context:Error(joinPath(path, "maxStock"), "must not be below minStock")
    end
    if offer.minDanger and offer.maxDanger and offer.maxDanger < offer.minDanger then
        context:Error(joinPath(path, "maxDanger"), "must not be below minDanger")
    end
    if item.lootCategory == "cash" then
        context:Error(joinPath(path, "item"), "cash cannot be sold by a trader")
    end
    if offer.mastercraft and not item.attributes then
        context:Error(joinPath(path, "mastercraft"), "only items with a weapon type can be offered as mastercrafts")
    end
    if (offer.mastercraft or item.lootCategory == "implants") and not offer.credits then
        context:Error(joinPath(path, "credits"), "is required: mastercrafts and implants are priced in credits")
    end
    if not offer.credits and (item.value or 0) <= 0 then
        context:Error(joinPath(path, "item"), "has no value, so it has no cash price")
    end
    return offer
end

local function validateTrader(context, traderId, raw, registry)
    local path = "traders." .. tostring(traderId)
    if not string.match(traderId, idPattern) or #traderId > 32 then
        context:Error(path, "trader ids must be camelCase letters and digits (at most 32)")
        return nil
    end
    if not isObject(raw) then
        context:Error(path, "must be an object with name, buys, and offers")
        return nil
    end
    checkFields(context, raw, traderFields, nil, path)
    local trader = { id = traderId, buys = {}, buysList = {}, offers = {} }
    trader.name = readString(context, raw, "name", path, { required = true })
    trader.essentialAmmo = readBoolean(context, raw, "essentialAmmo", path, false)
    if raw.buys ~= nil then
        if not isArray(raw.buys) then
            context:Error(joinPath(path, "buys"), "must be an array of loot categories")
        else
            for index, category in ipairs(raw.buys) do
                local entryPath = joinPath(path, "buys") .. "[" .. index .. "]"
                if type(category) ~= "string" or not StaticData.LootCategories[category] then
                    context:Error(entryPath, "must be one of " .. table.concat(sortedKeys(StaticData.LootCategories), ", "))
                elseif StaticData.UnsellableCategories[category] then
                    context:Error(entryPath, "traders cannot buy " .. category)
                elseif not trader.buys[category] then
                    trader.buys[category] = true
                    table.insert(trader.buysList, category)
                end
            end
        end
    end
    local offersPath = joinPath(path, "offers")
    if not isArray(raw.offers) then
        context:Error(offersPath, "must be an array of offers")
    elseif #raw.offers > StaticData.MaximumTraderOffers then
        context:Error(offersPath, "may list at most " .. StaticData.MaximumTraderOffers .. " offers")
    else
        for index, rawOffer in ipairs(raw.offers) do
            local offer = validateTraderOffer(context, rawOffer, offersPath .. "[" .. index .. "]", registry)
            if offer then
                offer.key = tostring(index)
                table.insert(trader.offers, offer)
            end
        end
    end
    if #trader.offers == 0 and not trader.essentialAmmo and #trader.buysList == 0 then
        context:Error(path, "neither sells nor buys anything")
    end
    return trader
end

local function validateTrade(report, registry)
    local data, context = readJsonFile(report, "trade")
    if not data then
        return
    end
    checkFields(context, data, tradeFields, nil, "")
    registry.tradeVersion = readNumber(context, data, "tradeVersion", "", { integer = true, min = 1, required = true })
    local trade = { traders = {}, npcServiceFees = {} }
    trade.buyMultiplier = readNumber(context, data, "buyMultiplier", "", { min = 1, max = 10, required = true })
    trade.sellMultiplier = readNumber(context, data, "sellMultiplier", "", { min = 0.01, max = 1, required = true })
    trade.maximumPurchaseUnits = readNumber(context, data, "maximumPurchaseUnits", "", { integer = true, min = 1, max = 100, required = true })
    trade.dailySaleCashLimit = readNumber(context, data, "dailySaleCashLimit", "", { integer = true, min = 1, max = StaticData.MaximumCredits, required = true })
    if trade.buyMultiplier and trade.sellMultiplier and trade.sellMultiplier >= trade.buyMultiplier then
        context:Error("sellMultiplier", "must be below buyMultiplier, or buying and selling back would make cash")
    end

    if data.npcServiceFees ~= nil then
        if not isObject(data.npcServiceFees) then
            context:Error("npcServiceFees", "must be an object of service name to cash fee")
        else
            for _, service in ipairs(sortedKeys(data.npcServiceFees)) do
                if not StaticData.ProfessionServices[service] then
                    context:Error(joinPath("npcServiceFees", service), "must be one of " .. table.concat(sortedKeys(StaticData.ProfessionServices), ", "))
                else
                    trade.npcServiceFees[service] = readNumber(context, data.npcServiceFees, service, "npcServiceFees", { integer = true, min = 0, max = StaticData.MaximumNpcServiceFee, required = true })
                end
            end
        end
    end

    trade.essentialAmmo = { items = {}, bundle = 1, stock = 0 }
    if data.essentialAmmo ~= nil then
        if not isObject(data.essentialAmmo) then
            context:Error("essentialAmmo", "must be an object with items, bundle, and stock")
        else
            checkFields(context, data.essentialAmmo, { items = true, bundle = true, stock = true }, nil, "essentialAmmo")
            local ammoIds = {}
            for _, item in pairs(registry.items) do
                if item.ammoId then ammoIds[item.ammoId] = true end
            end
            local items = readIdList(context, data.essentialAmmo, "items", "essentialAmmo", registry.items, "item", true)
            for index, itemId in ipairs(items) do
                if not ammoIds[itemId] then
                    context:Error("essentialAmmo.items[" .. index .. "]", "'" .. itemId .. "' is not ammunition used by any weapon")
                else
                    table.insert(trade.essentialAmmo.items, itemId)
                end
            end
            local smallestStack
            for _, itemId in ipairs(trade.essentialAmmo.items) do
                smallestStack = math.min(smallestStack or math.huge, registry.items[itemId].maxStack)
            end
            trade.essentialAmmo.bundle = readNumber(context, data.essentialAmmo, "bundle", "essentialAmmo", { integer = true, min = 1, max = smallestStack or 1000, required = true })
            trade.essentialAmmo.stock = readNumber(context, data.essentialAmmo, "stock", "essentialAmmo", { integer = true, min = 1, max = 100, required = true })
        end
    end

    if not isObject(data.traders) then
        context:Error("traders", "must be an object keyed by trader id")
    else
        for _, traderId in ipairs(sortedKeys(data.traders)) do
            local trader = validateTrader(context, traderId, data.traders[traderId], registry)
            if trader then
                if trader.essentialAmmo and #trade.essentialAmmo.items == 0 then
                    context:Error("traders." .. traderId .. ".essentialAmmo", "needs essentialAmmo.items at the top level")
                end
                trade.traders[traderId] = trader
            end
        end
    end
    registry.trade = trade
end

function StaticData:GetTrade()
    return self.Registry and self.Registry.trade or nil
end

function StaticData:GetTrader(traderId)
    local trade = self:GetTrade()
    return trade and type(traderId) == "string" and trade.traders[traderId] or nil
end

// Crafting stations: a recipe's station tag names the scripted entity class that provides it.
StaticData.CraftingStations = { workbench = "zn_crafting_station" }
StaticData.RecipeCategories = { Food = true, Medical = true, Ammunition = true, Materials = true, Weapons = true }
StaticData.RecipeFreshness = { new = true, inherit = true }
StaticData.MaximumRecipeIngredients = 8
StaticData.MaximumRecipeResults = 4
local recipeFields = {
    name = true, category = true, station = true, craftTime = true, levelRequirement = true,
    statRequirements = true, jobs = true, ingredients = true, results = true, freshness = true, service = true
}
local recipeRenamedFields = {
    duration = "was renamed to craftTime",
    requiredLevel = "was renamed to levelRequirement",
    mastercraft = "is not a recipe field; mastercrafting is a separate den service"
}
local recipeStackFields = { item = true, count = true }

// Reads an ingredient or result list of { item, count } entries.
local function readRecipeStacks(context, raw, key, path, registry, maximum, isResult)
    local stacks = {}
    local listPath = joinPath(path, key)
    local list = raw[key]
    if not isArray(list) or #list == 0 then
        context:Error(listPath, "must be a non-empty array of { item, count } entries")
        return stacks
    end
    if #list > maximum then
        context:Error(listPath, "may list at most " .. maximum .. " entries")
    end
    local seen = {}
    for index, entry in ipairs(list) do
        local entryPath = listPath .. "[" .. index .. "]"
        if not isObject(entry) then
            context:Error(entryPath, "must be an object with item and count")
        else
            local renamed = isResult and { mastercraft = "mastercraft results are not craftable; mastercrafting is a separate den service" } or nil
            checkFields(context, entry, recipeStackFields, renamed, entryPath)
            local itemId = readString(context, entry, "item", entryPath, { required = true })
            local item = itemId and registry.items[itemId]
            if itemId and not item then
                context:Error(joinPath(entryPath, "item"), "references unknown item '" .. itemId .. "'")
            end
            local count = readNumber(context, entry, "count", entryPath, { integer = true, min = 1, max = 1000, required = true })
            if item and count then
                if seen[itemId] then
                    context:Error(joinPath(entryPath, "item"), "lists '" .. itemId .. "' more than once")
                elseif item.entityClass == "weapon" and not isResult then
                    context:Error(joinPath(entryPath, "item"), "weapons cannot be ingredients; recipes consume stackable items only")
                elseif item.entityClass == "weapon" and count ~= 1 then
                    context:Error(joinPath(entryPath, "count"), "weapon results must have a count of 1")
                else
                    seen[itemId] = true
                    table.insert(stacks, { item = itemId, count = count })
                end
            end
        end
    end
    return stacks
end

local function validateRecipe(context, recipeId, raw, registry)
    local path = "recipes." .. tostring(recipeId)
    if not string.match(recipeId, "^recipe%u%w*$") then
        context:Error(path, "recipe ids must be camelCase and start with 'recipe'")
        return nil
    end
    if not isObject(raw) then
        context:Error(path, "must be an object")
        return nil
    end
    checkFields(context, raw, recipeFields, recipeRenamedFields, path)
    local recipe = { id = recipeId }
    recipe.name = readString(context, raw, "name", path, { required = true })
    recipe.category = readString(context, raw, "category", path, { required = true })
    if recipe.category and not StaticData.RecipeCategories[recipe.category] then
        context:Error(joinPath(path, "category"), "must be one of " .. table.concat(sortedKeys(StaticData.RecipeCategories), ", "))
    end
    recipe.service = readBoolean(context, raw, "service", path, false)
    // Service recipes are made by a professional through the Services flow, so they have no station.
    recipe.station = readString(context, raw, "station", path, { required = not recipe.service })
    if recipe.station and recipe.service then
        context:Error(joinPath(path, "station"), "service recipes are made by a professional, not at a station")
    elseif recipe.station and not StaticData.CraftingStations[recipe.station] then
        context:Error(joinPath(path, "station"), "must be a crafting station tag (" .. table.concat(sortedKeys(StaticData.CraftingStations), ", ") .. "); free-world crafting is not supported")
    end
    recipe.craftTime = readNumber(context, raw, "craftTime", path, { min = 0.5, max = 600, required = true })
    recipe.levelRequirement = readNumber(context, raw, "levelRequirement", path, { integer = true, min = 1, max = StaticData.MaximumItemLevel, default = 1 })

    recipe.statRequirements = {}
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
                    recipe.statRequirements[attribute] = readNumber(context, raw.statRequirements, attribute, requirementsPath, { integer = true, min = 1, required = true })
                end
            end
        end
    end

    if raw.jobs ~= nil then
        recipe.jobs = {}
        local jobsPath = joinPath(path, "jobs")
        if not isArray(raw.jobs) or #raw.jobs == 0 then
            context:Error(jobsPath, "must be a non-empty array of job names (omit it for any job)")
        else
            for index, job in ipairs(raw.jobs) do
                local profession = type(job) == "string" and registry.professions[job]
                if not profession then
                    context:Error(jobsPath .. "[" .. index .. "]", "is not a known profession id (" .. table.concat(sortedKeys(registry.professions), ", ") .. ")")
                elseif recipe.service and not profession.services.research then
                    context:Error(jobsPath .. "[" .. index .. "]", "'" .. job .. "' does not offer the research service")
                else
                    recipe.jobs[job] = true
                end
            end
        end
    elseif recipe.service then
        context:Error(joinPath(path, "jobs"), "is required for service recipes (the professions who research it)")
    end

    recipe.ingredients = readRecipeStacks(context, raw, "ingredients", path, registry, StaticData.MaximumRecipeIngredients, false)
    recipe.results = readRecipeStacks(context, raw, "results", path, registry, StaticData.MaximumRecipeResults, true)
    local ingredientIds, hasFoodIngredient, hasFoodResult = {}, false, false
    for _, stack in ipairs(recipe.ingredients) do
        ingredientIds[stack.item] = true
        if registry.items[stack.item].food then hasFoodIngredient = true end
    end
    for index, stack in ipairs(recipe.results) do
        if ingredientIds[stack.item] then
            context:Error(joinPath(path, "results") .. "[" .. index .. "].item", "'" .. stack.item .. "' is also an ingredient; a recipe cannot produce its own input")
        end
        if registry.items[stack.item].food then hasFoodResult = true end
    end

    // Food results must say how their freshness is decided: brand new, or the count-weighted freshness of food inputs.
    if hasFoodResult then
        recipe.freshness = readString(context, raw, "freshness", path, { required = true })
        if recipe.freshness and not StaticData.RecipeFreshness[recipe.freshness] then
            context:Error(joinPath(path, "freshness"), "must be new or inherit")
        elseif recipe.freshness == "inherit" and not hasFoodIngredient then
            context:Error(joinPath(path, "freshness"), "inherit needs at least one food ingredient")
        end
    elseif raw.freshness ~= nil then
        context:Error(joinPath(path, "freshness"), "only applies to recipes that produce food")
    end
    return recipe
end

local function validateRecipes(report, registry)
    local data, context = readJsonFile(report, "recipes")
    if not data then
        return
    end
    checkFields(context, data, { schemaVersion = true, recipeVersion = true, recipes = true }, nil, "")
    registry.recipeVersion = readNumber(context, data, "recipeVersion", "", { integer = true, min = 1, required = true })
    if not isObject(data.recipes) then
        context:Error("recipes", "must be an object keyed by recipe id")
        return
    end
    for _, recipeId in ipairs(sortedKeys(data.recipes)) do
        local recipe = validateRecipe(context, recipeId, data.recipes[recipeId], registry)
        if recipe then
            registry.recipes[recipeId] = recipe
        end
    end
end

local function validateMusic(report, registry)
    local data, context = readJsonFile(report, "music")
    if not data then return end
    checkFields(context, data, { schemaVersion = true, tracks = true, sets = true, defaultSet = true,
        idleSeconds = true, safeZones = true, environmentTags = true, tagPriority = true }, nil, "")
    local tags, zones = ZM_Music.RoutingKeys()
    local music, errors = ZM_Music.Validate(data, function(path) return file.Exists(path, "GAME") end, tags, zones)
    for _, issue in ipairs(errors) do context:Error(issue.path, issue.message) end
    registry.music = music
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
        recipes = {},
        recipeVersion = nil,
        professions = {},
        professionAliases = {},
        professionVersion = nil,
        denServices = nil,
        denServiceVersion = nil,
        trade = nil,
        tradeVersion = nil,
        loadedAt = os.time()
    }
    local internal = { lootPools = {}, enemySpawnWeights = {} }
    validateItems(report, registry)
    validateLoot(report, registry, internal)
    validateEntityLoot(report, registry, internal)
    validateEnemies(report, registry, internal)
    validateEnemySpawns(report, registry, internal)
    validateBosses(report, registry, internal)
    validateProfessions(report, registry)
    validateRecipes(report, registry)
    validateDenServices(report, registry)
    validateTrade(report, registry)
    validateMusic(report, registry)
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
    local implantCount = 0
    for _, item in pairs(registry.items) do
        if item.implant then implantCount = implantCount + 1 end
    end
    return string.format(
        "%d items (%d implants), %d loot groups, %d entity loot rules, %d enemies, %d spawn groups, %d bosses, %d recipes (v%s), %d professions (v%s), den services v%s, %d traders (v%s), %d music tracks",
        table.Count(registry.items), implantCount, table.Count(registry.lootGroups), #registry.entityLoot.rules,
        table.Count(registry.enemies), table.Count(registry.spawnGroups), table.Count(registry.bosses),
        table.Count(registry.recipes or {}), tostring(registry.recipeVersion),
        table.Count(registry.professions or {}), tostring(registry.professionVersion), tostring(registry.denServiceVersion),
        table.Count(registry.trade and registry.trade.traders or {}), tostring(registry.tradeVersion),
        table.Count(registry.music and registry.music.tracks or {})
    )
end

function StaticData:GetRecipe(recipeId)
    return self.Registry and self.Registry.recipes and self.Registry.recipes[recipeId] or nil
end

// Resolves a stored job name or alias to its profession definition; unknown names resolve to the fallback.
function StaticData:GetProfession(job)
    local registry = self.Registry
    if not registry or not registry.professions then
        return nil
    end
    local id = registry.professions[job] and job or registry.professionAliases[job] or self.DefaultProfession
    return registry.professions[id]
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
