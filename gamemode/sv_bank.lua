// Server-authoritative cash banking. Item bundles, bank balance, and the persistent transaction history commit together.
ZM_BankService = ZM_BankService or {}
local Bank = ZM_BankService
local Inventory = ZM_InventoryService

util.AddNetworkString("ZM.Bank.Open")
util.AddNetworkString("ZM.Bank.Request")
util.AddNetworkString("ZM.Bank.State")

Bank.Range = 160
Bank.RequestCooldown = 0.25
Bank.MaximumTransfer = 1000000
Bank.HistoryLimit = 10
Bank.TransferPresets = { 100, 500, 1000 }

local function profileFor(target)
    return ZM_Util.ProfileFor(target)
end

function Bank:Init()
    return ZM_CreateBankTables()
end

function Bank:CheckAccess(target, terminal)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
        return false, "You must be alive to use the bank."
    end
    if not target.ZM_Inventory then
        return false, "Your inventory is not loaded."
    end
    local characterKey, keyError = ZM_Util.CharacterKeyFor(target)
    if not characterKey then return false, "No active character: " .. tostring(keyError) end
    if not Inventory:CanAccessStash(target) then
        return false, "Banking is only available inside a den."
    end
    if not IsValid(terminal) or terminal:GetClass() ~= "zn_bank" then
        return false, "That bank terminal is no longer here."
    end
    if target:GetPos():DistToSqr(terminal:GetPos()) > self.Range * self.Range then
        return false, "Stand closer to the bank terminal."
    end
    local visibility = util.TraceLine({
        start = target:EyePos(),
        endpos = terminal:WorldSpaceCenter(),
        filter = { target, terminal },
        mask = MASK_SOLID
    })
    if visibility.Hit then
        return false, "The bank terminal is blocked from view."
    end
    return { characterKey = characterKey, profile = profileFor(target) }
end

function Bank:BundleCount(inventory)
    return Inventory.Ops.Count(inventory, "itemCashBundle", "backpack")
        + Inventory.Ops.Count(inventory, "itemCashBundle", "stash")
end

function Bank:BuildState(target, terminal, ok, message)
    local context, reason = self:CheckAccess(target, terminal)
    local state = {
        available = context ~= false and context ~= nil,
        reason = context and nil or reason,
        ok = ok ~= false,
        message = message,
        terminal = IsValid(terminal) and terminal:EntIndex() or nil,
        balance = math.max(0, tonumber(target.Cash) or 0),
        depositable = target.ZM_Inventory and self:BundleCount(target.ZM_Inventory) or 0,
        maximumTransfer = self.MaximumTransfer,
        presets = self.TransferPresets,
        history = {}
    }
    if not context then return state end
    local history, historyError = ZM_GetBankLedger(context.characterKey, context.profile, self.HistoryLimit)
    if not history then
        state.available = false
        state.reason = "Could not read bank history: " .. tostring(historyError)
        return state
    end
    state.history = history
    return state
end

function Bank:Transfer(target, terminal, action, amount, requestId)
    local context, accessError = self:CheckAccess(target, terminal)
    if not context then return false, accessError end
    if action ~= "deposit" and action ~= "withdraw" then
        return false, "Choose deposit or withdraw."
    end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > self.MaximumTransfer then
        return false, "Enter a whole-dollar amount from 1 to " .. string.Comma(self.MaximumTransfer) .. "."
    end
    if type(requestId) ~= "string" or not string.match(requestId, "^[%w_-]+$") or #requestId > 40 then
        return false, "Invalid transaction request."
    end

    local oldBalance = math.max(0, tonumber(target.Cash) or 0)
    local newBalance
    if action == "deposit" then
        local held = self:BundleCount(target.ZM_Inventory)
        if held < amount then
            return false, "You have only $" .. string.Comma(held) .. " in cash bundles."
        end
        newBalance = oldBalance + amount
        if newBalance > 2147483647 then return false, "Your bank balance is at its limit." end
    else
        if oldBalance < amount then
            return false, "You have only $" .. string.Comma(oldBalance) .. " in the bank."
        end
        newBalance = oldBalance - amount
    end

    local changed, result = Inventory:Mutate(target, function(draft)
        if action == "deposit" then
            local remaining = amount
            for _, container in ipairs({ "backpack", "stash" }) do
                local available = Inventory.Ops.Count(draft, "itemCashBundle", container)
                local take = math.min(available, remaining)
                if take > 0 then
                    local removed, removeError = Inventory.Ops.Remove(draft, container, "itemCashBundle", take)
                    if not removed then return false, removeError end
                    remaining = remaining - take
                end
            end
            if remaining ~= 0 then return false, "Your cash bundles changed; refresh the bank and try again." end
        else
            local bundle = {
                instanceId = Inventory.NewInstanceId(),
                itemId = "itemCashBundle",
                count = amount,
                level = 1,
                mastercraft = false,
                clip = 0,
                createdAt = os.time()
            }
            local added, addError = Inventory.Ops.Add(draft, "backpack", bundle)
            if not added then return false, "There is not enough backpack space for that withdrawal: " .. tostring(addError) end
        end
        return true, { balance = newBalance }
    end, {
        extraSteps = function()
            return {
                { kind = "cash", steamid = context.characterKey, expected = oldBalance, cash = newBalance },
                {
                    kind = "bankLedger",
                    steamid = context.characterKey,
                    requestId = requestId,
                    transactionKind = action,
                    amount = amount,
                    balance = newBalance
                }
            }
        end
    })
    if not changed then
        return false, string.find(tostring(result), "could not save", 1, true)
            and ("The bank transfer could not be saved: " .. tostring(result))
            or tostring(result)
    end
    target.Cash = newBalance
    if target.SendPlayerData then target:SendPlayerData() end
    return true, string.format("%s $%s.", action == "deposit" and "Deposited" or "Withdrew", string.Comma(amount))
end

function Bank:SendState(target, terminal, ok, message)
    if not IsValid(target) or not target:IsPlayer() then return end
    local state = self:BuildState(target, terminal, ok, message)
    net.Start("ZM.Bank.State")
        net.WriteString(util.TableToJSON(state, false) or "{}")
    net.Send(target)
end

net.Receive("ZM.Bank.Request", function(length, target)
    if not IsValid(target) or not target:IsPlayer() or length > 1024 then return end
    local terminal = Entity(net.ReadUInt(16))
    local request = util.JSONToTable(net.ReadString())
    if type(request) ~= "table" then
        Bank:SendState(target, terminal, false, "Invalid bank request.")
        return
    end
    local now = CurTime()
    if target.ZM_NextBankRequestAt and now < target.ZM_NextBankRequestAt then
        Bank:SendState(target, terminal, false, "Slow down.")
        return
    end
    target.ZM_NextBankRequestAt = now + Bank.RequestCooldown
    local action = request.action
    local ok, message = true, nil
    if action == "refresh" then
        local _, accessError = Bank:CheckAccess(target, terminal)
        if accessError then ok, message = false, accessError end
    else
        ok, message = Bank:Transfer(target, terminal, action, request.amount, request.requestId)
    end
    Bank:SendState(target, terminal, ok, message)
end)
