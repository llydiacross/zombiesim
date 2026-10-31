// Offline panel fixtures model layout state and text, not Derma painting or mouse dispatch.
return function(harness)
    local state = { missingIcon = nil, errors = {} }
    local methods = {}
    function methods:Dock(value) self.dock = value end
    function methods:DockMargin(left, top, right, bottom) self.margin = { left, top, right, bottom } end
    function methods:SetSize(width, height)
        local changed = self.width ~= width or self.height ~= height
        self.width, self.height = width, height
        if changed and self.OnSizeChanged then self:OnSizeChanged(width, height) end
    end
    function methods:SetTall(value) self:SetSize(self.width, value) end
    function methods:SetWide(value) self:SetSize(value, self.height) end
    function methods:SetPos(x, y) self.x, self.y = x, y end
    function methods:GetWide() return self.width end
    function methods:GetTall() return self.height end
    function methods:GetX() return self.x end
    function methods:GetY() return self.y end
    function methods:GetDockMargin()
        local margin = self.margin or { 0, 0, 0, 0 }
        return margin[1], margin[2], margin[3], margin[4]
    end
    function methods:InvalidateLayout(now)
        self.layoutInvalidations = (self.layoutInvalidations or 0) + 1
        if not now then return end
        if self.PerformLayout then self:PerformLayout(self.width, self.height) end
        local y = 0
        for _, child in ipairs(self.children) do
            if child.dock == 1 then
                local left, top, right, bottom = child:GetDockMargin()
                child:SetPos(left, y + top)
                child:SetSize(math.max(0, self.width - left - right), child:GetTall())
                y = y + top + child:GetTall() + bottom
            end
        end
    end
    function methods:SetText(value) self.text = value end
    function methods:GetText() return self.text end
    function methods:SetFont(value) self.font = value end
    function methods:SetTextColor(value) self.textColor = value end
    function methods:SetWrap(value) self.wrap = value end
    function methods:SetAutoStretchVertical(value) self.autoStretch = value end
    function methods:SizeToContentsY()
        local lineWidth = math.max(1, math.floor(self.width / 7))
        local count = 0
        for line in (self.text .. "\n"):gmatch("(.-)\n") do
            count = count + math.max(1, math.ceil(#line / lineWidth))
        end
        self:SetTall(math.max(16, count * 16))
    end
    function methods:SetContentAlignment(value) self.alignment = value end
    function methods:SetMouseInputEnabled(value) self.mouse = value end
    function methods:SetTooltip(value) self.tooltip = value end
    function methods:SetEnabled(value) self.enabled = value end
    function methods:IsEnabled() return self.enabled end
    function methods:SetVisible(value) self.visible = value end
    function methods:IsHovered() return false end
    function methods:HasFocus() return false end
    function methods:Remove()
        self.removed = true
        for _, child in ipairs(self.children) do child:Remove() end
    end
    local vgui = {}
    function vgui.Create(kind, parent)
        assert(kind == "DPanel" or kind == "DScrollPanel" or kind == "DLabel" or kind == "DButton",
            "unsupported fixture panel " .. tostring(kind))
        local panel = setmetatable({ kind = kind, parent = parent, children = {}, width = 64, height = 64,
            x = 0, y = 0, text = "", enabled = true }, { __index = methods })
        if parent then parent.children[#parent.children + 1] = panel end
        return panel
    end
    local professions = {
        Civilian = { id = "Civilian", name = "Civilian", description = "No trade.",
            statBonuses = {}, services = {}, deliveries = {} },
        Doctor = { id = "Doctor", name = "Doctor", description = "Treats the wounded.",
            statBonuses = { Medicine = 3, Intelligence = 1 }, services = { treat = true, implant = true },
            deliveries = { {}, {} } },
        ArmySoldier = { id = "ArmySoldier", name = "Army Soldier", description = "Military training.",
            statBonuses = { MachineGuns = 2, Endurance = 1 }, services = {}, deliveries = {} }
    }
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, pcall = pcall, tostring = tostring,
        math = math, string = string, table = table, vgui = vgui, ZM_TestHarness = harness,
        ZM_DermaSkin = { Palette = { panel = {}, raised = {}, black = {}, border = {}, redDark = {},
            redBright = {}, bonus = {}, text = {}, muted = {} } },
        ZM_CharacterRules = { Attributes = { "Strength", "Agility", "Intelligence", "Endurance", "MachineGuns",
            "Pistols", "Shotguns", "Rifles", "Explosives", "WeaponCrafting", "ArmorCrafting", "Medicine",
            "Farming", "WeaponRepairing", "ArmorRepairing", "Mechanics" } },
        TOP = 1, BOTTOM = 2, RIGHT = 3, FILL = 4, NODOCK = 0,
        TEXT_ALIGN_LEFT = 0, TEXT_ALIGN_CENTER = 1, TEXT_ALIGN_RIGHT = 2,
        ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
        IsValid = function(panel) return panel ~= nil and not panel.removed end
    }
    env.Material = function(path, flags)
        assert(flags == "smooth")
        local texture = { Width = function() return 16 end, Height = function() return 16 end }
        return { IsError = function() return path == state.missingIcon end, GetTexture = function() return texture end }
    end
    env.surface = {
        SetMaterial = function(material) state.lastMaterial = material end,
        SetDrawColor = function(...) state.lastColor = { ... } end,
        DrawRect = function(...) state.lastRect = { ... } end,
        DrawOutlinedRect = function(...) state.lastOutline = { ... } end,
        DrawTexturedRect = function(...) state.lastTexture = { ... } end
    }
    env.draw = { SimpleText = function(...) state.lastText = { ... } end }
    env.ZM_Professions = {}
    function env.ZM_Professions:GetIds()
        local ids = {}
        for id in pairs(professions) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    function env.ZM_Professions:GetKnown(id) return professions[id] end
    return env, state
end
