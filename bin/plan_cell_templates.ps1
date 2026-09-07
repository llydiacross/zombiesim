param(
    [string]$MapData = '',
    [string]$TemplateDirectory = '',
    [string]$CellDirectory = '',
    [ValidateRange(3, 99)]
    [int]$CellTileSize = 5,
    [string]$Output = '',
    [string]$ListOutput = '',
    [switch]$ListOnly,
    [string]$WorldProfile = '',
    [switch]$Preview,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$generatorSettings = $worldGenerationProfile.Settings
$profileSettings = $worldGenerationProfile.Config
$plannerSettings = $generatorSettings.cellPlanning
if (-not $PSBoundParameters.ContainsKey('CellTileSize')) {
    $CellTileSize = [int]$plannerSettings.cellTileGridSize
}

if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilePattern = "$($profileSettings.filePrefix)_grid_*.json"
    $MapData = @(Get-ChildItem -Path $PSScriptRoot -Filter $mapFilePattern -File |
        Where-Object { $_.Name -notlike '*_template_plan.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path $MapData)) {
    throw 'A generated map JSON file is required. Pass -MapData with the manifest path.'
}
if ([string]::IsNullOrWhiteSpace($TemplateDirectory)) {
    $TemplateDirectory = Join-Path $projectRoot $generatorSettings.paths.templateDirectory
}
if (-not (Test-Path $TemplateDirectory)) {
    throw "Template directory was not found: $TemplateDirectory"
}
if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = Join-Path $projectRoot $profileSettings.cellDirectory
}
if (-not (Test-Path $CellDirectory)) {
    [System.IO.Directory]::CreateDirectory($CellDirectory) | Out-Null
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MapData)
    $Output = Join-Path (Join-Path $projectRoot $generatorSettings.paths.scriptOutputDirectory) ("{0}_template_plan.json" -f $mapBaseName)
}
if ([string]::IsNullOrWhiteSpace($ListOutput)) {
    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MapData)
    $ListOutput = Join-Path (Join-Path $projectRoot $generatorSettings.paths.scriptOutputDirectory) ("{0}_required_cell_vmfs.txt" -f $mapBaseName)
}

$map = Get-Content -Raw $MapData | ConvertFrom-Json
if ($map.schemaVersion -lt 2) {
    throw 'The map manifest must use schema version 2 or later so environment tags are available.'
}

$templateFiles = @{}
$TemplateDirectory = (Resolve-Path $TemplateDirectory).Path.TrimEnd('\')
Get-ChildItem -Path $TemplateDirectory -Filter '*.vmf' -File -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($TemplateDirectory.Length).TrimStart('\').Replace('\', '/')
    $templateFiles[$relativePath.ToLowerInvariant()] = $relativePath
}
if ($templateFiles.Count -eq 0) {
    throw "No VMF templates were found in $TemplateDirectory"
}
$buildingTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.genericBuildings } | Sort-Object)
if ($plannerSettings.templatePatterns.ContainsKey('destroyedBuildings')) {
    $destroyedBuildingTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.destroyedBuildings } | Sort-Object)
} else {
    $destroyedBuildingTemplates = @()
}
$warehouseTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.warehouses } | Sort-Object)
$commercialTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.commercial } | Sort-Object)
$industryTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.industry } | Sort-Object)
$decorationTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.decorations } | Sort-Object)
$carparkTemplates = @($templateFiles.Values | Where-Object { $_ -match $plannerSettings.templatePatterns.carparks } | Sort-Object)
$filenameAbbreviations = $plannerSettings.filenameAbbreviations
$safeZoneSettings = $plannerSettings.safeZones
if ($null -eq $safeZoneSettings -or -not $safeZoneSettings.ContainsKey('biomePriority') -or -not $safeZoneSettings.ContainsKey('biomeCodes') -or -not $safeZoneSettings.ContainsKey('templateFilenameFormat')) {
    throw 'cellPlanning.safeZones must define biomePriority, biomeCodes, and templateFilenameFormat to plan standalone den maps.'
}
$safeZoneTemplateDirectory = Join-Path $projectRoot $generatorSettings.paths.safeZoneTemplateDirectory
if (-not (Test-Path -LiteralPath $safeZoneTemplateDirectory -PathType Container)) {
    throw "Safe-zone template directory was not found: $safeZoneTemplateDirectory"
}
$safeZoneTemplateDirectory = (Resolve-Path -LiteralPath $safeZoneTemplateDirectory).Path

function Get-CellConnections {
    param([object]$Cell)

    $connections = if ($Cell.highway.present) {
        @($Cell.highway.connections)
    } elseif ($Cell.road.present) {
        @($Cell.road.connections)
    } else {
        @()
    }
    return @($connections | Where-Object { $_ -in $generatorSettings.directions.cardinal })
}

function Get-HighwayRampExits {
    param([object]$Cell)

    if (-not $Cell.highway.present) { return @() }
    $recordedExits = @($Cell.highway.rampExits | Where-Object { $_ -in $generatorSettings.directions.cardinal })
    if ($recordedExits.Count -gt 0) { return @($recordedExits | Sort-Object -Unique) }
    return @($Cell.road.connections | Where-Object { $_ -in @('N', 'E', 'S', 'W') -and $_ -notin @($Cell.highway.connections) } | Sort-Object -Unique)
}

function Get-BridgeRampDirections {
    param([object]$Cell)

    return @($Cell.road.bridgeRampDirections | Where-Object { $_ -in $generatorSettings.directions.cardinal } | Sort-Object -Unique)
}

function Get-TransportFeature {
    param([object]$Cell)

    $bridgeRampDirections = @(Get-BridgeRampDirections $Cell)
    if ($Cell.highway.present -and $Cell.highway.bridge) {
        $bridgeDirection = $Cell.highway.bridgeCrossingDirection
        if ($bridgeDirection -in @('E', 'W')) { return 'bridge-horizontal' }
        if ($bridgeDirection -in @('N', 'S')) { return 'bridge-vertical' }
        $rampExits = @(Get-HighwayRampExits $Cell)
        if ($rampExits -contains 'E' -or $rampExits -contains 'W') { return 'bridge-horizontal' }
        return 'bridge-vertical'
    }

    if ($Cell.highway.present) {
        $rampExits = @(Get-HighwayRampExits $Cell)
        if ($rampExits.Count -eq 0) { return 'none' }
        if ($rampExits.Count -eq 1) { return "onramp-$($rampExits[0].ToLowerInvariant())" }
        $rampLabel = (@($rampExits | ForEach-Object { $_.ToLowerInvariant() }) -join '')
        return "onramp-dual-$rampLabel"
    }

    if ($bridgeRampDirections.Count -gt 0) { return "bridge-ramp-$($bridgeRampDirections[0].ToLowerInvariant())" }
    return 'none'
}

