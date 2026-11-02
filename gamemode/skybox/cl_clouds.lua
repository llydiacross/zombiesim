// Horizon dome and drifting cloud deck in the 3D skybox.
return function(Skybox, helpers)
    local getConVarNumber = helpers.getConVarNumber
    local smoothstep = helpers.smoothstep
    local cloudMaterial = helpers.materials.cloud

    local domeSegments = 48
    // Elevation (degrees above the eye) and alpha for each horizon-wall ring; below the eye the wall is opaque.
    local domeRings = {
        { elevation = -40, alpha = 1 },
        { elevation = 0, alpha = 1 },
        { elevation = 3, alpha = 0.9 },
        { elevation = 7, alpha = 0.55 },
        { elevation = 12, alpha = 0.18 },
        { elevation = 18, alpha = 0 }
    }
    local skylineDomeRings = {
        { elevation = -40, alpha = 1 },
        { elevation = -2, alpha = 1 },
        { elevation = 0, alpha = 0.45 },
        { elevation = 3, alpha = 0.12 },
        { elevation = 7, alpha = 0.05 },
        { elevation = 18, alpha = 0 }
    }
    local cloudClusterCount = 72
    local cloudSeed = 7331
    // Sky-space units (1 sky unit = manifest.scale world units).
    local cloudBaseHeight = 300
    local cloudHeightRange = 70
    // Drift is integrated per frame so storm speed-ups never jump the deck; storms blow up to 2.5x faster.
    local cloudDriftSpeed = 7
    local cloudStormDriftBoost = 1.5
    local cloudDriftDirectionX = 0.94
    local cloudDriftDirectionY = 0.34
    // Puffs turn slowly in place (radians per second) so clusters billow as they cross the sky.
    local cloudPuffSpinRate = 0.05

    // Builds the horizon wall around the origin, in sky units; it is translated to the sky eye when drawn.
    function Skybox:BuildDome(radius, skyline)
        local haze = math.Clamp(getConVarNumber("zombiesim_sky_horizon_haze", 0.5), 0, 1.5)
        if self.DomeMesh and self.DomeRadius == radius and self.DomeSkyline == skyline and self.DomeHaze == haze then return end
        if self.DomeMesh then self.DomeMesh:Destroy() end
        self.DomeMesh = nil
        self.DomeRadius = radius
        self.DomeSkyline = skyline
        self.DomeHaze = haze
        local rings = skyline and skylineDomeRings or domeRings

        local quads = domeSegments * (#rings - 1)
        if quads <= 0 then return end
        local ringZ = {}
        for index, ring in ipairs(rings) do
            ringZ[index] = radius * math.tan(math.rad(ring.elevation))
        end
        local corners = {}
        for segment = 0, domeSegments do
            local angle = segment / domeSegments * math.pi * 2
            corners[segment] = { math.cos(angle) * radius, math.sin(angle) * radius }
        end
        local position = Vector()
        local domeMesh = Mesh()
        mesh.Begin(domeMesh, MATERIAL_QUADS, quads)
        for ringIndex = 1, #rings - 1 do
            local lowZ, highZ = ringZ[ringIndex], ringZ[ringIndex + 1]
            local lowAlpha = math.min(1, rings[ringIndex].alpha * (rings[ringIndex].elevation >= 0 and haze or 1)) * 255
            local highAlpha = math.min(1, rings[ringIndex + 1].alpha * (rings[ringIndex + 1].elevation >= 0 and haze or 1)) * 255
            for segment = 0, domeSegments - 1 do
                local a, b = corners[segment], corners[segment + 1]
                position:SetUnpacked(a[1], a[2], lowZ)
                mesh.Position(position) mesh.Color(255, 255, 255, lowAlpha) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
                position:SetUnpacked(b[1], b[2], lowZ)
                mesh.Position(position) mesh.Color(255, 255, 255, lowAlpha) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
                position:SetUnpacked(b[1], b[2], highZ)
                mesh.Position(position) mesh.Color(255, 255, 255, highAlpha) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
                position:SetUnpacked(a[1], a[2], highZ)
                mesh.Position(position) mesh.Color(255, 255, 255, highAlpha) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
            end
        end
        mesh.End()
        self.DomeMesh = domeMesh
        self.Stats.domeQuads = quads
    end

    // Deterministic cloud clusters spread over a square that wraps around the sky camera.
    function Skybox:BuildClouds(fieldHalf)
        if self.Clouds and self.CloudFieldHalf == fieldHalf then return end
        self.CloudFieldHalf = fieldHalf
        local state = cloudSeed
        local function random()
            state = (state * 1103515245 + 12345) % 2147483648
            return state / 2147483648
        end
        local clouds = {}
        for index = 1, cloudClusterCount do
            local cluster = {
                x = (random() * 2 - 1) * fieldHalf,
                y = (random() * 2 - 1) * fieldHalf,
                z = cloudBaseHeight + random() * cloudHeightRange,
                threshold = random(),
                shade = 0.85 + random() * 0.15,
                puffs = {}
            }
            local spread = 50 + random() * 70
            for puff = 1, 4 + math.floor(random() * 5) do
                table.insert(cluster.puffs, {
                    x = (random() * 2 - 1) * spread,
                    y = (random() * 2 - 1) * spread * 0.7,
                    z = (random() * 2 - 1) * 10,
                    size = 60 + random() * 90,
                    rotation = random() * math.pi * 2,
                    spin = (random() * 2 - 1) * cloudPuffSpinRate
                })
            end
            clouds[index] = cluster
        end
        self.Clouds = clouds
        self.CloudOrder = {}
    end

    // Weather-driven cloud cover (0..1), eased so weather changes roll in rather than pop.
    function Skybox:UpdateCloudCover()
        local atmosphere = ZM_Atmosphere
        local weather = atmosphere and atmosphere.Weather or "clear"
        local storm = atmosphere and atmosphere.StormIntensity or 0
        local target = weather == "rain" and 0.85 or weather == "snow" and 0.75 or 0.55
        target = math.Clamp(target + storm * 0.3, 0, 1)
        local now = RealTime()
        local delta = math.Clamp(now - (self.CloudCoverTime or now), 0, 1)
        self.CloudCoverTime = now
        self.CloudCover = self.CloudCover and math.Approach(self.CloudCover, target, delta * 0.05) or target
        self.CloudStorm = storm
        local speed = cloudDriftSpeed * (1 + cloudStormDriftBoost * storm)
        self.CloudDriftX = (self.CloudDriftX or 0) + delta * speed * cloudDriftDirectionX
        self.CloudDriftY = (self.CloudDriftY or 0) + delta * speed * cloudDriftDirectionY
        self.CloudSpinTime = (self.CloudSpinTime or 0) + delta
        self.CloudSpeed = speed
        return self.CloudCover
    end

    local cloudVertex = Vector()

    local function compareCloudDistance(a, b)
        return a.distance > b.distance
    end

    function Skybox:DrawClouds(manifest, skyEye, fogColor, fogStart, fogEnd)
        local fieldHalf = self:GetFogEdge(manifest) / manifest.scale * 1.15
        self:BuildClouds(fieldHalf)
        local cover = self:UpdateCloudCover()
        local storm = self.CloudStorm or 0
        local camera = manifest.cameraVector
        local driftX, driftY = self.CloudDriftX or 0, self.CloudDriftY or 0
        local spinTime = self.CloudSpinTime or 0
        local span = fieldHalf * 2
        local red, green, blue = fogColor[1] or 128, fogColor[2] or 128, fogColor[3] or 128
        // Clouds are lit from above: fog colour lifted toward white, dimmed in storms and in dark atmospheres.
        local luminance = (red * 0.3 + green * 0.59 + blue * 0.11) / 255
        local brightness = math.Clamp(luminance * 1.7, 0.3, 1) * (1 - 0.45 * storm)
        local baseRed = Lerp(0.5, red, 245 * brightness)
        local baseGreen = Lerp(0.5, green, 245 * brightness)
        local baseBlue = Lerp(0.5, blue, 248 * brightness)
        local order = self.CloudOrder
        local count = 0
        local quads = 0
        for _, cluster in ipairs(self.Clouds) do
            local visibility = math.Clamp((cover - cluster.threshold) / 0.12, 0, 1)
            if visibility > 0 then
                // Wrap the drifting cluster into the field square centred on the sky camera.
                local x = (cluster.x + driftX + fieldHalf) % span - fieldHalf + camera.x
                local y = (cluster.y + driftY + fieldHalf) % span - fieldHalf + camera.y
                local z = camera.z + cluster.z
                local dx, dy, dz = x - skyEye.x, y - skyEye.y, z - skyEye.z
                local horizontal = math.sqrt(dx * dx + dy * dy)
                local edge = 1 - smoothstep(fieldHalf * 0.55, fieldHalf * 0.95, horizontal)
                local distance = math.sqrt(horizontal * horizontal + dz * dz)
                local fogAmount = math.Clamp((distance - fogStart) / math.max(fogEnd - fogStart, 1), 0, 1)
                // Clouds sink into the horizon wall rather than drawing over it.
                local elevation = smoothstep(0.03, 0.17, dz / math.max(distance, 1))
                local alpha = visibility * edge * elevation * (1 - 0.65 * fogAmount) * (0.7 + 0.3 * cover) * 255
                if alpha > 1 then
                    count = count + 1
                    local entry = order[count] or {}
                    order[count] = entry
                    entry.cluster = cluster
                    entry.x, entry.y, entry.z = x, y, z
                    entry.distance = distance
                    entry.alpha = alpha
                    entry.red = Lerp(fogAmount, baseRed * cluster.shade, red)
                    entry.green = Lerp(fogAmount, baseGreen * cluster.shade, green)
                    entry.blue = Lerp(fogAmount, baseBlue * cluster.shade, blue)
                    quads = quads + #cluster.puffs
                end
            end
        end
        for index = count + 1, #order do order[index] = nil end
        self.Stats.cloudClusters = count
        self.Stats.cloudQuads = quads
        self.Stats.cloudCover = cover
        if quads <= 0 then return end
        table.sort(order, compareCloudDistance)

        render.SetMaterial(cloudMaterial)
        mesh.Begin(MATERIAL_QUADS, quads)
        for index = 1, count do
            local entry = order[index]
            local r, g, b, a = entry.red, entry.green, entry.blue, entry.alpha
            for _, puff in ipairs(entry.cluster.puffs) do
                local px, py, pz = entry.x + puff.x, entry.y + puff.y, entry.z + puff.z
                local angle = puff.rotation + puff.spin * spinTime
                local c, s = math.cos(angle) * puff.size, math.sin(angle) * puff.size
                cloudVertex:SetUnpacked(px - c + s, py - s - c, pz)
                mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
                cloudVertex:SetUnpacked(px + c + s, py + s - c, pz)
                mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
                cloudVertex:SetUnpacked(px + c - s, py + s + c, pz)
                mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
                cloudVertex:SetUnpacked(px - c - s, py - s + c, pz)
                mesh.Position(cloudVertex) mesh.Color(r, g, b, a) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
            end
        end
        mesh.End()
    end
end
