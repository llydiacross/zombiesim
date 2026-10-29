return function()
    local state = { files = {}, directories = {}, values = {}, nextValue = 0, fail = {} }
    local function clone(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for key, entry in pairs(value) do copy[key] = clone(entry) end
        return copy
    end
    local files = {}
    function files.CreateDir(path) state.directories[path] = true end
    function files.IsDir(path, realm) assert(realm == "DATA"); return state.directories[path] == true end
    function files.Exists(path, realm) assert(realm == "DATA"); return state.files[path] ~= nil end
    function files.Read(path, realm) assert(realm == "DATA"); return state.files[path] end
    function files.Write(path, text)
        if state.fail.write then return false end
        state.files[path] = text
        return true
    end
    function files.Rename(source, destination)
        if state.fail.renameFrom == source or not state.files[source] or state.files[destination] then return false end
        state.files[destination], state.files[source] = state.files[source], nil
        return true
    end
    function files.Delete(path)
        if state.fail.delete or not state.files[path] then return false end
        state.files[path] = nil
        return true
    end
    function files.Find(pattern, realm)
        assert(pattern == "zombiesim/prefabs/*.json" and realm == "DATA")
        local names = {}
        for path in pairs(state.files) do
            local name = string.match(path, "^zombiesim/prefabs/([^/]+%.json)$")
            if name then names[#names + 1] = name end
        end
        return names, {}
    end
    local json = {}
    function json.TableToJSON(value)
        state.nextValue = state.nextValue + 1
        local key = "encoded-" .. state.nextValue
        state.values[key] = clone(value)
        return key
    end
    function json.JSONToTable(text) return clone(state.values[text]) end
    return { state = state, files = files, json = json }
end
