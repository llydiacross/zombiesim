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

    local function emitPrecipitationParticle(weather, eyePosition, eyeAngles)
        local emitter = Weather.GetEmitter(eyePosition)
        if not emitter then return end

        local side = eyeAngles:Right() * math.Rand(-620, 620)
        local forward = eyeAngles:Forward() * math.Rand(-180, 420)
        local position = eyePosition + side + forward + Vector(0, 0, math.Rand(260, 640))
        local material = weather == "rain" and "effects/laser_tracer" or "particle/snow"
        local particle = emitter:Add(material, position)
        if not particle then return end

        particle:SetDieTime(weather == "rain" and 0.65 or 4.2)
        particle:SetStartAlpha(weather == "rain" and 115 or 210)
        particle:SetEndAlpha(0)
        particle:SetStartSize(weather == "rain" and 1 or 2)
        particle:SetEndSize(weather == "rain" and 0.8 or 3)
        particle:SetColor(weather == "rain" and 177 or 218, weather == "rain" and 194 or 226, weather == "rain" and 204 or 232)
        particle:SetCollide(true)
        particle:SetBounce(0)
        particle:SetCollideCallback(function(collidedParticle)
            collidedParticle:SetDieTime(0)
        end)

        if weather == "rain" then
            particle:SetStartLength(34)
            particle:SetEndLength(34)
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
        if Environment.CheckShelter(player, now) then
            Atmosphere:StopWeatherEffects()
            return
        end
        if weather == "rain" then
            startRainAmbience(player)
        else
            startWindAmbience(player, now)
        end

        local interval = weather == "rain" and 0.05 or 0.1
        local density = math.Clamp(Weather.RainDensityConVar:GetFloat(), 0.5, 2)
        local particlesPerBurst = weather == "rain" and math.Clamp(math.Round(4 * density), 2, 8) or math.Clamp(math.Round(3 * density), 2, 6)
        Weather.Diagnostics.particleInterval = interval
        Weather.Diagnostics.particlesPerBurst = particlesPerBurst
        Weather.Diagnostics.rainDensity = density
        if now < nextWeatherParticleAt then return end
        nextWeatherParticleAt = now + interval
        local eyePosition = player:EyePos()
        local eyeAngles = EyeAngles()
        for _ = 1, particlesPerBurst do
            emitPrecipitationParticle(weather, eyePosition, eyeAngles)
        end
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
