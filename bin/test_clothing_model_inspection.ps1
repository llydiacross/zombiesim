Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$guideModels = @('models/player/group01/male_03.mdl', 'models/player/group01/female_01.mdl')
& (Join-Path $PSScriptRoot 'inspect_clothing_models.ps1') -UvGuideModels $guideModels
if (-not $?) { throw 'Mounted clothing model inspection failed.' }
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'generated\clothing_preview'
$report = Get-Content -LiteralPath (Join-Path $output 'model-inspection.json') -Raw | ConvertFrom-Json
$cases = [System.Collections.Generic.List[object]]::new()
function Assert-ClothingInspection([string]$Name, [bool]$Passed) {
    $cases.Add([pscustomobject]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Clothing model inspection regression failed: $Name" }
    Write-Host "PASS: $Name"
}
try {
    Assert-ClothingInspection 'exactly fifteen unique allowlisted citizen models inspected' (
        $report.models.Count -eq 15 -and @($report.models.model | Select-Object -Unique).Count -eq 15)
    foreach ($sex in 'male', 'female') {
        $count = if ($sex -eq 'male') { 9 } else { 6 }
        for ($number = 1; $number -le $count; $number++) {
            $path = 'models/player/group01/{0}_{1:D2}.mdl' -f $sex, $number
            $matches = @($report.models | Where-Object model -EQ $path)
            Assert-ClothingInspection "$path has one complete installed-model record" ($matches.Count -eq 1)
            $model = $matches[0]
            Assert-ClothingInspection "$path retains verified version and one existing skin/bodygroup choice" (
                $model.mdlVersion -eq 48 -and $model.skinCount -eq 1 -and
                $model.bodygroups.Count -eq 1 -and $model.bodygroups[0].choices -eq 1)
            $sheets = @($model.materials | Where-Object name -EQ 'players_sheet')
            Assert-ClothingInspection "$path resolves a single mounted 1024x1024 tintable body sheet" (
                $sheets.Count -eq 1 -and $sheets[0].width -eq 1024 -and $sheets[0].height -eq 1024 -and
                $sheets[0].playerColourProxy -eq $true -and $sheets[0].path -match '(?i)/group01/players_sheet$')
            $meshes = @($model.bodygroups[0].submodels[0].meshes)
            Assert-ClothingInspection "$path mesh vertex counts cover the root VVD without missing geometry" (
                ($meshes | Measure-Object vertices -Sum).Sum -eq $model.vertices)
            $body = @($meshes | Where-Object material -Match '(?i)/players_sheet$')
            Assert-ClothingInspection "$path body UV bounds/hash are finite and refer to the resolved material" (
                $body.Count -eq 1 -and $body[0].vertices -gt 0 -and
                $body[0].uvSequenceSha256 -match '^[0-9A-F]{64}$' -and
                $body[0].material -eq $sheets[0].path -and
                $body[0].uvMin[0] -ge 0 -and $body[0].uvMax[0] -le 1 -and
                $body[0].uvMin[1] -ge 0 -and $body[0].uvMax[1] -le 1 -and
                $body[0].uvMin[0] -lt $body[0].uvMax[0] -and $body[0].uvMin[1] -lt $body[0].uvMax[1])
            Assert-ClothingInspection "$path body sheet spans upper and lower body, not a separate garment slot" (
                $body[0].positionMin[2] -lt 20 -and $body[0].positionMax[2] -gt 50)
        }
    }
    $bodyMeshes = @($report.models.bodygroups.submodels.meshes | Where-Object material -Match '(?i)/players_sheet$')
    Assert-ClothingInspection 'material indices vary so a single hard-coded body slot is unsafe' (
        @($bodyMeshes.materialIndex | Sort-Object -Unique).Count -gt 1)
    Add-Type -AssemblyName System.Drawing
    foreach ($path in $guideModels) {
        $model = @($report.models | Where-Object model -EQ $path)[0]
        $body = @($model.bodygroups.submodels.meshes | Where-Object material -Match '(?i)/players_sheet$')[0]
        Assert-ClothingInspection "$path guide uses matching root VTX triangle topology" (
            $body.uvGuide.topologyVersion -eq 7 -and $body.uvGuide.triangles -gt 1000 -and
            $body.uvGuide.triangles -lt 15000 -and $body.uvGuide.garmentMasksVerified -eq $false)
        Assert-ClothingInspection "$path guide remains a generated inspection image, not a packaged model/texture" (
            (Split-Path -Parent $body.uvGuide.path) -eq $output -and
            [System.IO.Path]::GetExtension($body.uvGuide.path) -eq '.png')
        $image = [System.Drawing.Bitmap]::new($body.uvGuide.path)
        try {
            Assert-ClothingInspection "$path guide has a complete 1024-square UV canvas" ($image.Width -eq 1024 -and $image.Height -eq 1024)
            $wirePixels = 0
            for ($y = 0; $y -lt 1024; $y += 4) {
                for ($x = 0; $x -lt 1024; $x += 4) {
                    $pixel = $image.GetPixel($x, $y)
                    if ($pixel.R -gt 120 -and $pixel.G -gt 120 -and $pixel.B -gt 120) { $wirePixels++ }
                }
            }
            Assert-ClothingInspection "$path guide contains visible mesh topology, not just grid labels" ($wirePixels -gt 1000)
        } finally { $image.Dispose() }
        $neckline = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($body.uvGuide.path, '.neckline.json')) -Raw | ConvertFrom-Json
        $sleeves = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($body.uvGuide.path, '.sleeves.json')) -Raw | ConvertFrom-Json
        Assert-ClothingInspection "$path contains populated neckline and sleeve calibration reports" (
            $neckline.Count -gt 10 -and $sleeves.Count -gt 10)
        $valid = $true
        foreach ($triangle in $neckline) {
            if ($triangle.center.Count -ne 3 -or $triangle.uv.Count -ne 6) { $valid = $false }
            foreach ($coordinate in $triangle.uv) {
                if ([double]::IsNaN($coordinate) -or [double]::IsInfinity($coordinate) -or
                    $coordinate -lt 0 -or $coordinate -gt 1023) { $valid = $false }
            }
        }
        foreach ($triangle in $sleeves) {
            if ($triangle.center.Count -ne 3 -or $triangle.uvCenter.Count -ne 2) { $valid = $false }
            foreach ($coordinate in $triangle.uvCenter) {
                if ([double]::IsNaN($coordinate) -or [double]::IsInfinity($coordinate) -or
                    $coordinate -lt 0 -or $coordinate -gt 1023) { $valid = $false }
            }
        }
        Assert-ClothingInspection "$path calibration reports retain valid triangle/centroid UV shapes" $valid
        Assert-ClothingInspection "$path sleeve landmarks cover both anatomical sides" (
            @($sleeves | Where-Object { $_.center[0] -lt -8 }).Count -gt 0 -and
            @($sleeves | Where-Object { $_.center[0] -gt 8 }).Count -gt 0)
        $legs = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($body.uvGuide.path, '.legs.json')) -Raw | ConvertFrom-Json
        $prints = Get-Content -LiteralPath (Join-Path $root 'assets\clothing\prints.json') -Raw | ConvertFrom-Json
        $sex = if ($path -like '*male_03*') { 'male' } else { 'female' }
        Import-Module (Join-Path $PSScriptRoot 'clothing_artwork.psm1')
        foreach ($legStyle in (Get-ClothingLegPresets $prints)) {
        $rectangle = $legStyle.$sex[0].uv
        $covered = @($legs | Where-Object {
            $_.uvCenter[0] -ge $rectangle[0] -and $_.uvCenter[0] -lt $rectangle[0] + $rectangle[2] -and
            $_.uvCenter[1] -ge $rectangle[1] -and $_.uvCenter[1] -lt $rectangle[1] + $rectangle[3]
        })
        Assert-ClothingInspection "$path/$($legStyle.id) covers populated thigh geometry" ($covered.Count -gt 10)
        $direction = if ($legStyle.id -like '*_right') { -1 } else { 1 }
        Assert-ClothingInspection "$path/$($legStyle.id) does not cross to the other anatomical leg" (
            @($covered | Where-Object { $_.center[0] * $direction -le 0 }).Count -eq 0)
        if ($legStyle.id -like 'pants_back_*') {
            Assert-ClothingInspection "$path/$($legStyle.id) covers rear thigh only" (
                @($covered | Where-Object { $_.center[1] -le 1 -or $_.center[2] -lt 22 }).Count -eq 0)
        } elseif ($legStyle.id -like 'pants_cuff*') {
            Assert-ClothingInspection "$path/$($legStyle.id) spans front thigh through the trouser opening" (
                @($covered | Where-Object { $_.center[1] -lt -1 -and $_.center[2] -gt 28 }).Count -gt 0 -and
                @($covered | Where-Object { $_.center[1] -lt -1 -and $_.center[2] -lt 10 }).Count -gt 0)
            $cuff = @($covered | Where-Object { $_.center[1] -lt -1 -and $_.center[2] -lt 10 })
            Assert-ClothingInspection "$path/$($legStyle.id) source down points toward actual lower calf" (
                ($cuff | ForEach-Object { $_.uvCenter[1] } | Measure-Object -Minimum).Minimum -gt $rectangle[1] + 290)
        } else {
        Assert-ClothingInspection "$path/$($legStyle.id) raises artwork to front thigh rather than calf" (
            @($covered | Where-Object { $_.center[1] -lt -1 -and $_.center[2] -gt 28 }).Count -gt 0 -and
            @($covered | Where-Object { $_.center[2] -lt 18 }).Count -eq 0)
        }
        }
        foreach ($rear in (Get-ClothingRearPresets)) {
            $rectangle = $rear.$sex[0].uv
            $landmarks = if ($rear.id -like 'pants_*') { $legs } else { $sleeves }
            $covered = @($landmarks | Where-Object {
                $_.uvCenter[0] -ge $rectangle[0] -and $_.uvCenter[0] -lt $rectangle[0] + $rectangle[2] -and
                $_.uvCenter[1] -ge $rectangle[1] -and $_.uvCenter[1] -lt $rectangle[1] + $rectangle[3]
            })
            $direction = if ($rear.id -like '*_left') { 1 } else { -1 }
            Assert-ClothingInspection "$path/$($rear.id) contains actual rear-facing selected-limb geometry" (
                $covered.Count -ge 6 -and
                @($covered | Where-Object { $_.center[1] -le 1 -or $_.center[0] * $direction -le 0 }).Count -eq 0)
            $ordered = @($covered | Sort-Object { $_.uvCenter[1] })
            Assert-ClothingInspection "$path/$($rear.id) artwork top points physically up the limb" (
                $ordered[0].center[2] -gt $ordered[-1].center[2] + 2)
            Assert-ClothingInspection "$path/$($rear.id) does not stretch artist canvas" (
                $rectangle[2] -eq $rear.size[0] -and $rectangle[3] -eq $rear.size[1])
        }
    }
} finally {
    [pscustomobject]@{ cases = $cases.ToArray(); passed = @($cases | Where-Object passed).Count } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'inspection-test-report.json') -Encoding UTF8
}
Write-Host "Clothing model inspection checks passed: $($cases.Count)/$($cases.Count)."
