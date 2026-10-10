local Music = ZM_Music
local suite = ZM_TestHarness.NewSuite()
local function test(name, body) suite:Add(name, body) end
local function source()
    return util.JSONToTable(file.Read(ZM_StaticData.Files.music, "GAME") or "")
end
local function validate(data, exists)
    local tags, zones = Music.RoutingKeys()
    return Music.Validate(data, exists or function(path) return file.Exists(path, "GAME") end, tags, zones)
end
local function registry() return ZM_StaticData:GetRegistry().music end

test("shipped_music_has_all_valid_files_and_measured_durations", function(check)
    local data, issues = validate(source())
    check(data ~= nil and #issues == 0, "the shipped music registry validates")
    if not data then return end
    check(table.Count(data.tracks) == 8 and #data.sets.city == 5 and #data.sets.sewer == 3,
        "all eight authored city/sewer variations are registered")
    for _, track in pairs(data.tracks) do
        check((track.duration == nil or track.duration > 0) and file.Exists(track.file, "GAME"),
            track.id .. " has optional valid duration and real packaged file")
    end
end)

test("music_rejects_duplicate_ids_missing_defaults_files_and_bad_durations", function(check)
    for _, mutate in ipairs({
        function(data) data.tracks[2].id = data.tracks[1].id end,
        function(data) data.defaultSet = "missing" end,
        function(data) data.tracks[1].file = "sounds/music/missing.mp3" end,
        function(data) data.tracks[1].duration = 0 end,
        function(data) data.tracks[1].duration = math.huge end,
        function(data) data.sets.city[2] = data.sets.city[1] end,
        function(data) data.idleSeconds = { 720, 480 } end
    }) do
        local data = source()
        mutate(data)
        local result, issues = validate(data)
        check(result == nil and #issues > 0, "invalid music definitions are rejected explicitly")
    end
end)

test("workshop_sound_root_and_loose_development_music_both_validate", function(check)
    local data = source()
    for _, track in ipairs(data.tracks) do track.file = string.gsub(track.file, "^sounds/", "sound/") end
    local result, issues = validate(data, function(path) return string.match(path, "^sound/music/") ~= nil end)
    check(result ~= nil and #issues == 0, "canonical Workshop sound paths validate without breaking developer sounds paths")
end)

test("music_rejects_unknown_tags_zones_and_malformed_mapping_shapes", function(check)
    for _, mutate in ipairs({
        function(data) data.environmentTags.misspelled_environment = "city" end,
        function(data) data.safeZones["safezone-999-999"] = "sewer" end,
        function(data) data.environmentTags = 123 end,
        function(data) data.tagPriority = { "unknown" } end,
        function(data) data.sets.city = "not-an-array" end,
        function(data) data.tracks = false end
    }) do
        local data = source()
        mutate(data)
        local result, issues = validate(data)
        check(result == nil and #issues > 0, "malformed routing data reports validation errors rather than crashing")
    end
end)

test("routing_prioritises_den_then_authored_environment_then_default", function(check)
    local data = registry()
    check(Music.Resolve(data, { safeZoneId = "safezone-0-12", isOrigin = true, tags = { "grassland" } }) == "sewer",
        "origin Storm Drain den resolves to sewer music independent of its BSP name")
    check(Music.Resolve(data, { safeZoneId = "other-den", tags = { "metro_station" } }) == "city",
        "an unmapped den uses its default, not the entrance cell's metro music")
    local set, key = Music.Resolve(data, { tags = { "grassland", "metro_route", "metro_station" } })
    check(set == "sewer" and key == "environment:metro_station", "authored priority is independent of tag array order")
    check(Music.Resolve(data, { tags = { "grassland" } }) == "city", "unmapped city terrain has a valid default")
end)

test("variation_and_idle_schedule_use_the_authored_bounds", function(check)
    local data = registry()
    for _, set in ipairs({ "city", "sewer" }) do
        check(Music.Select(data, set, function(minimum) return minimum end) == data.sets[set][1], "first variation can be selected")
        check(Music.Select(data, set, function(_, maximum) return maximum end) == data.sets[set][#data.sets[set]],
            "last variation can be selected")
    end
    check(Music.IdleDelay(data, function(minimum) return minimum end) == 480, "minimum idle is exactly eight minutes")
    check(Music.IdleDelay(data, function(_, maximum) return maximum end) == 720, "maximum idle is exactly twelve minutes")
end)

test("travel_resumes_same_set_switches_city_sets_and_silences_den_exit", function(check)
    local data = registry()
    local city = { trackId = "cityA", routeSet = "city", position = 30, nextAt = 0 }
    local sewer = { trackId = "sewerA", routeSet = "sewer", position = 30, nextAt = 0 }
    local den = { trackId = "sewerA", routeSet = "sewer", safeZoneId = "safezone-0-12", position = 30, nextAt = 0 }
    local metro = { tags = { "metro_route" } }
    check(Music.TransitionAction(city, data, { tags = { "grassland" } }) == "resume",
        "ordinary city travel within the same set preserves song position")
    local action, set = Music.TransitionAction(city, data, metro)
    check(action == "switch" and set == "sewer", "cell travel into metro starts its destination set immediately")
    action, set = Music.TransitionAction(sewer, data, { tags = {} })
    check(action == "switch" and set == "city", "leaving metro cannot carry sewer music into ordinary city")
    check(Music.TransitionAction(den, data, { tags = {} }) == "silence",
        "leaving a playing safe-zone track schedules fresh silence")
    check(Music.TransitionAction(den, data, metro) == "silence",
        "den exit also ends the track when the entrance cell uses the same sewer set")
    local inside = { safeZoneId = "safezone-0-12", isOrigin = true, tags = {} }
    check(Music.TransitionAction(den, data, inside) == "resume", "reloading the same den preserves its track")
    check(Music.TransitionAction(sewer, data, inside) == "switch", "den entry starts its own destination track")
    check(Music.TransitionAction({ nextAt = 1000, routeSet = "city" }, data, metro) == "wait",
        "travel during silence preserves the pending deadline")
    check(Music.TransitionAction({ trackId = "sewerA" }, data, { tags = {} }) == "switch",
        "legacy resume records cannot leak the wrong set into a destination")
    check(Music.TransitionAction({ trackId = "cityA" }, data, { tags = {} }) == "resume",
        "compatible legacy records still resume")
    check(Music.TransitionAction({ trackId = "cityA", routeSet = "sewer" }, data, metro) == "resume",
        "a default failure fallback is not repeatedly replaced in its unchanged destination")
end)

test("resume_records_require_a_known_track_and_finite_in_range_position", function(check)
    local data = registry()
    check(Music.ValidResume({ version = 1, trackId = "cityA", position = 30, nextAt = 0 }, data),
        "a known interrupted track preserves its position")
    check(Music.ValidResume({ version = 1, nextAt = 1000 }, data), "a silent interval can survive a map change")
    for _, saved in ipairs({
        { version = 1, trackId = "missing", position = 0, nextAt = 0 },
        { version = 1, trackId = "cityA", position = -1, nextAt = 0 },
        { version = 1, trackId = "cityA", position = math.huge, nextAt = 0 },
        { version = 1, trackId = "cityA", position = data.tracks.cityA.duration, nextAt = 0 },
        { version = 1, nextAt = 0 / 0 },
        { version = 1, nextAt = 0, routeSet = "missing" },
        { version = 1, nextAt = 0, safeZoneId = false },
        { version = 1, nextAt = 0, safeZoneId = "" }
    }) do
        check(not Music.ValidResume(saved, data), "invalid persisted playback state is rejected")
    end
end)

test("actual_channel_durations_are_finite_and_match_the_catalogue", function(check)
    check(Music.DurationMatches(187.62097916667, nil), "omitted duration accepts the full decoded replacement track")
    check(not Music.DurationMatches(0, nil) and not Music.DurationMatches(math.huge, nil),
        "omitted duration does not accept invalid decoder results")
    local data = registry()
    check(Music.ValidResume({ version = 1, trackId = "cityE", position = 185, nextAt = 0 }, data),
        "optional-duration resume is checked against the decoded channel when loaded")
    check(Music.DurationMatches(116.328, 116.328), "measured MP3 duration matches exactly")
    check(not Music.DurationMatches(0, 116.328) and not Music.DurationMatches(math.huge, 116.328),
        "empty/invalid decoder results are not successful playback")
    check(not Music.DurationMatches(31, 116.328), "wrong track content is rejected")
end)

test("music_gain_tracks_the_game_music_slider_without_double_master_scaling", function(check)
    check(Music.OutputGain(0, 0) == 0, "the engine music slider can mute music")
    check(Music.OutputGain(0.45, 0) == 0.45, "unexposed playback exactly follows the music slider")
    check(Music.OutputGain(1, 1) == 0.55, "high Geiger exposure ducks music by at most 45 percent")
    check(Music.OutputGain(0.5, 0) == 0.5, "Source master/SFX scaling is not duplicated in the channel gain")
end)

ZM_TestHarness.Register({
    command = "zn_test_music", label = "Music", file = "music_tests.json", report = "musicTests",
    help = "Validates music files, routing, variations, idle bounds and resume records.",
    run = function() return suite:Run() end
})
