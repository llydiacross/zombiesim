// Server-only tests for enemy selection, definition scaling, and kill rewards.
local Enemies = ZM_Enemies
local Generation = ZM_ItemGeneration

local function enemy(id, minDanger, maxDanger, extra)
    local result = {
        id = id, entity = "zn_walker_zombie", minDanger = minDanger, maxDanger = maxDanger, boss = false,
        minHealth = 10, maxHealth = 30, minSpeed = 1, maxSpeed = 2, xp = 5,
        minLootDropChance = 0, maxLootDropChance = 0, lootEntries = {}
    }
    for key, value in pairs(extra or {}) do
        result[key] = value
    end
    return result
end

local function spawnEntry(enemyId, minWeight, maxWeight)
    return { enemy = enemyId, minSpawnWeight = minWeight, maxSpawnWeight = maxWeight or minWeight }
end

// A registry in the same shape as ZM_StaticData's resolved registry.
local function fixtureRegistry()
    return {
        enemies = {
            walker = enemy("walker", 0, 0.75),
            rare = enemy("rare", 0.25, 1),
            mutant = enemy("mutant", 0.5, 1),
            tank = enemy("tank", 0, 1, { boss = true })
        },
        spawnGroups = {
            generic = { id = "generic", enemies = { spawnEntry("walker", 0.75, 0.2), spawnEntry("rare", 0.25, 0.75) } },
            radiation = { id = "radiation", enemies = { spawnEntry("mutant", 1), spawnEntry("walker", 5) } },
            bosses = { id = "bosses", enemies = { spawnEntry("tank", 1) } }
        },
        environmentTags = { radioactive = "radiation", military = "bosses" },
        defaultSpawnGroup = "generic"
    }
end

local function candidateIds(context, registry)
    context.skipEntityCheck = true
    local candidates = Enemies:GetCandidates(context, registry)
    local ids = {}
    for _, candidate in ipairs(candidates) do
        ids[candidate.enemy.id] = candidate.weight
    end
    return ids
end

local function stubKiller()
    return {
        xp = 0, items = {}, messages = {},
        IsValid = function() return true end,
        IsPlayer = function() return true end,
        SteamID = function() return "STEAM_TEST:0:2701" end,
        AddXP = function(self, amount) self.xp = self.xp + amount end,
        GetLevel = function() return 5 end,
        GiveItemInstance = function(self, instance) table.insert(self.items, instance) return true end,
        ChatPrint = function(self, message) table.insert(self.messages, message) end
    }
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("eligibility_follows_danger_bounds", function(check)
    local registry = fixtureRegistry()
    local low = candidateIds({ danger = 0 }, registry)
    check(low.walker and not low.rare, "danger 0: only the walker is eligible")
    local edge = candidateIds({ danger = 0.25 }, registry)
    check(edge.walker and edge.rare, "danger 0.25: minDanger is inclusive")
    local top = candidateIds({ danger = 0.75 }, registry)
    check(top.walker and top.rare, "danger 0.75: maxDanger is inclusive")
    local high = candidateIds({ danger = 0.9 }, registry)
    check(not high.walker and high.rare, "danger 0.9: the walker is past its maxDanger")
end)

test("weights_interpolate_across_each_enemy_range", function(check)
    local registry = fixtureRegistry()
    local weights = candidateIds({ danger = 0 }, registry)
    check(math.abs(weights.walker - 0.75) < 1e-9, "walker weight is minSpawnWeight at its minDanger")
    weights = candidateIds({ danger = 0.75 }, registry)
    check(math.abs(weights.walker - 0.2) < 1e-9, "walker weight is maxSpawnWeight at its maxDanger")
    check(math.abs(weights.rare - (0.25 + 0.5 * 2 / 3)) < 1e-9, "rare is two-thirds through its 0.25-1 range at 0.75")
end)

