Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'scenery_density.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'tile_ground_grid.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force
$passed = 0
$maximumMultiTileFootprint = 3
$MotorwayCellInspection = $false

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Rectangular footprints: $Message" }
    $script:passed++
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    $rejected = $false
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $rejected = $true
    }
    Assert $rejected "Expected rejection matching '$Pattern'."
}

foreach ($source in @(
    @{ file = 'plan_cell_templates.ps1'; functions = @('Get-FootprintCoordinates', 'Get-RotatedFootprint', 'Get-FootprintAnchorCandidates', 'Set-FootprintPlacement', 'Set-TilePlacementDefaults', 'Get-TemplateRoadConnection', 'Get-ForcedMultiTileTemplate', 'Get-BuildingHeightTier', 'Get-TemplateRoadConnectionRotation', 'Get-OppositeDirection', 'Get-RotatedCardinalDirection', 'Get-OffsetTileCoordinate', 'Get-DirectionToCoordinate', 'Test-RoadPlacementFacesCoordinate', 'Get-FootprintRoadFacingCandidates', 'Get-MarkedRoadConnectionCandidates') },
    @{ file = 'build_tile_zoos.ps1'; functions = @('Get-ZooGridPlacements', 'Get-TemplateFootprint') },
    @{ file = 'build_cell_vmfs.ps1'; functions = @('Get-PlacementFootprint', 'Test-PlacementEmitsInstance', 'Get-PlacementId', 'Get-PlacementOwnerCoordinate', 'Get-PlacementCoordinates', 'Test-RecipeTilePlacements', 'Get-RecipeInteriorInstanceCount') }
)) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory $source.file), [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "$($source.file) parses."
    foreach ($name in $source.functions) {
        $definition = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        Assert ($definition.Count -eq 1) "One production definition of $name."
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }
}

function New-Grid {
    $grid = @{}
    for ($y = 0; $y -lt 5; $y++) {
        for ($x = 0; $x -lt 5; $x++) {
            $grid["$x,$y"] = [pscustomobject]@{
                tileX = $x; tileY = $y; template = 'fixture-terrain.vmf'; rotationYaw = 0; role = 'terrain'
            }
        }
    }
    return $grid
}

function New-Recipe {
    param([hashtable]$Grid)
    Set-TilePlacementDefaults @($Grid.Values)
    return [pscustomobject]@{ cellTemplateFilename = 'fixture.vmf'; tilePlacements = @($Grid.Values) }
}

foreach ($size in @(@(1, 1), @(2, 2), @(3, 3), @(1, 2), @(2, 1), @(2, 3), @(3, 2))) {
    foreach ($yaw in @(0, 90, 180, 270)) {
        $width = if ($yaw -in @(90, 270)) { $size[1] } else { $size[0] }
        $height = if ($yaw -in @(90, 270)) { $size[0] } else { $size[1] }
        $grid = New-Grid
        $anchors = @(Get-FootprintAnchorCandidates $grid 5 $width $height @('terrain'))
        Assert ($anchors.Count -eq (6 - $width) * (6 - $height)) 'Every legal rectangular anchor is available.'
        Set-FootprintPlacement $grid 5 1 1 $width $height 'fixture-authored.vmf' $yaw 'building_macro' 'macro' @('terrain')
        $recipe = New-Recipe $grid
        Test-RecipeTilePlacements $recipe 5
        Assert ($true) 'Planner occupancy passes the actual builder validator.'
        $records = @($recipe.tilePlacements | Where-Object placementId -eq macro)
        Assert ($records.Count -eq $width * $height) 'Exact rectangle coverage.'
        Assert (@($records | Where-Object emitsInstance).Count -eq 1) 'One emitting owner.'
        Assert ((Get-RecipeInteriorInstanceCount $recipe) -eq 26 - $width * $height) 'Occupied records never duplicate instances.'
        foreach ($record in $records) {
            Assert ($record.ownerTileX -eq 1 -and $record.ownerTileY -eq 1 -and $record.rotationYaw -eq $yaw) 'Owner anchor and authored yaw are unchanged.'
        }
        $before = ConvertTo-Json -InputObject $grid -Depth 10 -Compress
        Assert-Rejected { Set-FootprintPlacement $grid 5 4 4 1 1 'fixture-authored.vmf' $yaw 'building_macro' 'macro' @('terrain') } '*already has an occupancy owner*'
        Assert ((ConvertTo-Json -InputObject $grid -Depth 10 -Compress) -ceq $before) 'Duplicate owner rejection is atomic.'
    }
}

