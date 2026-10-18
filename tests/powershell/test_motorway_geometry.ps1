Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$tileDirectory = Join-Path $testsRepoRoot 'tiletemplates'
Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force

$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway layout contracts: $Message" }
    $script:passed++
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    $rejected = $false
    try { & $Action } catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $rejected = $true
    }
    Assert $rejected "Invalid contract fails explicitly: $Pattern"
}

$pieces = @(
    @{ name = 'tile_motorway.vmf'; width = 3; height = 1 },
    @{ name = 'tile_motorway_road_bridge.vmf'; width = 3; height = 1 },
    @{ name = 'tile_motorway_ramp.vmf'; width = 3; height = 1 },
    @{ name = 'tile_motorway_corner_5x3.vmf'; width = 5; height = 3 },
    @{ name = 'tile_motorway_crossroads_3x3.vmf'; width = 3; height = 3 },
    @{ name = 'tile_motorway_tjunction_6x3.vmf'; width = 6; height = 3 },
    @{ name = 'tile_motorway_deadend_3x3.vmf'; width = 3; height = 3 },
    @{ name = 'tile_motorway_onramp_3x4.vmf'; width = 3; height = 4 },
    @{ name = 'tile_motorway_onramp_dual_3x4.vmf'; width = 3; height = 4 }
)
foreach ($piece in $pieces) {
    $footprint = Get-ZMMotorwayFootprint $piece.name
    Assert ($footprint.width -eq $piece.width -and $footprint.height -eq $piece.height) "$($piece.name) keeps its authored grid footprint."
    foreach ($yaw in @(0, 90, 180, 270)) {
        $reservation = Get-ZMMotorwayReservation $piece.name $yaw -1 -2 "owner:$($piece.name)"
        $width = if ($yaw -in @(90, 270)) { $piece.height } else { $piece.width }
        $height = if ($yaw -in @(90, 270)) { $piece.width } else { $piece.height }
        Assert ($reservation.width -eq $width -and $reservation.height -eq $height) "$($piece.name) swaps dimensions on quarter turns."
        Assert ($reservation.slots.Count -eq $width * $height) "$($piece.name) leases every occupied grid slot."
        Assert (@($reservation.slots | Where-Object emitsInstance).Count -eq 1) "$($piece.name) has exactly one emitting owner."
    }
}
Assert-Rejected { Get-ZMMotorwayFootprint 'tile_motorway_unknown_9x9.vmf' | Out-Null } 'Unsupported wide motorway template*'
Assert-Rejected { Get-ZMMotorwayFootprint 'roads\motorway_1x1\tile_motorway.vmf' | Out-Null } 'Expected a wide motorway VMF*'

$stripe = New-ZMStraightMotorwayStripe vertical 0
Assert ($stripe.owner.originCellLocal.x -eq 0 -and $stripe.owner.originCellLocal.y -eq 1280) 'The first vertical core stripe stays on the 640-unit grid.'
Assert ($stripe.placements.Count -eq 3 -and @($stripe.placements | Where-Object role -eq motorway_assembly).Count -eq 1) 'A stripe owns three slots and emits one instance.'

