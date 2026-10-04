local Feedback = ZM_DamageFeedback
local suite = ZM_TestHarness.NewSuite()

suite:Add("direction_prefers_attacker_then_inflictor_then_hit_position", function(check)
    local victim = Vector(1000, 1000, 64)
    local attacker = Vector(1200, 1000, 64)
    local inflictor = Vector(1000, 1300, 64)
    local impact = Vector(900, 900, 64)
    check(Feedback.SelectSource(victim, attacker, inflictor, impact) == attacker,
        "attacker position is the primary bearing")
    check(Feedback.SelectSource(victim, nil, inflictor, impact) == inflictor,
        "inflictor position is used when attacker has no position")
    check(Feedback.SelectSource(victim, nil, nil, impact) == impact,
        "a remote impact position is the final directional fallback")
end)

suite:Add("unreliable_damage_positions_are_not_directional", function(check)
    local victim = Vector(1000, 1000, 64)
    check(Feedback.SelectSource(victim, nil, nil, nil) == nil, "missing source falls back to undirected feedback")
    check(Feedback.SelectSource(victim, nil, nil, Vector(1001, 1000, 64)) == nil,
        "impact points close to the player do not invent a bearing")
    check(Feedback.SelectSource(victim, nil, nil, Vector(0, 0, 0)) == nil,
        "the default world origin is not treated as a source")
    check(Feedback.SelectSource(victim, nil, nil, Vector(1000, 1000, 1200)) == nil,
        "purely vertical sources do not produce an unstable screen direction")
    check(Feedback.SelectSource(victim, nil, nil, Vector(20000, 1000, 64)) == nil,
        "distant positions beyond the local feedback range are ignored")
end)

suite:Add("damage_intensity_is_monotonic_bounded_and_ignores_zero", function(check)
    local small = Feedback.Intensity(1)
    local medium = Feedback.Intensity(10)
    local large = Feedback.Intensity(25)
    check(Feedback.Intensity(-1) == 0 and Feedback.Intensity(0) == 0,
        "zero or negative damage creates no feedback intensity")
    check(small > 0 and medium > small and large > medium,
        "indicator intensity increases with damage")
    check(Feedback.Intensity(1000) == 1, "large damage is capped at full intensity")
end)

ZM_TestHarness.Register({
    command = "zn_test_damage_feedback",
    label = "Damage feedback",
    file = "damage_feedback_tests.json",
    report = "damage_feedback",
    help = "Run focused directional damage-feedback tests.",
    run = function()
        return suite:Run()
    end
})
