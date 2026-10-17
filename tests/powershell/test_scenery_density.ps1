Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'outer_edges.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'scenery_density.psm1') -Force
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Scenery density: $Message" }
    $script:passed++
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $rejected = $true
    }
    Assert $rejected "Expected explicit rejection matching '$Pattern'."
}

foreach ($case in @(
    @('buildings/tile_building_6a.vmf', 1),
    @('buildings/tile_industrial_3c.vmf', 1),
    @('border/tile_border_wall_1bb.vmf', 2),
    @('edges/tile_edge_wall_2aaa.vmf', 3),
    @('buildings/tile_epicenter_1aaa_3x.vmf', 3),
    @('buildings/tile_building_2aa_2x2.vmf', 2),
    @('roads/tile_motorway_1aaa_3x4.vmf', 3),
    @('BORDER\TILE_BORDER_WALL_1BB.VMF', 2),
    @('border/tile_border_water_pier_1.vmf', 0),
    @('edges/tile_edge_wall_corner.vmf', 0),
    @('border/tile_border_water_none.vmf', 0),
    @('roads/tile_motorway_corner_5x3.vmf', 0)
)) {
    Assert ((Get-ZMTemplateDensityTag $case[0]) -eq $case[1]) "Classify $($case[0])."
}
Assert-Rejected { Get-ZMTemplateDensityTag 'tile_wall_1aaaa.vmf' } 'Unsupported scenery density tag*'
Assert-Rejected { Get-ZMTemplateDensityTag 'tile_wall_1a!.vmf' } 'Malformed scenery density tag*'

$wallRecipe = [pscustomobject]@{
    x = 12; y = 9; environmentProfile = 'grassland'; topology = 'road-straight'; orientation = 'horizontal'
    landmarks = @(); cellVariant = 2; sceneryDensityPolicyVersion = 1
    sceneryDensityTier = 3; sceneryDensitySource = 'inland_band'; sceneryInlandDistance = 8
    buildingDensityTier = 3
}
$wallPool = @(
    'border/tile_border_wall_1a.vmf',
    'border/tile_border_wall_1aa.vmf',
    'border/tile_border_wall_1aaa.vmf'
)
for ($tier = 1; $tier -le 3; $tier++) {
    $zone = switch ($tier) {
        1 { Get-ZMSceneryDensityZone 0 'grassland' }
        2 { Get-ZMSceneryDensityZone 3 'grassland' }
        3 { Get-ZMSceneryDensityZone 8 'grassland' }
    }
    $wallRecipe.sceneryDensityTier = $zone.tier
    $wallRecipe.sceneryDensitySource = $zone.source
    $wallRecipe.sceneryInlandDistance = $zone.inlandDistance
    $wallRecipe.buildingDensityTier = $zone.tier
    foreach ($slot in @('N,-1,2', 'E,5,2', 'S,2,5', 'W,-1,2')) {
        $parts = $slot -split ','
        $first = Get-ZMSceneryWallTemplateSelection $wallRecipe $wallPool 1337 'border' "$($parts[1]),$($parts[2])" 'border_wall' $false
        $repeat = Get-ZMSceneryWallTemplateSelection $wallRecipe $wallPool 1337 'border' "$($parts[1]),$($parts[2])" 'border_wall' $false
        Assert (($first | ConvertTo-Json -Depth 8 -Compress) -ceq ($repeat | ConvertTo-Json -Depth 8 -Compress)) "Wall selection for tier $tier slot $slot is deterministic."
        Assert ($first.template -eq $first.selection.template) "Tier $tier selection records its emitted wall."
        Assert ($first.selection.actualTag -in @(0, $first.selection.targetTier)) "Tier $tier selects only neutral or target-tier walls."
        if ($tier -eq 1) { Assert ($first.selection.targetTier -eq 1) "Low-zone border slot $slot remains low." }
    }
}
$wallRecipe.sceneryDensityTier = 3
$wallRecipe.sceneryDensitySource = 'inland_band'
$wallRecipe.sceneryInlandDistance = 8
$wallRecipe.buildingDensityTier = 3
$routeWall = Get-ZMSceneryWallTemplateSelection $wallRecipe $wallPool 1337 'border' '2,-1' 'border_wall' $true
Assert ($routeWall.selection.routeAdjacentWall -and $routeWall.selection.targetTier -eq 2 -and $routeWall.selection.actualTag -ne 3) 'High-zone route-adjacent walls use the medium target and never select aaa.'
$neutralWall = Get-ZMSceneryWallTemplateSelection $wallRecipe @('border/tile_border_ra_wall.vmf') 1337 'border' '2,-1' 'border_wall' $true
Assert ($neutralWall.template -eq 'border/tile_border_ra_wall.vmf' -and $neutralWall.selection.actualTag -eq 0) 'Profile-specific neutral wall families remain valid at every density tier.'
Assert-Rejected {
    Get-ZMSceneryWallTemplateSelection $wallRecipe @('border/tile_border_wall_1a.vmf') 1337 'border' '2,2' 'border_wall' $false
} '*Required scenery pool unavailable*'
$legacyWallRecipe = [pscustomobject]@{ x = 1; y = 2 }
Assert ($null -eq (Get-ZMSceneryWallTemplateSelection $legacyWallRecipe $wallPool 1337 'border' '1,2' 'border_wall' $false)) 'Metadata-less legacy recipes retain the established wall selector.'

$outerWallSettings = @{
    enabled = $true
    wallVariationTemplates = $wallPool
    cornerTemplate = 'edges/tile_edge_wall_corner.vmf'
}
$outerBorder = @(
    for ($y = -1; $y -le 5; $y++) {
        for ($x = -1; $x -le 5; $x++) {
            if ($x -in @(-1, 5) -or $y -in @(-1, 5)) {
                [pscustomobject]@{ tileX = $x; tileY = $y; template = 'border/tile_border_wall.vmf' }
            }
        }
    }
)
$outerRecipe = [pscustomobject]@{
    x = 12; y = 9; environmentProfile = 'grassland'; topology = 'road-straight'; orientation = 'horizontal'
    landmarks = @(); cellVariant = 2; placementSeed = 1337
    sceneryDensityPolicyVersion = 1; sceneryDensityTier = 3; sceneryDensitySource = 'inland_band'
    sceneryInlandDistance = 8; buildingDensityTier = 3
}
$outerWalls = @(Get-ZMOuterEdgePlacements $outerRecipe 5 $outerWallSettings $outerBorder @{} @{} 1337 | Where-Object targetname -like 'zm_outer_wall_*')
Assert ($outerWalls.Count -gt 0 -and @($outerWalls | Where-Object { $null -eq $_.sceneryDensitySelection }).Count -eq 0) 'Policy-v1 outer walls record density selections.'
Assert (@($outerWalls | Where-Object { $_.sceneryDensitySelection.actualTag -notin @(0, $_.sceneryDensitySelection.targetTier) }).Count -eq 0) 'Outer walls obey their selected density target.'
$outerLegacy = [pscustomobject]@{ x = 12; y = 9; environmentProfile = 'grassland'; placementSeed = 1337 }
$legacyOuterWalls = @(Get-ZMOuterEdgePlacements $outerLegacy 5 $outerWallSettings $outerBorder @{} @{} 1337 | Where-Object targetname -like 'zm_outer_wall_*')
Assert (@($legacyOuterWalls | Where-Object { $null -ne $_.PSObject.Properties['sceneryDensitySelection'] }).Count -eq 0) 'Metadata-less outer-edge recipes keep legacy deterministic variation.'

