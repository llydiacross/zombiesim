Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'template_inventory.psm1') -Force
$projectRoot = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
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
$plannerMapPath = Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json'
$plannerOutputPath = Join-Path $testRoot 'plan.json'
$plannerListPath = Join-Path $testRoot 'required.txt'
$plannerCellDirectory = Join-Path $testRoot 'src'
$savedStraight = $settings.cellPlanning.topologyTemplates['motorway-straight']
$settings.cellPlanning.topologyTemplates['motorway-straight'] = 'roads/motorway_3x1/missing_required_source.vmf'
$plannerRejected = $false
try {
    [IO.File]::WriteAllText($plannerSettingsPath, ($settings | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    try {
        & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $plannerSettingsPath -MapData $plannerMapPath -CellDirectory $plannerCellDirectory -Output $plannerOutputPath -ListOutput $plannerListPath *> $null
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
