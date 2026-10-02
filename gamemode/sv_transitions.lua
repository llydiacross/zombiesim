ZM_Transitions = ZM_Transitions or {}
local Transitions = ZM_Transitions

util.AddNetworkString("ZM.PlayerTransitionEntry")
util.AddNetworkString("ZM.PlayerTransitionExit")
util.AddNetworkString("ZM.CancelTransitionWalk")
util.AddNetworkString("ZM.LoadingHold")

// Mouse look is client-only input, so the client reports it to interrupt the arrival walk; exit sequences are committed.
net.Receive("ZM.CancelTransitionWalk", function(_, playerEntity)
    if IsValid(playerEntity) then
        playerEntity.ZM_TransitionEntry = nil
    end
end)

Transitions.ExitSequenceSeconds = 0.9
Transitions.ExitTimeoutSeconds = 10
// Source discards every usercmd's movement and buttons until curtime 3.0 after a fresh map load
// (CBasePlayer::PlayerRunCommand, MapLoad_NewGame with developer 0). Arrivals hold black until it lifts.
Transitions.EngineInputLockSeconds = 3
// Matches the old den arrival walk (110 u/s for 1.1 s); the fade is twice the standard 1.1 s arrival fade.
Transitions.DenArrivalDistance = 120
Transitions.DenArrivalFade = 2.2

function Transitions:GetEngineInputLockRemaining()
    return math.max(0, self.EngineInputLockSeconds - CurTime())
end

// Fades the player in from black after holdSeconds and tells the client to hide its HUD and show the loading screen
// for the black hold and the fade. The engine wait stays pending in the loading log until the hold ends.
function Transitions:FadeInFromBlack(playerEntity, fadeSeconds, holdSeconds)
    if holdSeconds > 0 then
        local stepId = ZM_Loading:Begin(playerEntity, "Waiting for engine input")
        timer.Simple(holdSeconds, function()
            ZM_Loading:Finish(playerEntity, stepId, "ok", "Engine input ready")
        end)
    end
    net.Start("ZM.LoadingHold")
    net.WriteFloat(holdSeconds)
    net.WriteFloat(fadeSeconds)
    net.Send(playerEntity)
    playerEntity:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), fadeSeconds, holdSeconds)
end

// Keeps a freshly loaded player behind black until the engine accepts movement, then fades in.
function Transitions:HoldForEngineInputLock(playerEntity, fadeSeconds)
    local hold = self:GetEngineInputLockRemaining()
    if hold > 0 then
        self:FadeInFromBlack(playerEntity, fadeSeconds or 1.1, hold)
    end
    return hold
end
Transitions.ExitSequenceId = Transitions.ExitSequenceId or 0
local exitChangelevelTimer = "ZM.TransitionExitChangelevel"
local exitWatchdogTimer = "ZM.TransitionExitWatchdog"

local directions = {
    north = { code = "N", opposite = "SOUTH", yaw = 90 },
    east = { code = "E", opposite = "WEST", yaw = 0 },
    south = { code = "S", opposite = "NORTH", yaw = 270 },
    west = { code = "W", opposite = "EAST", yaw = 180 }
}
local directionByCode = { N = "north", E = "east", S = "south", W = "west" }
local gateUseRange = 96

local function getHumanPlayerCount()
    local count = 0
    for _, playerEntity in ipairs(player.GetAll()) do
        if IsValid(playerEntity) and playerEntity:IsPlayer() and not playerEntity:IsBot() then
            count = count + 1
        end
    end
    return count
end

local function getGateDetails(entity)
    if not IsValid(entity) or (entity:GetClass() ~= "trigger_multiple" and entity:GetClass() ~= "func_button") then
        return nil
    end

    local keys = entity:GetKeyValues()
    local authoredDirection = directionByCode[string.match(entity:GetName() or "", "^zm_transition_gate_([NESW])$")]
    if tostring(keys.zm_transition_gate) ~= "1" and not authoredDirection then
        return nil
    end

    local directionName = string.lower(tostring(keys.zm_transition_direction or ""))
    if directionName == "" then directionName = authoredDirection or "" end
    local direction = directions[directionName]
    if not direction or (authoredDirection and directionName ~= authoredDirection) then
        return nil
    end

    local mode = string.lower(tostring(keys.zm_transition_mode or "any"))
    if mode ~= "any" and mode ~= "road" and mode ~= "highway" then
        return nil
    end

    return directionName, direction, mode
end

