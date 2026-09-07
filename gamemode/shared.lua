// Shared gamemode metadata and startup work executed in both server and client realms.
include("sh_player.lua")
include("sh_compass.lua")
include("utils/world.lua")
include("utils/safezone.lua")

GM.Name = "Z-Nation"
GM.Author = "N/A"
GM.Email = "N/A"
GM.Website = "N/A"

// Loads the city-data profile selected by the current map's optional zn_world_profile entity.
function GM:InitPostEntity()
	local loaded, loadError = ZM_World:LoadMapProfile()
	if not loaded then
		ErrorNoHalt("[ZombieSim] " .. loadError .. "\n")
	end
end