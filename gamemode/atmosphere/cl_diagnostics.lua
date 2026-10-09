// Atmosphere status reporting with the existing snapshot and console contracts.
return function(Atmosphere, Modules)
    local Core = Modules.Core
    local Environment = Modules.Environment
    local Weather = Modules.Weather
    local Puddles = Modules.Puddles
    local Snow = Modules.Snow
    local Footsteps = Modules.Footsteps
    function Atmosphere:GetDiagnosticSnapshot()
        local player = LocalPlayer()
        local nearbyPuddleCount = 0
        if IsValid(player) then
            local playerPosition = player:GetPos()
            local nearbyPuddleRadiusSquared = 560 * 560
            for _, puddle in ipairs(Puddles.Items) do
                if not puddle.removed and puddle.position:DistToSqr(playerPosition) <= nearbyPuddleRadiusSquared then
                    nearbyPuddleCount = nearbyPuddleCount + 1
                end
            end
        end
        local expected = Core.GetExpectedCell(player)
        local profile = self:GetActiveProfile()
        local cells = ZM_World:IsLoaded() and ZM_World:GetCellsForMap(game.GetMap()) or nil
        local insideDen = IsValid(player) and ZM_SafeZones:IsPlayerInside(player) or false
        return {
            map = game.GetMap(),
            playerValid = IsValid(player),
            worldDataLoaded = ZM_World:IsLoaded(),
            outdoorCityCellCount = type(cells) == "table" and #cells or 0,
            insideDen = insideDen,
            precipitationEligible = type(cells) == "table" and #cells > 0 and not insideDen,
            weatherDiagnostics = table.Copy(Weather.Diagnostics),
            weatherThinkHookRegistered = type((hook.GetTable().Think or {})["ZM.Atmosphere.WeatherEffects"]) == "function",
            wetPuddleThinkHookRegistered = type((hook.GetTable().Think or {})["ZM.Atmosphere.WetPuddles"]) == "function",
            wetSurfaceRenderHookRegistered = type((hook.GetTable().PostDrawTranslucentRenderables or {})["ZM.Atmosphere.WetSurfaceEffects"]) == "function",
            boundaryThinkHookRegistered = type((hook.GetTable().Think or {})["ZM.Atmosphere.BoundaryMist"]) == "function",
            wetPuddleCount = #Puddles.Items,
            nearbyPuddleCount = nearbyPuddleCount,
            puddleSitesMap = Environment.SurfaceMap,
            puddleSiteCount = Environment.SurfaceMap == game.GetMap() and #Environment.SurfaceSites or 0,
            puddleSiteCursor = Puddles.PuddleSiteCursor,
            puddleSiteStatus = self.PuddleSiteStatus or "not initialized",
            puddleSiteAttempts = self.PuddleSiteAttempts or 0,
            puddleBoundsSource = self.PuddleBoundsSource,
            puddleUnusableSiteCount = (function()
                local count = 0
                for _, site in ipairs(Environment.SurfaceSites) do
                    if site.unusable then count = count + 1 end
                end
                return count
            end)(),
            puddleWorldBoundsAvailable = Environment.WorldMinimum ~= nil and Environment.WorldMaximum ~= nil,
            puddleWorldBounds = Environment.WorldMinimum and Environment.WorldMaximum and {
                minX = Environment.WorldMinimum.x,
                minY = Environment.WorldMinimum.y,
                minZ = Environment.WorldMinimum.z,
                maxX = Environment.WorldMaximum.x,
                maxY = Environment.WorldMaximum.y,
                maxZ = Environment.WorldMaximum.z
            } or nil,
            puddleMapBound = true,
            puddleAmount = Puddles.GetPuddleAmount(),
            activePuddleSites = Puddles.GetActivePuddleSiteCount(),
            maxPuddleClusters = Puddles.GetPuddleClusterLimit(),
            maxVisiblePuddleClusters = Puddles.GetVisiblePuddleClusterLimit(),
            largestPuddleSpread = (function()
                local largest = 0
                for _, puddle in ipairs(Puddles.Items) do
                    largest = math.max(largest, puddle.spread or 1)
                end
                return largest
            end)(),
            renderedPuddleClusters = self.PuddleRenderClusters or 0,
            renderedPuddleLobes = self.PuddleRenderLobes or 0,
            splashRingCount = #Footsteps.Splashes,
            rainSoundActive = self.RainSoundPatch ~= nil,
            rainSoundMounted = file.Exists("sound/" .. Weather.RainSoundPath, "GAME"),
            rainDensity = math.Clamp(Weather.RainDensityConVar:GetFloat(), 0.5, 2),
            puddleDropRings = self.PuddleDropRings or 0,
            puddleDropCrowns = self.PuddleDropCrowns or 0,
            puddleImpactQuads = self.PuddleImpactQuads or 0,
            puddleImpactMaxIndices = self.PuddleImpactMaxIndices or 0,
            splashRingMaterialAvailable = not Puddles.SplashRingMaterial:IsError(),
            splashRingMaterialShader = Puddles.SplashRingMaterial:GetShader(),
            footstepSplashMaterialAvailable = not self.FootstepSplashMaterial:IsError(),
            footstepSplashMaterialShader = self.FootstepSplashMaterial:GetShader(),
            puddleOpacity = math.Clamp(Puddles.PuddleOpacityConVar:GetFloat(), 0.05, 0.45),
            puddleTranslucencyMaterialAvailable = Puddles.PuddleMaterial ~= nil,
            puddleMaterialShader = Puddles.PuddleMaterial and Puddles.PuddleMaterial:GetShader() or nil,
            puddleMaterialError = Puddles.PuddleMaterial == nil,
            puddleReflection = Puddles.PuddleReflectionMaterial ~= nil,
            winterBlend = self.WinterBlend or 0,
            frostAmount = self.FrostAmount or 0,
            snowCoverAmount = self.SnowCoverAmount or 0,
            snowCoverStatus = Snow.Cover.status,
            snowCoverStage = Snow.Cover.stage,
            snowCoverPreload = Snow.Cover.preloadStep ~= nil and "holding" or (Snow.Cover.preloadDone and "done" or "waiting"),
            snowCoverPreloadResult = Snow.Cover.preloadResult,
            snowCoverPreloadSeconds = Snow.Cover.preloadSeconds,
            weatherSynced = self.WeatherSynced == true,
            snowCoverMap = Snow.Cover.map,
            snowCoverSpacing = Snow.Cover.spacing,
            snowCoverPoints = Snow.Cover.validPoints or 0,
            snowCoverTriangles = Snow.Cover.triangleCount or 0,
            snowCoverMeshes = Snow.Cover.meshCount or 0,
            snowCoverTextured = Snow.SnowFloorTexture ~= nil,
            snowCoverTexture = (function()
                local texture = Snow.SnowCoverMaterial:GetTexture("$basetexture")
                return texture and texture:GetName() or "none"
            end)(),
            snowCoverTextureReapplied = Snow.Cover.textureReapplied or 0,
            snowTrailPoints = Snow.Cover.troddenCount or 0,
            snowCoverDraws = Snow.Cover.drawCount or 0,
            snowCoverChunks = Snow.Cover.chunkList and #Snow.Cover.chunkList or 0,
            snowCoverDrawnChunks = Snow.Cover.lastDrawnChunks or 0,
            snowCoverCulledChunks = Snow.Cover.lastCulledChunks or 0,
            snowCoverRebuilds = Snow.Cover.rebuildCount or 0,
            snowCoverRebuildMsAverage = (Snow.Cover.rebuildCount or 0) > 0
                and (Snow.Cover.rebuildSeconds or 0) * 1000 / Snow.Cover.rebuildCount or 0,
            snowCoverFogCullDistance = Snow.FogCullDistance,
            windSoundActive = self.WindSoundPatch ~= nil,
            windSoundMounted = file.Exists("sound/" .. Weather.WindSoundPath, "GAME"),
            snowStepSoundMounted = file.Exists("sound/" .. Footsteps.SnowStepSoundPaths[1], "GAME"),
            puddleSloshSoundMounted = file.Exists("sound/" .. Footsteps.PuddleSloshSoundPaths[1], "GAME"),
            stepCount = self.StepCount or 0,
            lastStep = self.LastStep and table.Copy(self.LastStep) or nil,
            breathPuffs = self.BreathPuffs or 0,
            puddleTextureWidth = Puddles.PuddleBaseTexture and Puddles.PuddleBaseTexture:Width() or nil,
            boundaryMistMaterialError = Weather.BoundaryMistMaterial:IsError(),
            boundaryMistTextureWidth = Weather.BoundaryMistTexture and Weather.BoundaryMistTexture:Width() or nil,
            puddleMeshLobeLimit = Puddles.GetVisiblePuddleLobeLimit(),
            puddleMeshSegments = Puddles.PuddleMeshSegments,
            activeProfileIndex = self.ActiveProfileIndex,
            activeProfileId = profile and (profile.id or profile.name) or nil,
            expectedProfileIndex = expected and expected.profileIndex or nil,
            expectedProfileId = Core.GetProfileId(expected and expected.profileIndex),
            cellX = expected and expected.cellX or nil,
            cellY = expected and expected.cellY or nil,
            safeZoneId = IsValid(player) and player:GetNWString("CurrentSafeZoneId", "") or "",
            pendingProfileIndex = self.PendingProfileIndex,
            pendingPlayerProfileSource = self.PendingPlayerProfileSource,
            lastApplySource = self.LastApplySource,
            stormIntensity = self.StormIntensity,
            fog = self:GetFogSettings(),
            lastProfileReceive = self.LastProfileReceive,
            weather = self.Weather,
            sheltered = Environment.IsSheltered,
            boundaryMistActive = self.BoundaryMistActive,
            profileApplications = table.Copy(self.ProfileApplications),
            skybox = ZM_Skybox and ZM_Skybox:GetDiagnosticSnapshot() or nil,
            mapCapture = ZM_WorldMap and ZM_WorldMap:GetCaptureDiagnosticSnapshot() or nil,
            mapCaptureParticlesHidden = self.MapCaptureParticlesHidden == true,
            mapCaptureHideCount = self.MapCaptureHideCount or 0,
            retiredWeatherEmitters = #self.RetiredWeatherEmitters,
            shoulderCamera = ZM_IsShoulderCamera(),
            radiationFeedback = ZM_RadiationFeedback:GetDiagnosticSnapshot(),
            gore = ZM_GoreClient:GetDiagnosticSnapshot(),
            music = ZM_Music:GetDiagnosticSnapshot(),
            hookResults = table.Copy(self.HookResults)
        }
    end

    function Modules.Diagnostics.RegisterHooks()
        net.Receive("ZM.AtmosphereStatus.Request", function()
            local requestId = net.ReadUInt(16)
            local encoded = util.TableToJSON(Atmosphere:GetDiagnosticSnapshot(), false) or "{}"
            net.Start("ZM.AtmosphereStatus.Result")
                net.WriteUInt(requestId, 16)
                net.WriteString(encoded)
            net.SendToServer()
        end)

        concommand.Add("zombiesim_atmosphere_status", function()
            local player = LocalPlayer()
            local profile = Atmosphere:GetActiveProfile()
            local settings = Atmosphere:GetFogSettings()
            local worldReady = ZM_World:IsLoaded()
            local expected = Core.GetExpectedCell(player)
            print(string.format("[ZombieSim] Atmosphere: map=%s world=%s active=%s activeId=%s expected=%s expectedId=%s cell=%s,%s pending=%s pendingPlayer=%s source=%s storm=%.2f fog=%s",
                game.GetMap(),
                tostring(worldReady), tostring(Atmosphere.ActiveProfileIndex),
                tostring(profile and (profile.id or profile.name) or "none"),
                tostring(expected and expected.profileIndex),
                tostring(Core.GetProfileId(expected and expected.profileIndex)),
                tostring(expected and expected.cellX), tostring(expected and expected.cellY),
                tostring(Atmosphere.PendingProfileIndex), tostring(Atmosphere.PendingPlayerProfileSource),
                tostring(Atmosphere.LastApplySource), Atmosphere.StormIntensity,
                settings and string.format("start %.1f end %.1f density %.2f color %s",
                    settings.start, settings.finish, settings.maxDensity, table.concat(settings.color or {}, ","))
                    or "inactive"))
            local cells = ZM_World:IsLoaded() and ZM_World:GetCellsForMap(game.GetMap()) or nil
            local insideDen = IsValid(player) and ZM_SafeZones:IsPlayerInside(player) or false
            print("[ZombieSim] Atmosphere weather: " .. tostring(Atmosphere.Weather)
                .. " sheltered=" .. tostring(Environment.IsSheltered)
                .. " boundaryMist=" .. tostring(Atmosphere.BoundaryMistActive)
                .. " precipitationEligible=" .. tostring(type(cells) == "table" and #cells > 0 and not insideDen)
                .. " grain=" .. tostring(GetConVar("zombiesim_atmosphere_grain"):GetBool()))
            local received = Atmosphere.LastProfileReceive
            if received then
                print(string.format("[ZombieSim] Atmosphere receive: profile=%s id=%s world=%s expected=%s cell=%s,%s time=%.2f",
                    tostring(received.profileIndex), tostring(Core.GetProfileId(received.profileIndex)),
                    tostring(received.worldDataLoaded), tostring(received.expectedProfileIndex),
                    tostring(received.cellX), tostring(received.cellY), received.time))
            else
                print("[ZombieSim] Atmosphere receive: no server profile received in this client session")
            end

            for _, application in ipairs(Atmosphere.ProfileApplications) do
                print(string.format("[ZombieSim] Atmosphere apply: time=%.2f source=%s profile=%s id=%s applied=%s world=%s expected=%s cell=%s,%s",
                    application.time, application.source, tostring(application.profileIndex),
                    tostring(application.profileId), tostring(application.applied),
                    tostring(application.worldDataLoaded), tostring(application.expectedProfileIndex),
                    tostring(application.cellX), tostring(application.cellY)))
            end

            for _, hookName in ipairs({ "SetupWorldFog", "SetupSkyboxFog", "RenderScreenspaceEffects" }) do
                local result = Atmosphere.HookResults[hookName]
                if result then
                    local fog = result.fog
                    local correction = result.colorCorrection
                    local correctionSummary = correction and string.format("brightness %.2f contrast %.2f colour %.2f add %.2f,%.2f,%.2f multiply %.2f,%.2f,%.2f",
                        correction["$pp_colour_brightness"], correction["$pp_colour_contrast"], correction["$pp_colour_colour"],
                        correction["$pp_colour_addr"], correction["$pp_colour_addg"], correction["$pp_colour_addb"],
                        correction["$pp_colour_mulr"], correction["$pp_colour_mulg"], correction["$pp_colour_mulb"])
                        or "inactive"
                    print(string.format("[ZombieSim] Atmosphere hook: %s applied=%s returned=%s reason=%s profile=%s id=%s world=%s scale=%s fog=%s correction=%s",
                        hookName, tostring(result.applied), tostring(result.returned), tostring(result.reason),
                        tostring(result.profileIndex), tostring(result.profileId), tostring(result.worldDataLoaded),
                        tostring(result.scale), fog and string.format("start %.1f end %.1f density %.2f color %s",
                            fog.start, fog.finish, fog.maxDensity, table.concat(fog.color or {}, ","))
                            or "inactive", correctionSummary))
                else
                    print("[ZombieSim] Atmosphere hook: " .. hookName .. " has not run in this client session")
                end
            end
        end)
    end
end
