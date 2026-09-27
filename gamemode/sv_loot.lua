// Server-only loot rolls over the resolved entries built by ZM_StaticData (loot groups, entity-loot rules, enemies, bosses).
// Every roll takes an optional rng (ZM_ItemGeneration.NewRng) so tests and the test command are repeatable.
// Source entries are only read; rolls never modify the registry.
ZM_Loot = ZM_Loot or {}
local Loot = ZM_Loot
local Generation = ZM_ItemGeneration

local function clampDanger(danger)
    return math.Clamp(tonumber(danger) or 0, 0, 1)
end

// Weight multiplier for an entry from loot bonuses by category ({ weapons = 0.2 } makes weapons 1.2x). Implant items
// are never boosted, so an implant can not make other implants more likely.
function Loot.GetBonusMultiplier(entry, bonuses)
    if not bonuses then return 1 end
    local definition = ZM_StaticData:GetItem(entry.item)
    local category = definition and definition.lootCategory
    if not category or category == "implants" then return 1 end
    return 1 + math.max(tonumber(bonuses[category]) or 0, 0)
end

// Interpolated weight per entry; entries whose weight is not above 0 are excluded. Returns the list and total.
// bonuses (optional) scales weights by item loot category; see GetBonusMultiplier.
function Loot.GetWeights(entries, danger, bonuses)
    danger = clampDanger(danger)
    local weights, total = {}, 0
    for _, entry in ipairs(entries or {}) do
        local weight = Lerp(danger, entry.minWeight or 0, entry.maxWeight or entry.minWeight or 0) * Loot.GetBonusMultiplier(entry, bonuses)
        if weight > 0 then
            table.insert(weights, { entry = entry, weight = weight })
            total = total + weight
        end
    end
    return weights, total
end