# Route adjacency comes from the complete occupied corridor footprint, not template-path centrelines.
$routeFixture = @(
    [ordered]@{ tileX = 0; tileY = 0; template = 'roads/tile_road.vmf'; role = 'road' }
    [pscustomobject]@{ tileX = 1; tileY = 1; template = 'roads/tile_motorway_wide.vmf'; role = 'motorway_assembly'; footprintWidth = 3; footprintHeight = 1; emitsInstance = $true }
    [pscustomobject]@{ tileX = 0; tileY = 4; template = 'terrain/tile_grass.vmf'; role = 'motorway_external_occupied'; emitsInstance = $false }
    [pscustomobject]@{ tileX = 4; tileY = 4; template = 'roads/tile_motorway_wide.vmf'; role = 'motorway_occupied'; footprintWidth = 3; footprintHeight = 1; emitsInstance = $false }
    [pscustomobject]@{ tileX = 2; tileY = 3; template = 'carparks/tile_carpark_lane.vmf'; role = 'carpark_lane' }
    [pscustomobject]@{ tileX = 3; tileY = 3; template = 'carparks/tile_carpark_entrance.vmf'; role = 'carpark_entrance' }
    [pscustomobject]@{ tileX = 4; tileY = 0; template = 'buildings/tile_house.vmf'; role = 'building' }
    [pscustomobject]@{ tileX = 2; tileY = 2; template = 'terrain/tile_grass.vmf'; role = 'terrain' }
)
$routeLeases = @(
    [pscustomobject]@{ tileX = 2; tileY = -1; ring = 'border'; owner = 'motorway:-1'; emitsInstance = $false }
    [pscustomobject]@{ tileX = 2; tileY = -2; ring = 'outer'; owner = 'motorway:-2'; emitsInstance = $false }
)
$routeKeys = @(Get-ZMRouteFootprintSlots $routeFixture $routeLeases @('core', 'border') | ForEach-Object { "$($_.tileX),$($_.tileY)" })
foreach ($key in @('0,0', '1,1', '2,1', '3,1', '0,4', '4,4', '2,-1')) {
    Assert ($key -in $routeKeys) "Route footprint includes occupied corridor slot $key."
}
foreach ($key in @('5,4', '2,3', '3,3', '4,0', '2,2', '2,-2')) {
    Assert ($key -notin $routeKeys) "Route footprint excludes non-corridor or other-ring slot $key."
}
Assert ($routeKeys.Count -eq 7) 'Route footprint slots are unique.'
$wideRoadWallPool = @(Get-ZMRoadAdjacentWallPool $wallPool @(Get-ZMRouteFootprintSlots $routeFixture) 3 0)
Assert (@($wideRoadWallPool | Where-Object { $_ -match '_\d+aaa\.vmf$' }).Count -eq 0) 'A wall beside the widened end of a multi-tile corridor excludes aaa walls.'
$carparkWallPool = @(Get-ZMRoadAdjacentWallPool $wallPool @(Get-ZMRouteFootprintSlots $routeFixture) 2 4)
Assert (@($carparkWallPool | Where-Object { $_ -match '_\d+aaa\.vmf$' }).Count -gt 0) 'Carpark lanes and entrances are not corridors for the aaa wall exclusion.'
Assert ($null -eq (Get-ZMRecipeRouteLeases ([pscustomobject]@{ x = 0 })) -or @(Get-ZMRecipeRouteLeases ([pscustomobject]@{ x = 0 })).Count -eq 0) 'Recipes without motorway inspection contribute no leases.'

$leaseRecipe = $outerRecipe.PSObject.Copy()
$leaseRecipe | Add-Member -NotePropertyName motorwayCellInspection -NotePropertyValue ([pscustomobject]@{ leases = @(
    [pscustomobject]@{ tileX = 1; tileY = -1; ring = 'border'; owner = 'motorway:-1'; emitsInstance = $false }
) })
$leaseOuter = @(Get-ZMOuterEdgePlacements $leaseRecipe 5 $outerWallSettings $outerBorder @{} @{} 1337 | Where-Object targetname -like 'zm_outer_wall_*')
$leaseFlank = @($leaseOuter | Where-Object { $_.tileX -eq 1 -and $_.tileY -eq -2 })
$leaseControl = @($leaseOuter | Where-Object { $_.tileX -eq 3 -and $_.tileY -eq -2 })
Assert ($leaseFlank.Count -eq 1 -and $leaseFlank[0].sceneryDensitySelection.routeAdjacentWall -and $leaseFlank[0].sceneryDensitySelection.targetTier -eq 2) 'Outer walls beside a border-ring motorway lease use the route-adjacent medium target.'
Assert ($leaseFlank[0].template -notmatch '_\d+aaa\.vmf$') 'Outer walls beside a motorway lease never select aaa.'
Assert ($leaseControl.Count -eq 1 -and -not $leaseControl[0].sceneryDensitySelection.routeAdjacentWall) 'Outer walls away from the lease remain unconstrained.'
$plainFlank = @($outerWalls | Where-Object { $_.tileX -eq 1 -and $_.tileY -eq -2 })
Assert ($plainFlank.Count -eq 1 -and -not $plainFlank[0].sceneryDensitySelection.routeAdjacentWall) 'Without the lease, the same outer slot is not route-adjacent.'
Assert-Rejected { Get-ZMTemplateDensityTag 'tile_wall_1a.vmx' } 'Scenery density requires a VMF*'

foreach ($tier in 1..3) {
    $counts = @{ 1 = 0; 2 = 0; 3 = 0 }
    foreach ($roll in 0..99) {
        $target = Get-ZMSceneryTargetTier $tier $roll
        $expected = if ($tier -eq 1) { 1 } elseif ($roll -lt 95) { $tier } else { 5 - $tier }
        Assert ($target -eq $expected) "Exact threshold tier=$tier roll=$roll."
        $counts[$target]++
        $wallTarget = Get-ZMSceneryTargetTier $tier $roll -RouteAdjacentWall
        Assert ($wallTarget -eq $(if ($tier -eq 1) { 1 } else { 2 })) 'Route wall exception ignores the ordinary mix.'
    }
    Assert ($counts[$tier] -eq $(if ($tier -eq 1) { 100 } else { 95 })) 'Exact 100-bucket target distribution.'
}

$pool = @('edges/tile_edge_wall_1a.vmf', 'edges/tile_edge_wall_1bb.vmf', 'edges/tile_edge_wall_1aaa.vmf', 'edges/tile_edge_wall.vmf')
foreach ($tier in 1..3) {
    foreach ($roll in @(0, 94, 95, 99)) {
        foreach ($choice in 0..7) {
            $a = Select-ZMSceneryTemplate $pool $tier $roll $choice 'fixture/outer/1,2/wall'
            $b = Select-ZMSceneryTemplate @($pool[3], $pool[1], $pool[0], $pool[2], $pool[0]) $tier $roll $choice 'fixture/outer/1,2/wall'
            Assert ($a.template -ceq $b.template) 'Input enumeration and duplicate paths do not affect choice.'
            Assert ($a.actualTag -eq 0 -or $a.actualTag -eq $a.targetTier) 'Only selected tier or neutral is eligible.'
            Assert ($a.excluded.Count -eq 2) 'Rejected tags are reported.'
        }
    }
    $neutral = Select-ZMSceneryTemplate @('border/tile_border_water_pier_1.vmf') $tier 99 0 'fixture/water'
    Assert ($neutral.actualTag -eq 0 -and $neutral.status -eq 'selected') 'Compatible neutral works at all tiers.'
    $shortage = Select-ZMSceneryTemplate @() $tier 99 0 'fixture/optional'
    Assert ($shortage.status -eq 'shortage_keep_terrain' -and $null -eq $shortage.template) 'Optional shortage is explicit.'
    Assert-Rejected { Select-ZMSceneryTemplate @() $tier 0 0 'cell=4,5 side=N pool=wall' -Required } 'Required scenery pool unavailable at cell=4,5 side=N pool=wall*'
}
$shortage = Select-ZMSceneryTemplate @('buildings/tile_building_6a.vmf') 3 0 0 'fixture/building'
Assert ($shortage.status -eq 'shortage_keep_terrain' -and $shortage.targetTier -eq 3) 'No forbidden low fallback or reroll.'
Assert-Rejected { Select-ZMSceneryTemplate @('edges/tile_edge_wall_1aaa.vmf') 3 0 0 'fixture/route' -RouteAdjacentWall -Required } 'Required scenery pool unavailable*target=2*'
Assert-Rejected { Select-ZMSceneryTemplate @('tile_wall_1aaaa.vmf') 1 0 0 'fixture/bad-tag' } 'Unsupported scenery density tag*'

