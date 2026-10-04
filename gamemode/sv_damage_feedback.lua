// Sends bounded presentation feedback after actual damage is applied to a player.
ZM_DamageFeedback = ZM_DamageFeedback or {}
local Feedback = ZM_DamageFeedback
local minimumSourceDistanceSqr = 64 * 64
local maximumSourceDistanceSqr = 8192 * 8192

util.AddNetworkString("ZM.PlayerDamageFeedback")

local function isUsableSource(victimPosition, sourcePosition)
    if not isvector(victimPosition) or not isvector(sourcePosition) then
        return false
    end

    local sourceLengthSqr = sourcePosition.x * sourcePosition.x +
        sourcePosition.y * sourcePosition.y + sourcePosition.z * sourcePosition.z
    if sourceLengthSqr <= 1 then
        return false
    end

    local deltaX = sourcePosition.x - victimPosition.x
    local deltaY = sourcePosition.y - victimPosition.y
    local deltaZ = sourcePosition.z - victimPosition.z
    local distanceSqr = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ
    local horizontalDistanceSqr = deltaX * deltaX + deltaY * deltaY
    return distanceSqr >= minimumSourceDistanceSqr and distanceSqr <= maximumSourceDistanceSqr and
        horizontalDistanceSqr >= minimumSourceDistanceSqr
end

function Feedback.SelectSource(victimPosition, attackerPosition, inflictorPosition, damagePosition)
    if isUsableSource(victimPosition, attackerPosition) then
        return attackerPosition
    end
    if isUsableSource(victimPosition, inflictorPosition) then
        return inflictorPosition
    end
    if isUsableSource(victimPosition, damagePosition) then
        return damagePosition
    end
    return nil
end

function Feedback.Intensity(damage)
    damage = math.max(tonumber(damage) or 0, 0)
    if damage <= 0 then
        return 0
    end
    return math.Clamp(math.sqrt(damage / 25), 0.18, 1)
end

local function entityPosition(entity, victim)
    if IsValid(entity) and entity ~= victim and entity ~= game.GetWorld() then
        return entity:WorldSpaceCenter()
    end
    return nil
end

hook.Add("PostEntityTakeDamage", "ZM.PlayerDamageFeedback", function(entity, damageInfo, tookDamage)
    if not IsValid(entity) or not entity:IsPlayer() or tookDamage ~= true then
        return
    end

    local intensity = Feedback.Intensity(damageInfo:GetDamage())
    if intensity <= 0 then
        return
    end

    local attackerPosition = entityPosition(damageInfo:GetAttacker(), entity)
    local inflictorPosition = entityPosition(damageInfo:GetInflictor(), entity)
    local damagePosition = damageInfo:GetDamagePosition()
    local sourcePosition = Feedback.SelectSource(entity:WorldSpaceCenter(), attackerPosition,
        inflictorPosition, damagePosition)

    net.Start("ZM.PlayerDamageFeedback")
        net.WriteFloat(intensity)
        net.WriteBool(sourcePosition ~= nil)
        if sourcePosition then
            net.WriteVector(sourcePosition)
        end
    net.Send(entity)
end)
