param([switch]$StagePreview, [switch]$EnableRuntime)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$inputRoot = Join-Path $root 'generated\clothing_preview\citizen_calibration'
$models = [ordered]@{}
foreach ($sex in 'male', 'female') {
    $count = if ($sex -eq 'male') { 9 } else { 6 }
    for ($number = 1; $number -le $count; $number++) {
        $name = '{0}_{1:D2}' -f $sex, $number
        $inspection = Get-Content -LiteralPath (Join-Path $inputRoot "$name.json") -Raw | ConvertFrom-Json
        $path = "models/player/group01/$name.mdl"
        if ($inspection.schemaVersion -ne 1 -or $inspection.model -ne $path -or
            $inspection.atlas.Count -ne 3 -or $inspection.triangles.Count -lt 1000) {
            throw "Invalid independent citizen calibration: $name"
        }
        $polygons = @{ shirt = @(); pants = @() }
        $excluded = 0
        foreach ($triangle in $inspection.triangles) {
            $u = ($triangle.source[0] + $triangle.source[2] + $triangle.source[4]) / 3
            $v = ($triangle.source[1] + $triangle.source[3] + $triangle.source[5]) / 3
            $regions = @($inspection.atlas | Where-Object {
                $u -ge $_.bounds[0] -and $u -lt $_.bounds[2] -and
                $v -ge $_.bounds[1] -and $v -lt $_.bounds[3]
            })
            if ($regions.Count -eq 0) { continue }
            if ($regions.Count -ne 1) { throw "Ambiguous citizen garment chart: $name" }
            $region = $regions[0]
            if ($region.uInliers / $region.samples -lt 0.94 -or $region.vInliers / $region.samples -lt 0.94 -or
                $region.maximumInlierPixelError -gt 0.75) {
                throw "Insufficient upright atlas calibration: $name/$($region.id)"
            }
            $vertices = @()
            $residual = 0.0
            for ($corner = 0; $corner -lt 3; $corner++) {
                $targetU, $targetV = $triangle.target[2 * $corner], $triangle.target[2 * $corner + 1]
                $sourceU = ($targetU - $region.u[1]) / $region.u[0]
                $sourceV = ($targetV - $region.v[1]) / $region.v[0]
                $residual = [math]::Max($residual, [math]::Abs($sourceU - $triangle.source[2 * $corner]) * 1024)
                $residual = [math]::Max($residual, [math]::Abs($sourceV - $triangle.source[2 * $corner + 1]) * 1024)
                $vertices += ,@($targetU, $targetV, $sourceU, $sourceV)
            }
            # Different neckline/skin charts are retained natively, never guessed into the garment.
            if ($residual -gt 2 -or @($vertices | Where-Object { $_[2] -lt 0 -or $_[2] -gt 1 -or $_[3] -lt 0 -or $_[3] -gt 1 }).Count) {
                $excluded++
                continue
            }
            $garment = if ($region.id -eq 'pants') { 'pants' } else { 'shirt' }
            $polygons[$garment] += ,$vertices
        }
        if ($polygons.shirt.Count -lt 800 -or $polygons.pants.Count -lt 400) {
            throw "Incomplete citizen garment coverage: $name"
        }
        $models[$path] = @{ sex = $sex; shirt = $polygons.shirt; pants = $polygons.pants; nativeTrianglesExcluded = $excluded }
        Write-Host "$name : $($polygons.shirt.Count) shirt/$($polygons.pants.Count) pants triangles; $excluded nonmatching neckline/chart triangles remain native."
    }
}
$data = @{ schemaVersion = 1; previewOnly = -not $EnableRuntime; size = 1024; models = $models }
$output = Join-Path $inputRoot 'clothing_citizen_calibration.json'
$data | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $output -Encoding UTF8
if ($StagePreview) {
    $destination = Join-Path $root 'content\data_static\clothing_citizen_calibration.json'
    Copy-Item -LiteralPath $output -Destination $destination -Force
    if ((Get-FileHash $output).Hash -ne (Get-FileHash $destination).Hash) { throw 'Citizen calibration staging mismatch.' }
}
$gate = if ($EnableRuntime) { 'human-approved runtime enabled' } else { 'preview validation only' }
Write-Host "Built fifteen citizen-only transfer charts; $gate, no new catalogue textures or rebel support."
