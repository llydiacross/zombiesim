param(
    [Parameter(Mandatory = $true)]
    [string]$PlanData,
    [string]$BaselinePlanData = '',
    [string]$LayoutDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'outer_edges.psm1') -Force
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Cell variety: $Message" }
    $script:passed++
}

$pool = @('edges/tile_edge_wall_1a.vmf', 'edges/tile_edge_wall_1aa.vmf', 'edges/tile_edge_wall_1aaa.vmf', 'edges/tile_edge_wall_2aaa.vmf')
$route = [pscustomobject]@{ tileX = 2; tileY = -2 }
foreach ($offset in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
    $eligible = @(Get-ZMRoadAdjacentWallPool $pool @($route) (2 + $offset[0]) (-2 + $offset[1]))
    Assert ($eligible.Count -eq 2 -and $eligible[0] -eq $pool[0] -and $eligible[1] -eq $pool[1]) 'Cardinal road neighbours exclude aaa, retaining a and aa.'
}
Assert (@(Get-ZMRoadAdjacentWallPool $pool @($route) 3 -1).Count -eq 4) 'Diagonal slots are unchanged.'
Assert (@(Get-ZMRoadAdjacentWallPool $pool @($route) 4 -2).Count -eq 4) 'Non-adjacent slots retain the whole pool.'
$rejected = $false
try { Get-ZMRoadAdjacentWallPool @($pool[2]) @($route) 1 -2 | Out-Null } catch {
    if ($_.Exception.Message -notlike 'No non-aaa wall template*') { throw }
    $rejected = $true
}
Assert $rejected 'An all-aaa adjacent pool must fail explicitly.'

$edgeSettings = @{
    enabled = $true
    wallVariationTemplates = $pool
    cornerTemplate = 'edges/tile_edge_wall_corner.vmf'
}
$border = @(for ($y = -1; $y -le 5; $y++) { for ($x = -1; $x -le 5; $x++) {
    if ($x -in @(-1, 5) -or $y -in @(-1, 5)) {
        [pscustomobject]@{ tileX = $x; tileY = $y; template = 'border/tile_border_wall.vmf' }
    }
} })
foreach ($source in @('roads/tile_road.vmf', 'roads/tile_motorway.vmf', 'roads/tile_road_bridge.vmf')) {
    foreach ($side in @('N', 'E', 'S', 'W')) {
        foreach ($seed in 1..24) {
            $pieces = @(Get-ZMOuterEdgePlacements ([pscustomobject]@{ environmentProfile = 'grassland'; placementSeed = $seed }) 5 $edgeSettings $border @{} @{ $side = $source })
            $corridor = @($pieces | Where-Object targetname -like 'zm_outer_corridor_*')
            Assert ($corridor.Count -eq 1 -and $corridor[0].template -eq $source) 'Road/motorway/bridge sources are preserved.'
            $flanks = @($pieces | Where-Object {
                [Math]::Abs($_.tileX - $corridor[0].tileX) + [Math]::Abs($_.tileY - $corridor[0].tileY) -eq 1
            })
            Assert ($flanks.Count -eq 2 -and @($flanks | Where-Object template -match '_\d+aaa\.vmf$').Count -eq 0) 'Both outer corridor flanks exclude aaa.'
            Assert (@($pieces | Where-Object targetname -like 'zm_outer_corner_*' | Where-Object template -ne $edgeSettings.cornerTemplate).Count -eq 0) 'Corners remain unchanged.'
        }
    }
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$cells = @{}
$signatures = @{}
foreach ($cell in $plan.cells) {
    $key = "$($cell.x),$($cell.y)"
    Assert (-not $cells.ContainsKey($key)) "Unique cell coordinate $key."
    $cells[$key] = $cell
    $instances = @($cell.tilePlacements | Where-Object emitsInstance | Sort-Object tileY, tileX | Select-Object tileX, tileY, template, rotationYaw, footprintWidth, footprintHeight)
    $signatures[$key] = $instances | ConvertTo-Json -Depth 5 -Compress
    Assert ($cell.cellVariant -le 4) 'At most four variant numbers per recipe.'
}
$pairs = 0
foreach ($key in $cells.Keys) {
    $cell = $cells[$key]
    foreach ($next in @("$($cell.x + 1),$($cell.y)", "$($cell.x),$($cell.y + 1)")) {
        if (-not $cells.ContainsKey($next)) { continue }
        Assert ($cell.cellTemplateFilename -ne $cells[$next].cellTemplateFilename) "Adjacent cells $key / $next must not share a map."
        Assert ($signatures[$key] -cne $signatures[$next]) "Adjacent cells $key / $next must not share the same actual tile layout."
        $pairs++
    }
}
foreach ($group in @($plan.cells | Group-Object cellTemplateFilename)) {
    $first = $group.Group[0]
    foreach ($cell in $group.Group) {
        Assert ($signatures["$($cell.x),$($cell.y)"] -ceq $signatures["$($first.x),$($first.y)"]) "Shared BSP $($group.Name) must have a single consistent layout."
    }
}
if ($BaselinePlanData) {
    $baseline = Get-Content -Raw -LiteralPath $BaselinePlanData | ConvertFrom-Json
    Assert ($baseline.cells.Count -eq $plan.cells.Count) 'Logical cell count is unchanged.'
    foreach ($old in $baseline.cells) {
        $cell = $cells["$($old.x),$($old.y)"]
        foreach ($property in @('worldX', 'worldY', 'topology', 'orientation', 'transportFeature', 'rampExits', 'bridgeRampDirections', 'activeEntrances', 'safeZoneEntrance', 'suppressedBorderTiles', 'waterBorderSides', 'skyboxOceanSides')) {
            Assert (($cell.$property | ConvertTo-Json -Depth 20 -Compress) -ceq ($old.$property | ConvertTo-Json -Depth 20 -Compress)) "Cell $($old.x),$($old.y) preserves $property."
        }
    }
}
if ($LayoutDirectory) {
    foreach ($file in @(Get-ChildItem -LiteralPath $LayoutDirectory -Filter '*.layout.json' -File)) {
        $layout = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
        $placements = @($layout.corePlacements) + @($layout.borderPlacements) + @($layout.outerPlacements)
        $routes = @($placements | Where-Object { [string]$_.template -match '^roads[\\/]' })
        foreach ($wall in @($placements | Where-Object template -match '^(border|edges)[\\/].*_\d+aaa\.vmf$')) {
            Assert (@($routes | Where-Object { [Math]::Abs($_.tileX - $wall.tileX) + [Math]::Abs($_.tileY - $wall.tileY) -eq 1 }).Count -eq 0) "$($file.Name) keeps aaa away from road corridors."
        }
    }
}
Write-Output "Cell variety: $passed assertions passed; $($plan.cells.Count) cells; $($plan.requiredCellCount) recipes; $pairs adjacent pairs have distinct filenames and actual tile layouts."
