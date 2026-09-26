// Server-only world loot spots: matching map props become lootable, players search them, and the server offers one
// rolled item that is granted only on acceptance. Spot state is stored per profile and logical cell in SQLite.
ZM_LootSpots = ZM_LootSpots or {}
local Spots = ZM_LootSpots
local Generation = ZM_ItemGeneration

util.AddNetworkString("ZM.LootSearch")
util.AddNetworkString("ZM.LootOffer")
util.AddNetworkString("ZM.LootOfferResponse")
util.AddNetworkString("ZM.LootOfferResult")

Spots.RefreshSeconds = 300
Spots.SearchSeconds = 2
Spots.UseRange = 110
Spots.OfferRange = 200
Spots.OfferSeconds = 120
Spots.PresenceInterval = 15
Spots.HighlightColor = Color(255, 225, 110)
Spots.DeclinedColor = Color(145, 145, 145)

// Map-placed entities keep their MapCreationID across loads of the same map; runtime-spawned props are never spots.
function Spots.GetSpotKey(entity)
    local id = entity.MapCreationID and entity:MapCreationID() or -1
    if not id or id < 0 then
        return nil
    end
    return "m" .. id
end

// Returns loot candidates { key, rule, entity } for every map prop that matches an entity_loot rule.
function Spots:FindCandidates()
    local candidates = {}
    for _, entity in ipairs(ents.GetAll()) do
        if IsValid(entity) then
            local rule = ZM_StaticData:GetEntityLootRule(entity:GetClass(), entity:GetModel())
            local key = rule and self.GetSpotKey(entity)
            if key then
                table.insert(candidates, { key = key, rule = rule, entity = entity })
            end
        end
    end
    return candidates
end

function Spots.ShouldRegenerate(cellRow, now)
    return cellRow == nil or now - (tonumber(cellRow.lastPresentAt) or 0) >= Spots.RefreshSeconds
end

local function readItem(value)
    if type(value) ~= "string" or value == "" or value == "NULL" then
        return nil
    end
    return util.JSONToTable(value)
end

// Loads or re-rolls the spots for a cell. Returns the cell state or nil and a reason.
// candidates: { key, rule, entity }; options: { now, rng, danger, forceRegenerate }.
function Spots:LoadCell(profile, cellId, candidates, options)
    local now = options.now or os.time()
    local cellRow, cellError = ZM_GetLootCell(profile, cellId)
    if cellError then
        return nil, cellError
    end

    local cell = { profile = profile, cellId = cellId, danger = options.danger or 0, spots = {}, spotsByEntity = {} }
    local byKey = {}
    for _, candidate in ipairs(candidates) do
        byKey[candidate.key] = candidate
    end

    if options.forceRegenerate or self.ShouldRegenerate(cellRow, now) then
        local rng = options.rng or Generation.NewRng()
        local rows = {}
        for _, candidate in ipairs(candidates) do
            if ZM_Loot.RollActivation(candidate.rule, rng) then
                table.insert(rows, { key = candidate.key, state = "available" })
            end
        end
        local saved, saveError = ZM_ReplaceLootCell(profile, cellId, now, now, rows)
        if not saved then
            return nil, saveError
        end
        cell.regenerated = true
        for _, row in ipairs(rows) do
            local candidate = byKey[row.key]
            cell.spots[row.key] = { key = row.key, state = row.state, rule = candidate.rule, entity = candidate.entity }
        end
    else
        local rows, rowsError = ZM_GetLootSpots(profile, cellId)
        if not rows then
            return nil, rowsError
        end
        ZM_TouchLootCell(profile, cellId, now)
        for _, row in ipairs(rows) do
            local candidate = byKey[row.spotKey]
            if candidate then
                cell.spots[row.spotKey] = { key = row.spotKey, state = row.state, item = readItem(row.item), rule = candidate.rule, entity = candidate.entity }
            end
        end
    end

    for _, spot in pairs(cell.spots) do
        if spot.entity then
            cell.spotsByEntity[spot.entity] = spot
        end
    end
    return cell
