local Movement = ZM_Movement
local suite = ZM_TestHarness.NewSuite()
local function near(a, b) return math.abs(a - b) < 0.00001 end
local function target(walk, run)
    return {
        walk = walk, run = run,
        GetWalkSpeed = function(self) return self.walk end,
        GetRunSpeed = function(self) return self.run end,
        SetWalkSpeed = function(self, value) self.walk = value end,
        SetRunSpeed = function(self, value) self.run = value end
    }
end

suite:Add("walk_and_sprint_scale_once_and_preserve_implant_bonuses", function(check)
    local user = target(200, 400)
    Movement.Apply(user, 0)
    check(near(user.walk, 114.75) and near(user.run, 260.1), "walk uses 0.57375 and sprint uses 0.65025")
    for _ = 1, 10 do Movement.Apply(user, 0) end
    check(near(user.walk, 114.75) and near(user.run, 260.1), "repeated refresh does not compound reductions")
    Movement.Apply(user, 0.2)
    check(near(user.walk, 137.7) and near(user.run, 312.12), "implant bonuses apply to the balanced speeds")
    Movement.Apply(user, 0)
    check(near(user.walk, 114.75) and near(user.run, 260.1), "implant removal restores balanced speeds")
    user.walk, user.run = 200, 400
    Movement.Apply(user, 0.2)
    check(near(user.walk, 137.7) and near(user.run, 312.12), "engine spawn speed reset is balanced once")
    user.walk, user.run = 150, 300
    Movement.Apply(user, 0)
    check(near(user.walk, 86.0625) and near(user.run, 195.075), "external base speeds retain the same percentage policy")
    user.walk = 100
    Movement.Apply(user, 0)
    check(near(user.walk, 57.375) and near(user.run, 195.075), "a walk-only reset cannot compound the unchanged sprint speed")
end)

suite:Add("stamina_rates_match_exact_old_to_new_percentages_at_all_stats", function(check)
    for _, stats in ipairs({ { 0, 0 }, { 5, 5 }, { 25, 40 }, { 100, 100 } }) do
        local agility, strength = stats[1], stats[2]
        local drain, recovery = Movement.Rates(agility, strength)
        local oldDrain = 60 / (1 + agility * 0.05 + strength * 0.03)
        local oldRecovery = 5 * (1 + agility * 0.05)
        check(near(drain, oldDrain * 0.5), "sprint cost is exactly half the previous rate")
        check(near(recovery, oldRecovery * 1.10), "recovery is exactly 10 percent higher")
        check(near(100 / drain, (100 / oldDrain) * 2), "equal stamina lasts twice as long")
        check(near(100 / recovery, (100 / oldRecovery) / 1.10), "recovery duration matches the requested rate")
    end
end)

suite:Add("sustained_interrupted_and_exhausted_sprint_are_bounded", function(check)
    local stamina = 100
    for _ = 1, 100 do stamina = Movement.Step(stamina, 100, true, 0, 0, 0.01) end
    check(near(stamina, 70), "one second of sustained sprint consumes 30 stamina")
    stamina = Movement.Step(stamina, 100, false, 0, 0, 1)
    check(near(stamina, 75.5), "releasing sprint immediately restores 5.5 per second")
    check(Movement.Step(stamina, 100, true, 0, 0, 10) == 0, "exhaustion cannot become negative")
    check(Movement.Step(0, 100, true, 0, 0, 1) == 0, "held sprint stays exhausted")
    check(near(Movement.Step(0, 100, false, 0, 0, 1), 5.5), "released exhausted sprint recovers")
    check(Movement.Step(99, 100, false, 0, 0, 10) == 100, "recovery cannot exceed capacity")
    check(Movement.Step(45, 100, true, 0, 0, 0) == 45, "zero elapsed time cannot consume stamina")
end)

