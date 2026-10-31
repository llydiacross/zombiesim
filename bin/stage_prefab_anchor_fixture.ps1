param(
    [ValidateSet('Inspect', 'Stage', 'Restore')][string]$Action = 'Inspect',
    [string]$BspPath = '',
    [string]$ContentDirectory = '',
    [string]$EngineMapDirectory = '',
    [string]$LedgerPath = '',
    [switch]$Scaled,
    [switch]$ScaledBench,
    [switch]$Setpieces,
    [switch]$Particles,
    [switch]$MapOnly,
    [switch]$Guards,
    [string]$SetpiecesDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
if (@($Scaled, $ScaledBench, $Setpieces, $Particles, $MapOnly, $Guards).Where({ $_ }).Count -gt 1) {
    throw 'Scaled drum, scaled bench, set-piece, particle, guard and map-only fixtures are separate.'
}
if (-not $BspPath) {
    $BspPath = if ($Setpieces) { Join-Path $root 'generated\prefab_setpieces_20261029\build\zn_dev_prefab_anchor.bsp' }
        else { Join-Path $root 'generated\prefab_anchor_20261029\build\zn_dev_prefab_anchor.bsp' }
}
if (-not $ContentDirectory) { $ContentDirectory = Join-Path $root 'content' }
if (-not $EngineMapDirectory) { $EngineMapDirectory = Join-Path $root '..\..\maps' }
if (-not $LedgerPath) {
    $LedgerPath = if ($Setpieces) { Join-Path $root 'generated\prefab_setpieces_20261029\staging-ledger.json' }
        else { Join-Path $root 'generated\prefab_anchor_20261029\staging-ledger.json' }
}
if (-not $SetpiecesDirectory) { $SetpiecesDirectory = Join-Path $root 'generated\prefab_setpieces_20261029\prefabs' }
$BspPath = [IO.Path]::GetFullPath($BspPath)
$ContentDirectory = [IO.Path]::GetFullPath($ContentDirectory)
$EngineMapDirectory = [IO.Path]::GetFullPath($EngineMapDirectory)
$LedgerPath = [IO.Path]::GetFullPath($LedgerPath)
$mapName = 'zn_dev_prefab_anchor.bsp'
$prefabNames = @(if ($Setpieces) { 'zz_dev_roadblock.json'; 'zz_dev_transition_gate.json' }
    elseif (-not $MapOnly) { 'zz_dev_anchor_fixture.json' })
$mapContent = Join-Path $ContentDirectory "maps\$mapName"
$mapEngine = Join-Path $EngineMapDirectory $mapName
$destinations = @($mapContent, $mapEngine) + @($prefabNames | ForEach-Object { Join-Path $ContentDirectory "data_static\prefabs\$_" })
$json = '{"schemaVersion":1,"id":"zz_dev_anchor_fixture","name":"Temporary anchor fixture","description":"Isolated preview test only","tags":["road","motorway"],"props":[{"model":"models/props_c17/oildrum001.mdl","position":{"x":0,"y":0,"z":-64},"angles":{"p":0,"y":0,"r":0},"skin":0,"scale":1,"movable":false},{"model":"models/props_c17/oildrum001.mdl","position":{"x":64,"y":0,"z":-64},"angles":{"p":0,"y":0,"r":0},"skin":0,"scale":1,"movable":true}]}'
if ($Scaled) {
    $json = $json.Replace('"scale":1,"movable":false', '"scale":0.5,"movable":false').
        Replace('"scale":1,"movable":true', '"scale":2,"movable":true')
}
if ($ScaledBench) {
    $json = '{"schemaVersion":1,"id":"zz_dev_anchor_fixture","name":"Temporary scaled bench fixture","description":"Isolated preview test only","tags":["road","motorway"],"props":[{"model":"models/props_c17/bench01a.mdl","position":{"x":0,"y":0,"z":-64},"angles":{"p":0,"y":0,"r":0},"skin":0,"scale":1.4,"movable":true}]}'
}
if ($Particles) {
    $json = '{"schemaVersion":1,"id":"zz_dev_anchor_fixture","name":"Temporary particle anchor fixture","description":"Isolated preview test only","tags":["road","motorway"],"props":[],"particles":[{"particleId":"continuous","effect":"steam","position":{"x":0,"y":0,"z":-48},"angles":{"p":0,"y":0,"r":0},"mode":"continuous","overlap":true},{"particleId":"burst_overlap","effect":"steam","position":{"x":64,"y":0,"z":-48},"angles":{"p":0,"y":0,"r":0},"mode":"triggered","overlap":true},{"particleId":"burst_restart","effect":"steam","position":{"x":-64,"y":0,"z":-48},"angles":{"p":0,"y":0,"r":0},"mode":"triggered","overlap":false}]}'
}
if ($Guards) {
    $json = '{"schemaVersion":1,"id":"zz_dev_anchor_fixture","name":"Temporary guard anchor fixture","description":"Isolated preview test only","tags":["guardFixture"],"props":[{"propId":"p_drum","model":"models/props_c17/oildrum001.mdl","position":{"x":-64,"y":0,"z":0},"angles":{"p":0,"y":0,"r":0},"skin":0,"scale":1,"movable":false,"lootMode":"off"}],"guards":[{"guardId":"guard_1","name":"Anchor fixture","model":"models/player/group01/male_03.mdl","position":{"x":32,"y":16,"z":4},"angles":{"p":0,"y":90,"r":0},"idle":"idle_all_01","weapon":"smg","range":1200,"shirt":"catalogue_fabric_shirt_blue_plain","pants":"catalogue_fabric_pants_black_plain","damage":25,"fireInterval":0.075,"spread":0.04}]}'
}
$encoding = [Text.UTF8Encoding]::new($false)
$prefabBytes = $encoding.GetBytes($json)
$sha = [Security.Cryptography.SHA256]::Create()
try { $prefabHash = [BitConverter]::ToString($sha.ComputeHash($prefabBytes)).Replace('-', '') }
finally { $sha.Dispose() }
function Write-NewFixtureFile([string]$Path, [byte[]]$Bytes) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length) }
    finally { $stream.Dispose() }
}

