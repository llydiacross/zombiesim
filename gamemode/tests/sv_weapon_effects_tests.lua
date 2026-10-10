local suite = ZM_TestHarness.NewSuite()
local Effects = ZM_WeaponEffects

suite:Add("preview_prop_probe_is_registered_without_firing", function(check)
    check(type(concommand.GetTable().zombiesim_dev_muzzle_blast_probe) == "function", "console probe is not registered")
    check(type(ZM_DevConsole.DirectCommands.zombiesim_dev_muzzle_blast_probe) == "function", "bridge probe is not registered")
end)

suite:Add("firearm_profiles_match_inventory_ammunition_and_mounted_casings", function(check)
    local registry = ZM_StaticData:GetRegistry()
    local checked = 0
    for id, item in pairs(registry.items) do
        local weapon = item.weaponClass and weapons.Get(item.weaponClass)
        if weapon and item.type == "bullet_weapon" then
            local profile = Effects.Profiles[weapon.FirePresentation]
            check(profile ~= nil, id .. ": missing effect profile")
            if profile then
                check(profile.ammo == item.ammoId, id .. ": casing profile disagrees with ammunition")
                if profile.casing then check(util.IsValidModel(profile.casing), id .. ": casing model is not mounted") end
                if not profile.projectile then
                    check(profile.flash > 0 and profile.smoke > 0 and profile.scale > 0, id .. ": invalid effect sizes")
                end
            end
            check(weapon.BulletCount <= Effects.Limits.pellets, id .. ": pellet budget exceeded")
            if item.weaponClass ~= "weapon_zn_handgun_9mm" then
                for _, field in ipairs({ "FireSound", "ReloadSound", "ReloadFinishSound" }) do
                    local path = weapon[field]
                    local prefix = weapon.Base == "weapon_zn_base_cs16" and "zombiesim/cs16/weapons/" or "weapons/"
                    if item.weaponClass == "weapon_zn_lewis" then prefix = "zombiesim/imported/lewis/" end
                    check(type(path) == "string" and string.StartWith(path, prefix)
                        and file.Exists("sound/" .. path, "GAME"), id .. ": missing mounted firearm audio " .. field)
                end
            end
            checked = checked + 1
        end
    end
    check(checked == 55, "all 55 supported ranged weapons must be checked")
    check(weapons.GetStored("weapon_zn_base_melee").FirePresentation == nil, "melee must not inherit firearm effects")
end)

local function fixture(class)
    local base = weapons.Get(class or "weapon_zn_base_hitscan")
    local weapon = setmetatable({ rounds = 3, firingCalls = 0 }, { __index = base })
    weapon.IsSafeZoneHolstered = weapons.GetStored("weapon_zn_base").IsSafeZoneHolstered
    weapon.GetScale = function() return 1 end
    weapon.Clip1 = function(self) return self.rounds end
    weapon.SetClip1 = function(self, value) self.rounds = value end
    weapon.IsReloading = function(self) return self.reloading == true end
    weapon.SetNextPrimaryFire = function(self, value) self.nextFire = value end
    weapon.SendWeaponAnim = function() end
    weapon.PlaySound = function() end
    weapon.Reload = function(self) self.reloadRequested = true end
    weapon.GetScaledDelay = function(_, value) return value end
    weapon.GetScaledDamage = function(_, value) return value end
    weapon.recoilPitch, weapon.recoilYaw, weapon.recoilTime = 0, 0, 0
    weapon.GetRecoilPitchOffset = function(self) return self.recoilPitch end
    weapon.GetRecoilYawOffset = function(self) return self.recoilYaw end
    weapon.GetRecoilUpdatedAt = function(self) return self.recoilTime end
    weapon.SetRecoilPitchOffset = function(self, value) self.recoilPitch = value end
    weapon.SetRecoilYawOffset = function(self, value) self.recoilYaw = value end
    weapon.SetRecoilUpdatedAt = function(self, value) self.recoilTime = value end
    local owner = {
        IsValid = function() return true end,
        GetLevelAim = function() return Vector(0, 0, 64), Vector(1, 0, 0) end,
        SetAnimation = function() end,
        LagCompensation = function(self, value) self.lagCompensation = value end
    }
    owner.FireBullets = function(_, bullet)
        weapon.firingCalls = weapon.firingCalls + 1
        weapon.lastBullet = bullet
        for index = 1, bullet.Num do
            bullet.Callback(owner, {
                HitPos = Vector(200, index * 3, 64 + index), HitNormal = Vector(-1, 0, 0),
                MatType = MAT_CONCRETE, Hit = true, HitSky = false
            })
        end
    end
    weapon.GetOwner = function() return owner end
    return weapon, owner
