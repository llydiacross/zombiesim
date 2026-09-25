Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'zombiesim-building-frontage-check'
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$planPath = Join-Path $outputRoot 'preview_template_plan.json'
$listPath = Join-Path $outputRoot 'preview_required_cell_vmfs.txt'
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData (Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json') -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Preview planner failed.' }

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$cell = @($plan.cells | Where-Object { $_.x -eq 4 -and $_.y -eq 0 })[0]
if ($null -eq $cell) { throw 'Preview cell (4,0) was not planned.' }
$building = @($cell.tilePlacements | Where-Object { $_.tileX -eq 1 -and $_.tileY -eq 4 })[0]
$road = @($cell.tilePlacements | Where-Object { $_.tileX -eq 2 -and $_.tileY -eq 4 })[0]
if ($building.template -ne 'buildings/tile_construction_1aa.vmf' -or $building.role -ne 'building' -or $road.role -ne 'road' -or $building.rotationYaw -ne 90) {
    throw "Construction at (1,4) must face its east-adjacent road at yaw 90; found $($building.template) yaw=$($building.rotationYaw), neighbor=$($road.role)."
}
$house = @($cell.tilePlacements | Where-Object { $_.tileX -eq 3 -and $_.tileY -eq 2 })[0]
$corner = @($cell.tilePlacements | Where-Object { $_.tileX -eq 2 -and $_.tileY -eq 2 })[0]
if ($house.template -ne 'buildings/tile_building_1c.vmf' -or $house.role -ne 'building' -or $corner.role -ne 'road_center' -or $house.rotationYaw -ne 270) {
    throw "House at (3,2) must face its west-adjacent road corner at yaw 270; found $($house.template) yaw=$($house.rotationYaw), neighbor=$($corner.role)."
}
$commercialCells = @($plan.cells | Where-Object { $_.x -eq 12 -and $_.y -eq 20 })
if ($commercialCells.Count -eq 0) { throw 'Preview cell (12,20) was not planned.' }
$commercial = @($commercialCells[0].tilePlacements | Where-Object { $_.tileX -eq 0 -and $_.tileY -eq 0 })[0]
$commercialRoad = @($commercialCells[0].tilePlacements | Where-Object { $_.tileX -eq 2 -and $_.tileY -eq 0 })[0]
$commercialJunction = @($commercialCells[0].tilePlacements | Where-Object { $_.tileX -eq 2 -and $_.tileY -eq 1 })[0]
if ($commercial.template -ne 'buildings/tile_commercial_2a_2x.vmf' -or $commercial.role -ne 'building' -or $commercial.rotationYaw -ne 90 -or $commercialRoad.role -ne 'road' -or $commercialJunction.role -ne 'building_road_junction') {
    throw "Commercial building at (0,0) must face its east-adjacent road at yaw 90; found $($commercial.template) yaw=$($commercial.rotationYaw), road=$($commercialRoad.role), junction=$($commercialJunction.role)."
}
Write-Output 'Preview building frontage passed: construction (1,4) yaw=90; house (3,2) yaw=270; commercial (0,0) yaw=90'