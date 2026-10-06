Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $root 'assets\skybox'
$settings = Get-Content (Join-Path $assets 'catalogue.json') -Raw | ConvertFrom-Json
if ($settings.schemaVersion -ne 1) { throw 'Unsupported sky catalogue schema.' }
$output = Join-Path $root 'generated\sky_catalogue'
$null = New-Item -ItemType Directory -Force -Path $output
$utf8 = [Text.UTF8Encoding]::new($false)
$entries = @()
$owned = @()
$ownedLicences = @()
$ids = @{}
$specs = @($settings.entries)
foreach ($collection in $settings.collections) {
    foreach ($family in $collection.families) {
        foreach ($index in 1..$family.count) {
            $specs += [pscustomobject]@{ id = $collection.idPrefix + $family.prefix + $index
                label = $family.label + ' ' + $index; context = $family.context
                sourceDirectory = $collection.sourceDirectory; sourcePrefix = $family.prefix + $index
                credit = $collection.credit; licenceFile = $collection.licenceFile; permission = $collection.permission }
        }
    }
}
$excludedEntries = @($settings.excludedEntries)
foreach ($id in $excludedEntries) {
    if (@($specs | Where-Object id -EQ $id).Count -ne 1) { throw "Unknown or ambiguous excluded sky id: $id" }
}
$specs = @($specs | Where-Object { $_.id -notin $excludedEntries })
foreach ($entry in $specs) {
    if ($entry.id -notmatch '^[a-z][a-z0-9_]+$' -or $ids.ContainsKey($entry.id)) { throw 'Invalid or duplicate sky id.' }
    $ids[$entry.id] = $true
    if ($entry.context -notin @('day', 'dusk', 'night', 'overcast')) { throw "Invalid context: $($entry.id)" }
    foreach ($path in $entry.sourceDirectory, $entry.licenceFile) {
        if ([IO.Path]::IsPathRooted($path) -or $path -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe source path: $path" }
    }
    $licence = [IO.File]::ReadAllText((Join-Path $assets $entry.licenceFile))
    if ([string]::IsNullOrWhiteSpace($licence) -or [string]::IsNullOrWhiteSpace($entry.permission)) {
        throw "Missing permission record: $($entry.id)"
    }
    $licencePath = 'data_static\sky_licences\' + $entry.id + '\README.txt'
    foreach ($base in $output, (Join-Path $root 'content')) {
        $destination = Join-Path $base $licencePath
        $source = Join-Path $assets $entry.licenceFile
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        if (-not (Test-Path -LiteralPath $destination) -or
            (Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        if ((Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash) { throw "Sky licence staging mismatch: $destination" }
    }
    $ownedLicences += $licencePath
    $faceInfo = [ordered]@{}
    foreach ($face in 'ft', 'bk', 'lf', 'rt', 'up', 'dn') {
        $sourceFolder = Join-Path $assets $entry.sourceDirectory
        $sourceMaterial = Join-Path $sourceFolder ($entry.sourcePrefix + $face + '.vmt')
        $text = Get-Content -LiteralPath $sourceMaterial -Raw
        $baseTexture = [regex]::Match($text, '(?i)\$basetexture"?\s+"skybox/([a-z0-9_]+)"')
        if (-not $baseTexture.Success) { throw "Unsupported sky texture reference: $sourceMaterial" }
        $source = Join-Path $sourceFolder ($baseTexture.Groups[1].Value + '.vtf')
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 64 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne "VTF`0") {
            throw "Invalid sky texture: $source"
        }
        $width, $height = [BitConverter]::ToUInt16($bytes, 16), [BitConverter]::ToUInt16($bytes, 18)
        if ($width -lt 1 -or $height -lt 1) { throw "Empty sky face: $source" }
        $transform = [regex]::Match($text, '(?i)\$basetexturetransform"?\s+"([^"]+)"')
        $scaleX, $scaleY = 1, 1
        if ($transform.Success) {
            $scale = [regex]::Match($transform.Groups[1].Value, '^center 0\.5 0 scale ([12]) ([12]) rotate 0 translate 0 0$')
            if (-not $scale.Success -or $scale.Groups[1].Value -ne '1') { throw "Unverified sky transform: $sourceMaterial" }
            $scaleX, $scaleY = [int]$scale.Groups[1].Value, [int]$scale.Groups[2].Value
        }
        if ($width * $scaleX -ne $height * $scaleY) { throw "Non-square rendered sky face: $source" }
        $faceInfo[$face] = [ordered]@{ width = $width; height = $height; scaleX = $scaleX; scaleY = $scaleY
            transform = $(if ($transform.Success) { $transform.Groups[1].Value } else { '' })
            source = $source.Substring($assets.Length + 1); sha256 = (Get-FileHash $source).Hash.ToLowerInvariant() }
        $relative = 'materials\zombiesim\skies\' + $entry.id + $face
        $vtf = Join-Path $output ($entry.id + $face + '.vtf')
        Copy-Item -LiteralPath $source -Destination $vtf -Force
        $vmt = Join-Path $output ($entry.id + $face + '.vmt')
        $texture = 'zombiesim/skies/' + $entry.id + $face
        $transformText = if ($transform.Success) { ' "$basetexturetransform" "' + $transform.Groups[1].Value + '"' } else { '' }
        [IO.File]::WriteAllText($vmt, ('"UnlitGeneric" { "$basetexture" "' + $texture + '" "$nofog" "1"' + $transformText + ' }'), $utf8)
        foreach ($extension in 'vtf', 'vmt') {
            $owned += $relative + '.' + $extension
            $built = Join-Path $output ($entry.id + $face + '.' + $extension)
            foreach ($base in (Join-Path $root 'content'), (Resolve-Path (Join-Path $root '..\..')).Path) {
                $destination = Join-Path $base ($relative + '.' + $extension)
                $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
                if (-not (Test-Path -LiteralPath $destination) -or
                    (Get-FileHash $built).Hash -ne (Get-FileHash $destination).Hash) {
                    Copy-Item -LiteralPath $built -Destination $destination -Force
                }
                if ((Get-FileHash $built).Hash -ne (Get-FileHash $destination).Hash) { throw "Sky staging mismatch: $destination" }
            }
        }
    }
    $entries += [ordered]@{ id = $entry.id; label = $entry.label; context = $entry.context
        material = 'zombiesim/skies/' + $entry.id; credit = $entry.credit
        permission = $entry.permission; licence = $licence; licenceFile = $licencePath; faces = $faceInfo }
}
$manifest = [ordered]@{ schemaVersion = 1; entries = $entries; ownedFiles = $owned
    ownedLicenceFiles = $ownedLicences
    excludedEntries = $excludedEntries
    excludedCollections = @($settings.excludedCollections) }
$json = $manifest | ConvertTo-Json -Depth 8
foreach ($base in $output, (Join-Path $root 'content\data_static')) {
    $null = New-Item -ItemType Directory -Force -Path $base
    $path = Join-Path $base 'sky_catalogue.json'
    if (-not (Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path) -ne $json) {
        [IO.File]::WriteAllText($path, $json, $utf8)
    }
}
Write-Host ("Staged {0} permitted sky set(s), {1} owned material files. Uncleared collections untouched." -f $entries.Count, $owned.Count)
