// Server-only tests for inventory operations and persistence. Uses a stub player and a throwaway SteamID/profile.
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items
local SafeZones = ZM_SafeZones
local Drops = ZM_DroppedItems

local testSteamId = "STEAM_TEST:0:2700"
local testProfile = "zn_test"
local otherProfile = "zn_test_other"
local testDropCellId = 999990
local testDropLocationId = "cell:" .. testDropCellId

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local nextId = 0
local function newId()
    nextId = nextId + 1
    return "test" .. nextId
end

local function instance(itemId, count, extra)
    local definition = Items:GetDefinition(itemId)
    local result = { instanceId = newId(), itemId = itemId, count = count or 1, level = definition and definition.minLevel or 1, mastercraft = false, clip = 0, createdAt = 0 }
    for key, value in pairs(extra or {}) do
        result[key] = value
    end
    return result
end

local function stubPlayer(profile)
    return {
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        SteamID = function() return testSteamId end,
        ZM_Inventory = Service.NewInventory(),
        ZM_InventoryProfile = profile or testProfile
    }
end

local function stubUser(level, attributes)
    return {
        IsValid = function() return true end,
        GetLevel = function() return level end,
        GetStat = function(_, name) return attributes[name] or 0 end
    }
end

local function cleanup()
    ZM_DeletePlayerItems(testSteamId, testProfile)
    ZM_DeletePlayerItems(testSteamId, otherProfile)
    sql.Query("DELETE FROM world_dropped_items WHERE profile = " .. sql.SQLStr(testProfile) .. " AND cellId = " .. testDropCellId)
    sql.Query("DELETE FROM world_drop_requests WHERE profile = " .. sql.SQLStr(testProfile) .. " AND cellId = " .. testDropCellId)
    sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(testSteamId))
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

local function withDropOverrides(overrides, callback)
    local previous = {}
    for key, value in pairs(overrides) do
        previous[key] = Drops[key]
        Drops[key] = value
    end
    local originalSend = Service.Send
    Service.Send = function() end
    local ok, result = pcall(callback)
    Service.Send = originalSend
    for key, value in pairs(previous) do
        Drops[key] = value
    end
    if not ok then error(result) end
end

local function withCommitOverride(commitWriter, callback)
    local originalCommit = ZM_CommitWrites
    ZM_CommitWrites = commitWriter
    local ok, result = pcall(callback)
    ZM_CommitWrites = originalCommit
    if not ok then error(result) end
end

test("stackables_merge_up_to_max_stack", function(check)
    local inventory = Service.NewInventory()
    check(Ops.Add(inventory, "backpack", instance("itemBandage", 2)), "first add failed")
    check(Ops.Add(inventory, "backpack", instance("itemBandage", 2)), "second add failed")
    check(inventory.backpack[1] and inventory.backpack[1].count == 3, "slot 1 should hold 3 bandages")
    check(inventory.backpack[2] and inventory.backpack[2].count == 1, "slot 2 should hold the remaining bandage")
    check(Ops.Count(inventory, "itemBandage") == 4, "total bandages should be 4")
end)

test("weapons_never_stack", function(check)
    local inventory = Service.NewInventory()
    Ops.Add(inventory, "backpack", instance("weaponMeleeCrowbar"))
    Ops.Add(inventory, "backpack", instance("weaponMeleeCrowbar"))
    check(table.Count(inventory.backpack) == 2, "two crowbars should use two slots")
end)

test("full_container_rejects_without_changes", function(check)
    local inventory = Service.NewInventory()
    for _ = 1, Items.ContainerCapacity.backpack - 1 do
        Ops.Add(inventory, "backpack", instance("weaponMeleeCrowbar"))
    end
    Ops.Add(inventory, "backpack", instance("itemBandage", 3))
    local before = table.Copy(inventory)
    local added = Ops.Add(inventory, "backpack", instance("weaponMeleeCrowbar"))
    check(not added, "adding to a full backpack should fail")
    local partial = Ops.Add(inventory, "backpack", instance("itemBandage", 2))
    check(not partial, "a stack that only partly fits should fail")
    check(deepEqual(inventory, before), "failed adds must not change the inventory")
end)

test("remove_takes_across_stacks_and_rejects_shortfall", function(check)
    local inventory = Service.NewInventory()
    Ops.Add(inventory, "backpack", instance("itemBandage", 3))
    Ops.Add(inventory, "backpack", instance("itemBandage", 1))
    check(Ops.Remove(inventory, "backpack", "itemBandage", 2), "removing 2 should succeed")
    check(Ops.Count(inventory, "itemBandage") == 2, "2 bandages should remain")
    local before = table.Copy(inventory)
    check(not Ops.Remove(inventory, "backpack", "itemBandage", 5), "removing more than held should fail")
    check(not Ops.Remove(inventory, "stash", "itemBandage", 1), "removing from an empty stash should fail")
    check(deepEqual(inventory, before), "failed removes must not change the inventory")
end)

test("instances_are_validated_against_definitions", function(check)
    check(not Items:ValidateInstance(instance("itemBandage", 4)), "count above maxStack should fail")
    check(not Items:ValidateInstance(instance("weaponMeleeCrowbar", 1, { level = 31 })), "level above maxLevel should fail")
    check(not Items:ValidateInstance(instance("weaponMeleeCrowbar", 1, { level = 9 })), "level below minLevel should fail")
    check(not Items:ValidateInstance(instance("itemMissing")), "unknown item should fail")
    check(not Items:ValidateInstance(instance("itemBandage", 1, { attributes = { Damage = 5 } })), "attributes on a bandage should fail")
    check(not Items:ValidateInstance(instance("itemBandage", 1, { mastercraft = true })), "mastercraft bandage should fail")
    check(not Items:ValidateInstance(instance("weaponMeleeCrowbar", 1, { attributes = { ClipSize = 5 } })), "bullet attribute on a melee weapon should fail")
    check(not Items:ValidateInstance(instance("weaponMeleeCrowbar", 1, { attributes = { Damage = 40 } })), "attribute above maxAttributes should fail")
    check(Items:ValidateInstance(instance("weaponMeleeCrowbar", 1, { level = 20, mastercraft = true, attributes = { Damage = 12, Range = 4 } })), "valid crowbar should pass")
end)

test("move_split_merge_and_swap", function(check)
    local inventory = Service.NewInventory()
    local bandages = instance("itemBandage", 3)
    local crowbar = instance("weaponMeleeCrowbar")
    Ops.Add(inventory, "backpack", bandages)
    Ops.Add(inventory, "backpack", crowbar)

    check(Ops.Move(inventory, bandages.instanceId, "stash", nil, 1, newId), "partial move to stash should succeed")
    check(inventory.backpack[1].count == 2 and inventory.stash[1].count == 1, "split should leave 2 and move 1")
    check(inventory.stash[1].instanceId ~= bandages.instanceId, "split stack needs a new instance id")

    check(Ops.Move(inventory, inventory.stash[1].instanceId, "backpack", 1, nil, newId), "merging back into a compatible stack should succeed")
    check(inventory.backpack[1].count == 3 and next(inventory.stash) == nil, "merge should restore 3 bandages")

    check(Ops.Move(inventory, crowbar.instanceId, "backpack", 1, nil, newId), "full move onto an incompatible item should swap")
    check(inventory.backpack[1].itemId == "weaponMeleeCrowbar" and inventory.backpack[2].itemId == "itemBandage", "items should be swapped")

    check(not Ops.Move(inventory, inventory.backpack[2].instanceId, "backpack", 1, 1, newId), "splitting onto an occupied slot should fail")
    check(not Ops.Move(inventory, crowbar.instanceId, "backpack", 99, nil, newId), "slot above capacity should fail")
end)

