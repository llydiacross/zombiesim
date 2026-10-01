// Server-owned professions: once-per-UTC-day den deliveries and customer-initiated professional services.
// A delivery is granted by one inventory mutation saved in the same transaction as its claim row, whose primary key
// (steamid, profile, day) makes a second grant for the same day impossible. Services always consume the customer's
// own items; the professional contributes their job, level, and bonuses, and receives the agreed cash fee.
ZM_ProfessionService = ZM_ProfessionService or {}
local Pro = ZM_ProfessionService
local Professions = ZM_Professions
local Service = ZM_InventoryService
local Crafting = ZM_CraftingService
local Items = ZM_Items
local StaticData = ZM_StaticData

util.AddNetworkString("ZM.ProfessionRequest")
util.AddNetworkString("ZM.ProfessionState")
util.AddNetworkString("ZM.ProfessionOffer")

Pro.CheckInterval = 5
Pro.RetryDelay = 60
Pro.ServiceRange = 160
Pro.OfferLifetime = 60
Pro.MaximumFee = 100000
Pro.MaximumCookCount = 10
Pro.RequestCooldown = 0.25
Pro.DayOffset = Pro.DayOffset or 0
Pro.Offers = Pro.Offers or {}
Pro.NextOfferId = Pro.NextOfferId or 0

local profileFor = ZM_Util.ProfileFor

local cashOf = ZM_Util.CashOf

local isWholeNumber = ZM_Util.IsWholeNumber

local function levelOf(target)
    return target.GetLevel and target:GetLevel() or 1
end

local function jobOf(target)
    return target.GetJobRole and target:GetJobRole() or StaticData.DefaultProfession
end

local function displayName(itemId)
    return Items:GetDisplayName({ itemId = itemId })
end

local function describeStacks(stacks)
    local parts = {}
    for _, stack in ipairs(stacks) do
        table.insert(parts, stack.count .. " " .. displayName(stack.item))
    end
    return table.concat(parts, ", ")
end

local function notify(target, message)
    if IsValid(target) and target.IsPlayer and target:IsPlayer() and message then
        target:ChatPrint(message)
    end
end

// Server "now" for day boundaries. The development day offset shifts only the claim day, never item timestamps.
function Pro:Now()
    return os.time() + self.DayOffset * 86400
end

// UTC calendar day, e.g. 2026-05-13. Deliveries reset at midnight UTC.
function Pro:Day(now)
    return os.date("!%Y-%m-%d", now or self:Now())
end

// ---------------------------------------------------------------------------------------------------------------
// Daily deliveries
// ---------------------------------------------------------------------------------------------------------------

// The delivery the player would receive today: counts are a stable hash of player, profile, day, and item, so
// re-planning (after a failed save or a full inventory) always yields the same items for that day.
function Pro:PlanDelivery(target, day)
    local job = jobOf(target)
    local tier = Professions:GetDeliveryTier(job, levelOf(target))
    if not tier then
        return nil, job
    end
    local stacks = {}
    for _, entry in ipairs(tier.items) do
        local span = entry.max - entry.min + 1
        local characterKey = ZM_Util.CharacterKeyFor(target)
        if not characterKey then return nil, "no active character" end
        local roll = (tonumber(util.CRC(table.concat({ characterKey, profileFor(target), day, entry.item }, "|"))) or 0) % span
        table.insert(stacks, { item = entry.item, count = entry.min + roll })
    end
    return stacks, job, tier
end

function Pro:GetClaim(target, day)
    local characterKey, keyError = ZM_Util.CharacterKeyFor(target)
    if not characterKey then return nil, keyError end
    return ZM_GetProfessionClaim(characterKey, profileFor(target), day or self:Day())
end

