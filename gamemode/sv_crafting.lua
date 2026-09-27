// Server-owned den crafting. Clients only name a recipe and a batch count; the server checks den access, station
// range, requirements, and ingredients, runs a timed job, and exchanges ingredients for results in one saved mutation.
ZM_CraftingService = ZM_CraftingService or {}
local Crafting = ZM_CraftingService
local Service = ZM_InventoryService
local Items = ZM_Items
local StaticData = ZM_StaticData

util.AddNetworkString("ZM.CraftingRequest")
util.AddNetworkString("ZM.CraftingState")

Crafting.StationRange = 128
Crafting.MaximumBatches = 10
Crafting.RequestCooldown = 0.25
Crafting.TickInterval = 0.2
Crafting.IngredientContainers = { "backpack", "stash" }
Crafting.Jobs = Crafting.Jobs or {}

local isWholeNumber = ZM_Util.IsWholeNumber

// Nearest station entity for a recipe station tag within range of the player, or nil.
function Crafting:FindStation(target, stationTag)
    local className = StaticData.CraftingStations[stationTag]
    if not className or not target.GetPos then return nil end
    local best, bestDistance
    for _, station in ipairs(ents.FindByClass(className)) do
        if self:IsStationInRange(target, station) then
            local distance = target:GetPos():DistToSqr(station:GetPos())
            if not bestDistance or distance < bestDistance then
                best, bestDistance = station, distance
            end
        end
    end
    return best
end

function Crafting:IsStationInRange(target, station)
    if not IsValid(station) or not target.GetPos then return false end
    return target:GetPos():DistToSqr(station:NearestPoint(target:GetPos())) <= self.StationRange * self.StationRange
end

// Items the player can craft with: the backpack, plus the den stash while it is accessible.
function Crafting:CountAvailable(target, itemId)
    local inventory = target.ZM_Inventory
    if not inventory then return 0 end
    local total = Service.Ops.Count(inventory, itemId, "backpack")
    if Service:CanAccessStash(target) then
        total = total + Service.Ops.Count(inventory, itemId, "stash")
    end
    return total
end

// Level, attribute, and job gates. Returns a list of unmet requirement descriptions (empty when all are met).
function Crafting:UnmetRequirements(target, recipe)
    local unmet = {}
    local level = target.GetLevel and target:GetLevel() or 1
    if level < recipe.levelRequirement then
        table.insert(unmet, "Requires level " .. recipe.levelRequirement .. ".")
    end
    for attribute, required in SortedPairs(recipe.statRequirements) do
        local value = target.GetStat and target:GetStat(attribute) or 0
        if value < required then
            table.insert(unmet, "Requires " .. attribute .. " " .. required .. ".")
        end
    end
    if recipe.jobs then
        local job = target.GetJobRole and target:GetJobRole() or Items.DefaultJob
        if not recipe.jobs[job] then
            table.insert(unmet, "Requires the " .. table.concat(table.GetKeys(recipe.jobs), " or ") .. " job.")
        end
    end
    return unmet
end

// The number of batches the current ingredients cover.
function Crafting:MaxBatches(target, recipe)
    local batches = self.MaximumBatches
    for _, stack in ipairs(recipe.ingredients) do
        batches = math.min(batches, math.floor(self:CountAvailable(target, stack.item) / stack.count))
    end
    return batches
end

