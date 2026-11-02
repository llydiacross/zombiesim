// Skyline set dressing and cosmetic activity: detail props, wreck and rooftop fires, smoke plumes and tracers,
// plus the current cell's outer-edge fires.
return function(Skybox, helpers)
    local getConVarNumber = helpers.getConVarNumber
    local mapBasename = helpers.mapBasename
    local resolveCurrentCell = helpers.resolveCurrentCell
    local smoothstep = helpers.smoothstep
    local smokeMaterial = helpers.materials.smoke
    local fireMaterial = helpers.materials.fire
    local glowMaterial = helpers.materials.glow
    local tracerMaterial = helpers.materials.tracer

    // Set dressing: props are drawn while their projected radius/distance exceeds this, highest priority first, up to a
    // per-frame budget scaled by zombiesim_sky_props. Each prop is a separate model draw, so the budget bounds the cost.
    local detailAngularThreshold = 0.004
    local detailDrawBudget = 200
    // The scale matrix hides how small the models are on screen, so the engine would pick LOD0; force a low LOD.
    local detailModelLod = 3
    // Fire candidates come from the manifest (kind 1 wreck, kind 2 rooftop); a stable per-cell hash picks which burn.
    local fireChance = { 0.06, 0.08 }
    local firesPerCell = 2
    local maxFires = 32
    local smokePuffs = 9
    // Per kind (sky units / seconds): base lift, plume rise, sideways drift, puff start and growth, cycle, flame size.
    local fireStyles = {
        { lift = 1.5, rise = 40, drift = 24, size = 2.5, grow = 11, cycle = 14, flame = 2.2 },
        { lift = 0.5, rise = 85, drift = 48, size = 4.5, grow = 22, cycle = 20, flame = 4 }
    }
    local smokeDriftX, smokeDriftY = 0.944, 0.33

    // One shared, hidden model per detail prop type, scaled down to sky units; every placement re-poses it per draw.
    function Skybox:GetDetailModel(manifest, index)
        local models = self.DetailModels
        local cached = models[index]
        if cached ~= nil then return cached or nil end
        local modelPath = manifest.detail.models and manifest.detail.models[index + 1]
        local entity = type(modelPath) == "string" and file.Exists(modelPath, "GAME") and ClientsideModel(modelPath, RENDERGROUP_OPAQUE) or nil
        if not IsValid(entity) then
            models[index] = false
            return nil
        end
        entity:SetNoDraw(true)
        entity:SetLOD(detailModelLod)
        local scaleMatrix = Matrix()
        scaleMatrix:Scale(Vector(1, 1, 1) / manifest.scale)
        entity:EnableMatrix("RenderMultiply", scaleMatrix)
        local model = {
            entity = entity,
            radius = math.max(entity:GetModelRadius() or 0, 1) / manifest.scale,
            // Generated wrecks are placed on the road surface, so lift their origin by the model's floor offset.
            lift = -entity:OBBMins().z / manifest.scale
        }
        models[index] = model
        return model
    end

    // Stable 0..1 hash per cell and candidate, so a neighbour's fires stay put as the player moves between cells.
    local function fireHash(x, y, index, salt)
        local value = math.sin(x * 12.9898 + y * 78.233 + index * 37.719 + salt * 4.581) * 43758.5453
        return value - math.floor(value)
    end

    function Skybox:BuildActivitySites(manifest, gridX, gridY, radius)
        local candidates = {}
        local facadeCandidates = {}
        local reach = math.min(8, manifest.skylineRadius or radius)
        for dy = -reach, reach do
            for dx = -reach, reach do
                if math.max(math.abs(dx), math.abs(dy)) >= 1 then
                    local cell = ZM_World:GetCell(gridX + dx, gridY + dy)
                    local detail = cell and manifest.detail and manifest.detail.recipes and manifest.detail.recipes[mapBasename(cell.map)]
                    local rows = detail and detail.fires
                    if math.max(math.abs(dx), math.abs(dy)) >= 2 and type(rows) == "table" and #rows > 0 then
                        local seed = fireHash(gridX + dx, gridY + dy, 1, 41)
                        local row = rows[math.min(#rows, math.floor(seed * #rows) + 1)]
                        local position = manifest.cameraVector + Vector(dx * manifest.cellSpan + row[1],
                            -dy * manifest.cellSpan + row[2], row[3]) / manifest.scale
                        candidates[#candidates + 1] = { position = position, seed = seed, distance = dx * dx + dy * dy, x = dx, y = dy }
                    end
                    local paths = cell and manifest.towers and manifest.towers[mapBasename(cell.map)]
                    for _, path in ipairs(type(paths) == "table" and paths or {}) do
                        facadeCandidates[#facadeCandidates + 1] = { path = path, x = dx, y = dy, distance = dx * dx + dy * dy }
                    end
                end
            end
        end
        local function compareSites(a, b)
            if a.distance ~= b.distance then return a.distance < b.distance end
            if a.y ~= b.y then return a.y < b.y end
            if a.x ~= b.x then return a.x < b.x end
            return (a.path or "") < (b.path or "")
        end
        table.sort(candidates, compareSites)
        table.sort(facadeCandidates, compareSites)
        for _, candidate in ipairs(facadeCandidates) do
            if #self.FacadeFires >= 8 then break end
            local anchors = self:GetFacadeAnchors(candidate.path)
            if #anchors > 0 then
                local seed = fireHash(gridX + candidate.x, gridY + candidate.y, 1, 53)
                local anchor = anchors[math.min(#anchors, math.floor(seed * #anchors) + 1)]
                local origin = manifest.cameraVector + Vector(candidate.x * manifest.cellSpan, -candidate.y * manifest.cellSpan, 0) / manifest.scale
                self.FacadeFires[#self.FacadeFires + 1] = {
                    position = origin + anchor, style = fireStyles[2], phase = seed
                }
            end
        end
        for index = 1, math.min(24, #candidates) do
            self.ActivitySites[index] = candidates[index]
        end
        self.Stats.activitySites = #self.ActivitySites
        self.Stats.facadeFires = #self.FacadeFires
    end

    // Exported tower models have an identity root and already contain recipe transforms and sky scaling.
    // Use real wall triangles, not bounding boxes, which float outside stepped upper storeys.
    function Skybox:GetFacadeAnchors(path)
        if self.FacadeAnchors[path] then return self.FacadeAnchors[path] end
        local anchors = {}
        self.FacadeAnchors[path] = anchors
        local meshes = util.GetModelMeshes(path, 0)
        if type(meshes) ~= "table" then
            ErrorNoHalt("[ZombieSim] Cannot read tower facade mesh: " .. path .. "\n")
            return anchors
        end
        for _, part in ipairs(meshes) do
            local triangles = part.triangles or {}
            for index = 1, #triangles - 2, 3 do
                local a, b, c = triangles[index], triangles[index + 1], triangles[index + 2]
                local low = math.min(a.pos.z, b.pos.z, c.pos.z)
                local high = math.max(a.pos.z, b.pos.z, c.pos.z)
                if math.abs(a.normal.z) < 0.2 and high - low >= 24 then
                    local centre = (a.pos + b.pos + c.pos) / 3
                    if centre.z > 32 then
                        anchors[#anchors + 1] = centre + a.normal * 1.5
                    end
                end
            end
        end
        if #anchors == 0 then
            ErrorNoHalt("[ZombieSim] No tall vertical facade triangles in tower: " .. path .. "\n")
        end
        return anchors
    end

    function Skybox:AddNeighbourDetail(manifest, detail, origin, cellX, cellY)
        local scale = manifest.scale
        for _, row in ipairs(type(detail.props) == "table" and detail.props or {}) do
            local model = self:GetDetailModel(manifest, tonumber(row[1]) or -1)
            if model then
                local kind = tonumber(row[9]) or 0
                local position = origin + Vector(tonumber(row[2]) or 0, tonumber(row[3]) or 0, tonumber(row[4]) or 0) / scale
                if kind == 2 then position.z = position.z + model.lift end
                // Wrecks count double: they are what breaks the long road sightlines.
                local radius = model.radius * (kind > 0 and 2 or 1)
                table.insert(self.DetailProps, {
                    model = model,
                    position = position,
                    angles = Angle(tonumber(row[5]) or 0, tonumber(row[6]) or 0, tonumber(row[7]) or 0),
                    skin = tonumber(row[8]) or 0,
                    radius = radius,
                    priority = radius / math.max(position:Distance(manifest.cameraVector), 1)
                })
            else
                self.Stats.missingDetailModels = (self.Stats.missingDetailModels or 0) + 1
            end
        end
        local burning = 0
        for index, row in ipairs(type(detail.fires) == "table" and detail.fires or {}) do
            local kind = tonumber(row[4]) == 2 and 2 or 1
            if burning < firesPerCell and #self.Fires < maxFires and fireHash(cellX, cellY, index, kind) < fireChance[kind] then
                burning = burning + 1
                local style = fireStyles[kind]
                local position = origin + Vector(tonumber(row[1]) or 0, tonumber(row[2]) or 0, tonumber(row[3]) or 0) / scale
                position.z = position.z + style.lift
                table.insert(self.Fires, { position = position, style = style, phase = fireHash(cellY, cellX, index, 9) })
            end
        end
    end

    local propForward = Vector()

    function Skybox:DrawDetailProps(skyEye, maxDistance)
        local stats = self.Stats
        stats.frameProps = 0
        local density = getConVarNumber("zombiesim_sky_props", 1)
        local props = self.DetailProps
        if density <= 0 or not props or #props == 0 then return end
        local threshold = detailAngularThreshold
        local thresholdSqr = threshold * threshold
        local budget = math.floor(detailDrawBudget * math.Clamp(density, 0.1, 1))
        local maxDistanceSqr = maxDistance * maxDistance
        local forward = self.ViewForward or propForward
        local fx, fy, fz = forward.x, forward.y, forward.z
        local ex, ey, ez = skyEye.x, skyEye.y, skyEye.z
        local drawn = 0
        for _, prop in ipairs(props) do
            local position = prop.position
            local dx, dy, dz = position.x - ex, position.y - ey, position.z - ez
            local distanceSqr = dx * dx + dy * dy + dz * dz
            local radius = prop.radius
            if distanceSqr < maxDistanceSqr and radius * radius > thresholdSqr * distanceSqr and
                dx * fx + dy * fy + dz * fz > -radius then
                local entity = prop.model.entity
                if IsValid(entity) then
                    entity:SetRenderOrigin(position)
                    entity:SetRenderAngles(prop.angles)
                    entity:SetSkin(prop.skin)
                    entity:InvalidateBoneCache()
                    entity:SetupBones()
                    entity:DrawModel()
                    drawn = drawn + 1
                    if drawn >= budget then break end
                end
            end
        end
        stats.frameProps = drawn
    end

    local smokeOrder = {}
    local billboardVertex = Vector()
    local tracerStart, tracerEnd = Vector(), Vector()
    local tracerColor = Color(255, 187, 94)

    local function compareSmokeDistance(a, b)
        return a.distance > b.distance
    end

    // Camera-facing quad rotated in the view plane; right/up are the view's unit vectors.
    local function emitBillboard(x, y, z, size, cosine, sine, right, up, red, green, blue, alpha)
        local ax, ay, az = (right.x * cosine + up.x * sine) * size, (right.y * cosine + up.y * sine) * size, (right.z * cosine + up.z * sine) * size
        local bx, by, bz = (up.x * cosine - right.x * sine) * size, (up.y * cosine - right.y * sine) * size, (up.z * cosine - right.z * sine) * size
        billboardVertex:SetUnpacked(x - ax + bx, y - ay + by, z - az + bz)
        mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 0, 0) mesh.AdvanceVertex()
        billboardVertex:SetUnpacked(x + ax + bx, y + ay + by, z + az + bz)
        mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 1, 0) mesh.AdvanceVertex()
        billboardVertex:SetUnpacked(x + ax - bx, y + ay - by, z + az - bz)
        mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 1, 1) mesh.AdvanceVertex()
        billboardVertex:SetUnpacked(x - ax - bx, y - ay - by, z - az - bz)
        mesh.Position(billboardVertex) mesh.Color(red, green, blue, alpha) mesh.TexCoord(0, 0, 1) mesh.AdvanceVertex()
    end

    function Skybox:DrawActivity(manifest, skyEye, skyFog, fogColor)
        if ZM_WorldCapture and ZM_WorldCapture.Rendering then return end
        local stats = self.Stats
        stats.activityExplosions, stats.activityBursts, stats.activityBeams = 0, 0, 0
        stats.activityPreview = false
        if getConVarNumber("zombiesim_sky_fires", 1) <= 0 or not self.ViewForward or not self.ViewRight or not self.ViewUp or
            (ZM_WorldMap and ZM_WorldMap.Capturing) or (skyFog and skyFog.finish <= ZM_SkyboxGeometry.GetFogBoundary(manifest)) then return end
        local now = CurTime()
        local preview = (self.ActivityPreviewUntil or 0) > now
        local visible = self.ActivityVisible
        local count, explosions, bursts = 0, 0, 0
        for _, site in ipairs(self.ActivitySites) do
            local position = site.position
            local dx, dy, dz = position.x - skyEye.x, position.y - skyEye.y, position.z - skyEye.z
            if dx * self.ViewForward.x + dy * self.ViewForward.y + dz * self.ViewForward.z > 0 then
                local cycleTime = now + site.seed * 24
                local cycle = math.floor(cycleTime / 24)
                local age = cycleTime % 24
                local burst = fireHash(site.x, site.y, cycle, 47) > 0.55
                local scheduled = fireHash(site.x, site.y, cycle, 43) < 0.4
                if preview then
                    age = (now - self.ActivityPreviewStart) % 4
                    burst = count % 2 == 1
                    scheduled = true
                end
                if scheduled and age < (burst and 1.65 or 4) and (burst and bursts < 2 or not burst and explosions < 2) then
                    count = count + 1
                    local entry = visible[count] or {}
                    visible[count] = entry
                    entry.position, entry.age, entry.burst, entry.seed = position, age, burst, site.seed
                    if burst then bursts = bursts + 1 else explosions = explosions + 1 end
                    if count >= (preview and 2 or 4) then break end
                end
            end
        end
        for index = count + 1, #visible do visible[index] = nil end
        stats.activityPreview = preview
        stats.activityExplosions, stats.activityBursts = explosions, bursts
        render.FogMode(MATERIAL_FOG_LINEAR)
        render.FogStart(self:GetFogEdge(manifest) / manifest.scale)
        render.FogEnd(9 * manifest.cellSpan * math.sqrt(2) / manifest.scale)
        render.FogMaxDensity(math.Clamp(getConVarNumber("zombiesim_sky_tower_fog", 0.8), 0, 1))
        render.FogColor(fogColor[1], fogColor[2], fogColor[3])
        self:DrawFires(skyEye, true)
        local right, up = self.ViewRight, self.ViewUp
        if count > 0 then
            render.SetMaterial(glowMaterial)
            mesh.Begin(MATERIAL_QUADS, count)
            for _, entry in ipairs(visible) do
                local p, age = entry.position, entry.age
                local pulse = entry.burst and math.max(0, 1 - (age % 0.24) / 0.1) or math.max(0, 1 - age / 0.8)
                emitBillboard(p.x, p.y, p.z + 2, entry.burst and 4 or 12 + age * 10, 1, 0, right, up, 255, 165, 65, pulse * 220)
            end
            mesh.End()
        end
        if explosions > 0 then
            render.SetMaterial(smokeMaterial)
            mesh.Begin(MATERIAL_QUADS, explosions * 3)
            for _, entry in ipairs(visible) do
                if not entry.burst then
                    local p, age = entry.position, entry.age
                    local alpha = smoothstep(0, 0.35, age) * (1 - age / 4) * 160
                    for puff = 1, 3 do
                        emitBillboard(p.x + smokeDriftX * age * 6, p.y + smokeDriftY * age * 6,
                            p.z + age * 15 + puff * 4, 5 + age * 5 + puff, 1, 0, right, up, 45, 40, 35, alpha)
                    end
                end
            end
            mesh.End()
        end
        if bursts > 0 then
            render.SetMaterial(tracerMaterial)
            for _, entry in ipairs(visible) do
                if entry.burst then
                    for shot = 0, 3 do
                        local age = entry.age - shot * 0.24
                        if age >= 0 and age < 0.9 then
                            local p = entry.position
                            local drift = (entry.seed - 0.5) * age * 90
                            // Art ceiling below the existing 512-sky-unit room roof, including rooftop launch sites.
                            local velocity = math.max(0, math.min(420, (manifest.cameraVector.z + 460 - p.z - 2) / 0.9))
                            local height = age * velocity
                            tracerStart:SetUnpacked(p.x + drift, p.y + drift * 0.4, p.z + math.max(2, height - 32))
                            tracerEnd:SetUnpacked(p.x + drift + 2, p.y + drift * 0.4, p.z + height + 2)
                            tracerColor.a = (1 - age / 0.9) * 220
                            render.DrawBeam(tracerStart, tracerEnd, 0.8, 0, 1, tracerColor)
                            stats.activityBeams = stats.activityBeams + 1
                        end
                    end
                end
            end
        end
        if skyFog then
            render.FogStart(skyFog.start / manifest.scale)
            render.FogEnd(skyFog.finish / manifest.scale)
            render.FogMaxDensity(skyFog.maxDensity)
        else
            render.FogMode(MATERIAL_FOG_NONE)
        end
    end

    // Burning wrecks and rooftops: rising, spreading smoke plumes drifting with the clouds, flickering flames at the base.
    function Skybox:DrawFires(skyEye, facade, currentEdges)
        if ZM_WorldCapture and ZM_WorldCapture.Rendering then return end
        local stats = currentEdges and self.EdgeFireStats or self.Stats
        if not facade then
            stats.frameFires = 0
            stats.smokeQuads = 0
            stats.fireQuads = 0
        end
        local fires = currentEdges and self.EdgeFires or (facade and self.FacadeFires or self.Fires)
        local right, up = self.ViewRight, self.ViewUp
        if getConVarNumber("zombiesim_sky_fires", 1) <= 0 or not fires or #fires == 0 or not right or not up then return end
        local now = CurTime()
        local count = 0
        for fireIndex, fire in ipairs(fires) do
            local style = fire.style
            local base = fire.position
            for puff = 1, smokePuffs do
                local progress = (now / style.cycle + fire.phase + puff / smokePuffs) % 1
                local alpha = smoothstep(0, 0.12, progress) * (1 - progress) ^ 1.3 * 175
                if alpha > 2 then
                    local spread = progress ^ 1.4 * style.drift
                    local x = base.x + smokeDriftX * spread
                    local y = base.y + smokeDriftY * spread
                    local z = base.z + progress * style.rise
                    count = count + 1
                    local entry = smokeOrder[count] or {}
                    smokeOrder[count] = entry
                    local dx, dy, dz = x - skyEye.x, y - skyEye.y, z - skyEye.z
                    local rotation = fire.phase * 6.283 + puff * 1.7 + progress * 1.4 * (fireIndex % 2 == 0 and 1 or -1)
                    entry.x, entry.y, entry.z = x, y, z
                    entry.distance = dx * dx + dy * dy + dz * dz
                    entry.size = style.size + style.grow * progress ^ 0.8
                    entry.cosine, entry.sine = math.cos(rotation), math.sin(rotation)
                    entry.alpha = alpha
                    // Thick black smoke low down, lifting to a paler grey as it thins out.
                    entry.shade = 34 + 46 * progress
                end
            end
        end
        for index = count + 1, #smokeOrder do smokeOrder[index] = nil end
        stats.frameFires = stats.frameFires + #fires
        stats.smokeQuads = stats.smokeQuads + count

        // Flames first, so the base of the plume drifts over them.
        local flames = #fires * 3
        render.SetMaterial(glowMaterial)
        mesh.Begin(MATERIAL_QUADS, #fires)
        for _, fire in ipairs(fires) do
            local base = fire.position
            local flicker = 0.85 + 0.15 * math.sin(now * 7.3 + fire.phase * 40)
            emitBillboard(base.x, base.y, base.z, fire.style.flame * 2.6 * flicker, 1, 0, right, up, 255, 120, 40, 120 * flicker)
        end
        mesh.End()
        render.SetMaterial(fireMaterial)
        mesh.Begin(MATERIAL_QUADS, flames)
        for _, fire in ipairs(fires) do
            local base = fire.position
            local size = fire.style.flame
            for flame = 1, 3 do
                local wave = now * (5 + flame * 1.9) + fire.phase * 30 + flame * 2.1
                local flicker = 0.75 + 0.25 * math.sin(wave) * math.sin(wave * 0.61)
                local offset = (flame - 2) * size * 0.45
                emitBillboard(base.x + right.x * offset, base.y + right.y * offset, base.z + size * (0.35 + 0.25 * flame) * flicker,
                    size * flicker * (1.15 - flame * 0.15), 1, 0, right, up, 255, 200, 140, 235)
            end
        end
        mesh.End()
        stats.fireQuads = stats.fireQuads + flames + #fires
        if count <= 0 then return end
        table.sort(smokeOrder, compareSmokeDistance)
        render.SetMaterial(smokeMaterial)
        mesh.Begin(MATERIAL_QUADS, count)
        for index = 1, count do
            local entry = smokeOrder[index]
            local shade = entry.shade
            emitBillboard(entry.x, entry.y, entry.z, entry.size, entry.cosine, entry.sine, right, up, shade, shade * 0.97, shade * 0.94, entry.alpha)
        end
        mesh.End()
    end

    function Skybox:DrawCurrentEdgeFires()
        self.EdgeFireStats = self.EdgeFireStats or {}
        local stats = self.EdgeFireStats
        stats.frameFires, stats.smokeQuads, stats.fireQuads = 0, 0, 0
        stats.enabled = getConVarNumber("zombiesim_sky_fires", 1) > 0
        if getConVarNumber("zombiesim_sky_fires", 1) <= 0 then return end
        if ZM_LauncherMenu and ZM_LauncherMenu.Active then return end
        local manifest = self:GetManifest()
        local cell, _, gridX, gridY = resolveCurrentCell()
        if not manifest or manifest.schemaVersion ~= 2 or not cell then
            self.EdgeFires, self.EdgeFireKey = {}, nil
            stats.candidates, stats.selected = 0, 0
            stats.error = nil
            return
        end
        local key = manifest.templatePlanSha256 .. ":" .. gridX .. ":" .. gridY
        if key ~= self.EdgeFireKey then
            self.EdgeFireKey = key
            self.EdgeFires = {}
            local detail = manifest.detail and manifest.detail.recipes and manifest.detail.recipes[mapBasename(cell.map)]
            if not detail or type(detail.edgeFires) ~= "table" then
                stats.candidates, stats.selected = 0, 0
                stats.error = "current-edge fire anchors missing; rebuild the skyline manifest"
                ErrorNoHalt("[ZombieSim] " .. stats.error .. "\n")
                return
            end
            stats.error = nil
            stats.candidates = #detail.edgeFires
            local sourceStyle = fireStyles[2]
            local style = { cycle = sourceStyle.cycle }
            for _, field in ipairs({"lift", "rise", "drift", "size", "grow", "flame"}) do
                style[field] = sourceStyle[field] * manifest.scale
            end
            for index, row in ipairs(ZM_SkyboxGeometry.SelectEdgeFireAnchors(detail.edgeFires, gridX, gridY)) do
                self.EdgeFires[#self.EdgeFires + 1] = {
                    position = Vector(row[1], row[2], row[3] + style.lift),
                    style = style, phase = fireHash(gridX, gridY, index, 19)
                }
            end
            stats.selected = #self.EdgeFires
        end
        local started = SysTime()
        self:DrawFires(self.ViewOrigin, false, true)
        stats.drawMilliseconds = (SysTime() - started) * 1000
    end
end
