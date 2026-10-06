// Shared changelog renderer: Content Status, the in-game Changelog window and the launcher Options side panel.
ZM_Changelog = ZM_Changelog or {}
local Changelog = ZM_Changelog
local colours = ZM_DermaSkin.Palette
local good, warn = Color(110, 200, 120), Color(230, 180, 70)

surface.CreateFont("ZM_ToolsVersion", { font = "Trebuchet MS", size = 30, weight = 900, antialias = true })
surface.CreateFont("ZM_ToolsHeading", { font = "Trebuchet MS", size = 19, weight = 900, antialias = true })
surface.CreateFont("ZM_ToolsSubheading", { font = "Trebuchet MS", size = 14, weight = 900, antialias = true })
surface.CreateFont("ZM_ToolsBody", { font = "Trebuchet MS", size = 15, weight = 600, antialias = true })

function Changelog:Paragraph(scroll, text, colour, indent)
    local panel = scroll:Add("DLabel")
    panel:Dock(TOP)
    panel:DockMargin(indent or 24, 2, 12, 2)
    panel:SetFont("ZM_ToolsBody")
    panel:SetTextColor(colour or colours.text)
    panel:SetWrap(true)
    panel:SetAutoStretchVertical(true)
    panel:SetText(text)
    return panel
end

