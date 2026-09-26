// Client presentation for world loot spots: "?" markers, the search progress bar, the loot offer window, and result
// messages. The server rolls and owns every offer; this file only displays it and sends accept/decline with its token.
ZM_LootPopup = ZM_LootPopup or {}
local Popup = ZM_LootPopup

local markerRange = 1500
local gold = Color(255, 196, 64)
local messageDuration = 3

surface.CreateFont("ZM_LootMarker", { font = "Trebuchet MS", size = 26, weight = 900, antialias = true })
surface.CreateFont("ZM_LootTitle", { font = "Trebuchet MS", size = 22, weight = 900, antialias = true })
surface.CreateFont("ZM_LootLevel", { font = "Trebuchet MS", size = 15, weight = 700, antialias = true })

local thumbnailCache = {}
local function getThumbnail(name)
    if thumbnailCache[name] == nil then
        local path = "materials/items/" .. name .. ".png"
        thumbnailCache[name] = file.Exists(path, "GAME") and Material("items/" .. name .. ".png", "smooth") or false
    end
    return thumbnailCache[name] or nil
end

local function describeAttributes(offer)
    local lines = {}
    for name, score in SortedPairs(offer.attributes or {}) do
        table.insert(lines, name .. ": " .. score)
    end
    if #lines == 0 then
        table.insert(lines, "No attributes")
    end
    table.insert(lines, string.format("Value: $%.2f", tonumber(offer.value) or 0))
    return table.concat(lines, "\n")
end

local function respond(offer, accept)
    net.Start("ZM.LootOfferResponse")
        net.WriteString(offer.token or "")
        net.WriteBool(accept)
    net.SendToServer()
end

function Popup:Close()
    if IsValid(self.Frame) then
        self.Frame.Responded = true
        self.Frame:Remove()
    end
    self.Frame = nil
end

