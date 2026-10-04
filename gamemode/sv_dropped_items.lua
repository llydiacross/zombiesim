ZM_DroppedItems = ZM_DroppedItems or {}
local Drops = ZM_DroppedItems
local Service = ZM_InventoryService
local Items = ZM_Items

Drops.Lifetime = 24 * 60 * 60
Drops.DropDistance = 48
Drops.UseRange = 160
Drops.EntityClass = "zn_dropped_item"
Drops.CrateModel = "models/props_junk/wood_crate001a.mdl"

local function mapBasename(path)
    return string.lower(string.match(path or "", "([^/]+)$") or path or "")
end

local function finiteNumber(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function itemName(instance)
    local definition = Items:GetDefinition(instance.itemId)
    return definition and definition.name or instance.itemId
end

function Drops:GetTargetLocation(target)
    if not ZM_World or not ZM_World:IsLoaded() or type(ZM_World.ActiveProfile) ~= "string" then
        return nil, "The world profile is not ready."
    end
    local safeZoneId = target.CurrentSafeZoneId
    if type(safeZoneId) == "string" and safeZoneId ~= "" and safeZoneId ~= "NULL" then
        local safeZone = ZM_SafeZones and ZM_SafeZones:Get(safeZoneId)
        local safeZoneMap = safeZone and ZM_SafeZones:GetMap(safeZoneId)
        if not safeZone or not tonumber(safeZone.cell) or not safeZoneMap then
            return nil, "Your current safe-zone location is unavailable."
        end
        if mapBasename(safeZoneMap) ~= mapBasename(game.GetMap()) then
            return nil, "Your current safe-zone map is still loading."
        end
        return ZM_World.ActiveProfile, math.floor(tonumber(safeZone.cell)), "safezone:" .. safeZoneId, safeZone
    end
    if type(target.GetWorldCell) ~= "function" then
        return nil, "Your current world cell is unavailable."
    end
    local cell = target:GetWorldCell()
    if not cell or not tonumber(cell.id) then
        return nil, "Your current world cell is unavailable."
    end
    local mapPath = ZM_World:GetMapPath(cell)
    if not mapPath or mapBasename(mapPath) ~= mapBasename(game.GetMap()) then
        return nil, "Your current world cell is still loading."
    end
    local cellId = math.floor(tonumber(cell.id))
    return ZM_World.ActiveProfile, cellId, "cell:" .. cellId, cell
end

// A drop uses one fixed spot in front of the player. Any blocked trace rejects it; no nearby point is substituted.
function Drops:FindPlacement(target)
    local forward = target:GetForward()
    local direction = Vector(forward.x, forward.y, 0)
    if direction:LengthSqr() < 0.001 then
        return nil, "You cannot place a crate in front of you right now."
    end
    direction:Normalize()

    local playerCenter = target:WorldSpaceCenter()
    local destination = target:GetPos() + direction * self.DropDistance
    local path = util.TraceHull({
        start = playerCenter,
        endpos = Vector(destination.x, destination.y, playerCenter.z),
        mins = Vector(-12, -12, -12),
        maxs = Vector(12, 12, 20),
        filter = target,
        mask = MASK_SOLID
    })
    if path.StartSolid or path.Hit then
        return nil, "The space in front of you is blocked."
    end

    local ground = util.TraceLine({
        start = destination + Vector(0, 0, 96),
        endpos = destination - Vector(0, 0, 32),
        filter = target,
        mask = MASK_SOLID
    })
    if not ground.Hit or ground.HitSky or ground.StartSolid then
        return nil, "There is no clear ground to place a crate in front of you."
    end

    local position = ground.HitPos + Vector(0, 0, 2)
    local occupied = util.TraceHull({
        start = position,
        endpos = position,
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 24),
        filter = target,
        mask = MASK_SOLID
    })
    if occupied.StartSolid or occupied.AllSolid then
        return nil, "The space in front of you is blocked."
    end

    return {
        x = position.x,
        y = position.y,
        z = position.z,
        yaw = target:EyeAngles().y
    }
end

function Drops:CreateWorldEntity(row)
    if not util.IsValidModel(self.CrateModel) then
        return nil, "The dropped-item crate model is unavailable."
    end
    local entity = ents.Create(self.EntityClass)
    if not IsValid(entity) then
        return nil, "The dropped-item crate could not be created."
    end
    entity.ZM_DroppedItemData = table.Copy(row)
    entity:SetPos(Vector(row.x, row.y, row.z))
    entity:SetAngles(Angle(0, row.yaw, 0))
    entity:Spawn()
    if not IsValid(entity) then
        return nil, "The dropped-item crate could not be spawned."
    end
    local minimum = entity:GetModelBounds()
    entity:SetPos(Vector(row.x, row.y, row.z - minimum.z))
    entity:Activate()
    entity:SetDropData(row)
    return entity
