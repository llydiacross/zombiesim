local Clothing = ZM_Clothing
local cache, applied, corpses = {}, {}, {}
local nextScan = 0
local slots, warnings = {}, {}
local buildFailures = {}
local pending, pendingIndex = {}, 1
local compositionBudgetSeconds = 0.002

function Clothing:GetEntitySubMaterial(entity, index)
    local current = entity:GetSubMaterial(index)
    local state = applied[entity]
    if state and state.slot == index and (current == "" or current == state.previous or current == state.material) then
        return state.material
    end
    return current
end

function Clothing:GetReferencedTextureSlots(spawns, limbs)
    local referenced = {}
    local function retain(material)
        local index = type(material) == "string" and tonumber(string.match(material,
            "^models/zombiesim/clothing/pool_(%d%d)_[%a]+$"))
        if index then referenced[index] = true end
    end
    for entity, state in pairs(applied) do
        if IsValid(entity) then
            // Local overrides may not read back through the engine getter in the frame they are set.
            retain(state.material)
            retain(entity:GetSubMaterial(state.slot))
        end
    end
    // Queued copies pin their source before they become entities; bounded queue eviction releases the pin.
    for _, spawn in ipairs(spawns or (ZM_GoreClient and ZM_GoreClient.LimbSpawns) or {}) do
        for _, material in pairs(spawn.materials or {}) do retain(material) end
    end
    for _, limb in ipairs(limbs or (ZM_GoreClient and ZM_GoreClient.Limbs) or {}) do
        if IsValid(limb.entity) then
            for _, material in pairs(limb.materials or {}) do retain(material) end
            for index in ipairs(limb.entity:GetMaterials()) do retain(limb.entity:GetSubMaterial(index - 1)) end
        end
    end
    return referenced
end

local function allocateSlot(key)
    local referenced = Clothing:GetReferencedTextureSlots()
    for index = 1, Clothing.TextureCapacity do
        if not referenced[index] then
            if slots[index] then cache[slots[index]] = nil end
            slots[index] = key
            return index
        end
    end
    if not warnings[key] then
        warnings[key] = true
        ErrorNoHalt("[ZombieSim] Clothing texture budget is pinned; new distinct outfit stays native until a slot is released.\n")
    end
end

local function restore(entity, state)
    local current = entity:GetSubMaterial(state.slot)
    if current == state.material or current == state.previous then entity:SetSubMaterial(state.slot, state.previous) end
end

function Clothing:Apply(entity, shirt, pants, bloody)
    if not IsValid(entity) then return false end
    if bloody ~= nil and type(bloody) ~= "boolean" then
        ErrorNoHalt("[ZombieSim] Invalid clothing blood presentation flag.\n")
        return false
    end
    if bloody and not self.CatalogueReady then
        ErrorNoHalt("[ZombieSim] Blood counterparts require the bounded catalogue texture pool.\n")
        return false
    end
    for garment, selection in pairs({ shirt = shirt, pants = pants }) do
        if selection and selection ~= "" and (not self.Finishes[selection] or
            (self.Finishes[selection].garment and self.Finishes[selection].garment ~= garment)) then
            ErrorNoHalt("[ZombieSim] Invalid equipped clothing selection: " .. tostring(selection) .. "\n")
            return false
        end
    end
    local modelPath = string.lower(entity:GetModel() or "")
    local layout = not self.CanonicalModels[modelPath] and self:GetCitizenLayout(modelPath)
    local sex = self.Models[modelPath] or layout and layout.sex
    if sex and not self.CanonicalModels[modelPath] and not layout then
        if not warnings[modelPath] then
            warnings[modelPath] = true
            ErrorNoHalt("[ZombieSim] Citizen clothing transfer chart is unavailable: " .. modelPath .. "\n")
        end
        return false
    end
    local hasShirt, hasPants = shirt and shirt ~= "", pants and pants ~= ""
    local mode = hasShirt and (hasPants and "both" or "shirt") or (hasPants and "pants" or nil)
    local key = sex and mode and sex .. ":" .. (shirt or "") .. ":" .. (pants or "") .. ":" ..
        (self.CatalogueRevision or "") .. (bloody and ":blood-v1" or ":clean") ..
        (layout and ":" .. modelPath .. ":" .. self.CitizenLayoutRevision or "")
    local state = applied[entity]
    if state and state.key ~= key then
        restore(entity, state)
        applied[entity] = nil
        state = nil
    end
    if state or not sex or not mode then return true end
    if cache[key] == nil then
        local slot = self.CatalogueReady and allocateSlot(key)
        if self.CatalogueReady and not slot then return false end
        local started = SysTime()
        local name, failure = Clothing:BuildEquippedFinish(sex, mode, slot, shirt, pants, bloody, layout)
        if not name then
            if slot then slots[slot] = nil end
            if buildFailures[key] ~= failure then
                ErrorNoHalt("[ZombieSim] Equipped clothing failed: " .. tostring(failure) .. "\n")
                buildFailures[key] = failure
            end
            return false
        end
        buildFailures[key] = nil
        cache[key] = { name = name, slot = slot, buildMs = (SysTime() - started) * 1000 }
    end
    if not cache[key].name then return false end
    for index, material in ipairs(entity:GetMaterials()) do
        if string.lower(material) == "models/humans/" .. sex .. "/group01/players_sheet" then
            local slot = index - 1
            local name = cache[key].name
            applied[entity] = { slot = slot, previous = entity:GetSubMaterial(slot), material = name, sex = sex, mode = mode,
                key = key, bloody = bloody == true }
            entity:SetSubMaterial(slot, name)
            return true
        end
    end
    ErrorNoHalt("[ZombieSim] Equipped clothing has no verified body material on " .. tostring(entity:GetModel()) .. "\n")
    return false
