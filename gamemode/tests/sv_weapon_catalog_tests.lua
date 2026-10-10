// Server-side runtime contract tests for the first Alpha 2.8 CSS-inspired weapon batch.
local catalog = {
    weaponUsp9mm = {
        class = "weapon_zn_usp_9mm", ammo = "ammo9mm", mode = "semi_auto",
        view = "models/weapons/cstrike/c_pist_usp.mdl", world = "models/weapons/w_pist_usp.mdl"
    },
    weaponAutoPistol9mm = {
        class = "weapon_zn_auto_pistol_9mm", ammo = "ammo9mm", mode = "automatic",
        view = "models/weapons/cstrike/c_pist_glock18.mdl", world = "models/weapons/w_pist_glock18.mdl"
    },
    weaponMp5 = {
        class = "weapon_zn_mp5", ammo = "ammo9mm", mode = "automatic",
        view = "models/weapons/cstrike/c_smg_mp5.mdl", world = "models/weapons/w_smg_mp5.mdl"
    },
    weaponM4a1 = {
        class = "weapon_zn_m4a1", ammo = "ammo556", mode = "automatic",
        view = "models/weapons/cstrike/c_rif_m4a1.mdl", world = "models/weapons/w_rif_m4a1.mdl"
    },
    weaponAk47 = {
        class = "weapon_zn_ak47", ammo = "ammo762", mode = "automatic",
        view = "models/weapons/cstrike/c_rif_ak47.mdl", world = "models/weapons/w_rif_ak47.mdl"
    },
    weaponShotgunM3 = {
        class = "weapon_zn_shotgun_m3", ammo = "ammoShells", mode = "semi_auto",
        view = "models/weapons/cstrike/c_shot_m3super90.mdl", world = "models/weapons/w_shot_m3super90.mdl"
    },
    weaponScout = {
        class = "weapon_zn_scout", ammo = "ammo762", mode = "semi_auto",
        view = "models/weapons/cstrike/c_snip_scout.mdl", world = "models/weapons/w_snip_scout.mdl"
    },
    weaponAwp = {
        class = "weapon_zn_awp", ammo = "ammo50Bmg", mode = "semi_auto",
        view = "models/weapons/cstrike/c_snip_awp.mdl", world = "models/weapons/w_snip_awp.mdl"
    }
}

local function runTests(caller)
    local failures = {}
    local registry = ZM_StaticData:GetRegistry()
    local cs16Count = 0
    for itemId, item in pairs(registry and registry.items or {}) do
        if item.type == "bullet_weapon" then
            local cs16 = string.StartWith(itemId, "weaponCs16")
            if cs16 then cs16Count = cs16Count + 1 end
            catalog[itemId] = catalog[itemId] or {
                class = item.weaponClass, ammo = item.ammoId, mode = item.firingMode,
                view = item.viewModel or "models/weapons/c_pistol.mdl",
                world = item.worldModel or "models/weapons/w_pistol.mdl", cs16 = cs16
            }
        end
    end
    if cs16Count ~= 24 then
        table.insert(failures, "Expected 24 CS 1.6 firearms, found " .. cs16Count)
    end
    for itemId, expected in SortedPairs(catalog) do
        local item = registry and registry.items[itemId]
        if not item then
            table.insert(failures, itemId .. " is missing from the loaded item registry")
        else
            if item.weaponClass ~= expected.class then
                table.insert(failures, itemId .. " maps to " .. tostring(item.weaponClass) .. ", expected " .. expected.class)
            end
            if item.ammoId ~= expected.ammo then
                table.insert(failures, itemId .. " maps to " .. tostring(item.ammoId) .. ", expected " .. expected.ammo)
            end
            if item.firingMode ~= expected.mode then
                table.insert(failures, itemId .. " has the wrong firing mode")
            end
            if item.viewModel and (item.viewModel ~= expected.view or item.worldModel ~= expected.world) then
                table.insert(failures, itemId .. " model mapping does not match the catalog contract")
            end

            local weapon = weapons.Get(expected.class)
            if not weapon then
                table.insert(failures, expected.class .. " is not registered")
            else
                local expectedBase = expected.cs16 and "weapon_zn_base_cs16" or "weapon_zn_base_hitscan"
                if expected.class == "weapon_zn_hl2_shotgun" then expectedBase = "weapon_zn_shotgun_m3" end
                if weapon.Base ~= expectedBase then
                    table.insert(failures, expected.class .. " does not inherit the ZombieSim hitscan base")
                end
                if weapon.ViewModel ~= expected.view or weapon.WorldModel ~= expected.world then
                    table.insert(failures, expected.class .. " SWEP model paths do not match the item registry")
                end
                local automatic = weapon.Primary and weapon.Primary.Automatic == true
                if automatic ~= (expected.mode == "automatic") then
                    table.insert(failures, expected.class .. " automatic flag does not match its firing mode")
                end
                if expected.class ~= "weapon_zn_handgun_9mm" then
                    for _, key in ipairs({ "FireSound", "ReloadSound", "ReloadFinishSound" }) do
                        if not weapon[key] or not file.Exists("sound/" .. weapon[key], "GAME") then
                            table.insert(failures, expected.class .. " has missing " .. key)
                        end
                    end
                end
                if expected.cs16 then
                    local model = ents.Create("prop_dynamic")
                    if not IsValid(model) then
                        table.insert(failures, "Could not create CS 1.6 sequence test model")
                    else
                        model:SetModel(expected.view)
                        local base = weapons.GetStored("weapon_zn_base_cs16")
                        for _, key in ipairs({ "IdleSequence", "DrawSequence", "FireSequence", "ReloadSequence" }) do
                            local name = weapon[key] or base[key]
                            if model:LookupSequence(name) < 0 then
                                table.insert(failures, expected.class .. " is missing sequence " .. name)
                            end
                        end
                        model:Remove()
                    end
                end
            end
            if not util.IsValidModel(expected.view) then
                table.insert(failures, expected.view .. " is not mounted/valid")
            end
            if not util.IsValidModel(expected.world) then
                table.insert(failures, expected.world .. " is not mounted/valid")
            end
        end
    end

    if table.Count(catalog) ~= 55 then
        table.insert(failures, "Expected 55 ranged weapon mappings, found " .. table.Count(catalog))
    end
    local passed = #failures == 0
    local lines = { string.format("Weapon catalog runtime test: %d weapon mappings checked, %d failure(s).", table.Count(catalog), #failures) }
    for _, failure in ipairs(failures) do
        table.insert(lines, "FAIL " .. failure)
    end
    for _, line in ipairs(lines) do
        ZM_Util.Reply(caller, line)
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("weaponCatalogTests", { passed = passed, checked = table.Count(catalog), failures = failures })
    end
    if not passed then
        return false, "weapon catalog runtime validation failed"
    end
    return true
end

concommand.Add("zn_test_weapon_catalog", function(caller)
    if not ZM_Util.RequireAdmin(caller, "zn_test_weapon_catalog") then return end
    runTests(caller)
end, nil, "Checks local SWEP registration, CSS model mounts, item mappings, and firing modes.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zn_test_weapon_catalog = function()
    return runTests(nil)
end
