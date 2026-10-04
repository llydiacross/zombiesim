// Server-side tests for AFK countdowns, protection, grace expiry, cleanup and zombie targeting.
local AFK = ZM_AFK
local suite = ZM_TestHarness.NewSuite()

local function fakePlayer()
    local fake = { alive = true }
    function fake:Alive() return self.alive end
    function fake:IsValid() return true end
    return fake
end

local function damageFrom(attacker, amount)
    local damage = DamageInfo()
    damage:SetDamage(amount or 10)
    damage:SetDamageType(DMG_SLASH)
    damage:SetAttacker(attacker)
    damage:SetInflictor(attacker)
    return damage
end

local function spawnZombie()
    local zombie = ents.Create("zn_walker_zombie")
    if not IsValid(zombie) then return nil end
    zombie:SetPos(Vector(0, 0, -16000))
    zombie:Spawn()
    return zombie
end

suite:Add("countdown_opens_only_after_three_seconds", function(check)
    local ply = fakePlayer()
    check(AFK:Begin(ply, "inventory", 100), "a counted menu starts a countdown")
    check(not AFK:IsProtected(ply, 100), "the countdown itself gives no protection")
    AFK:Tick(ply, 102.9)
    check(not AFK:IsAFK(ply), "the menu is not open before three seconds")
    AFK:Tick(ply, 103)
    check(AFK:IsAFK(ply), "the countdown ends in AFK")
    check(AFK:GetState(ply).countdownUntil == nil, "the countdown is cleared once AFK")
end)

suite:Add("only_named_menus_are_accepted", function(check)
    local ply = fakePlayer()
    check(not AFK:Begin(ply, "map", 0), "the world map is not an AFK menu")
    check(not AFK:Begin(ply, "cheats", 0), "cheats never use a countdown")
    check(not AFK:EnterImmediately(ply, "inventory", 0), "inventory cannot skip the countdown")
    for _, menu in ipairs({ "inventory", "scoreboard", "options" }) do
        local other = fakePlayer()
        check(AFK:Begin(other, menu, 0), menu .. " starts a countdown")
    end
    ply.alive = false
    check(not AFK:Begin(ply, "inventory", 0), "a dead player cannot start a countdown")
end)

suite:Add("cheats_enter_afk_immediately", function(check)
    local ply = fakePlayer()
    local original = ZM_Preview and ZM_Preview.HasServerCapability
    if ZM_Preview then ZM_Preview.HasServerCapability = function() return true end end
    check(AFK:EnterImmediately(ply, "cheats", 10), "an operator enters AFK through cheats")
    check(AFK:IsAFK(ply), "no countdown is needed")
    if ZM_Preview then
        ZM_Preview.HasServerCapability = function() return false end
        local denied = fakePlayer()
        check(not AFK:EnterImmediately(denied, "cheats", 10), "a non-operator cannot use the cheats AFK path")
        ZM_Preview.HasServerCapability = original
    end
end)

suite:Add("cancel_and_damage_stop_the_countdown", function(check)
    local ply = fakePlayer()
    AFK:Begin(ply, "options", 0)
    check(AFK:CancelCountdown(ply), "a client cancel stops the countdown")
    AFK:Tick(ply, 5)
    check(not AFK:IsAFK(ply), "a cancelled countdown never opens the menu")

    AFK:Begin(ply, "scoreboard", 10)
    local blocked = AFK:FilterDamage(ply, damageFrom(game.GetWorld(), 5))
    check(not blocked, "damage during a countdown is not blocked")
    check(AFK:GetState(ply).countdownUntil == nil, "taking damage interrupts the countdown")
    AFK:Tick(ply, 20)
    check(not AFK:IsAFK(ply), "an interrupted countdown never opens the menu")

    AFK:Begin(ply, "inventory", 30)
    check(AFK:Leave(ply, 31), "closing during a countdown cancels it")
    AFK:Tick(ply, 40)
    check(not AFK:IsAFK(ply), "the menu stays closed")
end)

suite:Add("enemy_damage_is_blocked_while_afk_and_in_grace", function(check)
    local zombie = spawnZombie()
    check(IsValid(zombie), "a test walker spawns")
    if not IsValid(zombie) then return end
    local ply = fakePlayer()
    AFK:Begin(ply, "inventory", CurTime() - 4)
    AFK:Tick(ply, CurTime())
    check(AFK:FilterDamage(ply, damageFrom(zombie)), "zombie damage is blocked while AFK")
    check(not AFK:FilterDamage(ply, damageFrom(game.GetWorld())), "non-enemy damage still applies while AFK")
    AFK:Leave(ply, CurTime())
    check(AFK:IsInGrace(ply), "leaving AFK starts the grace")
    check(AFK:FilterDamage(ply, damageFrom(zombie)), "zombie damage is blocked during grace")
    AFK:EndGrace(ply)
    check(not AFK:FilterDamage(ply, damageFrom(zombie)), "zombie damage applies after grace ends")
    zombie:Remove()
end)

