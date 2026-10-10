ZM_WeaponEffects = ZM_WeaponEffects or {}
local Effects = ZM_WeaponEffects

Effects.Limits = {
    shots = 32, casings = 32, pellets = 16,
    casingLifetime = 2, smokeLifetime = 1.4, tracerLifetime = 0.08,
    smokeNodes = 16, smokeInterval = 0.025, smokeEmissionTime = 0.375,
    dustPuffs = 4, dustLifetime = 0.45,
    detailDistance = 1800, shotDistance = 4096
}

Effects.Profiles = {
    magnum = { ammo = "ammo357", casing = "models/weapons/shell.mdl", flash = 20, smoke = 8, scale = 1 },
    pulse = { ammo = "ammoPulse", casing = false, flash = 22, smoke = 9, scale = 1 },
    crossbow = { ammo = "ammoBolts", casing = false, projectile = true },
    pistol = { ammo = "ammo9mm", casing = "models/weapons/shell.mdl", flash = 12, smoke = 6, scale = 1 },
    smg = { ammo = "ammo9mm", casing = "models/weapons/shell.mdl", flash = 16, smoke = 7, scale = 1 },
    rifle556 = { ammo = "ammo556", casing = "models/weapons/rifleshell.mdl", flash = 22, smoke = 9, scale = 0.85 },
    rifle762 = { ammo = "ammo762", casing = "models/weapons/rifleshell.mdl", flash = 26, smoke = 10, scale = 1 },
    shotgun = { ammo = "ammoShells", casing = "models/weapons/shotgun_shell.mdl", flash = 30, smoke = 14, scale = 1 },
    sniper762 = { ammo = "ammo762", casing = "models/weapons/rifleshell.mdl", flash = 28, smoke = 11, scale = 1 },
    sniper50 = { ammo = "ammo50Bmg", casing = "models/weapons/rifleshell.mdl", flash = 36, smoke = 16, scale = 1.3 }
}

// Suppress only the stock flash/brass events; retain animation sounds and other events.
Effects.AnimationEvents = {
    [21] = true, [5001] = true, [5011] = true, [5021] = true, [5031] = true,
    [5003] = true, [5013] = true, [5023] = true, [5033] = true, [6001] = true
}

function Effects.IsDustMaterial(material)
    return material == MAT_CONCRETE or material == MAT_DIRT or material == MAT_SAND
        or material == MAT_WOOD or material == MAT_TILE
end

if SERVER then
    util.AddNetworkString("ZM.WeaponShot")

    function Effects.SendShot(weapon, source, direction, impacts)
        if not Effects.Profiles[weapon.FirePresentation] then
            ErrorNoHalt("[ZombieSim] Missing firing presentation for " .. weapon:GetClass() .. "\n")
            return
        end
        if #impacts > Effects.Limits.pellets then
            ErrorNoHalt("[ZombieSim] Shot exceeded the visual pellet budget: " .. weapon:GetClass() .. "\n")
        end
        local count = math.min(#impacts, Effects.Limits.pellets)
        local recipients = RecipientFilter()
        recipients:AddPVS(source)
        local owner = weapon:GetOwner()
        if IsValid(owner) and owner:IsPlayer() then recipients:AddPlayer(owner) end
        net.Start("ZM.WeaponShot")
            net.WriteEntity(weapon)
            net.WriteString(weapon.FirePresentation)
            net.WriteVector(source)
            net.WriteNormal(direction)
            net.WriteUInt(count, 5)
            for index = 1, count do
                local impact = impacts[index]
                net.WriteVector(impact.position)
                net.WriteNormal(impact.normal)
                net.WriteUInt(impact.material, 8)
                net.WriteBool(impact.hit)
            end
        net.Send(recipients)
    end
end
