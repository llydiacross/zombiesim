local Contract = {}

local function finiteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function fieldsMatch(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if not allowed[key] then return false end
    end
    return true
end

local function arrayLength(value)
    if type(value) ~= "table" then return nil end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return nil end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then return nil end
    return count
end

local documentFields = { schemaVersion = true, id = true, name = true, description = true, tags = true, props = true }
local propFields = { model = true, position = true, angles = true, skin = true, scale = true, movable = true,
    propId = true, lootMode = true, lootGroup = true, lootChance = true }
local positionFields = { x = true, y = true, z = true }
local angleFields = { p = true, y = true, r = true }
Contract.MinScale = 0.1
Contract.MaxScale = 10

function Contract.IsValidId(id)
    return type(id) == "string" and string.match(id, "^[a-z0-9][a-z0-9_%-]*$") ~= nil
end

function Contract.IsValidModelPath(model)
    return type(model) == "string" and string.match(string.lower(model), "^models/.+%.mdl$") ~= nil
        and not string.find(model, "..", 1, true) and not string.find(model, "\\", 1, true)
        and not string.find(model, ":", 1, true)
end

function Contract.Validate(document, validModel)
    if not fieldsMatch(document, documentFields) or document.schemaVersion ~= 1 then
        return nil, "Prefab must use schema version 1 and contain only supported fields."
    end
    if not Contract.IsValidId(document.id) then
        return nil, "Prefab ID must contain lowercase letters, numbers, underscores or hyphens."
    end
    if type(document.name) ~= "string" or not string.match(document.name, "%S") then
        return nil, "Prefab name cannot be empty."
    end
    if type(document.description) ~= "string" then
        return nil, "Prefab description must be text."
    end
    if type(validModel) ~= "function" then
        return nil, "Prefab model validation is unavailable."
    end
    local tagCount = arrayLength(document.tags)
    local propCount = arrayLength(document.props)
    if tagCount == nil or propCount == nil then
        return nil, "Prefab tags and props must be lists without gaps."
    end

    local result = {
        schemaVersion = 1, id = document.id, name = document.name,
        description = document.description, tags = {}, props = {}
    }
    local seenTags = {}
    for index = 1, tagCount do
        local tag = document.tags[index]
        if type(tag) ~= "string" or not string.match(tag, "%S") then
            return nil, "Prefab tags must be non-empty text."
        end
        local key = string.lower(tag)
        if seenTags[key] then return nil, "Prefab tags cannot be repeated." end
        seenTags[key] = true
        result.tags[index] = tag
    end

    local seenProps = {}
    for index = 1, propCount do
        local prop = document.props[index]
        local label = "Prefab prop " .. index
        if not fieldsMatch(prop, propFields) then return nil, label .. " has unsupported fields." end
        local model = prop.model
        if not Contract.IsValidModelPath(model) then
            return nil, label .. " has an invalid model path."
        end
        if not validModel(model) then return nil, label .. " uses an unavailable model: " .. model end
        if not fieldsMatch(prop.position, positionFields) or not fieldsMatch(prop.angles, angleFields)
            or not finiteNumber(prop.position.x) or not finiteNumber(prop.position.y) or not finiteNumber(prop.position.z)
            or not finiteNumber(prop.angles.p) or not finiteNumber(prop.angles.y) or not finiteNumber(prop.angles.r) then
            return nil, label .. " has invalid position or rotation values."
        end
        if not finiteNumber(prop.skin) or prop.skin < 0 or prop.skin ~= math.floor(prop.skin) then
            return nil, label .. " has an invalid skin."
        end
        local scale = prop.scale
        if scale == nil then scale = 1 end
        if not finiteNumber(scale) or scale < Contract.MinScale or scale > Contract.MaxScale then
            return nil, label .. " scale must be between 0.1 and 10."
        end
        local movable = prop.movable
        if movable == nil then movable = false end
        if type(movable) ~= "boolean" then return nil, label .. " movable must be a boolean." end
        local propId = prop.propId
        if propId == nil then propId = "legacy_" .. index end
        if not Contract.IsValidId(propId) or seenProps[propId] then
            return nil, label .. " must have a unique valid prop ID."
        end
        seenProps[propId] = true
        local lootMode = prop.lootMode
        if lootMode == nil then lootMode = "off" end
        if lootMode ~= "off" and lootMode ~= "normal" and lootMode ~= "guaranteed" then
            return nil, label .. " has an invalid loot mode."
        end
        local lootGroup = prop.lootGroup
        if lootGroup ~= nil and (type(lootGroup) ~= "string" or not string.match(lootGroup, "^[%w_]+$")) then
            return nil, label .. " has an invalid loot group ID."
        end
        local lootChance = prop.lootChance
        if lootChance ~= nil and (not finiteNumber(lootChance) or lootChance < 0 or lootChance > 1) then
            return nil, label .. " loot chance must be between 0 and 1."
        end
        result.props[index] = {
            model = model,
            position = { x = prop.position.x, y = prop.position.y, z = prop.position.z },
            angles = { p = prop.angles.p, y = prop.angles.y, r = prop.angles.r },
            skin = prop.skin,
            scale = scale,
            movable = movable,
            propId = propId,
            lootMode = lootMode,
            lootGroup = lootGroup,
            lootChance = lootChance
        }
    end
    return result
end

return Contract
