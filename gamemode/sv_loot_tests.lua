// Server-only tests for the loot roll engine. Uses hand-built entries plus the live registry for no-mutation checks.
local Loot = ZM_Loot
local Generation = ZM_ItemGeneration

local function entry(item, minWeight, maxWeight, extra)
    local result = { item = item, minWeight = minWeight, maxWeight = maxWeight or minWeight, minCount = 1, maxCount = 1, mastercraft = false, mastercraftChance = 0 }
    for key, value in pairs(extra or {}) do
        result[key] = value
    end
    return result
end

local function share(entries, danger, itemId, samples, seed)
    local rng = Generation.NewRng(seed)
    local hits = 0
    for _ = 1, samples do
        local picked = Loot.PickEntry(entries, danger, rng)
        if picked and picked.item == itemId then
            hits = hits + 1
        end
    end
    return hits / samples
end

local tests = {}
local function test(name, body)
    table.insert(tests, { name = name, body = body })
end

test("weights_interpolate_between_endpoints", function(check)
    local entries = { entry("itemBandage", 10, 30), entry("weaponMeleeCrowbar", 30, 10) }
    local weights = Loot.GetWeights(entries, 0)
    check(weights[1].weight == 10 and weights[2].weight == 30, "danger 0 must use minWeight")
    weights = Loot.GetWeights(entries, 1)
    check(weights[1].weight == 30 and weights[2].weight == 10, "danger 1 must use maxWeight")
    weights = Loot.GetWeights(entries, 0.5)
    check(weights[1].weight == 20 and weights[2].weight == 20, "danger 0.5 must be halfway")
    weights = Loot.GetWeights(entries, 7)
    check(weights[1].weight == 30, "danger above 1 is clamped")
end)

test("distribution_matches_weights", function(check)
    local entries = { entry("itemBandage", 10, 30), entry("weaponMeleeCrowbar", 30, 10) }
    local low = share(entries, 0, "itemBandage", 20000, 21)
    check(math.abs(low - 0.25) < 0.02, string.format("danger 0 bandage share %.3f should be about 0.25", low))
    local middle = share(entries, 0.5, "itemBandage", 20000, 22)
    check(math.abs(middle - 0.5) < 0.02, string.format("danger 0.5 bandage share %.3f should be about 0.5", middle))
    local high = share(entries, 1, "itemBandage", 20000, 23)
    check(math.abs(high - 0.75) < 0.02, string.format("danger 1 bandage share %.3f should be about 0.75", high))
end)

test("zero_weights_and_single_entries", function(check)
    local entries = { entry("itemBandage", 0, 0), entry("weaponMeleeCrowbar", 5) }
    check(share(entries, 0.3, "itemBandage", 2000, 31) == 0, "a zero-weight entry must never be picked")
    check(share(entries, 0.3, "weaponMeleeCrowbar", 2000, 32) == 1, "the only positive entry must always be picked")
    local fading = { entry("itemBandage", 10, 0), entry("weaponMeleeCrowbar", 5) }
    check(share(fading, 1, "itemBandage", 2000, 33) == 0, "an entry whose weight fades to 0 must not roll at danger 1")
    check(Loot.PickEntry({ entry("itemBandage", 0, 0) }, 0.5, Generation.NewRng(1)) == nil, "an all-zero table rolls nothing")
    check(Loot.PickEntry({}, 0.5, Generation.NewRng(1)) == nil, "an empty table rolls nothing")
    check(Loot:RollItem({}, { seed = 1 }) == nil, "RollItem on an empty table returns nil")
end)

test("counts_scale_with_danger_and_stay_in_bounds", function(check)
    local stack = entry("itemBandage", 1, 1, { minCount = 1, maxCount = 3 })
    local rng = Generation.NewRng(41)
    local lowMax, highMax, seenHigh = 0, 0, {}
    for _ = 1, 2000 do
        local low = Loot.RollCount(stack, 0, rng)
        local high = Loot.RollCount(stack, 1, rng)
        check(low >= 1 and low <= 2, "danger 0 count must be 1-2, got " .. low)
        check(high >= 1 and high <= 3, "danger 1 count must be 1-3, got " .. high)
        lowMax = math.max(lowMax, low)
        highMax = math.max(highMax, high)
        seenHigh[high] = true
    end
    check(lowMax == 2 and highMax == 3, "each danger's full count range should appear")
    check(seenHigh[1] and seenHigh[2] and seenHigh[3], "danger 1 should roll every count from 1 to 3")
    check(Loot.RollCount(entry("itemBandage", 1), 1, rng) == 1, "a fixed count stays 1")
end)

