// Server-owned Phase D materialization controller. Native Walker tickets remain authoritative.
ZM_WalkerMaterializer = ZM_WalkerMaterializer or {}
local Materializer = ZM_WalkerMaterializer

Materializer.Enabled = Materializer.Enabled == true
Materializer.Started = Materializer.Started == true
Materializer.Registry = Materializer.Registry or {}
Materializer.HandledReservations = Materializer.HandledReservations or {}
Materializer.PendingRequest = Materializer.PendingRequest or nil
Materializer.CurrentCellId = Materializer.CurrentCellId or nil
Materializer.NextReconcileAt = Materializer.NextReconcileAt or 0
Materializer.NextRequestAt = Materializer.NextRequestAt or 0
Materializer.LastError = Materializer.LastError or nil
Materializer.ErrorCount = Materializer.ErrorCount or 0
Materializer.RequestOverride = Materializer.RequestOverride or nil

local activeZombieCapConVar = CreateConVar(
    "zombiesim_walker_active_cap",
    "64",
    FCVAR_ARCHIVE,
    "Hard maximum live Walker NextBots controlled by the server materializer.",
    1,
    256
)
local populationPerZombieConVar = CreateConVar(
    "zombiesim_walker_population_per_zombie",
    "4",
    FCVAR_ARCHIVE,
    "Virtual walkers represented by one live Walker NextBot in the active cell.",
    1,
    65535
)
util.AddNetworkString("ZM.RequestWalkerMaterializationSettings")
util.AddNetworkString("ZM.WalkerMaterializationSettings")
util.AddNetworkString("ZM.SetWalkerMaterializationSettings")

local function ticketKey(ticket)
    return tostring(ticket.TicketIdHigh) .. ":" .. tostring(ticket.TicketIdLow)
end

local function getConfig()
    return ZM_WalkerSim and ZM_WalkerSim.MaterializationConfig or {}
end

local function getActiveCap()
    local configuredCap = activeZombieCapConVar and activeZombieCapConVar:GetInt() or getConfig().activeZombieCap
    return math.Clamp(math.floor(tonumber(configuredCap) or 1), 1, 256)
end

local function getPopulationPerZombie()
    local configuredScale = populationPerZombieConVar and populationPerZombieConVar:GetInt() or 8
    return math.Clamp(math.floor(tonumber(configuredScale) or 8), 1, 65535)
end

