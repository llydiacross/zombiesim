return function()
    local files = {}
    return {
        Add = function(path, value) files[path] = value end,
        Exists = function(path) return files[path] ~= nil end,
        Size = function(path) return files[path] and #files[path] or -1 end,
        Read = function(path) return files[path] end
    }
end
