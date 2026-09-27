param(
    [string]$GameRoot = '',
    [string]$VpkExe = '',
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'mounted_asset_catalog.psm1') -Force

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
if ([string]::IsNullOrWhiteSpace($VpkExe)) {
    $VpkExe = Join-Path $GameRoot 'bin\vpk.exe'
}
if (-not (Test-Path -LiteralPath $VpkExe -PathType Leaf)) {
    throw "VPK listing tool not found: $VpkExe"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'generated\asset_catalog\mounted_asset_catalog.json'
}

$archiveRoots = [System.Collections.Generic.List[object]]::new()
$garrysmodRoot = Join-Path $GameRoot 'garrysmod'
$sourceEngineRoot = Join-Path $GameRoot 'sourceengine'
foreach ($root in @(
    [pscustomobject]@{ path = $garrysmodRoot; label = 'garrysmod'; mounted = $true },
    [pscustomobject]@{ path = $sourceEngineRoot; label = 'sourceengine'; mounted = $true }
)) {
    if (Test-Path -LiteralPath $root.path -PathType Container) {
        $archiveRoots.Add($root)
    }
}

$mountConfig = Join-Path $garrysmodRoot 'cfg\mount.cfg'
if (Test-Path -LiteralPath $mountConfig -PathType Leaf) {
    $mountIndex = 0
    foreach ($line in Get-Content -LiteralPath $mountConfig) {
        if ($line -match '^\s*"(?<name>[^"]+)"\s+"(?<path>[^"]+)"') {
            $mountIndex++
            $mountName = $Matches.name
            $mountedPath = $Matches.path
            if (-not [System.IO.Path]::IsPathRooted($mountedPath)) {
                $mountedPath = Join-Path $garrysmodRoot $mountedPath
            }
            if (Test-Path -LiteralPath $mountedPath -PathType Container) {
                $archiveRoots.Add([pscustomobject]@{
                    path = (Resolve-Path -LiteralPath $mountedPath).Path
                    label = ('mountcfg/{0}-{1}' -f $mountIndex, $mountName)
                    mounted = $true
                })
            }
        }
    }
}

$archives = @{}
foreach ($root in $archiveRoots) {
    foreach ($archive in Get-ChildItem -LiteralPath $root.path -Filter '*_dir.vpk' -File -Recurse) {
        $fullPath = $archive.FullName
        $isMounted = [bool]$root.mounted -and $fullPath -notmatch '(?i)(^|[\\/])[^\\/]*\.disabled([\\/]|$)'
        $relativePath = $fullPath.Substring($root.path.Length).TrimStart('\', '/').Replace('\', '/')
        $source = '{0}/{1}' -f $root.label, $relativePath
        if (-not $archives.ContainsKey($fullPath)) {
            $archives[$fullPath] = [pscustomobject]@{
                path = $fullPath
                source = $source
                mounted = $isMounted
            }
        } elseif ($isMounted) {
            $archives[$fullPath].mounted = $true
        }
    }
}
if ($archives.Count -eq 0) {
    throw "No *_dir.vpk archives found under $garrysmodRoot, $sourceEngineRoot, or configured mount.cfg paths."
}

$itemDefinitionsPath = Join-Path $repoRoot 'content\data_static\item_definitions.json'
$itemData = Get-Content -LiteralPath $itemDefinitionsPath -Raw | ConvertFrom-Json
$entityLootPath = Join-Path $repoRoot 'content\data_static\entity_loot.json'
$entityLootData = Get-Content -LiteralPath $entityLootPath -Raw | ConvertFrom-Json
$references = [System.Collections.Generic.List[object]]::new()
$referencedModels = @{}
foreach ($itemProperty in $itemData.items.PSObject.Properties) {
    foreach ($field in @('iconModel', 'worldModel', 'viewModel')) {
        $modelProperty = $itemProperty.Value.PSObject.Properties[$field]
        if (-not $modelProperty) {
            continue
        }
        $model = $modelProperty.Value
        if (-not [string]::IsNullOrWhiteSpace([string]$model)) {
            $references.Add([pscustomobject]@{
                itemId = $itemProperty.Name
                usage = $field
                model = $model
            })
            $canonical = ConvertTo-CatalogModelPath ([string]$model)
            if ($canonical) {
                $referencedModels[$canonical] = $true
            }
        }
    }
}
for ($index = 0; $index -lt $entityLootData.rules.Count; $index++) {
    $model = $entityLootData.rules[$index].model
    $references.Add([pscustomobject]@{
        itemId = ('entity_loot[{0}]' -f ($index + 1))
        usage = 'entityLootModel'
        model = $model
    })
    $canonical = ConvertTo-CatalogModelPath ([string]$model)
    if ($canonical) {
        $referencedModels[$canonical] = $true
    }
}
$references.Add([pscustomobject]@{
    itemId = 'default'
    usage = 'fallbackIcon'
    model = 'models/props_junk/cardboard_box004a.mdl'
})
$referencedModels['models/props_junk/cardboard_box004a.mdl'] = $true

$archiveEntries = [System.Collections.Generic.List[object]]::new()
$archivePaths = @($archives.Keys | Sort-Object)
foreach ($archivePath in $archivePaths) {
    $archive = $archives[$archivePath]
    Write-Output "Scanning $($archive.source)"
    $listedPaths = & $VpkExe l $archive.path
    if ($LASTEXITCODE -ne 0) {
        throw "vpk.exe failed with exit code $LASTEXITCODE while listing $($archive.path)"
    }
    foreach ($listedPath in $listedPaths) {
        $model = ConvertTo-CatalogModelPath ([string]$listedPath)
        if ($model -and ((Test-CatalogCandidateModel $model) -or $referencedModels.ContainsKey($model))) {
            $archiveEntries.Add([pscustomobject]@{
                model = $model
                sourceArchive = $archive.source
                mounted = $archive.mounted
            })
        }
    }
}

$models = Merge-CatalogModelEntries -ArchiveEntries @($archiveEntries) -References @($references)
$mountedCount = @($models | Where-Object mounted).Count
$catalog = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    archivesScanned = $archivePaths.Count
    modelCount = $models.Count
    mountedModelCount = $mountedCount
    models = $models
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$catalog | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Catalog models: $($models.Count); mounted: $mountedCount; unmounted/missing: $($models.Count - $mountedCount); archives: $($archivePaths.Count); output: $OutputPath"
