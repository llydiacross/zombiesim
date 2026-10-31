return function(cards)
    local state = { now = 1, frame = 1, receivers = {}, requests = {}, commands = {}, panels = {},
        errors = {}, draws = {}, missingMaterials = {}, registered = {}, json = {} }
    local env = {
        type = type, tostring = tostring, tonumber = tonumber, ipairs = ipairs, pairs = pairs, next = next, os = os,
        string = string, table = table, math = math, ZM_CallingCards = cards,
        TOP = 1, BOTTOM = 2, LEFT = 3, RIGHT = 4, FILL = 5, KEY_ESCAPE = 70,
        TEXT_ALIGN_LEFT = 0, TEXT_ALIGN_CENTER = 1, TEXT_ALIGN_BOTTOM = 2
    }
    env.IsValid = function(value) return type(value) == "table" and value.valid ~= false end
    env.ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end
    env.print = function() end
    env.ScrW = function() return 1280 end
    env.ScrH = function() return 720 end
    env.RealTime = function() return state.now end
    env.FrameNumber = function() return state.frame end
    env.ZM_DermaSkin = { Palette = { black = {}, raised = {}, border = {}, text = {}, muted = {}, redBright = {} } }
    env.ZM_StaticData = { GetRegistry = function() return state.registry end }
    env.ZM_UI = {
        RegisterTransient = function(_, panel) state.registered[panel] = true end,
        UnregisterTransient = function(_, panel) state.registered[panel] = nil end
    }
    env.ZM_TradingUI = {
        State = { available = true, credits = 200 },
        SendCallingCardPurchase = function(_, id, price)
            if state.purchaseFailure then return nil, state.purchaseFailure end
            state.purchases = state.purchases or {}
            local requestId = "purchase_" .. (#state.purchases + 1)
            state.purchases[#state.purchases + 1] = { id = id, price = price, requestId = requestId }
            return requestId
        end
    }
    env.util = {
        TableToJSON = function(value)
            local key = "request-" .. (#state.json + 1)
            state.json[#state.json + 1] = value
            return key
        end
    }
    env.net = {
        Receive = function(name, callback) state.receivers[name] = callback end,
        Start = function(name) state.current = { name = name } end,
        WriteString = function(value) state.current.encoded = value end,
        SendToServer = function()
            local index = tonumber(string.match(state.current.encoded, "^request%-(%d+)$"))
            state.current.request = state.json[index]
            state.requests[#state.requests + 1] = state.current
            state.current = nil
        end,
        ReadUInt = function(bits)
            local value = table.remove(state.read, 1)
            assert(value.kind == "uint" and value.bits == bits, "unexpected net integer")
            return value.value
        end,
        ReadBool = function()
            local value = table.remove(state.read, 1)
            assert(value.kind == "bool", "unexpected net boolean")
            return value.value
        end,
        ReadString = function()
            local value = table.remove(state.read, 1)
            assert(value.kind == "string", "unexpected net string")
            return value.value
        end
    }
    function state:Deliver(packet)
        self.read = {
            { kind = "uint", bits = 32, value = packet.serial },
            { kind = "uint", bits = 16, value = packet.part },
            { kind = "uint", bits = 16, value = packet.total },
            { kind = "bool", value = packet.ok },
            { kind = "string", value = packet.message },
            { kind = "string", value = packet.requestId },
            { kind = "string", value = packet.background },
            { kind = "string", value = packet.detail },
            { kind = "uint", bits = 8, value = #packet.ids }
        }
        for _, id in ipairs(packet.ids) do self.read[#self.read + 1] = { kind = "string", value = id } end
        self.receivers["ZM.CallingCardState"]()
        assert(#self.read == 0, "response was not consumed")
    end
    env.concommand = { Add = function(name, callback) state.commands[name] = callback end }
    env.Material = function(path)
        return {
            path = path,
            IsError = function() return state.missingMaterials[path] == true end,
            GetShader = function() return "UnlitGeneric" end,
            GetTexture = function()
                return { Width = function() return 750 end, Height = function() return 125 end }
            end
        }
    end
    env.surface = {
        SetMaterial = function(material) state.material = material end,
        SetDrawColor = function(r, g, b, a) state.alpha = a end,
        DrawTexturedRect = function(x, y, width, height)
            state.draws[#state.draws + 1] = { path = state.material.path, alpha = state.alpha,
                x = x, y = y, width = width, height = height }
        end,
        DrawRect = function() end,
        DrawOutlinedRect = function() end
    }
    env.draw = { SimpleText = function() end }

    local panel = {}
    panel.__index = panel
    function panel:SetSkin(value) self.skin = value end
    function panel:SetTitle(value) self.title = value end
    function panel:SetSize(width, height) self.width, self.height = width, height end
    function panel:GetWide() return self.width or 0 end
    function panel:GetTall() return self.height or 0 end
    function panel:SetWide(width) self.width = width end
    function panel:SetTall(height) self.height = height end
    function panel:SetPos(x, y) self.x, self.y = x, y end
    function panel:GetParent() return self.parent end
    function panel:Dock(value) self.dock = value end
    function panel:DockMargin(left, top, right, bottom) self.margin = { left, top, right, bottom } end
    function panel:SetText(value) self.text = value end
    function panel:SetFont(value) self.font = value end
    function panel:SetTextColor(value) self.textColor = value end
    function panel:SetWrap(value) self.wrap = value end
    function panel:SetContentAlignment(value) self.align = value end
    function panel:SetEnabled(value) assert(type(value) == "boolean") self.enabled = value end
    function panel:MakePopup() self.popup = (self.popup or 0) + 1 end
    function panel:Clear()
        for _, child in ipairs(self.children) do child:Remove() end
        self.children = {}
    end
    function panel:Remove()
        if self.valid == false then return end
        self.valid = false
        self:Clear()
        if self.OnRemove then self:OnRemove() end
    end
    function panel:Close()
        if self.OnClose then self:OnClose() end
        self:Remove()
    end
    env.vgui = {
        Create = function(class, parent)
            local result = setmetatable({ class = class, parent = parent, children = {}, valid = true }, panel)
            state.panels[#state.panels + 1] = result
            if parent then parent.children[#parent.children + 1] = result end
            return result
        end
    }
    env.Derma_Query = function(text, title, first, confirm, second, cancel)
        local dialog = env.vgui.Create("DFrame")
        dialog.text, dialog.title, dialog.confirm, dialog.cancel = text, title, confirm, cancel
        state.dialog = dialog
        return dialog
    end
    function state:Row(view, id)
        for _, row in ipairs(view.List.children) do
            if row.CardId == id then return row, row.children[1] end
        end
    end
    return env, state
end
