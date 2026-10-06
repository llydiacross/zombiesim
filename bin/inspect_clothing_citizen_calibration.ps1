param([string]$EngineReport = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_citizen_calibration.psm1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $EngineReport) {
    $EngineReport = Join-Path $root '..\..\data\zombiesim\clothing_mesh_inspection.json'
}
$report = Get-Content -LiteralPath $EngineReport -Raw | ConvertFrom-Json
if ($report.schemaVersion -ne 1 -or $report.models.Count -ne 15 -or
    @($report.models.model | Select-Object -Unique).Count -ne 15) {
    throw 'Calibration requires a complete fifteen-citizen engine inspection.'
}
$output = Join-Path $root 'generated\clothing_preview\citizen_calibration'
$null = New-Item -ItemType Directory -Force -Path $output
foreach ($model in $report.models) {
    if ($model.model -notmatch '^models/player/group01/(male|female)_\d{2}\.mdl$' -or $model.bodies.Count -ne 1) {
        throw 'Calibration only accepts single-body group01 citizen meshes, never rebels.'
    }
    $sex = $Matches[1]
    $canonical = 'models/player/group01/' + $(if ($sex -eq 'male') { 'male_03' } else { 'female_01' }) + '.mdl'
    $reference = @($report.models | Where-Object model -eq $canonical)
    if ($reference.Count -ne 1) { throw "Missing canonical citizen mesh: $canonical" }
    $mappings = @(Get-ClothingCitizenTriangleMatches $reference[0].bodies[0].triangles $model.bodies[0].triangles)
    $name = [IO.Path]::GetFileNameWithoutExtension($model.model)
    $summary = [pscustomobject]@{
        schemaVersion = 1; model = $model.model; reference = $canonical
        engineCapturedAt = $report.capturedAt; garmentMasksVerified = $false
        maximumPositionError = ($mappings | Measure-Object maximumPositionError -Maximum).Maximum
        withinQuarterUnit = @($mappings | Where-Object maximumPositionError -le 0.25).Count
        atlas = @(
            foreach ($region in @(
                @{ id = 'torso'; bounds = @(0, (584 / 1024), (496 / 1024), 1) },
                @{ id = 'sleeves'; bounds = @((496 / 1024), (584 / 1024), (840 / 1024), 1) },
                @{ id = 'pants'; bounds = @((496 / 1024), 0, 1, (464 / 1024)) }
            )) {
                $transform = Get-ClothingCitizenAtlasTransform $mappings $region.bounds
                $transform | Add-Member -NotePropertyName id -NotePropertyValue $region.id
                $transform
            }
        )
        triangles = $mappings
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output "$name.json") -Encoding UTF8
    Write-Host "$name : $($summary.withinQuarterUnit)/$($mappings.Count) physical triangles within0.25units; maximum $($summary.maximumPositionError). Diagnostic only, not enabled support."
    foreach ($atlas in $summary.atlas) {
        Write-Host "  $($atlas.id): U $($atlas.u -join ','); V $($atlas.v -join ','); inliers $($atlas.uInliers)/$($atlas.vInliers) of $($atlas.samples), error $($atlas.maximumInlierPixelError)px"
    }
}
