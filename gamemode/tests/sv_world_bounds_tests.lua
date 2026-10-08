local Harness = ZM_TestHarness
local suite = Harness.NewSuite()
local function fixture(revision)
    local world = setmetatable({}, { __index = ZM_World })
    world.Data = { world = { cellBounds = {
        revision = revision, tileSize = 640, coreTileGridSize = 5,
        coreHalfExtent = 1600, traversableHalfExtent = 2240,
        visualHalfExtent = revision == 2 and 2880 or 2240,
        neighbourPitch = revision == 2 and 5760 or 4480,
        coastContactHalfExtent = 2240, playableCeiling = 4608
    } } }
    return world
end

suite:Add("legacy_bounds_without_metadata", function(check)
    local world = fixture(1)
    world.Data.world.cellBounds = nil
    local bounds = world:GetCellBounds()
    check(bounds.revision == 1 and bounds.coreHalfExtent == 1600 and bounds.neighbourPitch == 4480,
        "older exports retain their original geometry contract")
end)

suite:Add("expanded_bounds_keep_the_core_fixed", function(check)
    local bounds = fixture(2):GetCellBounds()
    check(bounds.coreHalfExtent == 1600 and bounds.traversableHalfExtent == 2240
        and bounds.visualHalfExtent == 2880 and bounds.neighbourPitch == 5760,
        "spawn, traversal and visual extents remain distinct")
end)

suite:Add("all_core_edges_are_inclusive", function(check)
    local world = fixture(2)
    for _, position in ipairs({Vector(-1600, 0, 32), Vector(1600, 0, 32), Vector(0, -1600, 32), Vector(0, 1600, 32)}) do
        check(world:IsCoreSpawnPosition(position), "a position on the core boundary remains eligible")
    end
end)

suite:Add("borders_and_scenery_are_not_spawn_areas", function(check)
    local world = fixture(2)
    for _, position in ipairs({Vector(-1601, 0, 32), Vector(1601, 0, 32), Vector(0, -1601, 32), Vector(0, 1601, 32), Vector(2560, 0, 32)}) do
        check(not world:IsCoreSpawnPosition(position), "reachable border and inaccessible scenery remain ineligible")
    end
end)

suite:Add("sky_room_and_nonfinite_positions_are_ineligible", function(check)
    local world = fixture(2)
    check(not world:IsCoreSpawnPosition(Vector(0, 0, 5120)), "the sky room cannot supply spawn nav areas")
    check(not world:IsCoreSpawnPosition({ x = math.huge, y = 0, z = 32 }), "infinite positions are ineligible")
    check(not world:IsCoreSpawnPosition({ x = 0, y = 0, z = -math.huge }), "infinite height is ineligible")
    check(not world:IsCoreSpawnPosition({ x = 0 / 0, y = 0, z = 32 }), "NaN positions are ineligible")
end)

suite:Add("coast_contact_does_not_move_with_visual_pitch", function(check)
    local world = fixture(2)
    world.ResolveCell = function() return { waterSides = {"N", "W"} } end
    check(world:GetCellSideExtent(0, "N") == 2240 and world:GetCellSideExtent(0, "W") == 2240,
        "omitted sides retain ocean contact")
    check(world:GetCellSideExtent(0, "S") == 2880 and world:GetCellSideExtent(0, "E") == 2880,
        "land sides include the new scenery ring")
    local value, reason = world:GetCellSideExtent(0, "up")
    check(value == nil and reason ~= nil, "invalid sides report an explicit error")
end)

Harness.Register({
    command = "zn_test_world_bounds",
    label = "World bounds",
    file = "world_bounds_tests.json",
    report = "world_bounds_tests",
    help = "Tests isolated legacy/expanded bounds and spawn/coast eligibility without changing live state.",
    run = function() return suite:Run() end
})
