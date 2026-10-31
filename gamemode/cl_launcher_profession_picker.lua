local Picker = {}
local palette = ZM_DermaSkin.Palette
local iconPaths = {
    ArmySoldier = "icon16/award_star_gold_1.png",
    Capitalist = "icon16/coins.png",
    Chef = "icon16/cup.png",
    Civilian = "icon16/user.png",
    Doctor = "icon16/heart.png",
    Farmer = "icon16/basket.png",
    Hunter = "icon16/gun.png",
    Mechanic = "icon16/wrench.png",
    PoliceOfficer = "icon16/shield.png",
    Scavenger = "icon16/magnifier.png",
    Scientist = "icon16/lightbulb.png"
}
local iconCache = {}

function Picker:GetIconStatus(id)
    local path = iconPaths[id] or iconPaths.Civilian
    if iconCache[path] then return iconCache[path] end
    local material = Material(path, "smooth")
    local texture = not material:IsError() and material:GetTexture("$basetexture") or nil
    local width = texture and texture:Width() or 0
    local height = texture and texture:Height() or 0
    local status = { path = path, material = material, width = width, height = height,
        valid = texture ~= nil and width > 0 and height > 0 }
    if not status.valid then
        ErrorNoHalt("[ZombieSim] Profession icon is unavailable: " .. path .. "\n")
    end
    iconCache[path] = status
    return status
end

