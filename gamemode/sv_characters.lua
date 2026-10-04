// Server-owned character slots and the one-time migration from player ownership to character ownership.
ZM_CharacterService = ZM_CharacterService or {}
local Characters = ZM_CharacterService
local ply = FindMetaTable("Player")

Characters.MaximumSlots = 3
Characters.SchemaVersion = 1
Characters.NonPlayerOwnerKeys = { BOT = true, NULL = true }

// Bots, unauthenticated players, and zn_test_* fixtures (STEAM_TEST:*) have no Steam identity to own a character.
function Characters.IsNonPlayerOwnerKey(steamId)
    return type(steamId) == "string" and (Characters.NonPlayerOwnerKeys[steamId] == true or string.sub(steamId, 1, 11) == "STEAM_TEST:")
end
Characters.StorageTables = {
    "player_attributes",
    "player_data",
    "player_items",
    "den_stash_items",
    "equipped_weapon_slots",
    "profession_claims",
    "player_implants",
    "player_credits",
    "credit_ledger",
    "mastercraft_attempts",
    "trade_ledger",
    "bank_ledger"
}

local characterSchema = "CREATE TABLE IF NOT EXISTS characters (steamid TEXT NOT NULL, profile TEXT NOT NULL, slot INTEGER NOT NULL, characterId TEXT NOT NULL UNIQUE, name TEXT NOT NULL, model TEXT, skin INTEGER, bodygroups TEXT, playerColour TEXT, job TEXT NOT NULL DEFAULT 'Civilian', originCellX INTEGER, originCellY INTEGER, originLatitude REAL, originLongitude REAL, createdAt INTEGER NOT NULL, lastPlayedAt INTEGER NOT NULL DEFAULT 0, appearanceRequired INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (steamid, profile, slot))"
local activeSchema = "CREATE TABLE IF NOT EXISTS active_characters (steamid TEXT NOT NULL, profile TEXT NOT NULL, slot INTEGER NOT NULL, selectedAt INTEGER NOT NULL, PRIMARY KEY (steamid, profile))"
local bioSchema = "CREATE TABLE IF NOT EXISTS character_bios (characterId TEXT PRIMARY KEY, bio TEXT NOT NULL, updatedAt INTEGER NOT NULL)"

local function runQuery(query)
    local result = sql.Query(query)
    if result == false then
        return false, sql.LastError() or "SQLite query failed"
    end
    return true, result
end

local function normalizeProfile(profile)
    profile = type(profile) == "string" and string.lower(profile) or nil
    if not profile or not string.match(profile, "^[a-z0-9_-]+$") then return nil end
    return profile
end

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validSlot(slot)
    return isFiniteNumber(slot) and slot == math.floor(slot) and slot >= 1 and slot <= Characters.MaximumSlots
end

Characters.ValidateSlot = validSlot

local function validSteamId(steamId)
    return type(steamId) == "string" and string.match(steamId, "^STEAM_[0-5]:[01]:%d+$") ~= nil
end

local function legacyCharacterId(steamId, profile)
    return steamId .. "|character|" .. profile .. "|1"
end

local function newCharacterId(steamId, profile, slot)
    local seed = table.concat({ steamId, profile, slot, os.time(), SysTime(), math.random(1, 2147483647) }, "|")
    return "character:" .. util.CRC(seed) .. ":" .. tostring(math.floor(SysTime() * 1000000))
end

local function createSchemas()
    for _, schema in ipairs({ characterSchema, activeSchema, bioSchema,
        "CREATE TABLE IF NOT EXISTS zm_schema_version (version INTEGER PRIMARY KEY, appliedAt INTEGER NOT NULL)" }) do
        local created, createError = runQuery(schema)
        if not created then return false, createError end
    end
    return true
end

// Garry's Mod blocks Lua file access to sv.db, so the pre-migration backup is a logical
// SQLite export: every schema statement plus every row, verified by per-table row counts.
local backupPath = "zombiesim/backups/sv_db_alpha_2_8_5_backup.json"

local function readBackupCounts(data)
    local counts = {}
    for _, tableData in ipairs(data.tables or {}) do
        counts[tableData.name] = tonumber(tableData.rowCount)
    end
    return counts
end

