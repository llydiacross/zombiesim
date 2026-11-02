// Storm lightning: cosmetic, client-local strikes during stormy rain. Each strike draws a branching bolt in the 3D
// skybox between the cloud base and the ground, brightens the sky/cloud colour and the world view for a brief
// flicker, and plays distant thunder delayed by the strike distance. Nothing here affects gameplay or the server.
return function(Skybox, helpers)
    local getConVarNumber = helpers.getConVarNumber

    local Lightning = Skybox.Lightning or {}
    Skybox.Lightning = Lightning
    Lightning.Stats = Lightning.Stats or { strikes = 0, forcedStrikes = 0 }
    Lightning.PendingThunder = Lightning.PendingThunder or {}

    CreateClientConVar("zombiesim_lightning_reduce_flashes", "0", true, false,
        "Reduce lightning sky and screen flashes to a single gentle pulse.", 0, 1)

    local minimumStorm = 0.3
    local intervalMin, intervalMax = 20, 60
    local cloudBase = 300
    local groundLift = 2
    local mainSegments = { 10, 14 }
    local boltColor = Color(200, 210, 255)
    local flashSkyColor = { 220, 225, 255 }
    local pulseDecay = 0.09
    local flashDuration = 0.6
    // Source units per second for sound (~343 m/s); the delay is clamped so very distant strikes still read as one event.
    local soundSpeed = 13500
    local thunderSounds = {
        "ambient/atmosphere/thunder1.wav",
        "ambient/atmosphere/thunder2.wav",
        "ambient/atmosphere/thunder3.wav",
        "ambient/atmosphere/thunder4.wav"
    }

    local boltMaterial = CreateMaterial("zombiesim_lightning_bolt_v1", "UnlitGeneric", {
        ["$basetexture"] = "sprites/laserbeam",
        ["$additive"] = 1,
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$nocull"] = 1,
        ["$nofog"] = 1
    })
    local glowMaterial = CreateMaterial("zombiesim_lightning_glow_v1", "UnlitGeneric", {
        ["$basetexture"] = "sprites/light_glow02",
        ["$additive"] = 1,
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$nocull"] = 1,
        ["$nofog"] = 1
    })
    Lightning.BoltMaterial = boltMaterial
    Lightning.GlowMaterial = glowMaterial

    local flashColor = { 0, 0, 0 }
    local drawColor = Color(255, 255, 255, 255)
    local pointA = Vector()
    local glowPosition = Vector()
    local worldFlashSettings = {
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = 0,
        ["$pp_colour_contrast"] = 1,
        ["$pp_colour_colour"] = 1,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    }

    local function reducedFlashes()
        return getConVarNumber("zombiesim_lightning_reduce_flashes", 0) > 0
    end

    local function textureWidth(material)
        local texture = material:GetTexture("$basetexture")
        return texture and texture:Width() or 0
    end

    // Strikes stay out of the launcher, dens and non-world contexts; the bolt itself only draws in the 3D skybox pass.
    local function suppressionReason()
        if ZM_LauncherMenu and ZM_LauncherMenu.Active then return "launcher" end
        local player = LocalPlayer()
        if not IsValid(player) then return "no local player" end
        if ZM_SafeZones and ZM_SafeZones:IsPlayerInside(player) then return "inside den" end
        if not Skybox.Manifest then return "no skybox manifest" end
        return nil
    end

    local function stormAmount()
        local atmosphere = ZM_Atmosphere
        if not atmosphere or atmosphere.Weather ~= "rain" then return 0 end
        return atmosphere.StormIntensity or 0
    end

    local function scheduleNext(now, storm)
        Lightning.NextStrikeAt = now + math.Rand(intervalMin, intervalMax) / math.max(storm, 0.1)
    end

    // Builds the flicker envelope: one to three return strokes, or a single gentle pulse when reduced.
    local function buildPulses(reduced)
        if reduced then return { { 0, 1 } } end
        local pulses = { { 0, 1 } }
        local count = math.random(1, 3)
        if count >= 2 then pulses[#pulses + 1] = { 0.07 + math.Rand(0, 0.03), math.Rand(0.45, 0.65) } end
        if count >= 3 then pulses[#pulses + 1] = { 0.18 + math.Rand(0, 0.05), math.Rand(0.6, 0.85) } end
        return pulses
    end

    // Bolt points are stored relative to the strike foot in sky units; draw time adds the sky eye position.
    local function buildBolt(height)
        local segments = math.random(mainSegments[1], mainSegments[2])
        local step = height / segments
        local main = {}
        local x, y = 0, 0
        local drift = step * 0.55
        for index = 0, segments do
            local z = height - index * step
            if index > 0 and index < segments then
                x = x + math.Rand(-drift, drift)
                y = y + math.Rand(-drift, drift)
            elseif index == segments then
                // The channel ends near the start's column so the foot stays planted below the glow.
                x, y = x * 0.6, y * 0.6
            end
            main[#main + 1] = { x, y, z }
        end
        local branches = {}
        for _ = 1, math.random(2, 4) do
            local origin = main[math.random(2, math.max(2, segments - 3))]
            local branch = { { origin[1], origin[2], origin[3] } }
            local bx, by, bz = origin[1], origin[2], origin[3]
            local angle = math.Rand(0, math.pi * 2)
            local outX, outY = math.cos(angle) * step * 0.6, math.sin(angle) * step * 0.6
            for _ = 1, math.random(3, 5) do
                bx = bx + outX + math.Rand(-drift, drift) * 0.6
                by = by + outY + math.Rand(-drift, drift) * 0.6
                bz = bz - step * math.Rand(0.5, 0.9)
                if bz <= 0 then break end
                branch[#branch + 1] = { bx, by, bz }
            end
            if #branch >= 2 then branches[#branches + 1] = branch end
        end
        return main, branches
    end

    function Lightning:GetDistanceRange(manifest)
        local scale = manifest.scale
        local boundary = ZM_SkyboxGeometry.GetFogBoundary(manifest) / scale
        local edge = Skybox:GetFogEdge(manifest) / scale
        local nearest = boundary * 1.3
        local farthest = math.max(nearest + 1, edge * 0.85)
        return nearest, farthest
    end

    function Lightning:Strike(forced)
        local reason = suppressionReason()
        if reason then
            self.Stats.lastRejected = reason
            return false, reason
        end
        local manifest = Skybox.Manifest
        local nearest, farthest = self:GetDistanceRange(manifest)
        local fraction = math.Rand(0, 1)
        local distance = Lerp(fraction, nearest, farthest)
        local azimuth = math.Rand(0, math.pi * 2)
        local main, branches = buildBolt(cloudBase - groundLift)
        local now = RealTime()
        local reduced = reducedFlashes()
        self.Active = {
            startedAt = now,
            offsetX = math.cos(azimuth) * distance,
            offsetY = math.sin(azimuth) * distance,
            distance = distance,
            fraction = fraction,
            main = main,
            branches = branches,
            pulses = buildPulses(reduced),
            reduced = reduced
        }
        local worldDistance = distance * manifest.scale
        local thunder = self.PendingThunder
        thunder[#thunder + 1] = {
            at = now + math.Clamp(worldDistance / soundSpeed, 0.4, 6),
            sound = thunderSounds[math.random(#thunderSounds)],
            volume = Lerp(fraction, 1, 0.45),
            pitch = math.random(92, 106),
            directionX = math.cos(azimuth),
            directionY = math.sin(azimuth)
        }
        local stats = self.Stats
        stats.strikes = stats.strikes + 1
        if forced then stats.forcedStrikes = stats.forcedStrikes + 1 end
        stats.lastStrikeAt = now
        stats.lastDistanceSky = distance
        stats.lastDistanceWorld = worldDistance
        stats.lastThunderDelay = thunder[#thunder].at - now
        stats.lastPulses = #self.Active.pulses
        stats.lastBranches = #branches
        stats.lastRejected = nil
        return true
    end

    // Raw envelope in 0..1, before the sky/world reduction factors.
    function Lightning:GetFlash(now)
        local active = self.Active
        if not active then return 0 end
        local age = now - active.startedAt
        if age > flashDuration then
            self.Active = nil
            return 0
        end
        local value = 0
        for _, pulse in ipairs(active.pulses) do
            local offset = age - pulse[1]
            if offset >= 0 then value = math.max(value, pulse[2] * math.exp(-offset / pulseDecay)) end
        end
        // A short tail ensures the flash always settles to exactly zero at the end of the window.
        return value * math.Clamp((flashDuration - age) / 0.1, 0, 1)
    end

    function Lightning:GetSkyFlash(now)
        local flash = self:GetFlash(now)
        local active = self.Active
        return flash * (active and active.reduced and 0.4 or 1)
    end

    function Lightning:GetWorldFlash(now)
        local flash = self:GetFlash(now)
        local active = self.Active
        return flash * (active and active.reduced and 0.2 or 1)
    end

    // Returns the shared fog colour unchanged, or a reused brightened copy while a flash is visible.
    function Lightning:ApplySkyFlash(fogColor)
        local amount = self:GetSkyFlash(RealTime()) * 0.5
        self.Stats.lastSkyFlash = amount
        if amount <= 0.002 then return fogColor end
        flashColor[1] = Lerp(amount, fogColor[1] or 128, flashSkyColor[1])
        flashColor[2] = Lerp(amount, fogColor[2] or 128, flashSkyColor[2])
        flashColor[3] = Lerp(amount, fogColor[3] or 128, flashSkyColor[3])
        return flashColor
    end

    local function drawStrand(points, footX, footY, footZ, width, alpha)
        local count = #points
        if count < 2 then return end
        render.StartBeam(count)
        for index, point in ipairs(points) do
            pointA:SetUnpacked(footX + point[1], footY + point[2], footZ + point[3])
            drawColor.r, drawColor.g, drawColor.b = boltColor.r, boltColor.g, boltColor.b
            drawColor.a = alpha
            render.AddBeam(pointA, width, (index - 1) / (count - 1), drawColor)
        end
        render.EndBeam()
    end

    // Draws the active bolt in sky units; called by Skybox:Draw after the cloud deck.
    function Lightning:Draw(manifest, skyEye, fogStart, fogEnd)
        local active = self.Active
        local stats = self.Stats
        stats.frameBolts = 0
        if not active or not manifest then return end
        local flash = self:GetFlash(RealTime())
        if flash <= 0.01 then return end
        local footX = skyEye.x + active.offsetX
        local footY = skyEye.y + active.offsetY
        local footZ = manifest.cameraVector.z + groundLift
        local fogAmount = math.Clamp((active.distance - fogStart) / math.max(fogEnd - fogStart, 1), 0, 1)
        local alpha = math.Clamp(flash * (1 - 0.5 * fogAmount), 0, 1) * 255
        if alpha < 2 then return end
        local core = math.max(1.5, active.distance * 0.004)
        render.SetMaterial(boltMaterial)
        drawStrand(active.main, footX, footY, footZ, core * 4, alpha * 0.35)
        drawStrand(active.main, footX, footY, footZ, core, alpha)
        for _, branch in ipairs(active.branches) do
            drawStrand(branch, footX, footY, footZ, core * 0.6, alpha * 0.75)
        end
        local top = active.main[1]
        glowPosition:SetUnpacked(footX + top[1], footY + top[2], footZ + top[3])
        local glowSize = active.distance * 0.3
        drawColor.r, drawColor.g, drawColor.b, drawColor.a = 210, 220, 255, alpha * 0.8
        render.SetMaterial(glowMaterial)
        render.DrawSprite(glowPosition, glowSize, glowSize, drawColor)
        stats.frameBolts = 1
        stats.lastBoltDraw = RealTime()
    end

    local function updateThunder(now)
        local thunder = Lightning.PendingThunder
        local index = 1
        while index <= #thunder do
            local entry = thunder[index]
            if now >= entry.at then
                table.remove(thunder, index)
                local player = LocalPlayer()
                if IsValid(player) then
                    local eye = player:EyePos()
                    local sheltered = ZM_Atmosphere and ZM_Atmosphere.Modules and ZM_Atmosphere.Modules.Environment
                        and ZM_Atmosphere.Modules.Environment.IsSheltered
                    local volume = entry.volume * (sheltered and 0.75 or 1)
                    // SNDLVL_NONE plays at full level everywhere; the offset only gives a stereo direction.
                    sound.Play(entry.sound, eye + Vector(entry.directionX * 256, entry.directionY * 256, 64), 0, entry.pitch, volume)
                    Lightning.Stats.thunderPlayed = (Lightning.Stats.thunderPlayed or 0) + 1
                    Lightning.Stats.lastThunder = entry.sound
                end
            else
                index = index + 1
            end
        end
    end

    function Lightning:Update()
        local now = RealTime()
        updateThunder(now)
        local storm = stormAmount()
        local stats = self.Stats
        stats.storm = storm
        if storm < minimumStorm or suppressionReason() then
            self.NextStrikeAt = nil
            return
        end
        if not self.NextStrikeAt then
            scheduleNext(now, storm)
            return
        end
        if now >= self.NextStrikeAt then
            self:Strike(false)
            scheduleNext(now, storm)
        end
    end

    function Lightning:GetDiagnostics()
        local stats = self.Stats
        local now = RealTime()
        return {
            storm = stats.storm,
            strikes = stats.strikes,
            forcedStrikes = stats.forcedStrikes,
            nextStrikeIn = self.NextStrikeAt and (self.NextStrikeAt - now) or nil,
            lastStrikeAge = stats.lastStrikeAt and (now - stats.lastStrikeAt) or nil,
            lastDistanceSky = stats.lastDistanceSky,
            lastDistanceWorld = stats.lastDistanceWorld,
            lastThunderDelay = stats.lastThunderDelay,
            lastPulses = stats.lastPulses,
            lastBranches = stats.lastBranches,
            lastBoltDrawAge = stats.lastBoltDraw and (now - stats.lastBoltDraw) or nil,
            lastRejected = stats.lastRejected,
            thunderPlayed = stats.thunderPlayed or 0,
            lastThunder = stats.lastThunder,
            pendingThunder = #self.PendingThunder,
            reducedFlashes = reducedFlashes(),
            suppression = suppressionReason(),
            boltMaterialError = boltMaterial:IsError(),
            boltTextureWidth = textureWidth(boltMaterial),
            glowMaterialError = glowMaterial:IsError(),
            glowTextureWidth = textureWidth(glowMaterial)
        }
    end

    function Lightning:Reset()
        self.Active = nil
        self.NextStrikeAt = nil
        table.Empty(self.PendingThunder)
    end

    hook.Add("Think", "ZM.Skybox.Lightning", function()
        Lightning:Update()
    end)

    // A separate pass so the atmosphere colour grade stays untouched; it only runs while a flash is visible.
    hook.Add("RenderScreenspaceEffects", "ZM.Skybox.LightningFlash", function()
        local flash = Lightning:GetWorldFlash(RealTime())
        if flash <= 0.002 then return end
        if suppressionReason() then return end
        local environment = ZM_Atmosphere and ZM_Atmosphere.Modules and ZM_Atmosphere.Modules.Environment
        if environment and environment.IsSheltered then flash = flash * 0.5 end
        worldFlashSettings["$pp_colour_brightness"] = 0.16 * flash
        worldFlashSettings["$pp_colour_contrast"] = 1 + 0.08 * flash
        worldFlashSettings["$pp_colour_addb"] = 0.02 * flash
        DrawColorModify(worldFlashSettings)
        Lightning.Stats.lastWorldFlash = flash
    end)

    // Development aid: forces one strike now, ignoring weather but not launcher/den suppression.
    concommand.Add("zombiesim_lightning_strike", function()
        local ok, reason = Lightning:Strike(true)
        print(ok and "[ZombieSim] Lightning strike forced." or ("[ZombieSim] Lightning strike rejected: " .. tostring(reason)))
    end)

    return Lightning
end
