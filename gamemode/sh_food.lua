// Shared food rules: timestamp freshness, freshness bands, bounded effects, and the behaviour class for food items.
// Freshness derives only from an instance's createdAt and the definition's shelf life, so it survives moves, saves,
// den deposits, and offline time without any stored per-tick state.
ZM_Food = ZM_Food or {}
local Food = ZM_Food
local Items = ZM_Items

// Freshness above FreshAbove is fresh, above zero is stale, and zero is spoiled.
Food.FreshAbove = 0.5
Food.Bands = {
    fresh = { label = "Fresh", multiplier = 1 },
    stale = { label = "Stale", multiplier = 0.6 },
    spoiled = { label = "Spoiled", multiplier = 0.25 }
}
Food.SpoiledHealthPenalty = -10
Food.EffectBounds = {
    nutrition = { 0, 100 },
    hydration = { 0, 100 },
    health = { -50, 50 },
    stamina = { 0, 100 }
}

function Food:GetDefinitionFood(itemId)
    local definition = Items:GetDefinition(itemId)
    return definition and definition.food or nil, definition
end

function Food:IsPerishable(itemId)
    local food = self:GetDefinitionFood(itemId)
    return food ~= nil and food.shelfLifeHours ~= nil
end

// Returns freshness 0..1. Non-perishable food and instances without a creation time are always fully fresh.
function Food:GetFreshness(instance, now)
    local food = self:GetDefinitionFood(instance.itemId)
    if not food then
        return nil
    end
    if food.tier == 0 then
        return 0
    end
    local createdAt = tonumber(instance.createdAt) or 0
    if not food.shelfLifeHours or createdAt <= 0 then
        return 1
    end
    local age = math.max(0, (now or os.time()) - createdAt)
    return math.Clamp(1 - age / (food.shelfLifeHours * 3600), 0, 1)
end

function Food:GetBand(instance, now)
    local freshness = self:GetFreshness(instance, now)
    if freshness == nil then
        return nil
    end
    if freshness > self.FreshAbove then
        return "fresh", freshness
    elseif freshness > 0 then
        return "stale", freshness
    end
    return "spoiled", freshness
end

// Seconds until the instance's next band change, or nil when it will not change.
function Food:GetSecondsToNextBand(instance, now)
    local food = self:GetDefinitionFood(instance.itemId)
    local band, freshness = self:GetBand(instance, now)
    if not food or not food.shelfLifeHours or band == "spoiled" or (tonumber(instance.createdAt) or 0) <= 0 then
        return nil
    end
    local target = band == "fresh" and self.FreshAbove or 0
    return math.max(0, (freshness - target) * food.shelfLifeHours * 3600)
end

// Returns the effects one unit would apply now: { nutrition, hydration, health, stamina, band }.
// Rotten (tier 0) food keeps its authored penalty; spoiled perishable food loses most value and costs health.
function Food:GetEffects(instance, now)
    local food = self:GetDefinitionFood(instance.itemId)
    if not food then
        return nil
    end
    local band = self:GetBand(instance, now)
    local multiplier = food.tier == 0 and 1 or self.Bands[band].multiplier
    local effects = { band = band }
    for effect, bounds in pairs(self.EffectBounds) do
        local value = food[effect] or 0
        if value > 0 then
            value = math.floor(value * multiplier + 0.5)
        end
        effects[effect] = value
    end
    if band == "spoiled" and food.tier > 0 then
        effects.health = math.min(effects.health, 0) + self.SpoiledHealthPenalty
    end
    for effect, bounds in pairs(self.EffectBounds) do
        effects[effect] = math.Clamp(effects[effect], bounds[1], bounds[2])
    end
    return effects
end

// Perishable stacks only combine within the same freshness band; the merged stack keeps the oldest timestamp.
function Food:CanStack(first, second, now)
    if not self:IsPerishable(first.itemId) then
        return true
    end
    return self:GetBand(first, now) == self:GetBand(second, now)
