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

Export-ModuleMember -Function Get-ZMTransitionDeckHeight, Get-ZMTransitionGateCoordinates, Set-ZMTransitionArrivalLandmarks
