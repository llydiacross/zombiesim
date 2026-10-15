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

    foreach ($gate in $Gates) {
        $name = "$($gate.directionName.ToUpperInvariant())_ENTRANCE"
        $pattern = '(?s)("classname" "info_landmark"\s+"targetname" "' + [regex]::Escape($name) + '".*?"origin" ")[^"]+(")'
        if ([regex]::Matches($Vmf, $pattern).Count -ne 1) { throw "Expected one transition arrival landmark: $name" }
        $origin = '{0} {1} {2}' -f $gate.arrivalX, $gate.arrivalY, $gate.arrivalZ
        $Vmf = [regex]::Replace($Vmf, $pattern, '${1}' + $origin + '${2}')
    }
    return $Vmf
}

function Get-ZMTransitionTriggerBounds {
    param([object]$Gate)

    $measured = $null -ne $Gate.PSObject.Properties['lanes']
    $min = if ($measured) { [double]$Gate.lateralMin } else { -128 }
    $max = if ($measured) { [double]$Gate.lateralMax } else { 128 }
    $road = $null -ne $Gate.PSObject.Properties['route'] -and $Gate.route -eq 'road'
    if ($measured -and ($Gate.lanes.Count -ne $(if ($road) { 1 } else { 2 }) -or $min -ge 0 -or $max -le 0 -or
        [double]::IsNaN($min) -or [double]::IsInfinity($min) -or
        [double]::IsNaN($max) -or [double]::IsInfinity($max))) {
        throw 'Measured transition trigger requires finite extents for its route lane count.'
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

Export-ModuleMember -Function Get-ZMTransitionDeckHeight, Get-ZMTransitionGateCoordinates, Set-ZMTransitionArrivalLandmarks, Get-ZMTransitionTriggerBounds, Get-ZMTransitionBarricadeProps
