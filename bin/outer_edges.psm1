Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        [hashtable]$RoadTemplates
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
    $sideYaw = @{ N = 180; E = 90; S = 0; W = 270 }
    $cornerYaw = @{ NW = 180; NE = 90; SE = 0; SW = 270 }
    $center = [int][Math]::Floor($TileGridSize / 2)
    $result = [System.Collections.Generic.List[object]]::new()
    for ($y = -2; $y -le $TileGridSize + 1; $y++) {
        for ($x = -2; $x -le $TileGridSize + 1; $x++) {
            $vertical = if ($y -eq -2) { 'N' } elseif ($y -eq $TileGridSize + 1) { 'S' } else { '' }
            $horizontal = if ($x -eq -2) { 'W' } elseif ($x -eq $TileGridSize + 1) { 'E' } else { '' }
            if (-not ($vertical -or $horizontal)) { continue }
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
                    $template = [string]$walls[[int]([Math]::Abs($hash) % $walls.Count)]
                    $yaw = $sideYaw[$side]
                    $kind = 'wall'
                }
            }
            $result.Add([ordered]@{
                tileX = $x; tileY = $y; template = $template; rotationYaw = $yaw
                targetname = "zm_outer_$kind`_$x`_$y"
            })
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

Export-ModuleMember -Function Get-ZMOuterEdgeRoadTemplates, Get-ZMOuterEdgePlacements, Expand-ZMOuterEdgeShell
