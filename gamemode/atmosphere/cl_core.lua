// Initialize every subsystem before exposing engine callbacks; retain the public facade and lifecycle.
return function(Atmosphere)
    if Atmosphere.ModulesReady then
        Atmosphere.Modules.Weather.Shutdown()
    end
    Atmosphere.ModulesReady = false
    local Modules = {
        Core = {},
        Environment = {},
        Weather = {},
        Puddles = {},
        Snow = {},
        Footsteps = {},
        ScreenEffects = {},
        Fog = {},
        Diagnostics = {},
    }
    Atmosphere.Modules = Modules
    local Core = Modules.Core
    local Environment = Modules.Environment
    local Weather = Modules.Weather
    local Puddles = Modules.Puddles
    local Snow = Modules.Snow
    local Footsteps = Modules.Footsteps

    Atmosphere.ActiveProfileIndex = Atmosphere.ActiveProfileIndex or nil
    Atmosphere.StormIntensity = Atmosphere.StormIntensity or 0
    Atmosphere.Weather = Atmosphere.Weather or "clear"
    Atmosphere.PendingProfileIndex = Atmosphere.PendingProfileIndex or nil
    Atmosphere.PendingPlayerProfileSource = Atmosphere.PendingPlayerProfileSource or nil
    Atmosphere.LastApplySource = Atmosphere.LastApplySource or "none"
    Atmosphere.ProfileApplications = Atmosphere.ProfileApplications or {}
    Atmosphere.LastProfileReceive = Atmosphere.LastProfileReceive or nil
    Atmosphere.HookResults = Atmosphere.HookResults or {}
    Atmosphere.BoundaryMistActive = Atmosphere.BoundaryMistActive or false
    Atmosphere.SessionStart = Atmosphere.SessionStart or SysTime()
    // Until the server's weather sync arrives, the last known state (saved by this client) lets a new map start
    // building the settled cover behind the loading screen straight away.
    if Atmosphere.SnowCoverAmount == nil then
        Atmosphere.SnowCoverAmount = math.Clamp(tonumber(cookie.GetString("zombiesim_snow_cover", "0")) or 0, 0, 1)
        Atmosphere.CachedWeather = cookie.GetString("zombiesim_weather", "clear")
    end

    function Core.GetNumber(value, fallback)
        value = tonumber(value)
        return value and value or fallback
    end

    function Core.GetExpectedCell(player)
        if not ZM_World:IsLoaded() or not IsValid(player) then
            return nil
        end

        local cellX = player.CellX
        local cellY = player.CellY
        if cellX == nil then cellX = player:GetNWInt("CellX", 0) end
        if cellY == nil then cellY = player:GetNWInt("CellY", 0) end
        local gridX, gridY = ZM_World:GetGridCoordinates(cellX, cellY)
        local cell = gridX and ZM_World:GetCell(gridX, gridY) or nil
        if not cell then
            return nil
        end

        return {
            cellX = cellX,
            cellY = cellY,
            gridX = gridX,
            gridY = gridY,
            profileIndex = cell.atmosphereProfile
        }
    end

    function Core.GetProfileId(profileIndex)
        local profile = ZM_World:GetAtmosphereProfileByIndex(profileIndex)
        return profile and (profile.id or profile.name) or nil
    end

    function Core.RecordHookResult(name, returned, applied, settings, scale, reason, correction)
        local result = Atmosphere.HookResults[name] or {}
        result.time = RealTime()
        result.returned = returned
        result.applied = applied
        result.profileIndex = Atmosphere.ActiveProfileIndex
        result.profileId = Core.GetProfileId(Atmosphere.ActiveProfileIndex)
        result.worldDataLoaded = ZM_World:IsLoaded()
        result.scale = scale
        result.reason = reason
        result.colorCorrection = correction
        if settings then
            local fog = result.fog or {}
            fog.start = settings.start
            fog.finish = settings.finish
            fog.maxDensity = settings.maxDensity
            fog.color = settings.color
            result.fog = fog
        else
            result.fog = nil
        end
        Atmosphere.HookResults[name] = result
    end

    local function recordProfileApplication(profileIndex, source, applied)
        local expected = Core.GetExpectedCell(LocalPlayer())
        local history = Atmosphere.ProfileApplications
        history[#history + 1] = {
            time = RealTime(),
            source = tostring(source or "unknown"),
            profileIndex = profileIndex,
            profileId = Core.GetProfileId(profileIndex),
            applied = applied,
            worldDataLoaded = ZM_World:IsLoaded(),
            expectedProfileIndex = expected and expected.profileIndex or nil,
            cellX = expected and expected.cellX or nil,
            cellY = expected and expected.cellY or nil
        }
        if #history > 16 then
            table.remove(history, 1)
        end
    end

    function Atmosphere:GetActiveProfile()
        return ZM_World:GetAtmosphereProfileByIndex(self.ActiveProfileIndex)
    end

    function Atmosphere:SetMapCaptureHidden(hidden)
        self.MapCaptureParticlesHidden = hidden
        if hidden then self.MapCaptureHideCount = (self.MapCaptureHideCount or 0) + 1 end
        Weather.SetParticlesHidden(hidden)
    end

    function Atmosphere:GetMapCaptureState()
        local amount = self.SnowCoverAmount or 0
        local rebuilding = amount > 0.002 and
            (next(Snow.Cover.dirtyChunks or {}) ~= nil or next(Snow.Cover.urgentChunks or {}) ~= nil)
        return string.format("%s/%d/%s/%s", self.Weather or "clear",
            amount <= 0.002 and 0 or math.max(1, math.Round(amount * 12)),
            Snow.Cover.status or "not built", rebuilding and "rebuilding" or "settled")
    end

    function Atmosphere:SetWeather(weather)
        if type(weather) ~= "string" then
            ErrorNoHalt("[ZombieSim] Atmosphere received an invalid weather state.\n")
            return false
        end
        weather = string.lower(string.Trim(weather))
        if weather ~= "clear" and weather ~= "rain" and weather ~= "snow" then
            ErrorNoHalt("[ZombieSim] Atmosphere received an unknown weather state: " .. weather .. "\n")
            return false
        end
        if self.Weather ~= weather then
            self:StopWeatherEffects()
        end
        if self.Weather == "rain" and weather ~= "rain" then
            self.PuddlesDryAt = CurTime() + 3
        elseif weather == "rain" then
            self.PuddlesDryAt = nil
        end
        self.Weather = weather
        self.StormIntensity = weather == "rain" and 0.55 or (weather == "snow" and 0.35 or 0)
        self.WeatherChangedAt = CurTime()
        return true
    end

    function Atmosphere:ApplyProfile(profileIndex, source)
        profileIndex = tonumber(profileIndex)
        if not profileIndex then
            ErrorNoHalt("[ZombieSim] Atmosphere received a non-numeric profile index.\n")
            recordProfileApplication(nil, source, false)
            return false
        end
        local profile = ZM_World:GetAtmosphereProfileByIndex(profileIndex)
        if not profile then
            if not ZM_World:IsLoaded() then
                self.PendingProfileIndex = profileIndex
                self.LastApplySource = tostring(source or "unknown") .. " (waiting for world data)"
            else
                self.PendingProfileIndex = nil
                ErrorNoHalt("[ZombieSim] Unknown atmosphere profile index: " .. tostring(profileIndex) .. "\n")
                if self.LoadingStepId then
                    ZM_Loading:Finish(self.LoadingStepId, "fail", "Unknown atmosphere profile " .. profileIndex)
                    self.LoadingStepId = nil
                end
            end
            recordProfileApplication(profileIndex, source, false)
            return false
        end

        self.ActiveProfileIndex = math.floor(profileIndex)
        self.PendingProfileIndex = nil
        self.PendingPlayerProfileSource = nil
        self.LastApplySource = source or "unknown"
        recordProfileApplication(self.ActiveProfileIndex, source, true)
        if self.LoadingStepId then
            ZM_Loading:Finish(self.LoadingStepId, "ok", "Applied atmosphere profile " .. self.ActiveProfileIndex)
            self.LoadingStepId = nil
        end
        return true
    end

    function Atmosphere:ApplyPlayerProfile(source)
        local player = LocalPlayer()
        if not IsValid(player) then
            recordProfileApplication(nil, source, false)
            return false
        end

        if not ZM_World:IsLoaded() then
            self.PendingPlayerProfileSource = source or "player data"
            recordProfileApplication(nil, source, false)
            return false
        end
        self.PendingPlayerProfileSource = nil
        local expected = Core.GetExpectedCell(player)
        if not expected then
            recordProfileApplication(nil, source, false)
            return false
        end
        return self:ApplyProfile(expected.profileIndex, source or "player data")
    end

    // Weather updates set a bounded intensity that blends into the active cell fog profile.
    function Atmosphere:SetStormIntensity(intensity)
        self.StormIntensity = math.Clamp(Core.GetNumber(intensity, 0), 0, 1)
    end

    // Quality settings come from cl_quality.lua; the fallbacks keep the original high-quality behaviour.
    function Atmosphere.GetQualityNumber(key, fallback, minimum, maximum)
        local convar = ZM_Quality and ZM_Quality.ConVars and ZM_Quality.ConVars[key]
        if not convar then return fallback end
        return math.Clamp(convar:GetFloat(), minimum, maximum)
    end

    include( "atmosphere/cl_environment.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_weather.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_puddles.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_snow.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_footsteps.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_screen_effects.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_fog.lua" )(Atmosphere, Modules)
    include( "atmosphere/cl_diagnostics.lua" )(Atmosphere, Modules)

    function Core.RegisterHooks()
        net.Receive("ZM.Atmosphere.Weather", function()
            local code = net.ReadUInt(2)
            local weather = ({ [0] = "clear", [1] = "rain", [2] = "snow" })[code]
            if not weather then
                ErrorNoHalt("[ZombieSim] Received an unknown weather code: " .. tostring(code) .. "\n")
                return
            end
            Atmosphere:SetWeather(weather)
            Atmosphere.WeatherSynced = true
            local snowAmount = net.ReadFloat()
            if snowAmount == snowAmount then
                Atmosphere.SnowCoverAmount = math.Clamp(snowAmount, 0, 1)
            end
        end)

        hook.Add("Think", "ZM.Atmosphere.WeatherEffects", Weather.UpdateWeatherEffects)
        hook.Add("Think", "ZM.Atmosphere.WetPuddles", Puddles.UpdateWetPuddles)
        hook.Add("Think", "ZM.Atmosphere.BoundaryMist", Weather.UpdateBoundaryMist)
        hook.Add("Think", "ZM.Atmosphere.WeatherFootsteps", Footsteps.UpdateWeatherFootsteps)
        hook.Add("Think", "ZM.Atmosphere.Winter", Weather.UpdateWinter)
        hook.Add("Think", "ZM.Atmosphere.SnowCover", Snow.UpdateSnowCover)
        hook.Remove("PostDrawOpaqueRenderables", "ZM.Atmosphere.SnowCover")
        hook.Add("PreCleanupMap", "ZM.Atmosphere.WeatherCleanup", function()
            Atmosphere:StopWeatherEffects()
            Atmosphere:StopBoundaryEffects()
            Puddles.Reset()
            Environment.Reset()
            Footsteps.Reset()
            Snow.ClearSnowTrail()
            Weather.Reset()
        end)
        hook.Add("ShutDown", "ZM.Atmosphere.WeatherCleanup", Weather.Shutdown)

        net.Receive("ZM.SetAtmosphereProfile", function()
            local profileIndex = net.ReadUInt(8)
            local expected = Core.GetExpectedCell(LocalPlayer())
            Atmosphere.LastProfileReceive = {
                time = RealTime(),
                profileIndex = profileIndex,
                worldDataLoaded = ZM_World:IsLoaded(),
                expectedProfileIndex = expected and expected.profileIndex or nil,
                cellX = expected and expected.cellX or nil,
                cellY = expected and expected.cellY or nil
            }
            Atmosphere:ApplyProfile(profileIndex, "server net message")
            if Atmosphere.ActiveProfileIndex == profileIndex and not Atmosphere.PendingProfileIndex then
                ZM_Loading:Step("Applied atmosphere profile " .. profileIndex)
            elseif Atmosphere.PendingProfileIndex then
                Atmosphere.LoadingStepId = ZM_Loading:Begin("Applying atmosphere (waiting for world data)")
            else
                ZM_Loading:Step("Unknown atmosphere profile " .. profileIndex, "fail")
            end
        end)

        hook.Add("InitPostEntity", "ZM.Atmosphere.ApplyLoadedCell", function()
            timer.Simple(0, function()
                Atmosphere:ApplyPlayerProfile("InitPostEntity")
            end)
        end)

        hook.Add("Think", "ZM.Atmosphere.WaitForWorldData", function()
            if not ZM_World:IsLoaded() then return end
            if Atmosphere.PendingProfileIndex then
                Atmosphere:ApplyProfile(Atmosphere.PendingProfileIndex, "world data ready")
            elseif Atmosphere.PendingPlayerProfileSource and IsValid(LocalPlayer()) then
                Atmosphere:ApplyPlayerProfile(Atmosphere.PendingPlayerProfileSource .. " (world data ready)")
            end
        end)
    end

    Modules.Core.RegisterHooks()
    Modules.Environment.RegisterHooks()
    Modules.Weather.RegisterHooks()
    Modules.Puddles.RegisterHooks()
    Modules.Snow.RegisterHooks()
    Modules.Footsteps.RegisterHooks()
    Modules.ScreenEffects.RegisterHooks()
    Modules.Fog.RegisterHooks()
    Modules.Diagnostics.RegisterHooks()
    Atmosphere.ModulesReady = true
end
