param(
    [Parameter(Mandatory = $true)][string]$MapData,
    [Parameter(Mandatory = $true)][string]$PlanData,
    [Parameter(Mandatory = $true)][string]$TrustedMotorwayPlan,
    [switch]$RequireDistrictRefreshTiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
Import-Module (Join-Path $bin 'scenery_density.psm1') -Force
Import-Module (Join-Path $bin 'motorway_geometry.psm1') -Force

$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Alpha 3.5 preview: $Message" }
    $script:passed++
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $bin 'export_runtime_world_data.ps1'), [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Runtime exporter parses.'
foreach ($name in @('Get-RuntimeSceneryDensityFields', 'Get-RuntimeMotorwayGates')) {
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    Assert ($definitions.Count -eq 1) "Runtime exporter defines $name once."
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $bin 'build_cell_vmfs.ps1'), [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'VMF builder parses.'
foreach ($name in @('Get-PlacementFootprint', 'Test-PlacementEmitsInstance')) {
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    Assert ($definitions.Count -eq 1) "VMF builder defines $name once."
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$manifest = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$trusted = Get-Content -Raw -LiteralPath $TrustedMotorwayPlan | ConvertFrom-Json
$settings = (& (Join-Path $bin 'resolve_world_generation_profile.ps1') -WorldProfile preview).Settings
$priority = @($settings.cellPlanning.environment.profilePriority)
$referencedManifest = if ([IO.Path]::IsPathRooted($plan.mapData)) {
    [IO.Path]::GetFullPath($plan.mapData)
} else {
    [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($PlanData))) $plan.mapData))
}
Assert ($referencedManifest -ieq ([IO.Path]::GetFullPath($MapData))) 'Plan references the supplied manifest.'
Assert ($plan.mapSeed -eq $manifest.map.seed -and $plan.mapGridCells -eq $manifest.map.gridCells) 'Plan seed and grid match the manifest.'
Assert ($trusted.mapSeed -eq $plan.mapSeed -and $trusted.mapGridCells -eq $plan.mapGridCells) 'Trusted motorway plan matches the seed and grid.'
Assert (Test-ZMSceneryDensityManifest $manifest) 'Current manifest density and zone metadata validate.'

$plannedByKey = @{}
$emptyByKey = @{}
$trustedByKey = @{}
foreach ($cell in @($plan.cells)) {
    $key = "$($cell.x),$($cell.y)"
    Assert (-not $plannedByKey.ContainsKey($key)) "Duplicate planned cell $key."
    $plannedByKey[$key] = $cell
}
foreach ($cell in @($plan.emptyCells)) {
    $key = "$($cell.x),$($cell.y)"
    Assert (-not $emptyByKey.ContainsKey($key) -and -not $plannedByKey.ContainsKey($key)) "Duplicate or planned empty cell $key."
    $emptyByKey[$key] = $true
}
foreach ($cell in @($trusted.cells)) { $trustedByKey["$($cell.x),$($cell.y)"] = $cell }
Assert ($plannedByKey.Count + $emptyByKey.Count -eq @($manifest.cells).Count) 'Planned and empty cells cover the manifest.'

