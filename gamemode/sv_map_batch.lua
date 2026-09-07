// Server-side maintenance queue for operations that must execute inside each loaded map.
ZM_MapBatch = ZM_MapBatch or {}
local MapBatch = ZM_MapBatch

local statePath = "zombiesim/map_batch.json"
local loadDelaySeconds = 3

local function mapBasename(mapName)
    return string.lower(string.match(mapName or "", "([^/]+)$") or mapName or "")
end

local function isValidMapPath(mapName)
    return type(mapName) == "string" and mapName:match("^[%w_/%-]+$") ~= nil
end

function MapBatch:Notify(message)
    print(message)
    PrintMessage(HUD_PRINTCONSOLE, message .. "\n")
end

function MapBatch:LoadState()
    local json = file.Read(statePath, "DATA")
    if not json then
        return nil
    end

    local state = util.JSONToTable(json)
    if type(state) ~= "table" or type(state.queue) ~= "table" or type(state.index) ~= "number" then
        return nil
    end
    return state
end

function MapBatch:SaveState(state)
    file.CreateDir("zombiesim")
    file.Write(statePath, util.TableToJSON(state, true))
end

function MapBatch:IsActive()
    local state = self:LoadState()
    return state and state.active == true
end

function MapBatch:GetCurrentMap(state)
    return state.queue[state.index]
end

function MapBatch:CanUse(ply)
    return not IsValid(ply) or ply:IsAdmin()
end

function MapBatch:BuildQueue()
    if not ZM_World or not ZM_World:IsLoaded() then
        return nil, "World data is not loaded on this map."
    end

    local data = ZM_World:GetData()
    local mapDirectory = data and data.world and data.world.mapDirectory
    if not isValidMapPath(mapDirectory) then
        return nil, "World data has an invalid map directory."
    end

    local queued = {}
    local queue = {}
    local function addMap(mapName)
        if type(mapName) ~= "string" or not mapName:match("^[%w_%-]+$") then
            return
        end

        local path = mapDirectory .. "/" .. mapName
        local key = string.lower(path)
        if not queued[key] then
            queued[key] = true
            table.insert(queue, path)
        end
    end

    for _, cell in ipairs(data.cells or {}) do
        addMap(cell.map)
    end
    for _, safeZone in ipairs(data.safeZones or {}) do
        addMap(safeZone.map)
    end

    if #queue == 0 then
        return nil, "World data has no recipe or safe-zone maps to process."
    end
    return queue
end

function MapBatch:Advance(state)
    local completedMap = self:GetCurrentMap(state)
    state.completed = state.index
    state.index = state.index + 1
    state.phase = "queued"

    if state.index > #state.queue then
        state.active = false
        state.finishedAt = os.time()
        self:SaveState(state)
        self:Notify("[ZombieSim] " .. state.operation .. " batch completed " .. state.completed .. " maps.")
        return
    end

    self:SaveState(state)
    self:Notify("[ZombieSim] Completed " .. state.operation .. " for " .. completedMap .. ".")
    self:GoToCurrent(state)
end

