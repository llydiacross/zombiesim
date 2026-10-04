Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'zombiesim-building-frontage-check'
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$planPath = Join-Path $outputRoot 'preview_template_plan.json'
$listPath = Join-Path $outputRoot 'preview_required_cell_vmfs.txt'
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData (Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json') -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Preview planner failed.' }

$templateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'tiletemplates'
$yawByDirection = @{ N = 0; E = 270; S = 180; W = 90 }

# Template selection changes as the building pool grows; the contract is that the selected template's own frontage marker faces the road.
function Get-ExpectedFrontageYaw {
    param([string]$Template, [string]$FrontageDirection)

    $source = [System.IO.File]::ReadAllText((Join-Path $templateRoot $Template))
    $marker = [regex]::Match($source, '"classname" "zn_tile_direction"\s*"direction" "(\w+)"')
    $localDirection = if ($marker.Success) { $marker.Groups[1].Value.Substring(0, 1).ToUpperInvariant() } else { 'N' }
    return (($yawByDirection[$FrontageDirection] - $yawByDirection[$localDirection] + 360) % 360)
}

function Assert-Frontage {
    param([object]$Cell, [int]$TileX, [int]$TileY, [string]$FrontageDirection, [int]$NeighbourX, [int]$NeighbourY, [string[]]$NeighbourRoles, [string]$Label)

    $building = @($Cell.tilePlacements | Where-Object { $_.tileX -eq $TileX -and $_.tileY -eq $TileY })[0]
    $neighbour = @($Cell.tilePlacements | Where-Object { $_.tileX -eq $NeighbourX -and $_.tileY -eq $NeighbourY })[0]
    if ($null -eq $building -or $building.role -ne 'building' -or $null -eq $neighbour -or $neighbour.role -notin $NeighbourRoles) {
        throw "$Label at ($TileX,$TileY) must be a building beside a $($NeighbourRoles -join '/') tile at ($NeighbourX,$NeighbourY)."
    }
    $expectedYaw = Get-ExpectedFrontageYaw ([string]$building.template) $FrontageDirection
    if ([int]$building.rotationYaw -ne $expectedYaw) {
        throw "$Label at ($TileX,$TileY) must face $FrontageDirection at yaw $expectedYaw; found $($building.template) yaw=$($building.rotationYaw)."
    }
    return "$Label ($TileX,$TileY) $([System.IO.Path]::GetFileNameWithoutExtension($building.template)) yaw=$($building.rotationYaw)"
}

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$cell = @($plan.cells | Where-Object { $_.x -eq 4 -and $_.y -eq 0 })[0]
if ($null -eq $cell) { throw 'Preview cell (4,0) was not planned.' }
$results = @(
    Assert-Frontage $cell 1 4 'E' 2 4 @('road') 'Building'
    Assert-Frontage $cell 3 2 'W' 2 2 @('road_center') 'Building'
    Assert-Frontage $cell 1 0 'S' 1 2 @('building_road_junction') 'Multi-tile building'
)
$reportedCells = @($plan.cells | Where-Object { $_.x -eq 11 -and $_.y -eq 10 })
if ($reportedCells.Count -ne 1) { throw 'The reported frontage cell (11,10) is missing or duplicated in the preview plan.' }
$results += Assert-Frontage $reportedCells[0] 3 3 'N' 4 2 @('building_road_junction') 'Reported multi-tile building'
Write-Output "Preview building frontage passed: $($results -join '; ')"