end

function Drops:RemoveWorldEntity(entity)
    if IsValid(entity) then entity:Remove() end
end

function Drops:UpdateWorldEntity(entity, row)
    if IsValid(entity) then
        entity:SetDropData(row)
        return true
    end
    return false
end

function Drops.GetPickupCapacity(inventory, instance)
    local definition = instance and Items:GetDefinition(instance.itemId)
    if not definition or not inventory or type(inventory.backpack) ~= "table" then
        return 0
    end

    local stackSpace = 0
    for _, existing in pairs(inventory.backpack) do
        if Items:CanStack(existing, instance) then
            stackSpace = stackSpace + math.max(0, definition.maxStack - existing.count)
        end
    end
    local hasEmptySlot = table.Count(inventory.backpack) < Items.ContainerCapacity.backpack
    local emptySlotSpace = hasEmptySlot and definition.maxStack or 0
    return math.min(instance.count, stackSpace + emptySlotSpace)
end

// Adds as much as the backpack can hold and returns any original-identity remainder for the crate.
function Drops:AddToBackpack(inventory, instance)
    local valid, validationError = Items:ValidateInstance(instance)
    if not valid then return false, validationError end
    local amount = self.GetPickupCapacity(inventory, instance)
    if amount < 1 then return false, "Your backpack is full." end

    local incoming = table.Copy(instance)
    incoming.count = amount
    if amount < instance.count then
        incoming.instanceId = Service.NewInstanceId()
    end
    local added, addError = Service.Ops.Add(inventory, "backpack", incoming)
    if not added then return false, addError end

    local remainder
    if amount < instance.count then
        remainder = table.Copy(instance)
        remainder.count = instance.count - amount
    end
    return true, { pickedCount = amount, remainder = remainder }
end

function Drops:ApplyPickup(target, row)
    if type(row) ~= "table" or type(row.dropId) ~= "string" or type(row.instance) ~= "table"
        or not tonumber(row.cellId) or type(row.profile) ~= "string" or type(row.locationId) ~= "string" then
        return false, "That crate is no longer available."
    end
    local characterKey, keyError = ZM_Util.CharacterKeyFor(target)
    if not characterKey then
        return false, "Cannot save your inventory: " .. tostring(keyError)
    end

    return Service:Mutate(target, function(draft)
        return self:AddToBackpack(draft, row.instance)
    end, {
        extraSteps = function(_, result)
            local step = {
                kind = result.remainder and "worldDropUpdate" or "worldDropDelete",
                steamid = characterKey,
                cellId = row.cellId,
                locationId = row.locationId,
                dropId = row.dropId,
                expectedCount = row.instance.count
            }
            if result.remainder then
                step.instance = result.remainder
            end
            return { step }
        end
    })
end

function Drops:Pickup(target, entity)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
        return false, "You must be alive to pick up a crate."
    end
    local now = os.time()
    if target.ZM_NextDroppedItemPickupAt and CurTime() < target.ZM_NextDroppedItemPickupAt then
        return false, "Slow down."
    end
    target.ZM_NextDroppedItemPickupAt = CurTime() + 0.35

    local row = entity.ZM_DroppedItemData
    local cell = self.Cell
    if not row or not cell or cell.entities[row.dropId] ~= entity or cell.profile ~= row.profile
        or cell.cellId ~= row.cellId or cell.locationId ~= row.locationId then
        return false, "That crate is no longer available."
    end
    if now >= row.expiresAt then
        return false, "This crate has expired."
    end
    if target:GetPos():DistToSqr(entity:GetPos()) > self.UseRange * self.UseRange then
        return false, "You are too far away from that crate."
    end
    local trace = util.TraceLine({
        start = target:EyePos(),
        endpos = entity:WorldSpaceCenter(),
        filter = target,
        mask = MASK_SOLID
    })
    if trace.Hit and trace.Entity ~= entity then
        return false, "The crate is blocked from view."
    end

    local storedRow = cell.rows[row.dropId]
    if not storedRow or storedRow.instance.count ~= row.instance.count then
        return false, "That crate has changed; try again."
    end
    local picked, result = self:ApplyPickup(target, row)
    if not picked then return false, result end

    if result.remainder then
        row.instance = result.remainder
        cell.rows[row.dropId] = table.Copy(row)
        self:UpdateWorldEntity(entity, row)
    else
        cell.rows[row.dropId] = nil
        cell.entities[row.dropId] = nil
        self:RemoveWorldEntity(entity)
    end
    return true, "Picked up " .. result.pickedCount .. " " .. itemName(row.instance) .. "."
