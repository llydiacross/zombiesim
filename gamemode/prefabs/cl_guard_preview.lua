return function(api)
    local Preview = { Instances = {} }

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    function Preview:Remove(instance)
        if not instance then return end
        self.Instances[instance] = nil
        if api.IsValid(instance.weapon) then instance.weapon:Remove() end
        if api.IsValid(instance.model) then instance.model:Remove() end
    end

    function Preview:Clear()
        for instance in pairs(self.Instances) do self:Remove(instance) end
    end

    function Preview:Update(instance, guard, origin)
        if not instance or not api.IsValid(instance.model) or not api.IsValid(instance.weapon) then
            return false, "The guard preview model is unavailable."
        end
        if type(guard) ~= "table" or type(guard.position) ~= "table" or type(guard.angles) ~= "table"
            or type(guard.idle) ~= "string" or type(guard.shirt) ~= "string" or type(guard.pants) ~= "string"
            or not finite(guard.position.x) or not finite(guard.position.y) or not finite(guard.position.z)
            or not finite(guard.angles.p) or not finite(guard.angles.y) or not finite(guard.angles.r)
            or not api.IsVector(origin) then return false, "The guard preview settings are invalid." end
        instance.guard = guard
        instance.model:SetPos(origin + api.Vector(guard.position.x, guard.position.y, guard.position.z))
        instance.model:SetAngles(api.Angle(guard.angles.p, guard.angles.y, guard.angles.r))
        if instance.weapon:GetParent() ~= instance.model then
            instance.weapon:SetParent(instance.model)
            instance.weapon:AddEffects(api.EF_BONEMERGE)
            instance.weapon:SetLocalPos(api.Vector(0, 0, 0))
            instance.weapon:SetLocalAngles(api.Angle(0, 0, 0))
        end
        if instance.idle ~= guard.idle then
            instance.idle = guard.idle
            local idle = guard.idle
            api.timer.Simple(0, function()
                if not Preview.Instances[instance] or not api.IsValid(instance.model) or instance.idle ~= idle then return end
                local sequence = instance.model:LookupSequence(idle)
                if type(sequence) ~= "number" or sequence < 0 then
                    api.Report("The guard model does not support idle sequence: " .. idle)
                    return
                end
                instance.model:ResetSequence(sequence)
            end)
        end
        return true
    end

    function Preview:Create(guard, weapon, origin, existingModel)
        if type(guard) ~= "table" or type(guard.model) ~= "string"
            or type(weapon) ~= "table" or type(weapon.model) ~= "string" then
            return nil, "The guard preview model or weapon is unavailable."
        end
        local model = existingModel or api.ClientsideModel(guard.model, api.RENDERGROUP_OTHER)
        if not api.IsValid(model) then return nil, "Could not create guard preview model: " .. guard.model end
        if existingModel and string.lower(model:GetModel() or "") ~= string.lower(guard.model) then
            return nil, "The existing guard preview model does not match the selected citizen."
        end
        local weaponModel = api.ClientsideModel(weapon.model, api.RENDERGROUP_OTHER)
        if not api.IsValid(weaponModel) then
            model:Remove()
            return nil, "Could not create guard weapon preview: " .. weapon.model
        end
        model:SetNoDraw(true)
        weaponModel:SetNoDraw(true)
        local instance = { model = model, weapon = weaponModel }
        self.Instances[instance] = true
        local ok, problem = self:Update(instance, guard, origin)
        if not ok then self:Remove(instance) return nil, problem end
        return instance
    end

    function Preview:ClothingSelections()
        local result = {}
        for instance in pairs(self.Instances) do
            if api.IsValid(instance.model) then
                local guard = instance.guard
                result[#result + 1] = { entity = instance.model, shirt = guard.shirt, pants = guard.pants }
            end
        end
        return result
    end

    function Preview:Draw(instance, skipModel)
        if not instance or not api.IsValid(instance.model) or not api.IsValid(instance.weapon) then
            return false, "The guard preview model was removed."
        end
        if not skipModel then instance.model:DrawModel() end
        instance.weapon:DrawModel()
        return true
    end

    function Preview:Advance(instance)
        if api.IsValid(instance.model) then instance.model:FrameAdvance() end
    end

    function Preview:AdvanceAll()
        for instance in pairs(self.Instances) do self:Advance(instance) end
    end

    return Preview
end
