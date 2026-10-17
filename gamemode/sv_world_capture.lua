// Preview-only, bounded maintenance jobs; nav-only MapBatch state is never modified.
AddCSLuaFile("world_capture/sh_contract.lua")
AddCSLuaFile("sh_cell_health_contract.lua")
ZM_WorldCapture = ZM_WorldCapture or {}
local Capture = ZM_WorldCapture
local Contract = include("world_capture/sh_contract.lua")
local CellHealthContract = include("sh_cell_health_contract.lua")()
local statePath = "zombiesim/world_capture_state.json"
local cubemapConfirmationsPath = "zombiesim/cubemap_confirmations_preview.json"
local fields = {"XP", "Level", "MaxLevel", "Difficulty", "CellX", "CellY", "CurrentSafeZoneId",
    "SkillPoints", "Cash", "Health", "Stamina", "Hunger", "Thirst", "Job"}
local boot = tostring(os.time()) .. "-" .. tostring(SysTime())
local state
local requestSent
local arrivedAt

local function nativeNavBusy()
    return navmesh and navmesh.IsGenerating and navmesh.IsGenerating() == true
end

function Capture:IsActive()
    return state ~= nil and state.active == true
end

util.AddNetworkString("ZM.WorldCapture.Request")
util.AddNetworkString("ZM.WorldCapture.Result")
util.AddNetworkString("ZM.WorldCapture.Cancel")
util.AddNetworkString("ZM.WorldCapture.CancelRequest")
util.AddNetworkString("ZM.WorldCapture.CubemapPrompt")
util.AddNetworkString("ZM.WorldCapture.CubemapDecision")
util.AddNetworkString("ZM.CellHealth.CubemapStatusRequest")
util.AddNetworkString("ZM.CellHealth.CubemapStatus")
util.AddNetworkString("ZM.CellHealth.BatchStart")
util.AddNetworkString("ZM.CellHealth.BatchResult")

local function decode(path)
    local raw = file.Read(path, "DATA")
    local result = raw and util.JSONToTable(raw)
    if type(result) == "table" and result.schemaVersion == 1 and type(result.queue) == "table"
        and type(result.original) == "table" and type(result.revision) == "table" then return result end
end

state = decode(statePath) or decode(statePath .. ".previous.json")

local function save()
    file.CreateDir("zombiesim")
    file.CreateDir("zombiesim/world_captures/" .. state.runId)
    local json = assert(util.TableToJSON(state, true), "capture checkpoint serialization failed")
    local previous = file.Read(statePath, "DATA")
    if previous then file.Write(statePath .. ".previous.json", previous) end
    file.Write(statePath, json)
    file.Write("zombiesim/world_captures/" .. state.runId .. "/run.json", json)
    assert(file.Read(statePath, "DATA") == json, "capture checkpoint write failed")
end

local function loadCubemapConfirmations()
    local raw = file.Read(cubemapConfirmationsPath, "DATA")
    if not raw then
        return {schemaVersion = 1, profile = "preview", maps = {}}
    end
    local data = util.JSONToTable(raw)
    if type(data) ~= "table" or data.schemaVersion ~= 1 or data.profile ~= "preview"
        or type(data.maps) ~= "table" then
        return nil, "Cubemap confirmation data is invalid."
    end
    for mapName, record in pairs(data.maps) do
        if type(mapName) ~= "string" or not mapName:match("^[%w_%-]+$")
            or mapName ~= string.lower(mapName) or type(record) ~= "table"
            or record.confirmed ~= true or type(record.confirmedAt) ~= "number" then
            return nil, "Cubemap confirmation data contains an invalid map record."
        end
    end
    return data
end

local function saveCubemapConfirmations(data)
    local json = util.TableToJSON(data, true)
    if not json then return false, "Cubemap confirmations could not be serialized." end
    file.CreateDir("zombiesim")
    file.Write(cubemapConfirmationsPath, json)
    if file.Read(cubemapConfirmationsPath, "DATA") ~= json then
        return false, "Cubemap confirmation write failed read-back validation."
    end
    return true
end

local function sendCubemapStatus(target)
    local confirmations, failure = loadCubemapConfirmations()
    local encoded = confirmations and util.TableToJSON(confirmations.maps, false) or nil
    if not encoded or #encoded > 60000 then
        net.Start("ZM.CellHealth.CubemapStatus")
            net.WriteBool(false)
            net.WriteString(failure or "Cubemap confirmation response is too large.")
        net.Send(target)
        return
    end
    net.Start("ZM.CellHealth.CubemapStatus")
        net.WriteBool(true)
        net.WriteString(encoded)
    net.Send(target)
end