$context = @{ Seed = 1337; CellPolicy = 'recipe=grass/open'; Ring = 'outer'; Slot = '1,2'; Role = 'wall'; Variant = 2 }
$hash = Get-ZMScenerySelectionHash @context
Assert ($hash -eq (Get-ZMScenerySelectionHash @context)) 'Stable selection hash.'
Assert ($hash -eq 913026980) 'Pinned scenery-v1 SHA256 hash value is independent of process state.'
Assert ($hash -ne (Get-ZMScenerySelectionHash @context -Purpose template)) 'Independent tier/template streams.'
foreach ($name in @('Seed', 'CellPolicy', 'Ring', 'Slot', 'Role', 'Variant')) {
    $changed = $context.Clone()
    $changed[$name] = if ($name -in @('Seed', 'Variant')) { [int]$changed[$name] + 1 } else { "$($changed[$name])-changed" }
    Assert ($hash -ne (Get-ZMScenerySelectionHash @changed)) "Hash includes $name."
}
$oldCulture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
    Assert ($hash -eq (Get-ZMScenerySelectionHash @context)) 'Selection hash ignores current locale.'
    $cultureChoice = Select-ZMSceneryTemplate $pool 2 0 7 'fixture/culture'
    Assert ($cultureChoice.template -ceq (Select-ZMSceneryTemplate @($pool[2], $pool[0], $pool[3], $pool[1]) 2 0 7 'fixture/culture').template) 'Ordinal pool ordering ignores locale.'
}
finally { [Threading.Thread]::CurrentThread.CurrentCulture = $oldCulture }

$land = @(foreach ($y in 0..2) { foreach ($x in 0..11) { [pscustomobject]@{ x = $x; y = $y } } })
$shore = @($land | Where-Object x -eq 0)
$distances = Get-ZMSceneryInlandDistances $land $shore
foreach ($cell in $land) {
    Assert ($distances["$($cell.x),$($cell.y)"] -eq $cell.x) 'Actual west ocean, not arbitrary north/east/south edges.'
    foreach ($profile in @('grassland', 'commercial', 'financial', 'settlement', 'radioactive', 'parkland')) {
        $zone = Get-ZMSceneryDensityZone $distances["$($cell.x),$($cell.y)"] $profile
        $expected = if ($cell.x -lt 3) { 1 } elseif ($cell.x -ge 8 -or $profile -in @('commercial', 'financial')) { 3 } else { 2 }
        Assert ($zone.tier -eq $expected) 'Coast wins; only approved semantic districts raise inland density.'
        Assert ($zone.source -eq $(if ($cell.x -lt 3) { 'protected_coast' } elseif ($cell.x -lt 8 -and $profile -in @('commercial', 'financial')) { "district:$profile" } else { 'inland_band' })) 'Resolved tier includes source.'
    }
}
$bentLand = @([pscustomobject]@{ x = 0; y = 0 }, [pscustomobject]@{ x = 0; y = 1 }, [pscustomobject]@{ x = 1; y = 1 })
$bent = Get-ZMSceneryInlandDistances $bentLand @($bentLand[0])
Assert ($bent['1,1'] -eq 2) 'Cardinal land distance does not shortcut diagonally across missing land.'
Assert-Rejected { Get-ZMSceneryInlandDistances $land @() } '*explicit actual-ocean boundary*'
Assert-Rejected { Get-ZMSceneryInlandDistances $land @([pscustomobject]@{ x = -1; y = 0 }) } '*not a land cell*'
Assert-Rejected { Get-ZMSceneryInlandDistances @($land[0], $land[0]) @($land[0]) } '*Duplicate scenery land cell*'
Assert-Rejected { Get-ZMSceneryInlandDistances @($land[0], [pscustomobject]@{ x = 2; y = 0 }) @($land[0]) } '*cannot reach the actual ocean*'

$root = $testsRepoRoot
$profileSettings = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$plannerSettings = $profileSettings.Settings.cellPlanning
$sceneryDensityPolicyEnabled = $true
foreach ($source in @(
    @{ file = 'plan_cell_templates.ps1'; functions = @('Get-EnvironmentProfile', 'Get-BuildingDensityTier', 'Get-RecipePlacementSeed', 'Get-SceneryTemplateSelection', 'Set-ScenerySelectionMetadata', 'Get-BuildingDensity', 'Get-TemplateFootprint', 'Get-RotatedFootprint', 'Get-LandmarkTemplate', 'Get-LandmarkTemplateSelection', 'Get-CellTilePlacements', 'Get-CellLayoutSignature', 'Get-CellRecipeLayoutIdentity', 'Get-CellRecipeContentSignature', 'Get-RecipeSignatureDifferencePaths', 'Assert-RecipeFilenameContentUnique') },
    @{ file = 'build_cell_vmfs.ps1'; functions = @('Get-BorderCornerTemplate', 'Assert-BorderCornerVariationSettings') },
    @{ file = 'generate_world_cells.ps1'; functions = @('Move-RadiationSourcesToReachableRoadCells', 'Get-EnvironmentTags', 'Get-GeneratorSceneryDensityZone', 'Test-LandmarkTemplateSupportsDensityZone', 'Get-LandmarkDensityShortages', 'Export-MapData') },
    @{ file = 'export_runtime_world_data.ps1'; functions = @('Get-RuntimeSceneryDensityFields') }
)) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory $source.file), [ref]$tokens, [ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) "PowerShell parses $($source.file)."
    foreach ($name in $source.functions) {
        $definition = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        Assert ($definition.Count -eq 1) "Exactly one production function $name."
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }
}

$recipeIdentityCell = [pscustomobject]@{
    placementSeed = 773; tilePlacements = @(); sceneryDensityPolicyVersion = 1
}
$identityA = Get-CellRecipeLayoutIdentity $recipeIdentityCell 1337
$identityB = Get-CellRecipeLayoutIdentity $recipeIdentityCell 1338
Assert ($identityA -cne $identityB) 'Policy-v1 recipe identity separates map seeds used by boundary wall selection.'
$legacyIdentityCell = [pscustomobject]@{ placementSeed = 773; tilePlacements = @() }
Assert ((Get-CellRecipeLayoutIdentity $legacyIdentityCell 1337) -ceq (Get-CellRecipeLayoutIdentity $legacyIdentityCell 1338)) 'Legacy recipe identity remains unchanged across map seeds.'

function New-RecipeContentCell {
    param([int]$X, [object]$RampExits = @('N'), [object]$WaterBorderSides = @())
    return [pscustomobject]@{
        x = $X; y = 0; cellTemplateFilename = 'zz_preview_shared.vmf'; cellVariant = 0
        environmentProfile = 'commercial'; landmarks = @(); orientation = 'ns'; placementSeed = 773
        rampExits = $RampExits; topology = 'straight'; transportFeature = 'none'; waterBorderSides = $WaterBorderSides
        tilePlacements = @([pscustomobject]@{ tileX = 0; tileY = 0; template = 'roads/tile_road.vmf'; rotationYaw = 0 })
        sceneryDensityPolicyVersion = 1; sceneryDensityTier = 3; sceneryDensitySource = 'district:commercial'
    }
}
Assert-RecipeFilenameContentUnique @((New-RecipeContentCell 0), (New-RecipeContentCell 7))
Assert ($true) 'Identical builder inputs may share a recipe filename across cell coordinates.'
Assert-Rejected { Assert-RecipeFilenameContentUnique @((New-RecipeContentCell 0), (New-RecipeContentCell 7 -RampExits @('S'))) } '*different builder inputs*'
Assert-Rejected { Assert-RecipeFilenameContentUnique @((New-RecipeContentCell 0), (New-RecipeContentCell 7 -WaterBorderSides @('E'))) } '*different builder inputs*'
$tierCell = New-RecipeContentCell 7; $tierCell.sceneryDensityTier = 2
Assert-Rejected { Assert-RecipeFilenameContentUnique @((New-RecipeContentCell 0), $tierCell) } '*different builder inputs*'
$placementCell = New-RecipeContentCell 7; $placementCell.tilePlacements[0].rotationYaw = 90
Assert-Rejected { Assert-RecipeFilenameContentUnique @((New-RecipeContentCell 0), $placementCell) } '*different builder inputs*'
$nearCell = New-RecipeContentCell 0; $farCell = New-RecipeContentCell 7
$nearCell.tilePlacements[0] | Add-Member -NotePropertyName sceneryDensitySelection -NotePropertyValue ([pscustomobject]@{ source = 'district:commercial'; inlandDistance = 4; status = 'selected'; excludedCount = 11; excludedTags = @(1, 2); exclusionReason = 'tagged_template_not_target_or_neutral' })
$farCell.tilePlacements[0] | Add-Member -NotePropertyName sceneryDensitySelection -NotePropertyValue ([pscustomobject]@{ source = 'district:commercial'; inlandDistance = 9; status = 'selected'; excludedCount = 0; excludedTags = @(); exclusionReason = $null })
Assert-RecipeFilenameContentUnique @($nearCell, $farCell)
Assert ($nearCell.tilePlacements[0].sceneryDensitySelection.inlandDistance -eq 4) 'Absolute inland distance alone does not split an otherwise identical recipe, and the cell metadata is not mutated.'
Assert ($nearCell.tilePlacements[0].sceneryDensitySelection.excludedCount -eq 11) 'Candidate-pool exclusion diagnostics do not split an identical resolved selection and are not mutated.'
$farCell.tilePlacements[0].sceneryDensitySelection.status = 'fallback'
Assert-Rejected { Assert-RecipeFilenameContentUnique @($nearCell, $farCell) } '*differing fields: tilePlacements*.sceneryDensitySelection.status=*'
$Seed = 1337
$originKey = '0,0'
$originCellY = 0
$radiationFalloutRadiusCells = 1
$reachableRoadCells = @{ '2,1' = $true; '3,1' = $true; '4,1' = $true; '5,1' = $true }
$highwayCells = @{ '4,1' = $true }
$diagonalHighwayCells = @{}
$radiationSources = @([ordered]@{ name = 'Fixed Test Epicenter'; x = 4; y = 1; worldX = 4; worldY = 1; loreYieldMegatons = 1 })
Assert-Rejected { Move-RadiationSourcesToReachableRoadCells } '*Fixed radiation source*conflicts with a motorway*explicit decision*'
Assert ($radiationSources[0].x -eq 4 -and $radiationSources[0].y -eq 1) 'A fixed radiation-source conflict fails without mutating its location.'

