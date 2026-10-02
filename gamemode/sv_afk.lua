// Server-owned AFK protection for the inventory, scoreboard, options and cheats menus.
// A counted menu opens only after the server finishes a countdown; damage or a client cancel stops it. While AFK,
// zombies cannot target or damage the player. Leaving AFK grants a short grace that firing ends early.
ZM_AFK = ZM_AFK or {}
local AFK = ZM_AFK

AFK.CountdownSeconds = 3
AFK.GraceSeconds = 3
// The client re-confirms an open AFK menu; a silent client loses protection rather than keeping it forever.
AFK.HeartbeatTimeoutSeconds = 6
AFK.MinRequestInterval = 0.1
AFK.CountdownMenus = { inventory = true, scoreboard = true, options = true }
AFK.ImmediateMenus = { cheats = true }
AFK.Actions = { begin = 1, immediate = 2, cancel = 3, leave = 4, hold = 5 }

util.AddNetworkString("ZM.AFKRequest")
util.AddNetworkString("ZM.AFKState")

local function now()
    return CurTime()
end

function AFK:GetState(playerEntity)
    local state = playerEntity.ZM_AFKState
    if not state then
        state = { afk = false, graceUntil = 0, countdownUntil = nil, countdownMenu = nil, heartbeatAt = 0 }
        playerEntity.ZM_AFKState = state
    end
    return state
end

function AFK:IsAFK(playerEntity)
    local state = playerEntity.ZM_AFKState
    return state ~= nil and state.afk == true
end

function AFK:IsInGrace(playerEntity, at)
    local state = playerEntity.ZM_AFKState
    return state ~= nil and not state.afk and state.graceUntil > (at or now())
end

function AFK:IsProtected(playerEntity, at)
    return self:IsAFK(playerEntity) or self:IsInGrace(playerEntity, at)
end

// Sends the current state; openMenu asks the client to open that menu now that the countdown has finished.
function AFK:Send(playerEntity, openMenu, message)
    if type(playerEntity) ~= "Player" or not IsValid(playerEntity) then
        return
    end
    local state = self:GetState(playerEntity)
    net.Start("ZM.AFKState")
        net.WriteBool(state.afk)
        net.WriteFloat(state.countdownUntil or 0)
        net.WriteString(state.countdownMenu or "")
        net.WriteFloat(state.graceUntil)
        net.WriteString(openMenu or "")
        net.WriteString(message or "")
    net.Send(playerEntity)
end

// Stops every zombie currently chasing the player, including its last-known position.
function AFK:ReleaseAttackers(playerEntity)
    for _, class in ipairs({ "zn_walker_zombie", "zn_boss_zombie" }) do
        for _, zombie in ipairs(ents.FindByClass(class)) do
            if zombie.CurrentTarget == playerEntity then
                zombie.CurrentTarget = nil
                zombie.LastKnownTargetPosition = nil
                zombie.LastKnownTargetExpiresAt = 0
            end
        end
    end
end

function AFK:Enter(playerEntity, menu, at)
    local state = self:GetState(playerEntity)
    state.afk = true
    state.countdownUntil = nil
    state.countdownMenu = nil
    state.graceUntil = 0
    state.heartbeatAt = at or now()
    self:ReleaseAttackers(playerEntity)
    self:Send(playerEntity, menu)
end

// Returns true when the request was accepted; otherwise false and a reason.
function AFK:Begin(playerEntity, menu, at)
    at = at or now()
    if not self.CountdownMenus[menu] then
        return false, "unknown menu"
    end
    if not playerEntity:Alive() then
        return false, "dead"
    end
    local state = self:GetState(playerEntity)
    if state.afk then
        // Switching between AFK menus does not need a second countdown.
        state.heartbeatAt = at
        self:Send(playerEntity, menu)
        return true
    end
    state.countdownUntil = at + self.CountdownSeconds
    state.countdownMenu = menu
    self:Send(playerEntity)
    return true
end

function AFK:EnterImmediately(playerEntity, menu, at)
    if not self.ImmediateMenus[menu] then
        return false, "unknown menu"
    end
    if not playerEntity:Alive() then
        return false, "dead"
    end
    if menu == "cheats" and ZM_Preview and ZM_Preview.HasServerCapability and
        not ZM_Preview:HasServerCapability(playerEntity, ZM_Preview.Capabilities.operator) then
        return false, "not permitted"
    end
    self:Enter(playerEntity, nil, at)
    return true
end

function AFK:CancelCountdown(playerEntity, message)
    local state = playerEntity.ZM_AFKState
    if not state or not state.countdownUntil then
        return false
    end
    state.countdownUntil = nil
    state.countdownMenu = nil
    self:Send(playerEntity, nil, message)
    return true
end

