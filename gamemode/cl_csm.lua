ZM_CSM = ZM_CSM or {}
local CSM = ZM_CSM

local hookName = "ZM.CSM.ProjectedShadows"
local enabledConVar = CreateClientConVar("zombiesim_csm_enabled", "0", true, false,
    "Enables the client-local additive cascaded shadow overlay.")
local qualityConVar = CreateClientConVar("zombiesim_csm_quality", "low", true, false,
    "CSM quality: low, medium, or high.")
local texturePath = "effects/flashlight001"
local textureMaterial = Material(texturePath)
local white = Color(255, 255, 255)
local fallbackDirection = Vector(-0.2588190436, 0, 0.9659258127)

local qualityProfiles = {
    low = { label = "Low (1 cascade / 15 Hz)", updateRate = 15, extents = { 512 }, weights = { 1 } },
    medium = {
        label = "Medium (2 cascades / 30 Hz)",
        updateRate = 30,
        extents = { 512, 1024 },
        weights = { 0.65, 0.35 }
    },
    high = {
        label = "High (3 cascades / every frame)",
        updateRate = 0,
        extents = { 512, 1024, 2048 },
        weights = { 0.55, 0.3, 0.15 }
    }
}

CSM.ConVars = { enabled = enabledConVar, quality = qualityConVar }
CSM.QualityOrder = { "low", "medium", "high" }
CSM.Projectors = CSM.Projectors or {}
CSM.State = "off"
CSM.Reason = nil
CSM.UpdateCount = 0
CSM.LastUpdateAt = nil
CSM.NextUpdateAt = 0
CSM.LastUpdateFrame = nil
CSM.Map = nil
CSM.SunDirection = nil
CSM.SunDirectionSource = nil
CSM.AllocatedQuality = nil
CSM.FailedMap = nil
CSM.FailedQuality = nil
CSM.LastFailure = nil
CSM.LastLoggedFailure = nil

local function isFiniteNumber(value)
    return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(value)
    return isvector(value) and isFiniteNumber(value.x) and isFiniteNumber(value.y) and
        isFiniteNumber(value.z)
end

local function isFiniteAngle(value)
    return isangle(value) and isFiniteNumber(value.p) and isFiniteNumber(value.y) and
        isFiniteNumber(value.r)
end

local function removeProjectors(projectors)
    for _, projector in ipairs(projectors or {}) do
        if IsValid(projector) then projector:Remove() end
    end
end

local function supportedWorld(map)
    local world = ZM_World
    if not world or not isfunction(world.IsLoaded) or not world:IsLoaded() then
        return false, "waiting for world data", "waiting_for_map_metadata"
    end

    if world.ActiveProfile ~= "preview" and world.ActiveProfile ~= "city" then
        return false, "CSM supports generated preview and city cells only", "unsupported"
    end
    if not map:match("^zz_preview_") and not map:match("^zz_city_") then
        return false, "CSM is unavailable on launchers, dens, and non-cell maps", "unsupported"
    end
    return true
end

local function resolveSunDirection(map)
    if util and isfunction(util.GetSunInfo) then
        local ok, info = pcall(util.GetSunInfo)
        if not ok then
            return nil, "util.GetSunInfo failed: " .. tostring(info)
        end
        if istable(info) and info.enabled == true and isFiniteVector(info.direction) and
            info.direction:LengthSqr() > 0 then
            return info.direction:GetNormalized(), "util.GetSunInfo"
        end
    end

    if map:match("^zz_preview_") or map:match("^zz_city_") then
        return Vector(fallbackDirection.x, fallbackDirection.y, fallbackDirection.z),
            "template_border_s.vmf light_environment (angles 0 0 0, pitch -75)"
    end
    return nil, "sun direction is unavailable"
end

function CSM:GetSunDirection(map)
    return resolveSunDirection(map or game.GetMap())
end

local function removeOwnedProjectors()
    removeProjectors(CSM.Projectors)
    CSM.Projectors = {}
    CSM.AllocatedQuality = nil
end

local function setState(state, reason)
    CSM.State = state
    CSM.Reason = reason
end

