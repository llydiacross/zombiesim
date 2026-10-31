ZM_PrefabParticleCatalog = include("prefabs/sh_particle_catalog.lua")(file, util, include("prefabs/sh_contract.lua"))
ZM_PrefabParticleEffects = include("prefabs/cl_particle_effect.lua")({
    IsValid = IsValid, file = file, game = game, ClientsideModel = ClientsideModel, RENDERGROUP_OTHER = RENDERGROUP_OTHER,
    PrecacheParticleSystem = PrecacheParticleSystem, CreateParticleSystemNoEntity = CreateParticleSystemNoEntity,
    CreateSound = CreateSound, RealTime = RealTime
})
ZM_PrefabParticleProbe = include("prefabs/cl_particle_probe.lua")({
    Editor = ZM_PrefabEditorClient, Catalog = ZM_PrefabParticleCatalog,
    Vector = Vector, Angle = Angle, ErrorNoHalt = ErrorNoHalt, hook = hook
}, ZM_PrefabParticleEffects)
ZM_PrefabParticlePreview = include("prefabs/cl_particle_preview.lua")({
    GetEditor = function() return ZM_PrefabEditorClient end,
    Vector = Vector, Angle = Angle, RealTime = RealTime, ErrorNoHalt = ErrorNoHalt, hook = hook
}, ZM_PrefabParticleCatalog, ZM_PrefabParticleEffects)

concommand.Add("zombiesim_dev_prefab_particle_client", function(_, _, arguments)
    local action = arguments[1] or ""
    if action == "on" then
        local ok, problem = ZM_PrefabParticleProbe:Start(arguments[2] or "burst")
        if not ok then ErrorNoHalt("[ZombieSim] Prefab particle preview: " .. tostring(problem) .. "\n") end
    elseif action == "off" then
        ZM_PrefabParticleProbe:Stop()
    elseif action == "status" then
        local requestId = arguments[2]
        if type(requestId) ~= "string" or not string.match(requestId, "^%d+$") then
            ErrorNoHalt("[ZombieSim] Prefab particle status requires a request ID.\n")
            return
        end
        local status = ZM_PrefabParticleProbe:Status()
        status.requestId = requestId
        local encoded = util.TableToJSON(status, true)
        file.CreateDir("zombiesim")
        if type(encoded) ~= "string" or not file.Write("zombiesim/prefab-particle-probe.json", encoded) then
            ErrorNoHalt("[ZombieSim] Could not write the prefab particle preview status.\n")
        end
    else
        ErrorNoHalt("[ZombieSim] Prefab particle preview requires on, off or status.\n")
    end
end)
