Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1')

function Get-ZMTransitionDeckHeight {
    param([string]$TemplatePath, [int]$TileSize)

    $mesh = [ZombieSim.Skybox.TileMeshBuilder]::Build((Get-Content -Raw -LiteralPath $TemplatePath), 0)
    if ($mesh.MissingWindings -gt 0) { throw "Transition deck source has missing face windings: $TemplatePath" }
    # Follow the continuous central lane, not a parapet, median or transverse support.
    $faces = @($mesh.UpFaces | Where-Object {
        $_.Material -notlike 'TOOLS/*' -and
        $_.MinX -le -64 -and $_.MaxX -ge 64 -and
        $_.MinY -le -($TileSize / 2 - 64) -and $_.MaxY -ge ($TileSize / 2 - 64)
    } | Sort-Object Z -Descending)
    if ($faces.Count -eq 0) { throw "Transition source has no continuous central road deck: $TemplatePath" }
    return [double]$faces[0].Z
}

function Get-ZMTransitionGateCoordinates {
    param([object]$Bounds, [string]$Direction, [double]$ElevationOffset = 0)

    $half = if ([int]$Bounds.revision -eq 2) { [double]$Bounds.traversableHalfExtent } else { [double]$Bounds.coreHalfExtent }
    $gate = $half - 32
    $arrival = $half - $(if ($Direction -eq 'N') { 128 } else { 64 })
    switch ($Direction) {
        'N' { $x = 0; $y = $gate; $ax = 0; $ay = $arrival; $yaw = 90 }
        'E' { $x = $gate; $y = 0; $ax = $arrival; $ay = 0; $yaw = 0 }
        'S' { $x = 0; $y = -$gate; $ax = 0; $ay = -$arrival; $yaw = 270 }
        'W' { $x = -$gate; $y = 0; $ax = -$arrival; $ay = 0; $yaw = 180 }
        default { throw "Unknown transition gate direction: $Direction" }
    }
    return [ordered]@{
        x = $x; y = $y; zOffset = $ElevationOffset; yaw = $yaw
        arrivalX = $ax; arrivalY = $ay; arrivalZ = 40 + $ElevationOffset
    }
}

function Set-ZMTransitionArrivalLandmarks {
    param([string]$Vmf, [object[]]$Gates)

    $writtenDirections = @{}
    foreach ($gate in $Gates) {
        if ($writtenDirections.ContainsKey($gate.directionName)) { continue }
        $writtenDirections[$gate.directionName] = $true
        $name = "$($gate.directionName.ToUpperInvariant())_ENTRANCE"
        $pattern = '(?s)("classname" "info_landmark"\s+"targetname" "' + [regex]::Escape($name) + '".*?"origin" ")[^"]+(")'
        if ([regex]::Matches($Vmf, $pattern).Count -ne 1) { throw "Expected one transition arrival landmark: $name" }
        $origin = '{0} {1} {2}' -f $gate.arrivalX, $gate.arrivalY, $gate.arrivalZ
        $Vmf = [regex]::Replace($Vmf, $pattern, '${1}' + $origin + '${2}')
    }
    return $Vmf
}

function Expand-ZMTransitionGateLanes {
    param([object[]]$Gates)

    $expanded = [System.Collections.Generic.List[object]]::new()
    foreach ($gate in $Gates) {
        $lanes = if ($null -ne $gate.PSObject.Properties['lanes']) { @($gate.lanes) } else { @() }
        $laneCount = @($lanes).Count
        $route = if ($null -ne $gate.PSObject.Properties['route']) { [string]$gate.route } else { 'motorway' }
        if ($route -notin @('road', 'motorway')) { throw "Unsupported transition gate route: $route" }
        if ($route -eq 'road' -or $laneCount -eq 0) {
            $expanded.Add($gate)
            continue
        }
        if ($laneCount -ne 2) { throw 'Motorway transition gates require two carriageways.' }

        for ($index = 0; $index -lt $laneCount; $index++) {
            $lane = $lanes[$index]
            $lateral = [double]$lane.lateral
            $width = [double]$lane.width
            if ([double]::IsNaN($lateral) -or [double]::IsInfinity($lateral) -or
                [double]::IsNaN($width) -or [double]::IsInfinity($width) -or $width -le 0) {
                throw 'Motorway transition lanes require finite lateral centres and positive widths.'
            }
            $laneGate = $gate.PSObject.Copy()
            $laneGate | Add-Member -NotePropertyName route -NotePropertyValue motorway -Force
            $laneGate | Add-Member -NotePropertyName laneIndex -NotePropertyValue ($index + 1) -Force
            $laneGate | Add-Member -NotePropertyName lateralMin -NotePropertyValue ($lateral - $width / 2) -Force
            $laneGate | Add-Member -NotePropertyName lateralMax -NotePropertyValue ($lateral + $width / 2) -Force
            $expanded.Add($laneGate)
        }
    }
    return @($expanded)
}

