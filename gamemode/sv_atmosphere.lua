// Server-authoritative, steady weather state shared by clients in outdoor city cells.
ZM_AtmosphereService = ZM_AtmosphereService or {}
local AtmosphereService = ZM_AtmosphereService

AtmosphereService.WeatherCodes = {
    clear = 0,
    rain = 1,
    snow = 2
}

CreateConVar("zombiesim_weather_state", "clear", FCVAR_ARCHIVE, "Server-authoritative steady world weather.")

function AtmosphereService.NormalizeWeather(weather)
    if type(weather) ~= "string" then return nil end
    weather = string.lower(string.Trim(weather))
    return AtmosphereService.WeatherCodes[weather] and weather or nil
end

function AtmosphereService.GetWeatherCode(weather)
    weather = AtmosphereService.NormalizeWeather(weather)
    return weather and AtmosphereService.WeatherCodes[weather] or nil
end

function AtmosphereService.GetWeatherForCode(code)
    if type(code) ~= "number" or code ~= math.floor(code) then return nil end
    for weather, weatherCode in pairs(AtmosphereService.WeatherCodes) do
        if weatherCode == code then return weather end
    end
end

local weatherConVar = GetConVar("zombiesim_weather_state")
AtmosphereService.Weather = AtmosphereService.NormalizeWeather(weatherConVar:GetString())
if not AtmosphereService.Weather then
    ErrorNoHalt("[ZombieSim] Invalid archived weather state; resetting to clear.\n")
    AtmosphereService.Weather = "clear"
    weatherConVar:SetString("clear")
end

// Lying snow accumulates world-wide while it snows and melts otherwise. It is archived so it survives level changes,
// letting each newly loaded map start with the settled cover instead of rebuilding it from nothing.
// The rates must match the client's snow cover constants in cl_atmosphere.lua.
AtmosphereService.SnowBuildSeconds = 180
AtmosphereService.SnowMeltSeconds = 25
AtmosphereService.SnowRainMeltSeconds = 8
CreateConVar("zombiesim_snow_cover", "0", FCVAR_ARCHIVE, "Server-authoritative lying snow amount (0-1).")
local snowCoverConVar = GetConVar("zombiesim_snow_cover")
AtmosphereService.SnowCover = math.Clamp(snowCoverConVar:GetFloat(), 0, 1)

function AtmosphereService:UpdateSnowCover(seconds)
    local amount = self.SnowCover
    if self.Weather == "snow" then
        amount = math.min(1, amount + seconds / self.SnowBuildSeconds)
    else
        amount = math.max(0, amount - seconds / (self.Weather == "rain" and self.SnowRainMeltSeconds or self.SnowMeltSeconds))
    end
    if amount ~= self.SnowCover then
        self.SnowCover = amount
        snowCoverConVar:SetString(string.format("%.4f", amount))
    end
end

timer.Create("ZM.Atmosphere.SnowCover", 1, 0, function()
    AtmosphereService:UpdateSnowCover(1)
end)

util.AddNetworkString("ZM.Atmosphere.Weather")

function AtmosphereService:SendWeather(target)
    net.Start("ZM.Atmosphere.Weather")
        net.WriteUInt(AtmosphereService.GetWeatherCode(AtmosphereService.Weather), 2)
        net.WriteFloat(AtmosphereService.SnowCover)
    if IsValid(target) then
        net.Send(target)
    else
        net.Broadcast()
    end
end

// Seasonal schedule driven by the server clock (northern hemisphere). Each spell rolls clear/rain/snow from the
// month's chances; snow is rare, most likely in December, guaranteed on Christmas Day and never in summer.
AtmosphereService.SeasonalChances = {
    [1] = { snow = 0.10, rain = 0.30 },
    [2] = { snow = 0.08, rain = 0.30 },
    [3] = { snow = 0.03, rain = 0.30 },
    [4] = { snow = 0, rain = 0.30 },
    [5] = { snow = 0, rain = 0.25 },
    [6] = { snow = 0, rain = 0.20 },
    [7] = { snow = 0, rain = 0.20 },
    [8] = { snow = 0, rain = 0.20 },
    [9] = { snow = 0, rain = 0.25 },
    [10] = { snow = 0, rain = 0.35 },
    [11] = { snow = 0.03, rain = 0.35 },
    [12] = { snow = 0.25, rain = 0.30 }
}
AtmosphereService.SpellMinimumSeconds = 8 * 60
AtmosphereService.SpellMaximumSeconds = 25 * 60
AtmosphereService.ScheduleCheckSeconds = 10

CreateConVar("zombiesim_weather_auto", "1", FCVAR_ARCHIVE, "Lets the seasonal schedule change the weather (0 keeps it steady).")
CreateConVar("zombiesim_weather_until", "0", FCVAR_ARCHIVE, "Server time (os.time) when the current weather spell ends.")
CreateConVar("zombiesim_weather_manual", "0", FCVAR_ARCHIVE, "1 while an admin-chosen weather spell is holding.")
local weatherAutoConVar = GetConVar("zombiesim_weather_auto")
local weatherUntilConVar = GetConVar("zombiesim_weather_until")
local weatherManualConVar = GetConVar("zombiesim_weather_manual")

