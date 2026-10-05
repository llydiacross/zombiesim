param(
    [string[]]$WorldProfiles = @(),
    [string]$SettingsPath = '',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Stage,
    [switch]$Pack,
    [switch]$Release
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'workshop_packages.psm1') -Force
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$content = Join-Path $root 'content'
if (-not $SettingsPath) { $SettingsPath = Join-Path $root 'workshop-settings.json' }
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
if ($settings.schemaVersion -ne 1 -or $settings.maximumShardBytes -le $settings.metadataReserveBytes -or
    $settings.metadataReserveBytes -lt 65536 -or $settings.maximumShardBytes -gt 1GB) {
    throw 'Invalid Workshop schema/budget. Maximum shard size must not exceed the conservative 1 GiB target.'
}
if ($WorldProfiles.Count -eq 0) { $WorldProfiles = @($settings.worldProfiles) }
if ($WorldProfiles.Count -eq 0 -or @($WorldProfiles | Sort-Object -Unique).Count -ne $WorldProfiles.Count) {
    throw 'Select at least one unique world profile.'
}
$inventory = @{}
$excluded = [Collections.Generic.List[object]]::new()
$blockers = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$snapshots = @{}
function Read-PackageJson([string]$Path) {
    $snapshots[$Path] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Add-Content([string]$Path, [string]$Family, [string]$Group) {
    $key = ConvertTo-WorkshopPath $Path
    if ($inventory.ContainsKey($key)) {
        if ($inventory[$key].family -ne $Family -or $inventory[$key].group -ne $Group) { throw "Conflicting owner for $key" }
        return
    }
    Add-WorkshopFile $inventory (Join-Path $content $Path.Replace('/', '\')) $Path $Family $Group
}

foreach ($directory in 'gamemode', 'entities') {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $directory) -Recurse -File -Filter '*.lua') {
        $relative = $file.FullName.Substring($root.Length + 1)
        if ($file.Name -eq 'sh_distribution.lua') {
            $text = (Get-Content -LiteralPath $file.FullName -Raw).Replace('Distribution.Packaged = false', 'Distribution.Packaged = true')
            Add-WorkshopFile $inventory $file.FullName "gamemodes/zombiesim/$relative" 'core' 'code' $text
        } else { Add-WorkshopFile $inventory $file.FullName "gamemodes/zombiesim/$relative" 'core' 'code' }
    }
}
foreach ($name in 'icon24.png', 'logo.png') {
    Add-WorkshopFile $inventory (Join-Path $root $name) "gamemodes/zombiesim/$name" 'core' 'code'
}
$descriptor = Get-Content -LiteralPath (Join-Path $root 'zombiesim.txt') -Raw
$coreId = Resolve-WorkshopId ([string]$settings.coreWorkshopId) 'core'
$descriptor = [regex]::Replace($descriptor, '("workshopid"\s*")[^"]*(")', ('${1}' + $coreId.id + '${2}'))
Add-WorkshopFile $inventory (Join-Path $root 'zombiesim.txt') 'gamemodes/zombiesim/zombiesim.txt' 'core' 'code' $descriptor
foreach ($name in $settings.coreStaticFiles) {
    if ($name -notmatch '^[\w-]+\.json$') { throw "Invalid static registry name: $name" }
    if ($name -eq 'music_definitions.json') { continue }
    Add-Content "data_static/$name" 'core' 'registries'
}
$musicPath = Join-Path $content 'data_static\music_definitions.json'
$music = Read-PackageJson $musicPath
foreach ($track in $music.tracks) {
    if ($track.file -notmatch '^sounds/music/[\w -]+\.mp3$') { throw "Unexpected source music path: $($track.file)" }
    $original = $track.file
    $track.file = $original -replace '^sounds/', 'sound/'
    Add-WorkshopFile $inventory (Join-Path $content $original.Replace('/', '\')) $track.file 'common' "audio:$($track.id)"
}
Add-WorkshopFile $inventory $musicPath 'data_static/music_definitions.json' 'core' 'registries' ($music | ConvertTo-Json -Depth 8)

$cataloguePath = Join-Path $content 'data_static\clothing_catalogue.json'
$catalogue = Read-PackageJson $cataloguePath
if ($catalogue.schemaVersion -ne 1 -or $catalogue.files.Count -eq 0) { throw 'Invalid or unpublished clothing catalogue.' }
if (-not $catalogue.releaseEligible) { $blockers.Add('Clothing artwork/catalogue is not release-cleared.') }
foreach ($name in $catalogue.files) {
    if ($name -notmatch '^(catalog_[a-f0-9]{16}_[\w]+|pool_\d{2}_(male|female))\.(vtf|vmt)$') {
        throw "Invalid clothing ownership name: $name"
    }
    $group = [IO.Path]::GetFileNameWithoutExtension($name)
    if ($group -match '^(catalog_[a-f0-9]{16})_') { $group = $Matches[1] }
    Add-Content "materials/models/zombiesim/clothing/$name" 'clothing' $group
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $content 'materials\models\zombiesim\clothing') -File) {
    if ($file.Name -match '^(prototype_|equipped_)' -and $file.Name -notmatch '_front_back\.' -and
        $file.Extension -in '.vmt', '.vtf') {
        Add-Content "materials/models/zombiesim/clothing/$($file.Name)" 'clothing' 'sandbox-fixed-clothing'
    }
}
foreach ($directory in $settings.commonMaterialDirectories) {
    $null = ConvertTo-WorkshopPath $directory
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $content $directory) -Recurse -File) {
        if ($file.Extension -in $settings.commonMaterialExtensions) {
            $relative = $file.FullName.Substring($content.Length + 1)
            Add-Content $relative 'common' ([IO.Path]::GetFileNameWithoutExtension($relative))
        }
    }
}
$signs = Read-PackageJson (Join-Path $content 'data_static\zombiesim_signs_preview.json')
foreach ($variant in $signs.variants.PSObject.Properties) {
    foreach ($path in Get-WorkshopModelCompanions $content $variant.Value.model) {
        Add-Content $path 'common' ([IO.Path]::GetFileNameWithoutExtension($variant.Value.model))
    }
}