local function fail(reason)
    removeOwnedProjectors()
    CSM.LastFailure = reason
    CSM.FailedMap = game.GetMap()
    CSM.FailedQuality = CSM:GetQuality()
    setState("failed", reason)
    if CSM.LastLoggedFailure ~= reason then
        ErrorNoHalt("[ZombieSim][CSM] " .. tostring(reason) .. "\n")
        CSM.LastLoggedFailure = reason
    end
    return false
end

local function allocateProjectors(profileName, profile)
    local projectors = {}
    for index, extent in ipairs(profile.extents) do
        local allocated, projector = pcall(ProjectedTexture)
        if not allocated or not IsValid(projector) then
            removeProjectors(projectors)
            return false, "ProjectedTexture allocation failed for cascade " .. index
        end

        local configured, failure = pcall(function()
            projector:SetTexture(texturePath)
            projector:SetEnableShadows(true)
            projector:SetOrthographic(true, -extent, extent, extent, -extent)
            projector:SetNearZ(16)
            projector:SetFarZ(4096)
            projector:SetColor(white)
            projector:SetBrightness(profile.weights[index])
        end)
        if not configured then
            projector:Remove()
            removeProjectors(projectors)
            return false, "cascade " .. index .. " configuration failed: " .. tostring(failure)
        end
        projectors[index] = projector
    end

    removeOwnedProjectors()
    CSM.Projectors = projectors
    CSM.AllocatedQuality = profileName
    CSM.UpdateCount = 0
    CSM.NextUpdateAt = 0
    CSM.LastUpdateFrame = nil
    CSM.LastFailure = nil
    CSM.LastLoggedFailure = nil
    CSM.FailedMap = nil
    CSM.FailedQuality = nil
    return true
end

function CSM:GetQualityProfile(name)
    local profile = qualityProfiles[name]
    if not profile then return nil end
    return {
        label = profile.label,
        updateRate = profile.updateRate,
        extents = table.Copy(profile.extents),
        weights = table.Copy(profile.weights)
    }
end

function CSM:GetQuality()
    local quality = string.lower(qualityConVar:GetString())
    if qualityProfiles[quality] then return quality end
    return "low"
end

function CSM:GetStatus()
    local profile = qualityProfiles[self:GetQuality()]
    return {
        enabled = enabledConVar:GetBool(),
        quality = self:GetQuality(),
        state = self.State,
        reason = self.Reason,
        cascadeCount = #self.Projectors,
        updateRate = profile and profile.updateRate or 0,
        updateCount = self.UpdateCount,
        lastUpdateAt = self.LastUpdateAt,
        sunDirectionSource = self.SunDirectionSource
    }
end

function CSM:Reconcile()
    if not enabledConVar:GetBool() then
        removeOwnedProjectors()
        setState("off")
        return false
    end

    local map = game.GetMap()
    local quality = self:GetQuality()
    if self.State == "failed" and self.FailedMap == map and self.FailedQuality == quality then
        return false
    end
    local supported, reason, state = supportedWorld(map)
    if not supported then
        removeOwnedProjectors()
        setState(state, reason)
        return false
    end

    if self.Map ~= map then
        removeOwnedProjectors()
        self.Map = map
        self.SunDirection, self.SunDirectionSource = self:GetSunDirection(map)
    end
    if not isFiniteVector(self.SunDirection) or self.SunDirection:LengthSqr() == 0 then
        return fail(self.SunDirectionSource or "sun direction is unavailable")
    end
    if textureMaterial:IsError() then
        return fail("projected texture material is unavailable: " .. texturePath)
    end

    local profile = qualityProfiles[quality]
    if not profile then return fail("CSM quality profile is unavailable") end
    if self.AllocatedQuality ~= quality or #self.Projectors ~= #profile.extents then
        local allocated, failure = allocateProjectors(quality, profile)
        if not allocated then return fail(failure) end
    end

    setState("ready")
    return true
end

function CSM:IsSecondaryView()
    if ZM_LauncherMenu and ZM_LauncherMenu.Active then return true end
    if ZM_SkyInspection and ZM_SkyInspection.IsActive and ZM_SkyInspection:IsActive() then return true end
    if ZM_WorldCapture and ZM_WorldCapture.Rendering then return true end
    if ZM_WorldMap and ZM_WorldMap.Capturing then return true end
    return false
end

function CSM:Suspend(reason)
    removeOwnedProjectors()
    setState("suspended", reason)
