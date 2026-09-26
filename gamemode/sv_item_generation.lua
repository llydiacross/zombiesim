// Server-only item generation: instance ids, repeatable random numbers, item level, and attribute rolls.
ZM_ItemGeneration = ZM_ItemGeneration or {}
local Generation = ZM_ItemGeneration
local Items = ZM_Items

Generation.MaximumDangerBonusLevels = 5
// A non-mastercraft attribute rolls between (progress - LowRollSpread) and (progress + HighRollSpread) of its range.
Generation.LowRollSpread = 0.25
Generation.HighRollSpread = 0.1
Generation.PerfectMastercraftChance = 0.01

local instanceCounter = 0
function Generation.NewInstanceId()
    instanceCounter = (instanceCounter + 1) % 0x10000
    return string.format("%08x%06x%04x", os.time(), math.random(0, 0xFFFFFF), instanceCounter)
end

// Park-Miller minimal standard generator; exact in double precision, so a seed always repeats its sequence.
local Rng = {}
Rng.__index = Rng

function Generation.NewRng(seed)
    seed = math.floor(tonumber(seed) or math.random(1, 2147483646)) % 2147483647
    if seed <= 0 then
        seed = seed + 2147483646
    end
    return setmetatable({ state = seed }, Rng)
end

function Rng:Next()
    self.state = (self.state * 48271) % 2147483647
    return (self.state - 1) / 2147483646
end

function Rng:Int(minimum, maximum)
    return minimum + math.floor(self:Next() * (maximum - minimum + 1))
end

function Rng:Chance(probability)
    return self:Next() < probability
end

// Player level (clamped to the item's range) is the base; danger adds round(danger * 5) levels plus
// one more with probability equal to the danger, so danger 0 never lifts an item above the base.
function Generation:RollLevel(definition, playerLevel, danger, rng)
    danger = math.Clamp(tonumber(danger) or 0, 0, 1)
    local base = math.Clamp(math.floor(tonumber(playerLevel) or 1), definition.minLevel, definition.maxLevel)
    local bonus = math.Round(danger * self.MaximumDangerBonusLevels)
    if rng:Chance(danger) then
        bonus = bonus + 1
    end
    return math.min(base + bonus, definition.maxLevel)
end

// Matching scores across every attribute are reserved for perfect mastercrafts.
local function separateUniformScores(attributes, names, low, high, rng)
    if #names < 2 or low >= high then
        return
    end
    local first = attributes[names[1]]
    for index = 2, #names do
        if attributes[names[index]] ~= first then
            return
        end
    end
    local name = names[rng:Int(1, #names)]
    attributes[name] = first > low and first - 1 or first + 1
end

function Generation:RollAttributes(definition, level, mastercraft, rng)
    if not definition.attributes then
        return nil
    end
    local minimum, maximum = definition.minAttributes, definition.maxAttributes
    local names = definition.attributes
    local attributes = {}

    if mastercraft then
        local perfect = rng:Chance(self.PerfectMastercraftChance)
        local low = math.max(minimum, maximum - 1)
        for _, name in ipairs(names) do
            attributes[name] = perfect and maximum or low + rng:Int(0, maximum - low)
        end
        if not perfect then
            separateUniformScores(attributes, names, low, maximum, rng)
        end
        return attributes
    end

    local levelSpan = definition.maxLevel - definition.minLevel
    local progress = levelSpan > 0 and (level - definition.minLevel) / levelSpan or 1
    local ceiling = math.max(minimum, maximum - 1)
    local span = maximum - minimum
    for _, name in ipairs(names) do
        local roll = progress - self.LowRollSpread + rng:Next() * (self.LowRollSpread + self.HighRollSpread)
        attributes[name] = math.Clamp(minimum + math.Round(span * math.Clamp(roll, 0, 1)), minimum, ceiling)
    end
    separateUniformScores(attributes, names, minimum, ceiling, rng)
    return attributes
end

// Builds a validated instance. Options: count, level, playerLevel, danger, mastercraft, mastercraftChance,
// attributes, seed or rng, instanceId. Returns the instance or nil and a reason.
function Generation:CreateInstance(itemId, options)
    options = options or {}
    local definition = Items:GetDefinition(itemId)
    if not definition then
        return nil, "unknown item '" .. tostring(itemId) .. "'"
    end
    local rng = options.rng or self.NewRng(options.seed)
    local level = options.level
    if level == nil then
        level = definition.attributes and self:RollLevel(definition, options.playerLevel, options.danger, rng) or definition.minLevel
    end
    local mastercraft = options.mastercraft == true
    if not mastercraft and definition.attributes and options.mastercraftChance then
        mastercraft = rng:Chance(options.mastercraftChance)
    end
    local attributes = options.attributes and table.Copy(options.attributes) or self:RollAttributes(definition, level, mastercraft, rng)
    local instance = {
        instanceId = options.instanceId or self.NewInstanceId(),
        itemId = itemId,
        count = options.count or 1,
        level = level,
        mastercraft = mastercraft,
        attributes = attributes,
        createdAt = os.time()
    }
    local valid, reason = Items:ValidateInstance(instance)
    if not valid then
        return nil, reason
    end
    return instance
end
