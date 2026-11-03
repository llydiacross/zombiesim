Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ZMTemplateDensityTag {
    param([Parameter(Mandatory = $true)][string]$Template)

    if ([System.IO.Path]::GetExtension($Template) -ine '.vmf') {
        throw "Scenery density requires a VMF template: '$Template'."
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Template.Replace('/', '\'))
    if ($name -match '_\d+x(?:\d+)?$') {
        $name = $name.Substring(0, $name.LastIndexOf('_'))
    }
    # Terrain brush variants use s/t shape suffixes (tile_brush_1s), not density letters.
    if ($name -match '_\d+[st]$') { return 0 }
    if ($name -match '_\d+([a-z]+)$') {
        $length = $Matches[1].Length
        if ($length -gt 3) { throw "Unsupported scenery density tag in '$Template': '$($Matches[1])'." }
        return $length
    }
    if ($name -match '_\d+[^_]+$') {
        throw "Malformed scenery density tag in '$Template'."
    }
    return 0
}

function Get-ZMSceneryDensityZone {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$InlandDistance,
        [Parameter(Mandatory = $true)][string]$Profile
    )

    if ($InlandDistance -lt 3) {
        return [pscustomobject]@{ tier = 1; source = 'protected_coast'; inlandDistance = $InlandDistance }
    }
    $baseline = if ($InlandDistance -lt 8) { 2 } else { 3 }
    $districtTier = switch ($Profile.ToLowerInvariant()) {
        'commercial' { 3 }
        'financial' { 3 }
        'settlement' { 2 }
        default { 0 }
    }
    return [pscustomobject]@{
        tier = [Math]::Max($baseline, $districtTier)
        source = if ($districtTier -gt $baseline) { "district:$($Profile.ToLowerInvariant())" } else { 'inland_band' }
        inlandDistance = $InlandDistance
    }
}

function Get-ZMSceneryRadialDistance {
    param(
        [Parameter(Mandatory = $true)][int]$CellX,
        [Parameter(Mandatory = $true)][int]$CellY,
        [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$GridCells
    )

    if ($CellX -lt 0 -or $CellX -ge $GridCells -or $CellY -lt 0 -or $CellY -ge $GridCells) {
        throw "Scenery-density cell $CellX,$CellY is outside the $GridCells-cell grid."
    }
    $center = ($GridCells - 1) / 2.0
    $dx = $CellX - $center
    $dy = $CellY - $center
    return [Math]::Round([Math]::Sqrt($dx * $dx + $dy * $dy), 3)
}

function Get-ZMSceneryRadialDensityZone {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][double]$RadialDistance,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$InlandDistance,
        [Parameter(Mandatory = $true)][string]$Profile
    )

    if ([double]::IsNaN($RadialDistance) -or [double]::IsInfinity($RadialDistance)) {
        throw 'Scenery radial distance must be finite.'
    }
    if ($InlandDistance -lt 3) {
        return [pscustomobject]@{
            tier = 1
            source = 'protected_coast'
            inlandDistance = $InlandDistance
            radialDistance = $RadialDistance
        }
    }
    $baseline = if ($RadialDistance -lt 3) { 1 } elseif ($RadialDistance -lt 8) { 2 } else { 3 }
    $districtTier = switch ($Profile.ToLowerInvariant()) {
        'commercial' { 3 }
        'financial' { 3 }
        'settlement' { 2 }
        default { 0 }
    }
    return [pscustomobject]@{
        tier = [Math]::Max($baseline, $districtTier)
        source = if ($districtTier -gt $baseline) { "district:$($Profile.ToLowerInvariant())" } else { 'radial_band' }
        inlandDistance = $InlandDistance
        radialDistance = $RadialDistance
    }
}

function Get-ZMSceneryInlandDistances {
    param(
        [Parameter(Mandatory = $true)][object[]]$LandCells,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$OceanBoundaryCells
    )

    $land = @{}
    foreach ($cell in $LandCells) {
        $key = "$([int]$cell.x),$([int]$cell.y)"
        if ($land.ContainsKey($key)) { throw "Duplicate scenery land cell $key." }
        $land[$key] = $cell
    }
    $distances = @{}
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($cell in $OceanBoundaryCells) {
        $key = "$([int]$cell.x),$([int]$cell.y)"
        if (-not $land.ContainsKey($key)) { throw "Ocean boundary cell $key is not a land cell." }
        if (-not $distances.ContainsKey($key)) {
            $distances[$key] = 0
            $queue.Enqueue($key)
        }
    }
    if ($queue.Count -eq 0) { throw 'Scenery zoning requires an explicit actual-ocean boundary.' }
    while ($queue.Count -gt 0) {
        $key = $queue.Dequeue()
        $cell = $land[$key]
        foreach ($offset in @(@(0, -1), @(1, 0), @(0, 1), @(-1, 0))) {
            $neighbor = "$([int]$cell.x + $offset[0]),$([int]$cell.y + $offset[1])"
            if ($land.ContainsKey($neighbor) -and -not $distances.ContainsKey($neighbor)) {
                $distances[$neighbor] = $distances[$key] + 1
                $queue.Enqueue($neighbor)
            }
        }
    }
    foreach ($key in $land.Keys) {
        if (-not $distances.ContainsKey($key)) { throw "Scenery land cell $key cannot reach the actual ocean through cardinal land cells." }
    }
    return $distances
}

function Get-ZMSceneryTargetTier {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(1, 3)][int]$ZoneTier,
        [Parameter(Mandatory = $true)][ValidateRange(0, 99)][int]$Roll,
        [switch]$RouteAdjacentWall
    )

    if ($ZoneTier -eq 1) { return 1 }
    if ($RouteAdjacentWall) { return 2 }
    if ($Roll -lt 95) { return $ZoneTier }
    return (5 - $ZoneTier)
}

function Get-ZMSceneryPossibleTargetTiers {
    param([Parameter(Mandatory = $true)][ValidateRange(1, 3)][int]$ZoneTier)

    return @(@(0, 95) | ForEach-Object { Get-ZMSceneryTargetTier $ZoneTier $_ } | Sort-Object -Unique)
}

