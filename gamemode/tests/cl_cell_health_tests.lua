local function png(width, height)
    local function uint32(value)
        return string.char(
            math.floor(value / 16777216) % 256,
            math.floor(value / 65536) % 256,
            math.floor(value / 256) % 256,
            value % 256
        )
    end
    local signature = "\137PNG\r\n\26\n"
    local header = "\0\0\0\13IHDR" .. uint32(width) .. uint32(height) .. string.char(8, 2, 0, 0, 0) .. "CRC!"
    local imageData = "\0\0\0\1IDATxCRC!"
    local endMarker = "\0\0\0\0IEND\174B\96\130"
    return signature .. header .. imageData .. endMarker
end

local function makeManifest(cells)
    return {
        schemaVersion = 1,
        profile = "preview",
        mapManifestSha256 = "old-map-revision",
        templatePlanSha256 = "old-plan-revision",
        complete = false,
        variants = {
            clear = { complete = false, cells = {}, metadata = {} },
            atmospheric = { complete = false, cells = {}, metadata = {} }
        }
    }
end

local function createFixtureEngine()
    local files = {}
    return {
        Add = function(path, value) files[path] = value end,
        Exists = function(path) return files[path] ~= nil end,
        Size = function(path) return files[path] and #files[path] or -1 end,
        Read = function(path) return files[path] end
    }
end

