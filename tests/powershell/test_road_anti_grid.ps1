#Requires -Version 5.1
# Regression for mapGeneration.road.antiGrid: long straight ordinary-road
# avenues are broken into T-sections/jogs without reducing origin connectivity.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$generator = Join-Path $root 'bin\generate_world_cells.ps1'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("zs_antigrid_test_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$failures = [System.Collections.Generic.List[string]]::new()
$assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function New-World {
    param([bool]$Enabled, [string]$Name)

    $settings = Get-Content (Join-Path $root 'generator-settings.json') -Raw | ConvertFrom-Json
    $settings.mapGeneration.road.antiGrid.enabled = $Enabled
    $settingsPath = Join-Path $work "$Name.settings.json"
    $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $settingsPath -Encoding UTF8
    $output = Join-Path $work "$Name.json"
    $log = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generator -WorldProfile preview -SettingsPath $settingsPath -Output $output 2>&1 | Out-String
    if (-not (Test-Path -LiteralPath $output)) { throw "Generator did not write $output.`n$log" }
    return [pscustomobject]@{ Manifest = (Get-Content $output -Raw | ConvertFrom-Json); Log = $log }
}

function Get-RoadIndex {
    param($Manifest)

    $index = @{}
    foreach ($cell in $Manifest.cells) {
        if ($cell.road.present) { $index["$($cell.x),$($cell.y)"] = $cell }
    }
    return $index
}

function Get-OrdinaryRuns {
    param($Manifest, [hashtable]$Roads)

    $grid = [int]$Manifest.map.gridCells
    $originY = [int]$Manifest.map.origin.cellY
    $runs = [System.Collections.Generic.List[int]]::new()
    $isOrdinary = { param($key) $Roads.ContainsKey($key) -and -not $Roads[$key].highway.present -and -not $Roads[$key].highway.bridge }
    foreach ($axis in @('EW', 'NS')) {
        for ($line = 0; $line -lt $grid; $line++) {
            if ($axis -eq 'EW' -and $line -eq $originY) { continue }
            $length = 1
            for ($position = 0; $position -lt $grid; $position++) {
                $key = if ($axis -eq 'EW') { "$position,$line" } else { "$line,$position" }
                $next = if ($axis -eq 'EW') { "$($position + 1),$line" } else { "$line,$($position + 1)" }
                $forward = if ($axis -eq 'EW') { 'E' } else { 'S' }
                $linked = (& $isOrdinary $key) -and (& $isOrdinary $next) -and (@($Roads[$key].road.connections) -contains $forward)
                if ($linked) { $length++; continue }
                if ($length -gt 1) { $runs.Add($length) }
                $length = 1
            }
        }
    }
    return $runs
}

function Get-Reachable {
    param($Manifest, [hashtable]$Roads)

    $offsets = @{ N = @(0, -1); E = @(1, 0); S = @(0, 1); W = @(-1, 0) }
    $start = "0,$([int]$Manifest.map.origin.cellY)"
    $visited = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    [void]$visited.Add($start); $queue.Enqueue($start)
    while ($queue.Count -gt 0) {
        $key = $queue.Dequeue()
        $xy = $key -split ','
        foreach ($direction in @($Roads[$key].road.connections)) {
            $neighbor = "$([int]$xy[0] + $offsets[$direction][0]),$([int]$xy[1] + $offsets[$direction][1])"
            if ($Roads.ContainsKey($neighbor) -and $visited.Add($neighbor)) { $queue.Enqueue($neighbor) }
        }
    }
    return $visited
}

try {
    $maximumRun = 8
    $off = New-World -Enabled $false -Name 'off'
    $on = New-World -Enabled $true -Name 'on'

    Assert-True ($on.Log -match 'Anti-grid breaks=(\d+); jogs=(\d+); unresolved=(\d+)') 'Enabled run must report anti-grid results.'
    $changes = if ($Matches) { [int]$Matches[1] + [int]$Matches[2] } else { 0 }
    Assert-True ($changes -gt 0) 'Preview seed 1337 must break or jog at least one avenue.'
    Assert-True ($off.Log -notmatch 'Anti-grid breaks=') 'Disabled run must not apply the anti-grid pass.'

    $offRoads = Get-RoadIndex $off.Manifest
    $onRoads = Get-RoadIndex $on.Manifest
    $offRuns = Get-OrdinaryRuns $off.Manifest $offRoads
    $onRuns = Get-OrdinaryRuns $on.Manifest $onRoads
    $offLong = @($offRuns | Where-Object { $_ -gt $maximumRun }).Count
    $onLong = @($onRuns | Where-Object { $_ -gt $maximumRun }).Count
    $offMax = ($offRuns | Measure-Object -Maximum).Maximum
    $onMax = ($onRuns | Measure-Object -Maximum).Maximum
    Write-Host "[AntiGrid] off: longest=$offMax over$maximumRun=$offLong; on: longest=$onMax over$maximumRun=$onLong; changes=$changes"
    Assert-True ($offLong -gt 0) 'Fixture must contain over-long avenues without the anti-grid pass.'
    Assert-True ($onLong -lt $offLong) "Anti-grid must reduce over-long avenues ($onLong vs $offLong)."
    Assert-True ($onMax -le $offMax) "Anti-grid must not lengthen the longest avenue ($onMax vs $offMax)."

    $offReachable = Get-Reachable $off.Manifest $offRoads
    $onReachable = Get-Reachable $on.Manifest $onRoads
    $lost = @($offReachable | Where-Object { -not $onReachable.Contains($_) })
    Assert-True ($lost.Count -eq 0) "Anti-grid must preserve origin connectivity; lost: $($lost -join ' ')"

    foreach ($cell in $on.Manifest.cells) {
        if ($cell.highway.present) {
            $twin = $off.Manifest.cells | Where-Object { $_.x -eq $cell.x -and $_.y -eq $cell.y }
            Assert-True ((@($cell.highway.connections) -join '') -eq (@($twin.highway.connections) -join '')) "Highway cell $($cell.x),$($cell.y) connections must be unchanged."
        }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    throw "Anti-grid regression failed $($failures.Count) of $assertions assertions."
}
Write-Host "Anti-grid regression passed $assertions assertions." -ForegroundColor Green