local function sendCellHealthBatchResult(target, success, message)
    net.Start("ZM.CellHealth.BatchResult")
        net.WriteBool(success == true)
        net.WriteString(tostring(message or ""))
    net.Send(target)
end

local function owner()
    if not state then return end
    for _, target in ipairs(player.GetHumans()) do
        if target:SteamID64() == state.original.steamId64
            and target:GetCharacterKey() == state.original.characterKey
            and target.ZM_PersistentStateLoaded == true then return target end
    end
end

local function sendCubemapPrompt(target, stage, job)
    local encoded = util.TableToJSON({
        runId = state.runId,
        map = job.map,
        stage = stage
    }, false)
    if not encoded then
        Capture:Restore("failed", "cubemap prompt could not be serialized")
        return false
    end
    net.Start("ZM.WorldCapture.CubemapPrompt")
        net.WriteString(encoded)
    net.Send(target)
    return true
end

local function mapKey(mapName)
    return string.lower(string.match(mapName or "", "([^/]+)$") or mapName or "")
end

local function revisionMatches()
    if not ZM_World:IsLoaded() then return false end
    return Contract.Matches(state.revision, Contract.InstalledRevision(ZM_World:GetData().world, ZM_World.ActiveProfile, file, util))
end

local function loadedMap(path)
    return string.lower(game.GetMap()) == string.lower(string.match(path, "([^/]+)$") or path)
end

local function protect(target)
    target:Freeze(true)
end

local function setCore(target, data)
    for _, key in ipairs(fields) do
        if key == "CurrentSafeZoneId" then
            target[key] = data[key] ~= "NULL" and data[key] or nil
        elseif key == "Job" then target[key] = data[key]
        elseif key ~= "Health" then target[key] = tonumber(data[key]) end
    end
    target.SavedHealth = tonumber(data.Health) or 100
    target:SetHealth(target.SavedHealth)
    target:SetNetworkPlayerData()
    target:SendPlayerData()
end

local function restoreRow()
    local ok, failure = ZM_SetPlayerData(state.original.characterKey, "preview", state.original.core, "world capture restoration")
    if not ok then return false, failure end
    local actual = ZM_GetPlayerData(state.original.characterKey, "preview")
    for _, key in ipairs(fields) do
        local expected = state.original.core[key]
        local value = actual and actual[key]
        if key == "CurrentSafeZoneId" then
            expected = (expected == "NULL" or expected == "") and nil or expected
            value = (value == "NULL" or value == "") and nil or value
        end
        if key == "Job" or key == "CurrentSafeZoneId" then
            if value ~= expected then return false, "restoration mismatch: " .. key end
        elseif tonumber(value) ~= tonumber(expected) then return false, "restoration mismatch: " .. key end
    end
    return true
end

local function changelevel(path, phase)
    if type(path) ~= "string" or not path:match("^[%w_/%-]+$")
        or not file.Exists("maps/" .. path .. ".bsp", "GAME") then return false, "destination BSP unavailable" end
    state.phase, state.transitionBoot, state.phaseStartedAt = phase, boot, os.time()
    requestSent, arrivedAt = nil, nil
    save()
    game.ConsoleCommand("changelevel " .. path .. "\n")
    return true
end

function Capture:Restore(outcome, failure)
    if not state or state.active ~= true then return false, "no active capture run" end
    state.outcome, state.error = outcome, failure
    local target = owner()
    if ZM_World.ActiveProfile ~= "preview" then
        state.phase = "restore-blocked"
        state.error = "restore requires preview profile; original snapshot retained"
        save()
        return false, state.error
    end
    if nativeNavBusy() then
        state.phase, state.error = "restore-blocked", "native nav generation must stop before map/pose restoration"
        if target then target:Freeze(state.original.frozen) end
        save()
        return false, state.error
    end
    if target then setCore(target, state.original.core) end
    local ok, reason = restoreRow()
    if not ok then
        state.phase, state.error = "restore-blocked", reason
        save()
        return false, reason
    end
    if not target then
        state.phase, state.error = "restore-blocked", "original owner/character must reconnect to finish map/pose restoration"
        save()
        return false, state.error
    end
    local travelled, problem = changelevel(state.original.mapPath, "restoring")
    if not travelled then
        state.phase, state.error = "restore-blocked", problem
        target:Freeze(state.original.frozen)
        save()
    end
    return travelled, problem
end

local function fail(reason)
    Capture:Restore("failed", tostring(reason))
end

local function sendRequest(target, job)
    state.token = state.runId .. "-" .. state.index .. "-" .. state.variantIndex .. "-" .. tostring(SysTime())
    state.phase, state.phaseStartedAt = "capturing", os.time()
    save()
    net.Start("ZM.WorldCapture.Request")
    net.WriteString(util.TableToJSON({
        runId = state.runId, token = state.token, revision = state.revision,
        cell = job, variant = Contract.Variants[state.variantIndex]
    }))
    net.Send(target)
    requestSent = state.token
