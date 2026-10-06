// Shared gamemode metadata and startup work executed in both server and client realms.
include("sh_player.lua")
include("sh_loading.lua")
include("sh_distribution.lua")
include("sh_version.lua")
include("sh_compass.lua")
include("utils/world.lua")
include("utils/safezone.lua")
include("sh_preview.lua")
include("sh_music.lua")
include("sh_clothing.lua")
include("sh_static_data.lua")
include("sh_items.lua")
include("sh_weapon_effects.lua")
include("sh_food.lua")
include("sh_professions.lua")
include("sh_implants.lua")
include("sh_loot_targeting.lua")
include("sh_radiation_feedback.lua")
include("sh_gore_effects.lua")

// Item behaviour classes; each file registers itself in ZM_EntityClasses.
for _, itemFile in ipairs(file.Find(GM.FolderName .. "/gamemode/items/*.lua", "LUA")) do
	if SERVER then
		AddCSLuaFile("items/" .. itemFile)
	end
	include("items/" .. itemFile)
end

GM.Name = "Z-Nation"
GM.Author = "N/A"
GM.Email = "N/A"
GM.Website = "N/A"

// Loads the city-data profile selected by the current map's optional zn_world_profile entity.
function GM:InitPostEntity()
	if SERVER then
		self.PlayerWorldMapTransitionQueued = false
	end

	local loaded, loadError = ZM_World:LoadMapProfile()
	if not loaded then
		ErrorNoHalt("[ZombieSim] " .. loadError .. "\n")
	end
	if CLIENT then
		ZM_Loading:Step(loaded and "Loaded " .. tostring(ZM_World.ActiveProfile or "world") .. " world data"
			or "World data unavailable", loaded and "ok" or "fail")
	end
end