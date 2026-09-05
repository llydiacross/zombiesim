param(
    [int]$GridCells = 64,
    [int]$CellSize = 64,
    [int]$RoadWidthPixels = 18,
    [int]$Seed = 1337,
    [int]$RoadDepth = 7,
    [double]$BranchChance = 0.38,
    [int]$DeadEndRepairRadius = 8,
    [double]$BlockadeChance = 0.28,
    [int]$BiomeOpacity = 45,
    [double]$BridgeChance = 0.04,
    [double]$DeadEndBridgeChance = 0.30,
    [switch]$ExportLayers,
    [string]$Output = ''
)

Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $PSScriptRoot ("map_grid_64x64_seed_{0}.png" -f $Seed)
}

$width = $GridCells * $CellSize
$height = $GridCells * $CellSize
$worldOriginX = 0
$worldOriginY = 0
$originXOffset = -$width / 2
$originPixelX = [int]($width / 2 + $originXOffset)
$originPixelY = [int]($height / 2)

$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::FromArgb(18, 18, 22))

$random = New-Object System.Random($Seed)
$roadBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 82, 82, 88))
$highwayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 35, 90, 190))
$highwayLinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 245, 245, 245), 3)
$highwayLinePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
$blockadeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 35, 28, 24))
$blockadeStripeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 185, 125, 35))
$deadEndPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 235, 210, 80), 3)
$deadEndBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 235, 210, 80))
$deadEndTipBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 210, 55, 45))
$questionFont = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Bold)
$landmarkFont = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$denNameFont = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold)
$districtNameFont = New-Object System.Drawing.Font("Arial", 50, [System.Drawing.FontStyle]::Bold)
$cityTitleFont = New-Object System.Drawing.Font("Arial", 64, [System.Drawing.FontStyle]::Bold)
$cityStatsFont = New-Object System.Drawing.Font("Arial", 28, [System.Drawing.FontStyle]::Bold)
$keyTitleFont = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
$keyFont = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Regular)
$cityTitleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 245, 210, 80))
$cityStatsBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 225, 225, 230))
$keyBackgroundBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 12, 12, 16))
$keyBorderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 180, 180, 180), 2)
$laboratoryCellPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 50, 220, 90), 4)
$bunkerCellPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 240, 45, 45), 4)
$denBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215, 15, 115, 55))
$denCellPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 75, 235, 115), 3)
$denTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$districtNameBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(165, 255, 238, 170))
$metroLineColor = [System.Drawing.Color]::FromArgb(255, 220, 55, 65)
$metroLineOutlinePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 24, 24, 28), [single]16)
$metroStationBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$metroStationPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 24, 24, 28), [single]5)
$metroStationTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 24, 24, 28))
$metroStationNameFont = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$metroStationLabelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(238, 250, 250, 252))
$metroStationLabelPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 24, 24, 28), [single]2)
$roadWidth = [Math]::Min($RoadWidthPixels, $CellSize - 4)
$highwayWidth = [Math]::Min($CellSize - 8, $roadWidth * 2)
$bridgeDeckPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 118, 118, 126), [single]($roadWidth + 4))
$bridgeEdgePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 225, 225, 232), 2)
$highwayRampPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 105, 105, 112), [single]$roadWidth)
$highwayRampPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
$diagonalCrossingPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 110, 110, 118), $roadWidth)
$diagonalCrossingEdgePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 205, 205, 215), 2)
$originCellY = [int]($originPixelY / $CellSize)
$roadCells = @{}
$highwayCells = @{}
$bridgeCells = @{}
$bridgeCrossingDirections = @{}
$diagonalHighwayCells = @{}
$diagonalRampConnections = @{}
$diagonalUnderpasses = @()
$highwayRamps = @()
$usedHighwayRampConnections = @{}
$blockadeConnections = @{}
$blockadeMarkers = @()
$terrainCells = @{}
$terrainTypes = @{}
$buildingCells = @{}
$denCells = @{}
$metroLines = @()
$metroStations = @{}
$metroStationNames = @{}
$grassColor = [System.Drawing.Color]::FromArgb(70, 125, 62)
$sandColor = [System.Drawing.Color]::FromArgb(175, 145, 72)
$dirtColor = [System.Drawing.Color]::FromArgb(125, 78, 44)
$zones = @(
    @{ Name = "Ashwood"; X = 10; Y = 12; Radius = 15; Color = [System.Drawing.Color]::FromArgb(180, 80, 180, 80) },
    @{ Name = "Breakwater"; X = 8; Y = 38; Radius = 13; Color = [System.Drawing.Color]::FromArgb(180, 70, 105, 190) },
    @{ Name = "Cinder Ward"; X = 29; Y = 29; Radius = 17; Color = [System.Drawing.Color]::FromArgb(190, 190, 150, 70) },
    @{ Name = "Glassworks"; X = 37; Y = 9; Radius = 12; Color = [System.Drawing.Color]::FromArgb(180, 70, 150, 145) },
    @{ Name = "Greyline"; X = 54; Y = 9; Radius = 14; Color = [System.Drawing.Color]::FromArgb(180, 150, 150, 150) },
    @{ Name = "Iron Market"; X = 53; Y = 31; Radius = 17; Color = [System.Drawing.Color]::FromArgb(180, 185, 75, 80) },
    @{ Name = "Southwatch"; X = 13; Y = 51; Radius = 13; Color = [System.Drawing.Color]::FromArgb(180, 150, 165, 65) },
    @{ Name = "Red Hollow"; X = 31; Y = 51; Radius = 16; Color = [System.Drawing.Color]::FromArgb(180, 175, 75, 75) },
    @{ Name = "Raven Reach"; X = 57; Y = 51; Radius = 12; Color = [System.Drawing.Color]::FromArgb(180, 165, 75, 190) },
    @{ Name = "Dustfield"; X = 19; Y = 59; Radius = 9; Color = [System.Drawing.Color]::FromArgb(180, 145, 75, 35) }
)
$deadZones = @(
    @{ X = 18; Y = 20; Radius = 6 },
    @{ X = 42; Y = 18; Radius = 7 },
    @{ X = 27; Y = 42; Radius = 6 },
    @{ X = 48; Y = 48; Radius = 8 },
    @{ X = 9; Y = 57; Radius = 5 }
)
$cityPrefixes = @("Ash", "Black", "Cinder", "Dun", "East", "Grey", "Iron", "New", "North", "Raven", "Red", "West")
$citySuffixes = @("bridge", "cross", "fall", "gate", "haven", "mere", "point", "reach", "ridge", "vale", "watch", "wick")
$seedMagnitude = [Math]::Abs([int64]$Seed)
$cityName = "$($cityPrefixes[$seedMagnitude % $cityPrefixes.Count])$($citySuffixes[($seedMagnitude / $cityPrefixes.Count) % $citySuffixes.Count])"

function Add-RoadConnection {
    param(
        [int]$CellX,
        [int]$CellY,
        [string]$Direction
    )

    $key = "$CellX,$CellY"
    if (-not $roadCells.ContainsKey($key)) {
        $roadCells[$key] = @{ N = $false; E = $false; S = $false; W = $false }
    }
    $roadCells[$key][$Direction] = $true

    $neighborX = $CellX
    $neighborY = $CellY
    $oppositeDirection = ""
    switch ($Direction) {
        "N" { $neighborY--; $oppositeDirection = "S" }
        "E" { $neighborX++; $oppositeDirection = "W" }
        "S" { $neighborY++; $oppositeDirection = "N" }
        "W" { $neighborX--; $oppositeDirection = "E" }
    }

    if ($neighborX -ge 0 -and $neighborX -lt $GridCells -and $neighborY -ge 0 -and $neighborY -lt $GridCells) {
        $neighborKey = "$neighborX,$neighborY"
        if (-not $roadCells.ContainsKey($neighborKey)) {
            $roadCells[$neighborKey] = @{ N = $false; E = $false; S = $false; W = $false }
        }
        $roadCells[$neighborKey][$oppositeDirection] = $true
    }
}

function Add-HighwayConnection {
    param(
        [int]$CellX,
        [int]$CellY,
        [string]$Direction
    )

    $key = "$CellX,$CellY"
    if (-not $highwayCells.ContainsKey($key)) {
        $highwayCells[$key] = @{ N = $false; E = $false; S = $false; W = $false }
    }
    $highwayCells[$key][$Direction] = $true

    $neighborKey = Get-RoadNeighborKey $CellX $CellY $Direction
    if ($null -ne $neighborKey) {
        if (-not $highwayCells.ContainsKey($neighborKey)) {
            $highwayCells[$neighborKey] = @{ N = $false; E = $false; S = $false; W = $false }
        }
        $oppositeDirection = switch ($Direction) {
            "N" { "S" }
            "E" { "W" }
            "S" { "N" }
            "W" { "E" }
        }
        $highwayCells[$neighborKey][$oppositeDirection] = $true
    }

    Add-RoadConnection $CellX $CellY $Direction
}

function Remove-RoadConnection {
    param(
        [int]$CellX,
        [int]$CellY,
        [string]$Direction
    )

    $key = "$CellX,$CellY"
    if (-not $roadCells.ContainsKey($key)) { return }
    $roadCells[$key][$Direction] = $false

    $neighborKey = Get-RoadNeighborKey $CellX $CellY $Direction
    if ($null -eq $neighborKey -or -not $roadCells.ContainsKey($neighborKey)) { return }
    $oppositeDirection = switch ($Direction) {
        "N" { "S" }
        "E" { "W" }
        "S" { "N" }
        "W" { "E" }
    }
    $roadCells[$neighborKey][$oppositeDirection] = $false
}

function Get-TurnDirection {
    param(
        [string]$Direction,
        [int]$Turn
    )

    $directions = @("N", "E", "S", "W")
    $index = [Array]::IndexOf($directions, $Direction)
    return $directions[($index + $Turn + 4) % 4]
}

function Grow-Road {
    param(
        [int]$StartX,
        [int]$StartY,
        [string]$Direction,
        [int]$Depth
    )

    if ($Depth -le 0) { return }

    $cellX = $StartX
    $cellY = $StartY
    $steps = $random.Next(3, 10)
    for ($step = 0; $step -lt $steps; $step++) {
        $nextX = $cellX
        $nextY = $cellY
        switch ($Direction) {
            "N" { $nextY-- }
            "E" { $nextX++ }
            "S" { $nextY++ }
            "W" { $nextX-- }
        }

        if ($nextX -lt 0 -or $nextX -ge $GridCells -or $nextY -lt 0 -or $nextY -ge $GridCells) { break }

        Add-RoadConnection $cellX $cellY $Direction
        $cellX = $nextX
        $cellY = $nextY

        if ($Depth -gt 1 -and $random.NextDouble() -lt $BranchChance) {
            $branchDirection = Get-TurnDirection $Direction $(if ($random.Next(0, 2) -eq 0) { -1 } else { 1 })
            Grow-Road $cellX $cellY $branchDirection ($Depth - 1)
        }

        if ($random.NextDouble() -lt 0.16) {
            $Direction = Get-TurnDirection $Direction $(if ($random.Next(0, 2) -eq 0) { -1 } else { 1 })
        }
    }
}

function Get-RoadDegree {
    param([hashtable]$RoadCell)

    return @($RoadCell.N, $RoadCell.E, $RoadCell.S, $RoadCell.W | Where-Object { $_ }).Count
}

function Get-RoadNeighborKey {
    param(
        [int]$CellX,
        [int]$CellY,
        [string]$Direction
    )

    switch ($Direction) {
        "N" { $CellY-- }
        "E" { $CellX++ }
        "S" { $CellY++ }
        "W" { $CellX-- }
    }

    if ($CellX -lt 0 -or $CellX -ge $GridCells -or $CellY -lt 0 -or $CellY -ge $GridCells) {
        return $null
    }

    return "$CellX,$CellY"
}

function Get-MetroPath {
    param(
        [string]$StartKey,
        [string]$EndKey,
        [bool]$AvoidHighways = $false
    )

    $openSet = @{ $StartKey = $true }
    $cameFrom = @{}
    $gScore = @{ $StartKey = 0.0 }
    $endCoordinates = $EndKey -split ","
    $endX = [int]$endCoordinates[0]
    $endY = [int]$endCoordinates[1]
    $directions = @(
        @{ X = 1; Y = 0 }, @{ X = 1; Y = 1 }, @{ X = 0; Y = 1 }, @{ X = -1; Y = 1 },
        @{ X = -1; Y = 0 }, @{ X = -1; Y = -1 }, @{ X = 0; Y = -1 }, @{ X = 1; Y = -1 }
    )

    while ($openSet.Count -gt 0) {
        $currentKey = $null
        $currentScore = [double]::PositiveInfinity
        foreach ($openKey in $openSet.Keys) {
            $coordinates = $openKey -split ","
            $distanceX = [Math]::Abs([int]$coordinates[0] - $endX)
            $distanceY = [Math]::Abs([int]$coordinates[1] - $endY)
            # Favor the direct octilinear path between consecutive stations.
            $heuristic = [Math]::Max($distanceX, $distanceY)
            $score = $gScore[$openKey] + $heuristic
            if ($score -lt $currentScore -or ($score -eq $currentScore -and ($null -eq $currentKey -or [string]::CompareOrdinal($openKey, $currentKey) -lt 0))) {
                $currentKey = $openKey
                $currentScore = $score
            }
        }

        if ($currentKey -eq $EndKey) {
            $path = @($currentKey)
            while ($cameFrom.ContainsKey($path[0])) { $path = @($cameFrom[$path[0]]) + $path }
            return $path
        }
        $openSet.Remove($currentKey)

        $currentCoordinates = $currentKey -split ","
        $currentX = [int]$currentCoordinates[0]
        $currentY = [int]$currentCoordinates[1]
        foreach ($direction in $directions) {
            $neighborX = $currentX + $direction.X
            $neighborY = $currentY + $direction.Y
            if ($neighborX -lt 0 -or $neighborX -ge $GridCells -or $neighborY -lt 0 -or $neighborY -ge $GridCells) { continue }

            $neighborKey = "$neighborX,$neighborY"
            if ($AvoidHighways -and ($highwayCells.ContainsKey($neighborKey) -or $diagonalHighwayCells.ContainsKey($neighborKey))) { continue }
            $isDiagonal = $direction.X -ne 0 -and $direction.Y -ne 0
            $stepCost = if ($isDiagonal) { 1.414 } else { 1.0 }
            $tentativeScore = $gScore[$currentKey] + $stepCost
            if (-not $gScore.ContainsKey($neighborKey) -or $tentativeScore -lt $gScore[$neighborKey]) {
                $cameFrom[$neighborKey] = $currentKey
                $gScore[$neighborKey] = $tentativeScore
                $openSet[$neighborKey] = $true
            }
        }
    }

    return @()
}

function Get-MetroRoadAccessPath {
    param(
        [string]$StartKey,
        [bool]$EnforceSpacing = $false
    )

    if ($roadCells.ContainsKey($StartKey) -and -not $highwayCells.ContainsKey($StartKey) -and -not $diagonalHighwayCells.ContainsKey($StartKey) -and (-not $EnforceSpacing -or $metroStations.ContainsKey($StartKey) -or (Test-MetroStopSpacing $StartKey))) {
        return @($StartKey)
    }

    $startCoordinates = $StartKey -split ","
    $startX = [int]$startCoordinates[0]
    $startY = [int]$startCoordinates[1]
    $roadCandidates = @($roadCells.Keys | Where-Object {
        -not $highwayCells.ContainsKey($_) -and -not $diagonalHighwayCells.ContainsKey($_)
    } | Sort-Object {
        $coordinates = $_ -split ","
        [Math]::Pow([int]$coordinates[0] - $startX, 2) + [Math]::Pow([int]$coordinates[1] - $startY, 2)
    })
    foreach ($roadKey in $roadCandidates) {
        if ($EnforceSpacing -and -not $metroStations.ContainsKey($roadKey) -and -not (Test-MetroStopSpacing $roadKey)) { continue }
        $accessPath = @(Get-MetroPath $StartKey $roadKey $true)
        if ($accessPath.Count -gt 0) { return $accessPath }
    }

    return @()
}

function Get-MetroStationKey {
    param([hashtable]$Zone)

    $stationCandidates = @()
    for ($cellY = [Math]::Max(0, $Zone.Y - $Zone.Radius); $cellY -le [Math]::Min($GridCells - 1, $Zone.Y + $Zone.Radius); $cellY++) {
        for ($cellX = [Math]::Max(0, $Zone.X - $Zone.Radius); $cellX -le [Math]::Min($GridCells - 1, $Zone.X + $Zone.Radius); $cellX++) {
            $key = "$cellX,$cellY"
            $distance = [Math]::Sqrt([Math]::Pow($cellX - $Zone.X, 2) + [Math]::Pow($cellY - $Zone.Y, 2))
            if ($distance -gt $Zone.Radius -or $denCells.ContainsKey($key) -or $landmarkCells.ContainsKey($key)) { continue }
            $stationCandidates += @{ Key = $key; Distance = $distance }
        }
    }

    if ($stationCandidates.Count -eq 0) { throw "No metro station location is available in $($Zone.Name)." }
    return ($stationCandidates | Sort-Object Distance, Key)[0].Key
}

