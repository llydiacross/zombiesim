// Server-owned Mastercrafting Station: credit-priced den services. Mastercrafting upgrades an ordinary weapon in the
// backpack in place (same instance id and level): it becomes a mastercraft with freshly rolled attributes, and every
// attribute at max is an Ultra Mastercraft. Each instance can be attempted once; the attempt is recorded in
// mastercraft_attempts in the same transaction as the item and the credits, and the credits are spent whatever the roll.
// The station also sells a job change. Clients name only an action and an id: the server quotes a price under a
// single-use token, and a confirmation re-checks everything before anything is spent.
ZM_MastercraftService = ZM_MastercraftService or {}
local Svc = ZM_MastercraftService
local Service = ZM_InventoryService
local Credits = ZM_CreditService
local Items = ZM_Items
local Generation = ZM_ItemGeneration
local StaticData = ZM_StaticData

util.AddNetworkString("ZM.MastercraftRequest")
util.AddNetworkString("ZM.MastercraftState")

Svc.StationRange = 128
Svc.QuoteLifetime = 60
Svc.RequestCooldown = 0.25

local profileFor = ZM_Util.ProfileFor

local isPlayerEntity = ZM_Util.IsPlayerEntity

// Nearest Mastercrafting Station in range of the player, or nil.
function Svc:FindStation(target)
    if not target.GetPos then return nil end
    local best, bestDistance
    for _, station in ipairs(ents.FindByClass(StaticData.MastercraftStation)) do
        local distance = target:GetPos():DistToSqr(station:NearestPoint(target:GetPos()))
        if distance <= self.StationRange * self.StationRange and (not bestDistance or distance < bestDistance) then
            best, bestDistance = station, distance
        end
    end
    return best
end

function Svc:CheckAccess(target)
    if not IsValid(target) or (target.Alive and not target:Alive()) then
        return false, "You must be alive."
    end
    if not target.ZM_Inventory then
        return false, "Your inventory is not loaded."
    end
    if not Service:CanAccessStash(target) then
        return false, "The Mastercrafting Station is only available inside a den."
    end
    if not self:FindStation(target) then
        return false, "Stand next to a Mastercrafting Station."
    end
    if not StaticData:GetDenServices() then
        return false, "Den services are not loaded."
    end
    return true
end

// Backpack weapon by instance id, or the first ordinary (non-mastercraft) weapon with that item id.
function Svc:FindWeapon(target, ref)
    local bestSlot, best
    for slot, instance in pairs(target.ZM_Inventory and target.ZM_Inventory.backpack or {}) do
        if instance.instanceId == ref then return instance end
        local definition = Items:GetDefinition(instance.itemId)
        if instance.itemId == ref and definition and definition.attributes and not instance.mastercraft and (not bestSlot or slot < bestSlot) then
            bestSlot, best = slot, instance
        end
    end
    return best
end

// Why an instance cannot be mastercrafted, or nil when it can.
function Svc:IneligibleReason(target, instance)
    local definition = Items:GetDefinition(instance.itemId)
    if not definition or not definition.attributes then
        return "Only weapons can be mastercrafted."
    end
    if instance.mastercraft then
        return "This weapon is already a mastercraft."
    end
    local attempt, attemptError = ZM_GetMastercraftAttempt(target:SteamID(), profileFor(target), instance.instanceId)
    if attempt == nil then
        return "Could not check earlier attempts: " .. tostring(attemptError)
    end
    if attempt then
        return "This weapon has already been through a mastercraft attempt."
    end
end

