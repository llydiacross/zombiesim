Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'generated\clothing_preview'
$baselinePath = Join-Path $output 'model-inspection.json'
if (-not (Test-Path -LiteralPath $baselinePath)) {
    throw 'Run test_clothing_model_inspection.ps1 before the walker comparison.'
}
$baselineHash = (Get-FileHash -LiteralPath $baselinePath).Hash
$guideNames = @('male_03', 'female_01')
$survivorGuideHashes = @{}
foreach ($name in $guideNames) {
    $survivorGuideHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $output "uv_$name.png")).Hash
}
& (Join-Path $PSScriptRoot 'inspect_clothing_models.ps1') -ModelGroups group03 `
    -UvGuideModels @('models/player/group03/male_03.mdl', 'models/player/group03/female_01.mdl')
$survivors = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$walkers = Get-Content -LiteralPath (Join-Path $output 'model-inspection-group03.json') -Raw | ConvertFrom-Json
$passed = 0
function Assert-WalkerInspection([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Walker inspection regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
Assert-WalkerInspection 'group03 metadata contains all fifteen mounted player models' (
    $walkers.models.Count -eq 15 -and @($walkers.models.model | Select-Object -Unique).Count -eq 15)
foreach ($walker in $walkers.models) {
    $name = Split-Path $walker.model -Leaf
    $survivor = @($survivors.models | Where-Object { (Split-Path $_.model -Leaf) -eq $name })
    $body = @($walker.materials | Where-Object name -eq players_sheet)
    $meshes = @($walker.bodygroups.submodels.meshes | Where-Object material -like '*/players_sheet')
    Assert-WalkerInspection "$name has a distinct 2048-square group03 body material" (
        $body.Count -eq 1 -and $body[0].path -imatch '/group03/players_sheet$' -and
        $body[0].width -eq 2048 -and $body[0].height -eq 2048)
    Assert-WalkerInspection "$name retains valid mounted body mesh metadata without survivor-mask approval" (
        $meshes.Count -gt 0 -and @($meshes | Where-Object { $_.vertices -le 0 -or $_.uvSequenceSha256 -notmatch '^[A-F0-9]{64}$' -or
            ($null -ne $_.uvGuide -and $_.uvGuide.garmentMasksVerified) }).Count -eq 0)
    $original = @($survivor[0].bodygroups.submodels.meshes | Where-Object material -like '*/players_sheet')
    Assert-WalkerInspection "$name cannot inherit the survivor UV fingerprint" (
        $survivor.Count -eq 1 -and ($original.uvSequenceSha256 -join ',') -ne ($meshes.uvSequenceSha256 -join ','))
}
foreach ($name in $guideNames) {
    $path = Join-Path $output "uv_group03_$name.png"
    $image = [Drawing.Bitmap]::new($path)
    try {
        Assert-WalkerInspection "$name uses an independently named2048chart" ($image.Width -eq 2048 -and $image.Height -eq 2048)
    } finally { $image.Dispose() }
    $triangles = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($path, '.bodytriangles.json')) -Raw | ConvertFrom-Json
    Assert-WalkerInspection "$name full-body calibration retains model/size and no mask approval" (
        $triangles.schemaVersion -eq 1 -and $triangles.model -eq "models/player/group03/$name.mdl" -and
        $triangles.size -eq 2048 -and -not $triangles.garmentMasksVerified -and $triangles.triangles.Count -gt 1000)
    $valid = $true
    foreach ($triangle in $triangles.triangles) {
        if ($triangle.positions.Count -ne 3 -or $triangle.uv.Count -ne 6 -or $triangle.center.Count -ne 3) { $valid = $false; break }
        foreach ($uv in $triangle.uv) {
            if ([double]::IsNaN($uv) -or [double]::IsInfinity($uv) -or $uv -lt 0 -or $uv -gt 2047) { $valid = $false }
        }
        foreach ($position in $triangle.positions) {
            if ($position.Count -ne 3) { $valid = $false; break }
            foreach ($value in $position) {
                if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { $valid = $false }
            }
        }
    }
    Assert-WalkerInspection "$name allbodytriangles retain finite physical and bounded actualUV vertices" $valid
    Assert-WalkerInspection "$name calibration does not overwrite survivorUVchart" (
        (Get-FileHash -LiteralPath (Join-Path $output "uv_$name.png")).Hash -eq $survivorGuideHashes[$name])
}
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'inspect_clothing_models.ps1') -ModelGroups group03 -UvGuideModels 'models/player/group01/male_03.mdl'
} catch {
    if ($_.Exception.Message -notlike 'UV guide model is not in a supported selected model group*') { throw }
    $rejected = $true
}
Assert-WalkerInspection 'wrong-group UV requests fail before writing calibration outputs' $rejected
Assert-WalkerInspection 'walker inspection leaves the default survivor report untouched' (
    (Get-FileHash -LiteralPath $baselinePath).Hash -eq $baselineHash)
Write-Host "Clothing walker inspection checks passed: $passed/$passed."
