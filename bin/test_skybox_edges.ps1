param([string]$OutputRoot = '', [switch]$BuildModels)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $root 'generated\skybox_edges' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Force -Path $OutputRoot
Import-Module (Join-Path $PSScriptRoot 'cell_bounds.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$script:passed = 0
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Skybox edges: $Message" }
    $script:passed++
}
$resolved = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$settings = $resolved.Settings
$settings.vmfBuild.outerEdges.enabled = $true
$settings.vmfBuild.border.water.chancePercent = 100
$settingsPath = Join-Path $OutputRoot 'settings.json'
[IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
$sourceDirectory = Join-Path $OutputRoot 'src'
$planPath = Join-Path $OutputRoot 'plan.json'
$listPath = Join-Path $OutputRoot 'required.txt'
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData (Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json') -CellDirectory $sourceDirectory -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Skyline fixture planning failed.' }
$plan = Get-Content -Raw $planPath | ConvertFrom-Json
$selected = @($plan.cells | Group-Object { (@($_.skyboxOceanSides) -join '') + ':' + (@($_.waterBorderSides | ForEach-Object { $_.side } | Sort-Object) -join '') } |
    ForEach-Object { $_.Group[0] })
$tower = @($plan.cells | Where-Object { @($_.tilePlacements | Where-Object template -match 'tile_skyscraper_\d+[a-z]+_2x\.vmf$').Count -gt 0 } | Select-Object -First 1)
$bridge = @($plan.cells | Where-Object transportFeature -eq 'bridge-horizontal' | Select-Object -First 1)
Assert ($tower.Count -eq 1 -and $bridge.Count -eq 1) 'Actual tower and bridge recipes are available.'
Assert (@($selected | Where-Object { @($_.skyboxOceanSides).Count -gt 0 }).Count -gt 0) 'Actual west skybox-ocean omission recipes are exercised.'
$stormDrain = @($plan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 12 })
Assert ($stormDrain.Count -eq 1 -and $stormDrain[0].safeZoneEntrance.slot -eq 'W') 'Exact Storm Drain grid cell 0,12 is included.'
$plan.cells = @(@($selected) + $tower + $bridge + $stormDrain | Group-Object cellTemplateFilename | ForEach-Object { $_.Group[0] })
$plan.safeZoneMaps = @()
[IO.File]::WriteAllText($planPath, ($plan | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines($listPath, [string[]]@($plan.cells.cellTemplateFilename), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -CellDirectory $sourceDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Skyline fixture VMF generation failed.' }
$builder = [ZombieSim.Skybox.CellModelBuilder]::new(24)
$materials = [Collections.Generic.Dictionary[string, ZombieSim.Skybox.MaterialInfo]]::new()
$recipes = [string[]]@($plan.cells | ForEach-Object { Join-Path $sourceDirectory $_.cellTemplateFilename })
foreach ($material in $builder.CollectMaterials($recipes)) {
    if ($material -match '^tools/') { continue }
    $info = [ZombieSim.Skybox.MaterialInfo]::new()
    $info.ModelMaterial = $material
    $info.Width = 256
    $info.Height = 256
    $materials.Add($material, $info)
}
$measurements = @()
foreach ($cell in $plan.cells) {
    $path = Join-Path $sourceDirectory $cell.cellTemplateFilename
    $layout = Get-Content -Raw ([IO.Path]::ChangeExtension($path, '.layout.json')) | ConvertFrom-Json
    Assert ((@($layout.waterSides) -join ',') -ceq (@($cell.skyboxOceanSides) -join ',')) 'Coast attachment follows skybox ocean, not authored water-corner tiles.'
    if ($cell.x -eq 0) {
        Assert (@($layout.outerPlacements | Where-Object { $_.tileX -eq -2 -and $_.targetname -notlike 'zm_outer_corridor_*' }).Count -eq 0) 'West ocean omits the outer scenery and both adjacent outer corners.'
    }
    $shell = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -Raw -LiteralPath $path))
    foreach ($solid in $shell.Child('world').Children | Where-Object Name -eq 'solid') {
        $material = ($solid.Children | Where-Object Name -eq 'side' | Select-Object -First 1).Get('material').ToUpperInvariant()
        if ($material -notin @('HALFLIFE/BLACK', 'TOOLS/TOOLSSKYBOX')) { continue }
        $xCoordinates = @($solid.Children | Where-Object Name -eq 'side' | ForEach-Object { $_.Child('vertices_plus').GetAll('v') } |
            ForEach-Object { [double]($_ -split '\s+')[0] } | Sort-Object -Unique)
        $westCoordinates = if ($cell.x -eq 0) { @(-2240, -2304) } else { @(-3072, -3136) }
        Assert (@($xCoordinates | Where-Object { $_ -lt 0 -and $_ -notin $westCoordinates }).Count -eq 0) 'Actual recipe floor and sky seal match the west ocean attachment or expanded inland clearance.'
        if ($material -eq 'HALFLIFE/BLACK') {
            Assert (($xCoordinates -join ',') -eq $(if ($cell.x -eq 0) { '-2240,3072' } else { '-3072,3072' })) 'No black floor extends into the omitted west skybox band.'
        }
    }
    $instances = [ZombieSim.Skybox.CellModelBuilder]::ReadInstances($path)
    foreach ($placement in $layout.outerPlacements) {
        $expectedPath = [IO.Path]::GetFullPath((Join-Path $plan.chunkTemplateDirectory $placement.template))
        $expectedX = ($placement.tileX - 2) * 640
        $expectedY = (2 - $placement.tileY) * 640
        $found = @($instances | Where-Object {
            $_.File -eq $expectedPath -and $_.Origin.X -eq $expectedX -and $_.Origin.Y -eq $expectedY -and $_.Angles.Y -eq $placement.rotationYaw
        })
        Assert ($found.Count -eq 1) "Edge $($placement.targetname) appears once at $expectedX,$expectedY with yaw $($placement.rotationYaw)."
    }
    $parts = $builder.BuildParts($path, 1.0 / 16, $materials, 30000, 60)
    $detail = $builder.BuildDetail($path, 'trees', 'props_vehicles/', 'CONCRETE/CONCRETEFLOOR037A', [string[]]@(), 320, 0, 192)
    $edgeFires = @($detail.Fires | Where-Object EdgeBuilding)
    Assert ($edgeFires.Count -gt 6 -and $edgeFires.Count -le @($layout.outerPlacements).Count) 'Actual edge sources provide enough distinct rooftop anchors for six current-cell fires.'
    Assert (@($edgeFires | Where-Object Kind -ne 2).Count -eq 0) 'Nearby edge fires exclude wrecks.'
    Assert (@($detail.Fires | Where-Object { -not $_.EdgeBuilding -and $_.Kind -eq 2 }).Count -gt 0) 'Core and old-border rooftop candidates remain separate from physical edge fires.'
    foreach ($fire in $edgeFires) {
        Assert ([math]::Max([math]::Abs($fire.Origin.X), [math]::Abs($fire.Origin.Y)) -gt 2240) 'Generated edge rooftop coordinates are already transformed into physical world space.'
        if ($cell.x -eq 0) {
            Assert ($fire.Origin.X -ge -2240) 'Omitted west-ocean edge has no nearby fire anchors.'
        }
    }
    $snow = $builder.BuildSnowParts($path, 1.0 / 16, $materials, 30000, 'snow', 0.7, 8, 256)
    $towers = $builder.BuildTowerParts($path, 1.0 / 16, $materials, 30000, 60)
    Assert ($parts.Count -gt 0 -and $snow.Count -gt 0) 'Expanded source produces base and snow geometry.'
    foreach ($part in $parts) {
        $partMaterialCount = @($part.Smd -split '\r?\n' | Where-Object { $materials.ContainsKey($_) } | Sort-Object -Unique).Count
        Assert ($part.Vertices -le 30000 -and $partMaterialCount -le 60) 'Existing part budgets remain unchanged.'
    }
    $measurement = [ordered]@{ recipe = $cell.cellTemplateFilename; outerInstances = @($layout.outerPlacements).Count;
        parts = $parts.Count; triangles = ($parts | Measure-Object Triangles -Sum).Sum;
        snowParts = $snow.Count; snowTriangles = ($snow | Measure-Object Triangles -Sum).Sum;
        towerParts = $towers.Count }
    $measurements += $measurement
}
Assert (@($measurements | Where-Object towerParts -gt 0).Count -gt 0) 'Tower-only extraction still finds the selected actual skyscraper.'
# Dependency fixtures are isolated from authored assets and model inputs.
$dependencyDirectory = Join-Path $OutputRoot 'dependencies'
$null = New-Item -ItemType Directory -Force -Path $dependencyDirectory
$parent = Join-Path $dependencyDirectory 'parent.vmf'
$child = Join-Path $dependencyDirectory 'child.vmf'
$leaf = Join-Path $dependencyDirectory 'leaf.vmf'
[IO.File]::WriteAllText($parent, '"file" "child.vmf"')
[IO.File]::WriteAllText($child, '"file" "leaf.vmf"')
[IO.File]::WriteAllText($leaf, 'first')
$before = @(Get-VmfSourceHashes $parent)
[IO.File]::WriteAllText($leaf, 'second')
$after = @(Get-VmfSourceHashes $parent)
Assert ($before.Count -eq 3 -and $after.Count -eq 3 -and ($before -join ':') -ne ($after -join ':')) 'Nested source edits invalidate model hashes.'
[IO.File]::WriteAllText($child, '"file" "missing.vmf"')
$rejected = $false
try { $null = Get-VmfSourceHashes $parent } catch { $rejected = $_.Exception.Message -like 'Missing VMF source dependency:*' }
Assert $rejected 'Missing nested sources are explicit failures.'
if ($BuildModels) {
    $content = Join-Path $OutputRoot 'content'
    & (Join-Path $PSScriptRoot 'build_skybox_models.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -OutputContentDirectory $content -BuildDirectory (Join-Path $OutputRoot 'build')
    if (-not $?) { throw 'Expanded model compilation failed.' }
    & (Join-Path $PSScriptRoot 'test_skybox_manifest.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -ContentDirectory $content
    if (-not $?) { throw 'Expanded model manifest regression failed.' }
    $manifest = Get-Content -Raw (Join-Path $content 'data_static\zombiesim_skybox_preview.json') | ConvertFrom-Json
    $firstModel = [string]@($manifest.recipes.PSObject.Properties)[0].Value[0]
    $companion = Join-Path $content ($firstModel.Replace('/', '\').Replace('.mdl', '.vvd'))
    $lastWrite = (Get-Item -LiteralPath $companion).LastWriteTimeUtc
    & (Join-Path $PSScriptRoot 'build_skybox_models.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -OutputContentDirectory $content -BuildDirectory (Join-Path $OutputRoot 'build') | Out-Null
    if (-not $?) { throw 'Incremental skyline build failed.' }
    Assert ((Get-Item -LiteralPath $companion).LastWriteTimeUtc -eq $lastWrite) 'Unchanged sources reuse complete model companions.'
    Remove-Item -LiteralPath $companion
    & (Join-Path $PSScriptRoot 'build_skybox_models.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -OutputContentDirectory $content -BuildDirectory (Join-Path $OutputRoot 'build') | Out-Null
    if (-not $?) { throw 'Missing-companion recovery build failed.' }
    Assert ((Test-Path -LiteralPath $companion) -and (Get-Item -LiteralPath $companion).Length -gt 0) 'Missing VVD invalidates the cache and is rebuilt.'
    & (Join-Path $PSScriptRoot 'test_skybox_manifest.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -ContentDirectory $content
    if (-not $?) { throw 'Recovered model manifest regression failed.' }
}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'geometry-report.json'), ($measurements | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Host "Skybox edges: $script:passed assertions passed; $($plan.cells.Count) isolated skyline recipes."