function Get-TransportFeatureTemplate {
    param([string]$TransportFeature)

    if ($TransportFeature -like 'bridge-ramp-*') { return $plannerSettings.transportTemplates['bridge-ramp'] }
    if ($TransportFeature -like 'bridge-*') { return $plannerSettings.transportTemplates.bridge }
    if ($TransportFeature -like 'onramp-dual-*') { return $plannerSettings.transportTemplates['onramp-dual'] }
    if ($TransportFeature -like 'onramp-*') { return $plannerSettings.transportTemplates.onramp }
    return $null
}

function Get-TransportFeatureRotation {
    param([string]$TransportFeature)

    if ($TransportFeature -eq 'bridge-vertical') { return [int]$plannerSettings.rotations.transport['bridge-vertical'] }
    if ($TransportFeature -eq 'bridge-horizontal') { return [int]$plannerSettings.rotations.transport['bridge-horizontal'] }
    if ($TransportFeature -like 'bridge-ramp-*') {
        $bridgeDirection = $TransportFeature.Substring('bridge-ramp-'.Length, 1).ToUpperInvariant()
        return [int]$plannerSettings.rotations.transport.bridgeRampByDirection[$bridgeDirection]
    }
    if ($TransportFeature -like 'onramp-dual-*') {
        $dualDirections = $TransportFeature.Substring('onramp-dual-'.Length).ToUpperInvariant()
        if ($dualDirections -match 'N' -and $dualDirections -match 'S') { return [int]$plannerSettings.rotations.transport.onrampByDirection.N }
        if ($dualDirections -match 'E' -and $dualDirections -match 'W') { return [int]$plannerSettings.rotations.transport.onrampByDirection.E }
    }
    $rampDirection = if ($TransportFeature -like 'onramp-*') { $TransportFeature.Substring('onramp-'.Length, 1).ToUpperInvariant() } else { $null }
    if ($null -eq $rampDirection) { return 0 }
    return [int]$plannerSettings.rotations.transport.onrampByDirection[$rampDirection]
}

function Get-ActiveEntrances {
    param([object]$Cell)

    $connections = @((@(Get-CellConnections $Cell) + @(Get-HighwayRampExits $Cell)) | Sort-Object -Unique)
    $transportFeature = Get-TransportFeature $Cell
    if ($transportFeature -eq 'bridge-vertical') { $connections += @('N', 'S') }
    if ($transportFeature -eq 'bridge-horizontal') { $connections += @('E', 'W') }
    $blockades = if ($Cell.highway.present) { @() } else { @($Cell.road.blockades) }
    return @($connections | Where-Object { $_ -notin $blockades } | Sort-Object -Unique)
}

function Get-CellTopology {
    param([object]$Cell)

    if ($Cell.highway.present) {
        $prefix = 'motorway'
    } elseif ($Cell.road.present) {
        $prefix = 'road'
    } else {
        return 'open'
    }
    $connections = @(Get-CellConnections $Cell)

    switch ($connections.Count) {
        4 { return "$prefix-crossjunction" }
        3 { return "$prefix-tjunction" }
        2 {
            if (($connections -contains 'N' -and $connections -contains 'S') -or ($connections -contains 'E' -and $connections -contains 'W')) {
                return "$prefix-straight"
            }
            return "$prefix-corner"
        }
        1 { return "$prefix-deadend" }
        default { return "$prefix-isolated" }
    }
}

function Get-CellOrientation {
    param(
        [object]$Cell,
        [string]$Topology
    )

    if ($Topology -eq 'open') { return 'none' }
    $connections = @(Get-CellConnections $Cell)
    $cardinals = @($generatorSettings.directions.cardinal)
    $directionNames = $generatorSettings.directions.names
    $presentDirections = @($cardinals | Where-Object { $connections -contains $_ })

    if ($Topology -like '*-crossjunction') { return 'all' }
    if ($Topology -like '*-straight') {
        if ($connections -contains 'N' -and $connections -contains 'S') { return 'vertical' }
        return 'horizontal'
    }
    if ($Topology -like '*-corner') {
        return ($presentDirections | ForEach-Object { $directionNames[$_] }) -join '-'
    }
    if ($Topology -like '*-tjunction') {
        $missingDirection = @($cardinals | Where-Object { $connections -notcontains $_ })[0]
        return "missing-$($directionNames[$missingDirection])"
    }
    if ($Topology -like '*-deadend') {
        return $directionNames[$presentDirections[0]]
    }
    return 'none'
}

function Get-EnvironmentProfile {
    param([object]$Cell)

    $tags = @($Cell.environment.tags)
    foreach ($tag in @($plannerSettings.environment.profilePriority)) {
        if ($tags -contains $tag) { return $tag }
    }
    if ($Cell.building.present) { return 'settlement' }
    return $Cell.environment.terrain
}

function Get-TerrainTemplate {
    param([string]$Terrain)

    if ($plannerSettings.terrainTemplates.ContainsKey($Terrain)) { return $plannerSettings.terrainTemplates[$Terrain] }
    return $plannerSettings.terrainTemplates.default
}

function Get-GenericTopologyTemplate {
    param([string]$Topology)

    if ($plannerSettings.topologyTemplates.ContainsKey($Topology)) { return $plannerSettings.topologyTemplates[$Topology] }
    return $null
}

function Get-LinearTopologyTemplate {
    param([string]$Topology)

    if ($Topology -like 'motorway-*') { return $plannerSettings.topologyTemplates['motorway-straight'] }
    return $plannerSettings.topologyTemplates['road-straight']
}

