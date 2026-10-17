Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway geometry: $Message" }
    $script:passed++
}
$pieces = @(
    @('tile_motorway.vmf', 3, 1),
    @('tile_motorway_road_bridge.vmf', 3, 1),
    @('tile_motorway_ramp.vmf', 3, 1),
    @('tile_motorway_corner_5x3.vmf', 5, 3),
    @('tile_motorway_crossroads_3x3.vmf', 3, 3),
    @('tile_motorway_tjunction_6x3.vmf', 6, 3),
    @('tile_motorway_deadend_3x3.vmf', 3, 3),
    @('tile_motorway_onramp_3x4.vmf', 3, 4),
    @('tile_motorway_onramp_dual_3x4.vmf', 3, 4)
)
foreach ($piece in $pieces) {
    foreach ($yaw in @(0, 90, 180, 270)) {
        $r = Get-ZMMotorwayReservation $piece[0] $yaw -1 -2 "owner:$($piece[0])"
        $width = if ($yaw -in @(90, 270)) { $piece[2] } else { $piece[1] }
        $height = if ($yaw -in @(90, 270)) { $piece[1] } else { $piece[2] }
        Assert ($r.width -eq $width -and $r.height -eq $height) 'Quarter turns swap rectangular dimensions without clamping.'
        Assert ($r.authoredWidth -eq $piece[1] -and $r.authoredHeight -eq $piece[2]) 'Authored dimensions are preserved.'
        Assert ($r.slots.Count -eq $width * $height) 'Every nominal occupied slot is reserved.'
        Assert (@($r.slots | Where-Object emitsInstance).Count -eq 1) 'Exactly one emitting owner per reservation.'
        Assert (@($r.slots | Where-Object owner -ne $r.owner).Count -eq 0) 'All records retain one assembly owner.'
        Assert (@($r.slots | Group-Object tileX,tileY | Where-Object Count -ne 1).Count -eq 0) 'Slot coordinates are unique.'
        Assert ($r.originOffset.x -eq ($width - 1) * 320 -and $r.originOffset.y -eq -($height - 1) * 320) 'Logical south increases while physical Y decreases.'
        foreach ($slot in $r.slots) {
            Assert ($slot.tileX -ge -1 -and $slot.tileX -lt -1 + $width -and $slot.tileY -ge -2 -and $slot.tileY -lt -2 + $height) 'No occupied slot lies outside nominal reservation.'
        }
    }
}
$crossroads = Get-ZMMotorwayReservation 'tile_motorway_crossroads_3x3.vmf' 0 3 3 'crossroads'
Assert ($crossroads.centerTileX -eq 4 -and $crossroads.centerTileY -eq 4 -and $crossroads.originOffset.x -eq 640 -and $crossroads.originOffset.y -eq -640) '3x3 crossroads stays centered in the cell on whole-tile slots.'
$rampPiece = Get-ZMMotorwayReservation 'tile_motorway_ramp.vmf' 0 3 2 'motorway-ramp'
Assert ($rampPiece.width -eq 3 -and $rampPiece.height -eq 1 -and $rampPiece.centerTileX -eq 4 -and $rampPiece.centerTileY -eq 2) 'Motorway ramp occupies one 3x1 slot with north as its authored raised side.'
$ramp = Get-ZMMotorwayReservation 'tile_motorway_onramp_3x4.vmf' 90 0 0 'ramp'
Assert ($ramp.centerTileX -eq 1.5 -and $ramp.centerTileY -eq 1) 'Rotated even-height ramp retains half-tile alignment.'
$point = [pscustomobject]@{ x = -512; y = 320; z = 68 }
$expected = @(@(-512, 320), @(-320, -512), @(512, -320), @(320, 512))
$index = 0
foreach ($yaw in @(0, 90, 180, 270)) {
    $rotated = Convert-ZMMotorwayPoint $point $yaw
    Assert ($rotated.x -eq $expected[$index][0] -and $rotated.y -eq $expected[$index][1] -and $rotated.z -eq 68) 'Physical Source yaw, not logical clockwise rotation.'
    $restored = Convert-ZMMotorwayPoint $rotated ((360 - $yaw) % 360)
    Assert ($restored.x -eq $point.x -and $restored.y -eq $point.y -and $restored.z -eq $point.z) 'Inverse transform restores source port coordinates exactly.'
    $index++
}
$envelope = [pscustomobject]@{ x = [pscustomobject]@{ min = -1120; max = 1120 }; y = [pscustomobject]@{ min = -960; max = 992 }; z = [pscustomobject]@{ min = -225.328; max = 480 } }
$turned = Convert-ZMMotorwayEnvelope $envelope 90
Assert ($turned.x.min -eq -992 -and $turned.x.max -eq 960 -and $turned.y.min -eq -1120 -and $turned.y.max -eq 1120) 'Overhang envelope is rotated separately, not clipped to named footprint.'
Assert ($turned.z.min -eq -225.328 -and $turned.z.max -eq 480) 'Underlay and height envelope remain unchanged.'
$rejected = $false
try { Get-ZMMotorwayFootprint 'tile_motorway_unknown_9x9.vmf' | Out-Null } catch {
    if ($_.Exception.Message -notlike 'Unsupported wide motorway template*') { throw }
    $rejected = $true
}
Assert $rejected 'Unsupported assemblies fail explicitly.'
$rejected = $false
try { Get-ZMMotorwayFootprint 'roads\motorway_1x1\tile_motorway.vmf' | Out-Null } catch {
    if ($_.Exception.Message -notlike 'Expected a wide motorway VMF*') { throw }
    $rejected = $true
}
Assert $rejected 'Legacy same-name straight cannot receive a wide footprint.'