$externalModels = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($profile in @($WorldProfiles | Sort-Object)) {
    $resolved = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $profile
    $worldPath = Join-Path $root $resolved.Config.runtimeWorldData
    $world = Read-PackageJson $worldPath
    $profileProperty = $world.world.PSObject.Properties['profileId']
    if ($world.schemaVersion -ne 1 -or ($null -ne $profileProperty -and $profileProperty.Value -ne $resolved.Name) -or $world.cells.Count -eq 0) {
        throw "Invalid runtime world for $profile"
    }
    if ($null -eq $profileProperty) { $blockers.Add("Missing explicit runtime profile identity: $profile (legacy export; refresh only in approved release workflow)") }
    Add-Content ("data_static/" + [IO.Path]::GetFileName($worldPath)) 'core' 'registries'
    $maps = @(@($world.cells | ForEach-Object { $_.map }) + @($world.safeZones | ForEach-Object { $_.map }) | Sort-Object -Unique)
    foreach ($map in $maps) {
        if ($map -notmatch '^[\w-]+$') { throw "Invalid world map name: $map" }
        $prefix = if ($world.world.mapDirectory) { "$($world.world.mapDirectory)/" } else { '' }
        $path = "maps/$prefix$map"
        Add-Content "$path.bsp" 'world' "map:$map"
        if (Test-Path -LiteralPath (Join-Path $content "$path.nav".Replace('/', '\'))) {
            Add-Content "$path.nav" 'world' "map:$map"
        } else { $blockers.Add("Missing navigation: $path.nav") }
    }
    $launcher = "zn_$($resolved.Name)_start"
    Add-Content "maps/$launcher.bsp" 'core' "launcher:$launcher"
    if (Test-Path -LiteralPath (Join-Path $content "maps\$launcher.nav")) {
        Add-Content "maps/$launcher.nav" 'core' "launcher:$launcher"
    }
    $mapMaterials = Join-Path $content "materials\worlds\$($resolved.Name)"
    foreach ($directory in 'cells', 'cells_wireframe', 'map_layers') {
        $path = Join-Path $mapMaterials $directory
        if (-not (Test-Path -LiteralPath $path)) {
            $warnings.Add("Map display directory not staged: $profile/$directory")
            continue
        }
        foreach ($file in Get-ChildItem -LiteralPath $path -File -Filter '*.png') {
            if ($directory -eq 'map_layers' -or [IO.Path]::GetFileNameWithoutExtension($file.Name) -in $maps) {
                Add-Content $file.FullName.Substring($content.Length + 1) 'world' "map-display:$profile"
            }
        }
    }
    foreach ($map in @($world.cells.map | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath (Join-Path $mapMaterials "cells\$map.png"))) {
            $blockers.Add("Missing local map image: $profile/$map")
        }
    }
    $skyPath = Join-Path $content "data_static\zombiesim_skybox_$profile.json"
    if (-not (Test-Path -LiteralPath $skyPath)) {
        $blockers.Add("Missing skyline manifest for shipped world: $profile")
        continue
    }
    $sky = Read-PackageJson $skyPath
    if ($sky.schemaVersion -ne 1 -or $sky.profile -ne $profile) { throw "Invalid skyline manifest: $profile" }
    Add-Content "data_static/zombiesim_skybox_$profile.json" 'core' 'registries'
    $skyModels = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($section in 'recipes', 'snow', 'towers') {
        foreach ($recipe in $sky.$section.PSObject.Properties) {
            foreach ($model in @($recipe.Value)) {
                if ($model -isnot [string]) { throw "Invalid skyline model in $profile/$section/$($recipe.Name)" }
                $null = $skyModels.Add($model)
            }
        }
    }
    foreach ($model in $sky.detail.models) {
        if ($model -isnot [string]) { throw "Invalid skyline detail model: $profile" }
        $null = $skyModels.Add($model)
    }
    foreach ($model in $skyModels) {
        if ($model -notlike 'models/zombiesim/*') { $null = $externalModels.Add($model); continue }
        foreach ($path in Get-WorkshopModelCompanions $content $model) { Add-Content $path 'world' "skyline:$model" }
    }
}

foreach ($file in @($inventory.Values | Where-Object { $_.path -like '*.vmt' })) {
    $text = Get-Content -LiteralPath $file.source -Raw
    foreach ($match in [regex]::Matches($text, '"(?:include|\$basetexture|\$bumpmap|\$detail)"\s*"([^"]+)"', 'IgnoreCase')) {
        $reference = $match.Groups[1].Value.Replace('\', '/').ToLowerInvariant()
        if ($reference.StartsWith('materials/')) { $reference = $reference.Substring(10) }
        if ($reference -notlike '*zombiesim*' -or
            $reference -match '^zombiesim_clothing_(pool_\d{2}_v1|(?:equipped_)?(?:male|female)_(?:both|shirt|pants)_v2)$') { continue }
        $dependency = 'materials/' + $reference
        if (-not $dependency.EndsWith('.vmt')) { $dependency += '.vtf' }
        if (-not $inventory.ContainsKey($dependency)) { throw "Unpackaged custom material dependency: $dependency ($($file.path))" }
    }
}
$ownedSources = @{}
foreach ($file in $inventory.Values) { $ownedSources[$file.source] = $true }
foreach ($file in Get-ChildItem -LiteralPath $content -Recurse -File) {
    $relative = ConvertTo-WorkshopPath $file.FullName.Substring($content.Length + 1)
    if (-not $ownedSources.ContainsKey($file.FullName)) {
        $reason = if ($relative -match '/catalog_[a-f0-9]{16}_') { 'unowned-clothing-hash (may be in-flight; report only)' }
            elseif ($relative -like 'maps/*') { 'unreferenced-map-or-development-fixture' }
            else { 'outside-release-allowlist' }
        $excluded.Add([pscustomobject]@{ path = $relative; bytes = $file.Length; reason = $reason })
    }
}
foreach ($path in $snapshots.Keys) {
    if ((Get-FileHash -LiteralPath $path).Hash -ne $snapshots[$path]) { throw "Build inputs changed during inventory: $path. Retry after publication." }
}
if (-not $settings.releaseCleared) { $blockers.Add('Common assets and release provenance have not been signed off.') }
$packs = @(Split-WorkshopPackages @($inventory.Values) ($settings.maximumShardBytes - $settings.metadataReserveBytes))
$identity = @($WorldProfiles | Sort-Object) -join ','
foreach ($file in @($inventory.Values | Sort-Object path)) { $identity += "`n$($file.path):$($file.bytes):$($file.sha256)" }
$toolHash = (Get-FileHash -LiteralPath $PSCommandPath).Hash + (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'workshop_packages.psm1')).Hash
$releaseId = Get-WorkshopTextHash ($identity + "`n" + (Get-Content -LiteralPath $SettingsPath -Raw) + "`n" + $toolHash + "`nrelease=" + [bool]$Release)
$manifest = [ordered]@{ schemaVersion = 1; releaseId = $releaseId; development = -not [bool]$Release;
    profiles = @($WorldProfiles | Sort-Object); packs = @()
    integrityErrors = @($blockers | Where-Object { $_ -like 'Missing *' }) }
$usedWorkshopIds = @{}
foreach ($package in $packs) {
    $idProperty = $settings.workshopIds.PSObject.Properties[$package.id]
    $configuredId = if ($package.id -eq 'core') { [string]$settings.coreWorkshopId } elseif ($null -ne $idProperty) { [string]$idProperty.Value } else { '' }
    $resolvedId = Resolve-WorkshopId $configuredId $package.id
    $workshopId = $resolvedId.id
    if ($workshopId) {
        if ($usedWorkshopIds.ContainsKey($workshopId)) { throw "Duplicate Workshop ID: $workshopId" }
        $usedWorkshopIds[$workshopId] = $true
    }
    if (-not $workshopId) { $blockers.Add("Workshop ID not assigned: $($package.id)") }
    $revisionText = (@($package.files | Sort-Object path | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n")
    $manifest.packs += [ordered]@{ id = $package.id; revision = Get-WorkshopTextHash $revisionText; workshopId = $workshopId
        workshopIdPlaceholder = $resolvedId.placeholder
        files = @($package.files | Sort-Object path | Select-Object path, bytes) }
}
$reportDirectory = Join-Path $root 'generated\workshop'
$report = [ordered]@{ schemaVersion = 1; releaseId = $releaseId; profiles = $manifest.profiles
    maximumShardBytes = $settings.maximumShardBytes; releaseEligible = $blockers.Count -eq 0
    blockers = @($blockers); warnings = @($warnings); excluded = @($excluded)
    externalDependencies = @($settings.externalDependencies); externalModels = @($externalModels | Sort-Object)
    packages = @($packs | ForEach-Object { [ordered]@{ id = $_.id; payloadBytes = $_.bytes; files = @($_.files | Sort-Object path | Select-Object path, bytes, sha256) } })
    staged = $false; packed = $false; compressedUploadBytes = $null }
Write-WorkshopJson (Join-Path $reportDirectory 'inventory-report.json') $report
Write-Host "Inventory: $($inventory.Count) files, $($packs.Count) packages; $($excluded.Count) excluded files (report only), $($blockers.Count) release blockers."
if ($Release -and $blockers.Count -gt 0) { throw "Release blocked. Inspect generated\workshop\inventory-report.json ($($blockers.Count) blockers)." }
if (-not $Stage -and -not $Pack) { return }
$stageRoot = Join-Path $reportDirectory $releaseId.Substring(0, 12)
if (Test-Path -LiteralPath $stageRoot) { throw "Staging destination already exists; preserve it and verify with test_workshop_packages.ps1 -StagedDirectory '$stageRoot'." }
$null = New-Item -ItemType Directory -Path $stageRoot
$gameRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
foreach ($package in $packs) {
    $directory = Join-Path $stageRoot $package.id
    foreach ($file in $package.files) {
        if ((Get-FileHash -LiteralPath $file.source).Hash.ToLowerInvariant() -ne $file.sourceHash) { throw "Source changed before staging: $($file.source)" }
        $destination = Join-Path $directory $file.path.Replace('/', '\')
        if ($destination.Length -ge 260) { throw "Native gmad path exceeds Windows MAX_PATH; use a shorter project root: $destination" }
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        if ($null -ne $file.text) { [IO.File]::WriteAllText($destination, $file.text, [Text.UTF8Encoding]::new($false)) }
        else { Copy-Item -LiteralPath $file.source -Destination $destination }
    }
    $declaration = @($manifest.packs | Where-Object { $_.id -eq $package.id })[0]
    $marker = [ordered]@{ schemaVersion = 1; id = $package.id; revision = $declaration.revision }
    if ($package.id -eq 'core') { $marker.releaseId = $releaseId }
    Write-WorkshopJson (Join-Path $directory "data_static\zombiesim_packages\$($package.id).json") $marker
    Write-WorkshopJson (Join-Path $directory 'addon.json') ([ordered]@{
        title = "ZombieSim $($package.id)"; type = $(if ($package.id -eq 'core') { 'gamemode' } else { 'ServerContent' })
        tags = @('roleplay'); ignore = @() })
    if ($package.id -eq 'core') { Write-WorkshopJson (Join-Path $directory 'data_static\zombiesim_distribution.json') $manifest }
    $metadata = @("data_static/zombiesim_packages/$($package.id).json", 'addon.json')
    if ($package.id -eq 'core') { $metadata += 'data_static/zombiesim_distribution.json' }
    $metadataFiles = @($metadata | ForEach-Object {
        $path = Join-Path $directory $_.Replace('/', '\')
        [pscustomobject]@{ path = $_; bytes = (Get-Item -LiteralPath $path).Length
            sha256 = (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() }
    })
    Test-WorkshopStaging $directory (@($package.files) + $metadataFiles)
    $size = [long]((Get-ChildItem -LiteralPath $directory -Recurse -File | Measure-Object Length -Sum).Sum)
    if ($size -gt $settings.maximumShardBytes) { throw "Staged shard exceeds budget including metadata: $($package.id)" }
    $entry = @($report.packages | Where-Object { $_.id -eq $package.id })[0]
    $entry.stagedBytes = $size
    $entry.metadataFiles = $metadataFiles
    if ($Pack) {
        $gmad = Join-Path $gameRoot 'bin\win64\gmad.exe'
        if (-not (Test-Path -LiteralPath $gmad)) { $gmad = Join-Path $gameRoot 'bin\gmad.exe' }
        if (-not (Test-Path -LiteralPath $gmad)) { throw 'Bundled gmad.exe not found; staging is retained for inspection.' }
        $gma = Join-Path $stageRoot "$($package.id).gma"
        Invoke-WorkshopArchive $gmad $directory $gma (@($package.files) + $metadataFiles) $settings.maximumShardBytes
        $entry.packedBytes = (Get-Item -LiteralPath $gma).Length
        $entry.packedSha256 = (Get-FileHash -LiteralPath $gma).Hash.ToLowerInvariant()
        $entry.extractionVerified = $true
        if ($entry.packedBytes -gt $settings.maximumShardBytes) { throw "Packed GMA exceeds shard budget: $($package.id)" }
    }
}
$report.staged = $true
$report.packed = [bool]$Pack
$report.stageRoot = $stageRoot
Write-WorkshopJson (Join-Path $stageRoot 'package-report.json') $report
Write-WorkshopJson (Join-Path $reportDirectory 'inventory-report.json') $report
Write-Host "Hash-verified $(if ($Release) { 'release' } else { 'development-only' }) packages: $stageRoot. No upload, deletion or installed-file changes."
