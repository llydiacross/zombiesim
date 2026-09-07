param(
    [string]$PlanData = '',
    [string]$DestinationDirectory = '',
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DirectionCode {
    param([string]$Name)

    switch ($Name.ToLowerInvariant()) {
        'north' { return 'N' }
        'east' { return 'E' }
        'south' { return 'S' }
        'west' { return 'W' }
        default { throw "Unknown cardinal direction '$Name'." }
    }
}

function Get-TopologyDirections {
    param([object]$Recipe)

    $topology = [string]$Recipe.topology
    $orientation = [string]$Recipe.orientation
    if ($topology -like '*-crossjunction') { return @('N', 'E', 'S', 'W') }
    if ($topology -like '*-straight') {
        if ($orientation -eq 'vertical') { return @('N', 'S') }
        return @('E', 'W')
    }
    if ($topology -like '*-corner') {
        return @($orientation.Split('-') | ForEach-Object { Get-DirectionCode $_ })
    }
    if ($topology -like '*-tjunction') {
        $missingDirection = Get-DirectionCode $orientation.Substring('missing-'.Length)
        return @('N', 'E', 'S', 'W' | Where-Object { $_ -ne $missingDirection })
    }
    if ($topology -like '*-deadend') { return @(Get-DirectionCode $orientation) }
    return @()
}

function Draw-CornerLane {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string[]]$Directions,
        [int]$CenterCoordinate,
        [int]$ImageSize,
        [int]$Padding,
        [System.Drawing.Pen]$LanePen
    )

    $verticalDirection = @($Directions | Where-Object { $_ -in @('N', 'S') } | Select-Object -First 1)[0]
    $horizontalDirection = @($Directions | Where-Object { $_ -in @('E', 'W') } | Select-Object -First 1)[0]
    if ([string]::IsNullOrWhiteSpace($verticalDirection) -or [string]::IsNullOrWhiteSpace($horizontalDirection)) { return }

    $turnRadius = 18
    $curveFactor = 0.55228475
    $verticalSign = if ($verticalDirection -eq 'N') { -1 } else { 1 }
    $horizontalSign = if ($horizontalDirection -eq 'W') { -1 } else { 1 }
    $verticalEndpoint = if ($verticalDirection -eq 'N') { $Padding } else { $ImageSize - $Padding }
    $horizontalEndpoint = if ($horizontalDirection -eq 'W') { $Padding } else { $ImageSize - $Padding }
    $curveStart = [System.Drawing.PointF]::new($CenterCoordinate, $CenterCoordinate + ($verticalSign * $turnRadius))
    $curveEnd = [System.Drawing.PointF]::new($CenterCoordinate + ($horizontalSign * $turnRadius), $CenterCoordinate)
    $firstControl = [System.Drawing.PointF]::new($CenterCoordinate, $curveStart.Y - ($verticalSign * $curveFactor * $turnRadius))
    $secondControl = [System.Drawing.PointF]::new($curveEnd.X - ($horizontalSign * $curveFactor * $turnRadius), $CenterCoordinate)
    $verticalEdge = [System.Drawing.PointF]::new($CenterCoordinate, $verticalEndpoint)
    $horizontalEdge = [System.Drawing.PointF]::new($horizontalEndpoint, $CenterCoordinate)

    $Graphics.DrawLine($LanePen, $verticalEdge, $curveStart)
    $Graphics.DrawBezier($LanePen, $curveStart, $firstControl, $secondControl, $curveEnd)
    $Graphics.DrawLine($LanePen, $curveEnd, $horizontalEdge)
}

function Get-PlacementDirection {
    param(
        [int]$TileX,
        [int]$TileY,
        [int]$CenterTile
    )

    if ($TileX -eq $CenterTile -and $TileY -lt $CenterTile) { return 'N' }
    if ($TileX -gt $CenterTile -and $TileY -eq $CenterTile) { return 'E' }
    if ($TileX -eq $CenterTile -and $TileY -gt $CenterTile) { return 'S' }
    if ($TileX -lt $CenterTile -and $TileY -eq $CenterTile) { return 'W' }
    return $null
}