end

local function validateNav(job)
    local status = ZM_MapBatch:GetNavmeshStatus()
    if status.error or status.generating or not status.loaded or not status.navFileExists or status.areaCount <= 0 then
        return false, status.error or "saved navmesh failed fresh-load validation"
    end
    state.navmeshes[job.map] = {
        map = job.map, areaCount = status.areaCount, persistenceVerified = true,
        reloadValidated = true, checkedAt = os.time(), revision = state.revision
    }
    save()
    return true
end

local function beginNav(job)
    if not ZM_MapBatch or not navmesh.BeginGeneration or not navmesh.Save then
        return false, "navmesh maintenance APIs unavailable"
    end
    local status = ZM_MapBatch:GetNavmeshStatus()
    if status.generating then return false, "another nav generation is running" end
    // Existing mounted meshes are validated in this fresh cell load rather than rebuilt.
    if status.navFileExists then return validateNav(job) end
    local seed, failure = ZM_MapBatch:AddNavmeshSpawnSeed()
    if not seed then return false, failure end
    state.phase, state.phaseStartedAt, state.navObserved = "nav-generating", os.time(), false
    save()
    local ok, reason = pcall(navmesh.BeginGeneration)
    return ok, reason
end

local function wantsNav(job)
    if state.cellHealthBatch then return job.doNav == true end
    return state.withNav == true
end

local function wantsPhotos(job)
    if state.cellHealthBatch then return job.doPhotos == true end
    return state.withPhotos ~= false
end

local function wantsCubemaps(job)
    return state.withCubemaps == true and job.doCubemaps == true
end

local function advanceJob()
    state.index, state.variantIndex, state.phase = state.index + 1, 1, "next"
    requestSent = nil
    save()
end

local function continueLoadedJob(target, job)
    state.cubemapResults = state.cubemapResults or {}
    local key = mapKey(job.map)
    if wantsCubemaps(job) and state.cubemapResults[key] == nil then
        state.phase = "awaiting-cubemap-run"
        save()
        sendCubemapPrompt(target, "run", job)
        return
    end
    if wantsPhotos(job) then
        sendRequest(target, job)
    else
        advanceJob()
    end
end

