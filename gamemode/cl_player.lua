// Client-side mirrors of the Player values replicated by sv_player.lua.
local ply = FindMetaTable("Player")

// Copies all replicated attribute NWInts into fields used by local HUD/gameplay code.
function ply:SetPlayerAttributes()
    self.Attributes = {}
    self.Attributes.Strength = self:GetNWInt("Strength")
    self.Attributes.Agility = self:GetNWInt("Agility")
    self.Attributes.Intelligence = self:GetNWInt("Intelligence")
    self.Attributes.Endurance = self:GetNWInt("Endurance")
    self.Attributes.MachineGuns = self:GetNWInt("MachineGuns")
    self.Attributes.Shotguns = self:GetNWInt("Shotguns")
    self.Attributes.Snipers = self:GetNWInt("Snipers")
    self.Attributes.WeaponCrafting = self:GetNWInt("WeaponCrafting")
    self.Attributes.ArmorCrafting = self:GetNWInt("ArmorCrafting")
    self.Attributes.Medicine = self:GetNWInt("Medicine")
    self.Attributes.Farming = self:GetNWInt("Farming")
    self.Attributes.WeaponRepairing = self:GetNWInt("WeaponRepairing")
    self.Attributes.ArmorRepairing = self:GetNWInt("ArmorRepairing")
    self.Attributes.Mechanics = self:GetNWInt("Mechanics")
end

// Copies a server snapshot into fields used by local UI and gameplay code.
function ply:SetPlayerData(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local function integer(key, fallback)
        return math.floor(tonumber(snapshot[key]) or fallback)
    end
    local function number(key, fallback)
        return tonumber(snapshot[key]) or fallback
    end

    self.XP = integer("XP", self:GetNWInt("XP"))
    self.Level = integer("Level", self:GetNWInt("Level", 1))
    self.MaxLevel = integer("MaxLevel", self:GetNWInt("MaxLevel", 300))
    self.Difficulty = integer("Difficulty", self:GetNWInt("Difficulty", 1))
    self.CellX = integer("CellX", self:GetNWInt("CellX"))
    self.CellY = integer("CellY", self:GetNWInt("CellY"))
    self.CurrentSafeZoneId = tostring(snapshot.CurrentSafeZoneId or self:GetNWString("CurrentSafeZoneId", ""))
    self.SkillPoints = integer("SkillPoints", self:GetNWInt("SkillPoints"))
    self.SavedHealth = integer("Health", self:GetNWInt("Health", 100))
    self.Stamina = number("Stamina", self:GetNWFloat("Stamina", 100))
    self.Hunger = number("Hunger", self:GetNWFloat("Hunger", 100))
    self.Thirst = number("Thirst", self:GetNWFloat("Thirst", 100))
end
