ZM_WalkerSim = ZM_WalkerSim or {}
local WalkerSim = ZM_WalkerSim

WalkerSim.ApiVersion = 3
WalkerSim.Config = WalkerSim.Config or {
    minimumGroupSize = 4,
    maximumGroupSize = 64,
    progressPerTick = 4,
    attractionDecayPermille = 920,
    safeZonePenalty = 100000,
    ticketLifetimeTicks = 20,
    maximumTicketsPerRequest = 12
}
WalkerSim.MaterializationConfig = WalkerSim.MaterializationConfig or {
    activeZombieCap = 64,
    requestLimitPerTick = 4,
    materializationRadius = 2400,
    playerExclusionRadius = 512,
    minimumZombieSeparation = 96,
    placementAttemptsPerTicket = 128,
    reconcileInterval = 0.25,
    requestRetrySeconds = 1,
    despawnGraceSeconds = 10
}
WalkerSim.ActiveProfile = WalkerSim.ActiveProfile or nil
WalkerSim.LastError = WalkerSim.LastError or nil
WalkerSim.SnapshotInterval = 0.5
WalkerSim.NextSnapshotAt = WalkerSim.NextSnapshotAt or 0
WalkerSim.NextTicketRequestLow = WalkerSim.NextTicketRequestLow or (os.time() % 4294967296)
WalkerSim.NextTicketRequestHigh = WalkerSim.NextTicketRequestHigh or 1
WalkerSim.IsShuttingDown = WalkerSim.IsShuttingDown or false
WalkerSim.Checkpoint = WalkerSim.Checkpoint or {}
WalkerSim.NextCheckpointAt = WalkerSim.NextCheckpointAt or 0
WalkerSim.RestoreReconciliation = WalkerSim.RestoreReconciliation or nil
WalkerSim.CheckpointExportPending = WalkerSim.CheckpointExportPending or false

util.AddNetworkString("ZM.WalkerSnapshot")
util.AddNetworkString("ZM.WalkerPopulation")

local function getNative()
    local native = rawget(_G, "ZM_WalkerNative")
    if type(native) ~= "table" then
        return nil, "optional walker module is not installed"
    end
    if native.ApiVersion ~= WalkerSim.ApiVersion then
        return nil, "walker module API version is incompatible"
    end
    if type(native.LoadWorldJson) ~= "function" or type(native.Start) ~= "function" or
        type(native.Stop) ~= "function" or type(native.GetStats) ~= "function" or
        type(native.GetHordeSummaries) ~= "function" or type(native.RequestSpawnTickets) ~= "function" or
        type(native.GetTicketSummaries) ~= "function" or type(native.AcknowledgeTicket) ~= "function" or
        type(native.RejectTicket) ~= "function" or type(native.ResolveTicket) ~= "function" or
        type(native.ExportCheckpoint) ~= "function" or type(native.ImportCheckpoint) ~= "function" or
        type(native.RequestCheckpointExport) ~= "function" or type(native.TakeCheckpointExport) ~= "function" then
        return nil, "walker module does not provide the Phase G API"
    end
    return native
end

local function isAdminOrServer(ply, command)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] " .. command .. " must be run by an in-game admin.\n")
        return false
    end
    return true
end

local function checkpointPaths(profile)
    if type(profile) ~= "string" or not string.match(profile, "^[%w_-]+$") then
        return nil
    end
    return {
        profile = profile,
        displayPath = "SQLite walker_checkpoints/" .. profile
    }
end

local checkpointSchema = "CREATE TABLE IF NOT EXISTS walker_checkpoints (profile TEXT PRIMARY KEY, checkpoint TEXT NOT NULL, metadata TEXT NOT NULL, savedAt INTEGER NOT NULL, rejectedAt INTEGER, rejectionReason TEXT)"

local function ensureCheckpointTable()
    local result = sql.Query(checkpointSchema)
    if result == false then
        return false, sql.LastError() or "could not create Walker checkpoint table"
    end
    return true
end

local function writeCheckpointStatus()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_checkpoint_status.json", util.TableToJSON(WalkerSim.Checkpoint, true) or "{}")
end

local function quarantineCheckpoint(paths, reason)
    sql.Query("UPDATE walker_checkpoints SET rejectedAt = " .. os.time() .. ", rejectionReason = " .. sql.SQLStr(reason) .. " WHERE profile = " .. sql.SQLStr(paths.profile))
    WalkerSim.Checkpoint.lastError = reason
    WalkerSim.Checkpoint.lastRejectedAt = os.time()
end

function WalkerSim:LoadCheckpoint(profile)
    local paths = checkpointPaths(profile)
    if not paths then
        return false, "active profile cannot be used for checkpoint storage"
    end
    local tableReady, tableError = ensureCheckpointTable()
    if not tableReady then
        return false, tableError
    end

    self.Checkpoint = {
        profile = profile,
        checkpointPath = paths.displayPath,
        restored = false,
        checkedAt = os.time()
    }
    local rows = sql.Query("SELECT checkpoint, metadata, rejectedAt, rejectionReason FROM walker_checkpoints WHERE profile = " .. sql.SQLStr(profile))
    if rows == false then
        return false, sql.LastError() or "could not read Walker checkpoint"
    end
    local row = rows and rows[1] or nil
    if not row then
        self.Checkpoint.lastResult = "no checkpoint"
        writeCheckpointStatus()
        return true, false
    end
    if tonumber(row.rejectedAt) and tonumber(row.rejectedAt) > 0 then
        self.Checkpoint.lastResult = "previously rejected"
        self.Checkpoint.lastError = row.rejectionReason or "checkpoint was previously rejected"
        writeCheckpointStatus()
        return true, false
    end

    local encodedCheckpoint = row.checkpoint
    local checkpoint = type(encodedCheckpoint) == "string" and util.Base64Decode(encodedCheckpoint) or nil
    if type(checkpoint) ~= "string" or checkpoint == "" then
        quarantineCheckpoint(paths, "checkpoint file is empty, unreadable, or invalid Base64")
        writeCheckpointStatus()
        return true, false
    end

    local metadata = type(row.metadata) == "string" and util.JSONToTable(row.metadata) or nil
    local requestIdLow = metadata and tonumber(metadata.nextTicketRequestLow) or nil
    local requestIdHigh = metadata and tonumber(metadata.nextTicketRequestHigh) or nil
    if requestIdLow and requestIdHigh and requestIdLow == math.floor(requestIdLow) and
        requestIdHigh == math.floor(requestIdHigh) and requestIdLow >= 0 and requestIdLow <= 4294967295 and
        requestIdHigh >= 0 and requestIdHigh <= 4294967295 then
        self.NextTicketRequestLow = requestIdLow
        self.NextTicketRequestHigh = math.max(1, requestIdHigh)
    end

    local native = getNative()
    local imported, importError = native.ImportCheckpoint(checkpoint)
    if imported ~= true then
        quarantineCheckpoint(paths, tostring(importError or "native checkpoint import failed"))
        self.Checkpoint.lastResult = "rejected"
        writeCheckpointStatus()
        return true, false
    end

    local stats = native.GetStats()
    self.Checkpoint.restored = true
    self.Checkpoint.lastResult = "restored"
    self.Checkpoint.byteLength = #checkpoint
    self.Checkpoint.encodedByteLength = #encodedCheckpoint
    self.Checkpoint.lastCheckpointTick = stats.Tick
    self.Checkpoint.lastCheckpointStateHash = stats.StateHash
    self.Checkpoint.lastSavedStateHash = stats.StateHash
    writeCheckpointStatus()
    return true, true
