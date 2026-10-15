param(
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [string]$MapData = '',
    [switch]$Complex,
    [switch]$Mixed,
    [switch]$SizedInfill,
    [switch]$CompleteInfill,
    [switch]$NormalPlanOnly,
    [switch]$Normal,
    [switch]$NormalComplex,
    [switch]$SkipInfill,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($NormalComplex -and ($Mixed -or $Complex -or $Normal -or $NormalPlanOnly -or $SizedInfill -or $CompleteInfill)) { throw 'NormalComplex is a standalone normal-generator mode with its own complete infill pass.' }
if ($Mixed) { $Complex = $true; $CompleteInfill = $true }
if ($Normal -and ($NormalPlanOnly -or $Complex -or $SizedInfill -or $CompleteInfill)) { throw 'Normal emission currently covers the two plain straight recipes without inspection or infill modes.' }
if ($NormalPlanOnly -and ($Complex -or $SizedInfill -or $CompleteInfill)) { throw 'Normal plan-only checks currently cover plain straights without inspection or infill modes.' }
if ($SizedInfill -and -not $Complex) { throw 'Sized ground patches require complex inspection cells.' }
if ($CompleteInfill -and -not $Complex) { throw 'Complete ground infill requires complex inspection cells.' }
if ($CompleteInfill) { $SizedInfill = $true }
Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
if ($profile.Name -ne 'preview') { throw 'Motorway cell inspection is preview-only.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root $(if ($NormalComplex) { 'generated\phase_f_normal_complex_cells' } elseif ($Mixed) { 'generated\phase_e_mixed_cells' } elseif ($NormalPlanOnly -or $Normal) { 'generated\phase_e_normal_straight' } elseif ($CompleteInfill) { 'generated\phase_b_power2_infill_cells' } elseif ($Complex) { 'generated\phase_b_complex_cells' } else { 'generated\phase_b_motorway_cells' }) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$generatedRoot = [IO.Path]::GetFullPath((Join-Path $root 'generated')).TrimEnd('\') + '\'
if (-not $OutputDirectory.StartsWith($generatedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Motorway cell outputs must remain below generated.' }
if ([string]::IsNullOrWhiteSpace($MapData)) {
    $MapData = Join-Path $root 'generated\preview_variety_tuned_20261012\preview_grid_24x24_seed_1337.json'
}
if (-not (Test-Path -LiteralPath $MapData -PathType Leaf)) { throw 'Current matching preview manifest required; pass -MapData explicitly.' }
$sourceHash = (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash
$manifest = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
if ($manifest.map.gridCells -ne 24 -or $manifest.map.seed -ne 1337) { throw 'Cell inspection expects the approved 24x24 seed1337 preview manifest.' }
$targets = if ($NormalComplex) { @() } elseif ($Mixed) { @(
    [pscustomobject]@{ x = 17; y = 0; label = 'deadend_s_bridge'; syntheticT = $false },
    [pscustomobject]@{ x = 13; y = 18; label = 'corner_ne_ramp_s'; syntheticT = $false },
    [pscustomobject]@{ x = 6; y = 23; label = 'deadend_n_ramp_e'; syntheticT = $false },
    [pscustomobject]@{ x = 15; y = 23; label = 'deadend_n_bridge'; syntheticT = $false }
) } elseif ($Complex) { @(
    [pscustomobject]@{ x = 15; y = 14; label = 'corner'; syntheticT = $false },
    [pscustomobject]@{ x = 6; y = 7; label = 'crossroads'; syntheticT = $false },
    [pscustomobject]@{ x = 15; y = 18; label = 'tjunction_fixture'; syntheticT = $true },
    [pscustomobject]@{ x = 6; y = 0; label = 'deadend'; syntheticT = $false },
    [pscustomobject]@{ x = 17; y = 2; label = 'bridge'; syntheticT = $false },
    [pscustomobject]@{ x = 6; y = 3; label = 'single_ramp'; syntheticT = $false },
    [pscustomobject]@{ x = 17; y = 4; label = 'dual_ramp'; syntheticT = $false }
) } else { @(
    [pscustomobject]@{ x = 6; y = 1; orientation = 'vertical' },
    [pscustomobject]@{ x = 2; y = 7; orientation = 'horizontal' }
) }
$cells = @(foreach ($target in $targets) {
    $matches = @($manifest.cells | Where-Object { $_.x -eq $target.x -and $_.y -eq $target.y })
    if ($matches.Count -ne 1) { throw "Missing/duplicate inspection cell $($target.x),$($target.y)." }
    $cell = $matches[0]
    if ($Complex) {
        if (-not $cell.highway.present -or $null -ne $cell.safeZone -or @($cell.landmarks).Count -gt 0) { throw "Complex inspection target $($target.label) changed." }
        if ($target.syntheticT) {
            $cell.highway.connections = @('N', 'E', 'W')
            $cell.highway.degree = 3
            $cell.road.connections = @('N', 'E', 'W')
            $cell.road.degree = 3
            $cell | Add-Member -NotePropertyName inspectionFixtureChange -NotePropertyValue 'Explicit T-junction fixture derived from a crossroads; no T-junction exists in current preview world. Source world/neighbor graph unchanged.'
        }
        $cell
        continue
    }
    $expected = if ($target.orientation -eq 'vertical') { 'N,S' } else { 'E,W' }
    if (-not $cell.highway.present -or (@($cell.highway.connections | Sort-Object) -join ',') -ne $expected -or
        $cell.highway.bridge -or @($cell.highway.rampExits).Count -gt 0 -or $null -ne $cell.safeZone -or @($cell.landmarks).Count -gt 0) {
        throw "Inspection target $($target.x),$($target.y) no longer matches the intended plain straight motorway."
    }
    $cell
})
if ($NormalComplex) {
    $cells = @($manifest.cells | Where-Object {
        $_.highway.present -and $null -eq $_.safeZone -and -not (((@($_.highway.connections | Sort-Object) -join ',') -in @('N,S', 'E,W')) -and -not $_.highway.bridge -and @($_.highway.rampExits).Count -eq 0)
    })
    if ($cells.Count -eq 0) { throw 'No complex motorway cells found in the manifest.' }
}
$manifest.cells = $cells
$manifest.safeZones = @()
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$settings = $profile.Settings
$settings.vmfBuild.outerEdges.enabled = $true
$templateRoot = Join-Path $root $settings.paths.templateDirectory
# Only the intermediate old-axis plan uses these retained sources. The inspection pass replaces its full corridor.
$legacyMotorwayTopologies = @{
    'motorway-straight' = 'roads/motorway_1x1/tile_motorway.vmf'
    'motorway-corner' = 'roads/motorway_1x1/tile_motorway_corner.vmf'
    'motorway-tjunction' = 'roads/motorway_1x1/tile_motorway_tjunction.vmf'
    'motorway-crossjunction' = 'roads/motorway_1x1/tile_motorway_crossroads.vmf'
    'motorway-deadend' = 'roads/motorway_1x1/tile_motorway_deadend.vmf'
}
$legacyMotorwayTransports = @{
    'bridge' = 'roads/motorway_1x1/tile_motorway_road_bridge.vmf'
    'onramp' = 'roads/motorway_1x1/tile_motorway_onramp.vmf'
    'onramp-dual' = 'roads/motorway_1x1/tile_motorway_onramp_dual.vmf'
}
if (-not $NormalPlanOnly -and -not $Normal -and -not $NormalComplex) {
foreach ($key in $legacyMotorwayTopologies.Keys) {
    if (-not $settings.cellPlanning.topologyTemplates.ContainsKey($key)) {
        throw "Inspection settings are missing required topology '$key'."
    }
    $settings.cellPlanning.topologyTemplates[$key] = $legacyMotorwayTopologies[$key]
}
foreach ($key in $legacyMotorwayTransports.Keys) {
    if (-not $settings.cellPlanning.transportTemplates.ContainsKey($key)) {
        throw "Inspection settings are missing required transport '$key'."
    }
    $settings.cellPlanning.transportTemplates[$key] = $legacyMotorwayTransports[$key]
}
if (-not $settings.cellPlanning.topologyVariants.templates.ContainsKey('motorway-straight')) {
    $settings.cellPlanning.topologyVariants.templates['motorway-straight'] = @(
        'roads/motorway_1x1/tile_motorway_a.vmf',
        'roads/motorway_1x1/tile_motorway_b.vmf',
        'roads/motorway_1x1/tile_motorway_c.vmf'
    )
}
Write-Host 'Cell inspection settings only: explicitly mapped to retained 1x1 sources; root settings and existing authored assets unchanged.'
}
foreach ($path in @($settings.cellPlanning.topologyTemplates.Values) + @($settings.cellPlanning.transportTemplates.Values) + @($settings.vmfBuild.border.cornerTemplate)) {
    if (-not (Test-Path -LiteralPath (Join-Path $templateRoot $path) -PathType Leaf)) { throw "Isolated cell settings source missing: $path" }
}
$isolatedSettings = Join-Path $OutputDirectory 'settings.json'
$fixtureMap = Join-Path $OutputDirectory 'fixture-map.json'
$planPath = Join-Path $OutputDirectory 'plan.json'
$listPath = Join-Path $OutputDirectory 'required.txt'
$src = Join-Path $OutputDirectory 'src'
$skybox = Join-Path $OutputDirectory 'skybox'
Write-TextFileIfChanged -Path $isolatedSettings -Content ($settings | ConvertTo-Json -Depth 100) | Out-Null
Write-TextFileIfChanged -Path $fixtureMap -Content ($manifest | ConvertTo-Json -Depth 30) | Out-Null
$assemblyReport = ''
if ($Mixed) {
    & (Join-Path $PSScriptRoot 'create_road_connector_template.ps1') -WorldProfile preview -SettingsPath $isolatedSettings
    if (-not $?) { throw 'Approved extended road connector initialization failed.' }
}
if ($Complex -or $NormalComplex) {
    & (Join-Path $PSScriptRoot 'build_motorway_preview.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -OutputDirectory (Join-Path $OutputDirectory 'measured-assemblies') | Out-Null
    if (-not $?) { throw 'Measured assembly report generation failed.' }
    $assemblyReport = Join-Path $OutputDirectory 'measured-assemblies\assembly-report.json'
}
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -MapData $fixtureMap -CellDirectory $src -Output $planPath -ListOutput $listPath -MotorwayCellInspection:(!$NormalPlanOnly -and !$Normal -and !$NormalComplex) -MotorwayAssemblyReport $assemblyReport | Out-Null
if (-not $?) { throw 'Motorway inspection cell planner failed.' }
if ($NormalPlanOnly) {
    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
    if ($sourceHash -cne (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash) { throw 'Source manifest changed during normal planning.' }
    foreach ($cell in $plan.cells) {
        if ($null -ne $cell.PSObject.Properties['motorwayCellInspection'] -or
            $cell.motorwayAssembly.status -ne 'normal_reservations_travel_pending' -or
            $cell.motorwayAssembly.leases.Count -ne 27 -or $cell.motorwayAssembly.ringPlacements.Count -ne 4) {
            throw 'Normal plan-only output must own all straight core/ring leases without inspection metadata.'
        }
        [pscustomobject]@{
            gridX = $cell.x; gridY = $cell.y; orientation = $cell.orientation
            recipe = $cell.cellTemplateFilename; leases = $cell.motorwayAssembly.leases.Count
            ringOwners = $cell.motorwayAssembly.ringPlacements.Count; status = $cell.motorwayAssembly.status
        }
    }
    return
}
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -PlanData $planPath -CellDirectory $src -SkyboxOutputDirectory $skybox -RefreshGenerated -MotorwayCellInspection:(!$Normal -and !$NormalComplex) -MeasureCompleteTerrainInfill:($CompleteInfill -or ($NormalComplex -and -not $SkipInfill)) | Out-Null
if (-not $?) { throw 'Motorway inspection cell builder failed.' }
if ($NormalComplex) {
    if (-not $SkipInfill) {
    & (Join-Path $PSScriptRoot 'create_terrain_infill_templates.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -PartialGapLayoutDirectory $src -CompletePatches | Out-Null
    if (-not $?) { throw 'Normal complex ground base creation failed.' }
    & (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -PlanData $planPath -CellDirectory $src -SkyboxOutputDirectory $skybox -RefreshGenerated -SizedTerrainInfill -CompleteTerrainInfill | Out-Null
    if (-not $?) { throw 'Normal complex infill rebuild failed.' }
    }
    if ($sourceHash -cne (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash) { throw 'Source manifest changed during normal complex emission.' }
    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
    foreach ($cell in $plan.cells) {
        if ($null -ne $cell.PSObject.Properties['motorwayCellInspection']) { throw 'Normal complex recipes must not carry inspection metadata.' }
        $contract = $cell.PSObject.Properties['motorwayAssembly']
        [pscustomobject]@{ gridX = $cell.x; gridY = $cell.y; topology = $cell.topology; feature = $cell.transportFeature; vmf = Join-Path $src $cell.cellTemplateFilename; status = $(if ($contract) { $contract.Value.status } else { 'none' }) }
    }
    return
}
if ($Normal) {
    if ($sourceHash -cne (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash) { throw 'Source manifest changed during normal emission.' }
    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
    foreach ($cell in $plan.cells) {
        if ($null -ne $cell.PSObject.Properties['motorwayCellInspection']) { throw 'Normal emitted recipes must not carry inspection metadata.' }
        [pscustomobject]@{ orientation = $cell.orientation; vmf = $cell.cellTemplatePath; gates = $cell.motorwayAssembly.gates.Count; status = 'normal_emitted_not_compiled_or_live' }
    }
    return
}
if ($SizedInfill) {
    & (Join-Path $PSScriptRoot 'create_terrain_infill_templates.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -PartialGapLayoutDirectory $src -CompletePatches:$CompleteInfill | Out-Null
    if (-not $?) { throw 'Editable sized ground base creation failed.' }
    & (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $isolatedSettings -PlanData $planPath -CellDirectory $src -SkyboxOutputDirectory $skybox -RefreshGenerated -MotorwayCellInspection -SizedTerrainInfill -CompleteTerrainInfill:$CompleteInfill | Out-Null
    if (-not $?) { throw 'Sized ground inspection cell builder failed.' }
}
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
if ($sourceHash -cne (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash) { throw 'Source manifest changed during cell inspection generation.' }
$report = [ordered]@{
    schemaVersion = 1; status = 'complete_cell_geometry_inspection_not_live_travel'
    sourceManifest = [IO.Path]::GetFullPath($MapData); sourceManifestSha256 = $sourceHash
    settings = $isolatedSettings; plan = $planPath
    cells = @($plan.cells | ForEach-Object {
        [ordered]@{
            gridX = $_.x; gridY = $_.y; worldX = $_.worldX; worldY = $_.worldY
            orientation = $_.orientation; topology = $_.topology; transportFeature = $_.transportFeature
            vmf = Join-Path $src $_.cellTemplateFilename
            sourceSha256 = $_.motorwayCellInspection.sourceSha256
            coreSlots = $_.tilePlacements.Count
            corridorLeases = $_.motorwayCellInspection.leases.Count
            ringOwners = $(if ($Complex) { $null } else { $_.motorwayCellInspection.ringPlacements.Count })
            status = $_.motorwayCellInspection.status
        }
    })
    fixtureChanges = @($cells | Where-Object { $null -ne $_.PSObject.Properties['inspectionFixtureChange'] } | ForEach-Object { $_.inspectionFixtureChange })
    limits = @('Complete normal cell shell/scenery/rings/skybox with planned transport, not an asset zoo.', 'Complex mode is explicitly diagnostic: seams, ordinary-road approaches and partial boundary tiles are unapproved.', 'Legacy narrow gates/blockers not emitted; not staged or live-travel-ready.', 'No world-wide regeneration, BSP compilation or publication.')
}
Write-TextFileIfChanged -Path (Join-Path $OutputDirectory 'cell-report.json') -Content ($report | ConvertTo-Json -Depth 12) | Out-Null
$report.cells | ForEach-Object { [pscustomobject]$_ }
