param(
    [string]$MapData = '',
    [string]$PlanData = '',
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    # Re-plans from the manifest and requires an identical result, proving the plan is current and seed-stable.
    [switch]$Replan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MapData)) {
    $mapFilename = if ($WorldProfile -eq 'preview') { 'preview_grid_24x24_seed_1337.json' } else { 'map_grid_64x64_seed_1337.json' }
    $MapData = Join-Path $PSScriptRoot $mapFilename
}
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilename = if ($WorldProfile -eq 'preview') { 'preview_grid_24x24_seed_1337_template_plan.json' } else { 'map_grid_64x64_seed_1337_template_plan.json' }
    $PlanData = Join-Path $PSScriptRoot $planFilename
}
if (-not (Test-Path -LiteralPath $MapData -PathType Leaf) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A current map manifest and matching template plan are required.'
}

$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
$plannerSettings = $worldGenerationProfile.Settings.cellPlanning
$maximumOpenTilePercent = [int]$plannerSettings.openTerrain.maximumOpenTilePercent
$variantChancePercent = [int]$plannerSettings.topologyVariants.chancePercent
$industryPattern = [string]$plannerSettings.templatePatterns.industry
$industryTerrains = @($plannerSettings.buildingSelection.industryTerrains | ForEach-Object { [string]$_ })
$industryProfiles = @($plannerSettings.buildingSelection.industryProfiles | ForEach-Object { [string]$_ })
$variantBases = @{}
foreach ($topology in $plannerSettings.topologyVariants.templates.Keys) {
    foreach ($variant in @($plannerSettings.topologyVariants.templates[$topology])) {
        $variantBases[[string]$variant] = [string]$plannerSettings.topologyTemplates[$topology]
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
# Hammer .vmx companions must belong to a live template; removed templates are not recreated from leftovers.
$tileTemplateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'tiletemplates'
foreach ($vmx in @(Get-ChildItem -LiteralPath $tileTemplateRoot -Recurse -Filter '*.vmx' -File)) {
    if (-not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($vmx.FullName, '.vmf')) -PathType Leaf)) {
        $errors.Add("Orphan Hammer file $($vmx.FullName.Substring($tileTemplateRoot.Length + 1)) has no matching .vmf; delete it rather than recreating the template.")
    }
}
# Tiles share ground at z=0 and the base shell floor at z=-32; a template authored far below it leaks once placed.
foreach ($template in @(Get-ChildItem -LiteralPath $tileTemplateRoot -Recurse -Filter '*.vmf' -File)) {
    $planeZ = @([regex]::Matches([IO.File]::ReadAllText($template.FullName), '"plane" "\([-\d.e]+ [-\d.e]+ ([-\d.e]+)\)') | ForEach-Object { [double]$_.Groups[1].Value })
    if ($planeZ.Count -gt 0) {
        $lowest = ($planeZ | Measure-Object -Minimum).Minimum
        $highest = ($planeZ | Measure-Object -Maximum).Maximum
        if ($lowest -lt -160 -or $highest -le 0) {
            $errors.Add("Template $($template.FullName.Substring($tileTemplateRoot.Length + 1)) spans z $lowest..$highest; tiles must be authored on the z=0 ground plane.")
        }
    }
}
$map = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$mapCells = @{}
foreach ($mapCell in @($map.cells)) { $mapCells["$($mapCell.x),$($mapCell.y)"] = $mapCell }

$templateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'tiletemplates'
$industrialSources = @(Get-ChildItem -LiteralPath (Join-Path $templateRoot 'buildings') -Filter 'tile_industrial_*.vmf' | ForEach-Object { "buildings/$($_.Name)" })
if ($industrialSources.Count -eq 0) { $errors.Add('No authored industrial building templates were found.') }
foreach ($source in $industrialSources) {
    if ($source -notmatch $industryPattern) { $errors.Add("Industrial template '$source' does not match cellPlanning.templatePatterns.industry.") }
    if ([System.IO.File]::ReadAllText((Join-Path $templateRoot $source)) -notmatch '"classname" "zn_tile_direction"') {
        $errors.Add("Industrial template '$source' has no zn_tile_direction frontage marker.")
    }
}

