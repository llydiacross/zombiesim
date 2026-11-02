Set-StrictMode -Version Latest

# Structure claims (Alpha 3.4 Phase E): a core tile is claimable only when
# exactly one 1x1 terrain or decoration instance owns it. Coordinates are
# centred tile offsets: east +X, north +Y, matching runtime tile semantics.
$script:ClaimableRoles = @('terrain', 'decoration')
$script:ClaimableTemplatePrefixes = @('terrain/', 'decorations/')

function Get-ZMLayoutProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ZMClaimablePlacement {
    param([object]$Placement)

    $role = [string](Get-ZMLayoutProperty $Placement 'role')
    if ($script:ClaimableRoles -notcontains $role) { return $false }
    $template = ([string](Get-ZMLayoutProperty $Placement 'template')).Replace('\', '/').ToLowerInvariant()
    if (-not @($script:ClaimableTemplatePrefixes | Where-Object { $template.StartsWith($_) }).Count) { return $false }
    $width = Get-ZMLayoutProperty $Placement 'footprintWidth'
    $height = Get-ZMLayoutProperty $Placement 'footprintHeight'
    if (($null -ne $width -and [int]$width -ne 1) -or ($null -ne $height -and [int]$height -ne 1)) { return $false }
    $emits = Get-ZMLayoutProperty $Placement 'emitsInstance'
    if ($null -ne $emits -and -not [bool]$emits) { return $false }
    $ownerX = Get-ZMLayoutProperty $Placement 'ownerTileX'
    $ownerY = Get-ZMLayoutProperty $Placement 'ownerTileY'
    if (($null -ne $ownerX -and [int]$ownerX -ne [int]$Placement.tileX) -or
        ($null -ne $ownerY -and [int]$ownerY -ne [int]$Placement.tileY)) { return $false }
    return $true
}

function Get-ZMClaimTiles {
    param([Parameter(Mandatory = $true)][object]$Layout)

    $bounds = Get-ZMLayoutProperty $Layout 'bounds'
    $gridSize = [int](Get-ZMLayoutProperty $bounds 'coreTileGridSize')
    if ($gridSize -lt 1 -or $gridSize % 2 -ne 1) {
        throw "Claim tiles need an odd core tile grid size; got '$gridSize'."
    }
    $centre = ($gridSize - 1) / 2
    $placementsByTile = @{}
    foreach ($placement in @(Get-ZMLayoutProperty $Layout 'corePlacements')) {
        if ($null -eq $placement) { continue }
        $x = [int]$placement.tileX
        $y = [int]$placement.tileY
        if ($x -lt 0 -or $y -lt 0 -or $x -ge $gridSize -or $y -ge $gridSize) {
            throw "Core placement tile ($x,$y) is outside the $gridSize-tile grid."
        }
        $key = "$x,$y"
        if (-not $placementsByTile.ContainsKey($key)) { $placementsByTile[$key] = New-Object System.Collections.Generic.List[object] }
        $placementsByTile[$key].Add($placement)
    }

    $tiles = New-Object System.Collections.Generic.List[object]
    for ($y = 0; $y -lt $gridSize; $y++) {
        for ($x = 0; $x -lt $gridSize; $x++) {
            $placements = $placementsByTile["$x,$y"]
            if ($null -eq $placements -or $placements.Count -ne 1) { continue }
            if (-not (Test-ZMClaimablePlacement $placements[0])) { continue }
            $tiles.Add(@([int]($x - $centre), [int]($centre - $y)))
        }
    }
    return , $tiles.ToArray()
}

Export-ModuleMember -Function Get-ZMClaimTiles, Test-ZMClaimablePlacement
