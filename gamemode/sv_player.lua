// Server-only Player persistence, network synchronization, stamina, and XP behavior.
local ply = FindMetaTable("Player")
local playerBioDirectory = "zombiesim/player_bios"
local maxPlayerBioLength = 280

local function getPlayerBioPath(playerEntity)
    local steamId = playerEntity:SteamID64()
    if steamId == nil or steamId == "" or steamId == "0" then
        return nil
    end
    return playerBioDirectory .. "/" .. steamId .. ".txt"
end

local function normalizePlayerBio(bio)
    bio = string.Trim(tostring(bio or ""))
    bio = string.gsub(bio, "[%c]+", " ")
    bio = string.gsub(bio, "%s+", " ")
    return string.sub(bio, 1, maxPlayerBioLength)
end

// Loads a survivor bio from the server DATA folder and replicates it for the scoreboard.
function ply:LoadBio()
    local bioPath = getPlayerBioPath(self)
    if not bioPath then
        self:SetNWString("PlayerBio", "")
        return false
    end

    self:SetNWString("PlayerBio", normalizePlayerBio(file.Read(bioPath, "DATA") or ""))
    return true
end

// Persists a compact public bio outside profile-scoped progression data.
function ply:SaveBio(bio)
    local bioPath = getPlayerBioPath(self)
    if not bioPath then
        return false
    end

    local normalizedBio = normalizePlayerBio(bio)
    file.CreateDir(playerBioDirectory)
    file.Write(bioPath, normalizedBio)
    self:SetNWString("PlayerBio", normalizedBio)
    return true
end

local function getDefaultPlayerData()
    local worldData = ZM_World:GetData() or {}
    local worldOrigin = worldData.world and worldData.world.origin or {}
    return {
        XP = 0,
        Level = 1,
        MaxLevel = 300,
        Difficulty = 1,
        CellX = tonumber(worldOrigin[1]) or 0,
        CellY = tonumber(worldOrigin[2]) or 0,
        CurrentSafeZoneId = nil,
        SkillPoints = 0,
        Health = 100,
        Stamina = 100,
        Hunger = 100,
        Thirst = 100
    }
end

// Loads all attribute values, falling back to a zeroed record for a new player.
function ply:FetchAttributes()

    local attr, attributeError = ZM_GetPlayerAttributes(self:SteamID(), ZM_World.ActiveProfile)
    if attributeError then
        return false, attributeError
    end

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

    self.Attributes = {}
    self.Attributes.Strength = tonumber(attr.Strength) or 0
    self.Attributes.Agility = tonumber(attr.Agility) or 0
    self.Attributes.Intelligence = tonumber(attr.Intelligence) or 0
    self.Attributes.Endurance = tonumber(attr.Endurance) or 0
    self.Attributes.MachineGuns = tonumber(attr.MachineGuns) or 0
    self.Attributes.Shotguns = tonumber(attr.Shotguns) or 0
    self.Attributes.Snipers = tonumber(attr.Snipers) or 0
    self.Attributes.WeaponCrafting = tonumber(attr.WeaponCrafting) or 0
    self.Attributes.ArmorCrafting = tonumber(attr.ArmorCrafting) or 0
    self.Attributes.Medicine = tonumber(attr.Medicine) or 0
    self.Attributes.Farming = tonumber(attr.Farming) or 0
    self.Attributes.WeaponRepairing = tonumber(attr.WeaponRepairing) or 0
    self.Attributes.ArmorRepairing = tonumber(attr.ArmorRepairing) or 0
    self.Attributes.Mechanics = tonumber(attr.Mechanics) or 0
    return true
end

// Signals the owning client to copy its replicated attribute values into local fields.
function ply:SendPlayerAttributes()
    net.Start("ZM.RefreshPlayerAttributes")
    net.Send(self)
end

