ZM_CharacterCards = ZM_CharacterCards or {}
local Cards = ZM_CharacterCards

Cards.RendererVersion = 5
Cards.MaximumVisible = 3
Cards.MaximumInFlight = 1
Cards.CompositionBudgetSeconds = 0.002
Cards.FieldOfView = 32
Cards.FrameMargin = 1.14
Cards.HeadroomRatio = 0.16
Cards.LoadoutBoxWidth = 128
Cards.LoadoutBoxHeight = 38
Cards.LoadoutBoxSpacing = 6
Cards.LoadoutOriginX = 14
Cards.LoadoutOriginY = 36
Cards.Generation = Cards.Generation or 0
Cards.Entries = Cards.Entries or {}
Cards.Queue = Cards.Queue or {}

function Cards:Key(profile, row)
    return table.concat({
        tostring(profile or ""),
        tostring(row and row.slot or ""),
        tostring(row and row.presentationRevision or ""),
        tostring(self.RendererVersion)
    }, ":")
end

function Cards:Release(entry)
    if not entry or entry.released then return end
    entry.released = true
    local panel = entry.panel
    local entity = IsValid(panel) and panel:GetEntity() or nil
    if IsValid(entity) then ZM_Clothing:Apply(entity, "", "") end
    if IsValid(panel) then
        panel.CardEntry = nil
        panel:Remove()
    end
    self.Entries[entry.slot] = nil
end

function Cards:Reset()
    self.Generation = self.Generation + 1
    local entries = self.Entries
    self.Entries = {}
    self.Queue = {}
    for _, entry in pairs(entries) do self:Release(entry) end
end

local function applyAppearance(panel, entity, appearance)
    entity:SetSkin(tonumber(appearance.skin) or 0)
    for id, value in pairs(appearance.bodygroups or {}) do
        entity:SetBodygroup(tonumber(id) or 0, tonumber(value) or 0)
    end
    local colour = appearance.playerColour or {}
    panel.PlayerColour = Vector(
        math.Clamp(tonumber(colour[1]) or 1, 0, 1),
        math.Clamp(tonumber(colour[2]) or 1, 0, 1),
        math.Clamp(tonumber(colour[3]) or 1, 0, 1)
    )
    if not entity.GetPlayerColor then
        entity.GetPlayerColor = function() return panel.PlayerColour end
    end
end

local function frameFullBody(panel, entity)
    local minimum, maximum = entity:GetRenderBounds()
    if not minimum or not maximum then return nil, "Model bounds are unavailable" end
    minimum = Vector(minimum.x, minimum.y, minimum.z)
    maximum = Vector(maximum.x, maximum.y, maximum.z)
    local unpaddedHeight = maximum.z - minimum.z
    minimum.z = minimum.z - unpaddedHeight * 0.035
    maximum.z = maximum.z + unpaddedHeight * Cards.HeadroomRatio
    local centre = (minimum + maximum) * 0.5
    local halfHeight = (maximum.z - minimum.z) * 0.5
    local halfWidth = math.max(math.abs(maximum.y - centre.y), math.abs(minimum.y - centre.y))
    local tangent = math.tan(math.rad(Cards.FieldOfView * 0.5))
    local aspect = math.max(panel:GetWide(), 1) / math.max(panel:GetTall(), 1)
    local verticalDistance = halfHeight / math.max(tangent / math.max(aspect, 1), 0.001)
    local horizontalDistance = halfWidth / math.max(tangent, 0.001)
    local distance = math.max(verticalDistance, horizontalDistance) * Cards.FrameMargin
    if distance <= 0 or distance ~= distance then return nil, "Model bounds are invalid" end
    distance = math.Clamp(distance, 120, 480)
    panel:SetFOV(Cards.FieldOfView)
    panel:SetLookAt(centre)
    panel:SetCamPos(centre + Vector(distance, 0, 0))
    return {
        minimum = minimum,
        maximum = maximum,
        centre = centre,
        height = maximum.z - minimum.z,
        distance = distance,
        aspect = aspect,
        margin = Cards.FrameMargin,
        headroom = maximum.z - (centre.z + unpaddedHeight * 0.5)
    }
