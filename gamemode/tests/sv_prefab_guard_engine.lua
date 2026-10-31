return function(api, createWeaponCatalog)
    local lastEntity
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_engine",
        label = "Prefab guard model feasibility",
        file = "prefab-guard-engine-tests.json",
        report = "prefab_guard_engine_tests",
        help = "Inspects a temporary clothing-compatible model for prefab guard authoring.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            local details = { model = "models/player/group01/male_03.mdl", sequences = {} }
            suite:Add("clothing-compatible guard model exposes animation metadata", function(check)
                if lastEntity and api.IsValid(lastEntity) then
                    check(false, "the previous temporary model has not yet been removed")
                    return
                end
                check(api.Clothing.Models[details.model] ~= nil, "the model is supported by the clothing catalogue")
                if not api.util.IsValidModel(details.model) then
                    check(false, "the guard model is unavailable")
                    return
                end
                local entity = api.ents.Create("prop_dynamic")
                if not api.IsValid(entity) then
                    check(false, "the temporary guard model could not be created")
                    return
                end
                lastEntity = entity
                local ok, problem = pcall(function()
                    entity:SetModel(details.model)
                    entity:SetPos(api.Vector(0, 0, -16000))
                    entity:SetNoDraw(true)
                    entity:Spawn()
                    if not api.IsValid(entity) then
                        error("the temporary guard model could not spawn")
                    end
                    entity:SetSolid(api.SOLID_NONE)
                    local sequences = entity:GetSequenceList()
                    if type(sequences) == "table" then
                        for _, name in pairs(sequences) do
                            if type(name) == "string" then
                                local lowered = string.lower(name)
                                if string.find(lowered, "idle", 1, true) or string.find(lowered, "pistol", 1, true)
                                    or string.find(lowered, "smg", 1, true) then
                                    details.sequences[#details.sequences + 1] = name
                                end
                            end
                        end
                    end
                    table.sort(details.sequences)
                    details.idle = entity:LookupSequence("idle_all_01")
                    details.rightHandBone = entity:LookupBone("ValveBiped.Bip01_R_Hand")
                    details.rightHandAttachment = entity:LookupAttachment("anim_attachment_RH")
                    check(type(sequences) == "table" and #details.sequences > 0,
                        "the model reports candidate animation sequences")
                    check(type(details.idle) == "number" and details.idle >= 0,
                        "the candidate idle sequence resolves")
                end)
                if api.IsValid(entity) then entity:Remove() end
                check(ok, "guard model inspection failed: " .. tostring(problem))
            end)
            local summary = suite:Run()
            if api.DevConsole then api.DevConsole:Report("prefab_guard_model", details) end
            return summary
        end
    })
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_engine_cleanup",
        label = "Prefab guard model cleanup",
        file = "prefab-guard-engine-cleanup-tests.json",
        report = "prefab_guard_engine_cleanup_tests",
        help = "Verifies the temporary guard-model probe was removed after its frame.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("temporary guard model is removed", function(check)
                check(lastEntity ~= nil, "the guard model probe has run")
                if lastEntity ~= nil then check(not api.IsValid(lastEntity), "the temporary guard model is removed") end
            end)
            return suite:Run()
        end
    })
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_weapons",
        label = "Prefab guard weapon feasibility",
        file = "prefab-guard-weapon-tests.json",
        report = "prefab_guard_weapon_tests",
        help = "Checks the candidate guard firearms against the running weapon registry.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            local catalog = createWeaponCatalog(api)
            local details
            suite:Add("candidate firearms have usable guard data", function(check)
                local problem
                details, problem = catalog.List()
                check(type(details) == "table" and #details == 2,
                    "candidate guard firearms resolve: " .. tostring(problem))
            end)
            local summary = suite:Run()
            if api.DevConsole and details then api.DevConsole:Report("prefab_guard_weapons", details) end
            return summary
        end
    })
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_config",
        label = "Prefab guard configuration",
        file = "prefab-guard-config-tests.json",
        report = "prefab_guard_config_tests",
        help = "Validates Hammer guard settings against the running clothing and weapon registries.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("Hammer guard defaults and overrides resolve against live content", function(check)
                local defaults, problem = api.GuardConfig.FromHammer({})
                local normal = defaults and api.GuardConfig.Validate(defaults)
                check(normal and normal.weapon.id == "pistol" and normal.range == 1000,
                    "the default guard resolves: " .. tostring(problem))
                local values = {
                    guard_name = "Guard fixture", model = "models/player/group01/male_03.mdl",
                    idle = "idle_all_01", weapon = "pistol", range = "1000", shirt = "", pants = "",
                    damage = "25", fire_interval = "0.075", spread = "0"
                }
                local input, overrideError = api.GuardConfig.FromHammer(values)
                local override = input and api.GuardConfig.Validate(input)
                check(override and override.weapon.damage == 25 and override.weapon.delay == 0.075
                    and override.weapon.spread == 0, "the selected overrides resolve: " .. tostring(overrideError))
                values.fire_interval = "0.01"
                check(not api.GuardConfig.FromHammer(values), "invalid cadence is rejected")
                values.fire_interval, values.shirt = "", "invalid_fixture_clothing"
                check(not api.GuardConfig.FromHammer(values), "unknown clothing is rejected")
            end)
            return suite:Run()
        end
    })
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_hammer",
        label = "Prefab guard Hammer fixture",
        file = "prefab-guard-hammer-tests.json",
        report = "prefab_guard_hammer_tests",
        help = "Inspects directly map-placed guards in the isolated preview fixture.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("compiled Hammer guards initialize with their authored settings", function(check)
                local owner = api.FirstHuman()
                if not api.Editor:IsFixtureMap() or not api.Editor:IsParticipant(owner) then
                    check(false, "the sole preview fixture owner is required")
                    return
                end
                local guards = api.ents.FindByClass("zn_prefab_guard")
                check(#guards == 2, "the fixture has exactly two map guards")
                local byName = {}
                for _, guard in ipairs(guards) do byName[guard:GetName()] = guard end
                local default, custom = byName.hammer_default_guard, byName.hammer_override_guard
                check(api.IsValid(default) and api.IsValid(custom), "both named guards are present")
                if not api.IsValid(default) or not api.IsValid(custom) then return end
                check(default:CreatedByMap() and custom:CreatedByMap()
                    and default.ZM_GuardReady and custom.ZM_GuardReady, "both compiled guards initialized")
                local normal, override = default.ZM_GuardConfig, custom.ZM_GuardConfig
                check(type(normal) == "table" and type(normal.weapon) == "table"
                    and normal.name == "Guard" and normal.weapon.id == "pistol"
                    and normal.range == 1000 and normal.shirt == "" and normal.pants == "",
                    "the default guard resolves the documented settings")
                check(type(override) == "table" and type(override.weapon) == "table"
                    and override.name == "Hammer fixture" and override.weapon.id == "smg"
                    and override.range == 1200 and override.weapon.damage == 25
                    and override.weapon.delay == 0.075 and override.weapon.spread == 0.04,
                    "the custom guard retains its weapon and combat overrides")
                check(custom:GetNWString("ZM_Clothing_shirt") == "catalogue_fabric_shirt_blue_plain"
                    and custom:GetNWString("ZM_Clothing_pants") == "catalogue_fabric_pants_black_plain",
                    "the authored clothing finishes are networked")
                check(default:GetPos().x == -200 and custom:GetPos().x == 200
                    and default:GetAngles().y % 360 == 270 and custom:GetAngles().y % 360 == 270,
                    "the compiled guard transforms are preserved")
            end)
            return suite:Run()
        end
    })
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_anchor",
        label = "Prefab guard anchor fixture",
        file = "prefab-guard-anchor-tests.json",
        report = "prefab_guard_anchor_tests",
        help = "Inspects the isolated fixture's guard-bearing prefab anchors.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("compiled anchors initialize guards and props after deferred readiness", function(check)
                local owner = api.FirstHuman()
                if not api.Editor:IsFixtureMap() or not api.Editor:IsParticipant(owner)
                    or owner.ZM_PersistentStateLoaded == true or api.World.ActiveProfile ~= "preview" then
                    check(false, "The sole preview fixture owner and no loaded survivor are required.")
                    return
                end
                local status = api.Prefabs:GetStatus()
                check(status.pending == 0 and not status.error and status.anchors == 4
                    and status.guards == 4 and status.props == 4, "four anchors completed with one guard and prop each")
                for id, instance in pairs(api.Prefabs.Instances or {}) do
                    check(instance.id == "zz_dev_anchor_fixture" and not instance.pending
                        and api.IsValid(instance.anchor), "anchor " .. tostring(id) .. " owns the fixture prefab")
                    local guard, props = nil, 0
                    for _, entity in ipairs(instance.entities) do
                        if api.IsValid(entity) and entity.ZM_PrefabGuard then guard = entity
                        elseif api.IsValid(entity) and not entity.ZM_PrefabParticle and not entity.ZM_PrefabLight then
                            props = props + 1
                        end
                    end
                    check(api.IsValid(guard) and guard.ZM_GuardReady and props == 1,
                        "anchor " .. tostring(id) .. " owns a ready guard and one prop")
                    if api.IsValid(guard) and api.IsValid(instance.anchor) then
                        local position, angles = api.LocalToWorld(api.Vector(32, 16, 4), api.Angle(0, 90, 0),
                            instance.anchor:GetPos(), instance.anchor:GetAngles())
                        local config = guard.ZM_GuardConfig
                        check(guard:GetPos():DistToSqr(position) < 0.0001
                            and math.abs(api.AngleDifference(guard:GetAngles().y, angles.y)) < 0.01,
                            "anchor " .. tostring(id) .. " composes the guard transform")
                        check(type(config) == "table" and type(config.weapon) == "table"
                            and config.weapon.id == "smg" and config.weapon.damage == 25
                            and config.weapon.delay == 0.075 and config.weapon.spread == 0.04
                            and guard:GetNWString("ZM_Clothing_shirt") == "catalogue_fabric_shirt_blue_plain"
                            and guard:GetNWString("ZM_Clothing_pants") == "catalogue_fabric_pants_black_plain",
                            "anchor " .. tostring(id) .. " retains weapon, overrides and clothing")
                    end
                end
            end)
            return suite:Run()
        end
    })
end
