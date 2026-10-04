local indicatorDuration = 0.95
local indicatorMergeWindow = 0.3
local maximumIndicators = 6
local damageIndicators = {}
local undirectedIndicator = { created = 0, intensity = 0 }
local directionalShadowTriangle = { {}, {}, {} }
local directionalTriangle = { {}, {}, {} }

local function setTriangle(triangle, tipX, tipY, directionX, directionY, size, offsetX, offsetY)
    local perpendicularX = -directionY
    local perpendicularY = directionX
    local baseX = tipX - directionX * size
    local baseY = tipY - directionY * size
    triangle[1].x = tipX + offsetX
    triangle[1].y = tipY + offsetY
    triangle[2].x = baseX + perpendicularX * size * 0.48 + offsetX
    triangle[2].y = baseY + perpendicularY * size * 0.48 + offsetY
    triangle[3].x = baseX - perpendicularX * size * 0.48 + offsetX
    triangle[3].y = baseY - perpendicularY * size * 0.48 + offsetY
end

local function addDamageIndicator(intensity, sourcePosition)
    local now = CurTime()
    if not sourcePosition then
        if now - undirectedIndicator.created <= indicatorMergeWindow then
            undirectedIndicator.intensity = math.min(1, undirectedIndicator.intensity + intensity * 0.55)
        else
            undirectedIndicator.intensity = intensity
        end
        undirectedIndicator.created = now
        return
    end

    for _, indicator in ipairs(damageIndicators) do
        if now - indicator.created <= indicatorMergeWindow and
            indicator.source:DistToSqr(sourcePosition) <= 384 * 384 then
            indicator.source = sourcePosition
            indicator.intensity = math.min(1, indicator.intensity + intensity * 0.55)
            indicator.created = now
            return
        end
    end

    if #damageIndicators >= maximumIndicators then
        table.remove(damageIndicators, 1)
    end
    table.insert(damageIndicators, {
        source = sourcePosition,
        intensity = intensity,
        created = now
    })
end

net.Receive("ZM.PlayerDamageFeedback", function()
    local intensity = math.Clamp(net.ReadFloat(), 0, 1)
    local sourcePosition
    if net.ReadBool() then
        sourcePosition = net.ReadVector()
    end
    if intensity > 0 then
        addDamageIndicator(intensity, sourcePosition)
    end
end)

local function drawDirectionalIndicator(player, indicator, alpha)
    local cameraAngles = ZM_GetScreenCameraAngles and ZM_GetScreenCameraAngles() or player:EyeAngles()
    local direction = indicator.source - player:GetPos()
    direction.z = 0
    if direction:LengthSqr() < 1 then
        return false
    end
    direction:Normalize()

    local screenX = direction:Dot(cameraAngles:Right())
    local screenY = -direction:Dot(cameraAngles:Up())
    local screenLength = math.sqrt(screenX * screenX + screenY * screenY)
    if screenLength < 0.2 then
        return false
    end
    screenX = screenX / screenLength
    screenY = screenY / screenLength

    local centerX, centerY = ScrW() * 0.5, ScrH() * 0.5
    local size = 17 + indicator.intensity * 13
    local radius = math.min(ScrH() * 0.29, ScrW() * 0.23)
    local rects = ZM_GetHudReservedRects and ZM_GetHudReservedRects() or {}
    local tipX, tipY
    for _ = 1, 6 do
        local candidateX = centerX + screenX * radius
        local candidateY = centerY + screenY * radius
        local blocked = false
        for _, rect in ipairs(rects) do
            if rect.w > 0 and rect.h > 0 and
                candidateX > rect.x - size - 8 and candidateX < rect.x + rect.w + size + 8 and
                candidateY > rect.y - size - 8 and candidateY < rect.y + rect.h + size + 8 then
                blocked = true
                break
            end
        end
        if not blocked then
            tipX, tipY = candidateX, candidateY
            break
        end
        radius = radius * 0.82
    end
    if not tipX then
        return false
    end

    local shadowAlpha = math.floor(alpha * 0.8)
    draw.NoTexture()
    setTriangle(directionalShadowTriangle, tipX, tipY, screenX, screenY, size + 2, 1, 2)
    surface.SetDrawColor(8, 7, 8, shadowAlpha)
    surface.DrawPoly(directionalShadowTriangle)
    setTriangle(directionalTriangle, tipX, tipY, screenX, screenY, size, 0, 0)
    surface.SetDrawColor(255, math.floor(55 + indicator.intensity * 28),
        math.floor(49 + indicator.intensity * 12), alpha)
    surface.DrawPoly(directionalTriangle)
    return true
end

hook.Add("HUDPaint", "ZM.PlayerDamageFeedback", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active or gui.IsGameUIVisible() or
        vgui.CursorVisible() or IsValid(vgui.GetKeyboardFocus()) then
        return
    end

    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() or ZM_SafeZones:IsPlayerInside(player) then
        return
    end

    local now = CurTime()
    local undirectedAge = now - undirectedIndicator.created
    if undirectedIndicator.intensity > 0 and undirectedAge < indicatorDuration then
        local fade = math.Clamp((indicatorDuration - undirectedAge) / 0.72, 0, 1)
        local alpha = math.floor((55 + undirectedIndicator.intensity * 120) * fade)
        surface.SetDrawColor(242, 53, 59, alpha)
        surface.DrawOutlinedRect(7, 7, ScrW() - 14, ScrH() - 14, 3)
    end

    for index = #damageIndicators, 1, -1 do
        local indicator = damageIndicators[index]
        local age = now - indicator.created
        if age >= indicatorDuration then
            table.remove(damageIndicators, index)
        else
            local fade = math.Clamp((indicatorDuration - age) / 0.72, 0, 1)
            local alpha = math.floor((65 + indicator.intensity * 150) * fade)
            if indicator.isUndirected then
                continue
            end
            if not drawDirectionalIndicator(player, indicator, alpha) then
                indicator.isUndirected = true
                undirectedIndicator.created = now
                undirectedIndicator.intensity = math.max(undirectedIndicator.intensity, indicator.intensity * 0.6)
            end
        end
    end
end)
