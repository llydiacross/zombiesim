// Server-only backpack and den-stash inventory: container operations, SQLite persistence, networking, and death loss.
// The backpack is always at risk and is lost on death; the stash can only be changed inside a den.
ZM_InventoryService = ZM_InventoryService or {}
local Service = ZM_InventoryService
local Items = ZM_Items
local ply = FindMetaTable("Player")

util.AddNetworkString("ZM.InventorySnapshot")
util.AddNetworkString("ZM.InventoryRequest")
util.AddNetworkString("ZM.InventoryAction")
util.AddNetworkString("ZM.InventoryActionResult")

local maximumGrantCount = 10000
local useCooldown = 0.5

Service.NewInstanceId = ZM_ItemGeneration.NewInstanceId

function Service.NewInventory()
    return { backpack = {}, stash = {}, equipped = {} }
end

local profileFor = ZM_Util.ProfileFor

local function loadWeaponSlots(target)
    local rows, loadError = ZM_GetEquippedWeaponSlots(target:SteamID(), profileFor(target))
    if not rows then return nil, loadError end
    local slots = {}
    for _, row in ipairs(rows) do
        local slot = tonumber(row.slot)
        if slot and slot >= 1 and slot <= 3 then
            slots[slot] = { instanceId = row.instanceId, selected = tonumber(row.selected) == 1 }
        end
    end
    return slots
end

local function saveWeaponSlots(target)
    return ZM_ReplaceEquippedWeaponSlots(target:SteamID(), profileFor(target), target.ZM_WeaponSlots or {})
end

local isWholeNumber = ZM_Util.IsWholeNumber

// Pure container operations. They mutate the inventory they are given, so callers pass a draft copy.
local Ops = {}
Service.Ops = Ops

function Ops.FindInstance(inventory, instanceId)
    for container, slots in pairs(inventory) do
        for slot, instance in pairs(slots) do
            if instance.instanceId == instanceId then
                return container, slot, instance
            end
        end
    end
end

function Ops.Count(inventory, itemId, container)
    local total = 0
    for name, slots in pairs(inventory) do
        if container == nil or container == name then
            for _, instance in pairs(slots) do
                if instance.itemId == itemId then
                    total = total + instance.count
                end
            end
        end
    end
    return total
end

local function firstEmptySlot(slots, container)
    for slot = 1, Items.ContainerCapacity[container] do
        if slots[slot] == nil then
            return slot
        end
    end
end

// Adds an instance, merging into compatible stacks first. Fails without changes when it does not fit.
function Ops.Add(inventory, container, instance)
    if not Items.Containers[container] then
        return false, "unknown container '" .. tostring(container) .. "'"
    end
    local valid, reason = Items:ValidateInstance(instance)
    if not valid then
        return false, reason
    end
    if Ops.FindInstance(inventory, instance.instanceId) then
        return false, "instance is already in the inventory"
    end

    local definition = Items:GetDefinition(instance.itemId)
    local slots = inventory[container]
    local remaining = instance.count
    local merges = {}
    for slot, existing in SortedPairs(slots) do
        if remaining == 0 then
            break
        end
        if Items:CanStack(existing, instance) and existing.count < definition.maxStack then
            local amount = math.min(definition.maxStack - existing.count, remaining)
            table.insert(merges, { slot = slot, amount = amount })
            remaining = remaining - amount
        end
    end
    local newSlot = nil
    if remaining > 0 then
        newSlot = firstEmptySlot(slots, container)
        if not newSlot then
            return false, "there is no free slot in the " .. container
        end
    end

    for _, merge in ipairs(merges) do
        slots[merge.slot].count = slots[merge.slot].count + merge.amount
        if definition.food then
            slots[merge.slot].createdAt = ZM_Food.MergedCreatedAt(slots[merge.slot], instance)
        end
    end
    if newSlot then
        local placed = table.Copy(instance)
        placed.count = remaining
        slots[newSlot] = placed
    end
    return true, { slot = newSlot, merged = instance.count - remaining }
end

// Removes a total count of an item from one container, taking from the highest slots first.
function Ops.Remove(inventory, container, itemId, count)
    if not Items.Containers[container] then
        return false, "unknown container '" .. tostring(container) .. "'"
    end
    if not isWholeNumber(count, 1) then
        return false, "count must be a whole number of at least 1"
    end
    if Ops.Count(inventory, itemId, container) < count then
        return false, "not enough " .. tostring(itemId) .. " in the " .. container
    end

    local slots = inventory[container]
    local slotNumbers = table.GetKeys(slots)
    table.sort(slotNumbers, function(left, right) return left > right end)
    local remaining = count
    for _, slot in ipairs(slotNumbers) do
        local instance = slots[slot]
        if remaining > 0 and instance.itemId == itemId then
            local amount = math.min(instance.count, remaining)
            instance.count = instance.count - amount
            remaining = remaining - amount
            if instance.count == 0 then
                slots[slot] = nil
            end
        end
    end
    return true
end

function Ops.RemoveInstance(inventory, instanceId, count)
    local container, slot, instance = Ops.FindInstance(inventory, instanceId)
    if not instance then
        return false, "item instance not found"
    end
    count = count or instance.count
    if not isWholeNumber(count, 1, instance.count) then
        return false, "count must be from 1 to " .. instance.count
    end
    instance.count = instance.count - count
    if instance.count == 0 then
        inventory[container][slot] = nil
    end
    return true, container
end

