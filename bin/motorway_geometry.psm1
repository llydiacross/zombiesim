Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMMotorwayFootprint {
    param([Parameter(Mandatory = $true)][string]$Template)

    $canonical = $Template.Replace('/', '\')
    if ([System.IO.Path]::GetExtension($canonical) -ine '.vmf' -or $canonical -match '(?i)(^|\\)motorway_1x1\\') {
        throw "Expected a wide motorway VMF, not a legacy/other asset: '$Template'."
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($canonical)
    if ($name -eq 'tile_motorway' -or $name -eq 'tile_motorway_road_bridge') {
        return [pscustomobject]@{ width = 3; height = 1 }
    }
    if ($name -notin @(
        'tile_motorway_corner_5x3', 'tile_motorway_crossroads_6x3',
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

function Convert-ZMMotorwayEnvelope {
    param(
        [Parameter(Mandatory = $true)][object]$Bounds,
        [Parameter(Mandatory = $true)][ValidateSet(0, 90, 180, 270)][int]$Yaw
    )

    foreach ($axis in @('x', 'y', 'z')) {
        if ([double]$Bounds.$axis.min -gt [double]$Bounds.$axis.max) { throw "Motorway envelope has reversed $axis bounds." }
    }
    $corners = @(foreach ($x in @($Bounds.x.min, $Bounds.x.max)) {
        foreach ($y in @($Bounds.y.min, $Bounds.y.max)) {
            foreach ($z in @($Bounds.z.min, $Bounds.z.max)) {
                Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $x; y = $y; z = $z }) $Yaw
            }
        }
    })
    $result = [ordered]@{}
    foreach ($axis in @('x', 'y', 'z')) {
        $range = $corners | Measure-Object -Property $axis -Minimum -Maximum
        $result[$axis] = [pscustomobject]@{ min = $range.Minimum; max = $range.Maximum }
    }
    return [pscustomobject]$result
}

function Get-ZMMotorwaySurfacePorts {
    param([Parameter(Mandatory = $true)][object]$SurveyPiece)

    Get-ZMMotorwayFootprint ([string]$SurveyPiece.source) | Out-Null
    $name = [System.IO.Path]::GetFileName([string]$SurveyPiece.source)
    if ($name -notin @('tile_motorway.vmf', 'tile_motorway_road_bridge.vmf')) {
        throw "Surface port contract not yet recorded for '$name'; no inferred connector fallback."
    }
    $ports = [System.Collections.Generic.List[object]]::new()
    foreach ($lane in @(
        @{ id = 'west_carriageway'; sides = @('120', '126') },
        @{ id = 'east_carriageway'; sides = @('252', '258') }
    )) {
        $faces = @(foreach ($id in $lane.sides) {
            $matches = @($SurveyPiece.faces | Where-Object sideId -eq $id)
            if ($matches.Count -ne 1) { throw "Source port face '$id' missing/ambiguous in '$name'." }
            $face = $matches[0]
            if (-not $face.horizontal -or $face.displacement -or $face.material -ne 'CONCRETE/CONCRETEFLOOR037A') {
                throw "Source port face '$id' changed surface contract in '$name'."
            }
            $face
        })
        $segments = @($faces | ForEach-Object {
            $xr = $_.vertices | Measure-Object x -Minimum -Maximum
            $yr = $_.vertices | Measure-Object y -Minimum -Maximum
            [pscustomobject]@{ min = $xr.Minimum; max = $xr.Maximum; yMin = $yr.Minimum; yMax = $yr.Maximum; z = $_.vertices[0].z }
        } | Sort-Object min)
        if ($segments[0].max -ne $segments[1].min -or $segments[0].yMin -ne $segments[1].yMin -or $segments[0].yMax -ne $segments[1].yMax -or $segments[0].z -ne $segments[1].z) {
            throw "Source carriageway segments do not meet exactly in '$name' ($($lane.id))."
        }
        foreach ($direction in @('N', 'S')) {
            $ports.Add([pscustomobject]@{
                id = "$direction/$($lane.id)"
                route = 'motorway'
                position = [pscustomobject]@{ x = ($segments[0].min + $segments[1].max) / 2; y = $(if ($direction -eq 'N') { $segments[0].yMax } else { $segments[0].yMin }); z = $segments[0].z }
                outward = $direction
                width = $segments[1].max - $segments[0].min
                grade = 0.0
                sourceSides = $lane.sides
            })
        }
    }
    if ($name -eq 'tile_motorway_road_bridge.vmf') {
        $ids = @('642', '690', '738')
        $faces = @(foreach ($id in $ids) {
            $matches = @($SurveyPiece.faces | Where-Object sideId -eq $id)
            if ($matches.Count -ne 1 -or -not $matches[0].horizontal -or $matches[0].displacement -or $matches[0].material -ne 'CONCRETE/CONCRETEFLOOR037A') {
                throw "Bridge road surface contract changed at face '$id'."
            }
            $matches[0]
        })
        $segments = @($faces | ForEach-Object {
            $xr = $_.vertices | Measure-Object x -Minimum -Maximum
            $yr = $_.vertices | Measure-Object y -Minimum -Maximum
            [pscustomobject]@{ min = $xr.Minimum; max = $xr.Maximum; yMin = $yr.Minimum; yMax = $yr.Maximum; z = $_.vertices[0].z }
        } | Sort-Object min)
        for ($index = 1; $index -lt 3; $index++) {
            if ($segments[$index - 1].max -ne $segments[$index].min -or $segments[0].yMin -ne $segments[$index].yMin -or $segments[0].yMax -ne $segments[$index].yMax -or $segments[0].z -ne $segments[$index].z) {
                throw 'Bridge road surface segments do not meet exactly.'
            }
        }
        foreach ($direction in @('E', 'W')) {
            $ports.Add([pscustomobject]@{
                id = "$direction/road"
                route = 'road'
                position = [pscustomobject]@{ x = $(if ($direction -eq 'E') { $segments[2].max } else { $segments[0].min }); y = ($segments[0].yMin + $segments[0].yMax) / 2; z = $segments[0].z }
                outward = $direction
                width = $segments[0].yMax - $segments[0].yMin
                grade = 0.0
                sourceSides = $ids
            })
        }
    }
    return @($ports)
}

function Convert-ZMMotorwayPort {
    param(
        [Parameter(Mandatory = $true)][object]$Port,
        [Parameter(Mandatory = $true)][ValidateSet(0, 90, 180, 270)][int]$Yaw,
        [Parameter(Mandatory = $true)][object]$Origin
    )

    $normal = switch ($Port.outward) {
        'N' { [pscustomobject]@{ x = 0; y = 1; z = 0 } }
        'E' { [pscustomobject]@{ x = 1; y = 0; z = 0 } }
        'S' { [pscustomobject]@{ x = 0; y = -1; z = 0 } }
        'W' { [pscustomobject]@{ x = -1; y = 0; z = 0 } }
        default { throw "Invalid motorway port heading '$($Port.outward)'." }
    }
    if ($Port.route -notin @('road', 'motorway') -or [double]$Port.width -le 0 -or [double]::IsNaN([double]$Port.width) -or [double]::IsInfinity([double]$Port.width) -or [double]::IsNaN([double]$Port.grade) -or [double]::IsInfinity([double]$Port.grade)) {
        throw "Invalid motorway port dimensions/type for '$($Port.id)'."
    }
    $p = Convert-ZMMotorwayPoint $Port.position $Yaw
    $o = Convert-ZMMotorwayPoint $Origin 0
    $n = Convert-ZMMotorwayPoint $normal $Yaw
    $heading = if ($n.y -eq 1) { 'N' } elseif ($n.x -eq 1) { 'E' } elseif ($n.y -eq -1) { 'S' } else { 'W' }
    return [pscustomobject]@{
        id = $Port.id; route = $Port.route; width = [double]$Port.width; grade = [double]$Port.grade
        outward = $heading
        position = [pscustomobject]@{ x = $p.x + $o.x; y = $p.y + $o.y; z = $p.z + $o.z }
    }
}

function Resolve-ZMMotorwayPortTranslation {
    param(
        [Parameter(Mandatory = $true)][object]$FixedPort,
        [Parameter(Mandatory = $true)][object]$MovingPort,
        [Parameter(Mandatory = $true)][ValidateSet(0, 90, 180, 270)][int]$MovingYaw,
        [Parameter(Mandatory = $true)][double]$MovingOriginZ
    )

    $origin = [pscustomobject]@{ x = 0; y = 0; z = $MovingOriginZ }
    $moving = Convert-ZMMotorwayPort $MovingPort $MovingYaw $origin
    $fixed = Convert-ZMMotorwayPort $FixedPort 0 ([pscustomobject]@{ x = 0; y = 0; z = 0 })
    $opposite = @{ N = 'S'; S = 'N'; E = 'W'; W = 'E' }
    if ($fixed.outward -ne $opposite[$moving.outward]) { throw 'Motorway connection headings must oppose at the existing mapped yaw.' }
    if ($fixed.route -ne $moving.route) { throw 'Motorway connection route types differ.' }
    if ($fixed.width -ne $moving.width) { throw 'Motorway connection surface widths differ.' }
    if ($fixed.position.z -ne $moving.position.z) { throw 'Motorway connection deck heights differ; vertical correction is not authorized.' }
    if ($fixed.grade -ne -$moving.grade) { throw 'Motorway connection outward grades do not match.' }
    return [pscustomobject]@{
        x = $fixed.position.x - $moving.position.x
        y = $fixed.position.y - $moving.position.y
        z = $MovingOriginZ
    }
}

function Get-ZMMotorwayMouthRegistry {
    param([Parameter(Mandatory = $true)][object]$SurveyPiece)

    $footprint = Get-ZMMotorwayFootprint ([string]$SurveyPiece.source)
    $name = [System.IO.Path]::GetFileNameWithoutExtension([string]$SurveyPiece.source)
    # Each list identifies the actual floor faces, not a boundary inferred from the AABB.
    $specs = @(switch ($name) {
        'tile_motorway' { @(@('N', 'motorway', '120,126', '342,384'), @('S', 'motorway', '120,126', '342,384')) }
        'tile_motorway_road_bridge' { @(@('N', 'motorway', '120,126', '252,258'), @('S', 'motorway', '120,126', '252,258'), @('E', 'road', '738'), @('W', 'road', '642')) }
        'tile_motorway_corner_5x3' { @(@('E', 'motorway', '5556,5562', '4314,4320'), @('S', 'motorway', '6594,6600', '6401,6443')) }
        'tile_motorway_crossroads_6x3' { @(@('N', 'motorway', '10417,10429', '6594,6600'), @('S', 'motorway', '10417,10429', '6594,6600'), @('W', 'motorway', '4314,4320', '9565,9571'), @('E', 'motorway', '10157,10163', '7212,7218')) }
        'tile_motorway_tjunction_6x3' { @(@('N', 'motorway', '7463,7493', '6594,6600'), @('W', 'motorway', '4314,4320', '5556,5562'), @('E', 'motorway', '7164,7170', '7212,7218')) }
        'tile_motorway_deadend_3x3' { ,@('S', 'motorway', '120,126', '2442,2448') }
        'tile_motorway_onramp_3x4' { @(@('W', 'motorway', '2114,2120', '2066,2072'), @('E', 'motorway', '3307,3313', '2248,2254'), @('N', 'road', '2350')) }
        'tile_motorway_onramp_dual_3x4' { @(@('W', 'motorway', '2114,2120', '3470,3518'), @('E', 'motorway', '3181,3187', '3308,3314'), @('N', 'road', '2350'), @('S', 'road', '3169')) }
        default { throw "Motorway mouth registry missing '$name'." }
    })
    $mouths = @(foreach ($spec in $specs) {
        $direction = $spec[0]
        $axis = if ($direction -in @('N', 'S')) { 'y' } else { 'x' }
        $lateral = if ($axis -eq 'y') { 'x' } else { 'y' }
        $sign = if ($direction -in @('N', 'E')) { 1 } else { -1 }
        $lanes = @(for ($laneIndex = 2; $laneIndex -lt $spec.Count; $laneIndex++) {
            $ids = $spec[$laneIndex].Split(',')
            $edges = @(foreach ($id in $ids) {
                $faces = @($SurveyPiece.faces | Where-Object sideId -eq $id)
                if ($faces.Count -ne 1 -or $faces[0].material -ne 'CONCRETE/CONCRETEFLOOR037A' -or $faces[0].displacement) {
                    throw "Motorway mouth face '$id' changed/missing in '$name'."
                }
                $vertices = @($faces[0].vertices)
                if ($vertices.Count -lt 3) { throw "Motorway mouth face '$id' has no complete winding." }
                foreach ($vertex in $vertices) { Convert-ZMMotorwayPoint $vertex 0 | Out-Null }
                $p = $vertices[0]; $q = $vertices[1]; $r = $vertices[2]
                $ux = $q.x - $p.x; $uy = $q.y - $p.y; $uz = $q.z - $p.z
                $vx = $r.x - $p.x; $vy = $r.y - $p.y; $vz = $r.z - $p.z
                $nz = $ux * $vy - $uy * $vx
                if ($nz -ge 0) { throw "Motorway mouth face '$id' is not an upward floor winding." }
                $slope = if ($axis -eq 'x') { ($uz * $vy - $uy * $vz) / $nz } else { ($ux * $vz - $uz * $vx) / $nz }
                $candidates = @(for ($i = 0; $i -lt $vertices.Count; $i++) {
                    $a = $vertices[$i]
                    $b = $vertices[($i + 1) % $vertices.Count]
                    [pscustomobject]@{ a = $a; b = $b; score = $sign * ([double]$a.$axis + [double]$b.$axis) / 2 }
                })
                $edge = @($candidates | Sort-Object score -Descending)[0]
                [pscustomobject]@{ side = $id; a = $edge.a; b = $edge.b; outwardGrade = $sign * $slope }
            })
            $points = @($edges | ForEach-Object { $_.a; $_.b })
            $range = $points | Measure-Object -Property $lateral -Minimum -Maximum
            $outer = @($points | Sort-Object $lateral)
            $a = $outer[0]
            $b = $outer[-1]
            $intervals = @($edges | ForEach-Object {
                [pscustomobject]@{ min = [Math]::Min($_.a.$lateral, $_.b.$lateral); max = [Math]::Max($_.a.$lateral, $_.b.$lateral) }
            } | Sort-Object min)
            $gaps = @(for ($index = 1; $index -lt $intervals.Count; $index++) { $intervals[$index].min - $intervals[$index - 1].max })
            [pscustomobject]@{
                id = "$direction/lane$($laneIndex - 1)"
                route = $spec[1]; outward = $direction
                position = [pscustomobject]@{ x = ([double]$a.x + [double]$b.x) / 2; y = ([double]$a.y + [double]$b.y) / 2; z = ([double]$a.z + [double]$b.z) / 2 }
                width = $range.Maximum - $range.Minimum
                grade = $edges[0].outwardGrade
                consistentGrade = @($edges | Where-Object { $_.outwardGrade -ne $edges[0].outwardGrade }).Count -eq 0
                edgeGaps = $gaps
                contiguousEdges = @($gaps | Where-Object { $_ -ne 0 }).Count -eq 0
                edges = $edges
                planarCardinal = @($points | Where-Object { $_.$axis -ne $a.$axis -or $_.z -ne $a.z }).Count -eq 0
                sourceSides = $ids
            }
        })
        [pscustomobject]@{ outward = $direction; route = $spec[1]; lanes = $lanes }
    })
    return [pscustomobject]@{
        template = [string]$SurveyPiece.source
        sha256 = $SurveyPiece.sha256
        width = $footprint.width; height = $footprint.height
        envelope = $SurveyPiece.windingBounds
        mouths = $mouths
        status = 'saved_surface_contract_not_compiled_collision'
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

function Get-ZMStraightMotorwayMouths {
    param([Parameter(Mandatory = $true)][string]$TemplatePath)

    Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1')
    $hash = (Get-FileHash -LiteralPath $TemplatePath -Algorithm SHA256).Hash
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($TemplatePath))
    $faces = [System.Collections.Generic.List[object]]::new()
    foreach ($owner in @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)) {
        if ($null -eq $owner) { throw "Motorway mouth source has no world: $TemplatePath" }
        foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
            foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                if ($side.Get('id') -notin @('120', '126', '342', '384')) { continue }
                $winding = $side.Child('vertices_plus')
                if ($null -eq $winding) { throw "Motorway mouth side $($side.Get('id')) has no saved winding." }
                $vertices = @(foreach ($text in $winding.GetAll('v')) {
                    $point = [ZombieSim.Skybox.Vec3]::Parse($text)
                    [pscustomobject]@{ x = $point.X; y = $point.Y; z = $point.Z }
                })
                $faces.Add([pscustomobject]@{
                    sideId = $side.Get('id'); material = $side.Get('material')
                    displacement = $null -ne $side.Child('dispinfo'); vertices = $vertices
                })
            }
        }
    }
    $registry = Get-ZMMotorwayMouthRegistry ([pscustomobject]@{
        source = $TemplatePath; sha256 = $hash; windingBounds = $null; faces = @($faces)
    })
    if ($hash -cne (Get-FileHash -LiteralPath $TemplatePath -Algorithm SHA256).Hash) {
        throw 'Straight motorway source changed during mouth measurement.'
    }
    return $registry
}

function Get-ZMNormalStraightMotorwayGates {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$MouthRegistry
    )

    if ($Contract.schemaVersion -ne 1 -or $Contract.status -ne 'normal_reservations_travel_pending' -or
        $Contract.sourceSha256 -cne $MouthRegistry.sha256 -or
        [IO.Path]::GetFileName($Contract.template) -ne [IO.Path]::GetFileName($MouthRegistry.template) -or
        $Contract.orientation -notin @('vertical', 'horizontal') -or
        $Contract.yaw -ne $(if ($Contract.orientation -eq 'vertical') { 0 } else { 90 })) {
        throw 'Measured straight gates require a matching normal source/orientation contract.'
    }
    $gates = @(foreach ($mouth in $MouthRegistry.mouths) {
        if ($mouth.route -ne 'motorway' -or $mouth.lanes.Count -ne 2) {
            throw 'Straight motorway boundary requires two measured carriageways.'
        }
        $ports = @(foreach ($lane in $mouth.lanes) {
            if (-not $lane.planarCardinal -or -not $lane.contiguousEdges -or -not $lane.consistentGrade -or $lane.grade -ne 0) {
                throw 'Straight motorway gate requires contiguous flat cardinal floor mouths.'
            }
            Convert-ZMMotorwayPort $lane $Contract.yaw ([pscustomobject]@{ x = 0; y = 0; z = 0 })
        })
        $direction = $ports[0].outward
        $along = if ($direction -in @('N', 'W')) { -1 } else { 5 }
        $boundaryOwner = @($Contract.ringPlacements | Where-Object placementId -eq "motorway:$along")
        if ($boundaryOwner.Count -ne 1 -or $boundaryOwner[0].ring -ne 'border') {
            throw 'Measured motorway gate has no unique border stripe owner.'
        }
        $expectedStripe = New-ZMStraightMotorwayStripe $Contract.orientation $along $Contract.template
        $origin = Convert-ZMMotorwayPoint $boundaryOwner[0].originCellLocal 0
        if ($origin.x -ne $expectedStripe.owner.originCellLocal.x -or
            $origin.y -ne $expectedStripe.owner.originCellLocal.y -or $origin.z -ne 0) {
            throw 'Measured motorway gate border origin differs from its approved stripe.'
        }
        $forward = @{ N = @(0, 1); E = @(1, 0); S = @(0, -1); W = @(-1, 0) }[$direction]
        $right = @($forward[1], -$forward[0])
        $lanes = @(foreach ($port in $ports) {
            $offset = $port.position.x * $right[0] + $port.position.y * $right[1]
            $origin = $boundaryOwner[0].originCellLocal
            $boundary = ($port.position.x + $origin.x) * $forward[0] + ($port.position.y + $origin.y) * $forward[1]
            if ($boundary -ne 2240) { throw 'Measured motorway carriageway does not meet the traversable boundary.' }
            [pscustomobject]@{
                lateral = $offset; width = $port.width; deckZ = $port.position.z + $origin.z
                arrowX = $forward[0] * (2208 - 256) + $right[0] * $offset
                arrowY = $forward[1] * (2208 - 256) + $right[1] * $offset
                arrivalX = $forward[0] * (2208 - 384) + $right[0] * $offset
                arrivalY = $forward[1] * (2208 - 384) + $right[1] * $offset
                sourcePort = $port.id
            }
        })
        $lanes = @($lanes | Sort-Object lateral)
        if ($lanes[0].lateral -ge 0 -or $lanes[1].lateral -le 0 -or $lanes[0].deckZ -ne $lanes[1].deckZ) {
            throw 'Measured motorway carriageways must straddle the axis at one deck height.'
        }
        $min = $lanes[0].lateral - $lanes[0].width / 2
        $max = $lanes[1].lateral + $lanes[1].width / 2
        [pscustomobject]@{
            direction = $direction; x = $forward[0] * 2208; y = $forward[1] * 2208
            lateralMin = $min; lateralMax = $max; deckZ = $lanes[0].deckZ
            lanes = $lanes; arrivalLane = 1
            status = 'measured_source_gate_not_compiled_or_live'
        }
    })
    $gates = @($gates | Sort-Object direction)
    $expected = if ($Contract.orientation -eq 'vertical') { 'N,S' } else { 'E,W' }
    if ($gates.Count -ne 2 -or ($gates.direction -join ',') -ne $expected) {
        throw 'Measured straight gate headings disagree with normal topology.'
    }
    return $gates
}

