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
    WeaponRepairing = 0
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

// game specific variables
ply.ExperiencePerLevel = 1000 // equals a level
ply.PreviouslyConnected = false
ply.SkillPointsPerLevel = 1 // how many skill points the player gets per level up

function ply:AddXP(amount)
    self.XP = self.XP + amount
    if self:CanLevelUp() then
        //  while the player has enough XP to level up, keep leveling up until they don't have enough XP to level up
        local currentXP = self.XP
        while(  currentXP >= self.ExperiencePerLevel and self:CanLevelUp() ) do
            local newXP =  currentXP - self.ExperiencePerLevel 
            self.XP = newXP > 0 and newXP or 0
            self:LevelUp()
        end
        self.XP = currentXP
    end
end

function ply:GetPercentageToNextLevel()
    return (self.XP / self.ExperiencePerLevel) * 100
end

function ply:CanLevelUp()
    return self.XP >= self.ExperiencePerLevel
end

function ply:LevelUp()
    if self:CanLevelUp() then
        self.Level = self.Level + 1
        self.XP = self.XP - self.ExperiencePerLevel
        // increase the experience required for the next level
        self.ExperiencePerLevel = math.floor(self.ExperiencePerLevel * 1.1)
        // award skill points
        self.SkillPoints = self.SkillPoints + self.SkillPointsPerLevel

        // if the level is divisble by 5, give the player a bonus skill point
        if self.Level % 5 == 0 then
            self.SkillPoints = self.SkillPoints + self.SkillPointsPerLevel
        end

        // if the level is divisble by 10, give the player a bonus skill point
        if self.Level % 10 == 0 then
            self.SkillPoints = self.SkillPoints + self.SkillPointsPerLevel
        end

        // if the level is divisble by 25, give the player a bonus skill point
        if self.Level % 25 == 0 then
            self.SkillPoints = self.SkillPoints + self.SkillPointsPerLevel
        end

        // if the level is divisble by 50, give the player a bonus skill point
        if self.Level % 50 == 0 then
            self.SkillPoints = self.SkillPoints + self.SkillPointsPerLevel
        end

        // if the level is divisble by 100, give the player a bonus skill point
        if self.Level % 100 == 0 then
            self.SkillPoints = self.SkillPoints + self.SkillPointsPerLevel
        end
    end
end