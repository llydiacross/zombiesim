param([switch]$PlanOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_catalogue.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'clothing_fabrics.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$null = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$art = Join-Path $root 'assets\clothing'
$settings = Get-Content (Join-Path $art 'catalogue.json') -Raw | ConvertFrom-Json
$plan = Get-ClothingCataloguePlan $art $settings
$fabricSettings = Get-Content (Join-Path $art 'fabrics.json') -Raw | ConvertFrom-Json
$fabrics = @(Get-ClothingFabricPlan $fabricSettings $settings)
if ($plan.variants.Count + $fabrics.Count -gt $settings.maximumVariants) { throw 'Combined image/fabric catalogue exceeds variant budget.' }
$plan | Add-Member -NotePropertyName fabrics -NotePropertyValue $fabrics
$output = Join-Path $root 'generated\clothing_preview\catalogue'
$null = New-Item -ItemType Directory -Force -Path $output
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $output 'plan.json'), ($plan | ConvertTo-Json -Depth 8), $utf8)
if ($PlanOnly) { Write-Host "Planned $($plan.families.Count) image families / $($plan.variants.Count) image and $($fabrics.Count) fabric variants; no staging."; return }
& (Join-Path $PSScriptRoot 'inspect_clothing_models.ps1') -UvGuideModels @('models/player/group01/male_03.mdl', 'models/player/group01/female_01.mdl')
$prototype = Get-Content (Join-Path $art 'prototype.json') -Raw
$printSource = Get-Content (Join-Path $art 'prints.json') -Raw
$sha = [Security.Cryptography.SHA256]::Create()
$finishes = [ordered]@{}
$items = [ordered]@{}
$files = [Collections.Generic.HashSet[string]]::new()
$destinations = @((Join-Path $root 'content\materials\models\zombiesim\clothing'),
    (Join-Path $root '..\..\materials\models\zombiesim\clothing'))
$cataloguePaths = @((Join-Path $root 'content\data_static\clothing_catalogue.json'),
    (Join-Path $root '..\..\data_static\clothing_catalogue.json'))