// Layout from the prototype: name (gold with "(MC)" for mastercrafts), level, thumbnail with attribute tooltip,
// and Accept / Decline docked to the bottom.
function Popup:Show(offer)
    self:Close()
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("LOOT")
    frame:SetSize(math.min(320, ScrW() - 40), math.min(340, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnClose = function(panel)
        if not panel.Responded then
            panel.Responded = true
            respond(offer, false)
        end
    end
    frame.OnRemove = function(panel)
        if Popup.Frame == panel then
            Popup.Frame = nil
        end
        if ZM_UI then ZM_UI:UnregisterTransient(panel) end
    end
    self.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local nameText = offer.name or offer.itemId or "Unknown item"
    if offer.mastercraft then
        nameText = nameText .. " (MC)"
    end
    if (tonumber(offer.count) or 1) > 1 then
        nameText = nameText .. " x" .. offer.count
    end

    local name = vgui.Create("DLabel", frame)
    name:Dock(TOP)
    name:DockMargin(8, 8, 8, 0)
    name:SetTall(26)
    name:SetFont("ZM_LootTitle")
    name:SetContentAlignment(5)
    name:SetText(nameText)
    name:SetTextColor(offer.mastercraft and gold or ZM_DermaSkin.Palette.text)

    local level = vgui.Create("DLabel", frame)
    level:Dock(TOP)
    level:DockMargin(8, 2, 8, 0)
    level:SetTall(18)
    level:SetFont("ZM_LootLevel")
    level:SetContentAlignment(5)
    level:SetText("Level " .. tostring(offer.level or 1))
    level:SetTextColor(ZM_DermaSkin.Palette.muted)

    local buttons = vgui.Create("DPanel", frame)
    buttons:Dock(BOTTOM)
    buttons:DockMargin(8, 8, 8, 8)
    buttons:SetTall(34)
    buttons.Paint = function() end

    local accept = vgui.Create("DButton", buttons)
    accept:Dock(LEFT)
    accept:SetText("ACCEPT")
    accept.DoClick = function()
        frame.Responded = true
        respond(offer, true)
        frame:Remove()
    end
    local decline = vgui.Create("DButton", buttons)
    decline:Dock(RIGHT)
    decline:SetText("DECLINE")
    decline.DoClick = function()
        frame.Responded = true
        respond(offer, false)
        frame:Remove()
    end
    buttons.PerformLayout = function(panel, width)
        accept:SetWide(math.floor((width - 8) * 0.5))
        decline:SetWide(math.floor((width - 8) * 0.5))
    end

    local thumbnail = vgui.Create("DPanel", frame)
    thumbnail:Dock(FILL)
    thumbnail:DockMargin(40, 12, 40, 4)
    thumbnail:SetTooltip(describeAttributes(offer))
    local material = getThumbnail(offer.thumbnail or offer.itemId or "")
    thumbnail.Paint = function(panel, width, height)
        local size = math.min(width, height)
        local x, y = math.floor((width - size) * 0.5), math.floor((height - size) * 0.5)
        surface.SetDrawColor(ZM_DermaSkin.Palette.raised)
        surface.DrawRect(x, y, size, size)
        surface.SetDrawColor(offer.mastercraft and gold or ZM_DermaSkin.Palette.border)
        surface.DrawOutlinedRect(x, y, size, size, 2)
        if material then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(material)
            surface.DrawTexturedRect(x + 8, y + 8, size - 16, size - 16)
        else
            draw.SimpleText("?", "ZM_LootMarker", width * 0.5, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

net.Receive("ZM.LootOffer", function()
    local offer = util.JSONToTable(net.ReadString())
    Popup.Search = nil
    if type(offer) == "table" and type(offer.token) == "string" then
        Popup:Show(offer)
    end
end)

net.Receive("ZM.LootSearch", function()
    local started = net.ReadBool()
    local duration = net.ReadFloat()
    Popup.Search = started and { startedAt = CurTime(), duration = math.max(duration, 0.01) } or nil
end)

net.Receive("ZM.LootOfferResult", function()
    local ok = net.ReadBool()
    local message = net.ReadString()
    if not ok then
        Popup:Close()
    end
    if message ~= "" then
        Popup.Message = { text = message, ok = ok, expiresAt = CurTime() + messageDuration }
    end
end)

hook.Add("HUDPaint", "ZM.LootPopup.Markers", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then
        return
    end
    local origin = ply:GetPos()
    for _, entity in ipairs(ents.FindInSphere(origin, markerRange)) do
        if entity:GetNWBool("ZM_LootSpot", false) then
            local top = entity:WorldSpaceCenter() + Vector(0, 0, entity:OBBMaxs().z - entity:OBBCenter().z + 12)
            local screen = top:ToScreen()
            if screen.visible then
                local pulse = 200 + math.sin(CurTime() * 4) * 55
            local declined = entity:GetNWString("ZM_LootSpotState", "") == "declined"
            local color = declined and Color(160, 160, 160, 255) or Color(255, 220, 90, pulse)
            draw.SimpleTextOutlined("?", "ZM_LootMarker", screen.x, screen.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 200))
            end
        end
    end

    local search = Popup.Search
    if search and ply:Alive() then
        local progress = math.Clamp((CurTime() - search.startedAt) / search.duration, 0, 1)
        local anchorX, anchorY = ScrW() * 0.5, ScrH() * 0.5
        if ZM_GetPlayerOverheadScreenPos then
            anchorX, anchorY = ZM_GetPlayerOverheadScreenPos(ply)
        end
        local width, height = 90, 7
        local x, y = math.floor(anchorX - width * 0.5), math.floor(anchorY - 24)
        surface.SetDrawColor(20, 20, 20, 230)
        surface.DrawRect(x, y, width, height)
        surface.SetDrawColor(255, 205, 80, 255)
        surface.DrawRect(x, y, math.floor(width * progress), height)
        draw.SimpleTextOutlined("Searching...", "DermaDefaultBold", anchorX, y - 9, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
    end

    local message = Popup.Message
    if message then
        if CurTime() >= message.expiresAt then
            Popup.Message = nil
        else
            draw.SimpleTextOutlined(message.text, "ZM_LootLevel", ScrW() * 0.5, ScrH() * 0.7, message.ok and Color(120, 230, 140) or Color(255, 150, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
        end
    end
end)
