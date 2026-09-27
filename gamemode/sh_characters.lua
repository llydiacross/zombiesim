// Character creation rules shared for presentation; the server validates every submitted value again.
ZM_CharacterRules = {
	StartingPoints = 10,
	MaximumAttribute = 10,
	Attributes = {
		"Strength", "Agility", "Intelligence", "Endurance", "MachineGuns", "Shotguns",
		"Snipers", "WeaponCrafting", "ArmorCrafting", "Medicine", "Farming",
		"WeaponRepairing", "ArmorRepairing", "Mechanics"
	},
	Models = {}
}

for _, gender in ipairs({ "male", "female" }) do
	for index = 1, gender == "male" and 9 or 6 do
		table.insert(ZM_CharacterRules.Models,
			"models/player/group01/" .. gender .. "_" .. string.format("%02d", index) .. ".mdl")
	end
end
