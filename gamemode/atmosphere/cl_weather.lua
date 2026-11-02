// Precipitation, breath, ambience and boundary mist; owns active and draining particle emitters.
return function(Atmosphere, Modules)
    local Environment = Modules.Environment
    local Weather = Modules.Weather
    local Fog = Modules.Fog
    Weather.RainDensityConVar = CreateClientConVar("zombiesim_atmosphere_rain_density", "1.5", true, false,
        "Client rain particle density multiplier (0.5 to 2).")

    local weatherEmitter
    local boundaryEmitter
    local nextWeatherParticleAt = 0
    local nextBoundaryParticleAt = 0
    Weather.Diagnostics = {}
    Weather.RainSoundPath = "ambient/weather/rumble_rain.wav"
    Weather.WindSoundPath = "ambient/wind/wasteland_wind.wav"
    local windGustSoundPaths = {
        "ambient/wind/windgust.wav",
        "ambient/wind/windgust_strong.wav",
        "ambient/wind/wind_snippet1.wav",
        "ambient/wind/wind_snippet2.wav",
        "ambient/wind/wind_snippet3.wav"
    }
    local winterBlendSeconds = 3
    Atmosphere.WinterBlend = Atmosphere.WinterBlend or 0
    Atmosphere.FrostAmount = Atmosphere.FrostAmount or 0
    Atmosphere.BreathPuffs = Atmosphere.BreathPuffs or 0
    Weather.NextWindGustAt = 0
    Weather.BoundaryMistMaterial = Material("particle/particle_smokegrenade")
    Weather.BoundaryMistTexture = Weather.BoundaryMistMaterial:GetTexture("$basetexture")
    if Weather.BoundaryMistMaterial:IsError() then
        ErrorNoHalt("[ZombieSim] Mounted transition-mist material is unavailable.\n")
    end

    Atmosphere.RetiredWeatherEmitters = Atmosphere.RetiredWeatherEmitters or {}

    function Atmosphere:StopWeatherEffects()
        if weatherEmitter then
            // Retain draining emitters so map captures can still hide their remaining particles.
            self.RetiredWeatherEmitters[#self.RetiredWeatherEmitters + 1] = weatherEmitter
            weatherEmitter = nil
        end
        if self.RainSoundPatch then
            self.RainSoundPatch:FadeOut(0.6)
            self.RainSoundPatch = nil
        end
        self.RainSoundSheltered = nil
        if Weather.RunoffEdges then table.Empty(Weather.RunoffEdges) end
        if self.WindSoundPatch then
            self.WindSoundPatch:FadeOut(1.2)
            self.WindSoundPatch = nil
        end
        nextWeatherParticleAt = 0
    end

    function Atmosphere:StopBoundaryEffects()
        if boundaryEmitter then
            boundaryEmitter:Finish()
            boundaryEmitter = nil
        end
        nextBoundaryParticleAt = 0
        self.BoundaryMistActive = false
    end

    // Rain and snow spawn only in columns with open sky above, so precipitation falls up to walls and
    // roof edges and remains visible outside while the player is under cover.
    local columnTraceStart, columnTraceEnd = Vector(), Vector()
    local columnTrace = { start = columnTraceStart, endpos = columnTraceEnd, mask = MASK_SOLID_BRUSHONLY }
    local edgeTraceStart, edgeTraceEnd = Vector(), Vector()
    local edgeTrace = { start = edgeTraceStart, endpos = edgeTraceEnd, mask = MASK_SOLID_BRUSHONLY }
    local farRainMinimum, farRainMaximum, farRainHalfAngle = 720, 1700, math.rad(62)
    local runoffMaximumEdges, runoffProbeInterval, runoffRange = 10, 0.12, 520
    local runoffEdges = {}
    local nextRunoffProbeAt = 0
    Weather.RunoffEdges = runoffEdges

    local function traceColumn(x, y, z)
        columnTraceStart:SetUnpacked(x, y, z)
        columnTraceEnd:SetUnpacked(x, y, z + 4096)
        return util.TraceLine(columnTrace)
    end

    // Returns the spawn height for an open-sky column, or nil when the column is covered or inside solid.
    // Matches the shelter check: a trace that reaches nothing within range is open sky.
    local function openSkySpawnHeight(x, y, eyeZ, low, high)
        local trace = traceColumn(x, y, eyeZ)
        if trace.StartSolid or (trace.Hit and not trace.HitSky) then return nil end
        local preferred = eyeZ + math.Rand(low, high)
        local ceiling = trace.Hit and trace.HitPos and trace.HitPos.z - 8 or preferred
        return math.min(preferred, ceiling)
    end

    local function countDiagnostic(key)
        Weather.Diagnostics[key] = (Weather.Diagnostics[key] or 0) + 1
    end

    local function emitPrecipitationParticle(weather, eyePosition, eyeAngles, far)
        local emitter = Weather.GetEmitter(eyePosition)
        if not emitter then return end

        local x, y
        if far then
            local forward = eyeAngles:Forward()
            local heading = math.atan2(forward.y, forward.x) + math.Rand(-farRainHalfAngle, farRainHalfAngle)
            local distance = math.Rand(farRainMinimum, farRainMaximum)
            x, y = eyePosition.x + math.cos(heading) * distance, eyePosition.y + math.sin(heading) * distance
        else
            local side = eyeAngles:Right() * math.Rand(-680, 680)
            local forward = eyeAngles:Forward() * math.Rand(-200, 700)
            x, y = eyePosition.x + side.x + forward.x, eyePosition.y + side.y + forward.y
        end
        local z = openSkySpawnHeight(x, y, eyePosition.z, far and 180 or 260, far and 520 or 640)
        if not z then
            countDiagnostic("precipitationCoveredRejected")
            return
        end
        countDiagnostic(far and "precipitationFarSpawned" or "precipitationNearSpawned")
        local material = weather == "rain" and "effects/laser_tracer" or "particle/snow"
        local particle = emitter:Add(material, Vector(x, y, z))
        if not particle then return end

        particle:SetDieTime(weather == "rain" and 0.65 or 4.2)
        particle:SetStartAlpha(weather == "rain" and (far and 60 or 115) or (far and 150 or 210))
        particle:SetEndAlpha(0)
        particle:SetStartSize(weather == "rain" and (far and 3.2 or 1) or 2)
        particle:SetEndSize(weather == "rain" and (far and 2.6 or 0.8) or 3)
        particle:SetColor(weather == "rain" and 177 or 218, weather == "rain" and 194 or 226, weather == "rain" and 204 or 232)
        particle:SetCollide(true)
        particle:SetBounce(0)
        particle:SetCollideCallback(function(collidedParticle)
            collidedParticle:SetDieTime(0)
        end)

        if weather == "rain" then
            particle:SetStartLength(far and 64 or 34)
            particle:SetEndLength(far and 64 or 34)
            particle:SetVelocity(Vector(math.Rand(-45, 45), math.Rand(-45, 45), -1250))
        else
            particle:SetStartSize(math.Rand(1.6, 2.8))
            particle:SetEndSize(math.Rand(1.4, 2.4))
            particle:SetRoll(math.Rand(0, 360))
            particle:SetRollDelta(math.Rand(-1.5, 1.5))
            particle:SetAirResistance(18)
            particle:SetGravity(Vector(math.Rand(-10, 10), math.Rand(-10, 10), -22))
            particle:SetVelocity(Vector(math.Rand(-38, 38), math.Rand(-38, 38), math.Rand(-80, -40)))
        end
    end

    // Finds a drip edge: an overhang 24-520 units above eye height whose outward side opens to sky,
    // reached without crossing a wall. Returns the point just outside the edge, below the roof.
    local function probeRunoffEdge(eyePosition)
        countDiagnostic("runoffProbes")
        local angle = math.Rand(0, math.pi * 2)
        local distance = math.Rand(48, runoffRange)
        local px, py, pz = eyePosition.x + math.cos(angle) * distance, eyePosition.y + math.sin(angle) * distance, eyePosition.z
        local trace = traceColumn(px, py, pz)
        if trace.StartSolid or trace.HitSky or not trace.Hit or not trace.HitPos then return nil end
        local height = trace.HitPos.z - pz
        if height < 24 or height > 520 then return nil end

        local heading = math.Rand(0, math.pi * 2)
        local dx, dy = math.cos(heading), math.sin(heading)
        local covered, coveredZ, open = 0, trace.HitPos.z, nil
        for step = 1, 12 do
            local offset = step * 24
            local column = traceColumn(px + dx * offset, py + dy * offset, pz)
            if column.StartSolid then return nil end
            if column.HitSky or not column.Hit then
                open = offset
                break
            end
            covered = offset
            if column.HitPos then coveredZ = column.HitPos.z end
        end
        if not open then return nil end
        for _ = 1, 3 do
            local middle = (covered + open) * 0.5
            local column = traceColumn(px + dx * middle, py + dy * middle, pz)
            if column.StartSolid then return nil end
            if column.HitSky or not column.Hit then
                open = middle
            else
                covered = middle
                if column.HitPos then coveredZ = column.HitPos.z end
            end
        end

        // A wall between the probe and the edge means the opening belongs to a different space.
        edgeTraceStart:SetUnpacked(px, py, pz)
        edgeTraceEnd:SetUnpacked(px + dx * open, py + dy * open, pz)
        if util.TraceLine(edgeTrace).Hit then
            countDiagnostic("runoffWallRejected")
            return nil
        end
        return Vector(px + dx * (open + 3), py + dy * (open + 3), coveredZ - 2), -dy, dx
    end

    local function updateRunoffEdges(eyePosition, now)
        for index = #runoffEdges, 1, -1 do
            local edge = runoffEdges[index]
            if now >= edge.expiresAt or edge.position:DistToSqr(eyePosition) > (runoffRange + 400) ^ 2 then
                table.remove(runoffEdges, index)
            end
        end
        if #runoffEdges >= runoffMaximumEdges or now < nextRunoffProbeAt then return end
        nextRunoffProbeAt = now + runoffProbeInterval
        local position, tangentX, tangentY = probeRunoffEdge(eyePosition)
        if position then
            runoffEdges[#runoffEdges + 1] = {
                position = position, tangentX = tangentX, tangentY = tangentY, expiresAt = now + math.Rand(6, 10)
            }
            countDiagnostic("runoffEdgesFound")
        end
    end

    local function emitRunoff(eyePosition)
        if #runoffEdges == 0 then return end
        local emitter = Weather.GetEmitter(eyePosition)
        if not emitter then return end
        for _, edge in ipairs(runoffEdges) do
            if math.Rand(0, 1) < 0.7 then
                local origin, along = edge.position, math.Rand(-14, 14)
                local particle = emitter:Add("effects/laser_tracer",
                    Vector(origin.x + edge.tangentX * along, origin.y + edge.tangentY * along, origin.z))
                if particle then
                    particle:SetDieTime(1.1)
                    particle:SetStartAlpha(150)
                    particle:SetEndAlpha(0)
                    particle:SetStartSize(1.5)
                    particle:SetEndSize(1.2)
                    particle:SetColor(186, 202, 212)
                    particle:SetCollide(true)
                    particle:SetBounce(0)
                    particle:SetCollideCallback(function(collidedParticle)
                        collidedParticle:SetDieTime(0)
                    end)
                    particle:SetStartLength(10)
                    particle:SetEndLength(22)
                    particle:SetGravity(Vector(0, 0, -900))
                    particle:SetVelocity(Vector(math.Rand(-6, 6), math.Rand(-6, 6), math.Rand(-260, -140)))
                    countDiagnostic("runoffDrips")
                end
            end
        end
    end

    function Weather.PlayMountedSound(paths, position, level, pitch, volume, missingKey)
        local path = paths[math.random(#paths)]
        if file.Exists("sound/" .. path, "GAME") then
            sound.Play(path, position, level, pitch, volume)
            return true
        end
        if not Atmosphere[missingKey] then
            Atmosphere[missingKey] = true
            ErrorNoHalt("[ZombieSim] Mounted atmosphere sound is unavailable: " .. path .. "\n")
        end
        return false
    end

    local function startWindAmbience(player, now)
        local patch = Atmosphere.WindSoundPatch
        if not patch then
            if not file.Exists("sound/" .. Weather.WindSoundPath, "GAME") then
                if not Atmosphere.WindSoundMissing then
                    Atmosphere.WindSoundMissing = true
                    ErrorNoHalt("[ZombieSim] Mounted wind ambience is unavailable: " .. Weather.WindSoundPath .. "\n")
                end
                return
            end
            patch = CreateSound(player, Weather.WindSoundPath)
            if not patch then
                ErrorNoHalt("[ZombieSim] Could not create wind ambience sound patch.\n")
                return
            end
            Atmosphere.WindSoundPatch = patch
            patch:PlayEx(0, 100)
            patch:ChangeVolume(0.34, 2.5)
            Weather.NextWindGustAt = now + math.Rand(5, 10)
        elseif not patch:IsPlaying() then
            // Restart if the mounted wave has no loop cue.
            patch:PlayEx(0.34, 100)
        end

        if now >= Weather.NextWindGustAt then
            Weather.NextWindGustAt = now + math.Rand(9, 20)
            local offset = VectorRand() * 420
            offset.z = math.abs(offset.z) * 0.3 + 120
            Weather.PlayMountedSound(windGustSoundPaths, player:EyePos() + offset, 75, math.Rand(85, 110), math.Rand(0.25, 0.45), "WindGustSoundMissing")
        end
    end

    local function startRainAmbience(player)
        if Atmosphere.RainSoundPatch then return end
        if not file.Exists("sound/" .. Weather.RainSoundPath, "GAME") then
            if not Atmosphere.RainSoundMissing then
                Atmosphere.RainSoundMissing = true
                ErrorNoHalt("[ZombieSim] Mounted rain ambience is unavailable: " .. Weather.RainSoundPath .. "\n")
            end
            return
        end

        Atmosphere.RainSoundPatch = CreateSound(player, Weather.RainSoundPath)
        if not Atmosphere.RainSoundPatch then
            ErrorNoHalt("[ZombieSim] Could not create rain ambience sound patch.\n")
            return
        end
        Atmosphere.RainSoundPatch:PlayEx(0.24, 100)
    end

    local function findNearbyTransitionGate(position)
        local nearestGate
        local nearestDistance = 700 * 700
        for _, direction in ipairs({ "N", "E", "S", "W" }) do
            local count = math.min(GetGlobal2Int("ZMTransitionGateCount_" .. direction, 0), 4)
            for index = 1, count do
                local gate = GetGlobal2Vector("ZMTransitionGate_" .. direction .. "_" .. index, vector_origin)
                local distance = position:DistToSqr(gate)
                if distance < nearestDistance then
                    nearestGate = gate
                    nearestDistance = distance
                end
            end
        end
        return nearestGate
    end

    local function emitBoundaryMist(gate, fogColor)
        if not boundaryEmitter then
            boundaryEmitter = ParticleEmitter(gate)
        end
        if not boundaryEmitter then return end
        Atmosphere.BoundaryMistActive = true

        for _ = 1, 3 do
            local position = gate + Vector(math.Rand(-110, 110), math.Rand(-110, 110), math.Rand(-18, 104))
            local particle = boundaryEmitter:Add("particle/particle_smokegrenade", position)
            if particle then
                particle:SetDieTime(1.25)
                particle:SetStartAlpha(15)
                particle:SetEndAlpha(0)
                particle:SetStartSize(math.Rand(44, 62))
                particle:SetEndSize(math.Rand(88, 124))
                particle:SetColor(Fog.GetColorComponent(fogColor, 1), Fog.GetColorComponent(fogColor, 2), Fog.GetColorComponent(fogColor, 3))
                particle:SetCollide(false)
                particle:SetVelocity(Vector(math.Rand(-16, 16), math.Rand(-16, 16), math.Rand(-2, 5)))
            end
        end
    end

    local function emitBreath(player, now)
        if (player.ZM_NextBreathAt or 0) > now then return end
        player.ZM_NextBreathAt = now + math.Rand(2.6, 4)
        local emitter = Weather.GetEmitter(player:EyePos())
        if not emitter then return end

        local aim = player:EyeAngles():Forward()
        local origin = player:EyePos() + aim * 10 - Vector(0, 0, 4)
        local velocity = player:GetVelocity()
        for _ = 1, 4 do
            local particle = emitter:Add("particle/particle_smokegrenade", origin + VectorRand() * 1.5)
            if particle then
                particle:SetDieTime(math.Rand(1, 1.5))
                particle:SetStartAlpha(28)
                particle:SetEndAlpha(0)
                particle:SetStartSize(math.Rand(1.5, 2.5))
                particle:SetEndSize(math.Rand(9, 13))
                particle:SetColor(236, 240, 245)
                particle:SetCollide(false)
                particle:SetAirResistance(60)
                particle:SetGravity(Vector(0, 0, 6))
                particle:SetVelocity(velocity * 0.8 + aim * math.Rand(22, 34) + VectorRand() * 4)
            end
        end
        Atmosphere.BreathPuffs = (Atmosphere.BreathPuffs or 0) + 1
    end

    // WinterBlend eases the cold grade and fog over winterBlendSeconds; FrostAmount additionally needs open sky.
    function Weather.UpdateWinter()
        local localPlayer = LocalPlayer()
        local outdoorCell = IsValid(localPlayer) and Environment.IsOutdoorCityCell(localPlayer)
        local snowing = Atmosphere.Weather == "snow"
        local step = FrameTime() / winterBlendSeconds
        Atmosphere.WinterBlend = math.Approach(Atmosphere.WinterBlend or 0, (snowing and outdoorCell) and 1 or 0, step)
        local exposed = snowing and outdoorCell and not Environment.CheckShelter(localPlayer, CurTime())
        Atmosphere.FrostAmount = math.Approach(Atmosphere.FrostAmount or 0, exposed and 1 or 0, step)
        if Atmosphere.WinterBlend < 0.5 or not outdoorCell then return end

        local now = CurTime()
        local eyePosition = EyePos()
        for _, other in ipairs(player.GetAll()) do
            if other:Alive() and other:EyePos():DistToSqr(eyePosition) < 1500 * 1500 then
                emitBreath(other, now)
            end
        end
    end

    function Weather.UpdateWeatherEffects()
        Weather.Diagnostics.weatherThinkAt = RealTime()
        local player = LocalPlayer()
        local weather = Atmosphere.Weather
        Weather.Diagnostics.weather = weather
        Weather.Diagnostics.playerValid = IsValid(player)
        Weather.Diagnostics.outdoorCityCell = IsValid(player) and Environment.IsOutdoorCityCell(player) or false
        if not IsValid(player) or not Weather.Diagnostics.outdoorCityCell then
            Atmosphere:StopWeatherEffects()
            Environment.IsSheltered = nil
            Environment.NextShelterCheckAt = 0
            return
        end
        if weather ~= "rain" and weather ~= "snow" then
            Atmosphere:StopWeatherEffects()
            return
        end

        local now = CurTime()
        local sheltered = Environment.CheckShelter(player, now) == true
        Weather.Diagnostics.sheltered = sheltered
        if weather == "rain" then
            startRainAmbience(player)
            local patch = Atmosphere.RainSoundPatch
            if patch and Atmosphere.RainSoundSheltered ~= sheltered then
                Atmosphere.RainSoundSheltered = sheltered
                patch:ChangeVolume(sheltered and 0.13 or 0.24, 0.8)
            end
        else
            startWindAmbience(player, now)
        end

        local interval = weather == "rain" and 0.05 or 0.1
        local density = math.Clamp(Weather.RainDensityConVar:GetFloat(), 0.5, 2)
        local particlesPerBurst = weather == "rain" and math.Clamp(math.Round(4 * density), 2, 8) or math.Clamp(math.Round(3 * density), 2, 6)
        local farParticlesPerBurst = weather == "rain" and math.Clamp(math.Round(2 * density), 1, 4) or 0
        Weather.Diagnostics.particleInterval = interval
        Weather.Diagnostics.particlesPerBurst = particlesPerBurst
        Weather.Diagnostics.farParticlesPerBurst = farParticlesPerBurst
        Weather.Diagnostics.rainDensity = density
        local eyePosition = player:EyePos()
        if weather == "rain" then
            updateRunoffEdges(eyePosition, now)
        elseif #runoffEdges > 0 then
            table.Empty(runoffEdges)
        end
        Weather.Diagnostics.runoffEdges = #runoffEdges
        if now < nextWeatherParticleAt then return end
        nextWeatherParticleAt = now + interval
        local eyeAngles = EyeAngles()
        for _ = 1, particlesPerBurst do
            emitPrecipitationParticle(weather, eyePosition, eyeAngles, false)
        end
        for _ = 1, farParticlesPerBurst do
            emitPrecipitationParticle(weather, eyePosition, eyeAngles, true)
        end
        if weather == "rain" then emitRunoff(eyePosition) end
    end

    function Weather.UpdateBoundaryMist()
        Weather.Diagnostics.boundaryThinkAt = RealTime()
        local player = LocalPlayer()
        Weather.Diagnostics.boundaryOutdoorCityCell = IsValid(player) and Environment.IsOutdoorCityCell(player) or false
        if not Weather.Diagnostics.boundaryOutdoorCityCell then
            Atmosphere:StopBoundaryEffects()
            return
        end

        local now = CurTime()
        if now < nextBoundaryParticleAt then return end
        nextBoundaryParticleAt = now + 0.12
        if Environment.CheckShelter(player, now) then
            Atmosphere:StopBoundaryEffects()
            return
        end

        local gate = findNearbyTransitionGate(player:GetPos())
        if not gate then
            Atmosphere:StopBoundaryEffects()
            return
        end
        local fog = Atmosphere:GetFogSettings()
        if not fog then
            Atmosphere:StopBoundaryEffects()
            return
        end
        emitBoundaryMist(gate, fog.color)
    end

    function Weather.GetEmitter(position)
        if not weatherEmitter then
            weatherEmitter = ParticleEmitter(position)
            if weatherEmitter then
                weatherEmitter:SetNoDraw(Atmosphere.MapCaptureParticlesHidden == true)
            end
        end
        return weatherEmitter
    end

    function Weather.SetParticlesHidden(hidden)
        if weatherEmitter then weatherEmitter:SetNoDraw(hidden) end
        for _, emitter in ipairs(Atmosphere.RetiredWeatherEmitters) do
            emitter:SetNoDraw(hidden)
        end
    end

    function Weather.Reset()
        Weather.NextWindGustAt = 0
    end

    function Weather.Shutdown()
        Atmosphere:StopWeatherEffects()
        for _, emitter in ipairs(Atmosphere.RetiredWeatherEmitters) do emitter:Finish() end
        Atmosphere.RetiredWeatherEmitters = {}
        Atmosphere:StopBoundaryEffects()
    end

    function Modules.Weather.RegisterHooks()
        hook.Add("Think", "ZM.Atmosphere.RetiredWeatherCleanup", function()
            for index = #Atmosphere.RetiredWeatherEmitters, 1, -1 do
                local emitter = Atmosphere.RetiredWeatherEmitters[index]
                if emitter:GetNumActiveParticles() == 0 then
                    emitter:Finish()
                    table.remove(Atmosphere.RetiredWeatherEmitters, index)
                end
            end
        end)
    end
end
