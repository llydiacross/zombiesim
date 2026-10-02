ZM_SafeZoneDoors = ZM_SafeZoneDoors or {}
local Doors = ZM_SafeZoneDoors
local Transitions = ZM_Transitions

local defaultUseRadius = 96
local maximumUseRadius = 512

local function activeMapName()
    local mapName = game.GetMap()
    return string.lower(string.match(mapName, "([^/]+)$") or mapName)
end

local function transitionMapName(mapName)
    return string.lower(string.match(mapName or "", "([^/]+)$") or mapName or "")
end

local function sameMap(left, right)
    return transitionMapName(left) ~= "" and transitionMapName(left) == transitionMapName(right)
end

local function getReturnKey()
    return "zombiesim_safezone_return_" .. tostring(ZM_World and ZM_World.ActiveProfile or "city")
end

// The zn_safezone_door marker is the authored doorstep in front of the door; the visible door is the nearest
// prop_dynamic within this reach. Tunnel exits have no door prop.
Doors.DoorPropSearchRadius = 128
// Den exit places the player this far out from the doorstep, so the exit walk carries them out of the use radius.
Doors.ReturnStepOut = 16
// Minimum distance from the door plane to the return point; the player hull is 32 units wide, so this leaves a gap.
Doors.ReturnDoorClearance = 48

function Doors:FindDoorProp(door)
    local origin = door:GetPos()
    local nearest
    local nearestDistance
    for _, entity in ipairs(ents.FindInSphere(origin, self.DoorPropSearchRadius)) do
        if entity ~= door and IsValid(entity) and string.StartWith(entity:GetClass(), "prop_dynamic") and entity.WorldSpaceAABB then
            local mins, maxs = entity:WorldSpaceAABB()
            local size = maxs - mins
            local distance = origin:DistToSqr((mins + maxs) * 0.5)
            if math.max(size.x, size.y) >= 8 and (nearestDistance == nil or distance < nearestDistance) then
                nearest = entity
                nearestDistance = distance
            end
        end
    end
    return nearest
end

// The point a door transition faces: the door prop's centre (its origin is off-centre), else the marker.
function Doors:GetDoorTarget(door)
    local prop = self:FindDoorProp(door)
    if prop then
        local mins, maxs = prop:WorldSpaceAABB()
        return (mins + maxs) * 0.5
    end
    return door:GetPos()
end

// A door prop is a thin slab: its thin horizontal axis is the doorway normal, pointing toward the doorstep marker
// (or toward the player when the marker sits in the door plane). The return point keeps the marker's position
// along the door but is pushed at least ReturnDoorClearance out from the plane so the hull never overlaps the door.
// Without a prop, outward is from the marker toward the player.
local function doorwayReturnPoint(door, playerPosition)
    local doorstep = door:GetPos()
    local prop = Doors:FindDoorProp(door)
    local outward
    if prop then
        local mins, maxs = prop:WorldSpaceAABB()
        local size = maxs - mins
        local centre = (mins + maxs) * 0.5
        outward = size.x <= size.y and Vector(1, 0, 0) or Vector(0, 1, 0)
        local doorstepOffset = (doorstep - centre):Dot(outward)
        local sideOffset = math.abs(doorstepOffset) >= 4 and doorstepOffset or (playerPosition - centre):Dot(outward)
        if sideOffset < 0 then
            outward = -outward
        end
        local planeDistance = math.max((doorstep - centre):Dot(outward) + Doors.ReturnStepOut, Doors.ReturnDoorClearance)
        local position = doorstep + outward * (planeDistance - (doorstep - centre):Dot(outward))
        return position, outward:Angle().y
    end
    outward = playerPosition - doorstep
    outward.z = 0
    if outward:LengthSqr() < 1 then
        return nil
    end
    outward:Normalize()
    local position = doorstep + outward * Doors.ReturnStepOut
    return position, outward:Angle().y
end

// Remembers the spot outside the used city door, facing away from it, so den exit returns the player there.
function Doors:RecordReturnPoint(playerEntity, door, cityMap)
    if not IsValid(door) then
        return
    end
    local position, yaw = doorwayReturnPoint(door, playerEntity:GetPos())
    if not position then
        return
    end
    playerEntity:SetPData(getReturnKey(), util.TableToJSON({
        map = transitionMapName(cityMap),
        position = { position.x, position.y, position.z },
        yaw = yaw
    }, false))
end

function Doors:GetReturnPoint(playerEntity, cityMap)
    local record = util.JSONToTable(playerEntity:GetPData(getReturnKey(), "") or "")
    if type(record) ~= "table" or not sameMap(record.map, cityMap) or tonumber(record.yaw) == nil
        or type(record.position) ~= "table" then
        return nil
    end
    return record