foreach ($field in @('footprintWidth', 'footprintHeight', 'rotationYaw', 'template', 'ownerTileX', 'placementId', 'emitsInstance')) {
    $grid = New-Grid
    Set-FootprintPlacement $grid 5 1 1 2 3 'fixture-authored.vmf' 90 'building_macro' 'macro' @('terrain')
    $recipe = New-Recipe $grid
    $record = $grid['2,1']
    switch ($field) {
        footprintWidth { $record.footprintWidth = 1 }
        footprintHeight { $record.footprintHeight = 2 }
        rotationYaw { $record.rotationYaw = 0 }
        template { $record.template = 'wrong.vmf' }
        ownerTileX { $record.ownerTileX = 2 }
        placementId { $record.placementId = 'wrong' }
        emitsInstance { $record.emitsInstance = $true }
    }
    Assert-Rejected { Test-RecipeTilePlacements $recipe 5 } '*footprint*'
}

$grid = New-Grid
$recipe = New-Recipe $grid
$grid['4,4'].placementId = $grid['0,0'].placementId
Assert-Rejected { Test-RecipeTilePlacements $recipe 5 } '*duplicate emitting footprint owner*'
$grid = New-Grid
Set-FootprintPlacement $grid 5 1 1 3 1 'fixture-authored.vmf' 0 'building_macro' 'macro' @('terrain')
$recipe = New-Recipe $grid
foreach ($record in @($recipe.tilePlacements | Where-Object { $_.placementId -eq 'macro' -and -not $_.emitsInstance })) {
    $record.PSObject.Properties.Remove('footprintWidth')
    $record.PSObject.Properties.Remove('footprintHeight')
}
Test-RecipeTilePlacements $recipe 5
Assert ($true) 'Legacy occupied records without repeated dimensions retain their validated owner geometry.'
$grid = New-Grid
$before = ConvertTo-Json -InputObject $grid -Depth 10 -Compress
Assert-Rejected { Set-FootprintPlacement $grid 5 4 4 2 3 'fixture.vmf' 0 'building_macro' 'macro' @('terrain') } '*cannot reserve tile*'
Assert ((ConvertTo-Json -InputObject $grid -Depth 10 -Compress) -ceq $before) 'Out-of-grid reservation rejection is atomic.'
Assert-Rejected { Get-PlacementFootprint ([pscustomobject]@{ template = 'fixture.vmf'; footprintWidth = 4; footprintHeight = 1 }) } '*1 through 3 tiles per axis*'
Assert-Rejected { Get-PlacementFootprint ([pscustomobject]@{ template = 'fixture.vmf'; footprintWidth = 1; footprintHeight = 0 }) } '*1 through 3 tiles per axis*'

