// Shared suite runner; recording, stash stubs and command registration are server-only.
// A suite collects named cases; each case body receives
// check(condition, message). Running a suite records PASS/FAIL lines, writes data/zombiesim/<file>, and reports
// the summary through the dev bridge.
ZM_TestHarness = ZM_TestHarness or {}
local Harness = ZM_TestHarness
local Suite = {}
Suite.__index = Suite

function Harness.NewSuite()
    return setmetatable({ cases = {} }, Suite)
end

function Suite:Add(name, body)
    table.insert(self.cases, { name = name, body = body })
end

// Runs every case. options.before runs before each case and options.after once after the last case;
// options.setup / options.teardown run once around the whole run. Case errors are caught per case.
// Returns { passed, failed, cases = { { name, passed, failures } }, ranAt }.
function Suite:Run(options)
    options = options or {}
    local summary = { passed = 0, failed = 0, cases = {}, ranAt = os.time() }
    if options.setup then options.setup() end
    for _, entry in ipairs(self.cases) do
        if options.before then options.before() end
        local result = { name = entry.name, failures = {} }
        local function check(condition, message)
            if not condition then table.insert(result.failures, tostring(message)) end
        end
        local ok, err = pcall(entry.body, check)
        if not ok then table.insert(result.failures, "error: " .. tostring(err)) end
        result.passed = #result.failures == 0
        summary[result.passed and "passed" or "failed"] = summary[result.passed and "passed" or "failed"] + 1
        table.insert(summary.cases, result)
    end
    if options.after then options.after() end
    if options.teardown then options.teardown() end
    return summary
end

// Lets test stubs choose den access through their inDen field (real players keep the normal check).
// Returns a function that restores the original check.
function Harness.StubStashAccess()
    local Service = ZM_InventoryService
    local original = Service.CanAccessStash
    Service.CanAccessStash = function(self, target)
        if type(target) == "table" and target.inDen ~= nil then return target.inDen end
        return original(self, target)
    end
    return function() Service.CanAccessStash = original end
end

// Prints, saves, and reports a summary. Returns true, or false and a message listing the failures.
function Harness.Record(caller, summary, spec)
    file.CreateDir("zombiesim")
    file.Write("zombiesim/" .. spec.file, util.TableToJSON(summary, true) or "{}")
    local failures = {}
    for _, result in ipairs(summary.cases) do
        ZM_Util.Reply(caller, (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do
            ZM_Util.Reply(caller, "     " .. failure)
            table.insert(failures, result.name .. ": " .. failure)
        end
    end
    ZM_Util.Reply(caller, string.format("%s tests: %d passed, %d failed.", spec.label, summary.passed, summary.failed))
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report(spec.report, summary)
    end
    if summary.failed > 0 then
        return false, string.format("%s tests failed (%d/%d passed): %s", spec.label, summary.passed, summary.passed + summary.failed, table.concat(failures, " | "))
    end
    return true
end

// Registers an admin console command and a dev-bridge direct command for a suite.
// spec: { command, label, file, report, help, run = function() return summary end }.
function Harness.Register(spec)
    local function runAndRecord(caller)
        return Harness.Record(caller, spec.run(), spec)
    end
    concommand.Add(spec.command, function(caller)
        if not ZM_Util.RequireAdmin(caller, spec.command) then return end
        runAndRecord(caller)
    end, nil, spec.help)
    ZM_DevConsole = ZM_DevConsole or {}
    ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
    ZM_DevConsole.DirectCommands[spec.command] = function()
        return runAndRecord(nil)
    end
end
