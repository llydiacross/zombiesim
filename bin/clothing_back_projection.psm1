Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_fabrics.psm1')
$script:backTriangles = @{}

function Get-ClothingBackTriangles {
    param([Parameter(Mandatory)][ValidateSet('male', 'female')][string]$Sex)
    if (-not $script:backTriangles.ContainsKey($Sex)) {
        $model = if ($Sex -eq 'male') { 'male_03' } else { 'female_01' }
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) "generated\clothing_preview\uv_$model.torso.json"
        $torso = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $triangles = foreach ($triangle in $torso) {
            if ($triangle.center[1] -le 0) { continue }
            if ($triangle.positions.Count -ne 3 -or $triangle.uv.Count -ne 6) { throw 'Invalid torso projection triangle.' }
            $valid = $true
            $vertices = for ($i = 0; $i -lt 3; $i++) {
                $u, $v = $triangle.uv[$i * 2], $triangle.uv[$i * 2 + 1]
                if ($u -ge 496 -or $v -lt 584) { $valid = $false }
                foreach ($value in @($u, $v) + @($triangle.positions[$i])) {
                    if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw 'Non-finite torso projection vertex.' }
                    [double]$value
                }
            }
            if ($valid) { ,([double[]]$vertices) }
        }
        if (@($triangles).Count -lt 20) { throw "Missing inspected $Sex back topology; regenerate clothing model inspection." }
        $script:backTriangles[$Sex] = [double[][]]@($triangles)
    }
    return ,$script:backTriangles[$Sex]
}

function New-ClothingBackPath {
    param([Parameter(Mandatory)][ValidateSet('male', 'female')][string]$Sex)
    $path = [Drawing.Drawing2D.GraphicsPath]::new([Drawing.Drawing2D.FillMode]::Winding)
    try {
        foreach ($triangle in (Get-ClothingBackTriangles $Sex)) {
            $points = [Drawing.PointF[]]@(
                [Drawing.PointF]::new($triangle[0], $triangle[1]),
                [Drawing.PointF]::new($triangle[5], $triangle[6]),
                [Drawing.PointF]::new($triangle[10], $triangle[11]))
            if (($points[1].X - $points[0].X) * ($points[2].Y - $points[0].Y) -
                ($points[1].Y - $points[0].Y) * ($points[2].X - $points[0].X) -lt 0) {
                $points[1], $points[2] = $points[2], $points[1]
            }
            $path.AddPolygon($points)
        }
    } catch { $path.Dispose(); throw }
    return $path
}

function Write-ClothingBackProjection {
    param([Parameter(Mandatory)][Drawing.Graphics]$Graphics, [Parameter(Mandatory)][Drawing.Bitmap]$Source,
        [Parameter(Mandatory)][ValidateSet('male', 'female')][string]$Sex, [switch]$FullPrint)
    $triangles = Get-ClothingBackTriangles $Sex
    if ($FullPrint) {
        [ZombieSimFabricRendererV3]::DrawBack($Graphics, $Source, $triangles, $Source.Width / 2, 0, 60,
            $Source.Width / 16, $Source.Height / 20, $false)
    } else {
        [ZombieSimFabricRendererV3]::DrawBack($Graphics, $Source, $triangles, 232, 876, 47, 11, 11, $true)
    }
}

function New-ClothingBackMask {
    param([Parameter(Mandatory)][ValidateSet('male', 'female')][string]$Sex)
    $mask = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($mask)
    $source = [Drawing.Bitmap]::new(1, 1, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $source.SetPixel(0, 0, [Drawing.Color]::White)
        Write-ClothingBackProjection $graphics $source $Sex
    } catch { $mask.Dispose(); throw }
    finally { $graphics.Dispose(); $source.Dispose() }
    return $mask
}

Export-ModuleMember -Function Get-ClothingBackTriangles, New-ClothingBackPath, Write-ClothingBackProjection, New-ClothingBackMask
