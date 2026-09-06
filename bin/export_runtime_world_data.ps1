param(
    [string]$MapData = '',
    [string]$PlanData = '',
    [string]$Output = '',
    [string]$BuildDirectory = '',
    [switch]$Preview,
    [switch]$RequireCompiledMaps,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RecordName {
    param([object]$Record, [string]$Context)

    if ($Record -is [string]) { return $Record }
    $name = $Record.PSObject.Properties['name']
    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name.Value)) {
        throw "$Context must provide a non-empty name."
    }
    return [string]$name.Value
}

function Get-CoordinateKey {
    param([int]$X, [int]$Y)

    return "$X,$Y"
}

function Get-CellId {
    param([int]$X, [int]$Y, [int]$Width)

    return ($Y * $Width) + $X
}

function Get-AtmosphereProfile {
    param([object]$MapCell, [object]$PlanCell)

    if ($null -ne $MapCell.safeZone) { return 4 }
    if ([bool]$MapCell.deadZone) { return 3 }
    if ($PlanCell.environmentProfile -in @('commercial', 'financial')) { return 2 }
    if ($MapCell.environment.terrain -in @('grassland', 'sandy')) { return 0 }
    return 1
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$generatorSettings = & (Join-Path $PSScriptRoot 'import_generator_settings.ps1') -SettingsPath $SettingsPath
$releaseMapDirectoryKey = if ($Preview) { 'previewReleaseMapDirectory' } else { 'releaseMapDirectory' }
$mapDirectory = if ($Preview) { 'preview' } else { 'city' }
if ($generatorSettings.paths.ContainsKey($releaseMapDirectoryKey)) {
    $mapDirectory = Split-Path -Leaf ([string]$generatorSettings.paths[$releaseMapDirectoryKey])
}
if ([string]::IsNullOrWhiteSpace($mapDirectory)) { throw 'The runtime map directory cannot be empty.' }
if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilePattern = if ($Preview) { 'preview_grid_*.json' } else { 'map_grid_*.json' }
    $MapData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $mapFilePattern -File |
        Where-Object { $_.Name -notlike '*_template_plan.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path -LiteralPath $MapData -PathType Leaf)) {
    throw 'A generated map manifest is required. Pass -MapData with a map_grid_*.json path.'
}
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = if ($Preview) { 'preview_grid_*_template_plan.json' } else { 'map_grid_*_template_plan.json' }
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a map_grid_*_template_plan.json path.'
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $buildDirectoryKey = if ($Preview) { 'previewBuildDirectory' } else { 'buildDirectory' }
    $buildDirectoryFallback = if ($Preview) { 'maps/build_preview' } else { 'maps/build' }
    $buildDirectorySetting = if ($generatorSettings.paths.ContainsKey($buildDirectoryKey)) { $generatorSettings.paths[$buildDirectoryKey] } else { $buildDirectoryFallback }
    $BuildDirectory = Join-Path $projectRoot $buildDirectorySetting
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $runtimeWorldDataKey = if ($Preview) { 'previewRuntimeWorldData' } else { 'runtimeWorldData' }
    $runtimeWorldDataFallback = if ($Preview) { 'content/data_static/zombiesim_world_preview.json' } else { 'content/data_static/zombiesim_world.json' }
    $runtimeWorldDataSetting = if ($generatorSettings.paths.ContainsKey($runtimeWorldDataKey)) { $generatorSettings.paths[$runtimeWorldDataKey] } else { $runtimeWorldDataFallback }
    $Output = Join-Path $projectRoot $runtimeWorldDataSetting
}

$map = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
if ($map.schemaVersion -lt 2) {
    throw "Map manifest schema version $($map.schemaVersion) does not provide the required runtime environment data."
}
if ($plan.schemaVersion -lt 2) {
    throw "Template plan schema version $($plan.schemaVersion) does not provide cell recipe data."
}

$width = [int]$map.map.gridCells
$height = $width
$mapCells = @($map.cells)
$planCells = @($plan.cells)
if ($width -lt 1 -or $mapCells.Count -ne ($width * $height) -or $planCells.Count -ne $mapCells.Count) {
    throw "Map and template-plan cell counts must match a complete $width by $height grid."
}

$oppositeDirections = @{ N = 'S'; E = 'W'; S = 'N'; W = 'E' }
$mapCellByCoordinate = @{}
foreach ($mapCell in $mapCells) {
    $x = [int]$mapCell.x
    $y = [int]$mapCell.y
    if ($x -lt 0 -or $x -ge $width -or $y -lt 0 -or $y -ge $height) {
        throw "Map cell coordinate is outside the declared grid: $x,$y"
    }
    $key = Get-CoordinateKey $x $y
    if ($mapCellByCoordinate.ContainsKey($key)) {
        throw "Map manifest contains duplicate cell coordinate: $key"
    }
    $mapCellByCoordinate[$key] = $mapCell
}

