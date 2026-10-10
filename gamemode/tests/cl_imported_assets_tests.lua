local suite = ZM_TestHarness.NewSuite()

local function checkModel(check, path)
    local meshes = util.GetModelMeshes(path, 0)
    check(type(meshes) == "table" and #meshes > 0, path .. ": no client mesh")
    if type(meshes) ~= "table" then return end
    for _, part in ipairs(meshes) do
        check(#part.triangles > 0, path .. ": empty mesh")
        local material = Material(part.material)
        check(not material:IsError(), path .. ": error material " .. part.material)
        local texture = material:GetTexture("$basetexture")
        check(texture and texture:Width() > 1 and texture:Height() > 1, path .. ": missing base texture " .. part.material)
    end
end

for _, class in ipairs({ "weapon_zn_hammer", "weapon_zn_machete", "weapon_zn_spanner", "weapon_zn_lewis" }) do
    local weaponClass = class
    suite:Add(weaponClass .. "_client_meshes_and_textures", function(check)
        local weapon = weapons.Get(weaponClass)
        check(weapon ~= nil, "weapon registration")
        if not weapon then return end
        checkModel(check, weapon.ViewModel)
        checkModel(check, weapon.WorldModel)
    end)
end
suite:Add("hev_client_meshes_and_textures", function(check)
    checkModel(check, "models/zombiesim/imported/hev/motorhead/hevscientist.mdl")
    checkModel(check, "models/zombiesim/imported/hev/armhead/v_hand.mdl")
end)

concommand.Add("zombiesim_dev_test_imported_assets_client", function()
    if not ZM_Wardrobe:IsAvailable() then
        ErrorNoHalt("[ZombieSim] Imported asset client tests require a preview admin.\n")
        return
    end
    local summary = suite:Run()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/imported_assets_client_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
    end
    print(string.format("[ZombieSim] Imported asset client tests: %d passed, %d failed.", summary.passed, summary.failed))
end)