end

function WalkerSim:SaveCheckpoint(reason, completedCheckpoint)
    local native, nativeError = getNative()
    if not native then
        return false, nativeError
    end
    local profile = self.ActiveProfile
    local paths = checkpointPaths(profile)
    if not paths then
        return false, "active profile cannot be used for checkpoint storage"
    end

    local checkpoint = completedCheckpoint
    local checkpointError = nil
    if checkpoint == nil then
        checkpoint, checkpointError = native.ExportCheckpoint()
    end
    if type(checkpoint) ~= "string" or checkpoint == "" then
        local message = tostring(checkpointError or "native checkpoint export failed")
        self.Checkpoint.lastError = message
        self.Checkpoint.lastResult = "save failed"
        writeCheckpointStatus()
        return false, message
    end

    file.CreateDir("zombiesim")
    local encodedCheckpoint = util.Base64Encode(checkpoint)
    if type(encodedCheckpoint) ~= "string" or encodedCheckpoint == "" then
        local message = "could not Base64 encode the native checkpoint"
        self.Checkpoint.lastError = message
        self.Checkpoint.lastResult = "save failed"
        writeCheckpointStatus()
        return false, message
    end
    local stats = native.GetStats()
    local metadata = {
        profile = profile,
        savedAt = os.time(),
        reason = reason,
        byteLength = #checkpoint,
        encodedByteLength = #encodedCheckpoint,
        nextTicketRequestLow = self.NextTicketRequestLow,
        nextTicketRequestHigh = self.NextTicketRequestHigh,
        graphRevisionHash = stats.GraphRevisionHash,
        stateHash = stats.StateHash,
        tick = stats.Tick
    }
    local tableReady, tableError = ensureCheckpointTable()
    if not tableReady then
        self.Checkpoint.lastError = tableError
        self.Checkpoint.lastResult = "save failed"
        writeCheckpointStatus()
        return false, tableError
    end
    local saved = sql.Query(
        "INSERT OR REPLACE INTO walker_checkpoints (profile, checkpoint, metadata, savedAt, rejectedAt, rejectionReason) VALUES (" ..
        sql.SQLStr(profile) .. ", " .. sql.SQLStr(encodedCheckpoint) .. ", " ..
        sql.SQLStr(util.TableToJSON(metadata, false) or "{}") .. ", " .. metadata.savedAt .. ", NULL, NULL)"
    )
    if saved == false then
        local saveError = sql.LastError() or "could not save Walker checkpoint"
        self.Checkpoint.lastError = saveError
        self.Checkpoint.lastResult = "save failed"
        writeCheckpointStatus()
        return false, saveError
    end
    self.Checkpoint.profile = profile
    self.Checkpoint.checkpointPath = paths.displayPath
    self.Checkpoint.lastResult = "saved"
    self.Checkpoint.lastError = nil
    self.Checkpoint.lastSaveReason = reason
    self.Checkpoint.lastSavedAt = metadata.savedAt
    self.Checkpoint.byteLength = metadata.byteLength
    self.Checkpoint.encodedByteLength = metadata.encodedByteLength
    self.Checkpoint.lastCheckpointTick = metadata.tick
    self.Checkpoint.lastCheckpointStateHash = metadata.stateHash
    self.Checkpoint.lastSavedStateHash = metadata.stateHash
    self.CheckpointExportPending = false
    writeCheckpointStatus()
    return true
end

function WalkerSim:RequestPeriodicCheckpoint()
    if self.CheckpointExportPending then
        return true
    end
    local native, nativeError = getNative()
    if not native then
        return false, nativeError
    end
    local requested, requestError = native.RequestCheckpointExport()
    if requested ~= true then
        return false, tostring(requestError or "native checkpoint request failed")
    end
    self.CheckpointExportPending = true
    self.Checkpoint.requestedAt = os.time()
    return true
end

function WalkerSim:CollectPeriodicCheckpoint()
    if not self.CheckpointExportPending then
        return
    end
    local native, nativeError = getNative()
    if not native then
        self.CheckpointExportPending = false
        self.Checkpoint.lastError = nativeError
        return
    end
    local checkpoint, checkpointError = native.TakeCheckpointExport()
    if type(checkpoint) ~= "string" then
        local stats = native.GetStats()
        if type(stats) == "table" and stats.Lifecycle == "running" then
            return
        end
        self.CheckpointExportPending = false
        self.Checkpoint.lastError = tostring(checkpointError or "native checkpoint request ended before completion")
        self.Checkpoint.lastResult = "save failed"
        writeCheckpointStatus()
        return
    end

    self.CheckpointExportPending = false
    local saved, saveError = self:SaveCheckpoint("periodic", checkpoint)
    if not saved then
        self.LastError = tostring(saveError)
    end
end

function WalkerSim:IsRestoreReconciliationPending()
    return self.RestoreReconciliation and self.RestoreReconciliation.pending == true
end

function WalkerSim:ReconcileRestoredMaterializedTickets()
    local reconciliation = self.RestoreReconciliation
    if not reconciliation or not reconciliation.pending then
        return
    end
    if CurTime() >= reconciliation.deadline then
        reconciliation.error = "restored materialized tickets did not reconcile before the deadline"
        self.Checkpoint.lastError = reconciliation.error
        self.Checkpoint.lastResult = "restore reconciliation failed"
        writeCheckpointStatus()
        return
    end

    local tickets, ticketError = self:GetTicketSummaries()
    if not tickets then
        reconciliation.error = tostring(ticketError or "ticket snapshot is unavailable")
        return
    end

    local materializedCount = 0
    for _, ticket in ipairs(tickets) do
        if ticket.State == "materialized" then
            materializedCount = materializedCount + 1
            local key = tostring(ticket.TicketIdHigh) .. ":" .. tostring(ticket.TicketIdLow)
            if not reconciliation.requested[key] then
                local resolved, resolveError = self:ResolveTicket(ticket.TicketIdLow, ticket.TicketIdHigh, false)
                if resolved then
                    reconciliation.requested[key] = true
                else
                    reconciliation.error = tostring(resolveError or "could not queue restored ticket despawn")
                end
            end
        end
    end
    if materializedCount == 0 then
        reconciliation.pending = false
        self.Checkpoint.restoreReconciliation = "complete"
        self.Checkpoint.lastResult = "restored and reconciled"
        writeCheckpointStatus()
    end