$profile = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$plannerSettings = $profile.Settings.cellPlanning
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'plan_cell_templates.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'Existing planner parses.'
$definition = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-LayoutRotation'
}, $false))
Assert ($definition.Count -eq 1) 'Use the exact existing orientation owner.'
. ([scriptblock]::Create($definition[0].Extent.Text))
foreach ($case in @(
    @('motorway-straight', 'vertical', 0), @('motorway-straight', 'horizontal', 90),
    @('motorway-corner', 'north-east', 90), @('motorway-corner', 'east-south', 0),
    @('motorway-corner', 'south-west', 270), @('motorway-corner', 'north-west', 180),
    @('motorway-tjunction', 'missing-south', 0), @('motorway-tjunction', 'missing-east', 90),
    @('motorway-tjunction', 'missing-north', 180), @('motorway-tjunction', 'missing-west', 270),
    @('motorway-deadend', 'south', 0), @('motorway-deadend', 'east', 90),
    @('motorway-deadend', 'north', 180), @('motorway-deadend', 'west', 270)
)) {
    Assert ((Get-LayoutRotation $case[0] $case[1]) -eq $case[2]) 'Existing 1x1 canonical yaw mapping is preserved, not inferred from bounds.'
}
$root = $testsRepoRoot
$MotorwayCellInspection = $true
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'build_cell_vmfs.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'Builder parses.'
foreach ($name in @('Get-PlacementFootprint', 'Test-PlacementEmitsInstance', 'New-PlacementInstanceLines', 'Get-PlacementId', 'Get-PlacementCoordinates', 'Get-PlacementOwnerCoordinate', 'Test-RecipeTilePlacements', 'Get-TransitionGatePlacements', 'Set-CellPlayerStart')) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false))
    Assert ($definition.Count -eq 1) "Use the production builder definition of $name."
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$exportAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'export_runtime_world_data.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'Runtime exporter parses.'
$definition = @($exportAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-RuntimeMotorwayGates'
}, $false))
Assert ($definition.Count -eq 1) 'Use the production runtime motorway exporter.'
. ([scriptblock]::Create($definition[0].Extent.Text))
Assert (@(Get-RuntimeMotorwayGates ([pscustomobject]@{}) (Join-Path $root 'tiletemplates')).Count -eq 0) 'Legacy export does not fabricate measured motorway metadata.'
$mainCase = [pscustomobject]@{
    id = 'main'; piece = 'deadend.vmf'; yaw = 180
    origin = [pscustomobject]@{ x = 100; y = 200; z = 0 }
    instances = @(
        [pscustomobject]@{ owner = 'main/main'; template = 'deadend.vmf'; yaw = 180; origin = [pscustomobject]@{ x = 100; y = 200; z = 0 } },
        [pscustomobject]@{ owner = 'main/N/continuation'; template = 'straight.vmf'; yaw = 0; origin = [pscustomobject]@{ x = 100; y = 1480; z = 0 } }
    )
    connections = @([pscustomobject]@{ route = 'motorway'; ports = @(
        [pscustomobject]@{ outward = 'N'; width = 416; grade = 0; position = [pscustomobject]@{ x = -428; y = 1160; z = 68 } },
        [pscustomobject]@{ outward = 'N'; width = 416; grade = 0; position = [pscustomobject]@{ x = 612; y = 1160; z = 68 } }
    ) })
}
$transportCase = [pscustomobject]@{
    id = 'transport'; piece = 'tile_motorway_onramp_3x4.vmf'; yaw = 270
    origin = [pscustomobject]@{ x = -10000; y = 0; z = 0 }
    instances = @(
        [pscustomobject]@{ owner = 'transport/main'; template = 'tile_motorway_onramp_3x4.vmf'; yaw = 270; origin = [pscustomobject]@{ x = -10000; y = 0; z = 0 } },
        [pscustomobject]@{ owner = 'transport/N/continuation'; template = 'straight.vmf'; yaw = 0; origin = [pscustomobject]@{ x = -10000; y = 1280; z = 0 } },
        [pscustomobject]@{ owner = 'transport/S/continuation'; template = 'straight.vmf'; yaw = 0; origin = [pscustomobject]@{ x = -10000; y = -1280; z = 0 } }
    )
    connections = @(
        foreach ($heading in @('N', 'S')) {
            [pscustomobject]@{ route = 'motorway'; ports = @(
                foreach ($x in @(-10208, -9168)) {
                    [pscustomobject]@{ outward = $heading; width = 416; grade = 0; position = [pscustomobject]@{ x = $x; y = $(if ($heading -eq 'N') { 960 } else { -960 }); z = 68 } }
                }
            ) }
        }
        [pscustomobject]@{ route = 'road'; ports = @([pscustomobject]@{ outward = 'E'; width = 256; grade = -0.583333; position = [pscustomobject]@{ x = -8720; y = -384; z = 80 } }) }
    )
}
$beforeMixed = @($mainCase, $transportCase) | ConvertTo-Json -Depth 40 -Compress
$joined = Join-ZMMotorwayAssemblyCases $mainCase $transportCase
Assert ($joined.insertionSeam.status -eq 'exact_floor_seam' -and $joined.insertionSeam.translation.x -eq -320 -and $joined.insertionSeam.translation.y -eq 1920 -and $joined.insertionSeam.translation.z -eq 0) 'Mixed insertion uses the two source mouths, not tile-centre placement or a vertical correction.'
Assert ((($joined.connections | ForEach-Object { $_.ports[0].outward } | Sort-Object) -join ',') -eq 'E,N') 'Mixed assembly retains motorway and ramp routes without exposing the swallowed incoming leg.'
Assert ($joined.instances.Count -eq 3 -and @($joined.instances | Where-Object owner -like '*/S/continuation').Count -eq 0) 'Insertion displaces only the two internal continuations, retaining both authored main pieces.'
Assert (($joined.connections | Where-Object route -eq road).approachKind -eq 'onramp') 'Mixed ramp approach is resolved from its transport source, not the deadend/corner main source.'
Assert ((@($mainCase, $transportCase) | ConvertTo-Json -Depth 40 -Compress) -ceq $beforeMixed) 'Mixed solver leaves both approved source assembly records unchanged.'
$bridgeMain = $mainCase | ConvertTo-Json -Depth 40 | ConvertFrom-Json
$bridgeMain.piece = 'tile_motorway_deadend_3x3.vmf'
$bridgeCase = $transportCase | ConvertTo-Json -Depth 40 | ConvertFrom-Json
$bridgeCase.piece = 'tile_motorway_road_bridge.vmf'
$bridgeCase.yaw = 0
foreach ($connection in $bridgeCase.connections) {
    if ($connection.route -eq 'motorway') {
        for ($lane = 0; $lane -lt 2; $lane++) {
            $connection.ports[$lane].position.x = -10000 + $(if ($lane -eq 0) { -512 } else { 528 })
            $connection.ports[$lane].position.y = $(if ($connection.ports[$lane].outward -eq 'N') { 320 } else { -320 })
        }
    } else {
        $connection.ports[0].position.x = -9040
        $connection.ports[0].position.y = 0
        $connection.ports[0].position.z = 196.057
        $connection.ports[0].grade = 0
    }
}
foreach ($heading in @('N', 'S')) {
    $deadend = $bridgeMain | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    if ($heading -eq 'S') {
        $deadend.yaw = 0
        $deadend.instances[0].yaw = 0
        $deadend.instances[1].owner = 'main/S/continuation'
        for ($lane = 0; $lane -lt 2; $lane++) {
            $deadend.connections[0].ports[$lane].outward = 'S'
            $deadend.connections[0].ports[$lane].position.x = 100 + $(if ($lane -eq 0) { -512 } else { 528 })
            $deadend.connections[0].ports[$lane].position.y = -760
        }
    }
    $beforeBridge = @($deadend, $bridgeCase) | ConvertTo-Json -Depth 40 -Compress
    $bridgeJoined = Join-ZMMotorwayAssemblyCases $deadend $bridgeCase
    $bridgeOwner = @($bridgeJoined.instances | Where-Object owner -like '*/transport')
    Assert ($bridgeJoined.insertionSeam.dominantOwner -eq 'bridge' -and $bridgeOwner.Count -eq 1 -and
        $bridgeOwner[0].origin.x -eq 0 -and $bridgeOwner[0].origin.y -eq 0 -and $bridgeOwner[0].origin.z -eq 0) "$heading deadend bridge owns the exact cell centre."
    Assert ($bridgeJoined.instances[0].origin.y -eq $(if ($heading -eq 'S') { 1280 } else { -1280 }) -and
        $bridgeJoined.instances[0].origin.x -eq $(if ($heading -eq 'S') { 0 } else { 16 })) "$heading deadend adjusts around the centred bridge using its measured asymmetric mouths."
    Assert ($bridgeJoined.insertionSeam.status -eq 'exact_floor_seam' -and
        @($bridgeJoined.insertionSeam.residuals | Where-Object { $_.dx -ne 0 -or $_.dy -ne 0 -or $_.dz -ne 0 -or $_.widthDelta -ne 0 -or $_.gradeDelta -ne 0 }).Count -eq 0) "$heading bridge dominance preserves both exact floor joins."
    Assert (@($bridgeJoined.connections | Where-Object { $_.route -eq 'road' -and $_.ports[0].position.y -ne 0 }).Count -eq 0) "$heading bridge ordinary road stays on the cell centreline."
    Assert ((@($deadend, $bridgeCase) | ConvertTo-Json -Depth 40 -Compress) -ceq $beforeBridge) "$heading bridge priority never modifies authored assembly input records."
}
Assert ($joined.insertionSeam.dominantOwner -eq 'topology' -and $joined.instances[0].origin.x -eq 0 -and $joined.instances[0].origin.y -eq 0) 'Deadend/on-ramp retains its prior topology anchor; bridge priority does not affect ramps.'
foreach ($heading in @('S', 'E', 'N', 'W')) {
    $yaw = @{ S = 0; E = 90; N = 180; W = 270 }[$heading]
    foreach ($cross in @(-1408, 1408)) {
        foreach ($depth in @(-1920, -1280)) {
            $origin = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $cross; y = $depth; z = 0 }) $yaw
            $beforeApproach = $origin | ConvertTo-Json -Compress
            $approach = New-ZMCentredRoadApproach $origin $heading 'test/road' (Join-Path $root 'tiletemplates')
            $boundary = Convert-ZMMotorwayPoint $approach.boundaryPort.position ((360 - $yaw) % 360)
            Assert ($approach.entryAxis -eq 0 -and $approach.boundaryPort.outward -eq $heading -and
                $boundary.x -eq 0 -and $boundary.y -eq -2880 -and $boundary.z -eq 36) "$heading dogleg reaches the true central side-entry origin, never the offset ramp axis."
            Assert (@($approach.instances | Where-Object template -eq 'roads\tile_road_corner.vmf').Count -eq 2 -and
                @($approach.instances | Where-Object template -eq 'roads\connectors\tile_road_straight_768.vmf').Count -eq 1) "$heading dogleg uses the approved corner, extended straight, corner chain."
            Assert ($approach.instances.Count -eq $(if ($depth -eq -1920) { 3 } else { 4 })) "$heading dogleg retains only necessary centred boundary straights."
            Assert (@($approach.joins | Where-Object { $_.status -ne 'exact_floor_seam' -or $_.width -ne 256 -or $_.position.z -ne 36 }).Count -eq 0 -and
                $approach.joins.Count -eq $(if ($depth -eq -1920) { 3 } else { 4 })) "$heading all authored ordinary-road floor mouths match exactly, including the unchanged ramp approach."
            Assert (($origin | ConvertTo-Json -Compress) -ceq $beforeApproach) "$heading routing never shifts the retained ramp origin."
        }
    }
}
$rejected = $false
try {
    New-ZMCentredRoadApproach ([pscustomobject]@{ x = 1280; y = -1920; z = 0 }) S test (Join-Path $root 'tiletemplates') | Out-Null
} catch {
    if ($_.Exception.Message -notlike 'Centred mixed road requires*') { throw }
    $rejected = $true
}
Assert $rejected 'Unapproved connector offsets fail explicitly rather than moving a gate or scaling a generated instance.'
$borderControl = @(
    [pscustomobject]@{ tileX = 2; tileY = 5; template = 'roads/tile_road.vmf'; rotationYaw = 0; targetname = 'zm_transition_road_S' },
    [pscustomobject]@{ tileX = 5; tileY = 2; template = 'roads/tile_road.vmf'; rotationYaw = 90; targetname = 'zm_transition_road_E' },
    [pscustomobject]@{ tileX = 1; tileY = 5; template = 'decorations/tile_bushes_1aa.vmf'; rotationYaw = 90; targetname = 'zm_border_S_1' }
)
$beforeBorder = $borderControl | ConvertTo-Json -Compress
$roadRecipe = [pscustomobject]@{
    tilePlacements = @([pscustomobject]@{ role = 'terrain'; template = 'terrain/tile_grass.vmf' })
    motorwayCellInspection = [pscustomobject]@{ schemaVersion = 2; ordinaryRoadApproaches = @([pscustomobject]@{ heading = 'S' }) }
}
$cleanedBorder = @(Resolve-ZMCentredRoadBorderPlacements $roadRecipe $borderControl)
Assert ($cleanedBorder.Count -eq 3 -and $cleanedBorder[0].template -eq 'terrain/tile_grass.vmf' -and
    $cleanedBorder[0].tileX -eq 2 -and $cleanedBorder[0].tileY -eq 5 -and $cleanedBorder[0].rotationYaw -eq 0 -and
    $cleanedBorder[0].targetname -eq 'zm_border_road_terrain_S') 'The obsolete straight beside the south corner route is replaced with planned terrain in exactly its old slot, retaining the builder border ownership prefix.'
