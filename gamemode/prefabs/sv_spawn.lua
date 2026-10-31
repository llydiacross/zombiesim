return function(contract, api)
    local Spawn = {}

    local function removeEntities(entities)
        for _, entity in ipairs(entities) do
            if api.IsValid(entity) then entity:Remove() end
        end
    end

    function Spawn.Create(input, anchor, onReady)
        if not api.IsValid(anchor) then return nil, "Prefab anchor is unavailable." end
        local document, problem = contract.Validate(input, api.util.IsValidModel)
        if not document then return nil, problem end
        if #document.guards > 0 and not api.AllowGuards then
            return nil, "Prefab guard spawning is unavailable in this context."
        end
        if #document.guards > 0 and type(onReady) ~= "function" then
            return nil, "Prefab guard spawning requires a readiness callback."
        end
        local lootRules = {}
        local particleDefinitions = {}
        local guardSettings = {}
        local anchorId
        local function stableAnchorId()
            if anchor.ZM_PrefabInstanceId ~= nil then
                if anchor.ZM_PrefabInstanceId == "world_" .. document.id then return anchor.ZM_PrefabInstanceId end
                return nil
            end
            local id = anchor:MapCreationID()
            if type(id) == "number" and id >= 0 and id == math.floor(id) then return id end
        end
        if #document.lights > 0 or #document.particles > 0 then
            anchorId = stableAnchorId()
            if anchorId == nil then
                return nil, "Prefab lights and particles require a stable map creation ID."
            end
            for index, light in ipairs(document.lights) do
                if #tostring(anchorId) + 1 + #light.lightId > 511 then
                    return nil, "Prefab light " .. index .. " ID exceeds the network string limit."
                end
            end
            for index, particle in ipairs(document.particles) do
                if type(api.ResolveParticle) ~= "function" then return nil, "Prefab particle catalog is unavailable." end
                local definition, particleError = api.ResolveParticle(particle.effect)
                if not definition then return nil, "Prefab particle " .. index .. ": " .. tostring(particleError) end
                if #tostring(anchorId) + 1 + #particle.particleId > 511 or #definition.id > 511 then
                    return nil, "Prefab particle " .. index .. " ID exceeds the network string limit."
                end
                particleDefinitions[index] = definition
            end
        end
        for index, prop in ipairs(document.props) do
            if prop.scale ~= 1 and not api.AllowFixtureScale then
                return nil, "Prefab prop " .. index .. " uses scale " .. tostring(prop.scale)
                    .. "; scaled world collision has not yet been verified."
            end
            if not api.util.IsValidProp(prop.model) then
                return nil, "Prefab prop " .. index .. " has no valid physics model: " .. prop.model
            end
            if prop.lootMode ~= "off" then
                if type(api.ResolveLoot) ~= "function" then return nil, "Prefab loot validation is unavailable." end
                local rule, lootError = api.ResolveLoot(prop)
                if not rule then return nil, "Prefab prop " .. index .. ": " .. tostring(lootError) end
                anchorId = stableAnchorId()
                if anchorId == nil then
                    return nil, "Lootable prefab anchor requires a stable map creation ID."
                end
                lootRules[index] = rule
            end
        end
        for index, guard in ipairs(document.guards) do
            if type(api.ResolveGuard) ~= "function" then return nil, "Prefab guard validation is unavailable." end
            local settings, guardError = api.ResolveGuard(guard)
            if not settings then return nil, "Prefab guard " .. index .. ": " .. tostring(guardError) end
            guardSettings[index] = settings
        end

        local entities = {}
        for index, prop in ipairs(document.props) do
            local position, angles = api.LocalToWorld(
                api.Vector(prop.position.x, prop.position.y, prop.position.z),
                api.Angle(prop.angles.p, prop.angles.y, prop.angles.r), anchor:GetPos(), anchor:GetAngles())
            local entity = api.ents.Create("prop_physics")
            if not api.IsValid(entity) then
                removeEntities(entities)
                return nil, "Could not create prefab prop " .. index .. "."
            end
            entities[#entities + 1] = entity
            entity:SetModel(prop.model)
            entity:SetPos(position)
            entity:SetAngles(angles)
            entity:SetSkin(prop.skin)
            if lootRules[index] then
                entity.ZM_LootSpotKey = "p" .. anchorId .. "_" .. #document.id .. "_" .. document.id .. "_" .. prop.propId
                entity.ZM_PrefabLoot = { rule = lootRules[index], guaranteed = prop.lootMode == "guaranteed" }
            end
            entity:Spawn()
            if not api.IsValid(entity) then
                removeEntities(entities)
                return nil, "Could not spawn prefab prop " .. index .. ": " .. prop.model
            end
            if prop.scale ~= 1 then entity:SetModelScale(prop.scale, 0) end
            entity:Activate()
            local physics = entity:GetPhysicsObject()
            if not api.IsValid(physics) then
                removeEntities(entities)
                return nil, "Prefab prop " .. index .. " has no physics object: " .. prop.model
            end
            physics:EnableMotion(prop.movable)
            if prop.movable then physics:Wake() else physics:Sleep() end
            if api.AllowFixtureScale and prop.scale ~= 1 then
                entity:SetNW2Float("ZM.PrefabFixtureScale", prop.scale)
            end
        end
        for index, light in ipairs(document.lights) do
            local position, angles = api.LocalToWorld(
                api.Vector(light.position.x, light.position.y, light.position.z),
                api.Angle(light.angles.p, light.angles.y, light.angles.r), anchor:GetPos(), anchor:GetAngles())
            local entity = api.ents.Create("zn_prefab_spotlight")
            if not api.IsValid(entity) then
                removeEntities(entities)
                return nil, "Could not create prefab light " .. index .. "."
            end
            entities[#entities + 1] = entity
            entity.ZM_PrefabLight = true
            entity:SetPos(position)
            entity:SetAngles(angles)
            entity:SetPrefabLightId(tostring(anchorId) .. ":" .. light.lightId)
            entity:SetLightColor(api.Vector(light.color.r, light.color.g, light.color.b))
            entity:SetLightBrightness(light.brightness)
            entity:SetLightFov(light.fov)
            entity:SetLightRange(light.range)
            entity:Spawn()
            if not api.IsValid(entity) then
                removeEntities(entities)
                return nil, "Could not spawn prefab light " .. index .. "."
            end
        end
        local particles = {}
        for index, particle in ipairs(document.particles) do
            local position, angles = api.LocalToWorld(
                api.Vector(particle.position.x, particle.position.y, particle.position.z),
                api.Angle(particle.angles.p, particle.angles.y, particle.angles.r), anchor:GetPos(), anchor:GetAngles())
            local id = tostring(anchorId) .. ":" .. particle.particleId
            particles[particle.particleId] = {
                id = id, effect = particleDefinitions[index].id, position = position, angles = angles,
                mode = particle.mode, overlap = particle.overlap
            }
            if particle.mode == "continuous" then
                local entity = api.ents.Create("zn_prefab_particle")
                if not api.IsValid(entity) then
                    removeEntities(entities)
                    return nil, "Could not create prefab particle " .. index .. "."
                end
                entities[#entities + 1] = entity
                entity.ZM_PrefabParticle = true
                entity:SetPos(position)
                entity:SetAngles(angles)
                entity:SetPrefabParticleId(id)
                entity:SetParticleEffectId(particleDefinitions[index].id)
                entity:Spawn()
                if not api.IsValid(entity) then
                    removeEntities(entities)
                    return nil, "Could not spawn prefab particle " .. index .. "."
                end
            end
        end
        local pendingGuards, guardFailure, constructing, closed = 0, nil, true, false
        local function guardReady(index, _, ok, problem)
            if closed then return end
            pendingGuards = pendingGuards - 1
            if not ok then
                guardFailure = "Prefab guard " .. index .. ": " .. tostring(problem)
                closed = true
                removeEntities(entities)
                if not constructing then onReady(false, guardFailure) end
            elseif pendingGuards == 0 and not constructing then
                closed = true
                onReady(true)
            end
        end
        for index, guard in ipairs(document.guards) do
            local position, angles = api.LocalToWorld(
                api.Vector(guard.position.x, guard.position.y, guard.position.z),
                api.Angle(guard.angles.p, guard.angles.y, guard.angles.r), anchor:GetPos(), anchor:GetAngles())
            local entity = api.ents.Create("zn_prefab_guard")
            if not api.IsValid(entity) then
                closed = true
                removeEntities(entities)
                return nil, "Could not create prefab guard " .. index .. "."
            end
            entities[#entities + 1] = entity
            entity.ZM_PrefabGuard = true
            entity.ZM_GuardConfig = guardSettings[index]
            entity:SetPos(position)
            entity:SetAngles(angles)
            pendingGuards = pendingGuards + 1
            local guardIndex = index
            entity.ZM_GuardReadyCallback = function(subject, ok, problem)
                guardReady(guardIndex, subject, ok, problem)
            end
            entity:Spawn()
            if guardFailure then return nil, guardFailure end
            if not api.IsValid(entity) then
                closed = true
                removeEntities(entities)
                return nil, "Could not spawn prefab guard " .. index .. "."
            end
        end
        entities.particles = particles
        for _, entity in ipairs(entities) do anchor:DeleteOnRemove(entity) end
        constructing = false
        return entities, nil, pendingGuards > 0
    end

    function Spawn.Remove(entities)
        removeEntities(entities or {})
    end

    return Spawn
end
