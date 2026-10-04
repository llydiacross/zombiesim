local Feedback = ZM_RadiationFeedback
local volume = CreateClientConVar("zombiesim_geiger_volume", "0.35", true, false, "Geiger click volume; 0 disables audio.", 0, 1)
local visual = CreateClientConVar("zombiesim_geiger_visual", "1", true, false, "Radiation meter pulse intensity; 0 keeps the static readout.", 0, 1)
local grayscale = CreateClientConVar("zombiesim_radiation_extreme_grayscale", "1", true, false,
    "Black-and-white radiation effects above 15 Sv only; 0 disables.", 0, 1)
local shake = CreateClientConVar("zombiesim_radiation_extreme_shake", "1", true, false,
    "Extreme radiation camera tremor above 15 Sv only; 0 disables.", 0, 1)
local corners = CreateClientConVar("zombiesim_radiation_corners", "1", true, false,
    "Unprotected radiation corner vignette strength; 0 disables.", 0, 1)
local symbol = CreateClientConVar("zombiesim_radiation_symbol", "1", true, false,
    "Shows a slowly pulsing radiation warning symbol, including while protected.", 0, 1)
local cornerTexture = GetRenderTargetEx("zombiesim_radiation_corner_mask_v2", 64, 64,
    RT_SIZE_LITERAL or 8, MATERIAL_RT_DEPTH_NONE or 2, bit.bor(4, 8), 0, IMAGE_FORMAT_RGBA8888 or 0)
