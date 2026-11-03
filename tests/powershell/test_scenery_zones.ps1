Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
Import-Module (Join-Path $bin 'scenery_density.psm1') -Force

$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Scenery zones: $Message" }
    $script:passed++
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $rejected = $true
    }
    Assert $rejected "Expected rejection matching '$Pattern'."
}

$settings = (& (Join-Path $bin 'resolve_world_generation_profile.ps1') -WorldProfile preview).Settings
$plannerSettings = $settings.cellPlanning
$industrialThemedChancePercent = [int]$plannerSettings.decorations.industrialThemedChancePercent
$fortifiedThemedChancePercent = [int]$plannerSettings.buildingSelection.fortifiedThemedChancePercent
$commercialSpreadChancePercent = [int]$plannerSettings.buildingSelection.commercialSpreadChancePercent
$commercialSpreadProfiles = @($plannerSettings.buildingSelection.commercialSpreadProfiles)
$radioactiveBuildingTags = @($plannerSettings.buildingSelection.radioactiveTags)
$map = [pscustomobject]@{ map = [pscustomobject]@{ seed = 1337 } }
$script:scenerySelectionCache = @{}
$script:sceneryUsageCounts = @{}
foreach ($source in @(
    @{ file = 'generate_world_cells.ps1'; functions = @('Get-RadiationIntensity', 'Get-EnvironmentTags', 'Test-RadioactiveScenery') },
    @{ file = 'plan_cell_templates.ps1'; functions = @('Get-TerrainTemplate', 'Get-BuildingDensity', 'Get-SceneryTemplateSelection', 'Get-ProfileFallbackTemplates', 'Test-CommercialSpreadPlacement') }
)) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $bin $source.file), [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "Parse $($source.file)."
    foreach ($name in $source.functions) {
        $definitions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        Assert ($definitions.Count -eq 1) "Find exactly one production function $name."
        . ([scriptblock]::Create($definitions[0].Extent.Text))
    }
}

$radiationEnabled = $true
$radiationFalloutRadiusCells = 9
$radiationSceneryRadiusCells = 7
$laboratorySceneryRadiusCells = 2
$radiationDestroyedRadiusCells = 4
$militaryZoneRadiusCells = 4
$radiationSources = @([pscustomobject]@{ x = 10; y = 10 })
$laboratoryZoneOrigins = @([pscustomobject]@{ x = 1; y = 18 })
$militaryZoneOrigins = @(
    [pscustomobject]@{ x = 13; y = 10; kind = 'military' },
    [pscustomobject]@{ x = 10; y = 14; kind = 'fortified' }
)
$landmarkCells = @{
    '1,18' = @([pscustomobject]@{ Label = 'LAB'; Name = 'Laboratory' })
    '13,10' = @([pscustomobject]@{ Label = 'A'; Name = 'Army Base' })
    '10,14' = @([pscustomobject]@{ Label = 'B'; Name = 'Bunker' })
}
$terrainTypes = @{}
$buildingCells = @{}
$roadCells = @{}
$highwayCells = @{}
$diagonalHighwayCells = @{}
$denCells = @{ '10,11' = @{ Name = 'Fixture Den' } }
$metroStations = @{}
$metroLines = @()
$cells = [System.Collections.Generic.List[object]]::new()
for ($y = 0; $y -lt 20; $y++) {
    for ($x = 0; $x -lt 20; $x++) {
        $key = "$x,$y"
        $terrainTypes[$key] = 'grassland'
        $falloutDistance = [Math]::Sqrt([Math]::Pow($x - 10, 2) + [Math]::Pow($y - 10, 2))
        $laboratoryDistance = [Math]::Sqrt([Math]::Pow($x - 1, 2) + [Math]::Pow($y - 18, 2))
        $expectedExposure = [Math]::Round([Math]::Max(0.0, 1 - $falloutDistance / 9), 3)
        $tags = @(Get-EnvironmentTags $x $y)
        $scenery = Test-RadioactiveScenery $x $y
        Assert ((Get-RadiationIntensity $x $y) -eq $expectedExposure) "Exposure remains unchanged at $key."
        Assert (($tags -contains 'radioactive') -eq ($expectedExposure -gt 0 -or $laboratoryDistance -le 3)) "Gameplay radioactive tag remains unchanged at $key."
        Assert ($scenery -eq ($falloutDistance -lt 7 -or $laboratoryDistance -le 2)) "Scenery radii are exact at $key."
        $landmarks = if ($landmarkCells.ContainsKey($key)) { @($landmarkCells[$key]) } else { @() }
        $safeZone = if ($denCells.ContainsKey($key)) { $denCells[$key] } else { $null }
        $cells.Add([pscustomobject]@{
            x = $x; y = $y
            environment = [pscustomobject]@{ terrain = 'grassland'; tags = $tags; sceneryRadioactive = $scenery }
            building = [pscustomobject]@{ present = $false }
            landmarks = $landmarks
            safeZone = $safeZone
        })
    }
}
Assert ((Get-EnvironmentTags 14 10) -contains 'destroyed') 'Destruction includes the radius-4 boundary.'
Assert ((Get-EnvironmentTags 15 10) -notcontains 'destroyed') 'Destruction excludes cells beyond radius 4.'
Assert ((Get-EnvironmentTags 17 10) -contains 'radioactive' -and -not (Test-RadioactiveScenery 17 10)) 'Fallout remains active at the exclusive scenery radius.'
Assert ((Get-EnvironmentTags 1 15) -contains 'radioactive' -and -not (Test-RadioactiveScenery 1 15)) 'Laboratory gameplay coverage remains three cells while scenery stops at two.'
Assert (Test-RadioactiveScenery 1 16) 'Laboratory scenery includes its radius-2 boundary.'

