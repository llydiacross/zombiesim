// Client-local world fog and colour correction driven by the logical cell's compact profile id.
ZM_Atmosphere = ZM_Atmosphere or {}
local Atmosphere = ZM_Atmosphere

Atmosphere.ActiveProfileIndex = Atmosphere.ActiveProfileIndex or nil
Atmosphere.StormIntensity = Atmosphere.StormIntensity or 0
Atmosphere.PendingProfileIndex = Atmosphere.PendingProfileIndex or nil
Atmosphere.LastApplySource = Atmosphere.LastApplySource or "none"

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

function Atmosphere:ApplyProfile(profileIndex, source)
    profileIndex = tonumber(profileIndex)
    if not profileIndex then
        ErrorNoHalt("[ZombieSim] Atmosphere received a non-numeric profile index.\n")
        return false
    end
    local profile = ZM_World:GetAtmosphereProfileByIndex(profileIndex)
    if not profile then
        if not ZM_World:IsLoaded() then
            self.PendingProfileIndex = profileIndex
            self.LastApplySource = tostring(source or "unknown") .. " (waiting for world data)"
        else
            ErrorNoHalt("[ZombieSim] Unknown atmosphere profile index: " .. tostring(profileIndex) .. "\n")
        end
        return false
    end

    self.ActiveProfileIndex = math.floor(profileIndex)
    self.PendingProfileIndex = nil
    self.LastApplySource = source or "unknown"
    return true
end

function Atmosphere:ApplyPlayerProfile(source)
    local player = LocalPlayer()
    if not IsValid(player) then
        return false
    end

    if not ZM_World:IsLoaded() then
        return false
    end
    local gridX, gridY = ZM_World:GetGridCoordinates(player.CellX or player:GetNWInt("CellX", 0), player.CellY or player:GetNWInt("CellY", 0))
    local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    return cell and self:ApplyProfile(cell.atmosphereProfile, source or "player data") or false
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
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local settings = Atmosphere:GetFogSettings()
    return settings and applyFog(settings) or false
end)

hook.Add("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", function(scale)
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
    local settings = Atmosphere:GetFogSettings()
    return settings and applyFog(settings, scale) or false
end)

hook.Add("RenderScreenspaceEffects", "ZM.Atmosphere.ColourCorrection", function()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
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
    Atmosphere:ApplyProfile(net.ReadUInt(8), "server")
end)

hook.Add("InitPostEntity", "ZM.Atmosphere.ApplyLoadedCell", function()
    timer.Simple(0, function()
        Atmosphere:ApplyPlayerProfile("InitPostEntity")
    end)
end)

hook.Add("Think", "ZM.Atmosphere.WaitForWorldData", function()
    if not Atmosphere.PendingProfileIndex or not ZM_World:IsLoaded() then return end
    Atmosphere:ApplyProfile(Atmosphere.PendingProfileIndex, "world data ready")
end)

concommand.Add("zombiesim_atmosphere_status", function()
    local player = LocalPlayer()
    local profile = Atmosphere:GetActiveProfile()
    local settings = Atmosphere:GetFogSettings()
    local worldReady = ZM_World:IsLoaded()
    local cell
    if worldReady and IsValid(player) then
        local gridX, gridY = ZM_World:GetGridCoordinates(player.CellX or player:GetNWInt("CellX", 0), player.CellY or player:GetNWInt("CellY", 0))
        cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
    end
    print(string.format("[ZombieSim] Atmosphere: world=%s active=%s expected=%s pending=%s source=%s storm=%.2f fog=%s",
        tostring(worldReady), tostring(Atmosphere.ActiveProfileIndex),
        tostring(cell and cell.atmosphereProfile), tostring(Atmosphere.PendingProfileIndex),
        tostring(Atmosphere.LastApplySource), Atmosphere.StormIntensity,
        settings and string.format("start %.1f end %.1f density %.2f color %s",
            settings.start, settings.finish, settings.maxDensity, table.concat(settings.color or {}, ","))
            or "inactive"))
    if profile then print("[ZombieSim] Atmosphere profile: " .. tostring(profile.id or profile.name or Atmosphere.ActiveProfileIndex)) end
end)