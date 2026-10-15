param([string]$OutputDirectory = '', [switch]$SizedInfill, [switch]$CompleteInfill)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'generated\phase_b_complex_cells' }
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Complex motorway cells: $Message" }
    $script:passed++
}
& (Join-Path $PSScriptRoot 'build_motorway_cell_preview.ps1') -Complex -SizedInfill:$SizedInfill -CompleteInfill:$CompleteInfill -OutputDirectory $OutputDirectory | Out-Null
if (-not $?) { throw 'Complex cell generation failed.' }
$report = Get-Content -Raw -LiteralPath (Join-Path $OutputDirectory 'cell-report.json') | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $report.plan | ConvertFrom-Json
Assert ($plan.cells.Count -eq 7 -and $report.cells.Count -eq 7) 'Seven complete cells cover the seven remaining source pieces.'
Assert ($report.fixtureChanges.Count -eq 1 -and $report.fixtureChanges[0] -like '*T-junction*') 'Missing real T-junction is an explicitly declared synthetic fixture, never fabricated world evidence.'
$expectedNames = @('tile_motorway_corner_5x3.vmf', 'tile_motorway_crossroads_6x3.vmf', 'tile_motorway_tjunction_6x3.vmf', 'tile_motorway_deadend_3x3.vmf', 'tile_motorway_road_bridge.vmf', 'tile_motorway_onramp_3x4.vmf', 'tile_motorway_onramp_dual_3x4.vmf')
$sourceRoot = $plan.chunkTemplateDirectory
$byPiece = @{}
$sourceBounds = @{}
foreach ($cell in $plan.cells) {
    $inspection = $cell.motorwayCellInspection
    $name = [IO.Path]::GetFileName($inspection.template)
    Assert ($name -in $expectedNames -and -not $byPiece.ContainsKey($name)) 'Each required complex source appears in exactly one complete cell.'
    $byPiece[$name] = $cell
    Assert ($inspection.schemaVersion -eq 2 -and $inspection.status -eq 'complex_cell_diagnostic_not_live_travel') 'Unresolved diagnostic geometry is not represented as production-ready.'
    $vmf = Join-Path (Join-Path $OutputDirectory 'src') $cell.cellTemplateFilename
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmf))
    $entities = @($tree.Children | Where-Object Name -eq entity)
    $instances = @($entities | Where-Object { $_.Get('classname') -eq 'func_instance' })
    $layout = Get-Content -Raw -LiteralPath ([IO.Path]::ChangeExtension($vmf, '.layout.json')) | ConvertFrom-Json
    Assert ($layout.vmfSha256 -eq (Get-FileHash -LiteralPath $vmf -Algorithm SHA256).Hash.ToLowerInvariant()) 'Actual complete-cell layout fingerprint matches generated VMF.'
    Assert ($inspection.status -eq 'complex_cell_diagnostic_not_live_travel') 'Complete-cell inspection plan remains diagnostic-only and cannot be treated as a supported travel cell.'
    Assert ($layout.bounds.neighbourPitch -eq 5760) 'Full 9x9 frame remains authoritative.'
    Assert (@($tree.Child('world').Children | Where-Object Name -eq solid).Count -eq 10) 'Normal sealed cell shell retained.'
    Assert (@($entities | Where-Object { $_.Get('classname') -eq 'info_player_start' }).Count -eq 1) 'Complete cell retains a terrain-based player start.'
    Assert (@($instances | Where-Object { $_.Get('targetname') -eq 'zm_skybox_room' }).Count -eq 1) 'Normal skybox room remains in each complex cell.'
    Assert (@($entities | Where-Object { $_.Get('zm_transition_gate') -eq '1' }).Count -eq 0) 'No unvalidated narrow travel trigger masquerades as wide geometry.'
    Assert ($cell.tilePlacements.Count -eq 25 -and @($cell.tilePlacements | Where-Object role -eq terrain).Count -gt 0) 'Every core slot represented and a real free terrain spawn preserved.'
    $assemblyEntities = @($instances | Where-Object { $_.Get('targetname') -like 'zm_assembly_*' })
    Assert ($assemblyEntities.Count -eq $inspection.assemblies.Count) 'Each measured transport owner emits exactly one actual instance.'
    $owners = @($inspection.assemblies.owner)
    Assert (@($owners | Sort-Object -Unique).Count -eq $owners.Count) 'Assembly owners never duplicate.'
    foreach ($assembly in $inspection.assemblies) {
        Assert ($assembly.placementEligibility -eq 'inspection_only' -and $assembly.disposition -in @('authored_source', 'exact_surface_candidate_clearance_pending', 'unsupported_connector_deferred', 'unsupported_approach_connector_deferred', 'source_measured_road_join_clearance_pending')) 'Every transport/approach placement is explicitly excluded from production eligibility.'
        if ($assembly.disposition -eq 'source_measured_road_join_clearance_pending') {
            Assert ($assembly.status -eq 'exact_ordinary_road_floor_seam') 'Road joins remain measured floor-seam candidates, not clearance acceptance.'
        }
        if ($assembly.disposition -eq 'exact_surface_candidate_clearance_pending') {
            Assert ($assembly.status -in @('exact_floor_seam', 'continuation_floor_seam')) 'An exact surface candidate is not mislabeled as clearance-validated.'
        }
        if ($assembly.disposition -eq 'unsupported_approach_connector_deferred') {
            Assert ($assembly.status -in @('unapproved_road_deck_grade_diagnostic', 'unapproved_road_approach_continuation')) 'Deferred road geometry remains explicitly diagnostic.'
        }
        $entity = @($assemblyEntities | Where-Object { $_.Get('targetname') -eq "zm_assembly_$($assembly.owner)" })
        Assert ($entity.Count -eq 1) 'Exact emitting assembly owner exists in the written VMF.'
        $origin = [ZombieSim.Skybox.Vec3]::Parse($entity[0].Get('origin'))
        Assert ($origin.X -eq $assembly.origin.x -and $origin.Y -eq $assembly.origin.y -and $origin.Z -eq $assembly.origin.z -and $origin.Z -eq 0) 'Fractional XY survives serialization; no elevation correction hides grade/deck mismatch.'
        Assert ($entity[0].Get('angles') -eq "0 $($assembly.yaw) 0") 'Authored mapped yaw is preserved.'
        $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $vmf) $entity[0].Get('file').Replace('/', '\')))
        Assert ($resolved -ieq (Join-Path $sourceRoot $assembly.template)) 'Written instance resolves to exact measured authored source.'
        Assert (@($inspection.leases | Where-Object owner -eq $assembly.owner).Count -gt 0) 'Every transport owner reserves cell slots before scenery.'
        if (-not $sourceBounds.ContainsKey($resolved)) {
            $sourceTree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($resolved))
            $vertices = @(foreach ($owner in @($sourceTree.Child('world')) + @($sourceTree.Children | Where-Object Name -eq entity)) {
                foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
                    foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                        foreach ($point in $side.Child('vertices_plus').GetAll('v')) { [ZombieSim.Skybox.Vec3]::Parse($point) }
                    }
                }
            })
            $sourceBounds[$resolved] = $vertices
        }
        $yaw = $assembly.yaw
        $transformed = @($sourceBounds[$resolved] | ForEach-Object {
            $vertex = $_
            switch ($yaw) {
                0 { $x = $vertex.X; $y = $vertex.Y }
                90 { $x = -$vertex.Y; $y = $vertex.X }
                180 { $x = -$vertex.X; $y = -$vertex.Y }
                270 { $x = $vertex.Y; $y = -$vertex.X }
            }
            [pscustomobject]@{ x = $x + $origin.X; y = $y + $origin.Y; z = $vertex.Z + $origin.Z }
        })
        foreach ($axis in @('x', 'y', 'z')) {
            $range = $transformed | Measure-Object -Property $axis -Minimum -Maximum
            Assert ($range.Minimum -eq $assembly.windingBounds.$axis.min -and $range.Maximum -eq $assembly.windingBounds.$axis.max) 'Reservations use every saved world/brush-entity winding, never guessed approach bounds.'
        }
        $bounds = $assembly.windingBounds
        Assert ($assembly.windingWithinCellFrame -eq ($bounds.x.min -ge -2880 -and $bounds.x.max -le 2880 -and $bounds.y.min -ge -2880 -and $bounds.y.max -le 2880)) 'Overhang beyond the physical cell boundary explicitly reported.'
        Assert ($assembly.extendsBelowTerrain -eq ($bounds.z.min -lt 0)) 'Below-terrain source geometry remains disclosed for shell review.'
    }
    $overlapCount = 0
    for ($a = 0; $a -lt $inspection.assemblies.Count; $a++) {
        for ($b = $a + 1; $b -lt $inspection.assemblies.Count; $b++) {
            $first = $inspection.assemblies[$a]
            $second = $inspection.assemblies[$b]
            $one = $first.windingBounds
            $two = $second.windingBounds
            $intersects = $one.x.min -lt $two.x.max -and $one.x.max -gt $two.x.min -and $one.y.min -lt $two.y.max -and $one.y.max -gt $two.y.min -and $one.z.min -lt $two.z.max -and $one.z.max -gt $two.z.min
            $record = @($inspection.envelopeOverlaps | Where-Object { $_.first -eq $first.owner -and $_.second -eq $second.owner })
            Assert ($record.Count -eq [int]$intersects) 'Every actual continuation and approach participates in positive-volume envelope diagnostics.'
            if ($intersects) { $overlapCount++ }
        }
    }
    Assert ($inspection.envelopeOverlaps.Count -eq $overlapCount) 'No stale zoo-only overlap evidence survives into complete cells.'
    foreach ($instance in $instances) {
        $file = $instance.Get('file')
        $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $vmf) $file.Replace('/', '\')))
        Assert (Test-Path -LiteralPath $resolved -PathType Leaf) 'All cell sources exist, including surrounding scenery and boundaries.'
        Assert ($file -notmatch 'motorway_1x1|tile_road_gate|buildings/|carparks/') 'No legacy motorway, narrow blocker or building fallback appears in the final cell.'
    }
    foreach ($lease in $inspection.leases) {
        Assert ($lease.owner -in $owners -and -not $lease.emitsInstance) 'Occupied coverage never duplicates an emitting owner.'
        $ringIndex = [Math]::Max([Math]::Abs($lease.tileX - 2), [Math]::Abs($lease.tileY - 2))
        $expectedRing = if ($ringIndex -le 2) { 'core' } elseif ($ringIndex -eq 3) { 'border' } else { 'outer' }
        Assert ($lease.ring -eq $expectedRing) 'Physical coverage mapped to logical core/border/outer coordinates.'
    }
    foreach ($placement in @($layout.borderPlacements) + @($layout.outerPlacements) + @($cell.tilePlacements | Where-Object { $_.role -ne 'motorway_external_occupied' })) {
        Assert (@($inspection.leases | Where-Object { $_.tileX -eq $placement.tileX -and $_.tileY -eq $placement.tileY }).Count -eq 0) 'Scenery and walls do not reclaim any transport lease, including shared layered slots.'
    }
    foreach ($property in $inspection.sourceFingerprints.PSObject.Properties) {
        Assert ($property.Value -ceq (Get-FileHash -LiteralPath (Join-Path $sourceRoot $property.Name) -Algorithm SHA256).Hash) 'All motorway and approach source fingerprints unchanged.'
    }
    foreach ($gap in $inspection.boundaryGaps) {
        Assert ($gap.status -in @('reaches_boundary', 'unfilled_partial_tile_boundary_no_scaling', 'road_approach_and_boundary_pending')) 'Partial-tile endings and road approaches explicitly disclosed.'
        if ($gap.status -eq 'reaches_boundary') { Assert ($gap.gapToVisualBoundary -eq 0) 'Only exact footprint reach is labelled complete.' }
    }
    foreach ($connection in $inspection.connections) {
        if ($connection.route -eq 'road') {
            Assert ($connection.disposition -eq 'unsupported_approach_connector_deferred' -and $connection.placementEligibility -eq 'inspection_only') 'Ordinary-road mouth is an explicitly deferred unsupported connector.'
            Assert (@($inspection.assemblies | Where-Object { $_.owner -like "*/$($connection.ports[0].outward)/road_approach" -and $_.status -eq 'unapproved_road_deck_grade_diagnostic' -and $_.disposition -eq $connection.disposition }).Count -eq 1) 'Ordinary-road mouth has one visible approach explicitly labelled diagnostic.'
        } else {
            $expectedDisposition = if ($connection.status -eq 'exact_floor_seam') { 'exact_surface_candidate_clearance_pending' } else { 'unsupported_connector_deferred' }
            Assert ($connection.disposition -eq $expectedDisposition -and $connection.placementEligibility -eq 'inspection_only') 'Motorway seam disposition retains exact-candidate versus unsupported status without claiming clearance.'
            Assert ($connection.status -in @('exact_floor_seam', 'diagnostic_seam_not_approved')) 'Two-lane residual status retained from measured registry.'
        }
    }
    Assert (@($tree.Child('cameras').Children | Where-Object Name -eq camera).Count -eq 2) 'Full cell supplies both overview and road-height cameras.'
}
Assert ($byPiece['tile_motorway_road_bridge.vmf'].motorwayCellInspection.yaw -eq 90) 'Existing bridge-horizontal transport yaw retained, not guessed from the new source.'
$bridge = $byPiece['tile_motorway_road_bridge.vmf'].motorwayCellInspection
Assert (($bridge.measuredMotorwayDirections -join ',') -eq 'E,W') 'Measured bridge motorway direction exposes the mapped-yaw/declared-N-S integration mismatch rather than hiding it.'
Assert ($byPiece['tile_motorway_onramp_3x4.vmf'].motorwayCellInspection.yaw -eq 90 -and $byPiece['tile_motorway_onramp_dual_3x4.vmf'].motorwayCellInspection.yaw -eq 270) 'Both existing ramp mappings unchanged.'
$terminal = $byPiece['tile_motorway_deadend_3x3.vmf'].motorwayCellInspection
Assert ($terminal.connections.Count -eq 1 -and $terminal.connections[0].ports[0].outward -eq 'S') 'Terminal has no invented northern through exit.'
$negativeRoot = Join-Path $OutputDirectory 'unsupported-combinations'
[IO.Directory]::CreateDirectory($negativeRoot) | Out-Null
$incompleteAssembly = Get-Content -Raw (Join-Path $OutputDirectory 'measured-assemblies\assembly-report.json') | ConvertFrom-Json
$incompleteAssembly.cases = @($incompleteAssembly.cases | Where-Object {
    [IO.Path]::GetFileName($_.piece) -notin @('tile_motorway_road_bridge.vmf', 'tile_motorway_onramp_3x4.vmf')
})
$negativeAssemblyReport = Join-Path $negativeRoot 'missing-transport-report.json'
[IO.File]::WriteAllText($negativeAssemblyReport, ($incompleteAssembly | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
$sourceManifest = Get-Content -Raw -LiteralPath $report.sourceManifest | ConvertFrom-Json
$combined = @($sourceManifest.cells | Where-Object { ($_.x -eq 13 -and $_.y -eq 18) -or ($_.x -eq 17 -and $_.y -eq 0) })
Assert ($combined.Count -eq 2) 'Real corner/ramp and terminal/bridge combinations remain represented, never silently simplified.'
foreach ($target in $combined) {
    $sourceManifest.cells = @($target)
    $sourceManifest.safeZones = @()
    $negativeMap = Join-Path $negativeRoot "map-$($target.x)-$($target.y).json"
    [IO.File]::WriteAllText($negativeMap, ($sourceManifest | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try {
        & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $report.settings -MapData $negativeMap -Output (Join-Path $negativeRoot 'plan.json') -ListOutput (Join-Path $negativeRoot 'required.txt') -CellDirectory (Join-Path $negativeRoot 'src') -MotorwayCellInspection -MotorwayAssemblyReport $negativeAssemblyReport | Out-Null
    } catch {
        if ($_.Exception.Message -notlike '*Mixed motorway requires unique source-measured topology and transport orientations*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Combined topology without its measured transport case is rejected, never emitted as just a corner or terminal.'
}
$hashes = @{}
foreach ($file in Get-ChildItem (Join-Path $OutputDirectory 'src') -File) { $hashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
& (Join-Path $PSScriptRoot 'build_motorway_cell_preview.ps1') -Complex -SizedInfill:$SizedInfill -CompleteInfill:$CompleteInfill -OutputDirectory $OutputDirectory | Out-Null
if (-not $?) { throw 'Repeated complex-cell generation failed.' }
foreach ($file in Get-ChildItem (Join-Path $OutputDirectory 'src') -File) {
    Assert ($hashes.ContainsKey($file.Name) -and $hashes[$file.Name] -ceq (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) 'Actual cell VMFs and layouts regenerate byte-identically.'
}
& (Join-Path $PSScriptRoot 'check_required_cells.ps1') -WorldProfile preview -SettingsPath $report.settings -RequiredCellList (Join-Path $OutputDirectory 'required.txt') -CellDirectory (Join-Path $OutputDirectory 'src')
if (-not $?) { throw 'Complex required-cell check failed.' }
Write-Host "Complex motorway cells: $passed assertions passed; seven complete diagnostic cells. Human review, compiled clearance and unresolved routes/approaches remain separate."
