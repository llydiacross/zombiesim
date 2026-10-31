return function(contract)
    local Map = {}

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    local function arrayLength(value)
        if type(value) ~= "table" then return nil end
        local count, maximum = 0, 0
        for key in pairs(value) do
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return nil end
            count, maximum = count + 1, math.max(maximum, key)
        end
        if count ~= maximum then return nil end
        return count
    end

    local function fieldsMatch(value, allowed)
        if type(value) ~= "table" then return false end
        for key in pairs(value) do if not allowed[key] then return false end end
        return true
    end

    function Map.IsValidName(name)
        return type(name) == "string" and #name <= 128
            and string.match(name, "^[a-zA-Z0-9][a-zA-Z0-9_%-]*$") ~= nil
    end

    function Map.IsReservedName(name)
        if not Map.IsValidName(name) then return true end
        local lower = string.lower(name)
        return lower == "zn_preview_start" or lower == "zn_city_start" or lower == "zn_dev_prefab_anchor"
            or string.match(lower, "^zz_preview_") ~= nil or string.match(lower, "^zz_city_") ~= nil
    end

    function Map.IsValidCellId(id)
        return finite(id) and id >= 0 and id == math.floor(id)
    end

    function Map.IsValidTile(value)
        return finite(value) and value == math.floor(value) and value >= -2 and value <= 2
    end

    function Map.ValidateRequest(request)
        if not fieldsMatch(request, { map = true, token = true, openIds = true, cellId = true })
            or not Map.IsValidName(request.map)
            or (request.cellId == nil and Map.IsReservedName(request.map))
            or (request.cellId ~= nil and not Map.IsValidCellId(request.cellId))
            or not contract.IsValidId(request.token) or #request.token > 64 then
            return false, "The editor map-switch request is invalid."
        end
        local count = arrayLength(request.openIds)
        if not count then return false, "The editor map-switch open IDs must be a list." end
        local seen = {}
        for index = 1, count do
            local id = request.openIds[index]
            if not contract.IsValidId(id) or seen[id] then return false, "An open prefab ID is invalid or duplicated." end
            seen[id] = true
        end
        return true
    end

    function Map.ValidateSnapshot(snapshot)
        if not fieldsMatch(snapshot, { schemaVersion = true, token = true, map = true, active = true, tabs = true,
                cellId = true })
            or snapshot.schemaVersion ~= 1 or not contract.IsValidId(snapshot.token) or #snapshot.token > 64
            or not Map.IsValidName(snapshot.map)
            or (snapshot.cellId == nil and Map.IsReservedName(snapshot.map))
            or (snapshot.cellId ~= nil and not Map.IsValidCellId(snapshot.cellId)) then
            return false, "The saved editor map-switch snapshot is invalid."
        end
        local count = arrayLength(snapshot.tabs)
        if not count or count < 1 or not finite(snapshot.active) or snapshot.active ~= math.floor(snapshot.active)
            or snapshot.active < 1 or snapshot.active > count then
            return false, "The saved editor tabs are invalid."
        end
        local numbers, opened = {}, {}
        for index = 1, count do
            local tab = snapshot.tabs[index]
            if not fieldsMatch(tab, { number = true, document = true, openedId = true, dirty = true,
                revision = true, selected = true, mode = true, view = true })
                or not finite(tab.number) or tab.number < 1 or tab.number ~= math.floor(tab.number) or numbers[tab.number]
                or type(tab.dirty) ~= "boolean" or not finite(tab.revision) or tab.revision < 0
                or tab.revision ~= math.floor(tab.revision)
                or (tab.mode ~= "move" and tab.mode ~= "rotate" and tab.mode ~= "scale")
                or (tab.openedId ~= nil and (not contract.IsValidId(tab.openedId) or opened[tab.openedId])) then
                return false, "Saved editor tab " .. index .. " has invalid state."
            end
            numbers[tab.number] = true
            if tab.openedId then opened[tab.openedId] = true end
            local doc = tab.document
            if type(doc) ~= "table" or type(doc.id) ~= "string" or type(doc.name) ~= "string"
                or type(doc.description) ~= "string" or not arrayLength(doc.tags) then
                return false, "Saved editor tab " .. index .. " has invalid document metadata."
            end
            for _, tag in ipairs(doc.tags) do
                if type(tag) ~= "string" then return false, "Saved editor tab " .. index .. " has invalid tags." end
            end
            if doc.guards ~= nil and not arrayLength(doc.guards) then
                return false, "Saved editor tab " .. index .. " has an invalid guard list."
            end
            local guards = {}
            for guardIndex, guard in ipairs(doc.guards or {}) do
                if type(guard) ~= "table" or type(guard.name) ~= "string" then
                    return false, "Saved editor tab " .. index .. " has invalid guard metadata."
                end
                local copy = {}
                for key, value in pairs(guard) do copy[key] = value end
                copy.name = "Draft guard"
                guards[guardIndex] = copy
            end
            local draft = {
                schemaVersion = doc.schemaVersion, id = "draft", name = "Draft",
                description = doc.description, tags = {}, props = doc.props, lights = doc.lights,
                particles = doc.particles, guards = guards, worldPlacement = doc.worldPlacement
            }
            local valid, problem = contract.Validate(draft, function() return true end)
            if not valid then return false, "Saved editor tab " .. index .. ": " .. tostring(problem) end
            local view = tab.view
            if type(view) ~= "table" then return false, "Saved editor tab " .. index .. " has invalid view settings." end
            for _, key in ipairs({ "cameraYaw", "cameraPitch", "cameraDistance", "panX", "panY",
                "positionSnap", "rotationSnap", "gridSpacing", "referenceOffset", "prefabOffset" }) do
                if not finite(view[key]) then return false, "Saved editor tab " .. index .. " has invalid " .. key .. "." end
            end
            for _, key in ipairs({ "prefabOffsetX", "prefabOffsetY" }) do
                if view[key] ~= nil and not finite(view[key]) then
                    return false, "Saved editor tab " .. index .. " has invalid " .. key .. "."
                end
            end
            for _, key in ipairs({ "snapEnabled", "showGrid", "showCompass", "previewDark" }) do
                if type(view[key]) ~= "boolean" then return false, "Saved editor tab " .. index .. " has invalid " .. key .. "." end
            end
            if view.reference ~= nil and not contract.IsValidModelPath(view.reference) then
                return false, "Saved editor tab " .. index .. " has an invalid reference model."
            end
            if view.previewFog ~= nil then
                local fog = view.previewFog
                if type(fog) ~= "table" or not finite(fog.start) or not finite(fog.finish) or not finite(fog.maxDensity)
                    or type(fog.color) ~= "table" or not finite(fog.color[1]) or not finite(fog.color[2])
                    or not finite(fog.color[3]) then
                    return false, "Saved editor tab " .. index .. " has invalid fog settings."
                end
            end
            local selection = tab.selected
            if selection ~= nil then
                local found = false
                if type(selection) == "number" and selection == math.floor(selection) and selection ~= 0 then
                    found = selection > 0 and doc.props[selection] ~= nil
                        or selection < 0 and (doc.lights or {})[-selection] ~= nil
                elseif type(selection) == "string" then
                    local guardId = string.match(selection, "^guard:(.+)$")
                    local particleId = string.match(selection, "^particle:(.+)$")
                    for _, guard in ipairs(doc.guards or {}) do if guard.guardId == guardId then found = true end end
                    for _, particle in ipairs(doc.particles or {}) do if particle.particleId == particleId then found = true end end
                end
                if not found then return false, "Saved editor tab " .. index .. " has an invalid selection." end
            end
        end
        return true
    end

    function Map.SnapshotsEqual(left, right)
        if type(left) ~= type(right) then return false end
        if type(left) ~= "table" then return left == right end
        for key, value in pairs(left) do
            if not Map.SnapshotsEqual(value, right[key]) then return false end
        end
        for key in pairs(right) do if left[key] == nil then return false end end
        return true
    end

    return Map
end
