local suite = ZM_TestHarness.NewSuite()
local AtmosphereService = ZM_AtmosphereService

suite:Add("weather_names_are_normalized_and_limited", function(check)
    check(AtmosphereService.NormalizeWeather("CLEAR") == "clear", "weather names should be case-insensitive")
    check(AtmosphereService.NormalizeWeather(" rain ") == "rain", "surrounding whitespace should be ignored")
    check(AtmosphereService.NormalizeWeather("snow") == "snow", "snow should be a supported weather state")
    check(AtmosphereService.NormalizeWeather("storm") == nil, "unknown weather states must be rejected")
    check(AtmosphereService.NormalizeWeather(nil) == nil, "missing weather state must be rejected")
end)

suite:Add("weather_network_codes_round_trip", function(check)
    for weather, expectedCode in pairs({ clear = 0, rain = 1, snow = 2 }) do
        local code = AtmosphereService.GetWeatherCode(weather)
        check(code == expectedCode, weather .. " has an unexpected network code")
        check(AtmosphereService.GetWeatherForCode(code) == weather, weather .. " did not round-trip")
    end
    check(AtmosphereService.GetWeatherForCode(3) == nil, "unknown weather code must be rejected")
    check(AtmosphereService.GetWeatherForCode(1.5) == nil, "fractional weather code must be rejected")
end)

suite:Add("invalid_weather_state_does_not_change_the_server", function(check)
    local originalWeather = AtmosphereService.Weather
    local changed, changeError = AtmosphereService.SetWeather("storm")
    check(not changed and changeError ~= nil, "unsupported weather should report failure")
    check(AtmosphereService.Weather == originalWeather, "unsupported weather changed the active state")
end)

suite:Add("snow_cover_accumulates_and_melts", function(check)
    local originalWeather, originalCover = AtmosphereService.Weather, AtmosphereService.SnowCover
    AtmosphereService.Weather = "snow"
    AtmosphereService.SnowCover = 0
    AtmosphereService:UpdateSnowCover(AtmosphereService.SnowBuildSeconds * 0.5)
    check(math.abs(AtmosphereService.SnowCover - 0.5) < 0.001, "snow should settle gradually over the build time")
    AtmosphereService:UpdateSnowCover(AtmosphereService.SnowBuildSeconds)
    check(AtmosphereService.SnowCover == 1, "snow cover must clamp at fully settled")
    AtmosphereService.Weather = "rain"
    AtmosphereService:UpdateSnowCover(AtmosphereService.SnowRainMeltSeconds * 0.5)
    check(math.abs(AtmosphereService.SnowCover - 0.5) < 0.001, "rain should melt snow at the rain rate")
    AtmosphereService.Weather = "clear"
    AtmosphereService:UpdateSnowCover(AtmosphereService.SnowMeltSeconds)
    check(AtmosphereService.SnowCover == 0, "snow cover must clamp at fully melted")
    AtmosphereService.Weather = originalWeather
    AtmosphereService.SnowCover = originalCover
    GetConVar("zombiesim_snow_cover"):SetString(string.format("%.4f", originalCover))
end)

local function dateAt(month, day)
    return os.date("*t", os.time({ year = 2026, month = month, day = day, hour = 12 }))
end

suite:Add("seasonal_weather_follows_the_calendar", function(check)
    for _, roll in ipairs({ 0, 0.3, 0.6, 0.999 }) do
        check(AtmosphereService.RollSeasonalWeather(dateAt(12, 25), roll) == "snow", "Christmas Day must always snow")
    end
    for month = 6, 8 do
        for roll = 0, 0.99, 0.01 do
            check(AtmosphereService.RollSeasonalWeather(dateAt(month, 15), roll) ~= "snow", "summer must never snow (month " .. month .. ")")
        end
        check(not AtmosphereService.IsWeatherAllowed(dateAt(month, 15), "snow"), "summer must not allow lying snow")
    end
    local decemberSnow = AtmosphereService.GetSeasonalChances(dateAt(12, 10))
    local yearlySnow = 0
    for month = 1, 12 do
        local snow = AtmosphereService.GetSeasonalChances(dateAt(month, 10))
        yearlySnow = yearlySnow + snow / 12
        if month ~= 12 then
            check(snow < decemberSnow, "December must be the snowiest month (month " .. month .. ")")
        end
    end
    check(yearlySnow < 0.08, "snow must be rare across the year")
    check(not AtmosphereService.IsWeatherAllowed(dateAt(12, 25), "rain"), "Christmas must replace other weather with snow")
end)

suite:Add("weather_schedule_respects_holds_and_calendar", function(check)
    local originalWeather = AtmosphereService.Weather
    local untilConVar, manualConVar = GetConVar("zombiesim_weather_until"), GetConVar("zombiesim_weather_manual")
    local autoConVar = GetConVar("zombiesim_weather_auto")
    local originalUntil, originalManual, originalAuto = untilConVar:GetString(), manualConVar:GetString(), autoConVar:GetString()
    autoConVar:SetBool(true)
    local christmas = os.time({ year = 2026, month = 12, day = 25, hour = 12 })
    local summer = os.time({ year = 2026, month = 7, day = 15, hour = 12 })

    AtmosphereService.ApplyWeather("rain", "test")
    untilConVar:SetString(tostring(christmas + 600))
    manualConVar:SetBool(false)
    AtmosphereService:UpdateWeatherSchedule(christmas, 0.99)
    check(AtmosphereService.Weather == "snow", "Christmas Day must switch a scheduled spell to snow immediately")

    AtmosphereService.ApplyWeather("rain", "test")
    untilConVar:SetString(tostring(christmas + 600))
    manualConVar:SetBool(true)
    AtmosphereService:UpdateWeatherSchedule(christmas, 0.99)
    check(AtmosphereService.Weather == "rain", "an admin hold must last until its spell ends")
    AtmosphereService:UpdateWeatherSchedule(christmas + 601, 0.99)
    check(AtmosphereService.Weather == "snow", "the schedule must resume after an admin hold")

    AtmosphereService.ApplyWeather("snow", "test")
    untilConVar:SetString(tostring(summer + 600))
    manualConVar:SetBool(false)
    AtmosphereService:UpdateWeatherSchedule(summer, 0)
    check(AtmosphereService.Weather ~= "snow", "scheduled snow must stop in summer")
    local spellEnd = untilConVar:GetFloat()
    check(spellEnd >= summer + AtmosphereService.SpellMinimumSeconds and spellEnd <= summer + AtmosphereService.SpellMaximumSeconds,
        "a new spell must use the configured length")

    autoConVar:SetBool(false)
    AtmosphereService.ApplyWeather("snow", "test")
    untilConVar:SetString("0")
    AtmosphereService:UpdateWeatherSchedule(summer, 0.99)
    check(AtmosphereService.Weather == "snow", "a disabled schedule must leave the weather steady")

    autoConVar:SetString(originalAuto)
    untilConVar:SetString(originalUntil)
    manualConVar:SetString(originalManual)
    AtmosphereService.ApplyWeather(originalWeather, "test restore")
end)

suite:Add("weather_controls_are_registered", function(check)
    check(type(concommand.GetTable().zombiesim_weather) == "function", "weather console command is not registered")
    check(type(ZM_DevConsole.DirectCommands.zombiesim_weather) == "function", "weather bridge command is not registered")
end)

ZM_TestHarness.Register({
    command = "zn_test_atmosphere",
    label = "Atmosphere",
    file = "atmosphere_tests.json",
    report = "atmosphereTests",
    help = "Runs the weather-state validation, encoding, snow cover and seasonal schedule tests.",
    run = function() return suite:Run() end
})
