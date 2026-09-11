param(
    [string]$PlanData = '',
    [string]$CellDirectory = '',
    [string]$TileDirectory = '',
    [string]$BaseCellTemplate = '',
    [int]$TileSize = 640,
    [int]$TileZOffset = 0,
    [switch]$Force,
    [switch]$RefreshGenerated,
    [switch]$PruneStaleGenerated,
    [switch]$ClearCellDirectory,
    [switch]$WhatIf,
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
if (-not $PSBoundParameters.ContainsKey('TileSize')) { $TileSize = [int]$generatorSettings.vmfBuild.tileSize }
if (-not $PSBoundParameters.ContainsKey('TileZOffset')) { $TileZOffset = [int]$generatorSettings.vmfBuild.tileZOffset }
$vmfBuildSettings = $generatorSettings.vmfBuild
$borderSettings = if ($vmfBuildSettings.ContainsKey('border')) { $vmfBuildSettings.border } else { @{} }
$borderEnabled = $borderSettings.ContainsKey('enabled') -and [bool]$borderSettings.enabled
$topologyTemplates = $generatorSettings.cellPlanning.topologyTemplates
if (-not $PSBoundParameters.ContainsKey('PruneStaleGenerated')) { $PruneStaleGenerated = $true }
Import-Module (Join-Path $PSScriptRoot 'carpark_endcaps.psm1') -Force
if ($borderEnabled) {
    if (-not $borderSettings.ContainsKey('wallTemplatesByDensity') -or @($borderSettings.wallTemplatesByDensity).Count -eq 0) {
        throw 'vmfBuild.border must define at least one wallTemplatesByDensity entry when borders are enabled.'
    }
    if (-not $borderSettings.ContainsKey('cornerTemplate') -or [string]::IsNullOrWhiteSpace([string]$borderSettings.cornerTemplate)) {
        throw 'vmfBuild.border must define cornerTemplate when borders are enabled.'
    }
    foreach ($requiredTopology in @('road-straight', 'motorway-straight')) {
        if (-not $topologyTemplates.ContainsKey($requiredTopology) -or [string]::IsNullOrWhiteSpace([string]$topologyTemplates[$requiredTopology])) {
            throw "cellPlanning.topologyTemplates must define $requiredTopology when borders are enabled."
        }
    }
    if (-not $borderSettings.ContainsKey('transitionGateRoadTemplates') -or @($borderSettings.transitionGateRoadTemplates).Count -eq 0) {
        throw 'vmfBuild.border must define at least one transitionGateRoadTemplates entry when borders are enabled.'
    }
}

if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -Path $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path $PlanData)) {
    throw 'A template plan is required. Pass -PlanData with a *_template_plan.json path.'
}

$plan = Get-Content -Raw $PlanData | ConvertFrom-Json
if ($plan.schemaVersion -lt 2 -or $plan.cellTileGridSize -lt 1) {
    throw 'The template plan must contain a cellTileGridSize and tilePlacements.'
}
$safeZoneMaps = @($plan.safeZoneMaps)
$safeZoneTemplateDirectory = [string]$plan.safeZoneTemplateDirectory
if ($safeZoneMaps.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($safeZoneTemplateDirectory) -or -not (Test-Path -LiteralPath $safeZoneTemplateDirectory -PathType Container))) {
    throw 'The template plan defines standalone safe-zone maps but has no valid safeZoneTemplateDirectory. Re-run plan_cell_templates.ps1.'
}

