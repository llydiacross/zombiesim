local Harness = ZM_TestHarness
local Geometry = ZM_SkyboxGeometry
local suite = Harness.NewSuite()

local function fixture(sides)
    local bounds = {
        revision = 2, tileSize = 640, coreTileGridSize = 5, coreHalfExtent = 1600,
        traversableHalfExtent = 2240, visualHalfExtent = 2880, neighbourPitch = 5760,
        coastContactHalfExtent = 2240, playableCeiling = 4608
    }
    local manifest = {
        schemaVersion = 2, profile = "preview", scale = 16, cellSpan = 5760, cellBounds = table.Copy(bounds),
        templatePlanSha256 = string.rep("a", 64), recipes = {fixture = {}},
        geometry = {fixture = {waterSides = sides or {}, coastHalfExtent = 2240,
            visualHalfExtent = 2880, vmfSha256 = string.rep("b", 64)}}
    }
    return manifest, {profileId = "preview", cellBounds = bounds, templatePlanSha256 = manifest.templatePlanSha256}
end

suite:Add("matching_expanded_manifest", function(check)
    local manifest, world = fixture({"N", "W"})
    check(Geometry.ValidateManifest(manifest, world, {{map = "fixture", waterSides = {"W", "N"}}}),
        "matching plans, bounds and side sets are compatible regardless of side order")
end)

suite:Add("legacy_compatibility_and_mixed_revision_rejection", function(check)
    local manifest, world = fixture()
    check(Geometry.ValidateManifest({schemaVersion = 1}, {}), "loose legacy skyline remains supported")
    check(not Geometry.ValidateManifest({schemaVersion = 1}, world), "legacy skyline cannot render an expanded world")
    check(not Geometry.ValidateManifest(manifest, {}), "expanded skyline cannot render a legacy world")
end)

suite:Add("stale_plan_and_bounds_rejection", function(check)
    local manifest, world = fixture()
    manifest.templatePlanSha256 = string.rep("c", 64)
    check(not Geometry.ValidateManifest(manifest, world), "different plan rejects the skyline")
    manifest.templatePlanSha256 = world.templatePlanSha256
    manifest.profile = "city"
    check(not Geometry.ValidateManifest(manifest, world), "different world profile rejects the skyline")
    manifest.profile = world.profileId
    for key, value in pairs(manifest.cellBounds) do
        manifest.cellBounds[key] = value + 1
        check(not Geometry.ValidateManifest(manifest, world), "changed " .. key .. " rejects the skyline")
        manifest.cellBounds[key] = value
    end
end)

suite:Add("footprint_and_coast_rejection", function(check)
    local manifest, world = fixture({"N"})
    check(not Geometry.ValidateManifest(manifest, world, {{map = "fixture", waterSides = {"W"}}}),
        "same plan with different coast is rejected")
    manifest.geometry.fixture.waterSides = {"N", "N"}
    check(not Geometry.ValidateManifest(manifest, world), "duplicate sides are rejected")
    manifest.geometry.fixture.waterSides = {"up"}
    check(not Geometry.ValidateManifest(manifest, world), "unknown sides are rejected")
    manifest.geometry.fixture = nil
    check(not Geometry.ValidateManifest(manifest, world), "missing recipe footprint is rejected")
end)

suite:Add("all_cardinal_and_mixed_coast_masks", function(check)
    local cardinals = {"N", "E", "S", "W"}
    for mask = 0, 15 do
        local sides, omitted = {}, {}
        for index, side in ipairs(cardinals) do
            if bit.band(mask, bit.lshift(1, index - 1)) ~= 0 then
                table.insert(sides, side)
                omitted[side] = true
            end
        end
        local manifest = fixture(sides)
        for _, origin in ipairs({{0, 0}, {360, -360}, {-720, 720}}) do
            local x, y = origin[1], origin[2]
            local rectangle = Geometry.GetLandRectangle(manifest, "fixture", x, y)
            check(rectangle.x0 == x - (omitted.W and 140 or 180) and rectangle.x1 == x + (omitted.E and 140 or 180)
                and rectangle.y0 == y - (omitted.S and 140 or 180) and rectangle.y1 == y + (omitted.N and 140 or 180),
                "every side retains 2240 coast or 2880 land extent at every neighbour offset")
            local bands = Geometry.GetWaterBands(rectangle, x, y, 180)
            local area = (rectangle.x1 - rectangle.x0) * (rectangle.y1 - rectangle.y0)
            for index, band in ipairs(bands) do
                check(band.halfX > 0 and band.halfY > 0, "water bands have positive dimensions")
                area = area + 4 * band.halfX * band.halfY
                for other = index + 1, #bands do
                    local b = bands[other]
                    check(math.abs(band.x - b.x) >= band.halfX + b.halfX
                        or math.abs(band.y - b.y) >= band.halfY + b.halfY,
                        "mixed corner bands do not overlap")
                end
            end
            check(area == 360 * 360, "land plus water bands exactly cover each pitch square")
        end
    end
end)

