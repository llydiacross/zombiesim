Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMCellBounds {
    param([int]$TileGridSize, [int]$TileSize, [bool]$OuterEdgesEnabled, [bool]$OceanEdgesEnabled = $false)

    if ($TileGridSize -lt 1 -or $TileSize -lt 1) {
        throw 'Cell bounds require a positive tile grid size and a positive tile size.'
    }
    if ($OceanEdgesEnabled -and -not $OuterEdgesEnabled) { throw 'Ocean edge pieces require the outer-edge ring.' }
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
        # Authored ocean outer-edge pieces carry the shore to the visual edge; otherwise the skybox beach meets the border.
        coastContactHalfExtent = if ($OceanEdgesEnabled) { $visual } else { $border }
        playableCeiling = 4608
    }
}

function Test-ZMOceanEdgesEnabled {
    param([System.Collections.IDictionary]$OuterEdgeSettings)

    return $null -ne $OuterEdgeSettings -and $OuterEdgeSettings.Contains('enabled') -and [bool]$OuterEdgeSettings.enabled -and
        $OuterEdgeSettings.Contains('oceanTemplates') -and @($OuterEdgeSettings.oceanTemplates).Count -gt 0
}

Export-ModuleMember -Function Get-ZMCellBounds, Test-ZMOceanEdgesEnabled
