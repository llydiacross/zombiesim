// Server-authoritative structure land claims. A claim token in the backpack claims one eligible core tile of the
// player's current city cell; the token and the claim row commit in one inventory transaction. Claims belong to the
// claiming survivor; the owner's Steam account and the owner's friend accounts share access. A claim lapses after
// ZM_ClaimLifetimeSeconds without a visit by anyone with access, and a lapsed tile can be claimed again.
ZM_ClaimService = ZM_ClaimService or {}
local Service = ZM_ClaimService

Service.TokenItemId = "itemClaimToken"
// A visit counts while the player stands within one tile of a claimed tile centre (inclusive of the tile itself).
Service.VisitReach = 1.5
Service.VisitInterval = 60
Service.Now = Service.Now or os.time

local steamAccountPattern = "^STEAM_[0-5]:[01]:%d+$"

local function baseMapName(path)
    return string.lower(string.match(path or "", "([^/]+)$") or path or "")
end

function Service:Identity(target)
    if not IsValid(target) or not target.SteamID or (target.IsBot and target:IsBot())
        or target.ZM_PersistentStateLoaded ~= true then
        return nil, "An active survivor is required."
    end
    local account = target:SteamID()
    local profile = ZM_Util.ProfileFor(target)
    local character, characterError = ZM_Util.CharacterKeyFor(target)
    if type(account) ~= "string" or not string.match(account, steamAccountPattern)
        or type(profile) ~= "string" or not string.match(profile, "^[a-z0-9_-]+$")
        or type(character) ~= "string" or character == "" then
        return nil, "Invalid claim owner: " .. tostring(characterError or "account, profile or survivor")
    end
    return { account = account, profile = profile, character = character }
end

// The loaded city cell the player is standing in, or nil with a reason (dens and other maps are not claimable).
function Service:CurrentCell(target)
    if type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" then
        return nil, "Land cannot be claimed inside a den."
    end
    local cell = target.GetWorldCell and target:GetWorldCell() or nil
    if not cell then return nil, "You are not in a city cell." end
    if ZM_SafeZones and ZM_SafeZones:IsSafeZoneCell(cell) then
        return nil, "Land cannot be claimed in a safe-zone cell."
    end
    if baseMapName(ZM_World:GetMapPath(cell)) ~= baseMapName(game.GetMap()) then
        return nil, "This cell's map is not loaded."
    end
    return cell
end

function Service.IsActive(row, now)
    return type(row) == "table" and (tonumber(row.lastVisitAt) or 0) >= now - ZM_ClaimLifetimeSeconds
end

// Friend accounts for each owner, read once per call site and cached in the supplied table.
function Service:FriendsOf(profile, owner, cache)
    if cache and cache[owner] then return cache[owner] end
    local accounts, readError = ZM_GetClaimFriends(profile, owner)
    if not accounts then return nil, readError end
    local set = {}
    for _, account in ipairs(accounts) do set[account] = true end
    if cache then cache[owner] = set end
    return set
end

function Service:HasAccess(identity, row, friendCache)
    if row.owner == identity.character or row.account == identity.account then return true end
    local friends = self:FriendsOf(identity.profile, row.owner, friendCache)
    return friends ~= nil and friends[identity.account] == true
end

local function tileCentre(tileX, tileY)
    local tileSize = tonumber(ZM_World:GetCellBounds().tileSize) or 640
    return tileX * tileSize, tileY * tileSize, tileSize
end

local function isNear(position, tileX, tileY)
    local centreX, centreY, tileSize = tileCentre(tileX, tileY)
    local reach = tileSize * Service.VisitReach
    return math.abs(position.x - centreX) <= reach and math.abs(position.y - centreY) <= reach
end