function Get-MetroStopName {
    param(
        [string]$StationKey,
        [string]$DistrictName = "",
        [bool]$Major = $false
    )

    $coordinates = $StationKey -split ","
    $stationX = [int]$coordinates[0]
    $stationY = [int]$coordinates[1]
    $nearestZone = $zones | Sort-Object { [Math]::Pow($stationX - $_.X, 2) + [Math]::Pow($stationY - $_.Y, 2) } | Select-Object -First 1
    $prefix = if ([string]::IsNullOrWhiteSpace($DistrictName)) { ($nearestZone.Name -split " ")[0] } else { $DistrictName }
    if ($Major) { return "$prefix Exchange" }

    $stopSuffixes = @("Arcade", "Bridge", "Cross", "Gate", "Gardens", "Heights", "Junction", "Market", "Park", "Quay", "Square", "Terrace", "Works", "Yard")
    $startIndex = [Math]::Abs(($stationX * 73) + ($stationY * 37) + $Seed) % $stopSuffixes.Count
    for ($offset = 0; $offset -lt $stopSuffixes.Count; $offset++) {
        $candidate = "$prefix $($stopSuffixes[($startIndex + $offset) % $stopSuffixes.Count])"
        if (-not $metroStationNames.ContainsKey($candidate)) {
            $metroStationNames[$candidate] = $true
            return $candidate
        }
    }

    $fallback = "$prefix Stop $stationX-$stationY"
    $metroStationNames[$fallback] = $true
    return $fallback
}

function Test-MetroStopSpacing {
    param(
        [string]$StationKey,
        [int]$MinimumDistance = 6
    )

    $coordinates = $StationKey -split ","
    $stationX = [int]$coordinates[0]
    $stationY = [int]$coordinates[1]
    foreach ($existingStationKey in $metroStations.Keys) {
        if ($existingStationKey -eq $StationKey) { continue }
        $existingCoordinates = $existingStationKey -split ","
        $distanceX = $stationX - [int]$existingCoordinates[0]
        $distanceY = $stationY - [int]$existingCoordinates[1]
        if ([Math]::Sqrt(($distanceX * $distanceX) + ($distanceY * $distanceY)) -lt $MinimumDistance) {
            return $false
        }
    }

    return $true
}

function Add-MetroStop {
    param(
        [string]$RequestedKey,
        [string]$DistrictName,
        [bool]$Major,
        [string]$LineName,
        [bool]$EnforceSpacing = $false
    )

    $accessPath = @(Get-MetroRoadAccessPath $RequestedKey $EnforceSpacing)
    if ($accessPath.Count -eq 0) { return $null }
    $stationKey = $accessPath[-1]
    if ($highwayCells.ContainsKey($stationKey) -or $diagonalHighwayCells.ContainsKey($stationKey) -or -not $roadCells.ContainsKey($stationKey)) { return $null }
    if ($EnforceSpacing -and -not $metroStations.ContainsKey($stationKey) -and -not (Test-MetroStopSpacing $stationKey)) { return $null }

    if (-not $metroStations.ContainsKey($stationKey)) {
        $metroStations[$stationKey] = @{
            Name = (Get-MetroStopName $stationKey $DistrictName $Major)
            Major = $Major
            Lines = @($LineName)
            AccessPath = $accessPath
            AccessLine = $LineName
        }
    } else {
        $station = $metroStations[$stationKey]
        if ($station.Lines -notcontains $LineName) { $station.Lines += $LineName }
        if ($Major -and -not $station.Major) {
            $station.Major = $true
            $station.Name = Get-MetroStopName $stationKey $DistrictName $true
        }
    }

    return $stationKey
}

function Get-MetroSchematicPath {
    param([string[]]$Path)

    if ($Path.Count -le 2) { return $Path }
    $schematicPath = @($Path[0])
    $previousDirection = $null
    for ($pathIndex = 1; $pathIndex -lt $Path.Count; $pathIndex++) {
        $fromCoordinates = $Path[$pathIndex - 1] -split ","
        $toCoordinates = $Path[$pathIndex] -split ","
        $direction = "{0},{1}" -f ([int]$toCoordinates[0] - [int]$fromCoordinates[0]), ([int]$toCoordinates[1] - [int]$fromCoordinates[1])
        if ($null -ne $previousDirection -and $direction -ne $previousDirection) {
            $schematicPath += $Path[$pathIndex - 1]
        }
        $previousDirection = $direction
    }
    $schematicPath += $Path[$Path.Count - 1]
    return $schematicPath
}

