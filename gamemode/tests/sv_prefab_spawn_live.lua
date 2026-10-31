return function(contract, createSpawn, createPrefabLoot, createParticleCatalog)
    ZM_TestHarness.Register({
        command = "zn_test_prefab_spawn",
        label = "Prefab spawn",
        file = "prefab-spawn-tests.json",
        report = "prefab_spawn_tests",
        help = "Tests isolated prefab prop creation in the preview launcher.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            local owned = {}
            local fakeAnchor
            local particleCatalog = createParticleCatalog(file, util, contract)
            local api = {
                Vector = Vector, Angle = Angle,
                IsValid = function(value) return (fakeAnchor ~= nil and value == fakeAnchor) or IsValid(value) end,
                LocalToWorld = LocalToWorld,
                ResolveLoot = createPrefabLoot(ZM_StaticData).Resolve,
                ResolveParticle = particleCatalog.Resolve,
                util = util, ents = { Create = function(class)
                    local entity = ents.Create(class)
                    if IsValid(entity) then owned[#owned + 1] = entity end
                    return entity
                end }
            }
            local spawner = createSpawn(contract, api)
            local fixtureApi = {
                Vector = Vector, Angle = Angle, IsValid = api.IsValid, LocalToWorld = LocalToWorld,
                util = util, ents = api.ents, ResolveLoot = api.ResolveLoot,
                ResolveParticle = api.ResolveParticle, AllowFixtureScale = true
            }
            local fixtureSpawner = createSpawn(contract, fixtureApi)
            suite:Add("engine creates and removes stationary and movable props at cardinal anchors", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                local anchor = ents.Create("info_target")
                if not IsValid(anchor) then check(false, "Could not create fixture anchor.") return end
                owned[#owned + 1] = anchor
                anchor:SetPos(Vector(0, 0, 4096))
                anchor:Spawn()
                local document = {
                    schemaVersion = 1, id = "spawn_fixture", name = "Spawn fixture", description = "", tags = {},
                    props = {
                        { model = "models/props_c17/oildrum001.mdl", position = { x = 32, y = 16, z = 4 },
                            angles = { p = 0, y = 90, r = 0 }, skin = 0, scale = 1, movable = false },
                        { model = "models/props_c17/oildrum001.mdl", position = { x = 32, y = 16, z = 4 },
                            angles = { p = 0, y = 90, r = 0 }, skin = 0, scale = 1, movable = true }
                    }
                }
                for _, yaw in ipairs({ 0, 90, 180, 270 }) do
                    anchor:SetAngles(Angle(0, yaw, 0))
                    local entities, problem = spawner.Create(document, anchor)
                    check(entities ~= nil, "Spawn at yaw " .. yaw .. ": " .. tostring(problem or ""))
                    if entities then
                        local radians = math.rad(yaw)
                        local position = entities[1]:GetPos()
                        check(math.abs(position.x - (32 * math.cos(radians) - 16 * math.sin(radians))) < 0.01
                            and math.abs(position.y - (32 * math.sin(radians) + 16 * math.cos(radians))) < 0.01
                            and math.abs(position.z - 4100) < 0.01,
                            "Anchor position and rotation are applied at yaw " .. yaw)
                        check(math.abs(math.AngleDifference(entities[1]:GetAngles().y, yaw + 90)) < 0.01,
                            "Local yaw is composed at anchor yaw " .. yaw)
                        local stationary, movable = entities[1]:GetPhysicsObject(), entities[2]:GetPhysicsObject()
                        check(IsValid(stationary) and not stationary:IsMotionEnabled()
                            and IsValid(movable) and movable:IsMotionEnabled(),
                            "Both props have physics and the requested motion state at yaw " .. yaw)
                        spawner.Remove(entities)
                    end
                end
                anchor:Remove()
            end)
            suite:Add("runtime world anchors preserve stable identity without compiled map IDs", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                local anchor = api.ents.Create("zn_prefab_anchor")
                if not IsValid(anchor) then check(false, "Could not create runtime world anchor.") return end
                anchor.ZM_PrefabInstanceId = "world_world_fixture"
                anchor:SetPos(Vector(0, 0, 4096))
                anchor:SetAngles(Angle(0, 90, 0))
                anchor:Spawn()
                check(IsValid(anchor) and anchor:MapCreationID() < 0, "world anchor exists without a compiled map ID")
                local document = {
                    schemaVersion = 1, id = "world_fixture", name = "World fixture", description = "", tags = {},
                    worldPlacement = { enabled = true, profile = "preview", cellX = 14, cellY = 0,
                        tileX = 0, tileY = 0, offset = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 90, r = 0 } },
                    props = { { model = "models/props_c17/oildrum001.mdl", propId = "drum",
                        position = { x = 32, y = 0, z = 4 }, angles = { p = 0, y = 0, r = 0 },
                        skin = 0, lootMode = "guaranteed", lootGroup = "lootGenericMedical" } },
                    lights = { { lightId = "lamp", position = { x = 0, y = 0, z = 128 },
                        angles = { p = 45, y = 0, r = 0 }, color = { r = 255, g = 255, b = 255 },
                        brightness = 6, fov = 60, range = 512 } }
                }
                local entities, problem = spawner.Create(document, anchor)
                check(entities ~= nil, "Runtime anchor spawns the prefab: " .. tostring(problem or ""))
                if entities then
                    check(entities[1].ZM_LootSpotKey == "pworld_world_fixture_13_world_fixture_drum"
                        and entities[2]:GetPrefabLightId() == "world_world_fixture:lamp",
                        "native loot and light entities retain the stable world-prefab namespace")
                    check(entities[1]:GetPos():Distance(Vector(0, 32, 4100)) < 0.01,
                        "runtime anchor composes the actual local transform")
                    spawner.Remove(entities)
                end
                anchor:Remove()
            end)

            suite:Add("native model scaling changes server collision relative to an unscaled control", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                local models = {
                    { path = "models/props_c17/oildrum001.mdl", scales = { 1, 0.1, 0.5, 2, 10 } },
                    { path = "models/props_c17/bench01a.mdl", scales = { 1, 1.4 } }
                }
                for _, model in ipairs(models) do
                    for _, movable in ipairs({ false, true }) do
                        local samples = {}
                        for _, scale in ipairs(model.scales) do
                            local entity = api.ents.Create("prop_physics")
                            if not IsValid(entity) then
                                check(false, "Could not create scaled fixture prop: " .. model.path)
                                return
                            end
                            entity:SetModel(model.path)
                            entity:SetPos(Vector(0, 0, 4096))
                            entity:SetAngles(Angle(0, 0, 0))
                            entity:Spawn()
                            if not IsValid(entity) then
                                check(false, "Could not spawn scaled fixture prop: " .. model.path)
                                return
                            end
                            entity:SetModelScale(scale, 0)
                            entity:Activate()
                            local physics = entity:GetPhysicsObject()
                            if not IsValid(physics) then
                                check(false, "Scaled fixture has no physics object: " .. model.path .. " at " .. tostring(scale))
                                return
                            end
                            physics:EnableMotion(movable)
                            if movable then physics:Wake() else physics:Sleep() end
                            local minimum, maximum = entity:GetModelBounds()
                            local height = 4096 + (minimum.z + maximum.z) * 0.5 * scale
                            check(math.abs(entity:GetModelScale() - scale) < 0.0001,
                                model.path .. " native render scale matches " .. tostring(scale))
                            local traces = {
                                x = { start = Vector(512, 0, height), finish = Vector(-512, 0, height) },
                                y = { start = Vector(0, 512, height), finish = Vector(0, -512, height) },
                                z = { start = Vector(0, 0, 5120), finish = Vector(0, 0, 3968) }
                            }
                            samples[scale] = {}
                            for axis, points in pairs(traces) do
                                local trace = util.TraceLine({
                                    start = points.start, endpos = points.finish,
                                    mask = MASK_SOLID, ignoreworld = true, filter = { entity }, whitelist = true
                                })
                                check(trace.Hit and trace.Entity == entity and not trace.StartSolid,
                                    model.path .. " collision trace hits on " .. axis .. " at scale " .. tostring(scale))
                                if trace.Hit and trace.Entity == entity then
                                    samples[scale][axis] = trace.HitPos[axis] - (axis == "z" and 4096 or 0)
                                end
                            end
                            entity:Remove()
                        end
                        for _, axis in ipairs({ "x", "y", "z" }) do
                            local baseline = samples[1] and samples[1][axis]
                            check(baseline ~= nil and baseline > 1,
                                model.path .. " has a measurable unscaled " .. axis .. " collision extent.")
                            for _, scale in ipairs(model.scales) do
                                local actual = samples[scale] and samples[scale][axis]
                                if scale ~= 1 and baseline and actual then
                                    local expected = baseline * scale
                                    check(math.abs(actual - expected) <= math.max(0.5, math.abs(expected) * 0.05),
                                        string.format("%s %s %s collision at scale %.1f: %.3f; expected %.3f.",
                                            model.path, movable and "movable" or "stationary", axis, scale, actual, expected))
                                end
                            end
                        end
                    end
                end
            end)
            suite:Add("prefab spawn metadata reaches the real loot candidate owner", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                fakeAnchor = {
                    GetPos = function() return Vector(0, 0, 4096) end,
                    GetAngles = function() return Angle(0, 0, 0) end,
                    MapCreationID = function() return 987654 end,
                    DeleteOnRemove = function() end
                }
                local document = {
                    schemaVersion = 1, id = "loot_fixture", name = "Loot fixture", description = "", tags = {},
                    props = {
                        { model = "models/props_c17/oildrum001.mdl", propId = "normal",
                            position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                            skin = 0, lootMode = "normal", lootGroup = "lootGenericMedical", lootChance = 0.4 },
                        { model = "models/props_c17/oildrum001.mdl", propId = "guaranteed",
                            position = { x = 80, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                            skin = 0, lootMode = "guaranteed", lootGroup = "lootGenericMedical" },
                        { model = "models/props_c17/oildrum001.mdl", propId = "off",
                            position = { x = 160, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                            skin = 0, lootMode = "off" }
                    }
                }
                local entities, problem = spawner.Create(document, fakeAnchor)
                check(entities ~= nil, "Fixture props spawn with validated loot: " .. tostring(problem or ""))
                if not entities then fakeAnchor = nil return end
                local found = {}
                for _, candidate in ipairs(ZM_LootSpots:FindCandidates()) do found[candidate.key] = candidate end
                local normal = found.p987654_12_loot_fixture_normal
                local guaranteed = found.p987654_12_loot_fixture_guaranteed
                check(normal and not normal.guaranteed and normal.rule.activationChance == 0.4,
                    "normal prefab reaches the real candidate owner with its configured chance")
                check(guaranteed and guaranteed.guaranteed and #guaranteed.rule.entries > 0,
                    "guaranteed prefab reaches the real candidate owner with group entries")
                check(not found.p987654_12_loot_fixture_off, "Off prefab never becomes a candidate")
                spawner.Remove(entities)
                fakeAnchor = nil
            end)
            suite:Add("fixture-only spawning applies native scale and preserves motion settings", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                local anchor = ents.Create("info_target")
                if not IsValid(anchor) then check(false, "Could not create fixture anchor.") return end
                owned[#owned + 1] = anchor
                anchor:SetPos(Vector(0, 0, 4096))
                anchor:Spawn()
                local document = {
                    schemaVersion = 1, id = "scale_fixture", name = "Scale fixture", description = "", tags = {},
                    props = {
                        { model = "models/props_c17/oildrum001.mdl", position = { x = 0, y = 0, z = 0 },
                            angles = { p = 0, y = 0, r = 0 }, skin = 0, scale = 0.5, movable = false },
                        { model = "models/props_c17/oildrum001.mdl", position = { x = 100, y = 0, z = 0 },
                            angles = { p = 0, y = 0, r = 0 }, skin = 0, scale = 2, movable = true }
                    }
                }
                local blocked = spawner.Create(document, anchor)
                check(not blocked, "normal world spawner still rejects unverified scale")
                local entities, problem = fixtureSpawner.Create(document, anchor)
                check(entities ~= nil, "fixture spawner creates scaled props: " .. tostring(problem or ""))
                if entities then
                    local fixed, moving = entities[1]:GetPhysicsObject(), entities[2]:GetPhysicsObject()
                    check(math.abs(entities[1]:GetModelScale() - 0.5) < 0.0001
                        and math.abs(entities[2]:GetModelScale() - 2) < 0.0001,
                        "native model scale matches each authored value")
                    check(IsValid(fixed) and not fixed:IsMotionEnabled() and IsValid(moving) and moving:IsMotionEnabled(),
                        "scaled props retain their stationary and movable physics settings")
                    fixtureSpawner.Remove(entities)
                end
                anchor:Remove()
            end)
            suite:Add("networked prefab spotlight uses the actual anchor transform and settings", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                fakeAnchor = {
                    GetPos = function() return Vector(0, 0, 4096) end,
                    GetAngles = function() return Angle(0, 90, 0) end,
                    MapCreationID = function() return 987654 end,
                    DeleteOnRemove = function() end
                }
                local document = {
                    schemaVersion = 1, id = "light_fixture", name = "Light fixture", description = "",
                    tags = {}, props = {}, lights = { {
                        lightId = "light_1", position = { x = 32, y = 16, z = 4 },
                        angles = { p = 40, y = 45, r = 0 }, color = { r = 255, g = 235, b = 200 },
                        brightness = 6, fov = 60, range = 512
                    } }
                }
                local entities, problem = spawner.Create(document, fakeAnchor)
                check(entities ~= nil, "Networked light spawns: " .. tostring(problem or ""))
                if entities then
                    local light = entities[1]
                    local position, color = light:GetPos(), light:GetLightColor()
                    check(light:GetClass() == "zn_prefab_spotlight" and light:GetPrefabLightId() == "987654:light_1"
                        and math.abs(position.x + 16) < 0.01 and math.abs(position.y - 32) < 0.01
                        and math.abs(position.z - 4100) < 0.01
                        and math.abs(math.AngleDifference(light:GetAngles().y, 135)) < 0.01,
                        "engine light is transformed and retains its stable network identity")
                    check(color.x == 255 and color.y == 235 and color.z == 200
                        and light:GetLightBrightness() == 6 and light:GetLightFov() == 60 and light:GetLightRange() == 512
                        and light:UpdateTransmitState() == TRANSMIT_ALWAYS,
                        "engine network variables and always-transmit policy match the authored light")
                    spawner.Remove(entities)
                end
                fakeAnchor = nil
            end)
            suite:Add("networked prefab particles use anchor transforms and triggered IDs", function(check)
                local humans = player.GetHumans()
                if game.GetMap() ~= "zn_preview_start" or ZM_World.ActiveProfile ~= "preview"
                    or #humans ~= 1 or not IsValid(humans[1]) or not humans[1]:IsAdmin()
                    or humans[1].ZM_PersistentStateLoaded == true then
                    check(false, "Run this fixture in the preview launcher with one admin and no loaded survivor.")
                    return
                end
                fakeAnchor = {
                    GetPos = function() return Vector(0, 0, 4096) end,
                    GetAngles = function() return Angle(0, 90, 0) end,
                    MapCreationID = function() return 987654 end,
                    DeleteOnRemove = function() end
                }
                local document = {
                    schemaVersion = 1, id = "particle_fixture", name = "Particle fixture", description = "",
                    tags = {}, props = {}, particles = {
                        { particleId = "continuous", effect = "steam", position = { x = 32, y = 16, z = 4 },
                            angles = { p = 0, y = 45, r = 0 }, mode = "continuous" },
                        { particleId = "burst", effect = "steam", position = { x = 64, y = 0, z = 4 },
                            angles = { p = 0, y = 90, r = 0 }, mode = "triggered", overlap = false }
                    }
                }
                local entities, problem = spawner.Create(document, fakeAnchor)
                check(entities ~= nil, "Networked particle spawns: " .. tostring(problem or ""))
                if entities then
                    local particle = entities[1]
                    local position = particle:GetPos()
                    local burst = entities.particles.burst
                    check(particle:GetClass() == "zn_prefab_particle"
                        and particle:GetPrefabParticleId() == "987654:continuous"
                        and particle:GetParticleEffectId() == "steam"
                        and math.abs(position.x + 16) < 0.01 and math.abs(position.y - 32) < 0.01
                        and math.abs(position.z - 4100) < 0.01
                        and math.abs(math.AngleDifference(particle:GetAngles().y, 135)) < 0.01
                        and particle:UpdateTransmitState() == TRANSMIT_ALWAYS,
                        "continuous entity publishes the transformed effect and stable identity")
                    check(burst and burst.id == "987654:burst" and burst.mode == "triggered"
                        and burst.overlap == false and math.abs(burst.position.y - 64) < 0.01,
                        "triggered metadata preserves its own identity, transform and restart rule")
                    spawner.Remove(entities)
                end
                fakeAnchor = nil
            end)
            return suite:Run({ teardown = function()
                for _, entity in ipairs(owned) do if IsValid(entity) then entity:Remove() end end
            end })
        end
    })
end
