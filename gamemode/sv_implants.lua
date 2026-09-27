// Server-owned implants and the single character-modifier service. Installed implants live outside the inventory in
// player_implants (one per player, profile, and slot) and survive death. Installing and removing happen only through a
// Doctor's service (sv_professions.lua), which calls Install/Extract so the backpack change, the implant rows, and any
// fee are written in one transaction. Effects are aggregated here with the caps in ZM_StaticData.ImplantEffects.
ZM_ImplantService = ZM_ImplantService or {}
local Svc = ZM_ImplantService
local Implants = ZM_Implants
local Service = ZM_InventoryService
local Items = ZM_Items
local StaticData = ZM_StaticData

util.AddNetworkString("ZM.ImplantState")

Svc.RegenInterval = 1

local profileFor = ZM_Util.ProfileFor

local isPlayerEntity = ZM_Util.IsPlayerEntity

// Rows for the playerImplants commit step.
function Svc.RowsFor(installed)
    local rows = {}
    for _, slot in ipairs(Implants:GetSlots()) do
        local instance = installed and installed[slot]
        if instance then
            table.insert(rows, { slot = slot, instanceId = instance.instanceId, itemId = instance.itemId, level = instance.level, createdAt = instance.createdAt or 0, installedAt = instance.installedAt or 0 })
        end
    end
    return rows
end

// Loads installed implants for the target's inventory profile. Rows with unknown definitions are kept (and ignored).
function Svc:Load(target)
    local rows, loadError = ZM_GetPlayerImplants(target:SteamID(), profileFor(target))
    if not rows then
        target.ZM_Implants = {}
        self:Refresh(target)
        return false, loadError
    end
    local installed = {}
    for _, row in ipairs(rows) do
        if table.HasValue(Implants:GetSlots(), row.slot) then
            installed[row.slot] = {
                instanceId = row.instanceId, itemId = row.itemId, count = 1,
                level = tonumber(row.level) or 1, createdAt = tonumber(row.createdAt) or 0, installedAt = tonumber(row.installedAt) or 0,
                missingDefinition = Implants:GetDefinition(row.itemId) == nil or nil
            }
        end
    end
    target.ZM_Implants = installed
    self:Refresh(target)
    return true
end

// Recomputes the target's modifiers from installed implants and reapplies movement. Call after any implant change.
function Svc:Refresh(target)
    target.ZM_Implants = target.ZM_Implants or {}
    target.ZM_Modifiers = Implants:Aggregate(target.ZM_Implants)
    self:ApplyMovement(target)
    self:Send(target)
    return target.ZM_Modifiers
end

function Svc:GetEffect(target, effectId)
    local modifiers = target and target.ZM_Modifiers
    return modifiers and modifiers.effects[effectId] or 0
end

// Loot weight bonuses by category for loot the target finds (loot spots and enemy drops only).
function Svc:GetLootBonuses(target)
    local modifiers = target and target.ZM_Modifiers
    return modifiers and Implants:GetLootBonuses(modifiers.effects) or {}
end

// XP awards are scaled by xpGain and rounded to whole points.
function Svc:ScaleXP(target, amount)
    local gain = self:GetEffect(target, "xpGain")
    if gain <= 0 or amount <= 0 then return amount end
    return math.floor(amount * (1 + gain) + 0.5)
end

// Scales walk and run speed from the speeds the player had without implants.
function Svc:ApplyMovement(target)
    if not isPlayerEntity(target) then return end
    // Speeds are stored as floats, so compare with a tolerance; anything else set them since, which becomes the new base.
    local walk, run = target:GetWalkSpeed(), target:GetRunSpeed()
    local changed = not target.ZM_BaseWalkSpeed
        or math.abs(walk - target.ZM_AppliedWalkSpeed) > 0.01 or math.abs(run - target.ZM_AppliedRunSpeed) > 0.01
    if changed then
        target.ZM_BaseWalkSpeed, target.ZM_BaseRunSpeed = walk, run
    end
    local scale = 1 + self:GetEffect(target, "moveSpeed")
    target.ZM_AppliedWalkSpeed = target.ZM_BaseWalkSpeed * scale
    target.ZM_AppliedRunSpeed = target.ZM_BaseRunSpeed * scale
    target:SetWalkSpeed(target.ZM_AppliedWalkSpeed)
    target:SetRunSpeed(target.ZM_AppliedRunSpeed)
