param(
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$SourceDirectory = '',
    [string]$OutputDirectory = '',
    [switch]$Apply,
    [switch]$Replace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Id -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Prefab ID must use lowercase letters, numbers, underscores or hyphens.' }
if (-not $SourceDirectory) { $SourceDirectory = Join-Path $root '..\..\data\zombiesim\prefabs' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'content\data_static\prefabs' }
$source = Join-Path $SourceDirectory "$Id.json"
$destination = Join-Path $OutputDirectory "$Id.json"
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Prefab source is missing: $source" }

function Assert-Fields([object]$Value, [string[]]$Names, [string]$Label, [string[]]$Optional = @()) {
    if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw "$Label must be an object." }
    $actual = @($Value.PSObject.Properties.Name)
    foreach ($name in $Names) {
        if ($actual -cnotcontains $name) { throw "$Label is missing field '$name'." }
    }
    foreach ($name in $actual) {
        if ($Names -cnotcontains $name -and $Optional -cnotcontains $name) { throw "$Label contains unsupported field '$name'." }
    }
}

function Assert-Finite([object]$Value, [string]$Label) {
    if ($null -eq $Value -or $Value -is [bool] -or $Value -isnot [ValueType]) { throw "$Label must be a number." }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw "$Label must be finite." }
}

function Assert-GuardRecords([object[]]$Guards) {
    $weaponCatalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\prefab_guard_weapons.json') -Raw | ConvertFrom-Json
    if ($weaponCatalog -isnot [array] -or $weaponCatalog.Count -lt 1) {
        throw 'Guard weapon catalogue must be a non-empty list.'
    }
    $weaponIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($weapon in @($weaponCatalog)) {
        Assert-Fields $weapon @('id', 'label', 'class', 'idle', 'attack') 'Guard weapon choice'
        if ($weapon.id -isnot [string] -or $weapon.id -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or
            -not $weaponIds.Add($weapon.id) -or $weapon.label -isnot [string] -or
            [string]::IsNullOrWhiteSpace($weapon.label) -or $weapon.class -isnot [string] -or
            $weapon.class -cnotmatch '^weapon_[a-zA-Z0-9_]+$' -or $weapon.idle -isnot [string] -or
            [string]::IsNullOrWhiteSpace($weapon.idle) -or $weapon.attack -isnot [string] -or
            [string]::IsNullOrWhiteSpace($weapon.attack)) { throw 'Guard weapon catalogue contains an invalid or duplicate choice.' }
    }
    if (-not $weaponIds.Contains('pistol')) { throw 'Guard weapon catalogue is missing its default pistol.' }
    $calibration = Get-Content -LiteralPath (Join-Path $root 'content\data_static\clothing_citizen_calibration.json') -Raw | ConvertFrom-Json
    if ($calibration.schemaVersion -ne 1 -or $calibration.size -ne 1024 -or $calibration.previewOnly -isnot [bool] -or
        $null -eq $calibration.models -or @($calibration.models.PSObject.Properties).Count -ne 15) {
        throw 'Guard citizen model calibration is invalid.'
    }
    $models = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $calibration.models.PSObject.Properties) {
        if ($entry.Name -cnotmatch '^models/player/group01/(male|female)_(\d\d)\.mdl$' -or
            $entry.Value.sex -cne $Matches[1] -or [int]$Matches[2] -lt 1 -or
            [int]$Matches[2] -gt $(if ($Matches[1] -eq 'male') { 9 } else { 6 })) {
            throw 'Guard citizen model calibration contains an invalid model.'
        }
        if (-not $calibration.previewOnly) { [void]$models.Add($entry.Name) }
    }
    if ($calibration.previewOnly) {
        [void]$models.Add('models/player/group01/male_03.mdl')
        [void]$models.Add('models/player/group01/female_01.mdl')
    }
    $clothing = $null
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($guard in $Guards) {
        Assert-Fields $guard @('guardId', 'name', 'model', 'position', 'angles', 'idle', 'weapon', 'range', 'shirt', 'pants') `
            'Prefab guard' @('damage', 'fireInterval', 'spread')
        if ($guard.guardId -isnot [string] -or $guard.guardId -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or
            -not $ids.Add($guard.guardId)) { throw 'Prefab guard IDs must be valid and unique.' }
        if ($guard.name -isnot [string] -or [string]::IsNullOrWhiteSpace($guard.name) -or
            [Text.Encoding]::UTF8.GetByteCount($guard.name) -gt 64) { throw 'Prefab guard name is invalid.' }
        if ($guard.model -isnot [string] -or -not $models.Contains($guard.model)) {
            throw 'Prefab guard must use a supported clothing-compatible citizen model.'
        }
        Assert-Fields $guard.position @('x', 'y', 'z') 'Guard position'
        Assert-Fields $guard.angles @('p', 'y', 'r') 'Guard rotation'
        foreach ($field in @('x', 'y', 'z')) { Assert-Finite $guard.position.$field "Guard position $field" }
        foreach ($field in @('p', 'y', 'r')) { Assert-Finite $guard.angles.$field "Guard rotation $field" }
        if ($guard.idle -isnot [string] -or [string]::IsNullOrWhiteSpace($guard.idle) -or
            [Text.Encoding]::UTF8.GetByteCount($guard.idle) -gt 128 -or
            $guard.weapon -isnot [string] -or -not $weaponIds.Contains($guard.weapon)) {
            throw 'Prefab guard animation or weapon is invalid.'
        }
        Assert-Finite $guard.range 'Guard range'
        if ($guard.range -le 0) { throw 'Prefab guard range must be positive.' }
        foreach ($garment in @('shirt', 'pants')) {
            $id = $guard.$garment
            if ($id -isnot [string]) { throw "Prefab guard $garment must be a clothing finish ID." }
            if ($id -eq '' -or $id -ceq 'prototype') { continue }
            if ($null -eq $clothing) {
                $clothing = Get-Content -LiteralPath (Join-Path $root 'content\data_static\clothing_catalogue.json') -Raw | ConvertFrom-Json
            }
            $finish = $clothing.finishes.PSObject.Properties[$id]
            if ($null -eq $finish -or $finish.Name -cne $id -or $finish.Value.garment -cne $garment) {
                throw "Prefab guard $garment finish is unavailable or mismatched."
            }
        }
        foreach ($field in @('damage', 'fireInterval', 'spread')) {
            $property = $guard.PSObject.Properties[$field]
            if ($null -eq $property) { continue }
            Assert-Finite $property.Value "Guard $field"
            if (($field -eq 'damage' -and $property.Value -le 0) -or
                ($field -eq 'fireInterval' -and $property.Value -lt 0.05) -or
                ($field -eq 'spread' -and $property.Value -lt 0)) {
                throw "Prefab guard $field is outside its supported range."
            }
        }
    }
}

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $source).Path)
$text = [Text.Encoding]::UTF8.GetString($bytes)
$document = $text | ConvertFrom-Json
Assert-Fields $document @('schemaVersion', 'id', 'name', 'description', 'tags', 'props') 'Prefab' @('lights', 'particles', 'guards', 'worldPlacement')
Assert-Finite $document.schemaVersion 'Schema version'
if ($document.schemaVersion -ne 1 -or $document.id -isnot [string] -or $document.id -cne $Id -or
    $document.name -isnot [string] -or [string]::IsNullOrWhiteSpace($document.name) -or
    $document.description -isnot [string] -or $document.tags -isnot [array] -or $document.props -isnot [array]) {
    throw 'Prefab metadata, filename or collections are invalid.'
}
$tags = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$placementProperty = $document.PSObject.Properties['worldPlacement']
if ($null -ne $placementProperty) {
    $placement = $placementProperty.Value
    Assert-Fields $placement @('enabled', 'profile', 'cellX', 'cellY', 'tileX', 'tileY', 'offset', 'angles') 'World placement'
    if ($placement.enabled -isnot [bool] -or $placement.profile -isnot [string] -or
        @('preview', 'city') -cnotcontains $placement.profile) { throw 'World placement requires a boolean enabled flag and preview or city profile.' }
    foreach ($field in @('cellX', 'cellY', 'tileX', 'tileY')) {
        Assert-Finite $placement.$field "World placement $field"
        if ($placement.$field -ne [Math]::Floor($placement.$field)) { throw 'World placement cell and tile coordinates must be whole numbers.' }
    }
    if ([Math]::Abs($placement.tileX) -gt 2 -or [Math]::Abs($placement.tileY) -gt 2) {
        throw 'World placement tile coordinates must be between -2 and 2.'
    }
    Assert-Fields $placement.offset @('x', 'y', 'z') 'World placement offset'
    Assert-Fields $placement.angles @('p', 'y', 'r') 'World placement rotation'
    foreach ($field in @('x', 'y', 'z')) {
        Assert-Finite $placement.offset.$field "World placement offset $field"
        if ([Math]::Abs($placement.offset.$field) -gt 32768) { throw 'World placement offset exceeds 32768.' }
    }
    foreach ($field in @('p', 'y', 'r')) { Assert-Finite $placement.angles.$field "World placement rotation $field" }
}
$guards = $document.PSObject.Properties['guards']
if ($null -ne $guards) {
    if ($guards.Value -isnot [array]) { throw 'Prefab guards must be a list.' }
    if ($guards.Value.Count -gt 0) {
        Assert-GuardRecords $guards.Value
    }
}
foreach ($tag in $document.tags) {
    if ($tag -isnot [string] -or [string]::IsNullOrWhiteSpace($tag) -or -not $tags.Add($tag)) {
        throw 'Prefab tags must be unique non-empty strings.'
    }
}
$propIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$propIndex = 0
$lootCatalog = $null
foreach ($prop in $document.props) {
    $propIndex++
    Assert-Fields $prop @('model', 'position', 'angles', 'skin') 'Prefab prop' @('scale', 'movable', 'propId', 'lootMode', 'lootGroup', 'lootChance')
    if ($prop.model -isnot [string] -or $prop.model -notmatch '^models/.+\.mdl$' -or
        $prop.model.Contains('..') -or $prop.model.Contains('\') -or $prop.model.Contains(':')) {
        throw 'Prefab prop has an invalid model path.'
    }
    Assert-Fields $prop.position @('x', 'y', 'z') 'Prefab position'
    Assert-Fields $prop.angles @('p', 'y', 'r') 'Prefab rotation'
    foreach ($field in @('x', 'y', 'z')) { Assert-Finite $prop.position.$field "Position $field" }
    foreach ($field in @('p', 'y', 'r')) { Assert-Finite $prop.angles.$field "Rotation $field" }
    Assert-Finite $prop.skin 'Skin'
    if ($prop.skin -lt 0 -or [Math]::Floor([double]$prop.skin) -ne [double]$prop.skin) {
        throw 'Prefab skin must be a non-negative integer.'
    }
    $scale = $prop.PSObject.Properties['scale']
    if ($null -ne $scale) {
        Assert-Finite $scale.Value 'Scale'
        if ($scale.Value -lt 0.1 -or $scale.Value -gt 10) { throw 'Prefab scale must be between 0.1 and 10.' }
    }
    $movable = $prop.PSObject.Properties['movable']
    if ($null -ne $movable -and $movable.Value -isnot [bool]) {
        throw 'Prefab prop movable must be a boolean.'
    }
    $propId = $prop.PSObject.Properties['propId']
    $propRecordId = if ($null -eq $propId) { "legacy_$propIndex" } else { $propId.Value }
    if ($propRecordId -isnot [string] -or $propRecordId -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or -not $propIds.Add($propRecordId)) {
        throw 'Prefab prop IDs must be valid and unique.'
    }
    $lootMode = $prop.PSObject.Properties['lootMode']
    if ($null -ne $lootMode -and ($lootMode.Value -isnot [string] -or
        @('off', 'normal', 'guaranteed') -cnotcontains $lootMode.Value)) {
        throw 'Prefab prop loot mode must be off, normal or guaranteed.'
    }
    $lootGroup = $prop.PSObject.Properties['lootGroup']
    if ($null -ne $lootGroup) {
        if ($lootGroup.Value -isnot [string] -or $lootGroup.Value -cnotmatch '^[a-zA-Z0-9_]+$') {
            throw 'Prefab prop loot group ID is invalid.'
        }
        if ($null -eq $lootCatalog) {
            $lootCatalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\loot.json') -Raw | ConvertFrom-Json
        }
        if (@($lootCatalog.groups.PSObject.Properties.Name) -cnotcontains $lootGroup.Value) {
            throw "Unknown prefab loot group: $($lootGroup.Value)"
        }
    }
    $lootChance = $prop.PSObject.Properties['lootChance']
    if ($null -ne $lootChance) {
        Assert-Finite $lootChance.Value 'Prefab loot chance'
        if ($lootChance.Value -lt 0 -or $lootChance.Value -gt 1) { throw 'Prefab loot chance must be between 0 and 1.' }
    }
}

$lights = $document.PSObject.Properties['lights']
if ($null -ne $lights) {
    if ($lights.Value -isnot [array]) { throw 'Prefab lights must be a list.' }
    $lightIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($light in $lights.Value) {
        Assert-Fields $light @('lightId', 'position', 'angles', 'color', 'brightness', 'fov', 'range') 'Prefab light'
        if ($light.lightId -isnot [string] -or $light.lightId -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or
            -not $lightIds.Add($light.lightId)) { throw 'Prefab light IDs must be valid and unique.' }
        Assert-Fields $light.position @('x', 'y', 'z') 'Light position'
        Assert-Fields $light.angles @('p', 'y', 'r') 'Light rotation'
        Assert-Fields $light.color @('r', 'g', 'b') 'Light color'
        foreach ($field in @('x', 'y', 'z')) { Assert-Finite $light.position.$field "Light position $field" }
        foreach ($field in @('p', 'y', 'r')) { Assert-Finite $light.angles.$field "Light rotation $field" }
        foreach ($field in @('r', 'g', 'b')) {
            $component = $light.color.$field
            Assert-Finite $component "Light color $field"
            if ($component -lt 0 -or $component -gt 255 -or [Math]::Floor([double]$component) -ne [double]$component) {
                throw 'Prefab light color components must be integers between 0 and 255.'
            }
        }
        foreach ($field in @('brightness', 'fov', 'range')) { Assert-Finite $light.$field "Light $field" }
        if ($light.brightness -lt 0 -or $light.brightness -gt 1000000 -or
            $light.fov -lt 0.001 -or $light.fov -gt 179.999 -or
            $light.range -lt 8.001 -or $light.range -gt 1000000) {
            throw 'Prefab light brightness, cone angle or range is invalid.'
        }
    }
}

$particles = $document.PSObject.Properties['particles']
if ($null -ne $particles) {
    if ($particles.Value -isnot [array]) { throw 'Prefab particles must be a list.' }
    $particleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $particleCatalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\prefab_particles.json') -Raw | ConvertFrom-Json
    if ($particleCatalog.schemaVersion -ne 1 -or $particleCatalog.effects -isnot [array]) {
        throw 'Prefab particle catalog is invalid.'
    }
    foreach ($particle in $particles.Value) {
        Assert-Fields $particle @('particleId', 'effect', 'position', 'angles', 'mode') 'Prefab particle' @('overlap')
        if ($particle.particleId -isnot [string] -or $particle.particleId -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or
            -not $particleIds.Add($particle.particleId)) { throw 'Prefab particle IDs must be valid and unique.' }
        if ($particle.effect -isnot [string] -or @($particleCatalog.effects.id) -cnotcontains $particle.effect) {
            throw 'Prefab particle effect is not in the catalog.'
        }
        Assert-Fields $particle.position @('x', 'y', 'z') 'Particle position'
        Assert-Fields $particle.angles @('p', 'y', 'r') 'Particle rotation'
        foreach ($field in @('x', 'y', 'z')) { Assert-Finite $particle.position.$field "Particle position $field" }
        foreach ($field in @('p', 'y', 'r')) { Assert-Finite $particle.angles.$field "Particle rotation $field" }
        if ($particle.mode -isnot [string] -or @('continuous', 'triggered') -cnotcontains $particle.mode) {
            throw 'Prefab particle mode must be continuous or triggered.'
        }
        $overlap = $particle.PSObject.Properties['overlap']
        if ($null -ne $overlap -and $overlap.Value -isnot [bool]) { throw 'Prefab particle overlap must be a boolean.' }
    }
}

$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$exists = Test-Path -LiteralPath $destination -PathType Leaf
if ($exists -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $sourceHash) {
    Write-Output "Prefab $Id is already exported with the same SHA-256."
    return
}
if ($exists -and -not $Replace) { throw "Prefab destination already exists; pass -Replace only after review: $destination" }
if (-not $Apply) {
    Write-Output "Would export prefab $Id to $destination (SHA-256 $sourceHash). No files changed."
    return
}

[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$token = [Guid]::NewGuid().ToString('N')
$temporary = Join-Path $OutputDirectory ".$Id.$token.tmp"
$backup = Join-Path $OutputDirectory ".$Id.$token.bak"
try {
    [IO.File]::WriteAllBytes($temporary, $bytes)
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $sourceHash) {
        throw 'Temporary prefab export hash does not match the source.'
    }
    if ($exists) {
        [IO.File]::Replace($temporary, $destination, $backup)
    } else {
        [IO.File]::Move($temporary, $destination)
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) {
        throw "Export hash mismatch; previous file, if any, remains at $backup."
    }
    if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup }
} finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary }
}
Write-Output "Exported prefab $Id to $destination (SHA-256 $sourceHash)."