end

function Drops:ClearActiveCell()
    local cell = self.Cell
    self.Cell = nil
    if not cell then return end
    for _, entity in pairs(cell.entities or {}) do
        self:RemoveWorldEntity(entity)
    end
end

function Drops:OnPlayerReady(target)
    if target.ZM_PersistentStateLoaded ~= true then return true end
    if self.StorageReady ~= true then
        return false, "Dropped-item storage is unavailable."
    end
    local profile, cellId, locationId = self:GetTargetLocation(target)
    if not profile then
        if self.Cell and self.Cell.mapName ~= mapBasename(game.GetMap()) then
            self:ClearActiveCell()
        end
        return true
    end
    if self.Cell and self.Cell.profile == profile and self.Cell.locationId == locationId
        and self.Cell.mapName == mapBasename(game.GetMap()) then
        return true
    end
    self:ClearActiveCell()

    local now = os.time()
    local expired, expiryError = ZM_DeleteExpiredWorldDroppedItems(profile, locationId, now)
    if not expired then return false, expiryError end
    local storedRows, rowsError = ZM_GetWorldDroppedItems(profile, locationId)
    if not storedRows then return false, rowsError end

    local cell = {
        profile = profile,
        cellId = cellId,
        locationId = locationId,
        mapName = mapBasename(game.GetMap()),
        rows = {},
        entities = {}
    }
    self.Cell = cell
    for _, stored in ipairs(storedRows) do
        local instance = type(stored.itemData) == "string" and util.JSONToTable(stored.itemData) or nil
        local instanceValid = instance and Items:ValidateInstance(instance)
        local row = {
            profile = profile,
            cellId = cellId,
            locationId = locationId,
            dropId = stored.dropId,
            instance = instance,
            x = tonumber(stored.x),
            y = tonumber(stored.y),
            z = tonumber(stored.z),
            yaw = tonumber(stored.yaw),
            createdAt = tonumber(stored.createdAt),
            expiresAt = tonumber(stored.expiresAt)
        }
        if not instanceValid or not row.dropId or not finiteNumber(row.x) or not finiteNumber(row.y)
            or not finiteNumber(row.z) or not finiteNumber(row.yaw) or not row.expiresAt
            or tonumber(stored.itemCount) ~= instance.count then
            ErrorNoHalt("[ZombieSim] Skipping invalid dropped-item row " .. tostring(stored.dropId) .. " in cell " .. cellId .. ".\n")
        else
            cell.rows[row.dropId] = row
            local entity, spawnError = self:CreateWorldEntity(row)
            if entity then
                cell.entities[row.dropId] = entity
            else
                ErrorNoHalt("[ZombieSim] Could not restore dropped-item crate " .. row.dropId .. ": " .. tostring(spawnError) .. "\n")
            end
        end
    end
    return true
end

function Drops:InitializeStorage()
    local ready, storageError = ZM_CreateWorldDroppedItemTables()
    self.StorageReady = ready
    if not ready then
        ErrorNoHalt("[ZombieSim] Could not prepare dropped-item storage: " .. tostring(storageError) .. "\n")
        return false, storageError
    end
    return true
end

