return function(gizmo, contract)
    local state = { hooks = {}, receivers = {}, commands = {}, panels = {}, models = {},
        json = {}, nextJson = 0, messages = {}, requests = {}, map = "gm_flatgrass", now = 0,
        modelFolders = { ["models/props_c17/"] = { files = { "oildrum001.mdl" }, directories = {} } },
        compassLabels = {}, mouseX = 50, mouseY = 50, renderLines = {}, renderBoxes = {} }
    local vectorMeta = {}
    vectorMeta.__index = vectorMeta
    function vectorMeta.__add(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vectorMeta) end
    function vectorMeta.__sub(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta) end
    function vectorMeta.__mul(a, b) return setmetatable({ x = a.x * b, y = a.y * b, z = a.z * b }, vectorMeta) end
    function vectorMeta:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
    function vectorMeta:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
    function vectorMeta:ToScreen() return { x = self.x, y = self.y, visible = true } end
    local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
    local function clone(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for key, entry in pairs(value) do copy[key] = clone(entry) end
        return copy
    end
    local env = {
        type = type, tostring = tostring, tonumber = tonumber, string = {}, table = table,
        ipairs = ipairs, pairs = pairs, math = {}, KEY_ESCAPE = 70, MOUSE_LEFT = 1, MOUSE_RIGHT = 2, MOUSE_MIDDLE = 3,
        TOP = 1, LEFT = 2, RIGHT = 3, FILL = 4, RENDERGROUP_OTHER = 0,
        color_white = { r = 255, g = 255, b = 255 }, BOTTOM = 5, TEXT_ALIGN_CENTER = 1
    }
    for key, value in pairs(string) do env.string[key] = value end
    env.string.Trim = function(value) return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")) end
    for key, value in pairs(math) do env.math[key] = value end
    env.math.Clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
    env.Vector = vector
    env.Angle = function(p, y, r)
        local pitch, yaw, roll = math.rad(p), math.rad(y), math.rad(r)
        local sp, cp, sy, cy, sr, cr = math.sin(pitch), math.cos(pitch),
            math.sin(yaw), math.cos(yaw), math.sin(roll), math.cos(roll)
        return {
            p = p, y = y, r = r,
            Forward = function() return vector(cp * cy, cp * sy, -sp) end,
            Right = function() return vector(-sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp) end,
            Up = function() return vector(cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp) end
        }
    end
    env.Matrix = function()
        return { Scale = function(self, value) self.scale = value end }
    end
    env.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env.IsValid = function(value) return type(value) == "table" and value.valid ~= false end
    env.include = function(path)
        if path == "prefabs/sh_gizmo.lua" then return gizmo end
        assert(path == "prefabs/sh_contract.lua")
        return contract
    end
    env.ErrorNoHalt = function(message) state.messages[#state.messages + 1] = message end
    env.Derma_Message = function(message) state.messages[#state.messages + 1] = message end
    env.Derma_Query = function(...) state.query = { ... } end
    env.Derma_StringRequest = function(...) state.stringRequest = { ... } end
    env.ScrW = function() return 1920 end
    env.ScrH = function() return 1080 end
    env.RealTime = function() return state.now end
    env.SysTime = function() return state.now end
    env.game = { GetMap = function() return state.map end }
    state.atmosphereProfiles = {
        { id = "outskirts", fog = { start = 800, ["end"] = 3000, maxDensity = 0.65, color = { 186, 208, 224 } } },
        { id = "inner_city", fog = { start = 350, ["end"] = 1450, maxDensity = 0.82, color = { 122, 132, 141 } } }
    }
    env.ZM_World = {
        GetData = function() return { atmosphereProfiles = state.atmosphereProfiles } end,
        GetAtmosphereProfileByIndex = function(_, index) return state.atmosphereProfiles[index + 1] end
    }
    env.ZM_DermaSkin = { StyleComboBox = function(panel) return panel end }
    env.LocalPlayer = function() return state.player end
    state.player = { GetNWBool = function(_, key) return key == "ZM.PrefabEditorActive" and state.active == true end }
    env.gui = {
        MousePos = function() return state.mouseX, state.mouseY end,
        ScreenToVector = function() return vector(1, 0, 0) end
    }
    env.util = {
        TableToJSON = function(value)
            state.nextJson = state.nextJson + 1
            local key = "json-" .. state.nextJson
            state.json[key] = clone(value)
            return key
        end,
        JSONToTable = function(value) return clone(state.json[value]) end,
        IntersectRayWithOBB = function(_, _, _, _, minimum, maximum)
            state.rayMinimum, state.rayMaximum = minimum, maximum
            if state.rayHit then return vector(), vector(), 0.5 end
            return nil, nil, nil
        end,
        IntersectRayWithPlane = function() return state.planeHit end
    }
    env.file = { Find = function(pattern, realm)
        assert(realm == "GAME" and string.sub(pattern, -1) == "*")
        local folder = string.sub(pattern, 1, -2)
        if state.failedModelFolder == folder then return nil, nil end
        local entry = state.modelFolders[folder]
        return clone(entry and entry.files or {}), clone(entry and entry.directories or {})
    end }
    env.hook = { Add = function(event, name, callback) state.hooks[name] = callback end }
    env.concommand = { Add = function(name, callback) state.commands[name] = callback end }
    env.net = {
        Receive = function(name, callback) state.receivers[name] = callback end,
        Start = function(name) state.request = { name = name, values = {} } end,
        WriteString = function(value) state.request.values[#state.request.values + 1] = value end,
        SendToServer = function() state.requests[#state.requests + 1] = state.request end,
        ReadString = function()
            local value = state.input[state.inputIndex]
            state.inputIndex = state.inputIndex + 1
            return value
        end,
        ReadBool = function()
            local value = state.input[state.inputIndex]
            state.inputIndex = state.inputIndex + 1
            return value
        end
    }
    env.surface = { SetDrawColor = function() end, DrawRect = function() end, CreateFont = function() end }
    env.render = {
        DrawLine = function(...) state.renderLines[#state.renderLines + 1] = { ... } end,
        DrawWireframeBox = function(...) state.renderBoxes[#state.renderBoxes + 1] = { ... } end
    }
    env.cam = {
        Start3D2D = function(origin, angle, scale)
            state.compassOrigin, state.compassAngle, state.compassScale = origin, angle, scale
        end,
        End3D2D = function() end
    }
    env.draw = { SimpleText = function(text, font, x, y)
        state.compassLabels[text] = { x = x, y = y, font = font }
    end }
    env.ClientsideModel = function(path)
        local model = { path = path, valid = true }
        function model:SetNoDraw(value) self.noDraw = value end
        function model:SetPos(value) self.position = value end
        function model:SetAngles(value) self.angles = value end
        function model:SetSkin(value) self.skin = value end
        function model:SetModelScale(value, duration) self.scale, self.scaleDuration = value, duration end
        function model:EnableMatrix(kind, matrix) self.matrixKind, self.matrix = kind, matrix end
        function model:SetRenderBounds(minimum, maximum) self.renderMinimum, self.renderMaximum = minimum, maximum end
        function model:GetPos() return self.position end
        function model:GetAngles() return self.angles end
        function model:OBBMins() return vector(-1, -1, -1) end
        function model:OBBMaxs() return vector(1, 1, 1) end
        function model:GetModelBounds() return vector(-2, -3, -4), vector(2, 3, 4) end
        function model:DrawModel() self.drawn = true end
        function model:Remove() self.valid = false end
        state.models[#state.models + 1] = model
        return model
    end
    env.vgui = {}
    function env.vgui.Create(kind, parent)
        local panel = { kind = kind, valid = true, lines = {}, children = {}, choices = {}, value = "" }
        if parent then parent.children[#parent.children + 1] = panel end
        function panel:Dock() end
        function panel:DockMargin() end
        function panel:SetTall() end
        function panel:SetWide() end
        function panel:SetSize() end
        function panel:SetPos() end
        function panel:Center() end
        function panel:SetTitle() end
        function panel:SetDraggable() end
        function panel:ShowCloseButton() end
        function panel:MakePopup() end
        function panel:SetText(value) self.text = value end
        function panel:SetTextColor(value) self.textColor = value end
        function panel:SetEnabled(value) self.enabled = value end
        function panel:SetValue(value)
            self.value = value
            if self.OnValueChange then self:OnValueChange(value) end
            if self.OnValueChanged then self:OnValueChanged(value) end
            if self.kind == "DCheckBoxLabel" and self.OnChange then self:OnChange(value == true or value == 1) end
        end
        function panel:SetUpdateOnType(value) self.updateOnType = value end
        function panel:TypeText(value)
            self.value = value
            if self.updateOnType and self.OnValueChange then self:OnValueChange(value) end
        end
        function panel:GetValue() return self.value end
        function panel:SetDecimals() end
        function panel:SetMin() end
        function panel:SetMax() end
        function panel:SetWrap() end
        function panel:SetContentAlignment() end
        function panel:SetPlaceholderText(value) self.placeholder = value end
        function panel:SetSpaceX() end
        function panel:SetSpaceY() end
        function panel:SetTooltip(value) self.tooltip = value end
        function panel:SetMouseInputEnabled(value) self.mouseEnabled = value end
        function panel:SetKeyboardInputEnabled(value) self.keyboardEnabled = value end
        function panel:SetModel(value)
            self.model = value
            if self.kind == "DModelPanel" then self.entity = env.ClientsideModel(value) end
        end
        function panel:GetEntity() return self.entity end
        function panel:SetFOV(value) self.fov = value end
        function panel:SetCamPos(value) self.camPos = value end
        function panel:SetLookAt(value) self.lookAt = value end
        function panel:GetText() return self.text end
        function panel:InvalidateLayout() end
        function panel:Add(kind) return env.vgui.Create(kind, self) end
        function panel:AddColumn() end
        function panel:AddChoice(text, data) self.choices[#self.choices + 1] = { text = text, data = data } end
        function panel:AddLine(...)
            local row = { values = { ... } }
            self.lines[#self.lines + 1] = row
            return row
        end
        function panel:Clear()
            self.lines = {}
            self.choices = {}
            for _, child in ipairs(self.children) do child.valid = false end
            self.children = {}
        end
        function panel:MouseCapture(value) self.capture = value end
        function panel:Remove()
            self.valid = false
            if self.entity and self.entity.valid then self.entity:Remove() end
            if self.OnRemove then self:OnRemove() end
        end
        function panel:Close() self:Remove() end
        state.panels[#state.panels + 1] = panel
        return panel
    end
    function state:Response(action, success, message, value)
        if action == "model" and success and value and not value.propId then
            self.nextPropId = (self.nextPropId or 0) + 1
            value.propId = "p_fixture" .. self.nextPropId
        end
        local encoded = value and env.util.TableToJSON(value) or ""
        self.input, self.inputIndex = { action, success, message or "", encoded }, 1
        self.receivers["ZM.PrefabEditorResponse"]()
    end
    return env, state
end
