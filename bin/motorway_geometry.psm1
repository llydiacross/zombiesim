Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMMotorwayFootprint {
    param([Parameter(Mandatory = $true)][string]$Template)

    $canonical = $Template.Replace('/', '\')
    if ([System.IO.Path]::GetExtension($canonical) -ine '.vmf' -or $canonical -match '(?i)(^|\\)motorway_1x1\\') {
        throw "Expected a wide motorway VMF, not a legacy/other asset: '$Template'."
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($canonical)
    if ($name -in @('tile_motorway', 'tile_motorway_road_bridge', 'tile_motorway_ramp')) {
        return [pscustomobject]@{ width = 3; height = 1 }
    }
    if ($name -notin @(
        'tile_motorway_corner_5x3', 'tile_motorway_crossroads_3x3',
        'tile_motorway_tjunction_6x3', 'tile_motorway_deadend_3x3',
        'tile_motorway_onramp_3x4', 'tile_motorway_onramp_dual_3x4'
    )) { throw "Unsupported wide motorway template '$Template'." }
    if ($name -notmatch '_(\d+)x(\d+)$') { throw "Wide motorway footprint suffix missing in '$Template'." }
    return [pscustomobject]@{ width = [int]$Matches[1]; height = [int]$Matches[2] }
}

function Convert-ZMMotorwayPoint {
    param(
        [Parameter(Mandatory = $true)][object]$Point,
        [Parameter(Mandatory = $true)][ValidateSet(0, 90, 180, 270)][int]$Yaw
    )

    foreach ($axis in @('x', 'y', 'z')) {
        if ($null -eq $Point.PSObject.Properties[$axis]) { throw "Motorway point requires physical $axis." }
        $value = [double]$Point.$axis
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw "Motorway point has non-finite physical $axis." }
    }
    $x = [double]$Point.x
    $y = [double]$Point.y
    switch ($Yaw) {
        0 { $rx = $x; $ry = $y }
        90 { $rx = -$y; $ry = $x }
        180 { $rx = -$x; $ry = -$y }
        270 { $rx = $y; $ry = -$x }
    }
    return [pscustomobject]@{ x = $rx; y = $ry; z = [double]$Point.z }
}

function Get-ZMMotorwayReservation {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][ValidateSet(0, 90, 180, 270)][int]$Yaw,
        [Parameter(Mandatory = $true)][int]$AnchorTileX,
        [Parameter(Mandatory = $true)][int]$AnchorTileY,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    $authored = Get-ZMMotorwayFootprint $Template
    $width = if ($Yaw -in @(90, 270)) { $authored.height } else { $authored.width }
    $height = if ($Yaw -in @(90, 270)) { $authored.width } else { $authored.height }
    $centerX = $AnchorTileX + ($width - 1) / 2.0
    $centerY = $AnchorTileY + ($height - 1) / 2.0
    $slots = @(for ($y = $AnchorTileY; $y -lt $AnchorTileY + $height; $y++) {
        for ($x = $AnchorTileX; $x -lt $AnchorTileX + $width; $x++) {
            [pscustomobject]@{ tileX = $x; tileY = $y; owner = $Owner; emitsInstance = $x -eq $AnchorTileX -and $y -eq $AnchorTileY }
        }
    })
    return [pscustomobject]@{
        template = $Template
        owner = $Owner
        yaw = $Yaw
        authoredWidth = $authored.width
        authoredHeight = $authored.height
        width = $width
        height = $height
        anchorTileX = $AnchorTileX
        anchorTileY = $AnchorTileY
        centerTileX = $centerX
        centerTileY = $centerY
        originOffset = [pscustomobject]@{ x = ($width - 1) * 320.0; y = -($height - 1) * 320.0; z = 0.0 }
        slots = $slots
    }
}











