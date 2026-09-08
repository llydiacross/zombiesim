param(
    [string]$MapData = '',
    [string]$TemplateDirectory = '',
    [string]$CellDirectory = '',
    [ValidateRange(3, 99)]
    [int]$CellTileSize = 5,
    [string]$Output = '',
    [string]$ListOutput = '',
    [switch]$ListOnly,
    [switch]$ForceEligibleCarparks,
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
$multiTileSettings = if ($plannerSettings.ContainsKey('multiTileFeatures')) { $plannerSettings.multiTileFeatures } else { @{} }
$buildingSelectionSettings = $plannerSettings.buildingSelection
$multiTileEnabled = $multiTileSettings.ContainsKey('enabled') -and [bool]$multiTileSettings.enabled
$maximumMultiTileFootprint = if ($multiTileSettings.ContainsKey('maximumFootprint')) { [int]$multiTileSettings.maximumFootprint } else { 3 }
$multiTileBuildingChancePercent = if ($multiTileSettings.ContainsKey('buildingChancePercent')) { [int]$multiTileSettings.buildingChancePercent } else { 0 }
$multiTileFixtureTemplateProperty = if ($multiTileSettings.ContainsKey('fixtureTemplateProperty')) { [string]$multiTileSettings.fixtureTemplateProperty } else { 'multiTileTemplate' }
$specialLandmarkSettings = if ($multiTileSettings.ContainsKey('specialLandmarks')) { $multiTileSettings.specialLandmarks } else { @{} }
$epicenterSettings = if ($multiTileSettings.ContainsKey('epicenter')) { $multiTileSettings.epicenter } else { @{} }
$epicenterLandmarkName = if ($epicenterSettings.ContainsKey('landmark')) { [string]$epicenterSettings.landmark } else { 'The Epicenter' }
$epicenterPlacement = if ($epicenterSettings.ContainsKey('placement')) { [string]$epicenterSettings.placement } else { 'center' }
$epicenterExclusive = -not $epicenterSettings.ContainsKey('exclusive') -or [bool]$epicenterSettings.exclusive
$commercialSpreadChancePercent = if ($buildingSelectionSettings.ContainsKey('commercialSpreadChancePercent')) { [int]$buildingSelectionSettings.commercialSpreadChancePercent } else { 0 }
$commercialSpreadProfiles = if ($buildingSelectionSettings.ContainsKey('commercialSpreadProfiles')) { @($buildingSelectionSettings.commercialSpreadProfiles | ForEach-Object { [string]$_ }) } else { @() }
if ($maximumMultiTileFootprint -lt 1 -or $maximumMultiTileFootprint -gt 3) {
    throw 'cellPlanning.multiTileFeatures.maximumFootprint must be from 1 through 3.'
}
if ($multiTileBuildingChancePercent -lt 0 -or $multiTileBuildingChancePercent -gt 100) {
    throw 'cellPlanning.multiTileFeatures.buildingChancePercent must be from 0 through 100.'
}
if ($commercialSpreadChancePercent -lt 0 -or $commercialSpreadChancePercent -gt 100) {
    throw 'cellPlanning.buildingSelection.commercialSpreadChancePercent must be from 0 through 100.'
}
if ([string]::IsNullOrWhiteSpace($multiTileFixtureTemplateProperty)) {
    throw 'cellPlanning.multiTileFeatures.fixtureTemplateProperty cannot be empty.'
}
if (-not ($specialLandmarkSettings -is [System.Collections.IDictionary])) {
    throw 'cellPlanning.multiTileFeatures.specialLandmarks must be an object.'
}
foreach ($specialLandmarkName in $specialLandmarkSettings.Keys) {
    $specialLandmark = $specialLandmarkSettings[$specialLandmarkName]
    if (-not ($specialLandmark -is [System.Collections.IDictionary])) {
        throw "cellPlanning.multiTileFeatures.specialLandmarks.$specialLandmarkName must be an object."
    }
    $specialPlacement = if ($specialLandmark.ContainsKey('placement')) { [string]$specialLandmark.placement } else { 'road-facing' }
    if ($specialPlacement -notin @('center', 'road-facing')) {
        throw "Special landmark '$specialLandmarkName' must use a center or road-facing placement."
    }
    $overwritesRoads = $specialLandmark.ContainsKey('overwriteRoads') -and [bool]$specialLandmark.overwriteRoads
    $capsApproachRoads = $specialLandmark.ContainsKey('capApproachRoads') -and [bool]$specialLandmark.capApproachRoads
    if ($capsApproachRoads -and -not $overwritesRoads) {
        throw "Special landmark '$specialLandmarkName' cannot cap approach roads without overwriteRoads."
    }
}
if ([string]::IsNullOrWhiteSpace($epicenterLandmarkName) -or $epicenterPlacement -ne 'center' -or -not $epicenterExclusive) {
    throw 'cellPlanning.multiTileFeatures.epicenter must define an exclusive center placement with a landmark name.'
}
Import-Module (Join-Path $PSScriptRoot 'carpark_endcaps.psm1') -Force
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

function Get-TemplateFootprint {
    param([string]$Template)

    $templateName = [System.IO.Path]::GetFileNameWithoutExtension($Template)
    if ($templateName -match '(?i)_2x(?:2)?$') {
        return [pscustomobject]@{ width = 2; height = 2 }
    }
    if ($templateName -match '(?i)_3x(?:3)?$') {
        return [pscustomobject]@{ width = 3; height = 3 }
    }
    return [pscustomobject]@{ width = 1; height = 1 }
}

function Get-FootprintCoordinates {
    param(
        [int]$TileX,
        [int]$TileY,
        [int]$FootprintWidth,
        [int]$FootprintHeight
    )

    $coordinates = [System.Collections.Generic.List[object]]::new()
    for ($offsetY = 0; $offsetY -lt $FootprintHeight; $offsetY++) {
        for ($offsetX = 0; $offsetX -lt $FootprintWidth; $offsetX++) {
            $coordinates.Add([pscustomobject]@{ tileX = $TileX + $offsetX; tileY = $TileY + $offsetY })
        }
    }
    return @($coordinates)
}

function Get-FootprintAnchorCandidates {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize,
        [int]$FootprintWidth,
        [int]$FootprintHeight,
        [string[]]$AllowedRoles
    )

    if ($FootprintWidth -lt 1 -or $FootprintHeight -lt 1 -or $FootprintWidth -gt $TileGridSize -or $FootprintHeight -gt $TileGridSize) {
        return @()
    }

    $center = [int][Math]::Floor($TileGridSize / 2)
    $candidates = [System.Collections.Generic.List[object]]::new()
    for ($tileY = 0; $tileY -le ($TileGridSize - $FootprintHeight); $tileY++) {
        for ($tileX = 0; $tileX -le ($TileGridSize - $FootprintWidth); $tileX++) {
            $coordinates = @(Get-FootprintCoordinates $tileX $tileY $FootprintWidth $FootprintHeight)
            $available = $true
            foreach ($coordinate in $coordinates) {
                $key = "$($coordinate.tileX),$($coordinate.tileY)"
                if (-not $Placements.ContainsKey($key) -or [string]$Placements[$key].role -notin $AllowedRoles) {
                    $available = $false
                    break
                }
            }
            if (-not $available) { continue }

            $featureCenterX = $tileX + (($FootprintWidth - 1) / 2.0)
            $featureCenterY = $tileY + (($FootprintHeight - 1) / 2.0)
            $candidates.Add([pscustomobject]@{
                tileX = $tileX
                tileY = $tileY
                centerDistance = [Math]::Abs($featureCenterX - $center) + [Math]::Abs($featureCenterY - $center)
                entranceDirection = $null
            })
        }
    }
    return @($candidates | Sort-Object centerDistance, tileY, tileX)
}

function Set-FootprintPlacement {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize,
        [int]$TileX,
        [int]$TileY,
        [int]$FootprintWidth,
        [int]$FootprintHeight,
        [string]$Template,
        [int]$RotationYaw,
        [string]$Role,
        [string]$PlacementId,
        [string[]]$AllowedRoles
    )

    if ($FootprintWidth -lt 1 -or $FootprintHeight -lt 1 -or $FootprintWidth -gt $maximumMultiTileFootprint -or $FootprintHeight -gt $maximumMultiTileFootprint) {
        throw "Footprint for '$Template' must be from 1 through $maximumMultiTileFootprint tiles per axis."
    }
    $coordinates = @(Get-FootprintCoordinates $TileX $TileY $FootprintWidth $FootprintHeight)
    foreach ($coordinate in $coordinates) {
        $key = "$($coordinate.tileX),$($coordinate.tileY)"
        if ($coordinate.tileX -lt 0 -or $coordinate.tileX -ge $TileGridSize -or $coordinate.tileY -lt 0 -or $coordinate.tileY -ge $TileGridSize -or
            -not $Placements.ContainsKey($key) -or [string]$Placements[$key].role -notin $AllowedRoles) {
            throw "Footprint '$PlacementId' cannot reserve tile $key for role '$Role'."
        }
    }

    foreach ($coordinate in $coordinates) {
        $key = "$($coordinate.tileX),$($coordinate.tileY)"
        $isAnchor = $coordinate.tileX -eq $TileX -and $coordinate.tileY -eq $TileY
        $Placements[$key] = [pscustomobject]@{
            tileX = $coordinate.tileX
            tileY = $coordinate.tileY
            template = $Template
            rotationYaw = $RotationYaw
            role = if ($isAnchor) { $Role } else { '{0}_occupied' -f $Role }
            footprintWidth = $FootprintWidth
            footprintHeight = $FootprintHeight
            placementId = $PlacementId
            ownerTileX = $TileX
            ownerTileY = $TileY
            emitsInstance = $isAnchor
        }
    }
}