test("mastercraft_forced_and_chance", function(check)
    local forced = { entry("weaponMeleeCrowbar", 5, 5, { mastercraft = true }) }
    local rng = Generation.NewRng(51)
    for _ = 1, 200 do
        local instance = Loot:RollItem(forced, { rng = rng })
        check(instance and instance.mastercraft, "a mastercraft entry must always roll mastercrafted")
    end
    local chance = { entry("weaponMeleeCrowbar", 5, 5, { mastercraftChance = 0.2 }) }
    local mastercrafts = 0
    for _ = 1, 5000 do
        if Loot:RollItem(chance, { rng = rng }).mastercraft then
            mastercrafts = mastercrafts + 1
        end
    end
    check(math.abs(mastercrafts / 5000 - 0.2) < 0.02, string.format("mastercraft rate %.3f should be about 0.2", mastercrafts / 5000))
    local bandage = Loot:RollItem({ entry("itemBandage", 5) }, { rng = rng })
    check(bandage and not bandage.mastercraft, "items without a weapon type are never mastercrafted")
end)

test("same_seed_repeats_the_same_rolls", function(check)
    local group = ZM_StaticData:GetLootGroup("lootGenericZombie")
    local function sequence()
        local rng = Generation.NewRng(777)
        local rolled = {}
        for index = 1, 50 do
            local instance = Loot:RollItem(group.entries, { rng = rng, danger = 0.4 })
            rolled[index] = instance.itemId .. ":" .. instance.count .. ":" .. instance.level .. ":" .. tostring(instance.mastercraft)
        end
        return table.concat(rolled, ",")
    end
    check(sequence() == sequence(), "the same seed should produce the same 50 rolls")
end)

test("rolls_never_mutate_the_registry", function(check)
    local registry = ZM_StaticData:GetRegistry()
    local before = util.TableToJSON({ registry.lootGroups, registry.entityLoot.rules, registry.enemies, registry.bosses })
    local rng = Generation.NewRng(61)
    for groupId in pairs(registry.lootGroups) do
        for _ = 1, 100 do
            Loot:RollGroup(groupId, { rng = rng, danger = rng:Next(), playerLevel = rng:Int(1, 40) })
        end
    end
    for _, rule in ipairs(registry.entityLoot.rules) do
        Loot:RollEntityLoot(rule, { rng = rng })
    end
    for _, enemy in pairs(registry.enemies) do
        Loot:RollEnemyDrop(enemy, { rng = rng, danger = 1 })
    end
    local after = util.TableToJSON({ registry.lootGroups, registry.entityLoot.rules, registry.enemies, registry.bosses })
    check(before == after, "rolling must not change any registry table")
end)

test("group_rolls_use_the_live_registry", function(check)
    local rng = Generation.NewRng(71)
    for _ = 1, 200 do
        local instance, rolledEntry = Loot:RollGroup("lootGenericZombie", { rng = rng, danger = 0.5, playerLevel = 12 })
        check(instance and ZM_Items:ValidateInstance(instance), "rolled instances must validate")
        check(rolledEntry and rolledEntry.item == instance.itemId, "the returned entry must match the instance")
    end
    local missing, reason = Loot:RollGroup("lootDoesNotExist")
    check(missing == nil and string.find(reason, "unknown loot group", 1, true), "unknown groups report an error")
end)

test("enemy_drop_chance_follows_its_danger_range", function(check)
    local enemy = { minDanger = 0.2, maxDanger = 0.6, minLootDropChance = 0.1, maxLootDropChance = 0.5, lootEntries = { entry("itemBandage", 1) } }
    local function near(value, expected) return math.abs(value - expected) < 1e-9 end
    check(near(Loot.GetEnemyDropChance(enemy, 0.2), 0.1), "minDanger gives minLootDropChance")
    check(near(Loot.GetEnemyDropChance(enemy, 0.4), 0.3), "the middle of the range is halfway")
    check(near(Loot.GetEnemyDropChance(enemy, 0.6), 0.5), "maxDanger gives maxLootDropChance")
    check(near(Loot.GetEnemyDropChance(enemy, 0), 0.1) and near(Loot.GetEnemyDropChance(enemy, 1), 0.5), "outside the range clamps")

    local rng = Generation.NewRng(81)
    local drops = 0
    for _ = 1, 10000 do
        if Loot:RollEnemyDrop(enemy, { rng = rng, danger = 0.4 }) then
            drops = drops + 1
        end
    end
    check(math.abs(drops / 10000 - 0.3) < 0.02, string.format("drop rate %.3f should be about 0.3", drops / 10000))
    check(Loot:RollEnemyDrop({ minDanger = 0, maxDanger = 1, minLootDropChance = 1, maxLootDropChance = 1, lootEntries = {} }, { rng = rng }) == nil, "an enemy without loot never drops")
end)

