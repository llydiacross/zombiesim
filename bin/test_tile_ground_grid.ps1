Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'tile_ground_grid.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'tiletemplates\terrain\tile_grass.vmf'
$text = [IO.File]::ReadAllText($path)
$script:checks = 0
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
$reference = Get-ZMTileGroundReference $path
Assert ($reference.complete -and $reference.centerX -eq 0 -and $reference.centerY -eq 0) 'Canonical ground must establish the centered one-tile footprint.'
Assert (@(Get-ZMTileGroundGridIssues $path).Count -eq 0) 'Canonical ground must not warn.'
$fixture = $text + "`r`nentity`r`n{`r`n`t`"id`" `"999`"`r`n`t`"classname`" `"prop_dynamic`"`r`n`t`"origin`" `"10 20 30`"`r`n`t`"model`" `"models/test.mdl`"`r`n}`r`n"
$shifted = Move-ZMTileGroundOriginText $fixture ([pscustomobject]@{ complete = $true; source = $path; centerX = 0.0; centerY = -0.388 })
$offsetReference = Get-ZMTileGroundReference $path -Text $shifted
Assert ($offsetReference.complete -and [Math]::Abs($offsetReference.centerY - 0.388) -lt 0.000000000001) 'Ground bounds must detect the shared source offset.'
$issues = @(Get-ZMTileGroundGridIssues $path -Text $shifted)
Assert ($issues.Count -eq 1 -and $issues[0].repairable) 'Plain translated ground must be repairable.'
$groundOnly = Repair-ZMTileGroundGridText $shifted $issues
Assert ($groundOnly.Contains('"origin" "10 20.388 30"')) 'Ground-only repair must leave prop origins unchanged.'
Assert (@(Get-ZMTileGroundGridIssues $path -Text $groundOnly).Count -eq 0) 'Ground repair must be idempotently aligned.'
Assert ((Repair-ZMTileGroundGridText $groundOnly @()) -ceq $groundOnly) 'Repeated repair must not rewrite geometry.'
$centered = Move-ZMTileGroundOriginText $shifted $offsetReference
$centered = Repair-ZMTileGroundGridText $centered @(Get-ZMTileGroundGridIssues $path -Text $centered)
$centeredTree = [ZombieSim.Skybox.KeyValuesParser]::Parse($centered)
$prop = $centeredTree.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('id') -eq '999' }
$origin = [ZombieSim.Skybox.Vec3]::Parse($prop.Get('origin'))
Assert ($origin.X -eq 10 -and [Math]::Abs($origin.Y - 20) -lt 0.000000000001 -and $origin.Z -eq 30) 'Whole-template correction must restore prop placement relative to ground within double arithmetic roundoff.'
$after = Get-ZMTileGroundReference $path -Text $centered
Assert ($after.complete -and $after.centerX -eq 0 -and $after.centerY -eq 0) 'Whole-template correction must establish exact origin centering.'
$tree = [ZombieSim.Skybox.KeyValuesParser]::Parse($centered)
foreach ($side in $tree.Child('world').Child('solid').Children | Where-Object Name -eq side) {
    $plane = @([regex]::Matches($side.Get('plane'), '\(([^)]+)\)') | ForEach-Object { $_.Groups[1].Value })
    $vertices = @($side.Child('vertices_plus').GetAll('v'))
    foreach ($point in $plane) { Assert ($point -in $vertices) 'Repaired plane points must match saved winding vertices.' }
}
$originalTree = [ZombieSim.Skybox.KeyValuesParser]::Parse($fixture)
$shiftedTree = [ZombieSim.Skybox.KeyValuesParser]::Parse($shifted)
foreach ($side in $originalTree.Child('world').Child('solid').Children | Where-Object Name -eq side) {
    $shiftedSide = $shiftedTree.Child('world').Child('solid').Children | Where-Object { $_.Name -eq 'side' -and $_.Get('id') -eq $side.Get('id') }
    foreach ($axis in @('uaxis', 'vaxis')) {
        $old = @([regex]::Matches($side.Get($axis), '-?\d+(?:\.\d+)?') | ForEach-Object { [double]$_.Value })
        $new = @([regex]::Matches($shiftedSide.Get($axis), '-?\d+(?:\.\d+)?') | ForEach-Object { [double]$_.Value })
        Assert ([Math]::Abs($old[3] - ($new[3] + $new[1] * 0.388 / $new[4])) -lt 0.000000000001) 'Whole-template translation must preserve locked texture coordinates.'
    }
}
$geometryPattern = '"(?:plane|v|origin|uaxis|vaxis)"\s+"[^"]+"'
Assert ([regex]::Replace($fixture, $geometryPattern, '') -ceq [regex]::Replace($shifted, $geometryPattern, '')) 'Translation must preserve IDs, classes, materials, models, editor data and line endings.'
$decoy = $shifted.Replace('DE_CBBLE/GRASSFLOOR01', 'NATURE/ROCKWALL001A')
Assert (@(Get-ZMTileGroundGridIssues $path -Text $decoy).Count -eq 0) 'Unknown decorative material must not identify ground.'
$decoy = $shifted.Replace('BUILDING_TEMPLATE/BUILDING_TEMPLATE028A', 'DE_CBBLE/GRASSFLOOR01')
Assert (@(Get-ZMTileGroundGridIssues $path -Text $decoy).Count -eq 0) 'Grass material alone must not identify a standard base.'
$decoy = $shifted.Replace('vertices_plus', "dispinfo`r`n`t`t`t{`r`n`t`t`t}`r`n`t`t`tvertices_plus")
Assert (@(Get-ZMTileGroundGridIssues $path -Text $decoy).Count -eq 0) 'Displacements must not be snapped as plain ground.'
$failed = $false
try { Move-ZMTileGroundOriginText $decoy $offsetReference | Out-Null } catch { $failed = $true }
Assert $failed 'Origin correction must reject displacement transforms it cannot safely apply.'
$unknownReference = Get-ZMTileGroundReference (Join-Path $root 'tiletemplates\fixture_2x2.vmf') -Text $shifted
Assert (-not $unknownReference.complete) 'Incomplete ground cannot establish a declared multi-tile center.'
$failed = $false
try { Move-ZMTileGroundOriginText $shifted $unknownReference | Out-Null } catch { $failed = $true }
Assert $failed 'Asymmetric/incomplete ground must not trigger origin correction.'
$gross = Move-ZMTileGroundOriginText $fixture ([pscustomobject]@{ complete = $true; source = $path; centerX = -8.0; centerY = 0.0 })
$grossIssues = @(Get-ZMTileGroundGridIssues $path -Text $gross)
Assert ($grossIssues.Count -eq 1 -and -not $grossIssues[0].repairable) 'Larger uncertain offsets must warn rather than snap ground alone.'
$failed = $false
try { Repair-ZMTileGroundGridText $gross $grossIssues | Out-Null } catch { $failed = $true }
Assert $failed 'Uncertain ground-only repairs must fail explicitly.'
$parkPath = Join-Path $root 'tiletemplates\buildings\tile_park_1a_2x.vmf'
$park = Get-ZMTileGroundReference $parkPath
Assert ($park.complete -and $park.baseCount -eq 31 -and $park.centerX -eq 0) 'Partitioned park ground must prove the complete declared footprint from its actual nonoverlapping pieces.'
$parkText = [IO.File]::ReadAllText($parkPath)
$parkTree = [ZombieSim.Skybox.KeyValuesParser]::Parse($parkText)
$parkDirection = @($parkTree.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'zn_tile_direction' })
Assert ($parkDirection.Count -eq 1 -and $parkDirection[0].Get('origin') -eq '0 -640 32') 'The centered park must retain its semantic south-edge direction marker independently of the former ground offset.'
$parkMoved = Move-ZMTileGroundOriginText $parkText $park
$parkAfter = Get-ZMTileGroundReference $parkPath -Text $parkMoved
Assert ($parkAfter.complete -and $parkAfter.centerX -eq 0 -and $parkAfter.centerY -eq 0) 'A proven partitioned footprint centers as a whole without snapping intentional internal boundaries.'
foreach ($material in @('CS_HAVANA/GROUND01GRASS', 'CS_HAVANA/SWAMPDIRT01', 'NATURE/SANDFLOOR005A', 'GM_CONSTRUCT/FLATGRASS_2', 'DEV/VALUESAND40')) {
    Assert (@(Get-ZMTileGroundGridIssues $path -Text $shifted.Replace('DE_CBBLE/GRASSFLOOR01', $material)).Count -eq 1) "Existing standard base material must be supported: $material"
}
Write-Host "Tile ground grid: $script:checks assertions passed."
