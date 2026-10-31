local playerMeta = {}
local hooks, timers, receivers, networkNames = {}, {}, {}, {}

function FindMetaTable(name)
    assert(name == "Player")
    return playerMeta
end

function string.Trim(value)
    return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", ""))
end

function string.GetFileFromFilename(path)
    return string.match(path, "([^/\\]+)$")
end

function table.Copy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and table.Copy(value) or value
    end
    return copy
end

function table.HasValue(source, value)
    for _, entry in pairs(source) do if entry == value then return true end end
    return false
end

function table.GetKeys(source)
    local keys = {}
    for key in pairs(source) do keys[#keys + 1] = key end
    return keys
end

function table.Count(source)
    local count = 0
    for _ in pairs(source) do count = count + 1 end
    return count
end

function math.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

function IsValid(value)
    return type(value) == "table" and value.valid == true
end

local clock = 0
function SysTime()
    clock = clock + 0.001
    return clock
end

local errors = {}
function ErrorNoHalt(message) errors[#errors + 1] = message end

util = {}
function util.AddNetworkString(name) networkNames[name] = true end
function util.IsValidModel(path) return string.find(path, "models/player/group01/", 1, true) == 1 end

ents = {}
function ents.Create(class)
    assert(class == "prop_dynamic")
    return {
        valid = true,
        SetModel = function(self, model) self.model = model end,
        SkinCount = function() return 1 end,
        GetBodyGroups = function() return {} end,
        Remove = function(self) self.valid = false end
    }
end

hook = {}
function hook.Add(event, id, callback)
    assert(type(event) == "string" and type(id) == "string" and type(callback) == "function")
    hooks[id] = callback
end

timer = {}
function timer.Create(id, interval, repetitions, callback)
    assert(type(id) == "string" and type(interval) == "number"
        and type(repetitions) == "number" and type(callback) == "function")
    timers[id] = callback
end

net = {}
function net.Receive(name, callback)
    assert(type(name) == "string" and type(callback) == "function")
    receivers[name] = callback
end
function net.Start(name)
    assert(name == "ZM.RefreshPlayerData" or name == "ZM.RefreshPlayerAttributes")
    net.current = { name = name }
end
function net.WriteString(value)
    assert(net.current and net.current.name == "ZM.RefreshPlayerData")
    net.current.payload = value
end
function net.Send(target)
    assert(net.current and target.valid)
    target.lastNetworkMessage = net.current
    net.current = nil
end

ZM_Util = {
    ProfileFor = function(target) return target.profile end,
    CashOf = function(target) return target.Cash or 0 end,
    IsWholeNumber = function(value) return type(value) == "number" and value == math.floor(value) end,
    FirstHuman = function() return nil end,
    RegisterCommands = function(commands, callback)
        assert(type(commands) == "table" and type(callback) == "function")
    end
}

ZM_Clothing = { Slots = { shirt = true, pants = true }, Finishes = { prototype = true }, CatalogueItems = {} }
function ZM_Clothing:LoadCatalogue() self.loadCount = (self.loadCount or 0) + 1 end
ZM_Music = {
    RoutingKeys = function() return {}, {} end,
    Validate = function(data) assert(type(data) == "table") return {}, {} end
}
ZM_World = { ActiveProfile = "preview" }
function ZM_World:GetData() return { world = { origin = { 4, 5 } } } end
function ZM_World:GetOriginSafeZone() return { id = "fixture-den", cell = 1 } end
function ZM_World:GetCellById(id)
    assert(id == 1)
    return { x = 4, y = 5 }
end
ZM_LauncherScene = {}
function ZM_LauncherScene:GetOrigin(profile, x, y)
    assert((profile == "city" or profile == "preview") and x == 4 and y == 5)
    return 51, -1
end
ZM_InventoryService = { Ops = {} }
function ZM_InventoryService.Ops.FindInstance(inventory, instanceId)
    local instance = inventory.equipped[1]
    assert(instance and instance.instanceId == instanceId, "unexpected fixture weapon instance")
    return "equipped", 1, instance
end
ZM_CraftingService = {}
ZM_ImplantService = {}
function ZM_ImplantService:ApplyMovement(target) target.movementRefreshes = (target.movementRefreshes or 0) + 1 end

function ZM_TestEquipWeapon(target, itemId)
    local instance = { instanceId = "fixture-weapon", itemId = itemId }
    local weapon = { valid = true, nw = {} }
    function weapon:GetItemInstanceId() return instance.instanceId end
    function weapon:SetNWFloat(key, value) self.nw[key] = value end
    target.ZM_Inventory = { equipped = { instance } }
    function target:GetWeapons() return { weapon } end
    return weapon
end

function ZM_TestPlayer(steamId, profile)
    local target = setmetatable({ valid = true, steamId = steamId, profile = profile, nw = {} },
        { __index = playerMeta })
    function target:IsPlayer() return true end
    function target:IsBot() return false end
    function target:SteamID() return self.steamId end
    function target:Nick() return "Fixture" end
    function target:GetNWInt(key, default)
        if self.nw[key] ~= nil then return self.nw[key] end
        return default or 0
    end
    function target:GetNWFloat(key, default)
        if self.nw[key] ~= nil then return self.nw[key] end
        return default or 0
    end
    function target:GetNWString(key, default)
        if self.nw[key] ~= nil then return self.nw[key] end
        return default or ""
    end
    function target:SetNWInt(key, value) self.nw[key] = value end
    function target:SetNWFloat(key, value) self.nw[key] = value end
    function target:SetNWString(key, value) self.nw[key] = value end
    function target:UpdatePlayerData(source)
        local key, keyError = self:GetCharacterKey()
        if not key then return false, keyError end
        local data, dataError = ZM_GetPlayerData(key, self.profile)
        if dataError then return false, dataError end
        assert(data, "fixture player data must already exist")
        data.Job, data.Stamina = self.Job, self.Stamina
        return ZM_SetPlayerData(key, self.profile, data, source)
    end
    function target:SetNetworkAttributes()
        ZM_Items:RefreshEquippedWeaponSkills(self)
        ZM_ImplantService:ApplyMovement(self)
    end
    function target:SetNetworkPlayerData()
        self:SetNWString("Job", self.Job)
        self:SetNWInt("ZM_ProfessionBonusVersion", self:GetProfessionBonusVersion())
    end
    function target:SendPlayerData()
        self.sentJob = self.Job
        self.sentBonusVersion = self:GetProfessionBonusVersion()
    end
    return target
end

return { errors = errors, hooks = hooks, timers = timers, receivers = receivers, networkNames = networkNames }