function New-ZMNormalStraightMotorwayContract {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][string]$TemplateDirectory
    )

    $owners = @($Recipe.tilePlacements | Where-Object role -eq motorway_assembly)
    if ($owners.Count -ne 5) { throw 'Normal straight motorway requires five planned core owners.' }
    $template = [string]$owners[0].template
    $source = Join-Path $TemplateDirectory $template
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Normal motorway source missing: $source" }
    $rings = [System.Collections.Generic.List[object]]::new()
    $leases = [System.Collections.Generic.List[object]]::new()
    foreach ($along in -2..6) {
        $stripe = New-ZMStraightMotorwayStripe $Recipe.orientation $along $template
        $ring = if ($along -in 0..4) { 'core' } elseif ($along -in @(-1, 5)) { 'border' } else { 'outer' }
        foreach ($slot in $stripe.reservation.slots) {
            $leases.Add([pscustomobject]@{
                tileX = $slot.tileX; tileY = $slot.tileY; ring = $ring
                owner = $stripe.reservation.owner; emitsInstance = $slot.emitsInstance
            })
        }
        if ($ring -ne 'core') {
            $stripe.owner.targetname = $(if ($ring -eq 'border') { 'zm_border' } else { 'zm_outer' }) + "_motorway_$along"
            $stripe.owner | Add-Member -NotePropertyName ring -NotePropertyValue $ring
            $rings.Add($stripe.owner)
        }
    }
    $contract = [pscustomobject]@{
        schemaVersion = 1; status = 'normal_reservations_travel_pending'; template = $template
        sourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        orientation = $Recipe.orientation; yaw = $owners[0].rotationYaw; corridorWidthTiles = 3
        ringPlacements = @($rings); leases = @($leases)
    }
    $validation = $Recipe.PSObject.Copy()
    $inspection = $contract.PSObject.Copy()
    $inspection.status = 'cell_geometry_inspection_not_live_travel'
    $validation | Add-Member -NotePropertyName motorwayCellInspection -NotePropertyValue $inspection
    Assert-ZMStraightMotorwayCellContract $validation | Out-Null
    $mouths = Get-ZMStraightMotorwayMouths $source
    $contract | Add-Member -NotePropertyName gates -NotePropertyValue @(Get-ZMNormalStraightMotorwayGates $contract $mouths)
    return $contract
}

