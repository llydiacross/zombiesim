// Short-lived messages shown above the local player's head, newest message nearest the player.
local getAllPlayers = player.GetAll
local playerNotifications = {}
local hudEventNotifications = {}
local notificationDuration = 1
local notificationFadeDuration = 0.35
local hudEventDuration = 3.5
local hudEventFadeDuration = 0.5
local maximumPlayerNotifications = 6
local maximumHudEventNotifications = 4
local hudWeaponIconPanel
local hudWeaponIconKey
local enemyHitMarkerExpires = 0
local enemyHitMarkerSoundAt = 0
local compassHeightScale = CreateClientConVar("zombiesim_compass_height", "0.55", true, false,
    "Compass height multiplier (0.55 to 1.5).")
local minimapSizeScale = CreateClientConVar("zombiesim_minimap_size", "1", true, false,
    "Minimap size multiplier (0.7 to 1.75).")
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
local denNpcColor = Color(222, 184, 84)
local compassMarkerLabels = {
    waypoint = "Waypoint",
    objective = "Objective",
    safezone = "Safe Zone",
    trader = "Trader",
    medical = "Medical",
    loot = "Loot",
    warning = "Warning"
}
local waypointDirectionYaw = { N = 90, E = 0, S = -90, W = 180 }
local compassLandmarkStyles = {
    ["Airport"] = { color = Color(83, 177, 224), priority = 60 },
    ["Army Base"] = { color = Color(222, 72, 65), priority = 95 },
    ["Bank"] = { color = Color(232, 190, 61), priority = 50 },
    ["Bunker"] = { color = Color(151, 161, 171), priority = 90 },
    ["Church"] = { color = Color(181, 125, 218), priority = 40 },
    ["Fire"] = { color = Color(239, 112, 48), priority = 75 },
    ["Hospital"] = { color = Color(60, 212, 183), priority = 85 },
    ["Laboratory"] = { color = Color(134, 124, 226), priority = 80 },
    ["Leisure"] = { color = Color(218, 112, 170), priority = 25 },
    ["Market"] = { color = Color(221, 156, 58), priority = 35 },
    ["Park"] = { color = Color(95, 195, 104), priority = 20 },
    ["Petrol Station"] = { color = Color(238, 144, 47), priority = 65 },
    ["Police"] = { color = Color(84, 144, 224), priority = 70 },
    ["The Epicenter"] = { color = Color(191, 231, 62), priority = 100 }
}
local compassLandmarkFallbackColor = Color(52, 220, 176)
local compassLandmarkTargetCache = {}
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
    if hudName == "CHudHealth" or hudName == "CHudBattery" or hudName == "CHudAmmo" or hudName == "CHudSecondaryAmmo" then
        return false
    end
end)

// Dedicated notification font keeps combat feedback independent from the default HUD font.
surface.CreateFont("ZM_PlayerNotification", {
    font = "Trebuchet MS",
    size = 20,
    weight = 700,
})

surface.CreateFont("ZM_HudEventNotification", {
    font = "Trebuchet MS",
    size = 22,
    weight = 900,
    antialias = true
})

surface.CreateFont("ZM_MinimapLabel", {
    font = "Trebuchet MS",
    size = 13,
    weight = 800,
    antialias = true
})

surface.CreateFont("ZM_WeaponHudName", {
    font = "Trebuchet MS",
    size = 18,
    weight = 700,
    antialias = true
})

surface.CreateFont("ZM_WeaponHudValue", {
    font = "Trebuchet MS",
    size = 28,
    weight = 800,
    antialias = true
})

