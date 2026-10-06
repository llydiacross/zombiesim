param([switch]$ValidateBuilt, [string]$PreviousCatalogue)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_catalogue.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_artwork.psm1')
$root = Split-Path -Parent $PSScriptRoot
$settings = Get-Content (Join-Path $root 'assets\clothing\catalogue.json') -Raw | ConvertFrom-Json
$prints = Get-Content (Join-Path $root 'assets\clothing\prints.json') -Raw | ConvertFrom-Json
$passed = 0
function Assert-Catalogue([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Clothing catalogue regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
$patches = Get-ClothingTexturePool $settings.textureCapacity
Assert-Catalogue 'approved texture pool has exactly 96 slots and two native-family patches per slot' (
    $settings.textureCapacity -eq 96 -and $patches.Count -eq 192)
foreach ($slot in 1..$settings.textureCapacity) {
    $number = $slot.ToString('00')
    foreach ($sex in 'male', 'female') {
        Assert-Catalogue "pool $number/$sex inherits native shader and names its matching shared target" (
            $patches["pool_${number}_$sex.vmt"].Contains("materials/models/humans/$sex/group01/players_sheet.vmt") -and
            $patches["pool_${number}_$sex.vmt"].Contains("zombiesim_clothing_pool_${number}_v1"))
    }
}
foreach ($invalid in 0, 100) {
    $rejected = $false
    try { $null = Get-ClothingTexturePool $invalid } catch { $rejected = $true }
    Assert-Catalogue "pool rejects capacity $invalid outside the two-digit material namespace" $rejected
}
foreach ($preset in @(Get-ClothingShirtPresets $prints) + @(Get-ClothingLegPresets $prints)) {
    $icon = Get-ClothingCatalogueIcon $(if ($preset.id -like 'pants_*') { 'pants' } else { 'shirt' }) $preset.id $prints
    Assert-Catalogue "wardrobe icon retains calibrated canvas and split UV pieces: $($preset.id)" (
        ($icon.size -join ',') -eq ($preset.size -join ',') -and
        ($icon.male | ConvertTo-Json -Depth 5 -Compress) -eq ($preset.male | ConvertTo-Json -Depth 5 -Compress) -and
        ($icon.female | ConvertTo-Json -Depth 5 -Compress) -eq ($preset.female | ConvertTo-Json -Depth 5 -Compress))
}
foreach ($garment in 'shirt', 'pants') {
    $icon = Get-ClothingCatalogueIcon $garment repeat $prints
    foreach ($sex in 'male', 'female') {
        $piece = @($icon[$sex])[0]
        Assert-Catalogue "repeat $garment/$sex icon is populated, bounded and aspect preserving" (
            $icon.size[0] -gt 0 -and $icon.size[1] -gt 0 -and $piece.uv[0] -ge 0 -and $piece.uv[1] -ge 0 -and
            $piece.uv[0] + $piece.uv[2] -le 1024 -and $piece.uv[1] + $piece.uv[3] -le 1024 -and
            $piece.uv[2] -eq $icon.size[0] -and $piece.uv[3] -eq $icon.size[1] -and
            ($piece.source -join ',') -eq (@(0, 0, $icon.size[0], $icon.size[1]) -join ','))
    }
}
$chest = @($prints.styles | Where-Object id -eq chest)[0]
$front = @($prints.styles | Where-Object id -eq front_full)[0]
foreach ($sex in 'male', 'female') {
    $chestRect = $chest.$sex[0].uv
    $frontRect = $front.$sex[0].uv
    Assert-Catalogue "centred $sex chest logo is smaller and higher than the full torso print" (
        $chestRect[0] + $chestRect[2] / 2 -eq $frontRect[0] + $frontRect[2] / 2 -and
        $chestRect[1] + $chestRect[3] / 2 -lt $frontRect[1] + $frontRect[3] / 2 -and
        $chestRect[2] -lt $frontRect[2] -and $chestRect[3] -lt $frontRect[3] -and
        $chestRect[2] -eq 120 -and $chestRect[3] -eq 90 -and $chestRect[1] -eq 772)
}
$rejected = $false
try { $null = Get-ClothingCatalogueIcon shirt missing $prints } catch { $rejected = $true }
Assert-Catalogue 'missing wardrobe icon preset fails explicitly' $rejected
foreach ($case in @(
    @('deer.png', 'deer', $null, $null),
    @('deer_black.png', 'deer', 'black', $null),
    @('deer_front_black.png', 'deer', 'black', 'front'),
    @('deer_black_front.png', 'deer', 'black', 'front'),
    @('Deer_CHEST.png', 'deer', $null, 'chest'),
    @('deer_chest_dark_white.png', 'deer', 'white', 'chest'),
    @('deer_pink_chest.png', 'deer', 'pink', 'chest'),
    @('deer_front-full.png', 'deer', $null, 'front'),
    @('deer_back_full.png', 'deer', $null, 'back'),
    @('deer_arm_left_gray.png', 'deer', 'grey', 'arm_left'),
    @('deer_arm_right.png', 'deer', $null, 'arm_right'),
    @('deer_pants_navy.png', 'deer', 'navy', 'pants'),
    @('deer_check.png', 'deer_check', $null, $null))) {
    $parsed = Read-ClothingFilename $case[0] $settings
    Assert-Catalogue $case[0] ($parsed.family -eq $case[1] -and $parsed.colour -eq $case[2] -and $parsed.placement -eq $case[3])
}
foreach ($name in 'deer_front_back.png', 'deer_chest_front.png', 'chest.png', 'deer_black_white.png', 'arm_left.png', 'deer_front_arm_left.png',
    'deer_black_notblack.png', 'deer_notblack_black.png', 'deer_notblack_notblack.png', 'deer_grey_notgray.png') {
    $rejected = $false
    try { $null = Read-ClothingFilename $name $settings } catch { $rejected = $true }
    Assert-Catalogue "reject ambiguous/nameless $name" $rejected
}
foreach ($case in @(
    @('boardsofcanada_notblack.png', 'boardsofcanada', $null, $null, @('black')),
    @('deer_front_notblack_notred.png', 'deer', $null, 'front', @('black', 'red')),
    @('deer_notblack_arm_left_white.png', 'deer', 'white', 'arm_left', @('black')),
    @('deer_notgray_pants.png', 'deer', $null, 'pants', @('grey')),
    @('deer_notmagenta.png', 'deer_notmagenta', $null, $null, @()))) {
    $parsed = Read-ClothingFilename $case[0] $settings
    Assert-Catalogue "exclusion parse $($case[0])" (
        $parsed.family -eq $case[1] -and $parsed.colour -eq $case[2] -and $parsed.placement -eq $case[3] -and
        (($parsed.excludedColours | Sort-Object) -join ',') -eq (($case[4] | Sort-Object) -join ','))
}
foreach ($case in @(
    @('boardsofcanada_dark.png', 'boardsofcanada', 'dark', $null, $null),
    @('deer_light.png', 'deer', 'light', $null, $null),
    @('deer_dark_front_white.png', 'deer', 'dark', 'front', 'white'),
    @('deer_white_front_dark.png', 'deer', 'dark', 'front', 'white'),
    @('deer_notblack_dark_arm_left.png', 'deer', 'dark', 'arm_left', $null),
    @('deer_light_notgray_pants.png', 'deer', 'light', 'pants', $null),
    @('Deer-DARK-NOTBLACK-FRONT.png', 'deer', 'dark', 'front', $null),
    @('deer_moonlight.png', 'deer_moonlight', $null, $null, $null))) {
    $parsed = Read-ClothingFilename $case[0] $settings
    Assert-Catalogue "tone parse $($case[0])" ($parsed.family -eq $case[1] -and $parsed.artworkTone -eq $case[2] -and
        $parsed.placement -eq $case[3] -and $parsed.colour -eq $case[4])
}
foreach ($name in 'deer_dark_light.png', 'deer_dark_dark.png', 'light.png', 'dark_front.png') {
    $rejected = $false
    try { $null = Read-ClothingFilename $name $settings } catch { $rejected = $true }
    Assert-Catalogue "reject ambiguous/nameless tone $name" $rejected
}
Assert-Catalogue 'reference-tone contrast uses linear RGB, not colour-name guesses' (
    (Get-ClothingToneContrast dark '#000000') -eq 1 -and
    [math]::Abs((Get-ClothingToneContrast dark '#FFFFFF') - 21) -lt 0.000001 -and
    (Get-ClothingToneContrast light '#000000') -eq 21 -and
    [math]::Abs((Get-ClothingToneContrast light '#FFFFFF') - 1) -lt 0.000001)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('zombiesim-clothing-catalogue-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
try {
    Add-Type -AssemblyName System.Drawing
    foreach ($name in 'deer_arm_left_black.png', 'bird_pants.png', '__diagnostic.png', 'uv_probe.png') {
        $bitmap = [Drawing.Bitmap]::new(8, 12)
        try { $bitmap.Save((Join-Path $scratch $name), [Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose() }
    }
    $plan = Get-ClothingCataloguePlan $scratch $settings
    Assert-Catalogue 'exclude diagnostic PNGs' ($plan.families.Count -eq 2)
    $arm = @($plan.variants | Where-Object family -eq 'deer_arm_left_black')
    Assert-Catalogue 'arm tag generates one placed image and whole-shirt repeat' (
        $arm.Count -eq 2 -and @($arm | Where-Object style -eq 'arm_left').Count -eq 1 -and
        @($arm | Where-Object style -eq 'repeat').Count -eq 1 -and @($arm | Where-Object garment -ne 'shirt').Count -eq 0)
    Assert-Catalogue 'colour suffix fixes both counterparts' (@($arm | Where-Object colour -ne 'black').Count -eq 0)
    $pants = @($plan.variants | Where-Object family -eq 'bird_pants')
    Assert-Catalogue 'pants tag restricts families and uses subdued curated palette' (
        $pants.Count -eq 15 -and @($pants | Where-Object garment -ne 'pants').Count -eq 0 -and
        @($pants | Where-Object style -eq pants_leg_right).Count -eq 3)
    Assert-Catalogue 'pants retain thighs and add both separately named cuff anchors plus repeat' (
        @($pants | Where-Object style -eq pants_leg).Count -eq 3 -and
        @($pants | Where-Object style -eq pants_cuff).Count -eq 3 -and
        @($pants | Where-Object style -eq pants_cuff_right).Count -eq 3 -and
        @($pants | Where-Object style -eq repeat).Count -eq 3)
    $cuffFamily = Read-ClothingFilename 'flames_pants_cuff_dark_navy.png' $settings
    Assert-Catalogue 'explicit cuff suffix combines with background and tone' (
        $cuffFamily.family -eq 'flames' -and $cuffFamily.placement -eq 'pants_cuff' -and
        $cuffFamily.colour -eq 'navy' -and $cuffFamily.artworkTone -eq 'dark')
    $bitmap = [Drawing.Bitmap]::new(8, 12)
    try { $bitmap.Save((Join-Path $scratch 'flames_pants_cuff_olive.png'), [Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
    $cuffPlan = Get-ClothingCataloguePlan $scratch $settings
    $cuffs = @($cuffPlan.variants | Where-Object family -eq flames_pants_cuff_olive)
    Assert-Catalogue 'cuff-tagged artwork restricts placed graphics but retains whole-pants repeat' (
        $cuffs.Count -eq 3 -and @($cuffs | Where-Object { $_.garment -ne 'pants' -or $_.style -notin 'pants_cuff', 'pants_cuff_right', 'repeat' }).Count -eq 0)
    Remove-Item -LiteralPath (Join-Path $scratch 'flames_pants_cuff_olive.png')
    foreach ($tag in 'pants_back_left', 'pants_back_right', 'arm_back_left', 'arm_back_right') {
        $parsed = Read-ClothingFilename "deer_${tag}_white_dark.png" $settings
        Assert-Catalogue "$tag parses separately from family/background/tone" (
            $parsed.family -eq 'deer' -and $parsed.placement -eq $tag -and $parsed.colour -eq 'white' -and $parsed.artworkTone -eq 'dark')
        $path = Join-Path $scratch "deer_${tag}_white.png"
        $bitmap = [Drawing.Bitmap]::new(8, 12)
        try { $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
        try {
            $rearPlan = Get-ClothingCataloguePlan $scratch $settings
            $rearVariants = @($rearPlan.variants | Where-Object family -eq "deer_${tag}_white")
            $garment = if ($tag -like 'pants_*') { 'pants' } else { 'shirt' }
            Assert-Catalogue "$tag produces only explicitly selected rear limb and garment repeat" (
                $rearVariants.Count -eq 2 -and @($rearVariants | Where-Object garment -ne $garment).Count -eq 0 -and
                @($rearVariants | Where-Object style -eq $tag).Count -eq 1 -and
                @($rearVariants | Where-Object style -eq repeat).Count -eq 1)
            Assert-Catalogue "$tag leaves all ordinary family variants unchanged" (
                ($plan.variants | ConvertTo-Json -Depth 6 -Compress) -eq
                (@($rearPlan.variants | Where-Object family -ne "deer_${tag}_white") | ConvertTo-Json -Depth 6 -Compress))
        } finally { Remove-Item -LiteralPath $path }
    }
    Assert-Catalogue 'generated item IDs match static-data grammar' (
        @($plan.variants | Where-Object { $_.itemId -cnotmatch '^[a-z][a-zA-Z0-9]*$' }).Count -eq 0)
    Assert-Catalogue 'deterministic plan and IDs' (
        ($plan | ConvertTo-Json -Depth 6 -Compress) -eq ((Get-ClothingCataloguePlan $scratch $settings) | ConvertTo-Json -Depth 6 -Compress))
    $bitmap = [Drawing.Bitmap]::new(8, 12)
    try { $bitmap.Save((Join-Path $scratch 'boardsofcanada_notblack.png'), [Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
    $oldShirtColours, $oldPantsColours = $settings.shirtColours, $settings.pantsColours
    try {
        $settings.shirtColours = @('black', 'teal', 'grey')
        $settings.pantsColours = @('black', 'olive', 'navy')
        $excludedPlan = Get-ClothingCataloguePlan $scratch $settings
        $excludedVariants = @($excludedPlan.variants | Where-Object family -eq 'boardsofcanada_notblack')
        Assert-Catalogue 'notblack removes black even when curated palettes contain it' (
            $excludedVariants.Count -eq (2 * ($settings.defaultShirtPlacements.Count + 1) + 10) -and @($excludedVariants | Where-Object colour -eq 'black').Count -eq 0)
        foreach ($garment in 'shirt', 'pants') {
            $selected = @($excludedVariants | Where-Object garment -eq $garment)
            Assert-Catalogue "notblack preserves allowed single and repeating $garment variants" (
                @($selected | Where-Object style -eq 'repeat').Count -eq 2 -and
                @($selected | Where-Object style -ne 'repeat').Count -gt 0)
        }
        $settings.shirtColours = @('black')
        $rejected = $false
        try { $null = Get-ClothingCataloguePlan $scratch $settings } catch { $rejected = $true }
        Assert-Catalogue 'excluding every available colour fails explicitly' $rejected
    } finally {
        $settings.shirtColours, $settings.pantsColours = $oldShirtColours, $oldPantsColours
    }
    foreach ($name in 'ink_dark.png', 'ink_light.png', 'ink_dark_front_notgray.png', 'ink_white_front_dark.png') {
        Copy-Item (Join-Path $scratch 'bird_pants.png') (Join-Path $scratch $name)
    }
    $tonePlan = Get-ClothingCataloguePlan $scratch $settings
    foreach ($tone in 'dark', 'light') {
        $selected = @($tonePlan.variants | Where-Object family -eq "ink_$tone")
        Assert-Catalogue "$tone uses tone-specific shirt/pants palettes" (
            $selected.Count -eq ($settings.tonePalettes.$tone.shirt.Count * ($settings.defaultShirtPlacements.Count + 1) +
                $settings.tonePalettes.$tone.pants.Count * 5) -and
            @($selected | Where-Object artworkTone -ne $tone).Count -eq 0)
        Assert-Catalogue "$tone rejects insufficient contrast for every variant" (
            @($selected | Where-Object {
                (Get-ClothingToneContrast $tone $_.background) -lt $settings.minimumToneContrast
            }).Count -eq 0)
        foreach ($garment in 'shirt', 'pants') {
            $garmentVariants = @($selected | Where-Object garment -eq $garment)
            Assert-Catalogue "$tone produces single and repeat $garment counterparts" (
                @($garmentVariants | Where-Object style -eq 'repeat').Count -gt 0 -and
                @($garmentVariants | Where-Object style -ne 'repeat').Count -gt 0)
        }
    }
    Assert-Catalogue 'dark artwork never generates black or charcoal backgrounds' (
        @($tonePlan.variants | Where-Object { $_.artworkTone -eq 'dark' -and $_.colour -in 'black', 'charcoal' }).Count -eq 0)
    $excludedTone = @($tonePlan.variants | Where-Object family -eq 'ink_dark_front_notgray')
    Assert-Catalogue 'tone combines with exclusion aliases and placement' (
        $excludedTone.Count -eq 4 -and @($excludedTone | Where-Object colour -eq 'grey').Count -eq 0 -and
        @($excludedTone | Where-Object garment -ne 'shirt').Count -eq 0)
    $fixedTone = @($tonePlan.variants | Where-Object family -eq 'ink_white_front_dark')
    Assert-Catalogue 'compatible explicit background and tone preserve single/repeat variants' (
        $fixedTone.Count -eq 2 -and @($fixedTone | Where-Object colour -ne 'white').Count -eq 0)
    foreach ($name in 'ink_dark_black_front.png', 'ink_light_white_pants.png', 'x_dark_notwhite_notgrey_nottan_front.png') {
        $path = Join-Path $scratch $name
        Copy-Item (Join-Path $scratch 'bird_pants.png') $path
        try {
            $rejected = $false
            try { $null = Get-ClothingCataloguePlan $scratch $settings }
            catch { $rejected = $_.Exception.Message -like '*No allowed*after exclusions/tone contrast*' }
            Assert-Catalogue "reject contradictory/exhausted tone palette $name" $rejected
        } finally { Remove-Item -LiteralPath $path }
    }
    $invalidSettings = $settings | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $invalidSettings.tonePalettes.dark.pants = @('black')
    $rejected = $false
    try { $null = Get-ClothingCataloguePlan $scratch $invalidSettings }
    catch { $rejected = $_.Exception.Message -like '*insufficient contrast*' }
    Assert-Catalogue 'misconfigured tone palettes fail explicitly' $rejected
    $settings.maximumVariants = 1
    $rejected = $false
    try { $null = Get-ClothingCataloguePlan $scratch $settings } catch { $rejected = $true }
    Assert-Catalogue 'variant budget fails explicitly' $rejected
    $settings.maximumVariants = 256
    Copy-Item (Join-Path $scratch 'bird_pants.png') (Join-Path $scratch 'bird-pants.png')
    $rejected = $false
    try { $null = Get-ClothingCataloguePlan $scratch $settings } catch { $rejected = $true }
    Assert-Catalogue 'normalized filename collisions fail explicitly' $rejected
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
if ($ValidateBuilt) {
    $sourceSettings = Get-Content (Join-Path $root 'assets\clothing\catalogue.json') -Raw | ConvertFrom-Json
    $plan = Get-ClothingCataloguePlan (Join-Path $root 'assets\clothing') $sourceSettings
    Assert-Catalogue 'combined front-back choices are removed from the current plan' (
        @($plan.variants | Where-Object style -eq front_back).Count -eq 0)
    foreach ($family in $plan.families) {
        if ($null -ne $family.artworkTone -or $null -ne $family.colour -or
            $family.placement -eq 'pants' -or $family.placement -like 'pants_*') { continue }
        $colours = @($plan.variants | Where-Object { $_.family -eq $family.identity -and $_.garment -eq 'shirt' } |
            Select-Object -ExpandProperty colour -Unique | Sort-Object)
        $expected = @($sourceSettings.shirtColours | Where-Object { $_ -notin $family.excludedColours } | Sort-Object)
        Assert-Catalogue "$($family.source) gets the complete colourful default shirt palette" (
            ($colours -join ',') -eq ($expected -join ','))
    }
    $manifest = Get-Content (Join-Path $root 'content\data_static\clothing_catalogue.json') -Raw | ConvertFrom-Json
    Assert-Catalogue 'published capacity and exact pool ownership match source settings' (
        $manifest.capacity -eq $settings.textureCapacity -and
        ((@($manifest.files | Where-Object { $_ -like 'pool_*' }) | Sort-Object) -join ',') -eq
        (($patches.Keys | Sort-Object) -join ','))
    foreach ($name in $patches.Keys) {
        Assert-Catalogue "$name published native patch matches configured target exactly" (
            (Get-Content -LiteralPath (Join-Path $root "content\materials\models\zombiesim\clothing\$name") -Raw) -eq $patches[$name])
    }
    $finishCount = @($manifest.finishes.PSObject.Properties).Count
    $items = @($manifest.items.PSObject.Properties.Value)
    Assert-Catalogue 'combined front-back finishes are absent from the staged registry' (
        @($manifest.finishes.PSObject.Properties.Value | Where-Object style -eq front_back).Count -eq 0)
    Assert-Catalogue 'staged catalogue contains hundreds of finishes within the configured limit' (
        $finishCount -eq 206 + $plan.variants.Count -and $finishCount -ge 200 -and
        $finishCount -le $sourceSettings.maximumVariants)
    Assert-Catalogue 'all staged finish IDs route through exactly one distinct wearable item' (
        $items.Count -eq $finishCount -and @($items.clothing.finish | Select-Object -Unique).Count -eq $finishCount)
    if ($PreviousCatalogue) {
        $previous = Get-Content -LiteralPath $PreviousCatalogue -Raw | ConvertFrom-Json
        foreach ($property in $previous.finishes.PSObject.Properties) {
            Assert-Catalogue "$($property.Name) preserves previously published finish/layers/icon exactly" (
                $null -ne $manifest.finishes.PSObject.Properties[$property.Name] -and
                ($property.Value | ConvertTo-Json -Depth 8 -Compress) -eq
                ($manifest.finishes.($property.Name) | ConvertTo-Json -Depth 8 -Compress))
        }
        foreach ($property in $previous.items.PSObject.Properties) {
            Assert-Catalogue "$($property.Name) preserves previously published wearable identity exactly" (
                $null -ne $manifest.items.PSObject.Properties[$property.Name] -and
                ($property.Value | ConvertTo-Json -Depth 8 -Compress) -eq
                ($manifest.items.($property.Name) | ConvertTo-Json -Depth 8 -Compress))
        }
        Assert-Catalogue 'cuff expansion retains every previously owned file' (
            @($previous.files | Where-Object { $_ -notin $manifest.files }).Count -eq 0)
        $newFinishes = @($manifest.finishes.PSObject.Properties | Where-Object { $null -eq $previous.finishes.PSObject.Properties[$_.Name] })
        Assert-Catalogue 'limb expansion adds only explicitly named cuff or rear finishes' (
            @($newFinishes | Where-Object { $_.Value.style -notin 'pants_cuff', 'pants_cuff_right',
                'pants_back_left', 'pants_back_right', 'arm_back_left', 'arm_back_right' }).Count -eq 0)
    }
    foreach ($variant in $plan.variants) {
        $finish = $manifest.finishes.($variant.id)
        Assert-Catalogue "$($variant.id) retains exact image/placement/colour and item routing" (
            $finish.source -eq $variant.source -and $finish.style -eq $variant.style -and $finish.colour -eq $variant.colour -and
            $manifest.items.($variant.itemId).clothing.finish -eq $variant.id)
        if ($variant.style -like 'pants_cuff*' -or $variant.style -match '^(pants|arm)_back_') {
            $expectedIcon = Get-ClothingCatalogueIcon $variant.garment $variant.style $prints
            Assert-Catalogue "$($variant.id) publishes the exact model-specific limb icon canvas" (
                ($finish.icon | ConvertTo-Json -Depth 6 -Compress) -eq ($expectedIcon | ConvertTo-Json -Depth 6 -Compress))
        }
        if ($variant.style -eq 'back_full') {
            Assert-Catalogue "$($variant.id) uses one flat back-print icon for both sexes" (
                $finish.icon.layer -match '/catalog_[a-f0-9]{16}_shirt_back_full_icon$' -and
                ($finish.icon.male | ConvertTo-Json -Depth 5 -Compress) -eq
                ($finish.icon.female | ConvertTo-Json -Depth 5 -Compress))
        }
        foreach ($sex in 'male', 'female') {
            $relative = ($finish.layers.$sex -replace '/', '\') + '.vtf'
            $vtf = [IO.File]::ReadAllBytes((Join-Path $root "content\materials\$relative"))
            Assert-Catalogue "$($variant.id)/$sex built image layer is 1024 square with alpha" (
                [Text.Encoding]::ASCII.GetString($vtf, 0, 4) -eq "VTF`0" -and
                [BitConverter]::ToUInt16($vtf, 16) -eq 1024 -and [BitConverter]::ToUInt16($vtf, 18) -eq 1024 -and
                ([BitConverter]::ToUInt32($vtf, 20) -band 12288) -ne 0)
        }
    }
    foreach ($name in $manifest.files) {
        $content = Join-Path $root "content\materials\models\zombiesim\clothing\$name"
        $installed = Join-Path $root "..\..\materials\models\zombiesim\clothing\$name"
        Assert-Catalogue "$name exact installed/staged ownership hash" (
            (Get-FileHash -LiteralPath $content).Hash -eq (Get-FileHash -LiteralPath $installed).Hash)
    }
}
Write-Host "Clothing catalogue checks passed: $passed/$passed."
