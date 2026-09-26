param(
    [string]$MapData = '',
    [string]$PlanData = '',
    [string]$WorldProfile = 'preview'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilename = if ($WorldProfile -eq 'preview') { 'preview_grid_24x24_seed_1337.json' } else { 'map_grid_64x64_seed_1337.json' }
    $MapData = Join-Path $PSScriptRoot $mapFilename
}
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilename = if ($WorldProfile -eq 'preview') { 'preview_grid_24x24_seed_1337_template_plan.json' } else { 'map_grid_64x64_seed_1337_template_plan.json' }
    $PlanData = Join-Path $PSScriptRoot $planFilename
}
if (-not (Test-Path -LiteralPath $MapData -PathType Leaf) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A current map manifest and matching template plan are required.'
}

$map = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$minimumSpacing = [double]$map.generation.safeZonePlacement.minimumSpacingCells
$diagnostics = @($map.generation.safeZonePlacement.districts)
if ($diagnostics.Count -ne @($map.districts).Count) {
    throw "Expected one safe-zone placement diagnostic per district; found $($diagnostics.Count)."
}
$directions = @{ N = @(0, -1); E = @(1, 0); S = @(0, 1); W = @(-1, 0) }
$bridgeRampCells = @($plan.cells | Where-Object { $_.transportFeature -like 'bridge-ramp-*' })
foreach ($cell in $bridgeRampCells) {
    $center = [int][Math]::Floor([int]$cell.tileGridSize / 2)
    $direction = $cell.transportFeature.Substring('bridge-ramp-'.Length).ToUpperInvariant()
    $rampX = $center + $directions[$direction][0]
    $rampY = $center + $directions[$direction][1]
    $centerPlacement = @($cell.tilePlacements | Where-Object { $_.tileX -eq $center -and $_.tileY -eq $center })[0]
    $rampPlacement = @($cell.tilePlacements | Where-Object { $_.tileX -eq $rampX -and $_.tileY -eq $rampY })[0]
    $isCarparkRamp = [string]$cell.cellTemplateFilename -like '*-cp.vmf'
    if ($isCarparkRamp) {
        if ($null -eq $centerPlacement -or $centerPlacement.template -notin @('roads/tile_road_tjunction.vmf', 'roads/tile_road_crossjunction.vmf')) {
            throw "Carpark bridge-ramp recipe $($cell.cellTemplateFilename) must preserve a road junction at the center."
        }
        if (@($cell.tilePlacements | Where-Object { $_.role -eq 'carpark_road_junction' -and $_.template -eq 'roads/tile_road_tjunction.vmf' }).Count -eq 0) {
            throw "Carpark bridge-ramp recipe $($cell.cellTemplateFilename) must preserve its carpark T-junction."
        }
    } elseif ($null -eq $centerPlacement -or $centerPlacement.role -ne 'road_center' -or $centerPlacement.template -ne 'roads/tile_road_crossjunction.vmf') {
        throw "Bridge-ramp recipe $($cell.cellTemplateFilename) must preserve a road cross-junction at the center."
    }
    if ($null -eq $rampPlacement -or $rampPlacement.role -notin @('bridge_ramp', 'carpark_bridge_ramp')) {
        throw "Bridge-ramp recipe $($cell.cellTemplateFilename) must place its ramp one tile along $direction."
    }
    $bridgeX = $center + (2 * $directions[$direction][0])
    $bridgeY = $center + (2 * $directions[$direction][1])
    $bridgePlacement = @($cell.tilePlacements | Where-Object { $_.tileX -eq $bridgeX -and $_.tileY -eq $bridgeY })[0]
    if ($null -eq $bridgePlacement -or $bridgePlacement.role -ne 'bridge_road') {
        throw "Bridge-ramp recipe $($cell.cellTemplateFilename) must continue its bridge road beyond the ramp."
    }
    if (@($cell.tilePlacements | Where-Object { $_.role -eq 'bridge_ramp_deadend' }).Count -gt 0) {
        throw "Bridge-ramp recipe $($cell.cellTemplateFilename) must not add a perpendicular bridge-ramp dead end."
    }
}