function Get-LayoutRotation {
    param(
        [string]$Topology,
        [string]$Orientation
    )

    if ($Topology -like '*-deadend') { return [int]$plannerSettings.rotations.layout[$Topology][$Orientation] }
    if ($Topology -like '*-straight') {
        return [int]$plannerSettings.rotations.layout.straight[$Orientation]
    }
    if ($Topology -like '*-corner') {
        return [int]$plannerSettings.rotations.layout.corner[$Orientation]
    }
    if ($Topology -like '*-tjunction') {
        return [int]$plannerSettings.rotations.layout.tjunction[$Orientation]
    }
    return 0
}

function Get-MotorwayDeadEndRotation {
    param([string]$Orientation)

    if (-not $plannerSettings.rotations.layout['motorway-deadend'].ContainsKey($Orientation)) { return 0 }
    return [int]$plannerSettings.rotations.layout['motorway-deadend'][$Orientation]
}

function Get-BuildingDensity {
    param(
        [string]$Terrain,
        [string]$Profile
    )

    $densitySettings = $plannerSettings.environment.buildingDensity
    if ($densitySettings.ContainsKey($Profile)) { return [double]$densitySettings[$Profile] }
    if ($densitySettings.fallbackByTerrain.ContainsKey($Terrain)) { return [double]$densitySettings.fallbackByTerrain[$Terrain] }
    return [double]$densitySettings.fallbackByTerrain.default
}

function Get-BuildingDensityTier {
    param(
        [object]$Cell,
        [string]$Profile
    )

    $tags = @($Cell.environment.tags)
    $tierSettings = $plannerSettings.environment.densityTiers
    if (@($tags | Where-Object { $_ -in $tierSettings.highTags }).Count -gt 0) { return 3 }
    if (@($tags | Where-Object { $_ -in $tierSettings.mediumTags }).Count -gt 0) { return 2 }
    if (@($tags | Where-Object { $_ -in $tierSettings.lowTags }).Count -gt 0) { return 1 }
    if ($Profile -in $tierSettings.highProfiles) { return 3 }
    if ($Profile -in $tierSettings.mediumProfiles) { return 2 }
    return 1
}

function Get-BuildingHeightTier {
    param([string]$Template)

    $templateName = Split-Path -Leaf $Template
    if ($templateName -match '_[0-9]+([a-z]+)\.vmf$') {
        return $Matches[1].Length
    }
    return 1
}

function Get-BuildingTemplatesForDensity {
    param(
        [string[]]$BuildingTemplates,
        [int]$DensityTier
    )

    $weightedTemplates = [System.Collections.Generic.List[string]]::new()
    foreach ($template in $BuildingTemplates) {
        $heightTier = [Math]::Min((Get-BuildingHeightTier $template), [int]$plannerSettings.buildingSelection.maximumHeightTier)
        $distance = [Math]::Abs($heightTier - $DensityTier)
        $weight = [Math]::Max([int]$plannerSettings.buildingSelection.minimumWeight, [int]$plannerSettings.buildingSelection.baseWeight - ($distance * [int]$plannerSettings.buildingSelection.heightDistanceWeight))
        for ($index = 0; $index -lt $weight; $index++) {
            $weightedTemplates.Add($template)
        }
    }
    return @($weightedTemplates)
}

function Get-RecipePlacementSeed {
    param(
        [string]$Profile,
        [string]$Topology,
        [string]$Orientation,
        [int]$BuildingDensityTier,
        [string[]]$Landmarks,
        [int]$Variant = 0
    )

    $signature = "$Profile|$Topology|$Orientation|density-$BuildingDensityTier|$($Landmarks -join '+')|variant-$($plannerSettings.variants.suffix)$Variant"
    [int64]$seed = 17
    foreach ($character in $signature.ToCharArray()) {
        $seed = (($seed * 31) + [int][char]$character) % 2147483647
    }
    return [int]$seed
}

function Get-DirectionalTileCoordinates {
    param(
        [string]$Direction,
        [int]$Center,
        [int]$TileGridSize
    )

    switch ($Direction) {
        'N' { return @(0..($Center - 1) | ForEach-Object { [pscustomobject]@{ tileX = $Center; tileY = $_ } }) }
        'E' { return @(($Center + 1)..($TileGridSize - 1) | ForEach-Object { [pscustomobject]@{ tileX = $_; tileY = $Center } }) }
        'S' { return @(($Center + 1)..($TileGridSize - 1) | ForEach-Object { [pscustomobject]@{ tileX = $Center; tileY = $_ } }) }
        'W' { return @(0..($Center - 1) | ForEach-Object { [pscustomobject]@{ tileX = $_; tileY = $Center } }) }
        default { return @() }
    }
}

function Get-DirectionalTileRotation {
    param([string]$Direction)

    return [int]$generatorSettings.directions.linearTileYaw[$Direction]
}

function Get-OppositeDirection {
    param([string]$Direction)

    if ($generatorSettings.directions.opposites.ContainsKey($Direction)) { return $generatorSettings.directions.opposites[$Direction] }
    return $null
}

function Get-DirectionalAdjacentCoordinate {
    param(
        [string]$Direction,
        [int]$Center
    )

    switch ($Direction) {
        'N' { return [pscustomobject]@{ tileX = $Center; tileY = $Center - 1 } }
        'E' { return [pscustomobject]@{ tileX = $Center + 1; tileY = $Center } }
        'S' { return [pscustomobject]@{ tileX = $Center; tileY = $Center + 1 } }
        'W' { return [pscustomobject]@{ tileX = $Center - 1; tileY = $Center } }
        default { return $null }
    }
}

