local Clothing = ZM_Clothing
local cache, applied, corpses = {}, {}, {}
local nextScan = 0
local slots, warnings = {}, {}
local buildFailures = {}

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

function Clothing:Apply(entity, shirt, pants)
    if not IsValid(entity) then return false end
    for garment, selection in pairs({ shirt = shirt, pants = pants }) do
        if selection and selection ~= "" and (not self.Finishes[selection] or
            (self.Finishes[selection].garment and self.Finishes[selection].garment ~= garment)) then
            ErrorNoHalt("[ZombieSim] Invalid equipped clothing selection: " .. tostring(selection) .. "\n")
            return false
        end
    end
    local sex = self.Models[string.lower(entity:GetModel() or "")]
    local hasShirt, hasPants = shirt and shirt ~= "", pants and pants ~= ""
    local mode = hasShirt and (hasPants and "both" or "shirt") or (hasPants and "pants" or nil)
    local key = sex and mode and sex .. ":" .. (shirt or "") .. ":" .. (pants or "") .. ":" .. (self.CatalogueRevision or "")
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
        local name, failure = Clothing:BuildEquippedFinish(sex, mode, slot, shirt, pants)
        if not name then
            if slot then slots[slot] = nil end
            if buildFailures[key] ~= failure then
                ErrorNoHalt("[ZombieSim] Equipped clothing failed: " .. tostring(failure) .. "\n")
                buildFailures[key] = failure
            end
            return false
        end
        buildFailures[key] = nil
        cache[key] = { name = name, slot = slot }
    end
    if not cache[key].name then return false end
    for index, material in ipairs(entity:GetMaterials()) do
        if string.lower(material) == "models/humans/" .. sex .. "/group01/players_sheet" then
            local slot = index - 1
            local name = cache[key].name
            applied[entity] = { slot = slot, previous = entity:GetSubMaterial(slot), material = name, sex = sex, mode = mode, key = key }
            entity:SetSubMaterial(slot, name)
            return true
        end
    end
    ErrorNoHalt("[ZombieSim] Equipped clothing has no verified body material on " .. tostring(entity:GetModel()) .. "\n")
    return false
end

hook.Add("PreRender", "ZM.Clothing.Equipped", function()
    if RealTime() < nextScan then return end
    nextScan = RealTime() + 0.25
    for entity in pairs(applied) do if not IsValid(entity) then applied[entity] = nil end end
    for corpse in pairs(corpses) do if not IsValid(corpse) then corpses[corpse] = nil end end
    for _, survivor in ipairs(player.GetAll()) do
        local shirt = survivor:GetNWString("ZM_Clothing_shirt", "")
        local pants = survivor:GetNWString("ZM_Clothing_pants", "")
        Clothing:Apply(survivor, shirt, pants)
    end
    for _, corpse in ipairs(ents.FindByClass("class C_HL2MPRagdoll")) do
        if not corpses[corpse] then
            local snapshot = corpse:GetNWString("ZM_ClothingCorpse", "")
            if snapshot ~= "" then
                local selection = util.JSONToTable(snapshot)
                if type(selection) == "table" then
                    corpses[corpse] = Clothing:Apply(corpse, selection.shirt, selection.pants)
                else
                    ErrorNoHalt("[ZombieSim] Player corpse has an invalid clothing snapshot.\n")
                    corpses[corpse] = true
                end
            end
        end
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
                mode = state.mode, material = state.material, shader = material:GetShader(),
                width = texture and texture:Width(), height = texture and texture:Height() }
        end
    end
    return { builds = cache, applied = #entities, maximumTextures = self.CatalogueReady and self.TextureCapacity or 6,
        allocatedSlots = table.Count(slots), referencedSlots = self:GetReferencedTextureSlots(), budgetWarnings = table.Count(warnings),
        supportedModels = self.Models, finishes = self.Finishes, entities = entities, ragdolls = ragdolls }
end