// Signals the owning client to copy its replicated core data into local fields.
function ply:SendPlayerData()
    local snapshot = {
        XP = tonumber(self.XP) or 0,
        Level = tonumber(self.Level) or 1,
        MaxLevel = tonumber(self.MaxLevel) or 300,
        Difficulty = tonumber(self.Difficulty) or 1,
        CellX = tonumber(self.CellX) or 0,
        CellY = tonumber(self.CellY) or 0,
        CurrentSafeZoneId = self.CurrentSafeZoneId or "",
        SkillPoints = tonumber(self.SkillPoints) or 0,
        Health = tonumber(self.SavedHealth) or 100,
        Stamina = tonumber(self.Stamina) or 100,
        Hunger = tonumber(self.Hunger) or 100,
        Thirst = tonumber(self.Thirst) or 100
    }
    net.Start("ZM.RefreshPlayerData")
        net.WriteString(util.TableToJSON(snapshot, false) or "{}")
    net.Send(self)
end

// Persists every player record. Health and survival values are sampled immediately before the write.
function ply:Save(source)
    if self.ZM_PersistentStateLoaded ~= true then
        return false, "Player persistent state has not been loaded"
    end

    local attributesSaved, attributesError = ZM_SetPlayerAttributes(self:SteamID(), ZM_World.ActiveProfile, self.Attributes)
    self.SavedHealth = math.max(self:Health(), 0)
    self.Stamina = math.Clamp(self.Stamina or 100, 0, self:GetMaxStamina())
    self.Hunger = math.Clamp(self.Hunger or 100, 0, 100)
    self.Thirst = math.Clamp(self.Thirst or 100, 0, 100)
    local playerDataSaved, playerDataError = self:UpdatePlayerData(source or "player save")
    if not attributesSaved then
        return false, attributesError
    end
    return playerDataSaved, playerDataError
end

// Saves only the attributes table when an attribute changes.
function ply:UpdateAttributes()
    return ZM_SetPlayerAttributes(self:SteamID(), ZM_World.ActiveProfile, self.Attributes)
end

// Saves only the core player-data row when progression, cell, or survival values change.
function ply:UpdatePlayerData(source)
    if self.ZM_PersistentStateLoaded ~= true then
        return false, "Player persistent state has not been loaded"
    end

    return ZM_SetPlayerData(self:SteamID(), ZM_World.ActiveProfile, {XP = self.XP, Level = self.Level, MaxLevel = self.MaxLevel, Difficulty = self.Difficulty, CellX = self.CellX, CellY = self.CellY, CurrentSafeZoneId = self.CurrentSafeZoneId, SkillPoints = self.SkillPoints, Health = self.SavedHealth, Stamina = self.Stamina, Hunger = self.Hunger, Thirst = self.Thirst}, source or "runtime update")
end

// Records the standalone safe room the player is currently in without changing their city cell.
// Pass nil to record that the player has returned to the city.
function ply:SetCurrentSafeZone(safeZoneId)
    local previousSafeZoneId = self.CurrentSafeZoneId
    if safeZoneId == nil or safeZoneId == "" then
        self.CurrentSafeZoneId = nil
    else
        local safeZone = ZM_World:GetSafeZoneById(safeZoneId)
        if not safeZone then
            return false, "Unknown safe-zone id: " .. tostring(safeZoneId)
        end

        self.CurrentSafeZoneId = safeZone.id
    end

    local updated, updateError = self:UpdatePlayerData("safe-zone update")
    if not updated then
        self.CurrentSafeZoneId = previousSafeZoneId
        return false, updateError or "Could not persist current safe zone"
    end
    self:SetNetworkPlayerData()
    if GAMEMODE and GAMEMODE.SendPlayerAtmosphereProfile then
        GAMEMODE:SendPlayerAtmosphereProfile(self)
    end
    return true
end

