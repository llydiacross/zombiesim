return function(api, catalog, service)
    local Preview = { Continuous = {}, Bursts = {}, Errors = {}, NextRetry = {} }

    local function coordinates(particle)
        return api.Vector(particle.position.x, particle.position.y, particle.position.z),
            api.Angle(particle.angles.p, particle.angles.y, particle.angles.r)
    end

    local function sameTransform(left, particle, origin)
        local position, angles = particle.position, particle.angles
        return left.x == origin.x + position.x and left.y == origin.y + position.y and left.z == origin.z + position.z
            and left.p == angles.p and left.yaw == angles.y and left.r == angles.r
    end

    local function transform(particle, origin)
        return { x = origin.x + particle.position.x, y = origin.y + particle.position.y, z = origin.z + particle.position.z,
            p = particle.angles.p, yaw = particle.angles.y, r = particle.angles.r }
    end

    local function findParticle(editor, id)
        for _, particle in ipairs(editor.Document.particles) do
            if particle.particleId == id then return particle end
        end
    end

    function Preview:Report(id, problem)
        if self.Errors[id] ~= problem then
            local editor = api.GetEditor()
            if editor then editor:Message("Particle " .. id .. ": " .. problem, true)
            else api.ErrorNoHalt("[ZombieSim] Prefab particle preview: " .. problem .. "\n") end
        end
        self.Errors[id], self.NextRetry[id] = problem, api.RealTime() + 2
    end

    function Preview:Clear()
        for _, state in pairs(self.Continuous) do state.handle:Stop() end
        for _, bursts in pairs(self.Bursts) do
            for _, burst in ipairs(bursts) do burst.handle:Stop() end
        end
        self.Continuous, self.Bursts, self.Errors, self.NextRetry = {}, {}, {}, {}
    end

    function Preview:Trigger(id)
        local editor = api.GetEditor()
        if not editor or not editor:IsActive() then return false, "The prefab editor is not active." end
        local particle = findParticle(editor, id)
        if not particle or particle.mode ~= "triggered" then return false, "Select a triggered particle to preview it." end
        local definition, problem = catalog.Resolve(particle.effect)
        if not definition then return false, problem end
        local bursts = self.Bursts[id] or {}
        if not particle.overlap or (bursts.effect and bursts.effect ~= particle.effect) then
            for _, burst in ipairs(bursts) do burst.handle:Stop() end
            bursts = {}
            self.Bursts[id] = nil
        end
        local position, angles = coordinates(particle)
        local origin = editor:GetPreviewOrigin()
        local handle
        handle, problem = service.Create(definition, origin + position, angles, "triggered")
        if not handle then return false, problem end
        bursts.effect = particle.effect
        bursts[#bursts + 1] = { handle = handle, position = position, angles = angles,
            origin = { x = origin.x, y = origin.y, z = origin.z } }
        self.Bursts[id] = bursts
        return true
    end

    function Preview:Think()
        local editor = api.GetEditor()
        if not editor or not editor:IsActive() then
            if next(self.Continuous) or next(self.Bursts) or next(self.Errors) then self:Clear() end
            return
        end
        local seen = {}
        local origin = editor:GetPreviewOrigin()
        for _, particle in ipairs(editor.Document.particles) do
            local id = particle.particleId
            seen[id] = particle
            local state = self.Continuous[id]
            if state and (particle.mode ~= "continuous" or state.effect ~= particle.effect) then
                state.handle:Stop()
                self.Continuous[id], state = nil, nil
            end
            if particle.mode == "continuous" and not state and api.RealTime() >= (self.NextRetry[id] or 0) then
                local definition, problem = catalog.Resolve(particle.effect)
                local position, angles = coordinates(particle)
                local handle
                if definition then handle, problem = service.Create(definition, origin + position, angles, "continuous") end
                if handle then
                    state = { handle = handle, effect = particle.effect, transform = transform(particle, origin) }
                    self.Continuous[id], self.Errors[id], self.NextRetry[id] = state, nil, nil
                else
                    self:Report(id, problem)
                end
            end
            if state then
                if not sameTransform(state.transform, particle, origin) then
                    local position, angles = coordinates(particle)
                    state.handle:Move(origin + position, angles)
                    state.transform = transform(particle, origin)
                end
                local active, problem = state.handle:Update()
                if not active then
                    self.Continuous[id] = nil
                    if problem then self:Report(id, problem) end
                end
            end
        end
        for id, state in pairs(self.Continuous) do
            if not seen[id] then state.handle:Stop(); self.Continuous[id] = nil end
        end
        for id, bursts in pairs(self.Bursts) do
            if not seen[id] or seen[id].mode ~= "triggered" or seen[id].effect ~= bursts.effect then
                for _, burst in ipairs(bursts) do burst.handle:Stop() end
                self.Bursts[id] = nil
            else
                for index = #bursts, 1, -1 do
                    local burst = bursts[index]
                    if burst.origin.x ~= origin.x or burst.origin.y ~= origin.y or burst.origin.z ~= origin.z then
                        burst.handle:Move(origin + burst.position, burst.angles)
                        burst.origin = { x = origin.x, y = origin.y, z = origin.z }
                    end
                    local active, problem = burst.handle:Update()
                    if not active then
                        table.remove(bursts, index)
                        if problem then self:Report(id, problem) end
                    end
                end
                if #bursts == 0 then self.Bursts[id] = nil end
            end
        end
        for id in pairs(self.Errors) do
            if not seen[id] then self.Errors[id], self.NextRetry[id] = nil, nil end
        end
    end

    function Preview:Status()
        local continuous, bursts = 0, 0
        for _ in pairs(self.Continuous) do continuous = continuous + 1 end
        for _, instances in pairs(self.Bursts) do bursts = bursts + #instances end
        return { continuous = continuous, bursts = bursts, errors = self.Errors }
    end

    api.hook.Add("Think", "ZM.PrefabParticlePreview", function() Preview:Think() end)
    api.hook.Add("PreCleanupMap", "ZM.PrefabParticlePreview", function() Preview:Clear() end)
    api.hook.Add("ShutDown", "ZM.PrefabParticlePreview", function() Preview:Clear() end)
    return Preview
end
