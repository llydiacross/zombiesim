ZM_Clothing = ZM_Clothing or {}
local Clothing = ZM_Clothing

Clothing.Slots = { shirt = 5, pants = 6 }
Clothing.Finishes = Clothing.Finishes or { prototype = { style = "base" } }
Clothing.CatalogueItems = Clothing.CatalogueItems or {}
Clothing.TextureCapacity = 96
Clothing.MaximumCatalogueFinishes = 896
Clothing.CanonicalModels = {
    ["models/player/group01/male_03.mdl"] = "male",
    ["models/player/group01/female_01.mdl"] = "female"
}
Clothing.Models = table.Copy(Clothing.CanonicalModels)

local calibrationJSON = file.Read("data_static/clothing_citizen_calibration.json", "GAME")
if calibrationJSON then
    local calibration = util.JSONToTable(calibrationJSON)
    local valid = type(calibration) == "table" and calibration.schemaVersion == 1 and calibration.size == 1024 and
        type(calibration.previewOnly) == "boolean" and type(calibration.models) == "table" and table.Count(calibration.models) == 15
    local models = {}
    if valid then
        for path, layout in pairs(calibration.models) do
            local sex, number
            if type(path) == "string" then sex, number = string.match(path, "^models/player/group01/(%a+)_(%d%d)%.mdl$") end
            number = tonumber(number)
            if (sex ~= "male" and sex ~= "female") or not number or number < 1 or
                number > (sex == "male" and 9 or 6) or type(layout) ~= "table" or layout.sex ~= sex then
                valid = false
                break
            end
            models[path] = sex
        end
    end
    if valid then
        Clothing.CitizenLayoutPreviewOnly = calibration.previewOnly
        if CLIENT then
            Clothing.CitizenCalibrationData = calibration
            Clothing.CitizenLayoutRevision = util.CRC(calibrationJSON)
        end
        if not calibration.previewOnly then Clothing.Models = models end
    else
        ErrorNoHalt("[ZombieSim] Citizen clothing model manifest rejected.\n")
    end
end

function Clothing:LoadCatalogue()
    local json = file.Read("data_static/clothing_catalogue.json", "GAME")
    if not json then
        print("[ZombieSim] Optional clothing catalogue not built; fixed prototype finishes remain available.")
        return
    end
    local data = util.JSONToTable(json)
    local failure
    if type(data) ~= "table" or data.schemaVersion ~= 1 or data.capacity ~= self.TextureCapacity or
        type(data.finishes) ~= "table" or type(data.items) ~= "table" or
        table.Count(data.finishes) > self.MaximumCatalogueFinishes or table.Count(data.items) > self.MaximumCatalogueFinishes then
        failure = "invalid catalogue schema/budget"
    else
        for id, finish in pairs(data.finishes) do
            if type(id) ~= "string" or not string.match(id, "^catalogue_[%w_]+$") or type(finish) ~= "table" or
                not self.Slots[finish.garment] or type(finish.layers) ~= "table" then
                failure = "invalid finish declaration"
                break
            end
            for _, sex in ipairs({ "male", "female" }) do
                local path = finish.layers[sex]
                if type(path) ~= "string" or not string.match(path, "^models/zombiesim/clothing/catalog_%x+_[%w_]+$") or
                    not file.Exists("materials/" .. path .. ".vmt", "GAME") or not file.Exists("materials/" .. path .. ".vtf", "GAME") then
                    failure = "missing or invalid layer for " .. id
                    break
                end
            end
            if failure then break end
        end
        for id, item in pairs(data.items) do
            if type(id) ~= "string" or not string.match(id, "^itemClothing%w+$") or type(item) ~= "table" or
                type(item.clothing) ~= "table" or not data.finishes[item.clothing.finish] or
                data.finishes[item.clothing.finish].garment ~= item.clothing.garment then
                failure = "invalid item declaration"
                break
            end
        end
    end
    self.CatalogueError = failure
    if failure then
        ErrorNoHalt("[ZombieSim] Clothing catalogue rejected; retaining previous registry: " .. failure .. "\n")
        return
    end
    local finishes = { prototype = { style = "base" } }
    for id, finish in pairs(data.finishes) do finishes[id] = finish end
    self.Finishes = finishes
    self.CatalogueItems = data.items
    self.CatalogueReady = true
    self.CatalogueRevision = util.CRC(json)
