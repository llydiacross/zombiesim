ZM_Transitions = ZM_Transitions or {}
local Transitions = ZM_Transitions

util.AddNetworkString("ZM.PlayerTransitionEntry")

local directions = {
    north = { code = "N", opposite = "SOUTH", yaw = 90 },
    east = { code = "E", opposite = "WEST", yaw = 0 },
    south = { code = "S", opposite = "NORTH", yaw = 270 },
    west = { code = "W", opposite = "EAST", yaw = 180 }
}
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
    if tostring(keys.zm_transition_gate) ~= "1" then
        return nil
    end

    local directionName = string.lower(tostring(keys.zm_transition_direction or ""))
    local direction = directions[directionName]
    if not direction then
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

local function getEntryKey(profile)
    return "zombiesim_transition_entry_" .. tostring(profile or "city")
end

function Transitions:ClearPendingEntry(playerEntity)
    playerEntity:RemovePData(getEntryKey(ZM_World and ZM_World.ActiveProfile))
end

function Transitions:SetPendingEntry(playerEntity, directionName, direction)
    local entry = {
        direction = directionName,
        landmark = direction.opposite .. "_ENTRANCE",
        yaw = direction.yaw
    }
    playerEntity:SetPData(getEntryKey(ZM_World.ActiveProfile), util.TableToJSON(entry, false))
    return entry
end

function Transitions:ApplyPendingEntry(playerEntity)
    local key = getEntryKey(ZM_World and ZM_World.ActiveProfile)
    local encoded = playerEntity:GetPData(key, "")
    if encoded == "" then
        return false
    end

    local entry = util.JSONToTable(encoded)
    playerEntity:RemovePData(key)
    if type(entry) ~= "table" or type(entry.landmark) ~= "string" or type(entry.yaw) ~= "number" then
        return false
    end

    local entryAnchor = ents.FindByName(entry.landmark)[1]
    if IsValid(entryAnchor) then
        playerEntity:SetPos(entryAnchor:GetPos())
    end
    playerEntity:SetEyeAngles(Angle(0, entry.yaw, 0))
    playerEntity.ZM_TransitionEntry = {
        untilTime = CurTime() + 1.1,
        yaw = entry.yaw
    }

    net.Start("ZM.PlayerTransitionEntry")
    net.WriteFloat(entry.yaw)
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
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or playerEntity.ZM_PersistentStateLoaded ~= true then
        return false
    end
    if getHumanPlayerCount() ~= 1 then
        playerEntity:PrintMessage(HUD_PRINTCENTER, "Transitions require one human player.")
        return false
    end
    if GAMEMODE.PlayerWorldMapTransitionQueued or (ZM_MapBatch and ZM_MapBatch:IsActive()) then
        return false
    end

    local targetCell = playerEntity:CanTravelToNeighbour(direction.code, mode, false)
    if not targetCell then
        playerEntity:PrintMessage(HUD_PRINTCENTER, "This route is unavailable.")
        return false
    end

    local worldX, worldY = ZM_World:GetWorldCoordinates(targetCell)
    if not worldX or not worldY then
        return false
    end
    local entry = Transitions:SetPendingEntry(playerEntity, directionName, direction)
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