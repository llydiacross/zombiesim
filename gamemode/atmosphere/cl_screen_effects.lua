// Screen colour correction, radiation composition, frost borders and optional film grain.
return function(Atmosphere, Modules)
    local Core = Modules.Core
    CreateClientConVar("zombiesim_atmosphere_grain", "0", true, false, "Enables subtle animated film grain.")
    local nextGrainUpdateAt = 0
    local grainRects = {}
    local grainSeed = 0
    local frostEdgeStrips = 18

    local function drawFrostEdges()
        local amount = Atmosphere.FrostAmount or 0
        if amount <= 0.01 then return end
        local width, height = ScrW(), ScrH()
        local depth = math.floor(math.min(width, height) * 0.16)
        local stripSize = math.max(1, math.ceil(depth / frostEdgeStrips))
        cam.Start2D()
        for strip = 0, frostEdgeStrips - 1 do
            local falloff = 1 - strip / frostEdgeStrips
            surface.SetDrawColor(214, 228, 240, 34 * amount * falloff * falloff)
            local offset = strip * stripSize
            surface.DrawRect(0, offset, width, stripSize)
            surface.DrawRect(0, height - offset - stripSize, width, stripSize)
            surface.DrawRect(offset, 0, stripSize, height)
            surface.DrawRect(width - offset - stripSize, 0, stripSize, height)
        end
        cam.End2D()
    end

    local function updateGrain()
        local grain = GetConVar("zombiesim_atmosphere_grain")
        if not grain or not grain:GetBool() or (ZM_LauncherMenu and ZM_LauncherMenu.Active) then return end
        if ZM_LoadingScreen and CurTime() < ZM_LoadingScreen.HideUntil then return end

        local now = RealTime()
        if now >= nextGrainUpdateAt then
            nextGrainUpdateAt = now + 0.075
            grainSeed = grainSeed + 1
            grainRects = {}
            local width, height = ScrW(), ScrH()
            for index = 1, 52 do
                grainRects[#grainRects + 1] = {
                    x = math.floor(util.SharedRandom("ZM.Atmosphere.GrainX" .. grainSeed .. ":" .. index, 0, width)),
                    y = math.floor(util.SharedRandom("ZM.Atmosphere.GrainY" .. grainSeed .. ":" .. index, 0, height)),
                    size = math.floor(util.SharedRandom("ZM.Atmosphere.GrainSize" .. grainSeed .. ":" .. index, 1, 4)),
                    shade = math.floor(util.SharedRandom("ZM.Atmosphere.GrainShade" .. grainSeed .. ":" .. index, 130, 256))
                }
            end
        end

        cam.Start2D()
        for _, rect in ipairs(grainRects) do
            surface.SetDrawColor(rect.shade, rect.shade, rect.shade, 18)
            surface.DrawRect(rect.x, rect.y, rect.size, rect.size)
        end
        cam.End2D()
    end

    local colourCorrectionSettings = {}
    local emptyTable = {}

    function Modules.ScreenEffects.RegisterHooks()
        hook.Add("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection", function()
            if ZM_LauncherMenu and ZM_LauncherMenu.Active then
                Core.RecordHookResult("RenderScreenspaceEffects", nil, false, nil, nil, "launcher menu active")
                return
            end
            local profile = Atmosphere:GetActiveProfile()
            local correction = profile and profile.colorCorrection
            if type(correction) ~= "table" then
                Core.RecordHookResult("RenderScreenspaceEffects", nil, false, nil, nil, "no active colour-correction profile")
                return
            end

            local add = correction.add or emptyTable
            local multiply = correction.multiply or emptyTable
            local colorSettings = colourCorrectionSettings
            colorSettings["$pp_colour_addr"] = Core.GetNumber(add[1], 0)
            colorSettings["$pp_colour_addg"] = Core.GetNumber(add[2], 0)
            colorSettings["$pp_colour_addb"] = Core.GetNumber(add[3], 0)
            colorSettings["$pp_colour_brightness"] = Core.GetNumber(correction.brightness, 0)
            colorSettings["$pp_colour_contrast"] = Core.GetNumber(correction.contrast, 1)
            colorSettings["$pp_colour_colour"] = Core.GetNumber(correction.colour, 1)
            colorSettings["$pp_colour_mulr"] = Core.GetNumber(multiply[1], 1)
            colorSettings["$pp_colour_mulg"] = Core.GetNumber(multiply[2], 1)
            colorSettings["$pp_colour_mulb"] = Core.GetNumber(multiply[3], 1)
            // Cold grade: desaturate, cool the shadows and lift the mids slightly while snow is falling.
            local winter = Atmosphere.WinterBlend or 0
            if winter > 0.001 then
                colorSettings["$pp_colour_colour"] = colorSettings["$pp_colour_colour"] * (1 - 0.32 * winter)
                colorSettings["$pp_colour_brightness"] = colorSettings["$pp_colour_brightness"] + 0.025 * winter
                colorSettings["$pp_colour_contrast"] = colorSettings["$pp_colour_contrast"] * (1 - 0.05 * winter)
                colorSettings["$pp_colour_addr"] = colorSettings["$pp_colour_addr"] - 0.01 * winter
                colorSettings["$pp_colour_addb"] = colorSettings["$pp_colour_addb"] + 0.025 * winter
                colorSettings["$pp_colour_mulb"] = colorSettings["$pp_colour_mulb"] + 0.08 * winter
            end
            // The low preset turns off the full-screen grade and grain; frost edges remain because they convey the weather.
            local radiationGray = ZM_RadiationFeedback.GetGrayscale()
            local radiationSeverity = ZM_RadiationFeedback.GetExtremeVisualSeverity()
            colorSettings["$pp_colour_colour"] = colorSettings["$pp_colour_colour"] * (1 - radiationGray)
            if radiationGray > 0 then
                colorSettings["$pp_colour_addr"] = colorSettings["$pp_colour_addr"] * (1 - radiationGray)
                colorSettings["$pp_colour_addg"] = colorSettings["$pp_colour_addg"] * (1 - radiationGray)
                colorSettings["$pp_colour_addb"] = colorSettings["$pp_colour_addb"] * (1 - radiationGray)
                colorSettings["$pp_colour_mulr"] = colorSettings["$pp_colour_mulr"] * (1 - radiationGray)
                colorSettings["$pp_colour_mulg"] = colorSettings["$pp_colour_mulg"] * (1 - radiationGray)
                colorSettings["$pp_colour_mulb"] = colorSettings["$pp_colour_mulb"] * (1 - radiationGray)
                colorSettings["$pp_colour_contrast"] = colorSettings["$pp_colour_contrast"] + 0.4 * radiationSeverity
                colorSettings["$pp_colour_brightness"] = colorSettings["$pp_colour_brightness"] - 0.04 * radiationSeverity
            end
            if Atmosphere.GetQualityNumber("screenEffects", 1, 0, 1) < 0.5 then
                if ZM_RadiationFeedback.GetGrayscale() > 0 then
                    colorSettings["$pp_colour_addr"], colorSettings["$pp_colour_addg"], colorSettings["$pp_colour_addb"] = 0, 0, 0
                    colorSettings["$pp_colour_mulr"], colorSettings["$pp_colour_mulg"], colorSettings["$pp_colour_mulb"] = 0, 0, 0
                    colorSettings["$pp_colour_brightness"], colorSettings["$pp_colour_contrast"] = -0.04 * radiationSeverity, 1 + 0.4 * radiationSeverity
                    colorSettings["$pp_colour_colour"] = 1 - radiationGray
                    DrawColorModify(colorSettings)
                end
                Core.RecordHookResult("RenderScreenspaceEffects", nil, false, nil, nil, "screen effects disabled by quality setting")
                drawFrostEdges()
                return
            end
            DrawColorModify(colorSettings)
            Core.RecordHookResult("RenderScreenspaceEffects", nil, true, Atmosphere:GetFogSettings(), nil,
                "DrawColorModify applied; hook chain continues", colorSettings)
            drawFrostEdges()
            updateGrain()
        end)
    end
end
