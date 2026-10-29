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

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $source).Path)
$text = [Text.Encoding]::UTF8.GetString($bytes)
$document = $text | ConvertFrom-Json
Assert-Fields $document @('schemaVersion', 'id', 'name', 'description', 'tags', 'props') 'Prefab'
Assert-Finite $document.schemaVersion 'Schema version'
if ($document.schemaVersion -ne 1 -or $document.id -isnot [string] -or $document.id -cne $Id -or
    $document.name -isnot [string] -or [string]::IsNullOrWhiteSpace($document.name) -or
    $document.description -isnot [string] -or $document.tags -isnot [array] -or $document.props -isnot [array]) {
    throw 'Prefab metadata, filename or collections are invalid.'
}
$tags = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
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
    $id = if ($null -eq $propId) { "legacy_$propIndex" } else { $propId.Value }
    if ($id -isnot [string] -or $id -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or -not $propIds.Add($id)) {
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