function Get-RouteEndpoint {
    param(
        [string]$Direction,
        [int]$CenterCoordinate,
        [int]$ImageSize,
        [int]$Padding,
        [int]$TileSize,
        [bool]$StopsAtAdjacentTile
    )

    $endpointHorizontal = $CenterCoordinate
    $endpointVertical = $CenterCoordinate
    $distance = if ($StopsAtAdjacentTile) { $TileSize } else { $ImageSize - $Padding - $CenterCoordinate }
    switch ($Direction) {
        'N' { $endpointVertical = $CenterCoordinate - $distance }
        'E' { $endpointHorizontal = $CenterCoordinate + $distance }
        'S' { $endpointVertical = $CenterCoordinate + $distance }
        'W' { $endpointHorizontal = $CenterCoordinate - $distance }
    }
    return [pscustomobject]@{ Horizontal = $endpointHorizontal; Vertical = $endpointVertical }
}

function Draw-DeadEndMarker {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$CenterHorizontal,
        [int]$CenterVertical,
        [System.Drawing.Pen]$MarkerPen
    )

    $markerRadius = 9
    $Graphics.DrawLine($MarkerPen, $CenterHorizontal - $markerRadius, $CenterVertical - $markerRadius, $CenterHorizontal + $markerRadius, $CenterVertical + $markerRadius)
    $Graphics.DrawLine($MarkerPen, $CenterHorizontal - $markerRadius, $CenterVertical + $markerRadius, $CenterHorizontal + $markerRadius, $CenterVertical - $markerRadius)
}

function Get-EnvironmentColor {
    param([string]$Profile)

    switch ($Profile) {
        'grassland' { return [System.Drawing.Color]::FromArgb(75, 108, 65) }
        'sandy' { return [System.Drawing.Color]::FromArgb(155, 124, 70) }
        'dirt' { return [System.Drawing.Color]::FromArgb(110, 83, 61) }
        'parkland' { return [System.Drawing.Color]::FromArgb(61, 112, 78) }
        'recreation' { return [System.Drawing.Color]::FromArgb(62, 119, 95) }
        'commercial' { return [System.Drawing.Color]::FromArgb(76, 100, 126) }
        'financial' { return [System.Drawing.Color]::FromArgb(76, 92, 126) }
        'industrial' { return [System.Drawing.Color]::FromArgb(107, 96, 76) }
        'radioactive' { return [System.Drawing.Color]::FromArgb(92, 119, 55) }
        'destroyed' { return [System.Drawing.Color]::FromArgb(98, 78, 72) }
        'safe_zone' { return [System.Drawing.Color]::FromArgb(66, 117, 101) }
        default { return [System.Drawing.Color]::FromArgb(76, 92, 79) }
    }
}

function Get-LandmarkLabel {
    param([string]$Landmark)

    $labels = @{
        'Airport' = 'AIR'; 'Army Base' = 'ARM'; 'Bank' = 'BNK'; 'Bunker' = 'BNK'
        'Church' = 'CH'; 'Fire Station' = 'FIR'; 'Hospital' = 'HSP'; 'Laboratory' = 'LAB'
        'Leisure' = 'LEI'; 'Market' = 'MKT'; 'Park' = 'PRK'; 'Petrol Station' = 'GAS'
        'Police Station' = 'POL'; 'The Epicenter' = 'EPI'
    }
    if ($labels.ContainsKey($Landmark)) { return $labels[$Landmark] }
    $compactName = $Landmark -replace '[^A-Za-z0-9]', ''
    return $compactName.Substring(0, [Math]::Min(3, $compactName.Length)).ToUpperInvariant()
}