function Connect-MetroRouteThroughStops {
    param(
        [string[]]$BaseRoute,
        [hashtable]$StopsByRouteIndex,
        [hashtable]$GuideRouteIndexes
    )

    $routeWaypoints = @()
    for ($routeIndex = 0; $routeIndex -lt $BaseRoute.Count; $routeIndex++) {
        if ($StopsByRouteIndex.ContainsKey($routeIndex)) {
            $routeWaypoints += $StopsByRouteIndex[$routeIndex]
        } elseif ($GuideRouteIndexes.ContainsKey($routeIndex)) {
            $routeWaypoints += $BaseRoute[$routeIndex]
        }
    }

    $connectedRoute = @()
    for ($waypointIndex = 0; $waypointIndex -lt ($routeWaypoints.Count - 1); $waypointIndex++) {
        $segment = @(Get-MetroPath $routeWaypoints[$waypointIndex] $routeWaypoints[$waypointIndex + 1])
        if ($segment.Count -eq 0) { return @() }
        if ($connectedRoute.Count -gt 0) { $segment = @($segment | Select-Object -Skip 1) }
        $connectedRoute += $segment
    }
    return $connectedRoute
}

    function Get-MapLayerOutputPath {
        param([string]$LayerName)

        $outputDirectory = Split-Path -Parent $Output
        $outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Output)
        return Join-Path $outputDirectory ("{0}_{1}.png" -f $outputBaseName, $LayerName)
    }

    function Draw-BlockadeMarker {
        param(
            [System.Drawing.Graphics]$TargetGraphics,
            [hashtable]$Marker
        )

        $coordinates = $Marker.CellKey -split ","
        $cellX = [int]$coordinates[0]
        $cellY = [int]$coordinates[1]
        $cellLeft = $cellX * $CellSize
        $cellTop = $cellY * $CellSize
        $centerX = $cellLeft + [int]($CellSize / 2)
        $centerY = $cellTop + [int]($CellSize / 2)
        $barrierThickness = [Math]::Max(5, [int]($roadWidth / 3))
        $barrierLength = $roadWidth + 10

        switch ($Marker.Direction) {
            "N" {
                $barrierX = $centerX - [int]($barrierLength / 2)
                $barrierY = $cellTop + [int]($CellSize * 0.18)
                $TargetGraphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierLength, $barrierThickness)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX + 4, $barrierY, 4, $barrierThickness)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX + $barrierLength - 8, $barrierY, 4, $barrierThickness)
            }
            "E" {
                $barrierX = $cellLeft + [int]($CellSize * 0.82)
                $barrierY = $centerY - [int]($barrierLength / 2)
                $TargetGraphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierThickness, $barrierLength)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + 4, $barrierThickness, 4)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + $barrierLength - 8, $barrierThickness, 4)
            }
            "S" {
                $barrierX = $centerX - [int]($barrierLength / 2)
                $barrierY = $cellTop + [int]($CellSize * 0.82)
                $TargetGraphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierLength, $barrierThickness)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX + 4, $barrierY, 4, $barrierThickness)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX + $barrierLength - 8, $barrierY, 4, $barrierThickness)
            }
            "W" {
                $barrierX = $cellLeft + [int]($CellSize * 0.18)
                $barrierY = $centerY - [int]($barrierLength / 2)
                $TargetGraphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierThickness, $barrierLength)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + 4, $barrierThickness, 4)
                $TargetGraphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + $barrierLength - 8, $barrierThickness, 4)
            }
        }
    }

    function Draw-RoadLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        foreach ($key in $roadCells.Keys) {
            if ($diagonalHighwayCells.ContainsKey($key)) { continue }
            $coordinates = $key -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            $cellLeft = $cellX * $CellSize
            $cellTop = $cellY * $CellSize
            $centerX = $cellLeft + [int]($CellSize / 2)
            $centerY = $cellTop + [int]($CellSize / 2)
            $halfRoad = [int]($roadWidth / 2)
            $TargetGraphics.FillRectangle($roadBrush, $centerX - $halfRoad, $centerY - $halfRoad, $roadWidth, $roadWidth)
            if ($roadCells[$key].N) { $TargetGraphics.FillRectangle($roadBrush, $centerX - $halfRoad, $cellTop, $roadWidth, [int]($CellSize / 2) + $halfRoad) }
            if ($roadCells[$key].E) { $TargetGraphics.FillRectangle($roadBrush, $centerX - $halfRoad, $centerY - $halfRoad, [int]($CellSize / 2) + $halfRoad, $roadWidth) }
            if ($roadCells[$key].S) { $TargetGraphics.FillRectangle($roadBrush, $centerX - $halfRoad, $centerY - $halfRoad, $roadWidth, [int]($CellSize / 2) + $halfRoad) }
            if ($roadCells[$key].W) { $TargetGraphics.FillRectangle($roadBrush, $cellLeft, $centerY - $halfRoad, [int]($CellSize / 2) + $halfRoad, $roadWidth) }
        }

        foreach ($key in $bridgeCells.Keys) {
            if (-not $highwayCells.ContainsKey($key)) { continue }
            $coordinates = $key -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            $centerX = $cellX * $CellSize + [int]($CellSize / 2)
            $centerY = $cellY * $CellSize + [int]($CellSize / 2)
            $crossingDirection = if ($bridgeCrossingDirections.ContainsKey($key)) { $bridgeCrossingDirections[$key] } elseif ($highwayCells[$key].N -and $highwayCells[$key].S) { "E" } else { "N" }
            if ($crossingDirection -eq "E" -or $crossingDirection -eq "W") {
                $TargetGraphics.DrawLine($bridgeDeckPen, $cellX * $CellSize, $centerY, ($cellX + 1) * $CellSize, $centerY)
                $TargetGraphics.DrawLine($bridgeEdgePen, $cellX * $CellSize, $centerY - [int]($roadWidth / 2), ($cellX + 1) * $CellSize, $centerY - [int]($roadWidth / 2))
                $TargetGraphics.DrawLine($bridgeEdgePen, $cellX * $CellSize, $centerY + [int]($roadWidth / 2), ($cellX + 1) * $CellSize, $centerY + [int]($roadWidth / 2))
            } else {
                $TargetGraphics.DrawLine($bridgeDeckPen, $centerX, $cellY * $CellSize, $centerX, ($cellY + 1) * $CellSize)
                $TargetGraphics.DrawLine($bridgeEdgePen, $centerX - [int]($roadWidth / 2), $cellY * $CellSize, $centerX - [int]($roadWidth / 2), ($cellY + 1) * $CellSize)
                $TargetGraphics.DrawLine($bridgeEdgePen, $centerX + [int]($roadWidth / 2), $cellY * $CellSize, $centerX + [int]($roadWidth / 2), ($cellY + 1) * $CellSize)
            }
        }

        foreach ($underpass in $diagonalUnderpasses) {
            $centerY = $underpass.Y * $CellSize + [int]($CellSize / 2)
            $startX = ($underpass.X - 1) * $CellSize + [int]($CellSize / 2)
            $endX = ($underpass.X + 1) * $CellSize + [int]($CellSize / 2)
            $TargetGraphics.DrawLine($diagonalCrossingPen, $startX, $centerY, $endX, $centerY)
            $TargetGraphics.DrawLine($diagonalCrossingEdgePen, $startX, $centerY - [int]($roadWidth / 2), $endX, $centerY - [int]($roadWidth / 2))
            $TargetGraphics.DrawLine($diagonalCrossingEdgePen, $startX, $centerY + [int]($roadWidth / 2), $endX, $centerY + [int]($roadWidth / 2))
        }
        foreach ($connectionKey in $diagonalRampConnections.Keys) {
            $parts = $connectionKey -split ":"
            $coordinates = $parts[0] -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            $centerX = $cellX * $CellSize + [int]($CellSize / 2)
            $centerY = $cellY * $CellSize + [int]($CellSize / 2)
            if ($bridgeCells.ContainsKey("$cellX,$cellY")) { continue }
            $neighborKey = Get-RoadNeighborKey $cellX $cellY $parts[1]
            if ($null -eq $neighborKey) { continue }
            $neighborCoordinates = $neighborKey -split ","
            $neighborCenterX = [int]$neighborCoordinates[0] * $CellSize + [int]($CellSize / 2)
            $neighborCenterY = [int]$neighborCoordinates[1] * $CellSize + [int]($CellSize / 2)
            $TargetGraphics.DrawLine($diagonalCrossingPen, $centerX, $centerY, $neighborCenterX, $neighborCenterY)
        }

        foreach ($marker in $blockadeMarkers) { Draw-BlockadeMarker $TargetGraphics $marker }
        Draw-DeadEndMarkers $TargetGraphics
    }

    function Draw-HighwayLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        foreach ($key in $highwayCells.Keys) {
            $coordinates = $key -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            $cellLeft = $cellX * $CellSize
            $cellTop = $cellY * $CellSize
            $centerX = $cellLeft + [int]($CellSize / 2)
            $centerY = $cellTop + [int]($CellSize / 2)
            $halfHighway = [int]($highwayWidth / 2)
            $TargetGraphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $centerY - $halfHighway, $highwayWidth, $highwayWidth)
            if ($highwayCells[$key].N) { $TargetGraphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $cellTop, $highwayWidth, [int]($CellSize / 2) + $halfHighway) }
            if ($highwayCells[$key].E) { $TargetGraphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $centerY - $halfHighway, [int]($CellSize / 2) + $halfHighway, $highwayWidth) }
            if ($highwayCells[$key].S) { $TargetGraphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $centerY - $halfHighway, $highwayWidth, [int]($CellSize / 2) + $halfHighway) }
            if ($highwayCells[$key].W) { $TargetGraphics.FillRectangle($highwayBrush, $cellLeft, $centerY - $halfHighway, [int]($CellSize / 2) + $halfHighway, $highwayWidth) }
        }
        foreach ($key in $highwayCells.Keys) {
            $coordinates = $key -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            $centerX = $cellX * $CellSize + [int]($CellSize / 2)
            $centerY = $cellY * $CellSize + [int]($CellSize / 2)
            foreach ($direction in @("E", "S")) {
                if (-not $highwayCells[$key][$direction]) { continue }
                $neighborKey = Get-RoadNeighborKey $cellX $cellY $direction
                if ($null -eq $neighborKey) { continue }
                $neighborCoordinates = $neighborKey -split ","
                $TargetGraphics.DrawLine($highwayLinePen, $centerX, $centerY, [int]$neighborCoordinates[0] * $CellSize + [int]($CellSize / 2), [int]$neighborCoordinates[1] * $CellSize + [int]($CellSize / 2))
            }
        }
        foreach ($ramp in $highwayRamps) {
            $centerX = $ramp.X * $CellSize + [int]($CellSize / 2)
            $centerY = $ramp.Y * $CellSize + [int]($CellSize / 2)
            $rampKey = Get-RoadNeighborKey $ramp.X $ramp.Y $ramp.Exit
            if ($null -eq $rampKey) { continue }
            $rampCoordinates = $rampKey -split ","
            $rampCenterX = [int]$rampCoordinates[0] * $CellSize + [int]($CellSize / 2)
            $rampCenterY = [int]$rampCoordinates[1] * $CellSize + [int]($CellSize / 2)
            $exitKey = Get-RoadNeighborKey ([int]$rampCoordinates[0]) ([int]$rampCoordinates[1]) $ramp.Travel
            if ($null -eq $exitKey) { continue }
            $exitCoordinates = $exitKey -split ","
            $TargetGraphics.DrawLine($highwayRampPen, $centerX, $centerY, $rampCenterX, $rampCenterY)
            $TargetGraphics.DrawLine($highwayRampPen, $rampCenterX, $rampCenterY, [int]$exitCoordinates[0] * $CellSize + [int]($CellSize / 2), [int]$exitCoordinates[1] * $CellSize + [int]($CellSize / 2))
        }
    }

    function Draw-KeyLayer {
        param(
            [System.Drawing.Graphics]$TargetGraphics,
            [object[]]$Entries,
            [object[]]$SafeZones,
            [int]$KeyX,
            [int]$KeyY,
            [int]$KeyWidth,
            [int]$KeyHeight,
            [int]$SafeZoneY,
            [int]$SafeZoneHeight,
            [object[]]$TransportLines,
            [int]$TransportY,
            [int]$TransportHeight
        )

        $TargetGraphics.FillRectangle($keyBackgroundBrush, $KeyX, $KeyY, $KeyWidth, $KeyHeight)
        $TargetGraphics.DrawRectangle($keyBorderPen, $KeyX, $KeyY, $KeyWidth, $KeyHeight)
        $TargetGraphics.DrawString("MAP KEY", $keyTitleFont, $deadEndBrush, $KeyX + 14, $KeyY + 10)
        for ($entryIndex = 0; $entryIndex -lt $Entries.Count; $entryIndex++) {
            $entry = $Entries[$entryIndex]
            $entryY = $KeyY + 47 + ($entryIndex * $keyRowHeight)
            $entryBrush = New-Object System.Drawing.SolidBrush($entry.Color)
            $entryPenColor = if ($entry.Label -eq "LAB") { [System.Drawing.Color]::FromArgb(255, 50, 220, 90) } elseif ($entry.Label -eq "B") { [System.Drawing.Color]::FromArgb(255, 240, 45, 45) } else { [System.Drawing.Color]::White }
            $entryPen = New-Object System.Drawing.Pen($entryPenColor, 2)
            $entryDisplayLabel = if ($entry.DisplayLabel) { $entry.DisplayLabel } else { $entry.Label }
            if ($entry.Label -eq "METRO") {
                $metroKeyPen = [System.Drawing.Pen]::new($entry.Color, [single]6)
                $metroKeyStationPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 24, 24, 28), [single]2)
                $TargetGraphics.DrawLine($metroKeyPen, $KeyX + 14, $entryY + 10, $KeyX + 34, $entryY + 10)
                $TargetGraphics.FillEllipse($metroStationBrush, $KeyX + 19, $entryY + 5, 10, 10)
                $TargetGraphics.DrawEllipse($metroKeyStationPen, $KeyX + 19, $entryY + 5, 10, 10)
                $metroKeyPen.Dispose()
                $metroKeyStationPen.Dispose()
            } else {
                $TargetGraphics.FillEllipse($entryBrush, $KeyX + 14, $entryY, 20, 20)
                $TargetGraphics.DrawEllipse($entryPen, $KeyX + 14, $entryY, 20, 20)
                $TargetGraphics.DrawString($entryDisplayLabel, $keyFont, $deadEndBrush, $KeyX + 19, $entryY + 2)
            }
            $TargetGraphics.DrawString($entry.Name, $keyFont, $deadEndBrush, $KeyX + 44, $entryY + 1)
            $entryBrush.Dispose()
            $entryPen.Dispose()
        }

        $TargetGraphics.FillRectangle($keyBackgroundBrush, $KeyX, $SafeZoneY, $KeyWidth, $SafeZoneHeight)
        $TargetGraphics.DrawRectangle($keyBorderPen, $KeyX, $SafeZoneY, $KeyWidth, $SafeZoneHeight)
        $TargetGraphics.DrawString("SAFE ZONES", $keyTitleFont, $denTextBrush, $KeyX + 14, $SafeZoneY + 10)
        for ($safeZoneIndex = 0; $safeZoneIndex -lt $SafeZones.Count; $safeZoneIndex++) {
            $safeZone = $SafeZones[$safeZoneIndex]
            $coordinates = $safeZone.Key -split ","
            $worldX = [int]$coordinates[0]
            $worldY = [int]$coordinates[1] - $originCellY
            $safeZoneYPosition = $SafeZoneY + 42 + ($safeZoneIndex * $safeZoneRowHeight)
            $TargetGraphics.DrawString($safeZone.Value.Name, $keyFont, $denTextBrush, $KeyX + 14, $safeZoneYPosition)
            $TargetGraphics.DrawString("X $worldX  Y $worldY", $keyFont, $cityStatsBrush, $KeyX + 255, $safeZoneYPosition)
        }

        $TargetGraphics.FillRectangle($keyBackgroundBrush, $KeyX, $TransportY, $KeyWidth, $TransportHeight)
        $TargetGraphics.DrawRectangle($keyBorderPen, $KeyX, $TransportY, $KeyWidth, $TransportHeight)
        $TargetGraphics.DrawString("TRANSPORT", $keyTitleFont, $denTextBrush, $KeyX + 14, $TransportY + 10)
        for ($transportIndex = 0; $transportIndex -lt $TransportLines.Count; $transportIndex++) {
            $transportLine = $TransportLines[$transportIndex]
            $transportYPosition = $TransportY + 42 + ($transportIndex * $transportRowHeight)
            $transportPen = [System.Drawing.Pen]::new($transportLine.Color, [single]6)
            $TargetGraphics.DrawLine($transportPen, $KeyX + 14, $transportYPosition + 8, $KeyX + 38, $transportYPosition + 8)
            $TargetGraphics.FillEllipse($metroStationBrush, $KeyX + 21, $transportYPosition + 3, 10, 10)
            $TargetGraphics.DrawEllipse($metroStationPen, $KeyX + 21, $transportYPosition + 3, 10, 10)
            $TargetGraphics.DrawString($transportLine.Name, $keyFont, $denTextBrush, $KeyX + 50, $transportYPosition)
            $transportPen.Dispose()
        }
    }

    function Draw-TerrainLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        foreach ($key in $terrainCells.Keys) {
            $coordinates = $key -split ","
            $terrainBrush = New-Object System.Drawing.SolidBrush($terrainCells[$key])
            $TargetGraphics.FillRectangle($terrainBrush, [int]$coordinates[0] * $CellSize, [int]$coordinates[1] * $CellSize, $CellSize, $CellSize)
            $terrainBrush.Dispose()
        }
    }

    function Draw-BuildingLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        foreach ($key in $buildingCells.Keys) {
            $coordinates = $key -split ","
            $buildingColor = $buildingCells[$key]
            $left = [int]$coordinates[0] * $CellSize + $buildingMargin
            $top = [int]$coordinates[1] * $CellSize + $buildingMargin
            $buildingSize = $CellSize - ($buildingMargin * 2)
            $buildingBrush = New-Object System.Drawing.SolidBrush($buildingColor)
            $buildingPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, $buildingColor.R, $buildingColor.G, $buildingColor.B), 2)
            $TargetGraphics.FillRectangle($buildingBrush, $left, $top, $buildingSize, $buildingSize)
            $TargetGraphics.DrawRectangle($buildingPen, $left, $top, $buildingSize - 1, $buildingSize - 1)
            $buildingBrush.Dispose()
            $buildingPen.Dispose()
        }
    }

    function Draw-DeadEndMarkers {
        param([System.Drawing.Graphics]$TargetGraphics)

        foreach ($key in $roadCells.Keys) {
            if ((Get-RoadDegree $roadCells[$key]) -ne 1) { continue }
            $coordinates = $key -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            if ($cellX -eq 0 -and $cellY -eq $originCellY) { continue }

            $cellLeft = $cellX * $CellSize
            $cellTop = $cellY * $CellSize
            $centerX = $cellLeft + [int]($CellSize / 2)
            $centerY = $cellTop + [int]($CellSize / 2)
            $markerRadius = [int]($CellSize * 0.25)
            $markerLeft = $centerX - $markerRadius
            $markerTop = $centerY - $markerRadius
            $markerDiameter = $markerRadius * 2
            $connectedDirection = @("N", "E", "S", "W" | Where-Object { $roadCells[$key][$_] })[0]
            $tipLength = [Math]::Max(5, [int]($roadWidth / 3))
            $halfRoad = [int]($roadWidth / 2)
            switch ($connectedDirection) {
                "N" { $TargetGraphics.FillRectangle($deadEndTipBrush, $centerX - $halfRoad, $cellTop + $CellSize - $tipLength, $roadWidth, $tipLength) }
                "E" { $TargetGraphics.FillRectangle($deadEndTipBrush, $cellLeft, $centerY - $halfRoad, $tipLength, $roadWidth) }
                "S" { $TargetGraphics.FillRectangle($deadEndTipBrush, $centerX - $halfRoad, $cellTop, $roadWidth, $tipLength) }
                "W" { $TargetGraphics.FillRectangle($deadEndTipBrush, $cellLeft + $CellSize - $tipLength, $centerY - $halfRoad, $tipLength, $roadWidth) }
            }
            $TargetGraphics.DrawEllipse($deadEndPen, $markerLeft, $markerTop, $markerDiameter, $markerDiameter)
            $questionMark = "?"
            $textSize = $TargetGraphics.MeasureString($questionMark, $questionFont)
            $TargetGraphics.DrawString($questionMark, $questionFont, $deadEndBrush, $centerX - ($textSize.Width / 2), $centerY - ($textSize.Height / 2))
        }
    }

    function Draw-LandmarkLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        $iconRadius = [Math]::Max(10, [int]($CellSize * 0.22))
        foreach ($key in $landmarkCells.Keys) {
            $coordinates = $key -split ","
            $cellX = [int]$coordinates[0]
            $cellY = [int]$coordinates[1]
            $centerX = $cellX * $CellSize + [int]($CellSize / 2)
            $centerY = $cellY * $CellSize + [int]($CellSize / 2)
            $icons = @($landmarkCells[$key])
            $iconSpacing = [int]($iconRadius * 1.8)
            $gridColumns = [Math]::Min(2, $icons.Count)
            $gridRows = [Math]::Ceiling($icons.Count / 2.0)
            for ($iconIndex = 0; $iconIndex -lt $icons.Count; $iconIndex++) {
                $icon = $icons[$iconIndex]
                $gridColumn = $iconIndex % 2
                $gridRow = [Math]::Floor($iconIndex / 2)
                $iconX = $centerX + ($gridColumn - (($gridColumns - 1) / 2)) * $iconSpacing
                $iconY = $centerY + ($gridRow - (($gridRows - 1) / 2)) * $iconSpacing
                $iconBrush = New-Object System.Drawing.SolidBrush($icon.Color)
                $outlineColor = if ($icon.Label -eq "LAB" -or $icon.Label -eq "B") { [System.Drawing.Color]::FromArgb(255, 230, 45, 45) } else { [System.Drawing.Color]::FromArgb(255, 245, 245, 245) }
                $iconOutline = New-Object System.Drawing.Pen($outlineColor, 3)
                $isLaboratory = $icon.Label -eq "LAB"
                $displayLabel = if ($isLaboratory) { "L" } else { $icon.Label }
                $iconWidth = if ($isLaboratory) { 34 } else { $iconRadius * 2 }
                $iconHeight = if ($isLaboratory) { 22 } else { $iconRadius * 2 }
                $iconLeft = [int]($iconX - ($iconWidth / 2))
                $iconTop = [int]($iconY - ($iconHeight / 2))
                if ($isLaboratory) {
                    $TargetGraphics.FillRectangle($iconBrush, $iconLeft, $iconTop, $iconWidth, $iconHeight)
                    $TargetGraphics.DrawRectangle($iconOutline, $iconLeft, $iconTop, $iconWidth - 1, $iconHeight - 1)
                } else {
                    $TargetGraphics.FillEllipse($iconBrush, $iconLeft, $iconTop, $iconWidth, $iconHeight)
                    $TargetGraphics.DrawEllipse($iconOutline, $iconLeft, $iconTop, $iconWidth, $iconHeight)
                }
                $iconTextFont = if ($isLaboratory) { New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold) } else { $landmarkFont }
                $textSize = $TargetGraphics.MeasureString($displayLabel, $iconTextFont)
                $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                $TargetGraphics.DrawString($displayLabel, $iconTextFont, $textBrush, $iconX - ($textSize.Width / 2), $iconY - ($textSize.Height / 2))
                $textBrush.Dispose()
                if ($isLaboratory) { $iconTextFont.Dispose() }
                $iconBrush.Dispose()
                $iconOutline.Dispose()
            }

            $cellLeft = $cellX * $CellSize + 2
            $cellTop = $cellY * $CellSize + 2
            foreach ($icon in $icons) {
                if ($icon.Label -eq "LAB") {
                    $TargetGraphics.DrawRectangle($laboratoryCellPen, $cellLeft, $cellTop, $CellSize - 5, $CellSize - 5)
                    break
                }
                if ($icon.Label -eq "B") {
                    $TargetGraphics.DrawRectangle($bunkerCellPen, $cellLeft, $cellTop, $CellSize - 5, $CellSize - 5)
                    break
                }
            }
        }
    }

    function Draw-SafeZoneLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        $denFormat = New-Object System.Drawing.StringFormat
        $denFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $denFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        foreach ($key in $denCells.Keys) {
            $coordinates = $key -split ","
            $cellLeft = [int]$coordinates[0] * $CellSize
            $cellTop = [int]$coordinates[1] * $CellSize
            $denName = $denCells[$key].Name
            $denWords = $denName -split " "
            $denDisplayName = if ($denWords.Count -gt 1) { "$($denWords[0])`n$($denWords[1..($denWords.Count - 1)] -join ' ')" } else { $denName }
            $denRectangle = [System.Drawing.Rectangle]::new([int]($cellLeft + 3), [int]($cellTop + 3), [int]($CellSize - 6), [int]($CellSize - 6))
            $denTextRectangle = [System.Drawing.RectangleF]::new([single]$denRectangle.X, [single]$denRectangle.Y, [single]$denRectangle.Width, [single]$denRectangle.Height)
            $TargetGraphics.FillRectangle($denBrush, $denRectangle)
            $TargetGraphics.DrawRectangle($denCellPen, $denRectangle)
            $TargetGraphics.DrawString($denDisplayName, $denNameFont, $denTextBrush, $denTextRectangle, $denFormat)
        }
        $denFormat.Dispose()
    }

    function Get-MetroSegmentKey {
        param([string]$FirstKey, [string]$SecondKey)

        if ([string]::CompareOrdinal($FirstKey, $SecondKey) -lt 0) { return "$FirstKey|$SecondKey" }
        return "$SecondKey|$FirstKey"
    }

    function Draw-MetroTracks {
        param([System.Drawing.Graphics]$TargetGraphics)

        $segmentOwners = @{}
        foreach ($metroLine in $metroLines) {
            for ($routeIndex = 1; $routeIndex -lt $metroLine.RouteCells.Count; $routeIndex++) {
                $segmentKey = Get-MetroSegmentKey $metroLine.RouteCells[$routeIndex - 1] $metroLine.RouteCells[$routeIndex]
                if (-not $segmentOwners.ContainsKey($segmentKey)) { $segmentOwners[$segmentKey] = @() }
                if ($segmentOwners[$segmentKey] -notcontains $metroLine.Name) { $segmentOwners[$segmentKey] += $metroLine.Name }
            }
        }

        foreach ($metroLine in $metroLines) {
            $metroLinePen = [System.Drawing.Pen]::new($metroLine.Color, [single]8)
            for ($routeIndex = 1; $routeIndex -lt $metroLine.RouteCells.Count; $routeIndex++) {
                $fromKey = $metroLine.RouteCells[$routeIndex - 1]
                $toKey = $metroLine.RouteCells[$routeIndex]
                $segmentKey = Get-MetroSegmentKey $fromKey $toKey
                $owners = @($segmentOwners[$segmentKey] | Sort-Object)
                $ownerIndex = [array]::IndexOf($owners, $metroLine.Name)
                $offset = ($ownerIndex - (($owners.Count - 1) / 2.0)) * 6
                $fromCoordinates = $fromKey -split ","
                $toCoordinates = $toKey -split ","
                $fromX = [int]$fromCoordinates[0] * $CellSize + ($CellSize / 2)
                $fromY = [int]$fromCoordinates[1] * $CellSize + ($CellSize / 2)
                $toX = [int]$toCoordinates[0] * $CellSize + ($CellSize / 2)
                $toY = [int]$toCoordinates[1] * $CellSize + ($CellSize / 2)
                $deltaX = $toX - $fromX
                $deltaY = $toY - $fromY
                $length = [Math]::Sqrt(($deltaX * $deltaX) + ($deltaY * $deltaY))
                $offsetX = if ($length -gt 0) { (-$deltaY / $length) * $offset } else { 0 }
                $offsetY = if ($length -gt 0) { ($deltaX / $length) * $offset } else { 0 }
                $TargetGraphics.DrawLine($metroLineOutlinePen, [single]($fromX + $offsetX), [single]($fromY + $offsetY), [single]($toX + $offsetX), [single]($toY + $offsetY))
                $TargetGraphics.DrawLine($metroLinePen, [single]($fromX + $offsetX), [single]($fromY + $offsetY), [single]($toX + $offsetX), [single]($toY + $offsetY))
            }
            $metroLinePen.Dispose()
        }
    }

    function Draw-MetroStations {
        param([System.Drawing.Graphics]$TargetGraphics)

        foreach ($stationKey in $metroStations.Keys) {
            $coordinates = $stationKey -split ","
            $centerX = [int]$coordinates[0] * $CellSize + [int]($CellSize / 2)
            $centerY = [int]$coordinates[1] * $CellSize + [int]($CellSize / 2)
            $stationRadius = if ($metroStations[$stationKey].Major) { 15 } else { 10 }
            $stationDiameter = $stationRadius * 2
            $TargetGraphics.FillEllipse($metroStationBrush, $centerX - $stationRadius, $centerY - $stationRadius, $stationDiameter, $stationDiameter)
            $TargetGraphics.DrawEllipse($metroStationPen, $centerX - $stationRadius, $centerY - $stationRadius, $stationDiameter, $stationDiameter)
            $stationLabelSize = $TargetGraphics.MeasureString($metroStations[$stationKey].Name, $metroStationNameFont)
            $stationLabelWidth = [int][Math]::Ceiling($stationLabelSize.Width) + 12
            $stationLabelHeight = [int][Math]::Ceiling($stationLabelSize.Height) + 7
            $stationLabelLeft = [int]($centerX - ($stationLabelWidth / 2))
            $stationLabelTop = [Math]::Max(2, [int]($centerY - $stationRadius - $stationLabelHeight - 8))
            $TargetGraphics.FillRectangle($metroStationLabelBrush, $stationLabelLeft, $stationLabelTop, $stationLabelWidth, $stationLabelHeight)
            $TargetGraphics.DrawRectangle($metroStationLabelPen, $stationLabelLeft, $stationLabelTop, $stationLabelWidth - 1, $stationLabelHeight - 1)
            $TargetGraphics.DrawString($metroStations[$stationKey].Name, $metroStationNameFont, $metroStationTextBrush, $stationLabelLeft + 6, $stationLabelTop + 3)
        }
    }

    function Draw-MetroLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        Draw-MetroTracks $TargetGraphics
        Draw-MetroStations $TargetGraphics
    }

    function Draw-GridLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        for ($coordinate = 0; $coordinate -le $width; $coordinate += $CellSize) { $TargetGraphics.DrawLine($gridPen, $coordinate, 0, $coordinate, $height) }
        for ($coordinate = 0; $coordinate -le $height; $coordinate += $CellSize) { $TargetGraphics.DrawLine($gridPen, 0, $coordinate, $width, $coordinate) }
    }

    function Draw-LabelLayer {
        param([System.Drawing.Graphics]$TargetGraphics)

        $TargetGraphics.DrawString($cityName.ToUpperInvariant(), $cityTitleFont, $cityTitleBrush, 28, 20)
        $TargetGraphics.DrawString("Population: $($population.ToString('N0'))   Seed: $Seed", $cityStatsFont, $cityStatsBrush, 36, 108)
        $districtFormat = New-Object System.Drawing.StringFormat
        $districtFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $districtFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        foreach ($zone in $zones) {
            $districtLabelWidth = [int]($zone.Radius * $CellSize * 1.5)
            $districtLabelHeight = 76
            $districtLabelLeft = [int]($zone.X * $CellSize + ($CellSize / 2) - ($districtLabelWidth / 2))
            $districtLabelTop = [int]($zone.Y * $CellSize + ($CellSize / 2) - ($districtLabelHeight / 2))
            $districtLabelRectangle = [System.Drawing.RectangleF]::new([single]$districtLabelLeft, [single]$districtLabelTop, [single]$districtLabelWidth, [single]$districtLabelHeight)
            $TargetGraphics.DrawString($zone.Name.ToUpperInvariant(), $districtNameFont, $districtNameBrush, $districtLabelRectangle, $districtFormat)
        }
        $districtFormat.Dispose()
    }

    function Export-MapLayer {
        param(
            [string]$LayerName,
            [scriptblock]$DrawLayer,
            [bool]$Opaque = $false
        )

        $layerBitmap = [System.Drawing.Bitmap]::new($width, $height)
        $layerGraphics = [System.Drawing.Graphics]::FromImage($layerBitmap)
        if ($Opaque) {
            $layerGraphics.Clear([System.Drawing.Color]::FromArgb(18, 18, 22))
        } else {
            $layerGraphics.Clear([System.Drawing.Color]::Transparent)
        }
        & $DrawLayer $layerGraphics
        $layerOutput = Get-MapLayerOutputPath $LayerName
        $layerBitmap.Save($layerOutput, [System.Drawing.Imaging.ImageFormat]::Png)
        $layerGraphics.Dispose()
        $layerBitmap.Dispose()
        return $layerOutput
    }

    function ConvertTo-MapColor {
        param([System.Drawing.Color]$Color)

        return [ordered]@{
            argb = $Color.ToArgb()
            alpha = $Color.A
            red = $Color.R
            green = $Color.G
            blue = $Color.B
            hex = ("#{0:X2}{1:X2}{2:X2}" -f $Color.R, $Color.G, $Color.B)
        }
    }

    function Get-EnvironmentTags {
        param(
            [int]$CellX,
            [int]$CellY
        )

        $cellKey = "$CellX,$CellY"
        $tags = @($terrainTypes[$cellKey])
        if ($buildingCells.ContainsKey($cellKey)) { $tags += "settlement" }
        if ($roadCells.ContainsKey($cellKey)) { $tags += "roadside" }
        if ($highwayCells.ContainsKey($cellKey) -or $diagonalHighwayCells.ContainsKey($cellKey)) { $tags += "highway" }
        if ($denCells.ContainsKey($cellKey)) { $tags += "safe_zone" }
        if ($metroStations.ContainsKey($cellKey)) { $tags += "metro_station" }
        if (@($metroLines | Where-Object { $_.RouteCells -contains $cellKey }).Count -gt 0) { $tags += "metro_route" }

        if ($landmarkCells.ContainsKey($cellKey)) {
            foreach ($landmark in @($landmarkCells[$cellKey])) {
                switch ($landmark.Label) {
                    "LAB" { $tags += @("laboratory", "radioactive", "industrial") }
                    "A" { $tags += "military" }
                    "B" { $tags += @("fortified", "military") }
                    "P" { $tags += @("civic", "security") }
                    "H" { $tags += @("civic", "medical") }
                    "F" { $tags += @("civic", "emergency_services") }
                    "G" { $tags += @("commercial", "service_station") }
                    "$" { $tags += @("commercial", "financial") }
                    "M" { $tags += "commercial" }
                    "L" { $tags += "recreation" }
                    "K" { $tags += "parkland" }
                }
            }
        }

        foreach ($landmarkKey in $landmarkCells.Keys) {
            $laboratoryPresent = @($landmarkCells[$landmarkKey] | Where-Object { $_.Label -eq "LAB" }).Count -gt 0
            if (-not $laboratoryPresent) { continue }
            $laboratoryCoordinates = $landmarkKey -split ","
            $distance = [Math]::Sqrt([Math]::Pow($CellX - [int]$laboratoryCoordinates[0], 2) + [Math]::Pow($CellY - [int]$laboratoryCoordinates[1], 2))
            if ($distance -le 3) {
                $tags += "radioactive"
                break
            }
        }

        return @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    }

    function Get-MapCellData {
        param(
            [int]$CellX,
            [int]$CellY
        )

        $cellKey = "$CellX,$CellY"
        $roadConnections = if ($roadCells.ContainsKey($cellKey)) { @("N", "E", "S", "W" | Where-Object { $roadCells[$cellKey][$_] }) } else { @() }
        $highwayConnections = if ($highwayCells.ContainsKey($cellKey)) { @("N", "E", "S", "W" | Where-Object { $highwayCells[$cellKey][$_] }) } else { @() }
        $blockadeDirections = @($blockadeMarkers | Where-Object { $_.CellKey -eq $cellKey } | ForEach-Object { $_.Direction })
        $cellLandmarks = @()
        if ($landmarkCells.ContainsKey($cellKey)) {
            foreach ($landmark in @($landmarkCells[$cellKey])) {
                $cellLandmarks += [ordered]@{ label = $landmark.Label; name = $landmark.Name; color = ConvertTo-MapColor $landmark.Color }
            }
        }

        $nearestZone = $zones | Sort-Object { [Math]::Pow($CellX - $_.X, 2) + [Math]::Pow($CellY - $_.Y, 2) } | Select-Object -First 1
    $nearestDistance = [Math]::Sqrt([Math]::Pow($CellX - $nearestZone.X, 2) + [Math]::Pow($CellY - $nearestZone.Y, 2))
        $isDeadZone = $false
        foreach ($deadZone in $deadZones) {
            if ([Math]::Sqrt([Math]::Pow($CellX - $deadZone.X, 2) + [Math]::Pow($CellY - $deadZone.Y, 2)) -le $deadZone.Radius) {
                $isDeadZone = $true
                break
            }
        }

        $neighborOffsets = @(
            @{ direction = "N"; x = 0; y = -1 },
            @{ direction = "E"; x = 1; y = 0 },
            @{ direction = "S"; x = 0; y = 1 },
            @{ direction = "W"; x = -1; y = 0 }
        )
        $neighbors = @()
        foreach ($offset in $neighborOffsets) {
            $neighborX = $CellX + $offset.x
            $neighborY = $CellY + $offset.y
            $inBounds = $neighborX -ge 0 -and $neighborX -lt $GridCells -and $neighborY -ge 0 -and $neighborY -lt $GridCells
            $neighborKey = if ($inBounds) { "$neighborX,$neighborY" } else { $null }
            $neighbors += [ordered]@{
                direction = $offset.direction
                inBounds = $inBounds
                x = if ($inBounds) { $neighborX } else { $null }
                y = if ($inBounds) { $neighborY } else { $null }
                worldX = if ($inBounds) { $neighborX } else { $null }
                worldY = if ($inBounds) { $neighborY - $originCellY } else { $null }
                roadPresent = $inBounds -and $roadCells.ContainsKey($neighborKey)
                roadConnected = $roadConnections -contains $offset.direction
                highwayPresent = $inBounds -and $highwayCells.ContainsKey($neighborKey)
                highwayConnected = $highwayConnections -contains $offset.direction
            }
        }

        $safeZone = $null
        if ($denCells.ContainsKey($cellKey)) {
            $den = $denCells[$cellKey]
            $safeZone = [ordered]@{
                name = $den.Name
                district = if ($den.District -ge 0) { $zones[$den.District].Name } else { $null }
                difficult = $den.Difficult
            }
        }

        $metroStop = $null
        if ($metroStations.ContainsKey($cellKey)) {
            $station = $metroStations[$cellKey]
            $metroStop = [ordered]@{ name = $station.Name; major = $station.Major; lines = @($station.Lines | Sort-Object); accessPath = @($station.AccessPath) }
        }
        $metroLineNames = @($metroLines | Where-Object { $_.RouteCells -contains $cellKey } | ForEach-Object { $_.Name } | Sort-Object -Unique)

        return [ordered]@{
            x = $CellX
            y = $CellY
            worldX = $CellX
            worldY = $CellY - $originCellY
            terrain = ConvertTo-MapColor $terrainCells[$cellKey]
            environment = [ordered]@{ terrain = $terrainTypes[$cellKey]; tags = @(Get-EnvironmentTags $CellX $CellY) }
            district = [ordered]@{ name = $nearestZone.Name; distance = [Math]::Round([Math]::Sqrt([Math]::Pow($CellX - $nearestZone.X, 2) + [Math]::Pow($CellY - $nearestZone.Y, 2)), 3); inside = $nearestDistance -le $nearestZone.Radius }
            deadZone = $isDeadZone
            building = if ($buildingCells.ContainsKey($cellKey)) { [ordered]@{ present = $true; color = ConvertTo-MapColor $buildingCells[$cellKey] } } else { [ordered]@{ present = $false } }
            landmarks = $cellLandmarks
            safeZone = $safeZone
            road = [ordered]@{ present = $roadCells.ContainsKey($cellKey); connections = $roadConnections; degree = $roadConnections.Count; blockades = $blockadeDirections }
            highway = [ordered]@{ present = $highwayCells.ContainsKey($cellKey); connections = $highwayConnections; degree = $highwayConnections.Count; bridge = $bridgeCells.ContainsKey($cellKey); bridgeCrossingDirection = $bridgeCrossingDirections[$cellKey]; diagonal = $diagonalHighwayCells.ContainsKey($cellKey) }
            metro = [ordered]@{ lines = $metroLineNames; stop = $metroStop }
            neighbors = $neighbors
        }
    }

    function Export-MapData {
        $cells = @()
        for ($cellY = 0; $cellY -lt $GridCells; $cellY++) {
            for ($cellX = 0; $cellX -lt $GridCells; $cellX++) {
                $cells += Get-MapCellData $cellX $cellY
            }
        }

        $districtData = @($zones | ForEach-Object {
            $district = $_
            $districtTags = @($cells | Where-Object { $_.district.name -eq $district.Name -and $_.district.inside } | ForEach-Object { $_.environment.tags } | Sort-Object -Unique)
            [ordered]@{ name = $district.Name; x = $district.X; y = $district.Y; radius = $district.Radius; color = ConvertTo-MapColor $district.Color; environment = [ordered]@{ tags = $districtTags } }
        })
        $safeZoneData = @($denCells.GetEnumerator() | Sort-Object { $_.Value.District } | ForEach-Object {
            $coordinates = $_.Key -split ","
            [ordered]@{ name = $_.Value.Name; district = if ($_.Value.District -ge 0) { $zones[$_.Value.District].Name } else { $null }; difficult = $_.Value.Difficult; x = [int]$coordinates[0]; y = [int]$coordinates[1]; worldX = [int]$coordinates[0]; worldY = [int]$coordinates[1] - $originCellY }
        })
        $metroLineData = @($metroLines | ForEach-Object { [ordered]@{ name = $_.Name; color = ConvertTo-MapColor $_.Color; schematicPath = @($_.Path); routeCells = @($_.RouteCells) } })
        $metroStopData = @($metroStations.GetEnumerator() | Sort-Object Key | ForEach-Object {
            $coordinates = $_.Key -split ","
            [ordered]@{ name = $_.Value.Name; major = $_.Value.Major; lines = @($_.Value.Lines | Sort-Object); accessPath = @($_.Value.AccessPath); x = [int]$coordinates[0]; y = [int]$coordinates[1]; worldX = [int]$coordinates[0]; worldY = [int]$coordinates[1] - $originCellY }
        })
        $mapData = [ordered]@{
            schemaVersion = 2
            map = [ordered]@{ seed = $Seed; gridCells = $GridCells; cellSize = $CellSize; width = $width; height = $height; origin = [ordered]@{ cellX = 0; cellY = $originCellY; worldX = 0; worldY = 0 }; environment = [ordered]@{ taggingVersion = 1; tags = @($cells | ForEach-Object { $_.environment.tags } | Sort-Object -Unique) } }
            generation = [ordered]@{ roadDepth = $RoadDepth; branchChance = $BranchChance; blockadeChance = $BlockadeChance; bridgeChance = $BridgeChance; biomeOpacity = $biomeOpacity }
            statistics = [ordered]@{ population = $population; roadCells = $roadCells.Count; highwayCells = $highwayCells.Count; buildingCells = $buildingCells.Count; landmarkCells = $landmarkCells.Count; safeZones = $denCells.Count; metroLines = $metroLines.Count; metroStops = $metroStations.Count }
            districts = $districtData
            safeZones = $safeZoneData
            metro = [ordered]@{ lines = $metroLineData; stops = $metroStopData }
            cells = $cells
        }

        $mapDataOutput = [System.IO.Path]::ChangeExtension($Output, ".json")
        [System.IO.File]::WriteAllText($mapDataOutput, ($mapData | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
        return $mapDataOutput
    }

function Add-MetroLine {
    param(
        [string]$Name,
        [System.Drawing.Color]$Color,
        [string[]]$RouteNodes
    )

    $resolvedNodes = @()
    foreach ($node in $RouteNodes) {
        if ($node -match '^\d+,\d+$') { continue }

        $metroZone = @($zones | Where-Object { $_.Name -eq $node })[0]
        if ($null -eq $metroZone) { throw "Metro district '$node' was not found." }
        $requestedStationKey = Get-MetroStationKey $metroZone
        $stationKey = Add-MetroStop $requestedStationKey $node $true $Name $true
        if ($null -ne $stationKey) { $resolvedNodes += $stationKey }
    }

    $metroRoute = @()
    $guideRouteIndexes = @{ 0 = $true }
    for ($nodeIndex = 0; $nodeIndex -lt ($resolvedNodes.Count - 1); $nodeIndex++) {
        $segment = @(Get-MetroPath $resolvedNodes[$nodeIndex] $resolvedNodes[$nodeIndex + 1])
        if ($segment.Count -eq 0) { throw "Metro A* could not connect $($resolvedNodes[$nodeIndex]) to $($resolvedNodes[$nodeIndex + 1])." }
        if ($metroRoute.Count -gt 0) { $segment = @($segment | Select-Object -Skip 1) }
        $metroRoute += $segment
        $guideRouteIndexes[$metroRoute.Count - 1] = $true
    }

    $stopsByRouteIndex = @{}
    for ($pathIndex = 8; $pathIndex -lt ($metroRoute.Count - 1); $pathIndex += 8) {
        if ($guideRouteIndexes.ContainsKey($pathIndex)) { continue }
        $stationKey = Add-MetroStop $metroRoute[$pathIndex] "" $false $Name $true
        if ($null -ne $stationKey) { $stopsByRouteIndex[$pathIndex] = $stationKey }
    }

    $metroRoute = @(Connect-MetroRouteThroughStops $metroRoute $stopsByRouteIndex $guideRouteIndexes)
    if ($metroRoute.Count -eq 0) { throw "Metro A* could not connect all stops on $Name." }

    $script:metroLines += @{ Name = $Name; Color = $Color; Path = (Get-MetroSchematicPath $metroRoute); RouteCells = $metroRoute }
}

function Add-HighwayRun {
    param(
        [int]$StartX,
        [int]$StartY,
        [int]$EndX,
        [int]$EndY
    )

    if ($StartX -ne $EndX -and $StartY -ne $EndY) {
        throw "Highway runs must follow one grid axis."
    }
    $cellX = $StartX
    $cellY = $StartY
    while ($cellX -ne $EndX -or $cellY -ne $EndY) {
        $direction = if ($cellX -lt $EndX) { "E" } elseif ($cellX -gt $EndX) { "W" } elseif ($cellY -lt $EndY) { "S" } else { "N" }
        Add-HighwayConnection $cellX $cellY $direction
        switch ($direction) {
            "N" { $cellY-- }
            "E" { $cellX++ }
            "S" { $cellY++ }
            "W" { $cellX-- }
        }
    }
}

function Repair-RoadDeadEnds {
    $deadEnds = @($roadCells.Keys | Where-Object { (Get-RoadDegree $roadCells[$_]) -eq 1 })
    foreach ($deadEndKey in $deadEnds) {
        $coordinates = $deadEndKey -split ","
        $startX = [int]$coordinates[0]
        $startY = [int]$coordinates[1]
        if ($startX -eq 0 -and $startY -eq $originCellY) { continue }

        $targets = @{}
        foreach ($candidateKey in $roadCells.Keys) {
            if ($candidateKey -eq $deadEndKey) { continue }
            $candidateCoordinates = $candidateKey -split ","
            $candidateX = [int]$candidateCoordinates[0]
            $candidateY = [int]$candidateCoordinates[1]
            $distance = [Math]::Abs($candidateX - $startX) + [Math]::Abs($candidateY - $startY)
            if ($distance -lt 2 -or $distance -gt $DeadEndRepairRadius) { continue }
            if ((Get-RoadDegree $roadCells[$candidateKey]) -lt 2) { continue }
            if ($highwayCells.ContainsKey($candidateKey) -or $diagonalHighwayCells.ContainsKey($candidateKey)) { continue }
            $targets[$candidateKey] = $true
        }

        if ($targets.Count -eq 0) { continue }

        $openSet = @{ $deadEndKey = $true }
        $cameFrom = @{}
        $gScore = @{ $deadEndKey = 0.0 }
        $path = $null
        while ($openSet.Count -gt 0) {
            $currentKey = $null
            $currentScore = [double]::PositiveInfinity
            foreach ($openKey in $openSet.Keys) {
                $openCoordinates = $openKey -split ","
                $openX = [int]$openCoordinates[0]
                $openY = [int]$openCoordinates[1]
                $heuristic = [double]::PositiveInfinity
                foreach ($targetKey in $targets.Keys) {
                    $targetCoordinates = $targetKey -split ","
                    $heuristic = [Math]::Min($heuristic, [Math]::Abs($openX - [int]$targetCoordinates[0]) + [Math]::Abs($openY - [int]$targetCoordinates[1]))
                }
                $score = $gScore[$openKey] + $heuristic
                if ($score -lt $currentScore) {
                    $currentKey = $openKey
                    $currentScore = $score
                }
            }

            if ($targets.ContainsKey($currentKey)) {
                $path = @($currentKey)
                while ($cameFrom.ContainsKey($path[0])) { $path = @($cameFrom[$path[0]]) + $path }
                break
            }
            $openSet.Remove($currentKey)

            $currentCoordinates = $currentKey -split ","
            $currentX = [int]$currentCoordinates[0]
            $currentY = [int]$currentCoordinates[1]
            foreach ($direction in @("N", "E", "S", "W")) {
                $neighborKey = Get-RoadNeighborKey $currentX $currentY $direction
                if ($null -eq $neighborKey -or $highwayCells.ContainsKey($neighborKey) -or $diagonalHighwayCells.ContainsKey($neighborKey)) { continue }
                $neighborCoordinates = $neighborKey -split ","
                $distanceFromStart = [Math]::Abs($startX - [int]$neighborCoordinates[0]) + [Math]::Abs($startY - [int]$neighborCoordinates[1])
                if ($distanceFromStart -gt $DeadEndRepairRadius) { continue }

                $stepCost = if ($roadCells.ContainsKey($neighborKey) -and -not $targets.ContainsKey($neighborKey)) { 4.0 } else { 1.0 }
                $tentativeScore = $gScore[$currentKey] + $stepCost
                if (-not $gScore.ContainsKey($neighborKey) -or $tentativeScore -lt $gScore[$neighborKey]) {
                    $cameFrom[$neighborKey] = $currentKey
                    $gScore[$neighborKey] = $tentativeScore
                    $openSet[$neighborKey] = $true
                }
            }
        }

        if ($null -eq $path) { continue }
        for ($pathIndex = 0; $pathIndex -lt ($path.Count - 1); $pathIndex++) {
            $fromCoordinates = $path[$pathIndex] -split ","
            $toCoordinates = $path[$pathIndex + 1] -split ","
            $direction = if ([int]$toCoordinates[0] -gt [int]$fromCoordinates[0]) { "E" } elseif ([int]$toCoordinates[0] -lt [int]$fromCoordinates[0]) { "W" } elseif ([int]$toCoordinates[1] -gt [int]$fromCoordinates[1]) { "S" } else { "N" }
            Add-RoadConnection ([int]$fromCoordinates[0]) ([int]$fromCoordinates[1]) $direction
        }
    }
}

# Main arterial: each cell is an individual straight road tile.
for ($cellX = 0; $cellX -lt ($GridCells - 1); $cellX++) {
    Add-RoadConnection $cellX $originCellY "E"
}

# Recursively grow branches from the origin and along the arterial.
Grow-Road 0 $originCellY "N" $RoadDepth
Grow-Road 0 $originCellY "S" $RoadDepth
for ($cellX = 6; $cellX -lt ($GridCells - 2); $cellX += 6) {
    if ($random.NextDouble() -lt 0.85) {
        $direction = if ($random.Next(0, 2) -eq 0) { "N" } else { "S" }
        Grow-Road $cellX $originCellY $direction $RoadDepth
    }
}

# Deterministic interstate grid: straight corridors with only deliberate 90-degree jogs.
$westInterstateX = [int](($GridCells - 1) * 0.24)
$eastInterstateX = [int](($GridCells - 1) * 0.76)
$northInterstateY = [int](($GridCells - 1) * 0.30)
$southInterstateY = [int](($GridCells - 1) * 0.70)
$jogDistance = [Math]::Max(2, [int]($GridCells * 0.05))
$verticalJogY = [int](($GridCells - 1) * 0.62)
$horizontalJogX = [int](($GridCells - 1) * 0.58)

Add-HighwayRun $westInterstateX 0 $westInterstateX ($GridCells - 1)
Add-HighwayRun $eastInterstateX 0 $eastInterstateX $verticalJogY
Add-HighwayRun $eastInterstateX $verticalJogY ($eastInterstateX - $jogDistance) $verticalJogY
Add-HighwayRun ($eastInterstateX - $jogDistance) $verticalJogY ($eastInterstateX - $jogDistance) ($GridCells - 1)
Add-HighwayRun 0 $northInterstateY ($GridCells - 1) $northInterstateY
Add-HighwayRun 0 $southInterstateY $horizontalJogX $southInterstateY
Add-HighwayRun $horizontalJogX $southInterstateY $horizontalJogX ($southInterstateY + $jogDistance)
Add-HighwayRun $horizontalJogX ($southInterstateY + $jogDistance) ($GridCells - 1) ($southInterstateY + $jogDistance)

function Restrict-HighwayCrossings {
    foreach ($key in $highwayCells.Keys) {
        $coordinates = $key -split ","
        $cellX = [int]$coordinates[0]
        $cellY = [int]$coordinates[1]

        $ordinaryDirections = @("N", "E", "S", "W" | Where-Object { $roadCells[$key][$_] -and -not $highwayCells[$key][$_] })
        if ($ordinaryDirections.Count -eq 0) { continue }

        $hasVerticalHighway = $highwayCells[$key].N -and $highwayCells[$key].S
        $hasHorizontalHighway = $highwayCells[$key].E -and $highwayCells[$key].W
        $isOverpass = ($hasVerticalHighway -and $ordinaryDirections -contains "E" -and $ordinaryDirections -contains "W") -or ($hasHorizontalHighway -and $ordinaryDirections -contains "N" -and $ordinaryDirections -contains "S")
        if ($isOverpass -and $random.NextDouble() -lt $BridgeChance) {
            $bridgeCells[$key] = $true
            continue
        }

        foreach ($direction in $ordinaryDirections) {
            Remove-RoadConnection $cellX $cellY $direction
        }
    }
}

function Repair-DeadEndsAcrossHighways {
    $deadEnds = @($roadCells.Keys | Where-Object {
        -not $highwayCells.ContainsKey($_) -and (Get-RoadDegree $roadCells[$_]) -eq 1
    })

    foreach ($deadEndKey in $deadEnds) {
        $coordinates = $deadEndKey -split ","
        $startX = [int]$coordinates[0]
        $startY = [int]$coordinates[1]

        foreach ($direction in @("N", "E", "S", "W")) {
            $nextKey = Get-RoadNeighborKey $startX $startY $direction
            if ($null -eq $nextKey -or -not $highwayCells.ContainsKey($nextKey)) { continue }

            $highwaySpan = @()
            for ($span = 0; $span -lt 3; $span++) {
                if (-not $highwayCells.ContainsKey($nextKey)) { break }
                $highwaySpan += $nextKey
                $highwayCoordinates = $nextKey -split ","
                $nextKey = Get-RoadNeighborKey ([int]$highwayCoordinates[0]) ([int]$highwayCoordinates[1]) $direction
                if ($null -eq $nextKey) { break }
            }

            if ($highwaySpan.Count -eq 0 -or $highwayCells.ContainsKey($nextKey)) { continue }
            if (-not $roadCells.ContainsKey($nextKey) -or (Get-RoadDegree $roadCells[$nextKey]) -eq 0) { continue }
            if ($random.NextDouble() -gt $DeadEndBridgeChance) { break }

            Add-RoadConnection $startX $startY $direction
            foreach ($highwayKey in $highwaySpan) {
                $highwayCoordinates = $highwayKey -split ","
                Add-RoadConnection ([int]$highwayCoordinates[0]) ([int]$highwayCoordinates[1]) $direction
                $bridgeCells[$highwayKey] = $true
                $bridgeCrossingDirections[$highwayKey] = $direction
            }
            break
        }
    }
}

function Add-HighwayRamp {
    param(
        [int]$HighwayX,
        [int]$HighwayY,
        [string]$ExitDirection,
        [string]$TravelDirection,
        [int]$DistrictIndex = -1
    )

    $highwayKey = "$HighwayX,$HighwayY"
    $connectionKey = "$highwayKey`:$ExitDirection"
    if (-not $highwayCells.ContainsKey($highwayKey) -or $usedHighwayRampConnections.ContainsKey($connectionKey)) { return $false }

    $rampKey = Get-RoadNeighborKey $HighwayX $HighwayY $ExitDirection
    if ($null -eq $rampKey -or $highwayCells.ContainsKey($rampKey)) { return $false }
    $rampCoordinates = $rampKey -split ","
    $rampX = [int]$rampCoordinates[0]
    $rampY = [int]$rampCoordinates[1]
    $exitKey = Get-RoadNeighborKey $rampX $rampY $TravelDirection
    if ($null -eq $exitKey -or $highwayCells.ContainsKey($exitKey)) { return $false }

    Add-RoadConnection $HighwayX $HighwayY $ExitDirection
    Add-RoadConnection $rampX $rampY $TravelDirection
    $usedHighwayRampConnections[$connectionKey] = $true
    $script:highwayRamps += @{ X = $HighwayX; Y = $HighwayY; Exit = $ExitDirection; Travel = $TravelDirection; District = $DistrictIndex }
    return $true
}

function Add-DistrictHighwayRamp {
    param(
        [hashtable]$Zone,
        [int]$DistrictIndex
    )

    $bestRamp = $null
    $bestScore = [double]::PositiveInfinity
    foreach ($highwayKey in $highwayCells.Keys) {
        $highwayCoordinates = $highwayKey -split ","
        $highwayX = [int]$highwayCoordinates[0]
        $highwayY = [int]$highwayCoordinates[1]
        foreach ($exitDirection in @("N", "E", "S", "W")) {
            $connectionKey = "$highwayKey`:$exitDirection"
            if ($usedHighwayRampConnections.ContainsKey($connectionKey)) { continue }
            $rampKey = Get-RoadNeighborKey $highwayX $highwayY $exitDirection
            if ($null -eq $rampKey -or $highwayCells.ContainsKey($rampKey)) { continue }
            $rampCoordinates = $rampKey -split ","

            foreach ($travelDirection in @("N", "E", "S", "W")) {
                if ($travelDirection -eq $exitDirection) { continue }
                $exitKey = Get-RoadNeighborKey ([int]$rampCoordinates[0]) ([int]$rampCoordinates[1]) $travelDirection
                if ($null -eq $exitKey -or $highwayCells.ContainsKey($exitKey)) { continue }
                $exitCoordinates = $exitKey -split ","
                $distanceToDistrict = [Math]::Abs([int]$exitCoordinates[0] - $Zone.X) + [Math]::Abs([int]$exitCoordinates[1] - $Zone.Y)
                $mergesWithLocalRoad = $roadCells.ContainsKey($exitKey) -and (Get-RoadDegree $roadCells[$exitKey]) -gt 0
                $score = $distanceToDistrict + $(if ($mergesWithLocalRoad) { 0 } else { $GridCells * 2 })
                if ($score -lt $bestScore) {
                    $bestScore = $score
                    $bestRamp = @{ X = $highwayX; Y = $highwayY; Exit = $exitDirection; Travel = $travelDirection }
                }
            }
        }
    }

    if ($null -ne $bestRamp) {
        return Add-HighwayRamp $bestRamp.X $bestRamp.Y $bestRamp.Exit $bestRamp.Travel $DistrictIndex
    }
    return $false
}

function Get-OppositeDirection {
    param([string]$Direction)

    switch ($Direction) {
        "N" { "S" }
        "E" { "W" }
        "S" { "N" }
        "W" { "E" }
    }
}

function Add-BlockadeConnection {
    param(
        [string]$CellKey,
        [string]$Direction
    )

    $coordinates = $CellKey -split ","
    $neighborKey = Get-RoadNeighborKey ([int]$coordinates[0]) ([int]$coordinates[1]) $Direction
    if ($null -eq $neighborKey) { return }
    $blockadeConnections["$CellKey`:$Direction"] = $true
    $blockadeConnections["$neighborKey`:$((Get-OppositeDirection $Direction))"] = $true
}

function Test-RouteToHighwayOrWorldEdge {
    param([string]$StartKey)

    $queue = @($StartKey)
    $visited = @{ $StartKey = $true }
    $queueIndex = 0
    while ($queueIndex -lt $queue.Count) {
        $currentKey = $queue[$queueIndex]
        $queueIndex++
        if ($highwayCells.ContainsKey($currentKey)) { return $true }

        $coordinates = $currentKey -split ","
        $cellX = [int]$coordinates[0]
        $cellY = [int]$coordinates[1]
        if ($cellX -eq 0 -or $cellX -eq ($GridCells - 1) -or $cellY -eq 0 -or $cellY -eq ($GridCells - 1)) { return $true }

        foreach ($direction in @("N", "E", "S", "W")) {
            if (-not $roadCells[$currentKey][$direction]) { continue }
            if ($blockadeConnections.ContainsKey("$currentKey`:$direction")) { continue }
            $neighborKey = Get-RoadNeighborKey $cellX $cellY $direction
            if ($null -ne $neighborKey -and $roadCells.ContainsKey($neighborKey) -and -not $visited.ContainsKey($neighborKey)) {
                $visited[$neighborKey] = $true
                $queue += $neighborKey
            }
        }
    }

    return $false
}

function Test-BlockadePlacement {
    param(
        [string]$CellKey,
        [string]$Direction
    )

    if (-not $roadCells.ContainsKey($CellKey)) { return $false }
    if ($highwayCells.ContainsKey($CellKey) -or $diagonalHighwayCells.ContainsKey($CellKey)) { return $false }
    if (-not $roadCells[$CellKey][$Direction]) { return $false }

    $coordinates = $CellKey -split ","
    $neighborKey = Get-RoadNeighborKey ([int]$coordinates[0]) ([int]$coordinates[1]) $Direction
    if ($null -eq $neighborKey -or -not $roadCells.ContainsKey($neighborKey)) { return $false }

    Add-BlockadeConnection $CellKey $Direction
    $sourceHasExit = Test-RouteToHighwayOrWorldEdge $CellKey
    $targetHasExit = Test-RouteToHighwayOrWorldEdge $neighborKey
    $blockadeConnections.Remove("$CellKey`:$Direction")
    $blockadeConnections.Remove("$neighborKey`:$((Get-OppositeDirection $Direction))")
    return $sourceHasExit -and $targetHasExit
}

# Close nearby dead ends where possible; isolated ends remain valid roads.
Repair-RoadDeadEnds
Restrict-HighwayCrossings
Repair-DeadEndsAcrossHighways

# Every district receives an on/off-ramp, preferably merging with an existing local road.
for ($districtIndex = 0; $districtIndex -lt $zones.Count; $districtIndex++) {
    Add-DistrictHighwayRamp $zones[$districtIndex] $districtIndex | Out-Null
}

# A district without any ordinary road cannot support homes, landmarks, or a metro stop.
foreach ($zone in $zones) {
    $hasLocalRoad = $false
    foreach ($roadKey in $roadCells.Keys) {
        if ($highwayCells.ContainsKey($roadKey) -or $diagonalHighwayCells.ContainsKey($roadKey)) { continue }
        $roadCoordinates = $roadKey -split ","
        $distance = [Math]::Sqrt([Math]::Pow([int]$roadCoordinates[0] - $zone.X, 2) + [Math]::Pow([int]$roadCoordinates[1] - $zone.Y, 2))
        if ($distance -le $zone.Radius) {
            $hasLocalRoad = $true
            break
        }
    }
    if ($hasLocalRoad) { continue }

    $streetSpan = [Math]::Max(2, [int]($zone.Radius * 0.45))
    $westX = [Math]::Max(0, $zone.X - $streetSpan)
    $eastX = [Math]::Min($GridCells - 1, $zone.X + $streetSpan)
    $northY = [Math]::Max(0, $zone.Y - $streetSpan)
    $southY = [Math]::Min($GridCells - 1, $zone.Y + $streetSpan)
    for ($cellX = $westX; $cellX -lt $eastX; $cellX++) {
        $fromKey = "$cellX,$($zone.Y)"
        $toKey = "$($cellX + 1),$($zone.Y)"
        if (-not $highwayCells.ContainsKey($fromKey) -and -not $highwayCells.ContainsKey($toKey) -and -not $diagonalHighwayCells.ContainsKey($fromKey) -and -not $diagonalHighwayCells.ContainsKey($toKey)) {
            Add-RoadConnection $cellX $zone.Y "E"
        }
    }
    for ($cellY = $northY; $cellY -lt $southY; $cellY++) {
        $fromKey = "$($zone.X),$cellY"
        $toKey = "$($zone.X),$($cellY + 1)"
        if (-not $highwayCells.ContainsKey($fromKey) -and -not $highwayCells.ContainsKey($toKey) -and -not $diagonalHighwayCells.ContainsKey($fromKey) -and -not $diagonalHighwayCells.ContainsKey($toKey)) {
            Add-RoadConnection $zone.X $cellY "S"
        }
    }
}

# Flood-fill the road network from the origin so landmarks only use reachable roads.
$reachableRoadCells = @{}
$originKey = "0,$originCellY"
if ($roadCells.ContainsKey($originKey)) {
    $roadQueue = @($originKey)
    $queueIndex = 0
    $reachableRoadCells[$originKey] = $true

    while ($queueIndex -lt $roadQueue.Count) {
        $currentKey = $roadQueue[$queueIndex]
        $queueIndex++
        $currentCoordinates = $currentKey -split ","
        $currentX = [int]$currentCoordinates[0]
        $currentY = [int]$currentCoordinates[1]

        foreach ($direction in @("N", "E", "S", "W")) {
            if (-not $roadCells[$currentKey][$direction]) { continue }
            $neighborKey = Get-RoadNeighborKey $currentX $currentY $direction
            if ($null -ne $neighborKey -and $roadCells.ContainsKey($neighborKey) -and -not $reachableRoadCells.ContainsKey($neighborKey)) {
                $reachableRoadCells[$neighborKey] = $true
                $roadQueue += $neighborKey
            }
        }
    }
}

# Generate irregular district cells behind the roads.
$biomeOpacity = [Math]::Max(0, [Math]::Min(255, $BiomeOpacity))
for ($cellY = 0; $cellY -lt $GridCells; $cellY++) {
    for ($cellX = 0; $cellX -lt $GridCells; $cellX++) {
        $normalizedX = $cellX / [Math]::Max($GridCells - 1, 1)
        $normalizedY = $cellY / [Math]::Max($GridCells - 1, 1)
        $centerBias = 1 - [Math]::Abs($normalizedX - 0.5) * 2
        $grassWeight = 0.55 - ($normalizedY * 0.2) + ((1 - $normalizedX) * 0.15)
        $sandWeight = 0.2 + ($centerBias * 0.35) + ((1 - $normalizedY) * 0.08)
        $dirtWeight = 0.2 + ($normalizedY * 0.5) + (($normalizedX - 0.5) * 0.08)
        $noise = (($cellX * 37 + $cellY * 67 + $Seed) % 17) / 100.0
        $grassWeight = [Math]::Max(0.05, $grassWeight + $noise)
        $sandWeight = [Math]::Max(0.05, $sandWeight - ($noise * 0.5))
        $dirtWeight = [Math]::Max(0.05, $dirtWeight + (($noise - 0.08) * 0.5))
        $weightTotal = $grassWeight + $sandWeight + $dirtWeight
        $biomeRed = [int](($grassColor.R * $grassWeight + $sandColor.R * $sandWeight + $dirtColor.R * $dirtWeight) / $weightTotal)
        $biomeGreen = [int](($grassColor.G * $grassWeight + $sandColor.G * $sandWeight + $dirtColor.G * $dirtWeight) / $weightTotal)
        $biomeBlue = [int](($grassColor.B * $grassWeight + $sandColor.B * $sandWeight + $dirtColor.B * $dirtWeight) / $weightTotal)
        $terrainColor = [System.Drawing.Color]::FromArgb($biomeOpacity, $biomeRed, $biomeGreen, $biomeBlue)
        $terrainKey = "$cellX,$cellY"
        $terrainCells[$terrainKey] = $terrainColor
        $terrainTypes[$terrainKey] = if ($grassWeight -ge $sandWeight -and $grassWeight -ge $dirtWeight) { "grassland" } elseif ($sandWeight -ge $dirtWeight) { "sandy" } else { "dirt" }
        $biomeBrush = New-Object System.Drawing.SolidBrush($terrainColor)
        $graphics.FillRectangle($biomeBrush, $cellX * $CellSize, $cellY * $CellSize, $CellSize, $CellSize)
        $biomeBrush.Dispose()
    }
}

$buildingMargin = [Math]::Max(6, [int]($CellSize * 0.12))
for ($cellY = 0; $cellY -lt $GridCells; $cellY++) {
    for ($cellX = 0; $cellX -lt $GridCells; $cellX++) {
        $nearestZone = $null
        $nearestDistance = [double]::PositiveInfinity
        foreach ($zone in $zones) {
            $distance = [Math]::Sqrt([Math]::Pow($cellX - $zone.X, 2) + [Math]::Pow($cellY - $zone.Y, 2))
            if ($distance -lt $nearestDistance) {
                $nearestZone = $zone
                $nearestDistance = $distance
            }
        }

        $inDeadZone = $false
        foreach ($deadZone in $deadZones) {
            $deadZoneDistance = [Math]::Sqrt([Math]::Pow($cellX - $deadZone.X, 2) + [Math]::Pow($cellY - $deadZone.Y, 2))
            if ($deadZoneDistance -le $deadZone.Radius) {
                $inDeadZone = $true
                break
            }
        }

        $cellKey = "$cellX,$cellY"
        $roadNearby = $roadCells.ContainsKey($cellKey)
        $localRoadNearby = $roadCells.ContainsKey($cellKey) -and -not $highwayCells.ContainsKey($cellKey) -and -not $diagonalHighwayCells.ContainsKey($cellKey)
        $highwayNearby = $highwayCells.ContainsKey($cellKey) -or $diagonalHighwayCells.ContainsKey($cellKey)
        foreach ($direction in @("N", "E", "S", "W")) {
            $neighborKey = Get-RoadNeighborKey $cellX $cellY $direction
            if ($null -eq $neighborKey) { continue }
            if ($roadCells.ContainsKey($neighborKey)) { $roadNearby = $true }
            if ($roadCells.ContainsKey($neighborKey) -and -not $highwayCells.ContainsKey($neighborKey) -and -not $diagonalHighwayCells.ContainsKey($neighborKey)) { $localRoadNearby = $true }
            if ($highwayCells.ContainsKey($neighborKey) -or $diagonalHighwayCells.ContainsKey($neighborKey)) { $highwayNearby = $true }
        }

        if ($nearestDistance -le $nearestZone.Radius -and -not $inDeadZone -and -not $highwayCells.ContainsKey($cellKey) -and -not $diagonalHighwayCells.ContainsKey($cellKey) -and $roadNearby -and (-not $highwayNearby -or $localRoadNearby)) {
            $density = 0.75 + 0.25 * (1 - ($nearestDistance / $nearestZone.Radius))
            if ($random.NextDouble() -lt $density) {
                $left = $cellX * $CellSize + $buildingMargin
                $top = $cellY * $CellSize + $buildingMargin
                $buildingSize = $CellSize - ($buildingMargin * 2)
                $buildingCells["$cellX,$cellY"] = $nearestZone.Color
                $buildingBrush = New-Object System.Drawing.SolidBrush($nearestZone.Color)
                $buildingPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, $nearestZone.Color.R, $nearestZone.Color.G, $nearestZone.Color.B), 2)
                $graphics.FillRectangle($buildingBrush, $left, $top, $buildingSize, $buildingSize)
                $graphics.DrawRectangle($buildingPen, $left, $top, $buildingSize - 1, $buildingSize - 1)
                $buildingBrush.Dispose()
                $buildingPen.Dispose()
            }
        }
    }
}

