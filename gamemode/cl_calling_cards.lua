return function(createState)
    ZM_CallingCardUI = ZM_CallingCardUI or {}
    local UI = ZM_CallingCardUI
    local Cards = ZM_CallingCards
    local assembler = createState(Cards.Category)
    local materialCache, reported = {}, {}
    local defaults = {
        background = "scoreboard/backgrounds/default.png",
        detail = "scoreboard/details/default.png"
    }

    local function reportOnce(key, message)
        if reported[key] then return end
        reported[key] = true
        ErrorNoHalt("[ZombieSim] " .. message .. "\n")
    end

    function UI:Catalogue()
        local registry = ZM_StaticData:GetRegistry()
        return registry and registry.callingCards or nil
    end

    local function materialStatus(path)
        if materialCache[path] then return materialCache[path] end
        local material = Material(path, "smooth")
        local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
        local width, height = texture and texture:Width() or 0, texture and texture:Height() or 0
        local status = { path = path, material = material, shader = material:GetShader(), width = width, height = height,
            valid = texture ~= nil and width > 0 and height > 0 }
        if not status.valid then reportOnce(path, "Calling-card material is unavailable: " .. path) end
        materialCache[path] = status
        return status
    end

    function UI:GetMaterialStatus(category, id)
        local default = defaults[category]
        if not default then return nil, "invalid_category" end
        local card, resolution = Cards.Resolve(self:Catalogue(), id, category)
        if not card then
            reportOnce("catalogue", "Calling-card catalogue is unavailable; displaying the built-in defaults.")
        elseif resolution == "invalid_alias" then
            reportOnce("alias:" .. tostring(id), "Calling-card alias is invalid: " .. tostring(id))
        end
        local status = materialStatus(card and card.material or default)
        if not status.valid and status.path ~= default then
            status = materialStatus(default)
            resolution = "material_missing"
        end
        return status, resolution
    end

    local function drawLayer(category, id, alpha, x, y, width, height)
        local status = UI:GetMaterialStatus(category, id)
        if status and status.valid then
            surface.SetMaterial(status.material)
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.DrawTexturedRect(x, y, width, height)
            local frame = FrameNumber()
            if UI.DrawFrame ~= frame then UI.DrawFrame, UI.DrawCount = frame, 0 end
            UI.DrawCount = UI.DrawCount + 1
        end
    end

    function UI:DrawPair(background, detail, x, y, width, height)
        drawLayer("background", background, 70, x, y, width, height)
        drawLayer("detail", detail, 225, x, y, width, height)
    end

    function UI:MaterialDiagnostics()
        local results = {}
        for path, status in pairs(materialCache) do
            results[#results + 1] = { path = path, valid = status.valid, shader = status.shader,
                width = status.width, height = status.height }
        end
        table.sort(results, function(left, right) return left.path < right.path end)
        return results
    end

    function UI:SendRequest(request)
        self.RequestCounter = ((self.RequestCounter or 0) % 2147483646) + 1
        request.requestId = string.format("card%d_%d", os.time(), self.RequestCounter)
        local encoded = util.TableToJSON(request, false)
        if not encoded then
            self.Message = { ok = false, text = "Could not encode the calling-card request." }
            self:RefreshViews()
            return false
        end
        self.PendingSince, self.PendingRequestId = RealTime(), request.requestId
        net.Start("ZM.CallingCardRequest")
            net.WriteString(encoded)
        net.SendToServer()
        return true
    end

    function UI:RequestState()
        self.State = nil
        self.Message = { ok = true, text = "Loading your calling cards..." }
        self:SendRequest({ action = "list" })
        self:RefreshViews()
    end

    local function label(parent, text, font, color)
        local control = vgui.Create("DLabel", parent)
        control:SetText(text)
        control:SetFont(font or "DermaDefault")
        control:SetTextColor(color or ZM_DermaSkin.Palette.text)
        control:SetWrap(true)
        return control
    end

    local function drawRowPreview(card, state, width, height)
        local palette = ZM_DermaSkin.Palette
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, width, height)
        local background, detail = state.selection.background, state.selection.detail
        if card.category == "background" then background = card.id else detail = card.id end
        UI:DrawPair(background, detail, 0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local function selectedCard(catalogue, state, category)
        local card, status = Cards.Resolve(catalogue, state.selection[category], category)
        if status == "missing" or status == "invalid_alias" then return nil, status end
        return card, status
    end

    function UI:RefreshView(view)
        if not IsValid(view) or not IsValid(view.List) then return end
        view.List:Clear()
        local state, catalogue = self.State, self:Catalogue()
        if not state or not state.available then
            local text = self.PendingSince and "Loading..." or "Calling-card ownership is unavailable."
            local notice = label(view.List, text, "DermaDefaultBold", ZM_DermaSkin.Palette.muted)
            notice:Dock(TOP)
            notice:SetTall(28)
            return
        end
        if not catalogue then
            local notice = label(view.List, "Calling-card catalogue is unavailable.", "DermaDefaultBold", ZM_DermaSkin.Palette.redBright)
            notice:Dock(TOP)
            notice:SetTall(28)
            return
        end
        local selected = selectedCard(catalogue, state, view.Category)
        local count = 0
        for _, card in ipairs(catalogue.byCategory[view.Category]) do
            if view.Mode ~= "shop" or card.shopCredits then
                count = count + 1
                local owned = state.owned[card.id] == true
                local isSelected = selected and selected.id == card.id
                local row = vgui.Create("DPanel", view.List)
                row.CardId = card.id
                row:Dock(TOP)
                row:DockMargin(0, 0, 0, 5)
                row:SetTall(58)
                row.Paint = function(_, width, height)
                    surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
                    surface.DrawRect(0, 0, width, height)
                end

                local action = vgui.Create("DButton", row)
                action:Dock(RIGHT)
                action:DockMargin(4, 10, 8, 10)
                action:SetWide(100)
                local traderState = ZM_TradingUI and ZM_TradingUI.State or nil
                local affordable = traderState ~= nil and type(traderState.credits) == "number"
                    and card.shopCredits ~= nil and traderState.credits >= card.shopCredits
                if view.Mode == "shop" then
                    action:SetText(owned and "OWNED" or (card.shopCredits .. " CR"))
                    action:SetEnabled(not owned and affordable and traderState.available == true
                        and not view.PurchasePending and not UI.PendingSince)
                    action.DoClick = function() UI:ConfirmPurchase(view, card) end
                else
                    action:SetText(isSelected and "SELECTED" or (owned and "SELECT" or "LOCKED"))
                    action:SetEnabled(owned and not isSelected and not UI.PendingSince)
                    action.DoClick = function()
                        if not owned or UI.PendingSince then return end
                        UI.Message = { ok = true, text = "Saving your selection..." }
                        UI:SendRequest({ action = "select", category = card.category, id = card.id })
                        UI:RefreshViews()
                    end
                end

                local preview = vgui.Create("DPanel", row)
                preview:Dock(LEFT)
                preview:DockMargin(7, 11, 8, 11)
                preview:SetWide(180)
                preview.Paint = function(_, width, height) drawRowPreview(card, state, width, height) end

                local description = vgui.Create("DPanel", row)
                description:Dock(FILL)
                description.Paint = nil
                local title = label(description, card.name, "DermaDefaultBold")
                title:Dock(TOP)
                title:DockMargin(0, 7, 0, 0)
                title:SetTall(19)
                local source
                if owned then
                    source = isSelected and "Current selection" or "Unlocked for this account and profile"
                elseif card.shopCredits and card.questReward then
                    source = "Trader or quest reward"
                elseif card.shopCredits then
                    source = "Purchase at a den trader"
                else
                    source = "Quest reward"
                end
                local subtitle = label(description, source, "DermaDefault", ZM_DermaSkin.Palette.muted)
                subtitle:Dock(TOP)
                subtitle:SetTall(22)
            end
        end
        if count == 0 then
            local notice = label(view.List, view.Mode == "shop" and "No designs are currently for sale." or
                "No designs are available in this category.", "DermaDefaultBold", ZM_DermaSkin.Palette.muted)
            notice:Dock(TOP)
            notice:SetTall(28)
        end
    end

    function UI:RefreshViews()
        self:RefreshView(self.Selector)
        self:RefreshView(self.Shop)
    end

    function UI:OnTradeState(state)
        if not IsValid(self.Shop) then return end
        if state.message and not self.Shop.PurchasePending then
            self.Message = { ok = state.ok ~= false, text = state.message }
        end
        self:RefreshView(self.Shop)
    end

    function UI:ConfirmPurchase(view, card)
        if not IsValid(view) or view.PurchasePending or IsValid(view.Confirmation) then return end
        view.Confirmation = Derma_Query(
            string.format("Unlock %s for %d credits? This is shared by your survivors in this world profile.", card.name, card.shopCredits),
            "Confirm Calling Card",
            "Confirm", function()
                view.Confirmation = nil
                if not IsValid(view) or not IsValid(view:GetParent()) then return end
                local trade = ZM_TradingUI
                local state = trade and trade.State
                if not state or not state.available or type(state.credits) ~= "number"
                    or state.credits < card.shopCredits or not UI.State or UI.State.owned[card.id] then
                    UI.Message = { ok = false, text = "The trader or ownership changed. Refresh and try again." }
                    UI:RefreshViews()
                    return
                end
                local requestId, requestError = trade:SendCallingCardPurchase(card.id, card.shopCredits)
                if not requestId then
                    UI.Message = { ok = false, text = requestError or "Could not send the calling-card purchase." }
                    UI:RefreshViews()
                    return
                end
                view.PurchasePending, view.PurchaseRequestId = RealTime(), requestId
                UI.Message = { ok = true, text = "Completing purchase..." }
                UI:RefreshViews()
            end,
            "Cancel", function() view.Confirmation = nil end
        )
    end

    local function openView(mode, parent)
        local existing = mode == "shop" and UI.Shop or UI.Selector
        if IsValid(existing) then existing:MakePopup() return existing end
        if not IsValid(parent) then return nil end
        local frame = vgui.Create("DFrame", parent)
        frame.Mode, frame.Category = mode, "background"
        frame:SetSkin("ZombieSim")
        frame:SetTitle(mode == "shop" and "CALLING CARD SHOP" or "EDIT CALLING CARD")
        local width = math.min(720, parent:GetWide() - 24, ScrW() - 40)
        local height = math.min(620, parent:GetTall() - 24, ScrH() - 40)
        frame:SetSize(width, height)
        frame:SetPos(math.floor((parent:GetWide() - width) * 0.5), math.floor((parent:GetTall() - height) * 0.5))
        frame:MakePopup()
        frame.OnClose = function() if IsValid(parent) then parent:MakePopup() end end
        frame.OnRemove = function()
            if IsValid(frame.Confirmation) then frame.Confirmation:Remove() end
            if UI.Selector == frame then UI.Selector = nil end
            if UI.Shop == frame then UI.Shop = nil end
            if ZM_UI then ZM_UI:UnregisterTransient(frame) end
        end
        frame.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE then frame:Close() end end
        frame.Think = function()
            if not IsValid(parent) then frame:Close() return end
            if UI.PendingSince and RealTime() - UI.PendingSince > 10 then
                UI.PendingSince, UI.PendingRequestId = nil, nil
                UI.Message = { ok = false, text = "Calling-card request timed out. Refresh to try again." }
                UI:RefreshViews()
            end
            if frame.PurchasePending and RealTime() - frame.PurchasePending > 10 then
                frame.PurchasePending, frame.PurchaseRequestId = nil, nil
                UI.State = nil
                UI.Message = { ok = false, text = "Purchase response timed out. Refresh ownership before retrying." }
                UI:RefreshViews()
            end
        end
        if mode == "shop" then UI.Shop = frame else UI.Selector = frame end
        if ZM_UI then ZM_UI:RegisterTransient(frame) end

        local footer = vgui.Create("DPanel", frame)
        footer:Dock(BOTTOM)
        footer:DockMargin(8, 4, 8, 8)
        footer:SetTall(42)
        footer.Paint = function(_, width, height)
            local message = UI.Message
            if message then
                draw.SimpleText(message.text, "DermaDefault", 4, height * 0.5,
                    message.ok and ZM_DermaSkin.Palette.text or ZM_DermaSkin.Palette.redBright,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        local refresh = vgui.Create("DButton", footer)
        frame.RefreshButton = refresh
        refresh:Dock(RIGHT)
        refresh:SetWide(90)
        refresh:SetText("REFRESH")
        refresh.DoClick = function() UI:RequestState() end

        local preview = vgui.Create("DPanel", frame)
        frame.Preview = preview
        preview:Dock(TOP)
        preview:DockMargin(8, 8, 8, 4)
        preview:SetTall(104)
        preview.Paint = function(_, w, h)
            local state = UI.State
            surface.SetDrawColor(ZM_DermaSkin.Palette.black)
            surface.DrawRect(0, 0, w, h)
            if state and state.available then
                UI:DrawPair(state.selection.background, state.selection.detail, 0, 0, w, h)
                local catalogue = UI:Catalogue()
                local _, backgroundStatus = selectedCard(catalogue, state, "background")
                local _, detailStatus = selectedCard(catalogue, state, "detail")
                if backgroundStatus == "missing" or detailStatus == "missing" then
                    draw.SimpleText("Unavailable saved design shown as default", "DermaDefault", 8, h - 8,
                        ZM_DermaSkin.Palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
                end
            end
        end

        local tabs = vgui.Create("DPanel", frame)
        tabs:Dock(TOP)
        tabs:DockMargin(8, 0, 8, 6)
        tabs:SetTall(30)
        tabs.Paint = nil
        frame.CategoryButtons = {}
        for _, category in ipairs({ "background", "detail" }) do
            local button = vgui.Create("DButton", tabs)
            frame.CategoryButtons[category] = button
            button:Dock(LEFT)
            button:DockMargin(0, 0, 6, 0)
            button:SetWide(130)
            button:SetText(category == "background" and "BACKGROUNDS" or "DETAILS")
            button.DoClick = function() frame.Category = category UI:RefreshView(frame) end
        end
        local hint = label(tabs, mode == "shop" and "Credits are spent by this survivor." or
            "Locked designs can be unlocked at a trader or by quests.", "DermaDefault", ZM_DermaSkin.Palette.muted)
        hint:Dock(FILL)
        hint:SetContentAlignment(4)

        local list = vgui.Create("DScrollPanel", frame)
        list:Dock(FILL)
        list:DockMargin(8, 0, 8, 0)
        frame.List = list
        UI:RequestState()
        return frame
    end

    function UI:OpenSelector(parent) return openView("selector", parent) end
    function UI:OpenShop(parent) return openView("shop", parent) end

    net.Receive("ZM.CallingCardState", function()
        local packet = {
            serial = net.ReadUInt(32), part = net.ReadUInt(16), total = net.ReadUInt(16),
            ok = net.ReadBool(), message = net.ReadString(), requestId = net.ReadString(),
            background = net.ReadString(), detail = net.ReadString(), ids = {}
        }
        for index = 1, net.ReadUInt(8) do packet.ids[index] = net.ReadString() end
        local status, result = assembler:Push(packet)
        if status == "error" then
            UI.State, UI.PendingSince, UI.PendingRequestId = nil, nil, nil
            if IsValid(UI.Shop) then UI.Shop.PurchasePending, UI.Shop.PurchaseRequestId = nil, nil end
            UI.Message = { ok = false, text = result }
            ErrorNoHalt("[ZombieSim] " .. result .. "\n")
        elseif status == "complete" then
            UI.State = result
            local matched = result.requestId ~= "" and result.requestId == UI.PendingRequestId
            if matched then UI.PendingSince, UI.PendingRequestId = nil, nil end
            if IsValid(UI.Shop) and result.requestId ~= "" and result.requestId == UI.Shop.PurchaseRequestId then
                UI.Shop.PurchasePending, UI.Shop.PurchaseRequestId = nil, nil
                matched = true
            end
            if not result.ok and result.requestId == "" then
                UI.PendingSince, UI.PendingRequestId = nil, nil
                if IsValid(UI.Shop) then UI.Shop.PurchasePending, UI.Shop.PurchaseRequestId = nil, nil end
                matched = true
            end
            if matched or (not UI.PendingSince and not (IsValid(UI.Shop) and UI.Shop.PurchasePending)) then
                UI.Message = { ok = result.ok, text = result.message ~= "" and result.message or
                    (result.available and "Calling cards loaded." or "Calling-card ownership is unavailable.") }
            end
        else
            return
        end
        UI:RefreshViews()
    end)

    concommand.Add("zombiesim_dev_calling_card_materials", function()
        local results = UI:MaterialDiagnostics()
        for _, status in ipairs(results) do
            print(string.format("[ZombieSim] Calling-card material %s: %s, %s (%dx%d)",
                status.path, status.valid and "OK" or "MISSING", status.shader or "unknown shader", status.width, status.height))
        end
        if #results == 0 then print("[ZombieSim] No calling-card materials have been requested yet.") end
        print(string.format("[ZombieSim] Calling-card draws: %d in frame %s.", UI.DrawCount or 0, tostring(UI.DrawFrame or "none")))
    end, nil, "Reports the calling-card materials requested by the client.")
end
