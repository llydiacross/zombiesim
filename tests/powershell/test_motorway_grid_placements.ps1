param(
    [string]$PlanData = '',
    [string]$TrustedPlanData = '',
    [string]$VmfDirectory = '',
    # Optional plan built from the same inputs before a placement change; every cell
    # without a restored on-ramp dogleg must match it exactly.
    [string]$BaselinePlanData = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $PlanData = Join-Path $root 'generated\phase_j_preview_20261015\plan_grid_road_review_corrected.json'
}
if ([string]::IsNullOrWhiteSpace($TrustedPlanData)) {
    $TrustedPlanData = Join-Path $root 'generated\phase_j_preview_20261015\plan.json'
}
if ([string]::IsNullOrWhiteSpace($VmfDirectory)) {
    $VmfDirectory = Join-Path $root 'generated\phase_j_grid_road_review_corrected\src'
}
foreach ($path in @($PlanData, $TrustedPlanData, $VmfDirectory)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Motorway grid test input is missing: $path" }
}
Import-Module (Join-Path $bin 'skybox_models.psm1') -Force
Import-Module (Join-Path $bin 'motorway_geometry.psm1') -Force
Import-Module (Join-Path $bin 'transition_gates.psm1')
Import-Module (Join-Path $bin 'motorway_grid_placements.psm1') -Force

foreach ($source in @(
    @{ path = 'build_cell_vmfs.ps1'; names = @('ConvertTo-TransitionGatePlacements', 'Get-TransitionGatePlacements') },
    @{ path = 'export_runtime_world_data.ps1'; names = @('Get-RuntimeMotorwayGates') }
)) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $bin $source.path), [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Cannot parse $($source.path)." }
    foreach ($name in $source.names) {
        $definitions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $false))
        if ($definitions.Count -ne 1) { throw "Expected one $name in $($source.path)." }
        . ([scriptblock]::Create($definitions[0].Extent.Text))
    }
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$trustedPlan = Get-Content -Raw -LiteralPath $TrustedPlanData | ConvertFrom-Json
$tileSize = [int]$plan.cellBounds.tileSize
$gridSize = [int]$plan.cellTileGridSize
$center = [int][Math]::Floor($gridSize / 2)
$passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway grid placements: $Message" }
    $script:passed++
}

function Get-JsonSignature {
    param([object[]]$Value)
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
}

function Get-RoadTilePlacements {
    param([object]$Cell)
    return @($Cell.tilePlacements | Where-Object {
        $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road') -and
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -like 'tile_road*.vmf'
    })
}

function Get-RoadAssemblyPlacements {
    param([object]$Cell)
    return @($Cell.motorwayAssembly.assemblies | Where-Object {
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -like 'tile_road*.vmf'
    })
}

function Test-GridAxis {
    param([double]$Value, [int]$Size)
    return [Math]::Abs($Value - ([Math]::Round($Value / $Size) * $Size)) -lt 0.000001
}

function Get-GateForwardCoordinate {
    param([string]$Direction, [double]$X, [double]$Y)
    switch ($Direction) {
        'N' { return $Y }
        'E' { return $X }
        'S' { return -$Y }
        'W' { return -$X }
        default { throw "Gate direction is not cardinal: $Direction" }
    }
}

function Get-Instance {
    param([object[]]$Instances, [string]$Targetname)
    $matches = @($Instances | Where-Object { $_.Get('targetname') -ceq $Targetname })
    if ($matches.Count -ne 1) { throw "Expected one VMF instance '$Targetname'; found $($matches.Count)." }
    return $matches[0]
}

$planEmptyCells = if ($plan.PSObject.Properties['emptyCells']) { @($plan.emptyCells) } else { @() }
Assert ($trustedPlan.cells.Count -eq 576 -and ($plan.cells.Count + $planEmptyCells.Count) -eq 576) 'The regenerated and trusted plans describe the same full preview.'
Assert ($plan.mapSeed -eq $trustedPlan.mapSeed -and $plan.mapGridCells -eq $trustedPlan.mapGridCells) 'The regenerated plan keeps the approved seed and cell grid.'