// Weighted pick of one entry. A single positive-weight entry is always picked; returns nil when nothing can roll.
function Loot.PickEntry(entries, danger, rng, bonuses)
    local weights, total = Loot.GetWeights(entries, danger, bonuses)
    if total <= 0 then
        return nil
    end
    local roll = rng:Next() * total
    local cumulative = 0
    for _, candidate in ipairs(weights) do
        cumulative = cumulative + candidate.weight
        if roll < cumulative then
            return candidate.entry
        end
    end
    return weights[#weights].entry
end

// Stack size: danger 0 rolls up to halfway between minCount and maxCount, danger 1 up to maxCount.
function Loot.RollCount(entry, danger, rng)
    local minimum = entry.minCount or 1
    local maximum = entry.maxCount or minimum
    local upper = minimum + math.Round((maximum - minimum) * (0.5 + 0.5 * clampDanger(danger)))
    return rng:Int(minimum, upper)
end

// Rolls one item instance from entries. Options: danger, playerLevel, rng, seed, and lootBonuses (the finder's implant
// loot bonuses by category). Returns instance, entry or nil, reason.
function Loot:RollItem(entries, options)
    options = options or {}
    local rng = options.rng or Generation.NewRng(options.seed)
    local danger = clampDanger(options.danger)
    local entry = self.PickEntry(entries, danger, rng, options.lootBonuses)
    if not entry then
        return nil, "nothing in this loot table can roll"
    end
    local instance, reason = Generation:CreateInstance(entry.item, {
        rng = rng,
        count = self.RollCount(entry, danger, rng),
        level = options.level,
        playerLevel = options.playerLevel,
        danger = danger,
        mastercraft = entry.mastercraft,
        mastercraftChance = entry.mastercraftChance
    })
    if not instance then
        return nil, reason
    end
    return instance, entry
end

function Loot:RollGroup(groupId, options)
    local group = ZM_StaticData:GetLootGroup(groupId)
    if not group then
        return nil, "unknown loot group '" .. tostring(groupId) .. "'"
    end
    return self:RollItem(group.entries, options)
end

// Whether a matching prop becomes an active loot spot (activationChance is a probability, not a weight).
function Loot.RollActivation(rule, rng)
    return rng:Chance(rule.activationChance or 0)
end

function Loot:RollEntityLoot(rule, options)
    return self:RollItem(rule.entries, options)
end

// Drop chance across the enemy's own danger range: minLootDropChance at minDanger, maxLootDropChance at maxDanger.
function Loot.GetEnemyDropChance(enemy, danger)
    local minimumDanger, maximumDanger = enemy.minDanger or 0, enemy.maxDanger or 1
    local progress = 1
    if maximumDanger > minimumDanger then
        progress = math.Clamp((clampDanger(danger) - minimumDanger) / (maximumDanger - minimumDanger), 0, 1)
    end
    return Lerp(progress, enemy.minLootDropChance or 0, enemy.maxLootDropChance or 0)
end

// Rolls whether a killed enemy drops loot and what. Returns nil (no reason) when the drop chance fails.
function Loot:RollEnemyDrop(enemy, options)
    options = options or {}
    local rng = options.rng or Generation.NewRng(options.seed)
    if #enemy.lootEntries == 0 or not rng:Chance(self.GetEnemyDropChance(enemy, options.danger)) then
        return nil
    end
    local rollOptions = table.Copy(options)
    rollOptions.rng = rng
    return self:RollItem(enemy.lootEntries, rollOptions)
end

// Bosses always drop a maximum-level mastercraft weapon or an explicitly boss-only special.
function Loot:RollBossLoot(boss, options)
    options = options or {}
    local weaponEntries = {}
    for _, entry in ipairs(boss.lootEntries or {}) do
        local definition = ZM_Items:GetDefinition(entry.item)
        if definition and (definition.attributes or entry.bossOnly) then
            local forcedEntry = table.Copy(entry)
            forcedEntry.mastercraft = definition.attributes ~= nil
            forcedEntry.mastercraftChance = nil
            table.insert(weaponEntries, forcedEntry)
        end
    end
    if #weaponEntries == 0 then
        return nil, "boss loot has no mastercraft-capable weapon entries"
    end
    local rng = options.rng or Generation.NewRng(options.seed)
    local entry = Loot.PickEntry(weaponEntries, 1, rng)
    local definition = ZM_Items:GetDefinition(entry.item)
    local rollOptions = table.Copy(options)
    rollOptions.rng = rng
    rollOptions.lootBonuses = nil
    rollOptions.danger = 1
    rollOptions.level = definition.maxLevel
    rollOptions.mastercraft = definition.attributes ~= nil
    return self:RollItem({ entry }, rollOptions)
end

// Samples a group and returns theoretical and observed shares per item, mastercraft rate, and average count.
function Loot:SampleGroup(groupId, danger, samples, seed)
    local group = ZM_StaticData:GetLootGroup(groupId)
    if not group then
        return nil, "unknown loot group '" .. tostring(groupId) .. "'"
    end
    local weights, total = self.GetWeights(group.entries, danger)
    local rows, byItem = {}, {}
    for _, candidate in ipairs(weights) do
        local row = { item = candidate.entry.item, weight = candidate.weight, expected = candidate.weight / total, hits = 0, mastercraft = 0, countTotal = 0 }
        table.insert(rows, row)
        byItem[row.item] = row
    end
    local rng = Generation.NewRng(seed)
    local failures = 0
    for _ = 1, samples do
        local instance = self:RollItem(group.entries, { danger = danger, rng = rng })
        local row = instance and byItem[instance.itemId]
        if row then
            row.hits = row.hits + 1
            row.countTotal = row.countTotal + instance.count
            if instance.mastercraft then
                row.mastercraft = row.mastercraft + 1
            end
        else
            failures = failures + 1
        end
    end
    for _, row in ipairs(rows) do
        row.observed = row.hits / samples
        row.averageCount = row.hits > 0 and row.countTotal / row.hits or 0
        row.mastercraftRate = row.hits > 0 and row.mastercraft / row.hits or 0
    end
    return { group = groupId, danger = clampDanger(danger), samples = samples, seed = seed, rows = rows, failures = failures }
end

local reply = ZM_Util.Reply

local function isAllowed(caller, command)
    if not ZM_Util.RequireAdmin(caller, command) then return false end
    return true
end

local function runLootRollTest(caller, arguments)
    local groupId = arguments[1]
    local danger = tonumber(arguments[2]) or 0
    local samples = math.Clamp(math.floor(tonumber(arguments[3]) or 1000), 1, 100000)
    local seed = tonumber(arguments[4]) or math.random(1, 2147483646)
    local report, reason = Loot:SampleGroup(groupId, danger, samples, seed)
    if not report then
        reply(caller, "zn_test_loot_roll: " .. reason)
        return false, reason
    end
    reply(caller, string.format("Loot roll test: %s at danger %.2f, %d samples, seed %d", groupId, report.danger, samples, seed))
    reply(caller, string.format("  %-22s %8s %9s %9s %7s %9s", "item", "weight", "expected", "observed", "avg x", "MC rate"))
    for _, row in ipairs(report.rows) do
        reply(caller, string.format("  %-22s %8.2f %8.1f%% %8.1f%% %7.2f %8.1f%%", row.item, row.weight, row.expected * 100, row.observed * 100, row.averageCount, row.mastercraftRate * 100))
    end
    if report.failures > 0 then
        reply(caller, "  " .. report.failures .. " roll(s) failed to produce an item")
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("lootRoll", report)
    end
    return report.failures == 0, report.failures > 0 and "some rolls failed" or nil
end

// Rolls a group for the target player (their level and cell danger unless a danger is given) and adds it to the backpack.
local function runGiveLoot(caller, arguments)
    local target = IsValid(caller) and caller or ZM_Util.FirstHuman()
    if not IsValid(target) then
        reply(caller, "zn_give_loot needs a connected player.")
        return false, "no target player"
    end
    local danger = tonumber(arguments[2]) or target:GetDangerIntensity() or 0
    local instance, reason = Loot:RollGroup(arguments[1], { danger = danger, playerLevel = target:GetLevel() })
    if not instance then
        reply(caller, "zn_give_loot: " .. tostring(reason))
        return false, reason
    end
    local given, giveError = target:GiveItemInstance(instance)
    if not given then
        reply(caller, "zn_give_loot: " .. tostring(giveError))
        return false, giveError
    end
    reply(caller, string.format("Rolled %s x%d (level %d%s) from %s at danger %.2f.", instance.itemId, instance.count, instance.level, instance.mastercraft and ", mastercraft" or "", arguments[1], danger))
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("lootGrant", { group = arguments[1], danger = danger, instance = instance })
    end
    return true
end

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
for command, definition in pairs({
    zn_test_loot_roll = { run = runLootRollTest, help = "zn_test_loot_roll <group> <danger 0-1> [samples] [seed]: compares theoretical and observed loot distribution." },
    zn_give_loot = { run = runGiveLoot, help = "zn_give_loot <group> [danger]: rolls a loot group and adds the result to the backpack." }
}) do
    concommand.Add(command, function(caller, _, arguments)
        if isAllowed(caller, command) then
            definition.run(caller, arguments)
        end
    end, nil, definition.help)
    ZM_DevConsole.DirectCommands[command] = function(argumentString)
        return definition.run(nil, string.Explode("%s+", argumentString or "", true))
    end
end
