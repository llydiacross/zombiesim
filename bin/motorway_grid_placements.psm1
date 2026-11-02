Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMGridRoadBranch {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][ValidateSet('N', 'E', 'S', 'W')][string]$Direction,
        [Parameter(Mandatory = $true)][int]$TileGridSize,
        [switch]$AllowEmpty
    )

    $center = [int][Math]::Floor($TileGridSize / 2)
    $roadTiles = @($Recipe.tilePlacements | Where-Object {
        $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road') -and
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -like 'tile_road*.vmf'
    })
    $branchTiles = @(switch ($Direction) {
        'N' { @($roadTiles | Where-Object { $_.tileX -eq $center -and $_.tileY -lt $center } | Sort-Object tileY) }
        'E' { @($roadTiles | Where-Object { $_.tileY -eq $center -and $_.tileX -gt $center } | Sort-Object tileX -Descending) }
        'S' { @($roadTiles | Where-Object { $_.tileX -eq $center -and $_.tileY -gt $center } | Sort-Object tileY -Descending) }
        'W' { @($roadTiles | Where-Object { $_.tileY -eq $center -and $_.tileX -lt $center } | Sort-Object tileX) }
    })
    if ($branchTiles.Count -eq 0) {
        if ($AllowEmpty) { return $null }
        throw "Motorway cell $($Recipe.x),$($Recipe.y) has no 5x5 road placement for $Direction."
    }

    $boundaryTile = $branchTiles[0]
    $crossCoordinate = if ($Direction -in @('N', 'S')) {
        ([int]$boundaryTile.tileX - $center) * 640
    } else {
        ($center - [int]$boundaryTile.tileY) * 640
    }
    $bridgeRoad = @($branchTiles | Where-Object {
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -eq 'tile_road_bridge.vmf'
    }).Count -gt 0
    return [pscustomobject]@{
        direction = $Direction
        tiles = @($branchTiles)
        boundaryTile = $boundaryTile
        crossCoordinate = $crossCoordinate
        bridgeRoad = $bridgeRoad
    }
}

function Set-ZMGridRoadGateCrossCoordinate {
    param(
        [Parameter(Mandatory = $true)][object]$Gate,
        [Parameter(Mandatory = $true)][object]$Branch
    )

    $direction = [string]$Gate.direction
    if ($direction -in @('N', 'S')) {
        $Gate.x = $Branch.crossCoordinate
        foreach ($lane in $Gate.lanes) {
            $lane.arrowX = $Branch.crossCoordinate
            $lane.arrivalX = $Branch.crossCoordinate
        }
    } else {
        $Gate.y = $Branch.crossCoordinate
        foreach ($lane in $Gate.lanes) {
            $lane.arrowY = $Branch.crossCoordinate
            $lane.arrivalY = $Branch.crossCoordinate
        }
    }
    $Gate.status = 'trusted_grid_road_gate_not_compiled_or_live'
}

function Get-ZMLatticeTile {
    param([double]$X, [double]$Y, [int]$TileSize, [int]$TileGridSize)

    $center = [int][Math]::Floor($TileGridSize / 2)
    $tileX = [int][Math]::Round($X / $TileSize) + $center
    $tileY = $center - [int][Math]::Round($Y / $TileSize)
    $ringIndex = [Math]::Max([Math]::Abs($tileX - $center), [Math]::Abs($tileY - $center))
    $ring = if ($ringIndex -le 2) { 'core' } elseif ($ringIndex -eq 3) { 'border' } else { 'outer' }
    return [pscustomobject]@{ tileX = $tileX; tileY = $tileY; ring = $ring }
}

