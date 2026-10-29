ENT.Type = "point"
ENT.Base = "base_point"
ENT.PrintName = "ZombieSim Prefab Anchor"
ENT.Spawnable = false

function ENT:KeyValue(key, value)
    self.ZM_Config = self.ZM_Config or {}
    self.ZM_Config[string.lower(key)] = value
end