$priority = @($plannerSettings.environment.profilePriority)
Set-ZMSceneryDensityFields @($cells.ToArray()) @($cells | Where-Object x -eq 0) $priority -GridCells 20 -RadiationSources $radiationSources -DestroyedRadiusCells 4 -MilitaryRadiusCells 4
$byKey = @{}
foreach ($cell in $cells) { $byKey["$($cell.x),$($cell.y)"] = $cell }
Assert ((Get-ZMSceneryEnvironmentProfile $byKey['10,10'] $priority) -ceq 'destroyed' -and $byKey['10,10'].sceneryDensityTier -eq 1) 'The detonation starts the low-density destroyed ring.'
Assert ($byKey['12,10'].sceneryDensityTier -eq 2) 'The middle destroyed ring is medium density.'
Assert ((Get-ZMSceneryEnvironmentProfile $byKey['14,10'] $priority) -ceq 'destroyed' -and $byKey['14,10'].sceneryDensityTier -eq 3) 'Destruction wins over surrounding military scenery and reaches high density.'
Assert ((Get-ZMSceneryEnvironmentProfile $byKey['13,10'] $priority) -ceq 'military' -and $byKey['13,10'].sceneryDensityTier -eq 1) 'An exact army landmark is protected inside the destroyed zone.'
Assert ((Get-ZMSceneryEnvironmentProfile $byKey['10,14'] $priority) -ceq 'fortified' -and $byKey['10,14'].sceneryDensityTier -eq 1) 'An exact bunker is protected at the destroyed boundary.'
Assert ((Get-ZMSceneryEnvironmentProfile $byKey['10,11'] $priority) -ceq 'safe_zone') 'An exact safe zone is protected inside the destroyed zone.'
Assert ((Get-ZMSceneryEnvironmentProfile $byKey['15,10'] $priority) -ceq 'military' -and $byKey['15,10'].sceneryZone.distance -eq 2) 'Military scenery uses the nearest matching landmark outside destruction.'
Assert ((Get-ZMDestroyedZoneTier 1.333 4) -eq 1 -and (Get-ZMDestroyedZoneTier 1.334 4) -eq 2 -and (Get-ZMDestroyedZoneTier 2.667 4) -eq 3) 'Destroyed tiers change at the approved thirds.'
Assert-Rejected { Get-ZMDestroyedZoneTier 4.1 4 } '*distance*radius*'
Assert-Rejected { Get-ZMIndustrialZoneTierCap ([double]::NaN) 4 } '*distance*radius*'
$manifest = [pscustomobject]@{ map = [pscustomobject]@{ gridCells = 20; environment = [pscustomobject]@{ sceneryDensityPolicyVersion = 2 } }; cells = @($cells.ToArray()) }
Assert (Test-ZMSceneryDensityManifest $manifest) 'All generated special-zone density records validate.'
$badZone = $byKey['14,10'] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$badZone.sceneryZone.distance = 3
Assert-Rejected { Get-ZMStoredSceneryDensity $badZone -GridCells 20 } 'Invalid scenery zone*'

