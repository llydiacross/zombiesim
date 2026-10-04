AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Use(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() or not ZM_DroppedItems then return end
    local picked, message = ZM_DroppedItems:Pickup(playerEntity, self)
    if message then
        playerEntity:ChatPrint("[Item Crate] " .. tostring(message))
    elseif picked then
        playerEntity:ChatPrint("[Item Crate] Picked up.")
    end
end
