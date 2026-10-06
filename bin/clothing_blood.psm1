Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_back_projection.psm1')
Add-Type -AssemblyName System.Drawing

function New-ClothingBloodLayer {
    param([Parameter(Mandatory)]$Settings, [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][ValidateSet('shirt', 'pants')][string]$Garment,
        [ValidateSet('male', 'female')][string]$Sex = 'male')
    if ($Settings.schemaVersion -ne 1 -or $Definition.size -ne 1024 -or
        $Settings.colour -notmatch '^#[0-9A-Fa-f]{6}$') { throw 'Invalid clothing blood schema/colour.' }
    foreach ($pair in @(@('seed', 0, 2147483000), @('patches', 1, 512), @('droplets', 0, 2048), @('maximumAlpha', 1, 240))) {
        $value = $Settings.($pair[0])
        if ($value -ne [math]::Floor($value) -or $value -lt $pair[1] -or $value -gt $pair[2]) {
            throw "Invalid clothing blood setting: $($pair[0])"
        }
    }
    $source = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $result = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $paint = [Drawing.Graphics]::FromImage($source)
    $graphics = [Drawing.Graphics]::FromImage($result)
    $mask = [Drawing.Drawing2D.GraphicsPath]::new()
    $inner = [Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $random = [Random]::new([int]$Settings.seed)
        $colour = [Drawing.ColorTranslator]::FromHtml($Settings.colour)
        $paint.Clear([Drawing.Color]::Transparent)
        $paint.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        for ($i = 0; $i -lt $Settings.patches + $Settings.droplets; $i++) {
            $x = $random.Next(1024); $y = $random.Next(1024)
            $radius = if ($i -lt $Settings.patches) { $random.Next(8, 34) } else { $random.Next(1, 5) }
            $alpha = $random.Next([int][math]::Max(1, $Settings.maximumAlpha / 3), [int]$Settings.maximumAlpha + 1)
            $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb($alpha, $colour))
            try {
                if ($i -lt $Settings.patches) {
                    $stain = [Drawing.Drawing2D.GraphicsPath]::new()
                    $gradient = $null
                    try {
                        $points = [Drawing.PointF[]]::new(16)
                        for ($p = 0; $p -lt 16; $p++) {
                            $angle = 2 * [math]::PI * $p / 16
                            $reach = $radius * (0.55 + $random.NextDouble() * 0.65)
                            $points[$p] = [Drawing.PointF]::new($x + [math]::Cos($angle) * $reach,
                                $y + [math]::Sin($angle) * $reach)
                        }
                        $stain.AddClosedCurve($points)
                        $gradient = [Drawing.Drawing2D.PathGradientBrush]::new($stain)
                        $gradient.CenterColor = [Drawing.Color]::FromArgb($alpha, $colour)
                        $gradient.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, $colour))
                        $paint.FillPath($gradient, $stain)
                    } finally {
                        if ($null -ne $gradient) { $gradient.Dispose() }
                        $stain.Dispose()
                    }
                    for ($j = 0; $j -lt 7; $j++) {
                        $small = $random.Next(2, 10)
                        $paint.FillEllipse($brush, $x + $random.Next(-2 * $radius, 2 * $radius),
                            $y + $random.Next(-2 * $radius, 2 * $radius), $small, $small)
                    }
                } else { $paint.FillEllipse($brush, $x - $radius, $y - $radius, 2 * $radius, 2 * $radius) }
            } finally { $brush.Dispose() }
        }
        foreach ($r in $Definition.$Garment.regions) {
            if ($r.Count -ne 4 -or $r[0] -lt 0 -or $r[1] -lt 0 -or $r[2] -lt 1 -or $r[3] -lt 1 -or
                $r[0] + $r[2] -gt 1024 -or $r[1] + $r[3] -gt 1024) { throw 'Invalid blood garment mask rectangle.' }
            $mask.AddRectangle([Drawing.Rectangle]::new($r[0], $r[1], $r[2], $r[3]))
        }
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SetClip($mask)
        if ($Garment -eq 'shirt') {
            foreach ($polygon in $Definition.shirt.innerShirt.polygons.$Sex) {
                $points = [Drawing.PointF[]]@($polygon | ForEach-Object { [Drawing.PointF]::new($_[0], $_[1]) })
                $inner.AddPolygon($points)
            }
            $graphics.SetClip($inner, [Drawing.Drawing2D.CombineMode]::Exclude)
            $state = $graphics.Save()
            $back = New-ClothingBackPath $Sex
            try {
                $graphics.SetClip($back, [Drawing.Drawing2D.CombineMode]::Exclude)
                $graphics.DrawImageUnscaled($source, 0, 0)
            } finally { $graphics.Restore($state); $back.Dispose() }
            Write-ClothingBackProjection $graphics $source $Sex
        } else { $graphics.DrawImageUnscaled($source, 0, 0) }
    } catch { $result.Dispose(); throw }
    finally { $inner.Dispose(); $mask.Dispose(); $paint.Dispose(); $graphics.Dispose(); $source.Dispose() }
    return $result
}

Export-ModuleMember -Function New-ClothingBloodLayer
