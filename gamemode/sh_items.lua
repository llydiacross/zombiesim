// Shared item-instance rules and use requirements. Definitions come from ZM_StaticData; instances are plain tables:
// { instanceId, itemId, count, level, mastercraft, attributes } and are created and changed only by the server.
ZM_Items = ZM_Items or {}
local Items = ZM_Items

Items.Containers = { backpack = true, stash = true, equipped = true }
Items.ContainerCapacity = { backpack = 20, stash = 60, equipped = 3 }
Items.DefaultJob = "Civilian"

local ply = FindMetaTable("Player")

function ply:GetLevel()
    return math.floor(tonumber(self.Level) or self:GetNWInt("Level", 1))
end

// Returns a player attribute value such as Strength or Medicine (0 when unknown).
function ply:GetStat(name)
    local attributes = self.Attributes
    return tonumber(attributes and attributes[name]) or 0
end

function ply:GetJobRole()
    local job = self.Job or self:GetNWString("Job", "")
    return job ~= "" and job or Items.DefaultJob
end

function Items:GetDefinition(itemId)
    return ZM_StaticData:GetItem(itemId)
end

// Stackable instances share an item id and level and carry no per-instance attributes or mastercraft.
function Items:CanStack(first, second)
    local definition = self:GetDefinition(first.itemId)
    return definition ~= nil and definition.maxStack > 1
        and first.itemId == second.itemId
        and first.level == second.level
        and not first.mastercraft and not second.mastercraft
        and first.attributes == nil and second.attributes == nil
end

// Validates an instance against its definition. Returns true or false plus a reason.
function Items:ValidateInstance(instance)
    if type(instance) ~= "table" then
        return false, "instance must be a table"
    end
    if type(instance.instanceId) ~= "string" or not string.match(instance.instanceId, "^[%w_-]+$") or #instance.instanceId > 64 then
        return false, "instance id is invalid"
    end
    local definition = self:GetDefinition(instance.itemId)
    if not definition then
        return false, "unknown item '" .. tostring(instance.itemId) .. "'"
    end
    local count = tonumber(instance.count)
    if not count or count ~= math.floor(count) or count < 1 or count > definition.maxStack then
        return false, "count must be a whole number from 1 to " .. definition.maxStack
    end
    local level = tonumber(instance.level)
    if not level or level ~= math.floor(level) or level < definition.minLevel or level > definition.maxLevel then
        return false, "level must be from " .. definition.minLevel .. " to " .. definition.maxLevel
    end
    if instance.mastercraft and not definition.attributes then
        return false, "only items with a weapon type can be mastercrafted"
    end
    if instance.attributes ~= nil then
        if not definition.attributes then
            return false, "this item cannot carry attributes"
        end
        if type(instance.attributes) ~= "table" then
            return false, "attributes must be a table"
        end
        local allowed = {}
        for _, name in ipairs(definition.attributes) do
            allowed[name] = true
        end
        for name, value in pairs(instance.attributes) do
            if not allowed[name] then
                return false, "attribute '" .. tostring(name) .. "' does not apply to this item"
            end
            if type(value) ~= "number" or value ~= math.floor(value) or value < definition.minAttributes or value > definition.maxAttributes then
                return false, "attribute '" .. name .. "' must be a whole number from " .. definition.minAttributes .. " to " .. definition.maxAttributes
            end
        end
    end
    return true
end

// Multiplier at the lowest and highest attribute score. Missing attributes are neutral (1).
// Swiftness, FiringSpeed, and ReloadSpeed scale a duration, so better scores give smaller multipliers.
Items.AttributeEffects = {
    Damage = { 0.6, 1.6 },
    Range = { 0.8, 1.3 },
    Swiftness = { 1.3, 0.7 },
    Crushing = { 0.5, 2.0 },
    FiringSpeed = { 1.3, 0.7 },
    ReloadSpeed = { 1.4, 0.6 },
    ClipSize = { 0.75, 1.5 }
}

// Returns an attribute score as 0..1 within the item's minAttributes..maxAttributes range.
function Items:GetAttributeProgress(definition, score)
    local span = definition.maxAttributes - definition.minAttributes
    if span <= 0 then
        return 1
    end
    return math.Clamp((score - definition.minAttributes) / span, 0, 1)
