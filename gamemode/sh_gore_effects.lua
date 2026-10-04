ZM_GoreEffects = ZM_GoreEffects or {}
local Effects = ZM_GoreEffects

local budgets = {
    [0] = { limbs = 0, pending = 0, spurts = 0, pools = 0, effects = 0, decals = 0, frameEffects = 0, frameDecals = 0 },
    [1] = { limbs = 4, pending = 8, spurts = 4, pools = 8, effects = 12, decals = 6, frameEffects = 4, frameDecals = 2 },
    [2] = { limbs = 12, pending = 24, spurts = 12, pools = 24, effects = 36, decals = 18, frameEffects = 12, frameDecals = 6 }
}

function Effects.Budget(quality)
    return budgets[math.Clamp(math.floor(quality), 0, 2)]
end

function Effects.PushBounded(queue, value, maximum, dispose)
    if maximum <= 0 then return false end
    while #queue >= maximum do
        local removed = table.remove(queue, 1)
        if dispose then dispose(removed) end
    end
    queue[#queue + 1] = value
    return true
end

function Effects.Trim(queue, maximum, dispose)
    while #queue > maximum do
        local removed = table.remove(queue, 1)
        if dispose then dispose(removed) end
    end
end

// Both rolling refill and per-frame caps prevent a packet burst from monopolising a frame.
function Effects.TakeToken(state, kind, now, frame, quality)
    local budget = Effects.Budget(quality)
    local capacity = budget[kind]
    if state.quality ~= quality then
        state.quality, state.time = quality, now
        state.effects, state.decals = budget.effects, budget.decals
    end
    local elapsed = math.max(0, now - (state.time or now))
    state.effects = math.min(budget.effects, (state.effects or 0) + elapsed * budget.effects)
    state.decals = math.min(budget.decals, (state.decals or 0) + elapsed * budget.decals)
    state.time = now
    if state.frame ~= frame then
        state.frame, state.frameEffects, state.frameDecals = frame, 0, 0
    end
    local frameKey = kind == "effects" and "frameEffects" or "frameDecals"
    if capacity <= 0 or state[kind] < 1 or state[frameKey] >= budget[frameKey] then return false end
    state[kind] = state[kind] - 1
    state[frameKey] = state[frameKey] + 1
    return true
end

Effects.PoolLifetime = 90
Effects.PoolFadeDuration = 10
Effects.MaximumDistance = 1500
Effects.MaximumMapDecals = 512

function Effects.PoolAlpha(age)
    return math.Clamp(age / 2, 0, 1)
        * math.Clamp((Effects.PoolLifetime - age) / Effects.PoolFadeDuration, 0, 1)
end

function Effects.BloodyMaterial(model, material)
    if not string.match(model, "^models/player/group03/") then return nil end
    local sex = string.match(model, "/(female)_%d+%.mdl$") or string.match(model, "/(male)_%d+%.mdl$")
    local prefix = sex and "models/humans/" .. sex .. "/group03/"
    if prefix and (material == prefix .. "players_sheet" or material == prefix .. "citizen_sheet") then
        return "models/humans/" .. sex .. "/bloody/citizen_sheet"
    end
end
