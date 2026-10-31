return function(api, catalog, service)
    local World = { Continuous = {}, Bursts = {}, Errors = {}, NextRetry = {}, NextScan = 0, Pending = 0,
        FixtureActive = false }

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    local function validTransform(position, angles)
        return api.IsVector(position) and api.IsAngle(angles)
            and finite(position.x) and finite(position.y) and finite(position.z)
            and finite(angles.p) and finite(angles.y) and finite(angles.r)
    end

    local function snapshot(position, angles)
        return { x = position.x, y = position.y, z = position.z, p = angles.p, yaw = angles.y, r = angles.r }
    end

    local function changed(previous, position, angles)
        return previous.x ~= position.x or previous.y ~= position.y or previous.z ~= position.z
            or previous.p ~= angles.p or previous.yaw ~= angles.y or previous.r ~= angles.r
    end

    function World:Report(id, problem)
        if self.Errors[id] ~= problem then
            api.ErrorNoHalt("[ZombieSim] Prefab particle " .. tostring(id) .. ": " .. tostring(problem) .. "\n")
        end
        self.Errors[id], self.NextRetry[id] = problem, api.RealTime() + 2
    end

    function World:Clear()
        for _, state in pairs(self.Continuous) do state.handle:Stop() end
        for _, bursts in pairs(self.Bursts) do for _, handle in ipairs(bursts) do handle:Stop() end end
        self.Continuous, self.Bursts, self.Errors, self.NextRetry = {}, {}, {}, {}
        self.NextScan, self.Pending = 0, 0
        self.FixtureActive = false
    end

    function World:SetFixtureActive(active)
        if active then self.FixtureActive = true else self:Clear() end
    end

    function World:Trigger(id, effectId, position, angles, overlap)
        if type(id) ~= "string" or not string.match(id, "^%d+:[a-z0-9][a-z0-9_%-]*$")
            or type(effectId) ~= "string" or type(overlap) ~= "boolean" or not validTransform(position, angles) then
            return false, "Invalid triggered prefab particle event."
        end
        local definition, problem = catalog.Resolve(effectId)
        if not definition then return false, problem end
        local bursts = self.Bursts[id] or {}
        if not overlap or (bursts.effect and bursts.effect ~= effectId) then
            for _, handle in ipairs(bursts) do handle:Stop() end
            bursts = {}
            self.Bursts[id] = nil
        end
        local handle
        handle, problem = service.Create(definition, position, angles, "triggered")
        if not handle then return false, problem end
        bursts.effect = effectId
        bursts[#bursts + 1] = handle
        self.Bursts[id] = bursts
        return true
    end

    function World:StopBursts(id)
        local bursts = self.Bursts[id]
        if not bursts then return end
        for _, handle in ipairs(bursts) do handle:Stop() end
        self.Bursts[id] = nil
    end

    function World:Scan()
        local seen, pending = {}, 0
        for _, entity in ipairs(api.FindEntities()) do
            if api.IsValid(entity) then
                local id, effectId = entity:GetPrefabParticleId(), entity:GetParticleEffectId()
                if id == "" or effectId == "" then
                    pending = pending + 1
                elseif seen[id] then
                    self:Report(id, "Duplicate networked particle ID.")
                else
                    seen[id] = true
                    local state = self.Continuous[id]
                    if state and (state.entity ~= entity or state.effect ~= effectId) then
                        state.handle:Stop()
                        self.Continuous[id], state = nil, nil
                    end
                    local position, angles = entity:GetPos(), entity:GetAngles()
                    if not validTransform(position, angles) then
                        if state then state.handle:Stop(); self.Continuous[id], state = nil, nil end
                        self:Report(id, "Invalid networked particle transform.")
                    elseif not state and api.RealTime() >= (self.NextRetry[id] or 0) then
                        local definition, problem = catalog.Resolve(effectId)
                        local handle
                        if definition then handle, problem = service.Create(definition, position, angles, "continuous") end
                        if handle then
                            state = { entity = entity, effect = effectId, handle = handle, transform = snapshot(position, angles) }
                            self.Continuous[id], self.Errors[id], self.NextRetry[id] = state, nil, nil
                        else
                            self:Report(id, problem)
                        end
                    elseif state and changed(state.transform, position, angles) then
                        state.handle:Move(position, angles)
                        state.transform = snapshot(position, angles)
                    end
                end
            end
        end
        self.Pending = pending
        for id, state in pairs(self.Continuous) do
            if not seen[id] then state.handle:Stop(); self.Continuous[id] = nil end
        end
        for id in pairs(self.Errors) do
            if not seen[id] then self.Errors[id], self.NextRetry[id] = nil, nil end
        end
    end

    function World:Think()
        local editor = api.GetEditor()
        if editor and editor:IsActive() and not self.FixtureActive then
            if next(self.Continuous) or next(self.Bursts) or next(self.Errors) then self:Clear() end
            return
        end
        local now = api.RealTime()
        if now >= self.NextScan then
            self.NextScan = now + 0.25
            self:Scan()
        end
        for id, state in pairs(self.Continuous) do
            local active, problem = state.handle:Update()
            if not active then
                self.Continuous[id] = nil
                self:Report(id, problem or "Continuous particle stopped without an error.")
            end
        end
        for id, bursts in pairs(self.Bursts) do
            for index = #bursts, 1, -1 do
                local active, problem = bursts[index]:Update()
                if not active then
                    table.remove(bursts, index)
                    if problem then self:Report(id, problem) end
                end
            end
            if #bursts == 0 then self.Bursts[id] = nil end
        end
    end

    function World:Status()
        local continuous, bursts = 0, 0
        for _ in pairs(self.Continuous) do continuous = continuous + 1 end
        for _, handles in pairs(self.Bursts) do bursts = bursts + #handles end
        return { continuous = continuous, bursts = bursts, pending = self.Pending, errors = self.Errors,
            fixture = self.FixtureActive }
    end

    api.hook.Add("Think", "ZM.PrefabParticleWorld", function() World:Think() end)
    api.hook.Add("PreCleanupMap", "ZM.PrefabParticleWorld", function() World:Clear() end)
    api.hook.Add("ShutDown", "ZM.PrefabParticleWorld", function() World:Clear() end)
    return World
end