function Get-LandmarkMarkerColor {
    param(
        [object]$Recipe,
        [string]$Landmark
    )

    $markerProperty = $Recipe.PSObject.Properties['landmarkMarkers']
    if ($null -ne $markerProperty) {
        $marker = @($markerProperty.Value | Where-Object { [string]$_.name -eq $Landmark } | Select-Object -First 1)[0]
        $colorProperty = if ($null -eq $marker) { $null } else { $marker.PSObject.Properties['color'] }
        if ($null -ne $colorProperty -and $null -ne $colorProperty.Value) {
            $color = $colorProperty.Value
            return [System.Drawing.Color]::FromArgb([int]$color.alpha, [int]$color.red, [int]$color.green, [int]$color.blue)
        }
    }
    return [System.Drawing.Color]::FromArgb(206, 151, 54)
}

function Get-PlacementFootprint {
    param([object]$Placement)

    $widthProperty = $Placement.PSObject.Properties['footprintWidth']
    $heightProperty = $Placement.PSObject.Properties['footprintHeight']
    return [pscustomobject]@{
        width = if ($null -eq $widthProperty) { 1 } else { [int]$widthProperty.Value }
        height = if ($null -eq $heightProperty) { 1 } else { [int]$heightProperty.Value }
    }
}

function Test-PlacementEmitsInstance {
    param([object]$Placement)

    $property = $Placement.PSObject.Properties['emitsInstance']
    return $null -eq $property -or [bool]$property.Value
}

function Test-LandmarkAnchor {
    param([object]$Placement)

    $role = [string]$Placement.role
    return (Test-PlacementEmitsInstance $Placement) -and
        ($role -eq 'landmark' -or ($role -like 'landmark_*' -and $role -notlike 'landmark_carpark*'))
}

Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
$generatorSettings = $worldGenerationProfile.Settings
$commercialTemplatePattern = [string]$generatorSettings.cellPlanning.templatePatterns.commercial
if ([string]::IsNullOrWhiteSpace($commercialTemplatePattern)) { throw 'cellPlanning.templatePatterns.commercial is required for local map markers.' }
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a <profile>_grid_*_template_plan.json path.'
}
if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    $DestinationDirectory = Join-Path $projectRoot (Join-Path (Join-Path 'content/materials/worlds' $worldGenerationProfile.Name) 'cells')
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
if ($plan.schemaVersion -lt 4) {
    throw 'The template plan must use schema version 4 or later to provide local map tile placements.'
}
$recipeCells = @($plan.cells | Group-Object cellTemplateFilename | Sort-Object Name | ForEach-Object { $_.Group[0] })
if ($recipeCells.Count -eq 0) { throw 'The template plan does not select any city recipes.' }
foreach ($recipe in $recipeCells) {
    $tileGridSize = [int]$recipe.tileGridSize
    if ($tileGridSize -lt 1 -or @($recipe.tilePlacements).Count -ne ($tileGridSize * $tileGridSize)) {
        throw "City recipe '$($recipe.cellTemplateFilename)' does not contain a complete local map tile grid. Re-run plan_cell_templates.ps1."
    }
}

if ($WhatIf) {
    Write-Output "WhatIf: render $($recipeCells.Count) local recipe map image(s) in: $DestinationDirectory"
    return
}

[System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null
Get-ChildItem -LiteralPath $DestinationDirectory -Filter '*.png' -File | Remove-Item -Force

$tileSize = 48
$padding = 0
$roadRoles = @('road', 'road_center', 'bridge_road', 'onramp_road', 'bridge_ramp_deadend', 'special_landmark_road_cap')
$buildingBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(78, 76, 72))
$decorationBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(101, 128, 87))
$carparkBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(135, 146, 153))
$roadBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(52, 59, 64))
$pathBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(165, 170, 162))
$motorwayBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(235, 35, 90, 190))
$landmarkBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(206, 151, 54))
$gridPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(115, 17, 20, 22), 1)
$roadPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(52, 59, 64), [single]30)
$roadLanePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 239, 189, 55), [single]3)
$roadLanePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
$carparkSpacePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(230, 243, 245, 242), 1)
$motorwayPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(235, 35, 90, 190), [single]34)
$motorwayLanePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 245, 245, 245), [single]3)
$motorwayLanePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
$fadedMotorwayPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(150, 35, 90, 190), [single]34)
$fadedMotorwayLanePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(210, 245, 245, 245), [single]3)
$fadedMotorwayLanePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
$blockadePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(218, 70, 46), [single]6)
$landmarkOutlinePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(235, 228, 232, 235), [single]2)
$landmarkFont = [System.Drawing.Font]::new('Arial', 9, [System.Drawing.FontStyle]::Bold)
$landmarkFormat = [System.Drawing.StringFormat]::new()
$landmarkFormat.Alignment = [System.Drawing.StringAlignment]::Center
$landmarkFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

