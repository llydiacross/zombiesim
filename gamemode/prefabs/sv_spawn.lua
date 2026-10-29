return function(contract, api)
    local Spawn = {}

    local function removeEntities(entities)
        for _, entity in ipairs(entities) do
            if api.IsValid(entity) then entity:Remove() end
        end
    end

    function Spawn.Create(input, anchor)
        if not api.IsValid(anchor) then return nil, "Prefab anchor is unavailable." end
        local document, problem = contract.Validate(input, api.util.IsValidModel)
        if not document then return nil, problem end

        local lootRules = {}
        local anchorId
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
                anchorId = anchor:MapCreationID()
                if type(anchorId) ~= "number" or anchorId < 0 or anchorId ~= math.floor(anchorId) then
                    return nil, "Lootable prefab anchor requires a stable map creation ID."
                end
                lootRules[index] = rule
            end
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
        for _, entity in ipairs(entities) do anchor:DeleteOnRemove(entity) end
        return entities
    end

    function Spawn.Remove(entities)
        removeEntities(entities or {})
    end

    return Spawn
end
