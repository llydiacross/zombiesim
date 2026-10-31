local Contract = include("prefabs/sh_contract.lua")
local PrefabLoot = include("prefabs/sv_loot.lua")(ZM_StaticData)
local ParticleCatalog = include("prefabs/sh_particle_catalog.lua")(file, util, Contract)
local function validateContent(document)
    local ok, problem = PrefabLoot.Validate(document)
    if not ok then return false, problem end
    ok, problem = ParticleCatalog.Validate(document)
    if not ok then return false, problem end
    return ZM_PrefabGuardConfig.ValidateDocument(document)
end
local Catalog = include("prefabs/sv_catalog.lua")(file, util, Contract, util.IsValidModel, validateContent)
local Spawn = include("prefabs/sv_spawn.lua")(Contract, {
    Vector = Vector, Angle = Angle, IsValid = IsValid, LocalToWorld = LocalToWorld, util = util, ents = ents,
    ResolveLoot = PrefabLoot.Resolve, ResolveParticle = ParticleCatalog.Resolve,
    ResolveGuard = ZM_PrefabGuardConfig.PrepareDocumentGuard, AllowGuards = true
})
local FixtureSpawn = include("prefabs/sv_spawn.lua")(Contract, {
    Vector = Vector, Angle = Angle, IsValid = IsValid, LocalToWorld = LocalToWorld, util = util, ents = ents,
    ResolveLoot = PrefabLoot.Resolve, ResolveParticle = ParticleCatalog.Resolve, AllowFixtureScale = true,
    ResolveGuard = ZM_PrefabGuardConfig.PrepareDocumentGuard, AllowGuards = true
})
local FixtureTrace = include("prefabs/sh_fixture_trace.lua")({
    IsValid = IsValid, Vector = Vector, Angle = Angle, LocalToWorld = LocalToWorld,
    util = util, MASK_SOLID = MASK_SOLID
})
ZM_Prefabs = {}
local Prefabs = ZM_Prefabs
local lightStatusSequence = 0
local particleStatusSequence = 0
local particleTriggerMessage = "ZM.PrefabParticle.Trigger"
local particleStopMessage = "ZM.PrefabParticle.Stop"
util.AddNetworkString(particleTriggerMessage)
util.AddNetworkString(particleStopMessage)

local function baseMap(path)
    return string.lower(string.match(path or "", "([^/]+)$") or "")
end

local function stopTriggeredParticles(instance)
    for _, particle in pairs(instance.entities.particles or {}) do
        if particle.mode == "triggered" then
            net.Start(particleStopMessage)
                net.WriteString(particle.id)
            net.Broadcast()
        end
    end
end

function Prefabs:Cleanup()
    local instances = self.Instances or {}
    self.Instances, self.CellId, self.Profile, self.Failure, self.Pending = nil, nil, nil, nil, nil
    for _, instance in pairs(instances) do
        stopTriggeredParticles(instance)
        Spawn.Remove(instance.entities)
        if instance.worldPlacement and IsValid(instance.anchor) then instance.anchor:Remove() end
    end
end

function Prefabs:RemoveAnchor(id, anchor)
    local instance = self.Instances and self.Instances[id]
    if not instance or instance.anchor ~= anchor then return end
    self.Instances[id] = nil
    if instance.pending then self.Pending = self.Pending - 1 end
    stopTriggeredParticles(instance)
    Spawn.Remove(instance.entities)
    if instance.pending and self.Pending == 0 then self:ResumeConnectedPlayers() end
end