// The last AFK menu closed: protection continues as a short grace period.
function AFK:Leave(playerEntity, at)
    local state = playerEntity.ZM_AFKState
    if not state then
        return false
    end
    if state.countdownUntil then
        return self:CancelCountdown(playerEntity)
    end
    if not state.afk then
        return false
    end
    state.afk = false
    state.graceUntil = (at or now()) + self.GraceSeconds
    self:Send(playerEntity)
    return true
end

function AFK:EndGrace(playerEntity)
    local state = playerEntity.ZM_AFKState
    if not state or state.afk or state.graceUntil <= 0 then
        return false
    end
    state.graceUntil = 0
    self:Send(playerEntity)
    return true
end

// Drops every AFK state without grace (death, respawn, transition, disconnect).
function AFK:Clear(playerEntity, notify)
    local state = playerEntity.ZM_AFKState
    if not state then
        return
    end
    local changed = state.afk or state.countdownUntil ~= nil or state.graceUntil > 0
    playerEntity.ZM_AFKState = nil
    if changed and notify ~= false then
        self:Send(playerEntity)
    end
end

// Advances countdowns and expires grace or silent AFK clients.
function AFK:Tick(playerEntity, at)
    at = at or now()
    local state = playerEntity.ZM_AFKState
    if not state then
        return
    end
    if state.countdownUntil and at >= state.countdownUntil then
        if not playerEntity:Alive() then
            self:Clear(playerEntity)
            return
        end
        self:Enter(playerEntity, state.countdownMenu, at)
        return
    end
    if state.afk and at - state.heartbeatAt > self.HeartbeatTimeoutSeconds then
        self:Leave(playerEntity, at)
        return
    end
    if not state.afk and state.graceUntil > 0 and at >= state.graceUntil then
        state.graceUntil = 0
        self:Send(playerEntity)
    end
end

// Returns true when the damage must be blocked. Real damage taken during a countdown cancels it.
function AFK:FilterDamage(playerEntity, damageInfo)
    local attacker = damageInfo:GetAttacker()
    local fromEnemy = IsValid(attacker) and (attacker:IsNPC() or attacker:IsNextBot())
    if fromEnemy and self:IsProtected(playerEntity) then
        return true
    end
    if damageInfo:GetDamage() > 0 then
        self:CancelCountdown(playerEntity, "Interrupted")
    end
    return false
end

function AFK:HandleRequest(playerEntity, action, menu)
    local at = now()
    local state = self:GetState(playerEntity)
    if action ~= self.Actions.hold then
        if at - (state.lastRequestAt or 0) < self.MinRequestInterval then
            self:Send(playerEntity)
            return false, "too fast"
        end
        state.lastRequestAt = at
    end
    if action == self.Actions.begin then
        local ok, reason = self:Begin(playerEntity, menu, at)
        if not ok then self:Send(playerEntity) end
        return ok, reason
    elseif action == self.Actions.immediate then
        local ok, reason = self:EnterImmediately(playerEntity, menu, at)
        if not ok then self:Send(playerEntity) end
        return ok, reason
    elseif action == self.Actions.cancel then
        return self:CancelCountdown(playerEntity)
    elseif action == self.Actions.leave then
        return self:Leave(playerEntity, at)
    elseif action == self.Actions.hold then
        if state.afk then state.heartbeatAt = at end
        return state.afk
    end
    return false, "unknown action"
end

net.Receive("ZM.AFKRequest", function(_, playerEntity)
    if not IsValid(playerEntity) then return end
    local action = net.ReadUInt(3)
    local menu = string.sub(net.ReadString(), 1, 32)
    AFK:HandleRequest(playerEntity, action, menu)
end)

local nextTickAt = 0
hook.Add("Think", "ZM.AFK.Tick", function()
    if CurTime() < nextTickAt then return end
    nextTickAt = CurTime() + 0.05
    for _, playerEntity in ipairs(player.GetHumans()) do
        AFK:Tick(playerEntity)
    end
end)

hook.Add("EntityTakeDamage", "ZM.AFK.Protection", function(victim, damageInfo)
    if not victim:IsPlayer() then return end
    if AFK:FilterDamage(victim, damageInfo) then
        return true
    end
end)

hook.Add("KeyPress", "ZM.AFK.FiringEndsGrace", function(playerEntity, key)
    if key == IN_ATTACK and AFK:IsInGrace(playerEntity) then
        AFK:EndGrace(playerEntity)
    end
end)

hook.Add("PlayerDeath", "ZM.AFK.ClearOnDeath", function(playerEntity)
    AFK:Clear(playerEntity)
end)

hook.Add("PlayerSpawn", "ZM.AFK.ClearOnSpawn", function(playerEntity)
    AFK:Clear(playerEntity)
end)

hook.Add("PlayerDisconnected", "ZM.AFK.ClearOnDisconnect", function(playerEntity)
    AFK:Clear(playerEntity, false)
end)
