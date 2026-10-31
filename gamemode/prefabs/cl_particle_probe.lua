return function(api, service)
    local Probe = {}

    function Probe:Stop()
        if self.Instance then
            self.Instance:Stop()
            self.LastStatus = self.Instance:Status()
            self.Instance = nil
        end
    end

    function Probe:Start(mode)
        if not api.Editor:IsActive() or not api.Editor.Origin then
            return false, "Open the prefab editor before starting the steam preview."
        end
        if mode ~= "burst" and mode ~= "loop" then return false, "Use burst or loop steam preview mode." end
        if self.Instance then return false, "The steam preview is already active." end
        local definition, problem = api.Catalog.Resolve("steam")
        if not definition then return false, problem end
        local origin = api.Editor.Origin + api.Vector(0, 0, 16)
        local instance
        instance, problem = service.Create(definition, origin, api.Angle(0, 0, 0),
            mode == "loop" and "continuous" or "triggered")
        if not instance then return false, problem end
        self.Instance, self.Definition, self.Mode = instance, definition, mode
        self.Failure, self.LastStatus = nil, nil
        return true
    end

    function Probe:Status()
        local status = self.Instance and self.Instance:Status() or self.LastStatus
            or { active = false, finished = false, soundPlaying = false, soundAnchor = false }
        status.particle = self.Definition and self.Definition.particleSystem or nil
        status.particleFile = self.Definition and self.Definition.particleFile or nil
        status.sound = self.Definition and self.Definition.sound or nil
        status.error, status.mode = self.Failure, self.Mode
        return status
    end

    api.hook.Add("Think", "ZM.PrefabParticleProbe", function()
        if not api.Editor:IsActive() then
            Probe:Stop()
        elseif Probe.Instance then
            local active, problem = Probe.Instance:Update()
            if not active then
                Probe.LastStatus = Probe.Instance:Status()
                Probe.Instance, Probe.Failure = nil, problem
                if problem then api.ErrorNoHalt("[ZombieSim] Prefab particle preview: " .. problem .. "\n") end
            end
        end
    end)
    api.hook.Add("PreCleanupMap", "ZM.PrefabParticleProbe", function() Probe:Stop() end)
    api.hook.Add("ShutDown", "ZM.PrefabParticleProbe", function() Probe:Stop() end)
    return Probe
end
