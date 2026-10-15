local toggleNetMessage = "ZM.ChestLamp.Toggle"
local enabledNetworkKey = "ZM_ChestLampEnabled"
local toggleCooldown = 0.25

util.AddNetworkString(toggleNetMessage)

local function IsGameplayCell()
    return ZM_World and ZM_World.ActiveProfile ~= nil and game.GetMap():match("^zz_") ~= nil
end

local function SetChestLampEnabled(target, enabled)
    target:SetNWBool(enabledNetworkKey, enabled)
    target.ZMChestLampLastToggle = CurTime()
    target:ChatPrint(enabled and "Chest lamp on." or "Chest lamp off.")
end

net.Receive(toggleNetMessage, function(_, target)
    if not IsValid(target) or not target:Alive() or not IsGameplayCell() then return end

    local now = CurTime()
    if now - (target.ZMChestLampLastToggle or 0) < toggleCooldown then return end
    local enabled = not target:GetNWBool(enabledNetworkKey, false)
    if enabled and target:LookupBone("ValveBiped.Bip01_Spine2") == nil then
        target:ChatPrint("This survivor model has no chest lamp attachment point.")
        return
    end
    SetChestLampEnabled(target, enabled)
end)

hook.Add("PlayerSwitchFlashlight", "ZM.ChestLamp.ReplaceNativeFlashlight", function(target, enabled)
    if enabled and IsValid(target) and IsGameplayCell() then
        return false
    end
end)

hook.Add("PlayerDeath", "ZM.ChestLamp.TurnOffOnDeath", function(target)
    if IsValid(target) and target:GetNWBool(enabledNetworkKey, false) then
        SetChestLampEnabled(target, false)
    end
end)