function Capture:Tick()
    if not state or not state.active or not ZM_World:IsLoaded() then return end
    if state.phase == "restore-blocked" then return end
    local target = owner()
    if not IsValid(target) then return end
    if #player.GetHumans() ~= 1 then fail("maintenance requires exactly one human"); return end
    if ZM_World.ActiveProfile ~= "preview" then
        self:Restore("failed", "profile changed during capture")
        return
    end
    protect(target)
    if state.phase == "restoring" then
        if state.transitionBoot == boot then
            if os.time() - state.phaseStartedAt > 60 then state.phase = "restore-blocked"; save() end
            return
        end
        if not loadedMap(state.original.mapPath) then fail("restoration loaded wrong map"); return end
        arrivedAt = arrivedAt or RealTime()
        if RealTime() - arrivedAt < 5 then return end
        setCore(target, state.original.runtimeCore)
        target:SetPos(Vector(unpack(state.original.position)))
        target:SetEyeAngles(Angle(unpack(state.original.angles)))
        target:SetMoveType(state.original.moveType)
        target:Freeze(state.original.frozen)
        local ok, reason = restoreRow()
        if not ok then state.phase, state.error = "restore-blocked", reason; save(); return end
        state.active, state.phase, state.restoredAt = false, state.outcome, os.time()
        state.restorationVerified = target.CellX == state.original.runtimeCore.CellX
            and target.CellY == state.original.runtimeCore.CellY
            and target.CurrentSafeZoneId == state.original.runtimeCore.CurrentSafeZoneId
            and target:Health() == state.original.runtimeCore.Health
            and target:GetMoveType() == state.original.moveType
            and target:GetPos():DistToSqr(Vector(unpack(state.original.position))) < 1
            and target:IsFrozen() == state.original.frozen
        if not state.restorationVerified then
            state.active, state.phase, state.error = true, "restore-blocked", "runtime restoration did not match"
        end
        save()
        return
    end
    if not revisionMatches() then fail("authoritative profile/revision/bounds changed"); return end
    if nativeNavBusy() and state.phase ~= "nav-generating" and state.phase ~= "nav-saving" then
        fail("external native nav generation overlaps capture")
        return
    end
    local job = state.queue[state.index]
    if not job then self:Restore("complete"); return end
    if state.phase == "awaiting-cubemap-run" then
        if not loadedMap(job.mapPath) then fail("cubemap prompt left its active map"); return end
        return
    elseif state.phase == "awaiting-cubemap-success" then
        if state.cubemapPromptDeliveredBoot ~= boot then
            state.cubemapPromptDeliveredBoot = boot
            save()
            sendCubemapPrompt(target, "success", job)
        end
        return
    end
    if state.phase == "loading" or state.phase == "nav-reloading" then
        if state.transitionBoot == boot then
            if os.time() - state.phaseStartedAt > 60 then fail("changelevel did not complete") end
            return
        end
        if not loadedMap(job.mapPath) then fail("unexpected map after changelevel"); return end
        local x, y = ZM_World:GetWorldCoordinates(ZM_World:GetCellById(job.id))
        if target.CellX ~= x or target.CellY ~= y or target.CurrentSafeZoneId then
            fail("loaded survivor logical cell differs from queue"); return
        end
        arrivedAt = arrivedAt or RealTime()
        if RealTime() - arrivedAt < 5 then return end
        if state.phase == "nav-reloading" then
            local ok, reason = validateNav(job)
            if not ok then fail(reason); return end
            if state.cancelRequested then self:Restore("cancelled"); return end
        elseif wantsNav(job) then
            local ok, reason
            if state.navmeshes[job.map] then ok, reason = validateNav(job)
            else ok, reason = beginNav(job) end
            if not ok then fail(reason); return end
            if state.phase == "nav-generating" then return end
        end
        continueLoadedJob(target, job)
    elseif state.phase == "nav-generating" then
        local status = ZM_MapBatch:GetNavmeshStatus()
        local elapsed = os.time() - state.phaseStartedAt
        if elapsed > 300 then fail("nav generation timeout"); return end
        if status.error then fail(status.error); return end
        if status.generating then
            if not state.navObserved then state.navObserved = true; save() end
            return
        end
        if elapsed < 3 then return end
        if not state.navObserved or status.areaCount <= 0 then fail("nav generation not observed/no areas"); return end
        state.phase, state.phaseStartedAt = "nav-saving", os.time()
        save()
        local ok, reason = pcall(navmesh.Save)
        if not ok then fail(reason) end
    elseif state.phase == "nav-saving" then
        if os.time() - state.phaseStartedAt < 2 then return end
        if not file.Exists("maps/" .. job.mapPath .. ".nav", "GAME") then fail("nav save produced no mounted file"); return end
        local ok, reason = changelevel(job.mapPath, "nav-reloading")
        if not ok then fail(reason) end
    elseif state.phase == "capturing" then
        if state.token ~= requestSent then sendRequest(target, job) end
        if os.time() - state.phaseStartedAt > 75 then fail("client capture acknowledgement timeout") end
    elseif state.phase == "next" then
        local x, y = ZM_World:GetWorldCoordinates(ZM_World:GetCellById(job.id))
        local ok, reason = target:SetWorldCell(x, y)
        if not ok then fail(reason); return end
        local loaded, loadError = changelevel(job.mapPath, "loading")
        if not loaded then fail(loadError) end
    end
end

net.Receive("ZM.WorldCapture.Result", function(_, target)
    local raw = net.ReadString()
    if #raw > 16384 or not state or not state.active or state.phase ~= "capturing" or target ~= owner() then return end
    local result = util.JSONToTable(raw)
    local job = state.queue[state.index]
    local variant = Contract.Variants[state.variantIndex]
    if type(result) ~= "table" or result.runId ~= state.runId or result.token ~= state.token
        or result.cellId ~= job.id or result.variant ~= variant then return end
    if result.ok ~= true then
        state.lastClientFailure = result
        save()
        fail(result.error or "client capture failed")
        return
    end
    local path = Contract.OutputPath(state.runId, job.id, variant)
    local data = file.Read(path, "DATA")
    if result.ready ~= true or result.path ~= path or not Contract.Matches(state.revision, result.revision)
        or result.map ~= game.GetMap() or not Contract.ValidPNG(data, Contract.Size)
        or #data ~= result.bytes or util.SHA256(data) ~= result.sha256 then
        fail("client result/output identity, checksum or PNG validation failed"); return
    end
    state.results[variant][tostring(job.id)] = result
    state.completedResults = state.completedResults + 1
    state.variantIndex = state.variantIndex + 1
    if state.variantIndex > #Contract.Variants then
        advanceJob()
    else
        state.phase = "capturing"
        requestSent = nil
        save()
    end
end)