$previous = if (Test-Path -LiteralPath $cataloguePaths[0]) {
    Get-Content -LiteralPath $cataloguePaths[0] -Raw | ConvertFrom-Json
} else { $null }
if ($null -ne $previous) {
    foreach ($name in $previous.files) {
        if ($name -notmatch '^catalog_[a-f0-9]{16}_[a-z_]+\.(vtf|vmt)$' -and $name -notmatch '^pool_[0-9]{2}_(male|female)\.vmt$') {
            throw "Unsafe previous catalogue file ownership entry: $name"
        }
    }
}
function Test-ClothingBuiltLayers([string]$Prefix, [string[]]$Names) {
    foreach ($name in $Names) {
        if (-not (Test-Path -LiteralPath (Join-Path $root "generated\clothing_preview\$Prefix\source\$name.png"))) { return $false }
        foreach ($extension in 'vtf', 'vmt') {
            $filename = "$name.$extension"
            $built = Join-Path $root "generated\clothing_preview\$Prefix\game\materials\models\zombiesim\clothing\$filename"
            if (-not (Test-Path -LiteralPath $built -PathType Leaf)) { return $false }
            $hash = (Get-FileHash -LiteralPath $built).Hash
            foreach ($destination in $destinations) {
                $staged = Join-Path $destination $filename
                if (-not (Test-Path -LiteralPath $staged -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $staged).Hash -ne $hash) { return $false }
            }
        }
    }
    return $true
}
try {
    foreach ($variant in $plan.variants) {
        $family = $plan.families | Where-Object identity -eq $variant.family
        $design = $prototype | ConvertFrom-Json
        $prints = $printSource | ConvertFrom-Json
        $design.shirt.pattern = 'solid'
        $design.pants.pattern = 'solid'
        $design.($variant.garment).color = $variant.background
        $prints.image = $variant.source
        $signature = 'back-projection-v2-thigh-v1|' + $family.sha256 + '|' + $variant.garment + '|' + $variant.background + '|' +
            $variant.style + '|' + $prototype + '|' + $printSource
        if ($variant.style -like 'pants_cuff*') {
            $signature += '|cuff-bottom-v1|' + (Get-Content -LiteralPath (Join-Path $art 'pants_cuffs.json') -Raw)
        }
        if ($variant.style -match '^(pants|arm)_back_') {
            $signature += '|rear-limbs-v1|' + (Get-Content -LiteralPath (Join-Path $art 'rear_limbs.json') -Raw)
        }
        $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature)))).Replace('-', '').ToLowerInvariant()
        $prefix = 'catalog_' + $hash.Substring(0, 16)
        $garments = if ($variant.garment -eq 'shirt') { @('shirt_male', 'shirt_female') }
            elseif ($variant.style -like 'pants_*') { @('pants_male', 'pants_female') } else { @('pants') }
        $names = @($garments | ForEach-Object { "${prefix}_${_}_$($variant.style)" })
        if ($variant.style -eq 'back_full') { $names += "${prefix}_shirt_back_full_icon" }
        $reusable = $null -ne $previous -and $null -ne $previous.finishes.PSObject.Properties[$variant.id] -and
            $previous.finishes.($variant.id).layers.male.StartsWith("models/zombiesim/clothing/${prefix}_") -and
            (Test-ClothingBuiltLayers $prefix $names)
        if (-not $reusable) {
            & (Join-Path $PSScriptRoot 'build_clothing_prototype.ps1') -DefinitionData $design -PrintData $prints `
                -AssetPrefix $prefix -OnlyGarments $garments -PrintStyles @($variant.style) -PrintOnly -SkipNativePatches
        }
        $layers = [ordered]@{}
        foreach ($sex in 'male', 'female') {
            $garment = if ($variant.garment -eq 'shirt') { 'shirt_' + $sex }
                elseif ($variant.style -like 'pants_*') { 'pants_' + $sex } else { 'pants' }
            $name = $prefix + '_' + $garment + '_' + $variant.style
            $layers[$sex] = 'models/zombiesim/clothing/' + $name
            foreach ($extension in 'vtf', 'vmt') { $null = $files.Add($name + '.' + $extension) }
        }
        $finishes[$variant.id] = [ordered]@{ garment = $variant.garment; layers = $layers;
            source = $variant.source; sourceHash = $family.sha256; colour = $variant.colour; style = $variant.style;
            artworkTone = $variant.artworkTone;
            icon = Get-ClothingCatalogueIcon $variant.garment $variant.style $prints }
        if ($variant.style -eq 'back_full') {
            $iconName = $prefix + '_shirt_back_full_icon'
            $icon = Get-ClothingCatalogueIcon shirt repeat $prints
            $icon.female = $icon.male
            $icon.layer = 'models/zombiesim/clothing/' + $iconName
            $finishes[$variant.id].icon = $icon
            foreach ($extension in 'vtf', 'vmt') { $null = $files.Add($iconName + '.' + $extension) }
        }
        $items[$variant.itemId] = [ordered]@{
            name = (($family.family -replace '_', ' ') + ' ' + $variant.garment + ' / ' + $variant.colour + ' / ' + ($variant.style -replace '_', ' '))
            entityClass = 'clothing'; clothing = @{ garment = $variant.garment; finish = $variant.id };
            thumbnail = $variant.itemId; value = 25; maxStack = 1; lootCategory = 'other'
        }
    }
    foreach ($fabric in $fabrics) {
        if ($finishes.Contains($fabric.id) -or $items.Contains($fabric.itemId)) { throw "Fabric/image catalogue identity collision: $($fabric.id)" }
        $design = $prototype | ConvertFrom-Json
        $garment = $design.($fabric.garment)
        foreach ($name in 'pattern', 'color', 'stripeColor', 'stripeSpacing', 'stripeWidth') { $garment.$name = $fabric.design.$name }
        if ($fabric.style -eq 'tie_dye') { $garment | Add-Member -NotePropertyName tieDye -NotePropertyValue $fabric.design.tieDye -Force }
        $garment.image = ''
        $garment.logo.image = ''
        $garment.logo.text = ''
        $signature = 'original-fabric-v3-back-projection-v1|' + ($design | ConvertTo-Json -Depth 12 -Compress)
        $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature)))).Replace('-', '').ToLowerInvariant()
        $prefix = 'catalog_' + $hash.Substring(0, 16)
        $garments = if ($fabric.garment -eq 'shirt') { @('shirt_male', 'shirt_female') } else { @('pants') }
        $reusable = $null -ne $previous -and $null -ne $previous.finishes.PSObject.Properties[$fabric.id] -and
            $previous.finishes.($fabric.id).sourceHash -eq $hash
        if ($reusable) { $reusable = Test-ClothingBuiltLayers $prefix @($garments | ForEach-Object { "${prefix}_$_" }) }
        if (-not $reusable) {
            & (Join-Path $PSScriptRoot 'build_clothing_prototype.ps1') -DefinitionData $design `
                -AssetPrefix $prefix -OnlyGarments $garments -BaseOnly -SkipNativePatches
        }
        $layers = [ordered]@{}
        foreach ($sex in 'male', 'female') {
            $name = $prefix + '_' + $(if ($fabric.garment -eq 'shirt') { 'shirt_' + $sex } else { 'pants' })
            $layers[$sex] = 'models/zombiesim/clothing/' + $name
            foreach ($extension in 'vtf', 'vmt') { $null = $files.Add($name + '.' + $extension) }
        }
        $finishes[$fabric.id] = [ordered]@{ garment = $fabric.garment; layers = $layers; source = '';
            sourceHash = $hash; colour = $fabric.colour; style = $fabric.style; artworkTone = $null; fabric = $true;
            icon = Get-ClothingCatalogueIcon $fabric.garment repeat ($printSource | ConvertFrom-Json) }
        $treatment = $fabric.design.id -replace ('^' + $fabric.garment + '_'), ''
        $treatment = $treatment -replace ('^' + $fabric.colour + '_'), ''
        $finishes[$fabric.id].treatment = $treatment
        $items[$fabric.itemId] = [ordered]@{ name = 'Original fabric ' + $fabric.garment + ' / ' + $fabric.colour + ' / ' + ($treatment -replace '_', ' ');
            entityClass = 'clothing'; clothing = @{ garment = $fabric.garment; finish = $fabric.id };
            thumbnail = $fabric.itemId; value = 25; maxStack = 1; lootCategory = 'other' }
    }
} finally { $sha.Dispose() }
foreach ($slot in 1..16) {
    $number = $slot.ToString('00')
    foreach ($sex in 'male', 'female') {
        $name = "pool_${number}_$sex.vmt"
        $text = @"
"Patch"
{
    "include" "materials/models/humans/$sex/group01/players_sheet.vmt"
    "replace" { "`$basetexture" "zombiesim_clothing_pool_${number}_v1" }
}
"@
        foreach ($directory in $destinations) {
            $null = New-Item -ItemType Directory -Force -Path $directory
            [IO.File]::WriteAllText((Join-Path $directory $name), $text, $utf8)
        }
        $null = $files.Add($name)
    }
}
foreach ($name in $files) {
    $first = Get-FileHash -LiteralPath (Join-Path $destinations[0] $name)
    if ($first.Hash -ne (Get-FileHash -LiteralPath (Join-Path $destinations[1] $name)).Hash) { throw "Catalogue staging mismatch: $name" }
}
$manifest = [ordered]@{ schemaVersion = 1; capacity = 16; releaseEligible = $false;
    provenance = $plan.provenance; finishes = $finishes; items = $items; files = @($files | Sort-Object) }
$json = $manifest | ConvertTo-Json -Depth 10
foreach ($path in $cataloguePaths) {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    [IO.File]::WriteAllText($path, $json, $utf8)
}
if ($null -ne $previous) {
    foreach ($name in $previous.files) {
        if (-not $files.Contains($name)) {
            foreach ($directory in $destinations) {
                $path = Join-Path $directory $name
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            }
        }
    }
}
Write-Host "Built $($finishes.Count) clean wearable finishes; staged $($files.Count) owned files and catalogue metadata. Not release-cleared."
