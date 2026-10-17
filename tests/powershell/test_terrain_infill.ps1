param([string]$OutputDirectory = '', [switch]$SizedInfill, [switch]$CompleteInfill, [switch]$Mixed)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'terrain_infill.psm1') -Force
$root = $testsRepoRoot
if ($Mixed) { $CompleteInfill = $true }
if ($CompleteInfill) { $SizedInfill = $true }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root $(if ($Mixed) { 'generated\phase_e_mixed_infill_cells' } else { 'generated\phase_b_rectangular_infill_cells' }) }
$sourceRoot = Join-Path $root 'tiletemplates'
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Terrain infill: $Message" }
    $script:passed++
}
function New-TestRectangle {
    param([double]$X, [double]$Y, [double]$Width, [double]$Height)
    return ,([ZombieSim.Infill.Point[]]@(
        [ZombieSim.Infill.Point]::new($X, $Y), [ZombieSim.Infill.Point]::new($X + $Width, $Y),
        [ZombieSim.Infill.Point]::new($X + $Width, $Y + $Height), [ZombieSim.Infill.Point]::new($X, $Y + $Height)
    ))
}
$left = New-TestRectangle 0 0 320 320
$right = New-TestRectangle 320 0 320 320
$empty = [ZombieSim.Infill.Point[][]]@()
$merged = [ZombieSim.Infill.Geometry]::MergeRectangles([ZombieSim.Infill.Point[][]]@($left, $right), $empty)
Assert ($merged.Count -eq 1 -and [ZombieSim.Infill.Geometry]::Area($merged[0]) -eq 204800) 'Adjacent rectangles merge without changing coverage.'
$notch = New-TestRectangle 320 0 320 160
Assert ([ZombieSim.Infill.Geometry]::MergeRectangles([ZombieSim.Infill.Point[][]]@($left, $notch), $empty).Count -eq 2) 'A concave union is never replaced by a polygon filler.'
$separated = New-TestRectangle 320.000001 0 320 320
Assert ([ZombieSim.Infill.Geometry]::MergeRectangles([ZombieSim.Infill.Point[][]]@($left, $separated), $empty).Count -eq 2) 'A real fractional gap is not rounded away.'
$triangle = [ZombieSim.Infill.Point[]]@(
    [ZombieSim.Infill.Point]::new(0, 0), [ZombieSim.Infill.Point]::new(320, 0), [ZombieSim.Infill.Point]::new(0, 320)
)
Assert ([ZombieSim.Infill.Geometry]::MergeRectangles([ZombieSim.Infill.Point[][]]@($triangle, $right), $empty).Count -eq 2) 'Angled structural fragments cannot enter rectangular consolidation.'
Assert (-not [ZombieSim.Infill.Geometry]::Intersects($left, $right)) 'Exact edge contact is not ground overlap.'
$tiny = New-TestRectangle 319.999999 0 1 320
Assert ([ZombieSim.Infill.Geometry]::Intersects($left, $tiny)) 'One-millionth-unit ground overlap remains measurable.'
$rejected = $false
try { Get-ZMInfillPatchName 23.038 39.387 | Out-Null } catch { $rejected = $true }
Assert $rejected 'Decimal-sized patches fail explicitly.'
$belowMinimum = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 0; minY = 0; width = 3; height = 320 })
Assert ($belowMinimum.pieces.Count -eq 0 -and $belowMinimum.unfilled.Count -gt 0) 'No dimension below4 gets a filler.'
$u4 = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 0; minY = 0; width = 4; height = 320 })
Assert ($u4.pieces.Count -eq 2 -and @($u4.pieces | Where-Object width -ne 4).Count -eq 0 -and @($u4.pieces | Where-Object height -notin @(256, 64)).Count -eq 0) 'Exactly4 is accepted with power-of-two height patches.'
$u8 = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 0; minY = 0; width = 8; height = 320 })
Assert ($u8.pieces.Count -eq 2 -and @($u8.pieces | Where-Object width -ne 8).Count -eq 0 -and @($u8.pieces | Where-Object height -notin @(256, 64)).Count -eq 0) 'Exactly8 is accepted with power-of-two height patches.'
$observedTGap = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 1267; minY = 960; width = 13; height = 256 })
Assert ((@($observedTGap.pieces.width | Sort-Object -Unique) -join ',') -eq '4,8' -and $observedTGap.unfilled.Count -eq 1 -and $observedTGap.unfilled[0].width -eq 1) 'The observed13x256 T-junction gap emits U8+U4 and leaves only the sub4 remainder.'
$threshold = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 0; minY = 0; width = 16; height = 320 })
Assert ($threshold.pieces.Count -eq 2 -and @($threshold.pieces | Where-Object width -ne 16).Count -eq 0) 'Exactly16 is accepted;320 extra-patch extent decomposes into256+64.'
$split = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 0; minY = 0; width = 304; height = 320 })
$splitArea = ($split.pieces | ForEach-Object { $_.width * $_.height } | Measure-Object -Sum).Sum
Assert ($split.unfilled.Count -eq 0 -and $splitArea -eq 304 * 320) '304x320 decomposes into power-of-two rectangles without rounding or omitted area.'
$remainder = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = 0; minY = 0; width = 15; height = 32 })
Assert ((@($remainder.pieces.width | Sort-Object -Unique) -join ',') -eq '4,8' -and $remainder.unfilled[0].width -eq 3) 'Sub4 remainder stays explicitly on the default floor rather than producing a thin patch.'