function New-ZMStraightMotorwayStripe {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('vertical', 'horizontal')][string]$Orientation,
        [Parameter(Mandatory = $true)][ValidateRange(-2, 6)][int]$Along,
        [string]$Template = 'roads\motorway_3x1\tile_motorway.vmf'
    )

    $footprint = Get-ZMMotorwayFootprint $Template
    if ($footprint.width -ne 3 -or $footprint.height -ne 1 -or [IO.Path]::GetFileName($Template) -ne 'tile_motorway.vmf') {
        throw 'Straight motorway stripes require the approved 3x1 straight source.'
    }
    $vertical = $Orientation -eq 'vertical'
    $yaw = if ($vertical) { 0 } else { 90 }
    $anchorX = if ($vertical) { 1 } else { $Along }
    $anchorY = if ($vertical) { $Along } else { 1 }
    $reservation = Get-ZMMotorwayReservation $Template $yaw $anchorX $anchorY "motorway:$Along"
    $owner = [pscustomobject]@{
        tileX = $anchorX; tileY = $anchorY; template = $Template; rotationYaw = $yaw
        role = 'motorway_assembly'; footprintWidth = $reservation.width; footprintHeight = $reservation.height
        authoredWidth = 3; authoredHeight = 1; placementId = $reservation.owner
        ownerTileX = $anchorX; ownerTileY = $anchorY; emitsInstance = $true
        originCellLocal = [pscustomobject]@{
            x = ($reservation.centerTileX - 2) * 640
            y = (2 - $reservation.centerTileY) * 640
            z = 0
        }
        targetname = "zm_motorway_assembly_$Along"
    }
    $placements = @(foreach ($slot in $reservation.slots) {
        if ($slot.emitsInstance) { $owner } else {
            [pscustomobject]@{
                tileX = $slot.tileX; tileY = $slot.tileY; template = $Template; rotationYaw = $yaw
                role = 'motorway_occupied'; placementId = $reservation.owner
                footprintWidth = $reservation.width; footprintHeight = $reservation.height
                ownerTileX = $anchorX; ownerTileY = $anchorY; emitsInstance = $false
            }
        }
    })
    return [pscustomobject]@{ owner = $owner; reservation = $reservation; placements = $placements }
}



function Get-ZMNormalStraightMotorwayContract {
    param([Parameter(Mandatory = $true)][object]$Recipe)

    $property = $Recipe.PSObject.Properties['motorwayAssembly']
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "Normal straight motorway requires a trusted gate/lease contract: $($Recipe.cellTemplateFilename)"
    }

    $contract = $property.Value
    $authority = $contract.PSObject.Properties['assemblyAuthority']
    if ($contract.schemaVersion -ne 1 -or $contract.status -ne 'normal_reservations_travel_pending' -or
        $null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout' -or
        @($contract.gates).Count -ne 2 -or @($contract.ringPlacements).Count -ne 4 -or
        @($contract.leases).Count -ne 27) {
        throw "Normal straight motorway requires the approved trusted gate/lease contract: $($Recipe.cellTemplateFilename)"
    }

    return $contract
}

function Resolve-ZMNormalStraightMotorwayRings {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [object[]]$BorderPlacements,
        [object[]]$OuterPlacements
    )

    $contract = Get-ZMNormalStraightMotorwayContract $Recipe
    $validation = $Recipe.PSObject.Copy()
    $inspection = $contract.PSObject.Copy()
    $inspection.status = 'cell_geometry_inspection_not_live_travel'
    $validation | Add-Member -NotePropertyName motorwayCellInspection -NotePropertyValue $inspection
    $leased = Assert-ZMStraightMotorwayCellContract $validation
    return [pscustomobject]@{
        borderPlacements = @($BorderPlacements | Where-Object { -not $leased.ContainsKey("$($_.tileX),$($_.tileY)") }) +
            @($contract.ringPlacements | Where-Object ring -eq border)
        outerPlacements = @($OuterPlacements | Where-Object { -not $leased.ContainsKey("$($_.tileX),$($_.tileY)") }) +
            @($contract.ringPlacements | Where-Object ring -eq outer)
    }
}

