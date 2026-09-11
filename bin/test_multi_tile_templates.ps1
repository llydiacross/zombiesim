param(
    [string]$OutputRoot = '',
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureMapPath = Join-Path $PSScriptRoot 'multi_tile_zoo_fixture_map.json'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot 'generated/multi_tile_zoo'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
[System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$planPath = Join-Path $OutputRoot 'multi_tile_zoo_fixture_template_plan.json'
$listPath = Join-Path $OutputRoot 'multi_tile_zoo_fixture_required_cell_vmfs.txt'
$cellDirectory = Join-Path $OutputRoot 'src'
$mapDirectory = Join-Path $OutputRoot 'map_materials'
$plannerScript = Join-Path $PSScriptRoot 'plan_cell_templates.ps1'
$builderScript = Join-Path $PSScriptRoot 'build_cell_vmfs.ps1'
$mapRendererScript = Join-Path $PSScriptRoot 'build_cell_map_materials.ps1'

function Get-TemplateFootprint {
    param([string]$Template)

    $templateName = [System.IO.Path]::GetFileNameWithoutExtension($Template)
    if ($templateName -match '(?i)_2x(?:2)?$') { return [pscustomobject]@{ width = 2; height = 2 } }
    if ($templateName -match '(?i)_3x(?:3)?$') { return [pscustomobject]@{ width = 3; height = 3 } }
    return [pscustomobject]@{ width = 1; height = 1 }
}

function Test-PlacementEmitsInstance {
    param([object]$Placement)

    $property = $Placement.PSObject.Properties['emitsInstance']
    return $null -eq $property -or [bool]$property.Value
}

function Add-ValidationError {
    param([System.Collections.Generic.List[string]]$Errors, [string]$Message)

    $Errors.Add($Message)
}

function Get-ExpectedRoadJunctionCount {
    param([string]$Template)

    $templatePath = Join-Path $projectRoot (Join-Path 'tiletemplates' $Template)
    $contents = Get-Content -Raw -LiteralPath $templatePath
    return @([regex]::Matches($contents, '(?s)entity\s*\{\s*(?<body>.*?)\r?\n\}') | Where-Object {
        $_.Groups['body'].Value -match '"classname"\s+"zn_road_connection"' -and
        $_.Groups['body'].Value -match '"connection_type"\s+"t_junction"'
    }).Count
}

function Get-AuthoredTileDirection {
    param([string]$Template)

    $templatePath = Join-Path $projectRoot (Join-Path 'tiletemplates' $Template)
    $contents = Get-Content -Raw -LiteralPath $templatePath
    $marker = @([regex]::Matches($contents, '(?s)entity\s*\{\s*(?<body>.*?)\r?\n\}') | Where-Object {
        $_.Groups['body'].Value -match '"classname"\s+"zn_tile_direction"'
    } | Select-Object -First 1)[0]
    if ($null -eq $marker) { return 'N' }
    $directionMatch = [regex]::Match($marker.Groups['body'].Value, '"direction"\s+"([^"]+)"')
    if (-not $directionMatch.Success) { throw "Tile direction marker in '$Template' has no direction." }
    $direction = [string]$directionMatch.Groups[1].Value
    return @{ NORTH = 'N'; EAST = 'E'; SOUTH = 'S'; WEST = 'W' }[$direction.ToUpperInvariant()]
}

function Get-CardinalYaw {
    param([string]$Direction)

    return @{ N = 0; E = 90; S = 180; W = 270 }[$Direction]
}

if (-not (Test-Path -LiteralPath $fixtureMapPath -PathType Leaf)) {
    throw "Multi-tile fixture map was not found: $fixtureMapPath"
}

$fixture = Get-Content -Raw -LiteralPath $fixtureMapPath | ConvertFrom-Json
$expectedTemplates = @($fixture.cells | ForEach-Object { [string]$_.multiTileTemplate } | Sort-Object)
if ($expectedTemplates.Count -ne 7) {
    throw "Multi-tile fixture must declare exactly seven templates; found $($expectedTemplates.Count)."
}
foreach ($template in $expectedTemplates) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot (Join-Path 'tiletemplates' $template)) -PathType Leaf)) {
        throw "Multi-tile fixture template was not found: $template"
    }
}

