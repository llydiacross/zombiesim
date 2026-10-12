local Suite = ZM_TestHarness.NewSuite()
local Presentation = ZM_LauncherPresentation

local function fixtures()
    local world = {
        world = {
            profileId = "preview", grid = { 2, 2 }, gridOrigin = { 1, 1 },
            templatePlanSha256 = "plan", cellBounds = { neighbourPitch = 5760 }
        },
        cells = {
            { map = "northwest" }, { map = "northeast" },
            { map = "southwest" }, { map = "southeast" }
        },
        safeZones = { { id = "den-one", name = "Test Den", cell = 3 } }
    }
    local skyline = {
        schemaVersion = 2, profile = "preview", templatePlanSha256 = "plan", cellSpan = 5760,
        recipes = {
            northwest = { "models/northwest.mdl" }, northeast = { "models/northeast.mdl" },
            southwest = { "models/southwest.mdl" }, southeast = { "models/southeast.mdl" }
        }
    }
    return world, skyline
end

Suite:Add("logical locations resolve without clamping", function(check)
    local world, skyline = fixtures()
    local result = Presentation.ResolveCity(world, skyline, "preview",
        { available = true, state = "city", cellX = 0, cellY = 0 })
    check(result and result.map == "southeast" and result.model == "models/southeast.mdl",
        "full logical coordinates select the exact cell model")
    check(result and #result.models == 4 and result.cellSpan == 5760,
        "edge selection returns its bounded available neighbour cluster")
    local selected = 0
    for _, model in ipairs(result and result.models or {}) do
        if model.selected then selected = selected + 1 end
    end
    check(selected == 1, "cluster identifies only the exact selected cell")
    local start = Presentation.ResolveCity(world, skyline, "preview",
        { available = true, state = "start", cellX = -1, cellY = -1 })
    check(start and start.map == "northwest" and start.state == "start",
        "undeployed start resolves its exact authored origin cell")
    local distant, reason = Presentation.ResolveCity(world, skyline, "preview",
        { available = true, state = "city", cellX = 4, cellY = 4 })
    check(not distant and reason == "saved logical cell is outside the profile",
        "out-of-profile locations fail explicitly")
end)

Suite:Add("den locations use their owning city cell", function(check)
    local world, skyline = fixtures()
    local result = Presentation.ResolveCity(world, skyline, "preview",
        { available = true, state = "den", safeZoneId = "den-one" })
    check(result and result.map == "southeast" and result.label == "Test Den",
        "den presentation resolves through the authored safe-zone owner")
end)

Suite:Add("profile and skyline revisions are strict", function(check)
    local world, skyline = fixtures()
    local location = { available = true, state = "start", cellX = -1, cellY = -1 }
    local result = Presentation.ResolveCity(world, skyline, "city", location)
    check(not result, "profile switching cannot reuse another profile's assets")
    skyline.templatePlanSha256 = "stale"
    local stale, reason = Presentation.ResolveCity(world, skyline, "preview", location)
    check(not stale and reason == "skyline assets are stale", "stale skyline data is explicit")
    skyline.templatePlanSha256 = "plan"
    local missing, missingReason = Presentation.ResolveCity(world, skyline, "preview",
        { available = false, reason = "corrupt resume" })
    check(not missing and missingReason == "corrupt resume", "unavailable saved state retains its reason")
    skyline.recipes.northwest = nil
    local absent, absentReason = Presentation.ResolveCity(world, skyline, "preview", location)
    check(not absent and absentReason == "selected cell skyline model is missing",
        "missing selected-cell assets fail explicitly")
end)

ZM_TestHarness.Register({
    command = "zn_test_launcher_presentation",
    label = "Launcher presentation",
    file = "launcher-presentation-tests.json",
    report = "launcherPresentation",
    help = "Tests bounded launcher city-scene resolution without creating presentation entities.",
    run = function() return Suite:Run() end
})