// Changes a player's logical world position and updates the atmosphere before the next map transition.
function ply:SetWorldCell(worldX, worldY)
    worldX = tonumber(worldX)
    worldY = tonumber(worldY)
    if not worldX or not worldY then
        return false, "World cell coordinates must be numeric"
    end

    worldX = math.floor(worldX)
    worldY = math.floor(worldY)
    local gridX, gridY = ZM_World:GetGridCoordinates(worldX, worldY)
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    if not cell then
        return false, "World cell is outside the loaded world"
    end

    local previousX, previousY = self.CellX, self.CellY
    local previousSafeZoneId = self.CurrentSafeZoneId
    self.CellX = worldX
    self.CellY = worldY
    self.CurrentSafeZoneId = nil
    local updated, updateError = self:UpdatePlayerData("world-cell update")
    if not updated then
        self.CellX = previousX
        self.CellY = previousY
        self.CurrentSafeZoneId = previousSafeZoneId
        return false, updateError or "Could not persist player world cell"
    end
    self:SetNetworkPlayerData()
    if GAMEMODE and GAMEMODE.SendPlayerAtmosphereProfile then
        GAMEMODE:SendPlayerAtmosphereProfile(self)
    end
    return true
end

// Restores fresh-character state at the active world's origin safe-zone entrance.
function ply:ResetForWorldOrigin()
    local originSafeZone = ZM_World:GetOriginSafeZone()
    local originCell = originSafeZone and ZM_World:GetCellById(originSafeZone.cell) or nil
    local destination = ZM_SafeZones:GetOriginMap()
    if not originSafeZone or not originCell or not destination then
        return false, "The active world origin safe zone is unavailable"
    end

    self.Attributes = {
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
        Mechanics = 0
    }
    self.XP = 0
    self.Level = 1
    self.MaxLevel = 300
    self.Difficulty = 1
    self.CellX, self.CellY = ZM_World:GetWorldCoordinates(originCell)
    self.CurrentSafeZoneId = originSafeZone.id
    self.SkillPoints = 10
    self.SavedHealth = 100
    self.Stamina = self:GetMaxStamina()
    self.Hunger = 100
    self.Thirst = 100
    self:SetHealth(self.SavedHealth)
    self:UpdateAttributes()
    self:UpdatePlayerData("player reset")
    self:SetNetworkAttributes()
    self:SetNetworkPlayerData()
    self:SendPlayerAttributes()
    self:SendPlayerData()
    if GAMEMODE and GAMEMODE.SendPlayerAtmosphereProfile then
        GAMEMODE:SendPlayerAtmosphereProfile(self)
    end

    return true, destination
end

// Loads core progression and logical world position, defaulting a first-time player to the world origin.
function ply:FetchPlayerData()

    local data, playerDataError = ZM_GetPlayerData(self:SteamID(), ZM_World.ActiveProfile)
    if playerDataError then
        return nil, playerDataError
    end
    local previouslyConnected = data ~= nil

    if ZM_World.ActiveProfile == "preview" then
        local recordDescription = "no record"
        if data then
            recordDescription = string.format(
                "cell %s,%s; skill points %s; safe zone %s",
                tostring(data.CellX),
                tostring(data.CellY),
                tostring(data.SkillPoints),
                tostring(data.CurrentSafeZoneId or "none")
            )
        end
        print(string.format(
            "[ZombieSim] Preview data load: %s on %s -> %s",
            self:SteamID(),
            game.GetMap(),
            recordDescription
        ))
    end

    if ( data == nil ) then
        data = getDefaultPlayerData()
    end

    local originX = tonumber((ZM_World:GetData().world.origin or {})[1]) or 0
    local originY = tonumber((ZM_World:GetData().world.origin or {})[2]) or 0

    local originSafeZone = ZM_World:GetOriginSafeZone()
    local originCell = originSafeZone and ZM_World:GetCellById(originSafeZone.cell) or nil
    if originSafeZone and originCell and data.CurrentSafeZoneId == originSafeZone.id
        and tonumber(data.CellX) == originCell.x and tonumber(data.CellY) == originCell.y then
        data.CellX = originX
        data.CellY = originY
    end

    self.XP = tonumber(data.XP) or 0
    self.Level = tonumber(data.Level) or 1
    self.MaxLevel = tonumber(data.MaxLevel) or 300
    self.Difficulty = tonumber(data.Difficulty) or 1 -- 1 = Easy, 2 = Normal, 3 = Hard, 4 = Insane
    self.CellX = tonumber(data.CellX) or originX
    self.CellY = tonumber(data.CellY) or originY
    self.CurrentSafeZoneId = data.CurrentSafeZoneId or nil
    self.SkillPoints = tonumber(data.SkillPoints) or 0
    self.SavedHealth = tonumber(data.Health) or 100
    self.Stamina = tonumber(data.Stamina) or 100
    self.Stamina = math.Clamp(self.Stamina, 0, self:GetMaxStamina())
    self.Hunger = math.Clamp(tonumber(data.Hunger) or 100, 0, 100)
    self.Thirst = math.Clamp(tonumber(data.Thirst) or 100, 0, 100)
    if ZM_World.ActiveProfile == "preview" and ZM_DevConsole and ZM_DevConsole.WritePlayerHydration then
        ZM_DevConsole:WritePlayerHydration({
            steamId = self:SteamID(),
            map = game.GetMap(),
            recordFound = previouslyConnected,
            cellX = self.CellX,
            cellY = self.CellY,
            currentSafeZoneId = self.CurrentSafeZoneId,
            skillPoints = self.SkillPoints,
            health = self.SavedHealth,
            stamina = self.Stamina,
            hunger = self.Hunger,
            thirst = self.Thirst
        })
    end
    return previouslyConnected
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

