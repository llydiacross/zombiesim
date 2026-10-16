ZM_CSM = ZM_CSM or {}
local CSM = ZM_CSM
local previousShadowFilterRestore = CSM.RestoreShadowCasterFilter
if isfunction(previousShadowFilterRestore) then
    previousShadowFilterRestore(CSM)
end

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

local shadowTriangleThreshold = 5000
local skyboxModelPrefix = "models/zombiesim/skybox/"
local shadowFilterScanInterval = 10
local modelMeasurementBudget = 0.0005
local modelCacheFile = "zombiesim/csm_model_cache.json"
local modelCacheVersion = 1
local vegetationTokens = {
    foliage = true,
    fern = true,
    ferns = true,
    flower = true,
    flowers = true,
    grass = true,
    grasses = true,
    ivy = true,
    leaf = true,
    leaves = true,
    plant = true,
    plants = true,
    reed = true,
    reeds = true,
    vegetation = true,
    vine = true,
    vines = true
}
local treeTokens = { tree = true, trees = true }
local bushTokens = {
    bush = true,
    bushes = true,
    hedge = true,
    hedges = true,
    shrub = true,
    shrubs = true
}
local modelMeasurementQueue = {}
local modelMeasurementQueueHead = 1
local queuedModels = {}
local pendingShadowEntities = {}
local nextShadowFilterScanAt = 0
local shadowFilterRescanPending = false
local shadowFilterScanCount = 0
local shadowFilterTotalSeconds = 0
local shadowFilterMaximumSeconds = 0
local modelMeasurementCount = 0
local modelMeasurementTotalSeconds = 0
local modelMeasurementMaximumSeconds = 0

CSM.ConVars = { enabled = enabledConVar, quality = qualityConVar }
CSM.QualityOrder = { "low", "medium", "high" }
CSM.Projectors = CSM.Projectors or {}
CSM.ShadowCasterOverrides = {}
CSM.ShadowModelInfo = CSM.ShadowModelInfo or {}
CSM.ShadowModelFailures = CSM.ShadowModelFailures or {}
CSM.UnsupportedBrushModels = CSM.UnsupportedBrushModels or {}
CSM.ShadowTriangleThreshold = shadowTriangleThreshold
CSM.ModelCacheVersion = modelCacheVersion
CSM.ModelCacheDirty = CSM.ModelCacheDirty == true
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

local modelCacheLoaded = false
local modelCacheJson = file.Read(modelCacheFile, "DATA")
if modelCacheJson then
    local modelCache = util.JSONToTable(modelCacheJson)
    if not istable(modelCache) or modelCache.version ~= modelCacheVersion or
        not istable(modelCache.models) then
        ErrorNoHalt("[ZombieSim][CSM] Ignoring invalid or stale model-count cache.\n")
    else
        modelCacheLoaded = true
        for model, info in pairs(modelCache.models) do
            if isstring(model) and istable(info) and isnumber(info.triangleCount) and
                info.triangleCount >= 0 and isbool(info.isFoliage) and isbool(info.isTree) and
                isbool(info.isBushOrHedge) then
                CSM.ShadowModelInfo[model] = {
                    triangleCount = info.triangleCount,
                    isFoliage = info.isFoliage,
                    isTree = info.isTree,
                    isBushOrHedge = info.isBushOrHedge
                }
            else
                ErrorNoHalt("[ZombieSim][CSM] Ignoring invalid model-count cache entry.\n")
            end
        end
    end
    if not modelCacheLoaded and next(CSM.ShadowModelInfo) then
        CSM.ModelCacheDirty = true
    end
end

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

local function containsToken(value, tokens)
    if not isstring(value) then return false end

    for token in string.lower(value):gmatch("[a-z0-9]+") do
        if tokens[token] then return true end
    end
    return false
end

local function containsTreeToken(value)
    if not isstring(value) then return false end

    for token in string.lower(value):gmatch("[a-z0-9]+") do
        if treeTokens[token] or token:match("^trees?%d+$") then return true end
    end
    return false
