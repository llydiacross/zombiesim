Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'template_inventory.psm1') -Force
$projectRoot = $testsRepoRoot
$profile = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$settings = $profile.Settings
$templateRoot = Join-Path $projectRoot $settings.paths.templateDirectory
$passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Template inventory: $Message" }
    $script:passed++
}

Assert-ZMRequiredMotorwayTemplateSettings -Settings $settings
$referenceCount = Assert-ZMConfiguredTileTemplatePaths -Settings $settings -TemplateRoot $templateRoot
Assert ($referenceCount -ge 50) 'Explicit tile sources across planner, border and edge pools are validated.'
$expectedMotorwayTopologies = @{
    'motorway-straight' = 'roads/motorway_3x1/tile_motorway.vmf'
    'motorway-corner' = 'roads/motorway_3x1/tile_motorway_corner_5x3.vmf'
    'motorway-tjunction' = 'roads/motorway_3x1/tile_motorway_tjunction_6x3.vmf'
    'motorway-crossjunction' = 'roads/motorway_3x1/tile_motorway_crossroads_3x3.vmf'
    'motorway-deadend' = 'roads/motorway_3x1/tile_motorway_deadend_3x3.vmf'
}
$expectedMotorwayTransports = @{
    'bridge' = 'roads/motorway_3x1/tile_motorway_road_bridge.vmf'
    'onramp' = 'roads/motorway_3x1/tile_motorway_onramp_3x4.vmf'
    'onramp-dual' = 'roads/motorway_3x1/tile_motorway_onramp_dual_3x4.vmf'
}
foreach ($key in $expectedMotorwayTopologies.Keys) {
    Assert ($settings.cellPlanning.topologyTemplates[$key] -ceq $expectedMotorwayTopologies[$key]) "$key maps to its exact approved wide source."
}
foreach ($key in $expectedMotorwayTransports.Keys) {
    Assert ($settings.cellPlanning.transportTemplates[$key] -ceq $expectedMotorwayTransports[$key]) "$key maps to its exact approved wide source."
}
Assert (-not $settings.cellPlanning.topologyVariants.templates.ContainsKey('motorway-straight')) 'Legacy 1x1 visual variants are not offered as 3x1 motorway replacements.'

$profileRoadVariants = $settings.cellPlanning.topologyVariants.profileTemplates
$expectedProfileRoads = @{
    radioactive = @('roads/tile_ra_road.vmf', 'roads/tile_ra_road_a.vmf', 'roads/tile_ra_road_b.vmf', 'roads/tile_ra_road_c.vmf', 'roads/tile_ra_road_night.vmf')
    destroyed = @('roads/tile_destroyed_road.vmf', 'roads/tile_destroyed_road_a.vmf', 'roads/tile_destroyed_road_b.vmf', 'roads/tile_destroyed_road_c.vmf', 'roads/tile_destroyed_road_night.vmf')
    military = @('roads/tile_army_road.vmf', 'roads/tile_army_road_a.vmf', 'roads/tile_army_road_b.vmf', 'roads/tile_army_road_c.vmf', 'roads/tile_army_road_d.vmf')
    fortified = @('roads/tile_army_road.vmf', 'roads/tile_army_road_a.vmf', 'roads/tile_army_road_b.vmf', 'roads/tile_army_road_c.vmf', 'roads/tile_army_road_d.vmf')
}
foreach ($profileName in $expectedProfileRoads.Keys) {
    $configuredRoads = @($profileRoadVariants[$profileName]['road-straight'])
    foreach ($template in $expectedProfileRoads[$profileName]) {
        Assert ($configuredRoads -contains $template) "$profileName straight-road selection includes $template."
    }
}
Assert ($settings.atmosphere.environmentLightingProfiles.radioactive -ceq 'dead_zone' -and
    $settings.atmosphere.environmentLightingProfiles.destroyed -ceq 'dead_zone' -and
    $settings.atmosphere.lightingProfiles.dead_zone.skyname -ceq 'sky_borealis01') 'Night-road profiles retain the configured dark dead-zone skybox.'