end

function Doors:GetDoorDetails(entity)
    if not IsValid(entity) or entity:GetClass() ~= "zn_safezone_door" or entity.ZM_RemovedInstanceCopy then
        return nil
    end

    local keys = entity.ZM_Config or entity:GetKeyValues() or {}
    local role = string.lower(string.Trim(tostring(keys.role or "")))
    if role ~= "enter" and role ~= "exit" then
        return nil
    end

    local radius = tonumber(keys.use_radius)
    if radius == nil then
        radius = defaultUseRadius
    end
    if radius ~= radius or radius <= 0 or radius > maximumUseRadius then
        ErrorNoHalt("[ZombieSim] zn_safezone_door " .. entity:EntIndex() .. " has invalid use_radius '" .. tostring(keys.use_radius) .. "'.\n")
        return nil
    end
    return role, radius
end

// VBSP leaves ZombieSim point entities inside a func_instance at template-local coordinates; the cell generator
// re-emits them in cell space with zm_instance_transformed. When any transformed copy exists, the raw copies are stale.
function Doors:RemoveUntransformedInstanceCopies()
    for _, className in ipairs({ "zn_safezone_door", "zn_safezone_arrival" }) do
        local transformed, raw = false, {}
        for _, entity in ipairs(ents.FindByClass(className)) do
            local keys = entity.ZM_Config or {}
            if tostring(keys.zm_instance_transformed or "") == "1" then
                transformed = true
            else
                table.insert(raw, entity)
            end
        end
        if transformed then
            // Entity:Remove is deferred to the end of the frame, so flag the copies for callers in this frame.
            for _, entity in ipairs(raw) do
                entity.ZM_RemovedInstanceCopy = true
                entity:Remove()
            end
        end
    end
end

// Door markers leave the client PVS, so their positions and roles are also published as Global2 values
// (ZMSafeZoneDoor_<index>, ZMSafeZoneDoorRole_<index>, count in ZMSafeZoneDoorCount) for always-visible map markers.
function Doors:InitializeDoors()
    self:RemoveUntransformedInstanceCopies()
    local published = 0
    for _, entity in ipairs(ents.FindByClass("zn_safezone_door")) do
        local role, radius = self:GetDoorDetails(entity)
        if entity.ZM_RemovedInstanceCopy then
            // Template-local copy pending removal this frame.
        elseif role then
            entity:SetNWBool("ZMSafeZoneDoor", true)
            entity:SetNWString("ZMSafeZoneDoorRole", role)
            entity:SetNWFloat("ZMSafeZoneDoorRadius", radius)
            published = published + 1
            SetGlobal2Vector("ZMSafeZoneDoor_" .. published, entity:GetPos())
            SetGlobal2String("ZMSafeZoneDoorRole_" .. published, role)
        else
            ErrorNoHalt("[ZombieSim] Ignoring zn_safezone_door " .. entity:EntIndex() .. " with an invalid role or use_radius.\n")
        end
    end
    SetGlobal2Int("ZMSafeZoneDoorCount", published)
end

function Doors:FindNearbyDoor(playerEntity)
    if not IsValid(playerEntity) then
        return nil
    end
    local position = playerEntity:GetPos()
    local nearestDoor
    local nearestDistance
    for _, entity in ipairs(ents.FindByClass("zn_safezone_door")) do
        local role, radius = self:GetDoorDetails(entity)
        if role then
            local distance = position:DistToSqr(entity:GetPos())
            if distance <= radius * radius and (nearestDistance == nil or distance < nearestDistance) then
                nearestDoor = entity
                nearestDistance = distance
            end
        end
    end
    return nearestDoor
end

function Doors:Notify(playerEntity, message)
    if IsValid(playerEntity) and playerEntity:IsPlayer() then
        playerEntity:PrintMessage(HUD_PRINTCENTER, message)
    end
end

function Doors:CancelTransition(playerEntity, previousSafeZoneId, message, previousWorldX, previousWorldY)
    Transitions:ClearPendingEntry(playerEntity)
    if previousWorldX ~= nil and previousWorldY ~= nil then
        local restored, restoreError = playerEntity:SetWorldCell(previousWorldX, previousWorldY)
        if not restored then
            ErrorNoHalt("[ZombieSim] Could not roll back safe-zone transition coordinates: " .. tostring(restoreError) .. "\n")
            self:Notify(playerEntity, "The transition failed and your world cell could not be restored.")
            return false
        end
    end
    if playerEntity.CurrentSafeZoneId ~= previousSafeZoneId then
        local restored, restoreError = playerEntity:SetCurrentSafeZone(previousSafeZoneId)
        if not restored then
            ErrorNoHalt("[ZombieSim] Could not roll back safe-zone transition state: " .. tostring(restoreError) .. "\n")
            self:Notify(playerEntity, "The transition failed and your safe-zone state could not be restored.")
            return false
        end
    end
    if message then
        self:Notify(playerEntity, message)
    end
    return false
