local Contract = include("prefabs/sh_contract.lua")
local PrefabLoot = include("prefabs/sv_loot.lua")(ZM_StaticData)
local Catalog = include("prefabs/sv_catalog.lua")(file, util, Contract, util.IsValidModel, PrefabLoot.Validate)
local Spawn = include("prefabs/sv_spawn.lua")(Contract, {
    Vector = Vector, Angle = Angle, IsValid = IsValid, LocalToWorld = LocalToWorld, util = util, ents = ents,
    ResolveLoot = PrefabLoot.Resolve
})
local FixtureSpawn = include("prefabs/sv_spawn.lua")(Contract, {
    Vector = Vector, Angle = Angle, IsValid = IsValid, LocalToWorld = LocalToWorld, util = util, ents = ents,
    ResolveLoot = PrefabLoot.Resolve, AllowFixtureScale = true
})
local FixtureTrace = include("prefabs/sh_fixture_trace.lua")({
    IsValid = IsValid, Vector = Vector, Angle = Angle, LocalToWorld = LocalToWorld,
    util = util, MASK_SOLID = MASK_SOLID
})
ZM_Prefabs = {}
local Prefabs = ZM_Prefabs

local function baseMap(path)
    return string.lower(string.match(path or "", "([^/]+)$") or "")
end

function Prefabs:Cleanup()
    for _, instance in pairs(self.Instances or {}) do Spawn.Remove(instance.entities) end
    self.Instances, self.CellId, self.Profile, self.Failure = nil, nil, nil, nil
end

