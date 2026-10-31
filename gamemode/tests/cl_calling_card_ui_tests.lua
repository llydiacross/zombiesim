return function(createEngine, loadModule, createState)
    local suite = ZM_TestHarness.NewSuite()

    local function setup()
        local env, state = createEngine(ZM_CallingCards)
        local entries = {
            { id = "background_default", category = "background", name = "Default", material = "scoreboard/backgrounds/default.png" },
            { id = "background_owned", category = "background", name = "Owned", material = "scoreboard/backgrounds/owned_background.png", questReward = true },
            { id = "background_shop", category = "background", name = "Shop", material = "scoreboard/backgrounds/shop_background.png", shopCredits = 100, questReward = false },
            { id = "background_both", category = "background", name = "Both", material = "scoreboard/backgrounds/both_background.png", shopCredits = 60, questReward = true },
            { id = "detail_default", category = "detail", name = "Default", material = "scoreboard/details/default.png" },
            { id = "detail_quest", category = "detail", name = "Quest", material = "scoreboard/details/quest_details.png", questReward = true }
        }
        local catalogue = { byId = {}, byCategory = { background = {}, detail = {} },
            aliases = { background_old = "background_owned" } }
        for _, card in ipairs(entries) do
            catalogue.byId[card.id] = card
            table.insert(catalogue.byCategory[card.category], card)
        end
        state.registry = { callingCards = catalogue }
        local initialize = loadModule("cl_calling_cards.lua")
        assert(type(initialize) == "function", "Calling-card UI fixture initializer is unavailable.")
        local previousEnvironment = getfenv(initialize)
        setfenv(initialize, env)
        local ok, failure = pcall(initialize, createState)
        setfenv(initialize, previousEnvironment)
        if not ok then error(failure, 0) end
        local parent = env.vgui.Create("DPanel")
        parent:SetSize(1024, 700)
        return env, state, env.ZM_CallingCardUI, parent
    end

    local function packet(serial, ids, background, detail, ok, message, requestId)
        return { serial = serial, part = 1, total = 1, ids = ids,
            background = background or "background_default", detail = detail or "detail_default",
            ok = ok ~= false, message = message or "", requestId = requestId or "" }
    end

    suite:Add("selector waits for authoritative ownership and saves independent choices", function(check)
        local env, state, ui, parent = setup()
        local view = ui:OpenSelector(parent)
        check(state.requests[1].request.action == "list" and ui.State == nil, "opening requests ownership rather than guessing it")
        local first = packet(1, { "background_default" }, nil, nil, nil, nil, state.requests[1].request.requestId)
        first.total = 2
        state:Deliver(first)
        check(ui.State == nil, "partial responses cannot enable choices")
        local second = packet(1, { "detail_default", "background_owned" }, nil, nil, nil, nil, state.requests[1].request.requestId)
        second.part, second.total = 2, 2
        state:Deliver(second)
        local _, selected = state:Row(view, "background_default")
        local _, owned = state:Row(view, "background_owned")
        local _, locked = state:Row(view, "background_shop")
        check(selected.text == "SELECTED" and not selected.enabled and owned.enabled and not locked.enabled,
            "current, owned and locked designs have distinct actions")
        owned:DoClick()
        local request = state.requests[#state.requests].request
        check(request.action == "select" and request.category == "background" and request.id == "background_owned",
            "selecting sends only the chosen owned layer to the server")
        state:Deliver(packet(2, { "background_default", "detail_default", "background_owned" },
            "background_owned", nil, nil, nil, request.requestId))
        view.CategoryButtons.detail:DoClick()
        local _, quest = state:Row(view, "detail_quest")
        local _, default = state:Row(view, "detail_default")
        check(quest.text == "LOCKED" and not quest.enabled and default.text == "SELECTED",
            "the other category retains its independent selection and locked reward")
        view:OnKeyCodePressed(env.KEY_ESCAPE)
        check(not env.IsValid(view) and env.IsValid(parent) and ui.Selector == nil and not state.registered[view],
            "Escape removes the selector and returns focus to its parent")
        state:Deliver(packet(3, { "background_default", "detail_default", "background_owned" }, "background_owned"))
        check(ui.Selector == nil and ui.State.selection.background == "background_owned",
            "a late response does not reopen a closed view")
        parent:Remove()
    end)

    suite:Add("shop filters quest-only designs and requires a confirmed affordable purchase", function(check)
        local env, state, ui, parent = setup()
        local view = ui:OpenShop(parent)
        state:Deliver(packet(1, { "background_default", "detail_default", "background_owned" },
            nil, nil, nil, nil, state.requests[1].request.requestId))
        local _, shop = state:Row(view, "background_shop")
        local _, both = state:Row(view, "background_both")
        check(not state:Row(view, "background_owned") and shop.enabled and both.enabled,
            "only designs with shop prices appear")
        shop:DoClick()
        state.dialog.cancel()
        check(not state.purchases, "cancelling never sends a purchase")
        state.dialog:Remove()
        shop:DoClick()
        local confirmation = state.dialog
        confirmation.confirm()
        confirmation:Remove()
        check(#state.purchases == 1 and state.purchases[1].id == "background_shop"
            and state.purchases[1].price == 100 and view.PurchasePending ~= nil,
            "confirmation sends the shown price once and waits for authoritative state")
        local _, pending = state:Row(view, "background_both")
        check(not pending.enabled, "additional purchases are disabled while the response is pending")
        state:Deliver(packet(2, { "background_default", "detail_default", "background_owned" }))
        check(view.PurchasePending ~= nil and ui.Message.text == "Completing purchase...",
            "an unrelated response cannot complete a pending purchase")
        ui:OnTradeState({ ok = false, message = "Price changed." })
        state:Deliver(packet(3, { "background_default", "detail_default", "background_owned" },
            nil, nil, false, "Price changed.", state.purchases[1].requestId))
        check(not ui.Message.ok and ui.Message.text == "Price changed." and not view.PurchasePending,
            "a server rejection remains visible and refreshes ownership")
        env.ZM_TradingUI.State.credits = 50
        ui:RefreshView(view)
        local _, unaffordable = state:Row(view, "background_shop")
        check(not unaffordable.enabled, "insufficient credits disable the purchase")
        env.ZM_TradingUI.State.credits = 200
        ui:RefreshView(view)
        local _, retry = state:Row(view, "background_shop")
        retry:DoClick()
        confirmation = state.dialog
        confirmation.confirm()
        confirmation:Remove()
        state:Deliver(packet(4, { "background_default", "detail_default", "background_owned", "background_shop" },
            nil, nil, true, "Unlocked.", state.purchases[2].requestId))
        local _, purchased = state:Row(view, "background_shop")
        check(purchased.text == "OWNED" and not purchased.enabled and #state.purchases == 2,
            "the completed purchase becomes owned and cannot be purchased again")
        view.CategoryButtons.detail:DoClick()
        check(not state:Row(view, "detail_quest"), "quest-only details are not sold")
        parent:Remove()
    end)

    suite:Add("parent removal closes confirmation and cannot submit a late purchase", function(check)
        local env, state, ui, parent = setup()
        local view = ui:OpenShop(parent)
        state:Deliver(packet(1, { "background_default", "detail_default" },
            nil, nil, nil, nil, state.requests[1].request.requestId))
        local _, button = state:Row(view, "background_shop")
        button:DoClick()
        local confirmation = state.dialog
        parent:Remove()
        check(not env.IsValid(view) and not env.IsValid(confirmation) and ui.Shop == nil,
            "closing the parent removes its shop and confirmation")
        confirmation.confirm()
        check(not state.purchases, "a late confirmation cannot spend after the shop closes")
    end)

    suite:Add("a purchase encoding failure stays visible and does not become pending", function(check)
        local _, state, ui, parent = setup()
        local view = ui:OpenShop(parent)
        state:Deliver(packet(1, { "background_default", "detail_default" },
            nil, nil, nil, nil, state.requests[1].request.requestId))
        local _, button = state:Row(view, "background_shop")
        state.purchaseFailure = "Could not encode the trader request."
        button:DoClick()
        local confirmation = state.dialog
        confirmation.confirm()
        confirmation:Remove()
        local _, retry = state:Row(view, "background_shop")
        check(not state.purchases and not view.PurchasePending and not view.PurchaseRequestId,
            "a failed request is not submitted or marked pending")
        check(not ui.Message.ok and ui.Message.text == state.purchaseFailure and retry.enabled,
            "the failure is shown and the card remains available to retry")
        parent:Remove()
    end)

    suite:Add("default appearance, aliases and missing materials are diagnosed", function(check)
        local _, state, ui, parent = setup()
        ui:DrawPair("background_default", "detail_default", 10, 20, 600, 125)
        check(#state.draws == 2 and state.draws[1].alpha == 70 and state.draws[2].alpha == 225
            and state.draws[1].path == "scoreboard/backgrounds/default.png"
            and state.draws[2].path == "scoreboard/details/default.png",
            "the default materials retain the existing scoreboard alpha values and dimensions")
        local renamed, aliasStatus = ui:GetMaterialStatus("background", "background_old")
        check(aliasStatus == "alias" and renamed.path == "scoreboard/backgrounds/owned_background.png",
            "an alias resolves to its current material")
        local missing, missingStatus = ui:GetMaterialStatus("detail", "detail_removed")
        check(missingStatus == "missing" and missing.path == "scoreboard/details/default.png",
            "a missing saved design displays its default")
        state.missingMaterials["scoreboard/backgrounds/shop_background.png"] = true
        local fallback, materialStatus = ui:GetMaterialStatus("background", "background_shop")
        check(materialStatus == "material_missing" and fallback.path == "scoreboard/backgrounds/default.png"
            and #state.errors == 1, "an invalid material logs a diagnostic and displays the default")
        check(#ui:MaterialDiagnostics() >= 4 and ui.DrawCount == 2,
            "material, shader, dimensions and per-frame draw counts remain inspectable")
        parent:Remove()
    end)

    suite:Add("timeouts and failed snapshots stay visible without stale choices", function(check)
        local env, state, ui, parent = setup()
        local view = ui:OpenSelector(parent)
        state.now = state.now + 11
        view:Think()
        check(ui.State == nil and not ui.Message.ok and string.find(ui.Message.text, "timed out", 1, true) ~= nil,
            "a lost response reports a timeout")
        view.RefreshButton:DoClick()
        local failed = packet(1, {}, "", "", false, "No active survivor.", state.requests[#state.requests].request.requestId)
        state:Deliver(failed)
        check(ui.State and not ui.State.available and not ui.Message.ok and ui.Message.text == "No active survivor.",
            "a failed store response cannot enable stale cards")
        parent:Remove()
    end)

    if concommand then
        concommand.Add("zombiesim_dev_test_calling_card_ui", function()
            if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
                ErrorNoHalt("[ZombieSim] Calling-card UI tests require a preview admin.\n")
                return
            end
            local summary = suite:Run()
            file.CreateDir("zombiesim")
            file.Write("zombiesim/calling_card_ui_tests.json", util.TableToJSON(summary, true))
            for _, result in ipairs(summary.cases) do
                print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
                for _, failure in ipairs(result.failures) do print("[ZombieSim]   " .. failure) end
            end
            print(string.format("[ZombieSim] Calling-card UI tests: %d passed, %d failed.", summary.passed, summary.failed))
        end, nil, "Runs isolated calling-card selector and shop fixtures.")
    end
    return suite
end