end

local function getFirstPlayerCell()
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and not playerEntity:IsBot() then
            local cell = playerEntity:GetWorldCell()
            if cell then
                return cell
            end
        end
    end
end

function WalkerSim:InitializeForActiveProfile()
    local native, nativeError = getNative()
    if not native then
        self.LastError = nativeError
        return false, nativeError
    end
    if not ZM_World or not ZM_World:IsLoaded() then
        self.LastError = "world data is not loaded"
        return false, self.LastError
    end

    local profile = ZM_World.ActiveProfile
    local path = ZM_World:GetProfileDataPath(profile)
    local jsonBytes = path and file.Read(path, "GAME") or nil
    if type(jsonBytes) ~= "string" or jsonBytes == "" then
        self.LastError = "could not read world JSON from GAME: " .. tostring(path)
        return false, self.LastError
    end

    local loaded, loadError = native.LoadWorldJson(jsonBytes, profile, self.Config)
    if loaded ~= true then
        self.LastError = tostring(loadError or "native world import failed")
        return false, self.LastError
    end

    self.ActiveProfile = profile
    local checkpointLoaded, restoredOrError = self:LoadCheckpoint(profile)
    if not checkpointLoaded then
        self.LastError = tostring(restoredOrError or "checkpoint storage failed")
        return false, self.LastError
    end

    local started, startError = native.Start()
    if started ~= true then
        self.LastError = tostring(startError or "native worker could not start")
        return false, self.LastError
    end

    self.IsShuttingDown = false
    self.LastError = nil
    if restoredOrError then
        self.RestoreReconciliation = {
            pending = true,
            requested = {},
            deadline = CurTime() + 8
        }
        self.Checkpoint.restoreReconciliation = "pending"
        writeCheckpointStatus()
    else
        self.RestoreReconciliation = nil
    end
    self:RefreshActiveCell()
    print("[ZombieSim] Walker worker started for profile " .. profile .. ".")
    return true
end

function WalkerSim:RefreshActiveCell()
    local native = getNative()
    if not native then
        return false
    end

    local cell = getFirstPlayerCell()
    if not cell then
        return false
    end

    local active, activeError = native.SetActiveCell(cell.id)
    if active ~= true then
        self.LastError = tostring(activeError or "native active-cell update failed")
        return false
    end
    return true
end

function WalkerSim:ReportNoise(cellId, localU, localV, strength, radius, duration)
    local native, nativeError = getNative()
    if not native then
        self.LastError = nativeError
        return false, nativeError
    end

    local submitted, submitError = native.SubmitAttractor(cellId, localU, localV, strength, radius, duration, "noise")
    if submitted ~= true then
        self.LastError = tostring(submitError or "native attractor submission failed")
        return false, self.LastError
    end
    return true
end

function WalkerSim:GetStats()
    local native, nativeError = getNative()
    if not native then
        return {
            Lifecycle = "fallback",
            LastError = nativeError,
            ProfileId = self.ActiveProfile or ""
        }
    end
    local stats = native.GetStats()
    if type(stats) == "table" then
        stats.CheckpointLoaded = self.Checkpoint.restored == true
        stats.CheckpointStateHash = self.Checkpoint.lastCheckpointStateHash or ""
        stats.LastCheckpointTick = self.Checkpoint.lastCheckpointTick or ""
        stats.LastCheckpointError = self.Checkpoint.lastError or ""
        stats.CheckpointResult = self.Checkpoint.lastResult or ""
    end
    return stats
end

function WalkerSim:GetCellSummary(cellId)
    local native, nativeError = getNative()
    if not native then
        return nil, nativeError
    end
    return native.GetCellSummary(cellId)
end

local function isUInt32(value)
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 4294967295
end

local function nextTicketRequestId()
    local low = WalkerSim.NextTicketRequestLow
    local high = WalkerSim.NextTicketRequestHigh
    WalkerSim.NextTicketRequestLow = low + 1
    if WalkerSim.NextTicketRequestLow > 4294967295 then
        WalkerSim.NextTicketRequestLow = 0
        WalkerSim.NextTicketRequestHigh = high + 1
    end
    if WalkerSim.NextTicketRequestHigh > 4294967295 then
        WalkerSim.NextTicketRequestHigh = 0
    end
    return low, high
end

function WalkerSim:NextTicketRequestId()
    return nextTicketRequestId()
end

function WalkerSim:RequestSpawnTickets(cellId, maximumCount, requestIdLow, requestIdHigh)
    local native, nativeError = getNative()
    if not native then
        return false, nativeError
    end
    if type(cellId) ~= "number" or cellId ~= math.floor(cellId) or cellId < 0 or cellId > 65535 or
        type(maximumCount) ~= "number" or maximumCount ~= math.floor(maximumCount) or maximumCount < 1 or
        maximumCount > self.Config.maximumTicketsPerRequest or not isUInt32(requestIdLow) or not isUInt32(requestIdHigh) or
        (requestIdLow == 0 and requestIdHigh == 0) then
        return false, "ticket request arguments are invalid"
    end
    return native.RequestSpawnTickets(cellId, maximumCount, requestIdLow, requestIdHigh)
end

function WalkerSim:AcknowledgeTicket(ticketIdLow, ticketIdHigh)
    local native, nativeError = getNative()
    if not native then
        return false, nativeError
    end
    if not isUInt32(ticketIdLow) or not isUInt32(ticketIdHigh) or (ticketIdLow == 0 and ticketIdHigh == 0) then
        return false, "ticket id is invalid"
    end
    return native.AcknowledgeTicket(ticketIdLow, ticketIdHigh)
end

function WalkerSim:RejectTicket(ticketIdLow, ticketIdHigh)
    local native, nativeError = getNative()
    if not native then
        return false, nativeError
    end
    if not isUInt32(ticketIdLow) or not isUInt32(ticketIdHigh) or (ticketIdLow == 0 and ticketIdHigh == 0) then
        return false, "ticket id is invalid"
    end
    return native.RejectTicket(ticketIdLow, ticketIdHigh)
end

function WalkerSim:ResolveTicket(ticketIdLow, ticketIdHigh, killed)
    local native, nativeError = getNative()
    if not native then
        return false, nativeError
    end
    if not isUInt32(ticketIdLow) or not isUInt32(ticketIdHigh) or (ticketIdLow == 0 and ticketIdHigh == 0) or
        type(killed) ~= "boolean" then
        return false, "ticket resolution arguments are invalid"
    end
    return native.ResolveTicket(ticketIdLow, ticketIdHigh, killed)
end