$planCellByCoordinate = @{}
foreach ($planCell in $planCells) {
    $key = Get-CoordinateKey ([int]$planCell.x) ([int]$planCell.y)
    if ($planCellByCoordinate.ContainsKey($key)) {
        throw "Template plan contains duplicate cell coordinate: $key"
    }
    $planCellByCoordinate[$key] = $planCell
}
foreach ($key in $mapCellByCoordinate.Keys) {
    if (-not $planCellByCoordinate.ContainsKey($key)) {
        throw "Template plan has no recipe for map cell: $key"
    }
}
$safeZoneMapByCoordinate = @{}
foreach ($safeZoneMap in @($plan.safeZoneMaps)) {
    $x = [int]$safeZoneMap.x
    $y = [int]$safeZoneMap.y
    $key = Get-CoordinateKey $x $y
    $mapFilename = [string]$safeZoneMap.mapFilename
    if ($safeZoneMapByCoordinate.ContainsKey($key) -or [System.IO.Path]::GetFileName($mapFilename) -ne $mapFilename -or [System.IO.Path]::GetExtension($mapFilename) -ine '.vmf') {
        throw "Template plan has an invalid standalone safe-zone map at $key. Re-run plan_cell_templates.ps1."
    }
    $safeZoneMapByCoordinate[$key] = [System.IO.Path]::GetFileNameWithoutExtension($mapFilename)
}
if (@($map.safeZones).Count -gt 0 -and $safeZoneMapByCoordinate.Count -eq 0) {
    throw 'Template plan has no standalone safe-zone maps. Re-run plan_cell_templates.ps1.'
}

$districts = @($map.districts | Sort-Object name)
$districtIndexByName = @{}
$runtimeDistricts = [System.Collections.Generic.List[object]]::new()
foreach ($district in $districts) {
    $districtName = Get-RecordName $district 'District'
    if ($districtIndexByName.ContainsKey($districtName)) { throw "Duplicate district name: $districtName" }
    $districtIndexByName[$districtName] = $runtimeDistricts.Count
    $runtimeDistricts.Add([ordered]@{ name = $districtName; color = $district.color.hex })
}

$landmarkIndexByName = @{}
$runtimeLandmarks = [System.Collections.Generic.List[string]]::new()
$metroLineIndexByName = @{}
$runtimeMetroLines = [System.Collections.Generic.List[string]]::new()
foreach ($mapCell in $mapCells) {
    foreach ($landmark in @($mapCell.landmarks)) {
        $landmarkName = Get-RecordName $landmark 'Landmark'
        if (-not $landmarkIndexByName.ContainsKey($landmarkName)) {
            $landmarkIndexByName[$landmarkName] = $runtimeLandmarks.Count
            $runtimeLandmarks.Add($landmarkName)
        }
    }
    foreach ($metroLine in @($mapCell.metro.lines)) {
        $lineName = [string]$metroLine
        if (-not $metroLineIndexByName.ContainsKey($lineName)) {
            $metroLineIndexByName[$lineName] = $runtimeMetroLines.Count
            $runtimeMetroLines.Add($lineName)
        }
    }
}

$safeZoneIndexByCoordinate = @{}
$safeZoneRequiredMapNames = @{}
$runtimeSafeZones = [System.Collections.Generic.List[object]]::new()
foreach ($safeZone in @($map.safeZones | Sort-Object name)) {
    $safeZoneName = Get-RecordName $safeZone 'Safe zone'
    $safeZoneKey = Get-CoordinateKey ([int]$safeZone.x) ([int]$safeZone.y)
    if ($safeZoneIndexByCoordinate.ContainsKey($safeZoneKey)) { throw "Multiple safe zones occupy cell $safeZoneKey." }
    $districtName = [string]$safeZone.district
    $districtId = $null
    if (-not [string]::IsNullOrWhiteSpace($districtName)) {
        if (-not $districtIndexByName.ContainsKey($districtName)) { throw "Safe zone '$safeZoneName' references unknown district '$districtName'." }
        $districtId = $districtIndexByName[$districtName]
    }
    if (-not $safeZoneMapByCoordinate.ContainsKey($safeZoneKey)) {
        throw "Safe zone '$safeZoneName' has no standalone map at $safeZoneKey. Re-run plan_cell_templates.ps1."
    }
    $safeZoneMapName = $safeZoneMapByCoordinate[$safeZoneKey]
    $safeZoneRequiredMapNames[$safeZoneMapName.ToLowerInvariant()] = $safeZoneMapName
    $safeZoneIndexByCoordinate[$safeZoneKey] = $runtimeSafeZones.Count
    $runtimeSafeZones.Add([ordered]@{
        name = $safeZoneName
        district = $districtId
        cell = Get-CellId ([int]$safeZone.x) ([int]$safeZone.y) $width
        difficult = [bool]$safeZone.difficult
        map = $safeZoneMapName
    })
}