if ($Action -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) { throw "Fixture staging ledger is missing: $LedgerPath" }
    $ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
    if ($ledger.schemaVersion -ne 1 -or $ledger.profile -ne 'preview' -or @($ledger.files).Count -ne $destinations.Count) {
        throw 'Fixture staging ledger is invalid.'
    }
    foreach ($index in 0..($destinations.Count - 1)) {
        $record = $ledger.files[$index]
        if ([IO.Path]::GetFullPath([string]$record.path) -ine [IO.Path]::GetFullPath($destinations[$index])) {
            throw 'Fixture ledger paths do not match the explicit staging destinations.'
        }
        if ((Test-Path -LiteralPath $record.path) -and
            ((Get-FileHash -LiteralPath $record.path -Algorithm SHA256).Hash -cne [string]$record.sha256)) {
            throw "Fixture file changed since staging; preserve it and inspect: $($record.path)"
        }
    }
    foreach ($record in $ledger.files) {
        if (Test-Path -LiteralPath $record.path -PathType Leaf) { Remove-Item -LiteralPath $record.path }
    }
    foreach ($record in $ledger.files) {
        if (Test-Path -LiteralPath $record.path) { throw "Fixture cleanup failed: $($record.path)" }
    }
    Remove-Item -LiteralPath $LedgerPath
    Write-Output 'Fixture files removed and verified absent.'
    return
}

if (-not (Test-Path -LiteralPath $BspPath -PathType Leaf)) { throw "Fixture BSP is missing: $BspPath" }
if (Test-Path -LiteralPath $LedgerPath) { throw "A fixture staging ledger already exists: $LedgerPath" }
foreach ($destination in $destinations) {
    if (Test-Path -LiteralPath $destination) { throw "Fixture destination already exists; preserve it: $destination" }
}
$mapHash = (Get-FileHash -LiteralPath $BspPath -Algorithm SHA256).Hash
$prefabRecords = @()
if ($Setpieces) {
    foreach ($name in $prefabNames) {
        $source = Join-Path $SetpiecesDirectory $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Set-piece prefab is missing: $source" }
        & (Join-Path $PSScriptRoot 'export_prefab.ps1') -Id ([IO.Path]::GetFileNameWithoutExtension($name)) `
            -SourceDirectory $SetpiecesDirectory -OutputDirectory (Join-Path $ContentDirectory 'data_static\prefabs') | Out-Null
        $prefabRecords += [ordered]@{
            path = (Join-Path $ContentDirectory "data_static\prefabs\$name")
            sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            source = $source
        }
    }
} elseif (-not $MapOnly) {
    $prefabRecords += [ordered]@{ path = $destinations[2]; sha256 = $prefabHash }
}
if ($Action -eq 'Inspect') {
    Write-Output "Would stage one preview fixture BSP twice and $($prefabNames.Count) temporary prefab(s). BSP SHA-256: $mapHash. No files changed."
    return
}
$ledger = [ordered]@{
    schemaVersion = 1
    profile = 'preview'
    files = @(
        [ordered]@{ path = $mapContent; sha256 = $mapHash },
        [ordered]@{ path = $mapEngine; sha256 = $mapHash }
    ) + @($prefabRecords | ForEach-Object { [ordered]@{ path = $_.path; sha256 = $_.sha256 } })
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $LedgerPath)) | Out-Null
Write-NewFixtureFile $LedgerPath ($encoding.GetBytes((ConvertTo-Json -InputObject $ledger -Depth 6)))
foreach ($destination in $destinations) { [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null }
[IO.File]::Copy($BspPath, $mapContent, $false)
[IO.File]::Copy($BspPath, $mapEngine, $false)
if ($Setpieces) {
    foreach ($record in $prefabRecords) { [IO.File]::Copy($record.source, $record.path, $false) }
} elseif (-not $MapOnly) {
    Write-NewFixtureFile $destinations[2] $prefabBytes
}
foreach ($record in $ledger.files) {
    if ((Get-FileHash -LiteralPath $record.path -Algorithm SHA256).Hash -cne $record.sha256) {
        throw "Fixture staging verification failed; inspect ledger before recovery: $LedgerPath"
    }
}
Write-Output "Staged and hash-verified the isolated preview fixture. Restore with -Action Restore; ledger: $LedgerPath"
