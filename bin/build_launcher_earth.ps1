param(
    [switch]$StageToGame
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force

$root = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $root 'assets\launcher\earth'
$sourcePath = Join-Path $assetRoot 'natural_earth_1.png'
$noticePath = Join-Path $assetRoot 'NOTICE.txt'
$expectedSourceHash = '55745a3b4ccad41db9ed42314de2bf6fce87b6d3990ede7db1730320e1aa2e04'
$output = Join-Path $root 'generated\launcher_earth'
$modelSource = Join-Path $output 'source'
$game = Join-Path $output 'game'
$materials = Join-Path $game 'materials\zombiesim\launcher'
$noticeRelative = 'data_static\launcher_earth\NOTICE.txt'
$manifestRelative = 'data_static\launcher_earth.json'
$content = Join-Path $root 'content'
$gmod = (Resolve-Path (Join-Path $root '..\..')).Path
$gmodInstall = (Resolve-Path (Join-Path $root '..\..\..')).Path
$destinations = @($content)
if ($StageToGame) { $destinations += $gmod }

foreach ($path in $sourcePath, $noticePath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing launcher Earth source: $path" }
}
if ((Get-FileHash -Algorithm SHA256 $sourcePath).Hash.ToLowerInvariant() -ne $expectedSourceHash) {
    throw 'Natural Earth source hash changed; review the replacement before building.'
}
$null = New-Item -ItemType Directory -Force -Path $modelSource, $materials

Add-Type -AssemblyName System.Drawing
if (-not ('ZombieSim.LauncherEarthBuilder' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace ZombieSim {
    public static class LauncherEarthBuilder {
        const int Width = 2048;
        const int Height = 1024;

        static void Save(Bitmap bitmap, string path) {
            bitmap.Save(path, ImageFormat.Png);
        }

        static PointF Project(double latitude, double longitude) {
            return new PointF((float)((longitude + 180.0) / 360.0 * Width),
                (float)((90.0 - latitude) / 180.0 * Height));
        }

        public static void Build(string sourcePath, string outputDirectory) {
            using (var source = new Bitmap(sourcePath)) {
                if (source.Width != Width || source.Height != Height)
                    throw new InvalidOperationException("Launcher Earth source must be 2048x1024.");
                using (var day = new Bitmap(Width, Height, PixelFormat.Format24bppRgb))
                using (var graphics = Graphics.FromImage(day)) {
                    graphics.DrawImageUnscaled(source, 0, 0);
                    Save(day, System.IO.Path.Combine(outputDirectory, "earth_day.png"));
                }
            }

            using (var lights = new Bitmap(Width, Height, PixelFormat.Format32bppArgb))
            using (var graphics = Graphics.FromImage(lights))
            using (var glow = new SolidBrush(Color.FromArgb(205, 255, 166, 64)))
            using (var core = new SolidBrush(Color.FromArgb(245, 255, 225, 150))) {
                graphics.Clear(Color.Transparent);
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                double[,] cities = {
                    { 51.5074, -0.1278 }, { 48.8566, 2.3522 }, { 52.5200, 13.4050 },
                    { 40.7128, -74.0060 }, { 34.0522, -118.2437 }, { 41.8781, -87.6298 },
                    { 19.4326, -99.1332 }, { -23.5505, -46.6333 }, { -34.6037, -58.3816 },
                    { 35.6762, 139.6503 }, { 31.2304, 121.4737 }, { 22.3193, 114.1694 },
                    { 28.6139, 77.2090 }, { 19.0760, 72.8777 }, { 1.3521, 103.8198 },
                    { -33.8688, 151.2093 }, { 25.2048, 55.2708 }, { 30.0444, 31.2357 },
                    { 6.5244, 3.3792 }, { -1.2921, 36.8219 }, { 55.7558, 37.6173 }
                };
                for (int index = 0; index < cities.GetLength(0); index++) {
                    PointF point = Project(cities[index, 0], cities[index, 1]);
                    float size = 5 + (index % 4);
                    graphics.FillEllipse(glow, point.X - size, point.Y - size, size * 2, size * 2);
                    graphics.FillEllipse(core, point.X - 1.5f, point.Y - 1.5f, 3, 3);
                    for (int satellite = 0; satellite < 5; satellite++) {
                        double angle = (index * 47 + satellite * 73) * Math.PI / 180.0;
                        float distance = 5 + satellite * 2;
                        graphics.FillEllipse(core, point.X + (float)Math.Cos(angle) * distance - 0.7f,
                            point.Y + (float)Math.Sin(angle) * distance - 0.7f, 1.4f, 1.4f);
                    }
                }
                Save(lights, System.IO.Path.Combine(outputDirectory, "earth_lights.png"));
            }

            using (var clouds = new Bitmap(Width, Height, PixelFormat.Format32bppArgb))
            using (var graphics = Graphics.FromImage(clouds)) {
                graphics.Clear(Color.Transparent);
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                var random = new Random(315);
                for (int band = 0; band < 34; band++) {
                    float startX = random.Next(-120, Width + 120);
                    float startY = random.Next(90, Height - 90);
                    float direction = random.Next(-18, 19) / 10f;
                    int puffs = random.Next(8, 19);
                    for (int puff = 0; puff < puffs; puff++) {
                        float x = startX + puff * random.Next(9, 20);
                        float y = startY + direction * puff + (float)Math.Sin((band + puff) * 0.8) * 7;
                        float width = random.Next(28, 86);
                        float height = random.Next(6, 20);
                        int alpha = random.Next(10, 31);
                        using (var brush = new SolidBrush(Color.FromArgb(alpha, 218, 224, 216)))
                            graphics.FillEllipse(brush, x - width / 2, y - height / 2, width, height);
                    }
                }
                Save(clouds, System.IO.Path.Combine(outputDirectory, "earth_clouds.png"));
            }

            using (var distress = new Bitmap(Width, Height, PixelFormat.Format32bppArgb))
            using (var graphics = Graphics.FromImage(distress)) {
                graphics.Clear(Color.Transparent);
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                var random = new Random(3115);
                for (int index = 0; index < 46; index++) {
                    PointF start = new PointF(random.Next(Width), random.Next(Height));
                    PointF end = new PointF(start.X + random.Next(-130, 131), start.Y + random.Next(-45, 46));
                    using (var pen = new Pen(Color.FromArgb(random.Next(18, 48), 35, 18, 12), random.Next(2, 8)))
                        graphics.DrawLine(pen, start, end);
                }
                Save(distress, System.IO.Path.Combine(outputDirectory, "earth_distress.png"));
            }

            using (var rim = new Bitmap(256, 256, PixelFormat.Format32bppArgb)) {
                for (int y = 0; y < 256; y++) {
                    for (int x = 0; x < 256; x++) {
                        double dx = (x - 127.5) / 127.5, dy = (y - 127.5) / 127.5;
                        double distance = Math.Sqrt(dx * dx + dy * dy);
                        double alpha = Math.Max(0, 1 - Math.Abs(distance - 0.82) / 0.18);
                        rim.SetPixel(x, y, Color.FromArgb((byte)(Math.Pow(alpha, 2) * 135), 92, 112, 80));
                    }
                }
                Save(rim, System.IO.Path.Combine(outputDirectory, "earth_rim.png"));
            }
        }
    }
}
'@
}

[ZombieSim.LauncherEarthBuilder]::Build($sourcePath, $modelSource)

$textures = [ordered]@{
    earth_day = $false
    earth_lights = $true
    earth_clouds = $true
    earth_distress = $true
    earth_rim = $true
}
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'), @'
"GameInfo"
{
    game "ZombieSim launcher Earth"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths { game |gameinfo_path|. }
    }
}
'@, $utf8)

$vtex = Join-Path $gmodInstall 'bin\vtex.exe'
if (-not (Test-Path -LiteralPath $vtex -PathType Leaf)) { throw "Missing Source compiler: $vtex" }
$owned = @()
$textureRecords = @()
foreach ($name in $textures.Keys) {
    $png = Join-Path $modelSource "$name.png"
    $image = [Drawing.Image]::FromFile($png)
    try { $width, $height = $image.Width, $image.Height } finally { $image.Dispose() }
    $tga = Join-Path $modelSource "$name.tga"
    [ZombieSim.SignAssets.Builder]::WriteTga($png, $tga, $width, $height, [bool]$textures[$name])
    [IO.File]::WriteAllText((Join-Path $modelSource "$name.txt"), "nolod 1`r`n", $utf8)
    $vtf = Join-Path $materials "$name.vtf"
    if (Test-Path -LiteralPath $vtf) { Remove-Item -LiteralPath $vtf }
    Invoke-SignCompiler $vtex ('-nop4 -nopause -game "{0}" -outdir "{1}" "{2}"' -f
        $game, $materials, $tga) (Join-Path $modelSource "$name-vtex.log")
    if (-not (Test-Path -LiteralPath $vtf -PathType Leaf)) { throw "vtex produced no texture: $name" }
    $relative = "materials\zombiesim\launcher\$name.vtf"
    $owned += $relative
    $textureRecords += [pscustomobject][ordered]@{
        id = $name
        width = $width
        height = $height
        sourceSha256 = (Get-FileHash -Algorithm SHA256 $png).Hash.ToLowerInvariant()
        vtfSha256 = (Get-FileHash -Algorithm SHA256 $vtf).Hash.ToLowerInvariant()
        compressedBytes = (Get-Item -LiteralPath $vtf).Length
        estimatedRgbaBytes = $width * $height * 4
    }
}

$materialsText = [ordered]@{
    earth_day = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_day" "$vertexcolor" "1" "$nocull" "1" "$nofog" "1" }'
    earth_lights = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_lights" "$additive" "1" "$vertexalpha" "1" "$nofog" "1" }'
    earth_clouds = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_clouds" "$translucent" "1" "$vertexalpha" "1" "$nocull" "1" "$nofog" "1" }'
    earth_distress = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_distress" "$translucent" "1" "$vertexalpha" "1" "$nocull" "1" "$nofog" "1" }'
    earth_rim = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_rim" "$additive" "1" "$vertexalpha" "1" "$nofog" "1" }'
}
foreach ($name in $materialsText.Keys) {
    $vmt = Join-Path $materials "$name.vmt"
    [IO.File]::WriteAllText($vmt, $materialsText[$name], $utf8)
    $owned += "materials\zombiesim\launcher\$name.vmt"
}

$manifest = [ordered]@{
    schemaVersion = 1
    source = [ordered]@{
        title = 'Natural Earth I'
        sourcePage = 'https://www.naturalearthdata.com/downloads/50m-raster-data/50m-natural-earth-1/'
        terms = 'https://www.naturalearthdata.com/about/terms-of-use/'
        permission = 'Public domain; use, modification and redistribution permitted without required credit.'
        sourceSha256 = $expectedSourceHash
        noticeFile = $noticeRelative.Replace('\', '/')
    }
    textures = $textureRecords
    ownedFiles = $owned
    ownedNoticeFiles = @($noticeRelative)
}
$manifestJson = $manifest | ConvertTo-Json -Depth 6
foreach ($destinationRoot in $destinations) {
    foreach ($relative in $owned) {
        $source = Join-Path $game $relative
        $destination = Join-Path $destinationRoot $relative
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ((Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash) { throw "Launcher Earth staging mismatch: $destination" }
    }
    $noticeDestination = Join-Path $destinationRoot $noticeRelative
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $noticeDestination)
    Copy-Item -LiteralPath $noticePath -Destination $noticeDestination -Force
    $manifestDestination = Join-Path $destinationRoot $manifestRelative
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestDestination)
    [IO.File]::WriteAllText($manifestDestination, $manifestJson, $utf8)
}

Write-Host ("Built launcher Earth: {0} texture layers, {1:N2} MiB VTF, {2:N2} MiB estimated RGBA." -f
    $textureRecords.Count,
    (($textureRecords | Measure-Object -Property compressedBytes -Sum).Sum / 1MB),
    (($textureRecords | Measure-Object -Property estimatedRgbaBytes -Sum).Sum / 1MB))