// Grants today's delivery once. Items go to the backpack first, then the den stash; if they do not all fit,
// nothing is granted and the claim stays open for a later retry.
function Pro:Claim(target, now)
    if not target.ZM_Inventory then
        return false, "Your inventory is not loaded."
    end
    if target.Alive and not target:Alive() then
        return false, "You are dead."
    end
    if not Service:CanAccessStash(target) then
        return false, "Deliveries arrive at your den."
    end
    local day = self:Day(now)
    local existing, claimError = self:GetClaim(target, day)
    if claimError then
        return false, "Could not read deliveries: " .. tostring(claimError)
    end
    if existing then
        return false, "Today's delivery has already arrived.", "claimed"
    end
    local stacks, job = self:PlanDelivery(target, day)
    if not stacks then
        return false, "Your profession (" .. job .. ") has no daily delivery.", "none"
    end
    local playerLevel = levelOf(target)
    local createdAt = os.time()
    return Service:Mutate(target, function(draft)
        for _, stack in ipairs(stacks) do
            local definition = Items:GetDefinition(stack.item)
            local remaining = stack.count
            while remaining > 0 do
                local amount = math.min(remaining, definition.maxStack)
                local instance, reason = ZM_ItemGeneration:CreateInstance(stack.item, { count = amount, playerLevel = playerLevel })
                if not instance then
                    return false, reason
                end
                instance.createdAt = createdAt
                if not Service.Ops.Add(draft, "backpack", instance) and not Service.Ops.Add(draft, "stash", instance) then
                    return false, "There is no room for your delivery (" .. displayName(stack.item) .. "). Make space and it will arrive shortly."
                end
                remaining = remaining - amount
            end
        end
        return true, stacks
    end, {
        extraSteps = function()
            return { { kind = "professionClaim", steamid = ZM_Util.CharacterKeyFor(target), day = day, job = job, claimedAt = createdAt, items = stacks } }
        end
    })
end

// Periodic check for connected, loaded, living players inside their den.
function Pro:CheckDeliveries()
    local day = self:Day()
    for _, target in ipairs(player.GetHumans()) do
        if IsValid(target) and target.ZM_Inventory and target:Alive() and target.ZM_DeliveryDay ~= day
            and (target.ZM_DeliveryRetryAt or 0) <= CurTime() and Service:CanAccessStash(target) then
            local ok, result, reason = self:Claim(target)
            if ok then
                target.ZM_DeliveryDay = day
                notify(target, "[Delivery] Your " .. (Professions:Get(jobOf(target)) or {}).name .. " delivery arrived: " .. describeStacks(result) .. ".")
            elseif reason == "claimed" or reason == "none" then
                target.ZM_DeliveryDay = day
            else
                target.ZM_DeliveryRetryAt = CurTime() + self.RetryDelay
                if target.ZM_DeliveryNoticeDay ~= day then
                    target.ZM_DeliveryNoticeDay = day
                    notify(target, "[Delivery] " .. tostring(result))
                end
            end
        end
    end
end

timer.Create("ZM.Professions.Deliveries", Pro.CheckInterval, 0, function()
    Pro:CheckDeliveries()
end)

// ---------------------------------------------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------------------------------------------

// Counts a customer's usable units of an item: backpack plus den stash, at or below the professional's level.
local function countUsable(customer, itemId, maxLevel, skipSpoiled)
    local containers = Service:CanAccessStash(customer) and { "backpack", "stash" } or { "backpack" }
    local total = 0
    for _, container in ipairs(containers) do
        for _, instance in pairs(customer.ZM_Inventory[container] or {}) do
            if instance.itemId == itemId and (tonumber(instance.level) or 1) <= maxLevel
                and not (skipSpoiled and ZM_Food:GetBand(instance) == "spoiled") then
                total = total + instance.count
            end
        end
    end
    return total
end

// The first backpack instance of a medical item the professional is allowed to apply.
local function findTreatable(customer, itemId, maxLevel)
    local bestSlot, best
    for slot, instance in pairs(customer.ZM_Inventory.backpack or {}) do
        if instance.itemId == itemId and (tonumber(instance.level) or 1) <= maxLevel and (not bestSlot or slot < bestSlot) then
            bestSlot, best = slot, instance
        end
    end
    return best
end

local function inRange(customer, provider)
    if customer == provider then return true end
    if not customer.GetPos or not provider.GetPos then return false end
    return customer:GetPos():DistToSqr(provider:GetPos()) <= Pro.ServiceRange * Pro.ServiceRange
end

// Den NPC professionals (zn_den_npc, see ZM_DenNpcs) stand in for a player provider: their configured profession and
// service level replace the player's job and level, they accept at once, they hold no inventory or cash, and their
// fixed fee is taken from the customer without crediting anyone.
local function isNpc(provider)
    return provider ~= nil and provider.ZM_IsDenNpc == true
end
Pro.IsNpcProvider = isNpc

local function providerName(provider)
    return provider.Nick and provider:Nick() or "the professional"
end