if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = Join-Path $projectRoot $profileSettings.cellDirectory
}
if ([string]::IsNullOrWhiteSpace($TileDirectory)) {
    $TileDirectory = $plan.chunkTemplateDirectory
}
if ([string]::IsNullOrWhiteSpace($BaseCellTemplate)) {
    $BaseCellTemplate = Join-Path $projectRoot $generatorSettings.paths.baseCellTemplate
}
if (-not (Test-Path $TileDirectory)) {
    throw "Tile template directory was not found: $TileDirectory"
}
if (-not (Test-Path $BaseCellTemplate)) {
    throw "Base cell template was not found: $BaseCellTemplate"
}
if (-not (Test-Path $CellDirectory)) {
    [System.IO.Directory]::CreateDirectory($CellDirectory) | Out-Null
}
$atmosphereSettings = $generatorSettings.atmosphere
if (-not ($atmosphereSettings -is [System.Collections.IDictionary]) -or
    -not ($atmosphereSettings.lightingProfiles -is [System.Collections.IDictionary]) -or
    -not ($atmosphereSettings.environmentLightingProfiles -is [System.Collections.IDictionary])) {
    throw 'generator-settings.json must define atmosphere lightingProfiles and environmentLightingProfiles objects.'
}
$lightingProfiles = $atmosphereSettings.lightingProfiles
$environmentLightingProfiles = $atmosphereSettings.environmentLightingProfiles
if (-not $environmentLightingProfiles.ContainsKey('default')) {
    throw 'generator-settings.json atmosphere.environmentLightingProfiles must define a default profile.'
}
foreach ($lightingProfileName in $lightingProfiles.Keys) {
    $lightingProfile = $lightingProfiles[$lightingProfileName]
    if (-not ($lightingProfile -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$lightingProfile.skyname) -or
        @($lightingProfile.ambient).Count -ne 4 -or @($lightingProfile.light).Count -ne 4) {
        throw "Atmosphere lighting profile '$lightingProfileName' must define skyname plus four-value ambient and light colors."
    }
}
foreach ($environmentProfile in $environmentLightingProfiles.Keys) {
    $lightingProfileName = [string]$environmentLightingProfiles[$environmentProfile]
    if (-not $lightingProfiles.ContainsKey($lightingProfileName)) {
        throw "Atmosphere environment lighting profile '$environmentProfile' references unknown lighting profile '$lightingProfileName'."
    }
}
$CellDirectory = (Resolve-Path $CellDirectory).Path
$clearedItems = 0
if ($ClearCellDirectory) {
    $projectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
    $expectedCellDirectory = (Join-Path $projectRoot $profileSettings.cellDirectory).TrimEnd('\')
    if (-not [string]::Equals($CellDirectory.TrimEnd('\'), $expectedCellDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "-ClearCellDirectory only supports the project source directory: $expectedCellDirectory"
    }

    $itemsToClear = @(Get-ChildItem -Path $CellDirectory -Force)
    if (-not $WhatIf) {
        foreach ($item in $itemsToClear) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
    }
    $clearedItems = $itemsToClear.Count
}

function Get-VmfInstancePath {
    param(
        [string]$SourceDirectory,
        [string]$TemplateDirectory,
        [string]$TemplateFilename
    )

    $fullTemplatePath = Join-Path $TemplateDirectory $TemplateFilename
    if (-not (Test-Path $fullTemplatePath)) {
        throw "Tile template was not found: $fullTemplatePath"
    }
    $sourcePath = (Resolve-Path $SourceDirectory).Path.TrimEnd('\') + '\'
    $sourceUri = [System.Uri]$sourcePath
    $templateUri = [System.Uri](Resolve-Path $fullTemplatePath).Path
    return [System.Uri]::UnescapeDataString($sourceUri.MakeRelativeUri($templateUri).ToString())
}

function Get-PlacementFootprint {
    param([object]$Placement)

    $widthProperty = $Placement.PSObject.Properties['footprintWidth']
    $heightProperty = $Placement.PSObject.Properties['footprintHeight']
    $width = if ($null -eq $widthProperty) { 1 } else { [int]$widthProperty.Value }
    $height = if ($null -eq $heightProperty) { 1 } else { [int]$heightProperty.Value }
    if ($width -lt 1 -or $height -lt 1 -or $width -ne $height -or $width -gt 3) {
        throw "Placement '$($Placement.template)' must define a square footprint from 1x1 through 3x3."
    }
    return [pscustomobject]@{ width = $width; height = $height }
}

function Test-PlacementEmitsInstance {
    param([object]$Placement)

    $property = $Placement.PSObject.Properties['emitsInstance']
    return $null -eq $property -or [bool]$property.Value
}

function Get-PlacementId {
    param([object]$Placement)

    $property = $Placement.PSObject.Properties['placementId']
    if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return [string]$property.Value
    }
    return "tile:$([int]$Placement.tileX),$([int]$Placement.tileY)"
}

function Get-PlacementDebugTargetname {
    param([object]$Placement)

    $roleProperty = $Placement.PSObject.Properties['role']
    $role = if ($null -eq $roleProperty) { 'tile' } else { [string]$roleProperty.Value }
    $role = $role.ToLowerInvariant() -replace '[^a-z0-9_]+', '_'
    if ([string]::IsNullOrWhiteSpace($role)) { $role = 'tile' }
    return "zm_tile_${role}_$([int]$Placement.tileX)_$([int]$Placement.tileY)"
}

function Get-PlacementOwnerCoordinate {
    param(
        [object]$Placement,
        [string]$PropertyName,
        [int]$DefaultValue
    )

    $property = $Placement.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $DefaultValue }
    return [int]$property.Value
}

function Get-PlacementCoordinates {
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

function Test-RecipeTilePlacements {
    param(
        [object]$Recipe,
        [int]$TileGridSize
    )

    $placements = @($Recipe.tilePlacements)
    $expectedTileCount = $TileGridSize * $TileGridSize
    if ($placements.Count -ne $expectedTileCount) {
        throw "$($Recipe.cellTemplateFilename) has $($placements.Count) occupancy records; expected $expectedTileCount."
    }

    $placementByCoordinate = @{}
    foreach ($placement in $placements) {
        $tileX = [int]$placement.tileX
        $tileY = [int]$placement.tileY
        $key = "$tileX,$tileY"
        if ($tileX -lt 0 -or $tileX -ge $TileGridSize -or $tileY -lt 0 -or $tileY -ge $TileGridSize -or $placementByCoordinate.ContainsKey($key)) {
            throw "$($Recipe.cellTemplateFilename) has an invalid or duplicate occupancy coordinate: $key"
        }
        $placementByCoordinate[$key] = $placement
    }

    $ownerByCoordinate = @{}
    foreach ($placement in $placements) {
        if (-not (Test-PlacementEmitsInstance $placement)) { continue }
        $tileX = [int]$placement.tileX
        $tileY = [int]$placement.tileY
        $footprint = Get-PlacementFootprint $placement
        $placementId = Get-PlacementId $placement
        foreach ($coordinate in @(Get-PlacementCoordinates $tileX $tileY $footprint.width $footprint.height)) {
            $key = "$($coordinate.tileX),$($coordinate.tileY)"
            if (-not $placementByCoordinate.ContainsKey($key) -or $ownerByCoordinate.ContainsKey($key)) {
                throw "$($Recipe.cellTemplateFilename) has overlapping or incomplete footprint ownership at $key."
            }
            $ownerByCoordinate[$key] = $placement
        }
    }

    if ($ownerByCoordinate.Count -ne $expectedTileCount) {
        throw "$($Recipe.cellTemplateFilename) covers $($ownerByCoordinate.Count) interior tiles; expected $expectedTileCount."
    }
    foreach ($key in $placementByCoordinate.Keys) {
        $occupancyRecord = $placementByCoordinate[$key]
        $owner = $ownerByCoordinate[$key]
        $ownerId = Get-PlacementId $owner
        if ((Get-PlacementId $occupancyRecord) -ne $ownerId -or
            (Get-PlacementOwnerCoordinate $occupancyRecord 'ownerTileX' ([int]$occupancyRecord.tileX)) -ne [int]$owner.tileX -or
            (Get-PlacementOwnerCoordinate $occupancyRecord 'ownerTileY' ([int]$occupancyRecord.tileY)) -ne [int]$owner.tileY) {
            throw "$($Recipe.cellTemplateFilename) has inconsistent footprint ownership at $key."
        }
    }
}

function Get-RecipeInteriorInstanceCount {
    param([object]$Recipe)

    return @($Recipe.tilePlacements | Where-Object { Test-PlacementEmitsInstance $_ }).Count
}

function Test-GeneratedCellVmf {
    param(
        [string]$Path,
        [int]$ExpectedInteriorInstanceCount = -1,
        [int]$ExpectedBorderInstanceCount = -1,
        [int]$ExpectedTransitionGateCount = -1
    )

    $contents = Get-Content -Raw $Path
    $instanceCount = [regex]::Matches($contents, '"classname" "func_instance"').Count
    if ($ExpectedInteriorInstanceCount -ge 0) {
        $expectedBorderCount = if ($ExpectedBorderInstanceCount -ge 0) { $ExpectedBorderInstanceCount } elseif ($borderEnabled) { 24 } else { 0 }
        $expectedInstanceCount = $ExpectedInteriorInstanceCount + $expectedBorderCount
        if ($instanceCount -ne $expectedInstanceCount) { return $false }
    }
    if ($ExpectedTransitionGateCount -ge 0 -and [regex]::Matches($contents, '"zm_transition_gate" "1"').Count -ne $ExpectedTransitionGateCount) {
        return $false
    }
    if (-not $borderEnabled) {
        return $contents -match 'tiletemplates/' -and $instanceCount -gt 0
    }
    return $contents -match 'tiletemplates/' -and
        $instanceCount -ge 24 -and
        [regex]::Matches($contents, '"targetname" "(?:zm_border_|zm_transition_road_)').Count -eq 24
}

function Get-RecipeLightingProfile {
    param([object]$Recipe)

    $environmentProfile = ([string]$Recipe.environmentProfile).ToLowerInvariant()
    if ($environmentLightingProfiles.ContainsKey($environmentProfile)) {
        return [string]$environmentLightingProfiles[$environmentProfile]
    }
    return [string]$environmentLightingProfiles.default
}

function Set-VmfKeyValue {
    param([string]$Vmf, [string]$Key, [string]$Value)

    $pattern = '(?m)^(\s*"' + [regex]::Escape($Key) + '"\s*)"[^"]*"\r?$'
    if ([regex]::Matches($Vmf, $pattern).Count -ne 1) {
        throw "Expected exactly one '$Key' key in the base cell template."
    }
    return [regex]::Replace($Vmf, $pattern, ('${{1}}"{0}"' -f $Value), 1)
}

function Set-VmfLightingProfile {
    param([string]$Vmf, [string]$Profile)

    if (-not $lightingProfiles.ContainsKey($Profile)) {
        throw "Unknown baked lighting profile: $Profile"
    }
    $lightingProfile = $lightingProfiles[$Profile]
    $settings = [ordered]@{
        skyname = [string]$lightingProfile.skyname
        _ambient = (@($lightingProfile.ambient) -join ' ')
        _light = (@($lightingProfile.light) -join ' ')
    }
    foreach ($key in $settings.Keys) {
        $Vmf = Set-VmfKeyValue $Vmf $key $settings[$key]
    }
    return $Vmf
}

function Remove-TemplateCubemaps {
    param([string]$Vmf)

    $pattern = '(?ms)^entity\r?\n\{\r?\n\s*"id" "\d+"\r?\n\s*"classname" "env_cubemap".*?^\}\r?\n(?=cameras|entity)'
    if ([regex]::Matches($Vmf, $pattern).Count -ne 1) {
        throw 'Base cell template must contain exactly one env_cubemap fallback entity.'
    }
    return [regex]::Replace($Vmf, $pattern, '', 1)
}

function Get-CubemapAnchors {
    param([object]$Recipe, [int]$TileGridSize, [int]$TileWidth, [int]$TileVerticalOffset)

    $placements = @($Recipe.tilePlacements | Where-Object { Test-PlacementEmitsInstance $_ })
    $center = [int][Math]::Floor($TileGridSize / 2)
    $usedCoordinates = @{}
    $candidates = [System.Collections.Generic.List[object]]::new()
    $hasRoad = $false
    $hasLandmark = $false

    function Add-CubemapCandidate {
        param([object]$Placement, [int]$Priority)

        $footprint = Get-PlacementFootprint $Placement
        $tileX = [double]$Placement.tileX + (($footprint.width - 1) / 2.0)
        $tileY = [double]$Placement.tileY + (($footprint.height - 1) / 2.0)
        $key = "$tileX,$tileY"
        if ($usedCoordinates.ContainsKey($key)) { return }
        $usedCoordinates[$key] = $true
        $candidates.Add([ordered]@{
            priority = $Priority
            distance = [Math]::Abs($tileX - $center) + [Math]::Abs($tileY - $center)
            x = [int](($tileX - $center) * $TileWidth)
            y = [int](($center - $tileY) * $TileWidth)
            z = $TileVerticalOffset + 96
        })
    }

    foreach ($placement in $placements) {
        $template = ([string]$placement.template).ToLowerInvariant()
        $isRoad = $template -match '(road|path|motorway)'
        $isJunction = $isRoad -and $template -match '(corner|cross|tjunction|junction|onramp|bridge)'
        $isLandmark = $template -match '(church|hospital|school|station|market|bank|tower|airport|laboratory|stadium|mall|epicenter)'
        $isOpen = -not $isRoad -and $template -match '(grass|park|plaza|open|field|lot|concrete)'
        $hasRoad = $hasRoad -or $isRoad
        $hasLandmark = $hasLandmark -or $isLandmark

        if ($isRoad -and [int]$placement.tileX -eq $center -and [int]$placement.tileY -eq $center) {
            Add-CubemapCandidate $placement 0
        }
        if ($isJunction) { Add-CubemapCandidate $placement 1 }
        if ($isLandmark) { Add-CubemapCandidate $placement 2 }
        if ($isOpen) { Add-CubemapCandidate $placement 3 }
        if ($isRoad) { Add-CubemapCandidate $placement 4 }
    }

    $denseRecipe = (Get-RecipeLightingProfile $Recipe) -eq 'overcast_day'
    $desiredCount = if ($denseRecipe -or $hasLandmark) { 3 } elseif ($hasRoad) { 2 } else { 1 }
    $anchors = @($candidates | Sort-Object priority, distance, y, x | Select-Object -First $desiredCount)
    if ($anchors.Count -eq 0) {
        $anchors = @([ordered]@{ priority = 5; distance = 0; x = 0; y = 0; z = $TileVerticalOffset + 128 })
    }
    return $anchors
}

function Get-RecipeEdgeConnections {
    param([object]$Recipe)

    $topology = ([string]$Recipe.topology).ToLowerInvariant()
    $orientation = ([string]$Recipe.orientation).ToLowerInvariant()
    if ($topology -notmatch '^(road|motorway)-') { return @() }
    if ($topology -like '*-crossjunction') { return @('N', 'E', 'S', 'W') }
    if ($topology -like '*-straight') {
        if ($orientation -eq 'vertical') { return @('N', 'S') }
        if ($orientation -eq 'horizontal') { return @('E', 'W') }
    }
    if ($topology -like '*-corner') {
        $directionCodes = @{ north = 'N'; east = 'E'; south = 'S'; west = 'W' }
        return @($orientation.Split('-') | ForEach-Object { $directionCodes[$_] } | Where-Object { $_ })
    }
    if ($topology -like '*-tjunction') {
        $missingDirection = $orientation.Replace('missing-', '').Substring(0, 1).ToUpperInvariant()
        $allDirections = @('N', 'E', 'S', 'W')
        return @($allDirections | Where-Object { $_ -ne $missingDirection })
    }
    if ($topology -like '*-deadend') {
        return @($orientation.Substring(0, 1).ToUpperInvariant())
    }
    return @()
}

function Get-BorderTemplateSet {
    param([object]$Recipe)

    $wallTemplates = @($borderSettings.wallTemplatesByDensity)
    $cornerTemplate = [string]$borderSettings.cornerTemplate
    $profile = ([string]$Recipe.environmentProfile).ToLowerInvariant()
    if ($borderSettings.ContainsKey('profileTemplates') -and $borderSettings.profileTemplates.ContainsKey($profile)) {
        $profileTemplates = $borderSettings.profileTemplates[$profile]
        if ($profileTemplates.ContainsKey('wallTemplatesByDensity') -and @($profileTemplates.wallTemplatesByDensity).Count -gt 0) {
            $wallTemplates = @($profileTemplates.wallTemplatesByDensity)
        }
        if ($profileTemplates.ContainsKey('cornerTemplate') -and -not [string]::IsNullOrWhiteSpace([string]$profileTemplates.cornerTemplate)) {
            $cornerTemplate = [string]$profileTemplates.cornerTemplate
        }
    }

    $densityTier = [Math]::Max(1, [int]$Recipe.buildingDensityTier)
    $wallIndex = [Math]::Min($densityTier - 1, $wallTemplates.Count - 1)
    return [ordered]@{
        wallTemplate = [string]$wallTemplates[$wallIndex]
        cornerTemplate = $cornerTemplate
    }
}

function Get-BorderPlacements {
    param([object]$Recipe, [int]$TileGridSize)

    if (-not $borderEnabled) { return @() }

    $edgeConnections = @(Get-RecipeEdgeConnections $Recipe)
    $rampExits = @($Recipe.rampExits | Where-Object { $_ -in @('N', 'E', 'S', 'W') } | Sort-Object -Unique)
    $isMotorway = ([string]$Recipe.topology).ToLowerInvariant() -like 'motorway-*'
    $primaryRoadTemplate = if ($isMotorway) { [string]$topologyTemplates['motorway-straight'] } else { [string]$topologyTemplates['road-straight'] }
    $rampRoadTemplate = [string]$topologyTemplates['road-straight']
    $transitionGateRoadTemplates = @($borderSettings.transitionGateRoadTemplates | ForEach-Object { [string]$_ })
    $transitionGateTemplateSeed = [Math]::Abs([int64]$Recipe.placementSeed)
    $borderTemplates = Get-BorderTemplateSet $Recipe
    $center = [int][Math]::Floor($TileGridSize / 2)
    $carparkEndcapsByBorderSlot = @{}
    foreach ($endcap in @(Get-CarparkEndcapPlacements -Recipe $Recipe -TileGridSize $TileGridSize -CarparkTemplates $generatorSettings.cellPlanning.carparks.templates)) {
        $carparkEndcapsByBorderSlot["$($endcap.tileX),$($endcap.tileY)"] = $endcap
    }
    $wallYawBySide = @{ N = 270; E = 180; S = 90; W = 0 }
    $cornerYawByPosition = @{ 'N-W' = 0; 'N-E' = 270; 'S-E' = 180; 'S-W' = 90 }
    $roadYawBySide = @{ N = 0; E = 90; S = 0; W = 90 }
    $placements = [System.Collections.Generic.List[object]]::new()

    for ($tileY = -1; $tileY -le $TileGridSize; $tileY++) {
        for ($tileX = -1; $tileX -le $TileGridSize; $tileX++) {
            $isOuterRow = $tileY -eq -1 -or $tileY -eq $TileGridSize
            $isOuterColumn = $tileX -eq -1 -or $tileX -eq $TileGridSize
            if (-not ($isOuterRow -or $isOuterColumn)) { continue }

            $isCorner = $isOuterRow -and $isOuterColumn
            if ($isCorner) {
                $northSouth = if ($tileY -eq -1) { 'N' } else { 'S' }
                $eastWest = if ($tileX -eq -1) { 'W' } else { 'E' }
                $cornerKey = "$northSouth-$eastWest"
                $placements.Add([ordered]@{
                    tileX = $tileX
                    tileY = $tileY
                    template = $borderTemplates.cornerTemplate
                    rotationYaw = $cornerYawByPosition[$cornerKey]
                    targetname = "zm_border_corner_$northSouth$eastWest"
                })
                continue
            }

            $side = if ($tileY -eq -1) { 'N' } elseif ($tileY -eq $TileGridSize) { 'S' } elseif ($tileX -eq -1) { 'W' } else { 'E' }
            $isCenterEdgeSlot = if ($side -in @('N', 'S')) { $tileX -eq $center } else { $tileY -eq $center }
            $usesRampRoad = $isCenterEdgeSlot -and $rampExits -contains $side
            $usesPrimaryRoad = $isCenterEdgeSlot -and $edgeConnections -contains $side
            $usesRoad = $usesRampRoad -or $usesPrimaryRoad
            $usesTransitionGateRoad = $usesRampRoad -or (-not $isMotorway -and $usesPrimaryRoad)
            $transitionGateRoadTemplate = $null
            if ($usesTransitionGateRoad) {
                $sideIndex = @{ N = 0; E = 1; S = 2; W = 3 }[$side]
                $transitionGateRoadTemplate = $transitionGateRoadTemplates[($transitionGateTemplateSeed + $sideIndex) % $transitionGateRoadTemplates.Count]
            }
            $carparkEndcap = $carparkEndcapsByBorderSlot["$tileX,$tileY"]
            $placements.Add([ordered]@{
                tileX = $tileX
                tileY = $tileY
                template = if ($usesTransitionGateRoad) { $transitionGateRoadTemplate } elseif ($usesRampRoad) { $rampRoadTemplate } elseif ($usesPrimaryRoad) { $primaryRoadTemplate } elseif ($null -ne $carparkEndcap) { $carparkEndcap.template } else { $borderTemplates.wallTemplate }
                rotationYaw = if ($usesRoad) { $roadYawBySide[$side] } elseif ($null -ne $carparkEndcap) { $carparkEndcap.rotationYaw } else { $wallYawBySide[$side] }
                targetname = if ($usesTransitionGateRoad) { "zm_transition_road_$side" } else { "zm_border_$side`_$tileX`_$tileY" }
            })
        }
    }

    $expectedCount = (($TileGridSize + 2) * ($TileGridSize + 2)) - ($TileGridSize * $TileGridSize)
    if ($placements.Count -ne $expectedCount) {
        throw "Border placement count for $($Recipe.cellTemplateFilename) was $($placements.Count), expected $expectedCount."
    }
    return @($placements)
}

function Get-TransitionGatePlacements {
    param([object]$Recipe)

    $activeEntrancesProperty = $Recipe.PSObject.Properties['activeEntrances']
    $directions = if ($null -ne $activeEntrancesProperty) {
        @($activeEntrancesProperty.Value)
    } else {
        @((Get-RecipeEdgeConnections $Recipe) + @($Recipe.rampExits))
    }
    $gateCenters = @{
        N = @{ x = 0; y = 1568; yaw = 90 }
        E = @{ x = 1568; y = 0; yaw = 0 }
        S = @{ x = 0; y = -1568; yaw = 270 }
        W = @{ x = -1568; y = 0; yaw = 180 }
    }

    return @($directions |
        Where-Object { $_ -in @('N', 'E', 'S', 'W') } |
        Sort-Object -Unique |
        ForEach-Object {
            $center = $gateCenters[$_]
            [ordered]@{
                direction = $_
                directionName = @{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }[$_]
                x = [int]$center.x
                y = [int]$center.y
                yaw = [int]$center.yaw
            }
        })
}

function Convert-NorthGateOffset {
    param(
        [object]$Gate,
        [double]$Across,
        [double]$Outward,
        [double]$Yaw = 0
    )

    $rotationRadians = ([double]$Gate.yaw - 90) * [Math]::PI / 180
    $cosine = [Math]::Cos($rotationRadians)
    $sine = [Math]::Sin($rotationRadians)
    return [ordered]@{
        x = [Math]::Round([double]$Gate.x + $Across * $cosine - $Outward * $sine, 3)
        y = [Math]::Round([double]$Gate.y + $Across * $sine + $Outward * $cosine, 3)
        yaw = [int](($Yaw + [int]$Gate.yaw - 90 + 360) % 360)
    }
}

function New-CellVmf {
    param(
        [object]$Recipe,
        [int]$TileGridSize,
        [int]$TileWidth,
        [int]$TileVerticalOffset,
        [string]$SourceDirectory,
        [string]$TemplateDirectory,
        [string]$BaseTemplatePath,
        [object[]]$CubemapAnchors,
        [object[]]$BorderPlacements
    )

    $placements = @($Recipe.tilePlacements)
    Test-RecipeTilePlacements $Recipe $TileGridSize

    $baseVmf = Get-Content -Raw $BaseTemplatePath
    $baseVmf = Remove-TemplateCubemaps $baseVmf
    $baseVmf = Set-VmfLightingProfile $baseVmf (Get-RecipeLightingProfile $Recipe)
    $cameraMatch = [regex]::Match($baseVmf, '(?m)^cameras\r?$')
    if (-not $cameraMatch.Success) {
        throw "Base cell template must contain a cameras block: $BaseTemplatePath"
    }
    $templateIds = @([regex]::Matches($baseVmf, '"id" "(\d+)"') | ForEach-Object { [int]$_.Groups[1].Value })
    $entityId = (@($templateIds | Measure-Object -Maximum).Maximum) + 1
    $center = [int][Math]::Floor($TileGridSize / 2)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($placement in ($placements | Where-Object { Test-PlacementEmitsInstance $_ } | Sort-Object tileY, tileX)) {
        $instancePath = Get-VmfInstancePath $SourceDirectory $TemplateDirectory $placement.template
        $footprint = Get-PlacementFootprint $placement
        $originX = [int]((([int]$placement.tileX - $center) + (($footprint.width - 1) / 2.0)) * $TileWidth)
        $originY = [int]((($center - [int]$placement.tileY) - (($footprint.height - 1) / 2.0)) * $TileWidth)
        $targetname = Get-PlacementDebugTargetname $placement
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "func_instance"',
            ('    "origin" "{0} {1} {2}"' -f $originX, $originY, $TileVerticalOffset),
            ('    "angles" "0 {0} 0"' -f [int]$placement.rotationYaw),
            ('    "file" "{0}"' -f $instancePath),
            ('    "targetname" "{0}"' -f $targetname),
            '    "fixup_style" "0"',
            '}'
        ))
        $entityId++
    }
    foreach ($placement in $BorderPlacements) {
        $instancePath = Get-VmfInstancePath $SourceDirectory $TemplateDirectory $placement.template
        $originX = ([int]$placement.tileX - $center) * $TileWidth
        $originY = ($center - [int]$placement.tileY) * $TileWidth
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "func_instance"',
            ('    "origin" "{0} {1} {2}"' -f $originX, $originY, $TileVerticalOffset),
            ('    "angles" "0 {0} 0"' -f [int]$placement.rotationYaw),
            ('    "file" "{0}"' -f $instancePath),
            ('    "targetname" "{0}"' -f $placement.targetname),
            '    "fixup_style" "0"',
            '}'
        ))
        $entityId++
    }
    foreach ($gate in @(Get-TransitionGatePlacements $Recipe)) {
        $halfWidth = if ($gate.direction -in @('N', 'S')) { 128 } else { 32 }
        $halfDepth = if ($gate.direction -in @('N', 'S')) { 32 } else { 128 }
        $minX = $gate.x - $halfWidth
        $maxX = $gate.x + $halfWidth
        $minY = $gate.y - $halfDepth
        $maxY = $gate.y + $halfDepth
        $minZ = 0
        $maxZ = 112
        $solidId = $entityId + 1
        $sideId = $solidId + 1
        $planes = @(
            "($minX $minY $maxZ) ($maxX $maxY $maxZ) ($maxX $minY $maxZ)",
            "($minX $maxY $minZ) ($maxX $minY $minZ) ($maxX $maxY $minZ)",
            "($maxX $minY $minZ) ($maxX $maxY $maxZ) ($maxX $maxY $minZ)",
            "($minX $maxY $minZ) ($minX $minY $maxZ) ($minX $minY $minZ)",
            "($maxX $maxY $minZ) ($minX $maxY $maxZ) ($minX $maxY $minZ)",
            "($minX $minY $minZ) ($maxX $minY $maxZ) ($maxX $minY $minZ)"
        )
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "trigger_multiple"',
            ('    "origin" "{0} {1} 56"' -f $gate.x, $gate.y),
            ('    "angles" "0 {0} 0"' -f $gate.yaw),
            ('    "targetname" "zm_transition_gate_{0}"' -f $gate.direction),
            '    "zm_transition_gate" "1"',
            ('    "zm_transition_direction" "{0}"' -f $gate.directionName),
            '    "zm_transition_mode" "any"',
            '    "wait" "1"',
            '    "solid"',
            '    {'
            ('        "id" "{0}"' -f $solidId)
        ))
        foreach ($plane in $planes) {
            $lines.AddRange([string[]]@(
                '        "side"',
                '        {',
                ('            "id" "{0}"' -f $sideId),
                ('            "plane" "{0}"' -f $plane),
                '            "material" "TOOLS/TOOLSTRIGGER"',
                '            "uaxis" "[1 0 0 0] 0.25"',
                '            "vaxis" "[0 -1 0 0] 0.25"',
                '            "rotation" "0"',
                '            "lightmapscale" "16"',
                '            "smoothing_groups" "0"',
                '        }'
            ))
            $sideId++
        }
        $lines.AddRange([string[]]@(
            '    }',
            '}'
        ))
        $entityId = $sideId

        $barricadeProps = @(
            @{ model = 'models/props/de_nuke/car_nuke_red.mdl'; across = -192; outward = -32; z = 44; yaw = 339 },
            @{ model = 'models/props/de_nuke/car_nuke_glass.mdl'; across = -192.499; outward = -30.74; z = 42.898; yaw = 339 },
            @{ model = 'models/props/de_nuke/car_nuke_glass.mdl'; across = 192.233; outward = -65.31; z = 42.898; yaw = 152 },
            @{ model = 'models/props/de_nuke/car_nuke_red.mdl'; across = 191.892; outward = -64; z = 44; yaw = 152 }
        )
        foreach ($index in 0..($barricadeProps.Count - 1)) {
            $prop = $barricadeProps[$index]
            $placement = Convert-NorthGateOffset $gate $prop.across $prop.outward $prop.yaw
            $lines.AddRange([string[]]@(
                'entity',
                '{',
                ('    "id" "{0}"' -f $entityId),
                '    "classname" "prop_static"',
                ('    "targetname" "zm_transition_gate_{0}_barricade_{1}"' -f $gate.direction, $index),
                ('    "angles" "0 {0} 0"' -f $placement.yaw),
                '    "fademindist" "-1"',
                '    "fadescale" "1"',
                '    "lightmapresolutionx" "32"',
                '    "lightmapresolutiony" "32"',
                ('    "model" "{0}"' -f $prop.model),
                '    "skin" "0"',
                '    "solid" "6"',
                ('    "origin" "{0} {1} {2}"' -f $placement.x, $placement.y, $prop.z),
                '}'
            ))
            $entityId++
        }

    }
    foreach ($anchor in $CubemapAnchors) {
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "env_cubemap"',
            ('    "origin" "{0} {1} {2}"' -f $anchor.x, $anchor.y, $anchor.z),
            '}'
        ))
        $entityId++
    }

    return $baseVmf.Insert($cameraMatch.Index, (($lines -join [Environment]::NewLine) + [Environment]::NewLine))
}