$profile = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$generatorSettings = $profile.Settings
$plannerSettings = $generatorSettings.cellPlanning
$templateRoadConnections = @{}
$fixtureTemplate = 'fixture-frontage.vmf'
$roadTemplate = [string]$plannerSettings.topologyTemplates['road-straight']
$multiTileFixtureTemplateProperty = 'fixtureMultiTileTemplate'
foreach ($case in @(
    @('tile_1aa.vmf', 1, 1), @('tile_1aa_2x.vmf', 2, 2),
    @('tile_1aa_3x.vmf', 3, 3), @('tile_1aa_2x2.vmf', 2, 2),
    @('tile_1aa_3x3.vmf', 3, 3), @('tile_1aa_2x3.vmf', 2, 3),
    @('tile_1aa_3x2.vmf', 3, 2), @('tile_1aa_1x3.vmf', 1, 3),
    @('TILE_1AA_3X1.VMF', 3, 1), @('tile_motorway_crossroads_3x3.vmf', 3, 3)
)) {
    $footprint = Get-ZMTemplateFootprint $case[0]
    Assert ($footprint.width -eq $case[1] -and $footprint.height -eq $case[2]) 'Filename dimensions preserve width then height and legacy square shorthand.'
}
Assert-Rejected { Get-ZMTemplateFootprint 'tile_0x2.vmf' } '*positive footprint dimensions*'
Assert-Rejected { Get-ZMTemplateFootprint 'tile_2x0.vmf' } '*positive footprint dimensions*'
Assert ((Get-BuildingHeightTier 'buildings/tile_1aaa_2x3.vmf') -eq 3) 'Legacy height selection retains rectangle density tag.'
Assert ((Get-ZMTemplateDensityTag 'buildings/tile_1aaa_2x3.vmf') -eq 3) 'Density selection retains rectangle tags independently of footprint.'
$landmarkPool = Get-ZMLandmarkTemplatePool @('Fixture') @{ Fixture = 'buildings/tile_fixture_*.vmf' } @(
    'buildings/tile_fixture_1a_2x3.vmf', 'buildings/tile_fixture_1aa_2x3.vmf', 'buildings/tile_fixture_1aaa_3x2.vmf'
)
Assert ($landmarkPool.footprint.width -eq 2 -and $landmarkPool.footprint.height -eq 3 -and $landmarkPool.templates.Count -eq 2) 'Landmark density variants retain authored rectangle shape rather than interchanging axes.'
$available = @{ 'tile_1aa_2x3.vmf' = 'tile_1aa_2x3.vmf'; 'tile_1aa_6x3.vmf' = 'tile_1aa_6x3.vmf' }
Assert ((Get-ForcedMultiTileTemplate ([pscustomobject]@{ fixtureMultiTileTemplate = 'tile_1aa_2x3.vmf' }) $available) -eq 'tile_1aa_2x3.vmf') 'Ordinary forced rectangle selection uses the shared parser.'
Assert-Rejected { Get-ForcedMultiTileTemplate ([pscustomobject]@{ fixtureMultiTileTemplate = 'tile_1aa_6x3.vmf' }) $available } '*3-tile per-axis limit*'
$TileSize = 640
$zoo = @(Get-ZooGridPlacements @('tile_1x3.vmf', 'tile_1x1.vmf', 'tile_2x1.vmf', 'tile_1x2.vmf'))
Assert ([Math]::Abs($zoo[0].x - $zoo[1].x) -eq 2560 -and [Math]::Abs($zoo[0].y - $zoo[2].y) -eq 2560) 'Zoo spacing uses the largest width OR height.'