// Gate triggers are not networked, so their centres are published per direction as Global2 vectors
// (ZMTransitionGate_<code>_<index>, count in ZMTransitionGateCount_<code>) for the minimap waypoint marker.
function Transitions:InitializeGates()
    local centres = {}
    for _, entity in ipairs(ents.FindByClass("trigger_multiple")) do
        local directionName, direction = getGateDetails(entity)
        if directionName then
            entity:SetNWBool("ZMTransitionGate", true)
            entity:SetNWString("ZMTransitionDirection", directionName)
            centres[direction.code] = centres[direction.code] or {}
            table.insert(centres[direction.code], entity:WorldSpaceCenter())
        end
    end
    for _, direction in pairs(directions) do
        local list = centres[direction.code] or {}
        SetGlobal2Int("ZMTransitionGateCount_" .. direction.code, #list)
        for index, centre in ipairs(list) do
            SetGlobal2Vector("ZMTransitionGate_" .. direction.code .. "_" .. index, centre)
        end
    end
end

function Transitions:FindNearbyGate(playerEntity)
    local nearestGate
    local nearestDistance = gateUseRange * gateUseRange
    for _, entity in ipairs(ents.FindByClass("trigger_multiple")) do
        if getGateDetails(entity) then
            local nearestPoint = entity:NearestPoint(playerEntity:GetPos())
            local distance = playerEntity:GetPos():DistToSqr(nearestPoint)
            if distance <= nearestDistance then
                nearestGate = entity
                nearestDistance = distance
            end
        end
    end
    return nearestGate
end

function Transitions:CheckDoorTransition(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or playerEntity.ZM_PersistentStateLoaded ~= true then
        return false, "player_not_ready"
    end
    if getHumanPlayerCount() ~= 1 then
        return false, "one_human_required"
    end
    if GAMEMODE.PlayerWorldMapTransitionQueued or GAMEMODE.OriginSafeZoneTransitionQueued
        or (ZM_MapBatch and ZM_MapBatch:IsActive()) then
        return false, "transition_queued"
    end
    return true
end

local function getEntryKey(profile)
    return "zombiesim_transition_entry_" .. tostring(profile or "city")
end

function Transitions:ClearPendingEntry(playerEntity)
    playerEntity:RemovePData(getEntryKey(ZM_World and ZM_World.ActiveProfile))
end

function Transitions:SetPendingEntryRecord(playerEntity, entry)
    local hasAnchorClass = type(entry) == "table" and type(entry.anchorClass) == "string" and entry.anchorClass ~= ""
    local hasLandmark = type(entry) == "table" and type(entry.landmark) == "string" and entry.landmark ~= ""
    if not hasAnchorClass and not hasLandmark then
        return false, "Pending transition entry needs an anchor class or legacy landmark"
    end
    if entry.anchorClass ~= nil and not hasAnchorClass then
        return false, "Pending transition anchor class is invalid"
    end
    if entry.landmark ~= nil and not hasLandmark then
        return false, "Pending transition landmark is invalid"
    end
    if entry.yaw ~= nil and tonumber(entry.yaw) == nil then
        return false, "Pending transition yaw is invalid"
    end
    if entry.position ~= nil and (type(entry.position) ~= "table" or tonumber(entry.position[1]) == nil
        or tonumber(entry.position[2]) == nil or tonumber(entry.position[3]) == nil) then
        return false, "Pending transition position is invalid"
    end

    local encoded = util.TableToJSON(entry, false)
    if type(encoded) ~= "string" or encoded == "" then
        return false, "Could not encode pending transition entry"
    end
    playerEntity:SetPData(getEntryKey(ZM_World.ActiveProfile), encoded)
    return true
end

function Transitions:SetPendingEntry(playerEntity, directionName, direction)
    local entry = {
        direction = directionName,
        landmark = direction.opposite .. "_ENTRANCE",
        yaw = direction.yaw
    }
    local saved = self:SetPendingEntryRecord(playerEntity, entry)
    if not saved then
        return nil
    end
    return entry
end

function Transitions:FindPendingEntryAnchor(entry)
    local anchors
    if type(entry.anchorClass) == "string" and entry.anchorClass ~= "" then
        anchors = ents.FindByClass(entry.anchorClass)
    elseif type(entry.landmark) == "string" and entry.landmark ~= "" then
        anchors = ents.FindByName(entry.landmark)
    else
        return nil
    end

    for _, anchor in ipairs(anchors or {}) do
        if IsValid(anchor) then
            return anchor
        end
    end

    if entry.anchorClass == "zn_safezone_arrival" then
        for _, anchor in ipairs(ents.FindByClass("info_player_start")) do
            if IsValid(anchor) then
                return anchor
            end
        end
    end
    return nil
end

function Transitions:IsPlayerHullClear(playerEntity, position)
    if not playerEntity.GetHull then
        return true
    end
    local mins, maxs = playerEntity:GetHull()
    local trace = util.TraceHull({
        start = position + Vector(0, 0, 1),
        endpos = position + Vector(0, 0, 1),
        mins = mins,
        maxs = maxs,
        mask = MASK_PLAYERSOLID,
        filter = playerEntity
    })
    return not trace.StartSolid
end

function Transitions:ApplyPendingEntry(playerEntity)
    local key = getEntryKey(ZM_World and ZM_World.ActiveProfile)
    local encoded = playerEntity:GetPData(key, "")
    if encoded == "" then
        return false
    end

    local entry = util.JSONToTable(encoded)
    playerEntity:RemovePData(key)
    if type(entry) ~= "table"
        or (type(entry.anchorClass) ~= "string" and type(entry.landmark) ~= "string")
        or (entry.anchorClass ~= nil and entry.anchorClass == "")
        or (entry.landmark ~= nil and entry.landmark == "")
        or (entry.yaw ~= nil and tonumber(entry.yaw) == nil) then
        return false
    end
    if ZM_AFK then ZM_AFK:Clear(playerEntity) end

    local entryAnchor = self:FindPendingEntryAnchor(entry)
    local position = type(entry.position) == "table" and tonumber(entry.position[1]) and tonumber(entry.position[2])
        and tonumber(entry.position[3]) and Vector(tonumber(entry.position[1]), tonumber(entry.position[2]), tonumber(entry.position[3])) or nil
    if position and IsValid(entryAnchor) and not self:IsPlayerHullClear(playerEntity, position) then
        // A recorded point can be stale after a map rebuild; never place the player inside geometry.
        ErrorNoHalt("[ZombieSim] Recorded transition position is obstructed; using the authored anchor.\n")
        position = nil
        entry.yaw = nil
    end
    if position then
        playerEntity:SetPos(position)
    elseif IsValid(entryAnchor) then
        playerEntity:SetPos(entryAnchor:GetPos())
    elseif type(entry.anchorClass) == "string" then
        ErrorNoHalt("[ZombieSim] Could not find pending transition anchor class '" .. entry.anchorClass .. "'.\n")
    end
    local yaw = tonumber(entry.yaw)
    if not yaw and IsValid(entryAnchor) then
        yaw = entryAnchor:GetAngles().y
    end
    if not yaw then
        return false
    end
    playerEntity:SetEyeAngles(Angle(0, yaw, 0))
    local hold = self:GetEngineInputLockRemaining()
    local inDen = entry.anchorClass == "zn_safezone_arrival"
        and type(playerEntity.CurrentSafeZoneId) == "string" and playerEntity.CurrentSafeZoneId ~= ""
    if inDen then
        // Den arrivals skip the scripted walk: place the player where the walk would end (clear of the exit door's
        // use radius) and hold a longer fade instead.
        local origin = playerEntity:GetPos()
        local mins, maxs = playerEntity:GetHull()
        local trace = util.TraceHull({
            start = origin,
            endpos = origin + Angle(0, yaw, 0):Forward() * Transitions.DenArrivalDistance,
            mins = mins,
            maxs = maxs,
            mask = MASK_PLAYERSOLID,
            filter = playerEntity
        })
        if not trace.StartSolid then
            playerEntity:SetPos(trace.HitPos)
        end
        playerEntity.ZM_TransitionEntry = nil
        ZM_Loading:Step(playerEntity, "Entered safe zone " .. playerEntity.CurrentSafeZoneId)

        net.Start("ZM.PlayerTransitionEntry")
        net.WriteFloat(yaw)
        net.WriteFloat(0)
        net.WriteFloat(0)
        net.WriteFloat(hold)
        net.Send(playerEntity)
        self:FadeInFromBlack(playerEntity, Transitions.DenArrivalFade, hold)
        return true
    end

    // Den exits take half a gate walk; gates keep the full walk. The walk starts once the engine input lock lifts.
    local walkSpeed = entry.anchorClass == "zn_safezone_arrival" and 80 or 160
    local startTime = CurTime() + hold
    playerEntity.ZM_TransitionEntry = {
        startTime = startTime,
        untilTime = startTime + 1.1,
        yaw = yaw,
        speed = walkSpeed
    }
    local arrivalSide = string.lower(string.match(tostring(entry.landmark or ""), "^(%a+)_ENTRANCE$") or "arrival")
    ZM_Loading:Step(playerEntity, entry.anchorClass == "zn_safezone_arrival" and "Placed outside the safe-zone door"
        or "Placed at the " .. arrivalSide .. " gate")

    net.Start("ZM.PlayerTransitionEntry")
    net.WriteFloat(yaw)
    net.WriteFloat(1.1)
    net.WriteFloat(walkSpeed)
    net.WriteFloat(hold)
    net.Send(playerEntity)
    self:FadeInFromBlack(playerEntity, 1.1, hold)
    return true
end

local movementButtons = bit.bor(IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT, IN_JUMP)

function Transitions.HasMovementInput(moveData)
    return bit.band(moveData:GetButtons(), movementButtons) ~= 0
end

hook.Add("SetupMove", "ZM.TransitionEntryWalk", function(playerEntity, moveData)
    local exit = playerEntity.ZM_TransitionExit
    if exit then
        moveData:SetMoveAngles(Angle(0, exit.yaw, 0))
        moveData:SetForwardSpeed(CurTime() < exit.untilTime and 100 or 0)
        moveData:SetSideSpeed(0)
        return
    end

    local entry = playerEntity.ZM_TransitionEntry
    if not entry then
        return
    end
    // Hold still behind the black screen until the walk starts.
    if entry.startTime and CurTime() < entry.startTime then
        moveData:SetForwardSpeed(0)
        moveData:SetSideSpeed(0)
        return
    end
    // Any movement input interrupts the arrival walk and hands control straight back to the player.
    if CurTime() >= entry.untilTime or Transitions.HasMovementInput(moveData) then
        playerEntity.ZM_TransitionEntry = nil
        return
    end

    moveData:SetMoveAngles(Angle(0, entry.yaw, 0))
    moveData:SetForwardSpeed(entry.speed or 160)
    moveData:SetSideSpeed(0)
end)

local function sendExitState(playerEntity, active, yaw, duration, title)
    net.Start("ZM.PlayerTransitionExit")
    net.WriteBool(active)
    net.WriteFloat(yaw or 0)
    net.WriteFloat(duration or 0)
    if active then
        net.WriteString(title or "")
    end
    net.Send(playerEntity)
end

function Transitions:IsExitSequenceActive()
    return self.ActiveExit ~= nil
end

// Faces the player toward the exit, raises the camera, and fades to black before the queued level change.
// A watchdog restores view, input, and persisted state if the level never changes.
function Transitions:BeginExitSequence(playerEntity, command, options)
    options = options or {}
    local duration = self.ExitSequenceSeconds
    local yaw = tonumber(options.yaw) or playerEntity:EyeAngles().y
    local sequenceId = self.ExitSequenceId + 1
    self.ExitSequenceId = sequenceId
    self.ActiveExit = { player = playerEntity, onCancel = options.onCancel, id = sequenceId }
    if ZM_AFK then ZM_AFK:Clear(playerEntity) end

    playerEntity.ZM_TransitionExit = { untilTime = CurTime() + duration, yaw = yaw }
    // The client turns the view toward the exit smoothly; snapping eye angles here would flip a player who backs in.
    // Its loading screen shows only the title: the level change would cut off any step log.
    sendExitState(playerEntity, true, yaw, duration, options.loadingTitle)
    playerEntity:ScreenFade(bit.bor(SCREENFADE.OUT, SCREENFADE.STAYOUT), Color(0, 0, 0), duration, 0)

    timer.Create(exitChangelevelTimer, duration, 1, function()
        if self.ExitSequenceId ~= sequenceId then return end
        game.ConsoleCommand(command)
    end)
    timer.Create(exitWatchdogTimer, duration + self.ExitTimeoutSeconds, 1, function()
        if self.ExitSequenceId ~= sequenceId then return end
        self:CancelExitSequence("The transition timed out. Please try again.")
    end)
end

// Clears the black screen, releases input, rolls back persisted transition state, and reports why.
function Transitions:CancelExitSequence(message)
    local active = self.ActiveExit
    self.ActiveExit = nil
    self.ExitSequenceId = self.ExitSequenceId + 1
    timer.Remove(exitChangelevelTimer)
    timer.Remove(exitWatchdogTimer)
    GAMEMODE.PlayerWorldMapTransitionQueued = false
    if not active then
        return false
    end

    local playerEntity = active.player
    if not IsValid(playerEntity) then
        return true
    end
    playerEntity.ZM_TransitionExit = nil
    if type(active.onCancel) == "function" then
        active.onCancel(playerEntity)
    else
        self:ClearPendingEntry(playerEntity)
    end
    sendExitState(playerEntity, false)
    playerEntity:ScreenFade(bit.bor(SCREENFADE.PURGE, SCREENFADE.IN), Color(0, 0, 0), 0.4, 0)
    if message then
        playerEntity:PrintMessage(HUD_PRINTCENTER, message)
    end
    return true
end

hook.Add("PlayerDisconnected", "ZM.CancelTransitionExit", function(playerEntity)
    local active = Transitions.ActiveExit
    if active and active.player == playerEntity then
        Transitions.ActiveExit = nil
        Transitions.ExitSequenceId = Transitions.ExitSequenceId + 1
        timer.Remove(exitChangelevelTimer)
        timer.Remove(exitWatchdogTimer)
        GAMEMODE.PlayerWorldMapTransitionQueued = false
    end
end)

function Transitions:TryUseGate(playerEntity, entity)
    local directionName, direction, mode = getGateDetails(entity)
    if not direction then
        return
    end
    local canTransition, guardError = self:CheckDoorTransition(playerEntity)
    if not canTransition and guardError == "one_human_required" then
        playerEntity:PrintMessage(HUD_PRINTCENTER, "Transitions require one human player.")
    end
    if not canTransition then
        return false
    end

    local targetCell = playerEntity:CanTravelToNeighbour(direction.code, mode, false)
    if not targetCell then
        playerEntity:PrintMessage(HUD_PRINTCENTER, "This route is unavailable.")
        return false
    end

    local worldX, worldY = ZM_World:GetWorldCoordinates(targetCell)
    if not worldX or not worldY then
        ErrorNoHalt("[ZombieSim] Transition target has no logical world coordinates.\n")
        return false
    end
    local entry = Transitions:SetPendingEntry(playerEntity, directionName, direction)
    if not entry then
        playerEntity:PrintMessage(HUD_PRINTCENTER, "Could not prepare the transition.")
        return false
    end
    local previousX, previousY = playerEntity:GetWorldCellCoordinates()
    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        Transitions:ClearPendingEntry(playerEntity)
        ErrorNoHalt("[ZombieSim] Could not persist transition destination: " .. tostring(positionError) .. "\n")
        return false
    end

    local queued = GAMEMODE:EnsurePlayerWorldMap(playerEntity, entry.landmark, {
        cinematic = true,
        forceReload = true,
        yaw = direction.yaw,
        onCancel = function(cancelledPlayer)
            Transitions:ClearPendingEntry(cancelledPlayer)
            if previousX ~= nil and previousY ~= nil then
                local restored, restoreError = cancelledPlayer:SetWorldCell(previousX, previousY)
                if not restored then
                    ErrorNoHalt("[ZombieSim] Could not roll back gate transition coordinates: " .. tostring(restoreError) .. "\n")
                end
            end
        end
    })
    if not queued then
        Transitions:ApplyPendingEntry(playerEntity)
    end
    return false
end

hook.Add("InitPostEntity", "ZM.InitializeTransitionGates", function()
    Transitions:InitializeGates()
end)

// Trigger brushes are not networked to clients, so the server publishes the nearby gate direction for HUD prompts,
// plus whether TryUseGate would refuse it (a barrier or missing neighbour) so the client can show PATH BLOCKED.
timer.Create("ZM.PublishNearbyTransitionGate", 0.2, 0, function()
    for _, playerEntity in ipairs(player.GetHumans()) do
        local directionName = ""
        local blocked = false
        if playerEntity:Alive() then
            local gate = Transitions:FindNearbyGate(playerEntity)
            if gate then
                local gateDirectionName, direction, mode = getGateDetails(gate)
                directionName = gateDirectionName or ""
                blocked = direction ~= nil and not playerEntity:CanTravelToNeighbour(direction.code, mode, false)
            end
        end
        playerEntity:SetNWString("ZMNearbyTransitionGate", directionName)
        playerEntity:SetNWBool("ZMNearbyTransitionGateBlocked", blocked)
    end
end)

hook.Add("PlayerUse", "ZM.UseTransitionGate", function(playerEntity, entity)
    return Transitions:TryUseGate(playerEntity, entity)
end)

hook.Add("KeyPress", "ZM.UseNearbyTransitionGate", function(playerEntity, key)
    if key ~= IN_USE or not IsValid(playerEntity) or not playerEntity:IsPlayer() then
        return
    end

    local gate = Transitions:FindNearbyGate(playerEntity)
    if gate then
        Transitions:TryUseGate(playerEntity, gate)
    end
end)