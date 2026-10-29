return function(api)
    local Sync = { Pending = {}, Applied = {} }
    local key = "ZM.PrefabFixtureScale"

    function Sync:Queue(entity, scale)
        if not api.IsValid(entity) or entity:GetClass() ~= "prop_physics" or type(scale) ~= "number"
            or scale ~= scale or scale < 0.1 or scale > 10 or scale == 1 then return end
        if self.Applied[entity] == scale or self.Pending[entity] and self.Pending[entity].scale == scale then return end
        self.Pending[entity] = { scale = scale, deadline = api.CurTime() + 5 }
    end

    function Sync:Think()
        for entity, entry in pairs(self.Pending) do
            if not api.IsValid(entity) then
                self.Pending[entity], self.Applied[entity] = nil, nil
            elseif entity:IsDormant() then
                self.Pending[entity] = nil
            elseif math.abs(entity:GetModelScale() - entry.scale) < 0.0001 then
                entity:Activate()
                self.Applied[entity], self.Pending[entity] = entry.scale, nil
            elseif api.CurTime() >= entry.deadline then
                api.ErrorNoHalt("[ZombieSim] Prefab fixture client scale did not synchronize for entity "
                    .. tostring(entity:EntIndex()) .. ".\n")
                self.Pending[entity] = nil
            end
        end
    end

    api.hook.Add("EntityNetworkedVarChanged", "ZM.PrefabFixture.Scale", function(entity, name, _, value)
        if name == key then Sync:Queue(entity, value) end
    end)
    api.hook.Add("NetworkEntityCreated", "ZM.PrefabFixture.Scale", function(entity)
        if not api.IsValid(entity) or entity:GetClass() ~= "prop_physics" then return end
        api.timer.Simple(0, function()
            if api.IsValid(entity) then Sync:Queue(entity, entity:GetNW2Float(key, 0)) end
        end)
    end)
    api.hook.Add("NotifyShouldTransmit", "ZM.PrefabFixture.Scale", function(entity, transmitting)
        if not transmitting then
            Sync.Pending[entity], Sync.Applied[entity] = nil, nil
        elseif api.IsValid(entity) and entity:GetClass() == "prop_physics" then
            api.timer.Simple(0, function()
                if api.IsValid(entity) then Sync:Queue(entity, entity:GetNW2Float(key, 0)) end
            end)
        end
    end)
    api.hook.Add("EntityRemoved", "ZM.PrefabFixture.Scale", function(entity)
        Sync.Pending[entity], Sync.Applied[entity] = nil, nil
    end)
    api.hook.Add("Think", "ZM.PrefabFixture.Scale", function() Sync:Think() end)
    return Sync
end
