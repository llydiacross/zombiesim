Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMGridRoadBranch {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][ValidateSet('N', 'E', 'S', 'W')][string]$Direction,
        [Parameter(Mandatory = $true)][int]$TileGridSize
    )

    $center = [int][Math]::Floor($TileGridSize / 2)
    $roadTiles = @($Recipe.tilePlacements | Where-Object {
        $_.role -in @('road', 'road_center', 'onramp_road', 'bridge_road') -and
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -like 'tile_road*.vmf'
    })
    $branchTiles = switch ($Direction) {
        'N' { @($roadTiles | Where-Object { $_.tileX -eq $center -and $_.tileY -lt $center } | Sort-Object tileY) }
        'E' { @($roadTiles | Where-Object { $_.tileY -eq $center -and $_.tileX -gt $center } | Sort-Object tileX -Descending) }
        'S' { @($roadTiles | Where-Object { $_.tileX -eq $center -and $_.tileY -gt $center } | Sort-Object tileY -Descending) }
        'W' { @($roadTiles | Where-Object { $_.tileY -eq $center -and $_.tileX -lt $center } | Sort-Object tileX) }
    }
    if ($branchTiles.Count -eq 0) {
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
    foreach ($lease in $motorLeaseRows) {
        if ($lease.ring -eq 'core' -and $lease.tileX -ge 0 -and $lease.tileX -lt $TileGridSize -and
            $lease.tileY -ge 0 -and $lease.tileY -lt $TileGridSize) {
            $key = "$($lease.tileX),$($lease.tileY)"
            if (-not $motorLeaseOwners.ContainsKey($key)) { $motorLeaseOwners[$key] = [string]$lease.owner }
        }
    }

    $roadGates = @($contract.gates | Where-Object { $_.route -eq 'road' })
    $motorGates = @($contract.gates | Where-Object { $_.route -ne 'road' })
    $gridRoadApproaches = [System.Collections.Generic.List[object]]::new()
    $roadExtensions = [System.Collections.Generic.List[object]]::new()
    $roadExtensionLeases = [System.Collections.Generic.List[object]]::new()
    $roadOnrampSlotAssignments = @{}
    $roadOnrampExtensionTemplates = @{}
    $motorOverlapRoadSlots = @{}
    $center = [int][Math]::Floor($TileGridSize / 2)

    foreach ($gate in $roadGates) {
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

    $contract.assemblies = @($motorAssemblies) + @($roadExtensions)
    $contract.leases = @($motorLeaseRows) + @($roadExtensionLeases)
    $contract.gates = @($motorGates) + @($roadGates)
    $contract.connections = @($contract.connections | Where-Object { $_.route -eq 'motorway' })
    $contract.ordinaryRoadApproaches = @()
    $contract.ordinaryRoadPlacementShifts = @()
    $contract | Add-Member -NotePropertyName gridRoadApproaches -NotePropertyValue @($gridRoadApproaches) -Force
    $contract.envelopeOverlaps = @()
    $contract.boundaryGaps = @($contract.boundaryGaps | Where-Object { $_.heading -in $contract.declaredMotorwayDirections })
    return $contract
}

Export-ModuleMember -Function Get-ZMGridRoadBranch, Set-ZMGridRoadGateCrossCoordinate, Set-ZMTrustedMotorwayGridContract
