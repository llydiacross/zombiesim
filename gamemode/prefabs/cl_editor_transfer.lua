return function(api, mapContract)
    local Transfer = {}
    local path = "zombiesim/prefab_editor_map_transfer.json"

    function Transfer:Exists()
        return api.file.Exists(path, "DATA")
    end

    function Transfer:Save(mapName, tabs, active, cellId)
        if self:Exists() then
            return nil, "A previous editor map-switch draft exists at " .. path .. "; preserve it before switching again."
        end
        if not mapContract.IsValidName(mapName)
            or (cellId == nil and mapContract.IsReservedName(mapName))
            or (cellId ~= nil and not mapContract.IsValidCellId(cellId)) then
            return nil, "The selected editor map is invalid or reserved."
        end
        local crc = api.util.CRC(mapName .. ":" .. tostring(api.SysTime()) .. ":" .. tostring(api.RealTime()))
        if type(crc) ~= "string" or not string.match(crc, "^%d+$") then
            return nil, "Could not create an editor map-switch token."
        end
        local snapshot = { schemaVersion = 1, token = "switch_" .. crc, map = mapName, cellId = cellId,
            active = active, tabs = tabs }
        local valid, problem = mapContract.ValidateSnapshot(snapshot)
        if not valid then return nil, problem end
        local encoded = api.util.TableToJSON(snapshot, false)
        local decoded = type(encoded) == "string" and api.util.JSONToTable(encoded) or nil
        if type(encoded) ~= "string" or type(decoded) ~= "table" or not mapContract.SnapshotsEqual(snapshot, decoded) then
            return nil, "Editor map-switch drafts could not be encoded without changing their contents."
        end
        api.file.CreateDir("zombiesim")
        if not api.file.Write(path, encoded) or api.file.Read(path, "DATA") ~= encoded then
            return nil, "Could not save and verify the editor map-switch draft; inspect " .. path .. "."
        end
        local openIds = {}
        for _, tab in ipairs(tabs) do if tab.openedId then openIds[#openIds + 1] = tab.openedId end end
        return { token = snapshot.token, map = mapName, cellId = cellId, openIds = openIds, encoded = encoded }
    end

    function Transfer:Read(token, openIds)
        local encoded = api.file.Read(path, "DATA")
        if type(encoded) ~= "string" then return nil, "The editor map-switch draft is missing from this client." end
        local snapshot = api.util.JSONToTable(encoded)
        local valid, problem = mapContract.ValidateSnapshot(snapshot)
        if not valid then return nil, problem .. " The original draft remains at " .. path .. "." end
        if snapshot.token ~= token then return nil, "The editor map-switch draft does not match the server session." end
        local authorized = mapContract.ValidateRequest({ map = snapshot.map, cellId = snapshot.cellId,
            token = token, openIds = openIds })
        if not authorized then return nil, "The server returned invalid editor open-tab IDs." end
        local requested = {}
        for _, id in ipairs(openIds) do requested[id] = true end
        for _, tab in ipairs(snapshot.tabs) do
            if tab.openedId then
                if not requested[tab.openedId] then return nil, "Saved editor tabs do not match server authorization." end
                requested[tab.openedId] = nil
            end
        end
        if next(requested) then return nil, "Server authorization contains a missing editor tab." end
        return snapshot, encoded
    end

    function Transfer:Remove(expected)
        local current = api.file.Read(path, "DATA")
        if type(expected) ~= "string" or current ~= expected then
            return false, "The editor map-switch draft changed; preserve and inspect " .. path .. "."
        end
        if not api.file.Delete(path) or api.file.Exists(path, "DATA") then
            return false, "Could not remove the restored editor map-switch draft at " .. path .. "."
        end
        return true
    end

    return Transfer
end
