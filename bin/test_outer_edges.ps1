param([string]$OutputRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $projectRoot 'generated\outer_edges' }
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
[System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
Import-Module (Join-Path $PSScriptRoot 'cell_bounds.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'outer_edges.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$script:passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Outer edges: $Message" }
    $script:passed++
}

$resolved = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$settings = $resolved.Settings
$settings.vmfBuild.outerEdges.enabled = $true
$settingsPath = Join-Path $OutputRoot 'settings.json'
[IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
$edgeSettings = $settings.vmfBuild.outerEdges
$fixedProps = @{
    'tile_edge_army_none.vmf' = 5
    'tile_edge_ra_none.vmf' = 7
    'tile_edge_ra_wall_1a.vmf' = 1
    'tile_edge_ra_wall_1aa.vmf' = 2
}
foreach ($filename in $fixedProps.Keys) {
    $root = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -Raw -LiteralPath (Join-Path $projectRoot "tiletemplates\edges\$filename")))
    $props = @($root.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'prop_dynamic_override' })
    Assert ($props.Count -eq $fixedProps[$filename]) "$filename retains all approved fixed dynamic trees/signs."
    Assert (@($root.Children | Where-Object { $_.Get('classname') -eq 'prop_static' -and $_.Get('model') -match 'tree[13]_trunk|signpole001|streetsign004e' }).Count -eq 0) 'VBSP-incompatible new-edge static props must not reappear.'
}
$bounds = Get-ZMCellBounds 5 640 $true
Assert ($bounds.coreHalfExtent -eq 1600 -and $bounds.traversableHalfExtent -eq 2240 -and $bounds.visualHalfExtent -eq 2880 -and $bounds.neighbourPitch -eq 5760) 'Exact 5/7/9-tile extents and pitch.'
Assert ((Get-ZMCellBounds 5 640 $false).neighbourPitch -eq 4480) 'Legacy pitch must remain unchanged.'
$border = @(
    for ($y = -1; $y -le 5; $y++) {
        for ($x = -1; $x -le 5; $x++) {
            if ($x -in @(-1, 5) -or $y -in @(-1, 5)) { [pscustomobject]@{ tileX = $x; tileY = $y } }
        }
    }
)
$recipe = [pscustomobject]@{ environmentProfile = 'grassland'; placementSeed = 1337 }
$land = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{})
Assert ($land.Count -eq 32) 'Full outer ring must contain 32 slots.'
Assert (@($land | Where-Object { $_.tileX -gt -2 -and $_.tileX -lt 6 -and $_.tileY -gt -2 -and $_.tileY -lt 6 }).Count -eq 0) 'Only outer perimeter slots may be emitted.'
Assert (@($land | Group-Object { "$($_.tileX),$($_.tileY)" } | Where-Object Count -ne 1).Count -eq 0) 'Outer slots must be unique.'
$yawCases = @(@(-2, 2, 270), @(6, 2, 90), @(2, -2, 180), @(2, 6, 0), @(-2, -2, 180), @(6, -2, 90), @(6, 6, 0), @(-2, 6, 270))
foreach ($case in $yawCases) {
    $piece = @($land | Where-Object { $_.tileX -eq $case[0] -and $_.tileY -eq $case[1] })
    Assert ($piece.Count -eq 1 -and $piece[0].rotationYaw -eq $case[2]) "Facing $($case[0]),$($case[1])."
}
$second = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{})
Assert (($land | ConvertTo-Json -Depth 5) -ceq ($second | ConvertTo-Json -Depth 5)) 'Placement must be deterministic.'
foreach ($profile in @('radioactive', 'military', 'fortified')) {
    $recipe.environmentProfile = $profile
    $pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{})
    $pool = @($edgeSettings.profileTemplates[$profile].wallVariationTemplates)
    foreach ($piece in $pieces) {
        Assert ($(if ($piece.targetname -like 'zm_outer_corner_*') { $piece.template -eq $edgeSettings.cornerTemplate } else { $piece.template -in $pool })) "$profile replaces the straight pool, with independent default corner fallback."
    }
}
$recipe.environmentProfile = 'grassland'
foreach ($mask in 0..15) {
    $water = @{}
    $sides = @('N', 'E', 'S', 'W')
    for ($i = 0; $i -lt 4; $i++) { if ($mask -band (1 -shl $i)) { $water[$sides[$i]] = $true } }
    $pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border $water @{})
    foreach ($piece in $pieces) {
        Assert (-not (($piece.tileY -eq -2 -and $water.ContainsKey('N')) -or ($piece.tileX -eq 6 -and $water.ContainsKey('E')) -or ($piece.tileY -eq 6 -and $water.ContainsKey('S')) -or ($piece.tileX -eq -2 -and $water.ContainsKey('W')))) "Water mask $mask must omit side fill and mixed corners."
    }
    $expected = @($land | Where-Object {
        -not (($_.tileY -eq -2 -and $water.ContainsKey('N')) -or ($_.tileX -eq 6 -and $water.ContainsKey('E')) -or ($_.tileY -eq 6 -and $water.ContainsKey('S')) -or ($_.tileX -eq -2 -and $water.ContainsKey('W')))
    }).Count
    Assert ($pieces.Count -eq $expected) "Water mask $mask exact count."
}
$corridor = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{ N = $true; W = $true } @{ N = 'roads\tile_road_straight.vmf' })
Assert (@($corridor | Where-Object { $_.tileY -eq -2 }).Count -eq 1 -and @($corridor | Where-Object { $_.tileY -eq -2 })[0].tileX -eq 2) 'Only a reserved centre corridor may continue across a waterfront side.'
$suppressed = @($border | Where-Object { -not ($_.tileY -eq -1 -and $_.tileX -eq 2) })
$pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $suppressed @{} @{ N = 'road.vmf' })
Assert (@($pieces | Where-Object { $_.tileY -eq -2 -and $_.tileX -eq 2 }).Count -eq 0) 'Entrance suppression precedes route reservation.'

