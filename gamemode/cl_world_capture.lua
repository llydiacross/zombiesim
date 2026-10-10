// Persistent queue ownership is server-side; this client only renders authenticated requests.
ZM_WorldCapture = ZM_WorldCapture or {}
local Capture = ZM_WorldCapture
local Contract = include("world_capture/sh_contract.lua")
local pending
local target
local coastMatrix = Matrix()
hook.Remove("PreDrawSkyBox", "ZM.WorldCapture.HideSkyRoom")

function Capture:GetInstalledRevision()
    if not ZM_World or not ZM_World:IsLoaded() then return nil end
    return Contract.InstalledRevision(ZM_World:GetData().world, ZM_World.ActiveProfile, file, util)
end

local function identity(request)
    local revision, failure = Contract.InstalledRevision(ZM_World:GetData().world, ZM_World.ActiveProfile, file, util)
    if not revision or not Contract.Matches(request.revision, revision) then
        return false, failure or "client world revision differs from capture run"
    end
    if not ZM_Skybox or ZM_Skybox:GetPlayableCeiling() ~= revision.cameraZ then
        return false, "skyline owner camera ceiling differs from capture revision"
    end
    local cell = ZM_World:GetCellById(request.cell.id)
    local localPlayer = LocalPlayer()
    if not cell or cell.map ~= request.cell.map or cell.x ~= request.cell.x or cell.y ~= request.cell.y
        or string.lower(game.GetMap()) ~= string.lower(cell.map) then
        return false, "loaded map/cell differs from capture request"
    end
    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
    if localPlayer:GetNWInt("CellX") ~= worldX or localPlayer:GetNWInt("CellY") ~= worldY
        or localPlayer:GetNWString("CurrentSafeZoneId", "") ~= "" then
        return false, "survivor has not arrived in requested ordinary cell"
    end
    return true
end

local function reply(request, result)
    result.runId, result.token, result.cellId = request.runId, request.token, request.cell.id
    result.variant = request.variant
    net.Start("ZM.WorldCapture.Result")
    net.WriteString(util.TableToJSON(result))
    net.SendToServer()
end

function Capture:Render(request)
    local ready, reason = identity(request)
    if not ready then return {ok = false, error = reason} end
    if not ZM_WorldMap or ZM_WorldMap.Capturing or not ZM_Atmosphere then
        return {ok = false, error = "capture owners unavailable/busy"}
    end
    local size = request.revision.size
    self.LastScene = nil
    target = target or GetRenderTargetEx("zombiesim_world_capture_v3", size, size,
        RT_SIZE_LITERAL or 8, MATERIAL_RT_DEPTH_SEPARATE or 1, bit.bor(4, 8), 0, IMAGE_FORMAT_RGBA8888 or 0)
    if not target then return {ok = false, error = "render target unavailable"} end
    local hidden = {}
    local function hide(entity)
        if not IsValid(entity) or hidden[entity] then return end
        hidden[entity] = {draw = entity:GetNoDraw(), shadow = entity:IsEffectActive(EF_NOSHADOW)}
        entity:SetNoDraw(true)
        entity:AddEffects(EF_NOSHADOW)
    end
    local priorCapture = ZM_WorldMap.Capturing
    local priorRendering = self.Rendering
    local priorParticles = ZM_Atmosphere.MapCaptureParticlesHidden == true
    local fogToken = ZM_Atmosphere:BeginWorldCaptureFog(request.variant)
    local pushed = false
    local pixels2D = false
    local data
    local ok, failure = xpcall(function()
        for _, entity in ipairs(ents.GetAll()) do
            local class = entity:GetClass()
            if entity:IsPlayer() or entity:IsWeapon() or entity:IsNPC()
                or class == "class C_ClientRagdoll" or class == "prop_ragdoll"
                or class:match("^npc_") or class:match("^zm_") or class:match("^zombiesim_")
                or class == "zn_walker_zombie" or class == "zn_boss_zombie" or class == "zn_dropped_item"
                or class:match("^env_sprite") or class == "gmod_hands" then hide(entity) end
        end
        for _, limb in ipairs(ZM_GoreClient and ZM_GoreClient.Limbs or {}) do hide(limb.entity) end
        if ZM_WeaponEffects and ZM_WeaponEffects.GetWorldCaptureEntities then
            for _, entity in ipairs(ZM_WeaponEffects:GetWorldCaptureEntities()) do hide(entity) end
        end
        ZM_WorldMap.Capturing = true
        self.Rendering = true
        ZM_Atmosphere:SetMapCaptureHidden(true)
        render.PushRenderTarget(target)
        pushed = true
        render.Clear(0, 0, 0, 255, true, true)
        local view = Contract.View(request.revision)
        view.origin, view.angles = Vector(0, 0, request.revision.cameraZ), Angle(90, 90, 0)
        if ZM_Skybox and ZM_Skybox.RenderClientView then
            local rendered, reason = ZM_Skybox:RenderClientView(view)
            if not rendered then error(reason or "secondary view renderer failed") end
        else render.RenderView(view) end
        cam.Start2D()
        pixels2D = true
        render.CapturePixels()
        local minima, maxima = {255, 255, 255}, {0, 0, 0}
        for y = 0, 11 do for x = 0, 11 do
            local values = {render.ReadPixel(math.floor((x + 0.5) * size / 12), math.floor((y + 0.5) * size / 12))}
            for channel = 1, 3 do
                local value = values[channel]
                if type(value) ~= "number" or value ~= value then error("unreadable render buffer") end
                minima[channel], maxima[channel] = math.min(minima[channel], value), math.max(maxima[channel], value)
            end
        end end
        cam.End2D()
        pixels2D = false
        if math.max(maxima[1] - minima[1], maxima[2] - minima[2], maxima[3] - minima[3]) < 2 then
            error("orthographic capture produced a blank/constant buffer; capability gate failed")
        end
        data = render.Capture({format = "png", x = 0, y = 0, w = size, h = size, alpha = false})
    end, debug.traceback)
    if pixels2D then cam.End2D() end
    if pushed then render.PopRenderTarget() end
    ZM_Atmosphere:EndWorldCaptureFog(fogToken)
    ZM_Atmosphere:SetMapCaptureHidden(priorParticles)
    ZM_WorldMap.Capturing = priorCapture
    self.Rendering = priorRendering
    for entity, state in pairs(hidden) do
        if IsValid(entity) then
            entity:SetNoDraw(state.draw)
            if not state.shadow then entity:RemoveEffects(EF_NOSHADOW) end
        end
    end
    if not ok then return {ok = false, error = tostring(failure), scene = self.LastScene} end
    if not Contract.ValidPNG(data, size) then return {ok = false, error = "capture returned invalid/missing PNG"} end
    local path = Contract.OutputPath(request.runId, request.cell.id, request.variant)
    file.CreateDir("zombiesim/world_captures/" .. request.runId .. "/" .. request.variant)
    file.Write(path, data)
    if file.Read(path, "DATA") ~= data then return {ok = false, error = "PNG write/readback failed"} end
    return {
        ok = true, path = path, bytes = #data, sha256 = util.SHA256(data),
        revision = request.revision, map = game.GetMap(), width = size, height = size,
        ready = true, atmosphereState = ZM_Atmosphere:GetMapCaptureState(), capturedAt = os.time(),
        scene = self.LastScene
    }
