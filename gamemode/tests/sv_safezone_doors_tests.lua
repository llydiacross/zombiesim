local Suite = ZM_TestHarness.NewSuite()
local Doors = ZM_SafeZoneDoors
local Transitions = ZM_Transitions
local SafeZones = ZM_SafeZones
local World = ZM_World
local Npcs = ZM_DenNpcs

local cell = { id = 42, map = "city_test_recipe" }
local safeZone = { id = "safezone-door-test", cell = cell.id, map = "den-door-test" }

local function door(role, radius)
    local config = { role = role }
    if radius ~= nil then config.use_radius = tostring(radius) end
    return {
        ZM_Config = config,
        IsValid = function() return true end,
        GetClass = function() return "zn_safezone_door" end,
        GetKeyValues = function() return config end,
        GetPos = function() return Vector(24, 16, 0) end,
        EntIndex = function() return 1 end
    }
end

// A double-door slab 8 thick in y behind the doorstep marker; its off-centre origin hides the doorway centre (24, 64).
local doorProp = {
    GetClass = function() return "prop_dynamic" end,
    GetPos = function() return Vector(-16, 64, 0) end,
    WorldSpaceAABB = function() return Vector(-16, 60, 0), Vector(64, 68, 96) end
}

local function playerEntity()
    return {
        CellX = 10,
        CellY = 20,
        CurrentSafeZoneId = nil,
        ZM_PersistentStateLoaded = true,
        pending = {},
        messages = {},
        failSafeZoneSave = false,
        screenFade = nil,
        SetPData = function(self, key, value) self.pending[key] = value end,
        GetPData = function(self, key, fallback) return self.pending[key] or fallback end,
        RemovePData = function(self, key) self.pending[key] = nil end,
        SetPos = function(self, position) self.position = position end,
        SetEyeAngles = function(self, angles) self.eyeAngles = angles end,
        ScreenFade = function(self, flags, color, fadeTime, fadeHold)
            self.screenFade = { flags = flags, color = color, fadeTime = fadeTime, fadeHold = fadeHold }
        end,
        GetWorldCell = function() return cell end,
        GetWorldCellCoordinates = function(self) return self.CellX, self.CellY end,
        SetWorldCell = function(self, x, y)
            self.CellX, self.CellY, self.CurrentSafeZoneId = x, y, nil
            return true
        end,
        SetCurrentSafeZone = function(self, safeZoneId)
            if self.failSafeZoneSave then return false, "simulated persistence failure" end
            self.CurrentSafeZoneId = safeZoneId
            return true
        end,
        IsPlayer = function() return true end,
        Alive = function() return true end,
        IsBot = function() return false end,
        GetPos = function() return Vector(0, 0, 0) end,
        WorldSpaceCenter = function() return Vector(0, 0, 32) end,
        PrintMessage = function(self, _, message) table.insert(self.messages, message) end
    }
end

local function withFixture(callback, overrides)
    local originalIsValid = IsValid
    local originalGetAll = player.GetAll
    local originalGetMap = game.GetMap
    local originalActiveProfile = World.ActiveProfile
    local originalGetForCell = SafeZones.GetForCell
    local originalGet = SafeZones.Get
    local originalGetSafeZoneMap = SafeZones.GetMap
    local originalGetEntranceCell = SafeZones.GetEntranceCell
    local originalWorldMapPath = World.GetMapPath
    local originalWorldCoordinates = World.GetWorldCoordinates
    local originalEnsure = GAMEMODE.EnsurePlayerWorldMap
    local originalQueued = GAMEMODE.PlayerWorldMapTransitionQueued
    local originalOriginQueued = GAMEMODE.OriginSafeZoneTransitionQueued
    local originalFindByClass = ents.FindByClass
    local originalFindByName = ents.FindByName
    local originalFindInSphere = ents.FindInSphere
    local currentMap = "city_test_recipe"
    local target = playerEntity()
    local ensureResult = true
    local ensureCalls = {}

    IsValid = function(value) return value ~= nil and value.valid ~= false end
    player.GetAll = function() return { target } end
    game.GetMap = function() return currentMap end
    World.ActiveProfile = "zn_test_safezones"
    SafeZones.GetForCell = function(_, targetCell)
        if overrides and overrides.safeZoneForCell ~= nil then
            return overrides.safeZoneForCell
        end
        return targetCell == cell and safeZone or nil
    end
    SafeZones.Get = function(_, id) return id == safeZone.id and safeZone or nil end
    SafeZones.GetMap = function(_, id) return id == safeZone.id and "safezones/den-door-test" or nil end
    SafeZones.GetEntranceCell = function(_, id) return id == safeZone.id and cell or nil end
    World.GetMapPath = function(_, targetCell)
        return targetCell and targetCell.map and "city/" .. targetCell.map or nil
    end
    World.GetWorldCoordinates = function(_, targetCell)
        if targetCell ~= cell then return nil end
        if overrides and overrides.entranceCoordinates then
            return overrides.entranceCoordinates[1], overrides.entranceCoordinates[2]
        end
        return target.CellX, target.CellY
    end
    GAMEMODE.EnsurePlayerWorldMap = function(_, _, _, options)
        table.insert(ensureCalls, currentMap)
        ensureCalls.lastOptions = options
        return ensureResult
    end
    GAMEMODE.PlayerWorldMapTransitionQueued = false
    GAMEMODE.OriginSafeZoneTransitionQueued = false
    ents.FindByClass = function(className)
        local result = {}
        for _, candidate in ipairs((overrides and overrides.anchors) or {}) do
            if candidate.class == className then table.insert(result, candidate) end
        end
        return result
    end
    ents.FindByName = function()
        error("class-based pending arrivals must not search by targetname")
    end
    ents.FindInSphere = function()
        if overrides and overrides.doorProps then return overrides.doorProps end
        return { doorProp }
    end

    local ok, errorMessage = pcall(callback, target, ensureCalls, function(mapName) currentMap = mapName end, function(value) ensureResult = value end)

    IsValid = originalIsValid
    player.GetAll = originalGetAll
    game.GetMap = originalGetMap
    World.ActiveProfile = originalActiveProfile
    SafeZones.GetForCell = originalGetForCell
    SafeZones.Get = originalGet
    SafeZones.GetMap = originalGetSafeZoneMap
    SafeZones.GetEntranceCell = originalGetEntranceCell
    World.GetMapPath = originalWorldMapPath
    World.GetWorldCoordinates = originalWorldCoordinates
    GAMEMODE.EnsurePlayerWorldMap = originalEnsure
    GAMEMODE.PlayerWorldMapTransitionQueued = originalQueued
    GAMEMODE.OriginSafeZoneTransitionQueued = originalOriginQueued
    ents.FindByClass = originalFindByClass
    ents.FindByName = originalFindByName
    ents.FindInSphere = originalFindInSphere
    if not ok then error(errorMessage) end
