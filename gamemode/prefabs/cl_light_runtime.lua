return function(api, pool)
    local Runtime = { Entities = {}, NextScan = 0, NextUpdate = 0, Error = nil, Pending = 0 }

    function Runtime:Clear()
        pool:Clear()
        self.Entities, self.NextScan, self.NextUpdate, self.Error, self.Pending = {}, 0, 0, nil, 0
    end

    function Runtime:Render(depth, skybox)
        if depth or skybox then return end
        local editor = api.GetEditor()
        if editor and editor:IsActive() then self:Clear() return end
        local now = api.CurTime()
        if now < self.NextUpdate then return end
        self.NextUpdate = now + 1 / 15
        if now >= self.NextScan then
            self.Entities = api.FindEntities()
            self.NextScan = now + 0.25
        end
        local candidates, pending = {}, 0
        for _, entity in ipairs(self.Entities) do
            if api.IsValid(entity) then
                local id = entity:GetPrefabLightId()
                if id == "" then
                    pending = pending + 1
                else
                    local color = entity:GetLightColor()
                    candidates[#candidates + 1] = {
                        id = id, position = entity:GetPos(), angles = entity:GetAngles(),
                        color = { r = color.x, g = color.y, b = color.z },
                        brightness = entity:GetLightBrightness(), fov = entity:GetLightFov(),
                        range = entity:GetLightRange()
                    }
                end
            end
        end
        self.Pending = pending
        local ok, problem = pool:Reconcile(api.EyePos(), candidates, true)
        if not ok then
            if self.Error ~= problem then api.ErrorNoHalt("[ZombieSim] Prefab spotlights: " .. tostring(problem) .. "\n") end
            self.Error = problem
            return
        end
        self.Error = nil
    end

    function Runtime:Status()
        local status = pool:Status()
        status.error, status.pending, status.networked = self.Error, self.Pending, #self.Entities
        return status
    end

    api.hook.Add("PreDrawOpaqueRenderables", "ZM.PrefabWorldLights", function(depth, skybox)
        Runtime:Render(depth, skybox)
    end)
    api.hook.Add("PreCleanupMap", "ZM.PrefabWorldLights", function() Runtime:Clear() end)
    api.hook.Add("ShutDown", "ZM.PrefabWorldLights", function() Runtime:Clear() end)
    return Runtime
end
