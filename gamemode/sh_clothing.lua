ZM_Clothing = ZM_Clothing or {}
local Clothing = ZM_Clothing

Clothing.Slots = { shirt = 5, pants = 6 }
Clothing.Finishes = Clothing.Finishes or { prototype = { style = "base" } }
Clothing.CatalogueItems = Clothing.CatalogueItems or {}
Clothing.TextureCapacity = 16
Clothing.MaximumCatalogueFinishes = 896
Clothing.Models = {
    ["models/player/group01/male_03.mdl"] = "male",
    ["models/player/group01/female_01.mdl"] = "female"
}

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