end

Suite:Add("door_role_and_default_radius", function(check)
    withFixture(function()
        local role, radius = Doors:GetDoorDetails(door("enter"))
        check(role == "enter", "the Hammer role should be recognized")
        check(radius == 96, "an omitted use_radius should default to 96")
    end)
end)

Suite:Add("entry_rejects_wrong_cell_and_missing_safe_zone", function(check)
    withFixture(function(target, ensureCalls)
        local wrongCell = { id = 99, map = "city_test_recipe" }
        local originalGetWorldCell = target.GetWorldCell
        target.GetWorldCell = function() return wrongCell end
        local result = Doors:TryUseDoor(target, door("enter"))
        check(not result, "a safe zone linked to a different cell must be rejected")
        check(target.CurrentSafeZoneId == nil and #ensureCalls == 0, "the wrong-cell refusal must not persist or transition")

        target.GetWorldCell = originalGetWorldCell
        SafeZones.GetForCell = function() return nil end
        result = Doors:TryUseDoor(target, door("enter"))
        check(not result and target.CurrentSafeZoneId == nil, "a city cell without a safe zone must be rejected")
    end, { safeZoneForCell = safeZone })
end)

Suite:Add("entry_rejects_queued_transition", function(check)
    withFixture(function(target, ensureCalls)
        GAMEMODE.PlayerWorldMapTransitionQueued = true
        local result = Doors:TryUseDoor(target, door("enter"))
        check(not result, "a queued map transition must block safe-zone entry")
        check(target.CurrentSafeZoneId == nil and #ensureCalls == 0, "queued entry must not persist state or request a map")
    end)
end)

Suite:Add("entry_requires_one_loaded_human", function(check)
    withFixture(function(target, ensureCalls)
        target.ZM_PersistentStateLoaded = false
        local notReady = Doors:TryUseDoor(target, door("enter"))
        target.ZM_PersistentStateLoaded = true
        player.GetAll = function() return { target, playerEntity() } end
        local multipleHumans = Doors:TryUseDoor(target, door("enter"))
        check(not notReady and not multipleHumans, "unloaded state and multiple humans must both block entry")
        check(target.CurrentSafeZoneId == nil and #ensureCalls == 0, "guard refusals must not persist or transition")
    end)
end)

Suite:Add("entry_rolls_back_on_persistence_failure", function(check)
    withFixture(function(target, ensureCalls)
        target.failSafeZoneSave = true
        local result = Doors:TryUseDoor(target, door("enter"))
        local key = "zombiesim_transition_entry_zn_test_safezones"
        check(not result and target.CurrentSafeZoneId == nil, "failed persistence must leave the player outside the den")
        check(target.pending[key] == nil and #ensureCalls == 0, "failed persistence must clear pending entry without a map change")
        check(#target.messages > 0, "failed persistence must explain the refusal in the center prompt")
    end)
end)

Suite:Add("entry_rolls_back_when_transition_cannot_be_queued", function(check)
    withFixture(function(target, ensureCalls, changeMap, setEnsureResult)
        setEnsureResult(false)
        local result = Doors:TryUseDoor(target, door("enter"))
        local key = "zombiesim_transition_entry_zn_test_safezones"
        check(not result and target.CurrentSafeZoneId == nil, "a failed map transition must restore the city state")
        check(target.pending[key] == nil and #ensureCalls == 1, "a failed map transition must clear pending entry")
    end)
end)

Suite:Add("entry_then_exit_preserves_the_city_cell", function(check)
    withFixture(function(target, ensureCalls, changeMap)
        check(safeZone.entrance == nil, "the fixture should represent legacy runtime data without entrance metadata")
        local enterResult = Doors:TryUseDoor(target, door("enter"))
        local pendingKey = "zombiesim_transition_entry_zn_test_safezones"
        local entry = util.JSONToTable(target.pending[pendingKey] or "")
        check(enterResult and target.CurrentSafeZoneId == safeZone.id, "entry should persist the selected safe-zone id")
        check(entry and entry.anchorClass == "zn_safezone_arrival", "entry should persist a class-based arrival anchor")
        check(entry and entry.landmark == nil, "entry should not depend on a func_instance-fixed targetname")
        check(#ensureCalls == 1, "entry should route through EnsurePlayerWorldMap")

        changeMap("den-door-test")
        local exitResult = Doors:TryUseDoor(target, door("exit"))
        local exitEntry = util.JSONToTable(target.pending[pendingKey] or "")
        check(exitResult and target.CurrentSafeZoneId == nil, "exit should clear the persisted safe-zone id")
        check(target.CellX == 10 and target.CellY == 20, "exit should retain the player's city-cell coordinates")
        check(exitEntry and exitEntry.anchorClass == "zn_safezone_arrival", "exit should return to the authored city arrival point")
        check(#ensureCalls == 2, "exit should route through EnsurePlayerWorldMap")
    end)
end)

Suite:Add("exit_persistence_failure_keeps_the_player_in_the_den", function(check)
    withFixture(function(target, ensureCalls, changeMap)
        check(Doors:TryUseDoor(target, door("enter")), "the fixture should enter before testing exit persistence")
        changeMap("den-door-test")
        target.failSafeZoneSave = true
        local result = Doors:TryUseDoor(target, door("exit"))
        local key = "zombiesim_transition_entry_zn_test_safezones"
        check(not result and target.CurrentSafeZoneId == safeZone.id, "failed exit persistence must retain the safe-zone id")
        check(target.pending[key] == nil and #ensureCalls == 1, "failed exit persistence must clear pending entry without changing maps")
    end)
end)

Suite:Add("exit_queue_failure_restores_previous_city_cell", function(check)
    withFixture(function(target, ensureCalls, changeMap, setEnsureResult)
        check(Doors:TryUseDoor(target, door("enter")), "the fixture should enter the den")
        changeMap("den-door-test")
        setEnsureResult(false)
        local result = Doors:TryUseDoor(target, door("exit"))
        local key = "zombiesim_transition_entry_zn_test_safezones"
        check(not result and target.CurrentSafeZoneId == safeZone.id, "failed exit must restore den state")
        check(target.CellX == 10 and target.CellY == 20, "failed exit must restore the previous city coordinates")
        check(target.pending[key] == nil and #ensureCalls == 2, "failed exit must clear the pending arrival")
    end, { entranceCoordinates = { 5, 6 } })
end)

Suite:Add("arrival_anchor_uses_class_and_falls_back_to_start", function(check)
    withFixture(function()
        local arrival = { class = "zn_safezone_arrival", valid = true }
        ents.FindByClass = function(className)
            if className == "zn_safezone_arrival" then return { arrival } end
            return {}
        end
        check(Transitions:FindPendingEntryAnchor({ anchorClass = "zn_safezone_arrival" }) == arrival, "the pending arrival should be found by class")

        local spawn = { class = "info_player_start", valid = true }
        ents.FindByClass = function(className)
            return className == "info_player_start" and { spawn } or {}
        end
        check(Transitions:FindPendingEntryAnchor({ anchorClass = "zn_safezone_arrival" }) == spawn, "a missing arrival point should fall back to info_player_start")
    end)
end)

Suite:Add("pending_entry_fades_in_after_arrival", function(check)
    withFixture(function(target)
        local originalStart = net.Start
        local originalWriteFloat = net.WriteFloat
        local originalSend = net.Send
        local sentMessage
        local sentValues = {}
        local loadingValues = {}
        local currentMessage
        net.Start = function(name) currentMessage = name; if name ~= "ZM.LoadingHold" then sentMessage = name end end
        net.WriteFloat = function(value) table.insert(currentMessage == "ZM.LoadingHold" and loadingValues or sentValues, value) end
        net.Send = function(recipient) sentValues.recipient = recipient end

        local anchorPosition = Vector(12, 34, 56)
        local arrival = {
            valid = true,
            GetPos = function() return anchorPosition end,
            GetAngles = function() return Angle(0, 90, 0) end
        }
        ents.FindByClass = function(className)
            return className == "zn_safezone_arrival" and { arrival } or {}
        end
        local key = "zombiesim_transition_entry_zn_test_safezones"
        target.pending[key] = util.TableToJSON({ anchorClass = "zn_safezone_arrival", yaw = 90 }, false)

        local originalLock = Transitions.GetEngineInputLockRemaining
        Transitions.GetEngineInputLockRemaining = function() return 0 end
        local ok, applied = pcall(function() return Transitions:ApplyPendingEntry(target) end)
        Transitions.GetEngineInputLockRemaining = originalLock
        net.Start = originalStart
        net.WriteFloat = originalWriteFloat
        net.Send = originalSend
        if not ok then error(applied) end

        check(applied, "a valid pending entry should be applied")
        check(target.position and target.position:DistToSqr(anchorPosition) == 0, "arrival should use the authored anchor position")
        check(target.eyeAngles and target.eyeAngles.y == 90, "arrival should face the stored gate direction")
        check(target.screenFade and target.screenFade.flags == SCREENFADE.IN
            and target.screenFade.fadeTime == 1.1 and target.screenFade.fadeHold == 0,
            "arrival should fade in from black after the destination is ready")
        check(sentMessage == "ZM.PlayerTransitionEntry" and sentValues[1] == 90 and sentValues[2] == 1.1
            and sentValues.recipient == target,
            "arrival should send the matching client camera sequence")
        check(sentValues[3] == 80 and target.ZM_TransitionEntry and target.ZM_TransitionEntry.speed == 80,
            "a city arrival from a den should walk half the gate distance")
    end)
end)

Suite:Add("obstructed_recorded_return_falls_back_to_anchor", function(check)
    withFixture(function(target)
        local originalStart = net.Start
        local originalWriteFloat = net.WriteFloat
        local originalSend = net.Send
        local originalTraceHull = util.TraceHull
        local originalErrorNoHalt = ErrorNoHalt
        net.Start = function() end
        net.WriteFloat = function() end
        net.Send = function() end
        ErrorNoHalt = function() end
        util.TraceHull = function() return { StartSolid = true } end
        target.GetHull = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end
        local anchorPosition = Vector(12, 34, 56)
        local arrival = {
            valid = true,
            GetPos = function() return anchorPosition end,
            GetAngles = function() return Angle(0, 180, 0) end
        }
        ents.FindByClass = function(className)
            return className == "zn_safezone_arrival" and { arrival } or {}
        end
        local key = "zombiesim_transition_entry_zn_test_safezones"
        target.pending[key] = util.TableToJSON({ anchorClass = "zn_safezone_arrival", position = { 500, 500, 0 }, yaw = 45 }, false)

        local originalLock = Transitions.GetEngineInputLockRemaining
        Transitions.GetEngineInputLockRemaining = function() return 0 end
        local ok, applied = pcall(function() return Transitions:ApplyPendingEntry(target) end)
        Transitions.GetEngineInputLockRemaining = originalLock
        net.Start = originalStart
        net.WriteFloat = originalWriteFloat
        net.Send = originalSend
        util.TraceHull = originalTraceHull
        ErrorNoHalt = originalErrorNoHalt
        if not ok then error(applied) end

        check(applied and target.position and target.position:DistToSqr(anchorPosition) == 0,
            "a recorded return point inside geometry should fall back to the authored anchor")
        check(target.eyeAngles and target.eyeAngles.y == 180, "and use the anchor's facing")
    end)
end)

Suite:Add("den_arrival_teleports_past_walk_with_double_fade", function(check)
    withFixture(function(target)
        local originalStart = net.Start
        local originalWriteFloat = net.WriteFloat
        local originalSend = net.Send
        local originalTraceHull = util.TraceHull
        local sentValues = {}
        local loadingValues = {}
        local currentMessage
        local traceInput
        net.Start = function(name) currentMessage = name end
        net.WriteFloat = function(value) table.insert(currentMessage == "ZM.LoadingHold" and loadingValues or sentValues, value) end
        net.Send = function() end
        util.TraceHull = function(input)
            traceInput = input
            return { HitPos = input.endpos, StartSolid = false }
        end

        target.CurrentSafeZoneId = "safezone-test-den"
        target.GetPos = function(self) return self.position or Vector(0, 0, 0) end
        target.GetHull = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end
        local arrival = {
            valid = true,
            GetPos = function() return Vector(100, 200, 40) end,
            GetAngles = function() return Angle(0, 90, 0) end
        }
        ents.FindByClass = function(className)
            return className == "zn_safezone_arrival" and { arrival } or {}
        end
        local key = "zombiesim_transition_entry_zn_test_safezones"
        target.pending[key] = util.TableToJSON({ anchorClass = "zn_safezone_arrival", yaw = 90 }, false)

        local ok, applied = pcall(function() return Transitions:ApplyPendingEntry(target) end)
        net.Start = originalStart
        net.WriteFloat = originalWriteFloat
        net.Send = originalSend
        util.TraceHull = originalTraceHull
        if not ok then error(applied) end

        local expected = Vector(100, 200 + Transitions.DenArrivalDistance, 40)
        check(applied and traceInput and traceInput.filter == target, "den arrival should hull-trace the skipped walk")
        check(target.position and target.position:DistToSqr(expected) < 0.01,
            "den arrival should place the player where the walk would have ended")
        check(target.ZM_TransitionEntry == nil, "den arrival must not start a scripted walk")
        check(sentValues[1] == 90 and sentValues[2] == 0 and sentValues[3] == 0,
            "den arrival should orient the client camera without a walk")
        check(target.screenFade and target.screenFade.fadeTime == 2.2 and Transitions.DenArrivalFade == 2.2,
            "den arrival should fade in over twice the standard duration")
        check(loadingValues[2] == 2.2, "the den loading screen should cover the longer fade")
    end)
end)

Suite:Add("arrival_holds_black_through_engine_input_lock", function(check)
    withFixture(function(target)
        local originalStart = net.Start
        local originalWriteFloat = net.WriteFloat
        local originalSend = net.Send
        local originalRemaining = Transitions.GetEngineInputLockRemaining
        local sentValues = {}
        local loadingValues = {}
        local currentMessage
        net.Start = function(name) currentMessage = name end
        net.WriteFloat = function(value) table.insert(currentMessage == "ZM.LoadingHold" and loadingValues or sentValues, value) end
        net.Send = function() end
        Transitions.GetEngineInputLockRemaining = function() return 1.5 end

        local gate = {
            valid = true,
            GetPos = function() return Vector(0, 0, 0) end,
            GetAngles = function() return Angle(0, 0, 0) end
        }
        ents.FindByClass = function(className)
            return className == "zn_safezone_arrival" and { gate } or {}
        end
        local key = "zombiesim_transition_entry_zn_test_safezones"
        target.pending[key] = util.TableToJSON({ anchorClass = "zn_safezone_arrival", yaw = 0 }, false)
        local now = CurTime()
        local ok, applied = pcall(function() return Transitions:ApplyPendingEntry(target) end)
        local walkHook = hook.GetTable().SetupMove["ZM.TransitionEntryWalk"]
        local held = { GetButtons = function() return IN_FORWARD end }
        held.SetMoveAngles = function() end
        held.SetForwardSpeed = function(_, speed) held.forward = speed end
        held.SetSideSpeed = function() end
        if ok then walkHook(target, held) end
        local plainFade
        if ok then
            target.screenFade = nil
            Transitions:HoldForEngineInputLock(target)
            plainFade = target.screenFade
        end
        net.Start = originalStart
        net.WriteFloat = originalWriteFloat
        net.Send = originalSend
        Transitions.GetEngineInputLockRemaining = originalRemaining
        if not ok then error(applied) end

        local entry = target.ZM_TransitionEntry
        check(applied and entry and math.abs(entry.startTime - (now + 1.5)) < 0.01
            and math.abs(entry.untilTime - (now + 2.6)) < 0.01, "the arrival walk should start after the input lock")
        check(sentValues[4] == 1.5, "the client should receive the input-lock delay")
        check(loadingValues[1] == 1.5 and loadingValues[2] == 1.1 and loadingValues[3] == 1.5 and loadingValues[4] == 1.1,
            "arrivals and plain spawns should show the loading screen for the hold and fade")
        check(held.forward == 0 and target.ZM_TransitionEntry ~= nil,
            "input during the lock should neither move nor cancel the arrival walk")
        check(plainFade and plainFade.fadeHold == 1.5 and plainFade.fadeTime == 1.1,
            "a plain spawn should hold black until the input lock lifts")
    end)
end)

Suite:Add("movement_input_interrupts_arrival_walk_but_not_exit_sequence", function(check)
    withFixture(function(target)
        local walkHook = hook.GetTable().SetupMove["ZM.TransitionEntryWalk"]
        local function moveData(buttons)
            local data = { buttons = buttons, forward = nil }
            data.GetButtons = function() return data.buttons end
            data.SetMoveAngles = function(_, angles) data.angles = angles end
            data.SetForwardSpeed = function(_, speed) data.forward = speed end
            data.SetSideSpeed = function() end
            return data
        end

        target.ZM_TransitionEntry = { untilTime = CurTime() + 10, yaw = 45, speed = 80 }
        local idle = moveData(0)
        walkHook(target, idle)
        check(idle.forward == 80 and target.ZM_TransitionEntry ~= nil, "an untouched arrival walk keeps walking")
        local pressed = moveData(IN_FORWARD)
        walkHook(target, pressed)
        check(pressed.forward == nil and target.ZM_TransitionEntry == nil, "movement input should cancel the arrival walk")

        target.ZM_TransitionEntry = nil
        target.ZM_TransitionExit = { untilTime = CurTime() + 10, yaw = 90 }
        local exiting = moveData(IN_FORWARD)
        walkHook(target, exiting)
        check(exiting.forward == 100 and exiting.angles and exiting.angles.y == 90,
            "the committed exit sequence keeps its heading despite input")
        target.ZM_TransitionExit = nil
    end)
end)

Suite:Add("den_exit_returns_outside_the_used_city_door", function(check)
    withFixture(function(target, ensureCalls, changeMap)
        local pendingKey = "zombiesim_transition_entry_zn_test_safezones"
        check(Doors:TryUseDoor(target, door("enter")), "the fixture should enter the den")
        changeMap("den-door-test")
        check(Doors:TryUseDoor(target, door("exit")), "the fixture should exit the den")
        local exitEntry = util.JSONToTable(target.pending[pendingKey] or "")
        check(exitEntry and type(exitEntry.position) == "table" and exitEntry.position[1] == 24
            and exitEntry.position[2] == 0 and exitEntry.position[3] == 0,
            "exit should return just outside the doorstep marker, along the door prop's normal")
        check(exitEntry and math.abs(((tonumber(exitEntry.yaw) or 0) % 360) - 270) < 0.01,
            "exit should face away from the city door")
        check(exitEntry and exitEntry.anchorClass == "zn_safezone_arrival", "the authored arrival remains the fallback")
        local exitOptions = ensureCalls.lastOptions
        check(exitOptions and exitOptions.loadingTitle == "GOODBYE", "leaving a den should say goodbye on the loading screen")
    end)
end)

Suite:Add("tunnel_exit_without_door_prop_faces_marker", function(check)
    withFixture(function(target, ensureCalls, changeMap)
        local pendingKey = "zombiesim_transition_entry_zn_test_safezones"
        check(Doors:TryUseDoor(target, door("enter")), "the fixture should enter the den")
        changeMap("den-door-test")
        check(Doors:TryUseDoor(target, door("exit")), "a propless tunnel exit should still leave the den")
        local options = ensureCalls.lastOptions
        check(options and math.abs(options.yaw - math.deg(math.atan2(16, 24))) < 0.01,
            "without a door prop the exit sequence should face the marker")
        check(util.JSONToTable(target.pending[pendingKey] or "") ~= nil, "the exit should still queue a city arrival")
        local fallbackPosition, fallbackYaw = nil, nil
        Doors:RecordReturnPoint(target, door("enter"), "city/city_test_recipe")
        local record = Doors:GetReturnPoint(target, "city/city_test_recipe")
        if record then fallbackPosition, fallbackYaw = record.position, record.yaw end
        local away = Vector(-24, -16, 0):GetNormalized()
        check(fallbackPosition and math.abs(fallbackPosition[1] - (24 + away.x * Doors.ReturnStepOut)) < 0.01
            and math.abs(fallbackPosition[2] - (16 + away.y * Doors.ReturnStepOut)) < 0.01,
            "without a door prop the return point steps from the marker toward where the player stood")
        check(fallbackYaw and math.abs(fallbackYaw - away:Angle().y) < 0.01, "and faces that way")
    end, { doorProps = {} })
end)

// The shipped double door is a 1-unit slab; a marker authored in the door plane must not return the player inside it.
Suite:Add("return_point_clears_door_plane_when_marker_is_in_doorway", function(check)
    local planeProp = {
        GetClass = function() return "prop_dynamic" end,
        GetPos = function() return Vector(-16, 16, 0) end,
        WorldSpaceAABB = function() return Vector(-28, 16, 0), Vector(76, 17, 112) end
    }
    withFixture(function(target)
        target.GetPos = function() return Vector(24, -40, 0) end
        Doors:RecordReturnPoint(target, door("enter"), "city/city_test_recipe")
        local record = Doors:GetReturnPoint(target, "city/city_test_recipe")
        local position = record and record.position
        check(position and math.abs(position[1] - 24) < 0.01 and math.abs(position[2] - (16.5 - Doors.ReturnDoorClearance)) < 0.01,
            "a doorway marker should return the player ReturnDoorClearance out from the door plane, on the player's side")
        check(record and math.abs(math.AngleDifference(record.yaw, 270)) < 0.01, "and face away from the door")
    end, { doorProps = { planeProp } })
end)

Suite:Add("door_transition_requests_exit_sequence_with_rollback", function(check)
    withFixture(function(target, ensureCalls)
        check(Doors:TryUseDoor(target, door("enter")), "the fixture should queue a den entry")
        local options = ensureCalls.lastOptions
        local key = "zombiesim_transition_entry_zn_test_safezones"
        check(type(options) == "table" and options.cinematic == true, "door transitions should request the exit sequence")
        check(options and math.abs(options.yaw - math.deg(math.atan2(64, 24))) < 0.01, "the exit sequence should face the doorway centre")
        check(options and type(options.onCancel) == "function", "the exit sequence needs a rollback callback")
        check(options and options.loadingTitle == nil, "entering a den should keep the standard loading title")
        if options and options.onCancel then options.onCancel(target) end
        check(target.CurrentSafeZoneId == nil and target.pending[key] == nil,
            "cancelling the exit sequence must restore city state and clear the pending arrival")
    end)
end)

Suite:Add("exit_sequence_cancel_restores_view_and_state", function(check)
    withFixture(function(target)
        local originalStart = net.Start
        local originalWriteBool = net.WriteBool
        local originalWriteFloat = net.WriteFloat
        local originalSend = net.Send
        local originalActive = Transitions.ActiveExit
        local sent = {}
        net.Start = function(name) sent.name = name end
        net.WriteBool = function(value) sent.active = value end
        net.WriteFloat = function() end
        net.Send = function(recipient) sent.recipient = recipient end

        local rolledBack = false
        target.ZM_TransitionExit = { untilTime = 0, yaw = 0 }
        GAMEMODE.PlayerWorldMapTransitionQueued = true
        Transitions.ActiveExit = { player = target, onCancel = function() rolledBack = true end }
        local ok, cancelled = pcall(function() return Transitions:CancelExitSequence("Transition cancelled.") end)
        net.Start = originalStart
        net.WriteBool = originalWriteBool
        net.WriteFloat = originalWriteFloat
        net.Send = originalSend
        local stillActive = Transitions.ActiveExit
        Transitions.ActiveExit = originalActive
        if not ok then error(cancelled) end

        check(cancelled and stillActive == nil, "cancel should end the active exit sequence")
        check(rolledBack, "cancel should run the owner's rollback")
        check(GAMEMODE.PlayerWorldMapTransitionQueued == false, "cancel should allow a later transition")
        check(target.ZM_TransitionExit == nil, "cancel should release movement control")
        check(target.screenFade and bit.band(target.screenFade.flags, SCREENFADE.PURGE) ~= 0,
            "cancel should purge the black screen fade")
        check(sent.name == "ZM.PlayerTransitionExit" and sent.active == false and sent.recipient == target,
            "cancel should tell the client to restore its camera")
        check(target.messages[#target.messages] == "Transition cancelled.", "cancel should show the reason")
    end)
end)

Suite:Add("untransformed_instance_copies_are_removed", function(check)
    withFixture(function()
        local function marker(transformed)
            local entity = { ZM_Config = {}, removed = false }
            if transformed then entity.ZM_Config.zm_instance_transformed = "1" end
            entity.Remove = function(self) self.removed = true end
            return entity
        end
        local rawDoor, cellDoor = marker(false), marker(true)
        local rawArrival, cellArrival = marker(false), marker(true)
        local denDoor = marker(false)
        local byClass = {
            zn_safezone_door = { rawDoor, cellDoor },
            zn_safezone_arrival = { rawArrival, cellArrival }
        }
        ents.FindByClass = function(className) return byClass[className] or {} end
        Doors:RemoveUntransformedInstanceCopies()
        check(rawDoor.removed and not cellDoor.removed, "a city cell should drop the template-local door copy")
        check(rawArrival.removed and not cellArrival.removed, "a city cell should drop the template-local arrival copy")

        byClass = { zn_safezone_door = { denDoor } }
        Doors:RemoveUntransformedInstanceCopies()
        check(not denDoor.removed, "maps without transformed copies must keep their authored doors")
    end)
end)

Suite:Add("npc_hammer_name_is_fallback", function(check)
    withFixture(function()
        local npc = { ZM_Config = { targetname = "Ketamine Keith" } }
        local resolved = Npcs:Resolve(npc)
        check(resolved.name == "Ketamine Keith", "an empty npc_name should use the Hammer targetname")
        npc.ZM_Config.npc_name = "Explicit NPC Name"
        resolved = Npcs:Resolve(npc)
        check(resolved.name == "Explicit NPC Name", "npc_name should take precedence over targetname")
    end)
end)

Suite:Add("transition_gate_centres_are_published", function(check)
    withFixture(function()
        local function gate(name, centre)
            return {
                IsValid = function() return true end,
                GetClass = function() return "trigger_multiple" end,
                GetName = function() return name end,
                GetKeyValues = function() return {} end,
                SetNWBool = function() end,
                SetNWString = function() end,
                WorldSpaceCenter = function() return centre end
            }
        end
        local gates = { gate("zm_transition_gate_N", Vector(0, 2000, 64)), gate("zm_transition_gate_N", Vector(512, 2000, 64)), gate("zm_transition_gate_E", Vector(2000, 0, 64)) }
        ents.FindByClass = function(className) return className == "trigger_multiple" and gates or {} end
        Transitions:InitializeGates()
        check(GetGlobal2Int("ZMTransitionGateCount_N", 0) == 2, "both north gates should be published")
        check(GetGlobal2Vector("ZMTransitionGate_N_2", vector_origin) == Vector(512, 2000, 64), "north gate centres should be published in order")
        check(GetGlobal2Int("ZMTransitionGateCount_E", 0) == 1 and GetGlobal2Int("ZMTransitionGateCount_S", -1) == 0, "gate counts should be published per direction, including empty sides")
    end)
    // Republish the loaded map's real gates after the fixture restores ents.FindByClass.
    Transitions:InitializeGates()
end)

Suite:Add("safe_zone_door_markers_are_published", function(check)
    withFixture(function()
        local function door(role, position)
            return {
                ZM_Config = { role = role, use_radius = "96" },
                IsValid = function() return true end,
                GetClass = function() return "zn_safezone_door" end,
                EntIndex = function() return 0 end,
                SetNWBool = function() end,
                SetNWString = function() end,
                SetNWFloat = function() end,
                GetPos = function() return position end
            }
        end
        local doors = { door("enter", Vector(-672, -488, 48)), door("bogus", Vector(0, 0, 0)), door("exit", Vector(64, 128, 0)) }
        ents.FindByClass = function(className) return className == "zn_safezone_door" and doors or {} end
        local originalErrorNoHalt = ErrorNoHalt
        ErrorNoHalt = function() end
        Doors:InitializeDoors()
        ErrorNoHalt = originalErrorNoHalt
        check(GetGlobal2Int("ZMSafeZoneDoorCount", 0) == 2, "only valid doors should be published")
        check(GetGlobal2Vector("ZMSafeZoneDoor_1", vector_origin) == Vector(-672, -488, 48)
            and GetGlobal2String("ZMSafeZoneDoorRole_1", "") == "enter", "the entrance position and role should be published")
        check(GetGlobal2Vector("ZMSafeZoneDoor_2", vector_origin) == Vector(64, 128, 0)
            and GetGlobal2String("ZMSafeZoneDoorRole_2", "") == "exit", "invalid doors should not leave gaps in the published list")

        // Entity:Remove is deferred, so template-local copies are still found in the frame they are removed.
        local transformedDoor = door("enter", Vector(-608, 488, 48))
        transformedDoor.ZM_Config.zm_instance_transformed = "1"
        local rawCopy = door("enter", Vector(-672, -488, 48))
        rawCopy.Remove = function() end
        doors = { transformedDoor, rawCopy }
        Doors:InitializeDoors()
        check(GetGlobal2Int("ZMSafeZoneDoorCount", 0) == 1
            and GetGlobal2Vector("ZMSafeZoneDoor_1", vector_origin) == Vector(-608, 488, 48),
            "template-local copies pending removal must not be published")
    end)
    // Republish the loaded map's real doors after the fixture restores ents.FindByClass.
    Doors:InitializeDoors()
end)

// Neighbouring cells can share one recipe BSP; gate travel must still change level so cell-scoped state resets.
Suite:Add("gate_travel_requests_reload_for_shared_recipe_map", function(check)
    withFixture(function(target, ensureCalls)
        local gate = {
            GetClass = function() return "trigger_multiple" end,
            GetName = function() return "zm_transition_gate_E" end,
            GetKeyValues = function() return {} end
        }
        target.CanTravelToNeighbour = function(_, code) return code == "E" and cell or nil end
        Transitions:TryUseGate(target, gate)
        check(#ensureCalls == 1, "a gate should request a level change")
        check(ensureCalls.lastOptions and ensureCalls.lastOptions.forceReload == true,
            "gate travel should force a reload when the neighbour shares the loaded map")
    end)
end)

Suite:Add("gate_travel_yields_to_searchable_loot", function(check)
    local originalFindAimedSpot = ZM_LootSpots.FindAimedSpot
    local selectedSpot = { key = "enemycorpse_test" }
    ZM_LootSpots.FindAimedSpot = function(_, target)
        return target and selectedSpot or nil
    end
    local ok, errorMessage = pcall(function()
        withFixture(function(target, ensureCalls)
            local gate = {
                GetClass = function() return "trigger_multiple" end,
                GetName = function() return "zm_transition_gate_E" end,
                GetKeyValues = function() return {} end
            }
            target.CanTravelToNeighbour = function() return cell end
            Transitions:TryUseGate(target, gate)
            check(#ensureCalls == 0, "using a searchable enemy corpse beside a gate must not transition")
        end)
    end)
    ZM_LootSpots.FindAimedSpot = originalFindAimedSpot
    if not ok then error(errorMessage) end
end)

Suite:Add("same_map_reload_only_when_forced", function(check)
    local realEnsurePlayerWorldMap = GAMEMODE.EnsurePlayerWorldMap
    withFixture(function(target)
        local originalExpected = GAMEMODE.GetExpectedPlayerMap
        local originalConsoleCommand = game.ConsoleCommand
        local commands = {}
        GAMEMODE.GetExpectedPlayerMap = function() return "city/city_test_recipe" end
        game.ConsoleCommand = function(command) table.insert(commands, command) end
        local ok, errorMessage = pcall(function()
            check(realEnsurePlayerWorldMap(GAMEMODE, target) == false and #commands == 0,
                "spawn-time checks must not reload the map that is already loaded")
            check(realEnsurePlayerWorldMap(GAMEMODE, target, nil, { forceReload = true }) == true,
                "a forced reload should queue a level change to the same map")
            check(commands[1] == "changelevel city/city_test_recipe\n", "the forced reload should change level to the loaded map")
        end)
        GAMEMODE.GetExpectedPlayerMap = originalExpected
        game.ConsoleCommand = originalConsoleCommand
        if not ok then error(errorMessage) end
    end)
end)

function Doors:RunTests()
    return Suite:Run()
end

ZM_TestHarness.Register({
    command = "zn_test_safezones", label = "Safe-zone", file = "safezone_tests.json", report = "safezoneTests",
    help = "Runs safe-zone door, persistence, arrival-anchor, and den NPC naming tests without player-data writes.",
    run = function() return Doors:RunTests() end
})
