local Armour = ZM_Armour
local Items = ZM_Items
local suite = ZM_TestHarness.NewSuite()

suite:Add("armour_damage_reduction_and_radiation_are_separate", function(check)
    local inventory = { equipped = { [Items.ArmourSlot] = { itemId = "itemHeavyArmour" } } }
    check(math.abs(Armour:GetDamageMultiplier(inventory, 0, false) - 0.65) < 0.00001,
        "heavy armour reduces ordinary damage by 35 percent")
    check(Armour:GetDamageMultiplier(inventory, 0, true) == 1,
        "ordinary armour does not reduce radiation damage")
    check(Armour:GetDamageMultiplier({ equipped = {} }, 0, false) == 1,
        "unarmoured damage is unchanged")
end)

suite:Add("armour_endurance_reduces_mobility_penalties_only", function(check)
    local inventory = { equipped = { [Items.ArmourSlot] = { itemId = "itemHeavyArmour" } } }
    local baseline = Items:GetArmourEffects(inventory, 0)
    local maximumEndurance = Items:GetArmourEffects(inventory, 100)
    check(math.abs(baseline.speedPenalty - 0.12) < 0.00001, "heavy armour applies its authored speed penalty")
    check(math.abs(baseline.staminaRegenPenalty - 0.3) < 0.00001, "heavy armour applies its authored recovery penalty")
    check(math.abs(maximumEndurance.speedPenalty - 0.06) < 0.00001, "endurance removes at most half the speed penalty")
    check(math.abs(maximumEndurance.staminaRegenPenalty - 0.15) < 0.00001,
        "endurance removes at most half the recovery penalty")
    check(maximumEndurance.damageReduction == baseline.damageReduction, "endurance does not alter damage reduction")
end)

suite:Add("armour_tiers_match_the_approved_profile", function(check)
    local expected = {
        itemLightArmour = { damageReduction = 0.1, speedPenalty = 0, staminaRegenPenalty = 0.05 },
        itemMediumArmour = { damageReduction = 0.2, speedPenalty = 0.05, staminaRegenPenalty = 0.15 },
        itemHeavyArmour = { damageReduction = 0.35, speedPenalty = 0.12, staminaRegenPenalty = 0.3 }
    }
    for itemId, values in pairs(expected) do
        local definition = Items:GetDefinition(itemId)
        local stats = definition and definition.armourStats or {}
        for field, value in pairs(values) do
            check(math.abs((tonumber(stats[field]) or -1) - value) < 0.00001,
                itemId .. " " .. field .. " must match the approved value")
        end
    end
end)

suite:Add("damage_application_is_player_only_and_keeps_radiation_separate", function(check)
    local inventory = { equipped = { [Items.ArmourSlot] = { itemId = "itemHeavyArmour" } } }
    local target = {
        ZM_Inventory = inventory,
        IsPlayer = function() return true end,
        GetStat = function() return 0 end
    }
    local function makeDamage(radiation)
        return {
            amount = 100,
            GetDamage = function(self) return self.amount end,
            SetDamage = function(self, amount) self.amount = amount end,
            IsDamageType = function(_, damageType) return radiation and damageType == DMG_RADIATION end
        }
    end
    local ordinary = makeDamage(false)
    Armour:ApplyDamage(target, ordinary)
    check(math.abs(ordinary.amount - 65) < 0.00001, "armour reduces player combat damage")
    local radiation = makeDamage(true)
    Armour:ApplyDamage(target, radiation)
    check(radiation.amount == 100, "ordinary armour leaves radiation damage unchanged")
    local nonPlayer = makeDamage(false)
    target.IsPlayer = function() return false end
    Armour:ApplyDamage(target, nonPlayer)
    check(nonPlayer.amount == 100, "armour does not alter NPC or world damage")
end)

ZM_TestHarness.Register({
    command = "zn_test_armour",
    label = "Armour",
    file = "armourTests.json",
    report = "armourTests",
    help = "Validates armour tiers, damage reduction, radiation separation, and Endurance mobility effects.",
    run = function() return suite:Run() end
})