function Resolve-ZMNormalStraightMotorwayRings {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][string]$TemplateDirectory,
        [object[]]$BorderPlacements,
        [object[]]$OuterPlacements
    )

    $contract = $Recipe.motorwayAssembly
    if ($null -ne $Recipe.PSObject.Properties['motorwayCellInspection'] -or
        $contract.schemaVersion -ne 1 -or $contract.status -ne 'normal_reservations_travel_pending') {
        throw 'Normal straight ring replacement requires a unique travel-pending normal contract.'
    }
    if ($contract.sourceSha256 -cne (Get-FileHash -LiteralPath (Join-Path $TemplateDirectory $contract.template) -Algorithm SHA256).Hash) {
        throw 'Normal straight motorway source changed; replan before ring replacement.'
    }
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

function Get-ZMInspectionWindingBounds {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($Path))
    $points = [System.Collections.Generic.List[object]]::new()
    foreach ($owner in @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)) {
        if ($null -eq $owner) { throw "Inspection source has no world: $Path" }
        foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
            foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                $winding = $side.Child('vertices_plus')
                if ($null -eq $winding) { throw "Missing saved winding in approach source: $Path side $($side.Get('id'))." }
                $vertices = @($winding.GetAll('v'))
                if ($vertices.Count -lt 3) { throw "Incomplete saved winding in approach source: $Path side $($side.Get('id'))." }
                foreach ($vertex in $vertices) {
                    $point = [ZombieSim.Skybox.Vec3]::Parse($vertex)
                    $points.Add((Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $point.X; y = $point.Y; z = $point.Z }) 0))
                }
            }
        }
    }
    if ($points.Count -eq 0) { throw "Inspection approach source has no saved winding vertices: $Path" }
    $bounds = [ordered]@{}
    foreach ($axis in @('x', 'y', 'z')) {
        $range = $points | Measure-Object -Property $axis -Minimum -Maximum
        $bounds[$axis] = [pscustomobject]@{ min = $range.Minimum; max = $range.Maximum }
    }
    return [pscustomobject]$bounds
}

