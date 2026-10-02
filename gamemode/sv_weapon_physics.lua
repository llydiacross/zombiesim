local Effects = ZM_WeaponEffects
local radius = 96
local maximumMass = 12
local maximumSpeed = 180
local maximumProps = 8
local propClasses = { prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true }

function Effects.CanBlastProp(entity)
    local lootCell = ZM_LootSpots and ZM_LootSpots.Cell
    if not IsValid(entity) or not propClasses[entity:GetClass()] or IsValid(entity:GetParent())
        or entity:GetNWBool("ZM_LootSpot", false)
        or lootCell and lootCell.spotsByEntity[entity]
        or ZM_StaticData:GetEntityLootRule(entity:GetClass(), entity:GetModel())
        or constraint.HasConstraints(entity) then return false end
    local physics = entity:GetPhysicsObject()
    return IsValid(physics) and physics:IsMotionEnabled()
        and physics:GetMass() > 0 and physics:GetMass() <= maximumMass
end

function Effects.TryBlastProp(weapon, source, entity, now)
    if not Effects.CanBlastProp(entity) or (entity.ZM_NextMuzzleBlast or 0) > now then return false end
    local position = entity:WorldSpaceCenter()
    local offset = position - source
    local distance = offset:Length()
    if distance >= radius then return false end
    local trace = util.TraceLine({
        start = source, endpos = position, mask = MASK_SOLID,
        filter = { weapon:GetOwner(), weapon }
    })
    if trace.StartSolid or trace.Hit and trace.Entity ~= entity then return false end

    // A little lift lets cans and small debris leave the floor, without an explosion or damage.
    local direction = Vector(offset.x, offset.y, math.max(offset.z, distance * 0.35, 8)):GetNormalized()
    local physics = entity:GetPhysicsObject()
    local speed = math.min(weapon.MuzzleBlastSpeed, 120) * (1 - distance / radius)
    local velocity = physics:GetVelocity()
    speed = math.min(speed, math.max(0, maximumSpeed - velocity:Length()))
    if speed <= 0 then return false end
    physics:Wake()
    physics:ApplyForceCenter(direction * speed * physics:GetMass())
    entity.ZM_NextMuzzleBlast = now + 0.1
    return true
end

function Effects.ApplyMuzzleBlast(weapon, source)
    local count = 0
    local now = CurTime()
    for _, entity in ipairs(ents.FindInSphere(source, radius)) do
        if Effects.TryBlastProp(weapon, source, entity, now) then
            count = count + 1
            if count >= maximumProps then break end
        end
    end
end

Effects.BlastProbe = Effects.BlastProbe or {}
local function clearProbe()
    for _, row in ipairs(Effects.BlastProbe) do
        if IsValid(row.entity) then row.entity:Remove() end
    end
    Effects.BlastProbe = {}
    timer.Remove("ZM.MuzzleBlastProbeCleanup")
end

local function reportProbe(caller)
    local rows = {}
    for _, row in ipairs(Effects.BlastProbe) do
        local entity = row.entity
        if IsValid(entity) then
            table.insert(rows, {
                role = row.role, displacement = entity:GetPos():Distance(row.origin),
                receivedBlast = entity.ZM_NextMuzzleBlast ~= nil,
                frozen = not entity:GetPhysicsObject():IsMotionEnabled()
            })
        end
    end
    ZM_Util.Reply(caller, "Temporary muzzle-blast props remaining: " .. #rows)
    if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("muzzleBlastProbe", rows) end
    return true
end

ZM_Util.RegisterCommands({
    zombiesim_dev_muzzle_blast_probe = "Preview-only temporary cans: start, status, or clear. Auto-cleans after 180 seconds."
}, function(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command) then return false, "admin required" end
    local action = arguments[1]
    if action == "clear" then
        clearProbe()
        return reportProbe(caller)
    end
    if action == "status" then return reportProbe(caller) end
    if action ~= "start" then
        ZM_Util.Reply(caller, "Use start, status, or clear.")
        return false, "invalid probe action"
    end
    if not ZM_Preview:IsActive() then
        ZM_Util.Reply(caller, "The prop probe requires the preview profile.")
        return false, "preview profile required"
    end
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not IsValid(target) or not target:IsAdmin() or not target:Alive() then
        ZM_Util.Reply(caller, "The probe requires a living admin.")
        return false, "living admin required"
    end
    clearProbe()
    local facing = Angle(0, target:EyeAngles().y, 0)
    local positions = {}
    for index = 1, 4 do
        local above = target:WorldSpaceCenter() + facing:Forward() * 40 + facing:Right() * ((index - 2) * 18)
        local ground = util.TraceLine({ start = above, endpos = above - Vector(0, 0, 96), mask = MASK_SOLID_BRUSHONLY })
        local position = ground.HitPos + Vector(0, 0, 5)
        local space = util.TraceHull({
            start = position, endpos = position, mins = Vector(-3, -3, -3), maxs = Vector(3, 3, 5),
            mask = MASK_SOLID, filter = target
        })
        if not ground.Hit or ground.StartSolid or ground.HitNormal.z < 0.8 or space.Hit then
            ZM_Util.Reply(caller, "Not enough clear flat ground ahead; move to an open floor and retry.")
            return false, "probe placement obstructed"
        end
        positions[index] = position
    end
    for index, position in ipairs(positions) do
        local entity = ents.Create("prop_physics")
        if not IsValid(entity) then
            clearProbe()
            ZM_Util.Reply(caller, "Could not create temporary test can.")
            return false, "probe entity creation failed"
        end
        table.insert(Effects.BlastProbe, { entity = entity, origin = position, role = index == 4 and "frozen" or "loose" })
        entity:SetModel("models/props_junk/popcan01a.mdl")
        entity:SetPos(position)
        entity:SetColor(index == 4 and Color(255, 60, 60) or Color(60, 255, 80))
        entity:Spawn()
        local physics = entity:GetPhysicsObject()
        if not IsValid(physics) then
            clearProbe()
            ZM_Util.Reply(caller, "Temporary can has no physics object.")
            return false, "probe physics unavailable"
        end
        physics:SetMass(2)
        physics:EnableMotion(index ~= 4)
        if index ~= 4 then physics:Wake() end
    end
    timer.Create("ZM.MuzzleBlastProbeCleanup", 180, 1, function()
        clearProbe()
        ZM_Util.Reply(nil, "Temporary muzzle-blast props automatically removed.")
    end)
    ZM_Util.Reply(caller, "Three green loose cans and one red frozen control are ahead. Fire away from them; auto-cleanup in 180 seconds.")
    return reportProbe(caller)
end)
