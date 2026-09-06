// Server-side SQLite schema and persistence helpers for player attributes and progress.

// Creates the attribute table only on a completely new server database.
function ZM_CreatePlayerAttributesTable()
    if not sql.TableExists("player_attributes") then
        sql.Query("CREATE TABLE player_attributes (steamid TEXT PRIMARY KEY, Strength INTEGER, Agility INTEGER, Intelligence INTEGER, Endurance INTEGER, MachineGuns INTEGER, Shotguns INTEGER, Snipers INTEGER, WeaponCrafting INTEGER, ArmorCrafting INTEGER, Medicine INTEGER, Farming INTEGER, WeaponRepairing INTEGER, ArmorRepairing INTEGER, Mechanics INTEGER)")
    end
end

// Creates the core player table, then applies additive migrations for existing databases.
function ZM_CreatePlayerDataTable()
    if not sql.TableExists("player_data") then
        sql.Query("CREATE TABLE player_data (steamid TEXT PRIMARY KEY, XP INTEGER, Level INTEGER, MaxLevel INTEGER, Difficulty INTEGER, CellX INTEGER, CellY INTEGER, CurrentSafeZoneId TEXT, SkillPoints INTEGER, Health INTEGER, Stamina REAL)")
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

    if not existingColumns.CurrentSafeZoneId then
        sql.Query("ALTER TABLE player_data ADD COLUMN CurrentSafeZoneId TEXT")
    end
end

// Returns whether the player has an attribute record and is therefore not a first-time player.
function ZM_PlayerPreviouslyExists(steamid)
    local result = sql.Query("SELECT * FROM player_attributes WHERE steamid = " .. sql.SQLStr(steamid))
    if result then
        return true
    else
        return false
    end
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

// Reads one player's progression, survival, and logical-cell row.
function ZM_GetPlayerData(steamid)
    local result = sql.Query("SELECT * FROM player_data WHERE steamid = " .. sql.SQLStr(steamid))
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

// Replaces one core data row, including city position and the optional current safe-room id.
function ZM_SetPlayerData(steamid, data)
    local currentSafeZoneId = data.CurrentSafeZoneId and sql.SQLStr(data.CurrentSafeZoneId) or "NULL"
    local query = "INSERT OR REPLACE INTO player_data (steamid, XP, Level, MaxLevel, Difficulty, CellX, CellY, CurrentSafeZoneId, SkillPoints, Health, Stamina) VALUES (" .. sql.SQLStr(steamid) .. ", " .. data.XP .. ", " .. data.Level .. ", " .. data.MaxLevel .. ", " .. data.Difficulty .. ", " .. data.CellX .. ", " .. data.CellY .. ", " .. currentSafeZoneId .. ", " .. data.SkillPoints .. ", " .. data.Health .. ", " .. data.Stamina .. ")"
    sql.Query(query)
end