function Get-CellTilePlacements {
    param(
        [object]$Cell,
        [string]$TerrainTemplate,
        [string[]]$BuildingTemplates,
        [string]$LandmarkTemplate,
        [string[]]$Landmarks,
        [string]$Profile,
        [string[]]$CarparkTemplates,
        [string[]]$DecorationTemplates,
        [int]$PlacementSeed,
        [int]$BuildingDensityTier,
        [string]$TransportFeature,
        [string]$Topology,
        [string]$Orientation,
        [int]$TileGridSize,
        [hashtable]$AvailableTemplates
    )

    $center = [int][Math]::Floor($TileGridSize / 2)
    $placements = @{}
    for ($tileY = 0; $tileY -lt $TileGridSize; $tileY++) {
        for ($tileX = 0; $tileX -lt $TileGridSize; $tileX++) {
            $placements["$tileX,$tileY"] = [pscustomobject]@{
                tileX = $tileX
                tileY = $tileY
                template = $TerrainTemplate
                rotationYaw = 0
                role = 'terrain'
            }
        }
    }

    $connections = @(Get-CellConnections $Cell)
    if ($connections.Count -gt 0) {
        $roadTemplate = Resolve-Template @((Get-LinearTopologyTemplate $Topology), $TerrainTemplate) $AvailableTemplates
        foreach ($direction in $connections) {
            $coordinates = @(Get-DirectionalTileCoordinates $direction $center $TileGridSize)
            $rotationYaw = Get-DirectionalTileRotation $direction
            foreach ($coordinate in $coordinates) {
                $placements["$($coordinate.tileX),$($coordinate.tileY)"] = [pscustomobject]@{
                    tileX = $coordinate.tileX
                    tileY = $coordinate.tileY
                    template = $roadTemplate
                    rotationYaw = $rotationYaw
                    role = 'road'
                }
            }
        }

        $transportTemplate = Get-TransportFeatureTemplate $TransportFeature
        $usesMotorwayDeadEnd = $Topology -eq 'motorway-deadend' -and $TransportFeature -in @('bridge-vertical', 'bridge-horizontal')
        $centerCandidates = @($transportTemplate, (Get-GenericTopologyTemplate $Topology), (Get-LinearTopologyTemplate $Topology), $TerrainTemplate)
        $centerTemplate = Resolve-Template $centerCandidates $AvailableTemplates
        $placements["$center,$center"] = [pscustomobject]@{
            tileX = $center
            tileY = $center
            template = $centerTemplate
            rotationYaw = if ($Topology -eq 'motorway-deadend' -and $null -eq $transportTemplate) { Get-MotorwayDeadEndRotation $Orientation } elseif ($null -eq $transportTemplate) { Get-LayoutRotation $Topology $Orientation } else { Get-TransportFeatureRotation $TransportFeature }
            role = if ($null -eq $transportTemplate) { 'road_center' } else { $TransportFeature }
        }

        if ($usesMotorwayDeadEnd) {
            $motorwayDirection = $Orientation.Substring(0, 1).ToUpperInvariant()
            $deadEndDirection = Get-OppositeDirection $motorwayDirection
            $deadEndCoordinate = Get-DirectionalAdjacentCoordinate $deadEndDirection $center
            $deadEndTemplate = Resolve-Template @($plannerSettings.topologyTemplates['motorway-deadend'], $plannerSettings.topologyTemplates['motorway-straight'], $TerrainTemplate) $AvailableTemplates
            $placements["$($deadEndCoordinate.tileX),$($deadEndCoordinate.tileY)"] = [pscustomobject]@{
                tileX = $deadEndCoordinate.tileX
                tileY = $deadEndCoordinate.tileY
                template = $deadEndTemplate
                rotationYaw = Get-MotorwayDeadEndRotation (@{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }[$motorwayDirection])
                role = 'motorway_bridge_deadend'
            }
        }

        if ($TransportFeature -like 'onramp-*') {
            $rampRoadTemplate = Resolve-Template @($plannerSettings.topologyTemplates['road-straight'], $TerrainTemplate) $AvailableTemplates
            foreach ($rampExit in @(Get-HighwayRampExits $Cell)) {
                $rotationYaw = Get-DirectionalTileRotation $rampExit
                foreach ($coordinate in @(Get-DirectionalTileCoordinates $rampExit $center $TileGridSize)) {
                    $placements["$($coordinate.tileX),$($coordinate.tileY)"] = [pscustomobject]@{
                        tileX = $coordinate.tileX
                        tileY = $coordinate.tileY
                        template = $rampRoadTemplate
                        rotationYaw = $rotationYaw
                        role = 'onramp_road'
                    }
                }
            }
        }

        if ($TransportFeature -in @('bridge-vertical', 'bridge-horizontal')) {
            $bridgeRoadTemplate = Resolve-Template @($plannerSettings.transportTemplates.bridgeRoad, $plannerSettings.topologyTemplates['road-straight'], $TerrainTemplate) $AvailableTemplates
            $bridgeDirections = if ($TransportFeature -eq 'bridge-vertical') { @('N', 'S') } else { @('E', 'W') }
            foreach ($bridgeDirection in $bridgeDirections) {
                $rotationYaw = Get-DirectionalTileRotation $bridgeDirection
                foreach ($coordinate in @(Get-DirectionalTileCoordinates $bridgeDirection $center $TileGridSize)) {
                    $placements["$($coordinate.tileX),$($coordinate.tileY)"] = [pscustomobject]@{
                        tileX = $coordinate.tileX
                        tileY = $coordinate.tileY
                        template = $bridgeRoadTemplate
                        rotationYaw = $rotationYaw
                        role = 'bridge_road'
                    }
                }
            }
        }

        if ($TransportFeature -like 'bridge-ramp-*') {
            $bridgeDirection = $TransportFeature.Substring('bridge-ramp-'.Length, 1).ToUpperInvariant()
            $bridgeRoadTemplate = Resolve-Template @($plannerSettings.transportTemplates.bridgeRoad, $plannerSettings.topologyTemplates['road-straight'], $TerrainTemplate) $AvailableTemplates
            $rotationYaw = Get-DirectionalTileRotation $bridgeDirection
            foreach ($coordinate in @(Get-DirectionalTileCoordinates $bridgeDirection $center $TileGridSize)) {
                $placements["$($coordinate.tileX),$($coordinate.tileY)"] = [pscustomobject]@{
                    tileX = $coordinate.tileX
                    tileY = $coordinate.tileY
                    template = $bridgeRoadTemplate
                    rotationYaw = $rotationYaw
                    role = 'bridge_road'
                }
            }
        }
    }

    if ($BuildingTemplates.Count -gt 0) {
        $buildingDensity = Get-BuildingDensity $Cell.environment.terrain $Profile
        $weightedBuildingTemplates = @(Get-BuildingTemplatesForDensity $BuildingTemplates $BuildingDensityTier)
        $preferDecorations = $Cell.environment.terrain -in $plannerSettings.decorations.preferredTerrains -or $Profile -in $plannerSettings.decorations.preferredProfiles
        foreach ($terrainPlacement in @($placements.Values | Where-Object { $_.role -eq 'terrain' } | Sort-Object tileY, tileX)) {
            $densityRoll = [Math]::Abs(($PlacementSeed + ([int]$terrainPlacement.tileX * 11) + ([int]$terrainPlacement.tileY * 17)) % 100)
            if ($densityRoll -ge [int]($buildingDensity * 100)) { continue }
            $decorationRoll = [Math]::Abs(($PlacementSeed + ([int]$terrainPlacement.tileX * 19) + ([int]$terrainPlacement.tileY * 23)) % 100)
            $useDecoration = if ($preferDecorations) { $decorationRoll -lt [int]$plannerSettings.decorations.preferredChancePercent } else { $decorationRoll -lt [int]$plannerSettings.decorations.standardChancePercent }
            if ($DecorationTemplates.Count -gt 0 -and $useDecoration) {
                $decorationIndex = ($PlacementSeed + ([int]$terrainPlacement.tileX * 19) + ([int]$terrainPlacement.tileY * 23)) % $DecorationTemplates.Count
                $placements["$($terrainPlacement.tileX),$($terrainPlacement.tileY)"] = [pscustomobject]@{
                    tileX = $terrainPlacement.tileX
                    tileY = $terrainPlacement.tileY
                    template = $DecorationTemplates[$decorationIndex]
                    rotationYaw = 0
                    role = 'decoration'
                }
                continue
            }
            $templateIndex = ($PlacementSeed + ([int]$terrainPlacement.tileX * 11) + ([int]$terrainPlacement.tileY * 17)) % $weightedBuildingTemplates.Count
            $placements["$($terrainPlacement.tileX),$($terrainPlacement.tileY)"] = [pscustomobject]@{
                tileX = $terrainPlacement.tileX
                tileY = $terrainPlacement.tileY
                template = $weightedBuildingTemplates[$templateIndex]
                rotationYaw = 0
                role = 'building'
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LandmarkTemplate)) {
        $landmarkPlacement = @($placements.Values | Where-Object { $_.role -in @('building', 'terrain') } | Sort-Object tileY, tileX | Select-Object -First 1)[0]
        if ($null -ne $landmarkPlacement) {
            $placements["$($landmarkPlacement.tileX),$($landmarkPlacement.tileY)"] = [pscustomobject]@{
                tileX = $landmarkPlacement.tileX
                tileY = $landmarkPlacement.tileY
                template = $LandmarkTemplate
                rotationYaw = 0
                role = 'landmark'
            }
        }
    }

    $hasNamedLandmark = @($Landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0
    $carparkRoll = $PlacementSeed % 100
    if ($Topology -eq 'road-straight' -and -not $hasNamedLandmark -and $CarparkTemplates.Count -gt 0 -and $carparkRoll -lt [int]$plannerSettings.carparks.roadStraightChancePercent) {
        $roadPlacements = @($placements.Values | Where-Object { $_.role -in @('road', 'road_center') })
        $carparkCandidates = @($placements.Values | Where-Object {
            if ($_.role -ne 'building') { return $false }
            foreach ($roadPlacement in $roadPlacements) {
                $distance = [Math]::Abs([int]$_.tileX - [int]$roadPlacement.tileX) + [Math]::Abs([int]$_.tileY - [int]$roadPlacement.tileY)
                if ($distance -eq 1) { return $true }
            }
            return $false
        } | Sort-Object tileY, tileX)
        if ($carparkCandidates.Count -gt 0) {
            $carparkIndex = $PlacementSeed % $carparkCandidates.Count
            $carparkTemplateIndex = [int]([Math]::Floor($PlacementSeed / 7) % $CarparkTemplates.Count)
            $carparkPlacement = $carparkCandidates[$carparkIndex]
            $placements["$($carparkPlacement.tileX),$($carparkPlacement.tileY)"] = [pscustomobject]@{
                tileX = $carparkPlacement.tileX
                tileY = $carparkPlacement.tileY
                template = $CarparkTemplates[$carparkTemplateIndex]
                rotationYaw = Get-LayoutRotation $Topology $Orientation
                role = 'carpark'
            }
        }
    }

    return @($placements.Values | Sort-Object tileY, tileX)
}

function Get-ProfileFallbackTemplates {
    param(
        [object]$Cell,
        [string]$Profile,
        [string[]]$Landmarks
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    $allowCommercial = $Profile -in $plannerSettings.buildingSelection.commercialProfiles -or $Landmarks -contains 'Market'
    $allowIndustry = $Cell.environment.terrain -in $plannerSettings.buildingSelection.industryTerrains -or $Profile -in $plannerSettings.buildingSelection.industryProfiles
    $candidatePool = if ($Profile -eq 'destroyed' -and $destroyedBuildingTemplates.Count -gt 0) { @($destroyedBuildingTemplates) } else { @($buildingTemplates) + @($warehouseTemplates) }
    if ($allowCommercial) { $candidatePool += @($commercialTemplates) }
    if ($allowIndustry) { $candidatePool += @($industryTemplates) }
    foreach ($candidate in $candidatePool) {
        if (-not $candidates.Contains($candidate)) {
            $candidates.Add($candidate)
        }
    }
    return @($candidates)
}

function Get-LandmarkTemplate {
    param(
        [string[]]$Landmarks,
        [hashtable]$AvailableTemplates
    )

    foreach ($landmark in $Landmarks) {
        $templatePattern = if ($plannerSettings.landmarkTemplatePatterns.ContainsKey($landmark)) { $plannerSettings.landmarkTemplatePatterns[$landmark] } else { $null }
        if ($null -eq $templatePattern) { continue }
        $matches = @($AvailableTemplates.Values | Where-Object { $_ -like $templatePattern -or $_ -like $templatePattern.TrimStart('*/') } | Sort-Object)
        if ($matches.Count -gt 0) { return $matches[0] }
        if ($landmark -eq 'Market' -and $commercialTemplates.Count -gt 0) { return $commercialTemplates[0] }
    }
    return $null
}

function Get-RecipeFilenameCodes {
    param(
        [string]$Profile,
        [string]$Topology,
        [string]$Orientation,
        [string]$TransportFeature,
        [int]$BuildingDensityTier,
        [string[]]$Landmarks
    )

    $profileKey = ConvertTo-FilenamePart $Profile
    $topologyKey = ConvertTo-FilenamePart $Topology
    $orientationKey = ConvertTo-FilenamePart $Orientation
    $profileCode = if ($filenameAbbreviations.environmentProfiles.Contains($profileKey)) { $filenameAbbreviations.environmentProfiles[$profileKey] } else { $profileKey }
    $topologyCode = if ($filenameAbbreviations.topologies.Contains($topologyKey)) { $filenameAbbreviations.topologies[$topologyKey] } else { $topologyKey }
    $orientationCode = if ($filenameAbbreviations.orientations.Contains($orientationKey)) { $filenameAbbreviations.orientations[$orientationKey] } else { $orientationKey }
    $transportCode = ''
    if ($TransportFeature -like 'bridge-ramp-*') {
        $transportCode = $filenameAbbreviations.transportFeatures['bridge-ramp'].Replace('<direction>', $TransportFeature.Substring('bridge-ramp-'.Length).ToLowerInvariant())
    }
    elseif ($TransportFeature -like 'onramp-dual-*') {
        $transportCode = $filenameAbbreviations.transportFeatures['onramp-dual'].Replace('<directions>', $TransportFeature.Substring('onramp-dual-'.Length).ToLowerInvariant())
    }
    elseif ($TransportFeature -like 'onramp-*') {
        $transportCode = $filenameAbbreviations.transportFeatures.onramp.Replace('<direction>', $TransportFeature.Substring('onramp-'.Length).ToLowerInvariant())
    }
    elseif ($filenameAbbreviations.transportFeatures.Contains($TransportFeature)) { $transportCode = $filenameAbbreviations.transportFeatures[$TransportFeature] }
    $landmarkCodes = @($Landmarks | ForEach-Object {
        $landmarkKey = ConvertTo-FilenamePart $_
        if ($filenameAbbreviations.landmarks.Contains($landmarkKey)) { $filenameAbbreviations.landmarks[$landmarkKey] } else { $landmarkKey }
    })
    return [pscustomobject]@{
        environment = $profileCode
        topology = $topologyCode
        orientation = $orientationCode
        transport = $transportCode
        density = "d$BuildingDensityTier"
        landmarks = $landmarkCodes
    }
}

function Get-CellFilename {
    param([object]$Codes)

    $filename = [string]$filenameAbbreviations.format
    if ([string]::IsNullOrWhiteSpace($filename)) { throw 'cellPlanning.filenameAbbreviations.format must not be empty.' }
    $filename = $filename.Replace('<environment>', [string]$Codes.environment)
    $filename = $filename.Replace('<topology>', [string]$Codes.topology)
    $filename = $filename.Replace('<orientation>', [string]$Codes.orientation)
    $filename = if ([string]::IsNullOrWhiteSpace($Codes.transport)) {
        $filename.Replace('[-<transport>]', '')
    } else {
        $filename.Replace('[-<transport>]', "-$($Codes.transport)")
    }
    $filename = $filename.Replace('d<density>', [string]$Codes.density)
    return $filename.Replace('<landmarks>', (@($Codes.landmarks) -join '+'))
}

function Get-CellVariantFilename {
    param(
        [string]$BaseFilename,
        [int]$Variant
    )

    if ($Variant -lt 1) { return $BaseFilename }
    return ('{0}-{1}{2}.vmf' -f [System.IO.Path]::GetFileNameWithoutExtension($BaseFilename), $plannerSettings.variants.suffix, $Variant)
}

function Get-CellVariantSortKey {
    param([object]$Cell)

    $signature = "$($Cell.baseCellTemplateFilename)|$($Cell.x),$($Cell.y)"
    [int64]$seed = 17
    foreach ($character in $signature.ToCharArray()) {
        $seed = (($seed * 31) + [int][char]$character) % 2147483647
    }
    return $seed
}

function ConvertTo-FilenamePart {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'none' }
    return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-') -replace '(^-)|(-$)', '')
}

function Get-CellLandmarks {
    param([object]$Cell)

    $landmarks = @($Cell.landmarks | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($landmarks.Count -eq 0) { return @('none') }
    return $landmarks
}

function Get-CellFeatures {
    param(
        [object]$Cell,
        [string]$Terrain,
        [string]$Profile,
        [string]$Topology
    )

    $redundantTags = @($Terrain, $Profile)
    if ($Topology -like 'motorway-*') {
        $redundantTags += 'highway'
    } elseif ($Topology -like 'road-*') {
        $redundantTags += 'roadside'
    }
    $features = @($Cell.environment.tags | Where-Object { $_ -notin $redundantTags })
    if ($Cell.building.present) { $features += 'building' }
    if ($Cell.deadZone) { $features += 'dead_zone' }
    if ($null -ne $Cell.safeZone) { $features += 'safe_zone' }
    if ($null -ne $Cell.metro.stop) { $features += 'metro_stop' }
    if (@($Cell.metro.lines).Count -gt 0) { $features += 'metro_route' }
    return @($features | Sort-Object -Unique)
}

function Resolve-Template {
    param(
        [string[]]$Candidates,
        [hashtable]$AvailableTemplates
    )

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $candidateKey = $candidate.ToLowerInvariant()
        if ($AvailableTemplates.ContainsKey($candidateKey)) {
            return $AvailableTemplates[$candidateKey]
        }
    }
    throw "No fallback template exists. Candidates: $($Candidates -join ', ')"
}

function Get-SafeZoneBiome {
    param([object]$Cell)

    $tags = @($Cell.environment.tags)
    foreach ($biome in @($safeZoneSettings.biomePriority)) {
        if ($tags -contains $biome) {
            return [string]$biome
        }
    }

    return [string]$safeZoneSettings.defaultBiome
}

function Get-SafeZoneLandmarkVariant {
    param([object]$Cell)

    $landmarkNames = @(Get-CellLandmarks $Cell)
    foreach ($landmark in @($safeZoneSettings.landmarkPriority)) {
        if ($landmarkNames -contains $landmark) {
            if (-not $safeZoneSettings.landmarkVariants.ContainsKey($landmark)) {
                throw "Standalone safe-zone landmark '$landmark' has no configured landmarkVariants entry."
            }
            return [string]$safeZoneSettings.landmarkVariants[$landmark]
        }
    }

    return ''
}

function Get-SafeZoneTemplateFilename {
    param(
        [string]$Biome,
        [string]$LandmarkVariant
    )

    if (-not $safeZoneSettings.biomeCodes.ContainsKey($Biome)) {
        throw "No standalone safe-zone biome code is configured for '$Biome'."
    }
    $biomeCode = [string]$safeZoneSettings.biomeCodes[$Biome]
    $landmarkSuffix = if ([string]::IsNullOrWhiteSpace($LandmarkVariant)) { '' } else { "_$LandmarkVariant" }
    $templateFilename = ([string]$safeZoneSettings.templateFilenameFormat).Replace('{biome}', $biomeCode).Replace('{landmarkSuffix}', $landmarkSuffix)
    if ([System.IO.Path]::GetFileName($templateFilename) -ne $templateFilename -or [System.IO.Path]::GetExtension($templateFilename) -ine '.vmf') {
        throw "Safe-zone template for biome '$Biome' must be a .vmf filename without a path: $templateFilename"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $safeZoneTemplateDirectory $templateFilename) -PathType Leaf)) {
        throw "Safe-zone template for biome '$Biome' was not found: $(Join-Path $safeZoneTemplateDirectory $templateFilename)"
    }
    return $templateFilename
}

