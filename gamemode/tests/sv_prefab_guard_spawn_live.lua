return function(api, contract, createSpawn)
    local run, lastOwned
    local timerName = "ZM.PrefabGuardSpawnFixture.Expiry"

    local function allowed()
        local humans = api.player.GetHumans()
        return api.game.GetMap() == "zn_preview_start" and api.World.ActiveProfile == "preview"
            and #humans == 1 and api.IsValid(humans[1]) and humans[1]:IsAdmin()
            and humans[1].ZM_PersistentStateLoaded ~= true
    end

    local function cleanup()
        api.timer.Remove(timerName)
        if not run then return end
        lastOwned = {}
        for _, record in ipairs(run.records) do
            if api.IsValid(record.guard) then
                if api.IsValid(record.guard.ZM_WeaponModel) then lastOwned[#lastOwned + 1] = record.guard.ZM_WeaponModel end
                lastOwned[#lastOwned + 1] = record.guard
            end
        end
        if api.IsValid(run.anchor) then lastOwned[#lastOwned + 1] = run.anchor end
        for _, entity in ipairs(lastOwned) do if api.IsValid(entity) then entity:Remove() end end
        run = nil
    end

    api.hook.Add("PreCleanupMap", "ZM.PrefabGuardSpawnFixture", cleanup)
    api.hook.Add("ShutDown", "ZM.PrefabGuardSpawnFixture", cleanup)

    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_spawn",
        label = "Prefab guard spawn start",
        file = "prefab-guard-spawn-tests.json",
        report = "prefab_guard_spawn_tests",
        help = "Creates isolated guards at four anchor rotations in the preview launcher.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("four fixture guards start deferred initialization", function(check)
                if not allowed() then check(false, "One preview-launcher admin and no loaded survivor are required.") return end
                if run then check(false, "A guard spawn fixture is already active.") return end
                for _, entity in ipairs(lastOwned or {}) do
                    if api.IsValid(entity) then check(false, "Previous fixture entities are still being removed.") return end
                end
                local anchor = api.ents.Create("info_target")
                if not api.IsValid(anchor) then check(false, "Could not create fixture anchor.") return end
                run = { anchor = anchor, records = {} }
                anchor:SetPos(api.Vector(0, 0, 4096))
                anchor:Spawn()
                if not api.IsValid(anchor) then cleanup(); check(false, "Could not spawn fixture anchor.") return end
                local spawn = createSpawn(contract, {
                    Vector = api.Vector, Angle = api.Angle, IsValid = api.IsValid, LocalToWorld = api.LocalToWorld,
                    util = api.util, ents = api.ents, AllowGuards = true,
                    ResolveGuard = api.GuardConfig.PrepareDocumentGuard
                })
                local document = {
                    schemaVersion = 1, id = "guard_spawn_fixture", name = "Guard spawn fixture",
                    description = "", tags = {}, props = {}, guards = { {
                        guardId = "guard_1", name = "Fixture guard", model = "models/player/group01/male_03.mdl",
                        position = { x = 32, y = 16, z = 4 }, angles = { p = 0, y = 90, r = 0 },
                        idle = "idle_all_01", weapon = "pistol", range = 1000, shirt = "", pants = "",
                        damage = 23, fireInterval = 0.075, spread = 0.04
                    } }
                }
                for _, yaw in ipairs({ 0, 90, 180, 270 }) do
                    anchor:SetAngles(api.Angle(0, yaw, 0))
                    local record = { yaw = yaw }
                    run.records[#run.records + 1] = record
                    local entities, problem, pending = spawn.Create(document, anchor, function(ok, reason)
                        record.done, record.ok, record.problem = true, ok, reason
                    end)
                    if not entities or not pending then
                        cleanup()
                        check(false, "Guard fixture failed to start: " .. tostring(problem or "initialization was not pending"))
                        return
                    end
                    record.guard = entities[1]
                end
                api.timer.Create(timerName, 30, 1, cleanup)
                check(#run.records == 4, "four actors are waiting for their engine initialization")
            end)
            return suite:Run()
        end
    })

    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_spawn_check",
        label = "Prefab guard spawn check",
        file = "prefab-guard-spawn-check-tests.json",
        report = "prefab_guard_spawn_check_tests",
        help = "Checks deferred guard initialization and removes the isolated actors.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("initialized fixture guards retain transforms and combat overrides", function(check)
                if not allowed() then check(false, "One preview-launcher admin and no loaded survivor are required.") return end
                if not run then check(false, "Start the guard spawn fixture first.") return end
                for _, record in ipairs(run.records) do
                    if not record.done then check(false, "Guard initialization is still pending.") return end
                end
                for _, record in ipairs(run.records) do
                    local guard, yaw = record.guard, record.yaw
                    local valid = record.ok and api.IsValid(guard) and guard.ZM_GuardReady == true
                    check(valid, "Guard initialization at yaw " .. yaw .. ": " .. tostring(record.problem))
                    if valid then
                        local radians = math.rad(yaw)
                        local position, angles = guard:GetPos(), guard:GetAngles()
                        local config = guard.ZM_GuardConfig
                        check(math.abs(position.x - (32 * math.cos(radians) - 16 * math.sin(radians))) < 0.01
                            and math.abs(position.y - (32 * math.sin(radians) + 16 * math.cos(radians))) < 0.01
                            and math.abs(position.z - 4100) < 0.01
                            and math.abs(api.AngleDifference(angles.y, yaw + 90)) < 0.01,
                            "Guard local transform is composed at yaw " .. yaw)
                        check(type(config) == "table" and type(config.weapon) == "table"
                            and config.weapon.damage == 23 and config.weapon.delay == 0.075
                            and config.weapon.spread == 0.04 and api.IsValid(guard.ZM_WeaponModel),
                            "Guard weapon overrides survive engine initialization at yaw " .. yaw)
                    end
                end
                cleanup()
            end)
            return suite:Run()
        end
    })

    ZM_TestHarness.Register({
        command = "zn_test_prefab_guard_spawn_cleanup",
        label = "Prefab guard spawn cleanup",
        file = "prefab-guard-spawn-cleanup-tests.json",
        report = "prefab_guard_spawn_cleanup_tests",
        help = "Checks the isolated guard spawn entities after deferred removal.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("guard fixture entities have been removed", function(check)
                check(lastOwned ~= nil and #lastOwned > 0, "The guard spawn fixture ran and requested cleanup.")
                for _, entity in ipairs(lastOwned or {}) do check(not api.IsValid(entity), "A fixture entity remains.") end
            end)
            return suite:Run()
        end
    })
end