function Join-ZMMotorwayAssemblyCases {
    param(
        [Parameter(Mandatory = $true)][object]$MainCase,
        [Parameter(Mandatory = $true)][object]$TransportCase
    )

    $main = $MainCase | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $transport = $TransportCase | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    foreach ($case in @($main, $transport)) {
        foreach ($instance in $case.instances) {
            foreach ($axis in @('x', 'y', 'z')) { $instance.origin.$axis -= $case.origin.$axis }
        }
        foreach ($connection in $case.connections) {
            foreach ($port in $connection.ports) {
                foreach ($axis in @('x', 'y', 'z')) { $port.position.$axis -= $case.origin.$axis }
            }
        }
    }
    $mounts = @($main.connections | Where-Object {
        $_.route -eq 'motorway' -and $_.ports[0].outward -in @($transport.connections |
            Where-Object route -eq motorway | ForEach-Object { $_.ports[0].outward })
    })
    if ($mounts.Count -ne 1) { throw 'Mixed motorway assembly requires one unambiguous outgoing mounting leg.' }
    $heading = $mounts[0].ports[0].outward
    $opposite = @{ N = 'S'; E = 'W'; S = 'N'; W = 'E' }[$heading]
    $incoming = @($transport.connections | Where-Object { $_.route -eq 'motorway' -and $_.ports[0].outward -eq $opposite })
    if ($incoming.Count -ne 1 -or $mounts[0].ports.Count -ne 2 -or $incoming[0].ports.Count -ne 2) {
        throw 'Mixed motorway insertion requires two measured lanes at both mouths.'
    }
    $lateral = if ($heading -in @('N', 'S')) { 'x' } else { 'y' }
    $fixed = @($mounts[0].ports | Sort-Object { $_.position.$lateral })
    $moving = @($incoming[0].ports | Sort-Object { $_.position.$lateral })
    $translation = [pscustomobject]@{}
    foreach ($axis in @('x', 'y', 'z')) {
        $translation | Add-Member -NotePropertyName $axis -NotePropertyValue ($fixed[0].position.$axis - $moving[0].position.$axis)
    }
    if ($translation.z -ne 0) { throw 'Mixed motorway insertion cannot vertically shift an authored assembly.' }
    $residuals = @(for ($lane = 0; $lane -lt 2; $lane++) {
        $delta = [ordered]@{ lane = $lane }
        foreach ($axis in @('x', 'y', 'z')) {
            $delta["d$axis"] = $fixed[$lane].position.$axis - ($moving[$lane].position.$axis + $translation.$axis)
        }
        $delta.widthDelta = $fixed[$lane].width - $moving[$lane].width
        $delta.gradeDelta = $fixed[$lane].grade + $moving[$lane].grade
        [pscustomobject]$delta
    })
    $exact = @($residuals | Where-Object { $_.dx -ne 0 -or $_.dy -ne 0 -or $_.dz -ne 0 -or $_.widthDelta -ne 0 -or $_.gradeDelta -ne 0 }).Count -eq 0
    $id = "$($MainCase.id)+$($TransportCase.id)"
    $instances = [System.Collections.Generic.List[object]]::new()
    foreach ($instance in $main.instances) {
        if ($instance.owner -eq "$($MainCase.id)/$heading/continuation") { continue }
        $instance.owner = $instance.owner.Replace($MainCase.id, $id)
        $instances.Add($instance)
    }
    foreach ($instance in $transport.instances) {
        if ($instance.owner -eq "$($TransportCase.id)/$opposite/continuation") { continue }
        foreach ($axis in @('x', 'y', 'z')) { $instance.origin.$axis += $translation.$axis }
        $instance.owner = if ($instance.owner -eq "$($TransportCase.id)/main") { "$id/transport" } else { $instance.owner.Replace($TransportCase.id, $id) }
        $instances.Add($instance)
    }
    $connections = @($main.connections | Where-Object { $_.ports[0].outward -ne $heading }) +
        @($transport.connections | Where-Object { $_.route -ne 'motorway' -or $_.ports[0].outward -ne $opposite })
    foreach ($connection in $transport.connections) {
        foreach ($port in $connection.ports) {
            foreach ($axis in @('x', 'y', 'z')) { $port.position.$axis += $translation.$axis }
        }
        if ($connection.route -eq 'road') {
            $connection | Add-Member -NotePropertyName approachKind -NotePropertyValue $(if ([IO.Path]::GetFileName($TransportCase.piece) -like '*onramp*') { 'onramp' } else { 'bridge' })
        }
    }
    $bridgeDominant = [IO.Path]::GetFileName($MainCase.piece) -eq 'tile_motorway_deadend_3x3.vmf' -and
        [IO.Path]::GetFileName($TransportCase.piece) -eq 'tile_motorway_road_bridge.vmf'
    $frameShift = [pscustomobject]@{ x = 0; y = 0; z = 0 }
    if ($bridgeDominant) {
        foreach ($axis in @('x', 'y', 'z')) { $frameShift.$axis = -$translation.$axis }
        foreach ($instance in $instances) {
            foreach ($axis in @('x', 'y', 'z')) { $instance.origin.$axis += $frameShift.$axis }
        }
        foreach ($connection in $connections) {
            foreach ($port in $connection.ports) {
                foreach ($axis in @('x', 'y', 'z')) { $port.position.$axis += $frameShift.$axis }
            }
        }
    }
    return [pscustomobject]@{
        id = $id; piece = $MainCase.piece; yaw = $MainCase.yaw
        origin = [pscustomobject]@{ x = 0; y = 0; z = 0 }
        instances = @($instances); connections = $connections
        insertionSeam = [pscustomobject]@{
            heading = $heading; translation = $translation; residuals = $residuals
            dominantOwner = $(if ($bridgeDominant) { 'bridge' } else { 'topology' })
            frameShift = $frameShift
            status = $(if ($exact) { 'exact_floor_seam' } else { 'diagnostic_seam_not_approved' })
            playerStartCandidate = [pscustomobject]@{
                x = $fixed[0].position.x - @{ N = 0; E = 128; S = 0; W = -128 }[$heading] + $frameShift.x
                y = $fixed[0].position.y - @{ N = 128; E = 0; S = -128; W = 0 }[$heading] + $frameShift.y
                z = $fixed[0].position.z + $frameShift.z
                status = 'measured_floor_candidate_clearance_pending'
            }
        }
    }
}

function Assert-ZMMotorwaySpawnFloor {
    param([object]$Instance, [object]$Candidate)

    $point = Convert-ZMMotorwayPoint $Candidate 0
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($Instance.template))
    $owners = @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)
    $faces = @(foreach ($owner in $owners) {
        foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
            foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                if ($side.Get('material') -notlike '*CONCRETEFLOOR*') { continue }
                $winding = $side.Child('vertices_plus')
                if ($null -eq $winding) { throw 'Measured mixed spawn floor has no saved winding.' }
                $vertices = @(foreach ($text in $winding.GetAll('v')) {
                    $v = [ZombieSim.Skybox.Vec3]::Parse($text)
                    $p = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $v.X; y = $v.Y; z = $v.Z }) $Instance.yaw
                    foreach ($axis in @('x', 'y', 'z')) { $p.$axis += $Instance.origin.$axis }
                    $p
                })
                if ($vertices.Count -ge 3 -and @($vertices | Where-Object { [Math]::Abs($_.z - $point.z) -gt 0.001 }).Count -eq 0) {
                    ,$vertices
                }
            }
        }
    })
    foreach ($dx in @(-16, 16)) { foreach ($dy in @(-16, 16)) {
        $supported = $false
        foreach ($face in $faces) {
            $positive = $false; $negative = $false
            for ($i = 0; $i -lt $face.Count; $i++) {
                $a = $face[$i]; $b = $face[($i + 1) % $face.Count]
                $cross = ($b.x - $a.x) * ($point.y + $dy - $a.y) - ($b.y - $a.y) * ($point.x + $dx - $a.x)
                if ($cross -gt 0.001) { $positive = $true }
                if ($cross -lt -0.001) { $negative = $true }
            }
            if (-not ($positive -and $negative)) { $supported = $true; break }
        }
        if (-not $supported) { throw 'Mixed motorway spawn candidate lacks a source-measured flat floor beneath its hull.' }
    } }
}

function Get-ZMOrdinaryRoadMouths {
    param([Parameter(Mandatory = $true)][string]$TemplatePath)

    Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1')
    $name = [IO.Path]::GetFileName($TemplatePath)
    if ($name -notin @('tile_road.vmf', 'tile_road_corner.vmf', 'tile_road_straight_768.vmf', 'tile_road_onramp.vmf')) {
        throw "Unsupported centred-road source '$name'."
    }
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($TemplatePath))
    $faces = @(foreach ($owner in @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)) {
        foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
            foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                if ($side.Get('material') -notlike '*CONCRETEFLOOR*') { continue }
                $winding = $side.Child('vertices_plus')
                if ($null -eq $winding) { throw "Centred-road floor has no saved winding in '$name'." }
                $vertices = @($winding.GetAll('v') | ForEach-Object {
                    $v = [ZombieSim.Skybox.Vec3]::Parse($_)
                    [pscustomobject]@{ x = $v.X; y = $v.Y; z = $v.Z }
                })
                if ($vertices.Count -ge 3 -and @($vertices | Where-Object z -ne 36).Count -eq 0) { ,$vertices }
            }
        }
    })
    $directions = if ($name -eq 'tile_road_corner.vmf') { @('S', 'E') } elseif ($name -eq 'tile_road_onramp.vmf') { @('S') } else { @('S', 'N') }
    $halfLength = if ($name -eq 'tile_road_straight_768.vmf') { 384 } else { 320 }
    foreach ($heading in $directions) {
        $axis = if ($heading -in @('N', 'S')) { 'y' } else { 'x' }
        $lateral = if ($axis -eq 'y') { 'x' } else { 'y' }
        $edge = $halfLength * $(if ($heading -in @('N', 'E')) { 1 } else { -1 })
        $segments = @(@(foreach ($face in $faces) {
            for ($index = 0; $index -lt $face.Count; $index++) {
                $a = $face[$index]; $b = $face[($index + 1) % $face.Count]
                if ($a.$axis -eq $edge -and $b.$axis -eq $edge -and $a.$lateral -ne $b.$lateral) {
                    [pscustomobject]@{ min = [Math]::Min($a.$lateral, $b.$lateral); max = [Math]::Max($a.$lateral, $b.$lateral) }
                }
            }
        }) | Sort-Object min,max)
        $centre = 0
        if ($segments.Count -eq 0 -or $segments[0].min -ne $centre - 128) { throw "Centred-road $heading mouth changed in '$name'." }
        $end = $segments[0].max
        foreach ($segment in @($segments | Select-Object -Skip 1)) {
            if ($segment.min -gt $end) { throw "Centred-road $heading floor has a gap in '$name'." }
            $end = [Math]::Max($end, $segment.max)
        }
        if ($end -ne $centre + 128) { throw "Centred-road $heading width changed in '$name'." }
        $position = [pscustomobject]@{ x = 0; y = 0; z = 36 }
        $position.$axis = $edge
        $position.$lateral = $centre
        [pscustomobject]@{ id = "$heading/road"; route = 'road'; width = 256; grade = 0; outward = $heading; position = $position }
    }
}

