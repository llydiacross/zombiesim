param(
    [string]$MapData = '',
    [string]$PlanData = '',
    [string]$ReportPath = '',
    [string]$WorldProfile = '',
    [switch]$Preview,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
if ([string]::IsNullOrWhiteSpace($MapData)) {
    $MapData = Join-Path $PSScriptRoot ("{0}_grid_{1}x{1}_seed_1337.json" -f $profile.Config.filePrefix, $profile.Config.gridCells)
}
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $PlanData = [System.IO.Path]::ChangeExtension($MapData, '_template_plan.json')
}
if (-not (Test-Path -LiteralPath $MapData -PathType Leaf)) { throw "Map manifest not found: $MapData" }
if (-not (Test-Path -LiteralPath $PlanData -PathType Leaf)) { throw "Template plan not found: $PlanData" }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $projectRoot (Join-Path 'generated/reachability' ("{0}_reachability_report.json" -f $profile.Name))
}

$map = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$width = [int]$map.map.gridCells
$height = $width
$mapCells = @($map.cells)
$planCells = @($plan.cells)
if ($width -lt 1 -or $mapCells.Count -ne ($width * $height) -or $planCells.Count -ne $mapCells.Count) {
    throw 'Map manifest and template plan must contain the same complete square grid.'
}

$opposites = @{ N = 'S'; E = 'W'; S = 'N'; W = 'E' }
$offsets = @{ N = @(0, -1); E = @(1, 0); S = @(0, 1); W = @(-1, 0) }
$mapByKey = @{}
$planByKey = @{}
foreach ($cell in $mapCells) { $mapByKey["$($cell.x),$($cell.y)"] = $cell }
foreach ($cell in $planCells) { $planByKey["$($cell.x),$($cell.y)"] = $cell }

function Get-BridgeDeckDirections {
    param([object]$Cell)
    if (-not [bool]$Cell.highway.bridge) { return @() }
    $direction = [string]$Cell.highway.bridgeCrossingDirection
    if ($direction -in @('N', 'S')) { return @('N', 'S') }
    if ($direction -in @('E', 'W')) { return @('E', 'W') }
    if (@($Cell.highway.connections) -contains 'N' -and @($Cell.highway.connections) -contains 'S') { return @('N', 'S') }
    return @('E', 'W')
}

$adjacency = @{}
$entranceCells = @{}
foreach ($key in $mapByKey.Keys) {
    $cell = $mapByKey[$key]
    $recipe = $planByKey[$key]
    $openEntrances = @($recipe.activeEntrances | Where-Object { $_ -in @('N', 'E', 'S', 'W') } | Sort-Object -Unique)
    if ($openEntrances.Count -gt 0) { $entranceCells[$key] = $true }
    $adjacency[$key] = [System.Collections.Generic.List[string]]::new()
    $cellBridgeDirections = @(Get-BridgeDeckDirections $cell)

    foreach ($neighbor in @($cell.neighbors)) {
        $direction = [string]$neighbor.direction
        if (-not [bool]$neighbor.inBounds -or $direction -notin $opposites.Keys) { continue }
        $neighborKey = "$($neighbor.x),$($neighbor.y)"
        if (-not $mapByKey.ContainsKey($neighborKey)) { continue }
        $neighborCell = $mapByKey[$neighborKey]
        $reverse = @($neighborCell.neighbors | Where-Object { $_.direction -eq $opposites[$direction] } | Select-Object -First 1)
        if ($reverse.Count -eq 0) { continue }

        $road = [bool]$neighbor.roadConnected -and [bool]$reverse[0].roadConnected
        $highway = [bool]$neighbor.highwayConnected -and [bool]$reverse[0].highwayConnected
        $neighborBridgeDirections = @(Get-BridgeDeckDirections $neighborCell)
        $road = $road -and ($cellBridgeDirections.Count -eq 0 -or $cellBridgeDirections -contains $direction) -and ($neighborBridgeDirections.Count -eq 0 -or $neighborBridgeDirections -contains $opposites[$direction])
        $highway = $highway -and ($cellBridgeDirections.Count -eq 0 -or $cellBridgeDirections -notcontains $direction) -and ($neighborBridgeDirections.Count -eq 0 -or $neighborBridgeDirections -notcontains $opposites[$direction])
        $blocked = (@($cell.road.blockades) -contains $direction) -or (@($neighborCell.road.blockades) -contains $opposites[$direction])
        if (($road -and -not $blocked) -or $highway) { $adjacency[$key].Add($neighborKey) }
    }
}

$origin = $map.map.origin
$originKey = "$($origin.cellX),$($origin.cellY)"
if (-not $mapByKey.ContainsKey($originKey)) { throw "World origin cell is missing: $originKey" }
$reachable = @{}
$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue($originKey)
while ($queue.Count -gt 0) {
    $key = $queue.Dequeue()
    if ($reachable.ContainsKey($key)) { continue }
    $reachable[$key] = $true
    foreach ($neighborKey in $adjacency[$key]) {
        if (-not $reachable.ContainsKey($neighborKey)) { $queue.Enqueue($neighborKey) }
    }
}

