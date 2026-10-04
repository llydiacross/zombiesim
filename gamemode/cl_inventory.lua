// Client inventory: mirrors the server snapshot. The regular inventory and den storage are separate windows; changes are requests
// (ZM.InventoryAction) that the server validates; the window only redraws from the snapshots the server sends back.
ZM_Inventory = ZM_Inventory or {}
local Inventory = ZM_Inventory

Inventory.Snapshot = Inventory.Snapshot or { backpack = {}, stash = {}, capacity = {}, canAccessStash = false, equipped = {} }
Inventory.Loaded = Inventory.Loaded or false

local slotSize = 64
local slotGap = 4
local gold = Color(255, 196, 64)
local equippedColor = Color(110, 220, 130)
local dragName = "zm_inventory_item"

hook.Add("PlayerBindPress", "ZM.Inventory.WeaponSlotNumbers", function(_, bind, pressed)
    if not pressed then return end
    local slot = tonumber(string.match(string.lower(bind or ""), "^slot([1-3])$"))
    if not slot then return end
    local loadout = Inventory.Snapshot.weaponSlots and Inventory.Snapshot.weaponSlots[slot]
    if loadout and loadout.instanceId then
        Inventory:SendAction({ action = "equip_slot", instanceId = loadout.instanceId, slot = slot })
        return true
    end
end)

surface.CreateFont("ZM_InventorySmall", { font = "Trebuchet MS", size = 13, weight = 700, antialias = true })
surface.CreateFont("ZM_InventoryTile", { font = "Trebuchet MS", size = 18, weight = 900, antialias = true })
surface.CreateFont("ZM_InventoryHeading", { font = "Trebuchet MS", size = 16, weight = 900, antialias = true })

net.Receive("ZM.InventorySnapshot", function()
    local snapshot = util.JSONToTable(net.ReadString())
    if type(snapshot) ~= "table" then
        return
    end
    snapshot.backpack = snapshot.backpack or {}
    snapshot.stash = snapshot.stash or {}
    snapshot.capacity = snapshot.capacity or {}
    snapshot.equipped = snapshot.equipped or {}
    Inventory.ServerTimeOffset = (tonumber(snapshot.serverTime) or os.time()) - os.time()
    Inventory.Snapshot = snapshot
    Inventory.Loaded = true
    hook.Run("ZM.InventoryUpdated", snapshot)
end)

net.Receive("ZM.InventoryActionResult", function()
    local ok = net.ReadBool()
    local message = net.ReadString()
    Inventory.Status = { text = message, ok = ok, at = CurTime() }
end)

net.Receive("ZM.DenEntity.Open", function()
    local class = net.ReadString()
    if class == "zn_den_stash" then
        Inventory:OpenDen()
    elseif class == "zn_crafting_station" and ZM_Crafting and ZM_Crafting.Open then
        ZM_Crafting:Open()
    elseif class == "zn_mastercraft_station" and ZM_MastercraftUI and ZM_MastercraftUI.Open then
        ZM_MastercraftUI:Open()
    end
end)

function Inventory:GetSnapshot()
    return self.Snapshot
end

function Inventory:RequestSnapshot()
    net.Start("ZM.InventoryRequest")
    net.SendToServer()
end

function Inventory:SendAction(request)
    net.Start("ZM.InventoryAction")
        net.WriteString(util.TableToJSON(request, false) or "{}")
    net.SendToServer()
end

function Inventory:IsEquipped(instanceId)
    for _, equippedId in ipairs(self.Snapshot.equipped or {}) do
        if equippedId == instanceId then
            return true
        end
    end
    return false
end

local function abbreviate(name)
    local letters = {}
    for word in string.gmatch(name, "%w+") do
        table.insert(letters, string.upper(string.sub(word, 1, 1)))
        if #letters == 3 then
            break
        end
    end
    return table.concat(letters)
end

function Inventory:GetServerTime()
    return os.time() + (self.ServerTimeOffset or 0)
end

local bandColors = {
    fresh = Color(120, 210, 90),
    stale = Color(225, 190, 70),
    spoiled = Color(200, 80, 60)
}

local function formatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    if hours >= 48 then
        return math.floor(hours / 24) .. " days"
    elseif hours >= 1 then
        return hours .. " h"
    end
    return math.max(1, math.floor(seconds / 60)) .. " min"
end

