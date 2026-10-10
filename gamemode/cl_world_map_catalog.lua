return function()
    local Catalog = {}
    Catalog.Variants = { clear = true, atmospheric = true }

    function Catalog.MigratePreferences(store, prefix, layers)
        if store.GetString(prefix .. "view_schema", "") == "2" then return end
        local mode = store.GetString(prefix .. "render_mode", "default")
        if mode == "default" or mode == "satellite" then mode = "atlas" end
        store.Set(prefix .. "render_mode", mode)
        for _, layer in ipairs(layers) do
            local value = store.GetString("zombiesim_world_map_layer_satellite_" .. layer.id, "")
            if value == "0" or value == "1" then
                store.Set("zombiesim_world_map_layer_atlas_" .. layer.id, value)
            end
        end
        store.Set(prefix .. "view_schema", "2")
    end

    local function validPath(path, profile)
        return type(path) == "string" and not string.find(path, "..", 1, true)
            and string.match(path, "^worlds/" .. profile .. "/captured/[%w_/%-]+%.png$") ~= nil
    end

    function Catalog.Validate(manifest, profile, worldData)
        if type(manifest) ~= "table" then return nil, "No captured-world manifest is installed." end
        if type(worldData) ~= "table" or type(worldData.world) ~= "table" then
            return nil, "World data is unavailable."
        end
        local world = worldData.world
        if type(worldData.cells) ~= "table" or #worldData.cells == 0 then
            return nil, "World data has no ordinary cells."
        end
        if manifest.schemaVersion ~= 1 or manifest.profile ~= profile or manifest.complete ~= true then
            return nil, "Captured-world manifest is incomplete or belongs to another profile."
        end
        if not world.mapManifestSha256 or not world.templatePlanSha256
            or manifest.mapManifestSha256 ~= world.mapManifestSha256
            or manifest.templatePlanSha256 ~= world.templatePlanSha256 then
            return nil, "Captured-world images do not match the current world revision."
        end
        if type(manifest.variants) ~= "table" then return nil, "Captured-world variants are missing." end
        local variants = {}
        for name in pairs(Catalog.Variants) do
            local variant = manifest.variants[name]
            if type(variant) == "table" and variant.complete == true then
                if not validPath(variant.atlas, profile) or type(variant.cells) ~= "table" then
                    return nil, "Invalid captured-world image paths."
                end
                for _, cell in ipairs(worldData.cells) do
                    if not validPath(variant.cells[tostring(cell.id)], profile) then
                        return nil, "Captured-world variant is missing cell " .. tostring(cell.id) .. "."
                    end
                end
                variants[name] = variant
            end
        end
        if not next(variants) then return nil, "No complete captured-world variant is installed." end
        return variants
    end
    return Catalog
end
