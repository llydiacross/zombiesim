// Shared profession rules. Definitions come from data_static/profession_definitions.json through ZM_StaticData.
// A stored job name resolves (id or alias) to one profession; unknown names fall back to Civilian without being
// rewritten, so a later data update can still recognise them. Stat bonuses are derived here and never persisted.
ZM_Professions = ZM_Professions or {}
local Professions = ZM_Professions
local StaticData = ZM_StaticData

function Professions:Get(job)
    return StaticData:GetProfession(job)
end

// Canonical profession id for a stored job name.
function Professions:Resolve(job)
    local profession = self:Get(job)
    return profession and profession.id or StaticData.DefaultProfession
end

function Professions:GetStatBonus(job, attribute)
    local profession = self:Get(job)
    return profession and profession.statBonuses[attribute] or 0
end

function Professions:OffersService(job, service)
    local profession = self:Get(job)
    return profession ~= nil and profession.services[service] == true
end

// The highest delivery tier whose minLevel the player level meets, or nil when the profession has no deliveries.
function Professions:GetDeliveryTier(job, level)
    local profession = self:Get(job)
    local chosen
    for _, tier in ipairs(profession and profession.deliveries or {}) do
        if (tonumber(level) or 1) >= tier.minLevel then
            chosen = tier
        end
    end
    return chosen
end

// Sorted canonical profession ids, for command help and reports.
function Professions:GetIds()
    local registry = StaticData:GetRegistry()
    local ids = table.GetKeys(registry and registry.professions or {})
    table.sort(ids)
    return ids
end
