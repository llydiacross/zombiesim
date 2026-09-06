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

function Test-GeneratedCellVmf {
    param([string]$Path)

    $contents = Get-Content -Raw $Path
    return $contents -match 'tiletemplates/' -and
        [regex]::Matches($contents, '"classname" "func_instance"').Count -eq 25
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

    $placements = @($Recipe.tilePlacements)
    $center = [int][Math]::Floor($TileGridSize / 2)
    $usedCoordinates = @{}
    $candidates = [System.Collections.Generic.List[object]]::new()
    $hasRoad = $false
    $hasLandmark = $false

    function Add-CubemapCandidate {
        param([object]$Placement, [int]$Priority)

        $tileX = [int]$Placement.tileX
        $tileY = [int]$Placement.tileY
        $key = "$tileX,$tileY"
        if ($usedCoordinates.ContainsKey($key)) { return }
        $usedCoordinates[$key] = $true
        $candidates.Add([ordered]@{
            priority = $Priority
            distance = [Math]::Abs($tileX - $center) + [Math]::Abs($tileY - $center)
            x = ($tileX - $center) * $TileWidth
            y = ($center - $tileY) * $TileWidth
            z = $TileVerticalOffset + 96
        })
    }

    foreach ($placement in $placements) {
        $template = ([string]$placement.template).ToLowerInvariant()
        $isRoad = $template -match '(road|path|motorway)'
        $isJunction = $isRoad -and $template -match '(corner|cross|tjunction|junction|onramp|bridge)'
        $isLandmark = $template -match '(church|hospital|school|station|market|bank|tower|airport|laboratory|stadium|mall)'
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

function New-CellVmf {
    param(
        [object]$Recipe,
        [int]$TileGridSize,
        [int]$TileWidth,
        [int]$TileVerticalOffset,
        [string]$SourceDirectory,
        [string]$TemplateDirectory,
        [string]$BaseTemplatePath,
        [object[]]$CubemapAnchors
    )

    $expectedTileCount = $TileGridSize * $TileGridSize
    $placements = @($Recipe.tilePlacements)
    if ($placements.Count -ne $expectedTileCount) {
        throw "$($Recipe.cellTemplateFilename) has $($placements.Count) tiles; expected $expectedTileCount."
    }

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
    foreach ($placement in ($placements | Sort-Object tileY, tileX)) {
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
            '    "fixup_style" "0"',
            '}'
        ))
        $entityId++
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
if ($RefreshGenerated -or $Force) {
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
    $cubemapAnchors = Get-CubemapAnchors $recipe $plan.cellTileGridSize $TileSize $TileZOffset
    $cubemapProbeCount += $cubemapAnchors.Count
    if ($WhatIf) {
        $cubemapProbeReport.Add("Cubemap probes: $($recipe.cellTemplateFilename) = $($cubemapAnchors.Count)")
    }
    if ((Test-Path $outputPath) -and -not $Force) {
        if (-not $RefreshGenerated -or -not (Test-GeneratedCellVmf $outputPath)) {
            $skipped++
            continue
        }
        $refreshed++
    }

    $vmf = New-CellVmf $recipe $plan.cellTileGridSize $TileSize $TileZOffset $CellDirectory $TileDirectory $BaseCellTemplate $cubemapAnchors
    if (-not $WhatIf) {
        [System.IO.File]::WriteAllText($outputPath, $vmf, [System.Text.UTF8Encoding]::new($false))
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