test("activation_and_boss_rewards", function(check)
    local rng = Generation.NewRng(91)
    local never, always, some = 0, 0, 0
    for _ = 1, 5000 do
        never = never + (Loot.RollActivation({ activationChance = 0 }, rng) and 1 or 0)
        always = always + (Loot.RollActivation({ activationChance = 1 }, rng) and 1 or 0)
        some = some + (Loot.RollActivation({ activationChance = 0.35 }, rng) and 1 or 0)
    end
    check(never == 0 and always == 5000, "activation chances 0 and 1 are exact")
    check(math.abs(some / 5000 - 0.35) < 0.02, string.format("activation rate %.3f should be about 0.35", some / 5000))

    local boss = { lootEntries = { entry("weaponMeleeCrowbar", 5, 5), entry("weaponHandgun9mm", 5, 5), entry("itemBossJuice", 2, 2, { bossOnly = true }), entry("itemBandage", 50) } }
    local crowbars = 0
    local bossJuice = 0
    for _ = 1, 500 do
        local instance = Loot:RollBossLoot(boss, { rng = rng })
        check(instance ~= nil, "a boss must always drop")
        if instance then
            local definition = ZM_Items:GetDefinition(instance.itemId)
            check(instance.level == definition.maxLevel, "every boss weapon must be maximum level")
            check(instance.itemId ~= "itemBandage", "boss rewards never select a low-tier non-boss item")
            if definition.attributes then
                check(instance.mastercraft, "every boss weapon must be mastercrafted")
            elseif instance.itemId == "itemBossJuice" then
                bossJuice = bossJuice + 1
                check(not instance.mastercraft, "special boss loot is not incorrectly marked mastercraft")
            end
        end
        if instance and instance.itemId == "weaponMeleeCrowbar" then
            crowbars = crowbars + 1
        end
    end
    check(crowbars > 150 and crowbars < 350, "both boss entries should roll")
    check(bossJuice > 0, "a boss-only special can appear in the boss reward pool")
end)

test("sample_report_matches_weights", function(check)
    local report = Loot:SampleGroup("lootGenericWeapons", 0, 20000, 101)
    check(report ~= nil, "sampling a real group should work")
    local total = 0
    for _, row in ipairs(report.rows) do
        total = total + row.expected
        check(math.abs(row.observed - row.expected) < 0.02, string.format("%s observed %.3f vs expected %.3f", row.item, row.observed, row.expected))
    end
    check(math.abs(total - 1) < 1e-9, "expected shares should add up to 1")
    check(report.failures == 0, "no roll should fail")
    check(Loot:SampleGroup("lootDoesNotExist", 0, 10, 1) == nil, "unknown groups cannot be sampled")
end)

function Loot:RunTests()
    local summary = { passed = 0, failed = 0, cases = {}, ranAt = os.time() }
    for _, definition in ipairs(tests) do
        local result = { name = definition.name, failures = {} }
        local function check(condition, message)
            if not condition then
                table.insert(result.failures, message)
            end
        end
        local ok, err = pcall(definition.body, check)
        if not ok then
            table.insert(result.failures, "error: " .. tostring(err))
        end
        result.passed = #result.failures == 0
        summary[result.passed and "passed" or "failed"] = summary[result.passed and "passed" or "failed"] + 1
        table.insert(summary.cases, result)
    end
    return summary
end

local function runAndRecord(caller)
    local summary = Loot:RunTests()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/loot_tests.json", util.TableToJSON(summary, true) or "{}")
    local lines = {}
    for _, result in ipairs(summary.cases) do
        table.insert(lines, (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do
            table.insert(lines, "     " .. failure)
        end
    end
    table.insert(lines, string.format("Loot tests: %d passed, %d failed.", summary.passed, summary.failed))
    for _, line in ipairs(lines) do
        if IsValid(caller) then
            caller:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] " .. line .. "\n")
        else
            print("[ZombieSim] " .. line)
        end
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("lootTests", summary)
    end
    if summary.failed > 0 then
        return false, "loot tests failed"
    end
    return true
end

concommand.Add("zn_test_loot", function(caller)
    if IsValid(caller) and not caller:IsAdmin() then
        caller:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] zn_test_loot must be run by an in-game admin.\n")
        return
    end
    runAndRecord(caller)
end, nil, "Runs the loot roll engine tests.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zn_test_loot = function()
    return runAndRecord(nil)
end