function Set-TilePlacementDefaults {
    param([object[]]$Placements)

    foreach ($placement in $Placements) {
        $tileX = [int]$placement.tileX
        $tileY = [int]$placement.tileY
        if ($null -eq $placement.PSObject.Properties['footprintWidth']) {
            Add-Member -InputObject $placement -NotePropertyName footprintWidth -NotePropertyValue 1
        }
        if ($null -eq $placement.PSObject.Properties['footprintHeight']) {
            Add-Member -InputObject $placement -NotePropertyName footprintHeight -NotePropertyValue 1
        }
        if ($null -eq $placement.PSObject.Properties['placementId']) {
            Add-Member -InputObject $placement -NotePropertyName placementId -NotePropertyValue "tile:$tileX,$tileY"
        }
        if ($null -eq $placement.PSObject.Properties['ownerTileX']) {
            Add-Member -InputObject $placement -NotePropertyName ownerTileX -NotePropertyValue $tileX
        }
        if ($null -eq $placement.PSObject.Properties['ownerTileY']) {
            Add-Member -InputObject $placement -NotePropertyName ownerTileY -NotePropertyValue $tileY
        }
        if ($null -eq $placement.PSObject.Properties['emitsInstance']) {
            Add-Member -InputObject $placement -NotePropertyName emitsInstance -NotePropertyValue $true
        }
    }
}