end

net.Receive("ZM.WorldCapture.Request", function()
    local request = util.JSONToTable(net.ReadString())
    if type(request) ~= "table" or type(request.cell) ~= "table"
        or not Contract.OutputPath(request.runId, request.cell.id, request.variant)
        or type(request.revision) ~= "table" or request.revision.size ~= Contract.Size then return end
    pending = {request = request, receivedAt = RealTime(), settledFrames = 0}
end)

net.Receive("ZM.WorldCapture.Cancel", function() pending = nil end)

hook.Add("PostRender", "ZM.WorldCapture.Render", function()
    if not pending or not IsValid(LocalPlayer()) or not ZM_World:IsLoaded() then return end
    if gui.IsGameUIVisible() or (ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud()) then return end
    local ready = identity(pending.request)
    if ready and ZM_Atmosphere and ZM_Atmosphere.WeatherSynced
        and not ZM_Atmosphere.PendingProfileIndex
        and ZM_Atmosphere.ActiveProfileIndex == ZM_World:GetCellById(pending.request.cell.id).atmosphereProfile
        and RealTime() - pending.receivedAt >= 3 then
        pending.settledFrames = pending.settledFrames + 1
        if pending.settledFrames < 3 then return end
        local request = pending.request
        pending = nil
        reply(request, Capture:Render(request))
    else
        pending.settledFrames = 0
        if RealTime() - pending.receivedAt > 45 then
            local request = pending.request
            pending = nil
            reply(request, {ok = false, error = "client readiness timeout"})
        end
    end
end)

hook.Add("PreDrawOpaqueRenderables", "ZM.WorldCapture.SceneDiagnostic", function(depth, skybox)
    if not Capture.Rendering or skybox or depth then return end
    local view = render.GetViewSetup(true)
    Capture.LastScene = {
        origin = {view.origin.x, view.origin.y, view.origin.z},
        angles = {view.angles.p, view.angles.y, view.angles.r},
        ortho = view.ortho, width = view.w, height = view.h,
        znear = view.znear, zfar = view.zfar,
        ortholeft = view.ortholeft, orthoright = view.orthoright,
        orthotop = view.orthotop, orthobottom = view.orthobottom
    }
end)

hook.Add("PostDrawOpaqueRenderables", "ZM.WorldCapture.Coast", function(depth, _, skybox)
    if depth or skybox or not Capture.Rendering or not ZM_Skybox.CoastMeshes then return end
    local manifest = ZM_Skybox:GetManifest()
    if not manifest then return end
    // Native ortho sky bounds are not scaled; draw the same approved coast buffers
    // depth-tested in world coordinates, without replacing or suppressing either sky pass.
    local scale, camera = manifest.scale, manifest.cameraVector
    coastMatrix:SetScale(Vector(scale, scale, scale))
    coastMatrix:SetTranslation(Vector(-camera.x * scale, -camera.y * scale, -camera.z * scale))
    local settings = ZM_Atmosphere:GetFogSettings()
    ZM_Skybox:DrawCoast(settings and settings.color, coastMatrix)
end)