$legacyRadioactive = [pscustomobject]@{ x = 1; y = 1; environment = [pscustomobject]@{ terrain = 'grassland'; tags = @('radioactive') }; building = [pscustomobject]@{ present = $false } }
Assert (Test-ZMSceneryRadioactiveTheme $legacyRadioactive) 'Legacy cells without the scenery flag retain tag-based radioactive selection.'
$legacyOverlap = [pscustomobject]@{
    x = 2; y = 2
    environment = [pscustomobject]@{ terrain = 'grassland'; tags = @('radioactive', 'military', 'safe_zone'); sceneryRadioactive = $false }
    building = [pscustomobject]@{ present = $true }
    landmarks = @([pscustomobject]@{ Name = 'Army Base'; Label = 'A' })
    industrialZone = [pscustomobject]@{ id = 1 }
}
$legacyPriority = @('radioactive', 'safe_zone', 'military')
Assert ((Get-ZMSceneryEnvironmentProfile $legacyOverlap $legacyPriority) -ceq 'radioactive') 'Unversioned cells retain their configured tag priority.'
Assert ((Get-ZMSceneryEnvironmentProfile $legacyOverlap $legacyPriority -CurrentPolicy) -ceq 'military') 'New manifest generation applies protected army-landmark precedence before writing its policy version.'
Add-Member -InputObject $legacyOverlap -NotePropertyName sceneryDensityPolicyVersion -NotePropertyValue 1
Assert ((Get-ZMSceneryEnvironmentProfile $legacyOverlap $legacyPriority) -ceq 'radioactive') 'Policy-v1 cells retain their configured tag priority.'
Assert ((Get-TerrainTemplate 'grassland' $legacyOverlap 'radioactive') -ceq $plannerSettings.terrainTemplates.grassland) 'Policy-v1 cells retain ordinary terrain selection.'
Assert (-not (Test-ZMSceneryRadioactiveTheme $byKey['17,10'])) 'Explicit false scenery takes precedence over the gameplay tag.'
Assert ((Get-TerrainTemplate 'grassland' $byKey['17,10'] 'grassland') -ceq $plannerSettings.terrainTemplates.grassland) 'A gameplay-only radioactive tag does not select radioactive terrain.'
Assert ((Get-TerrainTemplate 'grassland' $byKey['14,10'] 'destroyed') -ceq $plannerSettings.terrainTemplates.grassland) 'Destroyed terrain does not fall through to radioactive terrain.'
Assert (-not (Test-ZMIndustrialZoneCell ([pscustomobject]@{ industrialZone = $false }))) 'A shared plan recipe with industrialZone=false is not industrial.'
Assert (Test-ZMIndustrialZoneCell ([pscustomobject]@{ industrialZone = $true })) 'A shared plan recipe with industrialZone=true remains industrial.'

$industrialSettings = @{ enabled = $true; cellsPerZone = 400; radius = 4; minInlandDistance = 3; minSpacing = 0; excludedOriginTags = @('safe_zone') }
$industrialCells = [System.Collections.Generic.List[object]]::new()
for ($y = 0; $y -lt 20; $y++) {
    for ($x = 0; $x -lt 20; $x++) {
        $isArmySafe = $x -eq 15 -and $y -eq 16
        $isSafe = $isArmySafe -or ($x -eq 14 -and $y -eq 16)
        $industrialCells.Add([pscustomobject]@{
            x = $x; y = $y
            environment = [pscustomobject]@{ terrain = 'grassland'; tags = @('grassland') + $(if ($isSafe) { @('safe_zone') } else { @() }); sceneryRadioactive = $false }
            building = [pscustomobject]@{ present = $false }
            landmarks = if ($isArmySafe) { @([pscustomobject]@{ Name = 'Army Base'; Label = 'A' }) } else { @() }
            safeZone = if ($isSafe) { [pscustomobject]@{ name = 'Fixture Den' } } else { $null }
            district = [pscustomobject]@{ industrialOriginWeight = if ($x -eq 15 -and $y -eq 15) { 1.0 } else { 0.0 } }
        })
    }
}
Set-ZMSceneryDensityFields @($industrialCells.ToArray()) @($industrialCells | Where-Object x -eq 0) $priority -GridCells 20 -Seed 1337 -IndustrialZoneSettings $industrialSettings
$industrialByKey = @{}
foreach ($cell in $industrialCells) { $industrialByKey["$($cell.x),$($cell.y)"] = $cell }
Assert ($industrialByKey['15,15'].industrialZone.distance -eq 0 -and $industrialByKey['15,15'].sceneryDensityTier -eq 1) 'Industrial centers cap density to low.'
Assert ($industrialByKey['17,15'].industrialZone.distance -eq 2 -and $industrialByKey['17,15'].sceneryDensityTier -eq 2) 'Industrial middle rings cap density to medium.'
Assert ($industrialByKey['19,15'].industrialZone.distance -eq 4 -and $industrialByKey['19,15'].sceneryDensityTier -eq 3) 'Industrial boundaries include radius four and permit high density.'
Assert ((Get-ZMSceneryEnvironmentProfile $industrialByKey['15,16'] $priority) -ceq 'military') 'An Army Base sharing a safe-zone cell retains army surroundings.'
foreach ($key in @('15,16', '14,16')) {
    Assert (-not (Test-ZMIndustrialZoneCell $industrialByKey[$key]) -and $industrialByKey[$key].environment.tags -notcontains 'industrial_zone') "Industrial overlays do not change safe-zone cell $key, including an Army Base overlap."
}
Assert (Test-ZMSceneryDensityManifest ([pscustomobject]@{ map = $manifest.map; cells = @($industrialCells.ToArray()) })) 'Industrial density records validate.'

