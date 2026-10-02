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
        table.insert(ENT.Models, string.format("models/player/%s/male_%02d.mdl", group, index))
    end
    for index = 1, 6 do
        table.insert(ENT.Models, string.format("models/player/%s/female_%02d.mdl", group, index))
    end
end
ENT.WalkActivities = { ACT_HL2MP_WALK_ZOMBIE_01, ACT_HL2MP_WALK_ZOMBIE_02, ACT_HL2MP_WALK_ZOMBIE_03,
    ACT_HL2MP_WALK_ZOMBIE_04, ACT_HL2MP_WALK_ZOMBIE_05 }
ENT.IdleActivity = ACT_HL2MP_IDLE_ZOMBIE
ENT.CrawlActivity = ACT_HL2MP_SWIM
ENT.AttackGesture = ACT_GMOD_GESTURE_RANGE_ZOMBIE
ENT.DevelopmentHealth = 100
ENT.DevelopmentWalkSpeed = 55
ENT.DevelopmentAttackDamage = 12
ENT.DevelopmentAttackRange = 64
ENT.DevelopmentAttackInterval = 1
ENT.DevelopmentTargetSearchRange = 800
ENT.DevelopmentTargetSearchInterval = 1
ENT.DevelopmentPathRefreshInterval = 1.25
ENT.DevelopmentTargetMoveThreshold = 96
ENT.DevelopmentPathFailureCooldown = 2
ENT.DevelopmentTargetMemorySeconds = 10