// Copies progression, logical world cell, health, and stamina to replicated NW values.
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
    self:SetNWFloat("Hunger", self.Hunger)
    self:SetNWFloat("Thirst", self.Thirst)
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

            ply.Stamina = math.Clamp(stamina, 0, maxStamina)

            ply:SetNWFloat("Stamina", ply.Stamina)
            ply:SetNWFloat("MaxStamina", maxStamina)
        end
    end
end)

// Continuously drains survival reserves. Values are persisted with normal player saves.
local nextSurvivalUpdateAt = 0
hook.Add("Think", "ZM.Survival", function()
    if CurTime() < nextSurvivalUpdateAt then return end
    nextSurvivalUpdateAt = CurTime() + 1

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end

        ply.Hunger = math.Clamp((tonumber(ply.Hunger) or 100) - (1 / 600), 0, 100)
        ply.Thirst = math.Clamp((tonumber(ply.Thirst) or 100) - (1 / 400), 0, 100)
        ply:SetNWFloat("Hunger", ply.Hunger)
        ply:SetNWFloat("Thirst", ply.Thirst)

        local starvationDamage = ply.Hunger <= 0 and 1 or 0
        local dehydrationDamage = ply.Thirst <= 0 and 2 or 0
        if starvationDamage + dehydrationDamage > 0 then
            ply:TakeDamage(starvationDamage + dehydrationDamage, game.GetWorld(), game.GetWorld())
        end
    end
end)

// Applies ambient radiation once per second; standalone safe rooms remain protected.
local nextRadiationDamageAt = 0
hook.Add("Think", "ZM.RadiationDamage", function()
    if CurTime() < nextRadiationDamageAt then return end
    nextRadiationDamageAt = CurTime() + 1

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end

        local inSafeZone = type(ply.CurrentSafeZoneId) == "string" and ply.CurrentSafeZoneId ~= ""
        local intensity = inSafeZone and 0 or ply:GetRadiationIntensity()
        intensity = tonumber(intensity) or 0
        ply:SetNWFloat("RadiationIntensity", intensity)
        if intensity <= 0 then continue end

        local damagePerSecond = ply:GetRadiationDamagePerSecond()
        if not damagePerSecond or damagePerSecond <= 0 then continue end

        local damageInfo = DamageInfo()
        damageInfo:SetDamage(damagePerSecond)
        damageInfo:SetDamageType(DMG_RADIATION)
        damageInfo:SetAttacker(game.GetWorld())
        damageInfo:SetInflictor(game.GetWorld())
        ply:TakeDamageInfo(damageInfo)
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