local function describeFood(lines, instance)
    local now = Inventory:GetServerTime()
    local effects = ZM_Food:GetEffects(instance, now)
    if not effects then
        return
    end
    local definition = ZM_Items:GetDefinition(instance.itemId)
    local tier = ZM_StaticData.FoodTiers[definition.food.tier]
    table.insert(lines, string.format("%s %s food (tier %d)", tier and tier.label or "", definition.food.preparation, definition.food.tier))
    local band = ZM_Food.Bands[effects.band]
    local untilNext = ZM_Food:GetSecondsToNextBand(instance, now)
    local nextLabel = effects.band == "fresh" and "stale" or "spoiled"
    table.insert(lines, band.label .. (untilNext and (" - " .. nextLabel .. " in " .. formatDuration(untilNext)) or ""))
    local summary = ZM_Food:DescribeEffects(effects)
    if summary ~= "" then
        table.insert(lines, "Each: " .. summary)
    end
end

local function describe(instance)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    if not definition then
        return "Unknown item (" .. tostring(instance.itemId) .. ")\nThis item no longer exists and is kept unchanged."
    end
    local lines = { ZM_Items:GetDisplayName(instance) .. (instance.count > 1 and (" x" .. instance.count) or ""), "Item level " .. instance.level }
    if definition.food then
        describeFood(lines, instance)
    end
    if definition.type == "bullet_weapon" then
        table.insert(lines, "Loaded: " .. tostring(tonumber(instance.clip) or 0))
        table.insert(lines, "Ammo: " .. tostring(definition.ammoId))
    end
    for name, score in SortedPairs(instance.attributes or {}) do
        table.insert(lines, "  " .. name .. ": " .. score)
    end
    local player = LocalPlayer()
    local action = definition.entityClass == "weapon" and "equip" or "use"
    local requiredLevel = ZM_Items:GetRequiredLevel(instance.itemId, instance)
    local playerLevel = IsValid(player) and player:GetLevel() or 0
    if definition.entityClass == "weapon" or requiredLevel > 1 then
        table.insert(lines, "Requires player level " .. requiredLevel .. " to " .. action .. " (you: " .. playerLevel .. ")")
    end
    for stat, required in SortedPairs(definition.statRequirements) do
        local current = IsValid(player) and player:GetStat(stat) or 0
        table.insert(lines, "Requires " .. stat .. " " .. required .. " to " .. action .. " (you: " .. current .. ")")
    end
    local canUse, reason = ZM_Items:CanUse(player, instance.itemId, instance)
    if not canUse then
        table.insert(lines, "Unavailable: " .. reason)
    end
    table.insert(lines, string.format("Value: $%.2f", ZM_Items:GetInstanceValue(instance)))
    if Inventory:IsEquipped(instance.instanceId) then
        table.insert(lines, "Equipped")
    end
    return table.concat(lines, "\n")
end

local function findEmptySlot(container)
    local used = {}
    for _, instance in ipairs(Inventory.Snapshot[container] or {}) do
        used[instance.slot] = true
    end
    for slot = 1, Inventory.Snapshot.capacity[container] or 0 do
        if not used[slot] then
            return slot
        end
    end
end

// Double click: use entity items, equip or unequip weapons.
local function primaryAction(instance)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    if not definition then
        return
    end
    if definition.entityClass == "entity" then
        Inventory:SendAction({ action = "use", instanceId = instance.instanceId })
    elseif definition.entityClass == "weapon" then
        Inventory:SendAction({ action = Inventory:IsEquipped(instance.instanceId) and "unequip" or "equip", instanceId = instance.instanceId })
    end
end

local function openContextMenu(instance, container, allowStashMoves)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    local menu = DermaMenu()
    if definition and container == "backpack" then
        if definition.entityClass == "entity" then
            menu:AddOption("Use", function() Inventory:SendAction({ action = "use", instanceId = instance.instanceId }) end)
        elseif definition.entityClass == "weapon" then
            if Inventory:IsEquipped(instance.instanceId) then
                menu:AddOption("Unequip", function() Inventory:SendAction({ action = "unequip", instanceId = instance.instanceId }) end)
            else
                menu:AddOption("Equip", function() Inventory:SendAction({ action = "equip", instanceId = instance.instanceId }) end)
            end
        end
        menu:AddOption("Drop", function()
            local function sendDrop(count)
                if count < 1 or count > instance.count or count ~= math.floor(count) then
                    Inventory.Status = { text = "Enter a whole number from 1 to " .. instance.count .. ".", ok = false, at = CurTime() }
                    return
                end
                Inventory.DropRequestCounter = (Inventory.DropRequestCounter or 0) + 1
                local requestId = string.format("%d-%d-%d", os.time(), math.floor(SysTime() * 1000000), Inventory.DropRequestCounter)
                Inventory:SendAction({ action = "drop", instanceId = instance.instanceId, count = count, requestId = requestId })
            end
            if instance.count == 1 then
                sendDrop(1)
            else
                Derma_StringRequest("DROP ITEM", "How many " .. definition.name .. " do you want to drop?",
                    tostring(instance.count), function(value)
                        local count = tonumber(value)
                        if not count then
                            Inventory.Status = { text = "Enter a whole number from 1 to " .. instance.count .. ".", ok = false, at = CurTime() }
                            return
                        end
                        sendDrop(count)
                    end)
            end
        end)
    end
    if allowStashMoves and Inventory.Snapshot.canAccessStash then
        local other = container == "backpack" and "stash" or "backpack"
        menu:AddOption("Move to " .. other, function()
            Inventory:SendAction({ action = "move", instanceId = instance.instanceId, container = other })
        end)
    end
    if instance.count > 1 then
        menu:AddOption("Split stack", function()
            local slot = findEmptySlot(container)
            if slot then
                Inventory:SendAction({ action = "move", instanceId = instance.instanceId, container = container, slot = slot, count = math.floor(instance.count / 2) })
            else
                Inventory.Status = { text = "There is no free slot to split into.", ok = false, at = CurTime() }
            end
        end)
    end
    menu:Open()