// Full eligibility check for a service, run when it is requested and again when it is accepted.
// Returns a normalized request { kind, ref, count, fee, recipe? } or false and a reason.
// For an NPC provider a nil fee means "the NPC's current fee"; any other fee must match it.
function Pro:CheckService(customer, provider, kind, ref, count, fee)
    if not IsValid(customer) or not IsValid(provider) then
        return false, "That player is no longer available."
    end
    local npc = isNpc(provider)
    if not StaticData.ProfessionServices[kind] then
        return false, "Unknown service."
    end
    if type(ref) ~= "string" or #ref > 64 then
        return false, "Invalid service item."
    end
    if npc then
        if not provider:GetJobRole() then
            return false, providerName(provider) .. " has no valid profession and offers nothing."
        end
        local npcFee = provider:GetServiceFee(kind)
        if fee ~= nil and tonumber(fee) ~= npcFee then
            return false, providerName(provider) .. " now charges " .. tostring(npcFee) .. " for that; check the price and try again."
        end
        fee = npcFee
    end
    fee = tonumber(fee) or 0
    if not isWholeNumber(fee, 0, self.MaximumFee) then
        return false, "The fee must be a whole number from 0 to " .. self.MaximumFee .. "."
    end
    if customer == provider and fee ~= 0 then
        return false, "You cannot charge yourself a fee."
    end
    if cashOf(customer) < fee then
        return false, "You cannot afford a fee of " .. fee .. "."
    end
    for _, participant in ipairs(npc and { customer } or { customer, provider }) do
        if participant.Alive and not participant:Alive() then
            return false, "Both players must be alive."
        end
        if not participant.ZM_Inventory then
            return false, "An inventory is not loaded."
        end
        if not Service:CanAccessStash(participant) then
            return false, "Services are only available inside a den."
        end
    end
    if not inRange(customer, provider) then
        return false, "Stand closer to the professional."
    end
    local job = jobOf(provider)
    if not Professions:OffersService(job, kind) then
        return false, (customer == provider and "Your" or "Their") .. " profession (" .. job .. ") does not offer " .. kind .. "."
    end
    local providerLevel = levelOf(provider)
    local request = { kind = kind, ref = ref, fee = fee }
    if kind == "cook" then
        count = tonumber(count) or 1
        if not isWholeNumber(count, 1, self.MaximumCookCount) then
            return false, "Cook from 1 to " .. self.MaximumCookCount .. " at a time."
        end
        local definition = Items:GetDefinition(ref)
        local cooksInto = definition and definition.food and definition.food.cooksInto
        if not cooksInto then
            return false, "That cannot be cooked."
        end
        if countUsable(customer, ref, providerLevel, true) < count then
            return false, "Not enough unspoiled " .. displayName(ref) .. " at or below level " .. providerLevel .. "."
        end
        request.count, request.cooksInto = count, cooksInto
    elseif kind == "treat" then
        local definition = Items:GetDefinition(ref)
        if not definition or not definition.medical then
            return false, "That is not a medical item."
        end
        if not findTreatable(customer, ref, providerLevel) then
            return false, "No " .. displayName(ref) .. " at or below level " .. providerLevel .. " in the backpack."
        end
        if customer:Health() >= customer:GetMaxHealth() then
            return false, "Health is already full."
        end
        request.count = 1
    elseif kind == "implant" then
        local instance = ZM_ImplantService:FindInstallable(customer, ref, providerLevel)
        if not instance then
            return false, "No implant '" .. displayName(ref) .. "' at or below level " .. providerLevel .. " in the backpack."
        end
        request.count, request.slot = 1, Items:GetDefinition(instance.itemId).implant.slot
    elseif kind == "extract" then
        local installed = customer.ZM_Implants and customer.ZM_Implants[ref]
        if not installed then
            return false, "No implant is installed in the " .. ref .. " slot."
        end
        if (tonumber(installed.level) or 1) > providerLevel then
            return false, "Removing a level " .. installed.level .. " implant needs a level " .. installed.level .. " professional."
        end
        if table.Count(customer.ZM_Inventory.backpack or {}) >= Items.ContainerCapacity.backpack then
            return false, "The backpack needs a free slot for the removed implant."
        end
        request.count, request.slot = 1, ref
    else
        local recipe = StaticData:GetRecipe(ref)
        if not recipe or not recipe.service then
            return false, "That is not a research recipe."
        end
        if not recipe.jobs[job] then
            return false, "Only a " .. table.concat(table.GetKeys(recipe.jobs), " or ") .. " can research that."
        end
        local unmet = Crafting:UnmetRequirements(provider, recipe)
        if #unmet > 0 then
            return false, unmet[1]
        end
        for _, stack in ipairs(recipe.ingredients) do
            if countUsable(customer, stack.item, providerLevel, false) < stack.count then
                return false, "Not enough " .. displayName(stack.item) .. "."
            end
        end
        request.count, request.recipe = 1, recipe
    end
    return request
