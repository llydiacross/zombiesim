// Server-side SQLite schema and persistence helpers for player attributes and progress.

local playerAttributeSchema = "CREATE TABLE player_attributes (steamid TEXT NOT NULL, profile TEXT NOT NULL, Strength INTEGER, Agility INTEGER, Intelligence INTEGER, Endurance INTEGER, MachineGuns INTEGER, Shotguns INTEGER, Snipers INTEGER, WeaponCrafting INTEGER, ArmorCrafting INTEGER, Medicine INTEGER, Farming INTEGER, WeaponRepairing INTEGER, ArmorRepairing INTEGER, Mechanics INTEGER, Revision INTEGER NOT NULL DEFAULT 0, UpdatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))"
local playerDataSchema = "CREATE TABLE player_data (steamid TEXT NOT NULL, profile TEXT NOT NULL, XP INTEGER, Level INTEGER, MaxLevel INTEGER, Difficulty INTEGER, CellX INTEGER, CellY INTEGER, CurrentSafeZoneId TEXT, SkillPoints INTEGER, Health INTEGER, Stamina REAL, Hunger REAL, Thirst REAL, Revision INTEGER NOT NULL DEFAULT 0, UpdatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))"

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
    local query = "INSERT OR REPLACE INTO player_data (steamid, profile, XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina, Hunger, Thirst, Revision, UpdatedAt) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. integerValue(data.XP) .. ", " .. integerValue(data.Level, 1) .. ", " .. integerValue(data.MaxLevel, 300) .. ", " .. integerValue(data.Difficulty, 1) .. ", " .. integerValue(data.CellX) .. ", " .. integerValue(data.CellY) .. ", " .. currentSafeZoneId .. ", " .. integerValue(data.SkillPoints) .. ", " .. integerValue(data.Health, 100) .. ", " .. math.Clamp(tonumber(data.Stamina) or 100, 0, 100000) .. ", " .. math.Clamp(tonumber(data.Hunger) or 100, 0, 100) .. ", " .. math.Clamp(tonumber(data.Thirst) or 100, 0, 100) .. ", " .. revision .. ", " .. updatedAt .. ")"
    local saved, saveError = runQuery(query)
    if not saved then
        return false, saveError
    end
    if profile == "preview" then
        print(string.format("[ZombieSim] Preview data write (%s): %s -> cell %d,%d; skill points %d; safe zone %s", tostring(source or "unspecified"), steamid, integerValue(data.CellX), integerValue(data.CellY), integerValue(data.SkillPoints), tostring(data.CurrentSafeZoneId or "none")))
    end
    return true, revision
end