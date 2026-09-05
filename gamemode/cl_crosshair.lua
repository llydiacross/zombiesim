hook.Add("HUDShouldDraw", "ZM.HideDefaultCrosshair", function(name)
    if name == "CHudCrosshair" then return false end
end)

hook.Remove("player_hurt", "ZM.PlayerDamageNotification")

local lastPlayerHealth

hook.Add("Think", "ZM.TrackPlayerDamage", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        lastPlayerHealth = nil
        return
    end

    local currentHealth = ply:Health()
    local damage = lastPlayerHealth and lastPlayerHealth - currentHealth or 0
    if damage > 0 then
        ZM_AddCrosshairNotification("-" .. damage .. " HP")
    end

    lastPlayerHealth = currentHealth
end)

hook.Add("HUDPaint", "ZM.CustomCrosshair", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if ZM_IsSelfieCamera() then return end

    local size = 4
    if ply:KeyDown(IN_SPEED) then
        size = math.floor(4 + (math.sin(CurTime() * 10) + 1) * 1.5)
    end

    local healthPercent = math.Clamp(ply:Health() / math.max(ply:GetMaxHealth(), 1), 0, 1)
    local red = math.floor((1 - healthPercent) * 255)
    local green = math.floor(healthPercent * 255)
    local alpha = 255
    if healthPercent <= 0.25 then
        alpha = math.floor(80 + (math.sin(CurTime() * 12) + 1) * 87.5)
    end

    local x = math.floor((ScrW() - size) * 0.5)
    local y = math.floor((ScrH() - size) * 0.5)

    surface.SetDrawColor(red, green, 0, alpha)
    surface.DrawRect(x, y, size, size)
end)
