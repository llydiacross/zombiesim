return function(api)
    local Trace = {}

    function Trace.Sample(entity)
        if not api.IsValid(entity) then return nil, "Fixture prop is unavailable." end
        local origin = entity:GetPos()
        local minimum, maximum = entity:GetModelBounds()
        local scale = entity:GetModelScale()
        local height = (minimum.z + maximum.z) * 0.5 * scale
        local center = api.LocalToWorld(api.Vector(0, 0, height), api.Angle(0, 0, 0), origin, entity:GetAngles())
        local ray = api.util.TraceLine({
            start = center + api.Vector(512, 0, 0),
            endpos = center + api.Vector(-512, 0, 0),
            mask = api.MASK_SOLID, ignoreworld = true, filter = { entity }, whitelist = true
        })
        if not ray.Hit or ray.Entity ~= entity or ray.StartSolid then
            return nil, string.format("Collision trace missed fixture entity %d (scale %.3f, hit %s, startSolid %s).",
                entity:EntIndex(), scale, tostring(ray.Hit), tostring(ray.StartSolid))
        end
        return { entity = entity:EntIndex(), scale = scale, extent = ray.HitPos.x - center.x,
            x = origin.x, y = origin.y, z = origin.z }
    end
    return Trace
end
