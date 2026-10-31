local Probe = {}
local timerName = "ZM.PrefabParticleProbe.Expiry"
local statusSequence = 0

function Probe:Stop()
    timer.Remove(timerName)
    if IsValid(self.Owner) then self.Owner:ConCommand("zombiesim_dev_prefab_particle_client off") end
    self.Owner = nil
end

function Probe:Start(target, mode)
    if not ZM_PrefabEditor:IsParticipant(target) or ZM_PrefabEditor:IsFixtureMap()
        or not target.ZM_PrefabEditorOrigin then
        return false, "The sole prefab-editor owner and a ready workspace are required."
    end
    if IsValid(self.Owner) then return false, "The steam preview is already active." end
    if mode ~= "burst" and mode ~= "loop" then return false, "Use burst or loop steam preview mode." end
    self.Owner = target
    target:ConCommand("zombiesim_dev_prefab_particle_client on " .. mode)
    timer.Create(timerName, 300, 1, function() Probe:Stop() end)
    return true
end

hook.Add("PlayerDisconnected", "ZM.PrefabParticleProbe", function(target)
    if target == Probe.Owner then Probe:Stop() end
end)
hook.Add("PreCleanupMap", "ZM.PrefabParticleProbe", function() Probe:Stop() end)
hook.Add("ShutDown", "ZM.PrefabParticleProbe", function() Probe:Stop() end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_particle_probe = "Starts, stops or reports the isolated editor steam preview."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    local action = arguments[1] or ""
    if action == "start" then return Probe:Start(target, arguments[2] or "burst") end
    if action == "stop" then
        if not ZM_PrefabEditor:IsOwner(target) then return false, "Only the editor owner can stop this preview." end
        Probe:Stop()
        return true
    end
    if action == "status" then
        if not ZM_PrefabEditor:IsParticipant(target) then return false, "The editor owner is required." end
        statusSequence = statusSequence + 1
        local requestId = tostring(os.time()) .. tostring(statusSequence)
        if ZM_DevConsole and ZM_DevConsole.Report then
            ZM_DevConsole:Report("prefabParticleProbe", { owner = target == Probe.Owner, requestId = requestId })
        end
        target:ConCommand("zombiesim_dev_prefab_particle_client status " .. requestId)
        return true
    end
    return false, "Use start, stop or status."
end)
