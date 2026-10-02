// Server-only tests for profile-scoped boss eligibility and lifecycle gates.
local Bosses = ZM_Bosses

local function boss(id, minimumDanger, tags, maximumActive, cooldownHours)
    return { id = id, spawnConditions = { minCellDanger = minimumDanger, allowedEnvironmentTags = tags or {}, maxActiveWorldCount = maximumActive or 1, cooldownHours = cooldownHours or 0 } }
end

local function fixtureWorld()
    return { cells = { { id = 1, danger = 0.2, tags = { "grassland" } }, { id = 2, danger = 0.8, tags = { "military" } }, { id = 3, danger = 0.9, tags = { "radioactive" } } } }
end

local function withWorld(check, body)
    local oldDanger = ZM_World.GetDangerIntensity
    local oldEnvironment = ZM_World.GetEnvironment
    ZM_World.GetDangerIntensity = function(_, cell) return cell.danger end
    ZM_World.GetEnvironment = function(_, cell) return { tags = cell.tags } end
    local ok, err = pcall(body)
    ZM_World.GetDangerIntensity = oldDanger
    ZM_World.GetEnvironment = oldEnvironment
    check(ok, "error: " .. tostring(err))
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body) suite:Add(name, body) end

test("eligibility_uses_danger_and_environment_tags", function(check)
    withWorld(check, function()
        local cells = Bosses:GetEligibleCells(boss("militaryBoss", 0.75, { "military" }), fixtureWorld())
        check(#cells == 1 and cells[1].id == 2, "only the dangerous military cell is eligible")
        check(#Bosses:GetEligibleCells(boss("missingBoss", 0.99, { "military" }), fixtureWorld()) == 0, "no eligible cell is a valid empty result")
    end)
end)

test("active_count_and_cooldown_are_profile_scoped", function(check)
    Bosses:Reset()
    local definition = boss("testBoss", 0, {}, 1, 1)
    local first = Bosses:BeginSpawn(definition, { id = 4 }, "preview", 100)
    check(first ~= nil, "the first boss can spawn")
    check(not Bosses:CanSpawn(definition, "preview", 101), "active count blocks a second boss")
    Bosses:Finish(first.id, "preview")
    check(not Bosses:CanSpawn(definition, "preview", 101), "cooldown remains after the boss is removed")
    check(Bosses:CanSpawn(definition, "city", 101), "a different profile has independent state")
    check(Bosses:CanSpawn(definition, "preview", 3701), "cooldown expires after one hour")
end)

test("finish_is_idempotently_rejected_for_unknown_instances", function(check)
    Bosses:Reset()
    local definition = boss("finishBoss", 0)
    local instance = Bosses:BeginSpawn(definition, { id = 5 }, "preview", 200)
    local finished, reason = Bosses:Finish(instance.id, "preview")
    check(finished and reason == nil, "known boss instance finishes")
    local again, againReason = Bosses:Finish(instance.id, "preview")
    check(not again and againReason == "unknown boss instance", "duplicate finish is rejected")
end)

test("active_boss_state_removes_marker_once", function(check)
    Bosses:Reset()
    local definition = boss("markerBoss", 0)
    local instance = Bosses:BeginSpawn(definition, { id = 6 }, "preview", 300)
    local finished = Bosses:Finish(instance.id, "preview")
    check(finished, "active marker boss can be removed")
    check(Bosses:GetActiveCount("preview", definition.id) == 0, "removed boss is absent from active state")
    local duplicate, reason = Bosses:Finish(instance.id, "preview")
    check(not duplicate and reason == "unknown boss instance", "marker removal is idempotently guarded")
end)

test("boss_reward_policy_has_a_rewardable_result", function(check)
    local bossDefinition = ZM_StaticData:GetBoss("bossWalker")
    check(bossDefinition ~= nil, "the shipped boss definition is registered")
    check(bossDefinition and #bossDefinition.lootEntries > 0, "the boss has configured reward entries")
    local item = bossDefinition and ZM_Loot:RollBossLoot(bossDefinition, { seed = 17, playerLevel = 1 }) or nil
    check(item ~= nil, "boss loot always produces an item")
    if item then
        local definition = ZM_Items:GetDefinition(item.itemId)
        check(definition and (definition.attributes or item.itemId == "itemBossJuice"), "boss loot is a weapon or special")
        check(item.itemId ~= "itemBandage", "boss loot excludes ordinary low-tier items")
    end
end)

function Bosses:RunTests()
    return suite:Run()
end

ZM_TestHarness.Register({
    command = "zn_test_bosses", label = "Boss", file = "boss_tests.json", report = "bossTests",
    help = "Runs the boss eligibility and lifecycle tests.",
    run = function() return Bosses:RunTests() end
})
