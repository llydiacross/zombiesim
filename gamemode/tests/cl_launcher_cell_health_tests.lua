return function(loadChunk, loadTools)
    local suite = ZM_TestHarness.NewSuite()

    suite:Add("launcher sidebar exposes Cell Health only to preview admins", function(check)
        local state = { map = "zn_preview_start", profile = "preview", admin = true, buttons = {}, opens = 0 }
        local player = { valid = true, IsAdmin = function() return state.admin end }
        local host = { valid = true }
        local env = {
            type = type, tostring = tostring, string = string, table = table, ipairs = ipairs, pairs = pairs,
            ZM_DermaSkin = { Palette = { border = {} } }, ZM_World = { ActiveProfile = "preview" },
            game = { GetMap = function() return state.map end },
            IsValid = function(value) return type(value) == "table" and value.valid ~= false end,
            LocalPlayer = function() return player end,
            ZM_Wardrobe = { IsAvailable = function() return true end },
            ZM_CellHealth = { Open = function(_, parent) state.opens = state.opens + 1; state.parent = parent end },
            vgui = { Create = function()
                return { Dock = function() end, DockMargin = function() end, SetTall = function() end }
            end },
            concommand = { Add = function() end, Remove = function() end },
            TOP = 1
        }
        local chunk = loadTools()
        setfenv(chunk, env)
        chunk()
        local tools = env.ZM_LauncherTools
        tools.Host = host
        local function build()
            state.buttons = {}
            tools:BuildMenu({}, function(text, action)
                local button = { text = text, enabled = true, DoClick = action }
                function button:SetEnabled(value) self.enabled = value end
                function button:IsEnabled() return self.enabled end
                function button:SetTooltip(value) self.tooltip = value end
                state.buttons[text] = button
                return button
            end, function() end, function() state.refreshes = (state.refreshes or 0) + 1 end)
        end
        build()
        check(state.buttons["CELL HEALTH"] and state.buttons["CELL HEALTH"].enabled,
            "preview admin sees an enabled entry")
        state.buttons["CELL HEALTH"]:DoClick()
        check(state.opens == 1 and state.parent == host and state.refreshes == 1,
            "the entry opens the existing manager with the launcher as parent")
        state.admin = false
        build()
        check(not state.buttons["CELL HEALTH"].enabled and state.buttons["CELL HEALTH"].tooltip:find("admin", 1, true),
            "non-admins see a disabled entry with the reason")
        state.admin, state.map, env.ZM_World.ActiveProfile = true, "zn_city_start", "city"
        build()
        check(not state.buttons["CELL HEALTH"].enabled and not tools:GetCapabilities().cellHealth,
            "the city launcher cannot open preview Cell Health")
    end)

    suite:Add("Cell Health returns focus without starting maintenance", function(check)
        local state = { admin = true, loaded = true, errors = {}, refreshes = 0, requests = 0 }
        local player = { valid = true, IsAdmin = function() return state.admin end }
        local host = { valid = true, visible = true, popups = 0 }
        function host:IsVisible() return self.visible end
        function host:MakePopup() self.popups = self.popups + 1 end
        local env = {
            type = type, tostring = tostring, string = string, table = table, ipairs = ipairs, pairs = pairs,
            math = math, Color = function(r, g, b) return { r = r, g = g, b = b } end,
            ZM_DermaSkin = { Palette = {} }, ZM_LauncherMenu = { Frame = host, Page = "tools" },
            ZM_World = {
                ActiveProfile = "preview", IsLoaded = function() return state.loaded end,
                GetLoadError = function() return "not loaded" end
            },
            LocalPlayer = function() return player end,
            IsValid = function(value) return type(value) == "table" and value.valid ~= false end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            include = function(path) assert(path == "sh_cell_health_contract.lua"); return function() return {} end end,
            vgui = { Create = function(kind)
                assert(kind == "DFrame")
                local frame = { valid = true }
                function frame:SetSkin(value) self.skin = value end
                function frame:SetSize() end
                function frame:Center() end
                function frame:SetTitle(value) self.title = value end
                function frame:SetDeleteOnClose(value) self.deleteOnClose = value end
                function frame:MakePopup() self.popup = true end
                function frame:Close() self.valid = false; if self.OnRemove then self:OnRemove() end end
                return frame
            end },
            ScrW = function() return 1280 end, ScrH = function() return 720 end, KEY_ESCAPE = 70,
            concommand = { Add = function() end, Remove = function() end },
            net = { Receive = function() end }
        }
        local chunk = loadChunk("cl_cell_health.lua")
        setfenv(chunk, env)
        chunk()
        local manager = env.ZM_CellHealth
        manager.Refresh = function() state.refreshes = state.refreshes + 1 end
        manager.RequestCubemapStatus = function() state.requests = state.requests + 1 end
        check(manager:Open(host) and manager.Frame and manager.Frame.skin == "ZombieSim"
            and state.refreshes == 1 and state.requests == 1, "the preview manager opens and requests read-only status")
        check(not manager.BatchSelection.navmesh and not manager.BatchSelection.photos
            and not manager.BatchSelection.cubemaps, "all batch categories remain unchecked")
        manager.Frame:OnKeyCodePressed(env.KEY_ESCAPE)
        check(not manager.Frame and host.popups == 1, "Escape closes the manager and restores the Tools host")
        check(manager:Open(host), "manager can reopen")
        env.ZM_LauncherMenu.Page = "menu"
        manager.Frame:Think()
        check(not manager.Frame and host.popups == 1, "leaving Tools closes the child without stealing focus")
        state.admin = false
        check(not manager:Open(host) and #state.errors > 0, "non-admin opens are rejected")
        state.admin, env.ZM_World.ActiveProfile = true, "city"
        check(not manager:Open(host), "city profile opens are rejected")
    end)
    return suite
end