test("environment_tags_combine_groups_with_default_fallback", function(check)
    local registry = fixtureRegistry()
    local plain = candidateIds({ danger = 0.6, tags = { "grassland" } }, registry)
    check(plain.walker and plain.rare and not plain.mutant, "unmapped tags fall back to the default group")
    local radioactive = candidateIds({ danger = 0.6, tags = { "grassland", "radioactive" } }, registry)
    check(radioactive.mutant and radioactive.walker and not radioactive.rare, "a mapped tag replaces the default group")
    check(math.abs(radioactive.walker - 5) < 1e-9, "the radiation group's walker weight applies")
    local both = candidateIds({ danger = 0.6, tags = { "radioactive", "military" } }, registry)
    check(both.mutant and not both.tank, "bosses in a spawn group are never candidates")
end)

test("no_eligible_enemy_returns_a_reason", function(check)
    local registry = fixtureRegistry()
    registry.defaultSpawnGroup = "bosses"
    local picked, reason = Enemies:Pick({ danger = 0.5, tags = {}, skipEntityCheck = true }, Generation.NewRng(1), registry)
    check(picked == nil, "a group of only bosses has no candidates")
    check(reason and string.find(reason, "no eligible enemy", 1, true), "the reason explains the empty pool")
    registry.defaultSpawnGroup = "generic"
    local lowOnly = fixtureRegistry()
    lowOnly.enemies.walker.maxDanger = 0.1
    lowOnly.enemies.rare.minDanger = 0.9
    check(Enemies:Pick({ danger = 0.5, skipEntityCheck = true }, Generation.NewRng(1), lowOnly) == nil, "a danger between every range has no candidates")
end)