function Get-SafeZoneMapFilename {
    param(
        [string]$Biome,
        [string]$LandmarkVariant
    )

    $biomeCode = [string]$safeZoneSettings.biomeCodes[$Biome]
    $landmarkSuffix = if ([string]::IsNullOrWhiteSpace($LandmarkVariant)) { '' } else { "_$LandmarkVariant" }
    return "zn_den_${biomeCode}${landmarkSuffix}.vmf"
}

$planCells = @()
foreach ($cell in $map.cells) {
    $topology = Get-CellTopology $cell
    $orientation = Get-CellOrientation $cell $topology
    $profile = Get-EnvironmentProfile $cell
    $terrainTemplate = Get-TerrainTemplate $cell.environment.terrain
    $genericTopologyTemplate = Get-GenericTopologyTemplate $topology
    $transportFeature = Get-TransportFeature $cell
    $rampExits = @(Get-HighwayRampExits $cell)
    $bridgeRampDirections = @(Get-BridgeRampDirections $cell)
    $landmarks = @(Get-CellLandmarks $cell)
    $buildingCandidates = @(Get-ProfileFallbackTemplates $cell $profile $landmarks)
    $landmarkTemplate = Get-LandmarkTemplate $landmarks $templateFiles
    $buildingDensityTier = Get-BuildingDensityTier $cell $profile
    $placementSeed = Get-RecipePlacementSeed $profile $topology $orientation $buildingDensityTier $landmarks

    $desiredTemplate = if ($topology -eq 'open' -and $profile -in @('grassland', 'sandy', 'dirt')) {
        if ($buildingCandidates.Count -gt 0) { $buildingCandidates[0] } else { $terrainTemplate }
    } elseif ($profile -in @('grassland', 'sandy', 'dirt', 'settlement') -and $null -ne $genericTopologyTemplate) {
        $genericTopologyTemplate
    } elseif ($topology -eq 'open' -and $buildingCandidates.Count -gt 0) {
        $buildingCandidates[0]
    } else {
        "tile_{0}_{1}.vmf" -f $profile, $topology
    }

    $selectedTemplate = Resolve-Template @(
        $desiredTemplate,
        $genericTopologyTemplate,
        $buildingCandidates,
        $terrainTemplate
    ) $templateFiles
    $exactTemplateExists = $templateFiles.ContainsKey($desiredTemplate.ToLowerInvariant())
    $features = @(Get-CellFeatures $cell $cell.environment.terrain $profile $topology)
    $activeEntrances = @(Get-ActiveEntrances $cell)
    $tilePlacements = @(Get-CellTilePlacements $cell $terrainTemplate $buildingCandidates $landmarkTemplate $landmarks $profile $carparkTemplates $decorationTemplates $placementSeed $buildingDensityTier $transportFeature $topology $orientation $CellTileSize $templateFiles)
    $filenameCodes = Get-RecipeFilenameCodes $profile $topology $orientation $transportFeature $buildingDensityTier $landmarks
    $cellTemplateFilename = Get-CellFilename $filenameCodes
    $cellTemplatePath = Join-Path $CellDirectory $cellTemplateFilename

    $planCells += [pscustomobject]@{
        x = [int]$cell.x
        y = [int]$cell.y
        worldX = [int]$cell.worldX
        worldY = [int]$cell.worldY
        topology = $topology
        orientation = $orientation
        transportFeature = $transportFeature
        rampExits = $rampExits
        bridgeRampDirections = $bridgeRampDirections
        activeEntrances = $activeEntrances
        environmentProfile = $profile
        buildingDensityTier = $buildingDensityTier
        filenameCodes = $filenameCodes
        environmentTags = @($cell.environment.tags)
        landmarks = $landmarks
        features = $features
        cellTemplateFilename = $cellTemplateFilename
        baseCellTemplateFilename = $cellTemplateFilename
        cellVariant = 0
        availableCellVariants = 0
        cellTemplatePath = $cellTemplatePath
        cellTemplateExists = Test-Path $cellTemplatePath
        desiredChunkTemplate = $desiredTemplate
        selectedChunkTemplate = $selectedTemplate
        buildingTemplates = $buildingCandidates
        landmarkTemplate = $landmarkTemplate
        placementSeed = $placementSeed
        chunkFallbackUsed = -not $exactTemplateExists
        tileGridSize = $CellTileSize
        tilePlacements = $tilePlacements
    }
}

