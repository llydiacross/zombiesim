// Client crafting window. Recipe data, eligibility, and job progress come from the server (ZM.CraftingState);
// the client only sends open/start/cancel requests with a recipe id and batch count.
ZM_Crafting = ZM_Crafting or {}
local Crafting = ZM_Crafting

surface.CreateFont("ZM_CraftingHeading", { font = "Trebuchet MS", size = 20, weight = 900, antialias = true })
surface.CreateFont("ZM_CraftingBody", { font = "Trebuchet MS", size = 15, weight = 600, antialias = true })
surface.CreateFont("ZM_CraftingSmall", { font = "Trebuchet MS", size = 13, weight = 600, antialias = true })

local good = Color(96, 190, 110)
local bad = Color(239, 57, 72)
local gold = Color(222, 184, 84)

local function itemName(itemId)
    local definition = ZM_Items:GetDefinition(itemId)
    return definition and definition.name or itemId
end

function Crafting:SendRequest(request)
    net.Start("ZM.CraftingRequest")
        net.WriteString(util.TableToJSON(request, false) or "{}")
    net.SendToServer()
end

net.Receive("ZM.CraftingState", function()
    local state = util.JSONToTable(net.ReadString())
    if type(state) ~= "table" then return end
    Crafting.State = state
    if state.message then
        Crafting.Message = { text = state.message, ok = state.ok ~= false }
    end
    Crafting:Rebuild()
end)

local function findRecipe(recipeId)
    for _, recipe in ipairs(Crafting.State and Crafting.State.recipes or {}) do
        if recipe.id == recipeId then return recipe end
    end
end

local function line(parent, text, color, font)
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:DockMargin(0, 0, 0, 2)
    label:SetFont(font or "ZM_CraftingBody")
    label:SetTextColor(color or ZM_DermaSkin.Palette.text)
    label:SetText(text)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
    return label
end

