// Native land-claim suite (Alpha 3.4 Phase E): real GMod sql, real inventory transactions, throwaway profile.
// World and safe-zone lookups are replaced only for the duration of the run so no live cell or player is touched.
local Claims = ZM_ClaimService
local Inventory = ZM_InventoryService
local suite = ZM_TestHarness.NewSuite()
local profile, prefix, clock
local tables = { "player_claims", "claim_friends", "player_items", "equipped_weapon_slots" }
local cell = { id = 9001, map = "zn_test_claim_cell" }
local claimable = { ["0,0"] = true, ["1,0"] = true }

local function person(account, character, x, y)
    local target = {
        valid = true, ZM_PersistentStateLoaded = true, ZM_InventoryProfile = profile,
        ZM_Inventory = { backpack = {}, equipped = {}, stash = {} }, position = Vector(x or 0, y or 0, 0)
    }
    function target:IsValid() return true end
    function target:IsPlayer() return false end
    function target:IsBot() return false end
    function target:SteamID() return account end
    function target:GetCharacterKey() return prefix .. "_" .. character end
    function target:GetPos() return self.position end
    function target:GetWorldCell() return cell end
    assert(Inventory.Ops.Add(target.ZM_Inventory, "backpack",
        assert(ZM_ItemGeneration:CreateInstance(Claims.TokenItemId, { count = 2 }))))
    return target
end

local function tokens(target)
    return Inventory.Ops.Count(target.ZM_Inventory, Claims.TokenItemId, "backpack")
end

local function rows(tableName)
    local value = sql.QueryValue("SELECT COUNT(*) FROM " .. tableName .. " WHERE profile = " .. sql.SQLStr(profile))
    assert(value ~= nil and value ~= false, "Could not count " .. tableName .. ": " .. tostring(sql.LastError()))
    return tonumber(value)
end

suite:Add("claiming consumes one token atomically and blocks rivals", function(check)
    local owner = person("STEAM_0:1:2147483630", "owner")
    local ok, result = Claims:ClaimTile(owner, 0, 0)
    assert(ok, result)
    check(tokens(owner) == 1 and rows("player_claims") == 1, "one token becomes one claim row")
    local stored = ZM_GetCellClaims(profile, cell.id)
    check(stored and stored[1] and tonumber(stored[1].tileX) == 0 and stored[1].owner == owner:GetCharacterKey()
        and stored[1].account == owner:SteamID(), "native sql returns the stored owner and account")
    local rival = person("STEAM_0:1:2147483631", "rival")
    local blocked = Claims:ClaimTile(rival, 0, 0)
    check(not blocked and tokens(rival) == 2 and rows("player_claims") == 1, "an active claim keeps the rival's token")
end)

suite:Add("a lapsed claim is never refreshed and can be replaced", function(check)
    local owner = person("STEAM_0:1:2147483632", "lapsed")
    assert(Claims:ClaimTile(owner, 1, 0))
    clock = clock + ZM_ClaimLifetimeSeconds + 1
    local ok, refreshed = Claims:RecordVisit(owner, true)
    check(ok and refreshed == 0, "visits do not revive a lapsed claim")
    local rival = person("STEAM_0:1:2147483633", "replacer", 640, 0)
    local replaced, message = Claims:ClaimTile(rival, 1, 0)
    check(replaced, "lapsed tile can be claimed: " .. tostring(message))
    local snapshot = Claims:CellSnapshot(rival)
    local found
    for _, claim in ipairs(snapshot and snapshot.claims or {}) do
        if claim.tileX == 1 and claim.tileY == 0 then found = claim end
    end
    check(found and found.active and found.mine, "the replacement belongs to the new survivor")
end)

suite:Add("friends refresh active claims until removed", function(check)
    local owner = person("STEAM_0:1:2147483634", "friendly")
    local friend = person("STEAM_0:1:2147483635", "friend")
    // Earlier cases own both tiles; start this case from an empty throwaway profile.
    assert(sql.Query("DELETE FROM player_claims WHERE profile = " .. sql.SQLStr(profile)) ~= false)
    assert(Claims:ClaimTile(owner, 0, 0))
    clock = clock + 120
    local ok, count = Claims:RecordVisit(friend, true)
    check(ok and count == 0, "strangers cannot refresh claims")
    check(Claims:AddFriend(owner, friend:SteamID()), "friend accounts can be added")
    clock = clock + 120
    ok, count = Claims:RecordVisit(friend, true)
    check(ok and count == 1, "friends refresh the owner's active claims")
    check(Claims:RemoveFriend(owner, friend:SteamID()), "friend accounts can be removed")
    clock = clock + 120
    ok, count = Claims:RecordVisit(friend, true)
    check(ok and count == 0, "removed friends lose access")
end)