$safeZoneMaps = @()
$safeZoneMapCoordinates = @{}
foreach ($safeZone in @($map.safeZones | Sort-Object y, x, name)) {
    $x = [int]$safeZone.x
    $y = [int]$safeZone.y
    $coordinateKey = "$x,$y"
    if ($safeZoneMapCoordinates.ContainsKey($coordinateKey)) {
        throw "Multiple safe zones occupy map cell $coordinateKey."
    }
    $mapCell = @($map.cells | Where-Object { $_.x -eq $x -and $_.y -eq $y } | Select-Object -First 1)[0]
    if ($null -eq $mapCell -or $null -eq $mapCell.safeZone) {
        throw "Safe zone '$($safeZone.name)' does not match a generated map cell at $coordinateKey."
    }
    $biome = Get-SafeZoneBiome $mapCell
    $landmarkVariant = Get-SafeZoneLandmarkVariant $mapCell
    $templateFilename = Get-SafeZoneTemplateFilename $biome $landmarkVariant
    $mapFilename = Get-SafeZoneMapFilename $biome $landmarkVariant
    $safeZoneMaps += [pscustomobject]@{
        x = $x
        y = $y
        name = [string]$safeZone.name
        biome = $biome
        biomeCode = [string]$safeZoneSettings.biomeCodes[$biome]
        landmarkVariant = $landmarkVariant
        templateFilename = $templateFilename
        mapFilename = $mapFilename
        mapName = [System.IO.Path]::GetFileNameWithoutExtension($mapFilename)
    }
    $safeZoneMapCoordinates[$coordinateKey] = $true
}

