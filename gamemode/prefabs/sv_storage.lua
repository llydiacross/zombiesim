return function(files, json, contract, validModel, validateContent)
    local Storage = {}
    local root = "zombiesim/prefabs"
    local recovery = "zombiesim/prefab_editor_recovery"

    local function prepareDirectories()
        files.CreateDir(root)
        files.CreateDir(recovery)
        if not files.IsDir(root, "DATA") or not files.IsDir(recovery, "DATA") then
            return false, "Could not create prefab storage directories."
        end
        return true
    end

    local function pathFor(id)
        if not contract.IsValidId(id) then return nil, "Invalid prefab ID." end
        return root .. "/" .. id .. ".json"
    end

    function Storage.Load(id)
        local path, pathError = pathFor(id)
        if not path then return nil, pathError end
        local text = files.Read(path, "DATA")
        if type(text) ~= "string" then return nil, "Could not read prefab '" .. id .. "'." end
        local decoded = json.JSONToTable(text)
        if type(decoded) ~= "table" then return nil, "Prefab '" .. id .. "' contains invalid JSON." end
        local document, problem = contract.Validate(decoded, validModel)
        if not document then return nil, "Prefab '" .. id .. "': " .. problem end
        if validateContent then
            local ok, contentError = validateContent(document)
            if not ok then return nil, "Prefab '" .. id .. "': " .. contentError end
        end
        if document.id ~= id then return nil, "Prefab ID does not match its filename: " .. id end
        return document
    end

    function Storage.List()
        if not files.IsDir(root, "DATA") then return {} end
        local names = files.Find(root .. "/*.json", "DATA")
        if type(names) ~= "table" then return nil, "Could not list prefab files." end
        table.sort(names)
        local documents = {}
        for _, name in ipairs(names) do
            local id = string.match(name, "^(.*)%.json$")
            if not contract.IsValidId(id) then return nil, "Unexpected prefab filename: " .. tostring(name) end
            local document, problem = Storage.Load(id)
            if not document then return nil, problem end
            documents[#documents + 1] = document
        end
        return documents
    end

    function Storage.Save(input, openedId)
        local document, problem = contract.Validate(input, validModel)
        if not document then return false, problem end
        if validateContent then
            local ok, contentError = validateContent(document)
            if not ok then return false, contentError end
        end
        local path = pathFor(document.id)
        local exists = files.Exists(path, "DATA")
        if exists and openedId ~= document.id then
            return false, "A prefab with this ID already exists; open it before saving."
        end
        if openedId ~= nil and (openedId ~= document.id or not exists) then
            return false, "The opened prefab no longer matches the save target."
        end
        local ready, directoryError = prepareDirectories()
        if not ready then return false, directoryError end
        local pending = recovery .. "/" .. document.id .. ".pending.json"
        local backup = recovery .. "/" .. document.id .. ".backup.json"
        if files.Exists(pending, "DATA") or files.Exists(backup, "DATA") then
            return false, "A previous prefab save needs recovery before saving '" .. document.id .. "'."
        end
        local encoded = json.TableToJSON(document, true)
        if type(encoded) ~= "string" then return false, "Could not encode the prefab as JSON." end
        if not files.Write(pending, encoded) or files.Read(pending, "DATA") ~= encoded then
            return false, "Could not write or verify the pending prefab file: " .. pending
        end
        if exists and not files.Rename(path, backup) then
            return false, "Could not preserve the existing prefab; pending data remains at " .. pending
        end
        if not files.Rename(pending, path) then
            if exists and not files.Rename(backup, path) then
                return false, "Prefab save failed; recover the original from " .. backup .. " and draft from " .. pending
            end
            return false, "Prefab save failed; the original is intact and the draft remains at " .. pending
        end
        if exists and not files.Delete(backup) then
            return true, "Prefab saved; the previous copy remains at " .. backup
        end
        return true
    end

    function Storage.Delete(id)
        local path, problem = pathFor(id)
        if not path then return false, problem end
        if not files.Exists(path, "DATA") then return false, "Prefab '" .. id .. "' does not exist." end
        if not files.Delete(path) then return false, "Could not delete prefab '" .. id .. "'." end
        return true
    end

    return Storage
end