Assert (-not ($settings.cellPlanning.topologyVariants.templates['road-straight'] -contains 'roads/tile_road_night.vmf') -and
    -not ($settings.cellPlanning.topologyVariants.profileTemplates.military['road-straight'] -contains 'roads/tile_army_road_night.vmf')) 'Ordinary and army night-road tiles remain unselected until their profiles use the dark skybox.'
$expectedPatternSources = @(
    @($settings.cellPlanning.templatePatterns.destroyedBuildings, 'buildings/tile_skyscraper_destroyed_1a_2x.vmf'),
    @($settings.cellPlanning.templatePatterns.destroyedBuildings, 'buildings/tile_destroyed_1a.vmf'),
    @($settings.cellPlanning.templatePatterns.genericBuildings, 'buildings/tile_skyscraper_4aaa_2x.vmf'),
    @($settings.cellPlanning.templatePatterns.genericBuildings, 'buildings/tile_skyscraper_5aaa_2x.vmf'),
    @($settings.cellPlanning.templatePatterns.radioactiveBuildings, 'buildings/tile_skyscraper_ra_2a_2x.vmf'),
    @($settings.cellPlanning.templatePatterns.fortifiedBuildings, 'buildings/tile_fortified_1a.vmf'),
    @($settings.cellPlanning.templatePatterns.fortifiedBuildings, 'buildings/tile_fortified_1aa.vmf'),
    @($settings.cellPlanning.templatePatterns.fortifiedBuildings, 'buildings/tile_fortified_3aa.vmf'),
    @($settings.cellPlanning.templatePatterns.industry, 'buildings/tile_industrial_8a.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'decorations/tile_destroyed_debris_1a.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'decorations/tile_ra_bushes_1a.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'decorations/tile_industrial_containers_1a.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'decorations/tile_fortified_army_tent.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'decorations/tile_army_tent.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'decorations/tile_plaza_1a.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_fence_a_cap.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_fence_a_corner.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_fence_a_double.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_ra_fence_a_cap.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_ra_fence_a_corner.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_ra_fence_a_double.vmf'),
    @($settings.cellPlanning.templatePatterns.decorations, 'terrain/tile_ra_brush_1s.vmf')
)
foreach ($case in $expectedPatternSources) {
    Assert ($case[1] -match $case[0]) "Template pattern selects intended source $($case[1])."
}
Assert ($settings.cellPlanning.buildingSelection.fortifiedThemedChancePercent -eq 80) 'Fortified cells prefer compatible fortified buildings at the approved 80 percent rate.'
Assert ('buildings/tile_fortified_1a.vmf' -notmatch $settings.cellPlanning.templatePatterns.genericBuildings) 'Fortified buildings are not in the ordinary building pool.'
Assert ($settings.cellPlanning.terrainProfileTemplates.radioactive.grassland -ceq 'terrain/tile_ra_grass.vmf') 'Radioactive grass terrain is explicitly selectable.'
Assert ($settings.cellPlanning.terrainProfileTemplates.radioactive.sandy -ceq 'terrain/tile_ra_sand.vmf') 'Radioactive sand terrain is explicitly selectable.'
Assert ($settings.cellPlanning.terrainProfileTemplates.industrial.grassland -ceq 'terrain/tile_industrial_grass.vmf') 'Industrial grass terrain is explicitly selectable.'
Assert ($settings.cellPlanning.landmarkTemplatePatterns['Police'] -like '*/tile_police*.vmf') 'Police station variants remain available to the police landmark pool.'
Assert ($settings.cellPlanning.landmarkTemplatePatterns['Army Base'] -ceq 'buildings/tile_armybase_*.vmf') 'Army Base landmarks resolve the authored building, not the army scenery folder.'
Assert (@($settings.vmfBuild.outerEdges.profileTemplates.destroyed.wallVariationTemplates | Where-Object { $_ -match '(^|/)tile_edge_ra_' }).Count -eq 0) 'Destroyed outer walls do not reuse radioactive pieces.'
Assert (@($settings.vmfBuild.border.profileTemplates.destroyed.wallVariationTemplates | Where-Object { $_ -match '(^|/)tile_border_ra_' }).Count -eq 0) 'Destroyed border walls do not reuse radioactive pieces.'
foreach ($ring in @('border', 'outerEdges')) {
    $destroyed = $settings.vmfBuild[$ring].profileTemplates.destroyed
    foreach ($tier in $destroyed.wallDensityFallbacks.Keys) {
        Assert ($tier -in @('2', '3') -and $destroyed.wallDensityFallbacks[$tier] -in $destroyed.wallVariationTemplates) "Destroyed $ring tier-$tier fallback is an explicitly configured member of its wall pool."
    }
}
foreach ($template in @('edges/tile_edge_ra_wall_6aaa.vmf', 'edges/tile_edge_ra_wall_7aaa.vmf', 'edges/tile_edge_ra_wall_8aaa.vmf', 'edges/tile_edge_ra_wall_corner_1aaa.vmf')) {
    Assert (($settings.vmfBuild.outerEdges.profileTemplates.radioactive.wallVariationTemplates -contains $template) -or
        ($settings.vmfBuild.outerEdges.profileTemplates.radioactive.cornerVariationTemplates -contains $template)) "Radioactive outer-edge pool includes $template."
}
foreach ($template in @('edges/tile_edge_industrial_wall_3a.vmf', 'edges/tile_edge_industrial_wall_corner_1aaa.vmf')) {
    Assert (($settings.vmfBuild.outerEdges.profileTemplates.industrial.wallVariationTemplates -contains $template) -or
        ($settings.vmfBuild.outerEdges.profileTemplates.industrial.cornerVariationTemplates -contains $template)) "Industrial outer-edge pool includes $template."
}
Assert ($settings.vmfBuild.border.profileTemplates.industrial.wallVariationTemplates -contains 'border/tile_border_industrial_wall_3aaa.vmf') 'Industrial border pool includes its new high-tier wall.'
foreach ($template in @('border/tile_border_wall_4aa.vmf', 'border/tile_border_wall_5aa.vmf')) {
    Assert ($settings.vmfBuild.border.wallVariationTemplates -contains $template) "Generic border pool includes $template."
}
$anchorlessRoads = @(
    'roads/tile_army_road_a.vmf',
    'roads/tile_destroyed_road_a.vmf',
    'roads/tile_destroyed_road_c.vmf',
    'roads/tile_ra_road_b.vmf'
)
foreach ($template in $anchorlessRoads) {
    $path = Join-Path $templateRoot ($template.Replace('/', '\'))
    Assert ((Test-Path -LiteralPath $path -PathType Leaf) -and -not (Select-String -LiteralPath $path -Pattern 'zn_prefab_anchor' -Quiet)) "$template remains an authored anchorless road variant."
}
$configuredRoadVariants = [System.Collections.Generic.List[string]]::new()
foreach ($template in $settings.cellPlanning.topologyVariants.templates['road-straight']) {
    $configuredRoadVariants.Add([string]$template)
}
foreach ($profileName in $settings.cellPlanning.topologyVariants.profileTemplates.Keys) {
    foreach ($template in $settings.cellPlanning.topologyVariants.profileTemplates[$profileName]['road-straight']) {
        $configuredRoadVariants.Add([string]$template)
    }
}
foreach ($template in @($configuredRoadVariants | Sort-Object -Unique)) {
    $path = Join-Path $templateRoot ($template.Replace('/', '\'))
    $anchorCount = [regex]::Matches((Get-Content -Raw -LiteralPath $path), '"classname"\s+"zn_prefab_anchor"').Count
    $expectedAnchorCount = if ($template -in $anchorlessRoads) { 0 } else { 1 }
    Assert ($anchorCount -eq $expectedAnchorCount) "$template has the expected prefab-anchor count for its straight-road variant."
}
$nightRoadAnchorTags = @{
    'roads/tile_road_night.vmf' = 'road_carcrash'
    'roads/tile_ra_road_night.vmf' = 'roadRadiationHazard'
    'roads/tile_army_road_night.vmf' = 'roadArmy'
    'roads/tile_destroyed_road_night.vmf' = 'roadDestroyed'
}
foreach ($template in $nightRoadAnchorTags.Keys) {
    $path = Join-Path $templateRoot ($template.Replace('/', '\'))
    $source = Get-Content -Raw -LiteralPath $path
    Assert (([regex]::Matches($source, '"classname"\s+"zn_prefab_anchor"').Count -eq 1) -and
        ($source -match '"instance_local"\s+"1"') -and
        ($source -match ('"prefab_tags"\s+"' + [regex]::Escape($nightRoadAnchorTags[$template]) + '"')) -and
        ($source -match '"origin"\s+"0 0 44"')) "$template has one instance-local anchor at the canonical origin with its matching prefab tag."
}

$savedStraight = $settings.cellPlanning.topologyTemplates['motorway-straight']
$settings.cellPlanning.topologyTemplates['motorway-straight'] = 'roads/motorway_3x1/missing_required_source.vmf'
$missingSourceRejected = $false
try {
    Assert-ZMConfiguredTileTemplatePaths -Settings $settings -TemplateRoot $templateRoot | Out-Null
} catch {
    $missingSourceRejected = $_.Exception.Message -like '*cellPlanning.topologyTemplates.motorway-straight*missing_required_source.vmf*'
}
finally {
    $settings.cellPlanning.topologyTemplates['motorway-straight'] = $savedStraight
}
Assert $missingSourceRejected 'A missing explicit motorway source fails before placement with its setting path.'

$savedDeadEnd = $settings.cellPlanning.topologyTemplates['motorway-deadend']
$settings.cellPlanning.topologyTemplates.Remove('motorway-deadend') | Out-Null
$missingTopologyRejected = $false
try {
    Assert-ZMRequiredMotorwayTemplateSettings -Settings $settings
} catch {
    $missingTopologyRejected = $_.Exception.Message -like '*motorway-deadend*'
}
finally {
    $settings.cellPlanning.topologyTemplates['motorway-deadend'] = $savedDeadEnd
}
Assert $missingTopologyRejected 'A missing required motorway topology key fails explicitly.'

$testRoot = Join-Path (Join-Path $projectRoot 'generated') ('phase_d_template_preflight_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$plannerSettingsPath = Join-Path $testRoot 'settings.json'
$plannerMapPath = Join-Path $testsBinDirectory 'preview_grid_24x24_seed_1337.json'
$plannerOutputPath = Join-Path $testRoot 'plan.json'
$plannerListPath = Join-Path $testRoot 'required.txt'
$plannerCellDirectory = Join-Path $testRoot 'src'
$savedStraight = $settings.cellPlanning.topologyTemplates['motorway-straight']
$settings.cellPlanning.topologyTemplates['motorway-straight'] = 'roads/motorway_3x1/missing_required_source.vmf'
$plannerRejected = $false
try {
    [IO.File]::WriteAllText($plannerSettingsPath, ($settings | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    try {
        & (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $plannerSettingsPath -MapData $plannerMapPath -CellDirectory $plannerCellDirectory -Output $plannerOutputPath -ListOutput $plannerListPath *> $null
    } catch {
        $plannerRejected = $_.Exception.Message -like '*cellPlanning.topologyTemplates.motorway-straight*missing_required_source.vmf*'
    }
}
finally {
    $settings.cellPlanning.topologyTemplates['motorway-straight'] = $savedStraight
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
Assert $plannerRejected 'The planner rejects a missing motorway source before writing or placing the recipe.'
Assert (-not (Test-Path -LiteralPath $plannerOutputPath) -and -not (Test-Path -LiteralPath $plannerCellDirectory)) 'Failed preflight leaves no plan or placement directory.'

Write-Output "Template inventory: $passed assertions passed; $referenceCount explicit tile paths validated."