Assert (($cleanedBorder[1..2] | ConvertTo-Json -Compress) -ceq ($borderControl[1..2] | ConvertTo-Json -Compress)) 'Cleanup preserves neighbouring scenery and every unrelated road side.'
Assert (($borderControl | ConvertTo-Json -Compress) -ceq $beforeBorder) 'Cleanup never mutates source border records.'
Assert ((@(Resolve-ZMCentredRoadBorderPlacements ([pscustomobject]@{}) $borderControl) | ConvertTo-Json -Compress) -ceq $beforeBorder) 'Legacy and previously approved nonmixed layouts keep all border roads.'
$unequal = $mainCase | ConvertTo-Json -Depth 40 | ConvertFrom-Json
$unequal.connections[0].ports[1].width = 380
$diagnostic = Join-ZMMotorwayAssemblyCases $unequal $transportCase
Assert ($diagnostic.insertionSeam.status -eq 'diagnostic_seam_not_approved' -and $diagnostic.insertionSeam.residuals[1].widthDelta -eq -36) 'Nonmatching source lanes stay an explicit diagnostic, never success-shaped approval.'
$unequal.connections[0].ports[0].position.z += 1
$rejected = $false
try { Join-ZMMotorwayAssemblyCases $unequal $transportCase | Out-Null } catch {
    if ($_.Exception.Message -notlike 'Mixed motorway insertion cannot vertically shift*') { throw }
    $rejected = $true
}
Assert $rejected 'Mixed assembly rejects authored-deck correction.'
$spawnRecipe = [pscustomobject]@{
    tilePlacements = @(); cellTemplateFilename = 'mixed.vmf'
    motorwayCellInspection = [pscustomobject]@{ schemaVersion = 2; status = 'complex_cell_diagnostic_not_live_travel'; insertionSeam = $joined.insertionSeam }
}
$spawnVmf = '"classname" "info_player_start"' + "`n" + '"origin" "0 0 33.0001"'
$culture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $spawnOutput = Set-CellPlayerStart $spawnVmf $spawnRecipe 5 640
    Assert ($spawnOutput.Contains('"origin" "-528 832 101.0001"')) 'Measured mixed spawn retains base-cell terrain-floor clearance above the actual deck, with invariant coordinates.'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $culture }
