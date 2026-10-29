return function(contract, createSpawn, createLoot)
    local markerPath = "zombiesim/prefab_city_probe.json"
    local function readMarker()
        local text = file.Read(markerPath, "DATA")
        local marker = type(text) == "string" and util.JSONToTable(text) or nil
        if type(marker) ~= "table" or marker.schemaVersion ~= 1 or type(marker.profile) ~= "string"
            or not string.match(marker.profile, "^zn_test_prefab_city_[0-9a-f]+$") then
            return nil, "The prefab city probe marker is invalid; inspect it before cleanup."
        end
        return marker
    end
    local function cleanupMarker()
        local marker, problem = readMarker()
        if not marker then return false, problem end
        local removed, removeError = ZM_DeleteLootCells(marker.profile)
        if not removed then return false, "Could not remove test loot rows: " .. tostring(removeError) end
        for _, name in ipairs({ "loot_cells", "loot_spots", "loot_cell_backups" }) do
            local rows = sql.Query("SELECT profile FROM " .. name .. " WHERE profile = " .. sql.SQLStr(marker.profile) .. " LIMIT 1")
            if rows == false then return false, "Could not verify test loot cleanup: " .. tostring(sql.LastError()) end
            if rows and #rows > 0 then return false, "Test loot rows remain in " .. name .. "." end
        end
        if not file.Delete(markerPath) then return false, "Could not remove the prefab city probe marker." end
        if file.Exists(markerPath, "DATA") then return false, "The prefab city probe marker still exists." end
        return true
    end
    ZM_Util.RegisterCommands({
        zombiesim_prefab_city_probe_recover = "Removes the explicitly recorded throwaway prefab city-probe rows."
    }, function(caller, command)
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not IsValid(target) or not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview"
            or #player.GetHumans() ~= 1 then
            return false, "Prefab city probe recovery requires the sole preview admin."
        end
        if not file.Exists(markerPath, "DATA") then return false, "No prefab city probe recovery marker exists." end
        return cleanupMarker()
    end)

    ZM_TestHarness.Register({
        command = "zn_test_prefab_city",
        label = "Prefab city probe",
        file = "prefab-city-tests.json",
        report = "prefab_city_tests",
        help = "Tests a transient prefab loot prop in the current preview city cell without granting items.",
        run = function()
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("real city context finds, searches and declines temporary prefab loot", function(check)
                local target = ZM_Util.FirstHuman()
                local humans = player.GetHumans()
                if not IsValid(target) or not target:IsAdmin() or not target:Alive() or #humans ~= 1
                    or ZM_World.ActiveProfile ~= "preview" or target.ZM_PersistentStateLoaded ~= true
                    or not target.ZM_Inventory
                    or type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= ""
                    or not ZM_Prefabs.Ready or not ZM_LootSpots.Cell then
                    check(false, "A sole deployed preview admin with active city loot is required.")
                    return
                end
                local cell, cellError = target:GetWorldCell()
                local active = ZM_LootSpots.Cell
                local path = cell and ZM_World:GetMapPath(cell) or ""
                local mapName = string.lower(string.match(path or "", "([^/]+)$") or "")
                if not cell or ZM_SafeZones:IsSafeZoneCell(cell) or active.profile ~= "preview"
                    or active.cellId ~= cell.id or string.lower(game.GetMap()) ~= mapName then
                    check(false, "The deployed survivor, active loot and current city map do not agree: " .. tostring(cellError or ""))
                    return
                end
                if target.ZM_LootSearch or target.ZM_LootOffer then
                    check(false, "Finish the current loot interaction before running the probe.")
                    return
                end
                if file.Exists(markerPath, "DATA") then
                    check(false, "A previous prefab city probe needs explicit recovery first.")
                    return
                end
                local profile = "zn_test_prefab_city_" .. ZM_ItemGeneration.NewInstanceId()
                for _, name in ipairs({ "loot_cells", "loot_spots", "loot_cell_backups" }) do
                    local rows = sql.Query("SELECT profile FROM " .. name .. " WHERE profile = " .. sql.SQLStr(profile) .. " LIMIT 1")
                    if rows == false then check(false, "Could not check the temporary loot profile: " .. tostring(sql.LastError())) return end
                    if rows and #rows > 0 then check(false, "The temporary loot profile already exists.") return end
                end
                local marker = util.TableToJSON({ schemaVersion = 1, profile = profile }, false)
                file.CreateDir("zombiesim")
                if type(marker) ~= "string" or not file.Write(markerPath, marker) or file.Read(markerPath, "DATA") ~= marker then
                    check(false, "Could not create and verify the prefab city probe recovery marker.")
                    return
                end
                local previousCell = ZM_LootSpots.Cell
                local anchor = {
                    GetPos = function() return target:WorldSpaceCenter() end,
                    GetAngles = function() return Angle(0, 0, 0) end,
                    MapCreationID = function() return 2147483000 end,
                    DeleteOnRemove = function() end
                }
                local spawned, spawner, started
                local owned = {}
                local before = util.TableToJSON(ZM_InventoryService.ToRows(target.ZM_Inventory), false)
                local originalPosition = target:GetPos()
                local ok, problem = pcall(function()
                    local loot = createLoot(ZM_StaticData)
                    spawner = createSpawn(contract, {
                        Vector = Vector, Angle = Angle, LocalToWorld = LocalToWorld, util = util,
                        ents = { Create = function(class)
                            local entity = ents.Create(class)
                            if IsValid(entity) then owned[#owned + 1] = entity end
                            return entity
                        end },
                        IsValid = function(value) return value == anchor or IsValid(value) end,
                        ResolveLoot = loot.Resolve
                    })
                    local document = {
                        schemaVersion = 1, id = "zz_dev_city_loot", name = "Temporary city loot probe",
                        description = "", tags = {}, props = {
                            { model = "models/props_c17/oildrum001.mdl", propId = "probe",
                                position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 },
                                skin = 0, scale = 1, movable = false, lootMode = "guaranteed",
                                lootGroup = "lootGenericMedical" }
                        }
                    }
                    local spawnError
                    spawned, spawnError = spawner.Create(document, anchor)
                    if not spawned then error("Could not create the temporary prefab prop: " .. tostring(spawnError)) end
                    local key = spawned[1].ZM_LootSpotKey
                    local candidate
                    for _, entry in ipairs(ZM_LootSpots:FindCandidates()) do
                        if entry.key == key then candidate = entry break end
                    end
                    if not candidate or not candidate.guaranteed then error("The real city candidate scan did not find guaranteed prefab loot.") end
                    local now = os.time()
                    local testCell, loadError = ZM_LootSpots:LoadCell(profile, cell.id, { candidate }, {
                        now = now, rng = ZM_ItemGeneration.NewRng(42), danger = ZM_World:GetDangerIntensity(cell) or 0
                    })
                    if not testCell or not testCell.spots[key] then error("Could not initialize test loot: " .. tostring(loadError)) end
                    ZM_LootSpots:Activate(testCell)
                    local selected = ZM_LootSpots:FindNearestSpot(target)
                    if not selected or selected.key ~= key then error("The real player could not target the temporary spot.") end
                    local time = CurTime()
                    local began, beginError = ZM_LootSpots:BeginSearch(target, selected, time)
                    if not began then error("Could not search the temporary spot: " .. tostring(beginError)) end
                    started = true
                    local offer, offerError = ZM_LootSpots:CompleteSearch(target, time + ZM_LootSpots.SearchSeconds,
                        ZM_ItemGeneration.NewRng(43))
                    if not offer then error("Could not produce the test offer: " .. tostring(offerError)) end
                    local declined, declineError = ZM_LootSpots:RespondOffer(target, offer.token, false,
                        time + ZM_LootSpots.SearchSeconds)
                    if not declined then error("Could not decline the test offer: " .. tostring(declineError)) end
                    local restored, restoreError = ZM_LootSpots:LoadCell(profile, cell.id, { candidate }, { now = now + 1 })
                    if not restored or not restored.spots[key] or restored.spots[key].state ~= "declined"
                        or not restored.spots[key].item or restored.spots[key].item.instanceId ~= selected.item.instanceId then
                        error("The declined test offer did not survive reload: " .. tostring(restoreError))
                    end
                    check(true, "Real city candidate, targeting, search, decline and throwaway persistence completed.")
                end)
                if started then
                    ZM_LootSpots:CancelSearch(target)
                    ZM_LootSpots:ReleasePlayer(target)
                    net.Start("ZM.LootOfferResult")
                        net.WriteBool(false)
                        net.WriteString("Prefab test complete; no item was taken.")
                    net.Send(target)
                end
                ZM_LootSpots.Cell = previousCell
                if spawned then spawner.Remove(spawned) end
                for _, entity in ipairs(owned) do if IsValid(entity) then entity:Remove() end end
                local cleaned, cleanupError = cleanupMarker()
                check(cleaned, "Temporary loot profile and marker are removed: " .. tostring(cleanupError or ""))
                check(ok, "City prefab loot probe: " .. tostring(problem or ""))
                local after = util.TableToJSON(ZM_InventoryService.ToRows(target.ZM_Inventory), false)
                check(type(before) == "string" and before == after, "The real survivor inventory is unchanged.")
                check(target:GetPos():DistToSqr(originalPosition) < 0.0001, "The real survivor was not moved.")
            end)
            return suite:Run()
        end
    })
end
