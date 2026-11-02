[CmdletBinding()]
param(
    [string[]]$Tile = @(),
    [string]$CellDirectory = '',
    [string[]]$MapFilename = @(),
    [int]$PlaneBudget = 0,
    [string]$WorkDirectory = '',
    [string]$ReportPath = '',
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [switch]$FailOnRecommendation
)

# Measures each tile's standalone VBSP plane count and recommends converting over-budget tiles
# with build_tile_detail_models.ps1. Brush-side counts do not predict VBSP planes (bevels and
# splits dominate), so this compiles every changed tile once and caches by source hash.
# Exit 0: all within budget. Exit 2 with -FailOnRecommendation: at least one recommendation.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$tileRoot = Join-Path $root 'tiletemplates'
$mapPlaneLimit = 65536
# Calibrated 2026-11-01: the largest ordinary tile measured 2,002 planes and the largest whole cells ~5,500 (map limit 65,536).
if ($PlaneBudget -le 0) { $PlaneBudget = 8192 }
if ([string]::IsNullOrWhiteSpace($WorkDirectory)) { $WorkDirectory = Join-Path $root 'generated\tile_detail_budget' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $WorkDirectory 'report.json' }
$sourceDirectory = Join-Path $WorkDirectory 'src'
$buildDirectory = Join-Path $WorkDirectory 'build'
$cachePath = Join-Path $WorkDirectory 'cache.json'
$utf8 = [Text.UTF8Encoding]::new($false)
$configPath = Join-Path $root 'tiletemplates_modelsrc\detail_models.json'
$converted = @{}
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    foreach ($entry in @((Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json).tiles)) {
        $converted[([string]$entry.tile).Replace('/', '\').ToLowerInvariant()] = [string]$entry.name
    }
}

function Get-InstanceFiles([string]$vmfPath) {
    $directory = Split-Path -Parent $vmfPath
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vmfPath), '(?m)^\s*"file" "([^"]+\.vmf)"')) {
        [IO.Path]::GetFullPath((Join-Path $directory $match.Groups[1].Value.Replace('/', '\')))
    }
}

function Get-SourceHash([string]$vmfPath) {
    $seen = @{}
    $hashes = [Collections.Generic.List[string]]::new()
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue([IO.Path]::GetFullPath($vmfPath))
    while ($queue.Count -gt 0) {
        $path = $queue.Dequeue()
        if ($seen.ContainsKey($path)) { continue }
        $seen[$path] = $true
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing VMF dependency: $path" }
        $hashes.Add((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)
        foreach ($instance in @(Get-InstanceFiles $path)) { $queue.Enqueue($instance) }
    }
    $bytes = $utf8.GetBytes(($hashes -join '|'))
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
}

function Get-BspPlaneCount([string]$bspPath) {
    $stream = [IO.File]::OpenRead($bspPath)
    try {
        $header = New-Object byte[] 32
        if ($stream.Read($header, 0, 32) -ne 32 -or [Text.Encoding]::ASCII.GetString($header, 0, 4) -ne 'VBSP') { throw "Not a BSP: $bspPath" }
        # Lump 1 (planes) descriptor follows the 8-byte header and lump 0; dplane_t is 20 bytes.
        return [int]([BitConverter]::ToInt32($header, 28) / 20)
    } finally { $stream.Dispose() }
}

# Choose tiles: explicit list, tiles referenced by selected cells, or every tile template.
$tiles = [Collections.Generic.List[string]]::new()
if ($Tile.Count -gt 0) {
    foreach ($path in $Tile) { $tiles.Add((Resolve-Path -LiteralPath $path).Path) }
} elseif (-not [string]::IsNullOrWhiteSpace($CellDirectory)) {
    $cells = if ($MapFilename.Count -gt 0) { @($MapFilename | ForEach-Object { Join-Path $CellDirectory $_ }) } else { @(Get-ChildItem -LiteralPath $CellDirectory -Filter '*.vmf' -File | ForEach-Object FullName) }
    $set = @{}
    foreach ($cell in $cells) {
        foreach ($instance in @(Get-InstanceFiles $cell)) {
            if ($instance.StartsWith($tileRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and -not $set.ContainsKey($instance)) {
                $set[$instance] = $true; $tiles.Add($instance)
            }
        }
    }
} else {
    foreach ($file in Get-ChildItem -LiteralPath $tileRoot -Recurse -Filter '*.vmf' -File) { $tiles.Add($file.FullName) }
}
if ($tiles.Count -eq 0) { throw 'No tiles were selected for the detail budget check.' }

$cache = @{}
if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    foreach ($property in (Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json).PSObject.Properties) { $cache[$property.Name] = $property.Value }
}
[IO.Directory]::CreateDirectory($sourceDirectory) | Out-Null
[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null

$pending = [Collections.Generic.List[object]]::new()
$records = [Collections.Generic.List[object]]::new()
foreach ($path in $tiles) {
    if (-not $path.StartsWith($tileRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Tile is outside tiletemplates: $path" }
    $relative = $path.Substring($tileRoot.Length + 1)
    $key = $relative.ToLowerInvariant()
    $hash = Get-SourceHash $path
    # Short names: VBSP rejects env_cubemap patch material paths longer than 128 characters.
    $keyHash = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($utf8.GetBytes($key))) -replace '-', ''
    $map = 'zz_tb_' + $keyHash.Substring(0, 12).ToLowerInvariant() + '.vmf'
    $record = [pscustomobject]@{ tile = "tiletemplates\$relative"; key = $key; hash = $hash; map = $map; planes = $null; status = $null; reason = $null }
    $records.Add($record)
    $hit = $cache[$key]
    if ($null -ne $hit -and $hit.hash -ceq $hash) {
        $record.planes = $hit.planes; $record.status = $hit.status
        if ($hit.PSObject.Properties['reason']) { $record.reason = $hit.reason }
        continue
    }
    $wrapper = @('versioninfo', '{', '	"editorversion" "400"', '	"mapversion" "1"', '	"formatversion" "100"', '	"prefab" "0"', '}',
        'world', '{', '	"id" "1"', '	"mapversion" "1"', '	"classname" "worldspawn"', '	"skyname" "sky_day01_01"', '}',
        'entity', '{', '	"id" "2"', '	"classname" "func_instance"', '	"angles" "0 0 0"',
        ('	"file" "{0}"' -f ('..\..\..\tiletemplates\' + $relative).Replace('\', '/')), '	"targetname" "zm_budget"',
        '	"fixup_style" "0"', '	"origin" "0 0 0"', '}') -join "`r`n"
    $wrapperPath = Join-Path $sourceDirectory $map
    if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf) -or [IO.File]::ReadAllText($wrapperPath) -cne $wrapper) {
        [IO.File]::WriteAllText($wrapperPath, $wrapper, $utf8)
    }
    $pending.Add($record)
    Remove-Item -LiteralPath (Join-Path $buildDirectory ($map -replace '\.vmf$', '.bsp')) -ErrorAction SilentlyContinue
}

if ($pending.Count -gt 0) {
    Write-Host ("Measuring standalone VBSP planes for {0} changed tile(s); {1} cached." -f $pending.Count, ($records.Count - $pending.Count))
    $compileArguments = @{
        SourceDirectory = $sourceDirectory; BuildDirectory = $buildDirectory; WorldProfile = $WorldProfile
        MapFilename = @($pending | ForEach-Object map); VBSPOnly = $true; Force = $true
    }
    if ($SettingsPath) { $compileArguments.SettingsPath = $SettingsPath }
    # Wrapper maps are unsealed, so VBSP leak warnings are expected; only the plane lump matters here.
    # Individual failures are attributed per tile below, so the pool's aggregate failure is not fatal.
    try { & (Join-Path $PSScriptRoot 'compile_cell_vmfs.ps1') @compileArguments | Out-Null } catch { Write-Verbose $_.Exception.Message }
    foreach ($record in $pending) {
        $bsp = Join-Path $buildDirectory ($record.map -replace '\.vmf$', '.bsp')
        $log = Join-Path $buildDirectory ('logs\' + ($record.map -replace '\.vmf$', '.vbsp.log'))
        $logText = if (Test-Path -LiteralPath $log -PathType Leaf) { [IO.File]::ReadAllText($log) } else { '' }
        if ($logText -match 'MAX_MAP_PLANES') {
            $record.planes = $mapPlaneLimit; $record.status = 'exceeds-map-limit'
        } elseif (Test-Path -LiteralPath $bsp -PathType Leaf) {
            $record.planes = Get-BspPlaneCount $bsp; $record.status = 'measured'
        } else {
            $record.planes = $null; $record.status = 'vbsp-failed'
            $record.reason = if ($logText -match 'Brush (\d+): bounds out of range') {
                "brush $($Matches[1]) has bounds out of range (the map would not load)"
            } elseif ($logText -match 'Displacement \d+ has bad geometry near ([^\r\n]+)') {
                "a displacement has bad geometry near $($Matches[1].Trim()) (VBSP cannot build its physics)"
            } else { 'see the VBSP log' }
        }
        $cache[$record.key] = [pscustomobject]@{ hash = $record.hash; planes = $record.planes; status = $record.status; reason = $record.reason }
    }
    $ordered = [ordered]@{}
    foreach ($name in ($cache.Keys | Sort-Object)) { $ordered[$name] = $cache[$name] }
    [IO.File]::WriteAllText($cachePath, ($ordered | ConvertTo-Json -Depth 4), $utf8)
}

$recommendations = [Collections.Generic.List[object]]::new()
foreach ($record in $records) {
    if ($record.status -eq 'vbsp-failed' -or $null -eq $record.planes -or $record.planes -le $PlaneBudget) { continue }
    $isConverted = $converted.ContainsKey($record.key)
    $recommendations.Add([pscustomobject]@{
        tile = $record.tile; planes = $record.planes; budget = $PlaneBudget; status = $record.status; alreadyConverted = $isConverted
        recommendation = if ($isConverted) {
            "Already a detail-model tile but still over budget: move more of its geometry into func_detail in tiletemplates_modelsrc\$($record.key), then rerun build_tile_detail_models.ps1."
        } else {
            "Convert its func_detail brushes to a static model: move the VMF/VMX to tiletemplates_modelsrc\$($record.key), add it to tiletemplates_modelsrc\detail_models.json, then run .\bin\build_tile_detail_models.ps1. To keep brushes instead, simplify the tile and rerun this check."
        }
    })
}
$failed = @($records | Where-Object status -eq 'vbsp-failed')
$report = [pscustomobject]@{
    schema = 1; generatedUtc = [DateTime]::UtcNow.ToString('o'); planeBudget = $PlaneBudget; mapPlaneLimit = $mapPlaneLimit
    tileCount = $records.Count; recommendations = @($recommendations); vbspFailures = @($failed | ForEach-Object tile)
    tiles = @($records | Sort-Object { if ($null -eq $_.planes) { -1 } else { $_.planes } } -Descending | Select-Object tile, planes, status, reason, map)
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $ReportPath)) | Out-Null
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 5), $utf8)

foreach ($item in $failed) { Write-Warning "Tile detail budget: VBSP could not compile $($item.tile) standalone: $($item.reason). Log: $buildDirectory\logs\$($item.map -replace '\.vmf$', '.vbsp.log')" }
foreach ($item in $recommendations) {
    Write-Warning ("Tile detail budget: {0} compiles to {1} planes standalone (budget {2}, map limit {3}). {4}" -f $item.tile, $item.planes, $PlaneBudget, $mapPlaneLimit, $item.recommendation)
}
Write-Host ("Tile detail budget: {0} tile(s) checked, {1} over the {2}-plane budget. Report: {3}" -f $records.Count, $recommendations.Count, $PlaneBudget, $ReportPath)
if ($FailOnRecommendation -and $recommendations.Count -gt 0) { exit 2 }
