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
    [switch]$MotorwayCellInspection,
    [switch]$SizedTerrainInfill,
    [switch]$CompleteTerrainInfill,
    [switch]$MeasureCompleteTerrainInfill,
    [switch]$MotorwayOnlyInfill,
    [string]$WorldProfile = '',
    [switch]$Preview,
    [string]$SettingsPath = '',
    [string]$SkyboxOutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CompleteTerrainInfill -and -not $SizedTerrainInfill) { throw 'Complete infill requires sized terrain infill.' }
if ($MeasureCompleteTerrainInfill -and ($SizedTerrainInfill -or $CompleteTerrainInfill)) { throw 'Complete infill measurement cannot be combined with partial-source emission.' }
if ($MotorwayOnlyInfill -and -not ($MeasureCompleteTerrainInfill -or $SizedTerrainInfill -or $CompleteTerrainInfill)) {
    throw 'MotorwayOnlyInfill requires a terrain infill measurement or emission pass.'
}
if ($MotorwayOnlyInfill -and $ClearCellDirectory) {
    throw 'MotorwayOnlyInfill cannot clear a shared generated source directory.'
}
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
$outerEdgeSettings = if ($vmfBuildSettings.ContainsKey('outerEdges')) { $vmfBuildSettings.outerEdges } else { @{} }
$outerEdgesEnabled = $outerEdgeSettings.ContainsKey('enabled') -and [bool]$outerEdgeSettings.enabled
if ($outerEdgesEnabled -and -not $borderEnabled) { throw 'Outer edges require the existing border ring.' }
$topologyTemplates = $generatorSettings.cellPlanning.topologyTemplates
$transportTemplates = $generatorSettings.cellPlanning.transportTemplates
if (-not $PSBoundParameters.ContainsKey('PruneStaleGenerated')) { $PruneStaleGenerated = -not $MotorwayOnlyInfill }
if ($MotorwayOnlyInfill -and $PruneStaleGenerated) {
    throw 'MotorwayOnlyInfill cannot prune shared generated outputs; omit PruneStaleGenerated.'
}
Import-Module (Join-Path $PSScriptRoot 'carpark_endcaps.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'tile_ground_grid.psm1')
Import-Module (Join-Path $PSScriptRoot 'cell_bounds.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'outer_edges.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'transition_gates.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'motorway_geometry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scenery_density.psm1') -Force

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
    $cellSpan = (Get-ZMCellBounds $TileGridSize $TileWidth $outerEdgesEnabled).neighbourPitch
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
    if (-not [string]::IsNullOrWhiteSpace($SkyboxOutputDirectory)) {
        $roomPath = Join-Path ([System.IO.Path]::GetFullPath($SkyboxOutputDirectory)) 'skybox_room.vmf'
        $relativePath = $roomPath
    }
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
function Get-MotorwayInfillRecipes {
    param([Parameter(Mandatory = $true)][object[]]$Recipes)

    $motorwayRecipes = @($Recipes | Where-Object { $null -ne (Get-ZMComplexMotorwayContract $_) })
    if ($motorwayRecipes.Count -eq 0) {
        throw 'MotorwayOnlyInfill found no recipes with a schema-2 measured motorway contract.'
    }
    return $motorwayRecipes
}

$inspectionRecipes = @($plan.cells | Where-Object { $null -ne $_.PSObject.Properties['motorwayCellInspection'] })
if ($inspectionRecipes.Count -gt 0 -or $MotorwayCellInspection) {
    $generatedRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'generated')).TrimEnd('\') + '\'
    if (-not $MotorwayCellInspection -or $worldGenerationProfile.Name -ne 'preview' -or
        $inspectionRecipes.Count -ne $plan.cells.Count -or $inspectionRecipes.Count -lt 1 -or $inspectionRecipes.Count -gt 8 -or
        [string]::IsNullOrWhiteSpace($CellDirectory) -or -not [IO.Path]::GetFullPath($CellDirectory).StartsWith($generatedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::IsNullOrWhiteSpace($SkyboxOutputDirectory) -or -not [IO.Path]::GetFullPath($SkyboxOutputDirectory).StartsWith($generatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Motorway inspection requires explicit isolated preview cell/skybox output directories and -MotorwayCellInspection; never stage it as a normal recipe.'
    }
}
if ($outerEdgesEnabled -and ($null -eq $plan.PSObject.Properties['cellBounds'] -or $plan.cellBounds.revision -ne 2)) {
    throw 'Outer-edge generation requires a fresh expanded plan from matching settings.'
}
if ($null -ne $plan.PSObject.Properties['cellBounds'] -and ([int]$plan.cellBounds.revision -eq 2) -ne $outerEdgesEnabled) {
    throw 'Template plan and builder disagree about outer-edge enablement.'
}
if ($outerEdgesEnabled -and ($plan.cellBounds.tileSize -ne $TileSize -or $plan.cellBounds.coreTileGridSize -ne $plan.cellTileGridSize)) {
    throw 'Expanded plan tile dimensions do not match this build.'
}
if ($plan.schemaVersion -lt 2 -or $plan.cellTileGridSize -lt 1) {
    throw 'The template plan must contain a cellTileGridSize and tilePlacements.'
}
# Every city recipe carries the same 3D skybox room; cl_skybox.lua draws the current cell's neighbours inside it.
$skyboxSettings = if ($vmfBuildSettings.ContainsKey('skybox3d')) { $vmfBuildSettings.skybox3d } else { @{} }
$skyboxEnabled = $skyboxSettings.ContainsKey('enabled') -and [bool]$skyboxSettings.enabled
$skyboxRoomTemplate = ''
$safeZoneMaps = @()
if (-not $MotorwayOnlyInfill) { $safeZoneMaps = @($plan.safeZoneMaps) }
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

function Get-SkyboxOceanPlan {
    param([object]$Recipe)

    if ($null -eq $Recipe.PSObject.Properties['skyboxOceanSides']) {
        throw 'Expanded recipe lacks skyboxOceanSides; regenerate its template plan.'
    }
    $expected = @($(if ($Recipe.x -eq 0) { 'W' }))
    if ((@($Recipe.skyboxOceanSides) -join ',') -cne ($expected -join ',')) {
        throw "Expanded recipe has invalid skybox ocean sides at $($Recipe.x),$($Recipe.y)."
    }
    $sides = @{}
    foreach ($side in $expected) { $sides[$side] = $true }
    return $sides
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

    $fullTemplatePath = if ([System.IO.Path]::IsPathRooted($TemplateFilename)) { $TemplateFilename } else { Join-Path $TemplateDirectory $TemplateFilename }
    if (-not (Test-Path $fullTemplatePath)) {
        throw "Tile template was not found: $fullTemplatePath"
    }
    Write-ZMTileGroundGridWarnings $fullTemplatePath
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
    if ($null -ne $Placement.PSObject.Properties['role'] -and [string]$Placement.role -eq 'motorway_assembly') {
        $authored = Get-ZMMotorwayFootprint ([string]$Placement.template)
        $expectedWidth = if ([int]$Placement.rotationYaw -in @(90, 270)) { $authored.height } else { $authored.width }
        $expectedHeight = if ([int]$Placement.rotationYaw -in @(90, 270)) { $authored.width } else { $authored.height }
        if ($width -ne $expectedWidth -or $height -ne $expectedHeight) { throw 'Motorway rectangle differs from its authored/rotated footprint.' }
        return [pscustomobject]@{ width = $width; height = $height }
    }
    if ($width -lt 1 -or $height -lt 1 -or $width -gt 3 -or $height -gt 3) {
        throw "Placement '$($Placement.template)' must define a footprint from 1 through 3 tiles per axis."
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

function New-PlacementInstanceLines {
    param(
        [object]$Placement,
        [int]$TileGridSize,
        [int]$TileWidth,
        [int]$TileVerticalOffset,
        [int]$EntityId,
        [string]$InstancePath,
        [string]$Targetname,
        [switch]$Interior
    )

    if (-not (Test-PlacementEmitsInstance $Placement)) { throw 'Occupied placement cannot emit a VMF instance.' }
    $footprint = Get-PlacementFootprint $Placement
    $originProperty = $Placement.PSObject.Properties['originCellLocal']
    if ($null -ne $Placement.PSObject.Properties['role'] -and $Placement.role -eq 'motorway_assembly') {
        if ($TileGridSize -ne 5 -or $TileWidth -ne 640 -or $TileVerticalOffset -ne 0) {
            throw 'Measured motorway origins require the approved 5x5/640-unit cell frame with zero tile Z offset.'
        }
        if ($null -eq $originProperty -or $null -eq $originProperty.Value) {
            throw 'Motorway emitting owner requires an explicit cell-local physical origin.'
        }
        $origin = Convert-ZMMotorwayPoint $originProperty.Value 0
    } else {
        if ($null -ne $originProperty) { throw 'Explicit cell-local origins are currently limited to measured motorway owners.' }
        $center = [int][Math]::Floor($TileGridSize / 2)
        $origin = [pscustomobject]@{
            x = (([int]$Placement.tileX - $center) + ($footprint.width - 1) / 2.0) * $TileWidth
            y = (($center - [int]$Placement.tileY) - ($footprint.height - 1) / 2.0) * $TileWidth
            z = $TileVerticalOffset
        }
        if ($Interior) {
            $origin.x = [int]$origin.x
            $origin.y = [int]$origin.y
        }
    }
    $originText = '{0} {1} {2}' -f ([double]$origin.x).ToString('R', [Globalization.CultureInfo]::InvariantCulture),
        ([double]$origin.y).ToString('R', [Globalization.CultureInfo]::InvariantCulture),
        ([double]$origin.z).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    return [string[]]@(
        'entity',
        '{',
        ('    "id" "{0}"' -f $EntityId),
        '    "classname" "func_instance"',
        ('    "origin" "{0}"' -f $originText),
        ('    "angles" "0 {0} 0"' -f [int]$Placement.rotationYaw),
        ('    "file" "{0}"' -f $InstancePath),
        ('    "targetname" "{0}"' -f $Targetname),
        '    "fixup_style" "0"',
        '}'
    )
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
    if (-not $MotorwayCellInspection -and @($placements | Where-Object {
        $_.template.Replace('/', '\') -match '(?i)(^|\\)motorway_3x1\\'
    }).Count -gt 0) {
        if ($null -ne $Recipe.PSObject.Properties['motorwayCellInspection'] -or
            $null -eq $Recipe.PSObject.Properties['motorwayAssembly'] -or $Recipe.motorwayAssembly.schemaVersion -ne 1) {
            throw 'Normal wide motorway emission requires a complete measured straight assembly contract.'
        }
        $trustedPrevious = Test-TrustedPriorMotorwayAssembly $Recipe.motorwayAssembly
        $current = New-ZMNormalStraightMotorwayContract $Recipe $TileDirectory
        if (($current | ConvertTo-Json -Depth 30 -Compress) -cne
            ($Recipe.motorwayAssembly | ConvertTo-Json -Depth 30 -Compress)) {
            throw 'Normal wide motorway emission contract differs from current source.'
        }
        if ($trustedPrevious -and (@($Recipe.motorwayAssembly.gates).Count -eq 0 -or
            @($Recipe.motorwayAssembly.ringPlacements).Count -ne 4 -or
            @($Recipe.motorwayAssembly.leases).Count -ne 27)) {
            throw 'Trusted prior motorway plan lacks its approved gates or grid reservations.'
        }
        Get-TransitionGatePlacements $Recipe | Out-Null
    }
    $normalComplex = if ($null -ne $Recipe.PSObject.Properties['motorwayAssembly'] -and $Recipe.motorwayAssembly.schemaVersion -eq 2) { $Recipe.motorwayAssembly } else { $null }
    if ($null -ne $normalComplex) {
        if ($MotorwayCellInspection -or $null -ne $Recipe.PSObject.Properties['motorwayCellInspection'] -or
            $normalComplex.status -ne 'normal_complex_travel_pending') {
            throw 'Normal complex motorway emission requires a unique travel-pending schema-2 contract.'
        }
        if (-not (Test-TrustedPriorMotorwayAssembly $normalComplex)) {
            foreach ($property in $normalComplex.sourceFingerprints.PSObject.Properties) {
                if ($property.Value -cne (Get-FileHash -LiteralPath (Join-Path $TileDirectory $property.Name) -Algorithm SHA256).Hash) {
                    throw "Normal complex motorway source changed; replan before emission: $($property.Name)"
                }
            }
        }
        if ((Test-TrustedPriorMotorwayAssembly $normalComplex) -and
            @($normalComplex.gates).Count -eq 0) {
            throw 'Trusted prior complex motorway plan lacks its approved gate records.'
        }
        Get-TransitionGatePlacements $Recipe | Out-Null
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
    $suppressedInterior = @($placements | Where-Object { $_.role -eq 'safezone_entrance_occupied' -or $_.role -eq 'motorway_external_occupied' })
    $external = @($placements | Where-Object role -eq motorway_external_occupied)
    if ($external.Count -gt 0) {
        $complex = Get-ZMComplexMotorwayContract $Recipe
        $inspectionComplex = $null -ne $Recipe.PSObject.Properties['motorwayCellInspection'] -and $MotorwayCellInspection
        if ($null -eq $complex -or ($null -eq $normalComplex -and -not $inspectionComplex)) {
            throw 'External motorway occupancy requires a complex measured assembly contract.'
        }
        foreach ($record in $external) {
            $owner = @($complex.assemblies | Where-Object owner -eq $record.placementId)
            $lease = @($complex.leases | Where-Object { $_.tileX -eq $record.tileX -and $_.tileY -eq $record.tileY -and $_.owner -eq $record.placementId })
            if ($owner.Count -ne 1 -or $lease.Count -ne 1 -or $record.emitsInstance) { throw 'External occupied core slot has no unique measured assembly owner/lease.' }
        }
    }
    $ownerById = @{}
    foreach ($placement in $placements) {
        if (-not (Test-PlacementEmitsInstance $placement)) { continue }
        $tileX = [int]$placement.tileX
        $tileY = [int]$placement.tileY
        $footprint = Get-PlacementFootprint $placement
        $placementId = Get-PlacementId $placement
        if ($ownerById.ContainsKey($placementId)) {
            throw "$($Recipe.cellTemplateFilename) has duplicate emitting footprint owner '$placementId'."
        }
        $ownerById[$placementId] = $placement
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
        if ($occupancyRecord.role -in @('safezone_entrance_occupied', 'motorway_external_occupied')) { continue }
        $owner = $ownerByCoordinate[$key]
        $ownerId = Get-PlacementId $owner
        if ((Get-PlacementId $occupancyRecord) -ne $ownerId -or
            (Get-PlacementOwnerCoordinate $occupancyRecord 'ownerTileX' ([int]$occupancyRecord.tileX)) -ne [int]$owner.tileX -or
            (Get-PlacementOwnerCoordinate $occupancyRecord 'ownerTileY' ([int]$occupancyRecord.tileY)) -ne [int]$owner.tileY) {
            throw "$($Recipe.cellTemplateFilename) has inconsistent footprint ownership at $key."
        }
        $ownerFootprint = Get-PlacementFootprint $owner
        $recordWidth = $occupancyRecord.PSObject.Properties['footprintWidth']
        $recordHeight = $occupancyRecord.PSObject.Properties['footprintHeight']
        if (($null -ne $recordWidth -and [int]$recordWidth.Value -ne $ownerFootprint.width) -or
            ($null -ne $recordHeight -and [int]$recordHeight.Value -ne $ownerFootprint.height) -or
            [string]$occupancyRecord.template -cne [string]$owner.template -or
            [int]$occupancyRecord.rotationYaw -ne [int]$owner.rotationYaw) {
            throw "$($Recipe.cellTemplateFilename) has inconsistent footprint geometry at $key."
        }
    }
}

function Get-RecipeInteriorInstanceCount {
    param([object]$Recipe)

    $complex = Get-ZMComplexMotorwayContract $Recipe
    $externalCount = if ($null -ne $complex) { $complex.assemblies.Count } else { 0 }
    if ($null -ne $Recipe.PSObject.Properties['terrainInfill']) { $externalCount += $Recipe.terrainInfill.placements.Count }
    return @($Recipe.tilePlacements | Where-Object { Test-PlacementEmitsInstance $_ }).Count + $externalCount
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
        [regex]::Matches($contents, '"targetname" "(?:zm_border_|zm_transition_road_|zm_outer_)').Count -eq $expectedBorderCount
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

$longCubemapPatchTemplates = @{}
function Test-TemplateUsesLongCubemapPatch {
    param([string]$Template)

    if ([string]::IsNullOrWhiteSpace($Template)) { return $false }
    if (-not $longCubemapPatchTemplates.ContainsKey($Template)) {
        $path = if ([IO.Path]::IsPathRooted($Template)) { $Template } else { Join-Path $TileDirectory $Template }
        $longCubemapPatchTemplates[$Template] = (Test-Path -LiteralPath $path) -and
            [bool](Select-String -LiteralPath $path -Pattern 'CONCRETE/BLENDCONCRETEDEBRIS001A' -SimpleMatch -Quiet)
    }
    return $longCubemapPatchTemplates[$Template]
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
    # VBSP rejects cubemap patch names over 126 characters. A patched WVT blend lives under
    # maps/<map>/ already, so its cubemap patch repeats that prefix. The longest instanced
    # envmap blend is concrete/blendconcretedebris001a_wvt_patch (42 characters); pull an
    # anchor inward to three-digit coordinates only when that worst case would overflow.
    $mapName = [IO.Path]::GetFileNameWithoutExtension([string]$Recipe.cellTemplateFilename)
    $prefixLength = 2 * ('maps/'.Length + $mapName.Length + 1) + 42
    $usesLongPatch = @($placements | Where-Object { Test-TemplateUsesLongCubemapPatch ([string]$_.template) }).Count -gt 0
    foreach ($anchor in $anchors) {
        if (-not $usesLongPatch) { break }
        foreach ($axis in @('x', 'y')) {
            if (($prefixLength + ('_{0}_{1}_{2}' -f $anchor.x, $anchor.y, $anchor.z).Length) -le 126) { break }
            if ([Math]::Abs([int]$anchor[$axis]) -gt 999) { $anchor[$axis] = [Math]::Sign([int]$anchor[$axis]) * 999 }
        }
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
    $cornerVariationTemplates = if ($borderSettings.ContainsKey('cornerVariationTemplates')) { @($borderSettings.cornerVariationTemplates) } else { @() }
    $cornerDensityFallbacks = if ($borderSettings.ContainsKey('cornerDensityFallbacks')) { $borderSettings.cornerDensityFallbacks } else { @{} }
    $useCornerDensitySelection = $cornerVariationTemplates.Count -gt 0
    $profile = ([string]$Recipe.environmentProfile).ToLowerInvariant()
    if ($borderSettings.ContainsKey('profileTemplates') -and $borderSettings.profileTemplates.ContainsKey($profile)) {
        $profileTemplates = $borderSettings.profileTemplates[$profile]
        if ($profileTemplates.ContainsKey('wallVariationTemplates') -and @($profileTemplates.wallVariationTemplates).Count -gt 0) {
            $wallTemplates = @($profileTemplates.wallVariationTemplates)
        }
        if ($profileTemplates.ContainsKey('cornerVariationTemplates') -and @($profileTemplates.cornerVariationTemplates).Count -gt 0) {
            $cornerVariationTemplates = @($profileTemplates.cornerVariationTemplates)
            $cornerDensityFallbacks = if ($profileTemplates.ContainsKey('cornerDensityFallbacks')) { $profileTemplates.cornerDensityFallbacks } else { @{} }
            $cornerTemplate = if ($profileTemplates.ContainsKey('cornerTemplate') -and -not [string]::IsNullOrWhiteSpace([string]$profileTemplates.cornerTemplate)) {
                [string]$profileTemplates.cornerTemplate
            } else { [string]$cornerVariationTemplates[0] }
            $useCornerDensitySelection = $true
        } elseif ($profileTemplates.ContainsKey('cornerTemplate') -and -not [string]::IsNullOrWhiteSpace([string]$profileTemplates.cornerTemplate)) {
            $cornerTemplate = [string]$profileTemplates.cornerTemplate
            $cornerVariationTemplates = @()
            $cornerDensityFallbacks = @{}
            $useCornerDensitySelection = $false
        }
    }

    return [ordered]@{
        wallTemplates = $wallTemplates
        cornerTemplate = $cornerTemplate
        cornerVariationTemplates = if ($cornerVariationTemplates.Count -gt 0) { $cornerVariationTemplates } else { @($cornerTemplate) }
        cornerDensityFallbacks = $cornerDensityFallbacks
        useCornerDensitySelection = $useCornerDensitySelection
    }
}

function Get-BorderCornerTemplate {
    param(
        [object]$Recipe,
        [string]$CornerPosition,
        [string[]]$CornerTemplates,
        [System.Collections.IDictionary]$CornerDensityFallbacks,
        [string]$LegacyTemplate,
        [int]$MapSeed,
        [bool]$UseDensitySelection
    )

    if (-not $UseDensitySelection) { return [pscustomobject]@{ template = $LegacyTemplate; selection = $null } }
    $density = Get-ZMStoredSceneryDensity $Recipe
    if ($null -eq $density) { return [pscustomobject]@{ template = $LegacyTemplate; selection = $null } }

    $landmarks = @($Recipe.landmarks) -join '+'
    $cellPolicy = '{0}|{1}|{2}|{3}|{4}' -f `
        $Recipe.environmentProfile, $Recipe.topology, $Recipe.orientation, $density.sceneryDensityTier, $landmarks
    $selectionContext = @{
        Seed = $MapSeed
        CellPolicy = $cellPolicy
        Ring = 'border'
        Slot = $CornerPosition
        Role = 'border_corner'
        Variant = [int]$Recipe.cellVariant
    }
    $tierHash = Get-ZMScenerySelectionHash @selectionContext -Purpose tier
    $templateHash = Get-ZMScenerySelectionHash @selectionContext -Purpose template
    $context = 'cell={0},{1} corner={2} role=border_corner' -f $Recipe.x, $Recipe.y, $CornerPosition
    $selection = Select-ZMSceneryTemplate $CornerTemplates $density.sceneryDensityTier ([int]($tierHash % 100)) $templateHash $context
    if ($selection.status -eq 'selected') {
        return [pscustomobject]@{
            template = [string]$selection.template
            selection = [ordered]@{
                policyVersion = 1
                source = $density.sceneryDensitySource
                status = 'selected'
                zoneTier = $selection.zoneTier
                targetTier = $selection.targetTier
                template = [string]$selection.template
                actualTag = $selection.actualTag
                densityException = $null
            }
        }
    }

    $fallbackKey = [string]$selection.targetTier
    if ($CornerDensityFallbacks.Contains($fallbackKey)) {
        $fallbackTemplate = [string]$CornerDensityFallbacks[$fallbackKey]
        return [pscustomobject]@{
            template = $fallbackTemplate
            selection = [ordered]@{
                policyVersion = 1
                source = $density.sceneryDensitySource
                status = 'selected_explicit_exception'
                zoneTier = $selection.zoneTier
                targetTier = $selection.targetTier
                template = $fallbackTemplate
                actualTag = Get-ZMTemplateDensityTag $fallbackTemplate
                densityException = "target_tier_$($selection.targetTier)_fallback"
                excluded = @($selection.excluded)
            }
        }
    }
    throw "Required scenery pool unavailable at ${context}: zone=$($selection.zoneTier) target=$($selection.targetTier) routeAdjacentWall=false."
}

function Assert-BorderCornerVariationSettings {
    param(
        [System.Collections.IDictionary]$Settings,
        [string]$SettingPath,
        [string]$TileDirectory
    )

    if (-not $Settings.Contains('cornerVariationTemplates')) { return }
    $templates = @($Settings.cornerVariationTemplates | ForEach-Object { [string]$_ })
    if ($templates.Count -eq 0) { throw "$SettingPath.cornerVariationTemplates must not be empty." }
    $tags = @{}
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($template in $templates) {
        if ([string]::IsNullOrWhiteSpace($template) -or -not $seen.Add($template.Replace('\', '/'))) {
            throw "$SettingPath.cornerVariationTemplates contains an empty or duplicate source."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $TileDirectory $template) -PathType Leaf)) {
            throw "$SettingPath.cornerVariationTemplates references a missing source: $template"
        }
        $tags[$template.Replace('\', '/').ToLowerInvariant()] = Get-ZMTemplateDensityTag $template
    }

    $fallbacks = if ($Settings.Contains('cornerDensityFallbacks')) { $Settings.cornerDensityFallbacks } else { @{} }
    if (-not ($fallbacks -is [System.Collections.IDictionary])) {
        throw "$SettingPath.cornerDensityFallbacks must be a target-tier-to-template object."
    }
    foreach ($key in $fallbacks.Keys) {
        $target = 0
        if (-not [int]::TryParse([string]$key, [ref]$target) -or $target -notin 1..3) {
            throw "$SettingPath.cornerDensityFallbacks has an invalid target tier '$key'."
        }
        $fallback = ([string]$fallbacks[$key]).Replace('\', '/').ToLowerInvariant()
        if (-not $tags.ContainsKey($fallback)) {
            throw "$SettingPath.cornerDensityFallbacks[$key] must reference a member of cornerVariationTemplates."
        }
        if ($tags[$fallback] -eq 0 -or $tags[$fallback] -eq $target) {
            throw "$SettingPath.cornerDensityFallbacks[$key] must be a tagged template outside target tier $target."
        }
    }

    foreach ($target in 1..3) {
        $hasCompatibleTemplate = @($tags.Values | Where-Object { $_ -eq 0 -or $_ -eq $target }).Count -gt 0
        if (-not $hasCompatibleTemplate -and -not $fallbacks.Contains([string]$target)) {
            throw "$SettingPath.cornerVariationTemplates has no compatible or explicit fallback source for target tier $target."
        }
    }
}

Assert-BorderCornerVariationSettings -Settings $borderSettings -SettingPath 'vmfBuild.border' -TileDirectory $TileDirectory
if ($borderSettings.ContainsKey('profileTemplates')) {
    foreach ($profileName in $borderSettings.profileTemplates.Keys) {
        Assert-BorderCornerVariationSettings -Settings $borderSettings.profileTemplates[$profileName] -SettingPath "vmfBuild.border.profileTemplates.$profileName" -TileDirectory $TileDirectory
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
    $routeSlots = @(Get-ZMRouteFootprintSlots @($Recipe.tilePlacements) (Get-ZMRecipeRouteLeases $Recipe) @('core', 'border'))
    foreach ($routeSide in @($edgeConnections + $rampExits | Sort-Object -Unique)) {
        $routeSlots += [pscustomobject]@{
            tileX = $(if ($routeSide -eq 'W') { -1 } elseif ($routeSide -eq 'E') { $TileGridSize } else { $center })
            tileY = $(if ($routeSide -eq 'N') { -1 } elseif ($routeSide -eq 'S') { $TileGridSize } else { $center })
        }
    }
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
                $cornerSelection = if ($isWaterCorner) {
                    $null
                } else {
                    Get-BorderCornerTemplate -Recipe $Recipe -CornerPosition $cornerKey -CornerTemplates $borderTemplates.cornerVariationTemplates -CornerDensityFallbacks $borderTemplates.cornerDensityFallbacks -LegacyTemplate $borderTemplates.cornerTemplate -MapSeed ([int]$plan.mapSeed) -UseDensitySelection ([bool]$borderTemplates.useCornerDensitySelection)
                }
                $cornerPlacement = [ordered]@{
                    tileX = $tileX
                    tileY = $tileY
                    template = if ($isWaterCorner) { [string]$waterSettings.cornerTemplate } else { [string]$cornerSelection.template }
                    rotationYaw = $cornerYawByPosition[$cornerKey]
                    targetname = "zm_border_corner_$northSouth$eastWest"
                }
                if ($null -ne $cornerSelection -and $null -ne $cornerSelection.selection) {
                    $cornerPlacement.sceneryDensitySelection = $cornerSelection.selection
                }
                $placements.Add($cornerPlacement)
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
                $transitionGateRoadTemplate = if ($outerEdgesEnabled) { $rampRoadTemplate } else { $transitionGateRoadTemplates[($placementSeed + $sideIndex) % $transitionGateRoadTemplates.Count] }
            }
            $carparkEndcap = $carparkEndcapsByBorderSlot["$tileX,$tileY"]
            $isBridgeSide = $usesRoad -and ($side -in $bridgeSides)
            $usesWaterSide = -not $usesRoad -and $null -eq $carparkEndcap -and $waterSides.ContainsKey($side)
            $waterIndex = if ($side -in @('N', 'S')) { $tileX } else { $tileY }
            $waterPlan = if ($usesWaterSide) { $waterSides[$side] } else { $null }
            # Only the single center slot caps the run; the rest of a tip cell's side is plain wall, not a repeating water strip.
            $usesWaterDeadend = $usesWaterSide -and $waterPlan.isFarTip -and $isCenterEdgeSlot
            $usesWaterFill = $usesWaterSide -and -not $waterPlan.isFarTip
            $routeAdjacentWall = @($routeSlots | Where-Object {
                [Math]::Abs([int]$_.tileX - $tileX) + [Math]::Abs([int]$_.tileY - $tileY) -eq 1
            }).Count -gt 0
            $wallTemplates = if (-not ($usesRoad -or $null -ne $carparkEndcap -or $usesWaterDeadend -or $usesWaterFill)) {
                @(Get-ZMRoadAdjacentWallPool $borderTemplates.wallTemplates $routeSlots $tileX $tileY)
            } else { @($borderTemplates.wallTemplates) }
            $wallSelection = $null
            if (-not ($usesRoad -or $null -ne $carparkEndcap -or $usesWaterDeadend -or $usesWaterFill)) {
                $wallSelection = Get-ZMSceneryWallTemplateSelection $Recipe $wallTemplates ([int]$plan.mapSeed) 'border' "$tileX,$tileY" 'border_wall' $routeAdjacentWall
            }
            $placement = [ordered]@{
                tileX = $tileX
                tileY = $tileY
                template = if ($isBridgeSide) { $bridgeRoadTemplate } elseif ($usesTransitionGateRoad) { $transitionGateRoadTemplate } elseif ($usesRampRoad) { $rampRoadTemplate } elseif ($usesPrimaryRoad) { $primaryRoadTemplate } elseif ($null -ne $carparkEndcap) { $carparkEndcap.template } elseif ($usesWaterDeadend) { [string]$waterSettings.deadendTemplate } elseif ($usesWaterFill) { Get-WaterWallTemplate $waterIndex } elseif ($null -ne $wallSelection) { [string]$wallSelection.template } else { Get-RandomWallVariationTemplate $wallTemplates $placementSeed $tileX $tileY }
                rotationYaw = if ($usesRoad) { $roadYawBySide[$side] } elseif ($null -ne $carparkEndcap) { $carparkEndcap.rotationYaw } elseif ($usesWaterDeadend) { $waterDeadendYawBySide[$side] } else { $wallYawBySide[$side] }
                targetname = if ($usesTransitionGateRoad) { "zm_transition_road_$side" } else { "zm_border_$side`_$tileX`_$tileY" }
            }
            if ($null -ne $wallSelection -and $null -ne $wallSelection.selection) {
                $placement.sceneryDensitySelection = $wallSelection.selection
            }
            $placements.Add($placement)
        }
    }

    $expectedCount = (($TileGridSize + 2) * ($TileGridSize + 2)) - ($TileGridSize * $TileGridSize)
    $expectedCount -= $suppressedBorder.Count
    if ($placements.Count -ne $expectedCount) {
        throw "Border placement count for $($Recipe.cellTemplateFilename) was $($placements.Count), expected $expectedCount."
    }
    return @($placements)
}

function Test-TrustedPriorMotorwayAssembly {
    param([object]$Contract)

    $property = $Contract.PSObject.Properties['assemblyAuthority']
    return $null -ne $property -and $property.Value -eq 'trusted_prior_approved_grid_layout'
}

function ConvertTo-TransitionGatePlacements {
    param([object[]]$Gates)

    $placements = [System.Collections.Generic.List[object]]::new()
    foreach ($gate in $Gates) {
        if ($null -eq $gate.PSObject.Properties['lanes']) {
            $placements.Add($gate)
            continue
        }
        $arrivalLane = [int]$gate.arrivalLane
        if ($arrivalLane -lt 1 -or $arrivalLane -gt @($gate.lanes).Count) {
            throw "Transition gate has an invalid arrival lane: $($gate.direction)"
        }
        $arrival = $gate.lanes[$arrivalLane - 1]
        $route = if ($null -ne $gate.PSObject.Properties['route']) { [string]$gate.route } else { 'motorway' }
        $placements.Add([pscustomobject]@{
            direction = $gate.direction
            directionName = @{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }[$gate.direction]
            x = $gate.x; y = $gate.y
            yaw = @{ N = 90; E = 0; S = 270; W = 180 }[$gate.direction]
            zOffset = $gate.deckZ - 36
            arrivalX = $arrival.arrivalX; arrivalY = $arrival.arrivalY; arrivalZ = $gate.deckZ + 4
            route = $route; lanes = @($gate.lanes); lateralMin = $gate.lateralMin; lateralMax = $gate.lateralMax
        })
    }
    return @(Expand-ZMTransitionGateLanes @($placements))
}

function Get-TransitionGatePlacements {
    param([object]$Recipe)

    if ($null -ne $Recipe.PSObject.Properties['motorwayCellInspection']) { return @() }
    if ($null -ne $Recipe.PSObject.Properties['motorwayAssembly'] -and $Recipe.motorwayAssembly.schemaVersion -eq 2) {
        $complexGates = if (Test-TrustedPriorMotorwayAssembly $Recipe.motorwayAssembly) {
            @($Recipe.motorwayAssembly.gates)
        } else {
            @(Get-ZMComplexMotorwayGates $Recipe.motorwayAssembly $TileDirectory)
        }
        if ((@($Recipe.activeEntrances | Sort-Object -Unique) -join ',') -ne
            (@($complexGates.direction | Sort-Object -Unique) -join ',')) {
            throw "Normal complex motorway gates disagree with active entrances: $($Recipe.cellTemplateFilename)"
        }
        return @(ConvertTo-TransitionGatePlacements $complexGates)
    }
    if ($null -ne $Recipe.PSObject.Properties['motorwayAssembly']) {
        $fresh = New-ZMNormalStraightMotorwayContract $Recipe $TileDirectory
        if (($fresh.gates | ConvertTo-Json -Depth 10 -Compress) -cne
            ($Recipe.motorwayAssembly.gates | ConvertTo-Json -Depth 10 -Compress)) {
            throw 'Normal measured gate records differ from current source; replan.'
        }
        if ((@($Recipe.activeEntrances | Sort-Object -Unique) -join ',') -ne ($fresh.gates.direction -join ',')) {
            throw 'Normal measured gates disagree with active entrances.'
        }
        return @(ConvertTo-TransitionGatePlacements $fresh.gates)
    }
    $gateDirectionsProperty = $Recipe.PSObject.Properties['gateDirections']
    $activeEntrancesProperty = $Recipe.PSObject.Properties['activeEntrances']
    $directions = if ($null -ne $gateDirectionsProperty) {
        @($gateDirectionsProperty.Value)
    } elseif ($null -ne $activeEntrancesProperty) {
        @($activeEntrancesProperty.Value)
    } else {
        @((Get-RecipeEdgeConnections $Recipe) + @($Recipe.rampExits))
    }
    $bounds = Get-ZMCellBounds $plan.cellTileGridSize $TileSize $outerEdgesEnabled
    $transportFeature = [string]$Recipe.transportFeature
    $bridgeSides = if ($transportFeature -eq 'bridge-vertical') { @('N', 'S') } elseif ($transportFeature -eq 'bridge-horizontal') { @('E', 'W') } elseif ($transportFeature -like 'bridge-ramp-*') { @($transportFeature.Substring('bridge-ramp-'.Length, 1).ToUpperInvariant()) } else { @() }
    $elevationOffset = if (@($bridgeSides).Count -gt 0) {
        (Get-ZMTransitionDeckHeight (Join-Path $TileDirectory ([string]$transportTemplates.bridgeRoad)) $TileSize) -
            (Get-ZMTransitionDeckHeight (Join-Path $TileDirectory ([string]$topologyTemplates['road-straight'])) $TileSize)
    } else { 0 }

    $gates = @($directions |
        Where-Object { $_ -in @('N', 'E', 'S', 'W') } |
        Sort-Object -Unique |
        ForEach-Object {
            $center = Get-ZMTransitionGateCoordinates $bounds $_ $(if ($_ -in $bridgeSides) { $elevationOffset } else { 0 })
            [ordered]@{
                direction = $_
                directionName = @{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }[$_]
                x = [int]$center.x
                y = [int]$center.y
                yaw = [int]$center.yaw
                zOffset = [double]$center.zOffset
                arrivalX = [double]$center.arrivalX
                arrivalY = [double]$center.arrivalY
                arrivalZ = [double]$center.arrivalZ
            }
        })
    return @(Expand-ZMTransitionGateLanes $gates)
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
    $complexContract = Get-ZMComplexMotorwayContract $Recipe
    $candidate = if ($null -ne $complexContract -and $null -ne $complexContract.PSObject.Properties['insertionSeam']) {
        $complexContract.insertionSeam.playerStartCandidate
    } else { $null }
    if ($null -ne $candidate) {
        if ((-not $MotorwayCellInspection -and $complexContract.status -ne 'normal_complex_travel_pending') -or $TileGridSize -ne 5 -or $TileWidth -ne 640 -or
            $candidate.status -ne 'measured_floor_candidate_clearance_pending') {
            throw 'Measured motorway spawn candidate is limited to combined inspection fixtures.'
        }
        $point = Convert-ZMMotorwayPoint $candidate 0
        $spawnX = $point.x
        $spawnY = $point.y
    } else {
        if ($terrainTiles.Count -eq 0) { throw "Recipe '$($Recipe.cellTemplateFilename)' has no unobstructed terrain tile for the player start." }
        $spawnTile = $terrainTiles[0]
        $spawnX = [int](([int]$spawnTile.tileX - $centerTile) * $TileWidth)
        $spawnY = [int](($centerTile - [int]$spawnTile.tileY) * $TileWidth)
    }
    $originPropertyIndex = $Vmf.IndexOf('"origin"', $playerStartIndex, [System.StringComparison]::Ordinal)
    if ($originPropertyIndex -lt 0) { throw 'Base cell info_player_start must define an origin.' }
    $originMatch = [regex]::Match($Vmf.Substring($originPropertyIndex), '^"origin"\s+"(?<origin>-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?)"')
    if (-not $originMatch.Success) { throw 'Base cell info_player_start must define a numeric origin.' }
    $sourceCoordinates = @($originMatch.Groups['origin'].Value -split '\s+')
    $spawnZ = if ($null -ne $candidate) {
        ([double]$sourceCoordinates[2] + $point.z).ToString([Globalization.CultureInfo]::InvariantCulture)
    } else { $sourceCoordinates[2] }
    $spawnOrigin = '{0} {1} {2}' -f $spawnX.ToString([Globalization.CultureInfo]::InvariantCulture), $spawnY.ToString([Globalization.CultureInfo]::InvariantCulture), $spawnZ
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
    if ($outerEdgesEnabled) {
        $baseVmf = Expand-ZMOuterEdgeShell $baseVmf (Get-ZMCellBounds $TileGridSize $TileWidth $true) (Get-SkyboxOceanPlan $Recipe)
    }
    $baseVmf = Set-ZMTransitionArrivalLandmarks $baseVmf @(Get-TransitionGatePlacements $Recipe)
    $baseVmf = Remove-TemplateCubemaps $baseVmf
    $baseVmf = Set-VmfLightingProfile $baseVmf (Get-RecipeLightingProfile $Recipe)
    $baseVmf = Set-CellPlayerStart $baseVmf $Recipe $TileGridSize $TileWidth
    if ($null -ne $Recipe.PSObject.Properties['motorwayCellInspection']) {
        $inspectionCameras = @'
cameras
{
    "activecamera" "0"
    camera
    {
        "position" "[-2600 -2600 1700]"
        "look" "[0 0 68]"
    }
    camera
    {
        "position" "[-850 -1700 180]"
        "look" "[-512 0 68]"
    }
}
'@
        $baseVmf = [regex]::Replace($baseVmf, '(?ms)^cameras\r?\n\{.*?^\}', $inspectionCameras)
    }
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
        $targetname = Get-PlacementDebugTargetname $placement
        $lines.AddRange([string[]](New-PlacementInstanceLines $placement $TileGridSize $TileWidth $TileVerticalOffset $entityId $instancePath $targetname -Interior))
        $entityId++
    }
    $complexContract = Get-ZMComplexMotorwayContract $Recipe
    if ($null -ne $complexContract) {
        foreach ($assembly in $complexContract.assemblies) {
            $instancePath = Get-VmfInstancePath $SourceDirectory $TemplateDirectory $assembly.template
            $origin = $assembly.origin
            $originText = '{0} {1} {2}' -f ([double]$origin.x).ToString('R', [Globalization.CultureInfo]::InvariantCulture), ([double]$origin.y).ToString('R', [Globalization.CultureInfo]::InvariantCulture), ([double]$origin.z).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            $lines.AddRange([string[]]@(
                'entity', '{', ('    "id" "{0}"' -f $entityId),
                '    "classname" "func_instance"', ('    "origin" "{0}"' -f $originText),
                ('    "angles" "0 {0} 0"' -f $assembly.yaw), ('    "file" "{0}"' -f $instancePath),
                ('    "targetname" "zm_assembly_{0}"' -f $assembly.owner), '    "fixup_style" "0"', '}'
            ))
            $entityId++
        }
    }
    if ($null -ne $Recipe.PSObject.Properties['terrainInfill']) {
        foreach ($placement in $Recipe.terrainInfill.placements) {
            $instancePath = Get-VmfInstancePath $SourceDirectory $TemplateDirectory $placement.template
            $originText = '{0} {1} {2}' -f ([double]$placement.origin.x).ToString('R', [Globalization.CultureInfo]::InvariantCulture), ([double]$placement.origin.y).ToString('R', [Globalization.CultureInfo]::InvariantCulture), ([double]$placement.origin.z).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            $lines.AddRange([string[]]@(
                'entity', '{', ('    "id" "{0}"' -f $entityId), '    "classname" "func_instance"',
                ('    "origin" "{0}"' -f $originText),
                ('    "angles" "0 {0} 0"' -f $placement.yaw), ('    "file" "{0}"' -f $instancePath),
                ('    "targetname" "zm_terrain_{0}"' -f $placement.owner), '    "fixup_style" "0"', '}'
            ))
            $entityId++
        }
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
        $lines.AddRange([string[]](New-PlacementInstanceLines $placement $TileGridSize $TileWidth $TileVerticalOffset $entityId $instancePath $placement.targetname))
        $entityId++
    }
    foreach ($gate in @(Get-TransitionGatePlacements $Recipe)) {
        $triggerBounds = Get-ZMTransitionTriggerBounds $gate
        $minX = $triggerBounds.minX; $maxX = $triggerBounds.maxX
        $minY = $triggerBounds.minY; $maxY = $triggerBounds.maxY
        $minZ = $triggerBounds.minZ; $maxZ = $triggerBounds.maxZ
        $solidId = $entityId + 1
        $sideId = $solidId + 1
        $gateTargetName = if ($null -ne $gate.PSObject.Properties['laneIndex']) {
            'zm_transition_gate_{0}_lane{1}' -f $gate.direction, $gate.laneIndex
        } else {
            'zm_transition_gate_{0}' -f $gate.direction
        }
        $gateEntityStart = $lines.Count
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
            ('    "origin" "{0} {1} {2}"' -f $gate.x, $gate.y, (56 + $gate.zOffset)),
            ('    "angles" "0 {0} 0"' -f $gate.yaw),
            ('    "targetname" "{0}"' -f $gateTargetName),
            '    "zm_transition_gate" "1"',
            ('    "zm_transition_direction" "{0}"' -f $gate.directionName),
            '    "zm_transition_mode" "any"',
            '    "wait" "1"',
            '    "solid"',
            '    {'
            ('        "id" "{0}"' -f $solidId)
        ))
        if ($null -ne $gate.PSObject.Properties['laneIndex']) {
            $lines.Insert($gateEntityStart + 10, ('    "zm_transition_lane" "{0}"' -f $gate.laneIndex))
        }
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

        $barricadeProps = @(Get-ZMTransitionBarricadeProps $gate)
        foreach ($index in 0..($barricadeProps.Count - 1)) {
            $prop = $barricadeProps[$index]
            $placement = Convert-NorthGateOffset $gate $prop.across $prop.outward $prop.yaw
            $barricadeTargetName = if ($null -ne $gate.PSObject.Properties['laneIndex']) {
                'zm_transition_gate_{0}_lane{1}_barricade_{2}' -f $gate.direction, $gate.laneIndex, $index
            } else {
                'zm_transition_gate_{0}_barricade_{1}' -f $gate.direction, $index
            }
            $lines.AddRange([string[]]@(
                'entity',
                '{',
                ('    "id" "{0}"' -f $entityId),
                '    "classname" "prop_static"',
                ('    "targetname" "{0}"' -f $barricadeTargetName),
                ('    "angles" "0 {0} 0"' -f $placement.yaw),
                '    "fademindist" "-1"',
                '    "fadescale" "1"',
                '    "lightmapresolutionx" "32"',
                '    "lightmapresolutiony" "32"',
                ('    "model" "{0}"' -f $prop.model),
                '    "skin" "0"',
                '    "solid" "6"',
                ('    "origin" "{0} {1} {2}"' -f $placement.x, $placement.y, ($prop.z + $gate.zOffset)),
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
if ($MotorwayOnlyInfill) {
    $recipes = @(Get-MotorwayInfillRecipes $recipes)
}
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
if (-not $MotorwayOnlyInfill -and ($RefreshGenerated -or $Force -or $PruneStaleGenerated)) {
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
    $cubemapAnchors = Get-CubemapAnchors $recipe $plan.cellTileGridSize $TileSize $TileZOffset
    $borderPlacements = Get-BorderPlacements $recipe $plan.cellTileGridSize
    $outerPlacements = @()
    if ($outerEdgesEnabled) {
        $roadTemplates = Get-ZMOuterEdgeRoadTemplates $borderPlacements $plan.cellTileGridSize ([string]$topologyTemplates['road-straight']) ([string]$topologyTemplates['motorway-straight']) ([string]$transportTemplates.bridgeRoad)
        $outerPlacements = @(Get-ZMOuterEdgePlacements $recipe $plan.cellTileGridSize $outerEdgeSettings $borderPlacements (Get-SkyboxOceanPlan $recipe) $roadTemplates ([int]$plan.mapSeed))
        foreach ($placement in $outerPlacements) {
            if (-not (Test-Path -LiteralPath (Join-Path $TileDirectory $placement.template) -PathType Leaf)) {
                throw "Required outer-edge source is missing: $($placement.template)"
            }
        }
    }
    $complexContract = Get-ZMComplexMotorwayContract $recipe
    if ($null -ne $recipe.PSObject.Properties['motorwayAssembly'] -and $null -eq $complexContract) {
        $rings = Resolve-ZMNormalStraightMotorwayRings $recipe $TileDirectory $borderPlacements $outerPlacements
        $borderPlacements = $rings.borderPlacements
        $outerPlacements = $rings.outerPlacements
    }
    if ($null -ne $recipe.PSObject.Properties['motorwayCellInspection'] -or $null -ne $complexContract) {
        $inspection = if ($null -ne $complexContract) { $complexContract } else { $recipe.motorwayCellInspection }
        if ($inspection.schemaVersion -eq 2) {
            $expectedStatus = if ($null -ne $recipe.PSObject.Properties['motorwayCellInspection']) { 'complex_cell_diagnostic_not_live_travel' } else { 'normal_complex_travel_pending' }
            if ($inspection.status -ne $expectedStatus) { throw 'Invalid complex motorway contract status.' }
            if (-not (Test-TrustedPriorMotorwayAssembly $inspection)) {
                foreach ($property in $inspection.sourceFingerprints.PSObject.Properties) {
                    if ($property.Value -cne (Get-FileHash -LiteralPath (Join-Path $TileDirectory $property.Name) -Algorithm SHA256).Hash) { throw "Complex inspection source changed: $($property.Name). Replan." }
                }
            }
            $leased = @{}
            foreach ($lease in $inspection.leases) { $leased["$($lease.tileX),$($lease.tileY)"] = $true }
            $borderPlacements = @($borderPlacements | Where-Object { -not $leased.ContainsKey("$($_.tileX),$($_.tileY)") })
            $outerPlacements = @($outerPlacements | Where-Object { -not $leased.ContainsKey("$($_.tileX),$($_.tileY)") })
            $borderPlacements = @(Resolve-ZMCentredRoadBorderPlacements $recipe $borderPlacements)
        } else {
        if ($inspection.schemaVersion -ne 1 -or $inspection.status -ne 'cell_geometry_inspection_not_live_travel' -or
            $recipe.topology -ne 'motorway-straight' -or $recipe.transportFeature -ne 'none' -or
            $inspection.sourceSha256 -cne (Get-FileHash -LiteralPath (Join-Path $TileDirectory $inspection.template) -Algorithm SHA256).Hash) {
            throw 'Motorway cell inspection metadata is unsupported or its source fingerprint is stale; replan from current sources.'
        }
        $leased = Assert-ZMStraightMotorwayCellContract $recipe
        $borderPlacements = @($borderPlacements | Where-Object { -not $leased.ContainsKey("$($_.tileX),$($_.tileY)") }) +
            @($inspection.ringPlacements | Where-Object ring -eq border)
        $outerPlacements = @($outerPlacements | Where-Object { -not $leased.ContainsKey("$($_.tileX),$($_.tileY)") }) +
            @($inspection.ringPlacements | Where-Object ring -eq outer)
        }
    }
    if ($null -ne $complexContract) {
        Import-Module (Join-Path $PSScriptRoot 'terrain_infill.psm1')
        $infill = Set-ZMInspectionTerrainInfill $recipe $TileDirectory $borderPlacements $outerPlacements -SizedPatches:$SizedTerrainInfill -CompletePatches:$CompleteTerrainInfill -MeasureCompletePatches:$MeasureCompleteTerrainInfill
        $recipe | Add-Member -NotePropertyName terrainInfill -NotePropertyValue $infill
    }
    $expectedInteriorInstanceCount = (Get-RecipeInteriorInstanceCount $recipe) +
        $(if ($hasSafeZoneEntrance) { 1 } else { 0 }) +
        $(if ($skyboxEnabled) { 1 } else { 0 })
    $layout = [ordered]@{
        schemaVersion = 1
        recipe = $recipe.cellTemplateFilename
        corePlacements = @($recipe.tilePlacements)
        bounds = Get-ZMCellBounds $plan.cellTileGridSize $TileSize $outerEdgesEnabled
        waterSides = @(if ($outerEdgesEnabled) { (Get-SkyboxOceanPlan $recipe).Keys | Sort-Object } else { (Get-WaterBorderPlan $recipe).Keys | Sort-Object })
        authoredWaterBorderSides = @((Get-WaterBorderPlan $recipe).Keys | Sort-Object)
        borderPlacements = @($borderPlacements)
        outerPlacements = @($outerPlacements)
    }
    if ($null -ne $recipe.PSObject.Properties['motorwayCellInspection']) {
        $layout.motorwayCellInspection = $recipe.motorwayCellInspection
    }
    if ($null -ne $recipe.PSObject.Properties['motorwayAssembly']) { $layout.motorwayAssembly = $recipe.motorwayAssembly }
    if ($null -ne $Recipe.PSObject.Properties['terrainInfill']) { $layout.terrainInfill = $recipe.terrainInfill }
    $legacyBorderCount = $borderPlacements.Count
    $borderPlacements = @($borderPlacements) + @($outerPlacements)
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
        $matchesLegacyRing = $outerEdgesEnabled -and (Test-GeneratedCellVmf $outputPath $expectedInteriorInstanceCount $legacyBorderCount $transitionGates.Count)
        $matchesPreviousLayout = $false
        $previousLayoutPath = [IO.Path]::ChangeExtension($outputPath, '.layout.json')
        if ($outerEdgesEnabled -and (Test-Path -LiteralPath $previousLayoutPath -PathType Leaf)) {
            $previousLayout = Get-Content -Raw -LiteralPath $previousLayoutPath | ConvertFrom-Json
            if ($previousLayout.vmfSha256 -eq (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant() -and
                $previousLayout.bounds.revision -eq 2 -and $previousLayout.recipe -eq $recipe.cellTemplateFilename) {
                $previousBorderCount = @($previousLayout.borderPlacements).Count + @($previousLayout.outerPlacements).Count
                $matchesPreviousLayout = Test-GeneratedCellVmf $outputPath $expectedInteriorInstanceCount $previousBorderCount $transitionGates.Count
                if ($null -ne $recipe.PSObject.Properties['terrainInfill'] -and
                    $null -ne (Get-ZMComplexMotorwayContract $previousLayout)) {
                    $previousInfillCount = if ($null -ne $previousLayout.PSObject.Properties['terrainInfill']) { $previousLayout.terrainInfill.placements.Count } else { 0 }
                    $priorCount = $expectedInteriorInstanceCount - $recipe.terrainInfill.placements.Count + $previousInfillCount
                    $matchesPreviousLayout = $matchesPreviousLayout -or (Test-GeneratedCellVmf $outputPath $priorCount $previousBorderCount $transitionGates.Count)
                }
            }
        }
        if (-not $RefreshGenerated -or (-not $matchesExpectedStructure -and -not $matchesSkyboxToggle -and -not $matchesLegacyRing -and -not $matchesPreviousLayout)) {
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
        $layout.vmfSha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $null = Write-TextFileIfChanged -Path ([System.IO.Path]::ChangeExtension($outputPath, '.layout.json')) -Content (($layout | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
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
$scope = if ($MotorwayOnlyInfill) { 'motorway-only infill' } else { 'full plan' }
Write-Output "Cell recipes ($scope): $($recipes.Count); cubemap probes: $cubemapProbeCount; written: $created; unchanged: $unchanged; refreshed generated: $refreshed; skipped existing: $skipped; safe-room entrances: $($safeZoneMaps.Count); reusable safe-room maps: $($safeZoneSourceMaps.Count); maps copied: $safeZoneMapsWritten; maps skipped: $safeZoneMapsSkipped; pruned stale safe-room files: $prunedStandaloneDenMaps; pruned stale generated: $pruned; cleared source items: $clearedItems; output: $CellDirectory"