$weights = @(
    [pscustomobject]@{ x = 3; y = 1; environment = [pscustomobject]@{ tags = @() }; landmarks = @(); safeZone = $null; district = [pscustomobject]@{ industrialOriginWeight = 1.0 } },
    [pscustomobject]@{ x = 4; y = 1; environment = [pscustomobject]@{ tags = @() }; landmarks = @(); safeZone = $null; district = [pscustomobject]@{ industrialOriginWeight = 4.0 } }
)
$weightSettings = @{ cellsPerZone = 2; minInlandDistance = 3; minSpacing = 0; excludedOriginTags = @() }
$weightDistances = @{ '3,1' = 3; '4,1' = 4 }
$heavyWins = 0
foreach ($seed in 0..299) {
    $winner = @(Get-ZMIndustrialZoneOrigins $weights $weightDistances $seed $weightSettings)[0]
    if ($winner.x -eq 4) { $heavyWins++ }
    if ($seed -eq 0) {
        Assert ((@(Get-ZMIndustrialZoneOrigins $weights $weightDistances $seed $weightSettings)[0].x) -eq $winner.x) 'Industrial origin selection is deterministic for the same seed.'
    }
}
Assert ($heavyWins -ge 210 -and $heavyWins -le 270) "District weights bias industrial origins (heavy district won $heavyWins of 300 seeds)."
$weights[0].district.industrialOriginWeight = 0
Assert ((@(Get-ZMIndustrialZoneOrigins $weights $weightDistances 1337 $weightSettings)[0].x) -eq 4) 'A zero-weight district cannot produce an industrial origin.'

