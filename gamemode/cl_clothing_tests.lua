// Actual client-model pool regressions. Run in PreRender; own and remove every fixture.
local requested = false
local Clothing = ZM_Clothing

concommand.Add("zombiesim_dev_test_clothing_pool", function()
    if not ZM_Wardrobe:IsAvailable() then
        ErrorNoHalt("[ZombieSim] Clothing pool tests require a preview admin.\n")
        return
    end
    requested = true
end)

hook.Add("PreRender", "ZM.Clothing.PoolTests", function()
    if not requested then return end
    requested = false
    if not ZM_Wardrobe:IsAvailable() then return end
    local owned, shirts, pants = {}, {}, {}
    local originalBuilder = Clothing.BuildEquippedFinish
    local suite = ZM_TestHarness.NewSuite()
    local function cleanup()
        Clothing.BuildEquippedFinish = originalBuilder
        for _, entity in ipairs(owned) do
            if IsValid(entity) then Clothing:Apply(entity, "", "") entity:Remove() end
        end
        owned = {}
    end
    local function model(sex)
        local entity = ClientsideModel("models/player/group01/" .. (sex == "female" and "female_01" or "male_03") .. ".mdl", RENDERGROUP_OTHER)
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
        if not Clothing.CatalogueReady or #shirts < 17 or #pants < 1 then
            error("Pool tests need a built catalogue with at least 17 shirts and one pants finish")
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
    suite:Add("capacity_overflow_preserves_outfits_and_recovers", function(check)
        requireCatalogue()
        if next(baseline) then error("Close dressed UI and unequip live clothes before the isolated full-capacity test") end
        local materials = {}
        for index = 1, Clothing.TextureCapacity do
            local entity = model("male")
            check(Clothing:Apply(entity, shirts[index], ""), "Distinct outfit " .. index .. " applies")
            materials[index] = material(entity)
        end
        check(table.Count(Clothing:GetReferencedTextureSlots()) == Clothing.TextureCapacity, "Exactly sixteen slots pinned")
        local extra = model("male")
        check(not Clothing:Apply(extra, shirts[17], "") and material(extra) == "", "Seventeenth outfit stays native")
        for index = 1, Clothing.TextureCapacity do
            check(material(owned[index]) == materials[index], "Pinned outfit " .. index .. " not overwritten")
        end
        Clothing:Apply(owned[1], "", "")
        check(Clothing:Apply(extra, shirts[17], ""), "Overflow retries successfully after a slot releases")
        check(material(extra) == materials[1], "Only released slot reused")
    end)
    suite:Add("failed_composition_is_retryable", function(check)
        requireCatalogue()
        local entity = model("male")
        Clothing.BuildEquippedFinish = function() return nil, "intentional pool regression failure" end
        check(not Clothing:Apply(entity, shirts[17], pants[1]), "Failed build explicitly returns false")
        check(entity:GetSubMaterial(body(entity)) == "", "Failed build keeps native body")
        Clothing.BuildEquippedFinish = originalBuilder
        check(Clothing:Apply(entity, shirts[17], pants[1]), "Same outfit retries after failure instead of caching failure forever")
    end)
    local summary = suite:Run({ before = cleanup, after = cleanup })
    local restored = Clothing:GetReferencedTextureSlots()
    suite = ZM_TestHarness.NewSuite()
    suite:Add("fixture_cleanup_restores_reference_baseline", function(check)
        check(table.Count(restored) == table.Count(baseline), "No test pins remain")
        for slot in pairs(baseline) do check(restored[slot], "Original slot reference retained") end
    end)
    local final = suite:Run()
    summary.passed, summary.failed = summary.passed + final.passed, summary.failed + final.failed
    table.Add(summary.cases, final.cases)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/clothing_pool_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Clothing pool " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
    end
    print(string.format("[ZombieSim] Clothing pool tests: %d passed, %d failed.", summary.passed, summary.failed))
end)
