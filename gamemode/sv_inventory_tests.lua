// Server-only tests for inventory operations and persistence. Uses a stub player and a throwaway SteamID/profile.
local Service = ZM_InventoryService
local Ops = Service.Ops
local Items = ZM_Items

local testSteamId = "STEAM_TEST:0:2700"
local testProfile = "zn_test"
local otherProfile = "zn_test_other"

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
    local result = { instanceId = newId(), itemId = itemId, count = count or 1, level = definition and definition.minLevel or 1, mastercraft = false, createdAt = 0 }
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
    sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(testSteamId))
end

local tests = {}
local function test(name, body)
    table.insert(tests, { name = name, body = body })
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
    check(not ok and string.find(reason, "level 10", 1, true), "level 9 should fail the level 10 requirement")
    ok, reason = Items:CanUse(stubUser(10, { Strength = 4 }), "weaponMeleeCrowbar")
    check(not ok and string.find(reason, "Strength 5", 1, true), "Strength 4 should fail the Strength 5 requirement")
    check(Items:CanUse(stubUser(10, { Strength = 5 }), "weaponMeleeCrowbar"), "meeting both requirements should pass")
    check(Items:CanUse(stubUser(1, {}), "itemBandage"), "bandage has no requirements")
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
    check(weapon:GetMaxClip() > weapon.BaseClipSize and weapon:Clip1() == weapon:GetMaxClip(), "a mastercraft clip should exceed the base and start full")
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

function Service:RunTests()
    local summary = { passed = 0, failed = 0, cases = {}, ranAt = os.time() }
    for _, entry in ipairs(tests) do
        cleanup()
        local result = { name = entry.name, failures = {} }
        local function check(condition, message)
            if not condition then
                table.insert(result.failures, message)
            end
        end
        local ok, err = pcall(entry.body, check)
        if not ok then
            table.insert(result.failures, "error: " .. tostring(err))
        end
        result.passed = #result.failures == 0
        summary[result.passed and "passed" or "failed"] = summary[result.passed and "passed" or "failed"] + 1
        table.insert(summary.cases, result)
    end
    cleanup()
    return summary
end

local function runAndRecord(caller)
    local summary = Service:RunTests()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/inventory_tests.json", util.TableToJSON(summary, true) or "{}")
    local lines = {}
    for _, result in ipairs(summary.cases) do
        table.insert(lines, (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do
            table.insert(lines, "     " .. failure)
        end
    end
    table.insert(lines, string.format("Inventory tests: %d passed, %d failed.", summary.passed, summary.failed))
    for _, line in ipairs(lines) do
        if IsValid(caller) then
            caller:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] " .. line .. "\n")
        else
            print("[ZombieSim] " .. line)
        end
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("inventoryTests", summary)
    end
    if summary.failed > 0 then
        return false, "inventory tests failed"
    end
    return true
end

concommand.Add("zn_test_inventory", function(caller)
    if IsValid(caller) and not caller:IsAdmin() then
        caller:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] zn_test_inventory must be run by an in-game admin.\n")
        return
    end
    runAndRecord(caller)
end, nil, "Runs inventory operation and persistence tests against a throwaway SteamID and profile.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zn_test_inventory = function()
    return runAndRecord(nil)
end