try {
    foreach ($recipe in $recipeCells) {
        $tileGridSize = [int]$recipe.tileGridSize
        $imageSize = ($padding * 2) + ($tileGridSize * $tileSize)
        $backgroundColor = Get-EnvironmentColor ([string]$recipe.environmentProfile)
        $backgroundBrush = [System.Drawing.SolidBrush]::new($backgroundColor)
        $bitmap = [System.Drawing.Bitmap]::new($imageSize, $imageSize)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear($backgroundColor)
            $isMotorway = [string]$recipe.topology -like 'motorway-*'
            $showLocationMarkers = -not $isMotorway -or [string]$recipe.transportFeature -like 'bridge-*' -or [string]$recipe.transportFeature -like 'onramp-*'
            foreach ($placement in @($recipe.tilePlacements)) {
                $tileLeft = $padding + ([int]$placement.tileX * $tileSize)
                $tileTop = $padding + ([int]$placement.tileY * $tileSize)
                $role = [string]$placement.role
                $tileBrush = if ($role -eq 'motorway_bridge_deadend') {
                    $motorwayBrush
                } elseif ($role -in $roadRoles -or $role -like 'bridge-*' -or $role -like 'onramp-*') {
                    if ($isMotorway -and $role -in @('road', 'road_center')) { $motorwayBrush } else { $roadBrush }
                } elseif ($role -eq 'building' -or $role -eq 'building_occupied') { $buildingBrush
                } elseif ($role -eq 'decoration') { $decorationBrush
                } elseif ($role -eq 'path') { $pathBrush
                } elseif ($role -like '*carpark*') { $carparkBrush
                } elseif ($role -eq 'landmark' -or ($role -like 'landmark_*' -and $role -notlike 'landmark_carpark*')) { $landmarkBrush
                } else { $backgroundBrush }
                $graphics.FillRectangle($tileBrush, $tileLeft, $tileTop, $tileSize, $tileSize)
            }

            $centerCoordinate = $padding + (($tileGridSize * $tileSize) / 2)
            $topologyDirections = @(Get-TopologyDirections $recipe)
            $activeEntrances = @($recipe.activeEntrances | ForEach-Object { [string]$_ })
            $centerTile = [int][Math]::Floor($tileGridSize / 2)
            $motorwayDeadEndDirections = @($recipe.tilePlacements |
                Where-Object { $_.role -eq 'motorway_bridge_deadend' } |
                ForEach-Object { Get-PlacementDirection ([int]$_.tileX) ([int]$_.tileY) $centerTile } |
                Where-Object { $null -ne $_ })
            $roadDeadEndDirections = @($recipe.tilePlacements |
                Where-Object { $_.role -eq 'bridge_ramp_deadend' } |
                ForEach-Object { Get-PlacementDirection ([int]$_.tileX) ([int]$_.tileY) $centerTile } |
                Where-Object { $null -ne $_ })
            $cappedDeadEndDirections = @($motorwayDeadEndDirections + $roadDeadEndDirections | Sort-Object -Unique)
            $motorwayDirections = if ($isMotorway) { @($topologyDirections + $motorwayDeadEndDirections | Sort-Object -Unique) } else { @() }
            $roadDirections = @(($topologyDirections + $activeEntrances + $roadDeadEndDirections) | Where-Object { $_ -in @('N', 'E', 'S', 'W') -and $_ -notin $motorwayDirections } | Sort-Object -Unique)
            $routeDirections = @($roadDirections + $motorwayDirections | Sort-Object -Unique)
            $usesCurvedLane = [string]$recipe.topology -like '*-corner'
            $hasMotorwayBridge = $isMotorway -and [string]$recipe.transportFeature -in @('bridge-horizontal', 'bridge-vertical')
            foreach ($routeType in @('road', 'motorway')) {
                $directionsToDraw = if ($routeType -eq 'road') { $roadDirections } else { $motorwayDirections }
                foreach ($direction in $directionsToDraw) {
                    $routeEndpoint = Get-RouteEndpoint $direction $centerCoordinate $imageSize $padding $tileSize ($direction -in $cappedDeadEndDirections)
                    if ($routeType -eq 'motorway') {
                        $motorwayRoutePen = if ($hasMotorwayBridge) { $fadedMotorwayPen } else { $motorwayPen }
                        $motorwayRouteLanePen = if ($hasMotorwayBridge) { $fadedMotorwayLanePen } else { $motorwayLanePen }
                        $graphics.DrawLine($motorwayRoutePen, $centerCoordinate, $centerCoordinate, $routeEndpoint.Horizontal, $routeEndpoint.Vertical)
                        if (-not ($usesCurvedLane -and $direction -in $topologyDirections)) {
                            $graphics.DrawLine($motorwayRouteLanePen, $centerCoordinate, $centerCoordinate, $routeEndpoint.Horizontal, $routeEndpoint.Vertical)
                        }
                    } else {
                        $graphics.DrawLine($roadPen, $centerCoordinate, $centerCoordinate, $routeEndpoint.Horizontal, $routeEndpoint.Vertical)
                        if (-not ($usesCurvedLane -and $direction -in $topologyDirections)) {
                            $graphics.DrawLine($roadLanePen, $centerCoordinate, $centerCoordinate, $routeEndpoint.Horizontal, $routeEndpoint.Vertical)
                        }
                    }
                }
            }
            if ($usesCurvedLane) {
                $cornerLanePen = if ($topologyDirections[0] -in $motorwayDirections) { $motorwayLanePen } else { $roadLanePen }
                Draw-CornerLane $graphics $topologyDirections $centerCoordinate $imageSize $padding $cornerLanePen
            }
            if ([string]$recipe.topology -like '*-deadend') {
                $deadEndMarkerLocations = if ($cappedDeadEndDirections.Count -gt 0) {
                    @($cappedDeadEndDirections | ForEach-Object { Get-RouteEndpoint $_ $centerCoordinate $imageSize $padding $tileSize $true })
                } else {
                    @([pscustomobject]@{ Horizontal = $centerCoordinate; Vertical = $centerCoordinate })
                }
                foreach ($markerLocation in $deadEndMarkerLocations) {
                    Draw-DeadEndMarker $graphics $markerLocation.Horizontal $markerLocation.Vertical $blockadePen
                }
            }

            for ($gridIndex = 1; $gridIndex -lt $tileGridSize; $gridIndex++) {
                $gridCoordinate = $padding + ($gridIndex * $tileSize)
                $graphics.DrawLine($gridPen, $gridCoordinate, $padding, $gridCoordinate, $imageSize - $padding)
                $graphics.DrawLine($gridPen, $padding, $gridCoordinate, $imageSize - $padding, $gridCoordinate)
            }

            $carparkLanePlacements = @($recipe.tilePlacements | Where-Object {
                [string]$_.role -match '(?:^|_)carpark_lane(?:_endcap)?_(?:east|west)$'
            })
            foreach ($placement in $carparkLanePlacements) {
                $tileLeft = $padding + ([int]$placement.tileX * $tileSize)
                $tileTop = $padding + ([int]$placement.tileY * $tileSize)
                $spaceWidth = [int](($tileSize - 12) / 3)
                for ($spaceIndex = 0; $spaceIndex -lt 3; $spaceIndex++) {
                    $spaceLeft = $tileLeft + 6 + ($spaceIndex * $spaceWidth)
                    $graphics.DrawRectangle($carparkSpacePen, $spaceLeft, $tileTop + 8, $spaceWidth - 3, $tileSize - 16)
                }
            }

            $namedLandmarks = @(if ($showLocationMarkers) {
                @($recipe.landmarks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and $_ -ne 'none' })
            } else { @() })
            $landmarkPlacements = @($recipe.tilePlacements | Where-Object { Test-LandmarkAnchor $_ } | Sort-Object tileY, tileX)
            for ($landmarkIndex = 0; $landmarkIndex -lt $namedLandmarks.Count; $landmarkIndex++) {
                if ($landmarkPlacements.Count -eq 0) { break }
                $placement = $landmarkPlacements[$landmarkIndex % $landmarkPlacements.Count]
                $footprint = Get-PlacementFootprint $placement
                $tileLeft = $padding + ([int]$placement.tileX * $tileSize)
                $tileTop = $padding + ([int]$placement.tileY * $tileSize)
                $markerBounds = [System.Drawing.RectangleF]::new($tileLeft + 4, $tileTop + 4, ($footprint.width * $tileSize) - 8, ($footprint.height * $tileSize) - 8)
                $markerBrush = [System.Drawing.SolidBrush]::new((Get-LandmarkMarkerColor $recipe ([string]$namedLandmarks[$landmarkIndex])))
                $graphics.FillRectangle($markerBrush, $markerBounds)
                $graphics.DrawRectangle($landmarkOutlinePen, $tileLeft + 4, $tileTop + 4, ($footprint.width * $tileSize) - 9, ($footprint.height * $tileSize) - 9)
                $graphics.DrawString((Get-LandmarkLabel ([string]$namedLandmarks[$landmarkIndex])), $landmarkFont, [System.Drawing.Brushes]::White, $markerBounds, $landmarkFormat)
                $markerBrush.Dispose()
            }

            $commercialPlacements = @(if ($showLocationMarkers) {
                @($recipe.tilePlacements | Where-Object {
                    $_.role -eq 'building' -and (Test-PlacementEmitsInstance $_) -and [string]$_.template -match $commercialTemplatePattern
                } | Sort-Object tileY, tileX)
            } else { @() })
            foreach ($placement in $commercialPlacements) {
                $footprint = Get-PlacementFootprint $placement
                $tileLeft = $padding + ([int]$placement.tileX * $tileSize)
                $tileTop = $padding + ([int]$placement.tileY * $tileSize)
                $markerBounds = [System.Drawing.RectangleF]::new($tileLeft + 4, $tileTop + 4, ($footprint.width * $tileSize) - 8, ($footprint.height * $tileSize) - 8)
                $graphics.FillRectangle($landmarkBrush, $markerBounds)
                $graphics.DrawRectangle($landmarkOutlinePen, $tileLeft + 4, $tileTop + 4, ($footprint.width * $tileSize) - 9, ($footprint.height * $tileSize) - 9)
                $graphics.DrawString('COM', $landmarkFont, [System.Drawing.Brushes]::White, $markerBounds, $landmarkFormat)
            }

            $outputFilename = [System.IO.Path]::ChangeExtension([string]$recipe.cellTemplateFilename, '.png')
            $bitmap.Save((Join-Path $DestinationDirectory $outputFilename), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
            $backgroundBrush.Dispose()
        }
    }
} finally {
    $buildingBrush, $decorationBrush, $carparkBrush, $roadBrush, $pathBrush, $motorwayBrush, $landmarkBrush | ForEach-Object Dispose
    $gridPen, $roadPen, $roadLanePen, $carparkSpacePen, $motorwayPen, $motorwayLanePen, $fadedMotorwayPen, $fadedMotorwayLanePen, $blockadePen, $landmarkOutlinePen | ForEach-Object Dispose
    $landmarkFont.Dispose()
    $landmarkFormat.Dispose()
}

Write-Output "Rendered $($recipeCells.Count) local recipe map image(s): $DestinationDirectory"