return function(api)
    local Pool = { States = {} }
    local maximumLights, nearZ = 8, 8
    local texturePath = "effects/flashlight001"

    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    local function coordinates(value, keys, engineType)
        if type(value) ~= "table" and (not engineType or not engineType(value)) then return false end
        for _, key in ipairs(keys) do
            if not finite(value[key]) then return false end
        end
        return true
    end

    local positionKeys = { "x", "y", "z" }
    local angleKeys = { "p", "y", "r" }
    local colorKeys = { "r", "g", "b" }

    local function validate(candidate)
        if type(candidate) ~= "table" or type(candidate.id) ~= "string" or candidate.id == ""
            or not coordinates(candidate.position, positionKeys, api.IsVector)
            or not coordinates(candidate.angles, angleKeys, api.IsAngle)
            or not coordinates(candidate.color, colorKeys) then
            return false
        end
        for _, key in ipairs(colorKeys) do
            local component = candidate.color[key]
            if component < 0 or component > 255 or component ~= math.floor(component) then return false end
        end
        return finite(candidate.brightness) and candidate.brightness >= 0
            and finite(candidate.fov) and candidate.fov > 0 and candidate.fov < 180
            and finite(candidate.range) and candidate.range > nearZ
    end

    local function snapshot(candidate)
        return {
            position = { x = candidate.position.x, y = candidate.position.y, z = candidate.position.z },
            angles = { p = candidate.angles.p, y = candidate.angles.y, r = candidate.angles.r },
            color = { r = candidate.color.r, g = candidate.color.g, b = candidate.color.b },
            brightness = candidate.brightness, fov = candidate.fov, range = candidate.range
        }
    end

    local function changed(left, right)
        if not left then return true end
        for _, key in ipairs(positionKeys) do if left.position[key] ~= right.position[key] then return true end end
        for _, key in ipairs(angleKeys) do if left.angles[key] ~= right.angles[key] then return true end end
        for _, key in ipairs(colorKeys) do if left.color[key] ~= right.color[key] then return true end end
        return left.brightness ~= right.brightness or left.fov ~= right.fov or left.range ~= right.range
    end

    local function configure(light, candidate)
        local position, angles, color = candidate.position, candidate.angles, candidate.color
        light:SetPos(api.Vector(position.x, position.y, position.z))
        light:SetAngles(api.Angle(angles.p, angles.y, angles.r))
        light:SetColor(api.Color(color.r, color.g, color.b))
        light:SetBrightness(candidate.brightness)
        light:SetFOV(candidate.fov)
        light:SetFarZ(candidate.range)
    end

    function Pool:Clear()
        for _, state in pairs(self.States) do
            if api.IsValid(state.light) then state.light:Remove() end
        end
        self.States = {}
        self.TextureWidth, self.TextureHeight = nil, nil
    end

    function Pool:Reconcile(camera, candidates, refresh)
        if not coordinates(camera, positionKeys, api.IsVector) or type(candidates) ~= "table" or type(refresh) ~= "boolean" then
            self:Clear()
            return false, "Invalid prefab spotlight camera, candidates or refresh flag."
        end
        local ordered, ids, count, maximum = {}, {}, 0, 0
        for key, candidate in pairs(candidates) do
            count = count + 1
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or not validate(candidate)
                or ids[candidate.id] then
                self:Clear()
                return false, "Invalid or duplicate prefab spotlight candidate."
            end
            ids[candidate.id] = true
            maximum = math.max(maximum, key)
            local dx, dy, dz = candidate.position.x - camera.x, candidate.position.y - camera.y,
                candidate.position.z - camera.z
            local distance = dx * dx + dy * dy + dz * dz
            if not finite(distance) then
                self:Clear()
                return false, "Prefab spotlight distance is not finite."
            end
            ordered[#ordered + 1] = { candidate = candidate, distance = distance }
        end
        if maximum ~= count then
            self:Clear()
            return false, "Prefab spotlight candidates must be a contiguous list."
        end
        table.sort(ordered, function(left, right)
            if left.distance ~= right.distance then return left.distance < right.distance end
            return left.candidate.id < right.candidate.id
        end)

        local selected = {}
        for index = 1, math.min(#ordered, maximumLights) do
            selected[ordered[index].candidate.id] = true
        end
        for id, state in pairs(self.States) do
            if not selected[id] or not api.IsValid(state.light) then
                if api.IsValid(state.light) then state.light:Remove() end
                self.States[id] = nil
            end
        end

        local nearest = ordered[1] and ordered[1].candidate.id or nil
        for id, state in pairs(self.States) do
            if state.shadow and id ~= nearest then
                state.light:SetEnableShadows(false)
                state.light:Update()
                state.updates = (state.updates or 0) + 1
                state.shadow = false
            end
        end

        for index = 1, math.min(#ordered, maximumLights) do
            local candidate = ordered[index].candidate
            local state = self.States[candidate.id]
            if not state then
                local material = api.Material(texturePath)
                local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
                if not texture or texture:Width() <= 0 or texture:Height() <= 0 then
                    self:Clear()
                    return false, "The mounted prefab spotlight texture is unavailable."
                end
                self.TextureWidth, self.TextureHeight = texture:Width(), texture:Height()
                local light = api.ProjectedTexture()
                if not api.IsValid(light) then
                    self:Clear()
                    return false, "Could not allocate a prefab spotlight."
                end
                light:SetTexture(texturePath)
                light:SetOrthographic(false, 0, 0, 0, 0)
                light:SetNearZ(nearZ)
                state = { light = light, shadow = false }
                self.States[candidate.id] = state
            end
            local shadow = candidate.id == nearest
            local dirty = changed(state.settings, candidate)
            if dirty then
                configure(state.light, candidate)
                state.settings = snapshot(candidate)
            end
            if state.shadow ~= shadow or not state.initialized then
                state.light:SetEnableShadows(shadow)
                state.shadow = shadow
                dirty = true
            end
            if dirty or refresh then
                state.light:Update()
                state.updates = (state.updates or 0) + 1
            end
            state.initialized = true
        end
        return true
    end

    function Pool:Status()
        local active, shadowed, projectors = 0, 0, {}
        for id, state in pairs(self.States) do
            if api.IsValid(state.light) then
                active = active + 1
                if state.shadow then shadowed = shadowed + 1 end
                local position, angles, color = state.light:GetPos(), state.light:GetAngles(), state.light:GetColor()
                projectors[#projectors + 1] = {
                    id = id, shadowRequested = state.shadow, shadowEnabled = state.light:GetEnableShadows(),
                    position = { x = position.x, y = position.y, z = position.z },
                    angles = { p = angles.p, y = angles.y, r = angles.r },
                    color = { r = color.r, g = color.g, b = color.b },
                    brightness = state.light:GetBrightness(), fov = state.light:GetHorizontalFOV(),
                    range = state.light:GetFarZ(), updates = state.updates or 0
                }
            end
        end
        table.sort(projectors, function(left, right) return left.id < right.id end)
        return { active = active, shadowed = shadowed, maximum = maximumLights,
            textureWidth = self.TextureWidth, textureHeight = self.TextureHeight, projectors = projectors }
    end

    return Pool
end
