// Server-only Player persistence, network synchronization, stamina, and XP behavior.
local ply = FindMetaTable("Player")

// Loads all attribute values, falling back to a zeroed record for a new player.
function ply:FetchAttributes() 

    local attr = ZM_GetPlayerAttributes(self:SteamID())

    if( attr == nil ) then
        attr = {
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
    end

    self.Attributes.Strength = attr.Strength or 0
    self.Attributes.Agility = attr.Agility or 0
    self.Attributes.Intelligence = attr.Intelligence or 0
    self.Attributes.Endurance = attr.Endurance or 0 
    self.Attributes.MachineGuns = attr.MachineGuns or 0
    self.Attributes.Shotguns = attr.Shotguns or 0
    self.Attributes.Snipers = attr.Snipers or 0
    self.Attributes.WeaponCrafting = attr.WeaponCrafting or 0
    self.Attributes.ArmorCrafting = attr.ArmorCrafting or 0
    self.Attributes.Medicine = attr.Medicine or 0
    self.Attributes.Farming = attr.Farming or 0
    self.Attributes.WeaponRepairing = attr.WeaponRepairing or 0
    self.Attributes.ArmorRepairing = attr.ArmorRepairing or 0
    self.Attributes.Mechanics = attr.Mechanics or 0
end

// Signals the owning client to copy its replicated attribute values into local fields.
function ply:SendPlayerAttributes()
    net.Start("ZM.RefreshPlayerAttributes")
    net.Send(self)
end

// Signals the owning client to copy its replicated core data into local fields.
function ply:SendPlayerData()
    net.Start("ZM.RefreshPlayerData")
    net.Send(self)
end

// Persists every player record. Health and stamina are sampled immediately before the write.
function ply:Save()
    ZM_SetPlayerAttributes(self:SteamID(), self.Attributes)
    self.SavedHealth = math.max(self:Health(), 0)
    self.Stamina = math.Clamp(self.Stamina or 100, 0, self:GetMaxStamina())
    ZM_SetPlayerData(self:SteamID(), {XP = self.XP, Level = self.Level, MaxLevel = self.MaxLevel, Difficulty = self.Difficulty, CellX = self.CellX, CellY = self.CellY, CurrentSafeZoneId = self.CurrentSafeZoneId, SkillPoints = self.SkillPoints, Health = self.SavedHealth, Stamina = self.Stamina})
end

// Saves only the attributes table when an attribute changes.
function ply:UpdateAttributes()
    ZM_SetPlayerAttributes(self:SteamID(), self.Attributes)
end

// Saves only the core player-data row when progression, cell, or survival values change.
function ply:UpdatePlayerData()
    ZM_SetPlayerData(self:SteamID(), {XP = self.XP, Level = self.Level, MaxLevel = self.MaxLevel, Difficulty = self.Difficulty, CellX = self.CellX, CellY = self.CellY, CurrentSafeZoneId = self.CurrentSafeZoneId, SkillPoints = self.SkillPoints, Health = self.SavedHealth, Stamina = self.Stamina})
end

// Records the standalone safe room the player is currently in without changing their city cell.
// Pass nil to record that the player has returned to the city.
function ply:SetCurrentSafeZone(safeZoneId)
    if safeZoneId == nil or safeZoneId == "" then
        self.CurrentSafeZoneId = nil
    else
        local safeZone = ZM_World:GetSafeZoneById(safeZoneId)
        if not safeZone then
            return false, "Unknown safe-zone id: " .. tostring(safeZoneId)
        end

        self.CurrentSafeZoneId = safeZone.id
    end

    self:UpdatePlayerData()
    self:SetNetworkPlayerData()
    return true
end

// Loads core progression and logical city position, defaulting a first-time player to cell 0,0.
function ply:FetchPlayerData()

    local data = ZM_GetPlayerData(self:SteamID())

    if ( data == nil ) then
        data = {
            XP = 0,
            Level = 1,
            MaxLevel = 300,
            Difficulty = 1, -- 1 = Easy, 2 = Normal, 3 = Hard, 4 = Insane
            CellX = 0,
            CellY = 0,
            CurrentSafeZoneId = nil,
            SkillPoints = 0,
            Health = 100,
            Stamina = 100
        }
    end

    self.XP = data.XP or 0
    self.Level = data.Level or 1
    self.MaxLevel = data.MaxLevel or 300
    self.Difficulty = data.Difficulty or 1 -- 1 = Easy, 2 = Normal, 3 = Hard, 4 = Insane
    self.CellX = data.CellX or 0
    self.CellY = data.CellY or 0
    self.CurrentSafeZoneId = data.CurrentSafeZoneId or nil
    self.SkillPoints = data.SkillPoints or 0
    self.SavedHealth = tonumber(data.Health) or 100
    self.Stamina = tonumber(data.Stamina) or 100
    self.Stamina = math.Clamp(self.Stamina, 0, self:GetMaxStamina())
end

// Copies server attribute fields to replicated NWInts for the owning client and HUD.
function ply:SetNetworkAttributes()
    self:SetNWInt("Strength", self.Attributes.Strength)
    self:SetNWInt("Agility", self.Attributes.Agility)
    self:SetNWInt("Intelligence", self.Attributes.Intelligence)
    self:SetNWInt("Endurance", self.Attributes.Endurance)
    self:SetNWInt("MachineGuns", self.Attributes.MachineGuns)
    self:SetNWInt("Shotguns", self.Attributes.Shotguns)
    self:SetNWInt("Snipers", self.Attributes.Snipers)
    self:SetNWInt("WeaponCrafting", self.Attributes.WeaponCrafting)
    self:SetNWInt("ArmorCrafting", self.Attributes.ArmorCrafting)
    self:SetNWInt("Medicine", self.Attributes.Medicine)
    self:SetNWInt("Farming", self.Attributes.Farming)
    self:SetNWInt("WeaponRepairing", self.Attributes.WeaponRepairing)
    self:SetNWInt("ArmorRepairing", self.Attributes.ArmorRepairing)
    self:SetNWInt("Mechanics", self.Attributes.Mechanics)
end

// Copies progression, logical cell, health, and stamina to replicated NW values.
function ply:SetNetworkPlayerData()
    self:SetNWInt("XP", self.XP)
    self:SetNWInt("Level", self.Level)
    self:SetNWInt("MaxLevel", self.MaxLevel)
    self:SetNWInt("Difficulty", self.Difficulty)
    self:SetNWInt("CellX", self.CellX)
    self:SetNWInt("CellY", self.CellY)
    self:SetNWString("CurrentSafeZoneId", self.CurrentSafeZoneId or "")
    self:SetNWInt("SkillPoints", self.SkillPoints)
    self:SetNWInt("Health", self.SavedHealth)
    self:SetNWFloat("Stamina", self.Stamina)
    self:SetNWFloat("MaxStamina", self:GetMaxStamina())
end

// Prevents sprint input from moving an exhausted living player faster than walking speed.
hook.Add("SetupMove", "ZM.StaminaMovement", function(ply, move)
    if not IsValid(ply) or not ply:Alive() then return end

    ply.ZM_IsSprinting = bit.band(move:GetButtons(), IN_SPEED) ~= 0

    if ply.Stamina > 0 then return end

    move:SetMaxSpeed(ply:GetWalkSpeed())
    move:SetMaxClientSpeed(ply:GetWalkSpeed())
    move:SetButtons(bit.band(move:GetButtons(), bit.bnot(IN_SPEED)))
end)

// Continuously drains sprint stamina and restores stamina while the player is not sprinting.
hook.Add("Think", "ZM.Stamina", function()
    local delta = engine.TickInterval()
    local baseSprintDrain = 800

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local maxStamina = ply:GetMaxStamina()
            local isSprinting = ply:KeyDown(IN_SPEED)
            local agility = tonumber(ply.Attributes and ply.Attributes.Agility) or 0
            local strength = tonumber(ply.Attributes and ply.Attributes.Strength) or 0
            local stamina = tonumber(ply.Stamina) or maxStamina
            local staminaRate = baseSprintDrain / (1 + agility * 0.05 + strength * 0.03)
            local recoveryRate = 5 * (1 + agility * 0.05)

            if isSprinting then
                stamina = stamina - staminaRate * delta
            else
                stamina = stamina + recoveryRate * delta
            end

            print( string.format("Player: %s, Stamina: %.2f, MaxStamina: %.2f, IsSprinting: %s", ply:Nick(), stamina, maxStamina, tostring(isSprinting)) )

            ply.Stamina = math.Clamp(stamina, 0, maxStamina)

            ply:SetNWFloat("Stamina", ply.Stamina)
            ply:SetNWFloat("MaxStamina", maxStamina)
        end
    end
end)

// Adds XP and levels repeatedly if one award crosses several level thresholds.
function ply:AddXP(amount)
    self.XP = self.XP + amount
    if self:CanLevelUp() then
        //  while the player has enough XP to level up, keep leveling up until they don't have enough XP to level up
        local currentXP = self.XP
        while(  currentXP >= self.ExperiencePerLevel and self:CanLevelUp() ) do
            local newXP =  currentXP - self.ExperiencePerLevel 
            self:LevelUp()
            self.XP = newXP > 0 and newXP or 0
        end
        self.XP = currentXP
    end
end

// Consumes one level threshold and awards milestone bonus skill points.
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