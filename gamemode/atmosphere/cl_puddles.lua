// Map-bound puddle growth, pooled wet-surface geometry and rain impacts.
return function(Atmosphere, Modules)
    local Environment = Modules.Environment
    local Weather = Modules.Weather
    local Puddles = Modules.Puddles
    local Footsteps = Modules.Footsteps
    Puddles.PuddleOpacityConVar = CreateClientConVar("zombiesim_atmosphere_puddle_opacity", "0.15", true, false,
        "Client rain puddle opacity (0.05 to 0.45).")
    local puddleAmountConVar = CreateClientConVar("zombiesim_atmosphere_puddle_amount", "1", true, false,
        "Client rain puddle amount multiplier (0.5 to 3).")
    Puddles.NextPuddleAt = 0
    Puddles.PuddleSiteDebt = 0
    Puddles.PuddleSiteCursor = Atmosphere.PuddleSiteCursor or 1
    local puddles = Atmosphere.WetPuddles or {}
    Puddles.Items = puddles
    Atmosphere.WetPuddles = puddles
    // Refract ignores vertex alpha, so puddles use an alpha-blended wet-darkening pass plus a faint additive sheen.
    Puddles.PuddleMaterial = CreateMaterial("zombiesim_atmosphere_puddle_wet_v3", "UnlitGeneric", {
        ["$basetexture"] = "color/white",
        ["$translucent"] = "1",
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
        ["$nocull"] = "1"
    })
    local puddleSheenMaterial = CreateMaterial("zombiesim_atmosphere_puddle_sheen_v3", "UnlitGeneric", {
        ["$basetexture"] = "color/white",
        ["$additive"] = "1",
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
        ["$nocull"] = "1"
    })
    // Additive envmap-only pass: a black base leaves just the mounted HL2 outdoor water cubemap,
    // sampled along the view reflection vector so the water reflects the sky and shifts with the camera.
    Puddles.PuddleReflectionMaterial = CreateMaterial("zombiesim_atmosphere_puddle_reflect_v1", "UnlitGeneric", {
        ["$basetexture"] = "color/white",
        ["$color"] = "[0 0 0]",
        ["$envmap"] = "environment maps/water_wasteland05",
        ["$envmaptint"] = "[0.42 0.44 0.46]",
        ["$additive"] = "1",
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
        ["$nocull"] = "1"
    })
    if Puddles.PuddleReflectionMaterial:IsError() then
        Puddles.PuddleReflectionMaterial = nil
    end
    if Puddles.PuddleMaterial:IsError() or puddleSheenMaterial:IsError() then
        ErrorNoHalt("[ZombieSim] Could not initialize the puddle materials.\n")
        Puddles.PuddleMaterial = nil
    end
    Puddles.PuddleBaseTexture = Material("color/white"):GetTexture("$basetexture")
    Puddles.SplashRingMaterial = Material("effects/select_ring")
    if Puddles.SplashRingMaterial:IsError() then
        ErrorNoHalt("[ZombieSim] Mounted splash ring material is unavailable.\n")
    end
    local basePuddleSites = 64
    local maxPuddleLobes = 8
    local maxPuddleMeshLobes = 64
    local puddleSiteInterval = 0.55
    local puddleSiteCycleTicks = 64
    local puddleMatureSeconds = 240
    local puddleFlatTolerance = 6

    function Puddles.GetPuddleAmount()
        return math.Clamp(puddleAmountConVar:GetFloat(), 0.5, 3)
    end

    function Puddles.GetActivePuddleSiteCount()
        return math.Clamp(math.Round(basePuddleSites * Puddles.GetPuddleAmount()), 16, Environment.SurfaceSiteCapacity)
    end

    function Puddles.GetPuddleClusterLimit()
        return Puddles.GetActivePuddleSiteCount()
    end

    function Puddles.GetVisiblePuddleClusterLimit()
        return math.Clamp(math.Round(14 * Puddles.GetPuddleAmount()), 8, 32)
    end

    function Puddles.GetVisiblePuddleLobeLimit()
        return math.Clamp(math.Round(32 * Puddles.GetPuddleAmount()), 16, maxPuddleMeshLobes)
    end
    local puddleLifetime = 60
    Puddles.PuddleMeshSegments = 32
    // Lobes beyond this distance draw every second outline segment; the outline points themselves are unchanged.
    local puddleMeshLodDistanceSqr = 900 * 900
    Puddles.PuddleProbeDirections = {
        Vector(1, 0, 0),
        Vector(0.707, 0.707, 0),
        Vector(0, 1, 0),
        Vector(-0.707, 0.707, 0),
        Vector(-1, 0, 0),
        Vector(-0.707, -0.707, 0),
        Vector(0, -1, 0),
        Vector(0.707, -0.707, 0)
    }

    // Low-frequency harmonics give a smooth, organic outline instead of per-vertex spikes.
    local function createPuddleEdgeFactors()
        local harmonics = {
            { 2, math.Rand(0.06, 0.12), math.Rand(0, math.pi * 2) },
            { 3, math.Rand(0.04, 0.09), math.Rand(0, math.pi * 2) },
            { 5, math.Rand(0.01, 0.04), math.Rand(0, math.pi * 2) }
        }
        local edgeFactors = {}
        for index = 1, Puddles.PuddleMeshSegments do
            local angle = (index - 1) / Puddles.PuddleMeshSegments * math.pi * 2
            local factor = 1
            for _, harmonic in ipairs(harmonics) do
                factor = factor + harmonic[2] * math.sin(harmonic[1] * angle + harmonic[3])
            end
            edgeFactors[index] = factor
        end
        return edgeFactors
    end

    local function createPuddleLobe(trace, width, now)
        local edgeFactors = createPuddleEdgeFactors()
        return {
            position = trace.HitPos + trace.HitNormal * 0.6,
            normal = trace.HitNormal,
            width = 0,
            targetWidth = width,
            height = 0,
            targetHeight = width * math.Rand(0.68, 0.9),
            rotation = math.Rand(0, 360),
            opacityScale = math.Rand(0.8, 1),
            edgeFactors = edgeFactors,
            createdAt = now
        }
    end

    // Largest spread multiplier whose rim stays on level, open ground; prevents pools climbing kerbs or walls.
    local function measurePuddleMaxSpread(trace, width, player)
        local desired = math.random() < 0.22 and math.Rand(3.2, 4.4) or math.Rand(1.3, 2.0)
        local accepted = 1
        for _, spread in ipairs({ 1.4, 2, 2.8, 3.6, 4.4 }) do
            if spread > desired then break end
            local radius = width * 0.55 * spread
            for _, direction in ipairs({ Vector(1, 0, 0), Vector(0, 1, 0), Vector(-1, 0, 0), Vector(0, -1, 0) }) do
                local edge = Environment.TraceGround(trace.HitPos + direction * radius, player)
                if not edge or math.abs(edge.HitPos.z - trace.HitPos.z) > puddleFlatTolerance then
                    return accepted
                end
            end
            accepted = spread
        end
        return math.max(accepted, math.min(desired, accepted * 1.15))
    end

    local function addSpreadLobe(puddle, player, now)
        if #puddle.lobes >= maxPuddleLobes then return end
        local spread = puddle.spread or 1
        local angle = math.Rand(0, math.pi * 2)
        local distance = puddle.size * 0.45 * spread * math.Rand(0.35, 0.8)
        local offset = Vector(math.cos(angle) * distance, math.sin(angle) * distance, 0)
        local trace = Environment.TraceGround(puddle.position + offset, player)
        if not trace or math.abs(trace.HitPos.z - puddle.position.z) > puddleFlatTolerance then return end
        local lobe = createPuddleLobe(trace, math.Rand(88, 128), now)
        // Store lobes in unspread space so the render-time spread places them where the trace landed.
        local z = lobe.position.z
        lobe.position = puddle.position + (lobe.position - puddle.position) / spread
        lobe.position.z = z
        puddle.lobes[#puddle.lobes + 1] = lobe
    end

    local function addWetPuddle(site, player, now)
        if site.puddle and not site.puddle.removed then
            site.puddle.expiresAt = now + puddleLifetime
            site.puddle.lastWetAt = now
            if (site.puddle.spread or 1) > 1.25 and math.random() < 0.5 then
                addSpreadLobe(site.puddle, player, now)
            end
            return
        end

        local trace = Environment.TraceGround(site.position, player)
        if not trace then
            site.unusable = true
            return
        end
        trace = Environment.FindPuddleLowPoint(trace, player)
        if not Environment.IsSurfaceExposed(trace, player) then
            site.unusable = true
            return
        end

        local position = trace.HitPos + trace.HitNormal * 0.6
        local width = math.Rand(88, 128)
        local nearestPuddle
        local nearestDistance = math.huge
        for _, puddle in ipairs(puddles) do
            local dx = position.x - puddle.position.x
            local dy = position.y - puddle.position.y
            local distance = dx * dx + dy * dy
            local mergeDistance = math.max(108, math.min(puddle.size * 0.62 + width * 0.35, 210)) * (puddle.spread or 1)
            if not puddle.removed and math.abs(position.z - puddle.position.z) <= 40 and distance <= mergeDistance * mergeDistance and distance < nearestDistance then
                nearestPuddle = puddle
                nearestDistance = distance
            end
        end

        if not nearestPuddle then
            if #puddles >= Puddles.GetPuddleClusterLimit() then
                local oldestIndex = 1
                local oldestWetAt = math.huge
                for index, puddle in ipairs(puddles) do
                    local lastWetAt = puddle.lastWetAt or puddle.createdAt or 0
                    if lastWetAt < oldestWetAt then
                        oldestIndex = index
                        oldestWetAt = lastWetAt
                    end
                end
                if oldestIndex then
                    puddles[oldestIndex].removed = true
                    table.remove(puddles, oldestIndex)
                end
            end
            nearestPuddle = {
                position = position,
                normal = trace.HitNormal,
                size = width,
                createdAt = now,
                lastWetAt = now,
                expiresAt = now + puddleLifetime,
                rippleOffset = math.Rand(0, 2.4),
                wetSeconds = 0,
                spread = 1,
                maxSpread = measurePuddleMaxSpread(trace, width, player),
                lobes = {},
                removed = false
            }
            puddles[#puddles + 1] = nearestPuddle
        else
            nearestPuddle.expiresAt = now + puddleLifetime
            nearestPuddle.lastWetAt = now
            nearestPuddle.size = math.min(240, nearestPuddle.size + width * 0.1)
            if position.z < nearestPuddle.position.z - 2 then
                nearestPuddle.position = position
                nearestPuddle.normal = trace.HitNormal
            end
        end

        site.puddle = nearestPuddle
        local nearestLobe
        local nearestLobeDistance = math.huge
        for _, lobe in ipairs(nearestPuddle.lobes) do
            lobe.targetWidth = lobe.targetWidth or lobe.width or width
            lobe.targetHeight = lobe.targetHeight or lobe.height or width * 0.8
            local dx = position.x - lobe.position.x
            local dy = position.y - lobe.position.y
            local distance = dx * dx + dy * dy
            if distance < nearestLobeDistance then
                nearestLobe = lobe
                nearestLobeDistance = distance
            end
        end

        local mergeLobeDistance = nearestLobe and (nearestLobe.targetWidth + width) * 0.55 or 0
        if nearestLobe and nearestLobeDistance <= mergeLobeDistance * mergeLobeDistance then
            nearestLobe.targetWidth = math.min(184, nearestLobe.targetWidth + width * 0.12)
            nearestLobe.targetHeight = math.min(164, nearestLobe.targetHeight + width * 0.09)
        elseif #nearestPuddle.lobes < maxPuddleLobes then
            local lobe = createPuddleLobe(trace, width, now)
            local spread = nearestPuddle.spread or 1
            local z = lobe.position.z
            lobe.position = nearestPuddle.position + (lobe.position - nearestPuddle.position) / spread
            lobe.position.z = z
            nearestPuddle.lobes[#nearestPuddle.lobes + 1] = lobe
        end
    end

    function Puddles.UpdateWetPuddles()
        local now = CurTime()
        local dryAt = Atmosphere.PuddlesDryAt
        local elapsed = math.Clamp(now - (Atmosphere.PuddleGrowthAt or now), 0, 1)
        Atmosphere.PuddleGrowthAt = now
        local raining = Atmosphere.Weather == "rain" and not dryAt
        for index = #puddles, 1, -1 do
            local puddle = puddles[index]
            if now >= puddle.expiresAt or (dryAt and now >= dryAt) then
                puddle.removed = true
                table.remove(puddles, index)
            elseif raining then
                puddle.wetSeconds = (puddle.wetSeconds or 0) + elapsed
                local maturity = math.Clamp(puddle.wetSeconds / puddleMatureSeconds, 0, 1)
                maturity = maturity * maturity * (3 - 2 * maturity)
                puddle.spread = 1 + ((puddle.maxSpread or 1) - 1) * maturity
            end
        end

        local clusterLimit = Puddles.GetPuddleClusterLimit()
        while #puddles > clusterLimit do
            local oldestIndex = 1
            local oldestWetAt = math.huge
            for index, puddle in ipairs(puddles) do
                if (puddle.lastWetAt or 0) < oldestWetAt then
                    oldestIndex = index
                    oldestWetAt = puddle.lastWetAt or 0
                end
            end
            puddles[oldestIndex].removed = true
            table.remove(puddles, oldestIndex)
        end

        if not raining then
            Puddles.PuddleSiteDebt = 0
            return
        end
        if now >= Puddles.NextPuddleAt then
            Puddles.NextPuddleAt = now + puddleSiteInterval
            if not Environment.HasOutdoorCityCells() or not Environment.EnsureSurfaceSites() then
                Puddles.PuddleSiteDebt = 0
                return
            end
            // Visit every active site about once per 35 seconds, well inside the 60-second puddle lifetime.
            // Each tick's sites become debt that is paid off within the shared frame budget instead of in one burst.
            local activeSites = Puddles.GetActivePuddleSiteCount()
            Puddles.PuddleSiteDebt = math.min(Puddles.PuddleSiteDebt + math.ceil(activeSites / puddleSiteCycleTicks), activeSites)
        end
        if Puddles.PuddleSiteDebt <= 0 then return end

        local activeSites = Puddles.GetActivePuddleSiteCount()
        if activeSites <= 0 then
            Puddles.PuddleSiteDebt = 0
            return
        end
        local deadline = Environment.GetAtmosphereWorkDeadline()
        local player = LocalPlayer()
        while Puddles.PuddleSiteDebt > 0 do
            if Puddles.PuddleSiteCursor > activeSites then Puddles.PuddleSiteCursor = 1 end
            local site = Environment.SurfaceSites[Puddles.PuddleSiteCursor]
            Puddles.PuddleSiteCursor = Puddles.PuddleSiteCursor % activeSites + 1
            Puddles.PuddleSiteDebt = Puddles.PuddleSiteDebt - 1
            if site and not site.unusable then
                addWetPuddle(site, player, now)
            end
            if SysTime() >= deadline then break end
        end
        Atmosphere.PuddleSiteCursor = Puddles.PuddleSiteCursor
    end

    function Puddles.FindPuddleAt(position)
        local now = CurTime()
        local dryAt = Atmosphere.PuddlesDryAt
        local fade = dryAt and math.Clamp((dryAt - now) / 3, 0, 1) or 1
        if fade <= 0.15 then return nil end
        for _, puddle in ipairs(puddles) do
            if not puddle.removed and math.abs(position.z - puddle.position.z) <= 24 then
                local spread = (puddle.spread or 1) * (0.7 + 0.3 * fade)
                for _, lobe in ipairs(puddle.lobes) do
                    local center = puddle.position + (lobe.position - puddle.position) * spread
                    local radius = 0.25 * ((lobe.width or 0) + (lobe.height or 0)) * spread
                    local dx = position.x - center.x
                    local dy = position.y - center.y
                    if radius > 4 and dx * dx + dy * dy <= radius * radius then
                        return puddle
                    end
                end
            end
        end
        return nil
    end

    // Per-frame puddle render scratch lives in one table to stay under the chunk's local-variable limit.
    local puddleRender = {}
    // Candidate records, selection lists and per-lobe render centres are reused; results only live for one frame.
    puddleRender.candidatePool = {}
    puddleRender.candidates = {}
    puddleRender.selected = {}
    puddleRender.selectedClusters = {}

    local function comparePuddleCandidates(left, right)
        return left.distance < right.distance
    end

    local function getVisiblePuddleLobes(now)
        local candidates, selected, selectedClusters = puddleRender.candidates, puddleRender.selected, puddleRender.selectedClusters
        for index = #candidates, 1, -1 do candidates[index] = nil end
        for index = #selected, 1, -1 do selected[index] = nil end
        for key in pairs(selectedClusters) do selectedClusters[key] = nil end
        if #puddles == 0 or not Puddles.PuddleMaterial then return selected, 0 end

        local cameraPosition = EyePos()
        local viewDirection = EyeVector()
        local cameraX, cameraY, cameraZ = cameraPosition.x, cameraPosition.y, cameraPosition.z
        local viewX, viewY, viewZ = viewDirection.x, viewDirection.y, viewDirection.z
        for _, puddle in ipairs(puddles) do
            if not puddle.removed then
                local fade = 1
                if Atmosphere.PuddlesDryAt then
                    fade = math.Clamp((Atmosphere.PuddlesDryAt - now) / 3, 0, 1)
                elseif puddle.expiresAt - now < 4 then
                    fade = math.Clamp((puddle.expiresAt - now) / 4, 0, 1)
                end
                if fade > 0 then
                    // Drying pools contract toward their centre as they fade.
                    local spread = (puddle.spread or 1) * (0.7 + 0.3 * fade)
                    for _, lobe in ipairs(puddle.lobes) do
                        if not lobe.smoothEdges then
                            lobe.smoothEdges = true
                            lobe.edgeFactors = createPuddleEdgeFactors()
                            lobe.targetWidth = lobe.targetWidth or lobe.width
                            lobe.targetHeight = lobe.targetHeight or lobe.height
                            lobe.createdAt = lobe.createdAt or now - 1.25
                        end

                        local origin, lobePosition = puddle.position, lobe.position
                        local centerX = origin.x + (lobePosition.x - origin.x) * spread
                        local centerY = origin.y + (lobePosition.y - origin.y) * spread
                        local centerZ = lobePosition.z
                        local radius = math.max(lobe.targetWidth or 0, lobe.targetHeight or 0) * 0.6 * spread
                        local dx, dy, dz = centerX - cameraX, centerY - cameraY, centerZ - cameraZ
                        if dx * viewX + dy * viewY + dz * viewZ > -radius then
                            local center = lobe.renderCenter
                            if not center then
                                center = Vector()
                                lobe.renderCenter = center
                            end
                            center:SetUnpacked(centerX, centerY, centerZ)
                            local candidateIndex = #candidates + 1
                            local candidate = puddleRender.candidatePool[candidateIndex]
                            if not candidate then
                                candidate = {}
                                puddleRender.candidatePool[candidateIndex] = candidate
                            end
                            candidate.puddle = puddle
                            candidate.lobe = lobe
                            candidate.fade = fade
                            candidate.center = center
                            candidate.spread = spread
                            candidate.distance = dx * dx + dy * dy + dz * dz
                            candidates[candidateIndex] = candidate
                        end
                    end
                end
            end
        end

        table.sort(candidates, comparePuddleCandidates)
        local clusterCount = 0
        local clusterLimit = Puddles.GetVisiblePuddleClusterLimit()
        local lobeLimit = Puddles.GetVisiblePuddleLobeLimit()
        for _, candidate in ipairs(candidates) do
            if not selectedClusters[candidate.puddle] then
                if clusterCount >= clusterLimit then break end
                selectedClusters[candidate.puddle] = true
                clusterCount = clusterCount + 1
            end
            selected[#selected + 1] = candidate
            if #selected >= lobeLimit then break end
        end
        return selected, clusterCount
    end

    local puddleUpNormal = Vector(0, 0, 1)
    puddleRender.tangent = Vector()
    puddleRender.bitangent = Vector()
    // Shapes and their ring vertices are pooled; they only live for the frame that builds them.
    puddleRender.shapePool = {}
    puddleRender.shapes = {}

    local function buildPuddleGeometry(candidates, now, opacity)
        local shapes = puddleRender.shapes
        for index = #shapes, 1, -1 do shapes[index] = nil end
        local tangent, bitangent = puddleRender.tangent, puddleRender.bitangent
        for _, candidate in ipairs(candidates) do
            local lobe = candidate.lobe
            local normal = lobe.normal or puddleUpNormal
            local nx, ny, nz = normal.x, normal.y, normal.z
            tangent:SetUnpacked(1 - nx * nx, -ny * nx, -nz * nx)
            if tangent:LengthSqr() < 0.01 then
                tangent:SetUnpacked(-nx * ny, 1 - ny * ny, -nz * ny)
            end
            tangent:Normalize()
            local tx, ty, tz = tangent.x, tangent.y, tangent.z
            bitangent:SetUnpacked(ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx)
            bitangent:Normalize()
            local bx, by, bz = bitangent.x, bitangent.y, bitangent.z

            local progress = math.Clamp((now - (lobe.createdAt or now - 1.25)) / 1.25, 0, 1)
            local growth = progress * progress * (3 - 2 * progress)
            local resize = math.Clamp(FrameTime() * 3, 0, 1)
            lobe.width = Lerp(resize, lobe.width or lobe.targetWidth, lobe.targetWidth or lobe.width)
            lobe.height = Lerp(resize, lobe.height or lobe.targetHeight, lobe.targetHeight or lobe.height)
            local spread = candidate.spread or 1
            local center = candidate.center or lobe.position
            local width = lobe.width * growth * spread
            local height = lobe.height * growth * spread
            local alpha = math.Clamp(255 * math.min(opacity * 3.5, 0.85) * lobe.opacityScale * candidate.fade * growth, 0, 220)
            local shapeIndex = #shapes + 1
            local shape = puddleRender.shapePool[shapeIndex]
            if not shape then
                shape = { inner = {}, outer = {} }
                puddleRender.shapePool[shapeIndex] = shape
            end
            local inner, outer = shape.inner, shape.outer
            local cx, cy, cz = center.x, center.y, center.z
            for segment = 1, Puddles.PuddleMeshSegments do
                local angle = math.rad((segment - 1) * 360 / Puddles.PuddleMeshSegments + lobe.rotation)
                local edgeFactor = lobe.edgeFactors[segment] or 1
                local along = math.cos(angle) * edgeFactor * width * 0.5
                local across = math.sin(angle) * edgeFactor * height * 0.5
                local ox = tx * along + bx * across
                local oy = ty * along + by * across
                local oz = tz * along + bz * across
                local innerPoint, outerPoint = inner[segment], outer[segment]
                if not innerPoint then
                    innerPoint, outerPoint = Vector(), Vector()
                    inner[segment], outer[segment] = innerPoint, outerPoint
                end
                innerPoint:SetUnpacked(cx + ox * 0.7, cy + oy * 0.7, cz + oz * 0.7)
                outerPoint:SetUnpacked(cx + ox, cy + oy, cz + oz)
            end
            shape.center = center
            shape.normal = normal
            shape.step = (candidate.distance or 0) > puddleMeshLodDistanceSqr and 2 or 1
            shape.alpha = alpha
            shape.reflectAlpha = nil
            shapes[shapeIndex] = shape
        end
        return shapes
    end

    local puddleWetColor = { 6, 8, 10 }
    local puddleSheenColor = { 58, 66, 78 }
    local puddleReflectionColor = { 255, 255, 255 }

    local function drawPuddlePass(shapes, material, color, alphaScale, alphaKey)
        if #shapes == 0 then return end
        render.SetMaterial(material)
        local segments = Puddles.PuddleMeshSegments
        local segmentCount = 0
        for _, shape in ipairs(shapes) do
            segmentCount = segmentCount + math.ceil(segments / shape.step)
        end
        local position, normalFn, texCoord, vertexColor, advance = mesh.Position, mesh.Normal, mesh.TexCoord, mesh.Color, mesh.AdvanceVertex
        // Solid centre fan as triangles, then the feathered rim as quads. Source splits a quad (0,1,2)/(0,2,3),
        // so innerA, outerA, outerB, innerB reproduces the former two rim triangles with 4 vertices instead of 6.
        mesh.Begin(MATERIAL_TRIANGLES, segmentCount)
        for _, shape in ipairs(shapes) do
            local step = shape.step
            local alpha = (shape[alphaKey or "alpha"] or shape.alpha) * alphaScale
            local shapeColor = color or shape.color
            local red, green, blue = shapeColor[1], shapeColor[2], shapeColor[3]
            local center, normal, inner = shape.center, shape.normal, shape.inner
            for segment = 1, segments, step do
                local nextSegment = (segment + step - 1) % segments + 1
                position(center) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
                position(inner[segment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
                position(inner[nextSegment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
            end
        end
        mesh.End()
        mesh.Begin(MATERIAL_QUADS, segmentCount)
        for _, shape in ipairs(shapes) do
            local step = shape.step
            local alpha = (shape[alphaKey or "alpha"] or shape.alpha) * alphaScale
            local shapeColor = color or shape.color
            local red, green, blue = shapeColor[1], shapeColor[2], shapeColor[3]
            local normal, inner, outer = shape.normal, shape.inner, shape.outer
            for segment = 1, segments, step do
                local nextSegment = (segment + step - 1) % segments + 1
                position(inner[segment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
                position(outer[segment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, 0) advance()
                position(outer[nextSegment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, 0) advance()
                position(inner[nextSegment]) normalFn(normal) texCoord(0, 0.5, 0.5) vertexColor(red, green, blue, alpha) advance()
            end
        end
        mesh.End()
    end

    local function drawPuddleMesh(candidates, now, opacity)
        if #candidates == 0 or not Puddles.PuddleMaterial then return end

        local shapes = buildPuddleGeometry(candidates, now, opacity)
        drawPuddlePass(shapes, Puddles.PuddleMaterial, puddleWetColor, 1)
        if not Puddles.PuddleReflectionMaterial then
            drawPuddlePass(shapes, puddleSheenMaterial, puddleSheenColor, 0.55)
            return
        end

        // Schlick-style Fresnel: shallow viewing angles reflect strongly, looking straight down mostly shows the wet ground.
        local eye = EyePos()
        local ex, ey, ez = eye.x, eye.y, eye.z
        for _, shape in ipairs(shapes) do
            local center, normal = shape.center, shape.normal
            local dx, dy, dz = ex - center.x, ey - center.y, ez - center.z
            local length = math.sqrt(dx * dx + dy * dy + dz * dz)
            local facing = 0
            if length > 0 then
                facing = math.Clamp(math.abs((dx * normal.x + dy * normal.y + dz * normal.z) / length), 0, 1)
            end
            local fresnel = 0.2 + 0.8 * (1 - facing) ^ 3
            shape.reflectAlpha = shape.alpha * fresnel
        end
        drawPuddlePass(shapes, Puddles.PuddleReflectionMaterial, puddleReflectionColor, 1, "reflectAlpha")
    end

    local puddleDropLifetime = 0.32
    local maxPuddleDropRings = 240
    local maxPuddleDropCrowns = 40
    local puddleDropCrownDistance = 500
    local puddleDropBeamMaterial = Material("particle/particledefault")
    Atmosphere.PuddleImpactMaxIndices = maxPuddleDropRings * 6

    local function hashUnit(first, second)
        local value = math.sin(first * 12.9898 + second * 78.233) * 43758.5453
        return value - math.floor(value)
    end

    puddleRender.ringPosition = Vector()
    puddleRender.ringQuadCorners = { { -1, -1, 0, 0 }, { 1, -1, 1, 0 }, { 1, 1, 1, 1 }, { -1, 1, 0, 1 } }
    puddleRender.EmitRingQuad = function(center, normal, tangent, bitangent, size, red, green, blue, alpha)
        local half = size * 0.5
        local position = puddleRender.ringPosition
        local cx, cy, cz = center.x, center.y, center.z
        local rx, ry, rz = tangent.x * half, tangent.y * half, tangent.z * half
        local ux, uy, uz = bitangent.x * half, bitangent.y * half, bitangent.z * half
        for index = 1, 4 do
            local corner = puddleRender.ringQuadCorners[index]
            local sx, sy = corner[1], corner[2]
            position:SetUnpacked(cx + rx * sx + ux * sy, cy + ry * sx + uy * sy, cz + rz * sx + uz * sy)
            mesh.Position(position)
            mesh.Normal(normal)
            mesh.TexCoord(0, corner[3], corner[4])
            mesh.Color(red, green, blue, alpha)
            mesh.AdvanceVertex()
        end
    end

    // Drop records are pooled across frames; each frame overwrites the first #drops entries.
    puddleRender.dropPool = {}
    puddleRender.drops = {}
    puddleRender.dropTangent = Vector()
    puddleRender.dropBitangent = Vector()
    puddleRender.crownEnd = Vector()
    puddleRender.crownColor = Color(200, 215, 225, 0)

    // Each lobe owns deterministic drop slots; every slot re-rolls its impact point each cycle,
    // so the count scales with rain density and puddle area without allocating per-drop state.
    local function drawPuddleRainImpacts(candidates, now)
        if #candidates == 0 then
            Atmosphere.PuddleDropRings = 0
            Atmosphere.PuddleDropCrowns = 0
            Atmosphere.PuddleImpactQuads = 0
            return
        end

        local density = math.Clamp(Weather.RainDensityConVar:GetFloat(), 0.5, 2)
        local rippleAmount = Atmosphere.GetQualityNumber("rippleAmount", 1, 0.1, 1)
        local maxRings = math.max(1, math.floor(maxPuddleDropRings * rippleAmount))
        local cameraPosition = EyePos()
        local drops = puddleRender.drops
        for index = #drops, 1, -1 do drops[index] = nil end
        for candidateIndex, candidate in ipairs(candidates) do
            local lobe = candidate.lobe
            local spread = candidate.spread or 1
            local width = (lobe.width or 0) * spread
            local height = (lobe.height or 0) * spread
            if width > 4 and height > 4 then
                local area = width * height / (110 * 90)
                local slots = math.Clamp(math.Round(6 * density * rippleAmount * area * candidate.fade), 1, 30)
                local seed = (lobe.rotation or candidateIndex) * 1.37
                local normal = lobe.normal or puddleUpNormal
                local center = candidate.center
                for slot = 1, slots do
                    local offset = hashUnit(seed, slot) * puddleDropLifetime
                    local cycle = math.floor((now + offset) / puddleDropLifetime)
                    local phase = ((now + offset) % puddleDropLifetime) / puddleDropLifetime
                    local angle = hashUnit(cycle + seed, slot * 3.1) * math.pi * 2
                    local radius = math.sqrt(hashUnit(slot * 1.7, cycle + seed * 0.5)) * 0.42
                    local dropIndex = #drops + 1
                    local drop = puddleRender.dropPool[dropIndex]
                    if not drop then
                        drop = { position = Vector() }
                        puddleRender.dropPool[dropIndex] = drop
                    end
                    drop.position:SetUnpacked(
                        center.x + math.cos(angle) * width * radius + normal.x * 1.1,
                        center.y + math.sin(angle) * height * radius + normal.y * 1.1,
                        center.z + normal.z * 1.1
                    )
                    drop.normal = normal
                    drop.phase = phase
                    drop.weight = 0.6 + hashUnit(cycle, slot + seed) * 0.6
                    drop.fade = candidate.fade
                    drops[dropIndex] = drop
                    if #drops >= maxRings then break end
                end
            end
            if #drops >= maxRings then break end
        end

        if #drops == 0 then
            Atmosphere.PuddleDropRings = 0
            Atmosphere.PuddleDropCrowns = 0
            Atmosphere.PuddleImpactQuads = 0
            return
        end

        // One quad per drop: at the 240-drop cap this uses only 1,440 indices.
        if not Puddles.SplashRingMaterial:IsError() then
            render.SetMaterial(Puddles.SplashRingMaterial)
            mesh.Begin(MATERIAL_QUADS, #drops)
            for _, drop in ipairs(drops) do
                local normal = drop.normal
                local nx, ny, nz = normal.x, normal.y, normal.z
                local tangent, bitangent = puddleRender.dropTangent, puddleRender.dropBitangent
                tangent:SetUnpacked(1 - nx * nx, -ny * nx, -nz * nx)
                if tangent:LengthSqr() < 0.01 then
                    tangent:SetUnpacked(-nx * ny, 1 - ny * ny, -nz * ny)
                end
                tangent:Normalize()
                local tx, ty, tz = tangent.x, tangent.y, tangent.z
                bitangent:SetUnpacked(ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx)
                local inverse = 1 - drop.phase
                local growth = 1 - inverse * inverse
                local size = (2 + growth * 9) * drop.weight
                local alpha = 72 * inverse * math.sqrt(inverse) * drop.fade
                puddleRender.EmitRingQuad(drop.position, normal, tangent, bitangent, size, 168, 188, 198, alpha)
            end
            mesh.End()
            Atmosphere.PuddleImpactQuads = #drops
        else
            Atmosphere.PuddleImpactQuads = 0
        end

        // Nearby drops throw a tiny upward fleck at the moment of impact.
        local crowns = 0
        render.SetMaterial(puddleDropBeamMaterial)
        local crownDistance = puddleDropCrownDistance * puddleDropCrownDistance
        for _, drop in ipairs(drops) do
            if crowns >= maxPuddleDropCrowns then break end
            if drop.phase < 0.18 and drop.position:DistToSqr(cameraPosition) < crownDistance then
                crowns = crowns + 1
                local progress = drop.phase / 0.18
                local lift = math.sin(progress * math.pi) * 4 * drop.weight
                local position, normal = drop.position, drop.normal
                local length = 1 + lift
                puddleRender.crownEnd:SetUnpacked(position.x + normal.x * length, position.y + normal.y * length, position.z + normal.z * length)
                puddleRender.crownColor.a = 110 * (1 - progress) * drop.fade
                render.DrawBeam(position, puddleRender.crownEnd, 0.6, 0, 1, puddleRender.crownColor)
            end
        end
        Atmosphere.PuddleDropRings = #drops
        Atmosphere.PuddleDropCrowns = crowns
    end

    function Puddles.Reset()
        Puddles.ResetSites()
        Puddles.NextPuddleAt = 0
        Puddles.PuddleSiteDebt = 0
        Atmosphere.PuddleSiteCursor = Puddles.PuddleSiteCursor
        Atmosphere.PuddleRenderLobes = 0
        Atmosphere.PuddleRenderClusters = 0
        Atmosphere.PuddlesDryAt = nil
    end

    function Puddles.ResetSites()
        table.Empty(puddles)
        Puddles.PuddleSiteCursor = 1
        Atmosphere.PuddleSiteCursor = Puddles.PuddleSiteCursor
    end

    function Modules.Puddles.RegisterHooks()
        hook.Add("PostDrawTranslucentRenderables", "ZM.Atmosphere.WetSurfaceEffects", function(drawingDepth, drawingSkybox)
            if drawingDepth or drawingSkybox or ZM_WorldMap and ZM_WorldMap.Capturing then return end

            local now = CurTime()
            local puddleOpacity = math.Clamp(Puddles.PuddleOpacityConVar:GetFloat(), 0.05, 0.45)
            local visiblePuddles, visiblePuddleClusters = getVisiblePuddleLobes(now)
            Atmosphere.PuddleRenderLobes = #visiblePuddles
            Atmosphere.PuddleRenderClusters = visiblePuddleClusters
            drawPuddleMesh(visiblePuddles, now, puddleOpacity)

            if Atmosphere.Weather == "rain" and not Atmosphere.PuddlesDryAt then
                drawPuddleRainImpacts(visiblePuddles, now)
            else
                Atmosphere.PuddleDropRings = 0
                Atmosphere.PuddleDropCrowns = 0
                Atmosphere.PuddleImpactQuads = 0
            end
            Footsteps.DrawSplashes(now, Puddles.SplashRingMaterial)
        end)
    end
end
