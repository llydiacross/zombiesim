ZM_WalkerSim = ZM_WalkerSim or {}
local WalkerSim = ZM_WalkerSim

WalkerSim.ApiVersion = 1
WalkerSim.Config = WalkerSim.Config or {
    minimumGroupSize = 4,
    maximumGroupSize = 64,
    progressPerTick = 4,
    attractionDecayPermille = 920,
    safeZonePenalty = 100000,
    ticketLifetimeTicks = 20,
    maximumTicketsPerRequest = 12
}
WalkerSim.ActiveProfile = WalkerSim.ActiveProfile or nil
WalkerSim.LastError = WalkerSim.LastError or nil
WalkerSim.SnapshotInterval = 0.5
WalkerSim.NextSnapshotAt = WalkerSim.NextSnapshotAt or 0

util.AddNetworkString("ZM.WalkerSnapshot")

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
        type(native.GetHordeSummaries) ~= "function" then
        return nil, "walker module does not provide the Phase 2 API"
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

    local started, startError = native.Start()
    if started ~= true then
        self.LastError = tostring(startError or "native worker could not start")
        return false, self.LastError
    end

    self.ActiveProfile = profile
    self.LastError = nil
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
    return native.GetStats()
end

function WalkerSim:GetCellSummary(cellId)
    local native, nativeError = getNative()
    if not native then
        return nil, nativeError
    end
    return native.GetCellSummary(cellId)
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

    net.Start("ZM.WalkerSnapshot")
        net.WriteString(ZM_World.ActiveProfile)
        net.WriteString(tostring(stats.GraphRevisionHash or ""))
        net.WriteString(tostring(stats.Tick or "0"))
        net.WriteUInt(math.max(0, tonumber(stats.TotalPopulation) or 0), 32)
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

local function writeStatusSnapshot(stats)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_status.json", util.TableToJSON(stats, true) or "{}")
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
    local native = getNative()
    if native then
        native.Stop()
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

hook.Add("Think", "ZombieSim.WalkerSim.BroadcastPreviewSnapshot", function()
    if CurTime() < WalkerSim.NextSnapshotAt then
        return
    end
    WalkerSim.NextSnapshotAt = CurTime() + WalkerSim.SnapshotInterval
    WalkerSim:BroadcastPreviewSnapshot()
end)