ZM_WorldMap = ZM_WorldMap or {}
local WorldMap = ZM_WorldMap
local MapColors = ZM_DermaSkin.Palette
local getAllPlayers = player.GetAll
local localMapCameraHeight = 3600
local localMapFieldOfView = 48
local localMapSpan = 2 * localMapCameraHeight * math.tan(math.rad(localMapFieldOfView * 0.5))
local localMapDefaultZoom = 1
local localMapTileCount = 2
local localMapTileSize = 1024
local localMapTileSpan = localMapSpan / localMapTileCount
local localMapTileFieldOfView = math.deg(2 * math.atan(localMapTileSpan / (2 * localMapCameraHeight)))
local localMapCaptureVersion = 2
local localMapRefreshInterval = 3

WorldMap.Layers = {
    { id = "terrain", label = "Terrain", enabled = true },
    { id = "districts", label = "Districts", enabled = false },
    { id = "buildings", label = "Buildings", enabled = true },
    { id = "roads", label = "Roads", enabled = true },
    { id = "highways", label = "Motorways", enabled = true },
    { id = "metro", label = "Metro", enabled = true },
    { id = "safe_zones", label = "Safe Zones", enabled = true },
    { id = "landmarks", label = "Landmarks", enabled = true },
    { id = "radiation", label = "Radiation", enabled = false },
    { id = "danger", label = "Danger", enabled = false },
    { id = "tables", label = "Map Keys", enabled = true }
}
WorldMap.EnabledLayers = WorldMap.EnabledLayers or {}
WorldMap.Materials = WorldMap.Materials or {}
WorldMap.CellMaterials = WorldMap.CellMaterials or {}
WorldMap.LocalMapTiles = WorldMap.LocalMapTiles or {}
WorldMap.LocalMapRefreshTimes = WorldMap.LocalMapRefreshTimes or {}
WorldMap.SelectedCell = WorldMap.SelectedCell or nil
WorldMap.WaypointCell = WorldMap.WaypointCell or nil
WorldMap.WaypointProfile = WorldMap.WaypointProfile or nil
WorldMap.WaypointPath = WorldMap.WaypointPath or nil
WorldMap.Viewport = WorldMap.Viewport or { zoom = 1, panX = 0, panY = 0 }
WorldMap.LocalViewport = WorldMap.LocalViewport or { zoom = localMapDefaultZoom, panX = 0, panY = 0 }
WorldMap.RenderModes = { default = true, satellite = true, map = true }
WorldMap.RenderMode = WorldMap.RenderModes[WorldMap.RenderMode] and WorldMap.RenderMode or "default"
WorldMap.DefaultLayerOrder = {
    "terrain",
    "buildings",
    "roads",
    "highways",
    "metro",
    "safe_zones",
    "landmarks",
    "radiation",
    "danger",
    "districts"
}
WorldMap.LayerOrder = WorldMap.LayerOrder or {}

local function getLayerPreference(layer)
    local savedValue = cookie.GetString("zombiesim_world_map_layer_" .. layer.id, "")
    if savedValue == "0" then
        return false
    end
    if savedValue == "1" then
        return true
    end
    return layer.enabled
end

local function setLayerPreference(layerId, enabled)
    WorldMap.EnabledLayers[layerId] = enabled
    cookie.Set("zombiesim_world_map_layer_" .. layerId, enabled and "1" or "0")
end

local function getLayerById(layerId)
    for _, layer in ipairs(WorldMap.Layers) do
        if layer.id == layerId then
            return layer
        end
    end
    return nil
end

function WorldMap:LoadLayerOrder()
    local availableLayerIds = {}
    for _, layer in ipairs(self.Layers) do
        if layer.id ~= "tables" then
            availableLayerIds[layer.id] = true
        end
    end

    local savedOrder = cookie.GetString("zombiesim_world_map_layer_order", "")
    local layerOrder = {}
    local included = {}
    for layerId in string.gmatch(savedOrder, "[^,]+") do
        if availableLayerIds[layerId] and not included[layerId] then
            table.insert(layerOrder, layerId)
            included[layerId] = true
        end
    end
    for _, layerId in ipairs(self.DefaultLayerOrder) do
        if availableLayerIds[layerId] and not included[layerId] then
            table.insert(layerOrder, layerId)
            included[layerId] = true
        end
    end

    self.LayerOrder = layerOrder
end

function WorldMap:SaveLayerOrder()
    cookie.Set("zombiesim_world_map_layer_order", table.concat(self.LayerOrder, ","))
end

function WorldMap:MoveLayer(layerId, direction)
    local index
    for currentIndex, currentLayerId in ipairs(self.LayerOrder) do
        if currentLayerId == layerId then
            index = currentIndex
            break
        end
    end

    local targetIndex = index and index + direction or nil
    if not targetIndex or targetIndex < 1 or targetIndex > #self.LayerOrder then
        return false
    end

    self.LayerOrder[index], self.LayerOrder[targetIndex] = self.LayerOrder[targetIndex], self.LayerOrder[index]
    self:SaveLayerOrder()
    return true
end

local function getMapStateKey(name)
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    return "zombiesim_world_map_" .. profile .. "_" .. name
end

local function getSavedCell(name)
    local cellId = tonumber(cookie.GetString(getMapStateKey(name), ""))
    return cellId and ZM_World:GetCellById(math.floor(cellId)) or nil
end

function WorldMap:LoadPersistentState()
    if not ZM_World or not ZM_World:IsLoaded() then
        return
    end

    local profile = ZM_World.ActiveProfile
    if self.StateProfile == profile then
        return
    end

    self.StateProfile = profile
    self.Viewport = {
        zoom = math.Clamp(tonumber(cookie.GetString(getMapStateKey("zoom"), "")) or 1, 0.1, 32),
        panX = tonumber(cookie.GetString(getMapStateKey("pan_x"), "")) or 0,
        panY = tonumber(cookie.GetString(getMapStateKey("pan_y"), "")) or 0
    }
    self.LocalViewport = {
        zoom = math.Clamp(tonumber(cookie.GetString(getMapStateKey("local_zoom"), "")) or localMapDefaultZoom, 0.1, 32),
        panX = tonumber(cookie.GetString(getMapStateKey("local_pan_x"), "")) or 0,
        panY = tonumber(cookie.GetString(getMapStateKey("local_pan_y"), "")) or 0
    }
    self.SelectedCell = getSavedCell("selected_cell")
    self.WaypointCell = getSavedCell("waypoint_cell")
    self.WaypointProfile = self.WaypointCell and profile or nil
    self.WaypointPath = nil
    local renderMode = cookie.GetString(getMapStateKey("render_mode"), "default")
    self.RenderMode = self.RenderModes[renderMode] and renderMode or "default"
end

function WorldMap:SaveViewportState()
    cookie.Set(getMapStateKey("zoom"), tostring(self.Viewport.zoom))
    cookie.Set(getMapStateKey("pan_x"), tostring(self.Viewport.panX))
    cookie.Set(getMapStateKey("pan_y"), tostring(self.Viewport.panY))
end

function WorldMap:SaveLocalViewportState()
    cookie.Set(getMapStateKey("local_zoom"), tostring(self.LocalViewport.zoom))
    cookie.Set(getMapStateKey("local_pan_x"), tostring(self.LocalViewport.panX))
    cookie.Set(getMapStateKey("local_pan_y"), tostring(self.LocalViewport.panY))
end

function WorldMap:SaveCellState(name, cell)
    cookie.Set(getMapStateKey(name), cell and tostring(cell.id) or "")
end

function WorldMap:SetRenderMode(renderMode)
    if not self.RenderModes[renderMode] then
        return false
    end

    self.RenderMode = renderMode
    cookie.Set(getMapStateKey("render_mode"), renderMode)
    return true
end

for _, layer in ipairs(WorldMap.Layers) do
    if WorldMap.EnabledLayers[layer.id] == nil then
        WorldMap.EnabledLayers[layer.id] = getLayerPreference(layer)
    end
end
WorldMap:LoadLayerOrder()

local function getWorldData()
    if not ZM_World or not ZM_World:IsLoaded() then
        return nil
    end

    return ZM_World:GetData()
end

local function getMaterial(layerId)
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local materialKey = profile .. "/" .. layerId
    if not WorldMap.Materials[materialKey] then
        WorldMap.Materials[materialKey] = Material("worlds/" .. profile .. "/map_layers/" .. layerId .. ".png", "smooth")
    end

    return WorldMap.Materials[materialKey]
end

local function getRenderModeMaterial(renderMode)
    if renderMode == "satellite" then
        return getMaterial("satellite")
    end
    return nil
end

local function getLocalMapKey()
    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local mapName = game and game.GetMap and game.GetMap() or "current"
    mapName = string.lower(string.match(mapName, "([^/\\]+)$") or mapName)
    mapName = string.gsub(mapName, "[^%w_-]", "_")
    return profile .. "/" .. mapName .. "/v" .. localMapCaptureVersion, profile, mapName
end

local function getLocalMapTiles()
    local mapKey = getLocalMapKey()
    return WorldMap.LocalMapTiles[mapKey]
end