# Place up to two landmarks in each eligible city cell.
$commonLandmarks = @(
    @{ Label = "L"; Name = "Leisure"; Color = [System.Drawing.Color]::FromArgb(255, 80, 200, 125) },
    @{ Label = "M"; Name = "Market"; Color = [System.Drawing.Color]::FromArgb(255, 235, 180, 70) },
    @{ Label = "K"; Name = "Park"; Color = [System.Drawing.Color]::FromArgb(255, 105, 170, 80) }
)
$policeLandmark = @{ Label = "P"; Name = "Police"; Color = [System.Drawing.Color]::FromArgb(255, 70, 130, 230) }
$hospitalLandmark = @{ Label = "H"; Name = "Hospital"; Color = [System.Drawing.Color]::FromArgb(255, 230, 75, 85) }
$fireLandmark = @{ Label = "F"; Name = "Fire"; Color = [System.Drawing.Color]::FromArgb(255, 235, 110, 55) }
$petrolStationLandmark = @{ Label = "G"; Name = "Petrol Station"; Color = [System.Drawing.Color]::FromArgb(255, 60, 185, 115) }
$bankLandmark = @{ Label = '$'; Name = "Bank"; Color = [System.Drawing.Color]::FromArgb(255, 230, 185, 60) }
$rareLandmarks = @(
    @{ Label = "A"; Name = "Army Base"; Color = [System.Drawing.Color]::FromArgb(255, 170, 190, 85) },
    @{ Label = "LAB"; Name = "Laboratory"; Color = [System.Drawing.Color]::FromArgb(255, 185, 90, 220) },
    @{ Label = "B"; Name = "Bunker"; Color = [System.Drawing.Color]::FromArgb(255, 130, 135, 145) }
)
$landmarkCells = @{}
$landmarkCandidates = @{}
foreach ($key in $reachableRoadCells.Keys) {
    if ($highwayCells.ContainsKey($key) -or $diagonalHighwayCells.ContainsKey($key)) { continue }
    $landmarkCandidates[$key] = $true
}

