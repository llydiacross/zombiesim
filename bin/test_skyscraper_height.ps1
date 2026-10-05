param([switch]$Compile)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$sky = $profile.Settings.vmfBuild.skybox3d
$basePath = Join-Path $projectRoot $profile.Settings.paths.baseCellTemplate

function Get-PlaneHeights {
    param([string]$Path)

    foreach ($plane in [regex]::Matches([System.IO.File]::ReadAllText($Path), '"plane"\s+"([^"]+)"')) {
        foreach ($point in [regex]::Matches($plane.Groups[1].Value, '\(([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\)')) {
            [double]::Parse($point.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
}

$baseHeights = @(Get-PlaneHeights $basePath)
if ($baseHeights.Count -eq 0) { throw 'Playable shell must contain brush planes.' }
$shellTop = ($baseHeights | Measure-Object -Maximum).Maximum
$playableCeiling = $shellTop - 64
$templates = @('tile_skyscraper_1a_2x.vmf', 'tile_skyscraper_1aa_2x.vmf', 'tile_skyscraper_1aaa_2x.vmf')
foreach ($template in $templates) {
    $heights = @(Get-PlaneHeights (Join-Path $projectRoot "tiletemplates\buildings\$template"))
    if ($heights.Count -eq 0) { throw "No tower brush planes in $template." }
    $towerTop = ($heights | Measure-Object -Maximum).Maximum + [int]$profile.Settings.vmfBuild.tileZOffset
    if ($towerTop -ge $playableCeiling) { throw "$template reaches $towerTop, above playable ceiling $playableCeiling." }
    if ($towerTop / [double]$sky.scale + [double]$sky.snowLift / [double]$sky.scale -ge [double]$sky.roomHeight) {
        throw "$template does not fit inside the scaled sky room."
    }
}
$roomBottom = [double]$sky.cameraZ - 80
$captureHeight = [double]$sky.cameraZ - 128
if ($roomBottom -le $shellTop -or $captureHeight -le $playableCeiling -or $captureHeight -ge $roomBottom) {
    throw 'Sky room and map-capture height must remain separate above the playable shell.'
}
if ([int]$sky.skylineRadius -lt [int]$sky.neighbourRadius -or [int]$sky.maxTowerModels -lt 1) {
    throw 'Distant skyline radius/budget must cover the neighbours and bound model creation.'
}

$outputRoot = Join-Path $projectRoot 'generated\skyscraper_height'
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$fixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'multi_tile_zoo_fixture_map.json') | ConvertFrom-Json
$prototype = $fixture.cells[0] | ConvertTo-Json -Depth 12
$fixture.cells = @(
    for ($index = 0; $index -lt $templates.Count; $index++) {
        $cell = $prototype | ConvertFrom-Json
        $cell.x = $index
        $cell.worldX = $index
        $cell.multiTileTemplate = "buildings/$($templates[$index])"
        $cell.zooScenario = "skyscraper_height_$index"
        $cell
    }
)
$fixture.map.gridCells = 3
$fixture.map.width = 192
$mapPath = Join-Path $outputRoot 'fixture_map.json'
$planPath = Join-Path $outputRoot 'fixture_plan.json'
$listPath = Join-Path $outputRoot 'required_vmfs.txt'
$sourceDirectory = Join-Path $outputRoot 'src'
$fixture | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $mapPath -Encoding UTF8
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData $mapPath -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Skyscraper height fixture planning failed.' }
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
foreach ($cell in $plan.cells) {
    $expected = "buildings/$($templates[$cell.x])"
    if (@($cell.tilePlacements | Where-Object { $_.template -eq $expected -and $_.role -eq 'building' }).Count -eq 0) {
        throw "Forced tower $expected is missing from its fixture."
    }
}
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -PlanData $planPath -CellDirectory $sourceDirectory -RefreshGenerated | Out-Null
if (-not $?) { throw 'Skyscraper height fixture generation failed.' }
$roomPath = Join-Path $projectRoot 'generated\skybox_preview\skybox_room.vmf'
$roomText = [System.IO.File]::ReadAllText($roomPath)
$roomCoordinates = @(
    foreach ($plane in [regex]::Matches($roomText, '"plane"\s+"([^"]+)"')) {
        foreach ($point in [regex]::Matches($plane.Groups[1].Value, '\(([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\)')) {
            [math]::Abs([double]::Parse($point.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture))
            [math]::Abs([double]::Parse($point.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture))
        }
    }
)
$cellSpan = ($plan.cellTileGridSize + 2) * [int]$profile.Settings.vmfBuild.tileSize
$requiredHalf = ([int]$sky.skylineRadius + 0.5) * $cellSpan / [double]$sky.scale
$roomOuterHalf = ($roomCoordinates | Measure-Object -Maximum).Maximum
if ($roomOuterHalf -gt 16384 -or $roomOuterHalf - 1024 -lt $requiredHalf) {
    throw "Sky room does not contain the configured distant skyline: requiredHalf=$requiredHalf, outerHalf=$roomOuterHalf."
}
if ($Compile) {
    & (Join-Path $PSScriptRoot 'compile_cell_vmfs.ps1') -WorldProfile preview -SourceDirectory $sourceDirectory -BuildDirectory (Join-Path $outputRoot 'build') -MapFilename @($plan.requiredCellFiles | ForEach-Object { $_.filename }) -VBSPOnly
    if (-not $?) { throw 'Skyscraper height fixture VBSP failed.' }
}
Write-Output "Skyscraper height passed: three tower fixtures, shellTop=$shellTop, camera=$($sky.cameraZ), capture=$captureHeight, skylineRadius=$($sky.skylineRadius), roomOuterHalf=$roomOuterHalf, output=$outputRoot; VBSP=$Compile"