function Drops:DropItem(target, instanceId, count, requestId)
    if self.StorageReady ~= true then
        return false, "Dropped-item storage is unavailable."
    end
    if not IsValid(target) or not target.Alive or not target:Alive() then
        return false, "You must be alive to drop an item."
    end
    if not isstring(instanceId) or instanceId == "" then
        return false, "Invalid item."
    end
    if not isstring(requestId) or requestId == "" or #requestId > 64 then
        return false, "Invalid drop request."
    end
    if not ZM_Util.IsWholeNumber(count, 1, 10000) then
        return false, "Choose a whole-number quantity."
    end
    local characterKey, keyError = ZM_Util.CharacterKeyFor(target)
    if not characterKey then return false, "Cannot save your inventory: " .. tostring(keyError) end
    local profile, cellId, locationId = self:GetTargetLocation(target)
    if not profile then return false, cellId end
    if ZM_Util.ProfileFor(target) ~= profile then
        return false, "Your inventory and world profiles do not match."
    end
    local priorRequest, requestError = ZM_GetWorldDropRequest(profile, requestId)
    if requestError then return false, requestError end
    if priorRequest then
        if priorRequest.locationId == locationId and priorRequest.sourceInstanceId == instanceId
            and tonumber(priorRequest.requestedCount) == count then
            return true, "That drop request was already processed."
        end
        return false, "That drop request ID has already been used."
    end

    local source = Service:FindBackpackInstance(target, instanceId)
    if not source then return false, "That item is not in your backpack." end
    local valid, validationError = Items:ValidateInstance(source)
    if not valid then return false, validationError end
    if not ZM_Util.IsWholeNumber(count, 1, source.count) then
        return false, "Choose a whole-number quantity from 1 to " .. source.count .. "."
    end

    local position, placementError = self:FindPlacement(target)
    if not position then return false, placementError end

    local item = table.Copy(source)
    item.count = count
    if count < source.count then
        item.instanceId = Service.NewInstanceId()
    end
    local now = os.time()
    local row = {
        profile = profile,
        cellId = cellId,
        locationId = locationId,
        dropId = Service.NewInstanceId(),
        requestId = requestId,
        sourceInstanceId = instanceId,
        instance = item,
        x = position.x,
        y = position.y,
        z = position.z,
        yaw = position.yaw,
        createdAt = now,
        expiresAt = now + self.Lifetime
    }
    local entity, spawnError = self:CreateWorldEntity(row)
    if not entity then return false, spawnError end

    local dropped, result = Service:Mutate(target, function(draft)
        local current = Service:FindBackpackInstance(target, instanceId)
        local _, _, draftInstance = Service.Ops.FindInstance(draft, instanceId)
        if not current or not draftInstance or draftInstance.count < count then
            return false, "That item changed before it could be dropped."
        end
        local removed, removeError = Service.Ops.RemoveInstance(draft, instanceId, count)
        if not removed then return false, removeError end
        return true, count
    end, {
        extraSteps = function()
            return { {
                kind = "worldDropInsert",
                steamid = characterKey,
                cellId = row.cellId,
                locationId = row.locationId,
                dropId = row.dropId,
                requestId = row.requestId,
                sourceInstanceId = row.sourceInstanceId,
                instance = row.instance,
                x = row.x,
                y = row.y,
                z = row.z,
                yaw = row.yaw,
                createdAt = row.createdAt,
                expiresAt = row.expiresAt
            } }
        end
    })
    if not dropped then
        self:RemoveWorldEntity(entity)
        return false, result
    end

    if self.Cell and self.Cell.profile == profile and self.Cell.locationId == locationId then
        self.Cell.rows[row.dropId] = table.Copy(row)
        self.Cell.entities[row.dropId] = entity
    end
    return true, "Dropped " .. count .. " " .. itemName(row.instance) .. " in a crate."
end

Drops:InitializeStorage()

timer.Create("ZM.DroppedItems.Expiry", 30, 0, function()
    local cell = Drops.Cell
    if not cell then return end
    if cell.mapName ~= mapBasename(game.GetMap()) then
        Drops:ClearActiveCell()
        return
    end
    local now = os.time()
    for dropId, row in pairs(cell.rows) do
        local entity = cell.entities[dropId]
        if now >= row.expiresAt then
            local deleted, deleteError = ZM_DeleteWorldDroppedItem(cell.profile, cell.locationId, dropId, row.instance.count)
            if deleted then
                cell.rows[dropId] = nil
                cell.entities[dropId] = nil
                Drops:RemoveWorldEntity(entity)
            else
                ErrorNoHalt("[ZombieSim] Could not expire dropped-item crate " .. dropId .. ": " .. tostring(deleteError) .. "\n")
            end
        elseif not IsValid(entity) then
            local restored, restoreError = Drops:CreateWorldEntity(row)
            if restored then
                cell.entities[dropId] = restored
            else
                ErrorNoHalt("[ZombieSim] Could not restore dropped-item crate " .. dropId .. ": " .. tostring(restoreError) .. "\n")
            end
        end
    end
    local requestsDeleted, requestDeleteError = ZM_DeleteExpiredWorldDropRequests(cell.profile, cell.locationId, now)
    if not requestsDeleted then
        ErrorNoHalt("[ZombieSim] Could not expire dropped-item request keys: " .. tostring(requestDeleteError) .. "\n")
    end
end)

hook.Add("InitPostEntity", "ZM.DroppedItems.ClearPreviousCell", function()
    Drops:ClearActiveCell()
end)
