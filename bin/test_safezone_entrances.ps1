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
    $template = @($map.cells | Where-Object { $_.worldX -eq 0 -and $_.worldY -eq 0 })[0] | ConvertTo-Json -Depth 60
    function New-EntranceFixture {
        param([object[]]$Cases, [int64]$Seed = 1337)

        $fixture = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
        $fixture.map.seed = $Seed
        $cells = @()
        $zones = @()
        foreach ($case in $Cases) {
            $cell = $template | ConvertFrom-Json
            $cell.x = $case.x
            $cell.y = $case.y
            $cell.worldX = $case.x
            $cell.worldY = $case.y - 12
            $cell.road.connections = @($case.roads)
            $cell.road.degree = @($case.roads).Count
            $cell.road.blockades = @()
            $cell.landmarks = @(if ($case.ContainsKey('landmarks')) { $case.landmarks })
            $cell.safeZone.name = "Fixture $($case.x),$($case.y)"
            $cells += $cell
            $zones += [pscustomobject]@{ name = $cell.safeZone.name; district = $null; difficult = $false; x = $case.x; y = $case.y; worldX = $cell.worldX; worldY = $cell.worldY }
        }
        $fixture.cells = $cells
        $fixture.safeZones = $zones
        return $fixture
    }
    function Invoke-EntranceFixture {
        param([string]$Name, [object]$Fixture)

        $fixturePath = Join-Path $outputDirectory "$Name.json"
        $fixturePlanPath = Join-Path $outputDirectory "$Name-plan.json"
        [System.IO.File]::WriteAllText($fixturePath, (ConvertTo-Json -InputObject $Fixture -Depth 60), [System.Text.UTF8Encoding]::new($false))
        & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData $fixturePath -Output $fixturePlanPath -ListOutput $listPath *> $null
        return Get-Content -Raw -LiteralPath $fixturePlanPath | ConvertFrom-Json
    }

    # Interior coordinates keep these cases off the water border; (0,1) is the water fallback.
    $cases = @(
        @{ name = 'T missing N'; x = 5; y = 5; roads = @('E', 'S', 'W'); slots = @('N') },
        @{ name = 'T missing E'; x = 7; y = 5; roads = @('N', 'S', 'W'); slots = @('E') },
        @{ name = 'T missing S'; x = 9; y = 5; roads = @('N', 'E', 'W'); slots = @('S') },
        @{ name = 'T missing W'; x = 11; y = 5; roads = @('N', 'E', 'S'); slots = @('W') },
        @{ name = 'straight vertical'; x = 13; y = 5; roads = @('N', 'S'); slots = @('E', 'W') },
        @{ name = 'straight horizontal'; x = 15; y = 5; roads = @('E', 'W'); slots = @('N', 'S') },
        @{ name = 'corner north-east'; x = 5; y = 9; roads = @('N', 'E'); slots = @('S', 'W') },
        @{ name = 'corner south-west'; x = 7; y = 9; roads = @('S', 'W'); slots = @('N', 'E') },
        @{ name = 'dead end north'; x = 9; y = 9; roads = @('N'); slots = @('E', 'W') },
        @{ name = 'dead end east'; x = 11; y = 9; roads = @('E'); slots = @('N', 'S') },
        @{ name = 'crossroads'; x = 13; y = 9; roads = @('N', 'E', 'S', 'W'); slots = @('NW', 'NE', 'SW', 'SE') },
        @{ name = 'water fallback'; x = 0; y = 1; roads = @('N', 'E', 'S'); slots = @('NE', 'SE') }
    )
    $slotDefinitions = @{
        N = @{ yaw = 90; front = 'S'; roadY = 2 }; E = @{ yaw = 0; front = 'W'; roadY = 2 }
        S = @{ yaw = 270; front = 'N'; roadY = 2 }; W = @{ yaw = 180; front = 'E'; roadY = 2 }
        NW = @{ yaw = 180; front = 'E'; roadY = 1 }; NE = @{ yaw = 0; front = 'W'; roadY = 1 }
        SW = @{ yaw = 180; front = 'E'; roadY = 3 }; SE = @{ yaw = 0; front = 'W'; roadY = 3 }
    }
    # Map seed 5 activates the north-west water corner, blocking the west side at (0,1).
    $fixturePlan = Invoke-EntranceFixture 'orientations' (New-EntranceFixture $cases 5)
    foreach ($case in $cases) {
        $fixtureCell = @($fixturePlan.cells | Where-Object { $_.x -eq $case.x -and $_.y -eq $case.y })[0]
        $placed = $fixtureCell.safeZoneEntrance
        if ($null -eq $placed -or [string]$placed.slot -notin $case.slots) {
            throw "Fixture '$($case.name)' placed its entrance in an invalid slot: $($placed.slot)."
        }
        $expected = $slotDefinitions[[string]$placed.slot]
        if ([int]$placed.yaw -ne $expected.yaw -or $placed.frontage -ne $expected.front -or
            [int]$placed.adjacentRoadTile.tileX -ne 2 -or [int]$placed.adjacentRoadTile.tileY -ne $expected.roadY) {
            throw "Fixture '$($case.name)' has incorrect entrance placement: $($placed.slot), yaw $($placed.yaw), frontage $($placed.frontage)."
        }
        $occupied = @($fixtureCell.tilePlacements | Where-Object { $_.role -eq 'safezone_entrance_occupied' })
        if ($occupied.Count -ne @($placed.interiorTiles).Count -or @($fixtureCell.tilePlacements | Where-Object { $_.role -like '*carpark*' }).Count -gt 0) {
            throw "Fixture '$($case.name)' lost reserved entrance tiles or placed a carpark in a safe-zone cell."
        }
    }
    if (@(@($fixturePlan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 1 })[0].waterBorderSides | ForEach-Object { $_.side }) -notcontains 'W') {
        throw 'Water fallback fixture did not activate a west water border.'
    }

    $valid = @{ x = 5; y = 5; roads = @('N', 'S') }
    $failures = @(
        @{ name = 'exclusive-landmark'; case = @{ x = 9; y = 9; roads = @('N', 'E', 'S', 'W'); landmarks = @([pscustomobject]@{ label = 'E'; name = 'The Epicenter' }) }; message = 'No valid safe-zone entrance placement at 9,9' },
        @{ name = 'no-road'; case = @{ x = 9; y = 9; roads = @() }; message = 'has no adjacent road' }
    )
    foreach ($failure in $failures) {
        $failed = $null
        try { Invoke-EntranceFixture $failure.name (New-EntranceFixture @($valid, $failure.case)) | Out-Null } catch { $failed = $_.Exception.Message }
        if ($null -eq $failed -or $failed -notlike "*$($failure.message)*") {
            throw "Fixture '$($failure.name)' should fail with '$($failure.message)'; got '$failed'."
        }
    }
    Write-Output "Safe-zone entrance plan passed: $($plannedEntrances.Count) placements; $($cases.Count) orientation and water fixtures; $($failures.Count) rejection fixtures; no gates suppressed."
}
finally {
    Remove-Item -LiteralPath $outputDirectory -Recurse -Force
}