end

// Cash steps for the fee, saved in the same transaction as the item change. Nil when no cash moves.
// An NPC provider has no cash row: only the customer's side is written.
local function feeSteps(customer, provider, fee)
    if fee <= 0 or customer == provider then
        return nil
    end
    if isNpc(provider) or isNpc(customer) then
        local payer = isNpc(provider) and customer or provider
        local sign = isNpc(provider) and -1 or 1
        return function()
            return { { kind = "cash", steamid = ZM_Util.CharacterKeyFor(payer), cash = cashOf(payer) + sign * fee } }
        end
    end
    return function()
        return {
            { kind = "cash", steamid = ZM_Util.CharacterKeyFor(customer), cash = cashOf(customer) - fee },
            { kind = "cash", steamid = ZM_Util.CharacterKeyFor(provider), cash = cashOf(provider) + fee }
        }
    end
end

local function applyFee(customer, provider, fee)
    if fee <= 0 or customer == provider then return end
    if not isNpc(customer) then customer.Cash = cashOf(customer) - fee end
    if not isNpc(provider) then provider.Cash = cashOf(provider) + fee end
    for _, participant in ipairs({ customer, provider }) do
        if not isNpc(participant) then
            if participant.SendPlayerData then participant:SendPlayerData() end
            Service:Send(participant)
        end
    end
end

// Performs a checked service. Returns true and a message, or false and a reason; on failure nothing changes.
function Pro:PerformService(customer, provider, request, now)
    now = now or os.time()
    local providerLevel = levelOf(provider)
    local extraSteps = feeSteps(customer, provider, request.fee)
    if request.kind == "cook" then
        local recipe = {
            ingredients = { { item = request.ref, count = request.count } },
            results = { { item = request.cooksInto, count = request.count } },
            freshness = "inherit"
        }
        local ok, result = Crafting:CraftBatch(customer, recipe, now, { maxIngredientLevel = providerLevel, skipSpoiled = true, extraSteps = extraSteps })
        if not ok then return false, result end
        applyFee(customer, provider, request.fee)
        return true, "Cooked " .. request.count .. " " .. displayName(request.ref) .. " into " .. displayName(request.cooksInto) .. "."
    elseif request.kind == "research" then
        local ok, result = Crafting:CraftBatch(customer, request.recipe, now, { maxIngredientLevel = providerLevel, extraSteps = extraSteps })
        if not ok then return false, result end
        applyFee(customer, provider, request.fee)
        return true, "Researched " .. describeStacks(result) .. "."
    elseif request.kind == "implant" then
        local ok, result = ZM_ImplantService:Install(customer, request.ref, providerLevel, extraSteps, now)
        if not ok then return false, result end
        applyFee(customer, provider, request.fee)
        return true, "Installed " .. displayName(result.installed.itemId) .. " in the " .. result.slot .. " slot"
            .. (result.replaced and ("; " .. displayName(result.replaced.itemId) .. " was returned to the backpack.") or ".")
    elseif request.kind == "extract" then
        local ok, result = ZM_ImplantService:Extract(customer, request.ref, extraSteps)
        if not ok then return false, result end
        applyFee(customer, provider, request.fee)
        return true, "Removed " .. displayName(result.removed.itemId) .. " from the " .. result.slot .. " slot; it is in the backpack."
    end

    // Treatment: the unit is removed (with the fee) before the effect runs, so a failed save grants nothing;
    // a failed effect restores the unit and refunds the fee.
    local instance = findTreatable(customer, request.ref, providerLevel)
    if not instance then
        return false, "The medical item is gone."
    end
    local definition = Items:GetDefinition(instance.itemId)
    local itemClass = Items:GetItemClass(instance.itemId)
    local itemData = { id = instance.itemId, instance = table.Copy(instance), definition = definition }
    local canUse, reason = itemClass:CanUse(provider, itemData, customer)
    if not canUse then
        return false, reason
    end
    local instanceId = instance.instanceId
    local consumed, consumeError = Service:Mutate(customer, function(draft)
        return Service.Ops.RemoveInstance(draft, instanceId, 1)
    end, extraSteps and { extraSteps = extraSteps } or nil)
    if not consumed then
        return false, consumeError
    end
    applyFee(customer, provider, request.fee)
    if itemClass:OnUse(provider, itemData, customer) then
        return true, "Treated with " .. displayName(instance.itemId) .. " (+" .. tostring(itemData.healed or 0) .. " HP)."
    end
    local restore = table.Copy(itemData.instance)
    restore.instanceId = Service.NewInstanceId()
    restore.count = 1
    local refund = feeSteps(provider, customer, request.fee)
    local restored = Service:Mutate(customer, function(draft)
        if not Service.Ops.Add(draft, "backpack", restore) and not Service.Ops.Add(draft, "stash", restore) then
            return false, "no room to restore the medical item"
        end
        return true
    end, refund and { extraSteps = refund } or nil)
    if restored then
        applyFee(provider, customer, request.fee)
    end
    return false, "The treatment could not be applied."