$source = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'celltemplates\template_border_s.vmf')
$expanded = Expand-ZMOuterEdgeShell $source $bounds
$parsed = [ZombieSim.Skybox.KeyValuesParser]::Parse($expanded)
Assert ($null -ne $parsed.Child('cameras')) 'Expanded shell retains editor sections.'
foreach ($solid in $parsed.Child('world').Children | Where-Object Name -eq 'solid') {
    $material = ($solid.Children | Where-Object Name -eq 'side' | Select-Object -First 1).Get('material').ToUpperInvariant()
    $vertices = @($solid.Children | Where-Object Name -eq 'side' | ForEach-Object { $_.Child('vertices_plus').GetAll('v') })
    $axes = @()
    foreach ($axis in 0..1) { $axes += ,@($vertices | ForEach-Object { [double]($_ -split '\s+')[$axis] } | Sort-Object -Unique) }
    if ($material -eq 'TOOLS/TOOLSCLIP') {
        foreach ($axis in $axes) { foreach ($value in $axis) { Assert ([Math]::Abs($value) -in @(2240, 2304)) 'Clip perimeter must release the existing border and exclude the new scenery ring.' } }
    } elseif ($material -eq 'TOOLS/TOOLSSKYBOX') {
        foreach ($axis in $axes) { foreach ($value in $axis) { Assert ([Math]::Abs($value) -in @(3072, 3136)) 'Sky seals must contain approved brush overhangs beyond the 2880 visual bound.' } }
    }
}