// Moves all or part of a stack. A partial move splits off a new instance; a full move onto an incompatible item swaps them.
function Ops.Move(inventory, instanceId, toContainer, toSlot, count, newInstanceId)
    local fromContainer, fromSlot, instance = Ops.FindInstance(inventory, instanceId)
    if not instance then
        return false, "item instance not found"
    end
    if not Items.Containers[toContainer] then
        return false, "unknown container '" .. tostring(toContainer) .. "'"
    end
    count = count or instance.count
    if not isWholeNumber(count, 1, instance.count) then
        return false, "count must be from 1 to " .. instance.count
    end

    if toSlot == nil then
        if toContainer == fromContainer then
            return false, "choose a slot to move within the same container"
        end
        local moving = table.Copy(instance)
        moving.count = count
        if count == instance.count then
            inventory[fromContainer][fromSlot] = nil
        else
            moving.instanceId = newInstanceId()
            instance.count = instance.count - count
        end
        return Ops.Add(inventory, toContainer, moving)
    end

    if not isWholeNumber(toSlot, 1, Items.ContainerCapacity[toContainer]) then
        return false, "slot must be from 1 to " .. Items.ContainerCapacity[toContainer]
    end
    if toContainer == fromContainer and toSlot == fromSlot then
        return true
    end
    local target = inventory[toContainer][toSlot]
    if target == nil then
        if count == instance.count then
            inventory[fromContainer][fromSlot] = nil
            inventory[toContainer][toSlot] = instance
        else
            local split = table.Copy(instance)
            split.instanceId = newInstanceId()
            split.count = count
            instance.count = instance.count - count
            inventory[toContainer][toSlot] = split
        end
        return true
    end
    if Items:CanStack(target, instance) then
        local space = Items:GetDefinition(target.itemId).maxStack - target.count
        if space < count then
            return false, "the target stack only has room for " .. space
        end
        target.count = target.count + count
        if Items:GetDefinition(target.itemId).food then
            target.createdAt = ZM_Food.MergedCreatedAt(target, instance)
        end
        instance.count = instance.count - count
        if instance.count == 0 then
            inventory[fromContainer][fromSlot] = nil
        end
        return true
    end
    if count ~= instance.count then
        return false, "cannot split a stack onto an occupied slot"
    end
    inventory[fromContainer][fromSlot] = target
    inventory[toContainer][toSlot] = instance
    return true
end

function Service.ToRows(inventory)
    local rows = {}
    for container, slots in SortedPairs(inventory) do
        for slot, instance in SortedPairs(slots) do
            table.insert(rows, {
                instanceId = instance.instanceId,
                container = container,
                slot = slot,
                itemId = instance.itemId,
                count = instance.count,
                level = instance.level,
                mastercraft = instance.mastercraft == true,
                attributes = instance.attributes,
                clip = tonumber(instance.clip) or 0,
                createdAt = instance.createdAt or 0
            })
        end
    end
    return rows
end

// Player rows exclude the den stash, which is saved per den.
local function playerItemRows(inventory)
    local rows = {}
    for _, row in ipairs(Service.ToRows(inventory)) do
        if row.container ~= "stash" then table.insert(rows, row) end
    end
    return rows
end

local function readAttributes(value)
    if type(value) == "table" then
        return value
    end
    if type(value) == "string" and value ~= "" and value ~= "NULL" then
        return util.JSONToTable(value)
    end
    return nil
end

// Builds an inventory from stored rows. Items whose definition no longer exists are kept (flagged) so saves never delete them.
function Service.FromRows(rows)
    local inventory = Service.NewInventory()
    local warnings = {}
    for _, row in ipairs(rows) do
        local container = row.container
        local slot = tonumber(row.slot)
        if not Items.Containers[container] or not slot then
            table.insert(warnings, "skipped item " .. tostring(row.instanceId) .. " in unknown container or slot " .. tostring(container) .. "/" .. tostring(row.slot))
        else
            local instance = {
                instanceId = row.instanceId,
                itemId = row.itemId,
                count = tonumber(row.count) or 1,
                level = tonumber(row.level) or 1,
                mastercraft = tonumber(row.mastercraft) == 1 or row.mastercraft == true,
                attributes = readAttributes(row.attributes),
                clip = tonumber(row.clip) or 0,
                createdAt = tonumber(row.createdAt) or 0
            }
            if not Items:GetDefinition(instance.itemId) then
                instance.missingDefinition = true
                table.insert(warnings, "item " .. instance.instanceId .. " uses unknown item id '" .. tostring(instance.itemId) .. "' and is kept unchanged")
            end
            inventory[container][slot] = instance
        end
    end
    return inventory, warnings
end

local function baseMapName(path)
    return string.lower(string.match(path, "([^/]+)$") or path)
end

// The stash is reachable only while the player is loaded on their current den's map.
function Service:CanAccessStash(target)
    local safeZoneId = target.CurrentSafeZoneId
    if type(safeZoneId) ~= "string" or safeZoneId == "" then
        return false
    end
    local safeZoneMap = ZM_SafeZones and ZM_SafeZones:GetMap(safeZoneId) or nil
    return safeZoneMap ~= nil and baseMapName(safeZoneMap) == baseMapName(game.GetMap())
end

function Service:CurrentDenId(target)
    return type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" and target.CurrentSafeZoneId or nil
end

function Service:LoadDenStash(target)
    local denId = self:CurrentDenId(target)
    target.ZM_Inventory.stash = {}
    if not denId or not self:CanAccessStash(target) then return true end
    local rows, loadError = ZM_GetDenStashItems(target:SteamID(), profileFor(target), denId)
    if not rows then return false, loadError end
    local stashRows = {}
    for _, row in ipairs(rows) do
        table.insert(stashRows, { instanceId = row.instanceId, container = "stash", slot = tonumber(row.slot), itemId = row.itemId, count = tonumber(row.count) or 1, level = tonumber(row.level) or 1, mastercraft = tonumber(row.mastercraft) == 1, attributes = readAttributes(row.attributes), createdAt = tonumber(row.createdAt) or 0 })
    end
    local stash = Service.FromRows(stashRows)
    target.ZM_Inventory.stash = stash.stash
    return true
end

