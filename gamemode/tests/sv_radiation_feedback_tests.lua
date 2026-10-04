local Feedback = ZM_RadiationFeedback
local suite = ZM_TestHarness.NewSuite()

suite:Add("proximity_is_bounded_and_falls_off_with_distance", function(check)
    check(Feedback.Proximity(0, 1) == 1, "full intensity at source")
    check(Feedback.Proximity(300, 1) == 0.25, "quadratic falloff at half radius")
    check(Feedback.Proximity(600, 1) == 0 and Feedback.Proximity(900, 1) == 0, "outside radius is silent")
    check(Feedback.Proximity(-10, 2) == 1, "inputs cannot exceed full warning")
    check(Feedback.Proximity(0, 0) == 0, "ordinary source has no warning")
end)

suite:Add("sensory_uses_strongest_channel_without_addition", function(check)
    check(Feedback.SensoryIntensity(0, 0) == 0, "no exposure is quiet")
    check(Feedback.SensoryIntensity(0.05, 0.05) == 0, "low exposure stays quiet")
    check(Feedback.SensoryIntensity(0.5, 0.5) == Feedback.SensoryIntensity(0.5, 0), "channels do not stack")
    check(Feedback.SensoryIntensity(0, 1) == 1, "proximity independently reaches full warning")
    check(Feedback.ClickInterval(1) == 0.125 and Feedback.ClickInterval(0) == 1.6, "click cadence is bounded")
end)

suite:Add("meter_adds_cosmetic_proximity_without_changing_cell_channel", function(check)
    check(Feedback.DisplaySv(0.4, 0) == 4, "cell remains the baseline without nearby radiated zombies")
    check(Feedback.DisplaySv(0.4, 0.5) == 9, "proximity adds to the same meter")
    check(Feedback.DisplaySv(1, 1) == 20, "combined cosmetic readout reaches 20 Sv")
    check(Feedback.DisplaySv(2, 2) == 20 and Feedback.DisplaySv(-1, -1) == 0, "display is bounded")
    check(Feedback.SensoryIntensity(0.5, 0.5) < 1, "display sum is not the damaging or sensory exposure")
end)

suite:Add("geiger_cadence_is_irregular_bounded_and_fades_with_exposure", function(check)
    check(Feedback.ClickDelay(0.5, 0.2) > Feedback.ClickDelay(0.5, 0.8), "random samples vary the cadence")
    check(Feedback.ClickDelay(1, 0.5) < Feedback.ClickDelay(0.1, 0.5), "higher exposure clicks faster")
    check(Feedback.ClickDelay(1, 1) == 0.06 and Feedback.ClickDelay(0, 0) == 4, "no unbounded click burst or silence")
    check(Feedback.AudioGain(0) == 0 and Feedback.AudioGain(1) == 1, "audio fades between silence and configured volume")
    check(Feedback.AudioGain(0.01) < Feedback.AudioGain(0.5), "low exposure remains softer")
end)

suite:Add("extreme_threshold_preserves_ambient_damage_and_suit_immunity", function(check)
    local damage, interval, acute = Feedback.DamagePolicy(1, 0.5, false)
    check(damage == 2 and interval == 60 and not acute, "exactly 15 Sv retains the old ambient policy")
    damage, interval, acute = Feedback.DamagePolicy(1, 0.5001, false)
    check(damage == 1 and interval == 2 and acute, "strictly above 15 Sv enters potentially lethal exposure")
    damage, interval, acute = Feedback.DamagePolicy(0.5, 0, false)
    check(damage == 1 and interval == 120 and not acute, "lower cell radiation retains its slow damage")
    damage, interval = Feedback.DamagePolicy(1, 1, true)
    check(damage == 0 and interval == 0, "protective armour blocks acute damage")
    check(Feedback.ExtremeSeverity(1, 0.5, false) == 0, "normal radiation causes no extreme screen effects")
    check(Feedback.ExtremeSeverity(1, 1, false) == 1, "20 Sv reaches full extreme effects")
    check(Feedback.ExtremeSeverity(1, 1, true) == 0, "protective armour suppresses extreme screen effects")
end)