$recipes = @($plan.cells |
    Group-Object cellTemplateFilename |
    Sort-Object Name |
    ForEach-Object { $_.Group[0] })
$requiredRecipeNames = @{}
foreach ($recipe in $recipes) {
    $requiredRecipeNames[$recipe.cellTemplateFilename.ToLowerInvariant()] = $true
}
$safeZoneMapNames = @{}
$safeZoneSourceMaps = @{}
foreach ($safeZoneMap in $safeZoneMaps) {
    $mapFilename = [string]$safeZoneMap.mapFilename
    $templateFilename = [string]$safeZoneMap.templateFilename
    if ([System.IO.Path]::GetFileName($mapFilename) -ne $mapFilename -or [System.IO.Path]::GetExtension($mapFilename) -ine '.vmf') {
        throw "Standalone safe-zone map filename must be a .vmf filename without a path: $mapFilename"
    }
    if ([System.IO.Path]::GetFileName($templateFilename) -ne $templateFilename -or [System.IO.Path]::GetExtension($templateFilename) -ine '.vmf') {
        throw "Standalone safe-zone template must be a .vmf filename without a path: $templateFilename"
    }
    $mapFilenameKey = $mapFilename.ToLowerInvariant()
    if ($requiredRecipeNames.ContainsKey($mapFilenameKey)) {
        throw "Standalone safe-zone map filename conflicts with a city recipe source map: $mapFilename"
    }
    if ($safeZoneSourceMaps.ContainsKey($mapFilenameKey)) {
        $existingTemplateFilename = [string]$safeZoneSourceMaps[$mapFilenameKey].templateFilename
        if (-not [string]::Equals($existingTemplateFilename, $templateFilename, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Standalone safe-zone map '$mapFilename' references conflicting templates: $existingTemplateFilename and $templateFilename"
        }
        continue
    }
    $safeZoneMapNames[$mapFilenameKey] = $true
    $safeZoneSourceMaps[$mapFilenameKey] = $safeZoneMap
}
$created = 0
$refreshed = 0
$skipped = 0
$pruned = 0
$safeZoneMapsWritten = 0
$safeZoneMapsSkipped = 0
$prunedStandaloneDenMaps = 0
$cubemapProbeCount = 0
$cubemapProbeReport = [System.Collections.Generic.List[string]]::new()
if ($PruneStaleGenerated) {
    foreach ($existingVmf in (Get-ChildItem -Path $CellDirectory -Filter '*.vmf' -File)) {
        if ($requiredRecipeNames.ContainsKey($existingVmf.Name.ToLowerInvariant()) -or -not (Test-GeneratedCellVmf $existingVmf.FullName)) {
            continue
        }
        if (-not $WhatIf) {
            Remove-Item -LiteralPath $existingVmf.FullName
        }
        $pruned++
    }
}
if ($RefreshGenerated -or $Force -or $PruneStaleGenerated) {
    foreach ($existingDenMap in (Get-ChildItem -Path $CellDirectory -Filter 'zn_den_*' -File)) {
        if ($safeZoneMapNames.ContainsKey([System.IO.Path]::ChangeExtension($existingDenMap.Name, '.vmf').ToLowerInvariant())) {
            continue
        }
        if (-not $WhatIf) {
            Remove-Item -LiteralPath $existingDenMap.FullName -Force
        }
        $prunedStandaloneDenMaps++
    }
}
foreach ($recipe in $recipes) {
    $outputPath = Join-Path $CellDirectory $recipe.cellTemplateFilename
    Test-RecipeTilePlacements $recipe $plan.cellTileGridSize
    $expectedInteriorInstanceCount = Get-RecipeInteriorInstanceCount $recipe
    $cubemapAnchors = Get-CubemapAnchors $recipe $plan.cellTileGridSize $TileSize $TileZOffset
    $borderPlacements = Get-BorderPlacements $recipe $plan.cellTileGridSize
    $transitionGates = @(Get-TransitionGatePlacements $recipe)
    $expectedBorderInstanceCount = $borderPlacements.Count
    $cubemapProbeCount += $cubemapAnchors.Count
    if ($WhatIf) {
        $cubemapProbeReport.Add("Cubemap probes: $($recipe.cellTemplateFilename) = $($cubemapAnchors.Count)")
    }
    if ((Test-Path $outputPath) -and -not $Force) {
        if (-not $RefreshGenerated -or -not (Test-GeneratedCellVmf $outputPath $expectedInteriorInstanceCount $expectedBorderInstanceCount $transitionGates.Count)) {
            $skipped++
            continue
        }
        $refreshed++
    }

    $vmf = New-CellVmf $recipe $plan.cellTileGridSize $TileSize $TileZOffset $CellDirectory $TileDirectory $BaseCellTemplate $cubemapAnchors $borderPlacements
    if (-not $WhatIf) {
        [System.IO.File]::WriteAllText($outputPath, $vmf, [System.Text.UTF8Encoding]::new($false))
        if (-not (Test-GeneratedCellVmf $outputPath $expectedInteriorInstanceCount $expectedBorderInstanceCount $transitionGates.Count)) {
            throw "Generated VMF failed border structure validation: $outputPath"
        }
    }
    $created++
}

foreach ($safeZoneMap in ($safeZoneSourceMaps.Values | Sort-Object mapFilename)) {
    $templateVmfPath = Join-Path $safeZoneTemplateDirectory $safeZoneMap.templateFilename
    $outputVmfPath = Join-Path $CellDirectory $safeZoneMap.mapFilename
    if (-not (Test-Path -LiteralPath $templateVmfPath -PathType Leaf)) {
        throw "Standalone safe-zone template was not found: $templateVmfPath"
    }
    if ((Test-Path -LiteralPath $outputVmfPath -PathType Leaf) -and -not ($Force -or $RefreshGenerated)) {
        $safeZoneMapsSkipped++
        continue
    }

    if (-not $WhatIf) {
        Copy-Item -LiteralPath $templateVmfPath -Destination $outputVmfPath -Force
        $templateVmxPath = [System.IO.Path]::ChangeExtension($templateVmfPath, '.vmx')
        if (Test-Path -LiteralPath $templateVmxPath -PathType Leaf) {
            $outputVmxPath = Join-Path $CellDirectory ([System.IO.Path]::ChangeExtension([string]$safeZoneMap.mapFilename, '.vmx'))
            Copy-Item -LiteralPath $templateVmxPath -Destination $outputVmxPath -Force
        }
    }
    $safeZoneMapsWritten++
}

if ($WhatIf) {
    foreach ($line in $cubemapProbeReport) {
        Write-Output $line
    }
}
Write-Output "Cell recipes: $($recipes.Count); cubemap probes: $cubemapProbeCount; written: $created; refreshed generated: $refreshed; skipped existing: $skipped; safe-room entrances: $($safeZoneMaps.Count); reusable safe-room maps: $($safeZoneSourceMaps.Count); maps copied: $safeZoneMapsWritten; maps skipped: $safeZoneMapsSkipped; pruned stale safe-room files: $prunedStandaloneDenMaps; pruned stale generated: $pruned; cleared source items: $clearedItems; output: $CellDirectory"