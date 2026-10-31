// Shared profession rules. Definitions come from data_static/profession_definitions.json through ZM_StaticData.
// A stored job name resolves (id or alias) to one profession; unknown names fall back to Civilian without being
// rewritten, so a later data update can still recognise them. Each survivor retains their saved bonus ruleset.
ZM_Professions = ZM_Professions or {}
local Professions = ZM_Professions
local StaticData = ZM_StaticData

Professions.LegacyBonusVersion = StaticData.LegacyProfessionBonusVersion
Professions.CurrentBonusVersion = StaticData.CurrentProfessionBonusVersion

function Professions:Get(job)
    return StaticData:GetProfession(job)
end

// Input validation must not use Get(), because stored unknown names intentionally resolve to Civilian.
function Professions:GetKnown(job)
    local registry = StaticData:GetRegistry()
    if not registry or type(job) ~= "string" then return nil end
    local id = registry.professions[job] and job or registry.professionAliases[job]
    return id and registry.professions[id] or nil
end

// Canonical profession id for a stored job name.
function Professions:Resolve(job)
    local profession = self:Get(job)
    return profession and profession.id or StaticData.DefaultProfession
end

function Professions:IsValidBonusVersion(version)
    return version == self.LegacyBonusVersion or version == self.CurrentBonusVersion
end

function Professions:GetStatBonuses(job, version)
    if not self:IsValidBonusVersion(version) then
        error("Unsupported profession bonus version: " .. tostring(version), 2)
    end
    local profession = self:Get(job)
    if not profession then return nil end
    local bonuses
    if version == self.LegacyBonusVersion then
        bonuses = profession.legacyStatBonuses
    else
        bonuses = profession.statBonuses
    end
    if type(bonuses) ~= "table" then
        error("Missing profession bonuses for " .. tostring(profession.id) .. " version " .. version, 2)
    end
    return bonuses
end

function Professions:GetStatBonus(job, attribute, version)
    local bonuses = self:GetStatBonuses(job, version)
    return bonuses and bonuses[attribute] or 0
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
