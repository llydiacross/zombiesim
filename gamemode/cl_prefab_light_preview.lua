local pool = include("prefabs/cl_spotlight_pool.lua")({
    IsValid = IsValid, IsVector = isvector, IsAngle = isangle,
    Vector = Vector, Angle = Angle, Color = Color, Material = Material, ProjectedTexture = ProjectedTexture
})
ZM_PrefabLightPreview = include("prefabs/cl_light_preview.lua")({
    GetEditor = function() return ZM_PrefabEditorClient end,
    Vector = Vector, CurTime = CurTime, hook = hook
}, pool)

concommand.Add("zombiesim_prefab_light_preview_control_client", function(_, _, arguments)
    if not ZM_PrefabEditorClient:IsActive() then
        ErrorNoHalt("[ZombieSim] Prefab light preview control requires the editor.\n")
        return
    end
    if arguments[1] == "pause" then
        ZM_PrefabLightPreview:SetSuspended(true)
    elseif arguments[1] == "resume" then
        ZM_PrefabLightPreview:SetSuspended(false)
    else
        ErrorNoHalt("[ZombieSim] Prefab light preview control requires pause or resume.\n")
    end
end)
