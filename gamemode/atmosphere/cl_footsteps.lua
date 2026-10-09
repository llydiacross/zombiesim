// Weather footsteps, predicted puddle steps, mounted sounds and splash records.
return function(Atmosphere, Modules)
    local Environment = Modules.Environment
    local Weather = Modules.Weather
    local Puddles = Modules.Puddles
    local Snow = Modules.Snow
    local Footsteps = Modules.Footsteps
    local splashes = {}
    Footsteps.Splashes = splashes
    Footsteps.PuddleSloshSoundPaths = {
        "player/footsteps/slosh1.wav",
        "player/footsteps/slosh2.wav",
        "player/footsteps/slosh3.wav",
        "player/footsteps/slosh4.wav"
    }
    Footsteps.SnowStepSoundPaths = {
        "player/footsteps/snow1.wav",
        "player/footsteps/snow2.wav",
        "player/footsteps/snow3.wav",
        "player/footsteps/snow4.wav",
        "player/footsteps/snow5.wav",
        "player/footsteps/snow6.wav"
    }
    Atmosphere.StepCount = Atmosphere.StepCount or 0
    Footsteps.StepDistance = 0
    Footsteps.LastStepPosition = nil
    Atmosphere.FootstepSplashMaterial = Material("effects/splash2")
    if Atmosphere.FootstepSplashMaterial:IsError() then
        ErrorNoHalt("[ZombieSim] Mounted footstep splash material is unavailable.\n")
    end

    // A step into a puddle throws a larger crown and sloshes; a step on merely rain-wet ground only patters.
    local function addFootstepSplash(position, inPuddle)
        local now = CurTime()
        splashes[#splashes + 1] = {
            position = position + Vector(0, 0, 1),
            createdAt = now,
            expiresAt = now + 0.45,
            rotation = math.Rand(0, 360),
            size = inPuddle and 58 or 22
        }
        if #splashes > 12 then
            table.remove(splashes, 1)
        end

        if inPuddle then
            local emitter = Weather.GetEmitter(position)
            if emitter and not Atmosphere.FootstepSplashMaterial:IsError() then
                for _ = 1, 5 do
                    local particle = emitter:Add("effects/splash2", position + Vector(math.Rand(-4, 4), math.Rand(-4, 4), 1))
                    if particle then
                        particle:SetDieTime(math.Rand(0.3, 0.45))
                        particle:SetStartAlpha(110)
                        particle:SetEndAlpha(0)
                        particle:SetStartSize(math.Rand(2, 4))
                        particle:SetEndSize(math.Rand(7, 11))
                        particle:SetRoll(math.Rand(0, 360))
                        particle:SetColor(150, 162, 168)
                        particle:SetCollide(false)
                        particle:SetGravity(Vector(0, 0, -380))
                        particle:SetVelocity(Vector(math.Rand(-55, 55), math.Rand(-55, 55), math.Rand(60, 130)))
                    end
                end
            end
            return Weather.PlayMountedSound(Footsteps.PuddleSloshSoundPaths, position, 70, math.Rand(94, 106), 0.55, "PuddleSloshSoundMissing")
        end
        return Weather.PlayMountedSound(Footsteps.PuddleSloshSoundPaths, position, 60, math.Rand(108, 118), 0.14, "PuddleSloshSoundMissing")
    end

    local function addSnowStep(position, onSnowPatch)
        if onSnowPatch then
            local emitter = Weather.GetEmitter(position)
            if emitter then
                for _ = 1, 5 do
                    local particle = emitter:Add("particle/particle_smokegrenade", position + Vector(math.Rand(-6, 6), math.Rand(-6, 6), 2))
                    if particle then
                        particle:SetDieTime(math.Rand(0.5, 0.8))
                        particle:SetStartAlpha(70)
                        particle:SetEndAlpha(0)
                        particle:SetStartSize(math.Rand(3, 5))
                        particle:SetEndSize(math.Rand(9, 14))
                        particle:SetColor(232, 238, 244)
                        particle:SetCollide(false)
                        particle:SetAirResistance(80)
                        particle:SetVelocity(Vector(math.Rand(-30, 30), math.Rand(-30, 30), math.Rand(10, 34)))
                    end
                end
            end
        end
        Weather.PlayMountedSound(Footsteps.SnowStepSoundPaths, position, 65, math.Rand(92, 106), onSnowPatch and 0.6 or 0.32, "SnowStepSoundMissing")
    end

    // PlayerFootstep does not run clientside in singleplayer, so weather footsteps follow distance walked instead.
    function Footsteps.UpdateWeatherFootsteps()
        local player = LocalPlayer()
        if not IsValid(player) or not player:Alive() or not player:IsOnGround()
            or player:GetMoveType() == MOVETYPE_NOCLIP or player:WaterLevel() > 0 then
            Footsteps.LastStepPosition = nil
            Footsteps.StepDistance = 0
            return
        end
        local position = player:GetPos()
        local weather = Atmosphere.Weather
        if Footsteps.LastStepPosition then
            local dx = position.x - Footsteps.LastStepPosition.x
            local dy = position.y - Footsteps.LastStepPosition.y
            local moved = math.sqrt(dx * dx + dy * dy)
            // Teleports and cell transitions must not count as walking.
            if moved < 64 then
                Footsteps.StepDistance = Footsteps.StepDistance + moved
            end
        end
        Footsteps.LastStepPosition = position

        local speed = player:GetVelocity():Length2D()
        local stride = speed > 200 and 92 or 70
        if Footsteps.StepDistance < stride then return end
        Footsteps.StepDistance = 0

        local puddle = weather == "rain" and Puddles.FindPuddleAt(position) or nil
        local snowPoint = (Atmosphere.SnowCoverAmount or 0) > 0.15 and Snow.GetSnowCoverPointAt(position) or nil
        if snowPoint and (Snow.Cover.stage or 0) - snowPoint.patch * 0.6 < 0.15 then
            snowPoint = nil
        end
        local outdoors = Environment.IsOutdoorCityCell(player) and not Environment.CheckShelter(player, CurTime())
        local result
        if puddle then
            // Multiplayer puddle steps are handled by PlayerFootstep; keep other weather steps here.
            if not game.SinglePlayer() then return end
            addFootstepSplash(position, true)
            result = "puddle"
        elseif snowPoint then
            addSnowStep(position, true)
            result = "snow cover"
        elseif outdoors and weather == "snow" then
            addSnowStep(position, false)
            result = "snowfall"
        elseif outdoors and weather == "rain" then
            addFootstepSplash(position, false)
            result = "wet ground"
        end
        if result then
            Atmosphere.StepCount = (Atmosphere.StepCount or 0) + 1
            Atmosphere.LastStep = { surface = result, time = RealTime() }
        end
    end

    local splashColor = Color(170, 205, 218, 0)
    local splashNormal = Vector(0, 0, 1)

    function Footsteps.DrawSplashes(now, material)
        // Rain crowns bind their beam material; footsteps must rebind their own texture.
        render.SetMaterial(material)
        for index = #splashes, 1, -1 do
            local splash = splashes[index]
            local life = math.Clamp((splash.expiresAt - now) / 0.45, 0, 1)
            if life <= 0 then
                table.remove(splashes, index)
            elseif not material:IsError() and splash.position:ToScreen().visible then
                local size = (splash.size or 44) * (1 - life) + 8
                splashColor.a = 90 * life
                render.DrawQuadEasy(splash.position, splashNormal, size, size, splashColor, splash.rotation)
            end
        end
    end

    function Footsteps.Reset()
        table.Empty(splashes)
        Footsteps.LastStepPosition = nil
        Footsteps.StepDistance = 0
    end

    function Modules.Footsteps.RegisterHooks()
        hook.Add("PlayerFootstep", "ZM.Atmosphere.RainFootstepSplash", function(player, position)
            local localPlayer = LocalPlayer()
            if game.SinglePlayer() or player ~= localPlayer or not IsValid(localPlayer)
                or Atmosphere.Weather ~= "rain" or not Environment.IsOutdoorCityCell(localPlayer)
                or Environment.CheckShelter(localPlayer, CurTime()) then
                return
            end

            local puddle = Puddles.FindPuddleAt(position)
            if not puddle then return end
            if not IsFirstTimePredicted() then return true end

            local soundPlayed = addFootstepSplash(position, true)
            Atmosphere.StepCount = (Atmosphere.StepCount or 0) + 1
            Atmosphere.LastStep = { surface = "puddle", time = RealTime() }
            if soundPlayed then return true end
        end)
    end
end