$radiationSources = @([ordered]@{ name = 'Test Epicenter'; x = 8; y = 8; worldX = 8; worldY = 8; loreYieldMegatons = 1 })
$radiationSourcePlacementDiagnostics = @(Move-RadiationSourcesToReachableRoadCells)
$selectedSourceDestination = "$($radiationSources[0].x),$($radiationSources[0].y)"
Assert ($selectedSourceDestination -eq '5,1') 'Radiation-source road placement deterministically excludes motorway cells.'
Assert ($radiationSourcePlacementDiagnostics.Count -eq 1 -and $radiationSourcePlacementDiagnostics[0].sourceIndex -eq 0 -and $radiationSourcePlacementDiagnostics[0].identity -ceq 'Test Epicenter') 'Source relocation diagnostics preserve the source identity.'
Assert ($radiationSourcePlacementDiagnostics[0].original.x -eq 8 -and $radiationSourcePlacementDiagnostics[0].original.y -eq 8 -and $radiationSourcePlacementDiagnostics[0].destination.x -eq 5 -and $radiationSourcePlacementDiagnostics[0].destination.y -eq 1 -and $radiationSourcePlacementDiagnostics[0].reason -ceq 'reachable_ordinary_road' -and $radiationSourcePlacementDiagnostics[0].moved) 'Relocation diagnostics record exact old/new cells and reason.'

$relocationFixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("zombiesim-landmark-relocation-" + [guid]::NewGuid().ToString('N'))
$relocationTemplateDirectory = Join-Path $relocationFixtureRoot 'tiletemplates'
New-Item -ItemType Directory -Path (Join-Path $relocationTemplateDirectory 'buildings') -Force | Out-Null
foreach ($templateName in @('tile_hospital_1a.vmf')) {
    New-Item -ItemType File -Path (Join-Path (Join-Path $relocationTemplateDirectory 'buildings') $templateName) -Force | Out-Null
}
function Get-RadiationIntensity { param([int]$CellX, [int]$CellY) return 0.0 }
function Initialize-LandmarkRelocationFixture {
    param([string[]]$CandidateKeys)
    $script:GridCells = 12
    $script:projectRoot = $relocationFixtureRoot
    $script:generatorSettings = @{
        paths = @{ templateDirectory = 'tiletemplates' }
        cellPlanning = @{
            environment = @{ profilePriority = @('destroyed', 'radioactive', 'safe_zone', 'commercial', 'financial') }
            landmarkTemplatePatterns = @{ Hospital = '*/tile_hospital*.vmf' }
        }
    }
    $script:maximumLandmarksPerCell = 4
    $script:airportMinimumSeparationCells = 48
    $script:landmarkCells = @{}
    $script:eligibleLandmarkCandidates = @($CandidateKeys)
    $script:roadCells = @{}
    $script:reachableRoadCells = @{}
    foreach ($candidateKey in $CandidateKeys) {
        $script:roadCells[$candidateKey] = @{}
        $script:reachableRoadCells[$candidateKey] = $true
    }
    $script:highwayCells = @{}
    $script:diagonalHighwayCells = @{}
    $script:terrainTypes = @{}
    $script:buildingCells = @{}
    $script:denCells = @{ '0,0' = @{ Name = 'Origin'; District = -1; Difficult = $false }; '11,11' = @{ Name = 'Far Den'; District = 0; Difficult = $false } }
    $script:metroStations = @{}
    $script:metroLines = @()
    $script:radiationDestroyedThreshold = 0.7
    for ($fixtureY = 0; $fixtureY -lt $GridCells; $fixtureY++) {
        for ($fixtureX = 0; $fixtureX -lt $GridCells; $fixtureX++) {
            $script:terrainTypes["$fixtureX,$fixtureY"] = 'grassland'
        }
    }
}
try {
    Initialize-LandmarkRelocationFixture @('8,2', '2,2', '1,2')
    $relocationHospital = @{ Label = 'H'; Name = 'Hospital'; Color = 'red' }
    $sourceMarker = @{ Label = 'X'; Name = 'Source marker'; Color = 'blue' }
    $landmarkCells['8,2'] = @($relocationHospital, $sourceMarker)
    $landmarkCells['2,2'] = @(
        @{ Label = 'X'; Name = 'Full 1' },
        @{ Label = 'X'; Name = 'Full 2' },
        @{ Label = 'X'; Name = 'Full 3' },
        @{ Label = 'X'; Name = 'Full 4' }
    )
    $landmarkCells['1,2'] = @(@{ Label = 'X'; Name = 'Existing destination marker' })
    $safeZoneSnapshot = ($denCells | ConvertTo-Json -Depth 4 -Compress)
    $fixtureTemplates = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tiletemplates') -Filter '*.vmf' -File -Recurse | ForEach-Object { $_.FullName.Substring((Join-Path $projectRoot 'tiletemplates').Length).TrimStart([char]'\').Replace('\', '/') })
    $fixturePool = Get-ZMLandmarkTemplatePool @('Hospital') $generatorSettings.cellPlanning.landmarkTemplatePatterns $fixtureTemplates
    Assert ($null -ne $fixturePool -and $fixturePool.templates.Count -eq 1) "Relocation fixture discovers its configured templates: $($fixtureTemplates -join ',')."
    Assert (-not (Test-LandmarkTemplateSupportsDensityZone $fixturePool 3)) 'Low-only fixture pool conflicts with the high-density source zone.'
    $fixtureDistance = @{ '8,2' = 8 }
    Assert ((Get-GeneratorSceneryDensityZone '8,2' $fixtureDistance).tier -eq 3) 'Fixture source is in the intended high-density zone.'
    $landmarkCellsSnapshot = ($landmarkCells | ConvertTo-Json -Depth 4 -Compress)
    $landmarkDensityShortageDiagnostics = @(Get-LandmarkDensityShortages)
    Assert ($landmarkDensityShortageDiagnostics.Count -eq 1 -and $landmarkDensityShortageDiagnostics[0].identity -ceq 'Hospital') "Generator reports the density-incompatible landmark exactly once: $($landmarkDensityShortageDiagnostics | ConvertTo-Json -Depth 6 -Compress)"
    Assert (($landmarkCells | ConvertTo-Json -Depth 4 -Compress) -ceq $landmarkCellsSnapshot -and @($landmarkCells['8,2'] | Where-Object { [object]::ReferenceEquals($_, $relocationHospital) }).Count -eq 1) 'Density-exempt landmarks stay where generated with their original object.'
    $shortage = $landmarkDensityShortageDiagnostics[0]
    Assert ($shortage.cell.x -eq 8 -and $shortage.cell.y -eq 2 -and $shortage.zoneTier -eq 3 -and -not $shortage.moved -and $shortage.reason -ceq 'density_exempt_fixed_landmark') 'Shortage diagnostics identify the cell, zone and exemption reason.'
    Assert ((@($shortage.requiredTargetTiers) -join ',') -ceq '2,3' -and (@($shortage.availableTemplateTags) -join ',') -ceq '1') 'Shortage diagnostics record required targets against available template tags.'
    Assert (($denCells | ConvertTo-Json -Depth 4 -Compress) -ceq $safeZoneSnapshot) 'Shortage reporting leaves safe-zone identities untouched.'
    $landmarkCells['8,2'] = @(@{ Label = 'H'; Name = 'Hospital'; Color = 'red' })
    $landmarkCells['1,2'] = @(@{ Label = 'H'; Name = 'Hospital'; Color = 'red' })
    $compatibleOnly = @(Get-LandmarkDensityShortages | Where-Object { $_.cell.x -eq 1 })
    Assert ($compatibleOnly.Count -eq 0) 'Landmarks whose pool covers the zone produce no shortage.'
}
finally {
    if (Test-Path -LiteralPath $relocationFixtureRoot) { Remove-Item -LiteralPath $relocationFixtureRoot -Recurse -Force }
}