end

// Offers: a customer asks a professional; the professional accepts or declines within OfferLifetime seconds.
// Each offer is single-use and bound to its two players, so replayed or stale responses are refused.
function Pro:FindOfferFor(customer)
    for id, offer in pairs(self.Offers) do
        if offer.customer == customer then return id, offer end
    end
end

function Pro:ExpireOffers(now)
    now = now or CurTime()
    for id, offer in pairs(self.Offers) do
        if now >= offer.expiresAt or not IsValid(offer.customer) or not IsValid(offer.provider) then
            self.Offers[id] = nil
            notify(offer.customer, "[Services] Your request expired.")
        end
    end
end

function Pro:RequestService(customer, provider, kind, ref, count, fee)
    self:ExpireOffers()
    if self:FindOfferFor(customer) then
        return false, "You already have a pending service request."
    end
    local request, reason = self:CheckService(customer, provider, kind, ref, count, fee)
    if not request then
        return false, reason
    end
    if customer == provider or isNpc(provider) then
        return self:PerformService(customer, provider, request)
    end
    self.NextOfferId = self.NextOfferId + 1
    local id = self.NextOfferId .. "-" .. string.format("%06x", math.random(0, 0xFFFFFF))
    self.Offers[id] = {
        id = id, customer = customer, provider = provider, kind = kind, ref = ref,
        count = request.count, fee = request.fee, expiresAt = CurTime() + self.OfferLifetime
    }
    self:SendOffer(provider, self.Offers[id])
    return true, "Request sent to " .. provider:Nick() .. "."
end

function Pro:RespondToOffer(provider, offerId, accept)
    self:ExpireOffers()
    local offer = type(offerId) == "string" and self.Offers[offerId] or nil
    if not offer or offer.provider ~= provider then
        return false, "That request is no longer available."
    end
    self.Offers[offerId] = nil
    if not accept then
        notify(offer.customer, "[Services] " .. provider:Nick() .. " declined your request.")
        return true, "Request declined."
    end
    local request, reason = self:CheckService(offer.customer, provider, offer.kind, offer.ref, offer.count, offer.fee)
    local ok, message = false, reason
    if request then
        ok, message = self:PerformService(offer.customer, provider, request)
    end
    notify(offer.customer, "[Services] " .. (ok and message or ("Request failed: " .. tostring(message))))
    self:SendState(offer.customer, ok, message)
    return ok, message
end

function Pro:CancelOffers(target, reason)
    for id, offer in pairs(self.Offers) do
        if offer.customer == target or offer.provider == target then
            self.Offers[id] = nil
            if offer.customer ~= target then notify(offer.customer, "[Services] " .. reason) end
        end
    end
end

function Pro:SendOffer(provider, offer)
    if not (IsValid(provider) and provider.IsPlayer and provider:IsPlayer()) then return end
    net.Start("ZM.ProfessionOffer")
        net.WriteString(util.TableToJSON({
            id = offer.id, customer = offer.customer:Nick(), kind = offer.kind, ref = offer.ref,
            name = offer.kind == "research" and (StaticData:GetRecipe(offer.ref) or {}).name
                or offer.kind == "extract" and (offer.ref .. " implant")
                or displayName(offer.ref),
            count = offer.count, fee = offer.fee, expiresIn = math.max(0, math.floor(offer.expiresAt - CurTime()))
        }, false) or "{}")
    net.Send(provider)
end

