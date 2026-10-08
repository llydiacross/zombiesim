Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMCellBounds {
    param([int]$TileGridSize, [int]$TileSize, [bool]$OuterEdgesEnabled)

    if ($TileGridSize -lt 1 -or $TileSize -lt 1) {
        throw 'Cell bounds require a positive tile grid size and a positive tile size.'
    }
    $core = $TileGridSize * $TileSize / 2.0
    $border = $core + $TileSize
    $visual = $border + $(if ($OuterEdgesEnabled) { $TileSize } else { 0 })
    return [ordered]@{
        revision = if ($OuterEdgesEnabled) { 2 } else { 1 }
        tileSize = $TileSize
        coreTileGridSize = $TileGridSize
        coreHalfExtent = $core
        traversableHalfExtent = $border
        visualHalfExtent = $visual
        neighbourPitch = 2 * $visual
        coastContactHalfExtent = $border
        playableCeiling = 4608
    }
}

Export-ModuleMember -Function Get-ZMCellBounds
