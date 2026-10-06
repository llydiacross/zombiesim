// Shared garment compositor and diagnostic fixtures over the mounted body sheet.
ZM_ClothingPreview = ZM_ClothingPreview or {}
local cache, applied, diagnostics = {}, {}, {}
local nextScan = 0
local supported = {
    ["models/player/group01/male_03.mdl"] = "male",
    ["models/player/group01/female_01.mdl"] = "female"
}

local function loadCitizenLayouts()
    local data = ZM_Clothing.CitizenCalibrationData
    ZM_Clothing.CitizenCalibrationData = nil
    if not data then return end
    ZM_Loading:Step("Preparing calibrated citizen clothing")
    if type(data) ~= "table" or data.schemaVersion ~= 1 or data.size ~= 1024 or
        type(data.previewOnly) ~= "boolean" or type(data.models) ~= "table" or table.Count(data.models) ~= 15 then
        ErrorNoHalt("[ZombieSim] Invalid preview citizen calibration manifest.\n")
        return
    end
    local layouts = {}
    for path, layout in pairs(data.models) do
        local sex, number
        if type(path) == "string" then sex, number = string.match(path, "^models/player/group01/(%a+)_(%d%d)%.mdl$") end
        number = tonumber(number)
        if (sex ~= "male" and sex ~= "female") or not number or number < 1 or
            number > (sex == "male" and 9 or 6) or type(layout) ~= "table" or layout.sex ~= sex then
            ErrorNoHalt("[ZombieSim] Citizen calibration contains an invalid or rebel model.\n")
            return
        end
        local prepared = { sex = sex, polygons = {} }
        for _, garment in ipairs({ "shirt", "pants" }) do
            local triangles = layout[garment]
            if type(triangles) ~= "table" or #triangles < 400 or #triangles > 2000 then
                ErrorNoHalt("[ZombieSim] Invalid citizen garment coverage: " .. path .. "\n")
                return
            end
            prepared.polygons[garment] = {}
            for _, triangle in ipairs(triangles) do
                if type(triangle) ~= "table" or #triangle ~= 3 then
                    ErrorNoHalt("[ZombieSim] Invalid citizen transfer triangle.\n")
                    return
                end
                local polygon = {}
                for _, vertex in ipairs(triangle) do
                    if type(vertex) ~= "table" or #vertex ~= 4 then
                        ErrorNoHalt("[ZombieSim] Invalid citizen transfer vertex.\n")
                        return
                    end
                    for _, value in ipairs(vertex) do
                        if not isnumber(value) or value ~= value or value < 0 or value > 1 then
                            ErrorNoHalt("[ZombieSim] Non-finite or unbounded citizen transfer coordinate.\n")
                            return
                        end
                    end
                    polygon[#polygon + 1] = { x = vertex[1] * 1024, y = vertex[2] * 1024, u = vertex[3], v = vertex[4] }
                end
                local a, b, c = polygon[1], polygon[2], polygon[3]
                if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) < 0 then
                    polygon[2], polygon[3] = polygon[3], polygon[2]
                end
                prepared.polygons[garment][#prepared.polygons[garment] + 1] = polygon
            end
        end
        layouts[path] = prepared
    end
    ZM_Clothing.CitizenLayouts = layouts
    ZM_Loading:Step("Citizen clothing layouts ready", "ok")
end

loadCitizenLayouts()

function ZM_Clothing:GetCitizenLayout(path)
    if self.CitizenLayoutPreviewOnly and
        (not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or not ZM_World or ZM_World.ActiveProfile ~= "preview") then return end
    return self.CitizenLayouts and self.CitizenLayouts[path]
end

ZM_Clothing.GetPreviewCitizenLayout = ZM_Clothing.GetCitizenLayout

local function buildFinish(sex, mode, style, namespace, poolSlot, shirt, pants, bloody, layout)
    namespace = namespace or ""
    local path = "models/humans/" .. sex .. "/group01/players_sheet"
    local native = Material(path)
    local base = not native:IsError() and native:GetTexture("$basetexture")
    local layers, bloodLayers = {}, {}
    for _, garment in ipairs(mode == "both" and { "shirt", "pants" } or { mode }) do
        local layerName = garment == "shirt" and "shirt_" .. sex or garment
        local legStyle = string.match(style or "", "^pants_") ~= nil
        if garment == "pants" and legStyle then
            layerName = "pants_" .. sex .. "_" .. style
        elseif (garment == "shirt" and style ~= "base" and not legStyle) or (garment == "pants" and style == "repeat") then
            layerName = layerName .. "_" .. style
        end
        local selection = garment == "shirt" and shirt or pants
        local finish = selection and ZM_Clothing.Finishes[selection]
        local layer = Material(finish and finish.layers and finish.layers[sex] or
            "models/zombiesim/clothing/prototype_" .. layerName)
        local texture = not layer:IsError() and layer:GetTexture("$basetexture")
        if not texture or texture:Width() ~= 1024 or texture:Height() ~= 1024 then
            return nil, "missing original " .. garment .. " layer"
        end
        layers[#layers + 1] = { material = layer, garment = garment }
        if bloody then
            local bloodName = "models/zombiesim/clothing/prototype_blood_" ..
                (garment == "shirt" and "shirt_" .. sex or "pants")
            local blood = Material(bloodName)
            local bloodTexture = not blood:IsError() and blood:GetTexture("$basetexture")
            if not bloodTexture or bloodTexture:Width() ~= 1024 or bloodTexture:Height() ~= 1024 then
                return nil, "missing original blood overlay: " .. bloodName
            end
            bloodLayers[#bloodLayers + 1] = { material = blood, garment = garment }
        end
    end
    if not base or base:Width() ~= 1024 or base:Height() ~= 1024 then return nil, "unsupported mounted body sheet" end
    local key = namespace .. sex .. "_" .. mode
    local poolKey = poolSlot and string.format("pool_%02d", poolSlot)
    local targetName = poolKey and "zombiesim_clothing_" .. poolKey .. "_v1" or "zombiesim_clothing_" .. key .. "_v2"
    local target = GetRenderTargetEx(targetName, 1024, 1024,
        RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, bit.bor(4, 8), 0, IMAGE_FORMAT_RGBA8888)
    local copy = CreateMaterial("zombiesim_clothing_copy_" .. sex .. "_v1", "UnlitGeneric", {
        ["$basetexture"] = base:GetName(), ["$translucent"] = "1",
        ["$vertexcolor"] = "1", ["$vertexalpha"] = "1"
    })
    if not target or target:Width() ~= 1024 or copy:IsError() then return nil, "body-sheet render target unavailable" end
    local in2D = false
    render.PushRenderTarget(target)
    local ok, failure = xpcall(function()
        render.OverrideAlphaWriteEnable(true, true)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
        in2D = true
        // Untouched pixels retain the native tint mask; opaque artwork clears it only on the equipped garment.
        render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(copy)
        surface.DrawTexturedRect(0, 0, 1024, 1024)
        render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
            BLEND_ZERO, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
        local function drawLayer(layer)
            surface.SetMaterial(layer.material)
            if layout then
                for _, polygon in ipairs(layout.polygons[layer.garment]) do surface.DrawPoly(polygon) end
            else
                surface.DrawTexturedRect(0, 0, 1024, 1024)
            end
        end
        for _, layer in ipairs(layers) do drawLayer(layer) end
        for _, layer in ipairs(bloodLayers) do drawLayer(layer) end
    end, debug.traceback)
    if in2D then cam.End2D() end
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then return nil, tostring(failure) end
    // Patch inheritance retains the entire native proxy chain, including its repeated Clamp proxies.
    local name = "models/zombiesim/clothing/" .. (poolKey and poolKey .. "_" .. sex or
        (namespace == "" and "prototype_" or "") .. key)
    local material = Material(name)
    local texture = not material:IsError() and material:GetTexture("$basetexture")
    if not texture or texture:GetName() ~= target:GetName() or material:GetShader() ~= native:GetShader() then
        return nil, "inherited finish did not resolve the runtime texture/native shader"
    end
    return name
end

function ZM_Clothing:BuildEquippedFinish(sex, mode, slot, shirt, pants, bloody, layout)
    return buildFinish(sex, mode, "base", "equipped_", slot, shirt, pants, bloody, layout)
end

hook.Add("PreRender", "ZM.ClothingPreview.Fixtures", function()
    if RealTime() < nextScan then return end
    nextScan = RealTime() + 0.25
    local enabled = IsValid(LocalPlayer()) and LocalPlayer():IsAdmin() and ZM_World and ZM_World.ActiveProfile == "preview"
    for entity, state in pairs(applied) do
        if not IsValid(entity) then
            applied[entity] = nil
        elseif not enabled or entity:GetNWString("ZM_DevClothingFinish", "") ~= state.mode or
            entity:GetNWString("ZM_DevClothingStyle", "base") ~= state.style then
            // GetSubMaterial prioritises the server value, even when the client renders a local override.
            local current = entity:GetSubMaterial(state.slot)
            entity:SetSubMaterial(state.slot, current == state.material and state.previous or current)
            applied[entity] = nil
        end
    end
    if not enabled then return end
    for _, entity in ipairs(ents.FindByClass("prop_dynamic")) do
        local mode = entity:GetNWString("ZM_DevClothingFinish", "")
        local style = entity:GetNWString("ZM_DevClothingStyle", "base")
        local sex = supported[string.lower(entity:GetModel() or "")]
        if sex and (mode == "shirt" or mode == "pants" or mode == "both") and not applied[entity] then
            local key = sex .. "_" .. mode
            if cache[key] == nil or cache[key].style ~= style then
                local started = SysTime()
                local name, failure = buildFinish(sex, mode, style)
                cache[key] = { name = name, style = style }
                diagnostics[key] = { ready = name ~= nil, style = style, failure = failure, buildMs = (SysTime() - started) * 1000 }
                if not name then ErrorNoHalt("[ZombieSim] Clothing prototype failed: " .. failure .. "\n") end
            end
            if cache[key].name then
                local slot
                for index, material in ipairs(entity:GetMaterials()) do
                    if string.lower(material) == "models/humans/" .. sex .. "/group01/players_sheet" then slot = index - 1 break end
                end
                if slot then
                    local name = cache[key].name
                    applied[entity] = { slot = slot, previous = entity:GetSubMaterial(slot), material = name, mode = mode, style = style }
                    entity:SetSubMaterial(slot, name)
                    print("[ZombieSim] Clothing prototype ready: " .. key .. "/" .. style .. "; 1024-square runtime texture, native shader/proxies retained.")
                else
                    ErrorNoHalt("[ZombieSim] Clothing prototype fixture has no verified body material.\n")
                end
            end
        end
    end
end)

function ZM_ClothingPreview:GetDiagnosticSnapshot()
    local fixtures = {}
    for entity, state in pairs(applied) do
        if IsValid(entity) then
            local material = Material(state.material)
            local texture = material:GetTexture("$basetexture")
            local normal = material:GetTexture("$bumpmap")
            fixtures[#fixtures + 1] = {
                entityIndex = entity:EntIndex(), model = entity:GetModel(), mode = state.mode, style = state.style,
                slot = state.slot, serverReportedOverride = entity:GetSubMaterial(state.slot),
                appliedMaterial = state.material, previous = state.previous,
                shader = material:GetShader(), texture = texture and texture:GetName(),
                width = texture and texture:Width(), height = texture and texture:Height(),
                normal = normal and normal:GetName()
            }
        end
    end
    return { fixtures = fixtures, builds = diagnostics, tintPolicy = "artist colour on finishes; native tint elsewhere",
        maximumTextures = 6, prototypeOnly = true }
end