$safeZones = @($map.safeZones)
$minimumActualDistance = [double]::PositiveInfinity
for ($first = 0; $first -lt $safeZones.Count; $first++) {
    for ($second = $first + 1; $second -lt $safeZones.Count; $second++) {
        $deltaX = [double]$safeZones[$first].x - [double]$safeZones[$second].x
        $deltaY = [double]$safeZones[$first].y - [double]$safeZones[$second].y
        $minimumActualDistance = [Math]::Min($minimumActualDistance, [Math]::Sqrt($deltaX * $deltaX + $deltaY * $deltaY))
    }
}
$safeZoneKeys = @{}
foreach ($safeZone in $safeZones) { $safeZoneKeys["$($safeZone.x),$($safeZone.y)"] = $true }
$cellsByKey = @{}
foreach ($cell in @($map.cells)) { $cellsByKey["$($cell.x),$($cell.y)"] = $cell }
$opposites = @{ N = 'S'; E = 'W'; S = 'N'; W = 'E' }
$origin = $map.map.origin
$originKey = "$($origin.cellX),$($origin.cellY)"
$reachable = @{}
$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue($originKey)
while ($queue.Count -gt 0) {
    $key = $queue.Dequeue()
    if ($reachable.ContainsKey($key)) { continue }
    $reachable[$key] = $true
    $cell = $cellsByKey[$key]
    foreach ($neighbor in @($cell.neighbors)) {
        if (-not [bool]$neighbor.inBounds) { continue }
        $neighborKey = "$($neighbor.x),$($neighbor.y)"
        $next = $cellsByKey[$neighborKey]
        if ($null -eq $next) { continue }
        $reverse = @($next.neighbors | Where-Object { $_.direction -eq $opposites[[string]$neighbor.direction] } | Select-Object -First 1)
        if ($reverse.Count -eq 0) { continue }
        $road = [bool]$neighbor.roadConnected -and [bool]$reverse[0].roadConnected
        $highway = [bool]$neighbor.highwayConnected -and [bool]$reverse[0].highwayConnected
        $cellBridgeDirections = @()
        if ([bool]$cell.highway.bridge) {
            $cellBridgeDirection = [string]$cell.highway.bridgeCrossingDirection
            $cellBridgeDirections = if ($cellBridgeDirection -in @('N', 'S')) { @('N', 'S') } elseif ($cellBridgeDirection -in @('E', 'W')) { @('E', 'W') } elseif (@($cell.highway.connections) -contains 'N' -and @($cell.highway.connections) -contains 'S') { @('N', 'S') } else { @('E', 'W') }
        }
        $nextBridgeDirections = @()
        if ([bool]$next.highway.bridge) {
            $nextBridgeDirection = [string]$next.highway.bridgeCrossingDirection
            $nextBridgeDirections = if ($nextBridgeDirection -in @('N', 'S')) { @('N', 'S') } elseif ($nextBridgeDirection -in @('E', 'W')) { @('E', 'W') } elseif (@($next.highway.connections) -contains 'N' -and @($next.highway.connections) -contains 'S') { @('N', 'S') } else { @('E', 'W') }
        }
        $road = $road -and ($cellBridgeDirections.Count -eq 0 -or $cellBridgeDirections -contains [string]$neighbor.direction) -and ($nextBridgeDirections.Count -eq 0 -or $nextBridgeDirections -contains $opposites[[string]$neighbor.direction])
        $highway = $highway -and ($cellBridgeDirections.Count -eq 0 -or $cellBridgeDirections -notcontains [string]$neighbor.direction) -and ($nextBridgeDirections.Count -eq 0 -or $nextBridgeDirections -notcontains $opposites[[string]$neighbor.direction])
        $blocked = (@($cell.road.blockades) -contains [string]$neighbor.direction) -or (@($next.road.blockades) -contains $opposites[[string]$neighbor.direction])
        if (($road -and -not $blocked) -or $highway) { $queue.Enqueue($neighborKey) }
    }
}
$unreachableSafeZones = @($safeZoneKeys.Keys | Where-Object { -not $reachable.ContainsKey($_) })
if ($unreachableSafeZones.Count -gt 0) {
    throw "Safe-zone entrance cells are disconnected from the origin: $($unreachableSafeZones -join ', ')."
}