function Get-ZMTemplateFootprint {
    param([Parameter(Mandatory = $true)][string]$Template)

    $templateName = [System.IO.Path]::GetFileNameWithoutExtension($Template.Replace('\', '/'))
    if ($templateName -match '(?i)_(\d+)x(\d*)$') {
        $width = [int]$Matches[1]
        $height = if ([string]::IsNullOrEmpty($Matches[2])) { $width } else { [int]$Matches[2] }
        if ($width -lt 1 -or $height -lt 1) { throw "Template '$Template' must define positive footprint dimensions." }
        return [pscustomobject]@{ width = $width; height = $height }
    }
    return [pscustomobject]@{ width = 1; height = 1 }
}

function Get-ZMLandmarkTemplatePool {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Landmarks,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Patterns,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$AvailableTemplates
    )

    foreach ($landmark in $Landmarks) {
        if (-not $Patterns.Contains($landmark)) { continue }
        $pattern = [string]$Patterns[$landmark]
        $matches = @($AvailableTemplates | Where-Object { $_ -like $pattern -or $_ -like $pattern.TrimStart('*/') } | Sort-Object)
        if ($matches.Count -eq 0) { continue }

        $footprints = @{}
        foreach ($match in $matches) { $footprints[$match] = Get-ZMTemplateFootprint $match }
        # Prefer the largest authored footprint; equal areas keep the first-sorted shape.
        $primary = [string]$matches[0]
        foreach ($match in $matches) {
            if (($footprints[$match].width * $footprints[$match].height) -gt ($footprints[$primary].width * $footprints[$primary].height)) { $primary = [string]$match }
        }
        $footprint = $footprints[$primary]
        $compatible = @($matches | Where-Object {
            $footprints[$_].width -eq $footprint.width -and $footprints[$_].height -eq $footprint.height
        })
        # Single-tile variants of a multi-tile landmark remain usable when its footprint cannot be placed.
        $singleTileFallbacks = if ($footprint.width -gt 1 -or $footprint.height -gt 1) {
            @($matches | Where-Object { $footprints[$_].width -eq 1 -and $footprints[$_].height -eq 1 })
        } else { @() }
        $alternateFootprintPools = [System.Collections.Generic.List[object]]::new()
        $seenFootprints = @{}
        foreach ($match in $matches) {
            $candidateFootprint = $footprints[$match]
            if (($candidateFootprint.width -eq $footprint.width -and $candidateFootprint.height -eq $footprint.height) -or
                ($candidateFootprint.width -eq 1 -and $candidateFootprint.height -eq 1)) { continue }
            $shapeKey = '{0}x{1}' -f $candidateFootprint.width, $candidateFootprint.height
            if ($seenFootprints.ContainsKey($shapeKey)) { continue }
            $seenFootprints[$shapeKey] = $true
            $alternateFootprintPools.Add([pscustomobject]@{
                footprint = $candidateFootprint
                templates = @($matches | Where-Object {
                    $footprints[$_].width -eq $candidateFootprint.width -and $footprints[$_].height -eq $candidateFootprint.height
                })
            })
        }
        $alternateFootprintPools = @($alternateFootprintPools | Sort-Object `
            @{ Expression = { -($_.footprint.width * $_.footprint.height) } },
            @{ Expression = { $_.footprint.width } },
            @{ Expression = { $_.footprint.height } })
        return [pscustomobject]@{
            landmark = [string]$landmark
            template = [string]$compatible[0]
            footprint = $footprint
            templates = @($compatible)
            singleTileFallbackTemplates = @($singleTileFallbacks)
            alternateFootprintTemplates = @($alternateFootprintPools)
        }
    }
    return $null
}

function Get-ZMSceneryLandmarkTags {
    param([Parameter(Mandatory = $true)][object[]]$Landmarks)

    $tags = [System.Collections.Generic.List[string]]::new()
    foreach ($landmark in $Landmarks) {
        switch ([string]$landmark.Label) {
            'LAB' { $tags.AddRange([string[]]@('laboratory', 'radioactive', 'industrial')) }
            'EPI' { $tags.AddRange([string[]]@('epicenter', 'radioactive', 'destroyed')) }
            'AIR' { $tags.AddRange([string[]]@('airport', 'transport')) }
            'A' { $tags.Add('military') }
            'B' { $tags.AddRange([string[]]@('fortified', 'military')) }
            'P' { $tags.AddRange([string[]]@('civic', 'security')) }
            'H' { $tags.AddRange([string[]]@('civic', 'medical')) }
            'F' { $tags.AddRange([string[]]@('civic', 'emergency_services')) }
            'C' { $tags.AddRange([string[]]@('civic', 'religious')) }
            'G' { $tags.AddRange([string[]]@('commercial', 'service_station')) }
            '$' { $tags.AddRange([string[]]@('commercial', 'financial')) }
            'L' { $tags.Add('recreation') }
            'K' { $tags.Add('parkland') }
        }
    }
    return @($tags | Sort-Object -Unique)
}

function Get-ZMSceneryLandmarkZoneType {
    param([AllowEmptyCollection()][object[]]$Landmarks)

    $armyBase = $false
    foreach ($landmark in $Landmarks) {
        $label = ''
        $name = ''
        if ($landmark -is [string]) {
            $name = $landmark
        } elseif ($landmark -is [System.Collections.IDictionary]) {
            if ($landmark.Contains('label')) { $label = [string]$landmark['label'] }
            if ($landmark.Contains('name')) { $name = [string]$landmark['name'] }
        } elseif ($null -ne $landmark) {
            if ($null -ne $landmark.PSObject.Properties['label']) { $label = [string]$landmark.label }
            if ($null -ne $landmark.PSObject.Properties['name']) { $name = [string]$landmark.name }
        }
        if ($label -eq 'B' -or $name -eq 'Bunker') { return 'fortified' }
        if ($label -eq 'A' -or $name -eq 'Army Base') { $armyBase = $true }
    }
    if ($armyBase) { return 'military' }
    return ''
}

function Test-ZMSceneryRadioactiveTheme {
    param(
        [Parameter(Mandatory = $true)][object]$Cell,
        [string[]]$RadioactiveTags = @('radioactive')
    )

    $environment = $Cell.environment
    $hasTheme = if ($environment -is [System.Collections.IDictionary]) {
        $environment.Contains('sceneryRadioactive')
    } else {
        $null -ne $environment.PSObject.Properties['sceneryRadioactive']
    }
    if ($hasTheme) {
        if ($environment.sceneryRadioactive -isnot [bool]) {
            throw "Invalid radioactive scenery flag at $($Cell.x),$($Cell.y)."
        }
        return [bool]$environment.sceneryRadioactive
    }
    return @(@($environment.tags) | Where-Object { $_ -in $RadioactiveTags }).Count -gt 0
}

function Get-ZMSceneryEnvironmentProfile {
    param(
        [Parameter(Mandatory = $true)][object]$Cell,
        [Parameter(Mandatory = $true)][string[]]$ProfilePriority,
        [switch]$CurrentPolicy
    )

    $version = $Cell.PSObject.Properties['sceneryDensityPolicyVersion']
    $useCurrentPolicy = $CurrentPolicy -or ($null -ne $version -and $version.Value -eq 2)
    if ($useCurrentPolicy) {
        $landmarks = $Cell.PSObject.Properties['landmarks']
        if ($null -ne $landmarks) {
            $landmarkZone = Get-ZMSceneryLandmarkZoneType @($landmarks.Value)
            if (-not [string]::IsNullOrWhiteSpace($landmarkZone)) { return $landmarkZone }
        }
        if (@($Cell.environment.tags) -contains 'safe_zone') { return 'safe_zone' }
    }
    foreach ($tag in $ProfilePriority) {
        if ($useCurrentPolicy -and $tag -eq 'radioactive' -and -not (Test-ZMSceneryRadioactiveTheme $Cell)) { continue }
        if (@($Cell.environment.tags) -contains $tag) { return $tag }
    }
    if ($Cell.building.present) { return 'settlement' }
    return [string]$Cell.environment.terrain
}

function Get-ZMNearestSceneryZone {
    param(
        [Parameter(Mandatory = $true)][int]$CellX,
        [Parameter(Mandatory = $true)][int]$CellY,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Origins,
        [Parameter(Mandatory = $true)][double]$Radius
    )

    if ([double]::IsNaN($Radius) -or [double]::IsInfinity($Radius) -or $Radius -le 0) {
        throw 'Scenery zone radius must be finite and positive.'
    }
    $nearest = $null
    $nearestSquared = [double]::PositiveInfinity
    foreach ($origin in $Origins) {
        $dx = [double]$CellX - [double]$origin.x
        $dy = [double]$CellY - [double]$origin.y
        $distanceSquared = $dx * $dx + $dy * $dy
        if ($distanceSquared -gt $Radius * $Radius) { continue }
        $kind = if ($origin -is [System.Collections.IDictionary]) {
            if ($origin.Contains('kind')) { [string]$origin['kind'] } else { '' }
        } elseif ($null -ne $origin.PSObject.Properties['kind']) { [string]$origin.kind } else { '' }
        $preferTie = $null -ne $nearest -and $distanceSquared -eq $nearestSquared -and (
            ($kind -eq 'fortified' -and $nearest.kind -ne 'fortified') -or
            ($kind -eq $nearest.kind -and ([int]$origin.y -lt $nearest.originY -or
                ([int]$origin.y -eq $nearest.originY -and [int]$origin.x -lt $nearest.originX))))
        if ($null -eq $nearest -or $distanceSquared -lt $nearestSquared -or $preferTie) {
            $nearestSquared = $distanceSquared
            $nearest = [pscustomobject]@{
                kind = $kind
                originX = [int]$origin.x
                originY = [int]$origin.y
                distance = [Math]::Round([Math]::Sqrt($distanceSquared), 3)
                radius = $Radius
            }
        }
    }
    return $nearest
}

function Get-ZMDestroyedZoneTier {
    param(
        [Parameter(Mandatory = $true)][double]$Distance,
        [Parameter(Mandatory = $true)][double]$Radius
    )

    if ([double]::IsNaN($Distance) -or [double]::IsInfinity($Distance) -or $Distance -lt 0 -or
        [double]::IsNaN($Radius) -or [double]::IsInfinity($Radius) -or $Radius -le 0 -or $Distance -gt $Radius) {
        throw 'Destroyed zone distance and radius must be finite, with 0 <= distance <= radius.'
    }
    return [int][Math]::Min(3, 1 + [Math]::Floor(3.0 * $Distance / $Radius))
}

function Get-ZMIndustrialZoneTierCap {
    # Low density at a zone origin, rising to the surrounding density at its edge.
    param(
        [Parameter(Mandatory = $true)][double]$Distance,
        [Parameter(Mandatory = $true)][double]$Radius
    )

    if ([double]::IsNaN($Distance) -or [double]::IsInfinity($Distance) -or $Distance -lt 0 -or
        [double]::IsNaN($Radius) -or [double]::IsInfinity($Radius) -or $Radius -le 0 -or $Distance -gt $Radius) {
        throw 'Zone distance and radius must be finite, with 0 <= distance <= radius.'
    }
    return [int][Math]::Min(3, 1 + [Math]::Floor(($Distance * 2.0) / $Radius))
}

function Get-ZMIndustrialZoneHash {
    param([int]$Seed, [int]$X, [int]$Y)

    $key = "industrial-zone-v1|$Seed|$X|$Y"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) }
    finally { $sha.Dispose() }
    return ([int64]$bytes[0] * 16777216 + [int64]$bytes[1] * 65536 + [int64]$bytes[2] * 256 + [int64]$bytes[3])
}

function Get-ZMIndustrialDistrictWeight {
    param([Parameter(Mandatory = $true)][object]$Cell)

    $districtProperty = $Cell.PSObject.Properties['district']
    if ($null -eq $districtProperty -or $null -eq $districtProperty.Value) { return 1.0 }
    $district = $districtProperty.Value
    $hasWeight = if ($district -is [System.Collections.IDictionary]) {
        $district.Contains('industrialOriginWeight')
    } else {
        $null -ne $district.PSObject.Properties['industrialOriginWeight']
    }
    if (-not $hasWeight) { return 1.0 }
    $weight = [double]$district.industrialOriginWeight
    if ([double]::IsNaN($weight) -or [double]::IsInfinity($weight) -or $weight -lt 0) {
        throw "Invalid industrial origin weight at $($Cell.x),$($Cell.y)."
    }
    return $weight
}

function Get-ZMIndustrialZoneOrigins {
    # Deterministic seeded origins: inland, away from safe zones, landmarks and the dense
    # commercial/financial districts, and spaced apart. The count scales with world size.
    param(
        [Parameter(Mandatory = $true)][object[]]$Cells,
        [Parameter(Mandatory = $true)][hashtable]$InlandDistances,
        [Parameter(Mandatory = $true)][int]$Seed,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Settings
    )

    $cellsPerZone = [int]$Settings['cellsPerZone']
    if ($cellsPerZone -lt 1) { throw 'industrialZones.cellsPerZone must be at least 1.' }
    $minimumInland = [int]$Settings['minInlandDistance']
    $minimumSpacing = [double]$Settings['minSpacing']
    $excludedTags = @($Settings['excludedOriginTags'] | ForEach-Object { [string]$_ })
    $count = [int][Math]::Max(1, [Math]::Round($Cells.Count / [double]$cellsPerZone))
    $candidates = @($Cells | Where-Object {
        $cell = $_
        $safeZone = $cell.PSObject.Properties['safeZone']
        $landmarks = $cell.PSObject.Properties['landmarks']
        $excluded = @(@($cell.environment.tags) | Where-Object {
            $_ -in $excludedTags -and ($_ -ne 'radioactive' -or (Test-ZMSceneryRadioactiveTheme $cell))
        })
        $InlandDistances["$($cell.x),$($cell.y)"] -ge $minimumInland -and
            ($null -eq $safeZone -or $null -eq $safeZone.Value) -and
            ($null -eq $landmarks -or @($landmarks.Value).Count -eq 0) -and
            $excluded.Count -eq 0 -and (Get-ZMIndustrialDistrictWeight $cell) -gt 0
    } | Sort-Object @{ Expression = {
        $hash = Get-ZMIndustrialZoneHash $Seed ([int]$_.x) ([int]$_.y)
        -[Math]::Log(($hash + 1.0) / 4294967297.0) / (Get-ZMIndustrialDistrictWeight $_)
    } }, x, y)
    $origins = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $candidates) {
        if ($origins.Count -ge $count) { break }
        $tooClose = $false
        foreach ($origin in $origins) {
            $dx = [double]$candidate.x - $origin.x
            $dy = [double]$candidate.y - $origin.y
            if ([Math]::Sqrt($dx * $dx + $dy * $dy) -lt $minimumSpacing) { $tooClose = $true; break }
        }
        if (-not $tooClose) { $origins.Add([pscustomobject]@{ id = $origins.Count; x = [int]$candidate.x; y = [int]$candidate.y }) }
    }
    if ($origins.Count -lt $count) {
        Write-Warning "Industrial zones: placed $($origins.Count) of $count requested origins."
    }
    return @($origins)
}

function Test-ZMIndustrialZoneCell {
    param([Parameter(Mandatory = $true)][object]$Cell)

    $property = $Cell.PSObject.Properties['industrialZone']
    if ($null -eq $property -or $null -eq $property.Value) { return $false }
    if ($property.Value -is [bool]) { return $property.Value }
    return $true
}

function Set-ZMSceneryDensityFields {
    param(
        [Parameter(Mandatory = $true)][object[]]$Cells,
        [Parameter(Mandatory = $true)][object[]]$OceanBoundaryCells,
        [Parameter(Mandatory = $true)][string[]]$ProfilePriority,
        [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$GridCells,
        [int]$Seed = 0,
        [System.Collections.IDictionary]$IndustrialZoneSettings = $null,
        [AllowEmptyCollection()][object[]]$RadiationSources = @(),
        [double]$DestroyedRadiusCells = 0,
        [double]$MilitaryRadiusCells = 0
    )

    $distances = Get-ZMSceneryInlandDistances $Cells $OceanBoundaryCells
    $militaryOrigins = [System.Collections.Generic.List[object]]::new()
    if ($MilitaryRadiusCells -gt 0) {
        foreach ($cell in $Cells) {
            $landmarks = $cell.PSObject.Properties['landmarks']
            if ($null -eq $landmarks) { continue }
            $kind = Get-ZMSceneryLandmarkZoneType @($landmarks.Value)
            if (-not [string]::IsNullOrWhiteSpace($kind)) {
                $militaryOrigins.Add([pscustomobject]@{ x = [int]$cell.x; y = [int]$cell.y; kind = $kind })
            }
        }
    }
    $industrialOrigins = @()
    $industrialRadius = 0.0
    if ($null -ne $IndustrialZoneSettings -and [bool]$IndustrialZoneSettings['enabled']) {
        $industrialRadius = [double]$IndustrialZoneSettings['radius']
        if ($industrialRadius -le 0) { throw 'industrialZones.radius must be positive.' }
        $industrialOrigins = @(Get-ZMIndustrialZoneOrigins $Cells $distances $Seed $IndustrialZoneSettings)
    }
    foreach ($cell in $Cells) {
        $profile = Get-ZMSceneryEnvironmentProfile $cell $ProfilePriority -CurrentPolicy
        $radialDistance = Get-ZMSceneryRadialDistance ([int]$cell.x) ([int]$cell.y) $GridCells
        $zone = Get-ZMSceneryRadialDensityZone $radialDistance $distances["$($cell.x),$($cell.y)"] $profile
        $tier = $zone.tier
        $source = $zone.source
        $sceneryZone = $null
        if ($profile -eq 'destroyed' -and $DestroyedRadiusCells -gt 0) {
            $sceneryZone = Get-ZMNearestSceneryZone $cell.x $cell.y $RadiationSources $DestroyedRadiusCells
            if ($null -eq $sceneryZone) { throw "Destroyed scenery at $($cell.x),$($cell.y) has no detonation within its configured radius." }
            $sceneryZone.kind = 'destroyed'
            if ($source -ne 'protected_coast') {
                $tier = Get-ZMDestroyedZoneTier $sceneryZone.distance $sceneryZone.radius
                $source = 'destroyed_ring'
            }
        } elseif ($profile -in @('military', 'fortified') -and $MilitaryRadiusCells -gt 0) {
            $matchingOrigins = @($militaryOrigins | Where-Object { $_.kind -eq $profile })
            $sceneryZone = Get-ZMNearestSceneryZone $cell.x $cell.y $matchingOrigins $MilitaryRadiusCells
            if ($null -eq $sceneryZone) { throw "$profile scenery at $($cell.x),$($cell.y) has no matching landmark within its configured radius." }
            $tier = [Math]::Min($tier, (Get-ZMIndustrialZoneTierCap $sceneryZone.distance $sceneryZone.radius))
        }
        $industrialZone = $null
        if ($profile -ne 'safe_zone' -and @($cell.environment.tags) -notcontains 'safe_zone') {
            foreach ($origin in $industrialOrigins) {
                $dx = [double]$cell.x - $origin.x
                $dy = [double]$cell.y - $origin.y
                $distance = [Math]::Round([Math]::Sqrt($dx * $dx + $dy * $dy), 3)
                if ($distance -le $industrialRadius -and ($null -eq $industrialZone -or $distance -lt $industrialZone.distance)) {
                    $industrialZone = [ordered]@{ id = $origin.id; originX = $origin.x; originY = $origin.y; distance = $distance; radius = $industrialRadius }
                }
            }
        }
        if ($null -ne $industrialZone) {
            if ($null -eq $sceneryZone) {
                $tier = [Math]::Min($tier, (Get-ZMIndustrialZoneTierCap $industrialZone.distance $industrialRadius))
            }
            if (@($cell.environment.tags) -notcontains 'industrial_zone') {
                $cell.environment.tags = @(@($cell.environment.tags) + 'industrial_zone' | Sort-Object -Unique)
            }
        }
        if ($null -ne $industrialZone -or $industrialOrigins.Count -gt 0) {
            Add-Member -InputObject $cell -NotePropertyName industrialZone -NotePropertyValue $industrialZone -Force
        }
        if ($null -ne $sceneryZone) {
            Add-Member -InputObject $cell -NotePropertyName sceneryZone -NotePropertyValue $sceneryZone -Force
        }
        Add-Member -InputObject $cell -NotePropertyName sceneryDensityPolicyVersion -NotePropertyValue 2 -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryDensityTier -NotePropertyValue $tier -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryDensitySource -NotePropertyValue $source -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryInlandDistance -NotePropertyValue $zone.inlandDistance -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryRadialDistance -NotePropertyValue $zone.radialDistance -Force
        Add-Member -InputObject $cell -NotePropertyName buildingDensityTier -NotePropertyValue $tier -Force
    }
}

function Get-ZMStoredSceneryDensity {
    param(
        [Parameter(Mandatory = $true)][object]$Cell,
        [ValidateRange(0, 2147483647)][int]$GridCells = 0
    )

    $baseFields = @('sceneryDensityPolicyVersion', 'sceneryDensityTier', 'sceneryDensitySource', 'sceneryInlandDistance')
    $knownFields = @($baseFields + 'sceneryRadialDistance')
    $present = @($knownFields | Where-Object { $null -ne $Cell.PSObject.Properties[$_] })
    if ($present.Count -eq 0) { return $null }
    $context = "cell $($Cell.x),$($Cell.y)"
    if ($null -eq $Cell.PSObject.Properties['sceneryDensityPolicyVersion']) {
        throw "Incomplete stored scenery density for $context; regenerate the manifest."
    }
    if (($Cell.sceneryDensityPolicyVersion -isnot [int] -and $Cell.sceneryDensityPolicyVersion -isnot [long]) -or $Cell.sceneryDensityPolicyVersion -notin @(1, 2)) {
        throw "Unsupported scenery density policy for $context."
    }
    $fields = if ($Cell.sceneryDensityPolicyVersion -eq 2) { @($baseFields + 'sceneryRadialDistance') } else { $baseFields }
    $presentRequired = @($fields | Where-Object { $null -ne $Cell.PSObject.Properties[$_] })
    if ($presentRequired.Count -ne $fields.Count) { throw "Incomplete stored scenery density for $context; regenerate the manifest." }
    if ($Cell.sceneryDensityPolicyVersion -eq 1 -and $null -ne $Cell.PSObject.Properties['sceneryRadialDistance']) {
        throw "Unexpected scenery radial distance for policy-v1 $context."
    }
    if (($Cell.sceneryDensityTier -isnot [int] -and $Cell.sceneryDensityTier -isnot [long]) -or $Cell.sceneryDensityTier -notin @(1, 2, 3)) {
        throw "Invalid stored scenery density tier for $context."
    }
    if (($Cell.sceneryInlandDistance -isnot [int] -and $Cell.sceneryInlandDistance -isnot [long]) -or $Cell.sceneryInlandDistance -lt 0) {
        throw "Invalid stored scenery inland distance for $context."
    }
    $validSources = if ($Cell.sceneryDensityPolicyVersion -eq 2) {
        @('protected_coast', 'radial_band', 'destroyed_ring', 'district:commercial', 'district:financial', 'district:settlement')
    } else {
        @('protected_coast', 'inland_band', 'district:commercial', 'district:financial')
    }
    if ($Cell.sceneryDensitySource -isnot [string] -or $Cell.sceneryDensitySource -cnotin $validSources) {
        throw "Invalid stored scenery density source for $context."
    }
    $sourceProfile = if ($Cell.sceneryDensitySource.StartsWith('district:')) { $Cell.sceneryDensitySource.Substring(9) } else { 'grassland' }
    if ($Cell.sceneryDensityPolicyVersion -eq 2) {
        if ($Cell.sceneryRadialDistance -isnot [int] -and $Cell.sceneryRadialDistance -isnot [long] -and
            $Cell.sceneryRadialDistance -isnot [double] -and $Cell.sceneryRadialDistance -isnot [decimal]) {
            throw "Invalid stored scenery radial distance for $context."
        }
        $radialDistance = [double]$Cell.sceneryRadialDistance
        if ([double]::IsNaN($radialDistance) -or [double]::IsInfinity($radialDistance) -or $radialDistance -lt 0) {
            throw "Invalid stored scenery radial distance for $context."
        }
        if ($GridCells -gt 0) {
            $expectedRadialDistance = Get-ZMSceneryRadialDistance ([int]$Cell.x) ([int]$Cell.y) $GridCells
            if ($radialDistance -ne $expectedRadialDistance) {
                throw "Inconsistent stored scenery radial distance for $context."
            }
        }
        $expected = Get-ZMSceneryRadialDensityZone $radialDistance $Cell.sceneryInlandDistance $sourceProfile
    } else {
        $expected = Get-ZMSceneryDensityZone $Cell.sceneryInlandDistance $sourceProfile
    }
    $expectedTier = $expected.tier
    $expectedSource = $expected.source
    $specialZoneProperty = $Cell.PSObject.Properties['sceneryZone']
    $specialZone = if ($null -ne $specialZoneProperty) { $specialZoneProperty.Value } else { $null }
    $profileProperty = $Cell.PSObject.Properties['environmentProfile']
    $planProfile = if ($null -ne $profileProperty) { [string]$profileProperty.Value } else { '' }
    $specialProfile = $planProfile -in @('destroyed', 'military', 'fortified')
    if ($null -ne $specialZone) {
        $kind = [string]$specialZone.kind
        $distance = [double]$specialZone.distance
        $radius = [double]$specialZone.radius
        $dx = [double]$Cell.x - [double]$specialZone.originX
        $dy = [double]$Cell.y - [double]$specialZone.originY
        if ($kind -notin @('destroyed', 'military', 'fortified') -or
            [double]::IsNaN($distance) -or [double]::IsInfinity($distance) -or $distance -lt 0 -or
            [double]::IsNaN($radius) -or [double]::IsInfinity($radius) -or $radius -le 0 -or $distance -gt $radius -or
            $distance -ne [Math]::Round([Math]::Sqrt($dx * $dx + $dy * $dy), 3)) {
            throw "Invalid scenery zone for $context."
        }
        $specialProfile = $true
        if ($kind -eq 'destroyed' -and $expected.source -ne 'protected_coast') {
            $expectedTier = Get-ZMDestroyedZoneTier $distance $radius
            $expectedSource = 'destroyed_ring'
        } elseif ($kind -in @('military', 'fortified')) {
            $expectedTier = [Math]::Min($expectedTier, (Get-ZMIndustrialZoneTierCap $distance $radius))
        }
    } elseif ($Cell.sceneryDensitySource -eq 'destroyed_ring') {
        if ($planProfile -ne 'destroyed' -or $expected.source -eq 'protected_coast') {
            throw "Destroyed scenery density lacks its zone for $context."
        }
        # A shared recipe keeps the resolved tier, not the per-cell detonation distance.
        $expectedTier = $Cell.sceneryDensityTier
        $expectedSource = 'destroyed_ring'
    }
    $tierMatches = $expectedTier -eq $Cell.sceneryDensityTier
    if ($null -eq $specialZone -and $planProfile -in @('military', 'fortified')) {
        $tierMatches = $Cell.sceneryDensityTier -le $expectedTier
    }
    if (-not $specialProfile -and (Test-ZMIndustrialZoneCell $Cell)) {
        $industrialZone = $Cell.industrialZone
        $hasDistance = if ($industrialZone -is [System.Collections.IDictionary]) { $industrialZone.Contains('distance') } else { $null -ne $industrialZone.PSObject.Properties['distance'] }
        if ($hasDistance) {
            $expectedTier = [Math]::Min($expectedTier, (Get-ZMIndustrialZoneTierCap ([double]$industrialZone.distance) ([double]$industrialZone.radius)))
            $tierMatches = $expectedTier -eq $Cell.sceneryDensityTier
        } else {
            # Plan recipes keep only the zone flag (per-cell distance would split shared recipes); a zone can only cap the tier.
            $tierMatches = $Cell.sceneryDensityTier -le $expectedTier
        }
    }
    if (-not $tierMatches -or $expectedSource -cne $Cell.sceneryDensitySource) {
        throw "Inconsistent stored scenery density policy for $context."
    }
    $alias = $Cell.PSObject.Properties['buildingDensityTier']
    if ($null -eq $alias -or ($alias.Value -isnot [int] -and $alias.Value -isnot [long]) -or $alias.Value -ne $Cell.sceneryDensityTier) {
        throw "Scenery/building density alias mismatch for $context."
    }
    $storedDensity = [ordered]@{
        sceneryDensityPolicyVersion = [int]$Cell.sceneryDensityPolicyVersion
        sceneryDensityTier = [int]$Cell.sceneryDensityTier
        sceneryDensitySource = $Cell.sceneryDensitySource
        sceneryInlandDistance = [int]$Cell.sceneryInlandDistance
        buildingDensityTier = [int]$Cell.sceneryDensityTier
    }
    if ($Cell.sceneryDensityPolicyVersion -eq 2) {
        $storedDensity.sceneryRadialDistance = [double]$Cell.sceneryRadialDistance
    }
    return [pscustomobject]$storedDensity
}

function Test-ZMSceneryDensityManifest {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    $environmentProperty = $Manifest.map.PSObject.Properties['environment']
    $versionProperty = if ($null -ne $environmentProperty -and $null -ne $environmentProperty.Value) {
        $environmentProperty.Value.PSObject.Properties['sceneryDensityPolicyVersion']
    } else { $null }
    if ($null -ne $versionProperty -and (($versionProperty.Value -isnot [int] -and $versionProperty.Value -isnot [long]) -or $versionProperty.Value -notin @(1, 2))) {
        throw 'Unsupported manifest scenery density policy.'
    }
    $gridCells = 0
    if ($null -ne $versionProperty -and $versionProperty.Value -eq 2) {
        $gridProperty = $Manifest.map.PSObject.Properties['gridCells']
        if ($null -eq $gridProperty -or ($gridProperty.Value -isnot [int] -and $gridProperty.Value -isnot [long]) -or $gridProperty.Value -lt 1) {
            throw 'Policy-v2 manifest requires a positive map.gridCells value.'
        }
        $gridCells = [int]$gridProperty.Value
    }
    foreach ($cell in $Manifest.cells) {
        $stored = Get-ZMStoredSceneryDensity $cell -GridCells $gridCells
        if ($null -ne $versionProperty -and $null -eq $stored) {
            throw "Manifest scenery density missing at $($cell.x),$($cell.y); regenerate the manifest."
        }
        if ($null -eq $versionProperty -and $null -ne $stored) {
            throw "Stored scenery density requires a manifest policy header at $($cell.x),$($cell.y)."
        }
        if ($null -ne $versionProperty -and $null -ne $stored -and $stored.sceneryDensityPolicyVersion -ne $versionProperty.Value) {
            throw "Manifest/cell scenery density policy mismatch at $($cell.x),$($cell.y)."
        }
    }
    return $null -ne $versionProperty
}

function Get-ZMScenerySelectionHash {
    param(
        [Parameter(Mandatory = $true)][int]$Seed,
        [Parameter(Mandatory = $true)][string]$CellPolicy,
        [Parameter(Mandatory = $true)][string]$Ring,
        [Parameter(Mandatory = $true)][string]$Slot,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$Variant,
        [ValidateSet('tier', 'template')][string]$Purpose = 'tier'
    )

    $parts = @('scenery-v1', $Seed.ToString([Globalization.CultureInfo]::InvariantCulture), $CellPolicy, $Ring, $Slot, $Role, $Variant.ToString([Globalization.CultureInfo]::InvariantCulture), $Purpose)
    $key = ($parts | ForEach-Object { "$($_.Length):$_" }) -join '|'
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) }
    finally { $sha.Dispose() }
    return ([int64]$bytes[0] * 16777216 + [int64]$bytes[1] * 65536 + [int64]$bytes[2] * 256 + [int64]$bytes[3])
}

function Get-ZMPrimaryBuildingTemplates {
    param(
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][bool]$IsRadioactive,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ArmyTemplates,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$DestroyedTemplates,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RadioactiveTemplates,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$GenericTemplates,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$WarehouseTemplates,
        [AllowEmptyCollection()][string[]]$FortifiedTemplates = @()
    )

    $profileKey = $Profile.ToLowerInvariant()
    if ($profileKey -eq 'military') { return @($ArmyTemplates) }
    if ($profileKey -eq 'fortified') { return @($ArmyTemplates) + @($FortifiedTemplates) }
    if ($profileKey -eq 'destroyed') { return @($DestroyedTemplates) }
    if ($profileKey -eq 'safe_zone') { return @($GenericTemplates) + @($WarehouseTemplates) }
    if ($profileKey -eq 'radioactive' -or $IsRadioactive) { return @($RadioactiveTemplates) }
    return @($GenericTemplates) + @($WarehouseTemplates)
}

function Get-ZMSceneryDecorationTemplates {
    param(
        [AllowEmptyCollection()][string[]]$Templates,
        [string]$Profile,
        [bool]$IndustrialZone,
        [bool]$IsRadioactive
    )

    $profileKey = $Profile.ToLowerInvariant()
    $allowed = switch ($profileKey) {
        'destroyed' { @('destroyed') }
        'military' { @('army') }
        'fortified' { @('fortified') }
        'safe_zone' { @() }
        default {
            if ($IndustrialZone -or $profileKey -eq 'industrial') { @('industrial', 'radioactive') }
            elseif ($profileKey -eq 'radioactive' -or $IsRadioactive) { @('radioactive') }
            else { @() }
        }
    }
    foreach ($template in $Templates) {
        $path = $template.Replace('\', '/').ToLowerInvariant()
        $theme = if ($path -match '^decorations/tile_destroyed_') { 'destroyed' }
        elseif ($path -match '^decorations/tile_army_') { 'army' }
        elseif ($path -match '^decorations/tile_fortified_') { 'fortified' }
        elseif ($path -match '^decorations/tile_industrial_') { 'industrial' }
        elseif ($path -match '^(?:decorations/tile_ra_|terrain/tile_ra_)') { 'radioactive' }
        else { '' }
        if ([string]::IsNullOrWhiteSpace($theme) -or $theme -in $allowed) { $template }
    }
}

function Get-ZMSceneryPreferredTemplatePattern {
    param(
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][bool]$IndustrialZone,
        [Parameter(Mandatory = $true)][bool]$IsRadioactive,
        [string]$RadioactiveBuildingPattern = '',
        [string]$FortifiedBuildingPattern = '^buildings/tile_fortified_'
    )

    $profileKey = $Profile.ToLowerInvariant()
    if ($Role -in @('building', 'multi_tile_building')) {
        if ($profileKey -eq 'destroyed') { return '^buildings/tile_(?:destroyed|skyscraper_destroyed)_' }
        if ($profileKey -eq 'military') { return '^army/' }
        if ($profileKey -eq 'fortified') { return $FortifiedBuildingPattern }
        if ($profileKey -eq 'safe_zone') { return '' }
        if (($profileKey -eq 'radioactive' -or $IsRadioactive) -and -not [string]::IsNullOrWhiteSpace($RadioactiveBuildingPattern)) {
            return $RadioactiveBuildingPattern
        }
        if ($IndustrialZone -or $profileKey -eq 'industrial') { return '^buildings/tile_industrial_' }
        return ''
    }

    if ($Role -notin @('decoration', 'open_terrain_fill')) { return '' }
    if ($profileKey -eq 'destroyed') { return '^decorations/tile_destroyed_' }
    if ($profileKey -eq 'military') { return '^decorations/tile_army_' }
    if ($profileKey -eq 'fortified') { return '^decorations/tile_fortified_' }
    if ($profileKey -eq 'safe_zone') { return '' }
    if ($IndustrialZone -or $profileKey -eq 'industrial') {
        return '^(?:decorations/tile_(?:ra_|industrial_)|terrain/tile_ra_(?:brush(?:_[0-9]+[st])?|fence_a(?:_(?:cap|corner|double))?))'
    }
    if ($profileKey -eq 'radioactive' -or $IsRadioactive) {
        return '^(?:decorations/tile_ra_|terrain/tile_ra_(?:brush(?:_[0-9]+[st])?|fence_a(?:_(?:cap|corner|double))?))'
    }
    return ''
}

function Get-ZMProfileTerrainTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Terrain,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][bool]$IsRadioactive,
        [Parameter(Mandatory = $true)][bool]$IndustrialZone,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ProfileTemplates,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$TerrainTemplates
    )

    $terrainKey = if ([string]::IsNullOrWhiteSpace($Terrain)) { 'default' } else { $Terrain }
    $profileKey = $Profile.ToLowerInvariant()
    $themeProfile = if ($profileKey -in @('destroyed', 'military', 'fortified', 'safe_zone')) {
        $profileKey
    } elseif ($profileKey -eq 'radioactive' -or $IsRadioactive) {
        'radioactive'
    } elseif ($IndustrialZone -or $profileKey -eq 'industrial') {
        'industrial'
    } else {
        ''
    }
    if (-not [string]::IsNullOrWhiteSpace($themeProfile) -and
        $ProfileTemplates.Contains($themeProfile) -and
        $ProfileTemplates[$themeProfile].Contains($terrainKey)) {
        return [string]$ProfileTemplates[$themeProfile][$terrainKey]
    }
    if ($TerrainTemplates.Contains($terrainKey)) { return [string]$TerrainTemplates[$terrainKey] }
    return [string]$TerrainTemplates.default
}

function Get-ZMTopologyVariantCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$BaseTemplate,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$GlobalVariantTemplates,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ProfileVariantTemplates,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$AvailableTemplates
    )

    $baseKey = $BaseTemplate.Replace('\', '/').ToLowerInvariant()
    $profileKey = $Profile.ToLowerInvariant()
    $variants = $null
    if ($ProfileVariantTemplates.Contains($profileKey) -and
        $ProfileVariantTemplates[$profileKey].Contains($baseKey)) {
        $variants = @($ProfileVariantTemplates[$profileKey][$baseKey])
    } elseif ($GlobalVariantTemplates.Contains($baseKey)) {
        $variants = @($GlobalVariantTemplates[$baseKey])
    }
    if ($null -eq $variants) { return @() }
    return @($variants | Where-Object {
        $key = ([string]$_).Replace('\', '/').ToLowerInvariant()
        $AvailableTemplates.Contains($key)
    } | ForEach-Object {
        $key = ([string]$_).Replace('\', '/').ToLowerInvariant()
        [string]$AvailableTemplates[$key]
    })
}

function Select-ZMSceneryTemplate {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Templates,
        [Parameter(Mandatory = $true)][ValidateRange(1, 3)][int]$ZoneTier,
        [Parameter(Mandatory = $true)][ValidateRange(0, 99)][int]$Roll,
        [Parameter(Mandatory = $true)][ValidateRange(0, 4294967295)][long]$ChoiceHash,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$RouteAdjacentWall,
        [switch]$Required,
        [string]$PreferredPattern = '',
        [ValidateRange(0, 100)][int]$PreferredChancePercent = 100,
        [hashtable]$UsageCounts = $null,
        # Explicit opt-in for pools whose density tags are presentation only (radioactive towers).
        [switch]$AnyTier,
        [switch]$LowDensityBuildingPreference
    )

    # The caller supplies one compatible functional/footprint pool, never a global neutral pool.
    $target = Get-ZMSceneryTargetTier $ZoneTier $Roll -RouteAdjacentWall:$RouteAdjacentWall
    $eligible = [System.Collections.Generic.List[string]]::new()
    $excluded = [System.Collections.Generic.List[object]]::new()
    foreach ($template in $Templates) {
        $tag = Get-ZMTemplateDensityTag $template
        if ($AnyTier -or $tag -eq 0 -or $tag -eq $target) {
            $eligible.Add($template.Replace('\', '/').ToLowerInvariant())
        } else {
            $excluded.Add([pscustomobject]@{ template = $template; tag = $tag; reason = "target_tier_$target" })
        }
    }
    $pool = [string[]]@($eligible | Select-Object -Unique)
    [Array]::Sort($pool, [StringComparer]::Ordinal)
    $preferred = $false
    $weightedThemeChoice = $false
    if (-not [string]::IsNullOrWhiteSpace($PreferredPattern)) {
        $themed = [string[]]@($pool | Where-Object { $_ -match $PreferredPattern })
        $ordinary = [string[]]@($pool | Where-Object { $_ -notmatch $PreferredPattern })
        if ($themed.Count -gt 0) {
            if ($ordinary.Count -eq 0 -or $PreferredChancePercent -eq 100) {
                $pool = $themed
                $preferred = $true
            } else {
                $weightedThemeChoice = $true
                if (($ChoiceHash % 100) -lt $PreferredChancePercent) {
                    $pool = $themed
                    $preferred = $true
                } else {
                    $pool = $ordinary
                }
            }
        }
    }
    $lowDensityPreferenceApplied = $false
    if ($LowDensityBuildingPreference -and $ZoneTier -eq 1 -and -not $AnyTier) {
        $lowDensityTemplates = [string[]]@($pool | Where-Object { (Get-ZMTemplateDensityTag $_) -eq 1 })
        $neutralTemplates = [string[]]@($pool | Where-Object { (Get-ZMTemplateDensityTag $_) -eq 0 })
        if ($lowDensityTemplates.Count -gt 0 -and $neutralTemplates.Count -gt 0) {
            if (($ChoiceHash % 3) -lt 2) {
                $pool = $lowDensityTemplates
            } else {
                $pool = $neutralTemplates
            }
            $lowDensityPreferenceApplied = $true
        }
    }
    if ($pool.Count -eq 0 -and $Required) {
        throw "Required scenery pool unavailable at ${Context}: zone=$ZoneTier target=$target routeAdjacentWall=$([bool]$RouteAdjacentWall)."
    }
    # Optional usage balancing: only the least-used eligible templates remain candidates, so every
    # pool member is reached before any repeats; the hash still breaks ties deterministically.
    if ($null -ne $UsageCounts -and $pool.Count -gt 1) {
        $minimumUsage = [int]::MaxValue
        foreach ($template in $pool) {
            $usage = if ($UsageCounts.ContainsKey($template)) { [int]$UsageCounts[$template] } else { 0 }
            if ($usage -lt $minimumUsage) { $minimumUsage = $usage }
        }
        $pool = [string[]]@($pool | Where-Object { $usage = if ($UsageCounts.ContainsKey($_)) { [int]$UsageCounts[$_] } else { 0 }; $usage -eq $minimumUsage })
    }
    $chosen = $null
    if ($pool.Count -gt 0) {
        $choiceIndex = if ($lowDensityPreferenceApplied) {
            [int](([Math]::Floor($ChoiceHash / 3.0)) % $pool.Count)
        } elseif ($weightedThemeChoice) {
            [int](([Math]::Floor($ChoiceHash / 100.0)) % $pool.Count)
        } else {
            [int]($ChoiceHash % $pool.Count)
        }
        $chosen = $pool[$choiceIndex]
    }
    if ($null -ne $UsageCounts -and $null -ne $chosen) {
        $UsageCounts[$chosen] = 1 + $(if ($UsageCounts.ContainsKey($chosen)) { [int]$UsageCounts[$chosen] } else { 0 })
    }
    return [pscustomobject]@{
        status = if ($null -eq $chosen) { 'shortage_keep_terrain' } else { 'selected' }
        context = $Context
        zoneTier = $ZoneTier
        targetTier = $target
        template = $chosen
        actualTag = if ($null -eq $chosen) { $null } else { Get-ZMTemplateDensityTag $chosen }
        routeAdjacentWall = [bool]$RouteAdjacentWall
        anyTier = [bool]$AnyTier
        preferredPool = $preferred
        lowDensityPreferenceApplied = $lowDensityPreferenceApplied
        excluded = @($excluded)
    }
}

Export-ModuleMember -Function Get-ZMTemplateDensityTag, Get-ZMTemplateFootprint, Get-ZMLandmarkTemplatePool, Get-ZMSceneryDensityZone, Get-ZMSceneryRadialDistance, Get-ZMSceneryRadialDensityZone, Get-ZMSceneryInlandDistances, Get-ZMSceneryTargetTier, Get-ZMSceneryPossibleTargetTiers, Get-ZMSceneryLandmarkTags, Get-ZMSceneryLandmarkZoneType, Test-ZMSceneryRadioactiveTheme, Get-ZMSceneryEnvironmentProfile, Get-ZMNearestSceneryZone, Get-ZMDestroyedZoneTier, Set-ZMSceneryDensityFields, Get-ZMIndustrialZoneTierCap, Get-ZMIndustrialDistrictWeight, Get-ZMIndustrialZoneOrigins, Test-ZMIndustrialZoneCell, Get-ZMStoredSceneryDensity, Test-ZMSceneryDensityManifest, Get-ZMScenerySelectionHash, Get-ZMPrimaryBuildingTemplates, Get-ZMSceneryDecorationTemplates, Get-ZMSceneryPreferredTemplatePattern, Get-ZMProfileTerrainTemplate, Get-ZMTopologyVariantCandidates, Select-ZMSceneryTemplate
