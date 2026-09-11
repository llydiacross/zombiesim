// Server-side maintenance queue for operations that must execute inside each loaded map.
ZM_MapBatch = ZM_MapBatch or {}
local MapBatch = ZM_MapBatch

local statePath = "zombiesim/map_batch.json"
local navmeshStatusPath = "zombiesim/navmesh_status_%s.json"
local navmeshValidationPath = "zombiesim/navmesh_validation_%s.json"
local navmeshWireframeManifestPath = "zombiesim/navmesh_wireframes_%s.json"
local loadDelaySeconds = 3
local navmeshPollInterval = 0.25
local navmeshGenerationStartGraceSeconds = 2
local navmeshGenerationTimeoutSeconds = 300
local navmeshWireframeLoadTimeoutSeconds = 30

local function mapBasename(mapName)
    return string.lower(string.match(mapName or "", "([^/]+)$") or mapName or "")
end

local function isValidMapPath(mapName)
    return type(mapName) == "string" and mapName:match("^[%w_/%-]+$") ~= nil
end

local function getActiveProfile()
    return ZM_World and ZM_World.ActiveProfile or "unknown"
end

local function getRuntimeRevision()
    local data = ZM_World and ZM_World:GetData() or nil
    local world = data and data.world or nil
    if type(world) ~= "table" then
        return "unknown"
    end
    return tostring(world.mapManifestSha256 or world.templatePlanSha256 or "unknown")
end

local function getProfileDataPath(pattern, profile)
    local safeProfile = string.gsub(profile or "unknown", "[^%w_%-]", "_")
    return string.format(pattern, safeProfile)
end

local function getNavmeshWireframePath(profile, mapName)
    local safeProfile = string.gsub(profile or "unknown", "[^%w_%-]", "_")
    local safeMapName = string.gsub(mapBasename(mapName), "[^%w_%-]", "_")
    return "zombiesim/navmesh_wireframe_" .. safeProfile .. "_" .. safeMapName .. ".json"
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

function MapBatch:BuildQueue(includeSafeZones)
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
    if includeSafeZones ~= false then
        for _, safeZone in ipairs(data.safeZones or {}) do
            addMap(safeZone.map)
        end
    end

    if #queue == 0 then
        return nil, "World data has no recipe or safe-zone maps to process."
    end
    return queue
end

function MapBatch:GetNavmeshStatus()
    local mapName = game.GetMap()
    local data = ZM_World and ZM_World:GetData() or nil
    local mapDirectory = data and data.world and data.world.mapDirectory or ""
    local mapPath = "maps/" .. mapName
    if isValidMapPath(mapDirectory) then
        mapPath = "maps/" .. mapDirectory .. "/" .. mapName
    end
    local status = {
        map = mapName,
        profile = getActiveProfile(),
        runtimeRevision = getRuntimeRevision(),
        bspExists = file.Exists(mapPath .. ".bsp", "GAME"),
        navFileExists = file.Exists(mapPath .. ".nav", "GAME"),
        checkedAt = os.time()
    }

    if type(navmesh) ~= "table" or type(navmesh.GetNavAreaCount) ~= "function" or
        type(navmesh.IsGenerating) ~= "function" or type(navmesh.IsLoaded) ~= "function" then
        status.error = "navmesh API is unavailable"
        return status
    end

    local generating, generatingValue = pcall(navmesh.IsGenerating)
    local loaded, loadedValue = pcall(navmesh.IsLoaded)
    local counted, areaCount = pcall(navmesh.GetNavAreaCount)
    if not generating or not loaded or not counted then
        status.error = "could not query navmesh state"
        return status
    end

    status.generating = generatingValue == true
    status.loaded = loadedValue == true
    status.areaCount = math.max(0, math.floor(tonumber(areaCount) or 0))
    return status
end

function MapBatch:WriteNavmeshStatus(status)
    file.CreateDir("zombiesim")
    file.Write(
        getProfileDataPath(navmeshStatusPath, status.profile),
        util.TableToJSON(status, true) or "{}"
    )
end

function MapBatch:WriteNavmeshValidation(state)
    if state.operation ~= "navmeshes" and state.operation ~= "wireframes" then
        return
    end

    local validation = {
        profile = state.profile,
        runtimeRevision = state.runtimeRevision,
        active = state.active == true,
        completed = state.completed or 0,
        requiredMaps = state.queue or {},
        maps = state.navmeshResults or {},
        updatedAt = os.time()
    }
    file.CreateDir("zombiesim")
    file.Write(
        getProfileDataPath(navmeshValidationPath, state.profile),
        util.TableToJSON(validation, true) or "{}"
    )