end

// Background and fallback label; a model spawn icon, when attached, draws above this.
local function paintTile(instance, width, height)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    local palette = ZM_DermaSkin.Palette
    surface.SetDrawColor(palette.raised)
    surface.DrawRect(0, 0, width, height)
    if not definition then
        draw.SimpleText("?", "ZM_InventoryTile", width * 0.5, height * 0.5, palette.redBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif not ZM_ItemIcons:DrawOverride(definition, 6, 6, math.min(width, height) - 12) and not definition.iconModel then
        draw.SimpleText(abbreviate(definition.name), "ZM_InventoryTile", width * 0.5, height * 0.5, palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

// Level, count, equipped marker, and border, drawn above the spawn icon.
local function paintTileOverlay(instance, width, height)
    local palette = ZM_DermaSkin.Palette
    draw.SimpleTextOutlined("L" .. instance.level, "ZM_InventorySmall", 4, 2, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    if instance.count > 1 then
        draw.SimpleTextOutlined("x" .. instance.count, "ZM_InventorySmall", width - 4, height - 2, palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
    end
    if Inventory:IsEquipped(instance.instanceId) then
        draw.SimpleText("E", "ZM_InventorySmall", width - 4, 2, equippedColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end
    local band = ZM_Food:GetBand(instance, Inventory:GetServerTime())
    if band then
        surface.SetDrawColor(bandColors[band])
        surface.DrawRect(4, height - 8, 5, 5)
    end
    surface.SetDrawColor(instance.mastercraft and gold or palette.border)
    surface.DrawOutlinedRect(0, 0, width, height, instance.mastercraft and 2 or 1)
end

local function decorateTile(tile, instance)
    tile.Paint = function(_, width, height) paintTile(instance, width, height) end
    tile.PaintOver = function(_, width, height) paintTileOverlay(instance, width, height) end
    ZM_ItemIcons:Attach(tile, ZM_Items:GetDefinition(instance.itemId), 6)
end

local function buildContainer(parent, container, locked, allowStashMoves)
    local layout = parent:Add("DIconLayout")
    layout:Dock(TOP)
    layout:SetSpaceX(slotGap)
    layout:SetSpaceY(slotGap)

    local bySlot, highestSlot = {}, Inventory.Snapshot.capacity[container] or 0
    for _, instance in ipairs(Inventory.Snapshot[container] or {}) do
        bySlot[instance.slot] = instance
        highestSlot = math.max(highestSlot, instance.slot)
    end

    for slot = 1, highestSlot do
        local slotPanel = layout:Add("DPanel")
        slotPanel:SetSize(slotSize, slotSize)
        slotPanel.Container = container
        slotPanel.Slot = slot
        slotPanel.Paint = function(_, width, height)
            surface.SetDrawColor(ZM_DermaSkin.Palette.black)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
        end
        slotPanel:Receiver(dragName, function(receiver, panels, dropped)
            local source = panels[1]
            if dropped and source and source.Instance and (source.Container ~= receiver.Container or source.Instance.slot ~= receiver.Slot) then
                Inventory:SendAction({ action = "move", instanceId = source.Instance.instanceId, container = receiver.Container, slot = receiver.Slot })
            end
        end)

        local instance = bySlot[slot]
        if instance then
            local tile = vgui.Create("DButton", slotPanel)
            tile:Dock(FILL)
            tile:SetText("")
            tile.Instance = instance
            tile.Container = container
            tile:SetTooltip(describe(instance))
            decorateTile(tile, instance)
            tile.DoDoubleClick = function()
                if container == "backpack" then
                    primaryAction(instance)
                end
            end
            tile.DoRightClick = function() openContextMenu(instance, container, allowStashMoves) end
            if not locked then
                tile:Droppable(dragName)
            end
        end
    end
    return layout
end

local function heading(parent, text, detail, detailColor)
    local label = vgui.Create("DPanel", parent)
    label:Dock(TOP)
    label:SetTall(24)
    label.Paint = function(_, width, height)
        draw.SimpleText(text, "ZM_InventoryHeading", 2, height * 0.5, ZM_DermaSkin.Palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if detail then
            draw.SimpleText(detail, "ZM_InventorySmall", width - 2, height * 0.5, detailColor or ZM_DermaSkin.Palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
end

function Inventory:Rebuild(frame)
    frame = frame or self.Frame
    if not IsValid(frame) or not IsValid(frame.Body) then
        return
    end
    frame.Body:Clear()
    if not self.Loaded then
        local loading = vgui.Create("DLabel", frame.Body)
        loading:Dock(FILL)
        loading:SetContentAlignment(5)
        loading:SetFont("ZM_InventoryHeading")
        loading:SetTextColor(ZM_DermaSkin.Palette.muted)
        loading:SetText("Loading inventory...")
        return
    end

    local snapshot = self.Snapshot
    local columnWidth = 5 * slotSize + 4 * slotGap + 18
    local containers = vgui.Create("DPanel", frame.Body)
    containers:Dock(FILL)
    containers.Paint = function() end

    local backpackColumn = vgui.Create("DPanel", containers)
    local showStash = frame.ShowDenStash and snapshot.canAccessStash
    backpackColumn:Dock(showStash and LEFT or FILL)
    if showStash then
        backpackColumn:SetWide(math.floor((frame.Body:GetWide() - 12) * 0.5))
    end
    backpackColumn.Paint = function() end
    heading(backpackColumn, "BACKPACK", string.format("%d / %d  -  lost on death", #snapshot.backpack, snapshot.capacity.backpack or 0), ZM_DermaSkin.Palette.redBright)
    local backpackScroll = vgui.Create("DScrollPanel", backpackColumn)
    backpackScroll:Dock(FILL)
    backpackScroll:DockMargin(0, 4, 0, 0)
    backpackScroll:SetWide(columnWidth)
    buildContainer(backpackScroll, "backpack", false, showStash)

    if showStash then
        local stashColumn = vgui.Create("DPanel", containers)
        stashColumn:Dock(FILL)
        stashColumn:DockMargin(12, 0, 0, 0)
        stashColumn.Paint = function() end
        heading(stashColumn, "SAFE DEN STASH", string.format("%d / %d", #snapshot.stash, snapshot.capacity.stash or 0), equippedColor)
        local stashScroll = vgui.Create("DScrollPanel", stashColumn)
        stashScroll:Dock(FILL)
        stashScroll:DockMargin(0, 4, 0, 0)
        stashScroll:SetWide(columnWidth)
        buildContainer(stashScroll, "stash", false, true)
    end

    local loadout = vgui.Create("DPanel", frame.Body)
    loadout:Dock(BOTTOM)
    loadout:DockMargin(0, 10, 0, 0)
    loadout:SetTall(128)
    loadout.Paint = function() end
    heading(loadout, "EQUIPPED LOADOUT", nil, equippedColor)

    local slots = vgui.Create("DPanel", loadout)
    slots:Dock(LEFT)
    slots:SetWide(5 * slotSize + 4 * slotGap)
    slots:DockMargin(0, 4, 0, 0)
    slots.Paint = function() end
    local money = vgui.Create("DPanel", loadout)
    money:Dock(FILL)
    money:DockMargin(6, 28, 0, 0)
    money.Paint = function(_, width)
        draw.SimpleText("Money", "ZM_InventoryHeading", 4, 1, equippedColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        ZM_DermaSkin.DrawTextSegments(4, 19, "ZM_InventoryHeading", {
            { text = "Cash: ", color = ZM_DermaSkin.Palette.text },
            { text = "$" .. string.Comma(snapshot.cash or 0), color = gold }
        }, TEXT_ALIGN_TOP)
        ZM_DermaSkin.DrawTextSegments(4, 39, "ZM_InventorySmall", {
            { text = "+(", color = ZM_DermaSkin.Palette.muted },
            { text = "$" .. string.Comma(snapshot.bundleCash or 0), color = gold },
            { text = ") from bundles", color = ZM_DermaSkin.Palette.muted }
        }, TEXT_ALIGN_TOP)
        ZM_DermaSkin.DrawTextSegments(4, 51, "ZM_InventorySmall", {
            { text = "+(", color = ZM_DermaSkin.Palette.muted },
            { text = "$" .. string.Comma(snapshot.bankCash or 0), color = gold },
            { text = ") stored in banks", color = ZM_DermaSkin.Palette.muted }
        }, TEXT_ALIGN_TOP)
    end
    local weaponSlots = snapshot.weaponSlots or {}
    for slot = 1, 3 do
        local box = vgui.Create("DPanel", slots)
        box:Dock(LEFT)
        box:SetWide(slotSize)
        box:DockMargin(0, 0, slotGap, 0)
        local equipped = weaponSlots[slot]
        local instance = nil
        for _, candidate in ipairs(snapshot.equippedItems or {}) do
            if equipped and candidate.instanceId == equipped.instanceId then instance = candidate break end
        end
        box.Paint = function(_, width, height)
            surface.SetDrawColor(ZM_DermaSkin.Palette.black)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(equipped and equipped.selected and equippedColor or ZM_DermaSkin.Palette.border)
            surface.DrawOutlinedRect(0, 0, width, height, 2)
            draw.SimpleText("WEAPON " .. slot, "ZM_InventorySmall", 4, 3, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if not instance then draw.SimpleText("EMPTY", "ZM_InventorySmall", width * 0.5, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
        end
        box:Receiver(dragName, function(receiver, panels, dropped)
            local source = panels[1]
            if dropped and source and source.Instance then
                Inventory:SendAction({ action = "equip_slot", instanceId = source.Instance.instanceId, slot = slot })
            end
        end)
        if instance then
            local tile = vgui.Create("DButton", box)
            tile:Dock(FILL)
            tile:DockMargin(2, 16, 2, 2)
            tile:SetText("")
            tile:SetTooltip(describe(instance))
            tile.Instance = instance
            tile.Container = "equipped"
            tile.Slot = slot
            decorateTile(tile, instance)
            tile:Droppable(dragName)
            tile.DoClick = function() Inventory:SendAction({ action = "equip_slot", instanceId = instance.instanceId, slot = slot }) end
        end
    end
    for _, label in ipairs({ "ARMOR", "CLOTHING" }) do
        local box = vgui.Create("DPanel", slots)
        box:Dock(LEFT)
        box:SetWide(slotSize)
        box:DockMargin(0, 0, slotGap, 0)
        box.Paint = function(_, width, height)
            surface.SetDrawColor(ZM_DermaSkin.Palette.black)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(ZM_DermaSkin.Palette.border)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(label, "ZM_InventorySmall", width * 0.5, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

function Inventory:OpenWindow(frameKey, title, showDenStash)
    local existing = self[frameKey]
    if IsValid(existing) then
        existing:MakePopup()
        self:RequestSnapshot()
        return
    end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle(title)
    frame:SetSize(math.min(860, ScrW() - 40), math.min(560, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.ShowDenStash = showDenStash
    frame.OnRemove = function()
        if Inventory[frameKey] == frame then Inventory[frameKey] = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self[frameKey] = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local status = vgui.Create("DPanel", frame)
    status:Dock(BOTTOM)
    status:DockMargin(12, 4, 12, 8)
    status:SetTall(20)
    status.Paint = function(_, width, height)
        local current = Inventory.Status
        local text, color = "Double-click to use or equip. Right-click for options. Drag to move.", ZM_DermaSkin.Palette.muted
        if current and CurTime() - current.at < 4 then
            text, color = current.text, current.ok and equippedColor or ZM_DermaSkin.Palette.redBright
        end
        draw.SimpleText(text, "ZM_InventorySmall", 0, height * 0.5, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 8, 12, 0)
    body.Paint = function() end
    frame.Body = body
    body.PerformLayout = function(panel)
        if panel.BuiltWidth ~= panel:GetWide() then
            panel.BuiltWidth = panel:GetWide()
            Inventory:Rebuild(frame)
        end
    end
    self:RequestSnapshot()
end

function Inventory:Open()
    self:OpenWindow("Frame", "INVENTORY", false)
end

function Inventory:OpenDen()
    self:OpenWindow("DenFrame", "DEN + INVENTORY", true)
end

hook.Add("ZM.InventoryUpdated", "ZM.Inventory.RefreshWindow", function()
    if IsValid(Inventory.Frame) then
        Inventory:Rebuild(Inventory.Frame)
    end
    if IsValid(Inventory.DenFrame) then
        Inventory:Rebuild(Inventory.DenFrame)
    end
end)