$trustedCellsByCoordinate = @{}
foreach ($cell in $trustedPlan.cells) {
    $coordinate = "$($cell.x),$($cell.y)"
    if ($trustedCellsByCoordinate.ContainsKey($coordinate)) { throw "Trusted plan repeats cell $coordinate." }
    $trustedCellsByCoordinate[$coordinate] = $cell
}

$motorPathPattern = '(?i)\\motorway_3x1\\tile_motorway[^\\]*\.vmf$'
$motorwayCells = @($plan.cells | Where-Object { $_.topology -like 'motorway-*' })
Assert ($motorwayCells.Count -eq 96) 'All 96 approved wide-motorway cells are present.'

$baselineCellsByCoordinate = $null
if (-not [string]::IsNullOrWhiteSpace($BaselinePlanData)) {
    $baselinePlan = Get-Content -Raw -LiteralPath $BaselinePlanData | ConvertFrom-Json
    Assert ($baselinePlan.cells.Count -eq $plan.cells.Count) 'The baseline plan has the same planned cells.'
    $baselineCellsByCoordinate = @{}
    foreach ($cell in $baselinePlan.cells) { $baselineCellsByCoordinate["$($cell.x),$($cell.y)"] = $cell }
    $changedCells = @()
    foreach ($cell in $plan.cells) {
        $coordinate = "$($cell.x),$($cell.y)"
        if (-not $baselineCellsByCoordinate.ContainsKey($coordinate)) { throw "Baseline plan has no cell $coordinate." }
        $baselineCell = $baselineCellsByCoordinate[$coordinate]
        $restoredCount = 0
        $contractProperty = $cell.PSObject.Properties['motorwayAssembly']
        if ($null -ne $contractProperty -and $null -ne $contractProperty.Value.PSObject.Properties['ordinaryRoadApproaches']) {
            $restoredCount = @($contractProperty.Value.ordinaryRoadApproaches).Count
        }
        $same = (Get-JsonSignature @($cell.tilePlacements)) -ceq (Get-JsonSignature @($baselineCell.tilePlacements)) -and
            $cell.cellTemplateFilename -ceq $baselineCell.cellTemplateFilename
        if ($null -ne $contractProperty) {
            $same = $same -and (Get-JsonSignature @($contractProperty.Value)) -ceq (Get-JsonSignature @($baselineCell.motorwayAssembly))
        }
        if ($restoredCount -eq 0) {
            Assert $same "Cells without a restored on-ramp dogleg match the baseline plan at $coordinate."
        } elseif (-not $same) {
            $changedCells += $coordinate
        }
    }
    Assert ((@($changedCells | Sort-Object) -join ';') -ceq '13,18;6,23') 'Only the two trusted on-ramp approach cells change from the baseline plan.'
}

