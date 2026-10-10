// Cached world/skybox fog and launcher sky-inspection integration.
return function(Atmosphere, Modules)
    local Core = Modules.Core
    local Snow = Modules.Snow
    local Fog = Modules.Fog
    function Fog.GetColorComponent(color, index)
        return math.Clamp(Core.GetNumber(color and color[index], 0), 0, 255)
    end

    // Fog settings are read by several hooks per frame, so they are computed once per frame into reused tables.
    local fogSettingsCache = { color = {} }
    local fogWinterColor = {}
    local fogSettingsFrame = -1
    local fogSettingsResult

    // Scoped to the secondary capture view; never changes fog convars, weather or profile caches.
    function Atmosphere:BeginWorldCaptureFog(variant)
        local previous = self.WorldCaptureFogVariant
        self.WorldCaptureFogVariant = variant
        return {previous = previous, cullDistance = Snow.FogCullDistance}
    end

    function Atmosphere:EndWorldCaptureFog(token)
        self.WorldCaptureFogVariant = token.previous
        Snow.FogCullDistance = token.cullDistance
    end

    function Atmosphere:GetFogSettings()
        local frame = FrameNumber()
        if frame == fogSettingsFrame then
            return fogSettingsResult
        end
        fogSettingsFrame = frame
        local profile = self:GetActiveProfile()
        local fog = profile and profile.fog
        if type(fog) ~= "table" then
            fogSettingsResult = nil
            return nil
        end

        local stormMultiplier = math.Clamp(Core.GetNumber(fog.stormMultiplier, 1), 0.1, 1)
        local visibilityMultiplier = 1 + (stormMultiplier - 1) * self.StormIntensity
        local maxDensity = math.Clamp(Core.GetNumber(fog.maxDensity, 1), 0, 1)
        local density = math.Clamp(maxDensity + (1 - maxDensity) * self.StormIntensity, 0, 1)
        local color = fog.color
        // Snow pulls the fog toward a pale blue-white and closes it in slightly; eased by WinterBlend.
        local winter = self.WinterBlend or 0
        if winter > 0.001 then
            visibilityMultiplier = visibilityMultiplier * (1 - 0.22 * winter)
            density = math.Clamp(density + (1 - density) * 0.25 * winter, 0, 1)
            fogWinterColor[1] = Lerp(winter * 0.75, Fog.GetColorComponent(color, 1), 212)
            fogWinterColor[2] = Lerp(winter * 0.75, Fog.GetColorComponent(color, 2), 222)
            fogWinterColor[3] = Lerp(winter * 0.75, Fog.GetColorComponent(color, 3), 234)
            color = fogWinterColor
        end
        // Dark-lit cells tint the profile fog by the light measured from the cell's baked lighting, so fogged city and
        // sky scenery darken together instead of washing toward a pale daytime colour.
        local sceneryLight = ZM_Skybox and ZM_Skybox.SceneryLight
        if sceneryLight and (sceneryLight[1] < 0.999 or sceneryLight[2] < 0.999 or sceneryLight[3] < 0.999) then
            local litColor = self.FogLitColor or {}
            self.FogLitColor = litColor
            litColor[1] = Fog.GetColorComponent(color, 1) * sceneryLight[1]
            litColor[2] = Fog.GetColorComponent(color, 2) * sceneryLight[2]
            litColor[3] = Fog.GetColorComponent(color, 3) * sceneryLight[3]
            color = litColor
        end
        local settings = fogSettingsCache
        settings.color = color
        settings.start = math.max(0, Core.GetNumber(fog.start, 0) * visibilityMultiplier)
        settings.finish = math.max(1, Core.GetNumber(fog["end"], 1) * visibilityMultiplier)
        settings.maxDensity = density
        fogSettingsResult = settings
        return settings
    end

    local function applyFog(settings, scale)
        scale = scale or 1
        render.FogMode(MATERIAL_FOG_LINEAR)
        render.FogStart(settings.start * scale)
        render.FogEnd(math.max(settings.finish * scale, settings.start * scale + 1))
        render.FogMaxDensity(settings.maxDensity)
        render.FogColor(Fog.GetColorComponent(settings.color, 1), Fog.GetColorComponent(settings.color, 2), Fog.GetColorComponent(settings.color, 3))
        return true
    end

    function Modules.Fog.RegisterHooks()
        hook.Add("SetupWorldFog", "ZM.Atmosphere.WorldFog", function()
            if Atmosphere.WorldCaptureFogVariant == "clear" then
                render.FogMode(MATERIAL_FOG_NONE)
                Snow.FogCullDistance = nil
                return true
            end
            if ZM_LauncherMenu and ZM_LauncherMenu.Active then
                local preview = ZM_SkyInspection and ZM_SkyInspection.GetLauncherFogSettings and
                    ZM_SkyInspection:GetLauncherFogSettings()
                if preview then
                    local applied = applyFog(preview)
                    Core.RecordHookResult("SetupWorldFog", applied, applied, preview, 1, "launcher sky preview")
                    return applied
                end
                Core.RecordHookResult("SetupWorldFog", nil, false, nil, nil, "launcher menu active")
                return
            end
            local settings = Atmosphere:GetFogSettings()
            local applied = settings and applyFog(settings) or false
            // Only fully opaque fog hides geometry beyond its end, so only then may the snow draw cull by distance.
            Snow.FogCullDistance = (applied and settings.maxDensity >= 0.999) and settings.finish or nil
            local reason
            if not settings then reason = "no active profile" end
            Core.RecordHookResult("SetupWorldFog", applied, applied, settings, 1, reason)
            return applied
        end)

        hook.Add("SetupSkyboxFog", "ZM.Atmosphere.SkyboxFog", function(scale)
            if Atmosphere.WorldCaptureFogVariant == "clear" then
                render.FogMode(MATERIAL_FOG_NONE)
                return true
            end
            if ZM_LauncherMenu and ZM_LauncherMenu.Active then
                local preview = ZM_SkyInspection and ZM_SkyInspection.GetLauncherFogSettings and
                    ZM_SkyInspection:GetLauncherFogSettings()
                if preview then
                    local applied = applyFog(preview, scale)
                    Core.RecordHookResult("SetupSkyboxFog", applied, applied, preview, scale, "launcher sky preview")
                    return applied
                end
                Core.RecordHookResult("SetupSkyboxFog", nil, false, nil, scale, "launcher menu active")
                return
            end
            local settings = Atmosphere:GetFogSettings()
            // The runtime 3D skybox grades this fog to opaque at its horizon wall.
            if settings and ZM_Skybox and ZM_Skybox.GetSkyboxFog then settings = ZM_Skybox:GetSkyboxFog(settings) end
            local applied = settings and applyFog(settings, scale) or false
            local reason
            if not settings then reason = "no active profile" end
            Core.RecordHookResult("SetupSkyboxFog", applied, applied, settings, scale, reason)
            return applied
        end)
    end
end
