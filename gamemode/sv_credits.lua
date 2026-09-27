// Server-owned credits: a profile-scoped premium currency, separate from cash. Balances live in player_credits and
// every change appends a credit_ledger row in the same transaction, so each balance has an audit trail.
// Credits are granted only by admins/development tools in Alpha 2.8; there is no real-money path.
ZM_CreditService = ZM_CreditService or {}
local Credits = ZM_CreditService
local StaticData = ZM_StaticData

local profileFor = ZM_Util.ProfileFor

local isPlayerEntity = ZM_Util.IsPlayerEntity

local isWholeNumber = ZM_Util.IsWholeNumber

function Credits:Get(target)
    return tonumber(target and target.Credits) or 0
end

function Credits:Load(target)
    local balance, loadError = ZM_GetPlayerCredits(target:SteamID(), profileFor(target))
    target.Credits = balance or 0
    self:Sync(target)
    if balance == nil then return false, loadError end
    return true
end

function Credits:Sync(target)
    if isPlayerEntity(target) then
        target:SetNWInt("Credits", self:Get(target))
    end
end

// A ZM_CommitWrites step changing the balance by delta. Returns the step or nil and a player-facing reason.
function Credits:Step(target, delta, reason, ref)
    if not isWholeNumber(delta) or delta == 0 then
        return nil, "The credit change must be a whole number other than 0."
    end
    local current = self:Get(target)
    local balance = current + delta
    if balance < 0 then
        return nil, "Not enough credits (" .. current .. " held, " .. -delta .. " needed)."
    end
    if balance > StaticData.MaximumCredits then
        return nil, "Credits cannot exceed " .. StaticData.MaximumCredits .. "."
    end
    return { kind = "credits", steamid = target:SteamID(), expected = current, balance = balance, reason = reason, ref = ref }
end

// Applies a saved step to the in-memory balance.
function Credits:Apply(target, step)
    target.Credits = step.balance
    self:Sync(target)
end

// Grants (or, with a negative delta, removes) credits in its own transaction.
function Credits:Grant(target, delta, reason, ref)
    local step, stepError = self:Step(target, delta, reason, ref)
    if not step then return false, stepError end
    local saved, saveError = ZM_CommitWrites(profileFor(target), { step })
    if not saved then return false, "Could not save credits: " .. tostring(saveError) end
    self:Apply(target, step)
    return true, step.balance
end

// ---------------------------------------------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------------------------------------------

local firstHuman = ZM_Util.FirstHuman

local function runCreditCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command, { zn_credits = true }) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    if not target then return false, "no target player" end
    local ok, message = true, nil
    if command == "zn_grant_credits" then
        local amount = tonumber(arguments[1])
        local reason = arguments[2] and string.sub(arguments[2], 1, 48) or "admin grant"
        ok, message = Credits:Grant(target, amount, "grant: " .. reason)
        message = ok and ("balance is now " .. message) or message
    elseif command == "zn_dev_reset_credits" then
        ok, message = ZM_DeletePlayerCredits(target:SteamID(), profileFor(target))
        if ok then
            target.Credits = 0
            Credits:Sync(target)
            message = "deleted this profile's credits, ledger, and mastercraft attempts"
        end
    end
    local ledger = ZM_GetCreditLedger(target:SteamID(), profileFor(target), 10) or {}
    local output = "[ZombieSim] " .. command .. ": " .. tostring(message or (ok and "ok" or "failed")) .. " (credits " .. Credits:Get(target) .. ")"
    ZM_Util.Print(caller, output)
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("credits", { command = command, ok = ok, message = message, credits = Credits:Get(target), stored = ZM_GetPlayerCredits(target:SteamID(), profileFor(target)), ledger = ledger })
    end
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_credits = "Reports the target player's credit balance and the last ten ledger entries.",
    zn_grant_credits = "zn_grant_credits <amount> [reason]: admin; adds credits (a negative amount removes them).",
    zn_dev_reset_credits = "Development: deletes the target player's credits, ledger, and mastercraft attempts for the active profile."
}, runCreditCommand)
