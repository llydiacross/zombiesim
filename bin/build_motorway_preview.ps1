param(
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'motorway_geometry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
if ($profile.Name -ne 'preview') { throw 'Motorway assembly inspection is isolated to the preview profile.' }
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'generated\phase_b_motorway' }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$generatedRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'generated')).TrimEnd('\') + '\'
if (-not $OutputDirectory.StartsWith($generatedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Motorway inspection outputs must remain under generated, not authored or staged directories.' }
[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$surveyPath = Join-Path $OutputDirectory 'source-survey.json'
& (Join-Path $PSScriptRoot 'survey_motorway_templates.ps1') -WorldProfile preview -SettingsPath $SettingsPath -Output $surveyPath | Out-Null
$survey = Get-Content -Raw -LiteralPath $surveyPath | ConvertFrom-Json
$registry = @($survey.pieces | ForEach-Object { Get-ZMMotorwayMouthRegistry $_ })
$straight = $registry[0]
$opposite = @{ N = 'S'; E = 'W'; S = 'N'; W = 'E' }
$reportCases = [System.Collections.Generic.List[object]]::new()
$approachPath = Join-Path (Join-Path $root $profile.Settings.paths.templateDirectory) 'roads\tile_road_onramp.vmf'
$approachHash = (Get-FileHash -LiteralPath $approachPath -Algorithm SHA256).Hash
$approachTree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($approachPath))
$approachOwners = @($approachTree.Child('world')) + @($approachTree.Children | Where-Object Name -eq entity)
$approachFaces = @(foreach ($id in @('1172', '1256', '1267')) {
    $matches = @($approachOwners | ForEach-Object { $_.Children } | Where-Object Name -eq solid | ForEach-Object { $_.Children } | Where-Object { $_.Name -eq 'side' -and $_.Get('id') -eq $id })
    if ($matches.Count -ne 1 -or $matches[0].Get('material') -ne 'CONCRETE/CONCRETEFLOOR037A' -or $null -eq $matches[0].Child('vertices_plus')) { throw "Ordinary-road approach source floor '$id' changed/missing." }
    $vertices = @($matches[0].Child('vertices_plus').GetAll('v') | ForEach-Object {
        $point = [ZombieSim.Skybox.Vec3]::Parse($_)
        Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $point.X; y = $point.Y; z = $point.Z }) 0
    })
    [pscustomobject]@{ sideId = $id; vertices = $vertices }
})
if ($approachHash -cne (Get-FileHash -LiteralPath $approachPath -Algorithm SHA256).Hash) { throw 'Ordinary-road approach source changed during measurement.' }

function New-AssemblyCase {
    param([object]$Piece, [int]$Yaw, [object]$Origin, [string]$Id)

    $centeredCrossroads = [IO.Path]::GetFileName($Piece.template) -eq 'tile_motorway_crossroads_3x3.vmf'
    $mainOrigin = [pscustomobject]@{
        x = [double]$Origin.x; y = [double]$Origin.y
        z = [double]$Origin.z + $(if ($centeredCrossroads) { 800 } else { 0 })
    }
    $instances = [System.Collections.Generic.List[object]]::new()
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $instances.Add([pscustomobject]@{ template = $Piece.template; yaw = $Yaw; origin = $mainOrigin; owner = "$Id/main"; status = 'authored_piece' })
    foreach ($mouth in $Piece.mouths) {
        $fixedPorts = @($mouth.lanes | ForEach-Object { Convert-ZMMotorwayPort $_ $Yaw $mainOrigin })
        if ($mouth.route -eq 'road') {
            $diagnostics.Add([pscustomobject]@{
                mouth = $mouth.outward; route = 'road'; status = 'approach_contract_pending'
                disposition = 'unsupported_approach_connector_deferred'
                placementEligibility = 'inspection_only'
                ports = $fixedPorts
                reason = 'Existing road approach floors are recorded separately; no matching deck/grade approach has been approved or fabricated.'
            })
            continue
        }
        $heading = $fixedPorts[0].outward
        $rampContinuation = $centeredCrossroads -and $heading -in @('E', 'W')
        $continuationTemplate = if ($rampContinuation) {
            @($registry | Where-Object { [IO.Path]::GetFileName($_.template) -eq 'tile_motorway_ramp.vmf' })[0]
        } else { $straight }
        $continuationYaw = if ($rampContinuation) {
            $insideDirection = $opposite[$heading]
            [int]$profile.Settings.cellPlanning.rotations.transport.bridgeRampByDirection[$insideDirection]
        } elseif ($heading -in @('N', 'S')) {
            [int]$profile.Settings.cellPlanning.rotations.layout.straight.vertical
        } else {
            [int]$profile.Settings.cellPlanning.rotations.layout.straight.horizontal
        }
        $zero = [pscustomobject]@{ x = 0; y = 0; z = 0 }
        $movingMouth = @($continuationTemplate.mouths | Where-Object { (Convert-ZMMotorwayPort $_.lanes[0] $continuationYaw $zero).outward -eq $opposite[$heading] })
        if ($movingMouth.Count -ne 1) { throw "No mapped straight mouth for $Id/$heading." }
        $lateral = if ($heading -in @('N', 'S')) { 'x' } else { 'y' }
        $fixed = @($fixedPorts | Sort-Object { $_.position.$lateral })
        $moving = @($movingMouth[0].lanes | Sort-Object { (Convert-ZMMotorwayPort $_ $continuationYaw $zero).position.$lateral })
        $firstMoving = Convert-ZMMotorwayPort $moving[0] $continuationYaw $zero
        $translation = if ($fixed[0].width -eq $firstMoving.width -and $fixed[0].position.z -eq $firstMoving.position.z -and $fixed[0].grade -eq -$firstMoving.grade) {
            Resolve-ZMMotorwayPortTranslation $fixed[0] $moving[0] $continuationYaw 0
        } else {
            # Inspection-only alignment exposes the rejected seam; this is never a planner fallback.
            [pscustomobject]@{ x = $fixed[0].position.x - $firstMoving.position.x; y = $fixed[0].position.y - $firstMoving.position.y; z = 0.0 }
        }
        $residuals = @(for ($lane = 0; $lane -lt $fixed.Count; $lane++) {
            $joined = Convert-ZMMotorwayPort $moving[$lane] $continuationYaw $translation
            $sourceLane = @($mouth.lanes | Where-Object id -eq $fixed[$lane].id)[0]
            [pscustomobject]@{
                lane = $lane
                sourceLane = $sourceLane.id
                dx = $fixed[$lane].position.x - $joined.position.x
                dy = $fixed[$lane].position.y - $joined.position.y
                dz = $fixed[$lane].position.z - $joined.position.z
                widthDelta = $fixed[$lane].width - $joined.width
                planarCardinal = $sourceLane.planarCardinal
                contiguousEdges = $sourceLane.contiguousEdges
                consistentGrade = $sourceLane.consistentGrade
                gradeDelta = $fixed[$lane].grade + $joined.grade
            }
        })
        $exact = @($residuals | Where-Object { $_.dx -ne 0 -or $_.dy -ne 0 -or $_.dz -ne 0 -or $_.widthDelta -ne 0 -or $_.gradeDelta -ne 0 -or -not $_.planarCardinal -or -not $_.contiguousEdges -or -not $_.consistentGrade }).Count -eq 0
        $status = if ($exact) { 'exact_floor_seam' } else { 'diagnostic_seam_not_approved' }
        $disposition = if ($exact) { 'exact_surface_candidate_clearance_pending' } else { 'unsupported_connector_deferred' }
        $continuation = [pscustomobject]@{
            template = $continuationTemplate.template; yaw = $continuationYaw; origin = $translation
            owner = "$Id/$heading/continuation"; status = $status
        }
        if ($rampContinuation) { $continuation | Add-Member -NotePropertyName nextTemplate -NotePropertyValue $straight.template }
        $instances.Add($continuation)
        $diagnostics.Add([pscustomobject]@{
            mouth = $mouth.outward; route = 'motorway'; status = $status
            disposition = $disposition; placementEligibility = 'inspection_only'
            ports = $fixed; residuals = $residuals
            reason = if ($exact) { 'Both source-backed floor mouths match exactly; full-solid and clearance acceptance remains separate.' } else { 'First lane aligned for inspection only; residuals remain explicit. Not a production assembly fallback.' }
        })
    }
    $reservations = @(foreach ($instance in $instances) {
        $source = @($registry | Where-Object template -eq $instance.template)[0]
        $localOrigin = [pscustomobject]@{ x = $instance.origin.x - $Origin.x; y = $instance.origin.y - $Origin.y; z = $instance.origin.z - $Origin.z }
        $nominal = [pscustomobject]@{
            x = [pscustomobject]@{ min = -$source.width * 320; max = $source.width * 320 }
            y = [pscustomobject]@{ min = -$source.height * 320; max = $source.height * 320 }
            z = $source.envelope.z
        }
        $bounds = Convert-ZMMotorwayEnvelope $nominal $instance.yaw
        $winding = Convert-ZMMotorwayEnvelope $source.envelope $instance.yaw
        foreach ($axis in @('x', 'y', 'z')) {
            $bounds.$axis.min += $localOrigin.$axis
            $bounds.$axis.max += $localOrigin.$axis
            $winding.$axis.min += $localOrigin.$axis
            $winding.$axis.max += $localOrigin.$axis
        }
        $leases = @(for ($tileY = -4; $tileY -le 4; $tileY++) {
            for ($tileX = -4; $tileX -le 4; $tileX++) {
                if ($bounds.x.min -lt $tileX * 640 + 320 -and $bounds.x.max -gt $tileX * 640 - 320 -and $bounds.y.min -lt -$tileY * 640 + 320 -and $bounds.y.max -gt -$tileY * 640 - 320) {
                    $ring = [Math]::Max([Math]::Abs($tileX), [Math]::Abs($tileY))
                    [pscustomobject]@{ tileX = $tileX; tileY = $tileY; ring = $(if ($ring -le 2) { 'core' } elseif ($ring -eq 3) { 'border' } else { 'outer' }); owner = $instance.owner; emitsInstance = $false }
                }
            }
        })
        [pscustomobject]@{
            owner = $instance.owner; template = $instance.template; yaw = $instance.yaw
            authoredWidth = $source.width; authoredHeight = $source.height
            width = $(if ($instance.yaw -in @(90, 270)) { $source.height } else { $source.width })
            height = $(if ($instance.yaw -in @(90, 270)) { $source.width } else { $source.height })
            originCellLocal = $localOrigin; emitsInstance = $true; slots = $leases
            nominalBoundsCellLocal = $bounds; windingBoundsCellLocal = $winding
            windingWithinCellFrame = $winding.x.min -ge -2880 -and $winding.x.max -le 2880 -and $winding.y.min -ge -2880 -and $winding.y.max -le 2880
            clearanceStatus = 'unknown_models_displacements_pedestrians_and_underlay'
        }
    })
    $overlaps = @(for ($a = 0; $a -lt $reservations.Count; $a++) {
        for ($b = $a + 1; $b -lt $reservations.Count; $b++) {
            $first = $reservations[$a].windingBoundsCellLocal
            $second = $reservations[$b].windingBoundsCellLocal
            if ($first.x.min -lt $second.x.max -and $first.x.max -gt $second.x.min -and $first.y.min -lt $second.y.max -and $first.y.max -gt $second.y.min -and $first.z.min -lt $second.z.max -and $first.z.max -gt $second.z.min) {
                [pscustomobject]@{ first = $reservations[$a].owner; second = $reservations[$b].owner; status = 'conservative_envelope_overlap_requires_solid_clearance_review' }
            }
        }
    })
    return [pscustomobject]@{
        id = $Id; piece = $Piece.template; yaw = $Yaw; origin = $mainOrigin
        centeredCellCore = $centeredCrossroads
        instances = @($instances); connections = @($diagnostics); reservations = $reservations; envelopeOverlaps = $overlaps
    }
}

function Write-AssemblyVmf {
    param([string]$Path, [object[]]$Cases)

    $text = [System.Text.StringBuilder]::new()
    [void]$text.AppendLine("versioninfo`n{`n`t`"editorversion`" `"400`"`n`t`"mapversion`" `"1`"`n`t`"formatversion`" `"100`"`n}")
    [void]$text.AppendLine("world`n{`n`t`"id`" `"1`"`n`t`"classname`" `"worldspawn`"`n`t`"skyname`" `"sky_day01_01`"`n}")
    $id = 2
    foreach ($case in $Cases) {
        foreach ($instance in $case.instances) {
            $baseUri = [System.Uri]((Split-Path -Parent $Path).TrimEnd('\') + '\')
            $file = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri([System.Uri]$instance.template).ToString())
            $o = $instance.origin
            $originText = '{0} {1} {2}' -f $o.x.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $o.y.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $o.z.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            [void]$text.AppendLine("entity`n{`n`t`"id`" `"$id`"`n`t`"classname`" `"func_instance`"`n`t`"targetname`" `"$($instance.owner)`"`n`t`"file`" `"$file`"`n`t`"origin`" `"$originText`"`n`t`"angles`" `"0 $($instance.yaw) 0`"`n`t`"fixup_style`" `"0`"`n}")
            $id++
        }
        foreach ($connection in $case.connections) {
            foreach ($port in $connection.ports) {
                $p = $port.position
                $originText = '{0} {1} {2}' -f $p.x.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $p.y.ToString('R', [Globalization.CultureInfo]::InvariantCulture), ($p.z + 48).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
                [void]$text.AppendLine("entity`n{`n`t`"id`" `"$id`"`n`t`"classname`" `"info_target`"`n`t`"targetname`" `"$($case.id)/$($connection.mouth)/$($connection.status)`"`n`t`"origin`" `"$originText`"`n}")
                $id++
            }
        }
        [void]$text.AppendLine("cameras`n{`n`t`"activecamera`" `"0`"")
        foreach ($case in $Cases) {
            $o = $case.origin
            $cameraPosition = '[{0} {1} {2}]' -f ($o.x - 2600).ToString('R', [Globalization.CultureInfo]::InvariantCulture), ($o.y - 2600).ToString('R', [Globalization.CultureInfo]::InvariantCulture), '2800'
            $cameraLook = '[{0} {1} {2}]' -f $o.x.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $o.y.ToString('R', [Globalization.CultureInfo]::InvariantCulture), '68'
            [void]$text.AppendLine("`tcamera`n`t{`n`t`t`"position`" `"$cameraPosition`"`n`t`t`"look`" `"$cameraLook`"`n`t}")
        }
        [void]$text.AppendLine("}")
    }
    Write-TextFileIfChanged -Path $Path -Content $text.ToString() | Out-Null
}

$overviewCases = @(for ($index = 0; $index -lt $registry.Count; $index++) {
    $origin = [pscustomobject]@{
        x = [double](($index % 3) * 9000 - 9000)
        y = [double](9000 - [math]::Floor($index / 3) * 9000)
        z = 0.0
    }
    New-AssemblyCase $registry[$index] 0 $origin ("case$index/" + [IO.Path]::GetFileNameWithoutExtension($registry[$index].template))
})
$overviewPath = Join-Path $OutputDirectory 'motorway_phase_b_preview.vmf'
Write-AssemblyVmf $overviewPath $overviewCases
foreach ($piece in $registry) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($piece.template)
    $cases = @(foreach ($yaw in @(0, 90, 180, 270)) {
        $origin = [pscustomobject]@{ x = [double]$(if ($yaw -in @(0, 180)) { -4800 } else { 4800 }); y = [double]$(if ($yaw -in @(0, 90)) { 4800 } else { -4800 }); z = 0.0 }
        New-AssemblyCase $piece $yaw $origin "$name/yaw$yaw"
    })
    Write-AssemblyVmf (Join-Path $OutputDirectory "$name-rotations.vmf") $cases
    foreach ($case in $cases) { $reportCases.Add($case) }
}
$report = [ordered]@{
    schemaVersion = 1
    status = 'Hammer_integration_inspection_not_release_generation'
    supportPolicy = [ordered]@{
        exactMotorwaySeam = 'candidate_only_until_full_solid_and_clearance_validation'
        incompatibleMotorwaySeam = 'unsupported_connector_deferred'
        roadApproach = 'unsupported_approach_connector_deferred'
        diagnosticFixtures = 'inspection_only_never_planner_fallback'
    }
    overview = $overviewPath
    registry = $registry
    ordinaryRoadApproach = [ordered]@{ source = $approachPath; sha256 = $approachHash; faces = $approachFaces; status = 'measured_saved_floors_no_approved_connection' }
    cases = @($reportCases)
    limits = @('Diagnostic-only seams are present for inspection and are never accepted production fallbacks.', 'Mismatched motorway seams and road approaches are unsupported until separate connector assets are authorized and validated.', 'Exact floor seams remain candidates until full-solid/prop/clearance collision validation.', 'Not compiled/staged; no normal planner or source assets changed.')
}
Write-TextFileIfChanged -Path (Join-Path $OutputDirectory 'assembly-report.json') -Content ($report | ConvertTo-Json -Depth 18) | Out-Null
[pscustomobject]@{
    overview = $overviewPath; rotationFixtures = $registry.Count; cases = $reportCases.Count
    exactSeams = @($reportCases.connections | Where-Object status -eq 'exact_floor_seam').Count
    diagnosticSeams = @($reportCases.connections | Where-Object status -eq 'diagnostic_seam_not_approved').Count
    pendingApproaches = @($reportCases.connections | Where-Object status -eq 'approach_contract_pending').Count
    exactSurfaceCandidates = @($reportCases.connections | Where-Object disposition -eq 'exact_surface_candidate_clearance_pending').Count
    unsupportedMotorwayMouths = @($reportCases.connections | Where-Object disposition -eq 'unsupported_connector_deferred').Count
    unsupportedRoadMouths = @($reportCases.connections | Where-Object disposition -eq 'unsupported_approach_connector_deferred').Count
}
