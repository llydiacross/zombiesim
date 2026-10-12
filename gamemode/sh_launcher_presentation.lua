ZM_LauncherPresentation = ZM_LauncherPresentation or {}
local Presentation = ZM_LauncherPresentation

local function cellForLocation(world, location)
    local grid = world.world and world.world.grid
    local gridOrigin = world.world and world.world.gridOrigin
    local width, height = istable(grid) and tonumber(grid[1]), istable(grid) and tonumber(grid[2])
    if not width or not height or not istable(gridOrigin) then return nil, "world grid is invalid" end
    if location.state == "den" then
        for _, safeZone in ipairs(world.safeZones or {}) do
            if safeZone.id == location.safeZoneId then
                local index = tonumber(safeZone.cell)
                if not index then return nil, "saved den owner is invalid" end
                return world.cells and world.cells[index + 1], safeZone.name or safeZone.id,
                    index % width, math.floor(index / width)
            end
        end
        return nil, "saved den owner is missing"
    end
    local cellX, cellY = tonumber(location.cellX), tonumber(location.cellY)
    if not cellX or not cellY then
        return nil, "saved logical cell is invalid"
    end
    local rawX = cellX + (tonumber(gridOrigin[1]) or 0)
    local rawY = cellY + (tonumber(gridOrigin[2]) or 0)
    if rawX < 0 or rawX >= width or rawY < 0 or rawY >= height
        or rawX % 1 ~= 0 or rawY % 1 ~= 0 then
        return nil, "saved logical cell is outside the profile"
    end
    return world.cells and world.cells[rawY * width + rawX + 1], nil, rawX, rawY
end

function Presentation.ResolveCity(world, skyline, profile, location)
    if not istable(world) or not istable(world.world) or not istable(skyline) then
        return nil, "world or skyline data is missing"
    end
    if world.world.profileId ~= profile or skyline.profile ~= profile then
        return nil, "presentation profile does not match its assets"
    end
    if skyline.schemaVersion ~= 2 or skyline.templatePlanSha256 ~= world.world.templatePlanSha256
        or tonumber(skyline.cellSpan) ~= tonumber(world.world.cellBounds and world.world.cellBounds.neighbourPitch) then
        return nil, "skyline assets are stale"
    end
    if not istable(location) or not location.available then
        return nil, tostring(location and location.reason or "saved location is unavailable")
    end
    local cell, denLabel, rawX, rawY = cellForLocation(world, location)
    if not cell or not isstring(cell.map) then return nil, denLabel or "saved cell is missing" end
    local models = skyline.recipes and skyline.recipes[cell.map]
    local model = istable(models) and models[1]
    if not isstring(model) or model == "" then return nil, "selected cell skyline model is missing" end
    local width, height = tonumber(world.world.grid[1]), tonumber(world.world.grid[2])
    local cluster = {}
    for offsetY = -1, 1 do
        for offsetX = -1, 1 do
            local neighbourX, neighbourY = rawX + offsetX, rawY + offsetY
            if neighbourX >= 0 and neighbourX < width and neighbourY >= 0 and neighbourY < height then
                local neighbour = world.cells and world.cells[neighbourY * width + neighbourX + 1]
                local paths = neighbour and skyline.recipes and skyline.recipes[neighbour.map]
                for part, path in ipairs(paths or {}) do
                    if isstring(path) and path ~= "" then
                        cluster[#cluster + 1] = {
                            model = path,
                            map = neighbour.map,
                            offsetX = offsetX,
                            offsetY = offsetY,
                            part = part,
                            selected = offsetX == 0 and offsetY == 0
                        }
                    end
                end
            end
        end
    end
    return {
        profile = profile,
        state = location.state,
        cellX = tonumber(location.cellX),
        cellY = tonumber(location.cellY),
        safeZoneId = location.safeZoneId,
        label = denLabel or (string.upper(tostring(location.state or "city")) .. " / "
            .. tostring(location.cellX) .. ", " .. tostring(location.cellY)),
        map = cell.map,
        model = model,
        models = cluster,
        cellSpan = tonumber(skyline.cellSpan)
    }
end