function Prefabs:GetStatus()
    local anchors, props, lights, particles, guards = 0, 0, 0, 0, 0
    local instances = {}
    for anchorId, instance in pairs(self.Instances or {}) do
        anchors = anchors + 1
        instances[#instances + 1] = { anchorId = anchorId, prefabId = instance.id }
        for _, entity in ipairs(instance.entities) do
            if IsValid(entity) then
                if entity.ZM_PrefabGuard then guards = guards + 1
                elseif entity.ZM_PrefabLight then lights = lights + 1
                elseif not entity.ZM_PrefabParticle then props = props + 1 end
            end
        end
        for _ in pairs(instance.entities.particles or {}) do particles = particles + 1 end
    end
    return { ready = self.Ready == true, map = game.GetMap(), profile = self.Profile or ZM_World.ActiveProfile,
        cellId = self.CellId, anchors = anchors, props = props, lights = lights, particles = particles, guards = guards,
        pending = self.Pending or 0,
        instances = instances, error = self.Failure }
end

function Prefabs:TriggerParticle(anchor, particleId)
    if not IsValid(anchor) or not Contract.IsValidId(particleId) then return false, "Invalid prefab anchor or particle ID." end
    local anchorId = anchor.ZM_PrefabInstanceId or anchor:MapCreationID()
    local instance = self.Instances and self.Instances[anchorId]
    if instance and instance.pending then return false, "The prefab anchor is still initializing." end
    local particle = instance and instance.entities.particles and instance.entities.particles[particleId]
    if not particle then return false, "The prefab anchor has no particle with ID '" .. particleId .. "'." end
    if particle.mode ~= "triggered" then return false, "Prefab particle '" .. particleId .. "' is not triggered." end
    net.Start(particleTriggerMessage)
        net.WriteString(particle.id)
        net.WriteString(particle.effect)
        net.WriteDouble(particle.position.x)
        net.WriteDouble(particle.position.y)
        net.WriteDouble(particle.position.z)
        net.WriteDouble(particle.angles.p)
        net.WriteDouble(particle.angles.y)
        net.WriteDouble(particle.angles.r)
        net.WriteBool(particle.overlap)
    net.Broadcast()
    return true
end

function Prefabs:OnPlayerReady(target)
    if not IsValid(target) or target.ZM_PersistentStateLoaded ~= true then return true end
    if not self.Ready then return nil, "Prefab map initialization is pending." end
    if type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" then return true end
    local cell, cellError = target:GetWorldCell()
    if not cell then return false, cellError or "Prefab spawning requires a world cell." end
    if ZM_SafeZones:IsSafeZoneCell(cell) or baseMap(ZM_World:GetMapPath(cell)) ~= baseMap(game.GetMap()) then return true end
    return self:SpawnForCell(cell.id)
end

function Prefabs:CreateWorldAnchors(documents, cellId)
    local cell = ZM_World:GetCellById(cellId)
    if not cell then return nil, "World prefab placement requires a valid logical cell." end
    local x, y = ZM_World:GetWorldCoordinates(cell)
    local selected = Catalog.ForWorldCell(documents, ZM_World.ActiveProfile, x, y)
    if #selected == 0 then return {} end
    local bounds = ZM_World:GetCellBounds()
    local placements = {}
    for _, document in ipairs(selected) do
        local placement = document.worldPlacement
        local tx, ty = placement.tileX * bounds.tileSize, placement.tileY * bounds.tileSize
        local trace = util.TraceLine({
            start = Vector(tx, ty, bounds.playableCeiling - 1),
            endpos = Vector(tx, ty, -bounds.playableCeiling), filter = player.GetHumans(), mask = MASK_SOLID
        })
        if not trace.Hit or trace.HitSky or trace.StartSolid or not trace.HitNormal or trace.HitNormal.z <= 0
            or not trace.HitPos then
            return nil, "World prefab '" .. document.id .. "' has no solid surface at its tile centre."
        end
        placements[#placements + 1] = { document = document,
            position = trace.HitPos + Vector(placement.offset.x, placement.offset.y, placement.offset.z),
            angles = Angle(placement.angles.p, placement.angles.y, placement.angles.r) }
    end
    local anchors = {}
    for _, placement in ipairs(placements) do
        local anchor = ents.Create("zn_prefab_anchor")
        if not IsValid(anchor) then
            for _, created in ipairs(anchors) do created:Remove() end
            return nil, "Could not create world prefab anchor for '" .. placement.document.id .. "'."
        end
        anchors[#anchors + 1] = anchor
        anchor.ZM_PrefabInstanceId = "world_" .. placement.document.id
        anchor.ZM_WorldPrefabDocument = placement.document
        anchor:SetPos(placement.position)
        anchor:SetAngles(placement.angles)
        anchor:Spawn()
        if not IsValid(anchor) then
            for _, created in ipairs(anchors) do if IsValid(created) then created:Remove() end end
            return nil, "Could not spawn world prefab anchor for '" .. placement.document.id .. "'."
        end
    end
    return anchors
end

function Prefabs:SpawnForCell(cellId, fixture)
    if fixture and not ZM_PrefabEditor:IsFixtureMap() then
        return false, "Experimental scale is restricted to the isolated prefab fixture."
    end
    if self.Instances then
        if self.CellId ~= cellId or self.Profile ~= ZM_World.ActiveProfile then
            return false, "Prefab world cell differs from the active map session."
        end
        if self.Pending > 0 then return nil, "Prefab guard initialization is pending." end
        return self.Failure == nil, self.Failure
    end
    local anchors = ents.FindByClass("zn_prefab_anchor")
    local documents, problem = Catalog.Load()
    if not documents then self.Failure = problem return false, problem end
    if not fixture then
        local worldAnchors, placementError = self:CreateWorldAnchors(documents, cellId)
        if not worldAnchors then self.Failure = placementError return false, placementError end
        for _, anchor in ipairs(worldAnchors) do anchors[#anchors + 1] = anchor end
    end
    self.Failure = nil
    self.Instances, self.CellId, self.Profile, self.Pending = {}, cellId, ZM_World.ActiveProfile, 0
    local data = ZM_World:GetData()
    for _, anchor in ipairs(anchors) do
        local keys = anchor.ZM_Config or {}
        if keys.instance_local ~= "1" or keys.zm_instance_transformed == "1" then
            local id = anchor.ZM_PrefabInstanceId or anchor:MapCreationID()
            local tags = {}
            for tag in string.gmatch(keys.prefab_tags or "", "[^,]+") do
                tags[#tags + 1] = string.Trim(tag)
            end
            local document, selectionError = anchor.ZM_WorldPrefabDocument, nil
            if not document then
                document, selectionError = Catalog.Select(documents, tags, self.Profile,
                    data and data.world and data.world.seed, cellId, id)
            end
            local entities, spawnError, pending
            local instance
            if document then
                entities, spawnError, pending = (fixture and FixtureSpawn or Spawn).Create(document, anchor,
                    function(ok, problem)
                        if not Prefabs.Instances or Prefabs.Instances[id] ~= instance or not instance.pending then return end
                        instance.pending = false
                        Prefabs.Pending = Prefabs.Pending - 1
                        if not ok then
                            stopTriggeredParticles(instance)
                            Prefabs.Instances[id] = nil
                            Prefabs.Failure = "Prefab anchor " .. tostring(id) .. ": " .. tostring(problem)
                            ErrorNoHalt("[ZombieSim] " .. Prefabs.Failure .. "\n")
                            if instance.worldPlacement and IsValid(anchor) then anchor:Remove() end
                        end
                        if Prefabs.Pending == 0 then Prefabs:ResumeConnectedPlayers() end
                    end)
            end
            if not entities then
                self.Failure = "Prefab anchor " .. tostring(id) .. ": " .. tostring(selectionError or spawnError)
                ErrorNoHalt("[ZombieSim] " .. self.Failure .. "\n")
                if anchor.ZM_WorldPrefabDocument and IsValid(anchor) then anchor:Remove() end
            else
                instance = { id = document.id, entities = entities, anchor = anchor, pending = pending == true,
                    worldPlacement = anchor.ZM_WorldPrefabDocument ~= nil }
                self.Instances[id] = instance
                if instance.pending then self.Pending = self.Pending + 1 end
                anchor:CallOnRemove("ZM.Prefabs.ParticleCleanup", function(removed)
                    Prefabs:RemoveAnchor(id, removed)
                end)
            end
        end
    end
    if self.Pending > 0 then return nil, "Prefab guard initialization is pending." end
    return self.Failure == nil, self.Failure
end

function Prefabs:ResumeConnectedPlayers()
    for _, target in ipairs(player.GetHumans()) do
        local ok, problem = self:OnPlayerReady(target)
        if ok == false then ErrorNoHalt("[ZombieSim] " .. tostring(problem) .. "\n") end
        if ok ~= nil and IsValid(target) and target.ZM_PersistentStateLoaded == true then
            ZM_Loading:Step(target, ok and "Prepared prefab props" or "Prefab props unavailable",
                ok and "ok" or "warn")
            ZM_LootSpots:OnPlayerReady(target)
            ZM_Loading:Step(target, "Prepared loot spots")
        elseif ok == nil and IsValid(target) and target.ZM_PersistentStateLoaded == true then
            ZM_Loading:Step(target, "Prefab guard initialization is pending.", "info")
        end
    end
end

local function prepareConnectedPlayers()
    Prefabs.Ready = true
    Prefabs:ResumeConnectedPlayers()
end

hook.Add("InitPostEntity", "ZM.Prefabs.Ready", function()
    timer.Simple(0, prepareConnectedPlayers)
end)
hook.Add("PreCleanupMap", "ZM.Prefabs.Cleanup", function()
    Prefabs.Ready = false
    Prefabs:Cleanup()
end)
hook.Add("PostCleanupMap", "ZM.Prefabs.Restore", function()
    timer.Simple(0, prepareConnectedPlayers)
end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_status = "Reports loaded prefab anchors and surviving props and lights.",
    zombiesim_prefab_lights_status = "Requests an admin's client prefab-light diagnostics.",
    zombiesim_prefab_particles_status = "Requests an admin's client prefab-particle diagnostics.",
    zombiesim_prefab_fixture_spawn = "Spawns the isolated prefab fixture using a synthetic cell.",
    zombiesim_prefab_fixture_particle_trigger = "Fires one particle input on an isolated fixture anchor.",
    zombiesim_prefab_fixture_trace = "Compares server and client traces on the isolated prefab fixture."
}, function(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command) then return false, "Admin access required." end
    if command == "zombiesim_prefab_particles_status" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not IsValid(target) or not target:IsAdmin() then return false, "A connected admin is required." end
        particleStatusSequence = particleStatusSequence + 1
        local requestId = tostring(os.time()) .. tostring(particleStatusSequence)
        if ZM_DevConsole and ZM_DevConsole.Report then
            ZM_DevConsole:Report("prefabParticlesStatus", { requestId = requestId })
        end
        target:ConCommand("zombiesim_prefab_particles_status_client " .. requestId)
        return true
    elseif command == "zombiesim_prefab_lights_status" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not IsValid(target) or not target:IsAdmin() then return false, "A connected admin is required." end
        lightStatusSequence = lightStatusSequence + 1
        local requestId = tostring(os.time()) .. tostring(lightStatusSequence)
        if ZM_DevConsole and ZM_DevConsole.Report then
            ZM_DevConsole:Report("prefabLightStatus", { requestId = requestId })
        end
        target:ConCommand("zombiesim_prefab_lights_status_client " .. requestId)
        return true
    elseif command == "zombiesim_prefab_fixture_particle_trigger" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not ZM_PrefabEditor:IsFixtureMap() or not ZM_PrefabEditor:IsParticipant(target)
            or target.ZM_PersistentStateLoaded == true or ZM_World.ActiveProfile ~= "preview" then
            return false, "The isolated prefab fixture and its sole owner are required."
        end
        local id = tonumber(arguments and arguments[1])
        local particleId = arguments and arguments[2]
        local instance = id and Prefabs.Instances and Prefabs.Instances[id]
        local particle = instance and instance.entities.particles and instance.entities.particles[particleId]
        if not instance or not IsValid(instance.anchor) or not particle or particle.mode ~= "triggered" then
            return false, "Choose an active fixture anchor and triggered particle ID."
        end
        instance.anchor:Fire("TriggerParticle", particleId, 0)
        return true
    elseif command == "zombiesim_prefab_fixture_spawn" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not Prefabs.Ready or not ZM_PrefabEditor:IsFixtureMap()
            or not ZM_PrefabEditor:IsParticipant(target) or target.ZM_PersistentStateLoaded == true
            or ZM_World.ActiveProfile ~= "preview" then
            return false, "The isolated prefab fixture requires its sole preview admin and no loaded survivor."
        end
        local ok, problem = Prefabs:SpawnForCell(0, true)
        if ok == nil then
            if ZM_DevConsole and ZM_DevConsole.Report then
                ZM_DevConsole:Report("prefabFixtureSpawn", { state = "pending", pending = Prefabs.Pending })
            end
            return true
        end
        return ok, problem
    elseif command == "zombiesim_prefab_fixture_trace" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not ZM_PrefabEditor:IsFixtureMap() or not ZM_PrefabEditor:IsParticipant(target)
            or target.ZM_PersistentStateLoaded == true or ZM_World.ActiveProfile ~= "preview"
            or not Prefabs.Instances then
            return false, "The isolated prefab fixture and its owner are required for collision traces."
        end
        local mode = arguments and arguments[1] or ""
        if mode ~= "" and mode ~= "activate_client" then return false, "Invalid fixture trace mode." end
        local samples, errors = {}, {}
        for _, instance in pairs(Prefabs.Instances) do
            for _, entity in ipairs(instance.entities) do
                local sample, problem = FixtureTrace.Sample(entity)
                if sample then samples[#samples + 1] = sample else errors[#errors + 1] = problem end
            end
        end
        local expectedCount = #samples + #errors
        if expectedCount == 0 then return false, "The isolated prefab fixture has no props to trace." end
        local requestId = tostring(math.floor(CurTime() * 1000))
        if ZM_DevConsole and ZM_DevConsole.Report then
            ZM_DevConsole:Report("prefabFixtureTrace", { requestId = requestId, mode = mode, samples = samples, errors = errors })
        end
        target:ConCommand("zombiesim_dev_prefab_fixture_trace_client " .. requestId .. " "
            .. (mode ~= "" and mode or "compare") .. " " .. expectedCount)
        if #errors > 0 then return false, table.concat(errors, " | ") end
        return true
    end
    local status = Prefabs:GetStatus()
    if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("prefabs", status) end
    ZM_Util.Reply(caller, string.format("Prefabs: %d anchors, %d props, %d lights, %d particles; %s.",
        status.anchors, status.props, status.lights, status.particles, status.error or "no errors"))
    return true
end)
