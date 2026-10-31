return function(api)
    local lastOwned, lastFixture
    local enemyId = "zz_dev_prefab_guard_kill"

    local function allowed()
        local humans = api.player.GetHumans()
        return api.game.GetMap() == "zn_preview_start" and api.World.ActiveProfile == "preview"
            and #humans == 1 and api.IsValid(humans[1]) and humans[1]:IsAdmin()
            and humans[1].ZM_PersistentStateLoaded ~= true
    end

    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_kill",
        label = "Prefab guard kill",
        file = "prefab-guard-kill-tests.json",
        report = "prefab_guard_kill_tests",
        help = "Tests one isolated guard shot and corpse reward in the preview launcher.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("a guard shot produces a lootable corpse without player XP", function(check)
                if not allowed() then
                    check(false, "One preview-launcher admin and no loaded survivor are required.")
                    return
                end
                if api.LootSpots.Cell ~= nil then
                    check(false, "The launcher must not have an active loot cell.")
                    return
                end
                for _, entity in ipairs(lastOwned or {}) do
                    if api.IsValid(entity) then
                        check(false, "The previous fixture entities are still being removed.")
                        return
                    end
                end
                local registry = api.StaticData:GetRegistry()
                if type(registry) ~= "table" or type(registry.enemies) ~= "table"
                    or registry.enemies[enemyId] ~= nil then
                    check(false, "The temporary enemy registry slot is unavailable.")
                    return
                end

                local fixtureCell = { spots = {}, spotsByEntity = {} }
                local definition = {
                    id = enemyId, entity = "zn_walker_zombie", minDanger = 0, maxDanger = 1, boss = false,
                    minHealth = 10, maxHealth = 30, minSpeed = 1, maxSpeed = 2, xp = 12,
                    minLootDropChance = 1, maxLootDropChance = 1,
                    lootEntries = { { item = "itemBandage", minWeight = 1, maxWeight = 1, minCount = 1,
                        maxCount = 1, mastercraft = false, mastercraftChance = 0 } }
                }
                local observed = {}
                lastOwned = {}
                lastFixture = { cell = fixtureCell, registry = registry, definition = definition }
                local function create(class)
                    local entity = api.ents.Create(class)
                    if not api.IsValid(entity) then error("Could not create " .. class .. ".") end
                    lastOwned[#lastOwned + 1] = entity
                    return entity
                end
                local ok, problem = pcall(function()
                    local guard = create("zn_prefab_guard")
                    guard.ZM_GuardConfig = {
                        name = "Guard kill fixture", model = "models/player/group01/male_03.mdl",
                        idle = "idle_all_01", weapon = "pistol", range = 512, shirt = "", pants = "",
                        damage = 23, fireInterval = 0.2, spread = 0
                    }
                    guard:SetPos(api.Vector(-160, 0, -16000))
                    guard:SetAngles(api.Angle(0, 0, 0))
                    guard:SetNoDraw(true)
                    guard:Spawn()
                    if not api.IsValid(guard) or not guard.ZM_GuardConfig
                        or type(guard.ZM_GuardConfig.weapon) ~= "table" then
                        error("The temporary guard did not initialize its weapon settings.")
                    end

                    local walker = create("zn_walker_zombie")
                    walker:SetPos(api.Vector(160, 0, -16000))
                    walker:SetNoDraw(true)
                    walker:Spawn()
                    if not api.IsValid(walker) then error("The temporary Walker did not spawn.") end
                    walker.IsValidTarget = function() return false end
                    walker.RunBehaviour = function() end
                    walker:SetMaxHealth(10000)
                    walker:SetHealth(1)
                    walker.EnemyId, walker.EnemyDanger = enemyId, 0.5
                    local createCorpse, configureCorpse = walker.CreateCorpse, walker.ConfigureCorpse
                    walker.CreateCorpse = function(subject)
                        local corpse = createCorpse(subject)
                        if api.IsValid(corpse) then lastOwned[#lastOwned + 1] = corpse end
                        return corpse
                    end
                    walker.ConfigureCorpse = function(subject, corpse, lootable)
                        observed.reward, observed.corpse, observed.lootable = subject.EnemyReward, corpse, lootable
                        return configureCorpse(subject, corpse, lootable)
                    end

                    registry.enemies[enemyId], api.LootSpots.Cell = definition, fixtureCell
                    local fired, reason = api.Targeting.Fire(guard, guard:GetPos() + api.Vector(0, 0, 36),
                        walker, 512, guard.ZM_GuardConfig.weapon)
                    check(fired, "The real guard fires at the temporary Walker: " .. tostring(reason or ""))
                    local reward, corpse = observed.reward, observed.corpse
                    check(walker.WalkerDead == true and type(reward) == "table" and reward.xp == 0
                        and reward.killer == nil and reward.item and reward.item.itemId == "itemBandage",
                        "The guard kill rolls the fixture drop without assigning player XP (health "
                            .. tostring(walker:Health()) .. ", dead " .. tostring(walker.WalkerDead) .. ").")
                    local spot = corpse and fixtureCell.spotsByEntity[corpse] or nil
                    check(api.IsValid(corpse) and observed.lootable == true and spot and spot.runtime
                        and spot.state == "available" and reward and spot.item == reward.item,
                        "The actual corpse is registered as an available runtime loot spot.")
                    if walker.EnemyRewarded then
                        local repeated, repeatError = api.Enemies:OnEnemyKilled(walker, guard)
                        check(not repeated and repeatError == "already rewarded", "A repeated death cannot grant another reward.")
                    else
                        check(false, "The Walker never reached its enemy-reward callback.")
                    end
                end)
                if api.LootSpots.Cell == fixtureCell then
                    api.LootSpots.Cell = nil
                elseif api.LootSpots.Cell ~= nil then
                    check(false, "The active loot cell changed during the fixture; it was not overwritten.")
                end
                if registry.enemies[enemyId] == definition then
                    registry.enemies[enemyId] = nil
                elseif registry.enemies[enemyId] ~= nil then
                    check(false, "The temporary enemy slot changed during the fixture; it was not overwritten.")
                end
                for _, entity in ipairs(lastOwned) do if api.IsValid(entity) then entity:Remove() end end
                check(ok, "Guard kill fixture failed: " .. tostring(problem or ""))
            end)
            return suite:Run()
        end
    })

    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_kill_cleanup",
        label = "Prefab guard kill cleanup",
        file = "prefab-guard-kill-cleanup-tests.json",
        report = "prefab_guard_kill_cleanup_tests",
        help = "Verifies the guard kill fixture restored its temporary state and entities.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("temporary guard kill state is removed", function(check)
                check(lastOwned ~= nil and #lastOwned > 0 and lastFixture ~= nil, "The guard kill fixture has run.")
                for _, entity in ipairs(lastOwned or {}) do check(not api.IsValid(entity), "A fixture entity remains.") end
                if lastFixture then
                    check(api.LootSpots.Cell ~= lastFixture.cell, "The temporary loot cell is no longer active.")
                    check(lastFixture.registry.enemies[enemyId] ~= lastFixture.definition,
                        "The temporary enemy definition is no longer registered.")
                end
            end)
            return suite:Run()
        end
    })
end
