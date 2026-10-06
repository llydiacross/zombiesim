Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('ZombieSim.Clothing.CitizenCalibration' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
namespace ZombieSim.Clothing {
    public static class CitizenCalibration {
        static readonly int[][] Orders = {
            new[] {0,1,2}, new[] {0,2,1}, new[] {1,0,2},
            new[] {1,2,0}, new[] {2,0,1}, new[] {2,1,0}
        };
        public static double[] FitAxis(double[] source, double[] target) {
            if (source.Length < 6 || source.Length != target.Length)
                throw new ArgumentException("Atlas fitting requires matching coordinate samples.");
            var random = new Random(310);
            int most = -1;
            double slope = 0, offset = 0;
            const double tolerance = 0.75 / 1024;
            for (int attempt = 0; attempt < 1000; attempt++) {
                int first = random.Next(source.Length), second = random.Next(source.Length);
                double span = source[second] - source[first];
                if (Math.Abs(span) < 0.03) continue;
                double a = (target[second] - target[first]) / span;
                double b = target[first] - a * source[first];
                if (a < 0.5 || a > 2) continue;
                int hits = 0;
                for (int i = 0; i < source.Length; i++)
                    if (Math.Abs(target[i] - a * source[i] - b) <= tolerance) hits++;
                if (hits > most) { most = hits; slope = a; offset = b; }
            }
            if (most < 6) throw new ArgumentException("No reliable upright atlas transform.");
            for (int pass = 0; pass < 3; pass++) {
                double x = 0, y = 0, xx = 0, xy = 0;
                int count = 0;
                for (int i = 0; i < source.Length; i++) {
                    if (Math.Abs(target[i] - slope * source[i] - offset) > tolerance) continue;
                    x += source[i]; y += target[i]; xx += source[i] * source[i];
                    xy += source[i] * target[i]; count++;
                }
                double denominator = count * xx - x * x;
                if (count < 6 || Math.Abs(denominator) < 1e-10)
                    throw new ArgumentException("Degenerate atlas calibration.");
                slope = (count * xy - x * y) / denominator;
                offset = (y - slope * x) / count;
            }
            int inliers = 0;
            double maximum = 0;
            for (int i = 0; i < source.Length; i++) {
                double error = Math.Abs(target[i] - slope * source[i] - offset);
                if (error <= tolerance) { inliers++; maximum = Math.Max(maximum, error * 1024); }
            }
            return new[] { slope, offset, (double)inliers, maximum };
        }
        public static double[] Match(double[] source, double[] target) {
            if (source.Length == 0 || source.Length % 9 != 0 || target.Length % 9 != 0)
                throw new ArgumentException("Calibration requires complete physical triangles.");
            int count = source.Length / 9;
            var centers = new double[count * 3];
            for (int s = 0; s < count; s++)
                for (int axis = 0; axis < 3; axis++)
                    centers[s * 3 + axis] = (source[s * 9 + axis] +
                        source[s * 9 + 3 + axis] + source[s * 9 + 6 + axis]) / 3;
            var result = new double[target.Length / 9 * 5];
            for (int t = 0; t < target.Length / 9; t++) {
                var center = new double[3];
                for (int axis = 0; axis < 3; axis++)
                    center[axis] = (target[t * 9 + axis] +
                        target[t * 9 + 3 + axis] + target[t * 9 + 6 + axis]) / 3;
                double best = double.PositiveInfinity, maximum = 0;
                int selected = -1, order = 0;
                for (int s = 0; s < count; s++) {
                    double centerDistance = 0;
                    for (int axis = 0; axis < 3; axis++) {
                        double delta = center[axis] - centers[s * 3 + axis];
                        centerDistance += delta * delta;
                    }
                    if (centerDistance * 3 > best + 1e-10) continue;
                    for (int p = 0; p < Orders.Length; p++) {
                        double score = 0, farthest = 0;
                        for (int corner = 0; corner < 3; corner++) {
                            double distance = 0;
                            for (int axis = 0; axis < 3; axis++) {
                                double delta = target[t * 9 + corner * 3 + axis] -
                                    source[s * 9 + Orders[p][corner] * 3 + axis];
                                distance += delta * delta;
                            }
                            score += distance;
                            farthest = Math.Max(farthest, distance);
                        }
                        if (score < best) {
                            best = score; selected = s; order = p; maximum = farthest;
                        }
                    }
                }
                int offset = t * 5;
                result[offset] = selected;
                for (int corner = 0; corner < 3; corner++)
                    result[offset + corner + 1] = Orders[order][corner];
                result[offset + 4] = Math.Sqrt(maximum);
            }
            return result;
        }
    }
}
'@
}

