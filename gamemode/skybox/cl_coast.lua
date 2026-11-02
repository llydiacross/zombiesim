// Coastline and the scenery light cube: the sea, sand, rock, embankment and foam height-field meshes around the
// current cell, drawn in the 3D skybox. Shared shore helpers are returned for the cardinal edge terrain.
return function(Skybox, helpers)
    local coast = helpers.coast
    local defaultFogColor = helpers.defaultFogColor
    local mapBasename = helpers.mapBasename
    local smoothstep = helpers.smoothstep
    local valueNoise = helpers.valueNoise
    local seaMaterial = helpers.materials.sea
    local foamMaterial = helpers.materials.foam

    local identityMatrix = Matrix()
    local coastColor = Vector()

    local coastMeshKinds = { "underlay", "water", "sand", "rock", "embankment", "foam" }
    local quadOffsets = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }

    function Skybox:DestroyCoast()
        for _, list in pairs(self.CoastMeshes or {}) do
            for _, imesh in ipairs(list) do imesh:Destroy() end
        end
        self.CoastMeshes = nil
    end

    local function pushCoastVertex(buffer, x, y, z, red, green, blue, alpha, u, v)
        local count = buffer.count
        buffer[count + 1], buffer[count + 2], buffer[count + 3] = x, y, z
        buffer[count + 4] = math.Clamp(math.floor(red + 0.5), 0, 255)
        buffer[count + 5] = math.Clamp(math.floor(green + 0.5), 0, 255)
        buffer[count + 6] = math.Clamp(math.floor(blue + 0.5), 0, 255)
        buffer[count + 7] = math.Clamp(math.floor(alpha + 0.5), 0, 255)
        buffer[count + 8], buffer[count + 9] = u, v
        buffer.count = count + 9
    end

    // Splits a quad buffer into static meshes well below the per-mesh vertex limit. Everything inside Begin/End is
    // plain number access so nothing can error mid-build.
    local function buildCoastMeshes(buffer)
        local meshes = {}
        local quadCount = math.floor(buffer.count / 36)
        local vertex = coast.vertex
        local first = 0
        while first < quadCount do
            local quads = math.min(coast.chunkQuads, quadCount - first)
            local imesh = Mesh()
            mesh.Begin(imesh, MATERIAL_QUADS, quads)
            for index = first * 36 + 1, (first + quads) * 36, 9 do
                vertex:SetUnpacked(buffer[index], buffer[index + 1], buffer[index + 2])
                mesh.Position(vertex)
                mesh.Color(buffer[index + 3], buffer[index + 4], buffer[index + 5], buffer[index + 6])
                mesh.TexCoord(0, buffer[index + 7], buffer[index + 8])
                mesh.AdvanceVertex()
            end
            mesh.End()
            table.insert(meshes, imesh)
            first = first + quads
        end
        return meshes, quadCount
    end

    local function waterShade(depth)
        local t = smoothstep(0, 5.5, depth)
        return Lerp(t, 96, 30), Lerp(t, 156, 68), Lerp(t, 150, 88)
    end

    // Slots beyond the world grid become sea. A low rock embankment caps every city edge that faces it; below it a
    // noise-jittered sand beach with rocky outcrops descends into shallow water, and breaking foam follows the depth
    // contours toward the waterline. Built in absolute sky coordinates whenever the placement changes.
    function Skybox:BuildCoast(manifest, gridX, gridY, radius)
        self:DestroyCoast()
        local stats = self.Stats
        stats.coastSeaQuads, stats.coastWallQuads, stats.coastFoamQuads = 0, 0, 0
        stats.coastSandQuads, stats.coastRockQuads, stats.coastMeshes = 0, 0, 0
        if radius < 1 then return end
        local started = SysTime()

        local span = manifest.cellSpan / manifest.scale
        local half = span * 0.5
        local camera = manifest.cameraVector
        local reach = radius + 1
        // Only the west edge is ocean; the other edges are landforms drawn by the edge terrain, so they count as land here
        // (beaches form against them) but only city cells get the rock embankment.
        local data = ZM_World:GetData()
        local grid = data and data.world and data.world.grid
        local width, height = tonumber(grid and grid[1]) or 0, tonumber(grid and grid[2]) or 0
        local land, city = {}, {}
        local function classify(dx, dy)
            local key = dx .. ":" .. dy
            if land[key] == nil then
                local kind = Skybox.ClassifyEdge(gridX + dx, gridY + dy, width, height)
                city[key] = (dx == 0 and dy == 0) or (kind == "city" and ZM_World:GetCell(gridX + dx, gridY + dy) ~= nil)
                land[key] = city[key] or (kind ~= "ocean" and kind ~= "city")
            end
            return key
        end
        local function isLand(dx, dy) return land[classify(dx, dy)] end
        local function isCity(dx, dy) return city[classify(dx, dy)] end
        local seaSlots, edges = {}, {}
        local function landRectangle(dx, dy)
            local cell = ZM_World:GetCell(gridX + dx, gridY + dy)
            local x, y = camera.x + dx * span, camera.y - dy * span
            return ZM_SkyboxGeometry.GetLandRectangle(manifest, cell and mapBasename(cell.map), x, y)
        end
        local function nearbyLand(dx, dy)
            local lands = {}
            for ny = -1, 1 do
                for nx = -1, 1 do
                    if isLand(dx + nx, dy + ny) then
                        table.insert(lands, landRectangle(dx + nx, dy + ny))
                    end
                end
            end
            return lands
        end
        // Grid east (dx + 1) is +X; grid north (dy - 1) is +Y in Hammer space.
        local sides = { { 1, 0, 1, 0 }, { -1, 0, -1, 0 }, { 0, -1, 0, 1 }, { 0, 1, 0, -1 } }
        for dy = -reach, reach do
            for dx = -reach, reach do
                local cx, cy = camera.x + dx * span, camera.y - dy * span
                if isLand(dx, dy) then
                    if not isCity(dx, dy) then continue end
                    local rectangle = landRectangle(dx, dy)
                    for _, band in ipairs(ZM_SkyboxGeometry.GetWaterBands(rectangle, cx, cy, half)) do
                        band.lands = nearbyLand(dx, dy)
                        table.insert(seaSlots, band)
                    end
                    for _, side in ipairs(sides) do
                        local omitted = (side[3] == 1 and rectangle.x1 < cx + half) or
                            (side[3] == -1 and rectangle.x0 > cx - half) or
                            (side[4] == 1 and rectangle.y1 < cy + half) or
                            (side[4] == -1 and rectangle.y0 > cy - half)
                        if omitted or not isLand(dx + side[1], dy + side[2]) then
                            local x = side[3] == 1 and rectangle.x1 or (side[3] == -1 and rectangle.x0 or (rectangle.x0 + rectangle.x1) * 0.5)
                            local y = side[4] == 1 and rectangle.y1 or (side[4] == -1 and rectangle.y0 or (rectangle.y0 + rectangle.y1) * 0.5)
                            table.insert(edges, { x = x, y = y, nx = side[3], ny = side[4],
                                length = side[3] ~= 0 and rectangle.y1 - rectangle.y0 or rectangle.x1 - rectangle.x0 })
                        end
                    end
                else
                    table.insert(seaSlots, { x = cx, y = cy, lands = nearbyLand(dx, dy) })
                end
            end
        end
        if #seaSlots == 0 then return end

        local seaZ = camera.z + coast.seaLevel
        local offsetX, offsetY = gridX * span - camera.x, -gridY * span - camera.y
        local far = coast.bandWidth + 40
        // Returns terrain height, rockiness, and the unjittered distance to the nearest land slot.
        local function sample(px, py, lands)
            local nearest = far
            for index = 1, #lands do
                local slot = lands[index]
                nearest = math.min(nearest, ZM_SkyboxGeometry.DistanceToLand(px, py, slot))
            end
            if nearest >= far then return seaZ - 8, 0, nearest end
            local wx, wy = px + offsetX, py + offsetY
            local jitter = ((valueNoise(wx / 90, wy / 90) - 0.5) * 26 + (valueNoise(wx / 23 + 7.1, wy / 23 + 3.7) - 0.5) * 7) * smoothstep(0, 14, nearest)
            local distance = math.max(nearest + jitter, 0)
            local height
            if distance < coast.beachWidth then
                height = seaZ + coast.duneHeight * (1 - distance / coast.beachWidth) ^ 1.4
            else
                height = seaZ - (distance - coast.beachWidth) * coast.shelfSlope
            end
            local rock = smoothstep(0.56, 0.72, valueNoise(wx / 150 + 31.7, wy / 150 + 17.3))
            if rock > 0 then
                local ridge = 1 - math.abs(valueNoise(wx / 16 + 5.3, wy / 16 + 9.1) * 2 - 1)
                height = height + rock * (1 - smoothstep(25, 95, nearest)) * (ridge * ridge * 6.5 - 1.2)
            end
            return height, rock, nearest
        end
        // Samples a slot grid with a one-sample border so terrain normals are continuous across slot edges.
        local function sampleGrid(slot, divisions)
            local width, height = (slot.halfX or half) * 2, (slot.halfY or half) * 2
            local cx = camera.x + math.floor((slot.x - camera.x) / span + 0.5) * span
            local cy = camera.y + math.floor((slot.y - camera.y) / span + 0.5) * span
            local coastHalf = manifest.schemaVersion == 2 and manifest.cellBounds.coastContactHalfExtent / manifest.scale or nil
            local xs, columns = ZM_SkyboxGeometry.GetCoastAxis(slot.x - width * 0.5, slot.x + width * 0.5, cx, span, divisions, coastHalf)
            local ys, rows = ZM_SkyboxGeometry.GetCoastAxis(slot.y - height * 0.5, slot.y + height * 0.5, cy, span, divisions, coastHalf)
            local stride = columns + 3
            local grid = { xs = xs, ys = ys, stepX = width / columns, stepY = height / rows, columns = columns, rows = rows, stride = stride,
                x0 = slot.x - width * 0.5, y0 = slot.y - height * 0.5, heights = {}, rocks = {}, nearest = {} }
            for row = -1, rows + 1 do
                for column = -1, columns + 1 do
                    local index = (row + 1) * stride + column + 2
                    grid.heights[index], grid.rocks[index], grid.nearest[index] = sample(xs[column], ys[row], slot.lands)
                end
            end
            return grid
        end

        local buffers = {}
        for _, kind in ipairs(coastMeshKinds) do buffers[kind] = { count = 0 } end
        local tile = coast.rippleTile
        local lightX, lightY, lightZ = 0.45, 0.35, 0.82
        for _, slot in ipairs(seaSlots) do
            local halfX, halfY = slot.halfX or half, slot.halfY or half
            local x0, y0, x1, y1 = slot.x - halfX, slot.y - halfY, slot.x + halfX, slot.y + halfY
            local deepRed, deepGreen, deepBlue = waterShade(99)
            local underlayZ = seaZ - 0.4
            local underlay = buffers.underlay
            pushCoastVertex(underlay, x0, y0, underlayZ, deepRed, deepGreen, deepBlue, 255, (x0 + offsetX) / tile, (y0 + offsetY) / tile)
            pushCoastVertex(underlay, x1, y0, underlayZ, deepRed, deepGreen, deepBlue, 255, (x1 + offsetX) / tile, (y0 + offsetY) / tile)
            pushCoastVertex(underlay, x1, y1, underlayZ, deepRed, deepGreen, deepBlue, 255, (x1 + offsetX) / tile, (y1 + offsetY) / tile)
            pushCoastVertex(underlay, x0, y1, underlayZ, deepRed, deepGreen, deepBlue, 255, (x0 + offsetX) / tile, (y1 + offsetY) / tile)
            if slot.lands and #slot.lands > 0 then
                // Beach and rock terrain: only quads that reach the surface are kept; the rest is hidden by water.
                local grid = sampleGrid(slot, coast.terrainDivisions)
                local stepX, stepY, stride, heights, rocks, nearest = grid.stepX, grid.stepY, grid.stride, grid.heights, grid.rocks, grid.nearest
                local function terrainVertex(buffer, row, column, rocky)
                    local index = (row + 1) * stride + column + 2
                    local height = heights[index]
                    local slopeX = (heights[index + 1] - heights[index - 1]) / (grid.xs[column + 1] - grid.xs[column - 1])
                    local slopeY = (heights[index + stride] - heights[index - stride]) / (grid.ys[row + 1] - grid.ys[row - 1])
                    local light = (-slopeX * lightX - slopeY * lightY + lightZ) / math.sqrt(slopeX * slopeX + slopeY * slopeY + 1)
                    local shade = 0.5 + 0.5 * math.max(light, 0)
                    local wet = 1 - smoothstep(seaZ + 0.1, seaZ + 0.9, height)
                    local red, green, blue
                    if rocky then
                        shade = shade * (1 - 0.3 * wet)
                        red, green, blue = 192 * shade, 188 * shade, 182 * shade
                    else
                        shade = shade * (1 - 0.38 * wet)
                        red, green, blue = 255 * shade, 226 * shade, 172 * shade
                    end
                    local x, y = grid.xs[column], grid.ys[row]
                    pushCoastVertex(buffer, x, y, height, red, green, blue, 255, (x + offsetX) / 24, (y + offsetY) / 24)
                end
                for row = 0, grid.rows - 1 do
                    for column = 0, grid.columns - 1 do
                        local a = (row + 1) * stride + column + 2
                        local b, c, d = a + 1, a + stride + 1, a + stride
                        local highest = math.max(heights[a], heights[b], heights[c], heights[d])
                        if highest > seaZ - 0.4 and math.min(nearest[a], nearest[b], nearest[c], nearest[d]) < coast.bandWidth then
                            local lowest = math.min(heights[a], heights[b], heights[c], heights[d])
                            local rocky = (rocks[a] + rocks[b] + rocks[c] + rocks[d]) * 0.25 > 0.42 or highest - lowest > math.min(stepX, stepY) * 0.75
                            local buffer = rocky and buffers.rock or buffers.sand
                            terrainVertex(buffer, row, column, rocky)
                            terrainVertex(buffer, row, column + 1, rocky)
                            terrainVertex(buffer, row + 1, column + 1, rocky)
                            terrainVertex(buffer, row + 1, column, rocky)
                        end
                    end
                end

                // Shallow water shades with depth and carries the breaking-foam layer.
                grid = sampleGrid(slot, coast.waterDivisions)
                stepX, stepY, stride, heights, nearest = grid.stepX, grid.stepY, grid.stride, grid.heights, grid.nearest
                local foamZ = seaZ + 0.2
                local corners = {}
                for row = 0, grid.rows - 1 do
                    for column = 0, grid.columns - 1 do
                        local a = (row + 1) * stride + column + 2
                        corners[1], corners[2], corners[3], corners[4] = a, a + 1, a + stride + 1, a + stride
                        if math.min(nearest[a], nearest[a + 1], nearest[a + stride + 1], nearest[a + stride]) < coast.bandWidth then
                            local shallowest, deepest = math.huge, -math.huge
                            for corner = 1, 4 do
                                local index = corners[corner]
                                local depth = seaZ - heights[index]
                                shallowest, deepest = math.min(shallowest, depth), math.max(deepest, depth)
                                local x, y = grid.xs[column + quadOffsets[corner][1]], grid.ys[row + quadOffsets[corner][2]]
                                local red, green, blue = waterShade(depth)
                                pushCoastVertex(buffers.water, x, y, seaZ, red, green, blue, 255, (x + offsetX) / tile, (y + offsetY) / tile)
                            end
                            if shallowest < coast.foamDepth and deepest > -0.4 then
                                for corner = 1, 4 do
                                    local depth = seaZ - heights[corners[corner]]
                                    local x, y = grid.xs[column + quadOffsets[corner][1]], grid.ys[row + quadOffsets[corner][2]]
                                    local foam = 255 * (1 - smoothstep(2.6, coast.foamDepth, depth)) * smoothstep(-0.4, 0.2, depth)
                                    pushCoastVertex(buffers.foam, x, y, foamZ, foam, foam, foam, 255, (x + y + offsetX + offsetY) / 70, depth / coast.waveDepthLength)
                                end
                            end
                        end
                    end
                end
            end
        end

        // A low, slightly sloped rock lip covers the step between each city edge and the beach below it. Authored ocean
        // edge pieces already descend to the beach at the visual edge, so they replace the lip there.
        local topZ, footZ = camera.z + coast.streetHeight, seaZ - 1
        local bounds = manifest.schemaVersion == 2 and manifest.cellBounds
        if bounds and bounds.coastContactHalfExtent == bounds.visualHalfExtent then edges = {} end
        for _, edge in ipairs(edges) do
            // The edge runs perpendicular to its outward normal.
            local edgeHalf = edge.length * 0.5
            local tx, ty = -edge.ny * edgeHalf, edge.nx * edgeHalf
            local ox, oy = edge.nx * 1.5, edge.ny * 1.5
            local buffer = buffers.embankment
            local height = (topZ - footZ) / 8
            pushCoastVertex(buffer, edge.x - tx, edge.y - ty, topZ, 205, 200, 194, 255, 0, 0)
            pushCoastVertex(buffer, edge.x + tx, edge.y + ty, topZ, 205, 200, 194, 255, edge.length / 8, 0)
            pushCoastVertex(buffer, edge.x + tx + ox, edge.y + ty + oy, footZ, 150, 146, 140, 255, edge.length / 8, height)
            pushCoastVertex(buffer, edge.x - tx + ox, edge.y - ty + oy, footZ, 150, 146, 140, 255, 0, height)
        end

        local meshes, counts, meshCount = {}, {}, 0
        for _, kind in ipairs(coastMeshKinds) do
            meshes[kind], counts[kind] = buildCoastMeshes(buffers[kind])
            meshCount = meshCount + #meshes[kind]
        end
        self.CoastMeshes = meshes
        stats.coastSeaQuads = counts.underlay + counts.water
        stats.coastWallQuads = counts.embankment
        stats.coastFoamQuads = counts.foam
        stats.coastSandQuads = counts.sand
        stats.coastRockQuads = counts.rock
        stats.coastMeshes = meshCount
        stats.coastBuildMs = math.Round((SysTime() - started) * 1000, 1)
    end

    local function drawCoastMeshes(list)
        for _, imesh in ipairs(list) do imesh:Draw() end
    end

    local function setCoastTextureTransform(material, scale, yaw, offsetU, offsetV)
        local matrix = coast.textureMatrix
        matrix:Identity()
        coast.textureAngle:SetUnpacked(0, yaw, 0)
        matrix:Rotate(coast.textureAngle)
        coast.textureScale:SetUnpacked(scale, scale, 1)
        matrix:Scale(coast.textureScale)
        coast.textureOffset:SetUnpacked(offsetU % 1, offsetV % 1, 0)
        matrix:SetTranslation(coast.textureOffset)
        material:SetMatrix("$basetexturetransform", matrix)
    end

    // The playable cell's baked lighting, measured through the light cube, tints the shared fog colour (see
    // Atmosphere:GetFogSettings) so dark districts get dark fog in both the city and the sky, and the coast, edge terrain,
    // dome and clouds that derive from the fog colour darken with it. Bright daylight cells (cube top luminance about
    // 0.85) keep the profile colour; the square root keeps dim cells readable rather than black.
    Skybox.SceneryLight = { level = 1, 1, 1, 1, fullBright = 0.8, minimum = 0.3, chroma = 0.4 }
    function Skybox:UpdateSceneryLight(cube)
        local light = self.SceneryLight
        local top = cube and cube[5]
        if not top then
            light.level, light[1], light[2], light[3] = 1, 1, 1, 1
        else
            local luminance = math.max(top.x * 0.3 + top.y * 0.59 + top.z * 0.11, 0.0001)
            local level = math.Clamp(math.sqrt(luminance / light.fullBright), light.minimum, 1)
            // Hue follows the light only as it darkens, so daylight cells keep the profile colour exactly.
            local chroma = light.chroma * (1 - level) / (1 - light.minimum)
            light.level = level
            light[1] = math.min(level * Lerp(chroma, 1, math.Clamp(top.x / luminance, 0.5, 1.5)), 1)
            light[2] = math.min(level * Lerp(chroma, 1, math.Clamp(top.y / luminance, 0.5, 1.5)), 1)
            light[3] = math.min(level * Lerp(chroma, 1, math.Clamp(top.z / luminance, 0.5, 1.5)), 1)
        end
        self.Stats.sceneryLight = math.Round(light.level, 3)
        return light
    end

    // Coast colours follow the atmosphere's brightness; the sky-pass fog supplies distance haze, so the water keeps its
    // own hue instead of being pre-mixed toward the fog colour.
    function Skybox:DrawCoast(fogColor, modelMatrix)
        local meshes = self.CoastMeshes
        if not meshes then return end
        fogColor = fogColor or defaultFogColor
        local red, green, blue = (fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255
        local brightness = math.Clamp((red * 0.3 + green * 0.59 + blue * 0.11) * 1.6, 0.25, 1)
        local snow = self.Stats.snowAlpha or 0
        local now = CurTime()
        cam.PushModelMatrix(modelMatrix or identityMatrix)
        coastColor:SetUnpacked(Lerp(0.12, brightness, red), Lerp(0.12, brightness, green), Lerp(0.12, brightness, blue))
        seaMaterial:SetVector("$color", coastColor)
        render.SetMaterial(seaMaterial)
        drawCoastMeshes(meshes.underlay)
        drawCoastMeshes(meshes.water)
        local ground = brightness * Lerp(snow, 1, 1.15)
        coastColor:SetUnpacked(math.min(Lerp(snow * 0.7, ground, 1), 1), math.min(Lerp(snow * 0.7, ground, 1), 1), math.min(Lerp(snow * 0.7, ground, 1), 1))
        for _, entry in ipairs({ { coast.sandMaterial, meshes.sand }, { coast.rockMaterial, meshes.rock }, { coast.embankmentMaterial, meshes.embankment } }) do
            if #entry[2] > 0 then
                entry[1]:SetVector("$color", coastColor)
                render.SetMaterial(entry[1])
                drawCoastMeshes(entry[2])
            end
        end
        if coast.texturesReady then
            // Two ripple layers at different scales and headings interfere into a moving glitter.
            local ripple = coast.rippleMaterial
            coastColor:SetUnpacked(0.7 * brightness, 0.75 * brightness, 0.8 * brightness)
            ripple:SetVector("$color", coastColor)
            setCoastTextureTransform(ripple, 1, 0, now * 0.011, now * 0.019)
            render.SetMaterial(ripple)
            drawCoastMeshes(meshes.underlay)
            drawCoastMeshes(meshes.water)
            setCoastTextureTransform(ripple, 1.7, 37, -now * 0.014, now * 0.008)
            render.SetMaterial(ripple)
            drawCoastMeshes(meshes.underlay)
            drawCoastMeshes(meshes.water)
            if #meshes.foam > 0 then
                coastColor:SetUnpacked(0.95 * brightness, 0.97 * brightness, brightness)
                foamMaterial:SetVector("$color", coastColor)
                setCoastTextureTransform(foamMaterial, 1, 0, now * 0.006, now / coast.wavePeriod)
                render.SetMaterial(foamMaterial)
                drawCoastMeshes(meshes.foam)
            end
        end
        cam.PopModelMatrix()
        self.Stats.coastDraws = (self.Stats.coastDraws or 0) + 1
    end

    return { buildCoastMeshes = buildCoastMeshes, drawCoastMeshes = drawCoastMeshes, pushCoastVertex = pushCoastVertex, quadOffsets = quadOffsets }
end
