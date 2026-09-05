param(
    [string]$MapData = '',
    [string]$TemplateDirectory = '',
    [string]$CellDirectory = '',
    [ValidateRange(3, 99)]
    [int]$CellTileSize = 5,
    [string]$Output = '',
    [string]$ListOutput = '',
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MapData)) {
    $MapData = @(Get-ChildItem -Path $PSScriptRoot -Filter 'map_grid_*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path $MapData)) {
    throw 'A generated map JSON file is required. Pass -MapData with the manifest path.'
}
if ([string]::IsNullOrWhiteSpace($TemplateDirectory)) {
    $TemplateDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'tiletemplates'
}
if (-not (Test-Path $TemplateDirectory)) {
    throw "Template directory was not found: $TemplateDirectory"
}
if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'maps\src'
}
if (-not (Test-Path $CellDirectory)) {
    throw "Cell source directory was not found: $CellDirectory"
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MapData)
    $Output = Join-Path $PSScriptRoot ("{0}_template_plan.json" -f $mapBaseName)
}
if ([string]::IsNullOrWhiteSpace($ListOutput)) {
    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MapData)
    $ListOutput = Join-Path $PSScriptRoot ("{0}_required_cell_vmfs.txt" -f $mapBaseName)
}

$map = Get-Content -Raw $MapData | ConvertFrom-Json
if ($map.schemaVersion -lt 2) {
    throw 'The map manifest must use schema version 2 or later so environment tags are available.'
}

