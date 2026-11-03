Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'scenery_density.psm1') -Force
$passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Building frontage repair: $Message" }
    $script:passed++
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'plan_cell_templates.ps1'), [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Planner parses.'
foreach ($name in @(
    'Resolve-Template', 'Get-TemplateFootprint', 'Get-TemplateFrontageDirection', 'Get-TemplateRoadConnectionRotation',
    'Get-OppositeDirection', 'Get-RotatedCardinalDirection', 'Get-OffsetTileCoordinate', 'Get-DirectionToCoordinate', 'Test-RoadPlacementFacesCoordinate',
    'Get-CarparkJunctionRotation', 'Get-FootprintCoordinates', 'Get-RotatedFootprint', 'Get-FootprintAnchorCandidates',
    'Set-FootprintPlacement', 'Test-TemplateRequestsRoadJunction', 'Get-MarkedRoadConnectionCandidates',
    'Get-RoadConnectionTemplateMap', 'Get-RoadConnectionBase', 'Test-RoadConnectionAvailable', 'Resolve-RoadConnectionRequests',
    'Set-ResolvedRoadConnection', 'Set-MarkedRoadJunctions', 'Remove-PlacementRoadConnections',
    'Get-BuildingFootprintDimensions', 'Get-BuildingFrontageCoordinates', 'Test-BuildingFrontageClear',
    'Get-BuildingAdjacentRoadDirections', 'Repair-BlockedBuildingFrontages', 'Get-BuildingFrontageKeys',
    'Get-PlannerTileHash', 'Set-OpenTerrainFill'
)) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    Assert ($definition.Count -eq 1) "One production definition of $name."
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

$profile = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$generatorSettings = $profile.Settings
$plannerSettings = $profile.Settings.cellPlanning
$roadTemplate = [string]$plannerSettings.topologyTemplates['road-straight']
$terrainTemplate = 'fixture-terrain.vmf'
$available = @{}
foreach ($template in @($roadTemplate, [string]$plannerSettings.topologyTemplates['road-tjunction'], $terrainTemplate) + @($plannerSettings.roadConnectionTemplates.Values)) {
    $available[$template.ToLowerInvariant()] = $template
}
$roadTemplates = Get-RoadConnectionTemplateMap $available $terrainTemplate
$maximumMultiTileFootprint = 3
$maximumOpenTilePercent = 0
$sceneryDensityPolicyEnabled = $false
$templateRoadConnections = @{}
$cell = [pscustomobject]@{ x = 7; y = 9 }

function New-Grid {
    $script:RoadConnectionState = [System.Runtime.CompilerServices.ConditionalWeakTable[object, hashtable]]::new()
    $grid = @{}
    for ($y = 0; $y -lt 5; $y++) {
        for ($x = 0; $x -lt 5; $x++) {
            $grid["$x,$y"] = [pscustomobject]@{ tileX = $x; tileY = $y; template = $terrainTemplate; rotationYaw = 0; role = 'terrain' }
        }
    }
    return $grid
}

function Set-BlockedTile {
    param([hashtable]$Grid, [int]$X, [int]$Y)
    $Grid["$X,$Y"] = [pscustomobject]@{ tileX = $X; tileY = $Y; template = 'fixture-blocker.vmf'; rotationYaw = 0; role = 'building_occupied' }
}

function Set-RoadTile {
    param([hashtable]$Grid, [int]$X, [int]$Y, [int]$Yaw)
    $Grid["$X,$Y"] = [pscustomobject]@{ tileX = $X; tileY = $Y; template = $roadTemplate; rotationYaw = $Yaw; role = 'road' }
}

function Invoke-Repair {
    param([hashtable]$Grid, [string[]]$CellConnections = @(), [string]$Topology = 'open')
    $output = @(Repair-BlockedBuildingFrontages $Grid 5 $terrainTemplate $cell 'none' $CellConnections $Topology $available 3>&1)
    $maps = @($output | Where-Object { $_ -is [hashtable] })
    Assert ($maps.Count -eq 1) 'Repair returns one protected-terrain map.'
    return [pscustomobject]@{
        protected = $maps[0]
        warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    }
}

$single = 'tile_fixture_1a.vmf'
$templateRoadConnections[$single] = @{ direction = 'N'; markers = @() }
foreach ($case in @(
    @{ direction = 'N'; x = 2; y = 1 },
    @{ direction = 'E'; x = 3; y = 2 },
    @{ direction = 'S'; x = 2; y = 3 },
    @{ direction = 'W'; x = 1; y = 2 }
)) {
    $grid = New-Grid
    $yaw = Get-TemplateRoadConnectionRotation $single $case.direction
    Set-FootprintPlacement $grid 5 2 2 1 1 $single $yaw 'building' 'owner' @('terrain')
    Set-BlockedTile $grid $case.x $case.y
    $result = Invoke-Repair $grid
    $owner = $grid['2,2']
    $front = Get-RotatedCardinalDirection 'N' ([int]$owner.rotationYaw)
    Assert ($owner.role -eq 'building' -and $owner.rotationYaw -ne $yaw -and (Test-BuildingFrontageClear $grid $owner $front)) "A blocked $($case.direction) frontage rotates to a clear side."
    Assert ($grid["$($case.x),$($case.y)"].role -eq 'building_occupied' -and $result.warnings.Count -eq 0) 'A successful repair preserves its neighbour and reports no replacement.'
}

$grid = New-Grid
Set-FootprintPlacement $grid 5 2 2 1 1 $single 0 'building' 'owner' @('terrain')
$before = ConvertTo-Json -InputObject $grid -Depth 10 -Compress
$result = Invoke-Repair $grid
Assert ((ConvertTo-Json -InputObject $grid -Depth 10 -Compress) -ceq $before) 'An already-clear frontage remains byte-for-byte unchanged.'
Assert ($result.protected.Count -eq 0 -and $result.warnings.Count -eq 0) 'An unchanged building requires no fallback.'

$grid = New-Grid
Set-FootprintPlacement $grid 5 0 2 1 1 $single 90 'building' 'owner' @('terrain')
$result = Invoke-Repair $grid
$front = Get-RotatedCardinalDirection 'N' ([int]$grid['0,2'].rotationYaw)
Assert ($front -ne 'W' -and (Test-BuildingFrontageClear $grid $grid['0,2'] $front)) 'A frontage pointing outside the core turns inward.'

$grid = New-Grid
Set-FootprintPlacement $grid 5 2 2 1 1 $single 0 'building' 'owner' @('terrain')
Set-BlockedTile $grid 2 1
Set-RoadTile $grid 1 2 0
$grid['1,2'].role = 'road_center'
Set-RoadTile $grid 3 2 0
$result = Invoke-Repair $grid @('N', 'W') 'road-corner'
Assert ($grid['2,2'].rotationYaw -eq 90) 'A repaired building may visually face the closed side of a road corner.'

$grid = New-Grid
Set-FootprintPlacement $grid 5 2 2 1 1 $single 0 'building' 'owner' @('terrain')
Set-BlockedTile $grid 2 1
Set-RoadTile $grid 1 2 0
$grid['1,2'].template = [string]$plannerSettings.topologyTemplates['road-deadend']
Set-RoadTile $grid 3 2 0
$result = Invoke-Repair $grid @() 'road-straight'
Assert ($grid['2,2'].rotationYaw -eq 270) 'A repaired building avoids a capped deadend and faces the compatible road instead.'

$square = 'tile_fixture_1a_2x2.vmf'
$templateRoadConnections[$square] = @{ direction = 'N'; markers = @() }
$grid = New-Grid
Set-FootprintPlacement $grid 5 1 1 2 2 $square 0 'building' 'square' @('terrain')
Set-BlockedTile $grid 1 0
$result = Invoke-Repair $grid
Assert ($grid['1,1'].rotationYaw -eq 0) 'One open midpoint-adjacent tile keeps an even-width entrance clear.'
Set-BlockedTile $grid 2 0
$result = Invoke-Repair $grid
Assert ($grid['1,1'].rotationYaw -eq 90) 'Both blocked midpoint-adjacent tiles trigger an in-place square rotation.'
foreach ($key in @('1,1', '2,1', '1,2', '2,2')) {
    Assert ($grid[$key].rotationYaw -eq 90 -and $grid[$key].placementId -eq 'square') 'Every square footprint record retains its owner and updated yaw.'
}
Assert ($grid['1,0'].role -eq 'building_occupied' -and $grid['2,0'].role -eq 'building_occupied') 'Square rotation never overwrites blocking neighbours.'

$rectangle = 'tile_fixture_1a_2x3.vmf'
$templateRoadConnections[$rectangle] = @{ direction = 'N'; markers = @() }
$grid = New-Grid
Set-FootprintPlacement $grid 5 1 1 2 3 $rectangle 0 'building' 'rectangle' @('terrain')
Set-BlockedTile $grid 1 0
Set-BlockedTile $grid 2 0
$result = Invoke-Repair $grid
Assert ($grid['1,1'].rotationYaw -eq 180 -and $grid['2,3'].rotationYaw -eq 180) 'A rectangular footprint rotates 180 degrees without swapping its dimensions.'
Assert ($grid['1,1'].footprintWidth -eq 2 -and $grid['1,1'].footprintHeight -eq 3) 'Rectangle occupancy is unchanged.'

$grid = New-Grid
Set-FootprintPlacement $grid 5 1 1 2 3 $rectangle 0 'building' 'rectangle' @('terrain')
foreach ($coordinate in @(@(1, 0), @(2, 0), @(1, 4), @(2, 4))) { Set-BlockedTile $grid $coordinate[0] $coordinate[1] }
$result = Invoke-Repair $grid
Assert ($result.protected.Count -eq 6 -and $result.warnings.Count -eq 1) 'An ordinary rectangle with no safe in-place rotation is reported and replaced.'
foreach ($key in @('1,1', '2,1', '1,2', '2,2', '1,3', '2,3')) {
    Assert ($grid[$key].role -eq 'terrain' -and $result.protected.ContainsKey($key)) 'Every replaced footprint slot remains open terrain.'
}
Set-OpenTerrainFill -Placements $grid -TileGridSize 5 -PlacementSeed 10 -DecorationTemplates @('fixture-decoration.vmf') -Cell $cell -Profile 'grassland' -Topology 'open' -Orientation 'none' -BuildingDensityTier 1 -Landmarks @() -CellVariant 0 -AvailableTemplates $available -ProtectedTerrain $result.protected
Assert ($grid['1,1'].role -eq 'terrain' -and $grid['2,3'].role -eq 'terrain' -and $grid['4,4'].role -eq 'decoration') 'Later decoration fill preserves replacement terrain while filling unprotected terrain.'

$grid = New-Grid
Set-FootprintPlacement $grid 5 1 1 2 3 $rectangle 0 'landmark' 'landmark' @('terrain')
foreach ($coordinate in @(@(1, 0), @(2, 0), @(1, 4), @(2, 4))) { Set-BlockedTile $grid $coordinate[0] $coordinate[1] }
$result = Invoke-Repair $grid
Assert ($grid['1,1'].role -eq 'landmark' -and $grid['2,3'].role -eq 'landmark_occupied') 'An unrepairable landmark and its footprint are retained.'
Assert ($result.warnings.Count -eq 1 -and $result.warnings[0].Message -like '*7,9*retains blocked required frontage*') 'The retained landmark is explicitly reported with its cell.'

$grid = New-Grid
Set-FootprintPlacement $grid 5 1 1 2 2 $square 0 'building' 'square' @('terrain')
$result = Invoke-Repair $grid
Set-OpenTerrainFill -Placements $grid -TileGridSize 5 -PlacementSeed 10 -DecorationTemplates @('fixture-decoration.vmf') -Cell $cell -Profile 'grassland' -Topology 'open' -Orientation 'none' -BuildingDensityTier 1 -Landmarks @() -CellVariant 0 -AvailableTemplates $available -ProtectedTerrain $result.protected
Assert ($grid['1,0'].role -eq 'terrain' -and $grid['2,0'].role -eq 'terrain' -and $grid['4,4'].role -eq 'decoration') 'Both central tiles of an even-width entrance remain open through decoration fill.'

$grid = New-Grid
Set-RoadTile $grid 2 2 0
$baseRoad = $grid['2,2']
Set-MarkedRoadJunctions $grid @(
    [pscustomobject]@{ road = $baseRoad; branchDirection = 'W'; connectionType = 'driveway' },
    [pscustomobject]@{ road = $baseRoad; branchDirection = 'E'; connectionType = 'driveway' }
) $roadTemplates 'building_road_junction'
Assert ($grid['2,2'].template -eq $roadTemplates.dual_driveway) 'Opposing buildings share a dual driveway.'
Remove-PlacementRoadConnections $grid @{ '1,2' = $true } $roadTemplates 'building_road_junction'
Assert ($grid['2,2'].template -eq $roadTemplates.driveway -and $grid['2,2'].rotationYaw -eq (Get-CarparkJunctionRotation 'E')) 'Removing one owner retains and re-resolves the other driveway.'
Remove-PlacementRoadConnections $grid @{ '3,2' = $true } $roadTemplates 'building_road_junction'
Assert ([object]::ReferenceEquals($grid['2,2'], $baseRoad)) 'Removing the last owner restores the original road placement.'

$grid = New-Grid
Set-RoadTile $grid 2 2 0
$baseRoad = $grid['2,2']
Set-MarkedRoadJunctions $grid @([pscustomobject]@{ road = $baseRoad; branchDirection = 'W'; connectionType = 'driveway' }) $roadTemplates 'building_road_junction'
Set-MarkedRoadJunctions $grid @([pscustomobject]@{ road = $grid['2,2']; branchDirection = 'E'; connectionType = 't_junction' }) $roadTemplates 'landmark_road_junction'
Remove-PlacementRoadConnections $grid @{ '3,2' = $true } $roadTemplates 'landmark_road_junction'
Assert ($grid['2,2'].template -eq $roadTemplates.driveway -and $grid['2,2'].rotationYaw -eq (Get-CarparkJunctionRotation 'W')) 'Removing a winning landmark junction restores the other owner''s driveway.'

$implicitSouth = 'tile_fixture_south_1a.vmf'
$templateRoadConnections[$implicitSouth] = @{
    direction = 'S'
    markers = @([pscustomobject]@{ originX = 0.0; originY = -320.0; connectionType = 'driveway' })
}
$grid = New-Grid
Set-FootprintPlacement $grid 5 2 2 1 1 $implicitSouth 0 'building' 'south' @('terrain')
Set-RoadTile $grid 2 3 90
$southCandidates = @(Get-MarkedRoadConnectionCandidates $grid 5 1 1 $implicitSouth @('building') $roadTemplate |
    Where-Object { $_.tileX -eq 2 -and $_.tileY -eq 2 -and $_.rotationYaw -eq 0 })
Assert ($southCandidates.Count -eq 1 -and $southCandidates[0].roadConnections[0].branchDirection -eq 'N') 'A south-default road marker reaches its physical south road without rotating.'

$wide = 'tile_fixture_1a_3x1.vmf'
$templateRoadConnections[$wide] = @{
    direction = 'N'
    markers = @([pscustomobject]@{ originX = -640.0; originY = 320.0; connectionType = 'driveway' })
}
$grid = New-Grid
Set-FootprintPlacement $grid 5 1 2 3 1 $wide 0 'building' 'wide' @('terrain')
Set-FootprintPlacement $grid 5 1 0 1 1 'unmarked.vmf' 0 'building' 'neighbour' @('terrain')
Set-BlockedTile $grid 2 1
Set-RoadTile $grid 1 1 90
Set-RoadTile $grid 3 3 90
Set-MarkedRoadJunctions $grid @(
    [pscustomobject]@{ road = $grid['1,1']; branchDirection = 'S'; connectionType = 'driveway' },
    [pscustomobject]@{ road = $grid['1,1']; branchDirection = 'N'; connectionType = 'driveway' }
) $roadTemplates 'building_road_junction'
$result = Invoke-Repair $grid
Assert ($grid['1,2'].rotationYaw -eq 180 -and $grid['3,2'].rotationYaw -eq 180) 'A blocked marked rectangle rotates only when its new authored road connection fits.'
Assert ($grid['1,1'].template -eq $roadTemplates.driveway -and $grid['1,1'].rotationYaw -eq (Get-CarparkJunctionRotation 'N')) 'The old shared road retains the neighbouring building request.'
Assert ($grid['3,3'].template -eq $roadTemplates.driveway -and $grid['3,3'].rotationYaw -eq (Get-CarparkJunctionRotation 'N')) 'The rotated building installs its new road connection.'
Assert ($grid['2,1'].role -eq 'building_occupied' -and $result.warnings.Count -eq 0) 'Marked rotation protects the blocking neighbour without a fallback warning.'

Write-Output "Building frontage repair passed: $passed assertions."
