// Server-side SQLite schema and persistence helpers for player attributes and progress.

local playerAttributeSchema = "CREATE TABLE player_attributes (steamid TEXT NOT NULL, profile TEXT NOT NULL, Strength INTEGER, Agility INTEGER, Intelligence INTEGER, Endurance INTEGER, MachineGuns INTEGER, Shotguns INTEGER, Snipers INTEGER, WeaponCrafting INTEGER, ArmorCrafting INTEGER, Medicine INTEGER, Farming INTEGER, WeaponRepairing INTEGER, ArmorRepairing INTEGER, Mechanics INTEGER, Revision INTEGER NOT NULL DEFAULT 0, UpdatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))"
local playerDataSchema = "CREATE TABLE player_data (steamid TEXT NOT NULL, profile TEXT NOT NULL, XP INTEGER, Level INTEGER, MaxLevel INTEGER, Difficulty INTEGER, CellX INTEGER, CellY INTEGER, CurrentSafeZoneId TEXT, SkillPoints INTEGER, Cash INTEGER NOT NULL DEFAULT 0, Health INTEGER, Stamina REAL, Hunger REAL, Thirst REAL, Job TEXT DEFAULT 'Civilian', Revision INTEGER NOT NULL DEFAULT 0, UpdatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))"
local playerItemsSchema = "CREATE TABLE IF NOT EXISTS player_items (steamid TEXT NOT NULL, profile TEXT NOT NULL, instanceId TEXT NOT NULL, container TEXT NOT NULL, slot INTEGER NOT NULL, itemId TEXT NOT NULL, count INTEGER NOT NULL, level INTEGER NOT NULL, mastercraft INTEGER NOT NULL DEFAULT 0, attributes TEXT, clip INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, instanceId), UNIQUE (steamid, profile, container, slot))"
local denStashItemsSchema = "CREATE TABLE IF NOT EXISTS den_stash_items (steamid TEXT NOT NULL, profile TEXT NOT NULL, safeZoneId TEXT NOT NULL, instanceId TEXT NOT NULL, slot INTEGER NOT NULL, itemId TEXT NOT NULL, count INTEGER NOT NULL, level INTEGER NOT NULL, mastercraft INTEGER NOT NULL DEFAULT 0, attributes TEXT, clip INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, safeZoneId, instanceId), UNIQUE (steamid, profile, safeZoneId, slot))"
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

    local itemColumns, itemColumnsError = getTableColumns("player_items")
    if not itemColumns then return false, itemColumnsError end
    local itemClipAdded, itemClipError = addColumnIfMissing("player_items", itemColumns, "clip INTEGER NOT NULL DEFAULT 0")
    if not itemClipAdded then return false, itemClipError end

    local stashColumns, stashColumnsError = getTableColumns("den_stash_items")
    if not stashColumns then return false, stashColumnsError end
    local stashClipAdded, stashClipError = addColumnIfMissing("den_stash_items", stashColumns, "clip INTEGER NOT NULL DEFAULT 0")
    if not stashClipAdded then return false, stashClipError end

    return runQuery("CREATE TABLE IF NOT EXISTS equipped_weapon_slots (steamid TEXT NOT NULL, profile TEXT NOT NULL, slot INTEGER NOT NULL, instanceId TEXT, selected INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, slot))")
end

function ZM_GetDenStashItems(steamid, profile, safeZoneId)
    profile = getPlayerDataProfile(profile)
    if not profile or type(safeZoneId) ~= "string" or safeZoneId == "" then return nil, "Invalid den-stash identity" end
    local result = sql.Query("SELECT * FROM den_stash_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND safeZoneId = " .. sql.SQLStr(safeZoneId) .. " ORDER BY slot")
    if result == false then return nil, sql.LastError() or "Could not read den stash" end
    return result or {}
end