& (Join-Path $testsBinDirectory 'create_terrain_infill_templates.ps1') | Out-Null
$names = @('terrain\infill\tile_ground_full.vmf', 'terrain\infill\tile_ground_half.vmf', 'terrain\infill\tile_ground_quarter.vmf')
foreach ($name in $names) {
    $coverage = @(Get-ZMInfillGroundCoverage (Join-Path $sourceRoot $name) ([pscustomobject]@{ x = 0; y = 0; z = 0 }) 0)
    Assert ($coverage.Count -eq 1 -and $coverage[0].role -eq 'recognized_ground') 'Full/half/quarter bases are recognized ground, not nominal reservations.'
    $area = if ($name -like '*full*') { 409600 } elseif ($name -like '*half*') { 204800 } else { 102400 }
    Assert ([ZombieSim.Infill.Geometry]::Area($coverage[0].polygon) -eq $area) 'Canonical rectangular base has its exact approved area.'
}
$fixtureDirectory = Join-Path $OutputDirectory 'classifier-fixture'
[IO.Directory]::CreateDirectory($fixtureDirectory) | Out-Null
$fixturePath = Join-Path $fixtureDirectory 'tile_fixture.vmf'
$baseText = [IO.File]::ReadAllText((Join-Path $sourceRoot 'terrain\tile_grass.vmf'))
$angled = $baseText.Replace('BUILDING_TEMPLATE/BUILDING_TEMPLATE028A', 'CONCRETE/CONCRETEFLOOR037A')
[IO.File]::WriteAllText($fixturePath, $angled, [Text.UTF8Encoding]::new($false))
try {
    $coverage = @(Get-ZMInfillGroundCoverage $fixturePath ([pscustomobject]@{ x = 0; y = 0; z = 0 }) 0)
    Assert (@($coverage | Where-Object role -eq 'reserved_nonstandard_ground_requires_review').Count -eq 1) 'Grass-looking structural construction is not classified as standard ground.'
} finally { Remove-Item -LiteralPath $fixturePath }
$bushFloorPath = Join-Path $sourceRoot 'decorations\tile_bushes_1aa.vmf'
$bushFloorCoverage = @(Get-ZMInfillGroundCoverage $bushFloorPath ([pscustomobject]@{ x = -1280; y = -1280; z = 0 }) 0)
$authoredBounds = @($bushFloorCoverage | Where-Object role -eq 'authored_geometry_bounds')
$concreteFloor = @($authoredBounds | Where-Object solidId -eq '1945')[0].polygon
$floorBoundsX = $concreteFloor | Measure-Object X -Minimum -Maximum
$floorBoundsY = $concreteFloor | Measure-Object Y -Minimum -Maximum
Assert ($floorBoundsX.Minimum -eq -1584 -and $floorBoundsX.Maximum -eq -1344 -and $floorBoundsY.Minimum -eq -1600 -and $floorBoundsY.Maximum -eq -1216) 'Geometry bounds preserve the concrete-floor footprint at its authored position.'
$dirtLip = @($authoredBounds | Where-Object solidId -eq '1946')[0].polygon
$lipBoundsX = $dirtLip | Measure-Object X -Minimum -Maximum
$lipBoundsY = $dirtLip | Measure-Object Y -Minimum -Maximum
Assert ($lipBoundsX.Minimum -eq -1600 -and $lipBoundsX.Maximum -eq -1584 -and $lipBoundsY.Minimum -eq -1600 -and $lipBoundsY.Maximum -eq -1216) 'Geometry bounds preserve the16-unit dirt-lip footprint without material matching.'
$geometryFixturePath = Join-Path $fixtureDirectory 'tile_bushes_custom_material.vmf'
$sourceText = [IO.File]::ReadAllText($bushFloorPath)
$customMaterialText = $sourceText.Replace('CONCRETE/CONCRETEFLOOR015A', 'ARTIST/ANY_TEXTURE')
Assert ($customMaterialText -cne $sourceText) 'The material-independent fixture changes the source floor texture.'
[IO.File]::WriteAllText($geometryFixturePath, $customMaterialText, [Text.UTF8Encoding]::new($false))
try {
    $customCoverage = @(Get-ZMInfillGroundCoverage $geometryFixturePath ([pscustomobject]@{ x = -1280; y = -1280; z = 0 }) 0)
    $customFloor = @($customCoverage | Where-Object { $_.role -eq 'authored_geometry_bounds' -and $_.solidId -eq '1945' })
    Assert ($customFloor.Count -eq 1 -and [ZombieSim.Infill.Geometry]::Area($customFloor[0].polygon) -eq 240 * 384) 'A nonstandard artist-selected texture retains the same localized geometry exclusion.'
} finally { Remove-Item -LiteralPath $geometryFixturePath }
$rotatedSurfaces = @(Get-ZMInfillGroundCoverage $bushFloorPath ([pscustomobject]@{ x = -1280; y = -1280; z = 0 }) 90 | Where-Object { $_.role -eq 'authored_geometry_bounds' })
$rotatedFloor = @($rotatedSurfaces | Where-Object solidId -eq '1945')[0].polygon
$rotatedFloorBoundsX = $rotatedFloor | Measure-Object X -Minimum -Maximum
$rotatedFloorBoundsY = $rotatedFloor | Measure-Object Y -Minimum -Maximum
Assert ($rotatedFloorBoundsX.Minimum -eq -1344 -and $rotatedFloorBoundsX.Maximum -eq -960 -and $rotatedFloorBoundsY.Minimum -eq -1584 -and $rotatedFloorBoundsY.Maximum -eq -1344) 'Geometry bounds rotate with the source instance.'
$rotatedLip = @($rotatedSurfaces | Where-Object solidId -eq '1946')[0].polygon
$rotatedLipBoundsX = $rotatedLip | Measure-Object X -Minimum -Maximum
$rotatedLipBoundsY = $rotatedLip | Measure-Object Y -Minimum -Maximum
Assert ($rotatedLipBoundsX.Minimum -eq -1344 -and $rotatedLipBoundsX.Maximum -eq -960 -and $rotatedLipBoundsY.Minimum -eq -1600 -and $rotatedLipBoundsY.Maximum -eq -1584) 'Geometry bounds rotate with the source instance.'