end

local function containsBushToken(value)
    if not isstring(value) then return false end

    for token in string.lower(value):gmatch("[a-z0-9]+") do
        if bushTokens[token] or token:find("bush", 1, true) or token:find("hedge", 1, true) or
            token:find("shrub", 1, true) then
            return true
        end
    end
    return false
end

local function containsVegetationToken(value)
    return containsToken(value, vegetationTokens) or containsTreeToken(value) or
        containsBushToken(value) or (isstring(value) and
            string.lower(value):match("[%w]+grass") ~= nil)
end

local function isSkyboxModel(modelPath)
    return isstring(modelPath) and
        string.lower(modelPath):sub(1, #skyboxModelPrefix) == skyboxModelPrefix
end

for model in pairs(CSM.ShadowModelInfo) do
    if isSkyboxModel(model) then
        CSM.ShadowModelInfo[model] = nil
        CSM.ModelCacheDirty = true
    end
end
for model in pairs(CSM.ShadowModelFailures) do
    if isSkyboxModel(model) then CSM.ShadowModelFailures[model] = nil end
end

function CSM.ShouldExcludeModel(modelPath, triangleCount, modelInfo)
    modelInfo = istable(modelInfo) and modelInfo or {}
    if isSkyboxModel(modelPath) then return true end
    if modelInfo.isTree == true or containsTreeToken(modelPath) then return false end
    if modelInfo.isBushOrHedge == true or containsBushToken(modelPath) then return true end

    local isFoliage = modelInfo.isFoliage == true or containsVegetationToken(modelPath)
    return not isFoliage and isnumber(triangleCount) and triangleCount >= shadowTriangleThreshold
end

function CSM.GetDesiredShadowState(modelPath, triangleCount, modelInfo)
    modelInfo = istable(modelInfo) and modelInfo or {}
    if isSkyboxModel(modelPath) then return false end
    if modelInfo.isTree == true or containsTreeToken(modelPath) then return true end
    if CSM.ShouldExcludeModel(modelPath, triangleCount, modelInfo) then return false end
    return nil
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

function CSM:RestoreShadowCaster(entity)
    local state = self.ShadowCasterOverrides[entity]
    if not state then return end
    if IsValid(entity) then entity:DrawShadow(state.originallyCasts) end
    self.ShadowCasterOverrides[entity] = nil
end

function CSM:RestoreShadowCasterFilter()
    local entities = {}
    for entity in pairs(self.ShadowCasterOverrides or {}) do
        entities[#entities + 1] = entity
    end

    for _, entity in ipairs(entities) do
        self:RestoreShadowCaster(entity)
    end
    pendingShadowEntities = {}
    shadowFilterRescanPending = false
    nextShadowFilterScanAt = 0
end

function CSM:SetShadowCasterState(entity, shouldCast, model)
    if not IsValid(entity) or not isfunction(entity.GetEffects) or
        not isfunction(entity.DrawShadow) then
        return false
    end

    local state = self.ShadowCasterOverrides[entity]
    if not state then
        local originallyCasts = bit.band(entity:GetEffects(), EF_NOSHADOW) == 0
        if originallyCasts == shouldCast then return false end
        state = {
            originallyCasts = originallyCasts,
            shouldCast = shouldCast,
            model = model
        }
        self.ShadowCasterOverrides[entity] = state
    else
        state.shouldCast = shouldCast
        state.model = model
    end

    local currentlyCasts = bit.band(entity:GetEffects(), EF_NOSHADOW) == 0
    if currentlyCasts ~= shouldCast then entity:DrawShadow(shouldCast) end
    return true
end

local function measureModelInfo(model)
    if not util or not isfunction(util.GetModelMeshes) then
        return nil, "util.GetModelMeshes is unavailable"
    end
    if not isfunction(util.IsValidModel) or not util.IsValidModel(model) then
        return nil, "model is not mounted or valid"
    end

    local startedAt = SysTime()
    local ok, meshes = pcall(util.GetModelMeshes, model, 0)
    local elapsed = SysTime() - startedAt
    modelMeasurementCount = modelMeasurementCount + 1
    modelMeasurementTotalSeconds = modelMeasurementTotalSeconds + elapsed
    modelMeasurementMaximumSeconds = math.max(modelMeasurementMaximumSeconds, elapsed)
    if not ok then return nil, "util.GetModelMeshes failed: " .. tostring(meshes) end
    if not istable(meshes) then return nil, "util.GetModelMeshes returned no mesh table" end

    local vertexCount = 0
    local info = {
        isFoliage = containsVegetationToken(model),
        isTree = containsTreeToken(model),
        isBushOrHedge = containsBushToken(model)
    }
    for _, meshData in ipairs(meshes) do
        if not istable(meshData) or not istable(meshData.triangles) then
            return nil, "model mesh has no triangle vertex table"
        end
        vertexCount = vertexCount + #meshData.triangles
        info.isFoliage = info.isFoliage or containsVegetationToken(meshData.material)
        info.isTree = info.isTree or containsTreeToken(meshData.material)
        info.isBushOrHedge = info.isBushOrHedge or containsBushToken(meshData.material)
    end
    if vertexCount % 3 ~= 0 then
        return nil, "model triangle vertex count is not divisible by three"
    end

    return {
        triangleCount = vertexCount / 3,
        isFoliage = info.isFoliage,
        isTree = info.isTree,
        isBushOrHedge = info.isBushOrHedge
    }
end

local function saveModelInfoCache()
    if not CSM.ModelCacheDirty then return true end

    local encoded = util.TableToJSON({
        version = modelCacheVersion,
        models = CSM.ShadowModelInfo
    })
    if not encoded then
        ErrorNoHalt("[ZombieSim][CSM] Could not serialize model-count cache.\n")
        return false
    end

    file.CreateDir("zombiesim")
    file.Write(modelCacheFile, encoded)
    CSM.ModelCacheDirty = false
    return true
end

local function queueModelMeasurement(model)
    if CSM.ShadowModelInfo[model] or CSM.ShadowModelFailures[model] or queuedModels[model] then
        return
    end
    queuedModels[model] = true
    modelMeasurementQueue[#modelMeasurementQueue + 1] = model
end

local function processModelMeasurements()
    local startedAt = SysTime()
    local changed = false
    repeat
        local model = modelMeasurementQueue[modelMeasurementQueueHead]
        if not model then break end
        modelMeasurementQueueHead = modelMeasurementQueueHead + 1
        queuedModels[model] = nil

        if not CSM.ShadowModelInfo[model] and not CSM.ShadowModelFailures[model] then
            local info, failure = measureModelInfo(model)
            if info then
                CSM.ShadowModelInfo[model] = info
                CSM.ModelCacheDirty = true
                changed = true
            else
                CSM.ShadowModelFailures[model] = failure
                ErrorNoHalt("[ZombieSim][CSM] Could not classify model " .. model .. ": " ..
                    tostring(failure) .. "; polygon-based shadow exclusion is unavailable for it.\n")
            end
        end
    until modelMeasurementQueueHead > #modelMeasurementQueue or
        SysTime() - startedAt >= modelMeasurementBudget

    if modelMeasurementQueueHead > #modelMeasurementQueue then
        modelMeasurementQueue = {}
        modelMeasurementQueueHead = 1
        saveModelInfoCache()
    end
    return changed
end

local function updateShadowCasterEntity(entity)
    if not IsValid(entity) or not isfunction(entity.GetModel) or
        not isfunction(entity.GetEffects) or not isfunction(entity.DrawShadow) then
        CSM:RestoreShadowCaster(entity)
        return
    end

    local model = entity:GetModel()
    if not isstring(model) or model == "" then
        CSM:RestoreShadowCaster(entity)
        return
    end
    if model:sub(1, 1) == "*" then
        CSM.UnsupportedBrushModels[model] = true
        CSM:RestoreShadowCaster(entity)
        return
    end
    if isSkyboxModel(model) then
        CSM:SetShadowCasterState(entity, false, model)
        return
    end

    local info = CSM.ShadowModelInfo[model]
    if not info and containsVegetationToken(model) then
        info = {
            triangleCount = 0,
            isFoliage = true,
            isTree = containsTreeToken(model),
            isBushOrHedge = containsBushToken(model)
        }
        CSM.ShadowModelInfo[model] = info
        CSM.ModelCacheDirty = true
    elseif not info and not CSM.ShadowModelFailures[model] then
        local state = CSM.ShadowCasterOverrides[entity]
        local currentlyCasts = bit.band(entity:GetEffects(), EF_NOSHADOW) == 0
        if currentlyCasts or state then queueModelMeasurement(model) end
    end

    if not info then
        CSM:RestoreShadowCaster(entity)
        return
    end

    local desiredShadowState = CSM.GetDesiredShadowState(model, info.triangleCount, info)
    if desiredShadowState ~= nil then
        CSM:SetShadowCasterState(entity, desiredShadowState, model)
    else
        CSM:RestoreShadowCaster(entity)
    end
end

local function scanShadowCasters()
    local startedAt = SysTime()
    local seen = {}
    for _, entity in ents.Iterator() do
        if IsValid(entity) then
            seen[entity] = true
            updateShadowCasterEntity(entity)
        end
    end
    for entity in pairs(CSM.ShadowCasterOverrides) do
        if not seen[entity] then CSM:RestoreShadowCaster(entity) end
    end

    local elapsed = SysTime() - startedAt
    shadowFilterScanCount = shadowFilterScanCount + 1
    shadowFilterTotalSeconds = shadowFilterTotalSeconds + elapsed
    shadowFilterMaximumSeconds = math.max(shadowFilterMaximumSeconds, elapsed)
end

local function processPendingShadowEntities()
    local pending = pendingShadowEntities
    pendingShadowEntities = {}
    for entity in pairs(pending) do
        updateShadowCasterEntity(entity)
    end
end

local function updateShadowCasterFilter(now)
    if now >= nextShadowFilterScanAt then
        nextShadowFilterScanAt = now + shadowFilterScanInterval
        scanShadowCasters()
    end
    processPendingShadowEntities()
    if processModelMeasurements() then shadowFilterRescanPending = true end
    if shadowFilterRescanPending and #modelMeasurementQueue == 0 then
        shadowFilterRescanPending = false
        scanShadowCasters()
        nextShadowFilterScanAt = now + shadowFilterScanInterval
    end
    if CSM.ModelCacheDirty and #modelMeasurementQueue == 0 then
        saveModelInfoCache()
    end
end

local function setState(state, reason)
    CSM.State = state
    CSM.Reason = reason
end

local function fail(reason)
    CSM:RestoreShadowCasterFilter()
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
    local excludedEntities = 0
    local temporarilyEnabledTrees = 0
    local modelFailureDetails = {}
    for _, state in pairs(self.ShadowCasterOverrides) do
        if state.shouldCast then
            temporarilyEnabledTrees = temporarilyEnabledTrees + 1
        else
            excludedEntities = excludedEntities + 1
        end
    end
    for model, reason in pairs(self.ShadowModelFailures) do
        modelFailureDetails[#modelFailureDetails + 1] = { model = model, reason = reason }
    end
    table.sort(modelFailureDetails, function(left, right) return left.model < right.model end)
    while #modelFailureDetails > 20 do
        table.remove(modelFailureDetails)
    end

    return {
        enabled = enabledConVar:GetBool(),
        quality = self:GetQuality(),
        state = self.State,
        reason = self.Reason,
        cascadeCount = #self.Projectors,
        updateRate = profile and profile.updateRate or 0,
        updateCount = self.UpdateCount,
        lastUpdateAt = self.LastUpdateAt,
        sunDirectionSource = self.SunDirectionSource,
        shadowCasterFilter = {
            triangleThreshold = shadowTriangleThreshold,
            excludedEntities = excludedEntities,
            temporarilyEnabledTrees = temporarilyEnabledTrees,
            measuredModels = table.Count(self.ShadowModelInfo),
            failedModels = table.Count(self.ShadowModelFailures),
            modelFailureDetails = modelFailureDetails,
            unsupportedBrushModels = table.Count(self.UnsupportedBrushModels),
            pendingModelMeasurements = math.max(
                0,
                #modelMeasurementQueue - modelMeasurementQueueHead + 1
            ),
            scanAverageMilliseconds = shadowFilterScanCount > 0 and
                shadowFilterTotalSeconds * 1000 / shadowFilterScanCount or 0,
            scanMaximumMilliseconds = shadowFilterMaximumSeconds * 1000,
            modelMeasurementAverageMilliseconds = modelMeasurementCount > 0 and
                modelMeasurementTotalSeconds * 1000 / modelMeasurementCount or 0,
            modelMeasurementMaximumMilliseconds = modelMeasurementMaximumSeconds * 1000,
            scanIntervalSeconds = shadowFilterScanInterval,
            modelCacheDirty = self.ModelCacheDirty,
            modelCacheFile = modelCacheFile,
            staticPropsFiltered = false
        }
    }
end

function CSM:GetPlayerProjectorPosition(playerPosition)
    return playerPosition + self.SunDirection * 1024
end

function CSM:Reconcile()
    if not enabledConVar:GetBool() then
        self:RestoreShadowCasterFilter()
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
        self:RestoreShadowCasterFilter()
        removeOwnedProjectors()
        setState(state, reason)
        return false
    end

    if self.Map ~= map then
        self:RestoreShadowCasterFilter()
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
    self:RestoreShadowCasterFilter()
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

local function updateProjectors(playerPosition, now)
    local frame = FrameNumber()
    if CSM.LastUpdateFrame == frame then return end
    local profile = qualityProfiles[CSM.AllocatedQuality]
    if not profile then
        fail("active CSM projectors have no matching quality profile")
        return
    end
    if profile.updateRate > 0 and now < CSM.NextUpdateAt then return end

    local position = CSM:GetPlayerProjectorPosition(playerPosition)
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
    local playerPosition = playerEntity:GetPos()
    if not isFiniteVector(playerPosition) then
        fail("local player position is invalid")
        return
    end
    local now = SysTime()
    updateShadowCasterFilter(now)
    updateProjectors(playerPosition, now)
end)

hook.Add("PreCleanupMap", hookName, function()
    CSM:RestoreShadowCasterFilter()
    removeOwnedProjectors()
    CSM.Map = nil
    CSM.SunDirection = nil
    CSM.SunDirectionSource = nil
    setState(enabledConVar:GetBool() and "waiting_for_map_metadata" or "off")
end)

hook.Add("ShutDown", hookName, function()
    CSM:RestoreShadowCasterFilter()
    removeOwnedProjectors()
end)

hook.Add("EntityRemoved", "ZM.CSM.ShadowCasterCleanup", function(entity)
    CSM.ShadowCasterOverrides[entity] = nil
    pendingShadowEntities[entity] = nil
end)

hook.Add("NetworkEntityCreated", "ZM.CSM.ShadowCasterCreated", function(entity)
    if CSM.State == "ready" then
        pendingShadowEntities[entity] = true
    end
end)

concommand.Remove("zombiesim_csm_status")
concommand.Add("zombiesim_csm_status", function()
    saveModelInfoCache()
    local encoded = util.TableToJSON(CSM:GetStatus(), true)
    if not encoded then
        ErrorNoHalt("[ZombieSim][CSM] Could not serialize status.\n")
        return
    end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/csm_status.json", encoded)
    print("[ZombieSim][CSM] " .. encoded)
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
