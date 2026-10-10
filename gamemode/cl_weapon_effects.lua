local Effects = ZM_WeaponEffects
local limits = Effects.Limits
local shots = {}
local casings = {}

function Effects:GetWorldCaptureEntities()
    local entities = {}
    for _, casing in ipairs(casings) do entities[#entities + 1] = casing.entity end
    return entities
end
local flashTexture = Material("effects/muzzleflash1"):GetTexture("$basetexture")
local flashMaterial
if flashTexture then
    flashMaterial = CreateMaterial("zombiesim_muzzleflash_yellow", "UnlitGeneric", {
        ["$basetexture"] = flashTexture:GetName(),
        ["$additive"] = "1",
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1"
    })
    // Boost green in the mounted orange texture without altering the shared engine material.
    flashMaterial:SetVector("$color2", Vector(1, 2.5, 0.5))
else
    ErrorNoHalt("[ZombieSim] Mounted muzzleflash texture is unavailable.\n")
end
local smokeMaterial = Material("particle/particle_smokegrenade")
local tracerMaterial = Material("effects/laser1")
local flashColor = Color(255, 255, 170)
local tracerColor = Color(255, 210, 125)

local function removeCasing(index)
    local casing = table.remove(casings, index)
    if IsValid(casing.entity) then casing.entity:Remove() end
end

local function cleanup()
    for index = #casings, 1, -1 do removeCasing(index) end
    table.Empty(shots)
end

// Auto-refresh must not orphan clientside models from the previous module instance.
if Effects.Cleanup then Effects.Cleanup() end
Effects.Cleanup = cleanup
hook.Add("PreCleanupMap", "ZM.WeaponEffectsCleanup", cleanup)
hook.Add("ShutDown", "ZM.WeaponEffectsCleanup", cleanup)

local function attachment(weapon, name)
    local index = weapon:LookupAttachment(name)
    if index > 0 then return weapon:GetAttachment(index) end
end

local function ejectCasing(profile, position, angles, inheritedVelocity)
    if #casings >= limits.casings then removeCasing(1) end
    local entity = ClientsideModel(profile.casing, RENDERGROUP_OPAQUE)
    if not IsValid(entity) then
        ErrorNoHalt("[ZombieSim] Could not create casing model: " .. profile.casing .. "\n")
        return
    end
    entity:SetModelScale(profile.scale, 0)
    entity:SetPos(position)
    entity:SetAngles(angles)
    table.insert(casings, {
        entity = entity, position = position, angles = angles,
        velocity = angles:Right() * math.Rand(65, 100) + Vector(0, 0, math.Rand(55, 85)) + inheritedVelocity,
        expires = CurTime() + limits.casingLifetime
    })
end

local function shotTransform(shot)
    local weapon = shot.weapon
    local angles = shot.direction:Angle()
    local muzzle = shot.source + shot.direction * 24
    local muzzleDirection = shot.direction
    local ejectPosition
    local inheritedVelocity = vector_origin
    if IsValid(weapon) then
        local owner = weapon:GetOwner()
        if IsValid(owner) then
            owner:SetupBones()
            inheritedVelocity = owner:GetVelocity()
        end
        weapon:SetupBones()
        local muzzleAttachment = attachment(weapon, "muzzle") or weapon:GetAttachment(1)
        if muzzleAttachment then
            muzzle = muzzleAttachment.Pos
            muzzleDirection = muzzleAttachment.Ang:Forward()
        end
        local shellAttachment = attachment(weapon, "eject") or attachment(weapon, "shell")
        if shellAttachment then ejectPosition = shellAttachment.Pos end
    end
    return muzzle, ejectPosition or (muzzle - shot.direction * 12 + angles:Right() * 4), angles, inheritedVelocity, muzzleDirection
end

net.Receive("ZM.WeaponShot", function()
    local weapon = net.ReadEntity()
    local profileName = net.ReadString()
    local source = net.ReadVector()
    local direction = net.ReadNormal()
    local impacts = {}
    local dust = {}
    for index = 1, net.ReadUInt(5) do
        local position = net.ReadVector()
        local normal = net.ReadNormal()
        local material = net.ReadUInt(8)
        local hit = net.ReadBool()
        impacts[index] = position
        if hit and Effects.IsDustMaterial(material) and #dust < limits.dustPuffs - 1
            and EyePos():DistToSqr(position) <= limits.detailDistance ^ 2 then
            table.insert(dust, { position = position, normal = normal })
        end
    end
    local profile = Effects.Profiles[profileName]
    if not profile then
        ErrorNoHalt("[ZombieSim] Unknown firing presentation: " .. profileName .. "\n")
        return
    end
    if IsValid(weapon) and weapon:IsSafeZoneHolstered() then return end
    if ZM_AmbientDebris and ZM_AmbientDebris.OnShot then
        ZM_AmbientDebris:OnShot(source, direction, impacts)
    end
    if EyePos():DistToSqr(source) > limits.shotDistance ^ 2 then return end
    if EyePos():DistToSqr(source) <= limits.detailDistance ^ 2 then
        local ground = util.TraceLine({
            start = source, endpos = source - Vector(0, 0, 64), mask = MASK_SOLID_BRUSHONLY
        })
        if ground.Hit and not ground.StartSolid and Effects.IsDustMaterial(ground.MatType) then
            table.insert(dust, { position = ground.HitPos, normal = ground.HitNormal })
        end
    end
    for _, shot in ipairs(shots) do
        if shot.weapon == weapon then shot.emitting = false end
    end
    if #shots >= limits.shots then table.remove(shots, 1) end
    table.insert(shots, {
        weapon = weapon, source = source, direction = direction, impacts = impacts,
        profile = profile, started = CurTime(), smoke = {}, emitting = true, dust = dust
    })
end)

hook.Add("Think", "ZM.WeaponEffects", function()
    local now = CurTime()
    for index = #shots, 1, -1 do
        local shot = shots[index]
        if now - shot.started >= limits.smokeLifetime
            or IsValid(shot.weapon) and shot.weapon:IsSafeZoneHolstered() then table.remove(shots, index) end
    end
    local delta = math.min(FrameTime(), 0.05)
    for index = #casings, 1, -1 do
        local casing = casings[index]
        if not IsValid(casing.entity) or now >= casing.expires
            or EyePos():DistToSqr(casing.position) > limits.detailDistance ^ 2 then
            removeCasing(index)
        elseif not casing.resting then
            casing.velocity = casing.velocity + Vector(0, 0, -600 * delta)
            local trace = util.TraceHull({
                start = casing.position, endpos = casing.position + casing.velocity * delta,
                mins = Vector(-1, -1, -1), maxs = Vector(1, 1, 1),
                mask = MASK_SOLID_BRUSHONLY
            })
            casing.position = trace.HitPos
            if trace.Hit then
                casing.position = trace.HitPos + trace.HitNormal
                casing.velocity = (casing.velocity - 2 * casing.velocity:Dot(trace.HitNormal) * trace.HitNormal) * 0.3
                casing.resting = casing.velocity:LengthSqr() < 400
            end
            casing.angles:RotateAroundAxis(casing.angles:Forward(), 540 * delta)
            casing.entity:SetPos(casing.position)
            casing.entity:SetAngles(casing.angles)
        end
    end
end)

local smokeBeamColor = Color(205, 215, 225, 155)

local function drawSmoke(shot, now)
    if #shot.smoke < 2 then return end
    local fade = math.Clamp((limits.smokeLifetime - (now - shot.started)) / 0.6, 0, 1)
    local side = shot.direction:Angle():Right()
    render.SetMaterial(smokeMaterial)
    render.StartBeam(#shot.smoke)
    for index, node in ipairs(shot.smoke) do
        local age = now - node.started
        local drift = (1 - math.exp(-age * 10)) * 3
        local rise = age * 20 + age * age * 8
        local curl = math.sin(age * 8 + shot.started * 3) * math.min(age * 5, 4)
        local position = node.position + shot.direction * drift + side * curl
        position.z = position.z + rise
        local along = (index - 1) / (#shot.smoke - 1)
        local taper = 0.25 + 0.75 * math.sin(along * math.pi) ^ 0.5
        local width = (0.5 + age * 2.5) * math.Clamp(shot.profile.smoke / 6, 1, 1.8)
        smokeBeamColor.a = 155 * fade * taper
        render.AddBeam(position, width, along, smokeBeamColor)
    end
    render.EndBeam()
end

hook.Add("PostDrawTranslucentRenderables", "ZM.WeaponEffects", function(depth, skybox)
    if ZM_WorldCapture and ZM_WorldCapture.Rendering then return end
    if depth or skybox then return end
    local now = CurTime()
    for _, shot in ipairs(shots) do
        local distanceSquared = EyePos():DistToSqr(shot.position or shot.source)
        if distanceSquared > limits.shotDistance ^ 2 then continue end
        local age = now - shot.started
        local emitSmoke = shot.emitting and age <= limits.smokeEmissionTime
            and #shot.smoke < limits.smokeNodes and distanceSquared <= limits.detailDistance ^ 2
            and (not shot.nextSmoke or now >= shot.nextSmoke)
        // Resolve bone-merged attachments after the player/weapon pose has been drawn, not during net.Receive.
        local flashPosition
        if not shot.position or age < 0.045 or emitSmoke then
            local muzzle, ejectPosition, angles, velocity, muzzleDirection = shotTransform(shot)
            flashPosition = muzzle + muzzleDirection * 4
            if not shot.position then
                shot.position = muzzle
                shot.detailed = distanceSquared <= limits.detailDistance ^ 2
                if shot.detailed and shot.profile.casing then ejectCasing(shot.profile, ejectPosition, angles, velocity) end
            end
            if emitSmoke then
                table.insert(shot.smoke, { position = muzzle, started = now })
                shot.nextSmoke = now + limits.smokeInterval
            end
        end
        if age < 0.045 and flashMaterial then
            render.SetMaterial(flashMaterial)
            render.DrawSprite(flashPosition, shot.profile.flash, shot.profile.flash, flashColor)
        end
        if age < limits.tracerLifetime then
            render.SetMaterial(tracerMaterial)
            for _, impact in ipairs(shot.impacts) do
                // The engine callback supplies each spread pellet's actual endpoint.
                local travel = impact - shot.position
                local length = travel:Length()
                if length > 1 then
                    local direction = travel / length
                    local head = math.min(length, age * 24000)
                    local tail = math.max(0, head - 160)
                    render.DrawBeam(shot.position + direction * tail, shot.position + direction * head,
                        0.8, 0, 1, tracerColor)
                end
            end
        end
        if shot.detailed and distanceSquared <= limits.detailDistance ^ 2 and age < limits.smokeLifetime then
            drawSmoke(shot, now)
        end
        if age < limits.dustLifetime then
            render.SetMaterial(smokeMaterial)
            for _, puff in ipairs(shot.dust) do
                if EyePos():DistToSqr(puff.position) > limits.detailDistance ^ 2 then continue end
                local progress = age / limits.dustLifetime
                local size = 4 + progress * 18
                local alpha = 75 * math.min(age / 0.025, 1) * (1 - progress) ^ 2
                render.DrawSprite(puff.position + puff.normal * (2 + age * 16), size, size,
                    Color(165, 155, 135, alpha))
            end
        end
    end
end)

concommand.Add("zombiesim_weapon_effects_status", function()
    print(string.format("[ZombieSim] Firing effects: %d/%d shots, %d/%d casings; lifetimes %.2fs/%.2fs.",
        #shots, limits.shots, #casings, limits.casings, limits.smokeLifetime, limits.casingLifetime))
end)