$decorationFamilies = @(
    'decorations/tile_bushes_1a.vmf',
    'decorations/tile_destroyed_debris_1a.vmf',
    'decorations/tile_army_tent.vmf',
    'decorations/tile_fortified_army_tent.vmf',
    'decorations/tile_industrial_containers_1a.vmf',
    'decorations/tile_ra_trees_1a.vmf',
    'terrain/tile_ra_fence_a_cap.vmf'
)
foreach ($case in @(
    @{ profile = 'grassland'; industrial = $false; radioactive = $false; expected = @('decorations/tile_bushes_1a.vmf') },
    @{ profile = 'radioactive'; industrial = $false; radioactive = $true; expected = @('decorations/tile_bushes_1a.vmf', 'decorations/tile_ra_trees_1a.vmf', 'terrain/tile_ra_fence_a_cap.vmf') },
    @{ profile = 'grassland'; industrial = $true; radioactive = $false; expected = @('decorations/tile_bushes_1a.vmf', 'decorations/tile_industrial_containers_1a.vmf', 'decorations/tile_ra_trees_1a.vmf', 'terrain/tile_ra_fence_a_cap.vmf') },
    @{ profile = 'destroyed'; industrial = $true; radioactive = $true; expected = @('decorations/tile_bushes_1a.vmf', 'decorations/tile_destroyed_debris_1a.vmf') },
    @{ profile = 'military'; industrial = $true; radioactive = $true; expected = @('decorations/tile_bushes_1a.vmf', 'decorations/tile_army_tent.vmf') },
    @{ profile = 'fortified'; industrial = $true; radioactive = $true; expected = @('decorations/tile_bushes_1a.vmf', 'decorations/tile_fortified_army_tent.vmf') },
    @{ profile = 'safe_zone'; industrial = $true; radioactive = $true; expected = @('decorations/tile_bushes_1a.vmf') }
)) {
    $actual = @(Get-ZMSceneryDecorationTemplates $decorationFamilies $case.profile $case.industrial $case.radioactive)
    Assert (@(Compare-Object $actual $case.expected).Count -eq 0) "$($case.profile) decorations include only their approved themes and ordinary fallback."
}
$themedPattern = Get-ZMSceneryPreferredTemplatePattern 'grassland' 'decoration' $true $false
$decorations = @('decorations/tile_industrial_test_1a.vmf', 'decorations/tile_bushes_1a.vmf')
$themedCount = 0
foreach ($choice in 0..999) {
    $selected = Select-ZMSceneryTemplate $decorations 1 0 $choice 'fixture/industrial-choice' -PreferredPattern $themedPattern -PreferredChancePercent 80
    if ($selected.template -match $themedPattern) { $themedCount++ }
}
Assert ($themedCount -eq 800) 'The compatible industrial decoration preference selects themed art exactly 80% of the time.'
$ordinaryFallback = Select-ZMSceneryTemplate @('decorations/tile_bushes_1a.vmf') 1 0 0 'fixture/no-theme' -PreferredPattern $themedPattern -PreferredChancePercent 80
$themeFallback = Select-ZMSceneryTemplate @('decorations/tile_industrial_test_1a.vmf') 1 0 99 'fixture/no-ordinary' -PreferredPattern $themedPattern -PreferredChancePercent 80
Assert ($ordinaryFallback.template -ceq 'decorations/tile_bushes_1a.vmf') 'Missing themed decorations fall back to ordinary compatible pieces.'
Assert ($themeFallback.template -ceq 'decorations/tile_industrial_test_1a.vmf') 'Missing ordinary decorations fall back to compatible themed pieces.'
$choiceCell = $industrialByKey['15,15']
$industrialThemedChancePercent = 0
$zeroChoice = Get-SceneryTemplateSelection $decorations $choiceCell 'grassland' 'open' 'none' 1 @('none') 0 'test-slot' 'decoration'
$industrialThemedChancePercent = 100
$fullChoice = Get-SceneryTemplateSelection $decorations $choiceCell 'grassland' 'open' 'none' 1 @('none') 0 'test-slot' 'decoration'
Assert ($zeroChoice.template -notmatch $themedPattern -and $fullChoice.template -match $themedPattern) 'The planner applies the configured preference and separates cached choices by chance.'
$legacyChoiceCell = $choiceCell.PSObject.Copy()
$legacyChoiceCell.sceneryDensityPolicyVersion = 1
$industrialThemedChancePercent = 0
$legacyChoice = Get-SceneryTemplateSelection $decorations $legacyChoiceCell 'grassland' 'open' 'none' 1 @('none') 0 'legacy-slot' 'decoration' -WithoutUsage
$legacySelectionContext = @{ Seed = 1337; CellPolicy = 'grassland|grassland|open|none|1|none'; Ring = 'core'; Slot = 'legacy-slot'; Role = 'decoration'; Variant = 0 }
$legacyTierHash = Get-ZMScenerySelectionHash @legacySelectionContext -Purpose tier
$legacyTemplateHash = Get-ZMScenerySelectionHash @legacySelectionContext -Purpose template
$legacyExpected = Select-ZMSceneryTemplate $decorations 1 ([int]($legacyTierHash % 100)) $legacyTemplateHash 'legacy fixture'
Assert ($legacyChoice.template -ceq $legacyExpected.template -and -not $legacyChoice.preferredPool) 'Policy-v1 industrial decoration selection retains the original unpreferred pool.'

$fortifiedPattern = Get-ZMSceneryPreferredTemplatePattern 'fortified' 'building' $false $false '' $plannerSettings.templatePatterns.fortifiedBuildings
$fortifiedMix = @('army/tile_army_tent.vmf', 'buildings/tile_fortified_1a.vmf')
$fortifiedChoices = 0
foreach ($choice in 0..999) {
    $selected = Select-ZMSceneryTemplate $fortifiedMix 1 0 $choice 'fixture/fortified-choice' -PreferredPattern $fortifiedPattern -PreferredChancePercent 80
    if ($selected.template -match $fortifiedPattern) { $fortifiedChoices++ }
}
Assert ($fortifiedChoices -eq 800) 'The compatible fortified building preference selects fortified art exactly 80% of the time.'
$armyFallback = Select-ZMSceneryTemplate @('army/tile_army_tent.vmf', 'buildings/tile_fortified_1aa.vmf') 1 0 0 'fixture/incompatible-fortified' -PreferredPattern $fortifiedPattern -PreferredChancePercent 80
$fortifiedFallback = Select-ZMSceneryTemplate @('buildings/tile_fortified_1a.vmf') 1 0 99 'fixture/no-army' -PreferredPattern $fortifiedPattern -PreferredChancePercent 80
Assert ($armyFallback.template -ceq 'army/tile_army_tent.vmf') 'An incompatible fortified tier falls back to a compatible Army building.'
Assert ($fortifiedFallback.template -ceq 'buildings/tile_fortified_1a.vmf') 'A missing Army family falls back to a compatible fortified building.'
$fortifiedCell = $byKey['10,14']
$fortifiedThemedChancePercent = 0
$zeroFortified = Get-SceneryTemplateSelection $fortifiedMix $fortifiedCell 'fortified' 'open' 'none' 1 @('none') 0 'test-fortified-slot' 'building' -WithoutUsage
$fortifiedThemedChancePercent = 100
$fullFortified = Get-SceneryTemplateSelection $fortifiedMix $fortifiedCell 'fortified' 'open' 'none' 1 @('none') 0 'test-fortified-slot' 'building' -WithoutUsage
Assert ($zeroFortified.template -match '^army/' -and $fullFortified.template -match $fortifiedPattern) 'The planner applies the fortified preference and separates cached choices by chance.'
$fortifiedThemedChancePercent = [int]$plannerSettings.buildingSelection.fortifiedThemedChancePercent

