Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_back_projection.psm1') -Force
$passed = 0
function Assert-Back([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Clothing back regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
$source = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sourceGraphics = [Drawing.Graphics]::FromImage($source)
$brush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
try {
    $sourceGraphics.Clear([Drawing.Color]::FromArgb(255, 80, 80, 80))
    for ($x = 0; $x -lt 1024; $x++) {
        $brush.Color = [Drawing.Color]::FromArgb(255, 100 + ($x % 60), 100, 100)
        $sourceGraphics.FillRectangle($brush, $x, 0, 1, 1024)
    }
    foreach ($sex in 'male', 'female') {
        $triangles = Get-ClothingBackTriangles $sex
        Assert-Back "$sex retains inspected back triangles, not guessed UV rectangles" ($triangles.Count -gt 200)
        $output = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [Drawing.Graphics]::FromImage($output)
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            Write-ClothingBackProjection $graphics $source $sex
            $vertices = @{}
            foreach ($t in $triangles) {
                foreach ($i in 0, 5, 10) {
                    if ([math]::Abs($t[$i + 2]) -gt 0.1 -or $t[$i + 4] -lt 40 -or $t[$i + 4] -gt 56) { continue }
                    $key = '{0:F3},{1:F3},{2:F3}' -f $t[$i + 2], $t[$i + 3], $t[$i + 4]
                    if (-not $vertices.ContainsKey($key)) { $vertices[$key] = @{} }
                    $vertices[$key]['{0:F2},{1:F2}' -f $t[$i], $t[$i + 1]] = @($t[$i], $t[$i + 1])
                }
            }
            $pairs = 0
            foreach ($group in $vertices.Values) {
                if ($group.Count -ne 2) { continue }
                $pair = @($group.Values)
                if ([math]::Abs($pair[0][0] - $pair[1][0]) -lt 300) { continue }
                $first = $output.GetPixel([int][math]::Floor($pair[0][0]), [int][math]::Floor($pair[0][1]))
                $second = $output.GetPixel([int][math]::Floor($pair[1][0]), [int][math]::Floor($pair[1][1]))
                Assert-Back "$sex seam pair $pairs has no bare garment gap" ($first.A -eq 255 -and $second.A -eq 255)
                Assert-Back "$sex seam pair $pairs samples the same motif phase" ([math]::Abs($first.R - $second.R) -le 3)
                $pairs++
            }
            Assert-Back "$sex checks at least six distinct physical seam heights" ($pairs -ge 6)
            Assert-Back "$sex projection leaves hands, footwear and front chest untouched" (
                $output.GetPixel(900, 660).A -eq 0 -and $output.GetPixel(700, 128).A -eq 0 -and
                $output.GetPixel(232, 876).A -eq 0)
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.SetClip([Drawing.Rectangle]::new(0, 800, 496, 100))
            Write-ClothingBackProjection $graphics $source $sex
            Assert-Back "$sex projection respects the caller clip" (
                $output.GetPixel(20, 750).A -eq 0 -and $output.GetPixel(450, 960).A -eq 0)
            $graphics.ResetClip()
            $graphics.Clear([Drawing.Color]::Transparent)
            $full = [Drawing.Bitmap]::new(176, 224, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $fullGraphics = [Drawing.Graphics]::FromImage($full)
            try {
                $fullGraphics.Clear([Drawing.Color]::FromArgb(255, 200, 80, 30))
                Write-ClothingBackProjection $graphics $full $sex -FullPrint
                $covered = 0
                foreach ($group in $vertices.Values) {
                    if ($group.Count -ne 2) { continue }
                    foreach ($uv in $group.Values) {
                        $pixel = $output.GetPixel([int][math]::Floor($uv[0]), [int][math]::Floor($uv[1]))
                        if ($pixel.A -eq 255 -and $pixel.R -eq 200 -and $pixel.G -eq 80 -and $pixel.B -eq 30) { $covered++ }
                    }
                }
                Assert-Back "$sex full-back print covers both split seam edges without a fabric stripe" ($covered -ge 12)
            } finally { $fullGraphics.Dispose(); $full.Dispose() }
        } finally { $graphics.Dispose(); $output.Dispose() }
    }
} finally { $sourceGraphics.Dispose(); $source.Dispose(); $brush.Dispose() }
Write-Host "Clothing back projection checks passed: $passed/$passed."
