ZM_Transitions = ZM_Transitions or {}
local Transitions = ZM_Transitions

util.AddNetworkString("ZM.PlayerTransitionEntry")

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

function Transitions:InitializeGates()
    for _, entity in ipairs(ents.FindByClass("trigger_multiple")) do
        local directionName = getGateDetails(entity)
        if directionName then
            entity:SetNWBool("ZMTransitionGate", true)
            entity:SetNWString("ZMTransitionDirection", directionName)
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

    local entryAnchor = self:FindPendingEntryAnchor(entry)
    if IsValid(entryAnchor) then
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
    playerEntity.ZM_TransitionEntry = {
        untilTime = CurTime() + 1.1,
        yaw = yaw
    }

    net.Start("ZM.PlayerTransitionEntry")
    net.WriteFloat(yaw)
    net.WriteFloat(1.1)
    net.Send(playerEntity)
    return true
end

hook.Add("SetupMove", "ZM.TransitionEntryWalk", function(playerEntity, moveData)
    local entry = playerEntity.ZM_TransitionEntry
    if not entry then
        return
    end
    if CurTime() >= entry.untilTime then
        playerEntity.ZM_TransitionEntry = nil
        return
    end

    moveData:SetMoveAngles(Angle(0, entry.yaw, 0))
    moveData:SetForwardSpeed(160)
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
    local positioned, positionError = playerEntity:SetWorldCell(worldX, worldY)
    if not positioned then
        Transitions:ClearPendingEntry(playerEntity)
        ErrorNoHalt("[ZombieSim] Could not persist transition destination: " .. tostring(positionError) .. "\n")
        return false
    end

    local queued = GAMEMODE:EnsurePlayerWorldMap(playerEntity, entry.landmark)
    if not queued then
        Transitions:ApplyPendingEntry(playerEntity)
    end
    return false
end

hook.Add("InitPostEntity", "ZM.InitializeTransitionGates", function()
    Transitions:InitializeGates()
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