function Get-ForcedMultiTileTemplate {
    param(
        [object]$Cell,
        [hashtable]$AvailableTemplates
    )

    $templateProperty = $Cell.PSObject.Properties[$multiTileFixtureTemplateProperty]
    if ($null -eq $templateProperty -or [string]::IsNullOrWhiteSpace([string]$templateProperty.Value)) {
        return $null
    }

    $templateKey = ([string]$templateProperty.Value).Replace('\', '/').ToLowerInvariant()
    if (-not $AvailableTemplates.ContainsKey($templateKey)) {
        throw "Multi-tile fixture template was not found: $($templateProperty.Value)"
    }
    $template = [string]$AvailableTemplates[$templateKey]
    $footprint = Get-TemplateFootprint $template
    if ($footprint.width -eq 1 -and $footprint.height -eq 1) {
        throw "Multi-tile fixture template must end in _2x, _2x2, _3x, or _3x3: $template"
    }
    return $template
}

function Get-SpecialLandmarkSettings {
    param([string[]]$Landmarks)

    foreach ($landmark in @($Landmarks | Sort-Object)) {
        if (-not $specialLandmarkSettings.ContainsKey($landmark)) { continue }
        $settings = $specialLandmarkSettings[$landmark]
        return [pscustomobject]@{
            name = [string]$landmark
            placement = if ($settings.ContainsKey('placement')) { [string]$settings.placement } else { 'road-facing' }
            overwriteRoads = $settings.ContainsKey('overwriteRoads') -and [bool]$settings.overwriteRoads
            capApproachRoads = $settings.ContainsKey('capApproachRoads') -and [bool]$settings.capApproachRoads
        }
    }
    return $null
}

function Set-SpecialLandmarkRoadCaps {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize,
        [int]$TileX,
        [int]$TileY,
        [int]$FootprintWidth,
        [int]$FootprintHeight,
        [string]$Topology,
        [string]$TransportFeature,
        [hashtable]$AvailableTemplates
    )

    $coveredCoordinates = @{}
    foreach ($coordinate in @(Get-FootprintCoordinates $TileX $TileY $FootprintWidth $FootprintHeight)) {
        $coveredCoordinates["$($coordinate.tileX),$($coordinate.tileY)"] = $true
    }
    $roadRoles = @('road', 'road_center', 'onramp_road', 'bridge_road', 'bridge_ramp_deadend', 'motorway_onramp_interchange', 'motorway_onramp_deadend', 'motorway_bridge_deadend', $TransportFeature)
    $roadCapCoordinates = @{}
    foreach ($coordinate in @(Get-FootprintCoordinates $TileX $TileY $FootprintWidth $FootprintHeight)) {
        foreach ($direction in @('N', 'E', 'S', 'W')) {
            $neighbor = Get-OffsetTileCoordinate $coordinate $direction
            if ($null -eq $neighbor) { continue }
            $neighborKey = "$($neighbor.tileX),$($neighbor.tileY)"
            if ($coveredCoordinates.ContainsKey($neighborKey) -or -not $Placements.ContainsKey($neighborKey)) { continue }
            if ([string]$Placements[$neighborKey].role -notin $roadRoles) { continue }
            $roadCapCoordinates[$neighborKey] = [pscustomobject]@{
                tileX = [int]$neighbor.tileX
                tileY = [int]$neighbor.tileY
                directionToLandmark = Get-DirectionToCoordinate $neighbor $coordinate
                role = [string]$Placements[$neighborKey].role
            }
        }
    }

    foreach ($roadCap in $roadCapCoordinates.Values) {
        if ([string]::IsNullOrWhiteSpace($roadCap.directionToLandmark)) { continue }
        $usesMotorwayDeadEnd = $Topology -like 'motorway-*' -or $roadCap.role -like 'motorway*'
        $deadEndTopology = if ($usesMotorwayDeadEnd) { 'motorway-deadend' } else { 'road-deadend' }
        $deadEndTemplate = Resolve-Template @($plannerSettings.topologyTemplates[$deadEndTopology], $plannerSettings.topologyTemplates['road-deadend']) $AvailableTemplates
        $deadEndOrientation = $generatorSettings.directions.names[$roadCap.directionToLandmark]
        $Placements["$($roadCap.tileX),$($roadCap.tileY)"] = [pscustomobject]@{
            tileX = $roadCap.tileX
            tileY = $roadCap.tileY
            template = $deadEndTemplate
            rotationYaw = Get-LayoutRotation $deadEndTopology $deadEndOrientation
            role = 'special_landmark_road_cap'
        }
    }
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

function Get-CarparkCoverageSortKey {
    param([object]$Cell)

    $signature = "$($Cell.x),$($Cell.y)"
    [int64]$seed = 17
    foreach ($character in $signature.ToCharArray()) {
        $seed = (($seed * 31) + [int][char]$character) % 2147483647
    }
    return $seed
}

function Get-CarparkCoveragePlan {
    param([object[]]$MapCells)

    $carparkSettings = $plannerSettings.carparks
    $coverageCellSpan = if ($carparkSettings.ContainsKey('coverageCellSpan')) { [int]$carparkSettings.coverageCellSpan } else { 4 }
    if ($coverageCellSpan -lt 1) { throw 'cellPlanning.carparks.coverageCellSpan must be at least 1.' }
    $coverageCarparksPerRegion = if ($carparkSettings.ContainsKey('coverageCarparksPerRegion')) { [int]$carparkSettings.coverageCarparksPerRegion } else { 1 }
    if ($coverageCarparksPerRegion -lt 1) { throw 'cellPlanning.carparks.coverageCarparksPerRegion must be at least 1.' }
    $minimumCellSeparation = if ($carparkSettings.ContainsKey('minimumCellSeparation')) { [int]$carparkSettings.minimumCellSeparation } else { 1 }
    if ($minimumCellSeparation -lt 1) { throw 'cellPlanning.carparks.minimumCellSeparation must be at least 1.' }

    $eligibleCells = [System.Collections.Generic.List[object]]::new()
    if ($carparkTemplates.Count -gt 0 -and $CellTileSize -ge 5) {
        foreach ($cell in $MapCells) {
            $topology = Get-CellTopology $cell
            $orientation = Get-CellOrientation $cell $topology
            $hasNamedLandmark = @(Get-CellLandmarks $cell | Where-Object { $_ -ne 'none' }).Count -gt 0
            $hasSafeZone = $null -ne $cell.safeZone
            if ($topology -notin @('road-straight', 'road-tjunction', 'road-crossjunction') -or $hasNamedLandmark -or $hasSafeZone) { continue }
            $eligibleCells.Add([pscustomobject]@{
                cell = $cell
                region = ('{0},{1}' -f ([int][Math]::Floor([int]$cell.x / $coverageCellSpan)), ([int][Math]::Floor([int]$cell.y / $coverageCellSpan)))
                sortKey = (Get-CarparkCoverageSortKey $cell)
                topology = $topology
                topologyPriority = if ($topology -eq 'road-straight') { 0 } elseif ($topology -eq 'road-tjunction') { 1 } else { 2 }
            })
        }
    }

    $selectedCells = if ($ForceEligibleCarparks) {
        @($eligibleCells)
    } else {
        $selected = [System.Collections.Generic.List[object]]::new()
        $selectedCoordinates = @{}
        $coverageRegions = @($eligibleCells | Group-Object region | ForEach-Object {
            $regionCell = @($_.Group | Sort-Object sortKey, { $_.cell.y }, { $_.cell.x } | Select-Object -First 1)[0]
            [pscustomobject]@{
                name = $_.Name
                cells = @($_.Group)
                sortKey = Get-CarparkCoverageSortKey $regionCell.cell
            }
        } | Sort-Object sortKey, name)
        for ($selectionRound = 0; $selectionRound -lt $coverageCarparksPerRegion; $selectionRound++) {
            foreach ($coverageRegion in $coverageRegions) {
                $candidates = [System.Collections.Generic.List[object]]::new()
                foreach ($candidate in @($coverageRegion.cells)) {
                    $candidateKey = "$($candidate.cell.x),$($candidate.cell.y)"
                    if ($selectedCoordinates.ContainsKey($candidateKey)) { continue }
                    $nearestDistance = [int]::MaxValue
                    foreach ($existing in $selected) {
                        $distance = [Math]::Max([Math]::Abs([int]$candidate.cell.x - [int]$existing.cell.x), [Math]::Abs([int]$candidate.cell.y - [int]$existing.cell.y))
                        if ($distance -lt $nearestDistance) { $nearestDistance = $distance }
                    }
                    if ($nearestDistance -lt $minimumCellSeparation) { continue }
                    $candidates.Add([pscustomobject]@{ cell = $candidate; nearestDistance = $nearestDistance })
                }
                $selection = @($candidates | Sort-Object { $_.cell.topologyPriority }, @{ Expression = { $_.nearestDistance }; Descending = $true }, { $_.cell.sortKey }, { $_.cell.cell.y }, { $_.cell.cell.x } | Select-Object -First 1)
                if ($selection.Count -eq 0) { continue }
                $selectedCell = $selection[0].cell
                $selected.Add($selectedCell)
                $selectedCoordinates["$($selectedCell.cell.x),$($selectedCell.cell.y)"] = $true
            }
        }
        @($selected)
    }
    $selectedCoordinates = @{}
    foreach ($selectedCell in $selectedCells) {
        $selectedCoordinates["$($selectedCell.cell.x),$($selectedCell.cell.y)"] = $true
    }
    return [pscustomobject]@{
        cellSpan = $coverageCellSpan
        carparksPerRegion = $coverageCarparksPerRegion
        minimumCellSeparation = $minimumCellSeparation
        eligibleCells = @($eligibleCells)
        selectedCells = $selectedCells
        selectedCoordinates = $selectedCoordinates
    }
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

function Get-OffsetTileCoordinate {
    param(
        [object]$Origin,
        [string]$Direction,
        [int]$Distance = 1
    )

    switch ($Direction) {
        'N' { return [pscustomobject]@{ tileX = [int]$Origin.tileX; tileY = [int]$Origin.tileY - $Distance } }
        'E' { return [pscustomobject]@{ tileX = [int]$Origin.tileX + $Distance; tileY = [int]$Origin.tileY } }
        'S' { return [pscustomobject]@{ tileX = [int]$Origin.tileX; tileY = [int]$Origin.tileY + $Distance } }
        'W' { return [pscustomobject]@{ tileX = [int]$Origin.tileX - $Distance; tileY = [int]$Origin.tileY } }
        default { return $null }
    }
}

function Get-DirectionToCoordinate {
    param(
        [object]$Origin,
        [object]$Target
    )

    $deltaX = [int]$Target.tileX - [int]$Origin.tileX
    $deltaY = [int]$Target.tileY - [int]$Origin.tileY
    if ($deltaX -eq 1 -and $deltaY -eq 0) { return 'E' }
    if ($deltaX -eq -1 -and $deltaY -eq 0) { return 'W' }
    if ($deltaX -eq 0 -and $deltaY -eq -1) { return 'N' }
    if ($deltaX -eq 0 -and $deltaY -eq 1) { return 'S' }
    return $null
}

function Get-BuildingEntranceRotation {
    param([string]$EntranceDirection)

    return @{ N = 0; E = 90; S = 180; W = 270 }[$EntranceDirection]
}

function Test-RoadPlacementFacesCoordinate {
    param(
        [object]$RoadPlacement,
        [object]$CandidatePlacement,
        [string[]]$CellConnections,
        [string]$Topology
    )

    $facingDirection = Get-DirectionToCoordinate $RoadPlacement $CandidatePlacement
    if ([string]::IsNullOrWhiteSpace($facingDirection)) { return $false }

    $roadRole = [string]$RoadPlacement.role
    if ($roadRole -eq 'road_center' -and $Topology -like '*-corner') {
        return $facingDirection -in $CellConnections
    }
    return $true
}

function Get-ClosedCornerAvoidanceDirection {
    param(
        [object]$CandidatePlacement,
        [object[]]$RoadCenterPlacements,
        [string[]]$CellConnections,
        [string]$Topology
    )

    if ($Topology -notlike '*-corner') { return $null }
    $closedDirections = [System.Collections.Generic.List[string]]::new()
    foreach ($roadCenterPlacement in $RoadCenterPlacements) {
        $cornerDirection = Get-DirectionToCoordinate $roadCenterPlacement $CandidatePlacement
        if (-not [string]::IsNullOrWhiteSpace($cornerDirection) -and $cornerDirection -notin $CellConnections) {
            $closedDirections.Add($cornerDirection)
        }
    }
    if ($closedDirections.Count -eq 0) { return $null }
    return @($closedDirections | Sort-Object | Select-Object -First 1)[0]
}

function Get-CarparkJunctionRotation {
    param([string]$BranchDirection)

    return @{ N = 0; E = 270; S = 180; W = 90 }[$BranchDirection]
}

function Get-CarparkAssemblyRotation {
    param([string]$BranchDirection)

    return @{ N = 0; E = 270; S = 180; W = 90 }[$BranchDirection]
}

function Get-CarparkLaneRotation {
    param([string]$LaneDirection)

    return Get-DirectionalTileRotation $LaneDirection
}

function Get-PlacementVariationRoll {
    param([int]$PlacementSeed)

    $seed = [int64][Math]::Abs([int64]$PlacementSeed)
    $mixedSeed = $seed -bxor ($seed -shr 13) -bxor ($seed -shr 23)
    return [int]($mixedSeed % 100)
}

function Get-CarparkVariationRoll {
    param(
        [int]$PlacementSeed,
        [int]$Salt
    )

    $seed = [int64][Math]::Abs([int64]$PlacementSeed)
    $mixedSeed = $seed -bxor ([int64]$Salt * 1103515245)
    $mixedSeed = $mixedSeed -bxor ($mixedSeed -shr 13) -bxor ($mixedSeed -shr 23)
    return [int]([Math]::Abs([int64]$mixedSeed) % 100)
}

function Get-CarparkTemplateSet {
    param([string[]]$CarparkTemplates)

    $templateSet = [ordered]@{}
    $entranceTemplates = @($CarparkTemplates | Where-Object { (Split-Path -Leaf $_) -match '^tile_carpark_entrance.*\.vmf$' } | Sort-Object)
    $throughEntranceTemplates = @($entranceTemplates | Where-Object { (Split-Path -Leaf $_) -notmatch '^tile_carpark_entrance_deadend(?:_(?:east|west))?\.vmf$' })
    if ($throughEntranceTemplates.Count -eq 0) {
        return $null
    }
    $templateSet['throughEntrances'] = $throughEntranceTemplates
    $templateSet['entranceDeadend'] = [string]($entranceTemplates | Where-Object { (Split-Path -Leaf $_) -ieq 'tile_carpark_entrance_deadend.vmf' } | Select-Object -First 1)
    $templateSet['entranceDeadendEast'] = [string]($entranceTemplates | Where-Object { (Split-Path -Leaf $_) -ieq 'tile_carpark_entrance_deadend_east.vmf' } | Select-Object -First 1)
    $templateSet['entranceDeadendWest'] = [string]($entranceTemplates | Where-Object { (Split-Path -Leaf $_) -ieq 'tile_carpark_entrance_deadend_west.vmf' } | Select-Object -First 1)
    foreach ($templateKey in @('straightEast', 'straightWest', 'deadendEast', 'deadendWest')) {
        $template = [string]$plannerSettings.carparks.templates[$templateKey]
        if ([string]::IsNullOrWhiteSpace($template) -or $CarparkTemplates -notcontains $template) {
            return $null
        }
        $templateSet[$templateKey] = $template
    }
    return $templateSet
}

function Get-CarparkEntranceLayout {
    param(
        [object]$CarparkTemplateSet,
        [int]$PlacementSeed,
        [string]$BranchDirection,
        [string[]]$RequiredOpenLaneKeys = @(),
        [bool]$RequireThroughLayout = $false
    )

    $entranceLayouts = [System.Collections.Generic.List[object]]::new()
    $carparkYaw = Get-CarparkAssemblyRotation $BranchDirection
    $localEastDirection = @{ N = 'E'; E = 'S'; S = 'W'; W = 'N' }[$BranchDirection]
    foreach ($template in @($CarparkTemplateSet['throughEntrances'])) {
        $entranceLayouts.Add([pscustomobject]@{
            template = [string]$template
            openLaneKeys = @('east', 'west')
            rotationYaw = $carparkYaw
        })
    }
    if (-not $RequireThroughLayout) {
        foreach ($oneSidedLayout in @(
            [pscustomobject]@{ closedLaneKey = 'east'; openLaneKey = 'west' },
            [pscustomobject]@{ closedLaneKey = 'west'; openLaneKey = 'east' }
        )) {
            if ($RequiredOpenLaneKeys -contains $oneSidedLayout.closedLaneKey) { continue }
            $entranceDefinition = Get-CarparkOneSidedEntranceDefinition $oneSidedLayout.closedLaneKey $carparkYaw
            if ($null -eq $entranceDefinition) { continue }
            $entranceTemplate = [string]$CarparkTemplateSet[$entranceDefinition.templateKey]
            if ([string]::IsNullOrWhiteSpace($entranceTemplate)) { continue }
            $entranceLayouts.Add([pscustomobject]@{
                template = $entranceTemplate
                openLaneKeys = @($oneSidedLayout.openLaneKey)
                rotationYaw = [int]$entranceDefinition.rotationYaw
            })
        }
        if ($RequiredOpenLaneKeys.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$CarparkTemplateSet['entranceDeadend'])) {
            $entranceLayouts.Add([pscustomobject]@{
                template = [string]$CarparkTemplateSet['entranceDeadend']
                openLaneKeys = @()
                rotationYaw = $carparkYaw
            })
        }
    }
    if ($entranceLayouts.Count -eq 0) {
        throw 'Carpark template set has no entrance layout that supports the requested lanes.'
    }
    $layoutIndex = (Get-CarparkVariationRoll $PlacementSeed 41) % $entranceLayouts.Count
    return $entranceLayouts[$layoutIndex]
}

function Get-CarparkLaneLength {
    param(
        [object]$CarparkSettings,
        [int]$PlacementSeed,
        [int]$MaximumAvailableTiles
    )

    $minimumLaneTiles = if ($ForceEligibleCarparks) { 1 } elseif ($CarparkSettings.ContainsKey('minimumLaneTiles')) { [int]$CarparkSettings.minimumLaneTiles } else { $MaximumAvailableTiles }
    $maximumLaneTiles = if ($CarparkSettings.ContainsKey('maximumLaneTiles')) { [int]$CarparkSettings.maximumLaneTiles } else { $MaximumAvailableTiles }
    if ($minimumLaneTiles -lt 1 -or $maximumLaneTiles -lt $minimumLaneTiles -or $maximumLaneTiles -gt $MaximumAvailableTiles) {
        throw "cellPlanning.carparks lane tile range must be between 1 and $MaximumAvailableTiles."
    }
    $laneRange = $maximumLaneTiles - $minimumLaneTiles + 1
    $laneOffset = [int][Math]::Floor(((Get-CarparkVariationRoll $PlacementSeed 73) * $laneRange) / 100)
    return $minimumLaneTiles + $laneOffset
}

function Get-JunctionCarparkAccess {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize
    )

    $maximumLaneTiles = 1
    $validRoles = @('building', 'terrain', 'decoration')
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($roadPlacement in @($Placements.Values | Where-Object { $_.role -eq 'road' })) {
        $roadAxisIsVertical = ([int]$roadPlacement.rotationYaw % 180) -eq 0
        $branchDirections = if ($roadAxisIsVertical) { @('E', 'W') } else { @('N', 'S') }
        foreach ($branchDirection in $branchDirections) {
            $entranceCoordinate = Get-OffsetTileCoordinate $roadPlacement $branchDirection
            $localEastDirection = @{ N = 'E'; E = 'S'; S = 'W'; W = 'N' }[$branchDirection]
            foreach ($lane in @(
                [pscustomobject]@{ key = 'east'; direction = $localEastDirection },
                [pscustomobject]@{ key = 'west'; direction = (Get-OppositeDirection $localEastDirection) }
            )) {
                $laneCoordinates = @(1..$maximumLaneTiles | ForEach-Object { Get-OffsetTileCoordinate $entranceCoordinate $lane.direction $_ })
                $terminalCoordinate = Get-OffsetTileCoordinate $entranceCoordinate $lane.direction ($maximumLaneTiles + 1)
                $requiredCoordinates = @($entranceCoordinate) + $laneCoordinates
                $requiredKeys = @($requiredCoordinates | ForEach-Object { "$($_.tileX),$($_.tileY)" })
                if (@($requiredKeys | Where-Object { -not $Placements.ContainsKey($_) -or $Placements[$_].role -notin $validRoles }).Count -gt 0) { continue }
                $terminalKey = "$($terminalCoordinate.tileX),$($terminalCoordinate.tileY)"
                if ($Placements.ContainsKey($terminalKey) -and $Placements[$terminalKey].role -notin $validRoles) { continue }
                $candidates.Add([pscustomobject]@{
                    road = $roadPlacement
                    branchDirection = $branchDirection
                    entrance = $entranceCoordinate
                    lane = $lane
                    terminal = $terminalCoordinate
                    terminalInGrid = $Placements.ContainsKey($terminalKey)
                    maximumLaneTiles = $maximumLaneTiles
                })
            }
        }
    }
    $candidate = @($candidates | Sort-Object { $_.road.tileY }, { $_.road.tileX }, branchDirection, { $_.lane.key } | Select-Object -First 1)
    if ($candidate.Count -eq 0) { return $null }
    return $candidate[0]
}