function WalkerSim:GetTicketSummaries()
    local native, nativeError = getNative()
    if not native then
        return nil, nativeError
    end
    local tickets, ticketError = native.GetTicketSummaries()
    if type(tickets) ~= "table" then
        return nil, tostring(ticketError or "native ticket snapshot is unavailable")
    end
    return tickets
end

function WalkerSim:BroadcastPreviewSnapshot()
    if not ZM_Preview or not ZM_Preview:IsActive() then
        return
    end

    local native = getNative()
    if not native then
        return
    end
    local stats = native.GetStats()
    if type(stats) ~= "table" or stats.Lifecycle ~= "running" then
        return
    end
    local hordes, hordeError = native.GetHordeSummaries()
    if type(hordes) ~= "table" or #hordes > 8191 then
        self.LastError = tostring(hordeError or "native horde snapshot is unavailable")
        return
    end
    local populationPerZombieConVar = GetConVar("zombiesim_walker_population_per_zombie")
    local populationPerZombie = math.Clamp(
        populationPerZombieConVar and populationPerZombieConVar:GetInt() or 4,
        1,
        65535
    )

    net.Start("ZM.WalkerSnapshot")
        net.WriteString(ZM_World.ActiveProfile)
        net.WriteString(tostring(stats.GraphRevisionHash or ""))
        net.WriteString(tostring(stats.Tick or "0"))
        net.WriteUInt(math.max(0, tonumber(stats.TotalPopulation) or 0), 32)
        net.WriteUInt(populationPerZombie, 16)
        net.WriteUInt(#hordes, 13)
        for _, horde in ipairs(hordes) do
            net.WriteUInt(math.max(0, tonumber(horde.HordeIdLow) or 0), 32)
            net.WriteUInt(math.max(0, tonumber(horde.HordeIdHigh) or 0), 32)
            net.WriteUInt(math.max(0, tonumber(horde.CellId) or 0), 16)
            net.WriteUInt(math.max(0, tonumber(horde.NextCellId) or 0), 16)
            net.WriteUInt(math.max(0, tonumber(horde.Count) or 0), 16)
            net.WriteUInt(math.max(0, tonumber(horde.ProgressPermille) or 0), 10)
        end
    net.Broadcast()
end

function WalkerSim:BroadcastPopulation()
    local native = getNative()
    if not native or not self.ActiveProfile then
        return
    end
    local stats = native.GetStats()
    if type(stats) ~= "table" or stats.Lifecycle ~= "running" then
        return
    end

    net.Start("ZM.WalkerPopulation")
        net.WriteString(self.ActiveProfile)
        net.WriteUInt(math.max(0, tonumber(stats.TotalPopulation) or 0), 32)
    net.Broadcast()
end

local function writeStatusSnapshot(stats)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_status.json", util.TableToJSON(stats, true) or "{}")
end

local function writeTicketSnapshot(tickets)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_tickets.json", util.TableToJSON(tickets, true) or "{}")
end

local function writeTicketProbe(result)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_ticket_probe.json", util.TableToJSON(result, true) or "{}")
end

local function writeZombieSpawnResult(result)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_zombie_spawn.json", util.TableToJSON(result, true) or "{}")
end

local function writeZombieLifecycleResult(result)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_zombie_lifecycle.json", util.TableToJSON(result, true) or "{}")
end

local function writeZombieStatus(result)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_zombie_status.json", util.TableToJSON(result, true) or "{}")
end

function WalkerSim:RecordZombieLifecycle(zombie, event, details)
    local result = {
        event = event,
        observedAt = os.time(),
        map = game.GetMap(),
        profile = self.ActiveProfile,
        entityIndex = zombie:EntIndex(),
        ticketIdLow = zombie.WalkerTicketIdLow,
        ticketIdHigh = zombie.WalkerTicketIdHigh,
        hordeIdLow = zombie.WalkerHordeIdLow,
        hordeIdHigh = zombie.WalkerHordeIdHigh,
        sourceCellId = zombie.WalkerSourceCellId,
        state = zombie.WalkerState,
        acknowledged = zombie.WalkerTicketAcknowledged == true,
        resolutionQueued = zombie.WalkerTicketResolved == true
    }
    if type(details) == "table" then
        for key, value in pairs(details) do
            result[key] = value
        end
    end
    writeZombieLifecycleResult(result)
end

local function ticketKey(ticket)
    return tostring(ticket.TicketIdHigh) .. ":" .. tostring(ticket.TicketIdLow)
end

local function collectTicketKeys(tickets)
    local keys = {}
    for _, ticket in ipairs(tickets) do
        keys[ticketKey(ticket)] = true
    end
    return keys
end

local function findReservedTicket(tickets, knownTickets, cellId)
    for _, ticket in ipairs(tickets) do
        if not knownTickets[ticketKey(ticket)] and ticket.CellId == cellId and ticket.State == "reserved" then
            return ticket
        end
    end
end

local function findTicketById(tickets, ticketIdLow, ticketIdHigh)
    for _, ticket in ipairs(tickets) do
        if ticket.TicketIdLow == ticketIdLow and ticket.TicketIdHigh == ticketIdHigh then
            return ticket
        end
    end
end

local function isPlayerTooClose(position, radius)
    local minimumDistanceSquared = radius * radius
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and playerEntity:Alive() and playerEntity:GetPos():DistToSqr(position) < minimumDistanceSquared then
            return true
        end
    end
    return false
end

local function isWalkerZombieTooClose(position, radius)
    local minimumDistanceSquared = radius * radius
    for _, zombie in ipairs(ents.FindByClass("zn_walker_zombie")) do
        if IsValid(zombie) and zombie:GetPos():DistToSqr(position) < minimumDistanceSquared then
            return true
        end
    end
    return false
end

local function hasSpawnClearance(position)
    local trace = util.TraceHull({
        start = position + Vector(0, 0, 1),
        endpos = position + Vector(0, 0, 1),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        mask = MASK_NPCSOLID_BRUSHONLY
    })
    return not trace.StartSolid and not trace.AllSolid
end

local function isHiddenFromPlayers(position)
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and playerEntity:Alive() then
            local trace = util.TraceLine({
                start = position + Vector(0, 0, 48),
                endpos = playerEntity:EyePos(),
                mask = MASK_SOLID_BRUSHONLY
            })
            if not trace.Hit then
                return false
            end
        end
    end
    return true
end

function WalkerSim:FindZombieSpawnPosition(ticket, relevancePosition, relevanceRadius)
    if type(navmesh) ~= "table" or type(navmesh.IsLoaded) ~= "function" or
        type(navmesh.GetAllNavAreas) ~= "function" or not navmesh.IsLoaded() then
        return nil, "no loaded navmesh"
    end

    local areas = navmesh.GetAllNavAreas()
    if type(areas) ~= "table" or #areas == 0 then
        return nil, "no usable nav areas"
    end

    local localU = math.max(0, math.min(65535, tonumber(ticket.LocalU) or 0))
    local localV = math.max(0, math.min(65535, tonumber(ticket.LocalV) or 0))
    local target = Vector(
        -1600 + localU / 65535 * 3200,
        -1600 + localV / 65535 * 3200,
        0
    )
    table.sort(areas, function(left, right)
        return left:GetCenter():DistToSqr(target) < right:GetCenter():DistToSqr(target)
    end)

    local attempts = math.min(#areas, self.MaterializationConfig.placementAttemptsPerTicket)
    for index = 1, attempts do
        local area = areas[index]
        if area:IsValid() and not area:IsBlocked() and not area:IsUnderwater() then
            local position = area:GetCenter()
            local withinRelevance = not relevancePosition or not relevanceRadius or
                position:DistToSqr(relevancePosition) <= relevanceRadius * relevanceRadius
            if withinRelevance and not isPlayerTooClose(position, self.MaterializationConfig.playerExclusionRadius) and
                not isWalkerZombieTooClose(position, self.MaterializationConfig.minimumZombieSeparation) and
                hasSpawnClearance(position) and isHiddenFromPlayers(position) then
                return position
            end
        end
    end
    return nil, "no nav area passed player-distance, clearance, and visibility checks"
end

function WalkerSim:SpawnTicketZombie(ticket, cellId, relevancePosition, relevanceRadius)
    local position, positionError = self:FindZombieSpawnPosition(ticket, relevancePosition, relevanceRadius)
    if not position then
        return nil, positionError
    end

    local zombie = ents.Create("zn_walker_zombie")
    if not IsValid(zombie) then
        return nil, "could not create zn_walker_zombie"
    end
    zombie:SetPos(position)
    zombie:Spawn()
    zombie:Activate()
    if not zombie:SetWalkerTicket(ticket, cellId) then
        zombie:Remove()
        return nil, "could not assign ticket metadata to zombie"
    end

    local acknowledged, acknowledgeError = self:AcknowledgeTicket(ticket.TicketIdLow, ticket.TicketIdHigh)
    if not acknowledged then
        zombie:Remove()
        self:RejectTicket(ticket.TicketIdLow, ticket.TicketIdHigh)
        return nil, "could not acknowledge spawned zombie: " .. tostring(acknowledgeError)
    end
    zombie:MarkWalkerTicketAcknowledged()
    return zombie
end

hook.Add("InitPostEntity", "ZombieSim.WalkerSim.Initialize", function()
    timer.Simple(0, function()
        local initialized, initializeError = WalkerSim:InitializeForActiveProfile()
        if not initialized then
            print("[ZombieSim] Walker worker unavailable: " .. tostring(initializeError) .. ".")
        end
    end)
end)

hook.Add("ShutDown", "ZombieSim.WalkerSim.Stop", function()
    WalkerSim.IsShuttingDown = true
    if ZM_WalkerMaterializer and type(ZM_WalkerMaterializer.Shutdown) == "function" then
        ZM_WalkerMaterializer:Shutdown()
    end
    local saved, saveError = WalkerSim:SaveCheckpoint("server shutdown")
    if not saved then
        print("[ZombieSim] Walker checkpoint save failed during shutdown: " .. tostring(saveError) .. ".")
    end
    local native = getNative()
    if native then
        native.Stop()
    end
end)

hook.Add("Think", "ZombieSim.WalkerSim.Checkpoint", function()
    WalkerSim:ReconcileRestoredMaterializedTickets()
    WalkerSim:CollectPeriodicCheckpoint()
    if WalkerSim.IsShuttingDown or CurTime() < WalkerSim.NextCheckpointAt or WalkerSim.CheckpointExportPending then
        return
    end
    WalkerSim.NextCheckpointAt = CurTime() + 2
    local stats = WalkerSim:GetStats()
    if type(stats) ~= "table" or stats.Lifecycle ~= "running" or not WalkerSim.ActiveProfile or
        stats.StateHash == WalkerSim.Checkpoint.lastSavedStateHash then
        return
    end
    local requested, requestError = WalkerSim:RequestPeriodicCheckpoint()
    if not requested then
        local saveError = requestError
        WalkerSim.LastError = tostring(saveError)
    end
end)

concommand.Add("zombiesim_walker_status", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_status") then
        return
    end

    WalkerSim:RefreshActiveCell()
    local stats = WalkerSim:GetStats()
    writeStatusSnapshot(stats)
    if ZM_DevConsole then
        ZM_DevConsole:Report("walker", stats)
    end
    print(string.format(
        "[ZombieSim] Walker: %s; profile %s; tick %s; population %s; hordes %s; accepted commands %s; pending %s; active cell %s; error %s",
        tostring(stats.Lifecycle),
        tostring(stats.ProfileId),
        tostring(stats.Tick),
        tostring(stats.TotalPopulation),
        tostring(stats.HordeCount),
        tostring(stats.AcceptedCommandCount),
        tostring(stats.PendingCommandCount),
        tostring(stats.ActiveCellId),
        tostring(stats.LastError or "none")
    ))
end)

concommand.Add("zombiesim_walker_checkpoint_status", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_checkpoint_status") then
        return
    end
    writeCheckpointStatus()
    if ZM_DevConsole then
        ZM_DevConsole:Report("walkerCheckpoint", WalkerSim.Checkpoint)
    end
    print(string.format(
        "[ZombieSim] Walker checkpoint: %s; profile %s; tick %s; error %s.",
        tostring(WalkerSim.Checkpoint.lastResult or "not checked"),
        tostring(WalkerSim.Checkpoint.profile or "none"),
        tostring(WalkerSim.Checkpoint.lastCheckpointTick or "none"),
        tostring(WalkerSim.Checkpoint.lastError or "none")
    ))
end)

concommand.Add("zombiesim_walker_checkpoint_save", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_checkpoint_save") then
        return
    end
    local saved, saveError = WalkerSim:SaveCheckpoint("admin command")
    print(saved and "[ZombieSim] Walker checkpoint saved." or
        "[ZombieSim] Walker checkpoint save failed: " .. tostring(saveError) .. ".")
end)

concommand.Add("zombiesim_walker_checkpoint_clear", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_checkpoint_clear") then
        return
    end
    local profile = arguments[1]
    local paths = checkpointPaths(profile)
    if #arguments ~= 1 or not paths then
        print("[ZombieSim] Usage: zombiesim_walker_checkpoint_clear <profile>")
        return
    end
    local tableReady, tableError = ensureCheckpointTable()
    if not tableReady then
        print("[ZombieSim] Walker checkpoint clear failed: " .. tostring(tableError) .. ".")
        return
    end
    local cleared = sql.Query("DELETE FROM walker_checkpoints WHERE profile = " .. sql.SQLStr(paths.profile))
    if cleared == false then
        print("[ZombieSim] Walker checkpoint clear failed: " .. tostring(sql.LastError()) .. ".")
        return
    end
    WalkerSim.Checkpoint = {
        profile = profile,
        checkpointPath = paths.displayPath,
        lastResult = "cleared",
        clearedAt = os.time()
    }
    writeCheckpointStatus()
    print("[ZombieSim] Walker checkpoint cleared for profile " .. profile .. ".")
end)

concommand.Add("zombiesim_walker_cell", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_cell") then
        return
    end

    local worldX = tonumber(arguments[1])
    local worldY = tonumber(arguments[2])
    if not worldX or not worldY or worldX ~= math.floor(worldX) or worldY ~= math.floor(worldY) then
        print("[ZombieSim] Usage: zombiesim_walker_cell <worldX> <worldY>")
        return
    end

    local gridX, gridY = ZM_World:GetGridCoordinates(worldX, worldY)
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    if not cell then
        print("[ZombieSim] Walker cell is outside the active world profile.")
        return
    end

    local summary, summaryError = WalkerSim:GetCellSummary(cell.id)
    if not summary then
        print("[ZombieSim] Walker summary unavailable: " .. tostring(summaryError or "native worker is not ready") .. ".")
        return
    end
    if ZM_DevConsole then
        ZM_DevConsole:Report("walkerCell", { worldX = worldX, worldY = worldY, summary = summary })
    end
    print(string.format(
        "[ZombieSim] Walker cell %d (%d, %d): ambient %s; reserved %s; materialized %s; attraction %s.",
        cell.id,
        worldX,
        worldY,
        tostring(summary.AmbientPopulation),
        tostring(summary.ReservedPopulation),
        tostring(summary.MaterializedPopulation),
        tostring(summary.Attraction)
    ))
end)

concommand.Add("zombiesim_walker_noise", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_noise") then
        return
    end

    local strength = tonumber(arguments[1])
    local radius = tonumber(arguments[2])
    local duration = tonumber(arguments[3]) or 4
    if not strength or not radius or strength < 1 or strength > 65535 or radius < 0 or radius > 65535 or
        duration < 1 or duration > 65535 or strength ~= math.floor(strength) or radius ~= math.floor(radius) or
        duration ~= math.floor(duration) then
        print("[ZombieSim] Usage: zombiesim_walker_noise <strength> <radius> [durationTicks]")
        return
    end

    local cell = getFirstPlayerCell()
    if not cell then
        print("[ZombieSim] Walker noise requires an active player cell.")
        return
    end
    local submitted, submitError = WalkerSim:ReportNoise(cell.id, 32768, 32768, strength, radius, duration)
    if not submitted then
        print("[ZombieSim] Walker noise was rejected: " .. tostring(submitError) .. ".")
        return
    end
    timer.Simple(1, function()
        writeStatusSnapshot(WalkerSim:GetStats())
    end)
    print("[ZombieSim] Walker noise submitted for cell " .. cell.id .. ".")
end)

concommand.Add("zombiesim_walker_tickets", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_tickets") then
        return
    end

    local tickets, ticketError = WalkerSim:GetTicketSummaries()
    if not tickets then
        print("[ZombieSim] Walker tickets unavailable: " .. tostring(ticketError) .. ".")
        return
    end

    local totals = {
        reserved = 0,
        materialized = 0,
        rejected = 0,
        expired = 0,
        killed = 0,
        despawned = 0
    }
    for _, ticket in ipairs(tickets) do
        if totals[ticket.State] ~= nil then
            totals[ticket.State] = totals[ticket.State] + 1
        end
    end
    writeTicketSnapshot({ tickets = tickets, totals = totals, capturedAt = os.time() })
    print(string.format(
        "[ZombieSim] Walker tickets: reserved %d; materialized %d; rejected %d; expired %d; killed %d; despawned %d.",
        totals.reserved,
        totals.materialized,
        totals.rejected,
        totals.expired,
        totals.killed,
        totals.despawned
    ))
end)

concommand.Add("zombiesim_walker_ticket_request", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_ticket_request") then
        return
    end

    local maximumCount = tonumber(arguments[1]) or 1
    if #arguments > 1 or maximumCount ~= math.floor(maximumCount) or maximumCount < 1 or
        maximumCount > WalkerSim.Config.maximumTicketsPerRequest then
        print("[ZombieSim] Usage: zombiesim_walker_ticket_request [count]")
        return
    end

    local cell = getFirstPlayerCell()
    if not cell then
        print("[ZombieSim] Walker ticket request requires an active player cell.")
        return
    end
    if ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell) then
        print("[ZombieSim] Walker tickets cannot be requested from a safe-zone cell. Load an ordinary city cell first.")
        return
    end
    local requestIdLow, requestIdHigh = nextTicketRequestId()
    local submitted, submitError = WalkerSim:RequestSpawnTickets(
        cell.id,
        maximumCount,
        requestIdLow,
        requestIdHigh
    )
    if not submitted then
        print("[ZombieSim] Walker ticket request was rejected: " .. tostring(submitError) .. ".")
        return
    end
    print(string.format(
        "[ZombieSim] Requested %d walker ticket(s) for cell %d; request id %u:%u.",
        maximumCount,
        cell.id,
        requestIdHigh,
        requestIdLow
    ))
end)

local function parseTicketId(arguments, command)
    local ticketIdLow = tonumber(arguments[1])
    local ticketIdHigh = tonumber(arguments[2])
    if not isUInt32(ticketIdLow) or not isUInt32(ticketIdHigh) or (ticketIdLow == 0 and ticketIdHigh == 0) then
        print("[ZombieSim] Usage: " .. command .. " <ticketIdLow> <ticketIdHigh>")
        return nil
    end
    return ticketIdLow, ticketIdHigh
end

concommand.Add("zombiesim_walker_ticket_ack", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_ticket_ack") or #arguments ~= 2 then
        return
    end
    local ticketIdLow, ticketIdHigh = parseTicketId(arguments, "zombiesim_walker_ticket_ack")
    if not ticketIdLow then
        return
    end
    local submitted, submitError = WalkerSim:AcknowledgeTicket(ticketIdLow, ticketIdHigh)
    print(submitted and "[ZombieSim] Walker ticket acknowledgement queued." or
        "[ZombieSim] Walker ticket acknowledgement was rejected: " .. tostring(submitError) .. ".")
end)

concommand.Add("zombiesim_walker_ticket_reject", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_ticket_reject") or #arguments ~= 2 then
        return
    end
    local ticketIdLow, ticketIdHigh = parseTicketId(arguments, "zombiesim_walker_ticket_reject")
    if not ticketIdLow then
        return
    end
    local submitted, submitError = WalkerSim:RejectTicket(ticketIdLow, ticketIdHigh)
    print(submitted and "[ZombieSim] Walker ticket rejection queued." or
        "[ZombieSim] Walker ticket rejection was rejected: " .. tostring(submitError) .. ".")
end)

concommand.Add("zombiesim_walker_ticket_resolve", function(ply, _, arguments)
    if not isAdminOrServer(ply, "zombiesim_walker_ticket_resolve") or #arguments ~= 3 then
        return
    end
    local ticketIdLow, ticketIdHigh = parseTicketId(arguments, "zombiesim_walker_ticket_resolve")
    local killed = tonumber(arguments[3])
    if not ticketIdLow or (killed ~= 0 and killed ~= 1) then
        print("[ZombieSim] Usage: zombiesim_walker_ticket_resolve <ticketIdLow> <ticketIdHigh> <killed:0|1>")
        return
    end
    local submitted, submitError = WalkerSim:ResolveTicket(ticketIdLow, ticketIdHigh, killed == 1)
    print(submitted and "[ZombieSim] Walker ticket resolution queued." or
        "[ZombieSim] Walker ticket resolution was rejected: " .. tostring(submitError) .. ".")
end)

concommand.Add("zombiesim_walker_ticket_probe", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_ticket_probe") then
        return
    end

    local cell = getFirstPlayerCell()
    if not cell or (ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell)) then
        print("[ZombieSim] Walker ticket probe requires an ordinary active city cell.")
        return
    end

    local before, beforeError = WalkerSim:GetTicketSummaries()
    if not before then
        print("[ZombieSim] Walker ticket probe cannot read the current ticket snapshot: " .. tostring(beforeError) .. ".")
        return
    end
    local knownTickets = {}
    for _, ticket in ipairs(before) do
        knownTickets[tostring(ticket.TicketIdHigh) .. ":" .. tostring(ticket.TicketIdLow)] = true
    end

    local requestIdLow, requestIdHigh = nextTicketRequestId()
    local started, startError = WalkerSim:RequestSpawnTickets(cell.id, 1, requestIdLow, requestIdHigh)
    if not started then
        print("[ZombieSim] Walker ticket probe request was rejected: " .. tostring(startError) .. ".")
        return
    end

    local result = {
        profile = WalkerSim.ActiveProfile,
        map = game.GetMap(),
        cellId = cell.id,
        requestIdLow = requestIdLow,
        requestIdHigh = requestIdHigh,
        startedAt = os.time(),
        success = false
    }
    local function fail(message)
        result.error = message
        result.finishedAt = os.time()
        writeTicketProbe(result)
        print("[ZombieSim] Walker ticket probe failed: " .. message .. ".")
    end
    local function findNewTicket(tickets, expectedState)
        for _, ticket in ipairs(tickets) do
            local key = tostring(ticket.TicketIdHigh) .. ":" .. tostring(ticket.TicketIdLow)
            if not knownTickets[key] and ticket.CellId == cell.id and ticket.State == expectedState then
                return ticket
            end
        end
    end

    timer.Simple(1, function()
        local reserved, reservedError = WalkerSim:GetTicketSummaries()
        if not reserved then
            fail("could not read reservation snapshot: " .. tostring(reservedError))
            return
        end
        local ticket = findNewTicket(reserved, "reserved")
        if not ticket then
            fail("request did not produce a reserved ticket in active cell " .. cell.id)
            return
        end
        result.ticketIdLow = ticket.TicketIdLow
        result.ticketIdHigh = ticket.TicketIdHigh
        result.reservedAtTick = WalkerSim:GetStats().Tick
        local acknowledged, acknowledgeError = WalkerSim:AcknowledgeTicket(ticket.TicketIdLow, ticket.TicketIdHigh)
        if not acknowledged then
            fail("could not acknowledge reserved ticket: " .. tostring(acknowledgeError))
            return
        end

        timer.Simple(1, function()
            local materialized, materializedError = WalkerSim:GetTicketSummaries()
            if not materialized then
                fail("could not read materialized snapshot: " .. tostring(materializedError))
                return
            end
            local confirmed = findNewTicket(materialized, "materialized")
            if not confirmed or confirmed.TicketIdLow ~= ticket.TicketIdLow or confirmed.TicketIdHigh ~= ticket.TicketIdHigh then
                fail("acknowledged ticket did not become materialized")
                return
            end
            result.materializedAtTick = WalkerSim:GetStats().Tick
            local resolved, resolveError = WalkerSim:ResolveTicket(ticket.TicketIdLow, ticket.TicketIdHigh, false)
            if not resolved then
                fail("could not despawn materialized ticket: " .. tostring(resolveError))
                return
            end

            timer.Simple(1, function()
                local despawned, despawnedError = WalkerSim:GetTicketSummaries()
                if not despawned then
                    fail("could not read despawned snapshot: " .. tostring(despawnedError))
                    return
                end
                local confirmedDespawn = findNewTicket(despawned, "despawned")
                if not confirmedDespawn or confirmedDespawn.TicketIdLow ~= ticket.TicketIdLow or confirmedDespawn.TicketIdHigh ~= ticket.TicketIdHigh then
                    fail("resolved ticket did not become despawned")
                    return
                end
                local stats = WalkerSim:GetStats()
                result.despawnedAtTick = stats.Tick
                result.population = stats.TotalPopulation
                result.success = true
                result.finishedAt = os.time()
                writeTicketProbe(result)
                print("[ZombieSim] Walker ticket probe passed for ticket " .. ticket.TicketIdHigh .. ":" .. ticket.TicketIdLow .. ".")
            end)
        end)
    end)

    print("[ZombieSim] Walker ticket probe started for cell " .. cell.id .. ".")
end)

