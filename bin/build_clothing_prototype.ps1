param(
    [ValidateSet('chest', 'chest_left', 'chest_right', 'arm_left', 'arm_right', 'back_small', 'front_full', 'back_full', 'repeat', 'pants_leg', 'pants_leg_right', 'pants_cuff', 'pants_cuff_right', 'pants_back_left', 'pants_back_right', 'arm_back_left', 'arm_back_right')]
    [string[]]$PrintStyles = @(),
    [object]$DefinitionData,
    [object]$PrintData,
    [ValidatePattern('^[a-z0-9_]{1,96}$')][string]$AssetPrefix = 'prototype',
    [ValidateSet('shirt_male', 'shirt_female', 'pants', 'pants_male', 'pants_female')][string[]]$OnlyGarments = @(),
    [switch]$PrintOnly,
    [switch]$BaseOnly,
    [switch]$SkipNativePatches
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_fabrics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_back_projection.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_artwork.psm1')
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$gameRoot = (Resolve-Path (Join-Path $root '..\..\..')).Path
$assetRoot = Join-Path $root 'assets\clothing'
$definition = if ($null -ne $DefinitionData) { $DefinitionData } else { Get-Content -LiteralPath (Join-Path $assetRoot 'prototype.json') -Raw | ConvertFrom-Json }
$prints = if ($null -ne $PrintData) { $PrintData } else { Get-Content -LiteralPath (Join-Path $assetRoot 'prints.json') -Raw | ConvertFrom-Json }
if ($null -eq $DefinitionData) {
    & (Join-Path $PSScriptRoot 'inspect_clothing_models.ps1') -UvGuideModels @('models/player/group01/male_03.mdl', 'models/player/group01/female_01.mdl')
}
if ($AssetPrefix -ne 'prototype' -and -not $SkipNativePatches) { throw 'Catalogue layers must not overwrite prototype/equipment patches.' }
if ($BaseOnly -and $PrintOnly) { throw 'BaseOnly and PrintOnly are mutually exclusive.' }
if ($definition.schemaVersion -ne 1 -or $definition.size -ne 1024) { throw 'Clothing prototype requires schema 1 and a 1024-square canvas.' }
if ($prints.schemaVersion -ne 1 -or $prints.styles.Count -ne 8 -or
    @($prints.styles.id | Select-Object -Unique).Count -ne $prints.styles.Count) { throw 'Print presets require schema 1 and eight distinct styles.' }
$output = Join-Path $root ('generated\clothing_preview\' + $AssetPrefix)
$source = Join-Path $output 'source'
$game = Join-Path $output 'game'
$materials = Join-Path $game 'materials\models\zombiesim\clothing'
$null = New-Item -ItemType Directory -Force -Path $source, $materials
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'), @'
"GameInfo"
{
    game "ZombieSim original clothing prototype"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths { game |gameinfo_path|. }
    }
}
'@, $utf8)
function Read-OriginalImage([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $assetRoot $Path))
    if (-not $resolved.StartsWith($assetRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Artwork must exist under assets\clothing: $Path" }
    return [System.Drawing.Bitmap]::new($resolved)
}
function Write-PrintPlacement($Graphics, $Image, $Style, [string]$Sex) {
    if ($Style.id -notmatch '^[a-z_]+$' -or $Style.size.Count -ne 2) { throw 'Invalid print preset identity/size.' }
    foreach ($value in $Style.size) {
        if ($value -ne [math]::Floor($value) -or $value -lt 1 -or $value -gt 1024) { throw 'Invalid print preset canvas.' }
    }
    $alignment = if ($null -ne $Style.PSObject.Properties['alignment']) { $Style.alignment } else { 'center' }
    $canvas = New-FittedArtwork $Image $Style.size[0] $Style.size[1] $alignment
    try {
        foreach ($piece in $Style.$Sex) {
            foreach ($rectangle in $piece.uv, $piece.source) {
                if ($rectangle.Count -ne 4) { throw "Invalid rectangle: $($Style.id)/$Sex" }
                foreach ($value in $rectangle) {
                    if ($value -ne [math]::Floor($value) -or $value -lt 0 -or $value -gt 1024) { throw "Invalid print rectangle: $($Style.id)/$Sex" }
                }
                if ($rectangle[2] -lt 1 -or $rectangle[3] -lt 1) { throw 'Print rectangles require positive size.' }
            }
            if ($piece.uv[0] + $piece.uv[2] -gt 1024 -or $piece.uv[1] + $piece.uv[3] -gt 1024 -or
                $piece.source[0] + $piece.source[2] -gt $canvas.Width -or
                $piece.source[1] + $piece.source[3] -gt $canvas.Height) { throw "Out-of-bounds print: $($Style.id)/$Sex" }
            $destination = [System.Drawing.Rectangle]::new($piece.uv[0], $piece.uv[1], $piece.uv[2], $piece.uv[3])
            $Graphics.DrawImage($canvas, $destination, $piece.source[0], $piece.source[1], $piece.source[2],
                $piece.source[3], [System.Drawing.GraphicsUnit]::Pixel)
        }
    } finally { $canvas.Dispose() }
}
function Write-RepeatingArtwork($Graphics, $Image, $Settings) {
    foreach ($pair in $Settings.motifSize, $Settings.spacing, $Settings.offset) {
        if ($pair.Count -ne 2) { throw 'Repeating artwork settings require two coordinates per field.' }
        foreach ($value in $pair) {
            if ($value -ne [math]::Floor($value) -or $value -lt 0 -or $value -gt 1024) { throw 'Invalid repeating artwork coordinate.' }
        }
    }
    if ($Settings.motifSize[0] -lt 8 -or $Settings.motifSize[1] -lt 8) { throw 'Repeating motif dimensions must be at least eight pixels.' }
    $stepX = $Settings.motifSize[0] + $Settings.spacing[0]
    $stepY = $Settings.motifSize[1] + $Settings.spacing[1]
    if ($Settings.offset[0] -ge $stepX -or $Settings.offset[1] -ge $stepY) { throw 'Repeat offsets must lie inside one repeat period.' }
    $motif = New-FittedArtwork $Image $Settings.motifSize[0] $Settings.motifSize[1]
    try {
        for ($y = $Settings.offset[1] - $stepY; $y -lt 1024; $y += $stepY) {
            for ($x = $Settings.offset[0] - $stepX; $x -lt 1024; $x += $stepX) {
                $Graphics.DrawImageUnscaled($motif, $x, $y)
            }
        }
    } finally { $motif.Dispose() }
}
$variants = @(
    [pscustomobject]@{ garment = 'shirt_male'; style = $null },
    [pscustomobject]@{ garment = 'shirt_female'; style = $null },
    [pscustomobject]@{ garment = 'pants'; style = $null }
)
foreach ($sex in 'male', 'female') {
    foreach ($leg in (Get-ClothingLegPresets $prints)) {
        if ($PrintStyles.Count -eq 0 -or $leg.id -in $PrintStyles) {
            if ($leg.id -notin 'pants_leg', 'pants_leg_right', 'pants_cuff', 'pants_cuff_right', 'pants_back_left', 'pants_back_right') { throw 'Invalid pants-leg preset identity.' }
            $variants += [pscustomobject]@{ garment = "pants_$sex"; style = $leg }
        }
    }
    foreach ($style in (Get-ClothingShirtPresets $prints)) {
        if ($PrintStyles.Count -eq 0 -or $style.id -in $PrintStyles) {
            $variants += [pscustomobject]@{ garment = "shirt_$sex"; style = $style }
            if ($style.id -eq 'back_full' -and $sex -eq 'male') {
                $variants += [pscustomobject]@{ garment = "shirt_$sex"; style = $style; icon = $true }
            }
        }
    }
}
if ($PrintStyles.Count -eq 0 -or 'repeat' -in $PrintStyles) {
    foreach ($garment in 'shirt_male', 'shirt_female', 'pants') {
        $variants += [pscustomobject]@{ garment = $garment; style = [pscustomobject]@{ id = 'repeat' } }
    }
}
$variants = @($variants | Where-Object {
    ($OnlyGarments.Count -eq 0 -or $_.garment -in $OnlyGarments) -and (-not $PrintOnly -or $null -ne $_.style) -and
        (-not $BaseOnly -or $null -eq $_.style)
})
if ($variants.Count -eq 0) { throw 'No garment layers selected.' }
foreach ($variant in $variants) {
    $garment = $variant.garment
    $style = $variant.style
    $isIcon = $null -ne $variant.PSObject.Properties['icon']
    $assetName = if ($isIcon) { 'shirt_back_full_icon' } else { $garment + $(if ($null -ne $style) { '_' + $style.id } else { '' }) }
    $isShirt = $garment.StartsWith('shirt_')
    $sex = if ($isShirt -or $garment.StartsWith('pants_')) { $garment.Substring(6) } else { $null }
    $design = if ($isShirt) { $definition.shirt } else { $definition.pants }
    Test-ClothingFabric $design
    $innerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    if ($isShirt) {
        $inner = $design.innerShirt
        if ($inner.mode -notin 'native', 'color', 'image' -or $inner.color -notmatch '^#[0-9A-Fa-f]{6}$') {
            throw 'Inner shirt requires native, color or image mode and a valid colour.'
        }
        foreach ($polygon in $inner.polygons.$sex) {
            if ($polygon.Count -lt 3) { throw "Inner-shirt polygon requires at least three points: $sex" }
            $points = [System.Drawing.PointF[]]::new($polygon.Count)
            for ($index = 0; $index -lt $polygon.Count; $index++) {
                $point = $polygon[$index]
                if ($point.Count -ne 2) { throw "Invalid inner-shirt polygon point: $sex" }
                foreach ($value in $point) {
                    if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1024) {
                        throw "Out-of-bounds inner-shirt polygon: $sex"
                    }
                }
                $points[$index] = [System.Drawing.PointF]::new($point[0], $point[1])
            }
            $innerPath.AddPolygon($points)
        }
    }
    foreach ($color in $design.color, $design.stripeColor, $design.logo.color) {
        if ($color -notmatch '^#[0-9A-Fa-f]{6}$') { throw "Invalid $garment colour: $color" }
    }
    foreach ($value in $design.stripeSpacing, $design.stripeWidth, $design.logo.width, $design.logo.height) {
        if ($value -ne [math]::Floor($value) -or $value -lt 1 -or $value -gt 1024) { throw "Invalid $garment artwork size." }
    }
    if ($design.stripeWidth -gt $design.stripeSpacing -or $design.regions.Count -lt 1) { throw "Invalid $garment mask/stripe configuration." }
    foreach ($rectangle in $design.regions) {
        if ($rectangle.Count -ne 4) { throw "Invalid $garment region." }
        foreach ($value in $rectangle) {
            if ($value -ne [math]::Floor($value) -or $value -lt 0 -or $value -gt 1024) { throw "Invalid $garment region coordinate." }
        }
        if ($rectangle[2] -lt 1 -or $rectangle[3] -lt 1 -or
            $rectangle[0] + $rectangle[2] -gt 1024 -or $rectangle[1] + $rectangle[3] -gt 1024) { throw "Out-of-bounds $garment mask." }
    }
    if ($design.logo.x -lt 0 -or $design.logo.y -lt 0 -or
        $design.logo.x + $design.logo.width -gt 1024 -or $design.logo.y + $design.logo.height -gt 1024) { throw "Out-of-bounds $garment logo." }
    $bitmap = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $mask = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $logoBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($design.logo.color))
    $font = [System.Drawing.Font]::new('Arial', [single]$design.logo.height, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $image = $null
    $logo = $null
    $innerImage = $null
    $printImage = $null
    $png = Join-Path $source "${AssetPrefix}_$assetName.png"
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        foreach ($rectangle in $design.regions) {
            $mask.AddRectangle([System.Drawing.Rectangle]::new($rectangle[0], $rectangle[1], $rectangle[2], $rectangle[3]))
        }
        $graphics.SetClip($mask)
        if ($isShirt) { $graphics.SetClip($innerPath, [System.Drawing.Drawing2D.CombineMode]::Exclude) }
        Write-ClothingFabric $graphics $design
        if ($isShirt -and -not $isIcon) {
            $fabricCanvas = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $fabricGraphics = [Drawing.Graphics]::FromImage($fabricCanvas)
            try {
                Write-ClothingFabric $fabricGraphics $design
                Write-ClothingBackProjection $graphics $fabricCanvas $sex
            } finally { $fabricGraphics.Dispose(); $fabricCanvas.Dispose() }
        }
        $image = Read-OriginalImage $design.image
        if ($null -ne $image) {
            if ($image.Width -ne 1024 -or $image.Height -ne 1024) { throw "The $garment image must be a UV-aligned 1024-square sheet." }
            $graphics.DrawImageUnscaled($image, 0, 0)
        }
        $logo = Read-OriginalImage $design.logo.image
        if ($null -ne $style) {
            $printImage = Read-OriginalImage $prints.image
            if ($null -eq $printImage) { throw 'Print presets require artwork.' }
            if ($style.id -eq 'repeat') {
                $settings = if ($isShirt) { $prints.repeat.shirt } else { $prints.repeat.pants }
                if ($isShirt) {
                    $state = $graphics.Save()
                    $backPath = New-ClothingBackPath $sex
                    try {
                        $graphics.SetClip($backPath, [Drawing.Drawing2D.CombineMode]::Exclude)
                        Write-RepeatingArtwork $graphics $printImage $settings
                    } finally { $graphics.Restore($state); $backPath.Dispose() }
                    $tile = [Drawing.Bitmap]::new(($settings.motifSize[0] + $settings.spacing[0]),
                        ($settings.motifSize[1] + $settings.spacing[1]), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
                    $tileGraphics = [Drawing.Graphics]::FromImage($tile)
                    try {
                        $tileGraphics.Clear([Drawing.Color]::Transparent)
                        Write-RepeatingArtwork $tileGraphics $printImage $settings
                        Write-ClothingBackProjection $graphics $tile $sex
                    } finally { $tileGraphics.Dispose(); $tile.Dispose() }
                } else { Write-RepeatingArtwork $graphics $printImage $settings }
            } elseif ($isIcon) {
                Write-PrintPlacement $graphics $printImage (@($prints.styles | Where-Object id -eq front_full)[0]) 'male'
            } elseif ($style.id -eq 'back_full') {
                $canvas = New-FittedArtwork $printImage $style.size[0] $style.size[1]
                try { Write-ClothingBackProjection $graphics $canvas $sex -FullPrint }
                finally { $canvas.Dispose() }
            } else {
                Write-PrintPlacement $graphics $printImage $style $sex
            }
        } elseif ($null -ne $logo) {
            $graphics.DrawImage($logo, $design.logo.x, $design.logo.y, $design.logo.width, $design.logo.height)
        } elseif (-not [string]::IsNullOrEmpty($design.logo.text)) {
            $graphics.DrawString($design.logo.text, $font, $logoBrush,
                [System.Drawing.RectangleF]::new($design.logo.x, $design.logo.y, $design.logo.width, $design.logo.height))
        }
        if ($isShirt -and $inner.mode -ne 'native') {
            $graphics.SetClip($mask)
            $graphics.SetClip($innerPath, [System.Drawing.Drawing2D.CombineMode]::Intersect)
            $innerBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($inner.color))
            try { $graphics.FillRectangle($innerBrush, 0, 0, 1024, 1024) }
            finally { $innerBrush.Dispose() }
            if ($inner.mode -eq 'image') {
                $innerImage = Read-OriginalImage $inner.image
                if ($null -eq $innerImage -or $innerImage.Width -ne 1024 -or $innerImage.Height -ne 1024) {
                    throw 'Inner-shirt image mode requires a UV-aligned 1024-square original image.'
                }
                $graphics.DrawImageUnscaled($innerImage, 0, 0)
            }
        }
        $bitmap.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($null -ne $image) { $image.Dispose() }
        if ($null -ne $logo) { $logo.Dispose() }
        if ($null -ne $innerImage) { $innerImage.Dispose() }
        if ($null -ne $printImage) { $printImage.Dispose() }
        $font.Dispose(); $logoBrush.Dispose()
        $innerPath.Dispose(); $mask.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
    }
    $tga = Join-Path $source "${AssetPrefix}_$assetName.tga"
    [ZombieSim.SignAssets.Builder]::WriteTga($png, $tga, 1024, 1024, $true)
    [System.IO.File]::WriteAllText((Join-Path $source "${AssetPrefix}_$assetName.txt"), "nolod 1`r`n", $utf8)
    $vtf = Join-Path $materials "${AssetPrefix}_$assetName.vtf"
    if (Test-Path -LiteralPath $vtf) { Remove-Item -LiteralPath $vtf }
    Invoke-SignCompiler (Join-Path $gameRoot 'bin\vtex.exe') ('-nop4 -nopause -game "{0}" -outdir "{1}" "{2}"' -f $game, $materials, $tga) (Join-Path $output "vtex_$assetName.log")
    if (-not (Test-Path -LiteralPath $vtf -PathType Leaf)) { throw "vtex did not produce the $garment artwork." }
    [System.IO.File]::WriteAllText((Join-Path $materials "${AssetPrefix}_$assetName.vmt"), @"
"UnlitGeneric"
{
    "`$basetexture" "models/zombiesim/clothing/${AssetPrefix}_$assetName"
    "`$translucent" "1"
    "`$vertexcolor" "1"
    "`$vertexalpha" "1"
}
"@, $utf8)
    foreach ($extension in 'vtf', 'vmt') {
        $file = Join-Path $materials "${AssetPrefix}_$assetName.$extension"
        foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
            (Join-Path $gameRoot 'garrysmod\materials\models\zombiesim\clothing')) {
            $null = New-Item -ItemType Directory -Force -Path $directory
            $destination = Join-Path $directory "${AssetPrefix}_$assetName.$extension"
            Copy-Item -LiteralPath $file -Destination $destination -Force
            if ((Get-FileHash -LiteralPath $file).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Clothing staging hash mismatch: $destination" }
        }
    }
}
if (-not $SkipNativePatches) {
foreach ($sex in 'male', 'female') {
    foreach ($mode in 'shirt', 'pants', 'both') {
        foreach ($kind in 'prototype', 'equipped') {
        $name = "${kind}_${sex}_$mode"
        $targetKey = if ($kind -eq 'equipped') { "equipped_${sex}_${mode}" } else { "${sex}_${mode}" }
        $file = Join-Path $materials "$name.vmt"
        [System.IO.File]::WriteAllText($file, @"
"Patch"
{
    "include" "materials/models/humans/$sex/group01/players_sheet.vmt"
    "replace"
    {
        "`$basetexture" "zombiesim_clothing_${targetKey}_v2"
    }
}
"@, $utf8)
        foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
            (Join-Path $gameRoot 'garrysmod\materials\models\zombiesim\clothing')) {
            $destination = Join-Path $directory "$name.vmt"
            Copy-Item -LiteralPath $file -Destination $destination -Force
            if ((Get-FileHash -LiteralPath $file).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Clothing patch staging hash mismatch: $destination" }
        }
        }
    }
}
}
$patches = if ($SkipNativePatches) { 0 } else { 12 }
Write-Host "Built/root-staged $($variants.Count) garment layers and $patches native-material patches ($($variants.Count * 2 + $patches) files). No mounted artwork, models, BSPs or player data changed."