$runtimeMetroStops = [System.Collections.Generic.List[object]]::new()
$metroStopIndexByName = @{}
foreach ($mapCell in ($mapCells | Sort-Object y, x)) {
    if ($null -eq $mapCell.metro.stop) { continue }
    $stop = $mapCell.metro.stop
    $stopName = Get-RecordName $stop 'Metro stop'
    $cellId = Get-CellId ([int]$mapCell.x) ([int]$mapCell.y) $width
    if ($metroStopIndexByName.ContainsKey($stopName)) {
        $existingStop = $runtimeMetroStops[$metroStopIndexByName[$stopName]]
        if ($existingStop.cell -ne $cellId) { throw "Metro stop '$stopName' appears in multiple cells." }
        continue
    }
    $lineIds = @($stop.lines | ForEach-Object { $metroLineIndexByName[[string]$_] } | Sort-Object -Unique)
    $accessCellIds = @($stop.accessPath | ForEach-Object {
        $coordinates = ([string]$_).Split(',')
        if ($coordinates.Count -ne 2) { throw "Metro stop '$stopName' has invalid access coordinate '$_'." }
        Get-CellId ([int]$coordinates[0]) ([int]$coordinates[1]) $width
    } | Sort-Object -Unique)
    $metroStopIndexByName[$stopName] = $runtimeMetroStops.Count
    $runtimeMetroStops.Add([ordered]@{ name = $stopName; cell = $cellId; major = [bool]$stop.major; lines = $lineIds; access = $accessCellIds })
}

