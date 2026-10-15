Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root ('generated\motorway_fixture_test_' + [guid]::NewGuid().ToString('N'))
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway preview: $Message" }
    $script:passed++
}
try {
    $summary = & (Join-Path $PSScriptRoot 'build_motorway_preview.ps1') -OutputDirectory $output
    $report = Get-Content -Raw -LiteralPath (Join-Path $output 'assembly-report.json') | ConvertFrom-Json
    Assert ($summary.rotationFixtures -eq 8 -and $summary.cases -eq 32) 'Eight sources, each with all four rotations.'
    Assert ($summary.exactSeams -eq 52 -and $summary.diagnosticSeams -eq 20 -and $summary.pendingApproaches -eq 20) 'Approved-source measured seams and unresolved road approaches are not conflated.'
    Assert ($report.status -eq 'Hammer_integration_inspection_not_release_generation') 'Inspection output cannot claim production acceptance.'
    Assert ($report.supportPolicy.exactMotorwaySeam -eq 'candidate_only_until_full_solid_and_clearance_validation' -and
        $report.supportPolicy.incompatibleMotorwaySeam -eq 'unsupported_connector_deferred' -and
        $report.supportPolicy.roadApproach -eq 'unsupported_approach_connector_deferred' -and
        $report.supportPolicy.diagnosticFixtures -eq 'inspection_only_never_planner_fallback') 'Only exact seams are candidates; incompatible motorway and road mouths stay explicitly unsupported.'
    Assert ($summary.exactSurfaceCandidates -eq 52 -and $summary.unsupportedMotorwayMouths -eq 20 -and $summary.unsupportedRoadMouths -eq 20) 'Every surveyed mouth has an explicit exact-candidate or deferred-connector disposition.'
    Assert ($report.ordinaryRoadApproach.sha256 -ceq (Get-FileHash -LiteralPath $report.ordinaryRoadApproach.source -Algorithm SHA256).Hash) 'Existing ordinary-road approach is measured read-only with source provenance.'
    $approach = $report.ordinaryRoadApproach.faces
    Assert ($approach.Count -eq 3) 'Ordinary-road approach records its southern floor and both split northern floors.'
    Assert (@($approach[0].vertices | Where-Object { $_.y -eq -320 -and $_.z -eq 36 }).Count -eq 2) 'Approved approach southern mouth retains measured Z36.'
    Assert (@($approach[1].vertices | Where-Object { $_.y -eq 320 -and $_.z -eq 68 }).Count -eq 2 -and @($approach[2].vertices | Where-Object { $_.y -eq 320 -and $_.z -eq 96 }).Count -eq 2) 'Approved split mouths retain Z68/Z96; the single ramp remains Z80 and bridge Z196.057.'
    $before = @{}
    foreach ($file in Get-ChildItem -LiteralPath $output -File) { $before[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    Assert ($before.Count -eq 11) 'Nine bounded VMFs plus source and assembly reports only.'
    & (Join-Path $PSScriptRoot 'build_motorway_preview.ps1') -OutputDirectory $output | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $output -File) {
        Assert ($before.ContainsKey($file.Name) -and $before[$file.Name] -ceq (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) 'Repeated generation is byte-identical, including JSON and VMFs.'
    }
    foreach ($piece in $report.registry) {
        Assert ($piece.sha256 -ceq (Get-FileHash -LiteralPath $piece.template -Algorithm SHA256).Hash) 'Authored source hashes remain unchanged.'
        $cases = @($report.cases | Where-Object piece -eq $piece.template)
        Assert ($cases.Count -eq 4 -and (@($cases.yaw | Sort-Object -Unique) -join ',') -eq '0,90,180,270') 'Each source has one case per cardinal rotation.'
        $path = Join-Path $output ([IO.Path]::GetFileNameWithoutExtension($piece.template) + '-rotations.vmf')
        $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($path))
        Assert ($null -ne $tree.Child('world')) 'Generated VMF has a valid parseable world.'
        Assert ($tree.Child('cameras').Get('activecamera') -eq '0' -and @($tree.Child('cameras').Children | Where-Object Name -eq camera).Count -eq 4) 'Each rotation fixture starts with a usable camera and supplies a camera per case.'
        $entities = @($tree.Children | Where-Object Name -eq 'entity')
        $instances = @($entities | Where-Object { $_.Get('classname') -eq 'func_instance' })
        Assert ($instances.Count -eq @($cases.instances).Count) 'Each placement emits exactly one actual instance.'
        $ids = @($entities | ForEach-Object { $_.Get('id') })
        Assert (@($ids | Sort-Object -Unique).Count -eq $ids.Count) 'Generated entity ids are unique.'
        foreach ($case in $cases) {
            $motorwayMouths = @($case.connections | Where-Object route -eq motorway)
            Assert ($case.instances.Count -eq 1 + $motorwayMouths.Count) 'No fabricated ordinary-road approach or false terminal exit emitted.'
            Assert ($case.reservations.Count -eq $case.instances.Count) 'Every instance has one explicit reservation owner.'
            foreach ($placement in $case.instances) {
                $entity = @($instances | Where-Object { $_.Get('targetname') -eq $placement.owner })
                Assert ($entity.Count -eq 1) 'Actual VMF has the expected unique emitting owner.'
                $resolved = [IO.Path]::GetFullPath((Join-Path $output $entity[0].Get('file').Replace('/', '\')))
                Assert ($resolved -ieq $placement.template -and (Test-Path -LiteralPath $resolved -PathType Leaf)) 'Every relative instance path resolves to the exact measured authored source.'
                $position = [ZombieSim.Skybox.Vec3]::Parse($entity[0].Get('origin'))
                Assert ($position.X -eq $placement.origin.x -and $position.Y -eq $placement.origin.y -and $position.Z -eq $placement.origin.z) 'VMF writer retains unsnapped measured translations.'
                Assert ($entity[0].Get('angles') -eq "0 $($placement.yaw) 0" -and $position.Z -eq 0) 'Mapped yaw preserved; no Z correction masks an incompatible deck.'
                Assert ([Math]::Abs($position.X) -lt 12000 -and [Math]::Abs($position.Y) -lt 12000) 'Rotation fixtures remain bounded inside Hammer coordinates.'
            }
            foreach ($reservation in $case.reservations) {
                Assert ($reservation.emitsInstance -and $reservation.slots.Count -gt 0 -and @($reservation.slots | Where-Object emitsInstance).Count -eq 0) 'Only placement owner emits; occupied lease records do not duplicate instances.'
                $keys = @($reservation.slots | ForEach-Object { "$($_.tileX),$($_.tileY)" })
                Assert (@($keys | Sort-Object -Unique).Count -eq $keys.Count) 'No duplicate lease slots within a placement.'
                Assert $reservation.windingWithinCellFrame 'Current winding envelopes fit the authoritative 5760 cell frame in all rotations.'
                foreach ($slot in $reservation.slots) {
                    $ring = [Math]::Max([Math]::Abs($slot.tileX), [Math]::Abs($slot.tileY))
                    $expected = if ($ring -le 2) { 'core' } elseif ($ring -eq 3) { 'border' } else { 'outer' }
                    Assert ($slot.ring -eq $expected -and $slot.owner -eq $reservation.owner) 'Every conservative lease has the correct core/border/outer ring and owner.'
                }
            }
            foreach ($connection in $case.connections) {
                if ($connection.status -eq 'approach_contract_pending') {
                    Assert ($connection.disposition -eq 'unsupported_approach_connector_deferred' -and $connection.placementEligibility -eq 'inspection_only') 'Road approaches remain unsupported and diagnostic-only until separately authorized.'
                    continue
                }
                $invalid = @($connection.residuals | Where-Object { $_.dx -ne 0 -or $_.dy -ne 0 -or $_.dz -ne 0 -or $_.widthDelta -ne 0 -or $_.gradeDelta -ne 0 -or -not $_.planarCardinal -or -not $_.contiguousEdges -or -not $_.consistentGrade })
                Assert (($connection.status -eq 'exact_floor_seam') -eq ($invalid.Count -eq 0)) 'Exact seams require every measured lane condition, not first-lane alignment alone.'
                $expectedDisposition = if ($connection.status -eq 'exact_floor_seam') { 'exact_surface_candidate_clearance_pending' } else { 'unsupported_connector_deferred' }
                Assert ($connection.disposition -eq $expectedDisposition -and $connection.placementEligibility -eq 'inspection_only') 'Floor matches do not claim clearance; incompatible connections cannot become planner fallbacks.'
            }
            foreach ($overlap in $case.envelopeOverlaps) {
                Assert ($overlap.status -eq 'conservative_envelope_overlap_requires_solid_clearance_review') 'Envelope overlap is surfaced, never silently accepted as safe underlay.'
            }
        }
    }
    $overview = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($report.overview))
    Assert (@($overview.Child('cameras').Children | Where-Object Name -eq camera).Count -eq 8) 'Overview supplies a camera for every named assembly.'
    $overviewInstances = @($overview.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'func_instance' })
    Assert ($overviewInstances.Count -eq 26) 'Overview contains all eight assemblies with the intended eighteen motorway continuations.'
    foreach ($instance in $overviewInstances) {
        $p = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
        Assert ([Math]::Abs($p.X) -lt 12000 -and [Math]::Abs($p.Y) -lt 14000) 'Overview remains bounded within Hammer world limits.'
    }
    foreach ($invalidOutput in @($root, (Join-Path $root 'tiletemplates'), (Join-Path $root 'content'))) {
        $rejected = $false
        try { & (Join-Path $PSScriptRoot 'build_motorway_preview.ps1') -OutputDirectory $invalidOutput | Out-Null } catch {
            if ($_.Exception.Message -notlike '*outputs must remain under generated*') { throw }
            $rejected = $true
        }
        Assert $rejected 'Builder refuses authored/staged/root output directories.'
    }
}
finally {
    if (Test-Path -LiteralPath $output -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $output -File) { Remove-Item -LiteralPath $file.FullName }
        Remove-Item -LiteralPath $output
    }
}
Write-Host "Motorway preview: $passed assertions passed; generated files, provenance, exact/diagnostic joins and ring reservations verified. No compiled collision or human acceptance claim."
