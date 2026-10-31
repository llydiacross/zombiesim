return function(api, pool)
    local Preview = { Error = nil, RetryAt = 0, Suspended = false }

    function Preview:Clear()
        pool:Clear()
        self.Error, self.RetryAt, self.Suspended = nil, 0, false
    end

    function Preview:SetSuspended(value)
        self.Suspended = value
        if value then pool:Clear() end
    end

    function Preview:Render(depth, skybox)
        if depth or skybox then return end
        local editor = api.GetEditor()
        if not editor or not editor:IsActive() then
            self:Clear()
            return
        end
        if self.Suspended then return end
        if self.Error and api.CurTime() < self.RetryAt then return end
        local candidates = {}
        for _, light in ipairs(editor.Document.lights) do
            candidates[#candidates + 1] = {
                id = light.lightId,
                position = editor:GetPreviewOrigin() + api.Vector(light.position.x, light.position.y, light.position.z),
                angles = light.angles, color = light.color,
                brightness = light.brightness, fov = light.fov, range = light.range
            }
        end
        local view = editor:GetView(90)
        local ok, problem = pool:Reconcile(view.origin, candidates, editor.SceneRefresh == true)
        if not ok then
            if self.Error ~= problem then editor:Message(problem, true) end
            self.Error, self.RetryAt = problem, api.CurTime() + 1
            return
        end
        self.Error, self.RetryAt = nil, 0
        editor.SceneRefresh = false
    end

    function Preview:Status()
        local status = pool:Status()
        status.error = self.Error
        status.suspended = self.Suspended
        local editor = api.GetEditor()
        if editor and editor:IsActive() then
            status.authoredLights, status.authoredProps = editor.Document.lights, editor.Document.props
        end
        return status
    end

    api.hook.Add("PreDrawOpaqueRenderables", "ZM.PrefabLightPreview", function(depth, skybox)
        Preview:Render(depth, skybox)
    end)
    api.hook.Add("Think", "ZM.PrefabLightPreview", function()
        local editor = api.GetEditor()
        if not editor or not editor:IsActive() then Preview:Clear() end
    end)
    api.hook.Add("PreCleanupMap", "ZM.PrefabLightPreview", function() Preview:Clear() end)
    api.hook.Add("ShutDown", "ZM.PrefabLightPreview", function() Preview:Clear() end)
    return Preview
end
