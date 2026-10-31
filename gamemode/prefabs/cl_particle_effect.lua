return function(api)
    local Service = {}
    local Handle = {}
    Handle.__index = Handle
    local loaded, precached = {}, {}
    local anchorModel = "models/props_c17/oildrum001.mdl"

    local function createParticle(definition, position, angles)
        local effect = api.CreateParticleSystemNoEntity(definition.particleSystem, position, angles)
        if not api.IsValid(effect) then return nil, "Could not create particle effect: " .. definition.id end
        return effect
    end

    function Service.Create(definition, position, angles, mode)
        if type(definition) ~= "table" or type(definition.id) ~= "string"
            or type(definition.particleFile) ~= "string" or type(definition.particleSystem) ~= "string"
            or type(definition.sound) ~= "string" or (mode ~= "continuous" and mode ~= "triggered") then
            return nil, "Invalid prefab particle definition or mode."
        end
        if not api.file.Exists(definition.particleFile, "GAME")
            or not api.file.Exists("sound/" .. definition.sound, "GAME") then
            return nil, "Mounted particle file or sound is unavailable: " .. tostring(definition.id)
        end
        local anchor = api.ClientsideModel(anchorModel, api.RENDERGROUP_OTHER)
        if not api.IsValid(anchor) then return nil, "Could not create a prefab particle audio anchor." end
        anchor:SetNoDraw(true)
        anchor:SetPos(position)
        if not loaded[definition.particleFile] then
            api.game.AddParticles(definition.particleFile)
            loaded[definition.particleFile] = true
        end
        if not precached[definition.particleSystem] then
            api.PrecacheParticleSystem(definition.particleSystem)
            precached[definition.particleSystem] = true
        end
        local effect, problem = createParticle(definition, position, angles)
        if not effect then anchor:Remove() return nil, problem end
        local sound = api.CreateSound(anchor, definition.sound)
        if not sound then
            effect:StopEmission(false, true, false)
            anchor:Remove()
            return nil, "Could not create prefab particle sound: " .. definition.id
        end
        sound:SetSoundLevel(75)
        sound:Play()
        local now = api.RealTime()
        return setmetatable({
            Definition = definition, Position = position, Angles = angles, Mode = mode,
            Effect = effect, Anchor = anchor, Sound = sound, StartedAt = now, LastSpawnAt = now,
            Replacements = 0
        }, Handle)
    end

    function Handle:Stop()
        if self.Sound then self.Sound:Stop() end
        if api.IsValid(self.Effect) then self.Effect:StopEmission(false, true, false) end
        if api.IsValid(self.Anchor) then self.Anchor:Remove() end
        self.Sound, self.Effect, self.Anchor = nil, nil, nil
    end

    function Handle:Move(position, angles)
        self.Position, self.Angles = position, angles
        if api.IsValid(self.Anchor) then self.Anchor:SetPos(position) end
        if api.IsValid(self.Effect) then
            self.Effect:SetControlPoint(0, position)
            self.Effect:SetControlPoint(1, position)
            self.Effect:SetControlPointOrientation(0, angles)
        end
    end

    function Handle:Update()
        if api.IsValid(self.Effect) then
            if self.Effect:IsFinished() and not self.FinishedAfter then
                self.FinishedAfter = api.RealTime() - self.StartedAt
            end
            return true
        end
        local now = api.RealTime()
        self.EndedAfter = now - self.StartedAt
        if self.Mode == "continuous" and now - self.LastSpawnAt >= 0.1 then
            local effect, problem = createParticle(self.Definition, self.Position, self.Angles)
            if effect then
                self.Effect, self.LastSpawnAt = effect, now
                self.Replacements = self.Replacements + 1
                self.FinishedAfter = nil
                return true
            end
            self:Stop()
            return false, problem
        end
        local immediate = now - self.LastSpawnAt < 0.1
        if not immediate then self.Outcome = self.FinishedAfter and "finished" or "ended without observed finished state" end
        self:Stop()
        if immediate then return false, "Prefab particle became invalid immediately: " .. self.Definition.id end
        return false
    end

    function Handle:Status()
        return {
            active = api.IsValid(self.Effect),
            effectName = api.IsValid(self.Effect) and self.Effect:GetEffectName() or nil,
            finished = api.IsValid(self.Effect) and self.Effect:IsFinished() or false,
            soundPlaying = self.Sound ~= nil and self.Sound:IsPlaying() or false,
            soundAnchor = api.IsValid(self.Anchor), replacements = self.Replacements,
            finishedAfter = self.FinishedAfter, endedAfter = self.EndedAfter, outcome = self.Outcome
        }
    end
    return Service
end