end

local function isRealPlayer(target)
    return IsValid(target) and target.IsPlayer and target:IsPlayer()
end

function Spots:UpdateVisual(spot)
    local entity = spot.entity
    if not IsValid(entity) or not entity.SetNWBool then
        return
    end
    local active = spot.state == "available" or spot.state == "declined"
    if active and not spot.originalColor then
        spot.originalColor = entity:GetColor()
        entity:SetColor(spot.state == "declined" and self.DeclinedColor or self.HighlightColor)
    elseif active and spot.originalColor then
        entity:SetColor(spot.state == "declined" and self.DeclinedColor or self.HighlightColor)
    elseif not active and spot.originalColor then
        entity:SetColor(spot.originalColor)
        spot.originalColor = nil
    end
    entity:SetNWBool("ZM_LootSpot", active)
    entity:SetNWString("ZM_LootSpotState", spot.state or "")
end

function Spots:RegisterRuntimeSpot(entity, item, key)
    if not self.Cell or not IsValid(entity) or type(key) ~= "string" or type(item) ~= "table" then
        return nil, "runtime loot spot requires an active cell, entity, key, and item"
    end
    local spot = { key = key, state = "available", item = item, entity = entity, runtime = true }
    self.Cell.spots[key] = spot
    self.Cell.spotsByEntity[entity] = spot
    self:UpdateVisual(spot)
    return spot
end

function Spots:Activate(cell)
    self.Cell = cell
    for _, spot in pairs(cell.spots) do
        self:UpdateVisual(spot)
    end
end

function Spots.GetDistance(target, spot)
    local entity = spot.entity
    if not IsValid(entity) then
        return math.huge
    end
    local center = target:WorldSpaceCenter()
    return center:Distance(entity:NearestPoint(center))
end

local function send(target, name, writer)
    if not isRealPlayer(target) then
        return
    end
    net.Start(name)
    writer()
    net.Send(target)
end

local function sendResult(target, ok, message)
    send(target, "ZM.LootOfferResult", function()
        net.WriteBool(ok)
        net.WriteString(message or "")
    end)
end

function Spots:ClaimExpired(spot, now)
    local claim = spot.claim
    if not claim then
        return true
    end
    if not IsValid(claim.player) or not claim.player:Alive() or now >= claim.expiresAt then
        spot.claim = nil
        return true
    end
    return false
end

// Starts a search. Returns true or false and a player-facing reason.
function Spots:BeginSearch(target, spot, now)
    now = now or CurTime()
    if not self.Cell or self.Cell.spots[spot.key] ~= spot then
        return false, "That is not a loot spot."
    end
    if spot.state ~= "available" and spot.state ~= "declined" then
        return false, "There is nothing left here."
    end
    if not target:Alive() then
        return false, "You are dead."
    end
    if target.ZM_LootSearch or target.ZM_LootOffer then
        return false, "You are already searching."
    end
    if not self:ClaimExpired(spot, now) and spot.claim.player ~= target then
        return false, "Someone else is searching this."
    end
    if self.GetDistance(target, spot) > self.UseRange then
        return false, "You are too far away."
    end
    spot.claim = { player = target, expiresAt = now + self.SearchSeconds + self.OfferSeconds }
    target.ZM_LootSearch = { key = spot.key, finishAt = now + self.SearchSeconds }
    send(target, "ZM.LootSearch", function()
        net.WriteBool(true)
        net.WriteFloat(self.SearchSeconds)
    end)
    return true
end

function Spots:CancelSearch(target, reason)
    local search = target.ZM_LootSearch
    if not search then
        return
    end
    target.ZM_LootSearch = nil
    local spot = self.Cell and self.Cell.spots[search.key]
    if spot and spot.claim and spot.claim.player == target then
        spot.claim = nil
    end
    send(target, "ZM.LootSearch", function()
        net.WriteBool(false)
        net.WriteFloat(0)
    end)
    if reason then
        sendResult(target, false, reason)
    end
end