end

Clothing:LoadCatalogue()

function Clothing:GetEquipped(inventory, garment)
    local instance = inventory and inventory.equipped and inventory.equipped[self.Slots[garment]]
    local definition = instance and ZM_Items:GetDefinition(instance.itemId)
    local clothing = definition and definition.clothing
    return clothing and clothing.garment == garment and self.Finishes[clothing.finish] and clothing.finish or ""
end

function Clothing:GetEntitySelection(entity)
    local packet = entity:GetNWString("ZM_ClothingCorpse", "")
    if packet ~= "" then
        local selection = util.JSONToTable(packet)
        if type(selection) ~= "table" or type(selection.shirt) ~= "string" or type(selection.pants) ~= "string" or
            (selection.bloody ~= nil and type(selection.bloody) ~= "boolean") then
            ErrorNoHalt("[ZombieSim] Invalid immutable corpse clothing packet.\n")
            return
        end
        return selection
    end
    return {
        shirt = entity:GetNWString("ZM_Clothing_shirt", ""),
        pants = entity:GetNWString("ZM_Clothing_pants", ""),
        bloody = entity:GetNWBool("ZM_ClothingBloody", false)
    }
end

function Clothing:GetWalkerOutfit(model, seed)
    if not self.Models[model] or not self.CatalogueReady or self.CitizenLayoutPreviewOnly then return end
    if self.WalkerCatalogueRevision ~= self.CatalogueRevision then
        local shirts, pants = {}, {}
        for id, finish in pairs(self.Finishes) do
            if finish.garment == "shirt" then shirts[#shirts + 1] = id
            elseif finish.garment == "pants" then pants[#pants + 1] = id end
        end
        table.sort(shirts)
        table.sort(pants)
        self.WalkerShirts, self.WalkerPants = shirts, pants
        self.WalkerCatalogueRevision = self.CatalogueRevision
    end
    local shirts, pants = self.WalkerShirts, self.WalkerPants
    if #shirts == 0 or #pants == 0 then
        ErrorNoHalt("[ZombieSim] Citizen walker clothing requires both garment families.\n")
        return
    end
    local key = model .. ":" .. seed .. ":" .. self.CatalogueRevision
    return {
        shirt = shirts[tonumber(util.CRC(key .. ":shirt")) % #shirts + 1],
        pants = pants[tonumber(util.CRC(key .. ":pants")) % #pants + 1],
        bloody = true
    }
end

if SERVER then
    function Clothing:AssignWalkerOutfit(entity, cellId)
        if not IsValid(entity) or entity:GetClass() ~= "zn_walker_zombie" then return end
        if not entity.ZM_ClothingOutfitSeed then
            self.WalkerOutfitSequence = (self.WalkerOutfitSequence or 0) + 1
            entity.ZM_ClothingOutfitSeed = tostring(math.random(0, 2147483646)) .. ":" .. self.WalkerOutfitSequence
        end
        local identity = entity.ZM_ClothingOutfitSeed
        if isnumber(entity.WalkerTicketIdLow) and isnumber(entity.WalkerTicketIdHigh) then
            identity = "ticket:" .. entity.WalkerTicketIdHigh .. ":" .. entity.WalkerTicketIdLow
        end
        local selection = self:GetWalkerOutfit(string.lower(entity:GetModel() or ""),
            ZM_World.ActiveProfile .. ":" .. tostring(cellId or entity.WalkerSourceCellId or game.GetMap()) .. ":" .. identity)
        entity:SetNWString("ZM_Clothing_shirt", selection and selection.shirt or "")
        entity:SetNWString("ZM_Clothing_pants", selection and selection.pants or "")
        entity:SetNWBool("ZM_ClothingBloody", selection ~= nil)
    end
end
