// Optional client backdrop only; baked lighting, weather and the 3D skyline stay authoritative.
ZM_SkyPalettes = ZM_SkyPalettes or {}
local Palettes = ZM_SkyPalettes
if Palettes.Meshes then
    for _, entry in ipairs(Palettes.Meshes) do entry.mesh:Destroy() end
end
Palettes.Meshes = {}
Palettes.ActiveKey = nil
Palettes.Preview = nil
Palettes.Draws = 0
Palettes.Failure = nil
Palettes.NextUpdate = 0

local choice = CreateClientConVar("zombiesim_sky_palette", "default", true, false,
    "Personal cosmetic sky: default, natural, cinematic or an individual sky id. Does not relight the map.")
local origin = Vector(0, 0, 0)
local identity = Matrix()
local white = Color(255, 255, 255)
local gradientMaterial = CreateMaterial("zombiesim_sky_palette_gradient_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white", ["$vertexcolor"] = 1, ["$nocull"] = 1, ["$nofog"] = 1
})
function Palettes:Resolve(palette, context)
    if palette == "default" then return nil end
    if type(palette) == "string" and self.Entries[palette] then return palette end
    local profile = self:GetProfile(palette)
    if not profile then return nil, "unknown sky palette: " .. tostring(palette) end
    if not table.HasValue(self.ContextOrder, context) then
        return nil, "unknown atmosphere context: " .. tostring(context)
    end
    local id = profile.contexts[context]
    if id == "default" then return nil end
    if not self.Entries[id] then return nil, "palette sky unavailable: " .. tostring(id) end
    return id
end

