local gatePromptRange = 96
local routeGateColor = Color(246, 210, 48)
local defaultGateColor = Color(92, 240, 154)

// Loading screen shown while a transition holds the screen black. The whole HUD is hidden from the moment the screen
// starts fading out until it has fully faded back in; "LOADING" is drawn only while the screen is (nearly) black.
ZM_LoadingScreen = ZM_LoadingScreen or {}
local LoadingScreen = ZM_LoadingScreen
LoadingScreen.HideUntil = LoadingScreen.HideUntil or 0
LoadingScreen.BlackFrom = LoadingScreen.BlackFrom or math.huge
LoadingScreen.BlackUntil = LoadingScreen.BlackUntil or 0
local loadingTextFade = 0.35

surface.CreateFont("ZM_LoadingTitle", { font = "Trebuchet MS", size = 64, weight = 900, antialias = true })
surface.CreateFont("ZM_LoadingGlow", { font = "Trebuchet MS", size = 64, weight = 900, antialias = true,
    blursize = 8, additive = true })
surface.CreateFont("ZM_LoadingLog", { font = "Consolas", size = 17, weight = 500, antialias = true })

// The screen is already black and stays black for holdSeconds, then fades in over fadeSeconds.
function LoadingScreen:Hold(holdSeconds, fadeSeconds)
    local now = CurTime()
    self.Title = nil
    self.ShowLog = true
    self.BlackFrom = now
    self.BlackUntil = now + math.max(0, holdSeconds or 0)
    self.HideUntil = self.BlackUntil + math.max(0, fadeSeconds or 0)
end

// The screen fades to black over fadeSeconds and stays black until the level changes. The step log is hidden because
// the level change would cut it off; title replaces "LOADING" (for example "GOODBYE" when leaving a den).
function LoadingScreen:BeginFadeOut(fadeSeconds, title)
    local now = CurTime()
    self.Title = title ~= "" and title or nil
    self.ShowLog = false
    self.BlackFrom = now + math.max(0, fadeSeconds or 0)
    self.BlackUntil = math.huge
    self.HideUntil = math.huge
end

function LoadingScreen:Clear()
    self.Title = nil
    self.ShowLog = true
    self.BlackFrom = math.huge
    self.BlackUntil = 0
    self.HideUntil = 0
end

function LoadingScreen:IsHidingHud()
    return CurTime() < self.HideUntil
end

// Client systems can keep the screen black past the engine fade while they finish visible work (for example the
// snow cover). While any hold is active the screen stays black with the loading log; once released it fades in.
LoadingScreen.ExtraHolds = LoadingScreen.ExtraHolds or {}
LoadingScreen.CoverUntil = LoadingScreen.CoverUntil or 0
LoadingScreen.CoverFade = LoadingScreen.CoverFade or 1.1

function LoadingScreen:SetExtraHold(key, active)
    self.ExtraHolds[key] = active and true or nil
end

function LoadingScreen:HasExtraHold()
    return next(self.ExtraHolds) ~= nil
end

hook.Add("Think", "ZM.LoadingScreen.ExtraHolds", function()
    if not LoadingScreen:HasExtraHold() then
        return
    end
    local now = CurTime()
    LoadingScreen.BlackFrom = math.min(LoadingScreen.BlackFrom, now)
    LoadingScreen.BlackUntil = math.max(LoadingScreen.BlackUntil, now)
    LoadingScreen.HideUntil = math.max(LoadingScreen.HideUntil, LoadingScreen.BlackUntil + LoadingScreen.CoverFade)
    LoadingScreen.CoverUntil = now
end)

// 0..1 opacity of the loading text: fades in once the screen is black and out as the screen fades back in.
function LoadingScreen:GetTextAlpha()
    local now = CurTime()
    if now < self.BlackFrom or now >= self.BlackUntil + loadingTextFade then
        return 0
    end
    local fadeIn = math.Clamp((now - self.BlackFrom) / loadingTextFade, 0, 1)
    local fadeOut = now <= self.BlackUntil and 1 or 1 - (now - self.BlackUntil) / loadingTextFade
    return math.Clamp(math.min(fadeIn, fadeOut), 0, 1)
end

net.Receive("ZM.LoadingHold", function()
    local hold = net.ReadFloat()
    LoadingScreen:Hold(hold, net.ReadFloat())
end)

hook.Add("HUDShouldDraw", "ZM.LoadingScreen.HideHud", function()
    if LoadingScreen:IsHidingHud() then
        return false
    end
end)

local loadingWord = "LOADING"
// Half-Life 2 HUD gold (ClientScheme "Yellow").
local loadingAccent = Color(255, 220, 0)
local logTypeSeconds = 0.25
local logStaggerSeconds = 0.12
local logLineGap = 4
local logBottomMargin = 48
local spinnerFrames = { "|", "/", "-", "\\" }
local statusLabels = { ok = "[ OK ]", warn = "[WARN]", fail = "[FAIL]", info = "[INFO]" }
local statusColours = {
    ok = loadingAccent,
    warn = Color(255, 150, 40),
    fail = Color(255, 70, 60),
    info = Color(170, 170, 170)
}
local realmColours = { sv = Color(120, 170, 255), cl = Color(255, 220, 0) }