function New-ZMCentredRoadApproach {
    param(
        [Parameter(Mandatory = $true)][object]$ApproachOrigin,
        [Parameter(Mandatory = $true)][ValidateSet('N', 'E', 'S', 'W')][string]$Heading,
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$TemplateDirectory
    )

    $yaw = @{ S = 0; E = 90; N = 180; W = 270 }[$Heading]
    $local = Convert-ZMMotorwayPoint $ApproachOrigin ((360 - $yaw) % 360)
    if ($local.z -ne 0 -or [Math]::Abs($local.x) -ne 1408) {
        throw 'Centred mixed road requires the approved 1408-unit ramp offset at authored Z.'
    }
    $row = $local.y - 640
    $positive = $local.x -gt 0
    $pieces = [System.Collections.Generic.List[object]]::new()
    $specs = @(
        @{ template = 'roads\tile_road_corner.vmf'; x = 0; y = $row; yaw = $(if ($positive) { 0 } else { 270 }); label = 'entry_corner' },
        @{ template = 'roads\connectors\tile_road_straight_768.vmf'; x = $local.x / 2; y = $row; yaw = 90; label = 'cross_straight' },
        @{ template = 'roads\tile_road_corner.vmf'; x = $local.x; y = $row; yaw = $(if ($positive) { 180 } else { 90 }); label = 'ramp_corner' }
    )
    foreach ($spec in $specs) {
        $origin = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $spec.x; y = $spec.y; z = 0 }) $yaw
        $pieces.Add([pscustomobject]@{
            template = $spec.template; yaw = ($spec.yaw + $yaw) % 360; origin = $origin
            owner = "$Owner/$($spec.label)"; status = 'exact_ordinary_road_floor_seam'
            disposition = 'source_measured_road_join_clearance_pending'; placementEligibility = 'inspection_only'
        })
    }
    $mouths = @(foreach ($piece in $pieces) {
        $ports = @(Get-ZMOrdinaryRoadMouths (Join-Path $TemplateDirectory $piece.template) | ForEach-Object {
            Convert-ZMMotorwayPort $_ $piece.yaw $piece.origin
        })
        [pscustomobject]@{ owner = $piece.owner; ports = $ports }
    })
    $joins = @(for ($index = 0; $index -lt 2; $index++) {
        $matches = @(foreach ($a in $mouths[$index].ports) { foreach ($b in $mouths[$index + 1].ports) {
            if ($a.position.x -eq $b.position.x -and $a.position.y -eq $b.position.y) {
                $translation = Resolve-ZMMotorwayPortTranslation $a $b 0 0
                if ($translation.x -ne 0 -or $translation.y -ne 0) { throw 'Centred-road join unexpectedly needs translation.' }
                [pscustomobject]@{ first = $mouths[$index].owner; second = $mouths[$index + 1].owner; position = $a.position; width = $a.width; status = 'exact_floor_seam' }
            }
        } })
        if ($matches.Count -ne 1) { throw 'Centred-road corner/straight mouths do not connect exactly.' }
        $matches[0]
    })
    $rampPort = Get-ZMOrdinaryRoadMouths (Join-Path $TemplateDirectory 'roads\tile_road_onramp.vmf')
    $rampPort = Convert-ZMMotorwayPort $rampPort $yaw $ApproachOrigin
    $rampMouth = $rampPort.position
    $opposite = @{ N = 'S'; E = 'W'; S = 'N'; W = 'E' }[$Heading]
    $end = @($mouths[2].ports | Where-Object outward -eq $opposite)
    if ($end.Count -ne 1 -or $end[0].position.x -ne $rampMouth.x -or $end[0].position.y -ne $rampMouth.y) {
        throw 'Centred-road last corner misses the retained ramp approach.'
    }
    Resolve-ZMMotorwayPortTranslation $end[0] $rampPort 0 0 | Out-Null
    $joins += [pscustomobject]@{ first = $mouths[2].owner; second = "$Owner/road_approach"; position = $rampMouth; width = $rampPort.width; status = 'exact_floor_seam' }
    $entry = @($mouths[0].ports | Where-Object outward -eq $Heading)[0]
    $boundaryEnd = -$row + 320
    while ($boundaryEnd -lt 2880) {
        if ($boundaryEnd + 640 -gt 2880) { throw 'Centred-road entry requires an unsupported partial boundary tile.' }
        $origin = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = 0; y = -$boundaryEnd - 320; z = 0 }) $yaw
        $pieces.Add([pscustomobject]@{
            template = 'roads\tile_road.vmf'; yaw = $yaw; origin = $origin; owner = "$Owner/entry_straight$boundaryEnd"
            status = 'exact_ordinary_road_floor_seam'; disposition = 'source_measured_road_join_clearance_pending'; placementEligibility = 'inspection_only'
        })
        $ports = @(Get-ZMOrdinaryRoadMouths (Join-Path $TemplateDirectory 'roads\tile_road.vmf') | ForEach-Object {
            Convert-ZMMotorwayPort $_ $yaw $origin
        })
        $inside = @($ports | Where-Object outward -eq $opposite)[0]
        $translation = Resolve-ZMMotorwayPortTranslation $entry $inside 0 0
        if ($translation.x -ne 0 -or $translation.y -ne 0) { throw 'Centred-road entry straight misses its inner floor mouth.' }
        $joins += [pscustomobject]@{ first = $Owner; second = $pieces[$pieces.Count - 1].owner; position = $entry.position; width = $entry.width; status = 'exact_floor_seam' }
        $entry = @($ports | Where-Object outward -eq $Heading)[0]
        $boundaryEnd += 640
    }
    if ($boundaryEnd -ne 2880) { throw 'Centred-road row lies beyond the approved cell frame.' }
    $boundary = Convert-ZMMotorwayPort ([pscustomobject]@{
        id = 'S/centred_road'; route = 'road'; width = 256; grade = 0; outward = 'S'
        position = [pscustomobject]@{ x = 0; y = -2880; z = 36 }
    }) $yaw ([pscustomobject]@{ x = 0; y = 0; z = 0 })
    if ($entry.position.x -ne $boundary.position.x -or $entry.position.y -ne $boundary.position.y -or $entry.position.z -ne $boundary.position.z) {
        throw 'Centred-road emitted floor does not reach its central boundary port.'
    }
    return [pscustomobject]@{
        heading = $Heading; entryAxis = 0; boundaryPort = $boundary; instances = @($pieces); joins = $joins
        status = 'centred_boundary_route_gate_integration_pending'
    }
}

function Get-ZMAssemblyFlatFloors {
    param([object[]]$Assemblies, [string]$TemplateDirectory)

    $sources = @{}
    foreach ($assembly in $Assemblies) {
        $path = Join-Path $TemplateDirectory $assembly.template
        if (-not $sources.ContainsKey($path)) { $sources[$path] = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($path)) }
        $tree = $sources[$path]
        foreach ($owner in @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)) {
            foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
                foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                    if ($side.Get('material') -notlike '*CONCRETEFLOOR*' -or $null -ne $side.Child('dispinfo')) { continue }
                    $winding = $side.Child('vertices_plus')
                    if ($null -eq $winding) { throw "Complex gate floor has no saved winding: $path" }
                    $vertices = @($winding.GetAll('v') | ForEach-Object {
                        $v = [ZombieSim.Skybox.Vec3]::Parse($_)
                        $p = Convert-ZMMotorwayPoint ([pscustomobject]@{ x = $v.X; y = $v.Y; z = $v.Z }) $assembly.yaw
                        foreach ($axis in @('x', 'y', 'z')) { $p.$axis += $assembly.origin.$axis }
                        $p
                    })
                    if ($vertices.Count -lt 3 -or @($vertices | Where-Object { $_.z -ne $vertices[0].z }).Count -gt 0) { continue }
                    [pscustomobject]@{ vertices = $vertices; deckZ = $vertices[0].z; owner = $assembly.owner; side = $side.Get('id') }
                }
            }
        }
    }
}

function Get-ZMAssemblyFloorSlices {
    param([object[]]$Floors, [string]$Direction, [double]$Along)

    $forward = @{ N = @(0, 1); E = @(1, 0); S = @(0, -1); W = @(-1, 0) }[$Direction]
    if ($null -eq $forward) { throw 'Measured complex floor requires a cardinal direction.' }
    $right = @($forward[1], -$forward[0])
    foreach ($floor in $Floors) {
        $vertices = @($floor.vertices | ForEach-Object {
            [pscustomobject]@{ along = $_.x * $forward[0] + $_.y * $forward[1]; lateral = $_.x * $right[0] + $_.y * $right[1] }
        })
        $range = $vertices | Measure-Object along -Minimum -Maximum
        if ($range.Minimum -ge $range.Maximum -or $Along -lt $range.Minimum -or $Along -gt $range.Maximum) { continue }
        $cuts = @(for ($index = 0; $index -lt $vertices.Count; $index++) {
            $a = $vertices[$index]; $b = $vertices[($index + 1) % $vertices.Count]
            if ($a.along -eq $b.along) {
                if ($a.along -eq $Along) { $a.lateral; $b.lateral }
            } elseif ($Along -ge [Math]::Min($a.along, $b.along) -and $Along -le [Math]::Max($a.along, $b.along)) {
                $a.lateral + ($b.lateral - $a.lateral) * ($Along - $a.along) / ($b.along - $a.along)
            }
        })
        if ($cuts.Count -lt 2) { continue }
        $cross = $cuts | Measure-Object -Minimum -Maximum
        if ($cross.Minimum -eq $cross.Maximum) { continue }
        [pscustomobject]@{
            min = [double]$cross.Minimum; max = [double]$cross.Maximum; deckZ = $floor.deckZ
            owner = $floor.owner; side = $floor.side
        }
    }
}

