// Actual client-model pool regressions. Run in PreRender; own and remove every fixture.
local requested = false
local runFrame
local Clothing = ZM_Clothing

concommand.Add("zombiesim_dev_clothing_meshes", function()
    if not ZM_Wardrobe:IsAvailable() then
        ErrorNoHalt("[ZombieSim] Clothing mesh inspection requires a preview admin.\n")
        return
    end
    local report = { schemaVersion = 1, models = {}, capturedAt = os.time(), map = game.GetMap() }
    for _, sex in ipairs({ "male", "female" }) do
        for number = 1, sex == "male" and 9 or 6 do
            local path = string.format("models/player/group01/%s_%02d.mdl", sex, number)
            local meshes = util.GetModelMeshes(path, 0)
            if type(meshes) ~= "table" then
                ErrorNoHalt("[ZombieSim] Cannot inspect citizen mesh: " .. path .. "\n")
                return
            end
            local bodies = {}
            for _, part in ipairs(meshes) do
                if string.lower(part.material) == "models/humans/" .. sex .. "/group01/players_sheet" then
                    local triangles = {}
                    for index = 1, #part.triangles, 3 do
                        local positions, uv = {}, {}
                        for corner = 0, 2 do
                            local vertex = part.triangles[index + corner]
                            positions[#positions + 1] = { vertex.pos.x, vertex.pos.y, vertex.pos.z }
                            uv[#uv + 1], uv[#uv + 2] = vertex.u, vertex.v
                        end
                        triangles[#triangles + 1] = { positions = positions, uv = uv }
                    end
                    bodies[#bodies + 1] = { material = part.material, triangles = triangles }
                end
            end
            if #bodies ~= 1 then
                ErrorNoHalt("[ZombieSim] Citizen inspection requires exactly one body mesh: " .. path .. "\n")
                return
            end
            report.models[#report.models + 1] = { model = path, bodies = bodies }
        end
    end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/clothing_mesh_inspection.json", util.TableToJSON(report, false))
    print("[ZombieSim] Inspected fifteen citizen body meshes through util.GetModelMeshes.")
end)

concommand.Add("zombiesim_dev_test_clothing_pool", function()
    if not ZM_Wardrobe:IsAvailable() then
        ErrorNoHalt("[ZombieSim] Clothing pool tests require a preview admin.\n")
        return
    end
    if requested or runFrame then
        ErrorNoHalt("[ZombieSim] Clothing pool tests are already running.\n")
        return
    end
    requested = true
end)

hook.Add("PreRender", "ZM.Clothing.PoolTests", function()
    if runFrame then runFrame() return end
    if not requested then return end
    requested = false
    if not ZM_Wardrobe:IsAvailable() then return end
    local owned, shirts, pants = {}, {}, {}
    local originalBuilder = Clothing.BuildEquippedFinish
    local suite = ZM_TestHarness.NewSuite()
    local function stepped(name, steps)
        suite:Add(name, function() end)
        suite.cases[#suite.cases].steps = steps
    end
    local function cleanup()
        Clothing.BuildEquippedFinish = originalBuilder
        for _, entity in ipairs(owned) do
            if IsValid(entity) then Clothing:Apply(entity, "", "") entity:Remove() end
        end
        owned = {}
    end
    local function model(sex, number)
        local name = number and string.format("%s_%02d", sex, number) or (sex == "female" and "female_01" or "male_03")
        local entity = ClientsideModel("models/player/group01/" .. name .. ".mdl", RENDERGROUP_OTHER)
        if not IsValid(entity) then error("Could not create clothing pool fixture") end
        owned[#owned + 1] = entity
        entity:SetNoDraw(true)
        return entity
    end
    local function body(entity)
        for index, path in ipairs(entity:GetMaterials()) do
            if string.find(path, "/group01/players_sheet", 1, true) then return index - 1 end
        end
        error("Fixture has no supported clothing body material")
    end
    local function material(entity)
        return Clothing:GetEntitySubMaterial(entity, body(entity))
    end
    local function requireCatalogue()
        if not Clothing.CatalogueReady or #shirts <= Clothing.TextureCapacity or #pants < 1 then
            error("Pool tests need more shirts than outfit slots and at least one pants finish")
        end
    end
    for id, finish in pairs(Clothing.Finishes) do
        if finish.garment == "shirt" then shirts[#shirts + 1] = id
        elseif finish.garment == "pants" then pants[#pants + 1] = id end
    end
    table.sort(shirts)
    table.sort(pants)
    local baseline = Clothing:GetReferencedTextureSlots()
    suite:Add("shared_outfit_and_independent_native_restore", function(check)
        requireCatalogue()
        local a, b = model("male"), model("male")
        check(Clothing:Apply(a, shirts[1], pants[1]), "First generated combination applies")
        local first = material(a)
        check(first ~= "", "Actual clothing-owned body override exists")
        check(Clothing:Apply(b, shirts[1], pants[1]) and material(b) == first, "Identical outfits share one texture")
        check(Clothing:Apply(a, "", pants[1]) and material(a) ~= first, "Independent shirt restoration composes pants-only")
        check(material(b) == first, "Other model retains original combination")
        check(Clothing:Apply(a, "", "") and material(a) == "", "Both native restores original override")
        local female = model("female")
        check(Clothing:Apply(female, shirts[1], pants[1]), "Female generated combination applies")
        check(material(female) ~= first, "Male and female layouts do not share an outfit texture")
    end)
    suite:Add("queued_and_live_gore_reference_pinning", function(check)
        requireCatalogue()
        local source, limb = model("male"), model("male")
        check(Clothing:Apply(source, shirts[2], ""), "Source finish applies")
        local name = material(source)
        local slot = tonumber(string.match(name, "pool_(%d%d)_"))
        local queued = { { materials = { [body(source)] = name } } }
        Clothing:Apply(source, "", "")
        check(slot and Clothing:GetReferencedTextureSlots(queued, {})[slot], "Pending immutable copy pins released source slot")
        limb:SetSubMaterial(body(limb), name)
        check(slot and Clothing:GetReferencedTextureSlots({}, { { entity = limb, materials = queued[1].materials } })[slot],
            "Live copied limb pins immutable material record even before getter publication")
        limb:SetSubMaterial(body(limb), "")
        check(slot and not Clothing:GetReferencedTextureSlots({}, { { entity = limb } })[slot], "Removed override releases pin")
    end)
    local capacitySteps, materials = {}, {}
    for index = 1, Clothing.TextureCapacity do
        local slot = index
        capacitySteps[#capacitySteps + 1] = function(check)
            requireCatalogue()
            if next(baseline) then error("Close dressed UI and unequip live clothes before the isolated full-capacity test") end
            local entity = model("male")
            check(Clothing:Apply(entity, shirts[slot], ""), "Distinct outfit " .. slot .. " applies")
            materials[slot] = material(entity)
        end
    end
    capacitySteps[#capacitySteps + 1] = function(check)
        requireCatalogue()
        if next(baseline) then error("Close dressed UI and unequip live clothes before the isolated full-capacity test") end
        check(table.Count(Clothing:GetReferencedTextureSlots()) == Clothing.TextureCapacity, "Exactly the configured capacity pinned")
        local extra = model("male")
        local overflow = shirts[Clothing.TextureCapacity + 1]
        check(not Clothing:Apply(extra, overflow, "") and material(extra) == "", "Over-capacity outfit stays native")
        for index = 1, Clothing.TextureCapacity do
            check(material(owned[index]) == materials[index], "Pinned outfit " .. index .. " not overwritten")
        end
        Clothing:Apply(owned[1], "", "")
        check(Clothing:Apply(extra, overflow, ""), "Overflow retries successfully after a slot releases")
        check(material(extra) == materials[1], "Only released slot reused")
    end
    stepped("capacity_overflow_preserves_outfits_and_recovers", capacitySteps)
    suite:Add("failed_composition_is_retryable", function(check)
        requireCatalogue()
        local entity = model("male")
        Clothing.BuildEquippedFinish = function() return nil, "intentional pool regression failure" end
        check(not Clothing:Apply(entity, shirts[17], pants[1]), "Failed build explicitly returns false")
        check(entity:GetSubMaterial(body(entity)) == "", "Failed build keeps native body")
        Clothing.BuildEquippedFinish = originalBuilder
        check(Clothing:Apply(entity, shirts[17], pants[1]), "Same outfit retries after failure instead of caching failure forever")
    end)
    suite:Add("blood_counterpart_shares_pool_without_replacing_clean_outfit", function(check)
        requireCatalogue()
        local clean, blood, shared = model("male"), model("male"), model("male")
        check(Clothing:Apply(clean, shirts[1], pants[1]), "Clean outfit applies")
        local cleanName = material(clean)
        check(Clothing:Apply(blood, shirts[1], pants[1], true), "Bloody counterpart applies")
        local bloodName = material(blood)
        check(bloodName ~= "" and bloodName ~= cleanName, "Clean and bloody states have independent pinned composites")
        check(Clothing:Apply(shared, shirts[1], pants[1], true) and material(shared) == bloodName,
            "Matching bloody counterparts share one slot")
        check(material(clean) == cleanName, "Blood preview does not overwrite the clean wearer")
        check(Clothing:Apply(blood, shirts[1], pants[1], false) and material(blood) == cleanName,
            "Blood-off returns to the existing clean composite")
        local female = model("female")
        check(Clothing:Apply(female, shirts[1], "", true), "Female shirt-only bloody counterpart applies")
        check(Clothing:Apply(female, "", "") and material(female) == "", "Removing garments restores native skin")
    end)
    suite:Add("blood_build_failure_retries_without_caching_clean_as_success", function(check)
        requireCatalogue()
        local entity = model("female")
        Clothing.BuildEquippedFinish = function(_, sex, mode, slot, shirt, pants, bloody)
            if bloody then return nil, "intentional missing blood overlay" end
            return originalBuilder(Clothing, sex, mode, slot, shirt, pants, bloody)
        end
        check(not Clothing:Apply(entity, "", pants[1], true), "Missing blood layer fails explicitly")
        check(entity:GetSubMaterial(body(entity)) == "", "Failure keeps native appearance")
        Clothing.BuildEquippedFinish = originalBuilder
        check(Clothing:Apply(entity, "", pants[1], true), "Pants-only blood retries after the layer becomes available")
    end)
    suite:Add("blood_flag_rejects_invalid_input_without_changing_clean_outfit", function(check)
        requireCatalogue()
        local entity = model("male")
        check(Clothing:Apply(entity, shirts[1], ""), "Clean outfit applies before invalid input")
        local name = material(entity)
        check(not Clothing:Apply(entity, shirts[1], "", "true"), "String input is not interpreted as a blood flag")
        check(material(entity) == name, "Invalid input retains the current clean composite")
    end)
    local citizenSteps = {}
    for _, sex in ipairs({ "male", "female" }) do
        for number = 1, sex == "male" and 9 or 6 do
            local family, citizen = sex, number
            citizenSteps[#citizenSteps + 1] = function(check)
                requireCatalogue()
                local entity = model(family, citizen)
                check(Clothing:Apply(entity, shirts[1], pants[1], true), family .. citizen .. " bloody outfit applies")
                check(material(entity) ~= "", family .. citizen .. " has an actual body override")
                check(Clothing:Apply(entity, "", "") and material(entity) == "", family .. citizen .. " restores native body")
                entity:Remove()
            end
        end
    end
    citizenSteps[#citizenSteps + 1] = function(check)
        requireCatalogue()
        check(not Clothing:GetPreviewCitizenLayout("models/player/group03/male_01.mdl"), "Rebel has no transfer chart")
        local rebel = ClientsideModel("models/player/group03/male_01.mdl", RENDERGROUP_OTHER)
        if not IsValid(rebel) then error("Could not create rebel exclusion fixture") end
        owned[#owned + 1] = rebel
        rebel:SetNoDraw(true)
        check(Clothing:Apply(rebel, shirts[1], pants[1], true), "Unsupported rebel retains native appearance")
        for index in ipairs(rebel:GetMaterials()) do
            check(rebel:GetSubMaterial(index - 1) == "", "Rebel material " .. index .. " is not replaced")
        end
    end
    stepped("all_calibrated_citizens_apply_restore_and_rebels_remain_native", citizenSteps)
    local summary = { passed = 0, failed = 0, cases = {}, ranAt = os.time() }
    local function finish()
        cleanup()
        local restored = Clothing:GetReferencedTextureSlots()
        local finalSuite = ZM_TestHarness.NewSuite()
        finalSuite:Add("fixture_cleanup_restores_reference_baseline", function(check)
            check(table.Count(restored) == table.Count(baseline), "No test pins remain")
            for slot in pairs(baseline) do check(restored[slot], "Original slot reference retained") end
        end)
        local final = finalSuite:Run()
        summary.passed, summary.failed = summary.passed + final.passed, summary.failed + final.failed
        table.Add(summary.cases, final.cases)
        file.CreateDir("zombiesim")
        file.Write("zombiesim/clothing_pool_tests.json", util.TableToJSON(summary, true))
        for _, result in ipairs(summary.cases) do
            print("[ZombieSim] Clothing pool " .. (result.passed and "PASS " or "FAIL ") .. result.name)
            for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
        end
        print(string.format("[ZombieSim] Clothing pool tests: %d passed, %d failed.", summary.passed, summary.failed))
        runFrame = nil
    end
    local caseIndex, stepIndex, result = 1, 1
    runFrame = function()
        local entry = suite.cases[caseIndex]
        if not entry then finish() return end
        if not result then
            cleanup()
            result = { name = entry.name, failures = {} }
        end
        local step = entry.steps and entry.steps[stepIndex] or entry.body
        local single = ZM_TestHarness.NewSuite()
        single:Add(entry.name, function(check)
            if not ZM_Wardrobe:IsAvailable() then error("Preview admin session ended during pool tests") end
            step(check)
        end)
        local current = single:Run().cases[1]
        for _, failure in ipairs(current.failures) do
            result.failures[#result.failures + 1] = "step " .. stepIndex .. ": " .. failure
        end
        if entry.steps and stepIndex < #entry.steps and ZM_Wardrobe:IsAvailable() then
            stepIndex = stepIndex + 1
        else
            result.passed = #result.failures == 0
            summary[result.passed and "passed" or "failed"] = summary[result.passed and "passed" or "failed"] + 1
            summary.cases[#summary.cases + 1] = result
            caseIndex, stepIndex, result = caseIndex + 1, 1, nil
        end
    end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/clothing_pool_tests.json", util.TableToJSON({ running = true, ranAt = summary.ranAt }, true))
    print("[ZombieSim] Clothing pool tests started; capacity and citizen builds advance one step per frame.")
    runFrame()
end)