end

function Doors:StartMapTransition(playerEntity, destination, previousSafeZoneId, previousWorldX, previousWorldY, door)
    local facingYaw
    if IsValid(door) then
        local offset = self:GetDoorTarget(door) - playerEntity:GetPos()
        offset.z = 0
        if offset:LengthSqr() > 1 then
            facingYaw = offset:Angle().y
        end
    end
    local queued = GAMEMODE:EnsurePlayerWorldMap(playerEntity, nil, {
        cinematic = true,
        yaw = facingYaw,
        // Leaving a den says goodbye; entering one keeps the standard loading title.
        loadingTitle = previousSafeZoneId ~= nil and "GOODBYE" or nil,
        onCancel = function(cancelledPlayer)
            self:CancelTransition(cancelledPlayer, previousSafeZoneId, nil, previousWorldX, previousWorldY)
        end
    })
    if queued then
        return true
    end
    if sameMap(activeMapName(), destination) then
        if Transitions:ApplyPendingEntry(playerEntity) then
            return true
        end
        return self:CancelTransition(playerEntity, previousSafeZoneId, "Could not place you at the safe-zone entrance.", previousWorldX, previousWorldY)
    end
    return self:CancelTransition(playerEntity, previousSafeZoneId, "Could not queue the safe-zone transition.", previousWorldX, previousWorldY)
end

function Doors:Enter(playerEntity, door)
    if type(playerEntity.CurrentSafeZoneId) == "string" and playerEntity.CurrentSafeZoneId ~= "" then
        self:Notify(playerEntity, "You are already inside a safe zone.")
        return false
    end

    local cell, cellError = playerEntity:GetWorldCell()
    if not cell then
        self:Notify(playerEntity, "Your current world cell could not be resolved.")
        ErrorNoHalt("[ZombieSim] Safe-zone entry has no current world cell: " .. tostring(cellError) .. "\n")
        return false
    end
    local cityMap = ZM_World:GetMapPath(cell)
    if not cityMap or not sameMap(activeMapName(), cityMap) then
        self:Notify(playerEntity, "This safe-zone door does not belong to your current cell.")
        return false
    end

    local safeZone = ZM_SafeZones:GetForCell(cell)
    if not safeZone or tonumber(safeZone.cell) ~= tonumber(cell.id) then
        self:Notify(playerEntity, "This cell has no matching safe zone.")
        return false
    end
    local destination = ZM_SafeZones:GetMap(safeZone.id)
    if not destination then
        self:Notify(playerEntity, "The safe-zone map is unavailable.")
        ErrorNoHalt("[ZombieSim] Could not resolve safe-zone map for " .. tostring(safeZone.id) .. ".\n")
        return false
    end

    local pending, pendingError = Transitions:SetPendingEntryRecord(playerEntity, {
        anchorClass = "zn_safezone_arrival"
    })
    if not pending then
        self:Notify(playerEntity, "Could not prepare the safe-zone entry.")
        ErrorNoHalt("[ZombieSim] Could not save pending safe-zone entry: " .. tostring(pendingError) .. "\n")
        return false
    end

    local saved, saveError = playerEntity:SetCurrentSafeZone(safeZone.id)
    if not saved then
        Transitions:ClearPendingEntry(playerEntity)
        self:Notify(playerEntity, "Could not save your safe-zone state; entry was cancelled.")
        ErrorNoHalt("[ZombieSim] Could not persist safe-zone entry: " .. tostring(saveError) .. "\n")
        return false
    end
    self:RecordReturnPoint(playerEntity, door, cityMap)
    return self:StartMapTransition(playerEntity, destination, nil, nil, nil, door)
end

