ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "Walker Zombie"
ENT.Category = "ZombieSim"
ENT.Spawnable = false
ENT.AdminOnly = false

// Zombies are infected survivors: stock citizen, refugee and rebel player models, picked at random per zombie.
// They share the ValveBiped skeleton and the HL2MP zombie animation set used in init.lua.
ENT.Model = "models/player/group01/male_01.mdl"
ENT.Models = {}
for _, group in ipairs({ "group01", "group02", "group03" }) do
    for index = 1, 9 do
        // Mounted group02 supplies only the four even-numbered male refugees.
        if group ~= "group02" or index % 2 == 0 then
            table.insert(ENT.Models, string.format("models/player/%s/male_%02d.mdl", group, index))
        end
    end
    if group ~= "group02" then
        for index = 1, 6 do
            table.insert(ENT.Models, string.format("models/player/%s/female_%02d.mdl", group, index))
        end
    end
end
ENT.WalkActivities = { ACT_HL2MP_WALK_ZOMBIE_01, ACT_HL2MP_WALK_ZOMBIE_02, ACT_HL2MP_WALK_ZOMBIE_03,
    ACT_HL2MP_WALK_ZOMBIE_04, ACT_HL2MP_WALK_ZOMBIE_05 }
ENT.IdleActivity = ACT_HL2MP_IDLE_ZOMBIE
ENT.CrawlActivity = ACT_HL2MP_SWIM
ENT.AttackGesture = ACT_GMOD_GESTURE_RANGE_ZOMBIE
ENT.DevelopmentHealth = 100
ENT.DevelopmentWalkSpeed = 41.25
ENT.DevelopmentAttackDamage = 12
ENT.DevelopmentAttackRange = 64
ENT.DevelopmentAttackInterval = 1
ENT.DevelopmentTargetSearchRange = 800
ENT.DevelopmentTargetSearchInterval = 1
ENT.DevelopmentPathRefreshInterval = 1.25
ENT.DevelopmentTargetMoveThreshold = 96
ENT.DevelopmentPathFailureCooldown = 2
ENT.DevelopmentTargetMemorySeconds = 10
// Phase B perception and behaviour (user-approved 2026-10-30).
ENT.VisionConeDot = 0.5
ENT.CloseSenseRange = 150
ENT.AttackWindup = 0.9
ENT.AttackRecovery = 0.6
ENT.AttackReachTolerance = 16
ENT.WanderRadius = 256
ENT.WanderSpeedScale = 0.6
ENT.WanderPauseMin = 3
ENT.WanderPauseMax = 8
ENT.WanderTimeout = 12
ENT.InvestigateSeconds = 15
ENT.GroupingRadius = 600
ENT.ScuffleRange = 56
ENT.ScuffleChance = 0.004
ENT.ScuffleCooldown = 20
ENT.SoundIdle = "npc/zombie/zombie_voice_idle%d.wav"
ENT.SoundIdleCount = 14
ENT.SoundAlert = "npc/zombie/zombie_alert%d.wav"
ENT.SoundAlertCount = 3
ENT.SoundAttack = "npc/zombie/zo_attack%d.wav"
ENT.SoundAttackCount = 2
ENT.SoundHit = "npc/zombie/claw_strike%d.wav"
ENT.SoundHitCount = 3
ENT.SoundMiss = "npc/zombie/claw_miss%d.wav"
ENT.SoundMissCount = 2