local function offerPayload(offer, instance)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    return {
        token = offer.token,
        itemId = instance.itemId,
        name = definition and definition.name or instance.itemId,
        thumbnail = definition and definition.thumbnail or instance.itemId,
        count = instance.count,
        level = instance.level,
        mastercraft = instance.mastercraft == true,
        attributes = instance.attributes,
        value = ZM_Items:GetInstanceValue(instance)
    }
end

// Finishes a search: rolls the spot's item once (kept if declined), stores it, and issues a single-use offer.
function Spots:CompleteSearch(target, now, rng)
    now = now or CurTime()
    local search = target.ZM_LootSearch
    local spot = search and self.Cell and self.Cell.spots[search.key]
    target.ZM_LootSearch = nil
    if not spot or (spot.state ~= "available" and spot.state ~= "declined") or not spot.claim or spot.claim.player ~= target then
        return nil, "The search was interrupted."
    end
    if self.GetDistance(target, spot) > self.UseRange then
        spot.claim = nil
        return nil, "You moved too far away."
    end
    if not spot.item then
        local instance, reason = ZM_Loot:RollEntityLoot(spot.rule, {
            danger = self.Cell.danger,
            playerLevel = target.GetLevel and target:GetLevel() or 1,
            rng = rng
        })
        if not instance then
            spot.claim = nil
            return nil, "Nothing useful here: " .. tostring(reason)
        end
        local saved, saveError = ZM_SetLootSpot(self.Cell.profile, self.Cell.cellId, spot.key, "available", instance)
        if not saved then
            spot.claim = nil
            return nil, "Could not save the loot: " .. tostring(saveError)
        end
        spot.item = instance
    end
    local offer = { token = string.format("%08x%08x", math.random(0, 0x7FFFFFFF), math.random(0, 0x7FFFFFFF)), key = spot.key, expiresAt = now + self.OfferSeconds }
    target.ZM_LootOffer = offer
    spot.claim.expiresAt = offer.expiresAt
    local payload = offerPayload(offer, spot.item)
    send(target, "ZM.LootOffer", function()
        net.WriteString(util.TableToJSON(payload, false) or "{}")
    end)
    return payload
end

// Accepts or declines an offer. The token is single-use; declining keeps the same item on the spot.
function Spots:RespondOffer(target, token, accept, now)
    now = now or CurTime()
    local offer = target.ZM_LootOffer
    if not offer or type(token) ~= "string" or token ~= offer.token then
        return false, "That offer is no longer valid."
    end
    target.ZM_LootOffer = nil
    local spot = self.Cell and self.Cell.spots[offer.key]
    local function release()
        if spot and spot.claim and spot.claim.player == target then
            spot.claim = nil
        end
    end
    if not spot or spot.state ~= "available" or not spot.item then
        release()
        return false, "There is nothing left here."
    end
    if now >= offer.expiresAt then
        release()
        return false, "That offer expired."
    end
    if not accept then
        release()
        spot.state = "declined"
        if spot.runtime ~= true then
            ZM_SetLootSpot(self.Cell.profile, self.Cell.cellId, spot.key, "declined", spot.item)
        end
        self:UpdateVisual(spot)
        return true, "declined"
    end
    if not target:Alive() or self.GetDistance(target, spot) > self.OfferRange then
        release()
        return false, "You moved too far away."
    end

    local given, giveError = target:GiveItemInstance(spot.item)
    if not given then
        release()
        return false, "Could not take the item: " .. tostring(giveError)
    end
    local saved, saveError = ZM_SetLootSpot(self.Cell.profile, self.Cell.cellId, spot.key, "looted", nil)
    if not saved then
        print("[ZombieSim] Loot spot " .. spot.key .. " could not be saved as looted: " .. tostring(saveError))
    end
    spot.state = "looted"
    spot.item = nil
    release()
    self:UpdateVisual(spot)
    if spot.runtime and IsValid(spot.entity) then
        spot.entity:Remove()
    end
    return true, "accepted"
end