$variantThreshold = [int]$plannerSettings.variants.usageThreshold
$maximumCellVariants = [int]$plannerSettings.variants.maximumPerRecipe
foreach ($recipeGroup in @($planCells | Group-Object baseCellTemplateFilename | Where-Object { $_.Count -gt $variantThreshold })) {
    $variantCount = [Math]::Min($maximumCellVariants, $recipeGroup.Count)
    $variantCells = @($recipeGroup.Group | Sort-Object @{ Expression = { Get-CellVariantSortKey $_ }; Ascending = $true }, x, y)
    for ($variantIndex = 0; $variantIndex -lt $variantCells.Count; $variantIndex++) {
        $variantCell = $variantCells[$variantIndex]
        $variantCell.cellVariant = ($variantIndex % $variantCount) + 1
        $variantCell.availableCellVariants = $variantCount
        $variantCell.cellTemplateFilename = Get-CellVariantFilename $variantCell.baseCellTemplateFilename $variantCell.cellVariant
        $variantCell.cellTemplatePath = Join-Path $CellDirectory $variantCell.cellTemplateFilename
        $variantCell.cellTemplateExists = Test-Path $variantCell.cellTemplatePath
        $variantCell.placementSeed = Get-RecipePlacementSeed $variantCell.environmentProfile $variantCell.topology $variantCell.orientation $variantCell.buildingDensityTier $variantCell.landmarks $variantCell.cellVariant
        $mapCell = @($map.cells | Where-Object { $_.x -eq $variantCell.x -and $_.y -eq $variantCell.y } | Select-Object -First 1)[0]
        if ($null -eq $mapCell) { throw "Map cell was not found for variant at $($variantCell.x),$($variantCell.y)" }
        $variantTerrainTemplate = Get-TerrainTemplate $mapCell.environment.terrain
        $variantCell.tilePlacements = @(Get-CellTilePlacements $mapCell $variantTerrainTemplate $variantCell.buildingTemplates $variantCell.landmarkTemplate $variantCell.landmarks $variantCell.environmentProfile $carparkTemplates $decorationTemplates $variantCell.placementSeed $variantCell.buildingDensityTier $variantCell.transportFeature $variantCell.topology $variantCell.orientation $CellTileSize $templateFiles)
    }
}

