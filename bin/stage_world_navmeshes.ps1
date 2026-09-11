param(
    [string]$PlanData = '',
    [string]$SourceDirectory = '',
    [string]$DestinationDirectory = '',
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$CleanStagedCity,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a <profile>_grid_*_template_plan.json path.'
}
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $gameRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
    $SourceDirectory = Join-Path (Join-Path $gameRoot 'maps') $worldGenerationProfile.Name
}
if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    $DestinationDirectory = Join-Path $projectRoot $profileSettings.releaseMapDirectory
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$mapNames = @(
    @($plan.cells | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension([string]$_.cellTemplateFilename) }) +
    @($plan.safeZoneMaps | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension([string]$_.mapFilename) }) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
)
if ($mapNames.Count -eq 0) {
    throw 'The template plan contains no city or safe-zone map names.'
}
if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "The runtime navmesh directory does not exist: $SourceDirectory"
}

if ($WhatIf) {
    Write-Output "WhatIf: stage up to $($mapNames.Count) profile-matching navmeshes from $SourceDirectory to $DestinationDirectory"
    return
}

[System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null
$requiredMapNames = @{}
foreach ($mapName in $mapNames) {
    $requiredMapNames[$mapName.ToLowerInvariant()] = $true
}
if ($CleanStagedCity) {
    foreach ($stagedNavmesh in Get-ChildItem -LiteralPath $DestinationDirectory -Filter '*.nav' -File) {
        $mapName = [System.IO.Path]::GetFileNameWithoutExtension($stagedNavmesh.Name).ToLowerInvariant()
        if (-not $requiredMapNames.ContainsKey($mapName)) {
            Remove-Item -LiteralPath $stagedNavmesh.FullName -Force
        }
    }
}

$stagedCount = 0
$missingCount = 0
foreach ($mapName in $mapNames) {
    $navmeshName = "$mapName.nav"
    $sourcePath = Join-Path $SourceDirectory $navmeshName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $missingCount++
        continue
    }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $DestinationDirectory $navmeshName) -Force
    $stagedCount++
}

Write-Output "Staged $stagedCount existing navmeshes; $missingCount required maps have no runtime navmesh: $DestinationDirectory"