function Service:DepositCashBundles(target)
    if not target.ZM_Inventory then return false, "inventory is not loaded" end
    local deposited = 0
    local changed, changeError = self:Mutate(target, function(draft)
        for container, slots in pairs(draft) do
            if container ~= "equipped" then
                for slot, instance in pairs(slots) do
                    if instance.itemId == "itemCashBundle" then
                        deposited = deposited + math.max(0, tonumber(instance.count) or 0)
                        slots[slot] = nil
                    end
                end
            end
        end
        return true
    end)
    if not changed then return false, changeError end
    if deposited > 0 then
        target.Cash = math.max(0, tonumber(target.Cash) or 0) + deposited
        local saved, saveError = target:UpdatePlayerData("den cash deposit")
        if not saved then return false, saveError end
        target:SetNetworkPlayerData()
    end
    self:Send(target)
    return true, deposited
end

function Service:Send(target)
    if not IsValid(target) or not target:IsPlayer() or not target.ZM_Inventory then
        return
    end
    self:NormalizeWeaponSlots(target)
    local bundleCash = 0
    for _, slots in pairs(target.ZM_Inventory) do
        for _, instance in pairs(slots) do
            if instance.itemId == "itemCashBundle" then bundleCash = bundleCash + (tonumber(instance.count) or 0) end
        end
    end
    local bankCash = math.max(0, tonumber(target.Cash) or 0)
    local snapshot = { serverTime = os.time(), capacity = Items.ContainerCapacity, canAccessStash = self:CanAccessStash(target), cash = bankCash + bundleCash, bankCash = bankCash, bundleCash = bundleCash, equipped = {}, weaponSlots = target.ZM_WeaponSlots or {}, equippedItems = {} }
    local equippedIds = {}
    for slot = 1, 3 do
        local loadout = snapshot.weaponSlots[slot]
        if loadout then
            snapshot.equipped[slot] = loadout.instanceId
            equippedIds[loadout.instanceId] = true
            if loadout.selected then snapshot.selectedWeaponSlot = slot end
        end
    end
    for container, slots in pairs(target.ZM_Inventory) do
        if container == "equipped" then
            for slot, instance in SortedPairs(slots) do
                table.insert(snapshot.equippedItems, { slot = slot, instanceId = instance.instanceId, itemId = instance.itemId, count = instance.count, level = instance.level, mastercraft = instance.mastercraft == true, attributes = instance.attributes, clip = tonumber(instance.clip) or 0 })
            end
            continue
        end
        local list = {}
        for slot, instance in SortedPairs(slots) do
            if not equippedIds[instance.instanceId] then
                table.insert(list, {
                    slot = slot,
                    instanceId = instance.instanceId,
                    itemId = instance.itemId,
                    count = instance.count,
                    level = instance.level,
                    mastercraft = instance.mastercraft == true,
                    attributes = instance.attributes,
                    clip = tonumber(instance.clip) or 0,
                    createdAt = tonumber(instance.createdAt) or 0,
                    missingDefinition = instance.missingDefinition == true
                })
            end
        end
        snapshot[container] = list
    end
    net.Start("ZM.InventorySnapshot")
        net.WriteString(util.TableToJSON(snapshot, false) or "{}")
    net.Send(target)
end

function Service:Load(target)
    target.ZM_Inventory = nil
    local rows, loadError = ZM_GetPlayerItems(target:SteamID(), profileFor(target))
    if not rows then
        return false, loadError
    end
    local inventory, warnings = Service.FromRows(rows)
    for _, warning in ipairs(warnings) do
        print("[ZombieSim] Inventory load for " .. target:SteamID() .. ": " .. warning)
    end
    target.ZM_Inventory = inventory
    local stashLoaded, stashError = self:LoadDenStash(target)
    if not stashLoaded then return false, stashError end
    target.ZM_Inventory.equipped = target.ZM_Inventory.equipped or {}
    target.ZM_WeaponSlots = loadWeaponSlots(target) or {}
    self:NormalizeWeaponSlots(target)
    self:Send(target)
    self:RestoreEquippedWeapons(target)
    return true
end

function Service:NormalizeWeaponSlots(target)
    target.ZM_WeaponSlots = target.ZM_WeaponSlots or {}
    target.ZM_Inventory.equipped = target.ZM_Inventory.equipped or {}
    local changed = false

    for _, weapon in ipairs(target:GetWeapons()) do
        local instanceId = weapon.GetItemInstanceId and weapon:GetItemInstanceId() or ""
        if instanceId ~= "" then
            local equippedSlot, equippedInstance = Ops.FindInstance(target.ZM_Inventory, instanceId)
            if equippedSlot ~= "equipped" then
                local sourceContainer, sourceSlot, sourceInstance = Ops.FindInstance(target.ZM_Inventory, instanceId)
                if sourceInstance and sourceContainer == "backpack" then
                    local destination
                    for slot = 1, 3 do
                        if not target.ZM_Inventory.equipped[slot] then destination = slot break end
                    end
                    if destination then
                        target.ZM_Inventory.backpack[sourceSlot] = nil
                        target.ZM_Inventory.equipped[destination] = sourceInstance
                        target.ZM_WeaponSlots[destination] = { instanceId = instanceId, selected = false }
                        changed = true
                    end
                end
            end
        end
    end

    for slot = 1, 3 do
        local loadout = target.ZM_WeaponSlots[slot]
        local instance = loadout and loadout.instanceId and target.ZM_Inventory.equipped and select(3, Ops.FindInstance(target.ZM_Inventory, loadout.instanceId)) or nil
        if loadout and not instance then
            local backpackSlot, legacyInstance
            for candidateSlot, candidate in pairs(target.ZM_Inventory.backpack or {}) do
                if candidate.instanceId == loadout.instanceId then
                    backpackSlot, legacyInstance = candidateSlot, candidate
                    break
                end
            end
            if legacyInstance and not target.ZM_Inventory.equipped[slot] then
                target.ZM_Inventory.backpack[backpackSlot] = nil
                target.ZM_Inventory.equipped[slot] = legacyInstance
                instance = legacyInstance
                changed = true
            end
        end
        if loadout and not instance then
            target.ZM_WeaponSlots[slot] = nil
            changed = true
        end
    end
    if changed then
        ZM_ReplacePlayerItems(target:SteamID(), profileFor(target), playerItemRows(target.ZM_Inventory))
        saveWeaponSlots(target)
    end