function Doors:Exit(playerEntity, door)
    local safeZoneId = playerEntity.CurrentSafeZoneId
    if type(safeZoneId) ~= "string" or safeZoneId == "" then
        self:Notify(playerEntity, "You are not inside a safe zone.")
        return false
    end

    local safeZone = ZM_SafeZones:Get(safeZoneId)
    local denMap = ZM_SafeZones:GetMap(safeZoneId)
    if not safeZone or not denMap or not sameMap(activeMapName(), denMap) then
        self:Notify(playerEntity, "Your current safe zone does not match this den.")
        ErrorNoHalt("[ZombieSim] Safe-zone exit does not match the active den map for " .. safeZoneId .. ".\n")
        return false
    end
    local entranceCell = ZM_SafeZones:GetEntranceCell(safeZoneId)
    local destination = entranceCell and ZM_World:GetMapPath(entranceCell) or nil
    local worldX, worldY
    if entranceCell then
        worldX, worldY = ZM_World:GetWorldCoordinates(entranceCell)
    end
    if not entranceCell or not destination or worldX == nil or worldY == nil then
        self:Notify(playerEntity, "The city entrance for this safe zone is unavailable.")
        ErrorNoHalt("[ZombieSim] Could not resolve city entrance for safe zone " .. safeZoneId .. ".\n")
        return false
    end

    local exitEntry = { anchorClass = "zn_safezone_arrival" }
    local returnPoint = self:GetReturnPoint(playerEntity, destination)
    if returnPoint then
        exitEntry.position = returnPoint.position
        exitEntry.yaw = returnPoint.yaw
    end
    local pending, pendingError = Transitions:SetPendingEntryRecord(playerEntity, exitEntry)
    if not pending then
        self:Notify(playerEntity, "Could not prepare the safe-zone exit.")
        ErrorNoHalt("[ZombieSim] Could not save pending safe-zone exit: " .. tostring(pendingError) .. "\n")
        return false
    end

    local currentX, currentY = playerEntity:GetWorldCellCoordinates()
    local movedCell = currentX ~= worldX or currentY ~= worldY
    local saved, saveError
    if movedCell then
        saved, saveError = playerEntity:SetWorldCell(worldX, worldY)
    else
        saved, saveError = playerEntity:SetCurrentSafeZone(nil)
    end
    if not saved then
        Transitions:ClearPendingEntry(playerEntity)
        self:Notify(playerEntity, "Could not save your safe-zone exit; you remain in the den.")
        ErrorNoHalt("[ZombieSim] Could not persist safe-zone exit: " .. tostring(saveError) .. "\n")
        return false
    end
    return self:StartMapTransition(playerEntity, destination, safeZoneId,
        movedCell and currentX or nil, movedCell and currentY or nil, door)
end

function Doors:TryUseDoor(playerEntity, entity)
    local role = self:GetDoorDetails(entity)
    if not role then
        return false
    end
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not playerEntity:Alive() then
        return false
    end

    local canTransition, guardError = Transitions:CheckDoorTransition(playerEntity)
    if not canTransition then
        if guardError == "player_not_ready" then
            self:Notify(playerEntity, "Your player data is not ready for a transition.")
        elseif guardError == "one_human_required" then
            self:Notify(playerEntity, "Safe-zone transitions require one human player.")
        else
            self:Notify(playerEntity, "Another transition is already in progress.")
        end
        return false
    end

    if role == "enter" then
        return self:Enter(playerEntity, entity)
    end
    return self:Exit(playerEntity, entity)
end

hook.Add("InitPostEntity", "ZM.InitializeSafeZoneDoors", function()
    Doors:InitializeDoors()
end)

hook.Add("KeyPress", "ZM.UseNearbySafeZoneDoor", function(playerEntity, key)
    if key ~= IN_USE or not IsValid(playerEntity) or not playerEntity:IsPlayer() then
        return
    end
    local door = Doors:FindNearbyDoor(playerEntity)
    if door then
        Doors:TryUseDoor(playerEntity, door)
    end
end)

// Lists every safe-zone door and arrival point with its distance to the first human, for placement diagnosis.
concommand.Add("zn_safezone_door_status", function(caller)
    if IsValid(caller) and not caller:IsAdmin() then return end
    local human = player.GetHumans()[1]
    local origin = IsValid(human) and human:GetPos() or nil
    print("[ZombieSim] Safe-zone doors on " .. activeMapName() .. (origin and (" (player at " .. tostring(origin) .. ")") or ""))
    for _, className in ipairs({ "zn_safezone_door", "zn_safezone_arrival" }) do
        for _, entity in ipairs(ents.FindByClass(className)) do
            local role, radius = Doors:GetDoorDetails(entity)
            print(string.format("  %s #%d at %s angles %s role %s radius %s distance %s", className, entity:EntIndex(),
                tostring(entity:GetPos()), tostring(entity:GetAngles()), tostring(role), tostring(radius),
                origin and string.format("%.0f", origin:Distance(entity:GetPos())) or "-"))
        end
    end
end)
