// Client graphics quality presets. A preset writes its values into the individual archived settings; changing any
// of those settings by hand leaves the preset as "custom" unless the values again match a named preset exactly.
ZM_Quality = ZM_Quality or {}

local presetConVar = CreateClientConVar("zombiesim_quality_preset", "high", true, false,
    "Client graphics quality preset: low, medium, high, or custom.")

ZM_Quality.ConVars = {
    rippleAmount = CreateClientConVar("zombiesim_atmosphere_ripple_amount", "1", true, false,
        "Scales rain ripples drawn on puddles (0.1 to 1)."),
    snowDetail = CreateClientConVar("zombiesim_snow_detail", "1", true, false,
        "Lying snow sample density (0.25 to 1). Lower values use wider spacing; changing it rebuilds the cover."),
    snowDrawDistance = CreateClientConVar("zombiesim_snow_draw_distance", "0", true, false,
        "Maximum lying snow draw distance in units; 0 draws as far as the fog allows."),
    screenEffects = CreateClientConVar("zombiesim_screen_effects", "1", true, false,
        "Enables atmosphere colour correction and film grain."),
    skyDetail = CreateClientConVar("zombiesim_sky_detail", "2", true, false,
        "3D skybox neighbour rings drawn around the current cell (0 disables the city skyline)."),
    skyClouds = CreateClientConVar("zombiesim_sky_clouds", "1", true, false,
        "Draws the drifting 3D skybox cloud deck."),
    skyProps = CreateClientConVar("zombiesim_sky_props", "1", true, false,
        "Draws scaled tile props and road wrecks in the 3D skybox (0 off; 0.1 to 1 scales the per-frame prop budget)."),
    skyFires = CreateClientConVar("zombiesim_sky_fires", "1", true, false,
        "Draws burning wrecks, rooftop fires, and their smoke plumes in the 3D skybox.")
}

ZM_Quality.PresetOrder = { "low", "medium", "high" }
ZM_Quality.PresetLabels = { low = "Low", medium = "Medium", high = "High", custom = "Custom" }
// High matches the defaults the game shipped with before presets existed.
ZM_Quality.Presets = {
    low = {
        zombiesim_atmosphere_rain_density = 0.6,
        zombiesim_atmosphere_puddle_amount = 0.5,
        zombiesim_atmosphere_ripple_amount = 0.35,
        zombiesim_snow_detail = 0.4,
        zombiesim_snow_draw_distance = 2500,
        zombiesim_screen_effects = 0,
        zombiesim_ambient_debris_amount = 0.5,
        zombiesim_sky_detail = 1,
        zombiesim_sky_clouds = 0,
        zombiesim_sky_props = 0.4,
        zombiesim_sky_fires = 0
    },
    medium = {
        zombiesim_atmosphere_rain_density = 1,
        zombiesim_atmosphere_puddle_amount = 0.75,
        zombiesim_atmosphere_ripple_amount = 0.65,
        zombiesim_snow_detail = 0.7,
        zombiesim_snow_draw_distance = 4500,
        zombiesim_screen_effects = 1,
        zombiesim_ambient_debris_amount = 0.75,
        zombiesim_sky_detail = 2,
        zombiesim_sky_clouds = 1,
        zombiesim_sky_props = 0.7,
        zombiesim_sky_fires = 1
    },
    high = {
        zombiesim_atmosphere_rain_density = 1.5,
        zombiesim_atmosphere_puddle_amount = 1,
        zombiesim_atmosphere_ripple_amount = 1,
        zombiesim_snow_detail = 1,
        zombiesim_snow_draw_distance = 0,
        zombiesim_screen_effects = 1,
        zombiesim_ambient_debris_amount = 1,
        zombiesim_sky_detail = 2,
        zombiesim_sky_clouds = 1,
        zombiesim_sky_props = 1,
        zombiesim_sky_fires = 1
    }
}

local function presetMatches(values)
    for name, value in pairs(values) do
        local convar = GetConVar(name)
        if not convar or math.abs(convar:GetFloat() - value) > 0.001 then return false end
    end
    return true
end

function ZM_Quality:GetPreset()
    local preset = presetConVar:GetString()
    return self.Presets[preset] and preset or "custom"
end

function ZM_Quality:FindMatchingPreset()
    for _, preset in ipairs(self.PresetOrder) do
        if presetMatches(self.Presets[preset]) then return preset end
    end
    return "custom"
end

function ZM_Quality:ApplyPreset(preset)
    local values = self.Presets[preset]
    if not values then return false end
    for name, value in pairs(values) do
        local convar = GetConVar(name)
        if convar and math.abs(convar:GetFloat() - value) > 0.001 then
            convar:SetString(tostring(value))
        end
    end
    if presetConVar:GetString() ~= preset then
        presetConVar:SetString(preset)
    end
    return true
end

// Re-derives the preset label after any individual change; this is stateless, so callback ordering cannot desync it.
function ZM_Quality:RefreshPreset()
    local matched = self:FindMatchingPreset()
    if presetConVar:GetString() ~= matched then
        presetConVar:SetString(matched)
    end
end

cvars.RemoveChangeCallback("zombiesim_quality_preset", "ZM.Quality.Preset")
cvars.AddChangeCallback("zombiesim_quality_preset", function(_, _, value)
    if ZM_Quality.Presets[value] and not presetMatches(ZM_Quality.Presets[value]) then
        ZM_Quality:ApplyPreset(value)
    end
end, "ZM.Quality.Preset")

local controlled = {}
for _, values in pairs(ZM_Quality.Presets) do
    for name in pairs(values) do controlled[name] = true end
end
for name in pairs(controlled) do
    cvars.RemoveChangeCallback(name, "ZM.Quality.Custom")
    cvars.AddChangeCallback(name, function()
        ZM_Quality:RefreshPreset()
    end, "ZM.Quality.Custom")
end

// The atmosphere and foliage modules create some of these settings after this file loads.
timer.Simple(0, function()
    ZM_Quality:RefreshPreset()
end)
