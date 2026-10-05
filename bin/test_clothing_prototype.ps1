Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_back_projection.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_artwork.psm1')
$root = Split-Path -Parent $PSScriptRoot
$gameDirectory = Split-Path -Parent (Split-Path -Parent $root)
$output = Join-Path $root 'generated\clothing_preview\prototype'
$definition = Get-Content -LiteralPath (Join-Path $root 'assets\clothing\prototype.json') -Raw | ConvertFrom-Json
$cases = [System.Collections.Generic.List[object]]::new()
function Assert-Clothing([string]$Name, [bool]$Passed) {
    $cases.Add([pscustomobject]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Clothing prototype regression failed: $Name" }
    Write-Host "PASS: $Name"
}
try {
    foreach ($garment in 'shirt_male', 'shirt_female', 'pants') {
        $isShirt = $garment.StartsWith('shirt_')
        $design = if ($isShirt) { $definition.shirt } else { $definition.pants }
        $innerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        if ($isShirt) {
            foreach ($polygon in $design.innerShirt.polygons.($garment.Substring(6))) {
                $points = [System.Drawing.PointF[]]::new($polygon.Count)
                for ($index = 0; $index -lt $polygon.Count; $index++) {
                    $points[$index] = [System.Drawing.PointF]::new($polygon[$index][0], $polygon[$index][1])
                }
                $innerPath.AddPolygon($points)
            }
        }
        $png = [System.Drawing.Bitmap]::new((Join-Path $output "source\prototype_$garment.png"))
        try {
            Assert-Clothing "$garment artwork is 1024-square" ($png.Width -eq 1024 -and $png.Height -eq 1024)
            $maskMatches = $true
            for ($y = 0; $y -lt 1024; $y += 8) {
                for ($x = 0; $x -lt 1024; $x += 8) {
                    $expected = 0
                    foreach ($region in $design.regions) {
                        if ($x -ge $region[0] -and $x -lt $region[0] + $region[2] -and
                            $y -ge $region[1] -and $y -lt $region[1] + $region[3]) { $expected = 255 }
                    }
                    if ($isShirt -and $design.innerShirt.mode -eq 'native' -and $innerPath.IsVisible($x, $y)) { $expected = 0 }
                    if ($png.GetPixel($x, $y).A -ne $expected) { $maskMatches = $false }
                }
            }
            Assert-Clothing "$garment alpha matches the source mask at 16384 sampled pixels" $maskMatches
            foreach ($point in @(@(900, 512), @(900, 660), @(128, 128), @(384, 128))) {
                Assert-Clothing "$garment preserves hand/footwear region $($point -join ',')" ($png.GetPixel($point[0], $point[1]).A -eq 0)
            }
            Assert-Clothing "$garment torso ownership is independent" ($png.GetPixel(200, 800).A -eq $(if ($isShirt) { 255 } else { 0 }))
            Assert-Clothing "$garment leg ownership is independent" ($png.GetPixel(700, 128).A -eq $(if ($garment -eq 'pants') { 255 } else { 0 }))
            if ($isShirt) {
                $point = if ($garment -eq 'shirt_male') { @(60, 652) } else { @(251, 708) }
                Assert-Clothing "$garment inner-shirt ownership is independent" ($png.GetPixel($point[0], $point[1]).A -eq $(if ($design.innerShirt.mode -eq 'native') { 0 } else { 255 }))
                if ($design.pattern -eq 'checker') {
                    $spacing = [int]$design.stripeSpacing
                    $x = [int]([math]::Ceiling(512 / $spacing) * $spacing + 2)
                    $y = [int]([math]::Ceiling(896 / $spacing) * $spacing + 2)
                    $first = $png.GetPixel($x, $y).ToArgb()
                    $next = $png.GetPixel($x + $spacing, $y).ToArgb()
                    Assert-Clothing "$garment checkers alternate horizontally and vertically" (
                        $first -ne $next -and $next -eq $png.GetPixel($x, $y + $spacing).ToArgb())
                    Assert-Clothing "$garment checkers repeat exactly every two squares" (
                        $first -eq $png.GetPixel($x + 2 * $spacing, $y).ToArgb() -and
                        $first -eq $png.GetPixel($x, $y + 2 * $spacing).ToArgb())
                }
            }
        } finally { $innerPath.Dispose(); $png.Dispose() }
        $directory = Join-Path $root 'content\materials\models\zombiesim\clothing'
        $vtf = [System.IO.File]::ReadAllBytes((Join-Path $directory "prototype_$garment.vtf"))
        Assert-Clothing "$garment VTF signature, size and alpha flag" (
            [System.Text.Encoding]::ASCII.GetString($vtf, 0, 4) -eq "VTF`0" -and
            [BitConverter]::ToUInt16($vtf, 16) -eq 1024 -and [BitConverter]::ToUInt16($vtf, 18) -eq 1024 -and
            ([BitConverter]::ToUInt32($vtf, 20) -band 12288) -ne 0)
        foreach ($extension in 'vtf', 'vmt') {
            $name = "prototype_$garment.$extension"
            $hash = (Get-FileHash -LiteralPath (Join-Path $output "game\materials\models\zombiesim\clothing\$name")).Hash
            foreach ($destination in $directory, (Join-Path $gameDirectory 'materials\models\zombiesim\clothing')) {
                Assert-Clothing "$name staging hash in $destination" ((Get-FileHash -LiteralPath (Join-Path $destination $name)).Hash -eq $hash)
            }
        }
        $tga = [System.IO.File]::ReadAllBytes((Join-Path $output "source\prototype_$garment.tga"))
        Assert-Clothing "$garment TGA retains transparent texels" ($tga[21] -eq 0)
    }
    $prints = Get-Content -LiteralPath (Join-Path $root 'assets\clothing\prints.json') -Raw | ConvertFrom-Json
    foreach ($garment in 'shirt_male', 'shirt_female', 'pants') {
        $isShirt = $garment.StartsWith('shirt_')
        $settings = if ($isShirt) { $prints.repeat.shirt } else { $prints.repeat.pants }
        $name = "prototype_${garment}_repeat"
        $image = [System.Drawing.Bitmap]::new((Join-Path $output "source\$name.png"))
        $base = [System.Drawing.Bitmap]::new((Join-Path $output "source\prototype_$garment.png"))
        $backMask = if ($isShirt) { New-ClothingBackMask ($garment.Substring(6)) } else { $null }
        try {
            $sameAlpha = $true
            $outsideUntouched = $true
            $spacingUntouched = $true
            $spacingFailures = [Collections.Generic.List[string]]::new()
            $changedCells = @{}
            $stepX = $settings.motifSize[0] + $settings.spacing[0]
            $stepY = $settings.motifSize[1] + $settings.spacing[1]
            $oldLogo = $definition.shirt.logo
            for ($y = 0; $y -lt 1024; $y += 4) {
                for ($x = 0; $x -lt 1024; $x += 4) {
                    $pixel = $image.GetPixel($x, $y)
                    $native = $base.GetPixel($x, $y)
                    if ($pixel.A -ne $native.A) { $sameAlpha = $false }
                    $logoPixel = $isShirt -and $x -ge $oldLogo.x -and $x -lt $oldLogo.x + $oldLogo.width -and
                        $y -ge $oldLogo.y -and $y -lt $oldLogo.y + $oldLogo.height
                    if ($native.A -eq 0 -and $pixel.ToArgb() -ne $native.ToArgb()) { $outsideUntouched = $false }
                    $tileX = (($x - $settings.offset[0]) % $stepX + $stepX) % $stepX
                    $tileY = (($y - $settings.offset[1]) % $stepY + $stepY) % $stepY
                    $projectedBack = $isShirt -and $backMask.GetPixel($x, $y).A -gt 0
                    if (-not $logoPixel -and -not $projectedBack -and ($tileX -ge $settings.motifSize[0] -or $tileY -ge $settings.motifSize[1]) -and
                        $pixel.ToArgb() -ne $native.ToArgb()) {
                        $spacingUntouched = $false
                        if ($spacingFailures.Count -lt 8) { $spacingFailures.Add("$x,$y") }
                    }
                    if (-not $logoPixel -and $pixel.ToArgb() -ne $native.ToArgb()) {
                        $column = [int][math]::Floor(($x - $settings.offset[0]) / $stepX)
                        $row = [int][math]::Floor(($y - $settings.offset[1]) / $stepY)
                        $changedCells["$column,$row"] = @($column, $row)
                    }
                }
            }
            Assert-Clothing "$garment repeat preserves skin/shoes/inner-shirt alpha at 65536 points" $sameAlpha
            Assert-Clothing "$garment repeat leaves excluded RGBA pixels untouched" $outsideUntouched
            Assert-Clothing "$garment repeat preserves nonprojected fabric spacing (unexpected: $($spacingFailures -join '; '))" $spacingUntouched
            Assert-Clothing "$garment repeat contains source artwork in at least twenty tiles" ($changedCells.Count -ge 20)
            Assert-Clothing "$garment repeat spans multiple rows AND columns" (
                @($changedCells.Values | ForEach-Object { $_[0] } | Select-Object -Unique).Count -ge 4 -and
                @($changedCells.Values | ForEach-Object { $_[1] } | Select-Object -Unique).Count -ge 4)
            $startX = if ($isShirt) { 128 } else { 512 }
            $startY = if ($isShirt) { 600 } else { 128 }
            $periodX = if ($isShirt) { 480 } else { 168 }
            $periodY = if ($isShirt) { 288 } else { 192 }
            $periodic = $true
            $comparisonCount = 0
            for ($y = $startY; $y -lt $startY + 12; $y++) {
                for ($x = $startX; $x -lt $startX + 40; $x++) {
                    if ($isShirt -and ($backMask.GetPixel($x, $y).A -gt 0 -or
                        $backMask.GetPixel($x + $periodX, $y).A -gt 0 -or
                        $backMask.GetPixel($x, $y + $periodY).A -gt 0)) { continue }
                    if ($image.GetPixel($x, $y).ToArgb() -ne $image.GetPixel($x + $periodX, $y).ToArgb() -or
                        $image.GetPixel($x, $y).ToArgb() -ne $image.GetPixel($x, $y + $periodY).ToArgb()) { $periodic = $false }
                    $comparisonCount++
                }
            }
            Assert-Clothing "$garment nonprojected artwork retains combined-fabric periods at $comparisonCount pixels" (
                $periodic -and $comparisonCount -ge 120)
        } finally { $image.Dispose(); $base.Dispose(); if ($null -ne $backMask) { $backMask.Dispose() } }
        $vtf = Join-Path $output "game\materials\models\zombiesim\clothing\$name.vtf"
        $header = [System.IO.File]::ReadAllBytes($vtf)
        Assert-Clothing "$garment repeat VTF dimensions and alpha flag" (
            [System.Text.Encoding]::ASCII.GetString($header, 0, 3) -eq 'VTF' -and
            [BitConverter]::ToUInt16($header, 16) -eq 1024 -and [BitConverter]::ToUInt16($header, 18) -eq 1024 -and
            ([BitConverter]::ToUInt32($header, 20) -band 0x3000) -ne 0)
        foreach ($extension in 'vtf', 'vmt') {
            $file = Join-Path $output "game\materials\models\zombiesim\clothing\$name.$extension"
            foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
                (Join-Path $gameDirectory 'materials\models\zombiesim\clothing')) {
                Assert-Clothing "$name.$extension staging hash in $directory" (
                    (Get-FileHash -LiteralPath $file).Hash -eq (Get-FileHash -LiteralPath (Join-Path $directory "$name.$extension")).Hash)
            }
        }
    }
    foreach ($sex in 'male', 'female') {
        $prints = Get-Content -LiteralPath (Join-Path $root 'assets\clothing\prints.json') -Raw | ConvertFrom-Json
        foreach ($legStyle in (Get-ClothingLegPresets $prints)) {
        $legName = "prototype_pants_${sex}_$($legStyle.id)"
        $leg = [System.Drawing.Bitmap]::new((Join-Path $output "source\$legName.png"))
        $nativePants = [System.Drawing.Bitmap]::new((Join-Path $output 'source\prototype_pants.png'))
        try {
            $sameAlpha = $true
            $outsideChanges = 0
            $printChanges = 0
            $rectangle = $legStyle.$sex[0].uv
            for ($y = 0; $y -lt 1024; $y += 4) {
                for ($x = 0; $x -lt 1024; $x += 4) {
                    $pixel = $leg.GetPixel($x, $y)
                    $original = $nativePants.GetPixel($x, $y)
                    if ($pixel.A -ne $original.A) { $sameAlpha = $false }
                    if ($pixel.ToArgb() -ne $original.ToArgb()) {
                        if ($x -ge $rectangle[0] -and $x -lt $rectangle[0] + $rectangle[2] -and
                            $y -ge $rectangle[1] -and $y -lt $rectangle[1] + $rectangle[3]) { $printChanges++ }
                        else { $outsideChanges++ }
                    }
                }
            }
            Assert-Clothing "$sex/$($legStyle.id) preserves garment alpha and uncovered surfaces" $sameAlpha
            Assert-Clothing "$sex/$($legStyle.id) changes only the selected leg placement" ($outsideChanges -eq 0)
            Assert-Clothing "$sex/$($legStyle.id) contains visible single-image pixels" ($printChanges -ge 10)
            if ($legStyle.id -like 'pants_cuff*') {
                Assert-Clothing "$sex/$($legStyle.id) retains bottom-aligned calf-height canvas" (
                    $legStyle.alignment -eq 'bottom' -and $legStyle.size[0] -eq 88 -and $legStyle.size[1] -eq 344)
                $cuffChanges = 0
                for ($y = 340; $y -lt 380; $y += 2) {
                    for ($x = $rectangle[0]; $x -lt $rectangle[0] + 88; $x += 2) {
                        if ($leg.GetPixel($x, $y).ToArgb() -ne $nativePants.GetPixel($x, $y).ToArgb()) { $cuffChanges++ }
                    }
                }
                Assert-Clothing "$sex/$($legStyle.id) image pixels reach below the knee near the opening" ($cuffChanges -gt 20)
            } elseif ($legStyle.id -like 'pants_back_*') {
                Assert-Clothing "$sex/$($legStyle.id) retains independent rear thigh canvas" (
                    $legStyle.size[0] -eq 48 -and $legStyle.size[1] -eq 144 -and $rectangle[1] -le 40)
            } else {
                Assert-Clothing "$sex/$($legStyle.id) has the raised 88x144 thigh canvas" (
                    $legStyle.size[0] -eq 88 -and $legStyle.size[1] -eq 144 -and $rectangle[1] -le 40)
            }
        } finally { $leg.Dispose(); $nativePants.Dispose() }
        $vtf = [System.IO.File]::ReadAllBytes((Join-Path $output "game\materials\models\zombiesim\clothing\$legName.vtf"))
        Assert-Clothing "$sex/pants_leg VTF size and alpha" (
            [BitConverter]::ToUInt16($vtf, 16) -eq 1024 -and [BitConverter]::ToUInt16($vtf, 18) -eq 1024 -and
            ([BitConverter]::ToUInt32($vtf, 20) -band 12288) -ne 0)
        foreach ($extension in 'vtf', 'vmt') {
            $file = Join-Path $output "game\materials\models\zombiesim\clothing\$legName.$extension"
            foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
                (Join-Path $gameDirectory 'materials\models\zombiesim\clothing')) {
                Assert-Clothing "$legName.$extension scoped staging hash in $directory" (
                    (Get-FileHash -LiteralPath $file).Hash -eq
                    (Get-FileHash -LiteralPath (Join-Path $directory "$legName.$extension")).Hash)
            }
        }
        }
        $base = [System.Drawing.Bitmap]::new((Join-Path $output "source\prototype_shirt_$sex.png"))
        $backMask = New-ClothingBackMask $sex
        try {
            foreach ($style in (Get-ClothingShirtPresets $prints)) {
                $name = "prototype_shirt_${sex}_$($style.id)"
                $png = [System.Drawing.Bitmap]::new((Join-Path $output "source\$name.png"))
                try {
                    $sameAlpha = $true
                    $outsideChanges = 0
                    $printChanges = 0
                    for ($y = 0; $y -lt 1024; $y += 4) {
                        for ($x = 0; $x -lt 1024; $x += 4) {
                            $pixel = $png.GetPixel($x, $y)
                            $original = $base.GetPixel($x, $y)
                            if ($pixel.A -ne $original.A) { $sameAlpha = $false }
                            $insidePrint = $false
                            foreach ($piece in $style.$sex) {
                                if ($x -ge $piece.uv[0] -and $x -lt $piece.uv[0] + $piece.uv[2] -and
                                    $y -ge $piece.uv[1] -and $y -lt $piece.uv[1] + $piece.uv[3]) { $insidePrint = $true }
                            }
                            if ($style.id -eq 'back_full') {
                                $insidePrint = $backMask.GetPixel($x, $y).A -gt 0
                            }
                            $oldLogo = $definition.shirt.logo
                            $insideOldLogo = $x -ge $oldLogo.x -and $x -lt $oldLogo.x + $oldLogo.width -and
                                $y -ge $oldLogo.y -and $y -lt $oldLogo.y + $oldLogo.height
                            if ($pixel.ToArgb() -ne $original.ToArgb()) {
                                if ($insidePrint) { $printChanges++ }
                                elseif (-not $insideOldLogo) { $outsideChanges++ }
                            }
                        }
                    }
                    Assert-Clothing "$sex/$($style.id) preserves alpha/inner-shirt mask at 65536 points" $sameAlpha
                    Assert-Clothing "$sex/$($style.id) alters only print placement and replaces old text logo" ($outsideChanges -eq 0)
                    Assert-Clothing "$sex/$($style.id) has visible source-image pixels" ($printChanges -ge 10)
                } finally { $png.Dispose() }
                foreach ($extension in 'vtf', 'vmt') {
                    $file = Join-Path $output "game\materials\models\zombiesim\clothing\$name.$extension"
                    foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
                        (Join-Path $gameDirectory 'materials\models\zombiesim\clothing')) {
                        Assert-Clothing "$name.$extension scoped staging hash in $directory" (
                            (Get-FileHash -LiteralPath $file).Hash -eq (Get-FileHash -LiteralPath (Join-Path $directory "$name.$extension")).Hash)
                    }
                }
            }
        } finally { $base.Dispose(); $backMask.Dispose() }
        foreach ($mode in 'shirt', 'pants', 'both') {
            foreach ($kind in 'prototype', 'equipped') {
            $key = if ($kind -eq 'equipped') { "equipped_${sex}_${mode}" } else { "${sex}_${mode}" }
            $name = "${kind}_${sex}_$mode.vmt"
            $file = Join-Path $output "game\materials\models\zombiesim\clothing\$name"
            $vmt = Get-Content -LiteralPath $file -Raw
            Assert-Clothing "$sex/$mode patch references native shader/proxies without copying them" (
                $vmt.Contains('"Patch"') -and $vmt.Contains("materials/models/humans/$sex/group01/players_sheet.vmt") -and
                $vmt.Contains("zombiesim_clothing_${key}_v2") -and $vmt -notmatch 'Proxies|bumpmap|phong')
            foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
                (Join-Path $gameDirectory 'materials\models\zombiesim\clothing')) {
                Assert-Clothing "$name staging hash in $directory" (
                    (Get-FileHash -LiteralPath $file).Hash -eq (Get-FileHash -LiteralPath (Join-Path $directory $name)).Hash)
            }
            }
        }
    }
    $rejected = $false
    $temporary = Join-Path $output 'opaque-rejection-test.tga'
    try {
        try {
            [ZombieSim.SignAssets.Builder]::WriteTga((Join-Path $output 'source\prototype_shirt_female.png'), $temporary, 1024, 1024)
        } catch [System.Management.Automation.MethodInvocationException] {
            if ($_.Exception.InnerException.Message -ne 'Billboard artwork must be opaque.') { throw }
            $rejected = $true
        }
        Assert-Clothing 'existing billboard TGA API still rejects transparency' $rejected
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
} finally {
    [pscustomobject]@{ cases = $cases.ToArray(); passed = @($cases | Where-Object passed).Count } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'test-report.json') -Encoding UTF8
}
Write-Host "Clothing prototype checks passed: $($cases.Count)/$($cases.Count)."
