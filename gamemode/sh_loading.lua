// Loading-screen step log shared by every system that does work behind the loading screen.
//
// Server (target is a player, a list of players, or nil for every human):
//     ZM_Loading:Step(target, "Loaded inventory")                 -- a finished step, status "ok"
//     ZM_Loading:Step(target, "Cache missing", "warn")            -- statuses: ok, warn, fail, info, pending
//     local id = ZM_Loading:Begin(target, "Contacting services")  -- shows a spinner until finished
//     ZM_Loading:Finish(target, id)                               -- or Finish(target, id, "fail", "Services offline")
// Client (always the local player):
//     ZM_Loading:Step("Downloaded profile")
//     local id = ZM_Loading:Begin("Fetching news")
//     ZM_Loading:Finish(id, "ok", "Fetched 3 news items")
//
// Each line is stamped with the time since the player's current load began (their spawn on this map, or the start
// of an exit sequence), so the log shows real elapsed time rather than when the client happened to draw it.
ZM_Loading = ZM_Loading or {}
local Loading = ZM_Loading

Loading.Statuses = { pending = true, ok = true, warn = true, fail = true, info = true }
Loading.MaxLines = 64
Loading.NextId = Loading.NextId or 0

local function normaliseStatus(status)
    return Loading.Statuses[status] and status or "ok"
end

local function nextId(prefix)
    Loading.NextId = Loading.NextId + 1
    return prefix .. Loading.NextId
end

if SERVER then
    util.AddNetworkString("ZM.LoadingLog")
    util.AddNetworkString("ZM.LoadingLogReset")

    local function getRecipients(target)
        if target == nil then
            return player.GetHumans()
        end
        if type(target) == "Player" then
            return IsValid(target) and { target } or {}
        end
        local recipients = {}
        if type(target) == "table" then
            for _, playerEntity in ipairs(target) do
                if type(playerEntity) == "Player" and IsValid(playerEntity) then
                    table.insert(recipients, playerEntity)
                end
            end
        end
        return recipients
    end

    local function getElapsed(playerEntity)
        if not playerEntity.ZM_LoadingStart then
            playerEntity.ZM_LoadingStart = SysTime()
        end
        return SysTime() - playerEntity.ZM_LoadingStart
    end

    local function send(target, id, text, status)
        for _, playerEntity in ipairs(getRecipients(target)) do
            net.Start("ZM.LoadingLog")
            net.WriteString(id)
            net.WriteString(text or "")
            net.WriteString(status)
            net.WriteFloat(getElapsed(playerEntity))
            net.Send(playerEntity)
        end
    end

    // Starts a new load for the target: its log is cleared and timestamps restart from zero.
    function Loading:Reset(target)
        for _, playerEntity in ipairs(getRecipients(target)) do
            playerEntity.ZM_LoadingStart = SysTime()
            net.Start("ZM.LoadingLogReset")
            net.Send(playerEntity)
        end
    end

    function Loading:Step(target, text, status)
        local id = nextId("sv")
        send(target, id, tostring(text), normaliseStatus(status))
        return id
    end

    function Loading:Begin(target, text)
        return self:Step(target, text, "pending")
    end

    // Completes a Begin step; text is optional and replaces the step's original text.
    function Loading:Finish(target, id, status, text)
        if type(id) ~= "string" then
            return
        end
        send(target, id, text and tostring(text) or "", normaliseStatus(status or "ok"))
    end

    hook.Add("PlayerInitialSpawn", "ZM.Loading.StartClock", function(playerEntity)
        playerEntity.ZM_LoadingStart = SysTime()
    end)
    return
end

// Client: ordered lines plus an id lookup so Finish can update a pending line in place.
Loading.Lines = Loading.Lines or {}
Loading.ById = Loading.ById or {}
Loading.LocalStart = Loading.LocalStart or SysTime()

function Loading:Clear()
    self.Lines = {}
    self.ById = {}
    self.LocalStart = SysTime()
end

local function upsert(id, text, status, elapsed)
    local line = Loading.ById[id]
    if line then
        if text ~= "" then
            line.text = text
        end
        line.status = status
        line.finishedAt = RealTime()
        return line
    end
    line = { id = id, text = text, status = status, elapsed = elapsed, receivedAt = RealTime() }
    Loading.ById[id] = line
    table.insert(Loading.Lines, line)
    while #Loading.Lines > Loading.MaxLines do
        local removed = table.remove(Loading.Lines, 1)
        Loading.ById[removed.id] = nil
    end
    return line
end

function Loading:Step(text, status)
    local id = nextId("cl")
    upsert(id, tostring(text), normaliseStatus(status), SysTime() - self.LocalStart)
    return id
end

function Loading:Begin(text)
    return self:Step(text, "pending")
end

function Loading:Finish(id, status, text)
    if type(id) ~= "string" or not self.ById[id] then
        return
    end
    upsert(id, text and tostring(text) or "", normaliseStatus(status or "ok"))
end

function Loading:HasPending()
    for _, line in ipairs(self.Lines) do
        if line.status == "pending" then
            return true
        end
    end
    return false
end

net.Receive("ZM.LoadingLog", function()
    local id = net.ReadString()
    local text = net.ReadString()
    local status = net.ReadString()
    upsert(id, text, normaliseStatus(status), net.ReadFloat())
end)

net.Receive("ZM.LoadingLogReset", function()
    Loading:Clear()
end)
