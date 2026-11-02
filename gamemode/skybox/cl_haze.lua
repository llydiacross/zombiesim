// Skybox ground haze: concentric translucent shells around the sky eye that skyscrapers rise out of. Each shell is
// depth tested, so scenery is hazed only by the shells in front of it (aerial perspective by distance), and the first
// shell starts just past the playable boundary so the nearest neighbours stay clear. The mesh is static per cell,
// radius and quality; weather density, fog colour and fog-top height change per frame through $alpha, $color and the
// model matrix only. Cell radiation bakes a sickly yellow-green tint and extra density into the shell columns.
return function(Skybox, helpers)
    local getConVarNumber = helpers.getConVarNumber

    local Haze = Skybox.Haze or {}
    Skybox.Haze = Haze
    Haze.Stats = Haze.Stats or {}

    local meshVersion = 2
    // Shell count/segments per quality tier; low keeps a cheap simplified layer.
    local qualityTiers = {
        low = { shells = 4, segments = 24 },
        high = { shells = 8, segments = 48 }
    }
    // Height profile in sky units relative to the street surface (scaled by the weather height), with the alpha
    // factor at each row. The bottom row sits below the street to cover the ground seam; the top row fades out.
    local baseTop = 30
    local rows = { { -0.8, 1 }, { 0, 1 }, { 0.3, 0.72 }, { 0.65, 0.3 }, { 1, 0 } }
    local streetLift = 2
    local maxOpacity = 0.92
    local radiationColor = { 255, 165, 80 }
    // Radiated cells: a distant fire glow low on the horizon, brightest in a few irregular hotspots.
    local glowRows = { { -1.5, 1 }, { 1.5, 0.75 }, { 5, 0.3 }, { 10, 0 } }
    local glowColor = { 255, 105, 30 }
    local glowStrength = 0.75
    local glowMaterial = CreateMaterial("zombiesim_skybox_glow_v1", "UnlitGeneric", {
        ["$basetexture"] = "vgui/white",
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$additive"] = 1,
        ["$nocull"] = 1,
        ["$nofog"] = 1
    })
    Haze.GlowMaterial = glowMaterial
    local hazeMaterial = CreateMaterial("zombiesim_skybox_haze_v1", "UnlitGeneric", {
        ["$basetexture"] = "vgui/white",
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$translucent"] = 1,
        ["$nocull"] = 1,
        ["$nofog"] = 1
    })
    Haze.Material = hazeMaterial
    local hazeColor = Vector(1, 1, 1)
    local hazeMatrix = Matrix()
    local hazeScale = Vector(1, 1, 1)
    local hazeOrigin = Vector()

    // zombiesim_sky_haze is owned by cl_quality.lua with the other preset-controlled settings.
    local function getTier()
        local value = getConVarNumber("zombiesim_sky_haze", 1)
        if value <= 0 then return nil end
        return value < 0.75 and "low" or "high"
    end

    // Cheap deterministic variation so the shell is not a uniform ring.
    local function columnVariation(angle, shell)
        return 0.86 + 0.14 * math.sin(angle * 3 + shell * 1.7) * math.cos(angle * 5 - shell * 0.9)
    end

    local function sampleRadiation(manifest, gridX, gridY, worldX, worldY)
        local dx = math.Round(worldX / manifest.cellSpan)
        // Grid north (y - 1) is +Y in Hammer space.
        local dy = -math.Round(worldY / manifest.cellSpan)
        local cell = ZM_World:GetCell(gridX + dx, gridY + dy)
        if not cell or cell.empty == true then return 0 end
        return math.Clamp(ZM_World:GetRadiationIntensity(cell) or 0, 0, 1)
    end

    function Haze:Destroy()
        if self.Mesh then self.Mesh:Destroy() end
        self.Mesh = nil
        self.Key = nil
    end

    // Builds the outermost shell first so the single mesh draws back to front.
    function Haze:Build(manifest, gridX, gridY, tierName)
        local radius = math.max(Skybox:GetRadius(manifest), 1)
        local key = table.concat({ meshVersion, tostring(Skybox.ManifestProfile), gridX, gridY, radius,
            manifest.neighbourRadius or radius, manifest.cellSpan, manifest.scale, tierName }, ":")
        if key == self.Key and self.Mesh then return self.Mesh end
        self:Destroy()
        self.Key = key
        local stats = self.Stats
        local tier = qualityTiers[tierName]
        local scale = manifest.scale
        local inner = ZM_SkyboxGeometry.GetFogBoundary(manifest) / scale * 1.05
        local outer = math.max(inner * 2, ((manifest.neighbourRadius or radius) + 0.5) * manifest.cellSpan / scale)
        local shells, segments = tier.shells, tier.segments
        local quads = shells * segments * (#rows - 1)
        stats.quads = quads
        stats.shells = shells
        stats.segments = segments
        stats.innerRadius = inner
        stats.outerRadius = outer
        if quads <= 0 then return nil end

        // Target opacity rises with distance; each shell supplies the step from the previous shell's opacity.
        local radii, alphas = {}, {}
        local previous = 0
        for shell = 1, shells do
            local fraction = shell / shells
            local target = maxOpacity * (1 - math.exp(-2.6 * fraction)) / (1 - math.exp(-2.6))
            radii[shell] = inner * (outer / inner) ^ fraction
            alphas[shell] = math.Clamp(1 - (1 - target) / math.max(1 - previous, 0.001), 0, 1)
            previous = target
        end

        // Radiation and colour per column are computed before mesh.Begin so nothing can error inside it.
        local columns = {}
        local maxRadiation = 0
        for shell = shells, 1, -1 do
            local shellColumns = {}
            for segment = 0, segments do
                local angle = segment / segments * math.pi * 2
                local x, y = math.cos(angle) * radii[shell], math.sin(angle) * radii[shell]
                local radiation = sampleRadiation(manifest, gridX, gridY, x * scale, y * scale)
                maxRadiation = math.max(maxRadiation, radiation)
                local tint = radiation * 0.85
                local alpha = alphas[shell] * columnVariation(angle, shell) * (1 + 1.0 * radiation)
                shellColumns[segment] = {
                    x = x, y = y,
                    r = Lerp(tint, 255, radiationColor[1]),
                    g = Lerp(tint, 255, radiationColor[2]),
                    b = Lerp(tint, 255, radiationColor[3]),
                    a = math.Clamp(alpha, 0, 1) * 255
                }
            end
            columns[#columns + 1] = shellColumns
        end
        stats.maxRadiation = maxRadiation

        local position = Vector()
        local imesh = Mesh()
        mesh.Begin(imesh, MATERIAL_QUADS, quads)
        for _, shellColumns in ipairs(columns) do
            for segment = 0, segments - 1 do
                local a, b = shellColumns[segment], shellColumns[segment + 1]
                for row = 1, #rows - 1 do
                    local low, high = rows[row], rows[row + 1]
                    local lowZ, highZ = low[1] * baseTop, high[1] * baseTop
                    position:SetUnpacked(a.x, a.y, lowZ)
                    mesh.Position(position) mesh.Color(a.r, a.g, a.b, a.a * low[2]) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
                    position:SetUnpacked(b.x, b.y, lowZ)
                    mesh.Position(position) mesh.Color(b.r, b.g, b.b, b.a * low[2]) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
                    position:SetUnpacked(b.x, b.y, highZ)
                    mesh.Position(position) mesh.Color(b.r, b.g, b.b, b.a * high[2]) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
                    position:SetUnpacked(a.x, a.y, highZ)
                    mesh.Position(position) mesh.Color(a.r, a.g, a.b, a.a * high[2]) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
                end
            end
        end
        mesh.End()
        self.Mesh = imesh
        stats.builds = (stats.builds or 0) + 1
        return imesh
    end

    // Weather and current-cell radiation set how thick and how tall the haze is; eased so changes roll in rather than
    // snap. The radiation value is already eased by the layered fog settings.
    function Haze:UpdateWeather()
        local atmosphere = ZM_Atmosphere
        local weather = atmosphere and atmosphere.Weather or "clear"
        local storm = atmosphere and atmosphere.StormIntensity or 0
        local winter = atmosphere and atmosphere.WinterBlend or 0
        local settings = atmosphere and atmosphere.GetFogSettings and atmosphere:GetFogSettings()
        local radiation = math.Clamp(settings and settings.radiation or 0, 0, 1)
        local density = weather == "rain" and 0.85 or weather == "snow" and 0.8 or 0.6
        density = math.Clamp(density + storm * 0.35 + winter * 0.1, 0, 1)
        local height = 1 + (weather == "rain" and 0.3 or weather == "snow" and 0.25 or 0) + storm * 0.6
        local now = RealTime()
        local delta = math.Clamp(now - (self.WeatherTime or now), 0, 1)
        self.WeatherTime = now
        self.Density = self.Density and math.Approach(self.Density, density, delta * 0.05) or density
        self.Height = self.Height and math.Approach(self.Height, height, delta * 0.05) or height
        self.Radiation = radiation
        return math.Clamp(self.Density + radiation * 0.4, 0, 1), self.Height + radiation * 1.2
    end

    function Haze:DestroyGlow()
        if self.GlowMesh then self.GlowMesh:Destroy() end
        self.GlowMesh = nil
        self.GlowKey = nil
    end

    local function glowVariation(angle)
        local hot = math.max(0, math.sin(angle * 2 + 1.3)) ^ 3 + 0.6 * math.max(0, math.sin(angle * 5 - 0.7)) ^ 4
        return math.Clamp(0.35 + 0.65 * hot, 0, 1)
    end

    // A static ring just inside the dome; per-frame strength is only the material $alpha.
    function Haze:BuildGlow(radius, tierName)
        local key = table.concat({ meshVersion, radius, tierName }, ":")
        if key == self.GlowKey and self.GlowMesh then return self.GlowMesh end
        self:DestroyGlow()
        self.GlowKey = key
        local segments = qualityTiers[tierName].segments
        local quads = segments * (#glowRows - 1)
        if quads <= 0 then return nil end
        local ring = radius * 0.97
        local columns, heights = {}, {}
        for segment = 0, segments do
            local angle = segment / segments * math.pi * 2
            columns[segment] = { x = math.cos(angle) * ring, y = math.sin(angle) * ring, a = glowVariation(angle) * 255 }
        end
        for index, row in ipairs(glowRows) do heights[index] = ring * math.tan(math.rad(row[1])) end
        local position = Vector()
        local imesh = Mesh()
        mesh.Begin(imesh, MATERIAL_QUADS, quads)
        for segment = 0, segments - 1 do
            local a, b = columns[segment], columns[segment + 1]
            for row = 1, #glowRows - 1 do
                local lowZ, highZ = heights[row], heights[row + 1]
                local lowAlpha, highAlpha = glowRows[row][2], glowRows[row + 1][2]
                position:SetUnpacked(a.x, a.y, lowZ)
                mesh.Position(position) mesh.Color(255, 255, 255, a.a * lowAlpha) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
                position:SetUnpacked(b.x, b.y, lowZ)
                mesh.Position(position) mesh.Color(255, 255, 255, b.a * lowAlpha) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
                position:SetUnpacked(b.x, b.y, highZ)
                mesh.Position(position) mesh.Color(255, 255, 255, b.a * highAlpha) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
                position:SetUnpacked(a.x, a.y, highZ)
                mesh.Position(position) mesh.Color(255, 255, 255, a.a * highAlpha) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
            end
        end
        mesh.End()
        self.GlowMesh = imesh
        self.Stats.glowQuads = quads
        self.Stats.glowBuilds = (self.Stats.glowBuilds or 0) + 1
        return imesh
    end

    // Drawn after the dome so towers occlude it; slowly breathes so the fires feel alive.
    function Haze:DrawGlow(radius, skyEye)
        local stats = self.Stats
        stats.glowFrameDraws = 0
        local tierName = getTier()
        local settings = ZM_Atmosphere and ZM_Atmosphere.GetFogSettings and ZM_Atmosphere:GetFogSettings()
        local radiation = math.Clamp(settings and settings.radiation or 0, 0, 1)
        local alpha = math.Clamp(radiation * glowStrength * (0.9 + 0.1 * math.sin(RealTime() * 0.7)), 0, 1)
        stats.glowAlpha = alpha
        if not tierName then self:DestroyGlow() end
        if not tierName or alpha <= 0.002 then return end
        local imesh = self:BuildGlow(radius, tierName)
        if not imesh then return end
        hazeColor:SetUnpacked(glowColor[1] / 255, glowColor[2] / 255, glowColor[3] / 255)
        glowMaterial:SetVector("$color", hazeColor)
        glowMaterial:SetFloat("$alpha", alpha)
        hazeMatrix:Identity()
        hazeMatrix:SetTranslation(skyEye)
        cam.PushModelMatrix(hazeMatrix)
        render.SetMaterial(glowMaterial)
        render.OverrideDepthEnable(true, false)
        imesh:Draw()
        render.OverrideDepthEnable(false, false)
        cam.PopModelMatrix()
        stats.glowFrameDraws = 1
    end

    function Haze:Draw(manifest, skyEye, fogColor)
        local stats = self.Stats
        stats.frameDraws = 0
        local tierName = getTier()
        stats.tier = tierName or "off"
        if not tierName then
            self:Destroy()
            return
        end
        local gridX, gridY = Skybox.GridX, Skybox.GridY
        if not gridX or not gridY then return end
        local imesh = self:Build(manifest, gridX, gridY, tierName)
        if not imesh then return end
        local density, height = self:UpdateWeather()
        local amount = math.Clamp(getConVarNumber("zombiesim_sky_haze_density", 1), 0, 2)
        local alpha = math.Clamp(density * amount, 0, 1)
        stats.alpha = alpha
        stats.height = height * baseTop
        if alpha <= 0.002 then return end

        hazeColor:SetUnpacked((fogColor[1] or 128) / 255, (fogColor[2] or 128) / 255, (fogColor[3] or 128) / 255)
        hazeMaterial:SetVector("$color", hazeColor)
        hazeMaterial:SetFloat("$alpha", alpha)
        hazeOrigin:SetUnpacked(skyEye.x, skyEye.y, manifest.cameraVector.z + streetLift)
        hazeMatrix:Identity()
        hazeMatrix:SetTranslation(hazeOrigin)
        hazeScale:SetUnpacked(1, 1, height)
        hazeMatrix:Scale(hazeScale)
        cam.PushModelMatrix(hazeMatrix)
        render.SetMaterial(hazeMaterial)
        render.OverrideDepthEnable(true, false)
        imesh:Draw()
        render.OverrideDepthEnable(false, false)
        cam.PopModelMatrix()
        stats.frameDraws = 1
        stats.draws = (stats.draws or 0) + 1
    end

    function Haze:GetDiagnostics()
        local stats = self.Stats
        local texture = hazeMaterial:GetTexture("$basetexture")
        return {
            tier = stats.tier,
            builds = stats.builds or 0,
            quads = stats.quads or 0,
            shells = stats.shells,
            segments = stats.segments,
            innerRadius = stats.innerRadius,
            outerRadius = stats.outerRadius,
            maxRadiation = stats.maxRadiation,
            alpha = stats.alpha,
            height = stats.height,
            draws = stats.draws or 0,
            frameDraws = stats.frameDraws or 0,
            glowAlpha = stats.glowAlpha or 0,
            glowQuads = stats.glowQuads or 0,
            glowBuilds = stats.glowBuilds or 0,
            glowFrameDraws = stats.glowFrameDraws or 0,
            glowMaterialError = glowMaterial:IsError(),
            meshValid = self.Mesh ~= nil,
            materialError = hazeMaterial:IsError(),
            textureWidth = texture and texture:Width() or 0
        }
    end

    return Haze
end