$districtServices = @{}
$recipeLayouts = @{}
$checkedTemplates = @{}
$motorwayCount = 0
$templateRoot = Join-Path $root 'tiletemplates'
foreach ($cell in @($manifest.cells)) {
    $key = "$($cell.x),$($cell.y)"
    if ($emptyByKey.ContainsKey($key)) {
        Assert (-not $cell.road.present -and -not $cell.highway.present -and $null -eq $cell.safeZone -and @($cell.landmarks).Count -eq 0) "Empty cell $key has no road, motorway, den or landmark."
        continue
    }
    Assert ($plannedByKey.ContainsKey($key)) "Manifest cell $key is missing from the plan."
    $planned = $plannedByKey[$key]
    [void](Get-RuntimeSceneryDensityFields $cell $planned)
    Assert ($planned.environmentProfile -ceq (Get-ZMSceneryEnvironmentProfile $cell $priority)) "Scenery profile matches at $key."
    Assert ([bool]$planned.industrialZone -eq (Test-ZMIndustrialZoneCell $cell)) "Industrial-zone membership matches at $key."
    if ($null -ne $cell.safeZone) {
        Assert ($null -ne $planned.safeZoneEntrance -and -not $planned.industrialZone) "Den entrance and industrial exclusion are preserved at $key."
    }

    $district = [string]$cell.district.name
    Assert (-not [string]::IsNullOrWhiteSpace($district)) "Cell $key has a district."
    if (-not $districtServices.ContainsKey($district)) { $districtServices[$district] = @{ Police = 0; Fire = 0 } }
    $layout = [System.Collections.Generic.List[string]]::new()
    foreach ($placement in @($planned.tilePlacements)) {
        $footprint = Get-PlacementFootprint $placement
        $emitsInstance = Test-PlacementEmitsInstance $placement
        $layout.Add(('{0},{1}|{2}|{3}|{4}|{5},{6}|{7}' -f $placement.tileX, $placement.tileY, $placement.role, $placement.template, $placement.rotationYaw, $footprint.width, $footprint.height, $emitsInstance))
        if (-not $emitsInstance) { continue }
        $template = [string]$placement.template
        if (-not $checkedTemplates.ContainsKey($template)) {
            Assert (Test-Path -LiteralPath (Join-Path $templateRoot ($template.Replace('/', '\'))) -PathType Leaf) "Emitted source template exists: $template."
            $checkedTemplates[$template] = $true
        }
        if ($placement.role -eq 'decoration') {
            $eligible = @(Get-ZMSceneryDecorationTemplates @($template) $planned.environmentProfile ([bool]$planned.industrialZone) ([bool]$cell.environment.sceneryRadioactive))
            Assert ($eligible.Count -eq 1) "Decoration $template does not leak into $($planned.environmentProfile) at $key."
        }
        if ($placement.role -eq 'building') {
            if ($template -match '^army/') {
                Assert ($planned.environmentProfile -in @('military', 'fortified')) "Army building $template stays in an army or fortified zone at $key."
            }
            if ($template -match $settings.cellPlanning.templatePatterns.fortifiedBuildings) {
                Assert ($planned.environmentProfile -eq 'fortified') "Fortified building $template stays in a fortified zone at $key."
            }
            if ($planned.environmentProfile -eq 'destroyed') {
                Assert ($template -match $settings.cellPlanning.templatePatterns.destroyedBuildings) "Destroyed zone uses a destroyed building at $key."
            } elseif ($planned.environmentProfile -eq 'radioactive' -and -not $planned.industrialZone) {
                Assert ($template -match $settings.cellPlanning.templatePatterns.radioactiveBuildings) "Radioactive zone uses a radioactive building at $key."
            } elseif ($planned.environmentProfile -eq 'military') {
                Assert ($template -match '^army/') "Military zone uses an Army building at $key."
            } elseif ($planned.environmentProfile -eq 'fortified') {
                Assert ($template -match '^army/' -or $template -match $settings.cellPlanning.templatePatterns.fortifiedBuildings) "Fortified zone uses an Army or fortified building at $key."
            }
        }
        if ($placement.role -eq 'landmark') {
            if ($template -match '^buildings/tile_policestation_') { $districtServices[$district].Police++ }
            if ($template -match '^buildings/tile_firestation_') { $districtServices[$district].Fire++ }
        }
    }
    $filename = [string]$planned.cellTemplateFilename
    $signature = $layout -join "`n"
    if ($recipeLayouts.ContainsKey($filename)) {
        Assert ($recipeLayouts[$filename] -ceq $signature) "Shared recipe $filename has consistent placements."
    } else {
        $recipeLayouts[$filename] = $signature
    }

    if ($cell.highway.present) {
        Assert ($trustedByKey.ContainsKey($key)) "Trusted motorway cell $key exists."
        $previous = $trustedByKey[$key]
        Assert ($null -ne $planned.PSObject.Properties['motorwayAssembly'] -and $null -ne $previous.PSObject.Properties['motorwayAssembly']) "Motorway assembly exists at $key."
        $priorContract = $previous.motorwayAssembly | ConvertTo-Json -Depth 100 -Compress
        $currentContract = $planned.motorwayAssembly | ConvertTo-Json -Depth 100 -Compress
        Assert ($currentContract -ceq $priorContract) "Trusted motorway placements, leases and gates are unchanged at $key."
        [void](Get-RuntimeMotorwayGates $planned)
        $motorwayCount++
    }
}
if ($RequireDistrictRefreshTiles) {
    foreach ($requiredTemplate in @(
        'army/tile_army_guardtower.vmf', 'army/tile_army_hanger.vmf', 'army/tile_army_tent3.vmf',
        'army/tile_army_truck.vmf', 'army/tile_army_truck2.vmf',
        'buildings/tile_fortified_1a.vmf', 'buildings/tile_fortified_1aa.vmf', 'buildings/tile_fortified_3aa.vmf'
    )) {
        Assert ($checkedTemplates.ContainsKey($requiredTemplate)) "The refreshed preview emits $requiredTemplate."
    }
}
foreach ($district in @($districtServices.Keys | Sort-Object)) {
    Assert ($districtServices[$district].Police -ge 1 -and $districtServices[$district].Fire -ge 1) "$district contains a planned Police and Fire landmark."
}
Assert ($districtServices.Count -gt 0 -and $motorwayCount -gt 0) 'District and motorway coverage is nonempty.'
Write-Output "Alpha 3.5 preview: $passed assertions passed; $($plannedByKey.Count) planned cells, $($emptyByKey.Count) empty cells, $($recipeLayouts.Count) shared recipes, $motorwayCount trusted motorway cells and $($districtServices.Count) districts."
