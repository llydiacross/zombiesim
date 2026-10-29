local Probe = {}
local timerName = "ZM.PrefabSpotlightProbe.Expiry"
local statusSequence = 0

function Probe:Stop()
    timer.Remove(timerName)
    if IsValid(self.Entity) then self.Entity:Remove() end
    if IsValid(self.Owner) then self.Owner:ConCommand("zombiesim_dev_prefab_spotlight_client off") end
    self.Entity, self.Owner = nil, nil
end

function Probe:Start(target, mode)
    if not ZM_PrefabEditor:IsParticipant(target) or ZM_PrefabEditor:IsFixtureMap()
        or not target.ZM_PrefabEditorOrigin then
        return false, "The sole prefab-editor owner and a ready workspace are required."
    end
    if mode ~= "normal" and mode ~= "bright" and mode ~= "unshadowed" and mode ~= "compare" then
        return false, "Use normal, bright, unshadowed or compare spotlight mode."
    end
    if IsValid(self.Entity) then return false, "The spotlight preview is already active." end
    local model = "models/props_c17/oildrum001.mdl"
    if not util.IsValidModel(model) or not util.IsValidProp(model) then
        return false, "The spotlight preview prop is unavailable."
    end
    local entity = ents.Create("prop_physics")
    if not IsValid(entity) then return false, "Could not create the spotlight preview prop." end
    entity:SetModel(model)
    entity:SetPos(target.ZM_PrefabEditorOrigin + Vector(80, 0, 0))
    entity:SetAngles(Angle(0, 0, 0))
    entity:Spawn()
    if not IsValid(entity) then return false, "Could not spawn the spotlight preview prop." end
    entity:Activate()
    local physics = entity:GetPhysicsObject()
    if not IsValid(physics) then entity:Remove() return false, "The spotlight preview prop has no physics." end
    physics:EnableMotion(false)
    physics:Sleep()
    self.Entity, self.Owner = entity, target
    target:ConCommand("zombiesim_dev_prefab_spotlight_client on " .. mode)
    timer.Create(timerName, 300, 1, function() Probe:Stop() end)
    return true
end

hook.Add("PlayerDisconnected", "ZM.PrefabSpotlightProbe", function(target)
    if target == Probe.Owner then Probe:Stop() end
end)
hook.Add("PreCleanupMap", "ZM.PrefabSpotlightProbe", function() Probe:Stop() end)
hook.Add("ShutDown", "ZM.PrefabSpotlightProbe", function() Probe:Stop() end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_spotlight_probe = "Starts, stops or reports the isolated editor spotlight preview."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    local action = arguments[1] or ""
    if action == "start" then return Probe:Start(target, arguments[2] or "normal") end
    if action == "stop" then
        if not ZM_PrefabEditor:IsOwner(target) then return false, "Only the editor owner can stop this preview." end
        Probe:Stop()
        return true
    end
    if action == "status" then
        if not ZM_PrefabEditor:IsParticipant(target) then return false, "The editor owner is required." end
        statusSequence = statusSequence + 1
        local requestId = tostring(os.time()) .. tostring(statusSequence)
        local report = { active = IsValid(Probe.Entity), owner = target == Probe.Owner, requestId = requestId }
        if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("prefabSpotlightProbe", report) end
        target:ConCommand("zombiesim_dev_prefab_spotlight_client status " .. requestId)
        return true
    end
    return false, "Use start, stop or status."
end)
