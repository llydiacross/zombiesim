return function(api)
    local Targeting = {}

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    function Targeting.IsZombie(entity)
        if not api.IsValid(entity) then return false end
        local class = entity:GetClass()
        return (class == "zn_walker_zombie" or class == "zn_boss_zombie") and entity:Health() > 0
    end

    local function visible(shooter, source, target, range)
        if not Targeting.IsZombie(target) then return false end
        local position = target:WorldSpaceCenter()
        if source:DistToSqr(position) > range * range then return false end
        local trace = api.util.TraceLine({
            start = source, endpos = position, filter = shooter, mask = api.MASK_SHOT
        })
        return trace.Entity == target
    end

    function Targeting.Select(shooter, source, range)
        if not api.IsValid(shooter) or not api.IsVector(source) or not finite(range) or range <= 0 then
            return nil, "Invalid guard targeting parameters."
        end
        local selected, nearest
        for _, candidate in ipairs(api.ents.FindInSphere(source, range)) do
            if Targeting.IsZombie(candidate) then
                local distance = source:DistToSqr(candidate:WorldSpaceCenter())
                if (not nearest or distance < nearest
                    or (distance == nearest and candidate:EntIndex() < selected:EntIndex()))
                    and visible(shooter, source, candidate, range) then
                    selected, nearest = candidate, distance
                end
            end
        end
        return selected
    end

    function Targeting.Fire(shooter, source, target, range, weapon)
        if not api.IsValid(shooter) or not api.IsVector(source) or not finite(range) or range <= 0
            or type(weapon) ~= "table" or not finite(weapon.damage) or weapon.damage <= 0
            or not finite(weapon.spread) or weapon.spread < 0 or not finite(weapon.force) or weapon.force < 0
            or (weapon.tracer ~= nil and (not finite(weapon.tracer) or weapon.tracer < 0
                or weapon.tracer ~= math.floor(weapon.tracer))) then
            return false, "Invalid guard firing parameters."
        end
        if not visible(shooter, source, target, range) then return false, "The target is unavailable or obstructed." end
        local direction = target:WorldSpaceCenter() - source
        if direction:LengthSqr() <= 0 then return false, "The target is at the firing origin." end
        shooter:FireBullets({
            Src = source, Dir = direction:GetNormalized(), Spread = api.Vector(weapon.spread, weapon.spread, 0),
            Damage = weapon.damage, Force = weapon.force, Distance = range, Num = 1, Tracer = weapon.tracer or 0,
            Callback = function(_, result)
                if result.Entity ~= target or not Targeting.IsZombie(result.Entity) then return { damage = false } end
            end
        })
        return true
    end

    return Targeting
end