function WorldMap:CaptureCurrentMap(resetViewport)
    local player = LocalPlayer()
    if not IsValid(player) then
        return false
    end

    local mapKey, profile, mapName = getLocalMapKey()
    local tiles = {}
    for row = 0, localMapTileCount - 1 do
        for column = 0, localMapTileCount - 1 do
            local renderTargetName = string.format("zombiesim_local_map_%s_%s_v%d_%d_%d", profile, mapName, localMapCaptureVersion, row, column)
            local renderTarget = GetRenderTarget(renderTargetName, localMapTileSize, localMapTileSize, false)
            local material = CreateMaterial(renderTargetName .. "_material", "UnlitGeneric", {
                ["$basetexture"] = renderTarget:GetName(),
                ["$vertexcolor"] = "1",
                ["$vertexalpha"] = "1"
            })
            if not material or material:IsError() then
                return false
            end

            local cameraX = (column - localMapTileCount * 0.5 + 0.5) * localMapTileSpan
            local cameraY = (localMapTileCount * 0.5 - row - 0.5) * localMapTileSpan
            render.PushRenderTarget(renderTarget)
            render.Clear(0, 0, 0, 255, true, true)
            render.RenderView({
                origin = Vector(cameraX, cameraY, localMapCameraHeight),
                angles = Angle(90, 90, 0),
                x = 0,
                y = 0,
                w = localMapTileSize,
                h = localMapTileSize,
                fov = localMapTileFieldOfView,
                znear = 4,
                zfar = 8192,
                drawviewmodel = false,
                drawhud = false,
                dopostprocess = false
            })
            render.PopRenderTarget()
            table.insert(tiles, { row = row, column = column, material = material })
        end
    end

    self.LocalMapTiles[mapKey] = tiles
    self.LocalMapRefreshTimes[mapKey] = CurTime()
    if resetViewport ~= false then
        self.LocalViewport = { zoom = localMapDefaultZoom, panX = 0, panY = 0 }
        self:SaveLocalViewportState()
    end
    return true
end

function WorldMap:EnsureLocalMapCapture()
    if getLocalMapTiles() then
        return true
    end
    return self:CaptureCurrentMap()
end

function WorldMap:ProjectLocalMapPosition(x, y, width, height, centerPosition, viewHeight, mapPosition)
    centerPosition = centerPosition or vector_origin
    mapPosition = mapPosition or vector_origin
    viewHeight = math.Clamp(tonumber(viewHeight) or localMapSpan * 0.46, 1, localMapSpan)
    local viewWidth = viewHeight * width / height
    local viewStartU = 0.5 + centerPosition.x / localMapSpan - viewWidth / localMapSpan * 0.5
    local viewStartV = 0.5 - centerPosition.y / localMapSpan - viewHeight / localMapSpan * 0.5
    local mapU = 0.5 + mapPosition.x / localMapSpan
    local mapV = 0.5 - mapPosition.y / localMapSpan
    return x + (mapU - viewStartU) / (viewWidth / localMapSpan) * width,
        y + (mapV - viewStartV) / (viewHeight / localMapSpan) * height
end

function WorldMap:RefreshLocalMapIfDue()
    local mapKey = getLocalMapKey()
    local lastRefresh = self.LocalMapRefreshTimes[mapKey] or 0
    if not getLocalMapTiles() or CurTime() - lastRefresh >= localMapRefreshInterval then
        return self:CaptureCurrentMap(false)
    end
    return true
end

function WorldMap:DrawLocalMap(x, y, width, height, centerPosition, viewHeight)
    local tiles = getLocalMapTiles()
    if not tiles or width <= 0 or height <= 0 then
        return false
    end

    centerPosition = centerPosition or vector_origin
    viewHeight = math.Clamp(tonumber(viewHeight) or localMapSpan * 0.46, 1, localMapSpan)
    local viewWidth = viewHeight * width / height
    local viewStartU = 0.5 + centerPosition.x / localMapSpan - viewWidth / localMapSpan * 0.5
    local viewStartV = 0.5 - centerPosition.y / localMapSpan - viewHeight / localMapSpan * 0.5
    local viewEndU = viewStartU + viewWidth / localMapSpan
    local viewEndV = viewStartV + viewHeight / localMapSpan
    local tileUvSize = 1 / localMapTileCount
    local drewMap = false

    for _, tile in ipairs(tiles) do
        if tile.material and not tile.material:IsError() then
            local tileStartU = tile.column * tileUvSize
            local tileStartV = tile.row * tileUvSize
            local tileEndU = tileStartU + tileUvSize
            local tileEndV = tileStartV + tileUvSize
            local drawStartU = math.max(viewStartU, tileStartU)
            local drawStartV = math.max(viewStartV, tileStartV)
            local drawEndU = math.min(viewEndU, tileEndU)
            local drawEndV = math.min(viewEndV, tileEndV)
            if drawStartU < drawEndU and drawStartV < drawEndV then
                local destinationX = x + (drawStartU - viewStartU) / (viewEndU - viewStartU) * width
                local destinationY = y + (drawStartV - viewStartV) / (viewEndV - viewStartV) * height
                local destinationWidth = (drawEndU - drawStartU) / (viewEndU - viewStartU) * width
                local destinationHeight = (drawEndV - drawStartV) / (viewEndV - viewStartV) * height
                surface.SetMaterial(tile.material)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRectUV(
                    destinationX,
                    destinationY,
                    destinationWidth,
                    destinationHeight,
                    (drawStartU - tileStartU) / tileUvSize,
                    (drawStartV - tileStartV) / tileUvSize,
                    (drawEndU - tileStartU) / tileUvSize,
                    (drawEndV - tileStartV) / tileUvSize
                )
                drewMap = true
            end
        end
    end

    return drewMap
end

local function getCellRenderMaterial(cell)
    if not cell or type(cell.map) ~= "string" or cell.map == "" then
        return nil
    end

    local profile = ZM_World and ZM_World.ActiveProfile or "city"
    local materialKey = profile .. "/" .. cell.map
    if not WorldMap.CellMaterials[materialKey] then
        WorldMap.CellMaterials[materialKey] = Material("worlds/" .. profile .. "/cells/" .. cell.map .. ".png", "smooth")
    end

    return WorldMap.CellMaterials[materialKey]
end

local function getCellGridCoordinates(cell)
    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
    if worldX == nil or worldY == nil then
        return nil
    end

    return ZM_World:GetGridCoordinates(worldX, worldY)
end

local function getPlayerMapCell(player)
    local worldX = player:GetNWInt("CellX", 0)
    local worldY = player:GetNWInt("CellY", 0)
    local gridX, gridY = ZM_World:GetGridCoordinates(worldX, worldY)
    return gridX and ZM_World:GetCell(gridX, gridY) or nil
end

local function drawCellOutline(cell, mapX, mapY, cellSize, color)
    local gridX, gridY = getCellGridCoordinates(cell)
    if not gridX or not gridY then
        return
    end

    local x = mapX + gridX * cellSize
    local y = mapY + gridY * cellSize
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    surface.DrawOutlinedRect(x, y, cellSize, cellSize, 2)
end

local function drawWaypoint(cell, mapX, mapY, cellSize)
    local gridX, gridY = getCellGridCoordinates(cell)
    if not gridX or not gridY then
        return
    end

    local centerX = mapX + (gridX + 0.5) * cellSize
    local centerY = mapY + (gridY + 0.5) * cellSize
    local radius = math.max(5, math.min(12, cellSize * 0.22))
    surface.SetDrawColor(52, 220, 176, 255)
    surface.DrawLine(centerX, centerY - radius, centerX + radius, centerY)
    surface.DrawLine(centerX + radius, centerY, centerX, centerY + radius)
    surface.DrawLine(centerX, centerY + radius, centerX - radius, centerY)
    surface.DrawLine(centerX - radius, centerY, centerX, centerY - radius)
end

local function getWaypointPath(playerCell)
    local waypointCell = WorldMap.WaypointCell
    if not playerCell or not waypointCell or WorldMap.WaypointProfile ~= ZM_World.ActiveProfile then
        return nil
    end

    local cachedPath = WorldMap.WaypointPath
    if cachedPath and cachedPath.playerCellId == playerCell.id and cachedPath.waypointCellId == waypointCell.id then
        return cachedPath.cells
    end

    local path = ZM_World:FindPath(playerCell, waypointCell, { mode = "any", allowBlocked = false })
    local cells = path and path.cells or {}
    WorldMap.WaypointPath = { playerCellId = playerCell.id, waypointCellId = waypointCell.id, cells = cells }
    return cells
end

local function drawRouteLine(startX, startY, endX, endY, width)
    local deltaX = endX - startX
    local deltaY = endY - startY
    local length = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    if length <= 0 then
        return
    end

    local halfWidth = width * 0.5
    local offsetX = -deltaY / length * halfWidth
    local offsetY = deltaX / length * halfWidth
    for offset = -math.floor(halfWidth), math.floor(halfWidth) do
        surface.DrawLine(startX + offsetX / halfWidth * offset, startY + offsetY / halfWidth * offset, endX + offsetX / halfWidth * offset, endY + offsetY / halfWidth * offset)
    end
end

local function drawWaypointPath(cells, mapX, mapY, cellWidth, cellHeight)
    if not cells or #cells < 2 then
        return
    end

    local lineWidth = math.max(3, math.min(7, math.min(cellWidth, cellHeight) * 0.18))
    local outlineWidth = lineWidth + 4
    local previousX, previousY
    for _, cell in ipairs(cells) do
        local gridX, gridY = getCellGridCoordinates(cell)
        if gridX and gridY then
            local centerX = mapX + (gridX + 0.5) * cellWidth
            local centerY = mapY + (gridY + 0.5) * cellHeight
            if previousX then
                surface.SetDrawColor(8, 10, 12, 245)
                drawRouteLine(previousX, previousY, centerX, centerY, outlineWidth)
                surface.SetDrawColor(246, 210, 48, 255)
                drawRouteLine(previousX, previousY, centerX, centerY, lineWidth)
            end
            previousX, previousY = centerX, centerY
        end
    end
