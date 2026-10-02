// Server-side tests for dismemberment decisions, crawler conversion, and corpse transfer.
local Gore = ZM_Gore

local function spawnZombie(class)
    local zombie = ents.Create(class or "zn_walker_zombie")
    if not IsValid(zombie) then
        return nil
    end
    zombie:SetPos(Vector(0, 0, -16000))
    zombie:Spawn()
    zombie:SetMaxHealth(100)
    zombie:SetHealth(100)
    return zombie
end

local function forceRegion(zombie, region)
    zombie.GoreTraceTick = engine.TickCount()
    zombie.GoreTraceDamage = { [region] = 1 }
    zombie.GoreTraceHitPos = zombie:WorldSpaceCenter()
end

local function damageOf(amount, damageType)
    local damage = DamageInfo()
    damage:SetDamage(amount)
    damage:SetDamageType(damageType or DMG_SLASH)
    damage:SetAttacker(game.GetWorld())
    damage:SetInflictor(game.GetWorld())
    return damage
end

local function always()
    return 0
end

local function remove(...)
    for _, entity in ipairs({ ... }) do
        if IsValid(entity) then
            entity:Remove()
        end
    end
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

test("hitgroups_map_to_regions", function(check)
    check(Gore.RegionForHitGroup(HITGROUP_HEAD) == "head", "head hitgroup is the head region")
    check(Gore.RegionForHitGroup(HITGROUP_CHEST) == "torso", "chest hitgroup is the torso region")
    check(Gore.RegionForHitGroup(HITGROUP_LEFTARM) == "leftArm" and Gore.RegionForHitGroup(HITGROUP_RIGHTARM) == "rightArm",
        "arm hitgroups map to their side")
    check(Gore.RegionForHitGroup(HITGROUP_LEFTLEG) == "legs" and Gore.RegionForHitGroup(HITGROUP_RIGHTLEG) == "legs",
        "either leg severs the legs")
    check(Gore.RegionForHitGroup(HITGROUP_GENERIC) == nil, "generic hits have no hitgroup region")
end)

test("chance_needs_accumulated_damage_and_scales_with_weapon", function(check)
    check(Gore.SeverChance("leftArm", 0.1, 0.1, 2.5, false) == 0, "a living arm below its damage threshold never severs")
    local pistol = Gore.SeverChance("leftArm", 0.2, 0.3, 0.5, false)
    local shotgun = Gore.SeverChance("leftArm", 0.2, 0.3, 2.5, false)
    check(pistol > 0 and shotgun > pistol, "a heavier weapon has a higher chance once the threshold is met")
    check(Gore.SeverChance("leftArm", 0.1, 0.1, 0.5, true) > 0, "a killing blow ignores the damage threshold")
    check(Gore.SeverChance("legs", 1, 1, 10, true) == Gore.MaximumChance, "chances are capped")
    check(Gore.SeverChance("head", 1, 1, 2.5, false) == 0, "the head pops only on a killing blow")
    check(Gore.SeverChance("torso", 1, 1, 2.5, false) == 0, "torso splits only happen on a killing blow")
    check(Gore.SeverChance("torso", 0.5, 0.5, 2.5, true) > 0, "a heavy killing blow can split the torso")
    check(Gore.SeverChance("unknown", 1, 1, 1, true) == 0, "unknown regions never sever")
end)

test("weapon_factor_prefers_weapon_then_damage_type", function(check)
    check(Gore.WeaponFactor(damageOf(10, DMG_BUCKSHOT)) == 2.5, "buckshot falls back to a high factor")
    check(Gore.WeaponFactor(damageOf(10, DMG_SLASH)) == 1.8, "slashing falls back to its factor")
    check(Gore.WeaponFactor(damageOf(10, DMG_BULLET)) == Gore.DefaultFactor, "plain bullets use the default factor")
    local weapon = ents.Create("weapon_zn_shotgun_m3")
    if IsValid(weapon) then
        local damage = damageOf(10, DMG_BULLET)
        damage:SetInflictor(weapon)
        check(Gore.WeaponFactor(damage) == weapon.GoreSeverFactor and weapon.GoreSeverFactor == 2.5,
            "the inflicting weapon's GoreSeverFactor wins")
        weapon:Remove()
    else
        check(false, "a shotgun weapon fixture can be created")
    end
end)

test("living_leg_sever_makes_a_crawler", function(check)
    local zombie = spawnZombie()
    if not zombie then
        check(false, "a walker fixture can be created")
        return
    end
    local speed = zombie.WalkSpeed or zombie.DevelopmentWalkSpeed
    local model = zombie:GetModel()
    check(string.StartWith(model, "models/player/"), "walkers use a human player model (" .. model .. ")")
    forceRegion(zombie, "legs")
    check(Gore:HandleDamage(zombie, damageOf(10), false, { rng = always }) == nil,
        "a light leg hit below the threshold does not sever")
    forceRegion(zombie, "legs")
    local region = Gore:HandleDamage(zombie, damageOf(35), false, { rng = always })
    check(region == "legs", "accumulated leg damage past the threshold severs the legs")
    check(zombie:GetModel() == model and zombie:GetManipulateBonePosition(0) == Gore.CrawlerBodyOffset,
        "a legless zombie keeps its model and is lowered into a crawl")
    check(zombie:GetActivity() == zombie.CrawlActivity, "a crawler plays the crawl activity")
    check(zombie.GoreCrawler and math.abs(zombie.WalkSpeed - speed * Gore.CrawlerSpeedScale) < 0.001, "a crawler moves at half speed")
    local _, maxs = zombie:GetCollisionBounds()
    check(maxs.z == Gore.CrawlerMaxs.z, "a crawler has a low collision hull")
    forceRegion(zombie, "legs")
    check(Gore:HandleDamage(zombie, damageOf(50), false, { rng = always }) == nil, "legs cannot be severed twice")
    remove(zombie)
end)

