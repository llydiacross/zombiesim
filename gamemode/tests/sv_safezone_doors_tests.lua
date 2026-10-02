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
        EntIndex = function() return 1 end
    }
end

local function playerEntity()
    return {
        CellX = 10,
        CellY = 20,
        CurrentSafeZoneId = nil,
        ZM_PersistentStateLoaded = true,
        pending = {},
        messages = {},
        failSafeZoneSave = false,
        SetPData = function(self, key, value) self.pending[key] = value end,
        GetPData = function(self, key, fallback) return self.pending[key] or fallback end,
        RemovePData = function(self, key) self.pending[key] = nil end,
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
    GAMEMODE.EnsurePlayerWorldMap = function()
        table.insert(ensureCalls, currentMap)
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

function Doors:RunTests()
    return Suite:Run()
end

ZM_TestHarness.Register({
    command = "zn_test_safezones", label = "Safe-zone", file = "safezone_tests.json", report = "safezoneTests",
    help = "Runs safe-zone door, persistence, arrival-anchor, and den NPC naming tests without player-data writes.",
    run = function() return Doors:RunTests() end
})
