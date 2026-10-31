return function(files, json, contract, validModel, validateContent)
    local Catalog = {}
    local root = "data_static/prefabs"

    function Catalog.Load()
        local names = files.Find(root .. "/*.json", "GAME")
        if type(names) ~= "table" then return nil, "Could not list exported prefabs." end
        table.sort(names)
        local documents = {}
        for _, name in ipairs(names) do
            local id = string.match(name, "^(.*)%.json$")
            if not contract.IsValidId(id) then return nil, "Unexpected exported prefab filename: " .. tostring(name) end
            local text = files.Read(root .. "/" .. name, "GAME")
            if type(text) ~= "string" then return nil, "Could not read exported prefab '" .. id .. "'." end
            local input = json.JSONToTable(text)
            if type(input) ~= "table" then return nil, "Exported prefab '" .. id .. "' contains invalid JSON." end
            local document, problem = contract.Validate(input, validModel)
            if not document then return nil, "Exported prefab '" .. id .. "': " .. problem end
            if validateContent then
                local ok, contentError = validateContent(document)
                if not ok then return nil, "Exported prefab '" .. id .. "': " .. contentError end
            end
            if document.id ~= id then return nil, "Exported prefab ID does not match its filename: " .. id end
            documents[#documents + 1] = document
        end
        return documents
    end

    function Catalog.Select(documents, requestedTags, profile, worldSeed, cellId, anchorId)
        if type(documents) ~= "table" or type(requestedTags) ~= "table" or #requestedTags == 0 then
            return nil, "Prefab selection requires a catalog and at least one tag."
        end
        if type(profile) ~= "string" or profile == "" or type(worldSeed) ~= "number"
            or worldSeed ~= worldSeed or worldSeed == math.huge or worldSeed == -math.huge
            or type(cellId) ~= "number" or cellId < 0 or cellId ~= math.floor(cellId)
            or type(anchorId) ~= "number" or anchorId < 0 or anchorId ~= math.floor(anchorId) then
            return nil, "Prefab selection requires a valid profile, world seed, cell and map anchor."
        end
        for _, tag in ipairs(requestedTags) do
            if type(tag) ~= "string" or not string.match(tag, "%S") then
                return nil, "Prefab selection tags must be non-empty text."
            end
        end
        local matches = {}
        for _, document in ipairs(documents) do
            local available = {}
            for _, tag in ipairs(document.tags) do available[string.lower(tag)] = true end
            local matched = true
            for _, tag in ipairs(requestedTags) do
                if not available[string.lower(tag)] then matched = false break end
            end
            if matched and document.worldPlacement == nil then matches[#matches + 1] = document end
        end

        if #matches == 0 then return nil, "No exported prefab matches all requested tags." end
        table.sort(matches, function(a, b) return a.id < b.id end)
        local hash = tonumber(json.CRC(table.concat({ profile, worldSeed, cellId, anchorId }, "|")))
        if not hash then return nil, "Could not compute the deterministic prefab selection." end
        return matches[(hash % #matches) + 1]
    end

    function Catalog.ForWorldCell(documents, profile, cellX, cellY)
        local result = {}
        for _, document in ipairs(documents) do
            local placement = document.worldPlacement
            if placement and placement.enabled and placement.profile == profile
                and placement.cellX == cellX and placement.cellY == cellY then
                result[#result + 1] = document
            end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end

    return Catalog
end
