local suite = ZM_TestHarness.NewSuite()
local owned = {}
local originalCharacter = ZM_CharacterService.GetActiveCharacter
local testTarget

local function makeModel(path)
    local entity = ents.Create("prop_dynamic")
    if not IsValid(entity) then error("Imported model fixture could not be created") end
    owned[#owned + 1] = entity
    entity:SetModel(path)
    return entity
end

suite:Add("imported_models_materials_and_named_sequences_are_mounted", function(check)
    for _, class in ipairs({ "weapon_zn_hammer", "weapon_zn_machete", "weapon_zn_spanner", "weapon_zn_lewis" }) do
        local weapon = weapons.Get(class)
        check(weapon ~= nil, class .. " registration")
        if not weapon then continue end
        for _, path in ipairs({ weapon.ViewModel, weapon.WorldModel }) do
            check(util.IsValidModel(path), path .. " model validity")
            local model = makeModel(path)
            check(model:GetBoneCount() > 0, path .. " model bones")
            for _, material in ipairs(model:GetMaterials()) do
                check(file.Exists("materials/" .. material .. ".vmt", "GAME"), path .. " missing material " .. material)
            end
        end
        local view = makeModel(weapon.ViewModel)
        local names = class == "weapon_zn_lewis" and { "base_draw", "base_idle", "base_fire_1", "base_reload" }
            or { weapon.DrawSequence, weapon.IdleSequence, weapon.HitSequence, weapon.MissSequence }
        for _, name in ipairs(names) do check(view:LookupSequence(name) >= 0, class .. " missing sequence " .. name) end
        if class == "weapon_zn_hammer" then
            local model = makeModel(weapon.WorldModel)
            check(#model:GetMaterials() == 1 and string.find(model:GetMaterials()[1], "hammer", 1, true),
                "derived hammer must not contain hand materials")
        end
    end
    for _, path in ipairs({
        "models/zombiesim/imported/hev/motorhead/hevscientist.mdl",
        "models/zombiesim/imported/hev/armhead/v_hand.mdl"
    }) do
        local model = makeModel(path)
        check(util.IsValidModel(path) and model:GetBoneCount() > 0, path .. " valid skeleton")
        check(model:LookupBone("ValveBiped.Bip01_R_Hand") ~= nil, path .. " compatible hand bone")
        for _, material in ipairs(model:GetMaterials()) do
            check(file.Exists("materials/" .. material .. ".vmt", "GAME"), path .. " missing material " .. material)
        end
    end
end)

suite:Add("imported_melee_preserves_attributes_hit_miss_and_den_holster", function(check)
    for _, class in ipairs({ "weapon_zn_hammer", "weapon_zn_machete", "weapon_zn_spanner" }) do
        local base = weapons.Get(class)
        local weapon = setmetatable({}, { __index = base })
        local target = makeModel("models/props_junk/PopCan01a.mdl")
        target:SetPos(Vector(0, 0, 12000))
        target:Spawn()
        local owner = {
            IsValid = function() return true end,
            GetLevelAim = function() return Vector(0, 0, 12000), Vector(1, 0, 0) end,
            SetAnimation = function() end,
            LagCompensation = function() end
        }
        weapon.GetOwner = function() return owner end
        weapon.IsSafeZoneHolstered = function() return owner.den == true end
        weapon.GetScale = function() return 1.5 end
        weapon.SetNextPrimaryFire = function(self, value) self.nextFire = value end
        weapon.SendWeaponAnim = function(self, value) self.animation = value end
        weapon.PlaySound = function(self, value) self.sound = value end
        local originalTrace = util.TraceHull
        local traceData
        local hit = false
        util.TraceHull = function(data)
            traceData = data
            return { Hit = hit, Entity = NULL, HitPos = data.endpos }
        end
        local ok, failure = xpcall(function()
            weapon:PrimaryAttack()
            check(weapon.animation == ACT_VM_MISSCENTER and weapon.sound == weapon.SwingSound, class .. " miss")
            check(traceData.endpos.x == base.MeleeRange * 1.5, class .. " range attribute")
            check(math.abs(weapon.nextFire - CurTime() - base.MeleeDelay * 1.5) < 0.01, class .. " speed attribute")
            check(weapon:GetScaledDamage(base.MeleeDamage) == base.MeleeDamage * 1.5, class .. " damage attribute")
            hit = true
            weapon:PrimaryAttack()
            check(weapon.animation == ACT_VM_HITCENTER and weapon.sound == weapon.HitWorldSound, class .. " wall hit")
            traceData = nil
            owner.den = true
            weapon:PrimaryAttack()
            check(traceData == nil, class .. " den holster")
        end, debug.traceback)
        util.TraceHull = originalTrace
        if not ok then error(failure) end
    end
end)

suite:Add("radiation_suit_switches_model_hands_and_restores_saved_appearance", function(check)
    local model = makeModel("models/player/group01/male_01.mdl")
    local hands = makeModel("models/weapons/c_arms_citizen.mdl")
    local character = {
        appearanceRequired = 0, model = "models/player/group01/male_01.mdl", skin = 0,
        bodygroups = "{}", playerColour = "[0.25,0.5,0.75]"
    }
    local saved = util.TableToJSON(character)
    testTarget = {
        ZM_PersistentStateLoaded = true,
        ZM_Inventory = ZM_InventoryService.NewInventory(),
        HasRadiationProtection = function(self) return ZM_Items:HasRadiationProtection(self.ZM_Inventory) end,
        SetModel = function(_, path) model:SetModel(path) end,
        GetModel = function() return model:GetModel() end,
        SetSkin = function(_, skin) model:SetSkin(skin) end,
        GetBodyGroups = function() return model:GetBodyGroups() end,
        SetBodygroup = function(_, id, value) model:SetBodygroup(id, value) end,
        SetPlayerColor = function(self, colour) self.colour = colour end,
        GetHands = function() return hands end
    }
    ZM_CharacterService.GetActiveCharacter = function(self, target)
        if target == testTarget then return character end
        return originalCharacter(self, target)
    end
    ZM_InventoryService:RefreshWearableAppearance(testTarget)
    check(model:GetModel() == character.model and testTarget.ZM_HEVAppearance == false, "ordinary appearance")
    testTarget.ZM_Inventory.backpack[1] = { itemId = "itemRadiationSuit" }
    ZM_InventoryService:RefreshWearableAppearance(testTarget)
    check(model:GetModel() == character.model, "carried suit must not change appearance")
    testTarget.ZM_Inventory.equipped[ZM_Items.ArmourSlot] = testTarget.ZM_Inventory.backpack[1]
    testTarget.ZM_Inventory.backpack[1] = nil
    ZM_InventoryService:RefreshWearableAppearance(testTarget)
    check(model:GetModel() == "models/zombiesim/imported/hev/motorhead/hevscientist.mdl", "worn suit model")
    check(hands:GetModel() == "models/zombiesim/imported/hev/armhead/v_hand.mdl", "worn suit hands")
    testTarget.ZM_Inventory.equipped[ZM_Items.ArmourSlot] = nil
    ZM_InventoryService:RefreshWearableAppearance(testTarget)
    check(model:GetModel() == character.model and testTarget.ZM_HEVAppearance == false, "removing suit restores model")
    check(hands:GetModel() ~= "models/zombiesim/imported/hev/armhead/v_hand.mdl", "removing suit restores hands")
    check(testTarget.colour == Vector(0.25, 0.5, 0.75), "saved player colour retained")
    check(util.TableToJSON(character) == saved, "armour must not rewrite character appearance")
end)

ZM_TestHarness.Register({
    command = "zn_test_imported_assets", label = "Imported assets",
    file = "imported_assets_test_results.json", report = "importedAssetsTests",
    help = "Checks imported weapon assets, melee contracts and radiation-suit appearance without changing a survivor.",
    run = function()
        return suite:Run({
            after = function()
                ZM_CharacterService.GetActiveCharacter = originalCharacter
                testTarget = nil
                for _, entity in ipairs(owned) do if IsValid(entity) then entity:Remove() end end
                owned = {}
            end
        })
    end
})
