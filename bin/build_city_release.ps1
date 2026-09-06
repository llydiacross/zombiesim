param(
    [string]$MapData = '',
    [string]$PlanData = '',
    [string]$SourceDirectory = '',
    [string]$BuildDirectory = '',
    [string]$ContentMapDirectory = '',
    [string]$RuntimeWorldData = '',
    [string]$GameDirectory = '',
    [string]$CompilerDirectory = '',
    [string]$CompilerProfile = '',
    [int]$VbspTimeoutSeconds = 0,
    [int]$VvisTimeoutSeconds = 0,
    [int]$VradTimeoutSeconds = 0,
    [int]$DeferredGraceSeconds = 0,
    [switch]$OnlyRequiredMaps,
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$VBSPOnly,
    [switch]$SkipRecipeRefresh,
    [switch]$SkipCompile,
    [switch]$Force,
    [switch]$FinalizeWithIncomplete,
    [switch]$CleanStagedCity,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilePattern = "$($profileSettings.filePrefix)_grid_*.json"
    $MapData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $mapFilePattern -File |
        Where-Object { $_.Name -notlike '*_template_plan.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $projectRoot $profileSettings.cellDirectory
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $projectRoot $profileSettings.buildDirectory
}
if ([string]::IsNullOrWhiteSpace($ContentMapDirectory)) {
    $ContentMapDirectory = Join-Path $projectRoot $profileSettings.releaseMapDirectory
}
if ([string]::IsNullOrWhiteSpace($RuntimeWorldData)) {
    $RuntimeWorldData = Join-Path $projectRoot $profileSettings.runtimeWorldData
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path -LiteralPath $MapData -PathType Leaf)) {
    throw 'A generated map manifest is required. Pass -MapData with a map_grid_*.json path.'
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a map_grid_*_template_plan.json path.'
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
if ($plan.schemaVersion -lt 2) { throw 'The template plan must use schema version 2 or later.' }
$cityVmfNames = @($plan.cells | ForEach-Object { [string]$_.cellTemplateFilename } | Sort-Object -Unique)
$safeZoneVmfNames = @($plan.safeZoneMaps | ForEach-Object { [string]$_.mapFilename } | Sort-Object -Unique)
$requiredVmfNames = @($cityVmfNames + $safeZoneVmfNames | Sort-Object -Unique)
if ($cityVmfNames.Count -eq 0) { throw 'The template plan does not select any city recipe VMFs.' }
foreach ($filename in $requiredVmfNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $filename) -PathType Leaf)) {
        throw "Required source VMF is missing: $(Join-Path $SourceDirectory $filename)"
    }
}

if (-not $SkipRecipeRefresh) {
    $refreshArguments = @{
        PlanData = $PlanData
        CellDirectory = $SourceDirectory
        RefreshGenerated = $true
        WhatIf = $WhatIf
        WorldProfile = $worldGenerationProfile.Name
        SettingsPath = $SettingsPath
    }
    & (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') @refreshArguments
}

if ($WhatIf) {
    Write-Output "WhatIf: required city recipe BSPs: $($cityVmfNames.Count)"
    Write-Output "WhatIf: required standalone den BSPs: $($safeZoneVmfNames.Count)"
    Write-Output "WhatIf: stage BSPs in: $ContentMapDirectory"
    Write-Output "WhatIf: write runtime world data: $RuntimeWorldData"
}

if (-not $SkipCompile) {
    $compileArguments = @{
        SourceDirectory = $SourceDirectory
        BuildDirectory = $BuildDirectory
        GameDirectory = $GameDirectory
        CompilerDirectory = $CompilerDirectory
        CompilerProfile = $CompilerProfile
        VbspTimeoutSeconds = $VbspTimeoutSeconds
        VvisTimeoutSeconds = $VvisTimeoutSeconds
        VradTimeoutSeconds = $VradTimeoutSeconds
        DeferredGraceSeconds = $DeferredGraceSeconds
        Force = $Force
        WhatIf = $WhatIf
        WorldProfile = $worldGenerationProfile.Name
        VBSPOnly = $VBSPOnly
        FinalizeWithIncomplete = $FinalizeWithIncomplete
        SettingsPath = $SettingsPath
    }
    if ($OnlyRequiredMaps) { $compileArguments.MapFilename = $requiredVmfNames }
    & (Join-Path $PSScriptRoot 'compile_cell_vmfs.ps1') @compileArguments
    if (-not $WhatIf) {
        $compileReportPath = Join-Path $BuildDirectory 'compile-report.json'
        if (-not (Test-Path -LiteralPath $compileReportPath -PathType Leaf)) {
            throw "Compiler did not create the expected report: $compileReportPath"
        }
        $compileReport = Get-Content -LiteralPath $compileReportPath -Raw | ConvertFrom-Json
        if ($compileReport.failedCount -gt 0 -or $compileReport.incompleteCount -gt 0) {
            $message = "Release staging stopped: $($compileReport.failedCount) failed and $($compileReport.incompleteCount) incomplete compile(s). Review $compileReportPath."
            if ($FinalizeWithIncomplete) {
                Write-Warning "$message No BSPs or runtime data were staged."
                return
            }
            throw $message
        }
    }
}

if ($WhatIf) {
    Write-Output 'WhatIf: no runtime data or staged files were written.'
    return
}

$requiredBspNames = @($requiredVmfNames | ForEach-Object { [System.IO.Path]::ChangeExtension($_, '.bsp') })
foreach ($bspName in $requiredBspNames) {
    $buildBspPath = Join-Path $BuildDirectory $bspName
    if (-not (Test-Path -LiteralPath $buildBspPath -PathType Leaf)) {
        throw "Required compiled BSP is missing: $buildBspPath"
    }
}

if ($CleanStagedCity -and (Test-Path -LiteralPath $ContentMapDirectory)) {
    $stagedBspNames = @($requiredBspNames | ForEach-Object { $_.ToLowerInvariant() })
    foreach ($stagedBsp in (Get-ChildItem -LiteralPath $ContentMapDirectory -Filter '*.bsp' -File)) {
        if ($stagedBsp.Name.ToLowerInvariant() -notin $stagedBspNames) {
            Remove-Item -LiteralPath $stagedBsp.FullName -Force
        }
    }
}
[System.IO.Directory]::CreateDirectory($ContentMapDirectory) | Out-Null
foreach ($bspName in $requiredBspNames) {
    Copy-Item -LiteralPath (Join-Path $BuildDirectory $bspName) -Destination (Join-Path $ContentMapDirectory $bspName) -Force
}

& (Join-Path $PSScriptRoot 'export_runtime_world_data.ps1') -MapData $MapData -PlanData $PlanData -BuildDirectory $BuildDirectory -Output $RuntimeWorldData -WorldProfile $worldGenerationProfile.Name -RequireCompiledMaps -SettingsPath $SettingsPath
if (-not (Test-Path -LiteralPath $RuntimeWorldData -PathType Leaf)) {
    throw "Runtime-world exporter did not create the expected data file: $RuntimeWorldData"
}

Write-Output "Release city recipe BSPs: $($cityVmfNames.Count); standalone den BSPs: $($safeZoneVmfNames.Count); staged maps: $ContentMapDirectory; runtime world data: $RuntimeWorldData"