local function buildSuite(contract, engine)
    local suite = ZM_TestHarness.NewSuite()

    suite:Add("PNG validity checks the signature, dimensions and end marker", function(check)
        local valid = png(256, 256)
        local parsed = contract.ParsePngHeader(valid)
        check(parsed and parsed.width == 256 and parsed.height == 256, "valid square PNG header is accepted")
        local badSignature = "notpng" .. string.sub(valid, 7)
        check(contract.ParsePngHeader(badSignature) == nil, "invalid PNG signature is rejected")
        check(contract.ParsePngHeader(string.sub(valid, 1, 20)) == nil, "truncated PNG is rejected")
        local badEnd = string.sub(valid, 1, #valid - 12) .. "bad-end-marker"
        check(contract.ParsePngHeader(badEnd) == nil, "missing IEND marker is rejected")
        check(contract.ParsePngHeader(png(0, 256)) == nil, "zero-sized PNG is rejected")
    end)

    suite:Add("cell color requires all three artifacts for green", function(check)
        local state, count = contract.Classify(false, false, false)
        check(state == "red" and count == 0, "no artifacts produces red")
        state, count = contract.Classify(true, false, false)
        check(state == "orange" and count == 1, "one complete artifact produces orange")
        state, count = contract.Classify(true, false, true)
        check(state == "orange" and count == 2, "unverified cubemaps prevent a false green")
        state, count = contract.Classify(true, true, true)
        check(state == "green" and count == 3, "all three complete artifacts produce green")
    end)

    suite:Add("cubemap completion is an explicit user confirmation", function(check)
        local worldData = {
            world = { grid = { 2, 2 } },
            cells = {
                { id = 0, x = 0, y = 0, map = "map_a" },
                { id = 1, x = 1, y = 0, map = "map_a" },
                { id = 2, x = 0, y = 1, map = "map_b" },
                { id = 3, x = 1, y = 1, map = "map_b" }
            }
        }
        local snapshot = contract.BuildSnapshot(worldData, makeManifest(), createFixtureEngine(), nil, {
            map_a = { confirmed = true, confirmedAt = 100 }
        })
        check(snapshot.cells[1].cubemaps.complete and snapshot.cells[1].cubemaps.state == "user-confirmed",
            "a positive user response is recorded as user-confirmed, not engine-verified")
        check(snapshot.cells[2].cubemaps.complete and snapshot.summary.cubemapCells == 2,
            "confirmation applies to every logical cell sharing that map")
        check(not snapshot.cells[3].cubemaps.complete and snapshot.cells[3].cubemaps.state == "unverified",
            "a different map remains unverified")
    end)

    suite:Add("batch selection includes cells missing any selected artifact only", function(check)
        local snapshot = {
            cells = {
                { id = 0, navmesh = { complete = true }, photos = { complete = false }, cubemaps = { complete = true } },
                { id = 1, navmesh = { complete = false }, photos = { complete = true }, cubemaps = { complete = false } },
                { id = 2, navmesh = { complete = true }, photos = { complete = true }, cubemaps = { complete = true } }
            }
        }
        local jobs = contract.BuildBatchSelection(snapshot, { navmesh = true, photos = true, cubemaps = true })
        check(#jobs == 2, "the union of selected missing artifacts chooses two cells")
        check(jobs[1].id == 0 and jobs[1].photos and not jobs[1].navmesh and not jobs[1].cubemaps,
            "a cell only schedules its missing photo work")
        check(jobs[2].id == 1 and jobs[2].navmesh and jobs[2].cubemaps and not jobs[2].photos,
            "a cell only schedules its missing navmesh and cubemap work")
        local empty, failure = contract.BuildBatchSelection(snapshot, {
            navmesh = false, photos = false, cubemaps = false
        })
        check(empty == nil and failure == "Select at least one artifact to process.",
            "an empty selection is rejected explicitly")
    end)

    suite:Add("snapshot checks current-map photos and deduplicates navmesh files", function(check)
        local worldData = {
            world = { grid = { 2, 2 }, mapDirectory = "", mapManifestSha256 = "current", templatePlanSha256 = "current" },
            cells = {
                { id = 3, x = 1, y = 1, map = "map_b" },
                { id = 1, x = 1, y = 0, map = "map_a" },
                { id = 2, x = 0, y = 1, map = "map_b" },
                { id = 0, x = 0, y = 0, map = "map_a" }
            }
        }
        local manifest = makeManifest()
        local function addPhoto(variant, id, mapName, contents)
            local path = "worlds/preview/captured/" .. variant .. "/cell_" .. id .. ".png"
            manifest.variants[variant].cells[tostring(id)] = path
            manifest.variants[variant].metadata[tostring(id)] = { map = mapName }
            if contents then engine.Add("materials/" .. path, contents) end
        end
        local validPng = png(256, 256)
        addPhoto("clear", 0, "map_a", validPng)
        addPhoto("atmospheric", 0, "map_a", validPng)
        addPhoto("clear", 1, "old_map_a", validPng)
        addPhoto("atmospheric", 1, "old_map_a", validPng)
        addPhoto("clear", 2, "map_b", validPng)
        engine.Add("maps/map_a.nav", "NAV")

        local snapshot, failure = contract.BuildSnapshot(worldData, manifest, engine)
        check(snapshot ~= nil, "valid preview world is scanned" .. (failure and ": " .. failure or ""))
        if not snapshot then return end

        check(#snapshot.cells == 4 and snapshot.cells[1].id == 0 and snapshot.cells[4].id == 3,
            "cells are returned in row-major grid order")
        check(snapshot.cells[1].navmesh.complete and snapshot.cells[1].photos.complete
            and snapshot.cells[1].state == "orange",
            "valid navmesh and both current-map photos count, but unverified cubemaps stay incomplete")
        check(snapshot.cells[2].navmesh.complete and not snapshot.cells[2].photos.complete
            and snapshot.cells[2].photos.clear.reason == "Capture was made for a different or unknown map.",
            "photo metadata for an old recipe does not count for the current map")
        check(not snapshot.cells[3].navmesh.complete and not snapshot.cells[3].photos.complete
            and snapshot.cells[3].state == "red",
            "one photo variant alone is not a complete world photo")
        check(snapshot.summary.navmeshMaps == 2 and snapshot.summary.navmeshCells == 2,
            "two unique recipe maps require only two navmesh file checks")
        check(snapshot.summary.photoCells == 1 and snapshot.summary.clearPhotoCells == 2
            and snapshot.summary.atmosphericPhotoCells == 1,
            "photo coverage counts complete logical cells and each variant separately")
        check(snapshot.summary.orange == 2 and snapshot.summary.red == 2 and snapshot.summary.green == 0,
            "aggregate colors match the artifact states")
        check(snapshot.photoManifestError == nil and snapshot.cells[1].cubemaps.state == "unverified",
            "revision hashes are not required and cubemap uncertainty is visible")
    end)

    suite:Add("manifest identity and cell grid errors are explicit", function(check)
        local worldData = {
            world = { grid = { 1, 1 } },
            cells = { { id = 0, x = 0, y = 0, map = "map_a" } }
        }
        local wrongProfile = makeManifest()
        wrongProfile.profile = "city"
        local snapshot = contract.BuildSnapshot(worldData, wrongProfile, engine)
        check(snapshot and snapshot.photoManifestError ~= nil and not snapshot.cells[1].photos.complete,
            "a non-preview photo manifest is reported as unavailable")
        local invalidGrid = { world = { grid = { 2, 1 } }, cells = worldData.cells }
        local invalidSnapshot, failure = contract.BuildSnapshot(invalidGrid, wrongProfile, engine)
        check(invalidSnapshot == nil and failure == "Preview world grid is incomplete or invalid.",
            "incomplete preview grids fail explicitly")
    end)

    return suite
end

concommand.Remove("zombiesim_dev_test_cell_health_client")
concommand.Add("zombiesim_dev_test_cell_health_client", function()
    local player = LocalPlayer()
    if not IsValid(player) or not player:IsAdmin() or not ZM_World or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Cell Health tests require a preview admin.\n")
        return
    end

    local contract = ZM_CellHealth and ZM_CellHealth.Contract
    if not contract then
        ErrorNoHalt("[ZombieSim] Cell Health contract is unavailable.\n")
        return
    end
    local suite = buildSuite(contract, createFixtureEngine())
    suite:Add("installed snapshot covers the active preview world", function(check)
        local snapshot, failure = ZM_CellHealth:GetSnapshot()
        check(snapshot ~= nil, "preview snapshot loads" .. (failure and ": " .. failure or ""))
        if not snapshot then return end
        check(snapshot.summary.total == #ZM_World:GetData().cells, "every logical cell is represented")
        check(snapshot.summary.green + snapshot.summary.orange + snapshot.summary.red == snapshot.summary.total,
            "every cell has exactly one status color")
        check(snapshot.summary.cubemapCells <= snapshot.summary.total,
            "only explicit user-confirmed cubemaps count as complete")
    end)
    local summary = suite:Run()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/cell_health_tests.json", util.TableToJSON(summary, true) or "{}")
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Cell Health " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do
            ErrorNoHalt("[ZombieSim] " .. failure .. "\n")
        end
    end
    print(string.format(
        "[ZombieSim] Cell Health client tests: %d passed, %d failed. Report: data/zombiesim/cell_health_tests.json",
        summary.passed, summary.failed
    ))
end)

return function(createEngine, loadFactory)
    local contract = loadFactory("sh_cell_health_contract.lua")()
    return buildSuite(contract, createEngine())
end
