// Server-only enemy selection for Walker spawns and kill rewards (XP and loot drops).
// Walker tickets stay generic; the enemy type is chosen here after a ticket is reserved, seeded by the ticket id.
ZM_Enemies = ZM_Enemies or {}
local Enemies = ZM_Enemies
local Generation = ZM_ItemGeneration

local function clampDanger(danger)
    return math.Clamp(tonumber(danger) or 0, 0, 1)
end

// 0..1 position of a danger value within the enemy's own minDanger..maxDanger range.
function Enemies.GetDangerProgress(enemy, danger)
    local minimum, maximum = enemy.minDanger or 0, enemy.maxDanger or 1
    if maximum <= minimum then
        return 1
    end
    return math.Clamp((clampDanger(danger) - minimum) / (maximum - minimum), 0, 1)
end

// Bosses never spawn from spawn groups; both danger bounds are inclusive.
function Enemies.IsEligible(enemy, danger)
    danger = clampDanger(danger)
    return not enemy.boss and danger >= (enemy.minDanger or 0) and danger <= (enemy.maxDanger or 1)
end

// Ticket spawns need an entity class that implements the Walker ticket and enemy-definition interface.
function Enemies.SupportsWalkerTickets(className)
    local stored = scripted_ents.GetStored(className)
    local entityTable = stored and stored.t
    return entityTable ~= nil and isfunction(entityTable.SetWalkerTicket) and isfunction(entityTable.ApplyEnemyDefinition)
end

function Enemies.GetGroupIds(tags, registry)
    local groupIds, seen = {}, {}
    for _, tag in ipairs(tags or {}) do
        local groupId = registry.environmentTags[tag]
        if groupId and not seen[groupId] then
            seen[groupId] = true
            table.insert(groupIds, groupId)
        end
    end
    if #groupIds == 0 and registry.defaultSpawnGroup then
        table.insert(groupIds, registry.defaultSpawnGroup)
    end
    return groupIds
end

// Eligible enemies for a context { danger, tags, skipEntityCheck } with interpolated weights.
// Matching spawn groups combine into one pool; a later group replaces an earlier group's weights for the same enemy.
function Enemies:GetCandidates(context, registry)
    registry = registry or ZM_StaticData:GetRegistry()
    if not registry then
        return {}, 0, {}
    end
    local danger = clampDanger(context.danger)
    local groupIds = self.GetGroupIds(context.tags, registry)
    local order, entries = {}, {}
    for _, groupId in ipairs(groupIds) do
        local group = registry.spawnGroups[groupId]
        for _, entry in ipairs(group and group.enemies or {}) do
            if not entries[entry.enemy] then
                table.insert(order, entry.enemy)
            end
            entries[entry.enemy] = entry
        end
    end

    local candidates, total = {}, 0
    for _, enemyId in ipairs(order) do
        local enemy = registry.enemies[enemyId]
        if enemy and self.IsEligible(enemy, danger) and (context.skipEntityCheck or self.SupportsWalkerTickets(enemy.entity)) then
            local entry = entries[enemyId]
            local weight = Lerp(self.GetDangerProgress(enemy, danger), entry.minSpawnWeight or 0, entry.maxSpawnWeight or 0)
            if weight > 0 then
                table.insert(candidates, { enemy = enemy, weight = weight })
                total = total + weight
            end
        end
    end
    return candidates, total, groupIds
end

