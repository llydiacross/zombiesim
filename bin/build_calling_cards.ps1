param(
    [string]$SourceDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\scoreboard\callingcards'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'generated\callingcards_preview'),
    [string]$DefaultsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'content'),
    [ValidateRange(0, 100000)][int]$MaximumGenerated = 512,
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'calling_cards.psm1') -Force -DisableNameChecking

$plan = Get-CallingCardPlan -SourceDirectory $SourceDirectory -DefaultsRoot $DefaultsRoot -MaximumGenerated $MaximumGenerated
Write-Host "Calling cards: $($plan.finished.Count) finished, $($plan.generated.Count) generated, two existing defaults."
foreach ($card in @($plan.finished) + @($plan.generated)) {
    Write-Host "  $($card.id) -> materials/$($card.material)"
}
foreach ($path in $plan.ignored) { Write-Host "  Ignored non-PNG source: $path" }
if ($PlanOnly) {
    Write-Host 'Plan only; no preview files or staged content were written.'
    return
}

$result = Build-CallingCardPreview -Plan $plan -OutputDirectory $OutputDirectory
Write-Host "Preview built at $($result.directory); nothing was staged."
$result
