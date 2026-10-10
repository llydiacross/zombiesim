return function(Markers)
    if Markers.Cleanup then Markers:Cleanup() end
    Markers.Items = {}
    Markers.Draws = 0
    Markers.MapDraws = 0
    local directions = { N = Vector(0, 1, 0), E = Vector(1, 0, 0), S = Vector(0, -1, 0), W = Vector(-1, 0, 0) }
    local colours = { normal = Color(92, 240, 154), route = Color(246, 210, 48), blocked = Color(232, 52, 52) }
    local material = CreateMaterial("zombiesim_transition_arrow_v2", "UnlitGeneric", {
        ["$basetexture"] = "models/debug/debugwhite",
        ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$translucent"] = 1, ["$nocull"] = 1
    })
    local identity = Matrix()
    local texture = material:GetTexture("$basetexture")
    local available = not material:IsError() and texture ~= nil and texture:Width() > 0

    function Markers.BuildVertices(origin, normal, code, colour)
        local outward = directions[code]
        assert(outward, "Unknown transition arrow direction: " .. tostring(code))
        local forward = outward - normal * outward:Dot(normal)
        assert(forward:LengthSqr() > 0.01, "Invalid transition arrow surface normal")
        forward:Normalize()
        local right = forward:Cross(normal)
        right:Normalize()
        local function vertex(longitudinal, lateral)
            return { pos = origin + forward * longitudinal + right * lateral, normal = normal,
                u = (lateral + 64) / 128, v = (longitudinal + 96) / 192, color = colour }
        end
        return {
            vertex(-96, -24), vertex(32, 24), vertex(32, -24),
            vertex(-96, -24), vertex(-96, 24), vertex(32, 24),
            vertex(32, -64), vertex(32, 64), vertex(96, 0)
        }
    end

    function Markers.GetColour(blocked, route)
        return blocked and colours.blocked or route and colours.route or colours.normal
    end

    function Markers:Cleanup()
        for _, item in pairs(self.Items or {}) do item.mesh:Destroy() end
        self.Items = {}
    end

    function Markers:Reconcile()
        local active = {}
        for code in pairs(directions) do
            for index = 1, GetGlobal2Int("ZMTransitionGateCount_" .. code, 0) do
                local gateKey = "ZMTransitionGate_" .. code .. "_" .. index
                for lane = 1, GetGlobal2Int(gateKey .. "_ArrowCount", 0) do
                        local key = gateKey .. (lane == 1 and "" or "_Lane2")
                        if GetGlobal2Bool(key .. "_SurfaceReady", false) then
                            local origin = GetGlobal2Vector(key .. "_Surface")
                            local normal = GetGlobal2Vector(key .. "_Normal")
                            if normal.z >= 0.7 and normal.z <= 1 then
                                active[key] = true
                                local item = self.Items[key]
                                if not item or item.origin ~= origin or item.normal ~= normal then
                                    if item then item.mesh:Destroy() end
                                    local object = Mesh(material)
                                    object:BuildFromTriangles(self.BuildVertices(origin, normal, code, colours.normal))
                                    self.Items[key] = { mesh = object, origin = origin, normal = normal, code = code, gateKey = gateKey }
                                end
                            end
                        end
                end
            end
        end
        for key, item in pairs(self.Items) do
            if not active[key] then item.mesh:Destroy() self.Items[key] = nil end
        end
    end

    function Markers:GetWaypointDirection(playerEntity)
        if not ZM_World or not ZM_World:IsLoaded() or not ZM_WorldMap then return nil end
        local x, y = ZM_World:GetGridCoordinates(playerEntity:GetNWInt("CellX", 0), playerEntity:GetNWInt("CellY", 0))
        local cell = x and ZM_World:GetCell(x, y)
        return cell and ZM_WorldMap:GetWaypointDirection(cell) or nil
    end

    function Markers:DrawMap(project, x, y, width, height)
        self.MapDraws = 0
        local target = LocalPlayer()
        if width <= 0 or height <= 0 or not IsValid(target) or not target:Alive()
            or target:GetNWString("CurrentSafeZoneId", "") ~= "" then return end
        local route = self:GetWaypointDirection(target)
        draw.NoTexture()
        for _, item in pairs(self.Items) do
            local colour = self.GetColour(target:GetNWBool(item.gateKey .. "_Blocked", true), item.code == route)
            local vertices = self.BuildVertices(item.origin, item.normal, item.code, colour)
            local drawn = false
            surface.SetDrawColor(colour.r, colour.g, colour.b, 255)
            for first = 1, #vertices, 3 do
                local polygon = {}
                // Projection flips winding; DrawPoly expects clockwise screen-space vertices.
                for index = first + 2, first, -1 do
                    local px, py = project(vertices[index].pos)
                    polygon[#polygon + 1] = { x = px, y = py }
                end
                for _, edge in ipairs({ { "x", x, 1 }, { "x", x + width, -1 },
                    { "y", y, 1 }, { "y", y + height, -1 } }) do
                    local clipped = {}
                    if #polygon > 0 then
                        local previous = polygon[#polygon]
                        local previousDistance = (previous[edge[1]] - edge[2]) * edge[3]
                        for _, point in ipairs(polygon) do
                            local distance = (point[edge[1]] - edge[2]) * edge[3]
                            if (distance >= 0) ~= (previousDistance >= 0) then
                                local t = previousDistance / (previousDistance - distance)
                                clipped[#clipped + 1] = { x = previous.x + (point.x - previous.x) * t,
                                    y = previous.y + (point.y - previous.y) * t }
                            end
                            if distance >= 0 then clipped[#clipped + 1] = point end
                            previous, previousDistance = point, distance
                        end
                    end
                    polygon = clipped
                end
                if #polygon >= 3 then surface.DrawPoly(polygon) drawn = true end
            end
            if drawn then self.MapDraws = self.MapDraws + 1 end
        end
    end

    function Markers:Draw(depth, skybox)
        self.Draws = 0
        if depth or skybox or (ZM_WorldMap and ZM_WorldMap.Capturing)
            or (ZM_SkyInspection and ZM_SkyInspection.Rendering)
            or (ZM_LauncherMenu and ZM_LauncherMenu.Active)
            or (ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud()) then return end
        local target = LocalPlayer()
        if not IsValid(target) or not target:Alive() or target:GetNWString("CurrentSafeZoneId", "") ~= "" then return end
        if not available then return end
        local route = self:GetWaypointDirection(target)
        local position = EyePos()
        local visible = {}
        for key, item in pairs(self.Items) do
            if position:DistToSqr(item.origin) <= 1280 * 1280 then
                local colour = self.GetColour(target:GetNWBool(item.gateKey .. "_Blocked", true), item.code == route)
                local state = colour == colours.blocked and "blocked" or colour == colours.route and "route" or "normal"
                if item.state ~= state then
                    item.mesh:BuildFromTriangles(self.BuildVertices(item.origin, item.normal, item.code, colour))
                    item.state = state
                end
                visible[#visible + 1] = item
            end
        end
        if #visible > 0 then
            cam.PushModelMatrix(identity)
            render.SetMaterial(material)
            for _, item in ipairs(visible) do item.mesh:Draw() end
            cam.PopModelMatrix()
        end
        self.Draws = #visible
    end

    function Markers:GetDiagnosticSnapshot()
        local count = 0
        for _ in pairs(self.Items) do count = count + 1 end
        return { markers = count, draws = self.Draws, mapDraws = self.MapDraws, materialError = not available,
            textureWidth = texture and texture:Width() or 0, shader = material:GetShader(),
            length = 192, width = 128, range = 1280 }
    end

    if not available then ErrorNoHalt("[ZombieSim] Transition arrow material failed to resolve.\n") end
    hook.Add("Think", "ZM.TransitionArrows.Reconcile", function() Markers:Reconcile() end)
    hook.Add("PreDrawTranslucentRenderables", "ZM.TransitionArrows.Draw", function(depth, skybox) Markers:Draw(depth, skybox) end)
    hook.Add("PreCleanupMap", "ZM.TransitionArrows.Cleanup", function() Markers:Cleanup() end)
    hook.Add("ShutDown", "ZM.TransitionArrows.Cleanup", function() Markers:Cleanup() end)
    concommand.Add("zombiesim_transition_arrows_status", function()
        local snapshot = Markers:GetDiagnosticSnapshot()
        print("[ZombieSim] Transition arrows: " .. util.TableToJSON(snapshot))
        file.CreateDir("zombiesim")
        file.Write("zombiesim/transition_arrows_status.json", util.TableToJSON(snapshot, true))
    end)
end
