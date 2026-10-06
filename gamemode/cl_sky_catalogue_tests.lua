concommand.Add("zombiesim_dev_test_sky_catalogue", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Sky catalogue tests require a preview admin.\n")
        return
    end
    local Palettes = ZM_SkyPalettes
    if Palettes.CatalogueTestsRunning then
        ErrorNoHalt("[ZombieSim] Sky catalogue tests are already running.\n")
        return
    end
    local suites = {}
    local summary = { passed = 0, failed = 0, cases = {}, running = true, ranAt = os.time() }
    local function add(name, body)
        local suite = ZM_TestHarness.NewSuite()
        suite:Add(name, body)
        suites[#suites + 1] = suite
    end
    add("expanded_catalogue_and_builtin_contexts", function(check)
        check(table.Count(Palettes.Entries) >= 40, "at least forty individual skies")
        check(#Palettes.ProfileOrder >= 6, "at least six automatic profiles")
        check(not Palettes.CatalogueFailure, "permitted imported catalogue loads")
        check(Palettes.Entries.imported_moonlit and Palettes.Entries.imported_moonlit.credit == "Jasper Carmack, Sky_Night01 (2021)",
            "permitted import keeps author credit")
        for _, id in ipairs(Palettes.ProfileOrder) do
            for _, context in ipairs(Palettes.ContextOrder) do
                local resolved, failure = Palettes:Resolve(id, context)
                check(resolved and Palettes.Entries[resolved], id .. "/" .. context .. " resolves: " .. tostring(failure))
            end
        end
    end)
    add("new_automatic_variants_cover_supplied_skies", function(check)
        local used = {}
        for _, id in ipairs({ "cloud_prelude", "terrassee_horizons", "worldsend_horizons",
            "neon_twilight", "alien_embers", "cloudbound" }) do
            local profile = Palettes:GetProfile(id)
            check(profile ~= nil and table.HasValue(Palettes.ProfileOrder, id), id .. " appears in automatic browser")
            if not profile then continue end
            check(Palettes:ValidateCustomProfile(profile), id .. " can be copied into a custom palette")
            for _, context in ipairs(Palettes.ContextOrder) do
                local sky, failure = Palettes:Resolve(id, context)
                check(sky == profile.contexts[context] and Palettes.Entries[sky] ~= nil,
                    id .. "/" .. context .. " resolves exactly: " .. tostring(failure))
                check(Palettes:GetAvailability(sky), id .. "/" .. context .. " has every mounted face")
                check(Palettes:Resolve(id, context) == sky, id .. "/" .. context .. " stays deterministic")
                used[sky] = true
            end
        end
        for _, id in ipairs({ "imported_prelude", "imported_terrassee", "imported_worldsend",
            "imported_alienred", "imported_plainsky",
            "imported_sky1", "imported_waporvave", "imported_mr53" }) do
            check(used[id] == true, id .. " is included in a new automatic variant")
        end
        check(not used.imported_john_tron, "John Tron excluded from automatic variants at the user's request")
        for index = 1, 6 do
            check(used["imported_tropo_cloudy_" .. index] == true, "additional cloud set " .. index .. " is included")
        end
        check(Palettes.Profiles.neon_twilight.label:find("stylized", 1, true) ~= nil and
            Palettes.Profiles.alien_embers.label:find("stylized", 1, true) ~= nil, "fantasy variants are explicitly labelled")
        check(Palettes.Profiles.natural.contexts.day == "natural_day" and
            Palettes.Profiles.tropospheric_4.contexts.dusk == "imported_tropo_dusk_4", "existing profiles retain their assignments")
    end)
    add("automatic_context_weather_and_light_boundaries", function(check)
        local savedAtmosphere, savedSkybox = ZM_Atmosphere, ZM_Skybox
        local fixture = ZM_TestHarness.NewSuite()
        fixture:Add("context_matrix", function(assert)
            local fog = { 24, 48, 72 }
            ZM_Atmosphere = { Weather = "clear", StormIntensity = 0,
                GetFogSettings = function() return { color = fog } end }
            ZM_Skybox = { SceneryLight = { level = 1 } }
            for _, sample in ipairs({
                { level = 1, weather = "clear", storm = 0, expected = "day" },
                { level = 0.7, weather = "clear", storm = 0.25, expected = "day" },
                { level = 0.7, weather = "clear", storm = 0.251, expected = "overcast" },
                { level = 1, weather = "rain", storm = 0, expected = "overcast" },
                { level = 1, weather = "snow", storm = 0, expected = "overcast" },
                { level = 0.699, weather = "rain", storm = 1, expected = "dusk" },
                { level = 0.45, weather = "snow", storm = 1, expected = "dusk" },
                { level = 0.449, weather = "rain", storm = 1, expected = "night" }
            }) do
                ZM_Skybox.SceneryLight.level = sample.level
                ZM_Atmosphere.Weather, ZM_Atmosphere.StormIntensity = sample.weather, sample.storm
                local context, color = Palettes:GetContext()
                assert(context == sample.expected and color == fog, "context/fog for " .. sample.weather .. "/" .. sample.level)
                for _, id in ipairs(Palettes.ProfileOrder) do
                    assert(Palettes:Resolve(id, context) == Palettes.Profiles[id].contexts[sample.expected],
                        id .. " uses the expected weather/light slot")
                end
            end
        end)
        local result = fixture:Run()
        ZM_Atmosphere, ZM_Skybox = savedAtmosphere, savedSkybox
        for _, test in ipairs(result.cases) do
            for _, failure in ipairs(test.failures) do check(false, failure) end
        end
        check(ZM_Atmosphere == savedAtmosphere and ZM_Skybox == savedSkybox, "real atmosphere and skyline owners restored")
    end)
    for id, entry in pairs(Palettes.Entries) do
        if not entry.mounted then continue end
        add("cube_faces_" .. id, function(check)
            local meshes, failure = Palettes:Prepare(id, { 128, 144, 160 })
            check(meshes and #meshes == 6, "six faces resolve: " .. tostring(failure))
            for index, face in ipairs(meshes or {}) do
                local texture = face.material:GetTexture("$basetexture")
                local info = entry.faces and entry.faces[Palettes.MountedFaces[index].suffix]
                local scaleY = info and info.scaleY or 1
                check(not face.material:IsError() and texture:Width() > 0 and texture:Height() > 0,
                    "material and source texture available")
                check(face.triangles == (scaleY > 1 and 4 or 2) and
                    face.samplingInset.u == 0.5 / texture:Width() and
                    face.samplingInset.v == 0.5 / (texture:Height() * scaleY), "bounded face and exact transformed inset sampling")
                if info and info.transform ~= "" then
                    local matrix = face.material:GetMatrix("$basetexturetransform")
                    check(matrix and matrix:GetField(1, 1) == info.scaleX and matrix:GetField(2, 2) == info.scaleY,
                        "authored UV transform is active in the shader")
                end
                face.mesh:Destroy()
            end
        end)
    end
    add("custom_storage_create_edit_reload_delete_and_reject", function(check)
        local savedPath, savedStore, savedFailure = Palettes.CustomPath, table.Copy(Palettes.CustomStore), Palettes.CustomFailure
        local savedSelection = GetConVar("zombiesim_sky_palette"):GetString()
        local path = "zombiesim/sky_custom_test_" .. util.CRC(tostring(SysTime())) .. ".json"
        Palettes.CustomPath, Palettes.CustomFailure = path, nil
        Palettes.CustomStore = { schemaVersion = 1, nextId = 1, profiles = {} }
        local suite = ZM_TestHarness.NewSuite()
        suite:Add("isolated_persistence", function(assert)
            local profile = { label = "Fixture palette", contexts = {
                day = "natural_day", overcast = "natural_overcast", dusk = "cinematic_dusk", night = "imported_moonlit" } }
            local ok, id = Palettes:SaveCustomProfile(nil, profile)
            assert(ok and id == "custom_1", "creates stable unique custom id")
            assert(Palettes:Select(id), "custom profile can be selected")
            for context, expected in pairs(profile.contexts) do
                assert(Palettes:Resolve(id, context) == expected, "custom state resolves " .. context)
            end
            local before = file.Read(path, "DATA")
            local invalid = table.Copy(profile)
            invalid.contexts.night = "natural"
            assert(not Palettes:SaveCustomProfile(id, invalid), "nested automatic profile rejected")
            assert(file.Read(path, "DATA") == before, "invalid save preserves stored JSON")
            invalid = table.Copy(profile)
            invalid.contexts.night = nil
            assert(not Palettes:SaveCustomProfile(id, invalid), "missing context rejected")
            profile.label, profile.contexts.night = "Renamed palette", "default"
            assert(Palettes:SaveCustomProfile(id, profile), "edit retains id")
            assert(Palettes:LoadCustomProfiles(), "custom file reloads")
            assert(Palettes.CustomStore.profiles[id].label == "Renamed palette", "rename survives reload")
            assert(Palettes:Resolve(id, "night") == nil, "native sky can fill one custom state")
            assert(Palettes:DeleteCustomProfile(id), "delete saved custom profile")
            assert(GetConVar("zombiesim_sky_palette"):GetString() == "default", "deleting active profile restores map sky")
            assert(Palettes:LoadCustomProfiles() and not Palettes.CustomStore.profiles[id], "delete survives reload")
            assert(not Palettes:ValidateCustomStore({ schemaVersion = 99, profiles = {} }), "bad schema rejected")
            local broken = { schemaVersion = 1, nextId = 1, profiles = { custom_2 = profile } }
            assert(not Palettes:ValidateCustomStore(broken), "invalid allocator rejected")
        end)
        local result = suite:Run()
        Palettes.CustomPath, Palettes.CustomStore, Palettes.CustomFailure = savedPath, savedStore, savedFailure
        Palettes:Select(savedSelection)
        file.Delete(path)
        file.Delete(path .. ".backup.json")
        for _, test in ipairs(result.cases) do
            for _, failure in ipairs(test.failures) do check(false, failure) end
        end
    end)
    Palettes.CatalogueTestsRunning = true
    file.CreateDir("zombiesim")
    file.Write("zombiesim/sky_catalogue_tests.json", util.TableToJSON(summary, true))
    local index = 1
    timer.Create("ZM.SkyCatalogue.Tests", 0, 0, function()
        local part = suites[index]:Run()
        for _, result in ipairs(part.cases) do
            summary.cases[#summary.cases + 1] = result
            summary[result.passed and "passed" or "failed"] = summary[result.passed and "passed" or "failed"] + 1
            print("[ZombieSim] Sky catalogue " .. (result.passed and "PASS " or "FAIL ") .. result.name)
            for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
        end
        index = index + 1
        if index > #suites then
            timer.Remove("ZM.SkyCatalogue.Tests")
            summary.running, Palettes.CatalogueTestsRunning = false, false
        end
        file.Write("zombiesim/sky_catalogue_tests.json", util.TableToJSON(summary, true))
    end)
end)