// Claims a core tile of the current cell. Without coordinates it claims the tile the player stands on; explicit
// coordinates must be the player's tile or a neighbouring one.
function Service:ClaimTile(target, tileX, tileY)
    if not self.StorageReady then return false, "Land-claim storage is unavailable." end
    local identity, identityError = self:Identity(target)
    if not identity then return false, identityError end
    local cell, cellError = self:CurrentCell(target)
    if not cell then return false, cellError end
    local standingX, standingY = ZM_World:GetCoreTileAt(target:GetPos())
    if tileX == nil and tileY == nil then
        tileX, tileY = standingX, standingY
        if tileX == nil then return false, "Stand inside the cell's core tiles to claim land." end
    end
    if not ZM_Util.IsWholeNumber(tileX, -2, 2) or not ZM_Util.IsWholeNumber(tileY, -2, 2) then
        return false, "Invalid tile."
    end
    if not ZM_World:IsClaimableTile(cell.id, tileX, tileY) then
        return false, "That tile cannot be claimed."
    end
    if not isNear(target:GetPos(), tileX, tileY) then
        return false, "Move closer to the tile to claim it."
    end
    local now = math.floor(self.Now())
    local saved, saveError = ZM_InventoryService:Mutate(target, function(draft)
        return ZM_InventoryService.Ops.Remove(draft, "backpack", self.TokenItemId, 1)
    end, {
        extraSteps = function()
            return { {
                kind = "claimCreate", steamid = identity.character, account = identity.account,
                cellId = cell.id, tileX = tileX, tileY = tileY, now = now
            } }
        end
    })
    if not saved then return false, saveError end
    target.ZM_ClaimVisitAt = now
    return true, { cellId = cell.id, tileX = tileX, tileY = tileY }
end

// Refreshes every active claim near the player that the player can access. Throttled per player unless forced.
// Returns the number of claims refreshed.
function Service:RecordVisit(target, force)
    if not self.StorageReady then return false, "Land-claim storage is unavailable." end
    local now = math.floor(self.Now())
    if not force and target.ZM_ClaimVisitAt and now - target.ZM_ClaimVisitAt < self.VisitInterval then
        return true, 0
    end
    local identity, identityError = self:Identity(target)
    if not identity then return false, identityError end
    local cell, cellError = self:CurrentCell(target)
    if not cell then return false, cellError end
    target.ZM_ClaimVisitAt = now
    local rows, readError = ZM_GetCellClaims(identity.profile, cell.id)
    if not rows then return false, readError end
    local position = target:GetPos()
    local friendCache = {}
    local steps = {}
    for _, row in ipairs(rows) do
        if self.IsActive(row, now) and row.lastVisitAt < now and isNear(position, row.tileX, row.tileY)
            and self:HasAccess(identity, row, friendCache) then
            steps[#steps + 1] = {
                kind = "claimVisit", steamid = identity.character, owner = row.owner,
                cellId = cell.id, tileX = row.tileX, tileY = row.tileY, now = now
            }
        end
    end
    if #steps == 0 then return true, 0 end
    local saved, saveError = ZM_CommitWrites(identity.profile, steps)
    if not saved then return false, saveError end
    return true, #steps
end

local function changeFriend(self, target, account, kind)
    if not self.StorageReady then return false, "Land-claim storage is unavailable." end
    local identity, identityError = self:Identity(target)
    if not identity then return false, identityError end
    if type(account) ~= "string" or not string.match(account, steamAccountPattern) then
        return false, "Use a Steam account ID such as STEAM_0:1:12345."
    end
    if account == identity.account then return false, "Your own account already has access." end
    return ZM_CommitWrites(identity.profile, { { kind = kind, steamid = identity.character, friendAccount = account } })
end

function Service:AddFriend(target, account)
    return changeFriend(self, target, account, "claimFriendAdd")
end

function Service:RemoveFriend(target, account)
    return changeFriend(self, target, account, "claimFriendRemove")
end