// Full eligibility check for starting `batches` of a recipe. Returns the recipe and station, or false and a reason.
function Crafting:CheckStart(target, recipeId, batches)
    if type(recipeId) ~= "string" or #recipeId > 64 then
        return false, "Invalid recipe."
    end
    if not isWholeNumber(batches, 1, self.MaximumBatches) then
        return false, "Choose from 1 to " .. self.MaximumBatches .. " crafts."
    end
    if target.Alive and not target:Alive() then
        return false, "You are dead."
    end
    if not target.ZM_Inventory then
        return false, "Your inventory is not loaded."
    end
    if not Service:CanAccessStash(target) then
        return false, "Crafting is only available inside your den."
    end
    local recipe = StaticData:GetRecipe(recipeId)
    if not recipe then
        return false, "That recipe is not available."
    end
    if recipe.service then
        return false, "Only a " .. table.concat(table.GetKeys(recipe.jobs), " or ") .. " can make this for you."
    end
    local station = self:FindStation(target, recipe.station)
    if not station then
        return false, "Stand next to a crafting station to craft this."
    end
    local unmet = self:UnmetRequirements(target, recipe)
    if #unmet > 0 then
        return false, unmet[1]
    end
    for _, stack in ipairs(recipe.ingredients) do
        if self:CountAvailable(target, stack.item) < stack.count * batches then
            return false, "Not enough " .. Items:GetDisplayName({ itemId = stack.item }) .. "."
        end
    end
    return recipe, station
end

// Takes `count` of an item from the draft, backpack before stash and oldest first, and returns what was taken.
// Instances above maxLevel (when given) are skipped, so a professional only works items at or below their level;
// skipSpoiled leaves spoiled food behind (cooking services refuse it).
local function takeIngredient(draft, itemId, count, containers, maxLevel, skipSpoiled, now)
    local candidates = {}
    for order, container in ipairs(containers) do
        for slot, instance in pairs(draft[container]) do
            if instance.itemId == itemId and (not maxLevel or (tonumber(instance.level) or 1) <= maxLevel)
                and not (skipSpoiled and ZM_Food:GetBand(instance, now) == "spoiled") then
                table.insert(candidates, { order = order, container = container, slot = slot, instance = instance })
            end
        end
    end
    table.sort(candidates, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        local leftCreated, rightCreated = tonumber(left.instance.createdAt) or 0, tonumber(right.instance.createdAt) or 0
        if leftCreated ~= rightCreated then return leftCreated < rightCreated end
        return left.slot < right.slot
    end)
    local taken, remaining = {}, count
    for _, candidate in ipairs(candidates) do
        if remaining == 0 then break end
        local amount = math.min(candidate.instance.count, remaining)
        local portion = table.Copy(candidate.instance)
        portion.count = amount
        table.insert(taken, portion)
        candidate.instance.count = candidate.instance.count - amount
        if candidate.instance.count == 0 then
            draft[candidate.container][candidate.slot] = nil
        end
        remaining = remaining - amount
    end
    if remaining > 0 then
        return nil
    end
    return taken
end

// Count-weighted freshness of every food ingredient portion that was consumed.
local function averageFreshness(portions, now)
    local weighted, total = 0, 0
    for _, portion in ipairs(portions) do
        local freshness = ZM_Food:GetFreshness(portion, now)
        if freshness then
            weighted = weighted + freshness * portion.count
            total = total + portion.count
        end
    end
    return total > 0 and weighted / total or 1
end

// Crafts one batch as a single inventory mutation: ingredients are removed and results placed (backpack first,
// then the den stash) in one draft, so a missing ingredient, full inventory, or failed save changes nothing.
// options: maxIngredientLevel, skipSpoiled, playerLevel (result level basis), and extraSteps (saved in the same transaction).
function Crafting:CraftBatch(target, recipe, now, options)
    now = now or os.time()
    options = options or {}
    local containers = Service:CanAccessStash(target) and self.IngredientContainers or { "backpack" }
    local playerLevel = options.playerLevel or (target.GetLevel and target:GetLevel()) or 1
    return Service:Mutate(target, function(draft)
        local portions = {}
        for _, stack in ipairs(recipe.ingredients) do
            local taken = takeIngredient(draft, stack.item, stack.count, containers, options.maxIngredientLevel, options.skipSpoiled, now)
            if not taken then
                return false, "Not enough " .. Items:GetDisplayName({ itemId = stack.item }) .. "."
            end
            table.Add(portions, taken)
        end
        local freshness = recipe.freshness == "inherit" and averageFreshness(portions, now) or 1
        local produced = {}
        for _, stack in ipairs(recipe.results) do
            local definition = Items:GetDefinition(stack.item)
            local remaining = stack.count
            while remaining > 0 do
                local amount = math.min(remaining, definition.maxStack)
                local instance, reason = ZM_ItemGeneration:CreateInstance(stack.item, { count = amount, playerLevel = playerLevel })
                if not instance then
                    return false, reason
                end
                instance.createdAt = now
                if definition.food and definition.food.shelfLifeHours then
                    instance.createdAt = now - math.floor((1 - freshness) * definition.food.shelfLifeHours * 3600)
                end
                local added = Service.Ops.Add(draft, "backpack", instance)
                if not added and containers[2] then
                    added = Service.Ops.Add(draft, "stash", instance)
                end
                if not added then
                    return false, "There is no room for " .. Items:GetDisplayName({ itemId = stack.item }) .. "."
                end
                table.insert(produced, { item = stack.item, count = amount, instanceId = instance.instanceId })
                remaining = remaining - amount
            end
        end
        return true, produced
    end, options.extraSteps and { extraSteps = options.extraSteps } or nil)
