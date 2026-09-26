// Client inventory: mirrors the server snapshot and draws the backpack/stash window. Every change is a request
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
        Inventory:Open()
    elseif class == "zn_crafting_station" and ZM_Crafting and ZM_Crafting.Open then
        ZM_Crafting:Open()
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

local thumbnailCache = {}
local function getThumbnail(name)
    if thumbnailCache[name] == nil then
        thumbnailCache[name] = file.Exists("materials/items/" .. name .. ".png", "GAME") and Material("items/" .. name .. ".png", "smooth") or false
    end
    return thumbnailCache[name] or nil
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

local function describe(instance)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    if not definition then
        return "Unknown item (" .. tostring(instance.itemId) .. ")\nThis item no longer exists and is kept unchanged."
    end
    local lines = { ZM_Items:GetDisplayName(instance) .. (instance.count > 1 and (" x" .. instance.count) or ""), "Level " .. instance.level }
    for name, score in SortedPairs(instance.attributes or {}) do
        table.insert(lines, "  " .. name .. ": " .. score)
    end
    local canUse, reason = ZM_Items:CanUse(LocalPlayer(), instance.itemId)
    if not canUse then
        table.insert(lines, reason)
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

local function openContextMenu(instance, container)
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
    end
    if Inventory.Snapshot.canAccessStash then
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

local function paintTile(instance, width, height)
    local definition = ZM_Items:GetDefinition(instance.itemId)
    local palette = ZM_DermaSkin.Palette
    surface.SetDrawColor(palette.raised)
    surface.DrawRect(0, 0, width, height)
    local material = definition and getThumbnail(definition.thumbnail)
    if material then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(material)
        surface.DrawTexturedRect(6, 6, width - 12, height - 12)
    else
        local label = definition and abbreviate(definition.name) or "?"
        draw.SimpleText(label, "ZM_InventoryTile", width * 0.5, height * 0.5, definition and palette.text or palette.redBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    draw.SimpleText("L" .. instance.level, "ZM_InventorySmall", 4, 2, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    if instance.count > 1 then
        draw.SimpleTextOutlined("x" .. instance.count, "ZM_InventorySmall", width - 4, height - 2, palette.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
    end
    if Inventory:IsEquipped(instance.instanceId) then
        draw.SimpleText("E", "ZM_InventorySmall", width - 4, 2, equippedColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end
    surface.SetDrawColor(instance.mastercraft and gold or palette.border)
    surface.DrawOutlinedRect(0, 0, width, height, instance.mastercraft and 2 or 1)
end

local function buildContainer(parent, container, locked)
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
            tile.Paint = function(_, width, height) paintTile(instance, width, height) end
            tile.DoDoubleClick = function()
                if container == "backpack" then
                    primaryAction(instance)
                end
            end
            tile.DoRightClick = function() openContextMenu(instance, container) end
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

function Inventory:Rebuild()
    local frame = self.Frame
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
    local backpackColumn = vgui.Create("DPanel", frame.Body)
    backpackColumn:Dock(FILL)
    backpackColumn:SetWide(frame.Body:GetWide())
    backpackColumn.Paint = function() end
    heading(backpackColumn, "BACKPACK", string.format("%d / %d  -  lost on death", #snapshot.backpack, snapshot.capacity.backpack or 0), ZM_DermaSkin.Palette.redBright)
    local backpackScroll = vgui.Create("DScrollPanel", backpackColumn)
    backpackScroll:Dock(FILL)
    backpackScroll:DockMargin(0, 4, 0, 0)
    backpackScroll:SetWide(columnWidth)
    buildContainer(backpackScroll, "backpack", false)

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
        draw.SimpleText("$" .. string.Comma(snapshot.cash or 0), "ZM_InventoryHeading", 4, 19, gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("+($" .. string.Comma(snapshot.bundleCash or 0) .. ") from bundles", "ZM_InventorySmall", 4, 39, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("+($" .. string.Comma(snapshot.bankCash or 0) .. ") stored in banks", "ZM_InventorySmall", 4, 51, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
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
            tile.Paint = function(_, width, height) paintTile(instance, width, height) end
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

function Inventory:Open()
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        self:RequestSnapshot()
        return
    end
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("INVENTORY")
    frame:SetSize(math.min(860, ScrW() - 40), math.min(560, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if Inventory.Frame == frame then Inventory.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    self.Frame = frame
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
            Inventory:Rebuild()
        end
    end
    self:RequestSnapshot()
end

hook.Add("ZM.InventoryUpdated", "ZM.Inventory.RefreshWindow", function()
    if IsValid(Inventory.Frame) then
        Inventory:Rebuild()
    end
end)