$sourceHashes = @{}
foreach ($file in Get-ChildItem (Join-Path $sourceRoot 'terrain\infill') -Filter '*.vmf' -File) {
    $sourceHashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName).Hash
}
& (Join-Path $testsBinDirectory 'build_motorway_cell_preview.ps1') -Complex -Mixed:$Mixed -SizedInfill:$SizedInfill -CompleteInfill:$CompleteInfill -OutputDirectory $OutputDirectory | Out-Null
if (-not $?) { throw 'Rectangular ground cell generation failed.' }
$plan = Get-Content -Raw (Join-Path $OutputDirectory 'plan.json') | ConvertFrom-Json
$total = 0
$fullCount = 0
$authoredBoundsSeen = $false
foreach ($cell in $plan.cells) {
    $vmf = Join-Path $OutputDirectory ('src\' + $cell.cellTemplateFilename)
    $layout = Get-Content -Raw ([IO.Path]::ChangeExtension($vmf, '.layout.json')) | ConvertFrom-Json
    $infill = $layout.terrainInfill
    Assert ($layout.vmfSha256 -ceq (Get-FileHash $vmf).Hash.ToLowerInvariant()) 'Ground metadata matches the actual current VMF.'
    if ($CompleteInfill -and [IO.Path]::GetFileName($cell.motorwayCellInspection.template) -eq 'tile_motorway_corner_5x3.vmf') {
        Assert ($infill.placements.Count -gt 0) 'Complete infill includes the motorway corner rather than skipping its patch pass.'
        Assert (@($infill.partialGaps | Where-Object status -eq 'unfilled_partial_slot_requires_sized_source_or_approved_clipping').Count -eq 0) 'Motorway corner has no silently skipped rectangular infill gaps.'
        Assert (@($infill.unfilledRectangles | Where-Object { $_.width -ge 4 -and $_.height -ge 4 }).Count -eq 0) 'Motorway corner reports only the already-approved fractional/sub4 leftovers.'
    }
    if ([IO.Path]::GetFileName($cell.motorwayCellInspection.template) -eq 'tile_motorway_tjunction_6x3.vmf') {
        $tGapPatches = @($infill.placements | Where-Object { $_.origin.x -ge 1266 -and $_.origin.x -lt 1280 -and ($_.origin.y - $_.height / 2) -lt 1216 -and ($_.origin.y + $_.height / 2) -gt 960 -and $_.width -in @(4, 8) })
        Assert (@($tGapPatches.width | Sort-Object -Unique) -contains 4 -and @($tGapPatches.width | Sort-Object -Unique) -contains 8) 'The actual T-junction gap emits both approved U4 and U8 patches.'
    }
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmf))
    $instances = @($tree.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'func_instance' })
    $fillInstances = @($instances | Where-Object { $_.Get('targetname') -like 'zm_terrain_infill:*' })
    Assert ($fillInstances.Count -eq $infill.placements.Count) 'Every rectangle emits exactly once.'
    $coverage = @(foreach ($instance in $instances | Where-Object { $_.Get('targetname') -notlike 'zm_terrain_infill:*' -and $_.Get('targetname') -ne 'zm_skybox_room' }) {
        $path = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $vmf) $instance.Get('file').Replace('/', '\')))
        $origin = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
        Get-ZMInfillGroundCoverage $path ([pscustomobject]@{ x = $origin.X; y = $origin.Y; z = $origin.Z }) ([int]$instance.Get('angles').Split(' ')[1])
    })
    if (@($coverage | Where-Object role -eq 'authored_geometry_bounds').Count -gt 0) { $authoredBoundsSeen = $true }
    $allPolygons = [Collections.Generic.List[ZombieSim.Infill.Point[]]]::new()
    foreach ($record in $coverage) { $allPolygons.Add($record.polygon) }
    $fills = [Collections.Generic.List[ZombieSim.Infill.Point[]]]::new()
    $area = 0
    foreach ($placement in $infill.placements) {
        Assert ($placement.template -notlike '*_shape_*') 'Polygon fillers are prohibited.'
        $width = [double]$placement.width; $height = [double]$placement.height
        Assert ($width -eq [Math]::Round($width) -and $height -eq [Math]::Round($height) -and $width -le 640 -and $height -le 640) 'Ground rectangles have integer dimensions bounded by a full tile.'
        Assert ($width -ge 4 -and $height -ge 4) 'No emitted ground infill is thinner than4.'
        if ($placement.template -notin $names) {
            Assert ($width -in @(4, 8, 16, 32, 64, 128, 256, 512) -and $height -in @(4, 8, 16, 32, 64, 128, 256, 512)) 'Extra patches use strict power-of-two dimensions.'
        }
        $matching = @($fillInstances | Where-Object { $_.Get('targetname') -eq "zm_terrain_$($placement.owner)" })
        Assert ($matching.Count -eq 1) 'Ground owner is unique.'
        $origin = [ZombieSim.Skybox.Vec3]::Parse($matching[0].Get('origin'))
        Assert ($origin.X -eq [double]$placement.origin.x -and $origin.Y -eq [double]$placement.origin.y -and $origin.Z -eq 0) 'Actual rectangle placement matches metadata.'
        Assert ($matching[0].Get('angles') -eq "0 $($placement.yaw) 0") 'Authored rectangular base is rotated, never stretched.'
        $sourcePath = Join-Path $sourceRoot $placement.template
        $actual = @(Get-ZMInfillGroundCoverage $sourcePath ([pscustomobject]@{ x = $origin.X; y = $origin.Y; z = 0 }) $placement.yaw)
        Assert ($actual.Count -eq 1 -and $actual[0].role -eq 'recognized_ground' -and $actual[0].polygon.Count -eq 4) 'Actual emitted source is a recognized rectangular ground base.'
        Assert ([ZombieSim.Infill.Geometry]::Area($actual[0].polygon) -eq $width * $height) 'Source footprint equals its declared integer-sized rectangle.'
        foreach ($point in $actual[0].polygon) { Assert ($point.X -eq [Math]::Round($point.X) -and $point.Y -eq [Math]::Round($point.Y)) 'Actual world ground edges are integer-aligned.' }
        foreach ($other in $fills) { Assert (-not [ZombieSim.Infill.Geometry]::Intersects($actual[0].polygon, $other)) 'Emitted rectangles never overlap one another.' }
        foreach ($record in $coverage) { Assert (-not [ZombieSim.Infill.Geometry]::Intersects($actual[0].polygon, $record.polygon)) 'Rectangles do not overlap recognized ground or explicit protected reservations.' }
        $sourceTree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($sourcePath))
        $sides = @($sourceTree.Child('world').Child('solid').Children | Where-Object Name -eq side)
        Assert ($sides.Count -eq 6) 'Ground source has exactly six box faces.'
        foreach ($side in $sides) {
            $vertices = @($side.Child('vertices_plus').GetAll('v'))
            foreach ($point in [regex]::Matches($side.Get('plane'), '\(([^)]+)\)')) { Assert ($point.Groups[1].Value -in $vertices) 'Brush planes match actual saved box windings.' }
        }
        $fills.Add($actual[0].polygon); $allPolygons.Add($actual[0].polygon)
        $area += $width * $height
        if ($placement.template -like '*_full.vmf') { $fullCount++ }
    }
    Assert ($area -eq $infill.filledArea) 'Integer rectangle area equals emitted coverage exactly.'
    foreach ($gap in $infill.partialGaps) {
        Assert ($gap.rectangular) 'Ground gap metadata is rectangular, not a structural cut-out polygon.'
        if ($gap.status -in @('filled_by_standard_rectangles', 'partly_filled_standard_rectangles_remainder_reported')) { continue }
        Assert ($gap.status -in @('fractional_ground_boundary_requires_source_review', 'unfilled_partial_slot_requires_sized_source_or_approved_clipping')) 'Remaining ground gaps have explicit review status.'
        $allPolygons.Add([ZombieSim.Infill.Point[]]@($gap.polygon | ForEach-Object { [ZombieSim.Infill.Point]::new([double]$_.X, [double]$_.Y) }))
    }
    foreach ($gap in $infill.unfilledRectangles) {
        Assert ($gap.status -in @('fractional_ground_boundary_requires_source_review', 'below_u4_left_on_default_floor')) 'Each omitted rectangle records its fractional/sub4 reason.'
        Assert ($gap.width -lt 4 -or $gap.height -lt 4) 'Only sub4 remainders are left on the black floor; larger rectangular ground is not silently omitted.'
        $allPolygons.Add((New-TestRectangle $gap.minX $gap.minY $gap.width $gap.height))
    }
    foreach ($yaw in @(0, 90, 180, 270)) {
        $rotated = [Collections.Generic.List[ZombieSim.Infill.Point[]]]::new()
        foreach ($polygon in $allPolygons) {
            $rotated.Add([ZombieSim.Infill.Point[]]@($polygon | ForEach-Object {
                if ($yaw -eq 0) { [ZombieSim.Infill.Point]::new($_.X, $_.Y) }
                elseif ($yaw -eq 90) { [ZombieSim.Infill.Point]::new(-$_.Y, $_.X) }
                elseif ($yaw -eq 180) { [ZombieSim.Infill.Point]::new(-$_.X, -$_.Y) }
                else { [ZombieSim.Infill.Point]::new($_.Y, -$_.X) }
            }))
        }
        foreach ($y in 0..17) {
            foreach ($x in 0..17) {
                Assert ([ZombieSim.Infill.Geometry]::Uncovered($rotated.ToArray(), -2880 + $x * 320, -2880 + $y * 320, 320, 320).Count -eq 0) 'Recognized ground, integer rectangles and explicit exclusions account for every quarter at all cardinal rotations; this is not full-ground/clearance acceptance.'
            }
        }
    }
    $total += $infill.placements.Count
}
Assert ($fullCount -gt 0) 'Empty full-tile areas prefer 640x640 ground sources.'
Assert ($total -gt 0) 'Rectangular ground is emitted, not only planned.'
Assert $authoredBoundsSeen 'The complete-cell regression exercises source geometry bounds independent of material names.'
$usedTemplates = @($plan.cells | ForEach-Object {
    $layout = Get-Content -Raw (Join-Path $OutputDirectory ('src\' + [IO.Path]::ChangeExtension($_.cellTemplateFilename, '.layout.json'))) | ConvertFrom-Json
    $layout.terrainInfill.placements | ForEach-Object template
} | Sort-Object -Unique)
Assert ($usedTemplates.Count -le 67 -and $usedTemplates.Count -lt 75) 'Standardized sources stay within64power-of-two pairs plus3base sizes, below the former75active sources.'
Assert (@(Get-ChildItem (Join-Path $sourceRoot 'terrain\infill') -File | Where-Object { $_.Name -like 'tile_ground_shape_*' -or ($_.Name -like 'tile_ground_patch_*' -and $_.BaseName -match '\d+p\d+') }).Count -eq 0) 'Regeneration recreates neither rejected hashed shapes nor decimal-named sources.'
foreach ($path in $sourceHashes.Keys) { Assert ($sourceHashes[$path] -ceq (Get-FileHash $path).Hash) 'Regeneration never overwrites an existing artist-owned source.' }
Write-Host "Terrain infill: $passed assertions passed; $total integer rectangular instances ($fullCount full640 tiles). No polygon fillers. Fractional/nonstandard reservations and live collision remain explicit review gates."
