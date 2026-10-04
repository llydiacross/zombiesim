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
    local aimTrace = ply:GetLevelAimTrace()
    local hitPos = aimTrace.HitPos
    // A degenerate hitbox can return a NaN hit position (NaN ~= NaN); fall back to the shot origin.
    if hitPos.x ~= hitPos.x or hitPos.y ~= hitPos.y or hitPos.z ~= hitPos.z then
        hitPos = origin
    end
    local hitScreen = hitPos:ToScreen()
    if isInsidePlayArea(hitScreen, radius) then
        return hitScreen.x, hitScreen.y, aimTrace
    end
    if not isInsidePlayArea(origin:ToScreen(), radius) then
        return nil, nil, aimTrace
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
    return clipped.x, clipped.y, aimTrace
end

local crosshairColors = {
    neutral = Color(196, 202, 208, 225),
    interactable = Color(255, 207, 82, 245),
    enemy = Color(255, 72, 63, 250)
}
local enemyTickDirections = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
local enemyClasses = {
    zn_walker_zombie = true,
    zn_boss_zombie = true
}
local droppedItemUseRange = 160

local function getCrosshairTargetKind(player, aimTrace)
    local target = aimTrace and aimTrace.Entity
    if not IsValid(target) then
        return "neutral"
    end

    if enemyClasses[target:GetClass()] and target:Health() > 0 then
        return "enemy"
    end

    local lootTarget = ZM_LootPopup and ZM_LootPopup.Target
    if lootTarget and lootTarget.entity == target and lootTarget.aimed and not lootTarget.reason then
        return "interactable"
    end
    if target:GetClass() == "zn_dropped_item" and target:GetNWString("ZM_DropItemName", "") ~= "" and
        target:GetNWInt("ZM_DropItemCount", 0) > 0 and
        target:GetPos():DistToSqr(player:GetPos()) <= droppedItemUseRange * droppedItemUseRange then
        return "interactable"
    end
    return "neutral"
end

// Sprinting animates the ring; target color is independent of player health.
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

    local x, y, aimTrace
    if ZM_IsInDenCamera and ZM_IsInDenCamera() then
        // First-person den camera: the crosshair is fixed at screen centre and turns with the view.
        x, y = ScrW() * 0.5, ScrH() * 0.5
    else
        x, y, aimTrace = getClippedAimScreenPos(ply, radius)
    end
    if not x then return end

    local targetKind = getCrosshairTargetKind(ply, aimTrace)
    local targetColor = crosshairColors[targetKind]
    x, y = math.floor(x), math.floor(y)
    surface.DrawCircle(x, y, radius + 1, 0, 0, 0, 190)
    surface.DrawCircle(x, y, radius, targetColor.r, targetColor.g, targetColor.b, targetColor.a)
    if targetKind == "interactable" then
        surface.SetDrawColor(0, 0, 0, 190)
        surface.DrawOutlinedRect(x - 2, y - 2, 5, 5, 1)
        surface.SetDrawColor(targetColor)
        surface.DrawOutlinedRect(x - 2, y - 2, 5, 5, 1)
    elseif targetKind == "enemy" then
        local tickInner, tickOuter = radius + 3, radius + 7
        surface.SetDrawColor(0, 0, 0, 190)
        for _, direction in ipairs(enemyTickDirections) do
            surface.DrawLine(x + direction[1] * tickInner, y + direction[2] * tickInner,
                x + direction[1] * tickOuter, y + direction[2] * tickOuter)
        end
        surface.SetDrawColor(targetColor)
        for _, direction in ipairs(enemyTickDirections) do
            surface.DrawLine(x + direction[1] * tickInner, y + direction[2] * tickInner,
                x + direction[1] * tickOuter, y + direction[2] * tickOuter)
        end
    end
end)
