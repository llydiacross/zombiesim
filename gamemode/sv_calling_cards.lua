// Account/profile unlocks and per-survivor selections; clients never supply ownership or prices.
ZM_CallingCardService = ZM_CallingCardService or {}
local Service = ZM_CallingCardService
local Cards = ZM_CallingCards

util.AddNetworkString("ZM.CallingCardRequest")
util.AddNetworkString("ZM.CallingCardState")

local categories = { "background", "detail" }
local entriesPerMessage = 32

function Service:Identity(target)
    if not IsValid(target) or not target.SteamID or (target.IsBot and target:IsBot())
        or target.ZM_PersistentStateLoaded ~= true then
        return nil, "An active survivor is required."
    end
    local account = target:SteamID()
    local profile = ZM_Util.ProfileFor(target)
    local character, characterError = ZM_Util.CharacterKeyFor(target)
    if type(account) ~= "string" or not string.match(account, "^STEAM_[0-5]:[01]:%d+$")
        or type(profile) ~= "string" or not string.match(profile, "^[a-z0-9_-]+$")
        or type(character) ~= "string" or character == "" then
        return nil, "Invalid calling-card owner: " .. tostring(characterError or "account, profile or survivor")
    end
    return { account = account, profile = profile, character = character }
end

function Service:Catalogue()
    local registry = ZM_StaticData:GetRegistry()
    if not registry or not registry.callingCards then return nil, "The calling-card catalogue is unavailable." end
    return registry.callingCards
end

function Service:Snapshot(target)
    local identity, identityError = self:Identity(target)
    if not identity then return nil, identityError end
    local catalogue, catalogueError = self:Catalogue()
    if not catalogue then return nil, catalogueError end
    local rows, readError = ZM_GetCallingCardUnlocks(identity.account, identity.profile)
    if not rows then return nil, "Could not read calling-card unlocks: " .. tostring(readError) end
    local selection, selectionError = ZM_GetCallingCardSelection(identity.character, identity.profile)
    if not selection then return nil, "Could not read calling-card selections: " .. tostring(selectionError) end
    local owned = { background_default = true, detail_default = true }
    for _, row in ipairs(rows) do
        local category = Cards.Category(row.cardId)
        if not category then return nil, "A stored calling-card unlock has an invalid ID." end
        local card, status = Cards.Resolve(catalogue, row.cardId, category)
        if status == "available" or status == "alias" then owned[card.id] = true end
    end
    for _, category in ipairs(categories) do
        local id = selection[category]
        if Cards.Category(id) ~= category then return nil, "A stored " .. category .. " selection is invalid." end
        local card, status = Cards.Resolve(catalogue, id, category)
        if not card or status == "invalid_alias" or status == "catalogue_unavailable" then
            return nil, "Could not resolve the stored " .. category .. " selection."
        end
        if (status == "available" or status == "alias") and not owned[card.id] then
            return nil, "The stored " .. category .. " selection is not owned."
        end
    end
    return { identity = identity, catalogue = catalogue, owned = owned, selection = selection }
end

function Service:Reset(target)
    target:SetNWString("ZM_CallingCardBackground", "background_default")
    target:SetNWString("ZM_CallingCardDetail", "detail_default")
end

function Service:Publish(target, snapshot)
    target:SetNWString("ZM_CallingCardBackground", snapshot.selection.background)
    target:SetNWString("ZM_CallingCardDetail", snapshot.selection.detail)
end

function Service:Load(target)
    local snapshot, snapshotError = self:Snapshot(target)
    if not snapshot then
        self:Reset(target)
        return false, snapshotError
    end
    self:Publish(target, snapshot)
    return true
end

function Service:Select(target, category, id)
    local snapshot, snapshotError = self:Snapshot(target)
    if not snapshot then return false, snapshotError end
    local card = snapshot.catalogue.byId[id]
    if not card or card.category ~= category then return false, "That calling-card design is unavailable." end
    if not snapshot.owned[card.id] then return false, "That calling-card design is locked." end
    local selection = { background = snapshot.selection.background, detail = snapshot.selection.detail }
    selection[category] = card.id
    local saved, saveError = ZM_CommitWrites(snapshot.identity.profile, {
        { kind = "callingCardSelection", steamid = snapshot.identity.character,
            background = selection.background, detail = selection.detail }
    })
    if not saved then return false, "Could not save your calling-card selection: " .. tostring(saveError) end
    snapshot.selection = selection
    self:Publish(target, snapshot)
    return true, "Calling-card selection saved."