suite:Add("acute_damage_ticks_reset_and_bypass_only_the_ambient_health_floor", function(check)
    local target = {
        ZM_PersistentStateLoaded = true, hp = 12, intensity = 1, proximity = 1, protected = false,
        Alive = function(self) return self.hp > 0 end,
        HasRadiationProtection = function(self) return self.protected end,
        GetWorldCell = function() return { id = 123 } end,
        GetRadiationIntensity = function(self) return self.intensity end,
        GetNWFloat = function(self) return self.proximity end,
        SetNWFloat = function() end,
        GetRadiationHealthFloor = function() return 80 end,
        Health = function(self) return self.hp end,
        TakeDamageInfo = function(self, info) self.hp = self.hp - info:GetDamage() end
    }
    check(not Feedback:TickDamage(target, 0), "entry schedules damage rather than dealing it immediately")
    check(not Feedback:TickDamage(target, 1.999) and target.hp == 12, "no damage before two seconds")
    check(Feedback:TickDamage(target, 2) and target.hp == 11, "one HP is dealt below the old health floor")
    check(Feedback:TickDamage(target, 10) and target.hp == 10, "no catch-up burst after a stalled update")
    target.protected = true
    check(not Feedback:TickDamage(target, 12) and target.RadiationNextDamageAt == nil, "equipping protection cancels exposure")
    target.protected = false
    target.hp = 1
    check(not Feedback:TickDamage(target, 20) and Feedback:TickDamage(target, 22) and target.hp == 0, "acute damage can kill")
    target.hp, target.proximity = 12, 0
    check(not Feedback:TickDamage(target, 30), "leaving acute exposure resets the ambient timer")
    check(not Feedback:TickDamage(target, 90) and target.hp == 12, "ambient damage still respects its health floor")
    target.CurrentSafeZoneId = "test-den"
    check(not Feedback:TickDamage(target, 91) and target.RadiationNextDamageAt == nil, "den entry clears exposure")
end)

suite:Add("worn_armour_blocks_radiation_damage_hooks_but_not_other_damage", function(check)
    local callback = hook.GetTable().EntityTakeDamage["ZM.RadiationFeedback.ArmourProtection"]
    local target = { IsPlayer = function() return true end, HasRadiationProtection = function() return true end }
    local info = DamageInfo()
    info:SetDamageType(DMG_RADIATION)
    check(callback(target, info) == true, "radiation damage is blocked")
    info:SetDamageType(DMG_BULLET)
    check(callback(target, info) == nil, "suit is not immunity to ordinary damage")
end)

suite:Add("corners_scale_with_combined_exposure_and_symbol_remains_bounded", function(check)
    check(Feedback.CornerIntensity(0, 0, false) == 0, "clean air has no corner effect")
    check(Feedback.CornerIntensity(0.05, 0.05, false) == 0, "low exposure stays unobtrusive")
    check(Feedback.CornerIntensity(1, 1, false) == 1, "20 Sv reaches full corner strength")
    check(Feedback.CornerIntensity(0.5, 0.5, false) > Feedback.CornerIntensity(0.5, 0, false), "proximity increases the corner warning")
    check(Feedback.CornerIntensity(1, 1, true) == 0, "wearing a suit suppresses all corner effects")
    check(Feedback.WarningIntensity(1, 1) == 1, "the warning remains available while protected")
    check(Feedback.SymbolFrequency(0) == 0.2 and Feedback.SymbolFrequency(1) == 1.5, "flashes are slow and bounded")
    check(Feedback.SymbolFrequency(0.8) > Feedback.SymbolFrequency(0.2), "higher exposure increases flash frequency")
end)

suite:Add("corner_mask_has_transparent_square_edges_and_smooth_radial_falloff", function(check)
    check(Feedback.CornerMaskAlpha(1, 0) == 0 and Feedback.CornerMaskAlpha(1, 1) == 0, "quad boundaries must be fully transparent")
    check(Feedback.CornerMaskAlpha(0, 0) > Feedback.CornerMaskAlpha(0.5, 0), "corner center fades inward")
    check(Feedback.CornerMaskAlpha(0.5, 0) > Feedback.CornerMaskAlpha(0.9, 0), "feather approaches zero at the edge")
    for y = -8, 8 do
        for x = -8, 8 do
            local alpha = Feedback.CornerMaskAlpha(x / 8, y / 8)
            check(alpha >= 0 and alpha <= 1, "all mask samples stay in alpha range")
        end
    end
end)

suite:Add("only_living_radiated_sources_warn_and_groups_do_not_stack", function(check)
    local sources = {}
    for index = 1, 2 do
        local entity = ents.Create("zn_walker_zombie")
        entity:SetPos(Vector(index * 10, 0, -16000))
        entity:Spawn()
        entity:SetNWBool("ZM_Radiated", true)
        entity:SetNWFloat("ZM_RadiatedIntensity", 1)
        sources[index] = entity
    end
    local position = sources[1]:WorldSpaceCenter()
    check(Feedback.FindStrongest(position, sources) == 1, "nearby sources do not sum")
    sources[1]:SetHealth(0)
    sources[2]:SetNWBool("ZM_Radiated", false)
    check(Feedback.FindStrongest(position, sources) == 0, "dead or ordinary sources are excluded")
    for _, entity in ipairs(sources) do entity:Remove() end
    check(Feedback.FindStrongest(position, sources) == 0, "removed sources are excluded")
end)

ZM_TestHarness.Register({
    command = "zn_test_radiation_feedback", label = "Radiation feedback", file = "radiation_feedback_tests.json",
    report = "radiationFeedbackTests", help = "Test radiation warning bounds, falloff and source selection.",
    run = function() return suite:Run() end
})