test("unsupported_entities_are_skipped", function(check)
    check(Enemies.SupportsWalkerTickets("zn_walker_zombie"), "zn_walker_zombie supports tickets and definitions")
    check(not Enemies.SupportsWalkerTickets("npc_zombie"), "engine NPCs do not support the ticket interface")
    check(not Enemies.SupportsWalkerTickets("zn_class_that_does_not_exist"), "unknown classes are unsupported")
    local registry = fixtureRegistry()
    registry.enemies.walker.entity = "npc_zombie"
    local candidates = Enemies:GetCandidates({ danger = 0 }, registry)
    check(#candidates == 0, "an enemy with an unsupported entity is not a spawn candidate")
end)

test("hit_markers_only_target_registered_enemies", function(check)
    local victim = ents.Create("zn_walker_zombie")
    check(IsValid(victim), "walker test entity should be created")
    if not IsValid(victim) then return end

    victim:SetPos(Vector(0, 0, -16000))
    victim:Spawn()
    check(not Enemies.IsHitMarkerTarget(victim), "an unregistered walker is not a hit-marker target")
    victim.EnemyId = "walker"
    check(Enemies.IsHitMarkerTarget(victim), "a registered walker is a hit-marker target")
    victim.EnemyId = nil
    victim.BossInstanceId = "boss-test"
    check(Enemies.IsHitMarkerTarget(victim), "a boss instance is a hit-marker target")
    victim:Remove()
end)

test("headshots_kill_walkers_and_scale_boss_damage", function(check)
    local victim = ents.Create("zn_walker_zombie")
    check(IsValid(victim), "walker test entity should be created")
    if not IsValid(victim) then return end
    victim:SetPos(Vector(0, 0, -16000))
    victim:Spawn()
    victim:SetMaxHealth(60)
    victim:SetHealth(60)
    victim.EnemyId = "walker"
    local function bullet(amount, damageType)
        local damage = DamageInfo()
        damage:SetDamage(amount)
        damage:SetDamageType(damageType or DMG_BULLET)
        return damage
    end

    local body = bullet(12)
    check(not Enemies.ApplyHeadshot(victim, body) and body:GetDamage() == 12, "a body shot keeps its damage")
    victim.HeadHitTick = engine.TickCount()
    local head = bullet(12)
    check(Enemies.ApplyHeadshot(victim, head) and head:GetDamage() >= victim:Health(), "a headshot is lethal to a walker")
    local melee = bullet(20, DMG_CLUB)
    check(not Enemies.ApplyHeadshot(victim, melee) and melee:GetDamage() == 20, "melee is not a headshot")
    victim.HeadHitTick = engine.TickCount() - 1
    local stale = bullet(12)
    check(not Enemies.ApplyHeadshot(victim, stale) and stale:GetDamage() == 12, "a head trace from an earlier tick does not count")

    victim.EnemyId = nil
    victim.BossInstanceId = "boss-test"
    victim:SetHealth(600)
    victim.HeadHitTick = engine.TickCount()
    local bossHead = bullet(20)
    check(Enemies.ApplyHeadshot(victim, bossHead) and bossHead:GetDamage() == 20 * Enemies.BossHeadshotScale,
        "a boss headshot is scaled instead of lethal")
    victim:Remove()
end)

test("selection_distribution_and_ticket_repeatability", function(check)
    local registry = fixtureRegistry()
    local rng = Generation.NewRng(7)
    local rare = 0
    for _ = 1, 10000 do
        if Enemies:Pick({ danger = 0.75, skipEntityCheck = true }, rng, registry).id == "rare" then
            rare = rare + 1
        end
    end
    local rareWeight = 0.25 + 0.5 * 2 / 3
    local expected = rareWeight / (rareWeight + 0.2)
    check(math.abs(rare / 10000 - expected) < 0.02, string.format("rare share %.3f should be about %.3f", rare / 10000, expected))

    local ticket = { TicketIdLow = 123456, TicketIdHigh = 7 }
    local first = Enemies:Pick({ danger = 0.5, skipEntityCheck = true }, Generation.NewRng(Enemies.GetTicketSeed(ticket)), registry)
    for _ = 1, 20 do
        local again = Enemies:Pick({ danger = 0.5, skipEntityCheck = true }, Generation.NewRng(Enemies.GetTicketSeed(ticket)), registry)
        check(again.id == first.id, "the same ticket must always select the same enemy")
    end
end)

test("definitions_scale_a_spawned_walker", function(check)
    local definition = enemy("scaled", 0.2, 0.6, { minHealth = 20, maxHealth = 60, minSpeed = 1, maxSpeed = 2 })
    local function spawnWith(danger)
        local zombie = ents.Create("zn_walker_zombie")
        zombie:SetPos(Vector(0, 0, -16000))
        zombie:Spawn()
        zombie:ApplyEnemyDefinition(definition, danger)
        return zombie
    end
    local low, middle, high = spawnWith(0), spawnWith(0.4), spawnWith(1)
    check(low:Health() == 20 and low:GetMaxHealth() == 20, "at or below minDanger health is minHealth, got " .. low:Health())
    check(middle:Health() == 40, "halfway through the range health is halfway, got " .. middle:Health())
    check(high:Health() == 60, "at or above maxDanger health is maxHealth, got " .. high:Health())
    check(math.abs(high.WalkSpeed - high.DevelopmentWalkSpeed * 2) < 1e-6, "maxSpeed multiplies the base walk speed")
    check(middle.EnemyId == "scaled" and math.abs(middle.EnemyDanger - 0.4) < 1e-9, "the entity remembers its enemy and danger")
    for _, zombie in ipairs({ low, middle, high }) do
        zombie:Remove()
    end
end)

test("radiated_variant_chance_tracks_cell_intensity", function(check)
    local definition = enemy("walker", 0, 1)
    check(Enemies.GetRadiatedChance({ radiation = 0 }, definition) == 0, "nonradiated cells have no radiated variants")
    check(Enemies.GetRadiatedChance({ radiation = 0.5 }, definition) == 0.25, "half intensity yields a 25 percent chance")
    check(Enemies.GetRadiatedChance({ radiation = 1 }, definition) == 0.5, "full intensity yields a 50 percent chance")
    check(Enemies.GetRadiatedChance({ radiation = 2 }, definition) == 0.5, "chance is capped at 50 percent")
    check(Enemies.GetRadiatedChance({ radiation = 1 }, enemy("boss", 0, 1, { boss = true })) == 0,
        "ordinary walker variant selection does not alter bosses")
end)

test("radiated_variant_is_repeatable_and_preserves_stats", function(check)
    local zombie = ents.Create("zn_walker_zombie")
    zombie:SetPos(Vector(0, 0, -16000))
    zombie:Spawn()
    local definition = enemy("variant", 0, 1)
    zombie:ApplyEnemyDefinition(definition, 0.5)
    local health, speed = zombie:Health(), zombie.WalkSpeed
    local first = Enemies:ApplyRadiatedVariant(zombie, { radiation = 1 }, definition, Generation.NewRng(123))
    for _ = 1, 20 do
        check(Enemies:ApplyRadiatedVariant(zombie, { radiation = 1 }, definition, Generation.NewRng(123)) == first,
            "the same seed selects the same variant")
    end
    Enemies:ApplyRadiatedVariant(zombie, { radiation = 1 }, definition, { Next = function() return 0.49 end })
    check(zombie:GetNWBool("ZM_Radiated", false) and zombie:GetNWFloat("ZM_RadiatedIntensity", 0) == 1,
        "radiated state and strength are published")
    check(zombie:Health() == health and zombie.WalkSpeed == speed and zombie.EnemyId == definition.id,
        "variant selection preserves health, speed and reward definition")
    Enemies:ApplyRadiatedVariant(zombie, { radiation = 0 }, definition, Generation.NewRng(123))
    check(not zombie:GetNWBool("ZM_Radiated", true) and zombie:GetNWFloat("ZM_RadiatedIntensity", 1) == 0,
        "an ordinary cell clears variant state")
    zombie:Remove()
end)

test("kills_reward_xp_and_place_loot_on_corpse_once", function(check)
    local registry = ZM_StaticData:GetRegistry()
    local original = registry.enemies.testLootEnemy
    registry.enemies.testLootEnemy = enemy("testLootEnemy", 0, 1, {
        xp = 12, minLootDropChance = 1, maxLootDropChance = 1,
        lootEntries = { { item = "itemBandage", minWeight = 1, maxWeight = 1, minCount = 1, maxCount = 1, mastercraft = false, mastercraftChance = 0 } }
    })
    local ok, err = pcall(function()
        local killer = stubKiller()
        local victim = { EnemyId = "testLootEnemy", EnemyDanger = 0.5 }
        local rewarded, reward = Enemies:OnEnemyKilled(victim, killer, { rng = Generation.NewRng(3) })
        check(rewarded and reward.xp == 12, "a player kill should reward the enemy's XP")
        check(killer.xp == 12, "the killer should gain 12 XP, got " .. killer.xp)
        check(reward.item and reward.item.itemId == "itemBandage", "a 100% drop should roll one bandage for the corpse")
        check(#killer.items == 0, "a rolled enemy drop must not be inserted directly into the killer's inventory")
        check(#killer.messages == 0, "a rolled enemy drop must not be awarded through a loot chat message")

        local originalCell = ZM_LootSpots.Cell
        local walker = ents.Create("zn_walker_zombie")
        if IsValid(walker) then
            walker:SetPos(Vector(0, 0, -16000))
            walker:Spawn()
            local expectedModel = walker:GetModel()
            local corpse = walker:CreateCorpse()
            check(IsValid(corpse), "the walker creates an explicit ragdoll entity")
            check(corpse and corpse:GetClass() == "prop_ragdoll" and corpse:GetModel() == expectedModel, "the corpse uses the walker's model")
            check(corpse and corpse:GetCollisionGroup() == COLLISION_GROUP_DEBRIS, "the corpse does not collide with players")
            ZM_LootSpots.Cell = { spots = {}, spotsByEntity = {} }
            local registered, spot = Enemies:RegisterCorpseLoot(corpse, reward.item)
            check(registered, "the rolled enemy item registers on its corpse")
            check(spot and spot.runtime and spot.state == "available", "the corpse is an available runtime loot spot")
            check(spot and spot.item == reward.item and ZM_LootSpots.Cell.spotsByEntity[corpse] == spot, "the runtime spot references the rolled item and corpse")
            walker:ConfigureCorpse(corpse, registered)
            check(not corpse.CorpseFadeScheduled, "lootable corpses do not get a fade timer")

            local unlootableCorpse = walker:CreateCorpse()
            walker:ConfigureCorpse(unlootableCorpse, false)
            check(unlootableCorpse and unlootableCorpse.CorpseFadeScheduled, "corpses without loot are scheduled to fade")
            check(unlootableCorpse and unlootableCorpse:GetCollisionGroup() == COLLISION_GROUP_DEBRIS, "unlootable corpses also do not collide with players")
            if IsValid(unlootableCorpse) then unlootableCorpse:Remove() end
            if IsValid(corpse) then corpse:Remove() end
            if IsValid(walker) then walker:Remove() end
        else
            check(false, "a walker fixture can be created")
        end
        ZM_LootSpots.Cell = originalCell

        local again, reason = Enemies:OnEnemyKilled(victim, killer, { rng = Generation.NewRng(3) })
        check(not again and reason == "already rewarded", "a duplicate death callback must not reward again")
        check(killer.xp == 12 and #killer.items == 0, "the duplicate must not add XP or inventory items")

        local worldKill = { EnemyId = "testLootEnemy", EnemyDanger = 0.5 }
        local worldRewarded = Enemies:OnEnemyKilled(worldKill, game.GetWorld())
        check(not worldRewarded, "a non-player kill gives no reward")
        check(Enemies:OnEnemyKilled({}, killer) == false, "an entity without an enemy definition gives no reward")
    end)
    registry.enemies.testLootEnemy = original
    check(ok, "error: " .. tostring(err))
end)

test("despawns_and_bad_cells_never_reward_or_spawn", function(check)
    local zombie = ents.Create("zn_walker_zombie")
    zombie:SetPos(Vector(0, 0, -16000))
    zombie:Spawn()
    zombie:ApplyEnemyDefinition(enemy("despawned", 0, 1), 0.5)
    zombie:Remove()
    check(zombie.EnemyRewarded == nil, "removing (despawning) an enemy must not reward anyone")

    local before = #ents.FindByClass("zn_walker_zombie")
    local spawned, reason = ZM_WalkerSim:SpawnTicketZombie({ TicketIdLow = 1, TicketIdHigh = 1 }, -99999)
    check(spawned == nil and reason and string.find(reason, "unknown cell", 1, true), "an unknown cell is rejected before any entity is created")
    check(#ents.FindByClass("zn_walker_zombie") == before, "a rejected spawn must not leave an entity behind")
end)

test("live_registry_selects_shipped_enemies", function(check)
    local rng = Generation.NewRng(11)
    local seen = {}
    for _ = 1, 500 do
        local picked = Enemies:Pick({ danger = 0.5, tags = { "grassland" } }, rng)
        check(picked ~= nil, "the shipped spawn groups should always have a candidate at danger 0.5")
        if picked then
            seen[picked.id] = true
        end
    end
    check(seen.entityWalker and seen.entityRareWalker, "both shipped walkers should be selected at danger 0.5")
    local only = Enemies:Pick({ danger = 0.1 }, rng)
    check(only and only.id == "entityWalker", "below the rare walker's minDanger only the walker spawns")
end)

function Enemies:RunTests()
    local summary = suite:Run()
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_enemies", label = "Enemy", file = "enemy_tests.json", report = "enemyTests",
    help = "Runs the enemy selection, scaling, and kill-reward tests.",
    run = function() return Enemies:RunTests() end
})