function Set-ZMStraightMotorwayCellInspection {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][string]$TemplateDirectory,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$LayoutRotations
    )

    if ($Recipe.topology -ne 'motorway-straight' -or $Recipe.orientation -notin @('vertical', 'horizontal') -or
        $Recipe.transportFeature -ne 'none' -or $Recipe.tileGridSize -ne 5 -or $null -ne $Recipe.safeZoneEntrance -or
        @($Recipe.waterBorderSides).Count -gt 0 -or @($Recipe.skyboxOceanSides).Count -gt 0 -or
        @($Recipe.landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0) {
        throw 'Wide motorway cell inspection currently requires an inland 5x5 straight without a ramp, bridge, landmark or safe-zone entrance; unsupported cells never fall back.'
    }
    $template = 'roads\motorway_3x1\tile_motorway.vmf'
    $source = Join-Path $TemplateDirectory $template
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Wide motorway cell source missing: $source" }
    $yaw = [int]$LayoutRotations.straight[$Recipe.orientation]
    if (($Recipe.orientation -eq 'vertical' -and $yaw -ne 0) -or ($Recipe.orientation -eq 'horizontal' -and $yaw -ne 90)) {
        throw 'Straight motorway inspection requires the approved existing vertical0/horizontal90 yaw mappings.'
    }
    $vertical = $Recipe.orientation -eq 'vertical'
    $placements = @{}
    $terrain = @($Recipe.tilePlacements | Where-Object role -eq terrain | Select-Object -First 1)
    if ($terrain.Count -ne 1) { throw 'Wide motorway cell inspection requires an explicit planned terrain template.' }
    $sceneryChanges = [System.Collections.Generic.List[object]]::new()
    foreach ($placement in $Recipe.tilePlacements) {
        $cross = if ($vertical) { [int]$placement.tileX } else { [int]$placement.tileY }
        if ($cross -in @(1, 2, 3)) { continue }
        if ($placement.role -in @('terrain', 'decoration')) {
            $placements["$($placement.tileX),$($placement.tileY)"] = $placement
        } else {
            $sceneryChanges.Add([pscustomobject]@{ tileX = $placement.tileX; tileY = $placement.tileY; previousTemplate = $placement.template; reason = 'Motorway-only scenery: fixture removes buildings/macros; no persistent world feature relocation.' })
            $placements["$($placement.tileX),$($placement.tileY)"] = [pscustomobject]@{
                tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template
                rotationYaw = 0; role = 'terrain'
            }
        }
    }
    $ringPlacements = [System.Collections.Generic.List[object]]::new()
    $leases = [System.Collections.Generic.List[object]]::new()
    foreach ($along in -2..6) {
        $stripe = New-ZMStraightMotorwayStripe $Recipe.orientation $along $template
        $reservation = $stripe.reservation
        $owner = $stripe.owner
        $ring = if ($along -in 0..4) { 'core' } elseif ($along -in @(-1, 5)) { 'border' } else { 'outer' }
        foreach ($slot in $reservation.slots) {
            $leases.Add([pscustomobject]@{ tileX = $slot.tileX; tileY = $slot.tileY; ring = $ring; owner = $reservation.owner; emitsInstance = $slot.emitsInstance })
            if ($ring -eq 'core') {
                $placements["$($slot.tileX),$($slot.tileY)"] = @($stripe.placements | Where-Object { $_.tileX -eq $slot.tileX -and $_.tileY -eq $slot.tileY })[0]
            }
        }
        if ($ring -ne 'core') {
            $owner.targetname = $(if ($ring -eq 'border') { 'zm_border' } else { 'zm_outer' }) + "_motorway_$along"
            $owner | Add-Member -NotePropertyName ring -NotePropertyValue $ring
            $ringPlacements.Add($owner)
        }
    }
    if ($placements.Count -ne 25) { throw 'Wide motorway inspection must cover every core slot exactly once.' }
    $Recipe.tilePlacements = @($placements.Values | Sort-Object tileY, tileX)
    $Recipe.forceCarpark = $false
    $Recipe.selectedChunkTemplate = $template
    $Recipe.desiredChunkTemplate = $template
    $Recipe.buildingTemplates = @()
    $Recipe | Add-Member -NotePropertyName motorwayCellInspection -NotePropertyValue ([pscustomobject]@{
        schemaVersion = 1; status = 'cell_geometry_inspection_not_live_travel'; template = $template
        sourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        orientation = $Recipe.orientation; yaw = $yaw; corridorWidthTiles = 3
        ringPlacements = @($ringPlacements); leases = @($leases); sceneryChanges = @($sceneryChanges)
        limits = @('Straight motorway only; junction/ramp/bridge cells fail explicitly.', 'No legacy narrow transition triggers or blockers; live travel remains Phase E.', 'Current scenery selection is not full Phase D density acceptance.')
    })
}

