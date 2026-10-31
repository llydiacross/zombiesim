ENT.Type = "point"
ENT.Base = "base_point"
ENT.PrintName = "ZombieSim Prefab Anchor"
ENT.Spawnable = false

function ENT:KeyValue(key, value)
    self.ZM_Config = self.ZM_Config or {}
    self.ZM_Config[string.lower(key)] = value
end

if SERVER then
    function ENT:AcceptInput(name, activator, caller, value)
        if string.lower(name) ~= "triggerparticle" then return end
        if not ZM_Prefabs then
            ErrorNoHalt("[ZombieSim] Prefab particle trigger: prefab service is unavailable.\n")
            return true
        end
        local ok, problem = ZM_Prefabs:TriggerParticle(self, value)
        if not ok then ErrorNoHalt("[ZombieSim] Prefab particle trigger: " .. tostring(problem) .. "\n") end
        return true
    end
end