function Get-ClothingCitizenTriangleMatches {
    param([Parameter(Mandatory)]$SourceTriangles, [Parameter(Mandatory)]$TargetTriangles)
    $arrays = @()
    foreach ($triangles in @($SourceTriangles, $TargetTriangles)) {
        $positions = [Collections.Generic.List[double]]::new()
        foreach ($triangle in $triangles) {
            if ($triangle.positions.Count -ne 3 -or $triangle.uv.Count -ne 6) {
                throw 'Calibration requires three physical positions and six UV coordinates per triangle.'
            }
            foreach ($position in $triangle.positions) {
                if ($position.Count -ne 3) { throw 'Invalid calibration physical position.' }
                foreach ($value in $position) {
                    if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw 'Non-finite calibration position.' }
                    $positions.Add($value)
                }
            }
            foreach ($value in $triangle.uv) {
                if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1) {
                    throw 'Calibration UV coordinates must be finite and normalized.'
                }
            }
        }
        $arrays += ,$positions.ToArray()
    }
    $matches = [ZombieSim.Clothing.CitizenCalibration]::Match($arrays[0], $arrays[1])
    for ($index = 0; $index -lt $TargetTriangles.Count; $index++) {
        $offset = $index * 5
        $source = $SourceTriangles[[int]$matches[$offset]]
        $uv = @()
        for ($corner = 1; $corner -le 3; $corner++) {
            $vertex = [int]$matches[$offset + $corner]
            $uv += $source.uv[2 * $vertex], $source.uv[2 * $vertex + 1]
        }
        [pscustomobject]@{
            target = $TargetTriangles[$index].uv
            source = $uv
            maximumPositionError = $matches[$offset + 4]
        }
    }
}

function Get-ClothingCitizenAtlasTransform {
    param([Parameter(Mandatory)]$Mappings, [Parameter(Mandatory)][double[]]$Bounds)
    if ($Bounds.Count -ne 4) { throw 'Atlas calibration requires a source UV rectangle.' }
    $sourceU = [Collections.Generic.List[double]]::new()
    $sourceV = [Collections.Generic.List[double]]::new()
    $targetU = [Collections.Generic.List[double]]::new()
    $targetV = [Collections.Generic.List[double]]::new()
    foreach ($mapping in $Mappings) {
        if ($mapping.maximumPositionError -gt 0.25) { continue }
        $u = ($mapping.source[0] + $mapping.source[2] + $mapping.source[4]) / 3
        $v = ($mapping.source[1] + $mapping.source[3] + $mapping.source[5]) / 3
        if ($u -lt $Bounds[0] -or $u -ge $Bounds[2] -or $v -lt $Bounds[1] -or $v -ge $Bounds[3]) { continue }
        for ($corner = 0; $corner -lt 3; $corner++) {
            $sourceU.Add($mapping.source[2 * $corner])
            $sourceV.Add($mapping.source[2 * $corner + 1])
            $targetU.Add($mapping.target[2 * $corner])
            $targetV.Add($mapping.target[2 * $corner + 1])
        }
    }
    $uFit = [ZombieSim.Clothing.CitizenCalibration]::FitAxis($sourceU.ToArray(), $targetU.ToArray())
    $vFit = [ZombieSim.Clothing.CitizenCalibration]::FitAxis($sourceV.ToArray(), $targetV.ToArray())
    [pscustomobject]@{
        bounds = $Bounds; u = @($uFit[0], $uFit[1]); v = @($vFit[0], $vFit[1])
        samples = $sourceU.Count; uInliers = $uFit[2]; vInliers = $vFit[2]
        maximumInlierPixelError = [math]::Max($uFit[3], $vFit[3])
    }
}

Export-ModuleMember -Function Get-ClothingCitizenTriangleMatches, Get-ClothingCitizenAtlasTransform