function Assert-ZMStraightMotorwayCellContract {
    param([Parameter(Mandatory = $true)][object]$Recipe)

    $inspection = $Recipe.motorwayCellInspection
    if ($inspection.schemaVersion -ne 1 -or $inspection.status -ne 'cell_geometry_inspection_not_live_travel' -or
        $Recipe.topology -ne 'motorway-straight' -or $Recipe.transportFeature -ne 'none' -or
        $Recipe.orientation -notin @('vertical', 'horizontal') -or $Recipe.tileGridSize -ne 5 -or
        $null -ne $Recipe.safeZoneEntrance -or @($Recipe.waterBorderSides).Count -gt 0 -or
        @($Recipe.skyboxOceanSides).Count -gt 0 -or @($Recipe.landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0 -or
        $inspection.orientation -ne $Recipe.orientation -or $inspection.corridorWidthTiles -ne 3 -or
        $inspection.yaw -ne $(if ($Recipe.orientation -eq 'vertical') { 0 } else { 90 })) {
        throw 'Invalid straight motorway orientation, bounds or inspection contract.'
    }
    $coreOwners = @($Recipe.tilePlacements | Where-Object role -eq motorway_assembly)
    if ($inspection.leases.Count -ne 27 -or $inspection.ringPlacements.Count -ne 4 -or $coreOwners.Count -ne 5 -or
        @($Recipe.tilePlacements | Where-Object role -eq motorway_occupied).Count -ne 10 -or
        @($Recipe.tilePlacements | Where-Object { $_.role -notin @('motorway_assembly', 'motorway_occupied', 'terrain', 'decoration') }).Count -gt 0) {
        throw 'Incomplete straight motorway cell corridor or forbidden motorway scenery.'
    }
    $leased = @{}
    foreach ($lease in $inspection.leases) {
        $key = "$($lease.tileX),$($lease.tileY)"
        if ($leased.ContainsKey($key)) { throw "Duplicate motorway ring/core lease at $key." }
        $leased[$key] = $lease
    }
    $owners = @{}
    foreach ($owner in $coreOwners + @($inspection.ringPlacements)) {
        if ($owners.ContainsKey([string]$owner.placementId)) { throw "Duplicate motorway emitting owner '$($owner.placementId)'." }
        $owners[[string]$owner.placementId] = $owner
    }
    $core = @{}
    foreach ($record in $Recipe.tilePlacements) {
        $key = "$($record.tileX),$($record.tileY)"
        if ($record.tileX -notin 0..4 -or $record.tileY -notin 0..4 -or $core.ContainsKey($key)) {
            throw "Invalid or duplicate motorway core slot at $key."
        }
        $core[$key] = $record
    }
    if ($core.Count -ne 25) { throw 'Motorway cell requires all 25 core slots.' }
    foreach ($along in -2..6) {
        $anchorX = if ($Recipe.orientation -eq 'vertical') { 1 } else { $along }
        $anchorY = if ($Recipe.orientation -eq 'vertical') { $along } else { 1 }
        $expected = Get-ZMMotorwayReservation $inspection.template $inspection.yaw $anchorX $anchorY "motorway:$along"
        $ring = if ($along -in 0..4) { 'core' } elseif ($along -in @(-1, 5)) { 'border' } else { 'outer' }
        if (-not $owners.ContainsKey($expected.owner)) { throw "Missing motorway emitting owner '$($expected.owner)'." }
        $owner = $owners[$expected.owner]
        if ($owner.tileX -ne $anchorX -or $owner.tileY -ne $anchorY -or
            $owner.ownerTileX -ne $anchorX -or $owner.ownerTileY -ne $anchorY -or
            $owner.template -ne $inspection.template -or $owner.rotationYaw -ne $inspection.yaw -or
            $owner.footprintWidth -ne $expected.width -or $owner.footprintHeight -ne $expected.height -or
            $owner.authoredWidth -ne 3 -or $owner.authoredHeight -ne 1 -or
            $owner.role -ne 'motorway_assembly' -or -not $owner.emitsInstance -or
            ($ring -ne 'core' -and $owner.ring -ne $ring)) {
            throw "Invalid motorway emitting geometry for '$($expected.owner)'."
        }
        $origin = Convert-ZMMotorwayPoint $owner.originCellLocal 0
        if ($origin.x -ne ($expected.centerTileX - 2) * 640 -or
            $origin.y -ne (2 - $expected.centerTileY) * 640 -or $origin.z -ne 0) {
            throw "Motorway physical origin differs from its approved reservation for '$($expected.owner)'."
        }
        foreach ($slot in $expected.slots) {
            $key = "$($slot.tileX),$($slot.tileY)"
            if (-not $leased.ContainsKey($key) -or $leased[$key].owner -ne $expected.owner -or
                $leased[$key].ring -ne $ring -or $leased[$key].emitsInstance -ne $slot.emitsInstance) {
                throw "Invalid or missing wide motorway lease at $key."
            }
            if ($ring -eq 'core') {
                $record = $core[$key]
                if ($record.placementId -ne $expected.owner -or $record.ownerTileX -ne $anchorX -or
                    $record.ownerTileY -ne $anchorY -or $record.template -ne $inspection.template -or
                    $record.rotationYaw -ne $inspection.yaw -or $record.emitsInstance -ne $slot.emitsInstance -or
                    $record.role -ne $(if ($slot.emitsInstance) { 'motorway_assembly' } else { 'motorway_occupied' })) {
                    throw "Invalid motorway core ownership at $key."
                }
            }
        }
    }
    return $leased
}

















function Get-ZMComplexMotorwayGates {
    param([Parameter(Mandatory = $true)][object]$Contract)

    $authority = $Contract.PSObject.Properties['assemblyAuthority']
    if ($Contract.schemaVersion -ne 2 -or $Contract.status -ne 'normal_complex_travel_pending' -or
        $null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout') {
        throw 'Normal complex motorway gates require a trusted approved grid contract.'
    }
    $gates = @($Contract.gates)
    if ($gates.Count -eq 0) { throw 'Trusted complex motorway contract has no approved gate records.' }
    $directions = @($gates | ForEach-Object { [string]$_.direction })
    if (@($directions | Where-Object { $_ -notin @('N', 'E', 'S', 'W') }).Count -gt 0 -or
        @($directions | Sort-Object -Unique).Count -ne $directions.Count) {
        throw 'Trusted complex motorway contract has invalid or duplicate gate directions.'
    }
    foreach ($gate in $gates) {
        $expectedLanes = if ($gate.route -eq 'motorway') { 2 } elseif ($gate.route -eq 'road') { 1 } else { 0 }
        if ($expectedLanes -eq 0 -or @($gate.lanes).Count -ne $expectedLanes) {
            throw "Trusted complex motorway gate has an invalid route/lane contract: $($gate.direction)"
        }
    }
    return $gates
}

function Get-ZMComplexMotorwayContract {
    param([Parameter(Mandatory = $true)][object]$Recipe)

    $property = $Recipe.PSObject.Properties['motorwayAssembly']
    if ($null -eq $property -or $null -eq $property.Value -or $property.Value.schemaVersion -ne 2) { return $null }
    $authority = $property.Value.PSObject.Properties['assemblyAuthority']
    if ($null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout') {
        throw "Complex motorway contract is not from the trusted approved plan: $($Recipe.cellTemplateFilename)"
    }
    return $property.Value
}



Export-ModuleMember -Function Get-ZMComplexMotorwayContract, Get-ZMMotorwayFootprint, Get-ZMMotorwayReservation, New-ZMStraightMotorwayStripe, Get-ZMNormalStraightMotorwayContract, Resolve-ZMNormalStraightMotorwayRings, Set-ZMStraightMotorwayCellInspection, Assert-ZMStraightMotorwayCellContract, Get-ZMComplexMotorwayGates
