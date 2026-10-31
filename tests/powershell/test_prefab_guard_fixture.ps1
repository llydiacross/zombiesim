param([string]$BspPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
$output = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('zm-prefab-guard-' + [guid]::NewGuid().ToString('N'))))
$passed = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}
function Check-Entities([object[]]$Nodes, [string]$Label) {
    $guards = @($Nodes | Where-Object { $_.Get('classname') -eq 'zn_prefab_guard' })
    Assert-Fixture ($guards.Count -eq 2) "$Label must contain exactly two directly placed guards."
    $default = @($guards | Where-Object { $_.Get('targetname') -eq 'hammer_default_guard' })
    $custom = @($guards | Where-Object { $_.Get('targetname') -eq 'hammer_override_guard' })
    Assert-Fixture ($default.Count -eq 1 -and $custom.Count -eq 1) "$Label guard names must be distinct."
    Assert-Fixture ($default[0].Get('origin') -eq '-200 0 0' -and $default[0].Get('angles') -eq '0 270 0') "$Label default guard transform changed."
    Assert-Fixture ($custom[0].Get('origin') -eq '200 0 0' -and $custom[0].Get('angles') -eq '0 270 0') "$Label customized guard transform changed."
    foreach ($entry in @{
        guard_name = 'Hammer fixture'; model = 'models/player/group01/male_03.mdl'; idle = 'idle_all_01'
        weapon = 'smg'; range = '1200'; shirt = 'catalogue_fabric_shirt_blue_plain'
        pants = 'catalogue_fabric_pants_black_plain'; damage = '25'; fire_interval = '0.075'; spread = '0.04'
    }.GetEnumerator()) {
        Assert-Fixture ($custom[0].Get($entry.Key) -ceq $entry.Value) "$Label lost guard key $($entry.Key)."
    }
    Assert-Fixture (@($Nodes | Where-Object { $_.Get('classname') -eq 'zn_prefab_anchor' }).Count -eq 0) "$Label must not depend on a prefab anchor."
}
try {
    & (Join-Path $bin 'build_prefab_guard_fixture.ps1') -OutputDirectory $output | Out-Null
    Import-Module (Join-Path $bin 'skybox_models.psm1') -Force
    $vmf = Get-Content -LiteralPath (Join-Path $output 'src\zn_dev_prefab_anchor.vmf') -Raw
    $nodes = [ZombieSim.Skybox.KeyValuesParser]::Parse($vmf).Children
    Check-Entities $nodes 'Source'
    if ($BspPath) {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $BspPath).Path)
        Assert-Fixture ($bytes.Length -ge 24 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'VBSP') 'Invalid compiled guard fixture BSP.'
        $offset = [BitConverter]::ToInt32($bytes, 8)
        $length = [BitConverter]::ToInt32($bytes, 12)
        Assert-Fixture ($offset -ge 0 -and $length -gt 0 -and [long]$offset + $length -le $bytes.Length) 'Invalid compiled entity lump.'
        $compiled = [ZombieSim.Skybox.KeyValuesParser]::Parse(
            [Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)
        ).Children
        Check-Entities $compiled 'Compiled fixture'
    }
    $rejected = $false
    try { & (Join-Path $bin 'build_prefab_guard_fixture.ps1') -OutputDirectory $output | Out-Null } catch { $rejected = $true }
    Assert-Fixture $rejected 'Existing fixture output must not be overwritten.'
    Write-Output "Prefab guard Hammer fixture: $passed assertions passed."
} finally {
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
}