$planPath = Join-Path $OutputRoot 'plan.json'
$listPath = Join-Path $OutputRoot 'required.txt'
$cellDirectory = Join-Path $OutputRoot 'src'
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData (Join-Path $PSScriptRoot 'border_showcase_fixture_map.json') -CellDirectory $cellDirectory -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Expanded fixture planner failed.' }
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
Assert (@($plan.cells | Where-Object { $_.x -eq 0 -and (@($_.skyboxOceanSides) -join ',') -ne 'W' }).Count -eq 0) 'West boundary cells omit only the skybox ocean side.'
Assert (@($plan.cells | Where-Object { $_.x -gt 0 -and @($_.skyboxOceanSides).Count -gt 0 }).Count -eq 0) 'Authored water corners do not change outer-edge omission policy.'
Assert (@($plan.cells | Where-Object { $_.cellTemplateFilename -notlike '*-edge2.vmf' }).Count -eq 0) 'Expanded maps must have a distinct geometry revision identity.'
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -CellDirectory $cellDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Expanded fixture builder failed.' }
foreach ($group in $plan.cells | Group-Object cellTemplateFilename) {
    $vmfPath = Join-Path $cellDirectory $group.Name
    $layout = Get-Content -Raw -LiteralPath ([IO.Path]::ChangeExtension($vmfPath, '.layout.json')) | ConvertFrom-Json
    $cell = $group.Group[0]
    $text = Get-Content -Raw -LiteralPath $vmfPath
    Assert ($layout.vmfSha256 -eq (Get-FileHash -LiteralPath $vmfPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'Layout must identify the exact current VMF.'
    Assert ([regex]::Matches($text, '"targetname" "zm_outer_').Count -eq @($layout.outerPlacements).Count) 'VMF and artwork placement metadata must agree.'
    Assert ([regex]::Matches($text, '"targetname" "(?:zm_border_|zm_transition_road_)').Count -eq @($layout.borderPlacements).Count) 'Original border remains independent of outer-ring count.'
    Assert ([regex]::Matches($text, '"zm_transition_gate" "1"').Count -eq @($cell.activeEntrances).Count) 'Phase A must not duplicate or remove travel gates.'
}
$before = @{}
foreach ($path in Get-ChildItem -LiteralPath $cellDirectory -Filter '*.vmf') { $before[$path.Name] = $path.LastWriteTimeUtc }
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -CellDirectory $cellDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Incremental expanded fixture builder failed.' }
foreach ($path in Get-ChildItem -LiteralPath $cellDirectory -Filter '*.vmf') { Assert ($path.LastWriteTimeUtc -eq $before[$path.Name]) 'Unchanged recipes must retain timestamps.' }

$runtimePath = Join-Path $OutputRoot 'runtime.json'
$runtimeMap = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json') | ConvertFrom-Json
$runtimeMap.cells = @($runtimeMap.cells | Where-Object { $_.x -lt 6 -and $_.y -ge 9 -and $_.y -lt 15 })
$runtimeMap.safeZones = @($runtimeMap.safeZones | Where-Object { $_.x -lt 6 -and $_.y -ge 9 -and $_.y -lt 15 })
foreach ($cell in $runtimeMap.cells) {
    $cell.y -= 9
    $cell.metro.lines = @()
    $cell.metro.stop = $null
    foreach ($neighbor in $cell.neighbors) {
        $neighbor.y -= 9
        $neighbor.inBounds = $neighbor.x -ge 0 -and $neighbor.x -lt 6 -and $neighbor.y -ge 0 -and $neighbor.y -lt 6
        if (-not $neighbor.inBounds) { $neighbor.roadConnected = $false; $neighbor.highwayConnected = $false }
    }
    $inside = @($cell.neighbors | Where-Object inBounds | ForEach-Object { $_.direction })
    $cell.road.connections = @($cell.road.connections | Where-Object { $_ -in $inside })
    $cell.road.degree = $cell.road.connections.Count
    $cell.highway.connections = @($cell.highway.connections | Where-Object { $_ -in $inside })
    $cell.highway.degree = $cell.highway.connections.Count
}
foreach ($zone in $runtimeMap.safeZones) { $zone.y -= 9 }
$runtimeMap.map.gridCells = 6
$runtimeMap.map.width = 384
$runtimeMap.map.height = 384
$runtimeMap.map.origin.cellY = 3
$runtimeMapPath = Join-Path $OutputRoot 'runtime-map.json'
$runtimePlanPath = Join-Path $OutputRoot 'runtime-plan.json'
$runtimeSources = Join-Path $OutputRoot 'runtime-src'
[IO.File]::WriteAllText($runtimeMapPath, ($runtimeMap | ConvertTo-Json -Depth 60), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $runtimeMapPath -CellDirectory $runtimeSources -Output $runtimePlanPath -ListOutput (Join-Path $OutputRoot 'runtime-required.txt') | Out-Null
if (-not $?) { throw 'Isolated origin fixture planning failed.' }
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $runtimePlanPath -CellDirectory $runtimeSources -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Isolated origin fixture generation failed.' }
& (Join-Path $PSScriptRoot 'export_runtime_world_data.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $runtimeMapPath -PlanData $runtimePlanPath -Output $runtimePath | Out-Null
if (-not $?) { throw 'Expanded runtime metadata export failed.' }
$runtime = Get-Content -Raw -LiteralPath $runtimePath | ConvertFrom-Json
Assert ($runtime.world.cellBounds.neighbourPitch -eq 5760 -and $runtime.world.cellBounds.coreHalfExtent -eq 1600) 'Runtime distinguishes visual pitch from core eligibility.'
Assert (@($runtime.cells | Where-Object { $null -eq $_.PSObject.Properties['waterSides'] }).Count -eq 0) 'Runtime explicitly retains per-cell coast classification.'

# Exercise protected real-world recipes without touching their installed outputs.
$coverageDirectory = Join-Path $OutputRoot 'coverage'
$coveragePlanPath = Join-Path $OutputRoot 'coverage-plan.json'
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData (Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json') -CellDirectory $coverageDirectory -Output $coveragePlanPath -ListOutput (Join-Path $OutputRoot 'coverage-required.txt') | Out-Null
if (-not $?) { throw 'Expanded protected recipe planning failed.' }
$coveragePlan = Get-Content -Raw -LiteralPath $coveragePlanPath | ConvertFrom-Json
$legacyPlanPath = Join-Path $OutputRoot 'legacy-plan.json'
$legacyDirectory = Join-Path $OutputRoot 'legacy-src'
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData (Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json') -CellDirectory $legacyDirectory -Output $legacyPlanPath -ListOutput (Join-Path $OutputRoot 'legacy-required.txt') | Out-Null
if (-not $?) { throw 'Legacy border comparison planning failed.' }
$legacyPlan = Get-Content -Raw $legacyPlanPath | ConvertFrom-Json
Assert ($legacyPlan.requiredCellCount -eq 179) 'Installed legacy recipe policy remains 179 recipes.'
$legacyByCoordinate = @{}
foreach ($legacyCell in $legacyPlan.cells) { $legacyByCoordinate["$($legacyCell.x),$($legacyCell.y)"] = $legacyCell }
foreach ($cell in $coveragePlan.cells) {
    $legacyCell = $legacyByCoordinate["$($cell.x),$($cell.y)"]
    Assert (($cell.cellTemplateFilename -replace '(?:-oceanw)?-edge2\.vmf$', '.vmf') -ceq $legacyCell.cellTemplateFilename) 'Ocean variants preserve original core/border recipe identity.'
}
$selected = @($coveragePlan.cells | Where-Object {
    $_.safeZoneEntrance -ne $null -or $_.environmentProfile -in @('radioactive', 'fortified') -or $_.transportFeature -eq 'bridge-horizontal'
} | Group-Object { if ($_.safeZoneEntrance) { "entrance-$($_.safeZoneEntrance.mode)" } elseif ($_.transportFeature -eq 'bridge-horizontal') { 'bridge' } else { $_.environmentProfile } } | ForEach-Object { $_.Group[0] })
$storm = @($coveragePlan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 12 })
$selected = @(@($selected) + $storm | Group-Object cellTemplateFilename | ForEach-Object { $_.Group[0] })
$coveragePlan.cells = $selected
$coveragePlan.safeZoneMaps = @()
[IO.File]::WriteAllText($coveragePlanPath, ($coveragePlan | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'coverage-required.txt'), [string[]]@($selected | ForEach-Object { $_.cellTemplateFilename }), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $coveragePlanPath -CellDirectory $coverageDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Protected expanded recipe builder failed.' }
foreach ($cell in $selected) {
    $layout = Get-Content -Raw -LiteralPath (Join-Path $coverageDirectory ([IO.Path]::ChangeExtension($cell.cellTemplateFilename, '.layout.json'))) | ConvertFrom-Json
    Assert (@($layout.borderPlacements).Count -eq 24 - @($cell.suppressedBorderTiles).Count) 'Protected entrance border suppression remains unchanged.'
    Assert (($layout.corePlacements | ConvertTo-Json -Depth 15) -ceq ($cell.tilePlacements | ConvertTo-Json -Depth 15)) 'Core assignments, IDs, yaw and frontage remain byte-equivalent in placement metadata.'
}
$legacyStorm = @($legacyPlan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 12 })
Assert ($legacyStorm.Count -eq 1 -and $storm.Count -eq 1) 'Exact Storm Drain 0,12 exists in both policies.'
$legacyPlan.cells = $legacyStorm
$legacyPlan.safeZoneMaps = @()
[IO.File]::WriteAllText($legacyPlanPath, ($legacyPlan | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -PlanData $legacyPlanPath -CellDirectory $legacyDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'legacy-skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Legacy Storm Drain fixture generation failed.' }
$oldLayout = Get-Content -Raw (Join-Path $legacyDirectory ([IO.Path]::ChangeExtension($legacyStorm[0].cellTemplateFilename, '.layout.json'))) | ConvertFrom-Json
$newLayout = Get-Content -Raw (Join-Path $coverageDirectory ([IO.Path]::ChangeExtension($storm[0].cellTemplateFilename, '.layout.json'))) | ConvertFrom-Json
Assert (($oldLayout.borderPlacements | ConvertTo-Json -Depth 15) -ceq ($newLayout.borderPlacements | ConvertTo-Json -Depth 15)) 'Storm Drain retains every previous border template, tile, yaw, target and offset.'
Assert (($oldLayout.corePlacements | ConvertTo-Json -Depth 15) -ceq ($newLayout.corePlacements | ConvertTo-Json -Depth 15)) 'Storm Drain core and entrance assignments are unchanged.'
Assert ((@($newLayout.waterSides) -join ',') -ceq 'W') 'Storm Drain coast attaches west at the original border.'
Assert (@($newLayout.outerPlacements | Where-Object tileX -eq -2).Count -eq 0) 'Storm Drain has no outer layer on the west ocean side, including NW/SW corners.'
$oldInstances = [ZombieSim.Skybox.CellModelBuilder]::ReadInstances((Join-Path $legacyDirectory $legacyStorm[0].cellTemplateFilename))
$newInstances = [ZombieSim.Skybox.CellModelBuilder]::ReadInstances((Join-Path $coverageDirectory $storm[0].cellTemplateFilename))
foreach ($instance in $oldInstances | Where-Object { [IO.Path]::GetFileName($_.File) -ne 'skybox_room.vmf' }) {
    $matches = @($newInstances | Where-Object {
        $_.File -eq $instance.File -and $_.Origin.X -eq $instance.Origin.X -and $_.Origin.Y -eq $instance.Origin.Y -and $_.Origin.Z -eq $instance.Origin.Z -and
        $_.Angles.X -eq $instance.Angles.X -and $_.Angles.Y -eq $instance.Angles.Y -and $_.Angles.Z -eq $instance.Angles.Z
    })
    Assert ($matches.Count -eq 1) 'Every actual legacy Storm Drain source instance retains its exact physical transform.'
}
$militaryMap = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'border_showcase_fixture_map.json') | ConvertFrom-Json
$militaryCell = @($militaryMap.cells | Where-Object { $_.x -eq 5 -and $_.y -eq 5 })[0]
$militaryCell.environment.tags = @('military')
$militaryMapPath = Join-Path $OutputRoot 'military-map.json'
$militaryPlanPath = Join-Path $OutputRoot 'military-plan.json'
[IO.File]::WriteAllText($militaryMapPath, ($militaryMap | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $militaryMapPath -CellDirectory $coverageDirectory -Output $militaryPlanPath -ListOutput (Join-Path $OutputRoot 'military-required.txt') | Out-Null
if (-not $?) { throw 'Military fixture planning failed.' }
$militaryPlan = Get-Content -Raw -LiteralPath $militaryPlanPath | ConvertFrom-Json
$militaryPlan.cells = @($militaryPlan.cells | Where-Object environmentProfile -eq 'military' | Select-Object -First 1)
Assert ($militaryPlan.cells.Count -eq 1) 'An actual military recipe must be exercised.'
[IO.File]::WriteAllText($militaryPlanPath, ($militaryPlan | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $militaryPlanPath -CellDirectory $coverageDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated -PruneStaleGenerated:$false | Out-Null
if (-not $?) { throw 'Military fixture generation failed.' }
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'coverage-required.txt'), [string[]]@((Get-ChildItem -LiteralPath $coverageDirectory -Filter '*.vmf').Name), [Text.UTF8Encoding]::new($false))
$compileMaps = @(
    'zz_preview_d4cbfaa03e4b-v1-edge2.vmf',
    'zz_preview_d4cbfaa03e4b-wtrnw-oceanw-edge2.vmf',
    'zz_preview_d4cbfaa03e4b-wtrnt-edge2.vmf',
    'zz_preview_a51608af6980-cp-edge2.vmf'
)
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'compile-required.txt'), [string[]]$compileMaps, [Text.UTF8Encoding]::new($false))
Write-Output "Outer edges: $script:passed assertions passed; isolated fixtures: $cellDirectory"
