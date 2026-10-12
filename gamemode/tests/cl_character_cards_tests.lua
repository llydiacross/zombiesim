concommand.Add("zombiesim_dev_test_character_cards", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Character card tests require a preview admin.\n")
        return
    end

    local Cards = ZM_CharacterCards
    local suite = ZM_TestHarness.NewSuite()
    local root = vgui.Create("DPanel")
    root:SetSize(640, 720)
    root:SetVisible(false)
    local originalApply = ZM_Clothing.Apply
    local ownedPanels = {}
    local function row(slot, revision)
        local result = {
            slot = slot,
            presentationRevision = revision,
            appearance = {
                model = ZM_CharacterRules.Models[slot] or ZM_CharacterRules.Models[1],
                skin = 0,
                bodygroups = {},
                playerColour = { 1, 1, 1 }
            },
            outfit = { shirt = "", pants = "" }
        }
        if slot == 1 then
            result.weapons = {
                { slot = 1, itemId = "weaponMeleeHammer", name = "Hammer", selected = true,
                    worldModel = "models/zombiesim/imported/hammer/w_hammer.mdl" },
                { slot = 2, itemId = "weaponMeleeCrowbar", name = "Crowbar", selected = false,
                    worldModel = "models/weapons/w_crowbar.mdl" }
            }
            result.activeWeapon = result.weapons[1]
        end
        return result
    end
    local function create(slot, revision)
        local panel, failure = Cards:Create(root, "preview", row(slot, revision))
        if IsValid(panel) then ownedPanels[#ownedPanels + 1] = panel end
        return panel, failure
    end
    local function cleanup()
        ZM_Clothing.Apply = originalApply
        Cards:Reset()
        if IsValid(root) then root:Remove() end
        if ZM_LauncherMenu and IsValid(ZM_LauncherMenu.Frame) and ZM_LauncherMenu.Page == "load" then
            timer.Simple(0, function()
                if ZM_LauncherMenu and IsValid(ZM_LauncherMenu.Frame) and ZM_LauncherMenu.Page == "load" then
                    ZM_LauncherMenu:Render()
                end
            end)
        end
    end

    suite:Add("bounded_queue_revision_and_cleanup", function(check)
        Cards:Reset()
        ZM_Clothing.Apply = function() return true end
        for slot = 1, 3 do
            local panel, failure = create(slot, "revision-a")
            check(IsValid(panel), "slot " .. slot .. " creates: " .. tostring(failure))
        end
        local fourth = Cards:Create(root, "preview", row(4, "revision-a"))
        local initial = Cards:Status()
        check(not IsValid(fourth) and #initial.entries == 3 and initial.queued == 3,
            "cache is bounded to three visible cards")
        check(initial.entries[1].weaponModels == 0, "no weapon world model is posed on the portrait")
        local bySlot = {}
        for _, entry in ipairs(initial.entries) do bySlot[entry.slot] = entry end
        local loadout = bySlot[1] and bySlot[1].loadout or {}
        check(#loadout == 2 and loadout[1].label == "EQUIPPED" and loadout[1].value == "Hammer"
            and loadout[1].filled and loadout[2].label == "SLOT 2" and loadout[2].value == "Crowbar",
            "every equipped weapon owns a box and the selected one is marked")
        local unarmed = bySlot[2] and bySlot[2].loadout or {}
        check(#unarmed == 1 and unarmed[1].value == "UNARMED" and not unarmed[1].filled,
            "a survivor with no equipped weapons reports a single unarmed box")
        check(Cards.LoadoutOriginY + 2 * (Cards.LoadoutBoxHeight + Cards.LoadoutBoxSpacing)
            <= (bySlot[1] and bySlot[1].panelHeight or 0),
            "the weapon stack fits inside the portrait panel")
        check(initial.maximumInFlight == 1 and initial.compositionBudgetMs == 2,
            "queue exposes its one-build and two-millisecond budgets")
        Cards:ProcessQueue()
        Cards:ProcessQueue()
        Cards:ProcessQueue()
        local built = Cards:Status()
        check(built.queued == 0 and built.entries[1].ready and built.entries[2].ready and built.entries[3].ready,
            "one in-flight composition completes all three cards across bounded passes")
        check(built.entries[1].framed and built.entries[1].frameHeight > 60
            and built.entries[1].cameraDistance >= 120,
            "model bounds produce a complete full-body camera instead of the old torso crop")
        check(built.entries[1].frameMargin >= 1.1 and built.entries[1].composeMs ~= nil,
            "full-body framing has explicit margin and reports bounded composition cost")
        check(built.entries[1].frameHeadroom > 0 and built.entries[1].styledBackground,
            "portrait reserves face-safe headroom and owns its bordered presentation background")
        check(Cards:Key("preview", row(1, "revision-a")) ~= Cards:Key("preview", row(1, "revision-b")),
            "presentation revision invalidates the card key")
        Cards:Reset()
        local released = Cards:Status()
        check(#released.entries == 0 and released.queued == 0,
            "page cleanup releases every cached card and queued build")
    end)

    suite:Add("failed_composition_retries_instead_of_caching_fallback", function(check)
        Cards:Reset()
        local calls = 0
        ZM_Clothing.Apply = function()
            calls = calls + 1
            return calls > 1
        end
        local panel = create(1, "retry")
        Cards:ProcessQueue()
        local failed = Cards:Status()
        check(IsValid(panel) and failed.queued == 1 and not failed.entries[1].ready
            and failed.entries[1].attempts == 1, "failed composition stays queued")
        Cards.Entries[1].retryAt = 0
        Cards:ProcessQueue()
        local retried = Cards:Status()
        check(retried.queued == 0 and retried.entries[1].ready and retried.entries[1].attempts == 2,
            "transient failure retries and only then becomes ready")
    end)

    local summary
    local ok, failure = xpcall(function() summary = suite:Run() end, debug.traceback)
    cleanup()
    if not ok then
        summary = { passed = 0, failed = 1, ranAt = os.time(), cases = {
            { name = "character_card_test_runtime", passed = false, failures = { failure } }
        } }
    end
    file.CreateDir("zombiesim")
    file.Write("zombiesim/character_card_tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Character cards " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, message in ipairs(result.failures) do ErrorNoHalt("[ZombieSim] " .. message .. "\n") end
    end
end)
