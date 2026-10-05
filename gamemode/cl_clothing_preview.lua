// Shared garment compositor and diagnostic fixtures over the mounted body sheet.
ZM_ClothingPreview = ZM_ClothingPreview or {}
local cache, applied, diagnostics = {}, {}, {}
local nextScan = 0
local supported = {
    ["models/player/group01/male_03.mdl"] = "male",
    ["models/player/group01/female_01.mdl"] = "female"
}

local function buildFinish(sex, mode, style, namespace, poolSlot, shirt, pants)
    namespace = namespace or ""
    local path = "models/humans/" .. sex .. "/group01/players_sheet"
    local native = Material(path)
    local base = not native:IsError() and native:GetTexture("$basetexture")
    local layers = {}
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
        layers[#layers + 1] = layer
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
        for _, layer in ipairs(layers) do
            surface.SetMaterial(layer)
            surface.DrawTexturedRect(0, 0, 1024, 1024)
        end
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

function ZM_Clothing:BuildEquippedFinish(sex, mode, slot, shirt, pants)
    return buildFinish(sex, mode, "base", "equipped_", slot, shirt, pants)
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