end

suite:Add("bullet_data_preserves_ballistics_and_records_actual_spread_endpoints", function(check)
    local weapon, owner = fixture()
    weapon.BulletCount = 9
    weapon.GetScale = function() return 1.5 end
    weapon.GetScaledDamage = function(_, damage) return damage * 2 end
    local source, direction = owner:GetLevelAim()
    local impacts = {}
    local bullet = weapon:GetBulletData(owner, source, direction, impacts)
    check(bullet.Num == 9 and bullet.Src == source and bullet.Dir == direction, "bullet count/source/aim changed")
    check(bullet.Spread == Vector(weapon.BulletSpread, weapon.BulletSpread, 0), "spread changed")
    check(bullet.Force == weapon.BulletForce and bullet.Attacker == owner, "force/attacker changed")
    check(bullet.Damage == weapon.BulletDamage * 2 and bullet.Distance == weapon.BulletRange * 1.5, "damage/range scaling changed")
    check(bullet.Tracer == 0, "stock tracers must not duplicate presentation tracers")
    for index = 1, 9 do
        local point = Vector(100, index * 7, index * 5)
        local normal = Vector(0, 0, 1)
        local result = bullet.Callback(owner, { HitPos = point, HitNormal = normal, MatType = MAT_DIRT, Hit = true })
        check(impacts[index].position == point, "pellet endpoint was replaced by the central aim ray")
        check(impacts[index].normal == normal and impacts[index].material == MAT_DIRT and impacts[index].hit,
            "dust surface metadata was lost")
        check(result == nil, "presentation must not suppress damage or impact effects")
    end
    check(weapon:GetBulletData(owner, source, direction, nil).Callback == nil, "client prediction must not collect server effects")
end)

