Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Road connections: $Message" }
    $script:passed++
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'plan_cell_templates.ps1'), [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Planner parses.'
foreach ($name in @('Resolve-Template', 'Get-OppositeDirection', 'Get-DirectionToCoordinate', 'Get-CarparkJunctionRotation', 'Get-RotatedFootprint',
        'Get-RotatedCardinalDirection', 'Get-OffsetTileCoordinate', 'Get-FootprintCoordinates', 'Get-FootprintAnchorCandidates',
        'Get-MarkedRoadConnectionCandidates', 'Get-RoadConnectionTemplateMap', 'Get-RoadConnectionBase', 'Test-RoadConnectionAvailable',
        'Resolve-RoadConnectionRequests', 'Get-SingleTileRoadConnectionRequest', 'Set-ResolvedRoadConnection', 'Set-MarkedRoadJunctions')) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    Assert ($definition.Count -eq 1) "One production definition of $name."
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

$profile = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$generatorSettings = $profile.Settings
$plannerSettings = $generatorSettings.cellPlanning
$roadTemplate = [string]$plannerSettings.topologyTemplates['road-straight']
Assert ($roadTemplate -eq 'roads/tile_road.vmf') 'Ordinary straight road template is resolved.'
foreach ($connectionType in @('bus', 'driveway', 'parking', 'dual_driveway')) {
    Assert ($plannerSettings.roadConnectionTemplates.ContainsKey($connectionType)) "Settings configure $connectionType."
    $path = Join-Path (Join-Path $testsRepoRoot 'tiletemplates') ($plannerSettings.roadConnectionTemplates[$connectionType].Replace('/', '\'))
    Assert (Test-Path -LiteralPath $path) "Configured $connectionType template exists."
}
$available = @{}
foreach ($template in @($roadTemplate, [string]$plannerSettings.topologyTemplates['road-tjunction'], 'fixture-terrain.vmf') + @($plannerSettings.roadConnectionTemplates.Values)) {
    $available[$template.ToLowerInvariant()] = $template
}
$templates = Get-RoadConnectionTemplateMap $available 'fixture-terrain.vmf'
Assert ($templates.parking -eq 'roads/tile_road_parking.vmf' -and $templates.dual_driveway -eq 'roads/tile_road_driveway_double.vmf') 'One template map resolves parking and dual driveway.'
$templateRoadConnections = @{}

function New-RoadGrid {
    param([int]$RoadYaw)
    $script:RoadConnectionState = [System.Runtime.CompilerServices.ConditionalWeakTable[object, hashtable]]::new()
    $grid = @{}
    for ($y = 0; $y -lt 5; $y++) {
        for ($x = 0; $x -lt 5; $x++) {
            $onRoad = if ($RoadYaw -eq 0) { $x -eq 2 } else { $y -eq 2 }
            $grid["$x,$y"] = [pscustomobject]@{
                tileX = $x; tileY = $y
                template = if ($onRoad) { $roadTemplate } else { 'fixture-terrain.vmf' }
                rotationYaw = if ($onRoad) { $RoadYaw } else { 0 }
                role = if ($onRoad) { 'road' } else { 'terrain' }
            }
        }
    }
    return $grid
}

function Set-MarkerTemplate {
    param([string]$Template, [string]$ConnectionType)
    $script:templateRoadConnections[$Template.ToLowerInvariant()] = [pscustomobject]@{
        direction = 'N'
        markers = @([pscustomobject]@{ originX = 0.0; originY = 320.0; connectionType = $ConnectionType })
    }
}

function Request-SingleTile {
    param([hashtable]$Grid, [int]$X, [int]$Y, [string]$ConnectionType, [int]$RoadX, [int]$RoadY)
    $template = "fixture-$ConnectionType-$X-$Y.vmf"
    Set-MarkerTemplate $template $ConnectionType
    $building = [pscustomobject]@{ tileX = $X; tileY = $Y }
    $request = Get-SingleTileRoadConnectionRequest $Grid $template $Grid["$RoadX,$RoadY"] $building $roadTemplate
    if ($null -ne $request) { Set-MarkedRoadJunctions $Grid @($request) $templates 'building_road_junction' }
    return $request
}

# Every cardinal frontage applies its 1x1 request to the adjacent ordinary road with the connection-tile yaw.
foreach ($case in @(
    @{ roadYaw = 0; x = 1; y = 2; branch = 'W' },
    @{ roadYaw = 0; x = 3; y = 2; branch = 'E' },
    @{ roadYaw = 90; x = 2; y = 1; branch = 'N' },
    @{ roadYaw = 90; x = 2; y = 3; branch = 'S' }
)) {
    $grid = New-RoadGrid $case.roadYaw
    $request = Request-SingleTile $grid $case.x $case.y 'driveway' 2 2
    Assert ($null -ne $request -and $request.branchDirection -eq $case.branch) "1x1 $($case.branch) frontage requests the adjacent road."
    $road = $grid['2,2']
    Assert ($road.template -eq $templates.driveway -and $road.rotationYaw -eq (Get-CarparkJunctionRotation $case.branch)) "1x1 $($case.branch) driveway is placed on the road with branch yaw."
    Assert ((@($road.PSObject.Properties.Name) -join ',') -eq 'tileX,tileY,template,rotationYaw,role') 'Converted placements add no recipe fields.'
    Assert ((Get-RoadConnectionBase $grid $road).template -eq $roadTemplate) 'Converted road retains its ordinary base.'
}

# Opposite driveways share a dual driveway; priorities are driveway > parking > bus in either request order.
$priorityCases = @(
    @{ first = 'driveway'; second = 'driveway'; expected = 'dual_driveway' },
    @{ first = 'driveway'; second = 'parking'; expected = 'driveway' },
    @{ first = 'parking'; second = 'driveway'; expected = 'driveway' },
    @{ first = 'driveway'; second = 'bus'; expected = 'driveway' },
    @{ first = 'bus'; second = 'driveway'; expected = 'driveway' },
    @{ first = 'parking'; second = 'bus'; expected = 'parking' },
    @{ first = 'bus'; second = 'parking'; expected = 'parking' },
    @{ first = 'bus'; second = 'bus'; expected = 'bus' }
)
foreach ($roadYaw in @(0, 90)) {
    foreach ($case in $priorityCases) {
        $grid = New-RoadGrid $roadYaw
        $firstTile = if ($roadYaw -eq 0) { @(1, 2) } else { @(2, 1) }
        $secondTile = if ($roadYaw -eq 0) { @(3, 2) } else { @(2, 3) }
        $firstRequest = Request-SingleTile $grid $firstTile[0] $firstTile[1] $case.first 2 2
        $secondRequest = Request-SingleTile $grid $secondTile[0] $secondTile[1] $case.second 2 2
        Assert ($null -ne $firstRequest -and $null -ne $secondRequest) "Opposite $($case.first)/$($case.second) requests both reach the converted road."
        $expectedBranch = if ($case.expected -eq 'dual_driveway' -or $case.expected -eq $case.first) { $firstRequest.branchDirection } else { $secondRequest.branchDirection }
        Assert ($grid['2,2'].template -eq $templates[$case.expected]) "$($case.first) + $($case.second) resolves to $($case.expected) (yaw $roadYaw)."
        Assert ($grid['2,2'].rotationYaw -eq (Get-CarparkJunctionRotation $expectedBranch)) "$($case.expected) faces its winning building."
    }
}

# A real T-junction is preserved and blocks later frontage connections.
$grid = New-RoadGrid 0
Set-MarkedRoadJunctions $grid @([pscustomobject]@{ road = $grid['2,2']; branchDirection = 'W'; connectionType = 't_junction' }) $templates 'landmark_road_junction'
Assert ($grid['2,2'].template -eq $templates.t_junction) 'T-junction marker places the T-junction.'
Assert ($null -eq (Request-SingleTile $grid 3 2 'driveway' 2 2)) 'A T-junction road rejects a later driveway.'
Assert ($grid['2,2'].template -eq $templates.t_junction -and $grid['2,2'].role -eq 'landmark_road_junction') 'T-junction remains unchanged.'

# In-line, motorway, path and non-road targets receive no connection tile.
$grid = New-RoadGrid 0
Assert ($null -eq (Request-SingleTile $grid 2 1 'driveway' 2 2)) 'An in-line building cannot request a perpendicular road connection.'
foreach ($target in @(
    @{ template = 'roads/motorway_3x1/tile_motorway.vmf'; role = 'road' },
    @{ template = 'roads/tile_concrete_path.vmf'; role = 'path' },
    @{ template = 'roads/tile_road_a.vmf'; role = 'road' },
    @{ template = 'fixture-terrain.vmf'; role = 'terrain' }
)) {
    $grid = New-RoadGrid 0
    $grid['2,2'].template = $target.template
    $grid['2,2'].role = $target.role
    Assert ($null -eq (Request-SingleTile $grid 1 2 'driveway' 2 2)) "$($target.template) receives no connection tile."
    Assert ($grid['2,2'].template -eq $target.template) "$($target.template) remains unchanged."
}
$grid = New-RoadGrid 0
Set-MarkerTemplate 'fixture-none.vmf' 'none'
Assert ($null -eq (Get-SingleTileRoadConnectionRequest $grid 'fixture-none.vmf' $grid['2,2'] ([pscustomobject]@{ tileX = 1; tileY = 2 }) $roadTemplate)) 'A none marker requests no connection.'

# Multi-tile candidate selection also sees a road converted by another building.
$grid = New-RoadGrid 0
Request-SingleTile $grid 1 2 'driveway' 2 2 | Out-Null
foreach ($record in $grid.Values) { if ($record.role -eq 'terrain') { $record.role = 'protected' } }
$grid['3,2'].role = 'terrain'
Set-MarkerTemplate 'fixture-multi.vmf' 'driveway'
$candidates = @(Get-MarkedRoadConnectionCandidates $grid 5 1 1 'fixture-multi.vmf' @('terrain') $roadTemplate)
Assert ($candidates.Count -eq 1 -and $candidates[0].roadConnections.Count -eq 1) 'Marked candidate targets the converted ordinary road.'
Set-MarkedRoadJunctions $grid $candidates[0].roadConnections $templates 'building_road_junction'
Assert ($grid['2,2'].template -eq $templates.dual_driveway) 'Multi-tile and 1x1 opposite driveways resolve to dual driveway.'

# Replacing a converted placement by other planner code discards stale connection state.
$grid = New-RoadGrid 0
Request-SingleTile $grid 1 2 'bus' 2 2 | Out-Null
$grid['2,2'] = [pscustomobject]@{ tileX = 2; tileY = 2; template = $roadTemplate; rotationYaw = 0; role = 'road' }
Request-SingleTile $grid 3 2 'bus' 2 2 | Out-Null
Assert ($grid['2,2'].rotationYaw -eq (Get-CarparkJunctionRotation 'E')) 'Replaced road state does not resurrect an earlier request.'

Write-Output "Road connections: $passed assertions passed; 1x1/multi-tile requests, dual driveway, priority and protected targets. No maps generated or compiled."