# Restores a trusted ordinary-road dogleg (boundary straight, corners and 768 connector) that joins a motorway on-ramp.
# A legacy lateral grid shift is normalised back onto the 640 grid by moving the boundary pieces and inserting native
# 640 straights into the dogleg leg, so the road gate stays on the neighbour's grid road axis.
function Restore-ZMTrustedRoadApproach {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$Approach,
        [Parameter(Mandatory = $true)][int]$TileGridSize,
        [Parameter(Mandatory = $true)][int]$TileSize,
        [Parameter(Mandatory = $true)][string]$RoadStraightTemplate
    )

    $direction = [string]$Approach.heading
    $entryCornerOwner = @($Approach.instances | Where-Object { ([string]$_.owner) -like '*/entry_corner' })
    if ($entryCornerOwner.Count -ne 1) { throw "Trusted road approach $direction has no unique entry corner." }
    $prefix = ([string]$entryCornerOwner[0].owner).Substring(0, ([string]$entryCornerOwner[0].owner).Length - 'entry_corner'.Length)
    $assemblies = @($Contract.assemblies | Where-Object { ([string]$_.owner).StartsWith($prefix, [StringComparison]::Ordinal) } |
        ForEach-Object { $_ | ConvertTo-Json -Depth 30 | ConvertFrom-Json })
    $leases = @($Contract.leases | Where-Object { ([string]$_.owner).StartsWith($prefix, [StringComparison]::Ordinal) } |
        ForEach-Object { $_ | ConvertTo-Json -Depth 30 | ConvertFrom-Json })
    foreach ($instance in $Approach.instances) {
        if (@($assemblies | Where-Object owner -ceq $instance.owner).Count -ne 1) {
            throw "Trusted road approach instance $($instance.owner) has no unique assembly."
        }
    }

    $shiftRecords = @($Contract.ordinaryRoadPlacementShifts | Where-Object { $_.heading -eq $direction })
    $legacyShift = $Approach.PSObject.Properties['northGridShift']
    if ($shiftRecords.Count -gt 1) { throw "Trusted road approach $direction has multiple placement shifts." }
    $units = 0
    if ($shiftRecords.Count -eq 1) {
        if ([string]$shiftRecords[0].axis -ne 'y') { throw "Unsupported trusted road approach shift axis $($shiftRecords[0].axis)." }
        $units = [int]$shiftRecords[0].units
    }
    if ($null -ne $legacyShift) {
        if ($shiftRecords.Count -eq 1 -and [int]$legacyShift.Value -ne $units) { throw "Trusted road approach $direction has inconsistent shifts." }
        $units = [int]$legacyShift.Value
    }

    $joins = @($Approach.joins | ForEach-Object { $_ | ConvertTo-Json -Depth 30 | ConvertFrom-Json })
    $entryAxis = [double]$Approach.entryAxis
    $port = $Approach.boundaryPort | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $status = [string]$Approach.status
    if ($units -ne 0) {
        if ($direction -notin @('E', 'W') -or ($units % $TileSize) -ne 0) {
            throw "Unsupported trusted road approach shift $units for heading $direction."
        }
        $shiftedOwners = @("${prefix}entry_corner", "${prefix}entry_straight2240")
        foreach ($owner in $shiftedOwners) {
            if (@($assemblies | Where-Object owner -ceq $owner).Count -ne 1) { throw "Trusted road approach is missing $owner." }
        }
        $corner = @($assemblies | Where-Object owner -ceq "${prefix}entry_corner")[0]
        $oldCornerY = [double]$corner.origin.y
        foreach ($assembly in @($assemblies | Where-Object { $_.owner -cin $shiftedOwners })) {
            $assembly.origin.y = [double]$assembly.origin.y - $units
            if ($null -ne $assembly.PSObject.Properties['windingBounds']) {
                $assembly.windingBounds.y.min = [double]$assembly.windingBounds.y.min - $units
                $assembly.windingBounds.y.max = [double]$assembly.windingBounds.y.max - $units
            }
        }
        foreach ($lease in @($leases | Where-Object { $_.owner -cin $shiftedOwners })) {
            $lease.tileY = [int]$lease.tileY + [int]($units / $TileSize)
            $center = [int][Math]::Floor($TileGridSize / 2)
            $ringIndex = [Math]::Max([Math]::Abs([int]$lease.tileX - $center), [Math]::Abs([int]$lease.tileY - $center))
            $lease.ring = if ($ringIndex -le 2) { 'core' } elseif ($ringIndex -eq 3) { 'border' } else { 'outer' }
        }

        $sign = [Math]::Sign($units)
        $count = [int]([Math]::Abs($units) / $TileSize)
        $newCornerY = $oldCornerY - $units
        $previousOwner = "${prefix}entry_corner"
        $extensionJoins = [System.Collections.Generic.List[object]]::new()
        for ($index = 1; $index -le $count; $index++) {
            $owner = if ($count -eq 1) { "${prefix}entry_extension" } else { "${prefix}entry_extension$index" }
            $x = [double]$corner.origin.x
            $y = $newCornerY + ($sign * $TileSize * $index)
            $assemblies += [pscustomobject]@{
                template = $RoadStraightTemplate
                yaw = 0
                origin = [pscustomobject]@{ x = $x; y = $y; z = 0 }
                owner = $owner
                status = 'grid_normalised_ordinary_road_join'
                disposition = 'native_640_dogleg_extension_hammer_review_pending'
                placementEligibility = 'normal_travel_pending'
                windingBounds = [pscustomobject]@{
                    x = [pscustomobject]@{ min = $x - ($TileSize / 2); max = $x + ($TileSize / 2) }
                    y = [pscustomobject]@{ min = $y - ($TileSize / 2); max = $y + ($TileSize / 2) }
                    z = [pscustomobject]@{ min = 0; max = 40 }
                }
                windingWithinCellFrame = $true
                extendsBelowTerrain = $false
            }
            $tile = Get-ZMLatticeTile $x $y $TileSize $TileGridSize
            $leases += [pscustomobject]@{ tileX = $tile.tileX; tileY = $tile.tileY; ring = $tile.ring; owner = $owner; emitsInstance = $false }
            $extensionJoins.Add([pscustomobject]@{
                first = $previousOwner; second = $owner
                position = [pscustomobject]@{ x = $x; y = $y - ($sign * $TileSize / 2); z = 36 }
                width = 256; status = 'grid_normalised_floor_seam_hammer_review_pending'
            })
            $previousOwner = $owner
        }
        foreach ($join in $joins) {
            if ($join.first -ceq "${prefix}entry_corner" -and $join.second -cnotin $shiftedOwners) {
                $join.first = $previousOwner
            } elseif ($join.second -cin $shiftedOwners -or $join.first -cin $shiftedOwners) {
                $join.position.y = [double]$join.position.y - $units
                $join.status = 'grid_normalised_floor_seam_hammer_review_pending'
            }
        }
        $joins = @($joins) + @($extensionJoins)
        $entryAxis += $units
        $port.position.y = [double]$port.position.y - $units
        $status = 'grid_normalised_dogleg_hammer_review_pending'
    }

    $restoredApproach = [pscustomobject]@{
        heading = $direction
        entryAxis = $entryAxis
        boundaryPort = $port
        instances = @($assemblies | Where-Object { ([string]$_.owner) -notlike '*/road_approach' })
        joins = @($joins)
        status = $status
    }
    $crossCoordinate = if ($direction -in @('N', 'S')) { [double]$port.position.x } else { [double]$port.position.y }
    return [pscustomobject]@{
        approach = $restoredApproach
        assemblies = @($assemblies)
        leases = @($leases)
        crossCoordinate = $crossCoordinate
    }
}