local cornerMaterial = cornerTexture and CreateMaterial("zombiesim_radiation_corners_v2", "UnlitGeneric", {
    ["$basetexture"] = cornerTexture:GetName(),
    ["$translucent"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1"
})
local cornersAvailable = cornerMaterial ~= nil and not cornerMaterial:IsError() and cornerTexture:Width() > 0
local cornerMaskReady = false
if not cornersAvailable then ErrorNoHalt("[ZombieSim] Radiation corner material is unavailable.\n") end

hook.Add("PreRender", "ZM.RadiationFeedback.BuildCornerMask", function()
    if cornerMaskReady or not cornersAvailable then return end
    render.PushRenderTarget(cornerTexture)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(255, 255, 255, 0)
    // Copy straight RGBA into the mask, rather than blending opaque black sprite texels.
    render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    cam.Start2D()
    for y = 0, 63 do
        for x = 0, 63 do
            local alpha = Feedback.CornerMaskAlpha((x + 0.5 - 32) / 32, (y + 0.5 - 32) / 32)
            surface.SetDrawColor(255, 255, 255, math.floor(alpha * 255 + 0.5))
            surface.DrawRect(x, y, 1, 1)
        end
    end
    cam.End2D()
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    cornerMaskReady = true
    hook.Remove("PreRender", "ZM.RadiationFeedback.BuildCornerMask")
end)
local clickPaths = { "player/geiger1.wav", "player/geiger2.wav", "player/geiger3.wav" }
local nextClick = 0
local smoothed = 0
local extremeBlend = 0
local extremeSeverity = 0
local warningIntensity = 0
local cornerIntensity = 0
local symbolPhase = 0
local symbolGeometry
local symbolGeometrySize = 0
local cornerDrawCount = 0
local symbolDrawCount = 0
local clicks = 0
local soundAvailable = true
for _, path in ipairs(clickPaths) do
    if not file.Exists("sound/" .. path, "GAME") then
        soundAvailable = false
        ErrorNoHalt("[ZombieSim] Mounted Geiger click is unavailable: " .. path .. "\n")
    end
end

function Feedback.ClientActive()
    local target = LocalPlayer()
    return IsValid(target) and target:Alive() and ZM_World:IsLoaded() and target:GetWorldCell() ~= nil
        and not ZM_SafeZones:IsPlayerInside(target)
        and not (ZM_LauncherMenu and ZM_LauncherMenu.Active)
        and not (ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud())
        and not gui.IsGameUIVisible() and not vgui.CursorVisible()
end

function Feedback.GetClientChannels()
    if not Feedback.ClientActive() then return 0, 0 end
    local target = LocalPlayer()
    return math.Clamp(target:GetRadiationIntensity() or 0, 0, 1),
        math.Clamp(target:GetNWFloat("ZM_RadiatedProximity", 0), 0, 1)
end

hook.Add("Think", "ZM.RadiationFeedback", function()
    local cell, proximity = Feedback.GetClientChannels()
    local intensity = Feedback.SensoryIntensity(cell, proximity)
    local smoothing = 1 - math.exp(-5 * FrameTime())
    smoothed = Lerp(smoothing, smoothed, intensity)
    local target = LocalPlayer()
    local protected = IsValid(target) and target:HasRadiationProtection()
    local severity = Feedback.ExtremeSeverity(cell, proximity, protected)
    warningIntensity = Lerp(smoothing, warningIntensity, Feedback.WarningIntensity(cell, proximity))
    cornerIntensity = Lerp(smoothing, cornerIntensity, Feedback.CornerIntensity(cell, proximity, protected))
    symbolPhase = (symbolPhase + FrameTime() * Feedback.SymbolFrequency(warningIntensity)) % 1
    extremeBlend = Lerp(smoothing, extremeBlend, severity > 0 and 1 or 0)
    extremeSeverity = Lerp(smoothing, extremeSeverity, severity)
    if not Feedback.ClientActive() then smoothed, extremeBlend, extremeSeverity, warningIntensity, cornerIntensity = 0, 0, 0, 0, 0 end
    if protected then extremeBlend, extremeSeverity, cornerIntensity = 0, 0, 0 end
    local now = CurTime()
    if smoothed <= 0.005 or volume:GetFloat() <= 0 or not soundAvailable then
        nextClick = now
        return
    end
    if now >= nextClick then
        nextClick = now + Feedback.ClickDelay(smoothed, math.Rand(0, 1))
        // EmitSound entity -2 is local UI audio, independent of the gameplay camera position.
        EmitSound(clickPaths[math.random(#clickPaths)], vector_origin, -2, CHAN_AUTO,
            volume:GetFloat() * Feedback.AudioGain(smoothed), 0, 0, 100)
        clicks = clicks + 1
    end
end)

function Feedback.GetGrayscale()
    return Feedback.ClientActive() and not LocalPlayer():HasRadiationProtection() and extremeBlend * grayscale:GetFloat() or 0
end

function Feedback.GetExtremeVisualSeverity()
    return Feedback.ClientActive() and not LocalPlayer():HasRadiationProtection()
        and extremeSeverity * grayscale:GetFloat() or 0
end

function Feedback.ApplyCamera(view)
    if not Feedback.ClientActive() or LocalPlayer():HasRadiationProtection() or extremeBlend <= 0
        or ZM_WorldMap and ZM_WorldMap.Capturing then return end
    local strength = extremeBlend * (0.4 + 0.6 * extremeSeverity) * shake:GetFloat() * 3
    local now = CurTime()
    view.angles = Angle(view.angles.p + math.sin(now * 23) * strength,
        view.angles.y + math.sin(now * 29) * strength, view.angles.r)
end

function Feedback.GetMeterPulse()
    if not Feedback.ClientActive() then return 0 end
    return visual:GetFloat() * smoothed * (0.5 + 0.5 * math.sin(CurTime() * 7))
end

function Feedback.GetSymbolRect()
    local scale = math.Clamp(ScrH() / 1080, 0.75, 1.5)
    local size = 46 * scale
    local visible = symbol:GetBool() and warningIntensity > 0.005 and Feedback.ClientActive()
    return 24 * scale, 24 * scale, visible and size or 0, visible and size or 0
end

hook.Add("HUDPaintBackground", "ZM.RadiationFeedback.Corners", function()
    cornerDrawCount = 0
    if not cornersAvailable or not cornerMaskReady or cornerIntensity <= 0.005 or corners:GetFloat() <= 0
        or not Feedback.ClientActive() or LocalPlayer():HasRadiationProtection()
        or ZM_WorldMap and ZM_WorldMap.Capturing then return end
    local width, height = ScrW(), ScrH()
    local extent = math.min(width, height) * (0.14 + 0.16 * cornerIntensity)
    local diameter = extent * 2
    local monochrome = Feedback.GetGrayscale()
    surface.SetMaterial(cornerMaterial)
    surface.SetDrawColor(7 + monochrome * 3, 24 - monochrome * 14, 8 + monochrome * 2,
        190 * cornerIntensity ^ 1.3 * corners:GetFloat())
    surface.DrawTexturedRect(-extent, -extent, diameter, diameter)
    surface.DrawTexturedRect(width - extent, -extent, diameter, diameter)
    surface.DrawTexturedRect(-extent, height - extent, diameter, diameter)
    surface.DrawTexturedRect(width - extent, height - extent, diameter, diameter)
    cornerDrawCount = 4
end)

local function buildSymbol(x, y, size)
    local centerX, centerY = x + size * 0.5, y + size * 0.5
    local function point(radius, angle)
        return { x = centerX + math.cos(angle) * radius, y = centerY + math.sin(angle) * radius }
    end
    local geometry = { badge = {}, dot = {}, blades = {} }
    for segment = 0, 31 do
        local angle = segment * math.pi * 2 / 32
        geometry.badge[#geometry.badge + 1] = point(size * 0.5, angle)
        geometry.dot[#geometry.dot + 1] = point(size * 0.085, angle)
    end
    // Each annular blade is split into convex quads for surface.DrawPoly.
    for blade = 0, 2 do
        for segment = 0, 7 do
            local first = math.rad(-120 + blade * 120 + segment * 7.5)
            local last = first + math.rad(7.5)
            geometry.blades[#geometry.blades + 1] = {
                point(size * 0.40, first), point(size * 0.40, last),
                point(size * 0.16, last), point(size * 0.16, first)
            }
        end
    end
    return geometry
end

hook.Add("HUDPaint", "ZM.RadiationFeedback.Symbol", function()
    symbolDrawCount = 0
    if ZM_WorldMap and ZM_WorldMap.Capturing then return end
    local x, y, size = Feedback.GetSymbolRect()
    if size <= 0 then return end
    if not symbolGeometry or symbolGeometrySize ~= size then
        symbolGeometry, symbolGeometrySize = buildSymbol(x, y, size), size
    end
    local pulse = 0.2 + 0.8 * (0.5 + 0.5 * math.cos(symbolPhase * math.pi * 2))
    local alpha = (120 + 135 * warningIntensity) * pulse
    draw.NoTexture()
    surface.SetDrawColor(230, 200 - 85 * warningIntensity, 40, alpha)
    surface.DrawPoly(symbolGeometry.badge)
    surface.SetDrawColor(15, 18, 10, alpha)
    surface.DrawPoly(symbolGeometry.dot)
    for _, blade in ipairs(symbolGeometry.blades) do surface.DrawPoly(blade) end
    symbolDrawCount = 26
end)

function Feedback:GetDiagnosticSnapshot()
    local cell, proximity = self.GetClientChannels()
    return {
        cell = cell, proximity = proximity, sensory = smoothed, radius = self.Radius,
        active = self.ClientActive(), clicks = clicks, soundAvailable = soundAvailable,
        soundPaths = clickPaths, soundPlayback = "non-positional local UI",
        audioGain = self.AudioGain(smoothed), cadence = "bounded randomized intervals",
        zombies = ZM_RadiatedZombies and ZM_RadiatedZombies:GetDiagnosticSnapshot() or nil,
        volume = volume:GetFloat(), visual = visual:GetFloat(), grayscale = grayscale:GetFloat(), shake = shake:GetFloat(),
        protected = IsValid(LocalPlayer()) and LocalPlayer():HasRadiationProtection(),
        extremeSeverity = extremeSeverity, extremeBlend = extremeBlend,
        warningIntensity = warningIntensity, cornerIntensity = cornerIntensity,
        corners = corners:GetFloat(), cornersAvailable = cornersAvailable, cornerDraws = cornerDrawCount,
        cornerMaskReady = cornerMaskReady, cornerMaskVersion = 2,
        cornerTextureWidth = cornerTexture and cornerTexture:Width() or 0,
        symbol = symbol:GetBool(), symbolFrequencyHz = self.SymbolFrequency(warningIntensity), symbolPolygons = symbolDrawCount,
        damageChannel = "cell baseline; above 15 Sv combined, 1 HP / 2 seconds without floor",
        displayedSv = self.DisplaySv(cell, proximity)
    }
end
