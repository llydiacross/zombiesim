local suite = ZM_TestHarness.NewSuite()
local function fixture()
    local revision = string.rep("a", 64)
    return { schemaVersion = 1, releaseId = revision, development = true, profiles = { "city", "preview" },
        integrityErrors = {}, packs = {
            { id = "core", revision = revision, workshopId = "", files = { { path = "gamemodes/zombiesim/gamemode/shared.lua", bytes = 12 } } },
            { id = "clothing-01", revision = revision, workshopId = "", files = { { path = "materials/a.vtf", bytes = 12 } } }
        } }
end
local function validate(data, markerChange, size)
    return ZM_Distribution.Validate(data, function(path)
        local marker = { schemaVersion = 1, id = string.match(path, "([^/]+)%.json$"), releaseId = data.releaseId, revision = string.rep("a", 64) }
        if markerChange then return markerChange(marker) end
        return marker
    end, size or function() return 12 end)
end

suite:Add("compatible_core_and_content_versions_validate", function(check)
    check(validate(fixture()), "complete development packages validate")
end)
suite:Add("workshop_subscription_installation_and_placeholder_states_are_distinct", function(check)
    local pack = { id = "clothing-01", workshopId = "", workshopIdPlaceholder = "pending:clothing-01" }
    check(ZM_Distribution.WorkshopStatus(pack, true, { mounted = true }) == "pending", "placeholder never appears subscribed or usable")
    pack.workshopId = "123"
    check(ZM_Distribution.WorkshopStatus(pack, false) == "unsubscribed", "not subscribed")
    check(ZM_Distribution.WorkshopStatus(pack, true) == "downloading", "subscribed but not installed")
    check(ZM_Distribution.WorkshopStatus(pack, true, { downloaded = true, mounted = false }) == "disabled", "downloaded but disabled")
    check(ZM_Distribution.WorkshopStatus(pack, true, { downloaded = true, mounted = true }) == "mounted", "subscribed and mounted")
    check(ZM_Distribution.WorkshopStatus(pack, false, { downloaded = true, mounted = true }) == "mounted_unsubscribed",
        "server-downloaded content remains usable without forcing subscription")
end)
suite:Add("missing_or_mixed_content_marker_blocks_deployment", function(check)
    for _, mutate in ipairs({
        function() return nil end,
        function(marker) marker.releaseId = string.rep("b", 64) return marker end,
        function(marker) marker.revision = string.rep("b", 64) return marker end
    }) do
        local ready, message = validate(fixture(), mutate)
        check(not ready and string.find(message, "content pack", 1, true), "missing/stale pack has explicit diagnostic")
    end
end)
suite:Add("unchanged_content_revision_survives_core_only_updates", function(check)
    local data = fixture()
    local ready = validate(data, function(marker)
        if marker.id ~= "core" then marker.releaseId = string.rep("b", 64) end
        return marker
    end)
    check(ready, "old build provenance does not require republishing unchanged content")
    check(not validate(data, function(marker)
        if marker.id == "core" then marker.releaseId = string.rep("b", 64) end
        return marker
    end), "core must still agree with the complete release manifest")
end)
suite:Add("missing_wrong_sized_and_conflicting_files_fail", function(check)
    for _, bytes in ipairs({ -1, 11, 13 }) do check(not validate(fixture(), nil, function() return bytes end), "bad file size rejected") end
    local data = fixture()
    data.packs[2].files[1].path = data.packs[1].files[1].path
    check(not validate(data), "conflicting virtual paths rejected")
end)
suite:Add("malformed_manifest_and_unsafe_paths_fail", function(check)
    for _, mutate in ipairs({
        function(data) data.schemaVersion = 2 end,
        function(data) data.development = "true" end,
        function(data) data.releaseId = "bad" end,
        function(data) data.packs = {} end,
        function(data) data.packs[2].id = "core" end,
        function(data) data.packs[2].files[1].path = "../secret" end,
        function(data) data.packs[2].files[1].bytes = -1 end,
        function(data) table.remove(data.packs, 1) end
    }) do
        local data = fixture()
        mutate(data)
        check(not validate(data), "malformed manifest fails")
    end
    check(not ZM_Distribution.Validate(nil), "missing manifest fails")
end)
suite:Add("installed_game_file_size_matches_known_registry", function(check)
    local path = "data_static/clothing_catalogue.json"
    local content = file.Read(path, "GAME")
    check(content ~= nil and file.Size(path, "GAME") == #content, "GAME file.Size measures actual mounted registry bytes")
end)
suite:Add("release_requires_ids_and_rejects_unfinished_dependency_closure", function(check)
    local data = fixture()
    data.development = false
    check(not validate(data), "release without Workshop IDs fails")
    data = fixture()
    data.integrityErrors = { "Missing navigation: maps/a.nav" }
    check(not validate(data), "unfinished package cannot deploy")
    data = fixture()
    data.packs[1].workshopId, data.packs[2].workshopId = "123", "123"
    check(not validate(data), "one Workshop item cannot own two shards")
end)
suite:Add("deployment_gate_preserves_loose_development_and_checks_clients", function(check)
    local method = ZM_Distribution.CanDeploy
    check(method({ Ready = true }, {}), "loose development requires no package handshake")
    check(not method({ Ready = false, Error = "missing core" }, {}), "server failure blocks deployment")
    local target = {}
    local state = { Ready = true, Manifest = fixture(), Clients = {} }
    check(not method(state, target), "unvalidated client blocked")
    state.Clients[target] = { ready = false, message = "missing clothing" }
    check(not method(state, target), "failed client blocked")
    state.Clients[target].ready = true
    check(method(state, target), "compatible client can deploy")
end)
ZM_TestHarness.Register({ command = "zn_test_distribution", label = "Distribution",
    file = "distribution_test_results.json", report = "distribution_tests",
    help = "Checks packaged content ownership, compatibility and deployment gates without changing assets.",
    run = function() return suite:Run() end })