concommand.Add("zombiesim_walker_zombie_spawn_test", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_zombie_spawn_test") then
        return
    end
    if #ents.FindByClass("zn_walker_zombie") > 0 then
        print("[ZombieSim] A Walker zombie test is already active on this map.")
        return
    end

    local cell = getFirstPlayerCell()
    if not cell or (ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell)) then
        print("[ZombieSim] Walker zombie test requires an ordinary active city cell.")
        return
    end
    local tickets, ticketError = WalkerSim:GetTicketSummaries()
    if not tickets then
        print("[ZombieSim] Walker zombie test cannot read ticket snapshot: " .. tostring(ticketError) .. ".")
        return
    end

    local requestIdLow, requestIdHigh = nextTicketRequestId()
    local requested, requestError = WalkerSim:RequestSpawnTickets(cell.id, 1, requestIdLow, requestIdHigh)
    if not requested then
        print("[ZombieSim] Walker zombie test request was rejected: " .. tostring(requestError) .. ".")
        return
    end
    local result = {
        profile = WalkerSim.ActiveProfile,
        map = game.GetMap(),
        cellId = cell.id,
        requestIdLow = requestIdLow,
        requestIdHigh = requestIdHigh,
        startedAt = os.time(),
        success = false
    }
    local knownTickets = collectTicketKeys(tickets)
    timer.Simple(1, function()
        local reserved, reservedError = WalkerSim:GetTicketSummaries()
        local ticket = reserved and findReservedTicket(reserved, knownTickets, cell.id) or nil
        if not ticket then
            result.error = "no reserved ticket became available: " .. tostring(reservedError or "request was not fulfilled")
            result.finishedAt = os.time()
            writeZombieSpawnResult(result)
            print("[ZombieSim] Walker zombie test failed: " .. result.error .. ".")
            return
        end

        local zombie, spawnError = WalkerSim:SpawnTicketZombie(ticket, cell.id)
        if not zombie then
            WalkerSim:RejectTicket(ticket.TicketIdLow, ticket.TicketIdHigh)
            result.error = spawnError
            result.ticketIdLow = ticket.TicketIdLow
            result.ticketIdHigh = ticket.TicketIdHigh
            result.finishedAt = os.time()
            writeZombieSpawnResult(result)
            print("[ZombieSim] Walker zombie test failed: " .. tostring(spawnError) .. ".")
            return
        end

        result.ticketIdLow = ticket.TicketIdLow
        result.ticketIdHigh = ticket.TicketIdHigh
        result.entityIndex = zombie:EntIndex()
        result.spawnPosition = { x = zombie:GetPos().x, y = zombie:GetPos().y, z = zombie:GetPos().z }
        result.success = true
        result.finishedAt = os.time()
        writeZombieSpawnResult(result)
        print("[ZombieSim] Walker zombie test spawned entity " .. zombie:EntIndex() .. " for ticket " .. ticketKey(ticket) .. ".")
    end)
    print("[ZombieSim] Walker zombie test requested one ticket for cell " .. cell.id .. ".")
