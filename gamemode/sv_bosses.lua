// Server-owned boss lifecycle state. Persistence is intentionally in-memory and profile-scoped for Phase I.
ZM_Bosses = ZM_Bosses or {}
local Bosses = ZM_Bosses

util.AddNetworkString("ZM.BossSnapshot")
Bosses.Profiles = Bosses.Profiles or {}
Bosses.NextInstanceId = Bosses.NextInstanceId or 0

local function profileState(profile)
    profile = type(profile) == "string" and profile ~= "" and profile or "city"
    Bosses.Profiles[profile] = Bosses.Profiles[profile] or { active = {}, lastSpawnAt = {} }
    return Bosses.Profiles[profile]
end

function Bosses:BroadcastSnapshot()
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local entries = {}
    for _, instance in pairs(profileState(profile).active) do
        if IsValid(instance.entity) then table.insert(entries, instance) end
    end
    net.Start("ZM.BossSnapshot")
        net.WriteString(profile)
        net.WriteUInt(math.min(#entries, 255), 8)
        for index = 1, math.min(#entries, 255) do
            local instance = entries[index]
            net.WriteUInt(instance.id, 32)
            net.WriteUInt(math.max(0, tonumber(instance.cellId) or 0), 16)
            net.WriteString(instance.bossId or "")
            net.WriteEntity(instance.entity)
        end
    net.Broadcast()
end

function Bosses:SendSnapshot(playerEntity)
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local entries = {}
    for _, instance in pairs(profileState(profile).active) do
        if IsValid(instance.entity) then table.insert(entries, instance) end
    end
    net.Start("ZM.BossSnapshot")
        net.WriteString(profile)
        net.WriteUInt(math.min(#entries, 255), 8)
        for index = 1, math.min(#entries, 255) do
            local instance = entries[index]
            net.WriteUInt(instance.id, 32)
            net.WriteUInt(math.max(0, tonumber(instance.cellId) or 0), 16)
            net.WriteString(instance.bossId or "")
            net.WriteEntity(instance.entity)
        end
    net.Send(playerEntity)
end

local function hasAllowedEnvironment(boss, cell)
    local allowed = boss.spawnConditions and boss.spawnConditions.allowedEnvironmentTags or {}
    if #allowed == 0 then return true end
    local environment = ZM_World:GetEnvironment(cell) or {}
    local tags = {}
    for _, tag in ipairs(environment.tags or {}) do tags[tag] = true end
    for _, tag in ipairs(allowed) do
        if tags[tag] then return true end
    end
    return false
end

function Bosses:GetEligibleCells(boss, worldData)
    local eligible = {}
    worldData = worldData or (ZM_World and ZM_World.Data)
    for _, cell in ipairs(worldData and worldData.cells or {}) do
        local minimumDanger = boss.spawnConditions and boss.spawnConditions.minCellDanger or 0
        if (ZM_World:GetDangerIntensity(cell) or 0) >= minimumDanger and hasAllowedEnvironment(boss, cell) then
            table.insert(eligible, cell)
        end
    end
    return eligible
end

function Bosses:GetActiveCount(profile, bossId)
    local count = 0
    for _, instance in pairs(profileState(profile).active) do
        if not bossId or instance.bossId == bossId then count = count + 1 end
    end
    return count
end

function Bosses:CanSpawn(boss, profile, now)
    local state = profileState(profile)
    local conditions = boss.spawnConditions or {}
    if self:GetActiveCount(profile, boss.id) >= (conditions.maxActiveWorldCount or 1) then
        return false, "maximum active boss count reached"
    end
    local lastSpawnAt = state.lastSpawnAt[boss.id]
    local cooldown = (conditions.cooldownHours or 0) * 3600
    if lastSpawnAt and (tonumber(now) or os.time()) - lastSpawnAt < cooldown then
        return false, "boss cooldown is active"
    end
    return true
end

function Bosses:BeginSpawn(boss, cell, profile, now)
    local canSpawn, reason = self:CanSpawn(boss, profile, now)
    if not canSpawn then return nil, reason end
    self.NextInstanceId = self.NextInstanceId + 1
    local instance = {
        id = self.NextInstanceId,
        bossId = boss.id,
        cellId = cell.id,
        profile = profile or "city",
        spawnedAt = tonumber(now) or os.time()
    }
    local state = profileState(profile)
    state.active[instance.id] = instance
    state.lastSpawnAt[boss.id] = instance.spawnedAt
    self:BroadcastSnapshot()
    return instance
end

function Bosses:Finish(instanceId, profile)
    local state = profileState(profile)
    if not state.active[instanceId] then return false, "unknown boss instance" end
    state.active[instanceId] = nil
    self:BroadcastSnapshot()
    return true
end

function Bosses:SpawnAtCell(boss, cell, profile, position, now)
    local instance, spawnError = self:BeginSpawn(boss, cell, profile, now)
    if not instance then return nil, spawnError end
    local enemy = ZM_StaticData:GetEnemy(boss.enemy)
    local entity = enemy and ents.Create(enemy.entity) or nil
    if not IsValid(entity) then
        self:Finish(instance.id, profile)
        return nil, "boss entity could not be created"
    end
    entity:SetPos(position)
    entity:Spawn()
    entity.BossInstanceId = instance.id
    entity.BossProfile = profile or "city"
    entity.BossId = boss.id
    entity:ApplyEnemyDefinition(enemy, ZM_World:GetDangerIntensity(cell) or 0)
    entity:SetZMCompassMarker(boss.mapMarker.icon, boss.mapMarker.label)
    instance.entity = entity
    self:BroadcastSnapshot()
    return instance, entity
end

function Bosses:OnBossKilled(entity, attacker)
    if entity.BossRewarded then return false, "already rewarded" end
    entity.BossRewarded = true
    local boss = ZM_StaticData:GetBoss(entity.BossId)
    local killer = ZM_Enemies.ResolveKiller(attacker)
    if not boss or not killer then return false, "boss or player killer is missing" end
    local enemy = ZM_StaticData:GetEnemy(boss.enemy)
    local reward = { boss = boss.id, xp = enemy.xp or 0, killer = killer:SteamID() }
    if reward.xp > 0 then ZM_Enemies.AwardXP(killer, reward.xp) end
    local instance = ZM_Loot:RollBossLoot(boss, { danger = entity.EnemyDanger, playerLevel = killer:GetLevel(), seed = entity.BossInstanceId })
    reward.item = instance
    reward.given = false
    reward.error = instance and nil or "boss loot could not be rolled"
    self:Finish(entity.BossInstanceId, entity.BossProfile)
    return true, reward
end

function Bosses:SpawnForPlayer(playerEntity, bossId)
    local boss = ZM_StaticData:GetBoss(bossId)
    local cell = IsValid(playerEntity) and playerEntity:GetWorldCell() or nil
    if not boss or not cell then return nil, "unknown boss or player cell" end
    local eligibleHere = false
    for _, candidate in ipairs(self:GetEligibleCells(boss)) do
        if candidate.id == cell.id then eligibleHere = true break end
    end
    if not eligibleHere then return nil, "current cell is not eligible for this boss" end
    return self:SpawnAtCell(boss, cell, ZM_World.ActiveProfile, playerEntity:GetPos())
end

function Bosses:Reset()
    self.Profiles = {}
end