function Changelog:AddBanner(scroll, info)
    info = info or {}
    local banner = scroll:Add("DPanel")
    banner:Dock(TOP)
    banner:DockMargin(12, 10, 12, 4)
    banner:SetTall(92)
    banner.Paint = function(_, width, height)
        surface.SetDrawColor(0, 0, 0, 170)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(colours.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        draw.SimpleText(string.upper((info.product or GAMEMODE.Name or "Z-Nation") .. "  " .. (info.stage or "") .. " " .. (info.version or "?")),
            "ZM_ToolsVersion", 16, 12, colours.text)
        local released = info.status == "released"
        local status = string.upper(info.status or "unknown")
        surface.SetFont("ZM_ToolsBody")
        local statusWidth = surface.GetTextSize(status) + 16
        draw.RoundedBox(4, 16, 52, statusWidth, 24, released and Color(40, 90, 50) or Color(110, 80, 20))
        draw.SimpleText(status, "ZM_ToolsBody", 24, 64, released and good or warn, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(info.currentPhase or "", "ZM_ToolsBody", 28 + statusWidth, 64, colours.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return banner
end

// Appends the legend and every entry: underlined version titles, then ADDED / CHANGED / REMOVED groups.
function Changelog:Populate(scroll, info, entries)
    info = info or {}
    entries = entries or {}
    local markColours = { ["+"] = good, ["-"] = colours.redBright, ["?"] = warn }
    local markOrder = { ["+"] = 1, ["?"] = 2, ["-"] = 3 }
    local markByRank, groupNames = { "+", "?", "-" }, { "ADDED", "CHANGED", "REMOVED" }
    self:Paragraph(scroll, "+ added    ? changed, fixed or in progress    - removed", colours.muted)
    if #entries == 0 then self:Paragraph(scroll, "No changelog loaded.", warn) end
    for _, entry in ipairs(entries) do
        local current = info.version == entry.version
        local title = scroll:Add("DPanel")
        title:Dock(TOP)
        title:DockMargin(24, 22, 12, 4)
        title:SetTall(30)
        title.Paint = function(_, width, height)
            local accent = current and colours.redBright or colours.text
            draw.SimpleText(tostring(entry.version) .. "  " .. tostring(entry.title or ""), "ZM_ToolsHeading", 0, height / 2 - 2,
                accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.upper(tostring(entry.status or "")) .. "  " .. tostring(entry.date or ""), "ZM_ToolsBody",
                width, height / 2 - 2, entry.status == "released" and colours.muted or warn, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(current and colours.redBright or colours.border)
            surface.DrawRect(0, height - 2, width, 2)
        end
        if entry.summary then self:Paragraph(scroll, entry.summary, colours.muted) end
        local ordered = {}
        for index, line in ipairs(istable(entry.highlights) and entry.highlights or {}) do
            local mark = string.match(tostring(line), "^([%+%-%?])%s") or "+"
            ordered[#ordered + 1] = { line = line, rank = markOrder[mark], index = index }
        end
        table.sort(ordered, function(a, b) return a.rank ~= b.rank and a.rank < b.rank or a.rank == b.rank and a.index < b.index end)
        local group
        for _, item in ipairs(ordered) do
            local line = item.line
            if item.rank ~= group then
                group = item.rank
                local groupName, groupColour = groupNames[group], markColours[markByRank[group]]
                local sub = scroll:Add("DPanel")
                sub:Dock(TOP)
                sub:DockMargin(36, 8, 12, 3)
                sub:SetTall(20)
                sub.Paint = function(_, width, height)
                    surface.SetFont("ZM_ToolsSubheading")
                    local textWidth = surface.GetTextSize(groupName)
                    draw.SimpleText(groupName, "ZM_ToolsSubheading", 0, 0, groupColour)
                    surface.SetDrawColor(groupColour)
                    surface.DrawRect(0, height - 2, textWidth, 2)
                    surface.SetDrawColor(groupColour.r, groupColour.g, groupColour.b, 40)
                    surface.DrawRect(textWidth + 6, height - 1, width - textWidth - 6, 1)
                end
            end
            local mark, text = string.match(tostring(line), "^([%+%-%?])%s+(.+)$")
            mark, text = mark or "+", text or tostring(line)
            local panel = scroll:Add("DPanel")
            panel:Dock(TOP)
            panel:DockMargin(44, 1, 12, 1)
            panel.Paint = nil
            local marker = vgui.Create("DLabel", panel)
            marker:Dock(LEFT)
            marker:SetWide(18)
            marker:SetContentAlignment(7)
            marker:SetFont("ZM_ToolsHeading")
            marker:SetTextColor(markColours[mark])
            marker:SetText(mark)
            local label = vgui.Create("DLabel", panel)
            label:SetFont("ZM_ToolsBody")
            label:SetTextColor(colours.text)
            label:SetWrap(true)
            label:SetText(text)
            panel.PerformLayout = function(_, width)
                label:SetPos(18, 0)
                label:SetWide(math.max(40, width - 18))
                label:SizeToContentsY()
                local height = math.max(20, label:GetTall())
                if panel:GetTall() ~= height then panel:SetTall(height) end
            end
        end
    end
end

// Fills parent with a scrolling version banner and the full changelog.
function Changelog:BuildView(parent)
    local Version = ZM_Version
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(4, 4, 4, 4)
    self:AddBanner(scroll, Version and Version.Info)
    if Version and (Version.Error or Version.ChangelogError) then
        self:Paragraph(scroll, "! " .. tostring(Version.ChangelogError or Version.Error), colours.redBright)
    end
    self:Populate(scroll, Version and Version.Info, Version and Version.Entries)
    return scroll
end

// In-game window. Options (or any parent window) stays open underneath and regains focus on close.
function Changelog:Open(parent)
    if IsValid(self.Frame) then self.Frame:MakePopup() return self.Frame end
    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSkin("ZombieSim")
    frame:SetTitle("CHANGELOG")
    frame:SetSize(math.min(860, ScrW() - 32), math.min(760, ScrH() - 32))
    frame:Center()
    frame:SetDeleteOnClose(true)
    frame:MakePopup()
    if ZM_UI then ZM_UI:RegisterTransient(frame) end
    frame.OnRemove = function()
        if self.Frame == frame then self.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    frame.OnClose = function()
        if not IsValid(parent) then return end
        local window = parent
        while IsValid(window:GetParent()) and window:GetParent() ~= vgui.GetWorldPanel() do
            window = window:GetParent()
        end
        window:MakePopup()
    end
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then frame:Close() end
    end
    frame.Think = function()
        if parent ~= nil and not IsValid(parent) then frame:Remove() end
    end
    self:BuildView(frame)
    return frame
end

// Launcher Options: the changelog uses the right side of the launcher frame, like the Tools views.
function Changelog:IsPanelOpen()
    return IsValid(self.Panel)
end

function Changelog:OpenPanel(host, menuWidth)
    if not IsValid(host) then return end
    if IsValid(self.Panel) then return self.Panel end
    self.PanelHost, self.PanelMenuWidth = host, menuWidth or host:GetWide()
    host:SetWide(ScrW())
    local body = vgui.Create("DPanel", host)
    self.Panel = body
    body:Dock(RIGHT)
    body:DockMargin(0, 48, 24, 20)
    body:SetWide(math.max(320, ScrW() - self.PanelMenuWidth - 24))
    body.Paint = function(_, width, height)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(colours.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end
    body.OnRemove = function()
        if self.Panel == body then self.Panel = nil end
    end
    self:BuildView(body)
    return body
end

function Changelog:ClosePanel()
    if not IsValid(self.Panel) then self.Panel = nil return end
    self.Panel:Remove()
    self.Panel = nil
    if IsValid(self.PanelHost) and self.PanelMenuWidth then self.PanelHost:SetWide(self.PanelMenuWidth) end
end

function Changelog:TogglePanel(host, menuWidth)
    if IsValid(self.Panel) then self:ClosePanel() return false end
    return self:OpenPanel(host, menuWidth) ~= nil
end