test("bosses_keep_legs_while_alive", function(check)
    local boss = spawnZombie("zn_boss_zombie")
    if not boss then
        check(false, "a boss fixture can be created")
        return
    end
    check(Gore.IsBoss(boss), "the boss entity is recognised")
    check(not Gore.CanSever(boss, "legs", false), "a living boss never becomes a crawler")
    check(Gore.CanSever(boss, "leftArm", false), "a living boss can lose an arm")
    check(Gore.CanSever(boss, "legs", true) and Gore.CanSever(boss, "head", true), "a boss corpse can still gib")
    forceRegion(boss, "legs")
    check(Gore:HandleDamage(boss, damageOf(90), false, { rng = always }) == nil and not boss.GoreCrawler,
        "heavy leg damage leaves a living boss standing")
    remove(boss)
end)

test("death_severs_transfer_to_one_corpse", function(check)
    local zombie = spawnZombie()
    if not zombie then
        check(false, "a walker fixture can be created")
        return
    end
    forceRegion(zombie, "head")
    check(Gore:HandleDamage(zombie, damageOf(10), false, { rng = always }) == nil, "a non-lethal head hit never pops the head")
    zombie:SetHealth(0)
    forceRegion(zombie, "head")
    check(Gore:HandleDamage(zombie, damageOf(60), true, { rng = always }) == "head", "a killing headshot can pop the head")
    check(zombie.GoreDeathSever and zombie.GoreDeathSever.region == "head", "the killing sever is held for the corpse")
    local corpse = zombie:CreateCorpse()
    check(IsValid(corpse) and corpse:GetModel() == zombie:GetModel(), "a head pop keeps the full-body corpse")
    Gore:ApplyCorpse(zombie, corpse)
    check(IsValid(corpse) and Gore.HasRegion(Gore.GetMask(corpse), "head"), "the corpse carries the severed mask")
    check(zombie.GoreDeathSever == nil, "the killing sever is sent once")
    remove(corpse, zombie)

    local split = spawnZombie()
    split:SetHealth(0)
    forceRegion(split, "torso")
    check(Gore:HandleDamage(split, damageOf(100), true, { rng = always }) == "torso", "a heavy killing blow can split the torso")
    local splitCorpse = split:CreateCorpse()
    check(IsValid(splitCorpse) and splitCorpse:GetModel() == split:GetModel(), "a split corpse keeps the zombie model")
    remove(splitCorpse, split)
end)

test("killing_through_damage_creates_exactly_one_server_corpse", function(check)
    local zombie = spawnZombie()
    if not zombie then
        check(false, "a walker fixture can be created")
        return
    end
    local position = zombie:GetPos()
    local before = {}
    for _, entity in ipairs(ents.FindByClass("prop_ragdoll")) do
        before[entity] = true
    end
    forceRegion(zombie, "torso")
    zombie.GoreForcedRegion = "torso"
    local lethal = damageOf(500)
    local attacker = ZM_Util.FirstHuman()
    if IsValid(attacker) then
        lethal:SetAttacker(attacker)
        lethal:SetInflictor(attacker)
    end
    // The engine runs OnInjured, then subtracts health and calls OnKilled; TakeDamageInfo skips OnInjured on a
    // walker's spawn tick, so drive the same order directly.
    local healthBefore = zombie:Health()
    zombie:OnInjured(lethal)
    check(zombie:Health() == healthBefore, "OnInjured leaves health to the engine (no double damage)")
    zombie:SetHealth(healthBefore - lethal:GetDamage())
    local ok, failure = pcall(zombie.OnKilled, zombie, lethal)
    check(ok, "lethal damage is handled without error (" .. tostring(failure) .. ")")
    check(not IsValid(zombie) or zombie.WalkerDead, "lethal damage kills the walker (health " ..
        tostring(IsValid(zombie) and zombie:Health()) .. ")")
    local created = {}
    for _, entity in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not before[entity] and entity:GetPos():DistToSqr(position) < 256 * 256 then
            table.insert(created, entity)
        end
    end
    check(#created == 1, "one corpse is created per body; limbs are client-side only (got " .. #created .. ")")
    check(created[1] and string.StartWith(created[1]:GetModel(), "models/player/") and Gore.HasRegion(Gore.GetMask(created[1]), "legs"),
        "the torso-split corpse keeps the human model with the legs masked")
    check(created[1] and not created[1]:GetNWBool("ZM_LootSpot", false), "a corpse without a reward is not lootable")
    remove(unpack(created))
    remove(zombie)
end)

function Gore:RunTests()
    return suite:Run()
end

ZM_TestHarness.Register({
    command = "zn_test_gore", label = "Gore", file = "gore_tests.json", report = "goreTests",
    help = "Runs the dismemberment region, chance, crawler, and corpse-transfer tests.",
    run = function() return Gore:RunTests() end
})
