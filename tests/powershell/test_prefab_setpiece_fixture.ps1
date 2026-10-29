param([string]$BspPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
$output = Join-Path ([IO.Path]::GetTempPath()) ('zm-prefab-setpieces-' + [guid]::NewGuid().ToString('N'))
$passed = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}
try {
    & (Join-Path $bin 'build_prefab_setpiece_fixture.ps1') -OutputDirectory $output | Out-Null
    Import-Module (Join-Path $bin 'skybox_models.psm1') -Force
    $vmf = Get-Content -LiteralPath (Join-Path $output 'src\zn_dev_prefab_anchor.vmf') -Raw
    $nodes = [ZombieSim.Skybox.KeyValuesParser]::Parse($vmf).Children
    $anchors = @($nodes | Where-Object { $_.Get('classname') -eq 'zn_prefab_anchor' })
    $roads = @($nodes | Where-Object { $_.Get('classname') -eq 'prop_dynamic_override' })
    Assert-Fixture ($anchors.Count -eq 2 -and $roads.Count -eq 2) 'Fixture must have exactly two independent road stations.'
    $roadblock = @($anchors | Where-Object { $_.Get('targetname') -eq 'test_roadblock' })[0]
    $gate = @($anchors | Where-Object { $_.Get('targetname') -eq 'test_transition_gate' })[0]
    Assert-Fixture ($roadblock.Get('origin') -eq '-384 0 40' -and $roadblock.Get('angles') -eq '0 0 0' -and
        $roadblock.Get('prefab_tags') -eq 'roadBlockade') 'Roadblock must align to the north-south road.'
    Assert-Fixture ($gate.Get('origin') -eq '384 0 40' -and $gate.Get('angles') -eq '0 0 0' -and
        $gate.Get('prefab_tags') -eq 'transitionGate, road') 'Gate placeholder must align to the north-south road.'
    Assert-Fixture (@($nodes | Where-Object { $_.Get('classname') -eq 'trigger_multiple' }).Count -eq 0) 'Visual fixture must not imply travel access.'
    if ($BspPath) {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $BspPath).Path)
        Assert-Fixture ($bytes.Length -ge 24 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'VBSP') 'Invalid compiled set-piece BSP.'
        $offset = [BitConverter]::ToInt32($bytes, 8)
        $length = [BitConverter]::ToInt32($bytes, 12)
        Assert-Fixture ($offset -ge 0 -and $length -gt 0 -and [long]$offset + $length -le $bytes.Length) 'Invalid compiled entity lump.'
        $compiled = [ZombieSim.Skybox.KeyValuesParser]::Parse(
            [Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)
        ).Children
        $compiledAnchors = @($compiled | Where-Object { $_.Get('classname') -eq 'zn_prefab_anchor' })
        $compiledRoads = @($compiled | Where-Object { $_.Get('classname') -eq 'prop_dynamic_override' })
        Assert-Fixture ($compiledAnchors.Count -eq 2 -and $compiledRoads.Count -eq 2) 'Compiled fixture lost an anchor or road reference.'
        foreach ($expected in $anchors) {
            $matches = @($compiledAnchors | Where-Object {
                $_.Get('targetname') -eq $expected.Get('targetname') -and $_.Get('origin') -eq $expected.Get('origin') -and
                    $_.Get('angles') -eq $expected.Get('angles') -and $_.Get('prefab_tags') -eq $expected.Get('prefab_tags')
            })
            Assert-Fixture ($matches.Count -eq 1) "Compiled anchor mismatch: $($expected.Get('targetname'))."
        }
        Assert-Fixture (@($compiled | Where-Object { $_.Get('classname') -eq 'trigger_multiple' }).Count -eq 0) 'Compiled visual fixture unexpectedly contains a travel trigger.'
    }
    $prefabs = Join-Path $output 'prefabs'
    $roadDoc = Get-Content -LiteralPath (Join-Path $prefabs 'zz_dev_roadblock.json') -Raw | ConvertFrom-Json
    $gateDoc = Get-Content -LiteralPath (Join-Path $prefabs 'zz_dev_transition_gate.json') -Raw | ConvertFrom-Json
    Assert-Fixture (@($roadDoc.props).Count -eq 3 -and $roadDoc.props[0].position.x -eq -104 -and
        $roadDoc.props[2].position.x -eq 104) 'Roadblock test props must lie across the road.'
    Assert-Fixture (@($gateDoc.props).Count -eq 2 -and $gateDoc.props[0].position.x -eq -160 -and
        $gateDoc.props[1].position.x -eq 160) 'Gate test props must leave the centre open.'
    $exports = Join-Path $output 'exports'
    foreach ($id in @('zz_dev_roadblock', 'zz_dev_transition_gate')) {
        & (Join-Path $bin 'export_prefab.ps1') -Id $id -SourceDirectory $prefabs -OutputDirectory $exports -Apply | Out-Null
        Assert-Fixture ((Get-FileHash (Join-Path $prefabs "$id.json")).Hash -eq (Get-FileHash (Join-Path $exports "$id.json")).Hash) "Fixture $id must validate and export unchanged."
    }
    $rejected = $false
    try { & (Join-Path $bin 'build_prefab_setpiece_fixture.ps1') -OutputDirectory $output | Out-Null } catch { $rejected = $true }
    Assert-Fixture $rejected 'Existing fixture output must not be overwritten.'
    Write-Output "Prefab set-piece fixtures: $passed assertions passed."
} finally {
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
}
