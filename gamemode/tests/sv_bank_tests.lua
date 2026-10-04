// Bank tests use a throwaway character/profile and exercise inventory, cash, and history writes together.
local Bank = ZM_BankService
local Inventory = ZM_InventoryService
local Items = ZM_Items
local playerId = "STEAM_TEST:0:2980"
local profile = "zn_test_bank"
local denId = "zn_test_bank_den"

local function person(cash)
    return {
        IsValid = function() return true end,
        IsPlayer = function() return true end,
        Alive = function() return true end,
        SteamID = function() return playerId end,
        GetWeapons = function() return {} end,
        inDen = true,
        CurrentSafeZoneId = denId,
        ZM_InventoryProfile = profile,
        ZM_Inventory = Inventory.NewInventory(),
        Cash = cash or 0,
        SendPlayerData = function() end
    }
end

local function cashBundles(target)
    return Inventory.Ops.Count(target.ZM_Inventory, "itemCashBundle")
end

local function storedCash()
    local row = ZM_GetPlayerData(playerId, profile)
    return row and tonumber(row.Cash) or nil
end

local function cleanup()
    ZM_DeletePlayerItems(playerId, profile)
    ZM_ReplaceDenStashItems(playerId, profile, denId, {})
    ZM_DeleteBankLedger(playerId, profile)
    sql.Query("DELETE FROM player_data WHERE steamid = " .. sql.SQLStr(playerId) .. " AND profile = " .. sql.SQLStr(profile))
end

local suite = ZM_TestHarness.NewSuite()
local function test(name, body)
    suite:Add(name, body)
end

local function withBankOverrides(callback)
    local originalCheck = Bank.CheckAccess
    local originalSend = Inventory.Send
    Bank.CheckAccess = function(_, target)
        return { characterKey = playerId, profile = profile }
    end
    Inventory.Send = function() end
    local ok, result = pcall(callback)
    Bank.CheckAccess = originalCheck
    Inventory.Send = originalSend
    if not ok then error(result) end
    return result
end

test("deposit_and_withdraw_update_inventory_cash_and_ledger_atomically", function(check)
    local target = person(50)
    check(ZM_SetPlayerData(playerId, profile, { Cash = 50 }, "bank test"), "the bank balance row should be created")
    check(Inventory.Ops.Add(target.ZM_Inventory, "backpack", {
        instanceId = "bankcash1", itemId = "itemCashBundle", count = 250, level = 1, mastercraft = false, clip = 0, createdAt = 0
    }), "test cash bundles should fit")
    check(Inventory:Mutate(target, function() return true end), "test inventory should persist")

    withBankOverrides(function()
        local deposited, depositMessage = Bank:Transfer(target, {}, "deposit", 100, "bank-deposit-1")
        check(deposited, "deposit should succeed: " .. tostring(depositMessage))
        check(target.Cash == 150 and storedCash() == 150, "deposit should update the live and stored balance")
        check(cashBundles(target) == 150, "deposit should remove exactly the requested bundle amount")

        local withdrawn, withdrawMessage = Bank:Transfer(target, {}, "withdraw", 100, "bank-withdraw-1")
        check(withdrawn, "withdrawal should succeed: " .. tostring(withdrawMessage))
        check(target.Cash == 50 and storedCash() == 50, "withdrawal should update the live and stored balance")
        check(cashBundles(target) == 250, "withdrawal should return the same value as item bundles")

        local rows = ZM_GetBankLedger(playerId, profile, 10)
        check(#rows == 2 and rows[1].kind == "withdraw" and tonumber(rows[1].balance) == 50, "the latest ten persistent transactions should be newest-first")

        local replayed = Bank:Transfer(target, {}, "deposit", 100, "bank-deposit-1")
        check(not replayed, "a transaction request id must not be reusable")
        check(target.Cash == 50 and storedCash() == 50 and cashBundles(target) == 250, "a replay must not duplicate a bank transfer")
        check(#ZM_GetBankLedger(playerId, profile, 10) == 2, "a replay must not append a history entry")
    end)
end)

test("insufficient_funds_and_full_backpack_refuse_without_changes", function(check)
    local target = person(25)
    check(ZM_SetPlayerData(playerId, profile, { Cash = 25 }, "bank test"), "the bank balance row should be created")
    local weaponLevel = Items:GetDefinition("weaponMeleeCrowbar").minLevel
    for index = 1, Items.ContainerCapacity.backpack do
        local added = Inventory.Ops.Add(target.ZM_Inventory, "backpack", {
            instanceId = "bankweapon" .. index, itemId = "weaponMeleeCrowbar", count = 1, level = weaponLevel, mastercraft = false, clip = 0, createdAt = 0
        })
        check(added, "test weapon " .. index .. " should fit in the backpack")
    end
    check(table.Count(target.ZM_Inventory.backpack) == Items.ContainerCapacity.backpack, "the test backpack should be full")
    check(Inventory:Mutate(target, function() return true end), "test inventory should persist")

    withBankOverrides(function()
        local deposit = Bank:Transfer(target, {}, "deposit", 51, "bank-insufficient-deposit")
        check(not deposit, "a deposit larger than held bundles should be rejected")
        local withdraw = Bank:Transfer(target, {}, "withdraw", 26, "bank-insufficient-withdraw")
        check(not withdraw, "a withdrawal larger than the balance should be rejected")
        local full, fullMessage = Bank:Transfer(target, {}, "withdraw", 10, "bank-full-backpack")
        check(not full, "a withdrawal should be refused when its cash bundle cannot fit: " .. tostring(fullMessage))
    end)
    check(target.Cash == 25 and storedCash() == 25, "refused transfers should leave the balance unchanged")
    check(cashBundles(target) == 0 and #ZM_GetBankLedger(playerId, profile, 10) == 0, "refused transfers should not create bundles or write history")
end)

test("bank_and_stash_physics_are_frozen", function(check)
    for _, class in ipairs({ "zn_bank", "zn_den_stash" }) do
        local entity = ents.Create(class)
        check(IsValid(entity), class .. " should be creatable")
        if IsValid(entity) then
            entity:SetPos(Vector(0, 0, 10000))
            entity:Spawn()
            local physics = entity:GetPhysicsObject()
            check(IsValid(physics), class .. " should have a physics object")
            if IsValid(physics) then
                check(not physics:IsMotionEnabled(), class .. " physics should have motion disabled")
            end
            entity:Remove()
        end
    end
end)

function Bank:RunTests()
    local restoreStashAccess = ZM_TestHarness.StubStashAccess()
    local summary = withBankOverrides(function()
        local summary = suite:Run({ before = cleanup, after = cleanup })
        return summary
    end)
    restoreStashAccess()
    return summary
end

ZM_TestHarness.Register({
    command = "zn_test_bank",
    label = "Bank",
    file = "bank_tests.json",
    report = "bankTests",
    help = "Tests atomic den bank transfers, cash bundles, and persistent transaction history.",
    run = function() return Bank:RunTests() end
})
