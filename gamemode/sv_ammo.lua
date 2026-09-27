// Server-owned clip persistence and inventory-backed reloads.
ZM_AmmoService = ZM_AmmoService or {}
local Ammo = ZM_AmmoService
local Inventory = ZM_InventoryService
local Items = ZM_Items

local function getWeaponState(target, weapon, inventory)
    if not IsValid(target) or not IsValid(weapon) or not weapon.GetItemInstanceId then
        return nil, "invalid weapon"
    end
    local instanceId = weapon:GetItemInstanceId()
    local container, _, instance = Inventory.Ops.FindInstance(inventory or target.ZM_Inventory, instanceId)
    if not instance or container ~= "equipped" then
        return nil, "weapon instance is not equipped"
    end
    local definition = Items:GetDefinition(instance.itemId)
    if not definition or definition.type ~= "bullet_weapon" or not definition.ammoId then
        return nil, "weapon has no ammunition mapping"
    end
    return {
        instanceId = instanceId,
        instance = instance,
        definition = definition
    }
end

function Ammo:GetReserve(target, ammoId)
    if not IsValid(target) or not target.ZM_Inventory then
        return 0
    end
    return Inventory.Ops.Count(target.ZM_Inventory, ammoId, "backpack")
end

function Ammo:ApplyStoredClip(weapon, instance)
    if not IsValid(weapon) then
        return false
    end
    local maximum = weapon.GetMaxClip and weapon:GetMaxClip() or 0
    weapon:SetClip1(math.Clamp(math.floor(tonumber(instance and instance.clip) or 0), 0, maximum))
    return true
end

function Ammo:SyncWeapon(target, weapon)
    local state, stateError = getWeaponState(target, weapon)
    if not state then
        return false, stateError
    end
    local clip = math.Clamp(math.floor(weapon:Clip1()), 0, weapon:GetMaxClip())
    if (tonumber(state.instance.clip) or 0) == clip then
        return true
    end

    return Inventory:MutatePlayerItems(target, function(draft)
        local draftState, draftError = getWeaponState(target, weapon, draft)
        if not draftState then
            return false, draftError
        end
        draftState.instance.clip = clip
        return true
    end)
end

function Ammo:SyncAll(target)
    if not IsValid(target) or not target.ZM_Inventory then
        return false, "inventory is not loaded"
    end
    local clips = {}
    for _, weapon in ipairs(target:GetWeapons()) do
        if weapon.GetItemInstanceId and weapon.GetMaxClip then
            local instanceId = weapon:GetItemInstanceId()
            if instanceId ~= "" then
                clips[instanceId] = math.Clamp(math.floor(weapon:Clip1()), 0, weapon:GetMaxClip())
            end
        end
    end
    if next(clips) == nil then
        return true
    end

    return Inventory:MutatePlayerItems(target, function(draft)
        for instanceId, clip in pairs(clips) do
            local container, _, instance = Inventory.Ops.FindInstance(draft, instanceId)
            if not instance or container ~= "equipped" then
                return false, "equipped weapon instance disappeared during ammunition sync"
            end
            instance.clip = clip
        end
        return true
    end)
end

function Ammo:CompleteReload(target, weapon)
    local state, stateError = getWeaponState(target, weapon)
    if not state then
        return false, stateError
    end
    local currentClip = math.Clamp(math.floor(weapon:Clip1()), 0, weapon:GetMaxClip())
    local needed = weapon:GetMaxClip() - currentClip
    if needed <= 0 then
        return false, "clip is already full"
    end

    local loaded = 0
    local mutated, mutationError = Inventory:MutatePlayerItems(target, function(draft)
        local draftState, draftError = getWeaponState(target, weapon, draft)
        if not draftState then
            return false, draftError
        end
        loaded = math.min(needed, Inventory.Ops.Count(draft, state.definition.ammoId, "backpack"))
        if loaded <= 0 then
            return false, "no " .. state.definition.ammoId .. " ammunition"
        end
        local removed, removeError = Inventory.Ops.Remove(draft, "backpack", state.definition.ammoId, loaded)
        if not removed then
            return false, removeError
        end
        draftState.instance.clip = currentClip + loaded
        return true
    end)
    if not mutated then
        return false, mutationError
    end

    weapon:SetClip1(currentClip + loaded)
    return true, loaded
end

function Ammo:GetWeaponReport(target)
    local report = {}
    if not IsValid(target) or not target.ZM_Inventory then
        return report
    end
    for _, weapon in ipairs(target:GetWeapons()) do
        local state = getWeaponState(target, weapon)
        if state then
            table.insert(report, {
                class = weapon:GetClass(),
                instanceId = state.instanceId,
                ammoId = state.definition.ammoId,
                clip = weapon:Clip1(),
                maximumClip = weapon:GetMaxClip(),
                persistedClip = tonumber(state.instance.clip) or 0,
                reserve = self:GetReserve(target, state.definition.ammoId)
            })
        end
    end
    return report
end

local firstHuman = ZM_Util.FirstHuman

