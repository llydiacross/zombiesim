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

function Doors:GetDoorDetails(entity)
    if not IsValid(entity) or entity:GetClass() ~= "zn_safezone_door" then
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
            for _, entity in ipairs(raw) do entity:Remove() end
        end
    end
end

function Doors:InitializeDoors()
    self:RemoveUntransformedInstanceCopies()
    for _, entity in ipairs(ents.FindByClass("zn_safezone_door")) do
        local role, radius = self:GetDoorDetails(entity)
        if role then
            entity:SetNWBool("ZMSafeZoneDoor", true)
            entity:SetNWString("ZMSafeZoneDoorRole", role)
            entity:SetNWFloat("ZMSafeZoneDoorRadius", radius)
        else
            ErrorNoHalt("[ZombieSim] Ignoring zn_safezone_door " .. entity:EntIndex() .. " with an invalid role or use_radius.\n")
        end
    end
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
    self:Notify(playerEntity, message)
    return false
end

function Doors:StartMapTransition(playerEntity, destination, previousSafeZoneId, previousWorldX, previousWorldY)
    local queued = GAMEMODE:EnsurePlayerWorldMap(playerEntity)
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

function Doors:Enter(playerEntity)
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
    return self:StartMapTransition(playerEntity, destination, nil)
end

function Doors:Exit(playerEntity)
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

    local pending, pendingError = Transitions:SetPendingEntryRecord(playerEntity, {
        anchorClass = "zn_safezone_arrival"
    })
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
        movedCell and currentX or nil, movedCell and currentY or nil)
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
        return self:Enter(playerEntity)
    end
    return self:Exit(playerEntity)
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