foreach ($station in @($map.metro.stops)) {
    $stationKey = "$($station.x),$($station.y)"
    if (-not $cellsByKey.ContainsKey($stationKey) -or -not [bool]$cellsByKey[$stationKey].road.present) {
        throw "Metro station '$($station.name)' is not on a local road cell: $stationKey."
    }
    $accessPath = @($station.accessPath)
    if ($accessPath.Count -lt 1) { throw "Metro station '$($station.name)' has no recorded access path." }
    $lastAccessParts = ([string]$accessPath[-1]) -split ','
    $lastAccessCell = $cellsByKey[[string]$accessPath[-1]]
    if (-not $reachable.ContainsKey([string]$accessPath[-1]) -or $null -eq $lastAccessCell -or -not [bool]$lastAccessCell.road.present) {
        throw "Metro station '$($station.name)' access path does not terminate on an origin-connected road cell: $($accessPath[-1])."
    }
    for ($pathIndex = 0; $pathIndex -lt $accessPath.Count; $pathIndex++) {
        $pathKey = [string]$accessPath[$pathIndex]
        if ($pathIndex -eq ($accessPath.Count - 1)) { continue }
        $nextKey = [string]$accessPath[$pathIndex + 1]
        $pathCoordinates = $pathKey -split ','
        $nextCoordinates = $nextKey -split ','
        $deltaX = [int]$nextCoordinates[0] - [int]$pathCoordinates[0]
        $deltaY = [int]$nextCoordinates[1] - [int]$pathCoordinates[1]
        $direction = if ($deltaX -eq 1 -and $deltaY -eq 0) { 'E' } elseif ($deltaX -eq -1 -and $deltaY -eq 0) { 'W' } elseif ($deltaX -eq 0 -and $deltaY -eq 1) { 'S' } elseif ($deltaX -eq 0 -and $deltaY -eq -1) { 'N' } else { $null }
        if ($null -eq $direction) { throw "Metro station '$($station.name)' access path has a non-cardinal step: $pathKey -> $nextKey." }
        $pathCell = $cellsByKey[$pathKey]
        $nextCell = $cellsByKey[$nextKey]
        $reverse = @($nextCell.neighbors | Where-Object { $_.direction -eq $opposites[$direction] } | Select-Object -First 1)
        if ($reverse.Count -eq 0 -or -not [bool]$pathCell.road.present -or -not [bool]$nextCell.road.present -or
            -not [bool](@($pathCell.road.connections) -contains $direction) -or -not [bool](@($nextCell.road.connections) -contains $opposites[$direction])) {
            throw "Metro station '$($station.name)' access path uses a non-road edge: $pathKey -> $nextKey."
        }
        if ((@($pathCell.road.blockades) -contains $direction) -or (@($nextCell.road.blockades) -contains $opposites[$direction])) {
            throw "Metro station '$($station.name)' access path crosses a blockade: $pathKey -> $nextKey."
        }
    }
}

$manifestMinimum = [double]$map.generation.safeZonePlacement.actualMinimumSpacingCells
if ([Math]::Abs($minimumActualDistance - $manifestMinimum) -gt 0.001) {
    throw "Safe-zone spacing diagnostic $manifestMinimum disagrees with recomputed minimum $minimumActualDistance."
}
$missedSpacing = @($diagnostics | Where-Object { -not $_.meetsMinimumSpacing })
Write-Output ("Phase C 2 layout checks passed: bridge-ramp recipes={0}; safe zones={1}; metro stops={2}; spacing target={3}; actual minimum={4:N2}; target fallbacks={5}." -f $bridgeRampCells.Count,$safeZones.Count,@($map.metro.stops).Count,$minimumSpacing,$minimumActualDistance,$missedSpacing.Count)
