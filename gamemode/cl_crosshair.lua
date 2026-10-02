// Aim-point crosshair: a circle where a level shot from the centre of mass lands (see ply:GetLevelAim).
// Player status UI (stamina, damage) is drawn above the player in cl_hud.lua, independent of aiming.

// Suppresses the Source crosshair because ZM.CustomCrosshair draws the gameplay replacement.
hook.Add("HUDShouldDraw", "ZM.HideDefaultCrosshair", function(name)
    if name == "CHudCrosshair" then return false end
    if name == "CHudWeaponSelection" and ZM_SafeZones:IsPlayerInside(LocalPlayer()) then return false end
end)

hook.Add("PreDrawPlayerHands", "ZM.DenHolsterHands", function(_, _, ply)
    if ZM_SafeZones:IsPlayerInside(ply) then return true end
end)

// Remove the legacy event notifier; damage is tracked by ZM.TrackPlayerDamage in cl_hud.lua.
hook.Remove("player_hurt", "ZM.PlayerDamageNotification")

local screenMargin = 24
local panelPadding = 8
local clipSearchSteps = 12

// True when a screen point is on screen, inside the margin, and clear of the fixed HUD panels.
local function isInsidePlayArea(screen, radius)
    if not screen.visible then
        return false
    end
    local inset = screenMargin + radius
    if screen.x < inset or screen.y < inset or screen.x > ScrW() - inset or screen.y > ScrH() - inset then
        return false
    end
    local reach = panelPadding + radius
    for _, rect in ipairs(ZM_GetHudReservedRects and ZM_GetHudReservedRects() or {}) do
        if screen.x > rect.x - reach and screen.x < rect.x + rect.w + reach and
            screen.y > rect.y - reach and screen.y < rect.y + rect.h + reach then
            return false
        end
    end
    return true
end

// Returns the screen position of the aim point, pulled back along the shot line to the farthest point
// that stays inside the play area. Returns nil when even the player's own position is outside it.
local function getClippedAimScreenPos(ply, radius)
    local origin = ply:GetLevelAim()
    local hitPos = ply:GetLevelAimTrace().HitPos
    // A degenerate hitbox can return a NaN hit position (NaN ~= NaN); fall back to the shot origin.
    if hitPos.x ~= hitPos.x or hitPos.y ~= hitPos.y or hitPos.z ~= hitPos.z then
        hitPos = origin
    end
    local hitScreen = hitPos:ToScreen()
    if isInsidePlayArea(hitScreen, radius) then
        return hitScreen.x, hitScreen.y
    end
    if not isInsidePlayArea(origin:ToScreen(), radius) then
        return nil
    end
    local inside, outside = 0, 1
    for _ = 1, clipSearchSteps do
        local middle = (inside + outside) * 0.5
        if isInsidePlayArea(LerpVector(middle, origin, hitPos):ToScreen(), radius) then
            inside = middle
        else
            outside = middle
        end
    end
    local clipped = LerpVector(inside, origin, hitPos):ToScreen()
    return clipped.x, clipped.y
end

// Draws a health-colored ring. Sprinting animates its radius; low health pulses alpha.
// In the locked camera a white cross also marks the mouse aim cursor the player turns toward.
hook.Add("HUDPaint", "ZM.CustomCrosshair", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or ZM_SafeZones:IsPlayerInside(ply) then return end

    local cursorX, cursorY
    if ZM_GetAimCursor then
        cursorX, cursorY = ZM_GetAimCursor()
    end
    if cursorX and cursorY then
        cursorX, cursorY = math.floor(cursorX), math.floor(cursorY)
        surface.SetDrawColor(0, 0, 0, 160)
        surface.DrawRect(cursorX - 6, cursorY - 1, 13, 3)
        surface.DrawRect(cursorX - 1, cursorY - 6, 3, 13)
        surface.SetDrawColor(255, 255, 255, 230)
        surface.DrawRect(cursorX - 5, cursorY, 11, 1)
        surface.DrawRect(cursorX, cursorY - 5, 1, 11)
    end

    local radius = 6
    if ply:KeyDown(IN_SPEED) then
        radius = 6 + (math.sin(CurTime() * 10) + 1) * 1.5
    end

    local x, y
    if ZM_IsInDenCamera and ZM_IsInDenCamera() then
        // First-person den camera: the crosshair is fixed at screen centre and turns with the view.
        x, y = ScrW() * 0.5, ScrH() * 0.5
    else
        x, y = getClippedAimScreenPos(ply, radius)
    end
    if not x then return end

    local healthPercent = math.Clamp(ply:Health() / math.max(ply:GetMaxHealth(), 1), 0, 1)
    local alpha = 255
    if healthPercent <= 0.25 then
        alpha = math.floor(80 + (math.sin(CurTime() * 12) + 1) * 87.5)
    end
    local red = math.floor((1 - healthPercent) * 255)
    local green = math.floor(healthPercent * 255)

    x, y = math.floor(x), math.floor(y)
    surface.DrawCircle(x, y, radius + 1, 0, 0, 0, math.floor(alpha * 0.6))
    surface.DrawCircle(x, y, radius, red, green, 0, alpha)
end)
