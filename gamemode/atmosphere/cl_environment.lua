// Shared outdoor eligibility, shelter traces, surface sampling and per-frame work deadline.
return function(Atmosphere, Modules)
    local Environment = Modules.Environment
    local Weather = Modules.Weather
    local Puddles = Modules.Puddles
    local Snow = Modules.Snow
    Environment.NextShelterCheckAt = 0
    local surfaceSites = Atmosphere.PuddleSites or {}
    Environment.SurfaceSites = surfaceSites
    Atmosphere.PuddleSites = surfaceSites
    Environment.SurfaceMap = Atmosphere.PuddleSiteMap
    Environment.WorldMinimum = Atmosphere.PuddleWorldMinimum
    Environment.WorldMaximum = Atmosphere.PuddleWorldMaximum
    Environment.IsSheltered = nil
    // Snow sampling, chunk meshing, chunk re-bakes and the puddle site scan share one per-frame time budget.
    // Each step always makes at least one unit of progress; the per-frame counts above remain upper caps.
    local atmosphereWorkBudgetSeconds = 0.0015
    // The loading screen hides a fresh map, so the preload may spend most of each frame building the cover.
    local atmospherePreloadWorkBudgetSeconds = 0.05

    local atmosphereWorkFrame = -1
    local atmosphereWorkDeadline = 0

    function Environment.GetAtmosphereWorkDeadline()
        local frame = FrameNumber()
        if frame ~= atmosphereWorkFrame then
            atmosphereWorkFrame = frame
            local budget = Snow.Cover.preloadStep ~= nil and atmospherePreloadWorkBudgetSeconds or atmosphereWorkBudgetSeconds
            atmosphereWorkDeadline = SysTime() + budget
        end
        return atmosphereWorkDeadline
    end
    Environment.SurfaceSiteCapacity = 192

    function Environment.HasOutdoorCityCells()
        if not ZM_World:IsLoaded() then return false end
        local cells = ZM_World:GetCellsForMap(game.GetMap())
        return type(cells) == "table" and #cells > 0
    end

    function Environment.IsOutdoorCityCell(player)
        if not IsValid(player) or not Environment.HasOutdoorCityCells() then return false end
        return not ZM_SafeZones:IsPlayerInside(player)
    end

    local shelterTraceStart = Vector()
    local shelterTraceEnd = Vector()
    local shelterTraceResult = {}
    local shelterTrace = {
        start = shelterTraceStart,
        endpos = shelterTraceEnd,
        mask = MASK_SOLID_BRUSHONLY,
        output = shelterTraceResult
    }

    function Environment.CheckShelter(player, now)
        if now < Environment.NextShelterCheckAt then return Environment.IsSheltered end
        Environment.NextShelterCheckAt = now + 0.5
        local origin = player:GetPos()
        shelterTraceStart:SetUnpacked(origin.x, origin.y, origin.z + 32)
        shelterTraceEnd:SetUnpacked(origin.x, origin.y, origin.z + 32 + 4096)
        shelterTrace.filter = player
        local trace = util.TraceLine(shelterTrace)
        Environment.IsSheltered = trace.Hit and not trace.HitSky
        Weather.Diagnostics.shelterCheckedAt = RealTime()
        Weather.Diagnostics.shelterTraceHit = trace.Hit == true
        Weather.Diagnostics.shelterTraceHitSky = trace.HitSky == true
        return Environment.IsSheltered
    end

    function Environment.EnsureSurfaceSites()
        local mapName = game.GetMap()
        if Environment.SurfaceMap == mapName and #surfaceSites == Environment.SurfaceSiteCapacity and Environment.WorldMinimum and Environment.WorldMaximum then
            Atmosphere.PuddleSiteStatus = "ready"
            return true
        end

        Atmosphere.PuddleSiteAttempts = (Atmosphere.PuddleSiteAttempts or 0) + 1
        // Worldspawn is never IsValid(); test the NULL entity and IsWorld instead.
        local world = game.GetWorld()
        if not world or world == NULL or not world:IsWorld() then
            Atmosphere.PuddleSiteStatus = "world entity unavailable"
            if Atmosphere.PuddleBoundsErrorMap ~= mapName then
                Atmosphere.PuddleBoundsErrorMap = mapName
                ErrorNoHalt("[ZombieSim] Cannot seed map puddles: world entity bounds are unavailable for " .. mapName .. ".\n")
            end
            return false
        end
        local minimum, maximum = world:WorldSpaceAABB()
        if not minimum or not maximum or maximum.x <= minimum.x or maximum.y <= minimum.y then
            minimum, maximum = world:GetRenderBounds()
            Atmosphere.PuddleBoundsSource = "render bounds"
        else
            Atmosphere.PuddleBoundsSource = "world AABB"
        end
        // City recipes carry the 3D skybox room above the playable cell; keep puddle and snow sampling below it.
        if ZM_Skybox and ZM_Skybox.ClampWorldBounds then
            minimum, maximum = ZM_Skybox:ClampWorldBounds(minimum, maximum)
        end
        if not minimum or not maximum or maximum.x <= minimum.x or maximum.y <= minimum.y or maximum.z <= minimum.z then
            Atmosphere.PuddleSiteStatus = "invalid world bounds"
            if Atmosphere.PuddleBoundsErrorMap ~= mapName then
                Atmosphere.PuddleBoundsErrorMap = mapName
                ErrorNoHalt("[ZombieSim] Cannot seed map puddles: invalid world bounds for " .. mapName .. ".\n")
            end
            return false
        end

        local width = maximum.x - minimum.x
        local height = maximum.y - minimum.y
        local margin = math.min(48, math.min(width, height) * 0.05)
        local minimumX = minimum.x + margin
        local maximumX = maximum.x - margin
        local minimumY = minimum.y + margin
        local maximumY = maximum.y - margin
        if maximumX <= minimumX or maximumY <= minimumY then
            Atmosphere.PuddleSiteStatus = "world bounds too small"
            return false
        end

        table.Empty(surfaceSites)
        Puddles.ResetSites()
        for index = 1, Environment.SurfaceSiteCapacity do
            local seed = mapName .. ":" .. index
            surfaceSites[index] = {
                index = index,
                position = Vector(
                    util.SharedRandom("ZM.PuddleSiteX:" .. seed, minimumX, maximumX),
                    util.SharedRandom("ZM.PuddleSiteY:" .. seed, minimumY, maximumY),
                    0
                )
            }
        end

        Environment.SurfaceMap = mapName
        Environment.WorldMinimum = minimum
        Environment.WorldMaximum = maximum
        Atmosphere.PuddleSiteMap = mapName
        Atmosphere.PuddleWorldMinimum = minimum
        Atmosphere.PuddleWorldMaximum = maximum
        Atmosphere.PuddleBoundsErrorMap = nil
        Atmosphere.PuddleSiteStatus = "ready"
        return true
    end

    local puddleGroundStart = Vector()
    local puddleGroundEnd = Vector()
    // Ground results are retained and compared by callers, so only the request is reused.
    local puddleGroundTrace = {
        start = puddleGroundStart,
        endpos = puddleGroundEnd,
        mask = MASK_SOLID_BRUSHONLY
    }

    function Environment.TraceGround(position, player)
        local minimumZ = Environment.WorldMinimum.z
        local startZ = Environment.WorldMaximum.z - 1
        local trace
        puddleGroundTrace.filter = IsValid(player) and player or nil
        // Step through sky ceilings and thin overhead brushes until real ground is found.
        for _ = 1, 4 do
            puddleGroundStart:SetUnpacked(position.x, position.y, startZ)
            puddleGroundEnd:SetUnpacked(position.x, position.y, minimumZ - 64)
            trace = util.TraceLine(puddleGroundTrace)
            if not trace.Hit then return nil end
            if not trace.StartSolid and not trace.HitSky then break end
            local exitZ = trace.StartSolid and (startZ + (minimumZ - 64 - startZ) * trace.FractionLeftSolid) or trace.HitPos.z
            startZ = exitZ - 2
            if startZ <= minimumZ then return nil end
            trace = nil
        end
        if not trace or not trace.HitWorld or trace.HitSky or trace.HitNormal.z < 0.7 then return nil end
        return trace
    end

    local puddleOverheadStart = Vector()
    local puddleOverheadEnd = Vector()
    local puddleOverheadResult = {}
    local puddleOverheadTrace = {
        start = puddleOverheadStart,
        endpos = puddleOverheadEnd,
        mask = MASK_SOLID_BRUSHONLY,
        output = puddleOverheadResult
    }

    function Environment.IsSurfaceExposed(trace, player)
        local hitPos, hitNormal = trace.HitPos, trace.HitNormal
        local surfaceX = hitPos.x + hitNormal.x * 12
        local surfaceY = hitPos.y + hitNormal.y * 12
        puddleOverheadStart:SetUnpacked(surfaceX, surfaceY, hitPos.z + hitNormal.z * 12)
        puddleOverheadEnd:SetUnpacked(surfaceX, surfaceY, Environment.WorldMaximum.z + 64)
        puddleOverheadTrace.filter = IsValid(player) and player or nil
        local overhead = util.TraceLine(puddleOverheadTrace)
        return not overhead.Hit or overhead.HitSky
    end

    function Environment.FindPuddleLowPoint(trace, player)
        local lowest = trace
        for _ = 1, 4 do
            local nextLowest = lowest
            for _, direction in ipairs(Puddles.PuddleProbeDirections) do
                local candidate = Environment.TraceGround(lowest.HitPos + direction * 24, player)
                if candidate and candidate.HitPos.z < nextLowest.HitPos.z - 2 then
                    nextLowest = candidate
                end
            end
            if nextLowest == lowest then break end
            lowest = nextLowest
        end
        return lowest
    end

    function Modules.Environment.RegisterHooks()
    end

    function Environment.Reset()
        table.Empty(surfaceSites)
        Environment.SurfaceMap = nil
        Environment.WorldMinimum = nil
        Environment.WorldMaximum = nil
        Environment.IsSheltered = nil
        Environment.NextShelterCheckAt = 0
        Atmosphere.PuddleSiteMap = nil
        Atmosphere.PuddleWorldMinimum = nil
        Atmosphere.PuddleWorldMaximum = nil
        Atmosphere.PuddleBoundsErrorMap = nil
    end
end
