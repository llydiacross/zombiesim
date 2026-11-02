[CmdletBinding()]
param(
    [string[]]$SourceDirectory = @('tiletemplates', 'celltemplates'),
    [string]$LedgerPath = 'generated\hammer_assets\staging-ledger.json',
    [switch]$WhatIf
)

# Hammer and the compilers read the engine search paths in gameinfo.txt, not the
# gamemode's content\ folder. Copy every content-owned model and material that an
# authored Hammer source references into the installed garrysmod\ folder.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$contentRoot = Join-Path $projectRoot 'content'
$gameDirectory = Split-Path -Parent (Split-Path -Parent $projectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $gameDirectory 'gameinfo.txt') -PathType Leaf)) {
    throw "Installed Garry's Mod game directory not found: $gameDirectory"
}
if (-not [System.IO.Path]::IsPathRooted($LedgerPath)) { $LedgerPath = Join-Path $projectRoot $LedgerPath }

function Get-NormalizedRelative([string]$path) {
    return ($path.Trim().Replace('/', '\').TrimStart('\')).ToLowerInvariant()
}

function Get-ContentFile([string]$relative) {
    $full = Join-Path $contentRoot $relative
    if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    return $null
}

function Read-MdlMaterials([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 220 -or [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'IDST') {
        throw "Not a studio model: $path"
    }
    $readString = {
        param([int]$offset)
        $end = $offset
        while ($end -lt $bytes.Length -and $bytes[$end] -ne 0) { $end++ }
        [System.Text.Encoding]::ASCII.GetString($bytes, $offset, $end - $offset)
    }
    $textureCount = [BitConverter]::ToInt32($bytes, 204)
    $textureIndex = [BitConverter]::ToInt32($bytes, 208)
    $cdCount = [BitConverter]::ToInt32($bytes, 212)
    $cdIndex = [BitConverter]::ToInt32($bytes, 216)
    $names = for ($i = 0; $i -lt $textureCount; $i++) {
        $entry = $textureIndex + $i * 64
        & $readString ($entry + [BitConverter]::ToInt32($bytes, $entry))
    }
    $directories = for ($i = 0; $i -lt $cdCount; $i++) {
        & $readString ([BitConverter]::ToInt32($bytes, $cdIndex + $i * 4))
    }
    foreach ($directory in @($directories)) {
        foreach ($name in @($names)) { Get-NormalizedRelative "materials\$directory$name.vmt" }
    }
}

$files = [System.Collections.Generic.HashSet[string]]::new()
$referencedModels = [System.Collections.Generic.HashSet[string]]::new()
$referencedMaterials = [System.Collections.Generic.HashSet[string]]::new()

$sources = foreach ($directory in $SourceDirectory) {
    $root = if ([System.IO.Path]::IsPathRooted($directory)) { $directory } else { Join-Path $projectRoot $directory }
    Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.vmf', '*.vmx'
}
foreach ($source in @($sources)) {
    foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($source.FullName),
            '"(?:model|material)"\s+"([^"]+)"', 'IgnoreCase')) {
        $value = Get-NormalizedRelative $match.Groups[1].Value
        if ($value.EndsWith('.mdl')) { [void]$referencedModels.Add($value) }
        elseif ($value) { [void]$referencedMaterials.Add("materials\$value.vmt") }
    }
}

$materialQueue = [System.Collections.Generic.Queue[string]]::new()
$stagedModels = 0
foreach ($model in $referencedModels) {
    $mdl = Get-ContentFile $model
    if (-not $mdl) { continue }
    $stagedModels++
    $base = $model.Substring(0, $model.Length - 4)
    foreach ($extension in '.mdl', '.vvd', '.phy', '.ani', '.dx80.vtx', '.dx90.vtx', '.sw.vtx', '.vtx') {
        if (Get-ContentFile "$base$extension") { [void]$files.Add("$base$extension") }
    }
    foreach ($vmt in Read-MdlMaterials $mdl) { $materialQueue.Enqueue($vmt) }
}
foreach ($vmt in $referencedMaterials) { $materialQueue.Enqueue($vmt) }

$visited = [System.Collections.Generic.HashSet[string]]::new()
while ($materialQueue.Count -gt 0) {
    $vmt = $materialQueue.Dequeue()
    if (-not $visited.Add($vmt)) { continue }
    $vmtPath = Get-ContentFile $vmt
    if (-not $vmtPath) { continue }
    [void]$files.Add($vmt)
    foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($vmtPath), '"?(\$?[A-Za-z0-9_]+)"?\s+"([^"]+)"')) {
        $key = $match.Groups[1].Value.ToLowerInvariant()
        $value = Get-NormalizedRelative $match.Groups[2].Value
        if ($key -eq 'include') {
            $materialQueue.Enqueue($value)
        } elseif ($key.StartsWith('$')) {
            $relative = $value -replace '\.vtf$', ''
            $texture = "materials\$relative.vtf"
            if (Get-ContentFile $texture) { [void]$files.Add($texture) }
        }
    }
}

$ledger = @{}
if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
    foreach ($entry in @((Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json).files)) {
        $ledger[[string]$entry.path] = $entry
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$refused = [System.Collections.Generic.List[string]]::new()
$copied = 0
foreach ($relative in @($files | Sort-Object)) {
    $source = Join-Path $contentRoot $relative
    $destination = Join-Path $gameDirectory $relative
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $existed = Test-Path -LiteralPath $destination -PathType Leaf
    $owned = $ledger.ContainsKey($relative) -and [bool]$ledger[$relative].owned
    $state = 'current'
    if ($existed) {
        $current = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($current -ne $hash) {
            $ledgerHash = if ($ledger.ContainsKey($relative)) { [string]$ledger[$relative].sha256 } else { '' }
            if (-not $owned -or $current -ne $ledgerHash) {
                $refused.Add($relative)
                continue
            }
            $state = 'updated'
        }
    } else {
        $state = 'created'
        $owned = $true
    }
    if ($state -ne 'current' -and -not $WhatIf) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash) {
            throw "Hammer asset staging hash mismatch: $destination"
        }
        $copied++
    }
    $results.Add([pscustomobject]@{ path = $relative; sha256 = $hash; owned = $owned; state = $state })
}

if (-not $WhatIf) {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LedgerPath)
    [pscustomobject]@{
        gameDirectory = $gameDirectory
        sourceDirectories = @($SourceDirectory)
        files = @($results)
        refused = @($refused)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $LedgerPath -Encoding UTF8
}
Write-Host ("Hammer assets: {0} referenced content models, {1} files ({2} copied, {3} already current). Ledger: {4}" -f
    $stagedModels, $results.Count, $copied, @($results | Where-Object state -eq 'current').Count, $LedgerPath)
if ($refused.Count -gt 0) {
    Write-Warning "Refused to overwrite $($refused.Count) differing engine file(s) not owned by this ledger:"
    $refused | ForEach-Object { Write-Warning "  $_" }
    exit 1
}
