// Shared preview-tool capability state. The server remains authoritative.
ZM_Preview = ZM_Preview or {}
local Preview = ZM_Preview

Preview.Capabilities = {
    diagnostics = 1,
    operator = 2,
    dataAdmin = 4
}
Preview.ClientCapabilities = Preview.ClientCapabilities or 0

function Preview:IsActive()
    return ZM_World and ZM_World:IsLoaded() and ZM_World.ActiveProfile == "preview"
end

function Preview:SetClientCapabilities(capabilities)
    self.ClientCapabilities = math.max(0, math.floor(tonumber(capabilities) or 0))
end

function Preview:HasClientCapability(capability)
    capability = tonumber(capability) or 0
    return self:IsActive() and bit.band(self.ClientCapabilities, capability) == capability
end