end

local function getViewSetup()
    if not render or not isfunction(render.GetViewSetup) then
        return nil, "render.GetViewSetup is unavailable"
    end
    local ok, view = pcall(render.GetViewSetup, true)
    if not ok then return nil, "render.GetViewSetup failed: " .. tostring(view) end
    if not istable(view) or not isFiniteVector(view.origin) or not isFiniteAngle(view.angles) then
        return nil, "the current render view has invalid origin or angles"
    end
    return view
end

local function updateProjectors(view, now)
    local frame = FrameNumber()
    if CSM.LastUpdateFrame == frame then return end
    local profile = qualityProfiles[CSM.AllocatedQuality]
    if not profile then
        fail("active CSM projectors have no matching quality profile")
        return
    end
    if profile.updateRate > 0 and now < CSM.NextUpdateAt then return end

    local position = view.origin + CSM.SunDirection * 1024
    local angles = Vector(-CSM.SunDirection.x, -CSM.SunDirection.y, -CSM.SunDirection.z):Angle()
    if not isFiniteVector(position) or not isFiniteAngle(angles) then
        fail("calculated projector transform is not finite")
        return
    end

    local updated, failure = pcall(function()
        for _, projector in ipairs(CSM.Projectors) do
            if not IsValid(projector) then error("owned ProjectedTexture became invalid") end
            projector:SetPos(position)
            projector:SetAngles(angles)
            projector:Update()
        end
    end)
    if not updated then
        fail("ProjectedTexture update failed: " .. tostring(failure))
        return
    end

    CSM.LastUpdateFrame = frame
    CSM.NextUpdateAt = profile.updateRate > 0 and now + 1 / profile.updateRate or 0
    CSM.LastUpdateAt = now
    CSM.UpdateCount = CSM.UpdateCount + 1
end

removeProjectors(CSM.Projectors)
CSM.Projectors = {}
hook.Remove("PreDrawOpaqueRenderables", hookName)
hook.Remove("PreCleanupMap", hookName)
hook.Remove("ShutDown", hookName)
cvars.RemoveChangeCallback("zombiesim_csm_enabled", "ZM.CSM.Enabled")
cvars.RemoveChangeCallback("zombiesim_csm_quality", "ZM.CSM.Quality")

hook.Add("PreDrawOpaqueRenderables", hookName, function(depth, skybox)
    if depth or skybox then return end
    if not enabledConVar:GetBool() then
        if CSM.State ~= "off" or #CSM.Projectors > 0 then CSM:Reconcile() end
        return
    end

    if CSM:IsSecondaryView() then
        if CSM.State ~= "suspended" or #CSM.Projectors > 0 then
            CSM:Suspend("secondary render view")
        end
        return
    end

    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive() then
        if CSM.State ~= "suspended" or #CSM.Projectors > 0 then CSM:Suspend("no living local player") end
        return
    end

    if not CSM:Reconcile() then return end
    local view, failure = getViewSetup()
    if not view then
        fail(failure)
        return
    end
    updateProjectors(view, SysTime())
end)

hook.Add("PreCleanupMap", hookName, function()
    removeOwnedProjectors()
    CSM.Map = nil
    CSM.SunDirection = nil
    CSM.SunDirectionSource = nil
    setState(enabledConVar:GetBool() and "waiting_for_map_metadata" or "off")
end)

hook.Add("ShutDown", hookName, function()
    removeOwnedProjectors()
end)

cvars.AddChangeCallback("zombiesim_csm_enabled", function()
    CSM.FailedMap = nil
    CSM.FailedQuality = nil
    CSM:Reconcile()
end, "ZM.CSM.Enabled")

cvars.AddChangeCallback("zombiesim_csm_quality", function(_, _, value)
    value = string.lower(value or "")
    if not qualityProfiles[value] then
        ErrorNoHalt("[ZombieSim][CSM] Invalid quality '" .. tostring(value) .. "'; resetting to low.\n")
        qualityConVar:SetString("low")
        return
    end
    CSM.FailedMap = nil
    CSM.FailedQuality = nil
    CSM:Reconcile()
end, "ZM.CSM.Quality")

timer.Simple(0, function()
    CSM:Reconcile()
end)
