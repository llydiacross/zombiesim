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
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = $plan.cellDirectory
}
if ([string]::IsNullOrWhiteSpace($TileDirectory)) {
    $TileDirectory = $plan.chunkTemplateDirectory
}
if ([string]::IsNullOrWhiteSpace($BaseCellTemplate)) {
    $BaseCellTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) 'celltemplates\template_border_s.vmf'
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
    $expectedCellDirectory = (Join-Path $projectRoot 'maps\src').TrimEnd('\')
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
$created = 0
$refreshed = 0
$skipped = 0
$pruned = 0
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

Write-Output "Cell recipes: $($recipes.Count); written: $created; refreshed generated: $refreshed; skipped existing: $skipped; pruned stale generated: $pruned; cleared source items: $clearedItems; output: $CellDirectory"