function MapBatch:ProcessCurrent()
    local state = self:LoadState()
    if not state or not state.active or state.phase ~= "queued" then
        return
    end

    local mapName = self:GetCurrentMap(state)
    if not mapName or mapBasename(game.GetMap()) ~= mapBasename(mapName) then
        return
    end

    state.phase = state.operation == "cubemaps" and "awaiting-cubemap-reload" or "awaiting-confirmation"
    self:SaveState(state)
    self:Notify("[ZombieSim] " .. state.operation .. " " .. state.index .. "/" .. #state.queue .. ": " .. mapName)
    if state.operation == "cubemaps" then
        self:Notify("[ZombieSim] Run buildcubemaps in your console. After its reload, run zombiesim_map_batch_next to load the next map.")
    else
        self:Notify("[ZombieSim] Run nav_generate, then nav_save, in your console. When both finish, run zombiesim_map_batch_complete.")
    end
end

function MapBatch:GoToCurrent(state, forceReload)
    local mapName = self:GetCurrentMap(state)
    if not isValidMapPath(mapName) then
        self:Notify("[ZombieSim] Map batch stopped because its saved queue is invalid.")
        state.active = false
        self:SaveState(state)
        return
    end

    if not forceReload and mapBasename(game.GetMap()) == mapBasename(mapName) then
        timer.Simple(loadDelaySeconds, function()
            MapBatch:ProcessCurrent()
        end)
        return
    end

    self:Notify("[ZombieSim] Loading " .. mapName .. " for " .. state.operation .. ".")
    game.ConsoleCommand("changelevel " .. mapName .. "\n")
end

function MapBatch:Start(operation)
    local queue, queueError = self:BuildQueue()
    if not queue then
        print("[ZombieSim] Could not start map batch: " .. queueError)
        return
    end

    local state = {
        active = true,
        completed = 0,
        index = 1,
        operation = operation,
        phase = "queued",
        profile = ZM_World.ActiveProfile,
        queue = queue,
        startedAt = os.time()
    }
    self:SaveState(state)
    self:Notify("[ZombieSim] Started " .. operation .. " batch for " .. #queue .. " maps.")
    self:GoToCurrent(state)
end

function MapBatch:QueueResume()
    if self.ResumeQueued then
        return
    end

    self.ResumeQueued = true
    timer.Simple(loadDelaySeconds, function()
        MapBatch.ResumeQueued = false
        MapBatch:Resume()
    end)
end

function MapBatch:Resume()
    local state = self:LoadState()
    if not state or not state.active then
        return
    end

    if state.phase == "awaiting-confirmation" and mapBasename(game.GetMap()) == mapBasename(self:GetCurrentMap(state)) then
        self:Notify("[ZombieSim] " .. state.operation .. " is waiting for completion on " .. self:GetCurrentMap(state) .. ". Run zombiesim_map_batch_complete after the native command finishes.")
        return
    end
    if state.phase == "awaiting-cubemap-reload" and mapBasename(game.GetMap()) == mapBasename(self:GetCurrentMap(state)) then
        self:Notify("[ZombieSim] Cubemap reload detected for " .. self:GetCurrentMap(state) .. ". Run zombiesim_map_batch_next to load the next map.")
        return
    end
    self:GoToCurrent(state)
end

concommand.Add("zombiesim_build_cubemaps", function(ply)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can start a map batch.")
        return
    end
    MapBatch:Start("cubemaps")
end)

concommand.Add("zombiesim_generate_navmeshes", function(ply)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can start a map batch.")
        return
    end
    MapBatch:Start("navmeshes")
end)

concommand.Add("zombiesim_map_batch_resume", function(ply)
    if not MapBatch:CanUse(ply) then
        return
    end
    MapBatch:QueueResume()
end)

concommand.Add("zombiesim_map_batch_next", function(ply)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can advance a map batch.")
        return
    end

    local state = MapBatch:LoadState()
    local mapName = state and MapBatch:GetCurrentMap(state)
    if not state or not state.active or not mapName then
        print("[ZombieSim] No active map batch is available to advance.")
        return
    end
    if mapBasename(game.GetMap()) ~= mapBasename(mapName) then
        MapBatch:Notify("[ZombieSim] Map batch is waiting on " .. mapName .. ". Load it before advancing.")
        return
    end

    MapBatch:Advance(state)
end)

concommand.Add("zombiesim_map_batch_complete", function(ply)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can complete a map batch step.")
        return
    end

    local state = MapBatch:LoadState()
    local mapName = state and MapBatch:GetCurrentMap(state)
    if not state or not state.active or state.phase ~= "awaiting-confirmation" or not mapName then
        print("[ZombieSim] No map batch step is awaiting completion.")
        return
    end
    if mapBasename(game.GetMap()) ~= mapBasename(mapName) then
        print("[ZombieSim] Completion ignored: load " .. mapName .. " before confirming this step.")
        return
    end

    MapBatch:Advance(state)
end)

concommand.Add("zombiesim_map_batch_status", function(ply)
    if not MapBatch:CanUse(ply) then
        return
    end

    local state = MapBatch:LoadState()
    if not state then
        print("[ZombieSim] No map batch has been started.")
        return
    end
    local status = state.active and state.phase or "complete"
    print("[ZombieSim] " .. state.operation .. ": " .. status .. "; " .. state.completed .. "/" .. #state.queue .. " complete.")
end)

concommand.Add("zombiesim_map_batch_cancel", function(ply)
    if not MapBatch:CanUse(ply) then
        return
    end

    file.Delete(statePath)
    print("[ZombieSim] Map batch cancelled.")
end)

hook.Add("InitPostEntity", "ZombieSim.ResumeMapBatch", function()
    MapBatch:QueueResume()
end)

hook.Add("PlayerSpawn", "ZombieSim.ResumeMapBatchOnPlayerSpawn", function()
    if MapBatch:IsActive() then
        MapBatch:QueueResume()
    end
end)