end

function Svc:BuildState(target)
    local state = { slots = {}, effects = {} }
    local installed = target.ZM_Implants or {}
    for _, slot in ipairs(Implants:GetSlots()) do
        local instance = installed[slot]
        local entry = { slot = slot }
        if instance then
            local definition = Implants:GetDefinition(instance.itemId)
            entry.itemId, entry.level, entry.instanceId = instance.itemId, instance.level, instance.instanceId
            entry.name = definition and definition.name or instance.itemId
            entry.effects = {}
            for effectId, value in SortedPairs(Implants:GetInstanceEffects(instance)) do
                table.insert(entry.effects, { id = effectId, value = value, text = Implants:FormatEffect(effectId, value) })
            end
        end
        table.insert(state.slots, entry)
    end
    local modifiers = target.ZM_Modifiers or Implants:Aggregate(installed)
    for effectId, value in SortedPairs(modifiers.effects) do
        table.insert(state.effects, { id = effectId, value = value, capped = modifiers.capped[effectId] == true, text = Implants:FormatEffect(effectId, value) })
    end
    return state
end

function Svc:Send(target)
    if not isPlayerEntity(target) then return end
    net.Start("ZM.ImplantState")
        net.WriteString(util.TableToJSON(self:BuildState(target), false) or "{}")
    net.Send(target)
end

// Backpack instance of an implant item (by instance id, or the first stack of an item id) at or below maxLevel.
function Svc:FindInstallable(customer, ref, maxLevel)
    local bestSlot, best
    for slot, instance in pairs(customer.ZM_Inventory and customer.ZM_Inventory.backpack or {}) do
        if (instance.instanceId == ref or instance.itemId == ref) and Implants:GetDefinition(instance.itemId)
            and (tonumber(instance.level) or 1) <= maxLevel and (not bestSlot or instance.instanceId == ref or slot < bestSlot) then
            if instance.instanceId == ref then return instance end
            bestSlot, best = slot, instance
        end
    end
    return best
end

local function combineSteps(implantRows, steamid, extraSteps)
    return function(draft, result)
        local steps = { { kind = "playerImplants", steamid = steamid, rows = implantRows } }
        if extraSteps then
            local extra, extraError = extraSteps(draft, result)
            if not extra then return nil, extraError end
            table.Add(steps, extra)
        end
        return steps
    end
end

local function backpackCopy(instance)
    return { instanceId = instance.instanceId, itemId = instance.itemId, count = 1, level = instance.level, mastercraft = false, createdAt = instance.createdAt or 0 }
end

// Installs a backpack implant into its slot. An implant already in that slot returns to the backpack.
// extraSteps(draft, result) may add fee steps. Returns true, { installed, replaced } or false and a reason.
function Svc:Install(customer, ref, maxLevel, extraSteps, now)
    local instance = self:FindInstallable(customer, ref, maxLevel or StaticData.MaximumItemLevel)
    if not instance then return false, "That implant is not in the backpack." end
    local definition = Implants:GetDefinition(instance.itemId)
    local slot = definition.implant.slot
    local installed = table.Copy(customer.ZM_Implants or {})
    local replaced = installed[slot]
    local instanceId = instance.instanceId
    installed[slot] = { instanceId = instanceId, itemId = instance.itemId, count = 1, level = instance.level, createdAt = instance.createdAt or 0, installedAt = now or os.time() }
    local ok, result = Service:Mutate(customer, function(draft)
        local removed, removeError = Service.Ops.RemoveInstance(draft, instanceId, 1)
        if not removed then return false, removeError end
        if replaced then
            local added, addError = Service.Ops.Add(draft, "backpack", backpackCopy(replaced))
            if not added then return false, "no room in the backpack for the removed implant: " .. tostring(addError) end
        end
        return true, { installed = installed[slot], replaced = replaced, slot = slot }
    end, { extraSteps = combineSteps(self.RowsFor(installed), customer:SteamID(), extraSteps) })
    if not ok then return false, result end
    customer.ZM_Implants = installed
    self:Refresh(customer)
    return true, result