end

function Service:RestoreEquippedWeapons(target)
    local selectedClass
    for _, slot in pairs(target.ZM_WeaponSlots or {}) do
        local instance = slot.instanceId and target.ZM_Inventory.equipped and select(3, Ops.FindInstance(target.ZM_Inventory, slot.instanceId)) or nil
        if instance then
            self:EquipWeapon(target, instance.instanceId, true)
            if slot.selected then
                local definition = Items:GetDefinition(instance.itemId)
                selectedClass = definition and definition.weaponClass
            end
        end
    end
    if selectedClass and target:HasWeapon(selectedClass) then
        target:SelectWeapon(selectedClass)
    end
end

// Applies a mutation to a copy, persists it in one transaction, and only then replaces the live inventory.
// options.extraSteps(draft, result) may return more ZM_CommitWrites steps (cash, claims) saved in that transaction.
function Service:Mutate(target, mutator, options)
    if not IsValid(target) or not target.ZM_Inventory then
        return false, "inventory is not loaded"
    end
    target.ZM_Inventory.equipped = target.ZM_Inventory.equipped or {}
    local draft = table.Copy(target.ZM_Inventory)
    local ok, result = mutator(draft)
    if not ok then
        return false, result
    end
    local playerRows = playerItemRows(draft)
    local denId = self:CurrentDenId(target)
    local stashRows = Service.ToRows({ backpack = {}, stash = draft.stash, equipped = {} })
    for _, row in ipairs(stashRows) do row.container = "stash" end
    local steps = { { kind = "playerItems", steamid = target:SteamID(), rows = playerRows } }
    if denId and self:CanAccessStash(target) then
        table.insert(steps, { kind = "denStash", steamid = target:SteamID(), safeZoneId = denId, rows = stashRows })
    end
    if options and options.extraSteps then
        local extra, extraError = options.extraSteps(draft, result)
        if not extra then
            return false, extraError
        end
        table.Add(steps, extra)
    end
    local saved, saveError = ZM_CommitWrites(profileFor(target), steps)
    if not saved then
        return false, "could not save inventory: " .. tostring(saveError)
    end
    target.ZM_Inventory = draft
    self:ReconcileEquippedWeapons(target)
    self:Send(target)
    return true, result
end

// Applies a mutation limited to backpack/equipped state without rewriting the current den stash.
function Service:MutatePlayerItems(target, mutator)
    if not IsValid(target) or not target.ZM_Inventory then
        return false, "inventory is not loaded"
    end
    target.ZM_Inventory.equipped = target.ZM_Inventory.equipped or {}
    local draft = table.Copy(target.ZM_Inventory)
    local ok, result = mutator(draft)
    if not ok then
        return false, result
    end
    draft.stash = target.ZM_Inventory.stash
    local saved, saveError = ZM_ReplacePlayerItems(target:SteamID(), profileFor(target), playerItemRows(draft))
    if not saved then
        return false, "could not save inventory: " .. tostring(saveError)
    end
    target.ZM_Inventory.backpack = draft.backpack
    target.ZM_Inventory.equipped = draft.equipped
    self:ReconcileEquippedWeapons(target)
    self:Send(target)
    return true, result
end

// Strips any equipped item weapon whose instance is no longer in the backpack.
function Service:ReconcileEquippedWeapons(target)
    if not target.IsPlayer or not target:IsPlayer() or not target.ZM_Inventory then
        return
    end
    for _, weapon in ipairs(target:GetWeapons()) do
        local instanceId = weapon.GetItemInstanceId and weapon:GetItemInstanceId() or ""
        if instanceId ~= "" then
            local loadout = target.ZM_WeaponSlots or {}
            local equipped = false
            for _, slot in pairs(loadout) do
                if slot.instanceId == instanceId then equipped = true break end
            end
            if not equipped then
                target:StripWeapon(weapon:GetClass())
            end
        end
    end
end

// Creates new instances and adds them to a container (backpack by default). Returns true and the new instance ids.
// Options are passed to ZM_ItemGeneration:CreateInstance; weapons roll level and attributes unless given.
function Service:GiveItem(target, itemId, count, options)
    options = options or {}
    local definition = Items:GetDefinition(itemId)
    if not definition then
        return false, "unknown item '" .. tostring(itemId) .. "'"
    end
    count = count or 1
    if not isWholeNumber(count, 1, maximumGrantCount) then
        return false, "count must be from 1 to " .. maximumGrantCount
    end
    local container = options.container or "backpack"
    local playerLevel = options.playerLevel or (target.GetLevel and target:GetLevel()) or 1
    return self:Mutate(target, function(draft)
        local instanceIds = {}
        local remaining = count
        while remaining > 0 do
            local amount = math.min(remaining, definition.maxStack)
            local instance, reason = ZM_ItemGeneration:CreateInstance(itemId, {
                count = amount,
                level = options.level,
                playerLevel = playerLevel,
                danger = options.danger,
                mastercraft = options.mastercraft,
                mastercraftChance = options.mastercraftChance,
                attributes = options.attributes
            })
            if not instance then
                return false, reason
            end
            local added, addReason = Ops.Add(draft, container, instance)
            if not added then
                return false, addReason
            end
            table.insert(instanceIds, instance.instanceId)
            remaining = remaining - amount
        end
        return true, instanceIds
    end)
end

// Finds a backpack instance by instance id, or the first backpack stack of an item id.
function Service:FindBackpackInstance(target, reference)
    local inventory = target.ZM_Inventory
    if not inventory or type(reference) ~= "string" then
        return nil
    end
    for _, instance in SortedPairs(inventory.backpack) do
        if instance.instanceId == reference then
            return instance
        end
    end
    for _, instance in SortedPairs(inventory.backpack) do
        if instance.itemId == reference then
            return instance
        end
    end