test("rows_round_trip_and_unknown_items_are_kept", function(check)
    local inventory = Service.NewInventory()
    Ops.Add(inventory, "backpack", instance("weaponMeleeCrowbar", 1, { level = 15, mastercraft = true, attributes = { Damage = 10, Swiftness = 7 } }))
    Ops.Add(inventory, "stash", instance("itemBandage", 2))
    local restored = Service.FromRows(Service.ToRows(inventory))
    check(deepEqual(restored, inventory), "rows should round-trip to an identical inventory")

    local rows = { { instanceId = "legacy1", container = "stash", slot = 4, itemId = "itemRemovedLater", count = 2, level = 1, mastercraft = 0 } }
    local kept, warnings = Service.FromRows(rows)
    check(kept.stash[4] and kept.stash[4].missingDefinition, "unknown item should be kept and flagged")
    check(#warnings == 1, "unknown item should produce one warning")
    check(#Service.ToRows(kept) == 1, "unknown item should still be saved")
end)

test("use_requirements_check_level_and_stats", function(check)
    local ok, reason = Items:CanUse(stubUser(9, { Strength = 10 }), "weaponMeleeCrowbar")
    check(not ok and string.find(reason, "player level 10", 1, true), "level 9 should fail the player level 10 requirement")
    ok, reason = Items:CanUse(stubUser(10, { Strength = 4 }), "weaponMeleeCrowbar")
    check(not ok and string.find(reason, "Strength 5", 1, true), "Strength 4 should fail the Strength 5 requirement")
    check(Items:CanUse(stubUser(10, { Strength = 5 }), "weaponMeleeCrowbar"), "meeting both requirements should pass")
    check(Items:CanUse(stubUser(1, {}), "itemBandage"), "bandage has no requirements")
end)

test("weapon_instance_level_blocks_both_equip_paths", function(check)
    local pistol = instance("weaponHandgun9mm", 1, { level = 5 })
    local lowLevelUser = stubUser(1, {})
    lowLevelUser.ZM_Inventory = Service.NewInventory()
    Ops.Add(lowLevelUser.ZM_Inventory, "backpack", pistol)

    local canUse, reason = Items:CanUse(lowLevelUser, pistol.itemId, pistol)
    check(not canUse and string.find(reason, "player level 5", 1, true), "level 1 should not use a level 5 pistol")
    local equipped, equipReason = Service:EquipWeapon(lowLevelUser, pistol.instanceId)
    check(not equipped and string.find(equipReason, "player level 5", 1, true), "direct equip should reject the level 5 pistol")
    local slotted, slotReason = Service:EquipWeaponInSlot(lowLevelUser, pistol.instanceId, 1)
    check(not slotted and string.find(slotReason, "player level 5", 1, true), "slot equip should reject the level 5 pistol")
    local container, _, stored = Ops.FindInstance(lowLevelUser.ZM_Inventory, pistol.instanceId)
    check(container == "backpack" and stored ~= nil, "rejected pistol should remain in the backpack")

    check(Items:CanUse(stubUser(5, {}), pistol.itemId, pistol), "level 5 should meet the level 5 pistol requirement")
    local crowbar = instance("weaponMeleeCrowbar", 1, { level = 10 })
    canUse, reason = Items:CanUse(stubUser(10, { Strength = 4 }), crowbar.itemId, crowbar)
    check(not canUse and string.find(reason, "Strength 5", 1, true), "meeting the weapon level should not bypass its Strength requirement")
end)

test("sqlite_round_trip_and_profile_isolation", function(check)
    local target = stubPlayer()
    check(Service:GiveItem(target, "weaponMeleeCrowbar", 1, { level = 12 }), "grant should persist")
    check(Service:GiveItem(target, "itemBandage", 5), "stack grant should persist")
    local rows = ZM_GetPlayerItems(testSteamId, testProfile)
    check(#rows == 3, "expected 3 stored rows (crowbar, 3 + 2 bandages), got " .. #rows)
    local reloaded = Service.FromRows(rows)
    check(deepEqual(reloaded, target.ZM_Inventory), "stored rows should match the live inventory")
    check(#ZM_GetPlayerItems(testSteamId, otherProfile) == 0, "another profile must not see these items")
end)

test("safezone_and_city_drops_use_distinct_persistent_locations", function(check)
    local originalLoaded = ZM_World.IsLoaded
    local originalMapPath = ZM_World.GetMapPath
    local originalProfile = ZM_World.ActiveProfile
    local originalSafeZoneGet = ZM_SafeZones.Get
    local originalSafeZoneMap = ZM_SafeZones.GetMap
    local originalGameMap = game.GetMap
    local target = { CurrentSafeZoneId = "den-alpha" }
    target.GetWorldCell = function() return { id = 17 } end

    local ok, testError = pcall(function()
        ZM_World.IsLoaded = function() return true end
        ZM_World.ActiveProfile = testProfile
        ZM_World.GetMapPath = function() return "maps/city-cell-17" end
        ZM_SafeZones.Get = function(_, safeZoneId) return { id = safeZoneId, cell = 17 } end
        ZM_SafeZones.GetMap = function(_, safeZoneId) return "safezones/" .. safeZoneId end
        game.GetMap = function() return "den-alpha" end
        local profile, cellId, denLocation = Drops:GetTargetLocation(target)
        check(profile == testProfile and cellId == 17 and denLocation == "safezone:den-alpha", "a den should get its own persistent location")

        target.CurrentSafeZoneId = "den-beta"
        game.GetMap = function() return "den-beta" end
        local _, _, secondDenLocation = Drops:GetTargetLocation(target)
        check(secondDenLocation == "safezone:den-beta" and secondDenLocation ~= denLocation, "two dens sharing one entrance cell must not share crates")

        target.CurrentSafeZoneId = ""
        game.GetMap = function() return "city-cell-17" end
        local _, _, cityLocation = Drops:GetTargetLocation(target)
        check(cityLocation == "cell:17" and cityLocation ~= denLocation, "the city entrance cell must not share its den's crates")
    end)

    ZM_World.IsLoaded = originalLoaded
    ZM_World.GetMapPath = originalMapPath
    ZM_World.ActiveProfile = originalProfile
    ZM_SafeZones.Get = originalSafeZoneGet
    ZM_SafeZones.GetMap = originalSafeZoneMap
    game.GetMap = originalGameMap
    if not ok then error(testError) end
end)

test("dropped_crate_entity_and_model_are_available", function(check)
    check(util.IsValidModel(Drops.CrateModel), "the mounted crate model should be available")
    local groundZ = 10000
    local entity, entityError = Drops:CreateWorldEntity({
        x = 0,
        y = 0,
        z = groundZ,
        yaw = 0,
        instance = { itemId = "itemBandage", count = 1 }
    })
    check(IsValid(entity), "the dropped-item entity should spawn: " .. tostring(entityError))
    if IsValid(entity) then
        local minimum = entity:GetModelBounds()
        check(math.abs(entity:GetPos().z + minimum.z - groundZ) < 0.1, "the crate model bottom should sit at its saved ground position")
        entity:Remove()
    end
end)

test("drop_creation_failure_and_bad_quantities_preserve_inventory", function(check)
    local target = stubPlayer()
    target.Alive = function() return true end
    local fakeEntitiesCreated = 0
    withDropOverrides({
        GetTargetLocation = function() return testProfile, testDropCellId, testDropLocationId, { id = testDropCellId } end,
        FindPlacement = function() return { x = 10, y = 20, z = 30, yaw = 0 } end,
        CreateWorldEntity = function()
            fakeEntitiesCreated = fakeEntitiesCreated + 1
            return nil, "simulated crate creation failure"
        end
    }, function()
        check(Service:GiveItem(target, "itemBandage", 3), "test bandages should persist")
        local instanceId = target.ZM_Inventory.backpack[1].instanceId
        local before = table.Copy(target.ZM_Inventory)
        local invalidCount = Drops:DropItem(target, instanceId, 0, "drop-invalid-quantity")
        check(not invalidCount, "zero quantity should be rejected")
        local blocked, blockError = Drops:DropItem(target, instanceId, 1, "drop-create-failure")
        check(not blocked and string.find(blockError, "simulated crate creation failure", 1, true), "crate creation failure should be explicit")
        local tooMany = Drops:DropItem(target, instanceId, 4, "drop-too-many")
        check(not tooMany, "quantity above the selected stack should be rejected")
        check(fakeEntitiesCreated == 1, "invalid quantities must be rejected before entity creation")
        check(deepEqual(target.ZM_Inventory, before), "failed drops must leave the live inventory unchanged")
        check(#ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 0, "failed drops must not persist a crate")
    end)
end)

test("partial_drop_persists_once_and_retries_are_idempotent", function(check)
    local target = stubPlayer()
    target.Alive = function() return true end
    local created = 0
    withDropOverrides({
        GetTargetLocation = function() return testProfile, testDropCellId, testDropLocationId, { id = testDropCellId } end,
        FindPlacement = function() return { x = 10, y = 20, z = 30, yaw = 0 } end,
        CreateWorldEntity = function()
            created = created + 1
            return { testEntity = true }
        end
    }, function()
        check(Service:GiveItem(target, "itemBandage", 3), "test bandages should persist")
        local instanceId = target.ZM_Inventory.backpack[1].instanceId
        local dropped, dropMessage = Drops:DropItem(target, instanceId, 2, "drop-retry-once")
        check(dropped, "partial drop should succeed: " .. tostring(dropMessage))
        check(Service:Count(target, "itemBandage", "backpack") == 1, "the source stack should retain one bandage")
        local rows = ZM_GetWorldDroppedItems(testProfile, testDropLocationId)
        check(#rows == 1 and tonumber(rows[1].itemCount) == 2, "one persisted crate should contain the requested two bandages")
        local request = ZM_GetWorldDropRequest(testProfile, "drop-retry-once")
        check(request and request.sourceInstanceId == instanceId and tonumber(request.requestedCount) == 2, "the idempotency key should be stored with the transaction")

        local retried, retryMessage = Drops:DropItem(target, instanceId, 2, "drop-retry-once")
        check(retried and string.find(retryMessage, "already processed", 1, true), "an identical retry should report its prior success")
        check(created == 1, "an identical retry must not spawn another crate")
        check(Service:Count(target, "itemBandage", "backpack") == 1, "an identical retry must not consume another item")
        check(#ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 1, "an identical retry must not persist another crate")

        local pickupRow = rows[1]
        pickupRow.profile = testProfile
        pickupRow.cellId = testDropCellId
        pickupRow.locationId = testDropLocationId
        pickupRow.dropId = rows[1].dropId
        pickupRow.instance = util.JSONToTable(rows[1].itemData)
        local picked, pickupResult = Drops:ApplyPickup(target, pickupRow)
        check(picked and pickupResult.pickedCount == 2, "the persisted crate should be claimable")
        check(#ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 0, "a claimed crate should be removed")
        local replayedAfterPickup, replayMessage = Drops:DropItem(target, instanceId, 2, "drop-retry-once")
        check(replayedAfterPickup and string.find(replayMessage, "already processed", 1, true), "a retry after pickup should still be recognized")
        check(created == 1 and #ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 0, "a post-pickup retry must not recreate the crate")
        check(Service:Count(target, "itemBandage", "backpack") == 3, "a post-pickup retry must not remove the stack again")
    end)
end)

test("failed_drop_transaction_removes_spawned_crate_and_keeps_item", function(check)
    local target = stubPlayer()
    target.Alive = function() return true end
    local fakeEntity = { testEntity = true }
    local removedEntity
    withDropOverrides({
        GetTargetLocation = function() return testProfile, testDropCellId, testDropLocationId, { id = testDropCellId } end,
        FindPlacement = function() return { x = 10, y = 20, z = 30, yaw = 0 } end,
        CreateWorldEntity = function() return fakeEntity end,
        RemoveWorldEntity = function(_, entity) removedEntity = entity end
    }, function()
        check(Service:GiveItem(target, "itemBandage", 1), "test bandage should persist")
        local instanceId = target.ZM_Inventory.backpack[1].instanceId
        local before = table.Copy(target.ZM_Inventory)
        withCommitOverride(function() return false, "simulated transaction failure" end, function()
            local dropped, reason = Drops:DropItem(target, instanceId, 1, "drop-transaction-failure")
            check(not dropped and string.find(reason, "simulated transaction failure", 1, true), "failed persistence should be reported")
        end)
        check(removedEntity == fakeEntity, "a crate should be removed when its inventory transaction fails")
        check(deepEqual(target.ZM_Inventory, before), "failed persistence must leave the inventory unchanged")
        check(#ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 0, "failed persistence must leave no crate row")
        check(not ZM_GetWorldDropRequest(testProfile, "drop-transaction-failure"), "failed persistence must not reserve its retry key")
    end)
end)

test("partial_pickup_is_atomic_and_preserves_the_crate_remainder", function(check)
    local target = stubPlayer()
    local inventory = target.ZM_Inventory
    Ops.Add(inventory, "backpack", instance("itemBandage", 2))
    for _ = 1, Items.ContainerCapacity.backpack - 1 do
        Ops.Add(inventory, "backpack", instance("weaponMeleeCrowbar"))
    end
    local dropped = instance("itemBandage", 3)
    local now = os.time()
    local row = {
        profile = testProfile,
        cellId = testDropCellId,
        locationId = testDropLocationId,
        dropId = "pickup-test-crate",
        instance = dropped,
        x = 10,
        y = 20,
        z = 30,
        yaw = 0,
        createdAt = now,
        expiresAt = now + Drops.Lifetime
    }
    local saved, saveError = ZM_CommitWrites(testProfile, {
        {
            kind = "worldDropInsert",
            steamid = testSteamId,
            cellId = row.cellId,
            locationId = row.locationId,
            dropId = row.dropId,
            requestId = "pickup-test-request",
            sourceInstanceId = "pickup-source-instance",
            instance = row.instance,
            x = row.x,
            y = row.y,
            z = row.z,
            yaw = row.yaw,
            createdAt = row.createdAt,
            expiresAt = row.expiresAt
        }
    })
    check(saved, "test crate should persist: " .. tostring(saveError))

    withDropOverrides({}, function()
        local picked, result = Drops:ApplyPickup(target, row)
        check(picked, "partial pickup should commit: " .. tostring(result))
        check(result.pickedCount == 1 and result.remainder.count == 2, "pickup should transfer only the one stack slot that fits")
        check(Service:Count(target, "itemBandage", "backpack") == 3, "the backpack should gain exactly one bandage")
        local rows = ZM_GetWorldDroppedItems(testProfile, testDropLocationId)
        check(#rows == 1 and tonumber(rows[1].itemCount) == 2, "the remaining two bandages should stay in the crate")
        check(Service:Count({ ZM_Inventory = Service.FromRows(ZM_GetPlayerItems(testSteamId, testProfile)) }, "itemBandage", "backpack") == 3,
            "the stored backpack should match the live pickup")

        target.ZM_Inventory.backpack[Items.ContainerCapacity.backpack] = nil
        local stalePickup = Drops:ApplyPickup(target, row)
        check(not stalePickup, "a stale pickup snapshot must not commit twice")
        check(Service:Count(target, "itemBandage", "backpack") == 3, "a failed stale pickup must not add items")
        rows = ZM_GetWorldDroppedItems(testProfile, testDropLocationId)
        check(#rows == 1 and tonumber(rows[1].itemCount) == 2, "a stale pickup must leave the crate remainder unchanged")

        local current = {
            profile = testProfile,
            cellId = testDropCellId,
            locationId = testDropLocationId,
            dropId = rows[1].dropId,
            instance = util.JSONToTable(rows[1].itemData)
        }
        target.ZM_Inventory = Service.NewInventory()
        local fullyPicked, fullResult = Drops:ApplyPickup(target, current)
        check(fullyPicked and fullResult.pickedCount == 2, "an empty backpack should take the full remainder")
        check(Service:Count(target, "itemBandage", "backpack") == 2, "the full pickup should add the remaining two")
        check(#ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 0, "an empty crate should be deleted atomically")
    end)
end)

test("expired_drops_and_request_keys_are_removed", function(check)
    local now = os.time()
    local saved = ZM_CommitWrites(testProfile, {
        {
            kind = "worldDropInsert",
            steamid = testSteamId,
            cellId = testDropCellId,
            locationId = testDropLocationId,
            dropId = "expired-test-crate",
            requestId = "expired-test-request",
            sourceInstanceId = "expired-source-instance",
            instance = instance("itemBandage", 1),
            x = 10,
            y = 20,
            z = 30,
            yaw = 0,
            createdAt = now - 100,
            expiresAt = now - 1
        }
    })
    check(saved, "expired test crate should persist before cleanup")
    local expired, expireError = ZM_DeleteExpiredWorldDroppedItems(testProfile, testDropLocationId, now)
    check(expired, "expired rows should be removed: " .. tostring(expireError))
    check(#ZM_GetWorldDroppedItems(testProfile, testDropLocationId) == 0, "expired crates should no longer load")
    local request = ZM_GetWorldDropRequest(testProfile, "expired-test-request")
    check(not request, "the matching expired idempotency key should be removed")
end)

test("persisted_dropped_crates_restore_when_the_location_loads", function(check)
    local now = os.time()
    local dropId = "restore-test-crate"
    local saved, saveError = ZM_CommitWrites(testProfile, {
        {
            kind = "worldDropInsert",
            steamid = testSteamId,
            cellId = testDropCellId,
            locationId = testDropLocationId,
            dropId = dropId,
            requestId = "restore-test-request",
            sourceInstanceId = "restore-test-source",
            instance = instance("itemBandage", 2),
            x = 10,
            y = 20,
            z = 30,
            yaw = 0,
            createdAt = now,
            expiresAt = now + 86400
        }
    })
    check(saved, "the restoration fixture should persist: " .. tostring(saveError))
    if not saved then return end

    local originalCell = Drops.Cell
    local originalGetTargetLocation = Drops.GetTargetLocation
    local originalCreateWorldEntity = Drops.CreateWorldEntity
    local createdRows = {}
    Drops.Cell = nil
    Drops.GetTargetLocation = function()
        return testProfile, testDropCellId, testDropLocationId, { id = testDropCellId }
    end
    Drops.CreateWorldEntity = function(_, row)
        table.insert(createdRows, table.Copy(row))
        return { testEntity = true }
    end

    local ok, testError = pcall(function()
        local target = stubPlayer()
        target.ZM_PersistentStateLoaded = true
        local loaded, loadError = Drops:OnPlayerReady(target)
        check(loaded, "a fresh location load should restore persisted crates: " .. tostring(loadError))
        check(#createdRows == 1 and createdRows[1].dropId == dropId and createdRows[1].instance.count == 2,
            "the saved crate entity should be recreated with its persisted item and count")
        check(Drops.Cell and Drops.Cell.rows[dropId] and Drops.Cell.entities[dropId],
            "the restored crate should be registered in the active location")

        Drops.Cell = nil
        local restoredAgain, restoreError = Drops:OnPlayerReady(target)
        check(restoredAgain, "a fresh server-style location state should reload from storage: " .. tostring(restoreError))
        check(#createdRows == 2 and createdRows[2].dropId == dropId,
            "discarding active world state should recreate the crate from its durable row")
    end)

    Drops.Cell = originalCell
    Drops.GetTargetLocation = originalGetTargetLocation
    Drops.CreateWorldEntity = originalCreateWorldEntity
    if not ok then error(testError) end
end)

test("failed_mutations_leave_live_and_stored_inventory_unchanged", function(check)
    local target = stubPlayer()
    Service:GiveItem(target, "itemBandage", 2)
    local before = table.Copy(target.ZM_Inventory)
    local beforeRows = ZM_GetPlayerItems(testSteamId, testProfile)

    check(not Service:GiveItem(target, "itemMissing", 1), "unknown item grant should fail")
    check(not Service:RemoveItem(target, "itemBandage", 9), "over-removal should fail")
    target.ZM_InventoryProfile = "INVALID PROFILE"
    check(not Service:GiveItem(target, "itemBandage", 1), "a failed save should fail the grant")
    target.ZM_InventoryProfile = testProfile

    check(deepEqual(target.ZM_Inventory, before), "live inventory must be unchanged")
    check(deepEqual(ZM_GetPlayerItems(testSteamId, testProfile), beforeRows), "stored rows must be unchanged")
end)

test("failed_transaction_keeps_previous_rows", function(check)
    ZM_ReplacePlayerItems(testSteamId, testProfile, { { instanceId = "keep1", container = "stash", slot = 1, itemId = "itemBandage", count = 1, level = 1 } })
    local duplicateSlot = {
        { instanceId = "dup1", container = "backpack", slot = 1, itemId = "itemBandage", count = 1, level = 1 },
        { instanceId = "dup2", container = "backpack", slot = 1, itemId = "itemBandage", count = 1, level = 1 }
    }
    check(not ZM_ReplacePlayerItems(testSteamId, testProfile, duplicateSlot), "duplicate slots should fail the transaction")
    local rows = ZM_GetPlayerItems(testSteamId, testProfile)
    check(#rows == 1 and rows[1].instanceId == "keep1", "the previous rows must survive a rolled-back replace")
end)

test("stash_access_requires_the_players_current_den_map", function(check)
    local originalGetMap = SafeZones.GetMap
    local originalGetMapName = game.GetMap
    SafeZones.GetMap = function(_, safeZoneId)
        return safeZoneId == "inventory-test-den" and "safezones/den-test" or nil
    end
    game.GetMap = function() return "safezones/den-test" end
    local target = { CurrentSafeZoneId = "inventory-test-den" }
    local ok, errorMessage = pcall(function()
        check(Service:CanAccessStash(target), "the stash is accessible on the current den map")
        game.GetMap = function() return "city/another-map" end
        check(not Service:CanAccessStash(target), "the stash is not accessible on a different map")
        target.CurrentSafeZoneId = "missing-den"
        game.GetMap = function() return "safezones/den-test" end
        check(not Service:CanAccessStash(target), "an unknown den never grants stash access")
    end)
    SafeZones.GetMap = originalGetMap
    game.GetMap = originalGetMapName
    if not ok then error(errorMessage) end
end)

test("death_loses_backpack_but_keeps_stash", function(check)
    local target = stubPlayer()
    target.CurrentSafeZoneId = "safezone-inventory-test"
    local originalCanAccessStash = Service.CanAccessStash
    Service.CanAccessStash = function(_, player) return player == target end
    Service:GiveItem(target, "weaponMeleeCrowbar", 1)
    Service:GiveItem(target, "itemBandage", 2, { container = "stash" })
    local lost, count = Service:LoseBackpack(target)
    check(lost and count == 1, "one backpack stack should be lost")
    check(next(target.ZM_Inventory.backpack) == nil, "backpack should be empty")
    check(Service:Count(target, "itemBandage", "stash") == 2, "stash should keep its bandages")
    local rows = ZM_GetDenStashItems(testSteamId, testProfile, target.CurrentSafeZoneId)
    check(#rows == 1 and rows[1].itemId == "itemBandage", "only the per-den stash row should remain stored")
    Service.CanAccessStash = originalCanAccessStash
end)

test("death_keeps_equipped_weapon_storage", function(check)
    local target = stubPlayer()
    target.ZM_Inventory.equipped = {}
    local weaponInstance = instance("weaponMeleeCrowbar", 1)
    Ops.Add(target.ZM_Inventory, "equipped", weaponInstance)
    target.ZM_WeaponSlots = { [1] = { instanceId = weaponInstance.instanceId, selected = true } }
    Service:LoseBackpack(target)
    check(target.ZM_Inventory.equipped[1] and target.ZM_Inventory.equipped[1].instanceId == weaponInstance.instanceId, "death must preserve equipped weapon storage")
    check(target.ZM_WeaponSlots[1] and target.ZM_WeaponSlots[1].instanceId == weaponInstance.instanceId, "death must preserve equipped slot assignment")
end)

test("unequip_drag_to_backpack_keeps_item", function(check)
    local target = stubPlayer()
    local weaponInstance = instance("weaponMeleeCrowbar", 1)
    target.ZM_Inventory.equipped[1] = weaponInstance
    target.ZM_WeaponSlots = { [1] = { instanceId = weaponInstance.instanceId, selected = true } }
    local held = { { GetItemInstanceId = function() return weaponInstance.instanceId end, GetClass = function() return "weapon_zn_crowbar" end } }
    target.GetWeapons = function() return held end
    target.StripWeapon = function() held = {} end
    local moved, reason = Service:MoveItem(target, weaponInstance.instanceId, "backpack", 3)
    check(moved, "moving an equipped weapon to the backpack should succeed: " .. tostring(reason))
    Service:NormalizeWeaponSlots(target)
    check(target.ZM_Inventory.backpack[3] and target.ZM_Inventory.backpack[3].instanceId == weaponInstance.instanceId, "weapon must land in backpack slot 3")
    check(next(target.ZM_Inventory.equipped) == nil and next(target.ZM_WeaponSlots) == nil, "weapon must leave the loadout")
    local rows = ZM_GetPlayerItems(testSteamId, testProfile)
    check(#rows == 1 and rows[1].container == "backpack", "stored row should be in the backpack")
end)

test("job_is_preserved_when_callers_omit_it", function(check)
    check(ZM_SetPlayerData(testSteamId, testProfile, { Level = 1, Job = "Doctor" }, "inventory test"), "writing a job should succeed")
    check(ZM_SetPlayerData(testSteamId, testProfile, { Level = 2 }, "inventory test"), "writing without a job should succeed")
    local data = ZM_GetPlayerData(testSteamId, testProfile)
    check(data and data.Job == "Doctor", "job should stay Doctor, got " .. tostring(data and data.Job))
    check(ZM_NormalizeJob("Bad Job;") == "Civilian", "unsafe job names fall back to Civilian")
end)

local Generation = ZM_ItemGeneration

local function bandageUser(health, medicine, job)
    local user = stubPlayer()
    user.health = health
    user.messages = {}
    user.Alive = function() return true end
    user.Health = function(self) return self.health end
    user.GetMaxHealth = function() return 100 end
    user.SetHealth = function(self, value) self.health = value end
    user.EmitSound = function() end
    user.ChatPrint = function(self, message) table.insert(self.messages, message) end
    user.GetLevel = function() return 1 end
    user.GetStat = function(_, name) return name == "Medicine" and medicine or 0 end
    user.GetJobRole = function() return job or "Civilian" end
    return user
end

local function withoutIdentity(instance)
    local copy = table.Copy(instance)
    copy.instanceId = nil
    copy.createdAt = nil
    return copy
end

test("level_roll_uses_player_level_and_danger", function(check)
    local crowbar = Items:GetDefinition("weaponMeleeCrowbar")
    local rng = Generation.NewRng(1)
    for _ = 1, 500 do
        check(Generation:RollLevel(crowbar, 25, 0, rng) == 25, "danger 0 must keep the player level")
        check(Generation:RollLevel(crowbar, 3, 0, rng) == 10, "a low player level clamps up to minLevel")
        local low = Generation:RollLevel(crowbar, 25, 0.2, rng)
        check(low == 26 or low == 27, "danger 0.2 at level 25 should give 26-27, got " .. low)
        local mid = Generation:RollLevel(crowbar, 25, 0.5, rng)
        check(mid == 28 or mid == 29, "danger 0.5 at level 25 should give 28-29, got " .. mid)
        check(Generation:RollLevel(crowbar, 25, 1, rng) == 30, "danger 1 at level 25 should cap at 30")
        check(Generation:RollLevel(crowbar, 99, 0, rng) == 30, "a high player level clamps down to maxLevel")
    end
end)

test("same_seed_repeats_the_same_item", function(check)
    local first = Generation:CreateInstance("weaponHandgun9mm", { seed = 424242, playerLevel = 8, danger = 0.6, mastercraftChance = 0.5 })
    local second = Generation:CreateInstance("weaponHandgun9mm", { seed = 424242, playerLevel = 8, danger = 0.6, mastercraftChance = 0.5 })
    check(first and second, "both instances should be created")
    check(deepEqual(withoutIdentity(first), withoutIdentity(second)), "the same seed should produce the same level, mastercraft, and attributes")
end)

test("attributes_stay_in_bounds_and_rarely_match", function(check)
    local rng = Generation.NewRng(7)
    for _, itemId in ipairs({ "weaponMeleeCrowbar", "weaponHandgun9mm" }) do
        local definition = Items:GetDefinition(itemId)
        for sample = 1, 1000 do
            local level = rng:Int(definition.minLevel, definition.maxLevel)
            local instance = Generation:CreateInstance(itemId, { rng = rng, level = level })
            check(instance ~= nil, itemId .. " instance should validate")
            if not instance then
                return
            end
            local first, allSame = nil, true
            for _, name in ipairs(definition.attributes) do
                local score = instance.attributes[name]
                check(score ~= nil, itemId .. " is missing " .. name)
                check(score and score <= definition.maxAttributes - 1, "non-mastercraft " .. name .. " must stay below the max")
                first = first or score
                allSame = allSame and score == first
            end
            check(not allSame, itemId .. " sample " .. sample .. " rolled all-matching attributes without being a perfect mastercraft")
        end
    end
end)

test("higher_levels_roll_better_attributes", function(check)
    local definition = Items:GetDefinition("weaponHandgun9mm")
    local rng = Generation.NewRng(11)
    local function average(level)
        local total, count = 0, 0
        for _ = 1, 300 do
            local instance = Generation:CreateInstance("weaponHandgun9mm", { rng = rng, level = level })
            for _, score in pairs(instance.attributes) do
                total = total + score
                count = count + 1
            end
        end
        return total / count
    end
    local low, high = average(definition.minLevel), average(definition.maxLevel)
    check(high > low + 10, string.format("max-level average %.1f should clearly exceed min-level average %.1f", high, low))
end)

test("mastercrafts_are_near_max_and_perfect_is_rare", function(check)
    local definition = Items:GetDefinition("weaponMeleeCrowbar")
    local rng = Generation.NewRng(13)
    local perfect, samples = 0, 5000
    for _ = 1, samples do
        local instance = Generation:CreateInstance("weaponMeleeCrowbar", { rng = rng, level = definition.minLevel, mastercraft = true })
        local allMax = true
        for _, name in ipairs(definition.attributes) do
            local score = instance.attributes[name]
            check(score >= definition.maxAttributes - 1, "mastercraft " .. name .. " should be at least max - 1")
            allMax = allMax and score == definition.maxAttributes
        end
        if allMax then
            perfect = perfect + 1
        end
    end
    local rate = perfect / samples
    check(rate > 0.002 and rate < 0.03, string.format("perfect mastercraft rate %.4f should be about 0.01", rate))
end)

test("scales_and_value_follow_attributes", function(check)
    local definition = Items:GetDefinition("weaponHandgun9mm")
    local worst = { instanceId = "a", itemId = "weaponHandgun9mm", count = 1, level = definition.minLevel, attributes = {} }
    local best = { instanceId = "b", itemId = "weaponHandgun9mm", count = 1, level = definition.maxLevel, attributes = {} }
    for _, name in ipairs(definition.attributes) do
        worst.attributes[name] = definition.minAttributes
        best.attributes[name] = definition.maxAttributes
    end
    local worstScales, bestScales = Items:GetWeaponScales(worst), Items:GetWeaponScales(best)
    check(math.abs(worstScales.Damage - 0.6) < 1e-6 and math.abs(bestScales.Damage - 1.6) < 1e-6, "Damage should span 0.6-1.6")
    check(bestScales.FiringSpeed < worstScales.FiringSpeed, "better FiringSpeed should shorten the fire delay")
    check(bestScales.ReloadSpeed < worstScales.ReloadSpeed, "better ReloadSpeed should shorten the reload")
    check(bestScales.Swiftness == 1 and bestScales.Crushing == 1, "melee attributes stay neutral on a handgun")
    check(Items:GetWeaponScales({ itemId = "weaponHandgun9mm" }).Damage == 1, "an instance without attributes is neutral")

    local mastercraft = table.Copy(best)
    mastercraft.mastercraft = true
    check(Items:GetInstanceValue(best) > Items:GetInstanceValue(worst), "better rolls should be worth more")
    check(Items:GetInstanceValue(mastercraft) > Items:GetInstanceValue(best), "mastercrafts should be worth more")
    check(Items:GetInstanceValue({ itemId = "itemBandage", count = 3, level = 1 }) == 6, "3 bandages at $2 should be worth $6")
end)

test("weapon_aim_uses_cursor_pitch_outdoors_and_preserves_level_den_aim", function(check)
    local angles = Angle(0, 90, 0)
    local safeZone = ""
    local origin = Vector(10, 20, 36)
    local target = {
        EyeAngles = function() return angles end,
        GetNWString = function() return safeZone end,
        WorldSpaceCenter = function() return origin end
    }
    local getAim = FindMetaTable("Player").GetLevelAim
    local source, direction = getAim(target)
    check(source == origin and direction:DistToSqr(Vector(0, 1, 0)) < 0.000001,
        "level top-down/orbit commands must keep their horizontal trajectory and origin")
    for _, pitch in ipairs({ -35, 25 }) do
        angles = Angle(pitch, 40, 0)
        source, direction = getAim(target)
        check(source == origin and direction:DistToSqr(angles:Forward()) < 0.000001,
            "shoulder cursor aim must retain both yaw and pitch for weapons")
    end
    safeZone = "den"
    source, direction = getAim(target)
    check(direction:DistToSqr(Angle(0, 40, 0):Forward()) < 0.000001,
        "den aiming must retain its existing level-shot behavior")
end)

test("level_aim_dips_onto_crawlers_in_the_line_of_fire_only", function(check)
    local Low = ZM_LowTargetAim
    local function enemy(pos, mask, health)
        return {
            IsValid = function() return true end,
            Health = function() return health or 50 end,
            GetNWInt = function() return mask end,
            GetPos = function() return pos end
        }
    end
    local origin = Vector(0, 0, 36)
    local blocked = false
    local traceLine = util.TraceLine
    util.TraceLine = function() return { Hit = blocked } end
    local crawler = enemy(Vector(200, 0, 0), Low.LegsBit)
    local point = Low.Find(origin, 0, nil, { enemy(Vector(100, 0, 0), 0), crawler, enemy(Vector(150, 0, 0), Low.LegsBit, 0) })
    check(point == Vector(200, 0, Low.AimHeight), "level aim should select the live crawler, not standing or dead enemies")
    check(Low.Find(origin, 0, nil, { enemy(Vector(300, 0, 0), Low.LegsBit), crawler }) == Vector(200, 0, Low.AimHeight),
        "the nearest crawler in the line of fire should win")
    check(not Low.Find(origin, 0, nil, { enemy(Vector(200, 60, 0), Low.LegsBit), enemy(Vector(-200, 0, 0), Low.LegsBit) }),
        "crawlers beside or behind the level ray must not be targeted")
    blocked = true
    check(not Low.Find(origin, 0, nil, { crawler }), "a wall or entity in front of the crawler must keep the shot level")
    util.TraceLine = traceLine

    local find = Low.Find
    Low.Find = function() return Vector(200, 0, Low.AimHeight) end
    local angles, safeZone = Angle(0, 0, 0), ""
    local target = {
        EyeAngles = function() return angles end,
        GetNWString = function() return safeZone end,
        WorldSpaceCenter = function() return origin end
    }
    local getAim = FindMetaTable("Player").GetLevelAim
    local _, direction = getAim(target)
    check(direction.z < -0.05 and direction.x > 0, "top-down/orbit level aim should dip onto the crawler")
    angles = Angle(-10, 0, 0)
    _, direction = getAim(target)
    check(direction:DistToSqr(angles:Forward()) < 0.000001, "shoulder cursor pitch must be left unchanged")
    angles, safeZone = Angle(0, 0, 0), "den"
    _, direction = getAim(target)
    check(direction.z == 0, "den aim must stay level")
    Low.Find = find
end)

test("rolled_attributes_apply_to_a_spawned_weapon", function(check)
    local instance = Generation:CreateInstance("weaponHandgun9mm", { seed = 5, level = 20, mastercraft = true })
    local weapon = ents.Create("weapon_zn_handgun_9mm")
    check(IsValid(weapon), "weapon_zn_handgun_9mm should be registered")
    if not IsValid(weapon) then
        return
    end
    weapon:Spawn()
    Items:ApplyInstanceToWeapon(weapon, instance)
    local scales = Items:GetWeaponScales(instance)
    check(math.abs(weapon:GetDamageScale() - scales.Damage) < 1e-4, "damage scale should be applied")
    check(math.abs(weapon:GetReloadScale() - scales.ReloadSpeed) < 1e-4, "reload scale should be applied")
    check(weapon:GetItemInstanceId() == instance.instanceId, "the weapon should remember its instance")
    check(weapon:GetMaxClip() > weapon.BaseClipSize and weapon:Clip1() == 0, "a mastercraft clip should exceed the base and restore its persisted empty clip")
    weapon:Remove()
end)

test("switch_and_unequip_only_sync_firearm_ammunition", function(check)
    local target = stubPlayer()
    local meleeInstance = instance("weaponMeleeCrowbar")
    local pistolInstance = instance("weaponUsp9mm", 1, { clip = 4 })
    target.ZM_Inventory.equipped[1] = meleeInstance
    target.ZM_Inventory.equipped[2] = pistolInstance
    target.ZM_WeaponSlots = {
        [1] = { instanceId = meleeInstance.instanceId, selected = true },
        [2] = { instanceId = pistolInstance.instanceId, selected = false }
    }
    local melee = ents.Create("weapon_zn_melee_crowbar")
    local pistol = ents.Create("weapon_zn_usp_9mm")
    local originalSync = ZM_AmmoService.SyncWeapon
    local syncCalls = {}
    local ok, err = pcall(function()
        melee:Spawn()
        pistol:Spawn()
        Items:ApplyInstanceToWeapon(melee, meleeInstance)
        Items:ApplyInstanceToWeapon(pistol, pistolInstance)
        target.GetWeapons = function() return { melee, pistol } end
        local stripped
        target.StripWeapon = function(_, class) stripped = class end
        ZM_AmmoService.SyncWeapon = function(self, owner, weapon)
            table.insert(syncCalls, weapon)
            return originalSync(self, owner, weapon)
        end

        local switch = hook.GetTable().PlayerSwitchWeapon["ZM.Inventory.PersistSelectedWeapon"]
        switch(target, melee, pistol)
        check(#syncCalls == 0, "leaving melee must not attempt ammunition persistence")
        check(target.ZM_WeaponSlots[2].selected, "switching from melee must still select the pistol")
        pistol:SetClip1(2)
        switch(target, pistol, melee)
        check(#syncCalls == 1 and syncCalls[1] == pistol, "leaving a pistol must synchronize its clip")
        check(target.ZM_Inventory.equipped[2].clip == 2, "switching to melee must persist the fired pistol clip")
        check(target.ZM_WeaponSlots[1].selected, "switching to melee must still select it")

        local unequipped, reason = Service:UnequipWeapon(target, meleeInstance.instanceId)
        check(unequipped, "melee must unequip without an ammunition error: " .. tostring(reason))
        check(#syncCalls == 1, "unequipping melee must not attempt ammunition persistence")
        check(stripped == melee:GetClass(), "unequipping melee must strip the live weapon")
        check(Ops.FindInstance(target.ZM_Inventory, meleeInstance.instanceId) == "backpack", "melee must return to the backpack")

        stripped = nil
        target.ZM_InventoryProfile = "INVALID PROFILE"
        pistol:SetClip1(1)
        local removed, removeError = Service:UnequipWeapon(target, pistolInstance.instanceId)
        check(not removed and string.find(removeError, "could not save weapon ammunition", 1, true),
            "genuine firearm persistence failures must still be reported")
        check(stripped == nil and target.ZM_Inventory.equipped[2].clip == 2,
            "a failed firearm sync must not strip the weapon or change its stored clip")
    end)
    ZM_AmmoService.SyncWeapon = originalSync
    if IsValid(melee) then melee:Remove() end
    if IsValid(pistol) then pistol:Remove() end
    if not ok then error(err) end
end)

test("reload_conserves_inventory_ammo_and_persists_clip", function(check)
    local target = stubPlayer()
    local weaponInstance = Generation:CreateInstance("weaponUsp9mm", { seed = 17, level = 1 })
    weaponInstance.clip = 4
    target.ZM_Inventory.equipped[1] = weaponInstance
    target.ZM_WeaponSlots = { [1] = { instanceId = weaponInstance.instanceId, selected = true } }
    check(Ops.Add(target.ZM_Inventory, "backpack", instance("ammo9mm", 3)), "ammo should fit in the backpack")
    check(ZM_ReplacePlayerItems(testSteamId, testProfile, Service.ToRows(target.ZM_Inventory)), "initial ammo state should persist")

    local weapon = ents.Create("weapon_zn_usp_9mm")
    check(IsValid(weapon), "weapon_zn_usp_9mm should be registered")
    if not IsValid(weapon) then return end
    weapon:Spawn()
    Items:ApplyInstanceToWeapon(weapon, weaponInstance)
    check(weapon:Clip1() == 4, "the persisted clip should restore")

    local before = weapon:Clip1() + Service:Count(target, "ammo9mm", "backpack")
    local reloaded, loaded = ZM_AmmoService:CompleteReload(target, weapon)
    check(reloaded and loaded == 3, "partial reload should load all 3 available rounds")
    check(weapon:Clip1() == 7, "clip should contain the prior 4 plus 3 rounds")
    check(Service:Count(target, "ammo9mm", "backpack") == 0, "reload should consume reserve rounds")
    check(target.ZM_Inventory.equipped[1].clip == 7, "reload should persist the new clip atomically")
    check(weapon:Clip1() + Service:Count(target, "ammo9mm", "backpack") == before, "reload must conserve total rounds")

    weapon:SetClip1(2)
    check(ZM_AmmoService:SyncWeapon(target, weapon), "fired clip should sync at a boundary")
    check(target.ZM_Inventory.equipped[1].clip == 2, "boundary sync should persist the live clip")
    local rows = ZM_GetPlayerItems(testSteamId, testProfile)
    local stored
    for _, row in ipairs(rows or {}) do
        if row.instanceId == weaponInstance.instanceId then stored = row break end
    end
    check(stored and tonumber(stored.clip) == 2, "SQLite should store the synchronized clip")

    local emptyReload = ZM_AmmoService:CompleteReload(target, weapon)
    check(not emptyReload and weapon:Clip1() == 2, "reload without reserve ammo must not change the clip")
    check(Ops.Add(target.ZM_Inventory, "backpack", instance("ammo556", 5)), "mismatched ammunition should fit in the backpack")
    local mismatchedReload = ZM_AmmoService:CompleteReload(target, weapon)
    check(not mismatchedReload and weapon:Clip1() == 2, "mismatched ammunition must not reload a 9mm weapon")
    check(Service:Count(target, "ammo556", "backpack") == 5, "a rejected reload must not consume mismatched ammunition")
    weapon:Remove()
end)

test("ammo_sync_is_idempotent_and_failed_reload_changes_nothing", function(check)
    local target = stubPlayer()
    local weaponInstance = Generation:CreateInstance("weaponUsp9mm", { seed = 23, level = 1 })
    weaponInstance.clip = 5
    target.ZM_Inventory.equipped[1] = weaponInstance
    target.ZM_WeaponSlots = { [1] = { instanceId = weaponInstance.instanceId, selected = true } }
    Ops.Add(target.ZM_Inventory, "backpack", instance("ammo9mm", 10))
    check(ZM_ReplacePlayerItems(testSteamId, testProfile, Service.ToRows(target.ZM_Inventory)), "initial idempotence state should persist")

    local weapon = ents.Create("weapon_zn_usp_9mm")
    check(IsValid(weapon), "weapon_zn_usp_9mm should be registered")
    if not IsValid(weapon) then return end
    weapon:Spawn()
    Items:ApplyInstanceToWeapon(weapon, weaponInstance)
    weapon:SetClip1(3)
    check(ZM_AmmoService:SyncWeapon(target, weapon), "first clip sync should succeed")
    local firstRows = ZM_GetPlayerItems(testSteamId, testProfile)
    check(ZM_AmmoService:SyncWeapon(target, weapon), "replayed clip sync should succeed")
    check(deepEqual(firstRows, ZM_GetPlayerItems(testSteamId, testProfile)), "replayed sync must not change persisted rounds")

    target.ZM_InventoryProfile = "INVALID PROFILE"
    local before = table.Copy(target.ZM_Inventory)
    local reloaded = ZM_AmmoService:CompleteReload(target, weapon)
    check(not reloaded, "reload should fail when its inventory transaction cannot persist")
    check(weapon:Clip1() == 3, "failed reload must keep the live clip")
    check(deepEqual(target.ZM_Inventory, before), "failed reload must keep reserve and persisted clip unchanged")
    target.ZM_InventoryProfile = testProfile
    weapon:Remove()
end)

test("bandage_heals_and_is_consumed_exactly_once", function(check)
    local user = bandageUser(50, 0)
    Service:GiveItem(user, "itemBandage", 2)
    local used = Service:UseItem(user, "itemBandage")
    check(used, "the bandage should be usable at 50 HP")
    check(user.health == 75, "a bandage should heal 25, got " .. user.health)
    check(Service:Count(user, "itemBandage") == 1, "exactly one bandage should be consumed")
    check(#ZM_GetPlayerItems(testSteamId, testProfile) == 1, "the consumption should be saved")
    check(not Service:UseItem(user, "itemBandage"), "a second use inside the cooldown should be refused")
end)

test("bandage_doctor_bonus_and_full_health", function(check)
    local doctor = bandageUser(10, 5)
    Service:GiveItem(doctor, "itemBandage", 1)
    check(Service:UseItem(doctor, "itemBandage") and doctor.health == 60, "Medicine 5 should double healing to 50")

    cleanup()
    local byJob = bandageUser(10, 0, "Doctor")
    Service:GiveItem(byJob, "itemBandage", 1)
    check(Service:UseItem(byJob, "itemBandage") and byJob.health == 60, "the Doctor job should double healing")

    cleanup()
    local healthy = bandageUser(100, 0)
    Service:GiveItem(healthy, "itemBandage", 1)
    local used, reason = Service:UseItem(healthy, "itemBandage")
    check(not used and reason == "Health is already full.", "full health should refuse the bandage")
    check(Service:Count(healthy, "itemBandage") == 1, "a refused use must not consume the bandage")
end)

test("failed_save_during_use_changes_nothing", function(check)
    local user = bandageUser(40, 0)
    Service:GiveItem(user, "itemBandage", 1)
    user.ZM_InventoryProfile = "INVALID PROFILE"
    check(not Service:UseItem(user, "itemBandage"), "use should fail when the removal cannot be saved")
    check(user.health == 40, "health must not change when the removal was not saved")
    check(Service:Count(user, "itemBandage") == 1, "the bandage must still be in the backpack")
    user.ZM_InventoryProfile = testProfile
    check(not Service:UseItem(user, "weaponHandgun9mm"), "items not in the backpack cannot be used")
end)

test("client_actions_are_validated_by_the_server", function(check)
    local user = bandageUser(50, 0)
    Service:GiveItem(user, "itemBandage", 3)
    local instanceId = user.ZM_Inventory.backpack[1].instanceId
    local function act(request)
        user.ZM_NextInventoryActionAt = nil
        return Service:HandleAction(user, request)
    end

    check(not act(nil), "a missing request is rejected")
    check(not act({ action = 5 }), "a non-string action is rejected")
    check(not act({ action = "teleport", instanceId = instanceId }), "unknown actions are rejected")
    check(not act({ action = "use", instanceId = string.rep("x", 80) }), "oversized instance ids are rejected")
    check(not act({ action = "move", instanceId = instanceId, container = "vault" }), "unknown containers are rejected")
    check(not act({ action = "move", instanceId = instanceId, container = "backpack", slot = "two" }), "non-numeric slots are rejected")
    check(not act({ action = "drop", instanceId = instanceId, count = 1 }), "drop actions require a retry-safe request id")
    check(not act({ action = "drop", instanceId = instanceId, count = "many", requestId = "invalid-count" }), "drop actions reject non-numeric quantities")

    local moved, reason = act({ action = "move", instanceId = instanceId, container = "stash" })
    check(not moved and reason == "The stash is only available inside a den.", "stash moves outside a den are refused")
    check(act({ action = "move", instanceId = instanceId, container = "backpack", slot = 5 }), "moving within the backpack works")
    check(user.ZM_Inventory.backpack[5] and user.ZM_Inventory.backpack[5].instanceId == instanceId, "the stack is now in slot 5")

    check(act({ action = "use", instanceId = instanceId }), "using through a request works")
    check(user.health == 75 and Service:Count(user, "itemBandage") == 2, "the request heals and consumes one bandage")

    user.ZM_NextItemUseAt = nil
    user.ZM_NextInventoryActionAt = nil
    check(Service:HandleAction(user, { action = "move", instanceId = instanceId, container = "backpack", slot = 6 }), "the first request passes")
    local limited, limitReason = Service:HandleAction(user, { action = "move", instanceId = instanceId, container = "backpack", slot = 7 })
    check(not limited and limitReason == "Slow down.", "requests faster than the cooldown are refused")

    user.alive = false
    user.Alive = function(self) return self.alive end
    check(not act({ action = "use", instanceId = instanceId }), "dead players cannot act")
end)

local Food = ZM_Food
local testDen = "zn_test_den"

local function foodUser(values)
    local user = bandageUser(values.health or 50, 0)
    user.Hunger = values.hunger or 50
    user.Thirst = values.thirst or 50
    user.Stamina = values.stamina or 10
    return user
end

local function shelfSeconds(itemId)
    return Items:GetDefinition(itemId).food.shelfLifeHours * 3600
end

test("food_freshness_bands_and_bounded_effects", function(check)
    local now = 2000000000
    local beans = instance("itemCannedBeans", 1, { createdAt = now })
    local authored = Items:GetDefinition("itemCannedBeans").food
    local fresh = Food:GetEffects(beans, now)
    check(fresh.band == "fresh" and fresh.nutrition == authored.nutrition and fresh.stamina == authored.stamina, "new beans apply their authored effects")
    local stale = Food:GetEffects(beans, now + shelfSeconds("itemCannedBeans") * 0.6)
    check(stale.band == "stale" and stale.nutrition == 15, "stale beans give 60% nutrition, got " .. tostring(stale.nutrition))
    local spoiled = Food:GetEffects(beans, now + shelfSeconds("itemCannedBeans"))
    check(spoiled.band == "spoiled" and spoiled.nutrition == 6 and spoiled.health == Food.SpoiledHealthPenalty, "spoiled beans lose value and cost health")
    check(Food:GetBand(beans, now - 1000) == "fresh", "a timestamp in the future is treated as brand new")
    local rotten = Food:GetEffects(instance("itemRottenFood", 1, { createdAt = now }), now)
    check(rotten.band == "spoiled" and rotten.health == Items:GetDefinition("itemRottenFood").food.health, "rotten food is always spoiled and keeps its authored penalty")

    for itemId, definition in pairs(ZM_StaticData:GetRegistry().items) do
        if definition.food then
            local tier = ZM_StaticData.FoodTiers[definition.food.tier]
            check(tier ~= nil, itemId .. " must use a defined food tier")
            for _, age in ipairs({ 0, 0.3, 0.7, 1.5 }) do
                local effects = Food:GetEffects(instance(itemId, 1, { createdAt = now }), now + age * (definition.food.shelfLifeHours or 1) * 3600)
                for effect, bounds in pairs(Food.EffectBounds) do
                    check(effects[effect] >= bounds[1] and effects[effect] <= bounds[2], itemId .. " " .. effect .. " is out of bounds")
                end
            end
        end
    end
end)

test("food_stacks_only_within_band_and_keeps_oldest_timestamp", function(check)
    local now = os.time()
    local inventory = Service.NewInventory()
    check(Ops.Add(inventory, "backpack", instance("itemCannedBeans", 1, { createdAt = now - 3600 })), "first tin should fit")
    check(Ops.Add(inventory, "backpack", instance("itemCannedBeans", 1, { createdAt = now - 60 })), "second fresh tin should merge")
    check(inventory.backpack[1].count == 2 and inventory.backpack[1].createdAt == now - 3600, "a merged fresh stack keeps the oldest timestamp")
    local old = now - shelfSeconds("itemCannedBeans") * 0.8
    local staleTin = instance("itemCannedBeans", 1, { createdAt = old })
    check(Ops.Add(inventory, "backpack", staleTin), "a stale tin should fit")
    check(inventory.backpack[2] and inventory.backpack[2].createdAt == old, "a stale tin must not merge into a fresh stack")
    check(Ops.Move(inventory, staleTin.instanceId, "backpack", 1, 1, newId), "moving the stale tin onto the fresh stack swaps them")
    check(inventory.backpack[1].instanceId == staleTin.instanceId and inventory.backpack[2].count == 2, "incompatible freshness swaps rather than merging")
    check(Ops.Move(inventory, inventory.backpack[2].instanceId, "backpack", 5, 1, newId), "splitting a food stack should work")
    check(inventory.backpack[5].createdAt == now - 3600 and inventory.backpack[2].createdAt == now - 3600, "a split keeps the source timestamp")
    check(Ops.Add(inventory, "backpack", instance("itemRottenFood", 1, { createdAt = now })) and Ops.Add(inventory, "backpack", instance("itemRottenFood", 1, { createdAt = now - 99999 })), "rotten food should fit")
    check(Ops.Count(inventory, "itemRottenFood") == 2 and table.Count(inventory.backpack) == 4, "non-perishable rotten food stacks regardless of age")
end)

test("food_freshness_survives_save_load_stash_and_offline_time", function(check)
    local now = os.time()
    local createdAt = now - 10 * 3600
    local target = stubPlayer()
    Ops.Add(target.ZM_Inventory, "backpack", instance("itemPreservedMeat", 2, { createdAt = createdAt }))
    check(ZM_ReplacePlayerItems(testSteamId, testProfile, Service.ToRows(target.ZM_Inventory)), "food should persist")
    local loaded = Service.FromRows(ZM_GetPlayerItems(testSteamId, testProfile))
    check(loaded.backpack[1] and loaded.backpack[1].createdAt == createdAt, "a save/load round trip keeps the timestamp")
    check(Food:GetBand(loaded.backpack[1], now) == "fresh", "10 hours old preserved meat is fresh")
    local shelf = shelfSeconds("itemPreservedMeat")
    check(Food:GetBand(loaded.backpack[1], createdAt + shelf * 0.75) == "stale", "offline time ages food deterministically")
    check(Food:GetBand(loaded.backpack[1], createdAt + shelf + 1) == "spoiled", "food spoils after its shelf life even while offline")

    local stashRows = Service.ToRows({ backpack = {}, stash = loaded.backpack, equipped = {} })
    for _, row in ipairs(stashRows) do row.container = "stash" end
    check(ZM_ReplaceDenStashItems(testSteamId, testProfile, testDen, stashRows), "a stash deposit should persist")
    local stashed = ZM_GetDenStashItems(testSteamId, testProfile, testDen)
    check(stashed and stashed[1] and tonumber(stashed[1].createdAt) == createdAt, "a den deposit keeps the timestamp")
    ZM_ReplaceDenStashItems(testSteamId, testProfile, testDen, {})
end)

test("eating_applies_bounded_effects_exactly_once", function(check)
    local user = foodUser({ hunger = 50, thirst = 50, stamina = 10, health = 50 })
    Service:GiveItem(user, "itemCannedBeans", 2)
    local used, message = Service:UseItem(user, "itemCannedBeans")
    check(used, "hungry players can eat beans: " .. tostring(message))
    check(user.Hunger == 75 and user.Thirst == 55 and user.health == 52 and user.Stamina == 20, string.format("beans should apply +25/+5/+2/+10, got %s/%s/%s/%s", user.Hunger, user.Thirst, user.health, user.Stamina))
    check(Service:Count(user, "itemCannedBeans") == 1, "exactly one tin should be consumed")
    check(not Service:UseItem(user, "itemCannedBeans"), "a repeated request inside the cooldown is refused")
    check(Service:Count(user, "itemCannedBeans") == 1, "a refused repeat must not consume food")

    cleanup()
    local full = foodUser({ hunger = 100, thirst = 100, stamina = 100, health = 100 })
    Service:GiveItem(full, "itemCannedBeans", 1)
    local refused, reason = Service:UseItem(full, "itemCannedBeans")
    check(not refused and reason == "You are not hungry or thirsty.", "sated players are refused")
    check(Service:Count(full, "itemCannedBeans") == 1, "refused food is not consumed")
    full.ZM_NextItemUseAt = nil
    full.Hunger, full.Thirst = 99.5, 99.9
    local drifted, driftReason = Service:UseItem(full, "itemCannedBeans")
    check(not drifted and driftReason == "You are not hungry or thirsty.", "survival drift below one point does not make food useful")

    cleanup()
    local nearlyFull = foodUser({ hunger = 95, thirst = 100, stamina = 100, health = 100 })
    Service:GiveItem(nearlyFull, "itemLabGrownMeat", 1)
    check(Service:UseItem(nearlyFull, "itemLabGrownMeat") and nearlyFull.Hunger == 100, "hunger is capped at 100")
end)

test("spoiled_food_costs_health_and_failed_save_grants_nothing", function(check)
    local user = foodUser({ hunger = 40, health = 60 })
    Service:GiveItem(user, "itemCannedBeans", 1)
    user.ZM_Inventory.backpack[1].createdAt = os.time() - shelfSeconds("itemCannedBeans") - 60
    check(Service:UseItem(user, "itemCannedBeans"), "spoiled food can still be eaten")
    check(user.Hunger == 46 and user.health == 50, string.format("spoiled beans give +6 food and -10 health, got %s/%s", user.Hunger, user.health))

    cleanup()
    local failing = foodUser({ hunger = 30, thirst = 30 })
    Service:GiveItem(failing, "itemBarrelWater", 1)
    failing.ZM_InventoryProfile = "INVALID PROFILE"
    check(not Service:UseItem(failing, "itemBarrelWater"), "drinking must fail when the removal cannot be saved")
    check(failing.Thirst == 30 and failing.health == 50, "no effect is granted when the removal was not saved")
    check(Service:Count(failing, "itemBarrelWater") == 1, "the water must remain")
    failing.ZM_InventoryProfile = testProfile
    failing.ZM_NextItemUseAt = nil
    Service:GiveItem(failing, "itemOil", 2)
    local drank, oilReason = Service:UseItem(failing, "itemOil")
    check(not drank and oilReason == "That item cannot be used.", "resources that are not food cannot be consumed")
    check(Service:Count(failing, "itemOil") == 2, "refused resources stay in the backpack")
end)

function Service:RunTests()
    local summary = suite:Run({ before = cleanup, after = cleanup })
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_inventory", label = "Inventory", file = "inventory_tests.json", report = "inventoryTests",
    help = "Runs inventory operation and persistence tests against a throwaway SteamID and profile.",
    run = function() return Service:RunTests() end
})