function Svc:CheckMastercraft(target, ref)
    local access, reason = self:CheckAccess(target)
    if not access then return false, reason end
    if type(ref) ~= "string" or #ref > 64 then return false, "Invalid weapon." end
    local instance = self:FindWeapon(target, ref)
    if not instance then return false, "That weapon is not in your backpack." end
    local ineligible = self:IneligibleReason(target, instance)
    if ineligible then return false, ineligible end
    local cost = StaticData:GetMastercraftCost(instance.level)
    if Credits:Get(target) < cost then
        return false, "Mastercrafting this weapon costs " .. cost .. " credits; you have " .. Credits:Get(target) .. "."
    end
    return { kind = "mastercraft", ref = instance.instanceId, instanceId = instance.instanceId, itemId = instance.itemId, level = instance.level, cost = cost, name = Items:GetDisplayName(instance) }
end

function Svc:CheckJobChange(target, job)
    local access, reason = self:CheckAccess(target)
    if not access then return false, reason end
    local id, resolveError = ZM_ProfessionService:ResolveJob(job)
    if not id then return false, resolveError end
    local current = target.GetJobRole and target:GetJobRole() or target.Job
    if id == current then return false, "You are already a " .. id .. "." end
    local cost = StaticData:GetDenServices().jobChange.credits
    if Credits:Get(target) < cost then
        return false, "A job change costs " .. cost .. " credits; you have " .. Credits:Get(target) .. "."
    end
    return { kind = "job", ref = id, job = id, cost = cost, name = (StaticData:GetProfession(id) or {}).name or id }
end

function Svc:Check(target, kind, ref)
    if kind == "mastercraft" then return self:CheckMastercraft(target, ref) end
    if kind == "job" then return self:CheckJobChange(target, ref) end
    return false, "Unknown station service."
end

// Issues a single-use quote for a checked request, replacing any earlier quote.
function Svc:Quote(target, kind, ref)
    local request, reason = self:Check(target, kind, ref)
    if not request then return false, reason end
    local token = string.format("%08x%06x", os.time(), math.random(0, 0xFFFFFF))
    target.ZM_StationQuote = { id = token, kind = request.kind, ref = request.ref, cost = request.cost, name = request.name, expiresAt = CurTime() + self.QuoteLifetime }
    return true, target.ZM_StationQuote
end

// Spends a quote. The quote is consumed even when the confirmation fails, so a replay can never spend twice.
// options.seed (admin/tests only) makes the attribute roll repeatable.
function Svc:Confirm(target, token, options)
    local quote = target.ZM_StationQuote
    target.ZM_StationQuote = nil
    if not quote or type(token) ~= "string" or quote.id ~= token then
        return false, "That quote is no longer valid; request a new one."
    end
    if CurTime() >= quote.expiresAt then
        return false, "That quote expired; request a new one."
    end
    local request, reason = self:Check(target, quote.kind, quote.ref)
    if not request then return false, reason end
    if request.cost ~= quote.cost then
        return false, "The price changed from " .. quote.cost .. " to " .. request.cost .. " credits; request a new quote."
    end
    if request.kind == "mastercraft" then
        return self:PerformMastercraft(target, request, options)
    end
    return self:PerformJobChange(target, request)
end

function Svc:PerformMastercraft(target, request, options)
    options = options or {}
    local definition = Items:GetDefinition(request.itemId)
    local rng = Generation.NewRng(options.seed)
    local attributes = Generation:RollAttributes(definition, request.level, true, rng, StaticData:GetDenServices().mastercraft.ultraChance)
    local ultra = Items:IsUltraMastercraft({ itemId = request.itemId, mastercraft = true, attributes = attributes })
    local now = os.time()
    local creditStep, creditError = Credits:Step(target, -request.cost, "mastercraft", request.instanceId)
    if not creditStep then return false, creditError end
    local ok, result = Service:Mutate(target, function(draft)
        local container, _, instance = Service.Ops.FindInstance(draft, request.instanceId)
        if container ~= "backpack" or not instance then
            return false, "The weapon is no longer in your backpack."
        end
        instance.mastercraft = true
        instance.attributes = table.Copy(attributes)
        local valid, invalidReason = Items:ValidateInstance(instance)
        if not valid then return false, invalidReason end
        return true, table.Copy(instance)
    end, { extraSteps = function()
        return {
            creditStep,
            { kind = "mastercraftAttempt", steamid = target:SteamID(), instanceId = request.instanceId, itemId = request.itemId, level = request.level, credits = request.cost, ultra = ultra, attributes = attributes, attemptedAt = now }
        }
    end })
    if not ok then return false, result end
    Credits:Apply(target, creditStep)
    target.ZM_LastMastercraft = { instance = result, ultra = ultra, credits = request.cost }
    local parts = {}
    for _, name in ipairs(definition.attributes) do
        table.insert(parts, name .. " " .. attributes[name] .. "/" .. definition.maxAttributes)
    end
    return true, (ultra and "ULTRA MASTERCRAFT! " or "Mastercrafted ") .. Items:GetDisplayName(result) .. " for " .. request.cost .. " credits: " .. table.concat(parts, ", ") .. ".", result
