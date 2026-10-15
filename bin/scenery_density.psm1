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

        $footprint = Get-ZMTemplateFootprint $matches[0]
        $compatible = @($matches | Where-Object {
            $candidateFootprint = Get-ZMTemplateFootprint $_
            $candidateFootprint.width -eq $footprint.width -and $candidateFootprint.height -eq $footprint.height
        })
        return [pscustomobject]@{
            landmark = [string]$landmark
            template = [string]$matches[0]
            footprint = $footprint
            templates = @($compatible)
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

function Set-ZMSceneryDensityFields {
    param(
        [Parameter(Mandatory = $true)][object[]]$Cells,
        [Parameter(Mandatory = $true)][object[]]$OceanBoundaryCells,
        [Parameter(Mandatory = $true)][string[]]$ProfilePriority
    )

    $distances = Get-ZMSceneryInlandDistances $Cells $OceanBoundaryCells
    foreach ($cell in $Cells) {
        $profile = Get-ZMSceneryEnvironmentProfile $cell $ProfilePriority
        $zone = Get-ZMSceneryDensityZone $distances["$($cell.x),$($cell.y)"] $profile
        Add-Member -InputObject $cell -NotePropertyName sceneryDensityPolicyVersion -NotePropertyValue 1 -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryDensityTier -NotePropertyValue $zone.tier -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryDensitySource -NotePropertyValue $zone.source -Force
        Add-Member -InputObject $cell -NotePropertyName sceneryInlandDistance -NotePropertyValue $zone.inlandDistance -Force
        Add-Member -InputObject $cell -NotePropertyName buildingDensityTier -NotePropertyValue $zone.tier -Force
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
    if ($expected.tier -ne $Cell.sceneryDensityTier -or $expected.source -cne $Cell.sceneryDensitySource) {
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
        [switch]$Required
    )

    # The caller supplies one compatible functional/footprint pool, never a global neutral pool.
    $target = Get-ZMSceneryTargetTier $ZoneTier $Roll -RouteAdjacentWall:$RouteAdjacentWall
    $eligible = [System.Collections.Generic.List[string]]::new()
    $excluded = [System.Collections.Generic.List[object]]::new()
    foreach ($template in $Templates) {
        $tag = Get-ZMTemplateDensityTag $template
        if ($tag -eq 0 -or $tag -eq $target) {
            $eligible.Add($template.Replace('\', '/').ToLowerInvariant())
        } else {
            $excluded.Add([pscustomobject]@{ template = $template; tag = $tag; reason = "target_tier_$target" })
        }
    }
    $pool = [string[]]@($eligible | Select-Object -Unique)
    [Array]::Sort($pool, [StringComparer]::Ordinal)
    if ($pool.Count -eq 0 -and $Required) {
        throw "Required scenery pool unavailable at ${Context}: zone=$ZoneTier target=$target routeAdjacentWall=$([bool]$RouteAdjacentWall)."
    }
    $chosen = if ($pool.Count -gt 0) { $pool[[int]($ChoiceHash % $pool.Count)] } else { $null }
    return [pscustomobject]@{
        status = if ($null -eq $chosen) { 'shortage_keep_terrain' } else { 'selected' }
        context = $Context
        zoneTier = $ZoneTier
        targetTier = $target
        template = $chosen
        actualTag = if ($null -eq $chosen) { $null } else { Get-ZMTemplateDensityTag $chosen }
        routeAdjacentWall = [bool]$RouteAdjacentWall
        excluded = @($excluded)
    }
}

Export-ModuleMember -Function Get-ZMTemplateDensityTag, Get-ZMTemplateFootprint, Get-ZMLandmarkTemplatePool, Get-ZMSceneryDensityZone, Get-ZMSceneryInlandDistances, Get-ZMSceneryTargetTier, Get-ZMSceneryPossibleTargetTiers, Get-ZMSceneryLandmarkTags, Get-ZMSceneryEnvironmentProfile, Set-ZMSceneryDensityFields, Get-ZMStoredSceneryDensity, Test-ZMSceneryDensityManifest, Get-ZMScenerySelectionHash, Select-ZMSceneryTemplate
