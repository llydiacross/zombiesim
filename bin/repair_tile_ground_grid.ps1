param([string]$WorldProfile = 'preview', [string]$SettingsPath = '', [string[]]$Paths = @(), [switch]$Apply, [switch]$CenterOrigin)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'tile_ground_grid.psm1')
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
$templateDirectory = [IO.Path]::GetFullPath((Join-Path $root $profile.Settings.paths.templateDirectory)).TrimEnd('\')
if ($Paths.Count -eq 0) { $Paths = @(Get-ChildItem -LiteralPath $templateDirectory -Filter '*.vmf' -File -Recurse | ForEach-Object FullName) }
$backupDirectory = Join-Path $root 'generated\tile_ground_grid_repair'
$changes = [System.Collections.Generic.List[object]]::new()
foreach ($path in $Paths) {
    $fullPath = (Resolve-Path -LiteralPath $path).Path
    if (-not $fullPath.StartsWith($templateDirectory + '\', [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($fullPath) -ne '.vmf') { throw "Repair accepts authored tile VMFs only: $fullPath" }
    if ($fullPath -match '(?i)[\\/]terrain[\\/]infill[\\/]') { continue }
    $issues = @(Get-ZMTileGroundGridIssues $fullPath)
    $reference = Get-ZMTileGroundReference $fullPath
    Write-ZMTileGroundGridWarnings $fullPath
    foreach ($issue in $issues) { $changes.Add($issue) }
    if (-not $Apply) { continue }
    $text = [IO.File]::ReadAllText($fullPath)
    $rewritten = $text
    $offset = $null -ne $reference -and $reference.complete -and ([Math]::Abs($reference.centerX) -gt 0.001 -or [Math]::Abs($reference.centerY) -gt 0.001)
    if ($offset) {
        if (-not $CenterOrigin) { throw "Complete ground footprint is offset; review and use -CenterOrigin to preserve roads/props: $fullPath" }
        $rewritten = Move-ZMTileGroundOriginText $rewritten $reference
        $issues = @(Get-ZMTileGroundGridIssues $fullPath -Text $rewritten)
    }
    if (-not $offset -and $issues.Count -eq 0) { continue }
    if (@($issues | Where-Object { -not $_.repairable }).Count -gt 0) { throw "Tile requires manual ground alignment review before repair: $fullPath" }
    $rewritten = Repair-ZMTileGroundGridText $rewritten $issues
    if ($rewritten -ceq $text) { throw "Selected ground repair made no changes: $fullPath" }
    if (@(Get-ZMTileGroundGridIssues $fullPath -Text $rewritten).Count -ne 0) { throw "Proposed source repair remains misaligned: $fullPath" }
    $proposedReference = Get-ZMTileGroundReference $fullPath -Text $rewritten
    if ($offset -and ($null -eq $proposedReference -or -not $proposedReference.complete -or $proposedReference.centerX -ne 0 -or $proposedReference.centerY -ne 0)) { throw "Proposed source centering failed: $fullPath" }
    [IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
    $backup = Join-Path $backupDirectory ([IO.Path]::GetFileNameWithoutExtension($fullPath) + '-' + $hash + '.vmf')
    if (-not (Test-Path -LiteralPath $backup)) { [IO.File]::Copy($fullPath, $backup) }
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -cne $hash) { throw "Ground source backup verification failed: $backup" }
    [IO.File]::WriteAllText($fullPath, $rewritten, [Text.UTF8Encoding]::new($false))
    if (@(Get-ZMTileGroundGridIssues $fullPath).Count -ne 0) { throw "Ground source remains misaligned after repair: $fullPath; backup: $backup" }
    $afterReference = Get-ZMTileGroundReference $fullPath
    if ($offset -and ($null -eq $afterReference -or -not $afterReference.complete -or $afterReference.centerX -ne 0 -or $afterReference.centerY -ne 0)) { throw "Source ground centering verification failed: $fullPath; backup: $backup" }
}
$changes
