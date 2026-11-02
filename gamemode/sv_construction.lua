// Server-authoritative construction mode. Holding the Hammer and pressing Reload enters build mode only while the
// player stands within ZM_Construction.ProtectionMargin of an active claim tile they can access in the loaded city
// cell. In build mode zombies and other players ignore the builder and the builder cannot hurt them; leaving the
// area, switching weapon, dying or changing cell ends it. Claim access comes from ZM_ClaimService.
local Construction = ZM_Construction

Construction.CheckInterval = 1
Construction.ZombieClasses = { zn_walker_zombie = true, zn_boss_zombie = true }

util.AddNetworkString("ZM.Construction.Tiles")

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
    if not enabled then target.ZM_ConstructionTileSignature = nil end
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

// ---- Placement prototype -------------------------------------------------------------------------------------
// Pieces are transient for now: blueprints (unpaid wireframes) and built pieces vanish on map change.
Construction.PieceClass = "zn_construction_piece"
Construction.SlotRegistry = Construction.SlotRegistry or {}
Construction.NoticeInterval = 1.5

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

function Construction:BlueprintCount(target)
    local count = 0
    for key, entity in pairs(self.SlotRegistry) do
        if not IsValid(entity) then
            self.SlotRegistry[key] = nil
        elseif entity.ZM_Owner == target and not entity:GetPaid() then
            count = count + 1
        end
    end
    return count
end

// Validates and spawns a blueprint at the snapped placement for an aimed surface point; returns entity or false, reason.
function Construction:PlacePiece(target, weapon, kind, hitPos, viewYaw)
    if not weapon or not weapon:GetBuildMode() then return false, "Enter build mode first." end
    if not self.Pieces[kind] then return false, "Unknown construction piece." end
    local eligible, reason, tiles = self:Evaluate(target)
    if not eligible then return false, reason end
    local x, y, z, yaw = self.SnapPlacement(kind, hitPos.x, hitPos.y, hitPos.z, viewYaw)
    local tileSize = tonumber(ZM_World:GetCellBounds().tileSize) or 640
    for _, corner in ipairs(self.FootprintCorners(kind, x, y, yaw)) do
        if not self.WithinTiles(corner, tiles, tileSize, 0) then
            return false, "Pieces must be built inside your claim."
        end
    end
    local key = self.SlotKey(kind, x, y, z, yaw)
    if self:PieceAtSlot(key) then return false, "Something is already built there." end
    if self:BlueprintCount(target) >= self.MaxBlueprintsPerPlayer then
        return false, "Finish or remove some blueprints first."
    end
    local entity = ents.Create(self.PieceClass)
    if not IsValid(entity) then return false, "Could not create the construction piece." end
    entity:SetPieceKind(kind)
    entity:SetPieceYaw(yaw)
    entity:SetPos(Vector(x, y, z))
    entity.ZM_Owner = target
    entity.ZM_SlotKey = key
    entity:Spawn()
    self.SlotRegistry[key] = entity
    return entity
end

function Construction:IsPiece(entity)
    return IsValid(entity) and entity:GetClass() == self.PieceClass
end

// Pieces may sit on level world surfaces or on top of finished pieces.
function Construction:PrimaryBuild(target, weapon)
    if not IsValid(target) or not IsValid(weapon) then return end
    local trace = self:AimTrace(target)
    if not trace.Hit or trace.HitNormal.z < 0.7 then
        notify(target, "Aim at level ground within reach.")
        return
    end
    if not trace.HitWorld and not (self:IsPiece(trace.Entity) and trace.Entity:GetComplete()) then
        notify(target, "Pieces must stand on the ground or a finished piece.")
        return
    end
    local kind = self.SelectedPiece(weapon)
    local placed, reason = self:PlacePiece(target, weapon, kind, trace.HitPos, target:EyeAngles().y)
    if not placed then
        notify(target, reason)
        return
    end
    notify(target, self.Pieces[kind].name .. " blueprint placed. Hold E on it to build.")
end

// Removes the aimed unpaid blueprint the player placed; otherwise cycles the selected piece.
function Construction:RemoveBlueprint(target, entity)
    if not self:IsPiece(entity) or entity.ZM_Owner ~= target or entity:GetPaid() then return false end
    self.SlotRegistry[entity.ZM_SlotKey] = nil
    entity:Remove()
    return true
end

function Construction:SecondaryBuild(target, weapon)
    if not IsValid(target) or not IsValid(weapon) then return end
    local trace = self:AimTrace(target)
    if self:RemoveBlueprint(target, trace.Entity) then
        notify(target, "Blueprint removed.")
        return
    end
    local kind = self.NextPieceKind(self.SelectedPiece(weapon))
    weapon:SetBuildPiece(kind)
    notify(target, "Selected: " .. self.Pieces[kind].name)
end

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
    local cost = self.MaterialCost(entity:GetPieceKind(), weapon:GetItemMastercraft())
    local ids = table.GetKeys(cost)
    table.sort(ids)
    local saved = ZM_InventoryService:Mutate(target, function(draft)
        for _, itemId in ipairs(ids) do
            local removed, removeError = ZM_InventoryService.Ops.Remove(draft, "backpack", itemId, cost[itemId])
            if not removed then return false, removeError end
        end
        return true
    end)
    if not saved then return false, "Building this needs " .. describeCost(cost) .. " in your backpack." end
    return true
end

function Construction:CompletePiece(entity)
    entity:SetProgress(1)
    entity:SetComplete(true)
    entity:SetCompletedAt(CurTime())
    entity:SetCollisionGroup(COLLISION_GROUP_NONE)
end

// One continuous-use tick of a player building a piece. The first contribution pays the materials; progress then
// accrues by elapsed time scaled by the hammer level. Returns true while progress was made.
Construction.MaxContributionStep = 0.25
function Construction:Contribute(target, entity, now)
    if not self:IsPiece(entity) or entity:GetComplete() then return false end
    local weapon = self:ActiveTool(target)
    if not weapon or not weapon:GetBuildMode() or not self:IsProtected(target) then
        noticeOnce(target, "Hold the Hammer in build mode to build.")
        return false
    end
    if not entity:GetPaid() then
        local paid, reason = self:PayForPiece(target, weapon, entity)
        if not paid then
            noticeOnce(target, reason)
            return false
        end
        entity:SetPaid(true)
    end
    local step = 0
    if target.ZM_ConstructionUsePiece == entity then
        local gap = now - (target.ZM_ConstructionUseAt or now)
        if gap > 0 and gap <= self.MaxContributionStep then step = gap end
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
    if progress >= 1 then self:CompletePiece(entity) end
    return true
end

// Whether a player or creature stands inside the piece, which would trap it once the piece turns solid.
function Construction:Occupied(entity)
    local minX, minY, minZ, maxX, maxY, maxZ = self.PieceBounds(entity:GetPieceKind(), entity:GetPieceYaw())
    local origin = entity:GetPos()
    local found = ents.FindInBox(origin + Vector(minX, minY, minZ), origin + Vector(maxX, maxY, maxZ))
    for _, other in ipairs(found) do
        if IsValid(other) and other ~= entity and (other:IsPlayer() or other:IsNPC() or self:IsZombie(other)) then
            return true
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

local nextTickAt = 0
hook.Add("Think", "ZM.Construction.Tick", function()
    local now = CurTime()
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
