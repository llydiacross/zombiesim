param([string]$PlanData = '', [string]$OutputDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'motorway_geometry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'transition_gates.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'generated\phase_e_complex_gate_tests' }
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    & (Join-Path $PSScriptRoot 'build_motorway_cell_preview.ps1') -Mixed -OutputDirectory $OutputDirectory | Out-Null
    if (-not $?) { throw 'Mixed gate fixture generation failed.' }
    $PlanData = Join-Path $OutputDirectory 'plan.json'
}
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Complex motorway gates: $Message" }
    $script:passed++
}
function Assert-Rejected {
    param([object]$Contract, [string]$Expected)
    $before = $Contract | ConvertTo-Json -Depth 40
    $rejected = $false
    try { Get-ZMComplexMotorwayGates $Contract $plan.chunkTemplateDirectory | Out-Null } catch {
        if ($_.Exception.Message -notlike $Expected) { throw }
        $rejected = $true
    }
    Assert $rejected 'Invalid geometry is rejected explicitly.'
    Assert (($Contract | ConvertTo-Json -Depth 40) -ceq $before) 'Failure does not mutate the input contract.'
}
Assert ($plan.cells.Count -in @(4, 7)) 'The exact four mixed or seven standalone whole-cell cases are tested.'
foreach ($cell in $plan.cells) {
    $contract = $cell.motorwayCellInspection
    $before = $contract | ConvertTo-Json -Depth 40
    $gates = @(Get-ZMComplexMotorwayGates $contract $plan.chunkTemplateDirectory)
    Assert (($contract | ConvertTo-Json -Depth 40) -ceq $before) 'Source-floor measurement does not mutate geometry or diagnostic status.'
    Assert ($gates.Count -eq $contract.connections.Count) 'Every measured transport route has exactly one gate candidate.'
    foreach ($gate in $gates) {
        $forward = @{ N = @(0, 1); E = @(1, 0); S = @(0, -1); W = @(-1, 0) }[$gate.direction]
        $right = @($forward[1], -$forward[0])
        $along = $gate.x * $forward[0] + $gate.y * $forward[1]
        $axis = $gate.x * $right[0] + $gate.y * $right[1]
        Assert ($along -ge 2208 -and $along -le 2816) 'Gate remains inside the authoritative 2880-unit boundary.'
        Assert ($gate.lanes.Count -eq $(if ($gate.route -eq 'motorway') { 2 } else { 1 })) 'Road and motorway lane counts are explicit.'
        foreach ($lane in $gate.lanes) {
            Assert ($lane.deckZ -eq $gate.deckZ) 'Each lane and trigger uses the same measured floor height.'
            Assert ($lane.arrowX * $right[0] + $lane.arrowY * $right[1] -eq $axis + $lane.lateral -and
                $lane.arrivalX * $right[0] + $lane.arrivalY * $right[1] -eq $axis + $lane.lateral) 'Arrow and arrival retain the physical lane centre, including off-axis mouths.'
            Assert ($along - ($lane.arrowX * $forward[0] + $lane.arrowY * $forward[1]) -eq $(if ($gate.route -eq 'motorway') { 256 } else { 96 })) 'Ordinary-road arrow spacing and existing motorway spacing are separate.'
            Assert ($along - ($lane.arrivalX * $forward[0] + $lane.arrivalY * $forward[1]) -eq $(if ($gate.route -eq 'motorway') { 384 } else { 128 })) 'Arrival remains behind the arrow on its actual route.'
        }
        if ($gate.route -eq 'road' -and @($contract.ordinaryRoadApproaches | Where-Object heading -eq $gate.direction).Count -gt 0) {
            Assert ($axis -eq 0) 'Approved centred approaches retain the true central entrance axis.'
        }
        $writerGate = $gate | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $writerGate | Add-Member -NotePropertyName zOffset -NotePropertyValue ($gate.deckZ - 36)
        $bounds = Get-ZMTransitionTriggerBounds $writerGate
        $crossWidth = $gate.lateralMax - $gate.lateralMin
        Assert (($bounds.maxX - $bounds.minX) -eq $(if ($gate.direction -in @('N', 'S')) { $crossWidth } else { 64 }) -and
            ($bounds.maxY - $bounds.minY) -eq $(if ($gate.direction -in @('N', 'S')) { 64 } else { $crossWidth })) 'Trigger keeps its physical lane span and 64-unit crossing depth.'
        $props = @(Get-ZMTransitionBarricadeProps $writerGate)
        Assert ($props.Count -eq 4 -and $props[0].across -eq $(if ($gate.route -eq 'road') { -192 } else { $gate.lanes[0].lateral })) 'Ordinary roads preserve native barricades; motorway pairs use measured carriageways.'
    }
    if ($cell.topology -eq 'motorway-corner' -and $contract.ordinaryRoadApproaches.Count -gt 0) {
        $south = @($gates | Where-Object direction -eq S)[0]
        Assert ($south.y -eq -2720 -and $south.x -eq 0 -and $south.deckZ -eq 36) 'South gate, arrow -2624 and arrival -2592 all fit the centred corner approach.'
    }
    $stale = $before | ConvertFrom-Json
    @($stale.sourceFingerprints.PSObject.Properties)[0].Value = 'stale'
    Assert-Rejected $stale 'Complex gate source fingerprint changed:*'
    $unframed = $before | ConvertFrom-Json
    $unframed.PSObject.Properties.Remove('sourceFrameOrigin')
    Assert-Rejected $unframed 'Complex gate contract lacks its source coordinate frame.'
    foreach ($yaw in @(90, 180, 270)) {
        $rotated = $before | ConvertFrom-Json
        $rotated.sourceFrameOrigin = Convert-ZMMotorwayPoint $rotated.sourceFrameOrigin $yaw
        foreach ($assembly in $rotated.assemblies) {
            $assembly.origin = Convert-ZMMotorwayPoint $assembly.origin $yaw
            $assembly.yaw = ($assembly.yaw + $yaw) % 360
        }
        foreach ($connection in $rotated.connections) {
            $connection.ports = @($connection.ports | ForEach-Object { Convert-ZMMotorwayPort $_ $yaw ([pscustomobject]@{ x = 0; y = 0; z = 0 }) })
        }
        foreach ($approach in $rotated.ordinaryRoadApproaches) {
            $headingPort = Convert-ZMMotorwayPort $approach.boundaryPort $yaw ([pscustomobject]@{ x = 0; y = 0; z = 0 })
            $approach.heading = $headingPort.outward
            foreach ($instance in $approach.instances) {
                $instance.origin = Convert-ZMMotorwayPoint $instance.origin $yaw
                $instance.yaw = ($instance.yaw + $yaw) % 360
            }
        }
        $turned = @(Get-ZMComplexMotorwayGates $rotated $plan.chunkTemplateDirectory)
        Assert ($turned.Count -eq $gates.Count) 'Every route survives each cardinal rotation.'
        foreach ($gate in $gates) {
            $point = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $gate.x; y = $gate.y; z = $gate.deckZ }) $yaw
            $direction = (Convert-ZMMotorwayPort ([pscustomobject]@{
                id = 'gate'; route = $gate.route; position = $point; outward = $gate.direction; width = 256; grade = 0
            }) $yaw ([pscustomobject]@{ x = 0; y = 0; z = 0 })).outward
            $actual = @($turned | Where-Object direction -eq $direction)[0]
            Assert ($actual.x -eq $point.x -and $actual.y -eq $point.y -and $actual.deckZ -eq $point.z -and $actual.route -eq $gate.route) 'Physical gate axes rotate independently of diagnostic owner names.'
            for ($index = 0; $index -lt $gate.lanes.Count; $index++) {
                $lane = $gate.lanes[$index]
                $arrival = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $lane.arrivalX; y = $lane.arrivalY; z = $lane.deckZ }) $yaw
                $arrow = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $lane.arrowX; y = $lane.arrowY; z = $lane.deckZ }) $yaw
                Assert ($actual.lanes[$index].arrivalX -eq $arrival.x -and $actual.lanes[$index].arrivalY -eq $arrival.y -and
                    $actual.lanes[$index].arrowX -eq $arrow.x -and $actual.lanes[$index].arrowY -eq $arrow.y) 'Arrows and arrivals retain their exact cardinal source-floor relationship.'
            }
        }
    }
}
& (Get-Module motorway_geometry) {
    $slices = @([pscustomobject]@{ min = -128; max = -1; deckZ = 36 }, [pscustomobject]@{ min = 1; max = 128; deckZ = 36 })
    if (Test-ZMAssemblyLaneSupport $slices -128 128 36) { throw 'Floor support silently bridged a physical gap.' }
    $slices[0].max = 0; $slices[1].min = 0
    if (-not (Test-ZMAssemblyLaneSupport $slices -128 128 36)) { throw 'Contiguous saved edges did not form one lane.' }
    if (Test-ZMAssemblyLaneSupport $slices -128 128 68) { throw 'Floor support accepted the wrong deck.' }
}
$passed += 3
Write-Output "Complex motorway gates: $passed assertions passed."