function Test-ZMAssemblyLaneSupport {
    param([object[]]$Slices, [double]$Min, [double]$Max, [double]$DeckZ)

    $end = $Min
    foreach ($slice in @($Slices | Where-Object { $_.deckZ -eq $DeckZ -and $_.max -gt $Min -and $_.min -lt $Max } | Sort-Object min,max)) {
        if ($slice.min -gt $end) { return $false }
        $end = [Math]::Max($end, $slice.max)
        if ($end -ge $Max) { return $true }
    }
    return $false
}

function Get-ZMComplexMotorwayGates {
    param([Parameter(Mandatory = $true)][object]$Contract, [Parameter(Mandatory = $true)][string]$TemplateDirectory)

    if ($Contract.schemaVersion -ne 2 -or $Contract.assemblies.Count -eq 0 -or $Contract.connections.Count -eq 0) { throw 'Complex measured gates require a complete assembly contract.' }
    Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1')
    Import-Module (Join-Path $PSScriptRoot 'transition_gates.psm1')
    foreach ($assembly in $Contract.assemblies) {
        $fingerprint = $Contract.sourceFingerprints.PSObject.Properties[$assembly.template]
        if ($null -eq $fingerprint -or $fingerprint.Value -cne (Get-FileHash -LiteralPath (Join-Path $TemplateDirectory $assembly.template)).Hash) {
            throw "Complex gate source fingerprint changed: $($assembly.template)"
        }
        Convert-ZMMotorwayPoint $assembly.origin 0 | Out-Null
    }
    $floors = @(Get-ZMAssemblyFlatFloors $Contract.assemblies $TemplateDirectory)
    $directions = @($Contract.connections | ForEach-Object { $_.ports[0].outward } | Sort-Object -Unique)
    $gates = @(foreach ($direction in $directions) {
        $connection = @($Contract.connections | Where-Object { $_.ports[0].outward -eq $direction })
        if ($connection.Count -ne 1) { throw "Complex gate direction is ambiguous: $direction" }
        $route = $connection[0].route
        $forward = @{ N = @(0, 1); E = @(1, 0); S = @(0, -1); W = @(-1, 0) }[$direction]
        if ($null -eq $forward) { throw 'Complex gate direction is not cardinal.' }
        $right = @($forward[1], -$forward[0])
        $centred = @($Contract.ordinaryRoadApproaches | Where-Object heading -eq $direction)
        $candidates = @($Contract.assemblies | Where-Object {
            $name = [IO.Path]::GetFileName($_.template)
            $parallel = ($_.yaw % 180) -eq $(if ($direction -in @('N', 'S')) { 0 } else { 90 })
            ($_.origin.x * $forward[0] + $_.origin.y * $forward[1]) -gt 0 -and
            $(if ($route -eq 'motorway') { $name -eq 'tile_motorway.vmf' -and $parallel } else {
                ($name -in @('tile_road.vmf', 'tile_road_bridge.vmf') -and $parallel) -or
                ($name -eq 'tile_road_corner.vmf' -and $centred.Count -eq 1)
            })
        } | Sort-Object { $_.origin.x * $forward[0] + $_.origin.y * $forward[1] } -Descending)
        if ($null -eq $Contract.PSObject.Properties['sourceFrameOrigin']) { throw 'Complex gate contract lacks its source coordinate frame.' }
        $outside = if ($candidates.Count -gt 0) { $candidates[0] } else { $null }
        if ($route -eq 'motorway') {
            if ($null -ne $outside) {
                $mouths = Get-ZMStraightMotorwayMouths (Join-Path $TemplateDirectory $outside.template)
                $ports = @($mouths.mouths.lanes | ForEach-Object { Convert-ZMMotorwayPort $_ $outside.yaw $outside.origin } |
                    Where-Object outward -eq $direction)
                $axis = $outside.origin.x * $right[0] + $outside.origin.y * $right[1]
            } else {
                $ports = @(foreach ($sourcePort in $connection[0].ports) { $sourcePort | ConvertTo-Json -Depth 12 | ConvertFrom-Json })
                foreach ($port in $ports) {
                    foreach ($coordinate in @('x', 'y', 'z')) { $port.position.$coordinate -= $Contract.sourceFrameOrigin.$coordinate }
                }
                $axis = ($ports | ForEach-Object { $_.position.x * $right[0] + $_.position.y * $right[1] } | Measure-Object -Average).Average
            }
        } elseif ($route -eq 'road') {
            if ($null -eq $outside) { throw "Complex road gate has no authored flat approach: $direction" }
            $axis = if ($centred.Count -eq 1) { 0 } else { $outside.origin.x * $right[0] + $outside.origin.y * $right[1] }
            $ports = @([pscustomobject]@{
                id = "$direction/road"; width = 256
                position = [pscustomobject]@{ x = $right[0] * $axis; y = $right[1] * $axis; z = $(if ([IO.Path]::GetFileName($outside.template) -eq 'tile_road_bridge.vmf') {
                    Get-ZMTransitionDeckHeight (Join-Path $TemplateDirectory $outside.template) 640
                } else { 36 }) }
            })
        } else { throw 'Unsupported complex gate route.' }
        if ($ports.Count -ne $(if ($route -eq 'motorway') { 2 } else { 1 })) { throw "Complex gate lane count differs: $direction" }
        if ($route -eq 'motorway' -and @($ports | Where-Object {
            $_.grade -ne 0 -or $_.width -le 0
        }).Count -gt 0) { throw "Complex gate requires measured flat cardinal motorway mouths: $direction" }
        $arrowInset = if ($route -eq 'motorway') { 256 } else { 96 }
        $arrivalInset = if ($route -eq 'motorway') { 384 } else { 128 }
        $minimumAlong = 2208
        if ($centred.Count -eq 1) {
            $entry = @($centred[0].instances | Where-Object owner -like '*/entry_corner')
            if ($entry.Count -ne 1) { throw "Centred road gate lacks its unique entry corner: $direction" }
            $minimumAlong = [Math]::Max($minimumAlong, ($entry[0].origin.x * $forward[0] + $entry[0].origin.y * $forward[1]) + $arrivalInset + 32)
        }
        $selected = $null
        foreach ($along in @(2208, 2240, 2272, 2304, 2336, 2368, 2400, 2432, 2464, 2496, 2528, 2560, 2592, 2624, 2656, 2688, 2720, 2752, 2784, 2816)) {
            if ($along -lt $minimumAlong) { continue }
            $supported = $true
            foreach ($sample in @(($along - 32), ($along + 32), ($along - $arrowInset), ($along - $arrivalInset))) {
                $slices = @(Get-ZMAssemblyFloorSlices $floors $direction $sample)
                foreach ($port in $ports) {
                    $lateral = $port.position.x * $right[0] + $port.position.y * $right[1]
                    if (-not (Test-ZMAssemblyLaneSupport $slices ($lateral - $port.width / 2) ($lateral + $port.width / 2) $port.position.z)) {
                        $supported = $false; break
                    }
                }
                if (-not $supported) { break }
            }
            if ($supported) { $selected = $along; break }
        }
        if ($null -eq $selected) { throw "Complex gate/arrow/arrival lacks measured floor support: $direction" }
        $lanes = @($ports | ForEach-Object {
            $lateral = $_.position.x * $right[0] + $_.position.y * $right[1] - $axis
            [pscustomobject]@{
                lateral = $lateral; width = $_.width; deckZ = $_.position.z; sourcePort = $_.id
                arrowX = $forward[0] * ($selected - $arrowInset) + $right[0] * ($axis + $lateral)
                arrowY = $forward[1] * ($selected - $arrowInset) + $right[1] * ($axis + $lateral)
                arrivalX = $forward[0] * ($selected - $arrivalInset) + $right[0] * ($axis + $lateral)
                arrivalY = $forward[1] * ($selected - $arrivalInset) + $right[1] * ($axis + $lateral)
            }
        } | Sort-Object lateral)
        [pscustomobject]@{
            direction = $direction; route = $route
            x = $forward[0] * $selected + $right[0] * $axis; y = $forward[1] * $selected + $right[1] * $axis
            lateralMin = $lanes[0].lateral - $lanes[0].width / 2
            lateralMax = $lanes[-1].lateral + $lanes[-1].width / 2
            deckZ = $lanes[0].deckZ; lanes = $lanes; arrivalLane = 1
            status = 'measured_source_gate_not_compiled_or_live'
        }
    })
    foreach ($assembly in $Contract.assemblies) {
        if ($Contract.sourceFingerprints.PSObject.Properties[$assembly.template].Value -cne
            (Get-FileHash -LiteralPath (Join-Path $TemplateDirectory $assembly.template)).Hash) {
            throw "Complex gate source changed during measurement: $($assembly.template)"
        }
    }
    return $gates
}

function Get-ZMComplexMotorwayContract {
    param([Parameter(Mandatory = $true)][object]$Recipe)

    foreach ($name in @('motorwayCellInspection', 'motorwayAssembly')) {
        $property = $Recipe.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and $null -ne $property.Value.PSObject.Properties['schemaVersion'] -and
            $property.Value.schemaVersion -eq 2) { return $property.Value }
    }
    return $null
}

