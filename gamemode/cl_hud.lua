// Short-lived messages shown around the crosshair, newest message nearest the center.
local crosshairNotifications = {}
local notificationDuration = 1
local notificationFadeDuration = 0.35

// Dedicated notification font keeps combat feedback independent from the default HUD font.
surface.CreateFont("ZM_CrosshairNotification", {
    font = "Trebuchet24",
    size = 20,
    weight = 700,
})

// Queues a message that HUDPaint will fade and remove after notificationDuration seconds.
function ZM_AddCrosshairNotification(text)
    table.insert(crosshairNotifications, {
        text = tostring(text),
        created = CurTime(),
    })
end

// Draws queued notifications in reverse order so expired messages can be removed safely.
hook.Add("HUDPaint", "ZM.CrosshairNotifications", function()
    local now = CurTime()
    local y = ScrH() * 0.5 - 28
    local index = 1

    for notificationIndex = #crosshairNotifications, 1, -1 do
        local notification = crosshairNotifications[notificationIndex]
        local age = now - notification.created

        if age >= notificationDuration then
            table.remove(crosshairNotifications, notificationIndex)
        else
            local alpha = 255
            if age > notificationDuration - notificationFadeDuration then
                alpha = math.floor(255 * (notificationDuration - age) / notificationFadeDuration)
            end

            draw.SimpleText(
                notification.text,
                "ZM_CrosshairNotification",
                ScrW() * 0.5,
                y - (index - 1) * 22,
                Color(255, 255, 255, alpha),
                TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER
            )
            index = index + 1
        end
    end
end)

// Draws stamina only while sprinting or recovering, and hides it in the selfie camera view.
hook.Add("HUDPaint", "ZM.StaminaBar", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if ZM_IsSelfieCamera() then return end

    local stamina = ply:GetNWFloat("Stamina", 100)
    local maxStamina = math.max(ply:GetNWFloat("MaxStamina", 100), 1)
    local staminaPercent = math.Clamp(stamina / maxStamina, 0, 1)
    local isUsingStamina = ply:KeyDown(IN_SPEED) or staminaPercent < 1
    if not isUsingStamina then return end

    local barWidth = 80
    local barHeight = 5
    local barX = math.floor((ScrW() - barWidth) * 0.5)
    local barY = math.floor(ScrH() * 0.5 + 8)
    local alpha = 255
    if staminaPercent <= 0.1 then
        alpha = math.floor(80 + (math.sin(CurTime() * 14) + 1) * 87.5)
    end

    local barColor = HSVToColor(staminaPercent * 120, 0.9, 0.9)
    surface.SetDrawColor(20, 20, 20, alpha)
    surface.DrawRect(barX, barY, barWidth, barHeight)
    surface.SetDrawColor(barColor.r, barColor.g, barColor.b, alpha)
    surface.DrawRect(barX, barY, math.floor(barWidth * staminaPercent), barHeight)
end)