local function sendMaterializationSettings(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() then
        return
    end
    net.Start("ZM.WalkerMaterializationSettings")
        net.WriteUInt(getActiveCap(), 9)
        net.WriteUInt(getPopulationPerZombie(), 16)
        net.WriteBool(playerEntity:IsAdmin())
    net.Send(playerEntity)
end

net.Receive("ZM.RequestWalkerMaterializationSettings", function(_, playerEntity)
    sendMaterializationSettings(playerEntity)
end)

net.Receive("ZM.SetWalkerMaterializationSettings", function(_, playerEntity)
    local activeCap = math.Clamp(net.ReadUInt(9), 1, 256)
    local populationPerZombie = math.Clamp(net.ReadUInt(16), 1, 65535)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:IsAdmin() then
        sendMaterializationSettings(playerEntity)
        return
    end
    activeZombieCapConVar:SetInt(activeCap)
    populationPerZombieConVar:SetInt(populationPerZombie)
    sendMaterializationSettings(playerEntity)
end)

local function getRequestLimit()
    return math.max(1, math.floor(tonumber(getConfig().requestLimitPerTick) or 1))
end

local function getRetrySeconds()
    return math.max(0.25, tonumber(getConfig().requestRetrySeconds) or 1)
end

local function getTicketLifetimeSeconds()
    local ticks = ZM_WalkerSim and ZM_WalkerSim.Config and ZM_WalkerSim.Config.ticketLifetimeTicks or 20
    return math.max(1, tonumber(ticks) / 4 + 1)
end

local function getEligiblePlayer()
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and not playerEntity:IsBot() and playerEntity:Alive() then
            local cell = playerEntity:GetWorldCell()
            if cell and (not ZM_SafeZones or not ZM_SafeZones:IsSafeZoneCell(cell)) then
                return playerEntity, cell
            end
        end
    end
end

local function writeStatus(result)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_materializer_status.json", util.TableToJSON(result, true) or "{}")
end

function Materializer:RecordError(message)
    self.LastError = tostring(message)
    self.ErrorCount = self.ErrorCount + 1
    print("[ZombieSim] Walker materializer: " .. self.LastError .. ".")
end

function Materializer:SynchronizeRegistry()
    local activeCount = 0
    for key, zombie in pairs(self.Registry) do
        if IsValid(zombie) and zombie.WalkerTicketAcknowledged and not zombie.WalkerTicketResolved then
            activeCount = activeCount + 1
        else
            self.Registry[key] = nil
        end
    end

    for _, zombie in ipairs(ents.FindByClass("zn_walker_zombie")) do
        if IsValid(zombie) and zombie.WalkerTicketAcknowledged and not zombie.WalkerTicketResolved and
            zombie.WalkerTicketIdLow ~= nil and zombie.WalkerTicketIdHigh ~= nil then
            local key = tostring(zombie.WalkerTicketIdHigh) .. ":" .. tostring(zombie.WalkerTicketIdLow)
            if not self.Registry[key] then
                self.Registry[key] = zombie
                activeCount = activeCount + 1
            elseif self.Registry[key] ~= zombie then
                self:RecordError("duplicate live entity for ticket " .. key)
            end
        end
    end
    return activeCount
end

function Materializer:DespawnZombie(key, zombie, reason)
    self.Registry[key] = nil
    if IsValid(zombie) then
        zombie:RecordWalkerLifecycle("despawnRequested", { reason = reason })
        zombie:Remove()
    end
end

function Materializer:DespawnAll(reason)
    local entries = {}
    for key, zombie in pairs(self.Registry) do
        table.insert(entries, { key = key, zombie = zombie })
    end
    for _, entry in ipairs(entries) do
        local key = entry.key
        local zombie = entry.zombie
        self:DespawnZombie(key, zombie, reason)
    end
    self.PendingRequest = nil
end

function Materializer:DespawnIrrelevant(playerEntity)
    local radius = math.max(1, tonumber(getConfig().materializationRadius) or 1200)
    local graceSeconds = math.max(0, tonumber(getConfig().despawnGraceSeconds) or 10)
    local maximumDistanceSquared = radius * radius
    for key, zombie in pairs(self.Registry) do
        if IsValid(zombie) then
            if type(zombie.IsWalkerEngaged) == "function" and zombie:IsWalkerEngaged() then
                zombie.WalkerOutsideRelevanceAt = nil
            elseif zombie:GetPos():DistToSqr(playerEntity:GetPos()) > maximumDistanceSquared then
                zombie.WalkerOutsideRelevanceAt = zombie.WalkerOutsideRelevanceAt or CurTime()
                if CurTime() - zombie.WalkerOutsideRelevanceAt >= graceSeconds then
                    self:DespawnZombie(key, zombie, "outside relevance radius")
                end
            else
                zombie.WalkerOutsideRelevanceAt = nil
            end
        end
    end
end

function Materializer:GetPopulationTarget(cell)
    local summary, summaryError = ZM_WalkerSim:GetCellSummary(cell.id)
    if type(summary) ~= "table" then
        return nil, nil, tostring(summaryError or "cell population summary is unavailable")
    end

    local population = math.max(0, tonumber(summary.AmbientPopulation) or 0) +
        math.max(0, tonumber(summary.ReservedPopulation) or 0) +
        math.max(0, tonumber(summary.MaterializedPopulation) or 0)
    local target = math.min(getActiveCap(), math.ceil(population / getPopulationPerZombie()))
    return target, population
end

function Materializer:DespawnExcess(targetCount)
    local entries = {}
    for key, zombie in pairs(self.Registry) do
        if IsValid(zombie) and (type(zombie.IsWalkerEngaged) ~= "function" or not zombie:IsWalkerEngaged()) then
            table.insert(entries, { key = key, zombie = zombie })
        end
    end
    table.sort(entries, function(left, right)
        return left.key > right.key
    end)
    for index = targetCount + 1, #entries do
        self:DespawnZombie(entries[index].key, entries[index].zombie, "cell population target decreased")
    end
end

function Materializer:UpdatePendingRequest(tickets)
    if not self.PendingRequest then
        return
    end

    for _, ticket in ipairs(tickets) do
        if ticket.CellId == self.PendingRequest.cellId and not self.PendingRequest.knownTickets[ticketKey(ticket)] then
            self.PendingRequest = nil
            return
        end
    end
    if CurTime() >= self.PendingRequest.expiresAt then
        self:RecordError("ticket request did not publish a reservation before its deadline")
        self.PendingRequest = nil
        self.NextRequestAt = CurTime() + getRetrySeconds()
    end
end

function Materializer:MaterializeReservations(tickets, cell, playerEntity, activeCount, targetCount)
    local capacity = targetCount
    for _, ticket in ipairs(tickets) do
        if activeCount >= capacity then
            break
        end
        local key = ticketKey(ticket)
        if ticket.CellId == cell.id and ticket.State == "reserved" and not self.Registry[key] and
            not self.HandledReservations[key] then
            self.HandledReservations[key] = true
            local zombie, spawnError = ZM_WalkerSim:SpawnTicketZombie(
                ticket,
                cell.id,
                playerEntity:GetPos(),
                math.max(1, tonumber(getConfig().materializationRadius) or 1200)
            )
            if IsValid(zombie) then
                self.Registry[key] = zombie
                activeCount = activeCount + 1
            else
                local rejected, rejectError = ZM_WalkerSim:RejectTicket(ticket.TicketIdLow, ticket.TicketIdHigh)
                self:RecordError("placement rejected for ticket " .. key .. ": " .. tostring(spawnError or rejectError))
                self.NextRequestAt = math.max(self.NextRequestAt, CurTime() + getRetrySeconds())
                if not rejected then
                    self:RecordError("could not queue rejection for ticket " .. key .. ": " .. tostring(rejectError))
                end
            end
        end
    end
    return activeCount
end

function Materializer:RequestTickets(tickets, cell, activeCount, targetCount)
    if self.PendingRequest or CurTime() < self.NextRequestAt or activeCount >= targetCount then
        return
    end

    local requestedCount = self.RequestOverride or math.min(getRequestLimit(), targetCount - activeCount)
    self.RequestOverride = nil
    requestedCount = math.min(requestedCount, getRequestLimit(), targetCount - activeCount)
    if requestedCount < 1 then
        return
    end

    local knownTickets = {}
    for _, ticket in ipairs(tickets) do
        knownTickets[ticketKey(ticket)] = true
    end
    local requestIdLow, requestIdHigh = ZM_WalkerSim:NextTicketRequestId()
    local requested, requestError = ZM_WalkerSim:RequestSpawnTickets(cell.id, requestedCount, requestIdLow, requestIdHigh)
    if not requested then
        self:RecordError("ticket request failed: " .. tostring(requestError))
        self.NextRequestAt = CurTime() + getRetrySeconds()
        return
    end

    self.PendingRequest = {
        cellId = cell.id,
        requestIdLow = requestIdLow,
        requestIdHigh = requestIdHigh,
        knownTickets = knownTickets,
        expiresAt = CurTime() + getTicketLifetimeSeconds()
    }
end

function Materializer:PruneHandledReservations(tickets)
    local stillReserved = {}
    for _, ticket in ipairs(tickets) do
        if ticket.State == "reserved" then
            stillReserved[ticketKey(ticket)] = true
        end
    end
    for key in pairs(self.HandledReservations) do
        if not stillReserved[key] then
            self.HandledReservations[key] = nil
        end
    end
end

function Materializer:Reconcile()
    if not self.Started or not self.Enabled or not ZM_WalkerSim or ZM_WalkerSim.IsShuttingDown then
        return
    end
    if ZM_WalkerSim:IsRestoreReconciliationPending() then
        return
    end

    local stats = ZM_WalkerSim:GetStats()
    if type(stats) ~= "table" or stats.Lifecycle ~= "running" then
        return
    end

    local playerEntity, cell = getEligiblePlayer()
    if not playerEntity then
        self:DespawnAll("no eligible player")
        self.CurrentCellId = nil
        return
    end
    if self.CurrentCellId and self.CurrentCellId ~= cell.id then
        self:DespawnAll("active cell changed")
    end
    self.CurrentCellId = cell.id

    local refreshed, refreshError = ZM_WalkerSim:RefreshActiveCell()
    if not refreshed then
        self:RecordError("could not refresh active cell: " .. tostring(refreshError or "unknown error"))
        return
    end

    local tickets, ticketError = ZM_WalkerSim:GetTicketSummaries()
    if not tickets then
        self:RecordError("ticket snapshot unavailable: " .. tostring(ticketError))
        return
    end
    self:UpdatePendingRequest(tickets)
    local activeCount = self:SynchronizeRegistry()
    local targetCount, cellPopulation, targetError = self:GetPopulationTarget(cell)
    if not targetCount then
        self:RecordError("could not calculate active-cell population target: " .. targetError)
        return
    end
    self.CurrentCellPopulation = cellPopulation
    self.CurrentTargetCount = targetCount
    self:DespawnIrrelevant(playerEntity)
    activeCount = self:SynchronizeRegistry()
    self:DespawnExcess(targetCount)
    activeCount = self:SynchronizeRegistry()
    activeCount = self:MaterializeReservations(tickets, cell, playerEntity, activeCount, targetCount)
    self:RequestTickets(tickets, cell, activeCount, targetCount)
    self:PruneHandledReservations(tickets)
end

function Materializer:GetStatus()
    local activeCount = self:SynchronizeRegistry()
    return {
        capturedAt = os.time(),
        map = game.GetMap(),
        profile = ZM_WalkerSim and ZM_WalkerSim.ActiveProfile or nil,
        enabled = self.Enabled,
        activeZombieCount = activeCount,
        activeZombieCap = getActiveCap(),
        activeCellPopulation = self.CurrentCellPopulation,
        targetZombieCount = self.CurrentTargetCount,
        virtualWalkersPerZombie = getPopulationPerZombie(),
        currentCellId = self.CurrentCellId,
        pendingRequest = self.PendingRequest and {
            cellId = self.PendingRequest.cellId,
            requestIdLow = self.PendingRequest.requestIdLow,
            requestIdHigh = self.PendingRequest.requestIdHigh
        } or nil,
        lastError = self.LastError,
        errorCount = self.ErrorCount
    }
end

function Materializer:Start()
    self.Started = true
    self.Enabled = true
    self.Registry = {}
    self.HandledReservations = {}
    self.PendingRequest = nil
    self.CurrentCellId = nil
    self.CurrentCellPopulation = nil
    self.CurrentTargetCount = nil
    self.NextRequestAt = CurTime() + getRetrySeconds()
    self.LastError = nil
    self.ErrorCount = 0
end

function Materializer:Shutdown()
    self:DespawnAll("server shutdown")
    self.Enabled = false
    self.Started = false
end

concommand.Add("zombiesim_walker_materializer_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] zombiesim_walker_materializer_status must be run by an in-game admin.\n")
        return
    end
    local status = Materializer:GetStatus()
    writeStatus(status)
    if ZM_DevConsole then
        ZM_DevConsole:Report("walkerMaterializer", status)
    end
    print(string.format(
        "[ZombieSim] Walker materializer: enabled %s; active %d/%d; cell %s; pending %s; errors %d.",
        tostring(status.enabled),
        status.activeZombieCount,
        status.activeZombieCap,
        tostring(status.currentCellId or "none"),
        status.pendingRequest and "yes" or "no",
        status.errorCount
    ))
end)

concommand.Add("zombiesim_walker_materializer_request", function(ply, _, arguments)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] zombiesim_walker_materializer_request must be run by an in-game admin.\n")
        return
    end
    local count = tonumber(arguments[1]) or 1
    if #arguments > 1 or count ~= math.floor(count) or count < 1 or count > getRequestLimit() then
        print("[ZombieSim] Usage: zombiesim_walker_materializer_request [count]")
        return
    end
    Materializer.RequestOverride = count
    Materializer.NextRequestAt = 0
    Materializer:Reconcile()
    print("[ZombieSim] Walker materializer requested up to " .. count .. " ticket(s) through the active controller.")
end)

hook.Add("InitPostEntity", "ZombieSim.WalkerMaterializer.Start", function()
    timer.Simple(0, function()
        Materializer:Start()
    end)
end)

hook.Add("Think", "ZombieSim.WalkerMaterializer.Reconcile", function()
    local interval = math.max(0.25, tonumber(getConfig().reconcileInterval) or 0.25)
    if CurTime() < Materializer.NextReconcileAt then
        return
    end
    Materializer.NextReconcileAt = CurTime() + interval
    Materializer:Reconcile()
end)