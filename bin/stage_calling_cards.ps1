param(
    [Parameter(Mandatory)][string]$BuildDirectory,
    [string]$ContentRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'content'),
    [switch]$Apply,
    [switch]$RightsConfirmed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'calling_cards.psm1') -Force -DisableNameChecking
$result = Install-CallingCardBuild -BuildDirectory $BuildDirectory -ContentRoot $ContentRoot -Apply:$Apply -RightsConfirmed:$RightsConfirmed
Write-Host "Calling cards: $($result.active) active artist designs, $($result.retained) retained owned files."
foreach ($change in $result.changes) { Write-Host "  $change" }
if ($result.applied) { Write-Host 'Staging verified; default images were not changed.' }
else { Write-Host 'Dry run only; no staged content was changed.' }
$result
