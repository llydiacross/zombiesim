// Server-side SQLite schema and persistence helpers for player attributes and progress.

local playerAttributeSchema = "CREATE TABLE player_attributes (steamid TEXT NOT NULL, profile TEXT NOT NULL, Strength INTEGER, Agility INTEGER, Intelligence INTEGER, Endurance INTEGER, MachineGuns INTEGER, Shotguns INTEGER, Snipers INTEGER, WeaponCrafting INTEGER, ArmorCrafting INTEGER, Medicine INTEGER, Farming INTEGER, WeaponRepairing INTEGER, ArmorRepairing INTEGER, Mechanics INTEGER, Revision INTEGER NOT NULL DEFAULT 0, UpdatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))"
local playerDataSchema = "CREATE TABLE player_data (steamid TEXT NOT NULL, profile TEXT NOT NULL, XP INTEGER, Level INTEGER, MaxLevel INTEGER, Difficulty INTEGER, CellX INTEGER, CellY INTEGER, CurrentSafeZoneId TEXT, SkillPoints INTEGER, Cash INTEGER NOT NULL DEFAULT 0, Health INTEGER, Stamina REAL, Hunger REAL, Thirst REAL, Job TEXT DEFAULT 'Civilian', Revision INTEGER NOT NULL DEFAULT 0, UpdatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))"
local playerItemsSchema = "CREATE TABLE IF NOT EXISTS player_items (steamid TEXT NOT NULL, profile TEXT NOT NULL, instanceId TEXT NOT NULL, container TEXT NOT NULL, slot INTEGER NOT NULL, itemId TEXT NOT NULL, count INTEGER NOT NULL, level INTEGER NOT NULL, mastercraft INTEGER NOT NULL DEFAULT 0, attributes TEXT, createdAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, instanceId), UNIQUE (steamid, profile, container, slot))"
local denStashItemsSchema = "CREATE TABLE IF NOT EXISTS den_stash_items (steamid TEXT NOT NULL, profile TEXT NOT NULL, safeZoneId TEXT NOT NULL, instanceId TEXT NOT NULL, slot INTEGER NOT NULL, itemId TEXT NOT NULL, count INTEGER NOT NULL, level INTEGER NOT NULL, mastercraft INTEGER NOT NULL DEFAULT 0, attributes TEXT, createdAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, safeZoneId, instanceId), UNIQUE (steamid, profile, safeZoneId, slot))"
local defaultJob = "Civilian"

local function getPlayerDataProfile(profile)
    profile = type(profile) == "string" and string.lower(profile) or nil
    if not profile or not string.match(profile, "^[a-z0-9_-]+$") then
        return nil
    end
    return profile
end

local function runQuery(query)
    local result = sql.Query(query)
    if result == false then
        return false, sql.LastError() or "SQLite query failed"
    end
    return true, result
end

local function getTableColumns(tableName)
    local result, queryError = runQuery("PRAGMA table_info(" .. tableName .. ")")
    if not result then
        return nil, queryError
    end

    local columns = {}
    for _, column in ipairs(queryError or {}) do
        columns[column.name] = true
    end
    return columns
end

local function addColumnIfMissing(tableName, columns, columnDefinition)
    local columnName = string.match(columnDefinition, "^(%w+)")
    if columns[columnName] then
        return true
    end
    return runQuery("ALTER TABLE " .. tableName .. " ADD COLUMN " .. columnDefinition)
end

local function migrateLegacyAttributes()
    local started, startError = runQuery("BEGIN")
    if not started then
        return false, startError
    end

    local function rollback(message)
        sql.Query("ROLLBACK")
        return false, message
    end

    local renamed, renameError = runQuery("ALTER TABLE player_attributes RENAME TO player_attributes_legacy")
    if not renamed then
        return rollback(renameError)
    end
    local created, createError = runQuery(playerAttributeSchema)
    if not created then
        return rollback(createError)
    end
    local copied, copyError = runQuery("INSERT INTO player_attributes (steamid, profile, Strength, Agility, Intelligence, Endurance, MachineGuns, Shotguns, Snipers, WeaponCrafting, ArmorCrafting, Medicine, Farming, WeaponRepairing, ArmorRepairing, Mechanics, Revision, UpdatedAt) SELECT steamid, 'city', Strength, Agility, Intelligence, Endurance, MachineGuns, Shotguns, Snipers, WeaponCrafting, ArmorCrafting, Medicine, Farming, WeaponRepairing, ArmorRepairing, Mechanics, 0, 0 FROM player_attributes_legacy")
    if not copied then
        return rollback(copyError)
    end
    local dropped, dropError = runQuery("DROP TABLE player_attributes_legacy")
    if not dropped then
        return rollback(dropError)
    end
    local committed, commitError = runQuery("COMMIT")
    if not committed then
        return false, commitError
    end
    return true