// State for the Services window: profession, delivery status, nearby professionals, and eligible service items.
function Pro:BuildState(target)
    local job = jobOf(target)
    local profession = Professions:Get(job)
    local day = self:Day()
    local claim = target.SteamID and self:GetClaim(target, day) or nil
    local planned = target.SteamID and self:PlanDelivery(target, day) or nil
    local state = {
        job = job, storedJob = target.GetStoredJob and target:GetStoredJob() or job,
        professionName = profession and profession.name or job,
        description = profession and profession.description or "",
        statBonuses = profession and profession.statBonuses or {},
        services = profession and table.GetKeys(profession.services) or {},
        level = levelOf(target), cash = cashOf(target), day = day,
        inDen = Service:CanAccessStash(target),
        delivery = { claimed = claim ~= nil, items = claim and util.JSONToTable(claim.items or "[]") or planned },
        professionals = {}, cookables = {}, treatables = {}, research = {}, installables = {},
        implants = ZM_ImplantService:BuildState(target)
    }
    table.sort(state.services)
    for _, other in ipairs(player.GetHumans()) do
        if IsValid(other) and (other == target or inRange(target, other)) then
            local otherJob = jobOf(other)
            local otherProfession = Professions:Get(otherJob)
            local services = otherProfession and table.GetKeys(otherProfession.services) or {}
            if #services > 0 then
                table.sort(services)
                table.insert(state.professionals, { providerId = "p:" .. other:UserID(), userId = other:UserID(), name = other:Nick(), job = otherJob, level = levelOf(other), services = services, self = other == target })
            end
        end
    end
    if ZM_DenNpcs then
        for _, npc in ipairs(ZM_DenNpcs:FindNear(target, self.ServiceRange)) do
            local resolved = ZM_DenNpcs:Resolve(npc)
            if resolved.job and #resolved.services > 0 then
                table.insert(state.professionals, { providerId = "n:" .. npc:EntIndex(), npc = true, name = resolved.name, job = resolved.job, level = resolved.level, services = resolved.services, fees = resolved.fees })
            end
        end
    end
    local inventory = target.ZM_Inventory
    if inventory then
        local seen = {}
        for _, container in ipairs({ "backpack", "stash" }) do
            for _, instance in pairs(inventory[container] or {}) do
                local definition = Items:GetDefinition(instance.itemId)
                if definition and not seen[instance.itemId] then
                    if definition.food and definition.food.cooksInto then
                        seen[instance.itemId] = true
                        table.insert(state.cookables, { item = instance.itemId, cooksInto = definition.food.cooksInto, have = countUsable(target, instance.itemId, StaticData.MaximumItemLevel, true) })
                    elseif definition.medical and container == "backpack" then
                        seen[instance.itemId] = true
                        table.insert(state.treatables, { item = instance.itemId, health = definition.medical.health })
                    elseif definition.implant and container == "backpack" then
                        seen[instance.itemId] = true
                        table.insert(state.installables, { item = instance.itemId, slot = definition.implant.slot, level = instance.level })
                    end
                end
            end
        end
        local registry = StaticData:GetRegistry()
        for recipeId, recipe in SortedPairs(registry and registry.recipes or {}) do
            if recipe.service then
                local entry = { id = recipeId, name = recipe.name, jobs = table.GetKeys(recipe.jobs), levelRequirement = recipe.levelRequirement, ingredients = {}, results = recipe.results }
                for _, stack in ipairs(recipe.ingredients) do
                    table.insert(entry.ingredients, { item = stack.item, count = stack.count, have = countUsable(target, stack.item, StaticData.MaximumItemLevel, false) })
                end
                table.insert(state.research, entry)
            end
        end
    end
    local _, outgoing = self:FindOfferFor(target)
    if outgoing then
        state.pending = { id = outgoing.id, provider = IsValid(outgoing.provider) and outgoing.provider:Nick() or "?", kind = outgoing.kind, ref = outgoing.ref, expiresIn = math.max(0, math.floor(outgoing.expiresAt - CurTime())) }
    end
    return state
end

function Pro:SendState(target, ok, message)
    if not (IsValid(target) and target.IsPlayer and target:IsPlayer()) then return end
    local state = self:BuildState(target)
    state.ok = ok ~= false
    state.message = message
    net.Start("ZM.ProfessionState")
        net.WriteString(util.TableToJSON(state, false) or "{}")
    net.Send(target)
end

local function playerByUserId(userId)
    local found = Player(tonumber(userId) or -1)
    return IsValid(found) and found or nil
end