function Resolve-ZMCentredRoadBorderPlacements {
    param([Parameter(Mandatory = $true)][object]$Recipe, [object[]]$BorderPlacements)

    $contract = Get-ZMComplexMotorwayContract $Recipe
    $approaches = if ($null -ne $contract -and $null -ne $contract.PSObject.Properties['ordinaryRoadApproaches']) {
        @($contract.ordinaryRoadApproaches)
    } else { @() }
    $obsolete = @{}
    foreach ($approach in $approaches) { $obsolete["zm_transition_road_$($approach.heading)"] = $true }
    foreach ($placement in $BorderPlacements) {
        if (-not $obsolete.ContainsKey([string]$placement.targetname)) { $placement; continue }
        if ([IO.Path]::GetFileName($placement.template.Replace('/', '\')) -ne 'tile_road.vmf') {
            throw 'Centred-road cleanup cannot replace a nonstandard border road.'
        }
        $terrain = @($Recipe.tilePlacements | Where-Object { $_.role -in @('terrain', 'motorway_external_occupied') } | Select-Object -First 1)
        if ($terrain.Count -ne 1) { throw 'Centred-road cleanup requires the existing planned terrain source.' }
        [pscustomobject]@{
            tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template
            rotationYaw = 0; targetname = $placement.targetname.Replace('zm_transition_road_', 'zm_border_road_terrain_')
        }
    }
}

function Set-ZMComplexMotorwayCellInspection {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][object]$AssemblyCase,
        [Parameter(Mandatory = $true)][string]$TemplateDirectory,
        [Parameter(Mandatory = $true)][object]$Registry,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$TransportRotations,
        [switch]$Normal
    )

    $oceanSides = @($Recipe.skyboxOceanSides | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $connectionHeadings = @($AssemblyCase.connections | ForEach-Object { $_.ports[0].outward })
    if ($Recipe.tileGridSize -ne 5 -or $null -ne $Recipe.safeZoneEntrance -or @($Recipe.waterBorderSides).Count -gt 0 -or
        (-not $Normal -and $oceanSides.Count -gt 0) -or @($oceanSides | Where-Object { $_ -in $connectionHeadings }).Count -gt 0 -or
        @($Recipe.landmarks | Where-Object { $_ -ne 'none' }).Count -gt 0) {
        throw 'Complex motorway cells require a landmark-free 5x5 cell with no route toward water.'
    }
    if ($null -ne $AssemblyCase.PSObject.Properties['insertionSeam']) {
        Assert-ZMMotorwaySpawnFloor $AssemblyCase.instances[0] $AssemblyCase.insertionSeam.playerStartCandidate
    }
    $instances = [System.Collections.Generic.List[object]]::new()
    $gaps = [System.Collections.Generic.List[object]]::new()
    $roadApproaches = [System.Collections.Generic.List[object]]::new()
    foreach ($instance in $AssemblyCase.instances) {
        $relative = [Uri]::UnescapeDataString(([Uri]($TemplateDirectory.TrimEnd('\') + '\')).MakeRelativeUri([Uri]$instance.template).ToString()).Replace('/', '\')
        if ($null -ne $AssemblyCase.PSObject.Properties['insertionSeam'] -and $instance.owner -like '*/continuation') {
            $halfX = if ($instance.yaw -in @(0, 180)) { 960 } else { 320 }
            $halfY = if ($instance.yaw -in @(0, 180)) { 320 } else { 960 }
            if ([Math]::Abs($instance.origin.x - $AssemblyCase.origin.x) + $halfX -gt 2880 -or
                [Math]::Abs($instance.origin.y - $AssemblyCase.origin.y) + $halfY -gt 2880) { continue }
        }
        $disposition = if ($instance.status -eq 'exact_floor_seam') { 'exact_surface_candidate_clearance_pending' } elseif ($instance.status -eq 'authored_piece') { 'authored_source' } else { 'unsupported_connector_deferred' }
        $instances.Add([pscustomobject]@{
            template = $relative; yaw = $instance.yaw; owner = $instance.owner
            origin = [pscustomobject]@{ x = $instance.origin.x - $AssemblyCase.origin.x; y = $instance.origin.y - $AssemblyCase.origin.y; z = $instance.origin.z }
            status = $instance.status; disposition = $disposition; placementEligibility = 'inspection_only'
        })
    }
    foreach ($connection in $AssemblyCase.connections) {
        $port = $connection.ports[0]
        $heading = $port.outward
        $step = @{ N = @(0, 640); E = @(640, 0); S = @(0, -640); W = @(-640, 0) }[$heading]
        if ($connection.route -eq 'motorway') {
            $axis = if ($heading -in @('N', 'S')) { 'y' } else { 'x' }
            if ($null -ne $AssemblyCase.PSObject.Properties['insertionSeam'] -and
                [Math]::Abs($port.position.$axis - $AssemblyCase.origin.$axis) -eq 2880) {
                $gaps.Add([pscustomobject]@{ heading = $heading; gapToVisualBoundary = 0; status = 'reaches_boundary' })
                continue
            }
            $last = @($instances | Where-Object owner -eq "$($AssemblyCase.id)/$heading/continuation")[0]
            for ($index = 1; $index -le 8; $index++) {
                $next = [pscustomobject]@{ x = $last.origin.x + $step[0]; y = $last.origin.y + $step[1]; z = 0 }
                $halfX = if ($last.yaw -in @(0, 180)) { 960 } else { 320 }
                $halfY = if ($last.yaw -in @(0, 180)) { 320 } else { 960 }
                if ([Math]::Abs($next.x) + $halfX -gt 2880 -or [Math]::Abs($next.y) + $halfY -gt 2880) { break }
                $last = [pscustomobject]@{
                    template = $last.template; yaw = $last.yaw; owner = "$($AssemblyCase.id)/$heading/stripe$index"
                    origin = $next; status = 'continuation_floor_seam'
                    disposition = $connection.disposition; placementEligibility = 'inspection_only'
                }
                $instances.Add($last)
            }
            $end = if ($heading -in @('N', 'S')) { [Math]::Abs($last.origin.y) + 320 } else { [Math]::Abs($last.origin.x) + 320 }
            $gaps.Add([pscustomobject]@{ heading = $heading; gapToVisualBoundary = 2880 - $end; status = $(if ($end -eq 2880) { 'reaches_boundary' } else { 'unfilled_partial_tile_boundary_no_scaling' }) })
        } else {
            # Existing approaches are shown at authored Z; the unmatched grade/deck remains an explicit diagnostic.
            $ramp = if ($null -ne $connection.PSObject.Properties['approachKind']) {
                $connection.approachKind -eq 'onramp'
            } else { [IO.Path]::GetFileName($instances[0].template) -like '*onramp*' }
            $template = if ($ramp) { 'roads\tile_road_onramp.vmf' } else { 'roads\tile_road_bridge.vmf' }
            $yaw = if ($ramp) { [int]$TransportRotations.onrampRoadByDirection[$heading] } elseif ($heading -in @('N', 'S')) { 0 } else { 90 }
            $mouth = if ($ramp) {
                Convert-ZMMotorwayPoint ([pscustomobject]@{ x = 128; y = 320; z = 0 }) $yaw
            } else {
                [pscustomobject]@{ x = -$step[0] / 2; y = -$step[1] / 2; z = 0 }
            }
            $origin = [pscustomobject]@{ x = $port.position.x - $AssemblyCase.origin.x - $mouth.x; y = $port.position.y - $AssemblyCase.origin.y - $mouth.y; z = 0 }
            $instances.Add([pscustomobject]@{
                template = $template; yaw = $yaw; origin = $origin
                owner = "$($AssemblyCase.id)/$heading/road_approach"
                status = 'unapproved_road_deck_grade_diagnostic'
                disposition = $connection.disposition; placementEligibility = 'inspection_only'
            })
            if ($ramp -and $null -ne $AssemblyCase.PSObject.Properties['insertionSeam']) {
                $centred = New-ZMCentredRoadApproach $origin $heading "$($AssemblyCase.id)/$heading" $TemplateDirectory
                foreach ($piece in $centred.instances) { $instances.Add($piece) }
                $roadApproaches.Add($centred)
                $gaps.Add([pscustomobject]@{ heading = $heading; gapToVisualBoundary = 0; status = 'centred_road_gate_integration_pending' })
                continue
            }
            $end = 0
            for ($index = 1; $index -le 8; $index++) {
                $origin = [pscustomobject]@{ x = $origin.x + $step[0]; y = $origin.y + $step[1]; z = 0 }
                if ([Math]::Abs($origin.x) + 320 -gt 2880 -or [Math]::Abs($origin.y) + 320 -gt 2880) { break }
                $instances.Add([pscustomobject]@{
                    template = $(if ($ramp) { 'roads\tile_road.vmf' } else { $template })
                    yaw = $(if ($heading -in @('N', 'S')) { 0 } else { 90 })
                    origin = $origin; owner = "$($AssemblyCase.id)/$heading/road$index"
                    status = 'unapproved_road_approach_continuation'
                    disposition = $connection.disposition; placementEligibility = 'inspection_only'
                })
                $end = if ($heading -in @('N', 'S')) { [Math]::Abs($origin.y) + 320 } else { [Math]::Abs($origin.x) + 320 }
            }
            $gaps.Add([pscustomobject]@{ heading = $heading; gapToVisualBoundary = $(if ($end -gt 0) { 2880 - $end } else { $null }); status = 'road_approach_and_boundary_pending' })
        }
    }
    $leases = [System.Collections.Generic.List[object]]::new()
    $coverage = @{}
    $fingerprints = @{}
    $approachBounds = @{}
    foreach ($instance in $instances) {
        $path = Join-Path $TemplateDirectory $instance.template
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Inspection approach source missing: $path" }
        $fingerprints[$instance.template] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $source = @($Registry | Where-Object template -eq $path)
        if ($source.Count -eq 1) {
            if ($source[0].sha256 -cne $fingerprints[$instance.template]) { throw "Measured assembly registry is stale for $path; regenerate its source report." }
            $bounds = Convert-ZMMotorwayEnvelope $source[0].envelope $instance.yaw
        } else {
            if ($source.Count -gt 1) { throw "Duplicate measured motorway source: $path" }
            if (-not $approachBounds.ContainsKey($path)) { $approachBounds[$path] = Get-ZMInspectionWindingBounds $path }
            $bounds = Convert-ZMMotorwayEnvelope $approachBounds[$path] $instance.yaw
        }
        foreach ($axis in @('x', 'y', 'z')) { $bounds.$axis.min += $instance.origin.$axis; $bounds.$axis.max += $instance.origin.$axis }
        $instance | Add-Member -NotePropertyName windingBounds -NotePropertyValue $bounds
        $instance | Add-Member -NotePropertyName windingWithinCellFrame -NotePropertyValue ($bounds.x.min -ge -2880 -and $bounds.x.max -le 2880 -and $bounds.y.min -ge -2880 -and $bounds.y.max -le 2880)
        $instance | Add-Member -NotePropertyName extendsBelowTerrain -NotePropertyValue ($bounds.z.min -lt 0)
        foreach ($tileY in -2..6) {
            foreach ($tileX in -2..6) {
                if ($bounds.x.min -lt ($tileX - 2) * 640 + 320 -and $bounds.x.max -gt ($tileX - 2) * 640 - 320 -and
                    $bounds.y.min -lt (2 - $tileY) * 640 + 320 -and $bounds.y.max -gt (2 - $tileY) * 640 - 320) {
                    $ringIndex = [Math]::Max([Math]::Abs($tileX - 2), [Math]::Abs($tileY - 2))
                    $leases.Add([pscustomobject]@{ tileX = $tileX; tileY = $tileY; ring = $(if ($ringIndex -le 2) { 'core' } elseif ($ringIndex -eq 3) { 'border' } else { 'outer' }); owner = $instance.owner; emitsInstance = $false })
                    if (-not $coverage.ContainsKey("$tileX,$tileY")) { $coverage["$tileX,$tileY"] = $instance.owner }
                }
            }
        }
    }
    $terrain = @($Recipe.tilePlacements | Where-Object role -eq terrain | Select-Object -First 1)
    if ($terrain.Count -ne 1) { throw 'Complex inspection requires a planned terrain spawn template.' }
    $Recipe.tilePlacements = @(foreach ($placement in $Recipe.tilePlacements) {
        $key = "$($placement.tileX),$($placement.tileY)"
        if ($coverage.ContainsKey($key)) {
            [pscustomobject]@{ tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template; rotationYaw = 0; role = 'motorway_external_occupied'; placementId = $coverage[$key]; emitsInstance = $false }
        } elseif ($placement.role -in @('terrain', 'decoration') -and ($null -eq $placement.PSObject.Properties['footprintWidth'] -or $placement.footprintWidth -eq 1)) {
            $placement
        } else {
            [pscustomobject]@{ tileX = $placement.tileX; tileY = $placement.tileY; template = $terrain[0].template; rotationYaw = 0; role = 'terrain' }
        }
    })
    $overlaps = @(for ($a = 0; $a -lt $instances.Count; $a++) {
        for ($b = $a + 1; $b -lt $instances.Count; $b++) {
            $first = $instances[$a].windingBounds
            $second = $instances[$b].windingBounds
            if ($first.x.min -lt $second.x.max -and $first.x.max -gt $second.x.min -and
                $first.y.min -lt $second.y.max -and $first.y.max -gt $second.y.min -and
                $first.z.min -lt $second.z.max -and $first.z.max -gt $second.z.min) {
                [pscustomobject]@{ first = $instances[$a].owner; second = $instances[$b].owner; status = 'conservative_envelope_overlap_requires_solid_clearance_review' }
            }
        }
    })
    foreach ($template in $fingerprints.Keys) {
        if ($fingerprints[$template] -cne (Get-FileHash -LiteralPath (Join-Path $TemplateDirectory $template) -Algorithm SHA256).Hash) { throw "Inspection source changed during generation: $template" }
    }
    if (@($Recipe.tilePlacements | Where-Object role -eq terrain).Count -eq 0) {
        $free = @($Recipe.tilePlacements | Where-Object role -eq decoration | Select-Object -First 1)
        if ($free.Count -eq 1) {
            $free[0].role = 'terrain'; $free[0].template = $terrain[0].template; $free[0].rotationYaw = 0
        } elseif ($null -eq $AssemblyCase.PSObject.Properties['insertionSeam']) {
            throw 'Complex inspection leaves no free terrain spawn; assembly must be redesigned, not hidden.'
        }
    }
    foreach ($side in $oceanSides) {
        $outward = @{ N = { param($l) $l.tileY -lt 0 }; S = { param($l) $l.tileY -gt 4 }; E = { param($l) $l.tileX -gt 4 }; W = { param($l) $l.tileX -lt 0 } }[[string]$side]
        if ($null -ne $outward -and @($leases | Where-Object { & $outward $_ }).Count -gt 0) {
            throw "Complex motorway assembly reaches the omitted $side ocean ring."
        }
    }
    if ($Normal) {
        foreach ($instance in $instances) { $instance.placementEligibility = 'normal_travel_pending' }
    }
    $contractProperty = if ($Normal) { 'motorwayAssembly' } else { 'motorwayCellInspection' }
    if ($Normal -and $null -ne $Recipe.PSObject.Properties['motorwayAssembly']) { $Recipe.PSObject.Properties.Remove('motorwayAssembly') }
    $Recipe.forceCarpark = $false
    $Recipe.buildingTemplates = @()
    $Recipe | Add-Member -NotePropertyName $contractProperty -NotePropertyValue ([pscustomobject]@{
        schemaVersion = 2; status = $(if ($Normal) { 'normal_complex_travel_pending' } else { 'complex_cell_diagnostic_not_live_travel' }); template = $instances[0].template
        sourceSha256 = $fingerprints[$instances[0].template]; sourceFingerprints = $fingerprints; yaw = $instances[0].yaw
        assemblies = @($instances); leases = @($leases); connections = $AssemblyCase.connections; boundaryGaps = @($gaps)
        sourceFrameOrigin = [pscustomobject]@{ x = $AssemblyCase.origin.x; y = $AssemblyCase.origin.y; z = $AssemblyCase.origin.z }
        declaredMotorwayDirections = @($Recipe.activeEntrances | Where-Object { $_ -notin $Recipe.rampExits })
        measuredMotorwayDirections = @($AssemblyCase.connections | Where-Object route -eq motorway | ForEach-Object { $_.ports[0].outward } | Sort-Object)
        mappedYawStatus = 'existing_topology_yaw_preserved_compare_measured_route_directions_before_acceptance'
        envelopeOverlaps = $overlaps
        ordinaryRoadApproaches = @($roadApproaches)
        limits = @('Explicit diagnostic cell: unresolved seams/approach grades and partial boundary tiles are not approved connections.', 'Incompatible motorway mouths and road approaches remain unsupported until separately authorized connector assets are validated.', 'Exact floor seams are candidates only; conservative winding coverage suppresses scenery but does not establish full-solid collision clearance.', 'Conservative winding coverage suppresses scenery; shared leases do not authorize solid overlap.', 'No legacy transition triggers, geometry scaling, source modification or Z correction.')
    })
    if ($null -ne $AssemblyCase.PSObject.Properties['insertionSeam']) {
        $Recipe.$contractProperty | Add-Member -NotePropertyName insertionSeam -NotePropertyValue $AssemblyCase.insertionSeam
    }
}

Export-ModuleMember -Function Get-ZMComplexMotorwayContract, Get-ZMMotorwayFootprint, Convert-ZMMotorwayPoint, Get-ZMMotorwayReservation, Convert-ZMMotorwayEnvelope, Get-ZMMotorwaySurfacePorts, Convert-ZMMotorwayPort, Resolve-ZMMotorwayPortTranslation, Get-ZMMotorwayMouthRegistry, New-ZMStraightMotorwayStripe, Get-ZMStraightMotorwayMouths, Get-ZMNormalStraightMotorwayGates, New-ZMNormalStraightMotorwayContract, Resolve-ZMNormalStraightMotorwayRings, Set-ZMStraightMotorwayCellInspection, Assert-ZMStraightMotorwayCellContract, Join-ZMMotorwayAssemblyCases, Get-ZMOrdinaryRoadMouths, New-ZMCentredRoadApproach, Get-ZMComplexMotorwayGates, Resolve-ZMCentredRoadBorderPlacements, Set-ZMComplexMotorwayCellInspection