$environmentIndexByKey = @{}
$runtimeEnvironments = [System.Collections.Generic.List[object]]::new()
$runtimeCells = [System.Collections.Generic.List[object]]::new()
$requiredMapNames = @{}
foreach ($safeZoneMapName in $safeZoneRequiredMapNames.Values) {
    $requiredMapNames[$safeZoneMapName.ToLowerInvariant()] = $safeZoneMapName
}
foreach ($mapCell in ($mapCells | Sort-Object y, x)) {
    $x = [int]$mapCell.x
    $y = [int]$mapCell.y
    $cellId = Get-CellId $x $y $width
    $key = Get-CoordinateKey $x $y
    $planCell = $planCellByCoordinate[$key]
    $mapName = [System.IO.Path]::GetFileNameWithoutExtension([string]$planCell.cellTemplateFilename)
    if ([string]::IsNullOrWhiteSpace($mapName)) { throw "Template plan cell $key has no recipe filename." }
    $requiredMapNames[$mapName.ToLowerInvariant()] = $mapName

    $tags = @($mapCell.environment.tags | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $environmentKey = "{0}|{1}" -f $mapCell.environment.terrain, ($tags -join '|')
    if (-not $environmentIndexByKey.ContainsKey($environmentKey)) {
        $environmentIndexByKey[$environmentKey] = $runtimeEnvironments.Count
        $runtimeEnvironments.Add([ordered]@{ terrain = [string]$mapCell.environment.terrain; tags = $tags })
    }

    $districtName = [string]$mapCell.district.name
    if (-not $districtIndexByName.ContainsKey($districtName)) { throw "Map cell $key references unknown district '$districtName'." }
    $safeZoneId = $null
    if ($null -ne $mapCell.safeZone) {
        $safeZoneName = Get-RecordName $mapCell.safeZone "Map cell $key safe zone"
        if (-not $safeZoneIndexByCoordinate.ContainsKey($key)) { throw "Map cell $key references safe zone '$safeZoneName', but no safe zone is registered at that coordinate." }
        $safeZoneId = $safeZoneIndexByCoordinate[$key]
        if ($runtimeSafeZones[$safeZoneId].name -ne $safeZoneName) { throw "Map cell $key safe-zone name does not match its registered safe zone." }
    }
    $landmarkIds = @($mapCell.landmarks | ForEach-Object { $landmarkIndexByName[(Get-RecordName $_ "Map cell $key landmark")] } | Sort-Object -Unique)
    $exits = [System.Collections.Generic.List[object]]::new()
    foreach ($neighbor in @($mapCell.neighbors)) {
        $hasRoad = [bool]$neighbor.roadConnected
        $hasHighway = [bool]$neighbor.highwayConnected
        if (-not $hasRoad -and -not $hasHighway) { continue }
        $direction = [string]$neighbor.direction
        if (-not $oppositeDirections.ContainsKey($direction) -or -not [bool]$neighbor.inBounds) {
            throw "Map cell $key has an invalid connected neighbour in direction '$direction'."
        }
        $targetKey = Get-CoordinateKey ([int]$neighbor.x) ([int]$neighbor.y)
        if (-not $mapCellByCoordinate.ContainsKey($targetKey)) { throw "Map cell $key connects to missing cell $targetKey." }
        $targetCell = $mapCellByCoordinate[$targetKey]
        $targetNeighbor = @($targetCell.neighbors | Where-Object { $_.direction -eq $oppositeDirections[$direction] })[0]
        if ($null -eq $targetNeighbor -or -not ([bool]$targetNeighbor.roadConnected -or [bool]$targetNeighbor.highwayConnected)) {
            throw "Map connection $key $direction is not reciprocated by $targetKey."
        }
        $roadBlocked = $hasRoad -and ((@($mapCell.road.blockades) -contains $direction) -or (@($targetCell.road.blockades) -contains $oppositeDirections[$direction]))
        $modes = [System.Collections.Generic.List[object]]::new()
        if ($hasRoad) { $modes.Add([ordered]@{ type = 'road'; blocked = [bool]$roadBlocked }) }
        if ($hasHighway) { $modes.Add([ordered]@{ type = 'highway'; blocked = $false }) }
        $exits.Add([ordered]@{ direction = $direction; cell = Get-CellId ([int]$neighbor.x) ([int]$neighbor.y) $width; modes = @($modes) })
    }

    $metroLineIds = @($mapCell.metro.lines | ForEach-Object { $metroLineIndexByName[[string]$_] } | Sort-Object -Unique)
    $metroStopId = $null
    if ($null -ne $mapCell.metro.stop) { $metroStopId = $metroStopIndexByName[(Get-RecordName $mapCell.metro.stop "Map cell $key metro stop")] }
    $runtimeCells.Add([ordered]@{
        id = $cellId
        map = $mapName
        environment = $environmentIndexByKey[$environmentKey]
        profile = [string]$planCell.environmentProfile
        atmosphere = Get-AtmosphereProfile $mapCell $planCell
        district = $districtIndexByName[$districtName]
        deadZone = [bool]$mapCell.deadZone
        building = [bool]$mapCell.building.present
        landmarks = $landmarkIds
        safeZone = $safeZoneId
        topology = [string]$planCell.topology
        entrances = @($planCell.activeEntrances)
        transport = [ordered]@{ bridge = [bool]$mapCell.highway.bridge; rampExits = @($mapCell.highway.rampExits); diagonal = [bool]$mapCell.highway.diagonal }
        exits = @($exits)
        metro = [ordered]@{ lines = $metroLineIds; stop = $metroStopId }
    })
}

if ($RequireCompiledMaps) {
    foreach ($mapName in ($requiredMapNames.Values | Sort-Object)) {
        $bspPath = Join-Path $BuildDirectory "$mapName.bsp"
        if (-not (Test-Path -LiteralPath $bspPath -PathType Leaf)) {
            throw "Required compiled BSP is missing: $bspPath"
        }
    }
}

$mapHash = (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash.ToLowerInvariant()
$planHash = (Get-FileHash -LiteralPath $PlanData -Algorithm SHA256).Hash.ToLowerInvariant()
$runtimeWorld = [ordered]@{
    schemaVersion = 1
    world = [ordered]@{
        seed = $map.map.seed
        grid = @($width, $height)
        origin = @([int]$map.map.origin.worldX, [int]$map.map.origin.worldY)
        mapDirectory = $mapDirectory
        mapManifestSha256 = $mapHash
        templatePlanSha256 = $planHash
    }
    atmosphereProfiles = @('outskirts', 'suburbs', 'inner_city', 'dead_zone', 'safe_zone')
    environments = @($runtimeEnvironments)
    districts = @($runtimeDistricts)
    landmarks = @($runtimeLandmarks)
    safeZones = @($runtimeSafeZones)
    metro = [ordered]@{ lines = @($runtimeMetroLines); stops = @($runtimeMetroStops) }
    cells = @($runtimeCells)
}

$outputDirectory = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
[System.IO.File]::WriteAllText($Output, ($runtimeWorld | ConvertTo-Json -Depth 12 -Compress), [System.Text.UTF8Encoding]::new($false))
Write-Output "Runtime world cells: $($runtimeCells.Count); recipe BSPs: $($requiredMapNames.Count); output: $Output"