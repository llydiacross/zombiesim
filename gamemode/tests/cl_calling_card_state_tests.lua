return function(createState)
    local suite = ZM_TestHarness.NewSuite()

    local function packet(serial, part, total, ids)
        return {
            serial = serial, part = part, total = total, ok = true, message = "Loaded.", requestId = "fixture",
            background = "background_default", detail = "detail_default", ids = ids
        }
    end

    suite:Add("chunked responses publish only complete ownership", function(check)
        local state = createState(ZM_CallingCards.Category)
        local second = packet(1, 2, 2, { "detail_test" })
        check(state:Push(second) == "pending", "an out-of-order part does not publish partial data")
        check(state:Push(second) == "ignored", "a repeated part is not counted twice")
        local status, snapshot = state:Push(packet(1, 1, 2, { "background_default", "detail_default", "background_test" }))
        check(status == "complete" and snapshot.available and snapshot.owned.detail_test
            and snapshot.owned.background_test and snapshot.selection.background == "background_default",
            "both parts assemble into one complete snapshot")
        check(state:Push(second) == "ignored", "a completed serial cannot publish twice")
    end)

    suite:Add("newer responses supersede stale parts, including serial wrap", function(check)
        local state = createState(ZM_CallingCards.Category)
        state:Push(packet(4, 1, 2, { "background_default" }))
        local status, snapshot = state:Push(packet(5, 1, 1, { "background_default", "detail_default" }))
        check(status == "complete" and snapshot.available, "a newer complete response supersedes an unfinished one")
        check(state:Push(packet(4, 2, 2, { "detail_default" })) == "ignored", "late older parts are ignored")
        local wrapped = createState(ZM_CallingCards.Category)
        wrapped:Push(packet(4294967294, 1, 1, { "background_default", "detail_default" }))
        check(wrapped:Push(packet(1, 1, 1, { "background_default", "detail_default" })) == "complete",
            "serial one follows the server's maximum serial")
        check(wrapped:Push(packet(4294967294, 1, 1, { "background_default", "detail_default" })) == "ignored",
            "a pre-wrap response remains stale after wrap")
    end)

    suite:Add("malformed and inconsistent responses fail explicitly", function(check)
        local state = createState(ZM_CallingCards.Category)
        local first = packet(1, 1, 2, { "background_default" })
        state:Push(first)
        local inconsistent = packet(1, 2, 2, { "detail_default" })
        inconsistent.message = "Different."
        local status, message = state:Push(inconsistent)
        check(status == "error" and string.find(message, "do not match", 1, true) ~= nil,
            "parts with inconsistent metadata cannot publish")
        state = createState(ZM_CallingCards.Category)
        state:Push(packet(1, 1, 2, { "background_default", "detail_default" }))
        status, message = state:Push(packet(1, 2, 2, { "detail_default" }))
        check(status == "error" and string.find(message, "repeats", 1, true) ~= nil,
            "duplicates across chunks are rejected")
        state = createState(ZM_CallingCards.Category)
        local invalid = packet(1, 1, 1, { "background_default", "detail_default" })
        invalid.detail = "background_default"
        check(state:Push(invalid) == "error", "a selection from the wrong category is rejected")
        invalid = packet(2, 1, 1, { "background_default", "detail_default", "bad-id" })
        check(state:Push(invalid) == "error", "an invalid ownership ID is rejected")
    end)

    suite:Add("server failures remain failures and retain valid snapshots", function(check)
        local state = createState(ZM_CallingCards.Category)
        local failure = packet(1, 1, 1, {})
        failure.ok, failure.message, failure.background, failure.detail = false, "No active survivor.", "", ""
        local status, snapshot = state:Push(failure)
        check(status == "complete" and not snapshot.ok and not snapshot.available
            and snapshot.message == "No active survivor.", "an unavailable store is not represented as a successful snapshot")
        local rejected = packet(2, 1, 1, { "background_default", "detail_default" })
        rejected.ok, rejected.message = false, "That design is locked."
        status, snapshot = state:Push(rejected)
        check(status == "complete" and snapshot.available and not snapshot.ok
            and snapshot.message == "That design is locked.", "a rejected operation can still refresh authoritative ownership")
    end)

    if concommand then
        concommand.Add("zombiesim_dev_test_calling_card_client", function()
            if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
                ErrorNoHalt("[ZombieSim] Calling-card client tests require a preview admin.\n")
                return
            end
            local summary = suite:Run()
            file.CreateDir("zombiesim")
            file.Write("zombiesim/calling_card_client_tests.json", util.TableToJSON(summary, true))
            for _, result in ipairs(summary.cases) do
                print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
                for _, failure in ipairs(result.failures) do print("[ZombieSim]   " .. failure) end
            end
            print(string.format("[ZombieSim] Calling-card client tests: %d passed, %d failed.", summary.passed, summary.failed))
        end, nil, "Runs isolated calling-card client response fixtures.")
    end
    return suite
end
