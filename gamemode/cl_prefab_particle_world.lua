ZM_PrefabParticleWorld = include("prefabs/cl_particle_world.lua")({
    GetEditor = function() return ZM_PrefabEditorClient end,
    FindEntities = function() return ents.FindByClass("zn_prefab_particle") end,
    IsValid = IsValid, IsVector = isvector, IsAngle = isangle,
    RealTime = RealTime, ErrorNoHalt = ErrorNoHalt, hook = hook
}, ZM_PrefabParticleCatalog, ZM_PrefabParticleEffects)

net.Receive("ZM.PrefabParticle.Trigger", function()
    local id = net.ReadString()
    local effect = net.ReadString()
    local x = net.ReadDouble()
    local y = net.ReadDouble()
    local z = net.ReadDouble()
    local pitch = net.ReadDouble()
    local yaw = net.ReadDouble()
    local roll = net.ReadDouble()
    local position = Vector(x, y, z)
    local angles = Angle(pitch, yaw, roll)
    local overlap = net.ReadBool()
    local ok, problem = ZM_PrefabParticleWorld:Trigger(id, effect, position, angles, overlap)
    if not ok then ErrorNoHalt("[ZombieSim] Prefab particle trigger: " .. tostring(problem) .. "\n") end
end)

net.Receive("ZM.PrefabParticle.Stop", function()
    ZM_PrefabParticleWorld:StopBursts(net.ReadString())
end)

concommand.Add("zombiesim_prefab_particle_world_fixture_client", function(_, _, arguments)
    local player = LocalPlayer()
    if game.GetMap() ~= "gm_flatgrass" or not IsValid(player) or not player:IsAdmin()
        or not ZM_PrefabEditorClient:IsSession() then
        ErrorNoHalt("[ZombieSim] Prefab particle fixture requires its isolated editor owner.\n")
        return
    end
    if arguments[1] == "on" then
        ZM_PrefabParticleWorld:SetFixtureActive(true)
    elseif arguments[1] == "off" then
        ZM_PrefabParticleWorld:SetFixtureActive(false)
    else
        ErrorNoHalt("[ZombieSim] Prefab particle fixture requires on or off.\n")
    end
end)

concommand.Add("zombiesim_prefab_particles_status_client", function(_, _, arguments)
    local requestId = arguments[1]
    if type(requestId) ~= "string" or not string.match(requestId, "^%d+$") then
        ErrorNoHalt("[ZombieSim] Prefab particle status requires a request ID.\n")
        return
    end
    local result = { requestId = requestId, world = ZM_PrefabParticleWorld:Status(),
        editor = ZM_PrefabParticlePreview:Status() }
    local encoded = util.TableToJSON(result, true)
    file.CreateDir("zombiesim")
    if type(encoded) ~= "string" or not file.Write("zombiesim/prefab-particles-status.json", encoded) then
        ErrorNoHalt("[ZombieSim] Could not write prefab particle status.\n")
    end
end)