suite:Add("exhaustion_caps_server_move_without_removing_other_buttons", function(check)
    local user = target(180, 340)
    user.ZM_PersistentStateLoaded, user.Stamina = true, 0
    local move = {
        buttons = bit.bor(IN_SPEED, IN_FORWARD, IN_ATTACK),
        GetButtons = function(self) return self.buttons end,
        SetButtons = function(self, value) self.buttons = value end,
        SetMaxSpeed = function(self, value) self.maximum = value end,
        SetMaxClientSpeed = function(self, value) self.clientMaximum = value end
    }
    Movement.RestrictExhausted(user, move)
    check(move.maximum == 180 and move.clientMaximum == 180, "exhaustion uses the balanced walking limit")
    check(move.buttons == bit.bor(IN_FORWARD, IN_ATTACK), "forward and combat inputs remain intact")
    move.maximum, move.clientMaximum = nil, nil
    move.buttons = bit.bor(IN_SPEED, IN_FORWARD)
    user.Stamina = 1
    Movement.RestrictExhausted(user, move)
    check(move.maximum == nil and bit.band(move.buttons, IN_SPEED) ~= 0, "positive stamina allows sprint")
    user.Stamina, user.ZM_PersistentStateLoaded = 0, false
    Movement.RestrictExhausted(user, move)
    check(move.maximum == nil, "unloaded state is not treated as an exhausted survivor")
end)

suite:Add("armour_penalties_are_endurance_mitigated_without_compounding", function(check)
    local inventory = { equipped = { [ZM_Items.ArmourSlot] = { itemId = "itemHeavyArmour" } } }
    local untrained = ZM_Items:GetArmourEffects(inventory, 0)
    local trained = ZM_Items:GetArmourEffects(inventory, 10)
    check(near(untrained.damageReduction, 0.35), "heavy damage reduction is unchanged by Endurance")
    check(near(untrained.speedPenalty, 0.12) and near(untrained.staminaRegenPenalty, 0.3),
        "heavy penalties match their authored values")
    check(near(trained.speedPenalty, 0.06) and near(trained.staminaRegenPenalty, 0.15),
        "ten Endurance removes half of each movement and recovery penalty")
    local user = target(200, 400)
    user.ZM_Inventory, user.GetStat = inventory, function() return 0 end
    Movement.Apply(user, 0)
    check(near(user.walk, 100.98) and near(user.run, 228.888), "armour scales balanced base speeds")
    for _ = 1, 10 do Movement.Apply(user, 0) end
    check(near(user.walk, 100.98) and near(user.run, 228.888), "armour refreshes do not compound")
    local _, recovery = Movement.Rates(0, 0, 1 - untrained.staminaRegenPenalty)
    check(near(recovery, 3.85), "heavy armour reduces stamina recovery by 30 percent")
end)

suite:Add("deployed_players_use_balanced_runtime_speeds_and_rates", function(check)
    for _, user in ipairs(player.GetAll()) do
        if user.ZM_PersistentStateLoaded == true and user.ZM_Modifiers then
            local state = Movement.Snapshot(user)
            local scale = (1 + state.moveSpeedBonus) * (1 - state.armour.speedPenalty)
            check(state.baseWalkSpeed ~= nil and near(state.walkSpeed, state.baseWalkSpeed * 0.57375 * scale),
                "actual player walk speed matches the captured base and modifiers")
            check(state.baseRunSpeed ~= nil and near(state.runSpeed, state.baseRunSpeed * 0.65025 * scale),
                "actual player run speed matches the captured base and modifiers")
            check(near(state.sprintDrain, 30 / (1 + state.agility * 0.05 + state.strength * 0.03)),
                "actual stat-derived drain matches the authoritative rate")
            check(near(state.recovery,
                5.5 * (1 + state.agility * 0.05) * (1 - state.armour.staminaRegenPenalty)),
                "actual stat-derived recovery matches the authoritative rate")
        end
    end
end)

ZM_TestHarness.Register({
    command = "zn_test_movement", label = "Movement", file = "movement_tests.json", report = "movementTests",
    help = "Validates movement percentages, implant refresh, stamina drain/recovery and exhaustion.",
    run = function() return suite:Run() end
})
