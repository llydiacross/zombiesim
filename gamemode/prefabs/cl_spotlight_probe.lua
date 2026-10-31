return function(api)
    local Probe = { Updates = 0 }
    local modes = {
        normal = { brightness = 1, shadows = true },
        bright = { brightness = 6, shadows = true },
        unshadowed = { brightness = 6, shadows = false },
        compare = { brightness = 6, shadows = true },
        matrix = { brightness = 6, shadows = true }
    }

    function Probe:Stop()
        if api.IsValid(self.Light) then self.Light:Remove() end
        if api.IsValid(self.ComparisonModel) then self.ComparisonModel:Remove() end
        if api.IsValid(self.ManualModel) then self.ManualModel:Remove() end
        self.Light, self.Pending = nil, false
        self.ComparisonModel, self.ManualModel, self.ManualPair, self.ManualMatrix, self.ManualEditorSetup =
            nil, nil, nil, nil, nil
        self.Mode, self.Brightness, self.Shadows = nil, nil, nil
    end

    function Probe:Start(mode)
        if not api.Editor:IsActive() or not api.Editor.Origin then
            return false, "Open the prefab editor before starting the spotlight preview."
        end
        local settings = modes[mode]
        if not settings then return false, "Unknown spotlight preview mode." end
        if api.IsValid(self.Light) then return false, "The spotlight preview is already active." end
        local material = api.Material("effects/flashlight001")
        local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
        if not texture or texture:Width() <= 0 or texture:Height() <= 0 then
            return false, "The mounted spotlight texture is unavailable."
        end
        local light = api.ProjectedTexture()
        if not api.IsValid(light) then return false, "Could not allocate the spotlight preview." end
        self.Light = light
        if mode == "compare" or mode == "matrix" then
            local model = api.ClientsideModel("models/props_c17/oildrum001.mdl",
                mode == "matrix" and api.RENDERGROUP_OTHER or api.RENDERGROUP_OPAQUE)
            if not api.IsValid(model) then
                self:Stop()
                return false, "Could not create the client-side spotlight comparison model."
            end
            self.ComparisonModel = model
            model:SetPos(api.Editor.Origin + api.Vector(80, mode == "matrix" and 80 or 45, 0))
            model:SetAngles(api.Angle(0, 0, 0))
            if mode == "matrix" then
                model:SetNoDraw(true)
                local matrix = api.Matrix()
                matrix:Scale(api.Vector(1, 1, 1))
                model:EnableMatrix("RenderMultiply", matrix)
                self.ManualPair = true
            end
            local manual = api.ClientsideModel("models/props_c17/oildrum001.mdl", api.RENDERGROUP_OTHER)
            if not api.IsValid(manual) then
                self:Stop()
                return false, "Could not create the manually drawn spotlight comparison model."
            end
            self.ManualModel = manual
            manual:SetNoDraw(true)
            manual:SetPos(api.Editor.Origin + api.Vector(80, mode == "matrix" and -80 or -45, 0))
            manual:SetAngles(api.Angle(0, 0, 0))
        end
        self.TextureWidth = texture:Width()
        self.TextureHeight = texture:Height()
        light:SetTexture("effects/flashlight001")
        light:SetOrthographic(false, 0, 0, 0, 0)
        light:SetFOV(60)
        light:SetNearZ(8)
        light:SetFarZ(512)
        light:SetColor(api.Color(255, 235, 200))
        light:SetBrightness(settings.brightness)
        light:SetEnableShadows(settings.shadows)
        light:SetPos(api.Editor.Origin + api.Vector(-80, -160, 192))
        light:SetAngles(api.Angle(40, 45, 0))
        self.Mode, self.Brightness, self.Shadows = mode, settings.brightness, settings.shadows
        self.Updates = 0
        self.Pending = true
        return true
    end

    function Probe:SetManualMatrix(enabled)
        if not api.IsValid(self.ManualModel) or not api.IsValid(self.Light) then
            return false, "Start a comparison with a manually drawn drum first."
        end
        if enabled then
            local matrix = api.Matrix()
            matrix:Scale(api.Vector(1, 1, 1))
            self.ManualModel:EnableMatrix("RenderMultiply", matrix)
        else
            self.ManualModel:DisableMatrix("RenderMultiply")
        end
        self.ManualMatrix = enabled
        self.Pending = true
        return true
    end

    function Probe:RemoveComparison()
        if not api.IsValid(self.ComparisonModel) then return false, "No comparison model is active." end
        self.ComparisonModel:Remove()
        self.ComparisonModel = nil
        return true
    end

    function Probe:MatchEditorModel()
        if not api.IsValid(self.ManualModel) or not api.IsValid(self.Light) then
            return false, "Start a comparison with a manually drawn drum first."
        end
        self.ManualModel:SetSkin(0)
        local ok, problem = self:SetManualMatrix(true)
        if not ok then return false, problem end
        local minimum, maximum = self.ManualModel:GetModelBounds()
        self.ManualModel:SetRenderBounds(minimum, maximum)
        self.ManualEditorSetup = true
        return true
    end

    function Probe:Render(depth, skybox)
        if depth or skybox or not self.Pending or not api.IsValid(self.Light) then return end
        if not api.Editor:IsActive() then self:Stop() return end
        self.Light:Update()
        self.Pending = false
        self.Updates = self.Updates + 1
    end

    function Probe:Status()
        local status = { active = api.IsValid(self.Light), pending = self.Pending == true,
            textureWidth = self.TextureWidth, textureHeight = self.TextureHeight,
            updates = self.Updates, mode = self.Mode, brightness = self.Brightness,
            shadows = api.IsValid(self.Light) and self.Shadows == true,
            comparisonModel = api.IsValid(self.ComparisonModel), manualModel = api.IsValid(self.ManualModel),
            manualMatrix = self.ManualMatrix == true, manualEditorSetup = self.ManualEditorSetup == true }
        if status.active then
            local position, angles, color = self.Light:GetPos(), self.Light:GetAngles(), self.Light:GetColor()
            status.projector = {
                position = { x = position.x, y = position.y, z = position.z },
                angles = { p = angles.p, y = angles.y, r = angles.r },
                color = { r = color.r, g = color.g, b = color.b },
                brightness = self.Light:GetBrightness(), fov = self.Light:GetHorizontalFOV(),
                range = self.Light:GetFarZ(), shadows = self.Light:GetEnableShadows()
            }
        end
        return status
    end

    api.hook.Add("PreDrawOpaqueRenderables", "ZM.PrefabSpotlightProbe", function(depth, skybox)
        Probe:Render(depth, skybox)
    end)
    api.hook.Add("PostDrawTranslucentRenderables", "ZM.PrefabSpotlightProbe", function(depth, skybox)
        if not depth and not skybox and Probe.ManualPair and api.IsValid(Probe.ComparisonModel) then
            Probe.ComparisonModel:DrawModel()
        end
        if not depth and not skybox and api.IsValid(Probe.ManualModel) then Probe.ManualModel:DrawModel() end
    end)
    api.hook.Add("Think", "ZM.PrefabSpotlightProbe", function()
        if api.IsValid(Probe.Light) and not api.Editor:IsActive() then Probe:Stop() end
    end)
    api.hook.Add("PreCleanupMap", "ZM.PrefabSpotlightProbe", function() Probe:Stop() end)
    api.hook.Add("ShutDown", "ZM.PrefabSpotlightProbe", function() Probe:Stop() end)
    return Probe
end