// The current cell's claims as seen by the player: tile, whether active, and whether the player has access.
function Service:CellSnapshot(target)
    local identity, identityError = self:Identity(target)
    if not identity then return nil, identityError end
    local cell, cellError = self:CurrentCell(target)
    if not cell then return nil, cellError end
    local rows, readError = ZM_GetCellClaims(identity.profile, cell.id)
    if not rows then return nil, readError end
    local now = math.floor(self.Now())
    local friendCache = {}
    local claims = {}
    for _, row in ipairs(rows) do
        claims[#claims + 1] = {
            tileX = row.tileX, tileY = row.tileY, active = self.IsActive(row, now),
            mine = row.owner == identity.character, access = self:HasAccess(identity, row, friendCache),
            expiresAt = row.lastVisitAt + ZM_ClaimLifetimeSeconds
        }
    end
    return { cellId = cell.id, claimable = ZM_World:GetClaimTiles(cell.id), claims = claims }
end

// Server-only reward path (quests and similar): grants claim tokens to the backpack.
function Service:GrantToken(target, count, reason)
    count = count or 1
    if not ZM_Util.IsWholeNumber(count, 1, 10) then return false, "Token grants must be from 1 to 10." end
    local granted, grantError = ZM_InventoryService:GiveItem(target, self.TokenItemId, count)
    if not granted then return false, grantError end
    print(string.format("[ZombieSim] Granted %d claim token(s) to %s (%s).", count, tostring(target), tostring(reason or "reward")))
    return true
end

if SERVER and timer and not Service.TimerCreated then
    Service.TimerCreated = true
    timer.Create("ZM_ClaimVisits", 15, 0, function()
        if not Service.StorageReady then return end
        for _, candidate in ipairs(player.GetHumans()) do
            if candidate.ZM_PersistentStateLoaded == true then
                Service:RecordVisit(candidate)
            end
        end
    end)
end

if SERVER and ZM_Util and ZM_Util.RegisterCommands and concommand then
    ZM_Util.RegisterCommands({
        zn_claim_tile = "Claims the core tile you stand on (or an adjacent tile: zn_claim_tile <x> <y>) using one claim token.",
        zn_claim_status = "Lists the land claims in your current cell.",
        zn_claim_friend_add = "Gives a Steam account access to your survivor's claims: zn_claim_friend_add STEAM_0:1:12345",
        zn_claim_friend_remove = "Removes a Steam account's access to your survivor's claims."
    }, function(caller, command, arguments)
        local target = IsValid(caller) and caller or ZM_Util.FirstHuman()
        if not target then
            ZM_Util.Reply(caller, command .. " needs a connected player.")
            return false, "no player"
        end
        local ok, result
        if command == "zn_claim_tile" then
            local tileX, tileY = tonumber(arguments[1]), tonumber(arguments[2])
            if (arguments[1] or "") ~= "" and (tileX == nil or tileY == nil) then
                ZM_Util.Reply(caller, "Usage: zn_claim_tile [x y]")
                return false, "bad arguments"
            end
            ok, result = Service:ClaimTile(target, tileX, tileY)
            if ok then result = string.format("Claimed tile %d,%d in cell %d.", result.tileX, result.tileY, result.cellId) end
        elseif command == "zn_claim_status" then
            local snapshot, snapshotError = Service:CellSnapshot(target)
            ok, result = snapshot ~= nil, snapshotError
            if snapshot then
                ZM_Util.Reply(caller, string.format("Cell %d: %d claimable tiles, %d claim rows.", snapshot.cellId, #snapshot.claimable, #snapshot.claims))
                for _, claim in ipairs(snapshot.claims) do
                    ZM_Util.Reply(caller, string.format("  %d,%d %s%s%s", claim.tileX, claim.tileY,
                        claim.active and "active" or "lapsed", claim.mine and " (yours)" or "", claim.access and " access" or ""))
                end
                result = "ok"
            end
        else
            local account = arguments[1]
            if command == "zn_claim_friend_add" then
                ok, result = Service:AddFriend(target, account)
            else
                ok, result = Service:RemoveFriend(target, account)
            end
            if ok then result = command == "zn_claim_friend_add" and "Friend added." or "Friend removed." end
        end
        ZM_Util.Reply(caller, ok and tostring(result) or ("Claim failed: " .. tostring(result)))
        return ok, result
    end)
end
