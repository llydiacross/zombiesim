param(
    [string]$PlanData = '',
    [string]$Output = '',
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$generatorSettings = & (Join-Path $PSScriptRoot 'import_generator_settings.ps1') -SettingsPath $SettingsPath

if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $PlanData = @(Get-ChildItem -Path $PSScriptRoot -Filter '*_template_plan.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path $PlanData)) {
    throw 'A template plan is required. Pass -PlanData with a *_template_plan.json path.'
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $planBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PlanData)
    $Output = Join-Path (Join-Path $projectRoot $generatorSettings.paths.scriptOutputDirectory) ("{0}_filename_key.txt" -f $planBaseName)
}

$plan = Get-Content -Raw $PlanData | ConvertFrom-Json
if ($plan.schemaVersion -lt 3 -or $null -eq $plan.filenameAbbreviations) {
    throw 'The template plan must use schema version 3 or later and include filenameAbbreviations.'
}

$requiredRecipes = @($plan.requiredCellFiles | Sort-Object @{ Expression = 'cellCount'; Descending = $true }, filename)
if ($requiredRecipes.Count -eq 0) {
    throw "No required cell recipes were found in $PlanData"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Template plan: $([System.IO.Path]::GetFileName($PlanData))")
$lines.Add("Recipes: $($requiredRecipes.Count)")
$lines.Add('')

foreach ($recipe in $requiredRecipes) {
    $landmarks = @($recipe.landmarks | Where-Object { $_ -ne 'none' })
    $landmarkLabel = if ($landmarks.Count -gt 0) { $landmarks -join ', ' } else { 'none' }
    $transportLabel = if ($recipe.transportFeature -eq 'none') { 'none' } else { $recipe.transportFeature }
    $variantLabel = if ($recipe.variant -gt 0) { "v$($recipe.variant) of $($recipe.availableVariants) from $($recipe.baseFilename)" } else { 'base layout' }
    $coordinates = @($recipe.cells | ForEach-Object { "($($_.x),$($_.y))" }) -join ', '
    $lines.Add($recipe.filename)
    $lines.Add("  Variant: $variantLabel")
    $lines.Add("  Environment: $($recipe.environmentProfile)")
    $lines.Add("  Layout: $($recipe.topology), $($recipe.orientation)")
    $lines.Add("  Transport: $transportLabel")
    $lines.Add("  Building density tier: $($recipe.filenameCodes.density)")
    $lines.Add("  Landmarks: $landmarkLabel")
    $lines.Add("  Used by $($recipe.cellCount) cell(s): $coordinates")
    $lines.Add('')
}

[System.IO.File]::WriteAllLines($Output, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote filename key: $Output"
