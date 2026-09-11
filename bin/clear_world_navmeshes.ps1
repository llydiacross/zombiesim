param(
    [string]$RuntimeNavmeshDirectory = '',
    [string]$StagedNavmeshDirectory = '',
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
if ([string]::IsNullOrWhiteSpace($RuntimeNavmeshDirectory)) {
    $gameRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
    $RuntimeNavmeshDirectory = Join-Path (Join-Path $gameRoot 'maps') $worldGenerationProfile.Name
}
if ([string]::IsNullOrWhiteSpace($StagedNavmeshDirectory)) {
    $StagedNavmeshDirectory = Join-Path $projectRoot $profileSettings.releaseMapDirectory
}

$directories = @($RuntimeNavmeshDirectory, $StagedNavmeshDirectory | Select-Object -Unique)
$navmeshes = @(
    foreach ($directory in $directories) {
        if (Test-Path -LiteralPath $directory -PathType Container) {
            Get-ChildItem -LiteralPath $directory -Filter '*.nav' -File
        }
    }
)

if ($WhatIf) {
    Write-Output "WhatIf: remove $($navmeshes.Count) $($worldGenerationProfile.Name) profile navmeshes from $($directories -join ' and ')"
    return
}

foreach ($navmesh in $navmeshes) {
    Remove-Item -LiteralPath $navmesh.FullName -Force
}

Write-Output "Removed $($navmeshes.Count) $($worldGenerationProfile.Name) profile navmeshes from $($directories -join ' and ')"