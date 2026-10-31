ZM_PrefabGuardPreview = include("prefabs/cl_guard_preview.lua")({
    IsValid = IsValid, IsVector = isvector, Vector = Vector, Angle = Angle,
    ClientsideModel = ClientsideModel, RENDERGROUP_OTHER = RENDERGROUP_OTHER, EF_BONEMERGE = EF_BONEMERGE,
    timer = timer,
    Report = function(problem)
        if ZM_PrefabEditorClient and ZM_PrefabEditorClient:IsActive() then
            ZM_PrefabEditorClient:Message(problem, true)
        elseif ZM_PrefabExplorer and IsValid(ZM_PrefabExplorer.Frame) then
            ZM_PrefabExplorer:Message(problem)
        else
            ErrorNoHalt("[ZombieSim] Prefab guard preview: " .. tostring(problem) .. "\n")
        end
    end
})

hook.Add("PreCleanupMap", "ZM.PrefabGuardPreview", function() ZM_PrefabGuardPreview:Clear() end)
hook.Add("ShutDown", "ZM.PrefabGuardPreview", function() ZM_PrefabGuardPreview:Clear() end)
hook.Add("Think", "ZM.PrefabGuardPreview", function() ZM_PrefabGuardPreview:AdvanceAll() end)
