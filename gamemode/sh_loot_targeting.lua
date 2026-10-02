// Shared loot-spot targeting. The client highlights, and the server searches, the spot chosen by these same rules:
// the spot under the aim trace wins when it is searchable, in range and unobstructed; otherwise the nearest such spot
// is used. When neither exists but the aim trace is on a spot, the reason (empty, far, blocked) is returned instead.
ZM_LootTargeting = ZM_LootTargeting or {}
local Targeting = ZM_LootTargeting

Targeting.UseRange = 110
Targeting.AimRange = 600
Targeting.SearchRadius = Targeting.UseRange + 150

local searchableStates = { available = true, declined = true }

function Targeting.IsSearchableState(state)
    return searchableStates[state] == true
end

function Targeting.GetDistance(ply, entity)
    if not IsValid(entity) then
        return math.huge
    end
    local center = ply:WorldSpaceCenter()
    return center:Distance(entity:NearestPoint(center))
end

// Living characters, corpses and client-only props never hide a spot; walls, doors and other props do.
local function blocksSight(hit, ply, entity)
    if hit == entity then
        return true
    end
    if hit == ply or not IsValid(hit) then
        return false
    end
    if hit:IsPlayer() or hit:IsNPC() or (hit.IsNextBot and hit:IsNextBot()) or hit:GetClass() == "prop_ragdoll" then
        return false
    end
    if CLIENT and hit:EntIndex() < 0 then
        return false
    end
    return true
end

// True when no line from the player's centre reaches the spot's centre or its nearest surface point.
function Targeting.IsObstructed(ply, entity)
    if not isentity(entity) or not isentity(ply) or not IsValid(entity) then
        return false
    end
    local origin = ply:WorldSpaceCenter()
    local filter = function(hit)
        return blocksSight(hit, ply, entity)
    end
    for _, goal in ipairs({ entity:WorldSpaceCenter(), entity:NearestPoint(origin) }) do
        local trace = util.TraceLine({ start = origin, endpos = goal, filter = filter, mask = MASK_SOLID })
        if trace.Entity == entity or trace.Fraction >= 0.98 or not trace.Hit then
            return false
        end
    end
    return true
end

function Targeting.FindNearby(origin, radius)
    return ents.FindInSphere(origin, radius)
end

local function isUsable(ply, entity, state)
    return Targeting.IsSearchableState(state) and Targeting.GetDistance(ply, entity) <= Targeting.UseRange
        and not Targeting.IsObstructed(ply, entity)
end

// stateOf(entity) returns "available", "declined", "looted" or nil for an entity that is not a loot spot.
// Returns { entity, state, aimed } for the spot to search, or { entity, state, aimed = true, reason } when the
// player aims at a spot that cannot be searched, or nil.
function Targeting.Select(ply, stateOf)
    if not IsValid(ply) then
        return nil
    end
    local aimed = ply.GetLevelAimTrace and ply:GetLevelAimTrace(Targeting.AimRange).Entity
    local aimedState = IsValid(aimed) and stateOf(aimed) or nil
    if aimedState and isUsable(ply, aimed, aimedState) then
        return { entity = aimed, state = aimedState, aimed = true }
    end

    local nearest, nearestState, nearestDistance = nil, nil, Targeting.UseRange
    for _, entity in ipairs(Targeting.FindNearby(ply:WorldSpaceCenter(), Targeting.SearchRadius)) do
        local state = entity ~= aimed and stateOf(entity) or nil
        if state and Targeting.IsSearchableState(state) then
            local distance = Targeting.GetDistance(ply, entity)
            if distance <= nearestDistance and not Targeting.IsObstructed(ply, entity) then
                nearest, nearestState, nearestDistance = entity, state, distance
            end
        end
    end
    if nearest then
        return { entity = nearest, state = nearestState, aimed = false }
    end

    if aimedState then
        local reason = "blocked"
        if not Targeting.IsSearchableState(aimedState) then
            reason = "empty"
        elseif Targeting.GetDistance(ply, aimed) > Targeting.UseRange then
            reason = "far"
        end
        return { entity = aimed, state = aimedState, aimed = true, reason = reason }
    end
    return nil
end

Targeting.ReasonText = {
    empty = "There is nothing left here.",
    far = "You are too far away.",
    blocked = "Something is in the way."
}