suite:Add("grace_expires_after_three_seconds", function(check)
    local ply = fakePlayer()
    AFK:Begin(ply, "inventory", 0)
    AFK:Tick(ply, 3)
    AFK:Leave(ply, 10)
    check(not AFK:IsAFK(ply) and AFK:IsInGrace(ply, 12.9), "grace lasts three seconds")
    AFK:Tick(ply, 13)
    check(not AFK:IsProtected(ply, 13), "grace expires")
    check(not AFK:Leave(ply, 14), "a repeated leave does not restart grace")
    check(not AFK:IsProtected(ply, 14), "repeated toggles leave no protection")
end)

suite:Add("switching_menus_while_afk_keeps_afk_without_a_second_countdown", function(check)
    local ply = fakePlayer()
    AFK:Begin(ply, "inventory", 0)
    AFK:Tick(ply, 3)
    check(AFK:Begin(ply, "options", 4), "a second menu is accepted while AFK")
    check(AFK:IsAFK(ply) and AFK:GetState(ply).countdownUntil == nil, "no second countdown starts")
end)

suite:Add("silent_clients_lose_afk", function(check)
    local ply = fakePlayer()
    AFK:Begin(ply, "inventory", 0)
    AFK:Tick(ply, 3)
    AFK:HandleRequest(ply, AFK.Actions.hold)
    AFK:GetState(ply).heartbeatAt = 3
    AFK:Tick(ply, 3 + AFK.HeartbeatTimeoutSeconds - 0.1)
    check(AFK:IsAFK(ply), "a recent heartbeat keeps AFK")
    AFK:Tick(ply, 3 + AFK.HeartbeatTimeoutSeconds + 0.1)
    check(not AFK:IsAFK(ply), "a silent client drops out of AFK")
    check(AFK:IsInGrace(ply, 3 + AFK.HeartbeatTimeoutSeconds + 1), "the timeout still grants the normal grace")
end)

suite:Add("death_and_transitions_clear_every_state", function(check)
    local ply = fakePlayer()
    AFK:Begin(ply, "inventory", 0)
    AFK:Tick(ply, 3)
    AFK:Clear(ply)
    check(not AFK:IsProtected(ply, 3) and ply.ZM_AFKState == nil, "clear removes AFK without grace")
    AFK:Begin(ply, "inventory", 10)
    ply.alive = false
    AFK:Tick(ply, 13)
    check(not AFK:IsAFK(ply), "a countdown finishing after death does not enter AFK")
    ply.alive = true
    AFK:Begin(ply, "inventory", 20)
    AFK:Tick(ply, 23)
    AFK:Leave(ply, 24)
    AFK:Clear(ply)
    check(not AFK:IsProtected(ply, 24), "clear also removes grace")
end)

suite:Add("request_validation_rejects_bad_and_rapid_requests", function(check)
    local ply = fakePlayer()
    local ok = AFK:HandleRequest(ply, 7, "inventory")
    check(not ok, "unknown actions are rejected")
    AFK:GetState(ply).lastRequestAt = 0
    local accepted = AFK:HandleRequest(ply, AFK.Actions.begin, "inventory")
    local rapid = AFK:HandleRequest(ply, AFK.Actions.begin, "inventory")
    check(accepted and not rapid, "a second request inside the rate limit is ignored")
    check(not AFK:IsAFK(ply), "requests never skip the countdown")
end)

suite:Add("zombies_release_and_ignore_protected_players", function(check)
    local ply = fakePlayer()
    ply.IsPlayer = function() return true end
    ply.IsFlagSet = function(self) return self.notarget == true end
    ply.GetWorldCell = function() return { id = 42 } end
    ply.GetPos = function() return Vector(0, 0, 0) end
    local zombie = spawnZombie()
    check(IsValid(ply), "the isolated target fixture is valid")
    check(IsValid(zombie), "a test walker spawns")
    if not IsValid(ply) or not IsValid(zombie) then
        if IsValid(zombie) then zombie:Remove() end
        return
    end
    local cell = ply:GetWorldCell()
    zombie.WalkerSourceCellId = cell and cell.id
    local saved = ply.ZM_AFKState
    ply.ZM_AFKState = nil
    local validBefore = zombie:IsValidTarget(ply)
    zombie.CurrentTarget = ply
    zombie.LastKnownTargetPosition = ply:GetPos()
    ply.ZM_AFKState = { afk = true, graceUntil = 0, heartbeatAt = CurTime() }
    AFK:ReleaseAttackers(ply)
    check(validBefore, "the player is a valid target before AFK")
    check(not zombie:IsValidTarget(ply), "an AFK player is not a valid target")
    check(zombie.CurrentTarget == nil and zombie.LastKnownTargetPosition == nil, "existing attackers are released")
    ply.ZM_AFKState = { afk = false, graceUntil = CurTime() + 3, heartbeatAt = 0 }
    check(not zombie:IsValidTarget(ply), "a player in grace is not a valid target")
    ply.ZM_AFKState = saved
    ply.notarget = true
    check(not zombie:IsValidTarget(ply), "notarget remains protected independently of AFK")
    zombie:Remove()
end)

function AFK:RunTests()
    return suite:Run()
end

ZM_TestHarness.Register({
    command = "zn_test_afk", label = "AFK", file = "afk_tests.json", report = "afkTests",
    help = "Runs the AFK countdown, protection, grace, cleanup and zombie-targeting tests.",
    run = function() return AFK:RunTests() end
})