$cornerPool = @(
    'border/tile_border_wall_corner_1aa.vmf',
    'border/tile_border_wall_corner_1a.vmf'
)
$cornerFallbacks = @{ '3' = 'border/tile_border_wall_corner_1aa.vmf' }
$cornerSettings = @{ cornerVariationTemplates = $cornerPool; cornerDensityFallbacks = $cornerFallbacks }
$templateRoot = Join-Path $root $profileSettings.Settings.paths.templateDirectory
Assert-BorderCornerVariationSettings -Settings $cornerSettings -SettingPath 'fixture.border' -TileDirectory $templateRoot
Assert-Rejected { Assert-BorderCornerVariationSettings -Settings @{ cornerVariationTemplates = $cornerPool } -SettingPath 'fixture.border' -TileDirectory $templateRoot } '*no compatible or explicit fallback source for target tier 3*'
Assert-Rejected { Assert-BorderCornerVariationSettings -Settings @{ cornerVariationTemplates = $cornerPool; cornerDensityFallbacks = @{ '3' = 'border/tile_border_wall_corner_1aaa.vmf' } } -SettingPath 'fixture.border' -TileDirectory $templateRoot } '*must reference a member of cornerVariationTemplates*'
$newCornerDensityCell = {
    param([int]$Tier, [int]$Distance, [string]$Source)
    [pscustomobject]@{
        x = 4; y = 9
        environmentProfile = 'grassland'
        topology = 'road-straight'
        orientation = 'vertical'
        landmarks = @()
        cellVariant = 2
        sceneryDensityPolicyVersion = 1
        sceneryDensityTier = $Tier
        sceneryDensitySource = $Source
        sceneryInlandDistance = $Distance
        buildingDensityTier = $Tier
    }
}
$lowCorner = Get-BorderCornerTemplate -Recipe (& $newCornerDensityCell 1 0 'protected_coast') -CornerPosition 'N-W' -CornerTemplates $cornerPool -CornerDensityFallbacks $cornerFallbacks -LegacyTemplate 'border/tile_border_wall_corner_1a.vmf' -MapSeed 1337 -UseDensitySelection $true
$mediumCorner = Get-BorderCornerTemplate -Recipe (& $newCornerDensityCell 2 3 'inland_band') -CornerPosition 'N-W' -CornerTemplates $cornerPool -CornerDensityFallbacks $cornerFallbacks -LegacyTemplate 'border/tile_border_wall_corner_1a.vmf' -MapSeed 1337 -UseDensitySelection $true
$highCorner = Get-BorderCornerTemplate -Recipe (& $newCornerDensityCell 3 8 'inland_band') -CornerPosition 'N-W' -CornerTemplates $cornerPool -CornerDensityFallbacks $cornerFallbacks -LegacyTemplate 'border/tile_border_wall_corner_1a.vmf' -MapSeed 1337 -UseDensitySelection $true
Assert ($lowCorner.template -ceq 'border/tile_border_wall_corner_1a.vmf' -and $lowCorner.selection.status -eq 'selected') 'Policy-v1 low-zone border corners select the low tagged source.'
Assert ($mediumCorner.template -ceq 'border/tile_border_wall_corner_1aa.vmf' -and $mediumCorner.selection.status -eq 'selected') 'Policy-v1 medium-zone border corners select the medium tagged source.'
Assert ($highCorner.template -ceq 'border/tile_border_wall_corner_1aa.vmf' -and $highCorner.selection.status -eq 'selected_explicit_exception' -and $highCorner.selection.densityException -eq 'target_tier_3_fallback') 'High-target border corners use and record the explicitly configured medium-tier exception.'
$highCornerRepeat = Get-BorderCornerTemplate -Recipe (& $newCornerDensityCell 3 8 'inland_band') -CornerPosition 'N-W' -CornerTemplates @($cornerPool[1], $cornerPool[0]) -CornerDensityFallbacks $cornerFallbacks -LegacyTemplate 'border/tile_border_wall_corner_1a.vmf' -MapSeed 1337 -UseDensitySelection $true
Assert ($highCorner.template -ceq $highCornerRepeat.template -and $highCorner.selection.targetTier -eq $highCornerRepeat.selection.targetTier) 'Policy-v1 corner choice is deterministic and enumeration-order independent.'
$legacyCornerCell = [pscustomobject]@{ x = 4; y = 9; cellVariant = 0 }
$legacyCorner = Get-BorderCornerTemplate -Recipe $legacyCornerCell -CornerPosition 'N-W' -CornerTemplates $cornerPool -CornerDensityFallbacks $cornerFallbacks -LegacyTemplate 'border/tile_border_wall_corner_1a.vmf' -MapSeed 1337 -UseDensitySelection $true
Assert ($legacyCorner.template -ceq 'border/tile_border_wall_corner_1a.vmf' -and $null -eq $legacyCorner.selection) 'Legacy plans retain the configured single-corner source.'
$profileCorner = Get-BorderCornerTemplate -Recipe (& $newCornerDensityCell 3 8 'inland_band') -CornerPosition 'N-W' -CornerTemplates @('border/tile_border_army_wall_corner.vmf') -CornerDensityFallbacks @{} -LegacyTemplate 'border/tile_border_army_wall_corner.vmf' -MapSeed 1337 -UseDensitySelection $false
Assert ($profileCorner.template -ceq 'border/tile_border_army_wall_corner.vmf' -and $null -eq $profileCorner.selection) 'Profile-specific single neutral corners remain unchanged.'