end

function Crafting:GetJob(target)
    return self.Jobs[target]
end

function Crafting:Start(target, recipeId, batches)
    if self.Jobs[target] then
        return false, "You are already crafting."
    end
    local recipe, station = self:CheckStart(target, recipeId, batches)
    if not recipe then
        return false, station
    end
    local now = CurTime()
    self.Jobs[target] = {
        recipeId = recipeId,
        recipe = recipe,
        station = station,
        batches = batches,
        completed = 0,
        batchStartedAt = now,
        batchEndsAt = now + recipe.craftTime
    }
    self:SendState(target, true, "Crafting " .. recipe.name .. "...")
    return true, "Crafting " .. recipe.name .. "..."
end

function Crafting:Cancel(target, reason, ok)
    local job = self.Jobs[target]
    if not job then
        return false, "You are not crafting anything."
    end
    self.Jobs[target] = nil
    local message = reason or "Crafting cancelled."
    if job.completed > 0 then
        message = message .. " " .. job.completed .. " of " .. job.batches .. " finished."
    end
    self:SendState(target, ok == true, message)
    return true, message
end

// Why an active job can no longer continue, or nil.
function Crafting:InterruptReason(target, job)
    if not IsValid(target) then return "The crafter left." end
    if target.Alive and not target:Alive() then return "Crafting stopped: you died." end
    if not Service:CanAccessStash(target) then return "Crafting stopped: you left the den." end
    if StaticData:GetRecipe(job.recipeId) ~= job.recipe then return "Crafting stopped: that recipe changed." end
    if not IsValid(job.station) then return "Crafting stopped: the crafting station is gone." end
    if not self:IsStationInRange(target, job.station) then return "Crafting stopped: you moved away from the station." end
    local unmet = self:UnmetRequirements(target, job.recipe)
    if #unmet > 0 then return "Crafting stopped: " .. unmet[1] end
end

// Advances one job to `now` (CurTime). Completes at most one batch per call.
function Crafting:Advance(target, now)
    local job = self.Jobs[target]
    if not job then return end
    local interrupted = self:InterruptReason(target, job)
    if interrupted then
        if IsValid(target) then
            self:Cancel(target, interrupted)
        else
            self.Jobs[target] = nil
        end
        return
    end
    if now < job.batchEndsAt then return end

    local crafted, result = self:CraftBatch(target, job.recipe)
    if self.Jobs[target] ~= job then return end
    if not crafted then
        self:Cancel(target, "Crafting stopped: " .. tostring(result))
        return
    end
    job.completed = job.completed + 1
    if job.completed >= job.batches then
        self.Jobs[target] = nil
        self:SendState(target, true, "Crafted " .. job.recipe.name .. (job.batches > 1 and (" x" .. job.batches) or "") .. ".")
        return
    end
    job.batchStartedAt = now
    job.batchEndsAt = now + job.recipe.craftTime
    self:SendState(target, true)
end

