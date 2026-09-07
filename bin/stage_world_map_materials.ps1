param(
    [string]$MapData = '',
    [string]$DestinationDirectory = '',
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
if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilePattern = "$($profileSettings.filePrefix)_grid_*.json"
    $MapData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $mapFilePattern -File |
        Where-Object { $_.Name -notlike '*_template_plan.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path -LiteralPath $MapData -PathType Leaf)) {
    throw 'A generated map manifest is required. Pass -MapData with a <profile>_grid_*.json path.'
}
if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    $DestinationDirectory = Join-Path $projectRoot (Join-Path (Join-Path 'content/materials/worlds' $worldGenerationProfile.Name) 'map_layers')
}

$sourceDirectory = Split-Path -Parent $MapData
$outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MapData)
$compositeFilename = "$outputBaseName.png"
$mapImageFiles = @(
    Get-ChildItem -LiteralPath $sourceDirectory -File -Filter '*.png' |
        Where-Object { $_.Name -eq $compositeFilename -or $_.Name -like "$outputBaseName`_*.png" } |
        Sort-Object Name
)
if (-not ($mapImageFiles.Name -contains $compositeFilename)) {
    throw "Generated map image is missing: $(Join-Path $sourceDirectory $compositeFilename)"
}
if ([bool]$profileSettings.exportLayers -and $mapImageFiles.Count -lt 2) {
    throw "World-generation profile '$($worldGenerationProfile.Name)' exports map layers, but none were generated for $outputBaseName. Re-run generate_world_cells.ps1 for this manifest."
}

if ($WhatIf) {
    Write-Output "WhatIf: stage $($mapImageFiles.Count) generated map image(s) in: $DestinationDirectory"
    return
}

[System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null
Get-ChildItem -LiteralPath $DestinationDirectory -Filter '*.png' -File | Remove-Item -Force
$stagedImageNames = [System.Collections.Generic.List[string]]::new()
foreach ($mapImageFile in $mapImageFiles) {
    $destinationFilename = if ($mapImageFile.Name -eq $compositeFilename) {
        'world.png'
    } else {
        $mapImageFile.Name.Substring($outputBaseName.Length + 1)
    }
    Copy-Item -LiteralPath $mapImageFile.FullName -Destination (Join-Path $DestinationDirectory $destinationFilename) -Force
    $stagedImageNames.Add($destinationFilename)
}

Write-Output "Staged $($mapImageFiles.Count) generated map image(s): $DestinationDirectory ($($stagedImageNames -join ', '))"