function Test-LandmarkSpacing {
    param(
        [string]$Label,
        [int]$CellX,
        [int]$CellY,
        [int]$MinimumDistance = 20
    )

    foreach ($existingKey in $landmarkCells.Keys) {
        $existingCoordinates = $existingKey -split ","
        $existingX = [int]$existingCoordinates[0]
        $existingY = [int]$existingCoordinates[1]
        $distance = [Math]::Sqrt([Math]::Pow($CellX - $existingX, 2) + [Math]::Pow($CellY - $existingY, 2))
        if ($distance -ge $MinimumDistance) { continue }

        foreach ($existingIcon in @($landmarkCells[$existingKey])) {
            if ($existingIcon.Label -eq $Label) { return $false }
        }
    }

    return $true
}

function Get-DistrictDenName {
    param(
        [int]$DistrictIndex,
        [bool]$IsDifficult
    )

    $denPrefixes = @("Ash", "Cinder", "Grey", "Iron", "Raven", "Red", "West")
    if ($IsDifficult) {
        $secureSites = @("Bunker", "Laboratory", "Army Base")
        return "$($denPrefixes[$random.Next(0, $denPrefixes.Count)]) $($secureSites[$random.Next(0, $secureSites.Count)])"
    }

    $denSuffixes = @("Den", "Haven", "Refuge", "Shelter", "Station", "Watch")
    return "$($denPrefixes[$random.Next(0, $denPrefixes.Count)]) $($denSuffixes[$random.Next(0, $denSuffixes.Count)])"
}