local sentShots
suite:Add("failed_round_retains_ammo_without_presentation", function(check)
    local weapon = fixture("weapon_zn_hl2_crossbow")
    local attempts = 0
    weapon.FireRound = function(self)
        attempts = attempts + 1
        check(self.rounds == 2, "round must be reserved before damage can reenter firing")
        return false
    end
    sentShots = {}
    weapon:PrimaryAttack()
    check(attempts == 1 and weapon.rounds == 3, "failed round must restore its clip")
    check(#sentShots == 0 and not weapon.blastCalls, "failed projectile must not present a hitscan shot")
    weapon.reloading = true
    weapon:PrimaryAttack()
    check(attempts == 1, "reloading must block projectiles")
end)

suite:Add("rare_cs16_bonuses_stack_with_instance_attributes", function(check)
    local mappings = { usp = "weaponUsp9mm", glock18 = "weaponAutoPistol9mm", m3 = "weaponShotgunM3" }
    local registry = ZM_StaticData:GetRegistry()
    local checked = 0
    for id, item in pairs(registry.items) do
        if string.StartWith(id, "weaponCs16") then
            local family = string.sub(item.cssFamily, 6)
            local counterpartId = mappings[family]
            if not counterpartId then
                for candidateId, candidate in pairs(registry.items) do
                    if candidate.cssFamily == family then counterpartId = candidateId break end
                end
            end
            local counterpart = counterpartId and registry.items[counterpartId]
            check(counterpart ~= nil, id .. ": missing normal counterpart")
            if counterpart then
                local rare = setmetatable({}, { __index = weapons.Get(item.weaponClass) })
                local normal = setmetatable({}, { __index = weapons.Get(counterpart.weaponClass) })
                for _, weapon in ipairs({ rare, normal }) do
                    for _, name in ipairs({ "DamageScale", "RangeScale", "SpeedScale", "ReloadScale", "ClipScale" }) do
                        weapon["Get" .. name] = function() return 1.5 end
                    end
                end
                local function near(a, b) return math.abs(a - b) < 0.00001 end
                check(near(rare:GetScaledDamage(rare.BulletDamage), normal:GetScaledDamage(normal.BulletDamage) * 1.25), id .. ": damage bonus")
                check(near(rare.BulletRange * rare:GetScale("RangeScale"), normal.BulletRange * normal:GetScale("RangeScale") * 1.2), id .. ": range bonus")
                check(near(rare:GetScaledDelay(rare.FireDelay), normal:GetScaledDelay(normal.FireDelay) / 1.15), id .. ": firing speed bonus")
                check(near(rare.ReloadTime * rare:GetScale("ReloadScale"), normal.ReloadTime * normal:GetScale("ReloadScale") / 1.15), id .. ": reload bonus")
                check(rare:GetMaxClip() == math.Round(normal.BaseClipSize * 1.5 * 1.2), id .. ": clip bonus")
                check(rare.Primary.Automatic == normal.Primary.Automatic, id .. ": firing mode mismatch")
            end
            checked = checked + 1
        end
    end
    check(checked == 24, "all 24 rare variants must be compared")
end)

suite:Add("new_css_and_hl2_hitscan_weapons_fire_once_and_holster", function(check)
    local count = 0
    for id, item in pairs(ZM_StaticData:GetRegistry().items) do
        if item.type == "bullet_weapon" and not string.StartWith(id, "weaponCs16")
            and item.weaponClass ~= "weapon_zn_hl2_crossbow" then
            local weapon, owner = fixture(item.weaponClass)
            sentShots = {}
            weapon:PrimaryAttack()
            check(weapon.rounds == 2 and weapon.firingCalls == 1, id .. ": one round per shot")
            check(#sentShots == 1 and #sentShots[1].impacts == weapon.BulletCount, id .. ": pellet count")
            check(weapon.lastBullet.Damage == weapon.BulletDamage, id .. ": damage")
            check(weapon.lastBullet.Distance == weapon.BulletRange, id .. ": range")
            owner.CurrentSafeZoneId = "test-den"
            weapon:PrimaryAttack()
            check(weapon.rounds == 2 and weapon.firingCalls == 1, id .. ": den holster")
            count = count + 1
        end
    end
    check(count == 30, "all 30 normal hitscan weapons must fire")
end)

suite:Add("pulse_damage_is_energy_and_does_not_eject_brass", function(check)
    local weapon, owner = fixture("weapon_zn_hl2_pulse")
    local bullet = weapon:GetBulletData(owner, vector_origin, Vector(1, 0, 0), {})
    local damage = DamageInfo()
    bullet.Callback(owner, { HitPos = vector_origin, HitNormal = vector_up, MatType = MAT_METAL, Hit = true }, damage)
    check(damage:GetDamageType() == DMG_ENERGYBEAM, "pulse damage type")
    check(Effects.Profiles.pulse.casing == false, "pulse must not eject conventional brass")
end)

suite:Add("all_cs16_firearms_use_scaled_hitscan_and_den_holstering", function(check)
    local checked = 0
    for id, item in pairs(ZM_StaticData:GetRegistry().items) do
        if string.StartWith(id, "weaponCs16") then
            local weapon, owner = fixture(item.weaponClass)
            sentShots = {}
            weapon:PrimaryAttack()
            check(weapon.rounds == 2 and weapon.firingCalls == 1, id .. ": shot must consume exactly one round")
            check(#sentShots == 1 and #sentShots[1].impacts == weapon.BulletCount, id .. ": wrong pellet presentation")
            check(weapon.lastBullet.Damage == weapon.BulletDamage, id .. ": mapped damage lost")
            check(weapon.lastBullet.Distance == weapon.BulletRange, id .. ": mapped range lost")
            check(owner.lagCompensation == false, id .. ": lag compensation left open")
            check(Effects.Profiles[weapon.FirePresentation].ammo == item.ammoId, id .. ": effect/ammo mismatch")
            owner.CurrentSafeZoneId = "test-den"
            weapon:PrimaryAttack()
            check(weapon.rounds == 2 and weapon.firingCalls == 1, id .. ": fired inside a den")
            checked = checked + 1
        end
    end
    check(checked == 24, "all 24 CS 1.6 firearms must exercise the firing path")
end)

suite:Add("one_presentation_and_one_round_per_successful_shot", function(check)
    local weapon, owner = fixture()
    weapon.BulletCount = 9
    sentShots = {}
    weapon:PrimaryAttack()
    check(weapon.rounds == 2 and weapon.firingCalls == 1, "one shot must consume one round and call FireBullets once")
    check(owner.lagCompensation == false, "lag compensation was not closed")
    check(#sentShots == 1 and #sentShots[1].impacts == 9, "shotgun must present once, with all nine endpoints")
    check(weapon.recoilPitch < 0 and weapon.blastCalls == 1, "one successful shot must add recoil and one blast")
end)

suite:Add("empty_and_reloading_weapons_do_not_present", function(check)
    local weapon = fixture()
    sentShots = {}
    weapon.rounds = 0
    weapon:PrimaryAttack()
    check(weapon.reloadRequested and weapon.firingCalls == 0 and #sentShots == 0, "dry fire generated effects or bullets")
    weapon.rounds = 3
    weapon.reloading = true
    weapon:PrimaryAttack()
    check(weapon.rounds == 3 and weapon.firingCalls == 0 and #sentShots == 0, "reload generated effects or consumed a round")
    check(weapon.recoilPitch == 0 and not weapon.blastCalls, "dry fire/reloading caused recoil or a blast")
end)

suite:Add("recoil_recovers_and_is_bounded_and_shared_with_actual_aim", function(check)
    local weapon = fixture()
    for _ = 1, 100 do weapon:AddAimRecoil() end
    check(weapon.recoilPitch >= -4 and math.abs(weapon.recoilYaw) <= 1.5, "sustained recoil exceeded angular limits")
    weapon.recoilTime = CurTime() - 1
    local recovered = weapon:GetAimRecoil()
    check(math.abs(recovered.p) < 0.01 and math.abs(recovered.y) < 0.01, "recoil did not recover after one second")
    weapon.IsValid = function() return true end
    weapon.recoilPitch, weapon.recoilYaw, weapon.recoilTime = -2, 0.5, CurTime()
    local player = {
        EyeAngles = function() return Angle(0, 0, 0) end,
        GetNWString = function() return "" end,
        GetActiveWeapon = function() return weapon end,
        WorldSpaceCenter = function() return vector_origin end
    }
    local _, direction = FindMetaTable("Player").GetLevelAim(player)
    check(direction.z > 0.03 and direction.y > 0, "recoil did not affect shared shot/crosshair aim")
    player.GetNWString = function() return "den" end
    local _, denDirection = FindMetaTable("Player").GetLevelAim(player)
    check(denDirection.z == 0 and denDirection.y > 0, "den aim must stay level while retaining lateral recoil")
end)

local recoilTestWeapon
suite:Add("fresh_weapon_entities_initialize_recoil_network_fields", function(check)
    recoilTestWeapon = ents.Create("weapon_zn_auto_pistol_9mm")
    check(IsValid(recoilTestWeapon), "could not create throwaway firearm")
    if not IsValid(recoilTestWeapon) then return end
    recoilTestWeapon:Spawn()
    check(type(recoilTestWeapon.IsSafeZoneHolstered) == "function" and not recoilTestWeapon:IsSafeZoneHolstered(),
        "fresh weapon did not inherit the den holster helper")
    check(type(recoilTestWeapon.GetRecoilUpdatedAt) == "function", "recoil data-table accessors were not created")
    if not recoilTestWeapon.GetRecoilUpdatedAt then return end
    recoilTestWeapon:AddAimRecoil()
    check(recoilTestWeapon:GetAimRecoil().p < 0, "fresh weapon did not store and return recoil")
end)

local function blastFixture()
    local physics = {
        IsValid = function() return true end, mass = 5, motion = true, velocity = vector_origin,
        GetMass = function(self) return self.mass end,
        IsMotionEnabled = function(self) return self.motion end,
        GetVelocity = function(self) return self.velocity end,
        Wake = function() end,
        ApplyForceCenter = function(self, force) self.force = force end
    }
    local entity = {
        ZM_TestBlastFixture = true, class = "prop_physics", position = Vector(30, 0, -24),
        IsValid = function() return true end,
        GetClass = function(self) return self.class end,
        GetParent = function(self) return self.parent end,
        GetNWBool = function(self) return self.loot == true end,
        GetModel = function() return "models/props_junk/popcan01a.mdl" end,
        GetPhysicsObject = function() return physics end,
        WorldSpaceCenter = function(self) return self.position end
    }
    local weapon = { MuzzleBlastSpeed = 120, GetOwner = function() return NULL end }
    return entity, physics, weapon
end

suite:Add("muzzle_blast_only_moves_loose_light_nonloot_props", function(check)
    local entity, physics = blastFixture()
    check(Effects.CanBlastProp(entity), "loose light prop was rejected")
    for _, class in ipairs({ "player", "npc_zombie", "prop_door_rotating", "prop_ragdoll", "zn_item" }) do
        entity.class = class
        check(not Effects.CanBlastProp(entity), class .. " must be protected")
    end
    entity.class = "prop_physics"
    entity.loot = true
    check(not Effects.CanBlastProp(entity), "loot was not protected")
    entity.loot = false
    entity.constrained = true
    check(not Effects.CanBlastProp(entity), "constrained prop was not protected")
    entity.constrained = false
    entity.parent = { IsValid = function() return true end }
    check(not Effects.CanBlastProp(entity), "parented prop was not protected")
    entity.parent = nil
    physics.mass = 13
    check(not Effects.CanBlastProp(entity), "heavy prop was not protected")
    physics.mass, physics.motion = 5, false
    check(not Effects.CanBlastProp(entity), "frozen prop was not protected")
end)

local blastTrace
local boltTrace
local boltEntities = {}
suite:Add("crossbow_projectile_moves_hits_once_and_has_bounded_lifetime", function(check)
    local weapon = ents.Create("weapon_zn_hl2_crossbow")
    local attacker = ents.Create("prop_dynamic")
    local target = ents.Create("npc_citizen")
    for _, entity in ipairs({ weapon, attacker, target }) do boltEntities[#boltEntities + 1] = entity end
    check(IsValid(weapon) and IsValid(attacker) and IsValid(target), "crossbow fixture entities")
    if not IsValid(weapon) or not IsValid(attacker) or not IsValid(target) then return end
    attacker:SetModel("models/props_junk/PopCan01a.mdl")
    attacker:SetPos(Vector(0, 0, 12000))
    attacker:Spawn()
    target:SetModel("models/Humans/Group01/male_07.mdl")
    target:SetPos(Vector(256, 0, 12000))
    target:Spawn()
    weapon:SetPos(attacker:GetPos())
    weapon:Spawn()
    weapon:SetDamageScale(1.5)
    weapon:SetRangeScale(1.5)
    check(weapon:FireRound(attacker, attacker:GetPos(), Vector(1, 0, 0)), "crossbow projectile creation")
    local bolt
    for _, candidate in ipairs(ents.FindByClass("zn_crossbow_bolt")) do
        if candidate.Weapon == weapon then bolt = candidate break end
    end
    check(IsValid(bolt), "projectile not found")
    if not IsValid(bolt) then return end
    boltEntities[#boltEntities + 1] = bolt
    check(bolt.Damage == 112.5 and bolt.Range == 12288, "projectile snapshots item scaling")
    bolt.LastTick = CurTime() - 0.01
    local start = bolt:GetPos()
    boltTrace = { Hit = false, StartSolid = false, HitPos = start + Vector(25, 0, 0) }
    bolt:Think()
    check(bolt:GetPos().x > start.x and bolt.Travelled > 0, "bolt does not move")
    local damageCount = 0
    local captured
    hook.Add("EntityTakeDamage", "ZM.CrossbowFixture", function(entity, damage)
        if entity ~= target then return end
        damageCount = damageCount + 1
        captured = {
            amount = damage:GetDamage(), attacker = damage:GetAttacker(),
            inflictor = damage:GetInflictor(), position = damage:GetDamagePosition()
        }
        return true
    end)
    boltTrace = {
        Hit = true, StartSolid = false, HitSky = false, Entity = target,
        HitPos = target:GetPos(), HitNormal = Vector(-1, 0, 0), HitGroup = HITGROUP_CHEST,
        HitBox = 0, PhysicsBone = 0
    }
    bolt.LastTick = CurTime() - 0.01
    bolt:Think()
    check(damageCount == 1, "one projectile must dispatch one damage event")
    check(captured and captured.amount == 112.5 and captured.attacker == attacker and captured.inflictor == weapon, "projectile damage attribution/scaling")
    check(bolt:IsMarkedForDeletion(), "projectile must be removed on impact")
    bolt:Think()
    check(damageCount == 1, "deferred removal must not dispatch damage twice")
    hook.Remove("EntityTakeDamage", "ZM.CrossbowFixture")
    boltTrace = nil
    check(weapon:FireRound(attacker, attacker:GetPos(), Vector(1, 0, 0)), "lifetime fixture creation")
    for _, candidate in ipairs(ents.FindByClass("zn_crossbow_bolt")) do
        if candidate.Weapon == weapon and not candidate:IsMarkedForDeletion() then
            boltEntities[#boltEntities + 1] = candidate
            candidate.Started = CurTime() - 11
            candidate:Think()
            check(candidate:IsMarkedForDeletion(), "projectile lifetime must be bounded")
        end
    end
    check(weapon:FireRound(attacker, attacker:GetPos(), Vector(1, 0, 0)), "range fixture creation")
    for _, candidate in ipairs(ents.FindByClass("zn_crossbow_bolt")) do
        if candidate.Weapon == weapon and not candidate:IsMarkedForDeletion() then
            boltEntities[#boltEntities + 1] = candidate
            candidate.Travelled = candidate.Range
            candidate:Think()
            check(candidate:IsMarkedForDeletion(), "projectile range must be bounded")
        end
    end
end)

suite:Add("muzzle_blast_checks_walls_radius_cooldown_and_speed_budget", function(check)
    local entity, physics, weapon = blastFixture()
    blastTrace = { Hit = false, StartSolid = false }
    check(Effects.TryBlastProp(weapon, vector_origin, entity, 10), "nearby exposed prop did not move")
    check(physics.force.x > 0 and physics.force.z > 0, "blast must scatter outwards with lift")
    check(physics.force:Length() <= physics.mass * 120, "impulse exceeded cap")
    check(not Effects.TryBlastProp(weapon, vector_origin, entity, 10.05), "per-prop cooldown ignored")
    entity.ZM_NextMuzzleBlast = nil
    blastTrace = { Hit = true, Entity = NULL }
    check(not Effects.TryBlastProp(weapon, vector_origin, entity, 11), "blast passed through a wall")
    blastTrace = { Hit = false, StartSolid = true }
    check(not Effects.TryBlastProp(weapon, vector_origin, entity, 11), "solid source was accepted")
    blastTrace = { Hit = false, StartSolid = false }
    entity.position = Vector(96, 0, 0)
    check(not Effects.TryBlastProp(weapon, vector_origin, entity, 11), "blast exceeded radius")
    entity.position = Vector(20, 0, 0)
    physics.velocity = Vector(180, 0, 0)
    check(not Effects.TryBlastProp(weapon, vector_origin, entity, 11), "blast accelerated an already fast prop")
    physics.velocity = Vector(179, 0, 0)
    check(Effects.TryBlastProp(weapon, vector_origin, entity, 11), "remaining speed budget was not used")
    check(physics.force:Length() <= physics.mass + 0.001, "blast exceeded remaining speed budget")
end)

suite:Add("dust_only_uses_appropriate_surfaces_and_bounded_budget", function(check)
    for _, material in ipairs({ MAT_DIRT, MAT_SAND, MAT_CONCRETE, MAT_WOOD, MAT_TILE }) do
        check(Effects.IsDustMaterial(material), "dust surface rejected")
    end
    for _, material in ipairs({ MAT_FLESH, MAT_METAL, MAT_GLASS, MAT_SLOSH }) do
        check(not Effects.IsDustMaterial(material), "inappropriate dust surface accepted")
    end
    check(Effects.Limits.shots * Effects.Limits.dustPuffs <= 128, "dust population exceeded budget")
    check(Effects.Limits.dustLifetime <= 0.5, "dust lifetime exceeded budget")
end)

suite:Add("stock_flash_and_brass_are_suppressed_without_suppressing_sounds", function(check)
    local base = weapons.GetStored("weapon_zn_base_hitscan")
    local weapon = fixture()
    for _, event in ipairs({ 21, 5001, 5011, 5021, 5031, 5003, 6001 }) do
        check(base.FireAnimationEvent(weapon, nil, nil, event) == true, "duplicate event allowed: " .. event)
    end
    check(base.FireAnimationEvent(weapon, nil, nil, 5004) == nil, "animation sound event was suppressed")
end)

suite:Add("den_holster_blocks_fire_melee_reload_and_preserves_equipment", function(check)
    local weapon, owner = fixture()
    owner.CurrentSafeZoneId = "test-den"
    owner.ZM_WeaponSlots = { { instanceId = "retained", selected = true } }
    local slots = owner.ZM_WeaponSlots
    sentShots = {}
    weapon:PrimaryAttack()
    weapons.GetStored("weapon_zn_base_hitscan").Reload(weapon)
    weapons.GetStored("weapon_zn_base_melee").PrimaryAttack(weapon)
    check(weapon.rounds == 3 and weapon.firingCalls == 0 and #sentShots == 0, "holstered weapon fired or consumed ammunition")
    check(not weapon.blastCalls and weapon.recoilPitch == 0 and not weapon.reloadRequested, "holstered weapon produced side effects")
    check(owner.ZM_WeaponSlots == slots and slots[1].selected, "holster changed equipped slots")
    local loaded, reason = ZM_AmmoService:CompleteReload(owner, weapon)
    check(not loaded and reason == "weapons are holstered inside the den", "ammo service accepted den reload")
    owner.CurrentSafeZoneId = nil
    weapon:PrimaryAttack()
    check(weapon.rounds == 2 and weapon.firingCalls == 1, "firing did not restore outside")
end)

suite:Add("den_entry_cancels_reload_cycle_and_recoil_and_restores_hold_type", function(check)
    local weapon, owner = fixture()
    local base = weapons.GetStored("weapon_zn_base")
    weapon.finish = CurTime() + 2
    weapon.nextFire = weapon.finish
    weapon.GetReloadFinishTime = function(self) return self.finish end
    weapon.SetReloadFinishTime = function(self, value) self.finish = value end
    weapon.GetNextPrimaryFire = function(self) return self.nextFire end
    weapon.SetHoldType = function(self, value) self.hold = value end
    weapon.NextCycleSoundAt = CurTime() + 0.1
    weapon.recoilPitch = -2
    owner.CurrentSafeZoneId = "test-den"
    check(base.UpdateSafeZoneHolster(weapon), "den was not holstered")
    check(weapon.finish == 0 and weapon.NextCycleSoundAt == nil and weapon.recoilPitch == 0, "pending firing state survived entry")
    check(weapon.hold == "normal" and weapon.rounds == 3, "holster pose/ammo mismatch")
    owner.CurrentSafeZoneId = ""
    check(not base.UpdateSafeZoneHolster(weapon) and weapon.hold == weapon.HoldType, "outside hold type not restored")
end)

suite:Add("den_state_does_not_confuse_city_entrance_or_stale_network_state", function(check)
    local _, owner = fixture()
    owner.GetNWString = function() return "stale-den" end
    check(not ZM_SafeZones:IsPlayerInside(owner), "server trusted stale replicated state")
    owner.CurrentSafeZoneId = "NULL"
    check(not ZM_SafeZones:IsPlayerInside(owner), "NULL sentinel holstered weapons")
    owner.CurrentSafeZoneId = "test-den"
    check(ZM_SafeZones:IsPlayerInside(owner), "server den state was ignored")
end)

ZM_TestHarness.Register({
    command = "zn_test_weapon_effects",
    label = "Weapon effects",
    file = "weapon_effects_test_results.json",
    report = "weaponEffectsTests",
    help = "Checks firearm presentation profiles, shot traces, ballistics and dry-fire/reload behavior.",
    run = function()
        local originalSend = Effects.SendShot
        local originalBlast = Effects.ApplyMuzzleBlast
        local originalConstraints = constraint.HasConstraints
        local originalTrace = util.TraceLine
        return suite:Run({
            setup = function()
                Effects.SendShot = function(weapon, source, direction, impacts)
                    table.insert(sentShots, { weapon = weapon, source = source, direction = direction, impacts = impacts })
                end
                Effects.ApplyMuzzleBlast = function(weapon)
                    weapon.blastCalls = (weapon.blastCalls or 0) + 1
                end
                constraint.HasConstraints = function(entity)
                    if type(entity) == "table" and entity.ZM_TestBlastFixture then return entity.constrained == true end
                    return originalConstraints(entity)
                end
                util.TraceLine = function(data)
                    if boltTrace then return boltTrace end
                    if blastTrace then return blastTrace end
                    return originalTrace(data)
                end
            end,
            before = function() blastTrace = nil end,
            after = function()
                hook.Remove("EntityTakeDamage", "ZM.CrossbowFixture")
                for _, entity in ipairs(boltEntities) do
                    if IsValid(entity) then entity:Remove() end
                end
                boltEntities = {}
                boltTrace = nil
                if IsValid(recoilTestWeapon) then recoilTestWeapon:Remove() end
                recoilTestWeapon = nil
            end,
            teardown = function()
                Effects.SendShot = originalSend
                Effects.ApplyMuzzleBlast = originalBlast
                constraint.HasConstraints = originalConstraints
                util.TraceLine = originalTrace
            end
        })
    end
})
