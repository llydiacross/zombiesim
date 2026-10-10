// Shared capture identity and projection rules; no engine state is mutated here.
local Contract = {}
local cachedRaw, cachedSkyline, cachedSha256
Contract.SchemaVersion = 1
Contract.Size = 1024
Contract.CaptureVersion = 4
Contract.Variants = {"clear", "atmospheric"}

function Contract.Revision(world, profile, skyline, skylineSha256)
    if type(world) ~= "table" or profile ~= "preview" or world.profileId ~= profile then
        return nil, "capture requires authoritative preview world data"
    end
    for _, key in ipairs({"mapManifestSha256", "templatePlanSha256"}) do
        if type(world[key]) ~= "string" or #world[key] ~= 64 or not world[key]:match("^[a-fA-F0-9]+$") then
            return nil, "missing authoritative " .. key
        end
    end
    local bounds = world.cellBounds
    if type(bounds) ~= "table" or type(bounds.neighbourPitch) ~= "number"
        or bounds.neighbourPitch <= 0 or bounds.neighbourPitch >= 16384
        or type(bounds.playableCeiling) ~= "number" or bounds.playableCeiling <= 64
        or bounds.playableCeiling >= 16384 or type(bounds.revision) ~= "number" then
        return nil, "missing authoritative cell bounds"
    end
    if type(skyline) ~= "table" or skyline.profile ~= profile
        or skyline.templatePlanSha256 ~= world.templatePlanSha256
        or skyline.cellSpan ~= bounds.neighbourPitch
        or type(skyline.scale) ~= "number" or skyline.scale <= 0 or skyline.scale > 128
        or skyline.scale ~= skyline.scale
        or type(skyline.cellBounds) ~= "table" or skyline.cellBounds.revision ~= bounds.revision
        or type(skyline.cameraOrigin) ~= "table" or type(skyline.cameraOrigin[3]) ~= "number"
        or type(skylineSha256) ~= "string" or #skylineSha256 ~= 64
        or not skylineSha256:match("^[a-fA-F0-9]+$") then
        return nil, "missing/mismatched authoritative skyline camera"
    end
    // Same clearance as ZM_Skybox:GetPlayableCeiling; the client cross-checks that owning API.
    local cameraZ = skyline.cameraOrigin[3] - 128
    if cameraZ ~= cameraZ or cameraZ <= 64 or cameraZ >= 16384 then return nil, "invalid skyline capture ceiling" end
    return {
        schemaVersion = Contract.SchemaVersion, captureVersion = Contract.CaptureVersion, profile = profile,
        mapManifestSha256 = world.mapManifestSha256,
        templatePlanSha256 = world.templatePlanSha256,
        boundsRevision = bounds.revision, pitch = bounds.neighbourPitch,
        cameraZ = cameraZ, skylineManifestSha256 = skylineSha256, size = Contract.Size
    }
end

function Contract.InstalledRevision(world, profile, fileAPI, utilAPI)
    local raw = profile == "preview" and fileAPI.Read("data_static/zombiesim_skybox_preview.json", "GAME")
    if raw ~= cachedRaw then
        cachedRaw = raw
        cachedSkyline, cachedSha256 = raw and utilAPI.JSONToTable(raw), raw and utilAPI.SHA256(raw)
    end
    return Contract.Revision(world, profile, cachedSkyline, cachedSha256)
end

function Contract.Matches(expected, actual)
    if type(expected) ~= "table" or type(actual) ~= "table" then return false end
    for _, key in ipairs({"schemaVersion", "captureVersion", "profile", "mapManifestSha256", "templatePlanSha256",
        "boundsRevision", "pitch", "cameraZ", "skylineManifestSha256", "size"}) do
        if expected[key] ~= actual[key] then return false end
    end
    return true
end

function Contract.OutputPath(runId, cellId, variant)
    if type(runId) ~= "string" or not runId:match("^[%w_%-]+$")
        or type(cellId) ~= "number" or cellId < 0 or cellId ~= math.floor(cellId)
        or (variant ~= "clear" and variant ~= "atmospheric") then return nil end
    return "zombiesim/world_captures/" .. runId .. "/" .. variant .. "/cell_" .. cellId .. ".png"
end

function Contract.ValidPNG(data, size)
    if type(data) ~= "string" or #data < 33 or data:sub(1, 8) ~= "\137PNG\r\n\26\n"
        or data:sub(13, 16) ~= "IHDR" then return false end
    local function number(offset)
        local a, b, c, d = data:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return number(17) == size and number(21) == size
        and data:sub(-8, -5) == "IEND"
end

function Contract.View(revision)
    local half = revision.pitch * 0.5
    return {
        x = 0, y = 0, w = revision.size, h = revision.size, fov = 120,
        ortho = true,
        ortholeft = -half, orthoright = half,
        orthotop = -half, orthobottom = half, znear = 4, zfar = 8192,
        drawviewer = false, drawviewmodel = false, drawhud = false, dopostprocess = false
    }
end

return Contract
