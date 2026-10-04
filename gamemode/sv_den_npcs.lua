// Den NPCs (zn_den_npc): Hammer-placed point entities that act as a trader, a professional, or both.
// Keyvalues: profession (a profession id or alias; empty or "none" for a trader only), service_level (1..300; stands
// in for the player level cap), fees ("cook=5 treat=10"; overrides trade_definitions.json npcServiceFees), trader
// (a trader table id in trade_definitions.json), npc_name (falling back to Hammer targetname), and model. Settings are resolved against the live static
// data each time, so a reload takes effect at once; an unknown profession offers no services.
ZM_DenNpcs = ZM_DenNpcs or {}
local Npcs = ZM_DenNpcs
local StaticData = ZM_StaticData

Npcs.DefaultModel = "models/Humans/Group01/male_07.mdl"
Npcs.InteractionRange = 160
Npcs.DevSpawned = Npcs.DevSpawned or {}

util.AddNetworkString("ZM.DenNpc.Interact")

// Resolved settings: { job, level, services, fees, trader, traderName, name, problems }. job and trader are nil when
// absent or invalid; problems lists every setting that was rejected.
function Npcs:Resolve(npc)
    local config = npc.ZM_Config or {}
    local resolved = { level = 1, services = {}, fees = {}, problems = {} }
    local profession = string.Trim(tostring(config.profession or ""))
    if profession ~= "" and string.lower(profession) ~= "none" then
        local id, reason = ZM_ProfessionService:ResolveJob(profession)
        if id then
            resolved.job = id
        else
            table.insert(resolved.problems, reason)
        end
    end
    local level = tonumber(config.service_level or 1)
    if not level or level ~= math.floor(level) or level < 1 or level > StaticData.MaximumItemLevel then
        table.insert(resolved.problems, "service_level must be a whole number from 1 to " .. StaticData.MaximumItemLevel .. " (using 1)")
        level = 1
    end
    resolved.level = level
    local definition = resolved.job and StaticData:GetProfession(resolved.job)
    if definition then
        resolved.services = table.GetKeys(definition.services)
        table.sort(resolved.services)
    end
    local trade = StaticData:GetTrade()
    for _, kind in ipairs(resolved.services) do
        resolved.fees[kind] = trade and trade.npcServiceFees[kind] or 0
    end
    for kind, fee in string.gmatch(tostring(config.fees or ""), "(%a+)%s*=%s*(%-?%d+)") do
        fee = tonumber(fee)
        if not StaticData.ProfessionServices[kind] then
            table.insert(resolved.problems, "fees: unknown service '" .. kind .. "'")
        elseif not resolved.fees[kind] then
            table.insert(resolved.problems, "fees: " .. tostring(resolved.job or "this NPC") .. " does not offer " .. kind)
        elseif fee < 0 or fee > StaticData.MaximumNpcServiceFee then
            table.insert(resolved.problems, "fees: " .. kind .. " must be from 0 to " .. StaticData.MaximumNpcServiceFee)
        else
            resolved.fees[kind] = fee
        end
    end
    local traderId = string.Trim(tostring(config.trader or ""))
    if traderId ~= "" then
        local trader = StaticData:GetTrader(traderId)
        if trader then
            resolved.trader, resolved.traderName = traderId, trader.name
        else
            table.insert(resolved.problems, "unknown trader table '" .. traderId .. "'")
        end
    end
    local name = string.sub(string.Trim(tostring(config.npc_name or "")), 1, 32)
    if name == "" then
        name = string.sub(string.Trim(tostring(config.targetname or (npc.GetName and npc:GetName()) or "")), 1, 32)
    end
    resolved.name = name ~= "" and name or resolved.traderName or (definition and definition.name) or "Den Resident"
    return resolved
end

// Provider methods shared by the entity and test stubs. They let ZM_ProfessionService, crafting requirement checks,
// and medical items treat an NPC like a player provider (job, level, stats, name) without an inventory or cash.
Npcs.ProviderMethods = {
    ZM_IsDenNpc = true,
    Alive = function() return true end,
    Nick = function(self) return Npcs:Resolve(self).name end,
    GetLevel = function(self) return Npcs:Resolve(self).level end,
    GetJobRole = function(self) return Npcs:Resolve(self).job end,
    GetStat = function(self, name)
        local job = Npcs:Resolve(self).job
        return job and ZM_Professions:GetStatBonus(job, name) or 0
    end,
    GetServiceFee = function(self, kind) return Npcs:Resolve(self).fees[kind] end,
    GetTraderId = function(self) return Npcs:Resolve(self).trader end
}

// Copies the resolved display settings onto the entity's networked vars for the client.
function Npcs:Sync(npc)
    if not IsValid(npc) or not npc.SetNWString then return end
    local resolved = self:Resolve(npc)
    npc:SetNWString("ZM_NpcName", resolved.name)
    npc:SetNWString("ZM_NpcJob", resolved.job or "")
    npc:SetNWString("ZM_NpcTrader", resolved.trader or "")
    npc:SetNWInt("ZM_NpcLevel", resolved.level)
    if #resolved.problems > 0 then
        ErrorNoHalt("[ZombieSim] zn_den_npc " .. npc:EntIndex() .. " (" .. resolved.name .. "): " .. table.concat(resolved.problems, "; ") .. "\n")
    end
end

function Npcs:GetAll()
    return ents.FindByClass(StaticData.DenNpcClass)
end