end

// Server-only reward API; a repeated reward never removes ownership or creates a duplicate.
function Service:GrantReward(target, id, reason)
    local snapshot, snapshotError = self:Snapshot(target)
    if not snapshot then return false, snapshotError end
    if type(reason) ~= "string" or reason == "" or #reason > 64 then return false, "A reward reason is required." end
    local category = Cards.Category(id)
    if not category then return false, "Invalid calling-card reward ID." end
    local card, status = Cards.Resolve(snapshot.catalogue, id, category)
    if not card or (status ~= "available" and status ~= "alias") then
        return false, "The calling-card reward is unavailable."
    end
    if card.questReward ~= true then return false, "That calling-card design is not a quest reward." end
    if snapshot.owned[card.id] then return true, "Calling card already owned." end
    local saved, saveError = ZM_CommitWrites(snapshot.identity.profile, {
        { kind = "callingCardUnlock", steamid = snapshot.identity.character, account = snapshot.identity.account,
            cardId = card.id, source = reason }
    })
    if not saved then return false, "Could not save the calling-card reward: " .. tostring(saveError) end
    if ZM_Util.IsPlayerEntity(target) then self:SendState(target, true, "Calling card unlocked.") end
    return true, "Calling card unlocked."
end

function Service:SendState(target, ok, message, requestId)
    if not ZM_Util.IsPlayerEntity(target) then return end
    local snapshot, snapshotError = self:Snapshot(target)
    local ids = {}
    if snapshot then
        for id in pairs(snapshot.owned) do ids[#ids + 1] = id end
        table.sort(ids)
    else
        ok, message = false, snapshotError
    end
    target.ZM_CallingCardSerial = ((target.ZM_CallingCardSerial or 0) % 4294967294) + 1
    local responseId = type(requestId) == "string" and #requestId <= 40
        and string.match(requestId, "^[%w_-]+$") and requestId or ""
    local total = math.max(1, math.ceil(#ids / entriesPerMessage))
    for part = 1, total do
        local first = (part - 1) * entriesPerMessage + 1
        local last = math.min(part * entriesPerMessage, #ids)
        net.Start("ZM.CallingCardState")
            net.WriteUInt(target.ZM_CallingCardSerial, 32)
            net.WriteUInt(part, 16)
            net.WriteUInt(total, 16)
            net.WriteBool(ok ~= false and snapshot ~= nil)
            net.WriteString(string.sub(tostring(message or ""), 1, 512))
            net.WriteString(responseId)
            net.WriteString(snapshot and snapshot.selection.background or "")
            net.WriteString(snapshot and snapshot.selection.detail or "")
            net.WriteUInt(math.max(0, last - first + 1), 8)
            for index = first, last do net.WriteString(ids[index]) end
        net.Send(target)
    end
end

net.Receive("ZM.CallingCardRequest", function(length, target)
    if not IsValid(target) then return end
    if length > 4096 then
        Service:SendState(target, false, "Calling-card request is too large.")
        return
    end
    local request = util.JSONToTable(net.ReadString())
    if type(request) ~= "table" or type(request.requestId) ~= "string" or #request.requestId > 40
        or not string.match(request.requestId, "^[%w_-]+$") then
        Service:SendState(target, false, "Invalid calling-card request.")
        return
    end
    local now = CurTime()
    if target.ZM_NextCallingCardRequestAt and now < target.ZM_NextCallingCardRequestAt then
        Service:SendState(target, false, "Slow down.", request.requestId)
        return
    end
    target.ZM_NextCallingCardRequestAt = now + 0.25
    if request.action == "list" then
        Service:SendState(target, true, nil, request.requestId)
    elseif request.action == "select" then
        local ok, message = Service:Select(target, request.category, request.id)
        Service:SendState(target, ok, message, request.requestId)
    else
        Service:SendState(target, false, "Unknown calling-card request.", request.requestId)
    end
end)