end

function Food.MergedCreatedAt(first, second)
    local left, right = tonumber(first.createdAt) or 0, tonumber(second.createdAt) or 0
    if left <= 0 then return right end
    if right <= 0 then return left end
    return math.min(left, right)
end

function Food:DescribeEffects(effects)
    local parts = {}
    for _, effect in ipairs({ "nutrition", "hydration", "health", "stamina" }) do
        local value = effects[effect]
        if value ~= 0 then
            table.insert(parts, string.format("%s%d %s", value > 0 and "+" or "", value, effect == "nutrition" and "food" or effect == "hydration" and "water" or effect))
        end
    end
    return table.concat(parts, ", ")
end

// Behaviour class used by every item whose definition has a food block.
ZM_EntityClasses = ZM_EntityClasses or {}
local FoodItem = Items:NewItemClass()
ZM_EntityClasses.FoodItem = FoodItem

local function currentStamina(ply)
    local maximum = ply.GetMaxStamina and ply:GetMaxStamina() or 100
    return tonumber(ply.Stamina) or maximum, maximum
end

// Rejects eating when none of the positive effects would be of any use, so food is never wasted by accident.
function FoodItem:CanUse(ply, itemData, targetPly)
    local canUse, reason = ZM_EntityClasses.GenericItem.CanUse(self, ply, itemData, targetPly)
    if not canUse then
        return false, reason
    end
    if targetPly and targetPly ~= ply then
        return false, "You can only eat or drink food yourself."
    end
    local effects = Food:GetEffects(itemData.instance)
    if not effects then
        return false, "That is not food."
    end
    // A point of headroom is required, so slow survival drain alone never makes food "useful".
    local stamina, maxStamina = currentStamina(ply)
    local useful = (effects.nutrition > 0 and (tonumber(ply.Hunger) or 100) <= 99)
        or (effects.hydration > 0 and (tonumber(ply.Thirst) or 100) <= 99)
        or (effects.health > 0 and ply:Health() < ply:GetMaxHealth())
        or (effects.stamina > 0 and stamina <= maxStamina - 1)
    if not useful then
        return false, "You are not hungry or thirsty."
    end
    return true, ""
end

// Server-only. Effects are computed from the consumed instance's own timestamp, never from client data.
function FoodItem:OnUse(ply, itemData)
    if not IsValid(ply) or not ply:Alive() then
        return false
    end
    local effects = Food:GetEffects(itemData.instance)
    if not effects then
        return false
    end
    ply.Hunger = math.Clamp((tonumber(ply.Hunger) or 100) + effects.nutrition, 0, 100)
    ply.Thirst = math.Clamp((tonumber(ply.Thirst) or 100) + effects.hydration, 0, 100)
    local stamina, maxStamina = currentStamina(ply)
    ply.Stamina = math.Clamp(stamina + effects.stamina, 0, maxStamina)
    if effects.health ~= 0 then
        ply:SetHealth(math.Clamp(ply:Health() + effects.health, 1, ply:GetMaxHealth()))
    end
    if ply.SetNWFloat then
        ply:SetNWFloat("Hunger", ply.Hunger)
        ply:SetNWFloat("Thirst", ply.Thirst)
        ply:SetNWFloat("Stamina", ply.Stamina)
    end
    if ply.EmitSound then
        ply:EmitSound(effects.hydration > effects.nutrition and "npc/barnacle/barnacle_gulp2.wav" or "npc/barnacle/barnacle_gulp1.wav", 70, 100)
    end
    if ply.ChatPrint then
        local definition = Items:GetDefinition(itemData.id)
        ply:ChatPrint("[Food] " .. (definition and definition.name or itemData.id) .. " (" .. Food.Bands[effects.band].label .. "): " .. Food:DescribeEffects(effects) .. ".")
    end
    itemData.appliedEffects = effects
    return true
end
