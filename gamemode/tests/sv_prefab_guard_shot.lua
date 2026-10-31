return function(api, createTargeting)
    local targeting = createTargeting(api)
    local lastEntities
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_shot",
        label = "Prefab guard shot feasibility",
        file = "prefab-guard-shot-tests.json",
        report = "prefab_guard_shot_tests",
        help = "Tests one isolated nonlethal shot against a temporary walker in the prefab editor.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("non-player model can fire a safe shot at a walker", function(check)
                local owner = api.FirstHuman()
                if not api.Editor:IsParticipant(owner) or api.Editor:IsFixtureMap()
                    or not owner.ZM_PrefabEditorOrigin then
                    check(false, "the sole editor owner and a ready workspace are required")
                    return
                end
                for _, entity in ipairs(lastEntities or {}) do
                    if api.IsValid(entity) then
                        check(false, "the previous probe entities have not yet been removed")
                        return
                    end
                end
                lastEntities = {}
                local shooter = api.ents.Create("prop_dynamic")
                if not api.IsValid(shooter) then
                    check(false, "could not create the temporary shooter")
                    return
                end
                lastEntities[#lastEntities + 1] = shooter
                local ok, problem = pcall(function()
                    shooter:SetModel("models/player/group01/male_03.mdl")
                    shooter:SetPos(owner.ZM_PrefabEditorOrigin + api.Vector(-160, 400, 0))
                    shooter:SetNoDraw(true)
                    shooter:Spawn()
                    if not api.IsValid(shooter) then error("could not spawn the temporary shooter") end
                    shooter:SetSolid(api.SOLID_NONE)
                    local walker = api.ents.Create("zn_walker_zombie")
                    if not api.IsValid(walker) then error("could not create the temporary walker") end
                    lastEntities[#lastEntities + 1] = walker
                    walker:SetPos(owner.ZM_PrefabEditorOrigin + api.Vector(160, 400, 0))
                    walker:SetNoDraw(true)
                    walker:Spawn()
                    if not api.IsValid(walker) then error("could not spawn the temporary walker") end
                    walker:SetHealth(10000)
                    local source = shooter:GetPos() + api.Vector(0, 0, 36)
                    local before = walker:Health()
                    local fired, reason = targeting.Fire(shooter, source, walker, 512,
                        { damage = 1, spread = 0, force = 0, tracer = 0 })
                    check(fired, "the guard targeting primitive fires: " .. tostring(reason))
                    check(walker:Health() < before and walker:Health() > 0,
                        "the shot hits the temporary walker nonlethally")
                end)
                for _, entity in ipairs(lastEntities) do
                    if api.IsValid(entity) then entity:Remove() end
                end
                check(ok, "guard shot inspection failed: " .. tostring(problem))
            end)
            return suite:Run()
        end
    })
    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_shot_cleanup",
        label = "Prefab guard shot cleanup",
        file = "prefab-guard-shot-cleanup-tests.json",
        report = "prefab_guard_shot_cleanup_tests",
        help = "Verifies the temporary guard-shot probe entities were removed after their frame.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("temporary guard-shot entities are removed", function(check)
                check(lastEntities ~= nil and #lastEntities > 0, "the guard-shot probe has run")
                for _, entity in ipairs(lastEntities or {}) do
                    check(not api.IsValid(entity), "a temporary guard-shot entity remains")
                end
            end)
            return suite:Run()
        end
    })
end