function Get-FootprintRoadFacingCandidates {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize,
        [int]$FootprintWidth,
        [int]$FootprintHeight,
        [object[]]$RoadPlacements,
        [string[]]$CellConnections,
        [string]$Topology,
        [string[]]$AllowedRoles
    )

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($anchor in @(Get-FootprintAnchorCandidates $Placements $TileGridSize $FootprintWidth $FootprintHeight $AllowedRoles)) {
        foreach ($footprintCoordinate in @(Get-FootprintCoordinates $anchor.tileX $anchor.tileY $FootprintWidth $FootprintHeight)) {
            foreach ($roadPlacement in $RoadPlacements) {
                $distance = [Math]::Abs([int]$footprintCoordinate.tileX - [int]$roadPlacement.tileX) + [Math]::Abs([int]$footprintCoordinate.tileY - [int]$roadPlacement.tileY)
                if ($distance -ne 1 -or -not (Test-RoadPlacementFacesCoordinate $roadPlacement $footprintCoordinate $CellConnections $Topology)) { continue }
                $candidates.Add([pscustomobject]@{
                    tileX = [int]$anchor.tileX
                    tileY = [int]$anchor.tileY
                    centerDistance = [double]$anchor.centerDistance
                    entranceDirection = Get-DirectionToCoordinate $footprintCoordinate $roadPlacement
                })
            }
        }
    }
    return @($candidates | Sort-Object centerDistance, tileY, tileX, entranceDirection)
}

function Test-CommercialFootprintHasRequiredFrontage {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize,
        [int]$TileX,
        [int]$TileY,
        [int]$FootprintWidth,
        [int]$FootprintHeight
    )

    if ($TileX -eq 0 -or $TileY -eq 0 -or ($TileX + $FootprintWidth) -eq $TileGridSize -or ($TileY + $FootprintHeight) -eq $TileGridSize) {
        return $true
    }
    foreach ($coordinate in @(Get-FootprintCoordinates $TileX $TileY $FootprintWidth $FootprintHeight)) {
        foreach ($direction in @('N', 'E', 'S', 'W')) {
            $neighbor = Get-OffsetTileCoordinate $coordinate $direction
            $neighborKey = "$($neighbor.tileX),$($neighbor.tileY)"
            if ($Placements.ContainsKey($neighborKey) -and [string]$Placements[$neighborKey].role -like '*carpark*') {
                return $true
            }
        }
    }
    return $false
}

function Get-CommercialAccessPlan {
    param(
        [hashtable]$Placements,
        [int]$TileGridSize,
        [int]$TileX,
        [int]$TileY,
        [int]$FootprintWidth,
        [int]$FootprintHeight
    )

    $roadRoles = @('road', 'road_center', 'onramp_road', 'bridge_road', 'bridge_ramp_deadend', 'special_landmark_road_cap')
    $footprintKeys = @{}
    foreach ($coordinate in @(Get-FootprintCoordinates $TileX $TileY $FootprintWidth $FootprintHeight)) {
        $footprintKeys["$($coordinate.tileX),$($coordinate.tileY)"] = $true
    }

    $queue = [System.Collections.Queue]::new()
    $visited = @{}
    $previous = @{}
    $coordinates = @{}
    foreach ($coordinate in @(Get-FootprintCoordinates $TileX $TileY $FootprintWidth $FootprintHeight)) {
        foreach ($direction in @('N', 'E', 'S', 'W')) {
            $neighbor = Get-OffsetTileCoordinate $coordinate $direction
            $neighborKey = "$($neighbor.tileX),$($neighbor.tileY)"
            if (-not $Placements.ContainsKey($neighborKey) -or $footprintKeys.ContainsKey($neighborKey)) { continue }
            $neighborRole = [string]$Placements[$neighborKey].role
            if ($neighborRole -in $roadRoles -or $neighborRole -like '*carpark*') {
                return [pscustomobject]@{ path = @() }
            }
            if ($neighborRole -notin @('terrain', 'decoration') -or $visited.ContainsKey($neighborKey)) { continue }
            $visited[$neighborKey] = $true
            $previous[$neighborKey] = ''
            $coordinates[$neighborKey] = $neighbor
            $queue.Enqueue($neighborKey)
        }
    }

    while ($queue.Count -gt 0) {
        $currentKey = [string]$queue.Dequeue()
        $current = $coordinates[$currentKey]
        foreach ($direction in @('N', 'E', 'S', 'W')) {
            $neighbor = Get-OffsetTileCoordinate $current $direction
            $neighborKey = "$($neighbor.tileX),$($neighbor.tileY)"
            if (-not $Placements.ContainsKey($neighborKey) -or $footprintKeys.ContainsKey($neighborKey)) { continue }
            $neighborRole = [string]$Placements[$neighborKey].role
            if ($neighborRole -in $roadRoles) {
                $path = [System.Collections.Generic.List[object]]::new()
                $pathKey = $currentKey
                while (-not [string]::IsNullOrWhiteSpace($pathKey)) {
                    $path.Add($coordinates[$pathKey])
                    $pathKey = [string]$previous[$pathKey]
                }
                $pathCoordinates = $path.ToArray()
                [array]::Reverse($pathCoordinates)
                return [pscustomobject]@{ path = @($pathCoordinates) }
            }
            if ($neighborRole -notin @('terrain', 'decoration') -or $visited.ContainsKey($neighborKey)) { continue }
            $visited[$neighborKey] = $true
            $previous[$neighborKey] = $currentKey
            $coordinates[$neighborKey] = $neighbor
            $queue.Enqueue($neighborKey)
        }
    }
    return $null
}