local function buildQueue(target, arguments, fullWorld)
    local queue, seen = {}, {}
    local function add(cell)
        if not cell or seen[cell.id] then return end
        local path = ZM_World:GetMapPath(cell)
        if not path or not path:match("^[%w_/%-]+$") or not file.Exists("maps/" .. path .. ".bsp", "GAME") then
            error("ordinary cell BSP is not staged")
        end
        local x, y = ZM_World:GetWorldCoordinates(cell)
        queue[#queue + 1] = {id = cell.id, x = cell.x, y = cell.y, worldX = x, worldY = y, map = cell.map, mapPath = path}
        seen[cell.id] = true
    end
    local current = target:GetWorldCell()
    if fullWorld then
        if arguments[1] ~= "preview" or tonumber(arguments[2]) ~= #ZM_World:GetData().cells or arguments[3] then
            error("full rollout requires explicit preview scope and authoritative cell count")
        end
        for _, cell in ipairs(ZM_World:GetData().cells) do add(cell) end
        table.sort(queue, function(a, b) return a.id < b.id end)
    elseif not arguments[1] or arguments[1] == "" or arguments[1] == "current" then add(current)
    elseif arguments[1] == "pilot" then
        if not current then error("pilot needs a deployed ordinary-cell survivor") end
        for dy = 0, 1 do for dx = 0, 1 do add(ZM_World:GetCell(current.x + dx, current.y + dy)) end end
        for _, cell in ipairs(ZM_World:GetData().cells) do
            if cell.waterSides and #cell.waterSides > 0 then add(cell); break end
        end
        for _, cell in ipairs(ZM_World:GetData().cells) do
            if cell.transport and cell.transport.bridge == true then add(cell); break end
        end
    else
        for _, pair in ipairs(arguments) do
            local x, y = pair:match("^(-?%d+),(-?%d+)$")
            if not x then error("use current, pilot, or at most eight logical x,y pairs; full-world capture is gated") end
            local gx, gy = ZM_World:GetGridCoordinates(tonumber(x), tonumber(y))
            local cell = gx and ZM_World:GetCell(gx, gy)
            if not cell then error("logical cell outside authoritative world") end
            add(cell)
        end
    end
    if #queue == 0 or (not fullWorld and #queue > 8) then error("capture queue must contain one to eight ordinary cells") end
    return queue
end

local function buildCellHealthQueue(selection)
    if type(selection) ~= "table" then return nil, "Cell Health batch selection is invalid." end
    local worldData = ZM_World:GetData()
    local manifestPath = "data_static/world_captures_preview.json"
    local manifestRaw = file.Read(manifestPath, "GAME")
    local manifest, manifestError
    if not manifestRaw then
        manifestError = "Captured-world manifest is not mounted."
    else
        manifest = util.JSONToTable(manifestRaw)
        if type(manifest) ~= "table" then manifestError = "Captured-world manifest is invalid JSON." end
    end

    local confirmations, confirmationError = loadCubemapConfirmations()
    if not confirmations then return nil, confirmationError end
    local files = {
        Exists = function(path) return file.Exists(path, "GAME") end,
        Size = function(path) return file.Size(path, "GAME") end,
        Read = function(path) return file.Read(path, "GAME") end
    }
    local snapshot, snapshotError = CellHealthContract.BuildSnapshot(
        worldData, manifest, files, manifestError, confirmations.maps
    )
    if not snapshot then return nil, snapshotError end
    local selectedJobs, selectionError = CellHealthContract.BuildBatchSelection(snapshot, selection)
    if not selectedJobs then return nil, selectionError end
    if #selectedJobs == 0 then return nil, "No unhealthy cells for the selected artifacts." end

    local cellsById = {}
    for _, cell in ipairs(worldData.cells) do cellsById[tonumber(cell.id)] = cell end
    local queue = {}
    local firstJobByMap, navByMap, cubemapsByMap = {}, {}, {}
    for _, selected in ipairs(selectedJobs) do
        local id = tonumber(selected.id)
        if not id or id ~= math.floor(id) then return nil, "Cell Health returned an invalid cell id." end
        local cell = cellsById[id]
        if not cell then return nil, "Cell Health selected a cell outside the authoritative preview world." end
        local mapPath = ZM_World:GetMapPath(cell)
        if not mapPath or not mapPath:match("^[%w_/%-]+$") or
            not file.Exists("maps/" .. mapPath .. ".bsp", "GAME") then
            return nil, "A selected preview cell does not have a staged BSP."
        end
        local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
        local job = {
            id = id, x = cell.x, y = cell.y, worldX = worldX, worldY = worldY,
            map = cell.map, mapPath = mapPath,
            doNav = selected.navmesh == true,
            doPhotos = selected.photos == true,
            doCubemaps = selected.cubemaps == true
        }
        local key = string.lower(mapPath)
        firstJobByMap[key] = firstJobByMap[key] or job
        navByMap[key] = navByMap[key] or job.doNav
        cubemapsByMap[key] = cubemapsByMap[key] or job.doCubemaps
        queue[#queue + 1] = job
    end

    for key, job in pairs(firstJobByMap) do
        job.doNav = navByMap[key] == true
        job.doCubemaps = cubemapsByMap[key] == true
    end
    for _, job in ipairs(queue) do
        local key = string.lower(job.mapPath)
        if firstJobByMap[key] ~= job then
            job.doNav, job.doCubemaps = false, false
        end
    end

    local filtered = {}
    for _, job in ipairs(queue) do
        if job.doNav or job.doPhotos or job.doCubemaps then
            filtered[#filtered + 1] = job
        end
    end
    return filtered
end

function Capture:Start(target, arguments, withNav, fullWorld, selection, deferTick)
    if state and state.active then return false, "existing run requires cancel/status/restoration first" end
    if not ZM_World:IsLoaded() then return false, "authoritative world data is not ready" end
    if #player.GetHumans() ~= 1 or not IsValid(target) or not target:IsAdmin() or not target:Alive()
        or target.ZM_PersistentStateLoaded ~= true or ZM_World.LauncherMapProfiles[game.GetMap()] then
        return false, "one deployed living preview admin is required"
    end
    if nativeNavBusy() or (ZM_MapBatch and ZM_MapBatch:IsActive()) or GAMEMODE.PlayerWorldMapTransitionQueued
        or GAMEMODE.OriginSafeZoneTransitionQueued then return false, "another maintenance/transition is active" end
    local revision, failure = Contract.InstalledRevision(ZM_World:GetData().world, ZM_World.ActiveProfile, file, util)
    if not revision then return false, failure end
    local queue, queueError
    if selection then
        local built
        built, queue, queueError = pcall(buildCellHealthQueue, selection)
        if not built then return false, tostring(queue) end
    else
        local built
        built, queue = pcall(buildQueue, target, arguments, fullWorld)
        if not built then return false, queue end
    end
    if not queue then return false, queueError end
    local key = target:GetCharacterKey()
    local core, coreError = ZM_GetPlayerData(key, "preview")
    if not core then return false, coreError or "no persistent survivor row" end
    local runtime = {}
    for _, field in ipairs(fields) do
        runtime[field] = field == "Health" and target:Health() or target[field]
    end
    local originalMap = target.CurrentSafeZoneId and ZM_World:GetPlayerCurrentSafeZoneMap(target)
        or ZM_World:GetMapPath(target:GetWorldCell())
    if not originalMap or not loadedMap(originalMap) then return false, "original survivor/map identity cannot be restored safely" end
    local position, angles = target:GetPos(), target:EyeAngles()
    local expectedCaptureResults = 0
    for _, job in ipairs(queue) do
        local captures = true
        if selection then captures = job.doPhotos == true end
        if captures then expectedCaptureResults = expectedCaptureResults + #Contract.Variants end
    end
    state = {
        schemaVersion = 1, runId = "preview_" .. os.time() .. "_" .. util.CRC(tostring(SysTime())),
        active = true, phase = "next", index = 1, variantIndex = 1, queue = queue,
        revision = revision, withNav = withNav == true, withPhotos = selection == nil or selection.photos == true,
        withCubemaps = selection ~= nil and selection.cubemaps == true, cellHealthBatch = selection ~= nil,
        selectedArtifacts = selection, fullWorld = fullWorld == true, navmeshes = {}, cubemapResults = {},
        results = {clear = {}, atmospheric = {}}, completedResults = 0, startedAt = os.time(),
        requiredCellCount = #ZM_World:GetData().cells, expectedCaptureResults = expectedCaptureResults,
        original = {
            steamId64 = target:SteamID64(), characterKey = key, core = core, runtimeCore = runtime,
            mapPath = originalMap, position = {position.x, position.y, position.z},
            angles = {angles.p, angles.y, angles.r}, frozen = target:IsFrozen(), moveType = target:GetMoveType()
        }
    }
    save()
    protect(target)
    if not deferTick then self:Tick() end
    local message
    if selection then
        message = string.format("Cell Health batch started: %d cell/map job(s), %d photo result(s), run %s.",
            #queue, expectedCaptureResults, state.runId)
        if expectedCaptureResults > 0 then
            message = message .. " After completion, use watch_world_capture.ps1 to merge/stage photos."
        end
    else
        message = (#queue > 8 and "full preview capture run started: " or "bounded capture run started: ") .. state.runId
    end
    return true, message
end

function Capture:StartCellHealth(target, selection, deferTick)
    return self:Start(target, {}, false, false, selection, deferTick)
end

local function cancelRun(target)
    if not state or target ~= owner() then return false, "original batch owner is required" end
    if state.phase == "nav-generating" or state.phase == "nav-saving" then
        state.cancelRequested = true
        save()
        return true, "cancellation checkpointed; restoration follows native nav save/reload boundary"
    end
    return Capture:Restore("cancelled")
end

net.Receive("ZM.CellHealth.CubemapStatusRequest", function(_, target)
    if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then return end
    sendCubemapStatus(target)
end)

net.Receive("ZM.CellHealth.BatchStart", function(_, target)
    if not IsValid(target) then return end
    if not target:IsAdmin() then
        sendCellHealthBatchResult(target, false, "Cell Health batches require an admin.")
        return
    end
    local raw = net.ReadString()
    if type(raw) ~= "string" or #raw > 2048 then
        sendCellHealthBatchResult(target, false, "Cell Health batch request is too large or invalid.")
        return
    end
    local request = util.JSONToTable(raw)
    if type(request) ~= "table" or request.schemaVersion ~= 1 or type(request.selection) ~= "table" then
        sendCellHealthBatchResult(target, false, "Cell Health batch request is invalid.")
        return
    end
    local selection = request.selection
    for _, key in ipairs({"navmesh", "photos", "cubemaps"}) do
        if type(selection[key]) ~= "boolean" then
            sendCellHealthBatchResult(target, false, "Cell Health batch selection is invalid: " .. key)
            return
        end
    end
    for key in pairs(selection) do
        if key ~= "navmesh" and key ~= "photos" and key ~= "cubemaps" then
            sendCellHealthBatchResult(target, false, "Cell Health batch selection contains an unsupported option.")
            return
        end
    end

    local started, message = Capture:StartCellHealth(target, selection, true)
    sendCellHealthBatchResult(target, started, message)
    if started then Capture:Tick() end
end)

net.Receive("ZM.WorldCapture.CancelRequest", function(_, target)
    local cancelled, failure = cancelRun(target)
    if not cancelled and IsValid(target) then
        target:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] " .. tostring(failure) .. "\n")
    end
end)

net.Receive("ZM.WorldCapture.CubemapDecision", function(_, target)
    local runId = net.ReadString()
    local requestedMap = net.ReadString()
    local success = net.ReadBool()
    local job = state and state.queue[state.index]
    if not state or not state.active or state.phase ~= "awaiting-cubemap-success"
        or target ~= owner() or runId ~= state.runId or not job
        or mapKey(requestedMap) ~= mapKey(job.map) or not loadedMap(job.mapPath) then return end

    local confirmations, confirmationError = loadCubemapConfirmations()
    if not confirmations then
        Capture:Restore("failed", confirmationError)
        return
    end
    local key = mapKey(job.map)
    if success then
        confirmations.maps[key] = {confirmed = true, confirmedAt = os.time()}
    else
        confirmations.maps[key] = nil
    end
    local saved, saveError = saveCubemapConfirmations(confirmations)
    if not saved then
        Capture:Restore("failed", saveError)
        return
    end

    state.cubemapResults = state.cubemapResults or {}
    state.cubemapResults[key] = success == true
    state.phase, state.cubemapPromptDeliveredBoot = "loading", nil
    save()
    sendCubemapStatus(target)
    Capture:Tick()
end)

function Capture:Continue(target, arguments, extend)
    if not state or state.active or not state.restorationVerified then return false, "restore interrupted run before retry/extend" end
    if target ~= owner() or not revisionMatches() then return false, "original owner and exact revision are required" end
    if #player.GetHumans() ~= 1 or not target:IsAdmin() or not target:Alive()
        or nativeNavBusy() or (ZM_MapBatch and ZM_MapBatch:IsActive()) or GAMEMODE.PlayerWorldMapTransitionQueued
        or GAMEMODE.OriginSafeZoneTransitionQueued then return false, "maintenance/transition or survivor is not ready" end
    local currentMap = target.CurrentSafeZoneId and ZM_World:GetPlayerCurrentSafeZoneMap(target)
        or ZM_World:GetMapPath(target:GetWorldCell())
    if not currentMap or not loadedMap(currentMap) then return false, "cannot snapshot current survivor map" end
    local core, coreError = ZM_GetPlayerData(state.original.characterKey, "preview")
    if not core then return false, coreError or "cannot snapshot current survivor row" end
    if extend then
        if state.cellHealthBatch then
            return false, "Cell Health batches are selected from the current artifact snapshot; start a new batch after restoration."
        end
        local ok, additions = pcall(buildQueue, target, arguments)
        if not ok then return false, additions end
        local seen = {}
        for _, job in ipairs(state.queue) do seen[job.id] = true end
        local added = 0
        for _, job in ipairs(additions) do
            if not seen[job.id] then state.queue[#state.queue + 1] = job; added = added + 1 end
        end
        if added == 0 then return false, "no new logical cells; existing results are retained" end
        state.expectedCaptureResults = (tonumber(state.expectedCaptureResults)
            or (#state.queue - added) * #Contract.Variants) + added * #Contract.Variants
    elseif state.index > #state.queue then return false, "run queue is complete; extend with a bounded new selection" end
    // Each explicit continuation has a fresh restoration baseline; intervening gameplay must not be rolled back.
    state.original.core, state.original.runtimeCore, state.original.mapPath = core, {}, currentMap
    for _, field in ipairs(fields) do
        state.original.runtimeCore[field] = field == "Health" and target:Health() or target[field]
    end
    local position, angles = target:GetPos(), target:EyeAngles()
    state.original.position, state.original.angles = {position.x, position.y, position.z}, {angles.p, angles.y, angles.r}
    state.original.frozen, state.original.moveType = target:IsFrozen(), target:GetMoveType()
    state.active, state.phase, state.restorationVerified = true, "next", false
    state.error, state.cancelRequested, requestSent, arrivedAt = nil, nil, nil, nil
    save()
    protect(target)
    self:Tick()
    return true, "resuming existing capture run without repeating completed results: " .. state.runId
end

ZM_Util.RegisterCommands({
    zombiesim_world_capture_start = "Capture current, pilot, or up to eight logical x,y pairs (preview only).",
    zombiesim_world_maintenance_start = "Validate/generate/reload nav then capture each bounded preview cell.",
    zombiesim_world_capture_full = "Fresh capture-only rollout: explicit preview <authoritative cell count>.",
    zombiesim_world_maintenance_full = "Full sequential nav/capture rollout: explicit preview <authoritative cell count>.",
    zombiesim_world_capture_status = "Report persistent capture checkpoint and restoration status.",
    zombiesim_world_capture_cancel = "Cancel capture and restore the original survivor/map.",
    zombiesim_world_capture_retry = "Retry unfinished results in the same run after verified restoration.",
    zombiesim_world_capture_extend = "Append at most eight new logical cells to the same restored run."
}, function(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command) then return false, "admin required" end
    if command == "zombiesim_world_capture_status" then
        local json = state and util.TableToJSON(state, true) or "{}"
        ZM_Util.Print(caller, json)
        return true, json
    end
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not target then return false, "connected admin required" end
    if command == "zombiesim_world_capture_cancel" then
        net.Start("ZM.WorldCapture.Cancel"); net.Send(target)
        if state and (state.phase == "nav-generating" or state.phase == "nav-saving") then
            state.cancelRequested = true
            save()
            return true, "cancellation checkpointed; restoration follows native nav save/reload boundary"
        end
        return Capture:Restore("cancelled")
    end
    if command == "zombiesim_world_capture_retry" then
        return Capture:Continue(target, arguments, false)
    end
    if command == "zombiesim_world_capture_extend" then
        return Capture:Continue(target, arguments, true)
    end
    return Capture:Start(target, arguments,
        command == "zombiesim_world_maintenance_start" or command == "zombiesim_world_maintenance_full",
        command == "zombiesim_world_capture_full" or command == "zombiesim_world_maintenance_full")
end)

hook.Add("SetupPlayerVisibility", "ZM.WorldCapture.PVS", function(target)
    if state and state.active and target == owner() and state.phase ~= "restoring" then
        AddOriginToPVS(Vector(0, 0, state.revision.cameraZ))
    end
end)
hook.Add("InitPostEntity", "ZM.WorldCapture.CubemapReload", function()
    if not state or not state.active then return end
    local job = state.queue[state.index]
    if not job or not loadedMap(job.mapPath) then return end
    if state.phase == "awaiting-cubemap-run" then
        state.phase, state.phaseStartedAt, state.cubemapPromptDeliveredBoot =
            "awaiting-cubemap-success", os.time(), nil
        save()
    elseif state.phase == "awaiting-cubemap-success" then
        state.cubemapPromptDeliveredBoot = nil
        save()
    end
end)
hook.Add("StartCommand", "ZM.WorldCapture.FreezeInput", function(target, command)
    if state and state.active and target == owner() then command:ClearButtons(); command:ClearMovement() end
end)
hook.Add("EntityTakeDamage", "ZM.WorldCapture.ProtectSurvivor", function(target, damage)
    if state and state.active and target == owner() then damage:SetDamage(0); return true end
end)
timer.Create("ZM.WorldCapture.Queue", 0.5, 0, function()
    local ok, failure = xpcall(function() Capture:Tick() end, debug.traceback)
    if not ok and state and state.active then fail(failure) end
end)