end

function Svc:PerformJobChange(target, request)
    local creditStep, creditError = Credits:Step(target, -request.cost, "job change", request.job)
    if not creditStep then return false, creditError end
    local saved, saveError = ZM_CommitWrites(profileFor(target), { { kind = "job", steamid = target:SteamID(), job = request.job }, creditStep })
    if not saved then return false, "Could not change the job: " .. tostring(saveError) end
    Credits:Apply(target, creditStep)
    ZM_ProfessionService:ApplyJob(target, request.job)
    return true, "You are now a " .. request.name .. " (" .. request.cost .. " credits)."
end

function Svc:BuildState(target)
    local services = StaticData:GetDenServices()
    local access, accessReason = self:CheckAccess(target)
    local state = {
        credits = Credits:Get(target), available = access == true, reason = not access and accessReason or nil,
        job = target.GetJobRole and target:GetJobRole() or target.Job,
        jobChangeCost = services and services.jobChange.credits or nil,
        ultraChance = services and services.mastercraft.ultraChance or nil,
        weapons = {}, jobs = ZM_Professions:GetIds()
    }
    for slot, instance in SortedPairs(target.ZM_Inventory and target.ZM_Inventory.backpack or {}) do
        local definition = Items:GetDefinition(instance.itemId)
        if definition and definition.attributes then
            table.insert(state.weapons, {
                instanceId = instance.instanceId, itemId = instance.itemId, slot = slot, name = Items:GetDisplayName(instance),
                level = instance.level, attributes = instance.attributes, maxAttributes = definition.maxAttributes,
                mastercraft = instance.mastercraft == true, ultra = Items:IsUltraMastercraft(instance),
                cost = StaticData:GetMastercraftCost(instance.level), reason = self:IneligibleReason(target, instance)
            })
        end
    end
    local quote = target.ZM_StationQuote
    if quote and CurTime() < quote.expiresAt then
        state.quote = { id = quote.id, kind = quote.kind, ref = quote.ref, name = quote.name, cost = quote.cost, expiresIn = math.floor(quote.expiresAt - CurTime()) }
    end
    if target.ZM_LastMastercraft then
        state.last = { name = Items:GetDisplayName(target.ZM_LastMastercraft.instance), attributes = target.ZM_LastMastercraft.instance.attributes, ultra = target.ZM_LastMastercraft.ultra }
    end
    return state
end

function Svc:SendState(target, ok, message)
    if not isPlayerEntity(target) then return end
    local state = self:BuildState(target)
    state.ok = ok ~= false
    state.message = message
    net.Start("ZM.MastercraftState")
        net.WriteString(util.TableToJSON(state, false) or "{}")
    net.Send(target)
end

