param([switch]$ValidateBuilt)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_fabrics.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$settings = Get-Content (Join-Path $root 'assets\clothing\fabrics.json') -Raw | ConvertFrom-Json
$catalogue = Get-Content (Join-Path $root 'assets\clothing\catalogue.json') -Raw | ConvertFrom-Json
$passed = 0
function Assert-Fabric([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Clothing fabric regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Render-Fabric($Design) {
    $bitmap = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SetClip([Drawing.Rectangle]::new(100, 600, 700, 400))
        $graphics.SetClip([Drawing.Rectangle]::new(200, 650, 40, 40), [Drawing.Drawing2D.CombineMode]::Exclude)
        Write-ClothingFabric $graphics $Design
    } catch { $bitmap.Dispose(); throw }
    finally { $graphics.Dispose() }
    return $bitmap
}
$plan = @(Get-ClothingFabricPlan $settings $catalogue)
Assert-Fabric 'expanded library has 206 fabrics: 146 shirts and 60 restrained pants' (
    $plan.Count -eq 206 -and @($plan | Where-Object garment -eq shirt).Count -eq 146 -and
    @($plan | Where-Object garment -eq pants).Count -eq 60)
Assert-Fabric 'expanded plan reproduces stable identities and designs' (
    ($plan | ConvertTo-Json -Depth 8 -Compress) -eq
    (@(Get-ClothingFabricPlan $settings $catalogue) | ConvertTo-Json -Depth 8 -Compress))
Assert-Fabric 'fabric item identities match static-data grammar and are distinct' (
    @($plan | Where-Object { $_.itemId -cnotmatch '^[a-z][a-zA-Z0-9]*$' }).Count -eq 0 -and
    @($plan.itemId | Select-Object -Unique).Count -eq $plan.Count)
foreach ($fabric in $plan) {
    $first = Render-Fabric $fabric.design
    $second = $null
    try {
        $second = Render-Fabric $fabric.design
        $match = $true
        $colours = @{}
        for ($y = 604; $y -lt 1000; $y += 24) {
            for ($x = 104; $x -lt 800; $x += 24) {
                $pixel = $first.GetPixel($x, $y).ToArgb()
                if ($pixel -ne $second.GetPixel($x, $y).ToArgb()) { $match = $false }
                $colours[$pixel] = $true
            }
        }
        Assert-Fabric "$($fabric.id) deterministically reproduces exact sampled pixels" $match
        Assert-Fabric "$($fabric.id) respects caller garment/skin exclusions" (
            $first.GetPixel(0, 0).A -eq 0 -and $first.GetPixel(210, 660).A -eq 0 -and $first.GetPixel(400, 800).A -eq 255)
        if ($fabric.style -eq 'tie_dye') {
            Assert-Fabric "$($fabric.id) generates an appropriately varied dye field" (
                $colours.Count -gt $(if ($fabric.garment -eq 'pants') { 2 } else { 30 }))
            if ($fabric.garment -eq 'shirt') {
                $varyingBlocks = 0
                for ($y = 800; $y -lt 920; $y += 8) {
                    for ($x = 152; $x -lt 312; $x += 8) {
                        $block = @{}
                        for ($by = 0; $by -lt 8; $by++) {
                            for ($bx = 0; $bx -lt 8; $bx++) { $block[$first.GetPixel($x + $bx, $y + $by).ToArgb()] = $true }
                        }
                        if ($block.Count -gt 1) { $varyingBlocks++ }
                    }
                }
                Assert-Fabric "$($fabric.id) has per-texel dye detail in $varyingBlocks/300 blocks rather than flat 8x8 fills" ($varyingBlocks -gt 270)
            }
            if ($fabric.garment -eq 'pants') {
                $base = [Drawing.ColorTranslator]::FromHtml($fabric.design.color)
                $restrained = $true
                foreach ($argb in $colours.Keys) {
                    $pixel = [Drawing.Color]::FromArgb($argb)
                    if ($pixel.A -eq 0) { continue }
                    foreach ($channel in 'R', 'G', 'B') {
                        if ([math]::Abs($pixel.$channel - $base.$channel) -gt 3) { $restrained = $false }
                    }
                }
                Assert-Fabric 'pants wash stays within three RGB levels of its single-colour base' $restrained
            }
            $altered = $fabric.design | ConvertTo-Json -Depth 6 | ConvertFrom-Json
            $altered.tieDye.seed += 91
            $changed = Render-Fabric $altered
            try {
                $different = $false
                foreach ($x in 104, 304, 504, 704) {
                    if ($first.GetPixel($x, 804).ToArgb() -ne $changed.GetPixel($x, 804).ToArgb()) { $different = $true }
                }
                Assert-Fabric "$($fabric.id) seed changes pixels, not output identities" $different
            } finally { $changed.Dispose() }
        }
    } finally { $first.Dispose(); if ($null -ne $second) { $second.Dispose() } }
}
foreach ($mutation in 'budget', 'duplicate', 'loudpants', 'seed', 'scale', 'center', 'colour', 'pattern',
    'expansionbudget', 'expansioncolour', 'expansionduplicate', 'treatmentduplicate', 'dyestyle') {
    $invalid = $settings | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    switch ($mutation) {
        budget { $invalid.maximumVariants = 1 }
        duplicate { $invalid.variants[1].id = $invalid.variants[0].id }
        loudpants { $invalid.variants[-1].tieDye.strength = 0.8 }
        seed { $invalid.variants[-1].tieDye.seed = 1.5 }
        scale { $invalid.variants[-1].tieDye.scale = 0 }
        center { $invalid.variants[-1].tieDye.center = @(1025, 0) }
        colour { $invalid.variants[0].color = '#nope' }
        pattern { $invalid.variants[0].pattern = 'unknown' }
        expansionbudget { $invalid.maximumVariants = 200 }
        expansioncolour { $invalid.expansion.colours[0] = 'unknown' }
        expansionduplicate { $invalid.expansion.colours[0] = $invalid.expansion.colours[1] }
        treatmentduplicate { $invalid.expansion.shirtTreatments[0].id = $invalid.expansion.shirtTreatments[1].id }
        dyestyle { $invalid.expansion.shirtTreatments[-1].style = 'unknown' }
    }
    $rejected = $false
    try { $null = @(Get-ClothingFabricPlan $invalid $catalogue) } catch { $rejected = $true }
    Assert-Fabric "invalid $mutation fails explicitly" $rejected
}
if ($ValidateBuilt) {
    $manifest = Get-Content (Join-Path $root 'content\data_static\clothing_catalogue.json') -Raw | ConvertFrom-Json
    foreach ($fabric in $plan) {
        $finish = $manifest.finishes.($fabric.id)
        Assert-Fabric "$($fabric.id) staged item selects the exact fabric finish" (
            $manifest.items.($fabric.itemId).clothing.finish -eq $fabric.id -and $finish.fabric -eq $true)
        foreach ($sex in 'male', 'female') {
            $path = $finish.layers.$sex
            $filename = Split-Path -Leaf $path
            $prefix = $filename -replace '_(shirt_(male|female)|pants)$', ''
            $png = [Drawing.Bitmap]::new((Join-Path $root "generated\clothing_preview\$prefix\source\$filename.png"))
            try {
                Assert-Fabric "$($fabric.id)/$sex built layer preserves skin/shoes and independent garment" (
                    $png.GetPixel(900, 660).A -eq 0 -and $png.GetPixel(128, 128).A -eq 0 -and
                    $png.GetPixel(200, 800).A -eq $(if ($fabric.garment -eq 'shirt') { 255 } else { 0 }) -and
                    $png.GetPixel(700, 128).A -eq $(if ($fabric.garment -eq 'pants') { 255 } else { 0 }))
                if ($fabric.garment -eq 'shirt') {
                    $point = if ($sex -eq 'male') { @(60, 652) } else { @(251, 708) }
                    Assert-Fabric "$($fabric.id)/$sex keeps the inner shirt native" ($png.GetPixel($point[0], $point[1]).A -eq 0)
                }
            } finally { $png.Dispose() }
            foreach ($extension in 'vtf', 'vmt') {
                $relative = ($path -replace '/', '\') + ".$extension"
                $content = Join-Path $root "content\materials\$relative"
                $installed = Join-Path $root "..\..\materials\$relative"
                Assert-Fabric "$($fabric.id)/$sex staged $extension copies match" (
                    (Get-FileHash -LiteralPath $content).Hash -eq (Get-FileHash -LiteralPath $installed).Hash)
            }
            $vtf = [IO.File]::ReadAllBytes((Join-Path $root ('content\materials\' + ($path -replace '/', '\') + '.vtf')))
            Assert-Fabric "$($fabric.id)/$sex VTF is 1024 square with alpha" (
                [Text.Encoding]::ASCII.GetString($vtf, 0, 4) -eq "VTF`0" -and
                [BitConverter]::ToUInt16($vtf, 16) -eq 1024 -and [BitConverter]::ToUInt16($vtf, 18) -eq 1024 -and
                ([BitConverter]::ToUInt32($vtf, 20) -band 12288) -ne 0)
        }
    }
}
Write-Host "Clothing fabric checks passed: $passed/$passed."