function Palettes:GetChoices()
    local entries = { { id = "default", label = "Default map sky", automatic = true, custom = false } }
    local function addProfile(id, custom)
        local profile = self:GetProfile(id)
        local failure
        for _, context in ipairs(self.ContextOrder) do
            local ok, message = self:GetAvailability(profile.contexts[context])
            if not ok then failure = message break end
        end
        entries[#entries + 1] = { id = id, label = profile.label, automatic = true,
            custom = custom, contexts = profile.contexts, unavailable = failure }
    end
    for _, id in ipairs(self.ProfileOrder) do addProfile(id, false) end
    for _, id in ipairs(table.GetKeys(self.CustomStore.profiles)) do
        addProfile(id, true)
    end
    local individuals = {}
    for id, definition in pairs(self.Entries) do
        local ok, failure = self:GetAvailability(id)
        individuals[#individuals + 1] = { id = id, label = definition.label, context = definition.context,
            unavailable = not ok and failure or nil, credit = definition.credit }
    end
    table.sort(entries, function(a, b)
        if a.custom and b.custom then return a.label == b.label and a.id < b.id or a.label < b.label end
        if a.custom ~= b.custom then return not a.custom end
        local order = { default = 0 }
        for index, id in ipairs(self.ProfileOrder) do order[id] = index end
        return order[a.id] < order[b.id]
    end)
    table.sort(individuals, function(a, b) return a.label < b.label end)
    for _, entry in ipairs(individuals) do entries[#entries + 1] = entry end
    return entries
end

function Palettes:GetChoiceLabel()
    local id = choice:GetString()
    if id == "default" then return "Default map sky" end
    local profile = self:GetProfile(id)
    if profile then return profile.label .. " (automatic)" end
    return self.Entries[id] and self.Entries[id].label or "Unknown sky choice"
end

function Palettes:ValidateSelection(id)
    local profile = self:GetProfile(id)
    local ids = {}
    if profile then
        for _, context in ipairs(self.ContextOrder) do ids[#ids + 1] = profile.contexts[context] end
    else
        ids[1] = id
    end
    for _, sky in ipairs(ids) do
        local ok, failure = self:GetAvailability(sky)
        if not ok then return false, failure end
        if sky ~= "default" and self.Entries[sky].mounted then
            local materials
            materials, failure = self:GetFaceMaterials(sky)
            if not materials then return false, failure end
        end
    end
    return true
end

function Palettes:Select(id)
    local ok, failure = self:ValidateSelection(id)
    if not ok then
        ErrorNoHalt("[ZombieSim] Sky selection rejected: " .. failure .. "\n")
        return false, failure
    end
    self.Preview = nil
    choice:SetString(id)
    self:Update()
    return true
end

function Palettes:GradientColor(id, elevation, horizon)
    local top = self.Entries[id].top
    local blend = math.max(0, math.sin(elevation)) ^ 0.65
    return Lerp(blend, horizon[1], top[1]), Lerp(blend, horizon[2], top[2]),
        Lerp(blend, horizon[3], top[3])
end

function Palettes:GetContext()
    local atmosphere = ZM_Atmosphere
    local level = ZM_Skybox and ZM_Skybox.SceneryLight and ZM_Skybox.SceneryLight.level or 1
    local fog = atmosphere and atmosphere:GetFogSettings()
    local color = fog and fog.color or { 160, 180, 200 }
    local context = level < 0.45 and "night" or level < 0.7 and "dusk" or "day"
    if context == "day" and atmosphere and
        (atmosphere.Weather ~= "clear" or atmosphere.StormIntensity > 0.25) then context = "overcast" end
    return context, color
end

function Palettes:Clear()
    for _, entry in ipairs(self.Meshes) do entry.mesh:Destroy() end
    self.Meshes = {}
    self.ActiveKey = nil
    self.ActiveEntry = nil
end

local function vertex(position, u, v, color)
    return { pos = position, u = u, v = v, color = color }
end

local function makeMesh(vertices, material)
    local object = Mesh()
    object:BuildFromTriangles(vertices)
    return { mesh = object, material = material, triangles = #vertices / 3 }
end

Palettes.MountedFaces = {
    { suffix = "ft", center = Vector(256, 0, 0), right = Vector(0, -256, 0), up = Vector(0, 0, 256) },
    { suffix = "bk", center = Vector(-256, 0, 0), right = Vector(0, 256, 0), up = Vector(0, 0, 256) },
    { suffix = "lf", center = Vector(0, -256, 0), right = Vector(-256, 0, 0), up = Vector(0, 0, 256) },
    { suffix = "rt", center = Vector(0, 256, 0), right = Vector(256, 0, 0), up = Vector(0, 0, 256) },
    { suffix = "up", center = Vector(0, 0, 256), right = Vector(256, 0, 0), up = Vector(0, -256, 0) },
    { suffix = "dn", center = Vector(0, 0, -256), right = Vector(256, 0, 0), up = Vector(0, 256, 0) }
}

Palettes.FaceMaterials = {}
function Palettes:GetFaceMaterials(id)
    if self.FaceMaterials[id] then return self.FaceMaterials[id].materials, self.FaceMaterials[id].sampling end
    local definition = self.Entries[id]
    if not definition or not definition.mounted then return nil, "Not a cube sky: " .. tostring(id) end
    local materials, sampling = {}, {}
    for _, face in ipairs(self.MountedFaces) do
        local source = Material(definition.mounted .. face.suffix)
        local texture = not source:IsError() and source:GetTexture("$basetexture")
        if not texture or texture:Width() <= 0 or texture:Height() <= 0 then
            return nil, "mounted sky face unavailable: " .. definition.mounted .. face.suffix
        end
        local info = definition.faces and definition.faces[face.suffix]
        local scaleX, scaleY = info and info.scaleX or 1, info and info.scaleY or 1
        local keys = { ["$basetexture"] = texture:GetName(), ["$nocull"] = 1, ["$nofog"] = 1 }
        if info and info.transform ~= "" then keys["$basetexturetransform"] = info.transform end
        materials[#materials + 1] = CreateMaterial("zombiesim_sky_palette_" .. id .. "_" .. face.suffix .. "_v2",
            "UnlitGeneric", keys)
        sampling[#sampling + 1] = { u = 0.5 / (texture:Width() * scaleX), v = 0.5 / (texture:Height() * scaleY) }
    end
    self.FaceMaterials[id] = { materials = materials, sampling = sampling }
    return materials, sampling
end

function Palettes:Prepare(id, horizon)
    local definition = self.Entries[id]
    if not definition then return nil, "unknown individual sky: " .. tostring(id) end
    local entries = {}
    if definition.mounted then
        local faces = self.MountedFaces
        local materials, sampling = self:GetFaceMaterials(id)
        if not materials then return nil, sampling end
        for index, face in ipairs(faces) do
            // Sample edge texel centres, not the wrapping boundary between opposite texture edges.
            local inset = sampling[index]
            local info = definition.faces and definition.faces[face.suffix]
            local scaleY = info and info.scaleY or 1
            local maximumV = 1 / scaleY - inset.v
            local a = vertex(face.center - face.right + face.up, inset.u, inset.v, white)
            local b = vertex(face.center + face.right + face.up, 1 - inset.u, inset.v, white)
            local c = vertex(face.center + face.right - face.up, 1 - inset.u, maximumV, white)
            local d = vertex(face.center - face.right - face.up, inset.u, maximumV, white)
            local vertices = { a, b, c, a, c, d }
            if scaleY > 1 then
                // Keep half-height UVs inside the image instead of wrapping the sky below the horizon.
                local middle = face.up * (1 - 2 / scaleY)
                local left = vertex(face.center - face.right + middle, inset.u, maximumV, white)
                local right = vertex(face.center + face.right + middle, 1 - inset.u, maximumV, white)
                vertices = { a, b, right, a, right, left, left, right, c, left, c, d }
            end
            entries[#entries + 1] = makeMesh(vertices, materials[index])
            entries[#entries].samplingInset = inset
        end
    else
        local vertices, rings = {}, {}
        for ring = 0, 16 do
            local elevation = math.rad(-90 + ring * 180 / 16)
            local r, g, b = self:GradientColor(id, elevation, horizon)
            local tint = Color(r, g, b)
            rings[ring + 1] = {}
            for segment = 0, 48 do
                local angle = segment * math.pi * 2 / 48
                rings[ring + 1][segment + 1] = vertex(Vector(math.cos(angle) * math.cos(elevation),
                    math.sin(angle) * math.cos(elevation), math.sin(elevation)) * 256, 0, 0, tint)
            end
        end
        for ring = 1, 16 do
            for segment = 1, 48 do
                local a, b = rings[ring][segment], rings[ring][segment + 1]
                local c, d = rings[ring + 1][segment + 1], rings[ring + 1][segment]
                table.Add(vertices, { a, b, c, a, c, d })
            end
        end
        entries[1] = makeMesh(vertices, gradientMaterial)
    end
    return entries
end

function Palettes:Update()
    if self.Preview and RealTime() >= self.Preview.expiresAt then self.Preview = nil end
    local context, fog = self:GetContext()
    local id, failure = self:Resolve(choice:GetString(), context)
    if self.Preview then id, failure = self.Preview.id, nil end
    if failure then
        if self.Failure ~= failure then ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
        self.Failure = failure
        self:Clear()
        return
    end
    if not id then self:Clear() self.Failure = nil return end
    local horizon = {}
    for index = 1, 3 do horizon[index] = math.Clamp(math.Round(fog[index] / 8) * 8, 0, 255) end
    local key = id .. ":" .. table.concat(horizon, ":")
    if key == self.ActiveKey then return end
    local meshes, err = self:Prepare(id, horizon)
    if not meshes then
        self:Clear()
        if self.Failure ~= err then ErrorNoHalt("[ZombieSim] Sky palette failed: " .. tostring(err) .. "\n") end
        self.Failure = err
        return
    end
    self:Clear()
    self.Meshes, self.ActiveKey, self.ActiveEntry, self.Failure = meshes, key, id, nil
end

hook.Add("Think", "ZM.SkyPalettes.Prepare", function()
    if RealTime() < Palettes.NextUpdate then return end
    Palettes.NextUpdate = RealTime() + 1
    Palettes:Update()
end)

// The documented 2D-sky hook supplies sky masking; disable depth writes so later 3D scenery stays in front.
hook.Add("PostDraw2DSkyBox", "ZM.SkyPalettes.Draw", function()
    if choice:GetString() == "default" and not Palettes.Preview then return end
    if #Palettes.Meshes == 0 then return end
    render.OverrideDepthEnable(true, false)
    cam.Start3D(origin, EyeAngles())
    cam.PushModelMatrix(identity)
    for _, entry in ipairs(Palettes.Meshes) do
        render.SetMaterial(entry.material)
        entry.mesh:Draw()
    end
    cam.PopModelMatrix()
    cam.End3D()
    render.OverrideDepthEnable(false)
    Palettes.Draws = Palettes.Draws + 1
end)

function Palettes:GetDiagnosticSnapshot()
    local triangles = 0
    for _, entry in ipairs(self.Meshes) do triangles = triangles + entry.triangles end
    return { palette = choice:GetString(), activeEntry = self.ActiveEntry, context = self:GetContext(),
        meshes = #self.Meshes, triangles = triangles, draws = self.Draws, failure = self.Failure,
        preview = self.Preview, mountedValveTexturesCopied = false, bakedLightingChanged = false,
        catalogueEntries = table.Count(self.Entries), customProfiles = table.Count(self.CustomStore.profiles),
        catalogueFailure = self.CatalogueFailure, customFailure = self.CustomFailure }
end

concommand.Add("zombiesim_dev_sky_palette", function(_, _, arguments)
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Individual sky previews require a preview admin.\n")
        return
    end
    local id = arguments[1]
    if id == "restore" then Palettes.Preview = nil
    elseif not Palettes.Entries[id] then
        ErrorNoHalt("[ZombieSim] Unknown individual sky preview: " .. tostring(id) .. "\n")
        return
    else Palettes.Preview = { id = id, expiresAt = RealTime() + 120 } end
    Palettes:Update()
end)

concommand.Add("zombiesim_dev_test_sky_palettes", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Sky palette tests require a preview admin.\n")
        return
    end
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("default_keeps_native_sky", function(check)
        check(Palettes:Resolve("default", "day") == nil, "default allocates no replacement")
    end)
    suite:Add("all_palette_contexts_resolve_original_entries", function(check)
        for _, palette in ipairs({ "natural", "cinematic" }) do
            for _, context in ipairs({ "day", "dusk", "night", "overcast" }) do
                local id = Palettes:Resolve(palette, context)
                check(id and Palettes.Entries[id].context == context and not Palettes.Entries[id].mounted,
                    palette .. "/" .. context .. " resolves a context-compatible original sky")
            end
        end
    end)
    suite:Add("invalid_choices_reject_explicitly", function(check)
        local id, failure = Palettes:Resolve("unknown", "day")
        check(not id and failure ~= nil, "invalid palette rejected")
        id, failure = Palettes:Resolve("natural", "unknown")
        check(not id and failure ~= nil, "invalid context rejected")
    end)
    suite:Add("browser_choices_include_palettes_and_every_individual_once", function(check)
        local entries, seen = Palettes:GetChoices(), {}
        check(#entries == 1 + #Palettes.ProfileOrder + table.Count(Palettes.CustomStore.profiles) +
            table.Count(Palettes.Entries), "every palette and individual has a card")
        for _, entry in ipairs(entries) do
            check(not seen[entry.id], "unique card " .. entry.id)
            seen[entry.id] = true
            if not entry.automatic then
                for _, context in ipairs({ "day", "night", "dusk", "overcast" }) do
                    check(Palettes:Resolve(entry.id, context) == entry.id, "explicit choice never auto-switches context")
                end
            end
        end
    end)
    suite:Add("thumbnail_gradient_matches_backdrop_endpoints", function(check)
        for id, entry in pairs(Palettes.Entries) do
            if entry.top then
                local r, g, b = Palettes:GradientColor(id, 0, { 128, 144, 160 })
                check(r == 128 and g == 144 and b == 160, id .. " matches horizon")
                r, g, b = Palettes:GradientColor(id, math.pi / 2, { 128, 144, 160 })
                check(r == entry.top[1] and g == entry.top[2] and b == entry.top[3], id .. " matches zenith")
            end
        end
    end)
    suite:Add("all_original_meshes_are_bounded_and_destroyable", function(check)
        for id, definition in pairs(Palettes.Entries) do
            if not definition.mounted then
                local meshes = Palettes:Prepare(id, { 128, 144, 160 })
                check(meshes and #meshes == 1 and meshes[1].triangles == 1536, id .. " bounded single-mesh backdrop")
                for _, entry in ipairs(meshes or {}) do entry.mesh:Destroy() end
            end
        end
    end)
    suite:Add("mounted_side_and_top_edges_follow_measured_texture_correspondence", function(check)
        local faces = {}
        for _, face in ipairs(Palettes.MountedFaces) do faces[face.suffix] = face end
        local function edge(face, name)
            if name == "left" then return face.center - face.right + face.up, face.center - face.right - face.up end
            if name == "right" then return face.center + face.right + face.up, face.center + face.right - face.up end
            if name == "top" then return face.center - face.right + face.up, face.center + face.right + face.up end
            if name == "bottom" then return face.center - face.right - face.up, face.center + face.right - face.up end
        end
        for _, pair in ipairs({
            { "ft", "right", "lf", "left" }, { "lf", "right", "bk", "left" },
            { "bk", "right", "rt", "left" }, { "rt", "right", "ft", "left" },
            { "ft", "top", "up", "right", true }, { "bk", "top", "up", "left" },
            { "lf", "top", "up", "top", true }, { "rt", "top", "up", "bottom" }
        }) do
            local a, b = edge(faces[pair[1]], pair[2])
            local c, d = edge(faces[pair[3]], pair[4])
            if pair[5] then c, d = d, c end
            check(a:DistToSqr(c) == 0 and b:DistToSqr(d) == 0,
                pair[1] .. "/" .. pair[2] .. " joins " .. pair[3] .. "/" .. pair[4])
        end
        local meshes, failure = Palettes:Prepare("mounted_day", { 128, 144, 160 })
        check(meshes and #meshes == 6, "all six mounted faces resolve: " .. tostring(failure))
        for _, entry in ipairs(meshes or {}) do
            check(entry.triangles == 2 and not entry.material:IsError(), "bounded valid mounted face")
            local texture = entry.material:GetTexture("$basetexture")
            check(entry.samplingInset.u == 0.5 / texture:Width() and
                entry.samplingInset.v == 0.5 / texture:Height(), "face samples half-texel-inset edge centres")
            entry.mesh:Destroy()
        end
    end)
    local summary = suite:Run()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/sky_palette_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Sky palette " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. failure .. "\n") end
    end
end)