suite:Add("cardinal_land_joins_and_north_sign", function(check)
    local manifest = fixture()
    local current = Geometry.GetLandRectangle(manifest, "fixture", 0, 0)
    local east = Geometry.GetLandRectangle(manifest, "fixture", 360, 0)
    local west = Geometry.GetLandRectangle(manifest, "fixture", -360, 0)
    local north = Geometry.GetLandRectangle(manifest, "fixture", 0, 360)
    local south = Geometry.GetLandRectangle(manifest, "fixture", 0, -360)
    check(current.x1 == east.x0 and current.x0 == west.x1
        and current.y1 == north.y0 and current.y0 == south.y1,
        "all four neighbours meet exactly; north is physical +Y")
end)

suite:Add("storm_drain_west_ocean_meets_border_without_gap", function(check)
    local manifest = fixture({"W"})
    for _, origin in ipairs({{0, 0}, {0, 360}, {0, -360}}) do
        local x, y = origin[1], origin[2]
        local rectangle = Geometry.GetLandRectangle(manifest, "fixture", x, y)
        check((rectangle.x0 - x) * manifest.scale == -2240,
            "west shoreline attaches to the previous border, not the new -2880 edge")
        local bands = Geometry.GetWaterBands(rectangle, x, y, 180)
        check(#bands == 1 and bands[1].x - bands[1].halfX == x - 180
            and bands[1].x + bands[1].halfX == rectangle.x0
            and bands[1].y - bands[1].halfY == y - 180
            and bands[1].y + bands[1].halfY == y + 180,
            "water/beach band covers the entire omitted western layer and meets adjacent ocean exactly")
        check(rectangle.x1 == x + 180 and rectangle.y0 == y - 180 and rectangle.y1 == y + 180,
            "only the ocean-facing side changes; the other three sides retain expanded land joins")
    end
end)

suite:Add("coast_distance_and_fog_boundary", function(check)
    local manifest = fixture({"W", "N"})
    local rectangle = Geometry.GetLandRectangle(manifest, "fixture", 0, 0)
    check(Geometry.DistanceToLand(-140, 0, rectangle) == 0 and Geometry.DistanceToLand(-180, 0, rectangle) == 40,
        "coast samples start at the old physical border")
    check(math.abs(Geometry.DistanceToLand(-180, 180, rectangle) - math.sqrt(3200)) < 0.00001,
        "mixed corners use distance to the actual rectangular shore")
    check(Geometry.GetFogBoundary(manifest) == 2240
        and Geometry.GetFogBoundary({schemaVersion = 1, cellSpan = 4480}) == 2240,
        "fog continuation does not move outward with neighbour pitch")
end)

suite:Add("coast_grid_has_no_mixed_corner_t_junctions", function(check)
    for _, divisions in ipairs({32, 42}) do
        for _, centre in ipairs({0, 360, -720}) do
            local whole, count = Geometry.GetCoastAxis(centre - 180, centre + 180, centre, 360, divisions, 140)
            for _, bounds in ipairs({{-180, -140}, {-140, 140}, {140, 180}}) do
                local part, partCount = Geometry.GetCoastAxis(centre + bounds[1], centre + bounds[2], centre, 360, divisions, 140)
                for index = -1, partCount + 1 do
                    local found = false
                    for wholeIndex = -1, count + 1 do
                        if math.abs(part[index] - whole[wholeIndex]) < 0.000001 then found = true break end
                    end
                    check(found, "band vertices and normal samples coincide with the full-slot grid")
                end
            end
            local adjacent = Geometry.GetCoastAxis(centre + 180, centre + 540, centre + 360, 360, divisions, 140)
            check(math.abs(whole[count + 1] - adjacent[1]) < 0.000001
                and math.abs(whole[count - 1] - adjacent[-1]) < 0.000001,
                "neighbour slots share normal samples across their boundary")
        end
        local legacy, count = Geometry.GetCoastAxis(-140, 140, 0, 280, divisions)
        check(count == divisions, "legacy grid retains its original subdivision count")
        for index = -1, divisions + 1 do
            check(math.abs(legacy[index] - (-140 + index * 280 / divisions)) < 0.000001,
                "legacy grid retains every original coordinate")
        end
    end
end)

suite:Add("current_edge_fire_cap_and_stability", function(check)
    local rows = {}
    for index = 1, 12 do rows[index] = {index * 640, 2560, 384, 2} end
    local selected = Geometry.SelectEdgeFireAnchors(rows, 0, 12)
    local repeated = Geometry.SelectEdgeFireAnchors(rows, 0, 12)
    check(#selected == 6, "six spaced edge buildings burn when available")
    check(#rows == 12, "selection does not mutate generated anchors")
    for index, row in ipairs(selected) do
        check(row == repeated[index], "the same cell keeps the same building burning")
    end
    check(#Geometry.SelectEdgeFireAnchors({}, 0, 12) == 0, "empty edges produce no fires")
    check(#Geometry.SelectEdgeFireAnchors({rows[1]}, 0, 12) == 1, "scarce eligible buildings are not duplicated")
    check(#Geometry.SelectEdgeFireAnchors({rows[1], rows[1], {rows[1][1] + 100, 2560, 384, 2}}, 0, 12) == 1,
        "duplicate and adjacent rooftop anchors cannot stack fires")
end)

Harness.Register({
    command = "zn_test_skybox_geometry",
    label = "Skybox geometry",
    file = "skybox_geometry_tests.json",
    report = "skybox_geometry_tests",
    help = "Tests isolated skyline compatibility, cardinal joins and mixed coast bands without changing live state.",
    run = function() return suite:Run() end
})
