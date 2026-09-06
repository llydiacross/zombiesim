// Dedicated Hammer marker for selecting a ZombieSim world-data profile on a map.
ENT.Type = "point"
ENT.Base = "base_point"
ENT.PrintName = "ZombieSim World Profile"
ENT.Spawnable = false
ENT.AdminOnly = false

// Replicates the map-authored profile so both realms load the same world index.
function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "WorldProfile")
    self:NetworkVar("Float", 0, "StartDelay")
end

// Reads Hammer keyvalues before this map entity initializes.
function ENT:KeyValue(key, value)
    if SERVER and string.lower(key) == "world_profile" then
        self:SetWorldProfile(string.lower(string.Trim(value)))
    elseif SERVER and string.lower(key) == "start_delay" then
        self:SetStartDelay(math.max(tonumber(value) or 0, 0))
    end
end

// A placed marker with no keyvalue selects the normal city data profile.
function ENT:Initialize()
    if SERVER and self:GetWorldProfile() == "" then
        self:SetWorldProfile("city")
    end
    if SERVER and self:GetStartDelay() < 0 then
        self:SetStartDelay(0)
    end
end
