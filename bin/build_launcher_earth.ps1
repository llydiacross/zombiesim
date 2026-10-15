param(
    [switch]$StageToGame
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force

$root = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $root 'assets\launcher\earth'
$sourcePath = Join-Path $assetRoot 'natural_earth_1.png'
$nightSourcePath = Join-Path $assetRoot 'black_marble_2016.jpg'
$noticePath = Join-Path $assetRoot 'NOTICE.txt'
$expectedSourceHash = '55745a3b4ccad41db9ed42314de2bf6fce87b6d3990ede7db1730320e1aa2e04'
$expectedNightSourceHash = '1785ebc5f476b658df7f7c84cff4ba4ecf997c9331756de370ba8ef1daba575a'
$fullSourceArchiveUrl = 'https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip'
$expectedFullSourceArchiveHash = '9e85417223414bbed425aea5dca0f0b4c5661fc94d4f14494140a21a08dfa450'
$output = Join-Path $root 'generated\launcher_earth'
$archiveCache = Join-Path $output 'archive'
$fullSourceArchive = Join-Path $archiveCache 'NE1_50M_SR_W.zip'
$fullSourcePath = Join-Path $archiveCache 'NE1_50M_SR_W\NE1_50M_SR_W.tif'
$fullNightSourceUrl = 'https://assets.science.nasa.gov/content/dam/science/esd/eo/images/imagerecords/144000/144898/BlackMarble_2016_3km.jpg'
$expectedFullNightSourceHash = '230aac448ae68c358be433dd518888cccb3a85ccf66f7b44326441c324ad6725'
$fullNightSourcePath = Join-Path $archiveCache 'BlackMarble_2016_3km.jpg'
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

foreach ($path in $sourcePath, $nightSourcePath, $noticePath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing launcher Earth source: $path" }
}
if ((Get-FileHash -Algorithm SHA256 $sourcePath).Hash.ToLowerInvariant() -ne $expectedSourceHash) {
    throw 'Natural Earth source hash changed; review the replacement before building.'
}
if ((Get-FileHash -Algorithm SHA256 $nightSourcePath).Hash.ToLowerInvariant() -ne $expectedNightSourceHash) {
    throw 'NASA Black Marble source hash changed; review the replacement before building.'
}
$null = New-Item -ItemType Directory -Force -Path $modelSource, $materials, $archiveCache

# The close-zoom layer needs the full-resolution reviewed archive; it is cached
# under generated/ rather than committed, and is always verified by hash.
if (-not (Test-Path -LiteralPath $fullSourceArchive -PathType Leaf)) {
    & curl.exe -sSfL -o $fullSourceArchive $fullSourceArchiveUrl
    if ($LASTEXITCODE -ne 0) { throw "Could not download the Natural Earth archive: $fullSourceArchiveUrl" }
}
if ((Get-FileHash -Algorithm SHA256 $fullSourceArchive).Hash.ToLowerInvariant() -ne $expectedFullSourceArchiveHash) {
    throw 'Natural Earth archive hash changed; review the replacement before building.'
}
if (-not (Test-Path -LiteralPath $fullSourcePath -PathType Leaf)) {
    Expand-Archive -LiteralPath $fullSourceArchive -DestinationPath $archiveCache -Force
    if (-not (Test-Path -LiteralPath $fullSourcePath -PathType Leaf)) { throw "Archive did not contain $fullSourcePath" }
}
if (-not (Test-Path -LiteralPath $fullNightSourcePath -PathType Leaf)) {
    & curl.exe -sSfL -o $fullNightSourcePath $fullNightSourceUrl
    if ($LASTEXITCODE -ne 0) { throw "Could not download the NASA Black Marble 3 km image: $fullNightSourceUrl" }
}
if ((Get-FileHash -Algorithm SHA256 $fullNightSourcePath).Hash.ToLowerInvariant() -ne $expectedFullNightSourceHash) {
    throw 'NASA Black Marble 3 km source hash changed; review the replacement before building.'
}

Add-Type -AssemblyName System.Drawing
if (-not ('ZombieSim.LauncherEarthBuilder' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ZombieSim {
    public static class LauncherEarthBuilder {
        const int Width = 2048;
        const int Height = 1024;

        static void Save(Bitmap bitmap, string path) {
            bitmap.Save(path, ImageFormat.Png);
        }

        static byte Clamp(double value) {
            return (byte)Math.Max(0, Math.Min(255, (int)Math.Round(value)));
        }

        static int Wrap(int value, int period) {
            value %= period;
            return value < 0 ? value + period : value;
        }

        static double LatticeValue(int x, int y, int seed) {
            unchecked {
                uint hash = (uint)x * 374761393u + (uint)y * 668265263u + (uint)seed * 1442695041u;
                hash = (hash ^ (hash >> 13)) * 1274126177u;
                hash ^= hash >> 16;
                return (hash & 0x00ffffffu) / 16777215.0;
            }
        }

        static double Smooth(double value) {
            return value * value * (3 - 2 * value);
        }

        static double ValueNoise(double u, double v, int cellsX, int cellsY, int seed) {
            double x = u * cellsX;
            int x0 = (int)Math.Floor(x);
            double y = Math.Max(0, Math.Min(cellsY, v * cellsY));
            int y0 = (int)Math.Floor(y);
            int y1 = Math.Min(y0 + 1, cellsY);
            double amountX = Smooth(x - x0);
            double amountY = Smooth(y - y0);
            double top = LatticeValue(Wrap(x0, cellsX), y0, seed) * (1 - amountX)
                + LatticeValue(Wrap(x0 + 1, cellsX), y0, seed) * amountX;
            double bottom = LatticeValue(Wrap(x0, cellsX), y1, seed) * (1 - amountX)
                + LatticeValue(Wrap(x0 + 1, cellsX), y1, seed) * amountX;
            return top * (1 - amountY) + bottom * amountY;
        }

        static void BuildNightLights(string sourcePath, string outputDirectory, int width, int height, string name,
                int sourceWidth, int sourceHeight, double floor) {
            using (var source = new Bitmap(sourcePath)) {
                if (source.Width != sourceWidth || source.Height != sourceHeight)
                    throw new InvalidOperationException("NASA Black Marble source must be " + sourceWidth + "x" + sourceHeight + ".");
                using (var night = new Bitmap(width, height, PixelFormat.Format24bppRgb))
                using (var graphics = Graphics.FromImage(night)) {
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    using (var wrap = new ImageAttributes()) {
                        wrap.SetWrapMode(WrapMode.TileFlipXY);
                        graphics.DrawImage(source, new Rectangle(0, 0, width, height),
                            0, 0, source.Width, source.Height, GraphicsUnit.Pixel, wrap);
                    }
                    var rectangle = new Rectangle(0, 0, width, height);
                    var data = night.LockBits(rectangle, ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
                    try {
                        int stride = Math.Abs(data.Stride);
                        byte[] pixels = new byte[stride * height];
                        Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
                        for (int y = 0; y < height; y++) {
                            for (int x = 0; x < width; x++) {
                                int index = y * stride + x * 3;
                                double blue = pixels[index], green = pixels[index + 1], red = pixels[index + 2];
                                double luminance = Math.Max(0, red * 0.299 + green * 0.587 + blue * 0.114 - floor) * (255 - 24) / (255 - floor);
                                pixels[index] = Clamp(255 * Math.Pow(luminance / 255, 1.2) * 0.55);
                                pixels[index + 1] = Clamp(255 * Math.Pow(luminance / 255, 1.08) * 0.68);
                                pixels[index + 2] = Clamp(255 * Math.Pow(luminance / 255, 0.94));
                            }
                        }
                        Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
                    } finally {
                        night.UnlockBits(data);
                    }
                    Save(night, System.IO.Path.Combine(outputDirectory, name + ".png"));
                }
            }
        }

        // White soft-noise puff tinted at runtime for drifting launcher space fog and blast smoke.
        static void BuildSpaceFog(string outputDirectory) {
            const int Size = 512;
            using (var fog = new Bitmap(Size, Size, PixelFormat.Format32bppArgb)) {
                var data = fog.LockBits(new Rectangle(0, 0, Size, Size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                try {
                    int stride = Math.Abs(data.Stride);
                    byte[] pixels = new byte[stride * Size];
                    for (int y = 0; y < Size; y++) {
                        double v = (double)y / (Size - 1);
                        for (int x = 0; x < Size; x++) {
                            double u = (double)x / Size;
                            double dx = u * 2 - 1, dy = v * 2 - 1;
                            double warp = (ValueNoise(u, v, 4, 4, 701) - 0.5) * 0.35;
                            double radius = Math.Sqrt(dx * dx + dy * dy) + warp;
                            double falloff = Smooth(Math.Max(0, Math.Min(1, (0.95 - radius) / 0.75)));
                            double density = ValueNoise(u, v, 5, 5, 711) * 0.5 + ValueNoise(u, v, 11, 11, 712) * 0.3
                                + ValueNoise(u, v, 27, 27, 713) * 0.2;
                            double alpha = falloff * Smooth(Math.Max(0, Math.Min(1, (density - 0.25) / 0.6))) * 255;
                            byte tone = Clamp(200 + (density - 0.5) * 90);
                            int index = y * stride + x * 4;
                            pixels[index] = tone;
                            pixels[index + 1] = tone;
                            pixels[index + 2] = tone;
                            pixels[index + 3] = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(alpha)));
                        }
                    }
                    Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
                } finally {
                    fog.UnlockBits(data);
                }
                Save(fog, System.IO.Path.Combine(outputDirectory, "space_fog.png"));
            }
        }

        static void BuildClouds(string outputDirectory) {
            using (var clouds = new Bitmap(Width, Height, PixelFormat.Format32bppArgb)) {
                var rectangle = new Rectangle(0, 0, Width, Height);
                var data = clouds.LockBits(rectangle, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                try {
                    int stride = Math.Abs(data.Stride);
                    byte[] pixels = new byte[stride * Height];
                    for (int y = 0; y < Height; y++) {
                        double v = (double)y / (Height - 1);
                        for (int x = 0; x < Width; x++) {
                            double u = (double)x / Width;
                            double warpX = (ValueNoise(u, v, 5, 3, 281) - 0.5) * 0.12;
                            double warpY = (ValueNoise(u + 0.37, v + 0.61, 5, 3, 282) - 0.5) * 0.08;
                            double warpedU = u + warpX, warpedV = v + warpY;
                            double broad = ValueNoise(warpedU, warpedV, 8, 4, 315);
                            double medium = ValueNoise(warpedU, warpedV, 18, 9, 316);
                            double fine = ValueNoise(warpedU, warpedV, 40, 20, 317);
                            double wisps = ValueNoise(warpedU, warpedV, 88, 44, 318);
                            double density = broad * 0.45 + medium * 0.32 + fine * 0.16 + wisps * 0.07;
                            double coverage = Smooth(Math.Max(0, Math.Min(1, (density - 0.49) / 0.22)));
                            double wispyDetail = 0.35 + fine * 0.4 + wisps * 0.25;
                            double cloudAlpha = coverage * (8 + wispyDetail * 18);
                            double turbulence = (fine - 0.5) * 7 + (wisps - 0.5) * 3;
                            byte tone = Clamp(149 + wispyDetail * 20 + turbulence);
                            int index = y * stride + x * 4;
                            pixels[index] = tone;
                            pixels[index + 1] = tone;
                            pixels[index + 2] = tone;
                            pixels[index + 3] = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(cloudAlpha)));
                        }
                    }
                    Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
                } finally {
                    clouds.UnlockBits(data);
                }
                Save(clouds, System.IO.Path.Combine(outputDirectory, "earth_clouds.png"));
            }
        }

        static void GradeForScorchedEarth(Bitmap bitmap) {
            var rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            var data = bitmap.LockBits(rectangle, ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
            try {
                int stride = Math.Abs(data.Stride);
                byte[] pixels = new byte[stride * bitmap.Height];
                Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
                for (int y = 0; y < bitmap.Height; y++) {
                    for (int x = 0; x < bitmap.Width; x++) {
                        int index = y * stride + x * 3;
                        double blue = pixels[index], green = pixels[index + 1], red = pixels[index + 2];
                        double luminance = red * 0.299 + green * 0.587 + blue * 0.114;
                        bool ocean = blue > red * 1.08 && blue > green * 1.02;
                        if (ocean) {
                            pixels[index] = Clamp(12 + luminance * 0.17);
                            pixels[index + 1] = Clamp(13 + luminance * 0.15);
                            pixels[index + 2] = Clamp(12 + luminance * 0.13);
                        } else if (red > 220 && green > 220 && blue > 220) {
                            pixels[index] = 132;
                            pixels[index + 1] = 136;
                            pixels[index + 2] = 134;
                        } else {
                            double relief = Math.Max(0, Math.Min(1, (luminance - 24) / 210));
                            pixels[index] = Clamp(20 + relief * 48);
                            pixels[index + 1] = Clamp(22 + relief * 49);
                            pixels[index + 2] = Clamp(19 + relief * 46);
                        }
                    }
                }
                Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
            } finally {
                bitmap.UnlockBits(data);
            }
        }

        public static void Build(string sourcePath, string nightSourcePath, string outputDirectory) {
            using (var source = new Bitmap(sourcePath)) {
                if (source.Width != Width || source.Height != Height)
                    throw new InvalidOperationException("Launcher Earth source must be 2048x1024.");
                using (var day = new Bitmap(Width, Height, PixelFormat.Format24bppRgb))
                using (var graphics = Graphics.FromImage(day)) {
                    graphics.DrawImageUnscaled(source, 0, 0);
                    GradeForScorchedEarth(day);
                    Save(day, System.IO.Path.Combine(outputDirectory, "earth_day.png"));
                }
            }

            BuildNightLights(nightSourcePath, outputDirectory, Width, Height, "earth_lights", 3600, 1800, 24);
            BuildClouds(outputDirectory);
            BuildSpaceFog(outputDirectory);

            using (var distress = new Bitmap(Width, Height, PixelFormat.Format32bppArgb))
            using (var graphics = Graphics.FromImage(distress)) {
                graphics.Clear(Color.Transparent);
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                var random = new Random(3115);
                for (int index = 0; index < 34; index++) {
                    PointF centre = new PointF(random.Next(Width), random.Next(Height));
                    float width = random.Next(72, 245), height = random.Next(30, 126);
                    for (int layer = 0; layer < 5; layer++) {
                        float inset = layer * 0.13f;
                        int alpha = random.Next(14, 34);
                        using (var brush = new SolidBrush(Color.FromArgb(alpha, 21, 24, 22))) {
                            graphics.FillEllipse(brush,
                                centre.X - width * (1 - inset) / 2,
                                centre.Y - height * (1 - inset) / 2,
                                width * (1 - inset),
                                height * (1 - inset));
                        }
                    }
                }
                Save(distress, System.IO.Path.Combine(outputDirectory, "earth_distress.png"));
            }

            using (var rim = new Bitmap(256, 256, PixelFormat.Format32bppArgb)) {
                for (int y = 0; y < 256; y++) {
                    for (int x = 0; x < 256; x++) {
                        double dx = (x - 127.5) / 127.5, dy = (y - 127.5) / 127.5;
                        double distance = Math.Sqrt(dx * dx + dy * dy);
                        double alpha = Math.Max(0, 1 - Math.Abs(distance - 0.82) / 0.18);
                        rim.SetPixel(x, y, Color.FromArgb((byte)(Math.Pow(alpha, 2) * 85), 196, 66, 24));
                    }
                }
                Save(rim, System.IO.Path.Combine(outputDirectory, "earth_rim.png"));
            }
        }

        // Close-zoom layers: resampled from the full 10800x5400 Natural Earth raster
        // rather than upscaling the 2048 import, then graded identically.
        public static void BuildHighDetail(string fullSourcePath, string fullNightSourcePath, string outputDirectory) {
            const int HighWidth = 4096, HighHeight = 2048;
            using (var source = new Bitmap(fullSourcePath)) {
                if (source.Width != 10800 || source.Height != 5400)
                    throw new InvalidOperationException("Full Natural Earth source must be 10800x5400.");
                using (var day = new Bitmap(HighWidth, HighHeight, PixelFormat.Format24bppRgb))
                using (var graphics = Graphics.FromImage(day))
                using (var wrap = new ImageAttributes()) {
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    wrap.SetWrapMode(WrapMode.TileFlipXY);
                    graphics.DrawImage(source, new Rectangle(0, 0, HighWidth, HighHeight),
                        0, 0, source.Width, source.Height, GraphicsUnit.Pixel, wrap);
                    GradeForScorchedEarth(day);
                    Save(day, System.IO.Path.Combine(outputDirectory, "earth_day_hd.png"));
                }
            }
            // Downsampled from the 3 km product so close-zoom lights gain real detail;
            // its colour composite carries faint land relief, so a higher floor removes it.
            BuildNightLights(fullNightSourcePath, outputDirectory, HighWidth, HighHeight, "earth_lights_hd", 13500, 6750, 48);
        }
    }
}
'@
}

[ZombieSim.LauncherEarthBuilder]::Build($sourcePath, $nightSourcePath, $modelSource)
[ZombieSim.LauncherEarthBuilder]::BuildHighDetail($fullSourcePath, $fullNightSourcePath, $modelSource)

$textures = [ordered]@{
    earth_day = $false
    earth_lights = $true
    earth_day_hd = $false
    earth_lights_hd = $true
    earth_clouds = $true
    earth_distress = $true
    earth_rim = $true
    space_fog = $true
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
    earth_lights = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_lights" "$vertexcolor" "1" "$vertexalpha" "1" "$translucent" "1" "$nocull" "1" "$nofog" "1" }'
    earth_day_hd = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_day_hd" "$vertexcolor" "1" "$vertexalpha" "1" "$translucent" "1" "$nocull" "1" "$nofog" "1" }'
    earth_lights_hd = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_lights_hd" "$vertexcolor" "1" "$vertexalpha" "1" "$translucent" "1" "$nocull" "1" "$nofog" "1" }'
    earth_clouds = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_clouds" "$translucent" "1" "$vertexalpha" "1" "$nocull" "1" "$nofog" "1" }'
    earth_distress = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_distress" "$translucent" "1" "$vertexalpha" "1" "$nocull" "1" "$nofog" "1" }'
    earth_rim = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/earth_rim" "$additive" "1" "$vertexalpha" "1" "$nofog" "1" }'
        space_fog = '"UnlitGeneric" { "$basetexture" "zombiesim/launcher/space_fog" "$vertexcolor" "1" "$vertexalpha" "1" "$translucent" "1" "$nocull" "1" "$nofog" "1" }'
    }
foreach ($name in $materialsText.Keys) {
    $vmt = Join-Path $materials "$name.vmt"
    [IO.File]::WriteAllText($vmt, $materialsText[$name], $utf8)
    $owned += "materials\zombiesim\launcher\$name.vmt"
}

$manifest = [ordered]@{
    schemaVersion = 1
    source = [ordered]@{
        title = 'Natural Earth I and NASA Black Marble 2016'
        sourcePage = 'https://www.naturalearthdata.com/downloads/50m-raster-data/50m-natural-earth-1/'
        terms = 'https://www.naturalearthdata.com/about/terms-of-use/'
        permission = 'Public domain; use, modification and redistribution permitted without required credit.'
        sourceSha256 = $expectedSourceHash
        highDetailSource = [ordered]@{
            archive = $fullSourceArchiveUrl
            archiveSha256 = $expectedFullSourceArchiveHash
            image = 'NE1_50M_SR_W.tif (10800x5400), resampled to 4096x2048 for close zoom'
        }
        nightLights = [ordered]@{
            title = 'Black Marble 2016'
            sourcePage = 'https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/'
            sourceImage = 'https://assets.science.nasa.gov/dynamicimage/assets/science/esd/eo/images/imagerecords/144000/144898/BlackMarble_2016_01deg.jpg?w=3600&h=1800&fit=clip'
            sourceSha256 = $expectedNightSourceHash
            highDetailImage = $fullNightSourceUrl
            highDetailSha256 = $expectedFullNightSourceHash
            highDetailDescription = 'BlackMarble_2016_3km.jpg (13500x6750), normalized and resampled to 4096x2048 for close zoom'
            credit = 'NASA Goddard Space Flight Center; scientist Miguel Roman; image processing Joshua Stevens (SSAI); Suomi NPP VIIRS.'
        }
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
