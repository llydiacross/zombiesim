param([switch]$Compiled)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'generated\signs_preview\zoo'
$vmf = Get-Content -LiteralPath (Join-Path $output 'zn_dev_sign_zoo.vmf') -Raw
$catalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\zombiesim_signs_preview.json') -Raw | ConvertFrom-Json
$cases = [System.Collections.Generic.List[object]]::new()
function Assert-Zoo([string]$Name, [bool]$Passed) {
    $cases.Add([pscustomobject]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Sign zoo regression failed: $Name" }
    Write-Host "PASS: $Name"
}
try {
    $ids = @([regex]::Matches($vmf, '"id"\s+"(\d+)"') | ForEach-Object { $_.Groups[1].Value })
    Assert-Zoo 'all VMF object ids are unique' (($ids | Select-Object -Unique).Count -eq $ids.Count)
    Assert-Zoo 'showroom has seven six-sided solid brushes' (
        [regex]::Matches($vmf, '(?m)^solid\s*$').Count -eq 7 -and [regex]::Matches($vmf, '(?m)^    side\s*$').Count -eq 42)
    $blocks = @([regex]::Matches($vmf, '(?ms)^entity\s*\{([^{}]*)\}') | ForEach-Object { $_.Value })
    $props = @($blocks | Where-Object { $_ -match '"classname" "prop_static"' })
    Assert-Zoo 'all six signs are direct static props, not nested instances' ($props.Count -eq 6 -and $vmf -notmatch 'func_instance')
    $expected = [ordered]@{
        freestanding = '0 0 0'; panel = '0 0 0'; illuminated = '0 0 0'
        wall = '0 180 0'; print = '0 180 0'; poster = '0 180 0'
    }
    foreach ($variant in $expected.Keys) {
        $model = [string]$catalog.variants.$variant.model
        $prop = @($props | Where-Object { $_.Contains(('"model" "{0}"' -f $model)) })
        Assert-Zoo "$variant is present exactly once with correct cardinal facing" (
            $prop.Count -eq 1 -and $prop[0].Contains(('"angles" "{0}"' -f $expected[$variant])))
        $solid = if ($variant -eq 'poster') { 0 } else { 6 }
        Assert-Zoo "$variant retains intended static collision mode" ($prop[0].Contains(('"solid" "{0}"' -f $solid)))
        if ($catalog.variants.$variant.wallMounted) {
            Assert-Zoo "$variant back plane is half a unit in front of the south wall" ($prop[0].Contains('"origin"') -and $prop[0] -match '"origin" "[-0-9.]+ -607.5 192"')
        }
    }
    $lamp = @($blocks | Where-Object { $_ -match '"classname" "light_spot"' })
    Assert-Zoo 'lamp prefab retains translated light position and negative-down baked pitch' (
        $lamp.Count -eq 1 -and $lamp[0].Contains('"origin" "640 200 298"') -and
        $lamp[0].Contains('"angles" "-60 90 0"') -and $lamp[0].Contains('"pitch" "-60"'))
    Assert-Zoo 'spawn faces the large sign row from the central aisle' (
        @($blocks | Where-Object { $_ -match '"classname" "info_player_start"' -and
            $_.Contains('"origin" "0 -192 16"') -and $_.Contains('"angles" "0 90 0"') }).Count -eq 1)
    $staging = Get-Content -LiteralPath (Join-Path $root 'generated\signs_preview\staging-report.json') -Raw | ConvertFrom-Json
    Assert-Zoo 'staging includes model and original material files' ($staging.files.Count -ge 31)
    foreach ($file in $staging.files) {
        $source = Join-Path $root "content\$($file.path)"
        $destination = Join-Path $staging.gameDirectory $file.path
        Assert-Zoo "root-mounted $($file.path) matches packaged asset" (
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -eq $file.sha256 -and
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $file.sha256)
    }
    if ($Compiled) {
        $report = Get-Content -LiteralPath (Join-Path $output 'compile-report.json') -Raw | ConvertFrom-Json
        Assert-Zoo 'all compile stages passed within visibility budget' (
            $report.status -eq 'passed' -and $report.portalClusters -le 256 -and $report.portals -le 512)
        Assert-Zoo 'compiled zoo uses final static-prop lighting preset' ($report.lightingPreset -eq 'final')
        $lightingLog = Get-Content -LiteralPath (Join-Path $output 'zn_dev_sign_zoo.vrad.log') -Raw
        Assert-Zoo 'compiler retained all six static sign props' ($lightingLog -match 'static prop count\s+6/16384')
        Assert-Zoo 'compiler retained spotlight and three showroom lights' ($lightingLog -match 'LDR worldlights\s+4/8192')
        $bsp = Join-Path $output 'zn_dev_sign_zoo.bsp'
        $bytes = [System.IO.File]::ReadAllBytes($bsp)
        Assert-Zoo 'compiled zoo is a Source BSP' ([System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'VBSP')
        Assert-Zoo 'root-staged zoo matches compiled BSP' (
            (Get-FileHash -LiteralPath $bsp).Hash -eq
            (Get-FileHash -LiteralPath (Join-Path $staging.gameDirectory 'maps\zn_dev_sign_zoo.bsp')).Hash)
    }
} finally {
    [pscustomobject]@{ cases = $cases.ToArray(); passed = @($cases | Where-Object passed).Count } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'test-report.json') -Encoding UTF8
}
Write-Host "Sign zoo regressions passed: $($cases.Count)/$($cases.Count)."
