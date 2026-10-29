param([Parameter(Mandatory = $true)][string]$BuildDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stage = Join-Path $root 'bin\stage_prefab_road_preview.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zombiesim-road-stage-' + [Guid]::NewGuid().ToString('N'))
$content = Join-Path $temporary 'content'
$game = Join-Path $temporary 'game'
$ledger = Join-Path $temporary 'ledger.json'
$passed = 0
function Assert-Stage([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Prefab road staging: $Message" }
    $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Stage $rejected $Message
}
[IO.Directory]::CreateDirectory($temporary) | Out-Null
try {
    $parameters = @{ BuildDirectory = $BuildDirectory; ContentRoot = $content; GameRoot = $game; LedgerPath = $ledger }
    & $stage @parameters | Out-Null
    Assert-Stage (-not (Test-Path -LiteralPath $content) -and -not (Test-Path -LiteralPath $game) -and
        -not (Test-Path -LiteralPath $ledger)) 'Dry run changes no destination or ledger.'
    & $stage @parameters -Apply | Out-Null
    $record = Get-Content -LiteralPath $ledger -Raw | ConvertFrom-Json
    Assert-Stage ($record.state -eq 'staged' -and @($record.files).Count -gt 0) 'Apply writes a complete staging ledger.'
    foreach ($entry in $record.files) {
        Assert-Stage ((Get-FileHash -LiteralPath $entry.destination -Algorithm SHA256).Hash -ceq $entry.sha256) 'Each staged file matches its source hash.'
    }
    Assert-Rejected { & $stage @parameters -Apply } 'A second stage cannot overwrite the existing ledger or files.'
    $extra = Join-Path $content 'unrelated.txt'
    [IO.File]::WriteAllText($extra, 'keep')
    $changed = $record.files[0]
    [IO.File]::WriteAllText($changed.destination, 'changed')
    Assert-Rejected { & $stage @parameters -Cleanup } 'Cleanup refuses to remove a changed staged file.'
    Assert-Stage ((Test-Path -LiteralPath $extra) -and (Test-Path -LiteralPath $record.files[-1].destination)) 'Failed cleanup preserves unrelated and remaining files.'
    [IO.File]::Copy($changed.source, $changed.destination, $true)
    & $stage @parameters -Cleanup | Out-Null
    $after = Get-Content -LiteralPath $ledger -Raw | ConvertFrom-Json
    Assert-Stage ($after.state -eq 'removed') 'Successful cleanup records removal.'
    Assert-Stage (@($record.files | Where-Object { Test-Path -LiteralPath $_.destination }).Count -eq 0) 'Only the verified staged files are removed.'
    Assert-Stage (Test-Path -LiteralPath $extra -PathType Leaf) 'Unrelated files remain untouched.'
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Output "Prefab road staging: $passed assertions passed."