$caps = $plannerSettings.environment.buildingDensity.specialZoneTierCaps
foreach ($tier in 1..3) {
    Assert ((Get-BuildingDensity 'grassland' 'destroyed' $byKey['14,10'] $tier) -eq [Math]::Min([double]$plannerSettings.environment.buildingDensity.destroyed, [double]$caps[[string]$tier])) "Destroyed building occupancy applies tier-$tier cap."
    Assert ((Get-BuildingDensity 'grassland' 'grassland' $choiceCell $tier) -eq [Math]::Min([double]$plannerSettings.environment.buildingDensity.grassland, [double]$caps[[string]$tier])) "Industrial building occupancy applies tier-$tier cap."
    foreach ($profile in @('military', 'fortified')) {
        $uncapped = Get-BuildingDensity 'grassland' $profile
        Assert ((Get-BuildingDensity 'grassland' $profile $choiceCell $tier) -eq [Math]::Min($uncapped, [double]$caps[[string]$tier])) "$profile building occupancy applies tier-$tier cap."
    }
}
$legacyDensity = [pscustomobject]@{ sceneryDensityPolicyVersion = 1; industrialZone = $true }
Assert ((Get-BuildingDensity 'grassland' 'destroyed' $legacyDensity 1) -eq [double]$plannerSettings.environment.buildingDensity.destroyed) 'Legacy policy-v1 building occupancy is unchanged.'
Assert ((Get-BuildingDensity 'grassland' 'safe_zone' $choiceCell 1) -eq (Get-BuildingDensity 'grassland' 'safe_zone')) 'Safe-zone building occupancy is not capped by an industrial overlay.'

$armyBuildingTemplates = @('army/tile_army_tent.vmf')
$fortifiedBuildingTemplates = @('buildings/tile_fortified_1a.vmf')
$destroyedBuildingTemplates = @('buildings/tile_destroyed_1a.vmf')
$radioactiveBuildingTemplates = @('buildings/tile_ra_building_1a.vmf')
$buildingTemplates = @('buildings/tile_building_1a.vmf')
$warehouseTemplates = @('buildings/tile_warehouse_1a.vmf')
$commercialTemplates = @('buildings/tile_commercial_1a.vmf')
$industryTemplates = @('buildings/tile_industrial_1a.vmf')
$destroyedBuildings = @(Get-ProfileFallbackTemplates $byKey['14,10'] 'destroyed' @('none'))
$radioactiveBuildings = @(Get-ProfileFallbackTemplates $byKey['14,10'] 'radioactive' @('none'))
$militaryBuildings = @(Get-ProfileFallbackTemplates $byKey['13,10'] 'military' @('Army Base'))
$fortifiedBuildings = @(Get-ProfileFallbackTemplates $byKey['10,14'] 'fortified' @('Bunker'))
Assert ($destroyedBuildings.Count -eq 1 -and $destroyedBuildings[0] -ceq $destroyedBuildingTemplates[0]) 'Destroyed fallback buildings cannot be replaced by radioactive, military or industrial buildings.'
Assert ($radioactiveBuildings.Count -eq 1 -and $radioactiveBuildings[0] -ceq $radioactiveBuildingTemplates[0]) 'Radioactive fallback buildings do not admit generic or industrial buildings.'
Assert ($militaryBuildings.Count -eq 1 -and $militaryBuildings[0] -ceq $armyBuildingTemplates[0]) 'Military fallback buildings use only the army folder.'
Assert ($fortifiedBuildings.Count -eq 2 -and $fortifiedBuildings -contains $armyBuildingTemplates[0] -and $fortifiedBuildings -contains $fortifiedBuildingTemplates[0]) 'Fortified fallback buildings contain both approved families and no others.'
$legacyFortifiedCell = [pscustomobject]@{ x = 0; y = 0; sceneryDensityPolicyVersion = 1; environment = [pscustomobject]@{ terrain = 'grassland'; tags = @() } }
$legacyFortifiedBuildings = @(Get-ProfileFallbackTemplates $legacyFortifiedCell 'fortified' @('none'))
Assert ($legacyFortifiedBuildings -contains $buildingTemplates[0] -and $legacyFortifiedBuildings -contains $warehouseTemplates[0] -and
    $legacyFortifiedBuildings -notcontains $armyBuildingTemplates[0] -and $legacyFortifiedBuildings -notcontains $fortifiedBuildingTemplates[0]) 'Policy-v1 fortified cells retain their previous generic fallback pool.'
