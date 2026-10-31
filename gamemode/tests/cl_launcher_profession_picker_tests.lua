return function(picker)
    local suite = ZM_TestHarness.NewSuite()

    local function withFixture(draft, body)
        local host = vgui.Create("DPanel")
        host:SetSize(680, 1000)
        host:SetVisible(false)
        local menu = { Step = 4, renders = 0 }
        function menu:Render() self.renders = self.renders + 1 end
        local function button(text, callback, parent)
            local control = vgui.Create("DButton", parent or host)
            control:SetText(text)
            control.DoClick = callback
            return control
        end
        local function attributeLabel(attribute)
            return (string.gsub(attribute, "(%l)(%u)", "%1 %2"))
        end
        local ok, failure = pcall(function()
            local view = picker:Build(menu, host, draft, button, attributeLabel)
            body(view, menu)
        end)
        host:Remove()
        if not ok then error(failure, 0) end
    end

    suite:Add("profession selection requires an explicit available job", function(check)
        local draft = { attributes = { Strength = 4 } }
        withFixture(draft, function(view, menu)
            local ids = ZM_Professions:GetIds()
            local count = 0
            for _, id in ipairs(ids) do if view.cards[id] then count = count + 1 end end
            check(count == #ids and count > 0, "every available profession has a selectable card")
            check(not view.nextButton:IsEnabled() and draft.job == nil and menu.Step == 4,
                "a new draft cannot continue without choosing a profession")
            check(view.description:GetText():find("Select a profession", 1, true) ~= nil,
                "the detail panel explains why no job is selected")
            view.nextButton:DoClick()
            check(menu.Step == 4 and menu.renders == 0 and draft.attributes.Strength == 4,
                "even a direct invalid continuation cannot advance or change allocated points")
        end)
    end)

    suite:Add("profession detail follows selection and preserves allocated points", function(check)
        local draft = { attributes = { Strength = 4, Pistols = 2 } }
        withFixture(draft, function(view, menu)
            local doctor = ZM_Professions:GetKnown("Doctor")
            view.cards.Doctor:DoClick()
            check(draft.job == doctor.id and menu.Step == 4 and menu.renders == 0,
                "selecting a job updates the draft without immediately advancing")
            check(view.title:GetText() == string.upper(doctor.name)
                and view.description:GetText() == doctor.description
                and view.backstory:GetText() == "Backstory to be written.",
                "the selected name, authored description and explicit placeholder are visible")
            for _, attribute in ipairs(ZM_CharacterRules.Attributes) do
                local bonus = doctor.statBonuses[attribute]
                check(view.values[attribute]:GetText() == (bonus and ("+" .. bonus) or "0"),
                    "the job bonus table reflects " .. attribute)
            end
            check(view.services:GetText():find("treat", 1, true) ~= nil
                and view.services:GetText():find("Daily delivery tiers: " .. #doctor.deliveries, 1, true) ~= nil,
                "existing service and delivery information remains available")
            check(view.nextButton:IsEnabled(), "the selected profession enables continuation")
            view.nextButton:DoClick()
            check(menu.Step == 5 and menu.renders == 1 and draft.attributes.Strength == 4
                and draft.attributes.Pistols == 2, "continuing keeps existing point allocation intact")
        end)
    end)

    suite:Add("profession selection survives returning to the job step", function(check)
        local draft = { job = "Doctor", attributes = { Medicine = 3 } }
        withFixture(draft, function(view, menu)
            check(view.nextButton:IsEnabled() and view.title:GetText() == string.upper(ZM_Professions:GetKnown("Doctor").name),
                "a previously selected job is restored")
            view.cards.Civilian:DoClick()
            check(draft.job == "Civilian" and menu.Step == 4 and draft.attributes.Medicine == 3,
                "switching jobs leaves previously allocated points alone")
            check(view.values.Medicine:GetText() == "0"
                and view.services:GetText():find("Services: None", 1, true) ~= nil
                and view.services:GetText():find("Daily delivery tiers: 0", 1, true) ~= nil,
                "the no-bonus profession does not retain the old job's details")
        end)
    end)

    suite:Add("unknown draft jobs cannot silently select the default", function(check)
        local draft = { job = "UnavailableJob", attributes = { Strength = 1 } }
        withFixture(draft, function(view, menu)
            check(not view.nextButton:IsEnabled()
                and view.description:GetText():find("unavailable", 1, true) ~= nil,
                "an unavailable job is visible and cannot be confirmed")
            view.nextButton:DoClick()
            check(menu.Step == 4 and draft.job == "UnavailableJob" and draft.attributes.Strength == 1,
                "the invalid draft is not silently replaced or advanced")
            view.cards.Civilian:DoClick()
            check(view.nextButton:IsEnabled() and draft.job == "Civilian",
                "the player can explicitly select a valid replacement")
        end)
    end)

    suite:Add("an unavailable profession catalogue is reported", function(check)
        local original = ZM_Professions.GetIds
        ZM_Professions.GetIds = function() return {} end
        local ok, failure = pcall(function()
            withFixture({ attributes = {} }, function(view)
                check(not view.nextButton:IsEnabled()
                    and view.description:GetText():find("catalogue is unavailable", 1, true) ~= nil,
                    "an empty catalogue is visible and cannot advance")
            end)
        end)
        ZM_Professions.GetIds = original
        if not ok then error(failure, 0) end
    end)

    suite:Add("profession grid adapts without overlapping its details", function(check)
        withFixture({ attributes = {} }, function(view)
            local ids = ZM_Professions:GetIds()
            view.root:PerformLayout(640, 580)
            view.grid:PerformLayout(view.grid:GetWide(), view.grid:GetTall())
            check(view.details:GetX() >= view.grid:GetX() + view.grid:GetWide()
                and view.details:GetY() == 0, "wide layouts place the details to the right of the grid")
            check(view.cards[ids[2]]:GetX() >= view.cards[ids[1]]:GetX() + view.cards[ids[1]]:GetWide()
                and view.cards[ids[3]]:GetY() > view.cards[ids[1]]:GetY(),
                "the profession cards form a non-overlapping two-column grid")
            view.root:PerformLayout(320, 580)
            view.grid:PerformLayout(view.grid:GetWide(), view.grid:GetTall())
            check(view.details:GetX() == 0 and view.details:GetY() >= view.grid:GetTall()
                and view.root:GetTall() >= view.details:GetY() + view.details:GetTall(),
                "narrow layouts stack the details below the grid and expand the scrollable content")
            view.root:PerformLayout(420, 580)
            check(view.details:GetY() == 0 and view.details:GetX() >= view.grid:GetWide(),
                "the split layout starts at the configured width")
            view.root:PerformLayout(419, 580)
            check(view.details:GetX() == 0 and view.details:GetY() >= view.grid:GetTall(),
                "the layout stacks immediately below that width")
        end)
    end)

    suite:Add("profession details enclose the complete table as text wraps", function(check)
        withFixture({ attributes = {} }, function(view)
            check(view.details.GetVBar == nil, "the page owns scrolling rather than a nested detail scrollbar")
            local function layoutAndCheck(width)
                view.root:PerformLayout(width, view.root:GetTall())
                view.details:InvalidateLayout(true)
                for _, label in ipairs(view.detailTexts) do label:SizeToContentsY() end
                view.root:PerformLayout(width, view.root:GetTall())
                view.details:InvalidateLayout(true)
                for _, child in ipairs(view.detailElements) do
                    local _, _, _, bottom = child:GetDockMargin()
                    check(child:GetY() >= 0 and child:GetY() + child:GetTall() + bottom <= view.details:GetTall() - 8,
                        "every detail element remains inside the bordered panel")
                end
                check(view.root:GetTall() >= view.details:GetY() + view.details:GetTall(),
                    "the outer page includes the complete detail panel")
            end

            for _, width in ipairs({ 640, 420, 419, 320 }) do
                for _, id in ipairs(ZM_Professions:GetIds()) do
                    view.cards[id]:DoClick()
                    layoutAndCheck(width)
                end
            end
            local normalHeight = view.details:GetTall()
            view.description:SetText(string.rep("A longer profession description. ", 30))
            layoutAndCheck(320)
            local longHeight = view.details:GetTall()
            check(longHeight > normalHeight, "wrapped text expands the bordered panel")
            view.description:SetText("Short description.")
            layoutAndCheck(320)
            check(view.details:GetTall() < longHeight, "shorter text releases the extra height")
        end)
    end)

    suite:Add("profession icons resolve from mounted materials", function(check)
        for _, id in ipairs(ZM_Professions:GetIds()) do
            local status = picker:GetIconStatus(id)
            check(status.valid and status.width > 0 and status.height > 0,
                id .. " has a resolved icon texture")
        end
        check(picker:GetIconStatus("FutureProfession").path == picker:GetIconStatus("Civilian").path,
            "an unassigned future profession uses the generic mounted icon")
    end)
    return suite
end
