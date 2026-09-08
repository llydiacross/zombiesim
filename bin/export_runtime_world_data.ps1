param(
    [string]$MapData = '',
    [string]$PlanData = '',
    [string]$Output = '',
    [string]$BuildDirectory = '',
    [string]$WorldProfile = '',
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

function Get-OptionalProperty {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }
    return $null
}

function Get-BridgeDeckDirections {
    param([object]$MapCell)

    $highway = Get-OptionalProperty $MapCell 'highway'
    if (-not [bool](Get-OptionalProperty $highway 'bridge')) {
        return @()
    }

    $bridgeDirection = [string](Get-OptionalProperty $highway 'bridgeCrossingDirection')
    if ($bridgeDirection -notin @('N', 'E', 'S', 'W')) {
        $highwayConnections = @((Get-OptionalProperty $highway 'connections'))
        $bridgeDirection = if ($highwayConnections -contains 'N' -and $highwayConnections -contains 'S') { 'E' } else { 'N' }
    }

    if ($bridgeDirection -in @('N', 'S')) {
        return @('N', 'S')
    }
    return @('E', 'W')
}

function Get-AtmosphereProfiles {
    param([hashtable]$Settings)

    if (-not $Settings.ContainsKey('atmosphere') -or -not ($Settings.atmosphere -is [System.Collections.IDictionary])) {
        throw 'generator-settings.json must define an atmosphere object.'
    }
    $profiles = @($Settings.atmosphere.profiles)
    if ($profiles.Count -eq 0) {
        throw 'generator-settings.json must define at least one atmosphere profile.'
    }

    $indexById = @{}
    for ($index = 0; $index -lt $profiles.Count; $index++) {
        $profile = $profiles[$index]
        if (-not ($profile -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$profile.id) -or $indexById.ContainsKey([string]$profile.id)) {
            throw "Atmosphere profile $index must have a unique non-empty id."
        }
        if (-not ($profile.fog -is [System.Collections.IDictionary]) -or @($profile.fog.color).Count -ne 3 -or
            $null -eq $profile.fog.start -or $null -eq $profile.fog.end -or $null -eq $profile.fog.maxDensity -or $null -eq $profile.fog.stormMultiplier) {
            throw "Atmosphere profile '$($profile.id)' must define fog color, start, end, maxDensity, and stormMultiplier."
        }
        if ([double]$profile.fog.start -lt 0 -or [double]$profile.fog.end -le [double]$profile.fog.start -or
            [double]$profile.fog.maxDensity -lt 0 -or [double]$profile.fog.maxDensity -gt 1 -or
            [double]$profile.fog.stormMultiplier -le 0 -or [double]$profile.fog.stormMultiplier -gt 1) {
            throw "Atmosphere profile '$($profile.id)' has invalid fog ranges."
        }
        foreach ($colorComponent in @($profile.fog.color)) {
            if ([double]$colorComponent -lt 0 -or [double]$colorComponent -gt 255) {
                throw "Atmosphere profile '$($profile.id)' has a fog color component outside 0-255."
            }
        }
        $indexById[[string]$profile.id] = $index
    }

    foreach ($requiredProfileId in @('outskirts', 'suburbs', 'inner_city', 'dead_zone', 'safe_zone')) {
        if (-not $indexById.ContainsKey($requiredProfileId)) {
            throw "generator-settings.json atmosphere.profiles must include the '$requiredProfileId' profile."
        }
    }

    return [pscustomobject]@{ Profiles = $profiles; IndexById = $indexById }
}

