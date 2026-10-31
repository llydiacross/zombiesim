return function(state)
    local suite = ZM_TestHarness.NewSuite()

    suite:Add("guard loot uses the normal chance and danger-based item level", function(check)
        local guard = state.guard()
        for _, case in ipairs({ { 0, 10 }, { 0.5, 20 }, { 1, 30 } }) do
            local victim = { EnemyId = "fixture", EnemyDanger = case[1] }
            local ok, reward = ZM_Enemies:OnEnemyKilled(victim, guard, { rng = ZM_ItemGeneration.NewRng(5) })
            check(ok and reward.xp == 0 and reward.killer == nil and reward.item and reward.item.level == case[2],
                "danger " .. case[1] .. " produces level " .. case[2] .. " without XP")
            check(not ZM_Enemies:OnEnemyKilled(victim, guard), "a guard kill is rewarded only once")
        end
        local victim = { EnemyId = "no_drop", EnemyDanger = 0.5 }
        local ok, reward = ZM_Enemies:OnEnemyKilled(victim, guard, { rng = ZM_ItemGeneration.NewRng(5) })
        check(ok and reward.item == nil and reward.xp == 0, "a zero drop chance is not guaranteed")
        check(state.xp == 0 and state.bonusCalls == 0, "guard kills do not use player XP or implant bonuses")
    end)

    suite:Add("player and other non-player rewards remain separate", function(check)
        local player = state.player()
        local ok, reward = ZM_Enemies:OnEnemyKilled({ EnemyId = "fixture", EnemyDanger = 0 }, player,
            { rng = ZM_ItemGeneration.NewRng(5) })
        check(ok and reward.xp == 12 and player.xp == 12 and reward.item.level == 15
            and state.bonusCalls == 1, "player kills keep player-level XP and implant handling")
        local other = state.other()
        check(not ZM_Enemies:OnEnemyKilled({ EnemyId = "fixture", EnemyDanger = 1 }, other),
            "other non-player killers do not gain guard rewards")
    end)

    suite:Add("guard boss kills preserve guaranteed maximum-level loot and cleanup", function(check)
        local victim = { BossId = "fixture_boss", BossInstanceId = 123, BossProfile = "preview", EnemyDanger = 0.2 }
        local ok, reward = ZM_Bosses:OnBossKilled(victim, state.guard())
        check(ok and reward.xp == 0 and reward.killer == nil and reward.item and reward.item.level == 30,
            "guard boss kills retain maximum-level boss loot without player XP")
        check(state.finished == 123 and state.finishedProfile == "preview", "boss lifecycle finishes")
        check(not ZM_Bosses:OnBossKilled(victim, state.guard()), "boss rewards are idempotent")
    end)

    return suite
end