local function drawIcon(status, x, y, size)
    if status and status.valid then
        surface.SetMaterial(status.material)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, size, size)
    elseif status then
        draw.SimpleText("?", "DermaDefaultBold", x + size * 0.5, y + size * 0.5,
            palette.redBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

local function addText(parent, text, font, colour)
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:DockMargin(12, 3, 12, 3)
    label:SetFont(font or "DermaDefault")
    label:SetTextColor(colour or palette.text)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
    label:SetText(text)
    return label
end

function Picker:Build(menu, parent, draft, button, attributeLabel)
    local ids = ZM_Professions:GetIds()
    addText(parent, "Choose a previous job to see its benefits before continuing.", nil, palette.muted)

    local root = vgui.Create("DPanel", parent)
    root:Dock(TOP)
    root:DockMargin(4, 6, 4, 6)
    root:SetTall(580)
    root.Paint = function() end

    local grid = vgui.Create("DPanel", root)
    grid.Paint = function() end
    local details = vgui.Create("DPanel", root)
    details.Paint = function(_, width, height)
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height)
    end

    local detailElements, detailTexts = {}, {}
    local function trackDetail(panel)
        detailElements[#detailElements + 1] = panel
        local previousSizeChanged = panel.OnSizeChanged
        local previousHeight = panel:GetTall()
        panel.OnSizeChanged = function(child, width, height)
            if previousSizeChanged then previousSizeChanged(child, width, height) end
            if height == previousHeight then return end
            previousHeight = height
            if IsValid(root) then root:InvalidateLayout() end
        end
        return panel
    end
    local function addDetailText(text, font, colour)
        local label = trackDetail(addText(details, text, font, colour))
        detailTexts[#detailTexts + 1] = label
        return label
    end

    local selectedIcon, selectedProfession
    local header = vgui.Create("DPanel", details)
    header:Dock(TOP)
    header:SetTall(54)
    trackDetail(header)
    header.Paint = function(_, width, height)
        surface.SetDrawColor(palette.raised)
        surface.DrawRect(0, 0, width, height)
        drawIcon(selectedIcon, 12, 15, 24)
    end
    local title = vgui.Create("DLabel", header)
    title:Dock(FILL)
    title:DockMargin(46, 5, 8, 5)
    title:SetFont("DermaDefaultBold")
    title:SetTextColor(palette.text)
    title:SetWrap(true)
    title:SetMouseInputEnabled(false)

    addDetailText("DESCRIPTION", "DermaDefaultBold", palette.muted)
    local description = addDetailText("", nil, palette.text)
    addDetailText("BACKSTORY", "DermaDefaultBold", palette.muted)
    local backstory = addDetailText("Backstory to be written.", nil, palette.text)
    local services = addDetailText("", nil, palette.muted)

    local statHeader = vgui.Create("DPanel", details)
    statHeader:Dock(TOP)
    statHeader:DockMargin(8, 8, 8, 0)
    statHeader:SetTall(26)
    trackDetail(statHeader)
    statHeader.Paint = function(_, width, height)
        surface.SetDrawColor(palette.redDark)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText("ATTRIBUTE", "DermaDefaultBold", 8, height * 0.5,
            palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("JOB BONUS", "DermaDefaultBold", width - 8, height * 0.5,
            palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local values, rows = {}, {}
    for index, attribute in ipairs(ZM_CharacterRules.Attributes) do
        local row = vgui.Create("DPanel", details)
        row:Dock(TOP)
        row:DockMargin(8, 0, 8, 0)
        row:SetTall(24)
        trackDetail(row)
        row.Paint = function(_, width, height)
            surface.SetDrawColor(index % 2 == 0 and palette.raised or palette.black)
            surface.DrawRect(0, 0, width, height)
            if selectedProfession and selectedProfession.statBonuses[attribute] then
                surface.SetDrawColor(palette.bonus)
                surface.DrawRect(0, 0, 3, height)
            end
        end
        local value = vgui.Create("DLabel", row)
        value:Dock(RIGHT)
        value:DockMargin(0, 0, 8, 0)
        value:SetWide(58)
        value:SetFont("DermaDefaultBold")
        value:SetContentAlignment(6)
        local name = vgui.Create("DLabel", row)
        name:Dock(FILL)
        name:DockMargin(8, 0, 0, 0)
        name:SetText(attributeLabel(attribute))
        name:SetTextColor(palette.text)
        values[attribute] = value
        rows[attribute] = row
    end
    addDetailText("Weapon handling effects cap at 10 effective points. Some specialty attributes have no gameplay effects yet.", nil, palette.muted)

    local cards, cardList = {}, {}
    local refreshSelection
    for _, id in ipairs(ids) do
        local profession = assert(ZM_Professions:GetKnown(id), "Missing profession: " .. tostring(id))
        local icon = self:GetIconStatus(id)
        local card = button("", function()
            draft.job = profession.id
            refreshSelection()
        end, grid)
        card:Dock(NODOCK)
        card:DockMargin(0, 0, 0, 0)
        card:SetSize(100, 70)
        card:SetText("")
        card:SetTooltip(profession.name)
        card.Paint = function(control, width, height)
            local selected = selectedProfession and selectedProfession.id == profession.id
            surface.SetDrawColor(selected and palette.raised or palette.black)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor((selected or control:IsHovered() or control:HasFocus()) and palette.redBright or palette.border)
            surface.DrawOutlinedRect(0, 0, width, height)
            drawIcon(icon, (width - 24) * 0.5, 8, 24)
        end
        local name = vgui.Create("DLabel", card)
        name:Dock(BOTTOM)
        name:DockMargin(4, 0, 4, 4)
        name:SetTall(30)
        name:SetFont("DermaDefaultBold")
        name:SetTextColor(palette.text)
        name:SetText(profession.name)
        name:SetWrap(true)
        name:SetContentAlignment(5)
        name:SetMouseInputEnabled(false)
        cards[id] = card
        cardList[#cardList + 1] = card
    end

    local nextButton = button("NEXT: ATTRIBUTES", function()
        if not ZM_Professions:GetKnown(draft.job) then
            description:SetText("Choose an available profession before continuing.")
            return
        end
        menu.Step = 5
        menu:Render()
    end)

    refreshSelection = function()
        local profession = ZM_Professions:GetKnown(draft.job)
        selectedProfession = profession
        selectedIcon = profession and self:GetIconStatus(profession.id) or nil
        title:SetText(profession and string.upper(profession.name) or "SELECT A PROFESSION")
        if profession then
            description:SetText(profession.description ~= "" and profession.description or "No description is available.")
            local offered = {}
            for service, enabled in pairs(profession.services) do
                if enabled then offered[#offered + 1] = service end
            end
            table.sort(offered)
            services:SetText("Services: " .. (#offered > 0 and table.concat(offered, ", ") or "None")
                .. "\nDaily delivery tiers: " .. #profession.deliveries)
        else
            description:SetText(#ids == 0 and "The profession catalogue is unavailable. Return and try again."
                or (draft.job and "That profession is unavailable. Choose another."
                or "Select a profession to view its description and bonuses."))
            services:SetText("")
        end
        for _, attribute in ipairs(ZM_CharacterRules.Attributes) do
            local bonus = profession and profession.statBonuses[attribute] or nil
            values[attribute]:SetText(bonus and ("+" .. bonus) or (profession and "0" or "-"))
            values[attribute]:SetTextColor(bonus and palette.bonus or palette.muted)
        end
        nextButton:SetEnabled(profession ~= nil)
    end

    local cardHeight, gap = 70, 6
    local gridHeight = math.max(0, math.ceil(#cardList / 2) * (cardHeight + gap) - gap)
    grid.PerformLayout = function(_, width)
        local cardWidth = math.floor((width - gap) / 2)
        for index, card in ipairs(cardList) do
            card:SetPos(((index - 1) % 2) * (cardWidth + gap),
                math.floor((index - 1) / 2) * (cardHeight + gap))
            card:SetSize(cardWidth, cardHeight)
        end
    end
    root.PerformLayout = function(panel, width)
        local detailHeight = 8
        for _, child in ipairs(detailElements) do
            local _, top, _, bottom = child:GetDockMargin()
            detailHeight = detailHeight + top + child:GetTall() + bottom
        end
        local wantedHeight
        if width >= 420 then
            local gridWidth = math.floor((width - 10) * 0.46)
            grid:SetPos(0, 0)
            grid:SetSize(gridWidth, gridHeight)
            details:SetPos(gridWidth + 10, 0)
            details:SetSize(width - gridWidth - 10, detailHeight)
            wantedHeight = math.max(gridHeight, detailHeight)
        else
            grid:SetPos(0, 0)
            grid:SetSize(width, gridHeight)
            details:SetPos(0, gridHeight + 10)
            details:SetSize(width, detailHeight)
            wantedHeight = gridHeight + 10 + detailHeight
        end
        if panel:GetTall() ~= wantedHeight then panel:SetTall(wantedHeight) end
    end
    refreshSelection()
    return { root = root, grid = grid, details = details, cards = cards, values = values, rows = rows,
        detailElements = detailElements, detailTexts = detailTexts, title = title, description = description,
        backstory = backstory, services = services, nextButton = nextButton }
end

return Picker