local function writeDenStashRows(steamid, profile, safeZoneId, rows)
    local deleted, deleteError = runQuery("DELETE FROM den_stash_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND safeZoneId = " .. sql.SQLStr(safeZoneId))
    if not deleted then return false, deleteError end
    for _, row in ipairs(rows or {}) do
        local attributes = row.attributes and sql.SQLStr(util.TableToJSON(row.attributes, false) or "{}") or "NULL"
        local inserted, insertError = runQuery("INSERT INTO den_stash_items (steamid, profile, safeZoneId, instanceId, slot, itemId, count, level, mastercraft, attributes, clip, createdAt) VALUES (" .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. sql.SQLStr(safeZoneId) .. ", " .. sql.SQLStr(row.instanceId) .. ", " .. integerValue(row.slot) .. ", " .. sql.SQLStr(row.itemId) .. ", " .. integerValue(row.count, 1) .. ", " .. integerValue(row.level, 1) .. ", " .. (row.mastercraft and 1 or 0) .. ", " .. attributes .. ", " .. integerValue(row.clip) .. ", " .. integerValue(row.createdAt) .. ")")
        if not inserted then return false, insertError end
    end
    return true
end

local function writePlayerItemRows(steamid, profile, rows)
    local owner = sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile)
    local deleted, deleteError = runQuery("DELETE FROM player_items WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if not deleted then return false, deleteError end
    for _, row in ipairs(rows or {}) do
        local attributes = row.attributes and sql.SQLStr(util.TableToJSON(row.attributes, false) or "{}") or "NULL"
        local inserted, insertError = runQuery("INSERT INTO player_items (steamid, profile, instanceId, container, slot, itemId, count, level, mastercraft, attributes, clip, createdAt) VALUES (" .. owner .. ", " .. sql.SQLStr(row.instanceId) .. ", " .. sql.SQLStr(row.container) .. ", " .. integerValue(row.slot) .. ", " .. sql.SQLStr(row.itemId) .. ", " .. integerValue(row.count, 1) .. ", " .. integerValue(row.level, 1) .. ", " .. (row.mastercraft and 1 or 0) .. ", " .. attributes .. ", " .. integerValue(row.clip) .. ", " .. integerValue(row.createdAt) .. ")")
        if not inserted then return false, insertError end
    end
    return true
end

// Runs writer() inside one transaction; any failure rolls every write back.
local function inTransaction(writer)
    local started, startError = runQuery("BEGIN")
    if not started then return false, startError end
    local ok, writeError = writer()
    if not ok then
        sql.Query("ROLLBACK")
        return false, writeError
    end
    local committed, commitError = runQuery("COMMIT")
    if not committed then
        sql.Query("ROLLBACK")
        return false, commitError
    end
    return true
end

// Replaces one player's stash rows for a den in a single transaction; the previous rows survive any failure.
function ZM_ReplaceDenStashItems(steamid, profile, safeZoneId, rows)
    profile = getPlayerDataProfile(profile)
    if not profile or type(safeZoneId) ~= "string" or safeZoneId == "" then return false, "Invalid den-stash identity" end
    return inTransaction(function() return writeDenStashRows(steamid, profile, safeZoneId, rows) end)
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
    return inTransaction(function() return writePlayerItemRows(steamid, profile, rows) end)
end

// Replaces a player's carried items and one den stash together, so a change spanning both is all-or-nothing.
function ZM_ReplacePlayerAndDenStashItems(steamid, profile, playerRows, safeZoneId, stashRows)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return false, "Invalid player-item profile"
    end
    if type(safeZoneId) ~= "string" or safeZoneId == "" then return false, "Invalid den-stash identity" end
    return inTransaction(function()
        local savedPlayer, playerError = writePlayerItemRows(steamid, profile, playerRows)
        if not savedPlayer then return false, playerError end
        return writeDenStashRows(steamid, profile, safeZoneId, stashRows)
    end)
end

// Daily profession deliveries: one row per player, profile, and UTC day. The primary key makes a second claim
// for the same day fail inside its transaction, so a delivery can never be granted twice.
function ZM_CreateProfessionTables()
    return runQuery("CREATE TABLE IF NOT EXISTS profession_claims (steamid TEXT NOT NULL, profile TEXT NOT NULL, day TEXT NOT NULL, job TEXT NOT NULL, claimedAt INTEGER NOT NULL, items TEXT, PRIMARY KEY (steamid, profile, day))")
end

function ZM_GetProfessionClaim(steamid, profile, day)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid profession-claim profile" end
    local result = sql.Query("SELECT * FROM profession_claims WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND day = " .. sql.SQLStr(day))
    if result == false then return nil, sql.LastError() or "Could not read profession claims" end
    return result and result[1] or nil
end

function ZM_DeleteProfessionClaims(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then return false, "Invalid profession-claim profile" end
    return runQuery("DELETE FROM profession_claims WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
end

// Installed implants: at most one per player, profile, and implant slot. Rows leave player_items when installed.
function ZM_CreateImplantTables()
    return runQuery("CREATE TABLE IF NOT EXISTS player_implants (steamid TEXT NOT NULL, profile TEXT NOT NULL, slot TEXT NOT NULL, instanceId TEXT NOT NULL, itemId TEXT NOT NULL, level INTEGER NOT NULL, createdAt INTEGER NOT NULL DEFAULT 0, installedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile, slot))")
end

function ZM_GetPlayerImplants(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid implant profile" end
    local result = sql.Query("SELECT * FROM player_implants WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " ORDER BY slot")
    if result == false then return nil, sql.LastError() or "Could not read implants" end
    return result or {}
end

function ZM_DeletePlayerImplants(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then return false, "Invalid implant profile" end
    return runQuery("DELETE FROM player_implants WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
end

local function writeImplantRows(steamid, profile, rows)
    local deleted, deleteError = runQuery("DELETE FROM player_implants WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if not deleted then return false, deleteError end
    for _, row in ipairs(rows or {}) do
        if type(row.slot) ~= "string" or type(row.instanceId) ~= "string" or type(row.itemId) ~= "string" then
            return false, "implant rows need a slot, instanceId, and itemId"
        end
        local inserted, insertError = runQuery("INSERT INTO player_implants (steamid, profile, slot, instanceId, itemId, level, createdAt, installedAt) VALUES ("
            .. sql.SQLStr(steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. sql.SQLStr(row.slot) .. ", " .. sql.SQLStr(row.instanceId) .. ", "
            .. sql.SQLStr(row.itemId) .. ", " .. integerValue(row.level) .. ", " .. integerValue(row.createdAt) .. ", " .. integerValue(row.installedAt) .. ")")
        if not inserted then return false, insertError end
    end
    return true
end

// Credits: one balance row per player and profile, kept outside player_data so ordinary saves never overwrite it.
// Every change appends a credit_ledger row in the same transaction. Mastercraft attempts are keyed by item instance,
// so a second attempt on the same instance fails inside its transaction.
function ZM_CreateCreditTables()
    local balances, balancesError = runQuery("CREATE TABLE IF NOT EXISTS player_credits (steamid TEXT NOT NULL, profile TEXT NOT NULL, credits INTEGER NOT NULL DEFAULT 0, updatedAt INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, profile))")
    if not balances then return false, balancesError end
    local ledger, ledgerError = runQuery("CREATE TABLE IF NOT EXISTS credit_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT NOT NULL, profile TEXT NOT NULL, delta INTEGER NOT NULL, balance INTEGER NOT NULL, reason TEXT NOT NULL, ref TEXT, createdAt INTEGER NOT NULL)")
    if not ledger then return false, ledgerError end
    return runQuery("CREATE TABLE IF NOT EXISTS mastercraft_attempts (steamid TEXT NOT NULL, profile TEXT NOT NULL, instanceId TEXT NOT NULL, itemId TEXT NOT NULL, level INTEGER NOT NULL, credits INTEGER NOT NULL, ultra INTEGER NOT NULL DEFAULT 0, attributes TEXT, attemptedAt INTEGER NOT NULL, PRIMARY KEY (steamid, profile, instanceId))")
end

// Returns the stored balance (0 when the player has no row yet), or nil and an error.
function ZM_GetPlayerCredits(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid credit profile" end
    local result = sql.Query("SELECT credits FROM player_credits WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
    if result == false then return nil, sql.LastError() or "Could not read credits" end
    return result and tonumber(result[1].credits) or 0
end

function ZM_GetCreditLedger(steamid, profile, limit)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid credit profile" end
    local result = sql.Query("SELECT * FROM credit_ledger WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " ORDER BY id DESC LIMIT " .. math.Clamp(integerValue(limit, 10), 1, 100))
    if result == false then return nil, sql.LastError() or "Could not read the credit ledger" end
    return result or {}
end

function ZM_GetMastercraftAttempt(steamid, profile, instanceId)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid mastercraft profile" end
    local result = sql.Query("SELECT * FROM mastercraft_attempts WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND instanceId = " .. sql.SQLStr(instanceId))
    if result == false then return nil, sql.LastError() or "Could not read mastercraft attempts" end
    return result and result[1] or false
end

// Development and test cleanup: deletes a player's balance, ledger, and mastercraft attempts for a profile.
function ZM_DeletePlayerCredits(steamid, profile)
    profile = getPlayerDataProfile(profile)
    if not profile then return false, "Invalid credit profile" end
    local owner = " WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile)
    return inTransaction(function()
        for _, tableName in ipairs({ "player_credits", "credit_ledger", "mastercraft_attempts" }) do
            local deleted, deleteError = runQuery("DELETE FROM " .. tableName .. owner)
            if not deleted then return false, deleteError end
        end
        return true
    end)
end

// Offline den trading. trade_stock holds each den's shared daily stock per trader offer (sold counts only; the
// stock itself is regenerated deterministically). trade_ledger records every buy and sell once per request id.
function ZM_CreateTradeTables()
    local stock, stockError = runQuery("CREATE TABLE IF NOT EXISTS trade_stock (profile TEXT NOT NULL, safeZoneId TEXT NOT NULL, traderId TEXT NOT NULL, day TEXT NOT NULL, offerKey TEXT NOT NULL, stock INTEGER NOT NULL, sold INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (profile, safeZoneId, traderId, day, offerKey))")
    if not stock then return false, stockError end
    return runQuery("CREATE TABLE IF NOT EXISTS trade_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT NOT NULL, profile TEXT NOT NULL, requestId TEXT NOT NULL, safeZoneId TEXT NOT NULL, traderId TEXT NOT NULL, day TEXT NOT NULL, kind TEXT NOT NULL, itemId TEXT NOT NULL, count INTEGER NOT NULL, cash INTEGER NOT NULL DEFAULT 0, credits INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL, UNIQUE (steamid, profile, requestId))")
end

// Units sold today per offer key for one den trader: { [offerKey] = sold }, or nil and an error.
function ZM_GetTradeStock(profile, safeZoneId, traderId, day)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid trade profile" end
    local result = sql.Query("SELECT offerKey, sold FROM trade_stock WHERE profile = " .. sql.SQLStr(profile) .. " AND safeZoneId = " .. sql.SQLStr(safeZoneId)
        .. " AND traderId = " .. sql.SQLStr(traderId) .. " AND day = " .. sql.SQLStr(day))
    if result == false then return nil, sql.LastError() or "Could not read trader stock" end
    local sold = {}
    for _, row in ipairs(result or {}) do sold[row.offerKey] = tonumber(row.sold) or 0 end
    return sold
end

// Cash the player has received from sales on a day, or nil and an error.
function ZM_GetTradeSaleTotal(steamid, profile, day)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid trade profile" end
    local total = sql.QueryValue("SELECT COALESCE(SUM(cash), 0) FROM trade_ledger WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND kind = 'sell' AND day = " .. sql.SQLStr(day))
    if total == false then return nil, sql.LastError() or "Could not read trade sales" end
    return tonumber(total) or 0
end

// The ledger row for a request id, false when there is none, or nil and an error.
function ZM_GetTradeRequest(steamid, profile, requestId)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid trade profile" end
    local result = sql.Query("SELECT * FROM trade_ledger WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND requestId = " .. sql.SQLStr(requestId))
    if result == false then return nil, sql.LastError() or "Could not read the trade ledger" end
    return result and result[1] or false
end

function ZM_GetTradeLedger(steamid, profile, limit)
    profile = getPlayerDataProfile(profile)
    if not profile then return nil, "Invalid trade profile" end
    local result = sql.Query("SELECT * FROM trade_ledger WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " ORDER BY id DESC LIMIT " .. math.Clamp(integerValue(limit, 10), 1, 100))
    if result == false then return nil, sql.LastError() or "Could not read the trade ledger" end
    return result or {}
end

// Drops stock rows from days before `day`; they can never be read again.
function ZM_PruneTradeStock(day)
    return runQuery("DELETE FROM trade_stock WHERE day < " .. sql.SQLStr(day))
end

// Development and test cleanup: a player's trade ledger for a profile, plus (optionally) that profile's den stock.
function ZM_DeleteTradeData(steamid, profile, includeStock)
    profile = getPlayerDataProfile(profile)
    if not profile then return false, "Invalid trade profile" end
    return inTransaction(function()
        if steamid then
            local deleted, deleteError = runQuery("DELETE FROM trade_ledger WHERE steamid = " .. sql.SQLStr(steamid) .. " AND profile = " .. sql.SQLStr(profile))
            if not deleted then return false, deleteError end
        end
        if includeStock then
            local deleted, deleteError = runQuery("DELETE FROM trade_stock WHERE profile = " .. sql.SQLStr(profile))
            if not deleted then return false, deleteError end
        end
        return true
    end)
end

local commitWriters = {
    // Sells step.units from a shared den stock row. The row is created at step.stock on the first sale of the day,
    // and the update only applies while `sold` still equals step.expected and stays within the stock, so a stale
    // view or a race with another buyer fails the whole transaction.
    tradeStock = function(profile, step)
        local stock, expected, units = tonumber(step.stock), tonumber(step.expected), tonumber(step.units)
        if not stock or not expected or not units or units < 1 or units ~= math.floor(units) then return false, "invalid stock change" end
        for _, key in ipairs({ "safeZoneId", "traderId", "day", "offerKey" }) do
            if type(step[key]) ~= "string" or step[key] == "" then return false, "a stock change needs " .. key end
        end
        local where = " WHERE profile = " .. sql.SQLStr(profile) .. " AND safeZoneId = " .. sql.SQLStr(step.safeZoneId) .. " AND traderId = " .. sql.SQLStr(step.traderId)
            .. " AND day = " .. sql.SQLStr(step.day) .. " AND offerKey = " .. sql.SQLStr(step.offerKey)
        local created, createError = runQuery("INSERT OR IGNORE INTO trade_stock (profile, safeZoneId, traderId, day, offerKey, stock, sold) VALUES (" .. sql.SQLStr(profile) .. ", "
            .. sql.SQLStr(step.safeZoneId) .. ", " .. sql.SQLStr(step.traderId) .. ", " .. sql.SQLStr(step.day) .. ", " .. sql.SQLStr(step.offerKey) .. ", " .. math.floor(stock) .. ", 0)")
        if not created then return false, createError end
        local updated, updateError = runQuery("UPDATE trade_stock SET sold = " .. math.floor(expected + units) .. where .. " AND sold = " .. math.floor(expected) .. " AND " .. math.floor(expected + units) .. " <= stock")
        if not updated then return false, updateError end
        if tonumber(sql.QueryValue("SELECT changes()")) ~= 1 then return false, "the trader's stock changed; refresh and try again" end
        return true
    end,
    // Records one trade. requestId is unique per player and profile, so a replayed request fails its transaction.
    // A sale with step.saleLimit also fails when the player's cash from sales today would exceed that limit.
    tradeLedger = function(profile, step)
        if type(step.requestId) ~= "string" or step.requestId == "" then return false, "a trade needs a request id" end
        if step.tradeKind ~= "buy" and step.tradeKind ~= "sell" then return false, "a trade is a buy or a sell" end
        local owner = " WHERE steamid = " .. sql.SQLStr(step.steamid) .. " AND profile = " .. sql.SQLStr(profile)
        if step.saleLimit then
            local total = tonumber(sql.QueryValue("SELECT COALESCE(SUM(cash), 0) FROM trade_ledger" .. owner .. " AND kind = 'sell' AND day = " .. sql.SQLStr(step.day))) or 0
            if total + integerValue(step.cash) > step.saleLimit then return false, "the daily sale limit would be exceeded" end
        end
        return runQuery("INSERT INTO trade_ledger (steamid, profile, requestId, safeZoneId, traderId, day, kind, itemId, count, cash, credits, createdAt) VALUES ("
            .. sql.SQLStr(step.steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. sql.SQLStr(step.requestId) .. ", " .. sql.SQLStr(step.safeZoneId or "") .. ", "
            .. sql.SQLStr(step.traderId or "") .. ", " .. sql.SQLStr(step.day or "") .. ", " .. sql.SQLStr(step.tradeKind) .. ", " .. sql.SQLStr(step.itemId or "") .. ", "
            .. integerValue(step.count) .. ", " .. integerValue(step.cash) .. ", " .. integerValue(step.credits) .. ", " .. os.time() .. ")")
    end,
    playerItems = function(profile, step)
        return writePlayerItemRows(step.steamid, profile, step.rows)
    end,
    denStash = function(profile, step)
        if type(step.safeZoneId) ~= "string" or step.safeZoneId == "" then return false, "Invalid den-stash identity" end
        return writeDenStashRows(step.steamid, profile, step.safeZoneId, step.rows)
    end,
    // Sets a player's cash; the player row must already exist.
    cash = function(profile, step)
        local cash = tonumber(step.cash)
        if not cash or cash < 0 or cash ~= math.floor(cash) then return false, "cash must be a whole number of at least 0" end
        local updated, updateError = runQuery("UPDATE player_data SET Cash = " .. cash .. ", Revision = Revision + 1, UpdatedAt = " .. os.time() .. " WHERE steamid = " .. sql.SQLStr(step.steamid) .. " AND profile = " .. sql.SQLStr(profile))
        if not updated then return false, updateError end
        local changes = sql.QueryValue("SELECT changes()")
        if tonumber(changes) ~= 1 then return false, "no player record to update cash for " .. tostring(step.steamid) end
        return true
    end,
    professionClaim = function(profile, step)
        return runQuery("INSERT INTO profession_claims (steamid, profile, day, job, claimedAt, items) VALUES (" .. sql.SQLStr(step.steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. sql.SQLStr(step.day) .. ", " .. sql.SQLStr(step.job) .. ", " .. integerValue(step.claimedAt) .. ", " .. sql.SQLStr(util.TableToJSON(step.items or {}, false) or "[]") .. ")")
    end,
    // Replaces every installed implant for the player.
    playerImplants = function(profile, step)
        return writeImplantRows(step.steamid, profile, step.rows)
    end,
    // Moves a credit balance from step.expected to step.balance and records it in the ledger. The update only applies
    // while the stored balance still equals step.expected, so a stale or concurrent change fails the transaction.
    credits = function(profile, step)
        local expected, balance = tonumber(step.expected), tonumber(step.balance)
        local maximum = ZM_StaticData and ZM_StaticData.MaximumCredits or 1000000
        if not expected or not balance or balance ~= math.floor(balance) or balance < 0 or balance > maximum then
            return false, "credits must be a whole number from 0 to " .. maximum
        end
        if type(step.reason) ~= "string" or step.reason == "" or #step.reason > 64 then return false, "a credit change needs a reason" end
        local owner = sql.SQLStr(step.steamid) .. ", " .. sql.SQLStr(profile)
        local now = os.time()
        local created, createError = runQuery("INSERT OR IGNORE INTO player_credits (steamid, profile, credits, updatedAt) VALUES (" .. owner .. ", 0, " .. now .. ")")
        if not created then return false, createError end
        local updated, updateError = runQuery("UPDATE player_credits SET credits = " .. balance .. ", updatedAt = " .. now .. " WHERE steamid = " .. sql.SQLStr(step.steamid) .. " AND profile = " .. sql.SQLStr(profile) .. " AND credits = " .. math.floor(expected))
        if not updated then return false, updateError end
        if tonumber(sql.QueryValue("SELECT changes()")) ~= 1 then return false, "the stored credit balance changed; try again" end
        return runQuery("INSERT INTO credit_ledger (steamid, profile, delta, balance, reason, ref, createdAt) VALUES (" .. owner .. ", " .. (balance - math.floor(expected)) .. ", " .. balance .. ", " .. sql.SQLStr(step.reason) .. ", " .. (step.ref and sql.SQLStr(tostring(step.ref)) or "NULL") .. ", " .. now .. ")")
    end,
    mastercraftAttempt = function(profile, step)
        local attributes = step.attributes and sql.SQLStr(util.TableToJSON(step.attributes, false) or "{}") or "NULL"
        return runQuery("INSERT INTO mastercraft_attempts (steamid, profile, instanceId, itemId, level, credits, ultra, attributes, attemptedAt) VALUES (" .. sql.SQLStr(step.steamid) .. ", " .. sql.SQLStr(profile) .. ", " .. sql.SQLStr(step.instanceId) .. ", " .. sql.SQLStr(step.itemId) .. ", " .. integerValue(step.level, 1) .. ", " .. integerValue(step.credits) .. ", " .. (step.ultra and 1 or 0) .. ", " .. attributes .. ", " .. integerValue(step.attemptedAt) .. ")")
    end,
    // Sets a player's stored job; the player row must already exist.
    job = function(profile, step)
        local job = ZM_NormalizeJob(step.job)
        if job ~= step.job then return false, "invalid job '" .. tostring(step.job) .. "'" end
        local updated, updateError = runQuery("UPDATE player_data SET Job = " .. sql.SQLStr(job) .. ", Revision = Revision + 1, UpdatedAt = " .. os.time() .. " WHERE steamid = " .. sql.SQLStr(step.steamid) .. " AND profile = " .. sql.SQLStr(profile))
        if not updated then return false, updateError end
        if tonumber(sql.QueryValue("SELECT changes()")) ~= 1 then return false, "no player record to update the job for " .. tostring(step.steamid) end
        return true
    end
}

// Writes a list of persistence steps for one profile in a single transaction: every step lands or none do.
// Steps: { kind = "playerItems"|"denStash"|"cash"|"professionClaim"|"playerImplants"|"credits"|"mastercraftAttempt"|"job"|"tradeStock"|"tradeLedger", steamid = ..., ... }.
function ZM_CommitWrites(profile, steps)
    profile = getPlayerDataProfile(profile)
    if not profile then return false, "Invalid commit profile" end
    for index, step in ipairs(steps or {}) do
        if type(step) ~= "table" then return false, "write step " .. index .. " must be a table" end
        if step.kind ~= "tradeStock" and (type(step.steamid) ~= "string" or step.steamid == "") then
            return false, "write step " .. index .. " has no character persistence key"
        end
    end
    return inTransaction(function()
        for index, step in ipairs(steps or {}) do
            local writer = commitWriters[step.kind]
            if not writer then return false, "unknown write step '" .. tostring(step.kind) .. "'" end
            local ok, writeError = writer(profile, step)
            if not ok then return false, "step " .. index .. " (" .. step.kind .. "): " .. tostring(writeError) end
        end
        return true
    end)
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

// Harvest cooldowns are shared per world profile and logical cell, and survive server restarts.
function ZM_CreateFoliageTables()
    return runQuery("CREATE TABLE IF NOT EXISTS foliage_harvests (profile TEXT NOT NULL, cellId INTEGER NOT NULL, nodeKey TEXT NOT NULL, availableAt INTEGER NOT NULL, PRIMARY KEY (profile, cellId, nodeKey))")
end

function ZM_GetFoliageHarvests(profile, cellId)
    profile = getPlayerDataProfile(profile)
    if not profile then
        return nil, "Invalid foliage profile"
    end
    local result = sql.Query("SELECT nodeKey, availableAt FROM foliage_harvests WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. integerValue(cellId) .. " ORDER BY nodeKey")
    if result == false then
        return nil, sql.LastError() or "Could not read foliage harvests"
    end
    return result or {}
end

function ZM_SetFoliageHarvest(profile, cellId, nodeKey, availableAt)
    profile = getPlayerDataProfile(profile)
    if not profile or type(nodeKey) ~= "string" or nodeKey == "" then
        return false, "Invalid foliage harvest identity"
    end
    return runQuery("INSERT OR REPLACE INTO foliage_harvests (profile, cellId, nodeKey, availableAt) VALUES (" .. sql.SQLStr(profile) .. ", " .. integerValue(cellId) .. ", " .. sql.SQLStr(nodeKey) .. ", " .. integerValue(availableAt) .. ")")
end

function ZM_DeleteFoliageHarvest(profile, cellId, nodeKey)
    profile = getPlayerDataProfile(profile)
    if not profile or type(nodeKey) ~= "string" or nodeKey == "" then
        return false, "Invalid foliage harvest identity"
    end
    return runQuery("DELETE FROM foliage_harvests WHERE profile = " .. sql.SQLStr(profile) .. " AND cellId = " .. integerValue(cellId) .. " AND nodeKey = " .. sql.SQLStr(nodeKey))
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