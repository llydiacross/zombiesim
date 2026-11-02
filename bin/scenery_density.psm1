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
        return [pscustomobject]@{
            landmark = [string]$landmark
            template = [string]$compatible[0]
            footprint = $footprint
            templates = @($compatible)
            singleTileFallbackTemplates = @($singleTileFallbacks)
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

function Get-ZMSceneryEnvironmentProfile {
    param(
        [Parameter(Mandatory = $true)][object]$Cell,
        [Parameter(Mandatory = $true)][string[]]$ProfilePriority
    )

    foreach ($tag in $ProfilePriority) {
        if (@($Cell.environment.tags) -contains $tag) { return $tag }
    }
    if ($Cell.building.present) { return 'settlement' }
    return [string]$Cell.environment.terrain
}

function Get-ZMIndustrialZoneTierCap {
    # Low density at a zone origin, rising to the surrounding density at its edge.
    param(
        [Parameter(Mandatory = $true)][double]$Distance,
        [Parameter(Mandatory = $true)][double]$Radius
    )

    if ($Radius -le 0) { throw 'Industrial zone radius must be positive.' }
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
        $InlandDistances["$($cell.x),$($cell.y)"] -ge $minimumInland -and
            ($null -eq $safeZone -or $null -eq $safeZone.Value) -and
            ($null -eq $landmarks -or @($landmarks.Value).Count -eq 0) -and
            @(@($cell.environment.tags) | Where-Object { $_ -in $excludedTags }).Count -eq 0
    } | Sort-Object @{ Expression = { Get-ZMIndustrialZoneHash $Seed ([int]$_.x) ([int]$_.y) } }, x, y)
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
    return $null -ne $property -and $null -ne $property.Value
}

function Set-ZMSceneryDensityFields {
    param(
        [Parameter(Mandatory = $true)][object[]]$Cells,
        [Parameter(Mandatory = $true)][object[]]$OceanBoundaryCells,
        [Parameter(Mandatory = $true)][string[]]$ProfilePriority,
        [int]$Seed = 0,
        [System.Collections.IDictionary]$IndustrialZoneSettings = $null
    )

    $distances = Get-ZMSceneryInlandDistances $Cells $OceanBoundaryCells
    $industrialOrigins = @()
    $industrialRadius = 0.0
    if ($null -ne $IndustrialZoneSettings -and [bool]$IndustrialZoneSettings['enabled']) {
        $industrialRadius = [double]$IndustrialZoneSettings['radius']
        if ($industrialRadius -le 0) { throw 'industrialZones.radius must be positive.' }
        $industrialOrigins = @(Get-ZMIndustrialZoneOrigins $Cells $distances $Seed $IndustrialZoneSettings)
    }
    foreach ($cell in $Cells) {
        $profile = Get-ZMSceneryEnvironmentProfile $cell $ProfilePriority
        $zone = Get-ZMSceneryDensityZone $distances["$($cell.x),$($cell.y)"] $profile
        $tier = $zone.tier
        $industrialZone = $null
        foreach ($origin in $industrialOrigins) {
            $dx = [double]$cell.x - $origin.x
            $dy = [double]$cell.y - $origin.y
            $distance = [Math]::Round([Math]::Sqrt($dx * $dx + $dy * $dy), 3)
            if ($distance -le $industrialRadius -and ($null -eq $industrialZone -or $distance -lt $industrialZone.distance)) {
                $industrialZone = [ordered]@{ id = $origin.id; originX = $origin.x; originY = $origin.y; distance = $distance; radius = $industrialRadius }
            }
        }
        if ($null -ne $industrialZone) {
            $tier = [Math]::Min($tier, (Get-ZMIndustrialZoneTierCap $industrialZone.distance $industrialRadius))
            if (@($cell.environment.tags) -notcontains 'industrial_zone') {
                $cell.environment.tags = @(@($cell.environment.tags) + 'industrial_zone' | Sort-Object -Unique)
            }
        }
        if ($null -ne $industrialZone -or $industrialOrigins.Count -gt 0) {
            Add-Member -InputObject $cell -NotePropertyName industrialZone -NotePropertyValue $industrialZone -Force
        }
        Add-Member -InputObject $cell -NotePropertyName sceneryDensityPolicyVersion -NotePropertyValue 1 -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryDensityTier -NotePropertyValue $tier -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryDensitySource -NotePropertyValue $zone.source -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryInlandDistance -NotePropertyValue $zone.inlandDistance -Force
        Add-Member -InputObject $cell -NotePropertyName buildingDensityTier -NotePropertyValue $tier -Force
    }
}