end

function MapBatch:ExportNavmeshWireframe(status)
    if type(navmesh) ~= "table" or type(navmesh.GetAllNavAreas) ~= "function" then
        return false, "navmesh.GetAllNavAreas is unavailable"
    end

    local queried, navAreas = pcall(navmesh.GetAllNavAreas)
    if not queried or type(navAreas) ~= "table" then
        return false, "could not query generated nav areas"
    end

    local areas = {}
    for index, navArea in ipairs(navAreas) do
        local corners = {}
        for cornerIndex = 0, 3 do
            local readCorner, corner = pcall(navArea.GetCorner, navArea, cornerIndex)
            local x = readCorner and tonumber(corner.x) or nil
            local y = readCorner and tonumber(corner.y) or nil
            local z = readCorner and tonumber(corner.z) or nil
            if not x or not y or not z then
                return false, "nav area " .. tostring(index) .. " has an unreadable corner " .. tostring(cornerIndex)
            end
            table.insert(corners, { x = x, y = y, z = z })
        end
        local readId, areaId = pcall(navArea.GetID, navArea)
        table.insert(areas, {
            id = readId and math.floor(tonumber(areaId) or index) or index,
            corners = corners
        })
    end
    table.sort(areas, function(left, right) return left.id < right.id end)
    if #areas ~= status.areaCount then
        return false, "nav area export count " .. tostring(#areas) .. " does not match generated count " .. tostring(status.areaCount)
    end

    local exportPath = getNavmeshWireframePath(status.profile, status.map)
    local export = {
        schemaVersion = 1,
        profile = status.profile,
        runtimeRevision = status.runtimeRevision,
        map = status.map,
        areaCount = #areas,
        capturedAt = os.time(),
        areas = areas
    }
    file.CreateDir("zombiesim")
    file.Write(exportPath, util.TableToJSON(export, true) or "{}")

    local manifestPath = getProfileDataPath(navmeshWireframeManifestPath, status.profile)
    local manifest = util.JSONToTable(file.Read(manifestPath, "DATA") or "")
    if type(manifest) ~= "table" or manifest.runtimeRevision ~= status.runtimeRevision then
        manifest = {
            schemaVersion = 1,
            profile = status.profile,
            runtimeRevision = status.runtimeRevision,
            maps = {}
        }
    end
    manifest.maps = manifest.maps or {}
    manifest.maps[status.map] = {
        path = exportPath,
        areaCount = #areas,
        capturedAt = export.capturedAt
    }
    manifest.updatedAt = export.capturedAt
    file.Write(manifestPath, util.TableToJSON(manifest, true) or "{}")
    return true, exportPath
end

function MapBatch:RecordWireframeUnavailable(state, status, reason)
    status.wireframeExportError = reason
    self:WriteNavmeshStatus(status)
    state.navmeshResults = state.navmeshResults or {}
    state.navmeshResults[self:GetCurrentMap(state)] = status
    self:WriteNavmeshValidation(state)
    self:Notify("[ZombieSim] Skipped wireframe export for " .. self:GetCurrentMap(state) .. ": " .. reason .. ".")
    self:Advance(state)
end

function MapBatch:Fail(state, message)
    state.phase = "failed"
    state.error = message
    state.failedAt = os.time()
    self:SaveState(state)
    self:WriteNavmeshValidation(state)
    self:Notify("[ZombieSim] " .. state.operation .. " batch failed on " .. tostring(self:GetCurrentMap(state)) .. ": " .. message)
end

function MapBatch:AddNavmeshSpawnSeed()
    if type(navmesh) ~= "table" or type(navmesh.AddWalkableSeed) ~= "function" or
        type(navmesh.GetPlayerSpawnName) ~= "function" then
        return nil, "navmesh walkable-seed APIs are unavailable"
    end

    if type(navmesh.ClearWalkableSeeds) == "function" then
        navmesh.ClearWalkableSeeds()
    end

    local spawnClass = navmesh.GetPlayerSpawnName()
    local spawn = ents.FindByClass(spawnClass)[1]
    if not IsValid(spawn) then
        return nil, "no " .. tostring(spawnClass) .. " entity is available for navmesh generation"
    end

    local spawnPosition = spawn:GetPos()
    local trace = util.TraceLine({
        start = spawnPosition + Vector(0, 0, 32),
        endpos = spawnPosition - Vector(0, 0, 256),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not trace.Hit then
        return nil, "could not find walkable world geometry beneath " .. tostring(spawnClass)
    end

    navmesh.AddWalkableSeed(trace.HitPos, trace.HitNormal)
    return trace.HitPos
end

function MapBatch:StartNavmeshGeneration(state)
    if type(navmesh) ~= "table" or type(navmesh.BeginGeneration) ~= "function" then
        self:Fail(state, "navmesh.BeginGeneration is unavailable")
        return
    end

    local seedPosition, seedError = self:AddNavmeshSpawnSeed()
    if not seedPosition then
        self:Fail(state, seedError)
        return
    end

    state.phase = "generating-navmesh"
    state.error = nil
    state.generationStartedAt = os.time()
    state.generationObserved = false
    state.generationSeed = {
        x = math.floor(seedPosition.x),
        y = math.floor(seedPosition.y),
        z = math.floor(seedPosition.z)
    }
    self:SaveState(state)
    local started, startError = pcall(navmesh.BeginGeneration)
    if not started then
        self:Fail(state, "navmesh generation could not start: " .. tostring(startError))
        return
    end

    self:Notify("[ZombieSim] Generating navmesh for " .. self:GetCurrentMap(state) .. ".")
end

function MapBatch:PollNavmeshGeneration()
    local state = self:LoadState()
    if not state or not state.active or state.operation ~= "navmeshes" or state.phase ~= "generating-navmesh" then
        return
    end

    local mapName = self:GetCurrentMap(state)
    if not mapName or mapBasename(game.GetMap()) ~= mapBasename(mapName) then
        return
    end

    local status = self:GetNavmeshStatus()
    if status.error then
        self:Fail(state, status.error)
        return
    end
    if status.generating then
        if not state.generationObserved then
            state.generationObserved = true
            self:SaveState(state)
        end
        return
    end
    local startedAt = tonumber(state.generationStartedAt) or os.time()
    local elapsedSeconds = math.max(0, os.time() - startedAt)
    if not state.generationObserved and elapsedSeconds < navmeshGenerationStartGraceSeconds then
        return
    end
    if elapsedSeconds > navmeshGenerationTimeoutSeconds then
        self:Fail(state, "navmesh generation timed out after " .. navmeshGenerationTimeoutSeconds .. " seconds")
        return
    end
    if status.areaCount <= 0 then
        self:Fail(state, "navmesh generation did not start or produced no usable nav areas")
        return
    end
    if type(navmesh.Save) ~= "function" then
        self:Fail(state, "navmesh.Save is unavailable")
        return
    end

    state.generatedNavmesh = {
        map = status.map,
        areaCount = status.areaCount,
        generatedAt = os.time()
    }
    state.phase = "saving-navmesh"
    self:SaveState(state)
    local saved, saveError = pcall(navmesh.Save)
    if not saved then
        self:Fail(state, "navmesh save failed: " .. tostring(saveError))
        return
    end

    // Let the engine finish its save work before checking the mounted file system.
    timer.Simple(1, function()
        MapBatch:VerifySavedNavmesh()
    end)
end

function MapBatch:VerifySavedNavmesh()
    local state = self:LoadState()
    if not state or not state.active or state.operation ~= "navmeshes" or state.phase ~= "saving-navmesh" then
        return
    end

    local mapName = self:GetCurrentMap(state)
    if not mapName or mapBasename(game.GetMap()) ~= mapBasename(mapName) then
        return
    end

    local status = self:GetNavmeshStatus()
    if status.error then
        self:Fail(state, status.error)
        return
    end

    local generated = state.generatedNavmesh
    if type(generated) ~= "table" or generated.map ~= status.map or (tonumber(generated.areaCount) or 0) <= 0 then
        self:Fail(state, "navmesh generation result was lost before save verification")
        return
    end

    status.areaCount = math.floor(tonumber(generated.areaCount) or 0)
    status.generatedAt = generated.generatedAt
    status.persistenceVerified = status.navFileExists == true
    if not status.persistenceVerified then
        status.persistenceWarning = "nav areas exist in memory but no mounted .nav file was found; reload verification is required"
        status.wireframeExportError = "wireframe export requires a persisted navmesh"
    else
        local exported, exportPath = self:ExportNavmeshWireframe(status)
        if not exported then
            self:Fail(state, "navmesh wireframe export failed: " .. tostring(exportPath))
            return
        end
        status.wireframeExportPath = exportPath
    end
    self:WriteNavmeshStatus(status)
    state.navmeshResults = state.navmeshResults or {}
    state.navmeshResults[mapName] = status
    state.generatedNavmesh = nil
    self:WriteNavmeshValidation(state)
    if status.persistenceVerified then
        self:Notify("[ZombieSim] Saved " .. tostring(status.areaCount) .. " nav areas for " .. mapName .. ".")
    else
        self:Notify("[ZombieSim] Generated " .. tostring(status.areaCount) .. " nav areas for " .. mapName .. "; persistence is unverified, continuing batch.")
    end
    self:Advance(state)
end

function MapBatch:PollWireframeExport()
    local state = self:LoadState()
    if not state or not state.active or state.operation ~= "wireframes" or state.phase ~= "exporting-wireframe" then
        return
    end

    local mapName = self:GetCurrentMap(state)
    if not mapName or mapBasename(game.GetMap()) ~= mapBasename(mapName) then
        return
    end

    local status = self:GetNavmeshStatus()
    if status.error then
        self:Fail(state, status.error)
        return
    end
    if not status.navFileExists then
        self:RecordWireframeUnavailable(state, status, "mounted navmesh file is unavailable")
        return
    end
    if status.generating or not status.loaded then
        local startedAt = tonumber(state.wireframeExportStartedAt) or os.time()
        if os.time() - startedAt > navmeshWireframeLoadTimeoutSeconds then
            self:RecordWireframeUnavailable(state, status, "navmesh did not load within " .. navmeshWireframeLoadTimeoutSeconds .. " seconds")
            return
        end
        timer.Simple(navmeshPollInterval, function()
            MapBatch:PollWireframeExport()
        end)
        return
    end
    if status.areaCount <= 0 then
        self:RecordWireframeUnavailable(state, status, "mounted navmesh has no usable areas")
        return
    end

    local exported, exportPath = self:ExportNavmeshWireframe(status)
    if not exported then
        self:Fail(state, "navmesh wireframe export failed: " .. tostring(exportPath))
        return
    end
    status.persistenceVerified = true
    status.wireframeExportPath = exportPath
    self:WriteNavmeshStatus(status)
    state.navmeshResults = state.navmeshResults or {}
    state.navmeshResults[mapName] = status
    self:WriteNavmeshValidation(state)
    self:Notify("[ZombieSim] Exported " .. tostring(status.areaCount) .. " nav areas for " .. mapName .. ".")
    self:Advance(state)
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
        self:WriteNavmeshValidation(state)
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

    self:Notify("[ZombieSim] " .. state.operation .. " " .. state.index .. "/" .. #state.queue .. ": " .. mapName)
    if state.operation == "cubemaps" then
        state.phase = "awaiting-cubemap-reload"
        self:SaveState(state)
        self:Notify("[ZombieSim] Run buildcubemaps in your console. After its reload, run zombiesim_map_batch_next to load the next map.")
    elseif state.operation == "navmeshes" then
        self:StartNavmeshGeneration(state)
    else
        state.phase = "exporting-wireframe"
        state.wireframeExportStartedAt = os.time()
        self:SaveState(state)
        self:PollWireframeExport()
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

function MapBatch:Start(operation, requestedMap)
    local queue, queueError = self:BuildQueue(operation ~= "navmeshes" and operation ~= "wireframes")
    if not queue then
        print("[ZombieSim] Could not start map batch: " .. queueError)
        return
    end

    if operation == "navmeshes" then
        local missingQueue = {}
        for _, mapName in ipairs(queue) do
            if not file.Exists("maps/" .. mapName .. ".nav", "GAME") then
                table.insert(missingQueue, mapName)
            end
        end
        queue = missingQueue
        if #queue == 0 then
            print("[ZombieSim] Every ordinary city map already has a navmesh in the active profile.")
            return
        end
    end

    if operation == "wireframes" then
        local availableQueue = {}
        for _, mapName in ipairs(queue) do
            if file.Exists("maps/" .. mapName .. ".nav", "GAME") then
                table.insert(availableQueue, mapName)
            end
        end
        queue = availableQueue
        if #queue == 0 then
            print("[ZombieSim] No existing navmeshes are available for wireframe export in the active profile.")
            return
        end
    end

    if requestedMap and requestedMap ~= "" then
        local selectedMap
        local normalizedRequest = string.lower(requestedMap)
        for _, mapName in ipairs(queue) do
            if normalizedRequest == string.lower(mapName) or normalizedRequest == mapBasename(mapName) then
                selectedMap = mapName
                break
            end
        end
        if not selectedMap then
            print("[ZombieSim] Requested map is not an ordinary city-cell map in the active profile: " .. requestedMap)
            return
        end
        queue = { selectedMap }
    end

    local state = {
        active = true,
        completed = 0,
        index = 1,
        operation = operation,
        phase = "queued",
        profile = ZM_World.ActiveProfile,
        runtimeRevision = getRuntimeRevision(),
        queue = queue,
        navmeshResults = (operation == "navmeshes" or operation == "wireframes") and {} or nil,
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
    if state.phase == "generating-navmesh" and mapBasename(game.GetMap()) == mapBasename(self:GetCurrentMap(state)) then
        self:PollNavmeshGeneration()
        return
    end
    if state.phase == "exporting-wireframe" and mapBasename(game.GetMap()) == mapBasename(self:GetCurrentMap(state)) then
        self:PollWireframeExport()
        return
    end
    if state.phase == "saving-navmesh" and mapBasename(game.GetMap()) == mapBasename(self:GetCurrentMap(state)) then
        timer.Simple(loadDelaySeconds, function()
            MapBatch:VerifySavedNavmesh()
        end)
        return
    end
    if state.phase == "failed" then
        self:Notify("[ZombieSim] " .. state.operation .. " batch failed: " .. tostring(state.error) .. ". Run zombiesim_map_batch_retry or zombiesim_map_batch_cancel.")
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

concommand.Add("zombiesim_generate_navmeshes", function(ply, _, arguments)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can start a map batch.")
        return
    end
    if #arguments > 1 then
        print("[ZombieSim] Usage: zombiesim_generate_navmeshes [mapName]")
        return
    end
    MapBatch:Start("navmeshes", arguments[1])
end)

concommand.Add("zombiesim_export_navmesh_wireframes", function(ply, _, arguments)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can start a map batch.")
        return
    end
    if #arguments > 1 then
        print("[ZombieSim] Usage: zombiesim_export_navmesh_wireframes [mapName]")
        return
    end
    MapBatch:Start("wireframes", arguments[1])
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
    if state.operation == "navmeshes" then
        print("[ZombieSim] Navmesh batches advance automatically after navmesh.Save succeeds.")
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
        if state and state.active and state.operation == "navmeshes" then
            print("[ZombieSim] Navmesh batches advance automatically after navmesh.Save succeeds.")
            return
        end
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
    print("[ZombieSim] " .. state.operation .. ": " .. status .. "; " .. state.completed .. "/" .. #state.queue .. " complete; error " .. tostring(state.error or "none") .. ".")
end)

concommand.Add("zombiesim_map_batch_retry", function(ply)
    if not MapBatch:CanUse(ply) then
        return
    end

    local state = MapBatch:LoadState()
    if not state or not state.active or state.phase ~= "failed" then
        print("[ZombieSim] No failed map batch step is available to retry.")
        return
    end

    state.phase = "queued"
    state.error = nil
    state.retryCount = (state.retryCount or 0) + 1
    MapBatch:SaveState(state)
    MapBatch:GoToCurrent(state, true)
end)

concommand.Add("zombiesim_navmesh_status", function(ply)
    if not MapBatch:CanUse(ply) then
        print("[ZombieSim] Only admins can inspect navmesh status.")
        return
    end

    local status = MapBatch:GetNavmeshStatus()
    MapBatch:WriteNavmeshStatus(status)
    print(string.format(
        "[ZombieSim] Navmesh: map %s; profile %s; BSP %s; file %s; loaded %s; generating %s; areas %s; error %s.",
        tostring(status.map),
        tostring(status.profile),
        tostring(status.bspExists),
        tostring(status.navFileExists),
        tostring(status.loaded),
        tostring(status.generating),
        tostring(status.areaCount or 0),
        tostring(status.error or "none")
    ))
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

local nextNavmeshPollAt = 0
hook.Add("Think", "ZombieSim.PollNavmeshBatch", function()
    if CurTime() < nextNavmeshPollAt then
        return
    end
    nextNavmeshPollAt = CurTime() + navmeshPollInterval
    MapBatch:PollNavmeshGeneration()
end)