function Spots:ReleasePlayer(target)
    target.ZM_LootSearch = nil
    target.ZM_LootOffer = nil
    for _, spot in pairs(self.Cell and self.Cell.spots or {}) do
        if spot.claim and spot.claim.player == target then
            spot.claim = nil
        end
    end
end

function Spots:FindNearestSpot(target)
    if not self.Cell then
        return nil
    end
    local nearest, nearestDistance = nil, self.UseRange
    for _, entity in ipairs(ents.FindInSphere(target:WorldSpaceCenter(), self.UseRange + 150)) do
        local spot = self.Cell.spotsByEntity[entity]
        if spot and (spot.state == "available" or spot.state == "declined") then
            local distance = self.GetDistance(target, spot)
            if distance <= nearestDistance then
                nearest, nearestDistance = spot, distance
            end
        end
    end
    return nearest
end

local function baseMapName(path)
    return string.lower(string.match(path or "", "([^/]+)$") or path or "")
end

// Initializes the cell's spots the first time a loaded player is on their own city-cell map.
function Spots:OnPlayerReady(target)
    if self.Cell or not isRealPlayer(target) or target.ZM_PersistentStateLoaded ~= true then
        return
    end
    if type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" then
        return
    end
    local cell = target:GetWorldCell()
    if not cell or (ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell)) then
        return
    end
    if baseMapName(ZM_World:GetMapPath(cell)) ~= baseMapName(game.GetMap()) then
        return
    end
    local loaded, loadError = self:LoadCell(ZM_World.ActiveProfile, cell.id, self:FindCandidates(), { danger = ZM_World:GetDangerIntensity(cell) or 0 })
    if not loaded then
        print("[ZombieSim] Loot spots could not be loaded: " .. tostring(loadError))
        return
    end
    self:Activate(loaded)
    local active = 0
    for _, spot in pairs(loaded.spots) do
        if spot.state == "available" then
            active = active + 1
        end
    end
    print(string.format("[ZombieSim] Loot spots for cell %d: %d active%s.", cell.id, active, loaded.regenerated and " (re-rolled)" or ""))
end

hook.Add("KeyPress", "ZM.LootSpots.Search", function(target, key)
    if key ~= IN_USE or not isRealPlayer(target) or not Spots.Cell then
        return
    end
    local spot = Spots:FindNearestSpot(target)
    if spot then
        local started, reason = Spots:BeginSearch(target, spot)
        if not started then
            sendResult(target, false, reason)
        end
    end
end)

// Active spots are searched, not picked up or used.
hook.Add("PlayerUse", "ZM.LootSpots.BlockUse", function(_, entity)
    if Spots.Cell and Spots.Cell.spotsByEntity[entity] and Spots.Cell.spotsByEntity[entity].state == "available" then
        return false
    end
end)

hook.Add("Think", "ZM.LootSpots.Searches", function()
    if not Spots.Cell then
        return
    end
    local now = CurTime()
    for _, target in ipairs(player.GetHumans()) do
        local search = target.ZM_LootSearch
        if search then
            local spot = Spots.Cell.spots[search.key]
            if not target:Alive() or not spot or Spots.GetDistance(target, spot) > Spots.UseRange then
                Spots:CancelSearch(target, "Search interrupted.")
            elseif now >= search.finishAt then
                local offer, reason = Spots:CompleteSearch(target, now)
                if not offer then
                    sendResult(target, false, reason)
                end
            end
        elseif target.ZM_LootOffer and now >= target.ZM_LootOffer.expiresAt then
            Spots:ReleasePlayer(target)
            sendResult(target, false, "That offer expired.")
        end
    end
end)

net.Receive("ZM.LootOfferResponse", function(_, target)
    local token = net.ReadString()
    local accept = net.ReadBool()
    if not isRealPlayer(target) or #token > 32 then
        return
    end
    local ok, message = Spots:RespondOffer(target, token, accept)
    if ok and message == "accepted" then
        sendResult(target, true, "Added to your backpack.")
    elseif not ok then
        sendResult(target, false, message)
    end
end)

