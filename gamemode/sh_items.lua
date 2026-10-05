// Shared item-instance rules and use requirements. Definitions come from ZM_StaticData; instances are plain tables:
// { instanceId, itemId, count, level, mastercraft, attributes } and are created and changed only by the server.
ZM_Items = ZM_Items or {}
local Items = ZM_Items

Items.Containers = { backpack = true, stash = true, equipped = true }
Items.ContainerCapacity = { backpack = 20, stash = 60, equipped = 6 }
Items.ArmourSlot = 4
Items.DefaultJob = "Civilian"
Items.MaximumWeaponClip = 64

local ply = FindMetaTable("Player")

function ply:GetLevel()
    return math.floor(tonumber(self.Level) or self:GetNWInt("Level", 1))
end

// Returns a player's allocated attribute points, without profession bonuses (0 when unknown).
function ply:GetBaseStat(name)
    local attributes = self.Attributes
    return tonumber(attributes and attributes[name]) or 0
end

// Returns an effective attribute value such as Strength or Medicine: allocated points plus the profession bonus.
function ply:GetStat(name)
    local bonus = ZM_Professions and ZM_Professions:GetStatBonus(self:GetJobRole(), name) or 0
    return self:GetBaseStat(name) + bonus
end

// Raw stored job name (may be an alias or an unknown legacy value).
function ply:GetStoredJob()
    local job = self.Job or self:GetNWString("Job", "")
    return job ~= "" and job or Items.DefaultJob
end

// Canonical profession id for the stored job; aliases resolve and unknown jobs fall back to Civilian.
function ply:GetJobRole()
    local job = self:GetStoredJob()
    return ZM_Professions and ZM_Professions:Resolve(job) or job
end

function Items:GetDefinition(itemId)
    return ZM_StaticData:GetItem(itemId)
end

function Items:IsEquipmentSlot(instance, slot)
    if type(slot) ~= "number" or slot ~= math.floor(slot) then return false end
    local definition = instance and self:GetDefinition(instance.itemId)
    if not definition then return false end
    if definition.entityClass == "armour" then return slot == self.ArmourSlot end
    if definition.entityClass == "clothing" then return slot == ZM_Clothing.Slots[definition.clothing.garment] end
    return definition.entityClass == "weapon" and slot >= 1 and slot <= 3
end

function Items:HasRadiationProtection(inventory)
    local instance = inventory and inventory.equipped and inventory.equipped[self.ArmourSlot]
    local definition = instance and self:GetDefinition(instance.itemId)
    return definition ~= nil and definition.entityClass == "armour" and definition.radiationProtection == true
end

function ply:HasRadiationProtection()
    if SERVER then return Items:HasRadiationProtection(self.ZM_Inventory) end
    return self:GetNWBool("ZM_RadiationProtected", false)
end

function Items:GetRequiredLevel(itemId, instance)
    local definition = self:GetDefinition(itemId)
    if not definition then
        return nil
    end
    if definition.entityClass == "weapon" and type(instance) == "table" then
        return math.max(definition.minLevel, math.floor(tonumber(instance.level) or definition.minLevel))
    end
    return definition.minLevel
end

// Stackable instances share an item id and level and carry no per-instance attributes or mastercraft.
// Perishable food additionally requires the same freshness band at `now` (default: current time).
function Items:CanStack(first, second, now)
    local definition = self:GetDefinition(first.itemId)
    return definition ~= nil and definition.maxStack > 1
        and first.itemId == second.itemId
        and first.level == second.level
        and not first.mastercraft and not second.mastercraft
        and first.attributes == nil and second.attributes == nil
        and (not definition.food or not ZM_Food or ZM_Food:CanStack(first, second, now))
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
    local clip = tonumber(instance.clip) or 0
    if clip ~= math.floor(clip) or clip < 0 or clip > self.MaximumWeaponClip then
        return false, "clip must be a whole number from 0 to " .. self.MaximumWeaponClip
    end
    if clip > 0 and definition.type ~= "bullet_weapon" then
        return false, "only bullet weapons can store loaded rounds"
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
            value = value * (self:IsUltraMastercraft(instance) and 5 or 3)
        end
    end
    return math.Round(value, 2)
end

// An Ultra Mastercraft is a mastercraft whose every attribute is at the item's maximum.
function Items:IsUltraMastercraft(instance)
    local definition = instance and instance.mastercraft and self:GetDefinition(instance.itemId)
    if not definition or not definition.attributes or type(instance.attributes) ~= "table" then return false end
    for _, name in ipairs(definition.attributes) do
        if instance.attributes[name] ~= definition.maxAttributes then return false end
    end
    return true
end

// Checks level and stat requirements for using an item. Returns true or false plus a player-facing reason.
function Items:CanUse(user, itemId, instance)
    if not IsValid(user) then
        return false, "Player is invalid."
    end
    local definition = self:GetDefinition(itemId)
    if not definition then
        return false, "Unknown item."
    end
    local requiredLevel = self:GetRequiredLevel(itemId, instance)
    if user:GetLevel() < requiredLevel then
        return false, "Requires player level " .. requiredLevel .. "."
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
        name = name .. (self:IsUltraMastercraft(instance) and " (Ultra MC)" or " (MC)")
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
    if ZM_EntityClasses[itemId] then
        return ZM_EntityClasses[itemId]
    end
    local definition = self:GetDefinition(itemId)
    if definition and definition.food and ZM_EntityClasses.FoodItem then
        return ZM_EntityClasses.FoodItem
    end
    if definition and definition.medical and ZM_EntityClasses.MedicalItem then
        return ZM_EntityClasses.MedicalItem
    end
    return GenericItem
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
        weapon:OnItemInstanceApplied(instance)
    end
end
