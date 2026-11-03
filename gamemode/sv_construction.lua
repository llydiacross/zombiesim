// Server-authoritative construction mode. Holding the Hammer and pressing Reload enters build mode only while the
// player stands within ZM_Construction.ProtectionMargin of an active claim tile they can access in the loaded city
// cell. In build mode zombies and other players ignore the builder and the builder cannot hurt them; leaving the
// area, switching weapon, dying or changing cell ends it. Claim access comes from ZM_ClaimService.
local Construction = ZM_Construction

Construction.CheckInterval = 1
Construction.ZombieClasses = { zn_walker_zombie = true, zn_boss_zombie = true }

util.AddNetworkString("ZM.Construction.Tiles")
util.AddNetworkString("ZM.Construction.SelectPiece")
util.AddNetworkString("ZM.Construction.Hit")
util.AddNetworkString("ZM.Construction.Delete")

// Sends the accessible claim tiles so the client can draw the build boundary.
function Construction:SendTiles(target, tiles)
    net.Start("ZM.Construction.Tiles")
    net.WriteUInt(math.Clamp(math.floor(tonumber(ZM_World:GetCellBounds().tileSize) or 640), 1, 65535), 16)
    net.WriteUInt(math.min(#tiles, 25), 5)
    for index = 1, math.min(#tiles, 25) do
        net.WriteInt(tiles[index].tileX, 4)
        net.WriteInt(tiles[index].tileY, 4)
    end
    net.Send(target)
end

local function notify(target, message)
    if IsValid(target) and target:IsPlayer() then
        target:PrintMessage(HUD_PRINTCENTER, message)
    end
end

function Construction:ActiveTool(target)
    local weapon = IsValid(target) and target:GetActiveWeapon() or nil
    if IsValid(weapon) and weapon:GetClass() == self.ToolClass and weapon.GetBuildMode then
        return weapon
    end
end

// Accessible active claim tiles of the player's current cell, or nil and a reason.
function Construction:AccessibleTiles(target)
    if not ZM_ClaimService.StorageReady then return nil, "Land-claim storage is unavailable." end
    local snapshot, snapshotError = ZM_ClaimService:CellSnapshot(target)
    if not snapshot then return nil, snapshotError end
    local tiles = {}
    for _, claim in ipairs(snapshot.claims) do
        if claim.active and claim.access then
            tiles[#tiles + 1] = { tileX = claim.tileX, tileY = claim.tileY }
        end
    end
    return tiles
end

// Whether the player may be in build mode right now, or false and a player-facing reason.
function Construction:Evaluate(target)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
        return false, "You must be alive to build."
    end
    local tiles, tilesError = self:AccessibleTiles(target)
    if not tiles then return false, tilesError end
    if #tiles == 0 then return false, "Build mode needs a claim you can access in this cell." end
    local tileSize = tonumber(ZM_World:GetCellBounds().tileSize) or 640
    if not self.WithinTiles(target:GetPos(), tiles, tileSize, self.ProtectionMargin) then
        return false, "Move closer to your claim to build."
    end
    return true, nil, tiles
end

local function tileSignature(tiles)
    local parts = {}
    for _, tile in ipairs(tiles) do parts[#parts + 1] = tile.tileX .. "," .. tile.tileY end
    table.sort(parts)
    return table.concat(parts, ";")
end

function Construction:PublishTiles(target, tiles)
    local signature = tileSignature(tiles)
    if target.ZM_ConstructionTileSignature == signature then return end
    target.ZM_ConstructionTileSignature = signature
    self:SendTiles(target, tiles)
end

local function setMode(target, weapon, enabled)
    if IsValid(weapon) and weapon.SetBuildMode then weapon:SetBuildMode(enabled) end
    target.ZM_ConstructionProtected = enabled or nil
    target.ZM_ConstructionCheckedAt = enabled and CurTime() or nil
    if not enabled then
        target.ZM_ConstructionTileSignature = nil
        Construction:CancelDeleteMode(target)
    end
end

function Construction:ToggleBuildMode(target, weapon)
    if weapon:GetBuildMode() then
        setMode(target, weapon, false)
        notify(target, "Build mode off.")
        return false
    end
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then
        notify(target, reason)
        return false
    end
    setMode(target, weapon, true)
    self:PublishTiles(target, tiles)
    notify(target, "Build mode on. Zombies and players will ignore you.")
    return true
end

function Construction:SelectPiece(target, kind)
    if type(kind) ~= "string" or not self.Pieces[kind] then
        return false, "Unknown construction piece."
    end
    local weapon = self:ActiveTool(target)
    if not weapon or not self:IsProtected(target) then
        return false, "Hold the Hammer in build mode to select a piece."
    end
    local eligible, reason = self:Evaluate(target)
    if not eligible then return false, reason end
    if target.ZM_ConstructionDeleteSelection then return false, "Exit delete mode before selecting a build piece." end
    weapon:SetBuildPiece(kind)
    return true
end

net.Receive("ZM.Construction.SelectPiece", function(_, target)
    local kind = net.ReadString()
    local selected, reason = Construction:SelectPiece(target, kind)
    if not selected then notify(target, reason) end
end)

function Construction:Clear(target)
    if not IsValid(target) then return end
    local weapon = self:ActiveTool(target)
    setMode(target, weapon, false)
end

// True while the player is in eligible build mode; also requires the hammer still to be the active weapon.
function Construction:IsProtected(target)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or target.ZM_ConstructionProtected ~= true then
        return false
    end
    local weapon = self:ActiveTool(target)
    return weapon ~= nil and weapon:GetBuildMode() == true
end

// Re-checks eligibility for players in build mode; ends the mode when they leave, switch weapon or lose access.
function Construction:Tick(target, now)
    if target.ZM_ConstructionProtected ~= true then return end
    local weapon = self:ActiveTool(target)
    if not weapon or not weapon:GetBuildMode() or not target:Alive() then
        self:Clear(target)
        return
    end
    if now - (target.ZM_ConstructionCheckedAt or 0) < self.CheckInterval then return end
    target.ZM_ConstructionCheckedAt = now
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then
        setMode(target, weapon, false)
        notify(target, "Build mode ended: " .. reason)
    else
        self:PublishTiles(target, tiles)
    end
end

function Construction:IsZombie(entity)
    return IsValid(entity) and self.ZombieClasses[entity:GetClass()] == true
end

// ---- Placement and persistence ----------------------------------------------------------------------------------
// Blueprints and built pieces persist per profile and logical cell in construction_pieces, keyed by slot, and are
// restored when their cell loads. Placement, payment, removal and breaking write immediately (payment and refunds in
// the same transaction as the inventory change); build progress, damage and repair are flushed on a timer.
// StorageReady is true or false once init.lua prepares the table; nil keeps pieces transient (offline fixtures).
// Claim-review pieces are never saved.
Construction.SlotRegistry = Construction.SlotRegistry or {}
Construction.NoticeInterval = 1.5
Construction.FlushInterval = 5
Construction.Dirty = Construction.Dirty or {}

local function ownerKeyOf(target)
    if not ZM_Util or not ZM_Util.CharacterKeyFor then return nil end
    local key = ZM_Util.CharacterKeyFor(target)
    if type(key) == "string" and key ~= "" then return key end
end

// Whether the player's current survivor owns the piece. Persisted pieces compare survivor keys so ownership
// survives reloads; transient pieces compare the placing player entity.
function Construction:OwnsPiece(target, entity)
    if entity.ZM_OwnerKey then return entity.ZM_OwnerKey == ownerKeyOf(target) end
    return entity.ZM_Owner == target
end

function Construction.EncodeCost(cost)
    local ids = table.GetKeys(cost or {})
    table.sort(ids)
    local parts = {}
    for _, itemId in ipairs(ids) do parts[#parts + 1] = itemId .. ":" .. cost[itemId] end
    return table.concat(parts, ",")
end

function Construction.DecodeCost(text)
    local cost = {}
    for itemId, amount in string.gmatch(text or "", "([%w_]+):(%d+)") do cost[itemId] = tonumber(amount) end
    return cost
end

// Claim tiles the piece's footprint overlaps, as ",x:y," tokens matched by the reclaim cleanup.
function Construction:FootprintTiles(kind, x, y, yaw)
    local tileSize = tonumber(ZM_World:GetCellBounds().tileSize) or 640
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, corner in ipairs(self.FootprintCorners(kind, x, y, yaw)) do
        minX, maxX = math.min(minX, corner.x), math.max(maxX, corner.x)
        minY, maxY = math.min(minY, corner.y), math.max(maxY, corner.y)
    end
    local function tileOf(value) return math.floor(value / tileSize + 0.5) end
    // Pieces snap to tile edges, so shrink by a unit to avoid claiming the neighbour across a shared edge.
    local inset = 1
    local tokens = {}
    for tileY = tileOf(math.min(minY + inset, maxY)), tileOf(math.max(maxY - inset, minY)) do
        for tileX = tileOf(math.min(minX + inset, maxX)), tileOf(math.max(maxX - inset, minX)) do
            tokens[#tokens + 1] = tileX .. ":" .. tileY
        end
    end
    return "," .. table.concat(tokens, ",") .. ","
end

function Construction:IsPersisted(entity)
    return type(entity.ZM_Profile) == "string" and type(entity.ZM_CellId) == "number" and entity.ZM_OwnerKey ~= nil
end

// The save step for a persisted piece; overrides replace fields not yet applied to the entity (payment).
function Construction:SaveStep(entity, overrides)
    overrides = overrides or {}
    local position = entity:GetPos()
    local complete = entity:GetComplete()
    local paid = overrides.paid
    if paid == nil then paid = entity:GetPaid() end
    local health = 0
    if complete then health = self:PieceHealth(entity) end
    return {
        kind = "constructionPieceSave", steamid = entity.ZM_OwnerKey, account = entity.ZM_OwnerAccount,
        cellId = entity.ZM_CellId, slotKey = entity.ZM_SlotKey, pieceKind = entity:GetPieceKind(),
        x = position.x, y = position.y, z = position.z, yaw = entity:GetPieceYaw(),
        progress = math.Clamp(entity:GetProgress(), 0, 1), paid = paid == true,
        paidCost = self.EncodeCost(overrides.paidCost or entity.ZM_PaidCost), complete = complete, health = health,
        tiles = entity.ZM_Tiles, createdAt = entity.ZM_CreatedAt or 0, now = os.time()
    }
end

function Construction:DeleteStep(entity)
    return { kind = "constructionPieceDelete", steamid = entity.ZM_OwnerKey, cellId = entity.ZM_CellId, slotKey = entity.ZM_SlotKey }
end

// Writes a persisted piece now. Returns true for transient pieces.
function Construction:SavePiece(entity)
    if not IsValid(entity) or not self:IsPersisted(entity) or entity.ZM_ConstructionRemoving then return true end
    local saved, saveError = ZM_CommitWrites(entity.ZM_Profile, { self:SaveStep(entity) })
    if not saved then
        self.Dirty[entity] = true
        ErrorNoHalt("[ZombieSim] Could not save a construction piece: " .. tostring(saveError) .. "\n")
        return false, saveError
    end
    self.Dirty[entity] = nil
    return true
end

function Construction:MarkDirty(entity)
    if IsValid(entity) and self:IsPersisted(entity) then self.Dirty[entity] = true end
end

// Saves every piece whose progress, health or wear changed since its last write.
function Construction:FlushDirty()
    local pending = table.GetKeys(self.Dirty)
    self.Dirty = {}
    local failures = 0
    for _, entity in ipairs(pending) do
        if IsValid(entity) and not self:SavePiece(entity) then failures = failures + 1 end
    end
    return failures == 0
end

// Deletes a persisted piece's row immediately (pieces broken by zombies). Returns true for transient pieces.
function Construction:DeletePieceRow(entity)
    self.Dirty[entity] = nil
    if not self:IsPersisted(entity) then return true end
    local deleted, deleteError = ZM_CommitWrites(entity.ZM_Profile, { self:DeleteStep(entity) })
    if not deleted then
        ErrorNoHalt("[ZombieSim] Could not delete a construction piece: " .. tostring(deleteError) .. "\n")
    end
    return deleted, deleteError
end

// Removes a piece entity without touching storage (map cleanup, cell switch or a row already deleted).
function Construction:DespawnPiece(entity)
    self.Dirty[entity] = nil
    if entity.ZM_SlotKey and self.SlotRegistry[entity.ZM_SlotKey] == entity then self.SlotRegistry[entity.ZM_SlotKey] = nil end
    entity.ZM_ConstructionRemoving = true
    entity:Remove()
end

local function noticeOnce(target, message)
    local now = CurTime()
    if target.ZM_ConstructionNotice == message and now - (target.ZM_ConstructionNoticeAt or 0) < Construction.NoticeInterval then
        return
    end
    target.ZM_ConstructionNotice = message
    target.ZM_ConstructionNoticeAt = now
    notify(target, message)
end

function Construction:PieceAtSlot(key)
    local entity = self.SlotRegistry[key]
    if IsValid(entity) then return entity end
    self.SlotRegistry[key] = nil
end

// Validates and spawns a blueprint at a placement resolved from the server's trace.
function Construction:PlacePiece(target, weapon, kind, x, y, z, yaw)
    if not weapon or not weapon:GetBuildMode() then return false, "Enter build mode first." end
    if not self.Pieces[kind] then return false, "Unknown construction piece." end
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then return false, reason end
    local tileSize = tonumber(ZM_World:GetCellBounds().tileSize) or 640
    for _, corner in ipairs(self.FootprintCorners(kind, x, y, yaw)) do
        if not self.WithinTiles(corner, tiles, tileSize, 0) then
            return false, "Pieces must be built inside your claim."
        end
    end
    local key = self.SlotKey(kind, x, y, z, yaw)
    if self:PieceAtSlot(key) then return false, "Something is already built there." end
    local entity = ents.Create(self.PieceClass)
    if not IsValid(entity) then return false, "Could not create the construction piece." end
    entity:SetPieceKind(kind)
    entity:SetPieceYaw(yaw)
    entity:SetPos(Vector(x, y, z))
    entity.ZM_Owner = target
    entity:SetNWEntity("ZM_ConstructionOwner", target)
    entity.ZM_SlotKey = key
    entity.ZM_ClaimReviewSessionId = target.ZM_ClaimReviewSessionId
    local persist
    if self.StorageReady ~= nil and not target.ZM_ClaimReviewSessionId then
        if self.StorageReady ~= true then
            entity:Remove()
            return false, "Construction storage is unavailable."
        end
        local identity, identityError = ZM_ClaimService:Identity(target)
        local cell, cellError = ZM_ClaimService:CurrentCell(target)
        if not identity or not cell then
            entity:Remove()
            return false, identityError or cellError
        end
        entity.ZM_OwnerKey = identity.character
        entity.ZM_OwnerAccount = identity.account
        entity.ZM_Profile = identity.profile
        entity.ZM_CellId = cell.id
        entity.ZM_CreatedAt = os.time()
        entity.ZM_Tiles = self:FootprintTiles(kind, x, y, yaw)
        persist = true
    end
    entity:Spawn()
    if not IsValid(entity) or entity.ZM_CollisionReady ~= true then
        if IsValid(entity) then entity:Remove() end
        return false, "Could not initialize the construction piece's collision."
    end
    if persist then
        local saved, saveError = ZM_CommitWrites(entity.ZM_Profile, { self:SaveStep(entity) })
        if not saved then
            entity:Remove()
            ErrorNoHalt("[ZombieSim] Could not save a construction blueprint: " .. tostring(saveError) .. "\n")
            return false, "Could not save the blueprint; check the server log."
        end
    end
    self.SlotRegistry[key] = entity
    return entity
end

function Construction:IsPiece(entity)
    return IsValid(entity) and entity:GetClass() == self.PieceClass
end

// Pieces may stand on level world surfaces or attach to finished pieces.
function Construction:PrimaryBuild(target, weapon)
    if not IsValid(target) or not IsValid(weapon) then return end
    if target.ZM_ConstructionDeleteSelection then
        self:SelectForDeletion(target)
        return
    end
    local kind = self.SelectedPiece(weapon)
    local trace = self:PlacementTrace(target, kind)
    local x, y, z, yaw, valid, reason = self.ResolvePlacement(kind, trace, target:EyeAngles().y)
    if not valid then
        notify(target, reason)
        return
    end
    local placed
    placed, reason = self:PlacePiece(target, weapon, kind, x, y, z, yaw)
    if not placed then
        notify(target, reason)
        return
    end
    notify(target, self.Pieces[kind].name .. " blueprint placed. Hold E on it to build.")
end

// Refunds the exact paid cost in one inventory mutation before removing a structure. The saved rows of persisted
// pieces are deleted in the same transaction (or directly when nothing was paid), so a failure keeps both.
function Construction:RefundPiecesMaterials(target, pieces)
    local cost = {}
    local deleteSteps, profile = {}, nil
    for _, entity in ipairs(pieces) do
        if self:IsPersisted(entity) then
            if profile and profile ~= entity.ZM_Profile then return false, "Cannot remove pieces from different profiles together." end
            profile = entity.ZM_Profile
            deleteSteps[#deleteSteps + 1] = self:DeleteStep(entity)
        end
        if entity:GetPaid() then
            if type(entity.ZM_PaidCost) ~= "table" or next(entity.ZM_PaidCost) == nil then
                return false, "Cannot remove this structure: its paid material cost was not recorded."
            end
            for itemId, amount in pairs(entity.ZM_PaidCost) do
                if type(amount) ~= "number" or amount < 1 or amount ~= math.floor(amount) then
                    return false, "The structure's recorded material cost is invalid."
                end
                cost[itemId] = (cost[itemId] or 0) + amount
            end
        end
    end
    if next(cost) == nil then
        if #deleteSteps == 0 then return true end
        local deleted, deleteError = ZM_CommitWrites(profile, deleteSteps)
        if not deleted then return false, "Could not remove the saved structure: " .. tostring(deleteError) end
        return true
    end
    if not ZM_InventoryService or not ZM_ItemGeneration then
        return false, "Cannot refund materials because inventory services are unavailable."
    end
    if profile and profile ~= ZM_Util.ProfileFor(target) then
        return false, "Cannot refund a structure saved in another world profile."
    end
    local ids = table.GetKeys(cost)
    table.sort(ids)
    local saved, saveError = ZM_InventoryService:Mutate(target, function(draft)
        for _, itemId in ipairs(ids) do
            local definition = ZM_Items:GetDefinition(itemId)
            if not definition or not definition.maxStack or definition.maxStack < 1 then
                return false, "The structure's refund material has no valid stack size."
            end
            local remaining = cost[itemId]
            while remaining > 0 do
                local amount = math.min(remaining, definition.maxStack)
                local instance, createError = ZM_ItemGeneration:CreateInstance(itemId, { count = amount })
                if not instance then return false, createError end
                local added, addError = ZM_InventoryService.Ops.Add(draft, "backpack", instance)
                if not added then return false, addError end
                remaining = remaining - amount
            end
        end
        return true
    end, #deleteSteps > 0 and { extraSteps = function() return deleteSteps end } or nil)
    if not saved then
        return false, "Could not refund materials; the structure was not removed: " .. tostring(saveError)
    end
    return true
end

function Construction:RemoveOwnedPiece(target, entity)
    if not self:IsPiece(entity) or not self:OwnsPiece(target, entity) or entity.ZM_ConstructionRemoving then return false end
    local wasPaid = entity:GetPaid()
    local wasComplete = entity:GetComplete()
    local refunded, reason = self:RefundPiecesMaterials(target, { entity })
    if not refunded then return true, false, reason end
    if target.ZM_ConstructionDeleteSelection then
        target.ZM_ConstructionDeleteSelection[entity] = nil
        self:PublishDeleteCount(target)
    end
    self:DespawnPiece(entity)
    return true, true, wasPaid, wasComplete
end

function Construction:SecondaryBuild(target, weapon)
    if not IsValid(target) or not IsValid(weapon) then return end
    if not self:IsProtected(target) then return end
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then notify(target, reason) return end
    local trace = self:AimTrace(target, self.DeleteReach)
    if not self:IsPiece(trace.Entity) or trace.Entity:GetComplete() then return end
    local allowed, removeError = self:CanRemovePiece(target, trace.Entity, tiles)
    if not allowed then notify(target, removeError) return end
    local handled, removed, result, wasComplete = self:RemoveOwnedPiece(target, trace.Entity)
    if handled then
        if removed then
            if result then
                notify(target, "Structure removed; materials refunded.")
            else
                notify(target, wasComplete and "Structure removed." or "Blueprint removed.")
            end
        else
            notify(target, result)
        end
        return
    end
end

function Construction:PublishDeleteCount(target)
    local count = 0
    for entity in pairs(target.ZM_ConstructionDeleteSelection or {}) do
        if IsValid(entity) then count = count + 1 end
    end
    target:SetNWInt("ZM_ConstructionDeleteCount", count)
end

function Construction:CancelDeleteMode(target)
    for entity in pairs(target.ZM_ConstructionDeleteSelection or {}) do
        if IsValid(entity) then entity:SetNWBool("ZM_ConstructionDeleteSelected", false) end
    end
    target.ZM_ConstructionDeleteSelection = nil
    target:SetNWBool("ZM_ConstructionDeleteMode", false)
    target:SetNWInt("ZM_ConstructionDeleteCount", 0)
end

function Construction:CanRemovePiece(target, entity, tiles)
    if not self:IsPiece(entity) or not self:OwnsPiece(target, entity) or entity.ZM_ConstructionRemoving then
        return false, "Aim at a construction piece you own."
    end
    local tileSize = ZM_World:GetCellBounds().tileSize
    for _, corner in ipairs(self.FootprintCorners(entity:GetPieceKind(), entity:GetPos().x, entity:GetPos().y,
        entity:GetPieceYaw())) do
        if not self.WithinTiles(corner, tiles, tileSize, 0) then
            return false, "The piece is outside your accessible claim tiles."
        end
    end
    return true
end

function Construction:SelectForDeletion(target)
    if not self:IsProtected(target) or not target.ZM_ConstructionDeleteSelection then return end
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then notify(target, reason) return end
    local entity = self:AimTrace(target, self.DeleteReach).Entity
    local allowed, removeError = self:CanRemovePiece(target, entity, tiles)
    if not allowed then notify(target, removeError) return end
    local selection = target.ZM_ConstructionDeleteSelection
    selection[entity] = not selection[entity] or nil
    entity:SetNWBool("ZM_ConstructionDeleteSelected", selection[entity] == true)
    self:PublishDeleteCount(target)
end

function Construction:ToggleDeleteMode(target)
    if not self:IsProtected(target) then return false, "Hold the Hammer in build mode to delete pieces." end
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then return false, reason end
    if not target.ZM_ConstructionDeleteSelection then
        target.ZM_ConstructionDeleteSelection = {}
        target:SetNWBool("ZM_ConstructionDeleteMode", true)
        target:SetNWInt("ZM_ConstructionDeleteCount", 0)
        return true, "Delete mode: click pieces to mark them red, then press Delete to confirm."
    end
    local pieces = {}
    for entity in pairs(target.ZM_ConstructionDeleteSelection) do
        if IsValid(entity) then
            local allowed, removeError = self:CanRemovePiece(target, entity, tiles)
            if not allowed then return false, removeError end
            pieces[#pieces + 1] = entity
        end
    end
    local refunded, refundError = self:RefundPiecesMaterials(target, pieces)
    if not refunded then return false, refundError end
    self:CancelDeleteMode(target)
    for _, entity in ipairs(pieces) do
        self:DespawnPiece(entity)
    end
    return true, #pieces == 0 and "Delete mode off." or (#pieces .. " piece(s) removed; paid materials refunded.")
end

net.Receive("ZM.Construction.Delete", function(length, target)
    if length ~= 0 then notify(target, "Invalid construction delete request.") return end
    local now = CurTime()
    if target.ZM_ConstructionDeletePressedAt and now - target.ZM_ConstructionDeletePressedAt < 0.3 then return end
    target.ZM_ConstructionDeletePressedAt = now
    local _, message = Construction:ToggleDeleteMode(target)
    notify(target, message)
end)

local function describeCost(cost)
    local parts, ids = {}, table.GetKeys(cost)
    table.sort(ids)
    for _, itemId in ipairs(ids) do
        local definition = ZM_Items and ZM_Items:GetDefinition(itemId)
        parts[#parts + 1] = cost[itemId] .. " " .. (definition and definition.name or itemId)
    end
    return table.concat(parts, " and ")
end

// Charges a piece's material cost from the backpack in one atomic inventory mutation.
function Construction:PayForPiece(target, weapon, entity)
    if target.ZM_ClaimReviewSessionId then
        return false, "Paid construction is disabled during the claim review."
    end
    local cost = self.MaterialCost(entity:GetPieceKind(), weapon:GetItemMastercraft())
    local ids = table.GetKeys(cost)
    table.sort(ids)
    local insufficient = false
    local saved, saveError = ZM_InventoryService:Mutate(target, function(draft)
        for _, itemId in ipairs(ids) do
            if ZM_InventoryService.Ops.Count(draft, itemId, "backpack") < cost[itemId] then
                insufficient = true
                return false, "insufficient construction materials"
            end
        end
        for _, itemId in ipairs(ids) do
            local removed, removeError = ZM_InventoryService.Ops.Remove(draft, "backpack", itemId, cost[itemId])
            if not removed then return false, removeError end
        end
        return true
    end, self:IsPersisted(entity) and {
        extraSteps = function() return { self:SaveStep(entity, { paid = true, paidCost = cost }) } end
    } or nil)
    if not saved then
        if insufficient then return false, "Building this needs " .. describeCost(cost) .. " in your backpack." end
        ErrorNoHalt("[ZombieSim] Construction payment failed: " .. tostring(saveError) .. "\n")
        return false, "Could not save construction materials; check the server log."
    end
    entity.ZM_PaidCost = {}
    for itemId, amount in pairs(cost) do entity.ZM_PaidCost[itemId] = amount end
    return true
end

function Construction:CompletePiece(entity)
    entity:SetProgress(1)
    entity:SetComplete(true)
    entity:SetCompletedAt(CurTime())
    entity:SetCollisionGroup(COLLISION_GROUP_NONE)
    entity.ZM_Health = self.MaxHealth(entity:GetPieceKind())
    entity:SetWear(0)
    self:SavePiece(entity)
end

// Current health of a complete piece; pieces completed before health existed start at full health.
function Construction:PieceHealth(entity)
    local maxHealth = self.MaxHealth(entity:GetPieceKind()) or 1
    if entity.ZM_Health == nil then entity.ZM_Health = maxHealth end
    return math.Clamp(entity.ZM_Health, 0, maxHealth), maxHealth
end

local function setHealth(entity, health, maxHealth)
    entity.ZM_Health = health
    entity:SetWear(math.Clamp(1 - health / maxHealth, 0, 1))
    Construction:MarkDirty(entity)
end

Construction.GibModels = {
    "models/gibs/wood_gib01a.mdl", "models/gibs/wood_gib01b.mdl", "models/gibs/wood_gib01c.mdl",
    "models/gibs/wood_gib01d.mdl", "models/gibs/wood_gib01e.mdl"
}
Construction.GibLifetime = 10

// Breaks a piece: splintering sound, short-lived debris gibs and removal. Pieces resting on it are not checked.
function Construction:BreakPiece(entity)
    local origin = entity:GetPos()
    local minX, minY, minZ, maxX, maxY, maxZ = self.PieceBounds(entity:GetPieceKind(), entity:GetPieceYaw())
    local mins, maxs = Vector(minX or 0, minY or 0, minZ or 0), Vector(maxX or 0, maxY or 0, maxZ or 0)
    local center = origin + (mins + maxs) * 0.5
    local spread = (maxs - mins) * 0.35
    sound.Play("physics/wood/wood_plank_break" .. math.random(1, 4) .. ".wav", center, 80, math.random(90, 105), 1)
    for index = 1, math.random(4, 6) do
        local gib = ents.Create("prop_physics")
        if IsValid(gib) then
            gib:SetModel(self.GibModels[math.random(#self.GibModels)])
            gib:SetPos(center + Vector(math.Rand(-spread.x, spread.x), math.Rand(-spread.y, spread.y), math.Rand(-spread.z, spread.z)))
            gib:SetAngles(AngleRand())
            gib:Spawn()
            gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            local physics = gib:GetPhysicsObject()
            if IsValid(physics) then
                physics:SetVelocity(VectorRand() * 120 + Vector(0, 0, 80))
                physics:AddAngleVelocity(VectorRand() * 300)
            end
            SafeRemoveEntityDelayed(gib, self.GibLifetime + index * 0.1)
        end
    end
    self.BrokenCount = (self.BrokenCount or 0) + 1
    self:DeletePieceRow(entity)
    self:DespawnPiece(entity)
end

// Zombie damage to a complete piece. Each hit sends splinters to nearby clients; crossing a damage stage creaks,
// and reaching zero health breaks the piece. Returns true when the piece broke.
function Construction:DamagePiece(entity, amount, attacker, hitPos, hitNormal)
    if not self:IsPiece(entity) or not entity:GetComplete() then return false end
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    local health, maxHealth = self:PieceHealth(entity)
    local oldStage = self.DamageStage(entity:GetWear())
    health = math.max(0, health - amount)
    setHealth(entity, health, maxHealth)
    local position = hitPos or entity:NearestPoint(IsValid(attacker) and attacker:WorldSpaceCenter() or entity:GetPos())
    local normal = hitNormal or (IsValid(attacker) and (attacker:WorldSpaceCenter() - position):GetNormalized() or Vector(0, 0, 1))
    net.Start("ZM.Construction.Hit")
    net.WriteVector(position)
    net.WriteNormal(normal)
    net.SendPVS(position)
    if health <= 0 then
        self:BreakPiece(entity)
        return true
    end
    sound.Play("physics/wood/wood_plank_impact_hard" .. math.random(1, 5) .. ".wav", position, 75, math.random(90, 110), 0.9)
    if self.DamageStage(entity:GetWear()) > oldStage then
        sound.Play("physics/wood/wood_strain" .. math.random(2, 4) .. ".wav", position, 75, math.random(95, 105), 1)
    end
    return false
end

// One continuous-use tick repairing a damaged complete piece with the Hammer in build mode. Repair is free and
// restores the full health over the piece's build time at the hammer's speed.
function Construction:RepairPiece(target, entity, now)
    local health, maxHealth = self:PieceHealth(entity)
    if health >= maxHealth then return false end
    local weapon = self:ActiveTool(target)
    if not weapon or not weapon:GetBuildMode() or not self:IsProtected(target) then
        noticeOnce(target, "Hold the Hammer in build mode to repair.")
        return false
    end
    local step = self.InitialContributionSeconds
    if target.ZM_ConstructionUsePiece == entity then
        local gap = now - (target.ZM_ConstructionUseAt or now)
        if gap > 0 and gap <= self.MaxContributionStep then step = gap end
    end
    target.ZM_ConstructionUsePiece = entity
    target.ZM_ConstructionUseAt = now
    local seconds = self:BuildSeconds(entity:GetPieceKind(), weapon:GetItemLevel())
    health = math.min(maxHealth, health + maxHealth * step / seconds)
    setHealth(entity, health, maxHealth)
    self:PlayBuildFeedback(target, weapon, now)
    if health >= maxHealth then
        notify(target, "Repair complete.")
    end
    return true
end

// One continuous-use tick of a player building a piece. A press immediately contributes one second so tapping E
// visibly starts work; holding E then accrues the capped elapsed time. The first regular contribution pays materials.
Construction.MaxContributionStep = 0.25
Construction.InitialContributionSeconds = 1
Construction.FeedbackInterval = 0.65

function Construction:PlayBuildFeedback(target, weapon, now)
    if now < (target.ZM_ConstructionFeedbackAt or 0) then return end
    target.ZM_ConstructionFeedbackAt = now + self.FeedbackInterval
    weapon:SendWeaponAnim(ACT_VM_HITCENTER)
    target:SetAnimation(PLAYER_ATTACK1)
    weapon:EmitSound("physics/wood/wood_plank_impact_hard" .. math.random(1, 3) .. ".wav", 70, 100, 0.7, CHAN_WEAPON)
end

function Construction:Contribute(target, entity, now)
    if not self:IsPiece(entity) then return false end
    if target.ZM_ConstructionDeleteSelection then
        noticeOnce(target, "Exit delete mode before building or repairing.")
        return false
    end
    if entity:GetComplete() then return self:RepairPiece(target, entity, now) end
    local weapon = self:ActiveTool(target)
    if not weapon or not weapon:GetBuildMode() or not self:IsProtected(target) then
        noticeOnce(target, "Hold the Hammer in build mode to build.")
        return false
    end
    local activeReview = ZM_ClaimReviewTest and ZM_ClaimReviewTest.Active
    local reviewSessionId = activeReview and activeReview.id
    local freeReviewBuild = activeReview ~= nil and activeReview.target == target
        and type(reviewSessionId) == "string" and reviewSessionId ~= ""
        and target.ZM_ClaimReviewSessionId == reviewSessionId
        and entity.ZM_ClaimReviewSessionId == reviewSessionId
    // The preview Free Building cheat skips material payment; the blueprint stays unpaid so it remains removable.
    local freeCheatBuild = not freeReviewBuild and target.ZM_CheatFreeBuild == true
    local freeBuild = freeReviewBuild or freeCheatBuild
    if not entity:GetPaid() and not freeBuild then
        local paid, reason = self:PayForPiece(target, weapon, entity)
        if not paid then
            noticeOnce(target, reason)
            return false
        end
        entity:SetPaid(true)
    end
    local step = self.InitialContributionSeconds
    local newPress = true
    if target.ZM_ConstructionUsePiece == entity then
        local gap = now - (target.ZM_ConstructionUseAt or now)
        if gap > 0 and gap <= self.MaxContributionStep then
            step = gap
            newPress = false
        end
    end
    if newPress then
        noticeOnce(target, freeReviewBuild and "Building this review blueprint is free."
            or freeCheatBuild and "Free building cheat: no materials are used."
            or "Building started. Hold E to continue.")
    end
    target.ZM_ConstructionUsePiece = entity
    target.ZM_ConstructionUseAt = now
    local seconds = self:BuildSeconds(entity:GetPieceKind(), weapon:GetItemLevel())
    local progress = math.min(1, entity:GetProgress() + step / seconds)
    if progress >= 1 and self:Occupied(entity) then
        noticeOnce(target, "Something is in the way.")
        return false
    end
    entity:SetProgress(progress)
    self:MarkDirty(entity)
    self:PlayBuildFeedback(target, weapon, now)
    if progress >= 1 then
        self:CompletePiece(entity)
        notify(target, freeReviewBuild and "Review blueprint complete; no materials were used."
            or freeCheatBuild and "Construction complete; no materials were used." or "Construction complete.")
    end
    return true
end

// Whether a player or creature stands inside the piece, which would trap it once the piece turns solid.
function Construction:Occupied(entity)
    local origin = entity:GetPos()
    for _, part in ipairs(self.GetParts(entity:GetPieceKind(), entity:GetPieceYaw())) do
        local found = ents.FindInBox(origin + Vector(part.minX, part.minY, part.minZ),
            origin + Vector(part.maxX, part.maxY, part.maxZ))
        for _, other in ipairs(found) do
            if IsValid(other) and other ~= entity and (other:IsPlayer() or other:IsNPC() or self:IsZombie(other)) then
                return true
            end
        end
    end
    return false
end

// Damage between a builder and zombies or other players is blocked in both directions.
function Construction:BlocksDamage(victim, attacker)
    if not IsValid(victim) or not IsValid(attacker) or victim == attacker then return false end
    if victim:IsPlayer() and self:IsProtected(victim) and (attacker:IsPlayer() or self:IsZombie(attacker)) then
        return true
    end
    return attacker:IsPlayer() and self:IsProtected(attacker) and (victim:IsPlayer() or self:IsZombie(victim))
end

// ---- Restoring saved pieces -----------------------------------------------------------------------------------
// Spawns a saved row as a piece, applying stored progress, payment, completion and health. Returns the entity.
function Construction:SpawnSavedPiece(profile, row)
    if not self.Pieces[row.kind] then return nil, "unknown piece kind '" .. tostring(row.kind) .. "'" end
    if self:PieceAtSlot(row.slotKey) then return nil, "slot already occupied" end
    local entity = ents.Create(self.PieceClass)
    if not IsValid(entity) then return nil, "could not create the piece entity" end
    entity:SetPieceKind(row.kind)
    entity:SetPieceYaw(row.yaw)
    entity:SetPos(Vector(row.x, row.y, row.z))
    entity:SetProgress(math.Clamp(row.progress, 0, 1))
    entity:SetPaid(row.paid == true)
    entity:SetComplete(row.complete == true)
    // A completion time well in the past keeps restored pieces from replaying the build fade.
    if row.complete then entity:SetCompletedAt(CurTime() - 1000) end
    entity.ZM_SlotKey = row.slotKey
    entity.ZM_OwnerKey = row.owner
    entity.ZM_OwnerAccount = row.account
    entity.ZM_Profile = profile
    entity.ZM_CellId = row.cellId
    entity.ZM_CreatedAt = row.createdAt
    entity.ZM_Tiles = row.tiles
    if row.paid then entity.ZM_PaidCost = self.DecodeCost(row.paidCost) end
    entity:Spawn()
    if not IsValid(entity) or entity.ZM_CollisionReady ~= true then
        if IsValid(entity) then entity:Remove() end
        return nil, "could not initialize collision"
    end
    if row.complete then
        local maxHealth = self.MaxHealth(row.kind) or 1
        entity.ZM_Health = math.Clamp(row.health, 0, maxHealth)
        entity:SetWear(math.Clamp(1 - entity.ZM_Health / maxHealth, 0, 1))
    end
    self.SlotRegistry[row.slotKey] = entity
    return entity
end

// Points each restored piece's networked owner at its survivor's player when that player is online.
function Construction:BindOwners()
    for _, entity in pairs(self.SlotRegistry) do
        if IsValid(entity) and entity.ZM_OwnerKey then
            local owner = NULL
            for _, playerEntity in ipairs(player.GetHumans()) do
                if ownerKeyOf(playerEntity) == entity.ZM_OwnerKey then owner = playerEntity break end
            end
            entity.ZM_Owner = IsValid(owner) and owner or nil
            entity:SetNWEntity("ZM_ConstructionOwner", owner)
        end
    end
end

// Despawns every persisted piece (saving pending changes first) so another logical cell's pieces can load.
function Construction:UnloadCell()
    self:FlushDirty()
    for _, entity in pairs(self.SlotRegistry) do
        if IsValid(entity) and self:IsPersisted(entity) then self:DespawnPiece(entity) end
    end
    self.RestoredCell = nil
end

// Restores the saved pieces of a logical cell once per load. Rows that cannot spawn are logged and kept.
function Construction:RestoreCell(profile, cellId)
    local restored = self.RestoredCell
    if restored and restored.profile == profile and restored.cellId == cellId then return true, 0 end
    if restored then self:UnloadCell() end
    local rows, readError = ZM_GetCellConstructionPieces(profile, cellId)
    if not rows then return false, "Could not read saved construction: " .. tostring(readError) end
    local count, failures = 0, 0
    for _, row in ipairs(rows) do
        local entity, spawnError = self:SpawnSavedPiece(profile, row)
        if entity then
            count = count + 1
        else
            failures = failures + 1
            ErrorNoHalt("[ZombieSim] Could not restore construction piece " .. tostring(row.slotKey) .. ": "
                .. tostring(spawnError) .. "\n")
        end
    end
    self.RestoredCell = { profile = profile, cellId = cellId }
    if failures > 0 then return false, failures .. " saved construction piece(s) could not be restored.", count end
    return true, count
end

function Construction:OnPlayerReady(target)
    if not IsValid(target) or target.ZM_PersistentStateLoaded ~= true then return true end
    if self.StorageReady ~= true then return false, "Construction storage is unavailable." end
    if type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" then return true end
    local cell = target.GetWorldCell and target:GetWorldCell() or nil
    if not cell then return true end
    if ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell) then return true end
    local function baseMap(path) return string.lower(string.match(path or "", "([^/]+)$") or path or "") end
    if baseMap(ZM_World:GetMapPath(cell)) ~= baseMap(game.GetMap()) then return true end
    local restored, restoreError = self:RestoreCell(ZM_Util.ProfileFor(target), cell.id)
    self:BindOwners()
    if not restored then return false, restoreError end
    return true
end

hook.Add("PreCleanupMap", "ZM.Construction.Cleanup", function()
    Construction:FlushDirty()
    Construction.RestoredCell = nil
end)

hook.Add("PostCleanupMap", "ZM.Construction.Restore", function()
    timer.Simple(0, function()
        for _, playerEntity in ipairs(player.GetHumans()) do
            local restored, restoreError = Construction:OnPlayerReady(playerEntity)
            if not restored then ErrorNoHalt("[ZombieSim] " .. tostring(restoreError) .. "\n") end
        end
    end)
end)

hook.Add("ShutDown", "ZM.Construction.Flush", function()
    Construction:FlushDirty()
end)

local nextFlushAt = 0
local nextTickAt = 0
hook.Add("Think", "ZM.Construction.Tick", function()
    local now = CurTime()
    if now >= nextFlushAt then
        nextFlushAt = now + Construction.FlushInterval
        if next(Construction.Dirty) then Construction:FlushDirty() end
    end
    if now < nextTickAt then return end
    nextTickAt = now + 0.25
    for _, playerEntity in ipairs(player.GetHumans()) do
        Construction:Tick(playerEntity, now)
    end
end)

hook.Add("EntityTakeDamage", "ZM.Construction.NonInteraction", function(victim, damageInfo)
    if Construction:BlocksDamage(victim, damageInfo:GetAttacker()) then
        return true
    end
end)

hook.Add("PlayerDeath", "ZM.Construction.ClearOnDeath", function(playerEntity)
    Construction:Clear(playerEntity)
end)

hook.Add("PlayerSpawn", "ZM.Construction.ClearOnSpawn", function(playerEntity)
    Construction:Clear(playerEntity)
end)

hook.Add("PlayerDisconnected", "ZM.Construction.ClearOnDisconnect", function(playerEntity)
    Construction:Clear(playerEntity)
end)
