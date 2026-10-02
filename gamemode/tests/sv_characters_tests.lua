local Characters = ZM_CharacterService
local Suite = ZM_TestHarness.NewSuite()
local suffix = tostring(tonumber(util.CRC(tostring(os.time()) .. tostring(SysTime()))) or 1)
local profile = "preview"
local rawSteamId = "STEAM_0:1:" .. suffix
local characterOne = "character-test-one-" .. suffix
local characterTwo = "character-test-two-" .. suffix
local legacySteamId = "STEAM_0:1:" .. tostring(tonumber(suffix) + 1)
local legacyCharacterId = legacySteamId .. "|character|" .. profile .. "|1"

Suite:Add("launcher geographic anchors and credits data", function(check)
    local scene = ZM_LauncherScene
    local data = scene:GetData()
    check(data and #data.credits > 0, "maintained credits file is readable")
    local preview = scene:GetAnchor("preview")
    local city = scene:GetAnchor("city")
    check(preview and city and preview.city ~= city.city, "profiles have independent city anchors")
    if preview then
        local lat, lon = scene:GetOrigin("preview")
        check(math.abs(lat - preview.latitude) < 0.00001 and math.abs(lon - preview.longitude) < 0.00001,
            "origin without cell data resolves to the profile anchor")
    end
    check(scene:GetAnchor("missing") == nil, "unknown profiles have no anchor")
end)

local function run(query)
    local result = sql.Query(query)
    if result == false then error(sql.LastError() or "SQLite query failed") end
    return result
end

local function cleanup()
    for _, tableName in ipairs(Characters.StorageTables) do
        run("DELETE FROM " .. tableName .. " WHERE steamid IN ("
            .. sql.SQLStr(characterOne) .. ", " .. sql.SQLStr(characterTwo) .. ", " .. sql.SQLStr(legacyCharacterId) .. ")")
        run("DELETE FROM " .. tableName .. " WHERE steamid = " .. sql.SQLStr(rawSteamId)
            .. " OR steamid = " .. sql.SQLStr(legacySteamId))
    end
    run("DELETE FROM active_characters WHERE steamid = " .. sql.SQLStr(rawSteamId)
        .. " OR steamid = " .. sql.SQLStr(legacySteamId))
    run("DELETE FROM characters WHERE steamid = " .. sql.SQLStr(rawSteamId)
        .. " OR steamid = " .. sql.SQLStr(legacySteamId))
    run("DELETE FROM character_bios WHERE characterId IN ("
        .. sql.SQLStr(characterOne) .. ", " .. sql.SQLStr(characterTwo) .. ", " .. sql.SQLStr(legacyCharacterId) .. ")")
end

local function insertCharacter(steamId, slot, characterId, name)
    run("INSERT INTO characters (steamid, profile, slot, characterId, name, job, createdAt, appearanceRequired) VALUES ("
        .. sql.SQLStr(steamId) .. ", " .. sql.SQLStr(profile) .. ", " .. slot .. ", " .. sql.SQLStr(characterId)
        .. ", " .. sql.SQLStr(name) .. ", 'Civilian', " .. os.time() .. ", 1)")
end

local function insertOwnedRow(tableName, characterId)
    local columns = run("PRAGMA table_info(" .. tableName .. ")") or {}
    local names = {}
    local values = {}
    for _, column in ipairs(columns) do
        local value = nil
        if column.name == "steamid" then
            value = sql.SQLStr(characterId)
        elseif column.name == "profile" then
            value = sql.SQLStr(profile)
        elseif tonumber(column.notnull) == 1 and column.dflt_value == nil and tonumber(column.pk) == 0 then
            local columnType = string.upper(column.type or "")
            if string.find(columnType, "INT", 1, true) or string.find(columnType, "REAL", 1, true)
                or string.find(columnType, "NUM", 1, true) then
                value = "1"
            else
                value = sql.SQLStr(characterId .. "-" .. column.name)
            end
        end
        if value then
            table.insert(names, column.name)
            table.insert(values, value)
        end
    end
    run("INSERT INTO " .. tableName .. " (" .. table.concat(names, ", ") .. ") VALUES ("
        .. table.concat(values, ", ") .. ")")
end

Suite:Add("migration rekeys rows once without losing values", function(check)
    run("BEGIN")
    local ok, err = pcall(function()
        run("INSERT INTO player_data (steamid, profile, XP, Level, CellX, CellY, Cash) VALUES ("
            .. sql.SQLStr(legacySteamId) .. ", " .. sql.SQLStr(profile) .. ", 123, 4, 7, 9, 42)")
        run("INSERT INTO player_items (steamid, profile, instanceId, container, slot, itemId, count, level) VALUES ("
            .. sql.SQLStr(legacySteamId) .. ", " .. sql.SQLStr(profile) .. ", 'migration-item', 'backpack', 1, 'itemBandage', 2, 3)")
        local owner = { steamid = legacySteamId, profile = profile }
        local firstCounts, firstError = Characters.RekeyLegacyOwners({ [legacySteamId .. "\n" .. profile] = owner })
        if not firstCounts then error(firstError) end
        local data = run("SELECT XP, Level, CellX, CellY, Cash FROM player_data WHERE steamid = "
            .. sql.SQLStr(legacyCharacterId) .. " AND profile = " .. sql.SQLStr(profile))
        local items = run("SELECT instanceId, count, level FROM player_items WHERE steamid = "
            .. sql.SQLStr(legacyCharacterId) .. " AND profile = " .. sql.SQLStr(profile))
        check(data and #data == 1 and tonumber(data[1].XP) == 123 and tonumber(data[1].Level) == 4
            and tonumber(data[1].CellX) == 7 and tonumber(data[1].CellY) == 9 and tonumber(data[1].Cash) == 42,
            "migration preserves progression and logical-cell values")
        check(items and #items == 1 and items[1].instanceId == "migration-item"
            and tonumber(items[1].count) == 2 and tonumber(items[1].level) == 3,
            "migration preserves owned item rows")
        local secondCounts, secondError = Characters.RekeyLegacyOwners({ [legacySteamId .. "\n" .. profile] = owner })
        if not secondCounts then error(secondError) end
        local count = tonumber(sql.QueryValue("SELECT COUNT(*) FROM player_data WHERE steamid = "
            .. sql.SQLStr(legacyCharacterId) .. " AND profile = " .. sql.SQLStr(profile))) or 0
        check(count == 1, "re-running the migration does not duplicate character data")
    end)
    run("ROLLBACK")
    check(ok, "migration fixture completed: " .. tostring(err))
end)

Suite:Add("slot storage is isolated", function(check)
    local rowOne = { instanceId = "slot-one-item-" .. suffix, container = "backpack", slot = 1, itemId = "itemBandage", count = 1, level = 1 }
    local rowTwo = { instanceId = "slot-two-item-" .. suffix, container = "backpack", slot = 1, itemId = "itemMedkit", count = 1, level = 1 }
    local savedOne, errorOne = ZM_ReplacePlayerItems(characterOne, profile, { rowOne })
    local savedTwo, errorTwo = ZM_ReplacePlayerItems(characterTwo, profile, { rowTwo })
    check(savedOne and savedTwo, "both test character inventories save: " .. tostring(errorOne or errorTwo))

    local stashOne = { { instanceId = "slot-one-stash-" .. suffix, slot = 1, itemId = "itemBandage", count = 1, level = 1 } }
    local stashTwo = { { instanceId = "slot-two-stash-" .. suffix, slot = 1, itemId = "itemMedkit", count = 1, level = 1 } }
    local savedStashOne = ZM_ReplaceDenStashItems(characterOne, profile, "test-den", stashOne)
    local savedStashTwo = ZM_ReplaceDenStashItems(characterTwo, profile, "test-den", stashTwo)
    check(savedStashOne and savedStashTwo, "both test character stashes save")

    local creditOne = ZM_CommitWrites(profile, { { kind = "credits", steamid = characterOne, expected = 0, balance = 13, reason = "test", attemptedAt = os.time() } })
    local creditTwo = ZM_CommitWrites(profile, { { kind = "credits", steamid = characterTwo, expected = 0, balance = 29, reason = "test", attemptedAt = os.time() } })
    local itemsOne = ZM_GetPlayerItems(characterOne, profile) or {}
    local itemsTwo = ZM_GetPlayerItems(characterTwo, profile) or {}
    local stashRowsOne = ZM_GetDenStashItems(characterOne, profile, "test-den") or {}
    local stashRowsTwo = ZM_GetDenStashItems(characterTwo, profile, "test-den") or {}
    check(creditOne and creditTwo, "both test character credit balances save")
    check(#itemsOne == 1 and itemsOne[1].instanceId == rowOne.instanceId
        and #itemsTwo == 1 and itemsTwo[1].instanceId == rowTwo.instanceId,
        "slot 1 and slot 2 inventories do not overlap")
    check(#stashRowsOne == 1 and stashRowsOne[1].instanceId == stashOne[1].instanceId
        and #stashRowsTwo == 1 and stashRowsTwo[1].instanceId == stashTwo[1].instanceId,
        "slot 1 and slot 2 den stashes do not overlap")
    check(ZM_GetPlayerCredits(characterOne, profile) == 13 and ZM_GetPlayerCredits(characterTwo, profile) == 29,
        "slot 1 and slot 2 credit balances do not overlap")
end)

Suite:Add("slot and name validation reject invalid values", function(check)
    check(Characters.ValidateSlot(1) and Characters.ValidateSlot(3), "slots 1 and 3 are accepted")
    check(not Characters.ValidateSlot(0) and not Characters.ValidateSlot(4)
        and not Characters.ValidateSlot(1.5) and not Characters.ValidateSlot(0 / 0),
        "out-of-range, fractional, and NaN slots are rejected")
    check(Characters.ValidateName("  Rowan Vale  ") == "Rowan Vale", "valid names are trimmed")
    check(not Characters.ValidateName("x") and not Characters.ValidateName("bad/name")
        and not Characters.ValidateName(string.rep("a", 25)), "short, unsafe, and overlong names are rejected")
    check(not Characters.ValidateAppearance({ model = "models/player/unknown.mdl", skin = 0 }),
        "models outside the appearance allowlist are rejected")
end)

Suite:Add("starting allocation and appearance reject forged input", function(check)
    local rules = ZM_CharacterRules
    local valid = { Strength = rules.StartingPoints }
    local accepted = Characters.ValidateStartingAttributes(valid)
    check(accepted and accepted.Strength == 10 and accepted.Agility == 0,
        "exact point pool produces normalized attributes")
    check(not Characters.ValidateStartingAttributes({ Strength = 11 }), "overspent pool is refused")
    check(not Characters.ValidateStartingAttributes({ NotAnAttribute = 10 }), "unknown attribute is refused")
    check(not Characters.ValidateStartingAttributes({ Strength = 9 }), "unspent points are refused")
    check(not Characters.ValidateAppearance({ model = "models/player/not_a_citizen.mdl", skin = 0 }),
        "unknown player model is refused")
    check(not Characters.ValidateName("!invalid!"), "invalid name is refused")
end)

Suite:Add("failed creation writes no character rows", function(check)
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or (game.GetMap() ~= "zn_city_start" and game.GetMap() ~= "zn_preview_start") then
        check(true, "creation request requires a human in the launcher; skipped outside launcher")
        return
    end
    local owner = sql.SQLStr(target:SteamID())
    local currentProfile = ZM_Util.ProfileFor(target)
    local profileName = sql.SQLStr(currentProfile)
    local queryCount = "SELECT COUNT(*) FROM characters WHERE steamid = " .. owner
        .. " AND profile = " .. profileName
    local before = tonumber(sql.QueryValue(queryCount)) or 0
    local payload = { name = "Valid Test", job = "Civilian",
        appearance = { model = ZM_CharacterRules.Models[1], skin = 0, bodygroups = {},
            playerColour = { 1, 1, 1 } }, attributes = { Strength = 10 } }
    local cases = {
        { label = "unknown profession", change = function(p) p.job = "NonexistentProfession" end },
        { label = "unknown model", change = function(p) p.appearance.model = "models/player/forged.mdl" end },
        { label = "invalid name", change = function(p) p.name = "!invalid!" end },
        { label = "overspent points", change = function(p) p.attributes.Strength = 11 end }
    }
    for _, testCase in ipairs(cases) do
        local details = table.Copy(payload)
        testCase.change(details)
        target.ZM_CharacterRequestAt = nil
        local created = Characters:Create(target, 1, details)
        check(not created and (tonumber(sql.QueryValue(queryCount)) or 0) == before,
            testCase.label .. " writes no rows")
    end
    local occupiedSlot = tonumber(sql.QueryValue("SELECT slot FROM characters WHERE steamid = " .. owner
        .. " AND profile = " .. profileName .. " LIMIT 1"))
    if not occupiedSlot then
        run("BEGIN")
        local inserted, insertError = pcall(function()
            run("INSERT INTO characters (steamid, profile, slot, characterId, name, job, createdAt) VALUES ("
                .. owner .. ", " .. profileName .. ", 1, "
                .. sql.SQLStr("test-full-slot-" .. suffix) .. ", 'Occupied', 'Civilian', " .. os.time() .. ")")
        end)
        if inserted then occupiedSlot = 1 end
        check(inserted, "occupied-slot fixture created: " .. tostring(insertError))
    end
    target.ZM_CharacterRequestAt = nil
    local created = Characters:Create(target, occupiedSlot, payload)
    check(not created, "an occupied slot is refused")
    if before == 0 then run("ROLLBACK") end
    check((tonumber(sql.QueryValue(queryCount)) or 0) == before, "full-slot rejection writes no rows")
end)

Suite:Add("three character slots are the maximum", function(check)
    insertCharacter(rawSteamId, 1, characterOne, "Test One")
    insertCharacter(rawSteamId, 2, characterTwo, "Test Two")
    insertCharacter(rawSteamId, 3, legacyCharacterId, "Test Three")
    local rows = run("SELECT slot FROM characters WHERE steamid = " .. sql.SQLStr(rawSteamId)
        .. " AND profile = " .. sql.SQLStr(profile))
    check(rows and #rows == Characters.MaximumSlots, "all three allowed slots can be occupied")
    check(not Characters.ValidateSlot(Characters.MaximumSlots + 1), "a fourth slot is rejected")
    cleanup()
end)

Suite:Add("delete removes only the selected character records", function(check)
    insertCharacter(rawSteamId, 1, characterOne, "Test One")
    insertCharacter(rawSteamId, 2, characterTwo, "Test Two")
    run("INSERT INTO active_characters (steamid, profile, slot, selectedAt) VALUES ("
        .. sql.SQLStr(rawSteamId) .. ", " .. sql.SQLStr(profile) .. ", 1, " .. os.time() .. ")")
    for _, tableName in ipairs(Characters.StorageTables) do
        insertOwnedRow(tableName, characterOne)
        insertOwnedRow(tableName, characterTwo)
    end
    ZM_SetPlayerData(characterOne, profile, { XP = 1, Level = 1, CellX = 0, CellY = 0, Cash = 10 }, "character test")
    ZM_SetPlayerData(characterTwo, profile, { XP = 2, Level = 1, CellX = 0, CellY = 0, Cash = 20 }, "character test")
    Characters:SetBio(characterOne, "delete test bio")
    local deleted, deleteError = Characters:DeleteOwnedRows({
        steamid = rawSteamId, profile = profile, slot = 1, characterId = characterOne
    })
    local first = ZM_GetPlayerData(characterOne, profile)
    local second = ZM_GetPlayerData(characterTwo, profile)
    local bioAfterDelete = Characters:GetBio(characterOne)
    local characters = run("SELECT slot FROM characters WHERE steamid = " .. sql.SQLStr(rawSteamId) .. " AND profile = " .. sql.SQLStr(profile))
    check(deleted, "delete transaction succeeds: " .. tostring(deleteError))
    check(first == nil and second and tonumber(second.XP) == 2, "deletion removes slot 1 and preserves slot 2 progression")
    check(bioAfterDelete == "", "deletion removes the selected character's bio")
    check(characters and #characters == 1 and tonumber(characters[1].slot) == 2, "deletion preserves the other character record")
    for _, tableName in ipairs(Characters.StorageTables) do
        local remaining = run("SELECT COUNT(*) AS count FROM " .. tableName .. " WHERE steamid IN ("
            .. sql.SQLStr(characterOne) .. ", " .. sql.SQLStr(characterTwo) .. ") AND profile = " .. sql.SQLStr(profile))
        check(remaining and tonumber(remaining[1].count) == 1,
            tableName .. " removes the selected slot and preserves the other slot")
    end
    local active = run("SELECT slot FROM active_characters WHERE steamid = " .. sql.SQLStr(rawSteamId) .. " AND profile = " .. sql.SQLStr(profile))
    check(active and #active == 0, "deleting the active slot clears its active selection")
    local cleanupResult, cleanupError = Characters:DeleteOwnedRows({
        steamid = rawSteamId, profile = profile, slot = 2, characterId = characterTwo
    })
    check(cleanupResult, "test cleanup succeeds: " .. tostring(cleanupError))
end)

Suite:Add("active selection is persistent and ownerless writes fail", function(check)
    insertCharacter(rawSteamId, 1, characterOne, "Persistent Test")
    run("INSERT INTO active_characters (steamid, profile, slot, selectedAt) VALUES ("
        .. sql.SQLStr(rawSteamId) .. ", " .. sql.SQLStr(profile) .. ", 1, " .. os.time() .. ")")
    local resolvedBeforeRespawn = Characters:GetCharacterKeyForSteamID(rawSteamId, profile)
    local resolvedAfterRespawn = Characters:GetCharacterKeyForSteamID(rawSteamId, profile)
    check(resolvedBeforeRespawn == characterOne and resolvedAfterRespawn == characterOne,
        "active character can be resolved again after player state is recreated")
    local saved, saveError = ZM_CommitWrites(profile, { { kind = "credits", expected = 0, balance = 1, reason = "invalid test" } })
    check(not saved and string.find(tostring(saveError), "character persistence key", 1, true) ~= nil,
        "a character-owned write without an active key is refused")
    local cleanupResult = Characters:DeleteOwnedRows({
        steamid = rawSteamId, profile = profile, slot = 1, characterId = characterOne
    })
    check(cleanupResult, "test cleanup succeeds")
end)

Suite:Add("trade and profession rows retain character attribution", function(check)
    local professionSaved, professionError = ZM_CommitWrites(profile, { {
        kind = "professionClaim", steamid = characterOne, day = "2099-01-01", job = "Civilian",
        claimedAt = os.time(), items = {}
    } })
    local tradeSaved, tradeError = ZM_CommitWrites(profile, { {
        kind = "tradeLedger", steamid = characterTwo, requestId = "test-" .. suffix, safeZoneId = "test-den",
        traderId = "test-trader", day = "2099-01-01", tradeKind = "sell", itemId = "itemBandage",
        count = 1, cash = 2, credits = 0, createdAt = os.time()
    } })
    local claimOwner = sql.QueryValue("SELECT steamid FROM profession_claims WHERE steamid = "
        .. sql.SQLStr(characterOne) .. " AND profile = " .. sql.SQLStr(profile) .. " AND day = '2099-01-01'")
    local tradeOwner = sql.QueryValue("SELECT steamid FROM trade_ledger WHERE steamid = "
        .. sql.SQLStr(characterTwo) .. " AND profile = " .. sql.SQLStr(profile) .. " AND requestId = "
        .. sql.SQLStr("test-" .. suffix))
    check(professionSaved, "profession claim saves for its character: " .. tostring(professionError))
    check(tradeSaved, "trade ledger saves for its character: " .. tostring(tradeError))
    check(claimOwner == characterOne and tradeOwner == characterTwo, "trade and profession ownership remains character-specific")
    cleanup()
end)

ZM_TestHarness.Register({
    command = "zn_test_characters",
    label = "Character persistence",
    file = "characters-tests.json",
    report = "characters",
    help = "Tests character slot migration, storage isolation, ownership, and validation.",
    run = function()
        cleanup()
        local summary = Suite:Run({ teardown = cleanup })
        return summary
    end
})
