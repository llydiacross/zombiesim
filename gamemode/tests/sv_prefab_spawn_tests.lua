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
            ResolveParticle = function(id)
                if id == "steam" then return { id = "steam" } end
                return nil, "Unknown particle effect."
            end,
            ResolveGuard = function(guard)
                if state.invalidGuard == guard.guardId then return nil, "invalid guard settings" end
                return { name = guard.name, weapon = guard.weapon, damage = guard.damage, spread = guard.spread }
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
            assert(class == "prop_physics" or class == "zn_prefab_spotlight" or class == "zn_prefab_particle"
                or class == "zn_prefab_guard")
            local index = #state.entities + 1
            if state.failCreate == index then return nil end
            if class == "zn_prefab_guard" then
                local guard = { valid = true }
                function guard:SetPos(value) self.position = value end
                function guard:SetAngles(value) self.angles = value end
                function guard:Spawn() self.spawned = true end
                function guard:Complete(ok, problem)
                    local callback = self.ZM_GuardReadyCallback
                    self.ZM_GuardReadyCallback = nil
                    if callback then callback(self, ok, problem) end
                end
                function guard:Remove()
                    self.valid = false
                    self:Complete(false, "removed before ready")
                end
                state.entities[index] = guard
                return guard
            end
            if class == "zn_prefab_spotlight" or class == "zn_prefab_particle" then
                local light = { valid = true }
                for _, name in ipairs({ "SetPos", "SetAngles", "SetPrefabLightId", "SetLightColor",
                    "SetLightBrightness", "SetLightFov", "SetLightRange", "SetPrefabParticleId", "SetParticleEffectId" }) do
                    light[name] = function(self, value) self[name .. "Value"] = value end
                end
                function light:Spawn() self.spawned = true end
                function light:Remove() self.valid = false end
                state.entities[index] = light
                return light
            end
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
    suite:Add("guard spawning is rejected in unsupported contexts before creating entities", function(check)
        local state, spawn, anchor, document = fixture()
        document.guards = { {
            guardId = "guard_1", name = "Guard", model = "models/props_c17/oildrum001.mdl",
            position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
            idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = ""
        } }
        local entities, problem = spawn.Create(document, anchor)
        check(not entities and type(problem) == "string" and string.find(problem, "guard", 1, true)
            and #state.entities == 0, "guard-bearing prefabs fail explicitly before any partial spawn")
    end)
    suite:Add("fixture guards wait for every actor and use anchor transforms", function(check)
        local state, spawn, anchor, document, api = fixture()
        api.AllowGuards = true
        anchor.orientation.y = 90
        document.guards = {
            { guardId = "guard_1", name = "First", model = "models/props_c17/oildrum001.mdl",
                position = { x = 10, y = 20, z = 4 }, angles = { p = 0, y = 45, r = 0 },
                idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = "",
                damage = 25, spread = 0 },
            { guardId = "guard_2", name = "Second", model = "models/props_c17/oildrum001.mdl",
                position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = "" }
        }
        local missing, message = spawn.Create(document, anchor)
        check(not missing and type(message) == "string" and #state.entities == 0,
            "a guard prefab requires a readiness owner before creating entities")
        local calls = {}
        local entities, problem, pending = spawn.Create(document, anchor, function(ok, reason)
            calls[#calls + 1] = { ok = ok, reason = reason }
        end)
        local first, second = entities and entities[3], entities and entities[4]
        check(entities and pending and first.ZM_PrefabGuard and first.ZM_GuardConfig.damage == 25
            and first.ZM_GuardConfig.spread == 0 and math.abs(first.position.x - 80) < 0.00001
            and math.abs(first.position.y - 210) < 0.00001 and first.position.z == 14 and first.angles.y == 135,
            "guard settings and local transform follow the rotated anchor: " .. tostring(problem))
        first:Complete(true)
        check(#calls == 0, "one ready guard cannot complete a multi-guard prefab")
        second:Complete(true)
        check(#calls == 1 and calls[1].ok and #anchor.children == 4,
            "the owner is notified once after both guards are ready")
        spawn.Remove(entities)
        check(#calls == 1 and not first.valid and not second.valid, "cleanup does not repeat readiness")
    end)
    suite:Add("fixture guard failures roll back every owned entity", function(check)
        local state, spawn, anchor, document, api = fixture()
        api.AllowGuards = true
        document.guards = { {
            guardId = "guard_1", name = "Guard", model = "models/props_c17/oildrum001.mdl",
            position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
            idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = ""
        } }
        state.invalidGuard = "guard_1"
        local entities, problem = spawn.Create(document, anchor, function() end)
        check(not entities and type(problem) == "string" and #state.entities == 0,
            "invalid guard settings fail before any props are created")
        state.invalidGuard = nil
        local calls = {}
        entities, problem = spawn.Create(document, anchor, function(ok, reason)
            calls[#calls + 1] = { ok = ok, reason = reason }
        end)
        local guard = entities and entities[3]
        if guard then guard:Complete(false, "missing animation") end
        check(#calls == 1 and not calls[1].ok and string.find(calls[1].reason, "missing animation", 1, true)
            and not state.entities[1].valid and not state.entities[2].valid and not guard.valid,
            "a deferred guard failure reports the error and removes all earlier props")
    end)
    suite:Add("world prefab identities keep loot and effects stable across runtime entity IDs", function(check)
        local state, spawn, anchor, document = fixture()
        anchor.ZM_PrefabInstanceId = "world_test"
        function anchor:MapCreationID() return -1 end
        document.props[1].lootMode = "guaranteed"
        document.lights = { { lightId = "lamp", position = { x = 0, y = 0, z = 100 },
            angles = { p = 45, y = 0, r = 0 }, color = { r = 255, g = 255, b = 255 },
            brightness = 6, fov = 60, range = 512 } }
        document.particles = { { particleId = "steam", effect = "steam", position = { x = 0, y = 0, z = 0 },
            angles = { p = 0, y = 0, r = 0 }, mode = "triggered", overlap = false } }
        local result, problem = spawn.Create(document, anchor)
        check(result and result[1].ZM_LootSpotKey == "pworld_test_4_test_legacy_1"
            and result[3].SetPrefabLightIdValue == "world_test:lamp"
            and result.particles.steam.id == "world_test:steam",
            "loot, projector and particle keys use document identity: " .. tostring(problem))
        spawn.Remove(result)
        anchor.ZM_PrefabInstanceId = "world_different"
        local previousCount = #state.entities
        result, problem = spawn.Create(document, anchor)
        check(not result and type(problem) == "string" and #state.entities == previousCount,
            "a mismatched document identity is rejected before creating anything")
    end)

    suite:Add("spotlights use authoritative anchor transforms and roll back on failure", function(check)
        local state, spawn, anchor, document = fixture()
        document.lights = { { lightId = "light_1", position = { x = 10, y = 0, z = 100 },
            angles = { p = 40, y = 45, r = 0 }, color = { r = 255, g = 235, b = 200 },
            brightness = 6, fov = 60, range = 512 } }
        anchor.orientation.y = 90
        local result, problem = spawn.Create(document, anchor)
        local light = result and result[3]
        check(light and light.ZM_PrefabLight and light.spawned and light.SetPrefabLightIdValue == "1234:light_1"
            and math.abs(light.SetPosValue.x - 100) < 0.00001
            and math.abs(light.SetPosValue.y - 210) < 0.00001 and light.SetPosValue.z == 110
            and light.SetAnglesValue.y == 135 and light.SetLightColorValue.y == 235
            and light.SetLightBrightnessValue == 6 and light.SetLightFovValue == 60
            and light.SetLightRangeValue == 512 and #anchor.children == 3,
            "light transform, settings and cleanup ownership follow the anchor: " .. tostring(problem))
        spawn.Remove(result)
        check(not light.valid and not state.entities[1].valid, "cleanup removes lights and props")
        local state2, spawn2, anchor2, document2 = fixture()
        document2.lights = document.lights
        state2.failCreate = 3
        result, problem = spawn2.Create(document2, anchor2)
        check(not result and type(problem) == "string" and not state2.entities[1].valid
            and not state2.entities[2].valid and #anchor2.children == 0,
            "a failed light creation removes all prior props")
        local state3, spawn3, anchor3, document3 = fixture()
        document3.lights = document.lights
        function anchor3:MapCreationID() return -1 end
        result, problem = spawn3.Create(document3, anchor3)
        check(not result and type(problem) == "string" and #state3.entities == 0,
            "missing stable anchor identity fails before spawning")
    end)
    suite:Add("particles use authoritative anchor transforms and roll back on failure", function(check)
        local state, spawn, anchor, document = fixture()
        anchor.orientation.y = 90
        document.particles = {
            { particleId = "steam_1", effect = "steam", position = { x = 10, y = 0, z = 16 },
                angles = { p = 0, y = 45, r = 0 }, mode = "continuous" },
            { particleId = "steam_2", effect = "steam", position = { x = 20, y = 0, z = 16 },
                angles = { p = 0, y = 90, r = 0 }, mode = "triggered", overlap = false }
        }
        local result, problem = spawn.Create(document, anchor)
        local entity = result and result[3]
        local triggered = result and result.particles.steam_2
        check(entity and entity.ZM_PrefabParticle and entity.spawned
            and entity.SetPrefabParticleIdValue == "1234:steam_1" and entity.SetParticleEffectIdValue == "steam"
            and math.abs(entity.SetPosValue.y - 210) < 0.00001 and entity.SetAnglesValue.y == 135
            and triggered and triggered.id == "1234:steam_2" and triggered.mode == "triggered"
            and triggered.overlap == false and math.abs(triggered.position.y - 220) < 0.00001
            and #anchor.children == 3, "continuous entity and triggered metadata use the anchor: " .. tostring(problem))
        spawn.Remove(result)
        check(not entity.valid and not state.entities[1].valid, "cleanup removes owned particle and props")
        local state2, spawn2, anchor2, document2 = fixture()
        document2.particles = document.particles
        state2.failCreate = 3
        result, problem = spawn2.Create(document2, anchor2)
        check(not result and type(problem) == "string" and not state2.entities[1].valid
            and not state2.entities[2].valid and #anchor2.children == 0,
            "particle entity failure rolls back previously created props")
        local state3, spawn3, anchor3, document3 = fixture()
        document3.particles = document.particles
        document3.particles[1].effect = "unknown"
        result, problem = spawn3.Create(document3, anchor3)
        check(not result and type(problem) == "string" and #state3.entities == 0,
            "unknown catalog effects fail before creating entities")
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
