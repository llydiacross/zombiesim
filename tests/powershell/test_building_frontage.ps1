param(
    [string]$SettingsPath = '',
    [string]$TrustedMotorwayPlan = '',
    [string]$OutputRoot = '',
    [string]$PlanPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
if ([string]::IsNullOrWhiteSpace($PlanPath)) {
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'zombiesim-building-frontage-check'
    }
    $outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
    [System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
    $planPath = Join-Path $outputRoot 'preview_template_plan.json'
    $listPath = Join-Path $outputRoot 'preview_required_cell_vmfs.txt'
    $cellDirectory = Join-Path $outputRoot 'src'
    $plannerArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) { $plannerArgs.SettingsPath = $SettingsPath }
    if (-not [string]::IsNullOrWhiteSpace($TrustedMotorwayPlan)) { $plannerArgs.TrustedMotorwayPlan = $TrustedMotorwayPlan }
    & (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -MapData (Join-Path $testsBinDirectory 'preview_grid_24x24_seed_1337.json') -Output $planPath -ListOutput $listPath -CellDirectory $cellDirectory @plannerArgs | Out-Null
    if (-not $?) { throw 'Preview planner failed.' }
} else {
    $planPath = [System.IO.Path]::GetFullPath($PlanPath)
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Preview plan not found: $planPath" }
}

$templateRoot = Join-Path ($testsRepoRoot) 'tiletemplates'
$yawByDirection = @{ N = 0; E = 270; S = 180; W = 90 }
$templateDirections = @{}

# Template selection changes as the building pool grows; each selected template must face an adjacent road.
function Get-ExpectedFrontageYaw {
    param([string]$Template, [string]$FrontageDirection)

    if (-not $templateDirections.ContainsKey($Template)) {
        $source = [System.IO.File]::ReadAllText((Join-Path $templateRoot $Template))
        $marker = [regex]::Match($source, '"classname" "zn_tile_direction"\s*"direction" "(\w+)"')
        $templateDirections[$Template] = if ($marker.Success) { $marker.Groups[1].Value.Substring(0, 1).ToUpperInvariant() } else { 'S' }
    }
    $localDirection = $templateDirections[$Template]
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

function Test-CellClearFrontages {
    param([object]$Cell)

    $byPosition = @{}
    foreach ($placement in @($Cell.tilePlacements)) { $byPosition["$($placement.tileX),$($placement.tileY)"] = $placement }
    $checked = 0
    $protectedBlocked = 0
    $blockedRoles = @('building', 'building_occupied', 'landmark', 'landmark_occupied', 'landmark_epicenter', 'landmark_epicenter_occupied', 'safezone_entrance_occupied')
    foreach ($owner in @($Cell.tilePlacements | Where-Object { $_.role -in @('building', 'landmark', 'landmark_epicenter') -and $_.emitsInstance })) {
        $direction = @('N', 'E', 'S', 'W' | Where-Object { [int]$owner.rotationYaw -eq (Get-ExpectedFrontageYaw ([string]$owner.template) $_) })
        if ($direction.Count -ne 1) { throw "Non-cardinal building yaw in cell ($($Cell.x),$($Cell.y)): $($owner.template) yaw=$($owner.rotationYaw)." }
        $x = [int]$owner.tileX; $y = [int]$owner.tileY
        $width = [int]$owner.footprintWidth; $height = [int]$owner.footprintHeight
        $coordinates = switch ($direction[0]) {
            'N' { foreach ($offset in @([int][Math]::Floor(($width - 1) / 2.0), [int][Math]::Floor($width / 2.0)) | Sort-Object -Unique) { "$($x + $offset),$($y - 1)" } }
            'S' { foreach ($offset in @([int][Math]::Floor(($width - 1) / 2.0), [int][Math]::Floor($width / 2.0)) | Sort-Object -Unique) { "$($x + $offset),$($y + $height)" } }
            'W' { foreach ($offset in @([int][Math]::Floor(($height - 1) / 2.0), [int][Math]::Floor($height / 2.0)) | Sort-Object -Unique) { "$($x - 1),$($y + $offset)" } }
            'E' { foreach ($offset in @([int][Math]::Floor(($height - 1) / 2.0), [int][Math]::Floor($height / 2.0)) | Sort-Object -Unique) { "$($x + $width),$($y + $offset)" } }
        }
        $open = @($coordinates | Where-Object { $byPosition.ContainsKey($_) -and [string]$byPosition[$_].role -notin $blockedRoles })
        if ($open.Count -eq 0) {
            if ($owner.role -eq 'building') {
                throw "Building at cell ($($Cell.x),$($Cell.y)) tile ($x,$y) $($owner.template) has a blocked $($direction[0]) frontage."
            }
            $protectedBlocked++
        }
        $checked++
    }
    return [pscustomobject]@{ checked = $checked; protectedBlocked = $protectedBlocked }
}

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$frontageCount = 0
$multiTileCount = 0
$inwardCount = 0
$clearanceCount = 0
$protectedBlockedCount = 0
foreach ($cell in @($plan.cells)) {
    $checked = Test-CellFrontage $cell
    $frontageCount += $checked.Count
    $multiTileCount += @($checked | Where-Object { [int]$_.footprintWidth -gt 1 -or [int]$_.footprintHeight -gt 1 }).Count
    $inwardCount += Test-CellBorderRules -Cell $cell -RoadAdjacent $checked
    $clearance = Test-CellClearFrontages $cell
    $clearanceCount += $clearance.checked
    $protectedBlockedCount += $clearance.protectedBlocked
}
foreach ($reported in @(@(4, 0), @(11, 10))) {
    if (@($plan.cells | Where-Object { $_.x -eq $reported[0] -and $_.y -eq $reported[1] }).Count -ne 1) {
        throw "The reported frontage cell ($($reported[0]),$($reported[1])) is missing or duplicated in the preview plan."
    }
}
if ($frontageCount -eq 0 -or $multiTileCount -eq 0) {
    throw "Frontage coverage is empty: $frontageCount road-adjacent buildings, $multiTileCount multi-tile."
}
Write-Output "Preview building frontage passed: $frontageCount road-adjacent buildings ($multiTileCount multi-tile), $inwardCount roadless buildings, $clearanceCount checked entrances; $protectedBlockedCount protected landmarks reported blocked. No ordinary blocked frontage or single-tile core-corner building."