// A provider reference from a client or command: "p:<userId>", "n:<entIndex>" for a den NPC, a bare user id, or
// "npc" for the nearest den NPC offering `kind`. Returns the provider or nil.
function Pro:ResolveProvider(target, reference, kind)
    reference = tostring(reference or "")
    local npcIndex = string.match(reference, "^n:(%d+)$")
    if npcIndex then
        local npc = Entity(tonumber(npcIndex))
        return IsValid(npc) and isNpc(npc) and npc or nil
    end
    if reference == "npc" then
        for _, npc in ipairs(ZM_DenNpcs and ZM_DenNpcs:FindNear(target, self.ServiceRange) or {}) do
            local resolved = ZM_DenNpcs:Resolve(npc)
            if resolved.job and (not kind or table.HasValue(resolved.services, kind)) then return npc end
        end
        return nil
    end
    return playerByUserId(string.match(reference, "^p:(%d+)$") or reference)
end

// Validates one client request. Clients name only an action and ids; the server re-derives everything else.
function Pro:HandleRequest(target, request)
    if type(request) ~= "table" or type(request.action) ~= "string" then
        return false, "Invalid request."
    end
    local now = CurTime()
    if target.ZM_NextProfessionRequestAt and now < target.ZM_NextProfessionRequestAt then
        return false, "Slow down."
    end
    target.ZM_NextProfessionRequestAt = now + self.RequestCooldown
    if request.action == "open" then
        return true
    elseif request.action == "request" then
        local provider = self:ResolveProvider(target, request.provider, request.kind)
        if not provider then return false, "That professional is no longer available." end
        local fee = tonumber(request.fee)
        if not isNpc(provider) then fee = fee or 0 end
        return self:RequestService(target, provider, request.kind, request.ref, tonumber(request.count), fee)
    elseif request.action == "respond" then
        return self:RespondToOffer(target, request.offerId, request.accept == true)
    elseif request.action == "cancel" then
        local id = self:FindOfferFor(target)
        if not id then return false, "You have no pending request." end
        self.Offers[id] = nil
        return true, "Request cancelled."
    end
    return false, "Unknown action."
end

net.Receive("ZM.ProfessionRequest", function(length, target)
    if not IsValid(target) or length > 2048 then return end
    local request = util.JSONToTable(net.ReadString())
    local ok, message = Pro:HandleRequest(target, request)
    Pro:SendState(target, ok, message)
end)

hook.Add("PlayerDisconnected", "ZM.Professions.CancelOffers", function(target)
    Pro:CancelOffers(target, "The other player left.")
end)

hook.Add("PlayerDeath", "ZM.Professions.CancelOffers", function(victim)
    Pro:CancelOffers(victim, "The other player died.")
end)

// Sets a player's job (admin/dev only; there is no in-game picker yet). Stores the canonical profession id.
// Canonical profession id for an id, alias, or display name (case and spacing ignored), or nil and a reason.
function Pro:ResolveJob(job)
    local registry = StaticData:GetRegistry()
    local id = registry and (registry.professions[job] and job or registry.professionAliases[job])
    if not id and registry and isstring(job) then
        local key = string.lower(string.gsub(job, "[%s_%-]", ""))
        for professionId, profession in pairs(registry.professions) do
            if string.lower(professionId) == key or string.lower(string.gsub(profession.name or "", "[%s_%-]", "")) == key then
                id = professionId
                break
            end
        end
    end
    if not id then
        return nil, "Unknown profession '" .. tostring(job) .. "' (" .. table.concat(Professions:GetIds(), ", ") .. ")."
    end
    return id
end

// Applies an already-saved job change in memory: networked job, cancelled offers, and refreshed player data.
function Pro:ApplyJob(target, id)
    target.Job = id
    if target.SetNWString then target:SetNWString("Job", id) end
    self:CancelOffers(target, "The professional changed jobs.")
    if target.SendPlayerData then target:SendPlayerData() end
end

function Pro:SetJob(target, job)
    local id, reason = self:ResolveJob(job)
    if not id then
        return false, reason
    end
    target.Job = id
    if target.SetNWString then target:SetNWString("Job", id) end
    self:CancelOffers(target, "The professional changed jobs.")
    if target.UpdatePlayerData then
        local saved, saveError = target:UpdatePlayerData("job change")
        if not saved then return false, "Could not save the job: " .. tostring(saveError) end
    end
    if target.SendPlayerData then target:SendPlayerData() end
    return true, "Job set to " .. id .. "."