end

function Items:GetWeaponScales(instance)
    local scales = {}
    for name in pairs(self.AttributeEffects) do
        scales[name] = 1
    end
    local definition = instance and self:GetDefinition(instance.itemId)
    if not definition or not definition.attributes or not instance.attributes then
        return scales
    end
    for _, name in ipairs(definition.attributes) do
        local score = instance.attributes[name]
        local effect = self.AttributeEffects[name]
        if score and effect then
            scales[name] = Lerp(self:GetAttributeProgress(definition, score), effect[1], effect[2])
        end
    end
    return scales
end

// Stack value. Weapon value rises with level and attribute scores and triples for mastercrafts.
function Items:GetInstanceValue(instance)
    local definition = self:GetDefinition(instance.itemId)
    if not definition then
        return 0
    end
    local value = definition.value * instance.count
    if definition.attributes then
        local levelSpan = definition.maxLevel - definition.minLevel
        local levelProgress = levelSpan > 0 and (instance.level - definition.minLevel) / levelSpan or 0
        local attributeProgress = 0
        if instance.attributes then
            for _, name in ipairs(definition.attributes) do
                attributeProgress = attributeProgress + self:GetAttributeProgress(definition, instance.attributes[name] or definition.minAttributes)
            end
            attributeProgress = attributeProgress / #definition.attributes
        end
        value = value * (1 + levelProgress) * (1 + attributeProgress)
        if instance.mastercraft then
            value = value * 3
        end
    end
    return math.Round(value, 2)
end

// Checks level and stat requirements for using an item. Returns true or false plus a player-facing reason.
function Items:CanUse(user, itemId)
    if not IsValid(user) then
        return false, "Player is invalid."
    end
    local definition = self:GetDefinition(itemId)
    if not definition then
        return false, "Unknown item."
    end
    if user:GetLevel() < definition.minLevel then
        return false, "Requires level " .. definition.minLevel .. "."
    end
    for stat, required in SortedPairs(definition.statRequirements) do
        if user:GetStat(stat) < required then
            return false, "Requires " .. stat .. " " .. required .. "."
        end
    end
    return true, ""
end

function Items:GetDisplayName(instance)
    local definition = self:GetDefinition(instance.itemId)
    local name = definition and definition.name or instance.itemId
    if instance.mastercraft then
        name = name .. " (MC)"
    end
    return name
end

// Behaviour classes for usable "entity" items, keyed by item id. Items without their own class use GenericItem.
// Classes only decide and apply effects; the server inventory consumes one unit after OnUse succeeds.
ZM_EntityClasses = ZM_EntityClasses or {}
ZM_EntityClasses.GenericItem = ZM_EntityClasses.GenericItem or {}
local GenericItem = ZM_EntityClasses.GenericItem
GenericItem.__index = GenericItem

// Checks the user's level and stat requirements. targetPly is set when applying the item to another player.
function GenericItem:CanUse(ply, itemData, targetPly)
    if not IsValid(ply) or not ply:Alive() then
        return false, "Player is dead or invalid."
    end
    return Items:CanUse(ply, itemData.id)
end

// Server-only effect. Return true when the item was used and should be consumed.
function GenericItem:OnUse(ply, itemData, targetPly)
    return true
end

// Creates a class that inherits GenericItem, for use in gamemode/items/*.lua.
function Items:NewItemClass()
    return setmetatable({}, GenericItem)
end

function Items:GetItemClass(itemId)
    return ZM_EntityClasses[itemId] or GenericItem
end

// Server: copies an instance's attribute multipliers onto a ZombieSim weapon's networked scale variables.
function Items:ApplyInstanceToWeapon(weapon, instance)
    local scales = self:GetWeaponScales(instance)
    weapon:SetDamageScale(scales.Damage)
    weapon:SetRangeScale(scales.Range)
    weapon:SetSpeedScale(scales.Swiftness * scales.FiringSpeed)
    weapon:SetCrushScale(scales.Crushing)
    weapon:SetReloadScale(scales.ReloadSpeed)
    weapon:SetClipScale(scales.ClipSize)
    weapon:SetItemInstanceId(instance.instanceId)
    if weapon.OnItemInstanceApplied then
        weapon:OnItemInstanceApplied()
    end
end