$eligibleLandmarkCandidates = @()
foreach ($key in $landmarkCandidates.Keys) {
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $inDeadZone = $false
    foreach ($deadZone in $deadZones) {
        $deadZoneDistance = [Math]::Sqrt([Math]::Pow($cellX - $deadZone.X, 2) + [Math]::Pow($cellY - $deadZone.Y, 2))
        if ($deadZoneDistance -le $deadZone.Radius) {
            $inDeadZone = $true
            break
        }
    }
    if ($inDeadZone) { continue }
    if (-not $roadCells.ContainsKey($key) -or -not $reachableRoadCells.ContainsKey($key)) { continue }
    if ($highwayCells.ContainsKey($key) -or $diagonalHighwayCells.ContainsKey($key)) { continue }
    $eligibleLandmarkCandidates += $key
}

$deepCandidates = @($eligibleLandmarkCandidates | Where-Object {
    $coordinates = $_ -split ","
    $candidateX = [int]$coordinates[0]
    $candidateY = [int]$coordinates[1]
    $candidateX -ge [int]($GridCells * 0.65) -and ($candidateY -le [int]($GridCells * 0.25) -or $candidateY -ge [int]($GridCells * 0.75))
})
$bottomCandidates = @($eligibleLandmarkCandidates | Where-Object {
    $coordinates = $_ -split ","
    [int]$coordinates[1] -ge [int]($GridCells * 0.65)
})
if ($bottomCandidates.Count -eq 0) { $bottomCandidates = $deepCandidates }
if ($bottomCandidates.Count -eq 0) { $bottomCandidates = $eligibleLandmarkCandidates }

# Guarantee one laboratory and one bunker in lower-city cells.
$laboratoryKey = $bottomCandidates[$random.Next(0, $bottomCandidates.Count)]
$bunkerOptions = @($bottomCandidates | Where-Object { $_ -ne $laboratoryKey })
if ($bunkerOptions.Count -eq 0) { $bunkerOptions = $bottomCandidates }
$bunkerKey = $bunkerOptions[$random.Next(0, $bunkerOptions.Count)]
$landmarkCells[$laboratoryKey] = @($rareLandmarks[1])
$landmarkCells[$bunkerKey] = @($rareLandmarks[2])

foreach ($key in $eligibleLandmarkCandidates) {
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]

    $landmarks = if ($landmarkCells.ContainsKey($key)) { @($landmarkCells[$key]) } else { @() }
    $isDeepCity = $cellX -ge [int]($GridCells * 0.65) -and ($cellY -le [int]($GridCells * 0.25) -or $cellY -ge [int]($GridCells * 0.75))
    $isBottomCity = $cellY -ge [int]($GridCells * 0.65)
    $centerX = ($GridCells - 1) / 2
    $centerY = ($GridCells - 1) / 2
    $centerDistance = [Math]::Sqrt([Math]::Pow($cellX - $centerX, 2) + [Math]::Pow($cellY - $centerY, 2))
    $centrality = [Math]::Max(0, 1 - ($centerDistance / ($GridCells / 2)))

    if ($isDeepCity -and $random.NextDouble() -lt 0.05 -and $landmarks.Count -lt 2) {
        $landmarks += $rareLandmarks[$random.Next(0, $rareLandmarks.Count)]
    }
    if ($isBottomCity -and $random.NextDouble() -lt 0.08 -and $landmarks.Count -lt 2) {
        $landmarks += $rareLandmarks[$random.Next(1, 3)]
    }
    if ($random.NextDouble() -lt (0.08 + 0.22 * $centrality) -and $landmarks.Count -lt 2) {
        $landmarks += $commonLandmarks[$random.Next(0, $commonLandmarks.Count)]
    }
    if ($random.NextDouble() -lt (0.02 + 0.08 * $centrality) -and $landmarks.Count -lt 2) {
        $landmarks += $commonLandmarks[$random.Next(0, $commonLandmarks.Count)]
    }
    if ($random.NextDouble() -lt (0.015 + 0.035 * $centrality) -and $landmarks.Count -lt 2 -and (Test-LandmarkSpacing "F" $cellX $cellY)) {
        $landmarks += $fireLandmark
    }
    if ($random.NextDouble() -lt (0.015 + 0.035 * $centrality) -and $landmarks.Count -lt 2 -and (Test-LandmarkSpacing "P" $cellX $cellY)) {
        $landmarks += $policeLandmark
    }
    if ($random.NextDouble() -lt (0.008 + 0.02 * $centrality) -and $landmarks.Count -lt 2 -and (Test-LandmarkSpacing "H" $cellX $cellY)) {
        $landmarks += $hospitalLandmark
    }
    if ($random.NextDouble() -lt (0.018 + 0.03 * $centrality) -and $landmarks.Count -lt 2 -and (Test-LandmarkSpacing "G" $cellX $cellY)) {
        $landmarks += $petrolStationLandmark
    }
    if ($random.NextDouble() -lt (0.012 + 0.025 * $centrality) -and $landmarks.Count -lt 2 -and (Test-LandmarkSpacing '$' $cellX $cellY)) {
        $landmarks += $bankLandmark
    }

    if ($landmarks.Count -gt 0) {
        $landmarkCells[$key] = $landmarks
    }
}

