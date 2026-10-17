return function()
    local Contract = {}
    local photoVariants = { "clear", "atmospheric" }
    local cubemapReason = "No reliable native cubemap-bake marker is available; VBSP defaults do not count."

    local function readUInt32(value, offset)
        local first, second, third, fourth = string.byte(value, offset, offset + 3)
        return ((first * 256 + second) * 256 + third) * 256 + fourth
    end

    local function isValidMapName(value)
        return type(value) == "string" and value ~= "" and string.match(value, "^[%w_%-]+$") ~= nil
    end

    function Contract.ParsePngHeader(value)
        if type(value) ~= "string" or #value < 45 then
            return nil, "PNG is truncated."
        end
        if string.sub(value, 1, 8) ~= "\137PNG\r\n\26\n" then
            return nil, "PNG signature is invalid."
        end
        if string.sub(value, 9, 12) ~= "\0\0\0\13" or string.sub(value, 13, 16) ~= "IHDR" then
            return nil, "PNG header is invalid."
        end
        if string.sub(value, -12, -9) ~= "\0\0\0\0" or string.sub(value, -8, -5) ~= "IEND" then
            return nil, "PNG end marker is missing."
        end

        local width = readUInt32(value, 17)
        local height = readUInt32(value, 21)
        if width < 1 or height < 1 then
            return nil, "PNG dimensions are invalid."
        end
        return { width = width, height = height }
    end

    function Contract.Classify(navmeshComplete, cubemapsComplete, photosComplete)
        local completeCount = 0
        if navmeshComplete == true then completeCount = completeCount + 1 end
        if cubemapsComplete == true then completeCount = completeCount + 1 end
        if photosComplete == true then completeCount = completeCount + 1 end
        if completeCount == 3 then return "green", completeCount end
        if completeCount == 0 then return "red", completeCount end
        return "orange", completeCount
    end

    local function validateManifest(manifest, manifestError)
        if type(manifest) ~= "table" then
            return false, manifestError or "Captured-world manifest is unavailable."
        end
        if manifest.schemaVersion ~= 1 or manifest.profile ~= "preview" then
            return false, "Captured-world manifest is invalid or is not for preview."
        end
        if type(manifest.variants) ~= "table" then
            return false, "Captured-world manifest has no variants."
        end
        return true
    end

    local function getPhotoStatus(cell, mapName, manifest, manifestValid, manifestError, files, variant)
        local status = { complete = false, variant = variant }
        if not manifestValid then
            status.reason = manifestError
            return status
        end

        local variantData = manifest.variants[variant]
        if type(variantData) ~= "table" or type(variantData.cells) ~= "table" or
            type(variantData.metadata) ~= "table" then
            status.reason = "Capture variant records are unavailable."
            return status
        end

        local cellId = tostring(cell.id)
        local expectedPath = "worlds/preview/captured/" .. variant .. "/cell_" .. cellId .. ".png"
        if variantData.cells[cellId] ~= expectedPath then
            status.reason = "Capture manifest has no current-cell image path."
            return status
        end

        local metadata = variantData.metadata[cellId]
        if type(metadata) ~= "table" or metadata.map ~= mapName then
            status.reason = "Capture was made for a different or unknown map."
            return status
        end

        status.path = "materials/" .. expectedPath
        local imageData = files.Read(status.path)
        local dimensions, imageError = Contract.ParsePngHeader(imageData)
        if not dimensions then
            status.reason = imageData == nil and "Cell photo is missing." or imageError
            return status
        end

        status.complete = true
        status.width = dimensions.width
        status.height = dimensions.height
        return status
    end

    function Contract.BuildSnapshot(worldData, manifest, files, manifestError, cubemapConfirmations)
        if type(worldData) ~= "table" or type(worldData.world) ~= "table" or type(worldData.cells) ~= "table" then
            return nil, "Preview world data is unavailable."
        end
        if type(files) ~= "table" or type(files.Exists) ~= "function" or
            type(files.Size) ~= "function" or type(files.Read) ~= "function" then
            return nil, "Cell Health file access is unavailable."
        end

        local grid = worldData.world.grid
        local width = type(grid) == "table" and tonumber(grid[1]) or nil
        local height = type(grid) == "table" and tonumber(grid[2]) or nil
        if not width or not height or width < 1 or height < 1 or width ~= math.floor(width) or
            height ~= math.floor(height) or #worldData.cells ~= width * height then
            return nil, "Preview world grid is incomplete or invalid."
        end

        local manifestValid, currentManifestError = validateManifest(manifest, manifestError)
        local snapshot = {
            profile = "preview",
            width = width,
            height = height,
            cells = {},
            photoManifestError = currentManifestError,
            cubemapNote = cubemapReason,
            summary = {
                total = #worldData.cells,
                green = 0,
                orange = 0,
                red = 0,
                navmeshCells = 0,
                navmeshMaps = 0,
                clearPhotoCells = 0,
                atmosphericPhotoCells = 0,
                photoCells = 0,
                cubemapCells = 0
            }
        }
        if manifestValid then snapshot.photoManifestError = nil end

        local navmeshByMap = {}
        local seenCellIds = {}
        for _, sourceCell in ipairs(worldData.cells) do
            local cellId = tonumber(sourceCell.id)
            local x = tonumber(sourceCell.x)
            local y = tonumber(sourceCell.y)
            if not cellId or cellId < 0 or cellId >= width * height or cellId ~= math.floor(cellId) or
                seenCellIds[cellId] or x ~= cellId % width or y ~= math.floor(cellId / width) then
                return nil, "Preview world contains an invalid or duplicate cell coordinate."
            end
            seenCellIds[cellId] = true

            local mapName = sourceCell.map
            local mapKey = isValidMapName(mapName) and mapName or ("invalid-map-" .. tostring(cellId))
            local navmesh = navmeshByMap[mapKey]
            if not navmesh then
                navmesh = { complete = false }
                if isValidMapName(mapName) then
                    navmesh.path = "maps/" .. mapName .. ".nav"
                    navmesh.exists = files.Exists(navmesh.path) == true
                    navmesh.size = navmesh.exists and (tonumber(files.Size(navmesh.path)) or 0) or 0
                    navmesh.complete = navmesh.exists and navmesh.size > 0
                    if not navmesh.complete then
                        navmesh.reason = navmesh.exists and "Navmesh file is empty." or "Navmesh file is missing."
                    end
                else
                    navmesh.reason = "Runtime map name is invalid."
                end
                navmeshByMap[mapKey] = navmesh
                snapshot.summary.navmeshMaps = snapshot.summary.navmeshMaps + 1
            end

            local photos = {}
            for _, variant in ipairs(photoVariants) do
                photos[variant] = getPhotoStatus(
                    sourceCell, mapName, manifest, manifestValid, currentManifestError, files, variant
                )
            end
            photos.complete = photos.clear.complete and photos.atmospheric.complete

            local confirmation = isValidMapName(mapName) and type(cubemapConfirmations) == "table"
                and cubemapConfirmations[string.lower(mapName)] or nil
            local cubemaps = {
                complete = type(confirmation) == "table" and confirmation.confirmed == true,
                state = type(confirmation) == "table" and confirmation.confirmed == true and "user-confirmed" or "unverified",
                reason = type(confirmation) == "table" and confirmation.confirmed == true
                    and "User confirmed buildcubemaps succeeded." or cubemapReason,
                confirmedAt = type(confirmation) == "table" and confirmation.confirmedAt or nil
            }
            local state = Contract.Classify(navmesh.complete, cubemaps.complete, photos.complete)
            local cell = {
                id = cellId,
                x = x,
                y = y,
                map = mapName,
                navmesh = navmesh,
                cubemaps = cubemaps,
                photos = photos,
                state = state
            }
            snapshot.cells[#snapshot.cells + 1] = cell

            if navmesh.complete then snapshot.summary.navmeshCells = snapshot.summary.navmeshCells + 1 end
            if photos.clear.complete then snapshot.summary.clearPhotoCells = snapshot.summary.clearPhotoCells + 1 end
            if photos.atmospheric.complete then
                snapshot.summary.atmosphericPhotoCells = snapshot.summary.atmosphericPhotoCells + 1
            end
            if photos.complete then snapshot.summary.photoCells = snapshot.summary.photoCells + 1 end
            if cubemaps.complete then snapshot.summary.cubemapCells = snapshot.summary.cubemapCells + 1 end
            snapshot.summary[state] = snapshot.summary[state] + 1
        end

        table.sort(snapshot.cells, function(left, right)
            if left.y == right.y then return left.x < right.x end
            return left.y < right.y
        end)
        return snapshot
    end

    function Contract.BuildBatchSelection(snapshot, selected)
        if type(snapshot) ~= "table" or type(snapshot.cells) ~= "table" or type(selected) ~= "table" then
            return nil, "Cell Health batch selection is invalid."
        end
        for _, key in ipairs({"navmesh", "photos", "cubemaps"}) do
            if type(selected[key]) ~= "boolean" then
                return nil, "Cell Health batch selection is invalid: " .. key
            end
        end
        if not selected.navmesh and not selected.photos and not selected.cubemaps then
            return nil, "Select at least one artifact to process."
        end

        local jobs = {}
        for _, cell in ipairs(snapshot.cells) do
            local job = {
                id = cell.id,
                navmesh = selected.navmesh and not cell.navmesh.complete or false,
                photos = selected.photos and not cell.photos.complete or false,
                cubemaps = selected.cubemaps and not cell.cubemaps.complete or false
            }
            if job.navmesh or job.photos or job.cubemaps then
                jobs[#jobs + 1] = job
            end
        end
        return jobs
    end

    return Contract
end
