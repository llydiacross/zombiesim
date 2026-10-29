local Probe = include("prefabs/cl_spotlight_probe.lua")({
    Editor = ZM_PrefabEditorClient, IsValid = IsValid, Material = Material,
    ProjectedTexture = ProjectedTexture, ClientsideModel = ClientsideModel,
    RENDERGROUP_OPAQUE = RENDERGROUP_OPAQUE, RENDERGROUP_OTHER = RENDERGROUP_OTHER,
    Vector = Vector, Angle = Angle, Color = Color, hook = hook
})

concommand.Add("zombiesim_dev_prefab_spotlight_client", function(_, _, arguments)
    local action = arguments[1] or ""
    if action == "on" then
        local ok, problem = Probe:Start(arguments[2])
        if not ok then ErrorNoHalt("[ZombieSim] Prefab spotlight preview: " .. tostring(problem) .. "\n") end
    elseif action == "off" then
        Probe:Stop()
    elseif action == "status" then
        local requestId = arguments[2]
        if type(requestId) ~= "string" or not string.match(requestId, "^%d+$") then
            ErrorNoHalt("[ZombieSim] Prefab spotlight status requires a request ID.\n")
            return
        end
        local status = Probe:Status()
        status.requestId = requestId
        local encoded = util.TableToJSON(status, true)
        file.CreateDir("zombiesim")
        if type(encoded) ~= "string" or not file.Write("zombiesim/prefab-spotlight-probe.json", encoded) then
            ErrorNoHalt("[ZombieSim] Could not write the prefab spotlight preview status.\n")
        end
    else
        ErrorNoHalt("[ZombieSim] Prefab spotlight preview requires on, off or status.\n")
    end
end)
