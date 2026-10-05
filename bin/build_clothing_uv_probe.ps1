Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$gameRoot = (Resolve-Path (Join-Path $root '..\..\..')).Path
$definition = Get-Content -LiteralPath (Join-Path $root 'assets\clothing\uv_probe.json') -Raw | ConvertFrom-Json
if ($definition.schemaVersion -ne 1 -or $definition.size -ne 1024 -or
    $definition.columns -ne 8 -or $definition.rows -ne 8 -or $definition.hues.Count -ne 8) {
    throw 'UV probe requires schema 1, a 1024-square canvas and an 8x8 colour/label grid.'
}
foreach ($hue in $definition.hues) {
    if ($hue -notmatch '^#[0-9A-Fa-f]{6}$') { throw "Invalid UV probe colour: $hue" }
}
$output = Join-Path $root 'generated\clothing_preview\uv_probe'
$source = Join-Path $output 'source'
$game = Join-Path $output 'game'
$materials = Join-Path $game 'materials\models\zombiesim\clothing'
$null = New-Item -ItemType Directory -Force -Path $source, $materials
$png = Join-Path $source 'uv_probe.png'
$bitmap = [System.Drawing.Bitmap]::new(1024, 1024)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$font = [System.Drawing.Font]::new('Arial', 30, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$smallFont = [System.Drawing.Font]::new('Arial', 14, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$pen = [System.Drawing.Pen]::new([System.Drawing.Color]::Black, 3)
try {
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    for ($row = 0; $row -lt 8; $row++) {
        for ($column = 0; $column -lt 8; $column++) {
            $color = [System.Drawing.ColorTranslator]::FromHtml($definition.hues[$column])
            $factor = 1.0 - $row * 0.06
            $shade = [System.Drawing.Color]::FromArgb([int]($color.R * $factor), [int]($color.G * $factor), [int]($color.B * $factor))
            $brush = [System.Drawing.SolidBrush]::new($shade)
            try { $graphics.FillRectangle($brush, $column * 128, $row * 128, 128, 128) }
            finally { $brush.Dispose() }
            $graphics.DrawRectangle($pen, $column * 128, $row * 128, 127, 127)
            $label = [string][char](65 + $row) + ($column + 1)
            $graphics.DrawString($label, $font, [System.Drawing.Brushes]::Black, $column * 128 + 35, $row * 128 + 42)
            $graphics.DrawString('TOP ^', $smallFont, [System.Drawing.Brushes]::Black, $column * 128 + 39, $row * 128 + 7)
            $graphics.DrawString('RIGHT >', $smallFont, [System.Drawing.Brushes]::Black, $column * 128 + 27, $row * 128 + 101)
        }
    }
    $bitmap.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $pen.Dispose(); $font.Dispose(); $smallFont.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'), @'
"GameInfo"
{
    game "ZombieSim clothing UV probe"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths
        {
            game |gameinfo_path|.
        }
    }
}
'@, $utf8)
$tga = Join-Path $source 'uv_probe.tga'
[ZombieSim.SignAssets.Builder]::WriteTga($png, $tga, 1024, 1024)
[System.IO.File]::WriteAllText((Join-Path $source 'uv_probe.txt'), "nolod 1`r`n", $utf8)
$vtex = Join-Path $gameRoot 'bin\vtex.exe'
if (-not (Test-Path -LiteralPath $vtex -PathType Leaf)) { throw "Missing installed vtex: $vtex" }
$vtf = Join-Path $materials 'uv_probe.vtf'
if (Test-Path -LiteralPath $vtf) { Remove-Item -LiteralPath $vtf }
Invoke-SignCompiler $vtex ('-nop4 -nopause -game "{0}" -outdir "{1}" "{2}"' -f $game, $materials, $tga) (Join-Path $output 'vtex.log')
if (-not (Test-Path -LiteralPath $vtf -PathType Leaf)) { throw 'vtex did not produce the UV probe texture.' }
[System.IO.File]::WriteAllText((Join-Path $materials 'uv_probe.vmt'), @'
"VertexLitGeneric"
{
    "$basetexture" "models/zombiesim/clothing/uv_probe"
    "$halflambert" "1"
    "$model" "1"
}
'@, $utf8)
foreach ($extension in 'vtf', 'vmt') {
    $file = Join-Path $materials "uv_probe.$extension"
    foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
        (Join-Path $gameRoot 'garrysmod\materials\models\zombiesim\clothing')) {
        $null = New-Item -ItemType Directory -Force -Path $directory
        $destination = Join-Path $directory "uv_probe.$extension"
        Copy-Item -LiteralPath $file -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $file).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            throw "Clothing UV probe staging hash mismatch: $destination"
        }
    }
}
Write-Host 'Built and root-staged one original numbered UV texture/material. No models, BSPs or player data changed.'
