param([string]$BspPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
$output = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('zm-guard-anchor-' + [guid]::NewGuid().ToString('N'))))
$passed = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}
function Check-Entities([object[]]$Nodes, [string]$Label) {
    $anchors = @($Nodes | Where-Object { $_.Get('classname') -eq 'zn_prefab_anchor' })
    Assert-Fixture ($anchors.Count -eq 4) "$Label must contain four prefab anchors."
    foreach ($expected in @(
        @{ yaw = 0; origin = '-400 200 0' }, @{ yaw = 90; origin = '400 200 0' },
        @{ yaw = 180; origin = '-400 -200 0' }, @{ yaw = 270; origin = '400 -200 0' }
    )) {
        $match = @($anchors | Where-Object { $_.Get('targetname') -eq "guard_anchor_$($expected.yaw)" })
        Assert-Fixture ($match.Count -eq 1 -and $match[0].Get('origin') -eq $expected.origin -and
            $match[0].Get('angles') -eq "0 $($expected.yaw) 0" -and $match[0].Get('prefab_tags') -eq 'guardFixture') `
            "$Label must preserve the $($expected.yaw)-degree anchor."
    }
    Assert-Fixture (@($Nodes | Where-Object { $_.Get('classname') -eq 'zn_prefab_guard' }).Count -eq 0) `
        "$Label guards must come from the prefab, not directly from the map."
}
try {
    & (Join-Path $bin 'build_prefab_guard_anchor_fixture.ps1') -OutputDirectory $output | Out-Null
    Import-Module (Join-Path $bin 'skybox_models.psm1') -Force
    $vmf = Get-Content -LiteralPath (Join-Path $output 'src\zn_dev_prefab_anchor.vmf') -Raw
    Check-Entities ([ZombieSim.Skybox.KeyValuesParser]::Parse($vmf).Children) 'Source'
    if ($BspPath) {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $BspPath).Path)
        Assert-Fixture ($bytes.Length -ge 24 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'VBSP') 'Invalid compiled guard-anchor BSP.'
        $offset = [BitConverter]::ToInt32($bytes, 8)
        $length = [BitConverter]::ToInt32($bytes, 12)
        Assert-Fixture ($offset -ge 0 -and $length -gt 0 -and [long]$offset + $length -le $bytes.Length) 'Invalid compiled entity lump.'
        $compiled = [ZombieSim.Skybox.KeyValuesParser]::Parse(
            [Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)
        ).Children
        Check-Entities $compiled 'Compiled fixture'
    }
    $rejected = $false
    try { & (Join-Path $bin 'build_prefab_guard_anchor_fixture.ps1') -OutputDirectory $output | Out-Null } catch { $rejected = $true }
    Assert-Fixture $rejected 'Existing fixture output must not be overwritten.'
    Write-Output "Prefab guard-anchor fixture: $passed assertions passed."
} finally {
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
}
