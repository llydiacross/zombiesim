// Short-lived messages shown around the crosshair, newest message nearest the center.
local getAllPlayers = player.GetAll
local crosshairNotifications = {}
local notificationDuration = 1
local notificationFadeDuration = 0.35
local minimapMaterials = {}
local minimapSatelliteMaterials = {}
local minimapCellHalfExtent = 1600
local minimapZoom = 1
local minimapZoomProfile
local minimapZoomInDown = false
local minimapZoomOutDown = false
local minimapViewModes = {}
local minimapModeDown = false
local compassCellSize = 3200
local compassMarkerLabels = {
    waypoint = "Waypoint",
    landmark = "Landmark",
    objective = "Objective",
    safezone = "Safe Zone",
    trader = "Trader",
    medical = "Medical",
    loot = "Loot",
    warning = "Warning"
}
local minimapColors = {
    black = Color(7, 8, 10),
    panel = Color(15, 17, 20),
    border = Color(114, 22, 31),
    health = Color(39, 181, 84),
    hunger = Color(157, 226, 20),
    thirst = Color(0, 176, 223),
    text = Color(236, 236, 238)
}

hook.Add("HUDShouldDraw", "ZM.SuppressDefaultSurvivalHud", function(hudName)
    if hudName == "CHudHealth" or hudName == "CHudBattery" then
        return false
    end
end)

// Dedicated notification font keeps combat feedback independent from the default HUD font.
surface.CreateFont("ZM_CrosshairNotification", {
    font = "Trebuchet24",
    size = 20,
    weight = 700,
})

surface.CreateFont("ZM_MinimapLabel", {
    font = "Trebuchet MS",
    size = 13,
    weight = 800,
    antialias = true
})

surface.CreateFont("ZM_CompassHeading", {
    font = "Trebuchet MS",
    size = 15,
    weight = 900,
    antialias = true
})

surface.CreateFont("ZM_CompassMarker", {
    font = "Trebuchet MS",
    size = 14,
    weight = 900,
    antialias = true
})

local function getHudPlayerCell(player)
    if not ZM_World or not ZM_World:IsLoaded() then
        return nil
    end

    local gridX, gridY = ZM_World:GetGridCoordinates(player:GetNWInt("CellX", 0), player:GetNWInt("CellY", 0))
    return gridX and ZM_World:GetCell(gridX, gridY) or nil
end

local function hasCurrentSafeZone(player)
    local safeZoneId = player:GetNWString("CurrentSafeZoneId", "")
    return safeZoneId ~= "" and safeZoneId ~= "NULL"
end

local function normalizeCompassAngle(angle)
    return (angle + 180) % 360 - 180
end

local function getCompassMarkerLabel(markerType, label)
    label = string.Trim(tostring(label or ""))
    if label ~= "" then
        return label
    end
    markerType = string.lower(tostring(markerType or "objective"))
    return compassMarkerLabels[markerType] or "Marker"
end

local function getCellCompassYaw(player, targetCell)
    local playerWorldX = player:GetNWInt("CellX", 0)
    local playerWorldY = player:GetNWInt("CellY", 0)
    local targetWorldX, targetWorldY = ZM_World:GetWorldCoordinates(targetCell)
    if targetWorldX == nil or targetWorldY == nil then
        return nil
    end

    local position = player:GetPos()
    local offsetX = (targetWorldX - playerWorldX) * compassCellSize - position.x
    local offsetY = (playerWorldY - targetWorldY) * compassCellSize - position.y
    if offsetX * offsetX + offsetY * offsetY < 2500 then
        return nil
    end

    return Vector(offsetX, offsetY, 0):Angle().y
end

local function getNearbyLandmarkCompassTargets(playerCell)
    local targets = {}
    local worldData = ZM_World:GetData()
    if not worldData then
        return targets
    end

    for _, cell in ipairs(worldData.cells or {}) do
        if #(cell.landmarks or {}) > 0 then
            local distance = math.abs(cell.x - playerCell.x) + math.abs(cell.y - playerCell.y)
            if distance <= 6 then
                table.insert(targets, { cell = cell, distance = distance })
            end
        end
    end
    table.sort(targets, function(left, right)
        return left.distance < right.distance
    end)

    while #targets > 5 do
        table.remove(targets)
    end
    return targets
