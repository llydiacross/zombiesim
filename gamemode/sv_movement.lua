ZM_Movement = ZM_Movement or {}
local Movement = ZM_Movement

Movement.WalkScale = 0.57375
Movement.RunScale = 0.65025
Movement.SprintDrain = 30
Movement.Recovery = 5.5

function Movement.Rates(agility, strength, recoveryScale)
    return Movement.SprintDrain / (1 + agility * 0.05 + strength * 0.03),
        Movement.Recovery * (1 + agility * 0.05) * (tonumber(recoveryScale) or 1)
end

function Movement.Step(stamina, maximum, sprinting, agility, strength, delta, recoveryScale)
    local drain, recovery = Movement.Rates(agility, strength, recoveryScale)
    return math.Clamp(stamina + (sprinting and -drain or recovery) * delta, 0, maximum)
end

function Movement.Apply(target, bonus)
    local walk, run = target:GetWalkSpeed(), target:GetRunSpeed()
    if not target.ZM_BaseWalkSpeed or not target.ZM_AppliedWalkSpeed
        or math.abs(walk - target.ZM_AppliedWalkSpeed) > 0.01 then target.ZM_BaseWalkSpeed = walk end
    if not target.ZM_BaseRunSpeed or not target.ZM_AppliedRunSpeed
        or math.abs(run - target.ZM_AppliedRunSpeed) > 0.01 then target.ZM_BaseRunSpeed = run end
    local endurance = target.GetStat and target:GetStat("Endurance") or 0
    local armour = ZM_Items:GetArmourEffects(target.ZM_Inventory, endurance)
    local scale = (1 + bonus) * (1 - armour.speedPenalty)
    target.ZM_AppliedWalkSpeed = target.ZM_BaseWalkSpeed * Movement.WalkScale * scale
    target.ZM_AppliedRunSpeed = target.ZM_BaseRunSpeed * Movement.RunScale * scale
    target:SetWalkSpeed(target.ZM_AppliedWalkSpeed)
    target:SetRunSpeed(target.ZM_AppliedRunSpeed)
end

function Movement.RestrictExhausted(target, move)
    if target.ZM_PersistentStateLoaded ~= true or (tonumber(target.Stamina) or 0) > 0 then return end
    move:SetMaxSpeed(target:GetWalkSpeed())
    move:SetMaxClientSpeed(target:GetWalkSpeed())
    move:SetButtons(bit.band(move:GetButtons(), bit.bnot(IN_SPEED)))
end

function Movement.Snapshot(target)
    local agility, strength = target:GetStat("Agility"), target:GetStat("Strength")
    local armour = ZM_Items:GetArmourEffects(target.ZM_Inventory, target:GetStat("Endurance"))
    local drain, recovery = Movement.Rates(agility, strength, 1 - armour.staminaRegenPenalty)
    return {
        baseWalkSpeed = target.ZM_BaseWalkSpeed, baseRunSpeed = target.ZM_BaseRunSpeed,
        walkSpeed = target:GetWalkSpeed(), runSpeed = target:GetRunSpeed(),
        walkScale = Movement.WalkScale, runScale = Movement.RunScale,
        sprintDrain = drain, recovery = recovery, agility = agility, strength = strength,
        armour = armour,
        stamina = target.Stamina, maxStamina = target:GetMaxStamina(),
        sprintInput = target:KeyDown(IN_SPEED), velocity = target:GetVelocity():Length2D(),
        moveSpeedBonus = ZM_ImplantService:GetEffect(target, "moveSpeed")
    }
end