function Set-ZMTrustedMotorwayGridContract {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][object]$TrustedContract,
        [Parameter(Mandatory = $true)][int]$TileGridSize,
        [Parameter(Mandatory = $true)][int]$TileSize,
        [Parameter(Mandatory = $true)][int]$RoadExtensionDepth,
        [Parameter(Mandatory = $true)][string]$RoadStraightTemplate,
        [Parameter(Mandatory = $true)][string]$RoadBridgeTemplate,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$RoadYawByDirection
    )

    $contract = $TrustedContract | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $authority = $contract.PSObject.Properties['assemblyAuthority']
    if ($null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout') {
        throw 'Motorway grid placement requires an approved trusted-plan contract.'
    }
    if ($contract.schemaVersion -eq 1) { return $contract }
    if ($contract.schemaVersion -ne 2) {
        throw "Unsupported trusted motorway grid contract version $($contract.schemaVersion)."
    }

    $motorAssemblies = @($contract.assemblies | Where-Object {
        ([string]$_.template).Replace('/', '\') -match '(?i)\\motorway_3x1\\tile_motorway[^\\]*\.vmf$'
    })
    if ($motorAssemblies.Count -eq 0) {
        throw "Trusted motorway grid contract has no motorway pieces for cell $($Recipe.x),$($Recipe.y)."
    }
    $motorOwners = @($motorAssemblies | ForEach-Object { [string]$_.owner })
    $motorOwnerSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($owner in $motorOwners) { [void]$motorOwnerSet.Add($owner) }

    $motorLeaseRows = @($contract.leases | Where-Object { $motorOwnerSet.Contains([string]$_.owner) })
    $motorLeaseOwners = @{}
    $motorOverlapRoadSlots = @{}
    $bridgeOwners = @($motorAssemblies | Where-Object {
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -eq 'tile_motorway_road_bridge.vmf'
    } | ForEach-Object { [string]$_.owner })
    foreach ($lease in $motorLeaseRows) {
        if ($lease.ring -eq 'core' -and $lease.tileX -ge 0 -and $lease.tileX -lt $TileGridSize -and
            $lease.tileY -ge 0 -and $lease.tileY -lt $TileGridSize) {
            $key = "$($lease.tileX),$($lease.tileY)"
            if (-not $motorLeaseOwners.ContainsKey($key)) { $motorLeaseOwners[$key] = [string]$lease.owner }
            if ([string]$lease.owner -in $bridgeOwners) { $motorOverlapRoadSlots[$key] = [string]$lease.owner }
        }
    }

    $roadGates = @($contract.gates | Where-Object { $_.route -eq 'road' })
    $motorGates = @($contract.gates | Where-Object { $_.route -ne 'road' })
    $gridRoadApproaches = [System.Collections.Generic.List[object]]::new()
    $roadExtensions = [System.Collections.Generic.List[object]]::new()
    $roadExtensionLeases = [System.Collections.Generic.List[object]]::new()
    $roadOnrampSlotAssignments = @{}
    $roadOnrampExtensionTemplates = @{}
    $center = [int][Math]::Floor($TileGridSize / 2)
    $trustedApproaches = @()
    $approachProperty = $contract.PSObject.Properties['ordinaryRoadApproaches']
    if ($null -ne $approachProperty -and $null -ne $approachProperty.Value) {
        $trustedApproaches = @($approachProperty.Value | Where-Object {
            $null -ne $_.PSObject.Properties['instances'] -and @($_.instances).Count -gt 0
        })
    }
    $restoredApproaches = [System.Collections.Generic.List[object]]::new()
    $approachAssemblies = [System.Collections.Generic.List[object]]::new()
    $approachLeases = [System.Collections.Generic.List[object]]::new()
    $approachOccupiedSlots = @{}
    $approachTerrainSlots = @{}

    foreach ($gate in $roadGates) {
        $approach = @($trustedApproaches | Where-Object { [string]$_.heading -eq [string]$gate.direction })
        if ($approach.Count -gt 1) {
            throw "Trusted motorway contract has multiple road approaches for $($gate.direction) in cell $($Recipe.x),$($Recipe.y)."
        }
        if ($approach.Count -eq 1) {
            $restored = Restore-ZMTrustedRoadApproach -Contract $contract -Approach $approach[0] -TileGridSize $TileGridSize `
                -TileSize $TileSize -RoadStraightTemplate $RoadStraightTemplate
            $branch = Get-ZMGridRoadBranch $Recipe ([string]$gate.direction) $TileGridSize -AllowEmpty
            $gridCross = if ($null -ne $branch) { [double]$branch.crossCoordinate } else { 0.0 }
            if ([Math]::Abs($gridCross - [double]$restored.crossCoordinate) -gt 0.001) {
                throw "Restored road approach $($gate.direction) port $($restored.crossCoordinate) is off the grid road axis $gridCross in cell $($Recipe.x),$($Recipe.y)."
            }
            Set-ZMGridRoadGateCrossCoordinate $gate ([pscustomobject]@{ crossCoordinate = $gridCross })
            foreach ($assembly in $restored.assemblies) { $approachAssemblies.Add($assembly) }
            foreach ($lease in $restored.leases) {
                $approachLeases.Add($lease)
                $leaseKey = "$($lease.tileX),$($lease.tileY)"
                if ($lease.ring -eq 'core' -and -not $motorLeaseOwners.ContainsKey($leaseKey) -and
                    -not $approachOccupiedSlots.ContainsKey($leaseKey)) {
                    $approachOccupiedSlots[$leaseKey] = [string]$lease.owner
                }
            }
            if ($null -ne $branch) {
                foreach ($branchTile in $branch.tiles) {
                    $branchTileKey = "$($branchTile.tileX),$($branchTile.tileY)"
                    if ($motorLeaseOwners.ContainsKey($branchTileKey)) {
                        $motorOverlapRoadSlots[$branchTileKey] = $motorLeaseOwners[$branchTileKey]
                    } elseif (-not $approachOccupiedSlots.ContainsKey($branchTileKey)) {
                        $approachTerrainSlots[$branchTileKey] = $true
                    }
                }
            }
            $restoredApproaches.Add($restored.approach)
            continue
        }

        $branch = Get-ZMGridRoadBranch $Recipe ([string]$gate.direction) $TileGridSize
        $onrampTiles = @($branch.tiles | Where-Object {
            [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -eq 'tile_road_onramp.vmf'
        })
        if ($onrampTiles.Count -gt 1) {
            throw "Grid road branch $($branch.direction) has multiple on-ramp tiles in cell $($Recipe.x),$($Recipe.y)."
        }
        if ($onrampTiles.Count -eq 1) {
            $onrampTile = $onrampTiles[0]
            $onrampKey = "$($onrampTile.tileX),$($onrampTile.tileY)"
            foreach ($branchTile in $branch.tiles) {
                $branchTileKey = "$($branchTile.tileX),$($branchTile.tileY)"
                if ($motorLeaseOwners.ContainsKey($branchTileKey)) {
                    $motorOverlapRoadSlots[$branchTileKey] = $motorLeaseOwners[$branchTileKey]
                }
            }
            if ($motorLeaseOwners.ContainsKey($onrampKey)) {
                $availableCoreRoadTiles = @($branch.tiles | Where-Object {
                    -not $motorLeaseOwners.ContainsKey("$($_.tileX),$($_.tileY)")
                })
                if ($availableCoreRoadTiles.Count -gt 0) {
                    $destination = $availableCoreRoadTiles[0]
                    $destinationKey = "$($destination.tileX),$($destination.tileY)"
                    if ($roadOnrampSlotAssignments.ContainsKey($destinationKey)) {
                        throw "Grid on-ramp slot $destinationKey is claimed by multiple branches in cell $($Recipe.x),$($Recipe.y)."
                    }
                    $roadOnrampSlotAssignments[$destinationKey] = [pscustomobject]@{
                        template = [string]$onrampTile.template
                        rotationYaw = [int]$onrampTile.rotationYaw
                    }
                } else {
                    $roadOnrampExtensionTemplates[[string]$branch.direction] = [pscustomobject]@{
                        template = [string]$onrampTile.template
                        rotationYaw = [int]$onrampTile.rotationYaw
                    }
                }
            }
        }

        Set-ZMGridRoadGateCrossCoordinate $gate $branch
        $gridRoadApproaches.Add([pscustomobject]@{
            heading = $branch.direction
            boundaryTile = [pscustomobject]@{ tileX = $branch.boundaryTile.tileX; tileY = $branch.boundaryTile.tileY }
            crossCoordinate = $branch.crossCoordinate
        })

        $extensionTemplate = if ($branch.bridgeRoad) { $RoadBridgeTemplate } else { $RoadStraightTemplate }
        $step = @{
            N = @(0, -1); E = @(1, 0); S = @(0, 1); W = @(-1, 0)
        }[[string]$branch.direction]
        for ($index = 1; $index -le $RoadExtensionDepth; $index++) {
            $tileX = [int]$branch.boundaryTile.tileX + ($step[0] * $index)
            $tileY = [int]$branch.boundaryTile.tileY + ($step[1] * $index)
            if ($tileX -lt -2 -or $tileX -gt 6 -or $tileY -lt -2 -or $tileY -gt 6) {
                throw "Grid road continuation leaves the expanded tile lattice at $($branch.direction)/$index."
            }
            $ringIndex = [Math]::Max([Math]::Abs($tileX - $center), [Math]::Abs($tileY - $center))
            $ring = if ($ringIndex -le 2) { 'core' } elseif ($ringIndex -eq 3) { 'border' } else { 'outer' }
            $owner = "grid_road/$($branch.direction)/extension$index"
            $onrampExtension = $index -eq 1 -and $roadOnrampExtensionTemplates.ContainsKey([string]$branch.direction)
            $instanceTemplate = if ($onrampExtension) {
                [string]$roadOnrampExtensionTemplates[[string]$branch.direction].template
            } else { $extensionTemplate }
            $instanceYaw = if ($onrampExtension) {
                [int]$roadOnrampExtensionTemplates[[string]$branch.direction].rotationYaw
            } else { [int]$RoadYawByDirection[$branch.direction] }
            $roadExtensions.Add([pscustomobject]@{
                template = $instanceTemplate
                yaw = $instanceYaw
                origin = [pscustomobject]@{
                    x = ($tileX - $center) * $TileSize
                    y = ($center - $tileY) * $TileSize
                    z = 0
                }
                owner = $owner
                status = 'grid_road_continuation'
                disposition = 'five_by_five_640_grid'
                placementEligibility = 'normal_travel_pending'
                nextTemplate = $extensionTemplate
            })
            $roadExtensionLeases.Add([pscustomobject]@{
                tileX = $tileX; tileY = $tileY; ring = $ring; owner = $owner; emitsInstance = $false
            })
        }
    }

    $motorTemplates = @($motorAssemblies | ForEach-Object { ([string]$_.template).Replace('/', '\').ToLowerInvariant() })
    $terrain = @($Recipe.tilePlacements | Where-Object role -eq 'terrain' | Select-Object -First 1)
    if ($terrain.Count -ne 1) { throw "Trusted motorway grid contract has no terrain fallback in cell $($Recipe.x),$($Recipe.y)." }
    $Recipe.tilePlacements = @(foreach ($placement in $Recipe.tilePlacements) {
        $key = "$($placement.tileX),$($placement.tileY)"
        $templateKey = ([string]$placement.template).Replace('/', '\').ToLowerInvariant()
        $templateName = [IO.Path]::GetFileName($templateKey)
        $gridRoad = $placement.role -in @('road', 'road_center', 'onramp_road', 'bridge_road') -and
            $templateName -like 'tile_road*.vmf'
        if ($gridRoad -and $motorOverlapRoadSlots.ContainsKey($key)) {
            $owner = [string]$motorOverlapRoadSlots[$key]
            [pscustomobject]@{
                tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template
                rotationYaw = 0; role = 'motorway_external_occupied'; placementId = $owner; emitsInstance = $false
            }
        } elseif ($approachOccupiedSlots.ContainsKey($key)) {
            [pscustomobject]@{
                tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template
                rotationYaw = 0; role = 'motorway_external_occupied'; placementId = [string]$approachOccupiedSlots[$key]
                emitsInstance = $false
            }
        } elseif ($gridRoad -and $approachTerrainSlots.ContainsKey($key)) {
            [pscustomobject]@{
                tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template
                rotationYaw = 0; role = 'terrain'
            }
        } elseif ($gridRoad) {
            if ($roadOnrampSlotAssignments.ContainsKey($key)) {
                $onramp = $roadOnrampSlotAssignments[$key]
                [pscustomobject]@{
                    tileX = $placement.tileX; tileY = $placement.tileY
                    template = $onramp.template; rotationYaw = $onramp.rotationYaw; role = 'onramp_road'
                }
            } else {
                $placement
            }
        } elseif ($motorTemplates -contains $templateKey -or $motorLeaseOwners.ContainsKey($key)) {
            $owner = if ($motorLeaseOwners.ContainsKey($key)) { $motorLeaseOwners[$key] } else {
                [string](@($motorAssemblies | Where-Object { ([string]$_.template).Replace('/', '\').ToLowerInvariant() -eq $templateKey } | Select-Object -First 1)[0].owner)
            }
            [pscustomobject]@{
                tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template
                rotationYaw = 0; role = 'motorway_external_occupied'; placementId = $owner; emitsInstance = $false
            }
        } else {
            $placement
        }
    })

    $contract.assemblies = @($motorAssemblies) + @($approachAssemblies) + @($roadExtensions)
    $contract.leases = @($motorLeaseRows) + @($approachLeases) + @($roadExtensionLeases)
    $contract.gates = @($motorGates) + @($roadGates)
    $contract.connections = @($contract.connections | Where-Object { $_.route -eq 'motorway' })
    $contract.ordinaryRoadApproaches = @($restoredApproaches)
    $contract.ordinaryRoadPlacementShifts = @()
    $contract | Add-Member -NotePropertyName gridRoadApproaches -NotePropertyValue @($gridRoadApproaches) -Force
    $contract.envelopeOverlaps = @()
    $contract.boundaryGaps = @($contract.boundaryGaps | Where-Object { $_.heading -in $contract.declaredMotorwayDirections })
    return $contract
}

Export-ModuleMember -Function Get-ZMGridRoadBranch, Set-ZMGridRoadGateCrossCoordinate, Set-ZMTrustedMotorwayGridContract
