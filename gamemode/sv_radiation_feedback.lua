local Feedback = ZM_RadiationFeedback

function Feedback:ResetDamage(target)
    target.RadiationCellId = nil
    target.RadiationEnteredAt = nil
    target.RadiationNextDamageAt = nil
    target.RadiationAcute = nil
end

function Feedback:TickDamage(target, now)
    if not target:Alive() or target.ZM_PersistentStateLoaded ~= true then
        self:ResetDamage(target)
        return false
    end
    local safe = type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= ""
    local cell = not safe and target:GetWorldCell() or nil
    local intensity = cell and target:GetRadiationIntensity() or 0
    intensity = tonumber(intensity) or 0
    target:SetNWFloat("RadiationIntensity", intensity)
    local proximity = cell and target:GetNWFloat("ZM_RadiatedProximity", 0) or 0
    local damage, interval, acute = self.DamagePolicy(intensity, proximity, target:HasRadiationProtection())
    if not cell or damage == 0 then
        self:ResetDamage(target)
        return false
    end
    if target.RadiationCellId ~= cell.id or target.RadiationAcute ~= acute or not target.RadiationNextDamageAt then
        target.RadiationCellId, target.RadiationAcute = cell.id, acute
        target.RadiationEnteredAt, target.RadiationNextDamageAt = now, now + interval
        return false
    end
    if now < target.RadiationNextDamageAt then return false end
    target.RadiationNextDamageAt = now + interval
    if target.ZM_CheatSurvivalLock then return false end
    local floor = acute and 0 or target:GetRadiationHealthFloor()
    local applied = math.min(damage, math.max(target:Health() - floor, 0))
    if applied <= 0 then return false end
    local info = DamageInfo()
    info:SetDamage(applied)
    info:SetDamageType(DMG_RADIATION)
    info:SetAttacker(game.GetWorld())
    info:SetInflictor(game.GetWorld())
    target:TakeDamageInfo(info)
    return true
end

hook.Add("EntityTakeDamage", "ZM.RadiationFeedback.ArmourProtection", function(target, damage)
    if target:IsPlayer() and damage:IsDamageType(DMG_RADIATION) and target:HasRadiationProtection() then
        return true
    end
end)

function Feedback.FindStrongest(position, sources)
    local strongest, nearest = 0, nil
    for _, entity in ipairs(sources) do
        if IsValid(entity) and entity:Health() > 0 and entity:GetNWBool("ZM_Radiated", false) then
            local distance = position:Distance(entity:WorldSpaceCenter())
            local intensity = Feedback.Proximity(distance, entity:GetNWFloat("ZM_RadiatedIntensity", 0))
            if intensity > strongest then strongest, nearest = intensity, distance end
        end
    end
    return strongest, nearest
end

timer.Create("ZM.RadiationFeedback.Proximity", 0.25, 0, function()
    local sources = ents.FindByClass("zn_walker_zombie")
    for _, target in ipairs(player.GetHumans()) do
        local proximity = 0
        if target:Alive() and ZM_World:IsLoaded() and not ZM_SafeZones:IsPlayerInside(target)
            and target:GetWorldCell() then
            proximity = Feedback.FindStrongest(target:WorldSpaceCenter(), sources)
        end
        target:SetNWFloat("ZM_RadiatedProximity", proximity)
    end
end)

ZM_Util.RegisterCommands({
    zombiesim_dev_radiation_probe = "Preview-only: spawn one stationary radiated walker, or remove it with off."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not IsValid(target) then return false, "no admin player" end
    if ZM_World.ActiveProfile ~= "preview" or not target:IsAdmin() then
        ZM_Util.Reply(caller, "Radiation probes require an admin preview session.")
        return false, "admin preview required"
    end
    if arguments[1] ~= "on" and arguments[1] ~= "off" then
        ZM_Util.Reply(caller, "Usage: " .. command .. " on|off")
        return false, "expected on or off"
    end
    if IsValid(target.ZM_RadiationProbe) then target.ZM_RadiationProbe:Remove() end
    target.ZM_RadiationProbe = nil
    if arguments[1] == "off" then return true end
    if not target:Alive() or ZM_SafeZones:IsPlayerInside(target) or not target:GetWorldCell() then
        ZM_Util.Reply(caller, "Deploy into a city cell before running the probe.")
        return false, "deployed city player required"
    end
    local origin, direction = target:GetLevelAim()
    local trace = util.TraceLine({
        start = origin, endpos = origin + direction * 250, filter = target, mask = MASK_NPCSOLID_BRUSHONLY
    })
    local ground = util.TraceLine({
        start = trace.HitPos - direction * 24, endpos = trace.HitPos - direction * 24 - Vector(0, 0, 512),
        filter = target, mask = MASK_NPCSOLID_BRUSHONLY
    })
    if not ground.Hit or ground.HitNormal.z < 0.7 then
        ZM_Util.Reply(caller, "No walkable ground for the radiation probe.")
        return false, "no walkable ground"
    end
    local entity = ents.Create("zn_walker_zombie")
    if not IsValid(entity) then
        ZM_Util.Reply(caller, "Could not create the radiation probe.")
        return false, "entity creation failed"
    end
    entity:SetPos(ground.HitPos + Vector(0, 0, 4))
    entity:SetAngles(Angle(0, (target:GetPos() - entity:GetPos()):Angle().y, 0))
    entity:Spawn()
    entity.RunBehaviour = function() end
    entity:SetNWBool("ZM_Radiated", true)
    entity:SetNWFloat("ZM_RadiatedIntensity", 1)
    target.ZM_RadiationProbe = entity
    timer.Simple(120, function() if IsValid(entity) then entity:Remove() end end)
    ZM_Util.Reply(caller, "Stationary radiation probe created; approach/retreat to test the warning. Auto-removes in 120 seconds.")
    return true
end)
