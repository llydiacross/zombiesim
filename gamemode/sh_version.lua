// Game version and changelog from data_static/version.json and changelog.json (single source of truth).
ZM_Version = ZM_Version or {}
local Version = ZM_Version

local function readJson(name)
    local text = file.Read("data_static/" .. name, "GAME")
    if not text then return nil, name .. " is missing" end
    local data = util.JSONToTable(text)
    if not istable(data) or data.schemaVersion ~= 1 then return nil, name .. " is invalid" end
    return data
end

function Version:Load()
    self.Error, self.ChangelogError = nil, nil
    local info, problem = readJson("version.json")
    if info and not (isstring(info.version) and string.match(info.version, "^%d+%.%d+[%.%d]*$")
        and isstring(info.stage) and isstring(info.status)) then
        info, problem = nil, "version.json is missing version, stage or status"
    end
    self.Info, self.Error = info, problem
    local log, logProblem = readJson("changelog.json")
    if log and not istable(log.entries) then log, logProblem = nil, "changelog.json has no entries" end
    self.Entries = log and log.entries or {}
    self.ChangelogError = logProblem
end

// "Alpha 3.1.0 (in development)"
function Version:GetLabel()
    local info = self.Info
    if not info then return "Unknown version" end
    local label = info.stage .. " " .. info.version
    return info.status == "released" and label or label .. " (" .. info.status .. ")"
end

// Loose development checkouts only; packaged builds have no .git directory.
function Version:GetSourceCommit()
    if self.Commit ~= nil then return self.Commit or nil end
    self.Commit = false
    local root = "gamemodes/zombiesim/.git/"
    local head = file.Read(root .. "HEAD", "GAME")
    if not head then return nil end
    head = string.Trim(head)
    local ref = string.match(head, "^ref:%s*(.+)$")
    local hash = ref and file.Read(root .. ref, "GAME") or (not ref and head) or nil
    if ref and not hash then
        for line in string.gmatch(file.Read(root .. "packed-refs", "GAME") or "", "[^\n]+") do
            local candidate, name = string.match(line, "^(%x+)%s+(%S+)")
            if name == ref then hash = candidate break end
        end
    end
    hash = hash and string.match(string.Trim(hash), "^%x+$")
    if hash then
        self.Commit = { hash = string.sub(hash, 1, 10), branch = ref and string.match(ref, "refs/heads/(.+)$") or "detached" }
    end
    return self.Commit or nil
end

Version:Load()
