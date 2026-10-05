ZM_Distribution = ZM_Distribution or {}
local Distribution = ZM_Distribution

Distribution.Packaged = false
Distribution.Ready = false
Distribution.Clients = Distribution.Clients or {}

local function validPath(path)
    return type(path) == "string" and #path > 0 and not string.find(path, "\\", 1, true)
        and not string.find(path, "..", 1, true) and not string.find(path, "//", 1, true)
        and not string.match(path, "^/") and string.match(path, "^[%w_ ./%-]+$") ~= nil
end

function Distribution.WorkshopStatus(pack, subscribed, addon)
    if pack.workshopId == "" then
        return "pending", "Not published - " .. (pack.workshopIdPlaceholder or "pending:" .. pack.id)
    end
    if addon and addon.mounted then
        return subscribed and "mounted" or "mounted_unsubscribed",
            subscribed and "Subscribed and mounted" or "Mounted, not subscribed (server/local content)"
    end
    if addon and addon.downloaded then return "disabled", "Downloaded but not mounted - enable addon and restart" end
    if subscribed then return "downloading", "Subscribed, not mounted - finish downloads and restart" end
    return "unsubscribed", "Not subscribed - open Workshop to subscribe"
end

function Distribution.Validate(data, readMarker, size)
    if type(data) ~= "table" or data.schemaVersion ~= 1 or type(data.releaseId) ~= "string"
        or #data.releaseId ~= 64 or not string.match(data.releaseId, "^%x+$")
        or type(data.packs) ~= "table" or #data.packs == 0 or #data.packs > 128
        or type(data.development) ~= "boolean" or type(data.profiles) ~= "table" or #data.profiles == 0
        or type(data.integrityErrors) ~= "table" then
        return false, "Invalid distribution manifest"
    end
    if #data.integrityErrors > 0 then return false, "Package build is incomplete: " .. tostring(data.integrityErrors[1]) end
    local owners, ids, workshopIds, core = {}, {}, {}, false
    for _, pack in ipairs(data.packs) do
        if type(pack) ~= "table" or type(pack.id) ~= "string" or not string.match(pack.id, "^[%w%-]+$")
            or ids[pack.id] or type(pack.revision) ~= "string" or #pack.revision ~= 64
            or not string.match(pack.revision, "^%x+$") or type(pack.files) ~= "table"
            or #pack.files == 0 or #pack.files > 32768 or type(pack.workshopId) ~= "string"
            or (pack.workshopId ~= "" and not string.match(pack.workshopId, "^%d+$")) then
            return false, "Invalid or duplicate package declaration"
        end
        if pack.workshopId == "" and data.development ~= true then return false, "Missing Workshop ID: " .. pack.id end
        if pack.workshopId ~= "" then
            if workshopIds[pack.workshopId] then return false, "Duplicate Workshop ID: " .. pack.workshopId end
            workshopIds[pack.workshopId] = true
        end
        ids[pack.id], core = true, core or pack.id == "core"
        local marker = readMarker("data_static/zombiesim_packages/" .. pack.id .. ".json")
        if type(marker) ~= "table" or marker.schemaVersion ~= 1 or marker.id ~= pack.id
            or (pack.id == "core" and marker.releaseId ~= data.releaseId) or marker.revision ~= pack.revision then
            return false, "Missing or incompatible content pack: " .. pack.id
        end
        for _, entry in ipairs(pack.files) do
            if type(entry) ~= "table" or not validPath(entry.path) or owners[string.lower(entry.path)]
                or type(entry.bytes) ~= "number" or entry.bytes < 0 or entry.bytes ~= math.floor(entry.bytes) then
                return false, "Invalid or conflicting file ownership: " .. pack.id
            end
            owners[string.lower(entry.path)] = pack.id
            if size(entry.path) ~= entry.bytes then
                return false, "Missing or incorrect content file: " .. entry.path .. " (pack " .. pack.id .. ")"
            end
        end
    end
    if not core then return false, "Distribution is missing its core package" end
    return true
end

