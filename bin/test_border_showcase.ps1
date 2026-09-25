param(
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureMapPath = Join-Path $PSScriptRoot 'border_showcase_fixture_map.json'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot 'generated/border_showcase'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
[System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$planPath = Join-Path $OutputRoot 'border_showcase_fixture_template_plan.json'
$listPath = Join-Path $OutputRoot 'border_showcase_fixture_required_cell_vmfs.txt'
$cellDirectory = Join-Path $OutputRoot 'src'
$plannerScript = Join-Path $PSScriptRoot 'plan_cell_templates.ps1'
$builderScript = Join-Path $PSScriptRoot 'build_cell_vmfs.ps1'

if (-not (Test-Path -LiteralPath $fixtureMapPath -PathType Leaf)) {
    throw "Border showcase fixture map was not found: $fixtureMapPath"
}

& $plannerScript -WorldProfile preview -MapData $fixtureMapPath -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Border showcase fixture planner failed.' }

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()

function Test-CellHasTemplate {
    param([object]$Cell, [string]$Pattern)

    $vmfPath = Join-Path $cellDirectory $Cell.cellTemplateFilename
    if (-not (Test-Path -LiteralPath $vmfPath -PathType Leaf)) { return $false }
    return (Select-String -Path $vmfPath -Pattern $Pattern -Quiet)
}

# Water-corner showcase: the fixture's fixed seed deterministically activates the NW corner.
$cornerCell = @($plan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 0 })[0]
$northTipCell = @($plan.cells | Where-Object { $_.x -eq 3 -and $_.y -eq 0 })[0]
$westTipCell = @($plan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 3 })[0]
if ($null -eq $cornerCell -or $cornerCell.cellTemplateFilename -notlike '*-wtrnw.vmf') {
    $errors.Add('The (0,0) fixture cell must be the NW water-corner cell (filename suffix -wtrnw).')
}
if ($null -eq $northTipCell -or $northTipCell.cellTemplateFilename -notlike '*-wtrnt.vmf') {
    $errors.Add('The (3,0) fixture cell must be the water runway north tip (filename suffix -wtrnt).')
}
if ($null -eq $westTipCell -or $westTipCell.cellTemplateFilename -notlike '*-wtrwt.vmf') {
    $errors.Add('The (0,3) fixture cell must be the water runway west tip (filename suffix -wtrwt).')
}

# Landmark showcase: the Park landmark pattern added in Phase B must still resolve to a real building.
$parkCell = @($plan.cells | Where-Object { @($_.landmarks) -contains 'Park' })[0]
if ($null -eq $parkCell -or [string]$parkCell.landmarkTemplate -notlike '*tile_park*') {
    $errors.Add('The Park landmark fixture cell must resolve landmarkTemplate to a tile_park* building.')
}

# Topology variety: this fixture is meant to showcase more than one kind of generated layout.
$distinctTopologies = @($plan.cells | ForEach-Object { [string]$_.topology } | Sort-Object -Unique)
if ($distinctTopologies.Count -lt 6) {
    $errors.Add("Border showcase fixture must cover at least 6 distinct topologies for dev variety; found $($distinctTopologies.Count).")
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Border showcase fixture planner validation failed with $($errors.Count) error(s)."
}

& $builderScript -WorldProfile preview -PlanData $planPath -CellDirectory $cellDirectory -Force | Out-Null
if (-not $?) { throw 'Border showcase fixture VMF builder failed.' }

if (-not (Test-CellHasTemplate $cornerCell 'tile_border_water_pier_corner\.vmf')) {
    $errors.Add("$($cornerCell.cellTemplateFilename) must use tile_border_water_pier_corner.vmf at its map corner.")
}
if (-not (Test-CellHasTemplate $northTipCell 'tile_border_water_deadend\.vmf')) {
    $errors.Add("$($northTipCell.cellTemplateFilename) must cap its water runway with tile_border_water_deadend.vmf.")
}
if (-not (Test-CellHasTemplate $westTipCell 'tile_border_water_deadend\.vmf')) {
    $errors.Add("$($westTipCell.cellTemplateFilename) must cap its water runway with tile_border_water_deadend.vmf.")
}

$wallVariationCell = @($plan.cells | Where-Object { $_.cellTemplateFilename -notlike '*-wtr*' } | Select-Object -First 1)[0]
$wallVariationVmfPath = Join-Path $cellDirectory $wallVariationCell.cellTemplateFilename
$distinctWallVariants = @(Select-String -Path $wallVariationVmfPath -Pattern 'border/tile_border_wall(_1a|_1aa|_1aaa)?\.vmf' | ForEach-Object { $_.Matches[0].Value } | Sort-Object -Unique)
if ($distinctWallVariants.Count -lt 2) {
    $errors.Add("$($wallVariationCell.cellTemplateFilename) must mix at least two distinct wall-variation templates across its border ring; found $($distinctWallVariants.Count).")
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Border showcase fixture VMF validation failed with $($errors.Count) error(s)."
}

Write-Output "Border showcase fixture passed: cells=$($plan.cells.Count); topologies=$($distinctTopologies.Count); output=$OutputRoot"