end

// Uses one unit of a backpack "entity" item. The removal is persisted before the effect runs,
// so a failed save never grants a free use; a failed effect restores the unit.
function Service:UseItem(target, reference, targetPly)
    if target.ZM_NextItemUseAt and CurTime() < target.ZM_NextItemUseAt then
        return false, "You are already using an item."
    end
    local instance = self:FindBackpackInstance(target, reference)
    if not instance then
        return false, "That item is not in your backpack."
    end
    local definition = Items:GetDefinition(instance.itemId)
    if not definition or definition.entityClass ~= "entity" then
        return false, "That item cannot be used."
    end
    local itemClass = Items:GetItemClass(instance.itemId)
    local itemData = { id = instance.itemId, instance = table.Copy(instance), definition = definition }
    local canUse, reason = itemClass:CanUse(target, itemData, targetPly)
    if not canUse then
        return false, reason
    end

    target.ZM_NextItemUseAt = CurTime() + useCooldown
    local instanceId = instance.instanceId
    local consumed, consumeError = self:Mutate(target, function(draft)
        return Ops.RemoveInstance(draft, instanceId, 1)
    end)
    if not consumed then
        return false, consumeError
    end
    local used = itemClass:OnUse(target, itemData, targetPly)
    if used then
        if definition.food and target.UpdatePlayerData then
            local saved, saveError = target:UpdatePlayerData("food consumed")
            if not saved then
                print("[ZombieSim] Could not save survival stats after eating for " .. target:SteamID() .. ": " .. tostring(saveError))
            end
        end
        return true, itemData.appliedEffects and ("Consumed: " .. ZM_Food:DescribeEffects(itemData.appliedEffects) .. ".") or nil
    end
    local restore = table.Copy(itemData.instance)
    restore.instanceId = Service.NewInstanceId()
    restore.count = 1
    self:GiveInstance(target, restore, "backpack")
    return false, "The item could not be used."
end

// Gives the SWEP for a backpack weapon instance with its rolled attributes applied.
function Service:EquipWeapon(target, reference, preferredSlot)
    target.ZM_Inventory.equipped = target.ZM_Inventory.equipped or {}
    local backpackInstance = self:FindBackpackInstance(target, reference)
    if backpackInstance then
        reference = backpackInstance.instanceId
    end
    local container, sourceSlot, instance = Ops.FindInstance(target.ZM_Inventory, reference)
    if not instance then
        return false, "That item is not in your backpack."
    end
    local definition = Items:GetDefinition(instance.itemId)
    if not definition or definition.entityClass ~= "weapon" then
        return false, "That item is not a weapon."
    end
    local canUse, reason = Items:CanUse(target, instance.itemId, instance)
    if not canUse then
        return false, reason
    end
    if not weapons.GetStored(definition.weaponClass) then
        return false, "Weapon '" .. definition.weaponClass .. "' is not installed."
    end
    target.ZM_WeaponSlots = target.ZM_WeaponSlots or {}
    local selectedSlot = container == "equipped" and sourceSlot or tonumber(preferredSlot)
    if container ~= "equipped" and (not selectedSlot or selectedSlot < 1 or selectedSlot > 3) then
        selectedSlot = 1
        for slot = 1, 3 do
            if not target.ZM_WeaponSlots[slot] or not target.ZM_WeaponSlots[slot].instanceId then selectedSlot = slot break end
        end
    end
    local existingWeapon = target:GetWeapon(definition.weaponClass)
    if IsValid(existingWeapon) and existingWeapon.GetItemInstanceId and existingWeapon:GetItemInstanceId() == instance.instanceId then
        target:SelectWeapon(definition.weaponClass)
        target.ZM_WeaponSlots[selectedSlot] = { instanceId = instance.instanceId, selected = true }
        for slot = 1, 3 do
            if slot ~= selectedSlot and target.ZM_WeaponSlots[slot] then target.ZM_WeaponSlots[slot].selected = false end
        end
        saveWeaponSlots(target)
        self:Send(target)
        return true, existingWeapon
    end
    if target:HasWeapon(definition.weaponClass) then
        target:StripWeapon(definition.weaponClass)
    end
    local weapon = target:Give(definition.weaponClass, true)
    if not IsValid(weapon) then
        return false, "Could not give the weapon."
    end
    Items:ApplyInstanceToWeapon(weapon, instance)
    if container == "backpack" then
        local previousSlots = table.Copy(target.ZM_WeaponSlots)
        target.ZM_WeaponSlots[selectedSlot] = { instanceId = instance.instanceId, selected = true }
        local moved, moveError = self:Mutate(target, function(draft)
            local moving = draft.backpack[sourceSlot]
            if not moving or draft.equipped[selectedSlot] then return false, "That weapon slot is occupied." end
            draft.backpack[sourceSlot] = nil
            draft.equipped[selectedSlot] = moving
            return true
        end)
        if not moved then
            target.ZM_WeaponSlots = previousSlots
            target:StripWeapon(definition.weaponClass)
            return false, moveError
        end
        instance = target.ZM_Inventory.equipped[selectedSlot]
    elseif container ~= "equipped" then
        return false, "That item is not in your backpack."
    end
    target.ZM_WeaponSlots[selectedSlot] = { instanceId = instance.instanceId, selected = true }
    for slot = 1, 3 do
        if slot ~= selectedSlot and target.ZM_WeaponSlots[slot] then target.ZM_WeaponSlots[slot].selected = false end
    end
    saveWeaponSlots(target)
    target:SelectWeapon(definition.weaponClass)
    self:Send(target)
    return true, weapon
end