end

// Creates profile-scoped attributes and upgrades the old SteamID-only table into city records.
function ZM_CreatePlayerAttributesTable()
    if not sql.TableExists("player_attributes") then
        return runQuery(playerAttributeSchema)
    end

    local columns, columnsError = getTableColumns("player_attributes")
    if not columns then
        return false, columnsError
    end
    if not columns.profile then
        return migrateLegacyAttributes()
    end

    local armorRepairingAdded, armorRepairingError = addColumnIfMissing("player_attributes", columns, "ArmorRepairing INTEGER DEFAULT 0")
    if not armorRepairingAdded then
        return false, armorRepairingError
    end
    local revisionAdded, revisionError = addColumnIfMissing("player_attributes", columns, "Revision INTEGER NOT NULL DEFAULT 0")
    if not revisionAdded then
        return false, revisionError
    end
    local updatedAtAdded, updatedAtError = addColumnIfMissing("player_attributes", columns, "UpdatedAt INTEGER NOT NULL DEFAULT 0")
    if not updatedAtAdded then
        return false, updatedAtError
    end
    return true
end

// Creates the core player table, then applies additive migrations for existing databases.
function ZM_CreatePlayerDataTable()
    if not sql.TableExists("player_data") then
        return runQuery(playerDataSchema)
    end

    local existingColumns, columnsError = getTableColumns("player_data")
    if not existingColumns then
        return false, columnsError
    end

    for _, columnDefinition in ipairs({
        "Health INTEGER DEFAULT 100",
        "Stamina REAL DEFAULT 100",
        "Hunger REAL DEFAULT 100",
        "Thirst REAL DEFAULT 100",
        "CurrentSafeZoneId TEXT",
        "Cash INTEGER NOT NULL DEFAULT 0",
        "Job TEXT DEFAULT 'Civilian'",
        "Revision INTEGER NOT NULL DEFAULT 0",
        "UpdatedAt INTEGER NOT NULL DEFAULT 0"
    }) do
        local added, addError = addColumnIfMissing("player_data", existingColumns, columnDefinition)
        if not added then
            return false, addError
        end
    end
    return true
end