local function runStatus(caller)
    local target = IsValid(caller) and caller or firstHuman()
    if not IsValid(target) then
        return false, "no target player"
    end
    local report = Ammo:GetWeaponReport(target)
    for _, entry in ipairs(report) do
        local line = string.format(
            "%s %s: clip %d/%d, persisted %d, reserve %d %s",
            entry.class, entry.instanceId, entry.clip, entry.maximumClip,
            entry.persistedClip, entry.reserve, entry.ammoId
        )
        ZM_Util.Reply(caller, line)
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("ammo", report)
    end
    return true
end

concommand.Add("zn_ammo_status", function(caller)
    if IsValid(caller) and not caller:IsAdmin() then return end
    runStatus(caller)
end, nil, "Prints live, persisted, and reserve ammunition for equipped ZombieSim weapons.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zn_ammo_status = function()
    return runStatus(nil)
end

ZM_DevConsole.DirectCommands.zombiesim_dev_reload_active = function()
    local target = firstHuman()
    local weapon = IsValid(target) and target:GetActiveWeapon() or nil
    if not IsValid(weapon) or not weapon.GetMappedAmmoId then
        return false, "the active weapon is not an inventory-backed firearm"
    end
    local before = weapon:Clip1()
    weapon:Reload()
    if not weapon:IsReloading() then
        return false, "the active weapon did not begin reloading"
    end
    return true, string.format("%s began reloading from %d/%d", weapon:GetClass(), before, weapon:GetMaxClip())
end

ZM_DevConsole.DirectCommands.zombiesim_dev_fire_active = function()
    local target = firstHuman()
    local weapon = IsValid(target) and target:GetActiveWeapon() or nil
    if not IsValid(weapon) or not weapon.GetMappedAmmoId then
        return false, "the active weapon is not an inventory-backed firearm"
    end
    local before = weapon:Clip1()
    weapon:SetNextPrimaryFire(0)
    weapon:PrimaryAttack()
    local after = weapon:Clip1()
    if before <= 0 or after ~= before - 1 then
        return false, string.format("%s did not consume exactly one round (%d to %d)", weapon:GetClass(), before, after)
    end
    return true, string.format("%s fired one round (%d to %d)", weapon:GetClass(), before, after)
end

ZM_DevConsole.DirectCommands.zombiesim_dev_equip_ammo_test_weapon = function(argumentString)
    local target = firstHuman()
    local reference = string.Trim(argumentString or "")
    if not IsValid(target) or reference == "" then
        return false, "usage: zombiesim_dev_equip_ammo_test_weapon <instanceId|itemId>"
    end
    local preferredSlot
    local container, equippedSlot = Inventory.Ops.FindInstance(target.ZM_Inventory, reference)
    if container == "equipped" then
        preferredSlot = equippedSlot
    else
        for slot = 1, 3 do
            if not target.ZM_Inventory.equipped[slot] then
                preferredSlot = slot
                break
            end
        end
    end
    if not preferredSlot then
        return false, "all weapon slots are occupied"
    end
    local previousLevel = target.Level
    target.Level = target.MaxLevel or 300
    local callSucceeded, equipped, weaponOrError = pcall(Inventory.EquipWeapon, Inventory, target, reference, preferredSlot)
    target.Level = previousLevel
    if not callSucceeded then
        return false, equipped
    end
    if not equipped then
        return false, weaponOrError
    end
    return true, "equipped " .. weaponOrError:GetClass() .. " for an ammunition runtime test"
end

ZM_DevConsole.DirectCommands.zombiesim_dev_test_weapon_round = function(argumentString)
    local target = firstHuman()
    local reference = string.Trim(argumentString or "")
    if not IsValid(target) or reference == "" then
        return false, "usage: zombiesim_dev_test_weapon_round <instanceId|itemId>"
    end
    local weapon, state
    for _, candidate in ipairs(target:GetWeapons()) do
        local candidateState = getWeaponState(target, candidate)
        if candidateState and (candidateState.instanceId == reference or candidateState.instance.itemId == reference) then
            weapon = candidate
            state = candidateState
            break
        end
    end
    if not IsValid(weapon) or not state then
        return false, "the requested inventory-backed weapon is not equipped"
    end
    if weapon:Clip1() <= 0 then
        local reloaded, reloadError = Ammo:CompleteReload(target, weapon)
        if not reloaded then
            return false, reloadError
        end
    end
    local before = weapon:Clip1()
    weapon:SetNextPrimaryFire(0)
    weapon:PrimaryAttack()
    local after = weapon:Clip1()
    local expectedDelay = weapon:GetScaledDelay(weapon.FireDelay)
    local actualDelay = weapon:GetNextPrimaryFire() - CurTime()
    if after ~= before - 1 then
        return false, string.format("%s did not consume exactly one round (%d to %d)", weapon:GetClass(), before, after)
    end
    if math.abs(actualDelay - expectedDelay) > 0.05 then
        return false, string.format("%s set an invalid firing delay (%.3f, expected %.3f)", weapon:GetClass(), actualDelay, expectedDelay)
    end
    local report = {
        class = weapon:GetClass(),
        firingMode = state.definition.firingMode,
        automatic = weapon.Primary.Automatic == true,
        clipBefore = before,
        clipAfter = after,
        firingDelay = actualDelay
    }
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("ammoRuntime", report)
    end
    return true, string.format("%s consumed one round with %.3fs cadence", weapon:GetClass(), actualDelay)
end
