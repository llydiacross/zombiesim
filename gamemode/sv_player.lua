local ply = FindMetaTable("Player")

function ply:FetchAttributes() 

    local attr = GetPlayerAttributes(self:SteamID())

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

function ply:SendPlayerAttributes()
    net.Start("RefreshPlayerAttributes")
    net.Send(self)
end

function ply:SendPlayerData()
    net.Start("RefreshPlayerData")
    net.Send(self)
end

function ply:Save()
    SetPlayerAttributes(self:SteamID(), self.Attributes)
    SetPlayerData(self:SteamID(), {XP = self.XP, Level = self.Level, MaxLevel = self.MaxLevel, Difficulty = self.Difficulty, CellX = self.CellX, CellY = self.CellY, SkillPoints = self.SkillPoints})
end

function ply:UpdateAttributes()
    SetPlayerAttributes(self:SteamID(), self.Attributes)
end

function ply:UpdatePlayerData()
    SetPlayerData(self:SteamID(), {XP = self.XP, Level = self.Level, MaxLevel = self.MaxLevel, Difficulty = self.Difficulty, CellX = self.CellX, CellY = self.CellY, SkillPoints = self.SkillPoints})
end

function ply:FetchPlayerData()

    local data = GetPlayerData(self:SteamID())

    self.XP = data.XP or 0
    self.Level = data.Level or 1
    self.MaxLevel = data.MaxLevel or 300
    self.Difficulty = data.Difficulty or 1 -- 1 = Easy, 2 = Normal, 3 = Hard, 4 = Insane
    self.CellX = data.CellX or 0
    self.CellY = data.CellY or 0
    self.SkillPoints = data.SkillPoints or 0
end

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

function ply:SetNetworkPlayerData()
    self:SetNWInt("XP", self.XP)
    self:SetNWInt("Level", self.Level)
    self:SetNWInt("MaxLevel", self.MaxLevel)
    self:SetNWInt("Difficulty", self.Difficulty)
    self:SetNWInt("CellX", self.CellX)
    self:SetNWInt("CellY", self.CellY)
    self:SetNWInt("SkillPoints", self.SkillPoints)
end