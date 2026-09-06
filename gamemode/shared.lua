// Shared gamemode metadata and startup work executed in both server and client realms.
include("sh_player.lua")
include("utils/world.lua")
include("utils/safezone.lua")

GM.Name = "Z-Nation"
GM.Author = "N/A"
GM.Email = "N/A"
GM.Website = "N/A"

// Loads the packaged production world index. Failure is logged instead of aborting the gamemode,
// allowing development maps to start before the release data has been generated.
function GM:Initialize()
	local loaded, loadError = ZM_World:Load()
	if not loaded then
		ErrorNoHalt("[ZombieSim] " .. loadError .. "\n")
	end
end