function Get-ZMStoredSceneryDensity {
    param([Parameter(Mandatory = $true)][object]$Cell)

    $fields = @('sceneryDensityPolicyVersion', 'sceneryDensityTier', 'sceneryDensitySource', 'sceneryInlandDistance')
    $present = @($fields | Where-Object { $null -ne $Cell.PSObject.Properties[$_] })
    if ($present.Count -eq 0) { return $null }
    $context = "cell $($Cell.x),$($Cell.y)"
    if ($present.Count -ne $fields.Count) { throw "Incomplete stored scenery density for $context; regenerate the manifest." }
    if (($Cell.sceneryDensityPolicyVersion -isnot [int] -and $Cell.sceneryDensityPolicyVersion -isnot [long]) -or $Cell.sceneryDensityPolicyVersion -ne 1) {
        throw "Unsupported scenery density policy for $context."
    }
    if (($Cell.sceneryDensityTier -isnot [int] -and $Cell.sceneryDensityTier -isnot [long]) -or $Cell.sceneryDensityTier -notin @(1, 2, 3)) {
        throw "Invalid stored scenery density tier for $context."
    }
    if (($Cell.sceneryInlandDistance -isnot [int] -and $Cell.sceneryInlandDistance -isnot [long]) -or $Cell.sceneryInlandDistance -lt 0) {
        throw "Invalid stored scenery inland distance for $context."
    }
    if ($Cell.sceneryDensitySource -isnot [string] -or $Cell.sceneryDensitySource -cnotin @('protected_coast', 'inland_band', 'district:commercial', 'district:financial')) {
        throw "Invalid stored scenery density source for $context."
    }
    $sourceProfile = if ($Cell.sceneryDensitySource.StartsWith('district:')) { $Cell.sceneryDensitySource.Substring(9) } else { 'grassland' }
    $expected = Get-ZMSceneryDensityZone $Cell.sceneryInlandDistance $sourceProfile
    $expectedTier = $expected.tier
    $tierMatches = $expectedTier -eq $Cell.sceneryDensityTier
    if (Test-ZMIndustrialZoneCell $Cell) {
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
    if (-not $tierMatches -or $expected.source -cne $Cell.sceneryDensitySource) {
        throw "Inconsistent stored scenery density policy for $context."
    }
    $alias = $Cell.PSObject.Properties['buildingDensityTier']
    if ($null -eq $alias -or ($alias.Value -isnot [int] -and $alias.Value -isnot [long]) -or $alias.Value -ne $Cell.sceneryDensityTier) {
        throw "Scenery/building density alias mismatch for $context."
    }
    return [pscustomobject]@{
        sceneryDensityPolicyVersion = 1
        sceneryDensityTier = [int]$Cell.sceneryDensityTier
        sceneryDensitySource = $Cell.sceneryDensitySource
        sceneryInlandDistance = [int]$Cell.sceneryInlandDistance
        buildingDensityTier = [int]$Cell.sceneryDensityTier
    }
}

function Test-ZMSceneryDensityManifest {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    $environmentProperty = $Manifest.map.PSObject.Properties['environment']
    $versionProperty = if ($null -ne $environmentProperty -and $null -ne $environmentProperty.Value) {
        $environmentProperty.Value.PSObject.Properties['sceneryDensityPolicyVersion']
    } else { $null }
    if ($null -ne $versionProperty -and (($versionProperty.Value -isnot [int] -and $versionProperty.Value -isnot [long]) -or $versionProperty.Value -ne 1)) {
        throw 'Unsupported manifest scenery density policy.'
    }
    foreach ($cell in $Manifest.cells) {
        $stored = Get-ZMStoredSceneryDensity $cell
        if ($null -ne $versionProperty -and $null -eq $stored) {
            throw "Manifest scenery density missing at $($cell.x),$($cell.y); regenerate the manifest."
        }
        if ($null -eq $versionProperty -and $null -ne $stored) {
            throw "Stored scenery density requires a manifest policy header at $($cell.x),$($cell.y)."
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
        [hashtable]$UsageCounts = $null,
        # Explicit opt-in for pools whose density tags are presentation only (radioactive towers).
        [switch]$AnyTier
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
    # Themed assets (for example _ra_ buildings in radioactive cells) win whenever one fits the
    # target tier; the rest of the pool remains the fallback for tiers without themed art.
    $preferred = $false
    if (-not [string]::IsNullOrWhiteSpace($PreferredPattern)) {
        $themed = [string[]]@($pool | Where-Object { $_ -match $PreferredPattern })
        if ($themed.Count -gt 0) { $pool = $themed; $preferred = $true }
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
    $chosen = if ($pool.Count -gt 0) { $pool[[int]($ChoiceHash % $pool.Count)] } else { $null }
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
        excluded = @($excluded)
    }
}

Export-ModuleMember -Function Get-ZMTemplateDensityTag, Get-ZMTemplateFootprint, Get-ZMLandmarkTemplatePool, Get-ZMSceneryDensityZone, Get-ZMSceneryInlandDistances, Get-ZMSceneryTargetTier, Get-ZMSceneryPossibleTargetTiers, Get-ZMSceneryLandmarkTags, Get-ZMSceneryEnvironmentProfile, Set-ZMSceneryDensityFields, Get-ZMIndustrialZoneTierCap, Get-ZMIndustrialZoneOrigins, Test-ZMIndustrialZoneCell, Get-ZMStoredSceneryDensity, Test-ZMSceneryDensityManifest, Get-ZMScenerySelectionHash, Select-ZMSceneryTemplate