end

// The dossier lists every equipped weapon as a stacked slot box rather than posing world models on the portrait.
local function buildLoadout(row)
    local entries = {}
    for _, weapon in ipairs(row and row.weapons or {}) do
        local itemId = type(weapon) == "table" and weapon.itemId or nil
        if type(itemId) == "string" and itemId ~= "" then
            local slot = tonumber(weapon.slot)
            entries[#entries + 1] = {
                label = weapon.selected == true and "EQUIPPED" or ("SLOT " .. tostring(slot or #entries + 1)),
                value = weapon.name or itemId,
                definition = ZM_Items and ZM_Items:GetDefinition(itemId) or nil,
                filled = true,
                active = weapon.selected == true
            }
        end
    end
    if #entries == 0 then
        entries[1] = { label = "WEAPONS", value = "UNARMED", filled = false, active = false }
    end
    return entries
end

local function fitText(value, font, available)
    surface.SetFont(font)
    if surface.GetTextSize(value) <= available then return value end
    while #value > 3 and surface.GetTextSize(value .. "..") > available do
        value = string.sub(value, 1, #value - 1)
    end
    return value .. ".."
end

// Weapons have no authored thumbnails, so a reused child spawn icon draws between the box chrome and PaintOver.
local function drawSlotIcon(entry, index, definition, x, y, size)
    if not definition or not ZM_ItemIcons then return false end
    local override = ZM_ItemIcons:GetOverride(definition)
    if override then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(override)
        surface.DrawTexturedRect(x, y, size, size)
        return true
    end
    if type(definition.iconModel) ~= "string" then return false end
    if not IsValid(entry.panel) then return false end
    entry.icons = entry.icons or {}
    local holder = entry.icons[index]
    if IsValid(holder) and holder.IconModel ~= definition.iconModel then
        holder:Remove()
        holder = nil
    end
    if not IsValid(holder) then
        holder = vgui.Create("DPanel", entry.panel)
        holder:SetPaintBackgroundEnabled(false)
        holder:SetPaintBorderEnabled(false)
        holder:SetMouseInputEnabled(false)
        holder:SetKeyboardInputEnabled(false)
        holder.IconModel = definition.iconModel
        ZM_ItemIcons:Attach(holder, definition, 0)
        entry.icons[index] = holder
    end
    holder:SetPos(x, y)
    holder:SetSize(size, size)
    holder:SetVisible(true)
    return true
end

local function hideSlotIcons(entry, fromIndex)
    for index, holder in pairs(entry.icons or {}) do
        if index >= fromIndex and IsValid(holder) then holder:SetVisible(false) end
    end
end

local function drawLoadout(entry, width, height)
    local entries = entry.loadout
    local palette = ZM_DermaSkin and ZM_DermaSkin.Palette or {}
    local text = palette.text or Color(226, 230, 235)
    local muted = palette.muted or Color(138, 146, 156)
    local accent = palette.redBright or Color(239, 57, 72)
    local border = palette.border or Color(85, 22, 29)
    local boxWidth = math.min(Cards.LoadoutBoxWidth, math.floor(width * 0.44))
    local boxHeight = Cards.LoadoutBoxHeight
    local x, y = Cards.LoadoutOriginX, Cards.LoadoutOriginY
    if boxWidth < 60 then
        hideSlotIcons(entry, 1)
        return 0
    end
    draw.SimpleText("WEAPONS", "DermaDefaultBold", x, y - 17, muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    surface.SetDrawColor(border.r, border.g, border.b, 220)
    surface.DrawRect(x, y - 4, boxWidth, 1)
    local drawn = 0
    for index, slotEntry in ipairs(entries) do
        if y + boxHeight > height - 10 then break end
        surface.SetDrawColor(9, 12, 17, 234)
        surface.DrawRect(x, y, boxWidth, boxHeight)
        surface.SetDrawColor(border.r, border.g, border.b, 255)
        surface.DrawOutlinedRect(x, y, boxWidth, boxHeight, 1)
        surface.SetDrawColor(accent.r, accent.g, accent.b, slotEntry.active and 235 or 110)
        surface.DrawRect(x, y, 3, boxHeight)
        local iconSize = boxHeight - 10
        local textX = x + 12
        if drawSlotIcon(entry, index, slotEntry.definition, x + 9, y + 5, iconSize) then
            textX = x + 13 + iconSize
        end
        local available = math.max(boxWidth - (textX - x) - 8, 16)
        draw.SimpleText(slotEntry.label, "DermaDefault", textX, y + 5, muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(fitText(string.upper(tostring(slotEntry.value)), "DermaDefaultBold", available),
            "DermaDefaultBold", textX, y + 19, slotEntry.filled and text or muted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + boxHeight + Cards.LoadoutBoxSpacing
        drawn = drawn + 1
    end
    hideSlotIcons(entry, drawn + 1)
    return drawn
end

function Cards:Create(parent, profile, row)
    local slot = tonumber(row and row.slot)
    local appearance = row and row.appearance
    if not slot or slot < 1 or slot > self.MaximumVisible or type(appearance) ~= "table"
        or type(appearance.model) ~= "string" or not util.IsValidModel(appearance.model) then
        return nil, "Character preview data is unavailable"
    end
    if self.Entries[slot] then self:Release(self.Entries[slot]) end

    local panel = vgui.Create("DModelPanel", parent)
    panel:Dock(TOP)
    panel:DockMargin(4, 8, 4, 8)
    panel:SetTall(286)
    panel:SetModel(appearance.model)
    panel:SetAmbientLight(Color(42, 48, 58))
    panel:SetDirectionalLight(BOX_TOP, Color(255, 228, 194))
    panel:SetDirectionalLight(BOX_FRONT, Color(156, 178, 202))
    panel:SetDirectionalLight(BOX_RIGHT, Color(112, 54, 48))
    local modelPaint = panel.Paint
    panel.Paint = function(preview, width, height)
        surface.SetDrawColor(6, 10, 15, 245)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(19, 28, 38, 220)
        surface.DrawRect(8, 8, width - 16, math.floor(height * 0.58))
        surface.SetDrawColor(22, 16, 16, 245)
        surface.DrawRect(8, math.floor(height * 0.58), width - 16, math.ceil(height * 0.42) - 8)
        surface.SetDrawColor(158, 43, 48, 64)
        surface.DrawRect(8, math.floor(height * 0.58), width - 16, 1)
        for index = 1, 5 do
            surface.SetDrawColor(255, 255, 255, 3)
            surface.DrawRect(12, 16 + index * 32, width - 24, 1)
        end
        local painted = modelPaint(preview, width, height)
        local cardEntry = preview.CardEntry
        if cardEntry then cardEntry.loadoutDrawn = drawLoadout(cardEntry, width, height) end
        return painted
    end
    panel.PlayerColour = Vector(1, 1, 1)
    panel.LayoutEntity = function(preview, entity)
        entity:SetAngles(Angle(0, 24, 0))
        preview:RunAnimation()
    end
    local entry = {
        key = self:Key(profile, row),
        slot = slot,
        generation = self.Generation,
        panel = panel,
        row = row,
        attempts = 0,
        retryAt = 0,
        loadout = buildLoadout(row)
    }
    panel.PaintOver = function(_, width, height)
        surface.SetDrawColor(116, 126, 138, 100)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        surface.SetDrawColor(208, 56, 62, 210)
        surface.DrawRect(0, 0, 46, 2)
        surface.DrawRect(width - 46, height - 2, 46, 2)
        surface.SetDrawColor(220, 225, 230, 150)
        surface.DrawRect(10, 10, 18, 1)
        surface.DrawRect(10, 10, 1, 18)
        surface.DrawRect(width - 28, 10, 18, 1)
        surface.DrawRect(width - 11, 10, 1, 18)
    end
    panel.CardEntry = entry
    panel.OnRemove = function()
        if entry.released then return end
        local entity = panel:GetEntity()
        if IsValid(entity) then ZM_Clothing:Apply(entity, "", "") end
        entry.released = true
        if Cards.Entries[slot] == entry then Cards.Entries[slot] = nil end
    end
    self.Entries[slot] = entry
    self.Queue[#self.Queue + 1] = entry
    return panel
end

function Cards:ProcessQueue()
    local started = SysTime()
    local inFlight = 0
    for index = #self.Queue, 1, -1 do
        local entry = self.Queue[index]
        local panel = entry.panel
        if entry.released or entry.generation ~= self.Generation or not IsValid(panel) then
            table.remove(self.Queue, index)
        elseif not entry.ready and RealTime() >= entry.retryAt and inFlight < self.MaximumInFlight then
            inFlight = inFlight + 1
            local entity = panel:GetEntity()
            if IsValid(entity) then
                local composeStarted = SysTime()
                applyAppearance(panel, entity, entry.row.appearance)
                if not entry.frame then
                    local frame, frameError = frameFullBody(panel, entity)
                    if not frame then
                        entry.failure = frameError
                        entry.retryAt = RealTime() + 0.25
                        continue
                    end
                    entry.frame = frame
                end
                local outfit = entry.row.outfit or {}
                entry.attempts = entry.attempts + 1
                if ZM_Clothing:Apply(entity, outfit.shirt or "", outfit.pants or "") then
                    entry.ready = true
                    entry.composeMs = (SysTime() - composeStarted) * 1000
                    table.remove(self.Queue, index)
                else
                    entry.composeMs = (SysTime() - composeStarted) * 1000
                    entry.retryAt = RealTime() + 0.25
                end
            else
                entry.retryAt = RealTime() + 0.1
            end
        end
        if SysTime() - started >= self.CompositionBudgetSeconds then break end
    end
end

function Cards:Status()
    local entries = {}
    for slot, entry in pairs(self.Entries) do
        local entity = IsValid(entry.panel) and entry.panel:GetEntity() or nil
        local bodygroups = {}
        if IsValid(entity) then
            for _, group in ipairs(entity:GetBodyGroups() or {}) do
                bodygroups[tostring(group.id)] = entity:GetBodygroup(group.id)
            end
        end
        local loadout = {}
        for _, slotEntry in ipairs(entry.loadout or {}) do
            loadout[#loadout + 1] = {
                label = slotEntry.label, value = tostring(slotEntry.value),
                filled = slotEntry.filled == true, icon = slotEntry.definition ~= nil
            }
        end
        entries[#entries + 1] = {
            slot = slot, key = entry.key, ready = entry.ready == true,
            attempts = entry.attempts, valid = IsValid(entry.panel),
            weaponModels = 0, loadout = loadout,
            loadoutDrawn = entry.loadoutDrawn or 0, failure = entry.failure,
            panelHeight = IsValid(entry.panel) and entry.panel:GetTall() or 0,
            framed = entry.frame ~= nil,
            frameHeight = entry.frame and entry.frame.height or nil,
            cameraDistance = entry.frame and entry.frame.distance or nil,
            frameAspect = entry.frame and entry.frame.aspect or nil,
            frameMargin = entry.frame and entry.frame.margin or nil,
            frameHeadroom = entry.frame and entry.frame.headroom or nil,
            styledBackground = true,
            composeMs = entry.composeMs,
            model = IsValid(entity) and entity:GetModel() or nil,
            bodygroups = bodygroups,
            materials = IsValid(entity) and entity:GetMaterials() or {}
        }
    end
    table.sort(entries, function(a, b) return a.slot < b.slot end)
    return {
        rendererVersion = self.RendererVersion,
        maximumVisible = self.MaximumVisible,
        maximumInFlight = self.MaximumInFlight,
        compositionBudgetMs = self.CompositionBudgetSeconds * 1000,
        queued = #self.Queue,
        entries = entries
    }
end

hook.Add("PreRender", "ZM.CharacterCards.Compose", function()
    Cards:ProcessQueue()
end)

concommand.Add("zombiesim_dev_character_card_status", function()
    print("[ZombieSim] Character card status: " .. (util.TableToJSON(Cards:Status(), false) or "{}"))
end)