end)

local function getWalkerZombie()
    local zombies = ents.FindByClass("zn_walker_zombie")
    return IsValid(zombies[1]) and zombies[1] or nil
end

local function getWalkerZombies()
    local zombies = {}
    for _, zombie in ipairs(ents.FindByClass("zn_walker_zombie")) do
        if IsValid(zombie) then
            table.insert(zombies, zombie)
        end
    end
    return zombies
end

concommand.Add("zombiesim_walker_zombie_status", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_zombie_status") then
        return
    end

    local zombies = getWalkerZombies()
    local zombie = zombies[1]
    local result = {
        capturedAt = os.time(),
        map = game.GetMap(),
        profile = WalkerSim.ActiveProfile,
        active = IsValid(zombie),
        activeCount = #zombies,
        zombies = {},
        totals = {
            targetSearches = 0,
            pathComputes = 0,
            pathFailures = 0,
            stuckRecoveries = 0,
            attacks = 0
        }
    }

    local tickets, ticketError = WalkerSim:GetTicketSummaries()
    if not tickets then
        result.ticketError = ticketError
    end
    for _, activeZombie in ipairs(zombies) do
        local performance = type(activeZombie.GetWalkerPerformanceStats) == "function" and
            activeZombie:GetWalkerPerformanceStats() or {}
        local ticket = tickets and findTicketById(tickets, activeZombie.WalkerTicketIdLow, activeZombie.WalkerTicketIdHigh) or nil
        local entry = {
            entityIndex = activeZombie:EntIndex(),
            position = { x = activeZombie:GetPos().x, y = activeZombie:GetPos().y, z = activeZombie:GetPos().z },
            health = activeZombie:Health(),
            state = activeZombie.WalkerState,
            ticketIdLow = activeZombie.WalkerTicketIdLow,
            ticketIdHigh = activeZombie.WalkerTicketIdHigh,
            acknowledged = activeZombie.WalkerTicketAcknowledged == true,
            resolutionQueued = activeZombie.WalkerTicketResolved == true,
            ticketState = ticket and ticket.State or "not yet published",
            performance = performance
        }
        table.insert(result.zombies, entry)
        result.totals.targetSearches = result.totals.targetSearches + (performance.targetSearches or 0)
        result.totals.pathComputes = result.totals.pathComputes + (performance.pathComputes or 0)
        result.totals.pathFailures = result.totals.pathFailures + (performance.pathFailures or 0)
        result.totals.stuckRecoveries = result.totals.stuckRecoveries + (performance.stuckRecoveries or 0)
        result.totals.attacks = result.totals.attacks + (performance.attacks or 0)
    end
    if IsValid(zombie) then
        result.entityIndex = zombie:EntIndex()
        result.position = { x = zombie:GetPos().x, y = zombie:GetPos().y, z = zombie:GetPos().z }
        result.health = zombie:Health()
        result.state = zombie.WalkerState
        result.ticketIdLow = zombie.WalkerTicketIdLow
        result.ticketIdHigh = zombie.WalkerTicketIdHigh
        result.acknowledged = zombie.WalkerTicketAcknowledged == true
        result.resolutionQueued = zombie.WalkerTicketResolved == true

        if tickets then
            local ticket = findTicketById(tickets, zombie.WalkerTicketIdLow, zombie.WalkerTicketIdHigh)
            result.ticketState = ticket and ticket.State or "not yet published"
        end
    end
    writeZombieStatus(result)
    if ZM_DevConsole then
        ZM_DevConsole:Report("walkerZombie", result)
    end
    print(result.active and
        "[ZombieSim] Walker zombie status captured for " .. result.activeCount .. " active entity(s)." or
        "[ZombieSim] No Walker zombie is active on this map.")
end)

