local ply = FindMetaTable("Player")

ply.Attributes = {
    Strength = 0,
    Agility = 0,
    Intelligence = 0,
    Endurance = 0,
    MachineGuns = 0,
    Shotguns = 0,
    Snipers = 0,
    WeaponCrafting = 0,
    ArmorCrafting = 0,
    Medicine = 0,
    Farming = 0,
    WeaponRepairing = 0,
    ArmorRepairing = 0,
    Mechanics = 0
}

ply.XP = 0
ply.Level = 1
ply.MaxLevel = 300
ply.Difficulty = 1 -- 1 = Easy, 2 = Normal, 3 = Hard, 4 = Insane
ply.CellX = 0
ply.CellY = 0
ply.SkillPoints = 0
ply.Health = 100
ply.Stamina = 100

// game specific variables
ply.ExperiencePerLevel = 1000 // equals a level
ply.PreviouslyConnected = false
ply.SkillPointsPerLevel = 1 // how many skill points the player gets per level up

function ply:GetMaxStamina()
    local agility = tonumber(self.Attributes and self.Attributes.Agility) or 0
    local strength = tonumber(self.Attributes and self.Attributes.Strength) or 0

    return 100 + agility * 5 + strength * 3
end

function ply:GetPercentageToNextLevel()
    return (self.XP / self.ExperiencePerLevel) * 100
end

function ply:CanLevelUp()
    return self.XP >= self.ExperiencePerLevel
end