surface.CreateFont("ZM_WeaponHudReserve", {
    font = "Trebuchet MS",
    size = 16,
    weight = 700,
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

local function drawWeaponHudBullets(x, y, width, count, maxCount, active)
    if maxCount <= 0 then
        return
    end

    local columns = math.min(20, maxCount)
    local spacing = math.floor(width / columns)
    local bulletWidth = math.max(2, spacing - 2)
    for index = 1, maxCount do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        if index <= count then
            surface.SetDrawColor(active and 255 or 210, active and 210 or 170, 100, 240)
        else
            surface.SetDrawColor(65, 69, 72, 220)
        end
        surface.DrawRect(x + column * spacing, y + row * 10, bulletWidth, 7)
    end
end

local function getHudAmmoAndDefinition(weapon)
    local inventory = ZM_Inventory and ZM_Inventory.Snapshot
    local instanceId = weapon.GetItemInstanceId and weapon:GetItemInstanceId()
    if not inventory or not instanceId or instanceId == "" then
        return nil, nil
    end
    for _, instance in ipairs(inventory.equippedItems or {}) do
        if instance.instanceId == instanceId then
            local definition = ZM_Items:GetDefinition(instance.itemId)
            if not definition or not definition.ammoId then return nil, definition end
            local reserve = 0
            for _, item in ipairs(inventory.backpack or {}) do
                if item.itemId == definition.ammoId then
                    reserve = reserve + (tonumber(item.count) or 0)
                end
            end
            return reserve, definition
        end
    end
    return nil, nil
end

// Static per-weapon HUD data (definition, name, reserve, slot) only changes with the inventory snapshot,
// so it is cached per weapon; clip values are refreshed every frame.
local hudWeaponEntryCache = setmetatable({}, { __mode = "k" })
local hudWeaponEntries = {}
local hudOtherWeaponEntries = {}

local function compareHudWeaponEntries(left, right)
    if left.active ~= right.active then
        return left.active
    end
    return left.name == right.name and left.className < right.className or left.name < right.name
end

local function getHudWeaponEntry(player, weapon, snapshot)
    local instanceId = weapon.GetItemInstanceId and weapon:GetItemInstanceId()
    local entry = hudWeaponEntryCache[weapon]
    if entry and entry.snapshot == snapshot and entry.instanceId == instanceId then
        return entry
    end

    local className = weapon:GetClass() or ""
    local reserveAmmo, definition = getHudAmmoAndDefinition(weapon)
    local name = definition and definition.name or weapon:GetPrintName()
    local selectionSlot
    for slot = 1, 3 do
        local loadout = snapshot and snapshot.weaponSlots and snapshot.weaponSlots[slot]
        if instanceId and instanceId ~= "" and loadout and loadout.instanceId == instanceId then
            selectionSlot = slot
            break
        end
    end
    entry = {
        snapshot = snapshot,
        instanceId = instanceId,
        className = className,
        selectionSlot = selectionSlot,
        iconKey = className .. ":" .. tostring(instanceId or ""),
        name = name and name ~= "" and name or className,
        inventoryReserve = reserveAmmo,
        definition = definition
    }
    hudWeaponEntryCache[weapon] = entry
    return entry
end

local function getHudWeaponEntries(player)
    local entries = hudWeaponEntries
    table.Empty(entries)
    if not IsValid(player) then
        return entries
    end

    local activeWeapon = player:GetActiveWeapon()
    local snapshot = ZM_Inventory and ZM_Inventory.Snapshot
    for _, weapon in ipairs(player:GetWeapons() or {}) do
        if IsValid(weapon) and (weapon:GetClass() or "") ~= "" then
            local entry = getHudWeaponEntry(player, weapon, snapshot)
            local maxClip = tonumber(weapon.GetMaxClip and weapon:GetMaxClip() or weapon:GetMaxClip1()) or -1
            local reserveAmmo = entry.inventoryReserve
            if reserveAmmo == nil and not weapon.GetItemInstanceId then
                local ammoType = weapon:GetPrimaryAmmoType()
                if ammoType and ammoType >= 0 then
                    reserveAmmo = player:GetAmmoCount(ammoType)
                end
            end
            entry.clip = tonumber(weapon:Clip1()) or 0
            entry.maxClip = math.floor(maxClip)
            entry.reserve = reserveAmmo
            entry.active = IsValid(activeWeapon) and weapon == activeWeapon
            entries[#entries + 1] = entry
        end
    end

    table.sort(entries, compareHudWeaponEntries)
    return entries
end

local weaponSlotKeyActiveColor = Color(255, 208, 92)
local weaponSlotKeyIdleColor = Color(200, 200, 200)
local weaponHudLabelColor = Color(230, 230, 230)
local weaponHudClipColor = Color(255, 206, 98)
local weaponHudWhite = Color(255, 255, 255)

local function drawWeaponSlotKey(entry, x, y, height)
    if not entry.selectionSlot then return end
    local size = 20
    local badgeX, badgeY = x - size - 4, y + (height - size) * 0.5
    local color = entry.active and weaponSlotKeyActiveColor or weaponSlotKeyIdleColor
    surface.SetDrawColor(10, 12, 16, 230)
    surface.DrawRect(badgeX, badgeY, size, size)
    surface.SetDrawColor(color)
    surface.DrawOutlinedRect(badgeX, badgeY, size, size, 1)
    draw.SimpleText(tostring(entry.selectionSlot), "ZM_WeaponHudReserve",
        badgeX + size * 0.5, badgeY + size * 0.5, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function hideHudWeaponIcon()
    if IsValid(hudWeaponIconPanel) then
        hudWeaponIconPanel:SetVisible(false)
    end
end

local function drawHudWeaponIcon(entry, x, y, size)
    local definition = entry and entry.definition
    if not definition or not ZM_ItemIcons then
        hideHudWeaponIcon()
        return false
    end

    local override = ZM_ItemIcons:GetOverride(definition)
    if override then
        hideHudWeaponIcon()
        surface.SetMaterial(override)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, size, size)
        return true
    end

    if not definition.iconModel then
        hideHudWeaponIcon()
        return false
    end

    if not IsValid(hudWeaponIconPanel) or hudWeaponIconKey ~= entry.iconKey then
        if IsValid(hudWeaponIconPanel) then
            hudWeaponIconPanel:Remove()
        end

        hudWeaponIconPanel = vgui.Create("DPanel")
        hudWeaponIconPanel:SetPaintBackgroundEnabled(false)
        hudWeaponIconPanel:SetPaintBorderEnabled(false)
        hudWeaponIconPanel:SetMouseInputEnabled(false)
        hudWeaponIconPanel:SetKeyboardInputEnabled(false)
        hudWeaponIconKey = entry.iconKey
        ZM_ItemIcons:Attach(hudWeaponIconPanel, definition, 0)
    end

    hudWeaponIconPanel:SetPos(x, y)
    hudWeaponIconPanel:SetSize(size, size)
    hudWeaponIconPanel:SetVisible(true)
    return true
end

local function drawWeaponHudPanel()
    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() or ZM_SafeZones:IsPlayerInside(player)
        or ZM_LauncherMenu and ZM_LauncherMenu.Active then
        hideHudWeaponIcon()
        return
    end

    local weaponEntries = getHudWeaponEntries(player)
    if #weaponEntries <= 0 then
        hideHudWeaponIcon()
        return
    end

    local boxWidth = math.min(240, ScrW() - 48)
    local boxX = ScrW() - boxWidth - 16
    local activeWeapon = nil
    for _, entry in ipairs(weaponEntries) do
        if entry.active then
            activeWeapon = entry
            break
        end
    end
    local otherWeapons = hudOtherWeaponEntries
    table.Empty(otherWeapons)
    for _, entry in ipairs(weaponEntries) do
        if not entry.active then
            otherWeapons[#otherWeapons + 1] = entry
        end
    end

    local rows = activeWeapon and math.ceil(math.max(0, activeWeapon.maxClip) / 20) or 0
    local activeHeight = activeWeapon and (86 + rows * 10) or 0
    local slotHeight = 48
    local columns = boxWidth >= 200 and 2 or 1
    local columnGap = 30
    local slotWidth = math.floor((boxWidth - (columns - 1) * columnGap) / columns)
    local otherRows = math.ceil(#otherWeapons / columns)
    local boxY = math.max(72, ScrH() - 24 - activeHeight - otherRows * (slotHeight + 6))
    for index, entry in ipairs(otherWeapons) do
        local x = boxX + ((index - 1) % columns) * (slotWidth + columnGap)
        local y = boxY + math.floor((index - 1) / columns) * (slotHeight + 6)
        surface.SetDrawColor(12, 15, 19, 220)
        surface.DrawRect(x, y, slotWidth, slotHeight)
        surface.SetDrawColor(255, 255, 255, 40)
        surface.DrawOutlinedRect(x, y, slotWidth, slotHeight, 1)
        surface.SetFont("ZM_WeaponHudReserve")
        local label = entry.name
        if surface.GetTextSize(label) > slotWidth - 12 then
            repeat
                label = string.sub(label, 1, #label - 1)
            until #label == 0 or surface.GetTextSize(label .. "...") <= slotWidth - 12
            label = label .. "..."
        end
        draw.SimpleText(label, "ZM_WeaponHudReserve", x + 6, y + 4, weaponHudLabelColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local clipText = entry.maxClip > 0 and entry.clip >= 0 and (math.max(0, entry.clip) .. "/" .. entry.maxClip) or "--"
        draw.SimpleText(clipText, "ZM_WeaponHudReserve", x + 6, y + 25, weaponHudClipColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(entry.reserve and tostring(entry.reserve) or "--", "ZM_WeaponHudReserve", x + slotWidth - 6, y + 25, weaponSlotKeyIdleColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        drawWeaponSlotKey(entry, x, y, slotHeight)
    end

    if not activeWeapon then
        hideHudWeaponIcon()
        return
    end
    local activeX = boxX
    local activeY = boxY + otherRows * (slotHeight + 6)
    local activeWidth = boxWidth
    surface.SetDrawColor(10, 12, 16, 230)
    surface.DrawRect(activeX, activeY, activeWidth, activeHeight)
    surface.SetDrawColor(255, 255, 255, 65)
    surface.DrawOutlinedRect(activeX, activeY, activeWidth, activeHeight, 1)
    drawWeaponSlotKey(activeWeapon, activeX, activeY, activeHeight)

    draw.SimpleText(string.sub(activeWeapon.name, 1, 24), "ZM_WeaponHudName", activeX + 12, activeY + 8, weaponHudWhite, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local clipText = activeWeapon.maxClip > 0 and activeWeapon.clip >= 0 and (math.max(0, activeWeapon.clip) .. "/" .. activeWeapon.maxClip) or "--"
    draw.SimpleText(clipText, "ZM_WeaponHudValue", activeX + 12, activeY + 30, weaponHudWhite, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local weaponIconSize = activeWidth >= 200 and 44 or 34
    local weaponIconX = activeX + activeWidth - weaponIconSize - 8
    local weaponIconY = activeY + 20
    local reserveRight = weaponIconX - 8
    draw.SimpleText("RESERVE", "ZM_WeaponHudReserve", reserveRight, activeY + 30, weaponSlotKeyIdleColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    draw.SimpleText(activeWeapon.reserve and tostring(activeWeapon.reserve) or "--", "ZM_WeaponHudValue", reserveRight, activeY + 47, weaponSlotKeyActiveColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    if activeWeapon.maxClip > 0 and activeWeapon.clip >= 0 then
        drawWeaponHudBullets(activeX + 12, activeY + 77, activeWidth - 24, math.max(0, activeWeapon.clip), activeWeapon.maxClip, true)
    end
    drawHudWeaponIcon(activeWeapon, weaponIconX, weaponIconY, weaponIconSize)
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

local function getCellCompassLandmark(cell)
    local cacheKey = (ZM_World.ActiveProfile or "city") .. ":" .. tostring(cell.id)
    if compassLandmarkTargetCache[cacheKey] then
        return compassLandmarkTargetCache[cacheKey]
    end

    local selectedName
    local selectedStyle
    for _, landmarkName in ipairs(ZM_World:GetLandmarks(cell) or {}) do
        local style = compassLandmarkStyles[landmarkName]
        if not selectedStyle or (style and style.priority > selectedStyle.priority) then
            selectedName = landmarkName
            selectedStyle = style or { color = compassLandmarkFallbackColor, priority = 0 }
        end
    end
    if not selectedName then
        return nil
    end

    local landmark = {
        label = selectedName,
        color = selectedStyle.color
    }
    compassLandmarkTargetCache[cacheKey] = landmark
    return landmark
end

local landmarkTargetCacheCell
local landmarkTargetCacheData
local landmarkTargetCache

local function getNearbyLandmarkCompassTargets(playerCell)
    // Landmarks only change with the player's cell, so the scan of every world cell runs once per cell change.
    local worldData = ZM_World:GetData()
    if landmarkTargetCache and playerCell == landmarkTargetCacheCell and worldData == landmarkTargetCacheData then
        return landmarkTargetCache
    end
    local targets = {}
    if not worldData then
        return targets
    end

    for _, cell in ipairs(worldData.cells or {}) do
        if #(cell.landmarks or {}) > 0 then
            local landmark = getCellCompassLandmark(cell)
            if landmark then
                local distance = math.abs(cell.x - playerCell.x) + math.abs(cell.y - playerCell.y)
                if distance <= 6 then
                    table.insert(targets, { cell = cell, distance = distance, landmark = landmark })
                end
            end
        end
    end
    table.sort(targets, function(left, right)
        return left.distance < right.distance
    end)

    while #targets > 5 do
        table.remove(targets)
    end
    landmarkTargetCacheCell = playerCell
    landmarkTargetCacheData = worldData
    landmarkTargetCache = targets
    return targets
end

// Marker entities and den residents are gathered twice a second rather than walking every entity each frame.
local compassEntityRefreshSeconds = 0.5
local compassMarkerEntities = {}
local compassDenNpcs = {}
local nextCompassEntityRefreshAt = 0

local function refreshCompassEntities()
    local now = RealTime()
    if now < nextCompassEntityRefreshAt then return end
    nextCompassEntityRefreshAt = now + compassEntityRefreshSeconds
    table.Empty(compassMarkerEntities)
    for _, entity in ipairs(ents.GetAll()) do
        local marker = IsValid(entity) and entity:GetZMCompassMarker() or nil
        if marker then
            compassMarkerEntities[#compassMarkerEntities + 1] = { entity = entity, marker = marker }
        end
    end
    compassDenNpcs = ents.FindByClass("zn_den_npc")
end

local compassMarkerScratchColor = Color(255, 255, 255)

local function drawCompassMarker(x, y, width, heading, targetYaw, icon, color, pulse, showAtEdge, occupiedLabelRows)
    if not targetYaw then
        return
    end

    local relativeYaw = normalizeCompassAngle(targetYaw - heading)
    local isVisible = math.abs(relativeYaw) <= 95
    if not isVisible and not showAtEdge then
        return
    end

    local markerX = isVisible and (x + width * 0.5 + relativeYaw / 95 * (width * 0.5 - 12))
        or (relativeYaw > 0 and x + width - 7 or x + 7)
    local alpha = 255
    if pulse then
        alpha = math.floor(110 + 145 * (math.sin(CurTime() * 7) + 1) * 0.5)
    end
    local markerColor = compassMarkerScratchColor
    markerColor.r, markerColor.g, markerColor.b, markerColor.a = color.r, color.g, color.b, alpha
    surface.SetDrawColor(markerColor)
    surface.DrawRect(markerX - (isVisible and 1 or 2), y + 4, isVisible and 3 or 4, 19)
    if isVisible then
        surface.SetFont("ZM_CompassMarker")
        local labelWidth = surface.GetTextSize(icon)
        local maxLabelWidth = math.max(1, width - 16)
        while labelWidth > maxLabelWidth and #icon > 3 do
            icon = string.sub(icon, 1, #icon - 1)
            labelWidth = surface.GetTextSize(icon)
        end
        local labelX = math.Clamp(markerX, x + labelWidth * 0.5 + 8, x + width - labelWidth * 0.5 - 8)
        local maxRows = math.max(1, math.floor((94 * math.Clamp(compassHeightScale:GetFloat(), 0.55, 1.5) - 35) / 14))
        local row = 1
        while row <= maxRows do
            local overlaps = false
            for _, occupied in ipairs(occupiedLabelRows[row] or {}) do
                if labelX - labelWidth * 0.5 - 4 < occupied.right and labelX + labelWidth * 0.5 + 4 > occupied.left then
                    overlaps = true
                    break
                end
            end
            if not overlaps then
                break
            end
            row = row + 1
        end
        if row <= maxRows then
            occupiedLabelRows[row] = occupiedLabelRows[row] or {}
            table.insert(occupiedLabelRows[row], {
                left = labelX - labelWidth * 0.5 - 4,
                right = labelX + labelWidth * 0.5 + 4
            })
            draw.SimpleText(icon, "ZM_CompassMarker", labelX, y + 31 + (row - 1) * 14, markerColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end

// Screen rectangles of the fixed HUD panels, shared by their draw code and the crosshair clip.
local function getCompassRect()
    local width = math.min(500, ScrW() - 40)
    return math.floor((ScrW() - width) * 0.5), 18, width,
        math.floor(94 * math.Clamp(compassHeightScale:GetFloat(), 0.55, 1.5))
end

local minimapMargin = 20
local minimapBarAreaHeight = 76

local function getMinimapRect()
    local width = math.floor(math.min(230 * math.Clamp(minimapSizeScale:GetFloat(), 0.7, 1.75),
        ScrW() - minimapMargin * 2, (ScrH() * 0.6 - minimapBarAreaHeight) / 0.62))
    local height = math.floor(width * 0.62) + minimapBarAreaHeight
    return minimapMargin, ScrH() - height - minimapMargin, width, height
end

// Cached per frame: the crosshair clip queries these rects many times while searching for an edge.
local hudReservedRects = { {}, {}, {} }
local hudReservedRectsFrame = -1

function ZM_GetHudReservedRects()
    local frame = FrameNumber()
    if frame == hudReservedRectsFrame then
        return hudReservedRects
    end
    hudReservedRectsFrame = frame
    local compass, minimap, xpBar = hudReservedRects[1], hudReservedRects[2], hudReservedRects[3]
    compass.x, compass.y, compass.w, compass.h = getCompassRect()
    minimap.x, minimap.y, minimap.w, minimap.h = getMinimapRect()
    xpBar.x, xpBar.y, xpBar.w, xpBar.h = compass.x, compass.y + compass.h + 5, compass.w, 18
    return hudReservedRects
end

// Displayed compass heading eases toward the player's facing along the shortest turn, hiding cursor jitter.
local compassSmoothing = 10
local compassHeading

local function getSmoothedCompassHeading(player)
    local target = player:EyeAngles().y
    if not compassHeading then
        compassHeading = target
    end
    local blend = 1 - math.exp(-compassSmoothing * FrameTime())
    compassHeading = math.NormalizeAngle(compassHeading + math.AngleDifference(target, compassHeading) * blend)
    return compassHeading
end

local compassDirections = {
    { yaw = 90, label = "N" },
    { yaw = 0, label = "E" },
    { yaw = -90, label = "S" },
    { yaw = 180, label = "W" }
}
local compassWaypointColor = Color(246, 210, 48)
local compassEntityMarkerColor = Color(239, 57, 72)
local compassXpTextColor = Color(255, 255, 255)

local function drawPlayerCompass()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local player = LocalPlayer()
    if not IsValid(player) or not ZM_World or not ZM_World:IsLoaded() then
        return
    end

    local x, y, width, height = getCompassRect()
    local heading = getSmoothedCompassHeading(player)
    local playerCell = getHudPlayerCell(player)
    local isInDen = hasCurrentSafeZone(player)
    local occupiedLabelRows = {}

    surface.SetDrawColor(7, 8, 10, 235)
    surface.DrawRect(x, y, width, height)
    surface.SetDrawColor(114, 22, 31, 255)
    surface.DrawOutlinedRect(x, y, width, height, 1)
    surface.SetDrawColor(173, 28, 43, 255)
    surface.DrawRect(x + width * 0.5 - 1, y, 3, height)

    for _, direction in ipairs(compassDirections) do
        local relativeYaw = normalizeCompassAngle(direction.yaw - heading)
        if math.abs(relativeYaw) <= 105 then
            local tickX = x + width * 0.5 + relativeYaw / 105 * (width * 0.5 - 10)
            surface.SetDrawColor(181, 188, 194, 210)
            surface.DrawRect(tickX, y + 5, 1, 8)
            draw.SimpleText(direction.label, "ZM_CompassHeading", tickX, y + 14, minimapColors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end

    if not isInDen and playerCell and ZM_WorldMap and ZM_WorldMap.WaypointCell
        and ZM_WorldMap.WaypointProfile == ZM_World.ActiveProfile then
        local direction = ZM_WorldMap:GetWaypointDirection(playerCell)
        local yaw = waypointDirectionYaw[direction]
        if yaw then
            drawCompassMarker(x, y, width, heading, yaw, getCompassMarkerLabel("waypoint"), compassWaypointColor, true, true, occupiedLabelRows)
        end
    end
    if not isInDen and playerCell then
        for _, target in ipairs(getNearbyLandmarkCompassTargets(playerCell)) do
            drawCompassMarker(x, y, width, heading, getCellCompassYaw(player, target.cell), target.landmark.label, target.landmark.color, false, false, occupiedLabelRows)
        end
    end
    refreshCompassEntities()
    local eyePosition = player:EyePos()
    for _, entry in ipairs(compassMarkerEntities) do
        local entity, marker = entry.entity, entry.marker
        if IsValid(entity) then
            local offset = entity:WorldSpaceCenter() - eyePosition
            if offset:LengthSqr() > 2500 then
                drawCompassMarker(x, y, width, heading, offset:Angle().y, getCompassMarkerLabel(marker.icon, marker.label), compassEntityMarkerColor, false, false, occupiedLabelRows)
            end
        end
    end
    for _, npc in ipairs(compassDenNpcs) do
        if IsValid(npc) and not npc:IsDormant() then
            local offset = npc:WorldSpaceCenter() - eyePosition
            if offset:LengthSqr() > 2500 then
                drawCompassMarker(x, y, width, heading, offset:Angle().y, npc:GetNWString("ZM_NpcName", "Den Resident"), denNpcColor, false, false, occupiedLabelRows)
            end
        end
    end

    local xp = math.max(player:GetNWInt("XP", tonumber(player.XP) or 0), 0)
    local experiencePerLevel = math.max(player:GetNWInt("ExperiencePerLevel", tonumber(player.ExperiencePerLevel) or 1000), 1)
    local progress = math.Clamp(xp / experiencePerLevel, 0, 1)
    local xpY = y + height + 5
    local xpHeight = 18
    surface.SetDrawColor(7, 8, 10, 230)
    surface.DrawRect(x, xpY, width, xpHeight)
    surface.SetDrawColor(47, 123, 83, 255)
    surface.DrawRect(x, xpY, math.floor(width * progress), xpHeight)
    surface.SetDrawColor(114, 22, 31, 255)
    surface.DrawOutlinedRect(x, xpY, width, xpHeight, 1)
    draw.SimpleText(
        string.format("LEVEL %d  |  XP %d / %d", player:GetNWInt("Level", tonumber(player.Level) or 1), xp, experiencePerLevel),
        "ZM_MinimapLabel",
        x + width * 0.5,
        xpY + xpHeight * 0.5,
        compassXpTextColor,
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
end

hook.Add("HUDPaint", "ZM.PlayerCompass", drawPlayerCompass)
hook.Add("HUDPaint", "ZM.PlayerWeaponHud", drawWeaponHudPanel)

// Preview god mode is networked by sv_preview so the badge survives level changes with the persisted cheat.
local function getGodModeBadgeRect()
    local x, y, width, height = getCompassRect()
    local badgeWidth, badgeHeight = 120, 20
    return math.floor(x + (width - badgeWidth) * 0.5), y + height + 5 + 18 + 4, badgeWidth, badgeHeight
end

hook.Add("HUDPaint", "ZM.PreviewGodModeBadge", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local player = LocalPlayer()
    if not IsValid(player) or not player:GetNWBool("ZM_CheatGod", false) then return end

    local x, y, width, height = getGodModeBadgeRect()
    local pulse = 0.75 + 0.25 * math.sin(CurTime() * 4)
    surface.SetDrawColor(7, 8, 10, 230)
    surface.DrawRect(x, y, width, height)
    surface.SetDrawColor(246, 210, 48, math.floor(255 * pulse))
    surface.DrawOutlinedRect(x, y, width, height, 1)
    draw.SimpleText("GOD MODE", "ZM_MinimapLabel", x + width * 0.5, y + height * 0.5,
        Color(246, 210, 48, math.floor(255 * pulse)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

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

local minimapCardinalColor = Color(244, 244, 246, 235)
local minimapBarAlertColor = Color(239, 57, 72, 255)

local function drawMinimapBar(x, y, width, height, label, value, color)
    local intensity = math.Clamp(tonumber(value) or 0, 0, 1)
    local isLow = intensity <= 0.25
    local alertAlpha = math.floor(125 + (math.sin(CurTime() * 8) + 1) * 65)
    local borderColor = color
    if isLow then
        borderColor = minimapBarAlertColor
        borderColor.a = alertAlpha
    end
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

    local color = minimapCardinalColor
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

// Off-map NPCs are pinned to the minimap edge along the line from the centre, so they still point the right way.
local function drawDenNpcMinimapMarker(mapX, mapY, mapWidth, mapHeight, markerX, markerY, npc)
    local inset = 7
    local centreX, centreY = mapX + mapWidth * 0.5, mapY + mapHeight * 0.5
    local deltaX, deltaY = markerX - centreX, markerY - centreY
    local halfWidth, halfHeight = mapWidth * 0.5 - inset, mapHeight * 0.5 - inset
    local scale = math.max(math.abs(deltaX) / halfWidth, math.abs(deltaY) / halfHeight, 1)
    local pinned = scale > 1
    markerX, markerY = math.floor(centreX + deltaX / scale), math.floor(centreY + deltaY / scale)
    draw.NoTexture()
    surface.SetDrawColor(10, 8, 4, 255)
    surface.DrawPoly({ { x = markerX, y = markerY - 6 }, { x = markerX + 6, y = markerY }, { x = markerX, y = markerY + 6 }, { x = markerX - 6, y = markerY } })
    surface.SetDrawColor(denNpcColor.r, denNpcColor.g, denNpcColor.b, pinned and 190 or 255)
    surface.DrawPoly({ { x = markerX, y = markerY - 4 }, { x = markerX + 4, y = markerY }, { x = markerX, y = markerY + 4 }, { x = markerX - 4, y = markerY } })
    // Labels flip below markers pinned near the top edge so they do not cover the diamond.
    local labelBelow = markerY - 6 < mapY + 12
    local name = npc:GetNWString("ZM_NpcName", "Den Resident")
    surface.SetFont("ZM_MinimapLabel")
    local labelHalfWidth = math.min(surface.GetTextSize(name) * 0.5, mapWidth * 0.5 - 4)
    draw.SimpleText(
        name,
        "ZM_MinimapLabel",
        math.Clamp(markerX, mapX + 4 + labelHalfWidth, mapX + mapWidth - 4 - labelHalfWidth),
        labelBelow and markerY + 6 or markerY - 6,
        denNpcColor,
        TEXT_ALIGN_CENTER,
        labelBelow and TEXT_ALIGN_TOP or TEXT_ALIGN_BOTTOM
    )
end

local waypointMinimapColor = Color(246, 210, 48)

// Returns the published centre of the nearest transition gate on the waypoint route side of the current cell.
local function getWaypointGatePosition(playerCell, position)
    if not playerCell or not ZM_WorldMap or not ZM_WorldMap.WaypointCell or ZM_WorldMap.WaypointProfile ~= ZM_World.ActiveProfile then
        return nil
    end
    local direction = ZM_WorldMap:GetWaypointDirection(playerCell)
    if not waypointDirectionYaw[direction] then
        return nil
    end
    local nearest, nearestDistance
    for index = 1, GetGlobal2Int("ZMTransitionGateCount_" .. direction, 0) do
        local centre = GetGlobal2Vector("ZMTransitionGate_" .. direction .. "_" .. index, vector_origin)
        local distance = centre:DistToSqr(position)
        if not nearestDistance or distance < nearestDistance then
            nearest, nearestDistance = centre, distance
        end
    end
    return nearest
end

// Pinned to the minimap edge (like den NPCs) when the gate is outside the visible area.
local function drawWaypointMinimapMarker(mapX, mapY, mapWidth, mapHeight, markerX, markerY)
    local inset = 8
    local centreX, centreY = mapX + mapWidth * 0.5, mapY + mapHeight * 0.5
    local deltaX, deltaY = markerX - centreX, markerY - centreY
    local scale = math.max(math.abs(deltaX) / (mapWidth * 0.5 - inset), math.abs(deltaY) / (mapHeight * 0.5 - inset), 1)
    markerX, markerY = math.floor(centreX + deltaX / scale), math.floor(centreY + deltaY / scale)
    local pulse = 0.75 + 0.25 * math.sin(CurTime() * 5)
    draw.NoTexture()
    surface.SetDrawColor(10, 8, 4, 255)
    surface.DrawPoly({ { x = markerX, y = markerY - 8 }, { x = markerX + 8, y = markerY }, { x = markerX, y = markerY + 8 }, { x = markerX - 8, y = markerY } })
    surface.SetDrawColor(waypointMinimapColor.r, waypointMinimapColor.g, waypointMinimapColor.b, math.floor(255 * pulse))
    surface.DrawPoly({ { x = markerX, y = markerY - 6 }, { x = markerX + 6, y = markerY }, { x = markerX, y = markerY + 6 }, { x = markerX - 6, y = markerY } })
    local label = getCompassMarkerLabel("waypoint")
    local labelBelow = markerY - 8 < mapY + 12
    surface.SetFont("ZM_MinimapLabel")
    local labelHalfWidth = math.min(surface.GetTextSize(label) * 0.5, mapWidth * 0.5 - 4)
    draw.SimpleText(
        label,
        "ZM_MinimapLabel",
        math.Clamp(markerX, mapX + 4 + labelHalfWidth, mapX + mapWidth - 4 - labelHalfWidth),
        labelBelow and markerY + 8 or markerY - 8,
        waypointMinimapColor,
        TEXT_ALIGN_CENTER,
        labelBelow and TEXT_ALIGN_TOP or TEXT_ALIGN_BOTTOM
    )
end

// Safe-zone entrances (in a cell) and exits (in a den) stay visible, pinned to the minimap edge when off-screen.
local function drawSafeZoneDoorMinimapMarker(mapX, mapY, mapWidth, mapHeight, markerX, markerY, label)
    local inset = 8
    local centreX, centreY = mapX + mapWidth * 0.5, mapY + mapHeight * 0.5
    local deltaX, deltaY = markerX - centreX, markerY - centreY
    local scale = math.max(math.abs(deltaX) / (mapWidth * 0.5 - inset), math.abs(deltaY) / (mapHeight * 0.5 - inset), 1)
    markerX, markerY = math.floor(centreX + deltaX / scale), math.floor(centreY + deltaY / scale)
    ZM_WorldMap:DrawSafeZoneDoorGlyph(markerX, markerY, 5)
    local color = ZM_WorldMap.SafeZoneDoorColor
    local labelBelow = markerY - 7 < mapY + 12
    surface.SetFont("ZM_MinimapLabel")
    local labelHalfWidth = math.min(surface.GetTextSize(label) * 0.5, mapWidth * 0.5 - 4)
    draw.SimpleText(
        label,
        "ZM_MinimapLabel",
        math.Clamp(markerX, mapX + 4 + labelHalfWidth, mapX + mapWidth - 4 - labelHalfWidth),
        labelBelow and markerY + 8 or markerY - 8,
        color,
        TEXT_ALIGN_CENTER,
        labelBelow and TEXT_ALIGN_TOP or TEXT_ALIGN_BOTTOM
    )
end

local function drawBossMinimapMarker(mapX, mapY, mapWidth, mapHeight, markerX, markerY)
    if markerX < mapX or markerX > mapX + mapWidth or markerY < mapY or markerY > mapY + mapHeight then
        return
    end
    surface.SetDrawColor(35, 8, 12, 255)
    surface.DrawRect(markerX - 7, markerY - 7, 14, 14)
    surface.SetDrawColor(239, 57, 72, 255)
    surface.DrawOutlinedRect(markerX - 6, markerY - 6, 12, 12, 2)
    draw.SimpleText("B", "ZM_MinimapLabel", markerX, markerY, Color(255, 230, 232), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function drawPlayerMinimap()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local player = LocalPlayer()
    if not IsValid(player) then return end

    local x, y, width, height = getMinimapRect()
    local mapHeight = height - minimapBarAreaHeight
    local barAreaHeight = minimapBarAreaHeight
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
        if minimapViewMode == "map" and ZM_WorldMap and ZM_WorldMap.ProjectLocalMapPosition then
            refreshCompassEntities()
            for _, npc in ipairs(compassDenNpcs) do
                if IsValid(npc) and not npc:IsDormant() then
                    local npcX, npcY = ZM_WorldMap:ProjectLocalMapPosition(mapX, mapY, mapWidth, mapHeight, position, localMapViewHeight, npc:GetPos())
                    if npcX and npcY then drawDenNpcMinimapMarker(mapX, mapY, mapWidth, mapHeight, npcX, npcY, npc) end
                end
            end
        end
        if ZM_WorldMap and ZM_WorldMap.GetSafeZoneDoorMarkers then
            for _, door in ipairs(ZM_WorldMap:GetSafeZoneDoorMarkers()) do
                local doorX, doorY
                if minimapViewMode == "map" and ZM_WorldMap.ProjectLocalMapPosition then
                    doorX, doorY = ZM_WorldMap:ProjectLocalMapPosition(mapX, mapY, mapWidth, mapHeight, position, localMapViewHeight, door.position)
                elseif cellTextureTransform then
                    doorX, doorY = projectCellTexturePosition(mapX, mapY, mapWidth, mapHeight, door.position, cellTextureTransform)
                end
                if doorX and doorY then drawSafeZoneDoorMinimapMarker(mapX, mapY, mapWidth, mapHeight, doorX, doorY, door.label) end
            end
        end
        local gatePosition = not isInDen and getWaypointGatePosition(cell, position) or nil
        if gatePosition then
            local gateX, gateY
            if minimapViewMode == "map" and ZM_WorldMap and ZM_WorldMap.ProjectLocalMapPosition then
                gateX, gateY = ZM_WorldMap:ProjectLocalMapPosition(mapX, mapY, mapWidth, mapHeight, position, localMapViewHeight, gatePosition)
            elseif cellTextureTransform then
                gateX, gateY = projectCellTexturePosition(mapX, mapY, mapWidth, mapHeight, gatePosition, cellTextureTransform)
            end
            if gateX and gateY then drawWaypointMinimapMarker(mapX, mapY, mapWidth, mapHeight, gateX, gateY) end
        end
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
        local bossSnapshot = ZM_WorldMap and ZM_WorldMap.BossSnapshot
        if bossSnapshot and bossSnapshot.profile == ZM_World.ActiveProfile then
            for _, boss in ipairs(bossSnapshot.bosses or {}) do
                if IsValid(boss.entity) then
                    local bossX, bossY
                    if minimapViewMode == "map" and ZM_WorldMap.ProjectLocalMapPosition then
                        bossX, bossY = ZM_WorldMap:ProjectLocalMapPosition(mapX, mapY, mapWidth, mapHeight, position, localMapViewHeight, boss.entity:GetPos())
                    elseif cellTextureTransform then
                        bossX, bossY = projectCellTexturePosition(mapX, mapY, mapWidth, mapHeight, boss.entity:GetPos(), cellTextureTransform)
                    end
                    if bossX and bossY then drawBossMinimapMarker(mapX, mapY, mapWidth, mapHeight, bossX, bossY) end
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
function ZM_AddPlayerNotification(text)
    table.insert(playerNotifications, {
        text = string.sub(tostring(text), 1, 96),
        created = CurTime(),
    })
    while #playerNotifications > maximumPlayerNotifications do
        table.remove(playerNotifications, 1)
    end
end

function ZM_AddHudEventNotification(text, soundPath)
    table.insert(hudEventNotifications, {
        text = string.sub(tostring(text), 1, 96),
        created = CurTime(),
    })
    while #hudEventNotifications > maximumHudEventNotifications do
        table.remove(hudEventNotifications, 1)
    end
    if soundPath then
        surface.PlaySound(soundPath)
    end
end

// Screen position just above the player's head, or the screen centre when the head is off-screen.
function ZM_GetPlayerOverheadScreenPos(ply)
    local screen = (ply:GetPos() + Vector(0, 0, ply:OBBMaxs().z + 10)):ToScreen()
    if not screen.visible then
        return ScrW() * 0.5, ScrH() * 0.5
    end
    return screen.x, screen.y
end

local lastPlayerHealth

// Detects local health loss and shows the amount above the player.
hook.Add("Think", "ZM.TrackPlayerDamage", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        lastPlayerHealth = nil
        return
    end

    local currentHealth = ply:Health()
    local damage = lastPlayerHealth and lastPlayerHealth - currentHealth or 0
    if damage > 0 then
        ZM_AddPlayerNotification("-" .. damage .. " HP")
    end
    lastPlayerHealth = currentHealth
end)

local staminaBarWidth = 80
local staminaBarHeight = 5

// Draws queued notifications above the player (and above the stamina bar), removing expired ones.
hook.Add("HUDPaint", "ZM.PlayerNotifications", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local now = CurTime()
    local anchorX, anchorY = ZM_GetPlayerOverheadScreenPos(ply)
    local y = anchorY - staminaBarHeight - 16
    local index = 1

    for notificationIndex = #playerNotifications, 1, -1 do
        local notification = playerNotifications[notificationIndex]
        local age = now - notification.created

        if age >= notificationDuration then
            table.remove(playerNotifications, notificationIndex)
        else
            local alpha = 255
            if age > notificationDuration - notificationFadeDuration then
                alpha = math.floor(255 * (notificationDuration - age) / notificationFadeDuration)
            end

            draw.SimpleText(
                notification.text,
                "ZM_PlayerNotification",
                anchorX,
                y - (index - 1) * 22,
                Color(255, 255, 255, alpha),
                TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER
            )
            index = index + 1
        end
    end
end)

hook.Add("HUDPaint", "ZM.HudEventNotifications", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local player = LocalPlayer()
    if not IsValid(player) then return end

    local now = CurTime()
    local compassX, compassY, compassWidth, compassHeight = getCompassRect()
    local eventY = compassY + compassHeight + 5 + 18 + 12
    local visibleIndex = 0
    for index = #hudEventNotifications, 1, -1 do
        local notification = hudEventNotifications[index]
        local age = now - notification.created
        if age >= hudEventDuration then
            table.remove(hudEventNotifications, index)
        else
            local alpha = 255
            if age > hudEventDuration - hudEventFadeDuration then
                alpha = math.floor(255 * (hudEventDuration - age) / hudEventFadeDuration)
            end
            draw.SimpleText(
                notification.text,
                "ZM_HudEventNotification",
                compassX + compassWidth * 0.5,
                eventY + visibleIndex * 27,
                Color(255, 224, 145, alpha),
                TEXT_ALIGN_CENTER,
                TEXT_ALIGN_TOP
            )
            visibleIndex = visibleIndex + 1
        end
    end
end)

net.Receive("ZM.HudLevelUp", function()
    local level = net.ReadUInt(16)
    ZM_AddHudEventNotification("LEVEL UP  |  LEVEL " .. level, "buttons/button15.wav")
end)

net.Receive("ZM.EnemyHitMarker", function()
    if ZM_SafeZones:IsPlayerInside(LocalPlayer()) then return end
    local now = CurTime()
    enemyHitMarkerExpires = now + 0.22
    if now >= enemyHitMarkerSoundAt then
        surface.PlaySound("buttons/button14.wav")
        enemyHitMarkerSoundAt = now + 0.12
    end
end)

hook.Add("HUDPaint", "ZM.EnemyHitMarker", function()
    local player = LocalPlayer()
    if CurTime() >= enemyHitMarkerExpires or not IsValid(player) or not player:Alive()
        or ZM_SafeZones:IsPlayerInside(player)
        or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus())
        or ZM_LauncherMenu and ZM_LauncherMenu.Active then
        return
    end

    local scale = math.Clamp(ScrH() / 1080, 0.75, 1.5)
    local cursorX, cursorY
    if ZM_GetAimCursor then cursorX, cursorY = ZM_GetAimCursor() end
    local centerX, centerY = cursorX or ScrW() * 0.5, cursorY or ScrH() * 0.5
    local inner = 7 * scale
    local outer = 13 * scale
    local color = Color(255, 255, 255, 230)
    surface.SetDrawColor(color)
    for _, direction in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        surface.DrawLine(centerX + direction[1] * inner, centerY + direction[2] * inner,
            centerX + direction[1] * outer, centerY + direction[2] * outer)
    end
end)

// Draws stamina above the player only while sprinting or recovering.
hook.Add("HUDPaint", "ZM.StaminaBar", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local stamina = ply:GetNWFloat("Stamina", 100)
    local maxStamina = math.max(ply:GetNWFloat("MaxStamina", 100), 1)
    local staminaPercent = math.Clamp(stamina / maxStamina, 0, 1)
    local isUsingStamina = ply:KeyDown(IN_SPEED) or staminaPercent < 1
    if not isUsingStamina then return end

    local anchorX, anchorY = ZM_GetPlayerOverheadScreenPos(ply)
    local barWidth = staminaBarWidth
    local barHeight = staminaBarHeight
    local barX = math.floor(anchorX - barWidth * 0.5)
    local barY = math.floor(anchorY - barHeight)
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
