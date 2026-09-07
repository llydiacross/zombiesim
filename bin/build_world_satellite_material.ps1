param(
    [string]$PlanData = '',
    [string]$CellMaterialDirectory = '',
    [string]$OutputPath = '',
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a <profile>_grid_*_template_plan.json path.'
}
if ([string]::IsNullOrWhiteSpace($CellMaterialDirectory)) {
    $CellMaterialDirectory = Join-Path $projectRoot (Join-Path (Join-Path 'content/materials/worlds' $worldGenerationProfile.Name) 'cells')
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot (Join-Path (Join-Path (Join-Path 'content/materials/worlds' $worldGenerationProfile.Name) 'map_layers') 'satellite.png')
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$cells = @($plan.cells)
if ($plan.schemaVersion -lt 4 -or $cells.Count -lt 1) {
    throw 'The template plan must use schema version 4 or later and contain city cells.'
}

$gridWidth = 1 + [int](($cells | Measure-Object -Property x -Maximum).Maximum)
$gridHeight = 1 + [int](($cells | Measure-Object -Property y -Maximum).Maximum)
if ($gridWidth -lt 1 -or $gridHeight -lt 1 -or $cells.Count -ne ($gridWidth * $gridHeight)) {
    throw 'The template plan does not contain a complete rectangular city grid.'
}

$coordinates = @{}
foreach ($cell in $cells) {
    $x = [int]$cell.x
    $y = [int]$cell.y
    $key = "$x,$y"
    if ($x -lt 0 -or $x -ge $gridWidth -or $y -lt 0 -or $y -ge $gridHeight -or $coordinates.ContainsKey($key)) {
        throw "The template plan contains an invalid or duplicate cell coordinate: $key"
    }
    $coordinates[$key] = $cell
}

$tileSize = [Math]::Min(64, [Math]::Floor(4096 / [Math]::Max($gridWidth, $gridHeight)))
if ($tileSize -lt 1) {
    throw "The $gridWidth by $gridHeight city grid exceeds the 4096px satellite material limit."
}

if ($WhatIf) {
    Write-Output "WhatIf: stitch $($cells.Count) logical cell previews into $($gridWidth * $tileSize)x$($gridHeight * $tileSize) satellite material: $OutputPath"
    return
}

if (-not (Test-Path -LiteralPath $CellMaterialDirectory -PathType Container)) {
    throw "Cell material directory was not found: $CellMaterialDirectory"
}

Add-Type -AssemblyName System.Drawing
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
$bitmap = [System.Drawing.Bitmap]::new($gridWidth * $tileSize, $gridHeight * $tileSize)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.Clear([System.Drawing.Color]::Black)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    foreach ($cell in $cells) {
        $filename = [System.IO.Path]::ChangeExtension([string]$cell.cellTemplateFilename, '.png')
        $sourcePath = Join-Path $CellMaterialDirectory $filename
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Cell preview material is missing: $sourcePath"
        }
        $image = [System.Drawing.Image]::FromFile($sourcePath)
        try {
            $destination = [System.Drawing.Rectangle]::new([int]$cell.x * $tileSize, [int]$cell.y * $tileSize, $tileSize, $tileSize)
            $graphics.DrawImage($image, $destination)
        } finally {
            $image.Dispose()
        }
    }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

Write-Output "Stitched $($cells.Count) logical cell previews into satellite material: $OutputPath"