// Cardinal world-edge terrain ring and its regression checks; reuses the coast mesh helpers.
return function(Skybox, helpers)
    local coast = helpers.coast
    local smoothstep = helpers.smoothstep
    local valueNoise = helpers.valueNoise
    local buildCoastMeshes = helpers.buildCoastMeshes
    local drawCoastMeshes = helpers.drawCoastMeshes
    local pushCoastVertex = helpers.pushCoastVertex
    local quadOffsets = helpers.quadOffsets

    // Cardinal world edges: north hills, east mountains, south flatlands, west open ocean (the coast above). The ring is
    // one static height field in grid-local sky units, u east from the grid's west boundary and v south from its north
    // boundary, built once per profile and translated to the current cell when drawn. City boundaries sit at street
    // height; corners blend the two adjacent landforms and the north/south land falls to beach height at the west shore.
    local edgeTerrain = {
        cellsPerQuad = 7,
        northDepth = 40,
        southDepth = 40,
        eastDepth = 60,
        snowLine = 380,
        light = Vector(-0.45, -0.3, 0.84):GetNormalized(),
        matrix = Matrix(),
        translation = Vector(),
        color = Vector(),
        layerDepthBias = 0.00003
    }
    edgeTerrain.grassMaterial = CreateMaterial("zombiesim_skybox_edge_grass_v1", "UnlitGeneric", {
        ["$basetexture"] = "nature/grassfloor002a",
        ["$vertexcolor"] = 1,
        ["$nocull"] = 1
    })
    // Rock and snow are translucent overlays on the same surface; per-vertex alpha blends them smoothly over the grass.
    edgeTerrain.rockMaterial = CreateMaterial("zombiesim_skybox_edge_rock_v2", "UnlitGeneric", {
        ["$basetexture"] = "nature/rockfloor005a",
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$translucent"] = 1,
        ["$nocull"] = 1
    })
    edgeTerrain.snowMaterial = CreateMaterial("zombiesim_skybox_edge_snow_v2", "UnlitGeneric", {
        ["$basetexture"] = "nature/snowfloor002a",
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$translucent"] = 1,
        ["$nocull"] = 1
    })
    // Weather snow is drawn over grass and rock as a translucent pass whose alpha follows the settled snow cover.
    edgeTerrain.coverMaterial = CreateMaterial("zombiesim_skybox_edge_cover_v1", "UnlitGeneric", {
        ["$basetexture"] = "nature/snowfloor002a",
        ["$vertexcolor"] = 1,
        ["$translucent"] = 1,
        ["$nocull"] = 1
    })
    edgeTerrain.kinds = { "grass", "rock", "snow" }
    edgeTerrain.materials = { grass = edgeTerrain.grassMaterial, rock = edgeTerrain.rockMaterial, snow = edgeTerrain.snowMaterial }
    edgeTerrain.tiles = { grass = 48, rock = 96, snow = 72 }

    // Classifies a grid slot (cells, may lie outside the grid). Ocean owns every slot west of the grid, including the
    // north-west and south-west corner columns, so the shoreline runs straight along the west boundary.
    function Skybox.ClassifyEdge(gx, gy, width, height)
        if gx >= 0 and gx < width and gy >= 0 and gy < height then return "city" end
        if gx < 0 then return "ocean" end
        if gx >= width then
            if gy < 0 then return "hills-mountains" end
            if gy >= height then return "mountains-flatlands" end
            return "mountains"
        end
        if gy < 0 then return "hills" end
        return "flatlands"
    end

    local function terrainFbm(x, y)
        return valueNoise(x, y) * 0.5 + valueNoise(x * 2.03 + 17.1, y * 2.03 + 4.9) * 0.3 + valueNoise(x * 4.1 + 9.7, y * 4.1 + 23.3) * 0.2
    end

    local function terrainRidge(x, y)
        local total, amplitude, weight = 0, 0.6, 0
        for octave = 1, 3 do
            local ridge = 1 - math.abs(valueNoise(x, y) * 2 - 1)
            total, weight = total + ridge * ridge * amplitude, weight + amplitude
            x, y, amplitude = x * 2.1 + 13.7, y * 2.1 + 5.3, amplitude * 0.5
        end
        return total / weight
    end

    local function hillsHeight(u, v, d)
        return 2 + smoothstep(0, 350, d) * (14 + 62 * terrainFbm(u / 260 + 3.1, v / 260 + 8.7))
    end

    local function flatlandsHeight(u, v, d)
        return 2 + smoothstep(0, 250, d) * (1 + 5 * terrainFbm(u / 420 + 11.3, v / 420 + 2.9))
    end

    local function mountainHeight(u, v, d)
        local foothills = smoothstep(0, 300, d) * (12 + 40 * terrainFbm(u / 220 + 5.5, v / 220 + 1.7))
        // Large-scale massifs vary the range height; a domain warp breaks up the noise lattice so peaks do not repeat.
        local massif = terrainFbm(u / 1500 + 7.7, v / 1500 + 3.3)
        local warpU = u + (valueNoise(u / 700 + 1.9, v / 700 + 4.2) - 0.5) * 420
        local warpV = v + (valueNoise(u / 700 + 8.3, v / 700 + 6.6) - 0.5) * 420
        local ridge = terrainRidge(warpU / 430 + 2.2, warpV / 430 + 9.4)
        return 2 + foothills + smoothstep(250, 1300, d) * (140 + 1000 * massif * massif * (0.35 + 0.65 * ridge))
    end

    // Height above the sky camera (sky units) at grid-local (u, v) outside the city rectangle `width` x `height`.
    function Skybox.EdgeHeight(u, v, width, height, span)
        local e, n, s = math.max(u - width, 0), math.max(-v, 0), math.max(v - height, 0)
        local quad = span / edgeTerrain.cellsPerQuad
        local h
        if e > 0 and n > 0 then
            local d = math.sqrt(e * e + n * n)
            h = Lerp(smoothstep(0.25, 0.75, e / (e + n)), hillsHeight(u, v, d), mountainHeight(u, v, d))
        elseif e > 0 and s > 0 then
            local d = math.sqrt(e * e + s * s)
            h = Lerp(smoothstep(0.25, 0.75, e / (e + s)), flatlandsHeight(u, v, d), mountainHeight(u, v, d))
        elseif e > 0 then
            h = mountainHeight(u, v, e)
        elseif n > 0 then
            h = hillsHeight(u, v, n)
        elseif s > 0 then
            h = flatlandsHeight(u, v, s)
        else
            return 2
        end
        // North/south land falls to the coast's dune height at the west shore.
        if e <= 0 then
            local depth = math.max(n, s)
            h = Lerp(smoothstep(0, 360, u), Lerp(smoothstep(0, 40, depth), 2, coast.seaLevel + coast.duneHeight), h)
        end
        // The ring's outer limits taper so no cut face shows on the horizon.
        local taper = (1 - smoothstep(edgeTerrain.northDepth * quad * 0.55, edgeTerrain.northDepth * quad, n)) *
            (1 - smoothstep(edgeTerrain.southDepth * quad * 0.55, edgeTerrain.southDepth * quad, s)) *
            (1 - smoothstep(edgeTerrain.eastDepth * quad * 0.8, edgeTerrain.eastDepth * quad, e))
        return 2 + (h - 2) * taper
    end

    function Skybox:DestroyEdgeTerrain()
        for _, list in pairs(self.EdgeMeshes or {}) do
            for _, imesh in ipairs(list) do imesh:Destroy() end
        end
        self.EdgeMeshes = nil
        self.EdgeKey = nil
    end

    // Regions share their boundary sample lines exactly (all extents are whole quads), so no T-junction cracks appear.
    function Skybox:BuildEdgeTerrain(manifest)
        local data = ZM_World and ZM_World:GetData()
        local grid = data and data.world and data.world.grid
        local width, height = tonumber(grid and grid[1]), tonumber(grid and grid[2])
        if not width or not height then return end
        local span = manifest.cellSpan / manifest.scale
        local key = table.concat({ tostring(self.ManifestProfile), width, height, span, manifest.cameraVector.z, manifest.schemaVersion, "edges-v3" }, ":")
        if key == self.EdgeKey and self.EdgeMeshes then return end
        self:DestroyEdgeTerrain()
        local started = SysTime()
        local quad = span / edgeTerrain.cellsPerQuad
        local W, H = width * span, height * span
        local northDepth, southDepth, eastDepth = edgeTerrain.northDepth * quad, edgeTerrain.southDepth * quad, edgeTerrain.eastDepth * quad
        local regions = {
            { u0 = 0, v0 = -northDepth, columns = width * edgeTerrain.cellsPerQuad, rows = edgeTerrain.northDepth },
            { u0 = 0, v0 = H, columns = width * edgeTerrain.cellsPerQuad, rows = edgeTerrain.southDepth },
            { u0 = W, v0 = -northDepth, columns = edgeTerrain.eastDepth, rows = edgeTerrain.northDepth + height * edgeTerrain.cellsPerQuad + edgeTerrain.southDepth }
        }
        local baseZ = manifest.cameraVector.z
        local light = edgeTerrain.light
        local buffers = { grass = { count = 0 }, rock = { count = 0 }, snow = { count = 0 } }
        local tiles = edgeTerrain.tiles
        for _, region in ipairs(regions) do
            local stride = region.columns + 3
            local heights = {}
            for row = -1, region.rows + 1 do
                for column = -1, region.columns + 1 do
                    heights[(row + 1) * stride + column + 2] = Skybox.EdgeHeight(region.u0 + column * quad, region.v0 + row * quad, W, H, span)
                end
            end
            local shades, rocks, snows = {}, {}, {}
            for row = 0, region.rows do
                for column = 0, region.columns do
                    local index = (row + 1) * stride + column + 2
                    // Grid-local v grows south while sky Y grows north, hence the sign on the Y gradient.
                    local gx = (heights[index + 1] - heights[index - 1]) / (2 * quad)
                    local gy = -(heights[index + stride] - heights[index - stride]) / (2 * quad)
                    local length = math.sqrt(gx * gx + gy * gy + 1)
                    local lambert = math.max((-gx * light.x - gy * light.y + light.z) / length, 0)
                    shades[index] = 0.42 + 0.58 * lambert
                    local slope = math.sqrt(gx * gx + gy * gy)
                    local u, v = region.u0 + column * quad, region.v0 + row * quad
                    local h = heights[index]
                    rocks[index] = math.max(smoothstep(0.55, 1, slope), smoothstep(120, 230, h + (valueNoise(u / 90 + 1.3, v / 90 + 6.1) - 0.5) * 90))
                    snows[index] = smoothstep(edgeTerrain.snowLine - 50, edgeTerrain.snowLine + 50,
                        h + (valueNoise(u / 140 + 4.4, v / 140 + 7.7) - 0.5) * 160) * (1 - 0.7 * smoothstep(1.1, 1.8, slope))
                end
            end
            local corners = {}
            for row = 0, region.rows - 1 do
                for column = 0, region.columns - 1 do
                    local a = (row + 1) * stride + column + 2
                    corners[1], corners[2], corners[3], corners[4] = a, a + 1, a + stride + 1, a + stride
                    local rock, snow = 0, 0
                    for corner = 1, 4 do
                        rock, snow = math.max(rock, rocks[corners[corner]]), math.max(snow, snows[corners[corner]])
                    end
                    for corner = 1, 4 do
                        local index = corners[corner]
                        local x = region.u0 + (column + quadOffsets[corner][1]) * quad
                        local y = -(region.v0 + (row + quadOffsets[corner][2]) * quad)
                        local z = baseZ + heights[index]
                        local shade = shades[index] * 255
                        // Lower, drier grass warms; lush patches cool slightly.
                        local dry = valueNoise(x / 300 + 2.5, y / 300 + 8.5)
                        pushCoastVertex(buffers.grass, x, y, z, shade * Lerp(dry, 0.82, 1), shade * Lerp(dry, 0.9, 0.86), shade * Lerp(dry, 0.7, 0.62), 255, x / tiles.grass, y / tiles.grass)
                        if rock > 0.01 then
                            pushCoastVertex(buffers.rock, x, y, z, shade, shade * 0.98, shade * 0.95, rocks[index] * 255, x / tiles.rock, y / tiles.rock)
                        end
                        if snow > 0.01 then
                            pushCoastVertex(buffers.snow, x, y, z, shade * 0.96, shade * 0.98, shade, snows[index] * 255, x / tiles.snow, y / tiles.snow)
                        end
                    end
                end
            end
        end
        local meshes, total, meshCount = {}, 0, 0
        for _, kind in ipairs(edgeTerrain.kinds) do
            local quads
            meshes[kind], quads = buildCoastMeshes(buffers[kind])
            total, meshCount = total + quads, meshCount + #meshes[kind]
            self.Stats["edge" .. kind .. "Quads"] = quads
        end
        self.EdgeMeshes = meshes
        self.EdgeKey = key
        self.EdgeGrid = { width = width, height = height, span = span }
        local stats = self.Stats
        stats.edgeTerrainQuads = total
        stats.edgeTerrainMeshes = meshCount
        stats.edgeBuildMs = math.Round((SysTime() - started) * 1000, 1)
    end

    // Sky-space translation that places the grid-local terrain around the current cell.
    function Skybox:GetEdgeTranslation(manifest, gridX, gridY)
        local span = manifest.cellSpan / manifest.scale
        local camera = manifest.cameraVector
        return camera.x - (gridX + 0.5) * span, camera.y + (gridY + 0.5) * span
    end

    function Skybox:DrawEdgeTerrain(manifest, fogColor)
        local meshes = self.EdgeMeshes
        if not meshes or not self.CurrentGridX then return end
        local red, green, blue = (fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255
        local brightness = math.Clamp((red * 0.3 + green * 0.59 + blue * 0.11) * 1.6, 0.25, 1)
        local x, y = self:GetEdgeTranslation(manifest, self.CurrentGridX, self.CurrentGridY)
        edgeTerrain.translation:SetUnpacked(x, y, 0)
        edgeTerrain.matrix:SetTranslation(edgeTerrain.translation)
        cam.PushModelMatrix(edgeTerrain.matrix)
        local color = edgeTerrain.color
        color:SetUnpacked(Lerp(0.1, brightness, red), Lerp(0.1, brightness, green), Lerp(0.1, brightness, blue))
        // Overlays sit on identical geometry; a growing window-space depth bias keeps each layer in front of the last.
        for layer, kind in ipairs(edgeTerrain.kinds) do
            local list = meshes[kind]
            if #list > 0 then
                local material = edgeTerrain.materials[kind]
                material:SetVector("$color", color)
                render.SetMaterial(material)
                render.DepthRange(0, 1 - (layer - 1) * edgeTerrain.layerDepthBias)
                drawCoastMeshes(list)
            end
        end
        local snow = self.Stats.snowAlpha or 0
        if snow > 0.002 then
            local cover = edgeTerrain.coverMaterial
            cover:SetVector("$color", color)
            cover:SetFloat("$alpha", snow * 0.9)
            render.SetMaterial(cover)
            render.DepthRange(0, 1 - (#edgeTerrain.kinds) * edgeTerrain.layerDepthBias)
            drawCoastMeshes(meshes.grass)
        end
        render.DepthRange(0, 1)
        cam.PopModelMatrix()
        self.Stats.edgeDraws = (self.Stats.edgeDraws or 0) + 1
    end

    // Pure-function regression for the cardinal contract: classification of all four edges and corners, landform
    // character, seam continuity, the west shore height, east-range visibility from the far west, and sky-space direction.
    function Skybox:RunEdgeRegression()
        local manifest = self.Manifest
        local data = ZM_World and ZM_World:GetData()
        local grid = data and data.world and data.world.grid
        local width, height = tonumber(grid and grid[1]), tonumber(grid and grid[2])
        local results, failures = {}, 0
        local function check(name, passed, detail)
            table.insert(results, { name = name, passed = passed and true or false, detail = detail })
            if not passed then failures = failures + 1 end
        end
        if not manifest or not width or not height then
            check("prerequisites", false, "skybox manifest or world grid missing")
            return results, failures
        end
        local span = manifest.cellSpan / manifest.scale
        local W, H = width * span, height * span
        local midX, midY = math.floor(width / 2), math.floor(height / 2)
        local expected = {
            { "north", midX, -1, "hills" }, { "east", width, midY, "mountains" }, { "south", midX, height, "flatlands" },
            { "west", -1, midY, "ocean" }, { "northeast", width, -1, "hills-mountains" },
            { "southeast", width, height, "mountains-flatlands" }, { "northwest", -1, -1, "ocean" },
            { "southwest", -1, height, "ocean" }, { "center", midX, midY, "city" }
        }
        for _, case in ipairs(expected) do
            local actual = Skybox.ClassifyEdge(case[2], case[3], width, height)
            check("classify " .. case[1], actual == case[4], string.format("(%d,%d) -> %s, expected %s", case[2], case[3], actual, case[4]))
        end
        local function heightAt(u, v) return Skybox.EdgeHeight(u, v, W, H, span) end
        local function meanHeight(side)
            local total, samples = 0, 0
            for step = 1, 24 do
                local along = (step - 0.5) / 24
                local u, v
                if side == "north" then u, v = W * along, -600 elseif side == "south" then u, v = W * along, H + 600 else u, v = W + 1500, H * along end
                total, samples = total + heightAt(u, v), samples + 1
            end
            return total / samples
        end
        local north, east, south = meanHeight("north"), meanHeight("east"), meanHeight("south")
        check("landform east mountains", east > 250, string.format("mean %.1f", east))
        check("landform north hills", north > 12 and north < 110, string.format("mean %.1f", north))
        check("landform south flatlands", south > 1.5 and south < 9, string.format("mean %.1f", south))
        check("landform ordering", east > north and north > south, string.format("east %.1f north %.1f south %.1f", east, north, south))
        local worst = 0
        for step = 0, 40 do
            local t = step / 40
            worst = math.max(worst, math.abs(heightAt(W * t, 0) - 2), math.abs(heightAt(W * t, H) - 2),
                math.abs(heightAt(W, H * t) - 2))
        end
        check("city boundaries at street height", worst < 0.01, string.format("max deviation %.4f", worst))
        local seam = 0
        for step = 1, 40 do
            local depth = step * 40
            seam = math.max(seam, math.abs(heightAt(W - 0.001, -depth) - heightAt(W + 0.001, -depth)),
                math.abs(heightAt(W - 0.001, H + depth) - heightAt(W + 0.001, H + depth)),
                math.abs(heightAt(W + depth, -0.001) - heightAt(W + depth, 0.001)),
                math.abs(heightAt(W + depth, H - 0.001) - heightAt(W + depth, H + 0.001)))
        end
        check("corner seams continuous", seam < 0.5, string.format("max step %.3f", seam))
        local shoreTarget = coast.seaLevel + coast.duneHeight
        local shore = math.max(math.abs(heightAt(0, -400) - shoreTarget), math.abs(heightAt(0, H + 400) - shoreTarget))
        check("west shore meets beach height", shore < 0.01, string.format("max deviation %.4f", shore))
        // The far-west cell (eye about 4 sky units up) must see the east range above the opaque horizon (-2 degrees).
        local best = -90
        for step = 0, 60 do
            for depth = 200, 2400, 100 do
                local u, v = W + depth, H * step / 60
                local distance = math.sqrt((u - span * 0.5) ^ 2 + (v - H * 0.5) ^ 2)
                best = math.max(best, math.deg(math.atan2(heightAt(u, v) - 4, distance)))
            end
        end
        check("east range visible from far west", best > 2, string.format("peak elevation %.2f deg", best))
        local camera = manifest.cameraVector
        local x, y = self:GetEdgeTranslation(manifest, midX, midY)
        local eastX = x + W + 100
        local northY = y + 100
        check("sky direction east is +X", eastX > camera.x + span, string.format("east sky x %.1f vs camera %.1f", eastX, camera.x))
        check("sky direction north is +Y", northY > camera.y + span, string.format("north sky y %.1f vs camera %.1f", northY, camera.y))
        // Sky fog must continue the city fog: never clearer at the cell boundary, and at least the city maximum beyond.
        if self.Manifest and self.Stats.state == "ready" then
            local boundary = ZM_SkyboxGeometry.GetFogBoundary(self.Manifest)
            local function density(fog, distance)
                return fog.maxDensity * math.Clamp((distance - fog.start) / math.max(fog.finish - fog.start, 1), 0, 1)
            end
            local worst = math.huge
            for _, world in ipairs({ { start = 800, finish = 3000, maxDensity = 0.65 }, { start = 600, finish = 2200, maxDensity = 0.72 },
                { start = 350, finish = 1450, maxDensity = 0.82 }, { start = 200, finish = 950, maxDensity = 0.9 },
                { start = 900, finish = 3000, maxDensity = 0.5 }, { start = 0, finish = 900, maxDensity = 1 } }) do
                local sky = self:GetSkyboxFog(world)
                for _, distance in ipairs({ boundary, boundary * 2, boundary * 3 }) do
                    worst = math.min(worst, density(sky, distance) - density(world, distance))
                end
            end
            check("sky fog never clearer than city fog", worst > -0.01, string.format("worst sky-minus-city density %.4f", worst))
        end
        local saved = { level = self.SceneryLight.level, self.SceneryLight[1], self.SceneryLight[2], self.SceneryLight[3] }
        local bright = self:UpdateSceneryLight({ [5] = Vector(0.79, 0.87, 0.97) })
        local brightTint = math.min(bright[1], bright[2], bright[3])
        local dark = self:UpdateSceneryLight({ [5] = Vector(0.226, 0.277, 0.132) })
        local darkLevel = dark.level
        self.SceneryLight.level, self.SceneryLight[1], self.SceneryLight[2], self.SceneryLight[3] = saved.level, saved[1], saved[2], saved[3]
        self.Stats.sceneryLight = math.Round(saved.level, 3)
        check("daylight cells keep profile fog colour", brightTint > 0.999, string.format("min tint %.3f", brightTint))
        check("dark cells darken fog", darkLevel < 0.7, string.format("level %.3f", darkLevel))
        return results, failures
    end

    return { edgeTerrain = edgeTerrain }
end
