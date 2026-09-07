// Shared opt-in API for any entity that should appear on the player compass.
// Example: self:SetZMCompassMarker("objective", "Restore the generator")
local entityMeta = FindMetaTable("Entity")

function entityMeta:SetZMCompassMarker(icon, label)
    local marker = {
        icon = string.sub(tostring(icon or "objective"), 1, 16),
        label = string.sub(tostring(label or ""), 1, 64)
    }

    if SERVER then
        self:SetNWBool("ZMCompassVisible", true)
        self:SetNWString("ZMCompassIcon", marker.icon)
        self:SetNWString("ZMCompassLabel", marker.label)
    else
        self.ZMCompassMarker = marker
    end
end

function entityMeta:ClearZMCompassMarker()
    if SERVER then
        self:SetNWBool("ZMCompassVisible", false)
        self:SetNWString("ZMCompassIcon", "")
        self:SetNWString("ZMCompassLabel", "")
    else
        self.ZMCompassMarker = nil
    end
end

function entityMeta:GetZMCompassMarker()
    if self.ZMCompassMarker then
        return self.ZMCompassMarker
    end
    if not self:GetNWBool("ZMCompassVisible", false) then
        return nil
    end

    return {
        icon = self:GetNWString("ZMCompassIcon", "objective"),
        label = self:GetNWString("ZMCompassLabel", "")
    }
end