function Crafting:Tick(now)
    now = now or CurTime()
    for target in pairs(table.Copy(self.Jobs)) do
        self:Advance(target, now)
    end
end

timer.Create("ZM.Crafting.Tick", Crafting.TickInterval, 0, function()
    Crafting:Tick()
end)

// State for the crafting window: every recipe with its requirement/ingredient status, plus the active job.
function Crafting:BuildState(target)
    local registry = StaticData:GetRegistry()
    local inDen = Service:CanAccessStash(target)
    local state = { recipeVersion = registry and registry.recipeVersion, inDen = inDen, recipes = {}, maxBatches = self.MaximumBatches }
    for recipeId, recipe in SortedPairs(registry and registry.recipes or {}) do
        if recipe.service then continue end
        local entry = {
            id = recipeId, name = recipe.name, category = recipe.category, station = recipe.station,
            craftTime = recipe.craftTime, levelRequirement = recipe.levelRequirement, freshness = recipe.freshness,
            unmet = self:UnmetRequirements(target, recipe), ingredients = {}, results = {},
            stationInRange = inDen and self:FindStation(target, recipe.station) ~= nil or false
        }
        for _, stack in ipairs(recipe.ingredients) do
            table.insert(entry.ingredients, { item = stack.item, count = stack.count, have = self:CountAvailable(target, stack.item) })
        end
        for _, stack in ipairs(recipe.results) do
            table.insert(entry.results, { item = stack.item, count = stack.count })
        end
        entry.maxBatches = self:MaxBatches(target, recipe)
        entry.canCraft = inDen and entry.stationInRange and #entry.unmet == 0 and entry.maxBatches > 0
        table.insert(state.recipes, entry)
    end
    local job = self.Jobs[target]
    if job then
        state.active = {
            recipeId = job.recipeId, name = job.recipe.name, batches = job.batches, completed = job.completed,
            batchStartedAt = job.batchStartedAt, batchEndsAt = job.batchEndsAt
        }
    end
    return state
end

function Crafting:SendState(target, ok, message)
    if not IsValid(target) or not target.IsPlayer or not target:IsPlayer() then return end
    local state = self:BuildState(target)
    state.ok = ok ~= false
    state.message = message
    net.Start("ZM.CraftingState")
        net.WriteString(util.TableToJSON(state, false) or "{}")
    net.Send(target)
end

// Validates and runs one client crafting request. The client names an action, recipe, and count only.
function Crafting:HandleRequest(target, request)
    if type(request) ~= "table" or type(request.action) ~= "string" then
        return false, "Invalid request."
    end
    local now = CurTime()
    if target.ZM_NextCraftingRequestAt and now < target.ZM_NextCraftingRequestAt then
        return false, "Slow down."
    end
    target.ZM_NextCraftingRequestAt = now + self.RequestCooldown
    if request.action == "open" then
        return true
    elseif request.action == "start" then
        return self:Start(target, request.recipeId, tonumber(request.count))
    elseif request.action == "cancel" then
        return self:Cancel(target, "Crafting cancelled.", true)
    end
    return false, "Unknown action."
end

net.Receive("ZM.CraftingRequest", function(length, target)
    if not IsValid(target) or length > 2048 then return end
    local request = util.JSONToTable(net.ReadString())
    local ok, message = Crafting:HandleRequest(target, request)
    // Successful starts and cancels already sent their state.
    if not ok or (type(request) == "table" and request.action == "open") then
        Crafting:SendState(target, ok, message)
    end
end)

hook.Add("PlayerDeath", "ZM.Crafting.CancelOnDeath", function(victim)
    if Crafting.Jobs[victim] then
        Crafting:Cancel(victim, "Crafting stopped: you died.")
    end
end)

hook.Add("PlayerDisconnected", "ZM.Crafting.CancelOnDisconnect", function(target)
    Crafting.Jobs[target] = nil
end)

// Admin/bridge commands acting on the first connected human.
local firstHuman = ZM_Util.FirstHuman

