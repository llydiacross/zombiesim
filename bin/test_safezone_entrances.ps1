Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('zombiesim-safezone-entrance-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
try {
    $manifest = Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json'
    $planPath = Join-Path $outputDirectory 'safezone-plan.json'
    $listPath = Join-Path $outputDirectory 'required-vmfs.txt'
    & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData $manifest -Output $planPath -ListOutput $listPath | Out-Null
    if (-not $?) { throw 'Preview safe-zone entrance planning failed.' }

    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
    $map = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
    $plannedEntrances = @($plan.cells | Where-Object { $null -ne $_.safeZoneEntrance })
    if ($plannedEntrances.Count -ne @($map.safeZones).Count) {
        throw "Expected one entrance per safe zone: $($plannedEntrances.Count) planned for $(@($map.safeZones).Count) zones."
    }
    foreach ($cell in $plannedEntrances) {
        $entrance = $cell.safeZoneEntrance
        $suppressed = @($cell.suppressedBorderTiles)
        $expectedRing = if ($entrance.mode -eq 'edge') { 3 } elseif ($entrance.mode -eq 'corner') { 5 } else { throw "Invalid placement mode at $($cell.x),$($cell.y)." }
        if ($suppressed.Count -ne $expectedRing -or @($entrance.interiorTiles).Count + $suppressed.Count -ne 9) {
            throw "Entrance at $($cell.x),$($cell.y) does not cover exactly nine tiles."
        }
        foreach ($tile in $suppressed) {
            if (([int]$tile.tileX -eq 2 -and [int]$tile.tileY -in @(-1, 5)) -or
                ([int]$tile.tileY -eq 2 -and [int]$tile.tileX -in @(-1, 5))) {
                if ($cell.activeEntrances -contains $(if ($tile.tileX -eq -1) { 'W' } elseif ($tile.tileX -eq 5) { 'E' } elseif ($tile.tileY -eq -1) { 'N' } else { 'S' })) {
                    throw "Entrance at $($cell.x),$($cell.y) overlaps an active transition gate."
                }
            }
        }
        if (@($cell.tilePlacements | Where-Object { $_.role -eq 'safezone_entrance_occupied' }).Count -ne @($entrance.interiorTiles).Count) {
            throw "Entrance at $($cell.x),$($cell.y) did not reserve its playable tiles."
        }
    }
    $origin = @($plannedEntrances | Where-Object { $_.worldX -eq 0 -and $_.worldY -eq 0 })
    if ($origin.Count -ne 1 -or $origin[0].orientation -ne 'missing-west' -or
        $origin[0].safeZoneEntrance.slot -ne 'W' -or $origin[0].safeZoneEntrance.frontage -ne 'E' -or
        [int]$origin[0].safeZoneEntrance.yaw -ne 180) {
        throw 'Storm Drain origin must occupy the west edge, facing east onto the missing-west T-junction.'
    }
    $expectedYaw = @{ N = 90; E = 0; S = 270; W = 180 }
    foreach ($missingSide in @('N', 'E', 'S', 'W')) {
        $fixture = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
        $originCell = @($fixture.cells | Where-Object { $_.worldX -eq 0 -and $_.worldY -eq 0 })[0]
        $originCell.road.connections = @(@('N', 'E', 'S', 'W') | Where-Object { $_ -ne $missingSide })
        $originCell.road.degree = 3
        $originCell.road.blockades = @()
        $fixturePath = Join-Path $outputDirectory "missing-$missingSide.json"
        [System.IO.File]::WriteAllText($fixturePath, (ConvertTo-Json -InputObject $fixture -Depth 60), [System.Text.UTF8Encoding]::new($false))
        & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData $fixturePath -Output $planPath -ListOutput $listPath | Out-Null
        if (-not $?) { throw "T-junction fixture missing $missingSide did not plan." }
        $fixturePlan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
        $placed = @($fixturePlan.cells | Where-Object { $_.worldX -eq 0 -and $_.worldY -eq 0 })[0].safeZoneEntrance
        if ($placed.mode -ne 'edge' -or $placed.slot -ne $missingSide -or [int]$placed.yaw -ne $expectedYaw[$missingSide] -or
            $placed.adjacentRoadTile.tileX -ne 2 -or $placed.adjacentRoadTile.tileY -ne 2) {
            throw "T-junction missing $missingSide has incorrect entrance placement: $($placed.slot), yaw $($placed.yaw)."
        }
    }
    Write-Output "Safe-zone entrance plan passed: $($plannedEntrances.Count) placements; all four T-junction orientations; no gates suppressed."
}
finally {
    Remove-Item -LiteralPath $outputDirectory -Recurse -Force
}