local function itemRow(parent, itemId, text, color)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(34)
    row:DockMargin(0, 0, 0, 2)
    row.Paint = function(_, width, height)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText(text, "ZM_CraftingBody", 40, height * 0.5, color or ZM_DermaSkin.Palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local icon = vgui.Create("DPanel", row)
    icon:Dock(LEFT)
    icon:SetWide(34)
    icon.Paint = function(_, width, height)
        ZM_ItemIcons:DrawOverride(ZM_Items:GetDefinition(itemId), 2, 2, math.min(width, height) - 4)
    end
    ZM_ItemIcons:Attach(icon, ZM_Items:GetDefinition(itemId), 2)
    return row
end

local function buildRecipeList(parent)
    local list = vgui.Create("DScrollPanel", parent)
    list:Dock(LEFT)
    list:SetWide(230)
    list:DockMargin(0, 0, 10, 0)
    local lastCategory
    local recipes = table.Copy(Crafting.State.recipes or {})
    table.sort(recipes, function(left, right)
        if left.category ~= right.category then return left.category < right.category end
        return left.name < right.name
    end)
    for _, recipe in ipairs(recipes) do
        if recipe.category ~= lastCategory then
            lastCategory = recipe.category
            local header = line(list, string.upper(recipe.category), ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
            header:DockMargin(2, 6, 0, 2)
        end
        local button = vgui.Create("DButton", list)
        button:Dock(TOP)
        button:SetTall(28)
        button:DockMargin(0, 0, 0, 2)
        button:SetText("")
        button.Paint = function(panel, width, height)
            local selected = Crafting.SelectedRecipe == recipe.id
            surface.SetDrawColor(selected and ZM_DermaSkin.Palette.redDark or (panel:IsHovered() and ZM_DermaSkin.Palette.raised or ZM_DermaSkin.Palette.panel))
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(selected and ZM_DermaSkin.Palette.red or ZM_DermaSkin.Palette.border)
            surface.DrawOutlinedRect(0, 0, width, height)
            draw.SimpleText(recipe.name, "ZM_CraftingBody", 8, height * 0.5, recipe.canCraft and ZM_DermaSkin.Palette.text or ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if recipe.maxBatches > 0 then
                draw.SimpleText("x" .. recipe.maxBatches, "ZM_CraftingSmall", width - 8, height * 0.5, recipe.canCraft and good or ZM_DermaSkin.Palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        button.DoClick = function()
            Crafting.SelectedRecipe = recipe.id
            Crafting.BatchCount = 1
            Crafting:Rebuild()
        end
    end
end

local function buildDetails(parent, recipe)
    local details = vgui.Create("DScrollPanel", parent)
    details:Dock(FILL)
    if not recipe then
        line(details, "Select a recipe.", ZM_DermaSkin.Palette.muted)
        return
    end
    line(details, recipe.name, ZM_DermaSkin.Palette.text, "ZM_CraftingHeading")
    line(details, string.format("%s  |  %ss per craft  |  level %d", recipe.category, recipe.craftTime, recipe.levelRequirement), ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    if recipe.freshness == "inherit" then
        line(details, "Freshness follows the food used.", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    elseif recipe.freshness == "new" then
        line(details, "Produces fresh food.", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall")
    end
    for _, reason in ipairs(recipe.unmet or {}) do
        line(details, reason, bad)
    end
    if not recipe.stationInRange then
        line(details, Crafting.State.inDen and "Stand next to a crafting station." or "Crafting is only available inside your den.", bad)
    end

    line(details, "INGREDIENTS", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall"):DockMargin(0, 8, 0, 2)
    for _, stack in ipairs(recipe.ingredients) do
        itemRow(details, stack.item, string.format("%s  %d / %d", itemName(stack.item), stack.have, stack.count), stack.have >= stack.count and good or bad)
    end
    line(details, "RESULT", ZM_DermaSkin.Palette.muted, "ZM_CraftingSmall"):DockMargin(0, 8, 0, 2)
    for _, stack in ipairs(recipe.results) do
        itemRow(details, stack.item, string.format("%s  x%d", itemName(stack.item), stack.count), gold)
    end
end

local function buildFooter(parent, recipe)
    local state = Crafting.State
    local footer = vgui.Create("DPanel", parent)
    footer:Dock(BOTTOM)
    footer:SetTall(64)
    footer:DockMargin(0, 10, 0, 0)
    footer.Paint = function(_, width, height)
        local active = state.active
        if active then
            local duration = math.max(0.01, active.batchEndsAt - active.batchStartedAt)
            local progress = math.Clamp((CurTime() - active.batchStartedAt) / duration, 0, 1)
            surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
            surface.DrawRect(0, 0, width, 22)
            surface.SetDrawColor(ZM_DermaSkin.Palette.red)
            surface.DrawRect(0, 0, width * progress, 22)
            draw.SimpleText(string.format("%s  %d / %d", active.name, active.completed + 1, active.batches), "ZM_CraftingSmall", 8, 11, ZM_DermaSkin.Palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("%.1fs", math.max(0, active.batchEndsAt - CurTime())), "ZM_CraftingSmall", width - 8, 11, ZM_DermaSkin.Palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local message = Crafting.Message
        if message then
            draw.SimpleText(message.text, "ZM_CraftingSmall", 0, 34, message.ok and ZM_DermaSkin.Palette.muted or bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    local controls = vgui.Create("DPanel", footer)
    controls:Dock(BOTTOM)
    controls:SetTall(28)
    controls.Paint = nil

    local services = vgui.Create("DButton", controls)
    services:Dock(LEFT)
    services:SetWide(120)
    services:SetText("Services")
    services.DoClick = function()
        if ZM_ProfessionsUI then ZM_ProfessionsUI:Open() end
    end

    if state.active then
        local cancel = vgui.Create("DButton", controls)
        cancel:Dock(RIGHT)
        cancel:SetWide(120)
        cancel:SetText("Cancel")
        cancel.DoClick = function() Crafting:SendRequest({ action = "cancel" }) end
        return
    end
    if not recipe then return end

    local craft = vgui.Create("DButton", controls)
    craft:Dock(RIGHT)
    craft:SetWide(120)
    craft:SetText("Craft")
    craft:SetEnabled(recipe.canCraft == true)

    local count = vgui.Create("DNumberWang", controls)
    count:Dock(RIGHT)
    count:SetWide(60)
    count:DockMargin(0, 0, 8, 0)
    count:SetDecimals(0)
    count:SetMin(1)
    count:SetMax(math.max(1, recipe.maxBatches))
    count:SetValue(math.Clamp(Crafting.BatchCount or 1, 1, math.max(1, recipe.maxBatches)))
    count.OnValueChanged = function(_, value)
        Crafting.BatchCount = math.floor(tonumber(value) or 1)
    end

    craft.DoClick = function()
        local batches = math.Clamp(math.floor(tonumber(count:GetValue()) or 1), 1, math.max(1, recipe.maxBatches))
        Crafting:SendRequest({ action = "start", recipeId = recipe.id, count = batches })
    end
end

function Crafting:Rebuild()
    local frame = self.Frame
    if not IsValid(frame) or not IsValid(frame.Body) then return end
    frame.Body:Clear()
    local state = self.State
    if not state then
        line(frame.Body, "Loading recipes...", ZM_DermaSkin.Palette.muted)
        return
    end
    if state.active then
        self.SelectedRecipe = state.active.recipeId
    end
    if not findRecipe(self.SelectedRecipe) then
        self.SelectedRecipe = state.recipes and state.recipes[1] and state.recipes[1].id or nil
    end
    local recipe = findRecipe(self.SelectedRecipe)
    buildFooter(frame.Body, recipe)
    buildRecipeList(frame.Body)
    buildDetails(frame.Body, recipe)
end

function Crafting:Open()
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:SendRequest({ action = "open" })
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("CRAFTING STATION")
    frame:SetSize(math.min(760, ScrW() - 40), math.min(500, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if Crafting.Frame == frame then Crafting.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
    self.Message = nil
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(8, 8, 8, 8)
    body.Paint = nil
    frame.Body = body
    self:Rebuild()
    self:SendRequest({ action = "open" })
end
