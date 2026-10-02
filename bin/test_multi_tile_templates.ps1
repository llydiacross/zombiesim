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

function Get-TemplateRoadConnectionMarkers {
    param([string]$Template)

    $templatePath = Join-Path $projectRoot (Join-Path 'tiletemplates' $Template)
    $contents = Get-Content -Raw -LiteralPath $templatePath
    $markers = foreach ($match in [regex]::Matches($contents, '(?s)entity\s*\{\s*(?<body>.*?)\r?\n\}')) {
        $body = $match.Groups['body'].Value
        if ($body -notmatch '"classname"\s+"zn_road_connection"') { continue }
        $originMatch = [regex]::Match($body, '"origin"\s+"([^"]+)"')
        $typeMatch = [regex]::Match($body, '"connection_type"\s+"([^"]+)"')
        if (-not $originMatch.Success) {
            throw "Road connection marker in '$Template' must define origin."
        }
        $origin = @($originMatch.Groups[1].Value -split '\s+')
        if ($origin.Count -ne 3) { throw "Road connection marker in '$Template' has an invalid origin." }
        [pscustomobject]@{
            originX = [double]::Parse($origin[0], [Globalization.CultureInfo]::InvariantCulture)
            originY = [double]::Parse($origin[1], [Globalization.CultureInfo]::InvariantCulture)
            connectionType = if ($typeMatch.Success) { [string]$typeMatch.Groups[1].Value } else { 'none' }
        }
    }
    return @($markers)
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

    return @{ N = 0; E = 270; S = 180; W = 90 }[$Direction]
}

