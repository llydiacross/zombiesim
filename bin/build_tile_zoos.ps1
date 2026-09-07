param(
    [string]$TemplateDirectory = '',
    [string]$OutputDirectory = '',
    [int]$TileSize = 640,
    [string]$PlanData = '',
    [string]$MapData = '',
    [switch]$RefreshPlan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$generatorSettings = $worldGenerationProfile.Settings
Import-Module (Join-Path $PSScriptRoot 'carpark_endcaps.psm1') -Force
if ([string]::IsNullOrWhiteSpace($TemplateDirectory)) { $TemplateDirectory = Join-Path $projectRoot 'tiletemplates' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $projectRoot 'celltemplates/dev' }
if ([string]::IsNullOrWhiteSpace($PlanData)) { $PlanData = Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337_template_plan.json' }
if ([string]::IsNullOrWhiteSpace($MapData)) { $MapData = Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json' }
$carparkFixtureMapData = Join-Path $PSScriptRoot 'carpark_zoo_fixture_map.json'
$carparkFixturePlanData = Join-Path $PSScriptRoot 'carpark_zoo_fixture_template_plan.json'
$carparkFixtureListOutput = Join-Path $PSScriptRoot 'carpark_zoo_fixture_required_cell_vmfs.txt'
if (-not (Test-Path -LiteralPath $TemplateDirectory)) { throw "Required path was not found: $TemplateDirectory" }
if ($RefreshPlan) {
    $listOutput = Join-Path ([System.IO.Path]::GetDirectoryName($PlanData)) ([System.IO.Path]::GetFileNameWithoutExtension($PlanData).Replace('_template_plan', '_required_cell_vmfs') + '.txt')
    & (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') -WorldProfile preview -MapData $MapData -Output $PlanData -ListOutput $listOutput | Out-Null
    if (-not $?) { throw 'Preview planner failed while refreshing dev fixture data.' }
}
if (-not (Test-Path -LiteralPath $PlanData)) { throw "Template plan was not found: $PlanData. Run with -RefreshPlan to create it." }
if (-not (Test-Path -LiteralPath $carparkFixtureMapData)) { throw "Carpark zoo fixture map was not found: $carparkFixtureMapData" }
if (-not (Test-Path -LiteralPath $OutputDirectory)) { [System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null }
$TemplateDirectory = (Resolve-Path -LiteralPath $TemplateDirectory).Path.TrimEnd('\')
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path.TrimEnd('\')
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
if ($plan.cellTileGridSize -lt 1 -or @($plan.cells).Count -eq 0) { throw 'Template plan must contain cellTileGridSize and cells.' }

function Get-InstancePath {
    param([string]$OutputPath, [string]$Template)

    $sourceUri = [System.Uri]((Split-Path -Parent $OutputPath).TrimEnd('\') + '\')
    $templateUri = [System.Uri](Join-Path $TemplateDirectory $Template)
    return [System.Uri]::UnescapeDataString($sourceUri.MakeRelativeUri($templateUri).ToString())
}

function Get-BuildingZooSortKey {
    param([string]$Template)

    $filename = (Split-Path -Leaf $Template).ToLowerInvariant()
    $typeOrder = switch -Regex ($filename) {
        '^tile_destroyed' { 0; break }
        '^tile_(warehouse|industry)' { 1; break }
        '^tile_(commercial|market|bank)' { 2; break }
        '^tile_(church|hospital|police|fire|petrol|army|laboratory|bunker|airport)' { 3; break }
        '^tile_(building|construction)' { 4; break }
        default { 5 }
    }
    $density = if ($filename -match '_[0-9]+([a-z]+)\.vmf$') { $Matches[1].Length } else { 0 }
    return '{0:D2}-{1:D2}-{2}' -f $typeOrder, $density, $filename
}

function Get-TemplateFootprint {
    param([string]$Template)

    $templateName = [System.IO.Path]::GetFileNameWithoutExtension($Template)
    if ($templateName -match '(?i)_2x(?:2)?$') { return [pscustomobject]@{ width = 2; height = 2 } }
    if ($templateName -match '(?i)_3x(?:3)?$') { return [pscustomobject]@{ width = 3; height = 3 } }
    return [pscustomobject]@{ width = 1; height = 1 }
}

function Get-PlannedPlacementFootprint {
    param([object]$Placement)

    $widthProperty = $Placement.PSObject.Properties['footprintWidth']
    $heightProperty = $Placement.PSObject.Properties['footprintHeight']
    return [pscustomobject]@{
        width = if ($null -eq $widthProperty) { 1 } else { [int]$widthProperty.Value }
        height = if ($null -eq $heightProperty) { 1 } else { [int]$heightProperty.Value }
    }
}

function Test-PlannedPlacementEmitsInstance {
    param([object]$Placement)

    $property = $Placement.PSObject.Properties['emitsInstance']
    return $null -eq $property -or [bool]$property.Value
}

function Get-ZooGridPlacements {
    param([string[]]$Templates, [switch]$Buildings)

    if ($Buildings) {
        $orderedTemplates = @($Templates | Sort-Object { Get-BuildingZooSortKey $_ })
    } else {
        $orderedTemplates = @($Templates | Sort-Object)
    }
    $maximumFootprint = @($orderedTemplates | ForEach-Object { (Get-TemplateFootprint $_).width } | Measure-Object -Maximum).Maximum
    $slotTileSpan = [Math]::Max(1, [int]$maximumFootprint + 1)
    $columns = [Math]::Max(1, [int][Math]::Ceiling([Math]::Sqrt($orderedTemplates.Count)))
    $placements = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $orderedTemplates.Count; $index++) {
        $column = $index % $columns
        $row = [int][Math]::Floor($index / $columns)
        $footprint = Get-TemplateFootprint $orderedTemplates[$index]
        $placements.Add([pscustomobject]@{
            template = $orderedTemplates[$index]
            x = ($column - (($columns - 1) / 2.0)) * $slotTileSpan * $TileSize
            y = ((($columns - 1) / 2.0) - $row) * $slotTileSpan * $TileSize
            yaw = 0
            targetname = "zm_dev_zoo_$index"
            row = $row
            column = $column
            footprintWidth = $footprint.width
            footprintHeight = $footprint.height
        })
    }
    return @($placements)
}

function Get-LandmarkZooTemplates {
    $templates = @(Get-ChildItem -LiteralPath $TemplateDirectory -Filter '*.vmf' -File -Recurse |
        ForEach-Object { $_.FullName.Substring($TemplateDirectory.Length).TrimStart('\').Replace('\', '/') })
    $patterns = @($generatorSettings.cellPlanning.landmarkTemplatePatterns.Values |
        ForEach-Object { [string]$_ } |
        Sort-Object -Unique)
    $landmarkTemplates = [System.Collections.Generic.List[string]]::new()
    foreach ($template in $templates) {
        foreach ($pattern in $patterns) {
            if ($template -like $pattern -or $template -like $pattern.TrimStart('*/')) {
                $landmarkTemplates.Add($template)
                break
            }
        }
    }
    return @($landmarkTemplates | Sort-Object -Unique)
}

function New-DevVmf {
    param([string]$OutputPath, [object[]]$Placements)

    $entityId = 2
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($placement in $Placements) {
        $lines.AddRange([string[]]@(
            'entity',
            '{',
            ('    "id" "{0}"' -f $entityId),
            '    "classname" "func_instance"',
            ('    "origin" "{0} {1} 0"' -f [int]$placement.x, [int]$placement.y),
            ('    "angles" "0 {0} 0"' -f [int]$placement.yaw),
            ('    "file" "{0}"' -f (Get-InstancePath $OutputPath $placement.template)),
            ('    "targetname" "{0}"' -f $placement.targetname),
            '    "fixup_style" "0"',
            '}'
        ))
        $entityId++
    }
    $vmf = @"
versioninfo
{
    "editorversion" "400"
    "editorbuild" "8871"
    "mapversion" "1"
    "formatversion" "100"
    "prefab" "0"
}
visgroups
{
}
viewsettings
{
    "bSnapToGrid" "1"
    "bShowGrid" "1"
    "bShowLogicalGrid" "0"
    "nGridSpacing" "64"
}
world
{
    "id" "1"
    "mapversion" "1"
    "classname" "worldspawn"
}
"@ + [Environment]::NewLine + ($lines -join [Environment]::NewLine) + @"

cameras
{
    "activecamera" "-1"
}
cordons
{
    "active" "0"
}
"@
    [System.IO.File]::WriteAllText($OutputPath, $vmf, [System.Text.UTF8Encoding]::new($false))
}

function Add-RecipeFixturePlacements {
    param(
        [System.Collections.Generic.List[object]]$Placements,
        [object]$Recipe,
        [int]$OriginTileX,
        [int]$OriginTileY,
        [string]$Prefix
    )

    $center = [int][Math]::Floor([int]$plan.cellTileGridSize / 2)
    foreach ($placement in @($Recipe.tilePlacements | Where-Object { Test-PlannedPlacementEmitsInstance $_ })) {
        $footprint = Get-PlannedPlacementFootprint $placement
        $Placements.Add([pscustomobject]@{
            template = [string]$placement.template
            x = ($OriginTileX + [int]$placement.tileX - $center + (($footprint.width - 1) / 2.0)) * $TileSize
            y = ($OriginTileY + $center - [int]$placement.tileY - (($footprint.height - 1) / 2.0)) * $TileSize
            yaw = [int]$placement.rotationYaw
            targetname = "zm_dev_${Prefix}_$($placement.role)_$($placement.tileX)_$($placement.tileY)"
        })
    }
    foreach ($endcap in @(Get-CarparkEndcapPlacements -Recipe $Recipe -TileGridSize $plan.cellTileGridSize -CarparkTemplates $generatorSettings.cellPlanning.carparks.templates)) {
        $Placements.Add([pscustomobject]@{
            template = [string]$endcap.template
            x = ($OriginTileX + [int]$endcap.tileX - $center) * $TileSize
            y = ($OriginTileY + $center - [int]$endcap.tileY) * $TileSize
            yaw = [int]$endcap.rotationYaw
            targetname = "zm_dev_${Prefix}_carpark_endcap_$($endcap.tileX)_$($endcap.tileY)"
        })
    }
}

function Get-CarparkFixtureRecipes {
    $plannerScript = Join-Path $PSScriptRoot 'plan_cell_templates.ps1'
    & $plannerScript -WorldProfile preview -MapData $carparkFixtureMapData -Output $carparkFixturePlanData -ListOutput $carparkFixtureListOutput -ForceEligibleCarparks | Out-Null
    if (-not $?) { throw 'Carpark zoo fixture planner failed.' }

    $fixturePlan = Get-Content -Raw -LiteralPath $carparkFixturePlanData | ConvertFrom-Json
    $fixtureRecipes = @($fixturePlan.cells | Where-Object {
        @($_.tilePlacements | Where-Object { $_.role -eq 'carpark_entrance' }).Count -eq 1
    } | Sort-Object y, x)
    $fixtureExpectations = [ordered]@{
        '0,0' = @{ layout = 'one-sided'; eastLaneTiles = 0; westLaneTiles = 1; internalEndcaps = 1 }
        '1,0' = @{ layout = 'through'; eastLaneTiles = 2; westLaneTiles = 2; internalEndcaps = 0 }
        '2,0' = @{ layout = 'through'; eastLaneTiles = 1; westLaneTiles = 1; internalEndcaps = 2 }
        '3,0' = @{ layout = 'through'; eastLaneTiles = 1; westLaneTiles = 1; internalEndcaps = 2 }
        '4,0' = @{ layout = 'through'; eastLaneTiles = 1; westLaneTiles = 1; internalEndcaps = 2 }
        '5,0' = @{ layout = 'terminal'; eastLaneTiles = 0; westLaneTiles = 0; internalEndcaps = 0 }
        '6,0' = @{ layout = 'one-sided'; eastLaneTiles = 1; westLaneTiles = 0; internalEndcaps = 1 }
    }
    $expectedCoordinates = @($fixtureExpectations.Keys)
    if ($fixtureRecipes.Count -ne $expectedCoordinates.Count) {
        throw "Carpark zoo fixture planner produced $($fixtureRecipes.Count) carparks; expected $($expectedCoordinates.Count)."
    }
    foreach ($recipe in $fixtureRecipes) {
        if ("$($recipe.x),$($recipe.y)" -notin $expectedCoordinates) {
            throw "Carpark zoo fixture planner produced an unexpected cell: $($recipe.x),$($recipe.y)."
        }
        $coordinate = "$($recipe.x),$($recipe.y)"
        $expected = $fixtureExpectations[$coordinate]
        $entrance = @($recipe.tilePlacements | Where-Object { $_.role -eq 'carpark_entrance' })
        $eastLaneTiles = @($recipe.tilePlacements | Where-Object { $_.role -eq 'carpark_lane_east' }).Count
        $westLaneTiles = @($recipe.tilePlacements | Where-Object { $_.role -eq 'carpark_lane_west' }).Count
        $internalEndcaps = @($recipe.tilePlacements | Where-Object { $_.role -match '^carpark_lane_endcap_(east|west)$' }).Count
        if ($entrance.Count -ne 1 -or $eastLaneTiles -ne [int]$expected.eastLaneTiles -or $westLaneTiles -ne [int]$expected.westLaneTiles -or $internalEndcaps -ne [int]$expected.internalEndcaps) {
            throw "Carpark zoo fixture $coordinate no longer matches its expected $($expected.layout) layout."
        }
        $entranceFilename = Split-Path -Leaf ([string]$entrance[0].template)
        if ($expected.layout -eq 'terminal' -and $entranceFilename -ine 'tile_carpark_entrance_deadend.vmf') {
            throw "Carpark zoo fixture $coordinate must use the terminal entrance asset."
        }
        if ($expected.layout -eq 'through' -and $entranceFilename -match '^tile_carpark_entrance_deadend') {
            throw "Carpark zoo fixture $coordinate must use a through entrance asset."
        }
        if ($expected.layout -ne 'one-sided') { continue }
        if ($entranceFilename -notmatch '^tile_carpark_entrance_deadend_(east|west)\.vmf$') {
            throw "Carpark zoo fixture $coordinate must use a one-sided entrance asset."
        }
        $openLane = @($recipe.tilePlacements | Where-Object {
            $_.role -match '^carpark_lane_(east|west)$' -and
            ([Math]::Abs([int]$_.tileX - [int]$entrance[0].tileX) + [Math]::Abs([int]$_.tileY - [int]$entrance[0].tileY)) -eq 1
        })
        if ($openLane.Count -ne 1) { throw "Carpark zoo fixture $coordinate has no adjacent one-sided lane tile." }
        $carparkJunction = @($recipe.tilePlacements | Where-Object { $_.role -eq 'carpark_road_junction' })
        if ($carparkJunction.Count -ne 1) { throw "Carpark zoo fixture $coordinate has no carpark road junction." }
        $closedLaneKey = if ([string]$openLane[0].role -eq 'carpark_lane_east') { 'west' } else { 'east' }
        $entranceDefinition = Get-CarparkOneSidedEntranceDefinition $closedLaneKey ([int]$carparkJunction[0].rotationYaw)
        if ($null -eq $entranceDefinition) { throw "Carpark zoo fixture $coordinate has no one-sided entrance definition." }
        $expectedEntranceFilename = if ($entranceDefinition.templateKey -eq 'entranceDeadendEast') { 'tile_carpark_entrance_deadend_east.vmf' } else { 'tile_carpark_entrance_deadend_west.vmf' }
        if ($entranceFilename -ine $expectedEntranceFilename -or [int]$entrance[0].rotationYaw -ne [int]$entranceDefinition.rotationYaw) {
            throw "Carpark zoo fixture $coordinate one-sided entrance does not follow the local lane orientation contract."
        }
    }
    return @($fixtureRecipes)
}

function Get-CarparkFixturePrefix {
    param([object]$Recipe)

    $scenarioName = @{
        '0,0' = 'vertical_east'
        '1,0' = 'vertical_west'
        '2,0' = 'horizontal_north'
        '3,0' = 'horizontal_south'
        '4,0' = 'horizontal_south_bridge_ramp_east'
        '5,0' = 'vertical_terminal_entrance'
        '6,0' = 'horizontal_one_sided_east_short'
    }["$($Recipe.x),$($Recipe.y)"]
    if ([string]::IsNullOrWhiteSpace($scenarioName)) {
        throw "Carpark zoo fixture has no scenario name: $($Recipe.x),$($Recipe.y)."
    }
    return "carpark_fixture_$scenarioName"
}

function Get-StreetFixturePlacements {
    $scenarios = @($plan.cells | Where-Object {
        ($_.topology -like 'road-*' -or $_.topology -like 'motorway-*') -and
        @($_.tilePlacements | Where-Object { $_.role -like '*carpark*' }).Count -eq 0
    } | Group-Object { "$($_.topology)|$($_.orientation)" } | Sort-Object Name | ForEach-Object {
        @($_.Group | Sort-Object cellTemplateFilename | Select-Object -First 1)[0]
    })
    if ($scenarios.Count -eq 0) { throw 'Preview plan contains no non-carpark road or motorway recipes for the streets fixture.' }
    $placements = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $scenarios.Count; $index++) {
        $column = $index % 5
        $row = [int][Math]::Floor($index / 5)
        Add-RecipeFixturePlacements $placements $scenarios[$index] (($column - 2) * 6) ((1 - $row) * 6) "street_${index}"
    }
    return @($placements)
}

function Get-CarparkFixturePlacements {
    $recipes = @($plan.cells | Where-Object {
        @($_.tilePlacements | Where-Object { $_.role -eq 'carpark_entrance' }).Count -eq 1
    } | Group-Object cellTemplateFilename | ForEach-Object { $_.Group[0] } | Sort-Object cellTemplateFilename)
    if ($recipes.Count -eq 0) { throw 'Preview plan contains no carpark recipe. Increase carparks.roadStraightChancePercent or use a plan with carparks.' }
    $placements = [System.Collections.Generic.List[object]]::new()
    $selectedRecipes = @($recipes)
    for ($index = 0; $index -lt $selectedRecipes.Count; $index++) {
        Add-RecipeFixturePlacements $placements $selectedRecipes[$index] (($index - 1) * 6) 12 "carpark_${index}"
    }

    $fixtureRecipes = @(Get-CarparkFixtureRecipes)
    for ($index = 0; $index -lt $fixtureRecipes.Count; $index++) {
        $column = $index % 4
        $row = [int][Math]::Floor($index / 4)
        Add-RecipeFixturePlacements $placements $fixtureRecipes[$index] (($column - 1.5) * 6) (-$row * 6) (Get-CarparkFixturePrefix $fixtureRecipes[$index])
    }
    return @($placements)
}

$manifest = [ordered]@{ schemaVersion = 1; tileSize = $TileSize; cells = @() }
foreach ($categoryDirectory in @(Get-ChildItem -LiteralPath $TemplateDirectory -Directory | Sort-Object Name)) {
    $categoryName = $categoryDirectory.Name.ToLowerInvariant()
    $templates = @(Get-ChildItem -LiteralPath $categoryDirectory.FullName -Filter '*.vmf' -File -Recurse |
        ForEach-Object { $_.FullName.Substring($TemplateDirectory.Length).TrimStart('\').Replace('\', '/') })
    if ($templates.Count -eq 0) { continue }
    $outputPath = Join-Path $OutputDirectory "zoo_$categoryName.vmf"
    $placements = @(Get-ZooGridPlacements $templates -Buildings:($categoryName -eq 'buildings'))
    New-DevVmf $outputPath $placements
    $manifest.cells += [ordered]@{
        name = "zoo_$categoryName.vmf"
        category = $categoryName
        tiles = @($placements | ForEach-Object { [ordered]@{ template = $_.template; row = $_.row; column = $_.column; yaw = $_.yaw; footprintWidth = $_.footprintWidth; footprintHeight = $_.footprintHeight } })
    }
}

$landmarkTemplates = @(Get-LandmarkZooTemplates)
if ($landmarkTemplates.Count -eq 0) { throw 'No landmark templates match cellPlanning.landmarkTemplatePatterns.' }
$landmarkOutputPath = Join-Path $OutputDirectory 'landmarks.vmf'
$landmarkPlacements = @(Get-ZooGridPlacements $landmarkTemplates -Buildings)
New-DevVmf $landmarkOutputPath $landmarkPlacements
$manifest.cells += [ordered]@{
    name = 'landmarks.vmf'
    category = 'landmarks'
    tiles = @($landmarkPlacements | ForEach-Object { [ordered]@{ template = $_.template; row = $_.row; column = $_.column; yaw = $_.yaw } })
}

$streetOutputPath = Join-Path $OutputDirectory 'streets.vmf'
$streetPlacements = @(Get-StreetFixturePlacements)
New-DevVmf $streetOutputPath $streetPlacements
$manifest.cells += [ordered]@{ name = 'streets.vmf'; category = 'street_layout'; tiles = @($streetPlacements | ForEach-Object { [ordered]@{ template = $_.template; targetname = $_.targetname; yaw = $_.yaw } }) }

$carparkOutputPath = Join-Path $OutputDirectory 'carparks.vmf'
$carparkPlacements = @(Get-CarparkFixturePlacements)
New-DevVmf $carparkOutputPath $carparkPlacements
$manifest.cells += [ordered]@{ name = 'carparks.vmf'; category = 'carpark_layouts'; tiles = @($carparkPlacements | ForEach-Object { [ordered]@{ template = $_.template; targetname = $_.targetname; yaw = $_.yaw } }) }

$generatedZooNames = @($manifest.cells | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
$prunedZooVmfs = 0
foreach ($existingVmf in @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.vmf' -File)) {
    $isGeneratedZoo = $existingVmf.Name -like 'zoo_*.vmf' -or $existingVmf.Name -in @('streets.vmf', 'carparks.vmf', 'landmarks.vmf')
    if (-not $isGeneratedZoo -or $existingVmf.Name -in $generatedZooNames) { continue }
    Remove-Item -LiteralPath $existingVmf.FullName -Force
    $prunedZooVmfs++
}

$manifestPath = Join-Path $OutputDirectory 'zoo_manifest.json'
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated $($manifest.cells.Count) dev cells in $OutputDirectory; pruned stale zoo VMFs: $prunedZooVmfs"