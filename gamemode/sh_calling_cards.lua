ZM_CallingCards = ZM_CallingCards or {}
local CallingCards = ZM_CallingCards

local directories = { background = "backgrounds", detail = "details" }

local function isObject(value)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if type(key) ~= "string" then return false end end
    return true
end

local function isArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
        count = count + 1
    end
    return count == #value
end

local function idCategory(id)
    if type(id) ~= "string" or #id > 199 then return nil end
    local category, stem = string.match(id, "^(%l+)_(.+)$")
    if not directories[category] or not string.match(stem, "^[a-z0-9_]+$") or
        string.sub(stem, 1, 1) == "_" or string.sub(stem, -1) == "_" or string.find(stem, "__", 1, true) then
        return nil
    end
    return category
end

CallingCards.Category = idCategory

local function materialCategory(material)
    if type(material) ~= "string" then return nil end
    for category, directory in pairs(directories) do
        if string.match(material, "^scoreboard/" .. directory .. "/[a-z0-9][a-z0-9_ %-]*%.png$") then
            return category
        end
    end
    return nil
end

local function validDigest(entry)
    return type(entry.bytes) == "number" and entry.bytes == entry.bytes and entry.bytes > 0
        and entry.bytes < math.huge and entry.bytes == math.floor(entry.bytes)
        and type(entry.sha256) == "string" and #entry.sha256 == 64 and string.match(entry.sha256, "^[a-f0-9]+$") ~= nil
end

local function checkFields(value, allowed, path, fail)
    for key in pairs(value) do
        if not allowed[key] then fail(path .. "." .. tostring(key), "is not a recognised field") end
    end
end

