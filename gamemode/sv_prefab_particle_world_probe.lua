return function(contract, createSpawn, createLoot, createCatalog)
    local Probe = {}
    local timerName = "ZM.PrefabParticleWorldProbe.Expiry"
    local anchorId = 987655
    local catalog = createCatalog(file, util, contract)
    local spawn = createSpawn(contract, {
        Vector = Vector, Angle = Angle, IsValid = IsValid, LocalToWorld = LocalToWorld,
        util = util, ents = ents, ResolveLoot = createLoot(ZM_StaticData).Resolve, ResolveParticle = catalog.Resolve
    })

    function Probe:Stop()
        timer.Remove(timerName)
        if self.Runtime then self.Runtime:Cleanup() end
        if IsValid(self.Owner) then self.Owner:ConCommand("zombiesim_prefab_particle_world_fixture_client off") end
        if self.Anchor then self.Anchor.valid = false end
        self.Owner, self.Runtime, self.Anchor = nil, nil, nil
    end

    function Probe:Start(target)
        if not ZM_PrefabEditor:IsParticipant(target) or ZM_PrefabEditor:IsFixtureMap()
            or not target.ZM_PrefabEditorOrigin or target.ZM_PersistentStateLoaded == true
            or ZM_World.ActiveProfile ~= "preview" then
            return false, "The sole preview editor owner and no loaded survivor are required."
        end
        if IsValid(self.Owner) then return false, "The particle world probe is already active." end
        local anchor = { valid = true, origin = target.ZM_PrefabEditorOrigin }
        function anchor:IsValid() return self.valid end
        function anchor:GetPos() return self.origin end
        function anchor:GetAngles() return Angle(0, 0, 0) end
        function anchor:MapCreationID() return anchorId end
        function anchor:DeleteOnRemove() end
        local document = {
            schemaVersion = 1, id = "particle_probe", name = "Particle probe", description = "", tags = {}, props = {},
            particles = {
                { particleId = "continuous", effect = "steam", position = { x = -140, y = 0, z = 16 },
                    angles = { p = 0, y = 0, r = 0 }, mode = "continuous", overlap = true },
                { particleId = "burst_overlap", effect = "steam", position = { x = 0, y = 0, z = 16 },
                    angles = { p = 0, y = 0, r = 0 }, mode = "triggered", overlap = true },
                { particleId = "burst_restart", effect = "steam", position = { x = 140, y = 0, z = 16 },
                    angles = { p = 0, y = 0, r = 0 }, mode = "triggered", overlap = false }
            }
        }
        local entities, problem = spawn.Create(document, anchor)
        if not entities then anchor.valid = false return false, problem end
        local runtime = setmetatable({ Instances = {
            [anchorId] = { id = document.id, entities = entities, anchor = anchor }
        } }, { __index = ZM_Prefabs })
        self.Owner, self.Runtime, self.Anchor = target, runtime, anchor
        target:ConCommand("zombiesim_prefab_particle_world_fixture_client on")
        timer.Create(timerName, 300, 1, function() Probe:Stop() end)
        return true
    end

    hook.Add("PlayerDisconnected", "ZM.PrefabParticleWorldProbe", function(target)
        if target == Probe.Owner then Probe:Stop() end
    end)
    hook.Add("PreCleanupMap", "ZM.PrefabParticleWorldProbe", function() Probe:Stop() end)
    hook.Add("ShutDown", "ZM.PrefabParticleWorldProbe", function() Probe:Stop() end)

    ZM_Util.RegisterCommands({
        zombiesim_prefab_particle_world_probe = "Tests isolated server-owned prefab particle playback."
    }, function(caller, command, arguments)
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        local action = arguments[1] or ""
        if action == "start" then return Probe:Start(target) end
        if action == "stop" then
            if not ZM_PrefabEditor:IsOwner(target) then return false, "Only the editor owner can stop this probe." end
            Probe:Stop()
            return true
        end
        if action == "trigger" then
            if not ZM_PrefabEditor:IsParticipant(target) or target ~= Probe.Owner or not Probe.Runtime then
                return false, "The active particle probe owner is required."
            end
            local id = arguments[2]
            if id ~= "burst_overlap" and id ~= "burst_restart" then
                return false, "Use burst_overlap or burst_restart."
            end
            return Probe.Runtime:TriggerParticle(Probe.Anchor, id)
        end
        if action == "status" then
            if not ZM_PrefabEditor:IsParticipant(target) then return false, "The editor owner is required." end
            if ZM_DevConsole and ZM_DevConsole.Report then
                ZM_DevConsole:Report("prefabParticleWorldProbe", { active = target == Probe.Owner, anchorId = anchorId })
            end
            return true
        end
        return false, "Use start, trigger, stop or status."
    end)
end