& $plannerScript -WorldProfile preview -MapData $fixtureMapPath -Output $planPath -ListOutput $listPath -CellDirectory $cellDirectory -SettingsPath $SettingsPath | Out-Null
if (-not $?) { throw 'Multi-tile fixture planner failed.' }

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
$recipes = @($plan.cells)
$fixtureCellsByCoordinate = @{}
foreach ($fixtureCell in @($fixture.cells)) {
    $fixtureCellsByCoordinate["$($fixtureCell.x),$($fixtureCell.y)"] = $fixtureCell
}
if ($recipes.Count -ne $expectedTemplates.Count) {
    Add-ValidationError $errors "Expected $($expectedTemplates.Count) fixture recipes; found $($recipes.Count)."
}

$actualTemplates = [System.Collections.Generic.List[string]]::new()
foreach ($recipe in $recipes) {
    $coordinate = "$($recipe.x),$($recipe.y)"
    $fixtureCell = $fixtureCellsByCoordinate[$coordinate]
    if ($null -eq $fixtureCell) {
        Add-ValidationError $errors "Planner returned unexpected fixture cell $coordinate."
        continue
    }
    if (@($recipe.tilePlacements).Count -ne 25) {
        Add-ValidationError $errors "$coordinate does not retain 25 logical occupancy records."
    }

    $anchors = @($recipe.tilePlacements | Where-Object {
        (Test-PlacementEmitsInstance $_) -and ([int]$_.footprintWidth -gt 1 -or [int]$_.footprintHeight -gt 1)
    })
    if ($anchors.Count -ne 1) {
        Add-ValidationError $errors "$coordinate must contain exactly one macro anchor; found $($anchors.Count)."
        continue
    }
    $anchor = $anchors[0]
    $actualTemplates.Add([string]$anchor.template)
    $footprint = Get-TemplateFootprint ([string]$anchor.template)
    $expectedInteriorInstances = 25 - ($footprint.width * $footprint.height) + 1
    if (@($recipe.tilePlacements | Where-Object { Test-PlacementEmitsInstance $_ }).Count -ne $expectedInteriorInstances) {
        Add-ValidationError $errors "$coordinate has an incorrect emitted interior instance count."
    }

    $isEpicenter = @($fixtureCell.landmarks | ForEach-Object { $_.name }) -contains 'The Epicenter'
    if ($isEpicenter) {
        $expectedCapCount = @($fixtureCell.road.connections).Count
        $caps = @($recipe.tilePlacements | Where-Object { $_.role -eq 'special_landmark_road_cap' })
        if ($anchor.role -ne 'landmark_epicenter' -or $anchor.tileX -ne 1 -or $anchor.tileY -ne 1 -or $footprint.width -ne 3 -or $caps.Count -ne $expectedCapCount) {
            Add-ValidationError $errors "$coordinate does not meet the centered Epicenter road-overwrite contract."
        }
        continue
    }

    $roadPlacements = @($recipe.tilePlacements | Where-Object { $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road', 'path', 'building_road_junction', 'landmark_carpark_junction', 'landmark_road_junction') })
    $expectedJunctionCount = Get-ExpectedRoadJunctionCount ([string]$anchor.template)
    $junctionCount = @($recipe.tilePlacements | Where-Object { $_.role -in @('building_road_junction', 'landmark_carpark_junction', 'landmark_road_junction') }).Count
    if ($junctionCount -ne $expectedJunctionCount) {
        Add-ValidationError $errors "$coordinate must create $expectedJunctionCount authored building road T-junction(s); found $junctionCount."
    }
    $facesRoad = $false
    $localDirection = Get-AuthoredTileDirection ([string]$anchor.template)
    foreach ($tileY in [int]$anchor.tileY..(([int]$anchor.tileY + $footprint.height) - 1)) {
        foreach ($tileX in [int]$anchor.tileX..(([int]$anchor.tileX + $footprint.width) - 1)) {
            foreach ($roadPlacement in $roadPlacements) {
                $deltaX = [int]$roadPlacement.tileX - $tileX
                $deltaY = [int]$roadPlacement.tileY - $tileY
                $frontageDirection = if ($deltaX -eq 1 -and $deltaY -eq 0) { 'E' } elseif ($deltaX -eq -1 -and $deltaY -eq 0) { 'W' } elseif ($deltaX -eq 0 -and $deltaY -eq -1) { 'N' } elseif ($deltaX -eq 0 -and $deltaY -eq 1) { 'S' } else { $null }
                $expectedYaw = if ($null -eq $frontageDirection) { -1 } else { ((Get-CardinalYaw $frontageDirection) - (Get-CardinalYaw $localDirection) + 360) % 360 }
                if ($expectedYaw -ge 0 -and [int]$anchor.rotationYaw -eq $expectedYaw) {
                    $facesRoad = $true
                }
            }
        }
    }
    if (-not $facesRoad) {
        Add-ValidationError $errors "$coordinate macro does not face an adjacent road."
    }
}

if (@(Compare-Object $expectedTemplates @($actualTemplates | Sort-Object)).Count -gt 0) {
    Add-ValidationError $errors 'The fixture plan did not use exactly the seven requested templates.'
}
if (@($recipes.cellTemplateFilename | Sort-Object -Unique).Count -ne $expectedTemplates.Count) {
    Add-ValidationError $errors 'The fixture recipe filenames are not unique.'
}
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Multi-tile fixture planner validation failed with $($errors.Count) error(s)."
}

& $builderScript -WorldProfile preview -PlanData $planPath -CellDirectory $cellDirectory -Force -SettingsPath $SettingsPath | Out-Null
if (-not $?) { throw 'Multi-tile fixture VMF builder failed.' }
foreach ($recipe in $recipes) {
    $anchor = @($recipe.tilePlacements | Where-Object {
        (Test-PlacementEmitsInstance $_) -and ([int]$_.footprintWidth -gt 1 -or [int]$_.footprintHeight -gt 1)
    })[0]
    $footprint = Get-TemplateFootprint ([string]$anchor.template)
    $expectedInstanceCount = 25 - ($footprint.width * $footprint.height) + 1 + 24
    $vmfPath = Join-Path $cellDirectory $recipe.cellTemplateFilename
    $contents = Get-Content -Raw -LiteralPath $vmfPath
    if ([regex]::Matches($contents, '"classname" "func_instance"').Count -ne $expectedInstanceCount) {
        throw "$($recipe.cellTemplateFilename) has an incorrect VMF instance count."
    }
    $expectedX = [int]((([int]$anchor.tileX - 2) + (($footprint.width - 1) / 2.0)) * 640)
    $expectedY = [int](((2 - [int]$anchor.tileY) - (($footprint.height - 1) / 2.0)) * 640)
    $templateFilename = [regex]::Escape([System.IO.Path]::GetFileName([string]$anchor.template))
    $macroEntities = @([regex]::Matches($contents, '(?ms)^entity\r?\n\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline) | Where-Object { $_.Value -match $templateFilename })
    if ($macroEntities.Count -ne 1 -or $macroEntities[0].Value -notmatch [regex]::Escape(('"origin" "{0} {1} 0"' -f $expectedX, $expectedY))) {
        throw "$($recipe.cellTemplateFilename) does not emit one centered macro instance."
    }
}

& $mapRendererScript -WorldProfile preview -PlanData $planPath -DestinationDirectory $mapDirectory -SettingsPath $SettingsPath | Out-Null
if (-not $?) { throw 'Multi-tile fixture local-map renderer failed.' }
if (@(Get-ChildItem -LiteralPath $mapDirectory -Filter '*.png' -File).Count -ne $expectedTemplates.Count) {
    throw 'Multi-tile fixture local-map renderer did not create every recipe image.'
}

Write-Output "Multi-tile fixture passed: templates=$($expectedTemplates.Count); recipes=$($recipes.Count); output=$OutputRoot"