param(
    [string]$OutputRoot = '',
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$projectRoot = $testsRepoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot 'generated\test_cell_map_artwork'
}
$layoutDirectory = Join-Path $OutputRoot 'layouts'
$materialDirectory = Join-Path $OutputRoot 'materials'
[System.IO.Directory]::CreateDirectory($layoutDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($materialDirectory) | Out-Null

$recipe = 'zz_preview_artwork_fixture.vmf'
$core = @()
for ($y = 0; $y -lt 5; $y++) {
    for ($x = 0; $x -lt 5; $x++) {
        $core += [ordered]@{ tileX = $x; tileY = $y; template = 'terrain/tile_dirt.vmf'; role = 'terrain'; emitsInstance = $true }
    }
}
$plan = [ordered]@{
    schemaVersion = 4
    cellDirectory = $layoutDirectory
    cellTileGridSize = 5
    cellBounds = [ordered]@{ revision = 2; tileSize = 640; neighbourPitch = 5760 }
    cells = @([ordered]@{
        x = 0; y = 0; topology = 'road-straight'; orientation = 'vertical'; transportFeature = 'none'
        activeEntrances = @('N', 'S'); environmentProfile = 'dirt'; landmarks = @()
        cellTemplateFilename = $recipe; tileGridSize = 5; tilePlacements = $core
    })
}
$layout = [ordered]@{
    schemaVersion = 1
    recipe = $recipe
    corePlacements = $core
    bounds = $plan.cellBounds
    waterSides = @('W')
    authoredWaterBorderSides = @()
    borderPlacements = @(
        [ordered]@{ tileX = 2; tileY = -1; template = 'roads/tile_road.vmf'; rotationYaw = 0; targetname = 'north_route' }
    )
    outerPlacements = @(
        [ordered]@{ tileX = 6; tileY = 2; template = 'edges/tile_edge_ra_wall_1a.vmf'; rotationYaw = 90; targetname = 'east_edge' }
    )
}
$planPath = Join-Path $OutputRoot 'plan.json'
$layoutPath = Join-Path $layoutDirectory ([System.IO.Path]::ChangeExtension($recipe, '.layout.json'))
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8
$layout | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $layoutPath -Encoding UTF8

& (Join-Path $testsBinDirectory 'build_cell_map_materials.ps1') -WorldProfile preview -PlanData $planPath `
    -LayoutDirectory $layoutDirectory -DestinationDirectory $materialDirectory -ResolutionScale 1 -SettingsPath $SettingsPath | Out-Null
if (-not $?) { throw 'Cell-map artwork fixture renderer failed.' }

Add-Type -AssemblyName System.Drawing
$imagePath = Join-Path $materialDirectory ([System.IO.Path]::ChangeExtension($recipe, '.png'))
$image = [System.Drawing.Bitmap]::new($imagePath)
try {
    if ($image.Width -ne 432 -or $image.Height -ne 432) {
        throw "Expected a 432px 9x9 tile frame; got $($image.Width)x$($image.Height)."
    }
    $water = $image.GetPixel(24, 216)
    $northRoute = $image.GetPixel(196, 72)
    $eastEdge = $image.GetPixel(408, 216)
    $coreTerrain = $image.GetPixel(120, 120)
    if ($water.R -ne 58 -or $water.G -ne 91 -or $water.B -ne 112) { throw 'West omitted outer band is not water.' }
    if ($northRoute.R -ne 52 -or $northRoute.G -ne 59 -or $northRoute.B -ne 64) { throw 'Border route placement is not rendered.' }
    if ($eastEdge.R -ne 78 -or $eastEdge.G -ne 76 -or $eastEdge.B -ne 72) { throw 'Outer edge placement is not rendered.' }
    if ($coreTerrain.R -ne 110 -or $coreTerrain.G -ne 83 -or $coreTerrain.B -ne 61) { throw 'Core environment placement is not inset correctly.' }
} finally {
    $image.Dispose()
}

Write-Output "Cell-map artwork fixture passed: 9x9 frame, inset core, border route, outer edge and west-ocean omission."