$recipe = [pscustomobject]@{
    topology = 'motorway-straight'; orientation = 'vertical'; transportFeature = 'none'
    cellTemplateFilename = 'straight.vmf'; tileGridSize = 5
    safeZoneEntrance = $null; waterBorderSides = @(); skyboxOceanSides = @(); landmarks = @()
    forceCarpark = $false; selectedChunkTemplate = ''; desiredChunkTemplate = ''; buildingTemplates = @()
    tilePlacements = @(foreach ($y in 0..4) {
        foreach ($x in 0..4) {
            [pscustomobject]@{ tileX = $x; tileY = $y; role = 'terrain'; template = 'terrain\tile_ground.vmf'; rotationYaw = 0 }
        }
    })
}
Set-ZMStraightMotorwayCellInspection $recipe $tileDirectory @{ straight = @{ vertical = 0; horizontal = 90 } }
$contract = $recipe.motorwayCellInspection | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$contract.status = 'normal_reservations_travel_pending'
$contract.assemblyAuthority = 'trusted_prior_approved_grid_layout'
$contract.gates = @(
    [pscustomobject]@{ direction = 'N'; lanes = @(@{}, @()) },
    [pscustomobject]@{ direction = 'S'; lanes = @(@{}, @()) }
)
$recipe.PSObject.Properties.Remove('motorwayCellInspection')
$recipe | Add-Member -NotePropertyName motorwayAssembly -NotePropertyValue $contract
$before = $recipe | ConvertTo-Json -Depth 40 -Compress
Assert ((Get-ZMNormalStraightMotorwayContract $recipe).gates.Count -eq 2) 'Straight gates come from the approved trusted plan.'
Assert (($recipe | ConvertTo-Json -Depth 40 -Compress) -ceq $before) 'Trusted contract access does not mutate the recipe.'

$border = @(foreach ($y in -1..5) { foreach ($x in -1..5) {
    if ($x -in @(-1, 5) -or $y -in @(-1, 5)) {
        [pscustomobject]@{ tileX = $x; tileY = $y; template = "border_$x,$y"; rotationYaw = 270 }
    }
} })
$outer = @(foreach ($y in -2..6) { foreach ($x in -2..6) {
    if ($x -in @(-2, 6) -or $y -in @(-2, 6)) {
        [pscustomobject]@{ tileX = $x; tileY = $y; template = "outer_$x,$y"; rotationYaw = 180 }
    }
} })
$rings = Resolve-ZMNormalStraightMotorwayRings $recipe $border $outer
Assert ($rings.borderPlacements.Count -eq 20 -and $rings.outerPlacements.Count -eq 28) 'Trusted ring leases replace only reserved boundary slots.'
Assert (@($rings.borderPlacements | Where-Object template -like 'border_*').Count -eq 18 -and
    @($rings.outerPlacements | Where-Object template -like 'outer_*').Count -eq 26) 'Unleased neighboring walls and corners stay in place.'

$untrusted = $recipe | ConvertTo-Json -Depth 40 | ConvertFrom-Json
$untrusted.motorwayAssembly.PSObject.Properties.Remove('assemblyAuthority')
Assert-Rejected { Get-ZMNormalStraightMotorwayContract $untrusted | Out-Null } '*trusted gate/lease contract*'

$complexGates = @(
    [pscustomobject]@{ direction = 'N'; route = 'motorway'; lanes = @(@{}, @()) },
    [pscustomobject]@{ direction = 'E'; route = 'road'; lanes = @(@{}) }
)
$complex = [pscustomobject]@{
    schemaVersion = 2; status = 'normal_complex_travel_pending'
    assemblyAuthority = 'trusted_prior_approved_grid_layout'; gates = $complexGates
}
Assert ((Get-ZMComplexMotorwayGates $complex | ConvertTo-Json -Depth 10 -Compress) -ceq
    ($complexGates | ConvertTo-Json -Depth 10 -Compress)) 'Complex gate records are returned unchanged from the trusted plan.'
Assert ((Get-ZMComplexMotorwayContract ([pscustomobject]@{ motorwayAssembly = $complex })) -eq $complex) 'Only normal assembly contracts are exposed.'

$untrustedComplex = $complex | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$untrustedComplex.PSObject.Properties.Remove('assemblyAuthority')
Assert-Rejected { Get-ZMComplexMotorwayGates $untrustedComplex | Out-Null } '*trusted approved grid contract*'
$duplicateDirection = $complex | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$duplicateDirection.gates[1].direction = 'N'
Assert-Rejected { Get-ZMComplexMotorwayGates $duplicateDirection | Out-Null } '*invalid or duplicate gate directions*'

Write-Output "Motorway layout contracts: $passed assertions passed; trusted gates are consumed without mouth geometry."
