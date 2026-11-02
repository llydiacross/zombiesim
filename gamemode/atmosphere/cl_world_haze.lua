// In-world edge haze and ground mist for the layered fog style. Static translucent curtains stand in the band between
// the traversable edge and the world/3D-skybox seam on every side, so the seam and the end of the level dissolve into
// distance haze; low mist sprites drift near the ground around the player for depth. Both use the gentle layered fog
// colour, thicken with weather and current-cell radiation, and fade out as the player walks toward a side.
return function(Atmosphere, Modules)
    local Core = Modules.Core
    local Environment = Modules.Environment
    local WorldHaze = Modules.WorldHaze

    local meshVersion = 3
    local sides = { "N", "E", "S", "W" }
    // Outward normal per side in Hammer space (grid north is +Y).
    local sideAxes = { N = { 0, 1 }, E = { 1, 0 }, S = { 0, -1 }, W = { -1, 0 } }
    // Curtain positions are fractions of the band between the traversable edge and the side's visual extent.
    local tiers = {
        low = { curtains = { 0.45, 0.9 }, columns = 16, mist = 20, ash = 60, embers = 12 },
        high = { curtains = { 0.2, 0.55, 0.9 }, columns = 32, mist = 64, ash = 160, embers = 36 }
    }
    local minimumBand = 320
    // Curtains zigzag in small pleats, so no curtain segment is axis-aligned and none can lie in the plane of a
    // brush face; a coplanar curtain z-fights with that face as a flickering striped patch.
    local curtainWaveAmplitude, curtainGridOffset, curtainEdgeMargin = 20, 5.5, 24
    local curtainBase = -32
    local curtainHeight = 1200
    // Height fraction and alpha factor per row: dense at the ground, gone at the top.
    local rows = { { 0, 1 }, { 0.35, 0.7 }, { 0.7, 0.25 }, { 1, 0 } }
    // Combined ground-level opacity of a full curtain stack before weather/density scaling.
    local stackOpacity = 0.82
    local nearFadeStart, nearFadeLength = 300, 900
    local mistRingInner, mistRingOuter, mistCullDistance = 300, 1500, 1900
    local mistNearStart, mistNearEnd, mistFarStart, mistFarEnd = 250, 600, 1400, 1800
    local mistOpacity = 0.5
    local mistHalfWidth, mistHeight = 240, 150
    local mistFadeIn, mistFadeOut = 2, 3
    local mistSeedsPerFrame = 2
    // Radiated cells push the mist toward smoky red-brown dust matching the burning sky.
    local mistDustColor = { 165, 90, 50 }
    local mistDustWeight = 0.5
    // Radiation adds this fraction on top of the weather haze density.
    local radiationHazeBoost = 0.5
    local densityEaseSeconds = 3
    // Fallout ash: small flakes falling around the player in radiated cells; count scales with radiation.
    local ashRadius, ashCullRadius = 800, 1000
    local ashSpawnLow, ashSpawnHigh, ashFloor = 100, 400, 150
    local ashFallMin, ashFallMax = 30, 60
    local ashSizeMin, ashSizeMax = 3, 6
    local ashColor = { 90, 85, 75 }
    local ashOpacity = 0.85
    local ashFadeIn = 1
    local ashSeedsPerFrame = 4
    local ashMinimumRadiation = 0.02
    // Fire embers: glowing sparks rising and swirling through radiated cells, as if from fires nearby.
    local emberRadius, emberCullRadius = 700, 900
    local emberSpawnLow, emberSpawnHigh, emberCeiling = -60, 80, 500
    local emberRiseMin, emberRiseMax = 18, 45
    local emberSizeMin, emberSizeMax = 2.5, 5
    local emberColor = { 255, 130, 45 }
    local emberFadeIn, emberFadeOut = 0.8, 1.5
    local emberSeedsPerFrame = 2

    local densityConVar = CreateClientConVar("zombiesim_world_haze_density", "1", true, false,
        "In-world edge haze and ground mist density multiplier (0 to 2).")

    local function createMaterial(name, texture)
        return CreateMaterial(name, "UnlitGeneric", {
            ["$basetexture"] = texture,
            ["$vertexcolor"] = 1,
            ["$vertexalpha"] = 1,
            ["$translucent"] = 1,
            ["$nocull"] = 1,
            ["$nofog"] = 1
        })
    end
    // One material per side so each side's $alpha is independent within a frame.
    local curtainMaterials = {}
    for _, side in ipairs(sides) do
        curtainMaterials[side] = createMaterial("zombiesim_world_haze_" .. side .. "_v" .. meshVersion, "vgui/white")
    end
    local mistMaterial = createMaterial("zombiesim_world_mist_v" .. meshVersion, "particle/particle_smokegrenade")
    local ashMaterial = createMaterial("zombiesim_world_ash_v" .. meshVersion, "particle/particle_smokegrenade")
    local emberMaterial = CreateMaterial("zombiesim_world_ember_v" .. meshVersion, "UnlitGeneric", {
        ["$basetexture"] = "sprites/light_glow02",
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$additive"] = 1,
        ["$nocull"] = 1,
        ["$nofog"] = 1
    })
    WorldHaze.CurtainMaterials = curtainMaterials
    WorldHaze.MistMaterial = mistMaterial
    WorldHaze.AshMaterial = ashMaterial
    WorldHaze.EmberMaterial = emberMaterial
    WorldHaze.Meshes = WorldHaze.Meshes or {}
    WorldHaze.Sprites = WorldHaze.Sprites or {}
    WorldHaze.Ash = WorldHaze.Ash or {}
    WorldHaze.Embers = WorldHaze.Embers or {}
    WorldHaze.Stats = WorldHaze.Stats or {}
    WorldHaze.SideFade = WorldHaze.SideFade or {}
    local curtainColor = Vector(1, 1, 1)
    local mistColor = {}

    // zombiesim_world_haze is owned by cl_quality.lua with the other preset-controlled settings.
    function WorldHaze.GetTier()
        local value = Atmosphere.GetQualityNumber("worldHaze", 1, 0, 1)
        if value <= 0 then return nil end
        return value < 0.75 and "low" or "high"
    end

    function WorldHaze.GetInactiveReason(player)
        if Atmosphere:GetFogStyle() ~= "layered" then return "legacy fog style" end
        if not WorldHaze.GetTier() then return "disabled" end
        if Atmosphere.WorldCaptureFogVariant ~= nil or Atmosphere.MapCaptureParticlesHidden
            or ZM_WorldMap and ZM_WorldMap.Capturing then
            return "map capture"
        end
        if ZM_PrefabEditorClient and ZM_PrefabEditorClient:IsActive() then return "prefab editor" end
        if ZM_LauncherMenu and ZM_LauncherMenu.Active then return "launcher menu active" end
        if not IsValid(player) or not Environment.IsOutdoorCityCell(player) then return "not an outdoor city cell" end
        if not Atmosphere:GetFogSettings() then return "no active profile" end
        return nil
    end

    function WorldHaze.DestroyMeshes()
        for side, imesh in pairs(WorldHaze.Meshes) do
            imesh:Destroy()
            WorldHaze.Meshes[side] = nil
        end
        WorldHaze.MeshKey = nil
    end

    function WorldHaze.Reset()
        WorldHaze.DestroyMeshes()
        table.Empty(WorldHaze.Sprites)
        table.Empty(WorldHaze.Ash)
        WorldHaze.Active = false
        WorldHaze.Density = nil
        WorldHaze.DensityTime = nil
    end

    local function columnVariation(index, curtain, side)
        return 0.8 + 0.2 * math.sin(index * 0.9 + curtain * 1.7 + side * 2.3) * math.cos(index * 0.37 - curtain * 0.6)
    end

    // Builds one static mesh per side in world space, outermost curtain first so each mesh draws back to front.
    function WorldHaze.BuildCurtains(cell, tierName)
        local bounds = ZM_World:GetCellBounds()
        local traversable = bounds.traversableHalfExtent or 2240
        local extents = {}
        local spanHalf = 0
        for _, side in ipairs(sides) do
            local extent = cell and ZM_World:GetCellSideExtent(cell, side) or bounds.visualHalfExtent
            extents[side] = math.max(tonumber(extent) or traversable, traversable + minimumBand)
            spanHalf = math.max(spanHalf, extents[side])
        end
        local key = table.concat({ meshVersion, tierName, traversable, extents.N, extents.E, extents.S, extents.W }, ":")
        if key == WorldHaze.MeshKey and WorldHaze.Meshes.N then return true end
        WorldHaze.DestroyMeshes()
        WorldHaze.MeshKey = key
        local tier = tiers[tierName]
        local curtainCount, columns = #tier.curtains, tier.columns
        local quads = curtainCount * columns * (#rows - 1)
        local stats = WorldHaze.Stats
        stats.curtainQuads = quads * #sides
        stats.curtains = curtainCount
        stats.columns = columns
        if quads <= 0 then return false end
        // Each curtain supplies an equal share of the stack opacity, so tiers differ in smoothness, not strength.
        local curtainAlpha = 1 - (1 - stackOpacity) ^ (1 / curtainCount)
        local position = Vector()
        for sideIndex, side in ipairs(sides) do
            local axis = sideAxes[side]
            local ax, ay = axis[1], axis[2]
            local px, py = -ay, ax
            local band = extents[side] - traversable
            // Column positions and alphas are computed before mesh.Begin so nothing can error inside it.
            local layout = {}
            for curtain = curtainCount, 1, -1 do
                local base = traversable + band * tier.curtains[curtain] + curtainGridOffset
                local points = {}
                for column = 0, columns do
                    local along = -spanHalf + column / columns * spanHalf * 2
                    // Alternating pleats guarantee every segment slants by at least 0.8 x amplitude.
                    local pleat = (column % 2 == 0 and 1 or -1)
                        * (0.7 + 0.3 * math.sin(column * 1.3 + curtain * 2.1 + sideIndex * 0.7))
                    local distance = math.Clamp(base + curtainWaveAmplitude * pleat,
                        traversable + curtainEdgeMargin, extents[side] - curtainEdgeMargin)
                    points[column] = {
                        x = ax * distance + px * along,
                        y = ay * distance + py * along,
                        a = math.Clamp(curtainAlpha * columnVariation(column, curtain, sideIndex), 0, 1) * 255
                    }
                end
                layout[#layout + 1] = points
            end
            local imesh = Mesh()
            mesh.Begin(imesh, MATERIAL_QUADS, quads)
            for _, points in ipairs(layout) do
                for column = 0, columns - 1 do
                    local a, b = points[column], points[column + 1]
                    for row = 1, #rows - 1 do
                        local low, high = rows[row], rows[row + 1]
                        local lowZ = curtainBase + low[1] * curtainHeight
                        local highZ = curtainBase + high[1] * curtainHeight
                        position:SetUnpacked(a.x, a.y, lowZ)
                        mesh.Position(position) mesh.Color(255, 255, 255, a.a * low[2]) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
                        position:SetUnpacked(b.x, b.y, lowZ)
                        mesh.Position(position) mesh.Color(255, 255, 255, b.a * low[2]) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
                        position:SetUnpacked(b.x, b.y, highZ)
                        mesh.Position(position) mesh.Color(255, 255, 255, b.a * high[2]) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
                        position:SetUnpacked(a.x, a.y, highZ)
                        mesh.Position(position) mesh.Color(255, 255, 255, a.a * high[2]) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
                    end
                end
            end
            mesh.End()
            WorldHaze.Meshes[side] = imesh
            WorldHaze.SideFade[side] = WorldHaze.SideFade[side] or 0
            stats["inner" .. side] = traversable + band * tier.curtains[1]
        end
        stats.builds = (stats.builds or 0) + 1
        return true
    end

    // Weather and radiation set how thick the haze is; eased exponentially so changes roll in rather than snap.
    function WorldHaze.UpdateDensity(now, radiation)
        local weather = Atmosphere.Weather or "clear"
        local storm = Atmosphere.StormIntensity or 0
        local multiplier = weather == "rain" and 1.35 or weather == "snow" and 1.2 or 1
        local target = 0.75 * (multiplier + storm * 0.3) * (1 + radiationHazeBoost * math.Clamp(radiation or 0, 0, 1))
        target = math.Clamp(target, 0, 1.6)
        local delta = math.Clamp(now - (WorldHaze.DensityTime or now), 0, 1)
        WorldHaze.DensityTime = now
        if WorldHaze.Density then
            WorldHaze.Density = Lerp(1 - math.exp(-delta / densityEaseSeconds), WorldHaze.Density, target)
        else
            WorldHaze.Density = target
        end
        return WorldHaze.Density
    end

    local traceStart, traceEnd = Vector(), Vector()
    local traceRequest = { start = traceStart, endpos = traceEnd, mask = MASK_SOLID_BRUSHONLY }

    // One candidate per call: on outdoor walkable ground inside the visual bounds, open to the sky above.
    function WorldHaze.TrySeed(origin, limit, now)
        local angle = math.Rand(0, math.pi * 2)
        local radius = math.Rand(mistRingInner, mistRingOuter)
        local x, y = origin.x + math.cos(angle) * radius, origin.y + math.sin(angle) * radius
        local stats = WorldHaze.Stats
        stats.seedAttempts = (stats.seedAttempts or 0) + 1
        if math.abs(x) > limit or math.abs(y) > limit then return false end
        traceStart:SetUnpacked(x, y, origin.z + 160)
        traceEnd:SetUnpacked(x, y, origin.z - 600)
        local down = util.TraceLine(traceRequest)
        if not down or not down.Hit or down.StartSolid or down.HitSky or not down.HitNormal
            or down.HitNormal.z < 0.7 then
            return false
        end
        local ground = down.HitPos
        traceStart:SetUnpacked(ground.x, ground.y, ground.z + 16)
        traceEnd:SetUnpacked(ground.x, ground.y, ground.z + 4096)
        local up = util.TraceLine(traceRequest)
        if up and up.Hit and not up.HitSky then return false end
        local sprites = WorldHaze.Sprites
        sprites[#sprites + 1] = {
            x = ground.x, y = ground.y, z = ground.z + math.Rand(-8, 16),
            size = math.Rand(0.8, 1.3), born = now, dies = now + math.Rand(30, 60),
            driftX = math.Rand(-6, 6), driftY = math.Rand(-6, 6), distance = 0
        }
        stats.seeded = (stats.seeded or 0) + 1
        return true
    end

    function WorldHaze.UpdateMist(origin, tier, now, delta, limit)
        local sprites = WorldHaze.Sprites
        for index = #sprites, 1, -1 do
            local sprite = sprites[index]
            sprite.x = sprite.x + sprite.driftX * delta
            sprite.y = sprite.y + sprite.driftY * delta
            local dx, dy = sprite.x - origin.x, sprite.y - origin.y
            if now >= sprite.dies or dx * dx + dy * dy > mistCullDistance * mistCullDistance
                or math.abs(sprite.x) > limit or math.abs(sprite.y) > limit then
                table.remove(sprites, index)
            end
        end
        // Trim on a tier drop without leaving a hole in the ring all at once.
        while #sprites > tier.mist do table.remove(sprites) end
        for _ = 1, mistSeedsPerFrame do
            if #sprites >= tier.mist then break end
            WorldHaze.TrySeed(origin, limit, now)
        end
    end

    // One flake candidate per call: in open air above the player, with nothing between it and the sky.
    function WorldHaze.TrySeedAsh(eye, now)
        local stats = WorldHaze.Stats
        stats.ashAttempts = (stats.ashAttempts or 0) + 1
        local angle = math.Rand(0, math.pi * 2)
        local radius = ashRadius * math.sqrt(math.Rand(0, 1))
        local x, y = eye.x + math.cos(angle) * radius, eye.y + math.sin(angle) * radius
        local z = eye.z + math.Rand(ashSpawnLow, ashSpawnHigh)
        traceStart:SetUnpacked(x, y, z)
        traceEnd:SetUnpacked(x, y, z + 4096)
        local up = util.TraceLine(traceRequest)
        if not up or up.StartSolid or up.Hit and not up.HitSky then return false end
        local ash = WorldHaze.Ash
        ash[#ash + 1] = {
            x = x, y = y, z = z, born = now, dies = now + math.Rand(10, 20),
            fall = math.Rand(ashFallMin, ashFallMax), size = math.Rand(ashSizeMin, ashSizeMax),
            sway = math.Rand(8, 20), phase = math.Rand(0, math.pi * 2), rate = math.Rand(0.6, 1.4),
            driftX = math.Rand(-10, 10), driftY = math.Rand(-10, 10)
        }
        stats.ashSeeded = (stats.ashSeeded or 0) + 1
        return true
    end

    // Ash only exists in radiated cells; the target count scales with the eased radiation.
    function WorldHaze.UpdateAsh(eye, tier, now, delta, radiation)
        local ash = WorldHaze.Ash
        local target = radiation >= ashMinimumRadiation and math.floor(tier.ash * math.Clamp(radiation, 0, 1) + 0.5) or 0
        WorldHaze.Stats.ashTarget = target
        for index = #ash, 1, -1 do
            local flake = ash[index]
            flake.z = flake.z - flake.fall * delta
            flake.x = flake.x + flake.driftX * delta
            flake.y = flake.y + flake.driftY * delta
            local dx, dy = flake.x - eye.x, flake.y - eye.y
            if now >= flake.dies or flake.z < eye.z - ashFloor or dx * dx + dy * dy > ashCullRadius * ashCullRadius then
                table.remove(ash, index)
            end
        end
        while #ash > target do table.remove(ash) end
        for _ = 1, ashSeedsPerFrame do
            if #ash >= target then break end
            WorldHaze.TrySeedAsh(eye, now)
        end
    end

    // One ember candidate per call: in open air near the player's eye level, with nothing between it and the sky.
    function WorldHaze.TrySeedEmber(eye, now)
        local stats = WorldHaze.Stats
        stats.emberAttempts = (stats.emberAttempts or 0) + 1
        local angle = math.Rand(0, math.pi * 2)
        local radius = emberRadius * math.sqrt(math.Rand(0.05, 1))
        local x, y = eye.x + math.cos(angle) * radius, eye.y + math.sin(angle) * radius
        local z = eye.z + math.Rand(emberSpawnLow, emberSpawnHigh)
        traceStart:SetUnpacked(x, y, z)
        traceEnd:SetUnpacked(x, y, z + 4096)
        local up = util.TraceLine(traceRequest)
        if not up or up.StartSolid or up.Hit and not up.HitSky then return false end
        local embers = WorldHaze.Embers
        embers[#embers + 1] = {
            x = x, y = y, z = z, born = now, dies = now + math.Rand(4, 9),
            rise = math.Rand(emberRiseMin, emberRiseMax), size = math.Rand(emberSizeMin, emberSizeMax),
            swirl = math.Rand(10, 28), phase = math.Rand(0, math.pi * 2), rate = math.Rand(0.8, 2),
            flicker = math.Rand(5, 11), driftX = math.Rand(-14, 14), driftY = math.Rand(-14, 14)
        }
        stats.embersSeeded = (stats.embersSeeded or 0) + 1
        return true
    end

    // Embers share the ash rule: only in radiated cells, target count scaling with the eased radiation.
    function WorldHaze.UpdateEmbers(eye, tier, now, delta, radiation)
        local embers = WorldHaze.Embers
        local target = radiation >= ashMinimumRadiation and math.floor(tier.embers * math.Clamp(radiation, 0, 1) + 0.5) or 0
        WorldHaze.Stats.emberTarget = target
        for index = #embers, 1, -1 do
            local ember = embers[index]
            ember.z = ember.z + ember.rise * delta
            ember.x = ember.x + ember.driftX * delta
            ember.y = ember.y + ember.driftY * delta
            local dx, dy = ember.x - eye.x, ember.y - eye.y
            if now >= ember.dies or ember.z > eye.z + emberCeiling
                or dx * dx + dy * dy > emberCullRadius * emberCullRadius then
                table.remove(embers, index)
            end
        end
        while #embers > target do table.remove(embers) end
        for _ = 1, emberSeedsPerFrame do
            if #embers >= target then break end
            WorldHaze.TrySeedEmber(eye, now)
        end
    end

    function WorldHaze.Update()
        local player = LocalPlayer()
        local reason = WorldHaze.GetInactiveReason(player)
        local stats = WorldHaze.Stats
        stats.reason = reason
        if reason then
            if WorldHaze.Active or #WorldHaze.Sprites > 0 then table.Empty(WorldHaze.Sprites) end
            if #WorldHaze.Ash > 0 then table.Empty(WorldHaze.Ash) end
            if #WorldHaze.Embers > 0 then table.Empty(WorldHaze.Embers) end
            WorldHaze.Active = false
            if reason == "disabled" then WorldHaze.DestroyMeshes() end
            return
        end
        local tierName = WorldHaze.GetTier()
        local expected = Core.GetExpectedCell(player)
        local cell = expected and { x = expected.gridX, y = expected.gridY } or nil
        WorldHaze.Active = WorldHaze.BuildCurtains(cell, tierName)
        stats.tier = tierName
        local now = RealTime()
        local settings = Atmosphere:GetFogSettings()
        local radiation = math.Clamp(settings and settings.radiation or 0, 0, 1)
        WorldHaze.Radiation = radiation
        WorldHaze.UpdateDensity(now, radiation)
        local limit = ZM_World:GetCellBounds().visualHalfExtent or 2880
        local delta = FrameTime()
        WorldHaze.UpdateMist(player:GetPos(), tiers[tierName], now, delta, limit)
        local eye = EyePos()
        WorldHaze.UpdateAsh(eye, tiers[tierName], now, delta, radiation)
        WorldHaze.UpdateEmbers(eye, tiers[tierName], now, delta, radiation)
    end

    local sideOrder = { "N", "E", "S", "W" }
    local sideDistance = {}
    local function farthestSideFirst(first, second) return sideDistance[first] > sideDistance[second] end
    local visibleSprites = {}
    local function farthestSpriteFirst(first, second) return first.distance > second.distance end

    function WorldHaze.DrawCurtains(eye, color, alpha)
        local stats = WorldHaze.Stats
        local fades = WorldHaze.SideFade
        for _, side in ipairs(sides) do
            local axis = sideAxes[side]
            local distance = (stats["inner" .. side] or 0) - (eye.x * axis[1] + eye.y * axis[2])
            sideDistance[side] = distance
            fades[side] = math.Clamp((distance - nearFadeStart) / nearFadeLength, 0, 1)
        end
        table.sort(sideOrder, farthestSideFirst)
        curtainColor:SetUnpacked(color[1] / 255, color[2] / 255, color[3] / 255)
        local drawn = 0
        render.OverrideDepthEnable(true, false)
        for _, side in ipairs(sideOrder) do
            local imesh = WorldHaze.Meshes[side]
            local sideAlpha = math.Clamp(alpha * fades[side], 0, 1)
            if imesh and sideAlpha > 0.002 then
                local material = curtainMaterials[side]
                material:SetVector("$color", curtainColor)
                material:SetFloat("$alpha", sideAlpha)
                render.SetMaterial(material)
                imesh:Draw()
                drawn = drawn + 1
            end
        end
        render.OverrideDepthEnable(false, false)
        return drawn
    end

    function WorldHaze.DrawMist(eye, color, alpha, now)
        local count = 0
        for _, sprite in ipairs(WorldHaze.Sprites) do
            local dx, dy = sprite.x - eye.x, sprite.y - eye.y
            local distance = math.sqrt(dx * dx + dy * dy)
            local near = math.Clamp((distance - mistNearStart) / (mistNearEnd - mistNearStart), 0, 1)
            local far = 1 - math.Clamp((distance - mistFarStart) / (mistFarEnd - mistFarStart), 0, 1)
            local life = math.Clamp((now - sprite.born) / mistFadeIn, 0, 1) * math.Clamp((sprite.dies - now) / mistFadeOut, 0, 1)
            local spriteAlpha = mistOpacity * alpha * near * far * life
            if spriteAlpha > 0.004 then
                sprite.distance = distance
                sprite.alpha = math.min(spriteAlpha, 1) * 255
                count = count + 1
                visibleSprites[count] = sprite
            end
        end
        for index = count + 1, #visibleSprites do visibleSprites[index] = nil end
        WorldHaze.Stats.visibleMist = count
        if count == 0 then return 0 end
        table.sort(visibleSprites, farthestSpriteFirst)
        local right = EyeAngles():Right()
        local rx, ry = right.x, right.y
        local length = math.sqrt(rx * rx + ry * ry)
        if length < 0.001 then rx, ry, length = 1, 0, 1 end
        rx, ry = rx / length, ry / length
        local position = Vector()
        render.SetMaterial(mistMaterial)
        render.OverrideDepthEnable(true, false)
        mesh.Begin(MATERIAL_QUADS, count)
        for index = 1, count do
            local sprite = visibleSprites[index]
            local half, height = mistHalfWidth * sprite.size, mistHeight * sprite.size
            local r, g, b, a = color[1], color[2], color[3], sprite.alpha
            position:SetUnpacked(sprite.x - rx * half, sprite.y - ry * half, sprite.z)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
            position:SetUnpacked(sprite.x + rx * half, sprite.y + ry * half, sprite.z)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
            position:SetUnpacked(sprite.x + rx * half, sprite.y + ry * half, sprite.z + height)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
            position:SetUnpacked(sprite.x - rx * half, sprite.y - ry * half, sprite.z + height)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
        end
        mesh.End()
        render.OverrideDepthEnable(false, false)
        return count
    end

    // Camera-facing flakes in one dynamic mesh; skipped entirely when no flakes exist.
    function WorldHaze.DrawAsh(eye, now)
        local ash = WorldHaze.Ash
        local count = #ash
        if count == 0 then return 0 end
        local angles = EyeAngles()
        local right, up = angles:Right(), angles:Up()
        local position = Vector()
        local r, g, b = ashColor[1], ashColor[2], ashColor[3]
        render.SetMaterial(ashMaterial)
        render.OverrideDepthEnable(true, false)
        mesh.Begin(MATERIAL_QUADS, count)
        for index = 1, count do
            local flake = ash[index]
            local life = math.Clamp((now - flake.born) / ashFadeIn, 0, 1) * math.Clamp(flake.dies - now, 0, 1)
            local a = ashOpacity * life * 255
            local sway = math.sin(now * flake.rate + flake.phase) * flake.sway
            local cx, cy, cz = flake.x + right.x * sway, flake.y + right.y * sway, flake.z
            local s = flake.size * 0.5
            local rx, ry, rz = right.x * s, right.y * s, right.z * s
            local ux, uy, uz = up.x * s, up.y * s, up.z * s
            position:SetUnpacked(cx - rx - ux, cy - ry - uy, cz - rz - uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
            position:SetUnpacked(cx + rx - ux, cy + ry - uy, cz + rz - uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
            position:SetUnpacked(cx + rx + ux, cy + ry + uy, cz + rz + uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
            position:SetUnpacked(cx - rx + ux, cy - ry + uy, cz - rz + uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
        end
        mesh.End()
        render.OverrideDepthEnable(false, false)
        return count
    end

    // Flickering additive sparks in one dynamic mesh; skipped entirely when no embers exist.
    function WorldHaze.DrawEmbers(now)
        local embers = WorldHaze.Embers
        local count = #embers
        if count == 0 then return 0 end
        local angles = EyeAngles()
        local right, up = angles:Right(), angles:Up()
        local position = Vector()
        render.SetMaterial(emberMaterial)
        render.OverrideDepthEnable(true, false)
        mesh.Begin(MATERIAL_QUADS, count)
        for index = 1, count do
            local ember = embers[index]
            local life = math.Clamp((now - ember.born) / emberFadeIn, 0, 1)
                * math.Clamp((ember.dies - now) / emberFadeOut, 0, 1)
            local flicker = 0.65 + 0.35 * math.sin(now * ember.flicker + ember.phase)
            local a = math.Clamp(life * flicker, 0, 1) * 255
            local swirl = math.sin(now * ember.rate + ember.phase) * ember.swirl
            local cx, cy, cz = ember.x + right.x * swirl, ember.y + right.y * swirl, ember.z
            local s = ember.size * 0.5
            local rx, ry, rz = right.x * s, right.y * s, right.z * s
            local ux, uy, uz = up.x * s, up.y * s, up.z * s
            local r, g, b = emberColor[1], emberColor[2] * flicker, emberColor[3]
            position:SetUnpacked(cx - rx - ux, cy - ry - uy, cz - rz - uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
            position:SetUnpacked(cx + rx - ux, cy + ry - uy, cz + rz - uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
            position:SetUnpacked(cx + rx + ux, cy + ry + uy, cz + rz + uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
            position:SetUnpacked(cx - rx + ux, cy - ry + uy, cz - rz + uz)
            mesh.Position(position) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
        end
        mesh.End()
        render.OverrideDepthEnable(false, false)
        return count
    end

    function WorldHaze.Draw(drawingDepth, drawingSkybox)
        local stats = WorldHaze.Stats
        stats.frameCurtains, stats.frameMist, stats.frameAsh, stats.frameEmbers = 0, 0, 0, 0
        if drawingDepth or drawingSkybox or not WorldHaze.Active then return end
        // Capture or context changes between Think and render must still suppress the draw.
        if WorldHaze.GetInactiveReason(LocalPlayer()) then return end
        local settings = Atmosphere:GetFogSettings()
        if not settings then return end
        local color = settings.color
        local fogColor = {
            Modules.Fog.GetColorComponent(color, 1), Modules.Fog.GetColorComponent(color, 2),
            Modules.Fog.GetColorComponent(color, 3)
        }
        local amount = math.Clamp(densityConVar:GetFloat(), 0, 2)
        local alpha = math.Clamp((WorldHaze.Density or 0) * amount * (1 - (settings.topDown or 0)), 0, 1)
        stats.alpha = alpha
        stats.topDown = settings.topDown or 0
        local eye = EyePos()
        local now = RealTime()
        stats.frameAsh = WorldHaze.DrawAsh(eye, now)
        stats.frameEmbers = WorldHaze.DrawEmbers(now)
        if alpha <= 0.002 then return end
        stats.frameCurtains = WorldHaze.DrawCurtains(eye, fogColor, alpha)
        local dust = (WorldHaze.Radiation or 0) * mistDustWeight
        for index = 1, 3 do mistColor[index] = Lerp(dust, fogColor[index], mistDustColor[index]) end
        stats.frameMist = WorldHaze.DrawMist(eye, mistColor, alpha, now)
        stats.draws = (stats.draws or 0) + 1
    end

    function WorldHaze.GetDiagnostics()
        local stats = WorldHaze.Stats
        local fades = WorldHaze.SideFade
        return {
            active = WorldHaze.Active == true,
            reason = stats.reason,
            tier = stats.tier,
            builds = stats.builds or 0,
            curtainQuads = stats.curtainQuads or 0,
            curtains = stats.curtains,
            columns = stats.columns,
            density = WorldHaze.Density,
            alpha = stats.alpha,
            topDown = stats.topDown or 0,
            radiation = WorldHaze.Radiation or 0,
            ash = #WorldHaze.Ash,
            ashTarget = stats.ashTarget or 0,
            ashSeeded = stats.ashSeeded or 0,
            ashAttempts = stats.ashAttempts or 0,
            frameAsh = stats.frameAsh or 0,
            ashMaterialError = ashMaterial:IsError(),
            embers = #WorldHaze.Embers,
            emberTarget = stats.emberTarget or 0,
            embersSeeded = stats.embersSeeded or 0,
            frameEmbers = stats.frameEmbers or 0,
            emberMaterialError = emberMaterial:IsError(),
            sideFade = { N = fades.N, E = fades.E, S = fades.S, W = fades.W },
            mist = #WorldHaze.Sprites,
            visibleMist = stats.visibleMist or 0,
            seeded = stats.seeded or 0,
            seedAttempts = stats.seedAttempts or 0,
            frameCurtains = stats.frameCurtains or 0,
            frameMist = stats.frameMist or 0,
            draws = stats.draws or 0,
            mistMaterialError = mistMaterial:IsError()
        }
    end

    function WorldHaze.RegisterHooks()
        hook.Add("Think", "ZM.Atmosphere.WorldHaze", WorldHaze.Update)
        hook.Add("PostDrawTranslucentRenderables", "ZM.Atmosphere.WorldHaze", WorldHaze.Draw)
    end
end
