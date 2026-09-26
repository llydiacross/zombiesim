param(
    [Parameter(Mandatory)]
    [ValidateSet('city', 'preview')]
    [string]$WorldProfile,
    [string]$PlanData = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $prefix = if ($WorldProfile -eq 'city') { 'map' } else { 'preview' }
    $planPattern = "$prefix`_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planPattern -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0].FullName
}
if (-not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw "Template plan was not found: $PlanData"
}

$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile
$releaseMapDirectory = [string]$profile.Config.releaseMapDirectory
if ([System.IO.Path]::GetFileName($releaseMapDirectory.TrimEnd('\', '/')) -ne 'maps') {
    throw "Profile '$WorldProfile' must stage maps directly under content/maps; found '$releaseMapDirectory'."
}
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$mapPrefix = "zz_${WorldProfile}_"
$badRecipes = @($plan.cells | Where-Object { [string]$_.cellTemplateFilename -notlike "$mapPrefix*.vmf" })
$badDens = @($plan.safeZoneMaps | Where-Object { [string]$_.mapFilename -notlike "${mapPrefix}den_*.vmf" })
if ($badRecipes.Count -gt 0 -or $badDens.Count -gt 0) {
    throw "Profile '$WorldProfile' has invalid map prefixes: recipes=$($badRecipes.Count), dens=$($badDens.Count)."
}
$recipeNames = @($plan.requiredCellFiles | ForEach-Object { [string]$_.filename })
$uniqueRecipeNames = @($recipeNames | Sort-Object -Unique)
$maximumBasenameLength = @($recipeNames | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_).Length } | Measure-Object -Maximum).Maximum
if ($recipeNames.Count -ne $uniqueRecipeNames.Count) {
    throw "Profile '$WorldProfile' has colliding generated recipe basenames."
}
if ($maximumBasenameLength -gt 32) {
    throw "Profile '$WorldProfile' generated map basename length $maximumBasenameLength exceeds the 32-character cubemap-safe limit."
}

$expectedLauncher = "zn_${WorldProfile}_start"
if ([string]$profile.Config.thumbnail.map -ne $expectedLauncher) {
    throw "Profile '$WorldProfile' thumbnail map must be '$expectedLauncher'; found '$($profile.Config.thumbnail.map)'."
}
$launcherSource = Join-Path $projectRoot (Join-Path $profile.Settings.paths.launcherTemplateDirectory "$expectedLauncher.vmf")
if (-not (Test-Path -LiteralPath $launcherSource -PathType Leaf)) {
    throw "Launcher source VMF is missing: $launcherSource"
}

$gamemodeText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'zombiesim.txt')
$mapFilter = [regex]::Match($gamemodeText, '(?m)^\s*"maps"\s+"([^"]+)"').Groups[1].Value
if ($mapFilter -ne '^zn_' -or $expectedLauncher -notmatch $mapFilter -or 'zz_recipe_probe' -match $mapFilter) {
    throw "Gamemode map filter '$mapFilter' must include '$expectedLauncher' and exclude generated zz_ maps."
}

$worldSource = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'gamemode/utils/world.lua')
$launcherEntry = [regex]::Escape($expectedLauncher) + '\s*=\s*"' + [regex]::Escape($WorldProfile) + '"'
if ($worldSource -notmatch $launcherEntry) {
    throw "World profile lookup does not map '$expectedLauncher' to '$WorldProfile'."
}

Write-Output ("Map naming passed: profile={0}; recipes={1}; dens={2}; launcher={3}; prefix={4}; maxNameLength={5}" -f $WorldProfile,$plan.cells.Count,$plan.safeZoneMaps.Count,$expectedLauncher,$mapPrefix,$maximumBasenameLength)