function Distribution:Check()
    local json = file.Read("data_static/zombiesim_distribution.json", "GAME")
    if not json and not self.Packaged then
        self.Ready, self.Manifest, self.Error = true, nil, nil
        return true
    end
    local parsed = json and util.JSONToTable(json) or nil
    self.Manifest = type(parsed) == "table" and parsed or nil
    self.Ready, self.Error = self.Validate(self.Manifest, function(path)
        local marker = file.Read(path, "GAME")
        return marker and util.JSONToTable(marker)
    end, function(path) return file.Size(path, "GAME") end)
    if not self.Ready then ErrorNoHalt("[ZombieSim] Distribution check failed: " .. tostring(self.Error) .. "\n") end
    return self.Ready, self.Error
end

function Distribution:CanDeploy(target)
    if not self.Ready then return false, "Content packages unavailable: " .. tostring(self.Error) end
    if not self.Manifest then return true end
    local included = false
    for _, profile in ipairs(self.Manifest.profiles) do
        if ZM_World and profile == ZM_World.ActiveProfile then included = true break end
    end
    if not included then return false, "This release does not contain the active world profile" end
    local status = self.Clients[target]
    if not status then return false, "Waiting for client content-package validation; retry deployment shortly" end
    if not status.ready then return false, "Client content packages unavailable: " .. status.message end
    return true
end

Distribution:Check()

if SERVER then
    util.AddNetworkString("ZM.DistributionReady")
    if Distribution.Ready and Distribution.Manifest then
        for _, pack in ipairs(Distribution.Manifest.packs) do
            if pack.workshopId ~= "" then resource.AddWorkshop(pack.workshopId) end
        end
    end
    net.Receive("ZM.DistributionReady", function(_, target)
        local releaseId, ready, message = net.ReadString(), net.ReadBool(), net.ReadString()
        if not Distribution.Manifest or #releaseId > 64 or #message > 256 then return end
        local matches = releaseId == Distribution.Manifest.releaseId
        local previous = Distribution.Clients[target]
        Distribution.Clients[target] = { ready = ready and matches,
            message = matches and message or "Core/content release differs from server; update required addons" }
        if ready and matches and not (previous and previous.ready) and ZM_Launcher
            and target.ZM_LauncherState == "menu" then ZM_Launcher:TryAutoload(target) end
    end)
    hook.Add("PlayerDisconnected", "ZM.Distribution.Clear", function(target) Distribution.Clients[target] = nil end)
else
    function Distribution:RefreshWorkshop()
        self.WorkshopRows = {}
        if not self.Manifest or type(self.Manifest.packs) ~= "table" then return self.WorkshopRows end
        local addons = {}
        for _, addon in ipairs(engine.GetAddons()) do addons[tostring(addon.wsid)] = addon end
        for _, pack in ipairs(self.Manifest.packs) do
            if type(pack) == "table" and type(pack.id) == "string" and type(pack.workshopId) == "string"
                and (pack.workshopId == "" or string.match(pack.workshopId, "^[1-9]%d*$")) then
                local subscribed = pack.workshopId ~= "" and steamworks.IsSubscribed(pack.workshopId) or false
                local state, message = self.WorkshopStatus(pack, subscribed, addons[pack.workshopId])
                self.WorkshopRows[#self.WorkshopRows + 1] = {
                    id = pack.id, workshopId = pack.workshopId, state = state, message = message
                }
            end
        end
        return self.WorkshopRows
    end

    function Distribution:ReportClient()
        if not self.Packaged and not self.Manifest then return end
        net.Start("ZM.DistributionReady")
            net.WriteString(tostring(self.Manifest and self.Manifest.releaseId or ""))
            net.WriteBool(self.Ready)
            net.WriteString(string.sub(tostring(self.Error or ""), 1, 256))
        net.SendToServer()
    end

    function Distribution:RefreshClient()
        self:Check()
        self:RefreshWorkshop()
        self:ReportClient()
        return self.Ready, self.Error
    end

    hook.Add("InitPostEntity", "ZM.Distribution.Ready", function()
        Distribution:RefreshWorkshop()
        if not Distribution.Packaged and not Distribution.Manifest then return end
        ZM_Loading:Step(Distribution.Ready and "Content packages verified" or tostring(Distribution.Error),
            Distribution.Ready and "ok" or "fail")
        Distribution:ReportClient()
    end)
end
