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

local documentFields = { schemaVersion = true, id = true, name = true, description = true, tags = true,
    props = true, lights = true, particles = true, guards = true, worldPlacement = true }
local propFields = { model = true, position = true, angles = true, skin = true, scale = true, movable = true,
    propId = true, lootMode = true, lootGroup = true, lootChance = true }
local lightFields = { lightId = true, position = true, angles = true, color = true,
    brightness = true, fov = true, range = true }
local particleFields = { particleId = true, effect = true, position = true, angles = true, mode = true, overlap = true }
local guardFields = { guardId = true, name = true, model = true, position = true, angles = true,
    idle = true, weapon = true, range = true, shirt = true, pants = true,
    damage = true, fireInterval = true, spread = true }
local positionFields = { x = true, y = true, z = true }
local angleFields = { p = true, y = true, r = true }
local colorFields = { r = true, g = true, b = true }
Contract.MinScale = 0.1
Contract.MaxScale = 10
Contract.MinGuardFireInterval = 0.05
Contract.SuggestedTags = { "roadDetail", "roadBlockade", "transitionGate", "road", "motorway", "burningCar", "burningBarrel" }

function Contract.GetTagSuggestions(documents)
    local result, seen = {}, {}
    local function add(tag)
        local key = string.lower(tag)
        if not seen[key] then seen[key] = true result[#result + 1] = tag end
    end
    for _, tag in ipairs(Contract.SuggestedTags) do add(tag) end
    for _, document in ipairs(documents or {}) do
        for _, tag in ipairs(document.tags) do add(tag) end
    end
    table.sort(result, function(a, b) return string.lower(a) < string.lower(b) end)
    return result
end

function Contract.ValidateWorldPlacement(value)
    if not fieldsMatch(value, { enabled = true, profile = true, cellX = true, cellY = true,
        tileX = true, tileY = true, offset = true, angles = true })
        or type(value.enabled) ~= "boolean" or (value.profile ~= "preview" and value.profile ~= "city") then
        return nil, "World placement requires an enabled flag and a preview or city profile."
    end
    for _, key in ipairs({ "cellX", "cellY", "tileX", "tileY" }) do
        if not finiteNumber(value[key]) or value[key] ~= math.floor(value[key]) then
            return nil, "World placement cell and tile coordinates must be whole numbers."
        end
    end
    if math.abs(value.tileX) > 2 or math.abs(value.tileY) > 2 then
        return nil, "World placement tile coordinates must be between -2 and 2."
    end
    if not fieldsMatch(value.offset, positionFields) or not fieldsMatch(value.angles, angleFields) then
        return nil, "World placement offset or rotation is invalid."
    end
    for _, key in ipairs({ "x", "y", "z" }) do
        if not finiteNumber(value.offset[key]) or math.abs(value.offset[key]) > 32768 then
            return nil, "World placement offsets must be finite and between -32768 and 32768."
        end
    end
    for _, key in ipairs({ "p", "y", "r" }) do
        if not finiteNumber(value.angles[key]) then return nil, "World placement rotation must be finite." end
    end
    return { enabled = value.enabled, profile = value.profile, cellX = value.cellX, cellY = value.cellY,
        tileX = value.tileX, tileY = value.tileY,
        offset = { x = value.offset.x, y = value.offset.y, z = value.offset.z },
        angles = { p = value.angles.p, y = value.angles.y, r = value.angles.r } }
end

function Contract.ValidateGuardCombat(guard)
    if type(guard) ~= "table" then return false, "Guard combat settings must be a table." end
    if guard.damage ~= nil and (not finiteNumber(guard.damage) or guard.damage <= 0) then
        return false, "Guard damage must be a positive finite number."
    end
    if guard.fireInterval ~= nil
        and (not finiteNumber(guard.fireInterval) or guard.fireInterval < Contract.MinGuardFireInterval) then
        return false, "Guard fire interval must be a finite number of at least "
            .. Contract.MinGuardFireInterval .. " seconds."
    end
    if guard.spread ~= nil and (not finiteNumber(guard.spread) or guard.spread < 0) then
        return false, "Guard shot spread must be a non-negative finite number."
    end
    return true
end

function Contract.IsValidId(id)
    return type(id) == "string" and string.match(id, "^[a-z0-9][a-z0-9_%-]*$") ~= nil
end

function Contract.IsValidModelPath(model)
    return type(model) == "string" and string.match(string.lower(model), "^models/.+%.mdl$") ~= nil
        and not string.find(model, "..", 1, true) and not string.find(model, "\\", 1, true)
        and not string.find(model, ":", 1, true)
end

function Contract.ValidateGuardWeaponChoices(choices)
    local count = arrayLength(choices)
    if not count then return nil, "Guard weapon choices must be a list." end
    local result = {}
    for index = 1, count do
        local weapon = choices[index]
        if type(weapon) ~= "table" or not Contract.IsValidId(weapon.id) or result[weapon.id]
            or type(weapon.label) ~= "string" or not string.match(weapon.label, "%S")
            or not Contract.IsValidModelPath(weapon.model)
            or not finiteNumber(weapon.range) or weapon.range <= 0
            or not finiteNumber(weapon.damage) or weapon.damage <= 0
            or not finiteNumber(weapon.delay) or weapon.delay < Contract.MinGuardFireInterval
            or not finiteNumber(weapon.spread) or weapon.spread < 0 then
            return nil, "Guard weapon choice " .. index .. " is invalid."
        end
        result[weapon.id] = weapon
    end
    if not result.pistol then return nil, "The default guard weapon is unavailable." end
    return result
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
    local lightCount = document.lights == nil and 0 or arrayLength(document.lights)
    local particleCount = document.particles == nil and 0 or arrayLength(document.particles)
    local guardCount = document.guards == nil and 0 or arrayLength(document.guards)
    if tagCount == nil or propCount == nil or lightCount == nil or particleCount == nil or guardCount == nil then
        return nil, "Prefab tags, props, lights, particles and guards must be lists without gaps."
    end

    local result = {
        schemaVersion = 1, id = document.id, name = document.name,
        description = document.description, tags = {}, props = {}, lights = {}, particles = {}, guards = {}
    }
    if document.worldPlacement ~= nil then
        local placement, problem = Contract.ValidateWorldPlacement(document.worldPlacement)
        if not placement then return nil, problem end
        result.worldPlacement = placement
    end
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
    local seenLights = {}
    for index = 1, lightCount do
        local light = document.lights[index]
        local label = "Prefab light " .. index
        if not fieldsMatch(light, lightFields) then return nil, label .. " has unsupported fields." end
        if not Contract.IsValidId(light.lightId) or seenLights[light.lightId] then
            return nil, label .. " must have a unique valid light ID."
        end
        seenLights[light.lightId] = true
        if not fieldsMatch(light.position, positionFields) or not fieldsMatch(light.angles, angleFields)
            or not finiteNumber(light.position.x) or not finiteNumber(light.position.y) or not finiteNumber(light.position.z)
            or not finiteNumber(light.angles.p) or not finiteNumber(light.angles.y) or not finiteNumber(light.angles.r) then
            return nil, label .. " has invalid position or rotation values."
        end
        if not fieldsMatch(light.color, colorFields) then return nil, label .. " has an invalid color." end
        for _, key in ipairs({ "r", "g", "b" }) do
            local component = light.color[key]
            if not finiteNumber(component) or component < 0 or component > 255 or component ~= math.floor(component) then
                return nil, label .. " color components must be integers between 0 and 255."
            end
        end
        if not finiteNumber(light.brightness) or light.brightness < 0 or light.brightness > 1000000
            or not finiteNumber(light.fov) or light.fov < 0.001 or light.fov > 179.999
            or not finiteNumber(light.range) or light.range < 8.001 or light.range > 1000000 then
            return nil, label .. " has invalid brightness, cone angle or range."
        end
        result.lights[index] = {
            lightId = light.lightId,
            position = { x = light.position.x, y = light.position.y, z = light.position.z },
            angles = { p = light.angles.p, y = light.angles.y, r = light.angles.r },
            color = { r = light.color.r, g = light.color.g, b = light.color.b },
            brightness = light.brightness, fov = light.fov, range = light.range
        }
    end
    local seenParticles = {}
    for index = 1, particleCount do
        local particle = document.particles[index]
        local label = "Prefab particle " .. index
        if not fieldsMatch(particle, particleFields) then return nil, label .. " has unsupported fields." end
        if not Contract.IsValidId(particle.particleId) or seenParticles[particle.particleId] then
            return nil, label .. " must have a unique valid particle ID."
        end
        seenParticles[particle.particleId] = true
        if not Contract.IsValidId(particle.effect) then return nil, label .. " has an invalid effect ID." end
        if not fieldsMatch(particle.position, positionFields) or not fieldsMatch(particle.angles, angleFields)
            or not finiteNumber(particle.position.x) or not finiteNumber(particle.position.y) or not finiteNumber(particle.position.z)
            or not finiteNumber(particle.angles.p) or not finiteNumber(particle.angles.y) or not finiteNumber(particle.angles.r) then
            return nil, label .. " has invalid position or rotation values."
        end
        if particle.mode ~= "continuous" and particle.mode ~= "triggered" then
            return nil, label .. " mode must be continuous or triggered."
        end
        local overlap = particle.overlap
        if overlap == nil then overlap = true end
        if type(overlap) ~= "boolean" then return nil, label .. " overlap must be a boolean." end
        result.particles[index] = {
            particleId = particle.particleId, effect = particle.effect,
            position = { x = particle.position.x, y = particle.position.y, z = particle.position.z },
            angles = { p = particle.angles.p, y = particle.angles.y, r = particle.angles.r },
            mode = particle.mode, overlap = overlap
        }
    end
    local seenGuards = {}
    for index = 1, guardCount do
        local guard = document.guards[index]
        local label = "Prefab guard " .. index
        if not fieldsMatch(guard, guardFields) then return nil, label .. " has unsupported fields." end
        if not Contract.IsValidId(guard.guardId) or seenGuards[guard.guardId] then
            return nil, label .. " must have a unique valid guard ID."
        end
        seenGuards[guard.guardId] = true
        if type(guard.name) ~= "string" or not string.match(guard.name, "%S") or #guard.name > 64 then
            return nil, label .. " has an invalid name."
        end
        if not Contract.IsValidModelPath(guard.model) or not validModel(guard.model) then
            return nil, label .. " uses an invalid or unavailable model."
        end
        if not fieldsMatch(guard.position, positionFields) or not fieldsMatch(guard.angles, angleFields)
            or not finiteNumber(guard.position.x) or not finiteNumber(guard.position.y) or not finiteNumber(guard.position.z)
            or not finiteNumber(guard.angles.p) or not finiteNumber(guard.angles.y) or not finiteNumber(guard.angles.r) then
            return nil, label .. " has invalid position or rotation values."
        end
        if type(guard.idle) ~= "string" or not string.match(guard.idle, "%S") or #guard.idle > 128
            or not Contract.IsValidId(guard.weapon) or not finiteNumber(guard.range) or guard.range <= 0
            or type(guard.shirt) ~= "string" or type(guard.pants) ~= "string" then
            return nil, label .. " has invalid animation, weapon, range or clothing settings."
        end
        local combatValid, combatError = Contract.ValidateGuardCombat(guard)
        if not combatValid then return nil, label .. ": " .. combatError end
        result.guards[index] = {
            guardId = guard.guardId, name = guard.name, model = guard.model,
            position = { x = guard.position.x, y = guard.position.y, z = guard.position.z },
            angles = { p = guard.angles.p, y = guard.angles.y, r = guard.angles.r },
            idle = guard.idle, weapon = guard.weapon, range = guard.range,
            shirt = guard.shirt, pants = guard.pants, damage = guard.damage,
            fireInterval = guard.fireInterval, spread = guard.spread
        }
    end
    return result
end

return Contract