end

local function drawSatelliteBlockades(worldData, mapX, mapY, cellWidth, cellHeight)
    for _, cell in ipairs(worldData.cells or {}) do
        local gridX, gridY = getCellGridCoordinates(cell)
        if gridX and gridY then
            local cellX = mapX + gridX * cellWidth
            local cellY = mapY + gridY * cellHeight
            local thickness = math.max(2, math.min(8, math.floor(math.min(cellWidth, cellHeight) * 0.1)))
            local inset = math.max(1, math.floor(math.min(cellWidth, cellHeight) * 0.06))
            for _, exit in ipairs(cell.exits or {}) do
                local isBlocked = false
                for _, mode in ipairs(exit.modes or {}) do
                    if mode.type == "road" and mode.blocked then
                        isBlocked = true
                        break
                    end
                end
                if isBlocked then
                    local direction = tostring(exit.direction)
                    local startX, startY, width, height
                    if direction == "N" then
                        startX, startY, width, height = cellX + cellWidth * 0.26, cellY + inset, cellWidth * 0.48, thickness
                    elseif direction == "E" then
                        startX, startY, width, height = cellX + cellWidth - inset - thickness, cellY + cellHeight * 0.26, thickness, cellHeight * 0.48
                    elseif direction == "S" then
                        startX, startY, width, height = cellX + cellWidth * 0.26, cellY + cellHeight - inset - thickness, cellWidth * 0.48, thickness
                    elseif direction == "W" then
                        startX, startY, width, height = cellX + inset, cellY + cellHeight * 0.26, thickness, cellHeight * 0.48
                    end
                    if startX then
                        surface.SetDrawColor(18, 12, 12, 240)
                        surface.DrawRect(startX - 1, startY - 1, width + 2, height + 2)
                        surface.SetDrawColor(MapColors.redBright.r, MapColors.redBright.g, MapColors.redBright.b, 255)
                        surface.DrawRect(startX, startY, width, height)
                        surface.SetDrawColor(255, 225, 225, 235)
                        if direction == "N" or direction == "S" then
                            for stripeX = startX + 2, startX + width - 2, thickness * 2 do
                                surface.DrawRect(stripeX, startY + 1, math.min(thickness, startX + width - 1 - stripeX), height - 2)
                            end
                        else
                            for stripeY = startY + 2, startY + height - 2, thickness * 2 do
                                surface.DrawRect(startX + 1, stripeY, width - 2, math.min(thickness, startY + height - 1 - stripeY))
                            end
                        end
                    end
                end
            end
        end
    end
end

local function drawOverlay(material, x, y, width, height, startU, startV, endU, endV)
    if not material or material:IsError() then
        return
    end

    surface.SetMaterial(material)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(x, y, width, height, startU, startV, endU, endV)
end

local function drawCellCapture(material, x, y, width, height, imageDimensions)
    if not material or material:IsError() then
        return false
    end

    local sourceWidth = material:Width()
    local sourceHeight = material:Height()
    if sourceWidth <= 0 or sourceHeight <= 0 then
        return false
    end

    local imageWidth = math.min(imageDimensions and imageDimensions.width or sourceWidth, sourceWidth)
    local imageHeight = math.min(imageDimensions and imageDimensions.height or sourceHeight, sourceHeight)
    if imageWidth <= 0 or imageHeight <= 0 then
        return false
    end

    local sourceAspect = imageWidth / imageHeight
    local targetAspect = width / height
    local startU, startV = 0, 0
    local endU = imageWidth / sourceWidth
    local endV = imageHeight / sourceHeight
    if sourceAspect > targetAspect then
        local visibleWidth = imageHeight * targetAspect
        startU = (imageWidth - visibleWidth) * 0.5 / sourceWidth
        endU = (imageWidth + visibleWidth) * 0.5 / sourceWidth
    elseif sourceAspect < targetAspect then
        local visibleHeight = imageWidth / targetAspect
        startV = (imageHeight - visibleHeight) * 0.5 / sourceHeight
        endV = (imageHeight + visibleHeight) * 0.5 / sourceHeight
    end

    drawOverlay(material, x, y, width, height, startU, startV, endU, endV)
    return true
end

