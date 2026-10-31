local pool = include("prefabs/cl_spotlight_pool.lua")({
    IsValid = IsValid, IsVector = isvector, IsAngle = isangle,
    Vector = Vector, Angle = Angle, Color = Color, Material = Material, ProjectedTexture = ProjectedTexture
})
ZM_PrefabWorldLights = include("prefabs/cl_light_runtime.lua")({
    GetEditor = function() return ZM_PrefabEditorClient end,
    FindEntities = function() return ents.FindByClass("zn_prefab_spotlight") end,
    CurTime = CurTime, EyePos = EyePos, IsValid = IsValid, ErrorNoHalt = ErrorNoHalt, hook = hook
}, pool)

concommand.Add("zombiesim_prefab_lights_status_client", function(_, _, arguments)
    local requestId = arguments[1]
    if type(requestId) ~= "string" or not string.match(requestId, "^%d+$") then
        ErrorNoHalt("[ZombieSim] Prefab light status requires a request ID.\n")
        return
    end
    local status = ZM_PrefabWorldLights:Status()
    print(string.format("[ZombieSim] Prefab lights: %d networked, %d pending, %d active, %d shadowed; %s.",
        status.networked, status.pending, status.active, status.shadowed, status.error or "no errors"))
    local result = { requestId = requestId, world = status,
        editor = ZM_PrefabLightPreview and ZM_PrefabLightPreview:Status() or nil }
    local encoded = util.TableToJSON(result, true)
    file.CreateDir("zombiesim")
    if type(encoded) ~= "string" or not file.Write("zombiesim/prefab-lights-status.json", encoded) then
        ErrorNoHalt("[ZombieSim] Could not write prefab light status.\n")
    end
end)