// Upgrades an existing SteamID-only table by assigning each legacy record to the active profile.
function ZM_EnsureProfiledPlayerData(profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid player-data profile"
    end

    local columns, columnsError = getTableColumns("player_data")
    if not columns then
        return false, columnsError
    end
    if columns.profile then
        return true
    end

    local function runMigrationQuery(query)
        return runQuery(query)
    end

    local started, startError = runMigrationQuery("BEGIN")
    if not started then
        return false, startError
    end

    local function rollback(message)
        sql.Query("ROLLBACK")
        return false, message
    end

    local renamed, renameError = runMigrationQuery("ALTER TABLE player_data RENAME TO player_data_legacy")
    if not renamed then
        return rollback(renameError)
    end
    local created, createError = runMigrationQuery(playerDataSchema)
    if not created then
        return rollback(createError)
    end
    local copied, copyError = runMigrationQuery("INSERT INTO player_data (steamid, profile, XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina, Hunger, Thirst, Revision, UpdatedAt) SELECT steamid, " .. sql.SQLStr(profile) .. ", XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina, Hunger, Thirst, 0, 0 FROM player_data_legacy")
    if not copied then
        return rollback(copyError)
    end
    local dropped, dropError = runMigrationQuery("DROP TABLE player_data_legacy")
    if not dropped then
        return rollback(dropError)
    end
    local committed, commitError = runMigrationQuery("COMMIT")
    if not committed then
        return false, commitError
    end

    return true
end

// Reads one player's profile-scoped attribute row, or nil when no row has been created yet.
function ZM_GetPlayerAttributes(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return nil, "Invalid player-attribute profile"
    end

    local result = sql.Query("SELECT * FROM player_attributes WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if result == false then
        return nil, sql.LastError() or "Could not read player attributes"
    end
    if result then
        return result[1]
    else
        return nil
    end
end

// Reads one player's progression, survival, and logical-cell row for a world profile.
function ZM_GetPlayerData(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return nil, "Invalid player-data profile"
    end

    local result = sql.Query("SELECT * FROM player_data WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if result == false then
        return nil, sql.LastError() or "Could not read player data"
    end
    if result then
        local data = result[1]
        if data and (data.CurrentSafeZoneId == "" or data.CurrentSafeZoneId == "NULL") then
            data.CurrentSafeZoneId = nil
        end
        return data
    else
        return nil
    end
end

local function integerValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback or 0
    end
    return math.floor(value)
end

// Returns a safe stored job name, falling back to Civilian.
function ZM_NormalizeJob(job)
    if type(job) ~= "string" or #job > 32 or not string.match(job, "^%a+$") then
        return defaultJob
    end
    return job
end

function ZM_CreatePlayerItemsTable()
    local items, itemError = runQuery(playerItemsSchema)
    if not items then return false, itemError end
    local stash, stashError = runQuery(denStashItemsSchema)
    if not stash then return false, stashError end
    return runQuery("CREATE TABLE IF NOT EXISTS equipped_weapon_slots (steamid TEXT NOT NULL, profile TEXT NOT NULL, slot INTEGER NOT NULL, instanceId TEXT, selected INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, slot))")
end

function ZM_GetDenStashItems(steamid, profile, safeZoneId)
    profile = getPlayerDataProfile(profile)
    if not profile or type(safeZoneId) ~= "string" or safeZoneId == "" then return nil, "Invalid den-stash identity" end
    local result = sql.Query("SELECT * FROM den_stash_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND safeZoneId = " .. sql.SQLStr(safeZoneId) .. " ORDER BY slot")
    if result == false then return nil, sql.LastError() or "Could not read den stash" end
    return result or {}
end

function ZM_ReplaceDenStashItems(steamid, profile, safeZoneId, rows)
    profile = getPlayerDataProfile(profile)
    if not profile or type(safeZoneId) ~= "string" or safeZoneId == "" then return false, "Invalid den-stash identity" end
    local deleted, deleteError = runQuery("DELETE FROM den_stash_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND safeZoneId = " .. sql.SQLStr(safeZoneId))
    if not deleted then return false, deleteError end
    for _, row in ipairs(rows or {}) do
        local attributes = row.attributes and sql.SQLStr(util.TableToJSON(row.attributes, false) or "{}") or "NULL"
        local inserted, insertError = runQuery("INSERT INTO den_stash_items (steamid, profile, safeZoneId, instanceId, slot, itemId, count, level, mastercraft, attributes, createdAt) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. sql.SQLStr(safeZoneId) .. ", " .. sql.SQLStr(row.instanceId) .. ", " .. integerValue(row.slot) .. ", " .. sql.SQLStr(row.itemId) .. ", " .. integerValue(row.count, 1) .. ", " .. integerValue(row.level, 1) .. ", " .. (row.mastercraft and 1 or 0) .. ", " .. attributes .. ", " .. integerValue(row.createdAt) .. ")")
        if not inserted then return false, insertError end
    end
    return true
end

function ZM_GetEquippedWeaponSlots(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid equipped-weapon profile" end
    local result = sql.Query("SELECT * FROM equipped_weapon_slots WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " ORDER BY slot")
    if result == false then return nil, sql.LastError() or "Could not read equipped weapons" end
    return result or {}
end

function ZM_ReplaceEquippedWeaponSlots(steamid, profile, slots)
    profile = getPlayerDataProfile(profile)
    if not profile then return false, "Invalid equipped-weapon profile" end
    local deleted, deleteError = runQuery("DELETE FROM equipped_weapon_slots WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if not deleted then return false, deleteError end
    for slot = 1, 3 do
        local row = slots[slot] or {}
        local instanceId = row.instanceId and sql.SQLStr(row.instanceId) or "NULL"
        local selected = row.selected and 1 or 0
        local inserted, insertError = runQuery("INSERT INTO equipped_weapon_slots (steamid, profile, slot, instanceId, selected) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. slot .. ", " .. instanceId .. ", " .. selected .. ")")
        if not inserted then return false, insertError end
    end
    return true
end

// Reads every stored item row for one player and profile, ordered by container and slot.
function ZM_GetPlayerItems(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return nil, "Invalid player-item profile"
    end
    local result = sql.Query("SELECT * FROM player_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " ORDER BY container, slot")
    if result == false then
        return nil, sql.LastError() or "Could not read player items"
    end
    return result or {}
end

// Replaces all of one player's item rows in a single transaction; the previous rows survive any failure.
function ZM_ReplacePlayerItems(steamid, profile, rows)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid player-item profile"
    end

    local started, startError = runQuery("BEGIN")
    if not started then
        return false, startError
    end
    local function rollback(message)
        sql.Query("ROLLBACK")
        return false, message
    end

    local owner = sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile)
    local deleted, deleteError = runQuery("DELETE FROM player_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if not deleted then
        return rollback(deleteError)
    end
    for _, row in ipairs(rows) do
        local attributes = row.attributes and sql.SQLStr(util.TableToJSON(row.attributes, false) or "{}") or "NULL"
        local inserted, insertError = runQuery("INSERT INTO player_items (steamid, profile, instanceId, container, slot, itemId, count, level, mastercraft, attributes, createdAt) VALUES (" .. owner .. ", " .. sql.SQLStr(row.instanceId) .. ", " .. sql.SQLStr(row.container) .. ", " .. integerValue(row.slot) .. ", " .. sql.SQLStr(row.itemId) .. ", " .. integerValue(row.count, 1) .. ", " .. integerValue(row.level, 1) .. ", " .. (row.mastercraft and 1 or 0) .. ", " .. attributes .. ", " .. integerValue(row.createdAt) .. ")")
        if not inserted then
            return rollback(insertError)
        end
    end
    local committed, commitError = runQuery("COMMIT")
    if not committed then
        return rollback(commitError)
    end
    return true
end

// Deletes all of one player's item rows for a profile.
function ZM_DeletePlayerItems(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid player-item profile"
    end
    return runQuery("DELETE FROM player_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
end

// World loot spots per profile and logical cell. lastPresentAt drives the refresh-after-absence rule.
function ZM_CreateLootSpotTables()
    local cells, cellsError = runQuery("CREATE TABLE IF NOT EXISTS loot_cells (profile TEXT NOT NULL, cellId INTEGER NOT NULL, generatedAt INTEGER NOT NULL, lastPresentAt INTEGER NOT NULL, PRIMARY KEY (profile, cellId))")
    if not cells then
        return false, cellsError
    end
    return runQuery("CREATE TABLE IF NOT EXISTS loot_spots (profile TEXT NOT NULL, cellId INTEGER NOT NULL, spotKey TEXT NOT NULL, state TEXT NOT NULL, item TEXT, PRIMARY KEY (profile, cellId, spotKey))")
end

function ZM_GetLootCell(profile, cellId)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return nil, "Invalid loot profile"
    end
    local result = sql.Query("SELECT * FROM loot_cells WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. integerValue(cellId))
    if result == false then
        return nil, sql.LastError() or "Could not read loot cell"
    end
    return result and result[1] or nil
end

function ZM_GetLootSpots(profile, cellId)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return nil, "Invalid loot profile"
    end
    local result = sql.Query("SELECT * FROM loot_spots WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. integerValue(cellId) .. " ORDER BY spotKey")
    if result == false then
        return nil, sql.LastError() or "Could not read loot spots"
    end
    return result or {}
end

local function lootItemValue(item)
    return item and sql.SQLStr(util.TableToJSON(item, false) or "{}") or "NULL"
end

// Replaces a cell's spots and timestamps in one transaction (used when a cell is generated or re-rolled).
function ZM_ReplaceLootCell(profile, cellId, generatedAt, lastPresentAt, spots)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid loot profile"
    end
    local cell = integerValue(cellId)
    local started, startError = runQuery("BEGIN")
    if not started then
        return false, startError
    end
    local function rollback(message)
        sql.Query("ROLLBACK")
        return false, message
    end
    local deleted, deleteError = runQuery("DELETE FROM loot_spots WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. cell)
    if not deleted then
        return rollback(deleteError)
    end
    for _, spot in ipairs(spots) do
        local inserted, insertError = runQuery("INSERT INTO loot_spots (profile, cellId, spotKey, state, item) VALUES (" .. sql.SQLStr(profile) .. ", " .. cell .. ", " .. sql.SQLStr(spot.key) .. ", " .. sql.SQLStr(spot.state) .. ", " .. lootItemValue(spot.item) .. ")")
        if not inserted then
            return rollback(insertError)
        end
    end
    local saved, saveError = runQuery("INSERT OR REPLACE INTO loot_cells (profile, cellId, generatedAt, lastPresentAt) VALUES (" .. sql.SQLStr(profile) .. ", " .. cell .. ", " .. integerValue(generatedAt) .. ", " .. integerValue(lastPresentAt) .. ")")
    if not saved then
        return rollback(saveError)
    end
    local committed, commitError = runQuery("COMMIT")
    if not committed then
        return rollback(commitError)
    end
    return true
end

function ZM_SetLootSpot(profile, cellId, spotKey, state, item)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid loot profile"
    end
    return runQuery("UPDATE loot_spots SET state = " .. sql.SQLStr(state) .. ", item = " .. lootItemValue(item) .. " WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. integerValue(cellId) .. " AND spotKey = " .. sql.SQLStr(spotKey))
end

function ZM_TouchLootCell(profile, cellId, lastPresentAt)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid loot profile"
    end
    return runQuery("UPDATE loot_cells SET lastPresentAt = " .. integerValue(lastPresentAt) .. " WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. integerValue(cellId))
end

function ZM_DeleteLootCells(profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid loot profile"
    end
    local spots, spotsError = runQuery("DELETE FROM loot_spots WHERE profile = " .. sql.SQLStr(profile))
    if not spots then
        return false, spotsError
    end
    return runQuery("DELETE FROM loot_cells WHERE profile = " .. sql.SQLStr(profile))
end

// Replaces one profile-scoped attribute row and advances its revision.
function ZM_SetPlayerAttributes(steamid, profile, attributes)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid player-attribute profile"
    end

    local existing, existingError = ZM_GetPlayerAttributes(steamid, profile)
    if existingError then
        return false, existingError
    end
    local revision = integerValue(existing and existing.Revision, 0) + 1
    local updatedAt = os.time()
    local query = "INSERT OR REPLACE INTO player_attributes (steamid, profile, Strength, Agility, Intelligence, Endurance, MachineGuns, Shotguns, Snipers, WeaponCrafting, ArmorCrafting, Medicine, Farming, WeaponRepairing, ArmorRepairing, Mechanics, Revision, UpdatedAt) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. integerValue(attributes.Strength) .. ", " .. integerValue(attributes.Agility) .. ", " .. integerValue(attributes.Intelligence) .. ", " .. integerValue(attributes.Endurance) .. ", " .. integerValue(attributes.MachineGuns) .. ", " .. integerValue(attributes.Shotguns) .. ", " .. integerValue(attributes.Snipers) .. ", " .. integerValue(attributes.WeaponCrafting) .. ", " .. integerValue(attributes.ArmorCrafting) .. ", " .. integerValue(attributes.Medicine) .. ", " .. integerValue(attributes.Farming) .. ", " .. integerValue(attributes.WeaponRepairing) .. ", " .. integerValue(attributes.ArmorRepairing) .. ", " .. integerValue(attributes.Mechanics) .. ", " .. revision .. ", " .. updatedAt .. ")"
    return runQuery(query)
end

// Replaces one core data row, including city position, survival state, and the optional current safe-room id.
function ZM_SetPlayerData(steamid, profile, data, source)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false
    end

    local existing, existingError = ZM_GetPlayerData(steamid, profile)
    if existingError then
        return false, existingError
    end
    local revision = integerValue(existing and existing.Revision, 0) + 1
    local updatedAt = os.time()
    local currentSafeZoneId = data.CurrentSafeZoneId and sql.SQLStr(data.CurrentSafeZoneId) or "NULL"
    // Callers that do not manage the job (such as the preview editor) keep the stored value.
    local job = ZM_NormalizeJob(data.Job or (existing and existing.Job))
    local query = "INSERT OR REPLACE INTO player_data (steamid, profile, XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Cash, Health, Stamina, Hunger, Thirst, Job, Revision, UpdatedAt) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. integerValue(data.XP) .. ", " .. integerValue(data.Level, 1) .. ", " .. integerValue(data.MaxLevel, 300) .. ", " .. integerValue(data.Difficulty, 1) .. ", " .. integerValue(data.CellX) .. ", " .. integerValue(data.CellY) .. ", " .. currentSafeZoneId .. ", " .. integerValue(data.SkillPoints) .. ", " .. integerValue(data.Cash) .. ", " .. integerValue(data.Health, 100) .. ", " .. math.Clamp(tonumber(data.Stamina) or 100, 0, 100000) .. ", " .. math.Clamp(tonumber(data.Hunger) or 100, 0, 100) .. ", " .. math.Clamp(tonumber(data.Thirst) or 100, 0, 100) .. ", " .. sql.SQLStr(job) .. ", " .. revision .. ", " .. updatedAt .. ")"
    local saved, saveError = runQuery(query)
    if not saved then
        return false, saveError
    end
    if profile == "preview" then
        print(string.format("[ZombieSim] Preview data write (%s): %s -> cell %d,%d; skill points %d; safe zone %s", tostring(source or "unspecified"), steamid, integerValue(data.CellX), integerValue(data.CellY), integerValue(data.SkillPoints), tostring(data.CurrentSafeZoneId or "none")))
    end
    return true, revision
end