// Preview-admin-only, bounded claim/construction review with session-scoped cleanup.
ZM_ClaimReviewTest = ZM_ClaimReviewTest or {}
local Review = ZM_ClaimReviewTest
Review.TimeoutSeconds = 30 * 60
Review.TokenItemId = "itemClaimToken"
Review.HammerItemId = "weaponMeleeHammer"
Review.TimerName = "ZM.ClaimReview.AutoRollback"

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
local directCommands = ZM_DevConsole.DirectCommands

local function rowValue(value)
    return value == nil and "" or tostring(value)
end

local function itemRowSignature(row)
    return table.concat({
        rowValue(row.instanceId), rowValue(row.container), rowValue(row.slot), rowValue(row.itemId),
        rowValue(row.count), rowValue(row.level), rowValue(row.mastercraft), rowValue(row.attributes),
        rowValue(row.clip), rowValue(row.createdAt)
    }, "\31")
end

local function itemRowsSignature(rows)
    local signatures = {}
    for _, row in ipairs(rows or {}) do
        signatures[#signatures + 1] = itemRowSignature(row)
    end
    table.sort(signatures)
    return table.concat(signatures, "\30")
end

local function weaponSlotSignature(rows)
    local signatures = {}
    for _, row in ipairs(rows or {}) do
        signatures[#signatures + 1] = table.concat({
            rowValue(row.slot), rowValue(row.instanceId), rowValue(row.selected)
        }, "\31")
    end
    table.sort(signatures)
    return table.concat(signatures, "\30")
end

local function claimIdentity(row)
    return table.concat({
        rowValue(row.cellId), rowValue(row.tileX), rowValue(row.tileY), rowValue(row.owner),
        rowValue(row.account), rowValue(row.createdAt)
    }, "\31")
end