function Get-AtmosphereProfileId {
    param([object]$MapCell, [object]$PlanCell)

    if ($null -ne (Get-OptionalProperty $MapCell 'safeZone')) { return 'safe_zone' }
    if ([bool](Get-OptionalProperty $MapCell 'deadZone')) { return 'dead_zone' }
    if ($PlanCell.environmentProfile -in @('commercial', 'financial')) { return 'inner_city' }
    if ((Get-OptionalProperty $MapCell 'environment').terrain -in @('grassland', 'sandy')) { return 'outskirts' }
    return 'suburbs'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$generatorSettings = $worldGenerationProfile.Settings
$profileSettings = $worldGenerationProfile.Config
$atmosphereSettings = Get-AtmosphereProfiles $generatorSettings
$atmosphereProfiles = $atmosphereSettings.Profiles
$atmosphereProfileIndexById = $atmosphereSettings.IndexById
$mapDirectory = Split-Path -Leaf ([string]$profileSettings.releaseMapDirectory)
if ([string]::IsNullOrWhiteSpace($mapDirectory)) { throw 'The runtime map directory cannot be empty.' }
if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilePattern = "$($profileSettings.filePrefix)_grid_*.json"
    $MapData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $mapFilePattern -File |
        Where-Object { $_.Name -notlike '*_template_plan.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path -LiteralPath $MapData -PathType Leaf)) {
    throw 'A generated map manifest is required. Pass -MapData with a map_grid_*.json path.'
}
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a map_grid_*_template_plan.json path.'
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $projectRoot $profileSettings.buildDirectory
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $projectRoot $profileSettings.runtimeWorldData
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
    $safeZoneMapByCoordinate[$key] = $safeZoneMap
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
$originSafeZoneId = $null
if ($null -ne $map.map.origin) {
    $originSafeZoneKey = Get-CoordinateKey ([int]$map.map.origin.cellX) ([int]$map.map.origin.cellY)
}
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
    $safeZoneMap = $safeZoneMapByCoordinate[$safeZoneKey]
    $safeZoneMapName = [System.IO.Path]::GetFileNameWithoutExtension([string]$safeZoneMap.mapFilename)
    $safeZoneBiome = if ($null -ne $safeZoneMap.PSObject.Properties['biome']) { [string]$safeZoneMap.biome } else { '' }
    $safeZoneLandmarkVariant = if ($null -ne $safeZoneMap.PSObject.Properties['landmarkVariant']) { [string]$safeZoneMap.landmarkVariant } else { '' }
    $safeZoneId = "safezone-$([int]$safeZone.x)-$([int]$safeZone.y)"
    $isOrigin = $null -ne $originSafeZoneKey -and $safeZoneKey -eq $originSafeZoneKey
    $safeZoneRequiredMapNames[$safeZoneMapName.ToLowerInvariant()] = $safeZoneMapName
    $safeZoneIndexByCoordinate[$safeZoneKey] = $runtimeSafeZones.Count
    $runtimeSafeZones.Add([ordered]@{
        id = $safeZoneId
        name = $safeZoneName
        isOrigin = $isOrigin
        district = $districtId
        cell = Get-CellId ([int]$safeZone.x) ([int]$safeZone.y) $width
        difficult = [bool]$safeZone.difficult
        map = $safeZoneMapName
        biome = $safeZoneBiome
        landmarkVariant = $safeZoneLandmarkVariant
    })
    if ($isOrigin) {
        if ($null -ne $originSafeZoneId) { throw 'Multiple safe zones are marked as the world origin.' }
        $originSafeZoneId = $safeZoneId
    }
}
if ($null -eq $originSafeZoneId) { throw 'The world-origin city cell has no safe-zone entrance.' }

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
    $mapCellSafeZone = Get-OptionalProperty $mapCell 'safeZone'
    if ($null -ne $mapCellSafeZone) {
        $safeZoneName = Get-RecordName $mapCellSafeZone "Map cell $key safe zone"
        if (-not $safeZoneIndexByCoordinate.ContainsKey($key)) { throw "Map cell $key references safe zone '$safeZoneName', but no safe zone is registered at that coordinate." }
        $safeZoneId = $safeZoneIndexByCoordinate[$key]
        if ($runtimeSafeZones[$safeZoneId].name -ne $safeZoneName) { throw "Map cell $key safe-zone name does not match its registered safe zone." }
    }
    $landmarkIds = @($mapCell.landmarks | ForEach-Object { $landmarkIndexByName[(Get-RecordName $_ "Map cell $key landmark")] } | Sort-Object -Unique)
    $exits = [System.Collections.Generic.List[object]]::new()
    $bridgeDeckDirections = @(Get-BridgeDeckDirections $mapCell)
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
        $targetBridgeDeckDirections = @(Get-BridgeDeckDirections $targetCell)
        $hasRoad = $hasRoad -and [bool]$targetNeighbor.roadConnected -and ($bridgeDeckDirections.Count -eq 0 -or $bridgeDeckDirections -contains $direction) -and ($targetBridgeDeckDirections.Count -eq 0 -or $targetBridgeDeckDirections -contains $oppositeDirections[$direction])
        $hasHighway = $hasHighway -and [bool]$targetNeighbor.highwayConnected -and ($bridgeDeckDirections.Count -eq 0 -or $bridgeDeckDirections -notcontains $direction) -and ($targetBridgeDeckDirections.Count -eq 0 -or $targetBridgeDeckDirections -notcontains $oppositeDirections[$direction])
        if (-not $hasRoad -and -not $hasHighway) { continue }
        $roadBlocked = $hasRoad -and ((@($mapCell.road.blockades) -contains $direction) -or (@($targetCell.road.blockades) -contains $oppositeDirections[$direction]))
        $modes = [System.Collections.Generic.List[object]]::new()
        if ($hasRoad) { $modes.Add([ordered]@{ type = 'road'; blocked = [bool]$roadBlocked }) }
        if ($hasHighway) { $modes.Add([ordered]@{ type = 'highway'; blocked = $false }) }
        $exits.Add([ordered]@{ direction = $direction; cell = Get-CellId ([int]$neighbor.x) ([int]$neighbor.y) $width; modes = @($modes) })
    }

    $metroLineIds = @($mapCell.metro.lines | ForEach-Object { $metroLineIndexByName[[string]$_] } | Sort-Object -Unique)
    $metroStopId = $null
    if ($null -ne $mapCell.metro.stop) { $metroStopId = $metroStopIndexByName[(Get-RecordName $mapCell.metro.stop "Map cell $key metro stop")] }
    $cellRadiation = Get-OptionalProperty $mapCell 'radiation'
    $radiationIntensity = if ($null -ne $cellRadiation -and $null -ne (Get-OptionalProperty $cellRadiation 'intensity')) { [double]$cellRadiation.intensity } else { 0.0 }
    $radiationIntensity = [Math]::Max(0.0, [Math]::Min(1.0, $radiationIntensity))
    $cellDanger = Get-OptionalProperty $mapCell 'danger'
    $dangerIntensity = if ($null -ne $cellDanger -and $null -ne (Get-OptionalProperty $cellDanger 'intensity')) { [double]$cellDanger.intensity } else { 0.0 }
    $dangerIntensity = [Math]::Max(0.0, [Math]::Min(1.0, $dangerIntensity))
    $cellBuilding = Get-OptionalProperty $mapCell 'building'
    $runtimeCells.Add([ordered]@{
        id = $cellId
        map = $mapName
        environment = $environmentIndexByKey[$environmentKey]
        profile = [string]$planCell.environmentProfile
        atmosphereProfile = $atmosphereProfileIndexById[(Get-AtmosphereProfileId $mapCell $planCell)]
        district = $districtIndexByName[$districtName]
        deadZone = [bool](Get-OptionalProperty $mapCell 'deadZone')
        building = [bool](Get-OptionalProperty $cellBuilding 'present')
        landmarks = $landmarkIds
        safeZone = $safeZoneId
        radiation = $radiationIntensity
        danger = $dangerIntensity
        topology = [string]$planCell.topology
        entrances = @($planCell.activeEntrances)
        transport = [ordered]@{ bridge = [bool]$mapCell.highway.bridge; rampExits = if ([bool]$mapCell.highway.bridge) { @() } else { @($mapCell.highway.rampExits) }; diagonal = [bool]$mapCell.highway.diagonal }
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
$mapGeneration = Get-OptionalProperty $map 'generation'
$radiationGeneration = Get-OptionalProperty $mapGeneration 'radiation'
$radiationDamagePerSecondAtPeak = [double](Get-OptionalProperty $radiationGeneration 'damagePerSecondAtPeak')
$dangerGeneration = Get-OptionalProperty $mapGeneration 'danger'
$dangerEnabled = [bool](Get-OptionalProperty $dangerGeneration 'enabled')
$dangerPatternValue = Get-OptionalProperty $dangerGeneration 'pattern'
$dangerPattern = if ($null -ne $dangerPatternValue) { [string]$dangerPatternValue } else { 'none' }
$dangerTierCount = [int](Get-OptionalProperty $dangerGeneration 'tierCount')
$dangerOriginSource = Get-OptionalProperty $dangerGeneration 'origin'
$dangerOrigin = if ($null -ne $dangerOriginSource) { [ordered]@{ worldX = [int](Get-OptionalProperty $dangerOriginSource 'worldX'); worldY = [int](Get-OptionalProperty $dangerOriginSource 'worldY'); cellX = [int](Get-OptionalProperty $dangerOriginSource 'cellX'); cellY = [int](Get-OptionalProperty $dangerOriginSource 'cellY') } } else { $null }
$radiationEpicenterSource = Get-OptionalProperty $radiationGeneration 'epicenter'
$radiationEpicenter = if ($null -ne $radiationEpicenterSource) { [ordered]@{ name = [string](Get-OptionalProperty $radiationEpicenterSource 'name'); x = [int](Get-OptionalProperty $radiationEpicenterSource 'x'); y = [int](Get-OptionalProperty $radiationEpicenterSource 'y'); worldX = [int](Get-OptionalProperty $radiationEpicenterSource 'worldX'); worldY = [int](Get-OptionalProperty $radiationEpicenterSource 'worldY'); falloutRadiusCells = [int](Get-OptionalProperty $radiationEpicenterSource 'falloutRadiusCells'); falloutRadiusMiles = [double](Get-OptionalProperty $radiationEpicenterSource 'falloutRadiusMiles'); loreYieldMegatons = [double](Get-OptionalProperty $radiationEpicenterSource 'loreYieldMegatons') } } else { $null }
$radiationEpicenters = @()
$radiationEpicenterSources = Get-OptionalProperty $radiationGeneration 'epicenters'
if ($null -ne $radiationEpicenterSources) {
    foreach ($source in @($radiationEpicenterSources)) {
        $radiationEpicenters += [ordered]@{ name = [string](Get-OptionalProperty $source 'name'); x = [int](Get-OptionalProperty $source 'x'); y = [int](Get-OptionalProperty $source 'y'); worldX = [int](Get-OptionalProperty $source 'worldX'); worldY = [int](Get-OptionalProperty $source 'worldY'); falloutRadiusCells = [int](Get-OptionalProperty $source 'falloutRadiusCells'); falloutRadiusMiles = [double](Get-OptionalProperty $source 'falloutRadiusMiles'); loreYieldMegatons = [double](Get-OptionalProperty $source 'loreYieldMegatons') }
    }
} elseif ($null -ne $radiationEpicenter) {
    $radiationEpicenters = @($radiationEpicenter)
}
$radiationFalloutRadiusCells = [int](Get-OptionalProperty $radiationGeneration 'falloutRadiusCells')
$radiationDestroyedThresholdValue = Get-OptionalProperty $radiationGeneration 'destroyedThreshold'
$radiationDestroyedThreshold = if ($null -ne $radiationDestroyedThresholdValue) { [double]$radiationDestroyedThresholdValue } else { 1.0 }
$populationValue = Get-OptionalProperty (Get-OptionalProperty $map 'statistics') 'population'
if ($null -eq $populationValue -or [double]$populationValue -lt 0 -or [double][long]$populationValue -ne [double]$populationValue) {
    throw 'Map manifest statistics.population must be a non-negative integer.'
}
$population = [long]$populationValue
$runtimeWorld = [ordered]@{
    schemaVersion = 1
    world = [ordered]@{
        seed = $map.map.seed
        grid = @($width, $height)
        origin = @([int]$map.map.origin.worldX, [int]$map.map.origin.worldY)
        gridOrigin = @([int]$map.map.origin.cellX, [int]$map.map.origin.cellY)
        mapDirectory = $mapDirectory
        population = $population
        originSafeZoneId = $originSafeZoneId
        mapManifestSha256 = $mapHash
        templatePlanSha256 = $planHash
    }
    atmosphereProfiles = @($atmosphereProfiles)
    hazards = [ordered]@{ radiation = [ordered]@{ damagePerSecondAtPeak = [Math]::Max(0, $radiationDamagePerSecondAtPeak); epicenter = $radiationEpicenter; epicenters = @($radiationEpicenters); falloutRadiusCells = [Math]::Max(0, $radiationFalloutRadiusCells); destroyedThreshold = [Math]::Max(0.0, [Math]::Min(1.0, $radiationDestroyedThreshold)) }; danger = [ordered]@{ enabled = $dangerEnabled; pattern = $dangerPattern; origin = $dangerOrigin; tierCount = [Math]::Max(0, $dangerTierCount) } }
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