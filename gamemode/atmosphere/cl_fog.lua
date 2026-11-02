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
    local fogRadiationColor = {}
    local fogSkyTarget = {}
    local fogSettingsFrame = -1
    local fogSettingsResult
    // Radiated cells: the same burnt orange as the sky near the ground, darker in the sky itself.
    local radiationFogColor = { 170, 92, 40 }
    local radiationSkyColor = { 170, 92, 40 }
    local radiationColorWeight = 0.7
    local radiationSkyWeight = 0.8
    local radiationSkyDarken = 0.35
    local radiationStartScale = 0.25
    local radiationFinishScale = 0.35
    local radiationDensity = 0.7
    // Layered fog eases toward its target with this time constant (seconds) so weather and radiation never pop.
    local fogEaseSeconds = 3
    local eased = { color = {}, skyColor = {} }
    local easedKey
    local easedTime
    // Layered keeps Source fog extremely gentle; the skybox haze layers supply depth and scale.
    local fogStyleConVar = CreateClientConVar("zombiesim_fog_style", "layered", true, false,
        "Fog style: layered (gentle Source fog plus custom haze layers) or legacy (original dense Source fog).")
    local layeredDensityScale = 0.45
    local layeredStartScale = 1.4
    local layeredFinishScale = 1.6

    function Atmosphere:GetFogStyle()
        return fogStyleConVar:GetString() == "legacy" and "legacy" or "layered"
    end

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
        local start = math.max(0, Core.GetNumber(fog.start, 0) * visibilityMultiplier)
        local finish = math.max(1, Core.GetNumber(fog["end"], 1) * visibilityMultiplier)
        local layered = self:GetFogStyle() == "layered"
        if layered then
            start = start * layeredStartScale
            finish = finish * layeredFinishScale
            density = density * layeredDensityScale
            // Radiated cells close the fog in, thicken it and pull it toward a sickly yellow-green; the sky goes a
            // darker burnt orange, as if something enormous has burned on the horizon.
            local player = LocalPlayer()
            local radiation = IsValid(player) and player.GetRadiationIntensity and player:GetRadiationIntensity() or 0
            radiation = math.Clamp(tonumber(radiation) or 0, 0, 1)
            start = start * (1 - radiationStartScale * radiation)
            finish = math.max(start + 1, finish * (1 - radiationFinishScale * radiation))
            density = Lerp(radiation, density, math.max(density, radiationDensity))
            local weight = radiation * radiationColorWeight
            local skyWeight = radiation * radiationSkyWeight
            local darken = 1 - radiationSkyDarken * radiation
            local target = fogRadiationColor
            for index = 1, 3 do
                local base = Fog.GetColorComponent(color, index)
                target[index] = Lerp(weight, base, radiationFogColor[index])
                fogSkyTarget[index] = Lerp(skyWeight, base, radiationSkyColor[index]) * darken
            end
            local now = RealTime()
            local key = tostring(self.ActiveProfileIndex)
            local blend = 1
            if key == easedKey and easedTime then
                blend = 1 - math.exp(-math.max(now - easedTime, 0) / fogEaseSeconds)
            end
            easedKey = key
            easedTime = now
            eased.start = Lerp(blend, eased.start or start, start)
            eased.finish = Lerp(blend, eased.finish or finish, finish)
            eased.maxDensity = Lerp(blend, eased.maxDensity or density, density)
            eased.radiation = Lerp(blend, eased.radiation or radiation, radiation)
            for index = 1, 3 do
                eased.color[index] = Lerp(blend, eased.color[index] or target[index], target[index])
                local sky = fogSkyTarget[index]
                eased.skyColor[index] = Lerp(blend, eased.skyColor[index] or sky, sky)
            end
            settings.radiation = eased.radiation
            settings.skyColor = eased.skyColor
            color = eased.color
            start = eased.start
            finish = math.max(eased.finish, start + 1)
            density = eased.maxDensity
            // Fog seen from straight above reads as a flat wash, so it fades out with the top-down camera.
            local topDown = ZM_GetTopDownCameraWeight and math.Clamp(tonumber(ZM_GetTopDownCameraWeight()) or 0, 0, 1) or 0
            settings.topDown = topDown
            density = density * (1 - topDown)
        else
            easedKey = nil
            settings.radiation = nil
            settings.skyColor = nil
            settings.topDown = nil
        end
        settings.style = layered and "layered" or "legacy"
        settings.color = color
        settings.start = start
        settings.finish = finish
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
            if ZM_PrefabEditorClient and ZM_PrefabEditorClient:IsActive() then
                local settings = ZM_PrefabEditorClient.PreviewFog
                Snow.FogCullDistance = nil
                if not settings then
                    render.FogMode(MATERIAL_FOG_NONE)
                    Core.RecordHookResult("SetupWorldFog", true, true, nil, 1, "prefab editor fog off")
                    return true
                end
                local applied = applyFog(settings)
                Core.RecordHookResult("SetupWorldFog", applied, applied, settings, 1, "prefab editor fog preview")
                return applied
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
            if ZM_PrefabEditorClient and ZM_PrefabEditorClient:IsActive() then
                local settings = ZM_PrefabEditorClient.PreviewFog
                if not settings then
                    render.FogMode(MATERIAL_FOG_NONE)
                    Core.RecordHookResult("SetupSkyboxFog", true, true, nil, scale, "prefab editor fog off")
                    return true
                end
                local applied = applyFog(settings, scale)
                Core.RecordHookResult("SetupSkyboxFog", applied, applied, settings, scale, "prefab editor fog preview")
                return applied
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