end

hook.Add("PreRender", "ZM.Clothing.Equipped", function()
    if pendingIndex > #pending and RealTime() >= nextScan then
        nextScan = RealTime() + 0.25
        pending, pendingIndex = {}, 1
        local function enqueue(entity, selection, limb, corpse)
            pending[#pending + 1] = { entity = entity, selection = selection, limb = limb, corpse = corpse }
        end
        for entity in pairs(applied) do if not IsValid(entity) then applied[entity] = nil end end
        for corpse in pairs(corpses) do if not IsValid(corpse) then corpses[corpse] = nil end end
        for _, limb in ipairs(ZM_GoreClient and ZM_GoreClient.Limbs or {}) do
            if limb.clothing and not limb.clothingApplied and IsValid(limb.entity) then
                enqueue(limb.entity, limb.clothing, limb)
            end
        end
        for _, survivor in ipairs(player.GetAll()) do
            local shirt = survivor:GetNWString("ZM_Clothing_shirt", "")
            local pants = survivor:GetNWString("ZM_Clothing_pants", "")
            enqueue(survivor, { shirt = shirt, pants = pants })
        end
        for _, walker in ipairs(ents.FindByClass("zn_walker_zombie")) do
            local selection = Clothing:GetEntitySelection(walker)
            if selection then enqueue(walker, selection) end
        end
        local ragdolls = ents.FindByClass("class C_HL2MPRagdoll")
        table.Add(ragdolls, ents.FindByClass("prop_ragdoll"))
        for _, corpse in ipairs(ragdolls) do
            if not corpses[corpse] then
                local snapshot = corpse:GetNWString("ZM_ClothingCorpse", "")
                if snapshot ~= "" then
                    local selection = util.JSONToTable(snapshot)
                    if type(selection) == "table" then
                        enqueue(corpse, selection, nil, true)
                    else
                        ErrorNoHalt("[ZombieSim] Player corpse has an invalid clothing snapshot.\n")
                        corpses[corpse] = true
                    end
                end
            end
        end
    end
    local started = SysTime()
    while pendingIndex <= #pending do
        local request = pending[pendingIndex]
        pendingIndex = pendingIndex + 1
        if IsValid(request.entity) then
            local selection = request.selection
            local success = Clothing:Apply(request.entity, selection.shirt, selection.pants, selection.bloody)
            if request.corpse then corpses[request.entity] = success end
            if request.limb then
                request.limb.clothingApplied = success
                if success then
                    for index in ipairs(request.entity:GetMaterials()) do
                        request.limb.materials[index - 1] = Clothing:GetEntitySubMaterial(request.entity, index - 1)
                    end
                end
            end
        end
        // A single cold build can exceed the soft budget; never batch another behind it.
        if SysTime() - started >= compositionBudgetSeconds then break end
    end
end)

function Clothing:GetDiagnosticSnapshot()
    local entities = {}
    local ragdolls = {}
    for _, entity in ipairs(ents.GetAll()) do
        if string.find(string.lower(entity:GetClass()), "ragdoll", 1, true) then
            ragdolls[#ragdolls + 1] = { class = entity:GetClass(), model = entity:GetModel(),
                clothing = entity:GetNWString("ZM_ClothingCorpse", ""), materials = entity:GetMaterials() }
        end
    end
    for _, survivor in ipairs(player.GetAll()) do
        local corpse = survivor:GetRagdollEntity()
        if IsValid(corpse) then
            ragdolls[#ragdolls + 1] = { viaPlayer = true, class = corpse:GetClass(), model = corpse:GetModel(),
                clothing = corpse:GetNWString("ZM_ClothingCorpse", ""), materials = corpse:GetMaterials() }
        end
    end
    for entity, state in pairs(applied) do
        if IsValid(entity) then
            local material = Material(state.material)
            local texture = material:GetTexture("$basetexture")
            entities[#entities + 1] = { class = entity:GetClass(), model = entity:GetModel(), slot = state.slot,
                mode = state.mode, bloody = state.bloody, material = state.material, shader = material:GetShader(),
                width = texture and texture:Width(), height = texture and texture:Height() }
        end
    end
    return { builds = cache, applied = #entities, maximumTextures = self.CatalogueReady and self.TextureCapacity or 6,
        pendingCompositions = math.max(0, #pending - pendingIndex + 1), compositionBudgetMs = compositionBudgetSeconds * 1000,
        allocatedSlots = table.Count(slots), referencedSlots = self:GetReferencedTextureSlots(), budgetWarnings = table.Count(warnings),
        supportedModels = self.Models, finishes = self.Finishes, entities = entities, ragdolls = ragdolls }
end