hook.Add("PlayerDeath", "ZM.LootSpots.ReleaseOnDeath", function(target)
    Spots:CancelSearch(target)
    Spots:ReleasePlayer(target)
end)

hook.Add("PlayerDisconnected", "ZM.LootSpots.ReleaseOnDisconnect", function(target)
    Spots:ReleasePlayer(target)
end)

timer.Create("ZM.LootSpots.Presence", Spots.PresenceInterval, 0, function()
    local cell = Spots.Cell
    if cell and #player.GetHumans() > 0 then
        ZM_TouchLootCell(cell.profile, cell.cellId, os.time())
    end
end)

hook.Add("ShutDown", "ZM.LootSpots.Presence", function()
    local cell = Spots.Cell
    if cell then
        ZM_TouchLootCell(cell.profile, cell.cellId, os.time())
    end
end)

local function reply(caller, message)
    if IsValid(caller) then
        caller:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] " .. message .. "\n")
    else
        print("[ZombieSim] " .. message)
    end
end

local function describeSpots(caller)
    local candidates = Spots:FindCandidates()
    local candidateModels = {}
    for _, candidate in ipairs(candidates) do
        local model = candidate.entity:GetClass() .. " " .. candidate.entity:GetModel()
        candidateModels[model] = (candidateModels[model] or 0) + 1
    end
    reply(caller, #candidates .. " prop(s) on this map match an entity_loot rule.")
    for model, count in SortedPairs(candidateModels) do
        reply(caller, string.format("  %3d x %s", count, model))
    end
    local cell = Spots.Cell
    if not cell then
        reply(caller, "No loot spots are loaded on this map.")
        return { loaded = false, candidates = #candidates, candidateModels = candidateModels }
    end
    local report = { loaded = true, profile = cell.profile, cellId = cell.cellId, danger = cell.danger, spots = {}, candidates = #candidates, candidateModels = candidateModels }
    reply(caller, string.format("Loot spots for %s cell %d (danger %.2f):", cell.profile, cell.cellId, cell.danger))
    for key, spot in SortedPairs(cell.spots) do
        local model = IsValid(spot.entity) and spot.entity:GetModel() or "missing entity"
        local item = spot.item and (spot.item.itemId .. " x" .. spot.item.count) or "-"
        reply(caller, string.format("  %-8s %-9s %-40s item %s%s", key, spot.state, model, item, spot.claim and " (claimed)" or ""))
        table.insert(report.spots, { key = key, state = spot.state, model = model, item = spot.item })
    end
    return report
end

local function runSpotsCommand(caller, command)
    if IsValid(caller) and not caller:IsAdmin() then
        reply(caller, command .. " must be run by an in-game admin.")
        return false, "not an admin"
    end
    if command == "zn_loot_spots_refresh" then
        local cell = Spots.Cell
        if not cell then
            reply(caller, "No loot spots are loaded on this map.")
            return false, "no loot cell"
        end
        for _, spot in pairs(cell.spots) do
            spot.state = "looted"
            Spots:UpdateVisual(spot)
        end
        local reloaded, reason = Spots:LoadCell(cell.profile, cell.cellId, Spots:FindCandidates(), { danger = cell.danger, forceRegenerate = true })
        if not reloaded then
            reply(caller, "Refresh failed: " .. tostring(reason))
            return false, reason
        end
        Spots:Activate(reloaded)
        reply(caller, "Loot spots re-rolled.")
    end
    local report = describeSpots(caller)
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("lootSpots", report)
    end
    return true
end

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
for command, help in pairs({
    zn_loot_spots = "Lists the loot spots in the current cell.",
    zn_loot_spots_refresh = "Re-rolls every loot spot in the current cell as if the refresh time had passed."
}) do
    concommand.Add(command, function(caller)
        runSpotsCommand(caller, command)
    end, nil, help)
    ZM_DevConsole.DirectCommands[command] = function()
        return runSpotsCommand(nil, command)
    end
end