$templateFiles = @{}
$TemplateDirectory = (Resolve-Path $TemplateDirectory).Path.TrimEnd('\')
Get-ChildItem -Path $TemplateDirectory -Filter '*.vmf' -File -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($TemplateDirectory.Length).TrimStart('\').Replace('\', '/')
    $templateFiles[$relativePath.ToLowerInvariant()] = $relativePath
}
if ($templateFiles.Count -eq 0) {
    throw "No VMF templates were found in $TemplateDirectory"
}
$buildingTemplates = @($templateFiles.Values | Where-Object { $_ -like 'buildings/tile_building_*.vmf' } | Sort-Object)
$warehouseTemplates = @($templateFiles.Values | Where-Object { $_ -like 'buildings/tile_warehouse_*.vmf' } | Sort-Object)
$carparkTemplates = @($templateFiles.Values | Where-Object { $_ -like 'carparks/tile_carpark_[a-e].vmf' } | Sort-Object)

function Get-CellConnections {
    param([object]$Cell)

    $connections = if ($Cell.highway.present) {
        @($Cell.highway.connections)
    } elseif ($Cell.road.present) {
        @($Cell.road.connections)
    } else {
        @()
    }
    return @($connections | Where-Object { $_ -in @('N', 'E', 'S', 'W') })
}

function Get-ActiveEntrances {
    param([object]$Cell)

    $connections = @(Get-CellConnections $Cell)
    $blockades = if ($Cell.highway.present) { @() } else { @($Cell.road.blockades) }
    return @($connections | Where-Object { $_ -notin $blockades } | Sort-Object)
}

function Get-CellTopology {
    param([object]$Cell)

    if ($Cell.highway.present) {
        $prefix = 'motorway'
    } elseif ($Cell.road.present) {
        $prefix = 'road'
    } else {
        return 'open'
    }
    $connections = @(Get-CellConnections $Cell)

    switch ($connections.Count) {
        4 { return "$prefix-crossjunction" }
        3 { return "$prefix-tjunction" }
        2 {
            if (($connections -contains 'N' -and $connections -contains 'S') -or ($connections -contains 'E' -and $connections -contains 'W')) {
                return "$prefix-straight"
            }
            return "$prefix-corner"
        }
        1 { return "$prefix-deadend" }
        default { return "$prefix-isolated" }
    }
}

function Get-CellOrientation {
    param(
        [object]$Cell,
        [string]$Topology
    )

    if ($Topology -eq 'open') { return 'none' }
    $connections = @(Get-CellConnections $Cell)
    $cardinals = @('N', 'E', 'S', 'W')
    $directionNames = @{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }
    $presentDirections = @($cardinals | Where-Object { $connections -contains $_ })

    if ($Topology -like '*-crossjunction') { return 'all' }
    if ($Topology -like '*-straight') {
        if ($connections -contains 'N' -and $connections -contains 'S') { return 'vertical' }
        return 'horizontal'
    }
    if ($Topology -like '*-corner') {
        return ($presentDirections | ForEach-Object { $directionNames[$_] }) -join '-'
    }
    if ($Topology -like '*-tjunction') {
        $missingDirection = @($cardinals | Where-Object { $connections -notcontains $_ })[0]
        return "missing-$($directionNames[$missingDirection])"
    }
    if ($Topology -like '*-deadend') {
        return $directionNames[$presentDirections[0]]
    }
    return 'none'
}

function Get-EnvironmentProfile {
    param([object]$Cell)

    $tags = @($Cell.environment.tags)
    foreach ($tag in @('radioactive', 'safe_zone', 'fortified', 'military', 'medical', 'emergency_services', 'religious', 'service_station', 'financial', 'commercial', 'recreation', 'parkland')) {
        if ($tags -contains $tag) { return $tag }
    }
    if ($Cell.building.present) { return 'settlement' }
    return $Cell.environment.terrain
}

function Get-TerrainTemplate {
    param([string]$Terrain)

    switch ($Terrain) {
        'grassland' { return 'terrain/tile_grass.vmf' }
        'sandy' { return 'terrain/tile_sand.vmf' }
        default { return 'terrain/tile_dirt.vmf' }
    }
}

function Get-GenericTopologyTemplate {
    param([string]$Topology)

    switch ($Topology) {
        'road-straight' { return 'tile_road.vmf' }
        'road-corner' { return 'tile_road_corner.vmf' }
        'road-tjunction' { return 'tile_road_tjunction.vmf' }
        'road-crossjunction' { return 'tile_road_crossjunction.vmf' }
        'road-deadend' { return 'tile_road_deadend.vmf' }
        'motorway-straight' { return 'tile_motorway.vmf' }
        'motorway-corner' { return 'tile_motorway_corner.vmf' }
        'motorway-tjunction' { return 'tile_motorway_tjunction.vmf' }
        'motorway-crossjunction' { return 'tile_motorway_crossroads.vmf' }
        'motorway-deadend' { return 'tile_motorway_deadend.vmf' }
        default { return $null }
    }
}

function Get-LinearTopologyTemplate {
    param([string]$Topology)

    if ($Topology -like 'motorway-*') { return 'tile_motorway.vmf' }
    return 'tile_road.vmf'
}

function Get-LayoutRotation {
    param(
        [string]$Topology,
        [string]$Orientation
    )

    if ($Topology -like '*-deadend') {
        switch ($Orientation) {
            'south' { return 0 }
            'east' { return 90 }
            'north' { return 180 }
            'west' { return 270 }
        }
    }
    if ($Topology -like '*-straight') {
        if ($Orientation -eq 'vertical') { return 0 }
        return 90
    }
    if ($Topology -like '*-corner') {
        switch ($Orientation) {
            'east-south' { return 0 }
            'north-east' { return 90 }
            'north-west' { return 180 }
            'south-west' { return 270 }
        }
    }
    if ($Topology -like '*-tjunction') {
        switch ($Orientation) {
            'missing-south' { return 0 }
            'missing-west' { return 90 }
            'missing-north' { return 180 }
            'missing-east' { return 270 }
        }
    }
    return 0
}

function Get-BuildingDensity {
    param(
        [string]$Terrain,
        [string]$Profile
    )

    switch ($Profile) {
        'grassland' { return 0.30 }
        'sandy' { return 0.40 }
        'dirt' { return 0.50 }
        'parkland' { return 0.25 }
        'recreation' { return 0.40 }
        'settlement' { return 0.70 }
        default {
            switch ($Terrain) {
                'grassland' { return 0.55 }
                'sandy' { return 0.60 }
                default { return 0.65 }
            }
        }
    }
}

function Get-RecipePlacementSeed {
    param(
        [string]$Profile,
        [string]$Topology,
        [string]$Orientation,
        [string[]]$Landmarks
    )

    $signature = "$Profile|$Topology|$Orientation|$($Landmarks -join '+')"
    [int64]$seed = 17
    foreach ($character in $signature.ToCharArray()) {
        $seed = (($seed * 31) + [int][char]$character) % 2147483647
    }
    return [int]$seed
}

function Get-CellTilePlacements {
    param(
        [object]$Cell,
        [string]$TerrainTemplate,
        [string[]]$BuildingTemplates,
        [string]$LandmarkTemplate,
        [string[]]$Landmarks,
        [string]$Profile,
        [string[]]$CarparkTemplates,
        [int]$PlacementSeed,
        [string]$Topology,
        [string]$Orientation,
        [int]$TileGridSize,
        [hashtable]$AvailableTemplates
    )

    $center = [int][Math]::Floor($TileGridSize / 2)
    $placements = @{}
    for ($tileY = 0; $tileY -lt $TileGridSize; $tileY++) {
        for ($tileX = 0; $tileX -lt $TileGridSize; $tileX++) {
            $placements["$tileX,$tileY"] = [pscustomobject]@{
                tileX = $tileX
                tileY = $tileY
                template = $TerrainTemplate
                rotationYaw = 0
                role = 'terrain'
            }
        }
    }

    $connections = @(Get-CellConnections $Cell)
    if ($connections.Count -gt 0) {
        $roadTemplate = Resolve-Template @((Get-LinearTopologyTemplate $Topology), $TerrainTemplate) $AvailableTemplates
        foreach ($direction in $connections) {
            switch ($direction) {
                'N' { $coordinates = @(0..($center - 1) | ForEach-Object { [pscustomobject]@{ tileX = $center; tileY = $_ } }); $rotationYaw = 0 }
                'E' { $coordinates = @(($center + 1)..($TileGridSize - 1) | ForEach-Object { [pscustomobject]@{ tileX = $_; tileY = $center } }); $rotationYaw = 90 }
                'S' { $coordinates = @(($center + 1)..($TileGridSize - 1) | ForEach-Object { [pscustomobject]@{ tileX = $center; tileY = $_ } }); $rotationYaw = 0 }
                'W' { $coordinates = @(0..($center - 1) | ForEach-Object { [pscustomobject]@{ tileX = $_; tileY = $center } }); $rotationYaw = 90 }
            }
            foreach ($coordinate in $coordinates) {
                $placements["$($coordinate.tileX),$($coordinate.tileY)"] = [pscustomobject]@{
                    tileX = $coordinate.tileX
                    tileY = $coordinate.tileY
                    template = $roadTemplate
                    rotationYaw = $rotationYaw
                    role = 'road'
                }
            }
        }

        $centerCandidates = @((Get-GenericTopologyTemplate $Topology), (Get-LinearTopologyTemplate $Topology), $TerrainTemplate)
        $centerTemplate = Resolve-Template $centerCandidates $AvailableTemplates
        $placements["$center,$center"] = [pscustomobject]@{
            tileX = $center
            tileY = $center
            template = $centerTemplate
            rotationYaw = Get-LayoutRotation $Topology $Orientation
            role = 'road_center'
        }
    }

    if ($BuildingTemplates.Count -gt 0) {
        $buildingDensity = Get-BuildingDensity $Cell.environment.terrain $Profile
        foreach ($terrainPlacement in @($placements.Values | Where-Object { $_.role -eq 'terrain' } | Sort-Object tileY, tileX)) {
            $densityRoll = [Math]::Abs(($PlacementSeed + ([int]$terrainPlacement.tileX * 11) + ([int]$terrainPlacement.tileY * 17)) % 100)
            if ($densityRoll -ge [int]($buildingDensity * 100)) { continue }
            $templateIndex = (([int]$terrainPlacement.tileX * 11) + ([int]$terrainPlacement.tileY * 17)) % $BuildingTemplates.Count
            $placements["$($terrainPlacement.tileX),$($terrainPlacement.tileY)"] = [pscustomobject]@{
                tileX = $terrainPlacement.tileX
                tileY = $terrainPlacement.tileY
                template = $BuildingTemplates[$templateIndex]
                rotationYaw = 0
                role = 'building'
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LandmarkTemplate)) {
        $landmarkPlacement = @($placements.Values | Where-Object { $_.role -in @('building', 'terrain') } | Sort-Object tileY, tileX | Select-Object -First 1)[0]
        if ($null -ne $landmarkPlacement) {
            $placements["$($landmarkPlacement.tileX),$($landmarkPlacement.tileY)"] = [pscustomobject]@{
                tileX = $landmarkPlacement.tileX
                tileY = $landmarkPlacement.tileY
                template = $LandmarkTemplate
                rotationYaw = 0
                role = 'landmark'
            }
        }
    }

    $hasNamedLandmark = @($Landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0
    $carparkRoll = $PlacementSeed % 100
    if ($Topology -eq 'road-straight' -and -not $hasNamedLandmark -and $CarparkTemplates.Count -gt 0 -and $carparkRoll -lt 35) {
        $carparkCandidates = @($placements.Values | Where-Object { $_.role -eq 'building' } | Sort-Object tileY, tileX)
        if ($carparkCandidates.Count -gt 0) {
            $carparkIndex = $PlacementSeed % $carparkCandidates.Count
            $carparkTemplateIndex = [int]([Math]::Floor($PlacementSeed / 7) % $CarparkTemplates.Count)
            $carparkPlacement = $carparkCandidates[$carparkIndex]
            $placements["$($carparkPlacement.tileX),$($carparkPlacement.tileY)"] = [pscustomobject]@{
                tileX = $carparkPlacement.tileX
                tileY = $carparkPlacement.tileY
                template = $CarparkTemplates[$carparkTemplateIndex]
                rotationYaw = Get-LayoutRotation $Topology $Orientation
                role = 'carpark'
            }
        }
    }

    return @($placements.Values | Sort-Object tileY, tileX)
}

function Get-ProfileFallbackTemplates {
    param(
        [string]$Profile,
        [int]$CellX,
        [int]$CellY
    )

    $specialPatterns = switch ($Profile) {
        'radioactive' { @('buildings/tile_laboratory*.vmf', 'buildings/tile_research*.vmf'); break }
        'safe_zone' { @('buildings/tile_safehouse*.vmf', 'buildings/tile_den*.vmf'); break }
        'fortified' { @('buildings/tile_bunker*.vmf'); break }
        'military' { @('buildings/tile_military*.vmf', 'buildings/tile_army*.vmf', 'buildings/tile_barracks*.vmf'); break }
        'medical' { @('buildings/tile_hospital*.vmf', 'buildings/tile_medical*.vmf', 'buildings/tile_clinic*.vmf'); break }
        'emergency_services' { @('buildings/tile_fire*.vmf', 'buildings/tile_police*.vmf', 'buildings/tile_emergency*.vmf'); break }
        'service_station' { @('buildings/tile_service-station*.vmf', 'buildings/tile_service_station*.vmf', 'buildings/tile_petrol*.vmf'); break }
        'financial' { @('buildings/tile_bank*.vmf', 'buildings/tile_financial*.vmf'); break }
        'commercial' { @('tile_commercial_*.vmf'); break }
        'recreation' { @('buildings/tile_recreation*.vmf', 'buildings/tile_leisure*.vmf'); break }
        'parkland' { @('buildings/tile_park*.vmf'); break }
        default { @() }
    }
    $specialTemplates = @()
    foreach ($specialPattern in $specialPatterns) {
        $specialTemplates += @($templateFiles.Values | Where-Object { $_ -like $specialPattern } | Sort-Object)
    }
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in (@($specialTemplates) + @($warehouseTemplates) + @($buildingTemplates))) {
        if (-not $candidates.Contains($candidate)) {
            $candidates.Add($candidate)
        }
    }
    return @($candidates)
}

function Get-LandmarkTemplate {
    param(
        [string[]]$Landmarks,
        [hashtable]$AvailableTemplates
    )

    foreach ($landmark in $Landmarks) {
        $templatePattern = switch ($landmark) {
            'Church' { '*/tile_church*.vmf'; break }
            'Hospital' { '*/tile_hospital*.vmf'; break }
            'Police' { '*/tile_police*.vmf'; break }
            'Fire' { '*/tile_fire*.vmf'; break }
            'Petrol Station' { '*/tile_petrol*.vmf'; break }
            'Bank' { '*/tile_bank*.vmf'; break }
            'Army Base' { '*/tile_army*.vmf'; break }
            'Laboratory' { '*/tile_laboratory*.vmf'; break }
            'Bunker' { '*/tile_bunker*.vmf'; break }
            default { $null }
        }
        if ($null -eq $templatePattern) { continue }
        $matches = @($AvailableTemplates.Values | Where-Object { $_ -like $templatePattern -or $_ -like $templatePattern.TrimStart('*/') } | Sort-Object)
        if ($matches.Count -gt 0) { return $matches[0] }
    }
    return $null
}

function Get-CellFilename {
    param(
        [string]$Profile,
        [string]$Topology,
        [string]$Orientation,
        [string[]]$Landmarks
    )

    $layout = if ($Orientation -eq 'none') { $Topology } else { "$Topology-$Orientation" }
    return 'zn_{0}_{1}_{2}.vmf' -f `
        (ConvertTo-FilenamePart $Profile), (ConvertTo-FilenamePart $layout), `
        (($Landmarks | ForEach-Object { ConvertTo-FilenamePart $_ }) -join '+')
}

function ConvertTo-FilenamePart {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'none' }
    return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-') -replace '(^-)|(-$)', '')
}

function Get-CellLandmarks {
    param([object]$Cell)

    $landmarks = @($Cell.landmarks | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($landmarks.Count -eq 0) { return @('none') }
    return $landmarks
}

function Get-CellFeatures {
    param(
        [object]$Cell,
        [string]$Terrain,
        [string]$Profile,
        [string]$Topology
    )

    $redundantTags = @($Terrain, $Profile)
    if ($Topology -like 'motorway-*') {
        $redundantTags += 'highway'
    } elseif ($Topology -like 'road-*') {
        $redundantTags += 'roadside'
    }
    $features = @($Cell.environment.tags | Where-Object { $_ -notin $redundantTags })
    if ($Cell.building.present) { $features += 'building' }
    if ($Cell.deadZone) { $features += 'dead_zone' }
    if ($null -ne $Cell.safeZone) { $features += 'safe_zone' }
    if ($null -ne $Cell.metro.stop) { $features += 'metro_stop' }
    if (@($Cell.metro.lines).Count -gt 0) { $features += 'metro_route' }
    return @($features | Sort-Object -Unique)
}

function Resolve-Template {
    param(
        [string[]]$Candidates,
        [hashtable]$AvailableTemplates
    )

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $candidateKey = $candidate.ToLowerInvariant()
        if ($AvailableTemplates.ContainsKey($candidateKey)) {
            return $AvailableTemplates[$candidateKey]
        }
    }
    throw "No fallback template exists. Candidates: $($Candidates -join ', ')"
}

$planCells = @()
foreach ($cell in $map.cells) {
    $topology = Get-CellTopology $cell
    $orientation = Get-CellOrientation $cell $topology
    $profile = Get-EnvironmentProfile $cell
    $terrainTemplate = Get-TerrainTemplate $cell.environment.terrain
    $genericTopologyTemplate = Get-GenericTopologyTemplate $topology
    $landmarks = @(Get-CellLandmarks $cell)
    $buildingCandidates = @(Get-ProfileFallbackTemplates $profile ([int]$cell.x) ([int]$cell.y))
    $landmarkTemplate = Get-LandmarkTemplate $landmarks $templateFiles
    $placementSeed = Get-RecipePlacementSeed $profile $topology $orientation $landmarks

    $desiredTemplate = if ($topology -eq 'open' -and $profile -in @('grassland', 'sandy', 'dirt')) {
        if ($buildingCandidates.Count -gt 0) { $buildingCandidates[0] } else { $terrainTemplate }
    } elseif ($profile -in @('grassland', 'sandy', 'dirt', 'settlement') -and $null -ne $genericTopologyTemplate) {
        $genericTopologyTemplate
    } elseif ($topology -eq 'open' -and $buildingCandidates.Count -gt 0) {
        $buildingCandidates[0]
    } else {
        "tile_{0}_{1}.vmf" -f $profile, $topology
    }

    $selectedTemplate = Resolve-Template @(
        $desiredTemplate,
        $genericTopologyTemplate,
        $buildingCandidates,
        $terrainTemplate
    ) $templateFiles
    $exactTemplateExists = $templateFiles.ContainsKey($desiredTemplate.ToLowerInvariant())
    $features = @(Get-CellFeatures $cell $cell.environment.terrain $profile $topology)
    $activeEntrances = @(Get-ActiveEntrances $cell)
    $tilePlacements = @(Get-CellTilePlacements $cell $terrainTemplate $buildingCandidates $landmarkTemplate $landmarks $profile $carparkTemplates $placementSeed $topology $orientation $CellTileSize $templateFiles)
    $cellTemplateFilename = Get-CellFilename $profile $topology $orientation $landmarks
    $cellTemplatePath = Join-Path $CellDirectory $cellTemplateFilename

    $planCells += [pscustomobject]@{
        x = [int]$cell.x
        y = [int]$cell.y
        worldX = [int]$cell.worldX
        worldY = [int]$cell.worldY
        topology = $topology
        orientation = $orientation
        activeEntrances = $activeEntrances
        environmentProfile = $profile
        environmentTags = @($cell.environment.tags)
        landmarks = $landmarks
        features = $features
        cellTemplateFilename = $cellTemplateFilename
        cellTemplatePath = $cellTemplatePath
        cellTemplateExists = Test-Path $cellTemplatePath
        desiredChunkTemplate = $desiredTemplate
        selectedChunkTemplate = $selectedTemplate
        buildingTemplates = $buildingCandidates
        landmarkTemplate = $landmarkTemplate
        placementSeed = $placementSeed
        chunkFallbackUsed = -not $exactTemplateExists
        tileGridSize = $CellTileSize
        tilePlacements = $tilePlacements
    }
}

$requiredCellFiles = @($planCells | Group-Object cellTemplateFilename | Sort-Object Name | ForEach-Object {
    $representative = $_.Group[0]
    [pscustomobject]@{
        filename = $_.Name
        environmentProfile = $representative.environmentProfile
        topology = $representative.topology
        orientation = $representative.orientation
        landmarks = $representative.landmarks
        cellCount = $_.Count
        cellTemplateExists = @($_.Group | Where-Object cellTemplateExists).Count -eq $_.Count
        cells = @($_.Group | ForEach-Object { [pscustomobject]@{ x = $_.x; y = $_.y } })
        selectedChunkTemplates = @($_.Group.selectedChunkTemplate | Sort-Object -Unique)
        buildingTemplates = @($_.Group.buildingTemplates | Sort-Object -Unique)
        landmarkTemplates = @($_.Group.landmarkTemplate | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        tileCount = $CellTileSize * $CellTileSize
        tileTemplates = @($_.Group.tilePlacements | ForEach-Object { $_.template } | Sort-Object -Unique)
    }
})
$missingCellFiles = @($requiredCellFiles | Where-Object { -not $_.cellTemplateExists })

$plan = [ordered]@{
    schemaVersion = 2
    mapData = [System.IO.Path]::GetFileName($MapData)
    cellDirectory = $CellDirectory
    chunkTemplateDirectory = $TemplateDirectory
    availableChunkTemplates = @($templateFiles.Values | Sort-Object)
    cellTileGridSize = $CellTileSize
    selectedCellCount = $planCells.Count
    requiredCellCount = $requiredCellFiles.Count
    missingCellCount = $missingCellFiles.Count
    requiredCellList = $ListOutput
    requiredCellFiles = $requiredCellFiles
    missingCellFiles = $missingCellFiles
    cells = $planCells
}

if (-not $ListOnly) {
    [System.IO.File]::WriteAllText($Output, ($plan | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllLines($ListOutput, [string[]]@($requiredCellFiles | ForEach-Object { $_.filename }), [System.Text.UTF8Encoding]::new($false))
    Write-Output "Wrote template plan: $Output"
    Write-Output "Wrote required cell list: $ListOutput"
}

$requiredCellFiles | ForEach-Object { $_.filename }
