// Shared implant rules: per-instance effect values and the capped aggregate used by the server modifier service.
// Installed implants are { [slotName] = instance }; the server owns them and the client only displays summaries.
ZM_Implants = ZM_Implants or {}
local Implants = ZM_Implants

function Implants:GetSlots()
	return ZM_StaticData.ImplantSlots
end

function Implants:GetDefinition(itemId)
	local definition = ZM_StaticData:GetItem(itemId)
	return definition and definition.implant and definition or nil
end

// An effect's value for one instance: the authored range interpolated by the instance level within the item's levels.
function Implants:GetEffectValue(definition, level, effectId)
	local range = definition and definition.implant and definition.implant.effects[effectId]
	if not range then return 0 end
	local span = definition.maxLevel - definition.minLevel
	local progress = span > 0 and math.Clamp(((tonumber(level) or definition.minLevel) - definition.minLevel) / span, 0, 1) or 1
	return Lerp(progress, range[1], range[2])
end

// Effect values of one installed instance, keyed by effect id.
function Implants:GetInstanceEffects(instance)
	local definition = instance and self:GetDefinition(instance.itemId)
	local effects = {}
	if not definition then return effects end
	for effectId in pairs(definition.implant.effects) do
		effects[effectId] = self:GetEffectValue(definition, instance.level, effectId)
	end
	return effects
end

// Sums installed implants per effect and clamps each sum to its cap. Unknown implants and slots contribute nothing.
// Returns { effects = { id = value }, uncapped = { id = sum }, capped = { id = true } }.
function Implants:Aggregate(installed)
	local result = { effects = {}, uncapped = {}, capped = {} }
	for _, slot in ipairs(self:GetSlots()) do
		local instance = installed and installed[slot]
		local definition = instance and self:GetDefinition(instance.itemId)
		if definition and definition.implant.slot == slot then
			for effectId, value in pairs(self:GetInstanceEffects(instance)) do
				result.uncapped[effectId] = (result.uncapped[effectId] or 0) + value
			end
		end
	end
	for effectId, sum in pairs(result.uncapped) do
		local rule = ZM_StaticData.ImplantEffects[effectId]
		if rule then
			result.effects[effectId] = math.min(sum, rule.cap)
			result.capped[effectId] = sum > rule.cap or nil
		end
	end
	return result
end

// Loot weight bonuses by loot category (for example { weapons = 0.2 }) from aggregated effects.
function Implants:GetLootBonuses(effects)
	local bonuses = {}
	for effectId, value in pairs(effects or {}) do
		local rule = ZM_StaticData.ImplantEffects[effectId]
		if rule and rule.category and rule.category ~= "implants" and value > 0 then
			bonuses[rule.category] = (bonuses[rule.category] or 0) + value
		end
	end
	return bonuses
end

function Implants:FormatEffect(effectId, value)
	local rule = ZM_StaticData.ImplantEffects[effectId]
	if not rule then return tostring(effectId) end
	if rule.unit then
		return string.format("+%.1f %s %s", value, rule.unit, rule.label)
	end
	return string.format("+%d%% %s", math.Round(value * 100), rule.label)
end