// Validates one client request. The client never supplies prices, attributes, or outcomes.
function Svc:HandleRequest(target, request)
    if type(request) ~= "table" or type(request.action) ~= "string" then
        return false, "Invalid request."
    end
    local now = CurTime()
    if target.ZM_NextStationRequestAt and now < target.ZM_NextStationRequestAt then
        return false, "Slow down."
    end
    target.ZM_NextStationRequestAt = now + self.RequestCooldown
    if request.action == "open" then
        return true
    elseif request.action == "quote" then
        local ok, quote = self:Quote(target, request.kind, request.ref)
        if not ok then return false, quote end
        return true
    elseif request.action == "confirm" then
        return self:Confirm(target, request.token)
    elseif request.action == "cancel" then
        target.ZM_StationQuote = nil
        return true, "Cancelled."
    end
    return false, "Unknown action."
end

net.Receive("ZM.MastercraftRequest", function(length, target)
    if not IsValid(target) or length > 2048 then return end
    local ok, message = Svc:HandleRequest(target, util.JSONToTable(net.ReadString()))
    Svc:SendState(target, ok, message)
end)

// ---------------------------------------------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------------------------------------------

local firstHuman = ZM_Util.FirstHuman

local function runStationCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command, { zn_mastercraft = true }) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    if not target then return false, "no target player" end
    local ok, message = true, nil
    if command == "zn_station_quote" then
        local quote
        ok, quote = Svc:Quote(target, arguments[1], arguments[2])
        message = ok and string.format("quote %s: %s %s for %d credits", quote.id, quote.kind, quote.name, quote.cost) or quote
    elseif command == "zn_station_confirm" then
        // "current" confirms the pending quote, so one bridge request can quote and confirm.
        local token = arguments[1] == "current" and target.ZM_StationQuote and target.ZM_StationQuote.id or arguments[1]
        ok, message = Svc:Confirm(target, token, { seed = tonumber(arguments[2]) })
    elseif command == "zn_dev_goto_mastercraft" then
        local station = Svc:FindStation(target)
        if not IsValid(station) then
            local forward = target:GetForward()
            forward.z = 0
            forward:Normalize()
            station = ents.Create(StaticData.MastercraftStation)
            if IsValid(station) then
                station:SetPos(target:GetPos() + forward * 64 + Vector(0, 0, 4))
                station:SetAngles(Angle(0, target:EyeAngles().y + 180, 0))
                station:Spawn()
                local physics = station:GetPhysicsObject()
                if IsValid(physics) then physics:EnableMotion(false) end
                message = "spawned temporary station " .. station:EntIndex() .. " in front of the player"
            else
                ok, message = false, "could not create a Mastercrafting Station"
            end
        else
            message = "a station is already in range"
        end
    end
    local line = "[ZombieSim] " .. command .. ": " .. tostring(message or (ok and "ok" or "failed"))
    ZM_Util.Print(caller, line)
    if ZM_DevConsole and ZM_DevConsole.Report then
        local state = Svc:BuildState(target)
        state.command, state.ok, state.message = command, ok, message
        state.storedCredits = ZM_GetPlayerCredits(target:SteamID(), profileFor(target))
        state.storedJob = (ZM_GetPlayerData(target:SteamID(), profileFor(target)) or {}).Job
        state.ledger = ZM_GetCreditLedger(target:SteamID(), profileFor(target), 5)
        local station = Svc:FindStation(target)
        state.station = IsValid(station) and { entIndex = station:EntIndex(), model = station:GetModel(), hasPhysics = IsValid(station:GetPhysicsObject()) } or nil
        ZM_DevConsole:Report("mastercraft", state)
    end
    Svc:SendState(target, ok, message)
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_mastercraft = "Reports the Mastercrafting Station state: credits, eligible weapons and costs, and any pending quote.",
    zn_station_quote = "zn_station_quote <mastercraft|job> <instanceId|itemId|profession>: admin; quotes a station service.",
    zn_station_confirm = "zn_station_confirm <quoteId|current> [seed]: admin; spends the quote (the seed makes the roll repeatable).",
    zn_dev_goto_mastercraft = "Development: spawns a temporary Mastercrafting Station in front of the player if none is in range."
}, runStationCommand)