$inaccessible = @($mapByKey.Keys | Where-Object { -not $reachable.ContainsKey($_) })
$noEntranceCells = @($mapByKey.Keys | Where-Object { -not $entranceCells.ContainsKey($_) })
$deadCells = @($noEntranceCells | Where-Object { -not $reachable.ContainsKey($_) })
$unreachableLandmarks = @()
foreach ($key in @($inaccessible | Where-Object { $entranceCells.ContainsKey($_) })) {
    foreach ($landmark in @($mapByKey[$key].landmarks)) {
        $unreachableLandmarks += [pscustomobject]@{ x = [int]$mapByKey[$key].x; y = [int]$mapByKey[$key].y; name = [string]$landmark.name; label = [string]$landmark.label }
    }
}
$inaccessibleRecipes = @{}
$noEntranceRecipes = @{}
$allRecipeUsage = @{}
foreach ($key in $mapByKey.Keys) {
    $recipeName = [string]$planByKey[$key].cellTemplateFilename
    if (-not $allRecipeUsage.ContainsKey($recipeName)) { $allRecipeUsage[$recipeName] = [System.Collections.Generic.List[string]]::new() }
    $allRecipeUsage[$recipeName].Add($key)
}
foreach ($key in $inaccessible) {
    $recipeName = [string]$planByKey[$key].cellTemplateFilename
    if (-not $inaccessibleRecipes.ContainsKey($recipeName)) { $inaccessibleRecipes[$recipeName] = [System.Collections.Generic.List[string]]::new() }
    $inaccessibleRecipes[$recipeName].Add($key)
}
foreach ($key in $deadCells) {
    $recipeName = [string]$planByKey[$key].cellTemplateFilename
    if (-not $noEntranceRecipes.ContainsKey($recipeName)) { $noEntranceRecipes[$recipeName] = [System.Collections.Generic.List[string]]::new() }
    $noEntranceRecipes[$recipeName].Add($key)
}
$exclusiveRecipes = @($inaccessibleRecipes.Keys | Where-Object { $inaccessibleRecipes[$_].Count -eq $allRecipeUsage[$_].Count } | Sort-Object)
$noEntranceOnlyRecipes = @($noEntranceRecipes.Keys | Where-Object { $noEntranceRecipes[$_].Count -eq $allRecipeUsage[$_].Count } | Sort-Object)
$unreachableSettlements = @($inaccessible | Where-Object { $entranceCells.ContainsKey($_) -and [bool]$mapByKey[$_].building.present } | Sort-Object)
$unreachableRecipeNames = @($inaccessibleRecipes.Keys | Sort-Object)
$exclusiveRecipeNames = @($exclusiveRecipes)
$cellResults = @($mapByKey.Keys | Sort-Object { [int](($_ -split ',')[1]) }, { [int](($_ -split ',')[0]) } | ForEach-Object {
    $cell = $mapByKey[$_]
    $recipe = $planByKey[$_]
    [pscustomobject]@{
        x = [int]$cell.x
        y = [int]$cell.y
        map = [System.IO.Path]::GetFileNameWithoutExtension([string]$recipe.cellTemplateFilename)
        recipe = [string]$recipe.cellTemplateFilename
        hasEntrance = $entranceCells.ContainsKey($_)
        reachableFromOrigin = $reachable.ContainsKey($_)
        noEntrance = -not $entranceCells.ContainsKey($_)
        entranceReachableFromOrigin = $entranceCells.ContainsKey($_) -and $reachable.ContainsKey($_)
        building = [bool]$cell.building.present
        entrances = @($recipe.activeEntrances)
    }
})
$report = [ordered]@{
    schemaVersion = 1
    worldProfile = $profile.Name
    mapData = [System.IO.Path]::GetFullPath($MapData)
    planData = [System.IO.Path]::GetFullPath($PlanData)
    gridCells = $width
    totalCells = $mapByKey.Count
    reachableCells = $reachable.Count
    unreachableCells = $inaccessible.Count
    cellsWithoutExternalEntrances = $noEntranceCells.Count
    cellsWithEntrancesDisconnectedFromOrigin = @($inaccessible | Where-Object { $entranceCells.ContainsKey($_) }).Count
    unreachableSettlementCells = $unreachableSettlements
    unreachableLandmarks = @($unreachableLandmarks | Sort-Object name, y, x)
    uniqueRecipes = $allRecipeUsage.Count
    recipesUsedByUnreachableCells = $inaccessibleRecipes.Count
    exclusiveRecipeBspCost = $exclusiveRecipes.Count
    recipesUsedByUnreachableCellsOnly = $unreachableRecipeNames
    exclusiveRecipeBspNames = $exclusiveRecipeNames
    cellsWithoutEntrances = $noEntranceCells.Count
    completelyInaccessibleCells = $deadCells.Count
    recipesUsedByCompletelyInaccessibleCells = $noEntranceRecipes.Count
    exclusiveRecipeBspCostForCompletelyInaccessibleCells = $noEntranceOnlyRecipes.Count
    recipesUsedByCellsWithoutEntrances = $noEntranceRecipes.Count
    exclusiveRecipeBspCostForCellsWithoutEntrances = $noEntranceOnlyRecipes.Count
    exclusiveNoEntranceRecipes = @($noEntranceOnlyRecipes | ForEach-Object { [pscustomobject]@{ recipe = $_; cells = @($noEntranceRecipes[$_]) } })
    exclusiveRecipes = @($exclusiveRecipes | ForEach-Object { [pscustomobject]@{ recipe = $_; cells = @($inaccessibleRecipes[$_]) } })
    cells = $cellResults
}
$reportDirectory = Split-Path -Parent $ReportPath
[System.IO.Directory]::CreateDirectory($reportDirectory) | Out-Null
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-Output ("Reachability ({0}): reachable {1}/{2}; unreachable {3}; unreachable settlement cells {4}; recipes used by unreachable cells {5}; exclusive recipe BSP cost {6}; report: {7}" -f $profile.Name,$reachable.Count,$mapByKey.Count,$inaccessible.Count,$unreachableSettlements.Count,$inaccessibleRecipes.Count,$exclusiveRecipes.Count,$ReportPath)