param(
    [string]$SettingsPath = '',
    [string]$TrustedMotorwayPlan = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'zombiesim-building-frontage-check'
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$planPath = Join-Path $outputRoot 'preview_template_plan.json'
$listPath = Join-Path $outputRoot 'preview_required_cell_vmfs.txt'
$plannerArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) { $plannerArgs.SettingsPath = $SettingsPath }
if (-not [string]::IsNullOrWhiteSpace($TrustedMotorwayPlan)) { $plannerArgs.TrustedMotorwayPlan = $TrustedMotorwayPlan }
& (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -MapData (Join-Path $testsBinDirectory 'preview_grid_24x24_seed_1337.json') -Output $planPath -ListOutput $listPath @plannerArgs | Out-Null
if (-not $?) { throw 'Preview planner failed.' }

$templateRoot = Join-Path ($testsRepoRoot) 'tiletemplates'
$yawByDirection = @{ N = 0; E = 270; S = 180; W = 90 }

# Template selection changes as the building pool grows; the contract is that the selected template's own frontage marker faces the road.
function Get-ExpectedFrontageYaw {
    param([string]$Template, [string]$FrontageDirection)

    $source = [System.IO.File]::ReadAllText((Join-Path $templateRoot $Template))
    $marker = [regex]::Match($source, '"classname" "zn_tile_direction"\s*"direction" "(\w+)"')
    $localDirection = if ($marker.Success) { $marker.Groups[1].Value.Substring(0, 1).ToUpperInvariant() } else { 'N' }
    return (($yawByDirection[$FrontageDirection] - $yawByDirection[$localDirection] + 360) % 360)
}

# Tile Y grows southward: frontage N is (x, y-1), S is (x, y+1).
$neighbourOffsets = @(@('N', 0, -1), @('S', 0, 1), @('E', 1, 0), @('W', -1, 0))
$roadRolePattern = '^(road|road_center|.*road_junction)$'

# Pool-independent contract: every emitting building whose footprint touches a road tile must face one of those roads.
function Test-CellFrontage {
    param([object]$Cell)

    $byPosition = @{}
    foreach ($placement in @($Cell.tilePlacements)) { $byPosition["$($placement.tileX),$($placement.tileY)"] = $placement }
    $checked = New-Object System.Collections.Generic.List[object]
    foreach ($building in @($Cell.tilePlacements | Where-Object { $_.role -eq 'building' -and $_.emitsInstance })) {
        $roadDirections = @{}
        for ($dx = 0; $dx -lt [int]$building.footprintWidth; $dx++) {
            for ($dy = 0; $dy -lt [int]$building.footprintHeight; $dy++) {
                foreach ($offset in $neighbourOffsets) {
                    $neighbour = $byPosition["$([int]$building.tileX + $dx + $offset[1]),$([int]$building.tileY + $dy + $offset[2])"]
                    if ($null -ne $neighbour -and [string]$neighbour.role -match $roadRolePattern) { $roadDirections[$offset[0]] = $true }
                }
            }
        }
        if ($roadDirections.Count -eq 0) { continue }
        $accepted = @($roadDirections.Keys | Where-Object { [int]$building.rotationYaw -eq (Get-ExpectedFrontageYaw ([string]$building.template) $_) })
        if ($accepted.Count -eq 0) {
            throw "Building at cell ($($Cell.x),$($Cell.y)) tile ($($building.tileX),$($building.tileY)) $($building.template) yaw=$($building.rotationYaw) does not face its adjacent road(s) $(@($roadDirections.Keys | Sort-Object) -join '/')."
        }
        $checked.Add($building) | Out-Null
    }
    return ,$checked
}

# User rules: no single-tile building on a 5x5 core corner, and a building without an adjacent road never faces the cell border.
$coreGridSize = 5
function Test-CellBorderRules {
    param($Cell, $RoadAdjacent)

    $last = $coreGridSize - 1
    $inward = 0
    $roadAdjacentKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($adjacent in $RoadAdjacent) { [void]$roadAdjacentKeys.Add("$([int]$adjacent.tileX),$([int]$adjacent.tileY)") }
    foreach ($building in @($Cell.tilePlacements | Where-Object { $_.role -eq 'building' -and $_.emitsInstance })) {
        $x = [int]$building.tileX; $y = [int]$building.tileY
        $width = [int]$building.footprintWidth; $height = [int]$building.footprintHeight
        if ($width -eq 1 -and $height -eq 1 -and ($x -eq 0 -or $x -eq $last) -and ($y -eq 0 -or $y -eq $last)) {
            throw "Single-tile building at cell ($($Cell.x),$($Cell.y)) tile ($x,$y) $($building.template) occupies a core corner."
        }
        if ($roadAdjacentKeys.Contains("$x,$y")) { continue }
        # Unmarked templates have no authored facing, matching the planner, which leaves them unrotated.
        if (-not ([System.IO.File]::ReadAllText((Join-Path $templateRoot ([string]$building.template))) -match '"classname" "zn_tile_direction"')) { continue }
        $facing = @('N', 'E', 'S', 'W' | Where-Object { [int]$building.rotationYaw -eq (Get-ExpectedFrontageYaw ([string]$building.template) $_) })
        foreach ($direction in $facing) {
            $outward = switch ($direction) { 'N' { $y -eq 0 } 'S' { ($y + $height) -ge $coreGridSize } 'W' { $x -eq 0 } 'E' { ($x + $width) -ge $coreGridSize } default { $false } }
            if ($outward) {
                throw "Building at cell ($($Cell.x),$($Cell.y)) tile ($x,$y) $($building.template) yaw=$($building.rotationYaw) faces the $direction cell border."
            }
        }
        $inward++
    }
    return $inward
}

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$frontageCount = 0
$multiTileCount = 0
$inwardCount = 0
foreach ($cell in @($plan.cells)) {
    $checked = Test-CellFrontage $cell
    $frontageCount += $checked.Count
    $multiTileCount += @($checked | Where-Object { [int]$_.footprintWidth -gt 1 -or [int]$_.footprintHeight -gt 1 }).Count
    $inwardCount += Test-CellBorderRules -Cell $cell -RoadAdjacent $checked
}
foreach ($reported in @(@(4, 0), @(11, 10))) {
    if (@($plan.cells | Where-Object { $_.x -eq $reported[0] -and $_.y -eq $reported[1] }).Count -ne 1) {
        throw "The reported frontage cell ($($reported[0]),$($reported[1])) is missing or duplicated in the preview plan."
    }
}
if ($frontageCount -eq 0 -or $multiTileCount -eq 0) {
    throw "Frontage coverage is empty: $frontageCount road-adjacent buildings, $multiTileCount multi-tile."
}
Write-Output "Preview building frontage passed: $frontageCount road-adjacent buildings ($multiTileCount multi-tile) face an adjacent road; $inwardCount roadless buildings face away from the border; no single-tile core-corner buildings."