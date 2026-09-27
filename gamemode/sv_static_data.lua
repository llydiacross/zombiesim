// Server-only static-data commands and checks that need registered SWEPs, entities, and mounted content.
local StaticData = ZM_StaticData

util.AddNetworkString("ZM.StaticDataReloaded")

local lootFiles = { ["loot.json"] = true, ["entity_loot.json"] = true }

// Warns about references that only resolve at runtime; these never block a load.
function StaticData:ValidateRuntimeReferences(registry, report)
    local function warn(fileName, path, message)
        table.insert(report.warnings, { file = fileName, path = path, message = message })
    end

    for _, itemId in ipairs(table.GetKeys(registry.items)) do
        local item = registry.items[itemId]
        local storedWeapon = item.weaponClass and weapons.GetStored(item.weaponClass) or nil
        if item.weaponClass and not storedWeapon then
            warn("item_definitions.json", "items." .. itemId, "SWEP '" .. item.weaponClass .. "' is not registered")
        end
        if item.viewModel and not util.IsValidModel(item.viewModel) then
            warn("item_definitions.json", "items." .. itemId .. ".viewModel", item.viewModel .. " is not a valid mounted model")
        end
        if item.worldModel and not util.IsValidModel(item.worldModel) then
            warn("item_definitions.json", "items." .. itemId .. ".worldModel", item.worldModel .. " is not a valid mounted model")
        end
        if storedWeapon then
            if item.viewModel and storedWeapon.ViewModel ~= item.viewModel then
                warn("item_definitions.json", "items." .. itemId .. ".viewModel", "does not match SWEP '" .. item.weaponClass .. "'")
            end
            if item.worldModel and storedWeapon.WorldModel ~= item.worldModel then
                warn("item_definitions.json", "items." .. itemId .. ".worldModel", "does not match SWEP '" .. item.weaponClass .. "'")
            end
            local expectsAutomatic = item.firingMode == "automatic"
            local isAutomatic = storedWeapon.Primary and storedWeapon.Primary.Automatic == true
            if item.firingMode and expectsAutomatic ~= isAutomatic then
                warn("item_definitions.json", "items." .. itemId .. ".firingMode", "does not match SWEP '" .. item.weaponClass .. "'")
            end
        end
        // An authored materials/items/<thumbnail>.png is an optional override; the model spawn icon is the default.
        if not util.IsValidModel(item.iconModel) then
            warn("item_definitions.json", "items." .. itemId .. ".iconModel", item.iconModel .. " is not a valid mounted model")
        end
    end
    for _, rule in ipairs(registry.entityLoot.rules) do
        if not file.Exists(rule.model, "GAME") then
            warn("entity_loot.json", "rules[" .. rule.index .. "].model", rule.model .. " is not mounted")
        end
    end
    local npcList = list.Get("NPC")
    for _, recipeId in ipairs(table.GetKeys(registry.recipes or {})) do
        local stationClass = StaticData.CraftingStations[registry.recipes[recipeId].station]
        if stationClass and not scripted_ents.GetStored(stationClass) then
            warn("recipe_definitions.json", "recipes." .. recipeId .. ".station", "station entity '" .. stationClass .. "' is not registered")
        end
    end
    for _, enemyId in ipairs(table.GetKeys(registry.enemies)) do
        local enemy = registry.enemies[enemyId]
        if not scripted_ents.GetStored(enemy.entity) and not npcList[enemy.entity] then
            warn("enemy_definitions.json", "enemies." .. enemyId .. ".entity", "'" .. enemy.entity .. "' is not a registered scripted entity or NPC")
        end
    end

    local worldData = ZM_World and ZM_World:GetData() or nil
    if worldData and worldData.environments then
        local knownTags = {}
        for _, environment in pairs(worldData.environments) do
            for _, tag in ipairs(environment.tags or {}) do
                knownTags[tag] = true
            end
        end
        for tag in pairs(registry.environmentTags) do
            if not knownTags[tag] then
                warn("enemy_spawns.json", "environmentTags." .. tag, "no cell in the loaded world uses this tag")
            end
        end
    end
end

local function canRunCommand(ply, command)
    if not ZM_Util.RequireAdmin(ply, command) then return false end
    return true
end

local function printLines(ply, lines)
    for _, line in ipairs(lines) do
        ZM_Util.Reply(ply, line)
    end
end

local function reportToBridge(name, report, extra)
    if not (ZM_DevConsole and ZM_DevConsole.Report) then
        return
    end
    local value = { errors = report.errors, warnings = report.warnings, summary = StaticData:GetSummary() }
    for key, entry in pairs(extra or {}) do
        value[key] = entry
    end
    ZM_DevConsole:Report(name, value)
end

// Validates the files on disk (including runtime references) without replacing the live registry.
local function validateStaticData(ply, fileFilter)
    local registry, report = StaticData:Build()
    if registry and StaticData.RuntimeReady then
        StaticData:ValidateRuntimeReferences(registry, report)
    end
    local lines, errorCount = StaticData:FormatReport(report, fileFilter)
    table.insert(lines, 1, "Validating data_static files on disk (the live registry is unchanged):")
    printLines(ply, lines)
    reportToBridge("staticDataValidation", report)
    return errorCount == 0, errorCount > 0 and "static data validation found errors" or nil
end

local function reloadStaticData(ply)
    local loaded, report = StaticData:Reload()
    local lines = StaticData:FormatReport(report)
    if loaded then
        table.insert(lines, "Static data reloaded: " .. StaticData:GetSummary() .. ".")
        net.Start("ZM.StaticDataReloaded")
        net.Broadcast()
    else
        table.insert(lines, "Static data reload failed; the previous registry is still active (" .. StaticData:GetSummary() .. ").")
    end
    printLines(ply, lines)
    reportToBridge("staticDataReload", report, { loaded = loaded })
    if not loaded then
        return false, "static data reload failed"
    end
    return true
end

hook.Add("InitPostEntity", "ZM.StaticDataRuntimeReferences", function()
    StaticData.RuntimeReady = true
    local registry = StaticData:GetRegistry()
    if not registry then
        return
    end
    local report = { errors = {}, warnings = {} }
    StaticData:ValidateRuntimeReferences(registry, report)
    if #report.warnings > 0 then
        print("[ZombieSim] Static data has " .. #report.warnings .. " runtime reference warning(s); run zn_validate_static for details.")
    end
end)

concommand.Add("zn_reload_static", function(ply)
    if not canRunCommand(ply, "zn_reload_static") then
        return
    end
    reloadStaticData(ply)
end)

concommand.Add("zn_validate_static", function(ply, _, args)
    if not canRunCommand(ply, "zn_validate_static") then
        return
    end
    local fileFilter = nil
    if args[1] then
        fileFilter = {}
        for _, name in ipairs(args) do
            fileFilter[string.EndsWith(name, ".json") and name or name .. ".json"] = true
        end
    end
    validateStaticData(ply, fileFilter)
end, nil, "Validates data_static JSON. Optional arguments limit output to files, e.g. zn_validate_static loot entity_loot.")

concommand.Add("zn_validate_loot", function(ply)
    if not canRunCommand(ply, "zn_validate_loot") then
        return
    end
    validateStaticData(ply, lootFiles)
end, nil, "Validates loot.json and entity_loot.json.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zn_validate_static = function()
    return validateStaticData(nil, nil)
end
ZM_DevConsole.DirectCommands.zn_reload_static = function()
    return reloadStaticData(nil)
end
