Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scenery_density.psm1') -Force

function Get-ZMSceneryWallTemplateSelection {
    param(
        [object]$Recipe,
        [string[]]$Templates,
        [int]$MapSeed,
        [string]$Ring,
        [string]$Slot,
        [string]$Role,
        [bool]$RouteAdjacentWall
    )

    $density = Get-ZMStoredSceneryDensity $Recipe
    if ($null -eq $density) { return $null }
    $landmarks = @($Recipe.landmarks) -join '+'
    $cellPolicy = '{0}|{1}|{2}|{3}|{4}' -f `
        $Recipe.environmentProfile, $Recipe.topology, $Recipe.orientation, $density.sceneryDensityTier, $landmarks
    $selectionContext = @{
        Seed = $MapSeed
        CellPolicy = $cellPolicy
        Ring = $Ring
        Slot = $Slot
        Role = $Role
        Variant = [int]$Recipe.cellVariant
    }
    $tierHash = Get-ZMScenerySelectionHash @selectionContext -Purpose tier
    $templateHash = Get-ZMScenerySelectionHash @selectionContext -Purpose template
    $context = 'cell={0},{1} ring={2} slot={3} role={4}' -f $Recipe.x, $Recipe.y, $Ring, $Slot, $Role
    $selection = Select-ZMSceneryTemplate $Templates $density.sceneryDensityTier ([int]($tierHash % 100)) $templateHash $context -RouteAdjacentWall:$RouteAdjacentWall -Required
    return [pscustomobject]@{
        template = [string]$selection.template
        selection = [ordered]@{
            policyVersion = 1
            source = $density.sceneryDensitySource
            status = $selection.status
            zoneTier = $selection.zoneTier
            targetTier = $selection.targetTier
            template = [string]$selection.template
            actualTag = $selection.actualTag
            densityException = $null
            routeAdjacentWall = $selection.routeAdjacentWall
            excluded = @($selection.excluded)
        }
    }
}

function Get-ZMPlacementField {
    param([object]$Placement, [string]$Name)

    if ($Placement -is [System.Collections.IDictionary]) {
        if ($Placement.Contains($Name)) { return $Placement[$Name] }
        return $null
    }
    $property = $Placement.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ZMRouteFootprintSlots {
    # Every tile occupied by a road, bridge or motorway corridor, including non-emitting occupied
    # records and motorway inspection leases. Carpark lanes, entrances and endcaps are not corridors.
    param([object[]]$Placements, [object[]]$Leases = @(), [string[]]$LeaseRings = @())

    $routeRoles = @('motorway_assembly', 'motorway_occupied', 'motorway_external_occupied')
    $slots = [ordered]@{}
    foreach ($placement in @($Placements)) {
        if ($null -eq $placement) { continue }
        $role = [string](Get-ZMPlacementField $placement 'role')
        $template = [string](Get-ZMPlacementField $placement 'template')
        if (-not ($role -in $routeRoles -or $template -match '^roads[\\/]')) { continue }
        $width = Get-ZMPlacementField $placement 'footprintWidth'
        $height = Get-ZMPlacementField $placement 'footprintHeight'
        $width = if ($null -eq $width) { 1 } else { [Math]::Max(1, [int]$width) }
        $height = if ($null -eq $height) { 1 } else { [Math]::Max(1, [int]$height) }
        $emits = Get-ZMPlacementField $placement 'emitsInstance'
        # Non-emitting occupied records describe one slot of an owner already listed elsewhere.
        if ($null -ne $emits -and -not [bool]$emits) { $width = 1; $height = 1 }
        for ($offsetY = 0; $offsetY -lt $height; $offsetY++) {
            for ($offsetX = 0; $offsetX -lt $width; $offsetX++) {
                $tileX = [int](Get-ZMPlacementField $placement 'tileX') + $offsetX
                $tileY = [int](Get-ZMPlacementField $placement 'tileY') + $offsetY
                $slots["$tileX,$tileY"] = [pscustomobject]@{ tileX = $tileX; tileY = $tileY }
            }
        }
    }
    foreach ($lease in @($Leases)) {
        if ($null -eq $lease) { continue }
        if ($LeaseRings.Count -gt 0 -and [string](Get-ZMPlacementField $lease 'ring') -notin $LeaseRings) { continue }
        $tileX = [int](Get-ZMPlacementField $lease 'tileX')
        $tileY = [int](Get-ZMPlacementField $lease 'tileY')
        $slots["$tileX,$tileY"] = [pscustomobject]@{ tileX = $tileX; tileY = $tileY }
    }
    return @($slots.Values)
}

function Get-ZMRecipeRouteLeases {
    param([object]$Recipe)

    $inspection = Get-ZMPlacementField $Recipe 'motorwayCellInspection'
    $normal = Get-ZMPlacementField $Recipe 'motorwayAssembly'
    if ($null -ne $inspection -and $null -ne $normal) { throw 'A motorway recipe cannot own both inspection and normal leases.' }
    if ($null -ne $normal) {
        $schema = Get-ZMPlacementField $normal 'schemaVersion'
        $status = Get-ZMPlacementField $normal 'status'
        if (-not (($schema -eq 1 -and $status -eq 'normal_reservations_travel_pending') -or
            ($schema -eq 2 -and $status -eq 'normal_complex_travel_pending'))) {
            throw 'Unsupported normal motorway route-lease contract.'
        }
        return @(Get-ZMPlacementField $normal 'leases')
    }
    if ($null -eq $inspection) { return @() }
    $leases = Get-ZMPlacementField $inspection 'leases'
    if ($null -eq $leases) { return @() }
    return @($leases)
}

function Get-ZMRoadAdjacentWallPool {
    param([string[]]$Templates, [object[]]$RouteSlots, [int]$TileX, [int]$TileY)

    $adjacent = @($RouteSlots | Where-Object { [Math]::Abs([int]$_.tileX - $TileX) + [Math]::Abs([int]$_.tileY - $TileY) -eq 1 }).Count -gt 0
    if (-not $adjacent) { return $Templates }
    $eligible = @($Templates | Where-Object { $_ -notmatch '_\d+aaa\.vmf$' })
    if ($eligible.Count -eq 0) { throw "No non-aaa wall template is available beside a route at $TileX,$TileY." }
    return $eligible
}

function Get-ZMOuterEdgeRoadTemplates {
    param(
        [object[]]$BorderPlacements,
        [int]$TileGridSize,
        [string]$RoadStraightTemplate,
        [string]$MotorwayStraightTemplate,
        [string]$BridgeRoadTemplate
    )

    $roadTemplates = @{}
    $routeSources = @($RoadStraightTemplate, $MotorwayStraightTemplate, $BridgeRoadTemplate)
    foreach ($placement in $BorderPlacements) {
        $isTransitionRoad = [string]$placement.targetname -like 'zm_transition_road_*'
        if (-not ($isTransitionRoad -or [string]$placement.template -in $routeSources)) { continue }
        $side = if ($placement.tileY -eq -1) { 'N' } elseif ($placement.tileY -eq $TileGridSize) { 'S' } elseif ($placement.tileX -eq -1) { 'W' } else { 'E' }
        # A bridge deck must continue at deck height even when its slot also carries a ramp/transition name;
        # only gate-road variants are flattened to the plain straight road.
        $roadTemplates[$side] = if ([string]$placement.template -eq $BridgeRoadTemplate) { $BridgeRoadTemplate } elseif ($isTransitionRoad) { $RoadStraightTemplate } else { [string]$placement.template }
    }
    return $roadTemplates
}

function Get-ZMOuterEdgePlacements {
    param(
        [object]$Recipe,
        [int]$TileGridSize,
        [hashtable]$Settings,
        [object[]]$BorderPlacements,
        [hashtable]$WaterSides,
        [hashtable]$RoadTemplates,
        [int]$MapSeed = 0
    )

    if (-not $Settings.ContainsKey('enabled') -or -not $Settings.enabled) { return @() }
    $walls = @($Settings.wallVariationTemplates)
    $corner = [string]$Settings.cornerTemplate
    $profile = ([string]$Recipe.environmentProfile).ToLowerInvariant()
    if ($Settings.ContainsKey('profileTemplates') -and $Settings.profileTemplates.ContainsKey($profile)) {
        $pool = $Settings.profileTemplates[$profile]
        if ($pool.ContainsKey('wallVariationTemplates') -and @($pool.wallVariationTemplates).Count -gt 0) { $walls = @($pool.wallVariationTemplates) }
        if ($pool.ContainsKey('cornerTemplate') -and -not [string]::IsNullOrWhiteSpace($pool.cornerTemplate)) { $corner = [string]$pool.cornerTemplate }
    }
    if ($walls.Count -eq 0 -or [string]::IsNullOrWhiteSpace($corner)) { throw 'Outer edges require a default wall pool and corner template.' }

    $borderSlots = @{}
    foreach ($placement in $BorderPlacements) { $borderSlots["$($placement.tileX),$($placement.tileY)"] = $placement }
    $routeSlots = @(Get-ZMRouteFootprintSlots $BorderPlacements (Get-ZMRecipeRouteLeases $Recipe) @('border', 'outer'))
    $sideYaw = @{ N = 180; E = 90; S = 0; W = 270 }
    $cornerYaw = @{ NW = 180; NE = 90; SE = 0; SW = 270 }
    $center = [int][Math]::Floor($TileGridSize / 2)
    $result = [System.Collections.Generic.List[object]]::new()
    for ($y = -2; $y -le $TileGridSize + 1; $y++) {
        for ($x = -2; $x -le $TileGridSize + 1; $x++) {
            $vertical = if ($y -eq -2) { 'N' } elseif ($y -eq $TileGridSize + 1) { 'S' } else { '' }
            $horizontal = if ($x -eq -2) { 'W' } elseif ($x -eq $TileGridSize + 1) { 'E' } else { '' }
            if (-not ($vertical -or $horizontal)) { continue }
            $wallSelection = $null
            $side = if ($vertical) { $vertical } else { $horizontal }
            $bx = [Math]::Max(-1, [Math]::Min($TileGridSize, $x))
            $by = [Math]::Max(-1, [Math]::Min($TileGridSize, $y))
            # Project suppressed entrance slots outward; never fill their authored footprint.
            if (-not $borderSlots.ContainsKey("$bx,$by")) { continue }
            if ($vertical -and $horizontal) {
                if ($WaterSides.ContainsKey($vertical) -or $WaterSides.ContainsKey($horizontal)) { continue }
                $template = $corner
                $yaw = $cornerYaw["$vertical$horizontal"]
                $kind = 'corner'
            } else {
                $isRoute = $RoadTemplates.ContainsKey($side) -and $(if ($vertical) { $x -eq $center } else { $y -eq $center })
                if ($WaterSides.ContainsKey($side) -and -not $isRoute) { continue }
                if ($isRoute) {
                    $template = [string]$RoadTemplates[$side]
                    $yaw = if ($vertical) { 0 } else { 90 }
                    $kind = 'corridor'
                } else {
                    $hash = ([int64]$Recipe.placementSeed * 2654435761) -bxor ([int64]$x * 73856093) -bxor ([int64]$y * 19349663)
                    $hash = $hash -bxor ($hash -shr 15)
                    $adjacentSlots = @($routeSlots)
                    # Include the outer continuation itself when checking its two flanking wall slots.
                    if ($RoadTemplates.ContainsKey($side) -and $(if ($vertical) { [Math]::Abs($x - $center) -eq 1 } else { [Math]::Abs($y - $center) -eq 1 })) {
                        $adjacentSlots += [pscustomobject]@{ tileX = $(if ($vertical) { $center } else { $x }); tileY = $(if ($vertical) { $y } else { $center }) }
                    }
                    $routeAdjacentWall = @($adjacentSlots | Where-Object {
                        [Math]::Abs([int]$_.tileX - $x) + [Math]::Abs([int]$_.tileY - $y) -eq 1
                    }).Count -gt 0
                    $eligibleWalls = @(Get-ZMRoadAdjacentWallPool $walls $adjacentSlots $x $y)
                    $wallSelection = Get-ZMSceneryWallTemplateSelection $Recipe $eligibleWalls $MapSeed 'outer' "$x,$y" 'outer_wall' $routeAdjacentWall
                    $template = if ($null -ne $wallSelection) {
                        [string]$wallSelection.template
                    } else {
                        [string]$eligibleWalls[[int]([Math]::Abs($hash) % $eligibleWalls.Count)]
                    }
                    $yaw = $sideYaw[$side]
                    $kind = 'wall'
                }
            }
            $placement = [ordered]@{
                tileX = $x; tileY = $y; template = $template; rotationYaw = $yaw
                targetname = "zm_outer_$kind`_$x`_$y"
            }
            if ($kind -eq 'wall' -and $null -ne $wallSelection -and $null -ne $wallSelection.selection) {
                $placement.sceneryDensitySelection = $wallSelection.selection
            }
            $result.Add($placement)
        }
    }
    return @($result.ToArray())
}

function Expand-ZMOuterEdgeShell {
    param([string]$Vmf, [System.Collections.IDictionary]$Bounds, [hashtable]$OceanSides = @{})

    Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
    foreach ($side in $OceanSides.Keys) {
        if ($side -notin @('N', 'E', 'S', 'W')) { throw "Invalid shell ocean side: $side" }
    }
    $root = [ZombieSim.Skybox.KeyValuesParser]::Parse($Vmf)
    $world = $root.Child('world')
    if ($null -eq $world -or $Bounds.tileSize -ne 640 -or $Bounds.coreHalfExtent -ne 1600) {
        throw 'Outer-edge shell expansion currently requires the authored 5x5, 640-unit base cell.'
    }
    $skyCount = 0
    $clipCount = 0
    foreach ($solid in $world.Children | Where-Object Name -eq 'solid') {
        $materials = @($solid.Children | Where-Object Name -eq 'side' | ForEach-Object { $_.Get('material').ToUpperInvariant() } | Sort-Object -Unique)
        $mapping = @{}
        $preservedSides = @{}
        if ($materials.Count -eq 1 -and $materials[0] -eq 'TOOLS/TOOLSSKYBOX') {
            $mapping = @{ '2240' = 3072; '2304' = 3136 }
            $preservedSides = $OceanSides
            $skyCount++
        } elseif ($materials.Count -eq 1 -and $materials[0] -eq 'TOOLS/TOOLSCLIP') {
            $mapping = @{ '1984' = 2240; '2048' = 2304 }
            $clipCount++
        } elseif ($materials.Count -eq 1 -and $materials[0] -eq 'HALFLIFE/BLACK') {
            $mapping = @{ '2240' = 3072; '2304' = 3136 }
            $preservedSides = $OceanSides
        } else {
            throw "Unexpected base shell solid $($solid.Get('id')); inspect its geometry before expanding it."
        }
        Set-ZMShellCoordinates $solid $mapping $preservedSides
    }
    if ($skyCount -ne 5 -or $clipCount -ne 4) { throw 'Outer-edge base must contain five sky seals and four perimeter clips.' }
    return Convert-ZMVmfNodeToText $root ''
}

function Set-ZMShellCoordinates {
    param([object]$Node, [hashtable]$Mapping, [hashtable]$PreservedSides)

    for ($i = 0; $i -lt $Node.Keys.Count; $i++) {
        $entry = $Node.Keys[$i]
        if ($entry.Key -notin @('plane', 'v')) { continue }
        $value = [regex]::Replace($entry.Value, '[-\d.]+\s+[-\d.]+\s+[-\d.]+', {
            param($match)
            $parts = $match.Value -split '\s+'
            for ($axis = 0; $axis -lt 2; $axis++) {
                $number = [double]::Parse($parts[$axis], [Globalization.CultureInfo]::InvariantCulture)
                $side = if ($axis -eq 0) { if ($number -lt 0) { 'W' } else { 'E' } } else { if ($number -lt 0) { 'S' } else { 'N' } }
                if ($PreservedSides.ContainsKey($side)) { continue }
                $key = [Math]::Abs($number).ToString([Globalization.CultureInfo]::InvariantCulture)
                if ($Mapping.ContainsKey($key)) { $parts[$axis] = ([Math]::Sign($number) * $Mapping[$key]).ToString([Globalization.CultureInfo]::InvariantCulture) }
            }
            return $parts -join ' '
        })
        $Node.Keys[$i] = [System.Collections.Generic.KeyValuePair[string,string]]::new($entry.Key, $value)
    }
    foreach ($child in $Node.Children) { Set-ZMShellCoordinates $child $Mapping $PreservedSides }
}

function Convert-ZMVmfNodeToText {
    param([object]$Node, [string]$Indent)

    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Node.Name -ne 'root') {
        $lines.Add("$Indent$($Node.Name)")
        $lines.Add("$Indent{")
        $Indent += '    '
    }
    foreach ($entry in $Node.Keys) { $lines.Add(('{0}"{1}" "{2}"' -f $Indent, $entry.Key, $entry.Value)) }
    foreach ($child in $Node.Children) { $lines.Add((Convert-ZMVmfNodeToText $child $Indent).TrimEnd("`r", "`n")) }
    if ($Node.Name -ne 'root') { $lines.Add($Indent.Substring(4) + '}') }
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

Export-ModuleMember -Function Get-ZMSceneryWallTemplateSelection, Get-ZMRouteFootprintSlots, Get-ZMRecipeRouteLeases, Get-ZMRoadAdjacentWallPool, Get-ZMOuterEdgeRoadTemplates, Get-ZMOuterEdgePlacements, Expand-ZMOuterEdgeShell
