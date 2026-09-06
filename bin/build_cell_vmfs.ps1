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
    [switch]$Preview,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$generatorSettings = & (Join-Path $PSScriptRoot 'import_generator_settings.ps1') -SettingsPath $SettingsPath
if (-not $PSBoundParameters.ContainsKey('TileSize')) { $TileSize = [int]$generatorSettings.vmfBuild.tileSize }
if (-not $PSBoundParameters.ContainsKey('TileZOffset')) { $TileZOffset = [int]$generatorSettings.vmfBuild.tileZOffset }

if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $PlanData = @(Get-ChildItem -Path $PSScriptRoot -Filter '*_template_plan.json' -File |
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
    if ($Preview) {
        $CellDirectory = Join-Path $projectRoot $generatorSettings.paths.previewCellDirectory
    } else {
        $CellDirectory = $plan.cellDirectory
    }
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
$CellDirectory = (Resolve-Path $CellDirectory).Path
$clearedItems = 0
if ($ClearCellDirectory) {
    $projectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
    $expectedCellDirectory = (Join-Path $projectRoot 'generated\src').TrimEnd('\')
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

function New-CellVmf {
    param(
        [object]$Recipe,
        [int]$TileGridSize,
        [int]$TileWidth,
        [int]$TileVerticalOffset,
        [string]$SourceDirectory,
        [string]$TemplateDirectory,
        [string]$BaseTemplatePath
    )

    $expectedTileCount = $TileGridSize * $TileGridSize
    $placements = @($Recipe.tilePlacements)
    if ($placements.Count -ne $expectedTileCount) {
        throw "$($Recipe.cellTemplateFilename) has $($placements.Count) tiles; expected $expectedTileCount."
    }

    $baseVmf = Get-Content -Raw $BaseTemplatePath
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
    if ((Test-Path $outputPath) -and -not $Force) {
        if (-not $RefreshGenerated -or -not (Test-GeneratedCellVmf $outputPath)) {
            $skipped++
            continue
        }
        $refreshed++
    }

    $vmf = New-CellVmf $recipe $plan.cellTileGridSize $TileSize $TileZOffset $CellDirectory $TileDirectory $BaseCellTemplate
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

Write-Output "Cell recipes: $($recipes.Count); written: $created; refreshed generated: $refreshed; skipped existing: $skipped; safe-room entrances: $($safeZoneMaps.Count); reusable safe-room maps: $($safeZoneSourceMaps.Count); maps copied: $safeZoneMapsWritten; maps skipped: $safeZoneMapsSkipped; pruned stale safe-room files: $prunedStandaloneDenMaps; pruned stale generated: $pruned; cleared source items: $clearedItems; output: $CellDirectory"