function Add-PhysicalRoadConnectionValidation {
    param(
        [object]$Recipe,
        [object]$Anchor,
        [object]$Footprint,
        [System.Collections.Generic.List[string]]$Errors,
        [hashtable]$Statistics
    )

    $markers = @(Get-TemplateRoadConnectionMarkers ([string]$Anchor.template) | Where-Object { $_.connectionType -ne 'none' })
    $matchedTargets = @{}
    $originX = (([int]$Anchor.tileX - 2) + (($Footprint.width - 1) / 2.0)) * 640
    $originY = ((2 - [int]$Anchor.tileY) - (($Footprint.height - 1) / 2.0)) * 640
    $radians = ([int]$Anchor.rotationYaw % 360) * [Math]::PI / 180.0
    $cosine = [Math]::Cos($radians)
    $sine = [Math]::Sin($radians)
    $junctionRoles = @('building_road_junction', 'landmark_carpark_junction', 'landmark_road_junction')
    $junctionTemplates = @{
        t_junction = 'roads/tile_road_tjunction.vmf'
        bus = 'roads/tile_road_bus.vmf'
        driveway = 'roads/tile_road_driveway.vmf'
    }

    foreach ($marker in $markers) {
        $edge = if ([Math]::Abs($marker.originY - ($Footprint.height * 320.0)) -le 0.5) {
            'N'
        } elseif ([Math]::Abs($marker.originX - ($Footprint.width * 320.0)) -le 0.5) {
            'E'
        } elseif ([Math]::Abs($marker.originY + ($Footprint.height * 320.0)) -le 0.5) {
            'S'
        } elseif ([Math]::Abs($marker.originX + ($Footprint.width * 320.0)) -le 0.5) {
            'W'
        } else {
            $null
        }
        if ($null -eq $edge) {
            Add-ValidationError $Errors "$($Recipe.cellTemplateFilename) $($Anchor.template) road marker is not on a footprint edge."
            continue
        }
        $normal = switch ($edge) {
            'N' { [pscustomobject]@{ x = 0.0; y = 1.0 } }
            'E' { [pscustomobject]@{ x = 1.0; y = 0.0 } }
            'S' { [pscustomobject]@{ x = 0.0; y = -1.0 } }
            'W' { [pscustomobject]@{ x = -1.0; y = 0.0 } }
        }
        $markerWorldX = $originX + ($marker.originX * $cosine) - ($marker.originY * $sine)
        $markerWorldY = $originY + ($marker.originX * $sine) + ($marker.originY * $cosine)
        $roadWorldX = $markerWorldX + 320.0 * (($normal.x * $cosine) - ($normal.y * $sine))
        $roadWorldY = $markerWorldY + 320.0 * (($normal.x * $sine) + ($normal.y * $cosine))
        $targetTileX = [int][Math]::Round(($roadWorldX / 640.0) + 2)
        $targetTileY = [int][Math]::Round(2 - ($roadWorldY / 640.0))
        $target = @($Recipe.tilePlacements | Where-Object {
            [int]$_.tileX -eq $targetTileX -and [int]$_.tileY -eq $targetTileY
        } | Select-Object -First 1)[0]
        $Statistics.checked++
        if ($null -eq $target) {
            Add-ValidationError $Errors "$($Recipe.cellTemplateFilename) $($Anchor.template) marker does not land on a planned road at ($targetTileX,$targetTileY)."
            continue
        }
        $targetKey = "$targetTileX,$targetTileY"
        if ($matchedTargets.ContainsKey($targetKey)) {
            Add-ValidationError $Errors "$($Recipe.cellTemplateFilename) maps multiple road markers to ($targetTileX,$targetTileY)."
            continue
        }
        $matchedTargets[$targetKey] = $true

        if ($target.role -in $junctionRoles) {
            $Statistics.junctions++
            if ($target.template -ne $junctionTemplates[$marker.connectionType]) {
                Add-ValidationError $Errors "$($Recipe.cellTemplateFilename) marker type '$($marker.connectionType)' selected '$($target.template)' at ($targetTileX,$targetTileY)."
                continue
            }
            if ($marker.connectionType -eq 't_junction') {
                $junctionRadians = ([int]$target.rotationYaw % 360) * [Math]::PI / 180.0
                $stemX = -[Math]::Sin($junctionRadians)
                $stemY = [Math]::Cos($junctionRadians)
                $frontX = -(($normal.x * $cosine) - ($normal.y * $sine))
                $frontY = -(($normal.x * $sine) + ($normal.y * $cosine))
                if ([Math]::Abs($stemX - $frontX) -gt 0.001 -or [Math]::Abs($stemY - $frontY) -gt 0.001) {
                    Add-ValidationError $Errors "$($Recipe.cellTemplateFilename) T-junction at ($targetTileX,$targetTileY) points away from its building."
                }
            }
        } elseif ([string]$target.template -like 'roads/tile_motorway*.vmf') {
            $Statistics.motorways++
        } elseif ([string]$target.role -eq 'path') {
            $Statistics.paths++
        } else {
            Add-ValidationError $Errors "$($Recipe.cellTemplateFilename) marker targets unsupported $($target.role) '$($target.template)' at ($targetTileX,$targetTileY)."
        }
    }
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
$markerStatistics = @{ checked = 0; junctions = 0; motorways = 0; paths = 0 }
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
    Add-PhysicalRoadConnectionValidation $recipe $anchor $footprint $errors $markerStatistics
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
$cityPlanPath = Join-Path $OutputRoot 'preview_template_plan.json'
$cityListPath = Join-Path $OutputRoot 'preview_required_cell_vmfs.txt'
$cityMapDataPath = Join-Path $PSScriptRoot 'preview_grid_24x24_seed_1337.json'
& $plannerScript -WorldProfile preview -MapData $cityMapDataPath -Output $cityPlanPath -ListOutput $cityListPath -CellDirectory $cellDirectory -SettingsPath $SettingsPath | Out-Null
if (-not $?) { throw 'Full preview planner regression failed.' }
$cityPlan = Get-Content -Raw -LiteralPath $cityPlanPath | ConvertFrom-Json
$cityMarkerStatistics = @{ checked = 0; junctions = 0; motorways = 0; paths = 0 }
foreach ($recipe in @($cityPlan.cells)) {
    foreach ($anchor in @($recipe.tilePlacements | Where-Object {
        (Test-PlacementEmitsInstance $_) -and ([int]$_.footprintWidth -gt 1 -or [int]$_.footprintHeight -gt 1) -and
        $_.template -like 'buildings/*'
    })) {
        $footprint = [pscustomobject]@{ width = [int]$anchor.footprintWidth; height = [int]$anchor.footprintHeight }
        Add-PhysicalRoadConnectionValidation $recipe $anchor $footprint $errors $cityMarkerStatistics
    }
}
if ($cityMarkerStatistics.checked -eq 0) {
    Add-ValidationError $errors 'The current preview plan contains no marked multi-tile road connections to validate.'
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

Write-Output "Multi-tile frontage passed: fixtureTemplates=$($expectedTemplates.Count); fixtureRecipes=$($recipes.Count); cityMarkers=$($cityMarkerStatistics.checked); junctions=$($cityMarkerStatistics.junctions); motorwayFrontages=$($cityMarkerStatistics.motorways); output=$OutputRoot"