# The world origin and every district receive a named safe-zone den on a reachable local road.
$denCells[$originKey] = @{ Name = "The Evac Zone"; District = -1; Difficult = $false }
for ($districtIndex = 0; $districtIndex -lt $zones.Count; $districtIndex++) {
    $zone = $zones[$districtIndex]
    $isDifficultDistrict = $zone.X -ge [int]($GridCells * 0.65) -or $zone.Y -ge [int]($GridCells * 0.75)
    $districtCandidates = @($eligibleLandmarkCandidates | Where-Object {
        if ($denCells.ContainsKey($_) -or $landmarkCells.ContainsKey($_)) { return $false }
        $coordinates = $_ -split ","
        [Math]::Sqrt([Math]::Pow([int]$coordinates[0] - $zone.X, 2) + [Math]::Pow([int]$coordinates[1] - $zone.Y, 2)) -le $zone.Radius
    } | Sort-Object {
        $coordinates = $_ -split ","
        [Math]::Abs([int]$coordinates[0] - $zone.X) + [Math]::Abs([int]$coordinates[1] - $zone.Y)
    })
    if ($districtCandidates.Count -eq 0) {
        $districtCandidates = @($eligibleLandmarkCandidates | Where-Object { -not $denCells.ContainsKey($_) -and -not $landmarkCells.ContainsKey($_) })
    }
    if ($districtCandidates.Count -eq 0) { continue }

    $denKey = $districtCandidates[0]
    $denCells[$denKey] = @{ Name = Get-DistrictDenName $districtIndex $isDifficultDistrict; District = $districtIndex; Difficult = $isDifficultDistrict }
}

# Guided lines create a connected city-wide Tube network with deliberate detours between districts.
Add-MetroLine "Cinder Line" $metroLineColor @(
    "Breakwater",
    "16,47",
    "21,43",
    "Cinder Ward",
    "38,19",
    "46,20",
    "Iron Market"
)
Add-MetroLine "Ash Line" ([System.Drawing.Color]::FromArgb(255, 56, 170, 108)) @(
    "Ashwood",
    "18,18",
    "Cinder Ward",
    "34,18",
    "Glassworks",
    "47,13",
    "Greyline"
)
Add-MetroLine "South Line" ([System.Drawing.Color]::FromArgb(255, 244, 184, 44)) @(
    "Breakwater",
    "10,49",
    "Southwatch",
    "17,57",
    "Dustfield",
    "27,58",
    "Red Hollow",
    "45,56",
    "Raven Reach"
)
Add-MetroLine "Raven Line" ([System.Drawing.Color]::FromArgb(255, 164, 87, 211)) @(
    "Cinder Ward",
    "41,37",
    "Iron Market",
    "56,41",
    "Raven Reach"
)

# Draw every road tile inside its own cell.
foreach ($key in $roadCells.Keys) {
    if ($diagonalHighwayCells.ContainsKey($key)) { continue }
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $cellLeft = $cellX * $CellSize
    $cellTop = $cellY * $CellSize
    $centerX = $cellLeft + [int]($CellSize / 2)
    $centerY = $cellTop + [int]($CellSize / 2)
    $halfRoad = [int]($roadWidth / 2)

    $graphics.FillRectangle($roadBrush, $centerX - $halfRoad, $centerY - $halfRoad, $roadWidth, $roadWidth)
    if ($roadCells[$key].N) { $graphics.FillRectangle($roadBrush, $centerX - $halfRoad, $cellTop, $roadWidth, [int]($CellSize / 2) + $halfRoad) }
    if ($roadCells[$key].E) { $graphics.FillRectangle($roadBrush, $centerX - $halfRoad, $centerY - $halfRoad, [int]($CellSize / 2) + $halfRoad, $roadWidth) }
    if ($roadCells[$key].S) { $graphics.FillRectangle($roadBrush, $centerX - $halfRoad, $centerY - $halfRoad, $roadWidth, [int]($CellSize / 2) + $halfRoad) }
    if ($roadCells[$key].W) { $graphics.FillRectangle($roadBrush, $cellLeft, $centerY - $halfRoad, [int]($CellSize / 2) + $halfRoad, $roadWidth) }
}

# Draw actual highway grid tiles so visuals match the logical road graph.
foreach ($key in $highwayCells.Keys) {
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $cellLeft = $cellX * $CellSize
    $cellTop = $cellY * $CellSize
    $centerX = $cellLeft + [int]($CellSize / 2)
    $centerY = $cellTop + [int]($CellSize / 2)
    $halfHighway = [int]($highwayWidth / 2)

    $graphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $centerY - $halfHighway, $highwayWidth, $highwayWidth)
    if ($highwayCells[$key].N) { $graphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $cellTop, $highwayWidth, [int]($CellSize / 2) + $halfHighway) }
    if ($highwayCells[$key].E) { $graphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $centerY - $halfHighway, [int]($CellSize / 2) + $halfHighway, $highwayWidth) }
    if ($highwayCells[$key].S) { $graphics.FillRectangle($highwayBrush, $centerX - $halfHighway, $centerY - $halfHighway, $highwayWidth, [int]($CellSize / 2) + $halfHighway) }
    if ($highwayCells[$key].W) { $graphics.FillRectangle($highwayBrush, $cellLeft, $centerY - $halfHighway, [int]($CellSize / 2) + $halfHighway, $highwayWidth) }
}

# Dashed centerlines make the grid highways read as interstates.
foreach ($key in $highwayCells.Keys) {
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $centerX = $cellX * $CellSize + [int]($CellSize / 2)
    $centerY = $cellY * $CellSize + [int]($CellSize / 2)
    foreach ($direction in @("E", "S")) {
        if (-not $highwayCells[$key][$direction]) { continue }
        $neighborKey = Get-RoadNeighborKey $cellX $cellY $direction
        if ($null -eq $neighborKey) { continue }
        $neighborCoordinates = $neighborKey -split ","
        $neighborCenterX = [int]$neighborCoordinates[0] * $CellSize + [int]($CellSize / 2)
        $neighborCenterY = [int]$neighborCoordinates[1] * $CellSize + [int]($CellSize / 2)
        $graphics.DrawLine($highwayLinePen, $centerX, $centerY, $neighborCenterX, $neighborCenterY)
    }
}

# Bridge decks sit above the highway at the rare preserved street crossings.
foreach ($key in $bridgeCells.Keys) {
    if (-not $highwayCells.ContainsKey($key)) { continue }
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $centerX = $cellX * $CellSize + [int]($CellSize / 2)
    $centerY = $cellY * $CellSize + [int]($CellSize / 2)
    $crossingDirection = if ($bridgeCrossingDirections.ContainsKey($key)) { $bridgeCrossingDirections[$key] } elseif ($highwayCells[$key].N -and $highwayCells[$key].S) { "E" } else { "N" }
    if ($crossingDirection -eq "E" -or $crossingDirection -eq "W") {
        $graphics.DrawLine($bridgeDeckPen, $cellX * $CellSize, $centerY, ($cellX + 1) * $CellSize, $centerY)
        $graphics.DrawLine($bridgeEdgePen, $cellX * $CellSize, $centerY - [int]($roadWidth / 2), ($cellX + 1) * $CellSize, $centerY - [int]($roadWidth / 2))
        $graphics.DrawLine($bridgeEdgePen, $cellX * $CellSize, $centerY + [int]($roadWidth / 2), ($cellX + 1) * $CellSize, $centerY + [int]($roadWidth / 2))
    } else {
        $graphics.DrawLine($bridgeDeckPen, $centerX, $cellY * $CellSize, $centerX, ($cellY + 1) * $CellSize)
        $graphics.DrawLine($bridgeEdgePen, $centerX - [int]($roadWidth / 2), $cellY * $CellSize, $centerX - [int]($roadWidth / 2), ($cellY + 1) * $CellSize)
        $graphics.DrawLine($bridgeEdgePen, $centerX + [int]($roadWidth / 2), $cellY * $CellSize, $centerX + [int]($roadWidth / 2), ($cellY + 1) * $CellSize)
    }
}

# Highlight each short, grid-connected ramp where it meets the interstate.
foreach ($ramp in $highwayRamps) {
    $centerX = $ramp.X * $CellSize + [int]($CellSize / 2)
    $centerY = $ramp.Y * $CellSize + [int]($CellSize / 2)
    $rampKey = Get-RoadNeighborKey $ramp.X $ramp.Y $ramp.Exit
    if ($null -eq $rampKey) { continue }
    $rampCoordinates = $rampKey -split ","
    $rampCenterX = [int]$rampCoordinates[0] * $CellSize + [int]($CellSize / 2)
    $rampCenterY = [int]$rampCoordinates[1] * $CellSize + [int]($CellSize / 2)
    $exitKey = Get-RoadNeighborKey ([int]$rampCoordinates[0]) ([int]$rampCoordinates[1]) $ramp.Travel
    if ($null -eq $exitKey) { continue }
    $exitCoordinates = $exitKey -split ","
    $exitCenterX = [int]$exitCoordinates[0] * $CellSize + [int]($CellSize / 2)
    $exitCenterY = [int]$exitCoordinates[1] * $CellSize + [int]($CellSize / 2)
    $graphics.DrawLine($highwayRampPen, $centerX, $centerY, $rampCenterX, $rampCenterY)
    $graphics.DrawLine($highwayRampPen, $rampCenterX, $rampCenterY, $exitCenterX, $exitCenterY)
}

# Underpasses retain a complete road across the highway; ramps connect one street into it.
foreach ($underpass in $diagonalUnderpasses) {
    $centerY = $underpass.Y * $CellSize + [int]($CellSize / 2)
    $startX = ($underpass.X - 1) * $CellSize + [int]($CellSize / 2)
    $endX = ($underpass.X + 1) * $CellSize + [int]($CellSize / 2)
    $graphics.DrawLine($diagonalCrossingPen, $startX, $centerY, $endX, $centerY)
    $graphics.DrawLine($diagonalCrossingEdgePen, $startX, $centerY - [int]($roadWidth / 2), $endX, $centerY - [int]($roadWidth / 2))
    $graphics.DrawLine($diagonalCrossingEdgePen, $startX, $centerY + [int]($roadWidth / 2), $endX, $centerY + [int]($roadWidth / 2))
}
foreach ($connectionKey in $diagonalRampConnections.Keys) {
    $parts = $connectionKey -split ":"
    $coordinates = $parts[0] -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $centerX = $cellX * $CellSize + [int]($CellSize / 2)
    $centerY = $cellY * $CellSize + [int]($CellSize / 2)
    if ($bridgeCells.ContainsKey("$cellX,$cellY")) { continue }
    $neighborKey = Get-RoadNeighborKey $cellX $cellY $parts[1]
    if ($null -eq $neighborKey) { continue }
    $neighborCoordinates = $neighborKey -split ","
    $neighborCenterX = [int]$neighborCoordinates[0] * $CellSize + [int]($CellSize / 2)
    $neighborCenterY = [int]$neighborCoordinates[1] * $CellSize + [int]($CellSize / 2)
    $graphics.DrawLine($diagonalCrossingPen, $centerX, $centerY, $neighborCenterX, $neighborCenterY)
}

# Add random barriers to multi-exit cells to break up large intersections.
foreach ($key in $roadCells.Keys) {
    $connections = @("N", "E", "S", "W" | Where-Object { $roadCells[$key][$_] })
    if ($connections.Count -lt 2 -or $random.NextDouble() -gt $BlockadeChance) { continue }

    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    if ($cellX -eq 0 -and $cellY -eq $originCellY) { continue }

    $blockedDirection = $connections[$random.Next(0, $connections.Count)]
    if (-not (Test-BlockadePlacement $key $blockedDirection)) { continue }
    Add-BlockadeConnection $key $blockedDirection
        $blockadeMarkers += @{ CellKey = $key; Direction = $blockedDirection }
    $cellLeft = $cellX * $CellSize
    $cellTop = $cellY * $CellSize
    $centerX = $cellLeft + [int]($CellSize / 2)
    $centerY = $cellTop + [int]($CellSize / 2)
    $barrierThickness = [Math]::Max(5, [int]($roadWidth / 3))
    $barrierLength = $roadWidth + 10

    switch ($blockedDirection) {
        "N" {
            $barrierX = $centerX - [int]($barrierLength / 2)
            $barrierY = $cellTop + [int]($CellSize * 0.18)
            $graphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierLength, $barrierThickness)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX + 4, $barrierY, 4, $barrierThickness)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX + $barrierLength - 8, $barrierY, 4, $barrierThickness)
        }
        "E" {
            $barrierX = $cellLeft + [int]($CellSize * 0.82)
            $barrierY = $centerY - [int]($barrierLength / 2)
            $graphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierThickness, $barrierLength)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + 4, $barrierThickness, 4)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + $barrierLength - 8, $barrierThickness, 4)
        }
        "S" {
            $barrierX = $centerX - [int]($barrierLength / 2)
            $barrierY = $cellTop + [int]($CellSize * 0.82)
            $graphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierLength, $barrierThickness)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX + 4, $barrierY, 4, $barrierThickness)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX + $barrierLength - 8, $barrierY, 4, $barrierThickness)
        }
        "W" {
            $barrierX = $cellLeft + [int]($CellSize * 0.18)
            $barrierY = $centerY - [int]($barrierLength / 2)
            $graphics.FillRectangle($blockadeBrush, $barrierX, $barrierY, $barrierThickness, $barrierLength)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + 4, $barrierThickness, 4)
            $graphics.FillRectangle($blockadeStripeBrush, $barrierX, $barrierY + $barrierLength - 8, $barrierThickness, 4)
        }
    }
}

# Mark remaining dead ends with a question mark.
foreach ($key in $roadCells.Keys) {
    if ((Get-RoadDegree $roadCells[$key]) -ne 1) { continue }

    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    if ($cellX -eq 0 -and $cellY -eq $originCellY) { continue }

    $cellLeft = $cellX * $CellSize
    $cellTop = $cellY * $CellSize
    $centerX = $cellLeft + [int]($CellSize / 2)
    $centerY = $cellTop + [int]($CellSize / 2)
    $markerRadius = [int]($CellSize * 0.25)
    $markerLeft = $centerX - $markerRadius
    $markerTop = $centerY - $markerRadius
    $markerDiameter = $markerRadius * 2
    $connectedDirection = @("N", "E", "S", "W" | Where-Object { $roadCells[$key][$_] })[0]
    $tipLength = [Math]::Max(5, [int]($roadWidth / 3))
    $halfRoad = [int]($roadWidth / 2)

    switch ($connectedDirection) {
        "N" { $graphics.FillRectangle($deadEndTipBrush, $centerX - $halfRoad, $cellTop + $CellSize - $tipLength, $roadWidth, $tipLength) }
        "E" { $graphics.FillRectangle($deadEndTipBrush, $cellLeft, $centerY - $halfRoad, $tipLength, $roadWidth) }
        "S" { $graphics.FillRectangle($deadEndTipBrush, $centerX - $halfRoad, $cellTop, $roadWidth, $tipLength) }
        "W" { $graphics.FillRectangle($deadEndTipBrush, $cellLeft + $CellSize - $tipLength, $centerY - $halfRoad, $tipLength, $roadWidth) }
    }

    $graphics.DrawEllipse($deadEndPen, $markerLeft, $markerTop, $markerDiameter, $markerDiameter)
    $questionMark = "?"
    $textSize = $graphics.MeasureString($questionMark, $questionFont)
    $graphics.DrawString($questionMark, $questionFont, $deadEndBrush, $centerX - ($textSize.Width / 2), $centerY - ($textSize.Height / 2))
}

