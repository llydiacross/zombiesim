return function(contract, createSpawn)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { entities = {}, transforms = {}, invalidModel = nil, failCreate = nil, failPhysics = nil }
        local api = {
            Vector = function(x, y, z) return { x = x, y = y, z = z } end,
            Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            IsValid = function(value) return type(value) == "table" and value.valid ~= false end,
            util = {
                IsValidModel = function(model) return model == "models/props_c17/oildrum001.mdl" end,
                IsValidProp = function(model) return model ~= state.invalidModel end
            },
            ResolveLoot = function(prop)
                if prop.lootGroup == "invalid" then return nil, "invalid group" end
                return { entries = { "fixture" }, activationChance = 0.4 }
            end,
            ents = {}
        }
        api.LocalToWorld = function(position, angles, origin, orientation)
            state.transforms[#state.transforms + 1] = { position, angles, origin, orientation }
            local radians = orientation.y * math.pi / 180
            return { x = origin.x + position.x * math.cos(radians) - position.y * math.sin(radians),
                y = origin.y + position.x * math.sin(radians) + position.y * math.cos(radians),
                z = origin.z + position.z }, { p = angles.p, y = angles.y + orientation.y, r = angles.r }
        end
        function api.ents.Create(class)
            assert(class == "prop_physics")
            local index = #state.entities + 1
            if state.failCreate == index then return nil end
            local physics = { valid = state.failPhysics ~= index }
            function physics:EnableMotion(value) self.motion = value end
            function physics:Wake() self.awake = true end
            function physics:Sleep() self.sleeping = true end
            local entity = { valid = true, physics = physics }
            function entity:SetModel(value) self.model = value end
            function entity:SetPos(value) self.position = value end
            function entity:SetAngles(value) self.angles = value end
            function entity:SetSkin(value) self.skin = value end
            function entity:SetModelScale(value, duration) self.scale, self.scaleDuration = value, duration end
            function entity:SetNW2Float(key, value) self.scaleKey, self.networkScale = key, value end
            function entity:Spawn() self.spawned = true end
            function entity:Activate() self.activated = true end
            function entity:GetPhysicsObject() return self.physics end
            function entity:Remove() self.valid = false end
            state.entities[index] = entity
            return entity
        end
        local anchor = { valid = true, children = {}, position = { x = 100, y = 200, z = 10 },
            orientation = { p = 0, y = 0, r = 0 } }
        function anchor:GetPos() return self.position end
        function anchor:GetAngles() return self.orientation end
        function anchor:MapCreationID() return 1234 end
        function anchor:DeleteOnRemove(entity) self.children[#self.children + 1] = entity end
        local function document()
            return { schemaVersion = 1, id = "test", name = "Test", description = "", tags = {},
                props = {
                    { model = "models/props_c17/oildrum001.mdl", position = { x = 32, y = 16, z = 4 },
                        angles = { p = 0, y = 90, r = 0 }, skin = 1, scale = 1, movable = false },
                    { model = "models/props_c17/oildrum001.mdl", position = { x = 32, y = 16, z = 4 },
                        angles = { p = 0, y = 90, r = 0 }, skin = 0, scale = 1, movable = true }
                } }
        end
        return state, createSpawn(contract, api), anchor, document(), api
    end

    suite:Add("anchor transforms and per-prop motion are applied without overlap vetoes", function(check)
        for _, yaw in ipairs({ 0, 90, 180, 270 }) do
            local state, spawn, anchor, document = fixture()
            anchor.orientation.y = yaw
            local entities, problem = spawn.Create(document, anchor)
            check(entities and #entities == 2, "both overlapping props spawn for yaw " .. yaw .. ": " .. tostring(problem))
            if entities then
                local radians = yaw * math.pi / 180
                check(math.abs(entities[1].position.x - (100 + 32 * math.cos(radians) - 16 * math.sin(radians))) < 0.00001
                    and math.abs(entities[1].position.y - (200 + 32 * math.sin(radians) + 16 * math.cos(radians))) < 0.00001
                    and entities[1].position.z == 14 and entities[1].angles.y == yaw + 90,
                    "the anchor's position and rotation are used for yaw " .. yaw)
                check(entities[1].physics.motion == false and entities[1].physics.sleeping
                    and entities[2].physics.motion == true and entities[2].physics.awake,
                    "stationary and movable settings reach their physics objects")
                check(#anchor.children == 2 and entities[1].skin == 1, "anchor owns cleanup and skin is applied")
                spawn.Remove(entities)
                check(not state.entities[1].valid and not state.entities[2].valid, "owned entities are removed")
            end
        end
    end)

    suite:Add("invalid physics and unverified scales fail without partial props", function(check)
        local state, spawn, anchor, document = fixture()
        document.props[2].scale = 2
        local entities, problem = spawn.Create(document, anchor)
        check(not entities and type(problem) == "string" and #state.entities == 0,
            "scaled world collision is rejected before spawning")
        document.props[2].scale = 1
        state.invalidModel = document.props[1].model
        entities, problem = spawn.Create(document, anchor)
        check(not entities and type(problem) == "string" and #state.entities == 0,
            "models without valid physics are reported before spawning")
        state.invalidModel = nil
        state.failPhysics = 2
        entities, problem = spawn.Create(document, anchor)
        check(not entities and type(problem) == "string" and #state.entities == 2
            and not state.entities[1].valid and not state.entities[2].valid and #anchor.children == 0,
            "failed physics initialization rolls back the entire prefab")
        local state2, spawn2, anchor2, document2 = fixture()
        state2.failCreate = 2
        entities, problem = spawn2.Create(document2, anchor2)
        check(not entities and type(problem) == "string" and #state2.entities == 1
            and not state2.entities[1].valid and #anchor2.children == 0,
            "entity creation failure removes earlier props")
        anchor2.valid = false
        entities, problem = spawn2.Create(document2, anchor2)
        check(not entities and type(problem) == "string", "invalid anchors fail explicitly")
    end)
    suite:Add("loot keys identify stable props and distinct anchors", function(check)
        local _, spawn, anchor, document = fixture()
        document.props[1].propId, document.props[1].lootMode = "p_a", "normal"
        document.props[2].propId, document.props[2].lootMode = "p_b", "guaranteed"
        local entities, problem = spawn.Create(document, anchor)
        check(entities ~= nil, "lootable prefab spawns: " .. tostring(problem))
        if not entities then return end
        local secondKey = entities[2].ZM_LootSpotKey
        check(entities[1].ZM_LootSpotKey == "p1234_4_test_p_a"
            and secondKey == "p1234_4_test_p_b" and not entities[1].ZM_PrefabLoot.guaranteed
            and entities[2].ZM_PrefabLoot.guaranteed, "keys and guaranteed mode follow the authored props")
        table.remove(document.props, 1)
        local reordered = spawn.Create(document, anchor)
        check(reordered and reordered[1].ZM_LootSpotKey == secondKey,
            "removing an earlier prop does not change an explicit prop identity")
        function anchor:MapCreationID() return 1235 end
        local different = spawn.Create(document, anchor)
        check(different and different[1].ZM_LootSpotKey ~= secondKey,
            "different map anchors never share the same spot key")
        function anchor:MapCreationID() return 1234 end
        document.id, document.props[1].propId = "test_p", "b"
        local differentPrefab = spawn.Create(document, anchor)
        check(differentPrefab and differentPrefab[1].ZM_LootSpotKey ~= secondKey,
            "underscores cannot make prefab and prop IDs collide")
        document.props[1].lootGroup = "invalid"
        local invalid, error = spawn.Create(document, anchor)
        check(not invalid and type(error) == "string", "invalid loot settings fail before creating entities")
    end)
    suite:Add("experimental fixture scale is explicitly gated", function(check)
        local _, production, anchor, document, api = fixture()
        document.props[1].scale = 2
        local result = production.Create(document, anchor)
        check(result == nil, "normal spawning still rejects scaled props")
        api.AllowFixtureScale = true
        local fixtureSpawn = createSpawn(contract, api)
        result = fixtureSpawn.Create(document, anchor)
        check(result and result[1].scale == 2 and result[1].scaleDuration == 0
            and result[1].activated and result[1].physics.motion == false
            and result[1].scaleKey == "ZM.PrefabFixtureScale" and result[1].networkScale == 2,
            "only the explicit fixture path applies and publishes native scale")
    end)
    return suite
end