function CallingCards.Validate(data, exists)
    local errors = {}
    local function fail(path, message) errors[#errors + 1] = { path = path, message = message } end
    if not isObject(data) then fail("", "must be an object") return nil, errors end
    if type(exists) ~= "function" then fail("", "requires a material existence check") return nil, errors end
    checkFields(data, { schemaVersion = true, cards = true, aliases = true, ownedFiles = true }, "", fail)
    if data.schemaVersion ~= 1 then fail("schemaVersion", "must be 1") end
    local catalogue = { byId = {}, byCategory = { background = {}, detail = {} }, aliases = {} }
    local materials, activeOwned = {}, {}
    if not isArray(data.cards) then
        fail("cards", "must be an array")
    else
        for index, card in ipairs(data.cards) do
            local path = "cards[" .. index .. "]"
            if not isObject(card) then
                fail(path, "must be an object")
            else
                checkFields(card, { id = true, name = true, category = true, source = true,
                    material = true, bytes = true, sha256 = true, shopCredits = true, questReward = true }, path, fail)
                local category = idCategory(card.id)
                if not category or card.category ~= category then fail(path .. ".id", "must be a stable ID matching its category") end
                if category and catalogue.byId[card.id] then fail(path .. ".id", "duplicates a card ID") end
                if type(card.name) ~= "string" or card.name == "" or #card.name > 480 or
                    string.match(card.name, "^%s*$") or string.find(card.name, "%c") then
                    fail(path .. ".name", "must be a nonempty display name")
                end
                local source = card.source
                if source ~= "builtin" and source ~= "finished" and source ~= "generated" then
                    fail(path .. ".source", "must be builtin, finished, or generated")
                end
                if card.shopCredits ~= nil and (source == "builtin" or type(card.shopCredits) ~= "number"
                    or card.shopCredits ~= card.shopCredits or card.shopCredits ~= math.floor(card.shopCredits)
                    or card.shopCredits < 1 or card.shopCredits > 1000000) then
                    fail(path .. ".shopCredits", "must be a non-default card price from 1 to 1000000 credits")
                end
                if source == "builtin" and card.questReward ~= nil then
                    fail(path .. ".questReward", "must be omitted for built-in defaults")
                elseif source ~= "builtin" and type(card.questReward) ~= "boolean" then
                    fail(path .. ".questReward", "must explicitly state quest reward eligibility")
                elseif source ~= "builtin" and not card.questReward and card.shopCredits == nil then
                    fail(path, "must have a shop price or allow quest rewards")
                end
                local materialValid = category and materialCategory(card.material) == category
                if not materialValid then
                    fail(path .. ".material", "must be a safe material path matching the category")
                else
                    if materials[card.material] then fail(path .. ".material", "duplicates a material path") end
                    materials[card.material] = true
                    if not exists("materials/" .. card.material) then fail(path .. ".material", "material file is missing") end
                end
                if not validDigest(card) then fail(path, "must have a positive byte count and lowercase SHA-256") end
                if category then
                    local defaultId = category .. "_default"
                    local defaultMaterial = "scoreboard/" .. directories[category] .. "/default.png"
                    if source == "builtin" then
                        if card.id ~= defaultId or card.material ~= defaultMaterial then fail(path, "invalid built-in default") end
                    elseif card.id == defaultId or card.material == defaultMaterial then
                        fail(path, "only the built-in may use the default ID or material")
                    elseif materialValid and source == "generated" and
                        card.material ~= "scoreboard/" .. directories[category] .. "/generated_" .. card.id .. ".png" then
                        fail(path .. ".material", "generated material must match its ID")
                    elseif materialValid and source == "finished" then
                        local suffix = category == "background" and "_background.png" or "_details.png"
                        if string.sub(card.material, -#suffix) ~= suffix then fail(path .. ".material", "has the wrong finished-card suffix") end
                    end
                    if not catalogue.byId[card.id] then
                        local entry = { id = card.id, name = card.name, category = category,
                            source = source, material = card.material, bytes = card.bytes, sha256 = card.sha256,
                            shopCredits = card.shopCredits, questReward = card.questReward }
                        catalogue.byId[card.id] = entry
                        table.insert(catalogue.byCategory[category], entry)
                    end
                    if source ~= "builtin" and materialValid then activeOwned[card.material] = card end
                end
            end
        end
    end
    for category in pairs(directories) do
        local default = catalogue.byId[category .. "_default"]
        if not default or default.source ~= "builtin" or default.material ~= "scoreboard/" .. directories[category] .. "/default.png" then
            fail("cards", "must contain the built-in " .. category .. " default")
        end
        table.sort(catalogue.byCategory[category], function(left, right) return left.id < right.id end)
    end
    local owned = {}
    if not isArray(data.ownedFiles) then
        fail("ownedFiles", "must be an array")
    else
        for index, entry in ipairs(data.ownedFiles) do
            local path = "ownedFiles[" .. index .. "]"
            if not isObject(entry) then
                fail(path, "must be an object")
            else
                checkFields(entry, { material = true, bytes = true, sha256 = true }, path, fail)
                local category = materialCategory(entry.material)
                if not category or entry.material == "scoreboard/" .. directories[category] .. "/default.png" then
                    fail(path .. ".material", "must be a safe non-default scoreboard path")
                elseif owned[entry.material] then
                    fail(path .. ".material", "duplicates an owned material")
                else
                    owned[entry.material] = entry
                end
                if not validDigest(entry) then fail(path, "must have a positive byte count and lowercase SHA-256") end
            end
        end
    end
    for material, card in pairs(activeOwned) do
        local entry = owned[material]
        if not entry or entry.sha256 ~= card.sha256 or entry.bytes ~= card.bytes then
            fail("ownedFiles", "does not match active material " .. material)
        end
    end
    if not isObject(data.aliases) then
        fail("aliases", "must be an object")
    else
        for from, target in pairs(data.aliases) do
            local category = idCategory(from)
            if not category or category ~= idCategory(target) or catalogue.byId[from] then
                fail("aliases." .. tostring(from), "must map an unused ID to the same category")
            else
                catalogue.aliases[from] = target
            end
        end
        for from in pairs(catalogue.aliases) do
            local seen, current = {}, from
            while catalogue.aliases[current] do
                if seen[current] then
                    fail("aliases." .. from, "contains a cycle")
                    current = nil
                    break
                end
                seen[current] = true
                current = catalogue.aliases[current]
            end
            if current and not catalogue.byId[current] then fail("aliases." .. from, "points to an unavailable card") end
        end
    end
    if #errors > 0 then return nil, errors end
    return catalogue, errors
end

// Missing selections use the default without changing the saved ID or ownership.
function CallingCards.Resolve(catalogue, id, category)
    if not directories[category] then return nil, "invalid_category" end
    if not catalogue or not catalogue.byId or not catalogue.aliases then return nil, "catalogue_unavailable" end
    local default = catalogue.byId[category .. "_default"]
    if not default then return nil, "catalogue_unavailable" end
    if id == nil or id == "" then return default, "default" end
    if idCategory(id) ~= category then return default, "missing" end
    local resolved, seen = id, {}
    while catalogue.aliases[resolved] do
        if seen[resolved] then return default, "invalid_alias" end
        seen[resolved] = true
        resolved = catalogue.aliases[resolved]
    end
    local card = catalogue.byId[resolved]
    if not card or card.category ~= category then return default, "missing" end
    return card, resolved ~= id and "alias" or "available"
end