function Prefabs:GetStatus()
    local anchors, props = 0, 0
    local instances = {}
    for anchorId, instance in pairs(self.Instances or {}) do
        anchors = anchors + 1
        instances[#instances + 1] = { anchorId = anchorId, prefabId = instance.id }
        for _, entity in ipairs(instance.entities) do
            if IsValid(entity) then props = props + 1 end
        end
    end
    return { ready = self.Ready == true, map = game.GetMap(), profile = self.Profile or ZM_World.ActiveProfile,
        cellId = self.CellId, anchors = anchors, props = props, instances = instances, error = self.Failure }
end

function Prefabs:OnPlayerReady(target)
    if not IsValid(target) or target.ZM_PersistentStateLoaded ~= true then return true end
    if not self.Ready then return nil, "Prefab map initialization is pending." end
    if type(target.CurrentSafeZoneId) == "string" and target.CurrentSafeZoneId ~= "" then return true end
    local cell, cellError = target:GetWorldCell()
    if not cell then return false, cellError or "Prefab spawning requires a world cell." end
    if ZM_SafeZones:IsSafeZoneCell(cell) or baseMap(ZM_World:GetMapPath(cell)) ~= baseMap(game.GetMap()) then return true end
    return self:SpawnForCell(cell.id)
end

function Prefabs:SpawnForCell(cellId, fixture)
    if fixture and not ZM_PrefabEditor:IsFixtureMap() then
        return false, "Experimental scale is restricted to the isolated prefab fixture."
    end
    if self.Instances then
        if self.CellId ~= cellId or self.Profile ~= ZM_World.ActiveProfile then
            return false, "Prefab world cell differs from the active map session."
        end
        return self.Failure == nil, self.Failure
    end
    local anchors = ents.FindByClass("zn_prefab_anchor")
    if #anchors == 0 then return true end
    local documents, problem = Catalog.Load()
    if not documents then self.Failure = problem return false, problem end
    self.Failure = nil
    self.Instances, self.CellId, self.Profile = {}, cellId, ZM_World.ActiveProfile
    local data = ZM_World:GetData()
    for _, anchor in ipairs(anchors) do
        local keys = anchor.ZM_Config or {}
        if keys.instance_local ~= "1" or keys.zm_instance_transformed == "1" then
            local id = anchor:MapCreationID()
            local tags = {}
            for tag in string.gmatch(keys.prefab_tags or "", "[^,]+") do
                tags[#tags + 1] = string.Trim(tag)
            end
            local document, selectionError = Catalog.Select(documents, tags, self.Profile,
                data and data.world and data.world.seed, cellId, id)
            local entities, spawnError
            if document then entities, spawnError = (fixture and FixtureSpawn or Spawn).Create(document, anchor) end
            if not entities then
                self.Failure = "Prefab anchor " .. tostring(id) .. ": " .. tostring(selectionError or spawnError)
                ErrorNoHalt("[ZombieSim] " .. self.Failure .. "\n")
            else
                self.Instances[id] = { id = document.id, entities = entities }
            end
        end
    end
    return self.Failure == nil, self.Failure
end

local function prepareConnectedPlayers()
    Prefabs.Ready = true
    for _, target in ipairs(player.GetHumans()) do
        local ok, problem = Prefabs:OnPlayerReady(target)
        if not ok then ErrorNoHalt("[ZombieSim] " .. tostring(problem) .. "\n") end
        if IsValid(target) and target.ZM_PersistentStateLoaded == true then
            ZM_Loading:Step(target, ok and "Prepared prefab props" or "Prefab props unavailable",
                ok and "ok" or "warn")
            ZM_LootSpots:OnPlayerReady(target)
            ZM_Loading:Step(target, "Prepared loot spots")
        end
    end
end

hook.Add("InitPostEntity", "ZM.Prefabs.Ready", function()
    timer.Simple(0, prepareConnectedPlayers)
end)
hook.Add("PreCleanupMap", "ZM.Prefabs.Cleanup", function()
    Prefabs.Ready = false
    Prefabs:Cleanup()
end)
hook.Add("PostCleanupMap", "ZM.Prefabs.Restore", function()
    timer.Simple(0, prepareConnectedPlayers)
end)

ZM_Util.RegisterCommands({
    zombiesim_prefab_status = "Reports loaded prefab anchors and surviving owned props.",
    zombiesim_prefab_fixture_spawn = "Spawns the isolated prefab fixture using a synthetic cell.",
    zombiesim_prefab_fixture_trace = "Compares server and client traces on the isolated prefab fixture."
}, function(caller, command, arguments)
    if not ZM_Util.RequireAdmin(caller, command) then return false, "Admin access required." end
    if command == "zombiesim_prefab_fixture_spawn" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not Prefabs.Ready or not ZM_PrefabEditor:IsFixtureMap()
            or not ZM_PrefabEditor:IsParticipant(target) or target.ZM_PersistentStateLoaded == true
            or ZM_World.ActiveProfile ~= "preview" then
            return false, "The isolated prefab fixture requires its sole preview admin and no loaded survivor."
        end
        return Prefabs:SpawnForCell(0, true)
    elseif command == "zombiesim_prefab_fixture_trace" then
        local target = ZM_Util.ResolveCommandTarget(caller, command)
        if not ZM_PrefabEditor:IsFixtureMap() or not ZM_PrefabEditor:IsParticipant(target)
            or target.ZM_PersistentStateLoaded == true or not Prefabs.Instances then
            return false, "The isolated prefab fixture and its owner are required for collision traces."
        end
        local mode = arguments and arguments[1] or ""
        if mode ~= "" and mode ~= "activate_client" then return false, "Invalid fixture trace mode." end
        local samples, errors = {}, {}
        for _, instance in pairs(Prefabs.Instances) do
            for _, entity in ipairs(instance.entities) do
                local sample, problem = FixtureTrace.Sample(entity)
                if sample then samples[#samples + 1] = sample else errors[#errors + 1] = problem end
            end
        end
        local requestId = tostring(math.floor(CurTime() * 1000))
        if ZM_DevConsole and ZM_DevConsole.Report then
            ZM_DevConsole:Report("prefabFixtureTrace", { requestId = requestId, mode = mode, samples = samples, errors = errors })
        end
        target:ConCommand("zombiesim_dev_prefab_fixture_trace_client " .. requestId .. " " .. mode)
        if #errors > 0 then return false, table.concat(errors, " | ") end
        return true
    end
    local status = Prefabs:GetStatus()
    if ZM_DevConsole and ZM_DevConsole.Report then ZM_DevConsole:Report("prefabs", status) end
    ZM_Util.Reply(caller, string.format("Prefabs: %d anchors, %d props; %s.",
        status.anchors, status.props, status.error or "no errors"))
    return true
end)
