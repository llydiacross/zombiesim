param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [string]$ContentRoot = '',
    [string]$GameRoot = '',
    [string]$LedgerPath = '',
    [switch]$Apply,
    [switch]$Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Apply -and $Cleanup) { throw 'Apply and Cleanup are mutually exclusive.' }
$root = Split-Path -Parent $PSScriptRoot
$build = [IO.Path]::GetFullPath($BuildDirectory)
$generated = [IO.Path]::GetFullPath((Join-Path $root 'generated')).TrimEnd('\') + '\'
if (-not $build.StartsWith($generated, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The road reference build must be an isolated generated subdirectory.'
}
if (-not $ContentRoot) { $ContentRoot = Join-Path $root 'content' }
if (-not $GameRoot) { $GameRoot = Join-Path $root '..\..' }
if (-not $LedgerPath) { $LedgerPath = Join-Path $build 'staging-ledger.json' }
$ContentRoot = [IO.Path]::GetFullPath($ContentRoot)
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$LedgerPath = [IO.Path]::GetFullPath($LedgerPath)
if ($ContentRoot -ieq $GameRoot) { throw 'Content and game destinations must be different.' }
$sourceRoot = Join-Path $build 'game'
$reportPath = Join-Path $build 'report.json'
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Compiled road report is missing: $reportPath" }
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if ($report.model -cnotmatch '^models/zombiesim/prefab_tile_preview/road_[a-f0-9]{12}_v1\.mdl$') {
    throw 'The road report contains an unexpected model path.'
}
$road = Join-Path $root 'tiletemplates\roads\tile_road.vmf'
if ((Get-FileHash -LiteralPath $road -Algorithm SHA256).Hash.ToLowerInvariant() -cne $report.sourceSha256) {
    throw 'The authored road changed after compilation; rebuild the isolated preview.'
}
$modelBase = $report.model.Substring(0, $report.model.Length - 4)
$paths = [Collections.Generic.List[string]]::new()
foreach ($extension in @('.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx')) {
    $relative = ($modelBase + $extension).Replace('/', '\')
    if ($extension -eq '.dx80.vtx' -and -not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf)) { continue }
    $paths.Add($relative)
}
foreach ($material in $report.materials) {
    if ($material.material -cnotmatch '^zm_prefab_road_[a-f0-9]{12}_[a-z0-9_]+$') {
        throw 'The road report contains an unexpected material name.'
    }
    $paths.Add("materials\models\zombiesim\prefab_tile_preview\$($material.material).vmt")
}
if ($paths.Count -lt 4) { throw 'The road report has no preview materials.' }
$entries = [Collections.Generic.List[object]]::new()
foreach ($relative in $paths) {
    $source = Join-Path $sourceRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Preview output is missing: $source" }
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    foreach ($destinationRoot in @($ContentRoot, $GameRoot)) {
        $entries.Add([pscustomobject]@{
            relative = $relative; source = $source; destination = (Join-Path $destinationRoot $relative); sha256 = $hash
        })
    }
}

$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Ledger([object]$Value) {
    [IO.File]::WriteAllText($LedgerPath, ($Value | ConvertTo-Json -Depth 8), $utf8)
}
if ($Cleanup) {
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) { throw 'The staging ledger is missing.' }
    $ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
    if ($ledger.state -ne 'staged' -or @($ledger.files).Count -ne $entries.Count) {
        throw 'Only a complete staging ledger can be cleaned automatically.'
    }
    foreach ($entry in $entries) {
        $matches = @($ledger.files | Where-Object { $_.destination -ceq $entry.destination -and $_.sha256 -ceq $entry.sha256 })
        if ($matches.Count -ne 1 -or -not (Test-Path -LiteralPath $entry.destination -PathType Leaf) -or
            (Get-FileHash -LiteralPath $entry.destination -Algorithm SHA256).Hash -cne $entry.sha256) {
            throw "A staged preview file changed or is missing; nothing was removed: $($entry.destination)"
        }
    }
    foreach ($entry in $entries) { Remove-Item -LiteralPath $entry.destination }
    $ledger.state = 'removed'
    Write-Ledger $ledger
    Write-Output "Removed $($entries.Count) unchanged road-reference files from the recorded destinations."
    return
}
if (Test-Path -LiteralPath $LedgerPath) { throw "A staging ledger already exists: $LedgerPath" }
foreach ($entry in $entries) {
    if (Test-Path -LiteralPath $entry.destination) { throw "Preview destination already exists; refusing to overwrite: $($entry.destination)" }
}
if (-not $Apply) {
    Write-Output "Would stage $($entries.Count) road-reference files to content and the game directory; no files changed."
    return
}
$ledger = [pscustomobject]@{ state = 'staging'; sourceSha256 = $report.sourceSha256; files = @($entries) }
Write-Ledger $ledger
try {
    foreach ($entry in $entries) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $entry.destination)) | Out-Null
        [IO.File]::Copy($entry.source, $entry.destination, $false)
        if ((Get-FileHash -LiteralPath $entry.destination -Algorithm SHA256).Hash -cne $entry.sha256) {
            throw "Staged preview hash mismatch: $($entry.destination)"
        }
    }
    $ledger.state = 'staged'
    Write-Ledger $ledger
} catch {
    $ledger.state = 'incomplete'
    Write-Ledger $ledger
    throw
}
Write-Output "Staged and hash-verified $($entries.Count) road-reference files; ledger: $LedgerPath"
