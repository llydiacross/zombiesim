return function(api)
    local Catalog = {}
    local choices, byId

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    local function loadChoices()
        if choices then return choices, byId end
        local text = api.file.Read("data_static/prefab_guard_weapons.json", "GAME")
        if type(text) ~= "string" then return nil, "Guard weapon catalogue is unavailable." end
        local decoded = api.util.JSONToTable(text)
        if type(decoded) ~= "table" then return nil, "Guard weapon catalogue contains invalid JSON." end
        local count, maximum = 0, 0
        for key in pairs(decoded) do
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
                return nil, "Guard weapon catalogue must be a list."
            end
            count, maximum = count + 1, math.max(maximum, key)
        end
        if count == 0 or count ~= maximum then return nil, "Guard weapon catalogue must be a non-empty list." end
        local allowed = { id = true, label = true, class = true, idle = true, attack = true }
        local indexed = {}
        for index = 1, count do
            local choice = decoded[index]
            if type(choice) ~= "table" then return nil, "Guard weapon choice " .. index .. " is invalid." end
            for key in pairs(choice) do
                if not allowed[key] then return nil, "Guard weapon choice " .. index .. " has unsupported fields." end
            end
            if type(choice.id) ~= "string" or not string.match(choice.id, "^[a-z0-9][a-z0-9_%-]*$")
                or indexed[choice.id] or type(choice.label) ~= "string" or not string.match(choice.label, "%S")
                or type(choice.class) ~= "string" or not string.match(choice.class, "^weapon_[%w_]+$")
                or type(choice.idle) ~= "string" or not string.match(choice.idle, "%S")
                or type(choice.attack) ~= "string" or not string.match(choice.attack, "%S") then
                return nil, "Guard weapon choice " .. index .. " is invalid."
            end
            indexed[choice.id] = choice
        end
        if not indexed.pistol then return nil, "The default guard weapon is unavailable." end
        choices, byId = decoded, indexed
        return choices, byId
    end

    function Catalog.Resolve(id)
        local ordered, indexed = loadChoices()
        if not ordered then return nil, indexed end
        local choice = indexed[id]
        if not choice then return nil, "Unknown guard weapon: " .. tostring(id) end
        local weapon = api.weapons.Get(choice.class)
        if type(weapon) ~= "table" then return nil, "Guard weapon is unavailable: " .. choice.class end
        if type(weapon.WorldModel) ~= "string" or not api.util.IsValidModel(weapon.WorldModel)
            or type(weapon.FireSound) ~= "string" or weapon.FireSound == ""
            or not finite(weapon.BulletDamage) or weapon.BulletDamage <= 0
            or not finite(weapon.BulletSpread) or weapon.BulletSpread < 0
            or not finite(weapon.BulletForce) or weapon.BulletForce < 0
            or not finite(weapon.BulletRange) or weapon.BulletRange <= 0
            or weapon.BulletCount ~= 1
            or not finite(weapon.FireDelay) or weapon.FireDelay <= 0 then
            return nil, "Guard weapon has missing or invalid firing data: " .. choice.class
        end
        return {
            id = choice.id, label = choice.label, class = choice.class,
            idle = choice.idle, attack = choice.attack, model = weapon.WorldModel, sound = weapon.FireSound,
            damage = weapon.BulletDamage, spread = weapon.BulletSpread, force = weapon.BulletForce,
            range = weapon.BulletRange, delay = weapon.FireDelay, tracer = 0
        }
    end

    function Catalog.List()
        local ordered, problem = loadChoices()
        if not ordered then return nil, problem end
        local result = {}
        for _, definition in ipairs(ordered) do
            local choice, choiceError = Catalog.Resolve(definition.id)
            if not choice then return nil, choiceError end
            result[#result + 1] = choice
        end
        return result
    end

    return Catalog
end
