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
Import-Module (Join-Path $PSScriptRoot 'ps_progress_utils.psm1') -Force
$projectRoot = Split-Path -Parent $PSScriptRoot
Write-ZMProgress -Activity 'Building cell VMFs' -Status 'Loading recipe plan and source template inventory.' -PercentComplete 2 -Step 'setup'
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$generatorSettings = $worldGenerationProfile.Settings
$profileSettings = $worldGenerationProfile.Config
if (-not $PSBoundParameters.ContainsKey('TileSize')) { $TileSize = [int]$generatorSettings.vmfBuild.tileSize }
if (-not $PSBoundParameters.ContainsKey('TileZOffset')) { $TileZOffset = [int]$generatorSettings.vmfBuild.tileZOffset }
$vmfBuildSettings = $generatorSettings.vmfBuild
$borderSettings = if ($vmfBuildSettings.ContainsKey('border')) { $vmfBuildSettings.border } else { @{} }
$borderEnabled = $borderSettings.ContainsKey('enabled') -and [bool]$borderSettings.enabled
$topologyTemplates = $generatorSettings.cellPlanning.topologyTemplates
$transportTemplates = $generatorSettings.cellPlanning.transportTemplates
if (-not $PSBoundParameters.ContainsKey('PruneStaleGenerated')) { $PruneStaleGenerated = $true }
Import-Module (Join-Path $PSScriptRoot 'carpark_endcaps.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force

# Writes the shared 3D skybox room (sealed sky shell, ground plane, sky_camera) above the playable cell volume and
# returns its repository-relative path. It holds no props: cl_skybox.lua draws each cell's neighbour models at runtime.
function Write-SkyboxRoomVmf {
    param([hashtable]$Settings, [string]$ProfileName, [int]$TileGridSize, [int]$TileWidth, [double]$PlayableShellTop)

    $scale = if ($Settings.ContainsKey('scale')) { [int]$Settings.scale } else { 16 }
    $radius = if ($Settings.ContainsKey('neighbourRadius')) { [int]$Settings.neighbourRadius } else { 2 }
    $skylineRadius = if ($Settings.ContainsKey('skylineRadius')) { [int]$Settings.skylineRadius } else { $radius }
    if ($skylineRadius -lt $radius) { throw 'skybox3d skylineRadius must be at least neighbourRadius.' }
    $cameraZ = if ($Settings.ContainsKey('cameraZ')) { [int]$Settings.cameraZ } else { 3328 }
    $roomHeight = if ($Settings.ContainsKey('roomHeight')) { [int]$Settings.roomHeight } else { 512 }
    $groundMaterial = if ($Settings.ContainsKey('groundMaterial')) { [string]$Settings.groundMaterial } else { 'CS_HAVANA/SWAMPDIRT01' }
    if ($scale -lt 1 -or $radius -lt 1) { throw 'vmfBuild.skybox3d scale and neighbourRadius must be positive.' }
    $cellSpan = ($TileGridSize + 2) * $TileWidth
    # Neighbour models sit inside the room so their lighting origins resolve to a lit sky leaf. Every vertical room
    # plane lies on VBSP's 1024-unit block grid: off-grid planes become splitters that cut the playable cell's leaves
    # and add portals (measured +36 portals on zz_preview_594c1fb8277a with walls at +/-768 and +/-784).
    $roomHalf = [int]([math]::Ceiling((($skylineRadius + 0.5) * $cellSpan / $scale + 64) / 1024.0) * 1024)
    $roomBottom = $cameraZ - 64
    $roomTop = $cameraZ + $roomHeight
    if ($roomBottom - 16 -le $PlayableShellTop) { throw "vmfBuild.skybox3d.cameraZ $cameraZ places the skybox room inside the playable cell volume (shell top $PlayableShellTop)." }
    if ($roomTop + 16 -gt 16384 -or $roomHalf + 1024 -gt 16384) { throw 'The skybox room exceeds the Source coordinate limit.' }

    $script:skyboxVmfId = 1
    $newBox = {
        param([double]$X0, [double]$Y0, [double]$Z0, [double]$X1, [double]$Y1, [double]$Z1, [string]$Material)
        $faces = @(
            @("($X0 $Y1 $Z1) ($X1 $Y1 $Z1) ($X1 $Y0 $Z1)", '[1 0 0 0] 0.25', '[0 -1 0 0] 0.25'),
            @("($X0 $Y0 $Z0) ($X1 $Y0 $Z0) ($X1 $Y1 $Z0)", '[1 0 0 0] 0.25', '[0 -1 0 0] 0.25'),
            @("($X0 $Y1 $Z1) ($X0 $Y0 $Z1) ($X0 $Y0 $Z0)", '[0 1 0 0] 0.25', '[0 0 -1 0] 0.25'),
            @("($X1 $Y0 $Z1) ($X1 $Y1 $Z1) ($X1 $Y1 $Z0)", '[0 1 0 0] 0.25', '[0 0 -1 0] 0.25'),
            @("($X1 $Y1 $Z1) ($X0 $Y1 $Z1) ($X0 $Y1 $Z0)", '[1 0 0 0] 0.25', '[0 0 -1 0] 0.25'),
            @("($X0 $Y0 $Z1) ($X1 $Y0 $Z1) ($X1 $Y0 $Z0)", '[1 0 0 0] 0.25', '[0 0 -1 0] 0.25')
        )
        $box = [System.Collections.Generic.List[string]]::new()
        $box.Add("`tsolid"); $box.Add("`t{"); $box.Add("`t`t`"id`" `"$($script:skyboxVmfId)`""); $script:skyboxVmfId++
        foreach ($face in $faces) {
            $box.Add("`t`tside"); $box.Add("`t`t{")
            $box.Add("`t`t`t`"id`" `"$($script:skyboxVmfId)`""); $script:skyboxVmfId++
            $box.Add("`t`t`t`"plane`" `"$($face[0])`"")
            $box.Add("`t`t`t`"material`" `"$Material`"")
            $box.Add("`t`t`t`"uaxis`" `"$($face[1])`"")
            $box.Add("`t`t`t`"vaxis`" `"$($face[2])`"")
            $box.Add("`t`t`t`"rotation`" `"0`""); $box.Add("`t`t`t`"lightmapscale`" `"64`""); $box.Add("`t`t`t`"smoothing_groups`" `"0`"")
            $box.Add("`t`t}")
        }
        $box.Add("`t}")
        return $box
    }

    $w = 16
    $o = $roomHalf + 1024
    $sky = 'TOOLS/TOOLSSKYBOX'
    $vmf = [System.Collections.Generic.List[string]]::new()
    $vmf.Add('versioninfo'); $vmf.Add('{'); $vmf.Add("`t`"editorversion`" `"400`""); $vmf.Add("`t`"formatversion`" `"100`""); $vmf.Add("`t`"prefab`" `"0`""); $vmf.Add('}')
    $vmf.Add('world'); $vmf.Add('{'); $vmf.Add("`t`"id`" `"$($script:skyboxVmfId)`""); $script:skyboxVmfId++
    $vmf.Add("`t`"mapversion`" `"1`""); $vmf.Add("`t`"classname`" `"worldspawn`""); $vmf.Add("`t`"skyname`" `"sky_day01_01`"")
    $vmf.AddRange([string[]](& $newBox (-$o) (-$o) ($roomBottom - $w) $o $o $roomBottom $sky))
    $vmf.AddRange([string[]](& $newBox (-$o) (-$o) $roomTop $o $o ($roomTop + $w) $sky))
    $vmf.AddRange([string[]](& $newBox (-$o) (-$o) $roomBottom (-$roomHalf) $o $roomTop $sky))
    $vmf.AddRange([string[]](& $newBox $roomHalf (-$o) $roomBottom $o $o $roomTop $sky))
    $vmf.AddRange([string[]](& $newBox (-$roomHalf) (-$o) $roomBottom $roomHalf (-$roomHalf) $roomTop $sky))
    $vmf.AddRange([string[]](& $newBox (-$roomHalf) $roomHalf $roomBottom $roomHalf $o $roomTop $sky))
    # Seabed below cl_skybox.lua's coast sea level (-3 sky units). Neighbour models cover every in-grid slot, so this is
    # only seen through the sea beyond the world edge.
    $vmf.AddRange([string[]](& $newBox (-$roomHalf) (-$roomHalf) $roomBottom $roomHalf $roomHalf ($cameraZ - 24) $groundMaterial))
    $vmf.Add('}')
    # cl_atmosphere.lua replaces this fog every frame through SetupSkyboxFog.
    $vmf.Add('entity'); $vmf.Add('{'); $vmf.Add("`t`"id`" `"$($script:skyboxVmfId)`""); $script:skyboxVmfId++
    $vmf.Add("`t`"classname`" `"sky_camera`""); $vmf.Add("`t`"origin`" `"0 0 $cameraZ`""); $vmf.Add("`t`"angles`" `"0 0 0`"")
    $vmf.Add("`t`"scale`" `"$scale`""); $vmf.Add("`t`"fogenable`" `"1`""); $vmf.Add("`t`"fogblend`" `"0`""); $vmf.Add("`t`"use_angles`" `"0`"")
    $vmf.Add("`t`"fogcolor`" `"128 128 128`""); $vmf.Add("`t`"fogcolor2`" `"128 128 128`""); $vmf.Add("`t`"fogdir`" `"1 0 0`"")
    $vmf.Add("`t`"fogstart`" `"200`""); $vmf.Add("`t`"fogend`" `"2000`""); $vmf.Add("`t`"fogmaxdensity`" `"1`"")
    $vmf.Add('}')

    $relativePath = "generated\skybox_$ProfileName\skybox_room.vmf"
    $roomPath = Join-Path $projectRoot $relativePath
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $roomPath)
    $null = Write-TextFileIfChanged -Path $roomPath -Content (($vmf -join "`r`n") + "`r`n")
    return $relativePath
}

if ($borderEnabled) {
    if (-not $borderSettings.ContainsKey('wallVariationTemplates') -or @($borderSettings.wallVariationTemplates).Count -eq 0) {
        throw 'vmfBuild.border must define at least one wallVariationTemplates entry when borders are enabled.'
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
# Every city recipe carries the same 3D skybox room; cl_skybox.lua draws the current cell's neighbours inside it.
$skyboxSettings = if ($vmfBuildSettings.ContainsKey('skybox3d')) { $vmfBuildSettings.skybox3d } else { @{} }
$skyboxEnabled = $skyboxSettings.ContainsKey('enabled') -and [bool]$skyboxSettings.enabled
$skyboxRoomTemplate = ''
$safeZoneMaps = @($plan.safeZoneMaps)
$safeZoneTemplateDirectory = [string]$plan.safeZoneTemplateDirectory
if ($safeZoneMaps.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($safeZoneTemplateDirectory) -or -not (Test-Path -LiteralPath $safeZoneTemplateDirectory -PathType Container))) {
    throw 'The template plan defines standalone safe-zone maps but has no valid safeZoneTemplateDirectory. Re-run plan_cell_templates.ps1.'
}

$waterSettings = if ($borderSettings.ContainsKey('water')) { $borderSettings.water } else { @{} }
$waterEnabled = $borderEnabled -and $waterSettings.ContainsKey('enabled') -and [bool]$waterSettings.enabled
$waterPierInterval = [Math]::Max(1, $(if ($waterSettings.ContainsKey('pierEveryTiles')) { [int]$waterSettings.pierEveryTiles } else { 3 }))
if ($waterEnabled -and (-not $waterSettings.ContainsKey('deadendTemplate') -or -not $waterSettings.ContainsKey('noneTemplate') -or -not $waterSettings.ContainsKey('cornerTemplate') -or @($waterSettings.pierTemplates).Count -eq 0)) {
    throw 'vmfBuild.border.water must define deadendTemplate, noneTemplate, cornerTemplate, and at least one pierTemplates entry when enabled.'
}

function Get-WaterBorderPlan {
    param([object]$Recipe)

    $sides = @{}
    if (-not $waterEnabled) { return $sides }
    foreach ($entry in @($Recipe.waterBorderSides)) {
        $sides[[string]$entry.side] = [pscustomobject]@{ isFarTip = [bool]$entry.isFarTip }
    }
    return $sides
}

function Get-WaterWallTemplate {
    param([int]$Index)

    $pierTemplates = @($waterSettings.pierTemplates)
    if (($Index % $waterPierInterval) -eq 0) {
        return [string]$pierTemplates[[int](($Index / $waterPierInterval) % $pierTemplates.Count)]
    }
    return [string]$waterSettings.noneTemplate
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
if ($skyboxEnabled) {
    $baseContents = Get-Content -Raw -LiteralPath $BaseCellTemplate
    $basePlaneHeights = @(
        foreach ($plane in [regex]::Matches($baseContents, '"plane"\s+"([^"]+)"')) {
            foreach ($point in [regex]::Matches($plane.Groups[1].Value, '\(([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\)')) {
                [double]::Parse($point.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
    )
    if ($basePlaneHeights.Count -eq 0) { throw "Base cell template has no brush planes: $BaseCellTemplate" }
    $playableShellTop = ($basePlaneHeights | Measure-Object -Maximum).Maximum
    $skyboxRoomTemplate = Write-SkyboxRoomVmf $skyboxSettings ([string]$profileSettings.filePrefix) ([int]$plan.cellTileGridSize) $TileSize $playableShellTop
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
    $suppressedInterior = @($placements | Where-Object { $_.role -eq 'safezone_entrance_occupied' })
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

    if ($ownerByCoordinate.Count + $suppressedInterior.Count -ne $expectedTileCount) {
        throw "$($Recipe.cellTemplateFilename) covers $($ownerByCoordinate.Count) interior tiles plus $($suppressedInterior.Count) entrance tiles; expected $expectedTileCount."
    }
    foreach ($key in $placementByCoordinate.Keys) {
        $occupancyRecord = $placementByCoordinate[$key]
        if ($occupancyRecord.role -eq 'safezone_entrance_occupied') { continue }
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

# VBSP remaps instance entity origins/angles only for classes in the game's FGD (garrysmod.fgd), so ZombieSim point
# entities inside a func_instance keep their template-local coordinates. Re-emit them here in cell space, flagged
# with zm_instance_transformed so the runtime ignores the untransformed copies VBSP still merges.
$instanceTransformedClasses = @('zn_safezone_door', 'zn_safezone_arrival')

function Get-TransformedInstancePointEntities {
    param(
        [string]$TemplatePath,
        [double]$OriginX,
        [double]$OriginY,
        [double]$OriginZ,
        [int]$Yaw,
        [int]$FirstEntityId
    )

    $contents = Get-Content -Raw $TemplatePath
    $radians = $Yaw * [Math]::PI / 180.0
    $cosine = [Math]::Round([Math]::Cos($radians), 10)
    $sine = [Math]::Round([Math]::Sin($radians), 10)
    $lines = [System.Collections.Generic.List[string]]::new()
    $entityId = $FirstEntityId
    foreach ($match in [regex]::Matches($contents, '(?ms)^entity\r?\n\{\r?\n(.*?)^\}')) {
        $body = $match.Groups[1].Value
        $classMatch = [regex]::Match($body, '(?m)^\s*"classname" "([^"]+)"')
        if (-not $classMatch.Success -or $instanceTransformedClasses -notcontains $classMatch.Groups[1].Value) { continue }
        $keyValues = [ordered]@{}
        $editorStart = [regex]::Match($body, '(?m)^\s*editor\s*$')
        $keyText = if ($editorStart.Success) { $body.Substring(0, $editorStart.Index) } else { $body }
        foreach ($pair in [regex]::Matches($keyText, '(?m)^\s*"([^"]+)" "([^"]*)"')) {
            $keyValues[$pair.Groups[1].Value] = $pair.Groups[2].Value
        }
        $origin = @(([string]$keyValues['origin']) -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { [double]$_ })
        if ($origin.Count -ne 3) {
            throw "$($classMatch.Groups[1].Value) in $TemplatePath has no valid origin."
        }
        $angles = @(([string]$(if ($keyValues.Contains('angles')) { $keyValues['angles'] } else { '0 0 0' })) -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { [double]$_ })
        if ($angles.Count -ne 3) { $angles = @(0.0, 0.0, 0.0) }
        $worldX = $OriginX + $origin[0] * $cosine - $origin[1] * $sine
        $worldY = $OriginY + $origin[0] * $sine + $origin[1] * $cosine
        $worldZ = $OriginZ + $origin[2]
        $worldYaw = (($angles[1] + $Yaw) % 360 + 360) % 360
        $lines.Add('entity')
        $lines.Add('{')
        $lines.Add(('    "id" "{0}"' -f $entityId))
        foreach ($key in $keyValues.Keys) {
            if ($key -in @('id', 'origin', 'angles')) { continue }
            $lines.Add(('    "{0}" "{1}"' -f $key, $keyValues[$key]))
        }
        $lines.Add([string]::Format([Globalization.CultureInfo]::InvariantCulture, '    "origin" "{0:0.###} {1:0.###} {2:0.###}"', $worldX, $worldY, $worldZ))
        $lines.Add([string]::Format([Globalization.CultureInfo]::InvariantCulture, '    "angles" "{0:0.###} {1:0.###} {2:0.###}"', $angles[0], $worldYaw, $angles[2]))
        $lines.Add('    "zm_instance_transformed" "1"')
        $lines.Add('}')
        $entityId++
    }
    return [pscustomobject]@{ Lines = $lines; NextEntityId = $entityId }
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
    $expectedBorderCount = if ($ExpectedBorderInstanceCount -ge 0) { $ExpectedBorderInstanceCount } elseif ($borderEnabled) { 24 } else { 0 }
    if ($ExpectedInteriorInstanceCount -ge 0) {
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
        $instanceCount -gt 0 -and
        [regex]::Matches($contents, '"targetname" "(?:zm_border_|zm_transition_road_)').Count -eq $expectedBorderCount
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

    $wallTemplates = @($borderSettings.wallVariationTemplates)
    $cornerTemplate = [string]$borderSettings.cornerTemplate
    $profile = ([string]$Recipe.environmentProfile).ToLowerInvariant()
    if ($borderSettings.ContainsKey('profileTemplates') -and $borderSettings.profileTemplates.ContainsKey($profile)) {
        $profileTemplates = $borderSettings.profileTemplates[$profile]
        if ($profileTemplates.ContainsKey('wallVariationTemplates') -and @($profileTemplates.wallVariationTemplates).Count -gt 0) {
            $wallTemplates = @($profileTemplates.wallVariationTemplates)
        }
        if ($profileTemplates.ContainsKey('cornerTemplate') -and -not [string]::IsNullOrWhiteSpace([string]$profileTemplates.cornerTemplate)) {
            $cornerTemplate = [string]$profileTemplates.cornerTemplate
        }
    }

    return [ordered]@{
        wallTemplates = $wallTemplates
        cornerTemplate = $cornerTemplate
    }
}

function Get-RandomWallVariationTemplate {
    param([string[]]$WallTemplates, [int64]$PlacementSeed, [int]$TileX, [int]$TileY)

    if ($WallTemplates.Count -eq 1) { return $WallTemplates[0] }
    $hash = ([int64]$PlacementSeed * 2654435761) -bxor ([int64]$TileX * 73856093) -bxor ([int64]$TileY * 19349663)
    $hash = $hash -bxor ($hash -shr 15)
    return $WallTemplates[[int]([Math]::Abs($hash) % $WallTemplates.Count)]
}

function Get-BorderPlacements {
    param([object]$Recipe, [int]$TileGridSize)

    if (-not $borderEnabled) { return @() }

    $edgeConnections = @(Get-RecipeEdgeConnections $Recipe)
    $rampExits = @($Recipe.rampExits | Where-Object { $_ -in @('N', 'E', 'S', 'W') } | Sort-Object -Unique)
    $isMotorway = ([string]$Recipe.topology).ToLowerInvariant() -like 'motorway-*'
    $primaryRoadTemplate = if ($isMotorway) { [string]$topologyTemplates['motorway-straight'] } else { [string]$topologyTemplates['road-straight'] }
    $rampRoadTemplate = [string]$topologyTemplates['road-straight']
    $bridgeRoadTemplate = [string]$transportTemplates.bridgeRoad
    $transportFeature = [string]$Recipe.transportFeature
    $bridgeSides = if ($transportFeature -eq 'bridge-vertical') { @('N', 'S') } elseif ($transportFeature -eq 'bridge-horizontal') { @('E', 'W') } elseif ($transportFeature -like 'bridge-ramp-*') { @($transportFeature.Substring('bridge-ramp-'.Length, 1).ToUpperInvariant()) } else { @() }
    $transitionGateRoadTemplates = @($borderSettings.transitionGateRoadTemplates | ForEach-Object { [string]$_ })
    $placementSeed = [Math]::Abs([int64]$Recipe.placementSeed)
    $borderTemplates = Get-BorderTemplateSet $Recipe
    $waterSides = Get-WaterBorderPlan $Recipe
    $center = [int][Math]::Floor($TileGridSize / 2)
    $carparkEndcapsByBorderSlot = @{}
    foreach ($endcap in @(Get-CarparkEndcapPlacements -Recipe $Recipe -TileGridSize $TileGridSize -CarparkTemplates $generatorSettings.cellPlanning.carparks.templates)) {
        $carparkEndcapsByBorderSlot["$($endcap.tileX),$($endcap.tileY)"] = $endcap
    }
    $suppressedBorder = @{}
    $suppressedTilesProperty = $Recipe.PSObject.Properties['suppressedBorderTiles']
    $suppressedTiles = if ($null -ne $suppressedTilesProperty) { @($suppressedTilesProperty.Value) } else { @() }
    foreach ($tile in $suppressedTiles) {
        $key = "$([int]$tile.tileX),$([int]$tile.tileY)"
        if ($suppressedBorder.ContainsKey($key) -or $carparkEndcapsByBorderSlot.ContainsKey($key)) {
            throw "Safe-zone entrance conflicts with a carpark endcap or repeated border tile at $key in $($Recipe.cellTemplateFilename)."
        }
        $suppressedBorder[$key] = $true
    }
    $wallYawBySide = @{ N = 270; E = 180; S = 90; W = 0 }
    $waterDeadendYawBySide = @{ N = 180; E = 90; S = 0; W = 270 }
    $cornerYawByPosition = @{ 'N-W' = 0; 'N-E' = 270; 'S-E' = 180; 'S-W' = 90 }
    $roadYawBySide = @{ N = 0; E = 90; S = 0; W = 90 }
    $placements = [System.Collections.Generic.List[object]]::new()

    for ($tileY = -1; $tileY -le $TileGridSize; $tileY++) {
        for ($tileX = -1; $tileX -le $TileGridSize; $tileX++) {
            $isOuterRow = $tileY -eq -1 -or $tileY -eq $TileGridSize
            $isOuterColumn = $tileX -eq -1 -or $tileX -eq $TileGridSize
            if (-not ($isOuterRow -or $isOuterColumn)) { continue }
            if ($suppressedBorder.ContainsKey("$tileX,$tileY")) { continue }

            $isCorner = $isOuterRow -and $isOuterColumn
            if ($isCorner) {
                $northSouth = if ($tileY -eq -1) { 'N' } else { 'S' }
                $eastWest = if ($tileX -eq -1) { 'W' } else { 'E' }
                $cornerKey = "$northSouth-$eastWest"
                $isWaterCorner = $waterSides.ContainsKey($northSouth) -and $waterSides.ContainsKey($eastWest)
                $placements.Add([ordered]@{
                    tileX = $tileX
                    tileY = $tileY
                    template = if ($isWaterCorner) { [string]$waterSettings.cornerTemplate } else { $borderTemplates.cornerTemplate }
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
                $transitionGateRoadTemplate = $transitionGateRoadTemplates[($placementSeed + $sideIndex) % $transitionGateRoadTemplates.Count]
            }
            $carparkEndcap = $carparkEndcapsByBorderSlot["$tileX,$tileY"]
            $isBridgeSide = $usesRoad -and ($side -in $bridgeSides)
            $usesWaterSide = -not $usesRoad -and $null -eq $carparkEndcap -and $waterSides.ContainsKey($side)
            $waterIndex = if ($side -in @('N', 'S')) { $tileX } else { $tileY }
            $waterPlan = if ($usesWaterSide) { $waterSides[$side] } else { $null }
            # Only the single center slot caps the run; the rest of a tip cell's side is plain wall, not a repeating water strip.
            $usesWaterDeadend = $usesWaterSide -and $waterPlan.isFarTip -and $isCenterEdgeSlot
            $usesWaterFill = $usesWaterSide -and -not $waterPlan.isFarTip
            $placements.Add([ordered]@{
                tileX = $tileX
                tileY = $tileY
                template = if ($isBridgeSide) { $bridgeRoadTemplate } elseif ($usesTransitionGateRoad) { $transitionGateRoadTemplate } elseif ($usesRampRoad) { $rampRoadTemplate } elseif ($usesPrimaryRoad) { $primaryRoadTemplate } elseif ($null -ne $carparkEndcap) { $carparkEndcap.template } elseif ($usesWaterDeadend) { [string]$waterSettings.deadendTemplate } elseif ($usesWaterFill) { Get-WaterWallTemplate $waterIndex } else { Get-RandomWallVariationTemplate $borderTemplates.wallTemplates $placementSeed $tileX $tileY }
                rotationYaw = if ($usesRoad) { $roadYawBySide[$side] } elseif ($null -ne $carparkEndcap) { $carparkEndcap.rotationYaw } elseif ($usesWaterDeadend) { $waterDeadendYawBySide[$side] } else { $wallYawBySide[$side] }
                targetname = if ($usesTransitionGateRoad) { "zm_transition_road_$side" } else { "zm_border_$side`_$tileX`_$tileY" }
            })
        }
    }

    $expectedCount = (($TileGridSize + 2) * ($TileGridSize + 2)) - ($TileGridSize * $TileGridSize)
    $expectedCount -= $suppressedBorder.Count
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

function Set-CellPlayerStart {
    param(
        [string]$Vmf,
        [object]$Recipe,
        [int]$TileGridSize,
        [int]$TileWidth
    )

    $playerStartIndex = $Vmf.IndexOf('"classname" "info_player_start"', [System.StringComparison]::Ordinal)
    if ($playerStartIndex -lt 0) { throw 'Base cell template must contain an info_player_start entity.' }

    $centerTile = [int][Math]::Floor($TileGridSize / 2)
    $terrainTiles = @($Recipe.tilePlacements | Where-Object { $_.role -eq 'terrain' } | Sort-Object `
        @{ Expression = { [Math]::Abs([int]$_.tileX - $centerTile) + [Math]::Abs([int]$_.tileY - $centerTile) } },
        @{ Expression = { [int]$_.tileY } },
        @{ Expression = { [int]$_.tileX } })
    if ($terrainTiles.Count -eq 0) { throw "Recipe '$($Recipe.cellTemplateFilename)' has no unobstructed terrain tile for the player start." }

    $spawnTile = $terrainTiles[0]
    $spawnX = [int](([int]$spawnTile.tileX - $centerTile) * $TileWidth)
    $spawnY = [int](($centerTile - [int]$spawnTile.tileY) * $TileWidth)
    $originPropertyIndex = $Vmf.IndexOf('"origin"', $playerStartIndex, [System.StringComparison]::Ordinal)
    if ($originPropertyIndex -lt 0) { throw 'Base cell info_player_start must define an origin.' }
    $originMatch = [regex]::Match($Vmf.Substring($originPropertyIndex), '^"origin"\s+"(?<origin>-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?)"')
    if (-not $originMatch.Success) { throw 'Base cell info_player_start must define a numeric origin.' }
    $sourceCoordinates = @($originMatch.Groups['origin'].Value -split '\s+')
    $spawnOrigin = '{0} {1} {2}' -f $spawnX, $spawnY, $sourceCoordinates[2]
    $updatedOrigin = '"origin" "{0}"' -f $spawnOrigin
    $absoluteLength = $originMatch.Length
    return $Vmf.Substring(0, $originPropertyIndex) + $updatedOrigin + $Vmf.Substring($originPropertyIndex + $absoluteLength)
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
        [object[]]$BorderPlacements,
        [string]$SkyboxRoomTemplate
    )

    $placements = @($Recipe.tilePlacements)
    Test-RecipeTilePlacements $Recipe $TileGridSize

    $baseVmf = Get-Content -Raw $BaseTemplatePath
    $baseVmf = Remove-TemplateCubemaps $baseVmf
    $baseVmf = Set-VmfLightingProfile $baseVmf (Get-RecipeLightingProfile $Recipe)
    $baseVmf = Set-CellPlayerStart $baseVmf $Recipe $TileGridSize $TileWidth
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
    if (-not [string]::IsNullOrWhiteSpace($SkyboxRoomTemplate)) {
        $instancePath = Get-VmfInstancePath $SourceDirectory $projectRoot $SkyboxRoomTemplate
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "func_instance"',
            '    "origin" "0 0 0"',
            '    "angles" "0 0 0"',
            ('    "file" "{0}"' -f $instancePath),
            '    "targetname" "zm_skybox_room"',
            '    "fixup_style" "0"',
            '}'
        ))
        $entityId++
    }
    if ($null -ne $Recipe.PSObject.Properties['safeZoneEntrance'] -and $null -ne $Recipe.safeZoneEntrance) {
        $entrance = $Recipe.safeZoneEntrance
        $anchorX = [int]$entrance.anchorTile.tileX
        $anchorY = [int]$entrance.anchorTile.tileY
        $footprint = [int]$entrance.footprint
        $originX = [int](($anchorX - $center + (($footprint - 1) / 2.0)) * $TileWidth)
        $originY = [int](($center - $anchorY - (($footprint - 1) / 2.0)) * $TileWidth)
        $instancePath = Get-VmfInstancePath $SourceDirectory $TemplateDirectory ([string]$entrance.template)
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "func_instance"',
            ('    "origin" "{0} {1} {2}"' -f $originX, $originY, $TileVerticalOffset),
            ('    "angles" "0 {0} 0"' -f [int]$entrance.yaw),
            ('    "file" "{0}"' -f $instancePath),
            ('    "targetname" "zm_safezone_entrance_{0}"' -f $entrance.slot),
            '    "fixup_style" "0"',
            '}'
        ))
        $entityId++
        $transformed = Get-TransformedInstancePointEntities -TemplatePath (Join-Path $TemplateDirectory ([string]$entrance.template)) `
            -OriginX $originX -OriginY $originY -OriginZ $TileVerticalOffset -Yaw ([int]$entrance.yaw) -FirstEntityId $entityId
        if ($transformed.Lines.Count -gt 0) { $lines.AddRange([string[]]$transformed.Lines) }
        $entityId = $transformed.NextEntityId
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
$unchanged = 0
$safeZoneMapsSkipped = 0
$prunedStandaloneDenMaps = 0
$cubemapProbeCount = 0
$cubemapProbeReport = [System.Collections.Generic.List[string]]::new()
if ($PruneStaleGenerated) {
    foreach ($existingVmf in (Get-ChildItem -Path $CellDirectory -Filter '*.vmf' -File)) {
        if ($requiredRecipeNames.ContainsKey($existingVmf.Name.ToLowerInvariant()) -or -not (Test-GeneratedCellVmf $existingVmf.FullName)) {
            if ($requiredRecipeNames.ContainsKey($existingVmf.Name.ToLowerInvariant()) -or $existingVmf.Name -notlike 'zn_*.vmf') { continue }
        }
        if (-not $WhatIf) {
            Remove-Item -LiteralPath $existingVmf.FullName
        }
        $pruned++
    }
    foreach ($existingVmx in (Get-ChildItem -Path $CellDirectory -Filter 'zn_*.vmx' -File)) {
        $matchingVmf = [System.IO.Path]::ChangeExtension($existingVmx.Name, '.vmf')
        if ($requiredRecipeNames.ContainsKey($matchingVmf.ToLowerInvariant())) { continue }
        if (-not $WhatIf) {
            Remove-Item -LiteralPath $existingVmx.FullName
        }
        $pruned++
    }
}
if (($RefreshGenerated -or $Force -or $PruneStaleGenerated)) {
    foreach ($existingDenMap in (Get-ChildItem -Path $CellDirectory -File | Where-Object { $_.Name -like 'zn_den_*' -or $_.Name -like 'zz_den_*' })) {
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
    $hasSafeZoneEntrance = $null -ne $recipe.PSObject.Properties['safeZoneEntrance'] -and $null -ne $recipe.safeZoneEntrance
    $expectedInteriorInstanceCount = (Get-RecipeInteriorInstanceCount $recipe) +
        $(if ($hasSafeZoneEntrance) { 1 } else { 0 }) +
        $(if ($skyboxEnabled) { 1 } else { 0 })
    $cubemapAnchors = Get-CubemapAnchors $recipe $plan.cellTileGridSize $TileSize $TileZOffset
    $borderPlacements = Get-BorderPlacements $recipe $plan.cellTileGridSize
    $transitionGates = @(Get-TransitionGatePlacements $recipe)
    $expectedBorderInstanceCount = $borderPlacements.Count
    $cubemapProbeCount += $cubemapAnchors.Count
    if ($WhatIf) {
        $cubemapProbeReport.Add("Cubemap probes: $($recipe.cellTemplateFilename) = $($cubemapAnchors.Count)")
    }
    if ((Test-Path $outputPath) -and -not $Force) {
        $matchesExpectedStructure = Test-GeneratedCellVmf $outputPath $expectedInteriorInstanceCount $expectedBorderInstanceCount $transitionGates.Count
        # A recipe written before the skybox room was enabled or disabled differs only by that one instance.
        $skyboxToggledCount = $expectedInteriorInstanceCount + $(if ($skyboxEnabled) { -1 } else { 1 })
        $matchesSkyboxToggle = Test-GeneratedCellVmf $outputPath $skyboxToggledCount $expectedBorderInstanceCount $transitionGates.Count
        if (-not $RefreshGenerated -or (-not $matchesExpectedStructure -and -not $matchesSkyboxToggle)) {
            $skipped++
            continue
        }
        $refreshed++
    }

    $vmf = New-CellVmf $recipe $plan.cellTileGridSize $TileSize $TileZOffset $CellDirectory $TileDirectory $BaseCellTemplate $cubemapAnchors $borderPlacements `
        $skyboxRoomTemplate
    if (-not $WhatIf) {
        # Unchanged recipes keep their timestamps so compilers skip them.
        $vmfChanged = Write-TextFileIfChanged -Path $outputPath -Content $vmf
        if (-not (Test-GeneratedCellVmf $outputPath $expectedInteriorInstanceCount $expectedBorderInstanceCount $transitionGates.Count)) {
            throw "Generated VMF failed border structure validation: $outputPath"
        }
        if (-not $vmfChanged) {
            $unchanged++
            continue
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
        $denChanged = Copy-FileIfChanged -Source $templateVmfPath -Destination $outputVmfPath
        $templateVmxPath = [System.IO.Path]::ChangeExtension($templateVmfPath, '.vmx')
        if (Test-Path -LiteralPath $templateVmxPath -PathType Leaf) {
            $outputVmxPath = Join-Path $CellDirectory ([System.IO.Path]::ChangeExtension([string]$safeZoneMap.mapFilename, '.vmx'))
            Copy-FileIfChanged -Source $templateVmxPath -Destination $outputVmxPath | Out-Null
        }
        if (-not $denChanged) {
            $safeZoneMapsSkipped++
            continue
        }
    }
    $safeZoneMapsWritten++
}

if ($WhatIf) {
    foreach ($line in $cubemapProbeReport) {
        Write-Output $line
    }
}
Write-Output "Cell recipes: $($recipes.Count); cubemap probes: $cubemapProbeCount; written: $created; unchanged: $unchanged; refreshed generated: $refreshed; skipped existing: $skipped; safe-room entrances: $($safeZoneMaps.Count); reusable safe-room maps: $($safeZoneSourceMaps.Count); maps copied: $safeZoneMapsWritten; maps skipped: $safeZoneMapsSkipped; pruned stale safe-room files: $prunedStandaloneDenMaps; pruned stale generated: $pruned; cleared source items: $clearedItems; output: $CellDirectory"