end

// Removes the implant in a slot and returns it to the backpack.
function Svc:Extract(customer, slot, extraSteps)
    local installed = table.Copy(customer.ZM_Implants or {})
    local removed = installed[slot]
    if not removed then return false, "No implant is installed in the " .. tostring(slot) .. " slot." end
    installed[slot] = nil
    local ok, result = Service:Mutate(customer, function(draft)
        local added, addError = Service.Ops.Add(draft, "backpack", backpackCopy(removed))
        if not added then return false, "no room in the backpack: " .. tostring(addError) end
        return true, { removed = removed, slot = slot }
    end, { extraSteps = combineSteps(self.RowsFor(installed), customer:SteamID(), extraSteps) })
    if not ok then return false, result end
    customer.ZM_Implants = installed
    self:Refresh(customer)
    return true, result
end

// Deletes every installed implant for the target's profile (character reset and development cleanup).
function Svc:Clear(target)
    local deleted, deleteError = ZM_DeletePlayerImplants(target:SteamID(), profileFor(target))
    if not deleted then return false, deleteError end
    target.ZM_Implants = {}
    self:Refresh(target)
    return true
end

// Health regeneration: healthRegen HP per minute while alive and hurt, carried between ticks so fractions accrue.
timer.Create("ZM.ImplantRegen", Svc.RegenInterval, 0, function()
    for _, target in ipairs(player.GetHumans()) do
        local regen = Svc:GetEffect(target, "healthRegen")
        if regen > 0 and target:Alive() and target:Health() < target:GetMaxHealth() then
            target.ZM_RegenCarry = (target.ZM_RegenCarry or 0) + regen * Svc.RegenInterval / 60
            local whole = math.floor(target.ZM_RegenCarry)
            if whole >= 1 then
                target.ZM_RegenCarry = target.ZM_RegenCarry - whole
                target:SetHealth(math.min(target:GetMaxHealth(), target:Health() + whole))
            end
        else
            target.ZM_RegenCarry = 0
        end
    end
end)

// Spawning may reset speeds; reapply once the spawn has finished.
hook.Add("PlayerSpawn", "ZM.Implants.ApplyMovement", function(target)
    timer.Simple(0, function()
        if IsValid(target) and target.ZM_Modifiers then Svc:ApplyMovement(target) end
    end)
end)

// ---------------------------------------------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------------------------------------------

local firstHuman = ZM_Util.FirstHuman

local function runImplantCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command, { zn_implants = true }) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    if not target then return false, "no target player" end
    local ok, message = true, nil
    if command == "zn_dev_clear_implants" then
        ok, message = Svc:Clear(target)
        message = ok and "removed every installed implant (items were not returned)" or message
    end
    local state = Svc:BuildState(target)
    local lines = {}
    for _, entry in ipairs(state.slots) do
        table.insert(lines, entry.slot .. ": " .. (entry.name and (entry.name .. " (level " .. entry.level .. ")") or "empty"))
    end
    for _, effect in ipairs(state.effects) do
        table.insert(lines, "  " .. effect.text .. (effect.capped and " (capped)" or ""))
    end
    local output = "[ZombieSim] " .. command .. ": " .. tostring(message or (ok and "ok" or "failed")) .. "\n  " .. table.concat(lines, "\n  ")
    ZM_Util.Print(caller, output)
    if ZM_DevConsole and ZM_DevConsole.Report then
        state.command, state.ok, state.message = command, ok, message
        state.walkSpeed, state.runSpeed = target:GetWalkSpeed(), target:GetRunSpeed()
        state.lootBonuses = Svc:GetLootBonuses(target)
        ZM_DevConsole:Report("implants", state)
    end
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_implants = "Reports installed implants and the aggregated, capped modifiers.",
    zn_dev_clear_implants = "Development: deletes the target player's installed implants for the active profile."
}, runImplantCommand)
