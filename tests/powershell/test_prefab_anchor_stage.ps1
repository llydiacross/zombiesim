Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script = Join-Path $root 'bin\stage_prefab_anchor_fixture.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zm-anchor-stage-' + [guid]::NewGuid().ToString('N'))
$content = Join-Path $temporary 'content'
$engine = Join-Path $temporary 'engine'
$bsp = Join-Path $temporary 'fixture.bsp'
$ledger = Join-Path $temporary 'ledger.json'
$passed = 0
function Assert-Stage([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}
function Invoke-Stage([string]$Action) {
    & $script -Action $Action -BspPath $bsp -ContentDirectory $content -EngineMapDirectory $engine -LedgerPath $ledger | Out-Null
}
[IO.Directory]::CreateDirectory($temporary) | Out-Null
try {
    [IO.File]::WriteAllText($bsp, 'isolated fixture BSP')
    Invoke-Stage 'Inspect'
    Assert-Stage (-not (Test-Path -LiteralPath $content) -and -not (Test-Path -LiteralPath $ledger)) 'Inspect must be read-only.'
    $occupied = Join-Path $engine 'zn_dev_prefab_anchor.bsp'
    [IO.Directory]::CreateDirectory($engine) | Out-Null
    [IO.File]::WriteAllText($occupied, 'user file')
    $rejected = $false
    try { Invoke-Stage 'Stage' } catch { $rejected = $true }
    Assert-Stage ($rejected -and [IO.File]::ReadAllText($occupied) -eq 'user file' -and -not (Test-Path -LiteralPath $ledger)) 'Existing files must be protected.'
    Remove-Item -LiteralPath $occupied
    Invoke-Stage 'Stage'
    $map = Join-Path $content 'maps\zn_dev_prefab_anchor.bsp'
    $prefab = Join-Path $content 'data_static\prefabs\zz_dev_anchor_fixture.json'
    Assert-Stage ((Get-FileHash $map).Hash -eq (Get-FileHash $bsp).Hash -and (Get-FileHash $occupied).Hash -eq (Get-FileHash $bsp).Hash) 'Both staged BSPs must match.'
    $doc = Get-Content -LiteralPath $prefab -Raw | ConvertFrom-Json
    Assert-Stage ($doc.id -eq 'zz_dev_anchor_fixture' -and @($doc.props).Count -eq 2 -and -not $doc.props[0].movable -and $doc.props[1].movable) 'Fixture must contain both motion modes.'
    $rejected = $false
    try { Invoke-Stage 'Stage' } catch { $rejected = $true }
    Assert-Stage $rejected 'An existing ledger must prevent duplicate staging.'
    $prefabBytes = [IO.File]::ReadAllBytes($prefab)
    [IO.File]::WriteAllText($prefab, 'changed')
    $rejected = $false
    try { Invoke-Stage 'Restore' } catch { $rejected = $true }
    Assert-Stage ($rejected -and (Test-Path $map) -and (Test-Path $occupied) -and (Test-Path $ledger)) 'Restore must preserve every file if one hash changed.'
    [IO.File]::WriteAllBytes($prefab, $prefabBytes)
    Invoke-Stage 'Restore'
    Assert-Stage (-not (Test-Path $map) -and -not (Test-Path $occupied) -and -not (Test-Path $prefab) -and -not (Test-Path $ledger)) 'Restore must remove only the verified fixture files.'
    & $script -Action Stage -Scaled -BspPath $bsp -ContentDirectory $content -EngineMapDirectory $engine -LedgerPath $ledger | Out-Null
    $scaled = Get-Content -LiteralPath $prefab -Raw | ConvertFrom-Json
    Assert-Stage ($scaled.props[0].scale -eq 0.5 -and $scaled.props[1].scale -eq 2) 'Scaled fixture must contain the requested two sizes.'
    Invoke-Stage 'Restore'
    Assert-Stage (-not (Test-Path $map) -and -not (Test-Path $occupied) -and -not (Test-Path $prefab)) 'Scaled fixture restores through the same hash ledger.'
    $setpieceRoot = Join-Path $temporary 'setpieces'
    & (Join-Path $root 'bin\build_prefab_setpiece_fixture.ps1') -OutputDirectory $setpieceRoot | Out-Null
    $setpieceDirectory = Join-Path $setpieceRoot 'prefabs'
    & $script -Action Stage -Setpieces -BspPath $bsp -ContentDirectory $content -EngineMapDirectory $engine -LedgerPath $ledger -SetpiecesDirectory $setpieceDirectory | Out-Null
    $roadblock = Join-Path $content 'data_static\prefabs\zz_dev_roadblock.json'
    $gate = Join-Path $content 'data_static\prefabs\zz_dev_transition_gate.json'
    Assert-Stage ((Get-FileHash $roadblock).Hash -eq (Get-FileHash (Join-Path $setpieceDirectory 'zz_dev_roadblock.json')).Hash -and
        (Get-FileHash $gate).Hash -eq (Get-FileHash (Join-Path $setpieceDirectory 'zz_dev_transition_gate.json')).Hash) 'Both set pieces must retain their source hashes.'
    & $script -Action Restore -Setpieces -BspPath $bsp -ContentDirectory $content -EngineMapDirectory $engine -LedgerPath $ledger -SetpiecesDirectory $setpieceDirectory | Out-Null
    Assert-Stage (-not (Test-Path $roadblock) -and -not (Test-Path $gate) -and -not (Test-Path $occupied)) 'Set-piece staging must restore all owned files.'
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Output "Prefab fixture staging: $passed assertions passed."