# Draw landmarks last so icons remain visible over roads, blockades, and buildings.
$iconRadius = [Math]::Max(10, [int]($CellSize * 0.22))
foreach ($key in $landmarkCells.Keys) {
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $cellLeft = $cellX * $CellSize
    $cellTop = $cellY * $CellSize
    $centerX = $cellLeft + [int]($CellSize / 2)
    $centerY = $cellTop + [int]($CellSize / 2)
    $icons = @($landmarkCells[$key])
    $iconSpacing = [int]($iconRadius * 1.8)
    $gridColumns = [Math]::Min(2, $icons.Count)
    $gridRows = [Math]::Ceiling($icons.Count / 2.0)

    for ($iconIndex = 0; $iconIndex -lt $icons.Count; $iconIndex++) {
        $icon = $icons[$iconIndex]
        $gridColumn = $iconIndex % 2
        $gridRow = [Math]::Floor($iconIndex / 2)
        $iconX = $centerX + ($gridColumn - (($gridColumns - 1) / 2)) * $iconSpacing
        $iconY = $centerY + ($gridRow - (($gridRows - 1) / 2)) * $iconSpacing
        $iconBrush = New-Object System.Drawing.SolidBrush($icon.Color)
        $outlineColor = [System.Drawing.Color]::FromArgb(255, 245, 245, 245)
        if ($icon.Label -eq "LAB" -or $icon.Label -eq "B") {
            $outlineColor = [System.Drawing.Color]::FromArgb(255, 230, 45, 45)
        }
        $iconOutline = New-Object System.Drawing.Pen($outlineColor, 3)
        $isLaboratory = $icon.Label -eq "LAB"
        $displayLabel = if ($isLaboratory) { "L" } else { $icon.Label }
        $iconWidth = if ($isLaboratory) { 34 } else { $iconRadius * 2 }
        $iconHeight = if ($isLaboratory) { 22 } else { $iconRadius * 2 }
        $iconLeft = [int]($iconX - ($iconWidth / 2))
        $iconTop = [int]($iconY - ($iconHeight / 2))
        if ($isLaboratory) {
            $graphics.FillRectangle($iconBrush, $iconLeft, $iconTop, $iconWidth, $iconHeight)
            $graphics.DrawRectangle($iconOutline, $iconLeft, $iconTop, $iconWidth - 1, $iconHeight - 1)
        } else {
            $graphics.FillEllipse($iconBrush, $iconLeft, $iconTop, $iconWidth, $iconHeight)
            $graphics.DrawEllipse($iconOutline, $iconLeft, $iconTop, $iconWidth, $iconHeight)
        }
        $iconTextFont = if ($isLaboratory) { New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold) } else { $landmarkFont }
        $textSize = $graphics.MeasureString($displayLabel, $iconTextFont)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $graphics.DrawString($displayLabel, $iconTextFont, $textBrush, $iconX - ($textSize.Width / 2), $iconY - ($textSize.Height / 2))
        $textBrush.Dispose()
        if ($isLaboratory) { $iconTextFont.Dispose() }
        $iconBrush.Dispose()
        $iconOutline.Dispose()
    }
}

$population = [int](25000 + ($buildingCells.Count * 145) + ($seedMagnitude % 15000))
$population = [int]([Math]::Round($population / 100.0) * 100)
$graphics.DrawString($cityName.ToUpperInvariant(), $cityTitleFont, $cityTitleBrush, 28, 20)
$graphics.DrawString("Population: $($population.ToString('N0'))   Seed: $Seed", $cityStatsFont, $cityStatsBrush, 36, 108)

$gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(100, 95, 100, 105), 1)
for ($coordinate = 0; $coordinate -le $width; $coordinate += $CellSize) {
    $graphics.DrawLine($gridPen, $coordinate, 0, $coordinate, $height)
}
for ($coordinate = 0; $coordinate -le $height; $coordinate += $CellSize) {
    $graphics.DrawLine($gridPen, 0, $coordinate, $width, $coordinate)
}

# Highlight cells containing guaranteed rare landmarks.
foreach ($key in $landmarkCells.Keys) {
    $coordinates = $key -split ","
    $cellX = [int]$coordinates[0]
    $cellY = [int]$coordinates[1]
    $cellLeft = $cellX * $CellSize + 2
    $cellTop = $cellY * $CellSize + 2
    foreach ($icon in @($landmarkCells[$key])) {
        if ($icon.Label -eq "LAB") {
            $graphics.DrawRectangle($laboratoryCellPen, $cellLeft, $cellTop, $CellSize - 5, $CellSize - 5)
            break
        }
        if ($icon.Label -eq "B") {
            $graphics.DrawRectangle($bunkerCellPen, $cellLeft, $cellTop, $CellSize - 5, $CellSize - 5)
            break
        }
    }
}

# Draw named den safe zones above ordinary map details.
$denFormat = New-Object System.Drawing.StringFormat
$denFormat.Alignment = [System.Drawing.StringAlignment]::Center
$denFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
foreach ($key in $denCells.Keys) {
    $coordinates = $key -split ","
    $cellLeft = [int]$coordinates[0] * $CellSize
    $cellTop = [int]$coordinates[1] * $CellSize
    $denName = $denCells[$key].Name
    $denWords = $denName -split " "
    $denDisplayName = if ($denWords.Count -gt 1) { "$($denWords[0])`n$($denWords[1..($denWords.Count - 1)] -join ' ')" } else { $denName }
    $denRectangle = [System.Drawing.Rectangle]::new([int]($cellLeft + 3), [int]($cellTop + 3), [int]($CellSize - 6), [int]($CellSize - 6))
    $denTextRectangle = [System.Drawing.RectangleF]::new([single]$denRectangle.X, [single]$denRectangle.Y, [single]$denRectangle.Width, [single]$denRectangle.Height)
    $graphics.FillRectangle($denBrush, $denRectangle)
    $graphics.DrawRectangle($denCellPen, $denRectangle)
    $graphics.DrawString($denDisplayName, $denNameFont, $denTextBrush, $denTextRectangle, $denFormat)
}
$denFormat.Dispose()

# Draw the Metro after local map details, using direct station-to-station segments and labeled Tube-style roundels.
Draw-MetroLayer $graphics

# Large district labels sit above roads, landmarks, and dens while staying below map UI panels.
$districtFormat = New-Object System.Drawing.StringFormat
$districtFormat.Alignment = [System.Drawing.StringAlignment]::Center
$districtFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
foreach ($zone in $zones) {
    $districtLabelWidth = [int]($zone.Radius * $CellSize * 1.5)
    $districtLabelHeight = 76
    $districtLabelLeft = [int]($zone.X * $CellSize + ($CellSize / 2) - ($districtLabelWidth / 2))
    $districtLabelTop = [int]($zone.Y * $CellSize + ($CellSize / 2) - ($districtLabelHeight / 2))
    $districtLabelRectangle = [System.Drawing.RectangleF]::new([single]$districtLabelLeft, [single]$districtLabelTop, [single]$districtLabelWidth, [single]$districtLabelHeight)
    $graphics.DrawString($zone.Name.ToUpperInvariant(), $districtNameFont, $districtNameBrush, $districtLabelRectangle, $districtFormat)
}
$districtFormat.Dispose()

# Draw an icon key in the upper-right corner.
$keyEntries = @(
    @{ Label = "P"; Name = "Police station"; Color = [System.Drawing.Color]::FromArgb(255, 70, 130, 230) },
    @{ Label = "H"; Name = "Hospital"; Color = [System.Drawing.Color]::FromArgb(255, 230, 75, 85) },
    @{ Label = "L"; Name = "Leisure"; Color = [System.Drawing.Color]::FromArgb(255, 80, 200, 125) },
    @{ Label = "M"; Name = "Market"; Color = [System.Drawing.Color]::FromArgb(255, 235, 180, 70) },
    @{ Label = "K"; Name = "Park"; Color = [System.Drawing.Color]::FromArgb(255, 105, 170, 80) },
    @{ Label = "F"; Name = "Fire station"; Color = [System.Drawing.Color]::FromArgb(255, 235, 110, 55) },
    @{ Label = "G"; Name = "Petrol station"; Color = [System.Drawing.Color]::FromArgb(255, 60, 185, 115) },
    @{ Label = '$'; Name = "Bank"; Color = [System.Drawing.Color]::FromArgb(255, 230, 185, 60) },
    @{ Label = "A"; Name = "Army base"; Color = [System.Drawing.Color]::FromArgb(255, 170, 190, 85) },
    @{ Label = "LAB"; DisplayLabel = "L"; Name = "Laboratory (green cell border)"; Color = [System.Drawing.Color]::FromArgb(255, 185, 90, 220) },
    @{ Label = "B"; Name = "Bunker (red cell border)"; Color = [System.Drawing.Color]::FromArgb(255, 130, 135, 145) },
    @{ Label = "?"; Name = "Unrepaired dead end"; Color = [System.Drawing.Color]::FromArgb(255, 235, 210, 80) },
    @{ Label = "DEN"; DisplayLabel = "D"; Name = "Den safe zone"; Color = [System.Drawing.Color]::FromArgb(255, 75, 235, 115) },
    @{ Label = "HWY"; DisplayLabel = "H"; Name = "Highway"; Color = [System.Drawing.Color]::FromArgb(255, 35, 90, 190) }
)
$keyWidth = 360
$keyRowHeight = 28
$keyHeight = 50 + ($keyEntries.Count * $keyRowHeight)
$keyX = $width - $keyWidth - 18
$keyY = 18
$graphics.FillRectangle($keyBackgroundBrush, $keyX, $keyY, $keyWidth, $keyHeight)
$graphics.DrawRectangle($keyBorderPen, $keyX, $keyY, $keyWidth, $keyHeight)
$graphics.DrawString("MAP KEY", $keyTitleFont, $deadEndBrush, $keyX + 14, $keyY + 10)

for ($entryIndex = 0; $entryIndex -lt $keyEntries.Count; $entryIndex++) {
    $entry = $keyEntries[$entryIndex]
    $entryY = $keyY + 47 + ($entryIndex * $keyRowHeight)
    $entryBrush = New-Object System.Drawing.SolidBrush($entry.Color)
    $entryPenColor = if ($entry.Label -eq "LAB") { [System.Drawing.Color]::FromArgb(255, 50, 220, 90) } elseif ($entry.Label -eq "B") { [System.Drawing.Color]::FromArgb(255, 240, 45, 45) } else { [System.Drawing.Color]::White }
    $entryPen = New-Object System.Drawing.Pen($entryPenColor, 2)
    $entryDisplayLabel = if ($entry.DisplayLabel) { $entry.DisplayLabel } else { $entry.Label }
    if ($entry.Label -eq "METRO") {
        $metroKeyPen = [System.Drawing.Pen]::new($entry.Color, [single]6)
        $metroKeyStationPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 24, 24, 28), [single]2)
        $graphics.DrawLine($metroKeyPen, $keyX + 14, $entryY + 10, $keyX + 34, $entryY + 10)
        $graphics.FillEllipse($metroStationBrush, $keyX + 19, $entryY + 5, 10, 10)
        $graphics.DrawEllipse($metroKeyStationPen, $keyX + 19, $entryY + 5, 10, 10)
        $metroKeyPen.Dispose()
        $metroKeyStationPen.Dispose()
    } else {
        $graphics.FillEllipse($entryBrush, $keyX + 14, $entryY, 20, 20)
        $graphics.DrawEllipse($entryPen, $keyX + 14, $entryY, 20, 20)
        $graphics.DrawString($entryDisplayLabel, $keyFont, $deadEndBrush, $keyX + 19, $entryY + 2)
    }
    $graphics.DrawString($entry.Name, $keyFont, $deadEndBrush, $keyX + 44, $entryY + 1)
    $entryBrush.Dispose()
    $entryPen.Dispose()
}

# List all den safe zones and their world-cell coordinates beneath the map key.
$safeZoneDirectory = @($denCells.GetEnumerator() | Sort-Object { $_.Value.District })
$safeZoneRowHeight = 25
$safeZoneHeight = 45 + ($safeZoneDirectory.Count * $safeZoneRowHeight)
$safeZoneX = $keyX
$safeZoneY = $keyY + $keyHeight + 14
$graphics.FillRectangle($keyBackgroundBrush, $safeZoneX, $safeZoneY, $keyWidth, $safeZoneHeight)
$graphics.DrawRectangle($keyBorderPen, $safeZoneX, $safeZoneY, $keyWidth, $safeZoneHeight)
$graphics.DrawString("SAFE ZONES", $keyTitleFont, $denTextBrush, $safeZoneX + 14, $safeZoneY + 10)
for ($safeZoneIndex = 0; $safeZoneIndex -lt $safeZoneDirectory.Count; $safeZoneIndex++) {
    $safeZone = $safeZoneDirectory[$safeZoneIndex]
    $coordinates = $safeZone.Key -split ","
    $worldX = [int]$coordinates[0]
    $worldY = [int]$coordinates[1] - $originCellY
    $safeZoneYPosition = $safeZoneY + 42 + ($safeZoneIndex * $safeZoneRowHeight)
    $graphics.DrawString($safeZone.Value.Name, $keyFont, $denTextBrush, $safeZoneX + 14, $safeZoneYPosition)
    $graphics.DrawString("X $worldX  Y $worldY", $keyFont, $cityStatsBrush, $safeZoneX + 255, $safeZoneYPosition)
}

$transportDirectory = @($metroLines | Sort-Object Name)
$transportRowHeight = 25
$transportHeight = 45 + ($transportDirectory.Count * $transportRowHeight)
$transportX = $keyX
$transportY = $safeZoneY + $safeZoneHeight + 14
$graphics.FillRectangle($keyBackgroundBrush, $transportX, $transportY, $keyWidth, $transportHeight)
$graphics.DrawRectangle($keyBorderPen, $transportX, $transportY, $keyWidth, $transportHeight)
$graphics.DrawString("TRANSPORT", $keyTitleFont, $denTextBrush, $transportX + 14, $transportY + 10)
for ($transportIndex = 0; $transportIndex -lt $transportDirectory.Count; $transportIndex++) {
    $transportLine = $transportDirectory[$transportIndex]
    $transportYPosition = $transportY + 42 + ($transportIndex * $transportRowHeight)
    $transportPen = [System.Drawing.Pen]::new($transportLine.Color, [single]6)
    $graphics.DrawLine($transportPen, $transportX + 14, $transportYPosition + 8, $transportX + 38, $transportYPosition + 8)
    $graphics.FillEllipse($metroStationBrush, $transportX + 21, $transportYPosition + 3, 10, 10)
    $graphics.DrawEllipse($metroStationPen, $transportX + 21, $transportYPosition + 3, 10, 10)
    $graphics.DrawString($transportLine.Name, $keyFont, $denTextBrush, $transportX + 50, $transportYPosition)
    $transportPen.Dispose()
}

$directory = Split-Path -Parent $Output
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
}

$bitmap.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
$mapDataOutput = Export-MapData

$layerOutputs = @()
if ($ExportLayers) {
    $layerOutputs += Export-MapLayer "terrain" { param($targetGraphics) Draw-TerrainLayer $targetGraphics } $true
    $layerOutputs += Export-MapLayer "buildings" { param($targetGraphics) Draw-BuildingLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "roads" { param($targetGraphics) Draw-RoadLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "highways" { param($targetGraphics) Draw-HighwayLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "landmarks" { param($targetGraphics) Draw-LandmarkLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "safe_zones" { param($targetGraphics) Draw-SafeZoneLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "metro" { param($targetGraphics) Draw-MetroLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "grid" { param($targetGraphics) Draw-GridLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "labels" { param($targetGraphics) Draw-LabelLayer $targetGraphics }
    $layerOutputs += Export-MapLayer "keys" { param($targetGraphics) Draw-KeyLayer $targetGraphics $keyEntries $safeZoneDirectory $keyX $keyY $keyWidth $keyHeight $safeZoneY $safeZoneHeight $transportDirectory $transportY $transportHeight }
}

$roadBrush.Dispose()
$highwayBrush.Dispose()
$highwayLinePen.Dispose()
$bridgeDeckPen.Dispose()
$bridgeEdgePen.Dispose()
$highwayRampPen.Dispose()
$blockadeBrush.Dispose()
$blockadeStripeBrush.Dispose()
$deadEndPen.Dispose()
$deadEndBrush.Dispose()
$deadEndTipBrush.Dispose()
$questionFont.Dispose()
$landmarkFont.Dispose()
$denNameFont.Dispose()
$districtNameFont.Dispose()
$cityTitleFont.Dispose()
$cityStatsFont.Dispose()
$keyTitleFont.Dispose()
$keyFont.Dispose()
$cityTitleBrush.Dispose()
$cityStatsBrush.Dispose()
$keyBackgroundBrush.Dispose()
$keyBorderPen.Dispose()
$laboratoryCellPen.Dispose()
$bunkerCellPen.Dispose()
$denBrush.Dispose()
$denCellPen.Dispose()
$denTextBrush.Dispose()
$districtNameBrush.Dispose()
$metroLineOutlinePen.Dispose()
$metroStationBrush.Dispose()
$metroStationPen.Dispose()
$metroStationTextBrush.Dispose()
$gridPen.Dispose()
$graphics.Dispose()
$bitmap.Dispose()

if ($ExportLayers) {
    Write-Output "Generated $Output ($width x $height); map data: $mapDataOutput; exported layers: $($layerOutputs -join ', ')."
} else {
    Write-Output "Generated $Output ($width x $height); map data: $mapDataOutput; The Evac Zone is at world origin (0, 0); Metro network has $($metroLines.Count) lines and $($metroStations.Count) stations."
}
