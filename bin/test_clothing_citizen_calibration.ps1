Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_citizen_calibration.psm1')
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'generated\clothing_preview\citizen_calibration\clothing_citizen_calibration.json'
$data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$passed = 0
function Assert-CitizenCalibration([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Citizen calibration regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
$triangle = [pscustomobject]@{ positions = @(@(0, 0, 0), @(1, 0, 0), @(0, 1, 0)); uv = @(0, 0, 1, 0, 0, 1) }
$rotated = [pscustomobject]@{ positions = @(@(0, 1, 0), @(0, 0, 0), @(1, 0, 0)); uv = @(0, 1, 0, 0, 1, 0) }
$matches = @(Get-ClothingCitizenTriangleMatches @($triangle) @($rotated))
Assert-CitizenCalibration 'physical matching preserves corner UV identity despite triangle permutation' (
    $matches.Count -eq 1 -and $matches[0].maximumPositionError -eq 0 -and
    ($matches[0].source -join ',') -eq ($rotated.uv -join ','))
$fit = [ZombieSim.Clothing.CitizenCalibration]::FitAxis(
    [double[]]@(0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7),
    [double[]]@(0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.1))
Assert-CitizenCalibration 'upright fit excludes unrelated native chart instead of skewing artwork' (
    [math]::Abs($fit[0] - 1) -lt 1e-8 -and [math]::Abs($fit[1] - 0.2) -lt 1e-8 -and $fit[2] -eq 7)
$invalid = [pscustomobject]@{ positions = $triangle.positions; uv = @(0, 0, [double]::NaN, 0, 0, 1) }
$rejected = $false
try { $null = Get-ClothingCitizenTriangleMatches @($triangle) @($invalid) }
catch { if ($_.Exception.Message -notlike 'Calibration UV coordinates*') { throw }; $rejected = $true }
Assert-CitizenCalibration 'non-finite UV samples fail explicitly' $rejected
Assert-CitizenCalibration 'fifteen calibrated models retain an explicit rollout gate' (
    $data.schemaVersion -eq 1 -and $data.size -eq 1024 -and $data.previewOnly -is [bool] -and @($data.models.PSObject.Properties).Count -eq 15)
foreach ($sex in 'male', 'female') {
    $count = if ($sex -eq 'male') { 9 } else { 6 }
    for ($number = 1; $number -le $count; $number++) {
        $name = '{0}_{1:D2}' -f $sex, $number
        $modelPath = "models/player/group01/$name.mdl"
        $model = $data.models.$modelPath
        Assert-CitizenCalibration "$name keeps its actual family and no rebel replacement" ($model.sex -eq $sex)
        foreach ($garment in 'shirt', 'pants') {
            $polygons = $model.$garment
            Assert-CitizenCalibration "$name/$garment has bounded populated triangle coverage" (
                $polygons.Count -ge $(if ($garment -eq 'shirt') { 800 } else { 400 }) -and $polygons.Count -le 2000)
            $valid = $true
            foreach ($polygon in $polygons) {
                if ($polygon.Count -ne 3) { $valid = $false; break }
                foreach ($vertex in $polygon) {
                    if ($vertex.Count -ne 4) { $valid = $false; break }
                    foreach ($value in $vertex) {
                        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1) {
                            $valid = $false
                        }
                    }
                }
            }
            Assert-CitizenCalibration "$name/$garment target and source samples remain finite and normalized" $valid
        }
    }
}
Assert-CitizenCalibration 'rebel and refugee models never enter the calibration manifest' (
    @($data.models.PSObject.Properties.Name | Where-Object { $_ -notlike 'models/player/group01/*' }).Count -eq 0)
Write-Host "Citizen calibration checks: $passed/$passed passed."