// Steps from ZM_Loading type in one after another; as many as fit below the bar are shown, newest at the bottom.
// Each line shows its realm (SV/CL), real elapsed time from that realm's load start, and its status.
local function drawLoadingLog(centreX, topY, alpha, time)
    local lines = ZM_Loading and ZM_Loading.Lines or {}
    if #lines == 0 then
        return
    end
    // Lines received in the same frame are staggered so each one is readable as it arrives.
    local previousShow = 0
    for _, line in ipairs(lines) do
        if not line.showTime then
            line.showTime = math.max(line.receivedAt, previousShow + logStaggerSeconds)
        end
        previousShow = line.showTime
    end
    local visibleLines = {}
    for _, line in ipairs(lines) do
        if time >= line.showTime then
            table.insert(visibleLines, line)
        end
    end
    if #visibleLines == 0 then
        return
    end

    surface.SetFont("ZM_LoadingLog")
    local _, lineHeight = surface.GetTextSize("Ag")
    local rowHeight = lineHeight + logLineGap
    local capacity = math.max(1, math.floor((ScrH() - logBottomMargin - topY) / rowHeight))
    local first = math.max(1, #visibleLines - capacity + 1)
    local stampWidth = surface.GetTextSize("SV +000.000s  ")
    local statusWidth = surface.GetTextSize("[FAIL]")
    local textWidth = 0
    for index = first, #visibleLines do
        textWidth = math.max(textWidth, surface.GetTextSize(visibleLines[index].text))
    end
    local columnWidth = math.min(stampWidth + textWidth + 24 + statusWidth, ScrW() * 0.9)
    local left = centreX - columnWidth * 0.5

    for index = first, #visibleLines do
        local line = visibleLines[index]
        local row = index - first
        local age = time - line.showTime
        local typed = math.Clamp(age / logTypeSeconds, 0, 1)
        local fromNewest = #visibleLines - index
        local lineAlpha = alpha * Lerp(math.Clamp(fromNewest / 10, 0, 1), 1, 0.45)
        // When the log overflows, the oldest visible row fades out at the top.
        if first > 1 and row == 0 then
            lineAlpha = lineAlpha * 0.35
        end
        local y = topY + row * rowHeight
        local realm = string.sub(line.id, 1, 2)
        local realmColour = realmColours[realm] or statusColours.info
        draw.SimpleText(string.upper(realm), "ZM_LoadingLog", left, y,
            Color(realmColour.r, realmColour.g, realmColour.b, 220 * lineAlpha))
        draw.SimpleText(string.format("+%.3fs", line.elapsed or 0), "ZM_LoadingLog", left + surface.GetTextSize("SV "), y,
            Color(150, 150, 150, 255 * lineAlpha))
        local text = string.sub(line.text, 1, math.floor(#line.text * typed))
        draw.SimpleText(text, "ZM_LoadingLog", left + stampWidth, y,
            Color(235, 235, 235, 255 * lineAlpha))

        local statusX = left + columnWidth
        if typed < 1 then
            draw.SimpleText("_", "ZM_LoadingLog", left + stampWidth + surface.GetTextSize(text), y,
                Color(235, 235, 235, 255 * lineAlpha * (math.floor(time * 8) % 2)))
        elseif line.status == "pending" then
            draw.SimpleText("[ " .. spinnerFrames[math.floor(time * 10) % #spinnerFrames + 1] .. "  ]", "ZM_LoadingLog",
                statusX, y, Color(loadingAccent.r, loadingAccent.g, loadingAccent.b, 255 * lineAlpha), TEXT_ALIGN_RIGHT)
        else
            // Status tags flash white as a step completes, then settle to their status colour.
            local completedAt = math.max(line.showTime + logTypeSeconds, line.finishedAt or 0)
            local flash = math.Clamp(1 - (time - completedAt) / 0.4, 0, 1)
            local colour = statusColours[line.status] or statusColours.ok
            draw.SimpleText(statusLabels[line.status] or statusLabels.ok, "ZM_LoadingLog", statusX, y,
                Color(Lerp(flash, colour.r, 255), Lerp(flash, colour.g, 255), Lerp(flash, colour.b, 255), 255 * lineAlpha),
                TEXT_ALIGN_RIGHT)
        end
    end
end
hook.Add("DrawOverlay", "ZM.LoadingScreen.Draw", function()
    // Our own black cover for client holds that outlast the engine fade; it fades out once they are released.
    if LoadingScreen.CoverUntil > 0 then
        local coverAlpha = math.Clamp((LoadingScreen.CoverUntil + LoadingScreen.CoverFade - CurTime()) / LoadingScreen.CoverFade, 0, 1)
        if coverAlpha > 0 then
            surface.SetDrawColor(0, 0, 0, 255 * coverAlpha)
            surface.DrawRect(0, 0, ScrW(), ScrH())
        else
            LoadingScreen.CoverUntil = 0
        end
    end
    local alpha = LoadingScreen:GetTextAlpha()
    if alpha <= 0 then
        return
    end
    local time = RealTime()
    local centreX, centreY = ScrW() * 0.5, ScrH() * 0.5

    local word = LoadingScreen.Title or loadingWord
    surface.SetFont("ZM_LoadingTitle")
    local letterWidths = {}
    local totalWidth = 0
    local spacing = 10
    for index = 1, #word do
        local width = surface.GetTextSize(word:sub(index, index))
        letterWidths[index] = width
        totalWidth = totalWidth + width + (index < #word and spacing or 0)
    end

    // Each letter bobs on a travelling wave and glows as the highlight sweeps across the word.
    local x = centreX - totalWidth * 0.5
    local sweep = (time * 1.4) % 1.6 - 0.3
    for index = 1, #word do
        local letter = word:sub(index, index)
        local phase = (index - 1) / math.max(1, #word - 1)
        local bob = math.sin(time * 5 - index * 0.6) * 6
        local highlight = math.Clamp(1 - math.abs(sweep - phase) * 4, 0, 1)
        local letterX = x + letterWidths[index] * 0.5
        local glowAlpha = (90 + highlight * 165) * alpha
        draw.SimpleText(letter, "ZM_LoadingGlow", letterX, centreY + bob,
            Color(loadingAccent.r, loadingAccent.g, loadingAccent.b, glowAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local shade = Lerp(highlight, 210, 255)
        draw.SimpleText(letter, "ZM_LoadingTitle", letterX, centreY + bob,
            Color(Lerp(highlight, shade, loadingAccent.r), shade, Lerp(highlight, shade, loadingAccent.b), 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        x = x + letterWidths[index] + spacing
    end

    // A pulse runs back and forth along a thin bar under the word.
    local barWidth, barY = totalWidth + 40, centreY + 50
    local barLeft = centreX - barWidth * 0.5
    surface.SetDrawColor(255, 255, 255, 28 * alpha)
    surface.DrawRect(barLeft, barY, barWidth, 2)
    local pulse = (math.sin(time * 2.2) + 1) * 0.5
    local pulseWidth = barWidth * 0.22
    surface.SetDrawColor(loadingAccent.r, loadingAccent.g, loadingAccent.b, 230 * alpha)
    surface.DrawRect(barLeft + (barWidth - pulseWidth) * pulse, barY - 1, pulseWidth, 4)

    if LoadingScreen.ShowLog ~= false then
        drawLoadingLog(centreX, barY + 24, alpha, time)
    end
end)

local function getWaypointDirection(playerEntity)
    if not ZM_World or not ZM_World:IsLoaded() or not ZM_WorldMap
        or not ZM_WorldMap.GetWaypointDirection then
        return nil
    end

    local gridX, gridY = ZM_World:GetGridCoordinates(
        playerEntity:GetNWInt("CellX", 0),
        playerEntity:GetNWInt("CellY", 0)
    )
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    return cell and ZM_WorldMap:GetWaypointDirection(cell) or nil
end

local function getNearbySafeZoneDoor()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive() then
        return nil
    end

    local nearestDoor
    local nearestDistance
    for _, entity in ipairs(ents.FindByClass("zn_safezone_door")) do
        if entity:GetNWBool("ZMSafeZoneDoor", false) then
            local radius = entity:GetNWFloat("ZMSafeZoneDoorRadius", gatePromptRange)
            local distance = playerEntity:GetPos():DistToSqr(entity:GetPos())
            if distance <= radius * radius and (nearestDistance == nil or distance < nearestDistance) then
                nearestDoor = entity
                nearestDistance = distance
            end
        end
    end
    return nearestDoor
end

local function getNearbyTransitionGate()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive() then
        return nil
    end
    local directionName = playerEntity:GetNWString("ZMNearbyTransitionGate", "")
    return directionName ~= "" and directionName or nil
end

local directionCodes = { north = "N", east = "E", south = "S", west = "W" }
local blockedGateColor = Color(232, 52, 52)

hook.Add("HUDPaint", "ZM.TransitionGatePrompt", function()
    local safeZoneDoor = getNearbySafeZoneDoor()
    if safeZoneDoor then
        local role = safeZoneDoor:GetNWString("ZMSafeZoneDoorRole", "")
        local prompt = role == "enter" and "PRESS E TO ENTER SAFE ZONE" or "PRESS E TO EXIT SAFE ZONE"
        draw.SimpleText(prompt, "DermaLarge", ScrW() * 0.5, ScrH() * 0.5 + 38, Color(92, 240, 154), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local gateDirection = getNearbyTransitionGate()
    if not gateDirection then
        return
    end

    if LocalPlayer():GetNWBool("ZMNearbyTransitionGateBlocked", false) then
        draw.SimpleText("PATH BLOCKED", "DermaLarge", ScrW() * 0.5, ScrH() * 0.5 + 38, blockedGateColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local prompt = "PRESS E TO TRAVEL " .. string.upper(gateDirection)
    local color = directionCodes[gateDirection] == getWaypointDirection(LocalPlayer()) and routeGateColor or defaultGateColor
    draw.SimpleText(prompt, "DermaLarge", ScrW() * 0.5, ScrH() * 0.5 + 38, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)