local function craftingReport(target, command, ok, message)
    if not (ZM_DevConsole and ZM_DevConsole.Report) then return end
    local state = Crafting:BuildState(target)
    state.command = command
    state.ok = ok
    state.message = message
    state.rows = target.ZM_Inventory and Service.ToRows(target.ZM_Inventory) or nil
    state.stations = {}
    for tag, className in pairs(StaticData.CraftingStations) do
        for _, station in ipairs(ents.FindByClass(className)) do
            local trace = util.TraceLine({start = target:EyePos(), endpos = station:WorldSpaceCenter(), filter = target})
            table.insert(state.stations, {station = tag, entIndex = station:EntIndex(), model = station:GetModel(), hasPhysics = IsValid(station:GetPhysicsObject()), traceHits = trace.Entity == station, distance = math.floor(target:GetPos():Distance(station:GetPos())), inRange = Crafting:IsStationInRange(target, station)})
        end
    end
    ZM_DevConsole:Report("crafting", state)
end

local function runCraftingCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    if not target then return false, "no target player" end
    local ok, message = true, nil
    if command == "zn_craft" then
        ok, message = Crafting:Start(target, arguments[1], tonumber(arguments[2]) or 1)
    elseif command == "zn_craft_cancel" then
        ok, message = Crafting:Cancel(target, "Crafting cancelled.", true)
    elseif command == "zn_dev_craft_finish" then
        // Development: finishes the current batch now instead of waiting for its craft time.
        local job = Crafting.Jobs[target]
        if not job then
            ok, message = false, "You are not crafting anything."
        else
            job.batchEndsAt = CurTime()
            Crafting:Advance(target, CurTime())
            local after = Crafting.Jobs[target]
            message = after and (after.completed .. " of " .. after.batches .. " finished") or "job complete or stopped"
        end
    elseif command == "zn_dev_goto_station" then
        // Development: stands the player in front of the nearest workbench so live craft checks can run.
        local nearest, nearestDistance
        for _, station in ipairs(ents.FindByClass(StaticData.CraftingStations.workbench)) do
            local distance = target:GetPos():DistToSqr(station:GetPos())
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = station, distance
            end
        end
        local spawned = false
        if not IsValid(nearest) then
            // Den maps do not author a workbench yet, so spawn a temporary frozen one in front of the player.
            local forward = target:GetForward()
            forward.z = 0
            forward:Normalize()
            nearest = ents.Create(StaticData.CraftingStations.workbench)
            if IsValid(nearest) then
                nearest:SetPos(target:GetPos() + forward * 72 + Vector(0, 0, 20))
                nearest:SetAngles(Angle(0, target:EyeAngles().y + 180, 0))
                nearest:Spawn()
                local physics = nearest:GetPhysicsObject()
                if IsValid(physics) then physics:EnableMotion(false) end
                spawned = true
            end
        end
        if not IsValid(nearest) then
            ok, message = false, "could not create a crafting station"
        elseif spawned then
            message = "spawned temporary station " .. nearest:EntIndex() .. " in front of the player"
        else
            local standAt = nearest:GetPos() + nearest:GetForward() * 48 + Vector(0, 0, 4)
            target:SetPos(standAt)
            target:SetEyeAngles((nearest:GetPos() - standAt):Angle())
            message = "moved next to station " .. nearest:EntIndex()
        end
    end
    local line = "[ZombieSim] " .. command .. ": " .. tostring(message or (ok and "ok" or "failed"))
    ZM_Util.Print(caller, line)
    craftingReport(target, command, ok, message)
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_crafting = "Reports recipe eligibility and the active craft job for the target player.",
    zn_craft = "zn_craft <recipeId> [count]: starts a craft job at a nearby station in the den.",
    zn_craft_cancel = "Cancels the target player's active craft job.",
    zn_dev_craft_finish = "Development: completes the active craft batch immediately (all normal checks still apply).",
    zn_dev_goto_station = "Development: moves the target player in front of the nearest crafting station, spawning a temporary one if the map has none."
}, runCraftingCommand)