$legacyBuildings = @(Get-ProfileFallbackTemplates $legacyOverlap 'destroyed' @('none'))
Assert ($legacyBuildings -contains $radioactiveBuildingTemplates[0] -and $legacyBuildings -contains $industryTemplates[0] -and $legacyBuildings -notcontains $destroyedBuildingTemplates[0]) 'Policy-v1 overlapping fallout retains its prior radioactive and industrial building pool.'

$spreadCell = [pscustomobject]@{ x = 6; y = 5; district = [pscustomobject]@{ commercialSpreadChancePercent = 0 } }
$spreadProfile = [string]$commercialSpreadProfiles[0]
Assert (-not (Test-CommercialSpreadPlacement $spreadCell $spreadProfile)) 'Districts can disable commercial spread.'
$spreadCell.district.commercialSpreadChancePercent = 100
Assert (Test-CommercialSpreadPlacement $spreadCell $spreadProfile) 'Districts can guarantee commercial spread on eligible profiles.'
Assert (-not (Test-CommercialSpreadPlacement $spreadCell 'destroyed')) 'District commercial spread cannot override protected themed profiles.'
$spreadCell.district.commercialSpreadChancePercent = 101
Assert-Rejected { Test-CommercialSpreadPlacement $spreadCell $spreadProfile } 'Invalid district commercial spread*'

$templateRoot = (Resolve-Path (Join-Path $root 'tiletemplates')).Path.TrimEnd('\')
$availableTemplates = @(Get-ChildItem -LiteralPath $templateRoot -Filter '*.vmf' -File -Recurse | ForEach-Object {
    $_.FullName.Substring($templateRoot.Length).TrimStart('\').Replace('\', '/')
} | Sort-Object)
$actualDecorations = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.decorations })
foreach ($required in @(
    'decorations/tile_plaza_1a.vmf',
    'terrain/tile_fence_a_cap.vmf', 'terrain/tile_fence_a_corner.vmf', 'terrain/tile_fence_a_double.vmf',
    'terrain/tile_ra_fence_a_cap.vmf', 'terrain/tile_ra_fence_a_corner.vmf', 'terrain/tile_ra_fence_a_double.vmf'
)) {
    Assert ($actualDecorations -contains $required) "Approved decoration is in the actual catalog: $required."
}
foreach ($case in @(
    @{ name = 'ordinary'; profile = 'grassland'; industrial = $false; radioactive = $false; pattern = '^(?!decorations/tile_(?:destroyed|army|fortified|industrial|ra)_|terrain/tile_ra_)' },
    @{ name = 'destroyed'; profile = 'destroyed'; industrial = $true; radioactive = $true; pattern = '^decorations/tile_destroyed_' },
    @{ name = 'army'; profile = 'military'; industrial = $true; radioactive = $true; pattern = '^decorations/tile_army_' },
    @{ name = 'fortified'; profile = 'fortified'; industrial = $true; radioactive = $true; pattern = '^decorations/tile_fortified_' },
    @{ name = 'industrial'; profile = 'grassland'; industrial = $true; radioactive = $false; pattern = '^decorations/tile_industrial_' },
    @{ name = 'industrial radioactive'; profile = 'grassland'; industrial = $true; radioactive = $false; pattern = '^(?:decorations/tile_ra_|terrain/tile_ra_)' },
    @{ name = 'radioactive'; profile = 'radioactive'; industrial = $false; radioactive = $true; pattern = '^(?:decorations/tile_ra_|terrain/tile_ra_)' }
)) {
    $family = @($actualDecorations | Where-Object { $_ -match $case.pattern })
    Assert ($family.Count -gt 0) "Actual $($case.name) decoration family is present."
    $eligible = @(Get-ZMSceneryDecorationTemplates $actualDecorations $case.profile $case.industrial $case.radioactive)
    $preferred = Get-ZMSceneryPreferredTemplatePattern $case.profile 'decoration' $case.industrial $case.radioactive
    Assert ($preferred -ceq (Get-ZMSceneryPreferredTemplatePattern $case.profile 'open_terrain_fill' $case.industrial $case.radioactive)) "$($case.name) open-terrain fill uses the same theme."
    foreach ($template in $family) {
        Assert ($eligible -contains $template) "$template is eligible in its intended $($case.name) profile."
        if ($case.name -ne 'ordinary') { Assert ($template -match $preferred) "$template is in the intended preferred family." }
    }
    foreach ($tier in 1..3) {
        $expected = @($family | Where-Object { (Get-ZMTemplateDensityTag $_) -in @(0, $tier) })
        if ($expected.Count -eq 0) { continue }
        $selected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $chance = if ($case.industrial -and $case.profile -eq 'grassland') { 80 } else { 100 }
        for ($index = 0; $index -le $eligible.Count; $index++) {
            $choice = if ($chance -eq 80) { 100 * $index + 1 } else { $index }
            $result = Select-ZMSceneryTemplate $eligible $tier 0 $choice "actual/$($case.name)/$tier" -PreferredPattern $preferred -PreferredChancePercent $chance
            if ($null -ne $result.template) { [void]$selected.Add($result.template) }
        }
        foreach ($template in $expected) {
            Assert ($selected.Contains($template)) "$template is reachable at compatible tier $tier in $($case.name)."
        }
    }
}

$buildingTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.genericBuildings })
$armyBuildingTemplates = @($availableTemplates | Where-Object { $_ -match '^army/.*\.vmf$' })
$fortifiedBuildingTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.fortifiedBuildings })
$destroyedBuildingTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.destroyedBuildings })
$radioactiveBuildingTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.radioactiveBuildings })
$warehouseTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.warehouses })
$commercialTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.commercial })
$industryTemplates = @($availableTemplates | Where-Object { $_ -match $plannerSettings.templatePatterns.industry })
foreach ($case in @(
    @{ name = 'destroyed'; profile = 'destroyed'; cell = $byKey['14,10']; family = $destroyedBuildingTemplates },
    @{ name = 'radioactive'; profile = 'radioactive'; cell = $byKey['14,10']; family = $radioactiveBuildingTemplates },
    @{ name = 'army'; profile = 'military'; cell = $byKey['13,10']; family = $armyBuildingTemplates },
    @{ name = 'fortified Army'; profile = 'fortified'; cell = $byKey['10,14']; family = $armyBuildingTemplates },
    @{ name = 'fortified buildings'; profile = 'fortified'; cell = $byKey['10,14']; family = $fortifiedBuildingTemplates },
    @{ name = 'industrial'; profile = 'grassland'; cell = $choiceCell; family = $industryTemplates }
)) {
    Assert ($case.family.Count -gt 0) "Actual $($case.name) building family is present."
    $pool = @(Get-ProfileFallbackTemplates $case.cell $case.profile @('none'))
    $isIndustrial = Test-ZMIndustrialZoneCell $case.cell
    $isRadioactive = Test-ZMSceneryRadioactiveTheme $case.cell $radioactiveBuildingTags
    $preferred = Get-ZMSceneryPreferredTemplatePattern $case.profile 'building' $isIndustrial $isRadioactive $plannerSettings.templatePatterns.radioactiveBuildings $plannerSettings.templatePatterns.fortifiedBuildings
    foreach ($template in $case.family) {
        Assert ($pool -contains $template) "$template is in the actual $($case.name) building pool."
        $footprint = Get-ZMTemplateFootprint $template
        $compatible = @($pool | Where-Object {
            $candidateFootprint = Get-ZMTemplateFootprint $_
            $candidateFootprint.width -eq $footprint.width -and $candidateFootprint.height -eq $footprint.height
        })
        $tag = Get-ZMTemplateDensityTag $template
        $tier = [Math]::Max(1, $tag)
        $selected = $false
        for ($index = 0; $index -le 3 * $compatible.Count; $index++) {
            $chance = if ($case.profile -eq 'fortified') { $fortifiedThemedChancePercent } else { 100 }
            $choice = if ($case.profile -eq 'fortified') { 100 * $index + $(if ($template -match $preferred) { 0 } else { 80 }) } else { $index }
            $result = Select-ZMSceneryTemplate $compatible $tier 0 $choice "actual/$($case.name)/$template" -PreferredPattern $preferred -PreferredChancePercent $chance -LowDensityBuildingPreference
            if ($result.template -ceq $template) { $selected = $true; break }
        }
        Assert $selected "$template is selectable in a compatible $($case.name) tier and footprint."
    }
}

Write-Host "Scenery zones: $passed assertions passed; no world outputs changed."