foreach ($cell in $plan.cells) {
    $coordinate = "$($cell.x),$($cell.y)"
    if (-not $trustedCellsByCoordinate.ContainsKey($coordinate)) { throw "Trusted plan has no cell $coordinate." }
    $trustedCell = $trustedCellsByCoordinate[$coordinate]
    if ($cell.topology -notlike 'motorway-*') {
        # Later approved planner changes (anti-grid roads, empty cells, density) legitimately
        # move ordinary cells away from the October trusted plan, so prefer the baseline.
        if ($null -eq $baselineCellsByCoordinate) {
            Assert ((Get-JsonSignature @($cell.tilePlacements)) -ceq (Get-JsonSignature @($trustedCell.tilePlacements))) "Non-motorway grid placements remain unchanged at $coordinate."
        }
        continue
    }

    $contractProperty = $cell.PSObject.Properties['motorwayAssembly']
    if ($null -eq $contractProperty) { throw "Motorway cell $coordinate has no assembly contract." }
    $contract = $contractProperty.Value
    $trustedContract = $trustedCell.motorwayAssembly
    $runtimeGates = @(Get-RuntimeMotorwayGates $cell)
    Assert ((Get-JsonSignature $runtimeGates) -ceq (Get-JsonSignature @($contract.gates))) "Runtime export retains approved gate records at $coordinate."
    $writtenGates = @(Get-TransitionGatePlacements $cell)
    foreach ($gate in $contract.gates) {
        $route = if ($null -ne $gate.PSObject.Properties['route']) { [string]$gate.route } else { 'motorway' }
        $expectedCount = if ($route -eq 'road') { 1 } else { 2 }
        $written = @($writtenGates | Where-Object direction -eq $gate.direction)
        $arrival = $gate.lanes[[int]$gate.arrivalLane - 1]
        Assert ($written.Count -eq $expectedCount -and
            @($written | Where-Object {
                $_.route -ne $route -or $_.x -ne $gate.x -or $_.y -ne $gate.y -or
                $_.arrivalX -ne $arrival.arrivalX -or $_.arrivalY -ne $arrival.arrivalY
            }).Count -eq 0) "Gate writer preserves route, lane count, position and arrival at $coordinate/$($gate.direction)."
    }
    Assert ($writtenGates.Count -eq (@($contract.gates | ForEach-Object {
        if ($null -ne $_.PSObject.Properties['route'] -and $_.route -eq 'road') { 1 } else { 2 }
    } | Measure-Object -Sum).Sum)) "Gate writer emits no extra triggers at $coordinate."
    if ($contract.schemaVersion -eq 1) {
        if ($null -eq $baselineCellsByCoordinate) {
            Assert ((Get-JsonSignature @($cell.tilePlacements)) -ceq (Get-JsonSignature @($trustedCell.tilePlacements))) "Plain-straight grid slots remain unchanged at $coordinate."
        }
        Assert ((Get-JsonSignature @($contract)) -ceq (Get-JsonSignature @($trustedContract))) "Plain-straight motorway contract remains unchanged at $coordinate."
    } elseif ($contract.schemaVersion -eq 2) {
        $motorAssemblies = @($contract.assemblies | Where-Object { ([string]$_.template).Replace('/', '\') -match $motorPathPattern })
        $trustedMotorAssemblies = @($trustedContract.assemblies | Where-Object { ([string]$_.template).Replace('/', '\') -match $motorPathPattern })
        Assert ((Get-JsonSignature $motorAssemblies) -ceq (Get-JsonSignature $trustedMotorAssemblies)) "Trusted motorway instance origins/yaws remain unchanged at $coordinate."
        $motorGates = @($contract.gates | Where-Object route -ne 'road')
        $trustedMotorGates = @($trustedContract.gates | Where-Object route -ne 'road')
        Assert ((Get-JsonSignature $motorGates) -ceq (Get-JsonSignature $trustedMotorGates)) "Motorway gate records remain unchanged at $coordinate."
    } else {
        throw "Unsupported motorway contract version $($contract.schemaVersion) at $coordinate."
    }

    foreach ($placement in (Get-RoadTilePlacements $cell)) {
        Assert ($placement.tileX -ge 0 -and $placement.tileX -lt $gridSize -and
            $placement.tileY -ge 0 -and $placement.tileY -lt $gridSize) "Core road placement uses a 5x5 tile slot at $coordinate."
        $originX = ([int]$placement.tileX - $center) * $tileSize
        $originY = ($center - [int]$placement.tileY) * $tileSize
        Assert ((Test-GridAxis $originX $tileSize) -and (Test-GridAxis $originY $tileSize)) "Core road placement origin uses the 640-unit grid at $coordinate."
    }

    if ($contract.schemaVersion -eq 2) {
        Assert (@($contract.ordinaryRoadPlacementShifts).Count -eq 0) "No measured road-mouth offsets remain at $coordinate."
        Assert (@($contract.connections | Where-Object route -eq 'road').Count -eq 0) "Road branches are not emitted as measured motorway assemblies at $coordinate."
        $restoredApproaches = @($contract.ordinaryRoadApproaches)
        $trustedApproachHeadings = @($trustedContract.ordinaryRoadApproaches | Where-Object {
            $null -ne $_.PSObject.Properties['instances'] -and @($_.instances).Count -gt 0
        } | ForEach-Object { [string]$_.heading } | Sort-Object)
        Assert ((@($restoredApproaches | ForEach-Object { [string]$_.heading } | Sort-Object) -join ',') -ceq
            ($trustedApproachHeadings -join ',')) "Trusted on-ramp road doglegs are restored, and only those, at $coordinate."
        $approachPrefixes = @($restoredApproaches | ForEach-Object {
            $cornerOwner = [string](@($_.instances | Where-Object { ([string]$_.owner) -like '*/entry_corner' })[0].owner)
            $cornerOwner.Substring(0, $cornerOwner.Length - 'entry_corner'.Length)
        })
        $roadAssemblyPlacements = @(Get-RoadAssemblyPlacements $cell)
        foreach ($assembly in $roadAssemblyPlacements) {
            if (@($approachPrefixes | Where-Object { ([string]$assembly.owner).StartsWith($_, [StringComparison]::Ordinal) }).Count -gt 0) {
                continue
            }
            Assert ([string]$assembly.owner -like 'grid_road/*' -and
                $assembly.disposition -eq 'five_by_five_640_grid') "Road continuation is owned by a grid slot at $coordinate."
            Assert ((Test-GridAxis ([double]$assembly.origin.x) $tileSize) -and
                (Test-GridAxis ([double]$assembly.origin.y) $tileSize)) "Road continuation origin uses the 640-unit grid at $coordinate."
        }
        $motorCoreLeaseSlots = @{}
        $motorOwners = @($motorAssemblies | ForEach-Object { [string]$_.owner })
        foreach ($lease in @($contract.leases | Where-Object { $_.ring -eq 'core' -and $_.owner -in $motorOwners })) {
            $motorCoreLeaseSlots["$($lease.tileX),$($lease.tileY)"] = $true
        }
        foreach ($placement in @(Get-RoadTilePlacements $cell | Where-Object role -eq 'onramp_road')) {
            Assert (-not $motorCoreLeaseSlots.ContainsKey("$($placement.tileX),$($placement.tileY)")) "On-ramp road no longer overlaps a leased 5x5 motorway slot at $coordinate."
        }

        $gridApproachesProperty = $contract.PSObject.Properties['gridRoadApproaches']
        if ($null -eq $gridApproachesProperty) { throw "Motorway cell $coordinate has no grid road approach records." }
        $roadGates = @($contract.gates | Where-Object route -eq 'road')
        Assert ((@($gridApproachesProperty.Value).Count + $restoredApproaches.Count) -eq $roadGates.Count) "Every ordinary-road gate has one grid-slot approach or restored dogleg at $coordinate."
        foreach ($gate in $roadGates) {
            $restored = @($restoredApproaches | Where-Object heading -eq $gate.direction)
            $approach = @($gridApproachesProperty.Value | Where-Object heading -eq $gate.direction)
            $crossCoordinate = if ($gate.direction -in @('N', 'S')) { [double]$gate.x } else { [double]$gate.y }
            if ($restored.Count -eq 1) {
                $portCross = if ($gate.direction -in @('N', 'S')) { [double]$restored[0].boundaryPort.position.x } else { [double]$restored[0].boundaryPort.position.y }
                Assert ($approach.Count -eq 0 -and $crossCoordinate -eq $portCross -and (Test-GridAxis $crossCoordinate $tileSize)) "Restored dogleg gate stays on its 640-grid boundary port at $coordinate/$($gate.direction)."
            } else {
                if ($approach.Count -ne 1) { throw "Expected one grid approach for $coordinate/$($gate.direction)." }
                Assert ($crossCoordinate -eq [double]$approach[0].crossCoordinate) "Ordinary-road gate stays on its grid road axis at $coordinate/$($gate.direction)."
            }

            $trustedGate = @($trustedContract.gates | Where-Object { $_.route -eq 'road' -and $_.direction -eq $gate.direction })
            if ($trustedGate.Count -ne 1) { throw "Trusted plan has no unique road gate for $coordinate/$($gate.direction)." }
            Assert ((Get-GateForwardCoordinate $gate.direction $gate.x $gate.y) -eq
                (Get-GateForwardCoordinate $trustedGate[0].direction $trustedGate[0].x $trustedGate[0].y)) "Road gate keeps its original inward/outward coordinate at $coordinate/$($gate.direction)."
            Assert (@($gate.lanes).Count -eq @($trustedGate[0].lanes).Count) "Road gate lane count is unchanged at $coordinate/$($gate.direction)."
            for ($laneIndex = 0; $laneIndex -lt @($gate.lanes).Count; $laneIndex++) {
                foreach ($pointName in @('arrow', 'arrival')) {
                    $xName = "${pointName}X"
                    $yName = "${pointName}Y"
                    Assert ((Get-GateForwardCoordinate $gate.direction $gate.lanes[$laneIndex].$xName $gate.lanes[$laneIndex].$yName) -eq
                        (Get-GateForwardCoordinate $gate.direction $trustedGate[0].lanes[$laneIndex].$xName $trustedGate[0].lanes[$laneIndex].$yName)) "Road gate $pointName distance is unchanged at $coordinate/$($gate.direction)."
                }
            }
        }
    }
}

$southRamp = @($plan.cells | Where-Object { $_.x -eq 22 -and $_.y -eq 18 })
if ($southRamp.Count -ne 1) { throw 'Affected south-on-ramp cell (22,18) is missing or duplicated.' }
Assert ($southRamp[0].topology -eq 'motorway-straight' -and $southRamp[0].transportFeature -eq 'onramp-s') 'Cell (22,18) remains the approved south on-ramp layout.'
$southSlots = @(Get-RoadTilePlacements $southRamp[0] | ForEach-Object {
    '{0},{1}:{2}' -f $_.tileX, $_.tileY, [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\'))
} | Sort-Object)
Assert (($southSlots -join '|') -ceq '2,4:tile_road_onramp.vmf') 'Cell (22,18) moves the on-ramp to the first unleased south grid slot.'
$southSuppressed = @($southRamp[0].tilePlacements | Where-Object {
    $_.tileX -eq 2 -and $_.tileY -eq 3 -and $_.role -eq 'motorway_external_occupied' -and -not $_.emitsInstance
})
Assert ($southSuppressed.Count -eq 1) 'Cell (22,18) suppresses the overlapping on-ramp slot under motorway ownership.'
$southGate = @($southRamp[0].motorwayAssembly.gates | Where-Object { $_.route -eq 'road' -and $_.direction -eq 'S' })
Assert ($southGate.Count -eq 1 -and $southGate[0].x -eq 0 -and $southGate[0].y -eq -2208) 'Cell (22,18) south road gate follows the grid axis without moving the motorway.'

$dualRamp = @($plan.cells | Where-Object { $_.x -eq 17 -and $_.y -eq 4 })
if ($dualRamp.Count -ne 1) { throw 'Affected dual-on-ramp cell (17,4) is missing or duplicated.' }
Assert ($dualRamp[0].topology -eq 'motorway-straight' -and $dualRamp[0].transportFeature -eq 'onramp-dual-ew') 'Cell (17,4) remains the approved dual east/west on-ramp layout.'
$dualSlots = @(Get-RoadTilePlacements $dualRamp[0] | ForEach-Object {
    '{0},{1}:{2}' -f $_.tileX, $_.tileY, [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\'))
} | Sort-Object)
Assert (($dualSlots -join '|') -ceq '4,2:tile_road_onramp.vmf') 'Cell (17,4) moves the east on-ramp to the first unleased core road slot.'
$westOnrampExtension = @(Get-RoadAssemblyPlacements $dualRamp[0] | Where-Object owner -eq 'grid_road/W/extension1')
Assert ($westOnrampExtension.Count -eq 1 -and
    [IO.Path]::GetFileName(([string]$westOnrampExtension[0].template).Replace('/', '\')) -eq 'tile_road_onramp.vmf' -and
    $westOnrampExtension[0].origin.x -eq -1920 -and $westOnrampExtension[0].origin.y -eq 0 -and
    $westOnrampExtension[0].yaw -eq 270) 'Cell (17,4) puts the west on-ramp on the first 640-unit border continuation.'
$westOuterRoad = @(Get-RoadAssemblyPlacements $dualRamp[0] | Where-Object owner -eq 'grid_road/W/extension2')
Assert ($westOuterRoad.Count -eq 1 -and
    [IO.Path]::GetFileName(([string]$westOuterRoad[0].template).Replace('/', '\')) -eq 'tile_road.vmf' -and
    $westOuterRoad[0].origin.x -eq -2560 -and $westOuterRoad[0].origin.y -eq 0) 'Cell (17,4) continues west beyond the on-ramp on the same 640 grid.'
$dualGates = @($dualRamp[0].motorwayAssembly.gates | Where-Object route -eq 'road')
Assert ((@($dualGates.direction | Sort-Object) -join ',') -ceq 'E,W' -and
    @($dualGates | Where-Object { $_.y -eq 0 }).Count -eq 2) 'Cell (17,4) east/west road gates follow the same tile-grid line.'

$roadYawByDirection = [ordered]@{ N = 0; E = 90; S = 0; W = 90 }
function Invoke-TrustedGridContract {
    param([string]$Coordinate)
    $trustedCell = $trustedCellsByCoordinate[$Coordinate]
    $recipe = $trustedCell | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $result = Set-ZMTrustedMotorwayGridContract $recipe $trustedCell.motorwayAssembly $gridSize $tileSize 2 'roads/tile_road.vmf' 'roads/tile_road_bridge.vmf' $roadYawByDirection
    return [pscustomobject]@{ recipe = $recipe; contract = $result }
}
function Get-AssemblySummary {
    param([object]$Contract, [string]$Suffix)
    $matches = @($Contract.assemblies | Where-Object { ([string]$_.owner).EndsWith("/$Suffix", [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) { throw "Expected one restored assembly ending '$Suffix'; found $($matches.Count)." }
    return '{0}:{1}:{2},{3}' -f [IO.Path]::GetFileName(([string]$matches[0].template).Replace('/', '\')), [int]$matches[0].yaw, [double]$matches[0].origin.x, [double]$matches[0].origin.y
}

# (13,18): motorway corner + south on-ramp keeps its trusted dogleg to the south grid road.
$cornerRamp = Invoke-TrustedGridContract '13,18'
Assert (@($cornerRamp.contract.ordinaryRoadApproaches).Count -eq 1 -and $cornerRamp.contract.ordinaryRoadApproaches[0].heading -eq 'S') 'Cell (13,18) restores its south on-ramp road dogleg.'
Assert ((@('road_approach', 'entry_corner', 'cross_straight', 'ramp_corner', 'entry_straight2240') | ForEach-Object { Get-AssemblySummary $cornerRamp.contract $_ }) -join '|' -ceq
    'tile_road_onramp.vmf:0:1408,-1280|tile_road_corner.vmf:0:0,-1920|tile_road_straight_768.vmf:90:704,-1920|tile_road_corner.vmf:180:1408,-1920|tile_road.vmf:0:0,-2560') 'Cell (13,18) dogleg joins the on-ramp mouth to the centre south road with native pieces.'
Assert (@($cornerRamp.contract.assemblies | Where-Object { ([string]$_.owner) -like 'grid_road/*' }).Count -eq 0 -and
    @($cornerRamp.contract.gridRoadApproaches).Count -eq 0) 'Cell (13,18) adds no competing grid road branch.'
$cornerGate = @($cornerRamp.contract.gates | Where-Object route -eq 'road')
Assert ($cornerGate.Count -eq 1 -and $cornerGate[0].direction -eq 'S' -and $cornerGate[0].x -eq 0 -and $cornerGate[0].y -eq -2208) 'Cell (13,18) south road gate stays on the centre grid axis.'
Assert (@($cornerRamp.recipe.tilePlacements | Where-Object { $_.tileX -eq 2 -and $_.tileY -eq 4 -and $_.role -eq 'terrain' }).Count -eq 1 -and
    @($cornerRamp.recipe.tilePlacements | Where-Object { $_.role -eq 'onramp_road' }).Count -eq 0) 'Cell (13,18) does not relocate a disconnected on-ramp into a grid slot.'
Assert (@($cornerRamp.recipe.tilePlacements | Where-Object {
    $_.tileX -eq 4 -and $_.tileY -eq 4 -and $_.role -eq 'motorway_external_occupied' -and ([string]$_.placementId).EndsWith('/S/road_approach', [StringComparison]::Ordinal)
}).Count -eq 1) 'Cell (13,18) suppresses the core slot under the restored on-ramp.'

# (6,23): motorway dead end + east on-ramp keeps the dogleg, moved onto the y=0 grid with one native extension.
$deadendRamp = Invoke-TrustedGridContract '6,23'
Assert (@($deadendRamp.contract.ordinaryRoadApproaches).Count -eq 1 -and $deadendRamp.contract.ordinaryRoadApproaches[0].heading -eq 'E') 'Cell (6,23) restores its east on-ramp road dogleg.'
Assert ((@('road_approach', 'ramp_corner', 'cross_straight', 'entry_extension', 'entry_corner', 'entry_straight2240') | ForEach-Object { Get-AssemblySummary $deadendRamp.contract $_ }) -join '|' -ceq
    'tile_road_onramp.vmf:90:1280,2048|tile_road_corner.vmf:270:1920,2048|tile_road_straight_768.vmf:180:1920,1344|tile_road.vmf:0:1920,640|tile_road_corner.vmf:90:1920,0|tile_road.vmf:90:2560,0') 'Cell (6,23) dogleg reaches the y=0 grid road through one native 640 straight.'
$extension = @($deadendRamp.contract.assemblies | Where-Object { ([string]$_.owner).EndsWith('/entry_extension', [StringComparison]::Ordinal) })[0]
Assert (@($deadendRamp.contract.leases | Where-Object { $_.owner -eq $extension.owner -and $_.tileX -eq 5 -and $_.tileY -eq 1 -and $_.ring -eq 'border' }).Count -eq 1) 'Cell (6,23) extension leases its border slot.'
$extensionJoins = @($deadendRamp.contract.ordinaryRoadApproaches[0].joins | Where-Object { $_.first -eq $extension.owner -or $_.second -eq $extension.owner })
Assert ($extensionJoins.Count -eq 2) 'Cell (6,23) extension is joined to both neighbouring dogleg pieces.'
Assert (@($deadendRamp.contract.ordinaryRoadPlacementShifts).Count -eq 0 -and
    [double]$deadendRamp.contract.ordinaryRoadApproaches[0].boundaryPort.position.y -eq 0) 'Cell (6,23) normalises the measured road shift onto the grid.'
$deadendGate = @($deadendRamp.contract.gates | Where-Object route -eq 'road')
Assert ($deadendGate.Count -eq 1 -and $deadendGate[0].direction -eq 'E' -and $deadendGate[0].y -eq 0) 'Cell (6,23) east road gate stays on the y=0 grid axis.'
Assert (@($deadendRamp.contract.assemblies | Where-Object { ([string]$_.owner) -like 'grid_road/*' }).Count -eq 0 -and
    @($deadendRamp.recipe.tilePlacements | Where-Object { $_.role -eq 'onramp_road' }).Count -eq 0) 'Cell (6,23) adds no disconnected grid on-ramp extension.'

$nonMotorwayRoadControl = @($plan.cells | Where-Object {
    $_.topology -notlike 'motorway-*' -and @(Get-RoadTilePlacements $_).Count -gt 0
} | Select-Object -First 1)
if ($nonMotorwayRoadControl.Count -ne 1) { throw 'No ordinary-road control cell was found.' }
$controlCoordinate = "$($nonMotorwayRoadControl[0].x),$($nonMotorwayRoadControl[0].y)"
$trustedControl = if ($null -ne $baselineCellsByCoordinate) { $baselineCellsByCoordinate[$controlCoordinate] } else { $trustedCellsByCoordinate[$controlCoordinate] }
Assert ((Get-JsonSignature @($nonMotorwayRoadControl[0].tilePlacements)) -ceq
    (Get-JsonSignature @($trustedControl.tilePlacements))) "Ordinary-road control cell $controlCoordinate is unchanged."

$vmfDirectory = [IO.Path]::GetFullPath($VmfDirectory)
foreach ($cell in @($southRamp[0], $dualRamp[0])) {
    $vmfPath = Join-Path $vmfDirectory $cell.cellTemplateFilename
    if (-not (Test-Path -LiteralPath $vmfPath -PathType Leaf)) { throw "Generated review VMF is missing: $vmfPath" }
    $layoutPath = [IO.Path]::ChangeExtension($vmfPath, '.layout.json')
    if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) { throw "Generated layout metadata is missing: $layoutPath" }
    $layout = Get-Content -Raw -LiteralPath $layoutPath | ConvertFrom-Json
    Assert ($layout.vmfSha256 -ceq (Get-FileHash -LiteralPath $vmfPath -Algorithm SHA256).Hash.ToLowerInvariant()) "Review layout fingerprint matches $($cell.cellTemplateFilename)."

    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmfPath))
    $instances = @($tree.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'func_instance' })
    $roadInstances = @($instances | Where-Object { ([string]$_.Get('file')) -match '(?i)(?:^|[\\/])tile_road[^\\/]*\.vmf$' })
    Assert ($roadInstances.Count -gt 0) "Generated cell contains its planned ordinary road instances: $($cell.cellTemplateFilename)."
    foreach ($instance in $roadInstances) {
        $position = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
        Assert ((Test-GridAxis $position.X $tileSize) -and (Test-GridAxis $position.Y $tileSize)) "Serialized road instance stays on the 640-unit grid in $($cell.cellTemplateFilename)."
    }

    foreach ($placement in (Get-RoadTilePlacements $cell)) {
        $targetname = "zm_tile_$($placement.role)_$($placement.tileX)_$($placement.tileY)"
        $instance = Get-Instance $instances $targetname
        $position = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
        $expectedX = ([int]$placement.tileX - $center) * $tileSize
        $expectedY = ($center - [int]$placement.tileY) * $tileSize
        Assert ($position.X -eq $expectedX -and $position.Y -eq $expectedY) "Serialized core road instance matches slot $($placement.tileX),$($placement.tileY)."
        $angleParts = ([string]$instance.Get('angles')).Trim() -split '\s+'
        Assert ($angleParts.Count -eq 3 -and [int]$angleParts[1] -eq [int]$placement.rotationYaw) "Serialized core road yaw matches its existing grid mapping."
    }

    foreach ($assembly in (Get-RoadAssemblyPlacements $cell)) {
        $instance = Get-Instance $instances "zm_assembly_$($assembly.owner)"
        $position = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
        Assert ($position.X -eq [double]$assembly.origin.x -and $position.Y -eq [double]$assembly.origin.y) "Serialized ring road matches its planned grid origin."
    }
}

Write-Output "Motorway grid placements: $passed assertions passed; cells (22,18), (17,4), and ordinary-road control $controlCoordinate verified. VMFs: $($southRamp[0].cellTemplateFilename), $($dualRamp[0].cellTemplateFilename)."
