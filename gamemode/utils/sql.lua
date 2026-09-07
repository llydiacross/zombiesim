// Server-side SQLite schema and persistence helpers for player attributes and progress.

// Creates the attribute table only on a completely new server database.
function ZM_CreatePlayerAttributesTable()
    if not sql.TableExists("player_attributes") then
        sql.Query("CREATE TABLE player_attributes (steamid TEXT PRIMARY KEY, Strength INTEGER, Agility INTEGER, Intelligence INTEGER, Endurance INTEGER, MachineGuns INTEGER, Shotguns INTEGER, Snipers INTEGER, WeaponCrafting INTEGER, ArmorCrafting INTEGER, Medicine INTEGER, Farming INTEGER, WeaponRepairing INTEGER, ArmorRepairing INTEGER, Mechanics INTEGER)")
    end
end

local playerDataSchema = "CREATE TABLE player_data (steamid TEXT NOT NULL, profile TEXT NOT NULL, XP INTEGER, Level INTEGER, MaxLevel INTEGER, Difficulty INTEGER, CellX INTEGER, CellY INTEGER, CurrentSafeZoneId TEXT, SkillPoints INTEGER, Health INTEGER, Stamina REAL, Hunger REAL, Thirst REAL, PRIMARY KEY (steamid, profile))"

local function getPlayerDataProfile(profile)
    profile = type(profile) == "string" and string.lower(profile) or nil
    if not profile or not string.match(profile, "^[a-z0-9_-]+$") then
        return nil
    end
    return profile
end

// Creates the core player table, then applies additive migrations for existing databases.
function ZM_CreatePlayerDataTable()
    if not sql.TableExists("player_data") then
        sql.Query(playerDataSchema)
        return
    end

    local columns = sql.Query("PRAGMA table_info(player_data)") or {}
    local existingColumns = {}
    for _, column in ipairs(columns) do
        existingColumns[column.name] = true
    end

    if not existingColumns.Health then
        sql.Query("ALTER TABLE player_data ADD COLUMN Health INTEGER DEFAULT 100")
    end

    if not existingColumns.Stamina then
        sql.Query("ALTER TABLE player_data ADD COLUMN Stamina REAL DEFAULT 100")
    end

    if not existingColumns.Hunger then
        sql.Query("ALTER TABLE player_data ADD COLUMN Hunger REAL DEFAULT 100")
    end

    if not existingColumns.Thirst then
        sql.Query("ALTER TABLE player_data ADD COLUMN Thirst REAL DEFAULT 100")
    end

    if not existingColumns.CurrentSafeZoneId then
        sql.Query("ALTER TABLE player_data ADD COLUMN CurrentSafeZoneId TEXT")
    end
end

// Upgrades an existing SteamID-only table by assigning each legacy record to the active profile.
function ZM_EnsureProfiledPlayerData(profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid player-data profile"
    end

    local columns = sql.Query("PRAGMA table_info(player_data)") or {}
    for _, column in ipairs(columns) do
        if column.name == "profile" then
            return true
        end
    end

    local function runMigrationQuery(query)
        local result = sql.Query(query)
        if result == false then
            return false, sql.LastError()
        end
        return true
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
    local copied, copyError = runMigrationQuery("INSERT INTO player_data (steamid, profile, XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina, Hunger, Thirst) SELECT steamid, " .. sql.SQLStr(profile) .. ", XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina, Hunger, Thirst FROM player_data_legacy")
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

// Returns whether the player already has a progression record in this world profile.
function ZM_PlayerPreviouslyExists(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false
    end

    local result = sql.Query("SELECT 1 FROM player_data WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    return result ~= nil and result ~= false
end

// Reads one player's attribute row, or nil when no row has been created yet.
function ZM_GetPlayerAttributes(steamid)
    local result = sql.Query("SELECT * FROM player_attributes WHERE steamid = " .. sql.SQLStr(steamid))
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
        return nil
    end

    local result = sql.Query("SELECT * FROM player_data WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if result then
        return result[1]
    else
        return nil
    end
end

// Replaces one attribute row. SteamID is SQL-escaped; values come from server-owned player state.
function ZM_SetPlayerAttributes(steamid, attributes)
    local query = "INSERT OR REPLACE INTO player_attributes (steamid, Strength, Agility, Intelligence, Endurance, MachineGuns, Shotguns, Snipers, WeaponCrafting, ArmorCrafting, Medicine, Farming, WeaponRepairing, ArmorRepairing, Mechanics) VALUES (" .. sql.SQLStr(steamid) .. ", " .. attributes.Strength .. ", " .. attributes.Agility .. ", " .. attributes.Intelligence .. ", " .. attributes.Endurance .. ", " .. attributes.MachineGuns .. ", " .. attributes.Shotguns .. ", " .. attributes.Snipers .. ", " .. attributes.WeaponCrafting .. ", " .. attributes.ArmorCrafting .. ", " .. attributes.Medicine .. ", " .. attributes.Farming .. ", " .. attributes.WeaponRepairing .. ", " .. attributes.ArmorRepairing .. ", " .. attributes.Mechanics .. ")"
    sql.Query(query)
end

// Replaces one core data row, including city position, survival state, and the optional current safe-room id.
function ZM_SetPlayerData(steamid, profile, data)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false
    end

    local currentSafeZoneId = data.CurrentSafeZoneId and sql.SQLStr(data.CurrentSafeZoneId) or "NULL"
    local query = "INSERT OR REPLACE INTO player_data (steamid, profile, XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina, Hunger, Thirst) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. data.XP .. ", " .. data.Level .. ", " .. data.MaxLevel .. ", " .. data.Difficulty .. ", " .. data.CellX .. ", " .. data.CellY .. ", " .. currentSafeZoneId .. ", " .. data.SkillPoints .. ", " .. data.Health .. ", " .. data.Stamina .. ", " .. data.Hunger .. ", " .. data.Thirst .. ")"
    return sql.Query(query) ~= false
end