# Execute the real manifest serializer without drawing or generating a transport world.
& {
    $generatorSettings = $profileSettings.Settings
    $GridCells = 12
    $Seed = 1337
    $CellSize = 64
    $width = $GridCells * $CellSize
    $height = $width
    $cityName = 'Density Fixture'
    $originCellY = 6
    $zones = @()
    $denCells = @{}
    $roadCells = @{}
    $highwayCells = @{}
    $buildingCells = @{}
    $landmarkCells = @{}
    $metroStations = @{}
    $metroLines = @()
    $airportKeys = @()
    $safeZonePlacementDiagnostics = @()
    $landmarkDensityShortageDiagnostics = @()
    $radiationSources = @()
    $radiationSourcePlacementDiagnostics = @()
    $radiationEnabled = $false
    $dangerEnabled = $false
    $RoadDepth = 7
    $BranchChance = 0.38
    $BlockadeChance = 0.28
    $BridgeChance = 0.04
    $biomeOpacity = 45
    $safeZoneMinimumSpacingCells = 0
    $radiationFalloutRadiusCells = 9
    $radiationDestroyedThreshold = 0.7
    $radiationDamagePerSecondAtPeak = 8
    $radiationCellMiles = 4
    $radiationLoreYieldMegatons = 1
    $dangerTierCount = 6
    $population = 0
    function Get-MapCellData {
        param([int]$CellX, [int]$CellY)
        $tags = switch ($CellY) {
            1 { @('grassland', 'commercial') }
            2 { @('grassland', 'commercial', 'financial') }
            4 { @('grassland', 'commercial', 'destroyed') }
            default { @('grassland') }
        }
        return [ordered]@{
            x = $CellX; y = $CellY; worldX = $CellX; worldY = $CellY - 6
            environment = [ordered]@{ terrain = 'grassland'; tags = @($tags) }
            building = [ordered]@{ present = $CellY -eq 3 }
            danger = [ordered]@{ intensity = 0.5 }
            radiation = [ordered]@{ intensity = 0.25 }
        }
    }
    $Output = Join-Path ([System.IO.Path]::GetTempPath()) ("zombiesim-density-" + [guid]::NewGuid().ToString('N') + '.png')
    $jsonPath = [System.IO.Path]::ChangeExtension($Output, '.json')
    try {
        $written = Export-MapData
        Assert ($written -eq $jsonPath -and (Test-Path -LiteralPath $written)) 'Real exporter writes the exact isolated fixture manifest.'
        $fixture = Get-Content -Raw -LiteralPath $written | ConvertFrom-Json
        $firstHash = (Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash
        Export-MapData | Out-Null
        Assert ((Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash -ceq $firstHash) 'Repeated actual serialization is byte-identical.'
        Assert ($fixture.map.environment.sceneryDensityPolicyVersion -eq 1 -and $fixture.cells.Count -eq 144) 'Serialized header declares the density policy and retains grid cells.'
        Assert ($fixture.generation.landmarkDensityShortages.Count -eq 0) 'Map serialization emits an explicit empty landmark density-shortage list.'
        Assert (Test-ZMSceneryDensityManifest $fixture) 'The real exported manifest passes the shared header/cell policy guard.'
        foreach ($cell in $fixture.cells) {
            $stored = Get-ZMStoredSceneryDensity $cell
            $expectedProfile = Get-EnvironmentProfile $cell
            $expectedZone = Get-ZMSceneryDensityZone $cell.x $expectedProfile
            Assert ($stored.sceneryDensityTier -eq $expectedZone.tier -and $stored.sceneryDensitySource -ceq $expectedZone.source -and $stored.sceneryInlandDistance -eq $cell.x) 'Stored export tier/source/distance matches the approved fixture.'
            Assert ((Get-BuildingDensityTier $cell $expectedProfile) -eq $stored.sceneryDensityTier) 'Production planner consumes the stored tier.'
            Assert ((Get-BuildingDensityTier $cell 'financial') -eq $stored.sceneryDensityTier) 'Consumers cannot reinterpret stored density using a different profile.'
            Assert ($cell.buildingDensityTier -eq $cell.sceneryDensityTier) 'Legacy building field is exactly the authoritative alias.'
            $planCell = ($cell | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
            $fields = Get-RuntimeSceneryDensityFields $cell $planCell
            Assert ($fields.Count -eq 5 -and $fields.sceneryDensitySource -ceq $cell.sceneryDensitySource) 'Runtime export retains identical density metadata.'
            foreach ($field in $stored.PSObject.Properties) { $cell.PSObject.Properties.Remove($field.Name) }
            $original = [pscustomobject](Get-MapCellData $cell.x $cell.y)
            Assert (($cell | ConvertTo-Json -Depth 8 -Compress) -ceq ($original | ConvertTo-Json -Depth 8 -Compress)) 'Zoning changes no topology/location/occupancy/danger/radiation fixture data.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $jsonPath) { Remove-Item -LiteralPath $jsonPath }
    }
}

$freshCells = @(foreach ($x in 0..11) {
    [pscustomobject]@{ x = $x; y = 0; environment = [pscustomobject]@{ terrain = 'grassland'; tags = @('commercial') }; building = [pscustomobject]@{ present = $false } }
})
Set-ZMSceneryDensityFields $freshCells @($freshCells[0]) @($plannerSettings.environment.profilePriority)
$fresh = $freshCells[3]
$map = [pscustomobject]@{ map = [pscustomobject]@{ seed = 1337 } }
$densitySelectionPool = @(
    'buildings/tile_building_1a.vmf',
    'buildings/tile_building_1aa.vmf',
    'buildings/tile_building_1aaa.vmf',
    'buildings/tile_building_neutral.vmf'
)
foreach ($tier in 1..3) {
    $selection = Get-SceneryTemplateSelection $densitySelectionPool $fresh 'commercial' 'open' 'none' $tier @('none') 2 '2,3' 'building'
    $repeat = Get-SceneryTemplateSelection $densitySelectionPool $fresh 'commercial' 'open' 'none' $tier @('none') 2 '2,3' 'building'
    Assert ($selection.status -eq 'selected' -and ($selection.actualTag -eq 0 -or $selection.actualTag -eq $selection.targetTier)) "Planner selects only target-tier or neutral building templates at zone $tier."
    Assert ($selection.template -ceq $repeat.template -and $selection.targetTier -eq $repeat.targetTier) "Planner density choice is deterministic at zone $tier."
}
$forbiddenOnly = Get-SceneryTemplateSelection @('buildings/tile_building_6a.vmf') $fresh 'commercial' 'open' 'none' 3 @('none') 2 '2,3' 'building'
Assert ($forbiddenOnly.status -eq 'shortage_keep_terrain' -and $null -eq $forbiddenOnly.template) 'Planner never falls back to an incompatible tier.'
$landmarkPool = @{
    'buildings/tile_hospital_1a_2x.vmf' = 'buildings/tile_hospital_1a_2x.vmf'
    'buildings/tile_hospital_1aa_2x.vmf' = 'buildings/tile_hospital_1aa_2x.vmf'
    'buildings/tile_hospital_1aaa_2x.vmf' = 'buildings/tile_hospital_1aaa_2x.vmf'
    'buildings/tile_hospital_neutral_2x.vmf' = 'buildings/tile_hospital_neutral_2x.vmf'
    'buildings/tile_hospital_1aaa.vmf' = 'buildings/tile_hospital_1aaa.vmf'
}
$landmarkTemplateSelection = Get-LandmarkTemplateSelection @('Hospital') $landmarkPool $fresh 'commercial' 'road-straight' 'vertical' 3 0
Assert ($landmarkTemplateSelection.template -in @('buildings/tile_hospital_1aa_2x.vmf', 'buildings/tile_hospital_1aaa_2x.vmf', 'buildings/tile_hospital_neutral_2x.vmf')) 'Required landmark selection enforces density within its established footprint family.'
Assert ($landmarkTemplateSelection.selection.status -eq 'selected' -and ($landmarkTemplateSelection.selection.actualTag -eq 0 -or $landmarkTemplateSelection.selection.actualTag -eq $landmarkTemplateSelection.selection.targetTier)) 'Required landmark selection uses only a target-tier or neutral template.'
$lowOnlyLandmarkPool = @{ 'buildings/tile_hospital_1a_2x.vmf' = 'buildings/tile_hospital_1a_2x.vmf' }
$exemptLandmark = Get-LandmarkTemplateSelection @('Hospital') $lowOnlyLandmarkPool $fresh 'commercial' 'road-straight' 'vertical' 3 0 3>$null
Assert ($exemptLandmark.template -ceq 'buildings/tile_hospital_1a_2x.vmf' -and $exemptLandmark.selection.status -ceq 'density_exempt_landmark' -and $exemptLandmark.selection.actualTag -eq 1 -and $exemptLandmark.selection.targetTier -ne 1) 'Density-exempt landmarks keep their existing template and record the shortage.'
$sceneryDensityPolicyEnabled = $false
$legacyLandmarkTemplateSelection = Get-LandmarkTemplateSelection @('Hospital') $lowOnlyLandmarkPool $fresh 'commercial' 'road-straight' 'vertical' 3 0
Assert ($legacyLandmarkTemplateSelection.template -ceq 'buildings/tile_hospital_1a_2x.vmf' -and $null -eq $legacyLandmarkTemplateSelection.selection) 'Legacy manifests retain prior special-landmark template selection.'
$sceneryDensityPolicyEnabled = $true
$selectionMetadataPlacement = [pscustomobject]@{ role = 'terrain' }
Set-ScenerySelectionMetadata $selectionMetadataPlacement $forbiddenOnly $fresh 'building'
Assert ($selectionMetadataPlacement.sceneryDensitySelection.status -eq 'shortage_keep_terrain' -and $selectionMetadataPlacement.sceneryDensitySelection.targetTier -eq $forbiddenOnly.targetTier -and $selectionMetadataPlacement.sceneryDensitySelection.actualTag -eq $null) 'Planner records optional density shortages on retained terrain.'

function Get-CellConnections {
    param([object]$Cell)
    $connections = $Cell.PSObject.Properties['fixtureConnections']
    if ($null -eq $connections) { return @() }
    return @($connections.Value)
}
function Get-ForcedMultiTileTemplate {
    param([object]$Cell, [hashtable]$AvailableTemplates)
    $template = $Cell.PSObject.Properties['multiTileTemplate']
    if ($null -eq $template) { return $null }
    return [string]$template.Value
}
function Get-CarparkTemplateSet { param([string[]]$CarparkTemplates) return $null }
function Get-PlacementVariationRoll { param([int]$PlacementSeed) return 100 }
function Get-ClosedCornerFrontageDirection { param([object]$Placement, [object[]]$RoadCenterPlacements, [string[]]$Connections, [string]$Topology) return 'N' }
function Get-TemplateRoadConnectionRotation { param([string]$Template, [string]$Direction) return 0 }
function Resolve-Template {
    param([string[]]$Candidates, [hashtable]$AvailableTemplates)
    foreach ($candidate in $Candidates) {
        $key = $candidate.ToLowerInvariant()
        if ($AvailableTemplates.ContainsKey($key)) { return [string]$AvailableTemplates[$key] }
    }
    return $null
}
function Set-OpenTerrainFill {
    param([hashtable]$Placements, [int]$TileGridSize, [int]$PlacementSeed, [string[]]$DecorationTemplates, [object]$Cell, [string]$Profile, [string]$Topology, [string]$Orientation, [int]$BuildingDensityTier, [string[]]$Landmarks, [int]$CellVariant, [hashtable]$AvailableTemplates)
}
function Set-TopologyVariants { param([hashtable]$Placements, [int]$PlacementSeed, [hashtable]$AvailableTemplates) }
function Set-TilePlacementDefaults { param([object[]]$Placements) }
$sceneryDensityPolicyEnabled = $true
$plannerSettings = $profileSettings.Settings.cellPlanning
$commercialTemplates = @()
$topologyVariantChancePercent = 0
$topologyVariantTemplates = @{}
$templateRoadConnections = @{}
$multiTileEnabled = $false
$maximumOpenTilePercent = 100
$emptyBuildingCell = [pscustomobject]@{
    x = 0; y = 0
    environment = [pscustomobject]@{ terrain = 'grassland'; tags = @() }
    building = [pscustomobject]@{ present = $false }
}
Set-ZMSceneryDensityFields @($emptyBuildingCell) @($emptyBuildingCell) @($plannerSettings.environment.profilePriority)
$plannerSettings.decorations.preferredChancePercent = 100
$plannerSettings.decorations.standardChancePercent = 100
$decorationFixture = 'decorations/tile_fixture_1a.vmf'
$availableSceneryTemplates = @{
    'roads/tile_concrete_path.vmf' = 'roads/tile_concrete_path.vmf'
    'terrain/tile_grass.vmf' = 'terrain/tile_grass.vmf'
    $decorationFixture = $decorationFixture
    'buildings/tile_building_neutral.vmf' = 'buildings/tile_building_neutral.vmf'
    'buildings/tile_landmark_2x.vmf' = 'buildings/tile_landmark_2x.vmf'
}
$decorationsWithoutBuildings = @(Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @($decorationFixture) 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null)
$placedDecorations = @($decorationsWithoutBuildings | Where-Object { $_.role -eq 'decoration' })
Assert ($placedDecorations.Count -gt 0 -and @($decorationsWithoutBuildings | Where-Object { $_.role -eq 'building' }).Count -eq 0) 'Decoration-only motorway fixture places decorations without any building candidates.'
Assert (@($placedDecorations | Where-Object { $_.sceneryDensitySelection.actualTag -ne 0 -and $_.sceneryDensitySelection.actualTag -ne $_.sceneryDensitySelection.targetTier }).Count -eq 0) 'Decoration-only fixture respects hard density exclusions.'

Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force
$generatorSettings = $profileSettings.Settings
$plannerTokens = $null
$plannerErrors = $null
$plannerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'plan_cell_templates.ps1'), [ref]$plannerTokens, [ref]$plannerErrors)
foreach ($name in @('Get-LinearTopologyTemplate', 'Get-GenericTopologyTemplate', 'Get-TransportFeatureTemplate', 'Get-LayoutRotation', 'Get-DirectionalTileCoordinates', 'Get-DirectionalTileRotation', 'Set-TilePlacementDefaults', 'Resolve-Template')) {
    $definition = @($plannerAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false))
    Assert ($definition.Count -eq 1) "Normal motorway fixture uses production $name."
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$straightTemplate = [string]$plannerSettings.topologyTemplates['motorway-straight']
$availableSceneryTemplates[$straightTemplate.ToLowerInvariant()] = $straightTemplate
foreach ($orientation in @('vertical', 'horizontal')) {
    $normalCell = $emptyBuildingCell.PSObject.Copy()
    $normalCell | Add-Member -NotePropertyName fixtureConnections -NotePropertyValue $(if ($orientation -eq 'vertical') { @('N', 'S') } else { @('E', 'W') })
    $before = $normalCell | ConvertTo-Json -Depth 20
    $normalPlacements = @(Get-CellTilePlacements $normalCell 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @($decorationFixture) 0 1 1 'none' 'motorway-straight' $orientation 5 $availableSceneryTemplates $false $null)
    Assert ($normalPlacements.Count -eq 25) 'Normal wide straight planning retains every core slot exactly once.'
    Assert (@($normalPlacements | Where-Object role -eq motorway_assembly).Count -eq 5 -and
        @($normalPlacements | Where-Object role -eq motorway_occupied).Count -eq 10) 'Normal straight reserves15 slots through five emitting owners and ten suppressed slots.'
    Assert (@($normalPlacements | Where-Object role -in @('road', 'road_center')).Count -eq 0) 'No old centreline route record survives the wide reservation.'
    foreach ($along in 0..4) {
        $stripe = New-ZMStraightMotorwayStripe $orientation $along $straightTemplate
        $actual = @($normalPlacements | Where-Object placementId -eq $stripe.owner.placementId)
        Assert ($actual.Count -eq 3 -and @($actual | Where-Object emitsInstance).Count -eq 1) 'Each normal stripe owns exactly three slots and one instance.'
        foreach ($expected in $stripe.placements) {
            $record = @($actual | Where-Object { $_.tileX -eq $expected.tileX -and $_.tileY -eq $expected.tileY })
            Assert ($record.Count -eq 1 -and $record[0].role -ceq $expected.role -and $record[0].rotationYaw -eq $expected.rotationYaw) 'Density decoration never replaces an occupied motorway slot.'
            Assert ($record[0].footprintWidth -eq $stripe.owner.footprintWidth -and $record[0].footprintHeight -eq $stripe.owner.footprintHeight) 'Planner defaults preserve owner geometry on suppressed records instead of assigning1x1.'
        }
        $owner = @($actual | Where-Object emitsInstance)[0]
        Assert (($owner.originCellLocal | ConvertTo-Json -Compress) -ceq ($stripe.owner.originCellLocal | ConvertTo-Json -Compress)) 'Normal planning retains the same approved physical origin as inspection.'
    }
    $normalDecorations = @($normalPlacements | Where-Object role -eq decoration)
    Assert ($normalDecorations.Count -gt 0 -and @($normalDecorations | Where-Object {
        $(if ($orientation -eq 'vertical') { $_.tileX } else { $_.tileY }) -in @(1, 2, 3)
    }).Count -eq 0) 'Density-selected decorations remain available only outside the three-wide corridor.'
    Assert (($normalCell | ConvertTo-Json -Depth 20) -ceq $before) 'Normal planning does not alter the manifest cell.'
    $repeat = @(Get-CellTilePlacements $normalCell 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @($decorationFixture) 0 1 1 'none' 'motorway-straight' $orientation 5 $availableSceneryTemplates $false $null)
    Assert (($repeat | ConvertTo-Json -Depth 20 -Compress) -ceq ($normalPlacements | ConvertTo-Json -Depth 20 -Compress)) 'Normal wide reservations and density choices are deterministic.'
}
foreach ($case in @(
    @{ orientation = 'vertical'; grid = 5; connections = @('E', 'W'); message = 'Normal wide straight motorway connections disagree*' },
    @{ orientation = 'vertical'; grid = 7; connections = @('N', 'S'); message = 'Normal wide straight motorways require the approved 5x5*' }
)) {
    $invalid = $emptyBuildingCell.PSObject.Copy()
    $invalid | Add-Member -NotePropertyName fixtureConnections -NotePropertyValue $case.connections
    $before = $invalid | ConvertTo-Json -Depth 20
    $rejected = $false
    try {
        Get-CellTilePlacements $invalid 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' $case.orientation $case.grid $availableSceneryTemplates $false $null | Out-Null
    } catch {
        if ($_.Exception.Message -notlike $case.message) { throw }
        $rejected = $true
    }
    Assert $rejected 'Unsupported normal straight contracts fail instead of retaining the old centreline.'
    Assert (($invalid | ConvertTo-Json -Depth 20) -ceq $before) 'Rejected normal planning leaves the source manifest unchanged.'
}

$buildingDensitySettings = $plannerSettings.environment.buildingDensity.fallbackByTerrain
$previousGrasslandDensity = $buildingDensitySettings.grassland
try {
    $buildingDensitySettings.grassland = 1.0
    $motorwayBuildings = @(Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @('buildings/tile_building_neutral.vmf') '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null)
    Assert (@($motorwayBuildings | Where-Object { $_.role -eq 'building' }).Count -eq 0) 'Motorway transport reservation prevents otherwise-certain ordinary building selection.'
    $ordinaryRoadBuildings = @(Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @('buildings/tile_building_neutral.vmf') '' @('none') 'grassland' @() @() 0 1 1 'none' 'road-straight' 'north' 5 $availableSceneryTemplates $false $null)
    Assert (@($ordinaryRoadBuildings | Where-Object { $_.role -eq 'building' }).Count -gt 0) 'The motorway guard leaves ordinary-road building selection unchanged.'
}
finally {
    $buildingDensitySettings.grassland = $previousGrasslandDensity
}

Assert-Rejected {
    Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @() 'buildings/tile_landmark_2x.vmf' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null
} '*Motorway cell*physical landmark template*'
Assert-Rejected {
    Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @() '' @('power_station') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null
} '*Motorway cell*fixed physical landmark*'
Assert-Rejected {
    Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $true $null
} '*Motorway cell*forced carpark*'
$motorwayWithSettlement = $emptyBuildingCell | Select-Object *
$motorwayWithSettlement.building = [pscustomobject]@{ present = $true }
Assert-Rejected {
    Get-CellTilePlacements $motorwayWithSettlement 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null
} '*Motorway cell*settlement occupancy*'
$motorwayWithForcedLandmark = $emptyBuildingCell | Select-Object *
$motorwayWithForcedLandmark | Add-Member -NotePropertyName multiTileTemplate -NotePropertyValue 'buildings/tile_landmark_2x.vmf'
Assert-Rejected {
    Get-CellTilePlacements $motorwayWithForcedLandmark 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null
} '*Motorway cell*physical landmark template*'
$safeZoneEntranceFixture = [pscustomobject]@{ interiorTiles = @(); template = 'safezones/tile_safezone_entrance.vmf'; yaw = 0 }
Assert-Rejected {
    Get-CellTilePlacements $emptyBuildingCell 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $safeZoneEntranceFixture
} '*Motorway cell*safe-zone entrance*'
$motorwayWithSafeZone = $emptyBuildingCell | Select-Object *
$motorwayWithSafeZone | Add-Member -NotePropertyName safeZone -NotePropertyValue ([pscustomobject]@{ name = 'Fixture Den' })
Assert-Rejected {
    Get-CellTilePlacements $motorwayWithSafeZone 'terrain/tile_grass.vmf' @() '' @('none') 'grassland' @() @() 0 1 1 'none' 'motorway-straight' 'north' 5 $availableSceneryTemplates $false $null
} '*Motorway cell*safe-zone entrance*'

$legacy = [pscustomobject]@{ x = 3; y = 0; environment = [pscustomobject]@{ terrain = 'grassland'; tags = @('low_density', 'commercial') }; building = [pscustomobject]@{ present = $false } }
Assert ($null -eq (Get-ZMStoredSceneryDensity $legacy) -and (Get-BuildingDensityTier $legacy 'commercial') -eq 1) 'Legacy tag-based density remains unchanged until regeneration.'
Assert ((Get-RuntimeSceneryDensityFields $legacy $legacy).Count -eq 0) 'Legacy runtime export does not fabricate new policy metadata.'
$legacyManifest = [pscustomobject]@{ map = [pscustomobject]@{ seed = 1337 }; cells = @($legacy) }
Assert (-not (Test-ZMSceneryDensityManifest $legacyManifest)) 'Legacy fixture without environment metadata remains explicitly compatible.'
$freshManifest = [pscustomobject]@{ map = [pscustomobject]@{ environment = [pscustomobject]@{ sceneryDensityPolicyVersion = 1 } }; cells = $freshCells }
Assert (Test-ZMSceneryDensityManifest $freshManifest) 'New manifest validates its policy header and every cell.'
$missingManifest = [pscustomobject]@{ map = $freshManifest.map; cells = @($fresh, $legacy) }
Assert-Rejected { Test-ZMSceneryDensityManifest $missingManifest } 'Manifest scenery density missing*'
$undeclaredManifest = [pscustomobject]@{ map = $legacyManifest.map; cells = @($fresh) }
Assert-Rejected { Test-ZMSceneryDensityManifest $undeclaredManifest } 'Stored scenery density requires a manifest policy header*'
$futureManifest = [pscustomobject]@{ map = [pscustomobject]@{ environment = [pscustomobject]@{ sceneryDensityPolicyVersion = 2 } }; cells = $freshCells }
Assert-Rejected { Test-ZMSceneryDensityManifest $futureManifest } 'Unsupported manifest scenery density policy*'
Assert-Rejected { Get-RuntimeSceneryDensityFields $fresh $legacy } 'Runtime scenery density requires matching manifest and plan*'
Assert-Rejected { Get-RuntimeSceneryDensityFields $fresh $freshCells[8] } 'Runtime scenery density mismatch*'
foreach ($case in @(
    @('sceneryDensityPolicyVersion', 2, 'Unsupported scenery density policy*'),
    @('sceneryDensityTier', 4, 'Invalid stored scenery density tier*'),
    @('sceneryDensityTier', '3', 'Invalid stored scenery density tier*'),
    @('sceneryDensitySource', 'invented', 'Invalid stored scenery density source*'),
    @('sceneryInlandDistance', -1, 'Invalid stored scenery inland distance*'),
    @('sceneryInlandDistance', 0, 'Inconsistent stored scenery density policy*'),
    @('buildingDensityTier', 2, 'Scenery/building density alias mismatch*')
)) {
    $bad = $fresh | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $bad.($case[0]) = $case[1]
    Assert-Rejected { Get-BuildingDensityTier $bad 'commercial' } $case[2]
}
$partial = $fresh | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$partial.PSObject.Properties.Remove('sceneryDensitySource')
Assert-Rejected { Get-BuildingDensityTier $partial 'commercial' } 'Incomplete stored scenery density*'
$seedFromStored = Get-RecipePlacementSeed 'commercial' 'open' 'none' (Get-BuildingDensityTier $fresh 'commercial') @()
$seedFromAlias = Get-RecipePlacementSeed 'commercial' 'open' 'none' $fresh.buildingDensityTier @()
Assert ($seedFromStored -eq $seedFromAlias) 'Recipe/variant seeds see the same density as the legacy alias.'

$authored = @(foreach ($family in @('buildings', 'decorations', 'border', 'edges')) {
    Get-ChildItem -LiteralPath (Join-Path $root "tiletemplates\$family") -Filter '*.vmf' -File
})
foreach ($file in $authored) {
    $tag = Get-ZMTemplateDensityTag $file.FullName
    Assert ($tag -in 0..3) "Current authored template classifies: $($file.Name)."
}
Write-Host 'Coast fixture (west ocean; columns x=0..11):'
foreach ($profile in @('grassland', 'commercial', 'settlement')) {
    $row = (0..11 | ForEach-Object { (Get-ZMSceneryDensityZone $_ $profile).tier }) -join ' '
    Write-Host "$profile : $row"
}
Write-Host "Scenery density: $passed assertions passed; $($authored.Count) authored templates classified. No world outputs changed."
