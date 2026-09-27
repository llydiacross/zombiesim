// Server-only helpers shared by the gameplay services and their console commands. Keep each helper small and
// behavior-neutral; service-specific rules stay in their own modules.
ZM_Util = ZM_Util or {}
local Util = ZM_Util

// The first connected human, used as the target when a command runs from the server console or the dev bridge.
function Util.FirstHuman()
    for _, candidate in ipairs(player.GetHumans()) do
        if IsValid(candidate) then return candidate end
    end
end

// The persistence profile for a player or test stub.
function Util.ProfileFor(target)
    return target.ZM_InventoryProfile or ZM_World.ActiveProfile
end

// True for a real player entity (test stubs return false from IsPlayer).
function Util.IsPlayerEntity(target)
    return IsValid(target) and target.IsPlayer ~= nil and target:IsPlayer() == true
end

// A whole number within the optional inclusive bounds.
function Util.IsWholeNumber(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and (minimum == nil or value >= minimum) and (maximum == nil or value <= maximum)
end

// A player's in-memory cash as a whole number.
function Util.CashOf(target)
    return math.floor(tonumber(target.Cash) or 0)
end

// Prints a line to the caller's console, or to the server console when there is no caller.
function Util.Print(caller, line)
    if IsValid(caller) then
        caller:PrintMessage(HUD_PRINTCONSOLE, line .. "\n")
    else
        print(line)
    end
end

// Prints a "[ZombieSim] "-prefixed message to the caller's console, or to the server console.
function Util.Reply(caller, message)
    Util.Print(caller, "[ZombieSim] " .. message)
end

// False (after telling the caller) when an in-game caller is not an admin; the server console is always allowed.
// publicCommands is an optional set of command names any player may run.
function Util.RequireAdmin(caller, command, publicCommands)
    if IsValid(caller) and not caller:IsAdmin() and not (publicCommands and publicCommands[command]) then
        Util.Reply(caller, command .. " must be run by an in-game admin.")
        return false
    end
    return true
end

// The command's target: an admin caller, or the first human when run from the server console or the dev bridge.
// Returns nil (after telling the caller) when the caller is not an admin or no human is connected.
function Util.ResolveCommandTarget(caller, command)
    if IsValid(caller) then
        return Util.RequireAdmin(caller, command) and caller or nil
    end
    local target = Util.FirstHuman()
    if not target then
        Util.Reply(caller, command .. " needs a connected player.")
    end
    return target
end

// Registers each command as a console command and a dev-bridge direct command. runner(caller, command, arguments)
// receives the console caller (nil from the bridge) and the whitespace-split arguments.
function Util.RegisterCommands(commands, runner)
    ZM_DevConsole = ZM_DevConsole or {}
    ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
    for command, help in pairs(commands) do
        concommand.Add(command, function(caller, _, arguments)
            runner(caller, command, arguments)
        end, nil, help)
        ZM_DevConsole.DirectCommands[command] = function(argumentString)
            return runner(nil, command, string.Explode("%s+", argumentString or "", true))
        end
    end
end
