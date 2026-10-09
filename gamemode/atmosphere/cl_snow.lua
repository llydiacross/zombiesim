// Settled snow sampling, chunk meshes, footprint trails and loading-screen preload.
return function(Atmosphere, Modules)
    local Environment = Modules.Environment
    local Snow = Modules.Snow
    // Snow cover settles patchily over about 3 minutes of snowfall, melts over 25 s when clear and 8 s in rain. The
    // server owns the amount (sv_atmosphere.lua uses the same rates); the client only evolves it between syncs.
    local snowCoverBuildSeconds = 180
    local snowCoverMeltSeconds = 25
    local snowCoverRainMeltSeconds = 8
    // Coverage is baked into the vertices in discrete stages; each stage change rebuilds the chunks a few per frame.
    local snowCoverStages = 48
    local snowCoverTargetPoints = 40000
    local snowCoverMinimumSpacing = 28
    local snowCoverPointsPerFrame = 300
    local snowCoverMaxStep = 6
    local snowCoverChunkQuads = 16
    local snowCoverChunksPerFrame = 6
    local snowCoverRebuildsPerFrame = 4
    // Chunks are drawn only inside a slightly widened view cone, and not beyond an opaque fog end.
    local snowCoverCullConeMargin = math.rad(6)
    Snow.FogCullDistance = nil
    // While the loading screen hides a fresh map, the cover is built much faster and the fade-in waits for it.
    local snowPreloadPointsPerFrame = 4000
    local snowPreloadChunksPerFrame = 40
    local snowPreloadWindowSeconds = 15
    local snowPreloadMaxSeconds = 12
    local snowCarveRadius = 34
    local snowCarveInterval = 10
    local snowFootprintFillSeconds = 150
    // Refilling footprints only re-bake when a point's depth crosses one of these steps; the refill runs once per
    // step so each pass re-bakes every trodden chunk once instead of a few points' chunks every 3 s.
    local snowTrailRefillSteps = 12
    local snowTrailRefillInterval = snowFootprintFillSeconds / snowTrailRefillSteps
    local cover = Atmosphere.SnowCover or { status = "not built" }
    Snow.Cover = cover
    Atmosphere.SnowCover = cover
    local snowFloorMaterial = Material("nature/snowfloor001a")
    Snow.SnowFloorTexture = not snowFloorMaterial:IsError() and snowFloorMaterial:GetTexture("$basetexture") or nil
    if Snow.SnowFloorTexture and Snow.SnowFloorTexture:IsError() then
        Snow.SnowFloorTexture = nil
    end
    // The texture is named in the material's key values: a texture swapped in after creation did not survive fresh
    // map loads (the cover rendered flat white), so the draw also re-applies it if the material lost it.
    Snow.SnowCoverMaterial = CreateMaterial("zombiesim_atmosphere_snow_cover_v3", "UnlitGeneric", {
        ["$basetexture"] = Snow.SnowFloorTexture and Snow.SnowFloorTexture:GetName() or "color/white",
        ["$translucent"] = "1",
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
        ["$nocull"] = "1",
        ["$alpha"] = "1"
    })
    local snowCoverMeshVersion = 8
    local snowCoverLift = 4

    // Snow cover: a client-side heightfield blanket sampled once per map over every sky-exposed walkable
    // surface, built into static meshes and faded in/out as snow settles and melts. No map compile needed.
    local function snowHash(first, second)
        local value = math.sin(first * 12.9898 + second * 78.233) * 43758.5453
        return value - math.floor(value)
    end

    local function destroySnowCoverMeshes()
        for _, chunk in pairs(cover.chunks or {}) do
            if chunk.imesh then
                chunk.imesh:Destroy()
                chunk.imesh = nil
            end
        end
        for _, imesh in ipairs(cover.meshes or {}) do
            imesh:Destroy()
        end
        cover.meshes = {}
        cover.chunks = {}
        cover.chunkList = {}
        cover.dirtyChunks = {}
        cover.urgentChunks = {}
        cover.meshCount = 0
    end

    local function beginSnowCover(mapName)
        destroySnowCoverMeshes()
        local minimum, maximum = Environment.WorldMinimum, Environment.WorldMaximum
        local width = maximum.x - minimum.x
        local height = maximum.y - minimum.y
        local detail = Atmosphere.GetQualityNumber("snowDetail", 1, 0.25, 1)
        local spacing = math.max(snowCoverMinimumSpacing,
            math.ceil(math.sqrt(width * height / (snowCoverTargetPoints * detail))))
        cover.map = mapName
        cover.meshVersion = snowCoverMeshVersion
        cover.detail = detail
        cover.status = "sampling"
        cover.spacing = spacing
        cover.originX = minimum.x
        cover.originY = minimum.y
        cover.columns = math.floor(width / spacing) + 1
        cover.rows = math.floor(height / spacing) + 1
        cover.total = cover.columns * cover.rows
        cover.chunkColumns = math.ceil(cover.columns / snowCoverChunkQuads)
        cover.points = {}
        cover.trodden = {}
        cover.troddenCount = 0
        cover.cursor = 0
        cover.validPoints = 0
        cover.validQuads = nil
        cover.buildCursor = 1
        cover.triangleCount = 0
        cover.lastCarvePosition = nil
        cover.stage = math.Round((Atmosphere.SnowCoverAmount or 0) * snowCoverStages) / snowCoverStages
    end

    // Smooth value noise over a few grid cells, so snow settles in drifts rather than per-sample speckle.
    local function snowPatchNoise(column, row)
        local x, y = column / 7, row / 7
        local x0, y0 = math.floor(x), math.floor(y)
        local fx, fy = x - x0, y - y0
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        local top = Lerp(fx, snowHash(x0, y0), snowHash(x0 + 1, y0))
        local bottom = Lerp(fx, snowHash(x0, y0 + 1), snowHash(x0 + 1, y0 + 1))
        return Lerp(fy, top, bottom)
    end

    local function sampleSnowCover(budget)
        local columns = cover.columns
        local spacing = cover.spacing
        local deadline = Environment.GetAtmosphereWorkDeadline()
        for sampled = 1, budget do
            if sampled > 1 and SysTime() >= deadline then return end
            local cursor = cover.cursor
            if cursor >= cover.total then
                cover.status = "meshing"
                return
            end
            cover.cursor = cursor + 1
            local column = cursor % columns
            local row = math.floor(cursor / columns)
            local trace = Environment.TraceGround(Vector(cover.originX + column * spacing, cover.originY + row * spacing, 0), nil)
            if trace and Environment.IsSurfaceExposed(trace, nil) then
                local normal = trace.HitNormal
                local light = render.GetLightColor(trace.HitPos + normal * 4)
                local position = trace.HitPos + normal * snowCoverLift
                cover.points[cursor + 1] = {
                    position = position,
                    normal = normal,
                    // Plain numbers let chunk re-bakes update pooled vertices without Vector temporaries.
                    px = position.x, py = position.y, pz = position.z,
                    nx = normal.x, ny = normal.y, nz = normal.z,
                    // Unlit material: keep snow bright and only dim it modestly in darker spots.
                    brightness = math.Clamp(0.72 + (light.x + light.y + light.z) / 3 * 0.8, 0.72, 1),
                    drift = 0.7 + 0.3 * snowHash(column * 0.37, row * 0.71),
                    // Lower values settle first and melt last.
                    patch = 0.8 * snowPatchNoise(column, row) + 0.2 * snowHash(column * 1.31, row * 2.17)
                }
                cover.validPoints = cover.validPoints + 1
            end
        end
    end

    local function getSnowChunkKey(index)
        local columns = cover.columns
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        return math.floor(row / snowCoverChunkQuads) * cover.chunkColumns + math.floor(column / snowCoverChunkQuads)
    end

    // Quads are grouped into small spatial chunks so a carved trail only rebuilds the chunks it touches.
    local function collectSnowCoverQuads()
        local points = cover.points
        local columns = cover.columns
        local valid = {}
        local chunks = {}
        local chunkList = {}
        for row = 0, cover.rows - 2 do
            for column = 0, columns - 2 do
                local index = row * columns + column + 1
                local a, b, c, d = points[index], points[index + 1], points[index + columns + 1], points[index + columns]
                if a and b and c and d then
                    local low = math.min(a.position.z, b.position.z, c.position.z, d.position.z)
                    local high = math.max(a.position.z, b.position.z, c.position.z, d.position.z)
                    // Skip quads that would bridge kerbs or walls; their neighbours feather out instead.
                    if high - low <= snowCoverMaxStep then
                        valid[index] = true
                        local key = getSnowChunkKey(index)
                        local chunk = chunks[key]
                        if not chunk then
                            chunk = { key = key, quads = {},
                                minX = math.huge, minY = math.huge, minZ = math.huge,
                                maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge,
                                patchMin = math.huge, patchMax = -math.huge }
                            chunks[key] = chunk
                            chunkList[#chunkList + 1] = chunk
                        end
                        chunk.quads[#chunk.quads + 1] = index
                        for _, point in ipairs({ a, b, c, d }) do
                            chunk.minX = math.min(chunk.minX, point.px)
                            chunk.minY = math.min(chunk.minY, point.py)
                            chunk.minZ = math.min(chunk.minZ, point.pz)
                            chunk.maxX = math.max(chunk.maxX, point.px)
                            chunk.maxY = math.max(chunk.maxY, point.py)
                            chunk.maxZ = math.max(chunk.maxZ, point.pz)
                            chunk.patchMin = math.min(chunk.patchMin, point.patch)
                            chunk.patchMax = math.max(chunk.patchMax, point.patch)
                        end
                    end
                end
            end
        end
        // Bounding spheres for draw culling.
        for _, chunk in ipairs(chunkList) do
            chunk.centerX = (chunk.minX + chunk.maxX) * 0.5
            chunk.centerY = (chunk.minY + chunk.maxY) * 0.5
            chunk.centerZ = (chunk.minZ + chunk.maxZ) * 0.5
            local dx, dy, dz = chunk.maxX - chunk.centerX, chunk.maxY - chunk.centerY, chunk.maxZ - chunk.centerZ
            chunk.radius = math.sqrt(dx * dx + dy * dy + dz * dz) + snowCoverLift
        end
        cover.validQuads = valid
        cover.chunks = chunks
        cover.chunkList = chunkList
        cover.buildCursor = 1
    end

    local function getSnowVertexAlpha(index)
        local columns = cover.columns
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        if column == 0 or row == 0 then return 0 end
        local valid = cover.validQuads
        if valid[index] and valid[index - 1] and valid[index - columns] and valid[index - columns - 1] then
            return 255 * cover.points[index].drift
        end
        return 0
    end

    // Rewrites a pooled vertex in place: no tables, Vectors or Colors are allocated per re-bake.
    local function updateSnowVertex(vertex, index)
        local point = cover.points[index]
        local trodden = cover.trodden[index] or 0
        // Each point fills in over its own slice of the build: patches settle first, then the cover joins up and thickens.
        local coverage = math.Clamp((cover.stage - point.patch * 0.6) / 0.4, 0, 1)
        local depth = 1 + (snowCoverLift - 1) * coverage
        // Trodden snow is pressed down towards the ground, greyer, and thin enough to show the road through.
        local offset = depth - (depth - 0.5) * trodden - snowCoverLift
        vertex.pos:SetUnpacked(point.px + point.nx * offset, point.py + point.ny * offset, point.pz + point.nz * offset)
        local brightness = point.brightness * (1 - 0.28 * trodden)
        local color = vertex.color
        color.r = 236 * brightness
        color.g = 241 * brightness
        color.b = 250 * brightness
        color.a = point.edgeAlpha * coverage * (1 - 0.72 * trodden)
    end

    local function getSnowChunkVertex(chunk, index)
        local vertex = chunk.vertices[index]
        if not vertex then
            local point = cover.points[index]
            if point.edgeAlpha == nil then
                point.edgeAlpha = getSnowVertexAlpha(index)
            end
            vertex = {
                pos = Vector(point.px, point.py, point.pz),
                normal = point.normal,
                u = point.px / 192,
                v = point.py / 192,
                color = Color(255, 255, 255, 0)
            }
            chunk.vertices[index] = vertex
            chunk.vertexList[#chunk.vertexList + 1] = index
        end
        return vertex
    end

    // The triangle list references shared pooled vertices, so it is built once per chunk and reused.
    local function prepareSnowChunkVertices(chunk)
        chunk.vertices = {}
        chunk.vertexList = {}
        local triangles = {}
        local columns = cover.columns
        for _, index in ipairs(chunk.quads) do
            local a, b = getSnowChunkVertex(chunk, index), getSnowChunkVertex(chunk, index + 1)
            local c, d = getSnowChunkVertex(chunk, index + columns + 1), getSnowChunkVertex(chunk, index + columns)
            triangles[#triangles + 1] = a
            triangles[#triangles + 1] = c
            triangles[#triangles + 1] = b
            triangles[#triangles + 1] = a
            triangles[#triangles + 1] = d
            triangles[#triangles + 1] = c
        end
        chunk.triangleList = triangles
    end

    local function buildSnowChunkMesh(chunk)
        local startedAt = SysTime()
        if chunk.imesh then
            chunk.imesh:Destroy()
            chunk.imesh = nil
            cover.meshCount = cover.meshCount - 1
            cover.triangleCount = cover.triangleCount - (chunk.triangles or 0)
        end
        if not chunk.triangleList then
            prepareSnowChunkVertices(chunk)
        end
        if #chunk.triangleList == 0 then return end
        local vertices = chunk.vertices
        for _, index in ipairs(chunk.vertexList) do
            updateSnowVertex(vertices[index], index)
        end
        local imesh = Mesh(Snow.SnowCoverMaterial)
        imesh:BuildFromTriangles(chunk.triangleList)
        chunk.imesh = imesh
        chunk.triangles = #chunk.quads * 2
        cover.meshCount = cover.meshCount + 1
        cover.rebuildCount = (cover.rebuildCount or 0) + 1
        cover.rebuildSeconds = (cover.rebuildSeconds or 0) + SysTime() - startedAt
        cover.triangleCount = cover.triangleCount + chunk.triangles
    end

    local function buildSnowCoverChunks(budget)
        if not cover.validQuads then
            collectSnowCoverQuads()
            return
        end
        local chunkList = cover.chunkList
        local deadline = Environment.GetAtmosphereWorkDeadline()
        for built = 1, budget do
            if built > 1 and SysTime() >= deadline then return end
            local chunk = chunkList[cover.buildCursor]
            if not chunk then
                cover.status = "ready"
                return
            end
            buildSnowChunkMesh(chunk)
            cover.buildCursor = cover.buildCursor + 1
        end
    end

    local function markSnowQuadDirty(quadIndex, urgent)
        if cover.validQuads[quadIndex] then
            local key = getSnowChunkKey(quadIndex)
            if urgent then
                cover.urgentChunks[key] = true
            else
                cover.dirtyChunks[key] = true
            end
        end
    end

    // A point is shared by up to four quads; footprints are urgent so they jump the background re-bake queue.
    local function markSnowPointDirty(index, urgent)
        if not cover.validQuads or not cover.dirtyChunks then return end
        cover.urgentChunks = cover.urgentChunks or {}
        local columns = cover.columns
        markSnowQuadDirty(index, urgent)
        markSnowQuadDirty(index - 1, urgent)
        markSnowQuadDirty(index - columns, urgent)
        markSnowQuadDirty(index - columns - 1, urgent)
    end

    local function rebuildDirtySnowChunks(budget)
        local limit = budget or snowCoverRebuildsPerFrame
        local deadline = Environment.GetAtmosphereWorkDeadline()
        local rebuilt = 0
        local urgent = cover.urgentChunks or {}
        local dirty = cover.dirtyChunks
        while rebuilt < limit do
            local key = next(urgent)
            local queue = urgent
            if key == nil then
                key = next(dirty)
                queue = dirty
            end
            if key == nil then return end
            queue[key] = nil
            dirty[key] = nil
            local chunk = cover.chunks[key]
            if chunk then
                buildSnowChunkMesh(chunk)
            end
            rebuilt = rebuilt + 1
            if SysTime() >= deadline then return end
        end
    end

    // Coverage only changes for points whose settle window [0.6 * patch, 0.6 * patch + 0.4] overlaps the stage move.
    local function isSnowChunkAffectedByStage(chunk, from, to)
        local low, high = math.min(from, to), math.max(from, to)
        return high > chunk.patchMin * 0.6 and low < chunk.patchMax * 0.6 + 0.4
    end

    function Snow.GetSnowCoverPointAt(position)
        if cover.status ~= "ready" or cover.map ~= game.GetMap() then return nil end
        local column = math.Round((position.x - cover.originX) / cover.spacing)
        local row = math.Round((position.y - cover.originY) / cover.spacing)
        if column < 0 or row < 0 or column >= cover.columns or row >= cover.rows then return nil end
        local point = cover.points[row * cover.columns + column + 1]
        if point and math.abs(point.position.z - snowCoverLift - position.z) <= 16 then return point end
        return nil
    end

    local function carveSnowAt(position)
        local spacing = cover.spacing
        local columns = cover.columns
        local radius = snowCarveRadius
        local centerColumn = (position.x - cover.originX) / spacing
        local centerRow = (position.y - cover.originY) / spacing
        local reach = math.ceil(radius / spacing)
        local points = cover.points
        local trodden = cover.trodden
        for row = math.max(0, math.floor(centerRow) - reach), math.min(cover.rows - 1, math.ceil(centerRow) + reach) do
            for column = math.max(0, math.floor(centerColumn) - reach), math.min(columns - 1, math.ceil(centerColumn) + reach) do
                local index = row * columns + column + 1
                local point = points[index]
                if point and math.abs(point.position.z - snowCoverLift - position.z) <= 24 then
                    local dx = point.position.x - position.x
                    local dy = point.position.y - position.y
                    local falloff = 1 - math.sqrt(dx * dx + dy * dy) / radius
                    if falloff > 0 then
                        local depth = math.min(1, falloff * 1.6)
                        local current = trodden[index]
                        if not current or current < depth - 0.05 then
                            if not current then cover.troddenCount = cover.troddenCount + 1 end
                            trodden[index] = depth
                            markSnowPointDirty(index, true)
                        end
                    end
                end
            end
        end
    end

    function Snow.ClearSnowTrail()
        for index in pairs(cover.trodden or {}) do
            markSnowPointDirty(index)
        end
        cover.trodden = {}
        cover.troddenCount = 0
        cover.lastCarvePosition = nil
    end

    local function updateSnowTrail(weather)
        local player = LocalPlayer()
        if IsValid(player) and player:Alive() and player:IsOnGround() and player:GetMoveType() ~= MOVETYPE_NOCLIP then
            local position = player:GetPos()
            local last = cover.lastCarvePosition
            if not last or last:DistToSqr(position) >= snowCarveInterval * snowCarveInterval then
                cover.lastCarvePosition = position
                if Snow.GetSnowCoverPointAt(position) then
                    carveSnowAt(position)
                end
            end
        end

        // Fresh snowfall slowly fills the trail back in.
        local now = RealTime()
        if weather == "snow" and cover.troddenCount > 0 and now >= (cover.nextRefillAt or 0) then
            local elapsed = now - (cover.lastRefillAt or now)
            cover.lastRefillAt = now
            cover.nextRefillAt = now + snowTrailRefillInterval
            local fill = elapsed / snowFootprintFillSeconds
            if fill > 0 then
                for index, depth in pairs(cover.trodden) do
                    local updated = depth - fill
                    if updated <= 0.02 then
                        cover.trodden[index] = nil
                        cover.troddenCount = cover.troddenCount - 1
                        markSnowPointDirty(index)
                    else
                        cover.trodden[index] = updated
                        if math.floor(updated * snowTrailRefillSteps) ~= math.floor(depth * snowTrailRefillSteps) then
                            markSnowPointDirty(index)
                        end
                    end
                end
            end
        elseif weather ~= "snow" then
            cover.lastRefillAt = nil
        end
        rebuildDirtySnowChunks()
    end

    local function setSnowPreload(active)
        if active == (cover.preloadStep ~= nil) then return end
        if active then
            cover.preloadStartedAt = SysTime()
            cover.preloadStep = ZM_Loading and ZM_Loading:Begin("Settling snow cover") or false
        else
            if cover.preloadStep and ZM_Loading then
                local ready = cover.status == "ready"
                ZM_Loading:Finish(cover.preloadStep, ready and "ok" or "warn",
                    ready and string.format("Settled snow cover (%d triangles)", cover.triangleCount or 0)
                        or "Snow cover still settling")
            end
            cover.preloadStep = nil
            cover.preloadDone = true
            cover.preloadSeconds = SysTime() - (cover.preloadStartedAt or SysTime())
            cover.preloadResult = cover.status == "ready" and "ready" or "timed out"
            print(string.format("[ZombieSim] Snow cover preload %s after %.2f s (%d triangles).",
                cover.preloadResult, cover.preloadSeconds, cover.triangleCount or 0))
        end
        if ZM_LoadingScreen and ZM_LoadingScreen.SetExtraHold then
            ZM_LoadingScreen:SetExtraHold("snowCover", active)
        end
    end

    // Only a freshly loaded map waits for its snow cover; weather changes during play build it in the background.
    local function updateSnowPreload(amount, outdoorMap)
        if cover.preloadDone then return false end
        local mapName = game.GetMap()
        local needed = outdoorMap and amount > 0.002
            and (cover.map ~= mapName or cover.meshVersion ~= snowCoverMeshVersion
                or cover.detail ~= Atmosphere.GetQualityNumber("snowDetail", 1, 0.25, 1) or cover.status ~= "ready")
        if cover.preloadStep ~= nil then
            if not needed or SysTime() - cover.preloadStartedAt > snowPreloadMaxSeconds then
                setSnowPreload(false)
                return false
            end
            return true
        end
        if needed and SysTime() - Atmosphere.SessionStart < snowPreloadWindowSeconds then
            setSnowPreload(true)
            return true
        end
        if SysTime() - Atmosphere.SessionStart >= snowPreloadWindowSeconds then
            cover.preloadDone = true
        end
        return false
    end

    local function saveSnowCookie(amount)
        local now = RealTime()
        if now < (cover.nextCookieAt or 0) then return end
        cover.nextCookieAt = now + 2
        cookie.Set("zombiesim_snow_cover", string.format("%.4f", amount))
        cookie.Set("zombiesim_weather", Atmosphere.WeatherSynced and Atmosphere.Weather or (Atmosphere.CachedWeather or "clear"))
    end

    function Snow.UpdateSnowCover()
        // Before the first sync, assume the last known weather so a cached cover neither grows nor melts wrongly.
        local weather = Atmosphere.WeatherSynced and Atmosphere.Weather or Atmosphere.CachedWeather
        local outdoorMap = Environment.HasOutdoorCityCells()
        local frameTime = FrameTime()
        local amount = Atmosphere.SnowCoverAmount or 0
        if weather == "snow" then
            amount = math.min(1, amount + frameTime / snowCoverBuildSeconds)
        else
            amount = math.max(0, amount - frameTime / (weather == "rain" and snowCoverRainMeltSeconds or snowCoverMeltSeconds))
        end
        Atmosphere.SnowCoverAmount = amount
        saveSnowCookie(amount)
        local preloading = updateSnowPreload(amount, outdoorMap)
        if amount <= 0 then
            if cover.status == "ready" and (cover.troddenCount or 0) > 0 then
                Snow.ClearSnowTrail()
                rebuildDirtySnowChunks()
            end
            return
        end

        local mapName = game.GetMap()
        // A changed snow-detail setting resamples the cover in the background, like a new map would.
        if cover.map ~= mapName or cover.meshVersion ~= snowCoverMeshVersion
            or cover.detail ~= Atmosphere.GetQualityNumber("snowDetail", 1, 0.25, 1) then
            if not outdoorMap or not Environment.EnsureSurfaceSites() then return end
            beginSnowCover(mapName)
        end
        if cover.status == "sampling" then
            sampleSnowCover(preloading and snowPreloadPointsPerFrame or snowCoverPointsPerFrame)
        elseif cover.status == "meshing" then
            cover.stage = math.Round(amount * snowCoverStages) / snowCoverStages
            buildSnowCoverChunks(preloading and snowPreloadChunksPerFrame or snowCoverChunksPerFrame)
        elseif cover.status == "ready" then
            // A new coverage stage re-bakes only the chunks whose points it changes, a few per frame, so the cover
            // fills in (or thins) gradually.
            local stage = math.Round(amount * snowCoverStages) / snowCoverStages
            if stage ~= cover.stage then
                local previous = cover.stage or 0
                cover.stage = stage
                for key, chunk in pairs(cover.chunks) do
                    if isSnowChunkAffectedByStage(chunk, previous, stage) then
                        cover.dirtyChunks[key] = true
                    end
                end
            end
            updateSnowTrail(weather)
        end
    end
    local identityMatrix = Matrix()

    function Modules.Snow.RegisterHooks()
        hook.Add("PreDrawTranslucentRenderables", "ZM.Atmosphere.SnowCover", function(drawingDepth, drawingSkybox)
            cover.hookCount = (cover.hookCount or 0) + 1
            if drawingDepth or drawingSkybox then return end
            local amount = Atmosphere.SnowCoverAmount or 0
            if amount <= 0.002 or cover.map ~= game.GetMap() then return end
            // The settled pattern lives in the vertices; this only fades the first dusting in and the last of a melt out.
            local fade = math.min(1, amount * 3)
            local coverAlpha = fade * fade * (3 - 2 * fade)
            // Static meshes inherit whatever model matrix the last entity left behind; draw in world space.
            cam.PushModelMatrix(identityMatrix)
            if cover.chunkList and (cover.meshCount or 0) > 0 then
                if Snow.SnowFloorTexture then
                    local current = Snow.SnowCoverMaterial:GetTexture("$basetexture")
                    if not current or current:GetName() ~= Snow.SnowFloorTexture:GetName() then
                        Snow.SnowCoverMaterial:SetTexture("$basetexture", Snow.SnowFloorTexture)
                        cover.textureReapplied = (cover.textureReapplied or 0) + 1
                    end
                end
                Snow.SnowCoverMaterial:SetFloat("$alpha", coverAlpha)
                render.SetMaterial(Snow.SnowCoverMaterial)
                // IMesh:Draw is not engine-culled: skip chunks outside the view cone or hidden by opaque fog.
                local eyeX, eyeY, eyeZ = EyePos():Unpack()
                local forwardX, forwardY, forwardZ = EyeVector():Unpack()
                local view = render.GetViewSetup and render.GetViewSetup() or nil
                local coneSin, coneCos
                if view and view.fov and not view.ortho then
                    local tanHorizontal = math.tan(math.rad(math.Clamp(view.fov, 1, 170)) * 0.5)
                    local aspect = view.aspect
                    if not aspect or aspect <= 0 then
                        aspect = (view.w or view.width or ScrW()) / math.max(1, view.h or view.height or ScrH())
                    end
                    local tanVertical = tanHorizontal / aspect
                    local halfAngle = math.atan(math.sqrt(tanHorizontal * tanHorizontal + tanVertical * tanVertical))
                        + snowCoverCullConeMargin
                    if halfAngle < math.pi * 0.5 then
                        coneSin, coneCos = math.sin(halfAngle), math.cos(halfAngle)
                    end
                end
                local maxDistance = (view and view.ortho) and nil or Snow.FogCullDistance
                local qualityDistance = Atmosphere.GetQualityNumber("snowDrawDistance", 0, 0, 100000)
                if qualityDistance > 0 and not (view and view.ortho) then
                    maxDistance = maxDistance and math.min(maxDistance, qualityDistance) or qualityDistance
                end
                local drawn, culled = 0, 0
                for _, chunk in ipairs(cover.chunkList) do
                    if chunk.imesh then
                        local radius = chunk.radius
                        local visible = true
                        if radius then
                            local dx, dy, dz = chunk.centerX - eyeX, chunk.centerY - eyeY, chunk.centerZ - eyeZ
                            local distanceSqr = dx * dx + dy * dy + dz * dz
                            local along = dx * forwardX + dy * forwardY + dz * forwardZ
                            visible = along >= -radius
                            if visible and maxDistance then
                                local reach = maxDistance + radius
                                visible = distanceSqr <= reach * reach
                            end
                            if visible and coneSin and distanceSqr > radius * radius then
                                local lateral = math.sqrt(math.max(0, distanceSqr - along * along))
                                visible = lateral * coneCos - along * coneSin <= radius
                            end
                        end
                        if visible then
                            chunk.imesh:Draw()
                            drawn = drawn + 1
                        else
                            culled = culled + 1
                        end
                    end
                end
                cover.lastDrawnChunks = drawn
                cover.lastCulledChunks = culled
                cover.drawCount = (cover.drawCount or 0) + 1
            end
            cam.PopModelMatrix()
        end)
    end
end
