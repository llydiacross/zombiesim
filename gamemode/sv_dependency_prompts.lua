// Server-side availability reporting for optional local installations.
ZM_DependencyPrompts = ZM_DependencyPrompts or {}
local DependencyPrompts = ZM_DependencyPrompts

util.AddNetworkString("ZM.DependencyStatus")
util.AddNetworkString("ZM.RequestDependencyStatus")
util.AddNetworkString("ZM.DependencyPromptsReady")

DependencyPrompts.PendingTransitions = DependencyPrompts.PendingTransitions or {}
DependencyPrompts.NextTransitionId = DependencyPrompts.NextTransitionId or 0

local function isLauncherMap()
    local mapName = string.lower(string.match(game.GetMap(), "([^/]+)$") or game.GetMap())
    return ZM_World and ZM_World.LauncherMapProfiles and ZM_World.LauncherMapProfiles[mapName] ~= nil
end

local function hasWalkerModule()
    local native = rawget(_G, "ZM_WalkerNative")
    return type(native) == "table" and native.ApiVersion == 1 and type(native.GetStats) == "function"
end

local function nextTransitionId(playerEntity)
    DependencyPrompts.NextTransitionId = DependencyPrompts.NextTransitionId + 1
    local seed = string.format("%s:%0.6f:%d", playerEntity:SteamID(), SysTime(), DependencyPrompts.NextTransitionId)
    return math.max(1, math.floor(tonumber(util.CRC(seed)) or 1))
end

function DependencyPrompts:SendStatus(playerEntity)
    if not IsValid(playerEntity) or not playerEntity:IsPlayer() then
        return
    end

    local launcher = isLauncherMap()
    local walkerInstalled = hasWalkerModule()
    local pending = self.PendingTransitions[playerEntity]
    net.Start("ZM.DependencyStatus")
        net.WriteBool(launcher)
        net.WriteBool(walkerInstalled)
        net.WriteBool(pending ~= nil)
        net.WriteUInt(pending and pending.id or 0, 32)
    net.Send(playerEntity)
end

function DependencyPrompts:HoldLauncherTransition(playerEntity, profile, previouslyConnected)
    if not isLauncherMap() then
        return false
    end

    self.PendingTransitions[playerEntity] = {
        id = nextTransitionId(playerEntity),
        profile = profile,
        previouslyConnected = previouslyConnected == true
    }
    self:SendStatus(playerEntity)
    return true
end

function DependencyPrompts:ResumeLauncherTransition(playerEntity, transitionId)
    local pending = self.PendingTransitions[playerEntity]
    if not pending or transitionId ~= pending.id then
        return
    end
    self.PendingTransitions[playerEntity] = nil

    if not IsValid(playerEntity) or not isLauncherMap() then
        return
    end
    if GAMEMODE and GAMEMODE.ContinuePlayerSpawnMapTransition then
        GAMEMODE:ContinuePlayerSpawnMapTransition(playerEntity, pending.profile, pending.previouslyConnected)
    end
end

net.Receive("ZM.RequestDependencyStatus", function(_, playerEntity)
    DependencyPrompts:SendStatus(playerEntity)
end)

net.Receive("ZM.DependencyPromptsReady", function(_, playerEntity)
    DependencyPrompts:ResumeLauncherTransition(playerEntity, net.ReadUInt(32))
end)

hook.Add("PlayerSpawn", "ZombieSim.DependencyPrompts.SendStatus", function(playerEntity)
    timer.Simple(0, function()
        DependencyPrompts:SendStatus(playerEntity)
    end)
end)

hook.Add("PlayerDisconnected", "ZombieSim.DependencyPrompts.ClearTransition", function(playerEntity)
    DependencyPrompts.PendingTransitions[playerEntity] = nil
end)