function Set-CommercialAccessPath {
    param(
        [hashtable]$Placements,
        [object]$AccessPlan,
        [string]$PathTemplate
    )

    $path = @($AccessPlan.path)
    for ($pathIndex = 0; $pathIndex -lt $path.Count; $pathIndex++) {
        $coordinate = $path[$pathIndex]
        $nextCoordinate = if ($pathIndex -lt ($path.Count - 1)) { $path[$pathIndex + 1] } else { $null }
        $direction = if ($null -eq $nextCoordinate) { $null } else { Get-DirectionToCoordinate $coordinate $nextCoordinate }
        $Placements["$($coordinate.tileX),$($coordinate.tileY)"] = [pscustomobject]@{
            tileX = [int]$coordinate.tileX
            tileY = [int]$coordinate.tileY
            template = $PathTemplate
            rotationYaw = if ([string]::IsNullOrWhiteSpace($direction)) { 0 } else { Get-DirectionalTileRotation $direction }
            role = 'path'
        }
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
        [hashtable]$AvailableTemplates,
        [bool]$ForceCarpark
    )

    $center = [int][Math]::Floor($TileGridSize / 2)
    $placements = @{}
    $concretePathTemplate = Resolve-Template @('roads/tile_concrete_path.vmf') $AvailableTemplates
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
        $usesMotorwayCornerOnrampInterchange = $Topology -eq 'motorway-corner' -and $TransportFeature -like 'onramp-*'
        $centerCandidates = if ($usesMotorwayCornerOnrampInterchange) {
            @($plannerSettings.topologyTemplates['motorway-crossjunction'], (Get-GenericTopologyTemplate $Topology), (Get-LinearTopologyTemplate $Topology), $TerrainTemplate)
        } else {
            @($transportTemplate, (Get-GenericTopologyTemplate $Topology), (Get-LinearTopologyTemplate $Topology), $TerrainTemplate)
        }
        $centerTemplate = Resolve-Template $centerCandidates $AvailableTemplates
        $placements["$center,$center"] = [pscustomobject]@{
            tileX = $center
            tileY = $center
            template = $centerTemplate
            rotationYaw = if ($usesMotorwayCornerOnrampInterchange) { 0 } elseif ($Topology -eq 'motorway-deadend' -and $null -eq $transportTemplate) { Get-MotorwayDeadEndRotation $Orientation } elseif ($null -eq $transportTemplate) { Get-LayoutRotation $Topology $Orientation } else { Get-TransportFeatureRotation $TransportFeature }
            role = if ($usesMotorwayCornerOnrampInterchange) { 'motorway_onramp_interchange' } elseif ($null -eq $transportTemplate) { 'road_center' } else { $TransportFeature }
        }

        if ($usesMotorwayCornerOnrampInterchange) {
            $activeDirections = @((@($connections) + @(Get-HighwayRampExits $Cell)) | Sort-Object -Unique)
            $closedDirections = @($generatorSettings.directions.cardinal | Where-Object { $_ -notin $activeDirections })
            if ($closedDirections.Count -ne 1) {
                throw "Motorway corner onramp '$($Cell.x),$($Cell.y)' requires exactly one closed motorway arm; found $($closedDirections.Count)."
            }
            $closedDirection = $closedDirections[0]
            $deadEndCoordinate = Get-DirectionalAdjacentCoordinate $closedDirection $center
            $deadEndTemplate = Resolve-Template @($plannerSettings.topologyTemplates['motorway-deadend'], $plannerSettings.topologyTemplates['motorway-straight'], $TerrainTemplate) $AvailableTemplates
            $closedOrientation = @{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }[$closedDirection]
            $deadEndRotation = Get-MotorwayDeadEndRotation $closedOrientation
            $placements["$($deadEndCoordinate.tileX),$($deadEndCoordinate.tileY)"] = [pscustomobject]@{
                tileX = $deadEndCoordinate.tileX
                tileY = $deadEndCoordinate.tileY
                template = $deadEndTemplate
                rotationYaw = ($deadEndRotation + 180) % 360
                role = 'motorway_onramp_deadend'
            }
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
            $bridgeRampDeadEndTemplate = Resolve-Template @($plannerSettings.transportTemplates.roadDeadEnd, $plannerSettings.topologyTemplates['road-deadend'], $bridgeRoadTemplate, $TerrainTemplate) $AvailableTemplates
            $ordinaryApproachDirection = @{ N = 'E'; E = 'S'; S = 'W'; W = 'N' }[$bridgeDirection]
            $bridgeRampDeadEndCoordinate = Get-DirectionalAdjacentCoordinate $ordinaryApproachDirection $center
            $bridgeRampDeadEndDirection = $ordinaryApproachDirection
            $bridgeRampDeadEndOrientation = $generatorSettings.directions.names[$bridgeRampDeadEndDirection]
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
            $placements["$($bridgeRampDeadEndCoordinate.tileX),$($bridgeRampDeadEndCoordinate.tileY)"] = [pscustomobject]@{
                tileX = $bridgeRampDeadEndCoordinate.tileX
                tileY = $bridgeRampDeadEndCoordinate.tileY
                template = $bridgeRampDeadEndTemplate
                rotationYaw = Get-LayoutRotation 'road-deadend' $bridgeRampDeadEndOrientation
                role = 'road'
            }
        }
    }

    $roadCenterPlacements = @($placements.Values | Where-Object { $_.role -eq 'road_center' })
    $hasNamedLandmark = @($Landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0
    $forcedMultiTileTemplate = Get-ForcedMultiTileTemplate $Cell $AvailableTemplates
    $singleTileBuildingTemplates = @($BuildingTemplates | Where-Object {
        $footprint = Get-TemplateFootprint $_
        $footprint.width -eq 1 -and $footprint.height -eq 1
    })
    if ($singleTileBuildingTemplates.Count -gt 0) {
        $buildingDensity = Get-BuildingDensity $Cell.environment.terrain $Profile
        $weightedBuildingTemplates = @(Get-BuildingTemplatesForDensity $singleTileBuildingTemplates $BuildingDensityTier)
        $preferDecorations = $Cell.environment.terrain -in $plannerSettings.decorations.preferredTerrains -or $Profile -in $plannerSettings.decorations.preferredProfiles
        foreach ($terrainPlacement in @($placements.Values | Where-Object { $_.role -eq 'terrain' } | Sort-Object tileY, tileX)) {
            $terrainPlacementKey = "$($terrainPlacement.tileX),$($terrainPlacement.tileY)"
            if (-not $placements.ContainsKey($terrainPlacementKey) -or [string]$placements[$terrainPlacementKey].role -ne 'terrain') { continue }
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
            $selectedBuildingTemplate = $weightedBuildingTemplates[$templateIndex]
            $commercialAccessPlan = $null
            if ($commercialTemplates -contains $selectedBuildingTemplate) {
                $commercialAccessPlan = if (Test-CommercialFootprintHasRequiredFrontage $placements $TileGridSize ([int]$terrainPlacement.tileX) ([int]$terrainPlacement.tileY) 1 1) {
                    Get-CommercialAccessPlan $placements $TileGridSize ([int]$terrainPlacement.tileX) ([int]$terrainPlacement.tileY) 1 1
                } else { $null }
                if ($null -eq $commercialAccessPlan) {
                    $nonCommercialTemplates = @($weightedBuildingTemplates | Where-Object { $_ -notin $commercialTemplates })
                    if ($nonCommercialTemplates.Count -eq 0) { continue }
                    $selectedBuildingTemplate = $nonCommercialTemplates[[Math]::Abs($templateIndex) % $nonCommercialTemplates.Count]
                }
            }
            $adjacentRoadPlacement = $placements.Values | Where-Object {
                $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road', $TransportFeature) -and
                ([Math]::Abs([int]$terrainPlacement.tileX - [int]$_.tileX) + [Math]::Abs([int]$terrainPlacement.tileY - [int]$_.tileY)) -eq 1 -and
                (Test-RoadPlacementFacesCoordinate $_ $terrainPlacement $connections $Topology)
            } | Sort-Object tileY, tileX | Select-Object -First 1
            $entranceDirection = if ($null -eq $adjacentRoadPlacement) {
                Get-ClosedCornerAvoidanceDirection $terrainPlacement $roadCenterPlacements $connections $Topology
            } else {
                Get-DirectionToCoordinate $terrainPlacement $adjacentRoadPlacement
            }
            $placements["$($terrainPlacement.tileX),$($terrainPlacement.tileY)"] = [pscustomobject]@{
                tileX = $terrainPlacement.tileX
                tileY = $terrainPlacement.tileY
                template = $selectedBuildingTemplate
                rotationYaw = if ($null -eq $entranceDirection) { 0 } else { Get-BuildingEntranceRotation $entranceDirection }
                role = 'building'
            }
            if ($null -ne $commercialAccessPlan) {
                Set-CommercialAccessPath $placements $commercialAccessPlan $concretePathTemplate
            }
        }
    }

    $usesForcedLandmarkTemplate = $hasNamedLandmark -and -not [string]::IsNullOrWhiteSpace($forcedMultiTileTemplate)
    $resolvedLandmarkTemplate = if ($usesForcedLandmarkTemplate) { $forcedMultiTileTemplate } else { $LandmarkTemplate }
    $landmarkPlacedAsMacro = $false
    if (-not [string]::IsNullOrWhiteSpace($resolvedLandmarkTemplate)) {
        $landmarkFootprint = Get-TemplateFootprint $resolvedLandmarkTemplate
        if ($landmarkFootprint.width -gt 1 -or $landmarkFootprint.height -gt 1) {
            $specialLandmark = Get-SpecialLandmarkSettings $Landmarks
            $macroAllowedRoles = @('building', 'terrain', 'decoration')
            $macroRoadPlacements = @($placements.Values | Where-Object { $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road', $TransportFeature) } | Sort-Object tileY, tileX)
            $isEpicenter = $Landmarks -contains $epicenterLandmarkName
            if ($null -ne $specialLandmark -and $specialLandmark.overwriteRoads) {
                $macroAllowedRoles = @($macroAllowedRoles + @('road', 'road_center', 'onramp_road', 'bridge_road', 'bridge_ramp_deadend', 'motorway_onramp_interchange', 'motorway_onramp_deadend', 'motorway_bridge_deadend', $TransportFeature) | Sort-Object -Unique)
            }
            if ($isEpicenter -and ($landmarkFootprint.width -ne 3 -or $landmarkFootprint.height -ne 3)) {
                throw "Epicenter template '$resolvedLandmarkTemplate' must have a 3x3 footprint."
            }
            if ($isEpicenter -and $macroRoadPlacements.Count -gt 0 -and ($null -eq $specialLandmark -or -not $specialLandmark.overwriteRoads)) {
                throw "The Epicenter at $($Cell.x),$($Cell.y) needs specialLandmarks.$epicenterLandmarkName.overwriteRoads to replace its road footprint."
            }

            $usesCenteredPlacement = $isEpicenter -or ($null -ne $specialLandmark -and $specialLandmark.placement -eq 'center')
            $macroCandidates = if ($usesCenteredPlacement) {
                $centeredTileX = $center - [int][Math]::Floor($landmarkFootprint.width / 2)
                $centeredTileY = $center - [int][Math]::Floor($landmarkFootprint.height / 2)
                @(Get-FootprintAnchorCandidates $placements $TileGridSize $landmarkFootprint.width $landmarkFootprint.height $macroAllowedRoles |
                    Where-Object { $_.tileX -eq $centeredTileX -and $_.tileY -eq $centeredTileY })
            } elseif ($macroRoadPlacements.Count -gt 0) {
                @(Get-FootprintRoadFacingCandidates $placements $TileGridSize $landmarkFootprint.width $landmarkFootprint.height $macroRoadPlacements $connections $Topology $macroAllowedRoles)
            } else {
                @(Get-FootprintAnchorCandidates $placements $TileGridSize $landmarkFootprint.width $landmarkFootprint.height $macroAllowedRoles)
            }
            $macroPlacement = @($macroCandidates | Select-Object -First 1)[0]
            if ($null -eq $macroPlacement) {
                $source = if ($usesForcedLandmarkTemplate) { 'Forced multi-tile landmark' } else { 'Multi-tile landmark' }
                throw "$source '$resolvedLandmarkTemplate' has no compatible footprint at $($Cell.x),$($Cell.y)."
            }

            $macroRole = if ($isEpicenter) { 'landmark_epicenter' } else { 'landmark' }
            $macroRotationYaw = if ($isEpicenter -or [string]::IsNullOrWhiteSpace([string]$macroPlacement.entranceDirection)) { 0 } else { Get-BuildingEntranceRotation $macroPlacement.entranceDirection }
            $placementId = "${macroRole}:$($macroPlacement.tileX),$($macroPlacement.tileY)"
            Set-FootprintPlacement $placements $TileGridSize $macroPlacement.tileX $macroPlacement.tileY $landmarkFootprint.width $landmarkFootprint.height $resolvedLandmarkTemplate $macroRotationYaw $macroRole $placementId $macroAllowedRoles
            if ($null -ne $specialLandmark -and $specialLandmark.capApproachRoads) {
                Set-SpecialLandmarkRoadCaps $placements $TileGridSize $macroPlacement.tileX $macroPlacement.tileY $landmarkFootprint.width $landmarkFootprint.height $Topology $TransportFeature $AvailableTemplates
            }
            $landmarkPlacedAsMacro = $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedLandmarkTemplate) -and -not $landmarkPlacedAsMacro) {
        $landmarkCandidates = @($placements.Values | Where-Object { $_.role -in @('building', 'terrain') } | Sort-Object tileY, tileX)
        $roadPlacements = @($placements.Values | Where-Object { $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road', $TransportFeature) } | Sort-Object tileY, tileX)
        $carparkTemplateSet = Get-CarparkTemplateSet $CarparkTemplates
        $landmarkPlacement = $null
        $landmarkEntranceDirection = $null
        $carparkAccess = $null
        if ($roadPlacements.Count -gt 0) {
            $roadFacingCandidates = foreach ($candidate in $landmarkCandidates) {
                foreach ($roadPlacement in $roadPlacements) {
                    $distance = [Math]::Abs([int]$candidate.tileX - [int]$roadPlacement.tileX) + [Math]::Abs([int]$candidate.tileY - [int]$roadPlacement.tileY)
                    if ($distance -eq 1 -and (Test-RoadPlacementFacesCoordinate $roadPlacement $candidate $connections $Topology)) {
                        [pscustomobject]@{
                            placement = $candidate
                            entranceDirection = Get-DirectionToCoordinate $candidate $roadPlacement
                        }
                    }
                }
            }
            $roadFacingCandidate = @($roadFacingCandidates | Sort-Object { $_.placement.tileY }, { $_.placement.tileX }, entranceDirection | Select-Object -First 1)
            $roadFacingCandidate = if ($roadFacingCandidate.Count -eq 0) { $null } else { $roadFacingCandidate[0] }
            if ($null -ne $roadFacingCandidate) {
                $landmarkPlacement = $roadFacingCandidate.placement
                $landmarkEntranceDirection = $roadFacingCandidate.entranceDirection
            }
        }
        if ($null -eq $landmarkPlacement -and $null -ne $carparkTemplateSet) {
            $carparkAccessCandidates = foreach ($roadPlacement in @($roadPlacements | Where-Object { $_.role -eq 'road' })) {
                $roadAxisIsVertical = ([int]$roadPlacement.rotationYaw % 180) -eq 0
                $branchDirections = if ($roadAxisIsVertical) { @('E', 'W') } else { @('N', 'S') }
                foreach ($branchDirection in $branchDirections) {
                    $entranceCoordinate = Get-OffsetTileCoordinate $roadPlacement $branchDirection
                    $localEastDirection = @{ N = 'E'; E = 'S'; S = 'W'; W = 'N' }[$branchDirection]
                    foreach ($localLaneDirection in @($localEastDirection, (Get-OppositeDirection $localEastDirection))) {
                        $laneCoordinate = Get-OffsetTileCoordinate $entranceCoordinate $localLaneDirection
                        $landmarkCoordinate = Get-OffsetTileCoordinate $entranceCoordinate $localLaneDirection 2
                        $accessCoordinates = @($entranceCoordinate, $laneCoordinate, $landmarkCoordinate)
                        if (@($accessCoordinates | Where-Object { $null -eq $_ }).Count -gt 0) { continue }
                        $accessKeys = @($accessCoordinates | ForEach-Object { "$($_.tileX),$($_.tileY)" })
                        if (@($accessKeys | Where-Object { -not $placements.ContainsKey($_) }).Count -gt 0) { continue }
                        if (@($accessKeys | Where-Object { $placements[$_].role -notin @('building', 'terrain', 'decoration') }).Count -gt 0) { continue }
                        [pscustomobject]@{
                            road = $roadPlacement
                            branchDirection = $branchDirection
                            entrance = $entranceCoordinate
                            lane = $laneCoordinate
                            landmark = $landmarkCoordinate
                            localLaneDirection = $localLaneDirection
                            localEastDirection = $localEastDirection
                        }
                    }
                }
            }
            $carparkAccess = @($carparkAccessCandidates | Sort-Object { $_.road.tileY }, { $_.road.tileX }, branchDirection, localLaneDirection | Select-Object -First 1)
            $carparkAccess = if ($carparkAccess.Count -eq 0) { $null } else { $carparkAccess[0] }
            if ($null -ne $carparkAccess) {
                $landmarkPlacement = $carparkAccess.landmark
                $landmarkEntranceDirection = Get-OppositeDirection $carparkAccess.localLaneDirection
            }
        }
        if ($null -eq $landmarkPlacement) {
            $landmarkPlacement = @($landmarkCandidates | Select-Object -First 1)[0]
            $landmarkEntranceDirection = Get-ClosedCornerAvoidanceDirection $landmarkPlacement $roadCenterPlacements $connections $Topology
        }
        if ($null -ne $landmarkPlacement) {
            $placements["$($landmarkPlacement.tileX),$($landmarkPlacement.tileY)"] = [pscustomobject]@{
                tileX = $landmarkPlacement.tileX
                tileY = $landmarkPlacement.tileY
                template = $resolvedLandmarkTemplate
                rotationYaw = if ($null -eq $landmarkEntranceDirection) { 0 } else { Get-BuildingEntranceRotation $landmarkEntranceDirection }
                role = 'landmark'
            }
        }
        if ($null -ne $carparkAccess) {
            $laneRotation = Get-CarparkLaneRotation $carparkAccess.localLaneDirection
            $requiredLaneKey = if ($carparkAccess.localLaneDirection -eq $carparkAccess.localEastDirection) { 'east' } else { 'west' }
            $carparkEntranceLayout = Get-CarparkEntranceLayout $carparkTemplateSet $PlacementSeed $carparkAccess.branchDirection @($requiredLaneKey)
            $roadTjunctionTemplate = Resolve-Template @($plannerSettings.topologyTemplates['road-tjunction'], $plannerSettings.topologyTemplates['road-straight'], $TerrainTemplate) $AvailableTemplates
            $laneTemplate = if ($carparkAccess.localLaneDirection -eq $carparkAccess.localEastDirection) { $carparkTemplateSet.straightEast } else { $carparkTemplateSet.straightWest }
            $laneRole = if ($carparkAccess.localLaneDirection -eq $carparkAccess.localEastDirection) { 'landmark_carpark_lane_east' } else { 'landmark_carpark_lane_west' }
            $placements["$($carparkAccess.road.tileX),$($carparkAccess.road.tileY)"] = [pscustomobject]@{
                tileX = $carparkAccess.road.tileX
                tileY = $carparkAccess.road.tileY
                template = $roadTjunctionTemplate
                rotationYaw = Get-CarparkJunctionRotation $carparkAccess.branchDirection
                role = 'landmark_carpark_junction'
            }
            $placements["$($carparkAccess.entrance.tileX),$($carparkAccess.entrance.tileY)"] = [pscustomobject]@{
                tileX = $carparkAccess.entrance.tileX
                tileY = $carparkAccess.entrance.tileY
                template = $carparkEntranceLayout.template
                rotationYaw = $carparkEntranceLayout.rotationYaw
                role = 'landmark_carpark_entrance'
            }
            $placements["$($carparkAccess.lane.tileX),$($carparkAccess.lane.tileY)"] = [pscustomobject]@{
                tileX = $carparkAccess.lane.tileX
                tileY = $carparkAccess.lane.tileY
                template = $laneTemplate
                rotationYaw = $laneRotation
                role = $laneRole
            }
        }
    }

    $hasNamedLandmark = @($Landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0
    $carparkTemplateSet = Get-CarparkTemplateSet $CarparkTemplates
    $carparkRoll = Get-PlacementVariationRoll $PlacementSeed
    if ($Topology -eq 'road-straight' -and $Orientation -in @('vertical', 'horizontal') -and $TileGridSize -ge 5 -and -not $hasNamedLandmark -and $null -ne $carparkTemplateSet -and ($ForceCarpark -or $carparkRoll -lt [int]$plannerSettings.carparks.roadStraightChancePercent)) {
        $branchDirections = if ($Orientation -eq 'vertical') { @('E', 'W') } else { @('N', 'S') }
        $branchDirection = $branchDirections[[Math]::Abs($PlacementSeed) % $branchDirections.Count]
        $entranceCoordinate = Get-DirectionalAdjacentCoordinate $branchDirection $center
        $carparkEntranceLayout = Get-CarparkEntranceLayout -CarparkTemplateSet $carparkTemplateSet -PlacementSeed $PlacementSeed -BranchDirection $branchDirection -RequiredOpenLaneKeys @() -RequireThroughLayout ($ForceCarpark -and -not $ForceEligibleCarparks)
        $carparkLaneLength = Get-CarparkLaneLength $plannerSettings.carparks $PlacementSeed $center
        $localEastDirection = @{ N = 'E'; E = 'S'; S = 'W'; W = 'N' }[$branchDirection]
        $localWestDirection = Get-OppositeDirection $localEastDirection
        $roadTjunctionTemplate = Resolve-Template @($plannerSettings.topologyTemplates['road-tjunction'], $plannerSettings.topologyTemplates['road-straight'], $TerrainTemplate) $AvailableTemplates
        $placements["$center,$center"] = [pscustomobject]@{
            tileX = $center
            tileY = $center
            template = $roadTjunctionTemplate
            rotationYaw = Get-CarparkJunctionRotation $branchDirection
            role = 'carpark_road_junction'
        }
        if ($TransportFeature -like 'bridge-ramp-*') {
            $bridgeDirection = $TransportFeature.Substring('bridge-ramp-'.Length, 1).ToUpperInvariant()
            $bridgeRampCoordinate = Get-DirectionalAdjacentCoordinate $bridgeDirection $center
            $bridgeRampTemplate = Resolve-Template @((Get-TransportFeatureTemplate $TransportFeature), $plannerSettings.transportTemplates['bridge-ramp'], $TerrainTemplate) $AvailableTemplates
            $placements["$($bridgeRampCoordinate.tileX),$($bridgeRampCoordinate.tileY)"] = [pscustomobject]@{
                tileX = $bridgeRampCoordinate.tileX
                tileY = $bridgeRampCoordinate.tileY
                template = $bridgeRampTemplate
                rotationYaw = Get-TransportFeatureRotation $TransportFeature
                role = 'carpark_bridge_ramp'
            }
        }
        $placements["$($entranceCoordinate.tileX),$($entranceCoordinate.tileY)"] = [pscustomobject]@{
            tileX = $entranceCoordinate.tileX
            tileY = $entranceCoordinate.tileY
            template = $carparkEntranceLayout.template
            rotationYaw = $carparkEntranceLayout.rotationYaw
            role = 'carpark_entrance'
        }
        foreach ($lane in @(
            [pscustomobject]@{ key = 'east'; direction = $localEastDirection; template = $carparkTemplateSet.straightEast; role = 'carpark_lane_east' },
            [pscustomobject]@{ key = 'west'; direction = $localWestDirection; template = $carparkTemplateSet.straightWest; role = 'carpark_lane_west' }
        )) {
            if ($carparkEntranceLayout.openLaneKeys -notcontains $lane.key) { continue }
            $laneRotation = Get-CarparkLaneRotation $lane.direction
            for ($distance = 1; $distance -le $carparkLaneLength; $distance++) {
                $laneCoordinate = Get-OffsetTileCoordinate $entranceCoordinate $lane.direction $distance
                $laneKey = "$($laneCoordinate.tileX),$($laneCoordinate.tileY)"
                if (-not $placements.ContainsKey($laneKey)) { continue }
                $placements[$laneKey] = [pscustomobject]@{
                    tileX = $laneCoordinate.tileX
                    tileY = $laneCoordinate.tileY
                    template = $lane.template
                    rotationYaw = $laneRotation
                    role = $lane.role
                }
            }
            if ($carparkLaneLength -lt $center) {
                $endcapCoordinate = Get-OffsetTileCoordinate $entranceCoordinate $lane.direction ($carparkLaneLength + 1)
                $endcapKey = "$($endcapCoordinate.tileX),$($endcapCoordinate.tileY)"
                $endcapDefinition = Get-CarparkEndcapDefinition $lane.direction $carparkTemplateSet
                if ($null -eq $endcapDefinition) { throw "No carpark endcap is configured for $($lane.direction)." }
                $placements[$endcapKey] = [pscustomobject]@{
                    tileX = $endcapCoordinate.tileX
                    tileY = $endcapCoordinate.tileY
                    template = $endcapDefinition.template
                    rotationYaw = $endcapDefinition.rotationYaw
                    role = "carpark_lane_endcap_$($lane.key)"
                }
            }
        }
    }

    if ($ForceCarpark -and $Topology -in @('road-tjunction', 'road-crossjunction') -and $TileGridSize -ge 5 -and -not $hasNamedLandmark -and $null -ne $carparkTemplateSet) {
        $carparkAccess = Get-JunctionCarparkAccess $placements $TileGridSize
        if ($null -eq $carparkAccess) { throw "No sidecar carpark space is available for forced junction coverage at $($Cell.x),$($Cell.y)." }
        $carparkYaw = Get-CarparkAssemblyRotation $carparkAccess.branchDirection
        $closedLaneKey = if ($carparkAccess.lane.key -eq 'east') { 'west' } else { 'east' }
        $entranceDefinition = Get-CarparkOneSidedEntranceDefinition $closedLaneKey $carparkYaw
        $entranceTemplate = if ($null -eq $entranceDefinition) { '' } else { [string]$carparkTemplateSet[$entranceDefinition.templateKey] }
        if ([string]::IsNullOrWhiteSpace($entranceTemplate)) { throw "No one-sided carpark entrance is configured for junction coverage at $($Cell.x),$($Cell.y)." }
        $carparkLaneLength = 1
        $roadTjunctionTemplate = Resolve-Template @($plannerSettings.topologyTemplates['road-tjunction'], $plannerSettings.topologyTemplates['road-straight'], $TerrainTemplate) $AvailableTemplates
        $laneTemplate = if ($carparkAccess.lane.key -eq 'east') { $carparkTemplateSet.straightEast } else { $carparkTemplateSet.straightWest }
        $placements["$($carparkAccess.road.tileX),$($carparkAccess.road.tileY)"] = [pscustomobject]@{
            tileX = $carparkAccess.road.tileX
            tileY = $carparkAccess.road.tileY
            template = $roadTjunctionTemplate
            rotationYaw = Get-CarparkJunctionRotation $carparkAccess.branchDirection
            role = 'carpark_road_junction'
        }
        $placements["$($carparkAccess.entrance.tileX),$($carparkAccess.entrance.tileY)"] = [pscustomobject]@{
            tileX = $carparkAccess.entrance.tileX
            tileY = $carparkAccess.entrance.tileY
            template = $entranceTemplate
            rotationYaw = [int]$entranceDefinition.rotationYaw
            role = 'carpark_entrance'
        }
        $laneRotation = Get-CarparkLaneRotation $carparkAccess.lane.direction
        for ($distance = 1; $distance -le $carparkLaneLength; $distance++) {
            $laneCoordinate = Get-OffsetTileCoordinate $carparkAccess.entrance $carparkAccess.lane.direction $distance
            $placements["$($laneCoordinate.tileX),$($laneCoordinate.tileY)"] = [pscustomobject]@{
                tileX = $laneCoordinate.tileX
                tileY = $laneCoordinate.tileY
                template = $laneTemplate
                rotationYaw = $laneRotation
                role = "carpark_lane_$($carparkAccess.lane.key)"
            }
        }
        $endcapCoordinate = Get-OffsetTileCoordinate $carparkAccess.entrance $carparkAccess.lane.direction ($carparkLaneLength + 1)
        $endcapKey = "$($endcapCoordinate.tileX),$($endcapCoordinate.tileY)"
        if ($placements.ContainsKey($endcapKey)) {
            $endcapDefinition = Get-CarparkEndcapDefinition $carparkAccess.lane.direction $carparkTemplateSet
            if ($null -eq $endcapDefinition) { throw "No carpark endcap is configured for $($carparkAccess.lane.direction)." }
            $placements[$endcapKey] = [pscustomobject]@{
                tileX = $endcapCoordinate.tileX
                tileY = $endcapCoordinate.tileY
                template = $endcapDefinition.template
                rotationYaw = $endcapDefinition.rotationYaw
                role = "carpark_lane_endcap_$($carparkAccess.lane.key)"
            }
        }
    }

    if (-not $hasNamedLandmark) {
        $multiTileTemplate = $forcedMultiTileTemplate
        $macroAllowedRoles = @('building', 'terrain', 'decoration')
        $macroRoadPlacements = @($placements.Values | Where-Object { $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road', $TransportFeature) } | Sort-Object tileY, tileX)
        if ([string]::IsNullOrWhiteSpace($multiTileTemplate) -and $multiTileEnabled -and (Get-PlacementVariationRoll $PlacementSeed) -lt $multiTileBuildingChancePercent) {
            $multiTileCandidates = @($BuildingTemplates | Where-Object {
                $footprint = Get-TemplateFootprint $_
                ($footprint.width -gt 1 -or $footprint.height -gt 1) -and
                $footprint.width -le $maximumMultiTileFootprint -and
                $footprint.height -le $maximumMultiTileFootprint
            } | Sort-Object)
            if ($multiTileCandidates.Count -gt 0) {
                $candidateStartIndex = [int]([Math]::Abs([int64]$PlacementSeed) % $multiTileCandidates.Count)
                for ($candidateOffset = 0; $candidateOffset -lt $multiTileCandidates.Count; $candidateOffset++) {
                    $candidateIndex = ($candidateStartIndex + $candidateOffset) % $multiTileCandidates.Count
                    $candidateTemplate = [string]$multiTileCandidates[$candidateIndex]
                    $candidateFootprint = Get-TemplateFootprint $candidateTemplate
                    $candidateAnchors = if ($macroRoadPlacements.Count -gt 0) {
                        @(Get-FootprintRoadFacingCandidates $placements $TileGridSize $candidateFootprint.width $candidateFootprint.height $macroRoadPlacements $connections $Topology $macroAllowedRoles)
                    } else {
                        @(Get-FootprintAnchorCandidates $placements $TileGridSize $candidateFootprint.width $candidateFootprint.height $macroAllowedRoles)
                    }
                    if ($candidateAnchors.Count -eq 0) { continue }
                    $commercialAccessPlans = @{}
                    if ($commercialTemplates -contains $candidateTemplate) {
                        $candidateAnchors = @($candidateAnchors | Where-Object {
                            if (-not (Test-CommercialFootprintHasRequiredFrontage $placements $TileGridSize ([int]$_.tileX) ([int]$_.tileY) $candidateFootprint.width $candidateFootprint.height)) { return $false }
                            $accessPlan = Get-CommercialAccessPlan $placements $TileGridSize ([int]$_.tileX) ([int]$_.tileY) $candidateFootprint.width $candidateFootprint.height
                            if ($null -eq $accessPlan) { return $false }
                            $commercialAccessPlans["$($_.tileX),$($_.tileY)"] = $accessPlan
                            return $true
                        })
                    }
                    if ($candidateAnchors.Count -eq 0) { continue }
                    $anchorIndex = (Get-CarparkVariationRoll $PlacementSeed (97 + $candidateIndex)) % $candidateAnchors.Count
                    $anchor = $candidateAnchors[$anchorIndex]
                    $anchorRotationYaw = if ([string]::IsNullOrWhiteSpace([string]$anchor.entranceDirection)) { 0 } else { Get-BuildingEntranceRotation $anchor.entranceDirection }
                    Set-FootprintPlacement $placements $TileGridSize $anchor.tileX $anchor.tileY $candidateFootprint.width $candidateFootprint.height $candidateTemplate $anchorRotationYaw 'building' "building:$($anchor.tileX),$($anchor.tileY)" $macroAllowedRoles
                    if ($commercialTemplates -contains $candidateTemplate) {
                        Set-CommercialAccessPath $placements $commercialAccessPlans["$($anchor.tileX),$($anchor.tileY)"] $concretePathTemplate
                    }
                    break
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($multiTileTemplate)) {
            $fixtureFootprint = Get-TemplateFootprint $multiTileTemplate
            $fixtureAnchors = if ($macroRoadPlacements.Count -gt 0) {
                @(Get-FootprintRoadFacingCandidates $placements $TileGridSize $fixtureFootprint.width $fixtureFootprint.height $macroRoadPlacements $connections $Topology $macroAllowedRoles)
            } else {
                @(Get-FootprintAnchorCandidates $placements $TileGridSize $fixtureFootprint.width $fixtureFootprint.height $macroAllowedRoles)
            }
            if ($fixtureAnchors.Count -eq 0) {
                throw "Forced multi-tile template '$multiTileTemplate' has no compatible footprint at $($Cell.x),$($Cell.y)."
            }
            $fixtureAnchor = $fixtureAnchors[(Get-CarparkVariationRoll $PlacementSeed 101) % $fixtureAnchors.Count]
            $fixtureRotationYaw = if ([string]::IsNullOrWhiteSpace([string]$fixtureAnchor.entranceDirection)) { 0 } else { Get-BuildingEntranceRotation $fixtureAnchor.entranceDirection }
            Set-FootprintPlacement $placements $TileGridSize $fixtureAnchor.tileX $fixtureAnchor.tileY $fixtureFootprint.width $fixtureFootprint.height $multiTileTemplate $fixtureRotationYaw 'building' "building:$($fixtureAnchor.tileX),$($fixtureAnchor.tileY)" $macroAllowedRoles
        }
    }

    $plannedPlacements = @($placements.Values | Sort-Object tileY, tileX)
    Set-TilePlacementDefaults $plannedPlacements
    return $plannedPlacements
}

function Get-ProfileFallbackTemplates {
    param(
        [object]$Cell,
        [string]$Profile,
        [string[]]$Landmarks
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    $allowCommercial = $Profile -in $plannerSettings.buildingSelection.commercialProfiles -or (Test-CommercialSpreadPlacement $Cell $Profile)
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

function Test-CommercialSpreadPlacement {
    param(
        [object]$Cell,
        [string]$Profile
    )

    if ($commercialSpreadChancePercent -eq 0 -or $Profile -notin $commercialSpreadProfiles) { return $false }
    [int64]$hash = ([int64]$map.map.seed * 73856093) + ([int64]$Cell.x * 19349663) + ([int64]$Cell.y * 83492791)
    $hash = $hash -bxor ($hash -shr 13) -bxor ($hash -shr 23)
    return [int]([Math]::Abs($hash) % 100) -lt $commercialSpreadChancePercent
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
    }
    return $null
}

function Get-CompactMacroTemplateCode {
    param([string]$Template)

    $templateCode = ConvertTo-FilenamePart ([System.IO.Path]::GetFileNameWithoutExtension($Template))
    $templateCode = $templateCode -replace '^tile-', ''
    $templateCode = $templateCode -replace '-(?:2x|2x2|3x|3x3)$', ''
    switch -Regex ($templateCode) {
        '^building-' { return 'b' + $templateCode.Substring('building-'.Length) }
        '^commercial-' { return 'c' + $templateCode.Substring('commercial-'.Length) }
        '^construction-' { return 'cn' + $templateCode.Substring('construction-'.Length) }
        '^hospital-' { return 'h' + $templateCode.Substring('hospital-'.Length) }
        '^epicenter-' { return 'e' + $templateCode.Substring('epicenter-'.Length) }
        default { return $templateCode }
    }
}

function Get-CompactMacroRotationCode {
    param([int]$RotationYaw)

    $normalizedYaw = (($RotationYaw % 360) + 360) % 360
    if (($normalizedYaw % 90) -eq 0) { return 'q{0}' -f [int]($normalizedYaw / 90) }
    return 'r{0}' -f $normalizedYaw
}

function Get-MacroLayoutFilenameCode {
    param([object[]]$TilePlacements)

    $macroCodes = [System.Collections.Generic.List[string]]::new()
    foreach ($placement in @($TilePlacements | Sort-Object tileY, tileX)) {
        $emitsProperty = $placement.PSObject.Properties['emitsInstance']
        $emitsInstance = $null -eq $emitsProperty -or [bool]$emitsProperty.Value
        $widthProperty = $placement.PSObject.Properties['footprintWidth']
        $heightProperty = $placement.PSObject.Properties['footprintHeight']
        $footprintWidth = if ($null -eq $widthProperty) { 1 } else { [int]$widthProperty.Value }
        $footprintHeight = if ($null -eq $heightProperty) { 1 } else { [int]$heightProperty.Value }
        if (-not $emitsInstance -or ($footprintWidth -eq 1 -and $footprintHeight -eq 1)) { continue }

        $templateCode = Get-CompactMacroTemplateCode ([string]$placement.template)
        $rotationCode = Get-CompactMacroRotationCode ([int]$placement.rotationYaw)
        $macroCodes.Add(('m{0}{1}-{2}-p{3}-{4}-{5}' -f $footprintWidth, $footprintHeight, $templateCode, [int]$placement.tileX, [int]$placement.tileY, $rotationCode))
    }
    return [string]($macroCodes -join '+')
}

function Get-RecipeFilenameCodes {
    param(
        [string]$Profile,
        [string]$Topology,
        [string]$Orientation,
        [string]$TransportFeature,
        [int]$BuildingDensityTier,
        [string[]]$Landmarks,
        [object[]]$TilePlacements = @()
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
        macro = Get-MacroLayoutFilenameCode $TilePlacements
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
    $filename = $filename.Replace('<landmarks>', (@($Codes.landmarks) -join '+'))
    if ([string]::IsNullOrWhiteSpace([string]$Codes.macro)) { return $filename }
    return ('{0}-{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($filename), [string]$Codes.macro, [System.IO.Path]::GetExtension($filename))
}

function Get-CarparkCoverageFilename {
    param(
        [string]$BaseFilename,
        [bool]$ForceCarpark
    )

    if (-not $ForceCarpark) { return $BaseFilename }
    return '{0}-cp.vmf' -f [System.IO.Path]::GetFileNameWithoutExtension($BaseFilename)
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

$carparkCoverage = Get-CarparkCoveragePlan @($map.cells)
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
    $forceCarpark = $carparkCoverage.selectedCoordinates.ContainsKey("$($cell.x),$($cell.y)")

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
    $tilePlacements = @(Get-CellTilePlacements $cell $terrainTemplate $buildingCandidates $landmarkTemplate $landmarks $profile $carparkTemplates $decorationTemplates $placementSeed $buildingDensityTier $transportFeature $topology $orientation $CellTileSize $templateFiles $forceCarpark)
    $filenameCodes = Get-RecipeFilenameCodes $profile $topology $orientation $transportFeature $buildingDensityTier $landmarks $tilePlacements
    $cellTemplateFilename = Get-CarparkCoverageFilename (Get-CellFilename $filenameCodes) $forceCarpark
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
        landmarkMarkers = @($cell.landmarks | Where-Object { $landmarks -contains [string]$_.name } | ForEach-Object {
            $colorProperty = $_.PSObject.Properties['color']
            [pscustomobject]@{ name = [string]$_.name; color = if ($null -eq $colorProperty) { $null } else { $colorProperty.Value } }
        })
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
        forceCarpark = $forceCarpark
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
        $variantCell.tilePlacements = @(Get-CellTilePlacements $mapCell $variantTerrainTemplate $variantCell.buildingTemplates $variantCell.landmarkTemplate $variantCell.landmarks $variantCell.environmentProfile $carparkTemplates $decorationTemplates $variantCell.placementSeed $variantCell.buildingDensityTier $variantCell.transportFeature $variantCell.topology $variantCell.orientation $CellTileSize $templateFiles ([bool]$variantCell.forceCarpark))
    }
}

$forcedCarparkCells = @($planCells | Where-Object { $_.forceCarpark })
$forcedCarparkPlacements = @($forcedCarparkCells | Where-Object {
    @($_.tilePlacements | Where-Object { $_.role -eq 'carpark_entrance' }).Count -eq 1
})
if ($forcedCarparkPlacements.Count -ne $forcedCarparkCells.Count) {
    throw "Carpark coverage selected $($forcedCarparkCells.Count) cells, but only $($forcedCarparkPlacements.Count) received an entrance placement."
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
    carparkCoverage = [ordered]@{
        cellSpan = $carparkCoverage.cellSpan
        carparksPerRegion = $carparkCoverage.carparksPerRegion
        minimumCellSeparation = $carparkCoverage.minimumCellSeparation
        eligibleCellCount = $carparkCoverage.eligibleCells.Count
        selectedCellCount = $carparkCoverage.selectedCells.Count
        selectedCells = @($carparkCoverage.selectedCells | ForEach-Object { [ordered]@{ x = [int]$_.cell.x; y = [int]$_.cell.y; region = $_.region; topology = $_.topology } })
    }
    cells = $planCells
}

if (-not $ListOnly) {
    [System.IO.File]::WriteAllText($Output, ($plan | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllLines($ListOutput, [string[]]@($requiredCellFiles | ForEach-Object { $_.filename }), [System.Text.UTF8Encoding]::new($false))
    Write-Output "Wrote template plan: $Output"
    Write-Output "Wrote required cell list: $ListOutput"
}
Write-Output "Carpark coverage selected $($forcedCarparkCells.Count) eligible cells across $($carparkCoverage.selectedCells.Count) selections with $($carparkCoverage.carparksPerRegion) carpark(s) per $($carparkCoverage.cellSpan)-cell region and a $($carparkCoverage.minimumCellSeparation)-cell minimum separation."

$requiredCellFiles | ForEach-Object { $_.filename }
