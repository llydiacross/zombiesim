return function(clothing, weapons, validModel, contract)
    local Config = {}
    local fields = { name = true, model = true, idle = true, weapon = true, range = true, shirt = true, pants = true,
        damage = true, fireInterval = true, spread = true }

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    function Config.Validate(input)
        if type(input) ~= "table" then return nil, "Guard settings must be a table." end
        for key in pairs(input) do
            if not fields[key] then return nil, "Guard settings contain an unsupported field: " .. tostring(key) end
        end
        if type(input.name) ~= "string" or not string.match(input.name, "%S") or #input.name > 64 then
            return nil, "Guard name must be non-empty text of at most 64 bytes."
        end
        if type(input.model) ~= "string" or not clothing.Models[string.lower(input.model)] or not validModel(input.model) then
            return nil, "Guard model must be an available clothing-compatible citizen."
        end
        if type(input.idle) ~= "string" or not string.match(input.idle, "%S") or #input.idle > 128 then
            return nil, "Guard idle animation must be a non-empty sequence name."
        end
        local weapon, problem = weapons.Resolve(input.weapon)
        if not weapon then return nil, problem end
        if not finite(input.range) or input.range <= 0 or input.range > weapon.range then
            return nil, "Guard range must be positive and no greater than the selected weapon's range."
        end
        local combatValid, combatError = contract.ValidateGuardCombat(input)
        if not combatValid then return nil, combatError end
        for _, garment in ipairs({ "shirt", "pants" }) do
            local id = input[garment]
            local finish = type(id) == "string" and clothing.Finishes[id] or nil
            if type(id) ~= "string" or (id ~= "" and (not finish or (finish.garment and finish.garment ~= garment))) then
                return nil, "Guard " .. garment .. " must be an available matching clothing finish."
            end
        end
        if input.damage ~= nil then weapon.damage = input.damage end
        if input.fireInterval ~= nil then weapon.delay = input.fireInterval end
        if input.spread ~= nil then weapon.spread = input.spread end
        return {
            name = input.name, model = input.model, idle = input.idle, weapon = weapon,
            range = input.range, shirt = input.shirt, pants = input.pants
        }
    end

    function Config.PrepareDocumentGuard(guard)
        if type(guard) ~= "table" then return nil, "Guard record is invalid." end
        local settings = {
            name = guard.name, model = guard.model, idle = guard.idle, weapon = guard.weapon,
            range = guard.range, shirt = guard.shirt, pants = guard.pants,
            damage = guard.damage, fireInterval = guard.fireInterval, spread = guard.spread
        }
        local valid, problem = Config.Validate(settings)
        if not valid then return nil, problem end
        return settings
    end

    function Config.ValidateDocument(document)
        if type(document) ~= "table" or type(document.guards) ~= "table" then
            return false, "Prefab guard records are unavailable."
        end
        for index, guard in ipairs(document.guards) do
            local valid, problem = Config.PrepareDocumentGuard(guard)
            if not valid then return false, "Prefab guard " .. index .. ": " .. tostring(problem) end
        end
        return true
    end

    function Config.FromHammer(values)
        if type(values) ~= "table" then return nil, "Hammer guard keyvalues are unavailable." end
        local input = {
            name = values.guard_name or "Guard",
            model = values.model or "models/player/group01/male_03.mdl",
            idle = values.idle or "idle_all_01",
            weapon = values.weapon or "pistol",
            shirt = values.shirt or "",
            pants = values.pants or ""
        }
        local numericFields = {
            { key = "range", field = "range", default = "1000" },
            { key = "damage", field = "damage" },
            { key = "fire_interval", field = "fireInterval" },
            { key = "spread", field = "spread" }
        }
        for _, entry in ipairs(numericFields) do
            local value = values[entry.key]
            if value == nil then value = entry.default end
            if value ~= nil and value ~= "" then
                if type(value) ~= "string" or tonumber(value) == nil then
                    return nil, "Hammer guard " .. entry.key .. " must be a number."
                end
                input[entry.field] = tonumber(value)
            elseif entry.default ~= nil then
                return nil, "Hammer guard " .. entry.key .. " is required."
            end
        end
        local valid, problem = Config.Validate(input)
        if not valid then return nil, problem end
        return input
    end
    return Config
end
