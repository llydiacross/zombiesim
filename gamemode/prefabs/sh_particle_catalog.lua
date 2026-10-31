return function(files, json, contract)
    local Catalog = {}
    local path = "data_static/prefab_particles.json"
    local fields = { id = true, label = true, particleFile = true, particleSystem = true, sound = true }

    local function safePath(value, prefix, extension)
        return type(value) == "string" and string.sub(value, 1, #prefix) == prefix
            and string.sub(value, -#extension) == extension and not string.find(value, "..", 1, true)
            and not string.find(value, "\\", 1, true) and not string.find(value, ":", 1, true)
    end

    function Catalog.Load()
        if Catalog.Definitions then return Catalog.Definitions end
        local text = files.Read(path, "GAME")
        local decoded = type(text) == "string" and json.JSONToTable(text) or nil
        if type(decoded) ~= "table" or decoded.schemaVersion ~= 1 or type(decoded.effects) ~= "table" then
            return nil, "The prefab particle catalog is missing or invalid."
        end
        for key in pairs(decoded) do
            if key ~= "schemaVersion" and key ~= "effects" then return nil, "The prefab particle catalog has unsupported fields." end
        end
        local count, maximum, result, ids = 0, 0, {}, {}
        for index, effect in pairs(decoded.effects) do
            if type(index) ~= "number" or index < 1 or index ~= math.floor(index) or type(effect) ~= "table" then
                return nil, "The prefab particle catalog must contain a contiguous list."
            end
            count, maximum = count + 1, math.max(maximum, index)
            for key in pairs(effect) do
                if not fields[key] then return nil, "Prefab particle catalog effect has unsupported fields." end
            end
            if not contract.IsValidId(effect.id) or ids[effect.id]
                or type(effect.label) ~= "string" or not string.match(effect.label, "%S")
                or not safePath(effect.particleFile, "particles/", ".pcf")
                or type(effect.particleSystem) ~= "string" or not string.match(effect.particleSystem, "^[%w_]+$")
                or not safePath(effect.sound, "ambient/", ".wav") then
                return nil, "Prefab particle catalog effect has invalid or duplicate values."
            end
            ids[effect.id] = true
            result[index] = {
                id = effect.id, label = effect.label, particleFile = effect.particleFile,
                particleSystem = effect.particleSystem, sound = effect.sound
            }
        end
        if count ~= maximum or count == 0 then return nil, "The prefab particle catalog must be a non-empty contiguous list." end
        Catalog.Definitions = result
        return result
    end

    function Catalog.Resolve(id)
        local definitions, problem = Catalog.Load()
        if not definitions then return nil, problem end
        for _, definition in ipairs(definitions) do
            if definition.id == id then return definition end
        end
        return nil, "Unknown prefab particle effect: " .. tostring(id)
    end

    function Catalog.Validate(document)
        for index, particle in ipairs(document.particles) do
            local _, problem = Catalog.Resolve(particle.effect)
            if problem then return false, "Prefab particle " .. index .. ": " .. problem end
        end
        return true
    end
    return Catalog
end
