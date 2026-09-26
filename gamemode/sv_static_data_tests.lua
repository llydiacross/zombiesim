// Server-only fixture tests for the static-data loader. Fixtures live in tests/static_data/ (not shipped content).
local StaticData = ZM_StaticData
local resultPath = "zombiesim/static_data_tests.json"

local function fixtureRoot()
    return "gamemodes/" .. GAMEMODE.FolderName .. "/tests/static_data/"
end

local function fixtureFiles(overrides, root, failures)
    local files = table.Copy(StaticData.Files)
    for fileKey, fileName in pairs(overrides or {}) do
        if not StaticData.Files[fileKey] then
            table.insert(failures, "unknown file key '" .. tostring(fileKey) .. "' in case files")
        else
            files[fileKey] = root .. fileName
        end
    end
    return files
end

local function resolvePath(root, path)
    local value = root
    for segment in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[tonumber(segment) or segment]
    end
    return value
end

local function valuesMatch(actual, expected)
    if type(actual) == "number" and type(expected) == "number" then
        return math.abs(actual - expected) < 1e-9
    end
    return actual == expected
end

local function issueMatches(issue, expected)
    return issue.file == expected.file
        and (expected.path == nil or issue.path == expected.path)
        and string.find(issue.message, expected.message or "", 1, true) ~= nil
end

local function runCase(case, root)
    local result = { name = tostring(case.name), failures = {} }
    local files = fixtureFiles(case.files, root, result.failures)
    local registry, report = StaticData:Build(files)
    result.errorCount = #report.errors
    result.warningCount = #report.warnings

    if case.expectErrors then
        if registry then
            table.insert(result.failures, "expected errors, but the build succeeded")
        end
        for _, expected in ipairs(case.expectErrors) do
            local found = false
            for _, issue in ipairs(report.errors) do
                if issueMatches(issue, expected) then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(result.failures, string.format("missing expected error: %s %s: %s", tostring(expected.file), tostring(expected.path), tostring(expected.message)))
            end
        end
    elseif not registry then
        for _, line in ipairs(StaticData:FormatReport(report)) do
            table.insert(result.failures, "unexpected: " .. line)
        end
    end

    if registry then
        for _, expected in ipairs(case.expectValues or {}) do
            local actual = resolvePath(registry, expected.path)
            if not valuesMatch(actual, expected.value) then
                table.insert(result.failures, string.format("%s is %s, expected %s", expected.path, tostring(actual), tostring(expected.value)))
            end
        end
    end
    result.passed = #result.failures == 0
    return result
end

// A failed reload must report failure and leave the live registry untouched.
local function runReloadKeepsRegistryCase(root)
    local result = { name = "failed_reload_keeps_previous_registry", failures = {} }
    local before = StaticData:GetRegistry()
    if not before then
        table.insert(result.failures, "no live registry is loaded to protect")
    else
        local loaded = StaticData:Reload(fixtureFiles({ items = "malformed_items.json" }, root, result.failures))
        if loaded then
            table.insert(result.failures, "reload with malformed items unexpectedly succeeded")
        end
        if StaticData:GetRegistry() ~= before then
            table.insert(result.failures, "the live registry was replaced by a failed reload")
        end
    end
    result.passed = #result.failures == 0
    return result
end

function StaticData:RunFixtureTests()
    local root = fixtureRoot()
    local summary = { passed = 0, failed = 0, cases = {}, ranAt = os.time() }
    local manifest = util.JSONToTable(file.Read(root .. "cases.json", "GAME") or "")
    if type(manifest) ~= "table" or type(manifest.cases) ~= "table" then
        summary.error = "could not read " .. root .. "cases.json"
        summary.failed = 1
        return summary
    end

    local results = {}
    for _, case in ipairs(manifest.cases) do
        table.insert(results, runCase(case, root))
    end
    table.insert(results, runReloadKeepsRegistryCase(root))
    for _, result in ipairs(results) do
        if result.passed then
            summary.passed = summary.passed + 1
        else
            summary.failed = summary.failed + 1
        end
        table.insert(summary.cases, result)
    end
    return summary
end

local function printSummary(ply, summary)
    local lines = {}
    if summary.error then
        table.insert(lines, "ERROR " .. summary.error)
    end
    for _, result in ipairs(summary.cases) do
        table.insert(lines, (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do
            table.insert(lines, "     " .. failure)
        end
    end
    table.insert(lines, string.format("Static data fixture tests: %d passed, %d failed.", summary.passed, summary.failed))
    for _, line in ipairs(lines) do
        if IsValid(ply) then
            ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] " .. line .. "\n")
        else
            print("[ZombieSim] " .. line)
        end
    end
end

local function runAndRecord(ply)
    local summary = StaticData:RunFixtureTests()
    file.CreateDir("zombiesim")
    file.Write(resultPath, util.TableToJSON(summary, true) or "{}")
    printSummary(ply, summary)
    if ZM_DevConsole and ZM_DevConsole.Report then
        ZM_DevConsole:Report("staticDataTests", summary)
    end
    return summary.failed == 0, summary.failed > 0 and "static data fixture tests failed" or nil
end

concommand.Add("zn_test_static_data", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ZombieSim] zn_test_static_data must be run by an in-game admin.\n")
        return
    end
    runAndRecord(ply)
end, nil, "Runs the static-data loader fixture tests in tests/static_data/.")

ZM_DevConsole = ZM_DevConsole or {}
ZM_DevConsole.DirectCommands = ZM_DevConsole.DirectCommands or {}
ZM_DevConsole.DirectCommands.zn_test_static_data = function()
    return runAndRecord(nil)
end
