// Client-local world fog and colour correction driven by the logical cell's compact profile id.
ZM_Atmosphere = ZM_Atmosphere or {}
local Atmosphere = ZM_Atmosphere

Atmosphere.ActiveProfileIndex = Atmosphere.ActiveProfileIndex or nil
Atmosphere.StormIntensity = Atmosphere.StormIntensity or 0

local function getNumber(value, fallback)
    value = tonumber(value)
    return value and value or fallback
end

local function getColorComponent(color, index)
    return math.Clamp(getNumber(color and color[index], 0), 0, 255)
end

function Atmosphere:GetActiveProfile()
    return ZM_World:GetAtmosphereProfileByIndex(self.ActiveProfileIndex)
end

function Atmosphere:ApplyProfile(profileIndex)
    profileIndex = tonumber(profileIndex)
    local profile = profileIndex and ZM_World:GetAtmosphereProfileByIndex(profileIndex) or nil
    if not profile then
        return false
    end

    self.ActiveProfileIndex = math.floor(profileIndex)
    return true
end

function Atmosphere:ApplyPlayerProfile()
    local player = LocalPlayer()
    if not IsValid(player) then
        return false
    end

    local gridX, gridY = ZM_World:GetGridCoordinates(player:GetNWInt("CellX", 0), player:GetNWInt("CellY", 0))
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    return cell and self:ApplyProfile(cell.atmosphereProfile) or false
end

// A future server-authoritative weather event can set this from 0 (clear) to 1 (full storm).
function Atmosphere:SetStormIntensity(intensity)
    self.StormIntensity = math.Clamp(getNumber(intensity, 0), 0, 1)
end

function Atmosphere:GetFogSettings()
    local profile = self:GetActiveProfile()
    local fog = profile and profile.fog
    if type(fog) ~= "table" then
        return nil
    end

    local stormMultiplier = math.Clamp(getNumber(fog.stormMultiplier, 1), 0.1, 1)
    local visibilityMultiplier = 1 + (stormMultiplier - 1) * self.StormIntensity
    local maxDensity = math.Clamp(getNumber(fog.maxDensity, 1), 0, 1)
    return {
        color = fog.color,
        start = math.max(0, getNumber(fog.start, 0) * visibilityMultiplier),
        finish = math.max(1, getNumber(fog["end"], 1) * visibilityMultiplier),
        maxDensity = math.Clamp(maxDensity + (1 - maxDensity) * self.StormIntensity, 0, 1)
    }
end

local function applyFog(settings, scale)
    scale = scale or 1
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(settings.start * scale)
    render.FogEnd(math.max(settings.finish * scale, settings.start * scale + 1))
    render.FogMaxDensity(settings.maxDensity)
    render.FogColor(getColorComponent(settings.color, 1), getColorComponent(settings.color, 2), getColorComponent(settings.color, 3))
    return true
end

hook.Add("SetupWorldFog", "ZM.Atmosphere.WorldFog", function()
    local settings = Atmosphere:GetFogSettings()
    return settings and applyFog(settings) or false
end)

hook.Add("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", function(scale)
    local settings = Atmosphere:GetFogSettings()
    return settings and applyFog(settings, scale) or false
end)

hook.Add("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection", function()
    local profile = Atmosphere:GetActiveProfile()
    local correction = profile and profile.colorCorrection
    if type(correction) ~= "table" then
        return
    end

    local add = correction.add or {}
    local multiply = correction.multiply or {}
    DrawColorModify({
        ["$pp_colour_addr"] = getNumber(add[1], 0),
        ["$pp_colour_addg"] = getNumber(add[2], 0),
        ["$pp_colour_addb"] = getNumber(add[3], 0),
        ["$pp_colour_brightness"] = getNumber(correction.brightness, 0),
        ["$pp_colour_contrast"] = getNumber(correction.contrast, 1),
        ["$pp_colour_colour"] = getNumber(correction.colour, 1),
        ["$pp_colour_mulr"] = getNumber(multiply[1], 1),
        ["$pp_colour_mulg"] = getNumber(multiply[2], 1),
        ["$pp_colour_mulb"] = getNumber(multiply[3], 1)
    })
end)

net.Receive("ZM.SetAtmosphereProfile", function()
    Atmosphere:ApplyProfile(net.ReadUInt(8))
end)

hook.Add("InitPostEntity", "ZM.Atmosphere.ApplyLoadedCell", function()
    timer.Simple(0, function()
        Atmosphere:ApplyPlayerProfile()
    end)
end)