local function drawFixedMapOverlays(worldData, width, height)
    local labelMaterial = getMaterial("labels")
    if not labelMaterial or labelMaterial:IsError() then
        return
    end

    local keyWidth = 0
    if WorldMap.EnabledLayers.tables then
        local keyMaterial = getMaterial("keys")
        if keyMaterial and not keyMaterial:IsError() then
            local keySourceWidth = 360
            local keySourceHeight = 18 + (50 + 13 * 28) + 14 + (45 + 3 * 28) + 14 + (45 + #(worldData.safeZones or {}) * 25) + 14 + (45 + (2 + #((worldData.metro or {}).lines or {})) * 25)
            local keyAvailableWidth = math.max(0, width * 0.38 - 24)
            local keyScale = math.min(0.8, (height - 24) / keySourceHeight, keyAvailableWidth / keySourceWidth)
            keyWidth = keySourceWidth * keyScale
            local keyHeight = keySourceHeight * keyScale
            local keyTextureWidth = keyMaterial:Width()
            local keyTextureHeight = keyMaterial:Height()
            local keyStartU = (keyTextureWidth - keySourceWidth - 18) / keyTextureWidth
            local keyEndU = (keyTextureWidth - 18) / keyTextureWidth
            local keyEndV = math.min(1, keySourceHeight / keyTextureHeight)
            drawOverlay(keyMaterial, width - keyWidth - 12, 12, keyWidth, keyHeight, keyStartU, 0, keyEndU, keyEndV)
        end
    end

    local titleSourceWidth = 720
    local titleSourceHeight = 160
    local titleAvailableWidth = math.max(0, width - keyWidth - 36)
    local titleAvailableHeight = math.max(0, height * 0.22 - 24)
    local titleScale = math.min(0.8, titleAvailableWidth / titleSourceWidth, titleAvailableHeight / titleSourceHeight) * 0.5
    local titleTextureWidth = labelMaterial:Width()
    local titleTextureHeight = labelMaterial:Height()
    local titleEndU = math.min(1, titleSourceWidth / titleTextureWidth)
    local titleEndV = math.min(1, titleSourceHeight / titleTextureHeight)
    drawOverlay(labelMaterial, 12, 12, titleSourceWidth * titleScale, titleSourceHeight * titleScale, 0, 0, titleEndU, titleEndV)
end

local function createMapCanvas(parent, onSelect)
    local canvas = vgui.Create("DPanel", parent)
    canvas:SetPaintBackground(false)
    local initialViewport = WorldMap.RenderMode == "map" and WorldMap.LocalViewport or WorldMap.Viewport
    canvas.Zoom = initialViewport.zoom
    canvas.PanX = initialViewport.panX
    canvas.PanY = initialViewport.panY

    function canvas:SaveViewport()
        local viewport = WorldMap.RenderMode == "map" and WorldMap.LocalViewport or WorldMap.Viewport
        viewport.zoom = self.Zoom
        viewport.panX = self.PanX
        viewport.panY = self.PanY
    end

    function canvas:PersistViewport()
        self:SaveViewport()
        if WorldMap.RenderMode == "map" then
            WorldMap:SaveLocalViewportState()
        else
            WorldMap:SaveViewportState()
        end
    end

    function canvas:LoadRenderViewport()
        self.FocusAnimation = nil
        local viewport = WorldMap.RenderMode == "map" and WorldMap.LocalViewport or WorldMap.Viewport
        self.Zoom = viewport.zoom
        self.PanX = viewport.panX
        self.PanY = viewport.panY
    end

    function canvas:GetMapBounds()
        local baseSize = math.min(self:GetWide(), self:GetTall()) * 0.92
        local mapSize = baseSize * self.Zoom
        return self:GetWide() * 0.5 + self.PanX - mapSize * 0.5, self:GetTall() * 0.5 + self.PanY - mapSize * 0.5, mapSize
    end

    function canvas:ResetView()
        self.FocusAnimation = nil
        self.Zoom = WorldMap.RenderMode == "map" and localMapDefaultZoom or 1
        self.PanX = 0
        self.PanY = 0
        self:PersistViewport()
    end

    function canvas:FocusCell(cell)
        local gridX, gridY = getCellGridCoordinates(cell)
        if not gridX or not gridY then
            return
        end

        local targetZoom = math.Clamp(math.max(self.Zoom, 3), 0.1, 32)
        local mapSize = math.min(self:GetWide(), self:GetTall()) * 0.92 * targetZoom
    local worldData = getWorldData()
    local gridWidth = tonumber(worldData and worldData.world.grid[1]) or 1
    local gridHeight = tonumber(worldData and worldData.world.grid[2]) or 1
        self.FocusAnimation = {
            startTime = RealTime(),
            duration = 0.35,
            startZoom = self.Zoom,
            startPanX = self.PanX,
            startPanY = self.PanY,
            targetZoom = targetZoom,
            targetPanX = mapSize * 0.5 - (gridX + 0.5) * mapSize / gridWidth,
            targetPanY = mapSize * 0.5 - (gridY + 0.5) * mapSize / gridHeight
        }
    end

    function canvas:FocusLocalPosition(position)
        if not position then
            return
        end

        local targetZoom = math.Clamp(math.max(self.Zoom, 1), 0.1, 32)
        local mapSize = math.min(self:GetWide(), self:GetTall()) * 0.92 * targetZoom
        self.FocusAnimation = {
            startTime = RealTime(),
            duration = 0.35,
            startZoom = self.Zoom,
            startPanX = self.PanX,
            startPanY = self.PanY,
            targetZoom = targetZoom,
            targetPanX = -position.x / localMapSpan * mapSize,
            targetPanY = position.y / localMapSpan * mapSize
        }
    end

    function canvas:Think()
        local animation = self.FocusAnimation
        if not animation then
            return
        end

        local progress = math.Clamp((RealTime() - animation.startTime) / animation.duration, 0, 1)
        local easedProgress = 1 - (1 - progress) ^ 3
        self.Zoom = Lerp(easedProgress, animation.startZoom, animation.targetZoom)
        self.PanX = Lerp(easedProgress, animation.startPanX, animation.targetPanX)
        self.PanY = Lerp(easedProgress, animation.startPanY, animation.targetPanY)
        self:SaveViewport()
        if progress == 1 then
            self.FocusAnimation = nil
            self:PersistViewport()
        end
    end

    function canvas:GetCellAt(cursorX, cursorY)
        local worldData = getWorldData()
        if not worldData or type(worldData.world.grid) ~= "table" then
            return nil
        end

        local mapX, mapY, mapSize = self:GetMapBounds()
        local gridWidth = tonumber(worldData.world.grid[1]) or 0
        local gridHeight = tonumber(worldData.world.grid[2]) or 0
        if gridWidth < 1 or gridHeight < 1 then
            return nil
        end

        local cellX = math.floor((cursorX - mapX) / (mapSize / gridWidth))
        local cellY = math.floor((cursorY - mapY) / (mapSize / gridHeight))
        if cellX < 0 or cellX >= gridWidth or cellY < 0 or cellY >= gridHeight then
            return nil
        end

        return ZM_World:GetCell(cellX, cellY)
    end

    function canvas:UpdateLandmarkTooltip(cursorX, cursorY)
        local tooltipLines = {}
        if cursorX >= 0 and cursorY >= 0 and cursorX < self:GetWide() and cursorY < self:GetTall() then
            local cell = self:GetCellAt(cursorX, cursorY)
            local player = LocalPlayer()
            local playerCell = IsValid(player) and getPlayerMapCell(player) or nil
            if cell and playerCell and cell.id == playerCell.id then
                table.insert(tooltipLines, player:Nick())
            end
            if WorldMap.EnabledLayers.safe_zones then
                local safeZone = cell and ZM_World:GetSafeZone(cell) or nil
                if safeZone and safeZone.name then
                    table.insert(tooltipLines, "Safe Zone: " .. safeZone.name)
                end
            end
            if WorldMap.EnabledLayers.landmarks then
                local landmarks = cell and ZM_World:GetLandmarks(cell) or nil
                if landmarks and #landmarks > 0 then
                    for _, landmark in ipairs(landmarks) do
                        table.insert(tooltipLines, landmark)
                    end
                end
            end
        end

        local tooltipText = #tooltipLines > 0 and table.concat(tooltipLines, "\n") or nil

        if self.LandmarkTooltipText == tooltipText then
            return
        end

        self.LandmarkTooltipText = tooltipText
    end

    function canvas:DrawLandmarkTooltip(width, height)
        local tooltipText = self.LandmarkTooltipText
        if not tooltipText then
            return
        end

        local cursorX, cursorY = self:CursorPos()
        local lines = string.Explode("\n", tooltipText)
        surface.SetFont("DermaDefaultBold")
        local lineHeight = select(2, surface.GetTextSize("W"))
        local textWidth = 0
        for _, line in ipairs(lines) do
            textWidth = math.max(textWidth, surface.GetTextSize(line))
        end

        local padding = 7
        local tooltipWidth = textWidth + padding * 2
        local tooltipHeight = lineHeight * #lines + padding * 2
        local tooltipX = math.Clamp(cursorX + 14, 4, width - tooltipWidth - 4)
        local tooltipY = cursorY + 18
        if tooltipY + tooltipHeight > height - 4 then
            tooltipY = math.max(4, cursorY - tooltipHeight - 8)
        end

        draw.NoTexture()
        surface.SetDrawColor(MapColors.black.r, MapColors.black.g, MapColors.black.b, 245)
        surface.DrawRect(tooltipX, tooltipY, tooltipWidth, tooltipHeight)
        surface.SetDrawColor(MapColors.redBright.r, MapColors.redBright.g, MapColors.redBright.b, 255)
        surface.DrawOutlinedRect(tooltipX, tooltipY, tooltipWidth, tooltipHeight, 1)
        for index, line in ipairs(lines) do
            draw.SimpleText(line, "DermaDefaultBold", tooltipX + padding, tooltipY + padding + (index - 1) * lineHeight, MapColors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    function canvas:Paint(width, height)
        surface.SetDrawColor(MapColors.black.r, MapColors.black.g, MapColors.black.b, 245)
        surface.DrawRect(0, 0, width, height)

        local worldData = getWorldData()
        if not worldData or type(worldData.world.grid) ~= "table" then
            draw.SimpleText("WORLD DATA UNAVAILABLE", "DermaDefaultBold", width * 0.5, height * 0.5, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        if WorldMap.RenderMode == "map" then
            self.LandmarkTooltipText = nil
            local mapX, mapY, mapSize = self:GetMapBounds()
            local hasCapture = false
            local tileSize = mapSize / localMapTileCount
            for _, tile in ipairs(getLocalMapTiles() or {}) do
                hasCapture = drawCellCapture(
                    tile.material,
                    mapX + tile.column * tileSize,
                    mapY + tile.row * tileSize,
                    tileSize,
                    tileSize
                ) or hasCapture
            end
            if hasCapture then
                local player = LocalPlayer()
                if IsValid(player) then
                    local position = player:GetPos()
                    local playerX = mapX + mapSize * 0.5 + position.x / localMapSpan * mapSize
                    local playerY = mapY + mapSize * 0.5 - position.y / localMapSpan * mapSize
                    local cursorX, cursorY = self:CursorPos()
                    if (cursorX - playerX) ^ 2 + (cursorY - playerY) ^ 2 <= 144 then
                        self.LandmarkTooltipText = player:Nick()
                    end
                    surface.SetDrawColor(8, 10, 12, 255)
                    surface.DrawRect(playerX - 8, playerY - 8, 16, 16)
                    surface.SetDrawColor(240, 244, 250, 255)
                    surface.DrawOutlinedRect(playerX - 6, playerY - 6, 12, 12, 2)
                    surface.SetDrawColor(35, 160, 226, 255)
                    surface.DrawRect(playerX - 3, playerY - 3, 6, 6)

                    for _, otherPlayer in ipairs(getAllPlayers()) do
                        if otherPlayer ~= player and IsValid(otherPlayer) and otherPlayer:Alive() then
                            local otherPosition = otherPlayer:GetPos()
                            local otherX = mapX + mapSize * 0.5 + otherPosition.x / localMapSpan * mapSize
                            local otherY = mapY + mapSize * 0.5 - otherPosition.y / localMapSpan * mapSize
                            if (cursorX - otherX) ^ 2 + (cursorY - otherY) ^ 2 <= 144 then
                                self.LandmarkTooltipText = otherPlayer:Nick()
                            end
                            surface.SetDrawColor(8, 20, 13, 255)
                            surface.DrawRect(otherX - 7, otherY - 7, 14, 14)
                            surface.SetDrawColor(236, 255, 241, 255)
                            surface.DrawOutlinedRect(otherX - 5, otherY - 5, 10, 10, 2)
                            surface.SetDrawColor(52, 220, 176, 255)
                            surface.DrawRect(otherX - 2, otherY - 2, 4, 4)
                        end
                    end
                end
            else
                draw.SimpleText("LOCAL MAP UNAVAILABLE", "DermaDefaultBold", width * 0.5, height * 0.5, MapColors.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            self:DrawLandmarkTooltip(width, height)
            return
        end

        local mapX, mapY, mapSize = self:GetMapBounds()
        local renderMode = WorldMap.RenderMode
        local hasRenderMaterial = false
        if renderMode == "default" then
            for _, layerId in ipairs(WorldMap.LayerOrder) do
                local layer = getLayerById(layerId)
                if layer and WorldMap.EnabledLayers[layer.id] then
                    local material = getMaterial(layer.id)
                    if material and not material:IsError() then
                        surface.SetMaterial(material)
                        surface.SetDrawColor(255, 255, 255, 255)
                        surface.DrawTexturedRect(mapX, mapY, mapSize, mapSize)
                    end
                end
            end

            local gridMaterial = getMaterial("grid")
            if gridMaterial and not gridMaterial:IsError() then
                surface.SetMaterial(gridMaterial)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(mapX, mapY, mapSize, mapSize)
            end
        else
            local material = getRenderModeMaterial(renderMode)
            hasRenderMaterial = material and not material:IsError()
            if hasRenderMaterial then
                surface.SetMaterial(material)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(mapX, mapY, mapSize, mapSize)
            end
            for _, layerId in ipairs({ "safe_zones", "landmarks" }) do
                local annotationMaterial = getMaterial(layerId)
                if annotationMaterial and not annotationMaterial:IsError() then
                    surface.SetMaterial(annotationMaterial)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(mapX, mapY, mapSize, mapSize)
                end
            end
        end

        local gridWidth = tonumber(worldData.world.grid[1]) or 1
        local gridHeight = tonumber(worldData.world.grid[2]) or 1
        local cellWidth = mapSize / gridWidth
        local cellHeight = mapSize / gridHeight

        if renderMode == "satellite" then
            drawSatelliteBlockades(worldData, mapX, mapY, cellWidth, cellHeight)
        end

        local player = LocalPlayer()
        local playerCell
        if IsValid(player) then
            playerCell = getPlayerMapCell(player)
            drawWaypointPath(getWaypointPath(playerCell), mapX, mapY, cellWidth, cellHeight)
        end

        if WorldMap.SelectedCell then
            local selectionAlpha = math.floor(140 + 115 * (0.5 + 0.5 * math.sin(RealTime() * 5)))
            drawCellOutline(WorldMap.SelectedCell, mapX, mapY, cellWidth, Color(245, 214, 80, selectionAlpha))
        end
        if WorldMap.WaypointCell then
            drawWaypoint(WorldMap.WaypointCell, mapX, mapY, cellWidth)
        end

        if playerCell then
            local gridX, gridY = getCellGridCoordinates(playerCell)
            if gridX and gridY then
                local playerX = mapX + (gridX + 0.5) * cellWidth
                local playerY = mapY + (gridY + 0.5) * cellHeight
                surface.SetDrawColor(8, 10, 12, 255)
                surface.DrawRect(playerX - 8, playerY - 8, 16, 16)
                surface.SetDrawColor(240, 244, 250, 255)
                surface.DrawOutlinedRect(playerX - 6, playerY - 6, 12, 12, 2)
                surface.SetDrawColor(35, 160, 226, 255)
                surface.DrawRect(playerX - 3, playerY - 3, 6, 6)
            end
        end

        if renderMode == "default" or renderMode == "satellite" then
            drawFixedMapOverlays(worldData, width, height)
        end
        local cursorX, cursorY = self:CursorPos()
        self:UpdateLandmarkTooltip(cursorX, cursorY)
        self:DrawLandmarkTooltip(width, height)
    end

    function canvas:OnMousePressed(mouseCode)
        if mouseCode == MOUSE_RIGHT then
            if WorldMap.RenderMode == "map" then
                return
            end
            local cursorX, cursorY = self:CursorPos()
            local waypointCell = self:GetCellAt(cursorX, cursorY)
            if not waypointCell then
                return
            end
            onSelect(waypointCell)
            WorldMap.WaypointCell = waypointCell
            WorldMap.WaypointProfile = ZM_World.ActiveProfile
            WorldMap.WaypointPath = nil
            WorldMap:SaveCellState("waypoint_cell", WorldMap.WaypointCell)
            return
        end
        if mouseCode ~= MOUSE_LEFT then
            return
        end

        self.FocusAnimation = nil
        self.Dragging = true
        self.DragStartX, self.DragStartY = self:CursorPos()
        self.StartPanX = self.PanX
        self.StartPanY = self.PanY
        self:MouseCapture(true)
    end

    function canvas:OnCursorMoved(cursorX, cursorY)
        self:UpdateLandmarkTooltip(cursorX, cursorY)
        if not self.Dragging then
            return
        end

        self.PanX = self.StartPanX + cursorX - self.DragStartX
        self.PanY = self.StartPanY + cursorY - self.DragStartY
        self:SaveViewport()
    end

    function canvas:OnMouseReleased(mouseCode)
        if mouseCode ~= MOUSE_LEFT or not self.Dragging then
            return
        end

        local cursorX, cursorY = self:CursorPos()
        local wasClick = math.abs(cursorX - self.DragStartX) < 5 and math.abs(cursorY - self.DragStartY) < 5
        self.Dragging = false
        self:MouseCapture(false)
        self:PersistViewport()
        if wasClick and WorldMap.RenderMode ~= "map" then
            onSelect(self:GetCellAt(cursorX, cursorY))
        end
    end

    function canvas:OnMouseWheeled(delta)
        self.FocusAnimation = nil
        local cursorX, cursorY = self:CursorPos()
        local mapX, mapY, oldMapSize = self:GetMapBounds()
        local mapRatioX = (cursorX - mapX) / oldMapSize
        local mapRatioY = (cursorY - mapY) / oldMapSize
        self.Zoom = math.Clamp(self.Zoom * (delta > 0 and 1.2 or (1 / 1.2)), 0.1, 32)
        local _, _, newMapSize = self:GetMapBounds()
        self.PanX = cursorX - self:GetWide() * 0.5 + newMapSize * 0.5 - mapRatioX * newMapSize
        self.PanY = cursorY - self:GetTall() * 0.5 + newMapSize * 0.5 - mapRatioY * newMapSize
        self:PersistViewport()
        return true
    end

    return canvas
end

local function formatCellValue(value)
    value = tostring(value or "")
    if value == "" then
        return "None"
    end

    value = string.gsub(value, "[_-]", " ")
    return string.gsub(value, "(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
end

local function getCellTransportSummary(cell)
    local transport = cell.transport or {}
    local details = {}
    if transport.bridge then
        table.insert(details, "Bridge crossing")
    end
    if transport.diagonal then
        table.insert(details, "Diagonal motorway")
    end
    local rampExits = transport.rampExits
    local rampExitText = type(rampExits) == "table" and table.concat(rampExits, ", ") or tostring(rampExits or "")
    if rampExitText ~= "" then
        table.insert(details, "Motorway ramp: " .. rampExitText)
    end
    if #details == 0 then
        return "Standard road network"
    end

    return table.concat(details, " / ")
end

local function getCellAccessSummary(cell)
    local exits = {}
    for _, exit in ipairs(cell.exits or {}) do
        local modes = {}
        for _, mode in ipairs(exit.modes or {}) do
            local label = formatCellValue(mode.type)
            if mode.blocked then
                label = label .. " blocked"
            end
            table.insert(modes, label)
        end
        if #modes > 0 then
            table.insert(exits, tostring(exit.direction) .. ": " .. table.concat(modes, " / "))
        end
    end

    return #exits > 0 and table.concat(exits, ", ") or "No connected routes"
end

local function getCellBarricadeDirections(cell)
    local directions = {}
    for _, exit in ipairs(cell.exits or {}) do
        for _, mode in ipairs(exit.modes or {}) do
            if mode.type == "road" and mode.blocked then
                directions[tostring(exit.direction)] = true
                break
            end
        end
    end

    return directions
end

local function drawCellBarricade(previewX, previewY, previewSize, direction)
    local margin = math.max(5, math.floor(previewSize * 0.11))
    local depth = math.max(5, math.floor(previewSize * 0.09))
    local startX, startY, width, height
    if direction == "N" then
        startX, startY, width, height = previewX + margin, previewY + margin, previewSize - margin * 2, depth
    elseif direction == "E" then
        startX, startY, width, height = previewX + previewSize - margin - depth, previewY + margin, depth, previewSize - margin * 2
    elseif direction == "S" then
        startX, startY, width, height = previewX + margin, previewY + previewSize - margin - depth, previewSize - margin * 2, depth
    elseif direction == "W" then
        startX, startY, width, height = previewX + margin, previewY + margin, depth, previewSize - margin * 2
    else
        return
    end

    surface.SetDrawColor(18, 12, 12, 235)
    surface.DrawRect(startX - 1, startY - 1, width + 2, height + 2)
    surface.SetDrawColor(MapColors.redBright.r, MapColors.redBright.g, MapColors.redBright.b, 255)
    surface.DrawRect(startX, startY, width, height)
    surface.SetDrawColor(255, 225, 225, 235)
    local stripeSize = math.max(3, math.floor(depth * 0.65))
    if direction == "N" or direction == "S" then
        for stripeX = startX + 2, startX + width - 2, stripeSize * 2 do
            surface.DrawRect(stripeX, startY + 1, math.min(stripeSize, startX + width - 1 - stripeX), height - 2)
        end
    else
        for stripeY = startY + 2, startY + height - 2, stripeSize * 2 do
            surface.DrawRect(startX + 1, stripeY, width - 2, math.min(stripeSize, startY + height - 1 - stripeY))
        end
    end
end

local function getCellMetroSummary(cell)
    local metroStop = ZM_World:GetMetroStop(cell)
    local metroLines = ZM_World:GetMetroLines(cell)
    local details = {}
    if metroStop and metroStop.name then
        table.insert(details, metroStop.name)
    end
    if #metroLines > 0 then
        local lineNames = {}
        for _, line in ipairs(metroLines) do
            table.insert(lineNames, line.name or tostring(line))
        end
        table.insert(details, table.concat(lineNames, ", "))
    end

    return #details > 0 and table.concat(details, " / ") or nil
end

local function wrapCellInspectorText(text, maxWidth)
    surface.SetFont("DermaDefault")
    local lines = {}
    for paragraph in string.gmatch(tostring(text) .. "\n", "(.-)\n") do
        local line = ""
        for word in string.gmatch(paragraph, "%S+") do
            local candidate = line == "" and word or line .. " " .. word
            if line ~= "" and surface.GetTextSize(candidate) > maxWidth then
                table.insert(lines, line)
                line = word
            else
                line = candidate
            end
        end
        if line ~= "" then
            table.insert(lines, line)
        end
    end

    return #lines > 0 and lines or { "None" }
end

local function createCellInspector(parent)
    local inspector = vgui.Create("DScrollPanel", parent)
    local card = vgui.Create("DPanel", inspector)
    card:Dock(TOP)
    card.Cell = nil
    card.Rows = {}

    function card:SetCell(cell)
        self.Cell = cell
        self.Rows = {}
        if cell then
            local district = ZM_World:GetDistrict(cell)
            local environment = ZM_World:GetEnvironment(cell) or {}
            local safeZone = ZM_World:GetSafeZone(cell)
            local landmarks = ZM_World:GetLandmarks(cell) or {}
            local terrainDetails = formatCellValue(environment.terrain)
            if #(environment.tags or {}) > 0 then
                terrainDetails = terrainDetails .. " / " .. table.concat(environment.tags, ", ")
            end

            local state = cell.building and "Building present" or "Open terrain"
            if cell.deadZone then
                state = state .. " / Dead zone"
            end
            local metroDetails = getCellMetroSummary(cell)

            table.insert(self.Rows, { kind = "radiation", value = ZM_World:GetRadiationIntensity(cell) })
            table.insert(self.Rows, { kind = "danger", value = ZM_World:GetDangerIntensity(cell) })
            table.insert(self.Rows, { label = "District", value = district and district.name or "Unassigned" })
            table.insert(self.Rows, { label = "Terrain", value = terrainDetails })
            table.insert(self.Rows, { label = "Cell type", value = formatCellValue(cell.profile) .. " / " .. formatCellValue(cell.topology) })
            table.insert(self.Rows, { label = "State", value = state })
            if safeZone and safeZone.name then
                table.insert(self.Rows, { label = "Safe zone", value = safeZone.name })
            end
            if #landmarks > 0 then
                table.insert(self.Rows, { label = "Landmarks", value = table.concat(landmarks, ", ") })
            end
            table.insert(self.Rows, { label = "Entrances", value = #(cell.entrances or {}) > 0 and table.concat(cell.entrances, ", ") or "None" })
            table.insert(self.Rows, { label = "Routes", value = getCellAccessSummary(cell) })
            table.insert(self.Rows, { label = "Transport", value = getCellTransportSummary(cell) })
            if metroDetails then
                table.insert(self.Rows, { label = "Metro", value = metroDetails })
            end
        end
        self.LastLayoutWidth = nil
        self:InvalidateLayout(true)
    end

    function card:BuildLayout(width)
        local padding = 8
        local previewSize = math.max(54, math.min(112, width - padding * 2))
        local rows = {}
        local y = 43 + previewSize + 8
        if not self.Cell then
            y = 36
        end

        for _, row in ipairs(self.Rows) do
            if row.kind then
                table.insert(rows, { row = row, y = y, height = 27 })
                y = y + 31
            else
                local valueLines = wrapCellInspectorText(row.value, width - padding * 2)
                local rowHeight = 15 + #valueLines * 13 + 5
                table.insert(rows, { row = row, y = y, lines = valueLines, height = rowHeight })
                y = y + rowHeight
            end
        end

        self.PreviewSize = previewSize
        self.LayoutRows = rows
        self.LastLayoutWidth = width
        self:SetTall(y + padding)
    end

    function card:PerformLayout(width)
        self:BuildLayout(width)
    end

    function card:Paint(width, height)
        if self.LastLayoutWidth ~= width then
            self:BuildLayout(width)
        end

        local padding = 8
        surface.SetDrawColor(MapColors.panel.r, MapColors.panel.g, MapColors.panel.b, 252)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(MapColors.border.r, MapColors.border.g, MapColors.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        draw.SimpleText("CELL INSPECTOR", "DermaDefaultBold", padding, 8, MapColors.redBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        if not self.Cell then
            draw.SimpleText("Select a cell on the map", "DermaDefault", padding, 27, MapColors.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            return
        end

        local worldX, worldY = ZM_World:GetWorldCoordinates(self.Cell)
        draw.SimpleText(string.format("CELL %d, %d", worldX or self.Cell.x, worldY or self.Cell.y), "DermaDefaultBold", padding, 22, MapColors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local previewX = padding
        local previewY = 41
        local previewSize = self.PreviewSize
        local previewMaterial = getCellRenderMaterial(self.Cell)
        surface.SetDrawColor(5, 7, 9, 255)
        surface.DrawRect(previewX, previewY, previewSize, previewSize)
        if previewMaterial and not previewMaterial:IsError() then
            surface.SetMaterial(previewMaterial)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(previewX, previewY, previewSize, previewSize)
        else
            draw.SimpleText("RENDER", "DermaDefaultBold", previewX + previewSize * 0.5, previewY + previewSize * 0.5 - 6, Color(164, 174, 182), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("UNAVAILABLE", "DermaDefault", previewX + previewSize * 0.5, previewY + previewSize * 0.5 + 8, Color(164, 174, 182), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        for direction in pairs(getCellBarricadeDirections(self.Cell)) do
            drawCellBarricade(previewX, previewY, previewSize, direction)
        end
        surface.SetDrawColor(MapColors.border.r, MapColors.border.g, MapColors.border.b, 255)
        surface.DrawOutlinedRect(previewX, previewY, previewSize, previewSize, 1)

        for _, layoutRow in ipairs(self.LayoutRows or {}) do
            local row = layoutRow.row
            local y = layoutRow.y
            if row.kind == "radiation" then
                draw.SimpleText("RADIATION", "DermaDefaultBold", padding, y, MapColors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                local barY = y + 15
                local barWidth = width - padding * 2
                local intensity = math.Clamp(tonumber(row.value) or 0, 0, 1)
                surface.SetDrawColor(37, 44, 50, 255)
                surface.DrawRect(padding, barY, barWidth, 8)
                if intensity > 0 then
                    surface.SetDrawColor(math.floor(112 + intensity * 143), math.floor(214 - intensity * 152), 58, 255)
                    surface.DrawRect(padding + 1, barY + 1, math.max(1, (barWidth - 2) * intensity), 6)
                end
                surface.SetDrawColor(90, 102, 111, 255)
                surface.DrawOutlinedRect(padding, barY, barWidth, 8, 1)
            elseif row.kind == "danger" then
                draw.SimpleText("DANGER", "DermaDefaultBold", padding, y, MapColors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                local starCount = math.Clamp(math.ceil((tonumber(row.value) or 0) * 5), 0, 5)
                for starIndex = 1, 5 do
                    local color = starIndex <= starCount and MapColors.redBright or MapColors.raised
                    draw.SimpleText("*", "DermaDefaultBold", padding + (starIndex - 1) * 16, y + 13, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            else
                draw.SimpleText(string.upper(row.label), "DermaDefaultBold", padding, y, MapColors.redBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                for lineIndex, line in ipairs(layoutRow.lines) do
                    draw.SimpleText(line, "DermaDefault", padding, y + 14 + (lineIndex - 1) * 13, MapColors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            end
        end
    end

    function inspector:SetCell(cell)
        card:SetCell(cell)
    end

    card:SetCell(nil)
    return inspector
end

function WorldMap:Open()
    self:LoadPersistentState()
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("WORLD MAP")
    local horizontalMargin = math.max(16, math.floor(ScrW() * 0.025))
    local verticalMargin = math.max(16, math.floor(ScrH() * 0.025))
    local maximumWidth = math.max(1, ScrW() - horizontalMargin * 2)
    local maximumHeight = math.max(1, ScrH() - verticalMargin * 2)
    local preferredAspectRatio = 1.45
    local frameWidth = math.min(1320, maximumWidth, maximumHeight * preferredAspectRatio)
    local frameHeight = frameWidth / preferredAspectRatio
    frame:SetSize(math.floor(frameWidth), math.floor(frameHeight))
    frame:Center()
    frame:MakePopup()
    self.Frame = frame

    local sidebar = vgui.Create("DPanel", frame)
    sidebar:Dock(LEFT)
    sidebar:SetWide(math.Clamp(math.floor(frameWidth * 0.17), 120, 174))
    sidebar.Paint = function(_, width, height)
        surface.SetDrawColor(MapColors.panel.r, MapColors.panel.g, MapColors.panel.b, 255)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(MapColors.border.r, MapColors.border.g, MapColors.border.b, 255)
        surface.DrawRect(width - 2, 0, 2, height)
    end

    local title = vgui.Create("DLabel", sidebar)
    title:Dock(TOP)
    title:DockMargin(10, 12, 10, 8)
    title:SetFont("DermaDefaultBold")
    title:SetText("MAP")
    title:SetTextColor(MapColors.redBright)

    local sidebarView = "layers"
    local directoryMode = "landmarks"
    local sidebarTabs = vgui.Create("DPanel", sidebar)
    sidebarTabs:Dock(TOP)
    sidebarTabs:DockMargin(8, 0, 8, 6)
    sidebarTabs:SetTall(24)
    sidebarTabs.Paint = function(_, width, height)
        surface.SetDrawColor(MapColors.black.r, MapColors.black.g, MapColors.black.b, 255)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(MapColors.border.r, MapColors.border.g, MapColors.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local sidebarContent = vgui.Create("DPanel", sidebar)
    sidebarContent:Dock(TOP)
    sidebarContent:DockMargin(8, 0, 8, 2)
    sidebarContent:SetTall(math.Clamp(math.floor(frameHeight * 0.4), 168, 300))
    sidebarContent.Paint = function() end

    local layersContent = vgui.Create("DPanel", sidebarContent)
    layersContent:Dock(FILL)
    layersContent.Paint = function() end

    local placesContent = vgui.Create("DPanel", sidebarContent)
    placesContent:Dock(FILL)
    placesContent:SetVisible(false)
    placesContent.Paint = function() end

    local layerCheckboxes = {}
    local selectAllButton = vgui.Create("DButton", layersContent)
    selectAllButton:Dock(TOP)
    selectAllButton:DockMargin(2, 0, 2, 6)
    selectAllButton:SetText("Select All")
    selectAllButton.DoClick = function()
        for _, layer in ipairs(self.Layers) do
            self.EnabledLayers[layer.id] = true
            layerCheckboxes[layer.id]:SetValue(1)
        end
    end

    local layerList = vgui.Create("DScrollPanel", layersContent)
    layerList:Dock(FILL)

    local directoryModeTabs = vgui.Create("DPanel", placesContent)
    directoryModeTabs:Dock(TOP)
    directoryModeTabs:DockMargin(0, 0, 0, 6)
    directoryModeTabs:SetTall(50)
    directoryModeTabs.Paint = function() end

    local directoryList = vgui.Create("DScrollPanel", placesContent)
    directoryList:Dock(FILL)

    local resetButton = vgui.Create("DButton", sidebar)
    resetButton:Dock(TOP)
    resetButton:DockMargin(10, 4, 10, 4)
    resetButton:SetText("Reset View")

    local cellInspector = createCellInspector(sidebar)
    cellInspector:Dock(FILL)
    cellInspector:DockMargin(10, 4, 10, 10)

    local function selectCell(cell)
        WorldMap.SelectedCell = cell
        WorldMap:SaveCellState("selected_cell", cell)
        cellInspector:SetCell(cell)
    end

    local canvas = createMapCanvas(frame, selectCell)
    canvas:Dock(FILL)
    canvas:DockMargin(8, 8, 8, 8)

    resetButton.DoClick = function()
        canvas:ResetView()
    end

    local rebuildDirectory
    local rebuildLayerControls
    local setSidebarView
    local function createSidebarTab(parent, view, label)
        local button = vgui.Create("DButton", parent)
        button:SetText("")
        button.Paint = function(panel, width, height)
            local active = sidebarView == view
            surface.SetDrawColor(active and MapColors.raised.r or MapColors.panel.r, active and MapColors.raised.g or MapColors.panel.g, active and MapColors.raised.b or MapColors.panel.b, 255)
            surface.DrawRect(0, 0, width, height)
            if active then
                surface.SetDrawColor(MapColors.redBright.r, MapColors.redBright.g, MapColors.redBright.b, 255)
                surface.DrawRect(0, height - 2, width, 2)
            end
            draw.SimpleText(label, "DermaDefaultBold", width * 0.5, height * 0.5, active and MapColors.text or MapColors.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            setSidebarView(view)
        end
        return button
    end

    local layersTabButton = createSidebarTab(sidebarTabs, "layers", "LAYERS")
    layersTabButton:Dock(LEFT)
    layersTabButton:SetWide(math.floor((sidebar:GetWide() - 16) * 0.5))
    local placesTabButton = createSidebarTab(sidebarTabs, "places", "PLACES")
    placesTabButton:Dock(FILL)

    local function createDirectoryTab(mode, label)
        local button = vgui.Create("DButton", directoryModeTabs)
        button:SetText("")
        button.Paint = function(_, width, height)
            local active = directoryMode == mode
            surface.SetDrawColor(active and MapColors.raised.r or MapColors.panel.r, active and MapColors.raised.g or MapColors.panel.g, active and MapColors.raised.b or MapColors.panel.b, 255)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(active and MapColors.redBright.r or MapColors.border.r, active and MapColors.redBright.g or MapColors.border.g, active and MapColors.redBright.b or MapColors.border.b, 255)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(label, "DermaDefaultBold", width * 0.5, height * 0.5, active and MapColors.text or MapColors.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            directoryMode = mode
            rebuildDirectory()
        end
        return button
    end

    local landmarksButton = createDirectoryTab("landmarks", "LANDMARKS")
    landmarksButton:Dock(TOP)
    landmarksButton:SetTall(24)
    local safeZonesButton = createDirectoryTab("safe_zones", "SAFE ZONES")
    safeZonesButton:Dock(TOP)
    safeZonesButton:SetTall(24)

    local function addDirectoryEntry(entry)
        local button = vgui.Create("DButton", directoryList)
        button:Dock(TOP)
        button:DockMargin(0, 0, 0, 3)
        button:SetTall(36)
        button:SetText("")
        local radiation = math.floor(ZM_World:GetRadiationIntensity(entry.cell) * 100 + 0.5)
        local danger = math.floor(ZM_World:GetDangerIntensity(entry.cell) * 100 + 0.5)
        button:SetTooltip(string.format("Radiation: %d%%\nDanger: %d%%", radiation, danger))
        button.Paint = function(panel, width, height)
            local hovered = panel:IsHovered()
            surface.SetDrawColor(hovered and MapColors.raised.r or MapColors.panel.r, hovered and MapColors.raised.g or MapColors.panel.g, hovered and MapColors.raised.b or MapColors.panel.b, 255)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(hovered and MapColors.redBright.r or MapColors.border.r, hovered and MapColors.redBright.g or MapColors.border.g, hovered and MapColors.redBright.b or MapColors.border.b, 255)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(entry.label, "DermaDefaultBold", 7, 6, MapColors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(entry.coordinates, "DermaDefault", 7, 20, MapColors.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        button.DoClick = function()
            if WorldMap.RenderMode == "map" then
                WorldMap:SetRenderMode("default")
                canvas:LoadRenderViewport()
                rebuildLayerControls()
            end
            selectCell(entry.cell)
            canvas:FocusCell(entry.cell)
        end
    end

    rebuildDirectory = function()
        directoryList:Clear()
        local worldData = getWorldData()
        local entries = {}
        if directoryMode == "landmarks" then
            for _, cell in ipairs(worldData and worldData.cells or {}) do
                for _, landmark in ipairs(ZM_World:GetLandmarks(cell) or {}) do
                    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
                    table.insert(entries, {
                        label = landmark,
                        coordinates = string.format("CELL %d, %d", worldX or cell.x, worldY or cell.y),
                        danger = ZM_World:GetDangerIntensity(cell),
                        cell = cell
                    })
                end
            end
        else
            for _, safeZone in ipairs(worldData and worldData.safeZones or {}) do
                local cell = ZM_World:GetCellById(safeZone.cell)
                if cell and safeZone.name then
                    local worldX, worldY = ZM_World:GetWorldCoordinates(cell)
                    table.insert(entries, {
                        label = safeZone.name,
                        coordinates = string.format("CELL %d, %d", worldX or cell.x, worldY or cell.y),
                        cell = cell
                    })
                end
            end
        end

        table.sort(entries, function(left, right)
            if directoryMode == "landmarks" and left.danger ~= right.danger then
                return left.danger > right.danger
            end
            local leftLabel = string.lower(left.label)
            local rightLabel = string.lower(right.label)
            return leftLabel == rightLabel and left.cell.id < right.cell.id or leftLabel < rightLabel
        end)
        if #entries == 0 then
            local emptyLabel = vgui.Create("DLabel", directoryList)
            emptyLabel:Dock(TOP)
            emptyLabel:DockMargin(7, 8, 7, 0)
            emptyLabel:SetFont("DermaDefault")
            emptyLabel:SetText("No entries available")
            emptyLabel:SetTextColor(MapColors.muted)
            emptyLabel:SetWrap(true)
            emptyLabel:SetTall(32)
            return
        end
        for _, entry in ipairs(entries) do
            addDirectoryEntry(entry)
        end
    end

    setSidebarView = function(view)
        sidebarView = view
        layersContent:SetVisible(view == "layers")
        placesContent:SetVisible(view == "places")
        sidebarContent:InvalidateLayout(true)
    end

    rebuildLayerControls = function()
        layerList:Clear()
        layerCheckboxes = {}
        local layerControlsEnabled = WorldMap.RenderMode == "default"
        selectAllButton:SetEnabled(layerControlsEnabled)

        local function addLayerControl(layer, stackIndex)
            local row = vgui.Create("DPanel", layerList)
            row:Dock(TOP)
            row:DockMargin(4, 2, 4, 2)
            row:SetTall(20)
            row.Paint = function() end

            if stackIndex then
                local moveUpButton = vgui.Create("DButton", row)
                moveUpButton:Dock(RIGHT)
                moveUpButton:SetWide(19)
                moveUpButton:SetText("^")
                moveUpButton:SetTooltip("Move layer higher")
                moveUpButton:SetEnabled(layerControlsEnabled and stackIndex < #self.LayerOrder)
                moveUpButton.DoClick = function()
                    if self:MoveLayer(layer.id, 1) then
                        rebuildLayerControls()
                    end
                end

                local moveDownButton = vgui.Create("DButton", row)
                moveDownButton:Dock(RIGHT)
                moveDownButton:SetWide(19)
                moveDownButton:SetText("v")
                moveDownButton:SetTooltip("Move layer lower")
                moveDownButton:SetEnabled(layerControlsEnabled and stackIndex > 1)
                moveDownButton.DoClick = function()
                    if self:MoveLayer(layer.id, -1) then
                        rebuildLayerControls()
                    end
                end
            end

            local layerId = layer.id
            local checkbox = vgui.Create("DCheckBoxLabel", row)
            layerCheckboxes[layerId] = checkbox
            checkbox:Dock(FILL)
            checkbox:DockMargin(6, 1, 2, 0)
            checkbox:SetText(layer.label)
            checkbox:SetTextColor(MapColors.text)
            checkbox:SetValue(self.EnabledLayers[layerId] and 1 or 0)
            checkbox:SetEnabled(layerControlsEnabled)
            checkbox.OnChange = function(_, value)
                setLayerPreference(layerId, value)
                if (layerId == "landmarks" or layerId == "safe_zones") and not value then
                    canvas.LandmarkTooltipText = nil
                end
            end
        end

        for stackIndex = #self.LayerOrder, 1, -1 do
            addLayerControl(getLayerById(self.LayerOrder[stackIndex]), stackIndex)
        end
        addLayerControl(getLayerById("tables"), nil)
    end

    local renderModeControls = vgui.Create("DPanel", canvas)
    renderModeControls:SetSize(220, 26)
    renderModeControls.Paint = function(_, width, height)
        surface.SetDrawColor(MapColors.black.r, MapColors.black.g, MapColors.black.b, 235)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(MapColors.border.r, MapColors.border.g, MapColors.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end
    renderModeControls.Think = function(panel)
        local x = math.max(8, canvas:GetWide() - panel:GetWide() - 10)
        if panel.LastCanvasWidth ~= canvas:GetWide() then
            panel:SetPos(x, 10)
            panel.LastCanvasWidth = canvas:GetWide()
        end
    end

    local focusControls = vgui.Create("DPanel", canvas)
    focusControls:SetSize(58, 26)
    focusControls.Paint = function(_, width, height)
        surface.SetDrawColor(MapColors.black.r, MapColors.black.g, MapColors.black.b, 235)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(MapColors.border.r, MapColors.border.g, MapColors.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local playerFocusButton = vgui.Create("DButton", focusControls)
    playerFocusButton:Dock(LEFT)
    playerFocusButton:SetWide(29)
    playerFocusButton:SetText("")
    playerFocusButton:SetTooltip("Focus player")
    playerFocusButton.Paint = function(panel, buttonWidth, buttonHeight)
        local color = panel:IsEnabled() and MapColors.text or MapColors.muted
        local centerX = buttonWidth * 0.5
        local centerY = buttonHeight * 0.5
        surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
        surface.DrawOutlinedRect(centerX - 5, centerY - 5, 10, 10, 1)
        surface.DrawLine(centerX - 8, centerY, centerX - 5, centerY)
        surface.DrawLine(centerX + 5, centerY, centerX + 8, centerY)
        surface.DrawLine(centerX, centerY - 8, centerX, centerY - 5)
        surface.DrawLine(centerX, centerY + 5, centerX, centerY + 8)
        surface.DrawRect(centerX - 1, centerY - 1, 3, 3)
    end
    playerFocusButton.DoClick = function()
        local player = LocalPlayer()
        if not IsValid(player) then
            return
        end
        if WorldMap.RenderMode == "map" then
            canvas:FocusLocalPosition(player:GetPos())
            return
        end
        local playerCell = getPlayerMapCell(player)
        if playerCell then
            canvas:FocusCell(playerCell)
        end
    end

    local waypointFocusButton = vgui.Create("DButton", focusControls)
    waypointFocusButton:Dock(FILL)
    waypointFocusButton:SetText("")
    waypointFocusButton:SetTooltip("Focus waypoint")
    waypointFocusButton.Paint = function(panel, buttonWidth, buttonHeight)
        local color = panel:IsEnabled() and Color(246, 210, 48) or MapColors.muted
        local centerX = buttonWidth * 0.5
        local centerY = buttonHeight * 0.5
        surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
        surface.DrawLine(centerX, centerY - 7, centerX + 6, centerY)
        surface.DrawLine(centerX + 6, centerY, centerX, centerY + 7)
        surface.DrawLine(centerX, centerY + 7, centerX - 6, centerY)
        surface.DrawLine(centerX - 6, centerY, centerX, centerY - 7)
        surface.DrawRect(centerX - 1, centerY - 1, 3, 3)
    end
    waypointFocusButton.DoClick = function()
        local waypointCell = WorldMap.WaypointCell
        if not waypointCell or WorldMap.WaypointProfile ~= ZM_World.ActiveProfile then
            return
        end
        if WorldMap.RenderMode == "map" then
            WorldMap:SetRenderMode("default")
            canvas:LoadRenderViewport()
            rebuildLayerControls()
        end
        canvas:FocusCell(waypointCell)
    end

    focusControls.Think = function(panel)
        if panel.LastCanvasWidth ~= canvas:GetWide() then
            panel:SetPos(10, 10)
            panel.LastCanvasWidth = canvas:GetWide()
        end
        local player = LocalPlayer()
        local canFocusPlayer = IsValid(player) and (WorldMap.RenderMode == "map" or getPlayerMapCell(player) ~= nil)
        playerFocusButton:SetEnabled(canFocusPlayer)
        waypointFocusButton:SetEnabled(WorldMap.WaypointCell ~= nil and WorldMap.WaypointProfile == ZM_World.ActiveProfile)
    end

    local function addRenderModeButton(renderMode, label, width, available, unavailableTooltip)
        local button = vgui.Create("DButton", renderModeControls)
        button:Dock(LEFT)
        button:SetWide(width)
        button:SetText("")
        button:SetEnabled(available)
        if unavailableTooltip then
            button:SetTooltip(unavailableTooltip)
        end
        button.Paint = function(panel, buttonWidth, buttonHeight)
            local active = WorldMap.RenderMode == renderMode
            local enabled = panel:IsEnabled()
            surface.SetDrawColor(active and MapColors.raised.r or MapColors.panel.r, active and MapColors.raised.g or MapColors.panel.g, active and MapColors.raised.b or MapColors.panel.b, enabled and 255 or 145)
            surface.DrawRect(0, 0, buttonWidth, buttonHeight)
            if active then
                surface.SetDrawColor(MapColors.redBright.r, MapColors.redBright.g, MapColors.redBright.b, 255)
                surface.DrawRect(0, buttonHeight - 2, buttonWidth, 2)
            end
            draw.SimpleText(label, "DermaDefaultBold", buttonWidth * 0.5, buttonHeight * 0.5, enabled and MapColors.text or MapColors.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            if renderMode == "map" then
                local captured = WorldMap:CaptureCurrentMap()
                if not captured then
                    button:SetTooltip("No active world view is available to capture")
                    return
                end
            end
            if WorldMap:SetRenderMode(renderMode) then
                canvas:LoadRenderViewport()
                rebuildLayerControls()
            end
        end
    end

    local satelliteMaterial = getRenderModeMaterial("satellite")
    local satelliteAvailable = satelliteMaterial and not satelliteMaterial:IsError()
    if WorldMap.RenderMode == "satellite" and not satelliteAvailable then
        WorldMap:SetRenderMode("default")
    end
    addRenderModeButton("default", "DEFAULT", 68, true, "Map View")
    addRenderModeButton("satellite", "SATELLITE", 84, satelliteAvailable, "Satellite View")
    addRenderModeButton("map", "MAP", 66, true, "Level View")

    rebuildLayerControls()
    rebuildDirectory()
    setSidebarView("layers")

    selectCell(self.SelectedCell)
end

function WorldMap:Toggle()
    if IsValid(self.Frame) then
        self.Frame:Remove()
        return
    end

    self:Open()
end

concommand.Add("zombiesim_map", function()
    WorldMap:Toggle()
end)

concommand.Add("zombiesim_waypoint_status", function()
    local player = LocalPlayer()
    local playerCell = IsValid(player) and getPlayerMapCell(player) or nil
    local waypointCell = WorldMap.WaypointCell
    if not playerCell or not waypointCell or WorldMap.WaypointProfile ~= ZM_World.ActiveProfile then
        print("[ZombieSim] No active waypoint route.")
        return
    end

    local path, pathError = ZM_World:FindPath(playerCell, waypointCell, { mode = "any", allowBlocked = false })
    if not path then
        print("[ZombieSim] Waypoint route failed: " .. tostring(pathError))
        return
    end

    print(string.format("[ZombieSim] Waypoint route (%s): grid %d,%d to %d,%d", ZM_World.ActiveProfile, playerCell.x, playerCell.y, waypointCell.x, waypointCell.y))
    local previousMode
    for index, mode in ipairs(path.modes) do
        local cell = path.cells[index]
        local transport = cell.transport or {}
        if previousMode and previousMode ~= mode then
            local rampExits = transport.rampExits
            local rampExitText = type(rampExits) == "table" and table.concat(rampExits, ",") or tostring(rampExits or "")
            print(string.format("[ZombieSim] Mode change: %s to %s at grid %d,%d (ramp exits: %s; bridge: %s)", previousMode, mode, cell.x, cell.y, rampExitText, tostring(transport.bridge == true)))
        end
        if transport.bridge then
            print(string.format("[ZombieSim] Bridge segment: %s at grid %d,%d", mode, cell.x, cell.y))
        end
        previousMode = mode
    end
end)

hook.Add("Think", "ZM.WorldMap.M", function()
    local isDown = input.IsKeyDown(KEY_M)
    local isControlDown = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
    local isMapOpen = IsValid(WorldMap.Frame)
    local hasKeyboardFocus = IsValid(vgui.GetKeyboardFocus())
    if isDown and not isControlDown and not WorldMap.MDown and not gui.IsGameUIVisible() and (isMapOpen or not hasKeyboardFocus) then
        if isControlDown then
            local targetMode = WorldMap.RenderMode == "map" and "satellite" or "map"
            if targetMode ~= "map" or WorldMap:EnsureLocalMapCapture() then
                WorldMap:SetRenderMode(targetMode)
                if isMapOpen then
                    WorldMap.Frame:Remove()
                end
                WorldMap:Open()
            end
        else
            WorldMap:Toggle()
        end
    end
    WorldMap.MDown = isDown
end)

hook.Add("PostRender", "ZM.WorldMap.LocalMapRefresh", function()
    if IsValid(WorldMap.Frame) and WorldMap.RenderMode == "map" then
        WorldMap:RefreshLocalMapIfDue()
    end
end)