local function createDatabaseBackup()
    if file.Exists(backupPath, "DATA") then
        local existing = util.JSONToTable(file.Read(backupPath, "DATA") or "")
        if istable(existing) and istable(existing.tables) and existing.complete == true then return true end
        return false, "Existing character-migration backup is incomplete or unreadable: data/" .. backupPath
    end
    local schema = sql.Query("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name")
    if schema == false then return false, sql.LastError() or "Could not read the database schema for backup" end
    local backup = { format = "zombiesim-sqlite-logical-backup", version = 1, createdAt = os.time(), schema = {}, tables = {}, complete = true }
    for _, entry in ipairs(schema or {}) do
        table.insert(backup.schema, { type = entry.type, name = entry.name, sql = entry.sql })
        if entry.type == "table" then
            local quoted = sql.SQLStr(entry.name)
            local columns = sql.Query("PRAGMA table_info(" .. quoted .. ")")
            if columns == false then return false, sql.LastError() or ("Could not read columns for " .. entry.name) end
            local rows = sql.Query("SELECT * FROM " .. quoted)
            if rows == false then return false, sql.LastError() or ("Could not read rows for " .. entry.name) end
            local columnNames = {}
            for _, column in ipairs(columns or {}) do table.insert(columnNames, column.name) end
            local encodedRows = {}
            for _, row in ipairs(rows or {}) do
                local values = {}
                for index, columnName in ipairs(columnNames) do
                    local value = row[columnName]
                    values[index] = value == nil and { null = true } or { v = tostring(value) }
                end
                table.insert(encodedRows, values)
            end
            table.insert(backup.tables, { name = entry.name, columns = columnNames, rowCount = #encodedRows, rows = encodedRows })
        end
    end
    local encoded = util.TableToJSON(backup)
    if not encoded then return false, "Could not encode the character-migration backup" end
    file.CreateDir("zombiesim")
    file.CreateDir("zombiesim/backups")
    file.Write(backupPath, encoded)
    local verify = util.JSONToTable(file.Read(backupPath, "DATA") or "")
    if not istable(verify) or verify.complete ~= true then
        return false, "Could not verify the character-migration backup: data/" .. backupPath
    end
    local expected = readBackupCounts(backup)
    local actual = readBackupCounts(verify)
    for name, count in pairs(expected) do
        if actual[name] ~= count then
            file.Delete(backupPath)
            return false, "Character-migration backup row count mismatch for " .. name
        end
    end
    print(string.format("[ZombieSim] Pre-migration backup written to data/%s (%d tables).", backupPath, #backup.tables))
    return true
end
function Characters:BackupBeforeMigration()
    if sql.TableExists("zm_schema_version") then
        local currentVersion = tonumber(sql.QueryValue("SELECT MAX(version) FROM zm_schema_version")) or 0
        if currentVersion >= self.SchemaVersion then
            self.BackupReady = true
            return true
        end
    end
    local backedUp, backupError = createDatabaseBackup()
    if not backedUp then return false, backupError end
    self.BackupReady = true
    return true
end

local function readOwners()
    local owners = {}
    for _, tableName in ipairs(Characters.StorageTables) do
        if sql.TableExists(tableName) then
            local result = sql.Query("SELECT DISTINCT steamid, profile FROM " .. tableName)
            if result == false then
                return nil, sql.LastError() or ("Could not inspect " .. tableName)
            end
            for _, row in ipairs(result or {}) do
                local profile = normalizeProfile(row.profile)
                if Characters.IsNonPlayerOwnerKey(row.steamid) then
                    // Leave non-player rows untouched; they are never re-keyed to a character.
                    print("[ZombieSim] Character migration skipped non-player owner key " .. tostring(row.steamid) .. " in " .. tableName)
                elseif not validSteamId(row.steamid) then
                    return nil, "Cannot migrate an unrecognized owner key in " .. tableName .. ": " .. tostring(row.steamid)
                elseif not profile or row.profile ~= profile then
                    return nil, "Cannot migrate a non-canonical profile in " .. tableName .. ": " .. tostring(row.profile)
                else
                    owners[row.steamid .. "\n" .. profile] = { steamid = row.steamid, profile = profile }
                end
            end
        end
    end
    return owners
end

local function insertLegacyCharacter(owner)
    local steamSql = sql.SQLStr(owner.steamid)
    local profileSql = sql.SQLStr(owner.profile)
    local playerData = sql.Query("SELECT CellX, CellY, Job FROM player_data WHERE steamid = " .. steamSql .. " AND profile = " .. profileSql)
    if playerData == false then return false, sql.LastError() or "Could not read legacy player data" end
    local data = playerData and playerData[1] or {}
    local characterId = legacyCharacterId(owner.steamid, owner.profile)
    local now = os.time()
    local fileBio = nil
    local steamId64 = util.SteamIDTo64 and util.SteamIDTo64(owner.steamid) or nil
    if steamId64 and steamId64 ~= "" then
        fileBio = file.Read("zombiesim/player_bios/" .. steamId64 .. ".txt", "DATA")
    end
    local created, createError = runQuery("INSERT OR IGNORE INTO characters (steamid, profile, slot, characterId, name, job, originCellX, originCellY, createdAt, lastPlayedAt, appearanceRequired) VALUES ("
        .. steamSql .. ", " .. profileSql .. ", 1, " .. sql.SQLStr(characterId) .. ", 'Survivor', "
        .. sql.SQLStr(type(data.Job) == "string" and data.Job ~= "" and data.Job or "Civilian") .. ", "
        .. (tonumber(data.CellX) and tostring(math.floor(tonumber(data.CellX))) or "NULL") .. ", "
        .. (tonumber(data.CellY) and tostring(math.floor(tonumber(data.CellY))) or "NULL") .. ", "
        .. now .. ", " .. now .. ", 1)")
    if not created then return false, createError end
    local active, activeError = runQuery("INSERT OR IGNORE INTO active_characters (steamid, profile, slot, selectedAt) VALUES ("
        .. steamSql .. ", " .. profileSql .. ", 1, " .. now .. ")")
    if not active then return false, activeError end
    if fileBio and fileBio ~= "" then
        local bioSaved, bioError = runQuery("INSERT OR IGNORE INTO character_bios (characterId, bio, updatedAt) VALUES ("
            .. sql.SQLStr(characterId) .. ", " .. sql.SQLStr(fileBio) .. ", " .. now .. ")")
        if not bioSaved then return false, bioError end
    end
    return true
end

local function rekeyLegacyOwners(owners)
    for _, owner in pairs(owners) do
        local inserted, insertError = insertLegacyCharacter(owner)
        if not inserted then return nil, insertError end
    end

    local migratedCounts = {}
    for _, tableName in ipairs(Characters.StorageTables) do
        if sql.TableExists(tableName) then
            local changed, changeError = runQuery("UPDATE " .. tableName .. " SET steamid = ("
                .. "SELECT characterId FROM characters WHERE characters.steamid = " .. tableName .. ".steamid"
                .. " AND characters.profile = " .. tableName .. ".profile AND characters.slot = 1)"
                .. " WHERE EXISTS (SELECT 1 FROM characters WHERE characters.steamid = " .. tableName .. ".steamid"
                .. " AND characters.profile = " .. tableName .. ".profile AND characters.slot = 1)"
                .. " AND steamid NOT LIKE 'character:%' AND steamid NOT LIKE '%|character|%'")
            if not changed then return nil, changeError end
            migratedCounts[tableName] = tonumber(sql.QueryValue("SELECT changes()")) or 0
        end
    end
    return migratedCounts
end

Characters.RekeyLegacyOwners = rekeyLegacyOwners

// Back up the live database first, then atomically create slot-1 records and re-key every player-owned table.
function Characters:Migrate()
    local currentVersion = 0
    if sql.TableExists("zm_schema_version") then
        currentVersion = tonumber(sql.QueryValue("SELECT MAX(version) FROM zm_schema_version")) or 0
    end
    if currentVersion >= self.SchemaVersion then return createSchemas() end

    if not self.BackupReady then
        local backupReady, backupError = self:BackupBeforeMigration()
        if not backupReady then return false, backupError end
    end

    local started, startError = runQuery("BEGIN")
    if not started then return false, startError end
    local function rollback(message)
        sql.Query("ROLLBACK")
        return false, message
    end

    local schemasReady, schemaError = createSchemas()
    if not schemasReady then return rollback(schemaError) end
    local owners, ownersError = readOwners()
    if not owners then return rollback(ownersError) end
    local migratedCounts, migrationError = rekeyLegacyOwners(owners)
    if not migratedCounts then return rollback(migrationError) end

    local versionSaved, versionError = runQuery("INSERT INTO zm_schema_version (version, appliedAt) VALUES ("
        .. self.SchemaVersion .. ", " .. os.time() .. ")")
    if not versionSaved then return rollback(versionError) end
    local committed, commitError = runQuery("COMMIT")
    if not committed then
        sql.Query("ROLLBACK")
        return false, commitError
    end

    for tableName, count in pairs(migratedCounts) do
        print(string.format("[ZombieSim] Character migration re-keyed %d rows in %s", count, tableName))
    end
    return true
end

local function getCharacter(steamId, profile, slot)
    local result = sql.Query("SELECT * FROM characters WHERE steamid = " .. sql.SQLStr(steamId)
        .. " AND profile = " .. sql.SQLStr(profile) .. " AND slot = " .. slot)
    if result == false then return nil, sql.LastError() or "Could not read character" end
    return result and result[1] or nil
end

local function validateName(name)
    if type(name) ~= "string" then return nil, "Character name must be text" end
    name = string.Trim(name)
    if #name < 2 or #name > 24 or not string.match(name, "^[%w][%w _'-]*$") then
        return nil, "Character name must be 2-24 letters, numbers, spaces, apostrophes, underscores, or hyphens"
    end
    return name
end

Characters.ValidateName = validateName

function Characters:EnsureLegacyDisplayName(target, character)
    if character.name ~= "Survivor" or not string.find(character.characterId, "|character|", 1, true) then return true end
    local name = string.Trim(target:Nick() or "")
    name = string.gsub(name, "[^%w _'-]", "")
    name = string.gsub(name, "%s+", " ")
    name = string.Trim(string.sub(name, 1, 24))
    if #name < 2 then name = "Survivor" end
    if name == character.name then return true end
    local updated, updateError = runQuery("UPDATE characters SET name = " .. sql.SQLStr(name)
        .. " WHERE characterId = " .. sql.SQLStr(character.characterId) .. " AND name = 'Survivor'")
    if not updated then return false, updateError end
    character.name = name
    return true
end

local function validOwner(target)
    if not IsValid(target) or not target:IsPlayer() or target:IsBot() then return nil, nil, "A valid human player is required" end
    local steamId = target:SteamID()
    local profile = normalizeProfile(ZM_Util.ProfileFor(target))
    if not validSteamId(steamId) or not profile then return nil, nil, "Invalid character owner or profile" end
    return steamId, profile
end

local function allowRequest(target, action)
    target.ZM_CharacterRequestAt = target.ZM_CharacterRequestAt or {}
    local now = SysTime()
    if now < (target.ZM_CharacterRequestAt[action] or 0) then
        return false, "Character requests are rate-limited; try again shortly"
    end
    target.ZM_CharacterRequestAt[action] = now + 0.25
    return true
end

function Characters:Create(target, slot, details)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return false, ownerError end
    if game.GetMap() ~= "zn_city_start" and game.GetMap() ~= "zn_preview_start" then return false, "Characters can only be created in the launcher" end
    local rateAllowed, rateError = allowRequest(target, "create")
    if not rateAllowed then return false, rateError end
    if not validSlot(slot) then return false, "Character slot must be an integer from 1 to 3" end
    if type(details) ~= "table" then return false, "Character details must be a table" end
    for key in pairs(details) do
        if key ~= "name" and key ~= "job" and key ~= "appearance" and key ~= "attributes" then
            return false, "Unsupported character field: " .. tostring(key)
        end
    end
    local name, nameError = validateName(details.name)
    if not name then return false, nameError end
    local job = details.job
    if type(job) ~= "string" or #job > 32 or not string.match(job, "^%a+$") then return false, "Invalid profession name" end
    if ZM_Professions and not ZM_Professions:Get(job) then return false, "Unknown profession" end
    local appearance, appearanceError = self.ValidateAppearance(details.appearance)
    if not appearance then return false, appearanceError end
    local attributes, pointsError = self.ValidateStartingAttributes(details.attributes)
    if not attributes then return false, pointsError end

    local duplicate = sql.Query("SELECT slot FROM characters WHERE steamid = " .. sql.SQLStr(steamId)
        .. " AND profile = " .. sql.SQLStr(profile) .. " AND lower(name) = lower(" .. sql.SQLStr(name) .. ")")
    if duplicate == false then return false, sql.LastError() or "Could not check character names" end
    if duplicate and #duplicate > 0 then return false, "Character name is already in use" end
    local existing, existingError = getCharacter(steamId, profile, slot)
    if existingError then return false, existingError end
    if existing then return false, "That character slot is already occupied" end

    local characterId = newCharacterId(steamId, profile, slot)
    local now = os.time()
    local worldData = ZM_World:GetData() or {}
    local origin = worldData.world and worldData.world.origin or {}
    local originX = tonumber(origin[1])
    local originY = tonumber(origin[2])
    if not originX or not originY then return false, "World origin is unavailable" end
    local latitude, longitude = ZM_LauncherScene:GetOrigin(profile, originX, originY)
    if not latitude or not longitude then return false, "Launcher geographic anchor is unavailable" end
    local safeZone = ZM_World:GetOriginSafeZone()
    if not safeZone then return false, "Origin safe zone is unavailable" end
    local started, startError = runQuery("BEGIN")
    if not started then return false, startError end
    local function rollback(message)
        sql.Query("ROLLBACK")
        return false, message
    end
    local bodygroups = util.TableToJSON(appearance.bodygroups, false)
    local colour = util.TableToJSON(appearance.playerColour, false)
    if not bodygroups or not colour then return rollback("Could not encode appearance") end
    local created, createError = runQuery("INSERT INTO characters (steamid, profile, slot, characterId, name, model, skin, bodygroups, playerColour, job, originCellX, originCellY, originLatitude, originLongitude, createdAt, lastPlayedAt, appearanceRequired) VALUES ("
        .. sql.SQLStr(steamId) .. ", " .. sql.SQLStr(profile) .. ", " .. slot .. ", " .. sql.SQLStr(characterId) .. ", "
        .. sql.SQLStr(name) .. ", " .. sql.SQLStr(appearance.model) .. ", " .. appearance.skin .. ", "
        .. sql.SQLStr(bodygroups) .. ", " .. sql.SQLStr(colour) .. ", " .. sql.SQLStr(job) .. ", "
        .. (originX and tostring(math.floor(originX)) or "NULL") .. ", "
        .. (originY and tostring(math.floor(originY)) or "NULL") .. ", "
        .. (latitude and tostring(latitude) or "NULL") .. ", "
        .. (longitude and tostring(longitude) or "NULL") .. ", " .. now .. ", 0, 0)")
    if not created then return rollback(createError) end
    local saved, saveError = ZM_SetPlayerAttributes(characterId, profile, attributes)
    if not saved then return rollback(saveError) end
    local dataSaved, dataError = ZM_SetPlayerData(characterId, profile, {
        XP = 0, Level = 1, MaxLevel = 300, Difficulty = 1, CellX = originX, CellY = originY,
        CurrentSafeZoneId = safeZone.id, SkillPoints = 0, Cash = 0, Health = 100,
        Stamina = 100, Hunger = 100, Thirst = 100, Job = job
    }, "character creation")
    if not dataSaved then return rollback(dataError) end
    local committed, commitError = runQuery("COMMIT")
    if not committed then return rollback(commitError) end
    return true, characterId
end

function Characters:Select(target, slot)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return false, ownerError end
    if game.GetMap() ~= "zn_city_start" and game.GetMap() ~= "zn_preview_start" then return false, "Characters can only be selected in the launcher" end
    local rateAllowed, rateError = allowRequest(target, "select")
    if not rateAllowed then return false, rateError end
    if not validSlot(slot) then return false, "Character slot must be an integer from 1 to 3" end
    local character, readError = getCharacter(steamId, profile, slot)
    if readError then return false, readError end
    if not character then return false, "That character slot is empty" end
    if target.ZM_PersistentStateLoaded == true and target.ZM_CharacterId ~= character.characterId then
        return false, "Cannot switch characters while gameplay state is loaded"
    end
    local now = os.time()
    local started, startError = runQuery("BEGIN")
    if not started then return false, startError end
    local updated, updateError = runQuery("INSERT OR REPLACE INTO active_characters (steamid, profile, slot, selectedAt) VALUES ("
        .. sql.SQLStr(steamId) .. ", " .. sql.SQLStr(profile) .. ", " .. slot .. ", " .. now .. ")")
    if not updated then
        sql.Query("ROLLBACK")
        return false, updateError
    end
    local played, playedError = runQuery("UPDATE characters SET lastPlayedAt = " .. now .. " WHERE steamid = "
        .. sql.SQLStr(steamId) .. " AND profile = " .. sql.SQLStr(profile) .. " AND slot = " .. slot)
    if not played then
        sql.Query("ROLLBACK")
        return false, playedError
    end
    local committed, commitError = runQuery("COMMIT")
    if not committed then
        sql.Query("ROLLBACK")
        return false, commitError
    end
    target.ZM_CharacterKeyCache = nil
    target.ZM_CharacterId = character.characterId
    target.ZM_CharacterSlot = slot
    return true, character.characterId
end

local modelAllowlist = {}
for _, model in ipairs(ZM_CharacterRules.Models) do modelAllowlist[model] = true end

function Characters.ValidateStartingAttributes(values)
    if type(values) ~= "table" then return nil, "Starting attributes must be a table" end
    local allowed = {}
    for _, name in ipairs(ZM_CharacterRules.Attributes) do allowed[name] = true end
    local total = 0
    local normalized = {}
    for name, value in pairs(values) do
        if not allowed[name] or not isFiniteNumber(value) or value ~= math.floor(value)
            or value < 0 or value > ZM_CharacterRules.MaximumAttribute then
            return nil, "Invalid starting attribute"
        end
        normalized[name] = value
        total = total + value
    end
    if total ~= ZM_CharacterRules.StartingPoints then return nil, "Spend exactly 10 starting points" end
    for _, name in ipairs(ZM_CharacterRules.Attributes) do normalized[name] = normalized[name] or 0 end
    return normalized
end

local function validateAppearance(appearance)
    if type(appearance) ~= "table" then return nil, "Appearance must be a table" end
    for key in pairs(appearance) do
        if key ~= "model" and key ~= "skin" and key ~= "bodygroups" and key ~= "playerColour" then
            return nil, "Unsupported appearance field: " .. tostring(key)
        end
    end
    if type(appearance.model) ~= "string" or not modelAllowlist[appearance.model]
        or not util.IsValidModel(appearance.model) then return nil, "Model is not allowlisted or unavailable" end
    if not isFiniteNumber(appearance.skin) or appearance.skin ~= math.floor(appearance.skin) or appearance.skin < 0 or appearance.skin > 31 then
        return nil, "Skin must be an integer from 0 to 31"
    end
    local bodygroups = appearance.bodygroups or {}
    if type(bodygroups) ~= "table" then return nil, "Bodygroups must be a table" end
    local normalizedBodygroups = {}
    for key, value in pairs(bodygroups) do
        local index = tonumber(key)
        if not isFiniteNumber(index) or index ~= math.floor(index) or index < 0 or index > 31
            or not isFiniteNumber(value) or value ~= math.floor(value) or value < 0 or value > 31 then
            return nil, "Bodygroups must map indices and values from 0 to 31"
        end
        normalizedBodygroups[tostring(index)] = value
    end
    local modelEntity = ents.Create("prop_dynamic")
    if not IsValid(modelEntity) then return nil, "Could not inspect appearance model" end
    modelEntity:SetModel(appearance.model)
    local skinCount = modelEntity:SkinCount()
    local modelGroups = modelEntity:GetBodyGroups() or {}
    modelEntity:Remove()
    if appearance.skin >= math.max(1, skinCount) then return nil, "Skin does not exist for model" end
    for index, value in pairs(normalizedBodygroups) do
        local found = false
        for _, group in ipairs(modelGroups) do
            if group.id == tonumber(index) and value < group.num then found = true end
        end
        if not found then return nil, "Bodygroup does not exist for model" end
    end
    local colour = appearance.playerColour or { 1, 1, 1 }
    if type(colour) ~= "table" then return nil, "Player colour must contain exactly three components" end
    local colourComponents = 0
    for key in pairs(colour) do
        if not isFiniteNumber(key) or key ~= math.floor(key) or key < 1 or key > 3 then
            return nil, "Player colour must contain exactly three components"
        end
        colourComponents = colourComponents + 1
    end
    if colourComponents ~= 3 then return nil, "Player colour must contain exactly three components" end
    for index = 1, 3 do
        if not isFiniteNumber(colour[index]) or colour[index] < 0 or colour[index] > 1 then
            return nil, "Player colour components must be numbers from 0 to 1"
        end
    end
    return {
        model = appearance.model,
        skin = appearance.skin,
        bodygroups = normalizedBodygroups,
        playerColour = colour
    }
end

Characters.ValidateAppearance = validateAppearance

function Characters:SetAppearance(target, slot, appearance)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return false, ownerError end
    if game.GetMap() ~= "zn_city_start" and game.GetMap() ~= "zn_preview_start" then return false, "Appearance can only be set in the launcher" end
    local rateAllowed, rateError = allowRequest(target, "appearance")
    if not rateAllowed then return false, rateError end
    if not validSlot(slot) then return false, "Character slot must be an integer from 1 to 3" end
    local character, readError = getCharacter(steamId, profile, slot)
    if readError then return false, readError end
    if not character then return false, "That character slot is empty" end
    if target.ZM_PersistentStateLoaded == true and target.ZM_CharacterId == character.characterId then
        return false, "Cannot change appearance while the character is loaded"
    end
    local normalized, appearanceError = validateAppearance(appearance)
    if not normalized then return false, appearanceError end
    local bodygroups = util.TableToJSON(normalized.bodygroups, false)
    local playerColour = util.TableToJSON(normalized.playerColour, false)
    if not bodygroups or not playerColour then return false, "Could not encode character appearance" end
    local updated, updateError = runQuery("UPDATE characters SET model = " .. sql.SQLStr(normalized.model)
        .. ", skin = " .. normalized.skin .. ", bodygroups = " .. sql.SQLStr(bodygroups)
        .. ", playerColour = " .. sql.SQLStr(playerColour) .. ", appearanceRequired = 0 WHERE steamid = "
        .. sql.SQLStr(steamId) .. " AND profile = " .. sql.SQLStr(profile) .. " AND slot = " .. slot)
    if not updated then return false, updateError end
    if (tonumber(sql.QueryValue("SELECT changes()")) or 0) ~= 1 then return false, "That character slot is empty" end
    return true
end

function Characters:DeleteOwnedRows(character)
    if type(character) ~= "table" or type(character.characterId) ~= "string"
        or type(character.steamid) ~= "string" or type(character.profile) ~= "string"
        or not validSlot(tonumber(character.slot)) then
        return false, "Invalid character deletion record"
    end
    local started, startError = runQuery("BEGIN")
    if not started then return false, startError end
    for _, tableName in ipairs(self.StorageTables) do
        local deleted, deleteError = runQuery("DELETE FROM " .. tableName .. " WHERE steamid = "
            .. sql.SQLStr(character.characterId) .. " AND profile = " .. sql.SQLStr(character.profile))
        if not deleted then
            sql.Query("ROLLBACK")
            return false, deleteError
        end
    end
    local bioDeleted, bioError = runQuery("DELETE FROM character_bios WHERE characterId = " .. sql.SQLStr(character.characterId))
    if not bioDeleted then sql.Query("ROLLBACK") return false, bioError end
    local activeDeleted, activeError = runQuery("DELETE FROM active_characters WHERE steamid = " .. sql.SQLStr(character.steamid)
        .. " AND profile = " .. sql.SQLStr(character.profile) .. " AND slot = " .. tonumber(character.slot))
    if not activeDeleted then sql.Query("ROLLBACK") return false, activeError end
    local charDeleted, charError = runQuery("DELETE FROM characters WHERE steamid = " .. sql.SQLStr(character.steamid)
        .. " AND profile = " .. sql.SQLStr(character.profile) .. " AND slot = " .. tonumber(character.slot))
    if not charDeleted then sql.Query("ROLLBACK") return false, charError end
    local committed, commitError = runQuery("COMMIT")
    if not committed then sql.Query("ROLLBACK") return false, commitError end
    return true
end

function Characters:Delete(target, slot, confirmationName)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return false, ownerError end
    local rateAllowed, rateError = allowRequest(target, "delete")
    if not rateAllowed then return false, rateError end
    if not validSlot(slot) then return false, "Character slot must be an integer from 1 to 3" end
    if game.GetMap() ~= "zn_city_start" and game.GetMap() ~= "zn_preview_start" then return false, "Characters can only be deleted from the launcher" end
    local character, readError = getCharacter(steamId, profile, slot)
    if readError then return false, readError end
    if not character then return false, "That character slot is empty" end
    local confirmed, nameError = validateName(confirmationName)
    if not confirmed or confirmed ~= character.name then return false, nameError or "Character name confirmation did not match" end
    if target.ZM_PersistentStateLoaded == true and target.ZM_CharacterId == character.characterId then
        return false, "The currently loaded character cannot be deleted"
    end

    local deleted, deleteError = self:DeleteOwnedRows(character)
    if not deleted then return false, deleteError end
    target.ZM_CharacterKeyCache = nil
    print(string.format("[ZombieSim] Deleted character %s (slot %d, profile %s) for %s", character.characterId, slot, profile, steamId))
    return true
end

function Characters:GetActiveCharacter(target)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return nil, ownerError end
    local result = sql.Query("SELECT c.* FROM active_characters a JOIN characters c ON c.steamid = a.steamid"
        .. " AND c.profile = a.profile AND c.slot = a.slot WHERE a.steamid = " .. sql.SQLStr(steamId)
        .. " AND a.profile = " .. sql.SQLStr(profile))
    if result == false then return nil, sql.LastError() or "Could not read active character" end
    return result and result[1] or nil
end

function Characters:GetOwnedCharacter(target, slot)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return nil, ownerError end
    if not validSlot(slot) then return nil, "Invalid character slot" end
    return getCharacter(steamId, profile, slot)
end

function Characters:ClearActive(target)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return false, ownerError end
    local cleared, clearError = runQuery("DELETE FROM active_characters WHERE steamid = "
        .. sql.SQLStr(steamId) .. " AND profile = " .. sql.SQLStr(profile))
    if cleared then
        target.ZM_CharacterKeyCache = nil
        target.ZM_CharacterId = nil
        target.ZM_CharacterSlot = nil
    end
    return cleared, clearError
end

function Characters:GetCharacterKeyForSteamID(steamId, profile)
    profile = normalizeProfile(profile)
    if not validSteamId(steamId) or not profile then return nil, "Invalid character owner or profile" end
    local result = sql.Query("SELECT c.characterId FROM active_characters a JOIN characters c ON c.steamid = a.steamid"
        .. " AND c.profile = a.profile AND c.slot = a.slot WHERE a.steamid = " .. sql.SQLStr(steamId)
        .. " AND a.profile = " .. sql.SQLStr(profile))
    if result == false then return nil, sql.LastError() or "Could not resolve active character" end
    if not result or not result[1] then return nil, "No active character is selected for profile " .. profile end
    return result[1].characterId
end

function Characters:List(target, internal)
    local steamId, profile, ownerError = validOwner(target)
    if not steamId then return nil, ownerError end
    if not internal then
        local rateAllowed, rateError = allowRequest(target, "list")
        if not rateAllowed then return nil, rateError end
    end
    local result = sql.Query("SELECT c.characterId, c.slot, c.name, c.model, c.skin, c.job, c.originCellX, c.originCellY, c.originLatitude, c.originLongitude, c.createdAt, c.lastPlayedAt, c.appearanceRequired, COALESCE(d.Level, 1) AS level FROM characters c LEFT JOIN player_data d ON d.steamid = c.characterId AND d.profile = c.profile WHERE c.steamid = "
        .. sql.SQLStr(steamId) .. " AND c.profile = " .. sql.SQLStr(profile) .. " ORDER BY c.slot")
    if result == false then return nil, sql.LastError() or "Could not list characters" end
    for _, character in ipairs(result or {}) do
        local named, nameError = self:EnsureLegacyDisplayName(target, character)
        if not named then return nil, nameError end
        character.characterId = nil
    end
    return result or {}
end

function ply:GetCharacterKey()
    if self.ZM_LauncherState and self.ZM_LauncherState ~= "character_selected"
        and self.ZM_LauncherState ~= "deploying" then return nil, "No character loaded in launcher" end
    local profile = normalizeProfile(ZM_Util.ProfileFor(self))
    if not profile or not validSteamId(self:SteamID()) then return nil, "Invalid character owner or profile" end
    if self.ZM_CharacterKeyCache and self.ZM_CharacterKeyProfile == profile then
        return self.ZM_CharacterKeyCache
    end
    local character, characterError = Characters:GetActiveCharacter(self)
    if characterError then return nil, characterError end
    if not character then return nil, "No active character is selected" end
    local nameUpdated, nameError = Characters:EnsureLegacyDisplayName(self, character)
    if not nameUpdated then return nil, "Could not assign the migrated character name: " .. tostring(nameError) end
    self.ZM_CharacterKeyCache = character.characterId
    self.ZM_CharacterKeyProfile = profile
    self.ZM_CharacterId = character.characterId
    self.ZM_CharacterSlot = tonumber(character.slot)
    return character.characterId
end

function Characters:GetBio(characterId)
    local result = sql.Query("SELECT bio FROM character_bios WHERE characterId = " .. sql.SQLStr(characterId))
    if result == false then return nil, sql.LastError() or "Could not read character bio" end
    return result and result[1] and result[1].bio or ""
end

function Characters:SetBio(characterId, bio)
    return runQuery("INSERT OR REPLACE INTO character_bios (characterId, bio, updatedAt) VALUES ("
        .. sql.SQLStr(characterId) .. ", " .. sql.SQLStr(bio) .. ", " .. os.time() .. ")")
end
