function Get-CarparkDeadendOrientationDefinition {
    param([string]$Side)

    $definition = @{
        N = @{ templateKey = 'deadendWest'; rotationYaw = 270 }
        E = @{ templateKey = 'deadendEast'; rotationYaw = 0 }
        S = @{ templateKey = 'deadendWest'; rotationYaw = 90 }
        W = @{ templateKey = 'deadendEast'; rotationYaw = 180 }
    }[$Side]
    if ($null -eq $definition) { return $null }

    return [pscustomobject]@{
        templateKey = [string]$definition.templateKey
        rotationYaw = [int]$definition.rotationYaw
    }
}

function Get-CarparkOneSidedEntranceDefinition {
    param(
        [string]$ClosedLaneKey,
        [int]$AssemblyRotationYaw
    )

    if ($ClosedLaneKey -notin @('east', 'west')) { return $null }
    $normalizedAssemblyYaw = (($AssemblyRotationYaw % 360) + 360) % 360
    return [pscustomobject]@{
        templateKey = if ($ClosedLaneKey -eq 'east') { 'entranceDeadendEast' } else { 'entranceDeadendWest' }
        rotationYaw = ($normalizedAssemblyYaw + 180) % 360
    }
}

function Get-CarparkEndcapDefinition {
    param(
        [string]$Side,
        [object]$CarparkTemplates
    )

    $definition = Get-CarparkDeadendOrientationDefinition $Side
    if ($null -eq $definition) { return $null }

    $template = [string]$CarparkTemplates[$definition.templateKey]
    if ([string]::IsNullOrWhiteSpace($template)) { return $null }
    return [pscustomobject]@{
        template = $template
        rotationYaw = [int]$definition.rotationYaw
    }
}

function Get-CarparkEndcapPlacements {
    param(
        [object]$Recipe,
        [int]$TileGridSize,
        [object]$CarparkTemplates
    )

    $endcaps = [System.Collections.Generic.List[object]]::new()
    foreach ($tilePlacement in @($Recipe.tilePlacements)) {
        $role = [string]$tilePlacement.role
        if ($role -notmatch 'carpark_lane_(east|west)$') { continue }
        $side = if ([int]$tilePlacement.tileY -eq 0) { 'N' } elseif ([int]$tilePlacement.tileX -eq $TileGridSize - 1) { 'E' } elseif ([int]$tilePlacement.tileY -eq $TileGridSize - 1) { 'S' } elseif ([int]$tilePlacement.tileX -eq 0) { 'W' } else { $null }
        if ($null -eq $side) { continue }
        $outerTileX = if ($side -eq 'W') { -1 } elseif ($side -eq 'E') { $TileGridSize } else { [int]$tilePlacement.tileX }
        $outerTileY = if ($side -eq 'N') { -1 } elseif ($side -eq 'S') { $TileGridSize } else { [int]$tilePlacement.tileY }
        $endcapDefinition = Get-CarparkEndcapDefinition $side $CarparkTemplates
        if ($null -eq $endcapDefinition) { continue }
        $endcaps.Add([pscustomobject]@{
            tileX = $outerTileX
            tileY = $outerTileY
            template = [string]$endcapDefinition.template
            rotationYaw = [int]$endcapDefinition.rotationYaw
        })
    }
    return @($endcaps)
}

Export-ModuleMember -Function Get-CarparkDeadendOrientationDefinition, Get-CarparkOneSidedEntranceDefinition, Get-CarparkEndcapDefinition, Get-CarparkEndcapPlacements