end

// ---------------------------------------------------------------------------------------------------------------
// Admin / bridge commands acting on the caller, or the first connected human from the server console.
// ---------------------------------------------------------------------------------------------------------------

local firstHuman = ZM_Util.FirstHuman

local function runProfessionCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command, { zn_service = true, zn_service_respond = true, zn_profession = true }) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    if not target then return false, "no target player" end
    local ok, message = true, nil
    if command == "zn_set_job" then
        ok, message = Pro:SetJob(target, arguments[1])
    elseif command == "zn_claim_delivery" then
        ok, message = Pro:Claim(target)
        if ok then
            target.ZM_DeliveryDay = Pro:Day()
            message = "delivered " .. describeStacks(message)
        end
    elseif command == "zn_dev_advance_day" then
        local days = tonumber(arguments[1]) or 1
        if not isWholeNumber(days, -365, 365) then
            ok, message = false, "days must be a whole number from -365 to 365"
        else
            Pro.DayOffset = days == 0 and 0 or Pro.DayOffset + days
            message = "claim day is now " .. Pro:Day() .. " (offset " .. Pro.DayOffset .. ")"
        end
    elseif command == "zn_dev_reset_claims" then
        local characterKey, keyError = ZM_Util.CharacterKeyFor(target)
        if not characterKey then
            ok, message = false, "no active character: " .. tostring(keyError)
        else
            ok, message = ZM_DeleteProfessionClaims(characterKey, profileFor(target))
            if ok then target.ZM_DeliveryDay = nil end
            message = ok and "cleared delivery claims for this character" or message
        end
    elseif command == "zn_dev_set_health" then
        local health = tonumber(arguments[1])
        if not isWholeNumber(health, 1, target:GetMaxHealth()) then
            ok, message = false, "health must be from 1 to " .. target:GetMaxHealth()
        else
            target:SetHealth(health)
            message = "health set to " .. health
        end
    elseif command == "zn_service" then
        // zn_service <kind> <itemId|recipeId|slot> [count] [fee] [provider]; the provider defaults to yourself and may be
        // a user id, n:<entIndex>, or "npc" (the nearest den NPC offering the service; its fee applies when omitted).
        local provider = arguments[5] and Pro:ResolveProvider(target, arguments[5], arguments[1]) or target
        if not provider then
            ok, message = false, "no player or den NPC matches that provider"
        else
            local fee = tonumber(arguments[4])
            if not isNpc(provider) then fee = fee or 0 end
            ok, message = Pro:RequestService(target, provider, arguments[1], arguments[2], tonumber(arguments[3]) or 1, fee)
        end
    elseif command == "zn_service_respond" then
        ok, message = Pro:RespondToOffer(target, arguments[1], arguments[2] ~= "0")
    end
    local line = "[ZombieSim] " .. command .. ": " .. tostring(message or (ok and "ok" or "failed"))
    ZM_Util.Print(caller, line)
    if ZM_DevConsole and ZM_DevConsole.Report then
        local state = Pro:BuildState(target)
        state.command, state.ok, state.message = command, ok, message
        state.dayOffset = Pro.DayOffset
        state.hp = target:Health()
        state.rows = target.ZM_Inventory and Service.ToRows(target.ZM_Inventory) or nil
        state.claim = Pro:GetClaim(target)
        ZM_DevConsole:Report("professions", state)
    end
    Pro:SendState(target, ok, message)
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_profession = "Reports the target player's profession, today's delivery, and eligible services.",
    zn_set_job = "zn_set_job <profession>: sets the target player's job (admin; ids or aliases such as Medic, Soldier, Police).",
    zn_claim_delivery = "Claims today's profession delivery now instead of waiting for the periodic check.",
    zn_dev_advance_day = "Development: zn_dev_advance_day [days]: shifts the delivery claim day (0 resets). Item timestamps are unaffected.",
    zn_dev_reset_claims = "Development: deletes the target player's delivery claims for the active profile.",
    zn_dev_set_health = "Development: zn_dev_set_health <hp>: sets the target player's health (for treatment checks).",
    zn_service = "zn_service <cook|treat|research|implant|extract> <itemId|recipeId|slot> [count] [fee|-] [userId|n:<entIndex>|npc]: requests a service (yourself by default; '-' takes a den NPC's fee).",
    zn_service_respond = "zn_service_respond <offerId> <1|0>: accepts or declines a pending service request."
}, runProfessionCommand)