suite:Add("review snapshots preserve native SQL nulls", function(check)
    local owner = prefix .. "_exact"
    local saved, saveError = ZM_CommitWrites(profile, {
        { kind = "playerItemsExact", steamid = owner, rows = {
            { instanceId = "item_null", container = "backpack", slot = 1, itemId = "itemBandage",
                count = 1, level = 1, mastercraft = 0, clip = 0, createdAt = 10 },
            { instanceId = "item_json", container = "backpack", slot = 2, itemId = "itemBandage",
                count = 1, level = 1, mastercraft = 0, attributes = "{}", clip = 0, createdAt = 11 }
        } },
        { kind = "equippedWeaponSlotsExact", steamid = owner, rows = {
            { slot = 1, selected = 0 },
            { slot = 2, instanceId = "NULL", selected = 0 }
        } }
    })
    assert(saved, saveError)

    local rawItems = assert(ZM_GetPlayerItems(owner, profile))
    local items = assert(ZM_GetExactPlayerItems(owner, profile))
    local slots = assert(ZM_GetExactEquippedWeaponSlots(owner, profile))
    check(rawItems[1].attributes == "NULL" and items[1].attributes == nil and items[2].attributes == "{}",
        "exact item snapshots distinguish SQL NULL from JSON")
    check(slots[1].instanceId == nil and slots[2].instanceId == "NULL",
        "exact slot snapshots distinguish SQL NULL from the literal string")
    saved, saveError = ZM_CommitWrites(profile, {
        { kind = "playerItemsExact", steamid = owner, rows = items },
        { kind = "equippedWeaponSlotsExact", steamid = owner, rows = slots }
    })
    assert(saved, saveError)
    local slotNulls = assert(sql.Query("SELECT instanceId IS NULL AS is_null FROM equipped_weapon_slots WHERE steamid = "
        .. sql.SQLStr(owner) .. " AND profile = " .. sql.SQLStr(profile) .. " ORDER BY slot"))
    check(slotNulls[1].is_null == "1" and slotNulls[2].is_null == "0",
        "exact slot writes preserve both original SQL values")

    assert(sql.Query("UPDATE player_items SET attributes = 'NULL' WHERE steamid = " .. sql.SQLStr(owner)
        .. " AND profile = " .. sql.SQLStr(profile) .. " AND instanceId = 'item_null'") ~= false)
    items = assert(ZM_GetExactPlayerItems(owner, profile))
    saved, saveError = ZM_CommitWrites(profile, { { kind = "playerItemsExact", steamid = owner, rows = items } })
    local stillText = sql.QueryValue("SELECT attributes IS NULL FROM player_items WHERE steamid = " .. sql.SQLStr(owner)
        .. " AND profile = " .. sql.SQLStr(profile) .. " AND instanceId = 'item_null'")
    check(not saved and string.find(tostring(saveError), "invalid exact player-item attributes", 1, true)
        and stillText == "0", "invalid literal attributes are rejected without changing the original row")
end)

local function failureSummary(name, message)
    return { passed = 0, failed = 1, ranAt = os.time(), cases = {
        { name = name, passed = false, failures = { tostring(message) } }
    } }
end

local function cleanProfile()
    local failures = {}
    for _, name in ipairs(tables) do
        if sql.Query("DELETE FROM " .. name .. " WHERE profile = " .. sql.SQLStr(profile)) == false then
            failures[#failures + 1] = name .. ": " .. tostring(sql.LastError())
        elseif rows(name) ~= 0 then
            failures[#failures + 1] = name .. ": rows remain"
        end
    end
    return failures
end

function Claims:RunTests()
    prefix = "zn_claim_test_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    profile = prefix
    for _, name in ipairs(tables) do
        local ok, count = pcall(rows, name)
        if not ok or count ~= 0 then
            return failureSummary("fixture_preflight", ok and ("Refusing to overwrite test profile " .. profile) or count)
        end
    end

    local World, Safe = ZM_World, ZM_SafeZones
    local original = {
        now = self.Now, storage = self.StorageReady, getMapPath = World.GetMapPath, bounds = World.GetCellBounds,
        isClaimable = World.IsClaimableTile, claimTiles = World.GetClaimTiles, coreTile = World.GetCoreTileAt,
        safeCell = Safe and Safe.IsSafeZoneCell
    }
    clock = os.time()
    self.Now = function() return clock end
    World.GetMapPath = function(_, target)
        return target == cell and ("maps/" .. game.GetMap()) or original.getMapPath(World, target)
    end
    World.GetCellBounds = function() return { tileSize = 640, coreHalfExtent = 1600 } end
    World.IsClaimableTile = function(_, cellId, x, y) return cellId == cell.id and claimable[x .. "," .. y] == true end
    World.GetClaimTiles = function() return { { x = 0, y = 0 }, { x = 1, y = 0 } } end
    World.GetCoreTileAt = function(_, position)
        return math.floor(position.x / 640 + 0.5), math.floor(position.y / 640 + 0.5)
    end
    if Safe then Safe.IsSafeZoneCell = function() return false end end

    local ok, summary = xpcall(function() return suite:Run() end, debug.traceback)

    self.Now, World.GetMapPath, World.GetCellBounds = original.now, original.getMapPath, original.bounds
    World.IsClaimableTile, World.GetClaimTiles, World.GetCoreTileAt = original.isClaimable, original.claimTiles, original.coreTile
    if Safe then Safe.IsSafeZoneCell = original.safeCell end
    self.StorageReady = original.storage
    local cleanOk, cleanup = pcall(cleanProfile)
    if not ok then summary = failureSummary("fixture_runtime", summary) end
    if not cleanOk then cleanup = { tostring(cleanup) } end
    if #cleanup > 0 then
        summary.failed = summary.failed + 1
        summary.cases[#summary.cases + 1] = { name = "fixture_cleanup", passed = false, failures = cleanup }
    end
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_claims", label = "Land claims", file = "claim_tests.json", report = "claimTests",
    help = "Tests land-claim tokens, lapsing and friend access in an isolated throwaway profile.",
    run = function() return Claims:RunTests() end
})