$requiredCellFiles = @($planCells | Group-Object cellTemplateFilename | Sort-Object Name | ForEach-Object {
    $representative = $_.Group[0]
    [pscustomobject]@{
        filename = $_.Name
        baseFilename = $representative.baseCellTemplateFilename
        variant = $representative.cellVariant
        availableVariants = $representative.availableCellVariants
        environmentProfile = $representative.environmentProfile
        filenameCodes = $representative.filenameCodes
        topology = $representative.topology
        orientation = $representative.orientation
        transportFeature = $representative.transportFeature
        rampExits = $representative.rampExits
        bridgeRampDirections = $representative.bridgeRampDirections
        landmarks = $representative.landmarks
        cellCount = $_.Count
        cellTemplateExists = @($_.Group | Where-Object cellTemplateExists).Count -eq $_.Count
        cells = @($_.Group | ForEach-Object { [pscustomobject]@{ x = $_.x; y = $_.y } })
        selectedChunkTemplates = @($_.Group.selectedChunkTemplate | Sort-Object -Unique)
        buildingTemplates = @($_.Group.buildingTemplates | Sort-Object -Unique)
        landmarkTemplates = @($_.Group.landmarkTemplate | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        tileCount = $CellTileSize * $CellTileSize
        tileTemplates = @($_.Group.tilePlacements | ForEach-Object { $_.template } | Sort-Object -Unique)
    }
})
$missingCellFiles = @($requiredCellFiles | Where-Object { -not $_.cellTemplateExists })

$plan = [ordered]@{
    schemaVersion = 4
    mapData = [System.IO.Path]::GetFileName($MapData)
    cellDirectory = $CellDirectory
    chunkTemplateDirectory = $TemplateDirectory
    safeZoneTemplateDirectory = $safeZoneTemplateDirectory
    availableChunkTemplates = @($templateFiles.Values | Sort-Object)
    filenameAbbreviations = $filenameAbbreviations
    cellTileGridSize = $CellTileSize
    selectedCellCount = $planCells.Count
    requiredCellCount = $requiredCellFiles.Count
    requiredStandaloneMapCount = $safeZoneMaps.Count
    missingCellCount = $missingCellFiles.Count
    requiredCellList = $ListOutput
    requiredCellFiles = $requiredCellFiles
    missingCellFiles = $missingCellFiles
    safeZoneMaps = $safeZoneMaps
    cells = $planCells
}

if (-not $ListOnly) {
    [System.IO.File]::WriteAllText($Output, ($plan | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllLines($ListOutput, [string[]]@($requiredCellFiles | ForEach-Object { $_.filename }), [System.Text.UTF8Encoding]::new($false))
    Write-Output "Wrote template plan: $Output"
    Write-Output "Wrote required cell list: $ListOutput"
}

$requiredCellFiles | ForEach-Object { $_.filename }