function Get-ZMTransitionTriggerBounds {
    param([object]$Gate)

    $measured = $null -ne $Gate.PSObject.Properties['lanes']
    $laneSpecific = $null -ne $Gate.PSObject.Properties['laneIndex']
    $min = if ($measured) { [double]$Gate.lateralMin } else { -128 }
    $max = if ($measured) { [double]$Gate.lateralMax } else { 128 }
    $road = $null -ne $Gate.PSObject.Properties['route'] -and $Gate.route -eq 'road'
    if ($measured) {
        $expectedLanes = if ($road) { 1 } else { 2 }
        if ($Gate.lanes.Count -ne $expectedLanes -or $min -ge $max -or
            [double]::IsNaN($min) -or [double]::IsInfinity($min) -or
            [double]::IsNaN($max) -or [double]::IsInfinity($max)) {
            throw 'Transition trigger requires finite extents for its route lane count.'
        }
        if ($laneSpecific -and ($road -or $Gate.laneIndex -notin @(1, 2))) {
            throw 'Lane-specific transition triggers are only valid for a motorway carriageway.'
        }
        if (-not $laneSpecific -and ($min -ge 0 -or $max -le 0)) {
            throw 'Combined transition triggers must straddle their route axis.'
        }
    }
    $range = switch ($Gate.direction) {
        'N' { @($min, $max, -32, 32) }
        'E' { @(-32, 32, -$max, -$min) }
        'S' { @(-$max, -$min, -32, 32) }
        'W' { @(-32, 32, $min, $max) }
        default { throw 'Invalid transition trigger direction.' }
    }
    return [pscustomobject]@{
        minX = $Gate.x + $range[0]; maxX = $Gate.x + $range[1]
        minY = $Gate.y + $range[2]; maxY = $Gate.y + $range[3]
        minZ = $Gate.zOffset; maxZ = 112 + $Gate.zOffset
    }
}

function Get-ZMTransitionBarricadeProps {
    param([object]$Gate)

    $props = @(
        @{ model = 'models/props/de_nuke/car_nuke_red.mdl'; across = -192; outward = -32; z = 44; yaw = 339 },
        @{ model = 'models/props/de_nuke/car_nuke_glass.mdl'; across = -192.499; outward = -30.74; z = 42.898; yaw = 339 },
        @{ model = 'models/props/de_nuke/car_nuke_glass.mdl'; across = 192.233; outward = -65.31; z = 42.898; yaw = 152 },
        @{ model = 'models/props/de_nuke/car_nuke_red.mdl'; across = 191.892; outward = -64; z = 44; yaw = 152 }
    )
    if ($null -ne $Gate.PSObject.Properties['laneIndex']) {
        if ($Gate.route -eq 'road' -or $Gate.lanes.Count -ne 2 -or $Gate.laneIndex -notin @(1, 2)) {
            throw 'Lane-specific barricades require one of two motorway carriageways.'
        }
        $firstIndex = if ($Gate.laneIndex -eq 1) { 0 } else { 2 }
        $props = @($props[$firstIndex], $props[$firstIndex + 1])
        $lane = $Gate.lanes[$Gate.laneIndex - 1]
        $baseCentre = if ($Gate.laneIndex -eq 1) { -192 } else { 192 }
        foreach ($prop in $props) {
            $prop.across += [double]$lane.lateral - $baseCentre
        }
        return $props
    }
    if ($null -ne $Gate.PSObject.Properties['lanes'] -and
        -not ($null -ne $Gate.PSObject.Properties['route'] -and $Gate.route -eq 'road')) {
        if ($Gate.lanes.Count -ne 2) { throw 'Measured barricades require two carriageway centres.' }
        foreach ($prop in $props) {
            $lane = if ($prop.across -lt 0) { $Gate.lanes[0] } else { $Gate.lanes[1] }
            $prop.across += [double]$lane.lateral - $(if ($prop.across -lt 0) { -192 } else { 192 })
        }
    }
    return $props
}

Export-ModuleMember -Function Get-ZMTransitionDeckHeight, Get-ZMTransitionGateCoordinates, Set-ZMTransitionArrivalLandmarks, Expand-ZMTransitionGateLanes, Get-ZMTransitionTriggerBounds, Get-ZMTransitionBarricadeProps