function Npcs:CanInteract(target, npc, requireAim)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
        return false
    end
    if not IsValid(npc) or not npc.ZM_IsDenNpc or not ZM_InventoryService
        or not ZM_InventoryService:CanAccessStash(target) then
        return false
    end
    if target:GetPos():DistToSqr(npc:GetPos()) > self.InteractionRange * self.InteractionRange then
        return false
    end
    if requireAim then
        local aimTrace = target:GetEyeTrace()
        if not aimTrace or aimTrace.Entity ~= npc then
            return false
        end
    end
    local visibility = util.TraceLine({
        start = target:EyePos(),
        endpos = npc:WorldSpaceCenter(),
        filter = { target, npc },
        mask = MASK_SOLID
    })
    return not visibility.Hit
end

// Den NPCs within range of the target, nearest first.
function Npcs:FindNear(target, range)
    local found = {}
    if not target or not target.GetPos then return found end
    local origin = target:GetPos()
    for _, npc in ipairs(self:GetAll()) do
        local distance = origin:DistToSqr(npc:GetPos())
        if distance <= range * range then
            table.insert(found, { npc = npc, distance = distance })
        end
    end
    table.sort(found, function(left, right) return left.distance < right.distance end)
    local result = {}
    for _, entry in ipairs(found) do table.insert(result, entry.npc) end
    return result
end

net.Receive("ZM.DenNpc.Interact", function(length, target)
    if length ~= 16 or not IsValid(target) or not target:IsPlayer() then return end
    local npc = Entity(net.ReadUInt(16))
    if Npcs:CanInteract(target, npc, true) then
        npc:Use(target)
    end
end)

function Npcs:Describe(npc)
    local resolved = self:Resolve(npc)
    return {
        entIndex = npc.EntIndex and npc:EntIndex() or nil, name = resolved.name, job = resolved.job, level = resolved.level,
        services = resolved.services, fees = resolved.fees, trader = resolved.trader, problems = resolved.problems,
        config = npc.ZM_Config, devSpawned = npc.ZM_DevSpawned == true,
        pos = npc.GetPos and tostring(npc:GetPos()) or nil, model = npc.GetModel and npc:GetModel() or nil
    }
end

// Development: spawns a temporary NPC in front of the player. It is not saved; place real NPCs in Hammer.
function Npcs:SpawnDev(target, config, offset)
    local npc = ents.Create(StaticData.DenNpcClass)
    if not IsValid(npc) then return nil, "could not create a den NPC" end
    local forward = target:GetForward()
    forward.z = 0
    forward:Normalize()
    local right = forward:Cross(Vector(0, 0, 1))
    npc.ZM_Config = config
    npc.ZM_DevSpawned = true
    npc:SetPos(target:GetPos() + forward * 80 + right * (offset or 0))
    npc:SetAngles(Angle(0, target:EyeAngles().y + 180, 0))
    npc:Spawn()
    table.insert(self.DevSpawned, npc)
    return npc
end

// ---------------------------------------------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------------------------------------------

local firstHuman = ZM_Util.FirstHuman

local function runNpcCommand(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command, { zn_den_npcs = true }) then return false, "not an admin" end
    local target = IsValid(caller) and caller or firstHuman()
    local ok, message = true, nil
    if command == "zn_dev_spawn_den_npc" then
        // zn_dev_spawn_den_npc <profession|none> [level] [trader|-] [offset] [fees]
        if not target then return false, "no target player" end
        local config = {
            profession = arguments[1] or "none",
            service_level = arguments[2] or "1",
            trader = (arguments[3] and arguments[3] ~= "-") and arguments[3] or "",
            fees = arguments[5] or ""
        }
        local npc, spawnError = Npcs:SpawnDev(target, config, tonumber(arguments[4]) or 0)
        ok = npc ~= nil
        message = npc and ("spawned temporary den NPC " .. npc:EntIndex() .. " (" .. Npcs:Resolve(npc).name .. ")") or spawnError
    elseif command == "zn_dev_clear_den_npcs" then
        local removed = 0
        for _, npc in ipairs(Npcs.DevSpawned) do
            if IsValid(npc) then
                npc:Remove()
                removed = removed + 1
            end
        end
        Npcs.DevSpawned = {}
        message = "removed " .. removed .. " temporary den NPC(s)"
    end
    local described = {}
    for _, npc in ipairs(Npcs:GetAll()) do
        if IsValid(npc) and not (command == "zn_dev_clear_den_npcs" and npc.ZM_DevSpawned) then
            local entry = Npcs:Describe(npc)
            entry.distance = target and math.floor(target:GetPos():Distance(npc:GetPos())) or nil
            table.insert(described, entry)
        end
    end
    message = message or (#described .. " den NPC(s) on this map")
    local line = "[ZombieSim] " .. command .. ": " .. tostring(message)
    ZM_Util.Print(caller, line)
    for _, entry in ipairs(described) do
        local detail = string.format("  #%d %s: job %s lvl %d, trader %s%s", entry.entIndex or -1, entry.name, tostring(entry.job or "-"), entry.level, tostring(entry.trader or "-"),
            #entry.problems > 0 and (" [" .. table.concat(entry.problems, "; ") .. "]") or "")
        ZM_Util.Print(caller, detail)
    end
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("denNpcs", { command = command, ok = ok, message = message, npcs = described })
    end
    if not ok then return false, tostring(message) end
    return true
end

ZM_Util.RegisterCommands({
    zn_den_npcs = "Lists the den NPCs on this map with their resolved profession, level, fees, trader table, and any rejected settings.",
    zn_dev_spawn_den_npc = "Development: zn_dev_spawn_den_npc <profession|none> [level] [trader|-] [sideOffset] [fees]: spawns a temporary den NPC in front of the player.",
    zn_dev_clear_den_npcs = "Development: removes the temporary den NPCs spawned by zn_dev_spawn_den_npc."
}, runNpcCommand)