$legacySpawn = [pscustomobject]@{ cellTemplateFilename = 'legacy.vmf'; tilePlacements = @([pscustomobject]@{ role = 'terrain'; tileX = 2; tileY = 2 }) }
Assert ((Set-CellPlayerStart $spawnVmf $legacySpawn 5 640) -ceq $spawnVmf) 'Ordinary terrain spawn remains byte-identical.'
$MotorwayCellInspection = $false
$rejected = $false
try { Set-CellPlayerStart $spawnVmf $spawnRecipe 5 640 | Out-Null } catch {
    if ($_.Exception.Message -notlike 'Measured motorway spawn candidate is limited*') { throw }
    $rejected = $true
}
Assert $rejected 'Inspection spawn candidates cannot bypass normal-world integration guards.'
$MotorwayCellInspection = $true
foreach ($orientation in @('vertical', 'horizontal')) {
    $recipe = [pscustomobject]@{
        topology = 'motorway-straight'; orientation = $orientation; transportFeature = 'none'
        cellTemplateFilename = 'fixture.vmf'
        tileGridSize = 5; safeZoneEntrance = $null; waterBorderSides = @(); skyboxOceanSides = @()
        landmarks = @(); forceCarpark = $false; selectedChunkTemplate = ''; desiredChunkTemplate = ''
        buildingTemplates = @()
        tilePlacements = @(foreach ($y in 0..4) {
            foreach ($x in 0..4) {
                [pscustomobject]@{ tileX = $x; tileY = $y; role = 'terrain'; template = 'terrain\tile_ground.vmf'; rotationYaw = 0 }
            }
        })
    }
    Set-ZMStraightMotorwayCellInspection $recipe (Join-Path $root 'tiletemplates') @{ straight = @{ vertical = 0; horizontal = 90 } }
    Test-RecipeTilePlacements $recipe 5
    Assert $true 'Shared stripe records satisfy the actual builder ownership and repeated-footprint contract.'
    $leases = Assert-ZMStraightMotorwayCellContract $recipe
    Assert ($leases.Count -eq 27) 'Straight core/border/outer corridor has exactly27 leased slots.'
    $owners = @($recipe.tilePlacements | Where-Object role -eq motorway_assembly) + @($recipe.motorwayCellInspection.ringPlacements)
    foreach ($owner in $owners) {
        $along = [int]($owner.placementId -replace '^motorway:', '')
        Assert ($owner.originCellLocal.x -eq $(if ($orientation -eq 'vertical') { 0 } else { ($along - 2) * 640 }) -and
            $owner.originCellLocal.y -eq $(if ($orientation -eq 'vertical') { (2 - $along) * 640 } else { 0 })) 'Each owner retains its exact approved physical origin through both rings.'
        Assert (@($leases.Values | Where-Object owner -eq $owner.placementId).Count -eq 3) 'Each emitting straight owns its full three-wide opening.'
        $before = $owner | ConvertTo-Json -Depth 10
        foreach ($interior in @($false, $true)) {
            $lines = @(New-PlacementInstanceLines $owner 5 640 0 101 'fixture-motorway.vmf' 'fixture-owner' -Interior:$interior)
            Assert ($lines.Count -eq 10 -and $lines[0] -ceq 'entity' -and $lines[3] -ceq '    "classname" "func_instance"') 'Writer emits exactly one func_instance entity.'
            Assert ($lines[4] -ceq ('    "origin" "{0} {1} 0"' -f $owner.originCellLocal.x, $owner.originCellLocal.y)) 'Core and ring emission retain the explicit cell-local origin.'
            Assert ($lines[5] -ceq ('    "angles" "0 {0} 0"' -f $owner.rotationYaw) -and
                $lines[2] -ceq '    "id" "101"' -and $lines[6] -ceq '    "file" "fixture-motorway.vmf"' -and
                $lines[7] -ceq '    "targetname" "fixture-owner"' -and $lines[8] -ceq '    "fixup_style" "0"') 'Writer preserves ID, yaw, path, targetname and fixup ownership.'
        }
        Assert (($owner | ConvertTo-Json -Depth 10) -ceq $before) 'VMF emission leaves the placement unchanged.'
    }
    $serialized = $recipe | ConvertTo-Json -Depth 30
    $mutations = @(
        @{ name = 'wrong core origin'; change = { param($r) ($r.tilePlacements | Where-Object role -eq motorway_assembly | Select-Object -First 1).originCellLocal.x += 1 }; error = 'Motorway physical origin differs*' },
        @{ name = 'nonfinite origin'; change = { param($r) $r.motorwayCellInspection.ringPlacements[0].originCellLocal.z = [double]::NaN }; error = 'Motorway point has non-finite*' },
        @{ name = 'wrong ring origin'; change = { param($r) $r.motorwayCellInspection.ringPlacements[0].originCellLocal.y += 640 }; error = 'Motorway physical origin differs*' },
        @{ name = 'duplicate emitter'; change = { param($r) $r.motorwayCellInspection.ringPlacements[1].placementId = $r.motorwayCellInspection.ringPlacements[0].placementId }; error = 'Duplicate motorway emitting owner*' },
        @{ name = 'missing boundary lease'; change = { param($r) $r.motorwayCellInspection.leases[0].tileX = 99 }; error = 'Invalid or missing wide motorway lease*' },
        @{ name = 'wrong ring'; change = { param($r) $r.motorwayCellInspection.ringPlacements[0].ring = 'core' }; error = 'Invalid motorway emitting geometry*' },
        @{ name = 'wrong ring dimensions'; change = { param($r) $r.motorwayCellInspection.ringPlacements[0].footprintWidth += 1 }; error = 'Invalid motorway emitting geometry*' },
        @{ name = 'wrong yaw'; change = { param($r) $r.motorwayCellInspection.yaw = 180 }; error = 'Invalid straight motorway orientation*' },
        @{ name = 'ocean omission'; change = { param($r) $r.skyboxOceanSides = @('W') }; error = 'Invalid straight motorway orientation*' },
        @{ name = 'authored water border'; change = { param($r) $r.waterBorderSides = @('E') }; error = 'Invalid straight motorway orientation*' },
        @{ name = 'den entrance'; change = { param($r) $r.safeZoneEntrance = [pscustomobject]@{ slot = 'N' } }; error = 'Invalid straight motorway orientation*' },
        @{ name = 'wrong suppressed owner'; change = { param($r) ($r.tilePlacements | Where-Object role -eq motorway_occupied | Select-Object -First 1).placementId = 'other' }; error = 'Invalid motorway core ownership*' },
        @{ name = 'suppressed slot emits'; change = { param($r) ($r.tilePlacements | Where-Object role -eq motorway_occupied | Select-Object -First 1).emitsInstance = $true }; error = 'Invalid motorway core ownership*' },
        @{ name = 'duplicate core slot'; change = { param($r) $r.tilePlacements[1].tileX = $r.tilePlacements[0].tileX; $r.tilePlacements[1].tileY = $r.tilePlacements[0].tileY }; error = 'Invalid or duplicate motorway core slot*' }
    )
    foreach ($case in $mutations) {
        $corrupt = $serialized | ConvertFrom-Json
        & $case.change $corrupt
        $before = $corrupt | ConvertTo-Json -Depth 30
        $rejected = $false
        try { Assert-ZMStraightMotorwayCellContract $corrupt | Out-Null } catch {
            if ($_.Exception.Message -notlike $case.error) { throw }
            $rejected = $true
        }
        Assert $rejected "Reject $($case.name) before any ring replacement."
        Assert (($corrupt | ConvertTo-Json -Depth 30) -ceq $before) 'Contract validation never mutates input.'
    }
    Assert (($recipe | ConvertTo-Json -Depth 30) -ceq $serialized) 'Valid contract leaves source recipe unchanged.'
    $normal = $serialized | ConvertFrom-Json
    $normal.PSObject.Properties.Remove('motorwayCellInspection')
    $before = $normal | ConvertTo-Json -Depth 30
    $contract = New-ZMNormalStraightMotorwayContract $normal (Join-Path $root 'tiletemplates')
    Assert (($normal | ConvertTo-Json -Depth 30) -ceq $before) 'Normal ring planning is read-only and never tags a recipe as inspection.'
    Assert ($contract.status -ceq 'normal_reservations_travel_pending' -and $contract.leases.Count -eq 27 -and $contract.ringPlacements.Count -eq 4) 'Normal plan explicitly retains travel-pending status and full core/ring leases.'
    Assert (($contract.ringPlacements | ConvertTo-Json -Depth 10 -Compress) -ceq ($recipe.motorwayCellInspection.ringPlacements | ConvertTo-Json -Depth 10 -Compress)) 'Normal rings exactly match the approved inspection instances.'
    Assert (($contract.leases | ConvertTo-Json -Depth 10 -Compress) -ceq ($recipe.motorwayCellInspection.leases | ConvertTo-Json -Depth 10 -Compress)) 'Normal reservations displace exactly the approved27 core/border/outer slots.'
    Assert ($contract.gates.Count -eq 2) 'Normal straight plan owns exactly two source-measured boundary gates.'
    foreach ($gate in $contract.gates) {
        $flipped = $gate.direction -in @('S', 'E')
        Assert ($gate.lanes.Count -eq 2 -and $gate.arrivalLane -eq 1) 'Each gate retains two carriageways and the negative-right arrival lane.'
        Assert ($gate.lanes[0].lateral -eq $(if ($flipped) { -528 } else { -512 }) -and
            $gate.lanes[1].lateral -eq $(if ($flipped) { 512 } else { 528 })) 'Measured asymmetric lane centres survive all four cardinal transforms.'
        Assert ($gate.deckZ -eq 68 -and @($gate.lanes | Where-Object { $_.deckZ -ne 68 -or $_.width -ne 416 }).Count -eq 0) 'Both source carriageways are416 units wide at deck68.'
        Assert ($gate.lateralMin -eq $(if ($flipped) { -736 } else { -720 }) -and
            $gate.lateralMax -eq $(if ($flipped) { 720 } else { 736 })) 'Gate opening comes from actual lane extents, not centred nominal footprint.'
        $forward = @{ N = @(0, 1); E = @(1, 0); S = @(0, -1); W = @(-1, 0) }[$gate.direction]
        $right = @($forward[1], -$forward[0])
        foreach ($lane in $gate.lanes) {
            Assert ($lane.arrowX * $forward[0] + $lane.arrowY * $forward[1] -eq 1952 -and
                $lane.arrivalX * $forward[0] + $lane.arrivalY * $forward[1] -eq 1824) 'Arrows remain256 inward of the gate and arrival384 inward behind them.'
            Assert ($lane.arrowX * $right[0] + $lane.arrowY * $right[1] -eq $lane.lateral -and
                $lane.arrivalX * $right[0] + $lane.arrivalY * $right[1] -eq $lane.lateral) 'Arrow and arrival stay at measured carriageway centres.'
        }
    }
    $mouths = Get-ZMStraightMotorwayMouths (Join-Path (Join-Path $root 'tiletemplates') $contract.template)
    $invalidContract = $contract | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    @($invalidContract.ringPlacements | Where-Object ring -eq border)[0].originCellLocal.z = 1
    $rejected = $false
    try { Get-ZMNormalStraightMotorwayGates $invalidContract $mouths | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Measured motorway gate border origin differs*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Gate measurement rejects an unauthorized vertical shift of its ring owner.'
    foreach ($case in @(
        @{ change = { param($m) $m.sha256 = 'stale' }; error = 'Measured straight gates require*' },
        @{ change = { param($m) $m.mouths[0].lanes[0].grade = 0.1 }; error = 'Straight motorway gate requires*' },
        @{ change = { param($m) $m.mouths[0].lanes[0].position.y += 1 }; error = 'Measured motorway carriageway does not meet*' },
        @{ change = { param($m) $m.mouths[0].lanes[0].position.z += 1 }; error = 'Measured motorway carriageways must straddle*' }
    )) {
        $invalid = $mouths | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        & $case.change $invalid
        $beforeMeasurement = $invalid | ConvertTo-Json -Depth 30
        $rejected = $false
        try { Get-ZMNormalStraightMotorwayGates $contract $invalid | Out-Null } catch {
            if ($_.Exception.Message -notlike $case.error) { throw }
            $rejected = $true
        }
        Assert $rejected 'Invalid source-deck/boundary contracts fail without a success-shaped gate fallback.'
        Assert (($invalid | ConvertTo-Json -Depth 30) -ceq $beforeMeasurement) 'Gate derivation never mutates measured input.'
    }
    Import-Module (Join-Path $testsBinDirectory 'outer_edges.psm1') -Force
    $normal | Add-Member -NotePropertyName motorwayAssembly -NotePropertyValue $contract
    $normal | Add-Member -NotePropertyName activeEntrances -NotePropertyValue @($contract.gates.direction)
    $TileDirectory = Join-Path $root 'tiletemplates'
    $MotorwayCellInspection = $false
    Test-RecipeTilePlacements $normal 5
    Assert $true 'Complete normal straight source/ownership/gate contracts authorize production builder emission.'
    $invalidNormal = $normal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalidNormal.PSObject.Properties.Remove('motorwayAssembly')
    $rejected = $false
    try { Test-RecipeTilePlacements $invalidNormal 5 } catch {
        if ($_.Exception.Message -notlike 'Normal wide motorway emission requires*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Normal wide source remapping without measured assembly remains blocked.'
    $invalidNormal = $normal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalidNormal.motorwayAssembly.sourceSha256 = 'stale'
    $rejected = $false
    try { Test-RecipeTilePlacements $invalidNormal 5 } catch {
        if ($_.Exception.Message -notlike 'Normal wide motorway emission contract differs*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Stale normal metadata cannot authorize VMF emission.'
    $MotorwayCellInspection = $true
    $beforeExport = $normal | ConvertTo-Json -Depth 30 -Compress
    $runtimeGates = @(Get-RuntimeMotorwayGates $normal $TileDirectory)
    Assert (($runtimeGates | ConvertTo-Json -Depth 10 -Compress) -ceq ($contract.gates | ConvertTo-Json -Depth 10 -Compress)) 'Runtime export preserves exact measured cardinal/lane records.'
    Assert (($normal | ConvertTo-Json -Depth 30 -Compress) -ceq $beforeExport) 'Runtime export is read-only.'
    foreach ($field in @('sourceSha256', 'gates')) {
        $invalidExport = $normal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        if ($field -eq 'gates') { $invalidExport.motorwayAssembly.gates[0].lanes[0].arrowX += 1 }
        else { $invalidExport.motorwayAssembly.sourceSha256 = 'stale' }
        $rejected = $false
        try { Get-RuntimeMotorwayGates $invalidExport $TileDirectory | Out-Null } catch {
            if ($_.Exception.Message -notlike 'Runtime motorway gate metadata differs*') { throw }
            $rejected = $true
        }
        Assert $rejected "Runtime export rejects changed normal $field."
    }
    Import-Module (Join-Path $testsBinDirectory 'transition_gates.psm1') -Force
    $writerGates = @(Get-TransitionGatePlacements $normal)
    Assert ($writerGates.Count -eq 2) 'Production VMF gate selection consumes the measured normal plan.'
    foreach ($gate in $writerGates) {
        $bounds = Get-ZMTransitionTriggerBounds $gate
        $vertical = $gate.direction -in @('N', 'S')
        Assert (($bounds.maxX - $bounds.minX) -eq $(if ($vertical) { 1456 } else { 64 }) -and
            ($bounds.maxY - $bounds.minY) -eq $(if ($vertical) { 64 } else { 1456 })) 'Wide trigger covers both carriageways with unchanged64-unit crossing depth.'
        Assert ($bounds.minZ -eq 32 -and $bounds.maxZ -eq 144 -and $gate.arrivalZ -eq 72) 'Trigger and landmark preserve native deck-relative vertical clearance.'
        Assert ($gate.arrivalX -eq $gate.lanes[0].arrivalX -and $gate.arrivalY -eq $gate.lanes[0].arrivalY) 'Authored arrival landmark uses the selected measured lane behind the arrows.'
        $landmarkVmf = '"classname" "info_landmark"' + "`n" + '"targetname" "' + $gate.directionName.ToUpperInvariant() + '_ENTRANCE"' + "`n" + '"origin" "0 0 40"'
        $updatedLandmark = Set-ZMTransitionArrivalLandmarks $landmarkVmf @($gate)
        Assert ($updatedLandmark.Contains(('"origin" "{0} {1} 72"' -f $gate.arrivalX, $gate.arrivalY))) 'Actual landmark serialization consumes the measured lane/deck instead of axis-centred coordinates.'
        $forward = @{ N = @(0, 1); E = @(1, 0); S = @(0, -1); W = @(-1, 0) }[$gate.direction]
        $right = @($forward[1], -$forward[0])
        foreach ($lane in $gate.lanes) {
            foreach ($edge in @((-$lane.width / 2), ($lane.width / 2))) {
                $x = $gate.x + $right[0] * ($lane.lateral + $edge)
                $y = $gate.y + $right[1] * ($lane.lateral + $edge)
                Assert ($x -ge $bounds.minX -and $x -le $bounds.maxX -and $y -ge $bounds.minY -and $y -le $bounds.maxY) 'Measured floor edges remain within trigger bounds in every direction.'
            }
        }
        $props = @(Get-ZMTransitionBarricadeProps $gate)
        Assert ($props.Count -eq 4 -and $props[0].across -eq $gate.lanes[0].lateral -and
            [Math]::Abs(($props[3].across - $gate.lanes[1].lateral) + 0.108) -lt 0.000001) 'Existing barricade composition moves onto the two measured carriageways without scaling.'
        $legacy = [pscustomobject]@{ direction = $gate.direction; x = $gate.x; y = $gate.y; zOffset = 0 }
        $legacyBounds = Get-ZMTransitionTriggerBounds $legacy
        Assert (($legacyBounds.maxX - $legacyBounds.minX) -eq $(if ($vertical) { 256 } else { 64 }) -and
            ($legacyBounds.maxY - $legacyBounds.minY) -eq $(if ($vertical) { 64 } else { 256 })) 'Legacy gate dimensions remain exactly256 by64.'
        $legacyProps = @(Get-ZMTransitionBarricadeProps $legacy)
        Assert ($legacyProps[0].across -eq -192 -and $legacyProps[1].across -eq -192.499 -and
            $legacyProps[2].across -eq 192.233 -and $legacyProps[3].across -eq 191.892) 'Legacy barricade placements remain unchanged.'
    }
    $invalidGates = $normal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalidGates.motorwayAssembly.gates[0].lanes[0].lateral = -160
    $rejected = $false
    try { Get-TransitionGatePlacements $invalidGates | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Normal measured gate records differ*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Gate writer rejects stale or altered lane metadata rather than emitting mismatched geometry.'
    $invalidEntrances = $normal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalidEntrances.activeEntrances = @('N', 'E', 'S', 'W')
    $rejected = $false
    try { Get-TransitionGatePlacements $invalidEntrances | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Normal measured gates disagree*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Normal gates cannot silently discard additional active entrances.'
    Assert (@(Get-TransitionGatePlacements $recipe).Count -eq 0) 'Accepted inspection fixtures still emit no travel gates.'
    $routeLeases = @(Get-ZMRecipeRouteLeases $normal)
    Assert ($routeLeases.Count -eq 27) 'Boundary density adjacency consumes the normal-wide leases.'
    $border = @(foreach ($y in -1..5) { foreach ($x in -1..5) {
        if ($x -in @(-1, 5) -or $y -in @(-1, 5)) {
            [pscustomobject]@{ tileX = $x; tileY = $y; template = "control_border_$x,$y"; rotationYaw = 270 }
        }
    } })
    $outer = @(foreach ($y in -2..6) { foreach ($x in -2..6) {
        if ($x -in @(-2, 6) -or $y -in @(-2, 6)) {
            [pscustomobject]@{ tileX = $x; tileY = $y; template = "control_outer_$x,$y"; rotationYaw = 180 }
        }
    } })
    $beforeRings = @($border, $outer) | ConvertTo-Json -Depth 10 -Compress
    $resolved = Resolve-ZMNormalStraightMotorwayRings $normal (Join-Path $root 'tiletemplates') $border $outer
    Assert ($resolved.borderPlacements.Count -eq 20 -and $resolved.outerPlacements.Count -eq 28) 'Each ring replaces six displaced slots with two emitting three-wide owners.'
    foreach ($pair in @(@($border, $resolved.borderPlacements), @($outer, $resolved.outerPlacements))) {
        foreach ($original in $pair[0]) {
            $leased = @($contract.leases | Where-Object { $_.tileX -eq $original.tileX -and $_.tileY -eq $original.tileY }).Count -gt 0
            $remaining = @($pair[1] | Where-Object template -ceq $original.template)
            Assert ($remaining.Count -eq $(if ($leased) { 0 } else { 1 })) 'Only explicitly leased boundary pieces are displaced; neighbouring walls and corners survive.'
            if (-not $leased) { Assert ([object]::ReferenceEquals($remaining[0], $original)) 'Unleased authored boundary records retain identity and yaw.' }
        }
    }
    Assert ((@($border, $outer) | ConvertTo-Json -Depth 10 -Compress) -ceq $beforeRings) 'Ring resolution never mutates source boundary arrays.'
    $corruptNormal = $normal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $corruptNormal.motorwayAssembly.sourceSha256 = 'stale'
    $rejected = $false
    try { Resolve-ZMNormalStraightMotorwayRings $corruptNormal (Join-Path $root 'tiletemplates') $border $outer | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Normal straight motorway source changed*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Stale normal source fingerprints cannot replace boundaries.'
    $normal | Add-Member -NotePropertyName motorwayCellInspection -NotePropertyValue $recipe.motorwayCellInspection
    $rejected = $false
    try { Get-ZMRecipeRouteLeases $normal | Out-Null } catch {
        if ($_.Exception.Message -notlike 'A motorway recipe cannot own both*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Normal and inspection ownership cannot silently compete.'
    $MotorwayCellInspection = $false
    Assert ((Get-PlacementFootprint $owners[0]).width -eq $owners[0].footprintWidth) 'Shared footprint geometry is independent of inspection mode; recipe validation owns normal emission authorization.'
    $MotorwayCellInspection = $true
}

$placement = [pscustomobject]@{
    tileX = 1; tileY = 2; template = 'roads\motorway_3x1\tile_motorway.vmf'; rotationYaw = 0
    footprintWidth = 3; footprintHeight = 1; role = 'motorway_assembly'; emitsInstance = $true
    originCellLocal = [pscustomobject]@{ x = 17.125; y = -29.5; z = 68.25 }
}
$culture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    foreach ($interior in @($false, $true)) {
        $lines = @(New-PlacementInstanceLines $placement 5 640 0 101 'fixture.vmf' 'fractional' -Interior:$interior)
        Assert ($lines[4] -ceq '    "origin" "17.125 -29.5 68.25"') 'Explicit physical origin is independent of the integer anchor, unrounded and locale invariant.'
    }
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $culture
}
foreach ($case in @(
    @{ name = 'missing origin'; change = { param($p) $p.PSObject.Properties.Remove('originCellLocal') }; grid = 5; width = 640; z = 0; error = 'Motorway emitting owner requires*' },
    @{ name = 'nonfinite origin'; change = { param($p) $p.originCellLocal.y = [double]::PositiveInfinity }; grid = 5; width = 640; z = 0; error = 'Motorway point has non-finite*' },
    @{ name = 'suppressed emission'; change = { param($p) $p.emitsInstance = $false }; grid = 5; width = 640; z = 0; error = 'Occupied placement cannot emit*' },
    @{ name = 'different frame'; change = { param($p) }; grid = 7; width = 640; z = 0; error = 'Measured motorway origins require*' },
    @{ name = 'different pitch'; change = { param($p) }; grid = 5; width = 512; z = 0; error = 'Measured motorway origins require*' },
    @{ name = 'extra Z shift'; change = { param($p) }; grid = 5; width = 640; z = 32; error = 'Measured motorway origins require*' },
    @{ name = 'ordinary explicit origin'; change = { param($p) $p.role = 'terrain' }; grid = 5; width = 640; z = 0; error = 'Explicit cell-local origins are currently limited*' }
)) {
    $copy = $placement | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    & $case.change $copy
    $rejected = $false
    try { New-PlacementInstanceLines $copy $case.grid $case.width $case.z 101 'fixture.vmf' 'invalid' | Out-Null } catch {
        if ($_.Exception.Message -notlike $case.error) { throw }
        $rejected = $true
    }
    Assert $rejected "VMF writer rejects $($case.name)."
}
$MotorwayCellInspection = $false
Assert (@(New-PlacementInstanceLines $placement 5 640 0 101 'fixture.vmf' 'normal').Count -gt 0) 'Normal and inspection emission share the exact physical-origin serializer after recipe validation.'
foreach ($size in @(@(1, 1), @(2, 2), @(3, 3), @(1, 2), @(2, 1), @(2, 3), @(3, 2))) {
    foreach ($yaw in @(0, 90, 180, 270)) {
        foreach ($anchor in @(@(0, 1), @(-2, 6))) {
            foreach ($tileWidth in @(640, 641)) {
                foreach ($interior in @($false, $true)) {
                    $width = if ($yaw -in @(90, 270)) { $size[1] } else { $size[0] }
                    $height = if ($yaw -in @(90, 270)) { $size[0] } else { $size[1] }
                    $ordinary = [pscustomobject]@{
                        tileX = $anchor[0]; tileY = $anchor[1]; template = 'fixture-ordinary.vmf'
                        role = 'terrain'; rotationYaw = $yaw; footprintWidth = $width; footprintHeight = $height
                    }
                    $x = ($anchor[0] - 2 + ($width - 1) / 2.0) * $tileWidth
                    $y = (2 - $anchor[1] - ($height - 1) / 2.0) * $tileWidth
                    if ($interior) { $x = [int]$x; $y = [int]$y }
                    $expected = @(
                        'entity', '{', '    "id" "101"', '    "classname" "func_instance"',
                        ('    "origin" "{0} {1} 32"' -f $x, $y), ('    "angles" "0 {0} 0"' -f $yaw),
                        '    "file" "fixture-ordinary.vmf"', '    "targetname" "ordinary"', '    "fixup_style" "0"', '}'
                    )
                    $lines = @(New-PlacementInstanceLines $ordinary 5 $tileWidth 32 101 'fixture-ordinary.vmf' 'ordinary' -Interior:$interior)
                    Assert (($lines -join "`n") -ceq ($expected -join "`n")) 'Ordinary core/ring VMF entities exactly retain centred origins, interior rounding and metadata.'
                }
            }
        }
    }
}
Write-Host "Motorway geometry: $passed assertions passed; no world outputs changed."