function AtmosphereService.IsChristmasDay(date)
    return date.month == 12 and date.day == 25
end

function AtmosphereService.IsSummer(date)
    return date.month >= 6 and date.month <= 8
end

function AtmosphereService.GetSeasonalChances(date)
    if AtmosphereService.IsChristmasDay(date) then
        return 1, 0
    end
    local chances = AtmosphereService.SeasonalChances[date.month] or { snow = 0, rain = 0.25 }
    local snow = AtmosphereService.IsSummer(date) and 0 or chances.snow
    return snow, chances.rain
end

// roll is a number in [0, 1).
function AtmosphereService.RollSeasonalWeather(date, roll)
    local snow, rain = AtmosphereService.GetSeasonalChances(date)
    if roll < snow then return "snow" end
    if roll < snow + rain then return "rain" end
    return "clear"
end

function AtmosphereService.IsWeatherAllowed(date, weather)
    if AtmosphereService.IsChristmasDay(date) then
        return weather == "snow"
    end
    if weather == "snow" then
        return (AtmosphereService.GetSeasonalChances(date)) > 0
    end
    return true
end

function AtmosphereService.ApplyWeather(weather, reason)
    if weather == AtmosphereService.Weather then return end
    weatherConVar:SetString(weather)
    AtmosphereService.Weather = weather
    AtmosphereService:SendWeather()
    print("[ZombieSim] Weather set to " .. weather .. " (" .. reason .. ").")
end

local function setSpell(now, manual)
    local length = math.random(AtmosphereService.SpellMinimumSeconds, AtmosphereService.SpellMaximumSeconds)
    weatherUntilConVar:SetString(tostring(math.floor(now + length)))
    weatherManualConVar:SetBool(manual)
end

function AtmosphereService.GetSpellEnd()
    return weatherUntilConVar:GetFloat(), weatherManualConVar:GetBool()
end

// now is server os.time(); roll is optional and only injected by tests.
function AtmosphereService:UpdateWeatherSchedule(now, roll)
    if not weatherAutoConVar:GetBool() then return end
    now = now or os.time()
    local date = os.date("*t", now)
    local spellEnd, manual = self.GetSpellEnd()
    local expired = now >= spellEnd
    // An admin choice holds for its spell; otherwise the calendar rules (Christmas snow, no summer snow) apply at once.
    if not expired and (manual or self.IsWeatherAllowed(date, self.Weather)) then return end
    local weather = self.RollSeasonalWeather(date, roll or math.random())
    setSpell(now, false)
    self.ApplyWeather(weather, "seasonal schedule")
end

function AtmosphereService.ResumeWeatherSchedule()
    weatherUntilConVar:SetString("0")
    weatherManualConVar:SetBool(false)
    AtmosphereService:UpdateWeatherSchedule()
end

function AtmosphereService.SetWeather(weather)
    weather = AtmosphereService.NormalizeWeather(weather)
    if not weather then
        return false, "weather must be clear, rain, or snow"
    end

    setSpell(os.time(), true)
    AtmosphereService.ApplyWeather(weather, "admin")
    return true
end

timer.Create("ZM.Atmosphere.WeatherSchedule", AtmosphereService.ScheduleCheckSeconds, 0, function()
    AtmosphereService:UpdateWeatherSchedule()
end)
timer.Simple(0, function()
    AtmosphereService:UpdateWeatherSchedule()
end)

hook.Add("PlayerInitialSpawn", "ZM.Atmosphere.SendWeather", function(playerEntity)
    timer.Simple(1, function()
        if IsValid(playerEntity) then
            AtmosphereService:SendWeather(playerEntity)
        end
    end)
end)

ZM_Util.RegisterCommands({
    zombiesim_weather = "Sets world weather: clear, rain, or snow (holds for one spell), or auto to resume the seasonal schedule."
}, function(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command) then return end
    local weather = arguments and arguments[1] or nil
    if type(weather) == "string" then
        weather = string.Trim(weather)
        if weather == "" then weather = nil end
    end
    if not weather then
        local spellEnd, manual = AtmosphereService.GetSpellEnd()
        local mode = not GetConVar("zombiesim_weather_auto"):GetBool() and "steady (schedule off)"
            or (manual and "admin hold" or "seasonal schedule")
        local remaining = math.max(0, math.floor(spellEnd - os.time()))
        ZM_Util.Reply(caller, string.format("Current weather: %s (%s, next change in %dm %02ds). Usage: zombiesim_weather <clear|rain|snow|auto>.",
            AtmosphereService.Weather, mode, math.floor(remaining / 60), remaining % 60))
        return true
    end

    if string.lower(weather) == "auto" then
        AtmosphereService.ResumeWeatherSchedule()
        ZM_Util.Reply(caller, "Seasonal weather schedule resumed: " .. AtmosphereService.Weather .. ".")
        return true
    end

    local changed, changeError = AtmosphereService.SetWeather(weather)
    if not changed then
        ZM_Util.Reply(caller, changeError)
        return false, changeError
    end
    return true
end)