local function claimRowsSignature(rows, excludedTileX, excludedTileY)
    local signatures = {}
    for _, row in ipairs(rows or {}) do
        if row.tileX ~= excludedTileX or row.tileY ~= excludedTileY then
            signatures[#signatures + 1] = claimIdentity(row)
        end
    end
    table.sort(signatures)
    return table.concat(signatures, "\30")
end

local function slotsWithoutReviewHammer(currentRows, baselineRows, hammerId)
    local retained, seenSlots, seenInstances = {}, {}, {}
    local previousSelectedId
    for _, row in ipairs(baselineRows or {}) do
        if tonumber(row.selected) == 1 then previousSelectedId = row.instanceId end
    end
    local temporarySelected, selectedCount = false, 0
    for _, row in ipairs(currentRows or {}) do
        local slot, selected = tonumber(row.slot), tonumber(row.selected)
        if not slot or slot < 1 or slot > 3 or slot ~= math.floor(slot) or seenSlots[slot]
            or (selected ~= 0 and selected ~= 1)
            or (row.instanceId ~= nil and (type(row.instanceId) ~= "string" or row.instanceId == ""))
            or (selected == 1 and not row.instanceId)
            or (row.instanceId and seenInstances[row.instanceId]) then
            return nil, "The current weapon slots are invalid; refusing cleanup."
        end
        seenSlots[slot] = true
        if row.instanceId then seenInstances[row.instanceId] = true end
        if selected == 1 then selectedCount = selectedCount + 1 end
        if row.instanceId == hammerId then
            temporarySelected = selected == 1
            retained[#retained + 1] = { slot = slot, selected = 0 }
        else
            retained[#retained + 1] = { slot = slot, instanceId = row.instanceId, selected = selected }
        end
    end
    if selectedCount > 1 then return nil, "The current weapon slots have multiple selections; refusing cleanup." end
    if temporarySelected and previousSelectedId then
        for _, row in ipairs(retained) do
            if row.instanceId == previousSelectedId then
                row.selected = 1
                break
            end
        end
    end
    return retained
end

local function selectedWeaponClass(target, rows)
    local selectedId
    for _, row in ipairs(rows or {}) do
        if tonumber(row.selected) == 1 then
            if selectedId or type(row.instanceId) ~= "string" or row.instanceId == "" then
                return nil, "The saved selected weapon slot is invalid."
            end
            selectedId = row.instanceId
        end
    end
    if not selectedId then return nil end
    for _, weapon in ipairs(target:GetWeapons()) do
        if IsValid(weapon) and weapon.GetItemInstanceId and weapon:GetItemInstanceId() == selectedId then
            return weapon:GetClass()
        end
    end
    return nil, "The selected weapon is no longer available."
end

local function getTargetClaims(profile, cellId, tileX, tileY)
    local rows, readError = ZM_GetCellClaims(profile, cellId)
    if not rows then return nil, readError end
    local targetRow
    for _, row in ipairs(rows) do
        if row.tileX == tileX and row.tileY == tileY then
            if targetRow then return nil, "multiple claim rows exist for the review tile" end
            targetRow = row
        end
    end
    return rows, nil, targetRow
end

local function hasClaimTile(cellId, tileX, tileY)
    for _, tile in ipairs(ZM_World:GetClaimTiles(cellId) or {}) do
        if tile.x == tileX and tile.y == tileY then return true end
    end
    return false
end

local function hasOwnedConstruction(target)
    for _, entity in pairs(ZM_Construction.SlotRegistry or {}) do
        if IsValid(entity) and ZM_Construction:OwnsPiece(target, entity) then return true end
    end
    return false
end

local function backpackSlots(rows)
    local capacity = ZM_Items and ZM_Items.ContainerCapacity and ZM_Items.ContainerCapacity.backpack
    if not tonumber(capacity) then return nil, "Backpack capacity is unavailable." end
    local occupied = {}
    for _, row in ipairs(rows or {}) do
        if row.container == "backpack" then occupied[tonumber(row.slot)] = true end
    end
    local available = {}
    for slot = 1, tonumber(capacity) do
        if not occupied[slot] then available[#available + 1] = slot end
        if #available == 2 then return available end
    end
    return nil, "Two empty backpack slots are required for temporary review items."
end

local function temporaryItemRow(instance, slot)
    if type(instance) ~= "table" or type(instance.instanceId) ~= "string" or instance.instanceId == ""
        or type(instance.itemId) ~= "string" or instance.itemId == "" then
        return nil, "Item generation returned an invalid review item."
    end
    local attributes
    if instance.attributes ~= nil then
        attributes = util.TableToJSON(instance.attributes, false)
        if type(attributes) ~= "string" then return nil, "Could not encode temporary item attributes." end
    end
    return {
        instanceId = instance.instanceId,
        container = "backpack",
        slot = slot,
        itemId = instance.itemId,
        count = tonumber(instance.count) or 1,
        level = tonumber(instance.level) or 1,
        mastercraft = instance.mastercraft and 1 or 0,
        attributes = attributes,
        clip = tonumber(instance.clip) or 0,
        createdAt = tonumber(instance.createdAt) or os.time()
    }
end

local function report(state, details)
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("claimConstructionReview", {
            state = state,
            cellId = details.cellId,
            tileX = details.tileX,
            tileY = details.tileY,
            reason = details.reason,
            profile = details.profile,
            worldDataPath = details.worldDataPath,
            map = details.map,
            radiation = details.radiation,
            claimTiles = details.claimTiles
        })
    end
end

function Review:Start(target, tileX, tileY)
    if self.Active then return false, "A claim review session is already active." end
    if not IsValid(target) or not target:IsPlayer() or not target:IsAdmin()
        or target.ZM_PersistentStateLoaded ~= true or not target:Alive() then
        return false, "An alive, loaded preview admin is required."
    end
    if ZM_World.ActiveProfile ~= "preview" then return false, "Claim review is restricted to the preview profile." end
    local humans = player.GetHumans()
    if #humans ~= 1 or humans[1] ~= target then return false, "Claim review requires this admin to be the only connected human." end
    if target:Health() < target:GetMaxHealth() then return false, "Claim review requires full health." end
    local identity, identityError = ZM_ClaimService:Identity(target)
    if not identity then return false, identityError end
    local cell, cellError = ZM_ClaimService:CurrentCell(target)
    if not cell then return false, cellError end
    local radiation = tonumber(ZM_World:GetRadiationIntensity(cell))
    if radiation == nil or radiation > 0 then return false, "Choose a zero-radiation preview city cell for this review." end
    if not ZM_Util.IsWholeNumber(tileX, -2, 2) or not ZM_Util.IsWholeNumber(tileY, -2, 2)
        or not hasClaimTile(cell.id, tileX, tileY) then
        return false, "Choose an exported claimable tile offset from -2 through 2."
    end
    if not ZM_ClaimService:IsWithinClaimReach(target:GetPos(), tileX, tileY) then
        return false, "Move closer to the review tile before starting."
    end
    if hasOwnedConstruction(target) then return false, "Remove existing construction pieces before starting the review." end
    if target.ZM_ConstructionProtected == true then return false, "Turn build mode off before starting the review." end

    local baselineItems, itemError = ZM_GetExactPlayerItems(identity.character, identity.profile)
    if not baselineItems then return false, itemError end
    local liveInventory = target.ZM_Inventory
    if type(liveInventory) ~= "table" or type(liveInventory.backpack) ~= "table" then
        return false, "The survivor's live backpack is unavailable."
    end
    for _, row in ipairs(baselineItems) do
        if row.itemId == self.TokenItemId or row.itemId == self.HammerItemId then
            return false, "The review requires no existing claim token or construction Hammer in the active inventory."
        end
    end
    local baselineSlots, slotError = ZM_GetExactEquippedWeaponSlots(identity.character, identity.profile)
    if not baselineSlots then return false, slotError end
    local _, selectedError = selectedWeaponClass(target, baselineSlots)
    if selectedError then return false, selectedError end
    local availableSlots, backpackError = backpackSlots(baselineItems)
    if not availableSlots then return false, backpackError end
    if liveInventory.backpack[availableSlots[1]] or liveInventory.backpack[availableSlots[2]] then
        return false, "The live backpack no longer has the two checked empty slots."
    end
    local claims, claimsError, existingClaim = getTargetClaims(identity.profile, cell.id, tileX, tileY)
    if not claims then return false, claimsError end
    if existingClaim then return false, "Choose a claimable tile with no existing claim row." end
    local token, tokenError = ZM_ItemGeneration:CreateInstance(self.TokenItemId, { count = 1 })
    if not token then return false, tokenError or "Could not create a temporary claim token." end
    local playerLevel = target.GetLevel and target:GetLevel() or 1
    local hammer, hammerError = ZM_ItemGeneration:CreateInstance(self.HammerItemId, {
        count = 1,
        level = 8,
        playerLevel = playerLevel,
        mastercraft = false
    })
    if not hammer then return false, hammerError or "Could not create a temporary Hammer." end
    local canUse, useError = ZM_Items:CanUse(target, self.HammerItemId, hammer)
    if not canUse then return false, "Cannot equip the temporary review Hammer: " .. tostring(useError) end
    local tokenRow, tokenRowError = temporaryItemRow(token, availableSlots[1])
    if not tokenRow then return false, tokenRowError end
    local hammerRow, hammerRowError = temporaryItemRow(hammer, availableSlots[2])
    if not hammerRow then return false, hammerRowError end

    local session = {
        id = string.format("%s-%06d", tostring(os.time()), math.random(0, 999999)),
        target = target,
        account = identity.account,
        character = identity.character,
        profile = identity.profile,
        cellId = cell.id,
        tileX = tileX,
        tileY = tileY,
        map = game.GetMap(),
        startedAt = os.time(),
        baselineSlots = baselineSlots,
        hammerId = hammerRow.instanceId,
        testIds = { [tokenRow.instanceId] = true, [hammerRow.instanceId] = true },
        tempInstances = { [tokenRow.instanceId] = token, [hammerRow.instanceId] = hammer },
        tempSlots = { tokenRow.slot, hammerRow.slot }
    }
    self.Active = session
    target.ZM_ClaimReviewSessionId = session.id

    local stagedItems = {}
    for _, row in ipairs(baselineItems) do stagedItems[#stagedItems + 1] = row end
    stagedItems[#stagedItems + 1] = tokenRow
    stagedItems[#stagedItems + 1] = hammerRow
    local saved, saveError = ZM_CommitWrites(identity.profile, {
        { kind = "playerItemsExact", steamid = identity.character, rows = stagedItems }
    })
    if not saved then
        self.Active = nil
        target.ZM_ClaimReviewSessionId = nil
        return false, "Could not add temporary review items: " .. tostring(saveError)
    end
    liveInventory.backpack[tokenRow.slot] = token
    liveInventory.backpack[hammerRow.slot] = hammer
    ZM_InventoryService:Send(target, { skipWeaponSlotNormalization = true })

    if SERVER and timer then
        timer.Create(self.TimerName, self.TimeoutSeconds, 1, function()
            if Review.Active == session then
                local rolledBack, rollbackError = Review:Rollback(nil, "timeout")
                if not rolledBack then
                    ErrorNoHalt("[ZombieSim] Claim-review timeout cleanup failed: " .. tostring(rollbackError) .. "\n")
                end
            end
        end)
    end
    report("ready", session)
    return true, string.format(
        "Review ready for cell %d tile (%d,%d). Claim it, review build mode and blueprints, then run zombiesim_dev_claim_review_rollback within %d minutes. The review pieces are removed on cleanup.",
        cell.id, tileX, tileY, self.TimeoutSeconds / 60)
end

function Review:Rollback(requester, reason)
    local session = self.Active
    if not session then return false, "No claim review session is active." end
    if IsValid(requester) then
        if not requester:IsAdmin() or requester ~= session.target then
            return false, "Only the preview admin who started the review can roll it back."
        end
    end

    local currentItems, itemError = ZM_GetExactPlayerItems(session.character, session.profile)
    if not currentItems then return false, itemError end
    local retainedItems = {}
    for _, row in ipairs(currentItems) do
        if not session.testIds[row.instanceId] then retainedItems[#retainedItems + 1] = row end
    end
    local currentSlots, slotError = ZM_GetExactEquippedWeaponSlots(session.character, session.profile)
    if not currentSlots then return false, slotError end
    local retainedSlots, retainedSlotsError = slotsWithoutReviewHammer(currentSlots, session.baselineSlots, session.hammerId)
    if not retainedSlots then return false, retainedSlotsError end

    local claims, claimsError, testClaim = getTargetClaims(session.profile, session.cellId, session.tileX, session.tileY)
    if not claims then return false, claimsError end
    if testClaim and (testClaim.owner ~= session.character or testClaim.account ~= session.account
        or (tonumber(testClaim.createdAt) or 0) < session.startedAt) then
        return false, "The review tile claim does not match this session; refusing deletion."
    end

    local target = reason ~= "disconnect" and IsValid(session.target) and session.target or nil
    local restoreWeaponClass
    if target then
        if target.ZM_ClaimReviewSessionId ~= session.id then
            return false, "The live claim-review session changed; refusing rollback."
        end
        if type(target.ZM_Inventory) ~= "table" then
            return false, "The survivor's live inventory is not loaded; refusing rollback."
        end
        local selectedError
        restoreWeaponClass, selectedError = selectedWeaponClass(target, retainedSlots)
        if selectedError then return false, selectedError end
    end

    local steps = {
        { kind = "playerItemsExact", steamid = session.character, rows = retainedItems },
        { kind = "equippedWeaponSlotsExact", steamid = session.character, rows = retainedSlots }
    }
    if testClaim then
        steps[#steps + 1] = {
            kind = "claimDelete",
            steamid = session.character,
            owner = session.character,
            account = session.account,
            cellId = session.cellId,
            tileX = session.tileX,
            tileY = session.tileY,
            createdAt = testClaim.createdAt
        }
    end
    local saved, saveError = ZM_CommitWrites(session.profile, steps)
    if not saved then return false, saveError end

    local verifiedItems, verifyItemsError = ZM_GetExactPlayerItems(session.character, session.profile)
    if not verifiedItems then return false, verifyItemsError end
    local verifiedSlots, verifySlotsError = ZM_GetExactEquippedWeaponSlots(session.character, session.profile)
    if not verifiedSlots then return false, verifySlotsError end
    local verifiedClaims, verifyClaimsError, remainingClaim = getTargetClaims(session.profile, session.cellId, session.tileX, session.tileY)
    if not verifiedClaims then return false, verifyClaimsError end
    if itemRowsSignature(verifiedItems) ~= itemRowsSignature(retainedItems)
        or weaponSlotSignature(verifiedSlots) ~= weaponSlotSignature(retainedSlots)
        or claimRowsSignature(verifiedClaims, session.tileX, session.tileY) ~= claimRowsSignature(claims, session.tileX, session.tileY)
        or remainingClaim then
        return false, "Cleanup committed, but persistence verification failed; session remains available for diagnosis."
    end

    if target then
        ZM_Construction:Clear(target)
        for _, containerName in ipairs({ "backpack", "equipped" }) do
            local container = target.ZM_Inventory[containerName] or {}
            for slot, instance in pairs(container) do
                if session.testIds[instance.instanceId] then container[slot] = nil end
            end
        end
        target.ZM_WeaponSlots = {}
        for _, row in ipairs(retainedSlots) do
            if row.instanceId then
                local slot = tonumber(row.slot)
                target.ZM_WeaponSlots[slot] = {
                    instanceId = row.instanceId,
                    selected = tonumber(row.selected) == 1
                }
            end
        end
        for _, weapon in ipairs(target:GetWeapons()) do
            local instanceId = weapon.GetItemInstanceId and weapon:GetItemInstanceId() or ""
            if session.testIds[instanceId] then target:StripWeapon(weapon:GetClass()) end
        end
        ZM_InventoryService:ReconcileEquippedWeapons(target)
        if restoreWeaponClass then target:SelectWeapon(restoreWeaponClass) end
        ZM_InventoryService:Send(target, { skipWeaponSlotNormalization = true })
        target.ZM_ClaimReviewSessionId = nil
    end
    for _, entity in ipairs(ents.FindByClass(ZM_Construction.PieceClass)) do
        if IsValid(entity) and entity.ZM_ClaimReviewSessionId == session.id then entity:Remove() end
    end
    if timer then timer.Remove(self.TimerName) end
    self.Active = nil
    report("rolled_back", {
        cellId = session.cellId,
        tileX = session.tileX,
        tileY = session.tileY,
        reason = reason
    })
    print(string.format("[ZombieSim] Claim review rolled back for cell %d tile (%d,%d).",
        session.cellId, session.tileX, session.tileY))
    return true, "Review claim, temporary items and tagged blueprints were removed; other inventory changes were retained."
end

directCommands.zombiesim_dev_claim_review_start = function(argumentString)
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then return false, "claim review requires a connected admin" end
    local x, y = string.match(argumentString or "", "^%s*(-?%d+)%s+(-?%d+)%s*$")
    if not x or not y then return false, "usage: zombiesim_dev_claim_review_start <tileX -2..2> <tileY -2..2>" end
    return Review:Start(target, tonumber(x), tonumber(y))
end

directCommands.zombiesim_dev_claim_review_rollback = function()
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then return false, "claim review rollback requires a connected admin" end
    return Review:Rollback(target, "manual")
end

directCommands.zombiesim_dev_claim_review_status = function(argumentString)
    local target = ZM_Util.FirstHuman()
    if not IsValid(target) or not target:IsAdmin() then
        return false, "claim review status requires a connected admin"
    end
    if ZM_World.ActiveProfile ~= "preview" then
        return false, "claim review status is restricted to the preview profile"
    end

    local cellIdText = string.match(argumentString or "", "^%s*(.-)%s*$")
    local cell
    if cellIdText == "" then
        local cellError
        cell, cellError = ZM_ClaimService:CurrentCell(target)
        if not cell then return false, cellError end
    else
        local cellId = tonumber(cellIdText)
        if not ZM_Util.IsWholeNumber(cellId) then
            return false, "usage: zombiesim_dev_claim_review_status [cellId]"
        end
        cell = ZM_World:GetCellById(cellId)
        if not cell then return false, "the requested cell is not in the loaded preview world index" end
    end

    local claimTiles = ZM_World:GetClaimTiles(cell)
    report("status", {
        cellId = cell.id,
        map = cell.map,
        profile = ZM_World.ActiveProfile,
        worldDataPath = ZM_World.DataPath,
        radiation = ZM_World:GetRadiationIntensity(cell),
        claimTiles = claimTiles
    })
    return true, "Read-only claim review status reported."
end

if SERVER and hook then
    hook.Add("PlayerDisconnected", "ZombieSim.ClaimReview.DisconnectCleanup", function(target)
        if Review.Active and Review.Active.target == target then
            local rolledBack, rollbackError = Review:Rollback(nil, "disconnect")
            if not rolledBack then
                ErrorNoHalt("[ZombieSim] Claim-review disconnect cleanup failed: " .. tostring(rollbackError) .. "\n")
            end
        end
    end)
end