$markerDirectory = Join-Path ([IO.Path]::GetTempPath()) ('zm-rectangle-markers-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($markerDirectory) | Out-Null
try {
    foreach ($size in @(@(1, 1), @(2, 2), @(3, 3), @(2, 3), @(3, 2), @(1, 3), @(3, 1))) {
        $path = Join-Path $markerDirectory ("tile_1aa_{0}x{1}.vmf" -f $size[0], $size[1])
        foreach ($direction in @('NORTH', 'EAST', 'SOUTH', 'WEST')) {
            $x = switch ($direction) { EAST { $size[0] * 320 } WEST { -$size[0] * 320 } default { 0 } }
            $y = switch ($direction) { NORTH { $size[1] * 320 } SOUTH { -$size[1] * 320 } default { 0 } }
            $text = "entity`r`n{`r`n`"classname`" `"zn_tile_direction`"`r`n`"direction`" `"$direction`"`r`n`"origin`" `"$x $y 0`"`r`n}`r`n"
            [IO.File]::WriteAllText($path, $text)
            $metadata = Get-TemplateRoadConnection $path
            Assert ($metadata.direction -eq $direction.Substring(0, 1) -and $metadata.directionOriginX -eq $x -and $metadata.directionOriginY -eq $y) 'Inventory reader validates exact authored rectangular edge midpoint.'
            [IO.File]::WriteAllText($path, $text.Replace("$x $y 0", "$($x + 1) $y 0"))
            Assert-Rejected { Get-TemplateRoadConnection $path } '*midpoint*'
        }
    }
}
finally {
    Remove-Item -LiteralPath $markerDirectory -Recurse -Force
}
$cases = @(
    @{ yaw = 0; width = 2; height = 3; front = 'N'; roads = @(@(1, 0), @(2, 0)); roadYaw = 90 },
    @{ yaw = 90; width = 3; height = 2; front = 'W'; roads = @(@(0, 2), @(0, 1)); roadYaw = 0 },
    @{ yaw = 180; width = 2; height = 3; front = 'S'; roads = @(@(2, 4), @(1, 4)); roadYaw = 90 },
    @{ yaw = 270; width = 3; height = 2; front = 'E'; roads = @(@(4, 1), @(4, 2)); roadYaw = 0 }
)
foreach ($case in $cases) {
    foreach ($marked in @($false, $true)) {
        $grid = New-Grid
        foreach ($record in $grid.Values) { $record.role = 'protected' }
        for ($y = 1; $y -le $case.height; $y++) {
            for ($x = 1; $x -le $case.width; $x++) { $grid["$x,$y"].role = 'terrain' }
        }
        foreach ($coordinate in $case.roads) {
            $grid["$($coordinate[0]),$($coordinate[1])"] = [pscustomobject]@{
                tileX = $coordinate[0]; tileY = $coordinate[1]; template = $roadTemplate; rotationYaw = $case.roadYaw; role = 'road'
            }
        }
        $templateRoadConnections[$fixtureTemplate] = [pscustomobject]@{
            direction = 'N'
            markers = @(if ($marked) {
                [pscustomobject]@{ originX = -320.0; originY = 960.0; connectionType = 'driveway' }
                [pscustomobject]@{ originX = 320.0; originY = 960.0; connectionType = 'bus' }
            })
        }
        $before = ConvertTo-Json -InputObject $grid -Depth 10 -Compress
        $candidates = @(Get-MarkedRoadConnectionCandidates $grid 5 2 3 $fixtureTemplate @('terrain') $roadTemplate)
        Assert ($candidates.Count -gt 0) 'Rotated rectangle finds its actual frontage.'
        foreach ($candidate in $candidates) {
            Assert ($candidate.tileX -eq 1 -and $candidate.tileY -eq 1 -and $candidate.rotationYaw -eq $case.yaw) 'Only the available rotated anchor is proposed.'
            Assert ($candidate.footprintWidth -eq $case.width -and $candidate.footprintHeight -eq $case.height -and $candidate.frontageDirection -eq $case.front) 'Candidate dimensions match the authored rotation and cardinal frontage.'
            if ($marked) {
                Assert ($candidate.roadConnections.Count -eq 2) 'Every off-centre authored road marker has a separate target.'
                foreach ($i in 0..1) {
                    $road = $candidate.roadConnections[$i].road
                    Assert ($road.tileX -eq $case.roads[$i][0] -and $road.tileY -eq $case.roads[$i][1]) 'Marker order/type follows its exact rotated target, not the unrotated rectangle.'
                }
            }
        }
        $roadCandidates = @(Get-FootprintRoadFacingCandidates $grid 5 2 3 @($grid.Values | Where-Object role -eq road) @('N', 'E', 'S', 'W') 'road-straight' @('terrain') $fixtureTemplate)
        Assert ($roadCandidates.Count -gt 0) 'Unmarked generic frontage also finds the rotated rectangle.'
        foreach ($candidate in $roadCandidates) {
            Assert ($candidate.tileX -eq 1 -and $candidate.tileY -eq 1 -and $candidate.footprintWidth -eq $case.width -and $candidate.footprintHeight -eq $case.height) 'Generic frontage validates the rotated reservation, not its authored size.'
        }
        Assert ((ConvertTo-Json -InputObject $grid -Depth 10 -Compress) -ceq $before) 'Candidate discovery never mutates roads or scenery.'
        $candidate = $candidates[0]
        Set-FootprintPlacement $grid 5 $candidate.tileX $candidate.tileY $candidate.footprintWidth $candidate.footprintHeight $fixtureTemplate $candidate.rotationYaw 'building_macro' 'frontage' @('terrain')
        Test-RecipeTilePlacements (New-Recipe $grid) 5
        Assert ($true) 'Discovered dimensions reserve exactly one builder-valid rectangle.'
        $grid['1,1'].role = 'protected'
        Assert (@(Get-MarkedRoadConnectionCandidates $grid 5 2 3 $fixtureTemplate @('terrain') $roadTemplate).Count -eq 0) 'Protected occupancy excludes candidates in every rotation.'
    }
}
Assert-Rejected { Get-RotatedFootprint 2 3 45 } '*positive dimensions and a cardinal yaw*'
Assert-Rejected { Get-RotatedFootprint 0 3 90 } '*positive dimensions and a cardinal yaw*'

foreach ($size in 1..3) {
    $grid = New-Grid
    foreach ($record in $grid.Values) { $record.role = 'protected' }
    for ($y = 1; $y -le $size; $y++) {
        for ($x = 1; $x -le $size; $x++) { $grid["$x,$y"].role = 'terrain' }
    }
    $squareCases = @(
        @{ yaw = 0; x = 1; y = 0; roadYaw = 90 },
        @{ yaw = 90; x = 0; y = $size; roadYaw = 0 },
        @{ yaw = 180; x = $size; y = $size + 1; roadYaw = 90 },
        @{ yaw = 270; x = $size + 1; y = 1; roadYaw = 0 }
    )
    foreach ($case in $squareCases) {
        $grid["$($case.x),$($case.y)"] = [pscustomobject]@{
            tileX = $case.x; tileY = $case.y; template = $roadTemplate; rotationYaw = $case.roadYaw; role = 'road'
        }
    }
    $templateRoadConnections[$fixtureTemplate] = [pscustomobject]@{
        direction = 'N'
        markers = @([pscustomobject]@{ originX = -($size - 1) * 320.0; originY = $size * 320.0; connectionType = 'driveway' })
    }
    $candidates = @(Get-MarkedRoadConnectionCandidates $grid 5 $size $size $fixtureTemplate @('terrain') $roadTemplate)
    Assert ($candidates.Count -eq 4) 'Square control retains exactly four cardinal marked candidates.'
    foreach ($case in $squareCases) {
        $candidate = @($candidates | Where-Object rotationYaw -eq $case.yaw)
        Assert ($candidate.Count -eq 1 -and $candidate[0].tileX -eq 1 -and $candidate[0].tileY -eq 1) 'Square owner anchor and yaw remain unchanged.'
        Assert ($candidate[0].roadConnections[0].road.tileX -eq $case.x -and $candidate[0].roadConnections[0].road.tileY -eq $case.y) 'Square authored marker retains its original cardinal target.'
    }
    $templateRoadConnections[$fixtureTemplate].markers[0].originY = 0
    Assert-Rejected { Get-MarkedRoadConnectionCandidates $grid 5 $size $size $fixtureTemplate @('terrain') $roadTemplate } '*exterior footprint edge*'
}

Write-Output "Rectangular footprints: $passed assertions passed; square/rectangle ownership and rotated marked/unmarked frontage. No assets selected, maps generated or compiled."