// Picks one enemy definition for a spawn, or returns nil and a reason when nothing is eligible.
function Enemies:Pick(context, rng, registry)
    local candidates, total, groupIds = self:GetCandidates(context, registry)
    if total <= 0 then
        return nil, string.format("no eligible enemy in spawn groups [%s] at danger %.2f", table.concat(groupIds, ", "), clampDanger(context.danger))
    end
    local roll = rng:Next() * total
    local cumulative = 0
    for _, candidate in ipairs(candidates) do
        cumulative = cumulative + candidate.weight
        if roll < cumulative then
            return candidate.enemy
        end
    end
    return candidates[#candidates].enemy
end

function Enemies:GetCellContext(cell)
    local environment = ZM_World:GetEnvironment(cell) or {}
    return { danger = ZM_World:GetDangerIntensity(cell) or 0, tags = environment.tags or {} }
end

// The same ticket always selects the same enemy type.
function Enemies.GetTicketSeed(ticket)
    local low = math.floor(tonumber(ticket.TicketIdLow) or 0)
    local high = math.floor(tonumber(ticket.TicketIdHigh) or 0)
    return (low * 31 + high) % 2147483646 + 1
end

function Enemies.ResolveKiller(attacker)
    if not IsValid(attacker) then
        return nil
    end
    if attacker:IsPlayer() then
        return attacker
    end
    local owner = attacker.GetOwner and attacker:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then
        return owner
    end
    return nil
end

function Enemies.AwardXP(killer, amount)
    killer:AddXP(amount)
    if killer.UpdatePlayerData then
        killer:UpdatePlayerData("enemy kill")
        killer:SetNetworkPlayerData()
        killer:SendPlayerData()
    end
end

function Enemies:RegisterCorpseLoot(corpse, item, key)
    if not IsValid(corpse) then
        return false, "the enemy corpse is unavailable"
    end
    if type(item) ~= "table" then
        return false, "the corpse loot item is invalid"
    end
    if not ZM_LootSpots then
        return false, "the loot-spot service is unavailable"
    end

    key = type(key) == "string" and key ~= "" and key or ("enemycorpse_" .. corpse:EntIndex())
    local spot, spotError = ZM_LootSpots:RegisterRuntimeSpot(corpse, item, key)
    if not spot then
        return false, spotError or "the corpse loot spot could not be registered"
    end
    return true, spot
end

// Rewards the player who killed an enemy with XP and rolls loot onto its corpse. Runs at most once per victim;
// despawned enemies never reach this. Returns true and the reward, or false and a reason.
function Enemies:OnEnemyKilled(victim, attacker, options)
    if victim.EnemyRewarded then
        return false, "already rewarded"
    end
    victim.EnemyRewarded = true
    local enemy = victim.EnemyId and ZM_StaticData:GetEnemy(victim.EnemyId)
    if not enemy then
        return false, "victim has no enemy definition"
    end
    local killer = self.ResolveKiller(attacker)
    if not killer then
        return false, "not killed by a player"
    end

    local reward = { enemy = enemy.id, xp = enemy.xp or 0, killer = killer.SteamID and killer:SteamID() or nil }
    if reward.xp > 0 then
        self.AwardXP(killer, reward.xp)
    end
    local instance = ZM_Loot:RollEnemyDrop(enemy, {
        danger = victim.EnemyDanger,
        playerLevel = killer.GetLevel and killer:GetLevel() or 1,
        lootBonuses = ZM_ImplantService:GetLootBonuses(killer),
        rng = options and options.rng
    })
    if instance then
        reward.item = instance
    end
    victim.EnemyReward = reward
    return true, reward
end

local reply = ZM_Util.Reply

local resolveTarget = ZM_Util.ResolveCommandTarget

// Spawns a development enemy in front of the player without a Walker ticket (it is never counted or despawned by the materializer).
local function spawnEnemy(caller, arguments)
    local target = resolveTarget(caller, "zn_spawn_enemy")
    if not target then
        return false, "no target player"
    end
    local cell = target:GetWorldCell()
    if not cell then
        return false, "player has no world cell"
    end
    local context = Enemies:GetCellContext(cell)
    if tonumber(arguments[2]) then
        context.danger = clampDanger(arguments[2])
    end
    local enemy, reason
    if arguments[1] and arguments[1] ~= "" and arguments[1] ~= "auto" then
        enemy = ZM_StaticData:GetEnemy(arguments[1])
        reason = "unknown enemy '" .. tostring(arguments[1]) .. "'"
    else
        enemy, reason = Enemies:Pick(context, Generation.NewRng())
    end
    if not enemy then
        reply(caller, "zn_spawn_enemy: " .. tostring(reason))
        return false, reason
    end
    if not Enemies.SupportsWalkerTickets(enemy.entity) then
        reply(caller, "zn_spawn_enemy: " .. enemy.entity .. " does not support enemy definitions")
        return false, "unsupported entity"
    end

    local origin, direction = target:GetLevelAim()
    local ahead = util.TraceLine({ start = origin, endpos = origin + direction * 250, filter = target, mask = MASK_NPCSOLID_BRUSHONLY })
    local ground = util.TraceLine({ start = ahead.HitPos - direction * 32, endpos = ahead.HitPos - direction * 32 - Vector(0, 0, 512), mask = MASK_NPCSOLID_BRUSHONLY })
    local zombie = ents.Create(enemy.entity)
    if not IsValid(zombie) then
        return false, "could not create " .. enemy.entity
    end
    zombie:SetPos(ground.HitPos + Vector(0, 0, 4))
    zombie:SetAngles(Angle(0, direction:Angle().y + 180, 0))
    zombie:Spawn()
    zombie:Activate()
    zombie.WalkerSourceCellId = cell.id
    zombie:ApplyEnemyDefinition(enemy, context.danger)
    reply(caller, string.format("Spawned %s (%s) at danger %.2f with %d HP.", enemy.id, enemy.entity, context.danger, zombie:Health()))
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("enemySpawn", { enemy = enemy.id, danger = context.danger, health = zombie:Health(), walkSpeed = zombie.WalkSpeed })
    end
    return true
end

// Kills every defined enemy near the player with damage credited to that player, exercising the reward path.
local function killEnemies(caller)
    local target = resolveTarget(caller, "zn_kill_enemies")
    if not target then
        return false, "no target player"
    end
    local weapon = target:GetActiveWeapon()
    local rewards = {}
    for _, zombie in ipairs(ents.FindInSphere(target:GetPos(), 3000)) do
        if IsValid(zombie) and zombie.EnemyId and not zombie.WalkerDead then
            local damage = DamageInfo()
            damage:SetDamage(zombie:Health() + 100)
            damage:SetDamageType(DMG_BULLET)
            damage:SetAttacker(target)
            damage:SetInflictor(IsValid(weapon) and weapon or target)
            zombie:TakeDamageInfo(damage)
            table.insert(rewards, zombie.EnemyReward or { enemy = zombie.EnemyId, rewarded = false })
        end
    end
    reply(caller, "Killed " .. #rewards .. " enemy(s).")
    for _, reward in ipairs(rewards) do
        reply(caller, string.format("  %s: +%s XP%s", tostring(reward.enemy), tostring(reward.xp or 0), reward.item and (", dropped " .. reward.item.itemId .. " x" .. reward.item.count) or ""))
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("enemyKills", { rewards = rewards, xp = target.XP, level = target.Level })
    end
    return true
end

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
for command, definition in pairs({
    zn_spawn_enemy = { run = spawnEnemy, help = "zn_spawn_enemy [enemyId|auto] [danger]: spawns an enemy in front of the player (not Walker-ticketed)." },
    zn_kill_enemies = { run = killEnemies, help = "zn_kill_enemies: kills nearby defined enemies, credited to the player, to test rewards." }
}) do
    concommand.Add(command, function(caller, _, arguments)
        definition.run(caller, arguments)
    end, nil, definition.help)
    ZM_DevConsole.DirectCommands[command] = function(argumentString)
        return definition.run(nil, string.Explode("%s+", argumentString or "", true))
    end
end
