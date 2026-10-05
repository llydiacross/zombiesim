Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_artwork.psm1') -Force
$passed = 0
function Assert-Artwork([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Artwork fitting regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
foreach ($dimensions in @(@(80, 20), @(20, 80), @(20, 20), @(8, 400))) {
    $source = [Drawing.Bitmap]::new($dimensions[0], $dimensions[1])
    $graphics = [Drawing.Graphics]::FromImage($source)
    try { $graphics.Clear([Drawing.Color]::Red) } finally { $graphics.Dispose() }
    foreach ($alignment in 'center', 'bottom') {
        $canvas = New-FittedArtwork $source 88 344 $alignment
        try {
            $minX = 88; $maxX = -1; $minY = 344; $maxY = -1
            for ($y = 0; $y -lt 344; $y++) {
                for ($x = 0; $x -lt 88; $x++) {
                    if ($canvas.GetPixel($x, $y).A -lt 128) { continue }
                    $minX = [math]::Min($minX, $x); $maxX = [math]::Max($maxX, $x)
                    $minY = [math]::Min($minY, $y); $maxY = [math]::Max($maxY, $y)
                }
            }
            $scale = [math]::Min([double](88 / $dimensions[0]), [double](344 / $dimensions[1]))
            $edgeTolerance = if ($alignment -eq 'bottom') { 1 } else { 2 }
            Assert-Artwork "$($dimensions -join 'x')/$alignment preserves aspect without stretch/crop [$minX,$maxX,$minY,$maxY]" (
                [math]::Abs(($maxX - $minX + 1) - $dimensions[0] * $scale) -le $edgeTolerance -and
                [math]::Abs(($maxY - $minY + 1) - $dimensions[1] * $scale) -le $edgeTolerance)
            Assert-Artwork "$($dimensions -join 'x')/$alignment horizontally centered" ([math]::Abs($minX - (87 - $maxX)) -le $edgeTolerance)
            if ($alignment -eq 'bottom') {
                Assert-Artwork "$($dimensions -join 'x') bottom ends at last canvas row" ($maxY -eq 343)
            } else {
                Assert-Artwork "$($dimensions -join 'x') default stays vertically centered" ([math]::Abs($minY - (343 - $maxY)) -le $edgeTolerance)
            }
        } finally { $canvas.Dispose() }
    }
    $source.Dispose()
}
$source = [Drawing.Bitmap]::new(8, 8)
try {
    $failed = $false
    try { $canvas = New-FittedArtwork $source 88 344 'unknown'; $canvas.Dispose() } catch { $failed = $true }
    Assert-Artwork 'invalid alignment fails explicitly' $failed
} finally { $source.Dispose() }
Write-Host "Clothing artwork checks passed: $passed/$passed."