concommand.Add("zombiesim_walker_zombie_kill_test", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_zombie_kill_test") then
        return
    end

    local zombie = getWalkerZombie()
    if not zombie then
        print("[ZombieSim] Walker zombie kill test requires an active test zombie.")
        return
    end
    local entityIndex = zombie:EntIndex()
    local damage = DamageInfo()
    damage:SetDamage(math.max(1, zombie:Health()))
    damage:SetDamageType(DMG_SLASH)
    damage:SetAttacker(game.GetWorld())
    damage:SetInflictor(game.GetWorld())
    zombie:TakeDamageInfo(damage)
    print("[ZombieSim] Walker zombie kill test submitted lethal damage to entity " .. entityIndex .. ".")
end)

concommand.Add("zombiesim_walker_zombie_despawn_test", function(ply)
    if not isAdminOrServer(ply, "zombiesim_walker_zombie_despawn_test") then
        return
    end

    local zombie = getWalkerZombie()
    if not zombie then
        print("[ZombieSim] Walker zombie despawn test requires an active test zombie.")
        return
    end
    local entityIndex = zombie:EntIndex()
    zombie:Remove()
    print("[ZombieSim] Walker zombie despawn test removed entity " .. entityIndex .. ".")
end)

hook.Add("Think", "ZombieSim.WalkerSim.BroadcastPreviewSnapshot", function()
    if CurTime() < WalkerSim.NextSnapshotAt then
        return
    end
    WalkerSim.NextSnapshotAt = CurTime() + WalkerSim.SnapshotInterval
    WalkerSim:BroadcastPopulation()
    WalkerSim:BroadcastPreviewSnapshot()
end)