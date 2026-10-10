ZM_Music = ZM_Music or {}
local Music = ZM_Music

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function array(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
        count = count + 1
    end
    return count == #value
end

function Music.RoutingKeys()
    local tags, zones = {}, { origin = true }
    for _, path in pairs(ZM_World.DataProfiles) do
        local data = util.JSONToTable(file.Read(path, "GAME") or "")
        if type(data) == "table" then
            for _, environment in ipairs(data.environments or {}) do
                for _, tag in ipairs(environment.tags or {}) do tags[tag] = true end
            end
            for _, zone in ipairs(data.safeZones or {}) do zones[zone.id] = true end
        end
    end
    return tags, zones
end

function Music.Validate(data, exists, knownTags, knownZones)
    local errors = {}
    local function fail(path, message) errors[#errors + 1] = { path = path, message = message } end
    if type(data) ~= "table" then fail("", "must be an object") return nil, errors end
    if data.schemaVersion ~= 1 then fail("schemaVersion", "must be 1") end
    local tracks, sets = {}, {}
    if not array(data.tracks) or #data.tracks == 0 then
        fail("tracks", "must be a nonempty array")
    else
        for index, track in ipairs(data.tracks) do
            local path = "tracks[" .. index .. "]"
            if type(track) ~= "table" or type(track.id) ~= "string" or not string.match(track.id, "^%l%w*$") then
                fail(path, "must have a stable track id")
            else
                if tracks[track.id] then fail(path .. ".id", "duplicate track id") end
                if type(track.name) ~= "string" or track.name == "" then fail(path .. ".name", "is required") end
                if track.duration ~= nil and (not finite(track.duration) or track.duration <= 0) then
                    fail(path .. ".duration", "must be omitted or a positive duration")
                end
                if type(track.file) ~= "string" or not string.match(track.file, "^sounds?/music/[%w _%-]+%.mp3$") then
                    fail(path .. ".file", "must be a packaged ASCII music MP3 path")
                elseif not exists(track.file) then
                    fail(path .. ".file", "music file is missing: " .. track.file)
                end
                tracks[track.id] = track
            end
        end
    end
    if type(data.sets) ~= "table" then fail("sets", "must be an object") else
        for id, entries in pairs(data.sets) do
            if type(id) ~= "string" or not string.match(id, "^%l%w*$") then fail("sets", "invalid set id") end
            if not array(entries) or #entries == 0 then fail("sets." .. tostring(id), "must be a nonempty track-id array") else
                local seen = {}
                for _, trackId in ipairs(entries) do
                    if type(trackId) ~= "string" or not tracks[trackId] then fail("sets." .. tostring(id), "unknown track id")
                    elseif seen[trackId] then fail("sets." .. id, "duplicate track variation")
                    else seen[trackId] = true end
                end
                sets[id] = entries
            end
        end
    end
    if type(data.defaultSet) ~= "string" or not sets[data.defaultSet] then fail("defaultSet", "must reference an existing default set") end
    local idle = data.idleSeconds
    if not array(idle) or #idle ~= 2 or not finite(idle[1]) or not finite(idle[2])
        or idle[1] < 1 or idle[2] < idle[1] then fail("idleSeconds", "must be ordered positive minimum/maximum seconds") end
    for _, mapping in ipairs({ { "safeZones", knownZones }, { "environmentTags", knownTags } }) do
        if type(data[mapping[1]]) ~= "table" then fail(mapping[1], "must be an object") else
            for key, setId in pairs(data[mapping[1]]) do
                if not mapping[2][key] then fail(mapping[1] .. "." .. tostring(key), "unknown routing key") end
                if type(setId) ~= "string" or not sets[setId] then fail(mapping[1] .. "." .. tostring(key), "unknown track set") end
            end
        end
    end
    if not array(data.tagPriority) then fail("tagPriority", "must be an array") else
        local seen = {}
        for _, tag in ipairs(data.tagPriority) do
            if type(tag) ~= "string" or not knownTags[tag] then fail("tagPriority", "unknown environment tag")
            elseif seen[tag] then fail("tagPriority", "duplicate environment tag")
            elseif type(data.environmentTags) ~= "table" or not data.environmentTags[tag] then fail("tagPriority", "tag has no music mapping")
            else seen[tag] = true end
        end
        for tag in pairs(type(data.environmentTags) == "table" and data.environmentTags or {}) do
            if not seen[tag] then fail("tagPriority", "mapped tag is missing its priority: " .. tostring(tag)) end
        end
    end
    if #errors > 0 then return nil, errors end
    return {
        tracks = tracks, sets = sets, defaultSet = data.defaultSet, idleSeconds = idle,
        safeZones = data.safeZones, environmentTags = data.environmentTags, tagPriority = data.tagPriority
    }, errors
end

function Music.Resolve(registry, context)
    if context.safeZoneId then
        local set = registry.safeZones[context.safeZoneId]
            or context.isOrigin and registry.safeZones.origin
        if set then return set, "safezone:" .. context.safeZoneId end
        return registry.defaultSet, "safezone-default:" .. context.safeZoneId
    end
    local tags = {}
    for _, tag in ipairs(context.tags or {}) do tags[tag] = true end
    for _, tag in ipairs(registry.tagPriority) do
        if tags[tag] then return registry.environmentTags[tag], "environment:" .. tag end
    end
    return registry.defaultSet, "default"
end

function Music.Select(registry, setId, random)
    local entries = registry.sets[setId]
    return entries[(random or math.random)(1, #entries)]
end

function Music.IdleDelay(registry, random)
    return (random or math.Rand)(registry.idleSeconds[1], registry.idleSeconds[2])
end

function Music.TransitionAction(saved, registry, context)
    local set = Music.Resolve(registry, context)
    if not saved.trackId then return "wait", set end
    if saved.safeZoneId and not context.safeZoneId then return "silence", set end
    if context.safeZoneId ~= saved.safeZoneId and context.safeZoneId then return "switch", set end
    if saved.routeSet then
        return saved.routeSet == set and "resume" or "switch", set
    end
    for _, id in ipairs(registry.sets[set]) do
        if id == saved.trackId then return "resume", set end
    end
    return "switch", set
end

function Music.ValidResume(saved, registry)
    return type(saved) == "table" and saved.version == 1 and (saved.trackId == nil
        or type(saved.trackId) == "string" and registry.tracks[saved.trackId] ~= nil
        and finite(saved.position) and saved.position >= 0
        and (registry.tracks[saved.trackId].duration == nil or saved.position < registry.tracks[saved.trackId].duration))
        and finite(saved.nextAt) and saved.nextAt >= 0
        and (saved.routeSet == nil or type(saved.routeSet) == "string" and registry.sets[saved.routeSet] ~= nil)
        and (saved.safeZoneId == nil or type(saved.safeZoneId) == "string" and saved.safeZoneId ~= "")
end

function Music.DurationMatches(actual, expected)
    return finite(actual) and actual > 0
        and (expected == nil or finite(expected) and math.abs(actual - expected) <= 1)
end

function Music.OutputGain(musicVolume, intensity)
    return math.Clamp(musicVolume, 0, 1) * (1 - math.Clamp(intensity, 0, 1) * 0.45)
end