$recipes = @($plan.cells | Group-Object cellTemplateFilename | ForEach-Object { $_.Group[0] })
$openRatios = [System.Collections.Generic.List[double]]::new()
$industrialTiles = 0
$industrialTemplatesUsed = @{}
$eligibleStraight = 0
$variantTiles = 0
foreach ($recipe in $recipes) {
    $placements = @($recipe.tilePlacements)
    $gridTiles = [int]$recipe.tileGridSize * [int]$recipe.tileGridSize
    $openRatio = @($placements | Where-Object { $_.role -eq 'terrain' }).Count / [double]$gridTiles
    $openRatios.Add($openRatio)
    if ($openRatio * 100 -gt $maximumOpenTilePercent + 0.001) {
        $errors.Add("$($recipe.cellTemplateFilename) keeps $([Math]::Round($openRatio * 100, 1))% open terrain; the planner cap is $maximumOpenTilePercent%.")
    }

    $mapCell = $mapCells["$($recipe.x),$($recipe.y)"]
    foreach ($placement in @($placements | Where-Object { [string]$_.template -match $industryPattern })) {
        $industrialTiles++
        $industrialTemplatesUsed[[string]$placement.template] = $true
        if ($placement.role -notlike 'building*') {
            $errors.Add("$($recipe.cellTemplateFilename) uses $($placement.template) as role '$($placement.role)'.")
        }
        $terrain = if ($null -ne $mapCell) { [string]$mapCell.environment.terrain } else { '' }
        if ($terrain -notin $industryTerrains -and [string]$recipe.environmentProfile -notin $industryProfiles) {
            $errors.Add("$($recipe.cellTemplateFilename) places industrial template $($placement.template) outside the industry terrains/profiles (terrain=$terrain, profile=$($recipe.environmentProfile)).")
        }
    }

    foreach ($placement in $placements) {
        $template = [string]$placement.template
        $isVariant = $variantBases.ContainsKey($template)
        if ($placement.role -eq 'road' -and ($isVariant -or $template -in $variantBases.Values)) {
            $eligibleStraight++
            if ($isVariant) { $variantTiles++ }
        }
        if (-not $isVariant) { continue }
        if ($placement.role -ne 'road') {
            $errors.Add("$($recipe.cellTemplateFilename) places variant $template at ($($placement.tileX),$($placement.tileY)) with role '$($placement.role)'; variants replace plain straight road tiles only.")
        }
        $isMotorwayVariant = $variantBases[$template] -eq [string]$plannerSettings.topologyTemplates['motorway-straight']
        if ($isMotorwayVariant -ne ([string]$recipe.topology -like 'motorway-*')) {
            $errors.Add("$($recipe.cellTemplateFilename) places $template on a $($recipe.topology) recipe.")
        }
    }
}

$openMean = ($openRatios | Measure-Object -Average).Average * 100
$openMaximum = ($openRatios | Measure-Object -Maximum).Maximum * 100
if ($openMean -gt 18) { $errors.Add("Mean open terrain is $([Math]::Round($openMean, 1))%; the Phase E target is at most 18%.") }
if ($openMaximum -gt 32) { $errors.Add("A recipe keeps $([Math]::Round($openMaximum, 1))% open terrain; the Phase E target is at most 32%.") }
if ($industrialTiles -eq 0) { $errors.Add('The plan places no industrial building templates.') }
$variantPercent = if ($eligibleStraight -gt 0) { 100.0 * $variantTiles / $eligibleStraight } else { 0 }
if ($variantChancePercent -gt 0 -and [Math]::Abs($variantPercent - $variantChancePercent) -gt 10) {
    $errors.Add("Road/motorway variants cover $([Math]::Round($variantPercent, 1))% of eligible straight tiles; expected about $variantChancePercent%.")
}
foreach ($variant in $variantBases.Keys) {
    if (-not (@($recipes | ForEach-Object { $_.tilePlacements } | Where-Object { $_.template -eq $variant }).Count -gt 0)) {
        $errors.Add("Variant template $variant is never selected by the plan.")
    }
}

if ($Replan) {
    $outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'zombiesim-phase-e-replan'
    [System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
    $replanPath = Join-Path $outputRoot 'template_plan.json'
    & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile $WorldProfile -MapData $MapData -Output $replanPath -ListOutput (Join-Path $outputRoot 'required_cell_vmfs.txt') -SettingsPath $SettingsPath | Out-Null
    if (-not $?) { throw 'Replanning failed.' }
    $replanned = Get-Content -Raw -LiteralPath $replanPath | ConvertFrom-Json
    $expectedCells = $plan.cells | ConvertTo-Json -Depth 12 -Compress
    $actualCells = $replanned.cells | ConvertTo-Json -Depth 12 -Compress
    if ($expectedCells -ne $actualCells) {
        $errors.Add('Replanning the same manifest produced different cells; the plan is stale or selection is not seed-stable.')
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Phase E layout validation failed with $($errors.Count) error(s)."
}
Write-Output ("Phase E layout checks passed: recipes={0}; open terrain mean={1:N1}% max={2:N1}%; industrial tiles={3} ({4}); variants={5}/{6} ({7:N1}%){8}." -f $recipes.Count, $openMean, $openMaximum, $industrialTiles, ((@($industrialTemplatesUsed.Keys | Sort-Object) | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) }) -join ', '), $variantTiles, $eligibleStraight, $variantPercent, $(if ($Replan) { '; replan identical' } else { '' }))
