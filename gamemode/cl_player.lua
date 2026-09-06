// Client-side mirrors of the Player values replicated by sv_player.lua.
local ply = FindMetaTable("Player")

// Copies all replicated attribute NWInts into fields used by local HUD/gameplay code.
function ply:SetPlayerAttributes()
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

// Copies the replicated core progression NWInts into local fields.
// Cell position remains available directly as NWInts until client code needs it.
function ply:SetPlayerData()
    self.XP = self:GetNWInt("XP")
    self.Level = self:GetNWInt("Level")
    self.MaxLevel = self:GetNWInt("MaxLevel")
    self.Difficulty = self:GetNWInt("Difficulty")
end
