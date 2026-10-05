param(
    [string]$WorldProfile = 'preview',
    [string]$PlanData = '',
    [string]$ContentDirectory = '',
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
$prefix = [string]$profile.Config.filePrefix
if ([string]::IsNullOrWhiteSpace($ContentDirectory)) { $ContentDirectory = Join-Path $projectRoot 'content' }
elseif (-not [System.IO.Path]::IsPathRooted($ContentDirectory)) { $ContentDirectory = Join-Path $projectRoot $ContentDirectory }
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $plans = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "${prefix}_grid_*_template_plan.json" -File | Sort-Object LastWriteTime -Descending)
    if ($plans.Count -eq 0) { throw "No template plan exists for $WorldProfile." }
    $PlanData = $plans[0].FullName
}
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$manifestPath = Join-Path $ContentDirectory "data_static\zombiesim_skybox_$prefix.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$sky = $profile.Settings.vmfBuild.skybox3d
foreach ($field in 'schemaVersion', 'profile', 'scale', 'neighbourRadius', 'skylineRadius', 'maxTowerModels', 'cameraOrigin', 'cellSpan', 'recipes', 'snow', 'towers') {
    if (-not $manifest.PSObject.Properties[$field]) { throw "Skybox manifest is stale or invalid: missing $field." }
}
if ($manifest.schemaVersion -ne 1 -or $manifest.profile -ne $prefix -or
    $manifest.scale -ne $sky.scale -or $manifest.neighbourRadius -ne $sky.neighbourRadius -or
    $manifest.skylineRadius -ne $sky.skylineRadius -or $manifest.maxTowerModels -ne $sky.maxTowerModels -or
    $manifest.cameraOrigin[2] -ne $sky.cameraZ -or
    $manifest.cellSpan -ne ($plan.cellTileGridSize + 2) * $profile.Settings.vmfBuild.tileSize) {
    throw 'Skybox manifest does not match the active plan/settings.'
}

$recipeNames = @($plan.cells | ForEach-Object {
    [System.IO.Path]::GetFileNameWithoutExtension($_.cellTemplateFilename).ToLowerInvariant()
} | Sort-Object -Unique)
foreach ($tableName in 'recipes', 'snow', 'towers') {
    $table = $manifest.$tableName
    $actualNames = @($table.PSObject.Properties.Name | Sort-Object)
    $expectedNames = @(if ($tableName -ne 'snow' -or $sky.snowOverlay) { $recipeNames })
    if (($expectedNames.Count -ne $actualNames.Count) -or
        ($expectedNames.Count -gt 0 -and @(Compare-Object $expectedNames $actualNames).Count -ne 0)) {
        throw "Skybox $tableName entries do not exactly match the plan recipes."
    }
    foreach ($entry in $table.PSObject.Properties) {
        foreach ($path in $entry.Value) {
            if ($path -notmatch '^models/zombiesim/skybox/cells/[a-z0-9_-]+\.mdl$') {
                throw "Invalid generated model path: $path"
            }
            $base = Join-Path $ContentDirectory ($path -replace '/', '\' -replace '\.mdl$', '')
            foreach ($extension in '.mdl', '.vvd', '.dx90.vtx') {
                if (-not (Test-Path -LiteralPath "$base$extension" -PathType Leaf) -or
                    (Get-Item -LiteralPath "$base$extension").Length -eq 0) {
                    throw "Missing or empty compiled model companion: $base$extension"
                }
            }
        }
    }
}

$towerCells = @($plan.cells | Where-Object {
    @($_.tilePlacements | Where-Object { $_.template -match '(^|/)tile_skyscraper_[0-9]+[a-z]+_2x\.vmf$' }).Count -gt 0
})
foreach ($cell in $plan.cells) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($cell.cellTemplateFilename).ToLowerInvariant()
    $hasTower = @($cell.tilePlacements | Where-Object {
        $_.template -match '(^|/)tile_skyscraper_[0-9]+[a-z]+_2x\.vmf$'
    }).Count -gt 0
    if ($hasTower -ne (@($manifest.towers.$name).Count -gt 0)) {
        throw "Tower-only parts disagree with planned geometry for $name."
    }
}

$worstCandidates = 0
$overBudgetViews = 0
foreach ($view in $plan.cells) {
    $candidates = 0
    foreach ($tower in $towerCells) {
        $distance = [math]::Max([math]::Abs($tower.x - $view.x), [math]::Abs($tower.y - $view.y))
        if ($distance -gt $manifest.neighbourRadius -and $distance -le $manifest.skylineRadius) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($tower.cellTemplateFilename).ToLowerInvariant()
            $candidates += @($manifest.towers.$name).Count
        }
    }
    $worstCandidates = [math]::Max($worstCandidates, $candidates)
    if ($candidates -gt $manifest.maxTowerModels) { $overBudgetViews++ }
}
if ($WorldProfile -eq 'preview' -and $overBudgetViews -gt 0) {
    throw "Preview skyline truncates tower parts in $overBudgetViews views (worst=$worstCandidates, budget=$($manifest.maxTowerModels))."
}
Write-Output "Skybox manifest passed: recipes=$($recipeNames.Count), towerCells=$($towerCells.Count), views=$(@($plan.cells).Count), worstDistantParts=$worstCandidates, budget=$($manifest.maxTowerModels), truncatedViews=$overBudgetViews; model companions/settings/plan verified."
