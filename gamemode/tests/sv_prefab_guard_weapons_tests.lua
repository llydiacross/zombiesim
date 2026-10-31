return function(createCatalog)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("guard weapon choices reuse validated firearm data", function(check)
        local state = { bad = false, missing = false, invalid = false }
        local definitions = {
            { id = "pistol", label = "9mm Handgun", class = "weapon_zn_handgun_9mm",
                idle = "idle_pistol", attack = "range_pistol" },
            { id = "smg", label = "HL2 SMG", class = "weapon_zn_hl2_smg",
                idle = "idle_smg1", attack = "range_smg1" }
        }
        local weapons = {
            weapon_zn_handgun_9mm = { WorldModel = "pistol.mdl", FireSound = "pistol",
                BulletDamage = 12, BulletSpread = 0.02, BulletForce = 2.5, BulletRange = 3000, BulletCount = 1, FireDelay = 0.18 },
            weapon_zn_hl2_smg = { WorldModel = "smg.mdl", FireSound = "smg",
                BulletDamage = 12, BulletSpread = 0.03, BulletForce = 2.5, BulletRange = 4096, BulletCount = 1, FireDelay = 0.09 }
        }
        local catalog = createCatalog({
            weapons = { Get = function(id) return not state.bad and weapons[id] or nil end },
            file = { Read = function(path, realm)
                assert(path == "data_static/prefab_guard_weapons.json" and realm == "GAME")
                return not state.missing and "fixture" or nil
            end },
            util = {
                JSONToTable = function() return not state.invalid and definitions or {} end,
                IsValidModel = function(model) return model == "pistol.mdl" or model == "smg.mdl" end
            }
        })
        local list = catalog.List()
        check(list and #list == 2 and list[1].id == "pistol" and list[2].id == "smg",
            "the candidate subset has stable IDs and order")
        check(list and list[1].damage == 12 and list[1].range == 3000 and list[2].delay == 0.09,
            "damage, range and cadence come from existing firearms")
        check(not catalog.Resolve("unknown"), "unknown weapons are rejected")
        state.bad = true
        local missing, problem = catalog.List()
        check(not missing and problem ~= nil, "missing weapon data is reported")
        local broken = createCatalog({
            weapons = { Get = function(id) return weapons[id] end },
            file = { Read = function() return nil end },
            util = { JSONToTable = function() return definitions end, IsValidModel = function() return true end }
        })
        local unavailable, missingError = broken.List()
        check(not unavailable and type(missingError) == "string", "missing static catalogue is reported")
        local invalid = createCatalog({
            weapons = { Get = function(id) return weapons[id] end },
            file = { Read = function() return "fixture" end },
            util = { JSONToTable = function() return { definitions[1], definitions[1] } end,
                IsValidModel = function() return true end }
        })
        check(not invalid.List(), "duplicate static weapon IDs are rejected")
    end)
    return suite
end