end

local function drawCompassMarker(x, y, width, heading, targetYaw, icon, color)
    if not targetYaw then
        return
    end

    local relativeYaw = normalizeCompassAngle(targetYaw - heading)
    if math.abs(relativeYaw) > 95 then
        return
    end

    local markerX = x + width * 0.5 + relativeYaw / 95 * (width * 0.5 - 12)
    surface.SetDrawColor(color.r, color.g, color.b, 255)
    surface.DrawRect(markerX - 1, y + 4, 3, 19)
    draw.SimpleText(icon, "ZM_CompassMarker", markerX, y + 25, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

local function drawPlayerCompass()
    local player = LocalPlayer()
    if not IsValid(player) or not ZM_World or not ZM_World:IsLoaded() then
        return
    end

    local width = math.min(500, ScrW() - 40)
    local height = 51
    local x = math.floor((ScrW() - width) * 0.5)
    local y = 18
    local heading = player:EyeAngles().y
    local playerCell = getHudPlayerCell(player)
    local isInDen = hasCurrentSafeZone(player)

    surface.SetDrawColor(7, 8, 10, 235)
    surface.DrawRect(x, y, width, height)
    surface.SetDrawColor(114, 22, 31, 255)
    surface.DrawOutlinedRect(x, y, width, height, 1)
    surface.SetDrawColor(173, 28, 43, 255)
    surface.DrawRect(x + width * 0.5 - 1, y, 3, height)

    local compassDirections = {
        { yaw = 90, label = "N" },
        { yaw = 0, label = "E" },
        { yaw = -90, label = "S" },
        { yaw = 180, label = "W" }
    }
    for _, direction in ipairs(compassDirections) do
        local relativeYaw = normalizeCompassAngle(direction.yaw - heading)
        if math.abs(relativeYaw) <= 105 then
            local tickX = x + width * 0.5 + relativeYaw / 105 * (width * 0.5 - 10)
            surface.SetDrawColor(181, 188, 194, 210)
            surface.DrawRect(tickX, y + 5, 1, 8)
            draw.SimpleText(direction.label, "ZM_CompassHeading", tickX, y + 14, minimapColors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end

    if not isInDen and playerCell and ZM_WorldMap and ZM_WorldMap.WaypointCell and ZM_WorldMap.WaypointProfile == ZM_World.ActiveProfile then
        drawCompassMarker(x, y, width, heading, getCellCompassYaw(player, ZM_WorldMap.WaypointCell), getCompassMarkerLabel("waypoint"), Color(246, 210, 48))
    end
    if not isInDen and playerCell then
        for _, target in ipairs(getNearbyLandmarkCompassTargets(playerCell)) do
            drawCompassMarker(x, y, width, heading, getCellCompassYaw(player, target.cell), getCompassMarkerLabel("landmark"), Color(52, 220, 176))
        end
    end
    for _, entity in ipairs(ents.GetAll()) do
        local marker = IsValid(entity) and entity:GetZMCompassMarker() or nil
        if marker then
            local offset = entity:WorldSpaceCenter() - player:EyePos()
            if offset:LengthSqr() > 2500 then
                drawCompassMarker(x, y, width, heading, offset:Angle().y, getCompassMarkerLabel(marker.icon, marker.label), Color(239, 57, 72))
            end
        end
    end
end

hook.Add("HUDPaint", "ZM.PlayerCompass", drawPlayerCompass)

local function getMinimapCellMaterial(cell)
    if not cell or type(cell.map) ~= "string" or cell.map == "" or not ZM_World then
        return nil
    end

    local profile = ZM_World.ActiveProfile or "city"
    local key = profile .. "/" .. cell.map
    if not minimapMaterials[key] then
        minimapMaterials[key] = Material("worlds/" .. profile .. "/cells/" .. cell.map .. ".png", "smooth")
    end
    return minimapMaterials[key]
end

local function getCellTextureCoordinates(position)
    local cellSpan = minimapCellHalfExtent * 2
    return math.Clamp((position.x + minimapCellHalfExtent) / cellSpan, 0, 1),
        math.Clamp((minimapCellHalfExtent - position.y) / cellSpan, 0, 1)
end

local function getMinimapViewMode(isInSafeZone)
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local context = isInSafeZone and "safezone" or "world"
    local key = profile .. "/" .. context
    if not minimapViewModes[key] then
        local defaultMode = isInSafeZone and "map" or "cell"
        local savedMode = cookie.GetString("zombiesim_minimap_" .. profile .. "_" .. context .. "_mode", defaultMode)
        if isInSafeZone then
            minimapViewModes[key] = savedMode == "blank" and "blank" or "map"
        else
            minimapViewModes[key] = savedMode == "map" and "map" or "cell"
        end
    end
    return minimapViewModes[key]
end

local function setMinimapViewMode(isInSafeZone, mode)
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local context = isInSafeZone and "safezone" or "world"
    minimapViewModes[profile .. "/" .. context] = mode
    cookie.Set("zombiesim_minimap_" .. profile .. "_" .. context .. "_mode", mode)
end

local function drawCellTextureMinimap(x, y, width, height, cell, position, zoom)
    local material = getMinimapCellMaterial(cell)
    if not material or material:IsError() then
        return false
    end

    local cellOffsetU, cellOffsetV = getCellTextureCoordinates(position)
    local viewCellHeight = 0.46 / zoom
    local viewCellWidth = viewCellHeight * width / height
    local viewU = math.min(0.88, viewCellWidth)
    local viewV = math.min(1, viewCellHeight)
    local startU = math.Clamp(cellOffsetU - viewU * 0.5, 0, 1 - viewU)
    local startV = math.Clamp(cellOffsetV - viewV * 0.5, 0, 1 - viewV)
    surface.SetMaterial(material)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(x, y, width, height, startU, startV, startU + viewU, startV + viewV)
    return true, {
        startU = startU,
        startV = startV,
        viewU = viewU,
        viewV = viewV
    }
end

local function projectCellTexturePosition(x, y, width, height, position, transform)
    local cellOffsetU, cellOffsetV = getCellTextureCoordinates(position)
    return x + (cellOffsetU - transform.startU) / transform.viewU * width,
        y + (cellOffsetV - transform.startV) / transform.viewV * height
end

local function getMinimapZoom()
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    if minimapZoomProfile ~= profile then
        minimapZoomProfile = profile
        minimapZoom = math.Clamp(tonumber(cookie.GetString("zombiesim_minimap_" .. profile .. "_zoom", "")) or 1, 0.5, 4)
    end
    return minimapZoom
end

local function changeMinimapZoom(factor)
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local zoom = getMinimapZoom()
    minimapZoom = math.Clamp(zoom * factor, 0.5, 4)
    cookie.Set("zombiesim_minimap_" .. profile .. "_zoom", tostring(minimapZoom))
end

local function drawMinimapBar(x, y, width, height, label, value, color)
    local intensity = math.Clamp(tonumber(value) or 0, 0, 1)
    local isLow = intensity <= 0.25
    local alertAlpha = math.floor(125 + (math.sin(CurTime() * 8) + 1) * 65)
    local borderColor = isLow and Color(239, 57, 72, alertAlpha) or color
    surface.SetDrawColor(4, 5, 6, 255)
    surface.DrawRect(x, y, width, height)
    surface.SetDrawColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 255)
    surface.DrawOutlinedRect(x, y, width, height, 2)
    if intensity > 0 then
        surface.SetDrawColor(color.r, color.g, color.b, 255)
        surface.DrawRect(x + 3, y + height - 7, math.max(1, math.floor((width - 6) * intensity)), 4)
    end
    draw.SimpleText(label, "ZM_MinimapLabel", x + width * 0.5, y + 4, minimapColors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

local function drawMinimapCardinalDirections(x, y, width, height)
    local top, right, bottom, left = "N", "E", "S", "W"

    local color = Color(244, 244, 246, 235)
    draw.SimpleText(top, "ZM_MinimapLabel", x + width * 0.5, y + 2, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    draw.SimpleText(right, "ZM_MinimapLabel", x + width - 3, y + height * 0.5, color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(bottom, "ZM_MinimapLabel", x + width * 0.5, y + height - 2, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(left, "ZM_MinimapLabel", x + 3, y + height * 0.5, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function drawOtherPlayerMinimapMarker(mapX, mapY, mapWidth, mapHeight, markerX, markerY, otherPlayer)
    if markerX < mapX or markerX > mapX + mapWidth or markerY < mapY or markerY > mapY + mapHeight then
        return
    end

    surface.SetDrawColor(8, 20, 13, 255)
    surface.DrawRect(markerX - 5, markerY - 5, 10, 10)
    surface.SetDrawColor(236, 255, 241, 255)
    surface.DrawOutlinedRect(markerX - 4, markerY - 4, 8, 8, 1)
    surface.SetDrawColor(52, 220, 176, 255)
    surface.DrawRect(markerX - 2, markerY - 2, 4, 4)
    draw.SimpleText(
        otherPlayer:Nick(),
        "ZM_MinimapLabel",
        math.Clamp(markerX, mapX + 4, mapX + mapWidth - 4),
        math.max(mapY + 12, markerY - 7),
        Color(52, 220, 176, 255),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_BOTTOM
    )
end

local function drawPlayerMinimap()
    local player = LocalPlayer()
    if not IsValid(player) then return end

    local margin = 20
    local width = math.min(230, ScrW() - margin * 2)
    local mapHeight = math.floor(width * 0.62)
    local barAreaHeight = 76
    local height = mapHeight + barAreaHeight
    local x = margin
    local y = ScrH() - height - margin
    local mapX = x + 8
    local mapY = y + 8
    local mapWidth = width - 16
    local mapBottom = mapY + mapHeight

    surface.SetDrawColor(minimapColors.black.r, minimapColors.black.g, minimapColors.black.b, 238)
    surface.DrawRect(x, y, width, height)
    surface.SetDrawColor(minimapColors.border.r, minimapColors.border.g, minimapColors.border.b, 255)
    surface.DrawOutlinedRect(x, y, width, height, 2)
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(mapX, mapY, mapWidth, mapHeight)

    local isInDen = hasCurrentSafeZone(player)
    local cell = not isInDen and getHudPlayerCell(player) or nil
    local position = player:GetPos()
    local zoom = getMinimapZoom()
    local minimapViewMode = getMinimapViewMode(isInDen)
    local drewMap = false
    local cellTextureTransform
    local localMapViewHeight = minimapCellHalfExtent * 2 * 0.46 / zoom
    if minimapViewMode == "map" and ZM_WorldMap and ZM_WorldMap.EnsureLocalMapCapture and ZM_WorldMap.DrawLocalMap then
        if ZM_WorldMap:EnsureLocalMapCapture() then
            drewMap = ZM_WorldMap:DrawLocalMap(
                mapX,
                mapY,
                mapWidth,
                mapHeight,
                position,
                localMapViewHeight
            )
        end
    end
    if not drewMap and not isInDen then
        drewMap, cellTextureTransform = drawCellTextureMinimap(mapX, mapY, mapWidth, mapHeight, cell, position, zoom)
    end
    if drewMap then
        local playerMarkerX, playerMarkerY = mapX + mapWidth * 0.5, mapY + mapHeight * 0.5
        if cellTextureTransform then
            playerMarkerX, playerMarkerY = projectCellTexturePosition(mapX, mapY, mapWidth, mapHeight, position, cellTextureTransform)
        end
        surface.SetDrawColor(7, 8, 10, 255)
        surface.DrawRect(playerMarkerX - 6, playerMarkerY - 6, 12, 12)
        surface.SetDrawColor(244, 244, 246, 255)
        surface.DrawOutlinedRect(playerMarkerX - 4, playerMarkerY - 4, 8, 8, 1)
        surface.SetDrawColor(minimapColors.health.r, minimapColors.health.g, minimapColors.health.b, 255)
        surface.DrawRect(playerMarkerX - 2, playerMarkerY - 2, 4, 4)

        for _, otherPlayer in ipairs(getAllPlayers()) do
            if otherPlayer ~= player and IsValid(otherPlayer) and otherPlayer:Alive() then
                local otherX, otherY
                if minimapViewMode == "map" and ZM_WorldMap and ZM_WorldMap.ProjectLocalMapPosition then
                    otherX, otherY = ZM_WorldMap:ProjectLocalMapPosition(
                        mapX,
                        mapY,
                        mapWidth,
                        mapHeight,
                        position,
                        localMapViewHeight,
                        otherPlayer:GetPos()
                    )
                elseif cellTextureTransform then
                    otherX, otherY = projectCellTexturePosition(mapX, mapY, mapWidth, mapHeight, otherPlayer:GetPos(), cellTextureTransform)
                end
                if otherX and otherY then
                    drawOtherPlayerMinimapMarker(mapX, mapY, mapWidth, mapHeight, otherX, otherY, otherPlayer)
                end
            end
        end
    else
        surface.SetDrawColor(0, 0, 0, 118)
        surface.DrawRect(mapX, mapY, mapWidth, mapHeight)
    end
    drawMinimapCardinalDirections(mapX, mapY, mapWidth, mapHeight)
    surface.SetDrawColor(minimapColors.border.r, minimapColors.border.g, minimapColors.border.b, 255)
    surface.DrawOutlinedRect(mapX, mapY, mapWidth, mapHeight, 1)

    local barGap = 4
    local splitBarWidth = math.floor((mapWidth - barGap) * 0.5)
    local meterHeight = 24
    local health = math.max(player:Health(), 0)
    drawMinimapBar(mapX, mapBottom + 7, splitBarWidth, meterHeight, "FOOD", player:GetNWFloat("Hunger", 100) / 100, minimapColors.hunger)
    drawMinimapBar(mapX + splitBarWidth + barGap, mapBottom + 7, mapWidth - splitBarWidth - barGap, meterHeight, "THIRST", player:GetNWFloat("Thirst", 100) / 100, minimapColors.thirst)
    drawMinimapBar(mapX, mapBottom + 35, mapWidth, meterHeight, "+ " .. health, health / math.max(player:GetMaxHealth(), 1), minimapColors.health)
end

hook.Add("HUDPaint", "ZM.PlayerMinimap", drawPlayerMinimap)

hook.Add("Think", "ZM.PlayerMinimap.Zoom", function()
    local hasKeyboardFocus = IsValid(vgui.GetKeyboardFocus())
    local isShiftDown = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
    local isZoomInDown = (isShiftDown and input.IsKeyDown(KEY_EQUAL)) or (KEY_PAD_PLUS and input.IsKeyDown(KEY_PAD_PLUS))
    local isZoomOutDown = input.IsKeyDown(KEY_MINUS) or (KEY_PAD_MINUS and input.IsKeyDown(KEY_PAD_MINUS))
    if not gui.IsGameUIVisible() and not hasKeyboardFocus then
        if isZoomInDown and not minimapZoomInDown then
            changeMinimapZoom(1.2)
        elseif isZoomOutDown and not minimapZoomOutDown then
            changeMinimapZoom(1 / 1.2)
        end
    end
    minimapZoomInDown = isZoomInDown
    minimapZoomOutDown = isZoomOutDown
end)

hook.Add("Think", "ZM.PlayerMinimap.Mode", function()
    local isControlDown = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
    local isDown = isControlDown and input.IsKeyDown(KEY_M)
    local isMapOpen = ZM_WorldMap and IsValid(ZM_WorldMap.Frame)
    if isDown and not minimapModeDown and not isMapOpen and not gui.IsGameUIVisible() and not IsValid(vgui.GetKeyboardFocus()) then
        local player = LocalPlayer()
        if IsValid(player) then
            local isInSafeZone = hasCurrentSafeZone(player)
            local currentMode = getMinimapViewMode(isInSafeZone)
            local targetMode
            if isInSafeZone then
                targetMode = currentMode == "map" and "blank" or "map"
            else
                targetMode = currentMode == "map" and "cell" or "map"
            end
            if targetMode ~= "map" or ZM_WorldMap and ZM_WorldMap:EnsureLocalMapCapture() then
                setMinimapViewMode(isInSafeZone, targetMode)
            end
        end
    end
    minimapModeDown = isDown
end)

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
