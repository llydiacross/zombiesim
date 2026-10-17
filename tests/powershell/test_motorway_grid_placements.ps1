param(
    [string]$PlanData = '',
    [string]$TrustedPlanData = '',
    [string]$VmfDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $PlanData = Join-Path $root 'generated\phase_j_preview_20261015\plan_grid_road_review.json'
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

Assert ($plan.cells.Count -eq $trustedPlan.cells.Count -and $plan.cells.Count -eq 576) 'The regenerated and trusted plans describe the same full preview.'
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

foreach ($cell in $plan.cells) {
    $coordinate = "$($cell.x),$($cell.y)"
    if (-not $trustedCellsByCoordinate.ContainsKey($coordinate)) { throw "Trusted plan has no cell $coordinate." }
    $trustedCell = $trustedCellsByCoordinate[$coordinate]
    if ($cell.topology -notlike 'motorway-*') {
        Assert ((Get-JsonSignature @($cell.tilePlacements)) -ceq (Get-JsonSignature @($trustedCell.tilePlacements))) "Non-motorway grid placements remain unchanged at $coordinate."
        continue
    }

    $contractProperty = $cell.PSObject.Properties['motorwayAssembly']
    if ($null -eq $contractProperty) { throw "Motorway cell $coordinate has no assembly contract." }
    $contract = $contractProperty.Value
    $trustedContract = $trustedCell.motorwayAssembly
    if ($contract.schemaVersion -eq 1) {
        Assert ((Get-JsonSignature @($cell.tilePlacements)) -ceq (Get-JsonSignature @($trustedCell.tilePlacements))) "Plain-straight grid slots remain unchanged at $coordinate."
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
        Assert (@($contract.ordinaryRoadApproaches).Count -eq 0 -and
            @($contract.ordinaryRoadPlacementShifts).Count -eq 0) "No measured road-mouth offsets remain at $coordinate."
        Assert (@($contract.connections | Where-Object route -eq 'road').Count -eq 0) "Road branches are not emitted as measured motorway assemblies at $coordinate."
        $roadAssemblyPlacements = @(Get-RoadAssemblyPlacements $cell)
        foreach ($assembly in $roadAssemblyPlacements) {
            Assert ([string]$assembly.owner -like 'grid_road/*' -and
                $assembly.disposition -eq 'five_by_five_640_grid') "Road continuation is owned by a grid slot at $coordinate."
            Assert ((Test-GridAxis ([double]$assembly.origin.x) $tileSize) -and
                (Test-GridAxis ([double]$assembly.origin.y) $tileSize)) "Road continuation origin uses the 640-unit grid at $coordinate."
        }
        $motorCoreLeaseSlots = @{}
        foreach ($lease in @($contract.leases | Where-Object ring -eq 'core')) { $motorCoreLeaseSlots["$($lease.tileX),$($lease.tileY)"] = $true }
        foreach ($placement in @(Get-RoadTilePlacements $cell | Where-Object role -eq 'onramp_road')) {
            Assert (-not $motorCoreLeaseSlots.ContainsKey("$($placement.tileX),$($placement.tileY)")) "On-ramp road no longer overlaps a leased 5x5 motorway slot at $coordinate."
        }

        $gridApproachesProperty = $contract.PSObject.Properties['gridRoadApproaches']
        if ($null -eq $gridApproachesProperty) { throw "Motorway cell $coordinate has no grid road approach records." }
        $roadGates = @($contract.gates | Where-Object route -eq 'road')
        Assert (@($gridApproachesProperty.Value).Count -eq $roadGates.Count) "Every ordinary-road gate has one grid-slot approach at $coordinate."
        foreach ($gate in $roadGates) {
            $approach = @($gridApproachesProperty.Value | Where-Object heading -eq $gate.direction)
            if ($approach.Count -ne 1) { throw "Expected one grid approach for $coordinate/$($gate.direction)." }
            $crossCoordinate = if ($gate.direction -in @('N', 'S')) { [double]$gate.x } else { [double]$gate.y }
            Assert ($crossCoordinate -eq [double]$approach[0].crossCoordinate) "Ordinary-road gate stays on its grid road axis at $coordinate/$($gate.direction)."

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

$nonMotorwayRoadControl = @($plan.cells | Where-Object {
    $_.topology -notlike 'motorway-*' -and @(Get-RoadTilePlacements $_).Count -gt 0
} | Select-Object -First 1)
if ($nonMotorwayRoadControl.Count -ne 1) { throw 'No ordinary-road control cell was found.' }
$controlCoordinate = "$($nonMotorwayRoadControl[0].x),$($nonMotorwayRoadControl[0].y)"
$trustedControl = $trustedCellsByCoordinate[$controlCoordinate]
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