function Service:EquipWeaponInSlot(target, reference, slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > 3 or slot ~= math.floor(slot) then
        return false, "Invalid weapon slot."
    end
    local container, currentSlot, instance = Ops.FindInstance(target.ZM_Inventory, reference)
    if not instance then return false, "That item is not in your backpack." end
    local definition = Items:GetDefinition(instance.itemId)
    if not definition or definition.entityClass ~= "weapon" then return false, "That item is not a weapon." end
    local canUse, reason = Items:CanUse(target, instance.itemId, instance)
    if not canUse then return false, reason end
    target.ZM_WeaponSlots = target.ZM_WeaponSlots or {}
    if container == "equipped" and currentSlot ~= slot then
        local destination = target.ZM_Inventory.equipped[slot]
        target.ZM_Inventory.equipped[currentSlot] = destination
        target.ZM_Inventory.equipped[slot] = instance
        local saved, saveError = ZM_ReplacePlayerItems(target:SteamID(), profileFor(target), playerItemRows(target.ZM_Inventory))
        if not saved then return false, "could not save inventory: " .. tostring(saveError) end
        target.ZM_WeaponSlots[currentSlot], target.ZM_WeaponSlots[slot] = target.ZM_WeaponSlots[slot], target.ZM_WeaponSlots[currentSlot]
        for index = 1, 3 do
            if target.ZM_WeaponSlots[index] then target.ZM_WeaponSlots[index].selected = index == slot end
        end
        saveWeaponSlots(target)
        self:Send(target)
        return true, "Moved to weapon slot " .. slot .. "."
    end
    for index = 1, 3 do
        if target.ZM_WeaponSlots[index] and target.ZM_WeaponSlots[index].instanceId == instance.instanceId then
            target.ZM_WeaponSlots[index] = nil
        end
    end
    target.ZM_WeaponSlots[slot] = { instanceId = instance.instanceId, selected = true }
    for index = 1, 3 do
        if index ~= slot and target.ZM_WeaponSlots[index] then target.ZM_WeaponSlots[index].selected = false end
    end
    local equipped, equipReason = self:EquipWeapon(target, instance.instanceId, slot)
    if not equipped then return false, equipReason end
    saveWeaponSlots(target)
    self:Send(target)
    return true, "Equipped in weapon slot " .. slot .. "."
end

hook.Add("PlayerSwitchWeapon", "ZM.Inventory.PersistSelectedWeapon", function(target, oldWeapon, weapon)
    if ZM_AmmoService and IsValid(oldWeapon) and oldWeapon.GetItemInstanceId and oldWeapon:GetItemInstanceId() ~= "" then
        local synced, syncError = ZM_AmmoService:SyncWeapon(target, oldWeapon)
        if not synced then
            ErrorNoHalt("[ZombieSim] Could not persist switched weapon ammunition: " .. tostring(syncError) .. "\n")
        end
    end
    if not IsValid(target) or not target.ZM_WeaponSlots or not IsValid(weapon) or not weapon.GetItemInstanceId then return end
    local instanceId = weapon:GetItemInstanceId()
    if not instanceId then return end
    local changed = false
    for slot = 1, 3 do
        local loadout = target.ZM_WeaponSlots[slot]
        if loadout then
            local selected = loadout.instanceId == instanceId
            if loadout.selected ~= selected then
                loadout.selected = selected
                changed = true
            end
        end
    end
    if changed then saveWeaponSlots(target) end
end)

// Strips the equipped weapon created from an instance.
function Service:UnequipWeapon(target, instanceId)
    for _, weapon in ipairs(target:GetWeapons()) do
        if weapon.GetItemInstanceId and weapon:GetItemInstanceId() == instanceId then
            if ZM_AmmoService then
                local synced, syncError = ZM_AmmoService:SyncWeapon(target, weapon)
                if not synced then
                    return false, "could not save weapon ammunition: " .. tostring(syncError)
                end
            end
            local previousSlots = table.Copy(target.ZM_WeaponSlots or {})
            for slot = 1, 3 do
                if target.ZM_WeaponSlots and target.ZM_WeaponSlots[slot] and target.ZM_WeaponSlots[slot].instanceId == instanceId then
                    target.ZM_WeaponSlots[slot] = nil
                end
            end
            target:StripWeapon(weapon:GetClass())
            local _, equippedSlot, instance = Ops.FindInstance(target.ZM_Inventory, instanceId)
            if equippedSlot and instance then
                local moved, moveError = self:Mutate(target, function(draft)
                    local moving = draft.equipped[equippedSlot]
                    if not moving then return false, "That weapon is not equipped." end
                    local destination
                    for slot = 1, Items.ContainerCapacity.backpack do
                        if not draft.backpack[slot] then destination = slot break end
                    end
                    if not destination then return false, "Your backpack is full." end
                    draft.equipped[equippedSlot] = nil
                    draft.backpack[destination] = moving
                    return true
                end)
                if not moved then
                    target.ZM_WeaponSlots = previousSlots
                    self:RestoreEquippedWeapons(target)
                    return false, moveError
                end
            end
            saveWeaponSlots(target)
            self:Send(target)
            return true
        end
    end
    return false, "That item is not equipped."
end

local actionCooldown = 0.15

// Validates and runs one client inventory request. The client only names an action; the server decides the outcome.
function Service:HandleAction(target, request)
    if type(request) ~= "table" or type(request.action) ~= "string" then
        return false, "Invalid request."
    end
    local now = CurTime()
    if target.ZM_NextInventoryActionAt and now < target.ZM_NextInventoryActionAt then
        return false, "Slow down."
    end
    target.ZM_NextInventoryActionAt = now + actionCooldown
    if not target:Alive() then
        return false, "You are dead."
    end
    local instanceId = request.instanceId
    if type(instanceId) ~= "string" or #instanceId > 64 then
        return false, "Invalid item."
    end

    if request.action == "use" then
        return self:UseItem(target, instanceId)
    elseif request.action == "equip" then
        local equipped, result = self:EquipWeapon(target, instanceId)
        return equipped, equipped and "Equipped." or result
    elseif request.action == "equip_slot" then
        return self:EquipWeaponInSlot(target, instanceId, request.slot)
    elseif request.action == "unequip" then
        return self:UnequipWeapon(target, instanceId)
    elseif request.action == "move" then
        local container = request.container
        if not Items.Containers[container] then
            return false, "Invalid container."
        end
        local slot = request.slot ~= nil and tonumber(request.slot) or nil
        local count = request.count ~= nil and tonumber(request.count) or nil
        if (request.slot ~= nil and not slot) or (request.count ~= nil and not count) then
            return false, "Invalid slot or count."
        end
        return self:MoveItem(target, instanceId, container, slot, count)
    end
    return false, "Unknown action."
end

net.Receive("ZM.InventoryRequest", function(_, target)
    if IsValid(target) and (not target.ZM_NextInventoryRequestAt or CurTime() >= target.ZM_NextInventoryRequestAt) then
        target.ZM_NextInventoryRequestAt = CurTime() + 1
        Service:Send(target)
    end
end)

net.Receive("ZM.InventoryAction", function(length, target)
    if not IsValid(target) or length > 4096 then
        return
    end
    local ok, message = Service:HandleAction(target, util.JSONToTable(net.ReadString()))
    net.Start("ZM.InventoryActionResult")
        net.WriteBool(ok == true)
        net.WriteString(type(message) == "string" and message or (ok and "Done." or "That did not work."))
    net.Send(target)
end)

function Service:GiveInstance(target, instance, container)
    return self:Mutate(target, function(draft)
        return Ops.Add(draft, container or "backpack", table.Copy(instance))
    end)
end

function Service:RemoveItem(target, itemId, count, container)
    return self:Mutate(target, function(draft)
        return Ops.Remove(draft, container or "backpack", itemId, count or 1)
    end)
end

function Service:RemoveInstance(target, instanceId, count)
    return self:Mutate(target, function(draft)
        return Ops.RemoveInstance(draft, instanceId, count)
    end)
end

function Service:MoveItem(target, instanceId, toContainer, toSlot, count)
    local inventory = target.ZM_Inventory
    if not inventory then
        return false, "inventory is not loaded"
    end
    local fromContainer = Ops.FindInstance(inventory, instanceId)
    if not fromContainer then
        return false, "item instance not found"
    end
    if (fromContainer == "stash" or toContainer == "stash") and not self:CanAccessStash(target) then
        return false, "The stash is only available inside a den."
    end
    if fromContainer == "equipped" and toContainer == "backpack" then
        // Detach the loadout first; otherwise normalization during the mutation sees the held SWEP and pulls the item back.
        local previousSlots = table.Copy(target.ZM_WeaponSlots or {})
        local heldClass
        for slot = 1, 3 do
            if target.ZM_WeaponSlots and target.ZM_WeaponSlots[slot] and target.ZM_WeaponSlots[slot].instanceId == instanceId then
                target.ZM_WeaponSlots[slot] = nil
            end
        end
        for _, weapon in ipairs(target:GetWeapons()) do
            if weapon.GetItemInstanceId and weapon:GetItemInstanceId() == instanceId then
                heldClass = weapon:GetClass()
                target:StripWeapon(heldClass)
            end
        end
        local moved, moveError = self:Mutate(target, function(draft)
            local sourceContainer, draftSourceSlot, instance = Ops.FindInstance(draft, instanceId)
            if sourceContainer ~= "equipped" or not instance then return false, "That weapon is not equipped." end
            local destination = toSlot
            if destination == nil then
                for slot = 1, Items.ContainerCapacity.backpack do
                    if not draft.backpack[slot] then destination = slot break end
                end
            end
            if not destination or draft.backpack[destination] then return false, "That backpack slot is occupied." end
            draft.equipped[draftSourceSlot] = nil
            draft.backpack[destination] = instance
            return true
        end)
        if moved then
            saveWeaponSlots(target)
        else
            target.ZM_WeaponSlots = previousSlots
            if heldClass then self:RestoreEquippedWeapons(target) end
        end
        return moved, moveError
    end
    return self:Mutate(target, function(draft)
        return Ops.Move(draft, instanceId, toContainer, toSlot, count, Service.NewInstanceId)
    end)
end

// Empties the backpack. Returns true and the number of stacks lost.
function Service:LoseBackpack(target)
    return self:Mutate(target, function(draft)
        local lost = table.Count(draft.backpack)
        draft.backpack = {}
        return true, lost
    end)
end

// Deletes every item for the target in the active profile (used by a character reset).
function Service:Clear(target)
    local deleted, deleteError = ZM_DeletePlayerItems(target:SteamID(), profileFor(target))
    if not deleted then
        return false, deleteError
    end
    target.ZM_Inventory = Service.NewInventory()
    self:Send(target)
    return true
end

function Service:Count(target, itemId, container)
    return target.ZM_Inventory and Ops.Count(target.ZM_Inventory, itemId, container) or 0
end

// Player API. Inventory tables returned by GetInventory are live and must be treated as read-only.
function ply:GetInventory()
    return self.ZM_Inventory
end

function ply:GiveItem(itemId, count, options)
    return Service:GiveItem(self, itemId, count, options)
end

function ply:GiveItemInstance(instance, container)
    return Service:GiveInstance(self, instance, container)
end

function ply:RemoveItem(itemId, count, container)
    return Service:RemoveItem(self, itemId, count, container)
end
ply.RemoveInventoryItem = ply.RemoveItem

function ply:RemoveItemInstance(instanceId, count)
    return Service:RemoveInstance(self, instanceId, count)
end

function ply:MoveItem(instanceId, toContainer, toSlot, count)
    return Service:MoveItem(self, instanceId, toContainer, toSlot, count)
end

function ply:CountItem(itemId, container)
    return Service:Count(self, itemId, container)
end

function ply:HasItem(itemId, count, container)
    return self:CountItem(itemId, container) >= (count or 1)
end

function ply:CanAccessStash()
    return Service:CanAccessStash(self)
end

function ply:UseItem(reference, targetPly)
    return Service:UseItem(self, reference, targetPly)
end

function ply:EquipItem(reference)
    return Service:EquipWeapon(self, reference)
end

function ply:SendInventory()
    if self.ZM_Inventory then
        Service:LoadDenStash(self)
    end
    Service:Send(self)
end

hook.Add("PlayerDeath", "ZM.Inventory.LoseBackpackOnDeath", function(victim)
    if not IsValid(victim) or not victim.ZM_Inventory then
        return
    end
    if ZM_AmmoService then
        local synced, syncError = ZM_AmmoService:SyncAll(victim)
        if not synced then
            ErrorNoHalt("[ZombieSim] Could not persist weapon ammunition before death loss for " .. victim:SteamID() .. ": " .. tostring(syncError) .. "\n")
            return
        end
    end
    if next(victim.ZM_Inventory.backpack) == nil then return end
    local lost, result = Service:LoseBackpack(victim)
    if lost then
        victim:ChatPrint("[ZombieSim] You died and lost everything in your backpack.")
    else
        ErrorNoHalt("[ZombieSim] Could not clear the backpack after death for " .. victim:SteamID() .. ": " .. tostring(result) .. "\n")
    end
end)

// Admin commands. From the server console or the dev bridge they act on the first connected human.
local firstHuman = ZM_Util.FirstHuman

local resolveTarget = ZM_Util.ResolveCommandTarget

local reply = ZM_Util.Reply

local function describeInventory(target)
    local inventory = target.ZM_Inventory
    if not inventory then
        return { "Inventory is not loaded for " .. target:Nick() .. "." }
    end
    local lines = { string.format("Inventory for %s (stash %s):", target:Nick(), Service:CanAccessStash(target) and "accessible" or "locked") }
    for _, container in ipairs({ "backpack", "stash" }) do
        local slots = inventory[container]
        table.insert(lines, string.format("  %s %d/%d", container, table.Count(slots), Items.ContainerCapacity[container]))
        for slot, instance in SortedPairs(slots) do
            local attributes = ""
            if instance.attributes then
                local parts = {}
                for name, value in SortedPairs(instance.attributes) do
                    table.insert(parts, name .. " " .. value)
                end
                attributes = " [" .. table.concat(parts, ", ") .. "]"
            end
            local freshness = ""
            local band = ZM_Food:GetBand(instance)
            if band then
                freshness = "  " .. ZM_Food.Bands[band].label
            end
            table.insert(lines, string.format("    %2d  %s x%d  L%d  %s%s%s%s", slot, Items:GetDisplayName(instance), instance.count, instance.level, instance.instanceId, attributes, freshness, instance.missingDefinition and "  (unknown item)" or ""))
        end
    end
    return lines
end

local function inventoryReport(target)
    return {
        steamId = target:SteamID(),
        profile = profileFor(target),
        canAccessStash = Service:CanAccessStash(target),
        rows = target.ZM_Inventory and Service.ToRows(target.ZM_Inventory) or nil
    }
end

local function runInventoryCommand(caller, command, arguments)
    local target = resolveTarget(caller, command)
    if not target then
        return false, "no target player"
    end

    local ok, result = true, nil
    if command == "zn_give_item" then
        local itemId = arguments[1]
        local count = tonumber(arguments[2]) or 1
        local options = { level = tonumber(arguments[3]), mastercraft = arguments[4] == "1", danger = target:GetDangerIntensity() }
        ok, result = Service:GiveItem(target, itemId, count, options)
        reply(caller, ok and ("Gave " .. count .. " x " .. tostring(itemId) .. ".") or ("Could not give item: " .. tostring(result)))
    elseif command == "zn_use_item" then
        ok, result = Service:UseItem(target, arguments[1])
        reply(caller, ok and ("Used " .. tostring(arguments[1]) .. ".") or ("Could not use item: " .. tostring(result)))
    elseif command == "zn_equip_item" then
        ok, result = Service:EquipWeapon(target, arguments[1])
        reply(caller, ok and ("Equipped " .. result:GetClass() .. ".") or ("Could not equip item: " .. tostring(result)))
    elseif command == "zn_remove_item" then
        local count = tonumber(arguments[2]) or 1
        ok, result = Service:RemoveItem(target, arguments[1], count, arguments[3])
        reply(caller, ok and ("Removed " .. count .. " x " .. tostring(arguments[1]) .. ".") or ("Could not remove item: " .. tostring(result)))
    elseif command == "zn_move_item" then
        ok, result = Service:MoveItem(target, arguments[1], arguments[2], tonumber(arguments[3]), tonumber(arguments[4]))
        reply(caller, ok and "Moved item." or ("Could not move item: " .. tostring(result)))
    end
    for _, line in ipairs(describeInventory(target)) do
        reply(caller, line)
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        local report = inventoryReport(target)
        report.command = command
        report.ok = ok
        report.error = not ok and result or nil
        ZM_DevConsole:Report("inventory", report)
    end
    if not ok then
        return false, tostring(result)
    end
    return true
end

ZM_Util.RegisterCommands({
    zn_inventory = "Prints the target player's backpack and stash.",
    zn_give_item = "zn_give_item <itemId> [count] [level] [mastercraft 0/1]: adds items to the backpack (weapons roll level and attributes when level is omitted).",
    zn_use_item = "zn_use_item <instanceId|itemId>: uses one unit of a backpack item.",
    zn_equip_item = "zn_equip_item <instanceId|itemId>: equips a backpack weapon with its rolled attributes.",
    zn_remove_item = "zn_remove_item <itemId> [count] [container]: removes items (backpack by default).",
    zn_move_item = "zn_move_item <instanceId> <backpack|stash> [slot] [count]: moves or splits a stack."
}, runInventoryCommand)
